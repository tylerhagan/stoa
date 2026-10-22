-- Stoa QoL: social filters. Accepts invites from people you know, quietly
-- declines duels, party and guild invites from strangers. Each choice is
-- reported as a margin note so nothing happens behind your back.
local _, ns = ...
local Stoa = ns.Stoa

local Social = Stoa:NewModule("Social", {
	acceptFriendInvites = true,
	declineStrangerInvites = false,
	declineStrangerDuels = true,
	declineStrangerGuildInvites = true,
})

-- Friends, Battle.net friends on this game, and guildmates count as trusted.
function Stoa:IsTrusted(guid, name)
	if guid and not self:IsSecret(guid) then
		if C_FriendList.IsFriend(guid) then return true end
		if IsGuildMember and IsGuildMember(guid) then return true end
		if C_BattleNet and C_BattleNet.GetGameAccountInfoByGUID then
			if C_BattleNet.GetGameAccountInfoByGUID(guid) then return true end
		end
	end
	if name and not self:IsSecret(name) then
		if C_FriendList.GetFriendInfo and C_FriendList.GetFriendInfo(name) then return true end
		if IsGuildMember and IsGuildMember(name) then return true end
	end
	return false
end

-- A short note for the margin of the Grimoire console. When the console is
-- off, or chat has taken its left page, notes go to chat.
function Stoa:Note(kind, text)
	self:Fire("STOA_NOTE", kind, text)
	if not self.notesInConsole then
		self:Print(text)
	end
end

function Social:OnEnable()
	local db = self.db

	Stoa:On("PARTY_INVITE_REQUEST", function(name, _, _, _, _, _, inviterGUID)
		if Stoa:IsTrusted(inviterGUID, name) then
			if db.acceptFriendInvites then
				AcceptGroup()
				StaticPopup_Hide("PARTY_INVITE")
				Stoa:Note("social", ("Joined %s's group."):format(name))
			end
		elseif db.declineStrangerInvites then
			DeclineGroup()
			StaticPopup_Hide("PARTY_INVITE")
			Stoa:Note("social", ("Declined a group invite from %s."):format(name))
		end
	end)

	Stoa:On("DUEL_REQUESTED", function(name)
		if db.declineStrangerDuels and not Stoa:IsTrusted(nil, name) then
			CancelDuel()
			StaticPopup_Hide("DUEL_REQUESTED")
			Stoa:Note("social", ("Declined a duel from %s."):format(name))
		end
	end)

	Stoa:On("GUILD_INVITE_REQUEST", function(name)
		if db.declineStrangerGuildInvites and not Stoa:IsTrusted(nil, name) then
			DeclineGuild()
			StaticPopup_Hide("GUILD_INVITE")
			Stoa:Note("social", ("Declined a guild invite from %s."):format(name))
		end
	end)
end
