-- Stoa QoL: small comforts, each its own setting.
--   On by default: loot lands the moment the window would open, the camera
--   pulls further out, and an NPC with nothing to say but one option skips
--   straight past it.
--   Off by default: accepting and handing in quests (a quest with a choice
--   of reward always waits for you), skipping cinematics, and quieting the
--   red error text in combat.
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
end
