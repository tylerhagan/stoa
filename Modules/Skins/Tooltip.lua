-- Stoa: tooltips as cards.
-- The panel itself comes from Windows.lua (dark rounded card, thin health
-- bar). This adds what a card says and how it's dressed:
--   * a header band behind the name, lighter like a window's, with a soft
--     shadow under it and room above and below the name;
--   * the name takes the unit's colour (class, or the nameplates' reaction
--     colours: amber enemy, pale gold neutral, blue friend); the card's edge
--     stays a plain hairline, except for rank: elites get a gold line,
--     rares a silver one, rare elites gold with a silver header, bosses a
--     heavier gold, and their header warms with
--     that colour fading across it. Items above common fade their quality
--     colour across the header the same way;
--   * names in the serif, the rest in the sans; who it is on one quiet
--     line ("33 Gnome Mage", the class in its colour; "20 Humanoid" for
--     the rest), a guild or an NPC's title quiet in angle brackets above
--     it, and STOA's own lines under a hairline;
--   * for units, the lines that change what you do next: how hard an enemy
--     is as a word (TRIVIAL, EASY, EVEN, HARD, DEADLY, with ELITE, RARE or
--     BOSS), since the game's level colours fail for colour blindness;
--     whom it targets (YOU in the warning colour), what it's casting, your
--     threat; and for players their item level behind a sword mark at the
--     right of the identity line (read with an inspect, out of combat);
--   * for gear, one line against what you wear in that slot ("+6 over your
--     chest"), and for any item how many you have in your bags and bank;
--   * for herb and ore nodes, the skill they need against yours.
-- In combat a card keeps only what matters then: name, difficulty, target,
-- casting and threat. It can sit at the cursor instead of above the
-- console, and unit cards can stay hidden in combat until you hold Shift.
--
-- Unit details can be secret in combat; anything unreadable is left out.
local _, ns = ...
local Stoa = ns.Stoa
local UI = Stoa.UI

-- The headline's size. Slate sets it in the sans, which runs wider and
-- taller than the serif at the same size, so it steps down one.
local function headSize()
	return UI.slate() and Stoa.typeSize.label or Stoa.typeSize.name
end

local Tooltip = Stoa:NewModule("Tooltip", {
	-- "console": above the console's right corner; "cursor": at the mouse.
	anchor = "console",
	unitDetails = true,
	itemLevel = true,
	owned = true,
	-- Under the sell price of a stack, what one of them sells for.
	eachPrice = true,
	gathering = true,
	combatHide = false,
})

local RARE_SILVER = Stoa.silver
-- Room around the name: above it, and between the header and the lines.
local HEADER_TOP = 14
local HEADER_BELOW = 8
local LINE_GAP = 18
-- What the two add over the game's own spacing (10 above, 2 between).
local HEADER_ROOM = (HEADER_TOP - 10) + (LINE_GAP - 2)
local FADE_ALPHA = 0.22
-- Slate: the header's colour is a hint, not a wash, and the lines under
-- it stand a little apart (the game sets them 2 apart).
local SLATE_FADE_ALPHA = 0.1
local SLATE_AIR = 3
-- Cards with more than a name are at least this wide.
local MIN_WIDTH = 210
-- What an emptied line still takes, and the extra foot under STOA's lines.
local DROPPED_H = 5.5
local LOWER_PAD = 6

local INSPECT_WAIT = 1.5
local LEVELS_KEPT = 200

local function known(value)
	if Stoa:IsSecret(value) then return nil end
	return value
end

local function tokenHex(token)
	return Stoa:Hex(token)
end

-- Colours -----------------------------------------------------------------------

-- The hostile red as text: lifted a third of the way to white. The bar's
-- red is dark for small letters on a grey header, more so for readers who
-- see red and green poorly.
local function hostileText()
	local r, g, b = Stoa:Color("hostile")
	return r + (1 - r) * 0.34, g + (1 - g) * 0.34, b + (1 - b) * 0.34
end

-- A unit's colour: class for players (when the theme tints by class),
-- otherwise the nameplates' reaction colours. Returns r, g, b.
function Tooltip:UnitColour(unit)
	if known(UnitIsDeadOrGhost(unit)) then return Stoa:Color("muted") end
	if known(UnitIsPlayer(unit)) then
		local _, class = UnitClass(unit)
		class = known(class)
		local colour = class and Stoa:ClassTint() and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
		if colour then return colour.r, colour.g, colour.b end
		if known(UnitCanAttack("player", unit)) then return hostileText() end
		return Stoa:Color("text")
	end
	if known(UnitIsTapDenied(unit)) and not known(UnitPlayerControlled(unit)) then return Stoa:Color("muted") end
	local reaction = known(UnitReaction(unit, "player"))
	if reaction and reaction >= 5 then return Stoa:Color("mana") end
	if reaction == 4 then
		if Stoa.NeutralColour then return Stoa:NeutralColour() end
		return Stoa:Color("accent")
	end
	if reaction then return hostileText() end
	return Stoa:Color("text")
end

-- The unit a tooltip shows, or nil; not every tooltip has GetUnit.
local function tipUnit(tip)
	if not (tip and type(tip.GetUnit) == "function") then return nil end
	local ok, _, unit = pcall(tip.GetUnit, tip)
	if ok then return unit end
end

-- Lines -----------------------------------------------------------------------------

local function line(tip, i)
	local name = tip:GetName()
	return name and _G[name .. "TextLeft" .. i]
end

-- A label and value pair in Stoa's voice: the label quiet and in capitals.
local function addPair(tip, label, value, r, g, b)
	if value == nil then return end
	local mr, mg, mb = Stoa:Color("muted")
	-- A secret value (a name in a dungeon fight) can be shown but not
	-- measured, so the card doesn't widen for it and a right-hand value ran
	-- out past its edge. Those go on one left-aligned line instead.
	if Stoa:IsSecret(value) then
		local hex = ("|cff%02x%02x%02x"):format((r or 1) * 255, (g or 1) * 255, (b or 1) * 255)
		local ok = pcall(function()
			tip:AddLine(Stoa:Hex("muted") .. label .. "|r   " .. hex .. value .. "|r")
		end)
		if ok then return end
	end
	pcall(tip.AddDoubleLine, tip, label, value, mr, mg, mb, r or 1, g or 1, b or 1)
end

-- Item levels ------------------------------------------------------------------------
-- Another player's item level needs an inspect, which the game only answers
-- out of combat and in range. Each is asked once and remembered by GUID.

local levels, levelOrder = {}, {}
local pending

local function remember(guid, level)
	if not levels[guid] then
		levelOrder[#levelOrder + 1] = guid
		if #levelOrder > LEVELS_KEPT then levels[table.remove(levelOrder, 1)] = nil end
	end
	levels[guid] = level
end

function Tooltip:ItemLevel(unit, guid)
	if known(UnitIsUnit(unit, "player")) then
		if GetAverageItemLevel then
			local _, equipped = GetAverageItemLevel()
			equipped = known(equipped)
			return equipped and math.floor(equipped + 0.5)
		end
		return nil
	end
	if levels[guid] then return levels[guid] end
	self:Inspect(unit, guid)
end

function Tooltip:Inspect(unit, guid)
	if InCombatLockdown() or not NotifyInspect or not CanInspect then return end
	if InspectFrame and InspectFrame:IsShown() then return end
	if pending and GetTime() - pending.at < INSPECT_WAIT then return end
	if not known(CanInspect(unit)) then return end
	pending = { guid = guid, at = GetTime() }
	NotifyInspect(unit)
end

function Tooltip:InspectReady(guid)
	if not pending or guid ~= pending.guid then return end
	pending = nil
	local unit = "mouseover"
	local level
	if known(UnitGUID(unit)) == guid and C_PaperDollInfo and C_PaperDollInfo.GetInspectItemLevel then
		level = known(C_PaperDollInfo.GetInspectItemLevel(unit))
	end
	if ClearInspectPlayer and not (InspectFrame and InspectFrame:IsShown()) then ClearInspectPlayer() end
	if level and level > 0 then
		remember(guid, math.floor(level + 0.5))
		-- Show it straight away if the card is still up.
		local shown = tipUnit(GameTooltip)
		if GameTooltip:IsShown() and shown and known(UnitGUID(shown)) == guid then
			GameTooltip:SetUnit(shown)
		end
	end
end

-- Units -------------------------------------------------------------------------------

local CLASSIFICATIONS = { worldboss = "BOSS", rareelite = "RARE ELITE", elite = "ELITE", rare = "RARE" }

-- How hard an enemy is, as words and a colour token: the level gap the
-- game's own colours show, said out loud.
function Tooltip:Difficulty(unit)
	local level = known(UnitEffectiveLevel and UnitEffectiveLevel(unit) or UnitLevel(unit))
	local mine = known(UnitEffectiveLevel and UnitEffectiveLevel("player") or UnitLevel("player"))
	local word, token
	if level == -1 then
		word, token = "DEADLY", "danger"
	elseif level and mine then
		local gap = level - mine
		local trivial = known(UnitIsTrivial and UnitIsTrivial(unit))
		if trivial == nil and GetQuestGreenRange then trivial = gap < -GetQuestGreenRange() end
		if gap >= 5 then word, token = "DEADLY", "danger"
		elseif gap >= 3 then word, token = "HARD", "danger"
		elseif gap >= -2 then word, token = "EVEN", "accent"
		elseif trivial then word, token = "TRIVIAL", "muted"
		else word, token = "EASY", "text" end
	end
	local class = CLASSIFICATIONS[known(UnitClassification(unit)) or ""]
	if class then
		word = word and (word .. " " .. class) or class
		if class == "BOSS" then token = "danger" end
	end
	return word, token or "text"
end

-- The difficulty word sits beside the level ("Level 4, a dot, Even"), in its
-- colour: trivial grey, easy plain, even gold, hard and deadly amber, with
-- the word itself carrying the meaning. Without a level line it gets its own.
local function titleCase(word)
	return (word:lower():gsub("^%l", string.upper):gsub(" (%l)", function(c) return " " .. c:upper() end))
end

function Tooltip:SayDifficulty(tip, word, token, fs)
	if not fs then
		local prefix = LEVEL and LEVEL ~= "" and LEVEL or "Level"
		for i = 2, tip:NumLines() do
			local found = line(tip, i)
			local text = found and found:GetText()
			if type(text) == "string" and not Stoa:IsSecret(text) and text:find(prefix, 1, true) == 1 then
				fs = found
				break
			end
		end
	end
	local text = fs and fs:GetText()
	if type(text) == "string" and not Stoa:IsSecret(text) then
		fs:SetText(text .. Stoa.UI.WIDE_SEP .. tokenHex(token) .. titleCase(word) .. "|r")
		return
	end
	tip:AddLine(word, Stoa:Color(token))
end

-- Who it is, on one line: "33 Gnome Mage" with the class in its colour for
-- a player, "20 Humanoid" for anything else, in place of the game's level
-- line. A player's class line and faction line go (the other faction joins
-- the line in the warning colour), and whatever sits between the name and
-- this line (a guild, an NPC's title) goes quiet in angle brackets. Only
-- lines the game already drew are reworded. Returns the line, or nil when
-- the game's line can't be read (another language's wording, a secret
-- value) and is left as it was.
local GLYPH = UI.MEDIA .. "Textures\\Glyph"

function Tooltip:Identity(tip, unit)
	local prefix = LEVEL and LEVEL ~= "" and LEVEL or "Level"
	local index, fs
	for i = 2, tip:NumLines() do
		local found = line(tip, i)
		local text = found and found:GetText()
		if type(text) == "string" and not Stoa:IsSecret(text) and text:find(prefix, 1, true) == 1 then
			index, fs = i, found
			break
		end
	end
	if not fs then return nil end
	local level = known(UnitEffectiveLevel and UnitEffectiveLevel(unit) or UnitLevel(unit))
	if type(level) ~= "number" then return nil end
	local muted = tokenHex("muted")
	local text = muted .. (level > 0 and tostring(level) or "??")
	local drop = {}
	if known(UnitIsPlayer(unit)) then
		local race = known((UnitRace(unit)))
		local className, class = UnitClass(unit)
		className, class = known(className), known(class)
		if type(race) ~= "string" or type(className) ~= "string" then return nil end
		local colour = class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
		local hex = colour and Stoa:Hex(colour.r, colour.g, colour.b) or tokenHex("text")
		text = text .. " " .. race .. "|r " .. hex .. className .. "|r"
		local theirs, theirWord = UnitFactionGroup(unit)
		theirs, theirWord = known(theirs), known(theirWord)
		local mine = known((UnitFactionGroup("player")))
		if theirs and mine and theirs ~= mine and type(theirWord) == "string" then
			text = text .. UI.WIDE_SEP .. tokenHex("danger") .. theirWord .. "|r"
		end
		drop[className] = true
		if type(theirWord) == "string" then drop[theirWord] = true end
		if FACTION_ALLIANCE then drop[FACTION_ALLIANCE] = true end
		if FACTION_HORDE then drop[FACTION_HORDE] = true end
	else
		local kind = known(UnitCreatureType(unit))
		if type(kind) ~= "string" or kind == "" then return nil end
		text = text .. " " .. kind .. "|r"
		-- Rank is said with the difficulty for an enemy; a friend's is said here.
		local rank = CLASSIFICATIONS[known(UnitClassification(unit)) or ""]
		if rank and not known(UnitCanAttack("player", unit)) then
			text = text .. UI.WIDE_SEP .. tokenHex("text") .. titleCase(rank) .. "|r"
		end
	end
	fs:SetText(text)
	local quest = tip.stoaQuest
	for i = 2, index - 1 do
		local above = line(tip, i)
		local words = above and above:GetText()
		if type(words) == "string" and not Stoa:IsSecret(words) and words ~= "" and not (quest and quest[i]) then
			if words:sub(1, 1) ~= "<" then above:SetText("<" .. words .. ">") end
			above:SetTextColor(Stoa:Color("muted"))
		end
	end
	for i = index + 1, tip:NumLines() do
		local below = line(tip, i)
		local words = below and below:GetText()
		if type(words) == "string" and not Stoa:IsSecret(words) and drop[words] and not (quest and quest[i]) then
			below:SetText("")
			below:Hide()
			tip.stoaDropped = (tip.stoaDropped or 0) + 1
		end
	end
	return fs
end

-- STOA's own lines start under a hairline: a blank line with a rule across
-- its middle, added once and only when there is something to put under it.
local function lower(tip)
	if tip.stoaLower then return end
	tip.stoaLower = true
	tip:AddLine(" ")
	local spacer = line(tip, tip:NumLines())
	if not spacer then return end
	local rule = tip.stoaRule
	if not rule then
		rule = tip:CreateTexture(nil, "ARTWORK")
		rule:SetHeight(1)
		tip.stoaRule = rule
	end
	local r, g, b = Stoa:Color("text")
	rule:SetColorTexture(r, g, b, 0.14)
	rule:ClearAllPoints()
	-- An emptied line still takes a few pixels above the blank one, so the
	-- rule rises by half of that to sit midway between the two blocks.
	rule:SetPoint("LEFT", spacer, "LEFT", 0, (tip.stoaDropped or 0) * DROPPED_H / 2)
	rule:SetWidth(MIN_WIDTH - 20)
	rule:Show()
end

-- A player's item level rides the right end of the identity line behind a
-- small sword mark, so it takes no row and the card doesn't grow when the
-- number arrives.
function Tooltip:GearMark(tip, fs, level)
	local mark = tip.stoaGear
	if not mark then
		mark = tip:CreateFontString(nil, "ARTWORK")
		mark:SetFontObject(GameTooltipText)
		tip.stoaGear = mark
	end
	local r, g, b = Stoa:Color("muted")
	mark:SetText(("|T%sSword:13:13:0:0:32:32:0:32:0:32:%d:%d:%d|t %d"):format(GLYPH, r * 255, g * 255, b * 255, level))
	mark:SetTextColor(Stoa:Color("text"))
	mark.line = fs
	-- The game won't always measure a line (an enemy player's reads back
	-- secret), so the room it needs is then reckoned from its letters.
	local need = fs:GetStringWidth()
	local own = mark:GetStringWidth()
	if Stoa:IsSecret(need) or type(need) ~= "number" then
		local text = fs:GetText()
		local letters = 24
		if type(text) == "string" and not Stoa:IsSecret(text) then
			letters = #(text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|T.-|t", "  "))
		end
		need = letters * 7.5
	end
	if Stoa:IsSecret(own) or type(own) ~= "number" then own = 34 end
	tip.stoaWide = need + own + 36
	mark:ClearAllPoints()
	mark:SetPoint("RIGHT", fs, "LEFT", math.max(MIN_WIDTH, tip.stoaWide) - 20, 0)
	mark:Show()
	return true
end

function Tooltip:DressUnit(tip)
	local unit = tipUnit(tip)
	if not unit then return end
	-- In a dungeon fight the game hides which unit the card is for. The
	-- card is nearly always for what the mouse is over, so that is read
	-- instead; failing that the game's lines at least go quiet like
	-- STOA's, rather than standing white under a dressed name.
	if Stoa:IsSecret(unit) then
		unit = known(UnitExists("mouseover")) and "mouseover" or nil
		if not unit then
			local name = line(tip, 1)
			if name then Stoa:SetFont(name, "serif", headSize()) end
			for i = 2, tip:NumLines() do
				local text = line(tip, i)
				if text then text:SetTextColor(Stoa:Color("muted")) end
			end
			return
		end
	end
	local r, g, b = self:UnitColour(unit)
	local name = line(tip, 1)
	if name then
		name:SetTextColor(r, g, b)
		Stoa:SetFont(name, "serif", headSize())
	end
	self:Rank(tip, known(UnitClassification(unit)))

	-- The guild sits on the second line; the rest of Blizzard's lines go quiet.
	local guild = known(UnitIsPlayer(unit)) and GetGuildInfo and known((GetGuildInfo(unit)))
	for i = 2, tip:NumLines() do
		local text = line(tip, i)
		if text and not (tip.stoaQuest and tip.stoaQuest[i]) then
			if i == 2 and guild then
				text:SetTextColor(Stoa:Color("accent"))
			else
				text:SetTextColor(Stoa:Color("muted"))
			end
		end
	end
	local who = self:Identity(tip, unit)

	local attackable = known(UnitCanAttack("player", unit))
	if self.db.unitDetails then
		if known(UnitIsDeadOrGhost(unit)) then
			self:SayDifficulty(tip, "DEAD", "muted", who)
		elseif attackable then
			local word, token = self:Difficulty(unit)
			if word then self:SayDifficulty(tip, word, token, who) end
		end
	end

	-- Your own note about them leads STOA's lines.
	local notes = Stoa.Notes
	if notes and notes.TipLines then
		local first, second = notes:TipLines(unit)
		if first then
			lower(tip)
			local nr, ng, nb = Stoa:Color("text")
			tip:AddLine(first, nr, ng, nb, true)
			if second then tip:AddLine(second, Stoa:Color("muted")) end
		end
	end
	if not self.db.unitDetails then
		tip:Show()
		return
	end

	local target = unit .. "target"
	if known(UnitExists(target)) and not Stoa:SharedBy("tooltipTarget") then
		lower(tip)
		if known(UnitIsUnit(target, "player")) then
			addPair(tip, "TARGET", "YOU", Stoa:Color("danger"))
		else
			local tr, tg, tb = self:UnitColour(target)
			addPair(tip, "TARGET", UnitName(target), tr, tg, tb)
		end
	end

	-- A secret name can still be shown, just not tested.
	local casting = UnitCastingInfo(unit)
	if not Stoa:IsSecret(casting) and not casting then casting = UnitChannelInfo(unit) end
	if Stoa:IsSecret(casting) or casting then
		lower(tip)
		addPair(tip, "CASTING", casting, Stoa:Color("accent"))
	end

	if attackable and known(UnitAffectingCombat(unit)) and UnitDetailedThreatSituation then
		local _, status, scaled = UnitDetailedThreatSituation("player", unit)
		scaled, status = known(scaled), known(status)
		if scaled then
			local token = status and status >= 2 and "danger" or "text"
			lower(tip)
			addPair(tip, "THREAT", ("%d%%"):format(math.floor(scaled + 0.5)), Stoa:Color(token))
		end
	end

	if known(UnitIsPlayer(unit)) and not InCombatLockdown() then
		local guid = known(UnitGUID(unit))
		if guid and self.db.itemLevel then
			local level = self:ItemLevel(unit, guid)
			if level and not (who and self:GearMark(tip, who, level)) then
				lower(tip)
				addPair(tip, "ITEM LEVEL", tostring(level), Stoa:Color("text"))
			end
		end
	end
	tip:Show()
end

-- Items -------------------------------------------------------------------------------

-- The item's link: from the tooltip data first, as not every tooltip that
-- shows an item has GetItem (it was missing on some in Forever at launch).
local function itemLink(tip, data)
	local link = data and known(data.hyperlink)
	if not link and data and known(data.guid) and C_Item and C_Item.GetItemLinkByGUID then
		local ok, found = pcall(C_Item.GetItemLinkByGUID, data.guid)
		if ok then link = known(found) end
	end
	if not link and type(tip.GetItem) == "function" then
		local ok, _, found = pcall(tip.GetItem, tip)
		if ok then link = known(found) end
	end
	return link
end

function Tooltip:DressItem(tip, data)
	local link = itemLink(tip, data)
	local quality
	if link and not Stoa:IsSecret(link) and C_Item and C_Item.GetItemInfo then
		quality = select(3, C_Item.GetItemInfo(link))
	end
	local skin = Stoa.ItemSkin
	local r, g, b
	if skin and skin.qualityColour then r, g, b = skin.qualityColour(quality) end
	tip.stoaEdge:Clear()
	self:Fade(tip, r, g, b)
	local name = line(tip, 1)
	if name then Stoa:SetFont(name, "serif", headSize()) end

	if tip ~= GameTooltip or InCombatLockdown() then return end
	self:Upgrade(tip, link)
	if link and not Stoa:IsSecret(link) and Stoa.Items.isMarkedJunk(link) then
		tip:AddLine("Marked as junk", Stoa:Color("muted"))
		tip:Show()
	end
	if not self.db.owned then return end
	local id = data and known(data.id)
	if not id or not (C_Item and C_Item.GetItemCount) then return end
	local bags = known(C_Item.GetItemCount(id, false)) or 0
	local all = known(C_Item.GetItemCount(id, true)) or bags
	local bank = math.max(all - bags, 0)
	-- Your other characters' copies, from what each wrote down (Core/Alts.lua).
	local others = {}
	if Stoa.Alts and Stoa.Alts.db and Stoa.Alts.db.tooltipCounts then others = Stoa.Alts.holders(id) end
	if all <= 0 and #others == 0 then return end
	local parts = {}
	if bags > 0 then parts[#parts + 1] = bags .. " in bags" end
	if bank > 0 then parts[#parts + 1] = bank .. " in bank" end
	for i = 1, math.min(#others, 3) do parts[#parts + 1] = others[i][1] .. " " .. others[i][2] end
	if #others > 3 then parts[#parts + 1] = "+" .. (#others - 3) end
	addPair(tip, "OWNED", Stoa.UI.join(parts), Stoa:Color("text"))
	tip:Show()
end

-- A stack's sell price is the whole stack's; under it goes what one sells
-- for, from the item's own price, when the stack holds more than one.
function Tooltip:EachPrice(tip, data)
	if self.db.eachPrice == false or tip.isShopping or type(data) ~= "table" then return end
	local total = known(data.price)
	if not total or total <= 0 or (known(data.maxPrice) or 0) > 0 then return end
	local link = itemLink(tip)
	if not link or Stoa:IsSecret(link) or not (C_Item and C_Item.GetItemInfo) then return end
	local each = known(select(11, C_Item.GetItemInfo(link)))
	if not each or each <= 0 or total <= each or total % each ~= 0 then return end
	local money = MoneyFormatterUtil and GameTooltipMoneyFormat and MoneyFormatterUtil.FormatMoney(each, GameTooltipMoneyFormat) or Stoa:Money(each)
	local r, g, b = Stoa:Color("muted")
	tip:AddLine(("Each: %s"):format(money), r, g, b)
end

-- Gear against what you wear, from the weaker of the slots it goes in:
-- by stat weight for your role when the item can be scored, else by level.
function Tooltip:Upgrade(tip, link)
	if not link or Stoa:IsSecret(link) then return end
	-- Another addon's gear planner answers this already (Core/Companions.lua).
	if Stoa:SharedBy("gearUpgrade") then return end
	local gain, slot, none, source = Stoa.Items.upgrade(link)
	if gain then
		local role = Stoa.ROLE_LABELS[Stoa:GetRole() or ""] or "you"
		if source then role = "you, by " .. source end
		if none then
			tip:AddLine("Fills your empty " .. slot, Stoa:Color("accent"))
		elseif gain > 0 then
			tip:AddLine(("UPGRADE  +%d%% over your %s, for %s"):format(gain, slot, role), Stoa:Color("accent"))
		elseif gain <= -100 then
			tip:AddLine(("Nothing for %s, below your %s"):format(role, slot), Stoa:Color("muted"))
		elseif gain < 0 then
			tip:AddLine(("%d%% below your %s, for %s"):format(-gain, slot, role), Stoa:Color("muted"))
		elseif source then
			tip:AddLine(("Not an upgrade for %s"):format(role), Stoa:Color("muted"))
		else
			tip:AddLine("As good as your " .. slot, Stoa:Color("muted"))
		end
		return
	end
	local delta, where, empty = Stoa.Items.compare(link)
	if not delta then return end
	if empty then
		tip:AddLine("Fills your empty " .. where, Stoa:Color("accent"))
	elseif delta > 0 then
		tip:AddLine(("+%d over your %s"):format(delta, where), Stoa:Color("accent"))
	elseif delta < 0 then
		tip:AddLine(("%d below your %s"):format(-delta, where), Stoa:Color("muted"))
	else
		tip:AddLine("Same level as your " .. where, Stoa:Color("muted"))
	end
end

-- Gathering ----------------------------------------------------------------------------
-- Herb and ore nodes: the skill a node needs, from a table of the classic
-- ones by their English names, against your own. "Ooze Covered" nodes need
-- what the plain ones do. In other languages a herb node is known by the
-- game's name for the herb it gives (the two match); ore veins have no such
-- name to ask for, so they get a line in English only.

local HERBS = {
	Peacebloom = 1, Silverleaf = 1, Earthroot = 15, Mageroyal = 50, Briarthorn = 70,
	Stranglekelp = 85, Bruiseweed = 100, ["Wild Steelbloom"] = 115, ["Grave Moss"] = 120,
	Kingsblood = 125, Liferoot = 150, Fadeleaf = 160, Goldthorn = 170,
	["Khadgar's Whisker"] = 185, Wintersbite = 195, Firebloom = 205, ["Purple Lotus"] = 210,
	["Arthas' Tears"] = 220, Sungrass = 230, Blindweed = 235, ["Ghost Mushroom"] = 245,
	Gromsblood = 250, ["Golden Sansam"] = 260, Dreamfoil = 270, ["Mountain Silversage"] = 280,
	Plaguebloom = 285, Icecap = 290, ["Black Lotus"] = 300,
}
local ORES = {
	["Copper Vein"] = 1, ["Tin Vein"] = 65, ["Silver Vein"] = 75, ["Iron Deposit"] = 125,
	["Gold Vein"] = 155, ["Mithril Deposit"] = 175, ["Truesilver Deposit"] = 230,
	["Dark Iron Deposit"] = 230, ["Small Thorium Vein"] = 245, ["Rich Thorium Vein"] = 275,
	Incendicite = 65, ["Incendicite Mineral Vein"] = 65,
	["Lesser Bloodstone"] = 75, ["Lesser Bloodstone Deposit"] = 75,
	Indurium = 150, ["Indurium Mineral Vein"] = 150,
}
Tooltip.HERBS, Tooltip.ORES = HERBS, ORES

-- Each herb's item, for its name in the game's language.
local HERB_ITEMS = {
	Peacebloom = 2447, Silverleaf = 765, Earthroot = 2449, Mageroyal = 785, Briarthorn = 2450,
	Stranglekelp = 3820, Bruiseweed = 2453, ["Wild Steelbloom"] = 3355, ["Grave Moss"] = 3369,
	Kingsblood = 3356, Liferoot = 3357, Fadeleaf = 3818, Goldthorn = 3821,
	["Khadgar's Whisker"] = 3358, Wintersbite = 3819, Firebloom = 4625, ["Purple Lotus"] = 8831,
	["Arthas' Tears"] = 8836, Sungrass = 8838, Blindweed = 8839, ["Ghost Mushroom"] = 8845,
	Gromsblood = 8846, ["Golden Sansam"] = 13464, Dreamfoil = 13463, ["Mountain Silversage"] = 13465,
	Plaguebloom = 13466, Icecap = 13467, ["Black Lotus"] = 13468,
}
-- The game hands out item names as it loads them, so the ones still
-- missing are asked for again on a later look.
local herbWords, herbsLeft = {}, nil
local function englishHerb(name)
	if Stoa.english or not (C_Item and C_Item.GetItemNameByID) then return name end
	if herbWords[name] then return herbWords[name] end
	if herbsLeft == nil then
		herbsLeft = {}
		for english, itemID in pairs(HERB_ITEMS) do herbsLeft[english] = itemID end
	end
	for english, itemID in pairs(herbsLeft) do
		local word = Stoa.safe.plain(Stoa.safe.call(C_Item.GetItemNameByID, itemID))
		if type(word) == "string" and word ~= "" then
			herbWords[word] = english
			herbsLeft[english] = nil
		elseif C_Item.RequestLoadItemDataByID then
			Stoa.safe.call(C_Item.RequestLoadItemDataByID, itemID)
		end
	end
	return herbWords[name] or name
end

-- The profession skill lines, which don't change with the game's language.
local SKILL_LINES = { Herbalism = 182, Mining = 186 }

-- What a node needs: profession name, skill. Nil for anything else.
function Tooltip.NodeNeeds(name)
	if type(name) ~= "string" or Stoa:IsSecret(name) then return nil end
	name = englishHerb(name:gsub("^Ooze Covered ", ""))
	if HERBS[name] then return "Herbalism", HERBS[name] end
	if ORES[name] then return "Mining", ORES[name] end
end

-- Your skill in Herbalism or Mining (with any bonus), or nil if unlearned.
function Tooltip.GatherSkill(profession)
	if GetProfessions and GetProfessionInfo then
		local first, second = GetProfessions()
		for _, index in ipairs({ first or false, second or false }) do
			if index then
				local name, _, rank, _, _, _, line, modifier = GetProfessionInfo(index)
				rank = Stoa:PlainNumber(rank)
				if rank and (line == SKILL_LINES[profession] or name == profession) then
					return rank + (Stoa:PlainNumber(modifier) or 0)
				end
			end
		end
		return nil
	end
	if GetNumSkillLines and GetSkillLineInfo then
		for i = 1, GetNumSkillLines() do
			local name, isHeader, _, rank = GetSkillLineInfo(i)
			if name == profession and not isHeader then return Stoa:PlainNumber(rank) end
		end
	end
	return nil
end

function Tooltip:Gathering(tip)
	if not self.db.gathering then return end
	local first = line(tip, 1)
	local profession, needed = Tooltip.NodeNeeds(first and first:GetText())
	if not profession then return end
	local mine = Tooltip.GatherSkill(profession)
	if not mine then
		tip:AddLine(("%s %d (you haven't learned it)"):format(profession, needed), Stoa:Color("muted"))
	elseif mine < needed then
		tip:AddLine(("%s %d (you %d, TOO LOW)"):format(profession, needed, mine), Stoa:Color("danger"))
	else
		tip:AddLine(("%s %d (you %d)"):format(profession, needed, mine), Stoa:Color("text"))
	end
	tip:Show()
end

-- Dressing -----------------------------------------------------------------------------

local TIPS = { "GameTooltip", "ItemRefTooltip", "ShoppingTooltip1", "ShoppingTooltip2", "ItemRefShoppingTooltip1", "ItemRefShoppingTooltip2" }

-- Rank outlines and the header fade ---------------------------------------------------

-- Who gets a rank outline: the line's colour, the header fade's, and
-- whether the line is doubled up to read heavier.
local RANKS = {
	elite = { "accent", "accent" },
	rare = { RARE_SILVER, RARE_SILVER },
	rareelite = { "accent", RARE_SILVER },
	worldboss = { "accent", "accent", heavy = true },
}

local function rgb(colour)
	if type(colour) == "table" then return colour[1], colour[2], colour[3] end
	return Stoa:Color(colour)
end

-- A colour fading from the header's left across it; nothing clears it.
function Tooltip:Fade(tip, r, g, b)
	local fade = tip.stoaFade
	if not fade then return end
	if not r then fade:Hide() return end
	UI.setGradient(fade, { "HORIZONTAL", 1, 0 }, r, g, b, UI.slate() and SLATE_FADE_ALPHA or FADE_ALPHA)
	fade:Show()
end

function Tooltip:Rank(tip, classification)
	local rank = RANKS[classification or ""]
	local outlines = tip.stoaRank
	if not outlines then return end
	if not rank then
		for _, outline in ipairs(outlines) do outline:Clear() end
		self:Fade(tip)
		return
	end
	local r, g, b = rgb(rank[1])
	outlines[1]:Set(r, g, b, 1)
	if rank.heavy then outlines[2]:Set(r, g, b, 1) else outlines[2]:Clear() end
	-- One line only: a second line inside the first, on top of the header
	-- band and its rule, read as layer upon layer. The pair's second colour
	-- (a rare elite's silver) warms the header instead.
	outlines[3]:Clear()
	self:Fade(tip, rgb(rank[2]))
end

local function clear(tip)
	-- Lines the quest box stepped in go back under the line above them, or
	-- the next card (the bags' money list, an item) shows a stray indent.
	if tip.stoaMoved then
		for text, above in pairs(tip.stoaMoved) do
			text:ClearAllPoints()
			text:SetPoint("TOPLEFT", above, "BOTTOMLEFT", 0, -2)
		end
		tip.stoaMoved = nil
	end
	tip.stoaQuest = nil
	tip.stoaLower, tip.stoaWide, tip.stoaDropped = nil, nil, nil
	if tip.stoaRule then tip.stoaRule:Hide() end
	if tip.stoaGear then tip.stoaGear:Hide() end
	if tip.stoaQuestBox then tip.stoaQuestBox.fill:Hide() end
	tip.stoaEdge:Clear()
	for _, outline in ipairs(tip.stoaRank or {}) do outline:Clear() end
	if tip.stoaFade then tip.stoaFade:Hide() end
end

-- The header band behind the first line, its shadow, the fade over it,
-- and the rank outlines: the outer line, a second one just inside it for
-- a heavier boss line, and the inner line of the pair.
-- The name drops a little and the second line steps clear of the band.
-- The game lays its lines out again each time it shows the card, so this
-- runs after every Show rather than once.
local function placeLines(tip)
	local name = tip:GetName()
	local first, second = name and _G[name .. "TextLeft1"], name and _G[name .. "TextLeft2"]
	if not first then return end
	first:ClearAllPoints()
	-- 10 in, the game's own margin: the lines it places itself sit there,
	-- and a name further in leaves the line under it out of step with them.
	first:SetPoint("TOPLEFT", tip, "TOPLEFT", 10, -HEADER_TOP)
	if second then
		second:ClearAllPoints()
		second:SetPoint("TOPLEFT", first, "BOTTOMLEFT", 0, -LINE_GAP)
	end
end

-- The game sizes the card for its own spacing (the name 10 from the top,
-- lines 2 apart); the header's extra room is added at the foot so the last
-- line doesn't run over the edge.

-- Room around the quest box: its lines stay level with the rest of the
-- card, and the box keeps a gap from the lines above and below it.
local QUEST_GAP = 9
local QUEST_INDENT = 0
local QUEST_PAD = 5

local function questRange(tip)
	local first, last
	for i in pairs(tip.stoaQuest or {}) do
		if not first or i < first then first = i end
		if not last or i > last then last = i end
	end
	return first, last
end

-- Where the first quest line and the line after the box should sit, and
-- how much height that adds to the card.
local function questSpacing(tip, check)
	local first, last = questRange(tip)
	if not first then return 0, true end
	local top, prev = line(tip, first), line(tip, first - 1)
	local bottom, after = line(tip, last), line(tip, last + 1)
	if not (top and prev and bottom) then return 0, true end
	local gap = first == 2 and LINE_GAP or QUEST_GAP
	local hasAfter = after and after:IsShown()
	if check then
		local _, rel, _, x, y = top:GetPoint(1)
		if Stoa:IsSecret(y) or Stoa:IsSecret(x) then return 0, true end
		if rel ~= prev or math.abs((x or 0) - QUEST_INDENT) > 0.5 or math.abs((y or 0) + gap) > 0.5 then return 0, false end
		if hasAfter then
			local _, arel, _, ax, ay = after:GetPoint(1)
			if Stoa:IsSecret(ay) or Stoa:IsSecret(ax) then return 0, true end
			if arel ~= bottom or math.abs((ax or 0) + QUEST_INDENT) > 0.5 or math.abs((ay or 0) + QUEST_GAP) > 0.5 then return 0, false end
		end
		return 0, true
	end
	top:ClearAllPoints()
	top:SetPoint("TOPLEFT", prev, "BOTTOMLEFT", QUEST_INDENT, -gap)
	-- Remembered so the next card gets these lines back where the game
	-- keeps them (clear, above); it does not always lay them out again.
	tip.stoaMoved = tip.stoaMoved or {}
	tip.stoaMoved[top] = prev
	local extra = (first == 2 and 0 or (QUEST_GAP - 2))
	if hasAfter then
		after:ClearAllPoints()
		after:SetPoint("TOPLEFT", bottom, "BOTTOMLEFT", -QUEST_INDENT, -QUEST_GAP)
		tip.stoaMoved[after] = bottom
		extra = extra + QUEST_GAP - 2
	else
		extra = extra + QUEST_PAD
	end
	return extra, true
end

-- Slate: every line from the third down steps SLATE_AIR further from the
-- one above it, and the card grows by as much at its foot. Only lines the
-- game hung straight under the line above are moved (the quest box's two
-- are placed above); `check` only reports whether the game has laid them
-- out again since. Each moved line is remembered like the quest box's, so
-- the next card gets it back where the game keeps it.
local function airLines(tip, check)
	if not UI.slate() then return 0, true end
	local count = tip.NumLines and tip:NumLines()
	if Stoa:IsSecret(count) or type(count) ~= "number" then return 0, true end
	local questFirst, questLast = questRange(tip)
	local extra = 0
	for i = 3, count do
		local text, above = line(tip, i), line(tip, i - 1)
		if not (text and above and text:IsShown()) then break end
		if not (questFirst and (i == questFirst or i == questLast + 1)) then
			local _, rel, _, x, y = text:GetPoint(1)
			if Stoa:IsSecret(x) or Stoa:IsSecret(y) or Stoa:IsSecret(rel) then return extra, true end
			if rel == above and type(y) == "number" and math.abs(x or 0) < 0.5 then
				if math.abs(y + 2) < 0.5 then
					if check then return 0, false end
					text:ClearAllPoints()
					text:SetPoint("TOPLEFT", above, "BOTTOMLEFT", 0, -(2 + SLATE_AIR))
					tip.stoaMoved = tip.stoaMoved or {}
					tip.stoaMoved[text] = above
					extra = extra + SLATE_AIR
				elseif math.abs(y + 2 + SLATE_AIR) < 0.5 then
					extra = extra + SLATE_AIR
				end
			end
		end
	end
	return extra, true
end

local function settle(tip)
	placeLines(tip)
	local questRoom = questSpacing(tip) + airLines(tip)
	if not (tip.SetPadding and tip.GetPadding) then return end
	-- A one-line card (a minimap blip, a name) only needs the name's drop.
	local second = tip:GetName() and _G[tip:GetName() .. "TextLeft2"]
	local room = ((second and second:IsShown()) and HEADER_ROOM or (HEADER_TOP - 10)) + questRoom + (tip.stoaLower and LOWER_PAD or 0)
	tip.stoaRoom = room
	-- Cards with more than a name keep a minimum width, so a short card
	-- (a level and a word or two) doesn't look squeezed.
	local wide = second and second:IsShown()
	if tip.SetMinimumWidth then tip:SetMinimumWidth(wide and math.max(MIN_WIDTH, tip.stoaWide or 0) or 0) end
	-- The rule and the gear mark reach to the card's right margin.
	local width = tip:GetWidth()
	if not Stoa:IsSecret(width) and type(width) == "number" and width > 40 then
		local rule, mark = tip.stoaRule, tip.stoaGear
		if rule and rule:IsShown() then rule:SetWidth(width - 20) end
		if mark and mark:IsShown() and mark.line then
			mark:ClearAllPoints()
			mark:SetPoint("RIGHT", mark.line, "LEFT", width - 20, 0)
		end
	end
	local right, bottom, left, top = tip:GetPadding()
	if Stoa:IsSecret(right) or Stoa:IsSecret(bottom) or Stoa:IsSecret(left) or Stoa:IsSecret(top) then return end
	bottom = bottom or 0
	-- Ours to change when it is the game's default or what we set last;
	-- larger padding the game asked for (a bar under the lines) stays.
	if bottom < room or bottom == tip.stoaPad then
		tip.stoaPad = room
		if bottom ~= room then tip:SetPadding(right or 0, room, left or 0, top or 0) end
	end
end

local function keepHeader(tip)
	local name = tip:GetName()
	local first, second = name and _G[name .. "TextLeft1"], name and _G[name .. "TextLeft2"]
	if not (first and second and second:IsShown()) then return end
	local _, relative, _, _, y = second:GetPoint(1)
	-- In combat the game can hand back secret positions; leave the card be.
	if Stoa:IsSecret(y) or Stoa:IsSecret(relative) then return end
	if relative ~= first or math.abs((y or 0) + LINE_GAP) > 0.5 then settle(tip) end
	local padded = tip.GetPadding and select(2, tip:GetPadding())
	if Stoa:IsSecret(padded) then return end
	if tip.stoaPad ~= tip.stoaRoom and padded == tip.stoaPad then return settle(tip) end
	-- The game lays lines out again as quest objectives arrive.
	local _, placed = questSpacing(tip, true)
	if not placed then return settle(tip) end
	local _, aired = airLines(tip, true)
	if not aired then settle(tip) end
end

local function header(tip)
	local name = tip:GetName()
	local first = name and _G[name .. "TextLeft1"]
	if not first then return end
	placeLines(tip)
	local band = UI.sliced(tip, "BACKGROUND", "CardTop.tga")
	if not band then return end
	band:ClearAllPoints()
	band:SetPoint("TOPLEFT", tip, "TOPLEFT")
	band:SetPoint("TOPRIGHT", tip, "TOPRIGHT")
	band:SetPoint("BOTTOM", first, "BOTTOM", 0, -HEADER_BELOW)
	band:SetDrawLayer("BACKGROUND", -6)
	UI.tint(band, "text", 0.06)
	local fade = UI.sliced(tip, "BACKGROUND", "CardTop.tga")
	fade:ClearAllPoints()
	fade:SetAllPoints(band)
	fade:SetDrawLayer("BACKGROUND", -5)
	fade:Hide()
	tip.stoaFade = fade
	UI.shadowLine(tip, band)
	UI.applyTheme()
end

local function edge(tip)
	if tip.stoaEdge then return end
	tip.stoaEdge = UI.roundBorder(tip, "CardEdge.tga", 1)
	tip.stoaRank = {
		UI.roundBorder(tip, "CardEdge.tga", 1),
		UI.roundBorder(tip, "CardEdge.tga", 1, -1),
		UI.roundBorder(tip, "CardEdge.tga", 1, -4),
	}
	xpcall(header, Stoa.catch, tip)
	Stoa.SafeHook(tip, "Show", function(self) xpcall(settle, Stoa.catch, self) end)
	-- The game can show the card without calling Show from Lua, and it lays
	-- the lines out again when it adds one (quest objectives arrive after
	-- the card is up), so a moved line is checked each frame it is shown.
	tip:HookScript("OnShow", function(self) xpcall(settle, Stoa.catch, self) end)
	tip:HookScript("OnUpdate", function(self) xpcall(keepHeader, Stoa.catch, self) end)
	tip:HookScript("OnTooltipCleared", clear)
	tip:HookScript("OnHide", clear)
end

-- The game's tooltip fonts in Stoa's faces and sizes (the text size
-- setting and its floor apply through Stoa:SetFont).
local function fonts()
	local function face(object, kind, size)
		if object and object.SetFont then Stoa:SetFont(object, kind, size) end
	end
	face(GameTooltipHeaderText, "serif", headSize())
	face(GameTooltipText, "sans", Stoa.typeSize.body)
	face(GameTooltipTextSmall, "sans", Stoa.typeSize.caption)
end

-- Quests ------------------------------------------------------------------------------
-- The quest lines on a card (the quest's name, your progress, a party
-- member's name) sit together in a slightly lighter box: the quest name in the accent, the count picked
-- out, and finished objectives quiet behind the game's tick.


local function questBox(tip)
	local box = tip.stoaQuestBox
	if box then return box end
	box = {}
	box.fill = tip:CreateTexture(nil, "BACKGROUND", nil, -4)
	box.fill:SetTexture("Interface\\Buttons\\WHITE8x8")
	UI.tint(box.fill, "text", 0.08)
	tip.stoaQuestBox = box
	UI.applyTheme()
	return box
end

-- Lays the box over the first to the last quest line seen so far.
function Tooltip:PlaceQuestBox(tip)
	local first, last
	for i in pairs(tip.stoaQuest or {}) do
		if not first or i < first then first = i end
		if not last or i > last then last = i end
	end
	local top, bottom = first and line(tip, first), last and line(tip, last)
	if not (top and bottom) then return end
	local box = questBox(tip)
	box.fill:ClearAllPoints()
	box.fill:SetPoint("LEFT", tip, "LEFT", 8, 0)
	box.fill:SetPoint("RIGHT", tip, "RIGHT", -8, 0)
	box.fill:SetPoint("TOP", top, "TOP", 0, QUEST_PAD)
	box.fill:SetPoint("BOTTOM", bottom, "BOTTOM", 0, -QUEST_PAD)
	box.fill:Show()
end

function Tooltip:QuestLine(tip, data)
	local index = data and known(data.lineIndex)
	local text = index and line(tip, index)
	if not text then return end
	tip.stoaQuest = tip.stoaQuest or {}
	tip.stoaQuest[index] = data.type
	local types = Enum.TooltipDataLineType
	if data.type == types.QuestTitle then
		text:SetTextColor(Stoa:Color("accent"))
	elseif data.type == types.QuestObjective then
		if known(data.completed) then
			text:SetTextColor(Stoa:Color("muted"))
		else
			text:SetTextColor(Stoa:Color("text"))
			-- "8/20 Rabid Thistle Bear slain": the count in the accent.
			local words = known(text:GetText())
			if type(words) == "string" and not words:find("|c", 1, true) then
				local count = words:match("%d+%s*/%s*%d+")
				if count then
					local start, stop = words:find(count, 1, true)
					text:SetText(words:sub(1, start - 1) .. Stoa:Hex("accent") .. count .. "|r" .. words:sub(stop + 1))
				end
			end
		end
	else
		text:SetTextColor(Stoa:Color("text"))
	end
	self:PlaceQuestBox(tip)
end

-- Unit cards hidden in combat unless you hold Shift.
function Tooltip:HideInCombat(tip)
	if not self.db.combatHide or not InCombatLockdown() or IsShiftKeyDown() then return end
	if tipUnit(tip) then tip:Hide() end
end

-- At the cursor, when chosen.
function Tooltip:Anchor(tip, parent)
	if self.db.anchor ~= "cursor" then return false end
	tip:SetOwner(parent, "ANCHOR_CURSOR_RIGHT", 24, -8)
	return true
end

function Tooltip:OnEnable()
	if not (TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType) then return end
	xpcall(fonts, Stoa.catch)
	self.addsNotes = true
	for _, name in ipairs(TIPS) do
		local tip = _G[name]
		if tip and not (tip.IsForbidden and tip:IsForbidden()) then xpcall(edge, Stoa.catch, tip) end
	end
	local function usable(tip)
		return tip and tip.stoaEdge and not (tip.IsForbidden and tip:IsForbidden())
	end
	TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Unit, Stoa:Guard(function(tip)
		if not usable(tip) or tip ~= GameTooltip then return end
		self:DressUnit(tip)
		self:HideInCombat(tip)
	end, "Tooltip"))
	TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, Stoa:Guard(function(tip, data)
		if not usable(tip) then return end
		self:DressItem(tip, data)
	end, "Tooltip"))
	if Enum.TooltipDataType.Object then
		TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Object, Stoa:Guard(function(tip)
			if not usable(tip) or tip ~= GameTooltip then return end
			self:Gathering(tip)
		end, "Tooltip"))
	end
	local types = Enum.TooltipDataLineType
	if TooltipDataProcessor.AddLinePostCall and types then
		for _, kind in ipairs({ types.QuestTitle, types.QuestObjective, types.QuestPlayer }) do
			TooltipDataProcessor.AddLinePostCall(kind, Stoa:Guard(function(tip, data)
				if not usable(tip) then return end
				self:QuestLine(tip, data)
			end, "Tooltip"))
		end
		if types.SellPrice then
			TooltipDataProcessor.AddLinePostCall(types.SellPrice, Stoa:Guard(function(tip, data)
				if not usable(tip) then return end
				self:EachPrice(tip, data)
			end, "Tooltip"))
		end
	end
	Stoa:On("INSPECT_READY", function(guid)
		xpcall(self.InspectReady, Stoa.catch, self, guid)
	end)
end

-- /stoa tooltip cursor|console moves the card.
Stoa.commands.tooltip = function(rest)
	local where = rest and rest:lower():match("%a+")
	if where == "cursor" or where == "console" then
		Tooltip.db.anchor = where
		Stoa:Print(where == "cursor" and "Tooltips follow the cursor." or "Tooltips sit above the console's right corner.")
	else
		Stoa:Print("/stoa tooltip cursor or /stoa tooltip console.")
	end
end
