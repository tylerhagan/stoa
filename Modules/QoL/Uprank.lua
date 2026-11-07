-- Stoa QoL: auto-uprank. When you learn a new rank of a spell, any action
-- bar slot holding the rank that was your best until then is given the new
-- one, so you never keep casting Flash Heal rank 3 by accident. A lower rank
-- you put on a bar yourself (a cheap heal, downranking) is left alone, and
-- so are macros. /stoa uprank upgrades every slot, on purpose.
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

-- The best rank you knew of each spell on your bars, by name, as of the
-- last look. A slot is upgraded on its own only if it held that rank.
local function remember(self)
	local spells = Stoa.Spells
	self.known = self.known or {}
	for slot = 1, SLOTS do
		local kind, id = call(GetActionInfo, slot)
		id = Stoa:PlainNumber(id)
		local name = kind == "spell" and id and spells.name(id)
		if name and not Stoa:IsSecret(name) then
			local bestID = spells.best(id)
			if bestID then self.known[name] = bestID end
		end
	end
end

-- Walks the bars once and swaps outranked spells for their best rank: every
-- one when asked (all), or only those that were your best rank until a new
-- one was learned. Returns the list of { name, rank } it upgraded.
function Uprank:Run(all)
	if InCombatLockdown() then
		Stoa:AfterCombat(function() self:Run(all) end)
		return {}
	end
	local spells = Stoa.Spells
	if not (spells and GetActionInfo and PlaceAction) then return {} end
	-- Never fight the player's hands: a spell already on the cursor waits.
	if cursorBusy() then return {} end
	-- The first look after login only learns what the bars hold.
	if not all and not self.known then
		remember(self)
		return {}
	end
	local known = self.known or {}
	local done, seen = {}, {}
	for slot = 1, SLOTS do
		local kind, id = call(GetActionInfo, slot)
		id = Stoa:PlainNumber(id)
		if kind == "spell" and id and spells.outranked(id) then
			local bestID, rank = spells.best(id)
			local wasBest = known[spells.name(id) or ""] == id
			if bestID and bestID ~= id and (all or wasBest) then
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
	remember(self)
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
	local list = Uprank:Run(true)
	if #list == 0 and not InCombatLockdown() then Stoa:Print("Your bars already hold your best ranks.") end
end
