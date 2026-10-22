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

-- Card size and spot per role. Positions are UIParent offsets; a position
-- dragged with /stoa unlock wins over these.
local LAYOUTS = {
	HEALER = { width = 200, height = 46, gap = 6, point = { "TOPLEFT", UIParent, "CENTER", 190, 110 } },
	OTHER = { width = 160, height = 32, gap = 4, point = { "TOPLEFT", UIParent, "LEFT", 36, 160 } },
}

local ROLE_GLYPHS = { TANK = "T", HEALER = "H", DAMAGER = "D" }

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
	card.unit = unit
	Stoa:RegisterClickFrame(card)

	local bg = card:CreateTexture(nil, "BACKGROUND")
	bg:SetAllPoints()
	UI.paint(bg, "panel", 0.85)
	local edge = UI.line(card)
	edge:SetPoint("TOPLEFT")
	edge:SetPoint("TOPRIGHT")

	-- A class stripe on the left edge, the card's only strong colour.
	local stripe = card:CreateTexture(nil, "ARTWORK")
	stripe:SetPoint("TOPLEFT")
	stripe:SetPoint("BOTTOMLEFT")
	stripe:SetWidth(2)
	stripe:SetColorTexture(1, 1, 1)
	card.stripe = stripe

	local name = UI.text(card, "serif", Stoa.typeSize.label, "text")
	name:SetPoint("TOPLEFT", 10, -6)
	name:SetPoint("RIGHT", -28, 0)
	name:SetWordWrap(false)
	card.name = name

	-- Words, not just colour, for anything that matters.
	local status = UI.caption(card, "")
	status:SetPoint("TOPRIGHT", -8, -7)
	card.status = status

	local hp = UI.bar(card, 10, 4, "health")
	hp:SetPoint("BOTTOMLEFT", 10, 7)
	hp:SetPoint("BOTTOMRIGHT", -8, 7)
	card.hp = hp

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
	frame:SetSize(200, 46)
	frame:SetFrameStrata("LOW")
	-- In a raid the raid grid takes over.
	RegisterStateDriver(frame, "visibility", "[group:raid] hide; show")
	self.frame = frame

	self.cards = {}
	for i, unit in ipairs(UNITS) do
		self.cards[i] = self:BuildCard(i, unit)
	end
	UI.applyTheme()
	self:Layout()
	Stoa:RegisterMover("party", frame, "Party")
end

-- Sizes and stacks the cards for the current role. Out of combat only.
function Party:Layout()
	local layout = layoutFor(Stoa:GetRole())
	local frame = self.frame
	if not Stoa.char.positions.party then
		frame:ClearAllPoints()
		frame:SetPoint(unpack(layout.point))
	end
	frame:SetSize(layout.width, layout.height)
	local big = layout.height >= 40
	for i, card in ipairs(self.cards) do
		card:SetSize(layout.width, layout.height)
		card:ClearAllPoints()
		card:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, -(i - 1) * (layout.height + layout.gap))
		Stoa:SetFont(card.name, "serif", big and Stoa.typeSize.label or Stoa.typeSize.body)
		card.hp:SetHeight(big and 4 or 3)
	end
end

-- Updates -------------------------------------------------------------------

local function flag(value)
	if Stoa:IsSecret(value) then return false end
	return value and true or false
end

function Party:UpdateCard(card)
	local unit = card.unit
	-- Cards showing the /stoa test preview keep their sample data.
	if card.preview or not UnitExists(unit) then return end

	card.name:SetText(UnitName(unit))
	card.stripe:SetVertexColor(UI.classColor(unit))
	UI.setUnitBar(card.hp, unit, "health")

	local status = ""
	if not flag(UnitIsConnected(unit)) then
		status = "OFFLINE"
	elseif flag(UnitIsDeadOrGhost(unit)) then
		status = "DEAD"
	else
		local role = UnitGroupRolesAssigned(unit)
		if not Stoa:IsSecret(role) then status = ROLE_GLYPHS[role] or "" end
	end
	card.status:SetText(status)
	self:UpdateRange(card)
end

-- Range can be secret; newer clients let a secret boolean set alpha directly.
function Party:UpdateRange(card)
	if card.preview then return end
	local unit = card.unit
	if unit == "player" or not UnitExists(unit) then
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
	Stoa:On("GROUP_ROSTER_UPDATE", function() self:UpdateAll() end)
	Stoa:On("PLAYER_ENTERING_WORLD", function() self:UpdateAll() end)
	Stoa:On("UNIT_CONNECTION", function(unit)
		local card = cardFor(self, unit)
		if card then self:UpdateCard(card) end
	end)
	for _, event in ipairs({ "UNIT_HEALTH", "UNIT_MAXHEALTH", "UNIT_NAME_UPDATE", "UNIT_FLAGS" }) do
		Stoa:On(event, function(unit)
			local card = cardFor(self, unit)
			if card then self:UpdateCard(card) end
		end)
	end

	-- Range has no event, so it's checked a few times a second.
	C_Timer.NewTicker(0.3, function()
		for _, card in ipairs(self.cards) do
			self:UpdateRange(card)
		end
	end)
end
