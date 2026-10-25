-- Stoa QoL: merchants. Sells grey junk and repairs your gear when you open a
-- vendor, then leaves a note saying what it did.
local _, ns = ...
local Stoa = ns.Stoa

local Merchant = Stoa:NewModule("Merchant", {
	sellJunk = true,
	autoRepair = true,
	useGuildFunds = true,
})

-- Money as gold, silver and copper. The coin helper moved between clients,
-- so each home is tried before a plain text fallback.
local function money(copper)
	local format = (C_CurrencyInfo and C_CurrencyInfo.GetCoinTextureString) or GetCoinTextureString
	if format then return format(copper) end
	return ("%dg %ds %dc"):format(math.floor(copper / 10000), math.floor(copper / 100) % 100, copper % 100)
end

local function junkValue()
	local total = 0
	for bag = 0, NUM_BAG_SLOTS or 4 do
		for slot = 1, C_Container.GetContainerNumSlots(bag) do
			local info = C_Container.GetContainerItemInfo(bag, slot)
			if info and info.quality == Enum.ItemQuality.Poor and not info.hasNoValue then
				local sellPrice = select(11, C_Item.GetItemInfo(info.itemID)) or 0
				total = total + sellPrice * (info.stackCount or 1)
			end
		end
	end
	return total
end

-- Items you marked as junk yourself (greys are left to the grey path below).
local function sellMarked()
	local total = 0
	if not (Stoa.Items and C_Container and C_Container.UseContainerItem) then return 0 end
	Stoa.Items.eachBagSlot(function(bag, slot, info)
		if info.quality == Enum.ItemQuality.Poor or info.isLocked or info.hasNoValue then return end
		local id = info.itemID
		if not (id and Stoa.Items.isMarkedJunk(id)) then return end
		local price = Stoa.Items.sellPrice(id) or 0
		if price <= 0 then return end
		if pcall(C_Container.UseContainerItem, bag, slot) then
			total = total + price * (info.stackCount or 1)
		end
	end)
	return total
end

local function sellJunk()
	local marked = sellMarked()
	local value = junkValue()
	if value == 0 and marked == 0 then return end
	if value == 0 then
		Stoa:Note("merchant", ("Sold your marked junk for %s."):format(money(marked)))
		return
	end
	value = value + marked
	if C_MerchantFrame and C_MerchantFrame.SellAllJunkItems then
		C_MerchantFrame.SellAllJunkItems()
	else
		for bag = 0, NUM_BAG_SLOTS or 4 do
			for slot = 1, C_Container.GetContainerNumSlots(bag) do
				local info = C_Container.GetContainerItemInfo(bag, slot)
				if info and info.quality == Enum.ItemQuality.Poor and not info.hasNoValue then
					C_Container.UseContainerItem(bag, slot)
				end
			end
		end
	end
	Stoa:Note("merchant", ("Sold junk for %s."):format(money(value)))
end

local function repair(db)
	if not (CanMerchantRepair and CanMerchantRepair()) then return end
	local cost, needed = GetRepairAllCost()
	if not needed or cost == 0 then return end
	if db.useGuildFunds and IsInGuild() and CanGuildBankRepair and CanGuildBankRepair() then
		RepairAllItems(true)
		Stoa:Note("merchant", ("Repaired for %s from the guild bank."):format(money(cost)))
	elseif GetMoney() >= cost then
		RepairAllItems()
		Stoa:Note("merchant", ("Repaired for %s."):format(money(cost)))
	else
		Stoa:Note("merchant", ("Repairs cost %s, more than you carry."):format(money(cost)))
	end
end

function Merchant:OnEnable()
	local db = self.db
	Stoa:On("MERCHANT_SHOW", function()
		if db.sellJunk then xpcall(sellJunk, Stoa.catch) end
		if db.autoRepair then xpcall(repair, Stoa.catch, db) end
	end)
end

-- /stoa junk add|remove <item link or id>, list, clear
local function itemName(id)
	local name = C_Item and C_Item.GetItemInfo and C_Item.GetItemInfo(id)
	return name or ("item " .. id)
end

Stoa.commands.junk = function(rest)
	local action, arg = (rest or ""):match("^(%S*)%s*(.-)$")
	action = action:lower()
	local items = Stoa.Items
	if action == "add" or action == "remove" then
		local id = items.id(arg)
		if not id then
			Stoa:Print("Give an item link or number: /stoa junk " .. action .. " [item]")
			return
		end
		items.setJunk(id, action == "add")
		if action == "add" then
			Stoa:Print(itemName(id) .. " is marked as junk.")
		else
			Stoa:Print(itemName(id) .. " is no longer marked as junk.")
		end
	elseif action == "list" then
		local ids = {}
		for id in pairs(Stoa.db.junk or {}) do ids[#ids + 1] = id end
		table.sort(ids)
		if #ids == 0 then Stoa:Print("Nothing is marked as junk.") return end
		Stoa:Print(("Marked as junk (%d):"):format(#ids))
		for _, id in ipairs(ids) do Stoa:Print("  " .. itemName(id)) end
	elseif action == "clear" then
		Stoa.db.junk = {}
		Stoa:Fire("STOA_JUNK_CHANGED")
		Stoa:Print("Junk marks cleared.")
	else
		Stoa:Print("/stoa junk add|remove <item>, list, clear. Use the Junk button on your bags to mark by clicking.")
	end
end
