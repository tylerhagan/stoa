-- Stoa: the two states.
-- WORLD: the Grimoire console is open. COMBAT: the console folds to its spine
-- and the Halo rises. Leaving combat waits a few calm seconds (a setting: 1,
-- 3, 5 or 8) so the UI does not flicker between pulls, and in a group it
-- also waits while the people near you are still fighting, so a chain of
-- pulls stays one fight. The console can also stay open in combat
-- (Stoa.db.combatConsole, see Modules/Grimoire/Console.lua).
local _, ns = ...
local Stoa = ns.Stoa

local WORLD, COMBAT = "WORLD", "COMBAT"
local CALM_SECONDS = 3
-- How often the calm is checked, and the longest a fighting group can hold
-- the combat look after you've left combat.
local CALM_STEP = 0.5
local GROUP_HOLD = 20

Stoa.STATE_WORLD = WORLD
Stoa.STATE_COMBAT = COMBAT

local state = WORLD
local calmTimer
local practising = false
local combatLayout = false

function Stoa:GetState()
	return state
end

-- One clock for everything that times in combat: ticks only while the state
-- is combat (real or practice), and fires STOA_TICK with the time.
local clock

local function setClock()
	if state == COMBAT then
		if not clock then
			clock = Stoa:NewTicker(0.2, function() Stoa:Fire("STOA_TICK", GetTime()) end)
		end
	elseif clock then
		clock:Cancel()
		clock = nil
	end
end

local function setState(newState)
	if newState == state then return end
	state = newState
	setClock()
	Stoa:Fire("STOA_STATE_CHANGED", state)
end

-- Some frames sit one way out of combat and another in it: group frames
-- sit higher while the console is open, lower under the combat bar in a
-- fight. Secure frames can only move out of combat, and the handlers of
-- PLAYER_REGEN_DISABLED still run just before the lockdown begins, so they
-- move then, on STOA_COMBAT_LAYOUT.
function Stoa:CombatLayout()
	return combatLayout or InCombatLockdown()
end

local function setCombatLayout(on)
	if on == combatLayout then return end
	combatLayout = on
	Stoa:Fire("STOA_COMBAT_LAYOUT", on)
end

Stoa:On("PLAYER_REGEN_DISABLED", function()
	practising = false
	if calmTimer then
		calmTimer:Cancel()
		calmTimer = nil
	end
	setCombatLayout(true)
	setState(COMBAT)
end)

function Stoa:CalmSeconds()
	return tonumber(self.db and self.db.calm) or CALM_SECONDS
end

-- Someone in your group, near you and alive, still in a fight.
local function groupFighting()
	if not (Stoa.db and Stoa.db.calmGroup ~= false) or not IsInGroup() then return false end
	local raid = IsInRaid()
	local count = raid and GetNumGroupMembers() or GetNumSubgroupMembers()
	for i = 1, count do
		local unit = (raid and "raid" or "party") .. i
		if not UnitIsUnit(unit, "player") then
			local fighting = UnitAffectingCombat(unit)
			local near = not UnitInRange or UnitInRange(unit)
			if not Stoa:IsSecret(fighting) and not Stoa:IsSecret(near) and fighting and near and not UnitIsDeadOrGhost(unit) then
				return true
			end
		end
	end
	return false
end

Stoa:On("PLAYER_REGEN_ENABLED", function()
	setCombatLayout(false)
	if calmTimer then calmTimer:Cancel() end
	-- The calm seconds count only while the group is calm too.
	local calm, waited = 0, 0
	calmTimer = Stoa:NewTicker(CALM_STEP, function()
		if InCombatLockdown() then return end
		waited = waited + CALM_STEP
		local ok, fighting = pcall(groupFighting)
		if not (ok and fighting) or waited >= GROUP_HOLD then calm = calm + CALM_STEP end
		if calm >= Stoa:CalmSeconds() then
			calmTimer:Cancel()
			calmTimer = nil
			setState(WORLD)
		end
	end)
end)

-- /stoa combat: a practice combat state out of combat, for checking
-- layouts. The console folds, the Halo and combat bar show, the group
-- frames move. Real combat, or /stoa combat again, ends it.
function Stoa:IsPractising()
	return practising
end

Stoa.commands.combat = function()
	if InCombatLockdown() then
		Stoa:Print("You're already in combat.")
		return
	end
	practising = not practising
	setCombatLayout(practising)
	setState(practising and COMBAT or WORLD)
	Stoa:Print(practising and "Practice combat on. /stoa combat again to end it." or "Practice combat off.")
end

Stoa:On("PLAYER_ENTERING_WORLD", function()
	setState(InCombatLockdown() and COMBAT or WORLD)
end)
