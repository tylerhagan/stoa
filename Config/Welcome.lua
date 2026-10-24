-- Stoa: the welcome page.
-- Shown once per character, a few seconds into the first login, out of
-- combat: what each spec slot plays, the theme, and the ways to see the UI
-- before a real fight. /stoa welcome brings it back.
local _, ns = ...
local Stoa = ns.Stoa
local UI = Stoa.UI

local Welcome = {}
Stoa.Welcome = Welcome

local WIDTH, HEIGHT = 600, 484
local PAD = 28
local ROLE_WIDTH = 112
local CLASS_DEFAULT_WORD = "  (class default)"
local WELCOME_THEMES = { "Bone", "Tide", "Graphite", "Class" }

local function slotRole(slot)
	local chosen = Stoa.char.roles["slot" .. slot]
	if chosen and chosen ~= "AUTO" then return chosen, false end
	return Stoa:DefaultRole(), true
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
	UI.roundPanel(page, 0.97)
	self.page = page

	local title = UI.text(page, "serif", Stoa.typeSize.hero, "text")
	title:SetPoint("TOPLEFT", PAD, -PAD)
	title:SetText("Stoa")
	local lede = UI.text(page, "italic", Stoa.typeSize.label, "muted")
	lede:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -6)
	lede:SetText("Out of combat, the console. In combat, the Halo.")
	local rule = UI.line(page)
	rule:SetPoint("TOPLEFT", PAD, -104)
	rule:SetPoint("TOPRIGHT", -PAD, -104)

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

	-- Ways to see it all before a real fight.
	local tryLabel = UI.caption(page, "Try it")
	tryLabel:SetPoint("TOPLEFT", PAD, -368)
	local tries = {
		{ "Sample party", function() Stoa.commands.test("") end },
		{ "Practice combat", function() page:Hide(); Stoa.commands.combat("") end },
		{ "Settings", function() page:Hide(); Stoa:OpenSettings() end },
	}
	for i, entry in ipairs(tries) do
		local button = UI.button(page, entry[1], ROLE_WIDTH + 20, entry[2])
		button:SetPoint("TOPLEFT", PAD + (i - 1) * (ROLE_WIDTH + 28), -386)
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
