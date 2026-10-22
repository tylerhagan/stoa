-- Stoa: raid frames for 10, 20 and the odd 40.
-- One row of cards per group, after the Disc raid mockup, built on
-- Blizzard's secure group header so it fills and sorts itself, even in
-- combat. Cards are the party cards in a smaller cut, with the same
-- click-cast bindings. Healers get the grid under the Halo; everyone else
-- on the left.
local _, ns = ...
local Stoa = ns.Stoa
local UI = Stoa.UI

local Raid = Stoa:NewModule("Raid", {
	hideBlizzardRaid = true,
})

-- The size also lives in Raid.xml, which the header builds cells from.
local CELL_WIDTH, CELL_HEIGHT, GAP = 168, 58, 6
Stoa.RAID_CELL = { width = CELL_WIDTH, height = CELL_HEIGHT, gap = GAP }

local GRID_WIDTH = 5 * CELL_WIDTH + 4 * GAP

local LAYOUTS = {
	HEALER = { "TOP", "StoaHalo", "BOTTOM", 0, -52 },
	OTHER = { "TOPLEFT", UIParent, "LEFT", 36, 260 },
}

local cells = {}

-- Draws a raid cell. Shared with the /stoa test preview.
function UI.raidCell(cell)
	UI.unitCard(cell, "raid")
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
	holder:SetSize(GRID_WIDTH, CELL_HEIGHT)
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
	header:SetAttribute("columnSpacing", GAP)
	header:SetAttribute("unitsPerColumn", 5)
	header:SetAttribute("maxColumns", 8)
	RegisterStateDriver(header, "visibility", "[group:raid] show; hide")
	self.header = header

	self:Place()
	Stoa:RegisterMover("raid", holder, "Raid")
end

-- Healers read a group as a row under the Halo; everyone else gets a
-- column per group on the left, a size smaller. Out of combat only.
function Raid:Place()
	local role = Stoa:GetRole()
	local header = self.header
	if role == "HEALER" then
		header:SetAttribute("point", "LEFT")
		header:SetAttribute("xOffset", GAP)
		header:SetAttribute("yOffset", 0)
		header:SetAttribute("columnAnchorPoint", "TOP")
		self.holder:SetScale(1)
	else
		header:SetAttribute("point", "TOP")
		header:SetAttribute("xOffset", 0)
		header:SetAttribute("yOffset", -GAP)
		header:SetAttribute("columnAnchorPoint", "LEFT")
		self.holder:SetScale(0.8)
	end
	if Stoa.char.positions.raid then return end
	local point, relative, relativePoint, x, y = unpack(LAYOUTS[role] or LAYOUTS.OTHER)
	if type(relative) == "string" then relative = _G[relative] end
	self.holder:ClearAllPoints()
	if relative then
		self.holder:SetPoint(point, relative, relativePoint, x, y)
	else
		self.holder:SetPoint("TOP", UIParent, "CENTER", 0, -260)
	end
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
	for _, event in ipairs({ "UNIT_HEALTH", "UNIT_MAXHEALTH", "UNIT_NAME_UPDATE", "UNIT_FLAGS", "UNIT_CONNECTION", "UNIT_AURA", "UNIT_ABSORB_AMOUNT_CHANGED" }) do
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
	local function updateAll()
		for cell in pairs(cells) do
			if cell.unit and cell:IsVisible() then party:UpdateCard(cell) end
		end
	end
	Stoa:On("PLAYER_TARGET_CHANGED", updateAll)
	Stoa:On("STOA_THEME_CHANGED", updateAll)
	-- Buff timers count down.
	C_Timer.NewTicker(1, function()
		if IsInRaid() then updateAll() end
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
