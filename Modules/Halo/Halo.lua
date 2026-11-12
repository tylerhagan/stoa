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
	-- Who your target is targeting, as a small line at the plaque's right.
	targetOfTarget = true,
	-- Your focus as a small block under the target of target.
	focusFrame = true,
	-- Your own shield, draining as it soaks up damage, under the health
	-- number (and beside the console's medallion while it is open).
	shield = true,
	-- Your class's kept-up buff as a mark that empties (Mark.lua), under
	-- the power number and on the medallion.
	classMark = true,
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
		{ word = "NO SEAL", prefix = "Seal of ", combat = true, show = true, mark = true },
		{ word = "NO FURY", name = "Righteous Fury", spell = 25780, roles = { TANK = true } },
	},
	PRIEST = {
		{ word = "NO INNER FIRE", name = "Inner Fire", spell = 588, mark = true },
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

	-- Your shield under the health number, as the druid's form mana sits
	-- under the power number.
	if self.db.shield then
		local shield = UI.shieldGauge(frame, 22)
		shield:SetPoint("TOPRIGHT", healthText, "BOTTOMRIGHT", 1, -3)
		self.shield = shield
	end
	-- And your class mark under the power number, mirroring it.
	if self.db.classMark and Stoa.Mark then
		local mark = Stoa.Mark.attach(frame, 22)
		if mark then mark:SetPoint("TOPLEFT", manaText, "BOTTOMLEFT", -1, -3) end
		self.classMark = mark
	end

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
			show = function(_, raw) number:SetText(raw) number:Show() end,
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
-- plaque with a round portrait medallion breaking its right edge (the level
-- on a badge at its foot): kind, name, a rounded health bar carrying the
-- percent and the health, a fine power line, the hostile and threat words,
-- its cast and a row of auras. Elite and rare targets get a gold or a
-- silver edge and the word. Like the cast bar it is parented to UIParent,
-- so it stays with you out of combat as well. It's a secure unit button, so
-- right click opens the unit menu (focus, invite, inspect, trade) like
-- Blizzard's target frame.
local TARGET_WIDTH = 294
local TARGET_HEIGHT = 100
local TARGET_PAD = 14
-- Room on the right for the part of the medallion inside the plaque.
local TARGET_COIN_SPACE = UI.PLAQUE_MEDALLION_SPACE
-- The health bar: its size matches the pill drawn in TargetBar.tga
-- (Tools/art/plaque_dock.py), which masks it to round ends.
local TARGET_BAR_W = TARGET_WIDTH - TARGET_PAD - TARGET_COIN_SPACE
local TARGET_BAR_H = 14
local TARGET_CAST_H = 14

-- Out of combat, on the full console with its art, the plaque docks on the
-- gold rim on the mana side, beside the bars you read there: as tall as the
-- medallion, its left end fitted round it, no portrait (the level joins the
-- caption), its right end sweeping down to the rim (UI.plaque's
-- SetDocked). The target of target stands behind that sweep as a lower
-- slab of its own. In a fight it moves to the Halo's upper right as the
-- full plaque. A spot set with the movers wins.
local TARGET_DOCK_Y = -1
-- Where the words start, from the plaque's left end, clear of the medallion.
local TARGET_DOCK_TEXT = 60
-- Without the console's art there's no medallion to fit round: the plaque
-- rests a little above the console instead.
local TARGET_REST_Y = 14

-- The aura row hangs under the plaque at the Halo, and sits on top of it
-- while it rests on the console, where under it would run over the gold
-- edge. Out of combat only: the plaque is secure.
function Halo:PlaceTargetAuras()
	local icons = self.target and self.target.auras
	if not (icons and icons[1]) or InCombatLockdown() then return end
	icons[1]:ClearAllPoints()
	-- The cast sits next to the plaque and the auras past it, so a cast
	-- starting never moves them.
	local cast = self.target.castBar
	cast:ClearAllPoints()
	local step = TARGET_CAST_H + 6
	if self.targetResting then
		local left = self.targetTextLeft or TARGET_PAD
		cast:SetPoint("BOTTOMLEFT", self.target, "TOPLEFT", left, 6)
		icons[1]:SetPoint("BOTTOMLEFT", self.target, "TOPLEFT", left, 6 + step)
	elseif self.db.targetStrip then
		-- Without the panel they follow the bar, leaving one line for the
		-- threat and KICK words between them.
		cast:SetPoint("TOPLEFT", self.target.hp, "BOTTOMLEFT", 0, -26)
		icons[1]:SetPoint("TOPLEFT", self.target.hp, "BOTTOMLEFT", 0, -26 - step)
	else
		cast:SetPoint("TOPLEFT", self.target, "BOTTOMLEFT", TARGET_PAD, -6)
		icons[1]:SetPoint("TOPLEFT", self.target, "BOTTOMLEFT", TARGET_PAD, -6 - step)
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
		self.targetResting = true
		self.targetDocks = console.Art and console:Art() or false
		if self.targetDocks then
			target:SetPoint("BOTTOMLEFT", UIParent, "BOTTOM", UI.PLAQUE_SOCKET_X, console:OpenHeight() + TARGET_DOCK_Y)
			self.targetTextLeft = TARGET_DOCK_TEXT
		else
			local gap = 150 * (console.ART_SCALE or 0.556) + 22
			target:SetPoint("BOTTOMLEFT", UIParent, "BOTTOM", gap, console:OpenHeight() + TARGET_REST_Y)
			self.targetTextLeft = nil
		end
	elseif self.db.targetStrip then
		-- Level with the Halo, mirroring the party strips on its left.
		target:SetPoint("LEFT", frame, "RIGHT", 52 - TARGET_PAD, -6)
		self.targetResting = false
	else
		target:SetPoint("BOTTOMLEFT", frame, "RIGHT", 52, 36)
		self.targetResting = false
	end
	-- Docked, the corner starts rounding just past the health bar: there's
	-- no portrait to leave room for.
	local barEnd = (self.targetTextLeft or TARGET_PAD) + TARGET_BAR_W
	local curve = barEnd + 14
	if self.targetResting and self.targetDocks then curve = barEnd + 14 - UI.PLAQUE_JOIN_FLAT end
	target.plaque:SetDocked(self.targetResting and self.targetDocks, curve)
	self:LayoutTarget(target.plaque.docked and curve or nil)
	self:PlaceTargetOfTarget(target.plaque.docked and curve or nil)
	target:SetAlpha(self:TargetAlpha())
	self:PlaceTargetAuras()
	-- The level moves between the caption and the medallion's badge.
	if target.caption then self:UpdateTarget() end
end

-- Lays the plaque's words and bar out: docked (the full plaque's rows
-- between the medallion and the rounded corner, `curve` being where the
-- corner's art starts) or the full plaque. Out of combat only.
function Halo:LayoutTarget(curve)
	local target = self.target
	if not (target and target.hp) then return end
	local docked = curve ~= nil
	if docked == target.laidDocked and (not docked or curve == target.laidCurve) then return end
	target.laidDocked, target.laidCurve = docked, curve
	for _, part in ipairs({ target.caption, target.cue, target.name, target.hp }) do part:ClearAllPoints() end
	if docked then
		target:SetSize(curve + UI.PLAQUE_JOIN_SPAN, UI.PLAQUE_JOIN_H)
		-- Set high, so the bar keeps clear of the console's gold rim.
		local left = self.targetTextLeft
		target.caption:SetPoint("TOPLEFT", left, -9)
		target.cue:SetPoint("TOPRIGHT", target, "TOPLEFT", left + TARGET_BAR_W, -9)
		target.name:SetPoint("TOPLEFT", left, -22)
		target.name:SetWidth(TARGET_BAR_W)
		target.hp:SetPoint("TOPLEFT", left, -40)
	else
		target:SetSize(TARGET_WIDTH, TARGET_HEIGHT)
		target.caption:SetPoint("TOPLEFT", TARGET_PAD, -12)
		target.cue:SetPoint("TOPRIGHT", -TARGET_COIN_SPACE, -12)
		target.name:SetPoint("TOPLEFT", TARGET_PAD, -26)
		target.name:SetWidth(TARGET_BAR_W)
		target.hp:SetPoint("TOPLEFT", TARGET_PAD, -48)
	end
	self:UpdateTargetPower()
	self:UpdateTargetPips()
end

function Halo:BuildTarget(frame)
	local target = CreateFrame("Button", "StoaTarget", UIParent, "SecureUnitButtonTemplate")
	target:SetFrameStrata("LOW")
	target:SetSize(TARGET_WIDTH, TARGET_HEIGHT)
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
	-- The medallion faces away from the Halo, balancing the card.
	local plaque = UI.plaque(target, "RIGHT", { medallion = true })
	target.plaque = plaque
	self:BuildTargetCast(target)
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

	local caption = UI.caption(target, "")
	caption:SetPoint("TOPLEFT", TARGET_PAD, -12)
	-- Hostile targets get a word as well as a colour.
	local cue = UI.caption(target, "")
	cue:SetPoint("TOPRIGHT", -TARGET_COIN_SPACE, -12)
	-- One step below title size, so most creature names fit whole.
	local name = UI.text(target, "serif", Stoa.typeSize.name, "text", "LEFT")
	name:SetPoint("TOPLEFT", TARGET_PAD, -26)
	name:SetWidth(TARGET_BAR_W)
	name:SetWordWrap(false)
	-- The health bar: rounded, slim, carrying the percent and the health
	-- inside it.
	local hp = UI.bar(target, TARGET_BAR_W, TARGET_BAR_H, "health")
	-- Coloured by UpdateTarget (hostile or not), so a theme pass mustn't
	-- turn it back to the health colour.
	UI.unpaint(hp)
	hp:SetPoint("TOPLEFT", TARGET_PAD, -48)
	local outset = (TARGET_BAR_W * 64 / 512 - TARGET_BAR_H) / 2
	local mask = hp:CreateMaskTexture()
	mask:SetTexture(UI.MEDIA .. "Textures\\TargetBar", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
	mask:SetPoint("TOPLEFT", 0, outset)
	mask:SetPoint("BOTTOMRIGHT", 0, -outset)
	hp:GetStatusBarTexture():AddMaskTexture(mask)
	-- A dark well rather than the usual faint track, so the words read.
	hp.track:Hide()
	local well = hp:CreateTexture(nil, "BACKGROUND")
	well:SetAllPoints()
	well:SetColorTexture(0, 0, 0, 0.6)
	well:AddMaskTexture(mask)
	-- Its words sit above anything drawn over the bar (Lethal.lua).
	local words = CreateFrame("Frame", nil, hp)
	words:SetAllPoints()
	words:SetFrameLevel(hp:GetFrameLevel() + 6)
	local rim = words:CreateTexture(nil, "BORDER")
	rim:SetTexture(UI.MEDIA .. "Textures\\TargetBarEdge")
	rim:SetAllPoints(mask)
	UI.tint(rim, "text", 0.18)
	local health = UI.text(words, "sans", Stoa.typeSize.body, "text", "LEFT")
	health:SetPoint("LEFT", 10, 0)
	UI.legible(health)
	local amount = UI.text(words, "sans", Stoa.typeSize.micro, "text", "LEFT")
	amount:SetPoint("LEFT", health, "RIGHT", 8, 0)
	amount:SetAlpha(0.8)
	UI.legible(amount)
	target.healthWords = words
	-- Mana, rage or energy as a fine line under the bar.
	local power = UI.bar(target, TARGET_BAR_W - 16, 3, "mana")
	power:SetPoint("TOP", hp, "BOTTOM", 0, -4)
	-- Threat, in words: tanks hear when they are losing it, everyone else
	-- when they are taking it.
	local threat = UI.caption(target, "")
	threat:SetPoint("TOPRIGHT", hp, "BOTTOMRIGHT", 0, -12)
	-- KICK, when the target is casting something you can interrupt (Kit.lua).
	local kick = UI.text(target, "sans", Stoa.typeSize.caption, "danger", "LEFT")
	kick:SetPoint("TOPLEFT", hp, "BOTTOMLEFT", 0, -12)
	kick:Hide()
	target.kick = kick
	target.name, target.hp, target.cue, target.health = name, hp, cue, health
	target.amount, target.power = amount, power
	-- On a friend: your buffs on them as the party cards' tags.
	target.pips = UI.pipRow(target, hp, 12)
	target.threat, target.caption = threat, caption
	if self.db.targetStrip then
		plaque:SetBare(true)
		for _, fs in ipairs({ caption, cue, name, threat, kick }) do UI.legible(fs) end
	end

	if self.db.targetOfTarget then self:BuildTargetOfTarget(target) end
	if self.db.focusFrame then self:BuildFocus(target) end

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
	self:PlaceTarget()
end

-- The target's cast: a small rounded bar with the spell and the time left,
-- beside the plaque (above it when docked, under it at the Halo). Warm
-- while it can be interrupted, grey when it can't. Runs only while the
-- target is casting.
function Halo:BuildTargetCast(target)
	local cast = UI.bar(target, TARGET_BAR_W, TARGET_CAST_H, "accent")
	cast.track:Hide()
	local fill = UI.pillFill(cast, 0)
	UI.tint(fill, "panel", 0.92)
	UI.pillEdge(cast, 0):Set(Stoa:Color("hairline"))
	local spell = UI.text(cast, "sans", Stoa.typeSize.caption, "text", "LEFT")
	spell:SetPoint("LEFT", 8, 0)
	spell:SetPoint("RIGHT", -36, 0)
	spell:SetWordWrap(false)
	UI.legible(spell)
	local left = UI.text(cast, "sans", Stoa.typeSize.caption, "text", "RIGHT")
	left:SetPoint("RIGHT", -8, 0)
	UI.legible(left)
	cast.spell, cast.left = spell, left
	cast:Hide()
	target.castBar = cast
end

function Halo:StartTargetCast(channel)
	local cast = self.target and self.target.castBar
	if not cast then return end
	local name, text, _, startMS, endMS, _, _, flag = (channel and UnitChannelInfo or UnitCastingInfo)("target")
	if channel then flag = select(7, UnitChannelInfo("target")) end
	if name == nil then return self:StopTargetCast() end
	local label = name
	if text and not Stoa:IsSecret(text) and text ~= "" then label = text end
	cast.spell:SetText(label)
	local locked = not Stoa:IsSecret(flag) and flag == true
	cast:SetStatusBarColor(Stoa:Color(locked and "muted" or "accent"))
	cast.left:SetText("")
	cast:SetScript("OnUpdate", nil)
	if not Stoa:IsSecret(startMS) and not Stoa:IsSecret(endMS) then
		local finish = endMS / 1000
		cast:SetMinMaxValues(startMS / 1000, finish)
		cast:SetScript("OnUpdate", Stoa:GuardUpdate(function(bar)
			local now = GetTime()
			bar:SetValue(channel and finish - (now - startMS / 1000) or now)
			bar.left:SetFormattedText("%.1f", math.max(finish - now, 0))
		end))
	elseif cast.SetTimerDuration then
		local getDuration = channel and UnitChannelDuration or UnitCastingDuration
		if getDuration then pcall(cast.SetTimerDuration, cast, getDuration("target")) end
	end
	cast:Show()
end

function Halo:StopTargetCast()
	local cast = self.target and self.target.castBar
	if not cast then return end
	cast:SetScript("OnUpdate", nil)
	cast:Hide()
end

-- What the target is casting now, if anything (on a new target, or after
-- a stop that may have belonged to an earlier cast).
function Halo:UpdateTargetCast()
	if not UnitExists("target") then return self:StopTargetCast() end
	local function busy(info)
		local name = info("target")
		return Stoa:IsSecret(name) or name ~= nil
	end
	if busy(UnitCastingInfo) then return self:StartTargetCast(false) end
	if busy(UnitChannelInfo) then return self:StartTargetCast(true) end
	self:StopTargetCast()
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

-- Small unit blocks beside the target plaque: your target's target, and
-- your focus under it. A caption, a name and a thin health line; click to
-- target them. The game sends no events for the target's target, so both
-- are read a few times a second while they show.
local TOT_WIDTH = 124
local CHIP_HEIGHT = 38
function Halo:BuildUnitChip(name, unit, caption, parent)
	local chip = CreateFrame("Button", name, parent, "SecureUnitButtonTemplate")
	chip:SetSize(TOT_WIDTH, CHIP_HEIGHT)
	-- It follows the target's look: a small panel of its own beside the
	-- solid plaque, bare words beside the strip.
	local bare = self.db.targetStrip
	-- Past the medallion breaking the plaque's edge.
	chip.gap = (bare and 14 or 18) + UI.PLAQUE_MEDALLION_OUT
	-- Room between the two blocks: their panels reach 10 past each edge.
	chip.stack = bare and 16 or 28
	if not bare then
		local fill = UI.pillFill(chip, 10)
		UI.tint(fill, "panel", 0.9)
		local r, g, b = Stoa:Color("panel")
		fill:SetVertexColor(r, g, b, 0.9)
		local edge = UI.pillEdge(chip, 10)
		edge:Set(Stoa:Color("hairline"))
		chip.fill, chip.edge = fill, edge
	end
	chip:SetAttribute("unit", unit)
	chip:SetAttribute("type1", "target")
	chip:SetAttribute("type2", "togglemenu")
	chip:RegisterForClicks("AnyUp")
	RegisterStateDriver(chip, "visibility", "[@" .. unit .. ",exists] show; hide")
	chip:SetScript("OnEnter", function(button)
		GameTooltip:SetOwner(button, "ANCHOR_RIGHT")
		pcall(GameTooltip.SetUnit, GameTooltip, unit)
		GameTooltip:Show()
	end)
	chip:SetScript("OnLeave", function() GameTooltip:Hide() end)
	local label = UI.caption(chip, caption)
	label:SetPoint("TOPLEFT")
	local who = UI.text(chip, "sans", Stoa.typeSize.body, "text", "LEFT")
	who:SetPoint("TOPLEFT", label, "BOTTOMLEFT", 0, -4)
	who:SetWidth(TOT_WIDTH)
	who:SetWordWrap(false)
	local hp = UI.bar(chip, TOT_WIDTH, 3, "health")
	hp:SetPoint("TOPLEFT", who, "BOTTOMLEFT", 0, -4)
	if bare then
		for _, fs in ipairs({ label, who }) do UI.legible(fs) end
	end
	chip.unit, chip.name, chip.hp, chip.label = unit, who, hp, label
	Stoa:NewTicker(0.2, function()
		if chip:IsVisible() then self:UpdateUnitChip(chip) end
	end)
	return chip
end

function Halo:BuildTargetOfTarget(target)
	local chip = self:BuildUnitChip("StoaTargetTarget", "targettarget", "Targeting", target)
	chip:SetPoint("TOPLEFT", target, "TOPRIGHT", chip.gap, -TARGET_PAD)
	target.tot = chip
	-- The docked plaque casts its shadow on it while it shows.
	chip:HookScript("OnShow", function() target.plaque:SetShadow(true) end)
	chip:HookScript("OnHide", function() target.plaque:SetShadow(false) end)
	target.plaque:SetShadow(chip:IsShown())
	self:PlaceTargetOfTarget(target.plaque.docked and target.plaque.curve or nil)
end

-- Docked, the target of target is a lower slab standing on the rim behind
-- the plaque, its left end tucked under the plaque's sweep and its words
-- starting where the sweep has passed; `curve` is where the plaque's own
-- curve starts. Otherwise the small panel beside the plaque. Out of combat
-- only: the chip is secure.
local TOT_TUCK = 20    -- how far its left end sits under the plaque
local TOT_DOCK_TEXT = 82 -- its words, from its left end, past the sweep
function Halo:PlaceTargetOfTarget(curve)
	local target = self.target
	local chip = target and target.tot
	if not chip or InCombatLockdown() then return end
	local docked = curve ~= nil
	if docked and not chip.slab then chip.slab = UI.plaqueStep(chip) end
	chip:ClearAllPoints()
	chip.label:ClearAllPoints()
	if docked then
		local left = curve + UI.PLAQUE_JOIN_SPAN - TOT_TUCK
		-- Its corner starts rounding just past its words.
		local stepCurve = TOT_DOCK_TEXT + TOT_WIDTH + 10 - UI.PLAQUE_STEP_FLAT
		-- Behind the plaque: a lower strata than its LOW.
		chip:SetFrameStrata("BACKGROUND")
		chip:SetSize(stepCurve + UI.PLAQUE_STEP_SPAN, UI.PLAQUE_STEP_H)
		chip:SetPoint("BOTTOMLEFT", target, "BOTTOMLEFT", left, 0)
		chip.slab:Layout(stepCurve)
		chip.label:SetPoint("TOPLEFT", TOT_DOCK_TEXT, -6)
	else
		chip:SetFrameStrata("LOW")
		chip:SetSize(TOT_WIDTH, CHIP_HEIGHT)
		chip:SetPoint("TOPLEFT", target, "TOPRIGHT", chip.gap, -TARGET_PAD)
		chip.label:SetPoint("TOPLEFT")
	end
	if chip.slab then chip.slab:SetShown(docked) end
	if chip.fill then
		chip.fill:SetShown(not docked)
		if docked then chip.edge:Clear() else chip.edge:Set(Stoa:Color("hairline")) end
	end
end

-- Your focus, under the target's target, there with or without a target.
-- Its own mover, so it can go anywhere.
function Halo:BuildFocus(target)
	local chip = self:BuildUnitChip("StoaFocus", "focus", "Focus", UIParent)
	chip:SetFrameStrata("LOW")
	local function place()
		chip:ClearAllPoints()
		chip:SetPoint("TOPLEFT", target, "TOPRIGHT", chip.gap, -TARGET_PAD - CHIP_HEIGHT - chip.stack)
	end
	place()
	self.focus = chip
	Stoa:RegisterMover("focus", chip, "Focus", { default = place })
	Stoa:On("PLAYER_FOCUS_CHANGED", function() self:UpdateUnitChip(chip) end)
end

function Halo:UpdateTargetOfTarget()
	local chip = self.target and self.target.tot
	if chip then self:UpdateUnitChip(chip) end
end

function Halo:UpdateUnitChip(chip)
	local unit = chip.unit
	if not UnitExists(unit) then return end
	local plain = Stoa.safe.plain
	-- You, said plainly: on an enemy it is the thing to know at a glance.
	if plain(UnitIsUnit(unit, "player")) then
		local hostile = plain(UnitCanAttack("player", "target"))
		chip.name:SetText("YOU")
		chip.name:SetTextColor(Stoa:Color(hostile and "danger" or "accent"))
	else
		chip.name:SetText(UnitName(unit))
		chip.name:SetTextColor(UI.classColor(unit))
	end
	UI.setUnitBar(chip.hp, unit, "health")
	local foe = plain(UnitCanAttack("player", unit))
	chip.hp:SetStatusBarColor(Stoa:Color(foe and "hostile" or "health"))
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
	UI.setHealthPercent(target.health, "target", nil, true)
	self:UpdateTargetAmount()
	self:UpdateTargetPower()
	SetPortraitTexture(target.plaque.portrait, "target")

	-- Level on the medallion's badge, kind on the caption; elite and rare
	-- say so and change the plaque's line.
	local plain = Stoa.safe.plain
	local rank = plain(UnitClassification("target"))
	local level = plain(UnitLevel("target"))
	local kind = plain(UnitCreatureType("target"))
	local words = {}
	if rank == "elite" or rank == "worldboss" then words[#words + 1] = "ELITE" end
	if rank == "rare" or rank == "rareelite" then words[#words + 1] = "RARE" end
	local levelText = level and (level < 0 and "??" or tostring(level)) or nil
	-- Docked there's no portrait, so the level leads the caption.
	if target.plaque.docked then
		target.plaque:SetLevel(nil)
		if levelText then table.insert(words, 1, (rawget(_G, "LEVEL") or "Level"):upper() .. " " .. levelText) end
	else
		target.plaque:SetLevel(levelText)
	end
	-- The game calls creatures without a type "Not specified": say nothing.
	local unspecified = kind == "Not specified" or kind == (rawget(_G, "UNKNOWN") or "")
	if kind and not unspecified and not plain(UnitIsPlayer("target")) then words[#words + 1] = kind:upper() end
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
	target.power:SetShown(not dead and target.power.hasPower and not target.plaque.docked or false)
	target:SetAlpha(self:TargetAlpha(dead))
	self:UpdateTargetAuras()
	self:UpdateTargetOfTarget()
	if dead then
		target.threat:SetText("")
	else
		self:UpdateThreat()
	end
end

-- The health itself beside the percent, as the game gives it.
function Halo:UpdateTargetAmount()
	local fs = self.target and self.target.amount
	if not fs then return end
	local health = UnitHealth("target")
	if Stoa:IsSecret(health) then
		pcall(fs.SetText, fs, health)
	elseif health and BreakUpLargeNumbers then
		fs:SetText(BreakUpLargeNumbers(health))
	else
		fs:SetText(health or "")
	end
end

-- The power line, in the power's own colour; hidden for a target with none.
function Halo:UpdateTargetPower()
	local power = self.target and self.target.power
	if not power then return end
	local max = UnitPowerMax("target")
	local has = Stoa:IsSecret(max)
	if not has then
		max = Stoa:PlainNumber(max)
		has = max ~= nil and max > 0
	end
	power.hasPower = has
	if not has or self.target.plaque.docked then return power:Hide() end
	UI.setUnitBar(power, "target", "power")
	local kind = UnitPowerType and Stoa:PlainNumber((UnitPowerType("target")))
	power:SetStatusBarColor(Stoa:Color(kind and POWER_TOKENS[kind] or "mana"))
	local dead = UnitIsDead("target")
	power:SetShown(Stoa:IsSecret(dead) or not dead)
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
		-- Docked, there's no room under the bar: it's on the rim.
		local docked = self.target.plaque.docked
		if not hostile and not dead and not docked then party:AuraPips("target", pips) end
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
	-- The class mark shows these itself, empty and dimmed.
	-- In a fight that's the Halo's mark; out of one, the medallion's.
	local console = Stoa.modules.Grimoire
	local marked
	if inCombat then marked = self.classMark ~= nil
	else marked = console and console.sealMark ~= nil and not (console.db and console.db.slim) end
	for _, rule in ipairs(rules) do
		local applies = (not rule.roles or rule.roles[role])
			and (not rule.spell or knows(rule.spell))
			and (not rule.combat or inCombat)
		if applies then
			local found = matching(names, rule)
			if not found then
				if not (rule.mark and marked) then missing[#missing + 1] = rule.word end
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
	-- Docked it is part of the console, which doesn't fade.
	local docked = self.target and self.target.plaque.docked
	if self.db.restFade and not docked and Stoa:GetState() ~= Stoa.STATE_COMBAT
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
			-- Blizzard's focus frame goes only when STOA shows the focus.
			xpcall(hideBlizzard(self.db.focusFrame and { TargetFrame, FocusFrame } or { TargetFrame }), Stoa.catch)
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
		if unit == "target" then self:UpdateTargetPower() end
	end)
	Stoa:On("STOA_THEME_CHANGED", function()
		self.powerToken = nil
		self:UpdatePower()
		self:UpdateTarget()
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
	if self.shield then
		Stoa:OnUnit("UNIT_ABSORB_AMOUNT_CHANGED", { "player" }, function(unit)
			if unit == "player" then self.shield:Update("player", true) end
		end)
		for _, event in ipairs({ "PLAYER_ENTERING_WORLD", "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED" }) do
			Stoa:On(event, function() self.shield:Update("player") end)
		end
	end
	Stoa:OnUnit("UNIT_POWER_UPDATE", { "player", "target" }, function(unit)
		if unit == "player" then self:UpdatePower() end
		if unit == "target" then self:UpdateTargetPower() end
	end)
	Stoa:OnUnit("UNIT_MAXPOWER", { "player", "target" }, function(unit)
		if unit == "player" then self:UpdatePower() end
		if unit == "target" then self:UpdateTargetPower() end
	end)
	Stoa:On("PLAYER_TARGET_CHANGED", function()
		self:UpdateTarget()
		self:UpdateTargetCast()
	end)
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
			if unit == "target" then self:StartTargetCast(channel) end
		end
	end
	-- A stop, fail or interrupt can belong to another cast than the one on
	-- the bar: pressing a spell while one is casting fails that press, and
	-- the game says so. Blizzard's bar checks the cast's ID; this asks the
	-- game what is casting now and keeps the bar while it is.
	local function onStop(unit)
		if unit == "target" then return self:UpdateTargetCast() end
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
