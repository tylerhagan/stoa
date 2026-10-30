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
	-- Quiet mana play: the five-second rule and regen ticks, the cost of
	-- the spell you are casting, and a druid's mana while shapeshifted.
	manaRule = true,
	castCost = true,
	formMana = true,
})

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
local TARGET_WIDTH = 268
local TARGET_PAD = 12
-- Room on the left for the half of the coin inside the plaque.
local TARGET_COIN_SPACE = 40

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
	end)
	target:SetScript("OnLeave", GameTooltip_Hide)
	-- Any target, in or out of combat. A dead one stays, dimmed and saying
	-- DEAD, so the plaque always matches what you have targeted.
	RegisterStateDriver(target, "visibility", "[@target,exists] show; hide")
	self.target = target
	Stoa:RegisterMover("target", target, "Target plaque")

	-- A plaque like the tank watch opposite: the coin faces the Halo.
	local plaque = UI.plaque(target, "LEFT")
	target.plaque = plaque
	local left = TARGET_COIN_SPACE
	local caption = UI.caption(target, "")
	caption:SetPoint("TOPLEFT", left, -TARGET_PAD)
	-- Hostile targets get a word as well as a colour.
	local cue = UI.caption(target, "")
	cue:SetPoint("TOPRIGHT", -TARGET_PAD, -TARGET_PAD)
	local name = UI.text(target, "serif", Stoa.typeSize.title, "text", "LEFT")
	name:SetPoint("TOPLEFT", caption, "BOTTOMLEFT", 0, -4)
	name:SetWidth(TARGET_WIDTH - left - TARGET_PAD - 40)
	name:SetWordWrap(false)
	local health = UI.text(target, "serif", Stoa.typeSize.title, "text", "RIGHT")
	health:SetPoint("TOPRIGHT", cue, "BOTTOMRIGHT", 0, -4)
	local barWidth = TARGET_WIDTH - left - TARGET_PAD
	local hp = UI.bar(target, barWidth, 4, "health")
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
	target.threat, target.caption = threat, caption

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
		count:SetPoint("BOTTOMRIGHT", 2, -2)
		icon.count = count
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
	self.healthText:SetText(UnitHealth("player"))
end

-- The right arc is whatever your power is: mana in its own colour, energy
-- pale gold, rage bone, so a druid's form change reads at a glance.
local POWER_TOKENS = { [1] = "text", [3] = "accent" }

function Halo:UpdatePower()
	UI.setUnitBar(self.mana, "player", "power")
	self.manaText:SetText(UnitPower("player"))
	local kind = UnitPowerType and Stoa:PlainNumber((UnitPowerType("player")))
	local token = kind and POWER_TOKENS[kind] or "mana"
	if token ~= self.powerToken then
		self.powerToken = token
		self.mana:SetStatusBarColor(Stoa:Color(token))
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

function Halo:UpdateTarget()
	local target = self.target
	-- Showing and hiding is the unit watch's job, as the frame is secure.
	if not UnitExists("target") then return end
	target.name:SetText(UnitName("target"))
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
	target.caption:SetText(table.concat(words, " · "))
	local plaqueRank = (rank == "rare" or rank == "rareelite") and "rare"
		or (rank == "elite" or rank == "worldboss") and "elite" or nil
	target.plaque:SetRank(plaqueRank)
	target.caption:SetTextColor(Stoa:Color(plaqueRank and "accent" or "muted"))
	if plaqueRank == "rare" then target.caption:SetTextColor(0.79, 0.8, 0.82) end

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
	self:UpdateTargetAuras()
	if dead then
		target.threat:SetText("")
	else
		self:UpdateThreat()
	end
end

-- Fills the target's aura icons. Values can be secret in combat; textures
-- and counts still take them, and the sweep is skipped if the times can't
-- be read.
function Halo:UpdateTargetAuras()
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
				found[#found + 1] = aura
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
	-- The row hangs under the card, from its inner edge. The card is a
	-- secure button, so the anchor is set once, out of combat.
	if not icons.placed and not InCombatLockdown() then
		icons[1]:ClearAllPoints()
		icons[1]:SetPoint("TOPLEFT", self.target, "BOTTOMLEFT", TARGET_COIN_SPACE, -6)
		icons.placed = true
	end
	for i, icon in ipairs(icons) do
		local aura = found[i]
		if aura then
			icon.texture:SetTexture(aura.icon)
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
	local line = self.reminders
	local parts = {}
	local r, g, b = Stoa:Color("danger")
	local warn = string.format("|cff%02x%02x%02x", r * 255, g * 255, b * 255)
	for _, word in ipairs(missing) do parts[#parts + 1] = warn .. word .. "|r" end
	if active then parts[#parts + 1] = active end
	line:SetText(table.concat(parts, "  ·  "))
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
	addTicks(15407, 3) -- Mind Flay
	self:Build()

	self:UpdateHealth()
	self:UpdatePower()
	self:UpdateSignature()
	self:UpdateTarget()
	self.frame:SetAlpha(Stoa:GetState() == Stoa.STATE_COMBAT and 1 or 0)

	if self.db.hidePlayerFrame then
		Stoa:AfterCombat(function()
			xpcall(hideBlizzard({ PlayerFrame, PlayerCastingBarFrame }), Stoa.catch)
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
