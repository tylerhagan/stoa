-- Stoa: the minimap in Stoa's hand. The compass art goes and the zone name
-- is set in the serif. By default the map is a square with rounded corners,
-- like Stoa's windows and cards, framed by a hairline and an accent line; it
-- shows a little more of the world than a circle of the same width, and
-- leaves the medallion as the one circle on the console. The round map, in
-- rings, is a setting. The wheel zooms. Every Blizzard part is looked up carefully, so a renamed
-- frame costs one detail, not the map.
local _, ns = ...
local Stoa = ns.Stoa
local UI = Stoa.UI

local MinimapStyle = Stoa:NewModule("Minimap", { shape = "square" })

local MASK = UI.MEDIA .. "Textures\\MinimapMask"

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

	if self.db.shape == "square" then
		self:Square(map, frame)
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
function MinimapStyle:Square(map, frame)
	if not map.SetMaskTexture then return end
	map:SetMaskTexture(MASK)
	-- The blip ring and the round glow belong to the circle.
	hide(MinimapBackdrop)
	if map.SetArchBlobRingScalar then map:SetArchBlobRingScalar(0) end
	if map.SetQuestBlobRingScalar then map:SetQuestBlobRingScalar(0) end
	local gap = UI.sliced(frame, "BACKGROUND", "WindowFill.tga", 4)
	if gap then UI.tint(gap, "panel") end
	local accent = UI.sliced(frame, "BORDER", "WindowEdge.tga", 2)
	if accent then UI.tint(accent, "accent", 0.8) end
	local hair = UI.sliced(frame, "BORDER", "WindowEdge.tga", 5)
	if hair then UI.tint(hair, "hairline") end
	-- Other addons place their buttons and pins around the map by asking
	-- its shape; only answer when nobody else has.
	if not _G.GetMinimapShape then
		_G.GetMinimapShape = function() return "SQUARE" end
	end
end

function MinimapStyle:OnEnable()
	xpcall(self.Style, Stoa.catch, self)
end
