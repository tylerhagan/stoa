-- Stoa QoL: merchants. Sells grey junk and repairs your gear when you open a
-- vendor, then leaves a note saying what it did.
local _, ns = ...
local Stoa = ns.Stoa

local Merchant = Stoa:NewModule("Merchant", {
	sellJunk = true,
	autoRepair = true,
	useGuildFunds = true,
})

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
	Stoa:Note("merchant", ("Sold junk for %s."):format(GetCoinTextureString(value)))
end

local function repair(db)
	if not CanMerchantRepair() then return end
	local cost, needed = GetRepairAllCost()
	if not needed or cost == 0 then return end
	if db.useGuildFunds and IsInGuild() and CanGuildBankRepair and CanGuildBankRepair() then
		RepairAllItems(true)
		Stoa:Note("merchant", ("Repaired for %s from the guild bank."):format(GetCoinTextureString(cost)))
	elseif GetMoney() >= cost then
		RepairAllItems()
		Stoa:Note("merchant", ("Repaired for %s."):format(GetCoinTextureString(cost)))
	else
		Stoa:Note("merchant", ("Repairs cost %s, more than you carry."):format(GetCoinTextureString(cost)))
	end
end

function Merchant:OnEnable()
	local db = self.db
	Stoa:On("MERCHANT_SHOW", function()
		if db.sellJunk then xpcall(sellJunk, geterrorhandler()) end
		if db.autoRepair then xpcall(repair, geterrorhandler(), db) end
	end)
end
