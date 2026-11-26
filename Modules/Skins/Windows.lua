-- Stoa: Blizzard's NPC windows in Stoa's dress.
-- Quest, gossip, merchant, trainer and bag windows lose their parchment and
-- stone frames for a dark rounded panel with a hairline edge; quest and
-- gossip text turns light to read on it, in Stoa's type.
--
-- Everything is looked up by name and guarded, so a window this client has
-- renamed or rebuilt is simply left as Blizzard drew it.
local _, ns = ...
local Stoa = ns.Stoa
local hooksecurefunc = Stoa.SafeHook
local UI = Stoa.UI

local Windows = Stoa:NewModule("Windows")

local strip = Stoa.frames.strip

-- Some windows hold the game's own secure frames (the store, the shop
-- inside collections): asking a forbidden frame anything is an error, so
-- every walk over a window's children passes them by.
local function forbidden(frame)
	return frame.IsForbidden and frame:IsForbidden()
end

-- Strips the plain frames inside a window too, down a few levels, leaving
-- buttons, bars and edit boxes (and their icons) alone.
local KEEP = { Button = true, CheckButton = true, StatusBar = true, EditBox = true, Cooldown = true }
local function stripInside(frame, depth)
	if not (frame and frame.GetChildren) or depth <= 0 then return end
	for _, child in ipairs({ frame:GetChildren() }) do
		local kind = not forbidden(child) and child.GetObjectType and child:GetObjectType()
		if kind and not KEEP[kind] then
			strip(child)
			stripInside(child, depth - 1)
		end
	end
end

local hide = Stoa.frames.hide

local function titleOf(frame)
	if frame.TitleContainer and frame.TitleContainer.TitleText then return frame.TitleContainer.TitleText end
	if frame.TitleText then return frame.TitleText end
	if frame.GetTitleText then return frame:GetTitleText() end
end

-- Buttons ------------------------------------------------------------------

-- Blizzard's red panel buttons become dark rounded keys with light words;
-- the edge warms to the accent under the mouse. Textures only, so this is
-- fine on secure buttons too.
local PANEL_PARTS = { "Left", "Middle", "Center", "Right", "LeftSeparator", "RightSeparator" }

local function isPanelButton(button)
	-- The talent window's Primary and Secondary tabs become words there
	-- (Spellbook.lua), not red buttons.
	-- Tabs anywhere (the macro window's General/Character tabs and the
	-- like) are words with an underline, never boxed keys.
	if button.stoaTabParts or button.LeftActive or button.MiddleActive then return false end
	local parent = button.GetParent and button:GetParent()
	if parent and parent.tabTemplate then return false end
	local name = button.GetName and button:GetName()
	if type(name) == "string" and name:find("Tab%d+$") then return false end
	if button.Left and button.Middle and button.Right then return true end
	-- The newer red buttons (Add New Friend and the like) are three-slice:
	-- Left, Center and Right, set from an atlas kit on every state change.
	return button.Left and button.Center and button.Right and button.atlasName ~= nil
end

local function plainTextures(button)
	for _, key in ipairs(PANEL_PARTS) do hide(button[key]) end
	for _, getter in ipairs({ "GetNormalTexture", "GetPushedTexture", "GetHighlightTexture", "GetDisabledTexture" }) do
		local tex = button[getter] and button[getter](button)
		if tex then tex:SetAlpha(0) end
	end
end

-- Depth for the dark keys: only a soft dark shadow 1px under the key (a
-- light rim along the top read as a harsh grey line). Pressed, the key
-- sinks onto it and its words drop a pixel. Textures and hooked scripts
-- only, so secure buttons are fine.
local KEY_LIP = 1
local function keyDepth(button, face)
	local lip = UI.sliced(button, "BACKGROUND", "CardFill.tga")
	if not (lip and face) then return end
	if face.SetDrawLayer then face:SetDrawLayer("BACKGROUND", -6) end
	lip:SetDrawLayer("BACKGROUND", -8)
	lip:ClearAllPoints()
	lip:SetPoint("TOPLEFT", 0, -KEY_LIP)
	lip:SetPoint("BOTTOMRIGHT", 0, -KEY_LIP)
	lip:SetVertexColor(0, 0, 0, 0.45)
	if button.SetPushedTextOffset then button:SetPushedTextOffset(0, -1) end
	local function press(down)
		local enabled = not button.IsEnabled or button:IsEnabled()
		local y = (down and enabled) and 0 or -KEY_LIP
		lip:SetPoint("TOPLEFT", 0, y)
		lip:SetPoint("BOTTOMRIGHT", 0, y)
	end
	button:HookScript("OnMouseDown", function() press(true) end)
	button:HookScript("OnMouseUp", function() press(false) end)
	button:HookScript("OnLeave", function() press(false) end)
	press(false)
end

local function dressButton(button)
	if not button or button.stoaDressed then return end
	button.stoaDressed = true
	plainTextures(button)
	-- Blizzard puts the art back on some state changes.
	button:HookScript("OnShow", plainTextures)
	button:HookScript("OnEnable", plainTextures)
	button:HookScript("OnDisable", plainTextures)
	local face = UI.roundPanel(button, 0.95)
	keyDepth(button, face)
	local glow = UI.roundBorder(button, "CardEdge.tga", 1)
	local text = button.GetFontString and button:GetFontString()
	if text then
		Stoa:SetFont(text, "sans", Stoa.typeSize.body)
		text:SetShadowOffset(0, 0)
	end
	local function colour(over)
		if text then
			local enabled = not button.IsEnabled or button:IsEnabled()
			text:SetTextColor(Stoa:Color(not enabled and "muted" or over and "accent" or "text"))
		end
		if over then glow:Set(Stoa:Color("accent")) else glow:Clear() end
	end
	button:HookScript("OnEnter", function() colour(true) end)
	button:HookScript("OnLeave", function() colour(false) end)
	button:HookScript("OnShow", function() colour(false) end)
	button.stoaColour = colour
	colour(false)
end

-- The close X: just a quiet cross, warming to the accent under the mouse.
local function dressClose(button)
	if not button or button.stoaDressed then return end
	button.stoaDressed = true
	plainTextures(button)
	button:HookScript("OnShow", plainTextures)
	local cross = Stoa.UI.glyph(button, "Cross", 16, "muted")
	cross:SetPoint("CENTER", 0, 0)
	button:HookScript("OnEnter", function() cross:SetVertexColor(Stoa:Color("accent")) end)
	button:HookScript("OnLeave", function() cross:SetVertexColor(Stoa:Color("muted")) end)
end

-- Maximise and minimise (map, spellbook): the same quiet glyphs as the
-- close cross, a plus to grow and a minus to shrink.
local function dressMaxMin(holder)
	if not holder or holder.stoaDressed or forbidden(holder) then return end
	holder.stoaDressed = true
	for key, glyphName in pairs({ MaximizeButton = "Plus", MinimizeButton = "Minus" }) do
		local button = holder[key]
		if button then
			plainTextures(button)
			button:HookScript("OnShow", plainTextures)
			local glyph = Stoa.UI.glyph(button, glyphName, 14, "muted")
			glyph:SetPoint("CENTER", 0, 0)
			button:HookScript("OnEnter", function() glyph:SetVertexColor(Stoa:Color("accent")) end)
			button:HookScript("OnLeave", function() glyph:SetVertexColor(Stoa:Color("muted")) end)
		end
	end
end

-- Every red button inside a window, however deep.
local function dressButtonsIn(frame, depth)
	if not (frame and frame.GetChildren) or depth <= 0 then return end
	for _, child in ipairs({ frame:GetChildren() }) do
		if not forbidden(child) then
			if child.IsObjectType and child:IsObjectType("Button") and isPanelButton(child) then
				dressButton(child)
			end
			dressButtonsIn(child, depth - 1)
		end
	end
end

-- Search boxes (talents, spellbook): Blizzard's gold-rimmed field becomes
-- a dark rounded well whose edge warms while you type in it. The magnifier
-- and the grey hint stay.
local function dressSearch(box)
	if type(box) ~= "table" or not box.CreateTexture or forbidden(box) or box.stoaSearch then return end
	box.stoaSearch = true
	for _, key in ipairs({ "Left", "Middle", "Right", "Mid" }) do hide(box[key]) end
	if box.NineSlice then hide(box.NineSlice) end
	local fill = UI.sliced(box, "BACKGROUND", "CardFill.tga")
	if fill then
		-- The field's text sits 6px in from its frame on the left.
		fill:SetPoint("TOPLEFT", -6, 0)
		fill:SetDrawLayer("BACKGROUND", -8)
		fill:SetVertexColor(0, 0, 0, 0.45)
	end
	local edge = UI.roundBorder(box, "CardEdge.tga", 1)
	if edge.edges[1] then edge.edges[1]:SetPoint("TOPLEFT", -6, 0) end
	local function paint()
		if box:HasFocus() then edge:Set(Stoa:Color("accent")) else edge:Set(Stoa:Color("hairline")) end
	end
	box:HookScript("OnEditFocusGained", paint)
	box:HookScript("OnEditFocusLost", paint)
	paint()
	UI.applyTheme()
end

-- The small square arrow buttons that open a menu (the talents' search
-- options): a dark rounded key with a quiet down chevron instead of the
-- yellow button. Blizzard sets the arrow's art on every press, so the art
-- goes by alpha, which a new atlas keeps.
local function dressArrowDropdown(button)
	if type(button) ~= "table" or not button.CreateTexture or forbidden(button) or button.stoaArrow then return end
	button.stoaArrow = true
	for _, key in ipairs({ "Arrow", "Background", "Icon" }) do hide(button[key]) end
	plainTextures(button)
	UI.roundPanel(button, 0.95)
	local glow = UI.roundBorder(button, "CardEdge.tga", 1)
	local chevron = UI.glyph(button, "Chevron", 12, "muted")
	chevron:SetPoint("CENTER", 0, 0)
	chevron:SetRotation(-math.pi / 2)
	button:HookScript("OnEnter", function()
		glow:Set(Stoa:Color("accent"))
		chevron:SetVertexColor(Stoa:Color("accent"))
	end)
	button:HookScript("OnLeave", function()
		glow:Clear()
		chevron:SetVertexColor(Stoa:Color("muted"))
	end)
	UI.applyTheme()
end

-- Blizzard's minimal scroll bar (gold arrows, a bevelled thumb): the arrows
-- and track go clear, and the thumb is a thin pill that lights in the
-- accent under the mouse or while dragged. The arrows stay where they are
-- and still click; only their art goes.
local function paintThumb(thumb)
	local pill = thumb.stoaPill
	if not pill then return end
	local lit = thumb.over or thumb.down
	local r, g, b = Stoa:Color(lit and "accent" or "muted")
	pill:SetVertexColor(r, g, b, lit and 0.9 or 0.4)
end

local function dressScrollBar(bar)
	if type(bar) ~= "table" or forbidden(bar) or bar.stoaScroll then return end
	bar.stoaScroll = true
	for _, key in ipairs({ "Back", "Forward" }) do
		local step = bar[key]
		if type(step) == "table" and step.SetAlpha then step:SetAlpha(0) end
	end
	local track = bar.Track
	if type(track) ~= "table" then return end
	for _, key in ipairs({ "Begin", "Middle", "End" }) do
		if track[key] and track[key].SetAlpha then track[key]:SetAlpha(0) end
	end
	-- The rail: a quiet seam, clear at both ends, under the thumb.
	local rail = UI.seam(track, true)
	rail:SetFrameLevel(track:GetFrameLevel())
	rail:SetPoint("TOP", 0, 0)
	rail:SetPoint("BOTTOM", 0, 0)
	local thumb = track.Thumb
	if type(thumb) ~= "table" or not thumb.CreateTexture then return end
	for _, key in ipairs({ "Begin", "Middle", "End" }) do
		if thumb[key] and thumb[key].SetAlpha then thumb[key]:SetAlpha(0) end
	end
	local pill = thumb:CreateTexture(nil, "OVERLAY")
	pill:SetTexture(UI.WHITE)
	pill:SetWidth(3)
	pill:SetPoint("TOP", 0, -1)
	pill:SetPoint("BOTTOM", 0, 1)
	thumb.stoaPill = pill
	if thumb.OnButtonStateChanged then hooksecurefunc(thumb, "OnButtonStateChanged", paintThumb) end
	thumb:HookScript("OnEnter", paintThumb)
	thumb:HookScript("OnLeave", paintThumb)
	paintThumb(thumb)
	UI.applyTheme()
end

Windows.DressSearch = dressSearch
Windows.DressScrollBar = dressScrollBar
Windows.DressArrowDropdown = dressArrowDropdown
Windows.DressButtonsIn = dressButtonsIn
Windows.DressButton = dressButton
Windows.DressClose = dressClose
Windows.DressMaxMin = dressMaxMin

-- Window tabs stay where Blizzard hangs them, under the window, dressed as
-- tabs of the window: a dark rounded tab tucked under its edge, the chosen
-- one in the footer's shade with its word in the text colour over a short
-- accent underline, the rest darker with quiet words. Blizzard disables
-- the selected tab.
local TAB_SHADE = { selected = 0.32, other = 0.5 }

local function tabSelected(tab)
	-- Side tabs (collections) are check buttons: checked is chosen.
	if tab.GetChecked and tab.Icon then return tab:GetChecked() and true or false end
	if tab.isSelected ~= nil then return tab.isSelected and true or false end
	return tab.IsEnabled and not tab:IsEnabled()
end

local function colourTabs(frame)
	for _, tab in ipairs(frame.stoaTabs or {}) do
		local selected = tabSelected(tab)
		local text = tab.Text or (tab.GetFontString and tab:GetFontString())
		if text then text:SetTextColor(Stoa:Color(selected and "text" or "muted")) end
		if tab.stoaWordOnly then
			-- A tab drawn as a word only (macros): the chosen one in the
			-- text colour over the accent line, and every word on one line,
			-- where Blizzard sits the chosen tab's word higher.
			tab.stoaUnderline:SetShown(selected)
			if text then
				text:ClearAllPoints()
				text:SetPoint("CENTER", tab, "CENTER", 0, -(tab.stoaWordDrop or 0))
			end
		elseif tab.stoaShade and UI.slate() then
			-- Slate: the chosen tab washed in the accent, its word in the
			-- accent, no underline (the mock-up's segmented control).
			if selected then
				local r, g, b = Stoa:Color("accent")
				tab.stoaShade:SetVertexColor(r, g, b, 0.14)
				if text then text:SetTextColor(r, g, b) end
			else
				tab.stoaShade:SetVertexColor(0, 0, 0, TAB_SHADE.other)
			end
			tab.stoaUnderline:Hide()
		elseif tab.stoaShade then
			tab.stoaShade:SetVertexColor(0, 0, 0, selected and TAB_SHADE.selected or TAB_SHADE.other)
			tab.stoaUnderline:SetShown(selected)
		end
	end
end

Windows.ColourTabs = colourTabs

local function tabArt(tab)
	if tab.stoaShade then return end
	local base = UI.sliced(tab, "BACKGROUND", "TabFill.tga")
	if not base then return end
	-- Reaches up over the window's bottom edge so the tab reads as part of it.
	base:SetPoint("TOPLEFT", 0, 3)
	base:SetDrawLayer("BACKGROUND", -8)
	UI.tint(base, "panel", 0.97)
	local shade = UI.sliced(tab, "BACKGROUND", "TabFill.tga")
	shade:SetPoint("TOPLEFT", 0, 3)
	shade:SetDrawLayer("BACKGROUND", -7)
	local edge = UI.sliced(tab, "BORDER", "TabEdge.tga")
	if edge then
		edge:SetPoint("TOPLEFT", 0, 3)
		UI.tint(edge, "hairline", UI.edgeAlpha())
	end
	local underline = tab:CreateTexture(nil, "ARTWORK")
	underline:SetHeight(2)
	local text = tab.Text or (tab.GetFontString and tab:GetFontString())
	if text then
		underline:SetPoint("TOPLEFT", text, "BOTTOMLEFT", -2, -3)
		underline:SetPoint("TOPRIGHT", text, "BOTTOMRIGHT", 2, -3)
	else
		underline:SetPoint("BOTTOMLEFT", 10, 6)
		underline:SetPoint("BOTTOMRIGHT", -10, 6)
	end
	UI.paint(underline, "accent")
	tab.stoaShade, tab.stoaUnderline = shade, underline
	tab.stoaTabParts = { base, shade, edge }
	UI.applyTheme()
end

local function dressTabs(frame)
	local name = frame.GetName and frame:GetName()
	local tabs = frame.Tabs
	if not tabs and name then
		tabs = {}
		for i = 1, 6 do
			local tab = _G[name .. "Tab" .. i]
			if tab then tabs[#tabs + 1] = tab end
		end
	end
	if not tabs or #tabs == 0 then return end
	frame.stoaTabs = tabs
	for _, tab in ipairs(tabs) do
		strip(tab)
		-- Side tabs are icons: the icon stays, on a dark tile.
		if tab.Icon and tab.Icon.SetAlpha then tab.Icon:SetAlpha(1) end
		for _, key in ipairs({ "Left", "Middle", "Right", "LeftActive", "MiddleActive", "RightActive", "LeftHighlight", "MiddleHighlight", "RightHighlight" }) do
			hide(tab[key])
		end
		local text = tab.Text or (tab.GetFontString and tab:GetFontString())
		if text then
			Stoa:SetFont(text, "sans", Stoa.typeSize.body)
			text:SetShadowOffset(0, 0)
		end
		xpcall(tabArt, Stoa.catch, tab)
		tab:HookScript("OnEnter", function(self)
			local words = self.Text or (self.GetFontString and self:GetFontString())
			if words and not tabSelected(self) then words:SetTextColor(Stoa:Color("accent")) end
		end)
		tab:HookScript("OnLeave", function() colourTabs(frame) end)
		if tab.Icon and tab.SetChecked then hooksecurefunc(tab, "SetChecked", function() colourTabs(frame) end) end
	end
	colourTabs(frame)
	frame:HookScript("OnShow", function() colourTabs(frame) end)
end

local hookedTabs
local function hookTabs()
	if hookedTabs or not PanelTemplates_UpdateTabs then return end
	hookedTabs = true
	hooksecurefunc("PanelTemplates_UpdateTabs", function(frame)
		if frame and frame.stoaTabs then colourTabs(frame) end
	end)
end

-- Header tints by what a window is for (see UI.WINDOW_FAMILIES).
local FAMILY = {
	MerchantFrame = "trade", MailFrame = "trade", OpenMailFrame = "trade",
	AuctionHouseFrame = "trade", BankFrame = "trade",
	FriendsFrame = "social", SocialUIFrame = "social", CommunitiesFrame = "social", GuildFrame = "social",
	PVEFrame = "social", LFDParentFrame = "social", RaidParentFrame = "social",
}
-- The rulebook's band is BAND tall on every window with room for it.
-- Where Blizzard's content starts higher (its inset, or bag slots on a
-- window with no inset) the band stops there instead, so it never runs
-- under content; without an inset it is HEADER_FALLBACK, the compact band.
local BAND = 44
local HEADER_FALLBACK = 30
local TITLE_INSET = 18
Windows.FAMILY, Windows.HEADER_FALLBACK, Windows.BAND = FAMILY, HEADER_FALLBACK, BAND

-- Windows Stoa never dresses. The game menu and the settings panel are a
-- known cause of blocked-action errors when addons touch them; the rest
-- are drawn over live content or are Blizzard's own small prompts.
Windows.LEAVE = {
	GameMenuFrame = true, SettingsPanel = true, InterfaceOptionsFrame = true,
	VideoOptionsFrame = true, StaticPopup1 = true, StaticPopup2 = true, StaticPopup3 = true,
}

function Windows:Leaves(frame)
	local name = frame and frame.GetName and frame:GetName()
	return name ~= nil and self.LEAVE[name] == true
end

-- The band's height gives the title room above and below: the title sits
-- in the middle of it on the left, the close cross on the right. Out of
-- combat only, so moving them never touches a locked frame.
local PLAIN_HEADER = 40
-- Blizzard windows' metal header rises this far above the window's top, so
-- the title has room without covering what Blizzard puts under it.
local RAISE = 18
Windows.RAISE = RAISE

local function seatTitle(frame, title, close)
	local header = frame.stoaHeader
	if not header or InCombatLockdown() then return end
	-- A skin may ask for a smaller title (bags name themselves in label
	-- size); the size is applied here so a settle never grows it back.
	if title and (frame.stoaPlainHeader or frame.stoaTitleSize) and not frame.stoaOwnTitle then
		Stoa:SetFont(title, "serif", frame.stoaTitleSize or Stoa.typeSize.title)
		title:SetShadowColor(0, 0, 0, 0.9)
		title:SetShadowOffset(1, -1)
	end
	if title and not frame.stoaOwnTitle then
		title:ClearAllPoints()
		title:SetPoint("LEFT", header, "LEFT", TITLE_INSET, 0)
		-- Long names (a narrow bag's "Shipwright's Satchel") stop short of
		-- the close cross with an ellipsis instead of running off the panel.
		title:SetPoint("RIGHT", close or header, close and "LEFT" or "RIGHT", -6, 0)
		title:SetJustifyH("LEFT")
		title:SetWordWrap(false)
		if title.SetMaxLines then title:SetMaxLines(1) end
	end
	if close then
		close:ClearAllPoints()
		close:SetPoint("RIGHT", header, "RIGHT", -8, 0)
	end
end

-- Settling --------------------------------------------------------------------
-- Blizzard lays a window out again when it shows (and some parts a frame
-- later), so each dressed window has one settle step: the band takes its
-- height from where content now starts, Blizzard's border art is hidden
-- again, the title and close are seated, then any extra steps a skin
-- registered with Windows:OnSettle. It runs on show and on the next frame.

local function insetGap(frame)
	local inset = frame.Inset
	if not (inset and inset.GetTop and frame.GetTop) then return nil end
	local top, start = frame:GetTop(), inset:GetTop()
	if Stoa:IsSecret(top) or Stoa:IsSecret(start) or not top or not start then return nil end
	return top - start
end

local function bandHeight(frame)
	local gap = insetGap(frame)
	-- A dark strip holds the title row and every control Blizzard puts
	-- under it, down to where the content starts.
	-- Blizzard's windows: a dark header of one set height that holds the
	-- title; their tabs and buttons sit below it.
	-- Bags keep the compact row (their slots start near the top), and a
	-- window can ask for more room (the character sheet's two lines).
	if frame.stoaPlainHeader then
		local name = frame.GetName and frame:GetName() or ""
		if name:find("^ContainerFrame") then return HEADER_FALLBACK end
		return tonumber(frame.stoaBandHeight) or PLAIN_HEADER
	end
	if not gap then return nil end
	-- A window with a two-line header asks for more (frame.stoaBandHeight).
	-- "inset" makes the band reach all the way down to where content starts.
	if frame.stoaBandHeight == "inset" and gap >= HEADER_FALLBACK then return math.floor(gap + 0.5) end
	local want = tonumber(frame.stoaBandHeight) or BAND
	if gap >= want then return want end
	return nil
end

-- How far this window's header rises: Blizzard windows with the metal
-- header, except bags (stacked on each other) and the map filling the
-- screen (no room above it).
local function raiseOf(frame)
	if not frame.stoaPlainHeader then return 0 end
	local name = frame.GetName and frame:GetName() or ""
	if name:find("^ContainerFrame") then return 0 end
	local map = _G.WorldMapFrame
	if map and frame == map.BorderFrame and map.IsMaximized and map:IsMaximized() then return 0 end
	return tonumber(frame.stoaRaise) or RAISE
end

-- Lifts the panel's fill and edge with the header.
local function liftPanel(frame, raise)
	-- The map's fill lives on the map frame under its border frame (the
	-- canvas sits between them); it rises with the border's header too, or
	-- the raised strip shows the world through it.
	local map = _G.WorldMapFrame
	local mapFill = map and frame == map.BorderFrame and map.stoaMapFill
	-- (ipairs stops at a missing piece, so the parts are gathered first.
	-- Matte's moulding rises too: left behind, its top light drew a second
	-- header edge across the band.)
	local parts = {}
	for _, tex in pairs({ frame.stoaPanelBg, frame.stoaPanelEdge and frame.stoaPanelEdge.edges and frame.stoaPanelEdge.edges[1] or false, frame.stoaMould or false, mapFill or false }) do
		if tex then parts[#parts + 1] = tex end
	end
	for _, tex in ipairs(parts) do
		if tex and tex.SetTextureSliceMargins then
			tex:SetPoint("TOPLEFT", 0, raise)
		end
	end
	-- The raised strip lies outside the window's own edge, so a click (or a
	-- Shift-drag to move it) on its top part went through to the world:
	-- the window's clickable area reaches up to cover it.
	if frame.SetHitRectInsets and frame.GetHitRectInsets and not mapFill and not InCombatLockdown() then
		local left, right, _, bottom = frame:GetHitRectInsets()
		pcall(frame.SetHitRectInsets, frame, left or 0, right or 0, -raise, bottom or 0)
	end
end

function Windows:Settle(frame)
	if not frame or InCombatLockdown() then return end
	hide(frame.NineSlice)
	hide(frame.PortraitContainer)
	-- Guild & Communities draws its guild tabard or club icon on its own
	-- overlay, above the title.
	hide(frame.PortraitOverlay)
	local header = frame.stoaHeader
	local height = header and bandHeight(frame)
	local raise = header and raiseOf(frame) or 0
	if height and (header.stoaHeight ~= height or header.stoaRaise ~= raise) then
		header:ClearAllPoints()
		header:SetPoint("TOPLEFT", 0, raise)
		header:SetPoint("TOPRIGHT", 0, raise)
		header:SetHeight(height + raise)
		header.stoaHeight, header.stoaRaise = height, raise
		liftPanel(frame, raise)
	end
	local name = frame.GetName and frame:GetName()
	if not frame.stoaBorderOnly then
		pcall(seatTitle, frame, titleOf(frame), frame.CloseButton or (name and _G[name .. "CloseButton"]))
	elseif frame.stoaPlainHeader then
		-- Border-only windows keep their own buttons; only the title moves
		-- onto the metal.
		pcall(seatTitle, frame, titleOf(frame), nil)
	end
	for _, step in ipairs(frame.stoaSettlers or {}) do
		xpcall(step, Stoa.catch, frame)
	end
end

-- Adds a step to a window's settle (it runs now if the window is shown).
function Windows:OnSettle(frame, step)
	if not frame then return end
	frame.stoaSettlers = frame.stoaSettlers or {}
	table.insert(frame.stoaSettlers, step)
	if frame:IsShown() then xpcall(step, Stoa.catch, frame) end
end

function Windows:KeepSettled(frame)
	if not frame or frame.stoaSettling or not frame.HookScript then return end
	frame.stoaSettling = true
	frame:HookScript("OnShow", function(self)
		Windows:Settle(self)
		C_Timer.After(0, function() Windows:Settle(self) end)
	end)
end

-- The common window: no portrait, no stone border, a Stoa panel with a
-- header band, a dark footer tray below Blizzard's inset, and the title in
-- the header.
function Windows:Dress(frame)
	if not frame or frame.stoaDressed or self:Leaves(frame) then return end
	frame.stoaDressed = true
	strip(frame)
	for _, key in ipairs({ "NineSlice", "Bg", "TopTileStreaks", "PortraitContainer", "PortraitOverlay", "portrait", "PortraitFrame" }) do
		hide(frame[key])
	end
	if frame.TitleContainer then strip(frame.TitleContainer) end
	local inset = frame.Inset
	if inset then
		strip(inset)
		hide(inset.NineSlice)
		hide(inset.Bg)
	end
	local name = frame.GetName and frame:GetName()
	local title = titleOf(frame)
	UI.windowPanel(frame, nil, {
		header = inset or (title and HEADER_FALLBACK) or nil,
		footer = inset,
		family = FAMILY[name or ""],
		-- Blizzard's windows carry a lot in their top strip already (tabs,
		-- buttons, search), so the title sits on the panel without a band.
		plainHeader = true,
	})

	if title then
		Stoa:SetFont(title, "serif", Stoa.typeSize.title)
		title:SetTextColor(Stoa:Color("text"))
	end

	local close = frame.CloseButton or (name and _G[name .. "CloseButton"])
	dressClose(close)
	pcall(seatTitle, frame, title, close)
	dressButtonsIn(frame, 5)
	dressTabs(frame)
	hookTabs()
	self:KeepSettled(frame)
	self:Settle(frame)
end

-- Quest text ----------------------------------------------------------------

local function light(fs, title)
	if not (fs and fs.SetTextColor) then return end
	if title then
		fs:SetTextColor(Stoa:Color("accent"))
	else
		fs:SetTextColor(Stoa:Color("text"))
	end
end

-- Quest titles in the gossip and quest greeting lists carry their colour in
-- the text itself (NORMAL_QUEST_DISPLAY is "|cff000000%s|r", black for the
-- parchment), so a text colour alone can't lift them. The black code is
-- taken out; other colours (trivial, ignored) stay.
local function unblack(button)
	if not (button and button.GetText and button.SetText) then return end
	local text = button:GetText()
	if type(text) ~= "string" or Stoa:IsSecret(text) then return end
	local clean, found = text:gsub("|[cC][fF][fF]000000", "")
	if found > 0 then button:SetText(clean) end
	local fs = button.GetFontString and button:GetFontString()
	if fs then light(fs) end
end

local function unblackAll(parent, depth)
	if not (parent and parent.GetChildren) or (depth or 0) > 4 then return end
	for _, child in ipairs({ parent:GetChildren() }) do
		if not forbidden(child) then
			if child.IsObjectType and child:IsObjectType("Button") then unblack(child) end
			unblackAll(child, (depth or 0) + 1)
		end
	end
end

-- Blizzard picks text colours to suit the parchment; on a dark panel they
-- need to be light, so every colour it sets is set again.
-- The map's quest log shows the same quest text on Blizzard's parchment,
-- which Stoa leaves alone, so its dark colours stay there.
local function onParchment()
	return QuestInfoFrame and QuestInfoFrame.questLog
end

-- The quest window's own words (turn-in progress, the greeting list) are
-- never on that parchment. They are lit whatever the map's log last
-- showed: the log's flag stays set after it closes, which left a turn-in
-- in the parchment's dark brown now and then.
local OWN_TITLES = { "QuestProgressTitleText" }
local OWN_TEXT = {
	"QuestProgressText", "QuestProgressRequiredItemsText", "QuestProgressRequiredMoneyText",
	"GreetingText", "CurrentQuestsText", "AvailableQuestsText",
}

local function ownText(fs)
	for _, list in ipairs({ OWN_TITLES, OWN_TEXT }) do
		for _, name in ipairs(list) do
			if _G[name] == fs then return true end
		end
	end
	return false
end

local function lightQuestText()
	if QuestFrame_SetTitleTextColor then
		hooksecurefunc("QuestFrame_SetTitleTextColor", function(fs) if not onParchment() or ownText(fs) then light(fs, true) end end)
	end
	if QuestFrame_SetTextColor then
		hooksecurefunc("QuestFrame_SetTextColor", function(fs) if not onParchment() or ownText(fs) then light(fs) end end)
	end
	local function recolour()
		for _, name in ipairs(OWN_TITLES) do light(_G[name], true) end
		for _, name in ipairs(OWN_TEXT) do light(_G[name]) end
		if onParchment() then return end
		for _, name in ipairs({ "QuestInfoTitleHeader", "QuestInfoDescriptionHeader", "QuestInfoObjectivesHeader" }) do
			light(_G[name], true)
		end
		for _, name in ipairs({ "QuestInfoDescriptionText", "QuestInfoObjectivesText", "QuestInfoGroupSize", "QuestInfoRewardText" }) do
			light(_G[name])
		end
		local rewards = QuestInfoRewardsFrame
		if rewards then
			light(rewards.Header, true)
			light(rewards.ItemChooseText)
			light(rewards.ItemReceiveText)
			light(rewards.PlayerTitleText)
			if rewards.XPFrame then light(rewards.XPFrame.ReceiveText) end
		end
		local objectives = QuestInfoObjectivesFrame and QuestInfoObjectivesFrame.Objectives
		for _, line in ipairs(objectives or {}) do light(line) end
	end
	if QuestInfo_Display then hooksecurefunc("QuestInfo_Display", recolour) end
	if QuestFrameProgressItems_Update then hooksecurefunc("QuestFrameProgressItems_Update", recolour) end
	if QuestFrameProgressPanel then QuestFrameProgressPanel:HookScript("OnShow", recolour) end
	if QuestFrameGreetingPanel then
		QuestFrameGreetingPanel:HookScript("OnShow", recolour)
		-- Its title buttons are filled in as it shows.
		QuestFrameGreetingPanel:HookScript("OnShow", function(panel)
			C_Timer.After(0, function() xpcall(unblackAll, Stoa.catch, panel) end)
		end)
	end
end

-- Quest fonts in Stoa's type: titles in the display face, body in Inter.
local function questFonts()
	local display, sans = Stoa.fonts.serif[1], Stoa.fonts.sans[1]
	-- Slate sets every word in the sans, titles too.
	if UI.slate() then display = sans end
	local function face(fontObject, file, size)
		if fontObject and fontObject.SetFont then pcall(fontObject.SetFont, fontObject, file[1], size * file[2], "") end
	end
	face(QuestTitleFont, display, 18)
	face(QuestTitleFontBlackShadow, display, 18)
	face(QuestFont, sans, 13)
	face(QuestFontNormalSmall, sans, 12)
end

-- Slate sets every word in Inter. The game's own windows, tracker and
-- lists draw from a handful of base fonts, so those take STOA's face and
-- keep their own sizes and outlines. (Picking another Style reloads, which
-- gives the game's faces back.)
local BASE_FONTS = {
	"SystemFont_Tiny", "SystemFont_Tiny2", "SystemFont_Small", "SystemFont_Small2", "SystemFont_Med1", "SystemFont_Med2",
	"SystemFont_Med3", "SystemFont_Large", "SystemFont_Large2", "SystemFont_Huge1", "SystemFont_Huge2",
	"SystemFont_Shadow_Small", "SystemFont_Shadow_Small2", "SystemFont_Shadow_Med1", "SystemFont_Shadow_Med2",
	"SystemFont_Shadow_Med3", "SystemFont_Shadow_Large", "SystemFont_Shadow_Large2", "SystemFont_Shadow_Huge1",
	"SystemFont_Shadow_Huge2", "SystemFont_Outline_Small", "SystemFont_Outline", "SystemFont_Shadow_Outline_Small",
	"Game10Font_o1", "Game11Font", "Game12Font", "Game13Font", "Game13FontShadow", "Game15Font", "Game16Font",
	"Game18Font", "Game20Font", "Game24Font", "Game27Font", "ObjectiveFont", "ObjectiveTrackerFont12",
	"ObjectiveTrackerFont13", "ObjectiveTrackerFont14", "ObjectiveTrackerHeaderFont", "ObjectiveTrackerLineFont",
	"QuestFont_Large", "QuestFont_Shadow_Small", "QuestFont_Huge", "QuestFont_Shadow_Huge", "QuestFont_Super_Huge",
	"Fancy12Font", "Fancy14Font", "Fancy16Font", "Fancy18Font", "Fancy20Font", "Fancy22Font", "Fancy24Font",
	"FriendsFont_Normal", "FriendsFont_Small", "FriendsFont_Large", "FriendsFont_UserText", "FriendsFont_11",
	"GameFontNormal", "GameFontNormalSmall", "GameFontNormalMed1", "GameFontNormalMed2", "GameFontNormalMed3",
	"GameFontNormalLarge", "GameFontNormalHuge", "GameFontHighlight", "GameFontHighlightSmall",
	"GameFontHighlightSmall2", "GameFontHighlightMedium", "GameFontHighlightLarge", "GameFontHighlightHuge",
	"GameFontDisable", "GameFontDisableSmall", "GameFontDisableLarge", "GameFontWhite", "GameFontWhiteSmall",
	"MailFont_Large", "InvoiceFont_Med", "InvoiceFont_Small", "ReputationDetailFont", "AchievementFont_Small",
}
local function slateFonts()
	local file = Stoa.fonts.sans[1]
	if not file then return end
	for _, name in ipairs(BASE_FONTS) do
		local object = rawget(_G, name)
		if type(object) == "table" and object.GetFont and object.SetFont then
			local _, size, flags = object:GetFont()
			if type(size) == "number" and size > 0 then pcall(object.SetFont, object, file[1], size, flags or "") end
		end
	end
end

local function dressQuest()
	local frame = QuestFrame
	if not frame then return end
	Windows:Dress(frame)
	for _, name in ipairs({ "QuestFrameDetailPanel", "QuestFrameProgressPanel", "QuestFrameRewardPanel", "QuestFrameGreetingPanel" }) do
		local panel = _G[name]
		strip(panel)
		if panel then hide(panel.Bg) hide(panel.SealMaterialBG) hide(panel.MaterialTopLeft) end
	end
	for _, name in ipairs({ "QuestDetailScrollFrame", "QuestProgressScrollFrame", "QuestRewardScrollFrame", "QuestGreetingScrollFrame" }) do
		strip(_G[name])
	end
	-- The rewards sit together in a darker well.
	if QuestInfoRewardsFrame then UI.well(QuestInfoRewardsFrame, 4) end
	lightQuestText()
end

-- Gossip: the greeting and option lines live in a scroll box that remakes
-- its rows, so each row is recoloured as it's laid out.
local function dressGossip()
	local frame = GossipFrame
	if not frame then return end
	Windows:Dress(frame)
	local greeting = frame.GreetingPanel
	if not greeting then return end
	strip(greeting)
	local box = greeting.ScrollBox
	local function recolour()
		if not (box and box.ForEachFrame) then return end
		box:ForEachFrame(function(row)
			light(row.GreetingText)
			if row.GetFontString and row:GetFontString() then light(row:GetFontString()) end
			-- Quest rows set their title again whenever the quest updates.
			if row.UpdateTitleForQuest and not row.stoaUnblack then
				row.stoaUnblack = true
				hooksecurefunc(row, "UpdateTitleForQuest", unblack)
			end
			unblack(row)
		end)
	end
	if frame.Update then hooksecurefunc(frame, "Update", recolour) end
	-- The gossip frame is a theme container: it colours each line for the
	-- parchment as it registers it, after the rows are laid out.
	if frame.RegisterFontString then
		hooksecurefunc(frame, "RegisterFontString", function(_, fs) light(fs) end)
	end
	if box and box.RegisterCallback and ScrollBoxListMixin and ScrollBoxListMixin.Event then
		box:RegisterCallback(ScrollBoxListMixin.Event.OnDataRangeChanged, recolour, Windows)
	end
	frame:HookScript("OnShow", recolour)
end

local function dressMerchant()
	local frame = MerchantFrame
	if not frame then return end
	Windows:Dress(frame)
	for _, name in ipairs({ "MerchantFrameInset", "MerchantMoneyInset", "MerchantMoneyBg", "MerchantExtraCurrencyInset", "MerchantExtraCurrencyBg" }) do
		local part = _G[name]
		strip(part)
		if part then hide(part.NineSlice) hide(part.Bg) end
	end
	strip(frame.BottomInset)
	for i = 1, 12 do
		hide(_G["MerchantItem" .. i .. "SlotTexture"])
		hide(_G["MerchantItem" .. i .. "NameFrame"])
	end
	hide(MerchantBuyBackItemSlotTexture)
	hide(MerchantBuyBackItemNameFrame)
	-- The page turners: Blizzard's framed arrows and gold words become a
	-- chevron and a quiet word, dim when there is no page that way.
	local page = rawget(_G, "MerchantPageText")
	if page and page.SetTextColor then
		Stoa:SetFont(page, "sans", Stoa.typeSize.caption)
		page:SetTextColor(Stoa:Color("muted"))
	end
	for name, turn in pairs({ MerchantPrevPageButton = math.pi, MerchantNextPageButton = 0 }) do
		local button = rawget(_G, name)
		if type(button) == "table" and button.CreateTexture and not forbidden(button) and not button.stoaTurn then
			button.stoaTurn = true
			local words = {}
			for _, region in ipairs({ button:GetRegions() }) do
				local kind = region.GetObjectType and region:GetObjectType()
				if kind == "Texture" then
					region:SetAlpha(0)
				elseif kind == "FontString" then
					Stoa:SetFont(region, "sans", Stoa.typeSize.body)
					words[#words + 1] = region
				end
			end
			local glyph = UI.glyph(button, "Chevron", 12, "text")
			glyph:SetPoint("CENTER")
			glyph:SetRotation(turn)
			local function paint()
				local on = not button.IsEnabled or button:IsEnabled()
				local token = on and (button:IsMouseOver() and "accent" or "text") or "muted"
				local r, g, b = Stoa:Color(token)
				glyph:SetVertexColor(r, g, b, on and 1 or 0.4)
				for _, word in ipairs(words) do word:SetTextColor(r, g, b, on and 1 or 0.4) end
			end
			-- The word beside the arrow turns the page too.
			local left, right = 0, 0
			for _, word in ipairs(words) do
				local reach = math.ceil(word:GetStringWidth() or 0) + 10
				local wx, bx = word:GetCenter(), button:GetCenter()
				if (wx and bx and wx < bx) or (not wx and turn == 0) then left = reach else right = reach end
			end
			if button.SetHitRectInsets then button:SetHitRectInsets(-left, -right, -4, -4) end
			button:HookScript("OnEnter", paint)
			button:HookScript("OnLeave", paint)
			button:HookScript("OnShow", paint)
			for _, method in ipairs({ "Enable", "Disable", "SetEnabled" }) do
				if button[method] then hooksecurefunc(button, method, paint) end
			end
			paint()
		end
	end
end

-- One trainer row (and the skill-step row above the list): Blizzard's
-- framed row art goes, the hover and the chosen row become soft washes.
local function dressTrainerRow(button)
	if not button or button.stoaRow then return end
	button.stoaRow = true
	local normal = button.GetNormalTexture and button:GetNormalTexture()
	if normal then normal:SetAlpha(0) end
	local over = button.GetHighlightTexture and button:GetHighlightTexture()
	if over then
		over:SetTexture(UI.WHITE)
		over:SetTexCoord(0, 1, 0, 1)
		over:SetBlendMode("BLEND")
		over:SetVertexColor(1, 1, 1, 0.05)
	end
	local chosen = button.selectedTex
	if chosen then
		chosen:SetTexture(UI.WHITE)
		chosen:SetTexCoord(0, 1, 0, 1)
		chosen:SetBlendMode("BLEND")
		chosen:ClearAllPoints()
		chosen:SetAllPoints(button)
		chosen:SetDrawLayer("BACKGROUND", 1)
		local r, g, b = Stoa:Color("accent")
		chosen:SetVertexColor(r, g, b, 0.12)
	end
	if button.disabledBG then button.disabledBG:SetAlpha(0) end
	if button.icon and not button.stoaRim then
		button.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
		button.stoaRim = UI.roundBorder(button, "CardEdge.tga", 1)
	end
end

-- The skill bar under the title: a thin rounded STOA bar, the numbers in
-- STOA's type, Blizzard's framed blue bar gone.
local TRAINER_BAR_ROOM = 14

local function dressTrainerBar()
	local bar = ClassTrainerStatusBar
	if not bar or bar.stoaDressed then return end
	bar.stoaDressed = true
	for _, suffix in ipairs({ "Left", "Right", "Middle" }) do hide(_G["ClassTrainerStatusBar" .. suffix]) end
	local ground = _G.ClassTrainerStatusBarBackground
	if ground then
		ground:SetColorTexture(1, 1, 1, 1)
		ground:SetVertexColor(0, 0, 0, 0.45)
	end
	bar:SetStatusBarTexture(UI.WHITE)
	local r, g, b = Stoa:Color("accent")
	bar:SetStatusBarColor(r, g, b, 0.55)
	bar:SetHeight(14)
	local rank = bar.rankText or _G.ClassTrainerStatusBarSkillRank
	if rank then
		Stoa:SetFont(rank, "sans", Stoa.typeSize.caption)
		rank:SetTextColor(Stoa:Color("text"))
		rank:SetShadowOffset(1, -1)
		rank:SetShadowColor(0, 0, 0, 0.8)
	end
end

-- The Settings dropdown: a quiet word with a chevron, no button art,
-- warming to the accent under the mouse (it lives in the footer).
local function dressDropdownButton(dropdown)
	if not dropdown or dropdown.stoaDressed then return end
	dropdown.stoaDressed = true
	if dropdown.Background then dropdown.Background:SetAlpha(0) end
	dropdown.resizeToText = false
	dropdown:SetSize(76, 22)
	local chevron = UI.text(dropdown, "sans", Stoa.typeSize.label, "muted", "RIGHT")
	chevron:SetPoint("RIGHT", -2, 0)
	chevron:SetText("›")
	local function paint(over)
		local text = dropdown.Text
		if text then
			Stoa:SetFont(text, "sans", Stoa.typeSize.label)
			text:SetShadowOffset(0, 0)
			text:SetJustifyH("RIGHT")
			text:ClearAllPoints()
			text:SetPoint("RIGHT", chevron, "LEFT", -5, 0)
			text:SetTextColor(Stoa:Color(over and "accent" or "muted"))
		end
		chevron:SetTextColor(Stoa:Color(over and "accent" or "muted"))
	end
	dropdown:HookScript("OnEnter", function() paint(true) end)
	dropdown:HookScript("OnLeave", function() paint(false) end)
	dropdown:HookScript("OnShow", function() paint(false) end)
	dropdown:HookScript("OnMouseUp", function() paint(dropdown:IsMouseOver()) end)
	paint(false)
end

local function dressTrainer()
	local frame = ClassTrainerFrame
	if not frame or frame.stoaTrainer then return end
	frame.stoaTrainer = true
	Windows:Dress(frame)
	stripInside(frame, 4)
	dressTrainerBar()
	dressDropdownButton(frame.FilterDropdown)
	dressTrainerRow(frame.skillStepButton)
	local box = frame.ScrollBox
	local function rows()
		if box and box.ForEachFrame then box:ForEachFrame(function(row) Stoa.safe.guarded(dressTrainerRow, row) end) end
	end
	if box and box.RegisterCallback and ScrollBoxListMixin and ScrollBoxListMixin.Event then
		box:RegisterCallback(ScrollBoxListMixin.Event.OnDataRangeChanged, rows, Windows)
	end
	frame:HookScript("OnShow", rows)
	rows()
	-- Blizzard hangs its Settings/Filters dropdown at the top right, over
	-- the trainer's name (often a long one). It moves down into the footer,
	-- just left of Train.
	Windows:OnSettle(frame, function()
		local dropdown, train = frame.FilterDropdown, frame.TrainButton
		if dropdown and train and dropdown.ClearAllPoints then
			dropdown:ClearAllPoints()
			dropdown:SetPoint("RIGHT", train, "LEFT", -12, 0)
			if dropdown.GetFrameLevel and train.GetFrameLevel and dropdown:GetFrameLevel() < train:GetFrameLevel() then
				dropdown:SetFrameLevel(train:GetFrameLevel())
			end
		end
		-- The skill bar leaves the header for a full-width row of its own
		-- above the list: the list and the window grow down to make room.
		local bar, inset = ClassTrainerStatusBar, frame.Inset
		if bar and inset and not frame.stoaBarRow and not InCombatLockdown() then
			local point, rel, relPoint, x, y
			for i = 1, (inset.GetNumPoints and inset:GetNumPoints() or 1) do
				point, rel, relPoint, x, y = inset:GetPoint(i)
				if point == "TOPLEFT" then break end
			end
			if point == "TOPLEFT" and type(y) == "number" then
				frame.stoaBarRow = true
				inset:SetPoint(point, rel, relPoint, x, y - TRAINER_BAR_ROOM)
				frame:SetHeight(frame:GetHeight() + TRAINER_BAR_ROOM)
				bar:ClearAllPoints()
				bar:SetPoint("TOPLEFT", frame, "TOPLEFT", 14, y + 6)
				bar:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -14, y + 6)
				-- With a skill step (the next rank) shown, Blizzard ends the
				-- top list a set distance from the window's top; that end
				-- moves down with it, or the step row covers the list.
				local function lowerStepRow()
					if not (frame.bottomInset and frame.bottomInset:IsShown()) or InCombatLockdown() then return end
					for i = 1, (inset.GetNumPoints and inset:GetNumPoints() or 1) do
						local p, r, rp, px, py = inset:GetPoint(i)
						if p == "BOTTOMRIGHT" and rp == "TOPRIGHT" and type(py) == "number" then
							inset:SetPoint(p, r, rp, px, py - TRAINER_BAR_ROOM)
							break
						end
					end
				end
				if _G.ClassTrainerFrame_Update then
					hooksecurefunc("ClassTrainerFrame_Update", function() Stoa.safe.guarded(lowerStepRow) end)
				end
				lowerStepRow()
			end
		end
		-- Your money sits at the left of the footer, level with Train.
		local money = frame.money
		if money and money.ClearAllPoints then
			local lift = train and train.GetHeight and (train:GetHeight() / 2) or 11
			money:ClearAllPoints()
			money:SetPoint("LEFT", frame, "BOTTOMLEFT", 14, lift)
		end
	end)
end

Windows.DressTrainer = dressTrainer

local function dressBags()
	if ContainerFrameCombinedBags then Windows:Dress(ContainerFrameCombinedBags) end
	for i = 1, 13 do
		local bag = _G["ContainerFrame" .. i]
		if bag then Windows:Dress(bag) end
	end
end

-- Tooltips: the same dark rounded panel, a thin health bar, and the
-- default spot lifted to sit above the console's right corner instead of
-- over it.
-- (A chat link's tooltip has compare tooltips of its own, the Equipped
-- ones beside it, and a close button.)
local TOOLTIPS = { "GameTooltip", "ItemRefTooltip", "ShoppingTooltip1", "ShoppingTooltip2", "ItemRefShoppingTooltip1", "ItemRefShoppingTooltip2", "EmbeddedItemTooltip" }
local TOOLTIP_GAP = 16

local function dressTooltip(tip)
	if not tip or tip.stoaDressed then return end
	tip.stoaDressed = true
	hide(tip.NineSlice)
	UI.surface(tip, "card", { alpha = 0.96 })
	-- Blizzard re-applies its backdrop style each time a tooltip shows.
	tip:HookScript("OnShow", function(self) hide(self.NineSlice) end)
	-- A compare tooltip's "Equipped" tab: its gold-edged plate goes and the
	-- word sits on the tooltip's own dark card.
	local tab = tip.CompareHeader
	if tab and tab.GetRegions and not (tab.IsForbidden and tab:IsForbidden()) then
		for _, region in ipairs({ tab:GetRegions() }) do
			if region.IsObjectType and region:IsObjectType("Texture") then hide(region) end
		end
		pcall(UI.surface, tab, "card", { alpha = 0.96 })
		if tab.Label then tab.Label:SetTextColor(Stoa:Color("muted")) end
	end
end

-- Dropdown menus (the minimap's tracking list, the friends status, every
-- right-click menu): Blizzard's menus come from one shared pool and get
-- their gold-edged background drawn again each time they open, so each
-- menu, and each submenu, takes the tooltip's dark card when it opens.
-- Only the menu's own background goes; its lines, ticks and icons stay.
-- Forever's menus are guarded proxies: they refuse new textures (the
-- card can't be drawn on them), so STOA's card is a frame of its own,
-- a child of the menu at the menu's level (the lines sit above it), and
-- the menu's own art is faded out each time it opens.
local menuCards = setmetatable({}, { __mode = "k" })

local function menuCard(menu)
	local card = menuCards[menu]
	if card then return card end
	local ok, made = pcall(CreateFrame, "Frame", nil, menu)
	if not (ok and made) then return nil end
	card = made
	card:SetPoint("TOPLEFT", menu, "TOPLEFT", 0, 0)
	card:SetPoint("BOTTOMRIGHT", menu, "BOTTOMRIGHT", 0, 7)
	card:EnableMouse(false)
	UI.surface(card, "card", { alpha = 0.96 })
	menuCards[menu] = card
	return card
end

local function dressMenu(menu)
	if type(menu) ~= "table" or not menu.GetRegions or forbidden(menu) then return end
	local card = menuCard(menu)
	if not card then return end
	pcall(card.SetFrameLevel, card, menu:GetFrameLevel())
	card:Show()
	for _, region in ipairs({ menu:GetRegions() }) do
		if region.IsObjectType and region:IsObjectType("Texture") then region:SetAlpha(0) end
	end
end

-- One hook that may fail on its own without taking the others with it:
-- the menu manager is a guarded proxy that can refuse new fields.
local function tryHook(owner, method, fn)
	if type(owner) ~= "table" or type(owner[method]) ~= "function" then return end
	local ok, err = pcall(hooksecurefunc, owner, method, fn)
	if not ok then Stoa.catch(err) end
end

-- The game menu (Esc). It stays out of Windows:Dress (LEAVE): its buttons
-- lead to Edit Mode, Log Out and Exit, so nothing of Blizzard's is moved,
-- resized, reparented or given new fields here. STOA only lays a card
-- behind it, fades Blizzard's art and paints dark keys over the red
-- buttons. The menu takes its buttons from a pool and sets their scripts
-- afresh each time it opens, so the keys are painted after each build.
local menuKeys = setmetatable({}, { __mode = "k" })
local function paintMenuKey(button, over)
	local key = menuKeys[button]
	if not key then return end
	for _, part in ipairs(PANEL_PARTS) do hide(button[part]) end
	local lit = button.GetHighlightTexture and button:GetHighlightTexture()
	if lit then lit:SetAlpha(0) end
	local enabled = not button.IsEnabled or button:IsEnabled()
	local text = button.GetFontString and button:GetFontString()
	if text then
		Stoa:SetFont(text, "sans", Stoa.typeSize.label)
		text:SetShadowOffset(0, 0)
		text:SetTextColor(Stoa:Color(not enabled and "muted" or over and "accent" or "text"))
	end
	local hot = over and enabled
	key.lift:SetShown(hot)
	if key.edge then
		local r, g, b = Stoa:Color("accent")
		key.edge:SetVertexColor(r, g, b, 0.85)
		key.edge:SetShown(hot)
	end
end

-- A key is a flat plate with a 2 pixel corner and no gloss (MatteKey.tga,
-- Tools/art/matte_key.py): light caught on its top edge, shade along its
-- foot and a dark line under it, all inside the button, since the menu's
-- keys touch within a group. Returns the plate's hover parts.
local KEY_SLICE = 5
local function raiseMenuKey(button)
	local plate = UI.sliced(button, "BACKGROUND", "MatteKey.tga", 0, KEY_SLICE)
	if plate then plate:SetDrawLayer("BACKGROUND", -8) end
	-- Under the mouse the face lifts a shade and its outline shows.
	local lift = button:CreateTexture(nil, "BACKGROUND", nil, -7)
	lift:SetPoint("TOPLEFT", 2, -2)
	lift:SetPoint("BOTTOMRIGHT", -2, 4)
	lift:SetColorTexture(1, 1, 1, 0.05)
	lift:Hide()
	local edge = UI.sliced(button, "OVERLAY", "MatteKeyEdge.tga", 0, KEY_SLICE)
	if edge then edge:Hide() end
	return { lift = lift, edge = edge }
end

local function dressMenuKey(button)
	if type(button) ~= "table" or forbidden(button) then return end
	if not menuKeys[button] then
		menuKeys[button] = raiseMenuKey(button)
	end
	-- Blizzard cleared these scripts when it built the button, so each
	-- build hooks them once.
	button:HookScript("OnEnter", function(own) paintMenuKey(own, true) end)
	button:HookScript("OnLeave", function(own) paintMenuKey(own, false) end)
	paintMenuKey(button, false)
end

local function dressGameMenu()
	local menu = rawget(_G, "GameMenuFrame")
	if type(menu) ~= "table" or forbidden(menu) or type(menu.InitButtons) ~= "function" then return end
	local card
	local function dress()
		if not card then
			card = CreateFrame("Frame", nil, menu)
			card:SetAllPoints(menu)
			card:EnableMouse(false)
			UI.surface(card, "card", { alpha = 1 })
			-- Depth: a soft shadow thrown on the world around the block.
			UI.roundBorder(card, "CardGlow.tga", 3, 3):Set(0, 0, 0, 0.75)
		end
		card:SetFrameLevel(menu:GetFrameLevel())
		if menu.Border and menu.Border.SetAlpha then menu.Border:SetAlpha(0) end
		local header = menu.Header
		if header then
			for _, part in ipairs({ "LeftBG", "RightBG", "CenterBG" }) do hide(header[part]) end
			local title = header.Text
			if title and title.SetTextColor then
				Stoa:SetFont(title, "serif", Stoa.typeSize.name)
				title:SetShadowOffset(0, 0)
				title:SetTextColor(Stoa:Color("text"))
				title:ClearAllPoints()
				title:SetPoint("TOP", menu, "TOP", 0, -17)
			end
		end
		for _, button in ipairs(menu.buttons or {}) do dressMenuKey(button) end
	end
	tryHook(menu, "InitButtons", function() xpcall(dress, Stoa.catch) end)
end

local function dressMenus()
	local manager = type(Menu) == "table" and type(Menu.GetManager) == "function" and Menu.GetManager()
	-- A dropdown keeps its description between openings, so its submenu
	-- callback is added once.
	local watched = setmetatable({}, { __mode = "k" })
	local function opened(own, _, description)
		dressMenu(own:GetOpenMenu())
		-- Submenus open later from the same description.
		if type(description) == "table" and not watched[description] and description.AddMenuAcquiredCallback then
			watched[description] = true
			description:AddMenuAcquiredCallback(function(menu) xpcall(dressMenu, Stoa.catch, menu) end)
		end
	end
	if type(manager) == "table" then
		for _, method in ipairs({ "OpenMenu", "OpenContextMenu" }) do tryHook(manager, method, opened) end
	end
	-- Right-click menus on unit frames (the target's, the party's) open
	-- through the game's secure unit code, past the hooks above. Every menu
	-- draws its gold box from its style's Generate, so the dress follows
	-- that too. Each style mixin copied Generate when made, so each is
	-- hooked on its own.
	for _, name in ipairs({ "MenuStyle1Mixin", "MenuStyle1ThinMixin", "MenuStyle2Mixin" }) do
		local style = rawget(_G, name)
		tryHook(style, "Generate", function(menu) xpcall(dressMenu, Stoa.catch, menu) end)
	end
	local variants = rawget(_G, "MenuVariants")
	if type(variants) ~= "table" then return end
	-- The lines inside: a faint light under the mouse instead of the gold
	-- glow, ticks and radio marks in the accent, the submenu arrow quiet.
	local function quiet(tex, token, alpha)
		if not (tex and tex.SetDesaturated) then return end
		tex:SetDesaturated(true)
		local r, g, b = Stoa:Color(token)
		tex:SetVertexColor(r, g, b, alpha or 1)
	end
	do
		tryHook(variants, "CreateHighlight", function(frame)
			local light = type(frame) == "table" and frame.highlight
			if not (light and light.SetTexture) then return end
			-- The soft alpha lives in the colour itself, so a later
			-- SetVertexColor(1, 1, 1) can't turn it into a bright bar.
			light:SetColorTexture(1, 1, 1, 0.06)
			light:SetBlendMode("BLEND")
		end)
	end
	for _, method in ipairs({ "CreateCheckbox", "CreateRadio" }) do
		do
			tryHook(variants, method, function(_, frame, isSelected, data)
				local mark = type(frame) == "table" and frame.leftTexture1
				if not mark then return end
				local ok, chosen = pcall(isSelected, data)
				quiet(mark, (ok and chosen) and "accent" or "muted", (ok and chosen) and 1 or 0.6)
			end)
		end
	end
	do
		tryHook(variants, "CreateSubmenuArrow", function(frame)
			quiet(type(frame) == "table" and frame.arrow, "muted")
		end)
	end
end

local function dressTooltips()
	for _, name in ipairs(TOOLTIPS) do dressTooltip(_G[name]) end
	local link = _G.ItemRefTooltip
	if link then pcall(dressClose, link.CloseButton or _G.ItemRefCloseButton) end
	local bar = GameTooltipStatusBar
	if bar then
		bar:SetStatusBarTexture(UI.WHITE)
		bar:SetHeight(3)
		bar:ClearAllPoints()
		bar:SetPoint("TOPLEFT", GameTooltip, "BOTTOMLEFT", 8, -3)
		bar:SetPoint("TOPRIGHT", GameTooltip, "BOTTOMRIGHT", -8, -3)
		UI.surface(bar, "well", { outset = 1 })
		hooksecurefunc(bar, "SetStatusBarColor", function(self)
			if self.stoaColouring then return end
			self.stoaColouring = true
			self:SetStatusBarColor(Stoa:Color("health"))
			self.stoaColouring = false
		end)
	end
	if GameTooltip_SetDefaultAnchor then
		hooksecurefunc("GameTooltip_SetDefaultAnchor", function(tooltip, parent)
			if (tooltip.IsForbidden and tooltip:IsForbidden()) or tooltip:GetOwner() ~= parent then return end
			local cards = Stoa.modules.Tooltip
			if cards and cards.Anchor and Stoa:IsModuleEnabled("Tooltip") and cards:Anchor(tooltip, parent) then return end
			local console = Stoa.modules.Grimoire
			local floor = console and console.db and console.db.enabled ~= false and console.OpenHeight and console:OpenHeight() or 0
			tooltip:ClearAllPoints()
			tooltip:SetPoint("BOTTOMRIGHT", UIParent, "BOTTOMRIGHT", -Stoa.space.xxl, floor + TOOLTIP_GAP)
		end)
	end
end

-- The ready check prompt: the listener frame is the window; the frame
-- around it only carries events. The Ready and Not ready buttons are dressed
-- with the rest. Off with the kit's ready check setting.
local function dressReadyCheck()
	local kit = Stoa.modules.Kit
	if kit and kit.db and kit.db.readyCheck == false then return end
	local frame = ReadyCheckListenerFrame
	if not frame then return end
	Windows:Dress(frame)
	hide(frame.FrameGlow)
	hide(frame.Bg)
	strip(ReadyCheckFrame)
	local text = frame.Text or ReadyCheckFrameText
	if text then
		Stoa:SetFont(text, "sans", Stoa.typeSize.body)
		text:SetTextColor(Stoa:Color("text"))
	end
	-- The text is set again each time the prompt opens.
	frame:HookScript("OnShow", function()
		xpcall(function()
			if text then text:SetTextColor(Stoa:Color("text")) end
			dressButtonsIn(frame, 3)
		end, Stoa.catch)
	end)
end

local guarded = Stoa.safe.guarded

function Windows:OnEnable()
	if UI.slate() then guarded(slateFonts) end
	guarded(questFonts)
	guarded(dressQuest)
	guarded(dressGossip)
	guarded(dressMerchant)
	guarded(dressBags)
	guarded(dressTooltips)
	guarded(dressMenus)
	guarded(dressGameMenu)
	guarded(dressReadyCheck)
	-- The trainer window loads with its own addon the first time it opens.
	-- Forever's trainer addon has a bootstrap part that loads at startup,
	-- so its ADDON_LOADED can come before STOA listens and not again when
	-- the window itself loads. Opening a trainer dresses it as a backstop.
	if ClassTrainerFrame then guarded(dressTrainer) end
	Stoa:On("ADDON_LOADED", function(name)
		if name == "Blizzard_TrainerUI" then guarded(dressTrainer) end
	end)
	Stoa:On("TRAINER_SHOW", function()
		guarded(dressTrainer)
		C_Timer.After(0, function() guarded(dressTrainer) end)
	end)
	Stoa:On("STOA_THEME_CHANGED", function() UI.applyTheme() end)
	-- Quest and gossip buttons are made when a panel first opens.
	for _, frame in ipairs({ QuestFrame, GossipFrame, MerchantFrame }) do
		if frame then
			frame:HookScript("OnShow", function() guarded(function() dressButtonsIn(frame, 5) end) end)
		end
	end
end
