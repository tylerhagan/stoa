-- Stoa: group buff reminders.
-- For the group buffs you can cast (Fortitude, Mark of the Wild, Arcane
-- Intellect, a paladin's blessings, Divine Spirit, Shadow Protection), this
-- counts the people near you who are missing it and says so as a short line
-- on the console's Ready page, and again on screen when a ready check
-- starts. Nothing is said in combat, and nobody is counted whose buffs the
-- game won't let us read.
local _, ns = ...
local Stoa = ns.Stoa
local UI = Stoa.UI

local Buffs = Stoa:NewModule("Buffs", {
	readyCheck = true,
})

-- cast: your spells (the single-target and the group version); any one you
-- know makes the reminder apply. auras: any of these on a unit counts.
-- Spells are given by ID with their English name; they're matched by the
-- name in the game's language (see Spells.localName).
local FORT = { { 1243, "Power Word: Fortitude" }, { 21562, "Prayer of Fortitude" } }
local MARK = { { 1126, "Mark of the Wild" }, { 21849, "Gift of the Wild" } }
local INTELLECT = { { 1459, "Arcane Intellect" }, { 23028, "Arcane Brilliance" } }
local SPIRIT = { { 14752, "Divine Spirit" }, { 27681, "Prayer of Spirit" } }
local SHADOW = { { 976, "Shadow Protection" }, { 27683, "Prayer of Shadow Protection" } }
local BLESSINGS_CAST = {
	{ 20217, "Blessing of Kings" }, { 19740, "Blessing of Might" }, { 19742, "Blessing of Wisdom" },
	{ 25898, "Greater Blessing of Kings" }, { 25782, "Greater Blessing of Might" }, { 25894, "Greater Blessing of Wisdom" },
}
local BLESSINGS_ANY = {
	{ 20217, "Blessing of Kings" }, { 19740, "Blessing of Might" }, { 19742, "Blessing of Wisdom" },
	{ 19977, "Blessing of Light" }, { 1038, "Blessing of Salvation" }, { 20911, "Blessing of Sanctuary" },
	{ 25898, "Greater Blessing of Kings" }, { 25782, "Greater Blessing of Might" }, { 25894, "Greater Blessing of Wisdom" },
	{ 25890, "Greater Blessing of Light" }, { 25895, "Greater Blessing of Salvation" }, { 25899, "Greater Blessing of Sanctuary" },
}
local SOURCE = {
	{ word = "FORTITUDE", cast = FORT, auras = FORT },
	{ word = "MARK OF THE WILD", cast = MARK, auras = MARK },
	{ word = "ARCANE INTELLECT", cast = INTELLECT, auras = INTELLECT },
	{ word = "DIVINE SPIRIT", cast = SPIRIT, auras = SPIRIT },
	{ word = "SHADOW PROTECTION", cast = SHADOW, auras = SHADOW },
	-- Any one blessing counts, whoever cast it.
	{ word = "BLESSING", cast = BLESSINGS_CAST, auras = BLESSINGS_ANY },
}

local function names(spells)
	local list = {}
	for _, spell in ipairs(spells) do list[#list + 1] = Stoa.Spells.localName(spell[1], spell[2]) end
	return list
end

-- The list with names in the game's language, made on first use.
local LIST
local function buffList()
	if not LIST then
		LIST = {}
		for _, buff in ipairs(SOURCE) do
			LIST[#LIST + 1] = { word = buff.word, cast = names(buff.cast), auras = names(buff.auras) }
		end
	end
	return LIST
end

local call = Stoa.safe.call

local plain = Stoa.safe.plain

local function knowsAny(names)
	for _, name in ipairs(names) do
		if Stoa.Spells.best(name) then return true end
	end
	return false
end

-- true if the unit has one of the buffs, false if it has none, nil when
-- that can't be read.
local function hasAny(unit, names)
	if Stoa:AurasHidden() then return nil end
	local lookup = C_UnitAuras and C_UnitAuras.GetAuraDataBySpellName
	if lookup then
		for _, name in ipairs(names) do
			local ok, aura = pcall(lookup, unit, name, "HELPFUL")
			if not ok or Stoa:IsSecret(aura) then return nil end
			if aura then return true end
		end
		return false
	end
	local byIndex = C_UnitAuras and C_UnitAuras.GetAuraDataByIndex
	if not byIndex then return nil end
	local wanted = {}
	for _, name in ipairs(names) do wanted[name] = true end
	for i = 1, 40 do
		local ok, aura = pcall(byIndex, unit, i, "HELPFUL")
		if not ok then return nil end
		if not aura then return false end
		local name = aura.name
		if Stoa:IsSecret(name) then return nil end
		if wanted[name] then return true end
	end
	return false
end

-- Near enough to buff, awake and online. A unit whose range can't be
-- checked is left out rather than counted.
local function reachable(unit)
	if not UnitExists(unit) then return false end
	if plain(call(UnitIsConnected, unit)) == false then return false end
	if plain(call(UnitIsDeadOrGhost, unit)) ~= false then return false end
	if unit == "player" then return true end
	local inRange, checked = call(UnitInRange, unit)
	inRange, checked = plain(inRange), plain(checked)
	if checked == false then return false end
	return inRange == true
end

-- The buffs you could cast that someone near you lacks:
-- { { word, count, units } }. Empty in combat or on your own.
function Buffs:Missing()
	local list = {}
	if InCombatLockdown() or not IsInGroup() then return list end
	local units = {}
	for _, unit in ipairs(Stoa:GroupUnits()) do
		if reachable(unit) then units[#units + 1] = unit end
	end
	for _, buff in ipairs(buffList()) do
		if knowsAny(buff.cast) then
			local lacking = {}
			for _, unit in ipairs(units) do
				if hasAny(unit, buff.auras) == false then lacking[#lacking + 1] = unit end
			end
			if #lacking > 0 then list[#list + 1] = { word = buff.word, count = #lacking, units = lacking } end
		end
	end
	return list
end

-- "FORTITUDE · 3 missing", one buff to a line.
function Buffs.Line(list)
	local parts = {}
	for _, entry in ipairs(list) do
		parts[#parts + 1] = entry.word .. " · " .. entry.count .. " missing"
	end
	return table.concat(parts, "\n")
end

function Buffs:Update()
	self.list = self:Missing()
	local line = Buffs.Line(self.list)
	if line ~= (Stoa.groupBuffLine or "") then
		Stoa.groupBuffLine = line
		Stoa:Fire("STOA_REMINDERS_CHANGED")
	end
	if self.screen and self.screen:IsShown() then self:ShowReady() end
end

-- Folds bursts of aura and roster events into one look.
function Buffs:Soon()
	if self.pending then return end
	self.pending = true
	C_Timer.After(1, function()
		self.pending = false
		xpcall(self.Update, Stoa.catch, self)
	end)
end

-- On screen near the ready check --------------------------------------------

function Buffs:BuildScreen()
	if self.screen then return self.screen end
	local frame = CreateFrame("Frame", "StoaBuffsReady", UIParent)
	frame:SetSize(360, 20)
	frame:SetFrameStrata("DIALOG")
	frame:EnableMouse(false)
	local word = UI.text(frame, "sans", Stoa.typeSize.label, "accent", "CENTER")
	UI.legible(word)
	word:SetAllPoints()
	frame.word = word
	frame:Hide()
	self.screen = frame
	return frame
end

function Buffs:ShowReady()
	local frame = self:BuildScreen()
	local line = Buffs.Line(self.list or {})
	if line == "" or not self.db.readyCheck then frame:Hide() return end
	frame:ClearAllPoints()
	local check = _G.ReadyCheckFrame
	if check and check.IsShown and check:IsShown() then
		frame:SetPoint("TOP", check, "BOTTOM", 0, -10)
	else
		frame:SetPoint("TOP", UIParent, "TOP", 0, -160)
	end
	frame.word:SetText((line:gsub("\n", "   ")))
	frame:Show()
end

function Buffs:OnReadyCheck()
	self:Update()
	self:ShowReady()
end

function Buffs:OnReadyDone()
	if not self.screen then return end
	C_Timer.After(4, function() self.screen:Hide() end)
end

function Buffs:OnEnable()
	for _, event in ipairs({ "STOA_GROUP_CHANGED", "STOA_STATE_CHANGED", "STOA_SPELLS_CHANGED", "PLAYER_ENTERING_WORLD" }) do
		Stoa:On(event, function() self:Soon() end)
	end
	Stoa:On("UNIT_AURA", function(unit)
		if type(unit) == "string" and (unit == "player" or unit:find("^party%d") or unit:find("^raid%d")) then
			self:Soon()
		end
	end)
	Stoa:On("READY_CHECK", function() self:OnReadyCheck() end)
	Stoa:On("READY_CHECK_FINISHED", function() self:OnReadyDone() end)
	-- People walk in and out of range between events.
	Stoa:NewTicker(6, function() self:Update() end)
end
