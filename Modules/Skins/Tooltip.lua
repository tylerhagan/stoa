-- Stoa: tooltips as cards.
-- The panel itself comes from Windows.lua (dark rounded card, thin health
-- bar). This adds what a card says and how it's edged:
--   * the edge takes the unit's colour (class, or the nameplates' reaction
--     colours: amber enemy, pale gold neutral, blue friend) or the item's
--     quality;
--   * names in the serif, the rest in the sans, the level line quiet and
--     the guild in the accent;
--   * for units, the lines that change what you do next: how hard an enemy
--     is as a word (TRIVIAL, EASY, EVEN, HARD, DEADLY, with ELITE, RARE or
--     BOSS), since the game's level colours fail for colour blindness;
--     whom it targets (YOU in the warning colour), what it's casting, your
--     threat; and for players their item level (read with an inspect, out
--     of combat);
--   * for gear, one line against what you wear in that slot ("+6 over your
--     chest"), and for any item how many you have in your bags and bank.
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
	combatHide = false,
})

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
	tip.stoaEdge:Set(r, g, b, 0.75)

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
	if r then tip.stoaEdge:Set(r, g, b, 0.85) else tip.stoaEdge:Clear() end
	local name = line(tip, 1)
	if name then Stoa:SetFont(name, "serif", Stoa.typeSize.label + 2) end

	if tip ~= GameTooltip or InCombatLockdown() then return end
	self:Upgrade(tip, link)
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

-- Gear against what you wear: the slots each kind of item goes in, and the
-- name the line uses.
local SLOTS = {
	INVTYPE_HEAD = { 1 }, INVTYPE_NECK = { 2 }, INVTYPE_SHOULDER = { 3 }, INVTYPE_BODY = { 4 },
	INVTYPE_CHEST = { 5 }, INVTYPE_ROBE = { 5 }, INVTYPE_WAIST = { 6 }, INVTYPE_LEGS = { 7 },
	INVTYPE_FEET = { 8 }, INVTYPE_WRIST = { 9 }, INVTYPE_HAND = { 10 }, INVTYPE_FINGER = { 11, 12 },
	INVTYPE_TRINKET = { 13, 14 }, INVTYPE_CLOAK = { 15 }, INVTYPE_WEAPON = { 16, 17 },
	INVTYPE_2HWEAPON = { 16 }, INVTYPE_WEAPONMAINHAND = { 16 }, INVTYPE_WEAPONOFFHAND = { 17 },
	INVTYPE_SHIELD = { 17 }, INVTYPE_HOLDABLE = { 17 }, INVTYPE_RANGED = { 18 }, INVTYPE_RANGEDRIGHT = { 18 },
	INVTYPE_THROWN = { 18 }, INVTYPE_RELIC = { 18 },
}
local SLOT_NAMES = {
	[1] = "head", [2] = "neck", [3] = "shoulders", [5] = "chest", [6] = "waist", [7] = "legs", [8] = "feet",
	[9] = "wrists", [10] = "hands", [11] = "ring", [12] = "ring", [13] = "trinket", [14] = "trinket",
	[15] = "back", [16] = "main hand", [17] = "off hand", [18] = "ranged slot",
}

function Tooltip:Upgrade(tip, link)
	local skin = Stoa.ItemSkin
	if not (skin and skin.itemLevel) or not link or Stoa:IsSecret(link) then return end
	local level = skin.itemLevel(link)
	if not level then return end
	local equipLoc = C_Item and C_Item.GetItemInfo and select(9, C_Item.GetItemInfo(link))
	local slots = equipLoc and SLOTS[equipLoc]
	if not slots then return end
	-- Against the weaker of two slots, the one it would replace.
	local worstSlot, worst
	for _, slot in ipairs(slots) do
		local worn = GetInventoryItemLink("player", slot)
		if worn == link then return end
		local wornLevel = worn and skin.itemLevel(worn) or 0
		if not worst or wornLevel < worst then worstSlot, worst = slot, wornLevel end
	end
	local where = SLOT_NAMES[worstSlot] or "slot"
	if worst == 0 then
		tip:AddLine("Fills your empty " .. where, Stoa:Color("accent"))
	elseif level > worst then
		tip:AddLine(("+%d over your %s"):format(level - worst, where), Stoa:Color("accent"))
	elseif level < worst then
		tip:AddLine(("%d below your %s"):format(worst - level, where), Stoa:Color("muted"))
	else
		tip:AddLine("Same level as your " .. where, Stoa:Color("muted"))
	end
end

-- Dressing -----------------------------------------------------------------------------

local TIPS = { "GameTooltip", "ItemRefTooltip", "ShoppingTooltip1", "ShoppingTooltip2" }

local function edge(tip)
	if tip.stoaEdge then return end
	tip.stoaEdge = UI.roundBorder(tip, "CardEdge.tga", 1)
	tip:HookScript("OnTooltipCleared", function(self) self.stoaEdge:Clear() end)
	tip:HookScript("OnHide", function(self) self.stoaEdge:Clear() end)
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
