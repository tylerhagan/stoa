-- Stoa: addons made to sit beside Stoa.
-- Some addons aren't rivals but companions. OneForAll brings what Stoa
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
	gearUpgrade = "upgrade marks on gear",
	invites = "accepting invites from friends and guild",
	keywordInvites = "invites by keyword",
	duels = "declining duels",
	squareMinimap = "a square minimap",
}
local JOB_ORDER = {
	"fastLoot", "sellJunk", "repair", "lootFeed", "acceptQuests", "turnInQuests", "camera",
	"windows", "chatCopy", "tooltipTarget", "gearUpgrade", "invites", "keywordInvites", "duels",
	"squareMinimap",
}

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
			gearUpgrade = "gearValue", invites = "inviteOn", keywordInvites = "keywordOn",
			duels = "duelOn", squareMinimap = "mmSquare",
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
		if #jobs == 0 then
			Stoa:Print(("%s is here too and works beside Stoa; none of its helpers repeat Stoa's right now."):format(companion.name))
		else
			Stoa:Print(("%s is here too and works beside Stoa. It looks after %s; Stoa leaves those to it while they're on in %s."):format(
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
