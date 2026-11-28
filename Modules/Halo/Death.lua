-- Stoa: will Shadow Word: Death kill it? For Shadow priests.
-- Death hits back as hard as it hit unless the target dies, so it is best
-- cast as a finisher. STOA works out the smallest hit Death will do (the
-- low end of the spell's own description, which carries your spell power,
-- less a safety margin) and shows where that reaches:
--   Target plaque and nameplates: a fine line on the health bar where
--   Death's hit ends, and the health left inside it tinted, so once Death
--   will finish the target the whole of its health is tinted.
--   Combat bar: a ring round the Death button while it will kill.
-- The target's health is secret in Forever, so Lua never compares the two:
-- StatusBars do, the same way as the DoT marks (Lethal.lua). The line is a
-- bar scaled to the target's maximum health, the tint a bar laid over the
-- health fill and scaled to the health left (the client caps it there), and
-- the ring rides the fill end of a long bar scaled to the health left
-- inside a clipped window, so it only comes into view once the hit reaches
-- the health.
local _, ns = ...
local Stoa = ns.Stoa
local UI = Stoa.UI

local Death = Stoa:NewModule("Death", { plaque = true, plates = true, button = true, weaving = false })

local UPDATE = 0.1
local RECALC = 1
-- How long the ring's bar is: it starts sliding in its own width short of
-- lethal (about 1% of the health), which the margin covers.
local SLIDE = 4000
local RING = 5        -- how far the ring stands out round the button
local MARGIN = 0.10   -- taken off the smallest hit, for resists and rounding
local WEAVING = 1.10  -- Shadow Weaving at 5 stacks: 10% more shadow damage
local SHADOW = 6      -- shadow school, for spell power
local COEFF = 0.429   -- Death's spell power share, for the table below
local MASK = UI.MEDIA .. "Textures\\ButtonMask"
local TINT_ALPHA = 0.55
local LINE_ALPHA = 0.9

-- Forever's ranks (their own IDs, not the old ones) and their base hit, for
-- when the description can't be read.
local RANKS = {
	{ id = 1309636, min = 447 },
	{ id = 1309635, min = 402 },
	{ id = 1309633, min = 368 },
	{ id = 1309595, min = 294 },
}
Death.FIRST_RANK = RANKS[#RANKS].id

local function knows(id)
	if IsPlayerSpell and IsPlayerSpell(id) then return true end
	return IsSpellKnown and IsSpellKnown(id) or false
end

local function topRank()
	for _, rank in ipairs(RANKS) do
		if knows(rank.id) then return rank end
	end
end

local function spellName()
	return C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(Death.FIRST_RANK)
end

-- The low end of the hit from the description ("inflicts 447 to 474"),
-- when it reads and is near the table's (it carries spell power, so it
-- reads above).
local function described(rank)
	if not (C_Spell and C_Spell.GetSpellDescription) then return nil end
	local ok, text = pcall(C_Spell.GetSpellDescription, rank.id)
	if not ok or type(text) ~= "string" or Stoa:IsSecret(text) then return nil end
	local low = text:match("(%d[%d,%.]*)")
	low = low and tonumber((low:gsub("%D", "")))
	if low and low >= rank.min * 0.5 and low <= rank.min * 3 then return low end
end

-- The smallest hit Death is sure to do now, a plain number, or nil.
function Death:SafeHit()
	local rank = topRank()
	if not rank then return nil end
	local low = described(rank)
	if not low then
		local power = Stoa:PlainNumber(GetSpellBonusDamage and GetSpellBonusDamage(SHADOW))
		if power then self.power = power end
		low = rank.min + COEFF * (self.power or 0)
	end
	if self.db.weaving then low = low * WEAVING end
	return math.floor(low * (1 - MARGIN))
end

function Death:Active()
	local shadow = Stoa.modules.Shadow
	return shadow and shadow.Active and shadow:Active() and topRank() ~= nil or false
end

-- Marks on a health bar ----------------------------------------------------------

local function newBar(parent, token, alpha)
	local bar = CreateFrame("StatusBar", nil, parent)
	local fill = bar:CreateTexture(nil, "ARTWORK")
	fill:SetColorTexture(1, 1, 1, 1)
	bar:SetStatusBarTexture(fill)
	UI.tint(bar:GetStatusBarTexture(), token, alpha)
	bar:SetMinMaxValues(0, 1)
	bar:SetValue(0)
	return bar
end

-- The line and the tint on one health bar (the plaque's or a nameplate's).
local function buildMarks(hp)
	local marks = {}
	local clip = CreateFrame("Frame", nil, hp)
	clip:SetAllPoints(hp)
	clip:SetClipsChildren(true)
	clip:SetFrameLevel(hp:GetFrameLevel() + 1)
	-- Tint: over the health fill, scaled to the health left.
	local tint = newBar(clip, "accent", TINT_ALPHA)
	tint:SetPoint("TOPLEFT", hp:GetStatusBarTexture(), "TOPLEFT")
	tint:SetPoint("BOTTOMRIGHT", hp:GetStatusBarTexture(), "BOTTOMRIGHT")
	-- Line: a see-through bar over the whole width scaled to the most
	-- health, with a pixel line where its fill ends.
	local reach = CreateFrame("StatusBar", nil, clip)
	reach:SetAllPoints(clip)
	reach:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
	reach:SetStatusBarColor(0, 0, 0, 0)
	reach:SetMinMaxValues(0, 1)
	local line = reach:CreateTexture(nil, "OVERLAY")
	UI.pixel(line, "width")
	line:SetPoint("TOPRIGHT", reach:GetStatusBarTexture(), "TOPRIGHT")
	line:SetPoint("BOTTOMRIGHT", reach:GetStatusBarTexture(), "BOTTOMRIGHT")
	line:SetColorTexture(1, 1, 1, 1)
	UI.tint(line, "accent", LINE_ALPHA)
	marks.clip, marks.tint, marks.reach = clip, tint, reach
	clip:Hide()
	return marks
end

local function drawMarks(marks, unit, hit)
	local ok = pcall(function()
		marks.reach:SetMinMaxValues(0, UnitHealthMax(unit))
		marks.reach:SetValue(hit)
		marks.tint:SetMinMaxValues(0, UnitHealth(unit))
		marks.tint:SetValue(hit)
	end)
	marks.clip:SetShown(ok)
end

local function alive(unit)
	if not UnitExists(unit) then return false end
	local hostile = UnitCanAttack("player", unit)
	if not Stoa:IsSecret(hostile) and not hostile then return false end
	local dead = UnitIsDeadOrGhost(unit)
	return Stoa:IsSecret(dead) or not dead
end

-- Ring on the combat bar ---------------------------------------------------------

-- Built under the button (a lower frame level), so it shows as a rim round
-- it, outside the next-press outline.
local function buildRing(button)
	local window = CreateFrame("Frame", nil, button)
	window:SetPoint("TOPLEFT", -RING, RING)
	window:SetPoint("BOTTOMRIGHT", RING, -RING)
	window:SetClipsChildren(true)
	window:SetFrameStrata(button:GetFrameStrata())
	window:SetFrameLevel(math.max(0, button:GetFrameLevel() - 1))
	local size = (button.size or button:GetWidth()) + RING * 2
	local slide = CreateFrame("StatusBar", nil, window)
	slide:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
	slide:SetStatusBarColor(0, 0, 0, 0)
	slide:SetSize(SLIDE, size)
	slide:SetPoint("RIGHT", window, "RIGHT")
	local ring = slide:CreateTexture(nil, "ARTWORK")
	ring:SetSize(size, size)
	ring:SetPoint("RIGHT", slide:GetStatusBarTexture(), "RIGHT")
	ring:SetTexture(MASK)
	UI.tint(ring, "danger")
	window:Hide()
	return { window = window, slide = slide }
end

-- The combat bar's buttons that hold Death, any rank.
function Death:FindButtons()
	local found = {}
	local bar = Stoa.modules.CombatBar
	local name = spellName()
	if not (name and bar and bar.all and GetActionInfo) then
		self.buttons = found
		return
	end
	for _, button in ipairs(bar.all) do
		if button.slot then
			local kind, id = GetActionInfo(button.slot)
			if kind == "spell" and id and not Stoa:IsSecret(id) and C_Spell.GetSpellName(id) == name then
				found[#found + 1] = button
			end
		end
	end
	self.buttons = found
end

-- Drawing ------------------------------------------------------------------------

function Death:HideAll()
	if self.plaque then self.plaque.clip:Hide() end
	for _, marks in pairs(self.plateMarks) do
		marks.clip:Hide()
		marks.unit = nil
	end
	for _, ring in pairs(self.rings) do ring.window:Hide() end
end

function Death:DrawPlaque(hit)
	local halo = Stoa.modules.Halo
	local target = halo and halo.target
	if not (self.db.plaque and hit and target and target.hp and alive("target")) then
		if self.plaque then self.plaque.clip:Hide() end
		return
	end
	self.plaque = self.plaque or buildMarks(target.hp)
	drawMarks(self.plaque, "target", hit)
end

function Death:DrawPlates(hit)
	local plates = Stoa.modules.Plates
	local wanted = self.db.plates and hit and plates and plates.HealthBar and Stoa:IsModuleEnabled("Plates")
	for bar, marks in pairs(self.plateMarks) do
		if not wanted or not bar:IsVisible() then
			marks.clip:Hide()
			marks.unit = nil
		end
	end
	if not wanted or not (C_NamePlate and C_NamePlate.GetNamePlates) then return end
	for _, plate in ipairs(C_NamePlate.GetNamePlates() or {}) do
		local unit = plate.UnitFrame and plate.UnitFrame.unit
		local bar = unit and plates:HealthBar(unit)
		if bar then
			local marks = self.plateMarks[bar]
			if alive(unit) then
				if not marks then
					marks = buildMarks(bar)
					self.plateMarks[bar] = marks
				end
				marks.unit = unit
				drawMarks(marks, unit, hit)
			elseif marks then
				marks.clip:Hide()
				marks.unit = nil
			end
		end
	end
end

function Death:DrawRings(hit)
	local lit = {}
	if self.db.button and hit and alive("target") then
		for _, button in ipairs(self.buttons or {}) do
			-- Rings are made out of combat; a button first seen in a fight
			-- gets its ring after it.
			local ring = self.rings[button]
			if not ring and not InCombatLockdown() then
				ring = buildRing(button)
				self.rings[button] = ring
			end
			if ring and button:IsVisible() then
				local ok = pcall(function()
					ring.slide:SetMinMaxValues(0, UnitHealth("target"))
					ring.slide:SetValue(hit)
				end)
				if ok then lit[button] = true end
			end
		end
	end
	for button, ring in pairs(self.rings) do ring.window:SetShown(lit[button] == true) end
end

function Death:Update(recalc)
	if not self.active then return self:HideAll() end
	if recalc or not self.hit then
		self.hit = self:SafeHit()
		self:FindButtons()
	end
	local hit = self.hit
	self:DrawPlaque(hit)
	self:DrawPlates(hit)
	self:DrawRings(hit)
end

function Death:Refresh()
	self.active = self:Active()
	self.driver:SetShown(self.active)
	self:Update(true)
end

function Death:OnEnable()
	self.plateMarks, self.rings = {}, {}
	self.driver = CreateFrame("Frame")
	self.driver:Hide()
	local sinceUpdate, sinceRecalc = 0, 0
	self.driver:SetScript("OnUpdate", function(_, delta)
		sinceUpdate = sinceUpdate + delta
		if sinceUpdate < UPDATE then return end
		sinceRecalc = sinceRecalc + sinceUpdate
		sinceUpdate = 0
		local recalc = sinceRecalc >= RECALC
		if recalc then sinceRecalc = 0 end
		xpcall(self.Update, Stoa.catch, self, recalc)
	end)
	local function refresh() xpcall(self.Refresh, Stoa.catch, self) end
	for _, event in ipairs({ "STOA_ROLE_CHANGED", "SPELLS_CHANGED", "PLAYER_LEVEL_UP", "ACTIONBAR_SLOT_CHANGED", "PLAYER_REGEN_ENABLED" }) do
		Stoa:On(event, refresh)
	end
	refresh()
end
