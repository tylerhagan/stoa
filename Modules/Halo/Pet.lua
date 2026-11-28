-- Stoa: pets. For Hunters, Warlocks and anyone else with a pet:
--   a pet plaque at the Halo's upper left in a fight, like the target's
--   opposite, with its mood, health, power, stance and what it's on;
--   a thin inner arc on the Halo with its health;
--   a pet row under the combat bar (the console keeps Blizzard's pet bar,
--   in Stoa's dress, out of a fight);
--   a pet coin hanging off the console's medallion, with its health as a
--   ring and its mood under it; click it to feed the pet when it's hungry;
--   words with the reminders: CALL PET, PET DEAD, FEED <NAME>, PET LOW,
--   PET PASSIVE and GROWL ON in a group;
--   and, for healers in a party, a slim cell under each owner's card.
local _, ns = ...
local Stoa = ns.Stoa
local UI = Stoa.UI

local Pet = Stoa:NewModule("Pet", {
	plaque = true,
	arc = true,
	row = true,
	coin = true,
	words = true,
	partyPets = true,
})
Stoa.Pet = Pet

local plain = function(v) return Stoa.safe.plain(v) end

local PLAQUE_WIDTH, PLAQUE_HEIGHT = 294, 112
local PAD = 12
-- The companion ring: its size, and where on the pet's arc it sits
-- (degrees below the Halo's left).
local RING, RING_AT = 38, 68
-- Ground line: the gap between the health number and the ring.
local LINE_CLEAR = 8
local COIN_SPACE = UI.PLAQUE_COIN_SPACE
local ROW_SIZE, ROW_GAP, ROW_BREAK = 26, 5, 8
local COIN = 46
local LOW = 0.35
-- When the game shows the pet row and the pet coin.
local ROW_RULE = "[combat,@pet,exists,nopossessbar] show; hide"
-- With a card, the row also stands over it at rest.
local ROW_RULE_REST = "[@pet,exists,nopossessbar] show; hide"
local COIN_RULE = "[combat] hide; [@pet,exists] show; hide"

-- Spells that say you play with a pet: Call Pet and Revive Pet, the
-- Warlock's summons.
local CALL_PET, REVIVE_PET, FEED_PET = 883, 982, 6991
local SUMMONS = { 688, 697, 712, 691, 1122 } -- Imp, Voidwalker, Succubus, Felhunter, Inferno
local GROWL = 2649

local MOODS = { [1] = "UNHAPPY", [2] = "CONTENT", [3] = "HAPPY" }
local MOOD_TOKEN = { [1] = "danger", [2] = "accent", [3] = "text" }
local STANCES = {
	PET_MODE_AGGRESSIVE = "AGGRESSIVE", PET_MODE_DEFENSIVE = "DEFENSIVE",
	PET_MODE_PASSIVE = "PASSIVE", PET_MODE_ASSIST = "ASSIST", PET_MODE_DEFENSIVEASSIST = "DEFENSIVE",
}
local COMMANDS = { PET_ACTION_FOLLOW = "FOLLOWING", PET_ACTION_WAIT = "STAYING", PET_ACTION_MOVE_TO = "MOVING" }

-- A bar's colour now, for updates (UI.paint is for building: it also
-- keeps the colour through theme changes).
local function tint(sb, token, alpha)
	local r, g, b = Stoa:Color(token)
	sb:SetStatusBarColor(r, g, b, alpha or 1)
end

local function knows(id)
	if C_SpellBook and C_SpellBook.IsSpellKnown then
		local ok, known = pcall(C_SpellBook.IsSpellKnown, id)
		if ok and known then return true end
	end
	return IsPlayerSpell and plain(IsPlayerSpell(id)) or false
end

local function spellName(id)
	local name = C_Spell and C_Spell.GetSpellName and Stoa.safe.call(C_Spell.GetSpellName, id)
	return type(name) == "string" and not Stoa:IsSecret(name) and name or nil
end

function Pet:Keeper()
	if knows(CALL_PET) then return "HUNTER" end
	for _, id in ipairs(SUMMONS) do
		if knows(id) then return "WARLOCK" end
	end
end

-- The demo (/stoa pet demo) draws every piece with your own character
-- standing in for a pet, so the look can be judged without one.
local function unit()
	return Pet.demo and "player" or "pet"
end

local function hasPet()
	if Pet.demo then return true end
	return plain(UnitExists("pet")) and true or false
end

-- Health as a plain fraction, or nil while the game hides it.
local function healthFraction(unit)
	local h, m = UnitHealth(unit), UnitHealthMax(unit)
	if Stoa:IsSecret(h) or Stoa:IsSecret(m) or not m or m <= 0 then return nil end
	return h / m
end

function Pet:Mood()
	if self.demo then return 3 end
	if not (C_PetInfo and C_PetInfo.GetPetHappiness) or not hasPet() then return nil end
	local ok, happiness = pcall(C_PetInfo.GetPetHappiness)
	happiness = ok and plain(happiness)
	return MOODS[happiness or 0] and happiness or nil
end

-- The pet bar's current stance and command, from Blizzard's tokens.
function Pet:Stance()
	if self.demo then return "DEFENSIVE", "FOLLOWING" end
	if not GetPetActionInfo then return nil end
	local stance, command
	for i = 1, (NUM_PET_ACTION_SLOTS or 10) do
		local name, _, isToken, isActive = GetPetActionInfo(i)
		if isToken and plain(isActive) then
			stance = stance or STANCES[name]
			command = command or COMMANDS[name]
		end
	end
	return stance, command
end

function Pet:GrowlOn()
	local growl = spellName(GROWL)
	if not growl or not GetPetActionInfo then return false end
	for i = 1, (NUM_PET_ACTION_SLOTS or 10) do
		local name, _, isToken, _, allowed, enabled = GetPetActionInfo(i)
		if not isToken and name == growl then return plain(allowed) and plain(enabled) and true or false end
	end
	return false
end

-- Words -----------------------------------------------------------------------

function Pet:Words()
	local out = {}
	if not self.db.words or not self.enabled then return out end
	local keeper = self:Keeper()
	local fighting = Stoa:GetState() == Stoa.STATE_COMBAT
	if hasPet() then
		self.char().dead = nil
		if fighting then
			local fraction = healthFraction("pet")
			if fraction and fraction < LOW then out[#out + 1] = "PET LOW" end
			if self:Stance() == "PASSIVE" then out[#out + 1] = "PET PASSIVE" end
		elseif self:Mood() == 1 then
			out[#out + 1] = "FEED " .. (plain(UnitName("pet")) or "PET"):upper()
		end
		if IsInGroup() and Stoa:GetRole() ~= "TANK" and self:GrowlOn() then out[#out + 1] = "GROWL ON" end
	elseif keeper and not fighting and not plain(IsMounted()) and not plain(UnitOnTaxi("player"))
		and not plain(UnitIsDeadOrGhost("player")) then
		if self.char().dead and knows(REVIVE_PET) then
			out[#out + 1] = "PET DEAD, REVIVE"
		elseif not (Stoa.aura.byName and Stoa.aura.byName("player", Stoa.Spells.unsureName(18788, "Demonic Sacrifice"))) then
			out[#out + 1] = "CALL PET"
		end
	end
	return out
end

function Pet.char()
	Stoa.char.pet = Stoa.char.pet or {}
	return Stoa.char.pet
end

function Pet:Changed()
	local halo = Stoa.modules.Halo
	if halo and halo.enabled and halo.UpdateReminders then xpcall(halo.UpdateReminders, Stoa.catch, halo) end
end

-- The plaque ------------------------------------------------------------------

function Pet:BuildPlaque()
	local frame = CreateFrame("Frame", "StoaPetPlaque", UIParent)
	frame:SetFrameStrata("LOW")
	frame:SetSize(PLAQUE_WIDTH, PLAQUE_HEIGHT)
	frame:SetAlpha(0)
	frame:EnableMouse(false)
	-- No plate: the pet is a ring on the Halo (see below), in every style.

	-- The words sit in a column centred top to bottom, with room between
	-- each group (caption, name, bars, the line underneath).
	local column = CreateFrame("Frame", nil, frame)
	column:SetPoint("LEFT", PAD, 0)
	column:SetPoint("RIGHT", -COIN_SPACE, 0)
	column:SetHeight(86)
	local width = PLAQUE_WIDTH - PAD - COIN_SPACE

	local caption = UI.caption(column, "")
	caption:SetPoint("TOPLEFT")
	local word = UI.caption(column, "")
	word:SetPoint("TOPRIGHT")
	local name = UI.text(column, "serif", Stoa.typeSize.title, "text", "LEFT")
	name:SetPoint("TOPLEFT", caption, "BOTTOMLEFT", 0, -8)
	name:SetWidth(width - 50)
	name:SetWordWrap(false)
	local percent = UI.text(column, "serif", Stoa.typeSize.title, "text", "RIGHT")
	percent:SetPoint("TOPRIGHT", word, "BOTTOMRIGHT", 0, -8)
	local hp = UI.bar(column, width, 7, "health")
	hp:SetPoint("TOPLEFT", name, "BOTTOMLEFT", 0, -8)
	local power = UI.bar(column, width, 3, "accent")
	power:SetPoint("TOPLEFT", hp, "BOTTOMLEFT", 0, -8)
	local foot = UI.caption(column, "")
	foot:SetPoint("TOPLEFT", power, "BOTTOMLEFT", 0, -10)
	local on = UI.text(column, "sans", Stoa.typeSize.caption, "text", "LEFT")
	on:SetPoint("LEFT", foot, "RIGHT", 4, 0)
	on:SetWidth(width - 90)
	on:SetWordWrap(false)

	-- A companion ring at the foot of the pet's arc on the Halo, as if the
	-- arc grew out of it. The portrait in a ring that carries the pet's
	-- colour (red when it is low), its name and one line beside it inside
	-- the Halo, the percent under the ring. No plate at all.
	do
		frame.ring = true
		frame:SetSize(RING, RING)
		caption:Hide()
		word:Hide()
		hp:Hide()
		power:Hide()
		local gap = UI.circle(frame, "BACKGROUND", 0, RING, "panel", 1)
		gap:SetPoint("CENTER")
		local band = UI.circle(frame, "BORDER", 0, RING - 2, "accent", 1)
		band:SetPoint("CENTER")
		local face = CreateFrame("Frame", nil, frame)
		face:SetAllPoints()
		face:SetFrameLevel(frame:GetFrameLevel() + 2)
		local inset = UI.circle(face, "BACKGROUND", 0, RING - 6, "panel", 1)
		inset:SetPoint("CENTER")
		local portrait = UI.circle(face, "ARTWORK", 0, RING - 8)
		portrait:SetPoint("CENTER")
		frame.band, frame.portrait = band, portrait
		Stoa:SetFont(name, "serif", Stoa.typeSize.label, "OUTLINE")
		name:ClearAllPoints()
		name:SetPoint("LEFT", frame, "RIGHT", 6, 9)
		name:SetWidth(0)
		foot:ClearAllPoints()
		foot:SetPoint("BOTTOMLEFT", name, "TOPLEFT", 0, 4)
		on:ClearAllPoints()
		on:SetPoint("BOTTOMLEFT", name, "TOPLEFT", 0, 4)
		on:SetWidth(0)
		Stoa:SetFont(percent, "sans", Stoa.typeSize.caption, "OUTLINE")
		percent:ClearAllPoints()
		percent:SetPoint("TOP", frame, "BOTTOM", 0, -3)
	end
	frame.caption, frame.word, frame.name, frame.percent = caption, word, name, percent
	frame.hp, frame.power, frame.foot, frame.on = hp, power, foot, on
	for _, fs in ipairs({ caption, word, name, percent, foot, on }) do UI.legible(fs) end
	self.plaqueFrame = frame
	self:PlacePlaque()
	Stoa:RegisterMover("pet", frame, "Pet plaque", { default = function() self:PlacePlaque() end })

	-- Clicks: target the pet, right click its menu; in a fight, laid over
	-- the plaque while the pet is out. Click-casting binds work on it too.
	local clicker = CreateFrame("Button", "StoaPetClicks", UIParent, "SecureUnitButtonTemplate")
	clicker:SetFrameStrata("LOW")
	clicker:SetFrameLevel(frame:GetFrameLevel() + 5)
	clicker:SetAllPoints(frame)
	clicker:SetAttribute("unit", "pet")
	clicker:SetAttribute("type1", "target")
	clicker:SetAttribute("type2", "togglemenu")
	clicker:RegisterForClicks("AnyUp")
	clicker:SetScript("OnEnter", function(button)
		GameTooltip_SetDefaultAnchor(GameTooltip, button)
		GameTooltip:SetUnit("pet")
	end)
	clicker:SetScript("OnLeave", GameTooltip_Hide)
	RegisterStateDriver(clicker, "visibility", "[combat,@pet,exists] show; hide")
	Stoa:RegisterClickFrame(clicker)
end

-- Ground line: the room the pet's ring takes in the row left of the health
-- number, for the pieces that stand further out. Nothing without a pet class.
function Pet:LineRoom()
	if not (self.plaqueFrame and (self.demo or self:Keeper())) then return 0 end
	return LINE_CLEAR + RING + 8
end

-- Where the tank watch goes, at the Halo's upper left; a healer keeps that
-- spot for the watch, so the pet sits just under it.
function Pet:PlacePlaque()
	local frame, halo = self.plaqueFrame, _G.StoaHalo
	if not frame or Stoa:HasSavedPosition("pet") then return end
	frame:ClearAllPoints()
	local module = Stoa.modules.Halo
	if frame.ring and halo and module and module.Rail and module:Rail() then
		-- Side rail: the ring hangs under the rails, its name beside it.
		local rail = module.RAIL
		frame:SetPoint("TOP", halo, "CENTER", -(rail.x + rail.width + rail.gap / 2), rail.bottom - 8)
		frame.percent:ClearAllPoints()
		frame.percent:SetPoint("LEFT", frame.name, "RIGHT", 6, 0)
		return
	end
	if frame.ring and halo and module and module.Line and module:Line() then
		-- Ground line: the ring stands off to the left in the line's own
		-- row, just past the health number; the emergency button and your
		-- buffs step further out to make room (LineRoom). Its words stack
		-- over it and the percent under it, so nothing reaches sideways.
		local line = module.LINE
		frame:SetPoint("RIGHT", halo, "BOTTOM", -(line.gap + line.width + (line.numbers and 14 or 76) + LINE_CLEAR), line.y)
		frame.name:ClearAllPoints()
		frame.name:SetPoint("BOTTOM", frame, "TOP", 0, 3)
		frame.name:SetJustifyH("CENTER")
		for _, fs in ipairs({ frame.foot, frame.on }) do
			fs:ClearAllPoints()
			fs:SetPoint("BOTTOM", frame.name, "TOP", 0, 2)
			fs:SetJustifyH("CENTER")
		end
		return
	end
	if frame.ring and halo then
		-- At the foot of the pet's arc (see BuildArc for its size).
		local radius, at = halo:GetHeight() * 0.44, math.rad(RING_AT)
		frame:SetPoint("CENTER", halo, "CENTER", -radius * math.cos(at), -radius * math.sin(at))
		return
	end
	frame:SetPoint("CENTER", UIParent, "CENTER", -300, 120)
end

function Pet:UpdatePlaque()
	local frame = self.plaqueFrame
	if not frame then return end
	-- The demo shows it at rest too, unless the card is there to look at.
	-- The ring by the Halo only shows in a fight: at rest the console's
	-- own card stands in for it, even in the demo.
	local show = self.db.plaque and hasPet() and (Stoa:GetState() == Stoa.STATE_COMBAT or Stoa.previewing or (self.demo and not self.card))
	frame:SetAlpha(show and 1 or 0)
	if not hasPet() then return end

	local level = plain(UnitLevel(unit()))
	local family = plain(UnitCreatureFamily and UnitCreatureFamily(unit()))
	local kind = plain(UnitCreatureType(unit()))
	local words = { self:Keeper() == "WARLOCK" and "DEMON" or "PET" }
	if level then words[#words + 1] = "LEVEL " .. level end
	if family and family ~= "" then words[#words + 1] = family:upper()
	elseif kind then words[#words + 1] = kind:upper() end
	frame.caption:SetText(Stoa.UI.join(words))

	frame.name:SetText(self.demo and "Ashmane" or UnitName(unit()))
	UI.setUnitBar(frame.hp, unit(), "health")
	UI.setHealthPercent(frame.percent, unit(), nil, frame.ring)
	UI.setUnitBar(frame.power, unit(), "power")
	local powerType = plain(UnitPowerType(unit()))
	tint(frame.power, powerType == 0 and "mana" or "accent", powerType == 0 and 1 or 0.75)

	-- One word at the top right: dead, low, else the mood.
	local dead = plain(UnitIsDead(unit()))
	local fraction = healthFraction(unit())
	local mood = self:Mood()
	local word, token = "", "muted"
	if dead then
		word, token = "DEAD", Stoa:StateToken("DEAD")
	elseif fraction and fraction < LOW then
		word, token = "LOW", "danger"
	elseif mood then
		word, token = MOODS[mood], MOOD_TOKEN[mood]
	end
	frame.word:SetText(word)
	frame.word:SetTextColor(Stoa:Color(token))
	frame.hp:SetStatusBarColor(Stoa:Color(word == "LOW" and "danger" or "health"))
	frame:SetAlpha(show and (dead and 0.6 or 1) or 0)

	local stance, command = self:Stance()
	local foot = {}
	if mood == 1 then foot[#foot + 1] = "DOES LESS DAMAGE, FEED IT"
	elseif stance then foot[#foot + 1] = stance end
	local target = UnitExists("pettarget")
	if plain(target) and mood ~= 1 then
		foot[#foot + 1] = "ON"
		frame.on:SetText(UnitName("pettarget"))
	else
		if command and mood ~= 1 then foot[#foot + 1] = command end
		frame.on:SetText("")
	end
	if frame.ring then
		SetPortraitTexture(frame.portrait, unit())
		local r, g, b = Stoa:Color((dead or word == "LOW") and "danger" or "accent")
		frame.band:SetVertexColor(r, g, b, 1)
		frame.percent:SetTextColor(r, g, b)
		-- One line over the name, the most pressing first.
		local onName = plain(target) and plain(UnitName("pettarget"))
		local line = dead and "DEAD" or word == "LOW" and "LOW" or mood == 1 and "FEED IT" or ""
		frame.on:SetText(line == "" and onName and ("On " .. onName) or "")
		frame.foot:SetText(line ~= "" and line or onName and "" or stance or "")
		frame.foot:SetTextColor(Stoa:Color(line ~= "" and "danger" or "muted"))
		return
	end
	frame.foot:SetText(Stoa.UI.join(foot))
end

-- The card --------------------------------------------------------------------
-- At rest the pet has a card of its own left of yours, the mirror of the
-- target's on the right, contents flipped too: on Slate a twin of your
-- card, on Leather and Matte a block docked on the console's rim, coming
-- out of the medallion's left as the target's comes out of its right
-- (Matte gives it a tab with a cone for the portrait, like the target's).
-- It belongs to the console and fades with it; clicks go to the coin's
-- button, laid over it on the screen (see BuildCoin).
local CARD_H, CARD_PAD, CARD_GAP = 50, 11, 10
local CARD_NAME_W, CARD_NAME_GAP = 124, 12
local CARD_W_LEAST = 260

function Pet:CardWidth()
	local halo = Stoa.modules.Halo
	return math.max(CARD_W_LEAST, halo and halo.TwinWidth and halo:TwinWidth() or CARD_W_LEAST)
end

-- Leather and Matte: the docked block's rows, from its medallion end.
local DOCK_Y, DOCK_TEXT = -1, 60
local DOCK_NAME_W, DOCK_BAR_W = 110, 110

-- Where the card stands on the screen: its right end's x from the
-- screen's centre, its bottom from the screen's bottom, its size.
function Pet:CardSpot()
	local console, card = Stoa.modules.Grimoire, self.card
	if card.docked then
		return -card.docked, console:OpenHeight() + DOCK_Y, card:GetWidth(), card:GetHeight()
	end
	local you = console.YOU_CARD
	return -(you.width / 2 + CARD_GAP), console:OpenHeight() + you.y - you.height / 2, self:CardWidth(), CARD_H
end

-- Leather (the drawn console) and Matte, open full size: the docked block.
function Pet:BuildDockCard(console)
	local matte = console:Matte()
	if console.db.slim or not (matte or console:Art()) then return end
	local x = matte and console.MATTE_DOCK_X or UI.PLAQUE_SOCKET_X
	local near = matte and console.MATTE_DOCK_TEXT or DOCK_TEXT
	local h = UI.plaqueDockHeight()
	local curve = near + DOCK_NAME_W + CARD_NAME_GAP + DOCK_BAR_W + 8
	local card = CreateFrame("Frame", nil, console.frame)
	card:SetSize(curve + UI.PLAQUE_JOIN_SPAN, h)
	card:SetPoint("BOTTOMRIGHT", console.frame, "TOP", -x, DOCK_Y)
	card.docked = x
	card.plate = UI.dockPlate(card, true)
	card.plate:Layout(curve)
	-- The tab stands only while a pet is out, and only for the classes
	-- that have one.
	local class = select(2, UnitClass("player"))
	if matte and (class == "HUNTER" or class == "WARLOCK") then
		card.cone = console:BuildCone(console.frame, true)
		card.cone.holder:Hide()
	end
	console:AddPage(card)

	-- The name and stance by the medallion, the bar beyond them with the
	-- percent and one word under it.
	local top = math.floor(h / 2) - 14
	local name = UI.text(card, "serif", Stoa.typeSize.label, "text", "RIGHT")
	name:SetPoint("TOPRIGHT", -near, -top)
	name:SetWidth(DOCK_NAME_W)
	name:SetWordWrap(false)
	local doing = UI.caption(card, "")
	doing:SetPoint("TOPRIGHT", name, "BOTTOMRIGHT", 0, -5)
	doing:SetWidth(DOCK_NAME_W)
	doing:SetJustifyH("RIGHT")
	doing:SetWordWrap(false)
	local hp = UI.bar(card, DOCK_BAR_W, 8, "health")
	hp:SetPoint("TOPRIGHT", -(near + DOCK_NAME_W + CARD_NAME_GAP), -(top + 3))
	local power = UI.bar(card, DOCK_BAR_W, 3, "accent")
	power:SetPoint("TOPLEFT", hp, "BOTTOMLEFT", 0, -3)
	local word = UI.caption(card, "")
	word:SetPoint("TOPRIGHT", power, "BOTTOMRIGHT", 0, -5)
	local percent = UI.text(card, "sans", Stoa.typeSize.body, "muted", "LEFT")
	percent:SetPoint("TOPLEFT", power, "BOTTOMLEFT", 0, -3)
	card.name, card.doing, card.hp, card.power, card.word, card.percent = name, doing, hp, power, word, percent
	card:Hide()
	self.card = card
	return card
end

function Pet:BuildCard()
	local console = Stoa.modules.Grimoire
	if not (console and console.enabled and console.frame) then return end
	if not (console.youCard and console.SlatePlate and console.YOU_CARD) then return self:BuildDockCard(console) end
	local you = console.YOU_CARD
	local card = CreateFrame("Frame", nil, console.frame)
	card:SetSize(self:CardWidth(), CARD_H)
	card:SetPoint("RIGHT", console.frame, "TOP", -(you.width / 2 + CARD_GAP), you.y)
	card:SetFrameLevel(console.youCard:GetFrameLevel())
	console.SlatePlate(card)
	console:AddPage(card)

	-- The target card's layout flipped: the name and stance on the right,
	-- next to you, the bar on the left with its percent at the outer end.
	local name = UI.text(card, "serif", Stoa.typeSize.label, "text", "RIGHT")
	name:SetPoint("TOPRIGHT", -CARD_PAD, -10)
	name:SetWidth(CARD_NAME_W)
	name:SetWordWrap(false)
	local doing = UI.caption(card, "")
	doing:SetPoint("TOPRIGHT", -CARD_PAD, -30)
	doing:SetWidth(CARD_NAME_W)
	doing:SetJustifyH("RIGHT")
	doing:SetWordWrap(false)
	local right = CARD_PAD + CARD_NAME_W + CARD_NAME_GAP
	local hp = UI.bar(card, 10, 8, "health")
	hp:SetPoint("TOPLEFT", CARD_PAD, -13)
	hp:SetPoint("RIGHT", -right, 0)
	local power = UI.bar(card, 10, 3, "accent")
	power:SetPoint("TOPLEFT", hp, "BOTTOMLEFT", 0, -3)
	power:SetPoint("RIGHT", hp, "RIGHT")
	local word = UI.caption(card, "")
	word:SetPoint("RIGHT", card, "TOPRIGHT", -right, -37)
	local percent = UI.text(card, "sans", Stoa.typeSize.body, "muted", "LEFT")
	percent:SetPoint("LEFT", card, "TOPLEFT", CARD_PAD, -37)
	card.name, card.doing, card.hp, card.power, card.word, card.percent = name, doing, hp, power, word, percent
	card:Hide()
	self.card = card
	return card
end

function Pet:UpdateCard()
	local card = self.card
	if not card then return end
	local show = hasPet()
	local was = card:IsShown()
	card:SetShown(show)
	if card.cone then
		card.cone.holder:SetShown(show)
		if show then SetPortraitTexture(card.cone.portrait, unit()) end
	end
	if not show then return end
	if card.plate and not was then card.plate:PlayDock() end
	if not card.docked then card:SetWidth(self:CardWidth()) end
	card.name:SetText(self.demo and "Ashmane" or UnitName(unit()))
	UI.setUnitBar(card.hp, unit(), "health")
	UI.setHealthPercent(card.percent, unit(), nil, true)
	UI.setUnitBar(card.power, unit(), "power")
	local powerType = plain(UnitPowerType(unit()))
	tint(card.power, powerType == 0 and "mana" or "accent", powerType == 0 and 1 or 0.75)

	local dead = plain(UnitIsDead(unit()))
	local fraction = healthFraction(unit())
	local low = fraction and fraction < LOW
	local mood = self:Mood()
	local stance, command = self:Stance()
	-- One word under the bar, the most pressing first. Following is the
	-- usual state and goes unsaid; staying or moving is worth a word.
	local word, token = "", "muted"
	if dead then
		word, token = "DEAD", "danger"
	elseif mood == 1 then
		word, token = "FEED IT", "danger"
	elseif low then
		word, token = "LOW", "danger"
	elseif mood == 2 then
		word, token = MOODS[mood], "accent"
	elseif command and command ~= "FOLLOWING" then
		word = command
	elseif mood then
		word = MOODS[mood]
	end
	card.word:SetText(word)
	card.word:SetTextColor(Stoa:Color(token))
	card.hp:SetStatusBarColor(Stoa:Color(low and "danger" or "health"))

	-- The stance alone fits the name's column whole.
	card.doing:SetText(stance or "")
end

-- The arc ---------------------------------------------------------------------

function Pet:BuildArc()
	local halo = _G.StoaHalo
	if not halo then return end
	-- Ground line: the pet's health is a hairline riding on your own bar.
	local module = Stoa.modules.Halo
	if module and module.Rail and module:Rail() then
		-- Side rail: a third, thinner upright just inside your health.
		local rail = module.RAIL
		local sb = CreateFrame("StatusBar", nil, halo)
		sb:SetSize(3, rail.height)
		sb:SetOrientation("VERTICAL")
		sb:SetPoint("BOTTOMLEFT", halo, "CENTER", -(rail.x - 5), rail.bottom)
		sb:SetStatusBarTexture(UI.WHITE)
		UI.paint(sb, "accent", 0.7)
		local track = sb:CreateTexture(nil, "BACKGROUND")
		track:SetPoint("TOPLEFT", -1, 1)
		track:SetPoint("BOTTOMRIGHT", 1, -1)
		track:SetColorTexture(0.04, 0.05, 0.06, 0.6)
		sb:SetMinMaxValues(0, 1)
		sb:SetValue(0)
		sb:Hide()
		self.arcBar = sb
		return
	end
	if module and module.Line and module:Line() then
		local line = module.LINE
		local sb = CreateFrame("StatusBar", nil, halo)
		sb:SetSize(line.width, 3)
		sb:SetPoint("BOTTOMRIGHT", halo, "BOTTOM", -line.gap, line.y + (line.top or line.height / 2) + 4)
		sb:SetStatusBarTexture(UI.WHITE)
		if sb.SetReverseFill then sb:SetReverseFill(true) end
		UI.paint(sb, "accent", 0.7)
		local track = sb:CreateTexture(nil, "BACKGROUND")
		track:SetPoint("TOPLEFT", -1, 1)
		track:SetPoint("BOTTOMRIGHT", 1, -1)
		track:SetColorTexture(0.04, 0.05, 0.06, 0.6)
		sb:SetMinMaxValues(0, 1)
		sb:SetValue(0)
		sb:Hide()
		self.arcBar = sb
		return
	end
	local size = halo:GetHeight() * 0.88
	local file = UI.MEDIA .. "Textures\\HaloArcLeft"
	local sb = CreateFrame("StatusBar", nil, halo)
	sb:SetSize(size / 2, size)
	sb:SetPoint("LEFT", halo, "LEFT", halo:GetHeight() * 0.06, 0)
	sb:SetOrientation("VERTICAL")
	sb:SetStatusBarTexture(file)
	UI.paint(sb, "accent", 0.7)
	local track = sb:CreateTexture(nil, "BACKGROUND")
	track:SetAllPoints()
	track:SetTexture(file)
	UI.tint(track, "panel", 0.35)
	sb:SetMinMaxValues(0, 1)
	sb:SetValue(0)
	sb:Hide()
	self.arcBar = sb
end

function Pet:UpdateArc()
	local sb = self.arcBar
	if not sb then return end
	local show = self.db.arc and hasPet()
	sb:SetShown(show)
	if not show then return end
	UI.setUnitBar(sb, unit(), "health")
	local fraction = healthFraction(unit())
	tint(sb, fraction and fraction < LOW and "danger" or "accent", 0.7)
end

-- What the demo's row holds: attack, follow, stay, four spells, then
-- aggressive, defensive, passive.
local ICONS = "Interface\\Icons\\"
local DEMO_ICONS = {
	ICONS .. "Ability_GhoulFrenzy", ICONS .. "Ability_Tracking", ICONS .. "Spell_Nature_TimeStop",
	ICONS .. "Ability_Physical_Taunt", ICONS .. "Ability_Racial_Cannibalize", ICONS .. "Ability_Druid_Dash",
	ICONS .. "Ability_Druid_Rake",
	ICONS .. "Ability_Racial_BloodRage", ICONS .. "Ability_Defend", ICONS .. "Ability_Seal",
}

-- The pet row -----------------------------------------------------------------
-- Secure buttons that click Blizzard's own pet buttons, so left casts and
-- right toggles autocast just as on the pet bar, and dragging stays theirs.

function Pet:BuildRow()
	local row = CreateFrame("Frame", "StoaPetRow", UIParent)
	row:SetFrameStrata("LOW")
	local count = NUM_PET_ACTION_SLOTS or 10
	row:SetSize(count * ROW_SIZE + (count - 1) * ROW_GAP + 2 * ROW_BREAK, ROW_SIZE)
	self.row = row
	self.rowButtons = {}
	local x = 0
	for i = 1, count do
		local button = CreateFrame("Button", "StoaPetButton" .. i, row, "SecureActionButtonTemplate")
		button:SetSize(ROW_SIZE, ROW_SIZE)
		button:SetPoint("LEFT", row, "LEFT", x, 0)
		x = x + ROW_SIZE + ROW_GAP + ((i == 3 or i == 7) and ROW_BREAK or 0)
		button:RegisterForClicks("AnyUp")
		button:SetAttribute("type", "click")
		button:SetAttribute("clickbutton", _G["PetActionButton" .. i])
		local icon = button:CreateTexture(nil, "ARTWORK")
		icon:SetAllPoints()
		icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
		local mask = button:CreateMaskTexture()
		mask:SetAllPoints()
		mask:SetTexture(UI.MEDIA .. "Textures\\ButtonMask", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
		icon:AddMaskTexture(mask)
		button.icon = icon
		button.edge = UI.roundBorder(button, "CardEdge.tga", 1, 0)
		-- Autocast: a second, outer line in the accent.
		button.auto = UI.roundBorder(button, "CardEdge.tga", 1, 3)
		local cooldown = CreateFrame("Cooldown", nil, button, "CooldownFrameTemplate")
		cooldown:SetAllPoints()
		cooldown:SetSwipeTexture(UI.MEDIA .. "Textures\\ButtonMask")
		cooldown:SetDrawEdge(false)
		cooldown:SetHideCountdownNumbers(true)
		button.cooldown = cooldown
		button:SetScript("OnEnter", function(b)
			if not GameTooltip.SetPetAction then return end
			GameTooltip:SetOwner(b, "ANCHOR_TOP")
			GameTooltip:SetPetAction(i)
			GameTooltip:Show()
		end)
		button:SetScript("OnLeave", GameTooltip_Hide)
		self.rowButtons[i] = button
	end
	local label = UI.caption(row, "Pet")
	label:SetPoint("RIGHT", row, "LEFT", -8, 0)
	UI.legible(label)
	row.label = label
	RegisterStateDriver(row, "visibility", self:RowRule())
	Stoa:RegisterMover("petrow", row, "Pet row", { default = function() self:PlaceRow() end })
	self:PlaceRow()
end

function Pet:RowRule()
	return self.card and ROW_RULE_REST or ROW_RULE
end

-- Under the combat bar's last row; the party row moves down to make room.
-- At rest: standing on the pet's card, its right end over the card's.
-- Pinned to the screen, never to the console, which folds.
function Pet:PlaceRow()
	local row, halo = self.row, _G.StoaHalo
	if not row or not halo or InCombatLockdown() or Stoa:HasSavedPosition("petrow") then return end
	local resting = self.card and Stoa:GetState() == Stoa.STATE_WORLD
	if row.label then row.label:SetShown(not resting) end
	if resting then
		local x, y, _, h = self:CardSpot()
		row:ClearAllPoints()
		row:SetPoint("BOTTOMRIGHT", UIParent, "BOTTOM", x, y + h + 6)
		return
	end
	local bar = Stoa.modules.CombatBar
	local offset = bar and bar.enabled and bar.groupOffset and (bar.groupOffset - (bar.shift or 0))
	if not offset then
		-- No combat bar: under the healer's group when it stands there.
		local under = Stoa.HealerRowBottom and Stoa:HealerRowBottom()
		offset = under and -(under + 8) or -52
	end
	row:ClearAllPoints()
	row:SetPoint("TOP", halo, "BOTTOM", 0, offset - 4)
end

function Pet:UpdateRow()
	if not self.rowButtons then return end
	if not GetPetActionInfo then return end
	local r, g, b = Stoa:Color("accent")
	for i, button in ipairs(self.rowButtons) do
		local _, texture, isToken, isActive, allowed, enabled = GetPetActionInfo(i)
		if isToken and texture then texture = _G[texture] end
		if self.demo and not texture then
			texture, isActive, allowed, enabled = DEMO_ICONS[i], i == 2 or i == 9, i == 4, i == 4
		end
		button.icon:SetTexture(texture)
		button:SetAlpha(texture and 1 or 0.25)
		local active = plain(isActive)
		if active then
			button.edge:Set(r, g, b, 1)
		else
			local tr, tg, tb = Stoa:Color("text")
			button.edge:Set(tr, tg, tb, 0.3)
		end
		if plain(allowed) and plain(enabled) then button.auto:Set(r, g, b, 0.9) else button.auto:Clear() end
		local ok, start, duration = pcall(GetPetActionCooldown, i)
		if ok and start and duration and not Stoa:IsSecret(start) and duration > 0 then
			button.cooldown:SetCooldown(start, duration)
		else
			button.cooldown:Clear()
		end
	end
end

-- The coin on the medallion -------------------------------------------------

function Pet:FoodSlot()
	if not (C_PetInfo and C_PetInfo.CanPetEatItem and Stoa.Items) then return nil end
	local found
	Stoa.Items.eachBagSlot(function(bag, slot, info)
		if found or not info.itemID then return end
		local ok, can = pcall(C_PetInfo.CanPetEatItem, info.itemID)
		if ok and can then found = { bag, slot, info.itemID } end
	end)
	return found
end

-- With a card the coin draws nothing: its button is laid over the
-- card as the thing that takes the clicks.
function Pet:PlaceCoin()
	local coin, card = self.coin, self.card
	if not (coin and card) or InCombatLockdown() then return end
	local x, y, w, h = self:CardSpot()
	coin:ClearAllPoints()
	coin:SetSize(w, h)
	-- On the screen where the open console holds the card, never on the
	-- console itself, which folds in a fight.
	coin:SetPoint("BOTTOMRIGHT", UIParent, "BOTTOM", x, y)
end

function Pet:BuildCoin()
	local console = Stoa.modules.Grimoire
	if not (console and console.enabled and console.seal) then return end
	local coin = CreateFrame("Button", "StoaPetCoin", UIParent, "SecureActionButtonTemplate")
	coin:SetSize(COIN, COIN)
	coin:SetFrameStrata("LOW")
	coin:SetFrameLevel(console.seal:GetFrameLevel() + 6)
	-- Pinned to the seal's own button, which stays put on the screen, never
	-- to the console, which folds in a fight.
	local seal = _G.StoaSealButton or console.seal
	coin:SetPoint("CENTER", seal, "BOTTOMLEFT", 0, 12)
	coin:RegisterForClicks("AnyUp")
	coin:SetAttribute("type1", "macro")
	coin:SetAttribute("type2", "target")
	coin:SetAttribute("unit", "pet")

	local gap = UI.circle(coin, "BACKGROUND", 0, COIN)
	gap:SetPoint("CENTER")
	UI.paint(gap, "panel", 1)
	local track = UI.circle(coin, "BORDER", 0, COIN - 2)
	track:SetPoint("CENTER")
	UI.paint(track, "text", 0.15)
	-- The portrait sits on its own layer over the ring, so the ring shows
	-- only as the band around it.
	local face = CreateFrame("Frame", nil, coin)
	face:SetAllPoints()
	face:SetFrameLevel(coin:GetFrameLevel() + 3)
	local inset = UI.circle(face, "BACKGROUND", 0, COIN - 6)
	inset:SetPoint("CENTER")
	UI.paint(inset, "panel", 1)
	local portrait = UI.circle(face, "ARTWORK", 0, COIN - 10)
	portrait:SetPoint("CENTER")
	-- Health as a ring: a swipe frozen at the fraction, out of a fight only.
	local ring = CreateFrame("Cooldown", nil, coin, "CooldownFrameTemplate")
	ring:SetSize(COIN - 2, COIN - 2)
	ring:SetPoint("CENTER")
	ring:SetDrawEdge(false)
	ring:SetDrawBling(false)
	ring:SetHideCountdownNumbers(true)
	ring:SetReverse(true)
	if ring.SetSwipeTexture then ring:SetSwipeTexture(UI.CIRCLE_MASK or (UI.MEDIA .. "Textures\\ButtonMask")) end
	ring:SetFrameLevel(coin:GetFrameLevel() + 1)

	local mood = UI.caption(coin, "")
	mood:SetPoint("TOP", coin, "BOTTOM", 0, -6)
	local name = UI.caption(coin, "")
	name:SetPoint("TOP", mood, "BOTTOM", 0, -5)
	UI.legible(mood)
	UI.legible(name)

	coin:SetScript("OnEnter", function(b)
		GameTooltip:SetOwner(b, "ANCHOR_TOP")
		GameTooltip:SetUnit("pet")
		if b.food then
			GameTooltip:AddLine(("Click to feed it %s."):format(b.foodName or "food"), 1, 1, 1)
		elseif self:Mood() and self:Mood() < 3 then
			GameTooltip:AddLine("No food it eats in your bags.", 0.7, 0.7, 0.7)
		end
		GameTooltip:AddLine("Right-click to target it.", 0.7, 0.7, 0.7)
		GameTooltip:Show()
	end)
	coin:SetScript("OnLeave", GameTooltip_Hide)
	RegisterStateDriver(coin, "visibility", COIN_RULE)
	coin.portrait, coin.ring, coin.mood, coin.nameText, coin.track = portrait, ring, mood, name, track
	self.coin = coin
	if self.card then
		coin.plain = true
		for _, part in ipairs({ gap, track, face, ring, mood, name }) do part:Hide() end
		self:PlaceCoin()
	end
end

function Pet:UpdateCoin()
	local coin = self.coin
	if not coin then return end
	if not hasPet() then return end
	local mood = self:Mood()
	if coin.plain then
		self:PlaceCoin()
	else
		SetPortraitTexture(coin.portrait, unit())
		local fraction = healthFraction(unit())
		local r, g, b = Stoa:Color(fraction and fraction < LOW and "danger" or "health")
		if fraction then
			coin.ring:SetSwipeColor(r, g, b, 1)
			pcall(function()
				coin.ring:SetCooldown(GetTime() - 100 * (1 - fraction), 100)
				coin.ring:Pause()
			end)
		end
		coin.mood:SetText(mood and MOODS[mood] or "")
		coin.mood:SetTextColor(Stoa:Color(mood and MOOD_TOKEN[mood] or "muted"))
		coin.nameText:SetText(self.demo and "ASHMANE" or (plain(UnitName(unit())) or ""):upper())
		coin.mood:SetShown(self.db.coin)
		coin.nameText:SetShown(self.db.coin)
	end

	-- Feeding: a macro set out of combat, only while there's food it eats.
	if InCombatLockdown() then return end
	local food = mood and mood < 3 and self:FoodSlot()
	local feed = spellName(FEED_PET)
	if food and feed then
		coin:SetAttribute("macrotext1", ("/cast %s\n/use %d %d"):format(feed, food[1], food[2]))
		coin.food = true
		coin.foodName = C_Item and C_Item.GetItemNameByID and Stoa.safe.call(C_Item.GetItemNameByID, food[3])
	else
		coin:SetAttribute("macrotext1", "/target pet")
		coin.food, coin.foodName = nil, nil
	end
end

-- Party pets ----------------------------------------------------------------

local OWNERS = { "pet", "partypet1", "partypet2", "partypet3", "partypet4" }

function Pet:BuildCells()
	local party = Stoa.modules.Party
	if not (party and party.enabled and party.cards and party.frame) then return end
	self.cells = {}
	for i, unit in ipairs(OWNERS) do
		local owner = party.cards[i]
		local cell = CreateFrame("Button", "StoaPetCell" .. i, party.frame, "SecureUnitButtonTemplate")
		cell:SetAttribute("unit", unit)
		cell:SetAttribute("type1", "target")
		cell:SetAttribute("type2", "togglemenu")
		cell:RegisterForClicks("AnyUp")
		cell:SetHeight(24)
		cell:SetPoint("TOPLEFT", owner, "BOTTOMLEFT", 10, -6)
		cell:SetPoint("TOPRIGHT", owner, "BOTTOMRIGHT", -10, -6)
		UI.roundPanel(cell, 0.8)
		local hp = CreateFrame("StatusBar", nil, cell)
		hp:SetPoint("TOPLEFT", 1, -1)
		hp:SetPoint("BOTTOMRIGHT", -1, 1)
		hp:SetStatusBarTexture(UI.WHITE)
		hp:SetMinMaxValues(0, 1)
		UI.paint(hp, "health", 0.18)
		local name = UI.text(cell, "sans", Stoa.typeSize.caption, "muted", "LEFT")
		name:SetPoint("LEFT", 8, 0)
		name:SetWidth(100)
		name:SetWordWrap(false)
		local word = UI.caption(cell, "")
		word:SetPoint("RIGHT", -8, 0)
		cell.hp, cell.name, cell.word, cell.unit = hp, name, word, unit
		cell:SetScript("OnEnter", function(b)
			GameTooltip_SetDefaultAnchor(GameTooltip, b)
			GameTooltip:SetUnit(b.unit)
		end)
		cell:SetScript("OnLeave", GameTooltip_Hide)
		cell:Hide()
		Stoa:RegisterClickFrame(cell)
		self.cells[i] = cell
	end
	self:LayoutCells()
end

-- Healers in a party only; out of combat, as the cells are secure.
function Pet:LayoutCells()
	if not self.cells or InCombatLockdown() then return end
	local on = self.db.partyPets and Stoa:GetRole() == "HEALER"
	for _, cell in ipairs(self.cells) do
		UnregisterUnitWatch(cell)
		if on then RegisterUnitWatch(cell) else cell:Hide() end
	end
end

function Pet:UpdateCell(cell)
	if not plain(UnitExists(cell.unit)) then return end
	cell.name:SetText(UnitName(cell.unit))
	UI.setUnitBar(cell.hp, cell.unit, "health")
	local fraction = healthFraction(cell.unit)
	local dead = plain(UnitIsDead(cell.unit))
	local low = fraction and fraction < LOW
	tint(cell.hp, low and "danger" or "health", low and 0.35 or 0.18)
	cell.word:SetText(dead and "DEAD" or low and "LOW" or "")
	cell.word:SetTextColor(Stoa:Color((dead or low) and "danger" or "muted"))
end

function Pet:UpdateCells()
	for _, cell in ipairs(self.cells or {}) do self:UpdateCell(cell) end
end

-- The demo ----------------------------------------------------------------------
-- The row and the coin are shown by the game from whether a pet exists;
-- the demo takes that rule off them while it runs and puts it back after.
-- Feeding and pet commands do nothing in it: there is no pet to take them.
function Pet:SetDemo(on)
	if InCombatLockdown() then
		Stoa:Print("The pet demo can be switched once you're out of the fight.")
		return
	end
	self.demo = on and true or nil
	-- The row beside the ground line opens or closes the ring's place.
	for _, name in ipairs({ "Emergency", "SelfBuffs" }) do
		local module = Stoa.modules[name]
		if module and module.Place then module:Place() end
	end
	for frame, rule in pairs({ [self.row or false] = self:RowRule(), [self.coin or false] = COIN_RULE }) do
		if frame then
			if on then
				UnregisterStateDriver(frame, "visibility")
				frame:Show()
			else
				RegisterStateDriver(frame, "visibility", rule)
			end
		end
	end
	xpcall(self.UpdateAll, Stoa.catch, self)
	Stoa:Print(on and "Pet demo on: your own character stands in for a pet. /stoa pet demo again to end it."
		or "Pet demo off.")
end

Stoa.commands.pet = function(rest)
	if (rest or ""):lower():match("^%s*demo") then
		Pet:SetDemo(not Pet.demo)
	else
		Stoa:Print("/stoa pet demo shows STOA's pet pieces without a pet.")
	end
end

-- Lifecycle -------------------------------------------------------------------

function Pet:UpdateAll()
	self:UpdatePlaque()
	self:UpdateCard()
	self:UpdateArc()
	self:UpdateRow()
	self:UpdateCoin()
	self:UpdateCells()
end

function Pet:Relayout()
	Stoa:AfterCombat(function()
		self:PlaceRow()
		self:LayoutCells()
		local party = Stoa.modules.Party
		if party and party.enabled and party.Layout then xpcall(party.Layout, Stoa.catch, party) end
	end)
end

function Pet:OnEnable()
	if self.db.plaque then self:BuildPlaque() end
	if self.db.arc then self:BuildArc() end
	-- The card first: the row and the coin take their place from it.
	if self.db.coin then self:BuildCard() end
	if self.db.row then self:BuildRow() end
	if self.db.coin then self:BuildCoin() end
	if self.db.partyPets then self:BuildCells() end
	UI.applyTheme()

	local function refresh()
		xpcall(self.UpdateAll, Stoa.catch, self)
		self:Changed()
	end
	Stoa:On("UNIT_PET", function(unit)
		if unit ~= "player" then
			if self.cells then self:UpdateCells() end
			return
		end
		refresh()
		self:Relayout()
	end)
	Stoa:On("PET_BAR_UPDATE", refresh)
	Stoa:On("PET_UI_UPDATE", refresh)
	Stoa:On("PET_BAR_UPDATE_COOLDOWN", function() xpcall(self.UpdateRow, Stoa.catch, self) end)
	Stoa:On("UNIT_HAPPINESS", refresh)
	Stoa:On("STOA_STATE_CHANGED", function()
		refresh()
		-- The row has a resting spot with a card; it moves while it still may.
		if self.card and not InCombatLockdown() then self:PlaceRow() end
	end)
	Stoa:On("PLAYER_REGEN_ENABLED", function() if self.card then self:PlaceRow() end end)
	Stoa:On("STOA_ROLE_CHANGED", function()
		self:PlacePlaque()
		self:Relayout()
	end)
	Stoa:On("STOA_COMBAT_LAYOUT", function() Stoa:AfterCombat(function() self:PlaceRow() end) end)
	Stoa:On("BAG_UPDATE_DELAYED", function() if not InCombatLockdown() then xpcall(self.UpdateCoin, Stoa.catch, self) end end)
	Stoa:On("PLAYER_REGEN_ENABLED", refresh)
	Stoa:OnUnit("UNIT_HEALTH", OWNERS, function(unit)
		if unit == "pet" then
			if plain(UnitIsDead("pet")) then self.char().dead = true end
			xpcall(self.UpdatePlaque, Stoa.catch, self)
			xpcall(self.UpdateCard, Stoa.catch, self)
			xpcall(self.UpdateArc, Stoa.catch, self)
			if not InCombatLockdown() then xpcall(self.UpdateCoin, Stoa.catch, self) end
		end
		for _, cell in ipairs(self.cells or {}) do
			if cell.unit == unit then xpcall(self.UpdateCell, Stoa.catch, self, cell) end
		end
	end)
	Stoa:OnUnit("UNIT_POWER_UPDATE", { "pet" }, function()
		xpcall(self.UpdatePlaque, Stoa.catch, self)
		xpcall(self.UpdateCard, Stoa.catch, self)
	end)
	Stoa:OnUnit("UNIT_TARGET", { "pet" }, function() xpcall(self.UpdatePlaque, Stoa.catch, self) end)
	refresh()
end
