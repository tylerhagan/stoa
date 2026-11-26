-- Stoa: map comforts.
--   Fade: the world map goes see-through while you move, so you can read the
--   ground through it. The game's own "mapFade" setting is used where this
--   client has it; otherwise the map's alpha follows your movement.
--   Levels: a quiet "Level 10-20" beside the map's title and on the minimap's
--   zone tooltip. The game's own numbers (C_Map.GetMapLevels) are used when
--   it has them; Forever gives none, so a small table of the classic
--   levelling zones fills in, by English name and, in other languages, by
--   the game's own name for each zone's area.
--
-- Revealing unexplored areas is not done: the game only reports the areas
-- you have explored (C_MapExplorationInfo.GetExploredMapTextures), and the
-- art for the rest would be a large table of texture IDs.
local _, ns = ...
local Stoa = ns.Stoa
local hooksecurefunc = Stoa.SafeHook

local Map = Stoa:NewModule("Map", {
	fade = true,
	levels = true,
	fadeAlpha = 0.5,
})

-- Classic levelling zones, by English name: lowest, highest.
local ZONES = {
	["Dun Morogh"] = { 1, 10 }, ["Elwynn Forest"] = { 1, 10 }, ["Teldrassil"] = { 1, 10 },
	["Durotar"] = { 1, 10 }, ["Mulgore"] = { 1, 10 }, ["Tirisfal Glades"] = { 1, 10 },
	["Westfall"] = { 10, 20 }, ["Loch Modan"] = { 10, 20 }, ["Darkshore"] = { 10, 20 },
	["Silverpine Forest"] = { 10, 20 }, ["The Barrens"] = { 10, 25 },
	["Redridge Mountains"] = { 15, 25 }, ["Stonetalon Mountains"] = { 15, 27 },
	["Ashenvale"] = { 18, 30 }, ["Duskwood"] = { 18, 30 }, ["Wetlands"] = { 20, 30 },
	["Hillsbrad Foothills"] = { 20, 30 }, ["Thousand Needles"] = { 25, 35 },
	["Alterac Mountains"] = { 30, 40 }, ["Arathi Highlands"] = { 30, 40 },
	["Desolace"] = { 30, 40 }, ["Stranglethorn Vale"] = { 30, 45 },
	["Dustwallow Marsh"] = { 35, 45 }, ["Badlands"] = { 35, 45 },
	["Swamp of Sorrows"] = { 35, 45 }, ["Feralas"] = { 40, 50 },
	["The Hinterlands"] = { 40, 50 }, ["Tanaris"] = { 40, 50 },
	["Searing Gorge"] = { 43, 50 }, ["Azshara"] = { 45, 55 }, ["Blasted Lands"] = { 45, 55 },
	["Un'Goro Crater"] = { 48, 55 }, ["Felwood"] = { 48, 55 },
	["Burning Steppes"] = { 50, 58 }, ["Western Plaguelands"] = { 51, 58 },
	["Eastern Plaguelands"] = { 53, 60 }, ["Winterspring"] = { 53, 60 },
	["Deadwind Pass"] = { 55, 60 }, ["Silithus"] = { 55, 60 }, ["Moonglade"] = { 55, 60 },
}
Map.ZONES = ZONES

-- The same zones by the game's area IDs, which give each one's name in the
-- game's language. Read once, the first time a zone is asked for.
local AREAS = {
	["Dun Morogh"] = 1, ["Elwynn Forest"] = 12, ["Teldrassil"] = 141, ["Durotar"] = 14, ["Mulgore"] = 215,
	["Tirisfal Glades"] = 85, ["Westfall"] = 40, ["Loch Modan"] = 38, ["Darkshore"] = 148,
	["Silverpine Forest"] = 130, ["The Barrens"] = 17, ["Redridge Mountains"] = 44,
	["Stonetalon Mountains"] = 406, ["Ashenvale"] = 331, ["Duskwood"] = 10, ["Wetlands"] = 11,
	["Hillsbrad Foothills"] = 267, ["Thousand Needles"] = 400, ["Alterac Mountains"] = 36,
	["Arathi Highlands"] = 45, ["Desolace"] = 405, ["Stranglethorn Vale"] = 33, ["Dustwallow Marsh"] = 15,
	["Badlands"] = 3, ["Swamp of Sorrows"] = 8, ["Feralas"] = 357, ["The Hinterlands"] = 47, ["Tanaris"] = 440,
	["Searing Gorge"] = 51, ["Azshara"] = 16, ["Blasted Lands"] = 4, ["Un'Goro Crater"] = 490, ["Felwood"] = 361,
	["Burning Steppes"] = 46, ["Western Plaguelands"] = 28, ["Eastern Plaguelands"] = 139,
	["Winterspring"] = 618, ["Deadwind Pass"] = 41, ["Silithus"] = 1377, ["Moonglade"] = 493,
}
local translated
local function translateZones()
	translated = true
	if Stoa.english or not (C_Map and C_Map.GetAreaInfo) then return end
	for english, areaID in pairs(AREAS) do
		local name = Stoa.safe.plain(Stoa.safe.call(C_Map.GetAreaInfo, areaID))
		if type(name) == "string" and name ~= "" and not ZONES[name] then ZONES[name] = ZONES[english] end
	end
end

-- "Level 10-20" for a zone, or nil. The game's numbers come first.
function Map:Levels(name, mapID)
	if mapID and C_Map and C_Map.GetMapLevels then
		local ok, low, high = pcall(C_Map.GetMapLevels, mapID)
		low, high = Stoa:PlainNumber(low), Stoa:PlainNumber(high)
		if ok and low and high and low > 0 then
			return low == high and ("Level %d"):format(low) or ("Level %d-%d"):format(low, high)
		end
	end
	if not translated then translateZones() end
	local zone = type(name) == "string" and not Stoa:IsSecret(name) and ZONES[name]
	if not zone then return nil end
	return ("Level %d-%d"):format(zone[1], zone[2])
end

-- Fade ---------------------------------------------------------------------------

local function mapFadeCVar()
	if not (C_CVar and C_CVar.GetCVar) then return false end
	local ok, value = pcall(C_CVar.GetCVar, "mapFade")
	return ok and value ~= nil
end

local function mapAlpha(alpha)
	local map = WorldMapFrame
	if not (map and map.SetAlpha) then return end
	-- A full-screen map is for reading, so it stays solid.
	if alpha < 1 and map.IsMaximized and map:IsMaximized() then alpha = 1 end
	map:SetAlpha(alpha)
end

function Map:ApplyFade()
	local db = self.db
	if self.usesCVar then
		if db.fade then
			Stoa.GameSettings:Set("Map", "mapFade", "1")
		else
			Stoa.GameSettings:Restore("mapFade")
		end
		return
	end
	if not db.fade then mapAlpha(1) end
end

function Map:SetupFade()
	self.usesCVar = mapFadeCVar()
	self:ApplyFade()
	if self.usesCVar then return end
	Stoa:On("PLAYER_STARTED_MOVING", function()
		if self.db.fade then mapAlpha(self.db.fadeAlpha) end
	end)
	Stoa:On("PLAYER_STOPPED_MOVING", function() mapAlpha(1) end)
	if WorldMapFrame and WorldMapFrame.HookScript then
		WorldMapFrame:HookScript("OnShow", Stoa:Guard(function()
			local moving = IsPlayerMoving and IsPlayerMoving()
			mapAlpha(self.db.fade and moving and self.db.fadeAlpha or 1)
		end, "Map"))
	end
end

-- Levels ---------------------------------------------------------------------------

function Map:MapLabel()
	local map = WorldMapFrame
	if not map then return end
	if self.label then return self.label end
	local border = map.BorderFrame
	local title = border and border.TitleContainer and border.TitleContainer.TitleText
	local parent = border and border.TitleContainer or map
	local label = parent:CreateFontString(nil, "OVERLAY")
	Stoa:SetFont(label, "sans", Stoa.typeSize.caption)
	label:SetTextColor(Stoa:Color("muted"))
	if title and title.GetObjectType then
		-- Beside the title's words on the window's header (the title's own
		-- box runs the width of the header, so it follows the words; see
		-- Map:ShowMapLevels).
		label.stoaTitle = title
		label:SetPoint("LEFT", title, "LEFT", 0, 0)
	else
		label:SetPoint("TOP", map, "TOP", 0, -28)
	end
	self.label = label
	return label
end

function Map:ShowMapLevels()
	local map = WorldMapFrame
	if not map then return end
	local label = self:MapLabel()
	if not label then return end
	local text
	if self.db.levels and map.GetMapID then
		local id = map:GetMapID()
		local info = id and C_Map and C_Map.GetMapInfo and C_Map.GetMapInfo(id)
		if info then text = self:Levels(info.name, id) end
	end
	label:SetText(text or "")
	label:SetShown(text ~= nil)
	local title = label.stoaTitle
	if title and title.GetStringWidth then
		local justify = title.GetJustifyH and title:GetJustifyH() or "LEFT"
		local width = math.ceil(title:GetStringWidth() or 0)
		label:ClearAllPoints()
		if justify == "CENTER" then
			label:SetPoint("LEFT", title, "CENTER", width / 2 + 12, 0)
		else
			label:SetPoint("LEFT", title, "LEFT", width + 12, 0)
		end
	end
end

-- The windowed map leaves room on the left of its breadcrumbs for the
-- round portrait. A dressed map has no portrait, so the breadcrumbs start
-- at the left edge, where the game itself puts them on the full-screen map.
function Map:SeatCrumbs()
	local map = WorldMapFrame
	local bar, spacer = map and map.NavBar, map and map.TitleCanvasSpacerFrame
	if not (bar and spacer and map.BorderFrame and map.BorderFrame.stoaHeader) then return end
	if bar.IsForbidden and bar:IsForbidden() then return end
	bar:SetPoint("TOPLEFT", spacer, "TOPLEFT", 8, -25)
end

-- A dressed map's breadcrumbs: Blizzard's red and gold arrow plates go, the
-- zone names stay as plain words (the one you are on lit, the way back
-- quiet), with a chevron for each menu of neighbours.
local function isTexture(region)
	return region.GetObjectType and region:GetObjectType() == "Texture"
end

local function fadeTextures(frame)
	if type(frame) ~= "table" or not frame.GetRegions then return end
	for _, region in ipairs({ frame:GetRegions() }) do
		if isTexture(region) then region:SetAlpha(0) end
	end
end

local function paintCrumb(button)
	local text = button.text or (button.GetFontString and button:GetFontString())
	if not text then return end
	local bar = button:GetParent()
	local list = bar and bar.navList
	local last = type(list) == "table" and list[#list] == button
	local token = (button.IsMouseOver and button:IsMouseOver() and not last) and "accent" or last and "text" or "muted"
	text:SetTextColor(Stoa:Color(token))
end

local function dressCrumb(button)
	if type(button) ~= "table" or (button.IsForbidden and button:IsForbidden()) then return end
	if not button.stoaCrumb then
		button.stoaCrumb = true
		fadeTextures(button)
		local text = button.text or (button.GetFontString and button:GetFontString())
		if text then Stoa:SetFont(text, "sans", Stoa.typeSize.body) end
		local arrow = button.MenuArrowButton
		if type(arrow) == "table" and arrow.CreateTexture then
			fadeTextures(arrow)
			if arrow.Art then arrow.Art:SetAlpha(0) end
			local glyph = Stoa.UI.glyph(arrow, "Chevron", 10, "muted")
			glyph:SetPoint("CENTER", 0, 0)
			glyph:SetRotation(-math.pi / 2)
			arrow:HookScript("OnEnter", function() glyph:SetVertexColor(Stoa:Color("accent")) end)
			arrow:HookScript("OnLeave", function() glyph:SetVertexColor(Stoa:Color("muted")) end)
		end
		button:HookScript("OnEnter", paintCrumb)
		button:HookScript("OnLeave", paintCrumb)
	end
	paintCrumb(button)
end

function Map:DressCrumbs()
	local map = WorldMapFrame
	local bar = map and map.NavBar
	if not (bar and map.BorderFrame and map.BorderFrame.stoaHeader) then return end
	if bar.IsForbidden and bar:IsForbidden() then return end
	if not bar.stoaCrumbs then
		bar.stoaCrumbs = true
		fadeTextures(bar)
		if bar.overlay and bar.overlay.SetAlpha then bar.overlay:SetAlpha(0) end
		if bar.Inset and bar.Inset.SetAlpha then bar.Inset:SetAlpha(0) end
	end
	dressCrumb(bar.home)
	dressCrumb(bar.overflow)
	for _, button in ipairs(type(bar.navList) == "table" and bar.navList or {}) do dressCrumb(button) end
end

-- The quest log beside the map: its painted frame and filigree go, the
-- search field and scrollbar are STOA's, zone headings lose their plate and
-- the quest count reads as a quiet caption.
local function dressLogHeader(header)
	if type(header) ~= "table" or header.stoaLogHead or (header.IsForbidden and header:IsForbidden()) then return end
	header.stoaLogHead = true
	for _, region in ipairs({ header:GetRegions() }) do
		if isTexture(region) then
			local layer = region:GetDrawLayer()
			if layer == "HIGHLIGHT" then
				region:SetTexture(Stoa.UI.WHITE)
				region:SetVertexColor(1, 1, 1, 0.05)
			elseif layer == "BACKGROUND" or layer == "BORDER" then
				region:SetAlpha(0)
			end
		end
	end
	local rule = header:CreateTexture(nil, "BORDER")
	rule:SetTexture(Stoa.UI.WHITE)
	rule:SetHeight(1)
	rule:SetPoint("BOTTOMLEFT", 4, 1)
	rule:SetPoint("BOTTOMRIGHT", -4, 1)
	Stoa.UI.tint(rule, "hairline")
end

function Map:DressLog()
	local map = WorldMapFrame
	local scroll = rawget(_G, "QuestScrollFrame")
	if not (map and map.BorderFrame and map.BorderFrame.stoaHeader and type(scroll) == "table") then return end
	if scroll.IsForbidden and scroll:IsForbidden() then return end
	if not scroll.stoaLog then
		scroll.stoaLog = true
		local windows = Stoa.modules.Windows
		fadeTextures(scroll.BorderFrame)
		if scroll.Edge then scroll.Edge:SetAlpha(0) end
		if windows then
			if windows.DressSearch then xpcall(windows.DressSearch, Stoa.catch, scroll.SearchBox) end
			if windows.DressScrollBar then xpcall(windows.DressScrollBar, Stoa.catch, scroll.ScrollBar) end
		end
		local count = rawget(_G, "QuestLogQuestCount")
		if type(count) == "table" and count.SetTextColor then
			Stoa:SetFont(count, "sans", Stoa.typeSize.caption)
			count:SetTextColor(Stoa:Color("muted"))
			-- The count's own framed plate, where it has one.
			local holder = count:GetParent()
			if holder ~= scroll and holder ~= scroll.BorderFrame then fadeTextures(holder) end
		end
	end
	local pool = scroll.headerFramePool
	if type(pool) == "table" and pool.EnumerateActive then
		for header in pool:EnumerateActive() do dressLogHeader(header) end
	end
end

function Map:SetupDress()
	if self.dressHooked or not WorldMapFrame then return end
	self.dressHooked = true
	local function dress()
		Map:DressCrumbs()
		Map:DressLog()
	end
	WorldMapFrame:HookScript("OnShow", Stoa:Guard(dress, "Map"))
	if rawget(_G, "NavBar_AddButton") then
		hooksecurefunc("NavBar_AddButton", function(bar)
			if bar == WorldMapFrame.NavBar then Map:DressCrumbs() end
		end)
	end
	if rawget(_G, "QuestLogQuests_Update") then
		hooksecurefunc("QuestLogQuests_Update", function() Map:DressLog() end)
	end
end

function Map:SetupLevels()
	if not WorldMapFrame then return end
	if self.levelsHooked then return end
	self.levelsHooked = true
	WorldMapFrame:HookScript("OnShow", Stoa:Guard(function() Map:SeatCrumbs() end, "Map"))
	if WorldMapFrame.Minimize then
		hooksecurefunc(WorldMapFrame, "Minimize", function() Map:SeatCrumbs() end)
	end
	if WorldMapFrame.OnMapChanged then
		hooksecurefunc(WorldMapFrame, "OnMapChanged", function() Map:ShowMapLevels() end)
	end
	WorldMapFrame:HookScript("OnShow", Stoa:Guard(function() Map:ShowMapLevels() end, "Map"))
	-- The header drops its rise when the map fills the screen.
	local windows = Stoa.modules.Windows
	for _, method in ipairs({ "Maximize", "Minimize" }) do
		if WorldMapFrame[method] and windows and windows.Settle then
			hooksecurefunc(WorldMapFrame, method, function()
				if WorldMapFrame.BorderFrame then windows:Settle(WorldMapFrame.BorderFrame) end
			end)
		end
	end
end

-- On the minimap's zone tooltip, after the game's own lines.
function Map:SetupMinimapTip()
	local button = (MinimapCluster and MinimapCluster.ZoneTextButton) or MinimapZoneTextButton
	if not (button and button.HookScript) then return end
	button:HookScript("OnEnter", Stoa:Guard(function()
		if not Map.db.levels or not GameTooltip:IsShown() then return end
		local zone = GetZoneText and GetZoneText()
		local text = Map:Levels(zone, C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player"))
		if text then
			GameTooltip:AddLine(text, Stoa:Color("muted"))
			GameTooltip:Show()
		end
	end, "Map"))
end

function Map:Refresh()
	self:ApplyFade()
	self:ShowMapLevels()
end

local function setup()
	Map:SetupFade()
	Map:SetupLevels()
	Map:ShowMapLevels()
	Map:SetupDress()
end

function Map:OnEnable()
	xpcall(self.SetupMinimapTip, Stoa.catch, self)
	if WorldMapFrame then
		xpcall(setup, Stoa.catch)
	else
		-- The map can load later than the rest of the interface.
		Stoa:On("ADDON_LOADED", function(name)
			if name == "Blizzard_WorldMap" and not self.levelsHooked then xpcall(setup, Stoa.catch) end
		end)
	end
end
