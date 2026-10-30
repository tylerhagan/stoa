-- Stoa: every setting, described once. The settings window (Config/Window.lua)
-- draws its pages, search and notes from this list.
--
-- A setting: page, group, id, name, desc, kind, and how to read and write it.
-- Kinds: toggle, choice (a row of choices, or a list when there are many),
-- words (chips you add and take away), checks (a list of ticks), glance (At a
-- glance's lines), button and actions (things to do now). Flags: reload
-- (takes effect after /reload), game (changes one of the game's own
-- settings), scope (where it is kept, when not account-wide), cmd (the
-- /stoa words that do the same), words (other words search should find),
-- needs (an addon it needs).
local _, ns = ...
local Stoa = ns.Stoa

local Options = { list = {}, byId = {}, start = {} }
Stoa.Options = Options

Options.PAGES = {
	{ "look", "Look", "Theme, colour and the few painted pieces. These change everything else, so they come first." },
	{ "console", "Console", "The leather console along the bottom of the screen and what it holds." },
	{ "combat", "Combat", "What happens when a fight starts: the Halo, the combat bar and what they show." },
	{ "group", "Group", "Party and raid cards, healing clicks, and tools for tanks and leaders." },
	{ "plates", "Plates & tooltips", "Nameplates over the world, and the cards that appear under the mouse." },
	{ "windows", "Windows", "Blizzard's own windows in Stoa's dress, and moving them." },
	{ "mapchat", "Map & chat", "The minimap, the world map and the chat." },
	{ "journey", "Levelling & loot", "Help along the way: pace, quests, trainers, rewards and loot." },
	{ "comforts", "Comforts", "Small things Stoa does for you. Hold Shift to stop any of them in the moment." },
	{ "setup", "Setup", "Your setup as a whole: start again, keep a copy, put the game back, report a problem." },
}

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
	local was, now = Options.start[entry.id], entry.state and entry.state() or value(entry)
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
	entry.page, entry.group = entry.page or page, entry.group or group
	entry.id = entry.id or entry.key
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
	group = "Theme"
	local themes = {}
	for _, name in ipairs(Stoa.themeOrder) do
		themes[#themes + 1] = { name, name == "Class" and "Your class" or name, swatch = name }
	end
	choice(db, "theme", "Theme", "Bone is warm and class-tinted. Tide is all blues. Graphite is greyscale with one amber accent. Each class has its own, and Your class follows whoever you log in.", "Bone", themes, {
		list = true, words = "colour color palette class skin",
		change = function(_, v) Stoa:SetTheme(v) end,
	})
	local visions = {}
	for _, name in ipairs(Stoa.visionOrder) do visions[#visions + 1] = { name, Stoa.VISION_LABELS[name] } end
	choice(db, "vision", "Colour vision", "Swaps the warning, accent, mana and dispel colours for a set made for that kind of colour blindness, on top of any theme. Every state keeps its word or shape too. Modes other than Standard show names in the theme's text colour rather than class colours.", "Standard", visions, {
		list = true, cmd = "/stoa vision", words = "colour blind color blind cvd deuteranopia protanopia tritanopia accessibility",
		change = function(_, v) Stoa:SetVision(v) end,
	})
	group = "Painted pieces"
	choice(db, "ornament", "Ornament", "Plain keeps Stoa's fine lines. Painted puts leather and brass frames on the one-of-a-kind pieces: the minimap, the portrait coins on your target and tank plaques, and the Halo's signature slot. The brass takes your theme's accent.", "plain", { { "plain", "Plain" }, { "painted", "Painted" } }, { reload = true, words = "brass frame leather fancy" })
	toggle(db, "windowStone", "Stone behind windows", "Faint rings and grain in the theme's colour behind windows and Stoa's own pages. The console keeps its leather.", true, {
		words = "texture background granite", change = function() Stoa.UI.showStone(Stoa.db.windowStone) end,
	})
	toggle(db, "coinArt", "Spell art in the Halo's coins", "Each coin shows its spell's icon faintly behind the letter, in colour while it runs or is ready.", true, { words = "icons" })
	toggle(db, "smoothBars", "Smooth health and power", "Health and power bars glide to a new value instead of jumping.", true, { words = "animation motion bars" })
	group = "Action bars"
	toggle(of("ActionBars"), "enabled", "Rounded action buttons", "Rounded-square icons with a hairline edge, dim sockets for empty slots.", true, { id = "actionBars", reload = true, words = "icons buttons bars" })
	toggle(console, "hideBarArt", "Hide action bar art", "Removes the gryphons and border so the bar sits on the console.", true, { reload = true, words = "gryphon dragons" })

	-- Console
	page = "console"
	group = "The console"
	toggle(console, "enabled", "Show the console", "The leather console along the bottom of the screen.", true, { id = "consoleOn", reload = true })
	toggle(console, "art", "Leather console", "Tooled leather with lines in your theme's accent. Off gives a plain dark panel.", true, { id = "consoleArt", reload = true })
	toggle(console, "houseChat", "Hold chat in the console", "Chat sits on the console's left page and Stoa's notes appear in chat.", true, { reload = true, words = "chat window" })
	toggle(console, "houseMenu", "Bags and menu in the console corner", "The bag slots and game menu sit in the console's bottom-right corner, quiet until you mouse over them.", true, { reload = true, words = "micro menu bag bar" })
	toggle(of("ActionBars"), "hoverTray", "Extra rows on mouseover", "Out of combat only your main bar shows in the console; the other rows come up while you mouse over the bars. Off shows every row out of combat.", false, {
		words = "action bars hide", change = function(_, v) Stoa.modules.ActionBars:SetOption("hoverTray", v) end,
	})
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
	choice(db, "calm", "After a fight", "When the console folds: how long things must be calm before it opens again. Longer keeps quick pulls together.", "3", {
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
	toggle(halo, "hideTargetFrame", "Hide Blizzard's target frame", "Stoa shows your target beside the Halo.", true, { reload = true, words = "unit frame" })
	group = "Combat bar"
	toggle(of("CombatBar"), "enabled", "Combat bar under the Halo", "In combat, a compact row of your main bar's spells under the Halo, with their keys. Your keybinds keep working as before.", true, { id = "combatBar", reload = true, words = "action bar" })
	local rowChoices = { { "1", "1" }, { "2", "2" }, { "3", "3" } }
	local function relayout() Stoa:AfterCombat(function() Stoa.modules.CombatBar:Layout() end) end
	choice(of("CombatBar"), "rows", "Combat rows", "How many rows show under the Halo when you tank or deal damage: your main bar, then bottom-left, then bottom-right. Each extra row is a step smaller and shows only the buttons you've filled.", "2", rowChoices, { scope = "Per spec", words = "action bar buttons", change = relayout })
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
	toggle(halo, "manaRule", "Five-second rule and regen ticks", "A small spark runs along your mana on the Halo while spirit regeneration is paused after you spend mana, then pulses on each regeneration tick. Mana users only.", true, { id = "haloManaRule", words = "5sr spirit regen", change = manaPlay })
	toggle(halo, "castCost", "Show what a cast will cost", "While you cast, the mana the spell will spend is shaded on the Halo's mana arc.", true, { id = "haloCastCost", words = "mana cost", change = manaPlay })
	toggle(halo, "formMana", "Mana while shapeshifted", "Druids in cat or bear form see their mana as a slim bar under the Halo's power number.", true, { id = "haloFormMana", words = "druid cat bear", change = manaPlay })
	toggle(console, "manaRule", "Five-second rule on the console", "The same spark on the console's mana bar.", true, { id = "consoleManaRule", change = manaPlay })
	toggle(console, "castCost", "Cast cost on the console", "The same shade on the console's mana bar.", true, { id = "consoleCastCost", change = manaPlay })
	toggle(console, "formMana", "Form mana on the console", "A druid's mana under the console's bar while shapeshifted.", true, { id = "consoleFormMana", change = manaPlay })
	group = "Procs"
	local procs = of("Procs")
	local function takeOver() Stoa.modules.Procs:TakeOver(procs().takeOver and procs().art) end
	toggle(procs, "art", "Proc art beside the Halo", "When a proc fires, such as Clearcasting, Overpower or Shadow Trance, the game flashes glowing art around the middle of the screen. Stoa shows that art either side of the Halo instead, where your eyes already are.", true, {
		id = "procArt", words = "spell activation overlay proc glow clearcasting", change = takeOver,
	})
	toggle(procs, "takeOver", "Turn the game's own proc art off", "So proc art never shows twice. Off puts the game's back in the middle of the screen.", true, { id = "procTakeOver", game = true, change = takeOver })
	toggle(procs, "glow", "Glow on the combat bar", "The game's proc glow round the combat bar button that holds the spell.", true, { id = "procGlow", change = refresh("Procs", "UpdateGlows") })
	toggle(procs, "sound", "Proc sound", "The game's own proc chime when Stoa shows proc art.", true, { id = "procSound", words = "audio chime" })
	actions("procTry", "See it", "A sample proc shows either side of the Halo for a few seconds.", { { "Show a sample proc", command("procs", "test") } }, { cmd = "/stoa procs test" })
	group = "Cooldowns"
	toggle(of("Manager"), "enabled", "Read the game's Cooldown Manager", "Halo coins and the next-press outline ask the game's Cooldown Manager whether a spell is ready, which it knows in combat when the game hides it from addons. Spells it doesn't track keep Stoa's own reading. Turns the game's Cooldown Manager setting on.", false, {
		id = "cdm", reload = true, game = true, words = "cooldown manager essential utility blizzard",
	})
	toggle(of("Manager"), "showBlizzard", "Keep the Cooldown Manager's rows on screen", "Off keeps the game's rows running but see-through, so the Halo is the one place cooldowns show.", false, { id = "cdmShow", change = refresh("Manager", "Quiet") })
	actions("cdmProbe", "Check it", "Lists the spells the Cooldown Manager tracks, and what Stoa can read of each, in chat.", { { "What it tracks", command("cdm") } }, { cmd = "/stoa cdm" })
	group = "Will my DoTs kill it"
	toggle(of("Lethal"), "marker", "DoT damage on the target bar", "The end of the target plaque's health bar shows, in bone, how much your DoTs will still take off.", true, { id = "lethalMarker", needs = "Needs the DoesItDie addon", words = "dot damage execute", change = refresh("Lethal", "Update") })
	toggle(of("Lethal"), "skull", "Skull when they'll kill it", "A skull slides over the target's portrait once your DoTs will finish it off.", true, { id = "lethalSkull", needs = "Needs the DoesItDie addon", change = refresh("Lethal", "Update") })

	-- Group
	page = "group"
	group = "Party and raid cards"
	toggle(party, "enabled", "Show Stoa party cards", "Large beside the Halo when you heal, compact on the left otherwise.", true, { id = "partyOn", reload = true, words = "party frames unit" })
	toggle(party, "hideBlizzardParty", "Hide Blizzard's party frames", "", true, { reload = true })
	toggle(of("Raid"), "enabled", "Show Stoa raid frames", "A grid of compact cards, one column per group.", true, { id = "raidOn", reload = true, words = "raid frames unit" })
	toggle(of("Raid"), "hideBlizzardRaid", "Hide Blizzard's raid frames", "", true, { reload = true })
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
	toggle(of("ClickCast"), "enabled", "Click-casting", "Mouse bindings on Stoa's party and raid cards.", true, { id = "clickCast", reload = true, words = "clique mouseover healing" })
	choice(party, "clickGrid", "Click grid", "The table of what each click does, beside your cards when you heal. Folded keeps just its title until you hover a card or hold Shift; click the title to keep it open.", "fold", {
		{ "open", "Open" }, { "fold", "Folded" }, { "hidden", "Hidden" },
	}, { cmd = "/stoa grid", words = "click casting clique bindings", change = function() Stoa.modules.Party:SetGridMode(Stoa.modules.Party.db.clickGrid) end })
	button("clickBindings", "Click bindings", "Fifteen bindings for each role: five mouse buttons, plain, Shift and Ctrl.", "Open", function() Stoa.modules.ClickCast:TogglePage() end, { cmd = "/stoa clicks", words = "clique mouseover healing" })
	group = "Roles for this character"
	local roles = { { "AUTO", "Auto" } }
	for _, role in ipairs(Stoa.ROLES) do roles[#roles + 1] = { role, Stoa.ROLE_LABELS[role]:gsub(" DPS", "") } end
	for slot = 1, 2 do
		choice(function() return Stoa.char.roles end, "slot" .. slot, ("Spec %d plays as"):format(slot), "Stoa picks the layout from this when you change spec. Auto takes your class's usual role for the spec.", "AUTO", roles, {
			scope = "This character", words = "role layout spec tank healer", change = function() Stoa:UpdateRole() end,
		})
	end
	group = "Tools"
	local groupRules = Stoa.Rules.options({ "GROUP", "RAID", "ALWAYS", "NEVER" })
	choice(of("Threat"), "show", "Threat meter", "Up to five people by threat on your target, or your tank's, under the damage meters.", "GROUP", groupRules, { id = "threat", list = true, words = "aggro tank", change = rulesChanged })
	toggle(of("Threat"), "combatOnly", "Threat meter only in combat", "Hide the threat list out of combat.", true, { id = "threatCombat", change = rulesChanged })
	choice(of("Markers"), "show", "Raid marker strip", "Eight markers and clear for tanks and leaders. Click marks your target; Shift-click places a world marker.", "GROUP", groupRules, { id = "markers", list = true, words = "skull icons target markers", change = rulesChanged })
	toggle(of("Buffs"), "enabled", "Group buff reminders", "Out of combat, the console's Ready page says who in range is missing a buff you can cast, such as FORTITUDE · 3 missing.", true, { id = "buffs", reload = true, words = "fortitude mark of the wild intellect" })
	toggle(of("Buffs"), "readyCheck", "Buff reminder at ready checks", "The same line on screen while a ready check runs.", true, { id = "buffsReady" })
	toggle(of("Kit"), "readyCheck", "Ready check dress and words", "The ready check prompt on Stoa's panel, and READY, NOT READY or WAITING on each party card while it runs.", true, { id = "readyCheck", reload = true })
	toggle(of("Kit"), "bigNumber", "Big number for the pull timer", "/stoa pull 10 shows a large number in the middle of the screen when the game's own group countdown can't be used (you aren't a leader, or you are alone). Group chat gets 3, 2, 1 when you are grouped.", true, { cmd = "/stoa pull 10", words = "countdown pull timer" })
	toggle(of("Kit"), "kickCue", "KICK cue on the target", "The word KICK on the target plaque while it casts something you can interrupt.", true, { words = "interrupt", change = refresh("Kit", "UpdateKick") })
	group = "Logging"
	local logging = of("Logging")
	choice(logging, "remind", "Remind me to log", "Entering a dungeon or raid with combat logging off, a plaque says NOT LOGGING with a button to start it, for Warcraft Logs and similar sites. Starting also turns on the game's advanced logging.", "both", {
		{ "both", "Dungeons and raids" }, { "raid", "Raids only" }, { "off", "Never" },
	}, { id = "logRemind", words = "warcraft logs wcl combat log" })
	toggle(logging, "auto", "Start logging without asking", "Turns combat logging on as you enter, and says so.", false, { id = "logAuto", game = true })
	toggle(logging, "stopOnLeave", "Stop logging when you leave", "Only logging that Stoa started stops when you leave the dungeon or raid.", true, { id = "logStop" })
	actions("logTry", "See it", "The NOT LOGGING plaque shows at the top of the screen.", { { "Show the reminder", command("log", "test") } }, { cmd = "/stoa log test" })

	-- Plates and tooltips
	page = "plates"
	group = "Nameplates"
	local restyle = function() Stoa.modules.Plates:Restyle() end
	toggle(plates, "enabled", "Restyle nameplates", "Flat bars coloured by what you can do: amber for enemies, pale gold for neutral, blue for friends, and grey only for tapped or dead.", true, { id = "platesOn", reload = true, words = "nameplates enemy health bars" })
	choice(plates, "style", "Nameplate style", "Stoa: a rounded track. Bold: a heavy dark frame with the health value in the bar. Inline: name and health inside the bar. Brass: a brass edge with a level badge. Slim: a thin bar under the name.", "stoa", {
		{ "stoa", "Stoa" }, { "bold", "Bold" }, { "inline", "Inline" }, { "brass", "Brass" }, { "slim", "Slim" },
	}, { id = "plateStyle", change = restyle })
	choice(plates, "marker", "Mark your target's plate", "A bone edge round it, arrows either side, or a soft glow behind it.", "edge", {
		{ "edge", "Edge" }, { "arrows", "Arrows" }, { "glow", "Glow" },
	}, { id = "plateMarker", words = "target highlight", change = restyle })
	choice(plates, "fadeChoice", "Fade other plates", "While you have a target, plates you aren't targeting fade by this much.", "0", {
		{ "0", "None" }, { "25", "A little" }, { "45", "Half" }, { "65", "Mostly" },
	}, { id = "plateFade", change = function(_, v) plates().fade = tonumber(v) or 0; restyle() end })
	choice(plates, "scaleChoice", "Target plate size", "Makes your target's plate a little larger, using the game's own setting.", "100", {
		{ "100", "Same" }, { "115", "Larger" }, { "130", "Largest" },
	}, { id = "plateScale", game = true, words = "nameplateSelectedScale", change = function(_, v) plates().targetScale = tonumber(v) or 100; restyle() end })
	group = "Tooltips"
	toggle(tooltip, "enabled", "Tooltip cards", "Tooltips edged by rank or item quality, with whom a unit targets, what it casts, your threat, a player's item level and how many of an item you own.", true, { id = "tooltipOn", reload = true })
	choice(tooltip, "anchor", "Tooltip position", "Where tooltips for the world and Stoa's frames appear.", "console", {
		{ "console", "Above the console" }, { "cursor", "At the mouse" },
	}, { cmd = "/stoa tooltip", words = "anchor cursor mouse" })
	toggle(tooltip, "unitDetails", "Tooltip details", "Target, casting, threat, DEAD, item level and mount lines on unit tooltips.", true)
	toggle(tooltip, "itemLevel", "Players' item level", "Asks the game for a player's gear when you mouse over them, out of combat. Remembered for the session.", true, { words = "ilvl inspect" })
	toggle(tooltip, "owned", "Owned counts on items", "How many of an item you have in your bags and bank.", true, { words = "bank count" })
	toggle(tooltip, "combatHide", "Hide unit tooltips in combat", "Hold Shift to see them anyway.", false, { id = "tooltipCombat" })
	toggle(tooltip, "gathering", "Herb and ore skill on nodes", "A herb or ore node's tooltip shows the skill it needs against yours, with TOO LOW when you are short. English node names for now.", true, { words = "herbalism mining gather profession" })

	-- Windows
	page = "windows"
	group = "Dress"
	toggle(of("Windows"), "enabled", "Restyle Blizzard windows", "Quest, gossip, merchant, trainer and bag windows on Stoa's dark panels with light text.", true, { id = "windowsOn", reload = true, words = "skin blizzard frames" })
	toggle(of("MoreWindows"), "enabled", "Restyle more windows", "Spellbook, talents, world map border, mail, auction house, group finder, friends and guild on the same dark panels.", true, { id = "moreWindows", reload = true, words = "skin blizzard frames" })
	toggle(of("Bags"), "enabled", "Restyle bags", "Rounded slots, a coloured edge by quality plus a corner mark for epic and above, item level on gear, free slots, your money in letters and a Sort button.", true, { id = "bags", reload = true, words = "inventory" })
	choice(of("Bags"), "bagMode", "Bag layout", "One combined bag, or a window for each bag. You can still switch from the bag's own menu.", "combined", {
		{ "combined", "One bag" }, { "separate", "Separate" },
	}, { game = true, words = "combined bags inventory", change = function() Stoa.modules.Bags.db.appliedMode = nil; Stoa.modules.Bags:ApplyMode() end })
	toggle(of("Character"), "enabled", "Restyle the character sheet", "Item level and quality edges on every slot, WORN and BROKEN on gear that needs repair, an average item level line. The inspect window gets item levels too.", true, { id = "character", reload = true, words = "paper doll gear durability" })
	toggle(of("Top"), "enabled", "Restyle the top of the screen", "Buffs as cropped icons with quiet timers, the quest tracker in Stoa's type, and the minimap's zone header on a dark panel.", true, { id = "top", reload = true, words = "buffs auras objective tracker" })
	toggle(of("Top"), "buffList", "Buffs as a list", "Each buff's name and time left beside its icon, easy to scan before a pull. Works best with the buff frame set to one column in Edit Mode.", false, { words = "auras", change = refresh("Top", "RefreshBuffList") })
	toggle(of("Swing"), "enabled", "Restyle the swing timer", "Blizzard's swing timer as a flat bar in a rounded dark track: pale gold for the main hand, blue for the off hand. Place it in Edit Mode.", true, { id = "swing", reload = true, words = "auto attack melee" })
	toggle(of("Meters"), "enabled", "Restyle the damage meter", "Blizzard's damage and healing meters as words over the world with no panel: faint bone bars, your own bar in the accent.", true, { id = "meters", reload = true, words = "dps meter hps details recount" })
	toggle(of("Meters"), "place", "Meters in the top-left corner", "Every meter window sits side by side in one strip flush with the top-left corner. Off leaves them where Edit Mode put them.", true, {
		id = "metersPlace", change = function(_, v) if v then Stoa.modules.Meters:Place() end end,
	})
	group = "Moving"
	toggle(of("WindowMover"), "enabled", "Shift and drag to move windows", "Hold Shift and drag a window by its title or edge. Each keeps its spot when it opens again; Shift and right-click puts one back.", true, { id = "windowMover", reload = true, words = "move frames drag position" })
	button("moveFrames", "Move Stoa's frames", "Unlock the Halo, plaques, cards and bars to drag them where you like, with a grid and snapping. Each role keeps its own spots. Arrow keys nudge, right-click puts one back.", "Unlock", function()
		if Options.close then Options.close() end
		Stoa:ToggleMovers()
	end, { scope = "Per role", cmd = "/stoa unlock", words = "layout edit mode position" })
	actions("resetPlaces", "Put things back", "Every Blizzard window back where the game puts it, or Stoa's frames back in their usual places.", {
		{ "Put every window back", command("windows", "reset") },
		{ "Reset Stoa's frames", command("reset"), confirm = true },
	}, { cmd = "/stoa windows reset · /stoa reset", words = "reset positions default" })

	-- Map and chat
	page = "mapchat"
	group = "Minimap"
	toggle(of("Minimap"), "enabled", "Style the minimap", "Theme-coloured edge, serif zone name, wheel to zoom.", true, { id = "minimap", reload = true })
	choice(of("Minimap"), "shape", "Minimap shape", "A square with rounded corners like Stoa's windows, which shows a little more of the world, or the round map in rings.", "square", {
		{ "square", "Rounded square" }, { "round", "Round" },
	}, { reload = true })
	toggle(of("Tray"), "enabled", "Gather addon icons", "Other addons' minimap buttons move into one small button below the map's corner; click it for a tray of their icons.", true, { id = "tray", reload = true, words = "minimap buttons libdbicon" })
	add({
		kind = "checks", id = "trayKeep", name = "Icons kept on the map", reload = true, cmd = "/stoa tray leave",
		desc = "Ticked icons stay on the minimap; the rest gather in the tray. These are the addon icons Stoa has found.",
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
	toggle(of("Timers"), "mirror", "Breath and fatigue in Stoa's bar", "Breath, fatigue and feign death timers in the same slim bar, worded, in place of Blizzard's.", true, { words = "underwater" })
	group = "Chat"
	local look = of("ChatLook")
	toggle(look, "times", "Times on chat lines", "Each line starts with a quiet time and a thin rule, so messages line up in a column. Skipped when the game's own timestamps are on.", true, { words = "timestamps clock" })
	toggle(look, "air", "More space between chat lines", "", true, { words = "spacing", change = refresh("ChatLook", "Air") })
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
		desc = "Stoa stops counting these at the trainer, every rank. Right-click a spell on the Training page to skip it, or type its name here.",
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
	toggle(of("QuestItems"), "enabled", "Quest item buttons", "A small row of buttons for items your quests ask you to use, beside the Halo.", true, { id = "questItems", reload = true })
	toggle(of("Emergency"), "enabled", "Emergency item", "A button for your healthstone, best healing potion or bandage. It stays in view in combat and lights with LOW under 40% health.", true, { id = "emergency", reload = true, words = "potion healthstone bandage" })
	group = "Loot"
	toggle(of("Loot"), "enabled", "Loot feed and gold an hour", "A short fading list of what you loot above the chat, plus gold an hour and loot value for At a glance.", true, { id = "lootFeed", reload = true, cmd = "/stoa loot", words = "gold per hour" })
	choice(of("Loot"), "show", "Show the loot feed", "When the list above the chat shows.", "WORLD", Stoa.Rules.options({ "WORLD", "ALWAYS", "SOLO", "GROUP", "NEVER" }), { id = "lootShow", list = true, change = rulesChanged })
	actions("lootReset", "Totals", "Gold an hour and loot value count from the last time you started them.", { { "Start the totals again", command("loot", "reset") } }, { cmd = "/stoa loot reset" })

	-- Comforts
	page = "comforts"
	group = "Everyday"
	local comforts = of("Comforts")
	toggle(comforts, "fastLoot", "Faster loot", "With auto loot on, everything lands in your bags the moment the loot window would open. Hold Shift to see the window.", true, { words = "auto loot" })
	toggle(comforts, "farCamera", "Pull the camera further out", "Raises the camera's maximum zoom distance.", true, { game = true, words = "zoom distance max camera", change = refresh("Comforts", "Camera") })
	toggle(comforts, "skipGossip", "Skip one-option chats", "When a character has no quests and only one thing to say, Stoa picks it for you. Hold Shift to stop.", true, { words = "gossip npc" })
	toggle(comforts, "acceptQuests", "Accept quests", "Picks up offered quests. Hold Shift to read one first.", false)
	toggle(comforts, "turnInQuests", "Hand in quests", "Hands in finished quests. A quest with a choice of reward always waits for you. Hold Shift to stop.", false)
	toggle(comforts, "skipCinematics", "Skip cinematics", "Cancels cinematics and movies as they start. Hold Shift to watch.", false, { words = "movies cutscenes" })
	toggle(comforts, "quietErrors", "Quiet errors in combat", "Hides the red \"Not enough mana\" and \"Out of range\" text while you fight; it comes back after.", false, { words = "red text" })
	toggle(comforts, "quietDuels", "Hide other people's duel results", "Lines like \"X has defeated Y in a duel\" stay out of chat, unless they name you.", true)
	toggle(comforts, "quietDrunk", "Hide drunken chatter", "Lines about other people getting tipsy or drunk stay out of chat.", true)
	toggle(comforts, "declineDuels", "Decline duels", "Turns down duel requests as they come. Hold Shift to see one.", false)
	toggle(comforts, "releaseInPvP", "Release in battlegrounds", "Releases your spirit when you die in a battleground, unless you have a soulstone. Hold Shift to stay.", false, { words = "pvp" })
	toggle(comforts, "acceptRes", "Accept resurrections", "Takes a resurrection as soon as it's offered, unless whoever cast it is still fighting. Hold Shift to wait.", false, { words = "rez resurrect" })
	group = "Merchants"
	local merchant = of("Merchant")
	toggle(merchant, "sellJunk", "Sell grey junk", "", true, { words = "vendor" })
	toggle(merchant, "autoRepair", "Repair gear", "", true, { words = "vendor durability" })
	toggle(merchant, "useGuildFunds", "Use guild funds when allowed", "", true)
	add({
		kind = "words", id = "junkList", name = "Always sell", cmd = "/stoa junk add",
		desc = "Items sold with your grey junk, on every character. Shift-click an item in your bags while the box below is open, or type its name or number. The Junk button on your bags marks them by clicking.",
		placeholder = "Item, then Enter", links = true, words = "junk vendor sell list",
		items = function() return sortedKeys(Stoa.db.junk, itemLabel) end,
		add = function(text)
			local id = itemId(text)
			if not id then return false, "Stoa doesn't know that item yet. Shift-click it in your bags instead." end
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
			for id, n in pairs(Stoa.Restock.list()) do out[#out + 1] = { id, ("%s · %d"):format(Stoa.Restock.name(id), n) } end
			table.sort(out, function(a, b) return a[2]:lower() < b[2]:lower() end)
			return out
		end,
		add = function(text)
			local item, number = text:match("^(.-)%s+(%d+)%s*$")
			local id = itemId(item or text)
			if not id then return false, "Stoa doesn't know that item yet. Shift-click it in your bags instead." end
			Stoa.Restock.set(id, tonumber(number) or 20)
			return true
		end,
		remove = function(id) Stoa.Restock.set(id, nil) end,
	})
	group = "Mail"
	local mail = of("Mail")
	toggle(mail, "takeGold", "Take gold button", "Beside the mailbox's Open All: takes the money from every letter and leaves the items. Cash on delivery and letters from game masters are always left for you.", true, { reload = true, words = "postal mailbox money collect" })
	toggle(mail, "summary", "Say what came out", "After Open All, one line in chat with the money and items it took.", true, { words = "postal mailbox" })
	toggle(mail, "toList", "Your characters in To", "A Mine button beside the name box lists your own characters on this realm and the people you mailed lately.", true, { reload = true, words = "postal alts send recipient" })
	group = "Away"
	local away = of("Away")
	toggle(away, "enabled", "Away screen", "When you go away out of a fight, the interface steps aside: your name, rest and time away on a band of leather, and any whispers that come meanwhile. Move, or press Back, to return.", true, { id = "awayOn", words = "afk idle screensaver" })
	toggle(away, "spin", "Turn the camera", "The camera circles your character slowly while you're away.", true, { words = "afk rotate" })
	toggle(away, "inInstances", "In dungeons and raids too", "Off, the away screen waits for the open world.", false, { words = "afk instance" })
	button("awayNow", "See it now", "Shows the away screen without going away. Back or /stoa away closes it.", "Show", command("away"), { cmd = "/stoa away", words = "afk preview" })
	group = "People"
	local social = of("Social")
	toggle(social, "acceptFriendInvites", "Accept friend and guild invites", "", true, { words = "party group" })
	toggle(social, "declineStrangerInvites", "Decline stranger invites", "", false)
	toggle(social, "declineStrangerDuels", "Decline stranger duels", "", true)
	toggle(social, "declineStrangerGuildInvites", "Decline stranger guild invites", "", true)
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
	toggle(invite, "convertToRaid", "Make a raid when full", "", true)
	toggle(invite, "guildChat", "Words work in guild chat", "A guildmate saying just the word in guild chat gets an invite.", false)
	button("company", "Company", "Friends and guildmates who are online: click to whisper, Shift-click to invite.", "Open", function() Stoa.modules.Roster:Toggle() end, { cmd = "/stoa friends", words = "friends roster guild" })

	-- Setup
	page = "setup"
	group = "Start"
	button("welcome", "Welcome page", "The step-by-step setup: where to start, your specs, the look, what a fight does, how much of Stoa, and other addons.", "Open", function() Stoa.Welcome:Show() end, { cmd = "/stoa welcome", words = "wizard first time" })
	choice(function() return Stoa.db end, "preset", "How much Stoa", "Full is everything. Quiet folds more away. Classic feel keeps Blizzard's layout with Stoa's look. Choosing one sets several settings at once.", "full", {
		{ "full", "Full" }, { "quiet", "Quiet" }, { "classic", "Classic feel" },
	}, {
		reload = true, cmd = "/stoa preset", words = "preset minimal",
		set = function(v) Stoa.Welcome:ApplyPreset(v) end,
	})
	button("setups", "Saved setups", "Load the setup from another of your characters.", "Choose", function(owner) Stoa.Setups:Menu(owner) end, { cmd = "/stoa setups", words = "profile alt" })
	button("backup", "Backup", "All of Stoa's settings as one line of text to keep safe, and a place to paste one back.", "Open", function() Stoa.Backup:Show() end, { cmd = "/stoa backup", words = "profile export import string" })
	button("shareLayout", "Share layout", "A shorter line with where your frames sit and the look, to post for others. Paste one on the backup page to use it.", "Copy", function() Stoa.Backup:ShowLayout() end, { cmd = "/stoa layout", words = "export import string profile" })
	group = "Your characters"
	button("alts", "Characters", "Every character you've played with Stoa: level, rest earned since you last played them, raid lockouts and gold. /stoa alts forget <name> drops one.", "Open", command("alts"), { cmd = "/stoa alts", words = "alts altoholic gold lockouts saved instances rested" })
	toggle(of("Alts"), "tooltipCounts", "Count items on every character", "Item tooltips add how many your other characters carry and keep in the bank, from when each last played.", true, { words = "alts bags bank tooltip owned" })
	toggle(of("GearSets"), "enabled", "Gear for each spec", "Put on an equipment set in a spec and Stoa puts it back on whenever you change to that spec, after any fight. A set assigned to a spec in the equipment manager always wins.", true, { id = "gearSetsOn", scope = "This character", words = "equipment manager dual spec swap outfit" })
	group = "Keys"
	button("bind", "Bind keys", "Hover any action, pet or stance button and press a key, mouse button or wheel, with any modifier. Backspace clears; Esc finishes and keeps the keys.", "Start", command("bind"), { cmd = "/stoa bind", words = "keybind hotkey keybinding kb" })
	group = "The game's own settings"
	button("restore", "Put the game's settings back", "Puts back the game settings Stoa changed (far camera, map fade, target nameplate size, combined bags, proc art), as they were before Stoa. One you've changed yourself since stays as you set it.", "Put back", command("restore"), { cmd = "/stoa restore", words = "cvar ledger reset camera" })
	group = "Other addons"
	button("addons", "Other addons", "Choose again which of Stoa's parts step aside for other addons you run, such as bags or nameplates.", "Choose again", command("addons"), { cmd = "/stoa addons", words = "conflicts elvui bagnon companion" })
	button("looks", "Stoa's look for other addons", "Questie's tracker, Bagnon's bags, Details' meters and others in Stoa's dress.", "Choose", command("looks"), { cmd = "/stoa looks", words = "questie bagnon details skin" })
	group = "Help"
	button("report", "Report a problem", "Your setup and any errors Stoa caught this session, ready to copy and send.", "Open", function() Stoa.Report:Show() end, { cmd = "/stoa report", words = "bug error lua" })
	button("check", "Launch check", "Checks every spell, game function and frame Stoa relies on, after a game update. Results in chat.", "Run", command("check"), { cmd = "/stoa check", words = "update broken" })
	button("safe", "Safe mode", "Turns off every skin that reaches into Blizzard's frames and reloads. Turn them back on here afterwards.", "Turn on", function() Stoa.commands.safe() end, { confirm = true, cmd = "/stoa safe", words = "broken errors disable" })

	Options.snapshot()
end

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

function Options.onPage(id)
	local out = {}
	for _, entry in ipairs(Options.list) do
		if entry.page == id then out[#out + 1] = entry end
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
