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

-- A slot shows five rows. The game's rows are as tall and as far apart
-- as its Edit Mode says (25 and 4 unless changed), and setting those
-- from addon code would taint the meter, so the docked window is scaled
-- as a whole until five rows fit the slot, and its words are drawn that
-- much larger to come out the size of the pages' own.
local DOCK_ROWS = 5
local DOCK_FONT = 11

local function dockScale(window, spot)
	local tall = window.GetBarHeight and select(2, pcall(window.GetBarHeight, window))
	local apart = window.GetBarSpacing and select(2, pcall(window.GetBarSpacing, window))
	tall, apart = Stoa:PlainNumber(tall) or 25, Stoa:PlainNumber(apart) or 4
	-- The list starts DOCK_TITLE under the slot's top and ends 6 above
	-- its foot (the game's own margin, which scales with the window).
	local rows = DOCK_ROWS * (tall + apart) - apart + 7
	local scale = (spot.height - DOCK_TITLE) / rows
	return math.max(0.55, math.min(1, math.floor(scale * 100) / 100))
end

-- How far a length on the screen is inside the scaled window.
local function inside(window, length)
	return length / (window.stoaScale or 1)
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
		local color = (docked or Stoa:ClassTint()) and class and not Stoa:IsSecret(class) and RAID_CLASS_COLORS[class]
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

-- A docked row has no icon and runs from the window's left edge to its
-- right. Blizzard lays the row out again in UpdateStyle, which is hooked
-- to come here. The points are set outright, not read first: reading a
-- meter row's points back can fail.
local function layoutEntry(entry)
	local holder = entry.Icon
	if not (holder and holder.SetAlpha) then return end
	local docked = isDocked(entry.stoaWindow)
	-- Words the size of the pages' own, whatever the window's scale.
	local size = docked and math.floor(inside(entry.stoaWindow, DOCK_FONT) + 0.5) or Stoa.typeSize.body
	if entry.stoaFont ~= size then
		entry.stoaFont = size
		font(entry.GetName and entry:GetName(), size)
		font(entry.GetValue and entry:GetValue(), size)
	end
	holder:SetAlpha(docked and 0 or 1)
	if not docked then return end
	local bar = entry.GetStatusBar and entry:GetStatusBar()
	if not bar then return end
	pcall(bar.SetPoint, bar, "LEFT", entry, "LEFT", 0, 0)
	pcall(bar.SetPoint, bar, "BOTTOMRIGHT", entry, "BOTTOMRIGHT", 1, 1)
	-- The thin style hangs the name off the icon too.
	local thin = Enum and Enum.DamageMeterStyle and Enum.DamageMeterStyle.Thin
	local name = entry.GetName and entry:GetName()
	if thin and name and entry.GetStyle and entry:GetStyle() == thin then
		pcall(name.SetPoint, name, "LEFT", entry, "LEFT", 0, 0)
	end
end

local function dressEntry(entry, window)
	if not entry then return end
	if window then entry.stoaWindow = window end
	if entry.stoaDressed then
		colourEntry(entry)
		layoutEntry(entry)
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
	colourEntry(entry)
	layoutEntry(entry)
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
	if window.stoaChevron then window.stoaChevron:SetAlpha(seen and 1 or 0) end
	if window.SessionDropdown then window.SessionDropdown:SetAlpha(seen and 1 or 0) end
	if window.SettingsDropdown then window.SettingsDropdown:SetAlpha(seen and 1 or 0) end
	if window.MinimizeButton then window.MinimizeButton:SetAlpha(seen and 1 or 0) end
	-- The fight's clock has the buttons' place while they are away.
	if window.SessionTimer then window.SessionTimer:SetAlpha((docked and over) and 0 or 1) end
end

-- The window's header row as it floats, or as it sits in a slot.
local function layoutWindow(window)
	local header = window.Header
	if not header then return end
	local docked = isDocked(window)
	local laid = docked and (window.stoaScale or 1) or false
	if window.stoaLaidOut == laid then return end
	local was = window.stoaLaidOut
	window.stoaLaidOut = laid
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
		local lift = HEADER_HEIGHT + 2 - inside(window, DOCK_TITLE)
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
			minimize:SetPoint("TOPRIGHT", window, "TOPRIGHT", 0, 4)
		else
			minimize:SetPoint("TOPRIGHT", header, "TOPRIGHT", -3, -5)
		end
	end
	if timer then
		timer:ClearAllPoints()
		if docked then
			timer:SetPoint("TOPRIGHT", window, "TOPRIGHT", 0, -inside(window, 1))
		else
			timer:SetPoint("TOPLEFT", header, "TOPLEFT", 1, -9)
		end
		font(timer, docked and math.floor(inside(window, DOCK_FONT) + 0.5) or Stoa.typeSize.body, "muted")
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
		-- Docked, STOA's own heading stands in for it (below).
		title:SetAlpha(docked and 0 or 1)
		if docked then
			title:SetPoint("TOPLEFT", window, "TOPLEFT", 0, -3)
		else
			if typeDropdown.Arrow then title:SetPoint("LEFT", typeDropdown.Arrow, "RIGHT", 0, 3) end
			if session then title:SetPoint("RIGHT", session, "LEFT", -5, 0) end
			Stoa:SetFont(title, "serif", Stoa.typeSize.label)
			title:SetTextColor(Stoa:Color("text"))
		end
		UI.legible(title)
	end

	-- The heading as the pages have theirs: small capitals where a page's
	-- heading stands, and the hairline under it (none in Slate, where the
	-- card is the section). On a frame of its own that undoes the window's
	-- scale, so it is drawn at the pages' size.
	if docked and not window.stoaHead then
		local head = CreateFrame("Frame", nil, window)
		head:SetPoint("TOPLEFT", window, "TOPLEFT", 0, 0)
		head:SetSize(10, DOCK_TITLE)
		head.words = UI.caption(head, "")
		head.words:SetPoint("TOPLEFT", head, "TOPLEFT", 0, 0)
		local rule = UI.line(head)
		rule:SetPoint("TOPLEFT", head, "TOPLEFT", 0, -DOCK_RULE)
		rule:SetPoint("TOPRIGHT", head, "TOPRIGHT", 0, -DOCK_RULE)
		head.rule = rule
		window.stoaHead = head
		head.name = function()
			local words = title and title.GetText and title:GetText()
			if type(words) == "string" and not Stoa:IsSecret(words) and words ~= "" then
				UI.settleText(head.words, words:upper())
			end
		end
		if window.SetDamageMeterType then hooksecurefunc(window, "SetDamageMeterType", head.name) end
	end
	local head = window.stoaHead
	if head then
		head:SetShown(docked)
		if docked then
			head:SetScale(1 / (window.stoaScale or 1))
			local width = Stoa:PlainNumber(window:GetWidth())
			if width then head:SetWidth(width * (window.stoaScale or 1)) end
			head.rule:SetShown(not UI.slate())
			head.name()
		end
	end
	-- More than five in the list scrolls with the wheel; the bar stays away.
	local scroll = window.GetScrollBar and select(2, pcall(window.GetScrollBar, window))
	if type(scroll) == "table" and scroll.SetAlpha then scroll:SetAlpha(docked and 0 or 1) end

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
	-- The arrow that picks what is counted: STOA's chevron for the game's
	-- gold button.
	local typeDropdown = window.DamageMeterTypeDropdown
	if typeDropdown then
		textures(typeDropdown, 0)
		local chevron = UI.glyph(typeDropdown, "Chevron", 12, "muted")
		chevron:SetPoint("CENTER", 0, 0)
		chevron:SetRotation(-math.pi / 2)
		typeDropdown:HookScript("OnEnter", function() chevron:SetVertexColor(Stoa:Color("accent")) end)
		typeDropdown:HookScript("OnLeave", function() chevron:SetVertexColor(Stoa:Color("muted")) end)
		window.stoaChevron = chevron
	end
	-- The cog keeps its shape and takes the theme's accent for its gold.
	local settings = window.SettingsDropdown
	if settings then
		local function quiet()
			local icon = settings.Icon
			if not (icon and icon.SetDesaturated) then return end
			icon:SetDesaturated(true)
			icon:SetVertexColor(Stoa:Color("accent"))
		end
		if settings.OnButtonStateChanged then hooksecurefunc(settings, "OnButtonStateChanged", quiet) end
		quiet()
		window.stoaCog = quiet
	end

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

-- On a ride the console folds to its travel line and its cards go; a
-- window in a slot goes with them (by alpha only: hiding it would write
-- the game's own saved window list) and comes back with the console.
function Meters:SetRiding(on)
	for n = 1, 3 do
		local window = _G["DamageMeterSessionWindow" .. n]
		if window and window.SetAlpha and not (window.IsForbidden and window:IsForbidden()) then
			local docked = self.docks and self.docks[n]
			if on and docked then
				window.stoaRideHidden = true
				window:SetAlpha(0)
			elseif window.stoaRideHidden then
				window.stoaRideHidden = nil
				window:SetAlpha(1)
			end
		end
	end
end

function Meters:Place()
	local docks = self.docks or {}
	local anchor = self.db.place and self:Anchor()
	local x = 0
	for _, window in ipairs(shownWindows()) do
		local n = windowNumber(window)
		local spot = n and docks[n]
		-- Out of a slot the window is its own size again.
		if not spot and window.stoaScale then
			window.stoaScale = nil
			window:SetScale(1)
		end
		if spot or anchor then
			window:ClearAllPoints()
			if spot then
				local scale = dockScale(window, spot)
				window.stoaScale = scale
				window:SetScale(scale)
				window:SetPoint("TOPRIGHT", UIParent, "BOTTOMRIGHT", -spot.right / scale, spot.top / scale)
				window:SetSize(spot.width / scale, spot.height / scale)
			else
				window:SetPoint("TOPLEFT", anchor, "TOPLEFT", x, 0)
				window:SetSize(WIDTH, HEIGHT)
				x = x + WIDTH
			end
			-- Keep Blizzard's position cache from saving over the place.
			if window.SetUserPlaced and window:IsMovable() then pcall(window.SetUserPlaced, window, false) end
		end
		-- After the window has its scale, which the docked layout uses.
		if window.stoaDressed then guarded(layoutWindow, window) end
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
			if window and window.stoaCog then window.stoaCog() end
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
