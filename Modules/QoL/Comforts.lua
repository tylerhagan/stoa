-- Stoa QoL: small comforts, each its own setting.
--   On by default: loot lands the moment the window would open, the camera
--   pulls further out, an NPC with nothing to say but one option skips
--   straight past it, and the tracking you last chose (Find Minerals, Find
--   Herbs...) comes back on after you log in or come back from the dead.
--   Also on: other people's duel results and drunken lines stay out of chat.
--   Off by default: the game's icon over the object you can use, accepting and handing in quests (a quest with a choice
--   of reward always waits for you), skipping cinematics, quieting the
--   red error text in combat, declining duels, releasing your spirit in
--   battlegrounds and accepting a resurrection.
-- Holding Shift stops any of the automation for that window.
local _, ns = ...
local Stoa = ns.Stoa

local Comforts = Stoa:NewModule("Comforts", {
	fastLoot = true,
	farCamera = true,
	skipGossip = true,
	acceptQuests = false,
	turnInQuests = false,
	skipCinematics = false,
	quietErrors = false,
	quietDuels = true,
	quietDrunk = true,
	declineDuels = false,
	releaseInPvP = false,
	acceptRes = false,
	keepTracking = true,
	questGlow = false,
})

local FAR_CAMERA = 2.6

-- Shift stops every comfort. The NPC's window or the loot only opens after
-- a trip to the server, often after Shift is let go, so a press in the
-- last moment counts too, and a talk begun with Shift stays yours until
-- its windows close (the quest you pick from the list included).
local RECENT = 1.5
local shiftAt = -math.huge
local pausedWith -- the NPC a Shift talk is with

local function talkingTo()
	return UnitGUID and UnitGUID("npc") or nil
end

local function held()
	local now = GetTime()
	if IsShiftKeyDown() or now - shiftAt < RECENT then
		pausedWith = talkingTo() or pausedWith
		return true
	end
	local npc = talkingTo()
	return pausedWith ~= nil and npc == pausedWith
end

local function talkClosed()
	C_Timer.After(0.5, function()
		local gossip, quest = _G.GossipFrame, _G.QuestFrame
		if (gossip and gossip:IsShown()) or (quest and quest:IsShown()) then return end
		pausedWith = nil
	end)
end

-- Low-level (grey) quests are left for you to take or not.
local function trivial(questID)
	if not (questID and questID ~= 0 and C_QuestLog and C_QuestLog.IsQuestTrivial) then return false end
	local ok, grey = pcall(C_QuestLog.IsQuestTrivial, questID)
	return ok and grey == true
end

-- Quest help another addon does already (Core/Companions.lua) is left to it.
local function accepting(db)
	return db.acceptQuests and not Stoa:SharedBy("acceptQuests")
end

local function turningIn(db)
	return db.turnInQuests and not Stoa:SharedBy("turnInQuests")
end

-- Loot ------------------------------------------------------------------------

function Comforts:Loot()
	if not self.db.fastLoot or held() or Stoa:SharedBy("fastLoot") then return end
	-- Only when auto loot is on (or its modifier flips it on).
	local auto = GetCVarBool("autoLootDefault")
	if IsModifiedClick and IsModifiedClick("AUTOLOOTTOGGLE") then auto = not auto end
	if not auto then return end
	for slot = GetNumLootItems(), 1, -1 do LootSlot(slot) end
end

-- Camera ----------------------------------------------------------------------

function Comforts:Camera()
	if self.db.farCamera and not Stoa:SharedBy("camera") then
		Stoa.GameSettings:Set("Comforts", "cameraDistanceMaxZoomFactor", FAR_CAMERA)
	else
		Stoa.GameSettings:Restore("cameraDistanceMaxZoomFactor")
	end
end

-- Interact icon ---------------------------------------------------------------
-- An addon cannot draw on the world, so this turns on the game's own small
-- icon over the object or NPC you can use, once you're within reach and
-- facing it. (Retail's outline round objects is cut from Forever's client,
-- so it isn't offered.) Each setting goes back when the switch is turned
-- off (Core/GameSettings.lua).

local QUEST_GLOW = {
	{ "SoftTargetInteract", "3" },
	{ "SoftTargetIconInteract", "1" },
	{ "SoftTargetIconGameObject", "1" },
}
-- Set by earlier versions; handed back to the game.
local NO_LONGER = { "graphicsOutlineMode", "Outline" }

function Comforts:QuestGlow()
	for _, name in ipairs(NO_LONGER) do Stoa.GameSettings:Restore(name) end
	for _, pair in ipairs(QUEST_GLOW) do
		if self.db.questGlow then
			Stoa.GameSettings:Set("Comforts", pair[1], pair[2])
		else
			Stoa.GameSettings:Restore(pair[1])
		end
	end
end

-- Tracking --------------------------------------------------------------------
-- The game drops Find Minerals, Find Herbs and the rest when you log in or
-- die. Stoa remembers the last one you turned on (from the minimap menu or
-- by casting it) per character, and turns it back on out of combat.

local function trackingInfo(index)
	local a, b, c, d, e, f = C_Minimap.GetTrackingInfo(index)
	if type(a) == "table" then return a.name, a.active, a.spellID end
	-- Older shape: name, texture, active, category, nested, spellID.
	return a, c, f
end

local function trackingIndex(spellID, name)
	for index = 1, (C_Minimap.GetNumTrackingTypes() or 0) do
		local entryName, active, entrySpell = trackingInfo(index)
		if (spellID and entrySpell == spellID) or (not spellID and name and entryName == name) then
			return index, active
		end
	end
end

function Comforts:RememberTracking(index, on)
	local name, _, spellID = trackingInfo(index)
	-- Only tracking that comes from a spell is lost on death and login.
	if not spellID then return end
	if on then
		Stoa.char.tracking = { spellID = spellID, name = name }
	elseif Stoa.char.tracking and Stoa.char.tracking.spellID == spellID then
		Stoa.char.tracking = nil
	end
end

-- Tracking already on (after a /reload, say) counts as chosen.
local function learnActive()
	for index = 1, (C_Minimap.GetNumTrackingTypes() or 0) do
		local name, active, spellID = trackingInfo(index)
		if active and spellID then
			Stoa.char.tracking = { spellID = spellID, name = name }
			return
		end
	end
end

function Comforts:RestoreTracking()
	if C_Minimap and C_Minimap.GetTrackingInfo and not Stoa.char.tracking then learnActive() end
	local saved = Stoa.char.tracking
	if not (self.db.keepTracking and saved and C_Minimap and C_Minimap.SetTracking) then return end
	if UnitIsDeadOrGhost("player") then return end
	if InCombatLockdown() then
		self.trackAfterCombat = true
		return
	end
	local index, active = trackingIndex(saved.spellID, saved.name)
	if index and not active then
		self.restoring = true
		C_Minimap.SetTracking(index, true)
		self.restoring = false
	end
end

function Comforts:WatchTracking()
	if not (C_Minimap and C_Minimap.SetTracking and C_Minimap.GetTrackingInfo) then return end
	Stoa.SafeHook(C_Minimap, "SetTracking", function(index, on)
		if not self.restoring then self:RememberTracking(index, on) end
	end)
	if C_Minimap.ClearAllTracking then
		Stoa.SafeHook(C_Minimap, "ClearAllTracking", function() Stoa.char.tracking = nil end)
	end
	-- Cast from the spellbook or a bar.
	Stoa:OnUnit("UNIT_SPELLCAST_SUCCEEDED", { "player" }, function(_, _, spellID)
		if not spellID or Stoa:IsSecret(spellID) then return end
		local index = trackingIndex(spellID)
		if index then self:RememberTracking(index, true) end
	end)
	local function soon(delay)
		C_Timer.After(delay, function() xpcall(self.RestoreTracking, Stoa.catch, self) end)
	end
	Stoa:On("PLAYER_ENTERING_WORLD", function() soon(2) end)
	Stoa:On("PLAYER_ALIVE", function() soon(1) end)
	Stoa:On("PLAYER_UNGHOST", function() soon(1) end)
	Stoa:On("PLAYER_REGEN_ENABLED", function()
		if self.trackAfterCombat then
			self.trackAfterCombat = false
			soon(0.5)
		end
	end)
end

-- Gossip and quests -------------------------------------------------------------

function Comforts:Gossip()
	if held() or not C_GossipInfo then return end
	local db = self.db
	if turningIn(db) then
		for _, quest in ipairs(C_GossipInfo.GetActiveQuests() or {}) do
			if quest.isComplete then
				C_GossipInfo.SelectActiveQuest(quest.questID)
				return
			end
		end
	end
	if accepting(db) then
		for _, quest in ipairs(C_GossipInfo.GetAvailableQuests() or {}) do
			if not quest.isTrivial and not trivial(quest.questID) then
				C_GossipInfo.SelectAvailableQuest(quest.questID)
				return
			end
		end
	end
	if db.skipGossip and not Stoa:SharedBy("skipGossip") then
		local options = C_GossipInfo.GetOptions() or {}
		local quests = C_GossipInfo.GetNumAvailableQuests() + C_GossipInfo.GetNumActiveQuests()
		local only = options[1]
		if #options == 1 and quests == 0 and only.gossipOptionID and not only.failureDescription then
			C_GossipInfo.SelectOption(only.gossipOptionID)
		end
	end
end

-- The older quest greeting some NPCs still use.
function Comforts:Greeting()
	if held() then return end
	local db = self.db
	if turningIn(db) and GetNumActiveQuests then
		for i = 1, GetNumActiveQuests() do
			local _, complete = GetActiveTitle(i)
			if complete then
				SelectActiveQuest(i)
				return
			end
		end
	end
	if accepting(db) and GetNumAvailableQuests then
		for i = 1, GetNumAvailableQuests() do
			local isTrivial, _, _, _, questID = GetAvailableQuestInfo(i)
			if not isTrivial and not trivial(questID) then
				SelectAvailableQuest(i)
				return
			end
		end
	end
end

function Comforts:Detail()
	if not accepting(self.db) or held() then return end
	if trivial(GetQuestID and GetQuestID()) then return end
	if QuestGetAutoAccept and QuestGetAutoAccept() then
		if AcknowledgeAutoAcceptQuest then AcknowledgeAutoAcceptQuest() end
	else
		AcceptQuest()
	end
end

function Comforts:Progress()
	if not turningIn(self.db) or held() then return end
	if IsQuestCompletable() then CompleteQuest() end
end

function Comforts:Complete()
	if not turningIn(self.db) or held() then return end
	-- A choice of reward is yours to make.
	if GetNumQuestChoices() <= 1 then GetQuestReward(1) end
end

-- Cinematics --------------------------------------------------------------------

function Comforts:Cinematic()
	if not self.db.skipCinematics or held() then return end
	if CinematicFrame_CancelCinematic then
		CinematicFrame_CancelCinematic()
	elseif StopCinematic then
		StopCinematic()
	end
end

function Comforts:Movie()
	if not self.db.skipCinematics or held() then return end
	if MovieFrame and MovieFrame.StopMovie then
		MovieFrame:StopMovie()
	elseif GameMovieFinished then
		GameMovieFinished()
	end
end

-- Combat errors ---------------------------------------------------------------
-- "Not enough mana", "Out of range"... hidden while fighting, back after.

function Comforts:Errors(fighting)
	local errors = UIErrorsFrame
	if not errors then return end
	if fighting and self.db.quietErrors then
		errors:UnregisterEvent("UI_ERROR_MESSAGE")
	else
		errors:RegisterEvent("UI_ERROR_MESSAGE")
	end
end

-- Chat noise ------------------------------------------------------------------
-- System lines about other people's duels and drinking, matched from the
-- game's own wording so any language works.

local function pattern(format)
	if type(format) ~= "string" then return nil end
	format = format:gsub("%%%d%$", "%%")
	format = format:gsub("([%(%)%.%+%-%*%?%[%]%^%$])", "%%%1")
	format = format:gsub("%%[sd]", ".+")
	return "^" .. format .. "$"
end

local function patterns(names)
	local list = {}
	for _, name in ipairs(names) do
		local each = pattern(_G[name])
		if each then list[#list + 1] = each end
	end
	return list
end

function Comforts:ChatNoise()
	local duels = patterns({ "DUEL_WINNER_KNOCKOUT", "DUEL_WINNER_RETREAT" })
	local drunk = patterns({ "DRUNK_MESSAGE_OTHER1", "DRUNK_MESSAGE_OTHER2", "DRUNK_MESSAGE_OTHER3", "DRUNK_MESSAGE_OTHER4",
		"DRUNK_MESSAGE_ITEM_OTHER1", "DRUNK_MESSAGE_ITEM_OTHER2", "DRUNK_MESSAGE_ITEM_OTHER3", "DRUNK_MESSAGE_ITEM_OTHER4" })
	local me = UnitName("player")
	local function matches(list, text)
		for _, each in ipairs(list) do
			if text:find(each) then return true end
		end
		return false
	end
	if not ChatFrame_AddMessageEventFilter then return end
	ChatFrame_AddMessageEventFilter("CHAT_MSG_SYSTEM", function(_, _, text)
		if type(text) ~= "string" or Stoa:IsSecret(text) then return false end
		if self.db.quietDuels and matches(duels, text) and not (me and text:find(me, 1, true)) then return true end
		if self.db.quietDrunk and matches(drunk, text) then return true end
		return false
	end)
end

-- Duels, death and resurrection ----------------------------------------------

function Comforts:Duel()
	if not self.db.declineDuels or held() or Stoa:SharedBy("duels") then return end
	if CancelDuel then CancelDuel() end
	if StaticPopup_Hide then StaticPopup_Hide("DUEL_REQUESTED") end
end

function Comforts:Dead()
	if not self.db.releaseInPvP or held() or Stoa:SharedBy("releaseInPvP") then return end
	local _, kind = IsInInstance()
	if kind ~= "pvp" then return end
	-- A soulstone or reincarnation is yours to use.
	if HasSoulstone and HasSoulstone() then return end
	C_Timer.After(0.5, function()
		if UnitIsDead("player") and not UnitIsGhost("player") then pcall(RepopMe) end
	end)
end

function Comforts:Resurrect(from)
	if not self.db.acceptRes or held() or Stoa:SharedBy("acceptRes") then return end
	-- Not mid-fight: a resurrection then is usually better taken later.
	if from and UnitAffectingCombat and UnitExists(from) and UnitAffectingCombat(from) then return end
	AcceptResurrect()
	if StaticPopup_Hide then StaticPopup_Hide("RESURRECT") StaticPopup_Hide("RESURRECT_NO_SICKNESS") StaticPopup_Hide("RESURRECT_NO_TIMER") end
end

-- -----------------------------------------------------------------------------

function Comforts:OnEnable()
	local function on(event, method, ...)
		local args = { ... }
		Stoa:On(event, function()
			xpcall(self[method], Stoa.catch, self, unpack(args))
		end)
	end
	Stoa:On("MODIFIER_STATE_CHANGED", function(key)
		if key == "LSHIFT" or key == "RSHIFT" then shiftAt = GetTime() end
	end)
	Stoa:On("GOSSIP_CLOSED", talkClosed)
	Stoa:On("QUEST_FINISHED", talkClosed)
		on("LOOT_READY", "Loot")
	on("GOSSIP_SHOW", "Gossip")
	on("QUEST_GREETING", "Greeting")
	on("QUEST_DETAIL", "Detail")
	on("QUEST_PROGRESS", "Progress")
	on("QUEST_COMPLETE", "Complete")
	on("CINEMATIC_START", "Cinematic")
	on("PLAY_MOVIE", "Movie")
	on("PLAYER_REGEN_DISABLED", "Errors", true)
	on("PLAYER_REGEN_ENABLED", "Errors", false)
	on("PLAYER_ENTERING_WORLD", "Camera")
	on("PLAYER_ENTERING_WORLD", "QuestGlow")
	on("DUEL_REQUESTED", "Duel")
	on("PLAYER_DEAD", "Dead")
	Stoa:On("RESURRECT_REQUEST", function(from) xpcall(self.Resurrect, Stoa.catch, self, from) end)
	xpcall(self.ChatNoise, Stoa.catch, self)
	xpcall(self.WatchTracking, Stoa.catch, self)
end
