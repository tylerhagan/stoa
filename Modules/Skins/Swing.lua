-- Stoa: Blizzard's swing timer in Stoa's dress.
-- Forever's own swing timer (Edit Mode places it) loses its art for a flat
-- bar in the same rounded dark track as the nameplates: pale gold for the
-- main hand, blue for the off hand, bone for ranged. The weapon's name is
-- quiet on the left, the time left on the right; out of range, both turn
-- amber instead of Blizzard's red.
local _, ns = ...
local Stoa = ns.Stoa
local hooksecurefunc = Stoa.SafeHook
local UI = Stoa.UI

local Swing = Stoa:NewModule("Swing")

local PAD = 2
local FRAMES = {
	{ name = "SwingTimerMainHandFrame", token = "accent" },
	{ name = "SwingTimerOffHandFrame", token = "mana" },
	{ name = "SwingTimerRangedFrame", token = "text" },
}

local guarded = Stoa.safe.guarded

-- Textures moved here never draw again, whatever Blizzard does to them.
local vault = CreateFrame("Frame")
vault:Hide()
local function bury(tex)
	if tex and tex.SetParent then tex:SetParent(vault) end
end

local function colourLabels(frame)
	local bar = frame.StatusBar
	if not bar then return end
	local away = frame.IsOutOfRange and frame:IsOutOfRange()
	if bar.TypeLabel then bar.TypeLabel:SetTextColor(Stoa:Color(away and "danger" or "muted")) end
	if bar.TimeLabel then bar.TimeLabel:SetTextColor(Stoa:Color(away and "danger" or "text")) end
end

local function colourBar(frame)
	local bar = frame.StatusBar
	local fill = bar and bar:GetStatusBarTexture()
	if fill then fill:SetVertexColor(Stoa:Color(frame.stoaToken)) end
	if bar and bar.Pip then bar.Pip:SetVertexColor(Stoa:Color("text")) end
end

local function dress(frame, token)
	if not frame or frame.stoaDressed then return end
	frame.stoaDressed = true
	frame.stoaToken = token
	bury(frame.Background)
	bury(frame.Border)
	local bar = frame.StatusBar
	if not bar then return end
	bury(bar.TypeLabelShadow)
	bar:SetStatusBarTexture(UI.WHITE)
	-- The pip rides the end of the fill; Blizzard anchors it to the fill
	-- texture, which changed with the new texture.
	if bar.Pip then
		bar.Pip:ClearAllPoints()
		bar.Pip:SetPoint("RIGHT", bar:GetStatusBarTexture(), "RIGHT", 0, 0)
		bar.Pip:SetDesaturated(true)
	end
	UI.tint(UI.pillFill(bar, PAD), "panel", 0.85)
	UI.pillEdge(bar, PAD):Set(0, 0, 0, 0.9)
	for _, fs in ipairs({ bar.TypeLabel, bar.TimeLabel }) do
		local _, size = fs:GetFont()
		Stoa:SetFont(fs, "sans", size or Stoa.typeSize.caption)
		UI.legible(fs)
	end
	if frame.ApplyRangePresentation then
		hooksecurefunc(frame, "ApplyRangePresentation", colourLabels)
	end
	UI.applyTheme()
	colourBar(frame)
	colourLabels(frame)
end

function Swing:Dress()
	for _, entry in ipairs(FRAMES) do
		guarded(dress, _G[entry.name], entry.token)
	end
end

function Swing:OnEnable()
	Stoa:On("STOA_THEME_CHANGED", function()
		for _, entry in ipairs(FRAMES) do
			local frame = _G[entry.name]
			if frame and frame.stoaDressed then
				guarded(colourBar, frame)
				guarded(colourLabels, frame)
			end
		end
	end)
	if _G.SwingTimerMainHandFrame then
		self:Dress()
	else
		Stoa:On("ADDON_LOADED", function(name)
			if name == "Blizzard_SwingTimer" then guarded(Swing.Dress, Swing) end
		end)
	end
end
