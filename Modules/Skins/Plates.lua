-- Stoa: nameplates in Stoa's hand.
-- Blizzard still builds and drives every plate (so hidden combat values keep
-- working); Stoa changes how they look:
--   * a flat bar in a rounded dark track, and a rounded bone edge around
--     your target instead of Blizzard's frame
--   * colour by what you can do, not red/yellow/green: amber for an enemy,
--     pale gold for neutral, blue for friends, and grey only for tapped or
--     dead, as in the base game; enemy players keep class colour
--   * names and cast text in Stoa's sans with a fine outline; the level as
--     a plain number shaded by how hard the fight is
--   * cast bars on a dark ground with a cropped icon; Blizzard's shield
--     still marks a cast you can't interrupt
-- Plates the game won't let addons touch (friendly plates in instances) are
-- left alone.
--
-- Styles (Settings, Nameplate style), all in the theme's colours:
--   Stoa   : the rounded track above
--   Bold   : a heavy dark frame, a bevelled bar, the health value in it
--   Inline : name at the bar's left and health at its right, inside it
--   Brass  : a brass edge and a level badge on the bar's end
--   Slim   : a thin bar under the name, for busy pulls
-- The target can be marked by its edge, by arrows either side, or by a soft
-- glow behind it; plates you aren't targeting can fade, and the target can
-- grow a little (the game's own scale setting).
local _, ns = ...
local Stoa = ns.Stoa
local hooksecurefunc = Stoa.SafeHook
local UI = Stoa.UI

local Plates = Stoa:NewModule("Plates", {
	style = "stoa",
	marker = "edge",
	-- 0 to 100: how much plates you aren't targeting fade while you have one.
	fade = 0,
	fadeChoice = "0",
	-- 100 to 150: the target plate's size, in percent.
	targetScale = 100,
	scaleChoice = "100",
})

-- Bar height (nil keeps Blizzard's), edge kind and what's written in it.
local STYLES = {
	stoa = { },
	bold = { height = 16, box = 3, bevel = true, value = "CENTER", nameSize = 2 },
	inline = { height = 18, pill = true, value = "RIGHT", nameInside = true },
	brass = { height = 12, brass = true, bevel = true, badge = true },
	slim = { height = 5, pill = true },
}

function Plates:Style()
	return STYLES[self.db.style] or STYLES.stoa
end

-- How far the rounded track reaches past the bar's own edges.
local PAD = 2

local function guarded(fn, ...)
	xpcall(fn, Stoa.catch, ...)
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

-- Level ----------------------------------------------------------------------
-- The level sits as a plain number beside the bar. Its shade says how hard
-- the fight is by lightness, not green to red: muted for easy, bone for a
-- fair fight, pale gold a few levels up, amber well above you.

local function levelToken(diff)
	local trivial = C_QuestLog and C_QuestLog.GetTrivialRange and C_QuestLog.GetTrivialRange() or 5
	if diff < -trivial or diff <= -3 then return "muted" end
	if diff <= 2 then return "text" end
	if diff <= 4 then return "accent" end
	return "danger"
end

local function colourLevel(frame)
	if not frame.stoaDressed or not isPlate(frame) then return end
	local level = frame.PlayerLevelDiffFrame
	local text = level and level.playerLevelDiffText
	if not (text and level:IsShown()) then return end
	local theirs = known(UnitEffectiveLevel(frame.unit))
	local mine = known(UnitEffectiveLevel("player"))
	if not (theirs and mine) or theirs <= 0 then return end
	local token = known(UnitCanAttack("player", frame.unit)) and levelToken(theirs - mine) or "muted"
	text:SetText(theirs)
	text:SetTextColor(Stoa:Color(token))
end

-- Target edge ----------------------------------------------------------------

local function isTarget(frame)
	if frame.unit and not Stoa:IsSecret(frame.unit) then
		local same = UnitIsUnit(frame.unit, "target")
		if not Stoa:IsSecret(same) then return same and true or false end
	end
	return frame.IsTarget and frame:IsTarget() or false
end

local function targetEdge(frame)
	local edge = frame.stoaTargetEdge
	if not edge then return end
	local target = isTarget(frame)
	local marker = Plates.db.marker
	if target and marker == "edge" then
		edge:Set(Stoa:Color("text"))
	else
		edge:Clear()
	end
	local parts = frame.stoaParts
	if parts then
		for _, arrow in ipairs(parts.arrows) do arrow:SetShown(target and marker == "arrows") end
		parts.glow:SetShown(target and marker == "glow")
	end
	-- Plates you aren't targeting fade while you have a target.
	local fade = (Plates.db.fade or 0) / 100
	local alpha = 1
	if fade > 0 and not target and UnitExists("target") then alpha = 1 - fade end
	frame:SetAlpha(alpha)
end

-- Style parts -----------------------------------------------------------------
-- Built once per plate, hidden; the chosen style shows its own.

local function arrowTexture(tex, flip)
	local atlas = flip and "common-icon-backarrow" or "common-icon-forwardarrow"
	if not (C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(atlas) and pcall(tex.SetAtlas, tex, atlas)) then
		tex:SetTexture("Interface\\Buttons\\UI-SpellbookIcon-NextPage-Up")
		if flip then tex:SetTexCoord(1, 0, 0, 1) end
	end
end

local function buildParts(frame)
	local bar = frame.healthBar
	local parts = { arrows = {} }
	local holder = CreateFrame("Frame", nil, bar)
	holder:SetAllPoints()
	holder:SetFrameLevel(bar:GetFrameLevel() + 2)
	parts.holder = holder

	-- Bold: a dark box well past the bar's edges.
	local box = bar:CreateTexture(nil, "BACKGROUND", nil, -7)
	box:SetPoint("TOPLEFT", -3, 3)
	box:SetPoint("BOTTOMRIGHT", 3, -3)
	box:SetColorTexture(0, 0, 0, 0.92)
	parts.box = box
	-- A bevel: light along the top, shade along the foot, over the fill.
	local bevel = holder:CreateTexture(nil, "ARTWORK")
	bevel:SetAllPoints(bar)
	bevel:SetColorTexture(1, 1, 1, 1)
	if bevel.SetGradient and CreateColor then
		bevel:SetGradient("VERTICAL", CreateColor(0, 0, 0, 0.35), CreateColor(1, 1, 1, 0.22))
	else
		bevel:SetAlpha(0.12)
	end
	parts.bevel = bevel

	-- Brass: an accent edge and a small level badge on the right.
	parts.brass = UI.border(holder, 2, 2)
	local badge = CreateFrame("Frame", nil, holder)
	badge:SetSize(26, 18)
	badge:SetPoint("LEFT", bar, "RIGHT", 3, 0)
	local badgeFill = badge:CreateTexture(nil, "BACKGROUND")
	badgeFill:SetAllPoints()
	badgeFill:SetColorTexture(0, 0, 0, 0.85)
	badge.edge = UI.border(badge, 2, 0)
	badge.text = UI.text(badge, "sans", Stoa.typeSize.caption, "accent", "CENTER")
	badge.text:SetPoint("CENTER", 0, 0)
	parts.badge = badge

	-- Words inside the bar.
	parts.value = UI.text(holder, "sans", Stoa.typeSize.caption, "text", "CENTER")
	UI.legible(parts.value)
	parts.name = UI.text(holder, "sans", Stoa.typeSize.caption, "text", "LEFT")
	parts.name:SetPoint("LEFT", bar, "LEFT", 5, 0)
	parts.name:SetPoint("RIGHT", bar, "RIGHT", -44, 0)
	parts.name:SetWordWrap(false)
	UI.legible(parts.name)

	-- Target marks.
	for i, flip in ipairs({ false, true }) do
		local arrow = holder:CreateTexture(nil, "OVERLAY")
		arrow:SetSize(14, 22)
		arrowTexture(arrow, flip)
		arrow:SetVertexColor(Stoa:Color("text"))
		if i == 1 then arrow:SetPoint("RIGHT", bar, "LEFT", -6, 0) else arrow:SetPoint("LEFT", bar, "RIGHT", 6, 0) end
		arrow:Hide()
		parts.arrows[i] = arrow
	end
	local glow = bar:CreateTexture(nil, "BACKGROUND", nil, -8)
	glow:SetPoint("TOPLEFT", -22, 16)
	glow:SetPoint("BOTTOMRIGHT", 22, -16)
	glow:SetTexture("Interface\\GLUES\\Models\\UI_Draenei\\GenericGlow64")
	glow:SetBlendMode("ADD")
	UI.tint(glow, "accent", 0.55)
	glow:Hide()
	parts.glow = glow

	frame.stoaParts = parts
	return parts
end

local function healthValue(frame)
	local parts = frame.stoaParts
	if not parts or not parts.value:IsShown() then return end
	local ok = pcall(function()
		local now = UnitHealth(frame.unit)
		parts.value:SetText(AbbreviateLargeNumbers and AbbreviateLargeNumbers(now) or now)
	end)
	if not ok then parts.value:SetText("") end
end

local function plateLevel(frame)
	local parts = frame.stoaParts
	if not (parts and parts.badge:IsShown()) then return end
	local theirs = known(UnitEffectiveLevel(frame.unit))
	if not theirs then parts.badge.text:SetText("") return end
	parts.badge.text:SetText(theirs > 0 and theirs or "??")
end

local function plateName(frame)
	local parts = frame.stoaParts
	if not (parts and parts.name:IsShown()) then return end
	pcall(function() parts.name:SetText(UnitName(frame.unit)) end)
end

-- Shows the chosen style's parts and sizes the bar.
local function applyStyle(frame)
	if not frame.stoaDressed or not isPlate(frame) then return end
	local style = Plates:Style()
	local parts = frame.stoaParts or buildParts(frame)
	local bar = frame.healthBar
	if style.height and not (bar.IsProtected and bar:IsProtected()) then bar:SetHeight(style.height) end
	local pill = not style.box and not style.brass
	frame.stoaPillFill:SetShown(pill)
	frame.stoaPillEdge:SetShown(pill)
	parts.box:SetShown(style.box and true or false)
	parts.bevel:SetShown(style.bevel and true or false)
	if style.brass then parts.brass:Set(Stoa:Color("accent")) else parts.brass:Clear() end
	parts.badge:SetShown(style.badge and true or false)
	if style.badge then parts.badge.edge:Set(Stoa:Color("accent")) end
	parts.value:ClearAllPoints()
	if style.value == "RIGHT" then
		parts.value:SetPoint("RIGHT", bar, "RIGHT", -5, 0)
	else
		parts.value:SetPoint("CENTER", bar, "CENTER", 0, 0)
	end
	parts.value:SetShown(style.value and true or false)
	parts.name:SetShown(style.nameInside and true or false)
	if frame.name then frame.name:SetAlpha(style.nameInside and 0 or 1) end
	-- The level sits on the badge in the brass style.
	local level = frame.PlayerLevelDiffFrame
	if level then level:SetAlpha(style.badge and 0 or 1) end
	healthValue(frame)
	plateLevel(frame)
	plateName(frame)
	targetEdge(frame)
end

-- Dressing -------------------------------------------------------------------

local function dressCast(cast)
	if not cast or cast.stoaDressed then return end
	cast.stoaDressed = true
	if cast.Background then cast.Background:SetAlpha(0) end
	if cast.Border then cast.Border:SetAlpha(0) end
	if cast.Icon then cast.Icon:SetTexCoord(0.08, 0.92, 0.08, 0.92) end
	UI.tint(UI.pillFill(cast, PAD), "panel", 0.85)
	UI.pillEdge(cast, PAD):Set(0, 0, 0, 0.9)
end

local function dress(frame)
	if frame.stoaDressed then return end
	frame.stoaDressed = true

	local bar = frame.healthBar
	if bar then
		bar:SetStatusBarTexture(UI.WHITE)
		if bar.bgTexture then bar.bgTexture:SetAlpha(0) end
		if bar.selectedBorder then bar.selectedBorder:SetAlpha(0) end
		-- The fill runs square inside a rounded dark track a little larger
		-- than the bar, so the corners read rounded without masking it.
		frame.stoaPillFill = UI.tint(UI.pillFill(bar, PAD), "panel", 0.85)
		local edge = UI.pillEdge(bar, PAD)
		edge:Set(0, 0, 0, 0.9)
		frame.stoaPillEdge = { SetShown = function(_, shown) if shown then edge:Set(0, 0, 0, 0.9) else edge:Clear() end end }
		frame.stoaTargetEdge = UI.pillEdge(bar, PAD + 1)
		if bar.SetIsTarget then hooksecurefunc(bar, "SetIsTarget", function() targetEdge(frame) end) end
	end
	dressCast(frame.CastBarsContainer and frame.CastBarsContainer.castBar)
	local level = frame.PlayerLevelDiffFrame
	if level then
		if level.playerLevelDiffIcon then level.playerLevelDiffIcon:SetAlpha(0) end
		if level.selectedBorder then level.selectedBorder:SetAlpha(0) end
		sans(level.playerLevelDiffText)
	end

	UI.applyTheme()
	-- Blizzard sets fonts again whenever plate options change.
	if frame.ApplyFrameOptions then
		hooksecurefunc(frame, "ApplyFrameOptions", function(own)
			refont(own)
			guarded(applyStyle, own)
		end)
	end
	refont(frame)
end

function Plates:Added(unit)
	local plate = C_NamePlate.GetNamePlateForUnit(unit)
	local frame = plate and plate.UnitFrame
	if not frame or (frame.IsForbidden and frame:IsForbidden()) then return end
	dress(frame)
	colourHealth(frame)
	colourName(frame)
	colourLevel(frame)
	if frame.healthBar then guarded(applyStyle, frame) end
	Stoa:Fire("STOA_PLATE_ADDED", unit, frame)
end

-- The health bar of a unit's plate, for marks other modules hang on it.
function Plates:HealthBar(unit)
	local plate = C_NamePlate and C_NamePlate.GetNamePlateForUnit and C_NamePlate.GetNamePlateForUnit(unit)
	local frame = plate and plate.UnitFrame
	if not frame or (frame.IsForbidden and frame:IsForbidden()) or not frame.stoaDressed then return nil end
	return frame.healthBar
end

local function eachPlate(fn)
	for _, plate in ipairs(C_NamePlate.GetNamePlates and C_NamePlate.GetNamePlates() or {}) do
		local frame = plate.UnitFrame
		if frame and frame.stoaDressed then guarded(fn, frame) end
	end
end

-- Settings changes: restyle every plate on screen.
function Plates:Restyle()
	self:TargetScale()
	eachPlate(applyStyle)
end

function Plates:TargetScale()
	local set = (C_CVar and C_CVar.SetCVar) or SetCVar
	if set and not InCombatLockdown() then
		pcall(set, "nameplateSelectedScale", tostring((self.db.targetScale or 100) / 100))
	end
end

function Plates:OnEnable()
	if not (C_NamePlate and C_NamePlate.GetNamePlateForUnit) then return end
	if CompactUnitFrame_UpdateHealth then
		hooksecurefunc("CompactUnitFrame_UpdateHealth", function(frame)
			if frame and frame.stoaParts then guarded(healthValue, frame) end
		end)
	end
	Stoa:On("PLAYER_TARGET_CHANGED", function() eachPlate(targetEdge) end)
	if (self.db.targetScale or 100) ~= 100 then Stoa:AfterCombat(function() self:TargetScale() end) end
	if CompactUnitFrame_UpdateHealthColor then
		hooksecurefunc("CompactUnitFrame_UpdateHealthColor", function(frame) guarded(colourHealth, frame) end)
	end
	if CompactUnitFrame_UpdateName then
		hooksecurefunc("CompactUnitFrame_UpdateName", function(frame)
			guarded(colourName, frame)
			if frame and frame.stoaParts then guarded(plateName, frame) end
		end)
	end
	if CompactUnitFrame_UpdatePlayerLevelDiff then
		hooksecurefunc("CompactUnitFrame_UpdatePlayerLevelDiff", function(frame)
			guarded(colourLevel, frame)
			if frame and frame.stoaParts then guarded(plateLevel, frame) end
		end)
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
