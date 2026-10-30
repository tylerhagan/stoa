-- Stoa QoL: auto-invite. Whisper a keyword ("inv" by default), in game or
-- over Battle.net, and you are invited, as long as you are a friend or
-- guildmate and Stoa can invite. Optionally the keyword works in guild chat.
local _, ns = ...
local Stoa = ns.Stoa

local AutoInvite = Stoa:NewModule("AutoInvite", {
	keywords = "inv, invite",
	strangersToo = false,
	convertToRaid = true,
	guildChat = false,
})

local function keywordSet(text)
	local set = {}
	for word in text:gmatch("[^,%s]+") do
		set[word:lower()] = true
	end
	return set
end

local function canInvite()
	if not IsInGroup() then return true end
	return UnitIsGroupLeader("player") or UnitIsGroupAssistant("player")
end

local function maybeConvertToRaid(db)
	if db.convertToRaid and IsInGroup() and not IsInRaid() and GetNumGroupMembers() >= 5 then
		C_PartyInfo.ConvertToRaid()
		Stoa:Note("social", "Converted the party to a raid.")
	end
end

-- A full group can't take anyone else (a party only once it can become a raid).
local function hasRoom(db)
	if IsInRaid() then return GetNumGroupMembers() < (MAX_RAID_MEMBERS or 40) end
	if IsInGroup() and GetNumGroupMembers() >= 5 then return db.convertToRaid end
	return true
end

-- The character a Battle.net friend is playing in this same game, if any.
local function bnetCharacter(bnSenderID)
	if not (bnSenderID and C_BattleNet and C_BattleNet.GetAccountInfoByID) then return nil end
	if Stoa:IsSecret(bnSenderID) then return nil end
	local account = C_BattleNet.GetAccountInfoByID(bnSenderID)
	local game = account and account.gameAccountInfo
	if not (game and game.isOnline and game.clientProgram == BNET_CLIENT_WOW and game.characterName) then return nil end
	if game.wowProjectID and game.wowProjectID ~= WOW_PROJECT_ID then return nil end
	local name = game.characterName
	if game.realmName and game.realmName ~= GetRealmName() then name = name .. "-" .. game.realmName end
	return name, game.gameAccountID
end

function AutoInvite:OnEnable()
	local db = self.db

	local function wants(text)
		if not db.enabled or not text or Stoa:IsSecret(text) then return false end
		-- Another addon inviting by keyword already (Core/Companions.lua).
		if Stoa:SharedBy("keywordInvites") then return false end
		return keywordSet(db.keywords)[strtrim(text):lower()] or false
	end

	local function invite(name, text, gameAccountID)
		if not name or Stoa:IsSecret(name) then return end
		local short = Ambiguate(name, "short")
		if not canInvite() then
			Stoa:Note("social", ("%s asked for an invite, but you are not the leader."):format(short))
			return
		end
		if not hasRoom(db) then
			Stoa:Note("social", ("%s asked for an invite, but the group is full."):format(short))
			return
		end
		maybeConvertToRaid(db)
		if C_PartyInfo and C_PartyInfo.InviteUnit then
			C_PartyInfo.InviteUnit(name)
		elseif gameAccountID and BNInviteFriend then
			BNInviteFriend(gameAccountID)
		end
		Stoa:Note("social", ("%s said \"%s\" and was invited."):format(short, text))
	end

	Stoa:On("CHAT_MSG_WHISPER", function(text, sender, _, _, _, _, _, _, _, _, _, guid)
		if not wants(text) then return end
		if not db.strangersToo and not Stoa:IsTrusted(guid, sender) then return end
		invite(sender, text)
	end)

	-- Battle.net friends are trusted by being friends; the whisper names the
	-- account, so the character comes from what they're playing.
	Stoa:On("CHAT_MSG_BN_WHISPER", function(text, _, _, _, _, _, _, _, _, _, _, _, bnSenderID)
		if not wants(text) then return end
		local name, gameAccountID = bnetCharacter(bnSenderID)
		if name then invite(name, text, gameAccountID) end
	end)

	-- Guildmates are trusted already.
	Stoa:On("CHAT_MSG_GUILD", function(text, sender)
		if not db.guildChat or not wants(text) or Stoa:IsSecret(sender) then return end
		if Ambiguate(sender, "short") == UnitName("player") then return end
		invite(sender, text)
	end)
end
