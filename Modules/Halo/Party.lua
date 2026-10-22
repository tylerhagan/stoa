-- Stoa: party cards, after the Halo healer mockup.
-- One card per party member, with yourself first. Healers get large cards
-- beside the Halo; everyone else gets a compact column on the left.
-- Clicks follow the click-cast bindings (/stoa clicks); by default left
-- click targets and right click opens the unit menu.
--
-- Cards are secure buttons, so they are only built, moved and resized out
-- of combat. In combat Stoa only changes what they show and how bright they
-- are, which is always allowed.
local _, ns = ...
local Stoa = ns.Stoa
local UI = Stoa.UI

local Party = Stoa:NewModule("Party", {
	hideBlizzardParty = true,
})

local UNITS = { "player", "party1", "party2", "party3", "party4" }
local WORLD_ALPHA = 1
local OUT_OF_RANGE_ALPHA = 0.6
local GONE_ALPHA = 0.42

-- Card size and spot per role. Healers get a row of cards just under the
-- Halo, where their eyes already are, with the click bindings spelled out
-- beneath. Everyone else gets a column on the left. A position dragged with
-- /stoa unlock wins over these.
local LAYOUTS = {
	HEALER = { width = 176, height = 70, gap = 8, style = "party", row = true, grid = true },
	OTHER = { width = 184, height = 58, gap = 6, style = "compact", point = { "TOPLEFT", UIParent, "LEFT", 36, 180 } },
}

local function layoutFor(role)
	return LAYOUTS[role] or LAYOUTS.OTHER
end

-- Build ---------------------------------------------------------------------

function Party:BuildCard(index, unit)
	local card = CreateFrame("Button", "StoaPartyCard" .. index, self.frame, "SecureUnitButtonTemplate")
	card:SetAttribute("unit", unit)
	card:SetAttribute("type1", "target")
	card:SetAttribute("type2", "togglemenu")
	card:RegisterForClicks("AnyUp")
	card:SetSize(176, 70)
	card.unit = unit
	Stoa:RegisterClickFrame(card)
	UI.unitCard(card, "party")

	card:SetScript("OnEnter", function(button)
		GameTooltip_SetDefaultAnchor(GameTooltip, button)
		GameTooltip:SetUnit(button.unit)
	end)
	card:SetScript("OnLeave", GameTooltip_Hide)

	if unit == "player" then
		-- Your own card only shows in a group; alone the Halo covers you.
		RegisterStateDriver(card, "visibility", "[group] show; hide")
	else
		RegisterUnitWatch(card)
	end
	return card
end

function Party:Build()
	local frame = CreateFrame("Frame", "StoaParty", UIParent)
	frame:SetSize(176, 70)
	frame:SetFrameStrata("LOW")
	-- In a raid the raid grid takes over.
	RegisterStateDriver(frame, "visibility", "[group:raid] hide; show")
	self.frame = frame

	self.cards = {}
	for i, unit in ipairs(UNITS) do
		self.cards[i] = self:BuildCard(i, unit)
	end

	self:BuildGrid()

	UI.applyTheme()
	self:Layout()
	Stoa:RegisterMover("party", frame, "Party")
end

-- How many cards show: you plus your party, or all five in the preview.
function Party:VisibleCount()
	if self.cards and self.cards[1].preview then return #UNITS end
	return math.max(1, math.min(#UNITS, GetNumGroupMembers and GetNumGroupMembers() or 1))
end

-- Sizes and places the cards for the current role. Out of combat only.
function Party:Layout()
	local layout = layoutFor(Stoa:GetRole())
	local frame = self.frame
	local count = self:VisibleCount()
	local halo = _G.StoaHalo
	if not Stoa.char.positions.party then
		frame:ClearAllPoints()
		if layout.row and halo then
			frame:SetPoint("TOP", halo, "BOTTOM", 0, -52)
		elseif layout.row then
			frame:SetPoint("TOP", UIParent, "CENTER", 0, -260)
		else
			frame:SetPoint(unpack(layout.point))
		end
	end
	-- A row is as wide as the cards in it, so it stays centred.
	if layout.row then
		frame:SetSize(count * layout.width + (count - 1) * layout.gap, layout.height)
	else
		frame:SetSize(layout.width, layout.height)
	end
	for i, card in ipairs(self.cards) do
		card:SetSize(layout.width, layout.height)
		card:ClearAllPoints()
		if layout.row then
			card:SetPoint("TOPLEFT", frame, "TOPLEFT", (i - 1) * (layout.width + layout.gap), 0)
		else
			card:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, -(i - 1) * (layout.height + layout.gap))
		end
		UI.styleCard(card, layout.style)
	end
	self:UpdateAll()
	self:UpdateGrid()
end

-- The click grid: what every click does, laid out like the mockup's left
-- wing. Healers only, and only while there are cards to click.

local GRID_COLUMNS = {
	{ id = "1", label = "Left" }, { id = "2", label = "Right" }, { id = "3", label = "Wheel" },
	{ id = "4", label = "Thumb 1" }, { id = "5", label = "Thumb 2" },
}
local GRID_ROWS = { { prefix = "", label = "None" }, { prefix = "shift-", label = "Shift" }, { prefix = "ctrl-", label = "Ctrl" } }
local GRID_LABEL_WIDTH, GRID_CELL_WIDTH, GRID_ROW_HEIGHT = 60, 132, 32

-- Long spell names cut down to fit a cell.
local SHORT_NAMES = {
	["^Power Word: "] = "PW: ",
	["^Blessing of "] = "B. of ",
	["^Prayer of Mending$"] = "Mending",
	["^target$"] = "Target",
	["^menu$"] = "Menu",
}
local function shortName(action)
	if not action then return "·" end
	for pattern, short in pairs(SHORT_NAMES) do
		action = action:gsub(pattern, short)
	end
	return action
end

function Party:BuildGrid()
	local grid = CreateFrame("Frame", "StoaClickGrid", UIParent)
	local width = GRID_LABEL_WIDTH + #GRID_COLUMNS * GRID_CELL_WIDTH
	grid:SetSize(width, 20 + GRID_ROW_HEIGHT * (#GRID_ROWS + 1))
	grid:SetFrameStrata("LOW")
	grid:SetPoint("TOPLEFT", UIParent, "LEFT", 60, -40)
	grid:Hide()
	self.grid = grid

	local title = UI.caption(grid, "Your hands · click-cast on any card")
	title:SetPoint("TOPLEFT")

	local function cell(row, col, kind)
		local x = col == 0 and 0 or GRID_LABEL_WIDTH + (col - 1) * GRID_CELL_WIDTH
		local y = -20 - row * GRID_ROW_HEIGHT
		local fs = kind == "caption" and UI.caption(grid, "") or UI.text(grid, "serif", Stoa.typeSize.label, "text")
		fs:SetPoint("LEFT", grid, "TOPLEFT", x + 6, y - GRID_ROW_HEIGHT / 2)
		fs:SetWidth((col == 0 and GRID_LABEL_WIDTH or GRID_CELL_WIDTH) - 10)
		fs:SetWordWrap(false)
		return fs
	end

	for col, column in ipairs(GRID_COLUMNS) do
		cell(0, col, "caption"):SetText(column.label:upper())
	end
	grid.cells = {}
	for row, mod in ipairs(GRID_ROWS) do
		local line = UI.line(grid)
		line:SetPoint("TOPLEFT", 0, -20 - row * GRID_ROW_HEIGHT)
		line:SetPoint("TOPRIGHT", 0, -20 - row * GRID_ROW_HEIGHT)
		cell(row, 0, "caption"):SetText(mod.label:upper())
		for col, column in ipairs(GRID_COLUMNS) do
			grid.cells[mod.prefix .. column.id] = cell(row, col)
		end
	end
	Stoa:RegisterMover("clickgrid", grid, "Click grid")
end

function Party:UpdateGrid()
	local grid = self.grid
	local clickCast = Stoa.modules.ClickCast
	local bindings = clickCast and clickCast.Bindings and clickCast:Bindings() or {}
	for key, fs in pairs(grid.cells) do
		fs:SetText(shortName(bindings[key]))
	end
	local cards = Stoa.previewing or IsInGroup()
	grid:SetShown(layoutFor(Stoa:GetRole()).grid and cards and true or false)
	grid:SetAlpha(Stoa:GetState() == Stoa.STATE_COMBAT and 1 or 0.8)
end

-- Updates -------------------------------------------------------------------

local LOW_HEALTH = 0.35

local function flag(value)
	if Stoa:IsSecret(value) then return false end
	return value and true or false
end

-- Health as a 0 to 1 fraction when it can be worked out, else nil. In
-- combat health can be secret, and then low health isn't flagged.
local function healthFraction(unit)
	local health, max = UnitHealth(unit), UnitHealthMax(unit)
	if Stoa:IsSecret(health) or Stoa:IsSecret(max) or not max or max <= 0 then return nil end
	return health / max
end

-- The percent in the card's corner. Newer clients hand out a percent that
-- is safe to show even when it's secret; otherwise it's worked out, and
-- failing both the plain health is shown.
local function setPercent(fs, unit, fraction)
	if fraction then
		fs:SetText(math.floor(fraction * 100 + 0.5))
		return
	end
	if UnitHealthPercent and CurveConstants and CurveConstants.ScaleTo100 then
		local ok = pcall(function()
			fs:SetFormattedText("%d", UnitHealthPercent(unit, true, CurveConstants.ScaleTo100))
		end)
		if ok then return end
	end
	fs:SetText(UnitHealth(unit))
end

function Party:UpdateCard(card)
	local unit = card.unit
	-- Cards showing the /stoa test preview keep their sample data.
	if card.preview or not unit or not UnitExists(unit) then return end

	card.name:SetText(UnitName(unit))
	card.name:SetTextColor(UI.classColor(unit))
	UI.setUnitBar(card.hp, unit, "health")

	local gone
	if not flag(UnitIsConnected(unit)) then
		gone = "OFFLINE"
	elseif flag(UnitIsDeadOrGhost(unit)) then
		gone = "DEAD"
	end

	local pips = {}
	local fraction = healthFraction(unit)
	local low = not gone and fraction and fraction < LOW_HEALTH
	local dispel = not gone and self:DispelFor(unit)

	if gone then
		card.percent:SetText("·")
		card.hp:SetValue(0)
		pips[1] = { gone }
	else
		setPercent(card.percent, unit, fraction)
		if dispel then pips[#pips + 1] = { dispel.word, dispel.token } end
		if low then pips[#pips + 1] = { "LOW", "danger" } end
		self:AuraPips(unit, pips)
	end
	UI.setPips(card, pips)

	-- Bar and percent turn amber when low, and the border says why.
	local r, g, b = Stoa:Color(low and "danger" or "health")
	card.hp:SetStatusBarColor(r, g, b)
	card.percent:SetTextColor(Stoa:Color(low and "danger" or "text"))

	card.glow:Clear()
	if dispel then
		local dr, dg, db = Stoa:Color(dispel.token)
		card.state:Set(dr, dg, db)
		card.glow:Set(dr, dg, db, 0.22)
	elseif low then
		card.state:Set(Stoa:Color("danger"))
	elseif flag(UnitIsUnit(unit, "target")) then
		card.state:Set(Stoa:Color("text"))
	else
		card.state:Clear()
	end
	card.gone = gone

	self:UpdateAbsorb(card)
	self:UpdateRange(card)
end

-- Your own buffs worth tracking on a card, as short words. Timers show
-- once there's under half a minute left.
local OWN_BUFFS = {
	["Power Word: Shield"] = { "SHIELD", "shield" },
	["Renew"] = { "RENEW" },
	["Prayer of Mending"] = { "MENDING" },
	["Fear Ward"] = { "WARD" },
	["Power Infusion"] = { "INFUSION" },
	["Inner Fire"] = { "INNER FIRE" },
	["Blessing of Protection"] = { "PROTECTION" },
	["Blessing of Freedom"] = { "FREEDOM" },
	["Blessing of Sacrifice"] = { "SACRIFICE" },
}
-- Debuffs from anyone that change what you can cast on them.
local LOCKOUTS = {
	["Weakened Soul"] = "WS",
	["Forbearance"] = "FORB",
}
local MAX_PIPS = 3

local function timeLeft(aura)
	local expires = aura.expirationTime
	if Stoa:IsSecret(expires) or not expires or expires == 0 then return nil end
	local left = expires - GetTime()
	if left > 0 and left < 30 then return math.floor(left + 0.5) end
end

local function scan(unit, filter, fn)
	if not (C_UnitAuras and C_UnitAuras.GetAuraDataByIndex) then return end
	for i = 1, 40 do
		local ok, aura = pcall(C_UnitAuras.GetAuraDataByIndex, unit, i, filter)
		if not ok or not aura then return end
		local name = aura.name
		if not Stoa:IsSecret(name) and fn(name, aura) then return end
	end
end

function Party:AuraPips(unit, pips)
	scan(unit, "HELPFUL|PLAYER", function(name, aura)
		local cue = OWN_BUFFS[name]
		if cue then
			local left = timeLeft(aura)
			pips[#pips + 1] = { left and (cue[1] .. " " .. left) or cue[1], cue[2] }
		end
		return #pips >= MAX_PIPS
	end)
	if #pips >= MAX_PIPS then return end
	scan(unit, "HARMFUL", function(name, aura)
		local word = LOCKOUTS[name]
		if word then
			local left = timeLeft(aura)
			pips[#pips + 1] = { left and (word .. " " .. left) or word }
		end
		return #pips >= MAX_PIPS
	end)
end

-- Shields fill the empty end of the health bar, out of the same maximum.
function Party:UpdateAbsorb(card)
	if not card.absorb then return end
	card.absorb:SetMinMaxValues(0, UnitHealthMax(card.unit))
	if card.gone or not UnitGetTotalAbsorbs then
		card.absorb:SetValue(0)
		return
	end
	card.absorb:SetValue(UnitGetTotalAbsorbs(card.unit) or 0)
end

local DISPEL_CUES = {
	Magic = { word = "MAGIC", token = "magic" },
	Disease = { word = "DISEASE", token = "disease" },
	Curse = { word = "CURSE", token = "accent" },
	Poison = { word = "POISON", token = "danger" },
}

-- The first debuff you can remove, if any. The RAID filter asks the game
-- for debuffs this character can dispel.
function Party:DispelFor(unit)
	if not (C_UnitAuras and C_UnitAuras.GetAuraDataByIndex) then return nil end
	local ok, aura = pcall(C_UnitAuras.GetAuraDataByIndex, unit, 1, "HARMFUL|RAID")
	if not ok or not aura then return nil end
	local kind = aura.dispelName
	if Stoa:IsSecret(kind) then kind = nil end
	return DISPEL_CUES[kind] or { word = "DISPEL", token = "accent" }
end

-- Range can be secret; newer clients let a secret boolean set alpha directly.
-- The dead and offline stay dim whatever their range.
function Party:UpdateRange(card)
	if card.preview then return end
	local unit = card.unit
	if not unit or not UnitExists(unit) then return end
	if card.gone then
		card:SetAlpha(GONE_ALPHA)
		return
	end
	if unit == "player" or flag(UnitIsUnit(unit, "player")) then
		card:SetAlpha(1)
		return
	end
	local inRange = UnitInRange(unit)
	if card.SetAlphaFromBoolean then
		pcall(card.SetAlphaFromBoolean, card, inRange, 1, OUT_OF_RANGE_ALPHA)
	elseif not Stoa:IsSecret(inRange) then
		card:SetAlpha(inRange == false and OUT_OF_RANGE_ALPHA or 1)
	end
end

function Party:UpdateAll()
	self.frame:SetAlpha(Stoa:GetState() == Stoa.STATE_COMBAT and 1 or WORLD_ALPHA)
	for _, card in ipairs(self.cards) do
		self:UpdateCard(card)
	end
end

-- Tank watch ----------------------------------------------------------------
-- For healers: one line over the Halo naming who you're keeping alive, with
-- a health word, a thin bar with their shields, and your buffs on them.
-- It watches your focus if you have a friendly one, else the group's tank.
-- It shows with the Halo in combat, and in the /stoa test preview.

local WATCH_WIDTH = 220
local WATCH_PAD = 9
local HURT_HEALTH = 0.7

local function watchedUnit()
	if UnitExists("focus") and not flag(UnitCanAttack("player", "focus")) then return "focus" end
	if not IsInGroup() then return nil end
	local prefix, count = "party", 4
	if IsInRaid() then prefix, count = "raid", GetNumGroupMembers() end
	local mainTank
	for i = 1, count do
		local unit = prefix .. i
		if UnitExists(unit) and not flag(UnitIsUnit(unit, "player")) then
			local role = UnitGroupRolesAssigned and UnitGroupRolesAssigned(unit)
			if not Stoa:IsSecret(role) and role == "TANK" then return unit end
			if not mainTank and GetPartyAssignment and flag(GetPartyAssignment("MAINTANK", unit)) then
				mainTank = unit
			end
		end
	end
	return mainTank
end

function Party:BuildWatch()
	local watch = CreateFrame("Frame", "StoaTankWatch", UIParent)
	watch:SetFrameStrata("LOW")
	-- On a card like the party's, so it reads over snow and sky alike.
	watch:SetSize(WATCH_WIDTH + WATCH_PAD * 2, 64)
	UI.roundPanel(watch, 0.92)
	local halo = _G.StoaHalo
	if halo then
		watch:SetPoint("BOTTOM", halo, "TOP", 0, 14)
	else
		watch:SetPoint("CENTER", UIParent, "CENTER", 0, 120)
	end
	watch:SetAlpha(0)
	watch:EnableMouse(false)

	local label = UI.caption(watch, "Watching")
	label:SetPoint("TOPLEFT", WATCH_PAD, -WATCH_PAD)
	local word = UI.caption(watch, "")
	word:SetPoint("TOPRIGHT", -WATCH_PAD, -WATCH_PAD)
	local name = UI.text(watch, "serif", Stoa.typeSize.label + 2, "text", "LEFT")
	name:SetPoint("TOPLEFT", label, "BOTTOMLEFT", 0, -3)
	name:SetWidth(WATCH_WIDTH - 50)
	name:SetWordWrap(false)
	local percent = UI.text(watch, "serif", Stoa.typeSize.label + 2, "text", "RIGHT")
	percent:SetPoint("TOPRIGHT", word, "BOTTOMRIGHT", 0, -3)
	local hp = UI.bar(watch, WATCH_WIDTH, 3, "health")
	hp:SetPoint("TOPLEFT", name, "BOTTOMLEFT", 0, -5)
	hp:SetClipsChildren(true)
	local absorb = CreateFrame("StatusBar", nil, hp)
	absorb:SetStatusBarTexture(UI.WHITE)
	absorb:SetPoint("TOPLEFT", hp:GetStatusBarTexture(), "TOPRIGHT")
	absorb:SetSize(WATCH_WIDTH, 3)
	absorb:SetStatusBarColor(Stoa:Color("shield"))
	local buffs = UI.text(watch, "sans", Stoa.typeSize.caption, "text", "LEFT")
	buffs:SetPoint("TOPLEFT", hp, "BOTTOMLEFT", 0, -5)

	watch.name, watch.percent, watch.word, watch.hp = name, percent, word, hp
	watch.absorb, watch.buffs = absorb, buffs
	self.watch = watch
	Stoa:RegisterMover("tankwatch", watch, "Tank watch")
end

-- Fills the watch from sample data, for the /stoa test preview.
function Party:PreviewWatch()
	local watch = self.watch
	watch.name:SetText("Brunhok")
	watch.name:SetTextColor(Stoa:Color("text"))
	watch.percent:SetText("62")
	watch.word:SetText("HURT")
	watch.word:SetTextColor(Stoa:Color("accent"))
	watch.hp:SetMinMaxValues(0, 100)
	watch.hp:SetValue(62)
	watch.hp:SetStatusBarColor(Stoa:Color("health"))
	watch.absorb:SetMinMaxValues(0, 100)
	watch.absorb:SetValue(14)
	watch.buffs:SetText("SHIELD 12  ·  RENEW")
end

function Party:UpdateWatch()
	local watch = self.watch
	if not watch then return end
	local healer = Stoa:GetRole() == "HEALER"
	local previewing = Stoa.previewing and healer
	local unit = healer and watchedUnit()
	self.watchedUnit = unit

	local shown = previewing or (unit and Stoa:GetState() == Stoa.STATE_COMBAT)
	if not shown then
		if watch.shown then UI.fade(watch, 0, 0.3) end
		watch.shown = false
		return
	end
	if not watch.shown then UI.fade(watch, 1, 0.2) end
	watch.shown = true
	if previewing and not unit then
		self:PreviewWatch()
		return
	end

	watch.name:SetText(UnitName(unit))
	watch.name:SetTextColor(UI.classColor(unit))
	UI.setUnitBar(watch.hp, unit, "health")

	local fraction = healthFraction(unit)
	local word, token
	if not flag(UnitIsConnected(unit)) then
		word, token = "OFFLINE", "muted"
	elseif flag(UnitIsDeadOrGhost(unit)) then
		word, token = "DEAD", "muted"
	elseif fraction then
		if fraction < LOW_HEALTH then word, token = "LOW", "danger"
		elseif fraction < HURT_HEALTH then word, token = "HURT", "accent"
		else word, token = "STEADY", "muted" end
	end
	watch.word:SetText(word or "")
	if token then watch.word:SetTextColor(Stoa:Color(token)) end
	setPercent(watch.percent, unit, fraction)
	local low = word == "LOW"
	watch.hp:SetStatusBarColor(Stoa:Color(low and "danger" or "health"))
	watch.percent:SetTextColor(Stoa:Color(low and "danger" or "text"))

	watch.absorb:SetMinMaxValues(0, UnitHealthMax(unit))
	watch.absorb:SetValue(UnitGetTotalAbsorbs and UnitGetTotalAbsorbs(unit) or 0)

	local pips = {}
	self:AuraPips(unit, pips)
	local words = {}
	for i, pip in ipairs(pips) do words[i] = pip[1] end
	watch.buffs:SetText(table.concat(words, "  ·  "))
end

local function cardFor(self, unit)
	for _, card in ipairs(self.cards) do
		if card.unit == unit then return card end
	end
end

-- Blizzard's party frames repeat the cards.
local function hideBlizzardParty()
	for _, blizzard in ipairs({ PartyFrame, CompactPartyFrame }) do
		if blizzard then blizzard:SetParent(UI.hidden) end
	end
end

-- Lifecycle -----------------------------------------------------------------

function Party:OnEnable()
	self:Build()
	self:BuildWatch()
	self:UpdateAll()
	self:UpdateWatch()

	if self.db.hideBlizzardParty then
		Stoa:AfterCombat(function() xpcall(hideBlizzardParty, geterrorhandler()) end)
	end

	Stoa:On("STOA_ROLE_CHANGED", function()
		Stoa:AfterCombat(function() self:Layout() end)
	end)
	Stoa:On("STOA_STATE_CHANGED", function()
		self:UpdateAll()
		self:UpdateGrid()
		self:UpdateWatch()
	end)
	Stoa:On("STOA_PREVIEW_CHANGED", function()
		self:UpdateGrid()
		self:UpdateWatch()
	end)
	Stoa:On("STOA_ROLE_CHANGED", function() self:UpdateWatch() end)
	Stoa:On("PLAYER_FOCUS_CHANGED", function() self:UpdateWatch() end)
	Stoa:On("GROUP_ROSTER_UPDATE", function()
		self:UpdateAll()
		self:UpdateWatch()
		self:UpdateGrid()
		-- The healer row re-centres on the cards in it.
		Stoa:AfterCombat(function() self:Layout() end)
	end)
	Stoa:On("PLAYER_TARGET_CHANGED", function() self:UpdateAll() end)
	Stoa:On("STOA_THEME_CHANGED", function() self:UpdateAll() end)
	Stoa:On("STOA_CLICKS_CHANGED", function() self:UpdateGrid() end)
	Stoa:On("PLAYER_ENTERING_WORLD", function() self:UpdateAll() end)
	Stoa:On("UNIT_CONNECTION", function(unit)
		local card = cardFor(self, unit)
		if card then self:UpdateCard(card) end
	end)
	for _, event in ipairs({ "UNIT_HEALTH", "UNIT_MAXHEALTH", "UNIT_NAME_UPDATE", "UNIT_FLAGS", "UNIT_AURA", "UNIT_ABSORB_AMOUNT_CHANGED" }) do
		Stoa:On(event, function(unit)
			local card = cardFor(self, unit)
			if card then self:UpdateCard(card) end
			if unit and self.watchedUnit and flag(UnitIsUnit(unit, self.watchedUnit)) then
				self:UpdateWatch()
			end
		end)
	end

	-- Range has no event, so it's checked a few times a second; buff timers
	-- count down once a second.
	C_Timer.NewTicker(0.3, function()
		for _, card in ipairs(self.cards) do
			self:UpdateRange(card)
		end
	end)
	C_Timer.NewTicker(1, function()
		if self.frame:IsVisible() then self:UpdateAll() end
		self:UpdateWatch()
	end)
end
