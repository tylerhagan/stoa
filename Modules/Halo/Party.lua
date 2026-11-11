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
	-- When not healing, cards show health, and words only for what you can
	-- act on: a debuff you can dispel, dead or offline.
	quietCards = true,
	-- Out of combat the cards rest faint until the mouse is over them.
	restFade = false,
	-- Tanks and damage dealers see the party as thin strips beside the
	-- Halo instead of cards.
	strips = false,
	-- The click grid: "open" always shows it, "fold" keeps just its title
	-- until you hover a card or hold Shift, "hidden" never shows it.
	clickGrid = "fold",
})
Stoa:SpecSettings(Party, { "clickGrid" })

function Party:Quiet()
	return self.db.quietCards and Stoa:GetRole() ~= "HEALER"
end

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
	-- Strips stand to the left of the Halo as a column centred on it,
	-- mirroring the target on its right. (The tank watch above that spot
	-- is a healer's, and healers have cards.)
	STRIP = { width = 172, height = 27, gap = 7, style = "strip", strip = true, point = { "TOPLEFT", UIParent, "LEFT", 36, 180 } },
}
local STRIP_GAP = 60
-- A strip turns amber below half health, sooner than a card's LOW.
local STRIP_LOW = 0.5

local function layoutFor(role)
	if LAYOUTS[role] then return LAYOUTS[role] end
	return Party.db.strips and LAYOUTS.STRIP or LAYOUTS.OTHER
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
		Stoa:AddZoneLine(GameTooltip, button.unit)
		self:Peek("card", true)
		button.hover = true
		self:UpdateCard(button)
	end)
	card:SetScript("OnLeave", function(button)
		GameTooltip_Hide()
		self:Peek("card", false)
		button.hover = nil
		self:UpdateCard(button)
	end)

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
	-- The first time the strips show, a spot saved for the old cards is
	-- let go for tanks and damage dealers: it was chosen for a column of
	-- cards at the screen's edge, and the strips belong beside the Halo.
	if self.db.strips and not Stoa.char.stripsPlaced then
		Stoa.char.stripsPlaced = true
		Stoa.char.layouts = Stoa.char.layouts or {}
		for _, role in ipairs({ "TANK", "MELEE", "RANGED" }) do
			Stoa.char.layouts[role] = Stoa.char.layouts[role] or {}
			Stoa.char.layouts[role].party = false
		end
	end
	self:Layout()
	Stoa:RegisterMover("party", frame, "Party", { default = function() self:Layout() end })
end

-- How many cards show: you plus your party, or all five in the preview.
function Party:VisibleCount()
	if self.cards and self.cards[1].preview then return #UNITS end
	return math.max(1, math.min(#UNITS, GetNumGroupMembers and GetNumGroupMembers() or 1))
end

-- The top of the highest action bar standing under the Halo where a row
-- `wide` across would sit, in UIParent's units; nil when none is in the way.
local ROW_BARS = { "MainActionBar", "MainMenuBar", "MultiBarBottomLeft", "MultiBarBottomRight", "MultiBar5", "MultiBar6", "MultiBar7", "PetActionBar", "StanceBar" }
local function barsUnder(ceiling, wide)
	local scale = UIParent:GetEffectiveScale() or 1
	local middle = UIParent:GetWidth() / 2
	local best
	for _, name in ipairs(ROW_BARS) do
		local bar = _G[name]
		if bar and bar.IsShown and bar:IsShown() and not (bar.IsForbidden and bar:IsForbidden()) then
			local ok, left, bottom, width, height = pcall(bar.GetRect, bar)
			left, bottom = ok and Stoa:PlainNumber(left), ok and Stoa:PlainNumber(bottom)
			width, height = ok and Stoa:PlainNumber(width), ok and Stoa:PlainNumber(height)
			if left and bottom and width and height and width > 1 then
				local k = (bar:GetEffectiveScale() or 1) / scale
				local l, r, top = left * k, (left + width) * k, (bottom + height) * k
				local across = l < middle + wide / 2 and r > middle - wide / 2
				if across and top < ceiling and (not best or top > best) then best = top end
			end
		end
	end
	return best
end

-- Sizes and places the cards for the current role. Out of combat only.
function Party:Layout()
	-- Secure frames can't move in a fight; the caller comes back after it.
	if InCombatLockdown() then return end
	local layout = layoutFor(Stoa:GetRole())
	local frame = self.frame
	local count = self:VisibleCount()
	local halo = _G.StoaHalo
	if not Stoa:HasSavedPosition("party") then
		frame:ClearAllPoints()
		if layout.row and halo then
			-- Under the combat bar when there is one, in and out of combat:
			-- the row stays put when a fight starts or ends instead of
			-- jumping. In a group the target plaque keeps its
			-- Halo spot out of combat too, so nothing needs the room.
			local combatBar = Stoa:IsModuleEnabled("CombatBar") and Stoa.modules.CombatBar
			local offset = combatBar and combatBar:GroupOffset() or -52
			-- A tall combat bar can push the row down onto the open
			-- console. Out of combat it then stops just above the console
			-- (it moves only in that case); in a fight the console folds
			-- and the row keeps its place under the bar.
			-- The same goes for action bars that stay up out of combat under
			-- the Halo (Slim and Minimal stand them above the console's line):
			-- the row stops just above the highest of them.
			local console = Stoa.modules.Grimoire
			local haloBottom = halo:GetBottom()
			if not Stoa:CombatLayout() and haloBottom then
				local k = (halo:GetEffectiveScale() or 1) / (UIParent:GetEffectiveScale() or 1)
				local pets = (Stoa.Pet and Stoa.Pet.enabled and Stoa.Pet.db.partyPets and layout.grid) and 30 or 0
				local bottom = haloBottom * k + offset - layout.height - pets
				local clear = 0
				if console and console.enabled and console.OpenHeight then clear = console:OpenHeight() + 14 end
				local wide = count * layout.width + (count - 1) * layout.gap
				-- Only once the calm has ended: until then the combat bar
				-- still stands in that room and the row would land on it.
				if Stoa:GetState() ~= Stoa.STATE_COMBAT then
					local barsTop = barsUnder(haloBottom * k, wide)
					if barsTop then clear = math.max(clear, barsTop + 12) end
				end
				if bottom < clear then offset = offset + (clear - bottom) end
			end
			frame:SetPoint("TOP", halo, "BOTTOM", 0, offset)
		elseif layout.row then
			frame:SetPoint("TOP", UIParent, "CENTER", 0, -260)
		elseif layout.strip and halo then
			local tall = count * layout.height + (count - 1) * layout.gap
			frame:SetPoint("TOPRIGHT", halo, "LEFT", -STRIP_GAP, math.floor(tall / 2))
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

local GRID_MODES = { "open", "fold", "hidden" }
Party.gridModes = GRID_MODES

local function modeIndex(mode)
	for i, name in ipairs(GRID_MODES) do
		if name == mode then return i end
	end
end

function Party:GridMode()
	local mode = self.db.clickGrid
	return modeIndex(mode) and mode or "fold"
end

function Party:BuildGrid()
	local grid = CreateFrame("Frame", "StoaClickGrid", UIParent)
	local width = GRID_LABEL_WIDTH + #GRID_COLUMNS * GRID_CELL_WIDTH
	grid:SetSize(width, 20 + GRID_ROW_HEIGHT * (#GRID_ROWS + 1))
	grid:SetFrameStrata("LOW")
	grid:SetPoint("TOPLEFT", UIParent, "LEFT", 60, -40)
	grid:Hide()
	self.grid = grid
	self.peeks = {}

	-- The title is the grid's handle: click it to keep the grid open or
	-- fold it back to this one line.
	local handle = CreateFrame("Button", nil, grid)
	handle:SetPoint("TOPLEFT")
	handle:SetSize(width, 16)
	handle:RegisterForClicks("LeftButtonUp")
	local title = UI.caption(handle, "")
	title:SetPoint("LEFT")
	grid.title = title
	handle:SetScript("OnClick", function()
		self.db.clickGrid = self:GridMode() == "open" and "fold" or "open"
		self:UpdateGrid()
	end)
	handle:SetScript("OnEnter", function(button)
		self:Peek("handle", true)
		GameTooltip:SetOwner(button, "ANCHOR_TOPLEFT")
		GameTooltip:SetText("Click grid")
		GameTooltip:AddLine(self:GridMode() == "open" and "Click to fold it to this line. It opens while you hover a card or hold Shift."
			or "Click to keep it open.", 1, 1, 1, true)
		GameTooltip:Show()
	end)
	handle:SetScript("OnLeave", function()
		self:Peek("handle", false)
		GameTooltip_Hide()
	end)

	local body = CreateFrame("Frame", nil, grid)
	body:SetAllPoints()
	grid.body = body

	local function cell(row, col, kind)
		local x = col == 0 and 0 or GRID_LABEL_WIDTH + (col - 1) * GRID_CELL_WIDTH
		local y = -20 - row * GRID_ROW_HEIGHT
		local fs = kind == "caption" and UI.caption(body, "") or UI.text(body, "serif", Stoa.typeSize.label, "text")
		fs:SetPoint("LEFT", body, "TOPLEFT", x + 6, y - GRID_ROW_HEIGHT / 2)
		fs:SetWidth((col == 0 and GRID_LABEL_WIDTH or GRID_CELL_WIDTH) - 10)
		fs:SetWordWrap(false)
		return fs
	end

	for col, column in ipairs(GRID_COLUMNS) do
		cell(0, col, "caption"):SetText(column.label:upper())
	end
	grid.cells = {}
	for row, mod in ipairs(GRID_ROWS) do
		local line = UI.line(body)
		line:SetPoint("TOPLEFT", 0, -20 - row * GRID_ROW_HEIGHT)
		line:SetPoint("TOPRIGHT", 0, -20 - row * GRID_ROW_HEIGHT)
		cell(row, 0, "caption"):SetText(mod.label:upper())
		for col, column in ipairs(GRID_COLUMNS) do
			local fs = cell(row, col)
			-- What the spell costs, quietly at the cell's right (as Healbot's
			-- hover card did), so you see what a click spends.
			local price = UI.caption(body, "")
			price:SetPoint("RIGHT", body, "TOPLEFT", GRID_LABEL_WIDTH + col * GRID_CELL_WIDTH - 6, -20 - row * GRID_ROW_HEIGHT - GRID_ROW_HEIGHT / 2)
			fs:SetWidth(GRID_CELL_WIDTH - 44)
			fs.price = price
			grid.cells[mod.prefix .. column.id] = fs
		end
	end
	Stoa:RegisterMover("clickgrid", grid, "Click grid")
end

-- A folded grid opens while something asks to see it: a hovered card, its
-- own title, or Shift held down.
function Party:Peek(reason, on)
	if not self.peeks then return end
	self.peeks[reason] = on or nil
	self:UpdateGridBody()
end

function Party:UpdateGridBody()
	local grid = self.grid
	if not grid then return end
	local open = self:GridMode() == "open" or next(self.peeks) ~= nil
	grid.body:SetShown(open)
	grid.title:SetText(open and "CLICK GRID · CLICK-CAST ON ANY CARD" or "CLICK GRID · HOVER A CARD OR HOLD SHIFT")
end

function Party:UpdateGrid()
	local grid = self.grid
	local clickCast = Stoa.modules.ClickCast
	local bindings = clickCast and clickCast.Bindings and clickCast:Bindings() or {}
	local blank = false
	for key, fs in pairs(grid.cells) do
		-- Cleared first: the game skips a SetText with the same words, so a
		-- name drawn before the serif face loaded (empty) would stay empty.
		fs:SetText("")
		fs:SetText(shortName(bindings[key]))
		fs.spell = bindings[key]
		if (fs:GetStringWidth() or 0) == 0 then blank = true end
	end
	self.gridTries = blank and (self.gridTries or 0) + 1 or 0
	if blank and not self.gridRetry and self.gridTries <= 10 then
		self.gridRetry = true
		C_Timer.After(0.5, function()
			self.gridRetry = nil
			if self.grid then self:UpdateGrid() end
		end)
	end
	self:UpdateGridCosts()
	local cards = Stoa.previewing or IsInGroup()
	local wanted = layoutFor(Stoa:GetRole()).grid and cards and self:GridMode() ~= "hidden"
	grid:SetShown(wanted and true or false)
	grid:SetAlpha(Stoa:GetState() == Stoa.STATE_COMBAT and 1 or 0.8)
	self:UpdateGridBody()
end

-- Each binding's cost, and a dimmed cell when you can't pay it right now.
local function spellCost(spell)
	if type(spell) ~= "string" or not (C_Spell and C_Spell.GetSpellPowerCost) then return nil end
	local ok, list = pcall(C_Spell.GetSpellPowerCost, spell)
	local first = ok and type(list) == "table" and list[1]
	return first and Stoa:PlainNumber(first.cost) or nil
end

function Party:UpdateGridCosts()
	local grid = self.grid
	if not grid then return end
	local check = (C_Spell and C_Spell.IsSpellUsable) or IsUsableSpell
	for _, fs in pairs(grid.cells) do
		local price = fs.spell and spellCost(fs.spell)
		fs.price:SetText(price and price > 0 and tostring(price) or "")
		local short = false
		if fs.spell and check then
			local ok, _, noPower = pcall(check, fs.spell)
			short = ok and noPower == true
		end
		fs:SetAlpha(short and 0.45 or 1)
		fs.price:SetAlpha(short and 0.45 or 1)
	end
end

function Party:SetGridMode(mode)
	self.db.clickGrid = modeIndex(mode) and mode or "fold"
	if self.grid then self:UpdateGrid() end
end

-- /stoa grid [open|fold|hidden] sets or cycles the click grid.
Stoa.commands.grid = function(rest)
	local mode = rest and rest:lower():match("%a+")
	if mode == "hide" then mode = "hidden" end
	if not modeIndex(mode) then
		local index = modeIndex(Party:GridMode())
		mode = GRID_MODES[index % #GRID_MODES + 1]
	end
	Party:SetGridMode(mode)
	local words = { open = "always open", fold = "folded to its title until you hover a card or hold Shift", hidden = "hidden" }
	Stoa:Print(("Click grid: %s."):format(words[mode]))
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

-- The percent in the card's corner.
local function setPercent(fs, unit, fraction)
	UI.setHealthPercent(fs, unit, fraction)
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
	local strip = card.style and card.style.strip
	local low = not gone and fraction and fraction < (strip and STRIP_LOW or LOW_HEALTH)
	local dispel = not gone and self:DispelFor(unit)

	if gone then
		card.percent:SetText("·")
		card.hp:SetValue(0)
		pips[1] = { gone }
	else
		setPercent(card.percent, unit, fraction)
		if dispel then pips[#pips + 1] = { dispel.word, dispel.token } end
		if not self:Quiet() then
			if low then pips[#pips + 1] = { "LOW", "danger" } end
			self:AuraPips(unit, pips)
		end
	end
	-- During a ready check each card says where that player stands.
	local kit = Stoa.modules.Kit
	local ready, readyToken
	if kit and kit.ReadyPip and kit.enabled and not gone then
		ready, readyToken = kit:ReadyPip(unit)
		if ready then table.insert(pips, 1, ready) end
	end
	UI.setPips(card, pips)

	-- Bar and percent turn amber when low, and the border says why.
	local r, g, b = Stoa:Color(low and "danger" or "health")
	card.hp:SetStatusBarColor(r, g, b)
	card.percent:SetTextColor(Stoa:Color(low and "danger" or "text"))
	if ready then
		UI.cellWord(card, ready[1], readyToken)
	elseif gone then
		UI.cellWord(card, gone, "muted")
	elseif dispel then
		UI.cellWord(card, dispel.word, dispel.token)
	elseif low then
		UI.cellWord(card, "LOW", "danger")
	end

	card.glow:Clear()
	local isTarget = flag(UnitIsUnit(unit, "target"))
	-- A strip rests faint while its player is fine. Health the game keeps
	-- secret in a fight can't be judged, so the strip stays at full strength.
	if UI.stripRest(card, fraction and not (gone or dispel or low or ready or isTarget or card.hover)) then
		if low then card.name:SetTextColor(Stoa:Color("danger")) end
	elseif dispel then
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
-- once there's under half a minute left. Each is listed by a spell ID and
-- matched by that spell's name in the game's language (every rank shares
-- it); the English name stands in if the game doesn't know the ID.
local OWN_BUFF_IDS = {
	{ 17, "Power Word: Shield", { "SHLD", "shield" } },
	{ 139, "Renew", { "RNW" } },
	{ 33076, "Prayer of Mending", { "MNDNG" } },
	{ 6346, "Fear Ward", { "WRD" } },
	{ 10060, "Power Infusion", { "INFSN" } },
	{ 588, "Inner Fire", { "INNR FR" } },
	{ 1022, "Blessing of Protection", { "PRTCTN" } },
	{ 1044, "Blessing of Freedom", { "FRDM" } },
	{ 6940, "Blessing of Sacrifice", { "SCRFC" } },
	{ 774, "Rejuvenation", { "RJV" } },
	{ 8936, "Regrowth", { "RGRWTH" } },
	{ 1238215, "Wild Growth", { "GRWTH" } },
	{ 29166, "Innervate", { "INNRVT" } },
}
-- Debuffs from anyone that change what you can cast on them.
local LOCKOUT_IDS = {
	{ 6788, "Weakened Soul", "WS" },
	{ 25771, "Forbearance", "FRB" },
}

local function byName(list)
	local map = {}
	for _, entry in ipairs(list) do
		map[Stoa.Spells.localName(entry[1], entry[2])] = entry[3]
	end
	return map
end
local OWN_BUFFS, LOCKOUTS
local MAX_PIPS = 3

local function timeLeft(aura)
	local expires = aura.expirationTime
	if Stoa:IsSecret(expires) or not expires or expires == 0 then return nil end
	local left = expires - GetTime()
	if left > 0 and left < 30 then return math.floor(left + 0.5) end
end

local function scan(unit, filter, fn)
	if Stoa:AurasHidden() or not (C_UnitAuras and C_UnitAuras.GetAuraDataByIndex) then return end
	for i = 1, 40 do
		local ok, aura = pcall(C_UnitAuras.GetAuraDataByIndex, unit, i, filter)
		if not ok or not aura then return end
		local name = aura.name
		if not Stoa:IsSecret(name) and fn(name, aura) then return end
	end
end

-- In a fight the game hides auras, so your Shield and Renew (and the
-- Weakened Soul your shield leaves) come from your own casts instead.
local CAST_PIPS = {
	{ "shield", "SHLD", "shield" },
	{ "renew", "RNW" },
	{ "ws", "WS" },
}

local function castPips(unit, pips)
	for _, cue in ipairs(CAST_PIPS) do
		local left = Stoa:OwnHealLeft(unit, cue[1])
		if left then
			left = math.floor(left + 0.5)
			pips[#pips + 1] = { left < 30 and (cue[2] .. " " .. left) or cue[2], cue[3] }
			if #pips >= MAX_PIPS then return end
		end
	end
end

function Party:AuraPips(unit, pips)
	if Stoa:AurasHidden() then return castPips(unit, pips) end
	if not OWN_BUFFS then OWN_BUFFS, LOCKOUTS = byName(OWN_BUFF_IDS), byName(LOCKOUT_IDS) end
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
-- For healers: a card beside the Halo's upper left naming who you're keeping alive, with
-- a health word, a thin bar with their shields, and your buffs on them.
-- It watches your focus if you have a friendly one, else the group's tank.
-- It shows with the Halo in combat, and in the /stoa test preview. Your
-- click-casting bindings work on it in combat.

local WATCH_WIDTH = 214
local WATCH_PAD = 14
-- Room on the right for the half of the coin inside the plaque.
local WATCH_COIN_SPACE = UI.PLAQUE_COIN_SPACE
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
	watch:SetSize(WATCH_WIDTH + WATCH_PAD + WATCH_COIN_SPACE, 84)
	-- A plaque like the target opposite: the coin faces the Halo.
	local plaque = UI.plaque(watch, "RIGHT")
	watch.plaque = plaque
	local halo = _G.StoaHalo
	if halo then
		watch:SetPoint("BOTTOMRIGHT", halo, "LEFT", -52, 36)
	else
		watch:SetPoint("CENTER", UIParent, "CENTER", 0, 120)
	end
	watch:SetAlpha(0)
	watch:EnableMouse(false)

	local label = UI.caption(watch, "Watching")
	label:SetPoint("TOPLEFT", WATCH_PAD, -WATCH_PAD)
	local word = UI.caption(watch, "")
	word:SetPoint("TOPRIGHT", -WATCH_COIN_SPACE, -WATCH_PAD)
	local name = UI.text(watch, "serif", Stoa.typeSize.title, "text", "LEFT")
	name:SetPoint("TOPLEFT", label, "BOTTOMLEFT", 0, -4)
	name:SetWidth(WATCH_WIDTH - 50)
	name:SetWordWrap(false)
	local percent = UI.text(watch, "serif", Stoa.typeSize.title, "text", "RIGHT")
	percent:SetPoint("TOPRIGHT", word, "BOTTOMRIGHT", 0, -4)
	local hp = UI.bar(watch, WATCH_WIDTH, 7, "health")
	hp:SetPoint("TOPLEFT", name, "BOTTOMLEFT", 0, -5)
	hp:SetClipsChildren(true)
	local absorb = CreateFrame("StatusBar", nil, hp)
	absorb:SetStatusBarTexture(UI.WHITE)
	absorb:SetPoint("TOPLEFT", hp:GetStatusBarTexture(), "TOPRIGHT")
	absorb:SetSize(WATCH_WIDTH, 7)
	absorb:SetStatusBarColor(Stoa:Color("shield"))
	UI.engrave(hp, WATCH_WIDTH)
	local buffs = UI.caption(watch, "")
	buffs:SetPoint("TOPLEFT", hp, "BOTTOMLEFT", 0, -6)
	watch.label = label

	watch.name, watch.percent, watch.word, watch.hp = name, percent, word, hp
	watch.absorb, watch.buffs = absorb, buffs
	self.watch = watch
	Stoa:RegisterMover("tankwatch", watch, "Tank watch")
	self:BuildWatchClicks(watch)
end

-- Your click-casting bindings work on the watch card just as on the party
-- cards. The card itself fades, so the clicks live on a secure button laid
-- over it that the game shows only in combat while its unit exists. Its
-- unit can only change out of combat.
function Party:BuildWatchClicks(watch)
	local clicker = CreateFrame("Button", "StoaTankWatchClicks", UIParent, "SecureUnitButtonTemplate")
	clicker:SetFrameStrata("LOW")
	clicker:SetFrameLevel(watch:GetFrameLevel() + 5)
	clicker:SetAllPoints(watch)
	clicker:SetAttribute("type1", "target")
	clicker:SetAttribute("type2", "togglemenu")
	clicker:RegisterForClicks("AnyUp")
	clicker:SetScript("OnEnter", function(button)
		local unit = button:GetAttribute("unit")
		if unit and UnitExists(unit) then
			GameTooltip_SetDefaultAnchor(GameTooltip, button)
			GameTooltip:SetUnit(unit)
			Stoa:AddZoneLine(GameTooltip, unit)
		end
	end)
	clicker:SetScript("OnLeave", GameTooltip_Hide)
	clicker:Hide()
	self.clicker = clicker
	Stoa:RegisterClickFrame(clicker)
end

-- false means nobody: the button stays hidden.
function Party:SetClickUnit(unit)
	if self.clickUnit == unit or not self.clicker or InCombatLockdown() then return end
	self.clickUnit = unit
	local clicker = self.clicker
	UnregisterStateDriver(clicker, "visibility")
	if unit then
		clicker:SetAttribute("unit", unit)
		RegisterStateDriver(clicker, "visibility", "[combat,@" .. unit .. ",exists] show; hide")
	else
		clicker:SetAttribute("unit", nil)
		clicker:Hide()
	end
end

-- Fills the watch from sample data, for the /stoa test preview.
function Party:PreviewWatch()
	local watch = self.watch
	watch.label:SetText("WATCHING · TANK")
	SetPortraitTexture(watch.plaque.portrait, "player")
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
	watch.buffs:SetText("SHLD 12 · RNW")
end

function Party:UpdateWatch()
	local watch = self.watch
	if not watch then return end
	local healer = Stoa:GetRole() == "HEALER"
	local previewing = Stoa.previewing and healer
	local unit = healer and watchedUnit()
	-- In combat the card keeps showing whoever its clicks are set to, so
	-- what you see is always who you heal. A new focus takes over after.
	if InCombatLockdown() and self.clickUnit ~= nil then
		unit = self.clickUnit or nil
		if unit and not UnitExists(unit) then unit = nil end
	end
	self.watchedUnit = unit
	self:SetClickUnit(healer and watchedUnit() or false)

	local shown = previewing or (unit and Stoa:GetState() == Stoa.STATE_COMBAT)
	if not shown then
		if watch.shown then UI.fade(watch, 0, 0.3) end
		watch.shown = false
		return
	end
	if not watch.shown then UI.fade(watch, 1, 0.2) end
	watch.shown = true
	watch.plaque:SetRank(nil)
	if previewing and not unit then
		self:PreviewWatch()
		return
	end

	watch.name:SetText(UnitName(unit))
	watch.name:SetTextColor(UI.classColor(unit))
	watch.label:SetText(unit == "focus" and "WATCHING · FOCUS" or "WATCHING · TANK")
	SetPortraitTexture(watch.plaque.portrait, unit)
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
	watch.buffs:SetText(table.concat(words, " · "))
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
	Stoa:On("SPELL_UPDATE_USABLE", function()
		if self.grid and self.grid:IsShown() then xpcall(self.UpdateGridCosts, Stoa.catch, self) end
	end)
	self:Build()
	self:BuildWatch()
	self:UpdateAll()
	self:UpdateWatch()
	if self.db.restFade then
		local REST = 0.45
		local shown
		Stoa:NewTicker(0.15, function()
			local full = Stoa:GetState() == Stoa.STATE_COMBAT or InCombatLockdown()
				or (self.frame:IsVisible() and self.frame:IsMouseOver())
			if full == shown then return end
			shown = full
			UI.fade(self.frame, full and 1 or REST, full and 0.12 or 0.4)
		end)
	end

	if self.db.hideBlizzardParty then
		Stoa:AfterCombat(function() xpcall(hideBlizzardParty, Stoa.catch) end)
	end

	Stoa:On("STOA_ROLE_CHANGED", function()
		Stoa:AfterCombat(function() self:Layout() end)
	end)
	Stoa:On("STOA_COMBAT_LAYOUT", function()
		if not InCombatLockdown() then self:Layout() end
	end)
	Stoa:On("STOA_STATE_CHANGED", function()
		-- The row's resting spot depends on whether the combat bar is up.
		if not InCombatLockdown() then
			self:Layout()
		else
			self:UpdateAll()
			self:UpdateGrid()
		end
		self:UpdateWatch()
	end)
	Stoa:On("STOA_PREVIEW_CHANGED", function()
		self:UpdateGrid()
		self:UpdateWatch()
	end)
	Stoa:On("STOA_ROLE_CHANGED", function()
		self:UpdateWatch()
		self:UpdateAll()
	end)
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
	Stoa:On("MODIFIER_STATE_CHANGED", function()
		if self.grid and self.grid:IsShown() then self:Peek("shift", IsShiftKeyDown()) end
	end)
	Stoa:On("PLAYER_ENTERING_WORLD", function() self:UpdateAll() end)
	Stoa:On("STOA_OWN_HEALS", function()
		self:UpdateAll()
		self:UpdateWatch()
	end)
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
	Stoa:NewTicker(0.3, function()
		if not self.frame:IsShown() then return end
		for _, card in ipairs(self.cards) do
			self:UpdateRange(card)
		end
	end)
	Stoa:NewTicker(1, function()
		if self.frame:IsVisible() then self:UpdateAll() end
		self:UpdateWatch()
	end)
end

Stoa:On("STOA_SPEC_SETTINGS", function()
	if Party.grid then Party:SetGridMode(Party.db.clickGrid) end
end)
