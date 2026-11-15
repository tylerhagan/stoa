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
local hooksecurefunc = Stoa.SafeHook
local Console = Stoa.modules.Grimoire
local UI = Stoa.UI

local CHAT_WIDTH = 440
local CHAT_BOTTOM = 20
local CHAT_TOP_PAD = 16
local CHAT_TAB_HEIGHT = 22
-- With the leather art the chat starts just under the gold top border and
-- its tabs stand on that border. The gap gives the top line some air;
-- the tabs sit on their own strip, so it never moves them.
local ART_CHAT_GAP = 24

-- Tab art, in texture pixels (drawn at the console art's scale): the tab's
-- sides at X0 and 128 - X0, its top at TOP and the console's top edge at
-- FOOT. Caps are CAP wide; the middle column stretches.
local TAB_ART = { size = 128, x0 = 32, top = 24, foot = 70, cap = 52 }
local TAB_TEXT_PAD = 26

local function artOn()
	return Console:Art()
end

local function tabRise()
	return (TAB_ART.foot - TAB_ART.top) * Console.ART_SCALE
end

local placing = false

-- The chat keeps clear of any action bar Edit Mode puts over the console,
-- so on a narrow screen it wraps sooner instead of running under the bar.
local CHAT_MIN_WIDTH = 260
local CHAT_BAR_GAP = 12

function Console:ChatWidth()
	local frame = self.frame
	local width = frame and frame:GetWidth()
	if type(width) ~= "number" or (issecretvalue and issecretvalue(width)) or not self.CentreClear then return CHAT_WIDTH end
	local left = self:CentreClear()
	local room = width / 2 - left - self:PageInset() - CHAT_BAR_GAP
	return math.max(CHAT_MIN_WIDTH, math.min(CHAT_WIDTH, math.floor(room)))
end

-- Slim: the chat stands free above the line, on the left, with room under
-- it for the typing box and above it for Blizzard's own tabs.
local SLIM_CHAT_LIFT = 38
local SLIM_CHAT_HEIGHT = 150

local function placeChat()
	local chat = ChatFrame1
	if not chat then return end
	placing = true
	if Console.db.slim or Console.bare then
		chat:ClearAllPoints()
		chat:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", (Console:PageInset()), (Console.bare and 0 or Console:OpenHeight()) + SLIM_CHAT_LIFT)
		chat:SetSize(CHAT_WIDTH, SLIM_CHAT_HEIGHT)
		placing = false
		return
	end
	local bottom = CHAT_BOTTOM
	-- Stoa's typing strip sits under the messages, inside the console.
	local look = Stoa.modules.ChatLook
	if look and look.db and look.db.enabled ~= false and look.db.input then bottom = bottom + 8 end
	local top = artOn() and ART_CHAT_GAP or CHAT_TOP_PAD + CHAT_TAB_HEIGHT
	chat:ClearAllPoints()
	chat:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", (Console:PageInset()), bottom)
	chat:SetSize(Console:ChatWidth(), Console:OpenHeight() - bottom - top)
	-- The ink panel is the background, so the chat window's own goes.
	if FCF_SetWindowAlpha then FCF_SetWindowAlpha(chat, 0) end
	placing = false
end

-- Edit Mode and Blizzard's chat code put the chat back at its saved spot and
-- size from time to time (a layout applied after combat, the dock updating),
-- which left it hanging above the console. Any move Stoa didn't make is
-- undone on the next frame. The chat window isn't protected, so this also
-- works in combat; if a client ever protects it, the move waits.
local queued = false

local function replaceChat()
	queued = false
	local chat = ChatFrame1
	if not chat then return end
	if InCombatLockdown() and chat.IsProtected and chat:IsProtected() then
		Stoa:AfterCombat(function() xpcall(placeChat, Stoa.catch) end)
		return
	end
	xpcall(placeChat, Stoa.catch)
end

function Console:ReplaceChat() replaceChat() end

-- At most a few re-placings a second, in case Blizzard answers each one with
-- another move.
local windowStart, windowCount = 0, 0

local function chatMoved()
	if placing or queued then return end
	local now = GetTime()
	if now - windowStart > 1 then windowStart, windowCount = now, 0 end
	windowCount = windowCount + 1
	if windowCount > 5 then return end
	queued = true
	C_Timer.After(0, replaceChat)
end

local function guardChat()
	local chat = ChatFrame1
	if not chat or chat.stoaGuarded then return end
	chat.stoaGuarded = true
	for _, method in ipairs({ "SetPoint", "SetSize", "SetHeight", "SetWidth", "ApplySystemAnchor" }) do
		if type(chat[method]) == "function" then hooksecurefunc(chat, method, chatMoved) end
	end
	for _, name in ipairs({ "FCF_RestorePositionAndDimensions", "FCF_DockUpdate" }) do
		if _G[name] then hooksecurefunc(name, chatMoved) end
	end
	Stoa:On("PLAYER_REGEN_ENABLED", chatMoved)
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

-- Chat windows with a whisper you haven't seen yet (any window but the
-- main one that shows whispers): their tab gets a gold dot that pulses a
-- few times and stays until you open it.
local unread = {}

local function showsWhispers(chatFrame)
	if chatFrame.ContainsMessageGroup then return chatFrame:ContainsMessageGroup("WHISPER") end
	return ChatFrame_ContainsMessageGroup ~= nil and ChatFrame_ContainsMessageGroup(chatFrame, "WHISPER")
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
	if tab.selected and tab.chatFrame then unread[tab.chatFrame] = nil end
	local waiting = not tab.selected and tab.chatFrame and unread[tab.chatFrame]
	local token = (tab.selected and "accent") or ((waiting or tab:IsMouseOver()) and "text") or "muted"
	tab.label:SetTextColor(Stoa:Color(token))
	if tab.dot then
		tab.dot:SetVertexColor(Stoa:Color("accent"))
		if waiting then
			if not tab.dot:IsShown() then
				tab.dot:Show()
				tab.pulse:Play()
			end
		else
			tab.pulse:Stop()
			tab.dot:Hide()
		end
	end
end

local function makeTab()
	local tab = CreateFrame("Button", nil, strip)
	tab:SetHeight(tabRise())
	tab:RegisterForClicks("LeftButtonUp", "RightButtonUp", "MiddleButtonUp")
	tab.base = capped(tab, 1)
	tab.lines = capped(tab, 2, true)
	local label = tab:CreateFontString(nil, "OVERLAY")
	Stoa:SetFont(label, "sans", Stoa.typeSize.body)
	label:SetShadowOffset(0, 0)
	label:SetPoint("CENTER", 0, -3)
	tab.label = label
	local dot = UI.glyph(tab, "Dot", 10, "accent")
	dot:SetPoint("LEFT", label, "RIGHT", 4, 0)
	dot:Hide()
	tab.dot = dot
	local pulse = dot:CreateAnimationGroup()
	pulse:SetLooping("BOUNCE")
	local fade = pulse:CreateAnimation("Alpha")
	fade:SetFromAlpha(1)
	fade:SetToAlpha(0.25)
	fade:SetDuration(0.5)
	local beats = 0
	pulse:SetScript("OnLoop", function(own)
		beats = beats + 1
		if beats >= 6 then beats = 0 own:Stop() dot:SetAlpha(1) end
	end)
	pulse:SetScript("OnStop", function() beats = 0 dot:SetAlpha(1) end)
	tab.pulse = pulse
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
		-- Blizzard's tab may not be named yet at login; the window's own
		-- name is the same text.
		local text = blizzard and blizzard.GetText and blizzard:GetText()
		local info = FCF_GetChatWindowInfo or GetChatWindowInfo
		if (type(text) ~= "string" or text == "") and info and chatFrame.GetID then
			text = (info(chatFrame:GetID()))
		end
		if type(text) ~= "string" then text = "" end
		tab.label:SetText(text)
		tab.label:Show()
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
	xpcall(refreshTabs, Stoa.catch)
end

-- On a cold start the game can measure a label (the tab takes its width)
-- yet draw nothing, while the font file is still loading. Setting the
-- font and the words again once it has loaded makes them draw.
local function relabel()
	for _, tab in ipairs(tabs) do
		local text = tab.label:GetText()
		Stoa:SetFont(tab.label, "sans", Stoa.typeSize.body)
		tab.label:SetText("")
		tab.label:SetText(text or "")
	end
	safeRefresh()
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

-- Bags and the game menu leave the action bar row for the console's top
-- edge on the right, mirroring the chat tabs on the left: the menu, a gap,
-- then the bags in the corner, a size down and quiet until the mouse is
-- over them. They ride the console's top, so they come down with it when
-- it folds.
local MENU_SCALE = 0.8
local MENU_LIFT = 4
local MENU_GAP = 14
local MENU_REST_ALPHA = 0.55
local BAG_SLOTS = {
	"MainMenuBarBackpackButton", "CharacterBag0Slot", "CharacterBag1Slot",
	"CharacterBag2Slot", "CharacterBag3Slot", "CharacterReagentBag0Slot",
}

local function menuFrames()
	return MicroMenuContainer or MicroMenu, BagsBar
end

local menuPlacing

local function placeMenuNow()
	local menu, bags = menuFrames()
	local inset = Console:PageInset()
	local edge = Console.frame or UIParent
	local point = Console.frame and "TOPRIGHT" or "BOTTOMRIGHT"
	local lift = (Console.frame or Console.bare) and MENU_LIFT or Console:OpenHeight()
	-- Bags take the corner, where every hand already goes for the backpack;
	-- the menu sits inward of them.
	if bags then
		bags:ClearAllPoints()
		bags:SetScale(MENU_SCALE)
		bags:SetPoint("BOTTOMRIGHT", edge, point, -inset / MENU_SCALE, lift / MENU_SCALE)
	end
	if menu then
		menu:ClearAllPoints()
		menu:SetScale(MENU_SCALE)
		if bags then
			menu:SetPoint("BOTTOMRIGHT", bags, "BOTTOMLEFT", -MENU_GAP, 0)
		else
			menu:SetPoint("BOTTOMRIGHT", edge, point, -inset / MENU_SCALE, lift / MENU_SCALE)
		end
	end
	local bars = Stoa.modules.ActionBars
	if bars and bars.db and bars.db.enabled then
		for _, name in ipairs(BAG_SLOTS) do
			local slot = _G[name]
			if slot then
				xpcall(bars.Skin, Stoa.catch, bars, slot)
				if slot.IconBorder then slot.IconBorder:SetAlpha(0) end
			end
		end
	end
end

-- The quiet tray: Blizzard's icons stay, their frames go. The rows' border
-- and background art are hidden, each micro button loses its stone
-- backing, and the glyphs rest in bone with the accent under the mouse.
-- Bag slots match them: no frame, no socket, the bag drawn in bone. The console's own brass
-- edge runs under the rows, so they need no line of their own. Textures
-- and colours only, so it is safe on these buttons at load.
local MICRO_PARTS = { "Background", "PushedBackground" }
local ROW_ART = { "BorderArt", "BackgroundArt", "Background" }
local MICRO_BUTTONS = {
	"CharacterMicroButton", "ProfessionMicroButton", "SpellbookMicroButton", "TalentMicroButton",
	"PlayerSpellsMicroButton", "LegacyMicroButton", "AchievementMicroButton", "QuestLogMicroButton",
	"HousingMicroButton", "GuildMicroButton", "LFDMicroButton", "CollectionsMicroButton",
	"EJMicroButton", "HelpMicroButton", "StoreMicroButton", "MainMenuMicroButton",
}

local function tintMicro(button)
	local text = { Stoa:Color("text") }
	local accent = { Stoa:Color("accent") }
	local muted = { Stoa:Color("muted") }
	local function set(getter, colour, alpha, desaturate)
		local tex = button[getter] and button[getter](button)
		if not tex then return end
		pcall(tex.SetDesaturated, tex, desaturate)
		tex:SetVertexColor(colour[1], colour[2], colour[3], alpha or 1)
	end
	set("GetNormalTexture", text, 0.9, true)
	set("GetPushedTexture", accent, 1, true)
	set("GetDisabledTexture", muted, 0.5, true)
	set("GetHighlightTexture", accent, 0.9, true)
	-- Blizzard's own hover is a lit copy of the glyph (FlashContent).
	if button.FlashContent then pcall(button.FlashContent.SetVertexColor, button.FlashContent, accent[1], accent[2], accent[3]) end
end

local function dressMicro(button)
	if not (button and button.GetObjectType) then return end
	for _, key in ipairs(MICRO_PARTS) do
		local art = button[key]
		if art and art.SetAlpha then art:SetAlpha(0) end
	end
	tintMicro(button)
end

-- A bag slot matched to the menu glyphs: no frame and no socket, the bag
-- itself drawn in the same bone tone, a little inside its slot. Kept that
-- way through Blizzard's redraws.
local function quietBagSlot(slot)
	local function hide()
		for _, getter in ipairs({ "GetNormalTexture", "GetPushedTexture" }) do
			local tex = slot[getter] and slot[getter](slot)
			if tex then tex:SetAlpha(0) end
		end
		if slot.IconBorder then slot.IconBorder:SetAlpha(0) end
		if slot.SlotHighlightTexture then slot.SlotHighlightTexture:SetAlpha(0) end
		if slot.stoaPanelBg then slot.stoaPanelBg:SetAlpha(0) end
		if slot.stoaPanelEdge and slot.stoaPanelEdge.edges then
			for _, tex in ipairs(slot.stoaPanelEdge.edges) do tex:SetAlpha(0) end
		end
		local icon = slot.icon or slot.Icon
		if icon then
			pcall(icon.SetDesaturated, icon, true)
			local r, g, b = Stoa:Color("text")
			icon:SetVertexColor(r, g, b, 1)
			icon:ClearAllPoints()
			icon:SetPoint("TOPLEFT", 4, -4)
			icon:SetPoint("BOTTOMRIGHT", -4, 4)
		end
		local highlight = slot.GetHighlightTexture and slot:GetHighlightTexture()
		if highlight then
			local r, g, b = Stoa:Color("accent")
			highlight:SetVertexColor(r, g, b)
		end
	end
	hide()
	if not slot.stoaQuiet then
		slot.stoaQuiet = true
		if slot.UpdateTextures then Stoa.SafeHook(slot, "UpdateTextures", hide) end
		if slot.SetBarExpanded then Stoa.SafeHook(slot, "SetBarExpanded", hide) end
	end
end

local microHooked

local function dressMenu()
	local menu, bags = menuFrames()
	for _, row in ipairs({ menu, bags, MicroMenu, MicroMenuContainer, MicroButtonAndBagsBar }) do
		if row then
			for _, key in ipairs(ROW_ART) do
				local art = row[key]
				if art and art.SetAlpha then art:SetAlpha(0) end
			end
		end
	end
	-- The buttons by name, then anything else the menu holds.
	local seen = {}
	for _, name in ipairs(MICRO_BUTTONS) do
		local button = _G[name]
		if button then
			seen[button] = true
			xpcall(dressMicro, Stoa.catch, button)
		end
	end
	for _, holder in ipairs({ MicroMenu, menu }) do
		if holder and holder.GetChildren then
			for _, child in ipairs({ holder:GetChildren() }) do
				if not seen[child] and child.GetNormalTexture and child.Background then
					seen[child] = true
					xpcall(dressMicro, Stoa.catch, child)
				end
			end
		end
	end
	-- Blizzard reloads the glyph art on some events (guild colour, pushed
	-- state); the tint goes back on after it.
	if not microHooked and LoadMicroButtonTextures then
		microHooked = true
		Stoa.SafeHook("LoadMicroButtonTextures", function(button) xpcall(tintMicro, Stoa.catch, button) end)
	end
	for _, name in ipairs(BAG_SLOTS) do
		local slot = _G[name]
		if slot then xpcall(quietBagSlot, Stoa.catch, slot) end
	end
	-- Blizzard draws a divider between neighbouring bag slots; the quiet
	-- row has none, now and after every relayout.
	if bags and bags.UpdateDividers then
		bags.useDividers = false
		local function clear()
			for _, key in ipairs({ "HorizontalDividersPool", "VerticalDividersPool" }) do
				local pool = bags[key]
				if pool and pool.ReleaseAll then pool:ReleaseAll() end
			end
		end
		clear()
		if not bags.stoaNoDividers then
			bags.stoaNoDividers = true
			Stoa.SafeHook(bags, "UpdateDividers", clear)
		end
	end
	if KeyRingButton then xpcall(quietBagSlot, Stoa.catch, KeyRingButton) end
end

-- Stoa's own moves are marked so the watch below lets them through.
local function placeMenu()
	menuPlacing = true
	local ok, err = pcall(placeMenuNow)
	menuPlacing = false
	if not ok then error(err, 0) end
end

-- Blizzard puts the menu and bags back now and then: Edit Mode re-applies
-- their anchors (layout updates, the action bar showing again after a
-- vehicle or a cinematic), and the bottom frame manager re-stacks them.
-- Any move or rescale Stoa didn't make sends them back next frame, at most
-- a few times a second in case Blizzard answers each move with its own.
local pendingPlace
local placeWindow, placeCount = 0, 0

local function keepMenu()
	local function again()
		if menuPlacing or pendingPlace then return end
		local now = GetTime()
		if now - placeWindow > 1 then placeWindow, placeCount = now, 0 end
		if placeCount >= 3 then return end
		placeCount = placeCount + 1
		pendingPlace = true
		C_Timer.After(0, function()
			pendingPlace = false
			Stoa:AfterCombat(function() xpcall(placeMenu, Stoa.catch) end)
		end)
	end
	local menu, bags = menuFrames()
	for _, frame in ipairs({ menu, bags }) do
		if frame and not frame.stoaKeptPlace then
			frame.stoaKeptPlace = true
			hooksecurefunc(frame, "SetPoint", again)
			hooksecurefunc(frame, "SetScale", again)
		end
	end
	if MicroMenu and MicroMenu.ResetMicroMenuPosition then
		hooksecurefunc(MicroMenu, "ResetMicroMenuPosition", again)
	end
end

-- Bags open above the console rather than over it. Blizzard stacks bag
-- windows up from the screen's bottom-right corner; the ones it pins to the
-- screen are lifted clear of the console, and the rest follow them.
local BAG_LIFT_GAP = 16

local function liftBags()
	local floor = Console:OpenHeight() + BAG_LIFT_GAP
	-- Clear of the bags and menu row on the console's top edge, too.
	local menu, bagsBar = menuFrames()
	local row = bagsBar or menu
	if Console.db.houseMenu and row and row:IsShown() then
		local height = Stoa:PlainNumber(row:GetHeight())
		if height then floor = floor + MENU_LIFT + height * MENU_SCALE end
	end
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
	if not (menu or bags) then return end
	local lit
	local function update()
		local over = (menu and menu:IsVisible() and menu:IsMouseOver())
			or (bags and bags:IsVisible() and bags:IsMouseOver())
		if over == lit then return end
		lit = over
		local alpha = over and 1 or MENU_REST_ALPHA
		if menu then menu:SetAlpha(alpha) end
		if bags then bags:SetAlpha(alpha) end
	end
	update()
	Stoa:NewTicker(0.15, update)
end

-- Runs fn now, or after combat if it can't run yet. Each step is guarded so a
-- renamed Blizzard frame costs one feature, not the console.
local function safely(fn)
	Stoa:AfterCombat(function()
		xpcall(fn, Stoa.catch)
	end)
end

-- With the console switched off (the Minimal preset) there is no frame to
-- house things in, but Blizzard's bar art, menu, bags and chat still need
-- the same care: the gryphons and stone go, the menu and bags rest in the
-- bottom right corner, and the chat stands in the bottom left.
function Console:OnOff()
	self.bare = true
	local db = self.db
	local function apply()
		if db.houseChat then
			safely(placeChat)
			safely(guardChat)
		end
		if db.hideBarArt then safely(hideBarArt) end
		if db.houseMenu then
			safely(placeMenu)
			safely(dressMenu)
		end
	end
	apply()
	if db.houseMenu then
		watchMenu()
		safely(keepMenu)
		Stoa:On("STOA_THEME_CHANGED", function() safely(dressMenu) end)
	end
	Stoa:On("PLAYER_ENTERING_WORLD", apply)
	Stoa:On("UI_SCALE_CHANGED", apply)
	Stoa:On("EDIT_MODE_LAYOUTS_UPDATED", apply)
	if EventRegistry then EventRegistry:RegisterCallback("EditMode.Exit", apply, self) end
	local bar = actionBar()
	if bar and bar.UpdateEndCaps then
		hooksecurefunc(bar, "UpdateEndCaps", function()
			if db.hideBarArt then safely(hideBarArt) end
		end)
	end
end

function Console:House()
	local db = self.db

	local function apply()
		if db.houseChat then
			safely(placeChat)
			safely(guardChat)
			if artOn() then safely(buildTabs) end
		end
		if db.hideBarArt then safely(hideBarArt) end
		if db.houseMenu then
			safely(placeMenu)
			safely(dressMenu)
		end
	end

	if db.houseChat or db.slim then
		-- Notes now arrive in chat, so the notes page steps aside (the slim
		-- line has no room for it either way).
		self.leftPage:Hide()
		Stoa.notesInConsole = false
	end

	apply()
	if db.houseMenu then
		watchMenu()
		safely(keepMenu)
		if UpdateContainerFrameAnchors then
			hooksecurefunc("UpdateContainerFrameAnchors", function()
				if not InCombatLockdown() then xpcall(liftBags, Stoa.catch) end
			end)
		end
	end
	Stoa:On("PLAYER_ENTERING_WORLD", apply)
	Stoa:On("UI_SCALE_CHANGED", apply)
	if db.houseMenu then Stoa:On("STOA_THEME_CHANGED", function() safely(dressMenu) end) end
	Stoa:On("EDIT_MODE_LAYOUTS_UPDATED", apply)
	if EventRegistry then
		EventRegistry:RegisterCallback("EditMode.Exit", apply, self)
	end

	if db.houseChat and artOn() then
		-- Read-only hooks: Stoa's tabs follow the dock, nothing is changed.
		for _, name in ipairs({ "FCFDock_UpdateTabs", "FCFDock_SelectWindow", "FCF_SetWindowName", "FCF_OpenNewWindow", "FCF_Close", "FCF_DockFrame", "FCF_UnDockFrame" }) do
			if _G[name] then hooksecurefunc(name, safeRefresh) end
		end
		Stoa:On("STOA_THEME_CHANGED", safeRefresh)
		-- A whisper in a window you aren't looking at marks its tab.
		local function whispered()
			local selected = FCFDock_GetSelectedWindow and FCFDock_GetSelectedWindow(GENERAL_CHAT_DOCK)
			local marked = false
			for _, chatFrame in ipairs(dockedWindows()) do
				if chatFrame ~= selected and chatFrame ~= _G.ChatFrame1 and showsWhispers(chatFrame) then
					unread[chatFrame] = true
					marked = true
				end
			end
			if marked then safeRefresh() end
		end
		Stoa:On("CHAT_MSG_WHISPER", function() xpcall(whispered, Stoa.catch) end)
		Stoa:On("CHAT_MSG_BN_WHISPER", function() xpcall(whispered, Stoa.catch) end)
		Stoa:On("UPDATE_CHAT_WINDOWS", safeRefresh)
		Stoa:On("UPDATE_FLOATING_CHAT_WINDOWS", safeRefresh)
		-- Names can arrive a moment after login.
		Stoa:On("PLAYER_ENTERING_WORLD", function()
			C_Timer.After(1, safeRefresh)
			for _, delay in ipairs({ 2, 5 }) do
				C_Timer.After(delay, function() xpcall(relabel, Stoa.catch) end)
			end
		end)
		for i = 1, (NUM_CHAT_WINDOWS or 10) do
			local blizzard = _G["ChatFrame" .. i .. "Tab"]
			if blizzard and blizzard.SetText then hooksecurefunc(blizzard, "SetText", safeRefresh) end
		end
	end
	local bar = actionBar()
	if bar and bar.UpdateEndCaps then
		hooksecurefunc(bar, "UpdateEndCaps", function()
			if db.hideBarArt then safely(hideBarArt) end
		end)
	end
end
