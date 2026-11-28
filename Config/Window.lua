-- Stoa: the settings window. Pages down the left, the settings of one page
-- (or the search's finds) in the middle, and on the right what the setting
-- under the mouse does, whether it waits for a reload, where it's kept and
-- the /stoa words for it. Everything it shows comes from Config/Options.lua.
local _, ns = ...
local Stoa = ns.Stoa
-- Hooks on the game's code are guarded (Core/Report.lua).
local hooksecurefunc = Stoa.SafeHook
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
-- A setting tucked under the one it belongs to (entry.under).
local UNDER_INDENT, UNDER_GAP = 16, 0

local current = "parts"
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
	knob:SetColorTexture(1, 1, 1, 1)
	-- Slate: a full pill (two round ends and the stretch between them)
	-- with a pale knob, as on its mock-up. Solid colours, since the three
	-- pieces overlap.
	local pill, track
	if UI.tooled() then
		-- Leather and Matte: a track pressed into the material, warming
		-- with the accent when on, and a lit accent knob with a shadow.
		fill:Hide()
		track = UI.pressIn(button, "PlateFill.tga")
		track.warm = UI.pillFill(button, 0)
		track.warm:SetDrawLayer("BACKGROUND", -6)
		track.knobShadow = UI.circle(button, "ARTWORK", 0, 16)
		track.knobShadow:SetColorTexture(0, 0, 0, 0.55)
		track.knobLight = UI.circle(button, "ARTWORK", 2, 8)
		track.knobLight:SetColorTexture(1, 1, 1, 1)
		track.knobLight:SetPoint("CENTER", knob, "CENTER", -1, 2)
	elseif UI.slate() then
		fill:Hide()
		pill = { UI.circle(button, "BACKGROUND", 0, 20), UI.circle(button, "BACKGROUND", 0, 20), button:CreateTexture(nil, "BACKGROUND") }
		pill[1]:SetPoint("LEFT")
		pill[2]:SetPoint("RIGHT")
		pill[3]:SetPoint("TOPLEFT", 10, 0)
		pill[3]:SetPoint("BOTTOMRIGHT", -10, 0)
		for _, part in ipairs(pill) do part:SetColorTexture(1, 1, 1, 1) end
	end
	function button:Refresh()
		local on = Options.value(entry) and true or false
		if track then
			edge:Clear()
			colour(track.warm, "accent", on and 0.2 or 0)
			track.warm:SetShown(on)
			if on then colour(knob, "accent", 1) else colour(knob, "muted", 0.75) end
			track.knobLight:SetVertexColor(1, 1, 1, on and 0.35 or 0.12)
			knob:ClearAllPoints()
			knob:SetPoint(on and "RIGHT" or "LEFT", on and -3 or 3, 0)
			track.knobShadow:ClearAllPoints()
			track.knobShadow:SetPoint("CENTER", knob, "CENTER", 0, -1)
			return
		end
		if pill then
			local r, g, b = Stoa:Color(on and "accent" or "text")
			-- Off: a dim grey with a grey knob. On: the track holds a
			-- quarter of the accent and the knob all of it, so the accent
			-- sits on the round mark alone.
			local k = on and 0.26 or 0.2
			for _, part in ipairs(pill) do part:SetVertexColor(r * k, g * k, b * k, 1) end
			edge:Clear()
			colour(knob, on and "accent" or "muted", 1)
			knob:ClearAllPoints()
			knob:SetPoint(on and "RIGHT" or "LEFT", on and -3 or 3, 0)
			return
		end
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
	-- Leather and Matte: one groove pressed into the material, the chosen
	-- part a raised plate standing in it.
	local tooled = UI.tooled()
	if tooled then
		back:Hide()
		UI.pressIn(holder, "PlateFill.tga")
	end
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
		button.lift = tooled and UI.raisePlate(button) or UI.pillFill(button, 0)
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
		local v = Options.value(entry)
		if tooled then
			edge:Clear()
			for _, button in ipairs(self.buttons) do
				button.chosen = button.value == v
				button.lift:SetShown(button.chosen)
				button.edge:Clear()
				colour(button.text, button.chosen and "text" or "muted")
			end
			return
		end
		edge:Set(Stoa:Color("hairline"))
		for _, button in ipairs(self.buttons) do
			button.chosen = button.value == v
			button.lift:SetShown(button.chosen)
			-- Slate: the chosen one is a raised grey plate with a fine edge
			-- and its word in the text colour; no accent.
			local slate = UI.slate()
			colour(button.lift, "text", slate and 0.1 or 0.12)
			if button.chosen then
				local er, eg, eb = Stoa:Color(slate and "text" or "accent")
				button.edge:Set(er, eg, eb, slate and 0.16 or 1)
			else
				button.edge:Clear()
			end
			colour(button.text, button.chosen and (slate and "text" or "accent") or "muted")
		end
	end
	return holder
end

-- A choice whose options are small pictures over their names (the Halo's
-- arc styles). entry.pictures(value) gives the textures for one option's
-- left and right half; they are the real art, drawn small.
local TILE_W, TILE_H, TILE_ART = 80, 94, 60

local function makeTiles(parent, entry)
	local holder = CreateFrame("Frame", nil, parent)
	holder.buttons = {}
	for i, option in ipairs(entry.options) do
		local button = CreateFrame("Button", nil, holder)
		button:SetSize(TILE_W, TILE_H)
		button:SetPoint("LEFT", (i - 1) * (TILE_W + 4), 0)
		button.back = UI.pillFill(button, 0)
		button.edge = UI.pillEdge(button, 0)
		local left, right = entry.pictures(option[1])
		button.left = button:CreateTexture(nil, "ARTWORK")
		button.left:SetSize(TILE_ART / 2, TILE_ART)
		button.left:SetPoint("TOPRIGHT", button, "TOP", 0, -8)
		button.left:SetTexture(left)
		button.right = button:CreateTexture(nil, "ARTWORK")
		button.right:SetSize(TILE_ART / 2, TILE_ART)
		button.right:SetPoint("TOPLEFT", button, "TOP", 0, -8)
		button.right:SetTexture(right)
		local text = UI.text(button, "sans", Stoa.typeSize.body, "muted", "CENTER")
		text:SetPoint("BOTTOM", 0, 7)
		text:SetText(option[2])
		button.text, button.value = text, option[1]
		button:SetScript("OnClick", function() Options.set(entry, option[1]) end)
		button:SetScript("OnEnter", function(self) self.over = true; holder:Refresh() end)
		button:SetScript("OnLeave", function(self) self.over = nil; holder:Refresh() end)
		hover(button, entry)
		holder.buttons[i] = button
	end
	holder:SetSize(#entry.options * (TILE_W + 4) - 4, TILE_H)
	function holder:Refresh()
		local v = Options.value(entry)
		for _, button in ipairs(self.buttons) do
			local chosen = button.value == v
			local lit = chosen or button.over
			button.chosen = chosen
			local slate = UI.slate()
			local tooled = not slate
			if tooled and chosen then
				-- Leather and Matte: raised and edged in the text colour;
				-- the accent stays in the picture.
				colour(button.back, "text", 0.07)
				local er, eg, eb = Stoa:Color("text")
				button.edge:Set(er, eg, eb, 0.22)
			elseif slate and chosen then
				-- Slate: raised grey with a fine edge; the accent stays in
				-- the picture.
				colour(button.back, "text", 0.08)
				local er, eg, eb = Stoa:Color("text")
				button.edge:Set(er, eg, eb, 0.18)
			else
				button.back:SetVertexColor(0, 0, 0, chosen and 0.5 or 0.3)
				button.edge:Set(Stoa:Color(chosen and "accent" or "hairline"))
			end
			colour(button.left, "text", lit and 0.95 or 0.5)
			colour(button.right, (lit or not UI.slate()) and "accent" or "muted", lit and 0.95 or 0.5)
			colour(button.text, (chosen or button.over) and "text" or "muted")
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
	menu.stoaRise = UI.intro(menu, 0, 4, UI.MOTION.quick)
	menu:HookScript("OnShow", function(self) self.stoaRise:Play() end)
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
		-- Leather and Matte: a fine accent edge round the list.
		if UI.tooled() and self.stoaPanelEdge then
			local r, g, b = Stoa:Color("accent")
			self.stoaPanelEdge:Set(r, g, b, 0.2)
		end
		for i, row in ipairs(self.rows) do
			if row:IsShown() then
				local chosen = row.value == v
				-- The mark alone (Slate's dot, the others' diamond) shows the
				-- chosen line; its word stays in the text colour.
				colour(row.text, "text")
				row.dot:SetShown(chosen and UI.slate())
				colour(row.dot, "accent")
				row.diamond:SetShown(chosen and UI.tooled())
				row.glow:SetShown(i == self.focus)
				-- Leather and Matte: the line under the mouse sits pressed in.
				if UI.tooled() then row.glow:SetVertexColor(0, 0, 0, 0.35) else colour(row.glow, "text", 0.08) end
			end
		end
	end
end

local function openMenu(owner, entry, above)
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
			row.swatch:SetColorTexture(1, 1, 1, 1)
			row.swatch:SetPoint("LEFT", 12, 0)
			row.text = UI.text(row, "sans", Stoa.typeSize.body, "text")
			row.dot = UI.circle(row, "ARTWORK", 1, 6)
			row.dot:SetColorTexture(1, 1, 1, 1)
			row.dot:SetPoint("RIGHT", -12, 0)
			row.diamond = UI.chosenMark(row, 8)
			row.diamond:SetPoint("RIGHT", -11, 0)
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
	if above then
		menu:SetPoint("BOTTOMLEFT", owner, "TOPLEFT", -8, 4)
	else
		menu:SetPoint("TOPRIGHT", owner, "BOTTOMRIGHT", 0, -4)
	end
	menu:Paint()
	menu.catcher:Show()
	menu:Show()
end
-- The same list for a choice made outside the window (the console's slots).
Window.OpenMenu = openMenu

local function makeSelect(parent, entry)
	local button = UI.button(parent, "", INLINE, function(self) openMenu(self, entry) end)
	button.text:ClearAllPoints()
	button.text:SetPoint("LEFT", 12, 0)
	button.text:SetPoint("RIGHT", -28, 0)
	button.text:SetJustifyH("LEFT")
	local swatch = UI.circle(button, "ARTWORK", 1, 10)
	swatch:SetColorTexture(1, 1, 1, 1)
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
	-- A drawn outline, not four one-pixel lines: at some UI scales a line
	-- that thin fell between pixels and one side of the box went missing.
	local edge = UI.pillEdge(tick, 0)
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
	return UI.join(out)
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
	-- Right-click puts a changed switch or choice back as STOA comes.
	row:SetScript("OnMouseUp", function(_, button)
		if button ~= "RightButton" or not Options.isChanged(entry) then return end
		Options.set(entry, entry.default)
		Window:Say(entry.name .. " put back.")
	end)
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
	local seg = not entry.list and (entry.pictures and makeTiles or makeSegments)(row, entry)
	if seg and seg:GetWidth() > CONTENT - 40 then
		seg:Hide()
		seg = nil
	end
	row.control = seg or makeSelect(row, entry)
	local inline = row.control:GetWidth() <= INLINE + 2
	function row:Layout(w)
		self.control:ClearAllPoints()
		-- A wider row of choices still sits beside a name short enough to
		-- leave it the room; otherwise it goes under the name, at the right
		-- edge where every other control is.
		local beside = inline
		if not beside and self.name.GetUnboundedStringWidth then
			local nameW = tonumber(self.name:GetUnboundedStringWidth())
			beside = nameW ~= nil and nameW + self.control:GetWidth() + 24 <= w
		end
		if beside then
			self.control:SetPoint("TOPRIGHT", 0, -4)
			return math.max(nameHeight(self, w - self.control:GetWidth() - 16), 34) + 2
		end
		local h = nameHeight(self, w)
		self.control:SetPoint("TOPRIGHT", 0, -h - 4)
		return h + math.max(self.control:GetHeight(), 26) + 8
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
	-- Leather and Matte: a field pressed into the material.
	if UI.tooled() then
		back:Hide()
		UI.pressIn(box, "PlateFill.tga")
	end
	local hint = UI.text(box, "sans", Stoa.typeSize.body, "muted")
	hint:SetPoint("LEFT", 10, 0)
	hint:SetText(entry.placeholder or "Type, then Enter")
	local said = UI.text(row, "sans", Stoa.typeSize.caption, "muted")
	said:SetPoint("LEFT", box, "RIGHT", 10, 0)
	said:SetPoint("RIGHT", row, "RIGHT")
	local function paintBox()
		hint:SetShown(box:GetText() == "" and not box:HasFocus())
		if UI.tooled() and not box:HasFocus() then edge:Clear() return end
		local r, g, b, a = Stoa:Color(box:HasFocus() and "accent" or "hairline")
		edge:Set(r, g, b, UI.tooled() and 0.5 or a)
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
				chip.cross = UI.glyph(chip, "Cross", 10, "muted")
				chip.cross:SetPoint("RIGHT", -8, 0)
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

-- The console's right side: its three slots as wells, then every page a
-- slot can hold as a tile. Click a well, then a tile.
local WELL_H, PAGE_TILE_H = 44, 46
function builders.slots(row, entry)
	local console = Stoa.modules.Grimoire
	row.sel = 1
	row.wells, row.tiles, row.heads = {}, {}, {}
	local function plate(parent)
		local button = CreateFrame("Button", nil, parent)
		button.back = UI.pillFill(button, 0)
		button.edge = UI.pillEdge(button, 0)
		button:SetScript("OnEnter", function(self) self.over = true; row:Paint() end)
		button:SetScript("OnLeave", function(self) self.over = nil; row:Paint() end)
		hover(button, entry)
		return button
	end
	for n = 1, 3 do
		local well = plate(row)
		well.cap = UI.caption(well, "Slot " .. n)
		well.cap:SetPoint("TOPLEFT", 10, -8)
		well.text = UI.text(well, "serif", Stoa.typeSize.label, "text")
		well.text:SetPoint("BOTTOMLEFT", 10, 8)
		well.text:SetPoint("BOTTOMRIGHT", -8, 8)
		well.text:SetJustifyH("LEFT")
		well.text:SetWordWrap(false)
		well:SetScript("OnClick", function() row.sel = n; row:Paint() end)
		row.wells[n] = well
	end
	-- Says what a click on a tile will do, so the two steps read at once.
	row.guide = UI.text(row, "sans", Stoa.typeSize.body, "muted")
	local kinds = console and console.SLOT_KINDS or {}
	for i, kind in ipairs(kinds) do
		local tile = plate(row)
		tile.text = UI.text(tile, "sans", Stoa.typeSize.body, "text")
		tile.text:SetPoint("TOPLEFT", 9, -8)
		tile.note = UI.text(tile, "sans", Stoa.typeSize.caption, "muted")
		tile.note:SetPoint("TOPLEFT", tile.text, "BOTTOMLEFT", 0, -3)
		tile.note:SetJustifyH("LEFT")
		tile.note:SetWordWrap(false)
		tile.mark = UI.text(tile, "sans", Stoa.typeSize.caption, "accent", "RIGHT")
		tile.mark:SetPoint("TOPRIGHT", -8, -9)
		tile.text:SetText(kind[2])
		tile.note:SetText(kind[3] or "")
		tile.value = kind[1]
		tile:SetScript("OnClick", function() if console then console:SetSlot(row.sel, kind[1]) end end)
		row.tiles[i] = tile
	end
	function row:Paint()
		local slots = console and console.Slots and console.db and console:Slots() or {}
		local labels = {}
		for _, kind in ipairs(kinds) do labels[kind[1]] = kind[2] end
		for n, well in ipairs(self.wells) do
			local chosen = n == self.sel
			well.text:SetText(labels[slots[n]] or "Empty")
			well.back:SetVertexColor(0, 0, 0, 0.5)
			well.edge:Set(Stoa:Color(chosen and "accent" or "hairline"))
			colour(well.cap, chosen and "accent" or "muted")
			colour(well.text, (chosen or well.over) and "text" or "muted")
		end
		local r, g, b = Stoa:Color("accent")
		self.guide:SetText(("Slot %d holds |cff%02x%02x%02x%s|r. Click a page below to change it, or another slot above."):format(self.sel, r * 255, g * 255, b * 255, labels[slots[self.sel]] or "Empty"))
		for _, tile in ipairs(self.tiles) do
			local at
			for n, held in ipairs(slots) do
				if held == tile.value and held ~= "empty" then at = n end
			end
			tile.mark:SetText(at and ("SLOT " .. at) or "")
			tile.back:SetVertexColor(0, 0, 0, tile.over and 0.45 or 0.25)
			tile.edge:Set(Stoa:Color((tile.over or at == self.sel) and "accent" or "hairline"))
			colour(tile.text, (at or tile.over) and "text" or "muted")
		end
	end
	function row:Layout(w)
		local y = -nameHeight(self, w) - 4
		local gap = 6
		local third = math.floor((w - gap * 2) / 3)
		for n, well in ipairs(self.wells) do
			well:SetSize(third, WELL_H)
			well:ClearAllPoints()
			well:SetPoint("TOPLEFT", (n - 1) * (third + gap), y)
		end
		y = y - WELL_H - 10
		self.guide:ClearAllPoints()
		self.guide:SetPoint("TOPLEFT", 0, y)
		self.guide:SetWidth(w)
		self.guide:SetJustifyH("LEFT")
		y = y - 18
		local group, col, heads = nil, 0, 0
		for i, tile in ipairs(self.tiles) do
			local g = kinds[i][4]
			if g ~= group then
				if group and col > 0 then y = y - PAGE_TILE_H - gap end
				group, col, heads = g, 0, heads + 1
				local head = self.heads[heads]
				if not head then
					head = UI.caption(self, g)
					self.heads[heads] = head
				end
				head:ClearAllPoints()
				head:SetPoint("TOPLEFT", 0, y - 8)
				y = y - 26
			elseif col == 3 then
				col = 0
				y = y - PAGE_TILE_H - gap
			end
			tile:SetSize(third, PAGE_TILE_H)
			tile.note:SetWidth(third - 17)
			tile:ClearAllPoints()
			tile:SetPoint("TOPLEFT", col * (third + gap), y)
			col = col + 1
		end
		self:Paint()
		return -y + PAGE_TILE_H + 10
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
				if UI.tooled() then
					button.edge:Clear()
				elseif button.chosen then
				local er, eg, eb = Stoa:Color("accent")
				button.edge:Set(er, eg, eb, UI.slate() and 0.6 or 1)
			else
				button.edge:Clear()
			end
				colour(button.text, button.chosen and (UI.tooled() and "text" or "accent") or "muted")
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
		-- Slate: the heading is the muted caption (UI.eyebrow), with no rule.
		header.text = UI.eyebrow(header, "")
		header.text:SetPoint("LEFT")
		header.rule = UI.line(header, "hairline")
		header.rule:SetPoint("LEFT", header.text, "RIGHT", 10, 0)
		header.rule:SetPoint("RIGHT")
		header.rule:SetShown(not UI.slate())
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
	local list, more, title, intro
	if query then
		list = Options.search(query) or {}
		title = #list == 0 and "Nothing found" or ("%d found"):format(#list)
		intro = #list == 0 and ("No setting mentions \"%s\". Try a plainer word, such as bags, chat or camera."):format(query)
			or ("Settings that mention \"%s\", from every page."):format(query)
	else
		if current == "changed" then
			list = Options.changed()
		elseif current == "parts" then
			list = Options.parts()
		else
			list, more = Options.onPage(current)
		end
		for _, page in ipairs(Options.PAGES) do
			if page[1] == current then title, intro = page[2], page[3] end
		end
		if current == "changed" and #list == 0 then intro = "Nothing yet: every switch and choice is as STOA comes." end
	end
	if not keep then self.scroll:SetVerticalScroll(0) end
	-- A new page (or a new search) eases in; redraws in place don't.
	local shown = query and "?" or current
	if not keep and shown ~= self.drawn then
		self.childIn = self.childIn or UI.fadeIn(self.child, UI.MOTION.quick)
		self.childIn:Play()
	end
	self.drawn = shown
	self.title:SetText(title or "")
	-- The header says where you are: Slate names the page in the accent,
	-- Leather and Matte in the caption's own quiet colour.
	if self.crumb then
		local here = title and title ~= "" and ("  /  " .. (UI.slate() and (Stoa:Hex("accent") .. title:upper() .. "|r") or title:upper())) or ""
		self.crumb:SetText("SETTINGS" .. here)
	end
	self.intro:SetText(intro or "")
	local y = -(tonumber(self.intro:GetStringHeight()) or 16) - 54
	local lastGroup
	local mixed = query or current == "changed"
	local function place(entries)
		for _, entry in ipairs(entries) do
			if Options.shown(entry) then
				local groupName = mixed and (self:PageName(entry.page) .. ": " .. entry.group) or entry.group
				if groupName ~= lastGroup then
					lastGroup = groupName
					y = groupHeader(groupName, y - 8)
				end
				local row = Window.rowFor(entry)
				-- A setting under another sits close beneath it, set in
				-- behind a short rule, so the two read as one control.
				local tuck = entry.under and not mixed and UNDER_INDENT or 0
				if tuck > 0 then
					y = y + ROW_GAP - UNDER_GAP
					if not row.tie then
						row.tie = row:CreateTexture(nil, "BORDER")
						UI.paint(row.tie, "hairline")
						UI.pixel(row.tie, "width")
						row.tie:SetPoint("TOPLEFT", -UNDER_INDENT + 4, -4)
						row.tie:SetPoint("BOTTOMLEFT", -UNDER_INDENT + 4, 4)
					end
				end
				if row.tie then row.tie:SetShown(tuck > 0) end
				row:ClearAllPoints()
				row:SetPoint("TOPLEFT", tuck, y)
				local h = row:Layout(CONTENT - tuck)
				row:SetSize(CONTENT - tuck, h)
				if row.control and row.control.Refresh then row.control:Refresh() end
				row:Show()
				y = y - h - ROW_GAP
			end
		end
	end
	place(list)
	-- The rest of the page waits under More; an opened page stays open.
	local fold = self.fold
	if more and #more > 0 then
		Stoa.db.settingsMore = Stoa.db.settingsMore or {}
		local open = Stoa.db.settingsMore
		if not fold then
			fold = UI.button(self.child, "", CONTENT, function()
				open = Stoa.db.settingsMore
				open[current] = not open[current] or nil
				self:Draw(true)
			end)
			self.fold = fold
		end
		y = y - 10
		fold:ClearAllPoints()
		fold:SetPoint("TOPLEFT", 0, y)
		fold.text:SetText(open[current] and "Show fewer" or (#more == 1 and "More: 1 setting" or ("More: %d settings"):format(#more)))
		fold:Show()
		y = y - 26 - ROW_GAP
		if open[current] then
			lastGroup = nil
			place(more)
		end
	elseif fold then
		fold:Hide()
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
		-- The lift first: it's a white plate until tinted, so nothing that
		-- follows (the mark's motion) may leave it untinted.
		-- Slate: a raised grey plate, the word in the text colour; the
		-- small mark beside it keeps the accent.
		-- Leather and Matte: the chosen line sits pressed in, its word in
		-- the text colour, an accent diamond at its left.
		local slate = UI.slate()
		if slate then colour(button.lift, "text", 0.08) else button.lift:SetVertexColor(0, 0, 0, 0.35) end
		button.lift:SetShown(chosen)
		colour(button.text, chosen and "text" or (button:IsMouseOver() and "text" or "muted"))
		colour(button.mark, "accent")
		colour(button.count, "muted", 0.7)
		if button.id == "changed" then button.count:SetText(#Options.changed()) end
		button.mark:SetShown(chosen)
		if chosen and not button.wasChosen then
			button.wasChosen = true
			pcall(function()
				button.markIn = button.markIn or UI.growIn(button.mark, UI.slate() and "y" or nil)
				button.markIn:Play()
			end)
		end
		button.wasChosen = chosen
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
		self.note:SetText("Settings are saved per character. Saved setups, on the Setup page, copy another's.")
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
	if Options.isChanged(entry) then notes[#notes + 1] = "Changed. Right-click puts it back." end
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
	UI.riseOnShow(page)
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
	local mark = UI.text(page, "serif", Stoa.typeSize.title, "text")
	mark:SetPoint("TOPLEFT", PAD, -20)
	mark:SetText("STOA")
	local sub = UI.caption(page, "Settings")
	sub:SetPoint("BOTTOMLEFT", mark, "BOTTOMRIGHT", 12, 2)
	self.crumb = sub

	local close = CreateFrame("Button", nil, page)
	close:SetSize(26, 26)
	close:SetPoint("TOPRIGHT", -14, -17)
	local cross = UI.glyph(close, "Cross", 16, "muted")
	cross:SetPoint("CENTER")
	close:SetScript("OnClick", function() page:Hide() end)
	close:SetScript("OnEnter", function() colour(cross, "text") end)
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
	-- Leather and Matte: a field pressed into the material.
	if UI.tooled() then
		searchBack:Hide()
		UI.pressIn(search, "PlateFill.tga")
	end
	local searchEdge = UI.pillEdge(search, 0)
	local searchHint = UI.text(search, "sans", Stoa.typeSize.body, "muted")
	searchHint:SetPoint("LEFT", 12, 0)
	searchHint:SetText("Search settings")
	local clear = CreateFrame("Button", nil, search)
	clear:SetSize(20, 20)
	clear:SetPoint("RIGHT", -6, 0)
	local clearText = UI.glyph(clear, "Cross", 10, "muted")
	clearText:SetPoint("CENTER")
	clear:SetScript("OnClick", function() search:SetText("") search:ClearFocus() end)
	local function paintSearch()
		local text = search:GetText()
		searchHint:SetShown(text == "" and not search:HasFocus())
		clear:SetShown(text ~= "")
		local focus = search:HasFocus()
		local r, g, b, a = Stoa:Color(focus and "accent" or "hairline")
		-- Slate: a resting edge that only just shows, not an outline.
		if not focus and UI.slate() then a = (a or 1) * 0.4 end
		-- Leather and Matte: no outline at rest (the field is pressed in);
		-- a soft accent edge while typing.
		if UI.tooled() then
			if focus then searchEdge:Set(r, g, b, 0.5) else searchEdge:Clear() end
			return
		end
		searchEdge:Set(r, g, b, a)
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
			local rule = UI.tooled() and UI.crease(page) or UI.line(page, "hairline")
			rule:SetPoint("TOPLEFT", PAD, y - 6)
			rule:SetWidth(NAV - 12)
			y = y - 14
		end
		local button = CreateFrame("Button", nil, page)
		button:SetSize(NAV, 30)
		button:SetPoint("TOPLEFT", 12, y)
		button.id = info[1]
		button.lift = UI.pillFill(button, 0)
		colour(button.lift, "text", 0.06)
		button.lift:Hide()
		if UI.tooled() then
			button.mark = UI.chosenMark(button, 7)
			button.mark:SetPoint("LEFT", 4, 0)
		else
			button.mark = button:CreateTexture(nil, "ARTWORK")
			button.mark:SetTexture(UI.WHITE)
			button.mark:SetSize(2, 16)
			button.mark:SetPoint("LEFT", 2, 0)
		end
		button.text = UI.text(button, "sans", Stoa.typeSize.label, "muted")
		button.text:SetPoint("LEFT", 14, 0)
		button.text:SetText(info[4] or info[2])
		button.count = UI.text(button, "sans", Stoa.typeSize.caption, "muted", "RIGHT")
		button.count:SetPoint("RIGHT", -10, 0)
		button.count:SetText(info[1] == "parts" and #Options.parts() or #Options.onPage(info[1]))
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
	self.reload = UI.button(page, "Reload now", 110, function() Stoa:Reload() end)
	self.reload:SetPoint("LEFT", self.note, "RIGHT", 12, 0)
	self.reload:SetMain()
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
	local list
	if query then
		list = Options.search(query) or {}
	elseif current == "changed" then
		list = Options.changed()
	elseif current == "parts" then
		list = Options.parts()
	else
		-- More's settings too, opened or not.
		local shown, more = Options.onPage(current)
		list = {}
		for _, entry in ipairs(shown) do list[#list + 1] = entry end
		for _, entry in ipairs(more) do list[#list + 1] = entry end
	end
	local n = 0
	for _, entry in ipairs(list) do
		if Options.isChanged(entry) then
			Options.set(entry, entry.default)
			n = n + 1
		end
	end
	self:Say(n == 0 and "Already as STOA comes." or (n == 1 and "1 setting put back." or ("%d settings put back."):format(n)))
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
