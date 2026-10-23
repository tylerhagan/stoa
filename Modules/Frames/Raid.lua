-- Stoa: raid frames for 10, 20 and the odd 40.
-- Built on Blizzard's secure group header so they fill and sort
-- themselves, even in combat, with the party cards' click-cast bindings.
--
-- Healers keep one rule at every size: your group reads as a row under
-- your spells. Ten players are two rows of full party cards; twenty are
-- compact rows of small cells, health filling the cell behind the name;
-- forty are two blocks of smaller cells side by side, groups 1-4 on the
-- left and 5-8 on the right, so the raid stays above the console.
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
	tinyLeft = { width = 78, height = 22, gap = 2, style = "tiny", template = "StoaRaidTinyTemplate", groups = "1,2,3,4" },
	tinyRight = { width = 78, height = 22, gap = 2, style = "tiny", template = "StoaRaidTinyTemplate", groups = "5,6,7,8" },
}
-- The space between the two forty-player blocks.
local BLOCK_GAP = 16
Stoa.RAID_STYLES = RAID_STYLES
Stoa.RAID_CELL = RAID_STYLES.wide

-- Which header shows, by role. A raid of up to ten has no raid11.
local VISIBILITY = {
	HEALER = {
		wide = "hide",
		card = "[@raid11,exists] hide; [group:raid] show; hide",
		cell = "[@raid21,exists] hide; [@raid11,exists] show; hide",
		tinyLeft = "[@raid21,exists] show; hide",
		tinyRight = "[@raid21,exists] show; hide",
	},
	OTHER = {
		wide = "[group:raid] show; hide",
		card = "hide",
		cell = "hide",
		tinyLeft = "hide",
		tinyRight = "hide",
	},
}

-- Everyone but healers: columns standing above the chat and its tabs.
local OTHER_LEFT = 36
local OTHER_ABOVE_CONSOLE = 64
local OTHER_SCALE = 0.8

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
			if value then xpcall(Stoa.modules.Party.UpdateCard, Stoa.catch, Stoa.modules.Party, self) end
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
function StoaRaidTiny_OnLoad(cell) onLoad(cell, "tiny") end

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
		if size.groups then header:SetAttribute("groupFilter", size.groups) end
		header:SetAttribute("columnSpacing", size.gap)
		header:SetAttribute("unitsPerColumn", 5)
		header:SetAttribute("maxColumns", 8)
		header.size = size
		self.headers[key] = header
	end
	self.header = self.headers.wide

	self:Place()
	Stoa:RegisterMover("raid", holder, "Raid", { default = function() self:Place() end })
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
			if key == "tinyLeft" then
				header:SetPoint("TOPRIGHT", self.holder, "TOP", -BLOCK_GAP / 2, 0)
			elseif key == "tinyRight" then
				header:SetPoint("TOPLEFT", self.holder, "TOP", BLOCK_GAP / 2, 0)
			else
				header:SetPoint("TOP", self.holder, "TOP")
			end
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
	self.holder:SetScale(healer and 1 or OTHER_SCALE)
	local wide = RAID_STYLES.wide
	if healer then
		self.holder:SetSize(5 * wide.width + 4 * wide.gap, wide.height)
	else
		-- As tall as a full group, so the columns rest on the console.
		self.holder:SetSize(8 * wide.width + 7 * wide.gap, 5 * wide.height + 4 * wide.gap)
	end

	if Stoa:HasSavedPosition("raid") then return end
	self.holder:ClearAllPoints()
	local halo = _G.StoaHalo
	if healer and halo then
		local combatBar = Stoa:IsModuleEnabled("CombatBar") and Stoa:CombatLayout()
		self.holder:SetPoint("TOP", halo, "BOTTOM", 0, combatBar and Stoa.modules.CombatBar:GroupOffset() or -52)
	elseif healer then
		self.holder:SetPoint("TOP", UIParent, "CENTER", 0, -260)
	else
		local console = Stoa:IsModuleEnabled("Grimoire") and Stoa.modules.Grimoire:OpenHeight() or 0
		self.holder:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", OTHER_LEFT / OTHER_SCALE, (console + OTHER_ABOVE_CONSOLE) / OTHER_SCALE)
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
		Stoa:AfterCombat(function() xpcall(hideBlizzardRaid, Stoa.catch) end)
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
	Stoa:NewTicker(1, function()
		if IsInRaid() then updateAll() end
	end)
	Stoa:On("STOA_ROLE_CHANGED", function()
		Stoa:AfterCombat(function() self:Place() end)
	end)
	Stoa:On("STOA_COMBAT_LAYOUT", function()
		if not InCombatLockdown() then self:Place() end
	end)

	Stoa:NewTicker(0.3, function()
		if not IsInRaid() then return end
		for cell in pairs(cells) do
			if cell.unit then party:UpdateRange(cell) end
		end
	end)
end
