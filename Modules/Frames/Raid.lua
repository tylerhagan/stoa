-- Stoa: raid frames for 10, 20 and the odd 40.
-- Built on Blizzard's secure group header so they fill and sort
-- themselves, even in combat, with the party cards' click-cast bindings.
--
-- Healers keep one rule at every size: your group reads as a row under
-- your spells. Ten players are two rows of full party cards; more are
-- compact rows of small cells, health filling the cell behind the name.
-- Everyone else gets a column per group on the left, a size smaller.
local _, ns = ...
local Stoa = ns.Stoa
local UI = Stoa.UI

local Raid = Stoa:NewModule("Raid", {
	hideBlizzardRaid = true,
})

-- The sizes also live in Raid.xml, which the headers build cells from.
local RAID_STYLES = {
	wide = { width = 168, height = 58, gap = 6, style = "raid", template = "StoaRaidButtonTemplate" },
	card = { width = 176, height = 70, gap = 8, style = "party", template = "StoaRaidCardTemplate" },
	cell = { width = 90, height = 26, gap = 3, style = "cell", template = "StoaRaidCellTemplate" },
}
Stoa.RAID_STYLES = RAID_STYLES
Stoa.RAID_CELL = RAID_STYLES.wide

-- Which header shows, by role. A raid of up to ten has no raid11.
local VISIBILITY = {
	HEALER = {
		wide = "hide",
		card = "[@raid11,exists] hide; [group:raid] show; hide",
		cell = "[@raid11,exists] show; hide",
	},
	OTHER = {
		wide = "[group:raid] show; hide",
		card = "hide",
		cell = "hide",
	},
}

local OTHER_POINT = { "TOPLEFT", UIParent, "LEFT", 36, 260 }

local cells = {}

-- Draws a raid cell. Shared with the /stoa test preview.
function UI.raidCell(cell, styleName)
	UI.unitCard(cell, styleName or "raid")
end

-- Called from the XML templates for every cell a header makes. A header
-- may make cells in combat, so this only draws; bindings follow after.
local function onLoad(cell, styleName)
	UI.raidCell(cell, styleName)
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
function StoaRaidButton_OnLoad(cell) onLoad(cell, "raid") end
function StoaRaidCard_OnLoad(cell) onLoad(cell, "party") end
function StoaRaidCell_OnLoad(cell) onLoad(cell, "cell") end

function Raid:Build()
	local holder = CreateFrame("Frame", "StoaRaid", UIParent)
	local wide = RAID_STYLES.wide
	holder:SetSize(5 * wide.width + 4 * wide.gap, wide.height)
	holder:SetFrameStrata("LOW")
	self.holder = holder

	self.headers = {}
	for key, size in pairs(RAID_STYLES) do
		local header = CreateFrame("Frame", key == "wide" and "StoaRaidHeader" or nil, holder, "SecureGroupHeaderTemplate")
		header:SetAttribute("template", size.template)
		header:SetAttribute("templateType", "Button")
		header:SetAttribute("showRaid", true)
		header:SetAttribute("showParty", false)
		header:SetAttribute("showPlayer", true)
		header:SetAttribute("groupBy", "GROUP")
		header:SetAttribute("groupingOrder", "1,2,3,4,5,6,7,8")
		header:SetAttribute("columnSpacing", size.gap)
		header:SetAttribute("unitsPerColumn", 5)
		header:SetAttribute("maxColumns", 8)
		header.size = size
		self.headers[key] = header
	end
	self.header = self.headers.wide

	self:Place()
	Stoa:RegisterMover("raid", holder, "Raid")
end

-- Healers: rows centred under the combat bar, like the party row. Everyone
-- else: a column per group on the left, a size smaller. Out of combat only.
function Raid:Place()
	local healer = Stoa:GetRole() == "HEALER"
	local visibility = VISIBILITY[healer and "HEALER" or "OTHER"]
	for key, header in pairs(self.headers) do
		local gap = header.size.gap
		header:ClearAllPoints()
		if healer then
			header:SetAttribute("point", "LEFT")
			header:SetAttribute("xOffset", gap)
			header:SetAttribute("yOffset", 0)
			header:SetAttribute("columnAnchorPoint", "TOP")
			header:SetPoint("TOP", self.holder, "TOP")
		else
			header:SetAttribute("point", "TOP")
			header:SetAttribute("xOffset", 0)
			header:SetAttribute("yOffset", -gap)
			header:SetAttribute("columnAnchorPoint", "LEFT")
			header:SetPoint("TOPLEFT", self.holder, "TOPLEFT")
		end
		UnregisterStateDriver(header, "visibility")
		RegisterStateDriver(header, "visibility", visibility[key])
	end
	self.holder:SetScale(healer and 1 or 0.8)

	if Stoa.char.positions.raid then return end
	self.holder:ClearAllPoints()
	local halo = _G.StoaHalo
	if healer and halo then
		local combatBar = Stoa:IsModuleEnabled("CombatBar") and Stoa:CombatLayout()
		self.holder:SetPoint("TOP", halo, "BOTTOM", 0, combatBar and Stoa.modules.CombatBar:GroupOffset() or -52)
	elseif healer then
		self.holder:SetPoint("TOP", UIParent, "CENTER", 0, -260)
	else
		self.holder:SetPoint(unpack(OTHER_POINT))
	end
end

local function eachCellFor(unit, fn)
	for cell in pairs(cells) do
		-- Unit events fire for every token, raidN included, so names match.
		if cell.unit == unit and cell:IsVisible() then fn(cell) end
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
	Stoa:On("STOA_COMBAT_LAYOUT", function()
		if not InCombatLockdown() then self:Place() end
	end)

	C_Timer.NewTicker(0.3, function()
		if not IsInRaid() then return end
		for cell in pairs(cells) do
			if cell.unit then party:UpdateRange(cell) end
		end
	end)
end
