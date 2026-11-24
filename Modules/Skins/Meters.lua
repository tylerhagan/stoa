-- Stoa: Blizzard's damage meter in Stoa's dress.
-- Each meter window loses its header bar and background art and floats as
-- words and faint bars with no panel behind it. Bars turn bone, your own
-- bar turns to the accent, and only the names carry class colour. The
-- windows sit side by side in the top-left corner, out of the way of the
-- console and the Halo in both states. A window in one of the console's
-- slots is cut down further (see Docked).
--
-- Blizzard_DamageMeter loads on demand, so everything waits for it and is
-- looked up by name and guarded.
local _, ns = ...
local Stoa = ns.Stoa
local hooksecurefunc = Stoa.SafeHook
local UI = Stoa.UI

local Meters = Stoa:NewModule("Meters", { place = true })

local WIDTH, HEIGHT = 300, 168
-- Words and bars sit this far in from the window's edges.
local INSET = 10

local function guarded(fn, ...)
	xpcall(fn, Stoa.catch, ...)
end

local function hide(region)
	if region and region.SetAlpha then region:SetAlpha(0) end
end

-- Hides a frame's own textures, leaving its children and words.
local function strip(frame)
	if not (frame and frame.GetRegions) then return end
	for _, region in ipairs({ frame:GetRegions() }) do
		if region.IsObjectType and region:IsObjectType("Texture") then region:SetAlpha(0) end
	end
end

-- The meters float over the world with no panel, so every word gets a
-- fine outline and shadow to hold up over snow and bright sky.
local function font(fs, size, token)
	if not fs then return end
	Stoa:SetFont(fs, "sans", size)
	UI.legible(fs)
	if token then fs:SetTextColor(Stoa:Color(token)) end
end

-- Docked ---------------------------------------------------------------------
-- A window in one of the console's slots is cut down as a docked Details
-- window is (Core/Looks.lua): its title in STOA's quiet type on the line
-- of the pages' headings with their hairline under it, its buttons only
-- under the mouse, no icons on the rows, and every bar one faint colour
-- with the class in the name.

-- The rows start this far under the slot's top, the hairline this far.
local DOCK_TITLE, DOCK_RULE = 20, 17
-- Blizzard's header strip is this tall; the rows hang 2 under it.
local HEADER_HEIGHT = 32

local function windowNumber(window)
	return tonumber((window:GetName() or ""):match("(%d+)$"))
end

local function isDocked(window)
	local docks = Meters.docks
	local n = docks and window and windowNumber(window)
	return n and docks[n] ~= nil or false
end

-- Entries --------------------------------------------------------------------

local function colourEntry(entry)
	local docked = isDocked(entry.stoaWindow)
	local bar = entry.GetStatusBarTexture and entry:GetStatusBarTexture()
	if bar then
		local mine = entry.isLocalPlayer == true
		if docked then
			local r, g, b = Stoa:Color("muted")
			bar:SetVertexColor(r, g, b, 0.25)
		else
			local r, g, b = Stoa:Color(mine and "accent" or "muted")
			-- Faint enough that the white words over them keep their contrast;
			-- at 0.55 your own bar washed the row out.
			bar:SetVertexColor(r, g, b, mine and 0.3 or 0.18)
		end
	end
	local name = entry.GetName and entry:GetName()
	if name and name.SetTextColor then
		local class = entry.classFilename
		local color = (docked or Stoa:Theme().classTint) and class and not Stoa:IsSecret(class) and RAID_CLASS_COLORS[class]
		if color then
			name:SetTextColor(color.r, color.g, color.b)
		else
			name:SetTextColor(Stoa:Color("text"))
		end
	end
end

local function plainBackground(entry)
	for _, region in ipairs(entry.GetBackgroundRegions and entry:GetBackgroundRegions() or {}) do
		region:SetAlpha(0)
	end
end

-- Points hung off the row's icon are hung off the row's left edge.
local function offIcon(region, icon, entry)
	if not (region and region.GetNumPoints) then return end
	for i = 1, region:GetNumPoints() do
		local point, relativeTo = region:GetPoint(i)
		if relativeTo == icon then
			region:SetPoint(point, entry, "LEFT", 0, 0)
			return
		end
	end
end

-- A docked row has no icon and starts at the window's left edge. Blizzard
-- lays the row out again in UpdateStyle, which is hooked to come here.
local function layoutEntry(entry)
	local holder = entry.Icon
	if not (holder and holder.SetAlpha) then return end
	local docked = isDocked(entry.stoaWindow)
	holder:SetAlpha(docked and 0 or 1)
	if docked then
		-- Blizzard hangs the bar off the art inside the icon's holder.
		local bar = entry.GetStatusBar and entry:GetStatusBar()
		local name = entry.GetName and entry:GetName()
		for _, icon in ipairs({ holder, entry.GetIcon and entry:GetIcon() }) do
			offIcon(bar, icon, entry)
			offIcon(name, icon, entry)
		end
		-- The bar runs to the slot's right edge, under the hairline's end.
		if bar then bar:SetPoint("BOTTOMRIGHT", entry, "BOTTOMRIGHT", 1, 1) end
	end
end

local function dressEntry(entry, window)
	if not entry then return end
	if window then entry.stoaWindow = window end
	if entry.stoaDressed then
		layoutEntry(entry)
		colourEntry(entry)
		return
	end
	entry.stoaDressed = true
	local bar = entry.GetStatusBar and entry:GetStatusBar()
	if bar then
		bar:SetStatusBarTexture(UI.WHITE)
	end
	font(entry.GetName and entry:GetName(), Stoa.typeSize.body, "text")
	font(entry.GetValue and entry:GetValue(), Stoa.typeSize.body, "text")
	plainBackground(entry)
	-- Blizzard puts its own colour and background back as entries are reused.
	hooksecurefunc(entry, "SetStatusBarColor", colourEntry)
	hooksecurefunc(entry, "UpdateStatusBarColor", colourEntry)
	hooksecurefunc(entry, "UpdateBackground", plainBackground)
	if entry.UpdateName then hooksecurefunc(entry, "UpdateName", colourEntry) end
	if entry.UpdateStyle then hooksecurefunc(entry, "UpdateStyle", layoutEntry) end
	UI.applyTheme()
	layoutEntry(entry)
	colourEntry(entry)
end

-- Windows --------------------------------------------------------------------

local function textures(frame, alpha)
	if not (frame and frame.GetRegions) then return end
	for _, region in ipairs({ frame:GetRegions() }) do
		if region.IsObjectType and region:IsObjectType("Texture") then region:SetAlpha(alpha) end
	end
end

-- A docked window's buttons show under the mouse and are gone at rest.
local function showButtons(window, over)
	local docked = isDocked(window)
	local state = not docked and 0 or (over and 1 or 2)
	if window.stoaButtons == state then return end
	window.stoaButtons = state
	local seen = state ~= 2
	textures(window.DamageMeterTypeDropdown, seen and 1 or 0)
	if window.SessionDropdown then window.SessionDropdown:SetAlpha(seen and 1 or 0) end
	if window.SettingsDropdown then window.SettingsDropdown:SetAlpha(seen and 0.6 or 0) end
	if window.MinimizeButton then window.MinimizeButton:SetAlpha(seen and 1 or 0) end
	-- The fight's clock has the buttons' place while they are away.
	if window.SessionTimer then window.SessionTimer:SetAlpha((docked and over) and 0 or 1) end
end

-- The window's header row as it floats, or as it sits in a slot.
local function layoutWindow(window)
	local header = window.Header
	if not header then return end
	local docked = isDocked(window)
	if window.stoaLaidOut == docked then return end
	local was = window.stoaLaidOut
	window.stoaLaidOut = docked
	-- Out of a slot again: Blizzard's own layout puts the rows' icons back.
	if was and not docked and window.ForEachEntryFrame then
		window:ForEachEntryFrame(function(entry)
			if entry.UpdateStyle then pcall(entry.UpdateStyle, entry) end
		end)
	end

	header:ClearAllPoints()
	if docked then
		-- The rows hang 5 in and 2 under the header: flush with the slot's
		-- left edge, DOCK_TITLE under its top.
		local lift = HEADER_HEIGHT + 2 - DOCK_TITLE
		header:SetPoint("TOPLEFT", -5, lift)
		header:SetPoint("TOPRIGHT", 1, lift)
	else
		-- Inset the header row, and the bars hung under it, from the edges.
		header:SetPoint("TOPLEFT", INSET, -2)
		header:SetPoint("TOPRIGHT", -INSET + 4, -2)
	end

	local minimize, session, timer = window.MinimizeButton, window.SessionDropdown, window.SessionTimer
	if minimize then
		minimize:ClearAllPoints()
		if docked then
			minimize:SetPoint("TOPRIGHT", window, "TOPRIGHT", 0, 2)
		else
			minimize:SetPoint("TOPRIGHT", header, "TOPRIGHT", -3, -5)
		end
	end
	if timer then
		timer:ClearAllPoints()
		if docked then
			timer:SetPoint("TOPRIGHT", window, "TOPRIGHT", 0, -3)
		else
			timer:SetPoint("TOPLEFT", header, "TOPLEFT", 1, -9)
		end
		font(timer, docked and 11 or Stoa.typeSize.body, "muted")
	end
	local typeDropdown = window.DamageMeterTypeDropdown
	local title = typeDropdown and typeDropdown.TypeName
	if typeDropdown and session and timer then
		typeDropdown:ClearAllPoints()
		if docked then
			-- The arrow that picks what is counted joins the other buttons.
			typeDropdown:SetPoint("RIGHT", session, "LEFT", -2, -3)
		else
			typeDropdown:SetPoint("TOPLEFT", timer, "TOPRIGHT", 0, 6)
		end
	end
	if title then
		title:ClearAllPoints()
		if docked then
			title:SetPoint("TOPLEFT", window, "TOPLEFT", 0, -3)
			Stoa:SetFont(title, "sans", 11)
			title:SetTextColor(Stoa:Color("muted"))
		else
			if typeDropdown.Arrow then title:SetPoint("LEFT", typeDropdown.Arrow, "RIGHT", 0, 3) end
			if session then title:SetPoint("RIGHT", session, "LEFT", -5, 0) end
			Stoa:SetFont(title, "serif", Stoa.typeSize.label)
			title:SetTextColor(Stoa:Color("text"))
		end
		UI.legible(title)
	end

	-- The hairline under the title, as under the pages' headings.
	if docked and not window.stoaRule then
		local rule = UI.line(window)
		rule:SetPoint("TOPLEFT", window, "TOPLEFT", 0, -DOCK_RULE)
		rule:SetPoint("TOPRIGHT", window, "TOPRIGHT", 0, -DOCK_RULE)
		window.stoaRule = rule
	end
	if window.stoaRule then window.stoaRule:SetShown(docked) end

	showButtons(window, docked and window:IsMouseOver() or false)
	if window.ForEachEntryFrame then
		window:ForEachEntryFrame(function(entry) guarded(dressEntry, entry, window) end)
	end
	local mine = window.GetLocalPlayerEntry and window:GetLocalPlayerEntry()
	if mine then guarded(dressEntry, mine, window) end
end

local function dressWindow(window)
	if not window or window.stoaDressed then return end
	window.stoaDressed = true

	hide(window.Header)
	local container = window.GetMinimizeContainer and window:GetMinimizeContainer() or window.MinimizeContainer
	if container then
		hide(container.Background)
		-- Blizzard sets the background's alpha from its opacity setting.
		hooksecurefunc(window, "UpdateBackground", function() hide(container.Background) end)
		font(container.NotActive, Stoa.typeSize.body, "muted")
	end


	-- Header words: the meter's name in the display face, the rest quiet.
	local sessionDropdown = window.SessionDropdown
	if sessionDropdown then
		strip(sessionDropdown)
		font(sessionDropdown.SessionName, Stoa.typeSize.caption, "muted")
	end
	if window.MinimizeButton then
		local fold = UI.foldGlyph(window.MinimizeButton)
		local function update() fold(window.IsMinimized and window:IsMinimized()) end
		hooksecurefunc(window, "SetMinimized", update)
		update()
	end
	if window.SettingsDropdown then window.SettingsDropdown:SetAlpha(0.6) end

	-- Bars, now and as the list makes new ones.
	hooksecurefunc(window, "SetupEntry", function(_, entry) guarded(dressEntry, entry, window) end)
	-- The header row, and the bars there are, floating or in a slot.
	layoutWindow(window)

	-- The spell breakdown that opens beside a bar.
	local source = window.GetSourceWindow and window:GetSourceWindow()
	if source and not source.stoaDressed then
		source.stoaDressed = true
		strip(source)
		UI.roundPanel(source, 0.95)
		if source.SetupEntry then
			hooksecurefunc(source, "SetupEntry", function(_, entry) guarded(dressEntry, entry) end)
		end
		if source.SetBackgroundAlpha then
			hooksecurefunc(source, "SetBackgroundAlpha", function() strip(source) end)
		end
	end
end

-- Placement ------------------------------------------------------------------

-- The windows in order, left to right: the one Blizzard calls primary first.
local function shownWindows()
	local list = {}
	for i = 1, 3 do
		local window = _G["DamageMeterSessionWindow" .. i]
		if window and window:IsShown() then list[#list + 1] = window end
	end
	return list
end

-- The strip hangs from one frame of ours, so it can be moved as a whole.
function Meters:Anchor()
	if self.anchor then return self.anchor end
	local anchor = CreateFrame("Frame", "StoaMetersAnchor", UIParent)
	anchor:SetSize(WIDTH, HEIGHT)
	anchor:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 0, 0)
	self.anchor = anchor
	Stoa:RegisterMover("meters", anchor, "Damage meters")
	return anchor
end

-- A window given a slot on the console (Console:PlaceDocks) sits there;
-- `spot` is nil when it has none. The rest stay in the strip.
function Meters:Dock(n, spot)
	self.docks = self.docks or {}
	if self.docks[n] == nil and spot == nil then return end
	self.docks[n] = spot or nil
	if self.dressed then self:Place() end
	if spot then
		self:Remind(n)
		self:WatchMouse()
	end
end

-- Docked windows' buttons follow the mouse; the watch runs only once a
-- window has had a slot.
function Meters:WatchMouse()
	if self.watching then return end
	self.watching = true
	Stoa:NewTicker(0.15, function()
		if not (self.docks and next(self.docks)) then return end
		for n in pairs(self.docks) do
			local window = _G["DamageMeterSessionWindow" .. n]
			if window and window.stoaDressed and window:IsVisible() then showButtons(window, window:IsMouseOver()) end
		end
	end)
end

-- A slot whose window isn't there says so once a session, a few seconds
-- on (the game sets its windows up after login). STOA doesn't open the
-- window itself: that would write the game's own saved window list.
function Meters:Remind(n)
	self.reminded = self.reminded or {}
	if self.reminded[n] then return end
	self.reminded[n] = true
	C_Timer.After(6, function()
		if not (self.docks and self.docks[n]) then self.reminded[n] = nil return end
		local window = _G["DamageMeterSessionWindow" .. n]
		if window and window:IsShown() then self.reminded[n] = nil return end
		if n == 1 then
			Stoa:Print("Meter 1 has a slot on the console, but the game's damage meter isn't showing. Turn it on in the game's options and it will sit there.")
		else
			Stoa:Print(("Meter %d has a slot on the console, but that window doesn't exist yet. Open the cog on a meter window and choose to show a new window: it will sit in its slot."):format(n))
		end
	end)
end

function Meters:Place()
	local docks = self.docks or {}
	local anchor = self.db.place and self:Anchor()
	local x = 0
	for _, window in ipairs(shownWindows()) do
		local n = windowNumber(window)
		local spot = n and docks[n]
		if window.stoaDressed then guarded(layoutWindow, window) end
		if spot or anchor then
			window:ClearAllPoints()
			if spot then
				window:SetPoint("TOPRIGHT", UIParent, "BOTTOMRIGHT", -spot.right, spot.top)
				window:SetSize(spot.width, spot.height)
			else
				window:SetPoint("TOPLEFT", anchor, "TOPLEFT", x, 0)
				window:SetSize(WIDTH, HEIGHT)
				x = x + WIDTH
			end
			-- Keep Blizzard's position cache from saving over the place.
			if window.SetUserPlaced and window:IsMovable() then pcall(window.SetUserPlaced, window, false) end
		end
	end
end

local function hookWindow(window)
	if not window or window.stoaPlaced then return end
	window.stoaPlaced = true
	window:HookScript("OnShow", function() Meters:Place() end)
	window:HookScript("OnHide", function() Meters:Place() end)
	-- A drag or resize settles back into the strip while placing is on.
	window:HookScript("OnDragStop", function() Meters:Place() end)
	hooksecurefunc(window, "SetMinimized", function() Meters:Place() end)
end

function Meters:Dress()
	local meter = _G.DamageMeter
	if not meter or self.dressed then return end
	self.dressed = true
	local function each()
		for i = 1, 3 do
			local window = _G["DamageMeterSessionWindow" .. i]
			if window then
				guarded(dressWindow, window)
				guarded(hookWindow, window)
			end
		end
		guarded(Meters.Place, Meters)
	end
	if meter.SetupSessionWindow then
		hooksecurefunc(meter, "SetupSessionWindow", each)
	end
	-- Edit Mode re-anchors the primary window's frame when it closes.
	if EditModeManagerFrame then
		EditModeManagerFrame:HookScript("OnHide", function() guarded(Meters.Place, Meters) end)
	end
	Stoa:On("PLAYER_ENTERING_WORLD", function() C_Timer.After(0.5, each) end)
	each()
end

function Meters:OnEnable()
	Stoa:On("STOA_THEME_CHANGED", function()
		for i = 1, 3 do
			local window = _G["DamageMeterSessionWindow" .. i]
			if window and window.ForEachEntryFrame then window:ForEachEntryFrame(colourEntry) end
		end
	end)
	if _G.DamageMeter then
		self:Dress()
	else
		Stoa:On("ADDON_LOADED", function(name)
			if name == "Blizzard_DamageMeter" then guarded(Meters.Dress, Meters) end
		end)
	end
end
