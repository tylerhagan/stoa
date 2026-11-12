-- Stoa: addons made to sit beside Stoa.
-- Some addons aren't rivals but companions. Leatrix Plus is a box of small
-- helpers, many of which Stoa has too. OneForAll brings what Stoa
-- doesn't (dungeons and loot, quests, professions, Library Books, talent
-- plans) plus a handful of small helpers Stoa has too. Where both would do
-- the same small job, such as selling junk, looting faster, moving windows
-- or adding a target line to tooltips, the job goes to the companion when
-- its switch for it is on: Stoa's copy waits, and comes back by itself as
-- soon as that switch is off. The switch is read each time the job comes up,
-- so a change in the companion's settings counts at once, without a reload.
--
-- A few things stay Stoa's because they are part of how it looks: the
-- minimap shape (Stoa tells other addons the map is square before they ask,
-- see Modules/Grimoire/Minimap.lua), the chat's column of buttons (a
-- companion's chat button joins it) and the welcome page, which waits until
-- the companion's own has closed.
-- DoesItDie: Stoa draws its DoT estimate on the target plaque, and on Stoa's
-- nameplates while DoesItDie's own nameplate marker is off.
-- /stoa addons says which jobs each companion has right now.
local _, ns = ...
local Stoa = ns.Stoa

local Companions = {}
Stoa.Companions = Companions

-- Jobs Stoa shares, with the words players read in /stoa addons.
local JOBS = {
	fastLoot = "faster looting",
	sellJunk = "selling junk",
	repair = "repairs",
	lootFeed = "the loot feed",
	acceptQuests = "accepting quests",
	turnInQuests = "handing in quests",
	camera = "the far camera",
	windows = "moving Blizzard's windows",
	chatCopy = "the chat's copy button",
	tooltipTarget = "who a unit targets, in tooltips",
	gearUpgrade = "upgrade lines in tooltips",
	bagUpgrade = "upgrade marks in bags",
	rewardUpgrade = "marking the best quest reward",
	invites = "accepting invites from friends and guild",
	keywordInvites = "invites by keyword",
	duels = "declining duels",
	squareMinimap = "a square minimap",
	skipGossip = "skipping one-option gossip",
	releaseInPvP = "releasing in battlegrounds",
	acceptRes = "accepting resurrections",
	dotPlates = "DoT marks on nameplates",
	sparkle = "sparkles on what's up close",
	questLoot = "the game's sparkle on quest items",
	quietErrors = "hiding the red error text",
	tray = "gathering the minimap's addon icons",
	questXP = "finished quests' experience on the bar",
}
local JOB_ORDER = {
	"fastLoot", "sellJunk", "repair", "lootFeed", "acceptQuests", "turnInQuests", "camera",
	"windows", "chatCopy", "tooltipTarget", "gearUpgrade", "bagUpgrade", "rewardUpgrade", "invites", "keywordInvites", "duels",
	"squareMinimap", "skipGossip", "releaseInPvP", "acceptRes", "dotPlates", "sparkle", "questLoot", "quietErrors", "tray", "questXP",
}

-- Addons that only sparkle what's up close: while one is loaded, STOA's
-- sparkle waits, so the two don't stack.
local function sparkler(folder, name)
	return {
		folder = folder, name = name, keys = { sparkle = "on" }, get = function() return true end,
		note = "Sparkles what's up close; STOA's own sparkle waits while it's here.",
	}
end

-- Each companion: its folder, the name players know, and how to read its
-- switch for a job (true when it does that job now).
local COMPANIONS = {
	{
		folder = "OneForAll", name = "OneForAll",
		-- OneForAll keeps its switches in OneForAllDB.qol and answers for its
		-- own defaults through OneForAll.QoL.Get(key).
		keys = {
			fastLoot = "quickLoot", sellJunk = "sellJunk", repair = "autoRepair", lootFeed = "lootFeed",
			acceptQuests = "autoAccept", turnInQuests = "autoTurnIn", camera = "cameraZoom",
			windows = "moveWindows", chatCopy = "copyChat", tooltipTarget = "unitTarget",
			gearUpgrade = "gearValue", bagUpgrade = "gearValue", rewardUpgrade = "gearValue", invites = "inviteOn", keywordInvites = "keywordOn",
			duels = "duelOn", squareMinimap = "mmSquare", sparkle = "nodeGlow",
			questLoot = "questSparkles", quietErrors = "hideErrors", tray = "mmCollect", questXP = "questXP",
		},
		get = function(key)
			local ofa = _G.OneForAll
			local qol = type(ofa) == "table" and ofa.QoL
			if type(qol) ~= "table" or type(qol.Get) ~= "function" then return false end
			local ok, value = pcall(qol.Get, key)
			return ok and value and true or false
		end,
		-- Its welcome page, shown once on a first login.
		welcome = "OneForAllWelcome",
	},
	{
		folder = "Leatrix_Plus", name = "Leatrix Plus",
		-- Leatrix Plus keeps each switch in LeaPlusDB as "On" or "Off". The
		-- names are Leatrix Plus's own; one it renames simply stops counting
		-- as shared, and Stoa's copy does the job again.
		keys = {
			fastLoot = "FasterLooting", sellJunk = "AutoSellJunk", repair = "AutoRepairGear",
			acceptQuests = "AutomateQuests", turnInQuests = "AutomateQuests", skipGossip = "AutomateGossip",
			camera = "MaxCameraZoom", invites = "AcceptPartyFriends", keywordInvites = "InviteFromWhisper",
			duels = "NoDuelRequests", squareMinimap = "SquareMinimap",
			releaseInPvP = "AutoReleasePvP", acceptRes = "AutoAcceptRes",
		},
		get = function(key)
			local db = _G.LeaPlusDB
			return type(db) == "table" and db[key] == "On"
		end,
	},
	{
		folder = "Pawn", name = "Pawn",
		-- Pawn scores gear by its own scales; while it's loaded Stoa's upgrade
		-- marks take its answer (Core/Items.lua). Where Pawn's own switches
		-- (PawnCommon) draw its marks, Stoa leaves that place to it.
		keys = {
			gearUpgrade = "ShowUpgradesOnTooltips", bagUpgrade = "ShowBagUpgradeAdvisor",
			rewardUpgrade = "ShowQuestUpgradeAdvisor",
		},
		get = function(key)
			local db = _G.PawnCommon
			if type(db) ~= "table" then return false end
			-- Before Pawn fills its defaults, tooltips and rewards are on and bags off.
			if db[key] == nil then return key ~= "ShowBagUpgradeAdvisor" end
			return db[key] and true or false
		end,
		note = "Scores your gear; STOA's upgrade marks show Pawn's answer.",
	},
	{
		folder = "DoesItDie", name = "DoesItDie",
		-- It tracks your DoTs, and Stoa draws its estimate through its public
		-- API (Modules/Halo/Lethal.lua). Its own nameplate marker is on until
		-- its "Show on nameplates" is set to Off (DoesItDieDB.nameplateMode).
		keys = { dotPlates = "nameplateMode" },
		get = function(key)
			local db = _G.DoesItDieDB
			local mode = type(db) == "table" and db[key] or "markerIcon"
			return mode ~= "off"
		end,
		note = "Tracks your DoTs; STOA shows their damage left and a kill skull on the target plaque, and on its nameplates if you choose; Settings, Combat, DoT marks on nameplates changes it.",
	},
	sparkler("Sparkles", "Sparkles"),
	sparkler("AzerothForge_Goldspark", "AzerothForge Goldspark"),
	sparkler("NodeSightSparkles", "NodeSight Sparkles"),
	sparkler("NodeSight", "NodeSight"),
}

local function isLoaded(folder)
	if C_AddOns and C_AddOns.IsAddOnLoaded then return C_AddOns.IsAddOnLoaded(folder) end
	return IsAddOnLoaded and IsAddOnLoaded(folder)
end

-- Asked fresh each time: cheap, and right even before every addon has loaded.
local function loaded()
	local list = {}
	for _, companion in ipairs(COMPANIONS) do
		if isLoaded(companion.folder) then list[#list + 1] = companion end
	end
	return list
end

-- The name of the companion doing this job now, or nil when Stoa should.
function Stoa:SharedBy(job)
	for _, companion in ipairs(loaded()) do
		local key = companion.keys[job]
		if key and companion.get(key) then return companion.name end
	end
	return nil
end

-- The loaded companions, for other parts of Stoa.
function Companions:Loaded()
	return loaded()
end

-- Shows fn once every companion's welcome page is closed.
function Companions:AfterWelcomes(fn)
	for _, companion in ipairs(loaded()) do
		local page = companion.welcome and _G[companion.welcome]
		if type(page) == "table" and page.IsShown and page:IsShown() and page.HookScript then
			local done = false
			page:HookScript("OnHide", function()
				if done then return end
				done = true
				-- A beat between the two pages.
				C_Timer.After(0.5, function() Companions:AfterWelcomes(fn) end)
			end)
			return
		end
	end
	fn()
end

-- Lines for /stoa addons.
function Companions:Report()
	for _, companion in ipairs(loaded()) do
		local jobs = {}
		for _, job in ipairs(JOB_ORDER) do
			local key = companion.keys[job]
			if key and companion.get(key) then jobs[#jobs + 1] = JOBS[job] end
		end
		if companion.note then
			local also = #jobs > 0 and (" It also looks after %s itself, so STOA leaves those to it."):format(table.concat(jobs, ", ")) or ""
			Stoa:Print(("%s is here too and works with STOA. %s%s"):format(companion.name, companion.note, also))
		elseif #jobs == 0 then
			Stoa:Print(("%s is here too and works beside STOA; none of its helpers repeat STOA's right now."):format(companion.name))
		else
			Stoa:Print(("%s is here too and works beside STOA. It looks after %s; STOA leaves those to it while they're on in %s."):format(
				companion.name, table.concat(jobs, ", "), companion.name))
		end
	end
end

-- OneForAll on the console -----------------------------------------------------
-- Two lines anyone can pick for At a glance (right-click it, "OneForAll"):
-- the Library Books you have, and the dungeon guide, which opens OneForAll on
-- the dungeon you're in.

local function ofa()
	local addon = _G.OneForAll
	if isLoaded("OneForAll") and type(addon) == "table" then return addon end
end

local function bookCounts()
	local addon = ofa()
	if not (addon and type(addon.GetCounts) == "function" and type(addon.BOOKS) == "table") then return end
	local ok, done, owned = pcall(addon.GetCounts, addon)
	if not ok or type(done) ~= "number" then return end
	return done, owned or done, #addon.BOOKS
end

local function currentDungeon()
	local addon = ofa()
	if not (addon and type(addon.FindCurrentDungeon) == "function") then return end
	local ok, dungeon = pcall(addon.FindCurrentDungeon)
	return ok and type(dungeon) == "table" and dungeon or nil
end

local function register()
	local tally = Stoa.modules.Tally
	if not (ofa() and tally and tally.Register) then return end
	tally:Register("ofaBooks", {
		label = "Library Books",
		value = function()
			local done, _, total = bookCounts()
			if done then return ("%d / %d"):format(done, total) end
		end,
		figure = function()
			local done, _, total = bookCounts()
			if done and total > 0 then return "bar", done / total, "text" end
		end,
		detail = function(add)
			local done, owned, total = bookCounts()
			if not done then return end
			add("Turned in", tostring(done))
			if owned > done then add("In bags or bank", tostring(owned - done)) end
			add("Still to find", tostring(total - owned))
		end,
		action = "Library Books in OneForAll",
		open = function()
			local addon = ofa()
			if addon and type(addon.OpenPanel) == "function" then addon:OpenPanel("books") end
		end,
	}, "OneForAll")
	tally:Register("ofaGuide", {
		label = "Dungeon guide",
		value = function()
			local dungeon = currentDungeon()
			return dungeon and dungeon.name or "OneForAll"
		end,
		detail = function(add)
			local dungeon = currentDungeon()
			add(dungeon and "Bosses, loot and quests" or "Dungeons, quests and loot", "in OneForAll")
		end,
		action = "Open OneForAll",
		open = function()
			local addon = ofa()
			if addon and type(addon.ToggleUI) == "function" then addon:ToggleUI() end
		end,
	}, "OneForAll")
end

Stoa:On("PLAYER_LOGIN", function() xpcall(register, Stoa.catch) end)

-- OneForAll's doubles ----------------------------------------------------------
-- Two of OneForAll's helpers do what STOA does in its own way but can't hand
-- over by a switch STOA reads: its low-rank check (STOA's Uprank puts new
-- ranks on your bars by itself) and its info bar (a band at the top of the
-- screen, where STOA's console already shows gold, bags and the rest). STOA
-- asks once per account whether to switch OneForAll's off; only those
-- switches change, through OneForAll's own QoL.Set, and its Quality of Life
-- page turns them back on.
local DOUBLES = {
	{ key = "lowRank", words = "checking your bars for low spell ranks", stoa = "Uprank" },
	{ key = "infoBar", words = "an info bar at the top of the screen", stoa = "Grimoire" },
}

local function doublesOn()
	local addon = ofa()
	local qol = addon and addon.QoL
	if type(qol) ~= "table" or type(qol.Get) ~= "function" or type(qol.Set) ~= "function" then return end
	local list = {}
	for _, double in ipairs(DOUBLES) do
		local ok, on = pcall(qol.Get, double.key)
		if ok and on and Stoa:IsModuleEnabled(double.stoa) then list[#list + 1] = double end
	end
	if #list > 0 then return list, qol end
end

function Companions:AskOneForAll()
	if Stoa.db.askedOneForAll then return end
	local list = doublesOn()
	if not list then return end
	if Stoa.Welcome and Stoa.Welcome:Pending() then return end
	local busy = (Stoa.Conflicts and Stoa.Conflicts.asking) or (Stoa.Looks and Stoa.Looks.asking)
		or (_G.StoaDotPlatesPage and _G.StoaDotPlatesPage:IsShown())
	if busy or InCombatLockdown() then
		C_Timer.After(15, function() self:AskOneForAll() end)
		return
	end
	if not self.askPage then
		local function answer(useStoa)
			Stoa.db.askedOneForAll = true
			self.askPage:Hide()
			if not useStoa then return end
			local now, qol = doublesOn()
			if not now then return end
			local names = {}
			for _, double in ipairs(now) do
				pcall(qol.Set, double.key, false)
				names[#names + 1] = double.words
			end
			Stoa:Print(("OneForAll's %s is off now; STOA looks after it. OneForAll's Quality of Life page turns it back on."):format(table.concat(names, " and ")))
		end
		self.askPage = Stoa.Conflicts:Page("StoaOneForAllPage", function() answer(true) end, function() answer(false) end)
	end
	local words = {}
	for _, double in ipairs(list) do words[#words + 1] = double.words end
	local page = self.askPage
	page.title:SetText("OneForAll and STOA")
	page.body:SetText(("OneForAll is also doing what STOA does: %s. STOA can switch OneForAll's off, so the two don't double up."):format(table.concat(words, ", and ")))
	page.note:SetText("Only those switches change; everything else of OneForAll stays as it is, and its Quality of Life page turns them back on.")
	page.left.text:SetText("Use STOA's")
	page.right.text:SetText("Leave it")
	page:Show()
end

Stoa:On("PLAYER_LOGIN", function()
	if not ofa() then return end
	C_Timer.After(20, function() xpcall(function() Companions:AskOneForAll() end, Stoa.catch) end)
end)
