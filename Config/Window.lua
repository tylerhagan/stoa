-- Stoa: the settings window. Pages down the left, the settings of one page
-- (or the search's finds) in the middle, and on the right what the setting
-- under the mouse does, whether it waits for a reload, where it's kept and
-- the /stoa words for it. Everything it shows comes from Config/Options.lua.
local _, ns = ...
local Stoa = ns.Stoa
local UI = Stoa.UI
local Options = Stoa.Options

local Window = {}
Stoa.SettingsWindow = Window

local WIDTH, HEIGHT = 960, 640
local HEADER, FOOTER = 60, 50
local NAV, DETAIL = 170, 236
local PAD = 20
local CONTENT = WIDTH - NAV - DETAIL - PAD * 4
local INLINE = 210 -- the widest control that sits beside a setting's name
local ROW_GAP = 6

local current = "look"
local query
local rows = {}

local function colour(region, token, alpha)
	local r, g, b, a = Stoa:Color(token)
	if region.SetTextColor and not region.SetVertexColor then
		region:SetTextColor(r, g, b, alpha or a)
	else
		region:SetVertexColor(r, g, b, alpha or a)
	end
end

local function width(fs, fallback)
	local w = tonumber(fs:GetStringWidth())
	return w and w > 0 and w or fallback
end

local function labelOf(entry, v)
	for _, option in ipairs(entry.options or {}) do
		if option[1] == v then return option[2] end
	end
	return tostring(v)
end

-- Hovering a row, or anything in it, tells the notes column.
local function hover(frame, entry)
	frame:HookScript("OnEnter", function() Window:Describe(entry) end)
	frame:HookScript("OnLeave", function() Window:Describe(nil) end)
end

-- Controls ---------------------------------------------------------------------

local function makeToggle(parent, entry)
	local button = CreateFrame("Button", nil, parent)
	button:SetSize(38, 20)
	local fill = UI.pillFill(button, 0)
	local edge = UI.pillEdge(button, 0)
	local knob = UI.circle(button, "ARTWORK", 1, 14)
	function button:Refresh()
		local on = Options.value(entry) and true or false
		colour(fill, on and "accent" or "text", on and 0.85 or 0.1)
		if on then edge:Clear() else edge:Set(Stoa:Color("hairline")) end
		colour(knob, on and "panel" or "muted", 1)
		knob:ClearAllPoints()
		knob:SetPoint(on and "RIGHT" or "LEFT", on and -3 or 3, 0)
	end
	button:SetScript("OnClick", function()
		Options.set(entry, not Options.value(entry))
	end)
	hover(button, entry)
	return button
end

-- A row of choices; the chosen one is lifted and lit.
local function makeSegments(parent, entry)
	local holder = CreateFrame("Frame", nil, parent)
	local back = UI.pillFill(holder, 0)
	back:SetVertexColor(0, 0, 0, 0.35)
	local edge = UI.pillEdge(holder, 0)
	holder.buttons = {}
	local x = 2
	for i, option in ipairs(entry.options) do
		local button = CreateFrame("Button", nil, holder)
		local text = UI.text(button, "sans", Stoa.typeSize.body, "muted", "CENTER")
		text:SetPoint("CENTER")
		text:SetText(option[2])
		local w = math.floor(width(text, #option[2] * 7) + 22)
		button:SetSize(w, 22)
		button:SetPoint("LEFT", x, 0)
		x = x + w + 2
		button.lift = UI.pillFill(button, 0)
		button.edge = UI.pillEdge(button, 0)
		button.text, button.value = text, option[1]
		button:SetScript("OnClick", function() Options.set(entry, option[1]) end)
		button:SetScript("OnEnter", function(self) if not self.chosen then colour(self.text, "text") end end)
		button:SetScript("OnLeave", function(self) if not self.chosen then colour(self.text, "muted") end end)
		hover(button, entry)
		holder.buttons[i] = button
	end
	holder:SetSize(x, 26)
	function holder:Refresh()
		edge:Set(Stoa:Color("hairline"))
		local v = Options.value(entry)
		for _, button in ipairs(self.buttons) do
			button.chosen = button.value == v
			button.lift:SetShown(button.chosen)
			colour(button.lift, "text", 0.12)
			if button.chosen then button.edge:Set(Stoa:Color("accent")) else button.edge:Clear() end
			colour(button.text, button.chosen and "accent" or "muted")
		end
	end
	return holder
end

-- One shared list for every dropdown, drawn in the theme.
local menu

local function themeSwatch(name)
	if name == "Class" then
		local saved = Stoa.db.theme
		Stoa.db.theme = "Class"
		local resolved = Stoa:ThemeName()
		Stoa.db.theme = saved
		name = resolved
	end
	local theme = Stoa.themes[name]
	return theme and theme.accent
end

local function closeMenu()
	if menu then
		menu:Hide()
		menu.catcher:Hide()
	end
end

local function buildMenu()
	menu = CreateFrame("Frame", "StoaSettingsMenu", UIParent)
	menu:SetFrameStrata("FULLSCREEN_DIALOG")
	menu:SetFrameLevel(20)
	menu:SetClampedToScreen(true)
	menu:EnableMouse(true)
	UI.roundPanel(menu, 0.98)
	menu:Hide()
	local catcher = CreateFrame("Button", nil, UIParent)
	catcher:SetAllPoints(UIParent)
	catcher:SetFrameStrata("FULLSCREEN_DIALOG")
	catcher:SetFrameLevel(10)
	catcher:SetScript("OnClick", closeMenu)
	catcher:Hide()
	menu.catcher = catcher
	menu.rows = {}
	menu:EnableKeyboard(true)
	menu:SetScript("OnKeyDown", function(self, key)
		local handled = key == "UP" or key == "DOWN" or key == "ENTER" or key == "ESCAPE"
		self:SetPropagateKeyboardInput(not handled)
		if key == "ESCAPE" then closeMenu() return end
		local count = #self.entry.options
		if key == "UP" then self.focus = (self.focus - 2) % count + 1 end
		if key == "DOWN" then self.focus = self.focus % count + 1 end
		if key == "ENTER" then
			Options.set(self.entry, self.entry.options[self.focus][1])
			closeMenu()
			return
		end
		self:Paint()
	end)
	function menu:Paint()
		local v = Options.value(self.entry)
		for i, row in ipairs(self.rows) do
			if row:IsShown() then
				local chosen = row.value == v
				colour(row.text, chosen and "accent" or "text")
				row.dot:SetShown(chosen)
				colour(row.dot, "accent")
				row.glow:SetShown(i == self.focus)
				colour(row.glow, "text", 0.08)
			end
		end
	end
end

local function openMenu(owner, entry)
	if not menu then buildMenu() end
	if menu:IsShown() and menu.entry == entry then closeMenu() return end
	menu.entry = entry
	local v = Options.value(entry)
	local listWidth = math.max(owner:GetWidth(), 180)
	for i, option in ipairs(entry.options) do
		local row = menu.rows[i]
		if not row then
			row = CreateFrame("Button", nil, menu)
			row:SetHeight(24)
			row.glow = row:CreateTexture(nil, "BACKGROUND")
			row.glow:SetTexture(UI.WHITE)
			row.glow:SetPoint("TOPLEFT", 4, 0)
			row.glow:SetPoint("BOTTOMRIGHT", -4, 0)
			row.swatch = UI.circle(row, "ARTWORK", 1, 10)
			row.swatch:SetPoint("LEFT", 12, 0)
			row.text = UI.text(row, "sans", Stoa.typeSize.body, "text")
			row.dot = UI.circle(row, "ARTWORK", 1, 6)
			row.dot:SetPoint("RIGHT", -12, 0)
			row:SetScript("OnEnter", function(self) menu.focus = self.index menu:Paint() end)
			row:SetScript("OnClick", function(self)
				Options.set(menu.entry, self.value)
				closeMenu()
			end)
			menu.rows[i] = row
		end
		row.index, row.value = i, option[1]
		row:ClearAllPoints()
		row:SetPoint("TOPLEFT", 0, -6 - (i - 1) * 24)
		row:SetPoint("RIGHT")
		local swatch = option.swatch and themeSwatch(option.swatch)
		row.swatch:SetShown(swatch and true or false)
		if swatch then row.swatch:SetVertexColor(swatch[1], swatch[2], swatch[3], 1) end
		row.text:ClearAllPoints()
		row.text:SetPoint("LEFT", swatch and 30 or 12, 0)
		row.text:SetText(option[2])
		row:Show()
		if option[1] == v then menu.focus = i end
	end
	for i = #entry.options + 1, #menu.rows do menu.rows[i]:Hide() end
	menu.focus = menu.focus and math.min(menu.focus, #entry.options) or 1
	menu:SetSize(listWidth, #entry.options * 24 + 12)
	menu:ClearAllPoints()
	menu:SetPoint("TOPRIGHT", owner, "BOTTOMRIGHT", 0, -4)
	menu:Paint()
	menu.catcher:Show()
	menu:Show()
end

local function makeSelect(parent, entry)
	local button = UI.button(parent, "", INLINE, function(self) openMenu(self, entry) end)
	button.text:ClearAllPoints()
	button.text:SetPoint("LEFT", 12, 0)
	button.text:SetPoint("RIGHT", -28, 0)
	button.text:SetJustifyH("LEFT")
	local swatch = UI.circle(button, "ARTWORK", 1, 10)
	local caret = UI.text(button, "sans", Stoa.typeSize.caption, "muted", "RIGHT")
	caret:SetPoint("RIGHT", -12, 0)
	caret:SetText("v")
	function button:Refresh()
		local v = Options.value(entry)
		local accent
		for _, option in ipairs(entry.options) do
			if option[1] == v and option.swatch then accent = themeSwatch(option.swatch) end
		end
		swatch:SetShown(accent and true or false)
		if accent then
			swatch:SetPoint("LEFT", 12, 0)
			swatch:SetVertexColor(accent[1], accent[2], accent[3], 1)
			self.text:SetPoint("LEFT", 30, 0)
		else
			self.text:SetPoint("LEFT", 12, 0)
		end
		self.text:SetText(labelOf(entry, v))
		colour(caret, "muted")
	end
	hover(button, entry)
	return button
end

-- A small square to tick, with a filled centre when ticked.
local function makeTick(parent)
	local tick = CreateFrame("Button", nil, parent)
	tick:SetSize(14, 14)
	local edge = UI.border(tick, 1)
	local fill = tick:CreateTexture(nil, "ARTWORK")
	fill:SetTexture(UI.WHITE)
	fill:SetPoint("TOPLEFT", 3, -3)
	fill:SetPoint("BOTTOMRIGHT", -3, 3)
	function tick:SetTicked(on)
		edge:Set(Stoa:Color(on and "accent" or "muted"))
		fill:SetShown(on and true or false)
		colour(fill, "accent")
	end
	return tick
end

-- A line of text with a box, used by the lists below.
local function makeLine(parent, entry)
	local line = CreateFrame("Button", nil, parent)
	line:SetHeight(22)
	line.tick = makeTick(line)
	line.tick:SetPoint("LEFT", 0, 0)
	line.tick:EnableMouse(false)
	line.text = UI.text(line, "sans", Stoa.typeSize.body, "text")
	line.text:SetPoint("LEFT", 22, 0)
	line.text:SetPoint("RIGHT", -34, 0)
	line.text:SetWordWrap(false)
	hover(line, entry)
	return line
end

-- Rows ------------------------------------------------------------------------

local function flagsOf(entry)
	local out = {}
	if entry.reload then out[#out + 1] = "RELOAD" end
	if entry.game then out[#out + 1] = "GAME SETTING" end
	if entry.scope then out[#out + 1] = entry.scope:upper() end
	if entry.needs then out[#out + 1] = "ADDON" end
	return table.concat(out, " · ")
end

local function rowBase(entry)
	local row = CreateFrame("Frame", nil, Window.child)
	row:EnableMouse(true)
	row.entry = entry
	row.name = UI.text(row, "sans", Stoa.typeSize.label, "text")
	row.name:SetPoint("TOPLEFT", 0, -6)
	row.name:SetText(entry.name)
	row.name:SetWordWrap(true)
	row.flags = UI.text(row, "sans", Stoa.typeSize.caption, "muted")
	row.flags:SetPoint("TOPLEFT", row.name, "BOTTOMLEFT", 0, -3)
	row.flags:SetText(flagsOf(entry))
	hover(row, entry)
	return row
end

-- The space a row's words take, to know where its own controls start.
local function nameHeight(row, nameWidth)
	row.name:SetWidth(nameWidth)
	local h = (tonumber(row.name:GetStringHeight()) or 16) + 6
	if row.flags:GetText() ~= "" then h = h + 15 end
	return math.max(h, 26)
end

local builders = {}

function builders.toggle(row, entry)
	row.control = makeToggle(row, entry)
	row.control:SetPoint("TOPRIGHT", 0, -6)
	function row:Layout(w) return nameHeight(self, w - 60) + 4 end
end

function builders.choice(row, entry)
	local seg = not entry.list and makeSegments(row, entry)
	if seg and seg:GetWidth() > CONTENT - 40 then
		seg:Hide()
		seg = nil
	end
	row.control = seg or makeSelect(row, entry)
	local inline = row.control:GetWidth() <= INLINE + 2
	function row:Layout(w)
		self.control:ClearAllPoints()
		if inline then
			self.control:SetPoint("TOPRIGHT", 0, -4)
			return math.max(nameHeight(self, w - self.control:GetWidth() - 16), 34) + 2
		end
		local h = nameHeight(self, w)
		self.control:SetPoint("TOPLEFT", 0, -h - 4)
		return h + 34
	end
end

function builders.button(row, entry)
	local button
	button = UI.button(row, entry.label, 120, function(self)
		if entry.confirm and not button.armed then
			button.armed = true
			self.text:SetText("Sure?")
			C_Timer.After(3, function()
				button.armed = nil
				button.text:SetText(entry.label)
			end)
			return
		end
		button.armed = nil
		self.text:SetText(entry.label)
		xpcall(entry.run, Stoa.catch, self)
	end)
	row.control = button
	button:SetPoint("TOPRIGHT", 0, -4)
	hover(button, entry)
	function row:Layout(w) return math.max(nameHeight(self, w - 136), 34) + 2 end
end

function builders.actions(row, entry)
	row.buttons = {}
	for i, action in ipairs(entry.actions) do
		local probe = UI.text(row, "sans", Stoa.typeSize.body, "text")
		probe:SetText(action[1])
		local w = math.floor(width(probe, #action[1] * 7) + 28)
		probe:Hide()
		local button
		button = UI.button(row, action[1], w, function(self)
			if action.confirm and not button.armed then
				button.armed = true
				self.text:SetText("Sure?")
				C_Timer.After(3, function()
					button.armed = nil
					button.text:SetText(action[1])
				end)
				return
			end
			button.armed = nil
			self.text:SetText(action[1])
			xpcall(action[2], Stoa.catch)
			Window:Say(action[1] .. ": done.")
		end)
		hover(button, entry)
		row.buttons[i] = button
	end
	function row:Layout(w)
		local h = nameHeight(self, w)
		local x, y = 0, -h - 4
		for _, button in ipairs(self.buttons) do
			if x > 0 and x + button:GetWidth() > w then x, y = 0, y - 32 end
			button:ClearAllPoints()
			button:SetPoint("TOPLEFT", x, y)
			x = x + button:GetWidth() + 8
		end
		return -y + 32
	end
end

-- Chips you can take away, and a box to add one.
function builders.words(row, entry)
	row.chips = {}
	local box = CreateFrame("EditBox", nil, row)
	box:SetAutoFocus(false)
	box:SetSize(220, 24)
	box:SetMaxLetters(60)
	box:SetTextInsets(10, 10, 0, 0)
	Stoa:SetFont(box, "sans", Stoa.typeSize.body)
	box:SetTextColor(Stoa:Color("text"))
	local back = UI.pillFill(box, 0)
	back:SetVertexColor(0, 0, 0, 0.4)
	local edge = UI.pillEdge(box, 0)
	local hint = UI.text(box, "sans", Stoa.typeSize.body, "muted")
	hint:SetPoint("LEFT", 10, 0)
	hint:SetText(entry.placeholder or "Type, then Enter")
	local said = UI.text(row, "sans", Stoa.typeSize.caption, "muted")
	said:SetPoint("LEFT", box, "RIGHT", 10, 0)
	said:SetPoint("RIGHT", row, "RIGHT")
	local function paintBox()
		hint:SetShown(box:GetText() == "" and not box:HasFocus())
		edge:Set(Stoa:Color(box:HasFocus() and "accent" or "hairline"))
	end
	local function take(text)
		text = strtrim(text or "")
		if text == "" then return end
		local ok, why = entry.add(text)
		said:SetText(ok and "" or (why or "Couldn't add that."))
		colour(said, ok and "muted" or "danger")
		box:SetText("")
		Stoa:Fire("STOA_OPTION_CHANGED", entry.id)
	end
	box:SetScript("OnEnterPressed", function(self) take(self:GetText()) end)
	box:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
	box:SetScript("OnEditFocusGained", paintBox)
	box:SetScript("OnEditFocusLost", paintBox)
	box:SetScript("OnTextChanged", paintBox)
	hover(box, entry)
	row.box, row.paintBox = box, paintBox
	-- Shift-click an item while the box is in use adds it straight away.
	if entry.links and hooksecurefunc and ChatEdit_InsertLink then
		hooksecurefunc("ChatEdit_InsertLink", function(link)
			if box:HasFocus() and type(link) == "string" then take(link) end
		end)
	end
	function row:Layout(w)
		local h = nameHeight(self, w)
		local items = entry.items()
		local x, y = 0, -h - 4
		for i, item in ipairs(items) do
			local chip = self.chips[i]
			if not chip then
				chip = CreateFrame("Button", nil, self)
				chip:SetHeight(22)
				chip.fill = UI.pillFill(chip, 0)
				chip.edge = UI.pillEdge(chip, 0)
				chip.text = UI.text(chip, "sans", Stoa.typeSize.body, "text")
				chip.text:SetPoint("LEFT", 10, 0)
				chip.cross = UI.text(chip, "sans", Stoa.typeSize.body, "muted")
				chip.cross:SetPoint("RIGHT", -8, 0)
				chip.cross:SetText("×")
				chip:SetScript("OnClick", function(c)
					entry.remove(c.value)
					Stoa:Fire("STOA_OPTION_CHANGED", entry.id)
				end)
				chip:SetScript("OnEnter", function(c) colour(c.cross, "danger") Window:Describe(entry, "Click a word to take it off.") end)
				chip:SetScript("OnLeave", function(c) colour(c.cross, "muted") Window:Describe(nil) end)
				self.chips[i] = chip
			end
			chip.value = item[1]
			chip.text:SetText(item[2])
			colour(chip.fill, "text", 0.08)
			chip.edge:Set(Stoa:Color("hairline"))
			local cw = math.floor(width(chip.text, #item[2] * 7) + 34)
			chip:SetWidth(cw)
			if x > 0 and x + cw > w then x, y = 0, y - 28 end
			chip:ClearAllPoints()
			chip:SetPoint("TOPLEFT", x, y)
			chip:Show()
			x = x + cw + 6
		end
		for i = #items + 1, #self.chips do self.chips[i]:Hide() end
		if #items > 0 then y = y - 30 end
		box:ClearAllPoints()
		box:SetPoint("TOPLEFT", 0, y)
		paintBox()
		return -y + 32
	end
end

-- A list of ticks (the minimap icons kept out of the tray).
function builders.checks(row, entry)
	row.lines = {}
	row.empty = UI.text(row, "sans", Stoa.typeSize.body, "muted")
	row.empty:SetText(entry.empty or "")
	function row:Layout(w)
		local h = nameHeight(self, w)
		local items = entry.items()
		local half = math.floor((w - 12) / 2)
		for i, item in ipairs(items) do
			local line = self.lines[i]
			if not line then
				line = makeLine(self, entry)
				line:SetScript("OnClick", function(l)
					entry.toggle(l.value, not entry.checked(l.value))
					Stoa:Fire("STOA_OPTION_CHANGED", entry.id)
				end)
				self.lines[i] = line
			end
			line.value = item[1]
			line.text:SetText(item[2])
			line.tick:SetTicked(entry.checked(item[1]))
			line:SetWidth(half)
			line:ClearAllPoints()
			line:SetPoint("TOPLEFT", ((i - 1) % 2) * (half + 12), -h - 4 - math.floor((i - 1) / 2) * 24)
			line:Show()
		end
		for i = #items + 1, #self.lines do self.lines[i]:Hide() end
		self.empty:SetShown(#items == 0)
		self.empty:ClearAllPoints()
		self.empty:SetPoint("TOPLEFT", 0, -h - 6)
		return h + 8 + math.max(1, math.ceil(#items / 2)) * 24
	end
end

-- At a glance: the place to edit, then every line it can show with a tick
-- and a pin.
local glancePlace
function builders.glance(row, entry)
	local tally = Stoa.modules.Tally
	row.lines = {}
	row.places = makeSegments(row, {
		id = "glancePlace", name = "Which place", group = "At a glance", desc = "Each place keeps its own lines. Choose one to change its lines here.", options = { { "world", "In the world" }, { "dungeon", "In a dungeon" }, { "raid", "In a raid" } },
		get = function() return glancePlace or tally:Situation() end,
		set = function(v) glancePlace = v end,
	})
	-- The place row isn't a setting: choosing only changes what's edited.
	for _, button in ipairs(row.places.buttons) do
		button:SetScript("OnClick", function(b)
			glancePlace = b.value
			Window:Draw(true)
		end)
	end
	row.places:SetScript("OnShow", nil)
	row.count = UI.text(row, "sans", Stoa.typeSize.caption, "muted", "RIGHT")
	row.reset = UI.button(row, "Back to the usual lines", 170, function()
		tally:Reset(tally.db.follow and (glancePlace or tally:Situation()) or nil)
		Window:Draw(true)
	end)
	row.headers = {}
	function row:Layout(w)
		local h = nameHeight(self, w)
		local follow = tally.db.follow
		local place = follow and (glancePlace or tally:Situation()) or "world"
		local y = -h - 4
		self.places:SetShown(follow and true or false)
		if follow then
			self.places:ClearAllPoints()
			self.places:SetPoint("TOPLEFT", 0, y)
			self.places.Refresh(self.places)
			for _, button in ipairs(self.places.buttons) do
				button.chosen = button.value == place
				button.lift:SetShown(button.chosen)
				if button.chosen then button.edge:Set(Stoa:Color("accent")) else button.edge:Clear() end
				colour(button.text, button.chosen and "accent" or "muted")
			end
			y = y - 34
		end
		local own, pins = 0, tally:Pins()
		for _ in ipairs(tally:Own(place)) do own = own + 1 end
		self.count:ClearAllPoints()
		self.count:SetPoint("TOPRIGHT", 0, -h - (follow and 10 or 4))
		self.count:SetText(("%d of %d shown"):format(math.min(own + #pins, tally.MAX_ROWS), tally.MAX_ROWS))
		local half = math.floor((w - 12) / 2)
		local lastGroup, n, col = nil, 0, 0
		local headerIndex = 0
		for _, choice in ipairs(tally:Choices()) do
			if choice[3] ~= lastGroup then
				lastGroup = choice[3]
				if col == 1 then y = y - 24 col = 0 end
				headerIndex = headerIndex + 1
				local header = self.headers[headerIndex]
				if not header then
					header = UI.text(self, "sans", Stoa.typeSize.caption, "muted")
					self.headers[headerIndex] = header
				end
				header:SetText(choice[3]:upper())
				header:ClearAllPoints()
				header:SetPoint("TOPLEFT", 0, y - 6)
				header:Show()
				y = y - 24
			end
			n = n + 1
			local line = self.lines[n]
			if not line then
				line = makeLine(self, entry)
				line.pin = CreateFrame("Button", nil, line)
				line.pin:SetSize(32, 18)
				line.pin:SetPoint("RIGHT")
				line.pin.text = UI.text(line.pin, "sans", Stoa.typeSize.caption, "muted", "RIGHT")
				line.pin.text:SetPoint("RIGHT")
				line.pin.text:SetText("PIN")
				line.pin:SetScript("OnClick", function(p)
					tally:Pin(p:GetParent().value)
					Window:Draw(true)
				end)
				line.pin:SetScript("OnEnter", function() Window:Describe(entry, "A pinned line shows in every place, at the top.") end)
				line.pin:SetScript("OnLeave", function() Window:Describe(nil) end)
				line:SetScript("OnClick", function(l)
					tally:Toggle(l.value, tally.db.follow and (glancePlace or tally:Situation()) or nil)
					Window:Draw(true)
				end)
				self.lines[n] = line
			end
			line.value = choice[1]
			line.text:SetText(choice[2])
			line.tick:SetTicked(tally:Has(choice[1], place))
			local pinned = tally:IsPinned(choice[1])
			colour(line.pin.text, pinned and "accent" or "muted", pinned and 1 or 0.6)
			line:SetWidth(half)
			line:ClearAllPoints()
			line:SetPoint("TOPLEFT", col * (half + 12), y)
			line:Show()
			if col == 1 then y = y - 24 end
			col = 1 - col
		end
		if col == 1 then y = y - 24 end
		for i = n + 1, #self.lines do self.lines[i]:Hide() end
		for i = headerIndex + 1, #self.headers do self.headers[i]:Hide() end
		self.reset:ClearAllPoints()
		self.reset:SetPoint("TOPLEFT", 0, y - 6)
		return -y + 40
	end
end

function Window.rowFor(entry)
	if rows[entry.id] then return rows[entry.id] end
	local row = rowBase(entry)
	builders[entry.kind](row, entry)
	rows[entry.id] = row
	return row
end

-- Drawing ---------------------------------------------------------------------

local headers = {}
local headerCount = 0

local function groupHeader(text, y)
	headerCount = headerCount + 1
	local header = headers[headerCount]
	if not header then
		header = CreateFrame("Frame", nil, Window.child)
		header:SetHeight(20)
		header.text = UI.caption(header, "")
		header.text:SetPoint("LEFT")
		header.rule = UI.line(header, "hairline")
		header.rule:SetPoint("LEFT", header.text, "RIGHT", 10, 0)
		header.rule:SetPoint("RIGHT")
		headers[headerCount] = header
	end
	header.text:SetText(text:upper())
	header:ClearAllPoints()
	header:SetPoint("TOPLEFT", 0, y)
	header:SetPoint("RIGHT", Window.child, "RIGHT")
	header:Show()
	return y - 26
end

-- `keep` holds the scroll where it is, for a change made on the page.
function Window:Draw(keep)
	if not self.page then return end
	local was = keep and self.scroll:GetVerticalScroll() or 0
	headerCount = 0
	for _, row in pairs(rows) do row:Hide() end
	local list, title, intro
	if query then
		list = Options.search(query) or {}
		title = #list == 0 and "Nothing found" or ("%d found"):format(#list)
		intro = #list == 0 and ("No setting mentions \"%s\". Try a plainer word, such as bags, chat or camera."):format(query)
			or ("Settings that mention \"%s\", from every page."):format(query)
	else
		list = Options.onPage(current)
		for _, page in ipairs(Options.PAGES) do
			if page[1] == current then title, intro = page[2], page[3] end
		end
	end
	if not keep then self.scroll:SetVerticalScroll(0) end
	self.title:SetText(title or "")
	self.intro:SetText(intro or "")
	local y = -(tonumber(self.intro:GetStringHeight()) or 16) - 54
	local lastGroup
	for _, entry in ipairs(list) do
		local groupName = query and (self:PageName(entry.page) .. " · " .. entry.group) or entry.group
		if groupName ~= lastGroup then
			lastGroup = groupName
			y = groupHeader(groupName, y - 8)
		end
		local row = Window.rowFor(entry)
		row:ClearAllPoints()
		row:SetPoint("TOPLEFT", 0, y)
		local h = row:Layout(CONTENT)
		row:SetSize(CONTENT, h)
		if row.control and row.control.Refresh then row.control:Refresh() end
		row:Show()
		y = y - h - ROW_GAP
	end
	for i = headerCount + 1, #headers do headers[i]:Hide() end
	self.child:SetHeight(-y + 20)
	self:Scroll(was)
	self:Nav()
	self:Footer()
	self:Describe(nil)
end

function Window:PageName(id)
	for _, page in ipairs(Options.PAGES) do
		if page[1] == id then return page[2] end
	end
	return id
end

-- Keeps everything shown in step after a change, wherever it came from.
function Window:Refresh()
	if not (self.page and self.page:IsShown()) then return end
	for _, row in pairs(rows) do
		if row:IsShown() and row.control and row.control.Refresh then row.control:Refresh() end
	end
	self:Footer()
end

function Window:Scroll(to)
	local view = self.scroll:GetHeight() or 0
	local most = math.max(0, (self.child:GetHeight() or 0) - view)
	to = math.max(0, math.min(to, most))
	self.scroll:SetVerticalScroll(to)
	local thumb = self.thumb
	thumb:SetShown(most > 0)
	if most > 0 and view > 0 then
		local share = view / (view + most)
		local size = math.max(30, view * share)
		thumb:SetHeight(size)
		thumb:ClearAllPoints()
		thumb:SetPoint("TOPRIGHT", self.scroll, "TOPRIGHT", 10, -(view - size) * (to / most))
	end
end

function Window:Nav()
	for _, button in ipairs(self.navButtons) do
		local chosen = not query and button.id == current
		colour(button.text, chosen and "accent" or (button:IsMouseOver() and "text" or "muted"))
		button.mark:SetShown(chosen)
		colour(button.mark, "accent")
		button.lift:SetShown(chosen)
		colour(button.lift, "text", 0.06)
		colour(button.count, "muted", 0.7)
	end
end

function Window:Footer()
	local waiting = Options.pending()
	self.reload:SetShown(waiting > 0)
	if self.saying then return end
	if waiting > 0 then
		self.note:SetText(waiting == 1 and "1 change waits for a reload." or ("%d changes wait for a reload."):format(waiting))
		colour(self.note, "accent")
	else
		self.note:SetText("Settings are for all your characters unless a setting says otherwise.")
		colour(self.note, "muted")
	end
end

-- A short word in the footer after something is done.
function Window:Say(text)
	self.saying = true
	self.note:SetText(text)
	colour(self.note, "text")
	C_Timer.After(4, function()
		self.saying = nil
		self:Footer()
	end)
end

-- The notes column: the setting under the mouse, or the page.
function Window:Describe(entry, extra)
	if not self.page then return end
	if not entry then
		self.detailCaption:SetText("THIS PAGE")
		local name, intro = self.title:GetText(), self.intro:GetText()
		self.detailName:SetText(name or "")
		self.detailText:SetText((intro or "") .. "\n\nPoint at a setting to read what it does.")
		self.detailNotes:SetText("")
		return
	end
	self.detailCaption:SetText((entry.group or ""):upper())
	self.detailName:SetText(entry.name)
	local text = entry.desc ~= "" and entry.desc or "No more to say about this one."
	if extra then text = text .. "\n\n" .. extra end
	self.detailText:SetText(text)
	local notes = {}
	if entry.kind == "toggle" then
		notes[#notes + 1] = "Usually " .. (entry.default and "on." or "off.")
	elseif entry.kind == "choice" and entry.default ~= nil then
		notes[#notes + 1] = "Usually " .. labelOf(entry, entry.default) .. "."
	end
	if entry.reload then
		notes[#notes + 1] = Options.waiting(entry) and "Changed: reload to see it." or "Takes effect after a reload."
	end
	if entry.game then notes[#notes + 1] = "Changes one of the game's own settings. Put the game's settings back on the Setup page undoes it." end
	if entry.scope then notes[#notes + 1] = "Kept " .. entry.scope:lower() .. "." end
	if entry.needs then notes[#notes + 1] = entry.needs .. "." end
	if entry.cmd then notes[#notes + 1] = "Typed: " .. entry.cmd end
	self.detailNotes:SetText(table.concat(notes, "\n"))
end

-- Building --------------------------------------------------------------------

function Window:Build()
	local page = CreateFrame("Frame", "StoaSettings", UIParent)
	page:SetSize(WIDTH, HEIGHT)
	page:SetPoint("CENTER", 0, 30)
	page:SetFrameStrata("DIALOG")
	page:SetToplevel(true)
	page:SetClampedToScreen(true)
	page:EnableMouse(true)
	page:SetMovable(true)
	page:RegisterForDrag("LeftButton")
	page:SetScript("OnDragStart", page.StartMoving)
	page:SetScript("OnDragStop", page.StopMovingOrSizing)
	page:SetScript("OnHide", closeMenu)
	page:Hide()
	table.insert(UISpecialFrames, "StoaSettings")
	UI.windowPanel(page, 0.97, { header = HEADER, footer = FOOTER })
	self.page = page

	-- Header: name, search, close.
	local mark = UI.text(page, "serif", Stoa.typeSize.title, "accent")
	mark:SetPoint("TOPLEFT", PAD, -20)
	mark:SetText("STOA")
	local sub = UI.caption(page, "Settings")
	sub:SetPoint("BOTTOMLEFT", mark, "BOTTOMRIGHT", 12, 2)

	local close = CreateFrame("Button", nil, page)
	close:SetSize(26, 26)
	close:SetPoint("TOPRIGHT", -14, -17)
	local cross = UI.text(close, "sans", Stoa.typeSize.title, "muted", "CENTER")
	cross:SetPoint("CENTER")
	cross:SetText("×")
	close:SetScript("OnClick", function() page:Hide() end)
	close:SetScript("OnEnter", function() colour(cross, "accent") end)
	close:SetScript("OnLeave", function() colour(cross, "muted") end)

	local search = CreateFrame("EditBox", "StoaSettingsSearch", page)
	search:SetAutoFocus(false)
	search:SetSize(300, 28)
	search:SetPoint("RIGHT", close, "LEFT", -12, 0)
	search:SetTextInsets(12, 26, 0, 0)
	search:SetMaxLetters(40)
	Stoa:SetFont(search, "sans", Stoa.typeSize.body)
	search:SetTextColor(Stoa:Color("text"))
	local searchBack = UI.pillFill(search, 0)
	searchBack:SetVertexColor(0, 0, 0, 0.4)
	local searchEdge = UI.pillEdge(search, 0)
	local searchHint = UI.text(search, "sans", Stoa.typeSize.body, "muted")
	searchHint:SetPoint("LEFT", 12, 0)
	searchHint:SetText("Search settings")
	local clear = CreateFrame("Button", nil, search)
	clear:SetSize(20, 20)
	clear:SetPoint("RIGHT", -6, 0)
	local clearText = UI.text(clear, "sans", Stoa.typeSize.label, "muted", "CENTER")
	clearText:SetPoint("CENTER")
	clearText:SetText("×")
	clear:SetScript("OnClick", function() search:SetText("") search:ClearFocus() end)
	local function paintSearch()
		local text = search:GetText()
		searchHint:SetShown(text == "" and not search:HasFocus())
		clear:SetShown(text ~= "")
		searchEdge:Set(Stoa:Color(search:HasFocus() and "accent" or "hairline"))
	end
	search:SetScript("OnTextChanged", function(box)
		local text = strtrim(box:GetText() or "")
		query = text ~= "" and text or nil
		paintSearch()
		self:Draw()
	end)
	search:SetScript("OnEscapePressed", function(box)
		if box:GetText() ~= "" then box:SetText("") else box:ClearFocus() end
	end)
	search:SetScript("OnEnterPressed", function(box) box:ClearFocus() end)
	search:SetScript("OnEditFocusGained", paintSearch)
	search:SetScript("OnEditFocusLost", paintSearch)
	self.search, self.paintSearch = search, paintSearch

	-- Pages.
	self.navButtons = {}
	local y = -HEADER - 14
	for i, info in ipairs(Options.PAGES) do
		if info[1] == "setup" then
			local rule = UI.line(page, "hairline")
			rule:SetPoint("TOPLEFT", PAD, y - 6)
			rule:SetWidth(NAV - 12)
			y = y - 14
		end
		local button = CreateFrame("Button", nil, page)
		button:SetSize(NAV, 30)
		button:SetPoint("TOPLEFT", 12, y)
		button.id = info[1]
		button.lift = UI.pillFill(button, 0)
		button.mark = button:CreateTexture(nil, "ARTWORK")
		button.mark:SetTexture(UI.WHITE)
		button.mark:SetSize(2, 16)
		button.mark:SetPoint("LEFT", 2, 0)
		button.text = UI.text(button, "sans", Stoa.typeSize.label, "muted")
		button.text:SetPoint("LEFT", 14, 0)
		button.text:SetText(info[2])
		button.count = UI.text(button, "sans", Stoa.typeSize.caption, "muted", "RIGHT")
		button.count:SetPoint("RIGHT", -10, 0)
		button.count:SetText(#Options.onPage(info[1]))
		button:SetScript("OnClick", function()
			current = info[1]
			if query then search:SetText("") search:ClearFocus() end
			self:Draw()
		end)
		button:SetScript("OnEnter", function() self:Nav() end)
		button:SetScript("OnLeave", function() self:Nav() end)
		self.navButtons[i] = button
		y = y - 32
	end
	local split = page:CreateTexture(nil, "BORDER")
	split:SetTexture(UI.WHITE)
	UI.pixel(split, "width")
	split:SetPoint("TOPLEFT", NAV + PAD, -HEADER)
	split:SetPoint("BOTTOMLEFT", NAV + PAD, FOOTER)
	UI.paint(split, "hairline")

	-- Content.
	local scroll = CreateFrame("ScrollFrame", nil, page)
	scroll:SetPoint("TOPLEFT", NAV + PAD * 2, -HEADER - 12)
	scroll:SetPoint("BOTTOMRIGHT", -(DETAIL + PAD * 2), FOOTER + 4)
	scroll:EnableMouseWheel(true)
	scroll:SetScript("OnMouseWheel", function(frame, delta)
		closeMenu()
		self:Scroll((frame:GetVerticalScroll() or 0) - delta * 60)
	end)
	local child = CreateFrame("Frame", nil, scroll)
	child:SetSize(CONTENT, 10)
	scroll:SetScrollChild(child)
	self.scroll, self.child = scroll, child
	local thumb = page:CreateTexture(nil, "ARTWORK")
	thumb:SetTexture(UI.WHITE)
	thumb:SetWidth(3)
	UI.paint(thumb, "text", 0.18)
	self.thumb = thumb

	self.title = UI.text(child, "serif", Stoa.typeSize.display, "text")
	self.title:SetPoint("TOPLEFT", 0, -4)
	self.intro = UI.text(child, "sans", Stoa.typeSize.body, "muted")
	self.intro:SetPoint("TOPLEFT", self.title, "BOTTOMLEFT", 0, -6)
	self.intro:SetWidth(CONTENT)

	-- Notes.
	local rule = page:CreateTexture(nil, "BORDER")
	rule:SetTexture(UI.WHITE)
	UI.pixel(rule, "width")
	rule:SetPoint("TOPRIGHT", -(DETAIL + PAD), -HEADER)
	rule:SetPoint("BOTTOMRIGHT", -(DETAIL + PAD), FOOTER)
	UI.paint(rule, "hairline")
	local detail = CreateFrame("Frame", nil, page)
	detail:SetPoint("TOPRIGHT", -PAD, -HEADER - 18)
	detail:SetSize(DETAIL - PAD, 400)
	self.detailCaption = UI.text(detail, "sans", Stoa.typeSize.caption, "muted")
	self.detailCaption:SetPoint("TOPLEFT")
	self.detailName = UI.text(detail, "serif", Stoa.typeSize.title, "text")
	self.detailName:SetPoint("TOPLEFT", self.detailCaption, "BOTTOMLEFT", 0, -8)
	self.detailName:SetWidth(DETAIL - PAD)
	self.detailText = UI.text(detail, "sans", Stoa.typeSize.body, "text")
	self.detailText:SetPoint("TOPLEFT", self.detailName, "BOTTOMLEFT", 0, -10)
	self.detailText:SetWidth(DETAIL - PAD)
	self.detailText:SetSpacing(3)
	self.detailNotes = UI.text(detail, "sans", Stoa.typeSize.body, "muted")
	self.detailNotes:SetPoint("TOPLEFT", self.detailText, "BOTTOMLEFT", 0, -14)
	self.detailNotes:SetWidth(DETAIL - PAD)
	self.detailNotes:SetSpacing(5)

	-- Footer.
	self.note = UI.text(page, "sans", Stoa.typeSize.body, "muted")
	self.note:SetPoint("BOTTOMLEFT", PAD, 18)
	self.reload = UI.button(page, "Reload now", 110, function() ReloadUI() end)
	self.reload:SetPoint("LEFT", self.note, "RIGHT", 12, 0)
	local defaults
	defaults = UI.button(page, "Defaults for this page", 180, function(button)
		if not defaults.armed then
			defaults.armed = true
			button.text:SetText("Click again to reset")
			C_Timer.After(3, function()
				defaults.armed = nil
				defaults.text:SetText("Defaults for this page")
			end)
			return
		end
		defaults.armed = nil
		button.text:SetText("Defaults for this page")
		self:Defaults()
	end)
	defaults:SetPoint("BOTTOMRIGHT", -PAD, 12)
	self.defaults = defaults

	Stoa:On("STOA_OPTION_CHANGED", function() if page:IsShown() then self:Draw(true) end end)
	Stoa:On("STOA_THEME_CHANGED", function()
		if page:IsShown() then
			search:SetTextColor(Stoa:Color("text"))
			self:Draw()
		end
	end)
	UI.applyTheme()
end

-- Puts this page's toggles and choices back to how Stoa comes.
function Window:Defaults()
	local list = query and (Options.search(query) or {}) or Options.onPage(current)
	local n = 0
	for _, entry in ipairs(list) do
		if (entry.kind == "toggle" or entry.kind == "choice") and entry.default ~= nil and not entry.set
			and Options.value(entry) ~= entry.default then
			Options.set(entry, entry.default)
			n = n + 1
		end
	end
	self:Say(n == 0 and "Already as Stoa comes." or (n == 1 and "1 setting put back." or ("%d settings put back."):format(n)))
end

function Window:Show(pageId)
	if not self.page then self:Build() end
	if pageId then current = pageId end
	self.page:Show()
	self.paintSearch()
	self:Draw()
	self:Scroll(0)
end

function Window:Toggle()
	if self.page and self.page:IsShown() then self.page:Hide() else self:Show() end
end

function Window:Hide()
	if self.page then self.page:Hide() end
end
Options.close = function() Window:Hide() end

-- The window doesn't stay over a fight; it opens again when asked.
Stoa:On("PLAYER_REGEN_DISABLED", function()
	if Window.page and Window.page:IsShown() then
		Window.page:Hide()
		Stoa:Print("Settings closed for the fight.")
	end
end)
