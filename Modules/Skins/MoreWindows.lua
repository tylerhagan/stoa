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
			local fill = UI.sliced(frame, "BACKGROUND", "WindowFill.tga", 2)
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
-- The roster's member list (wide, with column heads 60px above its top) and
-- its two view dropdowns are placed by guildRoster instead.
local ROSTER_DROPDOWNS = { "GuildMemberListDropdown", "CommunityMemberListDropdown" }
local guildRoster
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

local function paintGuildTab(tab)
	local word = tab.stoaGuildWord
	if not word then return end
	local chosen = tab.GetChecked and tab:GetChecked()
	word:SetTextColor(Stoa:Color(chosen and "text" or "muted"))
	tab.stoaGuildLine:SetShown(chosen and true or false)
end

local function guildTabWord(tab, label)
	if type(tab) ~= "table" or forbidden(tab) or tab.stoaGuildWord then return end
	for _, region in ipairs({ tab:GetRegions() }) do
		if region.IsObjectType and region:IsObjectType("Texture") then region:SetAlpha(0) end
	end
	for _, key in ipairs({ "GetNormalTexture", "GetPushedTexture", "GetHighlightTexture", "GetCheckedTexture", "GetDisabledTexture" }) do
		local tex = tab[key] and tab[key](tab)
		if tex then tex:SetAlpha(0) end
	end
	local word = UI.text(tab, "sans", Stoa.typeSize.label, "muted", "CENTER")
	word:SetPoint("CENTER", 0, 1)
	word:SetText(label)
	local line = tab:CreateTexture(nil, "OVERLAY")
	line:SetTexture(UI.WHITE)
	line:SetHeight(2)
	line:SetPoint("TOPLEFT", word, "BOTTOMLEFT", 0, -4)
	line:SetPoint("TOPRIGHT", word, "BOTTOMRIGHT", 0, -4)
	UI.tint(line, "accent")
	tab.stoaGuildWord, tab.stoaGuildLine = word, line
	UI.applyTheme()
	hooksecurefunc(tab, "SetChecked", paintGuildTab)
	tab:HookScript("OnEnter", function(self) if not self:GetChecked() then self.stoaGuildWord:SetTextColor(Stoa:Color("accent")) end end)
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
				tab:SetFrameLevel(frame:GetFrameLevel() + 120)
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
		title:SetPoint("BOTTOMLEFT", header, "LEFT", 18, 1)
		title:SetPoint("RIGHT", right, "LEFT", -16, 0)
		sub:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -3)
		sub:SetPoint("RIGHT", title, "RIGHT")
	end
	sub:SetShown(not small)
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

local AFTER = {}
local wardrobeTabs
function AFTER.communities(frame)
	-- Its minimise button was the last red one in the header.
	local windows = Stoa.modules.Windows
	if windows and windows.DressMaxMin then windows.DressMaxMin(frame.MaximizeMinimizeFrame) end
	if not frame.stoaGuildHooks then
		frame.stoaGuildHooks = true
		if frame.UpdateCommunitiesTabs then
			hooksecurefunc(frame, "UpdateCommunitiesTabs", function(own)
				if not InCombatLockdown() then
					placeGuildTabs(own)
					guildTitle(own)
				end
			end)
		end
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
	-- The MOTD row takes its room only on the chat and roster pages.
	local drop = listMode and (COMMUNITIES_DROP + MOTD_ROW) or COMMUNITIES_DROP
	for _, key in ipairs(COMMUNITIES_PARTS) do dropTops(frame[key], drop) end
	guildRoster(frame, drop)
	placeGuildTabs(frame)
	guildTitle(frame)
	guildMotd(frame, listMode)
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
	end
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
local ROSTER_HEAD = 64
local function rosterTop(frame)
	local band = (frame.stoaHeader and frame.stoaHeader.stoaHeight) or 30
	return band + 2 + MOTD_ROW + ROSTER_HEAD
end

local function placeMemberList(frame, drop)
	local list = frame.MemberList
	if type(list) ~= "table" or forbidden(list) or InCombatLockdown() then return end
	if list.expandedDisplay and not guildMinimized(frame) then
		list:SetPoint("TOPLEFT", frame, "TOPLEFT", LIST_EDGE + 22, -rosterTop(frame))
	else
		dropTops(list, drop)
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
				local small = guildMinimized(frame)
				local d = (not small and guildListMode(frame)) and (COMMUNITIES_DROP + MOTD_ROW) or COMMUNITIES_DROP
				xpcall(placeMemberList, Stoa.catch, frame, d)
			end)
		end
		placeMemberList(frame, drop)
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

function AFTER.professions(frame)
	dressSideTab(frame.ProfessionsOverviewTab)
	for _, tab in ipairs(frame.rightProfessionTabs or {}) do dressSideTab(tab) end
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

function More:OnEnable()
	tryAll()
	dressRolls()
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
end
