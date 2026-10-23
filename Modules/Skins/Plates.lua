-- Stoa: nameplates in Stoa's hand.
-- Blizzard still builds and drives every plate (so hidden combat values keep
-- working); Stoa changes how they look:
--   * a flat bar on a dark ground with a fine dark edge, an amber edge on
--     your target instead of Blizzard's white frame
--   * colour by what you can do, not red/yellow/green: amber for an enemy,
--     pale gold for neutral, blue for friends, and grey only for tapped or
--     dead, as in the base game; enemy players keep class colour
--   * names and cast text in Stoa's sans with a fine outline
--   * cast bars on a dark ground with a cropped icon; Blizzard's shield
--     still marks a cast you can't interrupt
-- Plates the game won't let addons touch (friendly plates in instances) are
-- left alone.
local _, ns = ...
local Stoa = ns.Stoa
local UI = Stoa.UI

local Plates = Stoa:NewModule("Plates")

local function guarded(fn, ...)
	xpcall(fn, geterrorhandler(), ...)
end

local function isPlate(frame)
	local unit = frame and frame.unit
	return type(unit) == "string" and not Stoa:IsSecret(unit) and unit:find("^nameplate") ~= nil
		and not (frame.IsForbidden and frame:IsForbidden())
end

-- Reads a unit fact, or nil when the game hides it.
local function known(value)
	if Stoa:IsSecret(value) then return nil end
	return value
end

-- Colour ---------------------------------------------------------------------

local function healthToken(frame)
	local unit = frame.unit
	if not known(UnitIsConnected(unit)) or known(UnitIsDead(unit)) then return "muted", 0.6 end
	if known(UnitIsPlayer(unit)) and known(UnitCanAttack("player", unit)) then
		local _, class = UnitClass(unit)
		local color = Stoa:Theme().classTint and known(class) and RAID_CLASS_COLORS[class]
		if color then return color end
		return "health"
	end
	if known(UnitIsTapDenied(unit)) and not known(UnitPlayerControlled(unit)) then return "muted", 0.6 end
	local reaction = known(UnitReaction(unit, "player"))
	if reaction and reaction >= 5 then return "mana" end
	if reaction == 4 then return "accent" end
	return "danger"
end

local function colourHealth(frame)
	if not frame.stoaDressed or not isPlate(frame) then return end
	local token, alpha = healthToken(frame)
	local r, g, b
	if type(token) == "table" then
		r, g, b = token.r, token.g, token.b
	else
		r, g, b = Stoa:Color(token)
	end
	frame.healthBar:SetStatusBarColor(r, g, b, alpha or 1)
end

local function colourName(frame)
	if not frame.stoaDressed or not isPlate(frame) or not frame.name then return end
	local unit = frame.unit
	if known(UnitIsDead(unit)) or (known(UnitIsTapDenied(unit)) and not known(UnitPlayerControlled(unit))) then
		frame.name:SetVertexColor(Stoa:Color("muted"))
		return
	end
	if known(UnitIsPlayer(unit)) then
		local _, class = UnitClass(unit)
		local color = Stoa:Theme().classTint and known(class) and RAID_CLASS_COLORS[class]
		if color then
			frame.name:SetVertexColor(color.r, color.g, color.b)
			return
		end
	end
	frame.name:SetVertexColor(Stoa:Color("text"))
end

-- Type -----------------------------------------------------------------------

-- Keeps the size Blizzard chose (it follows the nameplate size setting).
local function sans(fs)
	if not (fs and fs.GetFont) then return end
	local _, size = fs:GetFont()
	Stoa:SetFont(fs, "sans", size or Stoa.typeSize.body)
	UI.legible(fs)
end

local function refont(frame)
	sans(frame.name)
	local bar = frame.healthBar
	if bar then
		sans(bar.Text)
		sans(bar.LeftText)
		sans(bar.RightText)
	end
	local cast = frame.CastBarsContainer and frame.CastBarsContainer.castBar
	if cast then
		sans(cast.Text)
		sans(cast.CastTargetNameText)
	end
end

-- Target edge ----------------------------------------------------------------

local function targetEdge(frame)
	local edge = frame.stoaTargetEdge
	if not edge then return end
	if frame.IsTarget and frame:IsTarget() then
		edge:Set(Stoa:Color("text"))
	else
		edge:Clear()
	end
end

-- Dressing -------------------------------------------------------------------

local function dressCast(cast)
	if not cast or cast.stoaDressed then return end
	cast.stoaDressed = true
	if cast.Background then
		cast.Background:SetTexture(UI.WHITE)
		cast.Background:SetVertexColor(Stoa:Color("panel"))
		cast.Background:SetAlpha(0.85)
	end
	if cast.Border then cast.Border:SetAlpha(0) end
	if cast.Icon then cast.Icon:SetTexCoord(0.08, 0.92, 0.08, 0.92) end
	local edge = UI.border(cast, 1, 1)
	edge:Set(0, 0, 0, 0.9)
end

local function dress(frame)
	if frame.stoaDressed then return end
	frame.stoaDressed = true

	local bar = frame.healthBar
	if bar then
		bar:SetStatusBarTexture(UI.WHITE)
		if bar.bgTexture then
			bar.bgTexture:SetTexture(UI.WHITE)
			bar.bgTexture:SetVertexColor(Stoa:Color("panel"))
			bar.bgTexture:SetAlpha(0.85)
		end
		if bar.selectedBorder then bar.selectedBorder:SetAlpha(0) end
		local edge = UI.border(bar, 1, 1)
		edge:Set(0, 0, 0, 0.9)
		frame.stoaTargetEdge = UI.border(bar, 1, 2)
		if bar.SetIsTarget then hooksecurefunc(bar, "SetIsTarget", function() targetEdge(frame) end) end
	end
	dressCast(frame.CastBarsContainer and frame.CastBarsContainer.castBar)

	-- Blizzard sets fonts again whenever plate options change.
	if frame.ApplyFrameOptions then hooksecurefunc(frame, "ApplyFrameOptions", refont) end
	refont(frame)
end

function Plates:Added(unit)
	local plate = C_NamePlate.GetNamePlateForUnit(unit)
	local frame = plate and plate.UnitFrame
	if not frame or (frame.IsForbidden and frame:IsForbidden()) then return end
	dress(frame)
	colourHealth(frame)
	colourName(frame)
	targetEdge(frame)
	Stoa:Fire("STOA_PLATE_ADDED", unit, frame)
end

-- The health bar of a unit's plate, for marks other modules hang on it.
function Plates:HealthBar(unit)
	local plate = C_NamePlate and C_NamePlate.GetNamePlateForUnit and C_NamePlate.GetNamePlateForUnit(unit)
	local frame = plate and plate.UnitFrame
	if not frame or (frame.IsForbidden and frame:IsForbidden()) or not frame.stoaDressed then return nil end
	return frame.healthBar
end

function Plates:OnEnable()
	if not (C_NamePlate and C_NamePlate.GetNamePlateForUnit) then return end
	if CompactUnitFrame_UpdateHealthColor then
		hooksecurefunc("CompactUnitFrame_UpdateHealthColor", function(frame) guarded(colourHealth, frame) end)
	end
	if CompactUnitFrame_UpdateName then
		hooksecurefunc("CompactUnitFrame_UpdateName", function(frame) guarded(colourName, frame) end)
	end
	local driver = _G.NamePlateDriverFrame
	if driver and driver.OnNamePlateAdded then
		hooksecurefunc(driver, "OnNamePlateAdded", function(_, unit) guarded(Plates.Added, Plates, unit) end)
	else
		Stoa:On("NAME_PLATE_UNIT_ADDED", function(unit) C_Timer.After(0, function() guarded(Plates.Added, Plates, unit) end) end)
	end
	Stoa:On("STOA_THEME_CHANGED", function()
		for _, plate in ipairs(C_NamePlate.GetNamePlates() or {}) do
			local frame = plate.UnitFrame
			if frame and frame.stoaDressed then
				guarded(colourHealth, frame)
				guarded(colourName, frame)
				guarded(targetEdge, frame)
			end
		end
	end)
	for _, plate in ipairs(C_NamePlate.GetNamePlates and C_NamePlate.GetNamePlates() or {}) do
		local unit = plate.UnitFrame and plate.UnitFrame.unit
		if unit then guarded(Plates.Added, Plates, unit) end
	end
end
