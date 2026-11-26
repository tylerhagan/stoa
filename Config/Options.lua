-- Stoa: every setting, described once. The settings window (Config/Window.lua)
-- draws its pages, search and notes from this list. A page: id, name, what
-- it holds, and a shorter name for the list of pages when the name is long.
--
-- A setting: page, group, id, name, desc, kind, and how to read and write it.
-- Kinds: toggle, choice (a row of choices, or a list when there are many),
-- words (chips you add and take away), checks (a list of ticks), glance (At a
-- glance's lines), button and actions (things to do now). Flags: reload
-- (takes effect after /reload), game (changes one of the game's own
-- settings), scope (where it is kept, when not account-wide), cmd (the
-- /stoa words that do the same), words (other words search should find),
-- needs (an addon it needs).
--
-- Each page opens on its few everyday settings (EVERYDAY, or everyday = true)
-- with the rest one click away under More. A setting in QUIET follows another
-- or is always as it comes: it is off the pages, and still found by search and
-- listed on What I've changed if it was ever set otherwise. A setting for
-- other classes (classes) or for an addon that isn't loaded (addonGlobal) is
-- left out altogether.
local _, ns = ...
local Stoa = ns.Stoa

local Options = { list = {}, byId = {}, start = {} }
Stoa.Options = Options

Options.PAGES = {
	{ "parts", "Build your STOA", "Start here. Pick a layout (Full, Slim or None), then switch on only the parts you want: anything you switch off goes back to the game's own. This page is the quick start; each part's finer settings are on its own page in the list on the left.", "Quick start" },
	{ "look", "Look", "The style (Leather or Matte black), then theme and colour. These change everything else, so they come first." },
	{ "console", "Console", "The console along the bottom of the screen and what it holds." },
	{ "combat", "Combat", "What happens when a fight starts: the Halo, the combat bar and what they show." },
	{ "group", "Group", "Party and raid cards, healing clicks, and tools for tanks and leaders." },
	{ "plates", "Plates & tooltips", "Nameplates over the world, and the cards that appear under the mouse." },
	{ "windows", "Windows", "Blizzard's own windows in STOA's dress, and moving them." },
	{ "mapchat", "Map & chat", "The minimap, the world map and the chat." },
	{ "journey", "Levelling & loot", "Help along the way: pace, quests, trainers, rewards and loot." },
	{ "comforts", "Comforts", "Small things STOA does for you. Hold Shift to stop any of them in the moment." },
	{ "setup", "Setup", "Your setup as a whole: start again, keep a copy, put the game back, report a problem." },
	{ "changed", "What I've changed", "Every setting that isn't as STOA comes. Right-click one to put it back, here or on any page.", "Changed" },
}

local function setOf(...)
	local out = {}
	for _, name in ipairs({ ... }) do out[name] = true end
	return out
end

-- The quick start page: the main switch of each piece of Stoa, gathered from the
-- pages below under a plain name, with what you get and what Off leaves.
-- { setting id, group, name, what it is }
local PARTS = {
	{ "preset", "Step 1: pick a layout", "Layout: Full, Slim or None", "The first of two answers that set the parts below in one go: the Full console, Slim (one line) or None. None with Quiet below is the Minimal layout. Then switch parts on or off." },
	{ "around", "Step 1: pick a layout", "Layout: everything around it", "The second answer. Standard shows everything. Quiet makes the target and party thin strips that fade out of combat and puts the extras away." },
	{ "consoleShape", "Step 2: choose your parts, out of a fight", "Console", "The panel along the bottom of the screen that holds chat, your action bars and the Ready, Journey and Company pages. Slim is one thin line with chat and bars standing above it. None takes the console away." },
	{ "houseChat", "Step 2: choose your parts, out of a fight", "Chat on the console", "Chat sits on the console's left page. Off leaves the chat window where the game puts it." },
	{ "glanceOn", "Step 2: choose your parts, out of a fight", "At a glance", "Up to eight numbers you choose, such as gold, gear and stats, beside the chat on the console. Off takes them away." },
	{ "actionBars", "Step 2: choose your parts, out of a fight", "Action buttons", "Rounded buttons with a fine edge and dim sockets for empty slots. Off keeps the game's square buttons." },
	{ "combatConsole", "In a fight", "The Halo", "The ring around your character in a fight, with your health, power, casts and cooldowns where your eyes already are. Fold to the Halo puts the console away while you fight. Console and Halo keeps both. Console only turns the Halo off, for players who use other unit frames." },
	{ "combatBar", "In a fight", "Combat bar", "A compact row of your main bar's spells under the Halo in a fight, with their keys. Off leaves your usual action bars in place." },
	{ "partyOn", "In a fight", "Party cards", "Your party as STOA's cards: large beside the Halo when you heal, compact on the left otherwise. Off brings back the game's party frames." },
	{ "raidOn", "In a fight", "Raid frames", "Your raid as a grid of compact cards, one column per group. Off brings back the game's raid frames." },
	{ "platesOn", "Over the world", "Nameplates", "Flat health bars over enemies, coloured by what you can do to them. Off keeps the game's nameplates." },
	{ "tooltipOn", "Over the world", "Tooltips", "Tooltips as cards with extra lines: who a unit targets, your threat, a player's item level, how many of an item you own. Off keeps the game's tooltips." },
	{ "minimap", "Over the world", "Minimap", "The minimap with an edge in your theme's colour and the zone name above it. Off keeps the game's minimap." },
	{ "top", "Over the world", "Buffs and quest list", "Your buffs as cropped icons with quiet timers, and the quest list in STOA's type. Off keeps the game's." },
	{ "windowsOn", "Windows and bags", "Windows", "The quest, merchant, trainer, spellbook, talents, mail and other game windows on dark panels with light text. Off keeps them as the game draws them." },
	{ "bags", "Windows and bags", "Bags", "Rounded slots with a coloured edge by quality, item level on gear and a Sort button. Off keeps the game's bags." },
	{ "character", "Windows and bags", "Character sheet", "Item level and quality on every slot, with gear that needs repair marked. Off keeps the game's character sheet." },
	{ "meters", "Windows and bags", "Damage meter", "The game's damage and healing meter as plain words and faint bars with no panel. Off keeps the game's look." },
	{ "xpbar", "Windows and bags", "Experience bar", "The experience and reputation bar as a thin flat bar. Off keeps the game's bar." },
}

local EVERYDAY = setOf(
	"Style", "Matte grain", "Theme", "Class colours on names", "Colour vision", "Text size", "Ornament", "Rounded action buttons",
	"Console size", "Leather console", "Hold chat in the console", "Travel line while riding", "At a glance, beside the chat", "Lines at a glance",
	"In combat", "Target of target", "Focus", "Combat bar under the Halo", "Combat rows", "Proc art beside the Halo",
	"Show STOA party cards", "Show STOA raid frames", "Show sample frames", "Click-casting", "Click bindings", "Threat meter",
	"Restyle nameplates", "Nameplate style", "Damage numbers", "Tooltip cards", "Tooltip position",
	"Restyle Blizzard windows", "Restyle bags", "Bag layout", "Restyle the top of the screen", "Move STOA's frames",
	"Style the minimap", "Minimap shape", "Gather addon icons", "Times on chat lines",
	"Experience pace", "New spells at your trainer", "Mark the best quest reward", "Quest item buttons", "Your buffs at hand", "Emergency item",
	"Faster loot", "Whisper card", "Accept quests", "Hand in quests", "Sell grey junk", "Repair gear", "Away screen", "Dungeon companion",
	"Welcome page", "Layout: Full, Slim or None", "Layout: everything around it", "Backup", "Characters", "Bind keys", "Other addons", "Report a problem"
)

local QUIET = setOf(
	"Smooth health and power", "Hide action bar art",
	"Five-second rule on the console", "Cast cost on the console", "Form mana on the console",
	"Turn the game's own proc art off", "Check it",
	"Hide Blizzard's party frames", "Hide Blizzard's raid frames", "Threat meter only in combat", "Stop logging when you leave",
	"Restyle more windows",
	"More space between chat lines", "Chat buttons in a column", "Quiet typing box",
	"Ranks", "Sparkle on what's up close", "Hide other people's duel results", "Hide drunken chatter",
	"Say what came out", "Gallery", "Launch check"
)

local MANA = setOf("PRIEST", "MAGE", "WARLOCK", "DRUID", "SHAMAN", "PALADIN", "HUNTER")
local PETS = setOf("HUNTER", "WARLOCK")

-- False for a setting that can't do anything on this character.
local function applies(entry)
	if entry.classes then
		local _, class = UnitClass("player")
		if class and not entry.classes[class] then return false end
	end
	if entry.addonGlobal and rawget(_G, entry.addonGlobal) == nil then return false end
	return true
end

local function module(name)
	local found = Stoa.modules[name]
	return found and found.db
end

local function value(entry)
	if entry.get then return entry.get() end
	local tbl = entry.tbl and entry.tbl()
	if not tbl then return nil end
	local v = tbl[entry.key]
	if v == nil then return entry.default end
	return v
end
Options.value = value

-- Changes go through here, so the window, defaults and search all agree.
-- onChange takes (setting, value) as the game's Settings API did.
function Options.set(entry, v)
	if entry.set then
		entry.set(v)
	else
		local tbl = entry.tbl and entry.tbl()
		if not tbl then return end
		tbl[entry.key] = v
	end
	if entry.change then xpcall(entry.change, Stoa.catch, nil, v) end
	Stoa:Fire("STOA_OPTION_CHANGED", entry.id, v)
end

-- Settings read when the UI loads: changed since login means a reload.
function Options.waiting(entry)
	if not entry.reload then return false end
	local was, now = Options.start[entry.startId or entry.id], entry.state and entry.state() or value(entry)
	if entry.reloadWhen then return entry.reloadWhen(was, now) end
	return was ~= now
end

function Options.pending()
	local n = 0
	for _, entry in ipairs(Options.list) do
		if Options.waiting(entry) then n = n + 1 end
	end
	return n
end

local page, group
local function add(entry)
	if not applies(entry) then return entry end
	entry.page, entry.group = entry.page or page, entry.group or group
	entry.id = entry.id or entry.key
	entry.quiet = QUIET[entry.name] or nil
	entry.more = not (entry.everyday or EVERYDAY[entry.name]) or nil
	-- A setting that belongs to another (`under` = its id) is drawn tucked
	-- beneath it, so it folds away with it too.
	local parent = entry.under and Options.byId[entry.under]
	if parent then entry.more = parent.more end
	if Options.byId[entry.id] then entry.id = entry.id .. #Options.list end
	Options.list[#Options.list + 1] = entry
	Options.byId[entry.id] = entry
	return entry
end

-- toggle(tableFn, key, name, desc, default, extra)
local function toggle(tbl, key, name, desc, default, extra)
	extra = extra or {}
	extra.kind, extra.tbl, extra.key, extra.name, extra.desc, extra.default = "toggle", tbl, key, name, desc, default
	return add(extra)
end

-- choice(tableFn, key, name, desc, default, { { value, label }, ... }, extra)
local function choice(tbl, key, name, desc, default, options, extra)
	extra = extra or {}
	extra.kind, extra.tbl, extra.key, extra.name, extra.desc, extra.default, extra.options = "choice", tbl, key, name, desc, default, options
	return add(extra)
end

local function button(id, name, desc, label, run, extra)
	extra = extra or {}
	extra.kind, extra.id, extra.name, extra.desc, extra.label, extra.run = "button", id, name, desc, label, run
	return add(extra)
end

-- actions(id, name, desc, { { label, fn, said }, ... }, extra)
local function actions(id, name, desc, list, extra)
	extra = extra or {}
	extra.kind, extra.id, extra.name, extra.desc, extra.actions = "actions", id, name, desc, list
	return add(extra)
end

local function db() return Stoa.db end
local function of(name) return function() return module(name) end end
local function command(word, rest) return function() if Stoa.commands[word] then Stoa.commands[word](rest or "") end end end
local function refresh(name, method)
	return function()
		local found = Stoa.modules[name]
		if found and found[method] then found[method](found) end
	end
end

-- Word lists ------------------------------------------------------------------

local function itemLabel(id)
	local name = C_Item and C_Item.GetItemNameByID and Stoa.safe.call(C_Item.GetItemNameByID, id)
	if type(name) == "string" and not Stoa:IsSecret(name) then return name end
	return "Item " .. id
end

-- An item from a link, a number or a name the game already knows.
local function itemId(text)
	local id = Stoa.Items.id(text)
	if id then return id end
	if C_Item and C_Item.GetItemInfoInstant then
		local found = Stoa.safe.call(C_Item.GetItemInfoInstant, text)
		if type(found) == "number" then return found end
	end
end

local function sortedKeys(set, label)
	local out = {}
	for k in pairs(set or {}) do out[#out + 1] = { k, label and label(k) or tostring(k) } end
	table.sort(out, function(a, b) return a[2]:lower() < b[2]:lower() end)
	return out
end

local function inviteWords()
	local list, seen = {}, {}
	for word in (module("AutoInvite") and module("AutoInvite").keywords or ""):gmatch("[^,%s]+") do
		word = word:lower()
		if not seen[word] then
			seen[word] = true
			list[#list + 1] = { word, word }
		end
	end
	return list
end

local function setInviteWords(list)
	local words = {}
	for _, item in ipairs(list) do words[#words + 1] = item[1] end
	module("AutoInvite").keywords = table.concat(words, ", ")
end

-- Building --------------------------------------------------------------------

local function build()
	local halo, party = of("Halo"), of("Party")
	local console, tooltip, plates = of("Grimoire"), of("Tooltip"), of("Plates")
	local rulesChanged = function() Stoa:Fire("STOA_RULES_CHANGED") end

	-- The console and the Halo are one choice, so the console never folds
	-- away with no Halo to take its place. "none" also turns the Halo off.
	if halo() and halo().enabled == false then Stoa.db.combatConsole = "none" end

	-- Look
	page = "look"
	group = "Style"
	choice(db, "material", "Style", "The whole design, and the biggest change on this page. It switches the console, windows, target and party frames, nameplates and minimap together. Leather is tooled leather and brass on the console, with warm rounded panels. Matte black is moulded black hardware: sharp corners, flat plates and a fine grain, and it loads far less art. Theme below then picks the colours; the Matte theme suits Matte black, and any theme's accent works as its light.", "leather", { { "leather", "Leather" }, { "matte", "Matte black" } }, { reload = true, words = "material look design matte black hardware plastic texture grain leather v2" })
	-- Leather's own choice: Matte black has no painted pieces, so the
	-- setting is only there under Leather.
	choice(db, "ornament", "Ornament", "Plain keeps STOA's fine lines. Painted puts leather and brass frames on the one-of-a-kind pieces: the minimap, the portrait coins on your target and tank plaques, and the Halo's signature slot. The brass takes your theme's accent.", "plain", { { "plain", "Plain" }, { "painted", "Painted" } }, { reload = true, under = "material", showWhen = function() return db().material ~= "matte" end, words = "brass frame leather fancy" })
	-- Part of the Style choice: tucked under it, there once Matte black
	-- is picked (even before the reload that brings the material in).
	choice(db, "grain", "Matte grain", "How much texture the Matte black surface has. Satin is flat, with no grain, like a matte speaker. Soft is a hint of texture.", "soft", { { "satin", "Satin" }, { "soft", "Soft" }, { "smooth", "Smooth" }, { "fine", "Fine" } }, {
		under = "material", showWhen = function() return db().material == "matte" end, words = "matte texture rough smooth satin flat finish",
		change = function() Stoa.UI.paintGrain() local c = Stoa.modules.Grimoire; if c and c.PaintMatte then c:PaintMatte() end end,
	})
	group = "Theme"
	local themes = {}
	for _, name in ipairs(Stoa.themeOrder) do
		themes[#themes + 1] = { name, name == "Class" and "Your class" or name, swatch = name }
	end
	choice(db, "theme", "Theme", "Bone is warm and class-tinted. Tide is all blues. Graphite is greyscale with one amber accent. Matte is black hardware with white print. Each class has its own, and Your class follows whoever you log in.", "Bone", themes, {
		list = true, words = "colour color palette class skin",
		change = function(_, v) Stoa:SetTheme(v) end,
	})
	local visions = {}
	for _, name in ipairs(Stoa.visionOrder) do visions[#visions + 1] = { name, Stoa.VISION_LABELS[name] } end
	choice(db, "vision", "Colour vision", "Swaps the warning, accent, mana and dispel colours for a set made for that kind of colour blindness, on top of any theme. Every state keeps its word or shape too. Modes other than Standard show names in the theme's text colour rather than class colours.", "Standard", visions, {
		list = true, cmd = "/stoa vision", words = "colour blind color blind cvd deuteranopia protanopia tritanopia accessibility",
		change = function(_, v) Stoa:SetVision(v) end,
	})
	choice(db, "classNames", "Class colours on names", "Names on party and raid cards, the target, nameplates, the threat list and meters in their class colour. As the theme sets follows the theme: Bone and the class themes colour names; Tide, Graphite, Matte and the colour vision modes keep them in the text colour. Always and Never override that.", "theme", {
		{ "theme", "As the theme sets" }, { "on", "Always" }, { "off", "Never" },
	}, { words = "class color colour names party raid nameplates", change = function() Stoa:Fire("STOA_THEME_CHANGED", Stoa.db.theme) end })
	choice(db, "textSize", "Text size", "Every STOA size together: words, numbers, tooltips and pages. Whatever you pick, the smallest text keeps at least 13 pixels on the screen, so a low UI scale never shrinks a caption past reading.", "standard", {
		{ "standard", "Standard" }, { "larger", "Larger" }, { "largest", "Largest" },
	}, { reload = true, words = "font size scale readable small big" })
	group = "Finish"
	toggle(db, "windowStone", "Depth in windows", "The body of each window sits a step below its header and footer, with a soft shadow at its edges. In Matte black the fine grain lies in it. Off leaves windows flat.", true, {
		words = "stone texture background grain recess shadow", change = function() Stoa.UI.showStone(Stoa.db.windowStone) end,
	})
	toggle(db, "coinArt", "Spell art in the Halo's coins", "Each coin shows its spell's icon faintly behind the letter, in colour while it runs or is ready.", true, { words = "icons" })
	toggle(db, "smoothBars", "Smooth health and power", "Health and power bars glide to a new value instead of jumping.", true, { words = "animation motion bars" })
	group = "Action bars"
	toggle(of("ActionBars"), "enabled", "Rounded action buttons", "Rounded-square icons with a hairline edge, dim sockets for empty slots.", true, { id = "actionBars", reload = true, words = "icons buttons bars" })
	toggle(console, "hideBarArt", "Hide action bar art", "Removes the gryphons and border so the bar sits on the console.", true, { reload = true, words = "gryphon dragons" })

	-- Console
	page = "console"
	group = "The console"
	-- First on its page: the console's size is what people come here for.
	choice(nil, "consoleShape", "Console size", "Full is the console along the bottom of the screen. Slim is one plain line a quarter of the height, with chat and the bars standing above it. None takes it away, and your health and mana show as two faint arcs around your character. Setup > Health and mana out of combat changes that.", "full", {
		{ "full", "Full" }, { "slim", "Slim line" }, { "none", "None" },
	}, {
		id = "consoleShape", reload = true, words = "console slim minimal full none hide bottom bar layout size",
		get = function()
			local c = module("Grimoire")
			if not c or c.enabled == false then return "none" end
			return c.slim and "slim" or "full"
		end,
		set = function(v)
			local c = module("Grimoire")
			if not c then return end
			c.enabled = v ~= "none"
			c.slim = v == "slim"
			-- Health and mana follow the console: on it while there is one,
			-- as the faint arcs when there is none (else they'd show nowhere,
			-- or twice once the console comes back).
			local halo = module("Halo")
			if halo then halo.restArcs = v == "none" end
		end,
	})
	toggle(console, "art", "Leather console", "Tooled leather with lines in your theme's accent. Off gives a plain dark panel.", true, {
		-- Leather's own choice: Matte black has its moulded console and no leather to switch.
		id = "consoleArt", reload = true, showWhen = function() return db().material ~= "matte" end,
	})
	toggle(console, "houseChat", "Hold chat in the console", "Chat sits on the console's left page and STOA's notes appear in chat.", true, { reload = true, words = "chat window" })
	toggle(console, "freeRight", "Leave the console's right side free", "Hides the Ready, Journey and Company pages together, leaving it bare right of the action bars for a window of your own, such as another addon's damage meter. The full console only.", false, { words = "ready journey company hide empty space meter right pages", change = function() local c = Stoa.modules.Grimoire; if c and c.FitPages then c:FitPages() end end })
	-- The right side's three slots: wells and page tiles (Window's slots
	-- row). The console's own captions change them too.
	add({
		kind = "slots", id = "slots", name = "The console's right side",
		desc = "Three slots, left to right. Pick a slot, then what it holds; choosing something another slot holds swaps the two. On the console itself, a click on a page's caption does the same. Meter 1 to 3 are the game's own meter windows (open more from the meter's menu, for healing or interrupts, say). Details 1 and 2 are Details' windows, when you run it. Empty leaves bare console for anything else. On a narrow screen the right-hand slots drop first. Usually Ready, Journey, Company. The full console only.",
		words = "slots modular right side meter details ready journey company empty arrange reputation cooldowns lockouts week pages",
	})
	toggle(console, "dividers", "Lines between the console's sections", "A faint line between chat, At a glance, the action bars and the Ready, Journey and Company pages.", true, { words = "separators dividers sections", change = function() local c = Stoa.modules.Grimoire; if c and c.FitPages then c:FitPages() end end })
	toggle(console, "daylight", "Light from the time of day", "The console's gold catches the sky's colour from above as the game's clock turns: rose at dawn, your own colour at midday, amber at dusk, moonlit blue at night, with a faint glass reflection on your portrait. Off keeps the gold as it is. /stoa daylight 23 previews an hour.", true, { words = "time of day daylight night dusk dawn", change = function() local c = Stoa.modules.Grimoire; if c and c.UpdateDaylight then c:UpdateDaylight() end end })
	toggle(console, "riding", "Travel line while riding", "On a mount or a flight, out of a fight, the console folds to a slim line with your speed, the zone, and how far the quest you follow is. Chat lifts above it and the action bars fade. A fight or getting off brings the full console back. Not on the Slim console. /stoa ride previews it.", true, { words = "mount mounted riding travel flight taxi speed", cmd = "/stoa ride", change = function() local c = Stoa.modules.Grimoire; if c and c.CheckRiding then c:CheckRiding() end end })
	toggle(console, "houseMenu", "Bags and menu in the console corner", "The bag slots and game menu sit in the console's bottom-right corner without their stone frames, quiet until you mouse over them.", true, { reload = true, words = "micro menu bag bar" })
	group = "At a glance"
	toggle(of("Tally"), "enabled", "At a glance, beside the chat", "Up to eight numbers you choose (stats, gear, gold, professions, other addons' feeds) to the right of chat on the console.", true, { id = "glanceOn", reload = true, words = "tally numbers data text broker titan" })
	toggle(of("Tally"), "follow", "At a glance follows where you are", "One set of lines out in the world, one in a dungeon and one in a raid (your role's stats first). Off keeps one set everywhere.", true, {
		words = "tally situation", change = refresh("Tally", "Refresh"),
	})
	add({ kind = "glance", id = "glanceLines", name = "Lines at a glance", desc = "Tick up to eight for each place. A pinned line shows in every place, at the top. Right-clicking At a glance on the console does the same.", scope = "Per spec", cmd = "/stoa glance", words = "tally numbers data text broker titan lines pin" })

	-- Combat
	page = "combat"
	group = "When a fight starts"
	local function refold() local c = Stoa.modules.Grimoire; if c and c.Refold then c:Refold() end end
	choice(db, "combatConsole", "In combat", "Fold the console to a thin line while the Halo rises around your character, keep the console open with the Halo as well, or keep the console open with no Halo for players who use other unit frames. Turning the Halo on or off takes effect after a reload.", "fold", {
		{ "fold", "Fold to the Halo" }, { "open", "Console and Halo" }, { "none", "Console only" },
	}, {
		reload = true, reloadWhen = function(was, now) return (was == "none") ~= (now == "none") end,
		words = "halo hide console fold unit frames",
		change = function(_, v) if halo() then halo().enabled = v ~= "none" end refold() end,
	})
	choice(db, "calm", "After a fight", "When the console folds: how long things must be calm before it opens again. Longer keeps quick pulls together.", "5", {
		{ "1", "1 s" }, { "3", "3 s" }, { "5", "5 s" }, { "8", "8 s" },
	}, { words = "delay timer out of combat" })
	choice(db, "countdownCombat", "On a pull countdown", "When a leader starts the game's pull countdown, the console folds and the Halo rises straight away, so you're settled before the pull. A cancelled countdown, or no fight a few seconds after it ends, opens the console again.", "raid", {
		{ "raid", "In raids" }, { "group", "Any group" }, { "off", "Never" },
	}, { words = "countdown pull timer dbm early halo" })
	toggle(db, "calmGroup", "Wait for your group", "In a group the console waits while anyone near you is still fighting (up to 20 seconds), so a chain of pulls stays one fight.", true)
	choice(db, "foldInstant", "How the console folds", "Slide eases the console away and back over a quarter of a second. Instantly swaps it at once, with no animation.", false, {
		{ false, "Slide" }, { true, "Instantly" },
	}, { words = "animation motion instant reduce" })
	toggle(halo, "hidePlayerFrame", "Hide Blizzard's player frame", "The medallion and the Halo show the same. Also hides Blizzard's cast bar.", true, { reload = true, words = "unit frame" })
	toggle(halo, "targetOfTarget", "Target of target", "Who your target is targeting: a name and a thin health line to the right of the target plaque. Says YOU when it is you. Click it to target them.", true, { reload = true, words = "tot assist aggro" })
	toggle(halo, "focusFrame", "Focus", "Your focus as a small block under the target of target, with or without a target. Off brings back Blizzard's focus frame. Move it with /stoa move.", true, { reload = true, words = "focus unit frame" })
	choice(halo, "arcStyle", "Arc style", "How the Halo's health and power arcs are drawn, shown small on each choice. Tube is a bright line on a wide faint band. Gauge is square: a straight bar inside a bracket. Line is the even half circle. Blade swells in the middle and thins to points. Visor bends as if on curved glass, with a gloss line inside. To see one without a fight, type /stoa combat.", "tube", { { "tube", "Tube" }, { "gauge", "Gauge" }, { "line", "Line" }, { "blade", "Blade" }, { "visor", "Visor" } }, { reload = true, words = "arc arcs shape style health mana ring", pictures = function(value)
		local file = Stoa.UI.MEDIA .. "Textures\\HaloArc" .. (value == "line" and "" or (value:gsub("^%l", string.upper)))
		return file .. "Left", file .. "Right"
	end })
	toggle(halo, "shield", "Your shield", "A silver shield whose fill drains as it soaks up damage: under the Halo's health number, and left of the medallion while the console is open.", true, { id = "haloShield", reload = true, words = "absorb power word shield bubble" })
	toggle(halo, "classMark", "Your class mark", "The buff your class keeps up, drawn like the shield and emptying as it runs out: Battle Shout (warrior), Slice and Dice (rogue), your seal (paladin), Lightning or Water Shield and Inner Fire by their charges (shaman, priest). Under the Halo's power number, and beside the shield left of the medallion.", true, { id = "haloClassMark", reload = true, words = "battle shout slice dice seal inner fire lightning water shield" })
	toggle(halo, "hideTargetFrame", "Hide Blizzard's target frame", "STOA shows your target beside the Halo.", true, { reload = true, words = "unit frame" })
	group = "Combat bar"
	toggle(of("CombatBar"), "enabled", "Combat bar under the Halo", "In combat, a compact row of your main bar's spells under the Halo, with their keys. Your keybinds keep working as before.", true, { id = "combatBar", reload = true, words = "action bar" })
	local rowChoices = { { "1", "1" }, { "2", "2" }, { "3", "3" } }
	local function relayout() Stoa:AfterCombat(function() Stoa.modules.CombatBar:Layout() end) end
	choice(of("CombatBar"), "rows", "Combat rows", "How many rows show under the Halo when you tank or deal damage: your main bar, then bottom-left, then bottom-right. Extra rows line up under the first and show only the buttons you've filled.", "2", rowChoices, { scope = "Per spec", words = "action bar buttons", change = relayout })
	choice(of("CombatBar"), "healerRows", "Combat rows when healing", "The same, for healing. One keeps the group frames close under your spells.", "1", rowChoices, { scope = "Per spec", change = relayout })
	toggle(of("ActionBars"), "combatHide", "Hand the bars to the Halo in combat", "With the combat bar on, the console's action bars step aside in combat and only the compact bar under the Halo shows. Your keybinds keep working.", true, {
		change = function(_, v) Stoa.modules.ActionBars:SetOption("combatHide", v) end,
	})
	group = "Mana"
	local function manaPlay()
		local h, c = Stoa.modules.Halo.manaPlay, Stoa.modules.Grimoire.manaPlay
		if h then h.Refresh() end
		if c then c.Refresh() end
	end
	-- The console's mana bar follows the Halo's switches.
	local function manaBoth(key)
		return function(_, v)
			local c = console()
			if c then c[key] = v end
			manaPlay()
		end
	end
	toggle(halo, "manaRule", "Five-second rule and regen ticks", "A small spark runs along your mana on the Halo and the console while spirit regeneration is paused after you spend mana, then pulses on each regeneration tick. Mana users only.", true, { id = "haloManaRule", classes = MANA, words = "5sr spirit regen", change = manaBoth("manaRule") })
	toggle(halo, "castCost", "Show what a cast will cost", "While you cast, the mana the spell will spend is shaded on the Halo's mana arc and the console's mana bar.", true, { id = "haloCastCost", classes = MANA, words = "mana cost", change = manaBoth("castCost") })
	toggle(halo, "formMana", "Mana while shapeshifted", "Druids in cat or bear form see their mana as a slim bar under the Halo's power number, and under the console's bar.", true, { id = "haloFormMana", classes = setOf("DRUID"), words = "druid cat bear", change = manaBoth("formMana") })
	toggle(console, "manaRule", "Five-second rule on the console", "The same spark on the console's mana bar.", true, { id = "consoleManaRule", classes = MANA, change = manaPlay })
	toggle(console, "castCost", "Cast cost on the console", "The same shade on the console's mana bar.", true, { id = "consoleCastCost", classes = MANA, change = manaPlay })
	toggle(console, "formMana", "Form mana on the console", "A druid's mana under the console's bar while shapeshifted.", true, { id = "consoleFormMana", classes = setOf("DRUID"), change = manaPlay })
	group = "Procs"
	local procs = of("Procs")
	local function takeOver() Stoa.modules.Procs:TakeOver(procs().takeOver and procs().art) end
	toggle(procs, "art", "Proc art beside the Halo", "When a proc fires, such as Clearcasting, Overpower or Shadow Trance, the game flashes glowing art around the middle of the screen. STOA shows that art either side of the Halo instead, where your eyes already are.", true, {
		id = "procArt", words = "spell activation overlay proc glow clearcasting", change = takeOver,
	})
	toggle(procs, "takeOver", "Turn the game's own proc art off", "So proc art never shows twice. Off puts the game's back in the middle of the screen.", true, { id = "procTakeOver", game = true, change = takeOver })
	toggle(procs, "glow", "Glow on the combat bar", "The game's proc glow round the combat bar button that holds the spell.", true, { id = "procGlow", change = refresh("Procs", "UpdateGlows") })
	toggle(procs, "sound", "Proc sound", "The game's own proc chime when STOA shows proc art.", true, { id = "procSound", words = "audio chime" })
	actions("procTry", "See it", "A sample proc shows either side of the Halo for a few seconds.", { { "Show a sample proc", command("procs", "test") } }, { cmd = "/stoa procs test" })
	group = "Cooldowns"
	toggle(of("Manager"), "enabled", "Read the game's Cooldown Manager", "Halo coins and the next-press outline ask the game's Cooldown Manager whether a spell is ready, which it knows in combat when the game hides it from addons. Spells it doesn't track keep STOA's own reading. Turns the game's Cooldown Manager setting on.", false, {
		id = "cdm", reload = true, game = true, words = "cooldown manager essential utility blizzard",
	})
	toggle(of("Manager"), "showBlizzard", "Keep the Cooldown Manager's rows on screen", "Off keeps the game's rows running but see-through, so the Halo is the one place cooldowns show.", false, { id = "cdmShow", change = refresh("Manager", "Quiet") })
	actions("cdmProbe", "Check it", "Lists the spells the Cooldown Manager tracks, and what STOA can read of each, in chat.", { { "What it tracks", command("cdm") } }, { cmd = "/stoa cdm" })
	group = "DoT kill marks"
	toggle(of("Lethal"), "marker", "DoT damage on the target bar", "The end of the target plaque's health bar shows, in dark stripes, how much your DoTs will still take off.", true, { id = "lethalMarker", needs = "Needs the DoesItDie addon", addonGlobal = "DoesItDie", words = "dot damage execute", change = refresh("Lethal", "Update") })
	choice(nil, "dotPlates", "DoT marks on nameplates", "Who marks each enemy's nameplate with the damage your DoTs still have to deal. STOA draws a dark striped stretch on the health bar and a small skull once they will kill. Does It Die draws its own marker. Choosing here sets Does It Die's \"Show on nameplates\" for you, so the two never both draw.", "stoa", {
		{ "stoa", "STOA" }, { "theirs", "Does It Die" }, { "off", "Neither" },
	}, {
		id = "lethalPlates", needs = "Needs the DoesItDie addon", addonGlobal = "DoesItDie", words = "dot damage nameplate execute doesitdie",
		get = function() local m = Stoa.modules.Lethal; return m and m.db and m:PlateOwner() or "stoa" end,
		set = function(v) local m = Stoa.modules.Lethal; if m and m.db then m:SetPlateOwner(v) end end,
	})
	toggle(of("Lethal"), "skull", "Skull when they'll kill it", "A skull slides over the target's portrait once your DoTs will finish it off.", true, { id = "lethalSkull", needs = "Needs the DoesItDie addon", addonGlobal = "DoesItDie", change = refresh("Lethal", "Update") })
	group = "Shadow priest"
	toggle(of("Shadow"), "followSequence", "Follow a cast sequence macro", "With a /castsequence macro on your bars, the next-press outline follows it: the macro lights up, and so does the spell button its next step will cast. Off goes back to STOA's own order (DoTs, Mind Blast, Death, Mind Flay).", true, { id = "shadowSequence", classes = setOf("PRIEST"), words = "castsequence macro rotation priority", change = refresh("Shadow", "UpdateNext") })
	group = "Your pet"
	local pet = of("Pet")
	local petRefresh = function() if Stoa.Pet and Stoa.Pet.enabled then Stoa.Pet:UpdateAll() end end
	toggle(pet, "plaque", "Pet plaque", "In a fight, a plaque like the target's at the Halo's upper left: your pet's mood, health, power, stance and what it's attacking. Under the tank watch when you heal.", true, { id = "petPlaque", classes = PETS, reload = true, words = "hunter warlock demon minion" })
	toggle(pet, "arc", "Pet health on the Halo", "A thin arc inside your own health with the pet's.", true, { id = "petArc", classes = PETS, reload = true, words = "hunter warlock" })
	toggle(pet, "row", "Pet row under the combat bar", "Your pet's buttons, smaller, under the combat bar in a fight. Right-click one to switch its autocast. Out of a fight the game's pet bar stays where it is, in STOA's dress.", true, { id = "petRow", classes = PETS, reload = true, words = "pet bar autocast stance" })
	toggle(pet, "coin", "Pet coin on the medallion", "Out of a fight, a small coin off the medallion with your pet's health as a ring and its mood under it. Click it to feed it food from your bags when it isn't happy; right-click targets it.", true, { id = "petCoin", classes = PETS, reload = true, words = "feed happiness hunter" })
	toggle(pet, "words", "Pet reminders", "CALL PET when it isn't out, PET DEAD when it needs reviving, FEED when it's unhappy, PET LOW and PET PASSIVE in a fight, GROWL ON in a group when you aren't the tank.", true, { id = "petWords", classes = PETS, words = "growl feed revive call", change = petRefresh })
	toggle(pet, "partyPets", "Pets under party cards", "When you heal in a party, a slim cell under each owner's card with the pet's health. Your click-casting works on it.", true, { id = "petParty", reload = true, words = "healer partypet" })

	-- Group
	page = "group"
	group = "Party and raid cards"
	toggle(party, "enabled", "Show STOA party cards", "Large beside the Halo when you heal, compact on the left otherwise.", true, { id = "partyOn", reload = true, words = "party frames unit" })
	toggle(party, "hideBlizzardParty", "Hide Blizzard's party frames", "The game's own party frames stay hidden while STOA's cards show. Off keeps both.", true, { reload = true })
	toggle(of("Raid"), "enabled", "Show STOA raid frames", "A grid of compact cards, one column per group.", true, { id = "raidOn", reload = true, words = "raid frames unit" })
	toggle(of("Raid"), "hideBlizzardRaid", "Hide Blizzard's raid frames", "The game's own raid frames stay hidden while STOA's grid shows. Off keeps both.", true, { reload = true })
	toggle(party, "quietCards", "Quiet group frames when not healing", "Tanking or dealing damage, party and raid cards show health and only the words you can act on: a debuff you can dispel, dead or offline. No buff words.", true, {
		words = "party raid frames unit", change = function() if Stoa.modules.Party.cards then Stoa.modules.Party:UpdateAll() end end,
	})
	actions("preview", "Show sample frames", "Fills the screen with sample cards so you can see and move them without a group. A fight ends the preview.", {
		{ "Party", function() Options.preview("party") end },
		{ "Raid of 10", function() Options.preview("raid10") end },
		{ "Raid of 20", function() Options.preview("raid") end },
		{ "Raid of 40", function() Options.preview("raid40") end },
		{ "Hide", function() Options.preview() end },
	}, { cmd = "/stoa test", words = "test preview dummy" })
	group = "Healing clicks"
	toggle(of("ClickCast"), "enabled", "Click-casting", "Mouse bindings on STOA's party and raid cards.", true, { id = "clickCast", reload = true, words = "clique mouseover healing" })
	choice(party, "clickGrid", "Click grid", "The table of what each click does, beside your cards when you heal. Folded keeps just its title until you hover a card or hold Shift; click the title to keep it open.", "fold", {
		{ "open", "Open" }, { "fold", "Folded" }, { "hidden", "Hidden" },
	}, { cmd = "/stoa grid", words = "click casting clique bindings", change = function() Stoa.modules.Party:SetGridMode(Stoa.modules.Party.db.clickGrid) end })
	button("clickBindings", "Click bindings", "Fifteen bindings for each role: five mouse buttons, plain, Shift and Ctrl.", "Open", function() Stoa.modules.ClickCast:TogglePage() end, { cmd = "/stoa clicks", words = "clique mouseover healing" })
	group = "Roles for this character"
	local roles = { { "AUTO", "Auto" } }
	for _, role in ipairs(Stoa.ROLES) do roles[#roles + 1] = { role, Stoa.ROLE_LABELS[role]:gsub(" DPS", "") } end
	for slot = 1, 2 do
		choice(function() return Stoa.char.roles end, "slot" .. slot, ("Spec %d plays as"):format(slot), "STOA picks the layout from this when you change spec. Auto takes your class's usual role for the spec.", "AUTO", roles, {
			scope = "This character", words = "role layout spec tank healer", change = function() Stoa:UpdateRole() end,
		})
	end
	group = "Tools"
	local groupRules = Stoa.Rules.options({ "GROUP", "RAID", "ALWAYS", "NEVER" })
	choice(of("Threat"), "show", "Threat meter", "Up to five people by threat on your target, or your tank's, to the left of the combat bar in a fight.", "GROUP", groupRules, { id = "threat", list = true, words = "aggro tank", change = rulesChanged })
	toggle(of("Threat"), "combatOnly", "Threat meter only in combat", "Hide the threat list out of combat.", true, { id = "threatCombat", change = rulesChanged })
	toggle(of("Buffs"), "enabled", "Group buff reminders", "Out of combat, the console's Ready page says who in range is missing a buff you can cast, such as FORTITUDE: 3 missing.", true, { id = "buffs", reload = true, words = "fortitude mark of the wild intellect" })
	toggle(of("Buffs"), "readyCheck", "Buff reminder at ready checks", "The same line on screen while a ready check runs.", true, { id = "buffsReady" })
	toggle(of("Kit"), "readyCheck", "Ready check dress and words", "The ready check prompt on STOA's panel, and READY, NOT READY or WAITING on each party card while it runs.", true, { id = "readyCheck", reload = true })
	toggle(of("Kit"), "bigNumber", "Big number for the pull timer", "/stoa pull 10 shows a large number in the middle of the screen when the game's own group countdown can't be used (you aren't a leader, or you are alone). Group chat gets 3, 2, 1 when you are grouped.", true, { cmd = "/stoa pull 10", words = "countdown pull timer" })
	toggle(of("Kit"), "kickCue", "KICK cue on the target", "The word KICK on the target plaque while it casts something you can interrupt.", true, { words = "interrupt", change = refresh("Kit", "UpdateKick") })
	group = "Logging"
	local logging = of("Logging")
	choice(logging, "remind", "Remind me to log", "Entering a dungeon or raid with combat logging off, a plaque says NOT LOGGING with a button to start it, for Warcraft Logs and similar sites. Starting also turns on the game's advanced logging.", "both", {
		{ "both", "Dungeons and raids" }, { "raid", "Raids only" }, { "off", "Never" },
	}, { id = "logRemind", words = "warcraft logs wcl combat log" })
	toggle(logging, "auto", "Start logging without asking", "Turns combat logging on as you enter, and says so.", false, { id = "logAuto", game = true })
	toggle(logging, "stopOnLeave", "Stop logging when you leave", "Only logging that STOA started stops when you leave the dungeon or raid.", true, { id = "logStop" })
	actions("logTry", "See it", "The NOT LOGGING plaque shows at the top of the screen.", { { "Show the reminder", command("log", "test") } }, { cmd = "/stoa log test" })

	-- Plates and tooltips
	page = "plates"
	group = "Nameplates"
	local restyle = function() Stoa.modules.Plates:Restyle() end
	toggle(plates, "enabled", "Restyle nameplates", "Flat bars coloured by what you can do: amber for enemies, pale gold for neutral, blue for friends, and grey only for tapped or dead.", true, { id = "platesOn", reload = true, words = "nameplates enemy health bars" })
	choice(plates, "style", "Nameplate style", "STOA: a rounded track. Bold: a heavy dark frame with the health value in the bar. Inline: name and health inside the bar. Brass: a brass edge with a level badge. Slim: a thin bar under the name. Matte: a thin line with no frame, as on the Matte target.", "stoa", {
		{ "stoa", "STOA" }, { "bold", "Bold" }, { "inline", "Inline" }, { "brass", "Brass" }, { "slim", "Slim" }, { "matte", "Matte" },
	}, { id = "plateStyle", change = restyle })
	choice(plates, "marker", "Mark your target's plate", "A soft glow behind it, a bone edge round it, or arrows either side.", "glow", {
		{ "edge", "Edge" }, { "arrows", "Arrows" }, { "glow", "Glow" },
	}, { id = "plateMarker", words = "target highlight", change = restyle })
	choice(plates, "fadeChoice", "Fade other plates", "While you have a target, plates you aren't targeting fade by this much.", "0", {
		{ "0", "None" }, { "25", "A little" }, { "45", "Half" }, { "65", "Mostly" },
	}, { id = "plateFade", change = function(_, v) plates().fade = tonumber(v) or 0; restyle() end })
	choice(plates, "scaleChoice", "Target plate size", "Makes your target's plate a little larger, using the game's own setting.", "100", {
		{ "100", "Same" }, { "115", "Larger" }, { "130", "Largest" },
	}, { id = "plateScale", game = true, words = "nameplateSelectedScale", change = function(_, v) plates().targetScale = tonumber(v) or 100; restyle() end })
	choice(plates, "damageText", "Damage numbers", "The size of the game's numbers over what you hit. The game draws them in the world, so they can't be moved, but smaller ones cover less of the Halo when an enemy stands on you.", "75", {
		{ "100", "Game size" }, { "75", "Smaller" }, { "55", "Small" },
	}, { id = "damageText", game = true, words = "floating combat text world text scale numbers", change = restyle })
	group = "Tooltips"
	toggle(tooltip, "enabled", "Tooltip cards", "Tooltips edged by rank or item quality, with whom a unit targets, what it casts, your threat, a player's item level and how many of an item you own.", true, { id = "tooltipOn", reload = true })
	choice(tooltip, "anchor", "Tooltip position", "Where tooltips for the world and STOA's frames appear.", "console", {
		{ "console", "Above the console" }, { "cursor", "At the mouse" },
	}, { cmd = "/stoa tooltip", words = "anchor cursor mouse" })
	toggle(tooltip, "unitDetails", "Tooltip details", "Target, casting, threat, DEAD, item level and mount lines on unit tooltips.", true)
	toggle(tooltip, "itemLevel", "Players' item level", "Asks the game for a player's gear when you mouse over them, out of combat. Remembered for the session.", true, { words = "ilvl inspect" })
	toggle(tooltip, "eachPrice", "Price of one in a stack", "Under the sell price of a stack, what one of them sells for.", true, { words = "sell price vendor each stack" })
	toggle(tooltip, "owned", "Owned counts on items", "How many of an item you have in your bags and bank.", true, { words = "bank count" })
	toggle(tooltip, "combatHide", "Hide unit tooltips in combat", "Hold Shift to see them anyway.", false, { id = "tooltipCombat" })
	toggle(tooltip, "gathering", "Herb and ore skill on nodes", "A herb or ore node's tooltip shows the skill it needs against yours, with TOO LOW when you are short. Herbs in every language; ore veins in English for now.", true, { words = "herbalism mining gather profession" })

	-- Windows
	page = "windows"
	group = "Dress"
	toggle(of("Windows"), "enabled", "Restyle Blizzard windows", "Quest, gossip, merchant, trainer, spellbook, talents, mail, auction house, group finder, friends and guild windows on STOA's dark panels with light text.", true, {
		id = "windowsOn", reload = true, words = "skin blizzard frames spellbook talents mail auction friends guild",
		change = function(_, v) local m = module("MoreWindows"); if m then m.enabled = v end end,
	})
	toggle(of("MoreWindows"), "enabled", "Restyle more windows", "Spellbook, talents, world map border, mail, auction house, group finder, friends and guild on the same dark panels.", true, { id = "moreWindows", reload = true, words = "skin blizzard frames" })
	toggle(of("Bags"), "enabled", "Restyle bags", "Rounded slots, a coloured edge by quality plus a corner mark for epic and above, item level on gear, free slots, your money in letters and a Sort button.", true, { id = "bags", reload = true, words = "inventory" })
	choice(of("Bags"), "bagMode", "Bag layout", "One combined bag, or a window for each bag. You can still switch from the bag's own menu.", "combined", {
		{ "combined", "One bag" }, { "separate", "Separate" },
	}, { game = true, words = "combined bags inventory", change = function() Stoa.modules.Bags.db.appliedMode = nil; Stoa.modules.Bags:ApplyMode() end })
	choice(of("Bags"), "bagView", "One bag's view", "Sections sorts your items into new, consumables, trade goods, quest, equipment, other, junk and empty slots. Grid keeps the game's one grid in bag order. A word in the bag's header switches too.", "sections", {
		{ "sections", "Sections" }, { "grid", "Grid" },
	}, { words = "bag sections categories sort grid", change = function() Stoa.modules.Bags:SetView(Stoa.modules.Bags.db.bagView) end })
	toggle(of("Bags"), "reagentsInBag", "Reagents in the bag", "The reagent bag opens with the combined bag as its bottom section, its slots in the same ten columns, instead of a window of its own.", true, { words = "reagent bag herb pouch profession", change = function() Stoa.modules.Bags:DockReagents() end })
	toggle(of("Character"), "enabled", "Restyle the character sheet", "Item level and quality edges on every slot, WORN and BROKEN on gear that needs repair, an average item level line. The inspect window gets item levels too.", true, { id = "character", reload = true, words = "paper doll gear durability" })
	toggle(of("Character"), "layout", "STOA's character layout", "A wider sheet: each item's name in its quality colour and its item level beside its slot, the weapons named under the model, the stats on a quiet column, the tabs as words in the header and your durability in a footer. Off keeps Blizzard's layout, dressed.", true, { id = "characterLayout", reload = true, words = "paper doll gear item names stats" })
	toggle(of("Spellbook"), "layout", "STOA's spellbook", "The spellbook without its parchment, opening as one scrolling list of your spells with rank, cost, cast time and next rank (a word switches to Blizzard's pages), and a To train word by the search that opens the training page beside the book.", true, { id = "spellbook", reload = true, words = "spells book ranks trainer training" })
	toggle(of("Spellbook"), "talents", "STOA's talents", "The talent trees without their painted spec art: each tree's name and points spent as words, quiet rules between the trees, Primary and Secondary as words, and a line by Apply while changes are waiting.", true, { id = "talents", reload = true, words = "talent trees spec points loadout apply" })
	toggle(of("Planner"), "enabled", "Talent planner", "A panel beside your talents to plan a build point by point, for levels you haven't reached yet. Planned talents show the level you take them at and your next point glows. Several named plans per class, shared as text, and Make game loadout hands the plan to the game's own loadouts. STOA never spends a point for you.", true, { reload = true, words = "talent planner plan build loadout respec order level" })
	toggle(of("Top"), "enabled", "Restyle the top of the screen", "Buffs as cropped icons with quiet timers, the quest tracker in STOA's type, and the minimap's zone header on a dark panel.", true, { id = "top", reload = true, words = "buffs auras objective tracker" })
	toggle(of("Top"), "buffList", "Buffs as a list", "Each buff's name and time left beside its icon, easy to scan before a pull. Works best with the buff frame set to one column in Edit Mode.", false, { words = "auras", change = refresh("Top", "RefreshBuffList") })
	toggle(of("Top"), "trackerFocus", "Fold quest list in combat", "In a fight the quest tracker folds to its header and comes back after. Hover the header to open it.", true, { words = "objective tracker fade collapse hide combat focus", change = refresh("Top", "FocusTracker") })
	toggle(of("Swing"), "enabled", "Restyle the swing timer", "Blizzard's swing timer as a flat bar in a rounded dark track: pale gold for the main hand, blue for the off hand. Place it in Edit Mode.", true, { id = "swing", reload = true, words = "auto attack melee" })
	toggle(of("XPBar"), "enabled", "Restyle the experience bar", "The experience and reputation bar as a thin flat bar in a rounded dark track: experience in the accent like the medallion, rested in blue, reputation by standing. Place it in Edit Mode.", true, { id = "xpbar", reload = true, words = "xp exp rested reputation honor status tracking bar" })
	toggle(of("XPBar"), "questXP", "Show finished quests on the bar", "A paler gold stretch runs on from your experience to where handing in your finished quests takes you. Hover the bar for the count and the experience.", true, { words = "xp exp quest turn in hand in complete", change = function() Stoa.modules.XPBar:UpdateQuests() end })
	toggle(of("XPBar"), "combatFade", "Fade the experience bar in combat", "The experience bar fades away in a fight, like the console, and comes back after.", true, { words = "xp exp hide combat", change = function(_, v) if not v then Stoa.modules.XPBar:Fade(false) end end })
	toggle(of("Meters"), "enabled", "Restyle the damage meter", "Blizzard's damage and healing meters as words over the world with no panel: faint bone bars, your own bar in the accent.", true, { id = "meters", reload = true, words = "dps meter hps details recount" })
	toggle(of("Meters"), "place", "Meters in the top-left corner", "Every meter window sits side by side in one strip flush with the top-left corner. Off leaves them where Edit Mode put them.", true, {
		id = "metersPlace", change = function(_, v) if v then Stoa.modules.Meters:Place() end end,
	})
	group = "Moving"
	toggle(of("WindowMover"), "enabled", "Shift and drag to move windows", "Hold Shift and drag a window by its title or edge. Each keeps its spot when it opens again; Shift and right-click puts one back.", true, { id = "windowMover", reload = true, words = "move frames drag position" })
	button("moveFrames", "Move STOA's frames", "Unlock the Halo, plaques, cards and bars to drag them where you like, with a grid and snapping. Each role keeps its own spots. Arrow keys nudge, right-click puts one back.", "Unlock", function()
		if Options.close then Options.close() end
		Stoa:ToggleMovers()
	end, { scope = "Per role", cmd = "/stoa unlock", words = "layout edit mode position" })
	actions("resetPlaces", "Put things back", "Every Blizzard window back where the game puts it, or STOA's frames back in their usual places.", {
		{ "Put every window back", command("windows", "reset") },
		{ "Reset STOA's frames", command("reset"), confirm = true },
	}, { cmd = "/stoa windows reset, /stoa reset", words = "reset positions default" })

	-- Map and chat
	page = "mapchat"
	group = "Minimap"
	toggle(of("Minimap"), "enabled", "Style the minimap", "Theme-coloured edge, serif zone name, wheel to zoom.", true, { id = "minimap", reload = true })
	choice(of("Minimap"), "shape", "Minimap shape", "A square with rounded corners like STOA's windows, which shows a little more of the world, or the round map in rings.", "square", {
		{ "square", "Rounded square" }, { "round", "Round" },
	}, { reload = true })
	toggle(of("Tray"), "enabled", "Gather addon icons", "Other addons' minimap buttons move into one small button below the map's corner; click it for a tray of their icons.", true, { id = "tray", reload = true, words = "minimap buttons libdbicon" })
	add({
		kind = "checks", id = "trayKeep", name = "Icons kept on the map", reload = true, cmd = "/stoa tray leave",
		desc = "Ticked icons stay on the minimap; the rest gather in the tray. These are the addon icons STOA has found.",
		empty = "No addon icons found yet.", words = "minimap buttons tray",
		items = function()
			local tray = Stoa.modules.Tray
			local set = {}
			for _, name in pairs(tray and tray.taken or {}) do set[name] = true end
			for name in pairs(tray and tray.db.leave or {}) do set[name] = true end
			return sortedKeys(set)
		end,
		checked = function(name) return Stoa.modules.Tray.db.leave[name] and true or false end,
		toggle = function(name, on) Stoa.modules.Tray.db.leave[name] = on or nil end,
		state = function()
			local out = {}
			for name in pairs(Stoa.modules.Tray and Stoa.modules.Tray.db.leave or {}) do out[#out + 1] = name end
			table.sort(out)
			return table.concat(out, ",")
		end,
	})
	group = "World map"
	local map = of("Map")
	toggle(map, "fade", "Fade the map while moving", "The world map goes see-through while you move, so you can walk with it open.", true, { id = "mapFade", game = true, words = "opacity transparent", change = refresh("Map", "Refresh") })
	toggle(map, "levels", "Zone levels on the map", "A zone's level range under the map title and on the minimap's zone tooltip.", true, { id = "mapLevels", change = refresh("Map", "Refresh") })
	toggle(of("Timers"), "flights", "Flight timer", "Where you're flying and how long is left, in a slim bar near the top, with times on the flight map.", true, { cmd = "/stoa timers", words = "taxi flight path" })
	toggle(of("Timers"), "mirror", "Breath and fatigue in STOA's bar", "Breath, fatigue and feign death timers in the same slim bar, worded, in place of Blizzard's.", true, { words = "underwater" })
	group = "Chat"
	local look = of("ChatLook")
	toggle(nil, "chatLook", "STOA's chat look", "More space between lines, the chat's buttons in one quiet column down its left side, and the typing box as a dark strip under the messages. Search finds the three on their own.", true, {
		id = "chatLook", reload = true, words = "chat spacing buttons column typing edit box",
		get = function() local c = look(); return c and c.air and c.rail and c.input and true or false end,
		set = function(v)
			local c = look()
			if not c then return end
			c.air, c.rail, c.input = v, v, v
			local m = Stoa.modules.ChatLook
			if m and m.Air then m:Air() end
		end,
	})
	toggle(look, "times", "Times on chat lines", "Each line starts with a quiet time and a thin rule, so messages line up in a column. Skipped when the game's own timestamps are on.", true, { words = "timestamps clock" })
	toggle(look, "air", "More space between chat lines", "A little air between lines, so a busy chat reads in rows rather than a block.", true, { words = "spacing", change = refresh("ChatLook", "Air") })
	toggle(look, "rail", "Chat buttons in a column", "Friends, channels, voice and the chat menu in one quiet column down the chat's left side.", true, { reload = true })
	toggle(look, "input", "Quiet typing box", "The box you type in becomes a dark strip under the messages with a fine rule above.", true, { reload = true, words = "edit box" })
	toggle(of("Chat"), "links", "Clickable web addresses", "Web addresses in chat become links; a click shows the address in a box to copy.", true, { reload = true, words = "url" })
	toggle(of("Chat"), "copy", "Copy chat", "A quiet copy mark on the chat, or Shift-click a chat tab, shows the last 200 lines to copy.", true, { id = "chatCopy", reload = true, cmd = "/stoa copychat" })
	toggle(of("Chat"), "history", "Keep chat across reloads", "The main chat window's last 100 lines come back after a reload or login, dimmed.", true)

	-- Levelling and loot
	page = "journey"
	group = "On the console"
	toggle(of("Kit"), "xpRate", "Experience pace", "Experience an hour and time to level under the Journey bar, worked out over the last half hour. Hidden at the highest level.", true, { cmd = "/stoa xp", words = "xp per hour leveling levelling", change = refresh("Kit", "UpdateConsole") })
	toggle(of("Kit"), "questLine", "Nearest quest", "When you are not in a group, one line under Journey with the progress of the watched quest nearest you.", true, { change = refresh("Kit", "UpdateConsole") })
	toggle(of("Trainer"), "enabled", "New spells at your trainer", "A line under Journey counting the spells and ranks your trainer would teach you now, and a note when a new level brings some.", true, { id = "trainer", reload = true, cmd = "/stoa trainer", words = "training class trainer" })
	add({
		kind = "words", id = "trainerSkip", name = "Spells you skip", scope = "This character", cmd = "/stoa trainer",
		desc = "STOA stops counting these at the trainer, every rank. Right-click a spell on the Training page to skip it, or type its name here.",
		placeholder = "Spell name, then Enter", words = "training ignore hide",
		items = function() return sortedKeys(Stoa.modules.Trainer:Skips()) end,
		add = function(text)
			local name = Stoa.Spells.name(text) or text
			Stoa.modules.Trainer:Skips()[name] = true
			Stoa.modules.Trainer:Refresh()
			return true
		end,
		remove = function(name)
			Stoa.modules.Trainer:Skips()[name] = nil
			Stoa.modules.Trainer:Refresh()
		end,
	})
	group = "Items"
	toggle(of("Uprank"), "enabled", "Upgrade spell ranks on your bars", "When you learn a new rank, bar slots holding an older rank get the new one, out of combat. Macros are left alone.", true, { id = "uprank", reload = true, words = "rank" })
	actions("uprankNow", "Ranks", "Puts your best ranks on your bars now.", { { "Upgrade my bars now", command("uprank") } }, { cmd = "/stoa uprank" })
	toggle(of("QuestReward"), "enabled", "Mark the best quest reward", "With a choice of rewards, UPGRADE marks the one that beats what you wear, or VALUE the one that sells for most.", true, { id = "reward", reload = true, words = "pawn upgrade" })
	toggle(of("QuestItems"), "enabled", "Quest item buttons", "A small row of buttons for items your quests ask you to use, beside the Halo. Untracking a quest hides its item.", true, { id = "questItems", reload = true })
	toggle(of("SelfBuffs"), "enabled", "Your buffs at hand", "Out of combat, small icons left of the Halo for your own long buffs (Inner Fire, an aura and a blessing, an armor) when one is missing or about to run out. Click one to cast it.", true, { id = "selfBuffs", reload = true, words = "buff reminder inner fire aura blessing armor" })
	toggle(of("Emergency"), "enabled", "Emergency item", "A button for your healthstone, best healing potion or bandage. It stays in view in combat and lights with LOW under 40% health.", true, { id = "emergency", reload = true, words = "potion healthstone bandage" })
	group = "Loot"
	toggle(of("Loot"), "enabled", "Loot feed and gold an hour", "A short fading list of what you loot above the chat, plus gold an hour and loot value for At a glance.", true, { id = "lootFeed", reload = true, cmd = "/stoa loot", words = "gold per hour" })
	choice(of("Loot"), "show", "Show the loot feed", "When the list above the chat shows. Off by default: the chat already lists your loot.", "NEVER", Stoa.Rules.options({ "WORLD", "ALWAYS", "SOLO", "GROUP", "NEVER" }), { id = "lootShow", list = true, change = rulesChanged })
	toggle(of("FullBags"), "enabled", "Help when your bags are full", "When the game says your inventory is full, a small card names the two or three least valuable stacks you carry, by what a vendor pays, and a click on one destroys it to make room. Grey junk first, then what you marked as junk, then plain white food and drink (health or mana back and nothing more); never food with a buff, elixirs, scrolls, quest items, spell reagents, gear, trade goods, tools or what you keep in Restock. Anything that isn't grey asks for a second click. While you loot it also says when what's left isn't worth the room. STOA never destroys anything by itself. /stoa fullbags previews the card.", true, { id = "fullBags", reload = true, cmd = "/stoa fullbags", words = "inventory full bags destroy delete junk room loot" })
	toggle(of("Rolls"), "enabled", "Loot rolls up off the bars, with who chose what", "The Need, Greed and Pass cards stack from their own spot (Loot rolls in unlock mode) instead of over your bars. Under each card you see who has chosen what; once your card goes, a small card shows every choice, the rolls and the winner for a few seconds. /stoa rolls shows a sample.", true, { id = "lootRolls", reload = true, cmd = "/stoa rolls", words = "need greed pass roll group loot winner" })
	actions("lootReset", "Totals", "Gold an hour and loot value count from the last time you started them.", { { "Start the totals again", command("loot", "reset") } }, { cmd = "/stoa loot reset" })

	-- Comforts
	page = "comforts"
	group = "Everyday"
	local comforts = of("Comforts")
	toggle(comforts, "fastLoot", "Faster loot", "With auto loot on, everything lands in your bags the moment the loot window would open. Hold Shift to see the window.", true, { words = "auto loot" })
	toggle(comforts, "farCamera", "Pull the camera further out", "Raises the camera's maximum zoom distance.", true, { game = true, words = "zoom distance max camera", change = refresh("Comforts", "Camera") })
	toggle(of("Whispers"), "enabled", "Whisper card", "A whisper brings up a small card above the chat tabs with who it's from and the start of what they said, so it isn't lost in the chat. Click to answer, right-click to put it away. /stoa whisper shows a sample.", true, { id = "whisperCard", cmd = "/stoa whisper", words = "whisper tell message friend toast notify" })
	toggle(comforts, "skipGossip", "Skip one-option chats", "When a character has no quests and only one thing to say, STOA picks it for you. Hold Shift to stop.", true, { words = "gossip npc" })
	toggle(comforts, "dismountCast", "Get off your mount to cast", "Casting a spell while mounted, flying too, gets you off first instead of saying you can't.", true, { game = true, words = "dismount mount cast", change = refresh("Comforts", "DismountCast") })
	toggle(comforts, "dismountTaxi", "Get off at the flight master", "Opening a flight master's map while mounted gets you off so you can pick a flight. Hold Shift to stay on.", true, { words = "dismount mount flight taxi gryphon", change = refresh("Comforts", "Taxi") })
	toggle(comforts, "keepTracking", "Keep my tracking on", "The game turns off Find Minerals, Find Herbs and other tracking when you log in or die. STOA turns the last one you chose back on.", true, { words = "find minerals herbs ore mining herbalism treasure humanoids beasts minimap", change = refresh("Comforts", "RestoreTracking") })
	toggle(comforts, "questGlow", "Interact icon up close", "Shows the game's small icon over the object or NPC you can use once you're within reach and facing it, so quest objects are easy to spot as you walk up. Switching it off puts the game's settings back.", false, { game = true, words = "quest item sparkle glow outline object interact world", change = refresh("Comforts", "QuestGlow") })
	toggle(comforts, "sparkle", "Sparkle on what's up close", "With the interact icon on, the herb, ore, chest or quest object it marks also gets a soft gold glow with twinkling stars, so it's easy to spot. NPCs don't sparkle.", true, { words = "sparkle glow herb ore mining node chest quest object", change = refresh("Comforts", "Sparkle") })
	toggle(comforts, "acceptQuests", "Accept quests", "Picks up offered quests, except low-level (grey) ones. Hold Shift to read one first.", false)
	toggle(comforts, "turnInQuests", "Hand in quests", "Hands in finished quests. A quest with a choice of reward always waits for you. Hold Shift to stop.", false)
	toggle(comforts, "skipCinematics", "Skip cinematics", "Cancels cinematics and movies as they start. Hold Shift to watch.", false, { words = "movies cutscenes" })
	toggle(comforts, "quietErrors", "Quiet errors in combat", "Hides the red \"Not enough mana\" and \"Out of range\" text while you fight; it comes back after.", false, { words = "red text" })
	toggle(nil, "chatNoise", "Hide chat noise", "Other people's duel results and lines about them getting drunk stay out of chat, unless they name you. Search finds the two on their own.", true, {
		id = "chatNoise", words = "duel drunk tipsy spam filter",
		get = function() local c = comforts(); return c and c.quietDuels and c.quietDrunk and true or false end,
		set = function(v) local c = comforts(); if c then c.quietDuels, c.quietDrunk = v, v end end,
	})
	toggle(comforts, "quietDuels", "Hide other people's duel results", "Lines like \"X has defeated Y in a duel\" stay out of chat, unless they name you.", true)
	toggle(comforts, "quietDrunk", "Hide drunken chatter", "Lines about other people getting tipsy or drunk stay out of chat.", true)
	choice(nil, "duels", "Decline duels", "Turns down duel requests as they come: from nobody, from anyone you don't know (friends and guildmates still get through), or from everyone. Hold Shift to see one.", "strangers", {
		{ "never", "Never" }, { "strangers", "Strangers" }, { "all", "Everyone" },
	}, {
		id = "duels", words = "duel decline stranger",
		get = function()
			local c, p = comforts(), module("Social")
			if c and c.declineDuels then return "all" end
			return p and p.declineStrangerDuels and "strangers" or "never"
		end,
		set = function(v)
			local c, p = comforts(), module("Social")
			if c then c.declineDuels = v == "all" end
			if p then p.declineStrangerDuels = v ~= "never" end
		end,
	})
	toggle(comforts, "releaseInPvP", "Release in battlegrounds", "Releases your spirit when you die in a battleground, unless you have a soulstone. Hold Shift to stay.", false, { words = "pvp" })
	toggle(comforts, "acceptRes", "Accept resurrections", "Takes a resurrection as soon as it's offered, unless whoever cast it is still fighting. Hold Shift to wait.", false, { words = "rez resurrect" })
	group = "Merchants"
	local merchant = of("Merchant")
	toggle(merchant, "sellJunk", "Sell grey junk", "At a merchant, greys and anything you marked as junk are sold at once, with what they fetched noted in chat. Hold Shift while opening the merchant to keep them.", true, { words = "vendor" })
	toggle(merchant, "autoRepair", "Repair gear", "At a merchant who repairs, everything you wear is mended at once, with the cost noted in chat. Hold Shift while opening the merchant to skip it.", true, { words = "vendor durability" })
	toggle(merchant, "useGuildFunds", "Use guild funds when allowed", "Repairs draw on the guild bank first when your rank may, and your own gold otherwise.", true)
	add({
		kind = "words", id = "junkList", name = "Always sell", cmd = "/stoa junk add",
		desc = "Items sold with your grey junk, on every character. Shift-click an item in your bags while the box below is open, or type its name or number. The Junk button on your bags marks them by clicking.",
		placeholder = "Item, then Enter", links = true, words = "junk vendor sell list",
		items = function() return sortedKeys(Stoa.db.junk, itemLabel) end,
		add = function(text)
			local id = itemId(text)
			if not id then return false, "STOA doesn't know that item yet. Shift-click it in your bags instead." end
			Stoa.Items.setJunk(id, true)
			return true
		end,
		remove = function(id) Stoa.Items.setJunk(id, false) end,
	})
	toggle(of("Restock"), "enabled", "Restock at vendors", "Any vendor that sells something on this character's list below tops it back up to the number you chose. Things bought with tokens or honour are left alone. Hold Shift as you open the vendor to skip it.", true, { id = "restockOn", words = "reagents ammo arrows candles poisons food water buy" })
	add({
		kind = "words", id = "restockList", name = "Keep in your bags", cmd = "/stoa restock add", scope = "This character",
		desc = "An item and how many, such as an item link then 20. Shift-click an item in your bags while the box is open, then type the number.",
		placeholder = "Item and count, then Enter", links = true, words = "restock reagents ammo arrows candles poisons food water",
		items = function()
			local out = {}
			for id, n in pairs(Stoa.Restock.list()) do out[#out + 1] = { id, ("%d %s"):format(n, Stoa.Restock.name(id)) } end
			table.sort(out, function(a, b) return a[2]:lower() < b[2]:lower() end)
			return out
		end,
		add = function(text)
			local item, number = text:match("^(.-)%s+(%d+)%s*$")
			local id = itemId(item or text)
			if not id then return false, "STOA doesn't know that item yet. Shift-click it in your bags instead." end
			Stoa.Restock.set(id, tonumber(number) or 20)
			return true
		end,
		remove = function(id) Stoa.Restock.set(id, nil) end,
	})
	group = "Mail"
	local mail = of("Mail")
	toggle(mail, "takeGold", "Take gold button", "Beside the mailbox's Open All: takes the money from every letter and leaves the items. Cash on delivery and letters from game masters are always left for you.", true, { reload = true, words = "postal mailbox money collect" })
	toggle(mail, "summary", "Say what came out", "After Open All, one line in chat with the money and items it took.", true, { words = "postal mailbox" })
	toggle(mail, "toList", "Your characters in To", "A small arrow inside the name box lists your own characters on this realm and the people you mailed lately.", true, { reload = true, words = "postal alts send recipient" })
	group = "Away"
	local away = of("Away")
	toggle(away, "enabled", "Away screen", "When you go away out of a fight, the interface steps aside: your name, rest and time away on a quiet band, and any whispers that come meanwhile. Move, or press Back, to return.", true, { id = "awayOn", words = "afk idle screensaver" })
	toggle(away, "spin", "Turn the camera", "The camera circles your character slowly while you're away.", true, { words = "afk rotate" })
	toggle(away, "inInstances", "In dungeons and raids too", "Off, the away screen waits for the open world.", false, { words = "afk instance" })
	button("awayNow", "See it now", "Shows the away screen without going away. Back or /stoa away closes it.", "Show", command("away"), { cmd = "/stoa away", words = "afk preview" })
	group = "Your session"
	local session = of("Session")
	toggle(session, "onLogout", "Recap when you log out", "While the game counts down to logging out, a card shows what this session brought: time played, levels, experience an hour, gold, quests, deaths and your best find. It never holds up the logout.", true, { words = "session summary recap logout stats" })
	toggle(session, "onAway", "Recap on the away screen", "When no whispers have come, the away screen shows a short version of this session's numbers where they would be.", false, { words = "session summary recap afk" })
	button("recapNow", "See this session", "Shows the recap card now.", "Show", command("recap"), { cmd = "/stoa recap", words = "session summary recap" })
	group = "Dungeon companion"
	local companion = of("Companion")
	toggle(companion, "enabled", "Dungeon companion", "Inside a five-player dungeon, out of a fight: the bosses (ticked off as they fall) and your quests for it. /stoa companion and part of a dungeon's name previews it anywhere. The quest list folds to its header while it shows; hover the header to open it.", true, { words = "dungeon instance boss quests preview" , change = function() Stoa.modules.Companion:Refresh() end })
	choice(companion, "view", "How it shows", "A card where the quest list sits, or one slim line over the console with the bosses as dots and the upgrades on hover. The card's minus and a click on the line switch too.", "card", {
		{ "card", "Card" }, { "line", "One line" },
	}, { words = "dungeon companion compact", change = function() Stoa.modules.Companion:Refresh() end })
	group = "People"
	local social = of("Social")
	toggle(social, "acceptFriendInvites", "Accept friend and guild invites", "A party invite from a friend, Battle.net friend or guildmate is taken as it comes, and noted in chat.", true, { words = "party group" })
	toggle(social, "declineStrangerInvites", "Decline stranger invites", "A party invite from anyone you don't know is turned down quietly, and noted in chat.", false)
	toggle(social, "declineStrangerGuildInvites", "Decline stranger guild invites", "A guild invite from anyone you don't know is turned down quietly, and noted in chat.", true)
	group = "Auto-invite"
	local invite = of("AutoInvite")
	toggle(invite, "enabled", "Invite on a keyword", "Friends and guildmates who whisper one of the words below get an invite.", true, { id = "inviteOn", words = "auto invite inv" })
	add({
		kind = "words", id = "keywords", name = "Invite words", cmd = "/stoa keywords",
		desc = "Matched as the whole whisper, in any case.", placeholder = "A word, then Enter", words = "auto invite keyword inv",
		items = inviteWords,
		add = function(text)
			local list = inviteWords()
			for word in text:gmatch("[^,%s]+") do list[#list + 1] = { word:lower(), word:lower() } end
			setInviteWords(list)
			return true
		end,
		remove = function(word)
			local list = {}
			for _, item in ipairs(inviteWords()) do
				if item[1] ~= word then list[#list + 1] = item end
			end
			setInviteWords(list)
		end,
	})
	toggle(invite, "strangersToo", "Invite strangers too", "Anyone who whispers a word, not just friends and guildmates.", false)
	toggle(invite, "convertToRaid", "Make a raid when full", "When the fifth person joins and more are waiting, the party is turned into a raid so the rest can come in.", true)
	toggle(invite, "guildChat", "Words work in guild chat", "A guildmate saying just the word in guild chat gets an invite.", false)
	local notes = of("Notes")
	toggle(notes, "enabled", "Player notes", "Write a line about someone you played with, good or bad: right-click them and choose STOA note, or type /stoa note and their name. The note comes back on their tooltip, their party card and their whispers, and every character of yours shares it. Off, the notes are kept but not shown.", true, { id = "notesOn", cmd = "/stoa note", words = "player note remember people blacklist ninja friend reputation", reload = true })
	toggle(notes, "chatMark", "Mark noted players in chat", "A noted player's diamond at the start of what they say in the world's channels (General, Trade, looking for group), in say and yell, and in whispers to you. Guild, party and raid chat stay plain. Left alone when another addon runs your chat.", true, { words = "player note chat mark diamond name" })
	toggle(notes, "joinLine", "Say when someone noted joins", "One chat line, only you see it, when a player you've written a note about joins your group.", true, { words = "player note group party join warn" })
	button("people", "People", "Everyone you've written a note about, to search, edit or remove.", "Open", function() Stoa.Notes:ShowPeople() end, { cmd = "/stoa people", words = "player notes list people" })
	button("company", "Company", "Friends and guildmates who are online: click to whisper, Shift-click to invite.", "Open", function() Stoa.modules.Roster:Toggle() end, { cmd = "/stoa friends", words = "friends roster guild" })

	-- Setup
	page = "setup"
	group = "Start"
	button("welcome", "Welcome page", "The step-by-step setup: where to start, your specs, the look, what a fight does, how much of STOA, and other addons.", "Open", function() Stoa.Welcome:Show() end, { cmd = "/stoa welcome", words = "wizard first time" })
	-- The wizard's two answers. Each sets several settings at once.
	local function mixTo(shape, around)
		local welcome = Stoa.Welcome
		local nowShape, nowAround = welcome:Mix()
		welcome:ApplyMix(shape or nowShape, around or nowAround)
		welcome:FollowLayout()
	end
	choice(nil, "preset", "Layout: Full, Slim or None", "Full is the console along the bottom of the screen. Slim makes it one line, with chat and the bars standing above it. None takes it away: two faint arcs for health and mana, and the Halo in a fight. Choosing one sets several settings at once; Your own mix below changes the parts one by one.", "full", {
		{ "full", "Full" }, { "slim", "Slim" }, { "none", "None" },
	}, {
		id = "preset", reload = true, cmd = "/stoa preset", words = "preset minimal slim full none layout starting set how much",
		get = function() return (Stoa.Welcome:Mix()) end,
		set = function(v) mixTo(v, nil) end,
	})
	choice(nil, "around", "Layout: everything around it", "Standard shows the target and party as panels, with tooltip details, the quest line and At a glance. Quiet makes the target and party thin strips that fade out of combat, and puts away tooltip details, the quest line, At a glance and the Cooldown Manager rows.", "standard", {
		{ "standard", "Standard" }, { "quiet", "Quiet" },
	}, {
		id = "around", reload = true, words = "preset quiet minimal less layout starting set how much",
		get = function() return select(2, Stoa.Welcome:Mix()) end,
		set = function(v) mixTo(nil, v) end,
	})
	actions("otherSets", "Other starting sets", "Classic feel keeps STOA's console, Halo and frames, and leaves the game's windows, bags, tooltips and nameplates as Blizzard draws them. Same as Designer is Full as its designer plays it, with the designer's Edit Mode layout. Type /reload after choosing one.", {
		{ "Classic feel", function() Stoa.Welcome:ApplyPreset("classic") end, "Classic feel set. Type /reload to finish." },
		{ "Same as Designer", function() if Stoa.Welcome:ApplyPreset("taer") then Stoa.Welcome:FollowLayout() end end, "Same as Designer set. Type /reload to finish." },
	}, { words = "preset classic designer" })
	-- One place to mix the parts the presets above set together.
	group = "Your own mix"
	choice(nil, "partyShape", "Party when not healing", "Cards are solid panels in a column at the left of the screen. Strips are thin lines beside the Halo: a name, health, and a word when you can act, resting faint while everyone is fine. Healers always get cards under the Halo.", "cards", {
		{ "cards", "Cards" }, { "strips", "Strips" },
	}, {
		id = "partyShape", words = "party frames cards strips slim minimal layout",
		get = function() local m = module("Party"); return m and m.strips and "strips" or "cards" end,
		set = function(v) local m = module("Party"); if m then m.strips = v == "strips" end end,
		change = function() local m = Stoa.modules.Party; if m.cards then Stoa:AfterCombat(function() m:Layout() end) end end,
	})
	choice(nil, "targetShape", "Target", "Plaque is a solid panel with a portrait beside the Halo. Words only drops the panel: a name, a bar and a small portrait over the world, level with the Halo.", "plaque", {
		{ "plaque", "Plaque" }, { "words", "Words only" },
	}, {
		id = "targetShape", reload = true, words = "target frame plaque strip panel slim minimal layout",
		get = function() local m = module("Halo"); return m and m.targetStrip and "words" or "plaque" end,
		set = function(v) local m = module("Halo"); if m then m.targetStrip = v == "words" end end,
	})
	-- Tucked under the target's shape. Each look keeps its own answer:
	-- Matte starts Compact, Leather starts Full.
	choice(nil, "targetSize", "Target size", "Compact is a small block: name, type and a slim health line. Full is the larger plaque with the target's portrait. Matte starts Compact and Leather starts Full; each look remembers its own.", "compact", {
		{ "compact", "Compact" }, { "full", "Full" },
	}, {
		id = "targetSize", reload = true, under = "targetShape", words = "target frame plaque slab size big small portrait matte leather compact",
		showWhen = function() local m = module("Halo"); return not (m and m.targetStrip) end,
		get = function()
			local m = module("Halo")
			if db().material == "matte" then return m and m.targetFull and "full" or "compact" end
			return m and m.targetCompact and "compact" or "full"
		end,
		set = function(v)
			local m = module("Halo")
			if not m then return end
			if db().material == "matte" then m.targetFull = v == "full" else m.targetCompact = v == "compact" end
		end,
	})
	choice(nil, "restFrames", "Target and party out of combat", "Faint rests them at half strength until a fight starts or the mouse is over them.", "full", {
		{ "full", "Full strength" }, { "faint", "Faint" },
	}, {
		id = "restFrames", reload = true, words = "fade dim transparent minimal target party rest layout",
		get = function() local m = module("Halo"); return m and m.restFade and "faint" or "full" end,
		set = function(v)
			local on = v == "faint"
			local h, p = module("Halo"), module("Party")
			if h then h.restFade = on end
			if p then p.restFade = on end
		end,
	})
	choice(nil, "restArcs", "Health and mana out of combat", "Faint arcs keeps your health and mana around your character as two faint arcs while the Halo rests. For playing without the console, which shows them otherwise.", "console", {
		{ "console", "On the console" }, { "arcs", "Faint arcs" },
	}, {
		id = "restArcsShape", reload = true, words = "health mana arcs minimal rest layout",
		get = function() local m = module("Halo"); return m and m.restArcs and "arcs" or "console" end,
		set = function(v) local m = module("Halo"); if m then m.restArcs = v == "arcs" end end,
	})
	group = "Keep and share"
	button("setups", "Saved setups", "Load the setup from another of your characters.", "Choose", function(owner) Stoa.Setups:Menu(owner) end, { cmd = "/stoa setups", words = "profile alt" })
	button("backup", "Backup", "All of STOA's settings as one line of text to keep safe, and a place to paste one back.", "Open", function() Stoa.Backup:Show() end, { cmd = "/stoa backup", words = "profile export import string" })
	button("shareLayout", "Share layout", "A shorter line with where your frames sit and the look, to post for others. Paste one on the backup page to use it.", "Copy", function() Stoa.Backup:ShowLayout() end, { cmd = "/stoa layout", words = "export import string profile" })
	group = "Your characters"
	button("alts", "Characters", "Every character you've played with STOA: level, where they are, gold, rest, raid lockouts and item level. Search finds an item in any character's bags or bank, and clicking a character shows their gear. /stoa alts forget <name> drops one.", "Open", command("alts"), { cmd = "/stoa alts", words = "alts altoholic gold lockouts saved instances rested search find item where gear model" })
	toggle(of("Alts"), "tooltipCounts", "Count items on every character", "Item tooltips add how many your other characters carry and keep in the bank, from when each last played.", true, { words = "alts bags bank tooltip owned" })
	toggle(of("GearSets"), "enabled", "Gear for each spec", "Put on an equipment set in a spec and STOA puts it back on whenever you change to that spec, after any fight. A set assigned to a spec in the equipment manager always wins.", true, { id = "gearSetsOn", scope = "This character", words = "equipment manager dual spec swap outfit" })
	group = "Keys"
	button("bind", "Bind keys", "Hover any action, pet or stance button and press a key, mouse button or wheel, with any modifier. Backspace clears; Esc finishes and keeps the keys.", "Start", command("bind"), { cmd = "/stoa bind", words = "keybind hotkey keybinding kb" })
	group = "The game's own settings"
	button("restore", "Put the game's settings back", "Puts back the game settings STOA changed (far camera, map fade, target nameplate size, combined bags, proc art), as they were before STOA. One you've changed yourself since stays as you set it.", "Put back", command("restore"), { cmd = "/stoa restore", words = "cvar ledger reset camera" })
	group = "Other addons"
	button("addons", "Other addons", "Choose again which of STOA's parts step aside for other addons you run, such as bags or nameplates.", "Choose again", command("addons"), { cmd = "/stoa addons", words = "conflicts elvui bagnon companion" })
	local fitter = Stoa.modules.Grimoire
	if fitter and fitter.CanFitEllesmere and fitter:CanFitEllesmere() then
		button("fitEllesmere", "Fit EllesmereUI to the console", "Places EllesmereUI's chat on the console's left page and its damage meter top left, by writing those two positions into EllesmereUI's own settings, then reloads. STOA keeps the old positions. The chat keeps its size: if it covers At a glance, drag its corner narrower.", "Fit and reload", command("fit"), { cmd = "/stoa fit", words = "ellesmere eui chat dock damage meter position" })
		button("unfitEllesmere", "Undo the EllesmereUI fit", "Puts EllesmereUI's chat and damage meter back where they were before the fit, then reloads.", "Undo and reload", command("fit undo"), { cmd = "/stoa fit undo", words = "ellesmere eui chat dock damage meter undo" })
	end
	-- One row for each part another addon is doing too (Core/Conflicts.lua),
	-- so a choice made or missed at login can be found again.
	local Conflicts = Stoa.Conflicts
	for _, found in ipairs(Conflicts and Conflicts:Found() or {}) do
		local rule = found.rule
		if not rule.suite then
			local them = Conflicts.names(found.loaded)
			choice(nil, "addons_" .. rule.key, rule.job:gsub("^%l", string.upper), ("%s and STOA both look after %s. Keep theirs and STOA's part steps aside. Use STOA's turns %s off. Until you choose, STOA's part waits."):format(them, rule.job, them), "ask", {
				{ "ask", "Not chosen" }, { "theirs", "Keep theirs" }, { "ours", "Use STOA's" },
			}, {
				id = "addons_" .. rule.key, everyday = true, reload = true, words = "conflicts other addons daylight " .. them:lower(),
				get = function() return found.picked or (Conflicts:Saved(found) == "theirs" and "theirs" or "ask") end,
				set = function(v) Conflicts:Pick(found, v) end,
			})
		end
	end
	button("looks", "STOA's look for other addons", "Questie's tracker, Bagnon's bags, Details' meters and RestedXP's guide in STOA's dress.", "Choose", command("looks"), { cmd = "/stoa looks", words = "questie bagnon details restedxp rxp guide skin" })
	group = "Help"
	toggle(of("Tips"), "enabled", "Tips", "When there are no small jobs, the console's Ready column shows a few words about something STOA does that's easy to miss; hover for the whole tip, click to open its setting, right-click once you've got it. The away screen shows them in turn. /stoa tips shows the ones you've marked again.", true, { words = "tips hints did you know help tutorial", change = function() Stoa.modules.Tips.current = nil; local c = Stoa.modules.Grimoire; if c and c.UpdateJobs then c:UpdateJobs() end end })
	button("report", "Report a problem", "Your setup and any errors STOA caught this session, ready to copy and send.", "Open", function() Stoa.Report:Show() end, { cmd = "/stoa report", words = "bug error lua" })
	button("gallery", "Gallery", "Every surface, size and state word STOA uses, side by side, to check that the look holds together.", "Open", function() Stoa.Gallery:Show() end, { cmd = "/stoa gallery", words = "design look style rulebook" })
	button("check", "Launch check", "Checks every spell, game function and frame STOA relies on, after a game update. Results in chat.", "Run", command("check"), { cmd = "/stoa check", words = "update broken" })
	button("safe", "Safe mode", "Turns off every skin that reaches into Blizzard's frames and reloads. Turn them back on here afterwards.", "Turn on", function() Stoa.commands.safe() end, { confirm = true, cmd = "/stoa safe", words = "broken errors disable" })

	-- Each part stands for a setting above: the same switch under its plain
	-- name. They aren't in the list, so search and the counts see one of each.
	Options.partList = {}
	for _, part in ipairs(PARTS) do
		local base = Options.byId[part[1]]
		if base then
			-- Each says where the rest of its settings are.
			local where = ""
			for _, info in ipairs(Options.PAGES) do
				if info[1] == base.page then where = (" Its finer settings are on the %s page."):format(info[2]) end
			end
			Options.partList[#Options.partList + 1] = setmetatable({
				id = "part_" .. base.id, startId = base.id, page = "parts", group = part[2], name = part[3], desc = part[4] .. where,
				more = false, quiet = false,
			}, { __index = base })
		end
	end

	Options.snapshot()
end

function Options.parts() return Options.partList or {} end

-- What the reload-only settings held as the UI loaded.
function Options.snapshot()
	for _, entry in ipairs(Options.list) do
		if entry.reload then
			Options.start[entry.id] = entry.state and entry.state() or value(entry)
		end
	end
end

-- The preview: one kind at a time, or none.
function Options.preview(kind)
	if Stoa.previewing then Stoa:TogglePreview("") end
	if kind then Stoa:TogglePreview(kind) end
end

-- Search: every word typed must be in the name, text, group, page, command
-- or the other words a setting lists.
function Options.search(query)
	local words = {}
	for word in (query or ""):lower():gmatch("%S+") do words[#words + 1] = word end
	if #words == 0 then return nil end
	local found = {}
	for _, entry in ipairs(Options.list) do
		local hay = entry.hay
		if not hay then
			local pageName = ""
			for _, p in ipairs(Options.PAGES) do if p[1] == entry.page then pageName = p[2] end end
			hay = table.concat({ entry.name or "", entry.desc or "", entry.group or "", pageName, entry.cmd or "", entry.words or "" }, " "):lower()
			entry.hay = hay
		end
		local all = true
		for _, word in ipairs(words) do
			if not hay:find(word, 1, true) then all = false break end
		end
		if all then found[#found + 1] = entry end
	end
	return found
end

-- A page's settings: the everyday ones, and those under More.
-- False for a setting that only matters under another's choice (showWhen).
function Options.shown(entry)
	return not entry.showWhen or entry.showWhen() and true or false
end

function Options.onPage(id)
	local out, more = {}, {}
	for _, entry in ipairs(Options.list) do
		if entry.page == id and not entry.quiet then
			local list = entry.more and more or out
			list[#list + 1] = entry
		end
	end
	return out, more
end

-- True for a switch or choice that isn't as Stoa comes and can be put back.
function Options.isChanged(entry)
	if (entry.kind ~= "toggle" and entry.kind ~= "choice") or entry.default == nil or entry.set then return false end
	if not (entry.tbl and entry.tbl()) then return false end
	return value(entry) ~= entry.default
end

function Options.changed()
	local out = {}
	for _, entry in ipairs(Options.list) do
		if Options.isChanged(entry) then out[#out + 1] = entry end
	end
	return out
end

-- /stoa keywords <words>: the invite words, as before the window.
Stoa.commands.keywords = function(rest)
	local entry = Options.byId.keywords
	rest = strtrim(rest or "")
	if rest == "" then
		local words = {}
		for _, item in ipairs(inviteWords()) do words[#words + 1] = item[1] end
		Stoa:Print("Invite words: " .. table.concat(words, ", ") .. ". /stoa keywords <words> to change them.")
		return
	end
	module("AutoInvite").keywords = rest
	Stoa:Print("Invite words: " .. rest .. ".")
	if entry then Stoa:Fire("STOA_OPTION_CHANGED", entry.id) end
end

Stoa:On("STOA_READY", function() xpcall(build, Stoa.catch) end)
