-- Stoa: /stoa test. Fills the party cards, or with "/stoa test raid" a raid
-- grid, with sample players so the layout can be checked without a group.
-- The two share a spot on screen, so only one shows at a time. Out of combat
-- only; /stoa test again puts everything back.
local _, ns = ...
local Stoa = ns.Stoa

local SAMPLE = {
	{ name = "Brunhok", class = "WARRIOR", health = 0.62, absorb = 0.18, pips = { { "SHIELD", "shield" }, { "WS 11" }, { "RENEW 9" } } },
	{ name = "Thalindra", class = "PRIEST", health = 0.95, pips = { { "INNER FIRE" } } },
	{ name = "Seren", class = "ROGUE", health = 0.71, dispel = "magic", pips = { { "MAGIC", "magic" } } },
	{ name = "Velaris", class = "MAGE", health = 0.78, absorb = 0.1, target = true, pips = { { "WS 4" } } },
	{ name = "Orsun", class = "HUNTER", health = 0.28, far = true },
	{ name = "Kaelith", class = "WARLOCK", status = "DEAD", health = 0 },
	{ name = "Aldren", class = "PALADIN", status = "OFFLINE", health = 1 },
	{ name = "Mirelle", class = "DRUID", health = 1 },
	{ name = "Tovan", class = "SHAMAN", health = 0.84, pips = { { "DISEASE", "disease" } }, dispel = "disease" },
}

local LOW_HEALTH = 0.35
local GROUPS = 4

local active = false
local raidPreview

-- Fills a card with a sample the same way Party:UpdateCard fills a real one.
local function fill(card, sample)
	local UI = Stoa.UI
	card.name:SetText(sample.name)
	local color = Stoa:Theme().classTint and RAID_CLASS_COLORS[sample.class]
	if color then
		card.name:SetTextColor(color.r, color.g, color.b)
	else
		card.name:SetTextColor(Stoa:Color("text"))
	end
	local low = not sample.status and sample.health < LOW_HEALTH
	card.hp:SetMinMaxValues(0, 1)
	card.hp:SetValue(sample.status and 0 or sample.health)
	card.hp:SetStatusBarColor(Stoa:Color(low and "danger" or "health"))
	card.absorb:SetMinMaxValues(0, 1)
	card.absorb:SetValue(sample.absorb or 0)
	card.percent:SetText(sample.status and "·" or math.floor(sample.health * 100 + 0.5))
	card.percent:SetTextColor(Stoa:Color(low and "danger" or "text"))

	local pips = {}
	if sample.status then
		pips[1] = { sample.status }
	else
		for _, pip in ipairs(sample.pips or {}) do pips[#pips + 1] = pip end
		if low then table.insert(pips, 1, { "LOW", "danger" }) end
	end
	UI.setPips(card, pips)

	card.glow:Clear()
	if sample.dispel then
		local r, g, b = Stoa:Color(sample.dispel)
		card.state:Set(r, g, b)
		card.glow:Set(r, g, b, 0.22)
	elseif low then
		card.state:Set(Stoa:Color("danger"))
	elseif sample.target then
		card.state:Set(Stoa:Color("text"))
	else
		card.state:Clear()
	end
	card:SetAlpha(sample.status and 0.42 or (sample.far and 0.6 or 1))
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
		card:Show()
	end
	party:Layout()
	for i, card in ipairs(party.cards) do fill(card, SAMPLE[i]) end
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
	end
	RegisterStateDriver(party.frame, "visibility", "[group:raid] hide; show")
	party:Layout()
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
				cell:SetSize(Stoa.RAID_CELL.width, Stoa.RAID_CELL.height)
				cell.group, cell.slot = group, slot
				Stoa.UI.raidCell(cell)
				table.insert(raidPreview.cells, cell)
			end
		end
	end
	-- Same arrangement as the real grid: rows of groups for healers,
	-- columns for everyone else.
	local size = Stoa.RAID_CELL
	local rows = Stoa:GetRole() == "HEALER"
	for i, cell in ipairs(raidPreview.cells) do
		local across, down = cell.slot - 1, cell.group - 1
		if not rows then across, down = down, across end
		cell:ClearAllPoints()
		cell:SetPoint("TOPLEFT", across * (size.width + size.gap), -down * (size.height + size.gap))
		fill(cell, SAMPLE[(i - 1) % #SAMPLE + 1])
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
