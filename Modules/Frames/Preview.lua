-- Stoa: /stoa test. Fills the party cards, or with "/stoa test raid" a raid
-- grid, with sample players so the layout can be checked without a group.
-- The two share a spot on screen, so only one shows at a time. Out of combat
-- only; /stoa test again puts everything back.
local _, ns = ...
local Stoa = ns.Stoa

local SAMPLE = {
	{ name = "Thalindra", class = "PRIEST", role = "H", health = 0.92 },
	{ name = "Brunhok", class = "WARRIOR", role = "T", health = 0.64, absorb = 0.25, missing = "-1.2K" },
	{ name = "Velaris", class = "MAGE", role = "D", health = 0.38, far = true, missing = "-940" },
	{ name = "Seren", class = "HUNTER", role = "D", health = 0.71, dispel = "MAGIC", missing = "-410" },
	{ name = "Kaelith", class = "ROGUE", status = "DEAD", health = 0 },
	{ name = "Orsun", class = "PALADIN", status = "OFFLINE", health = 1 },
}

local CELL_WIDTH, CELL_HEIGHT, GAP, GROUPS = 100, 44, 4, 4

local active = false
local raidPreview

local function fill(card, sample)
	card.name:SetText(sample.name)
	local color = RAID_CLASS_COLORS[sample.class]
	if color then card.stripe:SetVertexColor(color.r, color.g, color.b) end
	card.hp:SetMinMaxValues(0, 1)
	card.hp:SetValue(sample.health)
	card.status:SetText(sample.dispel or sample.status or sample.role or "")
	card:SetAlpha(sample.far and 0.45 or (sample.status and 0.7 or 1))
	if card.healthText then card.healthText:SetText(sample.missing or "") end
	if card.absorb then
		card.absorb:SetMinMaxValues(0, 1)
		card.absorb:SetValue(sample.absorb or 0)
	end
	if card.dispel then
		if sample.dispel then card.dispel:Set(Stoa:Color("magic")) else card.dispel:Clear() end
	end
end

local function showParty()
	local party = Stoa.modules.Party
	if not party.cards then return end
	UnregisterStateDriver(party.frame, "visibility")
	party.frame:Show()
	party.frame:SetAlpha(1)
	for i, card in ipairs(party.cards) do
		if card.unit == "player" then
			UnregisterStateDriver(card, "visibility")
		else
			UnregisterUnitWatch(card)
		end
		card.preview = true
		fill(card, SAMPLE[i])
		card:Show()
	end
end

local function hideParty()
	local party = Stoa.modules.Party
	if not party.cards then return end
	for _, card in ipairs(party.cards) do
		card.preview = nil
		if card.unit == "player" then
			RegisterStateDriver(card, "visibility", "[group] show; hide")
		else
			card:Hide()
			RegisterUnitWatch(card)
		end
		party:UpdateCard(card)
	end
	RegisterStateDriver(party.frame, "visibility", "[group:raid] hide; show")
	party:UpdateAll()
end

-- The raid preview is plain frames drawn by the same code as real cells,
-- laid over where the grid would be.
local function showRaid()
	local raid = Stoa.modules.Raid
	if not raid.holder then return end
	if not raidPreview then
		raidPreview = CreateFrame("Frame", nil, raid.holder)
		raidPreview:SetPoint("TOPLEFT")
		raidPreview:SetSize(1, 1)
		raidPreview.cells = {}
		for group = 1, GROUPS do
			for slot = 1, 5 do
				local cell = CreateFrame("Button", nil, raidPreview)
				cell:SetSize(CELL_WIDTH, CELL_HEIGHT)
				cell:SetPoint("TOPLEFT", (group - 1) * (CELL_WIDTH + GAP), -(slot - 1) * (CELL_HEIGHT + GAP))
				Stoa.UI.raidCell(cell)
				local sample = SAMPLE[(group + slot) % #SAMPLE + 1]
				fill(cell, sample)
				table.insert(raidPreview.cells, cell)
			end
		end
	end
	raidPreview:Show()
end

local function hideRaid()
	if raidPreview then raidPreview:Hide() end
end

function Stoa:TogglePreview(kind)
	if InCombatLockdown() then
		self:Print("The preview can be shown once combat ends.")
		return
	end
	if active then
		hideParty()
		hideRaid()
		active = false
		self:Print("Preview hidden.")
		return
	end
	active = true
	if kind == "raid" then
		showRaid()
		self:Print("Showing a sample raid. /stoa test to hide it; /stoa unlock to move it.")
	else
		showParty()
		self:Print("Showing a sample party. /stoa test raid for a raid, /stoa test to hide; /stoa unlock to move it.")
	end
end

Stoa.commands.test = function(rest) Stoa:TogglePreview(rest:lower()) end

-- Entering combat ends the preview, so sample frames never stand in for real
-- ones in a fight.
Stoa:On("PLAYER_REGEN_DISABLED", function()
	if not active then return end
	active = false
	hideRaid()
	Stoa:AfterCombat(hideParty)
end)
