-- Stoa: map comforts.
--   Fade: the world map goes see-through while you move, so you can read the
--   ground through it. The game's own "mapFade" setting is used where this
--   client has it; otherwise the map's alpha follows your movement.
--   Levels: a quiet "Level 10-20" under the map's title and on the minimap's
--   zone tooltip. The game's own numbers (C_Map.GetMapLevels) are used when
--   it has them; Forever gives none, so a small table of the classic
--   levelling zones fills in. English zone names only.
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

-- "Level 10-20" for a zone, or nil. The game's numbers come first.
function Map:Levels(name, mapID)
	if mapID and C_Map and C_Map.GetMapLevels then
		local ok, low, high = pcall(C_Map.GetMapLevels, mapID)
		low, high = Stoa:PlainNumber(low), Stoa:PlainNumber(high)
		if ok and low and high and low > 0 then
			return low == high and ("Level %d"):format(low) or ("Level %d-%d"):format(low, high)
		end
	end
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
		label:SetPoint("TOP", title, "BOTTOM", 0, -1)
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
end

function Map:SetupLevels()
	if not WorldMapFrame then return end
	if self.levelsHooked then return end
	self.levelsHooked = true
	if WorldMapFrame.OnMapChanged then
		hooksecurefunc(WorldMapFrame, "OnMapChanged", function() Map:ShowMapLevels() end)
	end
	WorldMapFrame:HookScript("OnShow", Stoa:Guard(function() Map:ShowMapLevels() end, "Map"))
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
