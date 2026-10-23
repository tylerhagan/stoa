-- Stoa: role detection.
-- The UI is built on four role layouts (Tank, Healer, Melee, Ranged). Each
-- dual-spec slot maps to one role. Forever reworked talents, so instead of
-- guessing from talent trees we use a sensible class default and let the
-- player set each slot in settings.
local _, ns = ...
local Stoa = ns.Stoa

Stoa.ROLES = { "TANK", "HEALER", "MELEE", "RANGED" }
Stoa.ROLE_LABELS = { TANK = "Tank", HEALER = "Healer", MELEE = "Melee DPS", RANGED = "Ranged DPS" }

-- What a class most likely plays when we know nothing else.
local classDefault = {
	WARRIOR = "MELEE", ROGUE = "MELEE", PALADIN = "MELEE", SHAMAN = "MELEE",
	DRUID = "MELEE", HUNTER = "RANGED", MAGE = "RANGED", WARLOCK = "RANGED",
	PRIEST = "RANGED",
}

local function activeSlot()
	if C_SpecializationInfo and C_SpecializationInfo.GetActiveSpecGroup then
		return C_SpecializationInfo.GetActiveSpecGroup() or 1
	end
	if GetActiveTalentGroup then
		return GetActiveTalentGroup() or 1
	end
	return 1
end

Stoa.ActiveSpecSlot = activeSlot

local currentRole

function Stoa:GetRole()
	return currentRole
end

-- Roles are stored as roles.slot1 / roles.slot2; "AUTO" means class default.
function Stoa:SetRoleForSlot(slot, role)
	self.char.roles["slot" .. slot] = role
	self:UpdateRole()
end

-- What this character's class plays when no role is chosen.
function Stoa:DefaultRole()
	local _, class = UnitClass("player")
	return classDefault[class] or "MELEE"
end

function Stoa:UpdateRole()
	local chosen = self.char.roles["slot" .. activeSlot()]
	local role = (chosen ~= "AUTO" and chosen) or self:DefaultRole()
	if role ~= currentRole then
		local previous = currentRole
		currentRole = role
		self:Fire("STOA_ROLE_CHANGED", role, previous)
	end
end

Stoa:On("PLAYER_LOGIN", function() Stoa:UpdateRole() end)
Stoa:On("ACTIVE_TALENT_GROUP_CHANGED", function() Stoa:UpdateRole() end)
Stoa:On("PLAYER_TALENT_UPDATE", function() Stoa:UpdateRole() end)
