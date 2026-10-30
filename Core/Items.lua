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

-- The item against the weaker of the slots it goes in: the item level
-- difference, that slot's name, and true when the slot is empty. Nil for
-- things you can't wear, or when it is what you wear.
function Items.compare(link)
	local level = Items.level(link)
	if not level then return nil end
	local _, _, equipLoc = Items.info(link)
	local slots = equipLoc and Items.SLOTS[equipLoc]
	if not slots then return nil end
	local worstSlot, worst
	for _, slot in ipairs(slots) do
		local worn = call(GetInventoryItemLink, "player", slot)
		if worn == link then return nil end
		local wornLevel = worn and Items.level(worn) or 0
		if not worst or wornLevel < worst then worstSlot, worst = slot, wornLevel end
	end
	return level - worst, Items.SLOT_NAMES[worstSlot] or "slot", worst == 0
end

-- The item for your role against the weaker of its slots, by stat weight
-- (Core/Weights.lua): the gain in percent, the slot's name, and true when
-- the slot is empty. Nil when either can't be scored, so callers fall back
-- to Items.compare.
function Items.upgrade(link)
	if not Stoa.Weights then return nil end
	local score = Stoa.Weights.score(link)
	if not score or score <= 0 then return nil end
	local _, _, equipLoc = Items.info(link)
	local slots = equipLoc and Items.SLOTS[equipLoc]
	if not slots then return nil end
	local worstSlot, worst
	for _, slot in ipairs(slots) do
		local worn = call(GetInventoryItemLink, "player", slot)
		if worn == link then return nil end
		local wornScore = worn and Stoa.Weights.score(worn) or 0
		if not wornScore then return nil end
		if not worst or wornScore < worst then worstSlot, worst = slot, wornScore end
	end
	local name = Items.SLOT_NAMES[worstSlot] or "slot"
	if worst <= 0 then return 100, name, true end
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
