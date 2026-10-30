-- Stoa QoL: auto-uprank. When you learn a new rank of a spell, any action
-- bar slot still holding an older rank is given the new one, so you never
-- keep casting Flash Heal rank 3 by accident. Macros are left alone.
local _, ns = ...
local Stoa = ns.Stoa

local Uprank = Stoa:NewModule("Uprank", {})

local SLOTS = 120

local call = Stoa.safe.call

local function pickup(spellID)
	if C_Spell and C_Spell.PickupSpell then
		return pcall(C_Spell.PickupSpell, spellID)
	end
	if PickupSpell then return pcall(PickupSpell, spellID) end
	return false
end

local function cursorBusy()
	return GetCursorInfo and call(GetCursorInfo) ~= nil
end

-- Walks the bars once and swaps every outranked spell for its best rank.
-- Returns the list of { name, rank } it upgraded.
function Uprank:Run()
	if InCombatLockdown() then
		Stoa:AfterCombat(function() self:Run() end)
		return {}
	end
	local spells = Stoa.Spells
	if not (spells and GetActionInfo and PlaceAction) then return {} end
	-- Never fight the player's hands: a spell already on the cursor waits.
	if cursorBusy() then return {} end
	local done, seen = {}, {}
	for slot = 1, SLOTS do
		local kind, id = call(GetActionInfo, slot)
		id = Stoa:PlainNumber(id)
		if kind == "spell" and id and spells.outranked(id) then
			local bestID, rank = spells.best(id)
			if bestID and bestID ~= id then
				local ok = pickup(bestID)
				if ok and cursorBusy() then
					pcall(PlaceAction, slot)
				end
				-- Whatever came off the bar is dropped, never kept on the cursor.
				if ClearCursor then pcall(ClearCursor) end
				local name = spells.name(bestID)
				if name and not seen[name] then
					seen[name] = true
					done[#done + 1] = { name, rank or 0 }
				end
			end
		end
	end
	for _, entry in ipairs(done) do
		local text = entry[2] > 0 and ("Upgraded %s to rank %d on your bars."):format(entry[1], entry[2])
			or ("Upgraded %s on your bars."):format(entry[1])
		Stoa:Print(text)
	end
	return done
end

function Uprank:OnEnable()
	Stoa:On("STOA_SPELLS_CHANGED", function()
		if not self.db.enabled then return end
		xpcall(function() self:Run() end, Stoa.catch)
	end)
end

Stoa.commands.uprank = function()
	local list = Uprank:Run()
	if #list == 0 and not InCombatLockdown() then Stoa:Print("Your bars already hold your best ranks.") end
end
