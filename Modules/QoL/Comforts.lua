-- Stoa QoL: small comforts, each its own setting.
--   On by default: loot lands the moment the window would open, the camera
--   pulls further out, and an NPC with nothing to say but one option skips
--   straight past it.
--   Also on: other people's duel results and drunken lines stay out of chat.
--   Off by default: accepting and handing in quests (a quest with a choice
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
})

local FAR_CAMERA = 2.6

local function held()
	return IsShiftKeyDown()
end

-- Loot ------------------------------------------------------------------------

function Comforts:Loot()
	if not self.db.fastLoot or held() then return end
	-- Only when auto loot is on (or its modifier flips it on).
	local auto = GetCVarBool("autoLootDefault")
	if IsModifiedClick and IsModifiedClick("AUTOLOOTTOGGLE") then auto = not auto end
	if not auto then return end
	for slot = GetNumLootItems(), 1, -1 do LootSlot(slot) end
end

-- Camera ----------------------------------------------------------------------

function Comforts:Camera()
	if not self.db.farCamera or InCombatLockdown() then return end
	pcall(SetCVar, "cameraDistanceMaxZoomFactor", FAR_CAMERA)
end

-- Gossip and quests -------------------------------------------------------------

function Comforts:Gossip()
	if held() or not C_GossipInfo then return end
	local db = self.db
	if db.turnInQuests then
		for _, quest in ipairs(C_GossipInfo.GetActiveQuests() or {}) do
			if quest.isComplete then
				C_GossipInfo.SelectActiveQuest(quest.questID)
				return
			end
		end
	end
	if db.acceptQuests then
		local available = C_GossipInfo.GetAvailableQuests() or {}
		if available[1] then
			C_GossipInfo.SelectAvailableQuest(available[1].questID)
			return
		end
	end
	if db.skipGossip then
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
	if db.turnInQuests and GetNumActiveQuests then
		for i = 1, GetNumActiveQuests() do
			local _, complete = GetActiveTitle(i)
			if complete then
				SelectActiveQuest(i)
				return
			end
		end
	end
	if db.acceptQuests and GetNumAvailableQuests and GetNumAvailableQuests() > 0 then
		SelectAvailableQuest(1)
	end
end

function Comforts:Detail()
	if not self.db.acceptQuests or held() then return end
	if QuestGetAutoAccept and QuestGetAutoAccept() then
		if AcknowledgeAutoAcceptQuest then AcknowledgeAutoAcceptQuest() end
	else
		AcceptQuest()
	end
end

function Comforts:Progress()
	if not self.db.turnInQuests or held() then return end
	if IsQuestCompletable() then CompleteQuest() end
end

function Comforts:Complete()
	if not self.db.turnInQuests or held() then return end
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
	if not self.db.declineDuels or held() then return end
	if CancelDuel then CancelDuel() end
	if StaticPopup_Hide then StaticPopup_Hide("DUEL_REQUESTED") end
end

function Comforts:Dead()
	if not self.db.releaseInPvP or held() then return end
	local _, kind = IsInInstance()
	if kind ~= "pvp" then return end
	-- A soulstone or reincarnation is yours to use.
	if HasSoulstone and HasSoulstone() then return end
	C_Timer.After(0.5, function()
		if UnitIsDead("player") and not UnitIsGhost("player") then pcall(RepopMe) end
	end)
end

function Comforts:Resurrect(from)
	if not self.db.acceptRes or held() then return end
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
	on("DUEL_REQUESTED", "Duel")
	on("PLAYER_DEAD", "Dead")
	Stoa:On("RESURRECT_REQUEST", function(from) xpcall(self.Resurrect, Stoa.catch, self, from) end)
	xpcall(self.ChatNoise, Stoa.catch, self)
end
