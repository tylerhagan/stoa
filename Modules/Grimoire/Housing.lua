-- Stoa: houses Blizzard's chat and action bar inside the Grimoire console.
-- Chat takes the console's left page and margin notes move into chat. The
-- action bar keeps its Edit Mode position in the console's centre, but loses
-- its gryphons and border so it sits on the ink.
--
-- Both frames belong to Edit Mode, which re-places them whenever a layout is
-- applied, so Stoa puts them back after each apply. Nothing here runs in
-- combat.
local _, ns = ...
local Stoa = ns.Stoa
local Console = Stoa.modules.Grimoire
local UI = Stoa.UI

local CHAT_WIDTH = 440
local CHAT_BOTTOM = 20
local CHAT_TOP_PAD = 16
local CHAT_TAB_HEIGHT = 22
-- With the leather art the chat starts just under the gold top border and
-- its tabs stand on that border.
local ART_CHAT_GAP = 14

-- Tab art, in texture pixels (drawn at the console art's scale): the tab's
-- sides at X0 and 128 - X0, its top at TOP and the console's top edge at
-- FOOT. Caps are CAP wide; the middle column stretches.
local TAB_ART = { size = 128, x0 = 32, top = 24, foot = 70, cap = 52 }
local TAB_TEXT_PAD = 26

local function artOn()
	return Console.db.art
end

local function tabRise()
	return (TAB_ART.foot - TAB_ART.top) * Console.ART_SCALE
end

local function placeChat()
	local chat = ChatFrame1
	if not chat then return end
	local bottom = CHAT_BOTTOM
	local top = artOn() and ART_CHAT_GAP or CHAT_TOP_PAD + CHAT_TAB_HEIGHT
	chat:ClearAllPoints()
	chat:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", (Console:PageInset()), bottom)
	chat:SetSize(CHAT_WIDTH, Console:OpenHeight() - bottom - top)
	-- The ink panel is the background, so the chat window's own goes.
	if FCF_SetWindowAlpha then FCF_SetWindowAlpha(chat, 0) end
end

-- With the art the tab row stands on the console's top edge.
-- Chat tabs ------------------------------------------------------------------
-- With the leather art, Stoa draws its own tabs standing on the console's
-- top edge, one per docked chat window, and Blizzard's tab row is only made
-- invisible. Blizzard's tabs are never reshaped: its chat code runs through
-- them on every update and breaks if they change under it. Stoa's tabs
-- only read the dock and pass clicks on: left selects the window, right
-- opens Blizzard's tab menu, middle pops a window back in.
--
-- The selected tab opens into the console, its gold border running up and
-- round it; the rest sit behind the edge, dimmer, with the border across
-- their foot. Its words read in the accent and the rest in muted bone.
local TAB_GAP = 2

local strip, tabs = nil, {}

local function blizzardTab(chatFrame)
	local name = chatFrame and chatFrame.GetName and chatFrame:GetName()
	return name and _G[name .. "Tab"]
end

-- Left cap, stretched middle and right cap of one texture file.
local function capped(tab, sublevel, gold)
	local s = Console.ART_SCALE
	local size, cap = TAB_ART.size, TAB_ART.cap
	local parts = {}
	for i = 1, 3 do
		local tex = tab:CreateTexture(nil, "BACKGROUND", nil, sublevel)
		tex:SetHeight(size * s)
		if gold then
			UI.tint(tex, "accent")
			tex:SetVertexColor(Stoa:Color("accent"))
		end
		parts[i] = tex
	end
	local left, middle, right = parts[1], parts[2], parts[3]
	left:SetWidth(cap * s)
	right:SetWidth(cap * s)
	left:SetTexCoord(0, cap / size, 0, 1)
	middle:SetTexCoord((size / 2) / size, (size / 2 + 1) / size, 0, 1)
	right:SetTexCoord(1 - cap / size, 1, 0, 1)
	left:SetPoint("TOPLEFT", tab, "BOTTOMLEFT", -TAB_ART.x0 * s, TAB_ART.foot * s)
	right:SetPoint("TOPRIGHT", tab, "BOTTOMRIGHT", TAB_ART.x0 * s, TAB_ART.foot * s)
	middle:SetPoint("TOPLEFT", left, "TOPRIGHT")
	middle:SetPoint("BOTTOMRIGHT", right, "BOTTOMLEFT")
	return parts
end

local function paintTab(tab)
	local kind = tab.selected and "Open" or "Closed"
	if tab.kind ~= kind then
		tab.kind = kind
		for _, tex in ipairs(tab.base) do tex:SetTexture(UI.MEDIA .. "Textures\\ChatTab" .. kind) end
		for _, tex in ipairs(tab.lines) do tex:SetTexture(UI.MEDIA .. "Textures\\ChatTab" .. kind .. "Lines") end
	end
	-- The open tab sits in front, so its border reads over its neighbours'.
	tab:SetFrameLevel(strip:GetFrameLevel() + (tab.selected and 3 or 1))
	local token = (tab.selected and "accent") or (tab:IsMouseOver() and "text") or "muted"
	tab.label:SetTextColor(Stoa:Color(token))
end

local function makeTab()
	local tab = CreateFrame("Button", nil, strip)
	tab:SetHeight(tabRise())
	tab:RegisterForClicks("LeftButtonUp", "RightButtonUp", "MiddleButtonUp")
	tab.base = capped(tab, 1)
	tab.lines = capped(tab, 2, true)
	local label = tab:CreateFontString(nil, "ARTWORK")
	Stoa:SetFont(label, "sans", Stoa.typeSize.caption + 1)
	label:SetShadowOffset(0, 0)
	label:SetPoint("CENTER", 0, -3)
	tab.label = label
	tab:SetScript("OnClick", function(self, button)
		-- Click Blizzard's own tab, so its own handler does the work.
		local blizzard = blizzardTab(self.chatFrame)
		if blizzard then blizzard:Click(button) end
	end)
	tab:SetScript("OnEnter", paintTab)
	tab:SetScript("OnLeave", paintTab)
	return tab
end

local function dockedWindows()
	local dock = GENERAL_CHAT_DOCK
	if not (dock and FCFDock_GetChatFrames) then return {} end
	local list = {}
	for _, chatFrame in ipairs(FCFDock_GetChatFrames(dock)) do
		local blizzard = blizzardTab(chatFrame)
		if blizzard and (chatFrame:IsShown() or blizzard:IsShown()) then
			list[#list + 1] = chatFrame
		end
	end
	return list
end

-- Rebuilds the strip from the dock: which windows, their names, which one
-- is selected.
local function refreshTabs()
	if not strip then return end
	local selected = FCFDock_GetSelectedWindow and FCFDock_GetSelectedWindow(GENERAL_CHAT_DOCK)
	local x = 0
	local windows = dockedWindows()
	for i, chatFrame in ipairs(windows) do
		local tab = tabs[i] or makeTab()
		tabs[i] = tab
		tab.chatFrame = chatFrame
		local blizzard = blizzardTab(chatFrame)
		local text = blizzard and blizzard.GetText and blizzard:GetText()
		tab.label:SetText(text or "")
		local width = tab.label:GetStringWidth()
		if type(width) ~= "number" then width = 40 end
		tab:SetWidth(width + TAB_TEXT_PAD * 2)
		tab:ClearAllPoints()
		tab:SetPoint("BOTTOMLEFT", strip, "BOTTOMLEFT", x, 0)
		x = x + tab:GetWidth() + TAB_GAP
		tab.selected = chatFrame == selected
		paintTab(tab)
		tab:Show()
	end
	for i = #windows + 1, #tabs do tabs[i]:Hide() end
end

local function buildTabs()
	if strip then return end
	strip = CreateFrame("Frame", "StoaChatTabs", UIParent)
	-- Above the chat frames, so these take the clicks rather than
	-- Blizzard's invisible tabs underneath.
	strip:SetFrameStrata("MEDIUM")
	strip:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", (Console:PageInset()), Console:OpenHeight())
	strip:SetSize(CHAT_WIDTH, tabRise())
	Console.tabArt = Console.tabArt or {}
	table.insert(Console.tabArt, strip)
	-- Blizzard's tab row stays where it is, working, just unseen.
	if GeneralDockManager then GeneralDockManager:SetAlpha(0) end
	refreshTabs()
end

local function safeRefresh()
	xpcall(refreshTabs, geterrorhandler())
end

local function actionBar()
	return MainActionBar or MainMenuBar
end

local function hideBarArt()
	local bar = actionBar()
	if not bar then return end
	for _, key in ipairs({ "EndCaps", "BorderArt", "Background" }) do
		local art = bar[key]
		if art and art.Hide then art:Hide() end
	end
end

-- Bags and the game menu leave the action bar row for the console's
-- bottom-right corner: bags, a gap, then the menu, a size down and quiet
-- until the mouse is over them. Bag slots take the action buttons' rounded
-- sockets.
local MENU_SCALE = 0.8
local MENU_BOTTOM = 12
local MENU_GAP = 14
local MENU_REST_ALPHA = 0.55
local BAG_SLOTS = {
	"MainMenuBarBackpackButton", "CharacterBag0Slot", "CharacterBag1Slot",
	"CharacterBag2Slot", "CharacterBag3Slot", "CharacterReagentBag0Slot",
}

local function menuFrames()
	return MicroMenuContainer or MicroMenu, BagsBar
end

local function placeMenu()
	local menu, bags = menuFrames()
	local inset = Console:PageInset()
	if menu then
		menu:ClearAllPoints()
		menu:SetScale(MENU_SCALE)
		menu:SetPoint("BOTTOMRIGHT", UIParent, "BOTTOMRIGHT", -inset / MENU_SCALE, MENU_BOTTOM / MENU_SCALE)
	end
	if bags then
		bags:ClearAllPoints()
		bags:SetScale(MENU_SCALE)
		if menu then
			bags:SetPoint("BOTTOMRIGHT", menu, "BOTTOMLEFT", -MENU_GAP, 0)
		else
			bags:SetPoint("BOTTOMRIGHT", UIParent, "BOTTOMRIGHT", -inset / MENU_SCALE, MENU_BOTTOM / MENU_SCALE)
		end
	end
	local bars = Stoa.modules.ActionBars
	if bars and bars.db and bars.db.enabled then
		for _, name in ipairs(BAG_SLOTS) do
			local slot = _G[name]
			if slot then
				xpcall(bars.Skin, geterrorhandler(), bars, slot)
				if slot.IconBorder then slot.IconBorder:SetAlpha(0) end
			end
		end
	end
end

-- Bags open above the console rather than over it. Blizzard stacks bag
-- windows up from the screen's bottom-right corner; the ones it pins to the
-- screen are lifted clear of the console, and the rest follow them.
local BAG_LIFT_GAP = 16

local function liftBags()
	local floor = Console:OpenHeight() + BAG_LIFT_GAP
	local frames = { ContainerFrameCombinedBags }
	for i = 1, 13 do frames[#frames + 1] = _G["ContainerFrame" .. i] end
	for _, bag in ipairs(frames) do
		if bag and bag:IsShown() and bag:GetNumPoints() == 1 then
			local point, relativeTo, relativePoint, x, y = bag:GetPoint(1)
			local onScreen = relativeTo == nil or relativeTo == UIParent
			if onScreen and point and point:find("^BOTTOM") and type(y) == "number" and y < floor then
				bag:SetPoint(point, relativeTo or UIParent, relativePoint, x, floor)
			end
		end
	end
end

-- Rests dim, brightens while the mouse is over either row.
local function watchMenu()
	local menu, bags = menuFrames()
	if not (menu or bags) or not MouseIsOver then return end
	local lit
	local function update()
		local over = (menu and menu:IsVisible() and MouseIsOver(menu))
			or (bags and bags:IsVisible() and MouseIsOver(bags))
		if over == lit then return end
		lit = over
		local alpha = over and 1 or MENU_REST_ALPHA
		if menu then menu:SetAlpha(alpha) end
		if bags then bags:SetAlpha(alpha) end
	end
	update()
	C_Timer.NewTicker(0.15, update)
end

-- Runs fn now, or after combat if it can't run yet. Each step is guarded so a
-- renamed Blizzard frame costs one feature, not the console.
local function safely(fn)
	Stoa:AfterCombat(function()
		xpcall(fn, geterrorhandler())
	end)
end

function Console:House()
	local db = self.db

	local function apply()
		if db.houseChat then
			safely(placeChat)
			if artOn() then safely(buildTabs) end
		end
		if db.hideBarArt then safely(hideBarArt) end
		if db.houseMenu then safely(placeMenu) end
	end

	if db.houseChat then
		-- Notes now arrive in chat, so the notes page steps aside.
		self.leftPage:Hide()
		Stoa.notesInConsole = false
	end

	apply()
	if db.houseMenu then
		watchMenu()
		if UpdateContainerFrameAnchors then
			hooksecurefunc("UpdateContainerFrameAnchors", function()
				if not InCombatLockdown() then xpcall(liftBags, geterrorhandler()) end
			end)
		end
	end
	Stoa:On("PLAYER_ENTERING_WORLD", apply)
	Stoa:On("UI_SCALE_CHANGED", apply)
	Stoa:On("EDIT_MODE_LAYOUTS_UPDATED", apply)
	if EventRegistry then
		EventRegistry:RegisterCallback("EditMode.Exit", apply, self)
	end

	if db.houseChat and db.art then
		-- Read-only hooks: Stoa's tabs follow the dock, nothing is changed.
		for _, name in ipairs({ "FCFDock_UpdateTabs", "FCFDock_SelectWindow", "FCF_SetWindowName", "FCF_OpenNewWindow", "FCF_Close", "FCF_DockFrame", "FCF_UnDockFrame" }) do
			if _G[name] then hooksecurefunc(name, safeRefresh) end
		end
		Stoa:On("STOA_THEME_CHANGED", safeRefresh)
	end
	local bar = actionBar()
	if bar and bar.UpdateEndCaps then
		hooksecurefunc(bar, "UpdateEndCaps", function()
			if db.hideBarArt then safely(hideBarArt) end
		end)
	end
end
