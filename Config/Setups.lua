-- Stoa: saved setups, to take your setup to another character.
-- Theme, colour vision, ornament and every module's switches are already
-- account-wide. What a character keeps for itself (frame spots per role,
-- At a glance, combat rows and the other per-spec settings, roles and
-- click-casting) lives in its own saved file, which other characters can't
-- read. So each time you log out, Stoa keeps a copy of this character's
-- setup in the account-wide save, under the character's name. On any other
-- character, load it from the backup page, the welcome page or
-- `/stoa setups`: no text to copy.
-- Loading onto a different class keeps that character's own roles and
-- click-casting (they name class spells), and takes the rest.
local _, ns = ...
local Stoa = ns.Stoa

local Setups = {}
Stoa.Setups = Setups

-- Kept for this character whatever setup it loads.
local OWN = { welcomed = true }
-- Class-bound: only taken from a setup of the same class.
local CLASS_BOUND = { roles = true, clicks = true }

local function copy(value)
	if type(value) ~= "table" then return value end
	local out = {}
	for k, v in pairs(value) do out[k] = copy(v) end
	return out
end

local function store()
	StoaDB.setups = StoaDB.setups or {}
	return StoaDB.setups
end

local function me()
	local name = UnitName("player")
	local realm = GetRealmName and GetRealmName() or ""
	if Stoa:IsSecret(name) or not name then return nil end
	return name .. (realm ~= "" and (" - " .. realm) or ""), name
end

function Setups:Save()
	local key, name = me()
	if not key then return end
	local _, classFile = UnitClass("player")
	local character = {}
	for k, v in pairs(StoaCharDB) do
		if not OWN[k] then character[k] = copy(v) end
	end
	store()[key] = { name = name, class = classFile, at = time and time() or 0, character = character }
end

-- Other characters' setups, newest first.
function Setups:List()
	local mine = me()
	local list = {}
	for key, setup in pairs(store()) do
		if key ~= mine and type(setup) == "table" and type(setup.character) == "table" then
			list[#list + 1] = { key = key, setup = setup }
		end
	end
	table.sort(list, function(a, b) return (a.setup.at or 0) > (b.setup.at or 0) end)
	return list
end

function Setups:Load(key)
	local setup = store()[key]
	if type(setup) ~= "table" or type(setup.character) ~= "table" then return false end
	if InCombatLockdown() then
		Stoa:Print("Load a setup once combat ends.")
		return false
	end
	local _, classFile = UnitClass("player")
	local sameClass = setup.class == classFile
	local keep = {}
	for k in pairs(OWN) do keep[k] = StoaCharDB[k] end
	if not sameClass then
		for k in pairs(CLASS_BOUND) do keep[k] = StoaCharDB[k] end
	end
	for k in pairs(StoaCharDB) do StoaCharDB[k] = nil end
	for k, v in pairs(setup.character) do StoaCharDB[k] = copy(v) end
	for k, v in pairs(keep) do StoaCharDB[k] = v end
	StoaCharDB.welcomed = true
	-- The reload's logout must not write this session's per-spec values
	-- over the ones just loaded (Core/Specs.lua).
	Stoa.loadingSetup = true
	ReloadUI()
	return true
end

-- A menu of setups to load, under `owner`.
function Setups:Menu(owner)
	local list = self:List()
	if #list == 0 then
		Stoa:Print("No other character's setup is saved yet. Each character's is saved when it logs out.")
		return
	end
	if not (MenuUtil and MenuUtil.CreateContextMenu) then
		Stoa.commands.setups("")
		return
	end
	MenuUtil.CreateContextMenu(owner, function(_, root)
		root:CreateTitle("Load a setup (reloads)")
		for _, entry in ipairs(list) do
			local setup = entry.setup
			local label = setup.name or entry.key
			local _, classFile = UnitClass("player")
			if setup.class and setup.class ~= classFile then label = label .. " (layout only)" end
			root:CreateButton(label, function() Setups:Load(entry.key) end)
		end
	end)
end

Stoa:On("PLAYER_LOGOUT", function()
	if Stoa.loadingSetup then return end
	xpcall(Setups.Save, Stoa.catch, Setups)
end)

Stoa.commands.setups = function(rest)
	rest = strtrim(rest or "")
	local list = Setups:List()
	if rest == "" then
		if #list == 0 then
			Stoa:Print("No other character's setup is saved yet. Each character's is saved when it logs out.")
			return
		end
		Stoa:Print("Saved setups (/stoa setups load <number>):")
		local _, classFile = UnitClass("player")
		for i, entry in ipairs(list) do
			local other = entry.setup.class and entry.setup.class ~= classFile
			Stoa:Print(("  %d. %s%s"):format(i, entry.key, other and ", another class: frames, At a glance and spec settings only" or ""))
		end
		return
	end
	local index = tonumber(rest:match("^load%s+(%d+)$") or "")
	local entry = index and list[index]
	if not entry then
		Stoa:Print("Use /stoa setups to list them and /stoa setups load <number> to load one.")
		return
	end
	Setups:Load(entry.key)
end
