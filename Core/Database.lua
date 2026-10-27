-- Stoa: saved settings.
-- StoaDB is account-wide (theme, module switches). StoaCharDB is per character
-- (which role each spec slot plays, frame positions).
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

function Stoa:InitializeDatabase()
	StoaDB = self:ApplyDefaults(StoaDB or {}, accountDefaults)
	StoaCharDB = self:ApplyDefaults(StoaCharDB or {}, characterDefaults)

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
