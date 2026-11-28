-- Stoa: more Blizzard windows in the same dress as the quest and merchant
-- windows (see Windows.lua): spellbook and talents, world map border, mail,
-- auction house, group finder, friends and guild, the bank, trade,
-- professions, wardrobe, journals, macros and the other framed windows.
--
-- Many of these load with their own addon the first time they open, so each
-- is dressed when its frame turns up (ADDON_LOADED) and again on first show.
-- Every frame name is looked up and skipped silently if this client lacks it.
-- Only a window's own border art is hidden; maps, pins, icons and lists stay
-- exactly as Blizzard draws them.
local _, ns = ...
local Stoa = ns.Stoa
-- Hooks on the game's code are guarded (Core/Report.lua).
local hooksecurefunc = Stoa.SafeHook
local UI = Stoa.UI

local More = Stoa:NewModule("MoreWindows")

-- How each window is dressed: the default is the full Windows:Dress; "border"
-- only hides the stone edge and puts a Stoa panel behind; "map" dresses the
-- world map's border frame alone. "parts" are extra named frames whose own
-- art is hidden (insets and money bars).
local TARGETS = {
	-- Talents and the spellbook fill their window right up to its top edge
	-- with their own art, which covered the lower half of the metal strip,
	-- so the whole strip rises above the window instead.
	{ name = "PlayerSpellsFrame", band = 0, raise = 42 },
	{ name = "SpellBookFrame", band = 24 },
	{ name = "PlayerTalentFrame" },
	{ name = "TalentFrame" },
	-- Send Mail's To row starts 30px down with the letter close beneath it,
	-- so the strip stays short to leave the row some air.
	{ name = "MailFrame", band = 24, parts = { "MailFrameInset", "SendMailMoneyInset", "SendMailMoneyBg" }, hides = { "InboxFrameBg" } },
	{ name = "OpenMailFrame", parts = { "OpenMailFrameInset" } },
	{ name = "AuctionHouseFrame" },
	{ name = "PVEFrame" },
	{ name = "LFDParentFrame" },
	-- Forever's Looking For Group: a bare parent (close, the eye, three
	-- side tabs) over three framed pages, one shown at a time.
	{ name = "LFGListingFrame", after = "lfg" },
	{ name = "LFGBrowseFrame", after = "lfg" },
	{ name = "LFGWhoListFrame", after = "lfg" },
	{ name = "FriendsFrame", parts = { "FriendsFrameInset", "WhoFrameListInset", "WhoFrameEditBoxInset" } },
	-- Forever's friends window is the newer social window: the Battle.net
	-- bar starts 22px down, so the strip stays short, and its tabs hang
	-- down the right edge as icon tiles.
	{ name = "SocialUIFrame", band = 24, after = "social" },
	-- A slimmer band: the channel dropdown and online count start just
	-- under the title, and the usual band reached halfway down them.
	{ name = "CommunitiesFrame", band = 30, after = "communities" },
	-- The rest of Blizzard's framed windows, in the same dress.
	{ name = "BankFrame" },
	{ name = "GuildBankFrame", mode = "border" },
	{ name = "TradeFrame" },
	{ name = "ProfessionsFrame", after = "professions" },
	{ name = "ProfessionsBookFrame", deep = 2 },
	-- The item list beside the model is its own panel hanging off the side.
	{ name = "DressUpFrame", panels = { "CustomSetDetailsPanel" }, after = "dressup" },
	{ name = "ItemTextFrame", after = "book" },
	{ name = "MacroFrame", after = "macro" },
	{ name = "CollectionsJournal", deep = 3, after = "collections" },
	{ name = "EncounterJournal" },
	{ name = "StableFrame" },
	{ name = "TabardFrame" },
	{ name = "PetitionFrame" },
	{ name = "GuildRegistrarFrame" },
	{ name = "ItemSocketingFrame" },
	{ name = "TimeManagerFrame" },
	{ name = "ChannelFrame" },
	{ name = "AddonList", buttons = { "EnableAllButton", "DisableAllButton", "OkayButton", "CancelButton" }, after = "addons" },
	{ name = "ClickBindingFrame" },
	-- The game menu and the settings panel are left alone: addons touching
	-- them are a known cause of blocked-action errors (Edit Mode, logout).
	-- The map canvas, pins and quest panel are never touched.
	{ name = "WorldMapFrame", mode = "map" },
	-- The flight map is built like the world map: a border frame over a
	-- canvas. Its parchment, flight points and routes stay the game's.
	{ name = "FlightMapFrame", mode = "map" },
}

local hide = Stoa.frames.hide

-- `keep`: textures Stoa drew on this frame itself, which stay.
local function hideOwnArt(frame, keep)
	if not (frame and frame.GetRegions) then return end
	for _, region in ipairs({ frame:GetRegions() }) do
		if region.IsObjectType and region:IsObjectType("Texture") and not (keep and keep[region]) then region:SetAlpha(0) end
	end
	hide(frame.NineSlice)
	hide(frame.Bg)
end

local function forbidden(frame)
	return frame.IsForbidden and frame:IsForbidden()
end

-- The edge only: stone border, portrait and title strip out, a Stoa panel in.
local function dressBorder(frame, bare)
	local windows = Stoa.modules.Windows
	if frame.stoaBorderDressed or (windows and windows.Leaves and windows:Leaves(frame)) then return end
	frame.stoaBorderDressed = true
	hideOwnArt(frame)
	for _, key in ipairs({ "TopTileStreaks", "PortraitContainer", "PortraitOverlay", "portrait", "PortraitFrame" }) do
		hide(frame[key])
	end
	if frame.TitleContainer then hideOwnArt(frame.TitleContainer) end
	local name = frame.GetName and frame:GetName()
	-- Header and footer as on the common windows, but nothing of the
	-- window's own is moved.
	UI.windowPanel(frame, nil, {
		header = frame.Inset or (windows and windows.HEADER_FALLBACK) or 30,
		footer = frame.Inset,
		family = windows and windows.FAMILY and windows.FAMILY[name or ""],
		bare = bare,
		plainHeader = true,
	})
	local title = frame.TitleContainer and frame.TitleContainer.TitleText or frame.TitleText
	if title and title.SetTextColor then
		Stoa:SetFont(title, "serif", Stoa.typeSize.title)
		title:SetTextColor(Stoa:Color("text"))
	end
	-- The band settles to the shared height on show, as on the common
	-- windows (Windows:Settle only resizes it; nothing of the window's own
	-- moves, since no title or close is seated without a full dress).
	if windows and windows.KeepSettled then
		frame.stoaBorderOnly = true
		-- The map's strip stays compact: its zone buttons start just under it.
		if bare then frame.stoaBandHeight = 24 end
		windows:KeepSettled(frame)
	end
end

local function dressFull(frame)
	local windows = Stoa.modules.Windows
	if windows and windows.Dress then windows:Dress(frame) else dressBorder(frame) end
end

-- The map's close cross and maximise button: quiet glyphs, centred in the
-- header band and set in from the right edge, as on every other window.
local MAP_BUTTON_INSET = 10
local function seatMapButtons(border)
	local header, close = border.stoaHeader, border.CloseButton
	if not (header and close) or InCombatLockdown() then return end
	close:ClearAllPoints()
	close:SetPoint("RIGHT", header, "RIGHT", -MAP_BUTTON_INSET, 0)
	local maxMin = border.MaximizeMinimizeFrame
	if maxMin then
		maxMin:ClearAllPoints()
		maxMin:SetPoint("RIGHT", close, "LEFT", -2, 0)
	end
end

local function dressMapButtons(border)
	local windows = Stoa.modules.Windows
	if not windows or border.stoaMapButtons then return end
	border.stoaMapButtons = true
	if windows.DressClose then windows.DressClose(border.CloseButton) end
	if windows.DressMaxMin then windows.DressMaxMin(border.MaximizeMinimizeFrame) end
	if windows.OnSettle then windows:OnSettle(border, seatMapButtons) end
	seatMapButtons(border)
end

local dressInner
local function dressTarget(target, frame)
	if target.mode == "border" then
		dressBorder(frame)
	elseif target.mode == "map" then
		-- The border frame holds the stone edge and title, and it is drawn
		-- above the canvas, so it gets the edge and header only: a fill or
		-- the stone there would cover the map.
		if frame.BorderFrame then
			dressBorder(frame.BorderFrame, true)
			dressMapButtons(frame.BorderFrame)
		end
		-- A panel behind everything, on the map frame itself: its textures
		-- draw under the canvas and the quest log, so only the margins
		-- around them (and the gap between) show it.
		if not frame.stoaMapFill then
			-- (Flush with the border frame's edge: drawn larger, it showed as a
			-- second, lighter border around the header.)
			local fill = UI.sliced(frame, "BACKGROUND", "WindowFill.tga", 0)
			if fill then
				fill:SetDrawLayer("BACKGROUND", -8)
				UI.tint(fill, "panel")
				frame.stoaMapFill = fill
			end
		end
		-- The quest log's red buttons, as on every other window.
		local windows = Stoa.modules.Windows
		local details = QuestMapFrame and QuestMapFrame.DetailsFrame
		if windows and windows.DressButtonsIn and details then windows.DressButtonsIn(details, 3) end
	else
		if target.band then frame.stoaBandHeight = target.band end
		if target.raise then frame.stoaRaise = target.raise end
		dressFull(frame)
	end
	for _, partName in ipairs(target.parts or {}) do
		local part = _G[partName]
		if type(part) == "table" and not forbidden(part) then hideOwnArt(part) end
	end
	dressInner(target, frame)
end

-- Inside a window: Blizzard's insets (stone and edge), card backdrops
-- (profession cards, the pet card's painted scene) and their shadowed
-- corners go, down a few levels; a card that loses its backdrop gets a dark
-- Stoa well instead. Buttons, bars and edit boxes (and their icons) are
-- never touched, nor are lists and models.
local KEEP = { Button = true, CheckButton = true, StatusBar = true, EditBox = true, Cooldown = true, ModelScene = true, PlayerModel = true, DressUpModel = true }
local BACKDROPS = { "Background", "PetBackground", "MountBackground", "BG", "YesMountsTex", "NoMountsTex" }

local function clearInside(frame, depth)
	if not (frame and frame.GetChildren) or depth <= 0 then return end
	for _, child in ipairs({ frame:GetChildren() }) do
		local kind = not forbidden(child) and child.GetObjectType and child:GetObjectType()
		if kind and not KEEP[kind] then
			if child.NineSlice then
				hide(child.NineSlice)
				if child.Bg and child.Bg.SetAlpha then child.Bg:SetAlpha(0) end
			end
			hide(child.ShadowOverlay)
			-- A collections page backdrop (toys, heirlooms, appearances): a
			-- tiled ground with gilded corners and a watermark, all of it art.
			if child.BackgroundTile then
				Stoa.frames.strip(child)
				if not child.stoaWell then UI.well(child, 0) end
			end
			for _, key in ipairs(BACKDROPS) do
				local tex = child[key]
				if type(tex) == "table" and tex.IsObjectType and tex:IsObjectType("Texture") then
					tex:SetAlpha(0)
					if not child.stoaWell then UI.well(child, 0) end
				end
			end
			clearInside(child, depth - 1)
		end
	end
end

-- A panel of a window's own that hangs outside it: all its art out, a Stoa
-- panel of its own in.
local function dressSidePanel(panel)
	if not panel or forbidden(panel) then return end
	-- This runs on every show; Stoa's own ground is a texture of the panel
	-- too, so it is told apart or the second show would clear it.
	hideOwnArt(panel, panel.stoaSideArt)
	if panel.stoaSideArt then return end
	local before, mine = {}, {}
	for _, region in ipairs({ panel:GetRegions() }) do before[region] = true end
	UI.windowPanel(panel, nil, {})
	for _, region in ipairs({ panel:GetRegions() }) do
		if not before[region] then mine[region] = true end
	end
	panel.stoaSideArt = mine
end

function dressInner(target, frame)
	if target.deep then clearInside(frame, target.deep) end
	for _, key in ipairs(target.panels or {}) do dressSidePanel(frame[key]) end
	for _, texName in ipairs(target.hides or {}) do
		local tex = _G[texName]
		if type(tex) == "table" and tex.SetAlpha then tex:SetAlpha(0) end
	end
	local windows = Stoa.modules.Windows
	if windows and windows.DressButton then
		for _, key in ipairs(target.buttons or {}) do
			local button = frame[key]
			if type(button) == "table" and not forbidden(button) then windows.DressButton(button) end
		end
	end
end

-- Guild & Communities (layout A, Tyler 2026-11-23): a bigger window, the
-- guild's or community's name and who is online as the header's title,
-- Chat, Roster, Perks and Info as words along the header's right, and the
-- message of the day on its own row over the chat and member list.
-- Blizzard sets the window's size and places its parts again whenever it
-- lays the window out (club, tab, maximise, minimise), always ending in
-- UpdateUIPanelPositions, where this runs again. Only top anchors of the
-- parts move (the bottoms stay); minimised, the window keeps Blizzard's
-- small size and only the old 10px drop.
local GUILD_W, GUILD_H = 1100, 640
local MOTD_ROW = 26
local COMMUNITIES_DROP = 10
local COMMUNITIES_PARTS = {
	"StreamDropdown", "CommunitiesListDropdown", "VoiceChatHeadset", "Chat",
}
-- Blizzard's content starts under a 23px title strip; STOA's header is
-- taller, so the content drops by the difference plus a little air.
local BLIZZARD_STRIP, CONTENT_AIR = 23, 8
-- The roster's member list (wide, with column heads 60px above its top) and
-- its two view dropdowns are placed by guildRoster instead.
local ROSTER_DROPDOWNS = { "GuildMemberListDropdown", "CommunityMemberListDropdown" }
local guildRoster, guildInner, guildChatRow, relayoutGuild
-- The side tabs, in header order, with their words.
local GUILD_TABS = {
	{ "ChatTab", "Chat" }, { "RosterTab", "Roster" }, { "GuildBenefitsTab", "Perks" },
	{ "GuildInfoTab", "Info" }, { "GuildPreferredPlaySettingsTab", "Settings" },
}
local TAB_GAP = 20

-- Each part is moved once per placing: Blizzard puts it back whenever it
-- lays the window out again, and the drop follows. A changed drop (the MOTD
-- row comes and goes with the page) moves it by the difference.
local function dropTops(part, amount)
	amount = amount or COMMUNITIES_DROP
	if not (part and part.GetNumPoints) or forbidden(part) then return end
	part.stoaDropped = part.stoaDropped or {}
	part.stoaDropBy = part.stoaDropBy or {}
	local points = {}
	for i = 1, part:GetNumPoints() do points[i] = { part:GetPoint(i) } end
	local moved = false
	for _, p in ipairs(points) do
		local point, y = p[1], p[5] or 0
		if type(point) == "string" and point:find("^TOP") then
			if part.stoaDropped[point] ~= y then
				-- Blizzard's own placing: drop it by the whole amount.
				p[5] = y - amount
				moved = true
			elseif part.stoaDropBy[point] ~= amount then
				-- Already dropped: move by the change only.
				p[5] = y - (amount - (part.stoaDropBy[point] or 0))
				moved = true
			end
			if moved then
				part.stoaDropped[point] = p[5]
				part.stoaDropBy[point] = amount
			end
		end
	end
	if not moved then return end
	part:ClearAllPoints()
	for _, p in ipairs(points) do part:SetPoint(p[1], p[2], p[3], p[4] or 0, p[5] or 0) end
end

local function guildMinimized(frame)
	local modes = rawget(_G, "COMMUNITIES_FRAME_DISPLAY_MODES")
	return modes and frame.GetDisplayMode and frame:GetDisplayMode() == modes.MINIMIZED
end

-- Chat and roster show the member list and channel row; the perks, info
-- and finder pages fill the window their own way and get no MOTD row.
local function guildListMode(frame)
	local modes = rawget(_G, "COMMUNITIES_FRAME_DISPLAY_MODES")
	if not (modes and frame.GetDisplayMode) then return false end
	local mode = frame:GetDisplayMode()
	return mode == modes.CHAT or mode == modes.ROSTER
end

local function selectedClub(frame)
	local id = frame.GetSelectedClubId and frame:GetSelectedClubId()
	return id and C_Club and C_Club.GetClubInfo and C_Club.GetClubInfo(id)
end

local function isGuild(info)
	local guildType = Enum and Enum.ClubType and Enum.ClubType.Guild
	return info and guildType ~= nil and info.clubType == guildType
end

-- Which page word is lit follows the window's page, not the tab's own
-- checked state: a click toggles a check button without Blizzard
-- unchecking the old one in a way the words saw.
local function chosenGuildTab(frame)
	local modes = rawget(_G, "COMMUNITIES_FRAME_DISPLAY_MODES")
	local mode = modes and frame.GetDisplayMode and frame:GetDisplayMode()
	if not mode then return nil end
	for _, entry in ipairs(GUILD_TABS) do
		local tab = frame[entry[1]]
		if type(tab) == "table" and tab.displayMode ~= nil and tab.displayMode == mode then return tab end
	end
	if mode == modes.CHAT then return frame.ChatTab end
	if mode == modes.ROSTER or (frame.IsShowingApplicantList and frame:IsShowingApplicantList()) then return frame.RosterTab end
	if mode == modes.GUILD_BENEFITS then return frame.GuildBenefitsTab end
	if mode == modes.GUILD_INFO then return frame.GuildInfoTab end
	if mode == modes.GUILD_PREFERRED_PLAY_SETTINGS then return frame.GuildPreferredPlaySettingsTab end
end

local function paintGuildTab(tab)
	local word = tab.stoaGuildWord
	if not word then return end
	local parent = tab:GetParent()
	local chosen = parent and tab:IsShown() and chosenGuildTab(parent) == tab
	word:SetTextColor(Stoa:Color(chosen and "text" or "muted"))
	local line = tab.stoaGuildLine
	line:SetColorTexture(Stoa:Color("accent"))
	line:SetShown(chosen and true or false)
end

local function paintGuildTabs(frame)
	for _, entry in ipairs(GUILD_TABS) do
		local tab = frame[entry[1]]
		if type(tab) == "table" and tab.stoaGuildWord then paintGuildTab(tab) end
	end
end

-- /stoa guild: what the page words see, for a report when they look wrong.
local function modeName(mode)
	local modes = rawget(_G, "COMMUNITIES_FRAME_DISPLAY_MODES")
	if mode == nil then return "nil" end
	for key, value in pairs(modes or {}) do if value == mode then return key end end
	return tostring(mode)
end

Stoa.commands.guild = function()
	local frame = rawget(_G, "CommunitiesFrame")
	if type(frame) ~= "table" then Stoa:Print("guild window not loaded") return end
	local mode = frame.GetDisplayMode and frame:GetDisplayMode()
	local chosen = chosenGuildTab(frame)
	Stoa:Print("page:", modeName(mode), "lit:", chosen and chosen.stoaGuildWord and chosen.stoaGuildWord:GetText() or "none")
	for _, entry in ipairs(GUILD_TABS) do
		local tab = frame[entry[1]]
		if type(tab) == "table" then
			Stoa:Print(entry[2], "shown", tostring(tab:IsShown()), "checked", tostring(tab:GetChecked()),
				"mode", modeName(tab.displayMode), "line", tostring(tab.stoaGuildLine and tab.stoaGuildLine:IsShown()))
		end
	end
end

-- Each page tab is faded out whole (its own art, checked glow and all) and
-- its word and underline live on a cover that ignores the fade and lets
-- the mouse through to the tab. Only paintGuildTab, by the window's page,
-- ever shows the underline.
local function guildTabWord(tab, label)
	if type(tab) ~= "table" or forbidden(tab) or tab.stoaGuildWord then return end
	tab:SetAlpha(0)
	local cover = CreateFrame("Frame", nil, tab)
	cover:SetAllPoints()
	cover:SetIgnoreParentAlpha(true)
	cover:EnableMouse(false)
	local word = cover:CreateFontString(nil, "OVERLAY")
	Stoa:SetFont(word, "sans", Stoa.typeSize.label)
	word:SetJustifyH("CENTER")
	word:SetPoint("CENTER", 0, 1)
	word:SetText(label)
	local line = cover:CreateTexture(nil, "OVERLAY")
	line:SetTexture(UI.WHITE)
	line:SetHeight(2)
	line:SetPoint("TOPLEFT", word, "BOTTOMLEFT", 0, -4)
	line:SetPoint("TOPRIGHT", word, "BOTTOMRIGHT", 0, -4)
	line:Hide()
	tab.stoaGuildWord, tab.stoaGuildLine, tab.stoaGuildCover = word, line, cover
	hooksecurefunc(tab, "SetChecked", paintGuildTab)
	-- Painted from PreClick, not OnClick: when anything in Blizzard's page
	-- switch errors, OnClick's hooks never run and the old word stayed lit.
	-- The timer paints once the switch is done, whatever happened in it.
	tab:HookScript("PreClick", function(self)
		local frame = self:GetParent()
		C_Timer.After(0, function()
			paintGuildTabs(frame)
			-- The page's layout (the MOTD row, the drops) too, for the same
			-- reason: Blizzard's own relayout may never have run.
			if relayoutGuild then relayoutGuild(frame) end
		end)
	end)
	tab:HookScript("OnEnter", function(self) if not self.stoaGuildLine:IsShown() then self.stoaGuildWord:SetTextColor(Stoa:Color("accent")) end end)
	tab:HookScript("OnLeave", paintGuildTab)
	paintGuildTab(tab)
end

-- The words sit right to left from the minimise button, the shown ones
-- only, level with the close cross.
local function placeGuildTabs(frame)
	if not frame.stoaHeader or InCombatLockdown() then return end
	local anchor, gap = frame.MaximizeMinimizeFrame or frame.CloseButton, 12
	frame.stoaFirstGuildTab = nil
	for i = #GUILD_TABS, 1, -1 do
		local tab = frame[GUILD_TABS[i][1]]
		if type(tab) == "table" and not forbidden(tab) then
			guildTabWord(tab, GUILD_TABS[i][2])
			if tab:IsShown() and tab.stoaGuildWord and anchor then
				-- Above every part of the window, so nothing Blizzard lays
				-- out near the top can take the clicks.
				-- That includes the title strip, which Forever keeps at
				-- frame level 510 and which took the words' lower half.
				local level = frame:GetFrameLevel() + 120
				local strip = frame.TitleContainer
				if strip and strip.GetFrameLevel then level = math.max(level, strip:GetFrameLevel() + 5) end
				tab:SetFrameLevel(level)
				tab:SetSize(math.ceil(tab.stoaGuildWord:GetStringWidth()) + 8, 26)
				tab:ClearAllPoints()
				tab:SetPoint("RIGHT", anchor, "LEFT", -gap, 0)
				anchor, gap = tab, TAB_GAP
				frame.stoaFirstGuildTab = tab
			end
		end
	end
end

-- The title: the club's name in the serif, who is online under it.
local function guildTitle(frame)
	local header = frame.stoaHeader
	if not header then return end
	if not frame.stoaGuildTitle then
		frame.stoaOwnTitle = true
		local blizzard = frame.TitleContainer and frame.TitleContainer.TitleText or frame.TitleText
		if blizzard then blizzard:SetAlpha(0) end
		local title = UI.text(frame, "serif", Stoa.typeSize.title, "text")
		title:SetShadowColor(0, 0, 0, 0.9)
		title:SetShadowOffset(1, -1)
		title:SetWordWrap(false)
		local sub = UI.text(frame, "sans", Stoa.typeSize.caption, "muted")
		sub:SetWordWrap(false)
		frame.stoaGuildTitle, frame.stoaGuildSub = title, sub
	end
	local title, sub = frame.stoaGuildTitle, frame.stoaGuildSub
	local info = selectedClub(frame)
	local name = info and info.name
	if type(name) ~= "string" or name == "" then name = "Guild & Communities" end
	title:SetText(name)
	local line = "Guild & Communities"
	if isGuild(info) and GetNumGuildMembers then
		local total, online = GetNumGuildMembers()
		if type(total) == "number" and total > 0 then
			line = string.format("%d of %d online", tonumber(online) or 0, total)
		end
	elseif info and type(info.memberCount) == "number" then
		line = string.format("Community · %d members", info.memberCount)
	end
	sub:SetText(line)
	local small = guildMinimized(frame)
	local right = frame.stoaFirstGuildTab or frame.MaximizeMinimizeFrame or header
	title:ClearAllPoints()
	sub:ClearAllPoints()
	if small then
		-- No room for two lines: the name alone.
		title:SetPoint("LEFT", header, "LEFT", 18, 0)
		title:SetPoint("RIGHT", frame.MaximizeMinimizeFrame or header, "LEFT", -8, 0)
	else
		-- One line: the name, a fine rule, then who is online, all on the
		-- header's middle. A long name gives way to the page words.
		local room = (right:GetLeft() or 0) - (header:GetLeft() or 0) - 18 - 16 - sub:GetStringWidth() - 26
		title:SetPoint("LEFT", header, "LEFT", 18, 0)
		if room > 40 then title:SetWidth(math.min(title:GetStringWidth() + 2, room)) end
		sub:SetPoint("LEFT", title, "RIGHT", 26, -1)
		if not frame.stoaGuildRule then
			local rule = frame:CreateTexture(nil, "ARTWORK")
			rule:SetTexture(UI.WHITE)
			rule:SetSize(1, 14)
			UI.pixel(rule, "width")
			UI.tint(rule, "hairline")
			frame.stoaGuildRule = rule
		end
		frame.stoaGuildRule:ClearAllPoints()
		frame.stoaGuildRule:SetPoint("LEFT", title, "RIGHT", 13, 0)
	end
	sub:SetShown(not small)
	if frame.stoaGuildRule then frame.stoaGuildRule:SetShown(not small) end
end

-- The message of the day (a guild's, or a community's broadcast) on its
-- own row between the header and the channel row, from the club list's
-- edge to the window's.
local LIST_EDGE = 172
local function guildMotd(frame, shown)
	if not frame.stoaMotd then
		local row = CreateFrame("Frame", nil, frame)
		row:SetHeight(MOTD_ROW)
		local fill = row:CreateTexture(nil, "BACKGROUND")
		fill:SetAllPoints()
		UI.tint(fill, "accent", 0.05)
		local rule = UI.line(row, "hairline")
		rule:SetPoint("BOTTOMLEFT")
		rule:SetPoint("BOTTOMRIGHT")
		local label = UI.text(row, "sans", Stoa.typeSize.micro, "accent")
		label:SetPoint("LEFT", 14, 0)
		label:SetText("MESSAGE OF THE DAY")
		local text = UI.text(row, "sans", Stoa.typeSize.body, "text")
		text:SetPoint("LEFT", label, "RIGHT", 10, 0)
		text:SetPoint("RIGHT", -14, 0)
		text:SetWordWrap(false)
		row.text = text
		frame.stoaMotd = row
		UI.applyTheme()
	end
	local row = frame.stoaMotd
	if shown then
		local band = (frame.stoaHeader and frame.stoaHeader.stoaHeight) or 30
		row:ClearAllPoints()
		row:SetPoint("TOPLEFT", frame, "TOPLEFT", LIST_EDGE, -band - 2)
		row:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -2, -band - 2)
		local info = selectedClub(frame)
		local motd = info and info.broadcast
		if isGuild(info) and GetGuildRosterMOTD then
			local own = GetGuildRosterMOTD()
			if type(own) == "string" and own ~= "" then motd = own end
		end
		if type(motd) ~= "string" or motd == "" then
			row.text:SetText("None set")
			row.text:SetTextColor(Stoa:Color("muted"))
		else
			row.text:SetText((motd:gsub("\n", " ")))
			row.text:SetTextColor(Stoa:Color("text"))
		end
	end
	row:SetShown(shown and true or false)
end

local function sizeGuild(frame)
	if guildMinimized(frame) then return end
	local w, h = frame:GetSize()
	if math.abs(w - GUILD_W) > 0.5 or math.abs(h - GUILD_H) > 0.5 then frame:SetSize(GUILD_W, GUILD_H) end
end

-- Guild > Info's news filters: a small pop-over of its own (a translucent
-- stone frame on UIParent). The stone gives way to a Stoa card, the title
-- takes the text colour and the close its quiet cross; under Slate the
-- ticks become STOA's squares.
local function dressNewsFilters()
	local pop = rawget(_G, "CommunitiesGuildNewsFiltersFrame")
	if type(pop) ~= "table" or pop.stoaDressed or forbidden(pop) then return end
	pop.stoaDressed = true
	-- The stone edge is a child frame of border pieces (its key differs
	-- between clients), so every child that isn't a button loses its art.
	hideOwnArt(pop)
	hide(pop.Border)
	for _, child in ipairs({ pop:GetChildren() }) do
		if not forbidden(child) and not (child.IsObjectType and child:IsObjectType("Button")) then
			hideOwnArt(child)
		end
	end
	UI.surface(pop, "card", { alpha = 0.98 })
	if pop.Title and pop.Title.SetTextColor then
		Stoa:SetFont(pop.Title, "serif", Stoa.typeSize.label)
		pop.Title:SetTextColor(Stoa:Color("text"))
	end
	local windows = Stoa.modules.Windows
	if windows and windows.DressClose then windows.DressClose(pop.CloseButton) end
	if windows and windows.DressButtonsIn then windows.DressButtonsIn(pop, 2) end
end

local AFTER = {}
local wardrobeTabs
function AFTER.communities(frame)
	xpcall(dressNewsFilters, Stoa.catch)
	-- Its minimise button was the last red one in the header.
	local windows = Stoa.modules.Windows
	if windows and windows.DressMaxMin then windows.DressMaxMin(frame.MaximizeMinimizeFrame) end
	if not frame.stoaGuildHooks then
		frame.stoaGuildHooks = true
		if frame.UpdateCommunitiesTabs then
			hooksecurefunc(frame, "UpdateCommunitiesTabs", function(own)
				if not InCombatLockdown() then xpcall(AFTER.communities, Stoa.catch, own) end
				paintGuildTabs(own)
			end)
		end
		-- Every page change and every opening repaints the words, whatever
		-- path Blizzard took to get there.
		if frame.SetDisplayMode then
			hooksecurefunc(frame, "SetDisplayMode", function(own) paintGuildTabs(own) end)
		end
		frame:HookScript("OnShow", function(own) paintGuildTabs(own) end)
		-- Who is online and the message change while the window is open.
		for _, event in ipairs({ "GUILD_ROSTER_UPDATE", "GUILD_MOTD", "CLUB_UPDATED" }) do
			Stoa:On(event, function()
				if not (frame:IsShown() and frame.stoaGuildTitle) then return end
				xpcall(guildTitle, Stoa.catch, frame)
				if frame.stoaMotd and frame.stoaMotd:IsShown() then xpcall(guildMotd, Stoa.catch, frame, true) end
			end)
		end
	end
	if InCombatLockdown() or not frame:IsShown() then return end
	sizeGuild(frame)
	local small = guildMinimized(frame)
	local listMode = not small and guildListMode(frame)
	local band = (frame.stoaHeader and frame.stoaHeader.stoaHeight) or 30
	local base = small and COMMUNITIES_DROP or math.max(COMMUNITIES_DROP, band + 2 - BLIZZARD_STRIP + CONTENT_AIR)
	-- The MOTD row takes its room only on the chat and roster pages; the
	-- club list beside it (and the pages hung from it) drop by the base.
	local drop = listMode and (base + MOTD_ROW) or base
	for _, key in ipairs(COMMUNITIES_PARTS) do
		-- Maximised, the chat and the headset are placed under the channel
		-- dropdown instead (guildChatRow).
		if small or (key ~= "Chat" and key ~= "VoiceChatHeadset") then dropTops(frame[key], drop) end
	end
	-- The club column starts right under the header, beside the MOTD row.
	dropTops(frame.CommunitiesList, small and 0 or math.max(0, band + 2 - BLIZZARD_STRIP))
	frame.stoaGuildDrop = drop
	guildRoster(frame, drop)
	if not small then xpcall(guildChatRow, Stoa.catch, frame, drop) end
	xpcall(guildInner, Stoa.catch, frame)
	placeGuildTabs(frame)
	paintGuildTabs(frame)
	guildTitle(frame)
	guildMotd(frame, listMode)
end

relayoutGuild = function(frame)
	if InCombatLockdown() or not frame:IsShown() then return end
	xpcall(AFTER.communities, Stoa.catch, frame)
end

local function dressMacroSlot(button)
	if type(button) ~= "table" or button.stoaSlot or forbidden(button) then return end
	button.stoaSlot = true
	for _, region in ipairs({ button:GetRegions() }) do
		if region.IsObjectType and region:IsObjectType("Texture") and region:GetDrawLayer() == "BACKGROUND" then
			region:SetAlpha(0)
		end
	end
	UI.well(button, 1)
end

local MACRO_TAB_DROP = 9

-- Macros: the "Create Macros" line is the window's title, unnamed and in
-- Blizzard's small yellow; it takes the title's place in the header.
function AFTER.macro(frame)
	if frame.stoaMacroTitle or not frame.stoaHeader then return end
	for _, region in ipairs({ frame:GetRegions() }) do
		if region.IsObjectType and region:IsObjectType("FontString") and region:GetText() == CREATE_MACROS then
			frame.stoaMacroTitle = region
			Stoa:SetFont(region, "serif", Stoa.typeSize.title)
			region:SetTextColor(Stoa:Color("text"))
			region:SetShadowColor(0, 0, 0, 0.9)
			region:SetShadowOffset(1, -1)
			region:ClearAllPoints()
			region:SetPoint("LEFT", frame.stoaHeader, "LEFT", 18, 0)
			region:SetJustifyH("LEFT")
		end
	end
	-- The icon grid's stone slots become dark STOA wells. The grid's buttons
	-- are made as it scrolls, so each is dressed as it is set up.
	local selector = frame.MacroSelector
	if selector and selector.RunSetup and not selector.stoaSlotsHooked then
		selector.stoaSlotsHooked = true
		hooksecurefunc(selector, "RunSetup", function(_, button) dressMacroSlot(button) end)
		if selector.EnumerateButtons and selector.initialized then
			for button in selector:EnumerateButtons() do dressMacroSlot(button) end
		end
	end
	-- Its two tabs sit inside the window under the title, so they are words
	-- with the accent underline, not tiles.
	for _, tab in ipairs(frame.stoaTabs or {}) do
		for _, part in ipairs(tab.stoaTabParts or {}) do part:Hide() end
		tab.stoaWordOnly = true
		-- The tabs ride over the header's foot; their words sit a little
		-- below it, with air above.
		tab.stoaWordDrop = MACRO_TAB_DROP
	end
	local windows = Stoa.modules.Windows
	if windows and windows.ColourTabs then windows.ColourTabs(frame) end
end

-- Collections: each page's count pill ("Total Mounts 2") moves from the top
-- of the page to the bottom right of the window, in the footer, the same
-- place on every page.
local COUNT_PILLS = {
	{ "MountJournal", "MountCount" }, { "PetJournal", "PetCount" },
	{ "ToyBox", "progressBar" }, { "HeirloomsJournal", "progressBar" },
	{ "WardrobeCollectionFrame", "progressBar" },
}
local COUNT_INSET = { x = -14, y = 16 }
local function footPill(frame, page, key)
	local pill = page[key]
	if type(pill) ~= "table" or not pill.SetPoint or forbidden(pill) or InCombatLockdown() then return end
	pill:ClearAllPoints()
	pill:SetPoint("RIGHT", frame, "BOTTOMRIGHT", COUNT_INSET.x, COUNT_INSET.y)
end

function AFTER.collections(frame)
	wardrobeTabs()
	for _, spot in ipairs(COUNT_PILLS) do
		local page = _G[spot[1]]
		if type(page) == "table" and page.HookScript and not forbidden(page) then
			footPill(frame, page, spot[2])
			-- Pages lay themselves out again when their tab opens.
			if not page.stoaPillHooked then
				page.stoaPillHooked = true
				page:HookScript("OnShow", function() footPill(frame, page, spot[2]) end)
			end
		end
	end
end

-- Add-ons: the character dropdown, "Load out of date AddOns" and the
-- search start just under the title, half under the header band; they
-- (and the usage block under them, which the list hangs from) sit lower.
local ADDONS_DROP = 14
-- Dressing Room: the set field, Save and the item list switch in one row
-- over the model, edge to edge with it and all one height.
local DRESSUP_ROW_Y, DRESSUP_ROW_H = -44, 22
-- The model starts a little lower (the game's own top is -63), so the row
-- has air above and below it.
local DRESSUP_MODEL_TOP = -72

local function quietButtonArt(button)
	for _, getter in ipairs({ "GetNormalTexture", "GetPushedTexture", "GetHighlightTexture", "GetDisabledTexture" }) do
		local tex = button[getter] and button[getter](button)
		if tex then tex:SetAlpha(0) end
	end
end

-- A dark rounded ground with an edge that warms under the mouse.
local function dressField(button)
	UI.roundPanel(button, 0.95)
	local glow = UI.roundBorder(button, "CardEdge.tga", 1)
	button:HookScript("OnEnter", function() glow:Set(Stoa:Color("accent")) end)
	button:HookScript("OnLeave", function() glow:Clear() end)
	return glow
end

-- A WowStyle1 dropdown in STOA's dark field with a chevron.
local function dressDropdownField(dropdown)
	if dropdown.stoaField then return end
	dropdown.stoaField = true
	for _, key in ipairs({ "Background", "Arrow" }) do
		if dropdown[key] and dropdown[key].SetAlpha then dropdown[key]:SetAlpha(0) end
	end
	dressField(dropdown)
	local chevron = UI.glyph(dropdown, "Chevron", 12, "muted")
	chevron:SetPoint("RIGHT", -6, 0)
	chevron:SetRotation(-math.pi / 2)
	local text = dropdown.Text
	if text and text.SetTextColor then
		Stoa:SetFont(text, "sans", Stoa.typeSize.body)
		text:SetShadowOffset(0, 0)
		text:SetTextColor(Stoa:Color("text"))
	end
	UI.applyTheme()
end

-- The roster page: Blizzard hangs the wide member list from the club
-- list's top, with its column heads and "Show Offline Members" 60px above
-- it, which put them over the MOTD row and the view dropdown up in the
-- header (under the page words, taking their clicks). The list now hangs
-- below the MOTD row, the dropdown sits level with the offline box.
local ROSTER_HEAD = 64 + CONTENT_AIR
local function rosterTop(frame)
	local band = (frame.stoaHeader and frame.stoaHeader.stoaHeight) or 30
	return band + 2 + MOTD_ROW + ROSTER_HEAD
end

-- Blizzard's channel dropdown sits 31px down from the window's top.
local STREAM_TOP = 31
local function placeMemberList(frame, drop)
	local list = frame.MemberList
	if type(list) ~= "table" or forbidden(list) or InCombatLockdown() then return end
	if list.expandedDisplay and not guildMinimized(frame) then
		list:SetPoint("TOPLEFT", frame, "TOPLEFT", LIST_EDGE + 22, -rosterTop(frame))
	elseif not guildMinimized(frame) then
		-- Beside the chat: level with the channel dropdown.
		list:SetPoint("TOPLEFT", frame, "TOPRIGHT", -165, -(STREAM_TOP + drop))
	else
		dropTops(list, drop)
	end
end

-- The chat starts right under the channel dropdown, the headset sits at
-- the right end of that row, and the club list's rows start at its top
-- (Blizzard keeps 40px clear there for the dropdown the small window has).
guildChatRow = function(frame)
	local chat, stream = frame.Chat, frame.StreamDropdown
	if type(chat) == "table" and type(stream) == "table" and not forbidden(chat) then
		chat:SetPoint("TOPLEFT", stream, "BOTTOMLEFT", 6, -16)
		local headset = frame.VoiceChatHeadset
		if type(headset) == "table" and not forbidden(headset) then
			headset:ClearAllPoints()
			headset:SetPoint("RIGHT", chat, "TOPRIGHT", 8, 24)
		end
	end
	local list = frame.CommunitiesList
	local box = type(list) == "table" and list.ScrollBox
	if type(box) == "table" and not forbidden(box) then
		box:SetPoint("TOPLEFT", 0, 32)
	end
end

guildRoster = function(frame, drop)
	local list = frame.MemberList
	if type(list) == "table" and not forbidden(list) then
		if not list.stoaRosterHook and list.RefreshLayout then
			list.stoaRosterHook = true
			-- Blizzard places the list again when the page changes, after
			-- the window's own layout pass.
			hooksecurefunc(list, "RefreshLayout", function()
				local d = frame.stoaGuildDrop or COMMUNITIES_DROP
				xpcall(placeMemberList, Stoa.catch, frame, d)
			end)
		end
		placeMemberList(frame, drop)
		-- "35/113 Online" over the list: the header says it already.
		if list.MemberCount and list.MemberCount.SetAlpha then list.MemberCount:SetAlpha(0) end
		local offline = list.ShowOfflineButton
		if type(offline) == "table" and offline.Text and not offline.stoaWord then
			offline.stoaWord = true
			Stoa:SetFont(offline.Text, "sans", Stoa.typeSize.body)
			offline.Text:SetShadowOffset(0, 0)
			offline.Text:SetTextColor(Stoa:Color("muted"))
		end
	end
	local y = rosterTop(frame) - 42
	for _, key in ipairs(ROSTER_DROPDOWNS) do
		local dropdown = frame[key]
		if type(dropdown) == "table" and not forbidden(dropdown) then
			dressDropdownField(dropdown)
			dropdown:ClearAllPoints()
			dropdown:SetPoint("RIGHT", frame, "TOPRIGHT", -30, -y)
			dropdown:SetFrameLevel(frame:GetFrameLevel() + 20)
		end
	end
end

-- The inside of the guild window: Blizzard's blue stone club list, gold
-- bevels round the chat and member list, the gold channel dropdowns and the
-- marbled rows become STOA's dark column, wells and fields.
local function alphaOff(region)
	if region and region.SetAlpha then region:SetAlpha(0) end
end

local function quietInset(inset)
	if type(inset) ~= "table" or forbidden(inset) then return end
	alphaOff(inset.NineSlice)
	alphaOff(inset.Bg)
end

local function column(owner, alpha, side)
	if owner.stoaColumn then return end
	local fill = owner:CreateTexture(nil, "BACKGROUND", nil, -6)
	fill:SetTexture(UI.WHITE)
	fill:SetAllPoints()
	fill:SetVertexColor(0, 0, 0, alpha)
	-- The console's own seam between the columns, not a plain white line.
	local rule = UI.seam(owner)
	rule:SetPoint("TOP" .. side)
	rule:SetPoint("BOTTOM" .. side)
	owner.stoaColumn = fill
end

-- Each scroll list builds its rows as they scroll into view.
local function eachRow(scrollBox, key, fn)
	if type(scrollBox) ~= "table" or forbidden(scrollBox) or scrollBox[key] then return end
	scrollBox[key] = true
	if ScrollUtil and ScrollUtil.AddAcquiredFrameCallback then
		ScrollUtil.AddAcquiredFrameCallback(scrollBox, function(_, row) xpcall(fn, Stoa.catch, row) end, scrollBox, true)
	elseif scrollBox.ForEachFrame then
		scrollBox:ForEachFrame(function(row) xpcall(fn, Stoa.catch, row) end)
	end
end

-- A club in the list: a dark rounded tile, its name in the text colour, an
-- accent edge on the open one. Blizzard swaps the tile's atlas per club,
-- so its own art is only ever faded out, never replaced.
local function paintClub(row)
	if not row.stoaClubFill then return end
	local chosen = row.Selection and row.Selection:IsShown()
	-- The open club: a lifted tile with a fine rim and a short accent bar
	-- on its left, not a full bright outline.
	if chosen then row.stoaClubEdge:Set(Stoa:Color("hairline")) else row.stoaClubEdge:Clear() end
	row.stoaClubBar:SetShown(chosen and true or false)
	row.stoaClubBar:SetVertexColor(Stoa:Color("accent"))
	local r, g, b = Stoa:Color("panel")
	local lift = chosen and 0.05 or (row.stoaOver and 0.025 or 0)
	row.stoaClubFill:SetVertexColor(r + lift, g + lift, b + lift, chosen and 0.95 or (row.stoaOver and 0.8 or 0.55))
	-- The add and find tiles (no club) keep their icons quiet.
	local icon = row.Icon
	if icon and icon.SetDesaturated then
		local quiet = row.clubId == nil
		icon:SetDesaturated(quiet)
		icon:SetAlpha(quiet and 0.7 or 1)
	end
	local name = row.Name
	if name and name.SetTextColor then
		local enabled = not row.IsEnabled or row:IsEnabled()
		name:SetTextColor(Stoa:Color(enabled and "text" or "muted"))
	end
end

local function dressClub(row)
	if type(row) ~= "table" or forbidden(row) then return end
	for _, key in ipairs({ "Background", "Selection", "NewCommunityFlash" }) do alphaOff(row[key]) end
	alphaOff(row.GetHighlightTexture and row:GetHighlightTexture())
	if not row.stoaClubFill then
		local fill = UI.sliced(row, "BACKGROUND", "CardFill.tga")
		if not fill then return end
		fill:ClearAllPoints()
		fill:SetPoint("TOPLEFT", 6, -3)
		fill:SetPoint("BOTTOMRIGHT", -6, 3)
		fill:SetDrawLayer("BACKGROUND", -8)
		local edge = UI.roundBorder(row, "CardEdge.tga", 1)
		for _, tex in ipairs(edge.edges) do
			tex:ClearAllPoints()
			tex:SetPoint("TOPLEFT", 6, -3)
			tex:SetPoint("BOTTOMRIGHT", -6, 3)
		end
		local bar = row:CreateTexture(nil, "ARTWORK", nil, 7)
		bar:SetTexture(UI.WHITE)
		bar:SetWidth(2)
		bar:SetPoint("TOPLEFT", fill, "TOPLEFT", 0, -12)
		bar:SetPoint("BOTTOMLEFT", fill, "BOTTOMLEFT", 0, 12)
		bar:Hide()
		row.stoaClubFill, row.stoaClubEdge, row.stoaClubBar = fill, edge, bar
		if row.Name then
			Stoa:SetFont(row.Name, "sans", Stoa.typeSize.body)
			row.Name:SetShadowOffset(0, 0)
		end
		if row.Selection then
			hooksecurefunc(row.Selection, "Show", function() paintClub(row) end)
			hooksecurefunc(row.Selection, "Hide", function() paintClub(row) end)
			hooksecurefunc(row.Selection, "SetShown", function() paintClub(row) end)
		end
		row:HookScript("OnEnter", function(self) self.stoaOver = true paintClub(self) end)
		row:HookScript("OnLeave", function(self) self.stoaOver = nil paintClub(self) end)
		for _, method in ipairs({ "Init", "SetFindCommunity", "SetAddCommunity", "SetGuildFinder", "SetEntryEnabled" }) do
			if row[method] then
				hooksecurefunc(row, method, function(self)
					for _, key in ipairs({ "Background", "Selection", "NewCommunityFlash" }) do alphaOff(self[key]) end
					paintClub(self)
				end)
			end
		end
	end
	paintClub(row)
end

-- A member row: Blizzard's bevelled bar goes, a faint light under the mouse.
local function dressMemberRow(row)
	if type(row) ~= "table" or forbidden(row) or row.stoaRow then return end
	row.stoaRow = true
	alphaOff(row.GetNormalTexture and row:GetNormalTexture())
	local over = row.GetHighlightTexture and row:GetHighlightTexture()
	if over and over.SetTexture then
		over:SetTexture(UI.WHITE)
		over:SetVertexColor(1, 1, 1, 0.05)
	end
end

-- The member card that opens beside the roster: STOA's card in place of the
-- dark dialog border, quiet labels, the notes as wells, STOA's buttons.
local DETAIL_LABELS = { "ZoneLabel", "RankLabel", "OnlineLabel", "NoteLabel", "OfficerNoteLabel" }
-- The member panel's card: how far its left edge sits inside the frame's
-- (the words start 17 in), how far its right runs past, and the gap to
-- the guild window.
local DETAIL_LEFT, DETAIL_RIGHT, DETAIL_GAP = 4, 8, 6

local function guildDetail(detail, windows)
	if type(detail) ~= "table" or forbidden(detail) or detail.stoaDetail then return end
	detail.stoaDetail = true
	alphaOff(detail.Border)
	-- Blizzard's border ran wider than the frame, more so on the right,
	-- and the buttons and note run to the frame's own right edge. The card
	-- is a frame of its own behind the words, with the same room on both
	-- sides, and the whole panel stands clear of the window beside it.
	local card = CreateFrame("Frame", nil, detail)
	card:SetPoint("TOPLEFT", detail, "TOPLEFT", DETAIL_LEFT, 0)
	card:SetPoint("BOTTOMRIGHT", detail, "BOTTOMRIGHT", DETAIL_RIGHT, 0)
	card:SetFrameLevel(math.max(detail:GetFrameLevel() - 1, 0))
	UI.surface(card, "card", { alpha = 0.97 })
	local function stand()
		local parent = detail:GetParent()
		if not parent then return end
		detail:ClearAllPoints()
		detail:SetPoint("TOPLEFT", parent, "TOPRIGHT", DETAIL_GAP - DETAIL_LEFT, -76)
	end
	detail:HookScript("OnShow", function() xpcall(stand, Stoa.catch) end)
	stand()
	if windows then
		if windows.DressClose then windows.DressClose(detail.CloseButton) end
		if windows.DressButton then
			for _, key in ipairs({ "RemoveButton", "GroupInviteButton" }) do
				if type(detail[key]) == "table" then xpcall(windows.DressButton, Stoa.catch, detail[key]) end
			end
		end
	end
	if type(detail.RankDropdown) == "table" and not forbidden(detail.RankDropdown) then dressDropdownField(detail.RankDropdown) end
	for _, key in ipairs(DETAIL_LABELS) do
		local label = detail[key]
		if label and label.SetTextColor then label:SetTextColor(Stoa:Color("muted")) end
	end
	if detail.Name and detail.Name.SetTextColor then
		Stoa:SetFont(detail.Name, "sans", Stoa.typeSize.body)
		detail.Name:SetTextColor(Stoa:Color("text"))
	end
	for _, key in ipairs({ "NoteBackground", "OfficerNoteBackground" }) do
		local box = detail[key]
		if type(box) == "table" and box.SetBackdropColor then
			pcall(box.SetBackdropColor, box, 0, 0, 0, 0.35)
			local r, g, b = Stoa:Color("hairline")
			pcall(box.SetBackdropBorderColor, box, r, g, b, 0.8)
		end
	end
end

-- The Info page (message of the day, guild information, challenges) and
-- the news beside it: Blizzard's parchment, gold bars and header plates go,
-- each column sits on a dark well, the headings are STOA's small caps and
-- the page titles take the text colour.
local function quietRegions(owner)
	for _, region in ipairs({ owner:GetRegions() }) do
		if region:IsObjectType("Texture") then
			if not region.stoaOwn then region:SetAlpha(0) end
		elseif region:IsObjectType("FontString") then
			local key
			for k, v in pairs(owner) do if v == region then key = k break end end
			if key == "TitleText" then
				Stoa:SetFont(region, "sans", Stoa.typeSize.label)
				region:SetTextColor(Stoa:Color("text"))
			elseif key ~= "NoNews" then
				local words = region:GetText()
				if type(words) == "string" and words ~= "" then
					Stoa:SetFont(region, "sans", Stoa.typeSize.micro)
					region:SetText(words:upper())
					region:SetTextColor(Stoa:Color("accent"))
				end
			end
		end
	end
end

-- Three even columns: the message of the day, the guild information, the
-- news. Blizzard stacks the first two in one narrow column with the
-- information squeezed at its foot; STOA hangs the information in the
-- empty middle and lets the message of the day run the first column's
-- height. STOA's own small heading sits over each.
local INFO_GAP, INFO_HEAD = 14, 26

local function infoHeading(owner, words)
	local label = UI.text(owner, "sans", Stoa.typeSize.micro, "accent")
	label:SetText(words)
	return label
end

local function placeGuildDetails(details)
	local info, news = details.Info, details.News
	if type(info) ~= "table" or type(news) ~= "table" then return end
	local width = details:GetWidth()
	if not width or width < 300 then return end
	local col = math.floor((width - 2 * INFO_GAP) / 3)
	info:ClearAllPoints()
	info:SetPoint("TOPLEFT", details, "TOPLEFT", 0, 0)
	info:SetPoint("BOTTOMLEFT", details, "BOTTOMLEFT", 0, 0)
	info:SetWidth(col)
	news:ClearAllPoints()
	news:SetPoint("TOPRIGHT", details, "TOPRIGHT", 0, 0)
	news:SetPoint("BOTTOMRIGHT", details, "BOTTOMRIGHT", 0, 0)
	news:SetWidth(col)
	local mid = details.stoaInfoMid
	mid:ClearAllPoints()
	mid:SetPoint("TOPLEFT", info, "TOPRIGHT", INFO_GAP, 0)
	mid:SetPoint("BOTTOMLEFT", info, "BOTTOMRIGHT", INFO_GAP, 0)
	mid:SetWidth(col)
	local textWidth = col - 36
	-- The information, in the middle column.
	local about = info.DetailsFrame
	if type(about) == "table" then
		about:ClearAllPoints()
		about:SetPoint("TOPLEFT", mid, "TOPLEFT", 14, -INFO_HEAD - 6)
		about:SetPoint("BOTTOMRIGHT", mid, "BOTTOMRIGHT", -22, 10)
		local child = about.GetScrollChild and about:GetScrollChild()
		if child then
			child:SetWidth(textWidth)
			if child.Details then child.Details:SetWidth(textWidth) end
		end
	end
	-- The message of the day runs the first column's height, unless the
	-- guild's challenges take the top of it.
	local motd = info.MOTDScrollFrame
	local challenges = info.BG and info.BG:IsShown()
	if type(motd) == "table" and not challenges then
		motd:ClearAllPoints()
		motd:SetPoint("TOPLEFT", info, "TOPLEFT", 14, -INFO_HEAD - 6)
		motd:SetPoint("BOTTOMRIGHT", info, "BOTTOMRIGHT", -22, 10)
		if motd.MOTD then motd.MOTD:SetWidth(textWidth) end
	end
	details.stoaMotdHead:SetShown(not challenges)
	-- Blizzard's edit links ride on the end of each heading row.
	if info.EditMOTDButton then
		info.EditMOTDButton:ClearAllPoints()
		info.EditMOTDButton:SetPoint("TOPRIGHT", info, "TOPRIGHT", -10, -6)
	end
	if info.EditDetailsButton then
		info.EditDetailsButton:ClearAllPoints()
		info.EditDetailsButton:SetPoint("TOPRIGHT", mid, "TOPRIGHT", -10, -6)
	end
end

local function guildDetails(details, windows)
	if type(details) ~= "table" or forbidden(details) then return end
	if details.stoaDetails then
		xpcall(placeGuildDetails, Stoa.catch, details)
		return
	end
	details.stoaDetails = true
	quietRegions(details)
	for _, key in ipairs({ "Info", "News" }) do
		local part = details[key]
		if type(part) == "table" and not forbidden(part) then
			quietRegions(part)
			local well = UI.well(part, 0)
			if well then well.stoaOwn = true end
		end
	end
	local info = details.Info
	if type(info) == "table" then
		-- Blizzard's own section labels go; STOA's headings take their place.
		for _, region in ipairs({ info:GetRegions() }) do
			if region:IsObjectType("FontString") and region ~= info.TitleText then region:SetAlpha(0) end
		end
		local mid = CreateFrame("Frame", nil, details)
		local well = UI.well(mid, 0)
		if well then well.stoaOwn = true end
		details.stoaInfoMid = mid
		details.stoaMotdHead = infoHeading(info, "MESSAGE OF THE DAY")
		details.stoaMotdHead:SetPoint("TOPLEFT", info, "TOPLEFT", 14, -10)
		local about = infoHeading(mid, "GUILD INFORMATION")
		about:SetPoint("TOPLEFT", mid, "TOPLEFT", 14, -10)
		details:HookScript("OnSizeChanged", function(own) xpcall(placeGuildDetails, Stoa.catch, own) end)
		details:HookScript("OnShow", function(own) xpcall(placeGuildDetails, Stoa.catch, own) end)
		if type(rawget(_G, "CommunitiesGuildInfoFrame_HideChallenges")) == "function" then
			hooksecurefunc("CommunitiesGuildInfoFrame_HideChallenges", function()
				xpcall(placeGuildDetails, Stoa.catch, details)
			end)
		end
		xpcall(placeGuildDetails, Stoa.catch, details)
	end
	local filters = details.News and details.News.SetFiltersButton
	local label = type(filters) == "table" and filters.GetFontString and filters:GetFontString()
	if label then label:SetTextColor(Stoa:Color("muted")) end
	if windows and windows.DressScrollBar then
		local pane, news = details.Info, details.News
		for _, owner in ipairs({ pane and pane.MOTDScrollFrame, pane and pane.DetailsFrame, news }) do
			if type(owner) == "table" then xpcall(windows.DressScrollBar, Stoa.catch, owner.ScrollBar) end
		end
	end
end

guildInner = function(frame)
	local windows = Stoa.modules.Windows
	xpcall(guildDetails, Stoa.catch, frame.GuildDetailsFrame, windows)
	if windows and windows.DressScrollBar then
		for _, owner in ipairs({ frame.CommunitiesList, frame.Chat, frame.MemberList }) do
			if type(owner) == "table" then xpcall(windows.DressScrollBar, Stoa.catch, owner.ScrollBar) end
		end
	end
	xpcall(guildDetail, Stoa.catch, frame.GuildMemberDetailFrame, windows)
	local list = frame.CommunitiesList
	if type(list) == "table" and not forbidden(list) then
		for _, key in ipairs({ "Bg", "TopFiligree", "BottomFiligree" }) do alphaOff(list[key]) end
		alphaOff(list.FilligreeOverlay)
		quietInset(list.InsetFrame)
		column(list, 0.22, "RIGHT")
		eachRow(list.ScrollBox, "stoaClubRows", dressClub)
	end
	local chat = frame.Chat
	if type(chat) == "table" and not forbidden(chat) then
		quietInset(chat.InsetFrame)
		if chat.InsetFrame and not chat.InsetFrame.stoaWell then UI.well(chat.InsetFrame, 0) end
	end
	if windows and windows.DressSearch then xpcall(windows.DressSearch, Stoa.catch, frame.ChatEditBox) end
	for _, key in ipairs({ "StreamDropdown", "CommunitiesListDropdown" }) do
		local dropdown = frame[key]
		if type(dropdown) == "table" and not forbidden(dropdown) then dressDropdownField(dropdown) end
	end
	local members = frame.MemberList
	if type(members) == "table" and not forbidden(members) then
		quietInset(members.InsetFrame)
		if members.ColumnDisplay then
			alphaOff(members.ColumnDisplay.Background)
			alphaOff(members.ColumnDisplay.TopTileStreaks)
		end
		column(members, 0.18, "LEFT")
		eachRow(members.ScrollBox, "stoaMemberRows", dressMemberRow)
	end
end

function AFTER.dressup(frame)
	if InCombatLockdown() then return end
	local dropdown, toggle = frame.CustomSetDropdown, frame.ToggleCustomSetDetailsButton
	local scene = frame.ModelScene
	if type(scene) == "table" and not forbidden(scene) and scene.SetPoint then
		scene:SetPoint("TOPLEFT", frame, "TOPLEFT", 7, DRESSUP_MODEL_TOP)
	end
	if type(dropdown) == "table" and not forbidden(dropdown) then
		dressDropdownField(dropdown)
		dropdown:ClearAllPoints()
		dropdown:SetPoint("TOPLEFT", frame, "TOPLEFT", 8, DRESSUP_ROW_Y)
		dropdown:SetHeight(DRESSUP_ROW_H)
		local save = dropdown.SaveButton
		local windows = Stoa.modules.Windows
		if type(save) == "table" and not forbidden(save) then
			if windows and windows.DressButton then windows.DressButton(save) end
			save:SetHeight(DRESSUP_ROW_H)
		end
	end
	if type(toggle) == "table" and not forbidden(toggle) then
		quietButtonArt(toggle)
		if not toggle.stoaField then
			toggle.stoaField = true
			dressField(toggle)
			-- Three short lines: a list.
			local lines = {}
			for i = 1, 3 do
				local bar = toggle:CreateTexture(nil, "OVERLAY")
				bar:SetSize(10, 1)
				UI.pixel(bar, "height")
				bar:SetPoint("CENTER", 0, (2 - i) * 4)
				bar:SetColorTexture(1, 1, 1)
				lines[i] = bar
			end
			local function paint(over)
				local r, g, b = Stoa:Color(over and "accent" or "muted")
				for _, bar in ipairs(lines) do bar:SetVertexColor(r, g, b) end
			end
			toggle:HookScript("OnEnter", function() paint(true) end)
			toggle:HookScript("OnLeave", function() paint(false) end)
			toggle:HookScript("OnShow", function() quietButtonArt(toggle) end)
			paint(false)
		end
		toggle:ClearAllPoints()
		toggle:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -10, DRESSUP_ROW_Y)
		toggle:SetSize(DRESSUP_ROW_H, DRESSUP_ROW_H)
	end
end

function AFTER.addons(frame)
	if InCombatLockdown() then return end
	for _, key in ipairs({ "Dropdown", "ForceLoad", "SearchBox", "Performance" }) do dropTops(frame[key], ADDONS_DROP) end
	-- Slate: each addon's tick is a small switch (the rows have the room),
	-- and the lone tick in the header a square like the other windows'.
	local windows = Stoa.modules.Windows
	if windows and windows.DressTick and UI.slate() then
		eachRow(frame.ScrollBox, "stoaSwitches", function(row)
			if type(row.Enabled) == "table" then windows.DressTick(row.Enabled, true) end
		end)
		if type(frame.ForceLoad) == "table" then windows.DressTick(frame.ForceLoad) end
	end
end

-- Professions: the tall tiles down the right (the overview and one per
-- profession) are dark STOA tiles with the icon kept; the open one has a
-- short accent bar on the side that meets the window. The tabs cast their
-- profession's spell, so they are never moved; only their art changes.
local function sideTabChosen(tab)
	local selected = tab.SelectedTexture
	if selected and selected.IsShown then return selected:IsShown() and true or false end
	if tab.GetChecked then return tab:GetChecked() and true or false end
	return tab.stoaChecked and true or false
end

local function paintSideTab(tab)
	if not tab.stoaSideFill then return end
	local chosen = sideTabChosen(tab)
	tab.stoaSideBar:SetShown(chosen)
	local r, g, b = Stoa:Color("panel")
	local lift = chosen and 0.06 or 0
	tab.stoaSideFill:SetVertexColor(r + lift, g + lift, b + lift, 1)
	tab.stoaSideRim:SetVertexColor(Stoa:Color(chosen and "accent" or "hairline"))
	local icon = tab.Icon
	if icon and icon.SetDesaturated then
		-- (Glyph tabs grey their icon themselves when the tab is unavailable.)
		if not tab.stoaGlyphTab then icon:SetDesaturated(false) end
		icon:SetAlpha(chosen and 1 or 0.7)
	end
end

-- Blizzard's side tab (LargeSideTabButtonTemplate): Background, the Icon
-- cut by Mask to the tab's shape, SelectedTexture, a pulsing TabGlow and
-- HighlightTexture. Its art goes clear (by vertex alpha, which the glow's
-- animation doesn't touch), the icon loses the mask and keeps Blizzard's
-- placing, and a square tile with a hairline rim sits behind it.
local SIDE_ART = { "Background", "SelectedTexture", "TabGlow", "HighlightTexture" }
-- `glyph`: the icon is an atlas glyph that Blizzard sets again (at its own
-- size) each time the tab is picked, as on the friends window; it keeps
-- its size and the tile is a fixed square centred where the icon sits.
local GLYPH_TILE = 40
local function dressSideTab(tab, glyph)
	if type(tab) ~= "table" or not tab.CreateTexture or forbidden(tab) or tab.stoaSideTab then return end
	local icon = tab.Icon
	if not icon then return end
	tab.stoaSideTab = true
	tab.stoaGlyphTab = glyph and true or nil
	for _, key in ipairs(SIDE_ART) do
		local part = tab[key]
		if type(part) == "table" and part.SetVertexColor then part:SetVertexColor(1, 1, 1, 0) end
	end
	if tab.Mask and icon.RemoveMaskTexture then pcall(icon.RemoveMaskTexture, icon, tab.Mask) end
	local rim = tab:CreateTexture(nil, "BACKGROUND", nil, 1)
	rim:SetTexture(UI.WHITE)
	if glyph then
		rim:SetSize(GLYPH_TILE, GLYPH_TILE)
		rim:SetPoint("CENTER", -3, 0)
	else
		icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
		local size = 34
		icon:SetSize(size, size)
		rim:SetPoint("TOPLEFT", icon, -4, 4)
		rim:SetPoint("BOTTOMRIGHT", icon, 4, -4)
	end
	local fill = tab:CreateTexture(nil, "BACKGROUND", nil, 2)
	fill:SetTexture(UI.WHITE)
	fill:SetPoint("TOPLEFT", rim, 1, -1)
	fill:SetPoint("BOTTOMRIGHT", rim, -1, 1)
	-- The open one: a short accent bar on the side facing the window.
	local bar = tab:CreateTexture(nil, "OVERLAY")
	bar:SetTexture(UI.WHITE)
	bar:SetWidth(2)
	bar:SetPoint("TOPRIGHT", rim, "TOPLEFT", -2, -8)
	bar:SetPoint("BOTTOMRIGHT", rim, "BOTTOMLEFT", -2, 8)
	UI.tint(bar, "accent")
	tab.stoaSideFill, tab.stoaSideRim, tab.stoaSideBar = fill, rim, bar
	if tab.SetChecked then hooksecurefunc(tab, "SetChecked", function(self, on) self.stoaChecked = on paintSideTab(self) end) end
	if tab.SelectedTexture then
		hooksecurefunc(tab.SelectedTexture, "Show", function() paintSideTab(tab) end)
		hooksecurefunc(tab.SelectedTexture, "Hide", function() paintSideTab(tab) end)
		hooksecurefunc(tab.SelectedTexture, "SetShown", function() paintSideTab(tab) end)
	end
	tab:HookScript("OnShow", paintSideTab)
	tab:HookScript("OnEnter", function(self) if not sideTabChosen(self) then self.Icon:SetAlpha(1) end end)
	tab:HookScript("OnLeave", paintSideTab)
	paintSideTab(tab)
end

-- A dark rounded tile with an edge, inset in its owner (rows and cards).
local function lfgTile(row, left, top, right, bottom)
	local fill = UI.sliced(row, "BACKGROUND", "CardFill.tga")
	if not fill then return end
	local edge = UI.roundBorder(row, "CardEdge.tga", 1)
	local parts = { fill }
	for _, tex in ipairs(edge.edges or {}) do parts[#parts + 1] = tex end
	for _, tex in ipairs(parts) do
		tex:ClearAllPoints()
		tex:SetPoint("TOPLEFT", left, -top)
		tex:SetPoint("BOTTOMRIGHT", -right, bottom)
	end
	fill:SetDrawLayer("BACKGROUND", -8)
	row.stoaFill, row.stoaEdge = fill, edge
	return fill
end

-- The overview page: Blizzard's five painted cards (two professions, then
-- cooking, fishing and first aid) become dark tiles with a fine rim. Names
-- read in the text colour, the bronze icon frames and the bar's bronze
-- rim go, the skill bar's swirl is one calm colour (the accent) and the
-- red unlearn cross is grey until the mouse is on it. The spell buttons
-- are secure and cast, so only their art and words change, never their
-- place.
local function professionWords(text, token)
	if type(text) == "table" and text.SetTextColor then
		text:SetTextColor(Stoa:Color(token))
		if text.SetShadowOffset then text:SetShadowOffset(0, 0) end
	end
end

local function quietRankBar(bar)
	if type(bar) ~= "table" or forbidden(bar) then return end
	alphaOff(bar.Border)
	if bar.Background and bar.Background.SetVertexColor then bar.Background:SetVertexColor(0, 0, 0, 0.6) end
	-- One flat colour: the game puts its animated swirl back whenever the
	-- profession shown changes, so this runs after each of its updates.
	-- Its mask still cuts the fill to the bar's shape and length.
	alphaOff(bar.Flare)
	local fill = bar.Fill
	if fill and fill.SetColorTexture then
		fill:SetColorTexture(1, 1, 1, 1)
		local r, g, b = Stoa:Color("accent")
		fill:SetVertexColor(r, g, b, 0.85)
	end
	local words = bar.Rank and bar.Rank.Text
	if words and words.SetTextColor then words:SetTextColor(Stoa:Color("text")) end
end

local function dressSpellButton(button)
	if type(button) ~= "table" or forbidden(button) then return end
	alphaOff(button.IconBorder)
	alphaOff(button.IconTextureOverlay)
	if button.IconTexture and button.IconTexture.SetTexCoord then button.IconTexture:SetTexCoord(0.08, 0.92, 0.08, 0.92) end
	-- Blizzard writes the name in yellow each time it draws the button
	-- (and in its own blue for a passive, which stays).
	local words = button.spellString
	if words and words.GetTextColor then
		local r, g, b = words:GetTextColor()
		local n = NORMAL_FONT_COLOR
		if n and math.abs(r - n.r) < 0.02 and math.abs(g - n.g) < 0.02 and math.abs(b - n.b) < 0.02 then professionWords(words, "text") end
	end
	if not button.stoaProfession then
		button.stoaProfession = true
		if type(button.UpdateButton) == "function" then
			Stoa.SafeHook(button, "UpdateButton", function(own) dressSpellButton(own) end)
		end
	end
end

local CARD_ART = 0.3
local function dressProfessionCard(card)
	if type(card) ~= "table" or forbidden(card) then return end
	-- The game's painting of the craft stays as a grey watermark on the
	-- tile, so the page is not five plain blocks.
	local art = card.Background
	if type(art) == "table" and art.SetDesaturated then
		art:SetDesaturated(true)
		art:SetAlpha(CARD_ART)
	end
	professionWords(card.ProfessionName, "text")
	professionWords(card.missingHeader, "text")
	professionWords(card.missingText, "muted")
	professionWords(card.specialization, "muted")
	quietRankBar(card.StatusBar)
	for _, button in ipairs(card.spellButtons or {}) do dressSpellButton(button) end
	if card.stoaFill then return end
	if not lfgTile(card, 3, 3, 3, 3) then return end
	local r, g, b = Stoa:Color("panel")
	card.stoaFill:SetVertexColor(r + 0.03, g + 0.03, b + 0.03, 0.9)
	card.stoaEdge:Set(Stoa:Color("hairline"))
	local bar = card.StatusBar
	if type(bar) == "table" and type(bar.Update) == "function" then
		Stoa.SafeHook(bar, "Update", function(own) quietRankBar(own) end)
	end
	local unlearn = card.UnlearnButton
	if type(unlearn) == "table" and not forbidden(unlearn) then
		local function paint(over)
			for _, key in ipairs({ "Icon", "Overlay" }) do
				local tex = unlearn[key]
				if tex and tex.SetDesaturated then
					tex:SetDesaturated(not over)
					if over then tex:SetVertexColor(1, 1, 1) else tex:SetVertexColor(Stoa:Color("muted")) end
				end
			end
		end
		unlearn:HookScript("OnEnter", function() paint(true) end)
		unlearn:HookScript("OnLeave", function() paint(false) end)
		paint(false)
	end
end

local PROFESSION_CARDS = { "PrimaryProfession1", "PrimaryProfession2", "SecondaryProfession1", "SecondaryProfession2", "SecondaryProfession3" }
local function professionContent(root, depth)
	if type(root) ~= "table" or forbidden(root) then return end
	if type(root.ProfessionsContentFrame) == "table" then return root.ProfessionsContentFrame end
	if depth <= 0 or not root.GetChildren then return end
	for _, child in ipairs({ root:GetChildren() }) do
		local found = professionContent(child, depth - 1)
		if found then return found end
	end
end

local function dressProfessionCards(frame)
	local content = frame.stoaProfessionContent or professionContent(frame.BookPage, 2)
	if not content then return end
	if not frame.stoaProfessionContent then
		frame.stoaProfessionContent = content
		-- The cards are filled in again whenever a skill changes.
		for _, owner in ipairs({ content:GetParent(), frame.BookPage }) do
			if type(owner) == "table" and type(owner.Update) == "function" and not owner.stoaProfessionHook then
				owner.stoaProfessionHook = true
				Stoa.SafeHook(owner, "Update", function() dressProfessionCards(frame) end)
			end
		end
	end
	for _, key in ipairs(PROFESSION_CARDS) do xpcall(dressProfessionCard, Stoa.catch, content[key]) end
end

-- A profession's own page: the recipe list on the left, the chosen recipe
-- on the right. The torn brown strip behind the skill bar, the list's
-- bronze ground and heading bars, the gold bevel round the recipe and the
-- yellow glow on the chosen row go. The list is a darker column, its
-- headings quiet words over a fine line, the chosen recipe a calm tile
-- with an accent bar. Nothing is moved.
local function holdColour(text, token)
	if type(text) ~= "table" or not text.SetTextColor then return end
	text.stoaHold = token
	if text.stoaHeld then
		text:SetTextColor(Stoa:Color(token))
		return
	end
	text.stoaHeld = true
	local busy
	-- The game colours a heading again each time it draws or leaves it.
	for _, method in ipairs({ "SetTextColor", "SetVertexColor" }) do
		if text[method] then
			hooksecurefunc(text, method, function(own)
				if busy then return end
				busy = true
				own[method](own, Stoa:Color(own.stoaHold))
				busy = false
			end)
		end
	end
	if text.SetShadowOffset then text:SetShadowOffset(0, 0) end
	text:SetTextColor(Stoa:Color(token))
end

local function paintRecipeRow(row)
	local mark = row.stoaChosen
	if not mark then return end
	local chosen = row.SelectedOverlay and row.SelectedOverlay:IsShown() and true or false
	mark.fill:SetShown(chosen)
	mark.bar:SetShown(chosen)
end

local function dressRecipeRow(row)
	if type(row) ~= "table" or forbidden(row) then return end
	if type(row.SelectedOverlay) == "table" and row.Label then
		-- A recipe.
		alphaOff(row.SelectedOverlay)
		alphaOff(row.HighlightOverlay)
		if not row.stoaChosen then
			local fill = row:CreateTexture(nil, "BACKGROUND")
			fill:SetTexture(UI.WHITE)
			fill:SetPoint("TOPLEFT", 2, 0)
			fill:SetPoint("BOTTOMRIGHT", -2, 0)
			UI.tint(fill, "accent", 0.12)
			local bar = row:CreateTexture(nil, "ARTWORK")
			bar:SetTexture(UI.WHITE)
			bar:SetWidth(2)
			bar:SetPoint("TOPLEFT", 2, -2)
			bar:SetPoint("BOTTOMLEFT", 2, 2)
			UI.tint(bar, "accent")
			local over = row:CreateTexture(nil, "HIGHLIGHT")
			over:SetTexture(UI.WHITE)
			over:SetPoint("TOPLEFT", 2, 0)
			over:SetPoint("BOTTOMRIGHT", -2, 0)
			over:SetVertexColor(1, 1, 1, 0.05)
			row.stoaChosen = { fill = fill, bar = bar }
			for _, method in ipairs({ "SetShown", "Show", "Hide" }) do
				hooksecurefunc(row.SelectedOverlay, method, function() paintRecipeRow(row) end)
			end
		end
		paintRecipeRow(row)
		return
	end
	if type(row.RankBar) ~= "table" or not row.GetRegions then return end
	-- A heading. Its bar art is the game's to swap (folded, open, under
	-- the mouse), so it is only ever faded out.
	local own = row.stoaHeadParts
	for _, region in ipairs({ row:GetRegions() }) do
		if region.IsObjectType and region:IsObjectType("Texture") and not (own and own[region]) then
			region:SetAlpha(0)
		elseif region.IsObjectType and region:IsObjectType("FontString") then
			holdColour(region, row.stoaOver and "text" or "muted")
		end
	end
	if own then return end
	local rule = row:CreateTexture(nil, "BACKGROUND")
	rule:SetTexture(UI.WHITE)
	rule:SetHeight(1)
	rule:SetPoint("BOTTOMLEFT", 4, 1)
	rule:SetPoint("BOTTOMRIGHT", -4, 1)
	UI.tint(rule, "hairline")
	row.stoaHeadParts = { [rule] = true }
	-- The plus and minus at the end: grey, not gold.
	local fold = type(row.GetCollapseButton) == "function" and row:GetCollapseButton()
	if type(fold) == "table" and not forbidden(fold) and fold.GetRegions then
		for _, region in ipairs({ fold:GetRegions() }) do
			if region.SetDesaturated then
				region:SetDesaturated(true)
				region:SetVertexColor(Stoa:Color("muted"))
			end
		end
	end
	local function words(over)
		row.stoaOver = over
		for _, region in ipairs({ row:GetRegions() }) do
			if region.stoaHeld then holdColour(region, over and "text" or "muted") end
		end
	end
	row:HookScript("OnEnter", function() words(true) end)
	row:HookScript("OnLeave", function() words(false) end)
end

-- Rows are filled in after they are handed out, so the look goes on once
-- the game has written them.
local function eachDrawn(scrollBox, key, fn)
	if type(scrollBox) ~= "table" or forbidden(scrollBox) or scrollBox[key] then return end
	if not (ScrollUtil and ScrollUtil.AddInitializedFrameCallback) then return eachRow(scrollBox, key, fn) end
	scrollBox[key] = true
	ScrollUtil.AddInitializedFrameCallback(scrollBox, function(_, row) xpcall(fn, Stoa.catch, row) end, scrollBox, true)
end

-- The painted workbench behind the recipe: grey and faint, so it reads as
-- a watermark on the window, not a brown card.
local FORM_ART = 0.22
local function quietFormArt(tex)
	if type(tex) ~= "table" or not tex.SetDesaturated then return end
	tex:SetDesaturated(true)
	tex:SetAlpha(FORM_ART)
end

local function dressCraftingPage(frame)
	local page = frame.CraftingPage
	if type(page) ~= "table" or forbidden(page) then return end
	local windows = Stoa.modules.Windows
	local bar = page.RankBar
	if type(bar) == "table" and not forbidden(bar) then
		quietRankBar(bar)
		if not bar.stoaQuiet and type(bar.Update) == "function" then
			bar.stoaQuiet = true
			Stoa.SafeHook(bar, "Update", function(own) quietRankBar(own) end)
		end
	end
	if page.stoaCrafting then return end
	page.stoaCrafting = true
	-- The strip of torn leather under the title.
	hideOwnArt(page)
	local list = page.RecipeList
	if type(list) == "table" and not forbidden(list) then
		alphaOff(list.Background)
		alphaOff(list.BackgroundNineSlice)
		column(list, 0.22, "RIGHT")
		professionWords(list.NoResultsText, "muted")
		if windows and windows.DressSearch then xpcall(windows.DressSearch, Stoa.catch, list.SearchBox) end
		if windows and windows.DressScrollBar then xpcall(windows.DressScrollBar, Stoa.catch, list.ScrollBar) end
		local filter = list.FilterDropdown
		if type(filter) == "table" and not forbidden(filter) and filter.CreateTexture then
			quietButtonArt(filter)
			xpcall(dressDropdownField, Stoa.catch, filter)
		end
		eachDrawn(list.ScrollBox, "stoaRecipeRows", dressRecipeRow)
	end
	local form = page.SchematicForm
	if type(form) == "table" and not forbidden(form) then
		-- The gold bevel is a nameless texture on the form's border layer.
		for _, region in ipairs({ form:GetRegions() }) do
			if region.IsObjectType and region:IsObjectType("Texture") and region ~= form.Background and region ~= form.MinimalBackground
				and region.GetDrawLayer and region:GetDrawLayer() == "BORDER" then
				region:SetAlpha(0)
			end
		end
		alphaOff(form.NineSlice)
		quietFormArt(form.Background)
		quietFormArt(form.MinimalBackground)
		for _, key in ipairs({ "Reagents", "OptionalReagents", "FinishingReagents" }) do
			local group = form[key]
			if type(group) == "table" then professionWords(group.Label, "muted") end
		end
	end
end

function AFTER.professions(frame)
	dressSideTab(frame.ProfessionsOverviewTab)
	for _, tab in ipairs(frame.rightProfessionTabs or {}) do dressSideTab(tab) end
	xpcall(dressProfessionCards, Stoa.catch, frame)
	xpcall(dressCraftingPage, Stoa.catch, frame)
end

-- Looking For Group. The parts on the bare parent first: its close becomes
-- the quiet cross, the side tabs dark tiles like the professions' ones, and
-- the big eye over the corner goes (as every window's portrait does).
-- Then each page's inside: wood, stone and gold bevels go, rows become
-- dark tiles, fields and ticks STOA's. Nothing is moved.
local function paintLfgRow(row)
	if not row.stoaFill then return end
	local chosen = row.Selected and row.Selected:IsShown()
	local over = row.stoaOver
	local r, g, b = Stoa:Color("panel")
	local lift = chosen and 0.06 or (over and 0.03 or 0)
	row.stoaFill:SetVertexColor(r + lift, g + lift, b + lift, chosen and 0.95 or (over and 0.8 or 0.55))
	if chosen then row.stoaEdge:Set(Stoa:Color("accent")) elseif over then row.stoaEdge:Set(Stoa:Color("hairline")) else row.stoaEdge:Clear() end
end

local LFG_ROW_ART = { "ResultBG", "Background", "Selected", "Highlight" }
local function lfgRowTile(row, left, top, right, bottom)
	for _, key in ipairs(LFG_ROW_ART) do alphaOff(row[key]) end
	alphaOff(row.GetHighlightTexture and row:GetHighlightTexture())
	if row.stoaFill or not lfgTile(row, left, top, right, bottom) then return end
	if row.Selected then
		for _, method in ipairs({ "Show", "Hide", "SetShown" }) do
			hooksecurefunc(row.Selected, method, function() paintLfgRow(row) end)
		end
	end
	row:HookScript("OnEnter", function(self) self.stoaOver = true paintLfgRow(self) end)
	row:HookScript("OnLeave", function(self) self.stoaOver = nil paintLfgRow(self) end)
	row:HookScript("OnShow", paintLfgRow)
	paintLfgRow(row)
end

-- A small square key (refresh, search, invite): the gold square goes, its
-- sign turns grey and warms under the mouse.
local function lfgKey(button)
	if type(button) ~= "table" or forbidden(button) or button.stoaKey then return end
	button.stoaKey = true
	quietButtonArt(button)
	local icon = button.Icon
	local fill = UI.sliced(button, "BACKGROUND", "CardFill.tga")
	if fill then
		fill:ClearAllPoints()
		fill:SetPoint("TOPLEFT", 4, -4)
		fill:SetPoint("BOTTOMRIGHT", -4, 4)
		fill:SetDrawLayer("BACKGROUND", -8)
		UI.tint(fill, "panel", 0.95)
	end
	local function paint(over)
		if not (icon and icon.SetVertexColor) then return end
		icon:SetDesaturated(true)
		icon:SetVertexColor(Stoa:Color(over and "accent" or "muted"))
	end
	button:HookScript("OnEnter", function() paint(true) end)
	button:HookScript("OnLeave", function() paint(false) end)
	button:HookScript("OnShow", function() paint(false) end)
	paint(false)
end

local function lfgWords(text, token)
	if type(text) == "table" and text.SetTextColor then
		text:SetTextColor(Stoa:Color(token))
		if text.SetShadowOffset then text:SetShadowOffset(0, 0) end
	end
end

local function lfgCommon(frame)
	local windows = Stoa.modules.Windows
	if type(frame.Inset) == "table" and not forbidden(frame.Inset) then hideOwnArt(frame.Inset) end
	if windows and windows.DressScrollBar then windows.DressScrollBar(frame.ScrollBar) end
end

-- A group in the browse list, or the heading of a folded set of them.
local function dressLfgEntry(row)
	if type(row) ~= "table" or forbidden(row) then return end
	if row.CategoryLabel then
		for _, key in ipairs({ "ResultBG", "Highlight" }) do alphaOff(row[key]) end
		if row.stoaHead then return end
		row.stoaHead = true
		local rule = row:CreateTexture(nil, "BACKGROUND")
		rule:SetTexture(UI.WHITE)
		rule:SetHeight(1)
		rule:SetPoint("BOTTOMLEFT", 10, 2)
		rule:SetPoint("BOTTOMRIGHT", -10, 2)
		UI.tint(rule, "hairline")
		lfgWords(row.CategoryLabel, "muted")
		for _, key in ipairs({ "ExpandIcon", "CollapseIcon" }) do
			local sign = row[key]
			if sign and sign.SetDesaturated then
				sign:SetDesaturated(true)
				sign:SetVertexColor(Stoa:Color("muted"))
			end
		end
		return
	end
	lfgRowTile(row, 4, 3, 4, 1)
	local display = row.DataDisplay
	local delist = type(display) == "table" and display.DelistButton
	if type(delist) == "table" and not forbidden(delist) and not delist.stoaKey then
		delist.stoaKey = true
		hideOwnArt(delist, { [delist.Icon or false] = true })
		if delist.Icon then delist.Icon:SetAlpha(1) end
	end
end

local function dressWhoRow(row)
	if type(row) ~= "table" or forbidden(row) then return end
	lfgRowTile(row, 0, 2, 0, 2)
	if row.stoaWho then return end
	row.stoaWho = true
	lfgWords(row.Name, "text")
	lfgKey(row.InviteButton)
end

-- An activity in "list yourself": the game sets the name's font (yellow,
-- or grey and red by level) each time the row is drawn; the plain and the
-- heading ones read in STOA's text colour.
local function dressActivityRow(row)
	if type(row) ~= "table" or forbidden(row) or row.stoaActivity then return end
	row.stoaActivity = true
	local windows = Stoa.modules.Windows
	if windows and windows.DressTick then windows.DressTick(row.CheckButton) end
	local name = row.NameButton and row.NameButton.Name
	local function paint(text, font, token)
		if font == rawget(_G, "LFGActivityEntry") or font == rawget(_G, "LFGActivityHeader") then lfgWords(text, token) end
	end
	if name and name.SetFontObject then
		hooksecurefunc(name, "SetFontObject", function(self, font) paint(self, font, "text") end)
		paint(name, name:GetFontObject(), "text")
	end
	if row.Level and row.Level.SetFontObject then
		hooksecurefunc(row.Level, "SetFontObject", function(self, font) paint(self, font, "muted") end)
		paint(row.Level, row.Level:GetFontObject(), "muted")
	end
end

-- The four big picture buttons: the bronze cover goes, the picture stays
-- (dimmed until the mouse is over it) on a dark tile with a fine rim.
local CATEGORY_DIM, CATEGORY_LIT = 0.5, 0.9
local function dressCategory(button)
	if type(button) ~= "table" or forbidden(button) then return end
	alphaOff(button.Cover)
	alphaOff(button.GetPushedTexture and button:GetPushedTexture())
	alphaOff(button.GetHighlightTexture and button:GetHighlightTexture())
	if button.stoaFill then return end
	if not lfgTile(button, 5, 8, 5, 5) then return end
	UI.tint(button.stoaFill, "panel", 0.95)
	local label = button.Label or (button.GetFontString and button:GetFontString())
	if label then
		Stoa:SetFont(label, "sans", Stoa.typeSize.name)
		lfgWords(label, "text")
	end
	local function paint(over)
		if button.Icon then button.Icon:SetAlpha(over and CATEGORY_LIT or CATEGORY_DIM) end
		if over then button.stoaEdge:Set(Stoa:Color("accent")) else button.stoaEdge:Set(Stoa:Color("hairline")) end
	end
	button:HookScript("OnEnter", function() paint(true) end)
	button:HookScript("OnLeave", function() paint(false) end)
	button:HookScript("OnShow", function() paint(false) end)
	paint(false)
end

local function dressCategories(view)
	if type(view) ~= "table" or forbidden(view) then return end
	for _, button in ipairs(view.CategoryButtons or {}) do xpcall(dressCategory, Stoa.catch, button) end
end

local function lfgListing(frame)
	local windows = Stoa.modules.Windows
	local tick = windows and windows.DressTick
	local roles = frame.RolesSection
	if type(roles) == "table" and not forbidden(roles) then
		hideOwnArt(roles)
		-- A fine line where the wood strip ended.
		local rule = roles:CreateTexture(nil, "ARTWORK")
		rule:SetTexture(UI.WHITE)
		rule:SetHeight(1)
		rule:SetPoint("BOTTOMLEFT", 14, 2)
		rule:SetPoint("BOTTOMRIGHT", -14, 2)
		UI.tint(rule, "hairline")
	end
	if type(frame.DividerFrame) == "table" and not forbidden(frame.DividerFrame) then hideOwnArt(frame.DividerFrame) end
	local solo = frame.SoloRoleButtons
	for _, role in ipairs(type(solo) == "table" and solo.RoleButtons or {}) do
		alphaOff(role.Background)
		if tick then tick(role.CheckButton) end
	end
	local group = frame.GroupRoleButtons
	if type(group) == "table" and not forbidden(group) then
		if group.RoleIcon then alphaOff(group.RoleIcon.Background) end
		if type(group.RoleDropdown) == "table" then dressDropdownField(group.RoleDropdown) end
	end
	local friendly = frame.NewPlayerFriendlyButton
	if tick and type(friendly) == "table" then tick(friendly.CheckButton) end
	dressCategories(frame.CategoryView)
	if rawget(_G, "LFGListingCategorySelection_UpdateCategoryButtons") then
		Stoa.SafeHook("LFGListingCategorySelection_UpdateCategoryButtons", function(view)
			dressCategories(view)
			dressCategories(frame.CategoryView)
		end)
	end
	local view = frame.ActivityView
	if type(view) ~= "table" or forbidden(view) then return end
	alphaOff(view.BarTop)
	alphaOff(view.BarMiddle)
	lfgWords(view.VoiceChatLabel, "muted")
	for _, key in ipairs({ "PlayStyleDropdown", "VoiceChatDropdown" }) do
		if type(view[key]) == "table" and not forbidden(view[key]) then dressDropdownField(view[key]) end
	end
	local ranges = view.LevelRangesCheckbox
	if type(ranges) == "table" then
		lfgWords(ranges.Text, "muted")
		if tick then tick(ranges.Checkbox) end
	end
	if windows and windows.DressScrollBar then windows.DressScrollBar(view.ScrollBar) end
	eachRow(view.ScrollBox, "stoaActivityRows", dressActivityRow)
	local comment = view.Comment
	if type(comment) == "table" and not forbidden(comment) and not comment.stoaWell then
		hideOwnArt(comment)
		UI.well(comment, 4)
	end
end

local function lfgBrowse(frame)
	for _, key in ipairs({ "CategoryDropdown", "ActivityDropdown" }) do
		if type(frame[key]) == "table" and not forbidden(frame[key]) then dressDropdownField(frame[key]) end
	end
	lfgKey(frame.RefreshButton)
	local gear = frame.OptionsButton
	if type(gear) == "table" and gear.Icon and gear.Icon.SetDesaturated then gear.Icon:SetDesaturated(true) end
	eachRow(frame.ScrollBox, "stoaLfgRows", dressLfgEntry)
end

local function lfgWho(frame)
	local windows = Stoa.modules.Windows
	if windows and windows.DressSearch then xpcall(windows.DressSearch, Stoa.catch, frame.EditBox) end
	lfgKey(frame.WhoSearch)
	if type(frame.FilterDropdown) == "table" and not forbidden(frame.FilterDropdown) then dressDropdownField(frame.FilterDropdown) end
	lfgWords(frame.WhoFrameTotals, "muted")
	eachRow(frame.ScrollBox, "stoaWhoRows", dressWhoRow)
end

-- Blizzard's places: the roles 70 in and 41 down with the newcomer flag
-- hard against the right edge, and the browse dropdowns 43 down, close
-- under the title. Without the wood strip the roles sit centred in the
-- band with more air above, and the dropdowns halfway to the list.
local LFG_ROLES_LEFT, LFG_ROLES_DOWN = 28, 8
local LFG_DROPS_DOWN = 10
local function placeLfg(frame, name)
	if InCombatLockdown() then return end
	local function seat(part, point, x, y)
		if type(part) ~= "table" or forbidden(part) or (part.IsProtected and part:IsProtected()) then return end
		part:ClearAllPoints()
		part:SetPoint(point, frame, point, x, y)
	end
	if name == "LFGListingFrame" then
		seat(frame.SoloRoleButtons, "TOPLEFT", 70 - LFG_ROLES_LEFT, -41 - LFG_ROLES_DOWN)
		seat(frame.GroupRoleButtons, "TOPLEFT", 105 - LFG_ROLES_LEFT, -41 - LFG_ROLES_DOWN)
		seat(frame.NewPlayerFriendlyButton, "TOPRIGHT", -3 - LFG_ROLES_LEFT, -30 - LFG_ROLES_DOWN)
	elseif name == "LFGBrowseFrame" then
		seat(frame.CategoryDropdown, "TOPLEFT", 70, -43 - LFG_DROPS_DOWN)
		seat(frame.OptionsButton, "TOPRIGHT", -12, -32 - LFG_DROPS_DOWN)
	end
end

function AFTER.lfg(frame)
	local parent = rawget(_G, "LFGParentFrame")
	if type(parent) ~= "table" or forbidden(parent) then return end
	if not parent.stoaLFG then
		parent.stoaLFG = true
		local windows = Stoa.modules.Windows
		if windows and windows.DressClose then windows.DressClose(rawget(_G, "LFGParentFrameCloseButton")) end
		for _, key in ipairs({ "ListingTab", "BrowsingTab", "WhoListingTab" }) do dressSideTab(parent[key]) end
		local eye = rawget(_G, "LFGParentFramePortrait")
		if type(eye) == "table" and eye.SetAlpha and not forbidden(eye) then
			eye:SetAlpha(0)
			if eye.EnableMouse then eye:EnableMouse(false) end
		end
	end
	if type(frame) ~= "table" or forbidden(frame) then return end
	local name = frame.GetName and frame:GetName()
	placeLfg(frame, name)
	if frame.stoaLfgInside then return end
	frame.stoaLfgInside = true
	lfgCommon(frame)
	if name == "LFGListingFrame" then
		lfgListing(frame)
	elseif name == "LFGBrowseFrame" then
		lfgBrowse(frame)
	elseif name == "LFGWhoListFrame" then
		lfgWho(frame)
	end
end

-- Friends (the social window): its tabs come from a pool when the window
-- opens or its features change, so each new one is dressed as it turns up.
-- The Battle.net bar's metal strip and the gold rules around the list go;
-- the friend cards stay as Blizzard draws them.
local function dressSocialTabs(frame)
	local pool = frame.socialTabPool
	if not (pool and pool.EnumerateActive) then return end
	for tab in pool:EnumerateActive() do dressSideTab(tab, true) end
end

local SOCIAL_LISTS = { "FriendsList", "RecentAlliesList", "QuickJoinList", "FriendRequestsList", "RaidList", "RecruitAFriendList" }
function AFTER.social(frame)
	dressSocialTabs(frame)
	if frame.stoaSocial then return end
	frame.stoaSocial = true
	if frame.RefreshTabs then
		hooksecurefunc(frame, "RefreshTabs", function(own) dressSocialTabs(own) end)
	end
	local bar = frame.BattleNetBar
	if bar then
		hide(bar.Background)
		hide(bar.ControlsContainer and bar.ControlsContainer.BattleNetBackground)
	end
	hide(frame.TopFade)
	hide(frame.BottomFade)
	local hr, hg, hb = Stoa:Color("hairline")
	for _, key in ipairs(SOCIAL_LISTS) do
		local list = frame[key]
		if type(list) == "table" and not forbidden(list) then
			for _, rule in ipairs({ list.TopDivider, list.BottomDivider }) do
				if rule and rule.SetDesaturated then
					rule:SetDesaturated(true)
					rule:SetVertexColor(hr, hg, hb, 1)
				end
			end
		end
	end
	local windows = Stoa.modules.Windows
	-- The ignore list opens as its own small window beside it.
	if windows and windows.Dress and frame.IgnoreListFrame and not forbidden(frame.IgnoreListFrame) then
		windows:Dress(frame.IgnoreListFrame)
	end
end

-- Appearances: its Items and Sets tabs sit inside the page under the title,
-- so they are words with the accent underline like the macro tabs, not
-- gold tiles (Forever shows only Items).
local function paintWordTab(tab)
	local text = tab.Text or (tab.GetFontString and tab:GetFontString())
	local chosen = tab.stoaWordLine and (tab.isSelected or (tab.IsEnabled and not tab:IsEnabled()))
	if text then text:SetTextColor(Stoa:Color(chosen and "text" or "muted")) end
	if tab.stoaWordLine then tab.stoaWordLine:SetShown(chosen and true or false) end
end

local function wordTab(tab)
	if type(tab) ~= "table" or not tab.GetRegions or forbidden(tab) or tab.stoaWordTab then return end
	tab.stoaWordTab = true
	for _, region in ipairs({ tab:GetRegions() }) do
		if region.IsObjectType and region:IsObjectType("Texture") then region:SetAlpha(0) end
	end
	for _, key in ipairs({ "GetNormalTexture", "GetPushedTexture", "GetHighlightTexture", "GetDisabledTexture" }) do
		local tex = tab[key] and tab[key](tab)
		if tex then tex:SetAlpha(0) end
	end
	local text = tab.Text or (tab.GetFontString and tab:GetFontString())
	if not text then return end
	Stoa:SetFont(text, "sans", Stoa.typeSize.body)
	text:SetShadowOffset(0, 0)
	local line = tab:CreateTexture(nil, "OVERLAY")
	line:SetTexture(UI.WHITE)
	line:SetHeight(2)
	line:SetPoint("TOPLEFT", text, "BOTTOMLEFT", 0, -4)
	line:SetPoint("TOPRIGHT", text, "BOTTOMRIGHT", 0, -4)
	UI.tint(line, "accent")
	tab.stoaWordLine = line
	UI.applyTheme()
	tab:HookScript("OnShow", paintWordTab)
	tab:HookScript("OnEnter", function(self) local t = self.Text or self:GetFontString() if t and not self.stoaWordLine:IsShown() then t:SetTextColor(Stoa:Color("accent")) end end)
	tab:HookScript("OnLeave", paintWordTab)
	if tab.SetEnabled then hooksecurefunc(tab, "SetEnabled", paintWordTab) end
	if tab.Enable then hooksecurefunc(tab, "Enable", paintWordTab) end
	if tab.Disable then hooksecurefunc(tab, "Disable", paintWordTab) end
	paintWordTab(tab)
end

function wardrobeTabs()
	local page = rawget(_G, "WardrobeCollectionFrame")
	if type(page) ~= "table" or forbidden(page) then return end
	wordTab(page.ItemsTab)
	wordTab(page.SetsTab)
	-- The Items word and the search (the filter hangs from it) sat tight
	-- under the header band; they start a little lower.
	if not InCombatLockdown() then
		dropTops(page.ItemsTab, 10)
		dropTops(page.SearchBox, 10)
	end
	if page.ClickTab and not page.stoaTabsHooked then
		page.stoaTabsHooked = true
		hooksecurefunc(page, "ClickTab", function()
			for _, tab in ipairs({ page.ItemsTab, page.SetsTab }) do if type(tab) == "table" and tab.stoaWordLine then paintWordTab(tab) end end
		end)
	end
end

-- Books, letters and plaques: Blizzard colours the words for its parchment
-- (dark brown, or orange on some materials), which reads poorly on STOA's
-- dark page, so the words take STOA's text colour. Previous, the page
-- number and Next sat across the header band's edge; they move to a row
-- along the foot of the page.
local function paintBook()
	local text = _G.ItemTextPageText
	if not (text and text.SetTextColor) then return end
	local r, g, b = Stoa:Color("text")
	text:SetTextColor("P", r, g, b)
	local ar, ag, ab = Stoa:Color("accent")
	for _, tag in ipairs({ "H1", "H2", "H3" }) do text:SetTextColor(tag, ar, ag, ab) end
	for _, key in ipairs({ "ItemTextFramePageBg", "ItemTextMaterialTopLeft", "ItemTextMaterialTopRight", "ItemTextMaterialBotLeft", "ItemTextMaterialBotRight" }) do
		local art = _G[key]
		if art and art.SetAlpha then art:SetAlpha(0) end
	end
end

local BOOK_FOOT = 36
local function seatBook(frame)
	if InCombatLockdown() then return end
	local scroll = _G.ItemTextScrollFrame
	if scroll and scroll.SetPoint then
		scroll:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 6, BOOK_FOOT + 4)
	end
	local prev, nextPage, page = _G.ItemTextPrevPageButton, _G.ItemTextNextPageButton, _G.ItemTextCurrentPage
	if prev then
		prev:ClearAllPoints()
		prev:SetPoint("CENTER", frame, "BOTTOMLEFT", 30, BOOK_FOOT / 2)
	end
	if nextPage then
		nextPage:ClearAllPoints()
		nextPage:SetPoint("CENTER", frame, "BOTTOMRIGHT", -30, BOOK_FOOT / 2)
	end
	if page then
		page:ClearAllPoints()
		page:SetPoint("CENTER", frame, "BOTTOM", 0, BOOK_FOOT / 2)
	end
end

function AFTER.book(frame)
	if not frame.stoaBook then
		frame.stoaBook = true
		local rule = UI.line(frame, "hairline")
		rule:SetPoint("BOTTOMLEFT", 14, BOOK_FOOT)
		rule:SetPoint("BOTTOMRIGHT", -14, BOOK_FOOT)
		local page = _G.ItemTextCurrentPage
		if page then
			Stoa:SetFont(page, "sans", Stoa.typeSize.caption)
			page:SetTextColor(Stoa:Color("muted"))
		end
		for _, button in ipairs({ _G.ItemTextPrevPageButton, _G.ItemTextNextPageButton }) do
			local word = button and button.GetFontString and button:GetFontString()
			if not word and button then
				for _, region in ipairs({ button:GetRegions() }) do
					if region.IsObjectType and region:IsObjectType("FontString") then word = region end
				end
			end
			if word then
				Stoa:SetFont(word, "sans", Stoa.typeSize.body)
				word:SetTextColor(Stoa:Color("text"))
			end
		end
		-- The game sets colours and the scroll frame's place on every page.
		frame:HookScript("OnEvent", function(own, event)
			if event == "ITEM_TEXT_BEGIN" or event == "ITEM_TEXT_READY" then
				xpcall(paintBook, Stoa.catch)
				xpcall(seatBook, Stoa.catch, own)
			end
		end)
	end
	paintBook()
	seatBook(frame)
end

local afterHooked = false
local function runAfter(target, frame)
	local step = target.after and AFTER[target.after]
	if not step then return end
	step(frame)
	-- The game lays panels out again through UpdateUIPanelPositions.
	if not afterHooked and UpdateUIPanelPositions then
		afterHooked = true
		hooksecurefunc("UpdateUIPanelPositions", function()
			for _, t in ipairs(TARGETS) do
				local f = t.after and _G[t.name]
				if type(f) == "table" and f.IsShown and f:IsShown() then xpcall(AFTER[t.after], Stoa.catch, f) end
			end
		end)
	end
end

local function dressLater(target, frame)
	local windows = Stoa.modules.Windows
	if InCombatLockdown() and windows and windows.Locked and not windows.Locked(frame) then
		-- Opened in a fight, with nothing protected inside: the look goes
		-- on now. The layout steps that hold back in a fight follow after.
		xpcall(dressTarget, Stoa.catch, target, frame)
		xpcall(runAfter, Stoa.catch, target, frame)
		if target.after and not target.afterWaits then
			target.afterWaits = true
			Stoa:AfterCombat(function()
				target.afterWaits = nil
				xpcall(runAfter, Stoa.catch, target, frame)
			end)
		end
		return
	end
	Stoa:AfterCombat(function()
		xpcall(dressTarget, Stoa.catch, target, frame)
		xpcall(runAfter, Stoa.catch, target, frame)
	end)
end

-- Dresses one window if it exists, once, out of combat.
local function tryTarget(target)
	local frame = _G[target.name]
	if type(frame) ~= "table" or not frame.GetObjectType or forbidden(frame) then return end
	if not target.hooked and frame.HookScript then
		target.hooked = true
		-- Some panels make part of their art on first show.
		frame:HookScript("OnShow", function() dressLater(target, frame) end)
	end
	if target.done then return end
	target.done = true
	dressLater(target, frame)
end

local function tryAll()
	for _, target in ipairs(TARGETS) do
		xpcall(tryTarget, Stoa.catch, target)
	end
end

-- The group loot roll cards (need, greed, pass): the stone toast gives way
-- to a Stoa card, the item's name takes the serif and the timer runs as a
-- flat accent bar. Nothing moves; the item's quality border and the game's
-- own buttons stay. These aren't protected, so they dress at once.
local function dressRoll(frame)
	if frame.stoaRollDressed or forbidden(frame) then return end
	frame.stoaRollDressed = true
	hide(frame.Background)
	hide(frame.Border)
	hide(frame.NineSlice)
	hide(frame.Bg)
	UI.surface(frame, "card", { alpha = 0.96 })
	if frame.Name then Stoa:SetFont(frame.Name, "serif", Stoa.typeSize.label) end
	local timer = frame.Timer
	if timer and timer.SetStatusBarTexture then
		timer:SetStatusBarTexture(UI.WHITE)
		timer:SetStatusBarColor(Stoa:Color("accent"))
		timer:SetHeight(3)
		if timer.Background then timer.Background:SetColorTexture(1, 1, 1, 0.08) end
		-- The game tucks the timer a level under the card on every show,
		-- where the new fill would cover it.
		local function lift() timer:SetFrameLevel(frame:GetFrameLevel() + 1) end
		frame:HookScript("OnShow", lift)
		lift()
	end
end

local function dressRolls()
	for i = 1, 4 do
		local frame = _G["GroupLootFrame" .. i]
		if type(frame) == "table" and frame.GetObjectType then xpcall(dressRoll, Stoa.catch, frame) end
	end
end

-- The loot window (a flat panel of item cards): STOA's card, the title in
-- the serif over a hairline, and each item a dark tile with a short bar in
-- the item's quality colour on its left. Blizzard tints its own card art by
-- quality on every fill, so that art is faded out, never replaced; the
-- item's name keeps Blizzard's quality colour.
local function lootQualityColor(quality)
	if type(quality) ~= "number" then return nil end
	local colors = rawget(_G, "ITEM_QUALITY_COLORS")
	local c = colors and colors[quality]
	if c and c.r then return c.r, c.g, c.b end
	if C_Item and C_Item.GetItemQualityColor then
		local ok, r, g, b = pcall(C_Item.GetItemQualityColor, quality)
		if ok and r then return r, g, b end
	end
end

local function paintLootRow(row)
	if not row.stoaLootFill then return end
	for _, key in ipairs({ "NameFrame", "BorderFrame", "HighlightNameFrame", "PushedNameFrame", "QualityStripe" }) do alphaOff(row[key]) end
	local data = row.GetElementData and row:GetElementData()
	local r, g, b = lootQualityColor(type(data) == "table" and data.quality)
	if r then
		row.stoaLootBar:SetVertexColor(r, g, b, 1)
		if row.QualityText then row.QualityText:SetTextColor(r, g, b) end
	else
		row.stoaLootBar:SetVertexColor(Stoa:Color("muted"))
	end
	local pr, pg, pb = Stoa:Color("panel")
	local lift = row.stoaOver and 0.04 or 0
	row.stoaLootFill:SetVertexColor(pr + lift, pg + lift, pb + lift, 0.9)
end

local function dressLootRow(row)
	if type(row) ~= "table" or forbidden(row) or row.stoaLootFill or not row.NameFrame then return end
	local fill = UI.sliced(row, "BACKGROUND", "CardFill.tga")
	if not fill then return end
	fill:ClearAllPoints()
	fill:SetPoint("TOPLEFT", 0, 0)
	fill:SetPoint("BOTTOMRIGHT", 0, 0)
	fill:SetDrawLayer("BACKGROUND", -8)
	local bar = row:CreateTexture(nil, "ARTWORK", nil, 7)
	bar:SetTexture(UI.WHITE)
	bar:SetWidth(2)
	bar:SetPoint("TOPLEFT", 0, -10)
	bar:SetPoint("BOTTOMLEFT", 0, 10)
	row.stoaLootFill, row.stoaLootBar = fill, bar
	if row.Text then
		Stoa:SetFont(row.Text, "sans", Stoa.typeSize.body)
		row.Text:SetShadowOffset(0, 0)
	end
	if row.QualityText then Stoa:SetFont(row.QualityText, "sans", Stoa.typeSize.micro) end
	if row.Init then hooksecurefunc(row, "Init", paintLootRow) end
	-- Only the item button takes the mouse (its hit rect runs the card's
	-- full width). A script on the card itself would make the card take
	-- the mouse too and could catch the click meant for the item.
	local item = row.Item
	if type(item) == "table" and item.HookScript then
		item:HookScript("OnEnter", function() row.stoaOver = true paintLootRow(row) end)
		item:HookScript("OnLeave", function() row.stoaOver = nil paintLootRow(row) end)
	end
	paintLootRow(row)
end

local function dressLoot(frame)
	if type(frame) ~= "table" or forbidden(frame) or frame.stoaLootDressed then return end
	frame.stoaLootDressed = true
	hide(frame.NineSlice)
	alphaOff(frame.Bg)
	UI.surface(frame, "card", { alpha = 0.96 })
	local strip = frame.TitleContainer
	local title = strip and strip.TitleText
	if title then
		Stoa:SetFont(title, "serif", Stoa.typeSize.label)
		title:SetTextColor(Stoa:Color("text"))
		local rule = frame:CreateTexture(nil, "ARTWORK")
		rule:SetTexture(UI.WHITE)
		rule:SetHeight(1)
		UI.pixel(rule, "height")
		rule:SetPoint("TOPLEFT", 8, -22)
		rule:SetPoint("TOPRIGHT", -8, -22)
		UI.tint(rule, "hairline")
	end
	local windows = Stoa.modules.Windows
	if windows then
		if windows.DressClose then xpcall(windows.DressClose, Stoa.catch, frame.ClosePanelButton) end
		if windows.DressScrollBar then xpcall(windows.DressScrollBar, Stoa.catch, frame.ScrollBar) end
	end
	local box = frame.ScrollBox
	if type(box) == "table" then
		for _, getter in ipairs({ "GetUpperShadowTexture", "GetLowerShadowTexture" }) do
			local ok, shadow = pcall(function() return box[getter] and box[getter](box) end)
			if ok and shadow then alphaOff(shadow) end
		end
		eachRow(box, "stoaLootRows", dressLootRow)
	end
	UI.applyTheme()
end

-- Right-click and dropdown menus (on a player, a bag item, the minimap,
-- a filter): the game's grey stone ground becomes STOA's panel with a
-- fine edge. A menu frame is borrowed from a pool and wiped when it
-- closes, so the look is put on each time one is built, with textures
-- the menu itself hands out; nothing of STOA's stays on it.
local MENU_OUT_X, MENU_OUT_Y = 8, 2
local function dressMenu(menu)
	if type(menu) ~= "table" or forbidden(menu) or type(menu.AttachTexture) ~= "function" or not menu.GetRegions then return end
	for _, region in ipairs({ menu:GetRegions() }) do
		if region.IsObjectType and region:IsObjectType("Texture") then region:SetAlpha(0) end
	end
	local fill, edge = menu:AttachTexture(), menu:AttachTexture()
	if not (fill and edge) then return end
	for _, tex in ipairs({ fill, edge }) do
		tex:SetPoint("TOPLEFT", -MENU_OUT_X, MENU_OUT_Y)
		tex:SetPoint("BOTTOMRIGHT", MENU_OUT_X, -MENU_OUT_Y)
	end
	fill:SetDrawLayer("BACKGROUND", 0)
	edge:SetDrawLayer("BORDER", 0)
	local r, g, b = Stoa:Color("panel")
	if UI.slice(fill, "CardFill.tga") and UI.slice(edge, "CardEdge.tga") then
		fill:SetVertexColor(r, g, b, 0.98)
		local er, eg, eb, ea = Stoa:Color("hairline")
		edge:SetVertexColor(er, eg, eb, ea or 1)
	else
		fill:SetColorTexture(r, g, b, 0.98)
		edge:SetAlpha(0)
	end
	fill:Show()
	edge:Show()
end

local function dressMenus()
	local style = rawget(_G, "MenuStyle1Mixin")
	if type(style) ~= "table" or type(style.Generate) ~= "function" then return end
	Stoa.SafeHook(style, "Generate", dressMenu)
end

function More:OnEnable()
	xpcall(dressMenus, Stoa.catch)
	tryAll()
	dressRolls()
	xpcall(dressLoot, Stoa.catch, rawget(_G, "LootFrame"))
	Stoa:On("STOA_THEME_CHANGED", function()
		for i = 1, 4 do
			local frame = _G["GroupLootFrame" .. i]
			local timer = type(frame) == "table" and frame.stoaRollDressed and frame.Timer
			if timer then timer:SetStatusBarColor(Stoa:Color("accent")) end
		end
	end)
	-- Load-on-demand windows (spellbook, auction house, communities, group
	-- finder) make their frames when their addon loads.
	Stoa:On("ADDON_LOADED", function(addon)
		if type(addon) == "string" and addon:find("^Blizzard_") then tryAll() end
	end)
	-- The flight map's addon has a part that loads at startup, so its
	-- ADDON_LOADED can come before the window exists and not again when the
	-- window is made. Opening a flight master dresses it as a backstop.
	Stoa:On("TAXIMAP_OPENED", function()
		tryAll()
		C_Timer.After(0, function() xpcall(tryAll, Stoa.catch) end)
	end)
end
