-- Stoa: other addons doing the same job.
-- When a bag, nameplate, chat, tooltip, bar, minimap, group frame or
-- click-casting addon (or a damage meter) is loaded beside Stoa, the two would dress the same
-- Blizzard frames (or draw two sets of frames). At login Stoa looks for the
-- well-known ones and asks once which should do the job:
--   Keep theirs: Stoa's own part steps aside, remembered account-wide. If the
--   other addon is later removed, Stoa's part comes back by itself.
--   Use Stoa's: the other addon is turned off and the UI reloads.
-- Until a choice is made, Stoa's part steps aside, so nothing fights.
-- A whole UI (ElvUI, SpartanUI and the like) can't share the screen with
-- Stoa: Stoa says so and asks the player to turn one of the two off.
-- /stoa addons lists what was found and asks again.
local _, ns = ...
local Stoa = ns.Stoa
local UI = Stoa.UI

local Conflicts = {}
Stoa.Conflicts = Conflicts

-- Each rule: the Stoa modules it covers, what they do (for the question) and
-- the other addons by folder name, with the name players know them by.
local RULES = {
	{
		key = "suite", job = "your whole screen", suite = true,
		addons = {
			{ "ElvUI", "ElvUI" }, { "Tukui", "Tukui" }, { "SpartanUI", "SpartanUI" },
			{ "NDui", "NDui" }, { "GW2_UI", "GW2 UI" }, { "KkthnxUI", "KkthnxUI" },
			{ "LUI", "LUI" }, { "RealUI", "RealUI" },
		},
	},
	{
		key = "bags", job = "your bags", modules = { "Bags" },
		addons = {
			{ "Bagnon", "Bagnon" }, { "Baganator", "Baganator" }, { "AdiBags", "AdiBags" },
			{ "ArkInventory", "ArkInventory" }, { "BetterBags", "BetterBags" },
			{ "Combuctor", "Combuctor" }, { "LiteBag", "LiteBag" }, { "Inventorian", "Inventorian" },
			{ "Sorted", "Sorted" }, { "DaylightUI_Bags", "Daylight UI Bags" },
			{ "EllesmereUIBags", "EllesmereUI Bags" },
		},
	},
	{
		key = "plates", job = "nameplates", modules = { "Plates" },
		addons = {
			{ "DaylightUI_Nameplates", "Daylight UI Nameplates" },
			{ "EllesmereUINameplates", "EllesmereUI Nameplates" },
			{ "Plater", "Plater" }, { "TidyPlates_ThreatPlates", "Threat Plates" },
			{ "TidyPlates", "TidyPlates" }, { "Kui_Nameplates", "KuiNameplates" },
			{ "NeatPlates", "NeatPlates" }, { "Platynator", "Platynator" },
		},
	},
	{
		key = "chat", job = "the chat", modules = { "ChatLook", "Chat" },
		addons = {
			{ "DaylightUI_Chat", "Daylight UI Chat" }, { "EllesmereUIChat", "EllesmereUI Chat" },
			{ "Prat-3.0", "Prat" }, { "Chattynator", "Chattynator" },
			{ "Glass", "Glass" }, { "Chatter", "Chatter" },
		},
	},
	{
		key = "tooltip", job = "tooltips", modules = { "Tooltip" },
		addons = { { "TipTac", "TipTac" }, { "TinyTooltip", "TinyTooltip" }, { "TipTop", "TipTop" }, { "DaylightUI_Tooltip", "Daylight UI Tooltip" } },
	},
	{
		key = "bars", job = "action bars", modules = { "ActionBars" },
		addons = {
			{ "Bartender4", "Bartender" }, { "Dominos", "Dominos" },
			{ "DaylightUI_ActionBars", "Daylight UI Action Bars" },
			{ "EllesmereUIActionBars", "EllesmereUI Action Bars" },
		},
	},
	{
		key = "minimap", job = "the minimap", modules = { "Minimap" },
		addons = { { "SexyMap", "SexyMap" }, { "BasicMinimap", "BasicMinimap" }, { "EllesmereUIMinimap", "EllesmereUI Minimap" } },
	},
	{
		key = "tray", job = "gathering the minimap's addon icons", modules = { "Tray" },
		addons = {
			{ "MinimapButtonButton", "MinimapButtonButton" }, { "MBB", "MinimapButtonBag" },
			{ "HidingBar", "HidingBar" }, { "MinimapButtonFrame", "MinimapButtonFrame" },
		},
	},
	{
		key = "group", job = "party and raid frames", modules = { "Party", "Raid" },
		addons = {
			{ "VuhDo", "VuhDo" }, { "Grid2", "Grid2" }, { "Cell", "Cell" },
			{ "HealBot", "HealBot" }, { "EllesmereUIRaidFrames", "EllesmereUI Raid Frames" },
			-- These draw a target frame too, so Stoa's target plaque goes with them.
			{ "ShadowedUnitFrames", "Shadowed Unit Frames", { "Target" } },
			{ "DaylightUI_UnitFrames", "Daylight UI Unit Frames", { "Target" } },
		},
	},
	{
		key = "clicks", job = "click-casting", modules = { "ClickCast" },
		addons = { { "Clique", "Clique" } },
	},
	{
		key = "movers", job = "moving Blizzard's windows", modules = { "WindowMover" },
		addons = { { "BlizzMove", "BlizzMove" }, { "MoveAny", "MoveAny" } },
	},
	{
		key = "meters", job = "damage and healing meters", modules = { "Meters" },
		addons = { { "Details", "Details" }, { "Skada", "Skada" }, { "Recount", "Recount" }, { "EllesmereUIDamageMeters", "EllesmereUI Damage Meters", mend = { damageMeterEnabled = "1" } } },
	},
	{
		key = "map", job = "the world map", modules = { "Map" },
		addons = { { "Mapster", "Mapster" } },
	},
	{
		key = "windows", job = "the game's windows", modules = { "Windows", "MoreWindows", "Character", "Spellbook" },
		addons = { { "DaylightUI_Skins", "Daylight UI Window Skins" }, { "EllesmereUIBlizzardSkin", "EllesmereUI Blizzard Skin" } },
	},
	{
		key = "top", job = "buffs and the quest list", modules = { "Top" },
		addons = {
			{ "DaylightUI_Buffs", "Daylight UI Buffs" }, { "DaylightUI_Quests", "Daylight UI Quest Tracker" },
			{ "EllesmereUIQuestTracker", "EllesmereUI Quest Tracker" },
		},
	},
	{
		-- Rows of cooldown icons. Stoa has no part to step aside: the Halo
		-- shows cooldowns, so "Use STOA's" only switches the other addon off.
		key = "cooldowns", job = "cooldown icons", modules = {},
		body = "EllesmereUI Cooldown Manager shows rows of cooldown icons. STOA shows cooldowns on the Halo, so you may not want both.",
		addons = { { "EllesmereUICooldownManager", "EllesmereUI Cooldown Manager" } },
	},
	{
		-- Icons for the buffs you're missing: Stoa's are the row left of
		-- the Halo (Modules/Halo/SelfBuffs.lua).
		key = "reminders", job = "buff reminders", modules = { "SelfBuffs" },
		addons = { { "EllesmereUIAuraBuffReminders", "EllesmereUI AuraBuff Reminders" } },
	},
	{
		-- Unit frames that leave party and raid frames to another module.
		key = "target", job = "the target frame", modules = { "Target" },
		addons = { { "EllesmereUIUnitFrames", "EllesmereUI Unit Frames" } },
	},
	{
		key = "corner", job = "the minimap, experience bar and meters", modules = { "Minimap", "XPBar", "Meters" },
		addons = { { "DaylightUI_InfoPanel", "Daylight UI Info Panel" } },
	},
}

-- Daylight UI's character window is part of its core, switched by its own
-- setting.
local function daylight(scope, path, value)
	local dui = _G.DaylightUI
	if type(dui) ~= "table" or type(dui.Get) ~= "function" or type(dui.Set) ~= "function" then return nil end
	if value == nil then
		local ok, now = pcall(dui.Get, dui, scope, path)
		if ok then return now end
		return nil
	end
	pcall(dui.Set, dui, scope, path, value)
end

RULES[#RULES + 1] = {
	key = "sheet", job = "the character window", modules = { "Character" },
	addons = { {
		"DaylightUI", "Daylight UI's character window",
		on = function()
			local dui = _G.DaylightUI
			if type(dui) ~= "table" or type(dui.GetModule) ~= "function" then return false end
			local ok, module = pcall(dui.GetModule, dui, "Character")
			return ok and module ~= nil and daylight("Character", "enabled") ~= false
		end,
		off = function() daylight("Character", "enabled", false) end,
		back = function() daylight("Character", "enabled", true) end,
	} },
}

local function isLoaded(folder)
	if C_AddOns and C_AddOns.IsAddOnLoaded then return C_AddOns.IsAddOnLoaded(folder) end
	return IsAddOnLoaded and IsAddOnLoaded(folder)
end

local function disable(folder)
	if C_AddOns and C_AddOns.DisableAddOn then
		C_AddOns.DisableAddOn(folder)
	elseif DisableAddOn then
		DisableAddOn(folder)
	end
end

local function enable(folder)
	if C_AddOns and C_AddOns.EnableAddOn then
		C_AddOns.EnableAddOn(folder)
	elseif EnableAddOn then
		EnableAddOn(folder)
	end
end

-- A part of a larger addon (an entry with on, off and back) is switched in
-- that addon's own settings instead of turning the whole addon off.
-- `mend` on an addon: game settings it changes and only puts back while it
-- runs (EllesmereUI's meter switches the game's own meter off, the one Stoa
-- dresses). Choosing Stoa's part notes them, and the next login without
-- that addon sets them (Conflicts:Check).
local function turnOff(addon)
	if addon.off then addon.off() else disable(addon[1]) end
	if addon.mend then
		Stoa.db.mend = Stoa.db.mend or {}
		Stoa.db.mend[addon[1]] = addon.mend
	end
end

local function turnOn(addon)
	if addon.back then addon.back() else enable(addon[1]) end
end

local function choices()
	Stoa.db.addons = Stoa.db.addons or {}
	return Stoa.db.addons
end

-- An answer belongs to the addons it was given for (their folders, in
-- Stoa.db.addonsFor), so another addon turning up for the same job later is
-- asked about, not quietly kept.
local function keptFor()
	Stoa.db.addonsFor = Stoa.db.addonsFor or {}
	return Stoa.db.addonsFor
end

local function keep(entry)
	choices()[entry.rule.key] = "theirs"
	local folders = {}
	for _, addon in ipairs(entry.loaded) do folders[addon[1]] = true end
	keptFor()[entry.rule.key] = folders
end

local function forget(entry)
	choices()[entry.rule.key] = nil
	keptFor()[entry.rule.key] = nil
end

-- "Bagnon", "Bagnon and AdiBags", "Bagnon, AdiBags and Sorted".
local function names(found)
	local list = {}
	for i, addon in ipairs(found) do list[i] = addon[2] end
	if #list < 2 then return list[1] or "" end
	return table.concat(list, ", ", 1, #list - 1) .. " and " .. list[#list]
end

-- Modules held back this session, by name, with the rule that holds them.
local aside = {}
local found = {}

function Conflicts:SteppedAside(name)
	return aside[name]
end

-- For the welcome page (Config/Welcome.lua): each clash found, its saved
-- answer, and a way to settle one there without the question page.
Conflicts.names = names

function Conflicts:Found()
	return found
end

function Conflicts:Saved(entry)
	return choices()[entry.rule.key]
end

-- "theirs" keeps the other addon; "ours" turns it off and returns true, as
-- it only takes effect after a reload.
function Conflicts:Settle(entry, choice)
	entry.asked = true
	if choice == "ours" then
		for _, addon in ipairs(entry.loaded) do turnOff(addon) end
		forget(entry)
		return true
	end
	keep(entry)
	return false
end

-- From Settings: "theirs" keeps the other addon, "ours" turns it off (and
-- "theirs" or "ask" turns it back on if this session turned it off), "ask"
-- forgets the answer. All of it takes effect at the next reload.
function Conflicts:Pick(entry, choice)
	entry.asked = true
	entry.picked = choice
	for _, addon in ipairs(entry.loaded) do
		if choice == "ours" then turnOff(addon) else turnOn(addon) end
	end
	if choice == "theirs" then keep(entry) else forget(entry) end
end

-- Called once at login, before modules are enabled.
function Conflicts:Check()
	wipe(aside)
	wipe(found)
	for folder, settings in pairs(Stoa.db.mend or {}) do
		if not isLoaded(folder) and type(settings) == "table" then
			for name, value in pairs(settings) do Stoa.GameSettings:Mend(name, value) end
		end
	end
	Stoa.db.mend = nil
	for _, rule in ipairs(RULES) do
		local loaded = {}
		for _, addon in ipairs(rule.addons) do
			if isLoaded(addon[1]) and (not addon.on or addon.on()) then loaded[#loaded + 1] = addon end
		end
		-- A part the player already switched off has nothing to fight over.
		local running = rule.suite or #(rule.modules or {}) == 0
		for _, name in ipairs(rule.modules or {}) do
			local settings = Stoa.db.modules[name]
			if not settings or settings.enabled ~= false then running = true end
		end
		if #loaded > 0 and running then
			-- An answer given for other addons doesn't cover a new one. One
			-- from before answers were tied to addons is taken as given for
			-- what's here now.
			if not rule.suite and choices()[rule.key] == "theirs" then
				local folders = keptFor()[rule.key]
				if not folders then
					keep({ rule = rule, loaded = loaded })
				else
					for _, addon in ipairs(loaded) do
						if not folders[addon[1]] then
							forget({ rule = rule })
							break
						end
					end
				end
			end
			found[#found + 1] = { rule = rule, loaded = loaded }
			if not rule.suite then
				for _, name in ipairs(rule.modules) do aside[name] = rule end
				-- An addon that does more than the rule's job names the rest.
				for _, addon in ipairs(loaded) do
					for _, name in ipairs(addon[3] or {}) do aside[name] = rule end
				end
			end
		end
	end
end

-- The question ------------------------------------------------------------------

local WIDTH, HEIGHT = 460, 220
local PAD = Stoa.space.xl

-- A small question page with a title, a few lines and two buttons; Stoa's
-- other questions about addons (Core/Looks.lua) use it too.
function Conflicts:Page(name, onLeft, onRight)
	local page = CreateFrame("Frame", name, UIParent)
	page:SetSize(WIDTH, HEIGHT)
	page:SetPoint("CENTER", 0, 120)
	page:SetFrameStrata("DIALOG")
	page:EnableMouse(true)
	page:SetMovable(true)
	page:RegisterForDrag("LeftButton")
	page:SetScript("OnDragStart", page.StartMoving)
	page:SetScript("OnDragStop", page.StopMovingOrSizing)
	page:Hide()
	UI.windowPanel(page, 0.97, { header = 64, footer = 58 })

	local title = UI.text(page, "serif", Stoa.typeSize.title, "text", "LEFT")
	title:SetPoint("TOPLEFT", PAD, -PAD + 4)
	page.title = title

	local body = UI.text(page, "sans", Stoa.typeSize.label, "text", "LEFT")
	body:SetPoint("TOPLEFT", PAD, -82)
	body:SetPoint("RIGHT", page, "RIGHT", -PAD, 0)
	body:SetWordWrap(true)
	page.body = body

	local note = UI.text(page, "italic", Stoa.typeSize.body, "muted", "LEFT")
	note:SetPoint("TOPLEFT", body, "BOTTOMLEFT", 0, -10)
	note:SetPoint("RIGHT", page, "RIGHT", -PAD, 0)
	note:SetWordWrap(true)
	page.note = note

	page.left = UI.button(page, "", 200, onLeft, true)
	page.left:SetPoint("BOTTOMLEFT", PAD, PAD - 10)
	page.right = UI.button(page, "", 200, onRight, true)
	page.right:SetPoint("BOTTOMRIGHT", -PAD, PAD - 10)
	return page
end

function Conflicts:Build()
	local page = self:Page("StoaAddonsPage", function(button) self:Answer("theirs", button) end, function(button) self:Answer("ours", button) end)
	page.theirs, page.ours = page.left, page.right
	self.page = page
end

function Conflicts:Ask(entry)
	if not self.page then self:Build() end
	local page, rule = self.page, entry.rule
	local them = names(entry.loaded)
	self.asking = entry
	local single = #entry.loaded == 1
	local everyone = { unpack(entry.loaded) }
	everyone[#everyone + 1] = { "Stoa", "STOA" }
	if rule.suite then
		-- A whole UI and Stoa can't share the screen: no keeping both.
		page.title:SetText("These don't work together")
		page.body:SetText(("STOA and %s are both whole interfaces and don't work together. Please turn one of them off."):format(them))
		page.note:SetText("Either button turns that addon off and reloads.")
		page.theirs.text:SetText("Turn STOA off")
		page.ours.text:SetText(single and ("Turn " .. them .. " off") or "Turn the others off")
	else
		page.title:SetText("Two addons, one job")
		page.body:SetText(("%s %s look after %s. Pick one so they don't get in each other's way."):format(names(everyone), single and "both" or "all", rule.job))
		page.theirs.text:SetText(single and #them <= 22 and ("Keep " .. them) or "Keep theirs")
		page.ours.text:SetText("Use STOA's")
		if rule.body then page.body:SetText(rule.body) end
		page.note:SetText(((rule.body and "" or "STOA's part waits until you choose. ") .. "Using STOA's turns %s off and reloads; /stoa addons asks again."):format(them))
	end
	page.ours:SetReloads(true)
	page.theirs:SetReloads(rule.suite)
	page:Show()
end

function Conflicts:Answer(choice, button)
	local entry = self.asking
	if not entry then return end
	self.asking = nil
	-- A button that reloads with its own click (UI.button) needs the page
	-- left up for it.
	local own = button and button.reloads
	if not own then self.page:Hide() end
	local rule = entry.rule
	if choice == "ours" then
		for _, addon in ipairs(entry.loaded) do turnOff(addon) end
		forget(entry)
		if not own then Stoa:Reload() end
	elseif rule.suite then
		disable("Stoa")
		if not own then Stoa:Reload() end
	else
		keep(entry)
		Stoa:Print(("Leaving %s to %s. /stoa addons to change."):format(rule.job, names(entry.loaded)))
		self:Next()
	end
end

-- Several clashes at once (a modular UI such as Daylight UI brings many):
-- one page with a row for each, both choices on the row, and one button.
local LIST_WIDTH, ROW_HEIGHT, ROWS_TOP = 640, 46, 132

function Conflicts:BuildList()
	local page = CreateFrame("Frame", "StoaAddonsList", UIParent)
	page:SetSize(LIST_WIDTH, HEIGHT)
	page:SetPoint("CENTER", 0, 60)
	page:SetFrameStrata("DIALOG")
	page:EnableMouse(true)
	page:SetMovable(true)
	page:RegisterForDrag("LeftButton")
	page:SetScript("OnDragStart", page.StartMoving)
	page:SetScript("OnDragStop", page.StopMovingOrSizing)
	page:Hide()
	UI.windowPanel(page, 0.97, { header = 64, footer = 58 })

	local title = UI.text(page, "serif", Stoa.typeSize.title, "text", "LEFT")
	title:SetPoint("TOPLEFT", PAD, -PAD + 4)
	title:SetText("Other addons, shared jobs")

	local body = UI.text(page, "sans", Stoa.typeSize.label, "text", "LEFT")
	body:SetPoint("TOPLEFT", PAD, -82)
	body:SetPoint("RIGHT", page, "RIGHT", -PAD, 0)
	body:SetWordWrap(true)
	body:SetText("These addons look after parts of the screen STOA does too. Pick one for each, so they don't get in each other's way.")

	local note = UI.text(page, "italic", Stoa.typeSize.body, "muted", "LEFT")
	note:SetPoint("BOTTOMLEFT", PAD, PAD - 2)
	note:SetPoint("RIGHT", page, "RIGHT", -PAD - 190, 0)
	note:SetWordWrap(true)
	note:SetText("Using STOA's turns the other addon's part off. /stoa addons asks again.")

	page.done = UI.button(page, "Done", 170, function(button) self:AnswerAll(button) end, true)
	page.done:SetPoint("BOTTOMRIGHT", -PAD, PAD - 10)
	page.rows = {}
	self.list = page
end

-- Shows each row's choice, and whether the button will reload.
function Conflicts:PaintList()
	local page, reload = self.list, false
	for i, entry in ipairs(self.listing or {}) do
		local row = page.rows[i]
		row.theirs:SetSelected(entry.choice ~= "ours")
		row.ours:SetSelected(entry.choice == "ours")
		if entry.choice == "ours" then reload = true end
	end
	-- The fit row shows while EllesmereUI's chat is the one kept.
	local fitRow = page.fitRow
	local fits = page.fitOffered and page.fitOffered.choice ~= "ours" or false
	if fitRow then
		fitRow:SetShown(fits)
		fitRow.yes:SetSelected(page.fitWanted)
		fitRow.no:SetSelected(not page.fitWanted)
	end
	page.fitNow = fits and page.fitWanted or false
	if page.fitNow then reload = true end
	page.done:SetReloads(reload)
	page.done.text:SetText(reload and "Done, and reload" or "Done")
end

function Conflicts:AskAll(entries)
	if not self.list then self:BuildList() end
	local page = self.list
	self.listing = entries
	for i, entry in ipairs(entries) do
		local row = page.rows[i]
		if not row then
			row = CreateFrame("Frame", nil, page)
			row:SetHeight(ROW_HEIGHT)
			row:SetPoint("TOPLEFT", PAD, -ROWS_TOP - (i - 1) * ROW_HEIGHT)
			row:SetPoint("RIGHT", page, "RIGHT", -PAD, 0)
			row.job = UI.text(row, "sans", Stoa.typeSize.label, "text", "LEFT")
			row.job:SetPoint("TOPLEFT", 0, -4)
			row.job:SetPoint("RIGHT", row, "RIGHT", -250, 0)
			row.job:SetWordWrap(false)
			row.them = UI.text(row, "sans", Stoa.typeSize.body, "muted", "LEFT")
			row.them:SetPoint("TOPLEFT", row.job, "BOTTOMLEFT", 0, -3)
			row.them:SetPoint("RIGHT", row, "RIGHT", -250, 0)
			row.them:SetWordWrap(false)
			row.ours = UI.button(row, "Use STOA's", 110, function()
				self.listing[i].choice = "ours"
				self:PaintList()
			end)
			row.ours:SetPoint("RIGHT", 0, 0)
			row.theirs = UI.button(row, "Keep theirs", 110, function()
				self.listing[i].choice = "theirs"
				self:PaintList()
			end)
			row.theirs:SetPoint("RIGHT", row.ours, "LEFT", -8, 0)
			page.rows[i] = row
		end
		entry.choice = entry.choice or "theirs"
		row.job:SetText((entry.rule.job:gsub("^%l", string.upper)))
		row.them:SetText(names(entry.loaded))
		row:Show()
	end
	for i = #entries + 1, #page.rows do page.rows[i]:Hide() end
	-- Keeping EllesmereUI's chat: one more row offers to seat it on the
	-- console in the same reload (Console:FitEllesmere, Housing.lua).
	page.fitOffered = false
	for _, entry in ipairs(entries) do
		for _, addon in ipairs(entry.loaded) do
			if addon[1] == "EllesmereUIChat" then page.fitOffered = entry end
		end
	end
	local console = Stoa.modules.Grimoire
	if not (console and console.FitEllesmere and not console.bare and not (console.db and console.db.slim)) then page.fitOffered = false end
	if page.fitOffered and not page.fitRow then
		local row = CreateFrame("Frame", nil, page)
		row:SetHeight(ROW_HEIGHT)
		row:SetPoint("RIGHT", page, "RIGHT", -PAD, 0)
		row.job = UI.text(row, "sans", Stoa.typeSize.label, "text", "LEFT")
		row.job:SetPoint("TOPLEFT", 0, -4)
		row.job:SetPoint("RIGHT", row, "RIGHT", -250, 0)
		row.job:SetWordWrap(false)
		row.job:SetText("EllesmereUI's chat on the console")
		row.them = UI.text(row, "sans", Stoa.typeSize.body, "muted", "LEFT")
		row.them:SetPoint("TOPLEFT", row.job, "BOTTOMLEFT", 0, -3)
		row.them:SetPoint("RIGHT", row, "RIGHT", -250, 0)
		row.them:SetWordWrap(false)
		row.them:SetText("Meter goes top left. If the chat covers At a glance, drag its corner narrower.")
		row.yes = UI.button(row, "Seat it", 110, function()
			page.fitWanted = true
			self:PaintList()
		end)
		row.yes:SetPoint("RIGHT", 0, 0)
		row.no = UI.button(row, "Leave it", 110, function()
			page.fitWanted = false
			self:PaintList()
		end)
		row.no:SetPoint("RIGHT", row.yes, "LEFT", -8, 0)
		page.fitRow = row
		page.fitWanted = true
	end
	if page.fitRow then
		page.fitRow:ClearAllPoints()
		page.fitRow:SetPoint("TOPLEFT", PAD, -ROWS_TOP - #entries * ROW_HEIGHT)
		page.fitRow:SetPoint("RIGHT", page, "RIGHT", -PAD, 0)
	end
	page:SetHeight(ROWS_TOP + (#entries + (page.fitOffered and 1 or 0)) * ROW_HEIGHT + 58 + PAD)
	self:PaintList()
	page:Show()
end

function Conflicts:AnswerAll(button)
	local entries = self.listing
	if not entries then return end
	self.listing = nil
	local own = button and button.reloads
	if not own then self.list:Hide() end
	local kept = {}
	for _, entry in ipairs(entries) do
		if entry.choice == "ours" then
			for _, addon in ipairs(entry.loaded) do turnOff(addon) end
			forget(entry)
		else
			keep(entry)
			kept[#kept + 1] = entry.rule.job
		end
	end
	if self.list.fitNow then
		local console = Stoa.modules.Grimoire
		if console and console.FitEllesmere then pcall(console.FitEllesmere, console) end
	end
	if #kept > 0 and not own then
		Stoa:Print(("Leaving %s to the other %s. /stoa addons to change."):format(
			#kept < 2 and kept[1] or (table.concat(kept, ", ", 1, #kept - 1) .. " and " .. kept[#kept]),
			#kept < 2 and "addon" or "addons"))
	end
	if not own then self:Next() end
end

-- Asks about each clash not settled before: a whole UI first and alone,
-- one other alone on the small page, several together on the list. While
-- the welcome page is still to come or open, it asks those itself; only a
-- whole UI is asked about here.
function Conflicts:Next()
	local saved = choices()
	local welcoming = Stoa.Welcome and Stoa.Welcome:Pending()
	local waiting = {}
	for _, entry in ipairs(found) do
		if not entry.asked and saved[entry.rule.key] ~= "theirs" and (entry.rule.suite or not welcoming) then
			if entry.rule.suite then
				entry.asked = true
				Stoa:AfterCombat(function() self:Ask(entry) end)
				return
			end
			waiting[#waiting + 1] = entry
		end
	end
	if #waiting == 1 then
		waiting[1].asked = true
		Stoa:AfterCombat(function() self:Ask(waiting[1]) end)
		return
	elseif #waiting > 1 then
		for _, entry in ipairs(waiting) do entry.asked = true end
		Stoa:AfterCombat(function() self:AskAll(waiting) end)
		return
	end
	-- Settled: Stoa's look for the addons kept (Core/Looks.lua).
	if Stoa.Looks and not welcoming then Stoa.Looks:Next() end
end

-- EllesmereUI opens with its own first-time pages: one where the player
-- picks which of its addons stay on, then, a reload later, one for its look.
-- Stoa's questions wait until both are done, so the pages never stack and
-- Stoa asks about the addons actually kept. Until then Stoa's parts stay
-- aside, as for any unanswered question.
local function theirSetupPending()
	local db = _G.EllesmereUIDB
	return type(db) == "table" and (not db.firstInstallPopupShown or db.styleChoicePending) and true or false
end

-- Looks again every few seconds for a page closed without a reload, for
-- five minutes; after that the questions wait for the next login.
local function askWhenClear(tries)
	if not theirSetupPending() then
		Conflicts:Next()
	elseif tries > 0 then
		C_Timer.After(3, function() askWhenClear(tries - 1) end)
	end
end

Stoa:On("STOA_READY", function()
	if #found == 0 then return end
	C_Timer.After(4, function() askWhenClear(100) end)
end)

Stoa.commands.addons = function()
	if Stoa.Companions then Stoa.Companions:Report() end
	if #found == 0 then
		Stoa:Print("No other addon is doing one of STOA's jobs.")
		return
	end
	for _, entry in ipairs(found) do
		Stoa:Print(("%s also %s after %s."):format(names(entry.loaded), #entry.loaded == 1 and "looks" or "look", entry.rule.job))
		forget(entry)
		entry.asked = nil
	end
	Conflicts:Next()
end
