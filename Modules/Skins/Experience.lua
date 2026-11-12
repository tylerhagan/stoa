-- Stoa: Blizzard's experience bar in STOA's dress.
-- The bar along the bottom of the screen (and the reputation, honor and
-- other bars that share its place) loses its frame, its segmented art and
-- its glossy fill for a thin flat bar in the same rounded dark track as the
-- nameplates and the swing timer. Experience fills in the accent like the
-- medallion's bezel, the rested stretch runs on in mana blue, and the
-- segment dividers become fine dark notches. Edit Mode still places it.
local _, ns = ...
local Stoa = ns.Stoa
local hooksecurefunc = Stoa.SafeHook
local UI = Stoa.UI

local XPBar = Stoa:NewModule("XPBar")

local HEIGHT = 6
local PAD = 2
local CONTAINERS = { "MainStatusTrackingBarContainer", "SecondaryStatusTrackingBarContainer" }

local guarded = Stoa.safe.guarded

-- Textures moved here never draw again, whatever Blizzard does to them.
local vault = CreateFrame("Frame")
vault:Hide()
local function bury(tex)
	if tex and tex.SetParent then tex:SetParent(vault) end
end

-- Reputation by standing, Hated to Exalted: red, orange, bone, then green.
-- A paragon or friendship bar Blizzard draws blue runs in mana blue.
local GREEN = { 0.56, 0.76, 0.50 }
local STANDING = { "hostile", "hostile", "danger", "text", GREEN, GREEN, GREEN, GREEN }

local function barColour(bar)
	local enum = StatusTrackingBarInfo and StatusTrackingBarInfo.BarsEnum
	local kind = bar.stoaColour
	if not kind and enum then
		if bar.barIndex == enum.Honor then kind = "hostile" end
	end
	kind = kind or "accent"
	if type(kind) == "table" then return kind[1], kind[2], kind[3] end
	return Stoa:Color(kind)
end

local function colourBar(bar)
	local status = bar.StatusBar
	if not status then return end
	if not status.stoaTexture then
		status:SetStatusBarTexture(UI.WHITE)
		status.stoaTexture = true
	end
	local r, g, b = barColour(bar)
	status:SetStatusBarColor(r, g, b, 1)
	local fill = status:GetStatusBarTexture()
	if fill then fill:SetVertexColor(r, g, b, 1) end
	local rested = bar.ExhaustionLevelFillBar
	if rested then
		local mr, mg, mb = Stoa:Color("mana")
		rested:SetVertexColor(mr, mg, mb, 0.55)
	end
	if bar.stoaTick then
		local mr, mg, mb = Stoa:Color("mana")
		bar.stoaTick:SetVertexColor(mr, mg, mb, 0.95)
	end
end

-- Blizzard swaps the fill's art as you level, go rested or change faction;
-- each swap is turned back to the flat fill straight away.
local function keepFlat(status)
	status.stoaTexture = nil
	local bar = status:GetParent()
	if bar then colourBar(bar) end
end

local function fitBar(bar)
	local status = bar.StatusBar
	if status then status:SetHeight(HEIGHT) end
end

local function dressBar(bar)
	if not bar or bar.stoaDressed or not bar.StatusBar then return end
	bar.stoaDressed = true
	local status = bar.StatusBar
	bury(status.Background)
	fitBar(bar)

	-- The track sits on the bar's own frame, under the rested stretch and
	-- the fill (the fill's frame draws over its parent).
	local track = UI.pillFill(bar, 0)
	track:ClearAllPoints()
	track:SetPoint("TOPLEFT", status, "TOPLEFT", -PAD, PAD)
	track:SetPoint("BOTTOMRIGHT", status, "BOTTOMRIGHT", PAD, -PAD)
	UI.tint(track, "panel", 0.85)
	UI.pillEdge(status, PAD):Set(0, 0, 0, 0.9)

	if status.SetBarTexture then hooksecurefunc(status, "SetBarTexture", keepFlat) end

	-- Reputation: the standing decides the colour.
	if bar.UpdateBarTextures then
		hooksecurefunc(bar, "UpdateBarTextures", function(own, level, blue)
			own.stoaColour = blue and "mana" or STANDING[level or 4] or "text"
			colourBar(own)
		end)
	end

	-- Experience: the rested stretch flat and the height of the fill, and a
	-- fine blue line where it ends instead of Blizzard's pip.
	local rested = bar.ExhaustionLevelFillBar
	if rested then
		rested:SetTexture(UI.WHITE)
		rested:ClearAllPoints()
		rested:SetPoint("TOPLEFT", status, "TOPLEFT")
		rested:SetPoint("BOTTOMLEFT", status, "BOTTOMLEFT")
	end
	local pip = bar.ExhaustionTick
	if pip then
		for _, key in ipairs({ "Normal", "Highlight" }) do
			if pip[key] then pip[key]:SetAlpha(0) end
		end
		local tick = pip:CreateTexture(nil, "OVERLAY")
		tick:SetTexture(UI.WHITE)
		tick:SetSize(1, HEIGHT + PAD * 2)
		tick:SetPoint("CENTER")
		bar.stoaTick = tick
	end

	local text = bar.OverlayFrame and bar.OverlayFrame.Text
	if text then
		Stoa:SetFont(text, "sans", Stoa.typeSize.caption)
		UI.legible(text)
	end
	colourBar(bar)
end

-- Blizzard's dividers (20 on Forever's bar) as fine dark notches that only
-- show where the bar has filled.
local function notch(container)
	local pool = container.HorizontalDividersPool
	if not pool or not pool.EnumerateActive then return end
	for divider in pool:EnumerateActive() do
		local tex = divider.BarDividerTexture
		if tex then
			tex:SetTexture(UI.WHITE)
			tex:SetVertexColor(0, 0, 0, 0.55)
			tex:ClearAllPoints()
			tex:SetPoint("CENTER")
			tex:SetSize(1, HEIGHT)
		end
	end
end

local function dressContainer(container)
	if not container or container.stoaDressed or type(container.bars) ~= "table" then return end
	container.stoaDressed = true
	bury(container.BarFrameTexture)
	for _, bar in pairs(container.bars) do guarded(dressBar, bar) end
	if container.UpdateDividers then
		hooksecurefunc(container, "UpdateDividers", notch)
	end
	if container.ResizeContainerBars then
		hooksecurefunc(container, "ResizeContainerBars", function(own)
			for _, bar in pairs(own.bars) do fitBar(bar) end
		end)
	end
	notch(container)
end

function XPBar:Dress()
	for _, name in ipairs(CONTAINERS) do
		guarded(dressContainer, _G[name])
	end
	UI.applyTheme()
	self.dressed = true
end

function XPBar:Recolour()
	for _, name in ipairs(CONTAINERS) do
		local container = _G[name]
		if container and container.stoaDressed then
			for _, bar in pairs(container.bars) do
				if bar.stoaDressed then guarded(colourBar, bar) end
			end
		end
	end
end

function XPBar:OnEnable()
	Stoa:On("STOA_THEME_CHANGED", function() XPBar:Recolour() end)
	self:Dress()
end
