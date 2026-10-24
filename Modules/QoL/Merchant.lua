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

local function sellJunk()
	local value = junkValue()
	if value == 0 then return end
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
