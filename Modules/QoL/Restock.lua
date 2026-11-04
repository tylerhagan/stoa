-- Stoa QoL: restock. Each character keeps a short list of things it always
-- carries (candles, ammo, poisons, food and water) and how many; any vendor
-- that sells one tops it back up when you open it, then says what it bought.
-- Hold Shift as the vendor opens to stop it. Items bought with tokens or
-- honour are never bought for you.
local _, ns = ...
local Stoa = ns.Stoa

local Restock = Stoa:NewModule("Restock", {
	enabled = true,
})
Stoa.Restock = Restock

local function list()
	Stoa.char.restock = Stoa.char.restock or {}
	return Stoa.char.restock
end
Restock.list = list

local function money(copper)
	local format = (C_CurrencyInfo and C_CurrencyInfo.GetCoinTextureString) or GetCoinTextureString
	if format then return format(copper) end
	return ("%dg %ds %dc"):format(math.floor(copper / 10000), math.floor(copper / 100) % 100, copper % 100)
end

function Restock.name(id)
	local name = C_Item and C_Item.GetItemNameByID and Stoa.safe.call(C_Item.GetItemNameByID, id)
	if type(name) == "string" and not Stoa:IsSecret(name) then return name end
	return "Item " .. id
end

function Restock.set(id, count)
	if count and count > 0 then list()[id] = math.floor(count) else list()[id] = nil end
end

local function maxStack(index, id)
	local n = GetMerchantItemMaxStack and Stoa.safe.call(GetMerchantItemMaxStack, index)
	if type(n) == "number" and n > 0 then return n end
	n = C_Item and C_Item.GetItemMaxStackSize and Stoa.safe.call(C_Item.GetItemMaxStackSize, id)
	return (type(n) == "number" and n > 0) and n or 20
end

function Restock:Run()
	local wants = list()
	if not next(wants) or not (GetMerchantNumItems and GetMerchantItemLink and BuyMerchantItem) then return end
	local bought, spent = {}, 0
	for index = 1, GetMerchantNumItems() or 0 do
		local id = Stoa.Items.id(GetMerchantItemLink(index))
		local want = id and wants[id]
		local info = want and C_MerchantFrame and C_MerchantFrame.GetItemInfo and Stoa.safe.call(C_MerchantFrame.GetItemInfo, index)
		if type(info) == "table" and info.isPurchasable ~= false and not info.hasExtendedCost and (info.price or 0) > 0 then
			local have = C_Item.GetItemCount(id, false) or 0
			local need = want - have
			if need > 0 then
				-- Some things come in bundles (arrows by the 200, water by 5).
				local bundle = math.max(info.stackCount or 1, 1)
				local buy = math.ceil(need / bundle) * bundle
				if info.numAvailable and info.numAvailable >= 0 then buy = math.min(buy, info.numAvailable * bundle) end
				local each = info.price / bundle
				local afford = math.floor((GetMoney() - spent) / each / bundle) * bundle
				buy = math.min(buy, afford)
				local chunk = math.max(maxStack(index, id), bundle)
				local left = buy
				while left > 0 do
					local n = math.min(left, chunk)
					if not pcall(BuyMerchantItem, index, n) then break end
					left = left - n
				end
				local got = buy - left
				if got > 0 then
					spent = spent + each * got
					bought[#bought + 1] = got .. " " .. (info.name or Restock.name(id))
				elseif afford <= 0 then
					bought[#bought + 1] = "not enough money for " .. (info.name or Restock.name(id))
				end
			end
		end
	end
	if #bought > 0 then
		Stoa:Note("merchant", ("Restocked %s for %s."):format(table.concat(bought, ", "), money(math.floor(spent + 0.5))))
	end
end

function Restock:OnEnable()
	Stoa:On("MERCHANT_SHOW", function()
		if not self.db.enabled or IsShiftKeyDown() then return end
		-- After the junk is sold, so the money is there.
		C_Timer.After(0.3, function() xpcall(self.Run, Stoa.catch, self) end)
	end)
end

-- /stoa restock add <item> [count], remove <item>, list, clear
Stoa.commands.restock = function(rest)
	local action, arg = (rest or ""):match("^(%S*)%s*(.-)$")
	action = action:lower()
	if action == "add" or action == "remove" then
		local item, number = arg:match("^(.-)%s+(%d+)%s*$")
		local count = tonumber(number)
		item = item or arg
		local id = Stoa.Items.id(item)
		if not id then
			Stoa:Print("Give an item link or number: /stoa restock add [item] 20")
			return
		end
		if action == "add" then
			Restock.set(id, count or 20)
			Stoa:Print(("Keeping %d %s on this character."):format(count or 20, Restock.name(id)))
		else
			Restock.set(id, nil)
			Stoa:Print(Restock.name(id) .. " is off the restock list.")
		end
	elseif action == "list" then
		if not next(list()) then Stoa:Print("Nothing to restock on this character.") return end
		Stoa:Print("Restock on this character:")
		for id, n in pairs(list()) do Stoa:Print(("  %d %s"):format(n, Restock.name(id))) end
	elseif action == "clear" then
		Stoa.char.restock = {}
		Stoa:Print("Restock list cleared.")
	else
		Stoa:Print("/stoa restock add <item> [count], remove <item>, list, clear. Shift-click the item into the chat line to name it.")
	end
end
