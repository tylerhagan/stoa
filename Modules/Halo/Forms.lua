-- Stoa: forms. Some forms change who you are, so STOA changes with them.
--
--   * A look per form (only Shadowform has one so far): while you're in it
--     the console seal's ring and dial and the Halo's signature ring take
--     the form's colour, a soft shade breathes slowly round the seal, and a
--     faint haze of it sits behind the Halo. Entering sends one quick dark
--     pulse across the console; leaving snaps everything back at once.
--   * A row of form chips off the medallion's lower right (the pet coin
--     sits lower left): one round chip per form, lit while you're in it.
--     Click to shift in or out, right-click to leave. Built so paladin
--     auras and druid forms can use the same row in the stance bar's place;
--     for now only the classes in CHIPS get it.
--
-- A medallion that wants the chips elsewhere calls Forms:SetChipSpot.
--
-- Other pieces can wear the look too: STOA_FORM_LOOK fires with the look
-- (its `ring` and `shade` colours) on the way in and with nil on the way
-- out, and Stoa.Forms.look holds the one on now. The Slate player card
-- (which has no round seal to dress) is meant to tint its class mark and
-- accent from it.
--
-- Everything here is laid over the console and the Halo, never into them:
-- their own colours and art are untouched, so a theme change or a new
-- medallion keeps working, and turning this off leaves no trace.
local _, ns = ...
local Stoa = ns.Stoa
local UI = Stoa.UI

local Forms = Stoa:NewModule("Forms", {
	looks = true,
	chips = true,
})
Stoa.Forms = Forms

-- The looks, by the form's spell. `ring` is the bright colour (rings and
-- the dial's lit ticks), `shade` the dark one that breathes round the seal.
local LOOKS = {
	[15473] = { -- Shadowform
		ring = { 0.60, 0.40, 1.00 },
		shade = { 0.20, 0.05, 0.42 },
	},
}

-- Which classes get the chip row, and their forms when the game's form bar
-- doesn't list them.
local CHIPS = {
	PRIEST = { 15473 },
}

local CHIP = 30
local BREATH = 2.6       -- seconds each way
local BREATH_LOW, BREATH_HIGH = 0.3, 0.75
local PULSE_IN, PULSE_OUT = 0.05, 0.13
local PULSE_DARK = 0.45
-- RingGlow.tga's light peaks this far out from its centre (Tools/art/ring_glow.py).
local GLOW_PEAK = 55 / 77
local SEAL_SHADE_OUT = 10   -- the shade's peak, beyond the face's edge
local HALO_HAZE_ALPHA = 0.35

local function knows(spellID)
	if IsPlayerSpell and IsPlayerSpell(spellID) then return true end
	return IsSpellKnown and IsSpellKnown(spellID) or false
end

-- Whether you're in the form `spellID`: its aura on you, or the game's form
-- bar saying so when the aura can't be read.
local function inForm(spellID)
	if C_UnitAuras and C_UnitAuras.GetPlayerAuraBySpellID then
		local ok, aura = pcall(C_UnitAuras.GetPlayerAuraBySpellID, spellID)
		if ok and aura then return true end
	end
	if GetShapeshiftForm and GetShapeshiftFormInfo then
		local index = GetShapeshiftForm()
		if not Stoa:IsSecret(index) and index and index > 0 then
			local _, active, _, id = GetShapeshiftFormInfo(index)
			if id == spellID and active ~= false then return true end
		end
	end
	return false
end

-- The look you're wearing now, or nil.
local function currentLook()
	for spellID, look in pairs(LOOKS) do
		if knows(spellID) and inForm(spellID) then return spellID, look end
	end
end

-- Look ----------------------------------------------------------------------

-- A ring band in the form's colour: a disc just under the face, so only
-- the band round it shows, over the ring it stands in for.
local function band(parent, face, extra)
	local size = face:GetWidth() + extra
	local tex = UI.circle(parent, "ARTWORK", -2, size)
	tex:SetPoint("CENTER", face, "CENTER")
	tex:Hide()
	return tex
end

local function breathe(tex)
	local group = tex:CreateAnimationGroup()
	group:SetLooping("BOUNCE")
	local fade = group:CreateAnimation("Alpha")
	fade:SetFromAlpha(BREATH_LOW)
	fade:SetToAlpha(BREATH_HIGH)
	fade:SetDuration(BREATH)
	fade:SetSmoothing("IN_OUT")
	return group
end

function Forms:BuildLook()
	local parts = {}
	local console = Stoa.modules.Grimoire
	-- Slate's medallion is a flat player card with no round seal: it takes
	-- the look from STOA_FORM_LOOK instead.
	local slate = Stoa.db and Stoa.db.material == "slate"
	if console and console.enabled and console.seal and console.portrait and not slate then
		local seal, face = console.seal, console.portrait
		parts.sealBand = band(seal, face, 4)
		-- The shade round the seal: the ring glow's soft halo, dark.
		local shade = seal:CreateTexture(nil, "BORDER", nil, 3)
		shade:SetTexture(UI.MEDIA .. "Textures\\RingGlow")
		local size = (face:GetWidth() / 2 + SEAL_SHADE_OUT) / GLOW_PEAK * 2
		shade:SetSize(size, size)
		shade:SetPoint("CENTER", face, "CENTER")
		shade:SetAlpha(0)
		shade:Hide()
		parts.sealShade, parts.breath = shade, breathe(shade)
		-- The dial's lit ticks follow the look after every redraw.
		hooksecurefunc(console, "UpdateRing", function() self:PaintTicks() end)
		parts.console = console

		-- The pulse: a dark veil over the whole console, gone in a blink.
		local veil = CreateFrame("Frame", nil, console.frame)
		veil:SetAllPoints()
		veil:SetFrameLevel(console.frame:GetFrameLevel() + 2)
		veil:EnableMouse(false)
		local dark = veil:CreateTexture(nil, "OVERLAY")
		dark:SetAllPoints()
		dark:SetColorTexture(0, 0, 0, 1)
		veil:SetAlpha(0)
		local pulse = veil:CreateAnimationGroup()
		local down = pulse:CreateAnimation("Alpha")
		down:SetFromAlpha(0)
		down:SetToAlpha(PULSE_DARK)
		down:SetDuration(PULSE_IN)
		down:SetOrder(1)
		local up = pulse:CreateAnimation("Alpha")
		up:SetFromAlpha(PULSE_DARK)
		up:SetToAlpha(0)
		up:SetDuration(PULSE_OUT)
		up:SetSmoothing("OUT")
		up:SetOrder(2)
		pulse:SetScript("OnFinished", function() veil:SetAlpha(0) end)
		parts.veil, parts.veilDark, parts.pulse = veil, dark, pulse
	end

	local halo = Stoa.modules.Halo
	if halo and halo.enabled and halo.frame then
		local slot = halo.signature
		if slot and slot.icon and not UI.ornate() then
			parts.haloBand = band(slot, slot.icon, 4)
		end
		-- A faint haze of the form's colour along the Halo's arcs.
		local haze = halo.frame:CreateTexture(nil, "BACKGROUND", nil, -8)
		haze:SetTexture(UI.MEDIA .. "Textures\\RingGlow")
		-- Its light peaks on the arcs, just inside the frame's edge.
		local size = halo.frame:GetWidth() * 0.96 / GLOW_PEAK
		haze:SetSize(size, size)
		haze:SetPoint("CENTER")
		haze:SetBlendMode("ADD")
		haze:Hide()
		parts.haloHaze = haze
	end
	self.parts = parts
end

-- Recolours the dial's ticks that are lit in the accent (the experience
-- done) in the look's colour; the rested and empty ones keep theirs.
function Forms:PaintTicks()
	local look = self.look
	local console = self.parts and self.parts.console
	if not (look and console and console.ringTicks) then return end
	local ar, ag, ab = Stoa:Color("accent")
	local r, g, b = unpack(look.ring)
	for _, tick in ipairs(console.ringTicks) do
		local tr, tg, tb, ta = tick:GetVertexColor()
		if math.abs(tr - ar) < 0.02 and math.abs(tg - ag) < 0.02 and math.abs(tb - ab) < 0.02 then
			tick:SetVertexColor(r, g, b, ta)
		end
	end
end

function Forms:ApplyLook(look, entering)
	local parts = self.parts
	if not parts then return end
	local was = self.look
	self.look = look
	if look then
		local r, g, b = unpack(look.ring)
		local sr, sg, sb = unpack(look.shade)
		for _, key in ipairs({ "sealBand", "haloBand" }) do
			local tex = parts[key]
			if tex then
				tex:SetColorTexture(r, g, b, 1)
				tex:Show()
			end
		end
		if parts.sealShade then
			parts.sealShade:SetVertexColor(sr, sg, sb)
			parts.sealShade:Show()
			if not parts.breath:IsPlaying() then parts.breath:Play() end
		end
		if parts.haloHaze then
			parts.haloHaze:SetVertexColor(r, g, b, HALO_HAZE_ALPHA)
			parts.haloHaze:Show()
		end
		if parts.veilDark then parts.veilDark:SetColorTexture(sr * 0.3, sg * 0.3, sb * 0.3, 1) end
		self:PaintTicks()
		-- The pulse only marks the moment you step in, and only where it
		-- can be seen: the console open on screen.
		if entering and not was and parts.pulse and parts.veil:IsVisible() then
			parts.pulse:Stop()
			parts.pulse:Play()
		end
	else
		-- Leaving snaps back: no fade.
		for _, key in ipairs({ "sealBand", "haloBand", "sealShade", "haloHaze" }) do
			if parts[key] then parts[key]:Hide() end
		end
		if parts.breath then parts.breath:Stop() end
		if was and parts.console and parts.console.UpdateRing then parts.console:UpdateRing() end
	end
	if look ~= was then Stoa:Fire("STOA_FORM_LOOK", look) end
end

function Forms:UpdateLook(entering)
	if not self.db.looks then
		if self.look then self:ApplyLook(nil) end
		return
	end
	local _, look = currentLook()
	if look == self.look then return end
	self:ApplyLook(look, entering)
end

-- Chips ---------------------------------------------------------------------

-- The forms this character's row shows: the game's form bar where it lists
-- them, else the class's own list. Only learned ones.
local function chipForms()
	local _, classFile = UnitClass("player")
	local fallback = CHIPS[classFile]
	if not fallback then return {} end
	local list = {}
	local count = GetNumShapeshiftForms and GetNumShapeshiftForms() or 0
	for i = 1, (Stoa:IsSecret(count) and 0 or count or 0) do
		local _, _, _, spellID = GetShapeshiftFormInfo(i)
		if spellID and not Stoa:IsSecret(spellID) then list[#list + 1] = spellID end
	end
	if #list == 0 then
		for _, spellID in ipairs(fallback) do
			if knows(spellID) then list[#list + 1] = spellID end
		end
	end
	return list
end

function Forms:BuildChip(i)
	local chip = CreateFrame("Button", "StoaFormChip" .. i, UIParent, "SecureActionButtonTemplate")
	chip:SetSize(CHIP, CHIP)
	chip:SetFrameStrata("LOW")
	-- Secure buttons act on press or release by the game's own setting, so
	-- both are taken; the template acts on the one that matches.
	chip:RegisterForClicks("AnyUp", "AnyDown")
	chip:SetAttribute("type1", "spell")
	chip:SetAttribute("type2", "cancelaura")

	local gap = UI.circle(chip, "BACKGROUND", 0, CHIP)
	gap:SetPoint("CENTER")
	UI.paint(gap, "panel", 1)
	local ring = UI.circle(chip, "BORDER", 0, CHIP - 2)
	ring:SetPoint("CENTER")
	local inset = UI.circle(chip, "BORDER", 1, CHIP - 5)
	inset:SetPoint("CENTER")
	UI.paint(inset, "panel", 1)
	local icon = UI.circle(chip, "ARTWORK", 0, CHIP - 8)
	icon:SetPoint("CENTER")
	icon:SetTexCoord(0.1, 0.9, 0.1, 0.9)
	-- The hover lift: the ring brightens, nothing moves.
	chip:SetScript("OnEnter", function(own)
		own.hover = true
		self:PaintChip(own)
		GameTooltip:SetOwner(own, "ANCHOR_TOP")
		local name = own.spellID and C_Spell.GetSpellName(own.spellID) or ""
		GameTooltip:AddLine(name)
		local mr, mg, mb = Stoa:Color("muted")
		GameTooltip:AddLine(own.lit and "Click or right-click to leave it." or "Click to shift into it.", mr, mg, mb)
		GameTooltip:Show()
	end)
	chip:SetScript("OnLeave", function(own)
		own.hover = nil
		self:PaintChip(own)
		GameTooltip:Hide()
	end)
	chip.ring, chip.icon = ring, icon
	return chip
end

function Forms:PaintChip(chip)
	local look = chip.spellID and LOOKS[chip.spellID]
	local r, g, b
	if look then r, g, b = unpack(look.ring) else r, g, b = Stoa:Color("accent") end
	if chip.lit then
		chip.ring:SetColorTexture(r, g, b, 1)
		chip.icon:SetDesaturated(false)
		chip.icon:SetVertexColor(1, 1, 1, 1)
	else
		local tr, tg, tb = Stoa:Color("text")
		chip.ring:SetColorTexture(tr, tg, tb, chip.hover and 0.45 or 0.18)
		chip.icon:SetDesaturated(true)
		chip.icon:SetVertexColor(1, 1, 1, chip.hover and 0.9 or 0.6)
	end
end

-- Sets the row's forms. Attributes can only change out of a fight, so a
-- change in one waits for it to end.
function Forms:LayoutChips()
	if not self.db.chips then return end
	if InCombatLockdown() then
		self.chipsPending = true
		return
	end
	self.chipsPending = nil
	local console = Stoa.modules.Grimoire
	local anchor = _G.StoaSealButton
	if not (console and console.enabled and anchor) then return end
	local forms = chipForms()
	self.chips = self.chips or {}
	for i, spellID in ipairs(forms) do
		local chip = self.chips[i] or self:BuildChip(i)
		self.chips[i] = chip
		local name = C_Spell.GetSpellName(spellID)
		chip.spellID = spellID
		chip:SetAttribute("spell", name)
		chip.icon:SetTexture(C_Spell.GetSpellTexture(spellID))
		chip:ClearAllPoints()
		local spot = self.chipSpot
		local card = console.youCard and console.YOU_CARD
		if spot then
			-- Placed by the medallion's owner (Slate's player card).
			chip:SetPoint("CENTER", spot.frame, spot.point, spot.x + (i - 1) * spot.step, spot.y)
		elseif card and console.OpenHeight then
			-- Slate's player card: just right of the card, on its centre
			-- line. Pinned to the screen, not to the card, which fades in
			-- a fight (the chips hide then anyway).
			chip:SetPoint("CENTER", UIParent, "BOTTOM", card.width / 2 + 8 + CHIP / 2 + (i - 1) * (CHIP + 6), console:OpenHeight() + card.y)
		else
			-- Off the seal's lower right, mirroring the pet coin, running out.
			chip:SetPoint("CENTER", anchor, "BOTTOMRIGHT", (i - 1) * (CHIP + 6), 12)
		end
		chip:SetFrameLevel(console.seal:GetFrameLevel() + 6)
		-- The console folds in a fight and the chips go with it.
		RegisterStateDriver(chip, "visibility", "[combat] hide; show")
	end
	for i = #forms + 1, #self.chips do
		local chip = self.chips[i]
		chip.spellID = nil
		UnregisterStateDriver(chip, "visibility")
		chip:Hide()
	end
	self:UpdateChips()
end

-- Where the chip row sits, for a medallion that wants it somewhere else
-- (Slate's player card): the first chip's centre on `point` of `frame`,
-- offset x, y, each next one `step` further along x (negative runs left).
-- Pass nil to go back to the seal's lower right. Takes effect out of a
-- fight, like every change to the chips.
function Forms:SetChipSpot(frame, point, x, y, step)
	self.chipSpot = frame and { frame = frame, point = point or "CENTER", x = x or 0, y = y or 0, step = step or (CHIP + 6) } or nil
	if self.enabled or self.chips then self:LayoutChips() end
end
Forms.CHIP_SIZE = CHIP

function Forms:UpdateChips()
	for _, chip in ipairs(self.chips or {}) do
		if chip.spellID then
			chip.lit = inForm(chip.spellID)
			self:PaintChip(chip)
		end
	end
end

-- Lifecycle -----------------------------------------------------------------

function Forms:Refresh(entering)
	self:UpdateLook(entering)
	self:UpdateChips()
end

function Forms:OnEnable()
	self:BuildLook()
	self:LayoutChips()

	local function changed()
		xpcall(self.Refresh, Stoa.catch, self, true)
	end
	Stoa:On("UPDATE_SHAPESHIFT_FORM", changed)
	Stoa:On("UNIT_AURA", function(unit)
		if unit == "player" then changed() end
	end)
	local function relayout()
		xpcall(self.LayoutChips, Stoa.catch, self)
	end
	Stoa:On("UPDATE_SHAPESHIFT_FORMS", relayout)
	Stoa:On("SPELLS_CHANGED", relayout)
	Stoa:On("PLAYER_REGEN_ENABLED", function()
		if self.chipsPending then relayout() end
	end)
	-- A theme change repaints the dial in the accent; the look goes back on.
	Stoa:On("STOA_THEME_CHANGED", function()
		if self.look then self:PaintTicks() end
		self:UpdateChips()
	end)
	-- Already in form at login or a reload: the look, without the pulse.
	xpcall(self.Refresh, Stoa.catch, self, false)
end
