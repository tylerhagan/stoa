-- Stoa: party cards, after the Halo healer mockup.
-- One card per party member, with yourself first. Healers get large cards
-- beside the Halo; everyone else gets a compact column on the left.
-- Clicks follow the click-cast bindings (/stoa clicks); by default left
-- click targets and right click opens the unit menu.
--
-- Cards are secure buttons, so they are only built, moved and resized out
-- of combat. In combat Stoa only changes what they show and how bright they
-- are, which is always allowed.
local _, ns = ...
local Stoa = ns.Stoa
local UI = Stoa.UI

local Party = Stoa:NewModule("Party", {
	hideBlizzardParty = true,
})

local UNITS = { "player", "party1", "party2", "party3", "party4" }
local WORLD_ALPHA = 0.75
local OUT_OF_RANGE_ALPHA = 0.45
local GONE_ALPHA = 0.42

-- Card size and spot per role. Healers get a row of cards just under the
-- Halo, where their eyes already are, with the click bindings spelled out
-- beneath. Everyone else gets a column on the left. A position dragged with
-- /stoa unlock wins over these.
local LAYOUTS = {
	HEALER = { width = 176, height = 70, gap = 8, style = "party", row = true, legend = true },
	OTHER = { width = 184, height = 58, gap = 6, style = "compact", point = { "TOPLEFT", UIParent, "LEFT", 36, 180 } },
}

local function layoutFor(role)
	return LAYOUTS[role] or LAYOUTS.OTHER
end

-- Build ---------------------------------------------------------------------

function Party:BuildCard(index, unit)
	local card = CreateFrame("Button", "StoaPartyCard" .. index, self.frame, "SecureUnitButtonTemplate")
	card:SetAttribute("unit", unit)
	card:SetAttribute("type1", "target")
	card:SetAttribute("type2", "togglemenu")
	card:RegisterForClicks("AnyUp")
	card:SetSize(176, 70)
	card.unit = unit
	Stoa:RegisterClickFrame(card)
	UI.unitCard(card, "party")

	card:SetScript("OnEnter", function(button)
		GameTooltip_SetDefaultAnchor(GameTooltip, button)
		GameTooltip:SetUnit(button.unit)
	end)
	card:SetScript("OnLeave", GameTooltip_Hide)

	if unit == "player" then
		-- Your own card only shows in a group; alone the Halo covers you.
		RegisterStateDriver(card, "visibility", "[group] show; hide")
	else
		RegisterUnitWatch(card)
	end
	return card
end

function Party:Build()
	local frame = CreateFrame("Frame", "StoaParty", UIParent)
	frame:SetSize(176, 70)
	frame:SetFrameStrata("LOW")
	-- In a raid the raid grid takes over.
	RegisterStateDriver(frame, "visibility", "[group:raid] hide; show")
	self.frame = frame

	self.cards = {}
	for i, unit in ipairs(UNITS) do
		self.cards[i] = self:BuildCard(i, unit)
	end

	-- What each click does, under the healer row.
	local legend = UI.text(frame, "serif", Stoa.typeSize.body, "text", "CENTER")
	legend:SetPoint("TOP", frame, "BOTTOM", 0, -10)
	self.legend = legend

	UI.applyTheme()
	self:Layout()
	Stoa:RegisterMover("party", frame, "Party")
end

-- How many cards show: you plus your party, or all five in the preview.
function Party:VisibleCount()
	if self.cards and self.cards[1].preview then return #UNITS end
	return math.max(1, math.min(#UNITS, GetNumGroupMembers and GetNumGroupMembers() or 1))
end

-- Sizes and places the cards for the current role. Out of combat only.
function Party:Layout()
	local layout = layoutFor(Stoa:GetRole())
	local frame = self.frame
	local count = self:VisibleCount()
	local halo = _G.StoaHalo
	if not Stoa.char.positions.party then
		frame:ClearAllPoints()
		if layout.row and halo then
			frame:SetPoint("TOP", halo, "BOTTOM", 0, -52)
		elseif layout.row then
			frame:SetPoint("TOP", UIParent, "CENTER", 0, -260)
		else
			frame:SetPoint(unpack(layout.point))
		end
	end
	-- A row is as wide as the cards in it, so it stays centred.
	if layout.row then
		frame:SetSize(count * layout.width + (count - 1) * layout.gap, layout.height)
	else
		frame:SetSize(layout.width, layout.height)
	end
	for i, card in ipairs(self.cards) do
		card:SetSize(layout.width, layout.height)
		card:ClearAllPoints()
		if layout.row then
			card:SetPoint("TOPLEFT", frame, "TOPLEFT", (i - 1) * (layout.width + layout.gap), 0)
		else
			card:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, -(i - 1) * (layout.height + layout.gap))
		end
		UI.styleCard(card, layout.style)
	end
	self.legend:SetShown(layout.legend and true or false)
	self:UpdateLegend()
	self:UpdateAll()
end

local LEGEND_BUTTONS = { ["1"] = "Left", ["2"] = "Right", ["3"] = "Wheel", ["4"] = "Thumb 1", ["5"] = "Thumb 2" }
local LEGEND_ORDER = { "1", "2", "3", "4", "5", "shift-1", "shift-2", "shift-3", "shift-4", "shift-5" }
local LEGEND_MAX = 5

-- Spells only: target and menu need no reminding.
function Party:UpdateLegend()
	if not self.legend:IsShown() then return end
	local clickCast = Stoa.modules.ClickCast
	local bindings = clickCast and clickCast.Bindings and clickCast:Bindings() or {}
	local r, g, b = Stoa:Color("muted")
	local muted = string.format("|cff%02x%02x%02x", r * 255, g * 255, b * 255)
	local parts = {}
	for _, key in ipairs(LEGEND_ORDER) do
		local action = bindings[key]
		if action and action ~= "target" and action ~= "menu" and #parts < LEGEND_MAX then
			local shift, button = key:match("^(shift%-)(%d)$")
			local label = shift and ("Shift-" .. LEGEND_BUTTONS[button]:lower()) or LEGEND_BUTTONS[key]
			parts[#parts + 1] = muted .. label:upper() .. "|r  " .. action
		end
	end
	self.legend:SetText(table.concat(parts, "     "))
end

-- Updates -------------------------------------------------------------------

local LOW_HEALTH = 0.35

local function flag(value)
	if Stoa:IsSecret(value) then return false end
	return value and true or false
end

-- Health as a 0 to 1 fraction when it can be worked out, else nil. In
-- combat health can be secret, and then low health isn't flagged.
local function healthFraction(unit)
	local health, max = UnitHealth(unit), UnitHealthMax(unit)
	if Stoa:IsSecret(health) or Stoa:IsSecret(max) or not max or max <= 0 then return nil end
	return health / max
end

-- The percent in the card's corner. Newer clients hand out a percent that
-- is safe to show even when it's secret; otherwise it's worked out, and
-- failing both the plain health is shown.
local function setPercent(fs, unit, fraction)
	if fraction then
		fs:SetText(math.floor(fraction * 100 + 0.5))
		return
	end
	if UnitHealthPercent and CurveConstants and CurveConstants.ScaleTo100 then
		local ok = pcall(function()
			fs:SetFormattedText("%d", UnitHealthPercent(unit, true, CurveConstants.ScaleTo100))
		end)
		if ok then return end
	end
	fs:SetText(UnitHealth(unit))
end

function Party:UpdateCard(card)
	local unit = card.unit
	-- Cards showing the /stoa test preview keep their sample data.
	if card.preview or not unit or not UnitExists(unit) then return end

	card.name:SetText(UnitName(unit))
	card.name:SetTextColor(UI.classColor(unit))
	UI.setUnitBar(card.hp, unit, "health")

	local gone
	if not flag(UnitIsConnected(unit)) then
		gone = "OFFLINE"
	elseif flag(UnitIsDeadOrGhost(unit)) then
		gone = "DEAD"
	end

	local pips = {}
	local fraction = healthFraction(unit)
	local low = not gone and fraction and fraction < LOW_HEALTH
	local dispel = not gone and self:DispelFor(unit)

	if gone then
		card.percent:SetText("·")
		card.hp:SetValue(0)
		pips[1] = { gone }
	else
		setPercent(card.percent, unit, fraction)
		if dispel then pips[#pips + 1] = { dispel.word, dispel.token } end
		if low then pips[#pips + 1] = { "LOW", "danger" } end
		self:AuraPips(unit, pips)
	end
	UI.setPips(card, pips)

	-- Bar and percent turn amber when low, and the border says why.
	local r, g, b = Stoa:Color(low and "danger" or "health")
	card.hp:SetStatusBarColor(r, g, b)
	card.percent:SetTextColor(Stoa:Color(low and "danger" or "text"))

	card.glow:Clear()
	if dispel then
		local dr, dg, db = Stoa:Color(dispel.token)
		card.state:Set(dr, dg, db)
		card.glow:Set(dr, dg, db, 0.22)
	elseif low then
		card.state:Set(Stoa:Color("danger"))
	elseif flag(UnitIsUnit(unit, "target")) then
		card.state:Set(Stoa:Color("text"))
	else
		card.state:Clear()
	end
	card.gone = gone

	self:UpdateAbsorb(card)
	self:UpdateRange(card)
end

-- Your own buffs worth tracking on a card, as short words. Timers show
-- once there's under half a minute left.
local OWN_BUFFS = {
	["Power Word: Shield"] = { "SHIELD", "shield" },
	["Renew"] = { "RENEW" },
	["Prayer of Mending"] = { "MENDING" },
	["Fear Ward"] = { "WARD" },
	["Power Infusion"] = { "INFUSION" },
	["Inner Fire"] = { "INNER FIRE" },
	["Blessing of Protection"] = { "PROTECTION" },
	["Blessing of Freedom"] = { "FREEDOM" },
	["Blessing of Sacrifice"] = { "SACRIFICE" },
}
-- Debuffs from anyone that change what you can cast on them.
local LOCKOUTS = {
	["Weakened Soul"] = "WS",
	["Forbearance"] = "FORB",
}
local MAX_PIPS = 3

local function timeLeft(aura)
	local expires = aura.expirationTime
	if Stoa:IsSecret(expires) or not expires or expires == 0 then return nil end
	local left = expires - GetTime()
	if left > 0 and left < 30 then return math.floor(left + 0.5) end
end

local function scan(unit, filter, fn)
	if not (C_UnitAuras and C_UnitAuras.GetAuraDataByIndex) then return end
	for i = 1, 40 do
		local ok, aura = pcall(C_UnitAuras.GetAuraDataByIndex, unit, i, filter)
		if not ok or not aura then return end
		local name = aura.name
		if not Stoa:IsSecret(name) and fn(name, aura) then return end
	end
end

function Party:AuraPips(unit, pips)
	scan(unit, "HELPFUL|PLAYER", function(name, aura)
		local cue = OWN_BUFFS[name]
		if cue then
			local left = timeLeft(aura)
			pips[#pips + 1] = { left and (cue[1] .. " " .. left) or cue[1], cue[2] }
		end
		return #pips >= MAX_PIPS
	end)
	if #pips >= MAX_PIPS then return end
	scan(unit, "HARMFUL", function(name, aura)
		local word = LOCKOUTS[name]
		if word then
			local left = timeLeft(aura)
			pips[#pips + 1] = { left and (word .. " " .. left) or word }
		end
		return #pips >= MAX_PIPS
	end)
end

-- Shields fill the empty end of the health bar, out of the same maximum.
function Party:UpdateAbsorb(card)
	if not card.absorb then return end
	card.absorb:SetMinMaxValues(0, UnitHealthMax(card.unit))
	if card.gone or not UnitGetTotalAbsorbs then
		card.absorb:SetValue(0)
		return
	end
	card.absorb:SetValue(UnitGetTotalAbsorbs(card.unit) or 0)
end

local DISPEL_CUES = {
	Magic = { word = "MAGIC", token = "magic" },
	Disease = { word = "DISEASE", token = "disease" },
	Curse = { word = "CURSE", token = "accent" },
	Poison = { word = "POISON", token = "danger" },
}

-- The first debuff you can remove, if any. The RAID filter asks the game
-- for debuffs this character can dispel.
function Party:DispelFor(unit)
	if not (C_UnitAuras and C_UnitAuras.GetAuraDataByIndex) then return nil end
	local ok, aura = pcall(C_UnitAuras.GetAuraDataByIndex, unit, 1, "HARMFUL|RAID")
	if not ok or not aura then return nil end
	local kind = aura.dispelName
	if Stoa:IsSecret(kind) then kind = nil end
	return DISPEL_CUES[kind] or { word = "DISPEL", token = "accent" }
end

-- Range can be secret; newer clients let a secret boolean set alpha directly.
-- The dead and offline stay dim whatever their range.
function Party:UpdateRange(card)
	if card.preview then return end
	local unit = card.unit
	if not unit or not UnitExists(unit) then return end
	if card.gone then
		card:SetAlpha(GONE_ALPHA)
		return
	end
	if unit == "player" or flag(UnitIsUnit(unit, "player")) then
		card:SetAlpha(1)
		return
	end
	local inRange = UnitInRange(unit)
	if card.SetAlphaFromBoolean then
		pcall(card.SetAlphaFromBoolean, card, inRange, 1, OUT_OF_RANGE_ALPHA)
	elseif not Stoa:IsSecret(inRange) then
		card:SetAlpha(inRange == false and OUT_OF_RANGE_ALPHA or 1)
	end
end

function Party:UpdateAll()
	self.frame:SetAlpha(Stoa:GetState() == Stoa.STATE_COMBAT and 1 or WORLD_ALPHA)
	for _, card in ipairs(self.cards) do
		self:UpdateCard(card)
	end
end

local function cardFor(self, unit)
	for _, card in ipairs(self.cards) do
		if card.unit == unit then return card end
	end
end

-- Blizzard's party frames repeat the cards.
local function hideBlizzardParty()
	for _, blizzard in ipairs({ PartyFrame, CompactPartyFrame }) do
		if blizzard then blizzard:SetParent(UI.hidden) end
	end
end

-- Lifecycle -----------------------------------------------------------------

function Party:OnEnable()
	self:Build()
	self:UpdateAll()

	if self.db.hideBlizzardParty then
		Stoa:AfterCombat(function() xpcall(hideBlizzardParty, geterrorhandler()) end)
	end

	Stoa:On("STOA_ROLE_CHANGED", function()
		Stoa:AfterCombat(function() self:Layout() end)
	end)
	Stoa:On("STOA_STATE_CHANGED", function() self:UpdateAll() end)
	Stoa:On("GROUP_ROSTER_UPDATE", function()
		self:UpdateAll()
		-- The healer row re-centres on the cards in it.
		Stoa:AfterCombat(function() self:Layout() end)
	end)
	Stoa:On("PLAYER_TARGET_CHANGED", function() self:UpdateAll() end)
	Stoa:On("STOA_THEME_CHANGED", function()
		self:UpdateAll()
		self:UpdateLegend()
	end)
	Stoa:On("STOA_CLICKS_CHANGED", function() self:UpdateLegend() end)
	Stoa:On("PLAYER_ENTERING_WORLD", function() self:UpdateAll() end)
	Stoa:On("UNIT_CONNECTION", function(unit)
		local card = cardFor(self, unit)
		if card then self:UpdateCard(card) end
	end)
	for _, event in ipairs({ "UNIT_HEALTH", "UNIT_MAXHEALTH", "UNIT_NAME_UPDATE", "UNIT_FLAGS", "UNIT_AURA", "UNIT_ABSORB_AMOUNT_CHANGED" }) do
		Stoa:On(event, function(unit)
			local card = cardFor(self, unit)
			if card then self:UpdateCard(card) end
		end)
	end

	-- Range has no event, so it's checked a few times a second; buff timers
	-- count down once a second.
	C_Timer.NewTicker(0.3, function()
		for _, card in ipairs(self.cards) do
			self:UpdateRange(card)
		end
	end)
	C_Timer.NewTicker(1, function()
		if self.frame:IsVisible() then self:UpdateAll() end
	end)
end
