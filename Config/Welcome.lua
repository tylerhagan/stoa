-- Stoa: the welcome page.
-- Shown once per character, a few seconds into the first login, out of
-- combat: what each spec slot plays, the theme, and the ways to see the UI
-- before a real fight. /stoa welcome brings it back.
local _, ns = ...
local Stoa = ns.Stoa
local UI = Stoa.UI

local Welcome = {}
Stoa.Welcome = Welcome

local WIDTH, HEIGHT = 600, 566
local PAD = 28
local ROLE_WIDTH = 112
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
local PRESET_WORDS = {
	full = { "Full", "Everything on, as Stoa ships." },
	quiet = { "Quiet", "Fewer words: no unit details, quest line or At a glance." },
	classic = { "Classic feel", "Blizzard's look for windows, bags and tooltips." },
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

function Welcome:Build()
	local page = CreateFrame("Frame", "StoaWelcomePage", UIParent)
	page:SetSize(WIDTH, HEIGHT)
	page:SetPoint("CENTER", 0, 60)
	page:SetFrameStrata("DIALOG")
	page:EnableMouse(true)
	page:SetMovable(true)
	page:RegisterForDrag("LeftButton")
	page:SetScript("OnDragStart", page.StartMoving)
	page:SetScript("OnDragStop", page.StopMovingOrSizing)
	page:SetScript("OnHide", function() Stoa.char.welcomed = true end)
	page:Hide()
	table.insert(UISpecialFrames, "StoaWelcomePage")
	UI.windowPanel(page, 0.97, { header = 108, footer = 66 })
	self.page = page

	-- The wordmark, in the theme's accent (white with alpha, 1024x256; the
	-- letters fill 4-1020 across and 32-224 down).
	local title = page:CreateTexture(nil, "ARTWORK")
	title:SetTexture(UI.MEDIA .. "Textures\\Wordmark")
	title:SetSize(200, 50)
	title:SetPoint("TOPLEFT", PAD - 1, -PAD + 6)
	UI.tint(title, "accent")
	local lede = UI.text(page, "italic", Stoa.typeSize.label, "muted")
	lede:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 1, 0)
	lede:SetText("Out of combat, the console. In combat, the Halo.")

	-- What each spec slot plays. Layouts and signatures follow the role.
	self.roleRows = {}
	for slot = 1, 2 do
		local y = -124 - (slot - 1) * 58
		local label = UI.caption(page, slot == 1 and "First spec plays" or "Second spec plays")
		label:SetPoint("TOPLEFT", PAD, y)
		local note = UI.caption(page, "")
		note:SetPoint("LEFT", label, "RIGHT", 0, 0)
		local row = { note = note, buttons = {} }
		for i, role in ipairs(Stoa.ROLES) do
			local button = UI.button(page, Stoa.ROLE_LABELS[role], ROLE_WIDTH, function()
				Stoa:SetRoleForSlot(slot, role)
				self:Refresh()
			end)
			button:SetPoint("TOPLEFT", PAD + (i - 1) * (ROLE_WIDTH + 8), y - 18)
			row.buttons[role] = button
		end
		self.roleRows[slot] = row
	end

	local themeLabel = UI.caption(page, "Theme")
	themeLabel:SetPoint("TOPLEFT", PAD, -240)
	self.themeButtons = {}
	-- The house themes and your class's; every class theme is in settings.
	for i, name in ipairs(WELCOME_THEMES) do
		local button = UI.button(page, name == "Class" and "Your class" or name, ROLE_WIDTH, function()
			Stoa:SetTheme(name)
			self:Refresh()
		end)
		button:SetPoint("TOPLEFT", PAD + (i - 1) * (ROLE_WIDTH + 8), -258)
		self.themeButtons[name] = button
	end

	-- Colour vision, laid over whichever theme you pick.
	local visionLabel = UI.caption(page, "Colour vision")
	visionLabel:SetPoint("TOPLEFT", PAD, -304)
	self.visionButtons = {}
	local VISION_WORDS = { Standard = "Standard", RedGreen = "Red-green", BlueYellow = "Blue-yellow", NoColour = "No colour" }
	for i, name in ipairs(Stoa.visionOrder) do
		local button = UI.button(page, VISION_WORDS[name], ROLE_WIDTH, function()
			Stoa:SetVision(name)
			self:Refresh()
		end)
		button:SetPoint("TOPLEFT", PAD + (i - 1) * (ROLE_WIDTH + 8), -322)
		self.visionButtons[name] = button
	end

	-- Where to start: how much of Stoa to switch on.
	local startLabel = UI.caption(page, "Start from")
	startLabel:SetPoint("TOPLEFT", PAD, -368)
	self.presetButtons = {}
	for i, name in ipairs(PRESET_ORDER) do
		local button = UI.button(page, PRESET_WORDS[name][1], ROLE_WIDTH + 20, function()
			self:ApplyPreset(name)
			self:Refresh()
		end)
		button:SetPoint("TOPLEFT", PAD + (i - 1) * (ROLE_WIDTH + 28), -386)
		self.presetButtons[name] = button
	end
	local presetNote = UI.caption(page, "")
	presetNote:SetPoint("TOPLEFT", PAD, -418)
	presetNote:SetWidth(WIDTH - PAD * 2 - 130)
	presetNote:SetJustifyH("LEFT")
	self.presetNote = presetNote
	local reload = UI.button(page, "Reload now", 110, function() ReloadUI() end)
	reload:SetPoint("TOPRIGHT", -PAD, -414)
	reload:Hide()
	self.reloadButton = reload

	-- Ways to see it all before a real fight.
	local tryLabel = UI.caption(page, "Try it")
	tryLabel:SetPoint("TOPLEFT", PAD, -452)
	local tries = {
		{ "Sample party", function() Stoa.commands.test("") end },
		{ "Practice combat", function() page:Hide(); Stoa.commands.combat("") end },
		{ "Settings", function() page:Hide(); Stoa:OpenSettings() end },
	}
	for i, entry in ipairs(tries) do
		local button = UI.button(page, entry[1], ROLE_WIDTH + 20, entry[2])
		button:SetPoint("TOPLEFT", PAD + (i - 1) * (ROLE_WIDTH + 28), -470)
	end

	local done = UI.button(page, "Done", 96, function() page:Hide() end)
	done:SetPoint("BOTTOMRIGHT", -PAD, PAD - 8)
	local foot = UI.text(page, "sans", Stoa.typeSize.caption, "muted", "LEFT")
	foot:SetPoint("BOTTOMLEFT", PAD, PAD)
	foot:SetPoint("RIGHT", done, "LEFT", -16, 0)
	foot:SetText("/stoa welcome brings this back. If a skin ever breaks Blizzard's UI, /stoa safe turns them off.")

	UI.applyTheme()
end

function Welcome:Refresh()
	for slot, row in ipairs(self.roleRows) do
		local role, isDefault = slotRole(slot)
		for name, button in pairs(row.buttons) do button:SetSelected(name == role) end
		row.note:SetText(isDefault and CLASS_DEFAULT_WORD or "")
	end
	local theme = Stoa.db.theme
	for name, button in pairs(self.themeButtons) do button:SetSelected(name == theme) end
	local vision = Stoa.db.vision or "Standard"
	for name, button in pairs(self.visionButtons) do button:SetSelected(name == vision) end
	local preset = Stoa.db.preset
	for name, button in pairs(self.presetButtons) do button:SetSelected(name == preset) end
	if self.applied and PRESET_WORDS[self.applied] then
		self.presetNote:SetText(PRESET_WORDS[self.applied][2] .. " Reload to finish.")
		self.reloadButton:Show()
	else
		self.presetNote:SetText("Pick one to set the lot at once. You can change anything later in settings.")
		self.reloadButton:Hide()
	end
end

function Welcome:Show()
	if InCombatLockdown() then
		Stoa:AfterCombat(function() Welcome:Show() end)
		return
	end
	if not self.page then self:Build() end
	self:Refresh()
	self.page:Show()
end

Stoa.commands.welcome = function() Welcome:Show() end

Stoa:On("STOA_READY", function()
	if Stoa.char.welcomed then return end
	-- Let the world and the rest of the UI settle first.
	C_Timer.After(4, function() Welcome:Show() end)
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
