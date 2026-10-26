-- Stoa: the minimap in Stoa's hand. The compass art goes and the zone name
-- is set in the serif. By default the map is a square with rounded corners,
-- like Stoa's windows and cards, framed by a hairline and an accent line; it
-- shows a little more of the world than a circle of the same width, and
-- leaves the medallion as the one circle on the console. The round map, in
-- rings, is a setting, and with the Painted ornament either shape wears its
-- leather and brass frame instead of the lines (Tools/art/minimap_frames.py). The wheel zooms. Every Blizzard part is looked up carefully, so a renamed
-- frame costs one detail, not the map.
local _, ns = ...
local Stoa = ns.Stoa
local UI = Stoa.UI

local MinimapStyle = Stoa:NewModule("Minimap", { shape = "square" })

local MASK = UI.MEDIA .. "Textures\\MinimapMask"
-- The painted frames, centred on their openings: how much wider than the
-- map each one is.
local PAINTED = {
	square = { file = "MinimapFrameSquare", scale = 1.374 },
	round = { file = "MinimapFrameRing", scale = 1.450 },
}

local function hide(region)
	if region and region.Hide then
		region:Hide()
		if region.SetAlpha then region:SetAlpha(0) end
	end
end

function MinimapStyle:Style()
	local map = Minimap
	if not map then return end

	hide(MinimapCompassTexture)
	hide(MinimapBorder)
	hide(MinimapBorderTop)
	if MinimapCluster then hide(MinimapCluster.BorderTop) end

	-- The frame sits behind the map, so the map itself covers its centre.
	local frame = CreateFrame("Frame", nil, map:GetParent() or UIParent)
	frame:SetFrameLevel(math.max(map:GetFrameLevel() - 1, 0))
	frame:SetAllPoints(map)
	self.ring = frame

	local painted = UI.ornate()
	if self.db.shape == "square" then
		self:Square(map, frame, painted)
	elseif painted then
		self:Painted(map, "round")
	else
		local size = map:GetWidth()
		local outer = UI.circle(frame, "BACKGROUND", 0, size + 8, "hairline")
		outer:SetPoint("CENTER")
		local gap = UI.circle(frame, "BACKGROUND", 1, size + 6, "panel")
		gap:SetPoint("CENTER")
		local ring = UI.circle(frame, "BACKGROUND", 2, size + 3, "accent")
		ring:SetPoint("CENTER")
	end

	local zone = MinimapZoneText or (MinimapCluster and MinimapCluster.ZoneTextButton and MinimapCluster.ZoneTextButton.ZoneText)
	if zone then Stoa:SetFont(zone, "serif", Stoa.typeSize.label) end

	map:EnableMouseWheel(true)
	map:SetScript("OnMouseWheel", function(_, delta)
		local zoom = map:GetZoom()
		if delta > 0 and zoom < map:GetZoomLevels() - 1 then
			map:SetZoom(zoom + 1)
		elseif delta < 0 and zoom > 0 then
			map:SetZoom(zoom - 1)
		end
	end)
	UI.applyTheme()
end

-- The rounded square: the map masked to Stoa's corner, a dark gap round it,
-- then an accent line and a hairline outside that, as the rings were.
function MinimapStyle:Square(map, frame, painted)
	if not map.SetMaskTexture then return end
	map:SetMaskTexture(MASK)
	-- The blip ring and the round glow belong to the circle.
	hide(MinimapBackdrop)
	if map.SetArchBlobRingScalar then map:SetArchBlobRingScalar(0) end
	if map.SetQuestBlobRingScalar then map:SetQuestBlobRingScalar(0) end
	if not _G.GetMinimapShape then
		_G.GetMinimapShape = function() return "SQUARE" end
	end
	if painted then
		self:Painted(map, "square")
		return
	end
	local gap = UI.sliced(frame, "BACKGROUND", "WindowFill.tga", 4)
	if gap then UI.tint(gap, "panel") end
	local accent = UI.sliced(frame, "BORDER", "WindowEdge.tga", 2)
	if accent then UI.tint(accent, "accent", 0.8) end
	local hair = UI.sliced(frame, "BORDER", "WindowEdge.tga", 5)
	if hair then UI.tint(hair, "hairline") end
end

-- The painted frame lies over the map's edge, so it sits on a frame just
-- above the map; it takes no clicks. Its leather band covers the map's
-- corners, and its brass takes the theme accent.
function MinimapStyle:Painted(map, shape)
	local art = PAINTED[shape]
	local over = CreateFrame("Frame", nil, map)
	over:SetFrameLevel(map:GetFrameLevel() + 1)
	over:SetPoint("CENTER")
	over:SetSize(map:GetWidth() * art.scale, map:GetHeight() * art.scale)
	map:HookScript("OnSizeChanged", function(_, width, height)
		over:SetSize(width * art.scale, height * art.scale)
	end)
	local base = over:CreateTexture(nil, "ARTWORK", nil, 0)
	base:SetTexture(UI.MEDIA .. "Textures\\" .. art.file)
	base:SetAllPoints()
	local lines = over:CreateTexture(nil, "ARTWORK", nil, 1)
	lines:SetTexture(UI.MEDIA .. "Textures\\" .. art.file .. "Lines")
	lines:SetAllPoints()
	UI.tint(lines, "accent")
	self.painted = over
	-- Keep the map's own buttons and pins (mail, tracking, addon icons)
	-- above the band.
	local level = over:GetFrameLevel()
	for _, child in ipairs({ map:GetChildren() }) do
		if child ~= over and child.GetFrameLevel and child:GetFrameLevel() <= level then
			pcall(child.SetFrameLevel, child, level + 1)
		end
	end
end

function MinimapStyle:OnEnable()
	xpcall(self.Style, Stoa.catch, self)
end
