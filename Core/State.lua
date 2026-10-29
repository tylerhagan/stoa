-- Stoa: the two states.
-- WORLD: the Grimoire console is open. COMBAT: the console folds to its spine
-- and the Halo rises. Leaving combat waits a few calm seconds so the UI does
-- not flicker between pulls. Holding Alt in combat "peeks" at the console.
local _, ns = ...
local Stoa = ns.Stoa

local WORLD, COMBAT = "WORLD", "COMBAT"
local CALM_SECONDS = 3

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

Stoa:On("PLAYER_REGEN_ENABLED", function()
	setCombatLayout(false)
	if calmTimer then calmTimer:Cancel() end
	calmTimer = C_Timer.NewTimer(CALM_SECONDS, function()
		calmTimer = nil
		if not InCombatLockdown() then
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
