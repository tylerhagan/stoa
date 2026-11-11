-- Stoa: will your DoTs finish it? Drawn on the target plaque.
-- DoesItDie (MIT, by Joe Greive) learns what your DoTs still have to deal
-- from your casts and the hits the game still shows in combat, and hands that
-- out through its public API. When it is installed, Stoa draws its numbers in
-- Stoa's look:
--   Marker: the health bar's last stretch, as much as your DoTs will still
--   take off, in bone, ending at the health's edge.
--   Skull: slides over the portrait coin when they will kill it.
-- And on STOA's nameplates, the same bone stretch on each enemy's bar and a
-- small skull beside its left end, while DoesItDie's own nameplate marker is
-- off (its "Show on nameplates"): with it on, the plates are left to it
-- (Core/Companions.lua), so the two never draw on the same bar.
-- The target's health is secret in combat, so Lua never compares the two:
-- StatusBars do. The marker is a reversed bar scaled to the target's maximum
-- and pinned to the health fill's edge. The skull rides the fill edge of a
-- long bar scaled to the target's health inside a clipped window, so it only
-- comes into view once the DoTs' damage reaches the health.
-- Without DoesItDie this module does nothing.
local _, ns = ...
local Stoa = ns.Stoa
local UI = Stoa.UI

local Lethal = Stoa:NewModule("Lethal", { marker = true, skull = true, plates = true })

local UPDATE = 0.1
-- How long the skull's bar is; the skull starts sliding in at its own width
-- short of lethal (under 1% of the health).
local SLIDE = 4000
local SKULL = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_8"
-- Damage on its way reads as diagonal stripes over a shaded stretch of the
-- bar, with a fine line where the health will land.
local HATCH = "Interface\\AddOns\\Stoa\\Media\\Textures\\Hatch"

-- Gives a marker bar its stripes (tiled, never stretched). The texture's
-- gaps are dark, which keeps the stripes readable on a bar of any colour.
local function hatch(marker)
	local stripes = marker:CreateTexture(nil, "ARTWORK")
	stripes:SetTexture(HATCH, "REPEAT", "REPEAT")
	if stripes.SetSnapToPixelGrid then stripes:SetSnapToPixelGrid(true) stripes:SetTexelSnappingBias(0) end
	if stripes.SetHorizTile then stripes:SetHorizTile(true) end
	if stripes.SetVertTile then stripes:SetVertTile(true) end
	marker:SetStatusBarTexture(stripes)
end

local function paintHatch(marker, edge)
	local r, g, b = Stoa:Color("text")
	marker:SetStatusBarColor(r, g, b)
	marker:GetStatusBarTexture():SetAlpha(1)
	edge:SetColorTexture(r, g, b, 0.9)
end

local function api()
	local did = rawget(_G, "DoesItDie")
	if type(did) == "table" and type(did.GetRemainingDamage) == "function" then return did end
end

function Lethal:Available()
	return api() ~= nil
end

function Lethal:Build()
	local halo = Stoa.modules.Halo
	local target = halo and halo.target
	if not (target and target.hp and target.plaque) then return false end
	local hp = target.hp

	-- Marker, clipped to the health bar so damage past the health doesn't
	-- spill over the plaque.
	local clip = CreateFrame("Frame", nil, target)
	clip:SetPoint("TOPLEFT", hp, "TOPLEFT", 0, 1)
	clip:SetPoint("BOTTOMRIGHT", hp, "BOTTOMRIGHT", 0, -1)
	clip:SetClipsChildren(true)
	clip:SetFrameLevel(hp:GetFrameLevel() + 2)
	local marker = CreateFrame("StatusBar", nil, clip)
	hatch(marker)
	marker:SetReverseFill(true)
	marker:SetPoint("TOP", clip, "TOP")
	marker:SetPoint("BOTTOM", clip, "BOTTOM")
	marker:SetPoint("RIGHT", hp:GetStatusBarTexture(), "RIGHT")
	marker:SetWidth(hp:GetWidth())
	local edge = marker:CreateTexture(nil, "OVERLAY")
	Stoa.UI.pixel(edge, "width")
	edge:SetPoint("TOPLEFT", marker:GetStatusBarTexture(), "TOPLEFT")
	edge:SetPoint("BOTTOMLEFT", marker:GetStatusBarTexture(), "BOTTOMLEFT")
	self.clip, self.marker, self.markerEdge = clip, marker, edge

	-- Skull over the portrait coin: a dark disc and the skull, sliding in.
	local coin = target.plaque.coin
	local size = coin:GetWidth()
	local window = CreateFrame("Frame", nil, coin)
	window:SetAllPoints(coin)
	window:SetClipsChildren(true)
	window:SetFrameLevel(coin:GetFrameLevel() + 4)
	local slide = CreateFrame("StatusBar", nil, window)
	slide:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
	slide:SetStatusBarColor(0, 0, 0, 0)
	slide:SetSize(SLIDE, size)
	slide:SetPoint("RIGHT", window, "RIGHT")
	local holder = CreateFrame("Frame", nil, slide)
	holder:SetSize(size, size)
	holder:SetPoint("RIGHT", slide:GetStatusBarTexture(), "RIGHT")
	local shade = UI.circle(holder, "ARTWORK", 0, size - 10)
	shade:SetPoint("CENTER")
	shade:SetColorTexture(0, 0, 0, 0.6)
	local skull = holder:CreateTexture(nil, "OVERLAY")
	skull:SetSize(size * 0.5, size * 0.5)
	skull:SetPoint("CENTER")
	skull:SetTexture(SKULL)
	skull:SetDesaturated(true)
	self.window, self.slide, self.skull = window, slide, skull

	self:Paint()
	Stoa:On("STOA_THEME_CHANGED", function() self:Paint() end)
	self:Hide()
	return true
end

function Lethal:Paint()
	paintHatch(self.marker, self.markerEdge)
	self.skull:SetVertexColor(Stoa:Color("danger"))
end

function Lethal:Hide()
	if not self.clip then return end
	self.clip:Hide()
	self.window:Hide()
end

function Lethal:Update()
	local did = api()
	if not self.clip then return end
	if not did or not UnitExists("target") then return self:Hide() end
	local dead = UnitIsDead("target")
	if Stoa:IsSecret(dead) then dead = false end
	local ok, damage, count = pcall(did.GetRemainingDamage, "target")
	if dead or not ok or not count or count == 0 or not damage or damage <= 0 then return self:Hide() end
	local drawn = pcall(function()
		self.marker:SetWidth(Stoa.modules.Halo.target.hp:GetWidth())
		self.marker:SetMinMaxValues(0, UnitHealthMax("target"))
		self.marker:SetValue(damage)
		self.slide:SetMinMaxValues(0, UnitHealth("target"))
		self.slide:SetValue(damage)
	end)
	if not drawn then return self:Hide() end
	self.clip:SetShown(self.db.marker)
	self.window:SetShown(self.db.skull)
end

-- Nameplates -------------------------------------------------------------------

local PLATE_SKULL = 11
local plateMarks = {} -- health bar -> its marks

local function platesWanted()
	return Lethal.db.plates and Stoa:IsModuleEnabled("Plates") and not Stoa:SharedBy("dotPlates")
end

local function buildPlateMarks(bar)
	local marks = {}
	local clip = CreateFrame("Frame", nil, bar)
	clip:SetPoint("TOPLEFT", bar, "TOPLEFT", 0, 0)
	clip:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", 0, 0)
	clip:SetClipsChildren(true)
	clip:SetFrameLevel(bar:GetFrameLevel() + 1)
	local marker = CreateFrame("StatusBar", nil, clip)
	hatch(marker)
	marker:SetReverseFill(true)
	marker:SetPoint("TOP", clip, "TOP")
	marker:SetPoint("BOTTOM", clip, "BOTTOM")
	marker:SetPoint("RIGHT", bar:GetStatusBarTexture(), "RIGHT")
	local edge = marker:CreateTexture(nil, "OVERLAY")
	UI.pixel(edge, "width")
	edge:SetPoint("TOPLEFT", marker:GetStatusBarTexture(), "TOPLEFT")
	edge:SetPoint("BOTTOMLEFT", marker:GetStatusBarTexture(), "BOTTOMLEFT")
	-- The skull beside the bar's left end, small and plain, in a clipped window.
	local window = CreateFrame("Frame", nil, bar)
	window:SetSize(PLATE_SKULL, PLATE_SKULL)
	window:SetPoint("RIGHT", bar, "LEFT", -3, 0)
	window:SetClipsChildren(true)
	window:SetFrameLevel(bar:GetFrameLevel() + 4)
	local slide = CreateFrame("StatusBar", nil, window)
	slide:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
	slide:SetStatusBarColor(0, 0, 0, 0)
	slide:SetSize(SLIDE, PLATE_SKULL)
	slide:SetPoint("RIGHT", window, "RIGHT")
	local skull = slide:CreateTexture(nil, "OVERLAY")
	skull:SetSize(PLATE_SKULL, PLATE_SKULL)
	skull:SetPoint("RIGHT", slide:GetStatusBarTexture(), "RIGHT")
	skull:SetTexture(SKULL)
	skull:SetDesaturated(true)
	marks.clip, marks.marker, marks.edge, marks.window, marks.slide, marks.skull = clip, marker, edge, window, slide, skull
	return marks
end

local function paintPlateMarks(marks)
	paintHatch(marks.marker, marks.edge)
	marks.skull:SetVertexColor(Stoa:Color("text"))
end

local function hidePlateMarks(marks)
	marks.clip:Hide()
	marks.window:Hide()
	marks.unit = nil
end

function Lethal:UpdatePlate(unit)
	if type(unit) ~= "string" or not unit:find("^nameplate") then return end
	local plates = Stoa.modules.Plates
	local bar = plates and plates.HealthBar and plates:HealthBar(unit)
	if not bar then return end
	local marks = plateMarks[bar]
	local did = api()
	local damage, count
	if did and platesWanted() then
		local ok, d, c = pcall(did.GetRemainingDamage, unit)
		if ok then damage, count = d, c end
	end
	local dead = UnitIsDead(unit)
	if Stoa:IsSecret(dead) then dead = false end
	if dead or not count or count == 0 or not damage or damage <= 0 then
		if marks then hidePlateMarks(marks) end
		return
	end
	if not marks then
		marks = buildPlateMarks(bar)
		paintPlateMarks(marks)
		plateMarks[bar] = marks
	end
	local drawn = pcall(function()
		marks.marker:SetWidth(bar:GetWidth())
		marks.marker:SetMinMaxValues(0, UnitHealthMax(unit))
		marks.marker:SetValue(damage)
		marks.slide:SetMinMaxValues(0, UnitHealth(unit))
		marks.slide:SetValue(damage)
	end)
	if not drawn then return hidePlateMarks(marks) end
	marks.unit = unit
	marks.clip:Show()
	marks.window:SetShown(self.db.skull)
end

-- Every plate on screen: after a setting changes, and on a light tick while
-- marks are up (health moves on its own).
function Lethal:UpdatePlates()
	for bar, marks in pairs(plateMarks) do
		if marks.unit and not bar:IsVisible() then hidePlateMarks(marks) end
	end
	if not (C_NamePlate and C_NamePlate.GetNamePlates) then return end
	for _, plate in ipairs(C_NamePlate.GetNamePlates() or {}) do
		local unit = plate.UnitFrame and plate.UnitFrame.unit
		if unit then self:UpdatePlate(unit) end
	end
end

function Lethal:EnablePlates()
	Stoa:On("STOA_PLATE_ADDED", function(unit) self:UpdatePlate(unit) end)
	Stoa:On("NAME_PLATE_UNIT_REMOVED", function()
		for bar, marks in pairs(plateMarks) do
			if marks.unit and not bar:IsVisible() then hidePlateMarks(marks) end
		end
	end)
	Stoa:On("STOA_THEME_CHANGED", function()
		for _, marks in pairs(plateMarks) do paintPlateMarks(marks) end
	end)
	Stoa:NewTicker(0.2, function()
		for _, marks in pairs(plateMarks) do
			if marks.unit then return self:UpdatePlates() end
		end
	end)
	self:UpdatePlates()
end

function Lethal:Refresh()
	self:Update()
	self:UpdatePlates()
end

-- Who marks the nameplates ---------------------------------------------------------
-- Does It Die draws its own marker on nameplates until its "Show on
-- nameplates" is Off, and STOA's marks wait for that. So the player needn't
-- hunt for the switch, STOA's setting (and a question asked once) turns it
-- for them: the one value DoesItDieDB.nameplateMode, which Does It Die reads
-- afresh on every update. What it held before is kept, to hand back.
local function theirSettings()
	local db = rawget(_G, "DoesItDieDB")
	return type(db) == "table" and db or nil
end

-- "theirs" while Does It Die draws on nameplates, else "stoa" or "off".
function Lethal:PlateOwner()
	local theirs = theirSettings()
	if theirs and (theirs.nameplateMode or "markerIcon") ~= "off" then return "theirs" end
	return self.db.plates and "stoa" or "off"
end

function Lethal:SetPlateOwner(owner)
	local theirs = theirSettings()
	if not theirs then return end
	local mode = theirs.nameplateMode or "markerIcon"
	if owner == "theirs" then
		if mode == "off" then theirs.nameplateMode = self.db.theirPlateMode or "markerIcon" end
	else
		if mode ~= "off" then self.db.theirPlateMode = mode end
		theirs.nameplateMode = "off"
		self.db.plates = owner == "stoa"
	end
	if self.enabled then self:Refresh() end
end

-- Asked once per account, after the welcome page and the other questions
-- about addons, while both would otherwise wait on each other.
function Lethal:AskPlates()
	if Stoa.db.askedDotPlates or not self:Available() or not self.db.plates then return end
	if not Stoa:IsModuleEnabled("Plates") or self:PlateOwner() ~= "theirs" then return end
	if Stoa.Welcome and Stoa.Welcome:Pending() then return end
	local busy = (Stoa.Conflicts and Stoa.Conflicts.asking) or (Stoa.Looks and Stoa.Looks.asking)
	if busy or InCombatLockdown() then
		C_Timer.After(15, function() self:AskPlates() end)
		return
	end
	if not self.askPage then
		local function answer(owner)
			Stoa.db.askedDotPlates = true
			self.askPage:Hide()
			if owner == "stoa" then
				self:SetPlateOwner("stoa")
				Stoa:Print("STOA now marks your DoTs on nameplates. Settings, Combat, DoT marks on nameplates changes it back.")
			end
		end
		self.askPage = Stoa.Conflicts:Page("StoaDotPlatesPage", function() answer("stoa") end, function() answer("theirs") end)
	end
	local page = self.askPage
	page.title:SetText("DoT marks on nameplates")
	page.body:SetText("Does It Die is drawing its own marker on your nameplates. STOA can draw it instead, in its own look: a bone stretch on the health bar for the damage your DoTs still have to deal, and a small skull once they will kill.")
	page.note:SetText("Using STOA's turns off Does It Die's \"Show on nameplates\" for you. Nothing else of it changes, and Settings, Combat can hand it back.")
	page.left.text:SetText("Use STOA's marks")
	page.right.text:SetText("Leave it")
	page:Show()
end

function Lethal:OnEnable()
	if not self:Available() then return end
	-- The API says when its numbers change, for the target and each plate.
	pcall(DoesItDie.RegisterCallback, "Stoa", function(_, unit)
		if unit == "target" then self:Update() else self:UpdatePlate(unit) end
	end)
	self:EnablePlates()
	C_Timer.After(12, function() self:AskPlates() end)
	if not Stoa:IsModuleEnabled("Halo") or not self:Build() then return end
	-- Health moves on its own, so a light tick keeps the bars' scale
	-- current while DoTs are up.
	Stoa:On("PLAYER_TARGET_CHANGED", function() self:Update() end)
	local elapsed = 0
	self.clip:GetParent():HookScript("OnUpdate", function(_, delta)
		elapsed = elapsed + delta
		if elapsed < UPDATE then return end
		elapsed = 0
		if self.clip:IsShown() or self.window:IsShown() then self:Update() end
	end)
	self:Update()
end
