-- Stoa: the welcome page.
-- Shown once per character, a few seconds into the first login, out of
-- combat: a short wizard that walks through where to start (by hand, from a
-- saved setup or as Stoa ships), what each spec plays, the look, what a
-- fight does to the console, how much of Stoa to use and the other addons
-- Stoa found. /stoa welcome brings it back.
local _, ns = ...
local Stoa = ns.Stoa
local UI = Stoa.UI

local Welcome = {}
Stoa.Welcome = Welcome

local WIDTH, HEIGHT = 860, 600
local HEADER, FOOTER = 64, 62
local RAIL = 190
local PAD = 28
local STEP_ORDER = { "start", "specs", "look", "combat", "preset", "addons", "ready" }
local CLASS_DEFAULT_WORD = "  (class default)"
local WELCOME_THEMES = { "Bone", "Tide", "Graphite", "Class" }

local function slotRole(slot)
	local chosen = Stoa.char.roles["slot" .. slot]
	if chosen and chosen ~= "AUTO" then return chosen, false end
	return Stoa:DefaultRole(), true
end

-- Presets ---------------------------------------------------------------------
-- Three starting points. Every preset first puts the settings any preset
-- touches back to their defaults, then applies its own changes, so picking
-- one after another never leaves leftovers. Skins and the like only change
-- after /reload.
local PRESET_ORDER = { "full", "quiet", "classic" }
-- Full is how Stoa ships; the other two are described against it, so the
-- page says exactly what a choice takes away.
local PRESET_WORDS = {
	full = { "Full", "Everything on, as Stoa ships: tooltip details, the quest line, At a glance, every bar row out of combat, and Stoa's look on windows, bags, tooltips, the top of the screen and nameplates." },
	quiet = { "Quiet", "Fewer words than Full: no tooltip details, quest line or At a glance; extra bar rows only on mouseover; the click grid folded for healers, hidden otherwise. Stoa's look stays." },
	classic = { "Classic feel", "Blizzard's own windows, bags, character sheet, tooltips, top of screen and nameplates instead of Stoa's. The console, Halo, frames and words stay as in Full." },
}
local SKINS = { "Windows", "MoreWindows", "Bags", "Character", "Tooltip", "Top", "Plates" }

-- Settings every preset resets: { module, key }.
local TOUCHED = {
	{ "Tooltip", "unitDetails" }, { "Kit", "questLine" }, { "Party", "clickGrid" },
	{ "Tally", "enabled" }, { "ActionBars", "hoverTray" },
}

local function playsHealer()
	for slot = 1, 2 do
		if slotRole(slot) == "HEALER" then return true end
	end
	return false
end

-- What each preset changes, as { module, key, value }.
local function changesFor(name)
	local list = {}
	if name == "quiet" then
		list[#list + 1] = { "Tooltip", "unitDetails", false }
		list[#list + 1] = { "Kit", "questLine", false }
		-- The grid only matters to healers, who keep it folded.
		list[#list + 1] = { "Party", "clickGrid", playsHealer() and "fold" or "hidden" }
		list[#list + 1] = { "Tally", "enabled", false }
		list[#list + 1] = { "ActionBars", "hoverTray", true }
	elseif name == "classic" then
		for _, module in ipairs(SKINS) do list[#list + 1] = { module, "enabled", false } end
	end
	return list
end

local function setValue(module, key, value)
	local m = Stoa.modules[module]
	if m and m.db then m.db[key] = value end
end

local function defaultOf(module, key)
	if key == "enabled" then return true end
	local m = Stoa.modules[module]
	return m and m.defaults[key]
end

-- Returns true, or false for a name that isn't a preset.
function Welcome:ApplyPreset(name)
	if not PRESET_WORDS[name] then return false end
	for _, entry in ipairs(TOUCHED) do setValue(entry[1], entry[2], defaultOf(entry[1], entry[2])) end
	for _, module in ipairs(SKINS) do setValue(module, "enabled", true) end
	local comforts = Stoa.modules.Comforts
	if comforts and comforts.db then
		for key, value in pairs(comforts.defaults) do comforts.db[key] = value end
	end
	for _, change in ipairs(changesFor(name)) do setValue(change[1], change[2], change[3]) end
	Stoa.db.preset = name
	-- Until the next reload the page asks for one.
	self.applied = name
	-- The settings these change are read when the UI loads.
	local party = Stoa.modules.Party
	if party and party.SetGridMode and party.db then party:SetGridMode(party.db.clickGrid) end
	return true
end

function Welcome:PresetNames()
	return PRESET_ORDER
end

-- The wizard ------------------------------------------------------------------
-- One window, a step at a time: where to start, what each spec plays, the
-- look, what happens in a fight, how much of Stoa, the other addons Stoa
-- found (only when it found some) and a last look before finishing. A step
-- rail on the left goes back to any step already seen. Choices that need a
-- reload (a preset, the ornament, the Halo on or off, another addon turned
-- off, a saved setup) wait for Finish, which reloads once.

local BODY_X = RAIL + PAD
local BODY_W = WIDTH - BODY_X - PAD
local BODY_TOP = HEADER + 22
local GAP = 10

local STEP_TITLES = {
	start = "Welcome", specs = "Your specs", look = "Look", combat = "In combat",
	preset = "How much", addons = "Other addons", ready = "Ready",
}
local CLASS_THEME_ORDER = { "Warrior", "Paladin", "Hunter", "Rogue", "Priest", "Shaman", "Mage", "Warlock", "Druid" }
local VISION_WORDS = { Standard = "Standard", RedGreen = "Red-green", BlueYellow = "Blue-yellow", NoColour = "No colour" }
local COMBAT_ORDER = { "fold", "open", "none" }
local COMBAT_WORDS = {
	fold = { "Fold the console, the Halo rises", "Chat and pages fold to a thin line; health, mana and your spells gather around your character." },
	open = { "Keep the console open, the Halo rises too", "Everything stays where it is; the Halo adds itself around your character." },
	none = { "Keep the console open, no Halo", "For players who use other unit frames. Stoa looks the same in and out of a fight." },
}
local CALMS = { "1", "3", "5", "8" }
local MAX_SETUPS = 4

local function halo()
	return Stoa.modules.Halo and Stoa.modules.Halo.db
end

-- The combat choice as one word: the console and the Halo go together, so
-- the console never folds with no Halo to take its place.
local function combatChoice()
	local db = halo()
	if db and db.enabled == false then return "none" end
	return Stoa.db.combatConsole == "open" and "open" or "fold"
end

local function setCombat(choice)
	local db = halo()
	if db then db.enabled = choice ~= "none" end
	Stoa.db.combatConsole = choice
	local console = Stoa.modules.Grimoire
	if console and console.Refold then console:Refold() end
end

local function themeWord(name)
	return name == "Class" and "Your class" or name
end

-- A wide choice: a title in the sans and a line under it in muted.
local function card(parent, width, height, title, onClick)
	local button = UI.button(parent, title, width, onClick)
	button:SetHeight(height)
	button.text:ClearAllPoints()
	button.text:SetPoint("TOPLEFT", 16, -11)
	button.text:SetPoint("RIGHT", -16, 0)
	button.text:SetJustifyH("LEFT")
	Stoa:SetFont(button.text, "sans", Stoa.typeSize.label)
	local sub = UI.text(button, "sans", Stoa.typeSize.body, "muted")
	sub:SetPoint("TOPLEFT", button.text, "BOTTOMLEFT", 0, -4)
	sub:SetPoint("RIGHT", -16, 0)
	sub:SetJustifyV("TOP")
	button.sub = sub
	return button
end

local function lede(parent, text)
	local fs = UI.text(parent, "sans", Stoa.typeSize.label, "muted")
	fs:SetWidth(BODY_W - 40)
	fs:SetJustifyV("TOP")
	fs:SetText(text)
	return fs
end

-- Steps ------------------------------------------------------------------------

local builders = {}

function builders.start(self, step)
	local hello = UI.text(step, "serif", Stoa.typeSize.display, "text")
	hello:SetPoint("TOPLEFT")
	hello:SetText("Welcome to Stoa")
	local words = lede(step, "A handful of choices and your screen is ready. Each can be changed later in settings, and /stoa welcome brings this back.")
	words:SetPoint("TOPLEFT", hello, "BOTTOMLEFT", 0, -10)
	step.top = 92
	step.cards = {}
	local options = {
		{ "guided", "Set it up with me", "Five short steps, about a minute." },
		{ "saved", "Use a saved setup", "Every character you play saves its setup when it logs out. Pick one to copy its frames, At a glance and combat rows." },
		{ "ships", "Start as Stoa ships", "Full, the theme you have now and your class's usual roles. Nothing else to choose." },
	}
	for _, option in ipairs(options) do
		local id = option[1]
		local button = card(step, BODY_W, id == "saved" and 62 or 54, option[2], function()
			self.start = id
			if id == "saved" and not self.setup and self.setups[1] then self.setup = self.setups[1].key end
			self:Refresh()
		end)
		button.sub:SetText(option[3])
		button.id = id
		step.cards[#step.cards + 1] = button
	end
	step.setupRows = {}
	for i = 1, MAX_SETUPS do
		local row = UI.button(step, "", BODY_W - 32, function(button)
			self.setup = button.key
			self:Refresh()
		end)
		row:SetHeight(28)
		row.text:ClearAllPoints()
		row.text:SetPoint("LEFT", 26, 0)
		row.text:SetJustifyH("LEFT")
		row.dot = UI.circle(row, "ARTWORK", 1, 8)
		row.dot:SetPoint("LEFT", 12, 0)
		row.what = UI.text(row, "sans", Stoa.typeSize.caption, "muted")
		row.what:SetPoint("LEFT", 170, 0)
		row.what:SetPoint("RIGHT", -12, 0)
		step.setupRows[i] = row
	end
end

function builders.specs(self, step)
	local words = lede(step, "Stoa lays out the screen for the role you play. Each spec keeps its own layout, combat rows and At a glance lines, and switches with your spec.")
	words:SetPoint("TOPLEFT")
	local width = math.floor((BODY_W - 3 * 8) / 4)
	self.roleRows = {}
	for slot = 1, 2 do
		local y = -64 - (slot - 1) * 66
		local label = UI.caption(step, slot == 1 and "First spec plays" or "Second spec plays")
		label:SetPoint("TOPLEFT", 0, y)
		local note = UI.caption(step, "")
		note:SetPoint("LEFT", label, "RIGHT", 0, 0)
		local row = { note = note, buttons = {} }
		for i, role in ipairs(Stoa.ROLES) do
			local button = UI.button(step, Stoa.ROLE_LABELS[role], width, function()
				Stoa:SetRoleForSlot(slot, role)
				self:Refresh()
			end)
			button:SetHeight(30)
			button:SetPoint("TOPLEFT", (i - 1) * (width + 8), y - 18)
			row.buttons[role] = button
		end
		self.roleRows[slot] = row
	end
	local hint = lede(step, "Healers get their group frames beside the Halo and click-casting; tanks get a threat word and their own combat rows.")
	hint:SetPoint("TOPLEFT", 0, -208)
	Stoa:SetFont(hint, "sans", Stoa.typeSize.body)
end

function builders.look(self, step)
	local label = UI.caption(step, "Theme")
	label:SetPoint("TOPLEFT")
	self.themeButtons = {}
	local wide = math.floor((BODY_W - 3 * 8) / 4)
	for i, name in ipairs(WELCOME_THEMES) do
		local button = UI.button(step, themeWord(name), wide, function()
			Stoa:SetTheme(name)
			self:Refresh()
		end)
		button:SetHeight(30)
		button:SetPoint("TOPLEFT", (i - 1) * (wide + 8), -18)
		self.themeButtons[name] = button
	end
	-- Every class theme, each with a dot of its own accent.
	local small = math.floor((BODY_W - 4 * 6) / 5)
	for i, name in ipairs(CLASS_THEME_ORDER) do
		local button = UI.button(step, name, small, function()
			Stoa:SetTheme(name)
			self:Refresh()
		end)
		local column, line = (i - 1) % 5, math.floor((i - 1) / 5)
		button:SetPoint("TOPLEFT", column * (small + 6), -56 - line * 32)
		local dot = UI.circle(button, "ARTWORK", 1, 8)
		dot:SetPoint("LEFT", 12, 0)
		local accent = Stoa.themes[name] and Stoa.themes[name].accent
		if accent then dot:SetColorTexture(accent[1], accent[2], accent[3], 1) end
		self.themeButtons[name] = button
	end
	local note = UI.text(step, "sans", Stoa.typeSize.caption, "muted")
	note:SetPoint("TOPLEFT", 0, -126)
	note:SetWidth(BODY_W)
	note:SetText("Your class follows whichever character you log in on; a named class keeps that theme on every character.")

	local ornament = UI.caption(step, "Ornament")
	ornament:SetPoint("TOPLEFT", 0, -156)
	self.ornamentCards = {}
	local half = math.floor((BODY_W - GAP) / 2)
	local ORNAMENTS = {
		{ "plain", "Plain", "Fine lines around the minimap and portrait coins." },
		{ "painted", "Painted", "Brass frames on the one-of-a-kind pieces." },
	}
	for i, entry in ipairs(ORNAMENTS) do
		local button = card(step, half, 50, entry[2], function()
			Stoa.db.ornament = entry[1]
			self:Refresh()
		end)
		button.sub:SetText(entry[3])
		button:SetPoint("TOPLEFT", (i - 1) * (half + GAP), -174)
		self.ornamentCards[entry[1]] = button
	end

	local vision = UI.caption(step, "Colour vision")
	vision:SetPoint("TOPLEFT", 0, -240)
	self.visionButtons = {}
	for i, name in ipairs(Stoa.visionOrder) do
		local button = UI.button(step, VISION_WORDS[name] or name, wide, function()
			Stoa:SetVision(name)
			self:Refresh()
		end)
		button:SetHeight(30)
		button:SetPoint("TOPLEFT", (i - 1) * (wide + 8), -258)
		self.visionButtons[name] = button
	end
	local visionNote = UI.text(step, "sans", Stoa.typeSize.caption, "muted")
	visionNote:SetPoint("TOPLEFT", 0, -296)
	visionNote:SetWidth(BODY_W)
	visionNote:SetText("Swaps only the colours that carry meaning (warnings, dispels, health), over any theme.")
end

function builders.combat(self, step)
	local label = UI.caption(step, "When a fight starts")
	label:SetPoint("TOPLEFT")
	step.top = 18
	step.cards = {}
	for _, id in ipairs(COMBAT_ORDER) do
		local button = card(step, BODY_W, 54, COMBAT_WORDS[id][1], function()
			setCombat(id)
			self:Refresh()
		end)
		button.sub:SetText(COMBAT_WORDS[id][2])
		button.id = id
		step.cards[#step.cards + 1] = button
	end
	-- Only folding has a way back to tune.
	local nested = CreateFrame("Frame", nil, step)
	nested:SetSize(BODY_W - 32, 68)
	local after = UI.text(nested, "sans", Stoa.typeSize.body, "text")
	after:SetPoint("TOPLEFT", 0, -7)
	after:SetText("Open again after")
	self.calmButtons = {}
	for i, seconds in ipairs(CALMS) do
		local button = UI.button(nested, seconds .. " s", 56, function()
			Stoa.db.calm = seconds
			self:Refresh()
		end)
		button:SetPoint("TOPLEFT", 130 + (i - 1) * 62, 0)
		self.calmButtons[seconds] = button
	end
	local group = UI.button(nested, "Wait for your group", 180, function()
		Stoa.db.calmGroup = not Stoa.db.calmGroup
		self:Refresh()
	end)
	group:SetPoint("TOPLEFT", 0, -36)
	local groupNote = UI.text(nested, "sans", Stoa.typeSize.caption, "muted")
	groupNote:SetPoint("LEFT", group, "RIGHT", 12, 0)
	groupNote:SetPoint("RIGHT", 0, 0)
	groupNote:SetText("Between pulls, stays folded while anyone near you still fights.")
	self.groupButton = group
	step.nested = nested
	local note = UI.text(step, "sans", Stoa.typeSize.body, "muted")
	note:SetWidth(BODY_W)
	note:SetJustifyV("TOP")
	step.note = note
end

function builders.preset(self, step)
	local words = lede(step, "How much Stoa does. Full is how it ships; the others say exactly what they take away.")
	words:SetPoint("TOPLEFT")
	self.presetCards = {}
	for i, name in ipairs(PRESET_ORDER) do
		local button = card(step, BODY_W, 70, PRESET_WORDS[name][1], function()
			self:ApplyPreset(name)
			self:Refresh()
		end)
		button.sub:SetText(PRESET_WORDS[name][2])
		button:SetPoint("TOPLEFT", 0, -48 - (i - 1) * (70 + GAP))
		self.presetCards[name] = button
	end
end

function builders.addons(self, step)
	local words = lede(step, "Stoa found these addons. Each keeps working; say who looks after what.")
	words:SetPoint("TOPLEFT")
	step.rows = {}
end

function builders.ready(self, step)
	local done = UI.text(step, "serif", Stoa.typeSize.display, "text")
	done:SetPoint("TOPLEFT")
	done:SetText("You're set")
	step.lines = {}
	local half = math.floor((BODY_W - 24) / 2)
	for i = 1, 10 do
		local column, line = (i - 1) % 2, math.floor((i - 1) / 2)
		local key = UI.text(step, "sans", Stoa.typeSize.body, "muted")
		key:SetPoint("TOPLEFT", column * (half + 24), -52 - line * 24)
		local value = UI.text(step, "sans", Stoa.typeSize.body, "text", "RIGHT")
		value:SetPoint("TOPRIGHT", step, "TOPLEFT", column * (half + 24) + half, -52 - line * 24)
		value:SetPoint("LEFT", key, "RIGHT", 8, 0)
		step.lines[i] = { key = key, value = value }
	end
	local try = UI.caption(step, "Try it before a real fight")
	try:SetPoint("TOPLEFT", 0, -186)
	local page = self.page
	local tries = {
		{ "Sample party", function() Stoa.commands.test("") end },
		{ "Practice combat", function() page:Hide(); Stoa.commands.combat("") end },
		{ "Move frames", function() page:Hide(); Stoa:ToggleMovers() end },
	}
	for i, entry in ipairs(tries) do
		local button = UI.button(step, entry[1], 140, entry[2])
		button:SetHeight(30)
		button:SetPoint("TOPLEFT", (i - 1) * 148, -204)
	end
	local reloadNote = UI.text(step, "sans", Stoa.typeSize.body, "muted")
	reloadNote:SetPoint("TOPLEFT", 0, -252)
	reloadNote:SetWidth(BODY_W)
	step.reloadNote = reloadNote
end

-- The window ---------------------------------------------------------------------

function Welcome:Build()
	local page = CreateFrame("Frame", "StoaWelcomePage", UIParent)
	page:SetSize(WIDTH, HEIGHT)
	page:SetPoint("CENTER", 0, 40)
	page:SetFrameStrata("DIALOG")
	page:EnableMouse(true)
	page:SetMovable(true)
	page:SetClampedToScreen(true)
	page:RegisterForDrag("LeftButton")
	page:SetScript("OnDragStart", page.StartMoving)
	page:SetScript("OnDragStop", page.StopMovingOrSizing)
	page:SetScript("OnHide", function() self:Closed() end)
	page:Hide()
	table.insert(UISpecialFrames, "StoaWelcomePage")
	UI.windowPanel(page, 0.97, { header = HEADER, footer = FOOTER })
	self.page = page

	-- The wordmark, in the theme's accent (white with alpha, 1024x256; the
	-- letters fill 4-1020 across and 32-224 down).
	local mark = page:CreateTexture(nil, "ARTWORK")
	mark:SetTexture(UI.MEDIA .. "Textures\\Wordmark")
	mark:SetSize(104, 26)
	mark:SetPoint("LEFT", page, "TOPLEFT", PAD - 1, -HEADER / 2)
	UI.tint(mark, "accent")
	local title = UI.text(page, "serif", Stoa.typeSize.title, "text")
	title:SetPoint("LEFT", mark, "RIGHT", 14, -1)
	self.title = title

	local skip = CreateFrame("Button", nil, page)
	skip:SetSize(200, 24)
	skip:SetPoint("RIGHT", page, "TOPRIGHT", -PAD + 4, -HEADER / 2)
	local skipText = UI.text(skip, "sans", Stoa.typeSize.body, "muted", "RIGHT")
	skipText:SetAllPoints()
	skipText:SetText("Skip, use what's chosen so far")
	skip:SetScript("OnEnter", function() skipText:SetTextColor(Stoa:Color("text")) end)
	skip:SetScript("OnLeave", function() skipText:SetTextColor(Stoa:Color("muted")) end)
	skip:SetScript("OnClick", function() self:Go("ready") end)
	self.skip = skip

	-- The step rail.
	local rule = page:CreateTexture(nil, "BORDER")
	rule:SetWidth(1)
	rule:SetPoint("TOPLEFT", RAIL, -HEADER)
	rule:SetPoint("BOTTOMLEFT", RAIL, FOOTER)
	UI.paint(rule, "hairline", 0.12)
	self.railRows = {}
	for i, id in ipairs(STEP_ORDER) do
		local row = CreateFrame("Button", nil, page)
		row:SetSize(RAIL - PAD, 30)
		row.dot = UI.circle(row, "ARTWORK", 1, 22)
		row.dot:SetPoint("LEFT")
		row.number = row:CreateFontString(nil, "OVERLAY")
		Stoa:SetFont(row.number, "sans", Stoa.typeSize.caption)
		row.number:SetPoint("CENTER", row.dot, "CENTER", 0, 0)
		row.name = row:CreateFontString(nil, "OVERLAY")
		Stoa:SetFont(row.name, "sans", Stoa.typeSize.body)
		row.name:SetPoint("LEFT", row.dot, "RIGHT", 10, 0)
		row.name:SetText(STEP_TITLES[id] == "Welcome" and "Start" or STEP_TITLES[id])
		row.id = id
		row:SetScript("OnClick", function() if self.seen[id] then self:Go(id) end end)
		self.railRows[id] = row
	end

	-- Each step's own frame.
	self.steps = {}
	for _, id in ipairs(STEP_ORDER) do
		local step = CreateFrame("Frame", nil, page)
		step:SetPoint("TOPLEFT", BODY_X, -BODY_TOP)
		step:SetSize(BODY_W, HEIGHT - BODY_TOP - FOOTER - 16)
		step:Hide()
		builders[id](self, step)
		self.steps[id] = step
	end

	local back = UI.button(page, "Back", 96, function() self:Move(-1) end)
	back:SetHeight(30)
	back:SetPoint("LEFT", page, "BOTTOMLEFT", PAD, FOOTER / 2)
	self.back = back
	local counter = UI.text(page, "sans", Stoa.typeSize.caption, "muted")
	counter:SetPoint("LEFT", back, "RIGHT", 14, 0)
	self.counter = counter
	local nextButton = UI.button(page, "Next", 150, function() self:Move(1) end)
	nextButton:SetHeight(30)
	nextButton:SetPoint("RIGHT", page, "BOTTOMRIGHT", -PAD, FOOTER / 2)
	self.next = nextButton

	UI.applyTheme()
end

-- The steps in play: Other addons only when Stoa found some.
function Welcome:Order()
	local list = {}
	for _, id in ipairs(STEP_ORDER) do
		if id ~= "addons" or #self.addonRows > 0 then list[#list + 1] = id end
	end
	return list
end

function Welcome:Go(id)
	self.current = id
	self.seen[id] = true
	self:Refresh()
end

function Welcome:Move(by)
	local order = self:Order()
	local index = 1
	for i, id in ipairs(order) do if id == self.current then index = i end end
	if by > 0 and self.current == "ready" then return self:Finish() end
	-- A saved setup or Stoa as it ships has nothing in between.
	if self.start ~= "guided" and (self.current == "start" or self.current == "ready") then
		return self:Go(by > 0 and "ready" or "start")
	end
	self:Go(order[math.max(1, math.min(#order, index + by))])
end

-- Other addons -----------------------------------------------------------------------
-- One row per job another addon shares with Stoa, and one per addon Stoa
-- can dress. A look for an addon that also shares a job joins that row
-- ("Bagnon, in Stoa's look").

local function lookFor(folder)
	if not Stoa.Looks then return nil end
	for _, look in ipairs(Stoa.Looks.list) do
		if look.folder == folder and Stoa.Looks:Ready(look) then return look end
	end
end

function Welcome:GatherAddons()
	local rows = {}
	local covered = {}
	for _, companion in ipairs(Stoa.Companions and Stoa.Companions:Loaded() or {}) do
		rows[#rows + 1] = { name = companion.name, note = "Works beside Stoa. Where both do a small job, its switch wins." }
	end
	local Conflicts = Stoa.Conflicts
	for _, entry in ipairs(Conflicts and Conflicts:Found() or {}) do
		if not entry.rule.suite then
			local them = Conflicts.names(entry.loaded)
			local look = #entry.loaded == 1 and lookFor(entry.loaded[1][1])
			local row = { name = them, note = "Both look after " .. entry.rule.job .. ".", entry = entry, look = look or nil, options = {} }
			if look then
				covered[look.key] = true
				row.options[1] = { "look", them .. ", in Stoa's look" }
				row.options[2] = { "theirs", them .. " as it is" }
			else
				row.options[1] = { "theirs", "Keep " .. them }
			end
			row.options[#row.options + 1] = { "ours", "Use Stoa's" }
			local saved = Conflicts:Saved(entry)
			if saved == "theirs" then
				row.choice = (look and Stoa.Looks:IsOn(look)) and "look" or "theirs"
			else
				row.choice = row.options[1][1]
			end
			rows[#rows + 1] = row
		end
	end
	for _, look in ipairs(Stoa.Looks and Stoa.Looks.list or {}) do
		if not covered[look.key] and Stoa.Looks:Ready(look) then
			rows[#rows + 1] = {
				name = look.name, note = "Stoa can dress " .. look.what .. " in its type and colours.", look = look,
				options = { { "look", "Stoa's look" }, { "theirs", "Leave it" } },
				choice = "look",
			}
		end
	end
	return rows
end

local ROW_HEIGHT = 66
local MAX_ADDON_ROWS = 4

function Welcome:BuildAddonRows()
	local step = self.steps.addons
	for _, frame in ipairs(step.rows) do frame:Hide() end
	for i, row in ipairs(self.addonRows) do
		if i > MAX_ADDON_ROWS then break end
		local frame = step.rows[i]
		if not frame then
			frame = CreateFrame("Frame", nil, step)
			frame:SetSize(BODY_W, ROW_HEIGHT - 8)
			frame:SetPoint("TOPLEFT", 0, -38 - (i - 1) * ROW_HEIGHT)
			UI.well(frame, 0)
			frame.name = UI.text(frame, "serif", Stoa.typeSize.label, "text")
			frame.name:SetPoint("TOPLEFT", 14, -9)
			frame.note = UI.text(frame, "sans", Stoa.typeSize.caption, "muted", "RIGHT")
			frame.note:SetPoint("TOPRIGHT", -14, -11)
			frame.note:SetPoint("LEFT", frame.name, "RIGHT", 12, 0)
			frame.buttons = {}
			step.rows[i] = frame
		end
		frame.name:SetText(row.name)
		frame.note:SetText(row.note)
		for _, button in ipairs(frame.buttons) do button:Hide() end
		local x = 14
		for j, option in ipairs(row.options or {}) do
			local button = frame.buttons[j]
			if not button then
				button = UI.button(frame, "", 100)
				frame.buttons[j] = button
			end
			button.text:SetText(option[2])
			local width = math.max(100, math.ceil(button.text:GetStringWidth()) + 28)
			button:SetWidth(width)
			button:ClearAllPoints()
			button:SetPoint("BOTTOMLEFT", x, 8)
			x = x + width + 8
			button:SetScript("OnClick", function()
				row.choice = option[1]
				self:Refresh()
			end)
			button:Show()
		end
		frame.row = row
		frame:Show()
	end
end

-- Applies the answers; true when one needs a reload.
function Welcome:SettleAddons()
	local reload = false
	for i, row in ipairs(self.addonRows) do
		if i > MAX_ADDON_ROWS then break end
		if row.entry then
			if Stoa.Conflicts:Settle(row.entry, row.choice == "ours" and "ours" or "theirs") then reload = true end
		end
		if row.look then
			Stoa.Looks:Set(row.look, row.choice == "look")
			row.look.offered = true
		end
	end
	return reload
end

-- Finishing ------------------------------------------------------------------------

function Welcome:NeedsReload()
	if self.start == "saved" and self.setup then return true end
	if self.applied then return true end
	if Stoa.db.ornament ~= self.opened.ornament then return true end
	local db = halo()
	if db and (db.enabled ~= false) ~= self.opened.halo then return true end
	for i, row in ipairs(self.addonRows) do
		if i <= MAX_ADDON_ROWS and row.entry and row.choice == "ours" then return true end
	end
	return false
end

function Welcome:Finish()
	local reload = self:NeedsReload()
	self:SettleAddons()
	self.finished = true
	Stoa.char.welcomed = true
	if self.start == "ships" then
		for slot = 1, 2 do Stoa:SetRoleForSlot(slot, "AUTO") end
		if (Stoa.db.preset or "full") ~= "full" then self:ApplyPreset("full"); reload = true end
	end
	if self.start == "saved" and self.setup and Stoa.Setups:Load(self.setup) then return end
	self.page:Hide()
	if reload then ReloadUI() end
end

-- Closed by Finish, Escape or a Try it button.
function Welcome:Closed()
	Stoa.char.welcomed = true
	if not self.finished and self:NeedsReload() and self.start ~= "saved" then
		Stoa:Print("Some of your choices take effect after /reload.")
	end
	-- Anything the page didn't settle is asked about now (Core/Conflicts.lua).
	if Stoa.Conflicts then C_Timer.After(1, function() Stoa.Conflicts:Next() end) end
end

-- Refresh ----------------------------------------------------------------------------

local function choose(map, chosen)
	for name, button in pairs(map) do button:SetSelected(name == chosen) end
end

function Welcome:RefreshStart(step)
	local y = step.top
	for _, button in ipairs(step.cards) do
		local shown = button.id ~= "saved" or #self.setups > 0
		button:SetShown(shown)
		if shown then
			button:ClearAllPoints()
			button:SetPoint("TOPLEFT", 0, -y)
			button:SetSelected(self.start == button.id)
			y = y + button:GetHeight() + GAP
			if button.id == "saved" then
				for i, row in ipairs(step.setupRows) do
					local entry = self.start == "saved" and self.setups[i]
					row:SetShown(entry and true or false)
					if entry then
						local setup = entry.setup
						local _, classFile = UnitClass("player")
						local same = setup.class == classFile
						row.key = entry.key
						row.text:SetText(setup.name or entry.key)
						local colour = setup.class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[setup.class]
						if colour then row.dot:SetColorTexture(colour.r, colour.g, colour.b, 1) else row.dot:SetColorTexture(Stoa:Color("muted")) end
						row.what:SetText(same and "Same class: everything, roles and click-casting too" or "Another class: frames, At a glance and spec settings; roles stay your own")
						row:ClearAllPoints()
						row:SetPoint("TOPLEFT", 16, -(y - GAP + 4))
						row:SetSelected(self.setup == entry.key)
						y = y + 32
					end
				end
				if self.start == "saved" then y = y + 6 end
			end
		end
	end
end

function Welcome:RefreshCombat(step)
	local choice = combatChoice()
	local y = step.top
	for _, button in ipairs(step.cards) do
		button:ClearAllPoints()
		button:SetPoint("TOPLEFT", 0, -y)
		button:SetSelected(button.id == choice)
		y = y + button:GetHeight() + GAP
		if button.id == "fold" then
			step.nested:SetShown(choice == "fold")
			if choice == "fold" then
				step.nested:ClearAllPoints()
				step.nested:SetPoint("TOPLEFT", 16, -(y - 2))
				y = y + step.nested:GetHeight() + 6
			end
		end
	end
	choose(self.calmButtons, Stoa.db.calm or "3")
	self.groupButton:SetSelected(Stoa.db.calmGroup ~= false)
	step.note:ClearAllPoints()
	step.note:SetPoint("TOPLEFT", 0, -(y + 4))
	local seconds = tonumber(Stoa.db.calm) or 3
	local words
	if choice == "fold" then
		words = ("After a fight the console opens again once things have been calm for %d %s%s"):format(seconds,
			seconds == 1 and "second" or "seconds", Stoa.db.calmGroup ~= false and " and your group has stopped fighting." or ".")
	elseif choice == "open" then
		words = "The console stays open through fights; the Halo comes and goes."
	else
		words = "Nothing changes when a fight starts."
	end
	local db = halo()
	if db and (db.enabled ~= false) ~= self.opened.halo then words = words .. " Turning the Halo on or off takes effect on Finish." end
	step.note:SetText(words)
end

function Welcome:Summary()
	local lines = {}
	local function add(key, value) lines[#lines + 1] = { key, value } end
	if self.start == "saved" and self.setup then
		local name = self.setup
		for _, entry in ipairs(self.setups) do if entry.key == self.setup then name = entry.setup.name or entry.key end end
		add("Setup", name .. "'s, loaded on Finish")
		add("Theme", themeWord(Stoa.db.theme or "Bone"))
		return lines
	end
	for slot = 1, 2 do
		local role = slotRole(slot)
		add(slot == 1 and "First spec" or "Second spec", Stoa.ROLE_LABELS[role] or role)
	end
	add("Theme", themeWord(Stoa.db.theme or "Bone"))
	add("Ornament", Stoa.db.ornament == "painted" and "Painted" or "Plain")
	add("Colour vision", VISION_WORDS[Stoa.db.vision or "Standard"] or "Standard")
	local choice = combatChoice()
	add("In combat", choice == "fold" and ("Fold, " .. (Stoa.db.calm or "3") .. " s" .. (Stoa.db.calmGroup ~= false and ", waits for group" or ""))
		or choice == "open" and "Console open, Halo" or "Console open, no Halo")
	add("How much", PRESET_WORDS[Stoa.db.preset or "full"][1])
	for i, row in ipairs(self.addonRows) do
		if i <= MAX_ADDON_ROWS and row.options and #lines < 10 then
			for _, option in ipairs(row.options) do
				if option[1] == row.choice then add(row.name, option[2]) end
			end
		end
	end
	return lines
end

function Welcome:Refresh()
	if not self.page then return end
	local current = self.current
	for id, step in pairs(self.steps) do step:SetShown(id == current) end
	self.title:SetText(STEP_TITLES[current])

	-- The rail: the current step filled in the accent, seen steps quiet, the
	-- rest faint.
	local order = self:Order()
	local y = -(HEADER + 22)
	for _, id in ipairs(STEP_ORDER) do self.railRows[id]:Hide() end
	for i, id in ipairs(order) do
		local row = self.railRows[id]
		row:ClearAllPoints()
		row:SetPoint("TOPLEFT", self.page, "TOPLEFT", PAD - 4, y)
		row.number:SetText(i)
		local r, g, b = Stoa:Color("text")
		if id == current then
			row.dot:SetColorTexture(Stoa:Color("accent"))
			row.number:SetTextColor(Stoa:Color("panel"))
			row.name:SetTextColor(r, g, b, 1)
		elseif self.seen[id] then
			row.dot:SetColorTexture(r, g, b, 0.16)
			row.number:SetTextColor(r, g, b, 1)
			row.name:SetTextColor(r, g, b, 1)
		else
			row.dot:SetColorTexture(r, g, b, 0.06)
			row.number:SetTextColor(Stoa:Color("muted"))
			row.name:SetTextColor(Stoa:Color("muted"))
		end
		row:Show()
		y = y - 34
	end

	local step = self.steps[current]
	if current == "start" then
		self:RefreshStart(step)
	elseif current == "specs" then
		for slot, row in ipairs(self.roleRows) do
			local role, isDefault = slotRole(slot)
			choose(row.buttons, role)
			row.note:SetText(isDefault and CLASS_DEFAULT_WORD or "")
		end
	elseif current == "look" then
		choose(self.themeButtons, Stoa.db.theme)
		choose(self.ornamentCards, Stoa.db.ornament == "painted" and "painted" or "plain")
		choose(self.visionButtons, Stoa.db.vision or "Standard")
	elseif current == "combat" then
		self:RefreshCombat(step)
	elseif current == "preset" then
		choose(self.presetCards, Stoa.db.preset or "full")
	elseif current == "addons" then
		for _, frame in ipairs(step.rows) do
			if frame:IsShown() and frame.row then
				for j, option in ipairs(frame.row.options or {}) do
					if frame.buttons[j] then frame.buttons[j]:SetSelected(option[1] == frame.row.choice) end
				end
			end
		end
	elseif current == "ready" then
		local lines = self:Summary()
		for i, line in ipairs(step.lines) do
			local entry = lines[i]
			line.key:SetText(entry and entry[1] or "")
			line.value:SetText(entry and entry[2] or "")
		end
		step.reloadNote:SetText(self:NeedsReload() and "Finish reloads the interface once, so every choice takes hold." or "Everything is already in place.")
	end

	-- Header and footer.
	self.skip:SetShown(current ~= "start" and current ~= "ready" and self.start == "guided")
	self.back:SetShown(current ~= "start")
	local index
	for i, id in ipairs(order) do if id == current then index = i end end
	local middle = #order - 2
	self.counter:SetText((current ~= "start" and current ~= "ready") and ("Step %d of %d"):format(index - 1, middle) or "")
	local word = "Next"
	if current == "ready" then
		word = self:NeedsReload() and "Finish and reload" or "Finish"
	elseif current == "start" and self.start ~= "guided" then
		word = "Continue"
	end
	self.next.text:SetText(word)
	self.next:SetWidth(math.max(120, math.ceil(self.next.text:GetStringWidth()) + 36))
	self.next:SetSelected(true)
end

function Welcome:Show()
	if InCombatLockdown() then
		Stoa:AfterCombat(function() Welcome:Show() end)
		return
	end
	if not self.page then self:Build() end
	local db = halo()
	self.opened = { ornament = Stoa.db.ornament, halo = not (db and db.enabled == false) }
	self.applied = nil
	self.finished = nil
	self.start = "guided"
	self.setups = Stoa.Setups and Stoa.Setups:List() or {}
	while #self.setups > MAX_SETUPS do table.remove(self.setups) end
	self.setup = nil
	self.addonRows = self:GatherAddons()
	self:BuildAddonRows()
	self.seen = {}
	self.current = "start"
	self.seen.start = true
	self:Refresh()
	self.page:Show()
end

-- Until this character has been through the page (or while it's open), it
-- asks about other addons itself.
function Welcome:Pending()
	if self.page and self.page:IsShown() then return true end
	return Stoa.char ~= nil and not Stoa.char.welcomed
end

Stoa.commands.welcome = function() Welcome:Show() end

Stoa:On("STOA_READY", function()
	if Stoa.char.welcomed then return end
	-- Let the world and the rest of the UI settle first.
	-- A companion's own welcome page (Core/Companions.lua) goes first.
	C_Timer.After(5, function()
		Stoa.Companions:AfterWelcomes(function() Welcome:Show() end)
	end)
end)

-- A theme picked here repaints the page at once.
Stoa:On("STOA_THEME_CHANGED", function()
	if Welcome.page and Welcome.page:IsShown() then Welcome:Refresh() end
end)

-- /stoa preset full|quiet|classic
Stoa.commands.preset = function(rest)
	local name = strtrim(rest or ""):lower()
	if name == "classic feel" then name = "classic" end
	if Welcome:ApplyPreset(name) then
		Stoa:Print(PRESET_WORDS[name][1] .. " set. Type /reload to finish.")
		if Welcome.page then Welcome:Refresh() end
	else
		Stoa:Print("Presets: full, quiet or classic. Now: " .. tostring(Stoa.db.preset or "none") .. ".")
	end
end
