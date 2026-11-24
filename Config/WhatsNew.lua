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
-- gets a short note of its own at the top of NOTES, with its version as
-- `edition`, so it shows once to everyone; a fixes-only release adds none.
-- The newest note opens; Earlier and Later page through the few kept here
-- (drop the oldest when adding one past five: CHANGELOG.md has the rest).
-- A line only some classes get names them in `classes` (class files, such
-- as "PRIEST"): each shows as a small tag in its class colour beside the
-- line's name.
local FOOT = "/stoa news shows this again."
local NOTES = {
	{
		edition = "2.0.0",
		title = "STOA 2",
		-- A big release: a line under the title, and a way to the page that
		-- shows both looks side by side.
		lead = "Two looks, a console you arrange, a shorter setup",
		tour = true,
		-- A word from the author, in a box of its own above the foot.
		thanks = {
			"Thank you to everyone who has stuck with STOA. It means a lot to me. If there is something you would like to see next, leave a comment on the CurseForge page and I will read it.",
			"curseforge.com/wow/addons/stoa",
		},
		lines = {
			{ "Matte, a second look", "STOA now comes in two looks. Leather is the one you know. Matte black is a plain dark design after moulded matte hardware: sharp corners, flat plates and a fine grain. Settings > Look > Material switches between them, or type /stoa welcome update to see both side by side." },
			{ "Made for Matte", "A matte console with recesses for chat, the bars and the pages, a Compact or Full target, flat party cards and a Matte nameplate style. Leather keeps everything it had." },
			{ "A console in slots", "The console's right side is now three slots. Put Ready, Journey or Company in any order, drop in the game's damage meter windows or a Details window, or leave one empty. A Details window in a slot is cut down to its title and rows. Settings > Console." },
			{ "Menu and bags as words", "The game menu and the bag row now rest behind two small words on the console's edge, MENU and BAGS. Put the mouse on a word and its row shows. A click on BAGS opens your bags." },
			{ "Leather polish", "A Compact target for Leather, rank as coloured words on the target, and nameplates that never cut a name short, with casts as a thin line." },
			{ "Halo arc styles", "Tube is the new look of the two arcs, with Gauge, Line, Blade or Visor under Settings > Halo." },
			{ "A shorter setup", "The welcome page asks two things about how much STOA you want: the console (Full, Slim or None) and everything around it (Standard or Quiet). A new Target and frames step sets the target, party, nameplates and text size. /stoa welcome opens it." },
			{ "Quiet does more", "Quiet now makes the target and party thin strips that fade out of combat, as well as putting away tooltip details, the quest line and At a glance." },
			{ "Chat on a ride", "On a mount or a flight the chat comes back while you type and for a few seconds after, and whispers from any chat window show in the feed." },
		},
	},
	{
		edition = "1.6.1",
		title = "New in STOA 1.6.1",
		lines = {
			{ "Heals halved", "When Mortal Strike or Mortal Wound is on someone, red stripes fill the empty part of their health bar on the tank watch and your party cards, with a HEALS HALF word. It works in a fight.", classes = { "PRIEST", "PALADIN", "DRUID", "SHAMAN" } },
			{ "Readable over bright ground", "Buff timers, the Halo's cast bar and the chat on a folded console sit on soft dark plates, so they read over sand, snow and sky." },
			{ "Loot rolls", "Need and Greed cards now sit right of the middle of the screen, off your bars, and show who chose what. A small card then shows every roll and the winner." },
			{ "Friends, guild, loot and menus", "The friends window, the loot window and every dropdown and right-click menu now wear STOA's dark dress. The guild window is bigger, with its pages as words in the header, the message of the day on its own row and every page, Info included, on dark wells." },
			{ "Switch layout from Ready", "Click your role under Ready on the console to pick Tank, Healer, Melee or Ranged for this spec, or to switch to your other talent spec." },
		},
	},
	{
		edition = "1.6.0",
		title = "New in STOA 1.6",
		lines = {
			{ "Player notes", "Remember who was good to play with and who wasn't. Right-click a player and choose STOA note, or type /stoa note and their name: pick Good or Bad, write one line, press Enter." },
			{ "Where notes come back", "On the player's tooltip, as a diamond on their party card, under their whisper, beside what they say in General, Trade and other public chat, and as one quiet chat line when they join your group." },
			{ "People", "A new tab in the Characters window lists everyone you've noted, to search, edit or remove. /stoa people opens it. Every character of yours shares the notes." },
			{ "Tidier tooltips", "Who someone is now fits one line, like 33 Gnome Mage with the class in its colour. Item level sits beside it behind a sword mark, and your own lines start under a thin rule." },
			{ "Build your STOA", "Settings open on a quick start page: pick a starting set, then switch each piece of STOA on or off, so you run only what you want. The other pages hold the finer settings." },
			{ "Simpler settings", "Each settings page opens on a few everyday settings, with the rest under More. Settings for other classes are gone from view, and search still finds everything." },
			{ "What I've changed", "A new settings page lists everything that isn't as STOA comes. Right-click any setting to put it back." },
			{ "A free right side", "Settings > Console > \"Leave the console's right side free\" hides Ready, Journey and Company, so another addon's window, such as a damage meter, can sit there." },
			{ "Fixes beside other addons", "The game's damage meter comes back after you pick STOA's over EllesmereUI's, and your bags stay as one bag after another bag addon is switched off." },
		},
	},
	{
		edition = "1.5.2",
		title = "New in STOA 1.5.2",
		lines = {
			{ "EllesmereUI", "STOA knows EllesmereUI's parts and asks, part by part, which of the two looks after each, cooldown icons and buff reminders included." },
			{ "EllesmereUI on the console", "Keep EllesmereUI's chat and one click seats it on the console's left page, with its damage meter top left. /stoa fit undo puts them back." },
		},
	},
	{
		edition = "1.5.1",
		title = "New in STOA 1.5.1",
		lines = {
			{ "Daylight UI", "STOA knows Daylight UI's parts and asks, part by part, which of the two looks after each: bags, nameplates, chat, tooltips, frames and more." },
			{ "One page of questions", "When several addons share jobs with STOA, the questions come as one list, with theirs kept unless you pick STOA's." },
			{ "Daylight's chat in the console", "Keep Daylight UI's chat and it sits in the console's chat place, with its tabs along the top edge." },
			{ "Other chat addons", "Chat from another addon now stands above the console instead of behind it." },
			{ "Changing your mind", "Settings > Setup > Other addons lists each shared job, so any answer can be changed later." },
		},
	},
}
local NOTE = NOTES[1]

local PAD = Stoa.space.xl
-- Up to PER_COLUMN lines sit in one column; past that the lines split over
-- two columns side by side.
local PER_COLUMN = 5
local THANKS_PAD = 14
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

-- The window, with a pool of line rows that Paint fills for one note.
function WhatsNew:Build()
	local page = CreateFrame("Frame", "StoaNewsPage", UIParent)
	UI.riseOnShow(page)
	page:SetSize(PAD * 2 + COLUMN, 240)
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
	page.title = title
	-- A big release says what it is about in one line under the title.
	local lead = UI.text(page, "sans", Stoa.typeSize.caption, "accent", "LEFT")
	lead:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -5)
	page.lead = lead
	page.rows, page.tags, page.columns = {}, {}, {}

	-- The foot runs the page's width above the buttons.
	local foot = UI.text(page, "italic", Stoa.typeSize.body, "muted", "LEFT")
	foot:SetPoint("BOTTOMLEFT", PAD, FOOTER + 12)
	foot:SetPoint("RIGHT", page, "RIGHT", -PAD, 0)
	foot:SetWordWrap(true)
	page.foot = foot

	-- A note can carry a thank-you: a recessed box with an accent bar down
	-- its left, a small heading, the words, and where to write.
	local thanks = CreateFrame("Frame", nil, page)
	thanks:SetPoint("BOTTOMLEFT", foot, "TOPLEFT", 0, 14)
	thanks:SetPoint("RIGHT", page, "RIGHT", -PAD, 0)
	UI.well(thanks)
	local bar = thanks:CreateTexture(nil, "ARTWORK")
	bar:SetPoint("TOPLEFT", 0, 0)
	bar:SetPoint("BOTTOMLEFT", 0, 0)
	bar:SetWidth(2)
	UI.paint(bar, "accent")
	local head = UI.text(thanks, "sans", Stoa.typeSize.caption, "accent", "LEFT")
	head:SetPoint("TOPLEFT", THANKS_PAD, -10)
	UI.settleText(head, "THANK YOU")
	local words = UI.text(thanks, "sans", Stoa.typeSize.body, "text", "LEFT")
	words:SetPoint("TOPLEFT", head, "BOTTOMLEFT", 0, -6)
	words:SetWordWrap(true)
	local where = UI.text(thanks, "sans", Stoa.typeSize.body, "accent", "LEFT")
	where:SetPoint("TOPLEFT", words, "BOTTOMLEFT", 0, -6)
	thanks.head, thanks.words, thanks.where = head, words, where
	thanks:Hide()
	page.thanks = thanks

	local settings = UI.button(page, "Open settings", 130, function()
		page:Hide()
		Stoa:OpenSettings()
	end)
	settings:SetPoint("BOTTOMLEFT", PAD, PAD - 10)
	local tour = UI.button(page, "See both looks", 130, function()
		page:Hide()
		Stoa.commands.welcome("update")
	end)
	tour:SetPoint("LEFT", settings, "RIGHT", 10, 0)
	page.tour = tour
	local done = UI.button(page, "Got it", 110, function() page:Hide() end)
	done:SetPoint("BOTTOMRIGHT", -PAD, PAD - 10)
	-- Earlier and Later page through the notes kept in NOTES.
	local later = UI.button(page, "Later", 76, function() WhatsNew:Paint(page.index - 1) end)
	later:SetPoint("RIGHT", done, "LEFT", -10, 0)
	local earlier = UI.button(page, "Earlier", 76, function() WhatsNew:Paint(page.index + 1) end)
	earlier:SetPoint("RIGHT", later, "LEFT", -6, 0)
	page.earlier, page.later = earlier, later

	self.page = page
end

-- Each line: its name, then what it is, wrapped under the name.
local function row(page, i)
	local r = page.rows[i]
	if r then return r end
	r = {}
	r.name = UI.text(page, "sans", Stoa.typeSize.label, "text", "LEFT")
	r.words = UI.text(page, "sans", Stoa.typeSize.body, "muted", "LEFT")
	r.words:SetPoint("TOPLEFT", r.name, "BOTTOMLEFT", 0, -3)
	r.words:SetWidth(COLUMN)
	r.words:SetWordWrap(true)
	page.rows[i] = r
	return r
end

-- The page is as tall as its tallest column. Heights the game won't give
-- in the open (it can hide them) are judged at a line and a half each.
local function heightOf(part)
	local height = Stoa:PlainNumber(part:GetStringHeight())
	return height and height > 0 and height or 22
end

function WhatsNew:Fit()
	local page = self.page
	local box = 0
	local thanks = page.thanks
	if thanks:IsShown() then
		local inner = 10 + heightOf(thanks.head) + 6 + heightOf(thanks.words) + 6 + heightOf(thanks.where) + 12
		thanks:SetHeight(math.ceil(inner))
		box = inner + 14
	end
	-- With two columns the thank-you stands at the foot of the last one,
	-- so it counts toward that column's height; with one it has a band of
	-- its own under the lines.
	local inColumn = #page.columns > 1
	local tallest = 0
	for n, parts in ipairs(page.columns) do
		local tall = 0
		for i, part in ipairs(parts) do tall = tall + heightOf(part) + (i % 2 == 0 and 12 or 3) end
		if inColumn and n == #page.columns then tall = tall + box + 6 end
		tallest = math.max(tallest, tall)
	end
	if inColumn then box = 0 end
	local tall = HEADER + 18 + tallest + 4 + box + heightOf(page.foot) + 12 + FOOTER
	page:SetHeight(math.ceil(tall) + 10)
end

-- Fills the window with one note (1 is the newest).
function WhatsNew:Paint(index)
	local page = self.page
	index = math.max(1, math.min(#NOTES, index or 1))
	local note = NOTES[index]
	page.index = index
	local count = #note.lines
	local columns = count > PER_COLUMN and 2 or 1
	local perColumn = math.ceil(count / columns)
	page:SetWidth(PAD * 2 + columns * COLUMN + (columns - 1) * GAP)
	page.title:SetText(note.title)
	page.title:SetPoint("TOPLEFT", PAD, -PAD + (note.lead and 10 or 4))
	UI.settleText(page.lead, note.lead and note.lead:upper() or "")
	page.lead:SetShown(note.lead ~= nil)
	page.tour:SetShown(note.tour == true)
	local thanks = page.thanks
	thanks:SetShown(note.thanks ~= nil)
	if note.thanks then
		local left = columns > 1 and (columns - 1) * (COLUMN + GAP) or 0
		thanks:ClearAllPoints()
		thanks:SetPoint("BOTTOMLEFT", page.foot, "TOPLEFT", left, 14)
		thanks:SetPoint("RIGHT", page, "RIGHT", -PAD, 0)
		thanks.words:SetWidth(page:GetWidth() - PAD * 2 - left - THANKS_PAD * 2)
		UI.settleText(thanks.words, note.thanks[1])
		UI.settleText(thanks.where, note.thanks[2] or "")
	end
	page.foot:SetText(note.foot or FOOT)
	for _, tag in ipairs(page.tags) do tag:Hide() end
	wipe(page.columns)
	local last
	for i, line in ipairs(note.lines) do
		local column = math.floor((i - 1) / perColumn) + 1
		local parts = page.columns[column]
		if not parts then
			parts = {}
			page.columns[column] = parts
			last = nil
		end
		local r = row(page, i)
		r.name:ClearAllPoints()
		if last then
			r.name:SetPoint("TOPLEFT", last, "BOTTOMLEFT", 0, -12)
		else
			r.name:SetPoint("TOPLEFT", PAD + (column - 1) * (COLUMN + GAP), -(HEADER + 18))
		end
		r.name:SetText(line[1])
		r.words:SetText(line[2])
		r.name:Show()
		r.words:Show()
		local tagAfter = r.name
		for _, class in ipairs(line.classes or {}) do
			local key = index .. ":" .. i .. ":" .. class
			local tag = page.tags[key]
			if not tag then
				tag = WhatsNew.classTag(page, class)
				page.tags[key] = tag
				page.tags[#page.tags + 1] = tag
			end
			tag:ClearAllPoints()
			tag:SetPoint("LEFT", tagAfter, "RIGHT", tagAfter == r.name and 8 or 4, 0)
			tag:Show()
			tagAfter = tag
		end
		parts[#parts + 1], parts[#parts + 2] = r.name, r.words
		last = r.words
	end
	for i = count + 1, #page.rows do
		page.rows[i].name:Hide()
		page.rows[i].words:Hide()
	end
	page.earlier:SetShown(index < #NOTES)
	page.later:SetShown(index > 1)
	self:Fit()
end

function WhatsNew:Show()
	if InCombatLockdown() then
		Stoa:AfterCombat(function() WhatsNew:Show() end)
		return
	end
	if not self.page then self:Build() end
	self:Paint(1)
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
