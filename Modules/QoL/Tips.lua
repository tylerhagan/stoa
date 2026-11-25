-- Stoa QoL: tips. Short "did you know" notes about things STOA does that
-- are easy to miss. One shows on the console's Ready column when there are
-- no small jobs (a few words, the whole tip on hover; click opens its
-- setting, right-click means got it and the next one takes its place), and
-- the away screen shows them in turn. Tips you've marked never come back.
local _, ns = ...
local Stoa = ns.Stoa

local Tips = Stoa:NewModule("Tips", {
	enabled = true,
})

-- { id, teaser, the whole tip, settings page or slash command }
-- A page opens Settings there; "/stoa x" runs that command instead.
Tips.LIST = {
	{ "daylight", "Day and night light", "The console's gold catches the sky as the game's clock turns: rose at dawn, your own colour at midday, amber at dusk and moonlit blue at night. /stoa daylight 23 previews an hour.", "console" },
	{ "shiftDrag", "Move any window", "Hold Shift and drag a window by its header or any empty part to move it. It keeps that spot. Shift and right-click puts it back.", "windows" },
	{ "characters", "All your characters", "The Characters window lists everyone you play with STOA: gold, rest, lockouts and item level. Click one to see their gear.", "/stoa alts" },
	{ "bagSearch", "Search every bag", "Type in the bag's search and STOA says which of your other characters hold a match too. Show opens them in the Characters window.", "/stoa alts" },
	{ "counts", "Counts on every character", "Item tooltips say how many your other characters carry and keep in the bank.", "setup" },
	{ "recap", "Your session so far", "/stoa recap shows what this session brought: time played, experience an hour, gold, quests and your best find. It also shows as you log out.", "comforts" },
	{ "companion", "Dungeon companion", "Inside a dungeon, a card lists its bosses and your quests there. /stoa companion and part of a dungeon's name previews it anywhere.", "comforts" },
	{ "planner", "Plan your talents", "The Talent planner word on the talent window opens a planner for levels you haven't reached, with named plans you can share as text.", "windows" },
	{ "selfBuffs", "Click to rebuff", "The small icons left of the Halo are long buffs you're missing or about to lose. Click one to cast it.", "journey" },
	{ "shiftSkip", "Shift skips the comforts", "Hold Shift as you talk to an NPC and STOA's comforts leave that talk alone, just this once.", "comforts" },
	{ "bind", "Bind keys by hovering", "/stoa kb, then hover any action button and press a key to bind it. Backspace clears; Esc keeps the changes.", "/stoa kb" },
	{ "specSwitch", "Switch layout from Ready", "Click your role under Ready on the console to pick another layout for this spec, or to switch talent spec.", "console" },
	{ "glance", "Choose At a glance", "Right-click At a glance on the console to choose which numbers it shows, per spec.", "console" },
	{ "bagViews", "Sections or one grid", "The word in the bag's header switches between sections (new, consumables, gear, junk and more) and one grid in bag order.", "windows" },
	{ "fullBags", "When your bags are full", "If the game says your inventory is full, a card names your least valuable stacks. Click one to destroy it and make room. /stoa fullbags previews it.", "/stoa fullbags" },
	{ "questItems", "Hide a quest's item", "The buttons beside your character are items your quests ask you to use. To hide one, untrack its quest; track it again to bring it back.", "journey" },
	{ "xpBar", "Your finished quests", "The deeper gold stretch on the experience bar is what handing in your finished quests gives. Hover the bar for the count.", "journey" },
	{ "safe", "If a window ever breaks", "/stoa safe turns off every skin that reaches into Blizzard's windows and reloads. Turn them back on in Settings afterwards.", "setup" },
	{ "news", "What's new", "/stoa news shows the latest what's-new note again.", "/stoa news" },
}

function Tips:OnEnable() end

local byId = {}
for _, tip in ipairs(Tips.LIST) do byId[tip[1]] = tip end

local function seen()
	StoaDB = StoaDB or {}
	StoaDB.tipsSeen = StoaDB.tipsSeen or {}
	return StoaDB.tipsSeen
end

-- Settings page names, for "Settings > Console" under a tip.
local function pageName(key)
	for _, page in ipairs(Stoa.Options and Stoa.Options.PAGES or {}) do
		if page[1] == key then return page[2] end
	end
end

function Tips:Where(tip)
	local to = tip[4]
	if to:sub(1, 1) == "/" then return to end
	local name = pageName(to)
	return name and ("Settings > " .. name) or nil
end

-- The tip for this session's Ready line: the first one not marked, starting
-- from a place that moves on each session so the order isn't always the same.
function Tips:Current()
	if not self.enabled or not self.db.enabled then return end
	if self.current and not seen()[self.current] then return byId[self.current] end
	local marked, count = seen(), #self.LIST
	if not self.started then
		self.started = true
		StoaDB.tipsStart = (StoaDB.tipsStart or 0) % count + 1
	end
	for step = 0, count - 1 do
		local tip = self.LIST[((StoaDB.tipsStart + step - 1) % count) + 1]
		if not marked[tip[1]] then
			self.current = tip[1]
			return tip
		end
	end
	self.current = nil
end

function Tips:GotIt(tip)
	if tip then seen()[tip[1]] = true end
end

-- Click: open where the tip lives.
function Tips:Open(tip)
	local to = tip and tip[4]
	if not to or InCombatLockdown() then return end
	if to:sub(1, 1) == "/" then
		local name, rest = to:match("^/stoa (%S+)%s*(.*)$")
		local command = name and Stoa.commands[name]
		if command then command(rest) end
	else
		Stoa:OpenSettings(to)
	end
end

function Tips:ShowTooltip(owner, tip)
	GameTooltip:SetOwner(owner, "ANCHOR_TOP")
	GameTooltip:AddLine("Did you know?")
	local r, g, b = Stoa:Color("text")
	GameTooltip:AddLine(tip[3], r, g, b, true)
	local mr, mg, mb = Stoa:Color("muted")
	local where = self:Where(tip)
	if where then GameTooltip:AddLine(where, mr, mg, mb) end
	GameTooltip:AddLine("Click to open. Right-click: got it.", mr, mg, mb)
	GameTooltip:Show()
end

-- The away screen: every tip in turn, the unmarked ones first.
function Tips:AwayList()
	if not self.enabled or not self.db.enabled then return {} end
	local first, later, marked = {}, {}, seen()
	for _, tip in ipairs(self.LIST) do
		table.insert(marked[tip[1]] and later or first, tip)
	end
	for _, tip in ipairs(later) do first[#first + 1] = tip end
	return first
end

-- /stoa tips: show marked tips again.
Stoa.commands.tips = function()
	if StoaDB then StoaDB.tipsSeen = nil end
	Tips.current = nil
	local console = Stoa.modules.Grimoire
	if console and console.UpdateJobs then console:UpdateJobs() end
	Stoa:Print("Every tip can show again.")
end
