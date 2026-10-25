-- Stoa: settings that follow your spec.
-- A few settings make sense per spec rather than per character: a Shadow
-- priest and a Discipline priest want different combat rows, tally lines
-- or threat meter rules. A module names those keys with
-- Stoa:SpecSettings(module, { "key", ... }). Whatever a key holds when you
-- change spec is kept for the spec you're leaving, and the one you're
-- going to gets back what it had. A spec that has never had its own value
-- starts from the current one, so nothing changes until you change it.
--
-- Values are kept per character in StoaCharDB.specs[slot][module][key].
local _, ns = ...
local Stoa = ns.Stoa

local keys = {} -- keys[moduleName] = { "key", ... }
local currentSlot

function Stoa:SpecSettings(module, list)
	keys[module.name] = keys[module.name] or {}
	for _, key in ipairs(list) do table.insert(keys[module.name], key) end
end

local function copy(value)
	if type(value) ~= "table" then return value end
	local out = {}
	for k, v in pairs(value) do out[k] = copy(v) end
	return out
end

local function store(slot)
	if not slot then return end
	Stoa.char.specs = Stoa.char.specs or {}
	local saved = Stoa.char.specs[slot] or {}
	Stoa.char.specs[slot] = saved
	for name, list in pairs(keys) do
		local module = Stoa.modules[name]
		if module and module.db then
			saved[name] = saved[name] or {}
			for _, key in ipairs(list) do saved[name][key] = copy(module.db[key]) end
		end
	end
end

local function restore(slot)
	local saved = Stoa.char.specs and Stoa.char.specs[slot]
	if not saved then return false end
	local changed = false
	for name, list in pairs(keys) do
		local module = Stoa.modules[name]
		local values = saved[name]
		if module and module.db and values then
			for _, key in ipairs(list) do
				if values[key] ~= nil then
					module.db[key] = copy(values[key])
					changed = true
				end
			end
		end
	end
	return changed
end

-- Runs on login and spec change, before the role is worked out again, so
-- modules see this spec's values when STOA_ROLE_CHANGED reaches them.
function Stoa:SwapSpecSettings()
	local slot = Stoa.ActiveSpecSlot and Stoa.ActiveSpecSlot() or 1
	if slot == currentSlot then return end
	store(currentSlot)
	currentSlot = slot
	if restore(slot) then Stoa:Fire("STOA_SPEC_SETTINGS", slot) end
end

Stoa:On("PLAYER_LOGIN", function() Stoa:SwapSpecSettings() end)
Stoa:On("ACTIVE_TALENT_GROUP_CHANGED", function() Stoa:SwapSpecSettings() end)
Stoa:On("PLAYER_LOGOUT", function() store(currentSlot) end)
