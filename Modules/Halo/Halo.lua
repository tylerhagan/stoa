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
	-- The target as a strip: no panel, a small portrait, words over the
	-- world, level with the Halo. Off brings back the solid plaque.
	targetStrip = false,
	hidePlayerFrame = true,
	hideTargetFrame = true,
	scale = 1,
	-- Quiet mana play: the five-second rule and regen ticks, the cost of
	-- the spell you are casting, and a druid's mana while shapeshifted.
	manaRule = true,
	castCost = true,
	formMana = true,
	-- Out of combat: health and mana stay as two faint arcs (for players
	-- with no console to read them from), and the target plaque rests faint.
	restArcs = false,
	restFade = false,
})

local REST_ARCS = 0.4
local REST_FADE = 0.45

local SIZE = 300
local FADE_IN = 0.2
local FADE_OUT = 0.5
local SIGNATURE_SIZE = 36
local AURA_SIZE = 22
local AURA_COUNT = 8

-- Signature spells: the one cooldown each spec lives around. The first
-- spell the character knows is shown; only spells with a cooldown are
-- listed, so the slot stays empty until there's a timer worth watching.
local SIGNATURES = {
	PRIEST = {
		RANGED = { 8092 },              -- Mind Blast
		HEALER = { 1240721, 17 },       -- Penance, Power Word: Shield
	},
	PALADIN = {
		MELEE = { 679, 20271 },         -- Holy Strike, Judgement
		TANK = { 1311015, 679, 20271 }, -- Templar's Bulwark, Holy Strike, Judgement
		HEALER = { 20473, 20216, 633 }, -- Holy Shock, Divine Favor, Lay on Hands
	},
	DRUID = {
		TANK = { 417141, 5229 },        -- Berserk, Enrage
		MELEE = { 417141, 5217 },       -- Berserk, Tiger's Fury
		RANGED = { 29166 },             -- Innervate
		HEALER = { 18562, 17116 },      -- Swiftmend, Nature's Swiftness
	},
	-- Mage picks by talent tree (Mage.lua); these are for before it can.
	MAGE = {
		RANGED = { 12042, 11129, 11426, 2136 }, -- Arcane Power, Combustion, Ice Barrier, Fire Blast
	},
	-- Classes without a signature of their own: one cooldown each.
	WARRIOR = {
		MELEE = { 12294, 23881, 1680 }, -- Mortal Strike, Bloodthirst, Whirlwind
		TANK = { 23922, 6572, 2565 },   -- Shield Slam, Revenge, Shield Block
	},
	ROGUE = {
		MELEE = { 13750, 13877, 14177, 5277 }, -- Adrenaline Rush, Blade Flurry, Cold Blood, Evasion
	},
	HUNTER = {
		RANGED = { 19434, 3044 },       -- Aimed Shot, Arcane Shot
		MELEE = { 2973, 3044 },         -- Raptor Strike, Arcane Shot
	},
	WARLOCK = {
		RANGED = { 17962, 17877, 6789 }, -- Conflagrate, Shadowburn, Death Coil
	},
	SHAMAN = {
		RANGED = { 16166, 8042 },       -- Elemental Mastery, Earth Shock
		MELEE = { 17364, 8042 },        -- Stormstrike, Earth Shock
		HEALER = { 16188, 16190 },      -- Nature's Swiftness, Mana Tide Totem
		TANK = { 8042 },                -- Earth Shock
	},
}

-- Self-buffs each class keeps up, by role. A reminder shows as a word
-- when the buff is missing (and the spell is known); seals only matter in
-- a fight, since they don't last between pulls. Matched by name, with
-- spell IDs only to check the spell is learned.
local REMINDERS = {
	PALADIN = {
		{ word = "NO AURA", suffix = " Aura", spell = 465 },             -- Devotion Aura
		{ word = "NO SEAL", prefix = "Seal of ", combat = true, show = true },
		{ word = "NO FURY", name = "Righteous Fury", spell = 25780, roles = { TANK = true } },
	},
	PRIEST = {
		{ word = "NO INNER FIRE", name = "Inner Fire", spell = 588 },
		{ word = "NO SHADOWFORM", name = "Shadowform", spell = 15473, roles = { RANGED = true } },
	},
	DRUID = {
		{ word = "NO MARK", name = "Mark of the Wild", spell = 1126 },
	},
	MAGE = {
		{ word = "NO ARMOR", suffix = " Armor", spell = 168 },           -- Frost, Ice, Mage or Molten Armor
		{ word = "NO INTELLECT", name = "Arcane Intellect", spell = 1459 },
	},
}

-- Channels whose ticks are worth seeing, by spell name: Mind Flay does
-- most of its damage on the last of three, so it shouldn't be clipped.
local CHANNEL_TICKS = {}
local function addTicks(spellID, count)
	local name = C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(spellID)
	if name then CHANNEL_TICKS[name] = count end
end

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
	-- A dark track, so the arc reads over snow and bright sky as well as
	-- over dark ground.
	UI.tint(track, "panel", 0.55)
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
	-- The numbers are what you read mid-fight, so they get a fine outline.
	Stoa:SetFont(healthText, "serif", Stoa.typeSize.title, "OUTLINE")
	Stoa:SetFont(manaText, "serif", Stoa.typeSize.title, "OUTLINE")
	self.healthText, self.manaText = healthText, manaText
	self:BuildManaPlay(frame, mana, manaText)

	self:BuildSignature(frame)
	self:BuildTarget(frame)
	self:BuildCast(frame)

	UI.applyTheme()
	Stoa:RegisterMover("halo", frame, "Halo")

	-- Everything here floats over the world, so its words are made legible
	-- over snow and bright sky.
	local function shade(region)
		for _, child in ipairs({ region:GetRegions() }) do
			if child.IsObjectType and child:IsObjectType("FontString") then UI.legible(child) end
		end
	end
	for _, region in ipairs({ frame, self.target, self.cast }) do shade(region) end
end

-- Mana play on the right arc (shared with the console, see Power.dress).
-- The arc is a half circle that fills upwards, so a fraction along it maps
-- to a height, and the dot sits on the circle at that height. A druid's
-- hidden mana gets a slim bar and number under the power number.
local ARC_RADIUS = SIZE / 2 - 8

function Halo:BuildManaPlay(frame, arcBar, manaText)
	local form = UI.bar(frame, 70, 2, "mana")
	form:SetPoint("TOPLEFT", manaText, "BOTTOMLEFT", 0, -4)
	local number = UI.caption(frame, "")
	number:SetPoint("TOPLEFT", form, "BOTTOMLEFT", 0, -3)
	form:Hide()
	local db = self.db
	self.manaPlay = Stoa.Power.dress(arcBar, {
		texture = UI.MEDIA .. "Textures\\HaloArcRight",
		enabled = function(key) return db[key] end,
		place = function(tex, f)
			local y = f * SIZE - SIZE / 2
			local x = math.sqrt(math.max(ARC_RADIUS * ARC_RADIUS - y * y, 0))
			tex:ClearAllPoints()
			tex:SetPoint("CENTER", arcBar, "LEFT", x, y)
		end,
		shade = function(tex, from, to)
			tex:ClearAllPoints()
			tex:SetPoint("BOTTOMLEFT", arcBar, "BOTTOMLEFT", 0, from * SIZE)
			tex:SetPoint("TOPRIGHT", arcBar, "BOTTOMRIGHT", 0, to * SIZE)
			-- Crop the arc's art to the same band so the shade keeps its curve.
			tex:SetTexCoord(0, 1, 1 - to, 1 - from)
		end,
		form = {
			bar = form,
			show = function(current) number:SetText(current) number:Show() end,
			hide = function() number:Hide() end,
		},
	})
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
	-- Spell icons carry a square frame of their own. Cropping into the art
	-- before the circle mask fills the circle edge to edge, like CSS
	-- object-fit: cover.
	local icon = UI.circle(slot, "ARTWORK", 0, SIGNATURE_SIZE)
	icon:SetPoint("CENTER")
	icon:SetTexCoord(0.1, 0.9, 0.1, 0.9)
	slot.icon = icon
	-- Painted: a leather and brass ring instead of the accent line.
	if UI.ornate() then
		ring:Hide()
		gap:Hide()
		local _, brass = UI.coinFrame(slot, SIGNATURE_SIZE)
		UI.tint(brass, "accent")
	end

	local cooldown = CreateFrame("Cooldown", nil, slot, "CooldownFrameTemplate")
	cooldown:SetAllPoints(icon)
	cooldown:SetSwipeTexture(UI.CIRCLE_MASK)
	cooldown:SetDrawEdge(false)
	cooldown:SetDrawBling(false)
	if cooldown.SetUseCircularEdge then cooldown:SetUseCircularEdge(true) end
	cooldown:SetHideCountdownNumbers(false)
	slot.cooldown = cooldown
	slot:Hide()
end

-- The target sits at the Halo's upper right, opposite the tank watch, on a
-- plaque with its portrait coin: level and kind, name and health, an
-- engraved bar, the hostile and threat words, and a row of auras under it.
-- Elite and rare targets get a doubled gold or a silver line and the word. Like the cast bar it is parented to UIParent, so
-- it stays with you out of combat as well. It's a secure unit button, so
-- right click opens the unit menu (focus, invite, inspect, trade) like
-- Blizzard's target frame.
local TARGET_WIDTH = 294
local TARGET_PAD = 12
-- Room on the left for the half of the coin inside the plaque.
local TARGET_COIN_SPACE = UI.PLAQUE_COIN_SPACE

-- Out of combat the plaque rests just above the console on the mana side,
-- beside the bars you read there; in a fight it
-- moves to the Halo's upper right. A spot set with the movers wins.
local TARGET_REST_Y = 14

-- The aura row hangs under the plaque at the Halo, and sits on top of it
-- while it rests on the console, where under it would run over the gold
-- edge. Out of combat only: the plaque is secure.
function Halo:PlaceTargetAuras()
	local icons = self.target and self.target.auras
	if not (icons and icons[1]) or InCombatLockdown() then return end
	icons[1]:ClearAllPoints()
	if self.targetResting then
		icons[1]:SetPoint("BOTTOMLEFT", self.target, "TOPLEFT", TARGET_COIN_SPACE, 6)
	elseif self.db.targetStrip then
		-- Without the panel the row follows the bar, leaving one line for
		-- the threat and KICK words between them.
		icons[1]:SetPoint("TOPLEFT", self.target.hp, "BOTTOMLEFT", 0, -20)
	else
		icons[1]:SetPoint("TOPLEFT", self.target, "BOTTOMLEFT", TARGET_COIN_SPACE, -6)
	end
	icons.placed = true
end

function Halo:PlaceTarget()
	local target, frame = self.target, self.frame
	if not target or InCombatLockdown() or Stoa:HasSavedPosition("target") then return end
	local console = Stoa.modules.Grimoire
	local edge = console and console.enabled and console.frame
	target:ClearAllPoints()
	-- In a group the cards sit under the Halo, over the resting spot, so
	-- the plaque keeps its Halo spot there in and out of combat.
	-- The slim console keeps that spot for the action bars.
	if edge and not console.db.slim and Stoa:GetState() == Stoa.STATE_WORLD and not IsInGroup() then
		-- Pinned to the screen where the open console's top edge sits, never
		-- to the console itself: it folds in a fight, and a secure frame
		-- anchored to it would make that fold a blocked action.
		local gap = 150 * (console.ART_SCALE or 0.556) + 22
		target:SetPoint("BOTTOMLEFT", UIParent, "BOTTOM", gap, console:OpenHeight() + TARGET_REST_Y)
		self.targetResting = true
	elseif self.db.targetStrip then
		-- Level with the Halo, mirroring the party strips on its left.
		target:SetPoint("LEFT", frame, "RIGHT", 52 - UI.PLAQUE_BARE_INSET, -6)
		self.targetResting = false
	else
		target:SetPoint("BOTTOMLEFT", frame, "RIGHT", 52, 36)
		self.targetResting = false
	end
	self:PlaceTargetAuras()
end

function Halo:BuildTarget(frame)
	local target = CreateFrame("Button", "StoaTarget", UIParent, "SecureUnitButtonTemplate")
	target:SetFrameStrata("LOW")
	target:SetSize(TARGET_WIDTH, 84)
	-- Over your head it fought with the game's own nameplate.
	target:SetPoint("BOTTOMLEFT", frame, "RIGHT", 52, 36)
	target:SetAttribute("unit", "target")
	target:SetAttribute("type1", "target")
	target:SetAttribute("type2", "togglemenu")
	target:RegisterForClicks("AnyUp")
	target:SetScript("OnEnter", function(button)
		GameTooltip_SetDefaultAnchor(GameTooltip, button)
		GameTooltip:SetUnit("target")
		button:SetAlpha(self:TargetAlpha())
	end)
	target:SetScript("OnLeave", function(button)
		GameTooltip_Hide()
		-- The mouse still counts as over the plaque during this script.
		C_Timer.After(0, function() button:SetAlpha(self:TargetAlpha()) end)
	end)
	-- Any target, in or out of combat. A dead one stays, dimmed and saying
	-- DEAD, so the plaque always matches what you have targeted.
	RegisterStateDriver(target, "visibility", "[@target,exists] show; hide")
	self.target = target
	Stoa:RegisterMover("target", target, "Target plaque", {
		default = function() self:PlaceTarget() end,
	})
	self:PlaceTarget()
	for _, event in ipairs({ "STOA_STATE_CHANGED", "PLAYER_ENTERING_WORLD", "GROUP_ROSTER_UPDATE" }) do
		Stoa:On(event, function()
			if not InCombatLockdown() then self:PlaceTarget() end
		end)
	end
	Stoa:On("PLAYER_REGEN_ENABLED", function() self:PlaceTarget() end)

	-- A plaque like the tank watch opposite: the coin faces the Halo.
	local plaque = UI.plaque(target, "LEFT")
	target.plaque = plaque
	local left = TARGET_COIN_SPACE
	local caption = UI.caption(target, "")
	caption:SetPoint("TOPLEFT", left, -TARGET_PAD)
	-- Hostile targets get a word as well as a colour.
	local cue = UI.caption(target, "")
	cue:SetPoint("TOPRIGHT", -TARGET_PAD, -TARGET_PAD)
	-- One step below title size, so most creature names fit whole.
	local name = UI.text(target, "serif", Stoa.typeSize.name, "text", "LEFT")
	name:SetPoint("TOPLEFT", caption, "BOTTOMLEFT", 0, -4)
	name:SetWidth(TARGET_WIDTH - left - TARGET_PAD - 44)
	name:SetWordWrap(false)
	local health = UI.text(target, "serif", Stoa.typeSize.name, "text", "RIGHT")
	health:SetPoint("TOPRIGHT", cue, "BOTTOMRIGHT", 0, -4)
	local barWidth = TARGET_WIDTH - left - TARGET_PAD
	local hp = UI.bar(target, barWidth, 7, "health")
	hp:SetPoint("TOPLEFT", name, "BOTTOMLEFT", 0, -5)
	UI.engrave(hp, barWidth)
	-- Threat, in words: tanks hear when they are losing it, everyone else
	-- when they are taking it.
	local threat = UI.caption(target, "")
	threat:SetPoint("TOPRIGHT", hp, "BOTTOMRIGHT", 0, -6)
	-- KICK, when the target is casting something you can interrupt (Kit.lua).
	local kick = UI.text(target, "sans", Stoa.typeSize.label, "danger", "LEFT")
	kick:SetPoint("TOPLEFT", hp, "BOTTOMLEFT", 0, -6)
	kick:Hide()
	target.kick = kick
	target.name, target.hp, target.cue, target.health = name, hp, cue, health
	-- On a friend: your buffs on them as the party cards' tags.
	target.pips = UI.pipRow(target, hp, 5)
	target.threat, target.caption = threat, caption
	if self.db.targetStrip then
		plaque:SetBare(true)
		for _, fs in ipairs({ caption, cue, name, health, threat, kick }) do UI.legible(fs) end
	end

	-- Auras: on a friend, their buffs, yours first; on an enemy, the
	-- debuffs you put there. Rounded icons with a sweep for time left.
	target.auras = {}
	local mask = UI.MEDIA .. "Textures\\ButtonMask"
	for i = 1, AURA_COUNT do
		local icon = CreateFrame("Frame", nil, target)
		icon:SetSize(AURA_SIZE, AURA_SIZE)
		if i > 1 then icon:SetPoint("LEFT", target.auras[i - 1], "RIGHT", 4, 0) end
		local tex = icon:CreateTexture(nil, "ARTWORK")
		tex:SetAllPoints()
		tex:SetTexCoord(0.07, 0.93, 0.07, 0.93)
		local m = icon:CreateMaskTexture()
		m:SetAllPoints()
		m:SetTexture(mask, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
		tex:AddMaskTexture(m)
		icon.texture = tex
		local cooldown = CreateFrame("Cooldown", nil, icon, "CooldownFrameTemplate")
		cooldown:SetAllPoints()
		cooldown:SetSwipeTexture(mask)
		cooldown:SetDrawEdge(false)
		cooldown:SetDrawBling(false)
		cooldown:SetHideCountdownNumbers(true)
		cooldown:SetReverse(true)
		icon.cooldown = cooldown
		local count = UI.text(icon, "sans", Stoa.typeSize.caption, "text", "RIGHT")
		count:SetPoint("BOTTOMRIGHT", -1, 1)
		UI.legible(count)
		icon.count = count
		-- Hover for the aura's tooltip, as on the game's own buff icons.
		icon:EnableMouse(true)
		icon:SetScript("OnEnter", function(self)
			if not (self.auraFilter and self.auraIndex) then return end
			GameTooltip_SetDefaultAnchor(GameTooltip, self)
			local shown = false
			if self.auraInstanceID and GameTooltip.SetUnitBuffByAuraInstanceID then
				local by = self.auraFilter:find("HARMFUL") and GameTooltip.SetUnitDebuffByAuraInstanceID or GameTooltip.SetUnitBuffByAuraInstanceID
				shown = pcall(by, GameTooltip, "target", self.auraInstanceID)
			end
			if not shown then pcall(GameTooltip.SetUnitAura, GameTooltip, "target", self.auraIndex, self.auraFilter) end
			GameTooltip:Show()
		end)
		icon:SetScript("OnLeave", GameTooltip_Hide)
		icon:Hide()
		target.auras[i] = icon
	end
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
	-- Tick marks for channels whose ticks matter. The bar drains towards
	-- the left, so each tick lands where the fill edge will be; the last
	-- tick, at the left end, gets a notch of its own.
	cast.ticks = {}
	for i = 1, 2 do
		local tick = cast:CreateTexture(nil, "OVERLAY")
		tick:SetSize(1, 9)
		UI.paint(tick, "text", 0.9)
		tick:Hide()
		cast.ticks[i] = tick
	end
	local notch = cast:CreateTexture(nil, "OVERLAY")
	notch:SetSize(3, 11)
	notch:SetPoint("CENTER", cast, "LEFT", 0, 0)
	UI.paint(notch, "accent")
	notch:Hide()
	cast.notch = notch
	cast:Hide()
	self.cast = cast
	Stoa:RegisterMover("cast", cast, "Cast bar")

	-- Missing self-buffs, and your seal, under the cast bar.
	local reminders = UI.caption(frame, "")
	reminders:SetPoint("TOP", frame, "BOTTOM", 0, -50)
	self.reminders = reminders
end

-- Updates -------------------------------------------------------------------

function Halo:UpdateHealth()
	UI.setUnitBar(self.health, "player", "health")
	if self.rest then UI.setUnitBar(self.rest.health, "player", "health") end
	self.healthText:SetText(UnitHealth("player"))
end

-- The right arc is whatever your power is: mana in its own colour, energy
-- pale gold, rage bone, so a druid's form change reads at a glance.
local POWER_TOKENS = { [1] = "text", [3] = "accent" }

function Halo:UpdatePower()
	UI.setUnitBar(self.mana, "player", "power")
	if self.rest then UI.setUnitBar(self.rest.mana, "player", "power") end
	self.manaText:SetText(UnitPower("player"))
	local kind = UnitPowerType and Stoa:PlainNumber((UnitPowerType("player")))
	local token = kind and POWER_TOKENS[kind] or "mana"
	if token ~= self.powerToken then
		self.powerToken = token
		self.mana:SetStatusBarColor(Stoa:Color(token))
		if self.rest then self.rest.mana:SetStatusBarColor(Stoa:Color(token)) end
		self.manaText:SetTextColor(Stoa:Color(token))
	end
end

function Halo:UpdateSignature()
	local slot = self.signature
	local role = Stoa:GetRole()
	local _, classFile = UnitClass("player")
	local list = SIGNATURES[classFile] and SIGNATURES[classFile][role] or {}

	slot.spellID = Stoa.signatureFor and Stoa.signatureFor() or nil
	for _, spellID in ipairs(slot.spellID and {} or list) do
		if knows(spellID) then
			slot.spellID = spellID
			break
		end
	end

	-- Until the spec's spell is learned the slot stays empty rather than
	-- showing a blank ring.
	if slot.spellID then
		slot.icon:SetTexture(C_Spell.GetSpellTexture(slot.spellID))
		slot.icon:SetTexCoord(0.1, 0.9, 0.1, 0.9)
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

function Halo:ResetTargetName()
	local fs = self.target and self.target.name
	if not fs or not UnitExists("target") then return end
	Stoa:SetFont(fs, "serif", Stoa.typeSize.name)
	fs:SetText("")
	fs:SetText(UnitName("target"))
end

function Halo:UpdateTarget()
	local target = self.target
	-- Showing and hiding is the unit watch's job, as the frame is secure.
	if not UnitExists("target") then return end
	local name = UnitName("target")
	target.name:SetText(name)
	-- The first time the serif face is drawn the game may not have loaded
	-- it yet and the string comes out empty, and it can come out empty
	-- while still measuring wide, so the width can't be trusted. The face
	-- and the words are set again a moment later, clearing first, since the
	-- game skips a SetText with the same words.
	C_Timer.After(0.1, function() self:ResetTargetName() end)
	target.name:SetTextColor(UI.classColor("target"))
	UI.setUnitBar(target.hp, "target", "health")
	UI.setHealthPercent(target.health, "target")
	SetPortraitTexture(target.plaque.portrait, "target")

	-- Level and kind on the caption; elite and rare say so and change the
	-- plaque's line.
	local plain = Stoa.safe.plain
	local rank = plain(UnitClassification("target"))
	local level = plain(UnitLevel("target"))
	local kind = plain(UnitCreatureType("target"))
	local words = {}
	if rank == "elite" or rank == "worldboss" then words[#words + 1] = "ELITE" end
	if rank == "rare" or rank == "rareelite" then words[#words + 1] = "RARE" end
	if level then words[#words + 1] = "LEVEL " .. (level < 0 and "??" or level) end
	if kind and not plain(UnitIsPlayer("target")) then words[#words + 1] = kind:upper() end
	target.caption:SetText(UI.join(words))
	local plaqueRank = (rank == "rare" or rank == "rareelite") and "rare"
		or (rank == "elite" or rank == "worldboss") and "elite" or nil
	target.plaque:SetRank(plaqueRank)
	target.caption:SetTextColor(Stoa:Color(plaqueRank and "accent" or "muted"))
	if plaqueRank == "rare" then target.caption:SetTextColor(unpack(Stoa.silver)) end

	-- A dead target says so in words and steps back, rather than reading as
	-- a hostile at zero.
	local dead = UnitIsDead("target")
	if Stoa:IsSecret(dead) then dead = false end
	local hostile = not dead and UnitCanAttack("player", "target")
	if Stoa:IsSecret(hostile) then hostile = false end
	target.hp:SetStatusBarColor(Stoa:Color(hostile and "hostile" or "health"))
	local cue = dead and "DEAD" or hostile and "HOSTILE" or ""
	target.cue:SetText(cue)
	target.cue:SetTextColor(Stoa:Color(dead and "muted" or Stoa:StateToken(cue)))
	if target.plaque.SetReaction then target.plaque:SetReaction(hostile and "hostile" or nil) end
	target.hp:SetShown(not dead)
	target.health:SetShown(not dead)
	target:SetAlpha(self:TargetAlpha(dead))
	self:UpdateTargetAuras()
	if dead then
		target.threat:SetText("")
	else
		self:UpdateThreat()
	end
end

-- Your Shield, Renew and the like on a friendly target, as the same tags
-- the party cards carry. Nothing on an enemy or the dead.
function Halo:UpdateTargetPips()
	local row = self.target and self.target.pips
	if not row then return end
	local pips = {}
	local party = Stoa.modules.Party
	if party and party.enabled and party.AuraPips and UnitExists("target") then
		local hostile, dead = UnitCanAttack("player", "target"), UnitIsDead("target")
		if Stoa:IsSecret(hostile) then hostile = true end
		if Stoa:IsSecret(dead) then dead = false end
		if not hostile and not dead then party:AuraPips("target", pips) end
	end
	UI.setPips(row, pips)
end

-- Fills the target's aura icons. Values can be secret in combat; textures
-- and counts still take them, and the sweep is skipped if the times can't
-- be read.
function Halo:UpdateTargetAuras()
	self:UpdateTargetPips()
	local icons = self.target.auras
	if not icons then return end
	local hostile = UnitCanAttack("player", "target")
	if Stoa:IsSecret(hostile) then hostile = false end
	local found, seen = {}, {}
	local function collect(filter)
		if Stoa:AurasHidden() or not (C_UnitAuras and C_UnitAuras.GetAuraDataByIndex) then return end
		for i = 1, 40 do
			if #found >= AURA_COUNT then return end
			local ok, aura = pcall(C_UnitAuras.GetAuraDataByIndex, "target", i, filter)
			if not ok or not aura then return end
			-- Your own buffs come first, so skip them on the second pass.
			local id = aura.auraInstanceID
			if Stoa:IsSecret(id) then id = nil end
			local key = id or (filter .. i)
			if not seen[key] then
				seen[key] = true
				found[#found + 1] = { aura = aura, filter = filter, index = i, id = id }
			end
		end
	end
	if UnitExists("target") then
		if hostile then
			collect("HARMFUL|PLAYER")
		else
			collect("HELPFUL|PLAYER")
			collect("HELPFUL")
		end
	end
	-- From the card's inner edge, under it or above it (PlaceTargetAuras).
	if not icons.placed then self:PlaceTargetAuras() end
	for i, icon in ipairs(icons) do
		local slot = found[i]
		local aura = slot and slot.aura
		if aura then
			icon.auraFilter, icon.auraIndex, icon.auraInstanceID = slot.filter, slot.index, slot.id
			if GameTooltip.IsOwned and GameTooltip:IsOwned(icon) then icon:GetScript("OnEnter")(icon) end
			icon.texture:SetTexture(aura.icon)
			icon.count:SetText("")
			pcall(function()
				local n = aura.applications
				icon.count:SetText(n and n > 1 and n or "")
			end)
			icon.cooldown:Clear()
			pcall(function()
				if aura.duration and aura.duration > 0 then
					icon.cooldown:SetCooldown(aura.expirationTime - aura.duration, aura.duration)
				end
			end)
			icon:Show()
		else
			icon.auraFilter, icon.auraIndex, icon.auraInstanceID = nil, nil, nil
			if GameTooltip.IsOwned and GameTooltip:IsOwned(icon) then GameTooltip:Hide() end
			icon:Hide()
		end
	end
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
	local text = words[status] or ""
	-- Close to pulling the enemy off the tank: say so, with the number when
	-- the game lets us read it.
	if not isTank then
		local ok, tanking, _, scaled = pcall(UnitDetailedThreatSituation, "player", "target")
		scaled = ok and Stoa:PlainNumber(scaled)
		if type(scaled) == "number" and scaled >= 90 and not Stoa:IsSecret(tanking) and tanking ~= true then
			text = "PULLING AGGRO " .. math.floor(scaled + 0.5) .. "%"
		end
	end
	threat:SetText(text)
	-- Holding aggro as a tank is the calm case; everything else is a warning.
	local calm = isTank and status == 3
	threat:SetTextColor(Stoa:Color(calm and "muted" or "danger"))
end

-- Reminders ----------------------------------------------------------------

-- Your own buff names, or nil when any of them is hidden (secret) and a
-- missing buff can't be told from an unreadable one.
local function ownBuffNames()
	if Stoa:AurasHidden() then return nil end
	if not (C_UnitAuras and C_UnitAuras.GetAuraDataByIndex) then return nil end
	local names = {}
	for i = 1, 40 do
		local ok, aura = pcall(C_UnitAuras.GetAuraDataByIndex, "player", i, "HELPFUL")
		if not ok then return nil end
		if not aura then break end
		if Stoa:IsSecret(aura.name) then return nil end
		names[#names + 1] = aura.name
	end
	return names
end

local function matching(names, rule)
	for _, name in ipairs(names) do
		if rule.name and name == rule.name then return name end
		if rule.prefix and name:sub(1, #rule.prefix) == rule.prefix then return name end
		if rule.suffix and name:sub(-#rule.suffix) == rule.suffix then return name end
	end
end

-- Missing buffs as words, plus the seal you're running, shortened.
function Halo:Reminders()
	local _, classFile = UnitClass("player")
	local rules = REMINDERS[classFile]
	if not rules then return {}, nil end
	local names = ownBuffNames()
	if not names then return {}, nil end
	local role = Stoa:GetRole()
	local inCombat = Stoa:GetState() == Stoa.STATE_COMBAT
	local missing, active = {}, nil
	for _, rule in ipairs(rules) do
		local applies = (not rule.roles or rule.roles[role])
			and (not rule.spell or knows(rule.spell))
			and (not rule.combat or inCombat)
		if applies then
			local found = matching(names, rule)
			if not found then
				missing[#missing + 1] = rule.word
			elseif rule.show and rule.prefix then
				active = found:sub(#rule.prefix + 1):upper()
			end
		end
	end
	return missing, active
end

function Halo:UpdateReminders()
	local missing, active = self:Reminders()
	-- Pet words (Pet.lua) join the missing buffs: CALL PET, FEED, PET LOW.
	if Stoa.Pet and Stoa.Pet.Words then
		local words = {}
		for _, word in ipairs(missing) do words[#words + 1] = word end
		local ok, pet = pcall(Stoa.Pet.Words, Stoa.Pet)
		for _, word in ipairs(ok and pet or {}) do words[#words + 1] = word end
		missing = words
	end
	local line = self.reminders
	local parts = {}
	local warn = Stoa:Hex("danger")
	for _, word in ipairs(missing) do parts[#parts + 1] = warn .. word .. "|r" end
	if active then parts[#parts + 1] = active end
	line:SetText(UI.join(parts, true))
	-- The console shows what's missing out of combat.
	Stoa.missingBuffs = missing
	Stoa:Fire("STOA_REMINDERS_CHANGED")
end

-- Cast bar. Plain times drive it with GetTime; secret times use the client's
-- duration object when there is one.
function Halo:StartCast(channel)
	local cast = self.cast
	local name, text, _, startMS, endMS = (channel and UnitChannelInfo or UnitCastingInfo)("player")
	if not name then
		self:StopCast()
		return
	end
	-- The display text is what Blizzard's own bar shows ("Opening" rather
	-- than the internal "Opening - No Text").
	local label = name
	if text and not Stoa:IsSecret(text) and text ~= "" then label = text end
	if not Stoa:IsSecret(label) then label = label:gsub(" %- No Text$", "") end
	cast.spell:SetText(label)
	cast:SetScript("OnUpdate", nil)
	self:SetTicks(channel and not Stoa:IsSecret(name) and CHANNEL_TICKS[name] or nil)

	if not Stoa:IsSecret(startMS) and not Stoa:IsSecret(endMS) then
		cast:SetMinMaxValues(startMS / 1000, endMS / 1000)
		cast:SetScript("OnUpdate", Stoa:GuardUpdate(function(bar)
			local now = GetTime()
			if channel then
				bar:SetValue(endMS / 1000 - (now - startMS / 1000))
			else
				bar:SetValue(now)
			end
		end))
	elseif cast.SetTimerDuration then
		local getDuration = channel and UnitChannelDuration or UnitCastingDuration
		if getDuration then pcall(cast.SetTimerDuration, cast, getDuration("player")) end
	end
	cast:Show()
end

-- Shows evenly spaced tick marks for a channel of this many ticks.
function Halo:SetTicks(count)
	local cast = self.cast
	for i, tick in ipairs(cast.ticks) do
		local shown = count and i < count
		if shown then
			tick:ClearAllPoints()
			tick:SetPoint("CENTER", cast, "LEFT", cast:GetWidth() * (count - i) / count, 0)
		end
		tick:SetShown(shown and true or false)
	end
	cast.notch:SetShown(count and true or false)
end

function Halo:StopCast()
	self.cast:SetScript("OnUpdate", nil)
	self.cast:Hide()
end

-- Showing and hiding --------------------------------------------------------

function Halo:SetShown(shown)
	local t = Stoa.TRANSITION
	local seconds = shown and (t and t.into or FADE_IN) or (t and t.out or FADE_OUT)
	UI.fade(self.frame, shown and 1 or 0, seconds)
	-- The resting arcs trade places with the Halo.
	if self.rest then UI.fade(self.rest, shown and 0 or REST_ARCS, seconds) end
	if self.target then self.target:SetAlpha(self:TargetAlpha()) end
end

-- The plaque: dimmed for a dead target, and (Settings: Fade frames out of
-- combat) resting faint out of a fight until the mouse is over it.
function Halo:TargetAlpha(dead)
	if dead == nil then
		dead = UnitIsDead("target")
		if Stoa:IsSecret(dead) then dead = false end
	end
	local alpha = dead and 0.6 or 1
	if self.db.restFade and Stoa:GetState() ~= Stoa.STATE_COMBAT
		and not (self.target and self.target:IsMouseOver()) then
		alpha = alpha * REST_FADE
	end
	return alpha
end

-- Two faint arcs in the Halo's place while it rests: the same health and
-- power, nothing else. On its own frame, so the Halo's fade doesn't take
-- them with it.
function Halo:BuildRest()
	local rest = CreateFrame("Frame", "StoaHaloRest", UIParent)
	rest:SetAllPoints(self.frame)
	rest:SetScale(self.db.scale)
	rest:SetFrameStrata("LOW")
	rest:EnableMouse(false)
	rest.health = arc(rest, "Left", "health")
	rest.health:SetPoint("LEFT")
	rest.mana = arc(rest, "Right", "mana")
	rest.mana:SetPoint("RIGHT")
	rest:SetAlpha(Stoa:GetState() == Stoa.STATE_COMBAT and 0 or REST_ARCS)
	self.rest = rest
	UI.applyTheme()
end

-- Blizzard frames that repeat what the seal and Halo show.
local function hideBlizzard(frames)
	return function()
		for _, blizzard in ipairs(frames) do
			if blizzard then blizzard:SetParent(UI.hidden) end
		end
	end
end

-- The game's totem bar is a child of the player frame, so hiding that
-- would take a Shaman's totems with it. It moves under the Halo instead,
-- where the game can still lay it out.
function Halo:KeepTotems()
	local totems = TotemFrame
	if not totems or self.totemsKept then return end
	local _, classFile = UnitClass("player")
	if classFile ~= "SHAMAN" then return end
	self.totemsKept = true
	totems:SetParent(UIParent)
	local function place()
		if InCombatLockdown and InCombatLockdown() then return end
		local _, relativeTo = totems:GetPoint(1)
		if relativeTo == self.frame then return end
		totems:ClearAllPoints()
		totems:SetPoint("TOP", self.frame, "BOTTOM", 0, -8)
	end
	place()
	Stoa:On("PLAYER_TOTEM_UPDATE", place)
	Stoa:On("STOA_STATE_CHANGED", place)
end

-- Lifecycle -----------------------------------------------------------------

function Halo:OnEnable()
	addTicks(15407, 3) -- Mind Flay
	-- The party strips and the target without a panel belong to Slim and
	-- Minimal; Full keeps the cards and the plaque. Both were on for
	-- everyone for a while and saved that way, so once per character they
	-- are set from the console in use: on for Slim or no console, else off.
	if not Stoa.char.stripsByConsole then
		Stoa.char.stripsByConsole = true
		local console, party = Stoa.modules.Grimoire, Stoa.modules.Party
		local small = console and (not Stoa:IsModuleEnabled("Grimoire") or (console.db and console.db.slim)) and true or false
		self.db.targetStrip = small
		if party and party.db then party.db.strips = small end
	end
	self:Build()
	if self.db.restArcs then self:BuildRest() end

	self:UpdateHealth()
	self:UpdatePower()
	self:UpdateSignature()
	self:UpdateTarget()
	self.frame:SetAlpha(Stoa:GetState() == Stoa.STATE_COMBAT and 1 or 0)

	if self.db.hidePlayerFrame then
		Stoa:AfterCombat(function()
			xpcall(hideBlizzard({ PlayerFrame, PlayerCastingBarFrame }), Stoa.catch)
			xpcall(function() self:KeepTotems() end, Stoa.catch)
		end)
	end
	if self.db.hideTargetFrame then
		Stoa:AfterCombat(function()
			xpcall(hideBlizzard({ TargetFrame, FocusFrame }), Stoa.catch)
		end)
	end

	Stoa:On("STOA_STATE_CHANGED", function(state)
		self:SetShown(state == Stoa.STATE_COMBAT)
		self:UpdateReminders()
	end)
	Stoa:On("STOA_ROLE_CHANGED", function()
		self:UpdateSignature()
		self:UpdateReminders()
	end)
	Stoa:On("UNIT_DISPLAYPOWER", function(unit)
		if unit == "player" then self:UpdatePower() end
	end)
	Stoa:On("STOA_THEME_CHANGED", function()
		self.powerToken = nil
		self:UpdatePower()
	end)
	Stoa:OnUnit("UNIT_AURA", { "player", "target" }, function(unit)
		if unit == "player" then self:UpdateReminders() end
		if unit == "target" then self:UpdateTargetAuras() end
	end)
	Stoa:On("PLAYER_ENTERING_WORLD", function()
		self:UpdateHealth()
		self:UpdatePower()
		self:UpdateSignature()
		self:UpdateReminders()
	end)
	Stoa:On("SPELLS_CHANGED", function() self:UpdateSignature() end)
	Stoa:On("SPELL_UPDATE_COOLDOWN", function() self:UpdateCooldown() end)

	Stoa:OnUnit("UNIT_HEALTH", { "player", "target" }, function(unit)
		if unit == "player" then self:UpdateHealth() end
		if unit == "target" then self:UpdateTarget() end
	end)
	Stoa:OnUnit("UNIT_MAXHEALTH", { "player", "target" }, function(unit)
		if unit == "player" then self:UpdateHealth() end
	end)
	Stoa:OnUnit("UNIT_POWER_UPDATE", { "player" }, function(unit)
		if unit == "player" then self:UpdatePower() end
	end)
	Stoa:OnUnit("UNIT_MAXPOWER", { "player" }, function(unit)
		if unit == "player" then self:UpdatePower() end
	end)
	Stoa:On("PLAYER_TARGET_CHANGED", function() self:UpdateTarget() end)
	-- A creature not yet seen this session has no name until the game has
	-- looked it up, a moment after targeting; fill it in when it arrives.
	Stoa:OnUnit("UNIT_NAME_UPDATE", { "target" }, function(unit)
		if unit == "target" then self:UpdateTarget() end
	end)
	Stoa:On("UNIT_THREAT_SITUATION_UPDATE", function() self:UpdateThreat() end)
	Stoa:On("UNIT_THREAT_LIST_UPDATE", function(unit)
		if unit == "target" then self:UpdateThreat() end
	end)

	local function onCast(channel)
		return function(unit)
			if unit == "player" then self:StartCast(channel) end
		end
	end
	-- A stop, fail or interrupt can belong to another cast than the one on
	-- the bar: pressing a spell while one is casting fails that press, and
	-- the game says so. Blizzard's bar checks the cast's ID; this asks the
	-- game what is casting now and keeps the bar while it is.
	local function onStop(unit)
		if unit ~= "player" then return end
		-- A hidden name still means something is casting.
		local function busy(info)
			local name = info("player")
			return Stoa:IsSecret(name) or name ~= nil
		end
		if busy(UnitCastingInfo) or busy(UnitChannelInfo) then return end
		self:StopCast()
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
