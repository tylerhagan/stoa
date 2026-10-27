-- Stoa: tooltips as cards.
-- The panel itself comes from Windows.lua (dark rounded card, thin health
-- bar). This adds what a card says and how it's dressed:
--   * a header band behind the name, lighter like a window's, with a soft
--     shadow under it and room above and below the name;
--   * the name takes the unit's colour (class, or the nameplates' reaction
--     colours: amber enemy, pale gold neutral, blue friend); the card's edge
--     stays a plain hairline, except for rank: elites get a doubled gold
--     line, rares a doubled silver one, rare elites gold outside and silver
--     inside, bosses a heavier doubled gold, and their header warms with
--     that colour fading across it. Items above common fade their quality
--     colour across the header the same way;
--   * names in the serif, the rest in the sans, the level line quiet and
--     the guild in the accent;
--   * for units, the lines that change what you do next: how hard an enemy
--     is as a word (TRIVIAL, EASY, EVEN, HARD, DEADLY, with ELITE, RARE or
--     BOSS), since the game's level colours fail for colour blindness;
--     whom it targets (YOU in the warning colour), what it's casting, your
--     threat; and for players their item level (read with an inspect, out
--     of combat);
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

local Tooltip = Stoa:NewModule("Tooltip", {
	-- "console": above the console's right corner; "cursor": at the mouse.
	anchor = "console",
	unitDetails = true,
	itemLevel = true,
	owned = true,
	gathering = true,
	combatHide = false,
})

-- The rare's silver, as on the target plaque.
local RARE_SILVER = { 0.79, 0.8, 0.82 }
-- Room around the name: above it, and between the header and the lines.
local HEADER_TOP = 14
local HEADER_BELOW = 8
local LINE_GAP = 18
local FADE_ALPHA = 0.22

local INSPECT_WAIT = 1.5
local LEVELS_KEPT = 200

local function known(value)
	if Stoa:IsSecret(value) then return nil end
	return value
end

local function hex(r, g, b)
	return ("|cff%02x%02x%02x"):format(r * 255, g * 255, b * 255)
end

local function tokenHex(token)
	return hex(Stoa:Color(token))
end

-- Colours -----------------------------------------------------------------------

-- A unit's colour: class for players (when the theme tints by class),
-- otherwise the nameplates' reaction colours. Returns r, g, b.
function Tooltip:UnitColour(unit)
	if known(UnitIsDeadOrGhost(unit)) then return Stoa:Color("muted") end
	if known(UnitIsPlayer(unit)) then
		local _, class = UnitClass(unit)
		class = known(class)
		local colour = class and Stoa:Theme().classTint and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
		if colour then return colour.r, colour.g, colour.b end
		if known(UnitCanAttack("player", unit)) then return Stoa:Color("danger") end
		return Stoa:Color("text")
	end
	if known(UnitIsTapDenied(unit)) and not known(UnitPlayerControlled(unit)) then return Stoa:Color("muted") end
	local reaction = known(UnitReaction(unit, "player"))
	if reaction and reaction >= 5 then return Stoa:Color("mana") end
	if reaction == 4 then return Stoa:Color("accent") end
	if reaction then return Stoa:Color("danger") end
	return Stoa:Color("text")
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
		local _, shown = GameTooltip:GetUnit()
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
		elseif gap >= -2 then word, token = "EVEN", "text"
		elseif trivial then word, token = "TRIVIAL", "muted"
		else word, token = "EASY", "muted" end
	end
	local class = CLASSIFICATIONS[known(UnitClassification(unit)) or ""]
	if class then
		word = word and (word .. " · " .. class) or class
		if class == "BOSS" then token = "danger" end
	end
	return word, token or "text"
end

function Tooltip:DressUnit(tip)
	local _, unit = tip:GetUnit()
	if not unit or Stoa:IsSecret(unit) then return end
	local r, g, b = self:UnitColour(unit)
	local name = line(tip, 1)
	if name then
		name:SetTextColor(r, g, b)
		Stoa:SetFont(name, "serif", Stoa.typeSize.label + 2)
	end
	self:Rank(tip, known(UnitClassification(unit)))

	-- The guild sits on the second line; the rest of Blizzard's lines go quiet.
	local guild = known(UnitIsPlayer(unit)) and GetGuildInfo and known((GetGuildInfo(unit)))
	for i = 2, tip:NumLines() do
		local text = line(tip, i)
		if text then
			if i == 2 and guild then
				text:SetTextColor(Stoa:Color("accent"))
			else
				text:SetTextColor(Stoa:Color("muted"))
			end
		end
	end
	if not self.db.unitDetails then return end

	if known(UnitIsDeadOrGhost(unit)) then
		tip:AddLine("DEAD", Stoa:Color("muted"))
	elseif known(UnitCanAttack("player", unit)) then
		local word, token = self:Difficulty(unit)
		if word then tip:AddLine(word, Stoa:Color(token)) end
	end

	local target = unit .. "target"
	if known(UnitExists(target)) then
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
	if Stoa:IsSecret(casting) or casting then addPair(tip, "CASTING", casting, Stoa:Color("accent")) end

	if known(UnitCanAttack("player", unit)) and known(UnitAffectingCombat(unit)) and UnitDetailedThreatSituation then
		local _, status, scaled = UnitDetailedThreatSituation("player", unit)
		scaled, status = known(scaled), known(status)
		if scaled then
			local token = status and status >= 2 and "danger" or "text"
			addPair(tip, "THREAT", ("%d%%"):format(math.floor(scaled + 0.5)), Stoa:Color(token))
		end
	end

	if known(UnitIsPlayer(unit)) and not InCombatLockdown() then
		local guid = known(UnitGUID(unit))
		if guid and self.db.itemLevel then
			local level = self:ItemLevel(unit, guid)
			if level then addPair(tip, "ITEM LEVEL", tostring(level), Stoa:Color("text")) end
		end
	end
	tip:Show()
end

-- Items -------------------------------------------------------------------------------

function Tooltip:DressItem(tip, data)
	local _, link = tip:GetItem()
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
	if name then Stoa:SetFont(name, "serif", Stoa.typeSize.label + 2) end

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
	if all <= 0 then return end
	local parts = {}
	if bags > 0 then parts[#parts + 1] = bags .. " in bags" end
	if bank > 0 then parts[#parts + 1] = bank .. " in bank" end
	addPair(tip, "OWNED", table.concat(parts, " · "), Stoa:Color("text"))
	tip:Show()
end

-- Gear against what you wear, from the weaker of the slots it goes in:
-- by stat weight for your role when the item can be scored, else by level.
function Tooltip:Upgrade(tip, link)
	if not link or Stoa:IsSecret(link) then return end
	local gain, slot, none = Stoa.Items.upgrade(link)
	if gain then
		local role = Stoa.ROLE_LABELS[Stoa:GetRole() or ""] or "you"
		if none then
			tip:AddLine("Fills your empty " .. slot, Stoa:Color("accent"))
		elseif gain > 0 then
			tip:AddLine(("UPGRADE  +%d%% over your %s, for %s"):format(gain, slot, role), Stoa:Color("accent"))
		elseif gain < 0 then
			tip:AddLine(("%d%% below your %s, for %s"):format(-gain, slot, role), Stoa:Color("muted"))
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
-- ones by their English names (other languages get no line), against your
-- own. "Ooze Covered" nodes need what the plain ones do.

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

-- The profession skill lines, which don't change with the game's language.
local SKILL_LINES = { Herbalism = 182, Mining = 186 }

-- What a node needs: profession name, skill. Nil for anything else.
function Tooltip.NodeNeeds(name)
	if type(name) ~= "string" or Stoa:IsSecret(name) then return nil end
	name = name:gsub("^Ooze Covered ", "")
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
		tip:AddLine(("%s %d · you haven't learned it"):format(profession, needed), Stoa:Color("muted"))
	elseif mine < needed then
		tip:AddLine(("%s %d · you %d · TOO LOW"):format(profession, needed, mine), Stoa:Color("danger"))
	else
		tip:AddLine(("%s %d · you %d"):format(profession, needed, mine), Stoa:Color("text"))
	end
	tip:Show()
end

-- Dressing -----------------------------------------------------------------------------

local TIPS = { "GameTooltip", "ItemRefTooltip", "ShoppingTooltip1", "ShoppingTooltip2" }

-- Rank outlines and the header fade ---------------------------------------------------

-- Who gets a rank outline: the outer line's colour, the inner's, and
-- whether the outer is doubled up to read heavier.
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
	UI.setGradient(fade, { "HORIZONTAL", 1, 0 }, r, g, b, FADE_ALPHA)
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
	local ir, ig, ib = rgb(rank[2])
	outlines[3]:Set(ir, ig, ib, 0.55)
	self:Fade(tip, r, g, b)
end

local function clear(tip)
	tip.stoaEdge:Clear()
	for _, outline in ipairs(tip.stoaRank or {}) do outline:Clear() end
	if tip.stoaFade then tip.stoaFade:Hide() end
end

-- The header band behind the first line, its shadow, the fade over it,
-- and the rank outlines: the outer line, a second one just inside it for
-- a heavier boss line, and the inner line of the pair.
local function header(tip)
	local name = tip:GetName()
	local first, second = name and _G[name .. "TextLeft1"], name and _G[name .. "TextLeft2"]
	if not first then return end
	first:ClearAllPoints()
	first:SetPoint("TOPLEFT", tip, "TOPLEFT", 12, -HEADER_TOP)
	if second then
		second:ClearAllPoints()
		second:SetPoint("TOPLEFT", first, "BOTTOMLEFT", 0, -LINE_GAP)
	end
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
	tip:HookScript("OnTooltipCleared", clear)
	tip:HookScript("OnHide", clear)
end

local function fonts()
	local serif, sans = Stoa.fonts.serif[1], Stoa.fonts.sans[1]
	local function face(object, file, size)
		if object and object.SetFont then pcall(object.SetFont, object, file[1], size * file[2], "") end
	end
	face(GameTooltipHeaderText, serif, 15)
	face(GameTooltipText, sans, 12)
	face(GameTooltipTextSmall, sans, 11)
end

-- Unit cards hidden in combat unless you hold Shift.
function Tooltip:HideInCombat(tip)
	if not self.db.combatHide or not InCombatLockdown() or IsShiftKeyDown() then return end
	if tip:GetUnit() then tip:Hide() end
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
