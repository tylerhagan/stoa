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
	{ name = "Ysolde", class = "MAGE", health = 0.91 },
	{ name = "Harrow", class = "WARRIOR", health = 1 },
	{ name = "Fennick", class = "ROGUE", health = 0.56, dispel = "magic", pips = { { "MAGIC", "magic" } } },
	{ name = "Brisa", class = "DRUID", health = 1 },
	{ name = "Doran", class = "PALADIN", health = 0.88, absorb = 0.12, pips = { { "SHIELD", "shield" } } },
	{ name = "Ilsa", class = "PRIEST", health = 1 },
	{ name = "Quill", class = "HUNTER", health = 1 },
	{ name = "Marrow", class = "WARLOCK", health = 0.39 },
	{ name = "Sable", class = "ROGUE", health = 1 },
	{ name = "Torvin", class = "SHAMAN", health = 0.74 },
	{ name = "Arthilian", class = "MAGE", health = 1 },
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
		local quiet = Stoa.modules.Party:Quiet()
		for _, pip in ipairs(sample.pips or {}) do
			if not quiet or (sample.dispel and pip[2] == sample.dispel) then pips[#pips + 1] = pip end
		end
		if low and not quiet then table.insert(pips, 1, { "LOW", "danger" }) end
	end
	UI.setPips(card, pips)
	if sample.status then
		UI.cellWord(card, sample.status, "muted")
	elseif sample.dispel then
		UI.cellWord(card, sample.pips[1][1], sample.dispel)
	elseif low then
		UI.cellWord(card, "LOW", "danger")
	end

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
-- laid out the way the real headers would: for healers, compact rows for
-- 20 or two rows of cards for 10; columns of cells for everyone else.
local function showRaid(ten)
	local raid = Stoa.modules.Raid
	if not raid.holder then return end
	local healer = Stoa:GetRole() == "HEALER"
	local key = not healer and "wide" or ten and "card" or "cell"
	local size = Stoa.RAID_STYLES[key]
	local groups = ten and 2 or GROUPS
	raidPreview = raidPreview or {}
	for _, built in pairs(raidPreview) do built:Hide() end
	local frame = raidPreview[key]
	if not frame then
		frame = CreateFrame("Frame", nil, raid.holder)
		frame.cells = {}
		for group = 1, GROUPS do
			for slot = 1, 5 do
				local cell = CreateFrame("Button", nil, frame)
				cell:SetSize(size.width, size.height)
				cell.group, cell.slot = group, slot
				Stoa.UI.raidCell(cell, size.style)
				table.insert(frame.cells, cell)
			end
		end
		raidPreview[key] = frame
	end
	local across, down = 5, groups
	if not healer then across, down = groups, 5 end
	frame:SetSize(across * (size.width + size.gap) - size.gap, down * (size.height + size.gap) - size.gap)
	frame:ClearAllPoints()
	if healer then
		frame:SetPoint("TOP", raid.holder, "TOP")
	else
		frame:SetPoint("TOPLEFT", raid.holder, "TOPLEFT")
	end
	for i, cell in ipairs(frame.cells) do
		local x, y = cell.slot - 1, cell.group - 1
		if not healer then x, y = y, x end
		cell:ClearAllPoints()
		cell:SetPoint("TOPLEFT", x * (size.width + size.gap), -y * (size.height + size.gap))
		cell:SetShown(cell.group <= groups)
		fill(cell, SAMPLE[(i - 1) % #SAMPLE + 1])
	end
	frame:Show()
end

local function hideRaid()
	for _, built in pairs(raidPreview or {}) do built:Hide() end
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
		self.previewing = nil
		self:Fire("STOA_PREVIEW_CHANGED")
		self:Print("Preview hidden.")
		return
	end
	active = true
	local raid = kind == "raid" or kind == "raid10"
	self.previewing = raid and "raid" or "party"
	self:Fire("STOA_PREVIEW_CHANGED")
	if raid then
		showRaid(kind == "raid10")
		self:Print("Showing a sample raid. /stoa test raid10 for ten players, /stoa test to hide it; /stoa unlock to move it.")
	else
		showParty()
		self:Print("Showing a sample party. /stoa test raid or raid10 for a raid, /stoa test to hide; /stoa unlock to move it.")
	end
end

Stoa.commands.test = function(rest) Stoa:TogglePreview(rest:lower()) end

-- Entering combat ends the preview, so sample frames never stand in for real
-- ones in a fight.
Stoa:On("PLAYER_REGEN_DISABLED", function()
	if not active then return end
	active = false
	Stoa.previewing = nil
	Stoa:Fire("STOA_PREVIEW_CHANGED")
	hideRaid()
	Stoa:AfterCombat(hideParty)
end)
