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

local PLAQUE_WIDTH, PLAQUE_HEIGHT = 268, 112
local PAD = 12
local COIN_SPACE = 40
local ROW_SIZE, ROW_GAP, ROW_BREAK = 26, 5, 8
local ROW_ROOM = ROW_SIZE + 12
local COIN = 46
local LOW = 0.35

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

local function hasPet()
	return plain(UnitExists("pet")) and true or false
end

-- Health as a plain fraction, or nil while the game hides it.
local function healthFraction(unit)
	local h, m = UnitHealth(unit), UnitHealthMax(unit)
	if Stoa:IsSecret(h) or Stoa:IsSecret(m) or not m or m <= 0 then return nil end
	return h / m
end

function Pet:Mood()
	if not (C_PetInfo and C_PetInfo.GetPetHappiness) or not hasPet() then return nil end
	local ok, happiness = pcall(C_PetInfo.GetPetHappiness)
	happiness = ok and plain(happiness)
	return MOODS[happiness or 0] and happiness or nil
end

-- The pet bar's current stance and command, from Blizzard's tokens.
function Pet:Stance()
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
			out[#out + 1] = "PET DEAD · REVIVE"
		elseif not (Stoa.aura.byName and Stoa.aura.byName("player", "Demonic Sacrifice")) then
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
	frame.plaque = UI.plaque(frame, "RIGHT")

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
	local hp = UI.bar(column, width, 4, "health")
	hp:SetPoint("TOPLEFT", name, "BOTTOMLEFT", 0, -8)
	UI.engrave(hp, width)
	local power = UI.bar(column, width, 2, "accent")
	power:SetPoint("TOPLEFT", hp, "BOTTOMLEFT", 0, -8)
	local foot = UI.caption(column, "")
	foot:SetPoint("TOPLEFT", power, "BOTTOMLEFT", 0, -10)
	local on = UI.text(column, "sans", Stoa.typeSize.caption, "text", "LEFT")
	on:SetPoint("LEFT", foot, "RIGHT", 4, 0)
	on:SetWidth(width - 90)
	on:SetWordWrap(false)

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

-- Where the tank watch goes, at the Halo's upper left; a healer keeps that
-- spot for the watch, so the pet sits just under it.
function Pet:PlacePlaque()
	local frame, halo = self.plaqueFrame, _G.StoaHalo
	if not frame or Stoa:HasSavedPosition("pet") then return end
	frame:ClearAllPoints()
	if not halo then
		frame:SetPoint("CENTER", UIParent, "CENTER", -300, 120)
	elseif Stoa:GetRole() == "HEALER" then
		frame:SetPoint("TOPRIGHT", halo, "LEFT", -52, 24)
	else
		frame:SetPoint("BOTTOMRIGHT", halo, "LEFT", -52, 30)
	end
end

function Pet:UpdatePlaque()
	local frame = self.plaqueFrame
	if not frame then return end
	local show = self.db.plaque and hasPet() and (Stoa:GetState() == Stoa.STATE_COMBAT or Stoa.previewing)
	frame:SetAlpha(show and 1 or 0)
	if not hasPet() then return end

	local level = plain(UnitLevel("pet"))
	local family = plain(UnitCreatureFamily and UnitCreatureFamily("pet"))
	local kind = plain(UnitCreatureType("pet"))
	local words = { self:Keeper() == "WARLOCK" and "DEMON" or "PET" }
	if level then words[#words + 1] = "LEVEL " .. level end
	if family and family ~= "" then words[#words + 1] = family:upper()
	elseif kind then words[#words + 1] = kind:upper() end
	frame.caption:SetText(table.concat(words, " · "))

	frame.name:SetText(UnitName("pet"))
	UI.setUnitBar(frame.hp, "pet", "health")
	UI.setHealthPercent(frame.percent, "pet")
	UI.setUnitBar(frame.power, "pet", "power")
	local powerType = plain(UnitPowerType("pet"))
	tint(frame.power, powerType == 0 and "mana" or "accent", powerType == 0 and 1 or 0.75)

	-- One word at the top right: dead, low, else the mood.
	local dead = plain(UnitIsDead("pet"))
	local fraction = healthFraction("pet")
	local mood = self:Mood()
	local word, token = "", "muted"
	if dead then
		word, token = "DEAD", "danger"
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
	if mood == 1 then foot[#foot + 1] = "DOES LESS DAMAGE · FEED IT"
	elseif stance then foot[#foot + 1] = stance end
	local target = UnitExists("pettarget")
	if plain(target) and mood ~= 1 then
		foot[#foot + 1] = "ON"
		frame.on:SetText(UnitName("pettarget"))
	else
		if command and mood ~= 1 then foot[#foot + 1] = command end
		frame.on:SetText("")
	end
	frame.foot:SetText(table.concat(foot, " · "))
end

-- The arc ---------------------------------------------------------------------

function Pet:BuildArc()
	local halo = _G.StoaHalo
	if not halo then return end
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
	UI.setUnitBar(sb, "pet", "health")
	local fraction = healthFraction("pet")
	tint(sb, fraction and fraction < LOW and "danger" or "accent", 0.7)
end

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
	RegisterStateDriver(row, "visibility", "[combat,@pet,exists,nopossessbar] show; hide")
	Stoa:RegisterMover("petrow", row, "Pet row", { default = function() self:PlaceRow() end })
	self:PlaceRow()
end

-- Under the combat bar's last row; the party row moves down to make room.
function Pet:PlaceRow()
	local row, halo = self.row, _G.StoaHalo
	if not row or not halo or InCombatLockdown() or Stoa:HasSavedPosition("petrow") then return end
	local bar = Stoa.modules.CombatBar
	local offset = bar and bar.enabled and bar.groupOffset or -52
	row:ClearAllPoints()
	row:SetPoint("TOP", halo, "BOTTOM", 0, offset - 4)
end

-- Room the pet row takes under the combat bar, for the party row below it.
function Pet:RowRoom()
	if not (self.enabled and self.db.row and self.row) then return 0 end
	if Stoa:HasSavedPosition("petrow") then return 0 end
	return (HasPetUI and plain(HasPetUI())) and ROW_ROOM or 0
end

function Pet:UpdateRow()
	if not self.rowButtons then return end
	if not GetPetActionInfo then return end
	local r, g, b = Stoa:Color("accent")
	for i, button in ipairs(self.rowButtons) do
		local _, texture, isToken, isActive, allowed, enabled = GetPetActionInfo(i)
		if isToken and texture then texture = _G[texture] end
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
	RegisterStateDriver(coin, "visibility", "[combat] hide; [@pet,exists] show; hide")
	coin.portrait, coin.ring, coin.mood, coin.nameText, coin.track = portrait, ring, mood, name, track
	self.coin = coin
end

function Pet:UpdateCoin()
	local coin = self.coin
	if not coin then return end
	if not hasPet() then return end
	SetPortraitTexture(coin.portrait, "pet")
	local fraction = healthFraction("pet")
	local r, g, b = Stoa:Color(fraction and fraction < LOW and "danger" or "health")
	if fraction then
		coin.ring:SetSwipeColor(r, g, b, 1)
		pcall(function()
			coin.ring:SetCooldown(GetTime() - 100 * (1 - fraction), 100)
			coin.ring:Pause()
		end)
	end
	local mood = self:Mood()
	coin.mood:SetText(mood and MOODS[mood] or "")
	coin.mood:SetTextColor(Stoa:Color(mood and MOOD_TOKEN[mood] or "muted"))
	coin.nameText:SetText((plain(UnitName("pet")) or ""):upper())
	coin.mood:SetShown(self.db.coin)
	coin.nameText:SetShown(self.db.coin)

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

-- Lifecycle -------------------------------------------------------------------

function Pet:UpdateAll()
	self:UpdatePlaque()
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
	Stoa:On("STOA_STATE_CHANGED", refresh)
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
			xpcall(self.UpdateArc, Stoa.catch, self)
			if not InCombatLockdown() then xpcall(self.UpdateCoin, Stoa.catch, self) end
		end
		for _, cell in ipairs(self.cells or {}) do
			if cell.unit == unit then xpcall(self.UpdateCell, Stoa.catch, self, cell) end
		end
	end)
	Stoa:OnUnit("UNIT_POWER_UPDATE", { "pet" }, function() xpcall(self.UpdatePlaque, Stoa.catch, self) end)
	Stoa:OnUnit("UNIT_TARGET", { "pet" }, function() xpcall(self.UpdatePlaque, Stoa.catch, self) end)
	refresh()
end
