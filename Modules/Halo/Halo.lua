-- Stoa: the Halo, the combat state.
-- When combat starts the Grimoire console folds away and the Halo rises
-- around your character: health on the left arc, mana on the right, your
-- spec's signature in the slot at its foot, your target beside it and your
-- cast below. The top of the ring stays open so your name shows through. It fades out again once combat has been calm for a moment.
--
-- The Halo never takes the mouse, so it can't block clicks on the world.
local _, ns = ...
local Stoa = ns.Stoa
local UI = Stoa.UI

local Halo = Stoa:NewModule("Halo", {
	hidePlayerFrame = true,
	hideTargetFrame = true,
	scale = 1,
})

local SIZE = 300
local FADE_IN = 0.2
local FADE_OUT = 0.5
local SIGNATURE_SIZE = 36

-- Signature spells: the one button each spec lives around. The first spell
-- the character knows is shown, so it fills in as you level.
local SIGNATURES = {
	PRIEST = {
		RANGED = { 8092, 589, 585 },   -- Mind Blast, Shadow Word: Pain, Smite
		HEALER = { 17, 2061, 2050 },   -- Power Word: Shield, Flash Heal, Lesser Heal
	},
	PALADIN = {
		MELEE = { 20271, 35395, 20154 }, -- Judgement, Crusader Strike, Seal of Righteousness
		TANK = { 31935, 20925, 20271 },  -- Avenger's Shield, Holy Shield, Judgement
		HEALER = { 20473, 19750, 635 },  -- Holy Shock, Flash of Light, Holy Light
	},
}

local function knows(spellID)
	if IsPlayerSpell and IsPlayerSpell(spellID) then return true end
	return IsSpellKnown and IsSpellKnown(spellID) or false
end

-- Build ---------------------------------------------------------------------

local function arc(parent, side, token)
	local file = UI.MEDIA .. "Textures\\HaloArc" .. side
	local sb = CreateFrame("StatusBar", nil, parent)
	sb:SetSize(SIZE / 2, SIZE)
	sb:SetOrientation("VERTICAL")
	sb:SetStatusBarTexture(file)
	UI.paint(sb, token)
	local track = sb:CreateTexture(nil, "BACKGROUND")
	track:SetAllPoints()
	track:SetTexture(file)
	UI.tint(track, "text", 0.1)
	sb:SetMinMaxValues(0, 1)
	sb:SetValue(1)
	return sb
end

function Halo:Build()
	local frame = CreateFrame("Frame", "StoaHalo", UIParent)
	frame:SetSize(SIZE, SIZE)
	frame:SetPoint("CENTER", UIParent, "CENTER", 0, -60)
	frame:SetScale(self.db.scale)
	frame:SetFrameStrata("LOW")
	frame:EnableMouse(false)
	frame:SetAlpha(0)
	self.frame = frame

	local health = arc(frame, "Left", "health")
	health:SetPoint("LEFT")
	local mana = arc(frame, "Right", "mana")
	mana:SetPoint("RIGHT")
	self.health, self.mana = health, mana

	local healthText = UI.text(frame, "serif", Stoa.typeSize.title, "text", "RIGHT")
	healthText:SetPoint("BOTTOMRIGHT", frame, "BOTTOM", -SIZE * 0.3, 6)
	local manaText = UI.text(frame, "serif", Stoa.typeSize.title, "mana", "LEFT")
	manaText:SetPoint("BOTTOMLEFT", frame, "BOTTOM", SIZE * 0.3, 6)
	self.healthText, self.manaText = healthText, manaText

	self:BuildSignature(frame)
	self:BuildTarget(frame)
	self:BuildCast(frame)

	UI.applyTheme()
	Stoa:RegisterMover("halo", frame, "Halo")
end

function Halo:BuildSignature(frame)
	local slot = CreateFrame("Frame", nil, frame)
	slot:SetSize(SIGNATURE_SIZE + 8, SIGNATURE_SIZE + 8)
	slot:SetPoint("CENTER", frame, "BOTTOM", 0, 8)
	self.signature = slot

	local ring = UI.circle(slot, "BORDER", 0, SIGNATURE_SIZE + 4, "accent")
	ring:SetPoint("CENTER")
	local gap = UI.circle(slot, "BORDER", 1, SIGNATURE_SIZE + 2, "panel")
	gap:SetPoint("CENTER")
	local icon = UI.circle(slot, "ARTWORK", 0, SIGNATURE_SIZE)
	icon:SetPoint("CENTER")
	slot.icon = icon

	local cooldown = CreateFrame("Cooldown", nil, slot, "CooldownFrameTemplate")
	cooldown:SetAllPoints(icon)
	cooldown:SetSwipeTexture(UI.CIRCLE_MASK)
	cooldown:SetDrawEdge(false)
	cooldown:SetHideCountdownNumbers(false)
	slot.cooldown = cooldown
	slot:Hide()
end

-- The target sits beside the Halo's upper left, clear of the nameplates
-- that crowd the space above your head. Like the cast bar it is parented to
-- UIParent, so it stays with you out of combat as well.
function Halo:BuildTarget(frame)
	local target = CreateFrame("Frame", nil, UIParent)
	target:SetFrameStrata("LOW")
	target:SetSize(200, 52)
	target:SetPoint("BOTTOMRIGHT", frame, "LEFT", -28, 36)
	self.target = target

	local name = UI.text(target, "serif", Stoa.typeSize.title, "text", "RIGHT")
	name:SetPoint("TOPRIGHT")
	name:SetWidth(200)
	name:SetWordWrap(false)
	local hp = UI.bar(target, 180, 3, "health")
	hp:SetPoint("TOPRIGHT", name, "BOTTOMRIGHT", 0, -5)
	-- Hostile targets get a word as well as a colour.
	local cue = UI.caption(target, "")
	cue:SetPoint("TOPRIGHT", hp, "BOTTOMRIGHT", 0, -5)
	local health = UI.text(target, "sans", Stoa.typeSize.body, "muted", "LEFT")
	health:SetPoint("TOPLEFT", hp, "BOTTOMLEFT", 0, -5)
	-- Threat, in words: tanks hear when they are losing it, everyone else
	-- when they are taking it.
	local threat = UI.caption(target, "")
	threat:SetPoint("TOPRIGHT", cue, "BOTTOMRIGHT", 0, -4)
	target.name, target.hp, target.cue, target.health = name, hp, cue, health
	target.threat = threat
	target:Hide()
end

-- The cast bar is parented to UIParent rather than the Halo, so it shows for
-- casts out of combat too, such as the pull, while the Halo is faded out.
function Halo:BuildCast(frame)
	local cast = UI.bar(UIParent, 200, 3, "accent")
	cast:SetFrameStrata("LOW")
	cast:SetPoint("TOP", frame, "BOTTOM", 0, -40)
	local spell = UI.text(cast, "italic", Stoa.typeSize.label, "text", "CENTER")
	spell:SetPoint("BOTTOM", cast, "TOP", 0, 4)
	cast.spell = spell
	cast:Hide()
	self.cast = cast
end

-- Updates -------------------------------------------------------------------

function Halo:UpdateHealth()
	UI.setUnitBar(self.health, "player", "health")
	self.healthText:SetText(UnitHealth("player"))
end

function Halo:UpdatePower()
	UI.setUnitBar(self.mana, "player", "power")
	self.manaText:SetText(UnitPower("player"))
end

function Halo:UpdateSignature()
	local slot = self.signature
	local role = Stoa:GetRole()
	local _, classFile = UnitClass("player")
	local list = SIGNATURES[classFile] and SIGNATURES[classFile][role] or {}

	slot.spellID = nil
	for _, spellID in ipairs(list) do
		if knows(spellID) then
			slot.spellID = spellID
			break
		end
	end

	-- Until the spec's spell is learned the slot stays empty rather than
	-- showing a blank ring.
	if slot.spellID then
		slot.icon:SetTexture(C_Spell.GetSpellTexture(slot.spellID))
		slot:Show()
		self:UpdateCooldown()
	else
		slot.cooldown:Clear()
		slot:Hide()
	end
end

-- Cooldown values may be secret in combat. Newer clients hand out a duration
-- object the swipe can take directly; otherwise plain numbers are used, and
-- a refused value just leaves the swipe empty.
function Halo:UpdateCooldown()
	local slot = self.signature
	if not slot.spellID then return end
	local cooldown = slot.cooldown
	if C_Spell.GetSpellCooldownDuration and cooldown.SetCooldownFromDurationObject then
		local ok = pcall(function()
			cooldown:SetCooldownFromDurationObject(C_Spell.GetSpellCooldownDuration(slot.spellID))
		end)
		if ok then return end
	end
	pcall(function()
		local info = C_Spell.GetSpellCooldown(slot.spellID)
		if info then cooldown:SetCooldown(info.startTime, info.duration) end
	end)
end

function Halo:UpdateTarget()
	local target = self.target
	if not UnitExists("target") then
		target:Hide()
		return
	end
	target.name:SetText(UnitName("target"))
	target.name:SetTextColor(UI.classColor("target"))
	UI.setUnitBar(target.hp, "target", "health")
	target.health:SetText(UnitHealth("target"))

	-- A dead target says so in words and steps back, rather than reading as
	-- a hostile at zero.
	local dead = UnitIsDead("target")
	if Stoa:IsSecret(dead) then dead = false end
	local hostile = not dead and UnitCanAttack("player", "target")
	if Stoa:IsSecret(hostile) then hostile = false end
	target.hp:SetStatusBarColor(Stoa:Color(hostile and "danger" or "health"))
	target.cue:SetText(dead and "DEAD" or hostile and "HOSTILE" or "")
	target.hp:SetShown(not dead)
	target.health:SetShown(not dead)
	target:SetAlpha(dead and 0.6 or 1)
	if dead then
		target.threat:SetText("")
	else
		self:UpdateThreat()
	end
	target:Show()
end

local THREAT_WORDS = {
	TANK = { [0] = "NO AGGRO", [1] = "NO AGGRO", [2] = "LOSING AGGRO", [3] = "HOLDING AGGRO" },
	OTHER = { [2] = "NEAR AGGRO", [3] = "AGGRO ON YOU" },
}

function Halo:UpdateThreat()
	local threat = self.target.threat
	local status = UnitExists("target") and UnitThreatSituation("player", "target")
	if not status or Stoa:IsSecret(status) then
		threat:SetText("")
		return
	end
	local isTank = Stoa:GetRole() == "TANK"
	local words = isTank and THREAT_WORDS.TANK or THREAT_WORDS.OTHER
	threat:SetText(words[status] or "")
	-- Holding aggro as a tank is the calm case; everything else is a warning.
	local calm = isTank and status == 3
	threat:SetTextColor(Stoa:Color(calm and "muted" or "danger"))
end

-- Cast bar. Plain times drive it with GetTime; secret times use the client's
-- duration object when there is one.
function Halo:StartCast(channel)
	local cast = self.cast
	local name, _, _, startMS, endMS = (channel and UnitChannelInfo or UnitCastingInfo)("player")
	if not name then
		self:StopCast()
		return
	end
	cast.spell:SetText(name)
	cast:SetScript("OnUpdate", nil)

	if not Stoa:IsSecret(startMS) and not Stoa:IsSecret(endMS) then
		cast:SetMinMaxValues(startMS / 1000, endMS / 1000)
		cast:SetScript("OnUpdate", function(bar)
			local now = GetTime()
			if channel then
				bar:SetValue(endMS / 1000 - (now - startMS / 1000))
			else
				bar:SetValue(now)
			end
		end)
	elseif cast.SetTimerDuration then
		local getDuration = channel and UnitChannelDuration or UnitCastingDuration
		if getDuration then pcall(cast.SetTimerDuration, cast, getDuration("player")) end
	end
	cast:Show()
end

function Halo:StopCast()
	self.cast:SetScript("OnUpdate", nil)
	self.cast:Hide()
end

-- Showing and hiding --------------------------------------------------------

function Halo:SetShown(shown)
	UI.fade(self.frame, shown and 1 or 0, shown and FADE_IN or FADE_OUT)
end

-- Blizzard frames that repeat what the seal and Halo show.
local function hideBlizzard(frames)
	return function()
		for _, blizzard in ipairs(frames) do
			if blizzard then blizzard:SetParent(UI.hidden) end
		end
	end
end

-- Lifecycle -----------------------------------------------------------------

function Halo:OnEnable()
	self:Build()

	self:UpdateHealth()
	self:UpdatePower()
	self:UpdateSignature()
	self:UpdateTarget()
	self.frame:SetAlpha(Stoa:GetState() == Stoa.STATE_COMBAT and 1 or 0)

	if self.db.hidePlayerFrame then
		Stoa:AfterCombat(function()
			xpcall(hideBlizzard({ PlayerFrame, PlayerCastingBarFrame }), geterrorhandler())
		end)
	end
	if self.db.hideTargetFrame then
		Stoa:AfterCombat(function()
			xpcall(hideBlizzard({ TargetFrame, FocusFrame }), geterrorhandler())
		end)
	end

	Stoa:On("STOA_STATE_CHANGED", function(state)
		self:SetShown(state == Stoa.STATE_COMBAT)
	end)
	Stoa:On("STOA_ROLE_CHANGED", function() self:UpdateSignature() end)
	Stoa:On("PLAYER_ENTERING_WORLD", function()
		self:UpdateHealth()
		self:UpdatePower()
		self:UpdateSignature()
	end)
	Stoa:On("SPELLS_CHANGED", function() self:UpdateSignature() end)
	Stoa:On("SPELL_UPDATE_COOLDOWN", function() self:UpdateCooldown() end)

	Stoa:On("UNIT_HEALTH", function(unit)
		if unit == "player" then self:UpdateHealth() end
		if unit == "target" then self:UpdateTarget() end
	end)
	Stoa:On("UNIT_MAXHEALTH", function(unit)
		if unit == "player" then self:UpdateHealth() end
	end)
	Stoa:On("UNIT_POWER_UPDATE", function(unit)
		if unit == "player" then self:UpdatePower() end
	end)
	Stoa:On("UNIT_MAXPOWER", function(unit)
		if unit == "player" then self:UpdatePower() end
	end)
	Stoa:On("PLAYER_TARGET_CHANGED", function() self:UpdateTarget() end)
	Stoa:On("UNIT_THREAT_SITUATION_UPDATE", function() self:UpdateThreat() end)
	Stoa:On("UNIT_THREAT_LIST_UPDATE", function(unit)
		if unit == "target" then self:UpdateThreat() end
	end)

	local function onCast(channel)
		return function(unit)
			if unit == "player" then self:StartCast(channel) end
		end
	end
	local function onStop(unit)
		if unit == "player" then self:StopCast() end
	end
	Stoa:On("UNIT_SPELLCAST_START", onCast(false))
	Stoa:On("UNIT_SPELLCAST_DELAYED", onCast(false))
	Stoa:On("UNIT_SPELLCAST_CHANNEL_START", onCast(true))
	Stoa:On("UNIT_SPELLCAST_CHANNEL_UPDATE", onCast(true))
	Stoa:On("UNIT_SPELLCAST_STOP", onStop)
	Stoa:On("UNIT_SPELLCAST_FAILED", onStop)
	Stoa:On("UNIT_SPELLCAST_INTERRUPTED", onStop)
	Stoa:On("UNIT_SPELLCAST_CHANNEL_STOP", onStop)
end
