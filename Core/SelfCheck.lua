-- Stoa: the launch check.
-- Stoa was built against the Forever beta. A live patch can move a spell
-- ID, rename an API or drop a Blizzard frame, and any of those would quietly
-- turn a feature off. So on the first login with a new game build, Stoa
-- checks everything it leans on and says in one line if anything's moved.
-- /stoa check shows the full list (it's in /stoa report too).
local _, ns = ...
local Stoa = ns.Stoa

local Check = {}
Stoa.Check = Check

-- The interface number Stoa's TOC was written for.
local BUILT_FOR = 16001

-- Every spell ID Stoa uses for each class, with its English name and who
-- uses it. Only your own class is checked. If the ID is gone, or (in an
-- English client) names a different spell, the feature that uses it is
-- named in the result.
local SPELLS = {
	PRIEST = {
		{ 589, "Shadow Word: Pain", "Shadow" },
		{ 2944, "Devouring Plague", "Shadow" },
		{ 15286, "Vampiric Embrace", "Shadow" },
		{ 8092, "Mind Blast", "Shadow and the Halo signature" },
		{ 32379, "Shadow Word: Death", "Shadow" },
		{ 15407, "Mind Flay", "Shadow and the cast bar ticks" },
		{ 15473, "Shadowform", "Shadow and reminders" },
		{ 15258, "Shadow Weaving", "Shadow" },
		{ 1240721, "Penance", "Discipline and the Halo signature" },
		{ 14751, "Inner Focus", "Discipline" },
		{ 10060, "Power Infusion", "Discipline" },
		{ 17, "Power Word: Shield", "Discipline and the Halo signature" },
		{ 139, "Renew", "Discipline" },
		{ 2060, "Greater Heal", "Discipline" },
		{ 588, "Inner Fire", "reminders" },
	},
	PALADIN = {
		{ 679, "Holy Strike", "Paladin and the Halo signature" },
		{ 20271, "Judgement", "Paladin and the Halo signature" },
		{ 26573, "Consecration", "Protection" },
		{ 20925, "Holy Shield", "Protection" },
		{ 1311649, "Seal of Fury", "Protection" },
		{ 1311015, "Templar's Bulwark", "the Halo signature for tanks" },
		{ 20375, "Seal of Command", "Retribution and Twist of Light" },
		{ 21084, "Seal of Righteousness", "Retribution and Twist of Light" },
		{ 21082, "Seal of the Crusader", "Retribution" },
		{ 879, "Exorcism", "Retribution" },
		{ 20473, "Holy Shock", "the Halo signature for Holy" },
		{ 20216, "Divine Favor", "the Halo signature for Holy" },
		{ 633, "Lay on Hands", "the Halo signature for Holy" },
		{ 465, "Devotion Aura", "reminders" },
		{ 25780, "Righteous Fury", "reminders" },
	},
	DRUID = {
		{ 8921, "Moonfire", "Balance" },
		{ 5570, "Insect Swarm", "Balance" },
		{ 5176, "Wrath", "Balance" },
		{ 2912, "Starfire", "Balance" },
		{ 24858, "Moonkin Form", "Balance" },
		{ 770, "Faerie Fire", "the druid signatures" },
		{ 16857, "Faerie Fire (Feral)", "Cat and Bear" },
		{ 1822, "Rake", "Cat" },
		{ 1079, "Rip", "Cat" },
		{ 5221, "Shred", "Cat" },
		{ 22568, "Ferocious Bite", "Cat" },
		{ 5217, "Tiger's Fury", "Cat and the Halo signature" },
		{ 417141, "Berserk", "Cat, Bear and the Halo signature" },
		{ 1322605, "Shifting Power", "Cat" },
		{ 768, "Cat Form", "Cat" },
		{ 5487, "Bear Form", "Bear" },
		{ 1235827, "Lacerate", "Bear" },
		{ 407995, "Primal Bite", "Bear" },
		{ 6807, "Maul", "Bear" },
		{ 99, "Demoralizing Roar", "Bear" },
		{ 6795, "Growl", "Bear's TAUNT" },
		{ 5229, "Enrage", "the Halo signature for tanks" },
		{ 774, "Rejuvenation", "Restoration" },
		{ 8936, "Regrowth", "Restoration" },
		{ 5185, "Healing Touch", "Restoration" },
		{ 1238215, "Wild Growth", "Restoration" },
		{ 18562, "Swiftmend", "Restoration and the Halo signature" },
		{ 17116, "Nature's Swiftness", "Restoration" },
		{ 16870, "Clearcasting", "CLEARCAST" },
		{ 29166, "Innervate", "the Halo signature for Balance" },
		{ 1126, "Mark of the Wild", "reminders" },
	},
	MAGE = {
		{ 12042, "Arcane Power", "Arcane and the Halo signature" },
		{ 12043, "Presence of Mind", "Arcane" },
		{ 12051, "Evocation", "Arcane" },
		{ 400573, "Arcane Blast", "Arcane" },
		{ 5143, "Arcane Missiles", "Arcane" },
		{ 400588, "Missile Barrage", "Arcane" },
		{ 12536, "Clearcasting", "CLEARCAST" },
		{ 133, "Fireball", "Fire" },
		{ 2136, "Fire Blast", "Fire and the Halo signature" },
		{ 11366, "Pyroblast", "Fire" },
		{ 2948, "Scorch", "Fire" },
		{ 11129, "Combustion", "Fire and the Halo signature" },
		{ 400624, "Hot Streak", "Fire" },
		{ 11095, "Improved Scorch", "Fire" },
		{ 22959, "Fire Vulnerability", "Fire" },
		{ 116, "Frostbolt", "Frost" },
		{ 400640, "Ice Lance", "Frost" },
		{ 122, "Frost Nova", "Frost" },
		{ 11426, "Ice Barrier", "Frost and the Halo signature" },
		{ 11958, "Ice Block", "Frost" },
		{ 400647, "Fingers of Frost", "Frost" },
		{ 168, "Frost Armor", "reminders" },
		{ 1459, "Arcane Intellect", "reminders" },
	},
}

-- Game functions Stoa calls, as dotted paths. "needed" ones break a
-- feature outright; the rest have a fallback, so missing ones only matter
-- if something looks off.
local APIS = {
	{ "C_UnitAuras.GetAuraDataByIndex", "party cards, target auras, signatures", true },
	{ "C_UnitAuras.GetAuraDataBySpellName", "signatures and Discipline counts", true },
	{ "C_Spell.GetSpellName", "signatures", true },
	{ "C_Spell.GetSpellCooldown", "signature coins", true },
	{ "C_Spell.GetSpellCooldownDuration", "coin swipes in combat" },
	{ "C_ActionBar.GetActionCooldownDuration", "combat bar sweeps in combat" },
	{ "IsUsableAction", "the combat bar", true },
	{ "IsActionInRange", "the combat bar's range cue" },
	{ "UnitCastingDuration", "the cast bar in combat" },
	{ "C_AssistedCombat", "next-press hints" },
	{ "issecretvalue", "secret value checks" },
	{ "RegisterAttributeDriver", "party and raid frames", true },
	{ "RegisterStateDriver", "the Halo and target", true },
	{ "C_PartyInfo.InviteUnit", "auto-invite and Company", true },
	{ "C_FriendList.GetFriendInfoByIndex", "Company", true },
	{ "C_BattleNet.GetFriendAccountInfo", "Battle.net friends in Company" },
	{ "C_BattleNet.GetAccountInfoByID", "Battle.net auto-invite" },
	{ "GetGuildRosterInfo", "the guild list" },
	{ "ChatFrameUtil.SendTell", "whispering from Company" },
	{ "C_Container.GetContainerItemInfo", "bags and merchants", true },
	{ "C_Container.SortBags", "the bags' Sort button" },
	{ "C_Item.GetDetailedItemLevelInfo", "item levels on bags and gear" },
	{ "GetInventoryItemDurability", "WORN and BROKEN, gear wear" },
	{ "Settings.RegisterAddOnSetting", "the settings panel", true },
	{ "CreateSettingsButtonInitializer", "settings buttons" },
	{ "Enum.PlayerSwingType", "Twist of Light" },
	{ "GetMaxPlayerLevel", "experience pace on the console" },
	{ "C_QuestLog.GetNumQuestWatches", "the console's quest line" },
	{ "C_QuestLog.GetQuestIDForQuestWatchIndex", "the console's quest line" },
	{ "C_QuestLog.GetQuestObjectives", "the console's quest line" },
	{ "C_QuestLog.GetDistanceSqToQuest", "nearest quest (else the first watched)" },
	{ "C_PartyInfo.DoCountdown", "/stoa pull (else a chat countdown)" },
	{ "C_ChatInfo.SendChatMessage", "the pull countdown in chat (else SendChatMessage)" },
	{ "GetReadyCheckStatus", "READY and NOT READY on party cards" },
	{ "UnitCastingInfo", "the KICK cue" },
	{ "UnitChannelInfo", "the KICK cue" },
	{ "TooltipDataProcessor.AddTooltipPostCall", "tooltip cards", true },
	{ "C_PaperDollInfo.GetInspectItemLevel", "players' item level in tooltips" },
	{ "NotifyInspect", "players' item level in tooltips" },
	{ "UnitDetailedThreatSituation", "the threat meter and threat in tooltips" },
	{ "C_SpellBook.GetSpellBookItemInfo", "spell ranks for auto-uprank and buff reminders" },
	{ "C_Spell.GetSpellPowerCost", "cast cost on the mana bar" },
	{ "UnitPower", "the five-second rule and form mana", true },
	{ "GetActionInfo", "auto-uprank" },
	{ "PlaceAction", "auto-uprank" },
	{ "C_Spell.PickupSpell", "auto-uprank" },
	{ "GetNumQuestChoices", "the best quest reward" },
	{ "GetQuestItemLink", "the best quest reward" },
	{ "C_Container.UseContainerItem", "selling junk" },
	{ "SetRaidTarget", "the raid marker strip" },
	{ "PlaceRaidMarker", "world markers on the marker strip" },
	{ "UnitInRange", "group buff reminders" },
	{ "LinkUtil.RegisterLinkHandler", "clickable web addresses in chat" },
	{ "GetProfessions", "gathering skill on tooltips and the tally" },
}

-- Blizzard frames Stoa dresses or takes the place of.
local FRAMES = {
	{ "PlayerFrame", "the Halo (hides it)" },
	{ "TargetFrame", "the target plaque (hides it)" },
	{ "ChatFrame1", "chat in the console" },
	{ "MinimapCluster", "the minimap" },
	{ "ObjectiveTrackerFrame", "the quest tracker" },
	{ "BuffFrame", "buffs at the top" },
	{ "NamePlateDriverFrame", "nameplates" },
	{ "ContainerFrameCombinedBags", "combined bags" },
	{ "CharacterFrame", "the character sheet" },
	{ "GameTooltip", "tooltips" },
	{ "WorldMapFrame", "the world map border, fade and zone levels" },
	{ "MailFrame", "the mail window" },
	{ "FriendsFrame", "the friends window" },
	{ "DamageMeter", "damage meters" },
	{ "SwingTimerMainHandFrame", "the swing timer" },
	{ "ReadyCheckFrame", "the ready check skin" },
	{ "ReadyCheckListenerFrame", "the ready check skin" },
	{ "QuestInfoRewardsFrame", "the best quest reward" },
}

-- Events the signatures and frames need from this client.
local EVENTS = {
	{ "PLAYER_SWING", "Twist of Light" },
	{ "UNIT_SPELLCAST_SUCCEEDED", "signature timing", true },
	{ "UNIT_AURA", "auras everywhere", true },
	{ "READY_CHECK", "ready words on party cards" },
	{ "READY_CHECK_CONFIRM", "ready words on party cards" },
	{ "READY_CHECK_FINISHED", "ready words on party cards" },
	{ "PLAYER_XP_UPDATE", "experience pace" },
	{ "UNIT_SPELLCAST_INTERRUPTIBLE", "the KICK cue" },
	{ "UNIT_SPELLCAST_NOT_INTERRUPTIBLE", "the KICK cue" },
	{ "UNIT_THREAT_LIST_UPDATE", "the threat meter" },
	{ "UNIT_POWER_FREQUENT", "regen ticks" },
	{ "PLAYER_STARTED_MOVING", "the map fading while you move" },
	{ "CHAT_MSG_LOOT", "the loot feed" },
}

local function lookup(path)
	local value = _G
	for part in path:gmatch("[^%.]+") do
		if type(value) ~= "table" then return nil end
		value = value[part]
	end
	return value
end

local function eventExists(event)
	if C_EventUtils and C_EventUtils.IsEventValid then return C_EventUtils.IsEventValid(event) end
	local probe = CreateFrame("Frame")
	local ok = pcall(probe.RegisterEvent, probe, event)
	if ok then probe:UnregisterAllEvents() end
	return ok
end

-- Runs every check. Returns the list of problems, each { level, text },
-- where level is "broken" (a feature is off) or "changed" (it falls back).
function Check:Run()
	local problems = {}
	local function add(level, text) problems[#problems + 1] = { level = level, text = text } end

	local interface = select(4, GetBuildInfo())
	if interface and interface ~= BUILT_FOR then
		add("changed", ("The game is on interface %s; Stoa was written for %d. If it shows as out of date, tick Load out of date AddOns."):format(tostring(interface), BUILT_FOR))
	end

	local english = not GetLocale or GetLocale() == "enUS" or GetLocale() == "enGB"
	local getName = C_Spell and C_Spell.GetSpellName
	if getName then
		local _, classFile = UnitClass("player")
		for _, spell in ipairs(SPELLS[classFile] or {}) do
			local id, expected, users = spell[1], spell[2], spell[3]
			local ok, name = pcall(getName, id)
			name = ok and name or nil
			if not name then
				add("broken", ("Spell %d (%s) no longer exists: %s won't track it."):format(id, expected, users))
			elseif english and name ~= expected then
				add("broken", ("Spell %d is now %s, not %s: %s needs the new ID."):format(id, name, expected, users))
			end
		end
	end

	for _, api in ipairs(APIS) do
		if lookup(api[1]) == nil then
			add(api[3] and "broken" or "changed", ("%s is missing: %s %s."):format(api[1], api[2], api[3] and "won't work" or "uses a fallback"))
		end
	end
	for _, frame in ipairs(FRAMES) do
		if _G[frame[1]] == nil then
			add("changed", ("Blizzard's %s isn't there (yet): %s is skipped."):format(frame[1], frame[2]))
		end
	end
	for _, event in ipairs(EVENTS) do
		if not eventExists(event[1]) then
			add(event[3] and "broken" or "changed", ("The %s event is gone: %s won't update."):format(event[1], event[2]))
		end
	end
	self.problems = problems
	return problems
end

-- The results as text, for the report page.
function Check:Text()
	local problems = self.problems or self:Run()
	if #problems == 0 then return "Launch check: everything Stoa relies on is where it expects." end
	local lines = { ("Launch check: %d to look at."):format(#problems) }
	for _, level in ipairs({ "broken", "changed" }) do
		for _, problem in ipairs(problems) do
			if problem.level == level then
				lines[#lines + 1] = (level == "broken" and "  OFF  " or "  NOTE ") .. problem.text
			end
		end
	end
	return table.concat(lines, "\n")
end

Stoa.commands.check = function()
	Check:Run()
	if Stoa.Report then Stoa.Report:Show() else print(Check:Text()) end
end

-- Once per game build, a few seconds after login: one line if anything is
-- off. Some Blizzard frames load late, so it waits.
Stoa:On("STOA_READY", function()
	C_Timer.After(8, function()
		local ok = xpcall(function()
			local _, build = GetBuildInfo()
			local problems = Check:Run()
			local broken = 0
			for _, problem in ipairs(problems) do
				if problem.level == "broken" then broken = broken + 1 end
			end
			if Stoa.db.checkedBuild == build and broken == 0 then return end
			Stoa.db.checkedBuild = build
			if broken > 0 then
				Stoa:Print(("Launch check: %d %s changed in this game build, so %s off. /stoa check lists %s."):format(
					broken, broken == 1 and "thing Stoa uses has" or "things Stoa uses have",
					broken == 1 and "a feature is" or "some features are", broken == 1 and "it" or "them"))
			elseif #problems > 0 then
				Stoa:Print("Launch check: all features work; /stoa check has a few notes.")
			end
		end, Stoa.catch)
		return ok
	end)
end)
