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

function Stoa:GetState()
	return state
end

local function setState(newState)
	if newState == state then return end
	state = newState
	Stoa:Fire("STOA_STATE_CHANGED", state)
end

Stoa:On("PLAYER_REGEN_DISABLED", function()
	if calmTimer then
		calmTimer:Cancel()
		calmTimer = nil
	end
	setState(COMBAT)
end)

Stoa:On("PLAYER_REGEN_ENABLED", function()
	if calmTimer then calmTimer:Cancel() end
	calmTimer = C_Timer.NewTimer(CALM_SECONDS, function()
		calmTimer = nil
		if not InCombatLockdown() then
			setState(WORLD)
		end
	end)
end)

Stoa:On("PLAYER_ENTERING_WORLD", function()
	setState(InCombatLockdown() and COMBAT or WORLD)
end)

-- Peek: hold Alt in combat to see the console without leaving combat state.
local peeking = false

function Stoa:IsPeeking()
	return peeking
end

Stoa:On("MODIFIER_STATE_CHANGED", function(key, down)
	if key ~= "LALT" and key ~= "RALT" then return end
	local nowPeeking = state == COMBAT and down == 1
	if nowPeeking ~= peeking then
		peeking = nowPeeking
		Stoa:Fire("STOA_PEEK_CHANGED", peeking)
	end
end)
