-- Stoa: At a glance (the module is still called Tally), a few numbers you
-- choose beside the chat.
-- Out of combat the console carries a small block to the right of chat:
-- up to eight label and value rows in two columns, like the right page's
-- columns. It follows where you are: one set out in the world (gold,
-- loot, professions, reputation, gear and bags), one in a dungeon and one
-- in a raid (your role's stats, then gear, bags or latency). Each set is
-- yours to change (right-click it, or /stoa glance), saved per character
-- and spec, and a line you pin shows in every set. Until you change a set
-- it follows your role:
--   Healer: healing, mana regen, spell crit, intellect;
--   Ranged: spell power, spell crit, hit, intellect;
--   Melee: attack power, crit, hit, agility or strength;
--   Tank: armor, defense, dodge, stamina.
-- Hovering a line shows where its number comes from, and clicking it opens
-- the window you'd go to next (the character sheet for stats, bags for bag
-- room, reputation for a faction, and so on).
--
-- Anything another addon publishes through LibDataBroker (the feeds Titan
-- Panel and similar bars show) can be picked too: its text shows as the
-- value, and clicking or hovering the row does what that addon does.
--
-- Numbers are read out of combat only (the console is folded then), and
-- every game function is checked before it's used.
local _, ns = ...
local Stoa = ns.Stoa
local UI = Stoa.UI

local Tally = Stoa:NewModule("Tally", {
	follow = true,
})

local MAX_ROWS = 8
local ROWS_PER_COLUMN = 4
local COLUMN_WIDTH = 170
local COLUMN_GAP = 36
local ROW_GAP = 20
-- Room left from the chat's right edge, and kept clear either side of the
-- centre for the medallion and the health bar.
local CHAT_RIGHT = 440 + 44
local CENTRE_CLEAR = 340
local REFRESH_SECONDS = 2
local LOW_WEAR, LOW_BAGS = 0.25, 2

local call = Stoa.safe.call

local function plain(value)
	value = Stoa:PlainNumber(value)
	return type(value) == "number" and value or nil
end

local function whole(value)
	value = plain(value)
	return value and tostring(math.floor(value + 0.5))
end

local function percent(value)
	value = plain(value)
	return value and ("%.1f%%"):format(value)
end

-- The best of a value across the magic schools (2 holy to 7 arcane).
local function bestSchool(fn)
	local best
	for school = 2, 7 do
		local value = plain(call(fn, school))
		if value and (not best or value > best) then best = value end
	end
	return best
end

local function stat(index)
	return function()
		local _, effective = call(UnitStat, "player", index)
		return whole(effective)
	end
end

local GEAR_SLOTS = { 1, 3, 5, 6, 7, 8, 9, 10, 16, 17, 18 }

local function money()
	local copper = plain(call(GetMoney))
	if not copper then return nil end
	local gold, silver = math.floor(copper / 10000), math.floor(copper / 100) % 100
	if gold > 0 then return ("%dg %02ds"):format(gold, silver) end
	return ("%ds %02dc"):format(silver, copper % 100)
end

-- Hover and click ------------------------------------------------------------------
-- An entry's detail(add) calls add(left, right) for each line of its
-- breakdown; its open() opens the window you'd go to next, and its action
-- names that window in the tooltip.

local function run(name, ...)
	local fn = _G[name]
	if type(fn) ~= "function" then return false end
	return (pcall(fn, ...))
end

local OPEN = {
	character = { "Character sheet", function() return run("ToggleCharacter", "PaperDollFrame") end },
	reputation = { "Reputation", function() return run("ToggleCharacter", "ReputationFrame") end },
	bags = { "Bags", function() return run("ToggleAllBags") end },
	money = { "Currencies", function()
		if _G.TokenFrame and run("ToggleCharacter", "TokenFrame") then return true end
		return run("ToggleAllBags")
	end },
	professions = { "Professions", function()
		if _G.ProfessionsBookFrame and run("ToggleProfessionsBook") then return true end
		if _G.SkillFrame and run("ToggleCharacter", "SkillFrame") then return true end
		return run("ToggleSpellBook", "professions")
	end },
	map = { "Map", function() return run("ToggleWorldMap") end },
	clock = { "Clock", function() return run("ToggleTimeManager") or run("TimeManager_Toggle") end },
}

local function signed(value)
	value = math.floor(value + 0.5)
	return (value >= 0 and "+" or "") .. value
end

local SCHOOLS = { "Holy", "Fire", "Nature", "Frost", "Shadow", "Arcane" }

-- Each school with a value, for spell power and spell crit.
local function bySchool(fn, format)
	return function(add)
		for school = 2, 7 do
			local value = plain(call(fn, school))
			if value and value > 0 then add(SCHOOLS[school - 1], format(value)) end
		end
	end
end

local function statDetail(index)
	return function(add)
		local base, effective, up, down = call(UnitStat, "player", index)
		base, effective = plain(base), plain(effective)
		if not (base and effective) then return end
		add("Base", whole(base))
		up, down = plain(up) or 0, plain(down) or 0
		if effective ~= base or up ~= 0 or down ~= 0 then add("From gear and buffs", signed(effective - base)) end
	end
end

local function powerDetail(fn)
	return function(add)
		local base, plus, minus = call(fn, "player")
		base, plus, minus = plain(base), plain(plus) or 0, plain(minus) or 0
		if not base then return end
		add("Base", whole(base))
		if plus ~= 0 then add("Buffs", signed(plus)) end
		if minus ~= 0 then add("Debuffs", signed(minus)) end
	end
end

-- Money and reputation at login, for "this session".
local session = {}

local function moneyText(copper)
	local sign = copper < 0 and "-" or "+"
	copper = math.abs(copper)
	local gold, silver = math.floor(copper / 10000), math.floor(copper / 100) % 100
	if gold > 0 then return ("%s%dg %02ds"):format(sign, gold, silver) end
	return ("%s%ds %02dc"):format(sign, silver, copper % 100)
end

-- Professions -------------------------------------------------------------------
-- The modern list where the game has it (GetProfessions), otherwise the
-- skill lines under the professions headers.

local SECONDARY = { Cooking = "cooking", Fishing = "fishing", ["First Aid"] = "firstAid" }
local PROFESSIONS = {
	Alchemy = true, Blacksmithing = true, Enchanting = true, Engineering = true,
	Herbalism = true, Inscription = true, Jewelcrafting = true, Leatherworking = true,
	Mining = true, Skinning = true, Tailoring = true,
}

local function readProfessions()
	local found = {}
	if GetProfessions and GetProfessionInfo then
		local one, two, _, fishing, cooking, firstAid = call(GetProfessions)
		for key, index in pairs({ prof1 = one, prof2 = two, fishing = fishing, cooking = cooking, firstAid = firstAid }) do
			if index then
				local name, _, rank, max = call(GetProfessionInfo, index)
				if name then found[key] = { name, rank, max } end
			end
		end
		return found
	end
	if not (GetNumSkillLines and GetSkillLineInfo) then return found end
	local primary = 0
	for i = 1, (call(GetNumSkillLines) or 0) do
		local name, isHeader, _, rank, _, _, max = call(GetSkillLineInfo, i)
		if name and not isHeader then
			if PROFESSIONS[name] and primary < 2 then
				primary = primary + 1
				found["prof" .. primary] = { name, rank, max }
			elseif SECONDARY[name] then
				found[SECONDARY[name]] = { name, rank, max }
			end
		end
	end
	return found
end

local professions = {}

local function profession(key, fallback)
	return {
		label = function() local p = professions[key] return p and p[1] or fallback end,
		value = function()
			local p = professions[key]
			if not p then return nil end
			local rank, max = plain(p[2]), plain(p[3])
			if not rank then return nil end
			return max and ("%d / %d"):format(rank, max) or tostring(rank)
		end,
		figure = function()
			local p = professions[key]
			local rank, max = p and plain(p[2]), p and plain(p[3])
			if rank and max and max > 0 then return "bar", rank / max, "text" end
		end,
		detail = function(add)
			local p = professions[key]
			local rank, max = p and plain(p[2]), p and plain(p[3])
			if not (rank and max) then return end
			add("Skill", ("%d of %d"):format(rank, max))
			if rank >= max then add("Next", "Visit a trainer") else add("To go", tostring(max - rank)) end
		end,
		open = "professions",
	}
end

-- How far into the watched faction's current standing you are, and its size.
local function standing()
	local data = C_Reputation and call(C_Reputation.GetWatchedFactionData)
	local low, high, value
	if type(data) == "table" and data.name then
		low, high, value = data.currentReactionThreshold, data.nextReactionThreshold, data.currentStanding
	else
		local name, _, min, max, current = call(GetWatchedFactionInfo)
		if not name then return nil end
		low, high, value = min, max, current
	end
	low, high, value = plain(low), plain(high), plain(value)
	if not (low and high and value) or high <= low then return nil end
	return value - low, high - low
end

-- Gear and bags, shared by the words and the small figures.
local function lowestWear()
	local lowest
	for _, slot in ipairs(GEAR_SLOTS) do
		local current, max = call(GetInventoryItemDurability, slot)
		current, max = plain(current), plain(max)
		if current and max and max > 0 and (not lowest or current / max < lowest) then lowest = current / max end
	end
	return lowest
end

-- Free slots in all bags, and one { used share, full } per bag.
local function bagRoom()
	local getFree = C_Container and C_Container.GetContainerNumFreeSlots or GetContainerNumFreeSlots
	local getSize = C_Container and C_Container.GetContainerNumSlots or GetContainerNumSlots
	if not (getFree and getSize) then return nil end
	local free, list = 0, {}
	for bag = 0, 4 do
		local size = plain(call(getSize, bag)) or 0
		if size > 0 then
			local open = plain(call(getFree, bag)) or 0
			free = free + open
			list[#list + 1] = { (size - open) / size, open == 0 }
		end
	end
	return free, list
end

-- Entries -----------------------------------------------------------------------
-- Each: a label (or a function giving one), a value function returning the
-- words to show and whether they warn, and the group the picker lists it in.
-- A figure function draws the number as well, beside the words: it returns
-- "bar", share, colour; "columns", a list of { share, full }; or "spark", a
-- list of recent values.

local ENTRIES = {
	strength = { label = "Strength", group = "Stats", value = stat(1), detail = statDetail(1), open = "character" },
	agility = { label = "Agility", group = "Stats", value = stat(2), detail = statDetail(2), open = "character" },
	stamina = { label = "Stamina", group = "Stats", value = stat(3), detail = statDetail(3), open = "character" },
	intellect = { label = "Intellect", group = "Stats", value = stat(4), detail = statDetail(4), open = "character" },
	spirit = { label = "Spirit", group = "Stats", value = stat(5), detail = statDetail(5), open = "character" },
	attackPower = { label = "Attack power", group = "Stats", value = function()
		local base, plus, minus = call(UnitAttackPower, "player")
		base, plus, minus = plain(base), plain(plus) or 0, plain(minus) or 0
		return base and whole(base + plus + minus)
	end, detail = powerDetail(UnitAttackPower), open = "character" },
	rangedPower = { label = "Ranged power", group = "Stats", value = function()
		local base, plus, minus = call(UnitRangedAttackPower, "player")
		base, plus, minus = plain(base), plain(plus) or 0, plain(minus) or 0
		return base and whole(base + plus + minus)
	end, detail = powerDetail(UnitRangedAttackPower), open = "character" },
	spellPower = { label = "Spell power", group = "Stats", value = function() return whole(bestSchool(GetSpellBonusDamage)) end,
		detail = bySchool(GetSpellBonusDamage, whole), open = "character" },
	healing = { label = "Healing", group = "Stats", value = function() return whole(call(GetSpellBonusHealing)) end, open = "character" },
	crit = { label = "Crit", group = "Stats", value = function() return percent(call(GetCritChance)) end, detail = function(add)
		local ranged = plain(call(GetRangedCritChance))
		if ranged then add("Ranged", percent(ranged)) end
	end, open = "character" },
	spellCrit = { label = "Spell crit", group = "Stats", value = function() return percent(bestSchool(GetSpellCritChance)) end,
		detail = bySchool(GetSpellCritChance, percent), open = "character" },
	hit = { label = "Hit", group = "Stats", value = function()
		local bonus = plain(call(GetHitModifier))
		return bonus and ("+%d%%"):format(bonus)
	end, detail = function(add)
		local spell = plain(call(GetSpellHitModifier))
		if spell then add("Spell hit", ("+%d%%"):format(spell)) end
	end, open = "character" },
	regen = { label = "Mana / 5s", group = "Stats", value = function()
		local _, casting = call(GetManaRegen)
		casting = plain(casting)
		return casting and whole(casting * 5)
	end, detail = function(add)
		local resting, casting = call(GetManaRegen)
		resting, casting = plain(resting), plain(casting)
		if casting then add("While casting", whole(casting * 5)) end
		if resting then add("Outside the five-second rule", whole(resting * 5)) end
	end, open = "character" },
	armor = { label = "Armor", group = "Stats", value = function()
		local _, effective = call(UnitArmor, "player")
		return whole(effective)
	end, detail = function(add)
		local base, effective = call(UnitArmor, "player")
		base, effective = plain(base), plain(effective)
		if base then add("Base", whole(base)) end
		if base and effective and effective ~= base then add("From buffs", signed(effective - base)) end
		local reduce = effective and plain(call(PaperDollFrame_GetArmorReduction, effective, UnitLevel("player")))
		if reduce then add("Physical damage taken", ("-%.1f%%"):format(reduce)) end
	end, open = "character" },
	defense = { label = "Defense", group = "Stats", value = function()
		local base, bonus = call(UnitDefense, "player")
		base, bonus = plain(base), plain(bonus) or 0
		return base and whole(base + bonus)
	end, detail = function(add)
		local base, bonus = call(UnitDefense, "player")
		base, bonus = plain(base), plain(bonus) or 0
		if base then add("Skill", whole(base)) end
		if bonus ~= 0 then add("From gear", signed(bonus)) end
	end, open = "character" },
	dodge = { label = "Dodge", group = "Stats", value = function() return percent(call(GetDodgeChance)) end, open = "character" },
	parry = { label = "Parry", group = "Stats", value = function() return percent(call(GetParryChance)) end, open = "character" },
	block = { label = "Block", group = "Stats", value = function() return percent(call(GetBlockChance)) end, open = "character" },

	durability = { label = "Gear", group = "Kit", value = function()
		local lowest = lowestWear()
		if not lowest then return "Whole" end
		return math.floor(lowest * 100 + 0.5) .. "%", lowest < LOW_WEAR
	end, figure = function()
		local share = lowestWear() or 1
		return "bar", share, Stoa.Figures.wear(share)
	end, detail = function(add)
		local worn = {}
		for _, slot in ipairs(GEAR_SLOTS) do
			local current, max = call(GetInventoryItemDurability, slot)
			current, max = plain(current), plain(max)
			if current and max and max > 0 and current < max then
				local link = call(GetInventoryItemLink, "player", slot)
				local name = link and call(GetItemInfo, link)
				worn[#worn + 1] = { name or ("Slot " .. slot), current / max }
			end
		end
		table.sort(worn, function(a, b) return a[2] < b[2] end)
		for i = 1, math.min(3, #worn) do add(worn[i][1], math.floor(worn[i][2] * 100 + 0.5) .. "%") end
		if #worn == 0 then add("Everything", "Whole") end
	end, open = "character" },
	bags = { label = "Bags free", group = "Kit", value = function()
		local free = bagRoom()
		if not free then return nil end
		return tostring(free), free <= LOW_BAGS
	end, figure = function()
		local _, list = bagRoom()
		if list then return "columns", list end
	end, detail = function(add)
		local getFree = C_Container and C_Container.GetContainerNumFreeSlots or GetContainerNumFreeSlots
		local getSize = C_Container and C_Container.GetContainerNumSlots or GetContainerNumSlots
		if not (getFree and getSize) then return end
		for bag = 0, 4 do
			local size = plain(call(getSize, bag))
			if size and size > 0 then
				add(bag == 0 and "Backpack" or ("Bag " .. bag), ("%d of %d free"):format(plain(call(getFree, bag)) or 0, size))
			end
		end
	end, open = "bags" },
	gold = { label = "Gold", group = "Kit", value = money, detail = function(add)
		local copper = plain(call(GetMoney))
		if copper and session.money then add("This session", moneyText(copper - session.money)) end
	end, open = "money" },

	prof1 = profession("prof1", "Profession"),
	prof2 = profession("prof2", "Second profession"),
	cooking = profession("cooking", "Cooking"),
	fishing = profession("fishing", "Fishing"),
	firstAid = profession("firstAid", "First Aid"),

	zone = { label = "Zone", group = "World", value = function()
		local sub, zone = call(GetSubZoneText), call(GetZoneText)
		return (sub and sub ~= "" and sub) or zone
	end, detail = function(add)
		local zone = call(GetZoneText)
		if zone and zone ~= "" then add("Zone", zone) end
		local kind = call(GetZonePVPInfo)
		local words = { sanctuary = "Sanctuary", friendly = "Friendly", hostile = "Hostile", contested = "Contested", combat = "Combat zone" }
		if kind and words[kind] then add("Territory", words[kind]) end
	end, open = "map" },
	reputation = { label = function()
		local data = C_Reputation and call(C_Reputation.GetWatchedFactionData)
		if type(data) == "table" and data.name then return data.name end
		local name = call(GetWatchedFactionInfo)
		return name or "Reputation"
	end, group = "World", value = function()
		local into, span = standing()
		if not into then return nil end
		return ("%d / %d"):format(into, span)
	end, figure = function()
		local into, span = standing()
		if into then return "bar", into / span, "text" end
	end, detail = function(add)
		local data = C_Reputation and call(C_Reputation.GetWatchedFactionData)
		local name, reaction, value
		if type(data) == "table" and data.name then
			name, reaction, value = data.name, data.reaction, data.currentStanding
		else
			local standing, _, _, current
			name, standing, _, _, current = call(GetWatchedFactionInfo)
			reaction, value = standing, current
		end
		reaction, value = plain(reaction), plain(value)
		local word = reaction and _G["FACTION_STANDING_LABEL" .. reaction]
		if word then add("Standing", word) end
		if name and value and session.rep and session.rep[1] == name then add("This session", signed(value - session.rep[2])) end
	end, open = "reputation" },
	clock = { label = "Time", group = "World", value = function() return date("%H:%M") end, detail = function(add)
		local hour, minute = call(GetGameTime)
		hour, minute = plain(hour), plain(minute)
		if hour and minute then add("Realm time", ("%02d:%02d"):format(hour, minute)) end
	end, open = "clock" },
	latency = { label = "Latency", group = "World", value = function()
		local _, _, home, world = call(GetNetStats)
		local ms = plain(world) or plain(home)
		return ms and (ms .. " ms")
	end, detail = function(add)
		local _, _, home, world = call(GetNetStats)
		home, world = plain(home), plain(world)
		if home then add("Home", home .. " ms") end
		if world then add("World", world .. " ms") end
	end },
	framerate = { label = "Framerate", group = "World", value = function()
		local fps = plain(call(GetFramerate))
		return fps and (math.floor(fps + 0.5) .. " fps")
	end },
}

for _, key in ipairs({ "prof1", "prof2", "cooking", "fishing", "firstAid" }) do ENTRIES[key].group = "Professions" end

-- The picker's order.
local GROUPS = {
	{ "Stats", { "strength", "agility", "stamina", "intellect", "spirit", "attackPower", "rangedPower", "spellPower", "healing", "crit", "spellCrit", "hit", "regen", "armor", "defense", "dodge", "parry", "block" } },
	{ "Kit", { "durability", "bags", "gold" } },
	{ "Professions", { "prof1", "prof2", "cooking", "fishing", "firstAid" } },
	{ "World", { "zone", "reputation", "clock", "latency", "framerate" } },
}

-- Other parts of Stoa, and other addons through StoaAPI, add entries
-- here: Tally:Register("goldHour", { label = "Gold an hour", value = fn },
-- "Kit"). value returns the text and, optionally, true to warn.
function Tally:Register(key, entry, groupName)
	if type(key) ~= "string" or type(entry) ~= "table" or type(entry.value) ~= "function" then return end
	groupName = groupName or entry.group or "Other"
	entry.group = groupName
	local isNew = not ENTRIES[key]
	ENTRIES[key] = entry
	if not isNew then return end
	for _, group in ipairs(GROUPS) do
		if group[1] == groupName then
			table.insert(group[2], key)
			return
		end
	end
	table.insert(GROUPS, { groupName, { key } })
end

local AGILE = { ROGUE = true, HUNTER = true, DRUID = true }

local ROLE_STATS = {
	HEALER = { "healing", "regen", "spellCrit", "intellect" },
	RANGED = { "spellPower", "spellCrit", "hit", "intellect" },
	TANK = { "armor", "defense", "dodge", "stamina" },
}

-- Situations: out in the world, in a dungeon, in a raid. Battlegrounds
-- and arenas count as dungeons.
local SITUATIONS = { "world", "dungeon", "raid" }
local SITUATION_WORDS = { world = "Out in the world", dungeon = "In a dungeon", raid = "In a raid" }
local AFTER_STATS = {
	dungeon = { "durability", "bags", "gold", "prof1" },
	raid = { "durability", "latency", "framerate", "gold" },
}
local WORLD = { "gold", "goldHour", "lootValue", "prof1", "prof2", "reputation", "durability", "bags" }

function Tally:Situation()
	if not self.db.follow then return "world" end
	local inside, kind = call(IsInInstance)
	if inside and kind == "raid" then return "raid" end
	if inside and (kind == "party" or kind == "pvp" or kind == "arena" or kind == "scenario") then return "dungeon" end
	return "world"
end

function Tally:Defaults(situation)
	situation = situation or self:Situation()
	local out = {}
	if situation == "world" then
		for _, key in ipairs(WORLD) do
			if ENTRIES[key] then out[#out + 1] = key end
		end
		return out
	end
	local role = Stoa:GetRole()
	local list = ROLE_STATS[role or ""]
	if not list then
		local _, class = UnitClass("player")
		list = { "attackPower", "crit", "hit", AGILE[class or ""] and "agility" or "strength" }
		if class == "HUNTER" then list[1] = "rangedPower" end
	end
	for _, key in ipairs(list) do out[#out + 1] = key end
	for _, key in ipairs(AFTER_STATS[situation] or AFTER_STATS.dungeon) do out[#out + 1] = key end
	return out
end

-- What you've picked is kept per spec and per situation, so a healing spec
-- and a damage spec each keep their own lines. A list saved before sets
-- followed the situation stands in for any set you haven't changed since.
local function slot()
	return Stoa.ActiveSpecSlot and Stoa.ActiveSpecSlot() or 1
end

local function older()
	local char = Stoa.char
	local bySpec = char.tallyBySpec
	if type(bySpec) == "table" and bySpec[slot()] ~= nil then return bySpec[slot()] or nil end
	return char.tally
end

local function saved(situation)
	local char = Stoa.char
	if not char then return nil end
	local sets = type(char.glanceBySpec) == "table" and char.glanceBySpec[slot()]
	local list = type(sets) == "table" and sets[situation]
	if list == false then return nil end
	if type(list) == "table" then return list end
	return older()
end

local function save(situation, list)
	local char = Stoa.char
	char.glanceBySpec = char.glanceBySpec or {}
	char.glanceBySpec[slot()] = char.glanceBySpec[slot()] or {}
	-- false marks "back to the default set" for this spec and situation.
	char.glanceBySpec[slot()][situation] = list or false
end

-- Pinned lines show in every situation, before the situation's own.
function Tally:Pins()
	local char = Stoa.char
	local pins = char and type(char.glancePins) == "table" and char.glancePins[slot()]
	return type(pins) == "table" and pins or {}
end

function Tally:IsPinned(key)
	for _, pinned in ipairs(self:Pins()) do
		if pinned == key then return true end
	end
	return false
end

function Tally:Pin(key)
	local list = {}
	for _, pinned in ipairs(self:Pins()) do
		if pinned ~= key then list[#list + 1] = pinned end
	end
	local on = not self:IsPinned(key)
	if on then list[#list + 1] = key end
	Stoa.char.glancePins = Stoa.char.glancePins or {}
	Stoa.char.glancePins[slot()] = list
	self:Refresh()
	return on
end

-- The situation's own keys: yours if you've picked, otherwise the default.
function Tally:Own(situation)
	situation = situation or self:Situation()
	local list = saved(situation)
	if type(list) == "table" then return list end
	return self:Defaults(situation)
end

-- What shows: the pins, then the situation's keys, at most MAX_ROWS.
function Tally:Chosen()
	local out, seen = {}, {}
	local function put(key)
		if not seen[key] and #out < MAX_ROWS then
			seen[key] = true
			out[#out + 1] = key
		end
	end
	for _, key in ipairs(self:Pins()) do put(key) end
	for _, key in ipairs(self:Own()) do put(key) end
	return out
end

-- Feeds -------------------------------------------------------------------------
-- LibDataBroker data objects, by the name they're published under.

local function broker()
	local stub = _G.LibStub
	return stub and call(stub.GetLibrary, stub, "LibDataBroker-1.1", true)
end

local function feedKey(name) return "ldb:" .. name end

local function feed(key)
	local name = key:match("^ldb:(.+)$")
	local ldb = name and broker()
	return ldb and call(ldb.GetDataObjectByName, ldb, name), name
end

function Tally:Feeds()
	local ldb, list = broker(), {}
	if not (ldb and ldb.DataObjectIterator) then return list end
	for name, object in ldb:DataObjectIterator() do
		if type(object) == "table" and (object.type == "data source" or object.text) then list[#list + 1] = name end
	end
	table.sort(list)
	return list
end

-- Reading -----------------------------------------------------------------------

function Tally:Read(key)
	local object, name = feed(key)
	if name then
		if not object then return nil end
		return object.label or name, object.text and tostring(object.text) or object.value and tostring(object.value)
	end
	local entry = ENTRIES[key]
	if not entry then return nil end
	local label = type(entry.label) == "function" and entry.label() or entry.label
	local value, warn = entry.value()
	return label, value, warn
end

-- The tooltip for one of Stoa's own lines: the number, where it comes
-- from, and what a click opens.
function Tally:ShowDetail(row, key)
	key = key or row.key
	local entry = ENTRIES[key]
	local label, value = self:Read(key)
	GameTooltip:SetOwner(row, "ANCHOR_TOP")
	local tr, tg, tb = Stoa:Color("text")
	local mr, mg, mb = Stoa:Color("muted")
	local ar, ag, ab = Stoa:Color("accent")
	GameTooltip:AddDoubleLine(label or "At a glance", value or "", tr, tg, tb, tr, tg, tb)
	if entry and type(entry.detail) == "function" then
		pcall(entry.detail, function(left, right)
			GameTooltip:AddDoubleLine(tostring(left), tostring(right or ""), mr, mg, mb, tr, tg, tb)
		end)
	end
	local open = entry and OPEN[entry.open or ""]
	local action = open and open[1] or entry and entry.action
	if action then GameTooltip:AddDoubleLine("Click", action, mr, mg, mb, ar, ag, ab) end
	GameTooltip:AddDoubleLine("Right-click", "Choose lines", mr, mg, mb, mr, mg, mb)
	GameTooltip:Show()
end

function Tally:Open(key)
	local entry = ENTRIES[key]
	if not entry then return end
	local open = OPEN[entry.open or ""]
	if open then return open[2]() end
	if type(entry.open) == "function" then pcall(entry.open) end
end

-- Building ----------------------------------------------------------------------

function Tally:BuildRow(page, index)
	local column = math.floor((index - 1) / ROWS_PER_COLUMN)
	local slot = (index - 1) % ROWS_PER_COLUMN
	local row = CreateFrame("Button", nil, page)
	row:SetSize(COLUMN_WIDTH, 18)
	row:SetPoint("TOPLEFT", self.rule, "BOTTOMLEFT", column * (COLUMN_WIDTH + COLUMN_GAP), -6 - slot * ROW_GAP)
	row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	local label = UI.text(row, "sans", Stoa.typeSize.caption + 1, "muted")
	label:SetPoint("LEFT")
	label:SetWidth(COLUMN_WIDTH - 70)
	label:SetWordWrap(false)
	local value = UI.text(row, "sans", Stoa.typeSize.label, "text", "RIGHT")
	value:SetPoint("RIGHT")
	value:SetWidth(COLUMN_WIDTH - 40)
	value:SetWordWrap(false)
	local pin = row:CreateTexture(nil, "OVERLAY")
	pin:SetSize(4, 4)
	pin:SetPoint("RIGHT", row, "LEFT", -5, 0)
	pin:SetTexture("Interface\\Buttons\\WHITE8x8")
	UI.tint(pin, "accent")
	if pin.SetMask then pcall(pin.SetMask, pin, "Interface\\CharacterFrame\\TempPortraitAlphaMask") end
	pin:Hide()
	local glow = row:CreateTexture(nil, "BACKGROUND")
	glow:SetPoint("TOPLEFT", -4, 1)
	glow:SetPoint("BOTTOMRIGHT", 4, -1)
	glow:SetTexture("Interface\\Buttons\\WHITE8x8")
	UI.tint(glow, "text", 0.08)
	glow:Hide()
	row.label, row.value, row.pin, row.glow = label, value, pin, glow
	row.figures = {}
	row:SetScript("OnClick", function(button, mouse)
		if mouse == "RightButton" then return self:OpenPicker(button) end
		local object = button.key and feed(button.key)
		if object then
			if object.OnClick then call(object.OnClick, button, mouse) end
		elseif button.key and not InCombatLockdown() then
			self:Open(button.key)
		end
	end)
	row:SetScript("OnEnter", function(button)
		button.glow:Show()
		local object = button.key and feed(button.key)
		if button.key and not object and ENTRIES[button.key] then
			self:ShowDetail(button)
		elseif object and object.OnTooltipShow then
			GameTooltip:SetOwner(button, "ANCHOR_TOP")
			call(object.OnTooltipShow, GameTooltip)
			GameTooltip:Show()
		elseif object and object.OnEnter then
			call(object.OnEnter, button)
		else
			GameTooltip:SetOwner(button, "ANCHOR_TOP")
			GameTooltip:AddLine("At a glance")
			GameTooltip:AddLine("Right-click to choose what shows here.", 1, 1, 1)
			GameTooltip:Show()
		end
	end)
	row:SetScript("OnLeave", function(button)
		button.glow:Hide()
		local object = button.key and feed(button.key)
		if object and object.OnLeave then call(object.OnLeave, button) end
		GameTooltip:Hide()
	end)
	row:Hide()
	return row
end

function Tally:Build(console)
	local inset, top = console:PageInset()
	local page = CreateFrame("Button", nil, console.frame)
	page:SetPoint("TOPLEFT", console.frame, "TOPLEFT", inset + CHAT_RIGHT, top)
	page:SetSize(COLUMN_WIDTH * 2 + COLUMN_GAP, 110)
	page:RegisterForClicks("RightButtonUp")
	page:SetScript("OnClick", function(button) self:OpenPicker(button) end)
	self.page = page

	local heading = UI.caption(page, "At a glance")
	heading:SetPoint("TOPLEFT")
	local rule = UI.line(page)
	rule:SetPoint("TOPLEFT", heading, "BOTTOMLEFT", 0, -6)
	rule:SetPoint("RIGHT", page, "RIGHT")
	-- Where you are, in the accent, at the right end of the heading.
	local where = UI.text(page, "sans", Stoa.typeSize.caption, "accent", "RIGHT")
	where:SetPoint("BOTTOMRIGHT", rule, "TOPRIGHT", 0, 6)
	self.heading, self.rule, self.where = heading, rule, where

	self.rows = {}
	for i = 1, MAX_ROWS do self.rows[i] = self:BuildRow(page, i) end
	UI.applyTheme()

	if console.AddPage then console:AddPage(page) end
	console.frame:HookScript("OnSizeChanged", function() self:Fit() end)
	self:Fit()
end

-- One column or two, or none, by the room between the chat and the centre.
function Tally:Fit()
	local console = Stoa.modules.Grimoire
	if not (self.page and console and console.frame) then return end
	local width = plain(console.frame:GetWidth())
	if not width then return end
	local inset = console:PageInset()
	local room = width / 2 - CENTRE_CLEAR - inset - CHAT_RIGHT
	self.columns = room >= COLUMN_WIDTH * 2 + COLUMN_GAP and 2 or room >= COLUMN_WIDTH and 1 or 0
	self.page:SetShown(self.columns > 0)
	self.page:SetWidth(self.columns == 2 and COLUMN_WIDTH * 2 + COLUMN_GAP or COLUMN_WIDTH)
	self:Refresh()
end

function Tally:Refresh()
	if not self.rows or InCombatLockdown() then return end
	professions = readProfessions()
	local shown = (self.columns or 2) * ROWS_PER_COLUMN
	local keys = self:Chosen()
	if self.where then
		self.where:SetText(self.db.follow and (SITUATION_WORDS[self:Situation()] or ""):upper() or "")
	end
	for i, row in ipairs(self.rows) do
		local key = i <= shown and keys[i]
		local label, value, warn
		if key then label, value, warn = self:Read(key) end
		row.key = key or nil
		if key and label then
			row.label:SetText(label)
			row.value:SetText(value or "–")
			row.value:SetTextColor(Stoa:Color(warn and "danger" or "text"))
			row.pin:SetShown(self:IsPinned(key))
			self:DrawFigure(row, key)
			row:Show()
		else
			row:Hide()
		end
	end
end

-- The small figure between a line's label and its value, made on first use.
local FIGURE_WIDTH = 34
local FIGURES = {
	bar = function(row) return Stoa.Figures.bar(row, FIGURE_WIDTH, 3) end,
	columns = function(row) return Stoa.Figures.columns(row, 5, 3, 12, 2) end,
	spark = function(row) return Stoa.Figures.spark(row, FIGURE_WIDTH, 12) end,
}

function Tally:DrawFigure(row, key)
	local entry = ENTRIES[key]
	local kind, a, b
	if entry and type(entry.figure) == "function" then
		local ok, k, x, y = pcall(entry.figure)
		if ok then kind, a, b = k, x, y end
	end
	if kind == "spark" and (type(a) ~= "table" or #a < 2) then kind = nil end
	for name, figure in pairs(row.figures) do
		if name ~= kind then figure:Hide() end
	end
	local valueWidth = plain(row.value:GetStringWidth()) or 30
	if not FIGURES[kind] then
		row.label:SetWidth(COLUMN_WIDTH - valueWidth - 8)
		return
	end
	local figure = row.figures[kind]
	if not figure then
		figure = FIGURES[kind](row)
		row.figures[kind] = figure
	end
	figure:ClearAllPoints()
	figure:SetPoint("RIGHT", row, "RIGHT", -(valueWidth + 8), 0)
	figure:Set(a, b)
	figure:Show()
	row.label:SetWidth(math.max(40, COLUMN_WIDTH - valueWidth - 8 - FIGURE_WIDTH - 6))
end

-- Choosing ----------------------------------------------------------------------

function Tally:Has(key, situation)
	for _, chosen in ipairs(self:Own(situation)) do
		if chosen == key then return true end
	end
	return false
end

-- Adds or removes a key in the current situation's set, keeping the rest
-- in order. Picking starts from the default set, so the first change
-- keeps what was showing. `situation` defaults to where you are.
function Tally:Toggle(key, situation)
	situation = situation or self:Situation()
	local list = {}
	for _, chosen in ipairs(self:Own(situation)) do list[#list + 1] = chosen end
	for i, chosen in ipairs(list) do
		if chosen == key then
			table.remove(list, i)
			save(situation, list)
			self:Refresh()
			return false
		end
	end
	if #list + #self:Pins() >= MAX_ROWS then
		Stoa:Print(("At a glance holds %d. Take one off first."):format(MAX_ROWS))
		return false
	end
	list[#list + 1] = key
	save(situation, list)
	self:Refresh()
	return true
end

function Tally:Reset(situation)
	save(situation or self:Situation(), nil)
	self:Refresh()
end

local function labelOf(key)
	local entry = ENTRIES[key]
	if not entry then return key end
	local label = entry.label
	if type(label) == "function" then label = call(label) end
	return label or key
end

-- Everything At a glance can show, for the settings window:
-- { key, label, group } in menu order, other addons' feeds last.
function Tally:Choices()
	local list = {}
	for _, group in ipairs(GROUPS) do
		for _, key in ipairs(group[2]) do
			if ENTRIES[key] then list[#list + 1] = { key, labelOf(key), group[1] } end
		end
	end
	for _, name in ipairs(self:Feeds()) do list[#list + 1] = { feedKey(name), name, "Other addons" } end
	return list
end
Tally.SITUATION_WORDS = SITUATION_WORDS
Tally.MAX_ROWS = MAX_ROWS

function Tally:OpenPicker(owner)
	if not (MenuUtil and MenuUtil.CreateContextMenu) then
		Stoa:Print("Choose with /stoa glance add <name> or /stoa glance remove <name>; /stoa glance lists the names.")
		return
	end
	MenuUtil.CreateContextMenu(owner, function(_, root)
		local word = self.db.follow and SITUATION_WORDS[self:Situation()]
		root:CreateTitle(word and ("At a glance: " .. word:lower()) or "At a glance")
		for _, group in ipairs(GROUPS) do
			local sub = root:CreateButton(group[1])
			for _, key in ipairs(group[2]) do
				sub:CreateCheckbox(labelOf(key), function() return self:Has(key) end, function() self:Toggle(key) end)
			end
		end
		local feeds = self:Feeds()
		if #feeds > 0 then
			local sub = root:CreateButton("Other addons")
			for _, name in ipairs(feeds) do
				local key = feedKey(name)
				sub:CreateCheckbox(name, function() return self:Has(key) end, function() self:Toggle(key) end)
			end
		end
		local shown = self:Chosen()
		if #shown > 0 then
			local sub = root:CreateButton("Pin to every situation")
			for _, key in ipairs(shown) do
				sub:CreateCheckbox(key:match("^ldb:(.+)$") or labelOf(key), function() return self:IsPinned(key) end, function() self:Pin(key) end)
			end
		end
		root:CreateDivider()
		root:CreateButton("Back to the default set", function() self:Reset() end)
	end)
end

-- Lifecycle ---------------------------------------------------------------------

function Tally:OnEnable()
	local console = Stoa.modules.Grimoire
	if not (console and console.frame and Stoa:IsModuleEnabled("Grimoire")) then return end
	session.money = plain(call(GetMoney))
	local data = C_Reputation and call(C_Reputation.GetWatchedFactionData)
	if type(data) == "table" and data.name and plain(data.currentStanding) then
		session.rep = { data.name, plain(data.currentStanding) }
	else
		local name, _, _, _, current = call(GetWatchedFactionInfo)
		if name and plain(current) then session.rep = { name, plain(current) } end
	end
	self:Build(console)
	Stoa:NewTicker(REFRESH_SECONDS, function() self:Refresh() end)
	Stoa:On("PLAYER_ENTERING_WORLD", function() self:Refresh() end)
	Stoa:On("ZONE_CHANGED_NEW_AREA", function() self:Refresh() end)
	Stoa:On("STOA_ROLE_CHANGED", function() self:Refresh() end)
	Stoa:On("ACTIVE_TALENT_GROUP_CHANGED", function() self:Refresh() end)
	Stoa:On("PLAYER_REGEN_ENABLED", function() self:Refresh() end)
	Stoa:On("STOA_THEME_CHANGED", function() self:Refresh() end)
end

-- /stoa glance (or /stoa tally): list the names; add or remove one; reset to the role's set.
Stoa.commands.glance = function(rest)
	local verb, key = (rest or ""):match("^(%a*)%s*(%S*)")
	verb = verb and verb:lower()
	if verb == "reset" then
		Tally:Reset()
		Stoa:Print("At a glance is back to the default set here.")
	elseif verb == "pin" and key ~= "" then
		if not (ENTRIES[key] or key:match("^ldb:")) then return Stoa:Print("No such entry: " .. key .. ". /stoa glance lists them.") end
		Stoa:Print((Tally:Pin(key) and "Pinned " or "Unpinned ") .. labelOf(key) .. ".")
	elseif (verb == "add" or verb == "remove") and key ~= "" then
		local known = ENTRIES[key] or key:match("^ldb:")
		if not known then return Stoa:Print("No such entry: " .. key .. ". /stoa glance lists them.") end
		if Tally:Has(key) == (verb == "add") then return end
		Tally:Toggle(key)
	else
		local names = {}
		for _, group in ipairs(GROUPS) do
			for _, name in ipairs(group[2]) do names[#names + 1] = name end
		end
		for _, name in ipairs(Tally:Feeds()) do names[#names + 1] = feedKey(name) end
		Stoa:Print(("Showing (%s): %s"):format((SITUATION_WORDS[Tally:Situation()] or ""):lower(), table.concat(Tally:Chosen(), ", ")))
		Stoa:Print("Names: " .. table.concat(names, ", "))
		Stoa:Print("/stoa glance add <name>, remove <name>, pin <name>, reset. Changes apply where you are now. Or right-click At a glance.")
	end
end
Stoa.commands.tally = Stoa.commands.glance
