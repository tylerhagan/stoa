-- Stoa QoL: gear for each spec. Stoa notices which equipment set you put on
-- in each spec (from the game's equipment manager) and puts it back on when
-- you change to that spec again, after any fight. A set you've assigned to
-- a spec in the equipment manager itself always wins.
local _, ns = ...
local Stoa = ns.Stoa

local GearSets = Stoa:NewModule("GearSets", {
	enabled = true,
})

local function sets()
	Stoa.char.gearBySpec = Stoa.char.gearBySpec or {}
	return Stoa.char.gearBySpec
end

local function api()
	return C_EquipmentSet and C_EquipmentSet.UseEquipmentSet and C_EquipmentSet.GetEquipmentSetInfo
end

-- name, isEquipped for a set ID, or nil once it's been deleted.
local function info(id)
	local ok, name, _, _, isEquipped = pcall(C_EquipmentSet.GetEquipmentSetInfo, id)
	if ok and name then return name, isEquipped end
end

function GearSets:Wanted(slot)
	if C_EquipmentSet.GetEquipmentSetForSpec then
		local ok, assigned = pcall(C_EquipmentSet.GetEquipmentSetForSpec, slot)
		if ok and assigned then return assigned, true end
	end
	return sets()[slot]
end

function GearSets:Wear()
	local slot = Stoa.ActiveSpecSlot()
	local id = self:Wanted(slot)
	if not id then return end
	local name, worn = info(id)
	if not name then
		sets()[slot] = nil
		return
	end
	if worn then return end
	Stoa:AfterCombat(function()
		if pcall(C_EquipmentSet.UseEquipmentSet, id) then
			Stoa:Note("gear", ("Wearing %s for this spec."):format(name))
		end
	end)
end

function GearSets:OnEnable()
	if not api() then return end
	-- Whatever set you put on is the one this spec wears from now on.
	Stoa:On("EQUIPMENT_SWAP_FINISHED", function(ok, id)
		if ok and id and self.db.enabled then sets()[Stoa.ActiveSpecSlot()] = id end
	end)
	Stoa:On("ACTIVE_TALENT_GROUP_CHANGED", function()
		if self.db.enabled then xpcall(self.Wear, Stoa.catch, self) end
	end)
end
