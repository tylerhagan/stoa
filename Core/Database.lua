-- Stoa: saved settings.
-- StoaDB is the account-wide save; StoaCharDB is per character (which role
-- each spec slot plays, frame positions).
--
-- Settings are per character. The code reads them from StoaDB (Stoa.db and
-- each module.db), so each character keeps its own copy in
-- StoaCharDB.settings: at load that copy is put into StoaDB, and at logout
-- StoaDB's settings are copied back. A character with no copy yet starts
-- from the settings the last character left, so it's set up from the
-- first login. What's shared stays shared: junk marks, other addons'
-- choices, the game settings ledger, alts, saved setups, trainer data.
local _, ns = ...
local Stoa = ns.Stoa

local accountDefaults = {
	-- Bumped when saved settings change shape, so later versions can move
	-- old settings over instead of losing them.
	schema = 1,
	theme = "Bone",
	vision = "Standard",
	-- The stone behind windows.
	windowStone = true,
	smoothBars = true,
	-- In combat the console folds ("fold") or stays open ("open"); after a
	-- fight it opens again once things have been calm this many seconds
	-- ("1", "3", "5" or "8"), waiting for the group nearby when calmGroup.
	combatConsole = "fold",
	calm = "5",
	calmGroup = true,
	countdownCombat = "raid",
	-- Fold and open at once, without the short slide.
	foldInstant = false,
	-- The spell's art behind the letter in the Halo's coins.
	coinArt = true,
	-- "painted" puts the leather and brass frames on the minimap, the
	-- portrait coins and the Halo's signature slot; "plain" keeps lines.
	ornament = "plain",
	-- Items marked as junk, by itemID, sold with the greys.
	junk = {},
	modules = {},
}

local characterDefaults = {
	-- Role for each dual-spec slot. "AUTO" means use the class default.
	roles = { slot1 = "AUTO", slot2 = "AUTO" },
	-- Older, layout-free spots; kept so earlier saves still work.
	positions = {},
	-- Frame spots per role layout: layouts.HEALER.party and so on.
	layouts = {},
	-- Click-cast bindings per role, filled from defaults on first use.
	clicks = {},
	-- Whether this character has seen the welcome page.
	welcomed = false,
}

-- The account-wide keys that are really one character's settings.
local PERSONAL = { "modules", "preset" }
for key in pairs(accountDefaults) do
	if key ~= "schema" and key ~= "junk" and key ~= "modules" then PERSONAL[#PERSONAL + 1] = key end
end

local function copy(value)
	if type(value) ~= "table" then return value end
	local out = {}
	for k, v in pairs(value) do out[k] = copy(v) end
	return out
end

-- This character's settings into StoaDB, where the code reads them.
local function loadSettings()
	local mine = StoaCharDB.settings
	if type(mine) ~= "table" then return end
	for _, key in ipairs(PERSONAL) do StoaDB[key] = copy(mine[key]) end
end

-- StoaDB's settings into this character's save.
function Stoa:SaveSettings()
	if not (StoaDB and StoaCharDB) then return end
	local mine = {}
	for _, key in ipairs(PERSONAL) do mine[key] = copy(StoaDB[key]) end
	StoaCharDB.settings = mine
end

function Stoa:InitializeDatabase()
	StoaDB = StoaDB or {}
	StoaCharDB = self:ApplyDefaults(StoaCharDB or {}, characterDefaults)
	loadSettings()
	StoaDB = self:ApplyDefaults(StoaDB, accountDefaults)

	for name, module in pairs(self.modules) do
		StoaDB.modules[name] = self:ApplyDefaults(StoaDB.modules[name] or {}, module.defaults)
		if StoaDB.modules[name].enabled == nil then
			StoaDB.modules[name].enabled = true
		end
		module.db = StoaDB.modules[name]
	end

	self.db = StoaDB
	self.char = StoaCharDB
end

-- Loading a saved setup or a backup puts its own settings in place before the
-- reload; this session's must not be written over them.
Stoa:On("PLAYER_LOGOUT", function()
	if Stoa.loadingSetup or Stoa.loadingBackup then return end
	Stoa:SaveSettings()
end)
