-- Stoa: what's new. After an update that brings something worth knowing,
-- the first login shows a short note once per account, so players who
-- already run STOA hear about it. A new install never sees it (the welcome
-- page covers the same ground), and small fixes don't bring it back: the
-- note is tied to NOTE.edition, not to the version number.
-- /stoa news shows it again.
local _, ns = ...
local Stoa = ns.Stoa
local UI = Stoa.UI

local WhatsNew = {}
Stoa.WhatsNew = WhatsNew

-- Read this before every release: the lines must still be true of the
-- version going out. Each release with something worth telling players
-- gets a fresh note and a new `edition` (its version), so it shows once
-- to everyone; a fixes-only release keeps the last one.
-- A line only some classes get names them in `classes` (class files, such
-- as "PRIEST"): each shows as a small tag in its class colour beside the
-- line's name.
local NOTE = {
	edition = "1.1.4",
	title = "New in STOA 1.1.4",
	lines = {
		{ "Your shield", "A silver shield beside the medallion and under the Halo's health number, draining as it soaks up damage." },
		{ "Your class mark", classes = { "PRIEST", "PALADIN", "WARRIOR", "ROGUE", "SHAMAN" }, "Next to it, the buff your class keeps up, emptying as it runs out: Inner Fire for priests, your seal for paladins, Battle Shout for warriors, Slice and Dice for rogues, and Lightning or Water Shield for shamans. A priest's missing Inner Fire, or a paladin's missing seal in a fight, shows as an empty mark instead of a warning." },
		{ "A new experience bar", "Blizzard's experience bar as a thin flat bar in STOA's dark track, wherever Edit Mode puts it, filling in gold like the medallion, rested in blue. Reputation is coloured by standing, and it fades away in a fight." },
		{ "Quest items in your bags", "Items a quest of yours still needs get a gold edge in your bags, and junk selling leaves them alone." },
	},
	foot = "Each can be switched off in the settings. /stoa news shows this again.",
}

local WIDTH = 520
local PAD = Stoa.space.xl
local HEADER, FOOTER = 64, 58

-- A class's name as a small tag in its class colour.
function WhatsNew.classTag(parent, class)
	local word = LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[class] or class
	local tag = UI.badge(parent, word, "text")
	local function colour()
		local c = RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
		if not c then return end
		tag.text:SetTextColor(c.r, c.g, c.b)
		tag.fill:SetVertexColor(c.r, c.g, c.b, 0.16)
	end
	colour()
	Stoa:On("STOA_THEME_CHANGED", colour)
	return tag
end

function WhatsNew:Build()
	local page = CreateFrame("Frame", "StoaNewsPage", UIParent)
	page:SetSize(WIDTH, 240)
	page:SetPoint("CENTER", 0, 120)
	page:SetFrameStrata("DIALOG")
	page:EnableMouse(true)
	page:SetMovable(true)
	page:RegisterForDrag("LeftButton")
	page:SetScript("OnDragStart", page.StartMoving)
	page:SetScript("OnDragStop", page.StopMovingOrSizing)
	page:Hide()
	UI.windowPanel(page, 0.97, { header = HEADER, footer = FOOTER })
	table.insert(UISpecialFrames, "StoaNewsPage")

	local title = UI.text(page, "serif", Stoa.typeSize.title, "text", "LEFT")
	title:SetPoint("TOPLEFT", PAD, -PAD + 4)
	title:SetText(NOTE.title)

	-- Each line: its name, then what it is, wrapped under the name.
	local last
	local parts = {}
	for _, line in ipairs(NOTE.lines) do
		local name = UI.text(page, "sans", Stoa.typeSize.label, "text", "LEFT")
		if last then
			name:SetPoint("TOPLEFT", last, "BOTTOMLEFT", 0, -12)
		else
			name:SetPoint("TOPLEFT", PAD, -(HEADER + 18))
		end
		name:SetText(line[1])
		local tagAfter = name
		for _, class in ipairs(line.classes or {}) do
			local tag = WhatsNew.classTag(page, class)
			tag:SetPoint("LEFT", tagAfter, "RIGHT", tagAfter == name and 8 or 4, 0)
			tagAfter = tag
		end
		local words = UI.text(page, "sans", Stoa.typeSize.body, "muted", "LEFT")
		words:SetPoint("TOPLEFT", name, "BOTTOMLEFT", 0, -3)
		words:SetPoint("RIGHT", page, "RIGHT", -PAD, 0)
		words:SetWordWrap(true)
		words:SetText(line[2])
		parts[#parts + 1], parts[#parts + 2] = name, words
		last = words
	end
	local foot = UI.text(page, "italic", Stoa.typeSize.body, "muted", "LEFT")
	foot:SetPoint("TOPLEFT", last, "BOTTOMLEFT", 0, -16)
	foot:SetPoint("RIGHT", page, "RIGHT", -PAD, 0)
	foot:SetWordWrap(true)
	foot:SetText(NOTE.foot)
	parts[#parts + 1] = foot
	page.parts = parts

	local settings = UI.button(page, "Open settings", 160, function()
		page:Hide()
		Stoa:OpenSettings()
	end)
	settings:SetPoint("BOTTOMLEFT", PAD, PAD - 10)
	local done = UI.button(page, "Got it", 160, function() page:Hide() end)
	done:SetPoint("BOTTOMRIGHT", -PAD, PAD - 10)

	self.page = page
end

-- The page is as tall as its words. Heights the game won't give in the
-- open (it can hide them) are judged at a line and a half each.
function WhatsNew:Fit()
	local page = self.page
	local tall = HEADER + 18 + FOOTER + 16
	for i, part in ipairs(page.parts) do
		local height = Stoa:PlainNumber(part:GetStringHeight())
		tall = tall + (height and height > 0 and height or 22) + (i % 2 == 0 and 12 or 3)
	end
	page:SetHeight(math.ceil(tall) + 10)
end

function WhatsNew:Show()
	if InCombatLockdown() then
		Stoa:AfterCombat(function() WhatsNew:Show() end)
		return
	end
	if not self.page then self:Build() end
	self:Fit()
	self.page:Show()
	if Stoa.db then Stoa.db.newsSeen = NOTE.edition end
end

Stoa.commands.news = function() WhatsNew:Show() end

Stoa:On("STOA_READY", function()
	if not Stoa.db then return end
	-- A new install has nothing that's new to it.
	if Stoa.freshInstall then
		Stoa.db.newsSeen = NOTE.edition
		return
	end
	if Stoa.db.newsSeen == NOTE.edition then return end
	-- A character still to be welcomed gets the welcome page; the note
	-- waits for one that has been.
	if not (Stoa.char and Stoa.char.welcomed) then return end
	C_Timer.After(6, function()
		if Stoa.db.newsSeen == NOTE.edition then return end
		local welcome = Stoa.Welcome
		if welcome and welcome.Pending and welcome:Pending() then return end
		WhatsNew:Show()
	end)
end)
