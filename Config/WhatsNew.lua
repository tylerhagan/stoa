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
	edition = "1.5.2",
	title = "New in STOA 1.5",
	lines = {
		{ "EllesmereUI", "STOA knows EllesmereUI's parts too and asks, part by part, which of the two looks after each, cooldown icons and buff reminders included." },
		{ "EllesmereUI on the console", "Keep EllesmereUI's chat and one click seats it on the console's left page, with its damage meter top left. /stoa fit undo puts them back." },
		{ "Daylight UI", "STOA knows Daylight UI's parts and asks, part by part, which of the two looks after each: bags, nameplates, chat, tooltips, frames and more." },
		{ "One page of questions", "When several addons share jobs with STOA, the questions come as one list, with theirs kept unless you pick STOA's." },
		{ "Daylight's chat in the console", "Keep Daylight UI's chat and it sits in the console's chat place, with its tabs along the top edge." },
		{ "Other chat addons", "Chat from another addon now stands above the console instead of behind it." },
		{ "Changing your mind", "Settings > Setup > Other addons lists each shared job, so any answer can be changed later." },
		{ "Raid target marks", "A skull, star or any other mark shows beside the name on the target plaque, and on the corner of party and raid cards." },
		{ "Help on its way", "A dead group member's card says RES while someone raises them, and SUMMON while a summon waits on their answer." },
		{ "Loot rolls", "The need, greed and pass cards wear STOA's dark card, with a thin timer along the foot." },
		{ "Other languages", "Seals, shields, creature types, zone levels on the map and herb nodes now work on clients that aren't English." },
		{ "Lighter in groups", "STOA listens only to the players it draws, so it does less work in a full raid." },
	},
	foot = "/stoa news shows this again.",
}

local PAD = Stoa.space.xl
-- Up to PER_COLUMN lines sit in one column; past that the lines split over
-- two columns side by side.
local PER_COLUMN = 5
local COLUMN, GAP = 456, 36
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
	local count = #NOTE.lines
	local columns = count > PER_COLUMN and 2 or 1
	local perColumn = math.ceil(count / columns)
	local page = CreateFrame("Frame", "StoaNewsPage", UIParent)
	UI.riseOnShow(page)
	page:SetSize(PAD * 2 + columns * COLUMN + (columns - 1) * GAP, 240)
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
	page.columns = {}
	local last
	for index, line in ipairs(NOTE.lines) do
		local column = math.floor((index - 1) / perColumn) + 1
		local parts = page.columns[column]
		if not parts then
			parts = {}
			page.columns[column] = parts
			last = nil
		end
		local name = UI.text(page, "sans", Stoa.typeSize.label, "text", "LEFT")
		if last then
			name:SetPoint("TOPLEFT", last, "BOTTOMLEFT", 0, -12)
		else
			name:SetPoint("TOPLEFT", PAD + (column - 1) * (COLUMN + GAP), -(HEADER + 18))
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
		words:SetWidth(COLUMN)
		words:SetWordWrap(true)
		words:SetText(line[2])
		parts[#parts + 1], parts[#parts + 2] = name, words
		last = words
	end
	-- The foot runs the page's width above the buttons.
	local foot = UI.text(page, "italic", Stoa.typeSize.body, "muted", "LEFT")
	foot:SetPoint("BOTTOMLEFT", PAD, FOOTER + 12)
	foot:SetPoint("RIGHT", page, "RIGHT", -PAD, 0)
	foot:SetWordWrap(true)
	foot:SetText(NOTE.foot)
	page.foot = foot

	local settings = UI.button(page, "Open settings", 160, function()
		page:Hide()
		Stoa:OpenSettings()
	end)
	settings:SetPoint("BOTTOMLEFT", PAD, PAD - 10)
	local done = UI.button(page, "Got it", 160, function() page:Hide() end)
	done:SetPoint("BOTTOMRIGHT", -PAD, PAD - 10)

	self.page = page
end

-- The page is as tall as its tallest column. Heights the game won't give
-- in the open (it can hide them) are judged at a line and a half each.
local function heightOf(part)
	local height = Stoa:PlainNumber(part:GetStringHeight())
	return height and height > 0 and height or 22
end

function WhatsNew:Fit()
	local page = self.page
	local tallest = 0
	for _, parts in ipairs(page.columns) do
		local tall = 0
		for i, part in ipairs(parts) do tall = tall + heightOf(part) + (i % 2 == 0 and 12 or 3) end
		tallest = math.max(tallest, tall)
	end
	local tall = HEADER + 18 + tallest + 4 + heightOf(page.foot) + 12 + FOOTER
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
