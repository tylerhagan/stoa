-- Stoa: raid frames for 10, 20 and the odd 40.
-- A grid of compact cards, one column per group, built on Blizzard's secure
-- group header so it fills and sorts itself, even in combat. Cards share
-- the party cards' look and the click-cast bindings. Healers get the grid
-- beside the Halo; everyone else on the left.
local _, ns = ...
local Stoa = ns.Stoa
local UI = Stoa.UI

local Raid = Stoa:NewModule("Raid", {
	hideBlizzardRaid = true,
})

local CELL_WIDTH, CELL_HEIGHT, GAP = 88, 36, 4

local LAYOUTS = {
	HEALER = { "TOPLEFT", UIParent, "CENTER", 170, 110 },
	OTHER = { "TOPLEFT", UIParent, "LEFT", 36, 200 },
}

local cells = {}

-- Draws a raid cell. Shared with the /stoa test preview.
function UI.raidCell(cell)
	local bg = cell:CreateTexture(nil, "BACKGROUND")
	bg:SetAllPoints()
	UI.paint(bg, "panel", 0.85)

	local stripe = cell:CreateTexture(nil, "ARTWORK")
	stripe:SetPoint("TOPLEFT")
	stripe:SetPoint("TOPRIGHT")
	stripe:SetHeight(2)
	stripe:SetColorTexture(1, 1, 1)
	cell.stripe = stripe

	local name = UI.text(cell, "serif", Stoa.typeSize.body, "text", "CENTER")
	name:SetPoint("TOPLEFT", 4, -8)
	name:SetPoint("TOPRIGHT", -4, -8)
	name:SetWordWrap(false)
	cell.name = name

	local status = UI.caption(cell, "")
	status:SetPoint("TOP", name, "BOTTOM", 0, -1)
	cell.status = status

	local hp = UI.bar(cell, 10, 3, "health")
	hp:SetPoint("BOTTOMLEFT", 4, 4)
	hp:SetPoint("BOTTOMRIGHT", -4, 4)
	cell.hp = hp
	UI.applyTheme()
end

-- Called from the XML template for every cell the header makes. The header
-- may make cells in combat, so this only draws; bindings follow after.
function StoaRaidButton_OnLoad(cell)
	UI.raidCell(cell)
	cell:SetScript("OnAttributeChanged", function(self, key, value)
		if key == "unit" then
			self.unit = value
			if value then Stoa.modules.Party:UpdateCard(self) end
		end
	end)
	cell:SetScript("OnEnter", function(self)
		if not self.unit then return end
		GameTooltip_SetDefaultAnchor(GameTooltip, self)
		GameTooltip:SetUnit(self.unit)
	end)
	cell:SetScript("OnLeave", GameTooltip_Hide)

	cells[cell] = true
	Stoa:RegisterClickFrame(cell)
end

function Raid:Build()
	local holder = CreateFrame("Frame", "StoaRaid", UIParent)
	holder:SetSize(CELL_WIDTH, CELL_HEIGHT)
	holder:SetFrameStrata("LOW")
	self.holder = holder

	local header = CreateFrame("Frame", "StoaRaidHeader", holder, "SecureGroupHeaderTemplate")
	header:SetPoint("TOPLEFT")
	header:SetAttribute("template", "StoaRaidButtonTemplate")
	header:SetAttribute("templateType", "Button")
	header:SetAttribute("showRaid", true)
	header:SetAttribute("showParty", false)
	header:SetAttribute("showPlayer", true)
	header:SetAttribute("groupBy", "GROUP")
	header:SetAttribute("groupingOrder", "1,2,3,4,5,6,7,8")
	header:SetAttribute("point", "TOP")
	header:SetAttribute("yOffset", -GAP)
	header:SetAttribute("columnAnchorPoint", "LEFT")
	header:SetAttribute("columnSpacing", GAP)
	header:SetAttribute("unitsPerColumn", 5)
	header:SetAttribute("maxColumns", 8)
	RegisterStateDriver(header, "visibility", "[group:raid] show; hide")
	self.header = header

	self:Place()
	Stoa:RegisterMover("raid", holder, "Raid")
end

function Raid:Place()
	if Stoa.char.positions.raid then return end
	local role = Stoa:GetRole()
	self.holder:ClearAllPoints()
	self.holder:SetPoint(unpack(LAYOUTS[role] or LAYOUTS.OTHER))
end

local function eachCellFor(unit, fn)
	for cell in pairs(cells) do
		-- Unit events fire for every token, raidN included, so names match.
		if cell.unit == unit then fn(cell) end
	end
end

local function hideBlizzardRaid()
	if CompactRaidFrameContainer then CompactRaidFrameContainer:SetParent(UI.hidden) end
end

function Raid:OnEnable()
	self:Build()
	if self.db.hideBlizzardRaid then
		Stoa:AfterCombat(function() xpcall(hideBlizzardRaid, geterrorhandler()) end)
	end

	local party = Stoa.modules.Party
	for _, event in ipairs({ "UNIT_HEALTH", "UNIT_MAXHEALTH", "UNIT_NAME_UPDATE", "UNIT_FLAGS", "UNIT_CONNECTION" }) do
		Stoa:On(event, function(unit)
			if not unit or not IsInRaid() then return end
			eachCellFor(unit, function(cell) party:UpdateCard(cell) end)
		end)
	end
	Stoa:On("GROUP_ROSTER_UPDATE", function()
		for cell in pairs(cells) do
			if cell.unit then party:UpdateCard(cell) end
		end
	end)
	Stoa:On("STOA_ROLE_CHANGED", function()
		Stoa:AfterCombat(function() self:Place() end)
	end)

	C_Timer.NewTicker(0.3, function()
		if not IsInRaid() then return end
		for cell in pairs(cells) do
			if cell.unit then party:UpdateRange(cell) end
		end
	end)
end
