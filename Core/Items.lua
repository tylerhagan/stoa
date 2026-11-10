-- Stoa: what an item is worth to you, shared.
-- The bags, tooltips, quest window, merchant and loot feed all ask the same
-- questions of an item: its level, what it sells for, whether it beats what
-- you wear and whether you've marked it as junk. The answers live here.
local _, ns = ...
local Stoa = ns.Stoa

local Items = {}
Stoa.Items = Items

local call = Stoa.safe.call

local getInfo = (C_Item and C_Item.GetItemInfo) or GetItemInfo

-- itemID from a link, an ID or an item string.
function Items.id(item)
	if type(item) == "number" then return item end
	if type(item) ~= "string" or Stoa:IsSecret(item) then return nil end
	return tonumber(item:match("item:(%d+)")) or tonumber(item)
end

-- Quality, sell price (copper each), equip slot, class and subclass IDs.
-- Nil while the game hasn't loaded the item yet.
function Items.info(item)
	if not item or Stoa:IsSecret(item) then return nil end
	local name, _, quality, _, _, _, _, _, equipLoc, _, price, classID, subclassID = call(getInfo, item)
	if not name then return nil end
	return quality, Stoa:PlainNumber(price) or 0, equipLoc, classID, subclassID
end

function Items.sellPrice(item)
	local _, price = Items.info(item)
	return price
end

-- Effective item level, only for things you can wear or wield.
function Items.level(link)
	if not link or Stoa:IsSecret(link) then return nil end
	local equippable = call(C_Item and C_Item.IsEquippableItem or IsEquippableItem, link)
	if not equippable then return nil end
	local level = call(C_Item and C_Item.GetDetailedItemLevelInfo or GetDetailedItemLevelInfo, link)
	level = Stoa:PlainNumber(level)
	if level and level > 1 then return math.floor(level + 0.5) end
end

-- Armour your class can wear now: cloth for all; leather for all but the
-- cloth wearers; mail for warriors and paladins, and hunters and shamans
-- from 40; plate for warriors and paladins from 40; shields, librams, idols
-- and totems for their classes. An item outside this is never an upgrade.
-- Weapons go by the game's own verdict: it paints a weapon type you can't
-- use red on the item's tooltip (Daggers for a paladin), so that's asked.
local ARMOR = 4
local ARMOR_RULES = {
	[2] = function(class) return class ~= "PRIEST" and class ~= "MAGE" and class ~= "WARLOCK" end,
	[3] = function(class, level)
		return class == "WARRIOR" or class == "PALADIN" or ((class == "HUNTER" or class == "SHAMAN") and level >= 40)
	end,
	[4] = function(class, level) return (class == "WARRIOR" or class == "PALADIN") and level >= 40 end,
	[6] = function(class) return class == "WARRIOR" or class == "PALADIN" or class == "SHAMAN" end,
	[7] = function(class) return class == "PALADIN" end,
	[8] = function(class) return class == "DRUID" end,
	[9] = function(class) return class == "SHAMAN" end,
}

local WEAPON = 2
local unusable = {}

-- True when the item's tooltip has a red line other than its level need:
-- a weapon or armour type you can't use. Kept per link until your skills
-- or level change.
local function redLine(link)
	if unusable[link] ~= nil then return unusable[link] end
	local getLines = C_TooltipInfo and C_TooltipInfo.GetHyperlink
	if not getLines then return false end
	local ok, data = pcall(getLines, link)
	if not ok or type(data) ~= "table" or type(data.lines) ~= "table" then return false end
	local levelPattern = type(ITEM_MIN_LEVEL) == "string" and ("^" .. ITEM_MIN_LEVEL:gsub("%%d", "%%d+")) or "^Requires Level"
	local red = false
	for _, line in ipairs(data.lines) do
		for _, side in ipairs({ { line.leftText, line.leftColor }, { line.rightText, line.rightColor } }) do
			local text, color = side[1], side[2]
			if type(text) == "string" and type(color) == "table" and not Stoa:IsSecret(text) then
				local r, g, b = Stoa:PlainNumber(color.r), Stoa:PlainNumber(color.g), Stoa:PlainNumber(color.b)
				if r and g and b and r > 0.9 and g < 0.25 and b < 0.25 and not text:match(levelPattern) then red = true end
			end
		end
	end
	unusable[link] = red
	return red
end

function Items.forgetUsable()
	wipe(unusable)
end

function Items.wearable(link)
	local _, _, _, classID, subclassID = Items.info(link)
	if classID == WEAPON then return not redLine(link) end
	if classID ~= ARMOR or not subclassID then return true end
	local rule = ARMOR_RULES[subclassID]
	if not rule then return true end
	local _, class = UnitClass("player")
	if not class or Stoa:IsSecret(class) then return true end
	local level = Stoa:PlainNumber(UnitLevel("player")) or 1
	return rule(class, level) and true or false
end

-- The slots each kind of item goes in, and the names lines use for them.
Items.SLOTS = {
	INVTYPE_HEAD = { 1 }, INVTYPE_NECK = { 2 }, INVTYPE_SHOULDER = { 3 }, INVTYPE_BODY = { 4 },
	INVTYPE_CHEST = { 5 }, INVTYPE_ROBE = { 5 }, INVTYPE_WAIST = { 6 }, INVTYPE_LEGS = { 7 },
	INVTYPE_FEET = { 8 }, INVTYPE_WRIST = { 9 }, INVTYPE_HAND = { 10 }, INVTYPE_FINGER = { 11, 12 },
	INVTYPE_TRINKET = { 13, 14 }, INVTYPE_CLOAK = { 15 }, INVTYPE_WEAPON = { 16, 17 },
	INVTYPE_2HWEAPON = { 16 }, INVTYPE_WEAPONMAINHAND = { 16 }, INVTYPE_WEAPONOFFHAND = { 17 },
	INVTYPE_SHIELD = { 17 }, INVTYPE_HOLDABLE = { 17 }, INVTYPE_RANGED = { 18 }, INVTYPE_RANGEDRIGHT = { 18 },
	INVTYPE_THROWN = { 18 }, INVTYPE_RELIC = { 18 },
}
Items.SLOT_NAMES = {
	[1] = "head", [2] = "neck", [3] = "shoulders", [5] = "chest", [6] = "waist", [7] = "legs", [8] = "feet",
	[9] = "wrists", [10] = "hands", [11] = "ring", [12] = "ring", [13] = "trinket", [14] = "trinket",
	[15] = "back", [16] = "main hand", [17] = "off hand", [18] = "ranged slot",
}

-- The slots an item would take from what you wear now. A one-hand weapon
-- goes in the main hand only when you can't dual wield, or when you hold a
-- two-hander (it would replace that); off-hand things next to a two-hander
-- have no fair comparison, so they get none.
local OFF_HAND_ONLY = { INVTYPE_WEAPONOFFHAND = true, INVTYPE_SHIELD = true, INVTYPE_HOLDABLE = true }
local MAIN_ONLY = { 16 }

function Items.slotsFor(equipLoc)
	local slots = equipLoc and Items.SLOTS[equipLoc]
	if not slots then return nil end
	if equipLoc ~= "INVTYPE_WEAPON" and not OFF_HAND_ONLY[equipLoc] then return slots end
	local main = call(GetInventoryItemLink, "player", 16)
	local mainLoc
	if main then mainLoc = select(3, Items.info(main)) end
	if mainLoc == "INVTYPE_2HWEAPON" then
		return equipLoc == "INVTYPE_WEAPON" and MAIN_ONLY or nil
	end
	if equipLoc == "INVTYPE_WEAPON" and CanDualWield then
		local ok, can = pcall(CanDualWield)
		if ok and not can then return MAIN_ONLY end
	end
	return slots
end

-- The item against the weaker of the slots it goes in: the item level
-- difference, that slot's name, and true when the slot is empty. Nil for
-- things you can't wear, or when it is what you wear.
function Items.compare(link)
	if not Items.wearable(link) then return nil end
	local level = Items.level(link)
	if not level then return nil end
	local _, _, equipLoc = Items.info(link)
	local slots = Items.slotsFor(equipLoc)
	if not slots then return nil end
	local worstSlot, worst
	for _, slot in ipairs(slots) do
		local worn = call(GetInventoryItemLink, "player", slot)
		if worn == link then return nil end
		-- Something worn whose level the game won't give: no fair comparison,
		-- and certainly not an empty slot.
		local wornLevel = 0
		if worn then
			wornLevel = Items.level(worn)
			if not wornLevel then return nil end
		end
		if not worst or wornLevel < worst then worstSlot, worst = slot, wornLevel end
	end
	return level - worst, Items.SLOT_NAMES[worstSlot] or "slot", worst == 0
end

-- Pawn (a companion addon, Core/Companions.lua) scores gear by its own stat
-- scales for your spec. While it's loaded its answer is the one Stoa shows,
-- so the two never disagree: the best gain over any of its scales, in
-- percent, against the item it would replace. 0 when Pawn says it isn't an
-- upgrade; nil when Pawn can't tell yet.
local function pawnUpgrade(link)
	if not (_G.PawnIsInitialized and _G.PawnGetItemData and _G.PawnIsItemAnUpgrade) then return nil end
	local ok, item = pcall(_G.PawnGetItemData, link)
	if not ok or type(item) ~= "table" or not item.Link then return nil end
	local _, _, equipLoc = Items.info(link)
	local slots = Items.slotsFor(equipLoc)
	if not slots then return nil end
	local fine, list = pcall(_G.PawnIsItemAnUpgrade, item)
	if not fine then return nil end
	local best, against
	for _, entry in ipairs(type(list) == "table" and list or {}) do
		local gain = tonumber(entry.PercentUpgrade)
		if gain and (not best or gain > best) then best, against = gain, entry.ExistingItemLink end
	end
	local slot = slots[1]
	for _, each in ipairs(slots) do
		if against and call(GetInventoryItemLink, "player", each) == against then slot = each end
	end
	local name = Items.SLOT_NAMES[slot] or "slot"
	if not best then return 0, name, false, "Pawn" end
	-- Pawn gives 100 (10,000%) for an empty slot.
	if best >= (_G.PawnBigUpgradeThreshold or 100) then return 100, name, true, "Pawn" end
	return math.floor(best * 100 + 0.5), name, false, "Pawn"
end

-- The item for your role against the weaker of its slots, by stat weight
-- (Core/Weights.lua), or by Pawn's scales when Pawn is loaded: the gain in
-- percent, the slot's name, true when the slot is empty, and "Pawn" when the
-- answer is Pawn's. Nil when either can't be scored, so callers fall back
-- to Items.compare.
function Items.upgrade(link)
	if not link or Stoa:IsSecret(link) then return nil end
	if not Items.wearable(link) then return nil end
	if _G.PawnIsItemAnUpgrade then
		local gain, name, none, source = pawnUpgrade(link)
		if gain then return gain, name, none, source end
	end
	if not Stoa.Weights then return nil end
	local score = Stoa.Weights.score(link)
	if not score or score <= 0 then return nil end
	local _, _, equipLoc = Items.info(link)
	local slots = Items.slotsFor(equipLoc)
	if not slots then return nil end
	local worstSlot, worst, empty
	for _, slot in ipairs(slots) do
		local worn = call(GetInventoryItemLink, "player", slot)
		if worn == link then return nil end
		local wornScore = 0
		if worn then
			wornScore = Stoa.Weights.score(worn)
			if not wornScore then return nil end
		end
		if not worst or wornScore < worst then worstSlot, worst, empty = slot, wornScore, not worn end
	end
	local name = Items.SLOT_NAMES[worstSlot] or "slot"
	-- Only a slot with nothing in it is empty; worn gear with nothing your
	-- role counts loses to anything that has some.
	if worst <= 0 then return 100, name, empty and true or false end
	return math.floor((score - worst) / worst * 100 + 0.5), name, false
end

-- Junk: grey items, plus anything you've marked. Marks are account-wide by
-- itemID in StoaDB.junk, so a mark made on one character holds for all.
function Items.isMarkedJunk(item)
	local id = Items.id(item)
	return id and Stoa.db and Stoa.db.junk and Stoa.db.junk[id] or false
end

function Items.isJunk(item)
	if Items.isMarkedJunk(item) then return true end
	local quality, price = Items.info(item)
	return quality == 0 and (price or 0) > 0
end

function Items.setJunk(item, on)
	local id = Items.id(item)
	if not id or not Stoa.db then return end
	Stoa.db.junk = Stoa.db.junk or {}
	Stoa.db.junk[id] = on and true or nil
	Stoa:Fire("STOA_JUNK_CHANGED", id, on)
end

-- Money as letters: 12g 04s 30c, dropping leading zero parts.
function Items.money(copper)
	copper = Stoa:PlainNumber(copper)
	if not copper then return "" end
	local negative = copper < 0
	copper = math.abs(math.floor(copper + 0.5))
	local gold, silver, rest = math.floor(copper / 10000), math.floor(copper / 100) % 100, copper % 100
	local text
	if gold > 0 then
		text = ("%dg %02ds"):format(gold, silver)
	elseif silver > 0 then
		text = ("%ds %02dc"):format(silver, rest)
	else
		text = rest .. "c"
	end
	return negative and ("-" .. text) or text
end

-- Every bag slot: fn(bag, slot, info) where info is the container item
-- table (itemID, hyperlink, stackCount, quality, isLocked...).
function Items.eachBagSlot(fn)
	local numSlots = C_Container and C_Container.GetContainerNumSlots or GetContainerNumSlots
	local itemInfo = C_Container and C_Container.GetContainerItemInfo
	if not (numSlots and itemInfo) then return end
	for bag = 0, (NUM_BAG_SLOTS or 4) do
		for slot = 1, call(numSlots, bag) or 0 do
			local info = call(itemInfo, bag, slot)
			if type(info) == "table" then fn(bag, slot, info) end
		end
	end
end

-- A trained weapon skill or a new level can make a red line go away.
Stoa:On("PLAYER_LEVEL_UP", Items.forgetUsable)
Stoa:On("SKILL_LINES_CHANGED", Items.forgetUsable)
Stoa:On("STOA_SPELLS_CHANGED", Items.forgetUsable)
