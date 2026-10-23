-- Stoa: Blizzard's damage meter in Stoa's dress.
-- Each meter window loses its header bar and background art for a dark
-- rounded panel with a hairline edge. Bars turn bone, your own bar turns to
-- the accent, and only the names carry class colour. The windows stack in
-- one strip flush in the top-left corner, side by side, out of the way of
-- the console and the Halo in both states.
--
-- Blizzard_DamageMeter loads on demand, so everything waits for it and is
-- looked up by name and guarded.
local _, ns = ...
local Stoa = ns.Stoa
local UI = Stoa.UI

local Meters = Stoa:NewModule("Meters", { place = true })

local WIDTH, HEIGHT, FOLDED = 300, 168, 30
-- Words and bars sit this far in from the window's edges.
local INSET = 10

local function guarded(fn, ...)
	xpcall(fn, geterrorhandler(), ...)
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

local function font(fs, size, token)
	if not fs then return end
	Stoa:SetFont(fs, "sans", size)
	fs:SetShadowOffset(0, 0)
	if token then fs:SetTextColor(Stoa:Color(token)) end
end

-- Entries --------------------------------------------------------------------

local function colourEntry(entry)
	local bar = entry.GetStatusBarTexture and entry:GetStatusBarTexture()
	if bar then
		local mine = entry.isLocalPlayer == true
		local r, g, b = Stoa:Color(mine and "accent" or "muted")
		bar:SetVertexColor(r, g, b, mine and 0.7 or 0.45)
	end
	local name = entry.GetName and entry:GetName()
	if name and name.SetTextColor then
		local class = entry.classFilename
		local color = Stoa:Theme().classTint and class and not Stoa:IsSecret(class) and RAID_CLASS_COLORS[class]
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

local function dressEntry(entry)
	if not entry or entry.stoaDressed then return end
	entry.stoaDressed = true
	local bar = entry.GetStatusBar and entry:GetStatusBar()
	if bar then
		bar:SetStatusBarTexture(UI.WHITE)
		local track = bar:CreateTexture(nil, "BACKGROUND", nil, -1)
		track:SetAllPoints()
		UI.paint(track, "text", 0.06)
	end
	font(entry.GetName and entry:GetName(), Stoa.typeSize.body, "text")
	font(entry.GetValue and entry:GetValue(), Stoa.typeSize.body, "text")
	plainBackground(entry)
	-- Blizzard puts its own colour and background back as entries are reused.
	hooksecurefunc(entry, "SetStatusBarColor", colourEntry)
	hooksecurefunc(entry, "UpdateStatusBarColor", colourEntry)
	hooksecurefunc(entry, "UpdateBackground", plainBackground)
	if entry.UpdateName then hooksecurefunc(entry, "UpdateName", colourEntry) end
	UI.applyTheme()
	colourEntry(entry)
end

-- Windows --------------------------------------------------------------------

-- A square panel with hairlines on its open sides: the strip meets the
-- screen's top and left edges, so only the bottom and right are drawn, and
-- the right hairline divides one window from the next.
local function slab(frame)
	local bg = frame:CreateTexture(nil, "BACKGROUND", nil, -8)
	bg:SetAllPoints()
	UI.paint(bg, "panel", 0.9)
	local bottom = UI.line(frame)
	bottom:SetPoint("BOTTOMLEFT")
	bottom:SetPoint("BOTTOMRIGHT")
	local right = frame:CreateTexture(nil, "BORDER")
	right:SetWidth(1)
	right:SetPoint("TOPRIGHT")
	right:SetPoint("BOTTOMRIGHT")
	UI.paint(right, "hairline")
	UI.applyTheme()
end

local function dressWindow(window)
	if not window or window.stoaDressed then return end
	window.stoaDressed = true

	hide(window.Header)
	-- Inset the header row, and the bars hung under it, from the edges.
	if window.Header then
		window.Header:ClearAllPoints()
		window.Header:SetPoint("TOPLEFT", INSET, -2)
		window.Header:SetPoint("TOPRIGHT", -INSET + 4, -2)
	end
	local container = window.GetMinimizeContainer and window:GetMinimizeContainer() or window.MinimizeContainer
	if container then
		hide(container.Background)
		-- Blizzard sets the background's alpha from its opacity setting.
		hooksecurefunc(window, "UpdateBackground", function() hide(container.Background) end)
		slab(container)
		font(container.NotActive, Stoa.typeSize.body, "muted")
	end

	-- A header-only panel for when the window is folded to its title.
	local folded = CreateFrame("Frame", nil, window)
	folded:SetPoint("TOPLEFT")
	folded:SetPoint("TOPRIGHT")
	folded:SetHeight(FOLDED)
	folded:SetFrameLevel(math.max(window:GetFrameLevel() - 1, 0))
	slab(folded)
	local function fold()
		folded:SetShown(window.IsMinimized and window:IsMinimized() or false)
	end
	hooksecurefunc(window, "SetMinimized", fold)
	fold()

	-- Header words: the meter's name in the display face, the rest quiet.
	local typeDropdown = window.DamageMeterTypeDropdown
	if typeDropdown and typeDropdown.TypeName then
		Stoa:SetFont(typeDropdown.TypeName, "serif", Stoa.typeSize.label)
		typeDropdown.TypeName:SetTextColor(Stoa:Color("text"))
		typeDropdown.TypeName:SetShadowOffset(0, 0)
	end
	font(window.SessionTimer, Stoa.typeSize.body, "muted")
	local sessionDropdown = window.SessionDropdown
	if sessionDropdown then
		strip(sessionDropdown)
		font(sessionDropdown.SessionName, Stoa.typeSize.caption, "muted")
	end
	local fold = window.MinimizeButton
	if fold then
		-- Blizzard's red collapse button becomes a quiet minus or plus.
		local function plain()
			for _, getter in ipairs({ "GetNormalTexture", "GetPushedTexture", "GetHighlightTexture" }) do
				local tex = fold[getter] and fold[getter](fold)
				if tex then tex:SetAlpha(0) end
			end
		end
		local glyph = fold:CreateFontString(nil, "OVERLAY")
		Stoa:SetFont(glyph, "sans", Stoa.typeSize.label)
		glyph:SetPoint("CENTER", 0, 1)
		glyph:SetTextColor(Stoa:Color("muted"))
		local function update()
			plain()
			glyph:SetText(window.IsMinimized and window:IsMinimized() and "+" or "–")
		end
		hooksecurefunc(window, "SetMinimized", update)
		fold:HookScript("OnEnter", function() glyph:SetTextColor(Stoa:Color("accent")) end)
		fold:HookScript("OnLeave", function() glyph:SetTextColor(Stoa:Color("muted")) end)
		update()
	end
	if window.SettingsDropdown then window.SettingsDropdown:SetAlpha(0.6) end

	-- Bars, now and as the list makes new ones.
	hooksecurefunc(window, "SetupEntry", function(_, entry) guarded(dressEntry, entry) end)
	if window.ForEachEntryFrame then
		window:ForEachEntryFrame(function(entry) guarded(dressEntry, entry) end)
	end
	local localEntry = window.GetLocalPlayerEntry and window:GetLocalPlayerEntry()
	if localEntry then guarded(dressEntry, localEntry) end

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

function Meters:Place()
	if not self.db.place then return end
	local x = 0
	for _, window in ipairs(shownWindows()) do
		window:ClearAllPoints()
		window:SetPoint("TOPLEFT", UIParent, "TOPLEFT", x, 0)
		window:SetSize(WIDTH, HEIGHT)
		-- Keep Blizzard's position cache from saving over the strip.
		if window.SetUserPlaced and window:IsMovable() then pcall(window.SetUserPlaced, window, false) end
		x = x + WIDTH
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
