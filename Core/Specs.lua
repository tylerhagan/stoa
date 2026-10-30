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
-- That table is the one that counts: module.db is account-wide, so on
-- login every spec key is set from this character's table (or the key's
-- default when the character has none yet), never left holding whatever
-- the last character played with.
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

local function same(a, b)
	if type(a) ~= "table" or type(b) ~= "table" then return a == b end
	for k, v in pairs(a) do if not same(v, b[k]) then return false end end
	for k in pairs(b) do if a[k] == nil then return false end end
	return true
end

-- A character from before spec tables were kept this way has nothing saved
-- but has been playing with the values in module.db: keep those for them
-- once. A character seen for the first time starts from the defaults.
local function seedFromCurrent()
	return Stoa.char.specs == nil and Stoa.char.welcomed == true
end

local function restore(slot)
	local saved = Stoa.char.specs and Stoa.char.specs[slot]
	local keep = seedFromCurrent()
	local changed = false
	for name, list in pairs(keys) do
		local module = Stoa.modules[name]
		local values = saved and saved[name]
		if module and module.db then
			for _, key in ipairs(list) do
				local value
				if values and values[key] ~= nil then
					value = values[key]
				elseif not keep then
					value = module.defaults and module.defaults[key]
				end
				if value ~= nil and not same(module.db[key], value) then
					module.db[key] = copy(value)
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
Stoa:On("PLAYER_LOGOUT", function()
	-- A saved setup being loaded (Config/Setups.lua) brings its own values.
	if Stoa.loadingSetup then return end
	store(currentSlot)
end)
