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

local function setState(newState)
	if newState == state then return end
	state = newState
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

-- Peek: hold Alt in combat to see the console without leaving combat state.
local peeking = false

function Stoa:IsPeeking()
	return peeking
end

local function setPeeking(on)
	if on == peeking then return end
	peeking = on
	Stoa:Fire("STOA_PEEK_CHANGED", peeking)
end

-- Alt-tabbing away can swallow the key-up, which would leave the console
-- open. While peeking, check the key itself until it's let go.
local peekTicker
Stoa:On("MODIFIER_STATE_CHANGED", function(key, down)
	if key ~= "LALT" and key ~= "RALT" then return end
	setPeeking(state == COMBAT and down == 1)
	if peeking and not peekTicker then
		peekTicker = C_Timer.NewTicker(0.2, function()
			if not IsAltKeyDown() or state ~= COMBAT then
				setPeeking(false)
				peekTicker:Cancel()
				peekTicker = nil
			end
		end)
	end
end)
