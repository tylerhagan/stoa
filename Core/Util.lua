-- Stoa: small shared helpers.
local _, ns = ...
local Stoa = ns.Stoa

-- Secret values -------------------------------------------------------------
-- On Forever, many unit values are "secret" in combat: they can be shown by a
-- widget (StatusBar:SetValue, FontString:SetText) but not compared or used in
-- maths. Every place that reads a unit value goes through these helpers.

local issecret = _G.issecretvalue or function() return false end

function Stoa:IsSecret(value)
	return issecret(value)
end

-- Returns the value when it is a plain number, otherwise nil. Use this before
-- any comparison or arithmetic.
function Stoa:PlainNumber(value)
	if issecret(value) or type(value) ~= "number" then
		return nil
	end
	return value
end

-- Combat lockdown -----------------------------------------------------------
-- Protected changes (moving secure frames, changing bindings) cannot happen in
-- combat. Queue them and run them when combat ends.

local queue = {}

function Stoa:AfterCombat(fn)
	if InCombatLockdown() then
		table.insert(queue, fn)
	else
		fn()
	end
end

Stoa:On("PLAYER_REGEN_ENABLED", function()
	local pending = queue
	queue = {}
	-- One failing change must not stop the rest.
	for i = 1, #pending do
		xpcall(pending[i], Stoa.catch)
	end
end)

-- Tables --------------------------------------------------------------------

-- Fills missing keys in target from defaults, recursively, without
-- overwriting what the player has already set.
function Stoa:ApplyDefaults(target, defaults)
	for key, value in pairs(defaults) do
		if type(value) == "table" then
			if type(target[key]) ~= "table" then
				target[key] = {}
			end
			self:ApplyDefaults(target[key], value)
		elseif target[key] == nil then
			target[key] = value
		end
	end
	return target
end
