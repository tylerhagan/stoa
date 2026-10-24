-- Stoa: the minimap in Stoa's hand. The compass art goes, a hairline and an
-- accent ring frame the map, and the zone name is set in the serif. The
-- wheel zooms. Every Blizzard part is looked up carefully, so a renamed
-- frame costs one detail, not the map.
local _, ns = ...
local Stoa = ns.Stoa
local UI = Stoa.UI

local MinimapStyle = Stoa:NewModule("Minimap")

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

	-- The rings sit behind the map, so the map itself covers their centres.
	local frame = CreateFrame("Frame", nil, map:GetParent() or UIParent)
	frame:SetFrameLevel(math.max(map:GetFrameLevel() - 1, 0))
	frame:SetAllPoints(map)
	local size = map:GetWidth()
	local outer = UI.circle(frame, "BACKGROUND", 0, size + 8, "hairline")
	outer:SetPoint("CENTER")
	local gap = UI.circle(frame, "BACKGROUND", 1, size + 6, "panel")
	gap:SetPoint("CENTER")
	local ring = UI.circle(frame, "BACKGROUND", 2, size + 3, "accent")
	ring:SetPoint("CENTER")
	self.ring = frame

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

function MinimapStyle:OnEnable()
	xpcall(self.Style, Stoa.catch, self)
end
