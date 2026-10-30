-- Stoa: your group, as a list of units.
-- Buff reminders, the threat meter and the marker strip all walk the same
-- group. Stoa:GroupUnits() gives the units in order (you first), and
-- STOA_GROUP_CHANGED fires once when the group's make-up settles.
local _, ns = ...
local Stoa = ns.Stoa

local units = { "player" }

local function count(fn)
	local ok, n = pcall(fn)
	return ok and type(n) == "number" and n or 0
end

local function rebuild()
	wipe(units)
	if IsInRaid() then
		for i = 1, count(GetNumGroupMembers) do units[#units + 1] = "raid" .. i end
	else
		units[1] = "player"
		for i = 1, math.min(4, count(GetNumSubgroupMembers)) do units[#units + 1] = "party" .. i end
	end
end

-- The units in your group, you included. Don't change the list you get.
function Stoa:GroupUnits()
	return units
end

-- "solo", "party" or "raid".
function Stoa:GroupKind()
	if IsInRaid() then return "raid" end
	if IsInGroup() then return "party" end
	return "solo"
end

-- True when you lead the group or are an assistant in a raid, so raid
-- markers and countdowns are yours to use.
function Stoa:CanLead()
	if not IsInGroup() then return true end
	if UnitIsGroupLeader("player") then return true end
	return IsInRaid() and UnitIsGroupAssistant and UnitIsGroupAssistant("player") or false
end

local pending
local function changed()
	if pending then return end
	pending = true
	C_Timer.After(0.2, function()
		pending = false
		rebuild()
		Stoa:Fire("STOA_GROUP_CHANGED", Stoa:GroupKind())
	end)
end

Stoa:On("PLAYER_LOGIN", rebuild)
Stoa:On("GROUP_ROSTER_UPDATE", changed)
Stoa:On("PLAYER_ENTERING_WORLD", changed)
