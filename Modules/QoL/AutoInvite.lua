-- Stoa QoL: auto-invite. Whisper a keyword ("inv" by default) and you are
-- invited, as long as you are a friend or guildmate and Stoa can invite.
local _, ns = ...
local Stoa = ns.Stoa

local AutoInvite = Stoa:NewModule("AutoInvite", {
	keywords = "inv, invite",
	strangersToo = false,
	convertToRaid = true,
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

function AutoInvite:OnEnable()
	local db = self.db

	local function onWhisper(text, sender, guid)
		if not db.enabled or Stoa:IsSecret(text) then return end
		local keywords = keywordSet(db.keywords)
		if not keywords[strtrim(text):lower()] then return end
		if not db.strangersToo and not Stoa:IsTrusted(guid, sender) then return end
		if not canInvite() then
			Stoa:Note("social", ("%s asked for an invite, but you are not the leader."):format(sender))
			return
		end
		maybeConvertToRaid(db)
		C_PartyInfo.InviteUnit(sender)
		Stoa:Note("social", ("%s whispered \"%s\" and was invited."):format(Ambiguate(sender, "short"), text))
	end

	Stoa:On("CHAT_MSG_WHISPER", function(text, sender, _, _, _, _, _, _, _, _, _, guid)
		onWhisper(text, sender, guid)
	end)

	-- Battle.net whispers carry no character name, so they are not handled yet.
end
