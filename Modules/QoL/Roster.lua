-- Stoa QoL: the roster. /stoa friends (or a click on the console's Company
-- page) opens one page of who you know that's online: friends, Battle.net
-- friends playing this game, and your guild. Click a name to whisper,
-- Shift-click or press Invite to ask them along.
local _, ns = ...
local Stoa = ns.Stoa
local UI = Stoa.UI

local Roster = Stoa:NewModule("Roster", {
	tab = "friends",
})

local WIDTH, HEIGHT = 460, 470
local PAD = 24
local ROWS = 14
local ROW_HEIGHT = 24

-- Class colours are keyed by the English class file name; friend lists give
-- the localised name, so build the way back.
local classFiles
local function classFileOf(className)
	if not className then return nil end
	if not classFiles then
		classFiles = {}
		for file, name in pairs(LOCALIZED_CLASS_NAMES_MALE or {}) do classFiles[name] = file end
		for file, name in pairs(LOCALIZED_CLASS_NAMES_FEMALE or {}) do classFiles[name] = file end
	end
	return classFiles[className] or className:upper()
end

local function classColour(file)
	local color = file and Stoa:Theme().classTint and RAID_CLASS_COLORS and RAID_CLASS_COLORS[file]
	if color then return color.r, color.g, color.b end
	return Stoa:Color("text")
end

local function status(afk, dnd)
	if dnd then return "BUSY" end
	if afk then return "AWAY" end
	return ""
end

-- Gathering -----------------------------------------------------------------

-- Your friends here and your Battle.net friends in this same game. Each
-- entry: name (to invite or whisper), label, level, zone, class file, and
-- for Battle.net friends the account to whisper.
local function gatherFriends()
	local list, seen = {}, {}
	if C_FriendList and C_FriendList.GetNumFriends then
		for i = 1, C_FriendList.GetNumFriends() or 0 do
			local info = C_FriendList.GetFriendInfoByIndex(i)
			if info and info.connected then
				seen[info.name] = true
				list[#list + 1] = {
					name = info.name, label = Ambiguate(info.name, "short"), level = info.level,
					zone = info.area, class = classFileOf(info.className), note = status(info.afk, info.dnd),
				}
			end
		end
	end
	if BNGetNumFriends and C_BattleNet and C_BattleNet.GetFriendAccountInfo then
		local count = BNGetNumFriends() or 0
		for i = 1, count do
			local account = C_BattleNet.GetFriendAccountInfo(i)
			local game = account and account.gameAccountInfo
			if game and game.isOnline and game.clientProgram == BNET_CLIENT_WOW
				and (not game.wowProjectID or game.wowProjectID == WOW_PROJECT_ID) and game.characterName then
				local name = game.characterName
				if game.realmName and game.realmName ~= GetRealmName() then name = name .. "-" .. game.realmName end
				if not seen[name] then
					seen[name] = true
					list[#list + 1] = {
						name = name, label = game.characterName, level = game.characterLevel,
						zone = game.areaName, class = game.classFilename or classFileOf(game.className),
						note = status(account.isAFK or game.isGameAFK, account.isDND or game.isGameBusy),
						account = account.accountName, gameAccountID = game.gameAccountID,
					}
				end
			end
		end
	end
	return list
end

local function gatherGuild()
	local list = {}
	if not IsInGuild() or not GetGuildRosterInfo then return list end
	local me = UnitName("player")
	for i = 1, GetNumGuildMembers() or 0 do
		local name, rank, _, level, className, zone, _, _, online, state, classFile = GetGuildRosterInfo(i)
		if name and online and Ambiguate(name, "short") ~= me then
			list[#list + 1] = {
				name = name, label = Ambiguate(name, "short"), level = level, zone = zone,
				class = classFile or classFileOf(className), note = state == 1 and "AWAY" or state == 2 and "BUSY" or "",
				rank = rank,
			}
		end
	end
	return list
end

-- Actions -------------------------------------------------------------------

function Roster:Whisper(entry)
	if entry.account and ChatFrameUtil and ChatFrameUtil.SendBNetTell then
		ChatFrameUtil.SendBNetTell(entry.account)
	elseif ChatFrameUtil and ChatFrameUtil.SendTell then
		ChatFrameUtil.SendTell(entry.name)
	elseif ChatFrame_SendTell then
		ChatFrame_SendTell(entry.name)
	end
end

function Roster:Invite(entry)
	if IsInGroup() and not (UnitIsGroupLeader("player") or UnitIsGroupAssistant("player")) then
		Stoa:Print("Only the group leader can invite.")
		return
	end
	if C_PartyInfo and C_PartyInfo.InviteUnit then
		C_PartyInfo.InviteUnit(entry.name)
	elseif entry.gameAccountID and BNInviteFriend then
		BNInviteFriend(entry.gameAccountID)
	end
	Stoa:Note("social", ("Invited %s."):format(entry.label))
end

-- Page ----------------------------------------------------------------------

function Roster:BuildRow(page, i)
	local row = CreateFrame("Button", nil, page)
	row:SetHeight(ROW_HEIGHT)
	row:SetPoint("TOPLEFT", PAD, -112 - (i - 1) * ROW_HEIGHT)
	row:SetPoint("RIGHT", page, "RIGHT", -PAD, 0)
	row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	local hover = row:CreateTexture(nil, "BACKGROUND")
	hover:SetAllPoints()
	UI.paint(hover, "text", 0.06)
	hover:Hide()
	local name = UI.text(row, "serif", Stoa.typeSize.label, "text", "LEFT")
	name:SetPoint("LEFT", 4, 0)
	name:SetWidth(130)
	name:SetWordWrap(false)
	local level = UI.text(row, "sans", Stoa.typeSize.caption + 1, "muted", "RIGHT")
	level:SetPoint("LEFT", name, "RIGHT", 4, 0)
	level:SetWidth(24)
	local zone = UI.text(row, "sans", Stoa.typeSize.caption + 1, "muted", "LEFT")
	zone:SetPoint("LEFT", level, "RIGHT", 12, 0)
	zone:SetWidth(150)
	zone:SetWordWrap(false)
	local invite = UI.button(row, "Invite", 64, function() if row.entry then self:Invite(row.entry) end end)
	invite:SetHeight(20)
	invite:SetPoint("RIGHT", -2, 0)
	invite:SetAlpha(0.75)
	row:SetScript("OnEnter", function() hover:Show() end)
	row:SetScript("OnLeave", function() hover:Hide() end)
	row:SetScript("OnClick", function(_, button)
		if not row.entry then return end
		if IsShiftKeyDown() or button == "RightButton" then self:Invite(row.entry) else self:Whisper(row.entry) end
	end)
	row.name, row.level, row.zone = name, level, zone
	return row
end

function Roster:Build()
	local page = CreateFrame("Frame", "StoaRosterPage", UIParent)
	page:SetSize(WIDTH, HEIGHT)
	page:SetPoint("CENTER", 0, 60)
	page:SetFrameStrata("DIALOG")
	page:EnableMouse(true)
	page:SetMovable(true)
	page:RegisterForDrag("LeftButton")
	page:SetScript("OnDragStart", page.StartMoving)
	page:SetScript("OnDragStop", page.StopMovingOrSizing)
	page:Hide()
	table.insert(UISpecialFrames, "StoaRosterPage")
	UI.windowPanel(page, 0.97)
	self.page = page

	local title = UI.text(page, "serif", Stoa.typeSize.display, "text")
	title:SetPoint("TOPLEFT", PAD, -PAD)
	title:SetText("Company")
	local lede = UI.text(page, "italic", Stoa.typeSize.label, "muted", "LEFT")
	lede:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -6)
	lede:SetText("Click to whisper. Shift-click or right-click to invite.")

	self.tabs = {}
	for i, entry in ipairs({ { "friends", "Friends" }, { "guild", "Guild" } }) do
		local tab = UI.button(page, entry[2], 96, function()
			self.db.tab = entry[1]
			self.offset = 0
			self:Refresh()
		end)
		tab:SetPoint("TOPLEFT", PAD + (i - 1) * 104, -78)
		self.tabs[entry[1]] = tab
	end

	self.rows = {}
	for i = 1, ROWS do self.rows[i] = self:BuildRow(page, i) end
	self.empty = UI.text(page, "italic", Stoa.typeSize.label, "muted")
	self.empty:SetPoint("TOPLEFT", PAD + 4, -118)

	self.offset = 0
	page:EnableMouseWheel(true)
	page:SetScript("OnMouseWheel", function(_, delta)
		local maxOffset = math.max(#(self.list or {}) - ROWS, 0)
		self.offset = math.min(math.max(self.offset - delta * 3, 0), maxOffset)
		self:Refresh()
	end)

	local count = UI.text(page, "sans", Stoa.typeSize.caption + 1, "muted", "LEFT")
	count:SetPoint("BOTTOMLEFT", PAD, PAD)
	self.count = count
	local close = UI.button(page, "Close", 80, function() page:Hide() end)
	close:SetPoint("BOTTOMRIGHT", -PAD, PAD - 8)

	page:SetScript("OnShow", function()
		-- The guild list only fills after the server answers.
		if IsInGuild() and C_GuildInfo and C_GuildInfo.GuildRoster then C_GuildInfo.GuildRoster() end
	end)
	UI.applyTheme()
end

function Roster:Refresh()
	if not (self.page and self.page:IsShown()) then return end
	local tab = self.db.tab == "guild" and "guild" or "friends"
	for name, button in pairs(self.tabs) do button:SetSelected(name == tab) end
	local list = tab == "guild" and gatherGuild() or gatherFriends()
	table.sort(list, function(a, b) return a.label < b.label end)
	self.list = list
	self.offset = math.min(self.offset or 0, math.max(#list - ROWS, 0))
	for i, row in ipairs(self.rows) do
		local entry = list[i + self.offset]
		row.entry = entry
		if entry then
			row.name:SetText(entry.label)
			row.name:SetTextColor(classColour(entry.class))
			row.level:SetText(entry.level and entry.level > 0 and entry.level or "")
			local where = entry.zone or ""
			if entry.note ~= "" then where = entry.note .. "  " .. where end
			row.zone:SetText(where)
			row:Show()
		else
			row:Hide()
		end
	end
	if tab == "guild" and not IsInGuild() then
		self.empty:SetText("You're not in a guild.")
	else
		self.empty:SetText(#list == 0 and "Nobody's online right now." or "")
	end
	self.count:SetText(#list == 1 and "1 online" or (#list .. " online"))
end

function Roster:Toggle()
	if not self.page then self:Build() end
	if self.page:IsShown() then
		self.page:Hide()
	else
		self.offset = 0
		self.page:Show()
		self:Refresh()
	end
end

function Roster:OnEnable()
	local function refresh() xpcall(self.Refresh, Stoa.catch, self) end
	for _, event in ipairs({ "FRIENDLIST_UPDATE", "BN_FRIEND_INFO_CHANGED", "BN_FRIEND_ACCOUNT_ONLINE",
		"BN_FRIEND_ACCOUNT_OFFLINE", "GUILD_ROSTER_UPDATE", "GROUP_ROSTER_UPDATE" }) do
		Stoa:On(event, refresh)
	end
end

Stoa.commands.friends = function() Roster:Toggle() end
Stoa.commands.company = Stoa.commands.friends
