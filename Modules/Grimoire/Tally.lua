-- Stoa: At a glance (the module is still called Tally), a few numbers you
-- choose beside the chat.
-- Out of combat the console carries a small block to the right of chat:
-- up to eight label and value rows in two columns, like the right page's
-- columns. What it shows is yours to pick (right-click it, or /stoa
-- tally), saved per character, and until you pick it follows your role:
--   Healer: healing, mana regen, spell crit, intellect;
--   Ranged: spell power, spell crit, hit, intellect;
--   Melee: attack power, crit, hit, agility or strength;
--   Tank: armor, defense, dodge, stamina;
-- then gear wear, bag room, gold and your first profession for everyone.
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

local Tally = Stoa:NewModule("Tally", {})

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

local function call(fn, ...)
	if type(fn) ~= "function" then return nil end
	local ok, a, b, c, d, e = pcall(fn, ...)
	if ok then return a, b, c, d, e end
end

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
	}
end

-- Entries -----------------------------------------------------------------------
-- Each: a label (or a function giving one), a value function returning the
-- words to show and whether they warn, and the group the picker lists it in.

local ENTRIES = {
	strength = { label = "Strength", group = "Stats", value = stat(1) },
	agility = { label = "Agility", group = "Stats", value = stat(2) },
	stamina = { label = "Stamina", group = "Stats", value = stat(3) },
	intellect = { label = "Intellect", group = "Stats", value = stat(4) },
	spirit = { label = "Spirit", group = "Stats", value = stat(5) },
	attackPower = { label = "Attack power", group = "Stats", value = function()
		local base, plus, minus = call(UnitAttackPower, "player")
		base, plus, minus = plain(base), plain(plus) or 0, plain(minus) or 0
		return base and whole(base + plus + minus)
	end },
	rangedPower = { label = "Ranged power", group = "Stats", value = function()
		local base, plus, minus = call(UnitRangedAttackPower, "player")
		base, plus, minus = plain(base), plain(plus) or 0, plain(minus) or 0
		return base and whole(base + plus + minus)
	end },
	spellPower = { label = "Spell power", group = "Stats", value = function() return whole(bestSchool(GetSpellBonusDamage)) end },
	healing = { label = "Healing", group = "Stats", value = function() return whole(call(GetSpellBonusHealing)) end },
	crit = { label = "Crit", group = "Stats", value = function() return percent(call(GetCritChance)) end },
	spellCrit = { label = "Spell crit", group = "Stats", value = function() return percent(bestSchool(GetSpellCritChance)) end },
	hit = { label = "Hit", group = "Stats", value = function()
		local bonus = plain(call(GetHitModifier))
		return bonus and ("+%d%%"):format(bonus)
	end },
	regen = { label = "Mana / 5s", group = "Stats", value = function()
		local _, casting = call(GetManaRegen)
		casting = plain(casting)
		return casting and whole(casting * 5)
	end },
	armor = { label = "Armor", group = "Stats", value = function()
		local _, effective = call(UnitArmor, "player")
		return whole(effective)
	end },
	defense = { label = "Defense", group = "Stats", value = function()
		local base, bonus = call(UnitDefense, "player")
		base, bonus = plain(base), plain(bonus) or 0
		return base and whole(base + bonus)
	end },
	dodge = { label = "Dodge", group = "Stats", value = function() return percent(call(GetDodgeChance)) end },
	parry = { label = "Parry", group = "Stats", value = function() return percent(call(GetParryChance)) end },
	block = { label = "Block", group = "Stats", value = function() return percent(call(GetBlockChance)) end },

	durability = { label = "Gear", group = "Kit", value = function()
		local lowest
		for _, slot in ipairs(GEAR_SLOTS) do
			local current, max = call(GetInventoryItemDurability, slot)
			current, max = plain(current), plain(max)
			if current and max and max > 0 and (not lowest or current / max < lowest) then lowest = current / max end
		end
		if not lowest then return "Whole" end
		return math.floor(lowest * 100 + 0.5) .. "%", lowest < LOW_WEAR
	end },
	bags = { label = "Bags free", group = "Kit", value = function()
		local getFree = C_Container and C_Container.GetContainerNumFreeSlots or GetContainerNumFreeSlots
		if not getFree then return nil end
		local free = 0
		for bag = 0, 4 do free = free + (plain(call(getFree, bag)) or 0) end
		return tostring(free), free <= LOW_BAGS
	end },
	gold = { label = "Gold", group = "Kit", value = money },

	prof1 = profession("prof1", "Profession"),
	prof2 = profession("prof2", "Second profession"),
	cooking = profession("cooking", "Cooking"),
	fishing = profession("fishing", "Fishing"),
	firstAid = profession("firstAid", "First Aid"),

	zone = { label = "Zone", group = "World", value = function()
		local sub, zone = call(GetSubZoneText), call(GetZoneText)
		return (sub and sub ~= "" and sub) or zone
	end },
	reputation = { label = function()
		local data = C_Reputation and call(C_Reputation.GetWatchedFactionData)
		if type(data) == "table" and data.name then return data.name end
		local name = call(GetWatchedFactionInfo)
		return name or "Reputation"
	end, group = "World", value = function()
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
		return ("%d / %d"):format(value - low, high - low)
	end },
	clock = { label = "Time", group = "World", value = function() return date("%H:%M") end },
	latency = { label = "Latency", group = "World", value = function()
		local _, _, home, world = call(GetNetStats)
		local ms = plain(world) or plain(home)
		return ms and (ms .. " ms")
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
local SHARED = { "durability", "bags", "gold", "prof1" }

function Tally:Defaults()
	local role = Stoa:GetRole()
	local list = ROLE_STATS[role or ""]
	if not list then
		local _, class = UnitClass("player")
		list = { "attackPower", "crit", "hit", AGILE[class or ""] and "agility" or "strength" }
		if class == "HUNTER" then list[1] = "rangedPower" end
	end
	local out = {}
	for _, key in ipairs(list) do out[#out + 1] = key end
	for _, key in ipairs(SHARED) do out[#out + 1] = key end
	return out
end

-- What you've picked is kept per spec, so a healing spec and a damage
-- spec each keep their own lines. A character saved before that keeps its
-- one list for both until a spec picks its own.
local function saved()
	local char = Stoa.char
	if not char then return nil end
	local slot = Stoa.ActiveSpecSlot and Stoa.ActiveSpecSlot() or 1
	local bySpec = char.tallyBySpec
	if type(bySpec) == "table" and bySpec[slot] ~= nil then return bySpec[slot] or nil end
	return char.tally
end

local function save(list)
	local slot = Stoa.ActiveSpecSlot and Stoa.ActiveSpecSlot() or 1
	Stoa.char.tallyBySpec = Stoa.char.tallyBySpec or {}
	-- false marks "back to the role's set" for this spec.
	Stoa.char.tallyBySpec[slot] = list or false
end

-- The chosen keys: yours if you've picked, otherwise the role's.
function Tally:Chosen()
	local list = saved()
	if type(list) == "table" then return list end
	return self:Defaults()
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
	row.label, row.value = label, value
	row:SetScript("OnClick", function(button, mouse)
		if mouse == "RightButton" then return self:OpenPicker(button) end
		local object = button.key and feed(button.key)
		if object and object.OnClick then call(object.OnClick, button, mouse) end
	end)
	row:SetScript("OnEnter", function(button)
		local object = button.key and feed(button.key)
		if object and object.OnTooltipShow then
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
	self.heading, self.rule = heading, rule

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
	for i, row in ipairs(self.rows) do
		local key = i <= shown and keys[i]
		local label, value, warn
		if key then label, value, warn = self:Read(key) end
		row.key = key or nil
		if key and label then
			row.label:SetText(label)
			row.value:SetText(value or "–")
			row.value:SetTextColor(Stoa:Color(warn and "danger" or "text"))
			row:Show()
		else
			row:Hide()
		end
	end
end

-- Choosing ----------------------------------------------------------------------

function Tally:Has(key)
	for _, chosen in ipairs(self:Chosen()) do
		if chosen == key then return true end
	end
	return false
end

-- Adds or removes a key, keeping the rest in order. Picking starts from
-- the role's list, so the first change keeps what was showing.
function Tally:Toggle(key)
	local list = {}
	for _, chosen in ipairs(self:Chosen()) do list[#list + 1] = chosen end
	for i, chosen in ipairs(list) do
		if chosen == key then
			table.remove(list, i)
			save(list)
			self:Refresh()
			return false
		end
	end
	if #list >= MAX_ROWS then
		Stoa:Print(("At a glance holds %d. Take one off first."):format(MAX_ROWS))
		return false
	end
	list[#list + 1] = key
	save(list)
	self:Refresh()
	return true
end

function Tally:Reset()
	save(nil)
	self:Refresh()
end

local function labelOf(key)
	local entry = ENTRIES[key]
	if not entry then return key end
	local label = entry.label
	if type(label) == "function" then label = call(label) end
	return label or key
end

function Tally:OpenPicker(owner)
	if not (MenuUtil and MenuUtil.CreateContextMenu) then
		Stoa:Print("Choose with /stoa glance add <name> or /stoa glance remove <name>; /stoa glance lists the names.")
		return
	end
	MenuUtil.CreateContextMenu(owner, function(_, root)
		root:CreateTitle("At a glance")
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
		root:CreateDivider()
		root:CreateButton("Back to my role's set", function() self:Reset() end)
	end)
end

-- Lifecycle ---------------------------------------------------------------------

function Tally:OnEnable()
	local console = Stoa.modules.Grimoire
	if not (console and console.frame and Stoa:IsModuleEnabled("Grimoire")) then return end
	self:Build(console)
	Stoa:NewTicker(REFRESH_SECONDS, function() self:Refresh() end)
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
		Stoa:Print("At a glance follows your role again.")
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
		Stoa:Print("Showing: " .. table.concat(Tally:Chosen(), ", "))
		Stoa:Print("Names: " .. table.concat(names, ", "))
		Stoa:Print("/stoa glance add <name>, /stoa glance remove <name>, /stoa glance reset. Or right-click At a glance.")
	end
end
Stoa.commands.tally = Stoa.commands.glance
