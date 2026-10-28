-- Stoa: the dungeon kit.
-- Small helpers for levelling and groups, each its own setting:
--   Experience per hour and time to level, on the console's Journey page
--   (and /stoa xp); the nearest watched quest's progress under it.
--   /stoa pull [seconds]: a pull countdown for the group.
--   Ready check: Stoa's panel, and each party card says READY / NOT READY.
--   KICK on the target plaque while the target casts something you can
--   interrupt.
-- Everything reaching for a game function checks it is there first.
local _, ns = ...
local Stoa = ns.Stoa
local UI = Stoa.UI

local Kit = Stoa:NewModule("Kit", {
	xpRate = true,
	questLine = true,
	bigNumber = true,
	readyCheck = true,
	kickCue = true,
})

local function pcallValue(fn, ...)
	local ok, a, b, c = pcall(fn, ...)
	if ok then return a, b, c end
end

-- Experience ----------------------------------------------------------------
-- The rate is gained experience over a rolling window of the last half hour,
-- starting again at each level (a new level is a new bar, and the old pace
-- over a different bar says little). The session total carries on.

local RATE_WINDOW = 1800
local RATE_MINIMUM = 120

function Kit:ResetWindow()
	self.samples = {}
	self.windowStart = GetTime()
end

function Kit:StartXP()
	self.sessionStart = GetTime()
	self.sessionXP = 0
	self.lastXP, self.lastMax = UnitXP("player"), UnitXPMax("player")
	self:ResetWindow()
end

-- Called on every experience change. Works from the numbers alone, so it
-- doesn't matter whether the level or the experience updates first.
function Kit:OnXP()
	local xp, max = Stoa:PlainNumber(UnitXP("player")), Stoa:PlainNumber(UnitXPMax("player"))
	if not xp or not max or max <= 0 then return end
	if not self.lastXP then
		self.lastXP, self.lastMax = xp, max
		return
	end
	local gain
	if max ~= self.lastMax or xp < self.lastXP then
		-- Levelled: what was left of the old bar, plus the start of the new.
		gain = (self.lastMax - self.lastXP) + xp
		self:ResetWindow()
	else
		gain = xp - self.lastXP
	end
	self.lastXP, self.lastMax = xp, max
	if gain > 0 then
		self.sessionXP = self.sessionXP + gain
		table.insert(self.samples, { at = GetTime(), gain = gain })
	end
end

function Kit:AtMaxLevel()
	local maxLevel = GetMaxPlayerLevel and GetMaxPlayerLevel()
	local level = UnitLevel("player")
	return maxLevel and level and level >= maxLevel or false
end

-- Experience per hour over the window, or nil until there's enough to say.
function Kit:Rate()
	local now = GetTime()
	local cutoff = now - RATE_WINDOW
	local total, kept = 0, {}
	for _, sample in ipairs(self.samples or {}) do
		if sample.at >= cutoff then
			total = total + sample.gain
			kept[#kept + 1] = sample
		end
	end
	self.samples = kept
	local elapsed = now - math.max(self.windowStart or now, cutoff)
	if total <= 0 or elapsed < RATE_MINIMUM then return nil end
	return total / elapsed * 3600
end

-- Seconds to the next level at the current rate, or nil.
function Kit:SecondsToLevel()
	local rate = self:Rate()
	local xp, max = Stoa:PlainNumber(UnitXP("player")), Stoa:PlainNumber(UnitXPMax("player"))
	if not rate or not xp or not max then return nil end
	return (max - xp) / rate * 3600
end

local function shortNumber(n)
	if n >= 10000 then return string.format("%dk", math.floor(n / 1000 + 0.5)) end
	if n >= 1000 then return string.format("%.1fk", n / 1000) end
	return tostring(math.floor(n + 0.5))
end

local function duration(seconds)
	seconds = math.max(seconds, 0)
	local hours = math.floor(seconds / 3600)
	local minutes = math.floor((seconds % 3600) / 60 + 0.5)
	if minutes == 60 then hours, minutes = hours + 1, 0 end
	if hours >= 100 then return "100h+" end
	if hours > 0 then return minutes > 0 and string.format("%dh %dm", hours, minutes) or hours .. "h" end
	if minutes < 1 then return "under a minute" end
	return minutes .. "m"
end

-- "13k xp/h · level in 1h 20m", or nil when there's nothing to say.
function Kit:XPLine()
	if self:AtMaxLevel() then return nil end
	local rate = self:Rate()
	if not rate then
		if (self.sessionXP or 0) > 0 then return "Working out your pace" end
		return nil
	end
	local line = shortNumber(rate) .. " xp/h"
	local left = self:SecondsToLevel()
	if left then line = line .. "  ·  level in " .. duration(left) end
	return line
end

Stoa.commands.xp = function()
	if not Kit.enabled then return end
	if Kit:AtMaxLevel() then
		Stoa:Print("You are at the highest level; there is no experience to count.")
		return
	end
	local session = Kit.sessionXP or 0
	local minutes = math.max((GetTime() - (Kit.sessionStart or GetTime())) / 60, 0)
	Stoa:Print(string.format("This session: %s xp in %s.", shortNumber(session), duration(minutes * 60)))
	local rate, left = Kit:Rate(), Kit:SecondsToLevel()
	if rate and left then
		Stoa:Print(string.format("About %s xp an hour; level in %s.", shortNumber(rate), duration(left)))
	else
		Stoa:Print("Not enough yet to work out a pace; keep going.")
	end
end

-- Quests --------------------------------------------------------------------

local function questTitle(questID)
	local title = C_QuestLog.GetTitleForQuestID and pcallValue(C_QuestLog.GetTitleForQuestID, questID)
	if type(title) == "string" and not Stoa:IsSecret(title) then return title end
end

-- The watched quest closest to you (the first one if distances aren't
-- known), as one line of progress: its first unfinished objective.
function Kit:QuestLine()
	local log = C_QuestLog
	if not (log and log.GetNumQuestWatches and log.GetQuestIDForQuestWatchIndex and log.GetQuestObjectives) then return nil end
	local count = Stoa:PlainNumber(pcallValue(log.GetNumQuestWatches)) or 0
	local bestID, bestDistance
	for i = 1, count do
		local questID = Stoa:PlainNumber(pcallValue(log.GetQuestIDForQuestWatchIndex, i))
		if questID then
			local distance = log.GetDistanceSqToQuest and Stoa:PlainNumber(pcallValue(log.GetDistanceSqToQuest, questID))
			if not bestID or (distance and (not bestDistance or distance < bestDistance)) then
				bestID, bestDistance = questID, distance
			end
		end
	end
	if not bestID then return nil end
	local title = questTitle(bestID)
	local objectives = pcallValue(log.GetQuestObjectives, bestID)
	if type(objectives) == "table" then
		for _, objective in ipairs(objectives) do
			local text = objective.text
			if not objective.finished and type(text) == "string" and text ~= "" and not Stoa:IsSecret(text) then
				return text
			end
		end
	end
	if title then
		local done = log.IsComplete and pcallValue(log.IsComplete, bestID)
		return (done == true and "Hand in: " or "") .. title
	end
end

-- The pace over the last while, one reading a minute, for the console's
-- small line chart (twelve readings, the oldest first).
local HISTORY = 12

function Kit:RecordPace()
	local rate = self:Rate()
	if not rate then return end
	local now = GetTime()
	if self.pacedAt and now - self.pacedAt < 60 then return end
	self.pacedAt = now
	self.history = self.history or {}
	table.insert(self.history, rate)
	while #self.history > HISTORY do table.remove(self.history, 1) end
end

-- The pace row on the console (a line chart, xp an hour and time to level)
-- and the nearest quest line. The quest line is out of combat only (the
-- console is folded then anyway) and only when travelling alone, as the
-- Company column holds the party otherwise.
function Kit:UpdateConsole()
	local console = Stoa.modules.Grimoire
	if not (console and console.rateNote) then return end
	local rate = self.db.xpRate and not self:AtMaxLevel() and self:Rate()
	local pace = console.pace
	if pace then
		if rate then
			self:RecordPace()
			pace.spark:Set(self.history or {})
			pace.perHour:SetText(shortNumber(rate))
			pace.perHourCap:SetText("xp an hour")
			local left = self:SecondsToLevel()
			local level = UnitLevel("player")
			pace.toLevel:SetText(left and duration(left) or "")
			pace.toLevelCap:SetText(left and ("to " .. (level + 1)) or "")
		end
		pace:SetShown(rate and true or false)
	end
	-- Words while the pace is still being worked out.
	local words = ""
	if self.db.xpRate and not rate then words = self:XPLine() or "" end
	console.rateNote:SetText(words)
	console.rateNote:SetShown(words ~= "")
	local quest = ""
	if self.db.questLine and not IsInGroup() and Stoa:GetState() ~= Stoa.STATE_COMBAT then
		quest = self:QuestLine() or ""
	end
	console.questNote:SetText(quest)
end

-- Pull timer ----------------------------------------------------------------

local DEFAULT_PULL = 10
local MAX_PULL = 60

local function chatChannel()
	if not IsInGroup() then return nil end
	if IsInRaid() then return "RAID" end
	local instance = _G.LE_PARTY_CATEGORY_INSTANCE
	if instance and IsInGroup(instance) then return "INSTANCE_CHAT" end
	return "PARTY"
end

local function say(message)
	local channel = chatChannel()
	if not channel then return end
	local send = C_ChatInfo and C_ChatInfo.SendChatMessage or SendChatMessage
	if send then pcall(send, message, channel) end
end

function Kit:BuildPull()
	if self.pullFrame then return end
	local frame = CreateFrame("Frame", "StoaPull", UIParent)
	frame:SetSize(300, 120)
	frame:SetPoint("CENTER", UIParent, "CENTER", 0, 160)
	frame:SetFrameStrata("HIGH")
	frame:EnableMouse(false)
	local number = UI.text(frame, "serif", 96, "text", "CENTER")
	number:SetPoint("CENTER")
	UI.legible(number)
	frame.number = number
	frame:Hide()
	self.pullFrame = frame
end

-- Called from the frame's OnUpdate while a countdown runs or its closing
-- word is on screen.
function Kit:TickPull()
	local frame = self.pullFrame
	local pull = self.pull
	local now = GetTime()
	if not pull then
		if not self.hideAt or now >= self.hideAt then
			frame:SetScript("OnUpdate", nil)
			frame:Hide()
		end
		return
	end
	local remaining = pull.endsAt - now
	if remaining <= 0 then
		self.pull = nil
		if pull.local_ then
			frame.number:SetText("PULL")
			self.hideAt = now + 1.2
		else
			frame:Hide()
		end
		return
	end
	local seconds = math.ceil(remaining)
	if pull.local_ then frame.number:SetText(seconds) end
	if pull.chat and seconds <= 3 and not pull.said[seconds] then
		pull.said[seconds] = true
		say(tostring(seconds))
	end
end

function Kit:StopPull(quiet)
	local pull = self.pull
	if not pull then
		if not quiet then Stoa:Print("No pull timer is running.") end
		return
	end
	self.pull = nil
	self.hideAt = nil
	if self.pullFrame then
		self.pullFrame:SetScript("OnUpdate", nil)
		self.pullFrame:Hide()
	end
	if quiet then return end
	if pull.blizzard and C_PartyInfo and C_PartyInfo.DoCountdown then pcall(C_PartyInfo.DoCountdown, 0) end
	if pull.chat then say("Pull cancelled") end
	Stoa:Print("Pull timer cancelled.")
end

function Kit:StartPull(seconds)
	if self.pull then
		Stoa:Print("A pull timer is already running. /stoa pull 0 cancels it.")
		return
	end
	local grouped = IsInGroup()
	local pull = { endsAt = GetTime() + seconds, said = {} }
	-- Blizzard's own countdown shows to everyone in the group; it needs a
	-- leader or assistant, so a refusal falls back to chat.
	if grouped and C_PartyInfo and C_PartyInfo.DoCountdown then
		local ok, result = pcall(C_PartyInfo.DoCountdown, seconds)
		pull.blizzard = ok and result ~= false
	end
	if not pull.blizzard then
		pull.chat = grouped
		pull.local_ = self.db.bigNumber
		if grouped and seconds > 3 then say("Pull in " .. seconds) end
	end
	self.pull = pull
	self.hideAt = nil
	self:BuildPull()
	if pull.local_ then
		self.pullFrame.number:SetText(seconds)
		self.pullFrame:Show()
	end
	self.pullFrame:SetScript("OnUpdate", Stoa:GuardUpdate(function() self:TickPull() end))
	Stoa:Print("Pull in " .. seconds .. ". /stoa pull 0 cancels.")
end

Stoa.commands.pull = function(rest)
	if not Kit.enabled then return end
	local text = strtrim(rest or "")
	local seconds = DEFAULT_PULL
	if text ~= "" then
		seconds = tonumber(text)
		if not seconds then
			Stoa:Print("Use /stoa pull 10, or /stoa pull 0 to cancel.")
			return
		end
	end
	seconds = math.floor(seconds)
	if seconds <= 0 then
		Kit:StopPull()
		return
	end
	Kit:StartPull(math.min(seconds, MAX_PULL))
end

-- Ready check ---------------------------------------------------------------
-- Each card gets a word while a check runs, and for a few seconds after, so
-- the answer reads without colour: READY, NOT READY, or WAITING.

local READY_STAY = 6

function Kit:ReadyPip(unit)
	if not (self.db.readyCheck and self.readyActive) then return nil end
	local status = self.answers and self.answers[unit]
	if GetReadyCheckStatus and not self.readyDone then
		local live = pcallValue(GetReadyCheckStatus, unit)
		if live == "ready" or live == "notready" then status = live end
	end
	if status == "ready" then return { "READY", "accent" }, "accent" end
	if status == "notready" or self.readyDone then return { "NOT READY", "danger" }, "danger" end
	return { "WAITING", nil, "muted" }, "muted"
end

function Kit:RefreshCards()
	local party = Stoa.modules.Party
	if party and party.cards and party.UpdateAll then party:UpdateAll() end
end

function Kit:OnReadyCheck()
	self.readyActive, self.readyDone = true, false
	self.answers = {}
	self.readyToken = (self.readyToken or 0) + 1
	self:RefreshCards()
end

function Kit:OnReadyConfirm(unit, isReady)
	if not self.readyActive or type(unit) ~= "string" then return end
	self.answers = self.answers or {}
	if isReady == true then
		self.answers[unit] = "ready"
	elseif isReady == false then
		self.answers[unit] = "notready"
	end
	self:RefreshCards()
end

function Kit:OnReadyFinished()
	if not self.readyActive then return end
	self.readyDone = true
	self:RefreshCards()
	local token = self.readyToken
	C_Timer.After(READY_STAY, function()
		-- A newer check has its own timer.
		if self.readyToken ~= token then return end
		self.readyActive, self.readyDone, self.answers = false, false, nil
		self:RefreshCards()
	end)
end

-- Interrupt cue -------------------------------------------------------------
-- KICK, in the warning colour, on the target plaque while the target is
-- casting or channelling something that can be interrupted. A word, so it
-- doesn't depend on colour. If the game hides whether a cast can be
-- interrupted (a secret value) the cue stays off rather than guess.

function Kit:ShowKick(shown)
	local halo = Stoa.modules.Halo
	local kick = halo and halo.target and halo.target.kick
	if not kick then return end
	if shown then
		kick:SetText("KICK")
		kick:SetTextColor(Stoa:Color("danger"))
	end
	kick:SetShown(shown and true or false)
end

function Kit:Kickable()
	if not self.db.kickCue or not UnitExists("target") then return false end
	local hostile = UnitCanAttack("player", "target")
	if Stoa:IsSecret(hostile) or not hostile then return false end
	-- A cast has its cast ID before the flag; a channel does not.
	local name, _, _, _, _, _, _, flag = UnitCastingInfo("target")
	if not (Stoa:IsSecret(name) or name ~= nil) then
		local channel, _, _, _, _, _, channelFlag = UnitChannelInfo("target")
		if not (Stoa:IsSecret(channel) or channel ~= nil) then return false end
		flag = channelFlag
	end
	if Stoa:IsSecret(flag) then return false end
	return flag ~= true
end

-- Never lets an error from a cast event reach the game.
function Kit:UpdateKick()
	local ok, kickable = pcall(self.Kickable, self)
	self:ShowKick(ok and kickable)
end

-- Lifecycle -----------------------------------------------------------------

function Kit:OnEnable()
	self:StartXP()
	self:BuildPull()

	Stoa:On("PLAYER_XP_UPDATE", function(unit)
		if unit and unit ~= "player" then return end
		self:OnXP()
		self:UpdateConsole()
	end)
	Stoa:On("PLAYER_LEVEL_UP", function()
		self:OnXP()
		self:UpdateConsole()
	end)

	-- Quest events come in bursts, so the console is refreshed once a moment
	-- after the last of them.
	local pending
	local function soon()
		if pending then return end
		pending = true
		C_Timer.After(0.5, function()
			pending = false
			self:UpdateConsole()
		end)
	end
	for _, event in ipairs({ "QUEST_LOG_UPDATE", "QUEST_WATCH_LIST_CHANGED", "UNIT_QUEST_LOG_CHANGED", "GROUP_ROSTER_UPDATE", "STOA_STATE_CHANGED", "PLAYER_ENTERING_WORLD" }) do
		Stoa:On(event, soon)
	end
	-- Pace and distance drift with time.
	Stoa:NewTicker(30, function() self:UpdateConsole() end)
	self:UpdateConsole()

	-- A fight starting is the pull; the number's job is done.
	Stoa:On("PLAYER_REGEN_DISABLED", function() self:StopPull(true) end)
	Stoa:On("GROUP_LEFT", function() self:StopPull(true) end)

	Stoa:On("READY_CHECK", function() self:OnReadyCheck() end)
	Stoa:On("READY_CHECK_CONFIRM", function(unit, isReady) self:OnReadyConfirm(unit, isReady) end)
	Stoa:On("READY_CHECK_FINISHED", function() self:OnReadyFinished() end)

	Stoa:On("PLAYER_TARGET_CHANGED", function() self:UpdateKick() end)
	for _, event in ipairs({
		"UNIT_SPELLCAST_START", "UNIT_SPELLCAST_DELAYED", "UNIT_SPELLCAST_CHANNEL_START", "UNIT_SPELLCAST_CHANNEL_UPDATE",
		"UNIT_SPELLCAST_STOP", "UNIT_SPELLCAST_FAILED", "UNIT_SPELLCAST_INTERRUPTED", "UNIT_SPELLCAST_CHANNEL_STOP",
		"UNIT_SPELLCAST_INTERRUPTIBLE", "UNIT_SPELLCAST_NOT_INTERRUPTIBLE",
	}) do
		Stoa:On(event, function(unit)
			if unit == "target" then self:UpdateKick() end
		end)
	end
end
