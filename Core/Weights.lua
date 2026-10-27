-- Stoa: what gear is worth to your role.
-- Item level says little in the old world: a +12 Intellect robe is no
-- upgrade for a warrior. Each class and role here has a rough weight for
-- each stat, so an item can be scored for the role you play and compared
-- with what you wear. The weights are Stoa's own, kept simple on purpose:
-- they rank gear sensibly while levelling and in early raids, they don't
-- replace a theorycrafted list.
--
-- Stats come from the game's item stats table. Its keys differ a little
-- between clients, so each key is matched by the words in it (STRENGTH,
-- SPELL_HEALING ...) rather than by exact name.
local _, ns = ...
local Stoa = ns.Stoa

local Weights = {}
Stoa.Weights = Weights

-- Hit and crit are counted per point of percent, so their weights are large.
local W = {
	WARRIOR = {
		MELEE = { str = 2.0, agi = 1.4, sta = 0.4, ap = 1.0, hit = 18, crit = 16, dps = 6, armor = 0.01 },
		TANK = { sta = 1.5, str = 1.0, agi = 1.0, def = 1.5, dodge = 12, parry = 12, block = 4, armor = 0.08, hit = 8, dps = 3 },
	},
	PALADIN = {
		MELEE = { str = 2.0, agi = 1.2, int = 0.4, sta = 0.4, ap = 1.0, sp = 0.5, hit = 16, crit = 14, dps = 6 },
		TANK = { sta = 1.5, str = 0.8, agi = 0.8, int = 0.3, sp = 0.6, def = 1.5, dodge = 10, parry = 10, block = 4, armor = 0.08, hit = 6 },
		HEALER = { int = 1.0, heal = 0.9, sp = 0.3, mp5 = 2.0, spi = 0.3, scrit = 10, sta = 0.2 },
	},
	PRIEST = {
		RANGED = { sp = 1.0, int = 0.4, spi = 0.3, sta = 0.3, shit = 12, scrit = 8, mp5 = 1.0 },
		HEALER = { heal = 1.0, int = 0.8, spi = 0.8, mp5 = 2.0, scrit = 8, sta = 0.2 },
	},
	MAGE = {
		RANGED = { sp = 1.0, int = 0.6, spi = 0.2, sta = 0.3, shit = 14, scrit = 10, mp5 = 0.8 },
	},
	WARLOCK = {
		RANGED = { sp = 1.0, int = 0.4, sta = 0.5, spi = 0.2, shit = 14, scrit = 7 },
	},
	HUNTER = {
		RANGED = { agi = 2.0, rap = 1.0, ap = 0.8, int = 0.4, sta = 0.4, hit = 16, crit = 14, dps = 6 },
	},
	ROGUE = {
		MELEE = { agi = 1.8, str = 1.0, ap = 1.0, sta = 0.3, hit = 18, crit = 14, dps = 6 },
	},
	DRUID = {
		MELEE = { str = 2.4, agi = 1.8, sta = 0.6, ap = 1.0, int = 0.3, hit = 14, crit = 14 },
		TANK = { sta = 1.5, agi = 1.2, str = 1.0, armor = 0.1, def = 1.2, dodge = 10, hit = 6 },
		HEALER = { heal = 1.0, int = 0.8, spi = 0.9, mp5 = 2.0, scrit = 6, sta = 0.2 },
		RANGED = { sp = 1.0, int = 0.5, spi = 0.4, shit = 12, scrit = 8, mp5 = 1.0 },
	},
	SHAMAN = {
		MELEE = { str = 1.8, agi = 1.3, int = 0.4, ap = 1.0, hit = 15, crit = 13, dps = 7, sp = 0.4 },
		HEALER = { heal = 1.0, int = 0.9, mp5 = 2.4, spi = 0.3, scrit = 8 },
		RANGED = { sp = 1.0, int = 0.6, mp5 = 1.0, shit = 12, scrit = 9 },
	},
}

-- For a class playing a role it has no list for.
local BY_ROLE = {
	MELEE = W.WARRIOR.MELEE, TANK = W.WARRIOR.TANK, HEALER = W.PRIEST.HEALER, RANGED = W.MAGE.RANGED,
}

-- The game's stat key, by the words in it, to Stoa's short name. Checked in
-- order: the spell and ranged forms before the plain ones.
local KEYS = {
	{ "HIT_SPELL", "shit" }, { "SPELL_HIT", "shit" }, { "CRIT_SPELL", "scrit" }, { "SPELL_CRIT", "scrit" },
	{ "SPELL_HEALING", "heal" }, { "HEALING", "heal" },
	{ "SPELL_DAMAGE", "sp" }, { "SPELL_POWER", "sp" }, { "SPELLDAMAGE", "sp" },
	{ "RANGED_ATTACK_POWER", "rap" }, { "ATTACK_POWER", "ap" },
	{ "DAMAGE_PER_SECOND", "dps" },
	{ "STRENGTH", "str" }, { "AGILITY", "agi" }, { "STAMINA", "sta" }, { "INTELLECT", "int" }, { "SPIRIT", "spi" },
	{ "POWER_REGEN0", "mp5" }, { "MANA_REGENERATION", "mp5" },
	{ "DEFENSE", "def" }, { "DODGE", "dodge" }, { "PARRY", "parry" }, { "BLOCK", "block" },
	{ "HIT", "hit" }, { "CRIT", "crit" },
	{ "RESISTANCE0", "armor" }, { "ARMOR", "armor" },
}

local cache = {}

local function short(key)
	if cache[key] ~= nil then return cache[key] end
	local name = false
	for _, pair in ipairs(KEYS) do
		if key:find(pair[1], 1, true) then name = pair[2] break end
	end
	cache[key] = name
	return name
end

function Weights.current()
	local _, class = UnitClass("player")
	local role = Stoa:GetRole()
	if not role then return nil end
	return (W[class] and W[class][role]) or BY_ROLE[role]
end

local getStats = (C_Item and C_Item.GetItemStats) or GetItemStats

-- An item's worth to your role, or nil when its stats aren't known.
function Weights.score(link)
	local weights = Weights.current()
	if not (weights and link and getStats) or Stoa:IsSecret(link) then return nil end
	local ok, stats = pcall(getStats, link)
	if not ok or type(stats) ~= "table" then return nil end
	local total = 0
	for key, value in pairs(stats) do
		local name = type(key) == "string" and short(key)
		value = Stoa:PlainNumber(value)
		if name and value then total = total + value * (weights[name] or 0) end
	end
	return total
end
