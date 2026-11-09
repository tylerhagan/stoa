-- Stoa: more Blizzard windows in the same dress as the quest and merchant
-- windows (see Windows.lua): spellbook and talents, world map border, mail,
-- auction house, group finder, friends and guild, game menu and the settings
-- panel border.
--
-- Many of these load with their own addon the first time they open, so each
-- is dressed when its frame turns up (ADDON_LOADED) and again on first show.
-- Every frame name is looked up and skipped silently if this client lacks it.
-- Only a window's own border art is hidden; maps, pins, icons and lists stay
-- exactly as Blizzard draws them.
local _, ns = ...
local Stoa = ns.Stoa
local UI = Stoa.UI

local More = Stoa:NewModule("MoreWindows")

-- How each window is dressed: the default is the full Windows:Dress; "border"
-- only hides the stone edge and puts a Stoa panel behind; "map" dresses the
-- world map's border frame alone. "parts" are extra named frames whose own
-- art is hidden (insets and money bars).
local TARGETS = {
	-- The spellbook's tabs start just under its title, so its metal strip
	-- stays short and the title sits above them.
	{ name = "PlayerSpellsFrame", band = 24 },
	{ name = "SpellBookFrame", band = 24 },
	{ name = "PlayerTalentFrame" },
	{ name = "TalentFrame" },
	{ name = "MailFrame", parts = { "MailFrameInset", "SendMailMoneyInset", "SendMailMoneyBg" } },
	{ name = "OpenMailFrame", parts = { "OpenMailFrameInset" } },
	{ name = "AuctionHouseFrame" },
	{ name = "PVEFrame" },
	{ name = "LFDParentFrame" },
	{ name = "FriendsFrame", parts = { "FriendsFrameInset", "WhoFrameListInset", "WhoFrameEditBoxInset" } },
	-- A slimmer band: the channel dropdown and online count start just
	-- under the title, and the usual band reached halfway down them.
	{ name = "CommunitiesFrame", band = 30, after = "communities" },
	-- The game menu and the settings panel are left alone: addons touching
	-- them are a known cause of blocked-action errors (Edit Mode, logout).
	-- The map canvas, pins and quest panel are never touched.
	{ name = "WorldMapFrame", mode = "map" },
}

local hide = Stoa.frames.hide

local function hideOwnArt(frame)
	if not (frame and frame.GetRegions) then return end
	for _, region in ipairs({ frame:GetRegions() }) do
		if region.IsObjectType and region:IsObjectType("Texture") then region:SetAlpha(0) end
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

local function dressTarget(target, frame)
	if target.mode == "border" then
		dressBorder(frame)
	elseif target.mode == "map" then
		-- The border frame holds the stone edge and title, and it is drawn
		-- above the canvas, so it gets the edge and header only: a fill or
		-- the stone there would cover the map.
		if frame.BorderFrame then dressBorder(frame.BorderFrame, true) end
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
		dressFull(frame)
	end
	for _, partName in ipairs(target.parts or {}) do
		local part = _G[partName]
		if type(part) == "table" and not forbidden(part) then hideOwnArt(part) end
	end
end

-- Guild & Communities: the channel row, the chat and the member list
-- start a little lower, so the dropdowns sit clear of the header band with
-- room to breathe. Only top anchors move (the bottoms stay), and each is
-- moved once per placing: the game puts them back whenever it lays the
-- window out again (tab, maximise, minimise), and they follow.
local COMMUNITIES_DROP = 10
local COMMUNITIES_PARTS = {
	"StreamDropdown", "CommunitiesListDropdown", "GuildMemberListDropdown", "CommunityMemberListDropdown",
	"VoiceChatHeadset", "Chat", "MemberList",
}

local function dropTops(part)
	if not (part and part.GetNumPoints) or forbidden(part) then return end
	part.stoaDropped = part.stoaDropped or {}
	local points = {}
	for i = 1, part:GetNumPoints() do points[i] = { part:GetPoint(i) } end
	local moved = false
	for _, p in ipairs(points) do
		local point, y = p[1], p[5] or 0
		if type(point) == "string" and point:find("^TOP") and part.stoaDropped[point] ~= y then
			p[5] = y - COMMUNITIES_DROP
			part.stoaDropped[point] = p[5]
			moved = true
		end
	end
	if not moved then return end
	part:ClearAllPoints()
	for _, p in ipairs(points) do part:SetPoint(p[1], p[2], p[3], p[4] or 0, p[5] or 0) end
end

local AFTER = {}
function AFTER.communities(frame)
	if InCombatLockdown() or not frame:IsShown() then return end
	for _, key in ipairs(COMMUNITIES_PARTS) do dropTops(frame[key]) end
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

function More:OnEnable()
	tryAll()
	-- Load-on-demand windows (spellbook, auction house, communities, group
	-- finder) make their frames when their addon loads.
	Stoa:On("ADDON_LOADED", function(addon)
		if type(addon) == "string" and addon:find("^Blizzard_") then tryAll() end
	end)
end
