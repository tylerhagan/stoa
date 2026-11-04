-- Stoa: Blizzard's swing timer in Stoa's dress.
-- Forever's own swing timer (Edit Mode places it) loses its art for a flat
-- bar in the same rounded dark track as the nameplates: pale gold for the
-- main hand, blue for the off hand, bone for ranged. The weapon's name is
-- quiet on the left, the time left on the right; out of range, both turn
-- amber instead of Blizzard's red.
-- Blizzard stacks the timers above its own action bar, which Stoa keeps in
-- the console, so they would sit inside it. Stoa holds them just above the
-- Halo's cast bar instead, on a frame you can move like the rest
-- (/stoa unlock, "Swing timer").
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

-- Where the timers hang: a holder Stoa owns and the movers can drag.
local GAP = 4
local holder

-- The timers are Edit Mode systems kept by the game's bottom layout, which
-- reparents and lays them out itself. Each is taken out of that layout the
-- game's own way (BreakFromFrameManager, as Edit Mode does when you drag
-- one) and anchored with its base SetPoint, which skips Edit Mode's
-- snapping.
local function free(frame)
	if frame.BreakFromFrameManager then
		pcall(frame.BreakFromFrameManager, frame)
	else
		frame.ignoreFramePositionManager = true
		if frame:GetParent() ~= UIParent then frame:SetParent(UIParent) end
	end
end

local function anchor(frame, ...)
	local clear = frame.ClearAllPointsBase or frame.ClearAllPoints
	local set = frame.SetPointBase or frame.SetPoint
	clear(frame)
	set(frame, ...)
end

local function place()
	if not holder or InCombatLockdown() then return end
	local above = holder
	for i, entry in ipairs(FRAMES) do
		local frame = _G[entry.name]
		if frame then
			frame.stoaPlacing = true
			free(frame)
			if i == 1 then
				anchor(frame, "BOTTOM", holder, "BOTTOM", 0, 0)
			else
				anchor(frame, "BOTTOM", above, "TOP", 0, GAP)
			end
			frame.stoaPlacing = nil
			above = frame
		end
	end
end

local function later()
	Stoa:AfterCombat(function() guarded(place) end)
end

local function hold(frame)
	if not frame or frame.stoaHeld then return end
	frame.stoaHeld = true
	-- Edit Mode layouts and the bottom layout put it back on their own;
	-- follow them with Stoa's spot.
	for _, method in ipairs({ "ApplySystemAnchor", "SetPoint", "SetPointBase" }) do
		if type(frame[method]) == "function" then
			hooksecurefunc(frame, method, function(self)
				if not self.stoaPlacing then later() end
			end)
		end
	end
end

function Swing:Hold()
	if not holder then
		holder = CreateFrame("Frame", "StoaSwingHolder", UIParent)
		holder:SetSize(200, 14)
		local halo = Stoa.modules.Halo
		local cast = halo and halo.cast
		local function default()
			holder:ClearAllPoints()
			if cast then
				holder:SetPoint("BOTTOM", cast, "TOP", 0, 28)
			else
				holder:SetPoint("CENTER", UIParent, "CENTER", 0, -220)
			end
		end
		default()
		Stoa:RegisterMover("swing", holder, "Swing timer", { default = default })
		hooksecurefunc(holder, "SetPoint", later)
	end
	for _, entry in ipairs(FRAMES) do guarded(hold, _G[entry.name]) end
	later()
end

function Swing:Dress()
	for _, entry in ipairs(FRAMES) do
		guarded(dress, _G[entry.name], entry.token)
	end
	self:Hold()
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
