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

-- The tabs stand on the console's top edge with the leather art and on
-- the matte console (its own tab art, Tools/art/matte_tabs.py).
local function artOn()
	return Console:Art() or (Console:Matte() and not Console.db.slim)
end

-- Slate: the tabs are small chips standing just over the chat card, as
-- Leather's stand on its rim, so the card is all messages. The picked one
-- is in the accent (Blizzard's own row stays, working, unseen).
local function pillsOn()
	return Console:Slate() and not Console.db.slim
end
local PILL_H, PILL_PAD, PILL_GAP, PILL_LIFT = 22, 11, 4, 4
-- With the chips out of the card, the messages start just under its top.
local SLATE_CHAT_TOP = 18

local function tabFile(kind)
	return UI.MEDIA .. "Textures\\ChatTab" .. (Console:Matte() and "Matte" or "") .. kind
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
-- The ride card: its air over the travel line, and the room it keeps
-- under the messages for the typing strip (the strip and the card's pad).
local SLATE_RIDE_AIR, SLATE_RIDE_INPUT = 8, 28
local CHAT_GROUND = {
	"Background", "TopLeftTexture", "BottomLeftTexture", "TopRightTexture", "BottomRightTexture",
	"LeftTexture", "RightTexture", "BottomTexture", "TopTexture",
}

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
	-- Stepped aside for Prat, STOA's strip isn't there to make room for.
	if Stoa.Conflicts and Stoa.Conflicts:SteppedAside("ChatLook") then look = nil end
	if look and look.db and look.db.enabled ~= false and look.db.input then bottom = bottom + 8 end
	-- On a ride the console is the travel line: the chat's foot stands
	-- clear of it, and its top stays where it was.
	if Console.riding and Console.RIDE_HEIGHT then
		-- The chat rides in a card of its own (Console:ChatShade), in
		-- every style, which holds the typing strip too and stands clear
		-- of the line.
		local typing = look and look.db and look.db.enabled ~= false and look.db.input
		bottom = Console.RIDE_HEIGHT + SLATE_RIDE_AIR + (typing and SLATE_RIDE_INPUT or 6)
	end
	local top = (pillsOn() and SLATE_CHAT_TOP) or (artOn() and ART_CHAT_GAP) or CHAT_TOP_PAD + CHAT_TAB_HEIGHT
	chat:ClearAllPoints()
	chat:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", (Console:PageInset()), bottom)
	chat:SetSize(Console:ChatWidth(), Console:OpenHeight() - bottom - top)
	-- The ink panel is the background, so the chat window's own goes.
	if FCF_SetWindowAlpha then FCF_SetWindowAlpha(chat, 0) end
	-- Blizzard fades that background (a flat black block) back in under
	-- the mouse, but only the parts that are shown. Slate's cards are the
	-- ground, so the block and its border are hidden outright.
	if pillsOn() then
		for _, part in ipairs(CHAT_GROUND) do
			local tex = _G["ChatFrame1" .. part]
			if tex and tex.Hide then tex:Hide() end
		end
	end
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
	if Console.HousesChat and not Console:HousesChat() then return end
	if InCombatLockdown() and chat.IsProtected and chat:IsProtected() then
		Stoa:AfterCombat(function() xpcall(placeChat, Stoa.catch) end)
		return
	end
	xpcall(placeChat, Stoa.catch)
end

-- Only a chat Stoa houses is Stoa's to place: one another addon keeps
-- (or one the player left out of the console) is never sized or moved here.
function Console:ReplaceChat()
	if self.HousesChat and self:HousesChat() then replaceChat() end
end

-- At most a few re-placings a second, in case Blizzard answers each one with
-- another move.
local windowStart, windowCount = 0, 0

local function chatMoved()
	if placing or queued then return end
	local now = GetTime()
	if now - windowStart > 1 then windowStart, windowCount = now, 0 end
	windowCount = windowCount + 1
	queued = true
	-- Past the limit the move still gets its answer, a second later: dropped
	-- outright, the chat stayed at Blizzard's size until a reload.
	C_Timer.After(windowCount > 5 and 1 or 0, replaceChat)
end

-- For /stoa report: where the chat stands against where Stoa puts it.
function Console:ChatState()
	local chat = ChatFrame1
	if not chat then return "no chat window" end
	if not (self.HousesChat and self:HousesChat()) then return "not housed by the console" end
	local function n(value)
		if type(value) ~= "number" or (issecretvalue and issecretvalue(value)) then return "?" end
		return tostring(math.floor(value + 0.5))
	end
	local text = "chat " .. n(chat:GetWidth()) .. "x" .. n(chat:GetHeight()) .. " at " .. n(chat:GetLeft()) .. "," .. n(chat:GetBottom())
		.. ", console " .. n(self.frame and self.frame:GetHeight()) .. " of " .. n(self:OpenHeight())
	local rail = _G.StoaChatRail
	if rail then
		text = text .. ", rail top " .. n(rail:GetTop()) .. " (chat top " .. n(chat:GetTop()) .. ")"
		for _, name in ipairs({ "QuickJoinToastButton", "ChatFrameChannelButton", "ChatFrameMenuButton" }) do
			local button = _G[name]
			if button and button.GetTop then
				local parent = button:GetParent()
				text = text .. ", " .. name .. " top " .. n(button:GetTop()) .. (parent == rail and "" or " (not on the rail)")
			end
		end
	end
	return text
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

local function paintPill(tab)
	local hover = tab:IsMouseOver()
	if tab.selected and tab.chatFrame then unread[tab.chatFrame] = nil end
	local waiting = not tab.selected and tab.chatFrame and unread[tab.chatFrame]
	-- Each chip is the panel's own dark, so its word reads over the world;
	-- the picked one takes a breath of the accent and an accent line.
	local r, g, b = Stoa:Color(tab.selected and "accent" or "text")
	local pr, pg, pb = Stoa:Color("panel")
	local mix = tab.selected and 0.16 or (hover and 0.07 or 0)
	tab.fill:SetVertexColor(pr + (r - pr) * mix, pg + (g - pg) * mix, pb + (b - pb) * mix, 0.94)
	tab.edge:Set(r, g, b, tab.selected and 0.45 or (hover and 0.14 or 0))
	tab.label:SetTextColor(Stoa:Color((tab.selected or hover or waiting) and "text" or "muted"))
	tab:SetFrameLevel(strip:GetFrameLevel() + 1)
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

local function paintTab(tab)
	if tab.pill then return paintPill(tab) end
	-- Matte: a key under a click goes down like the selected one.
	local kind = (tab.selected or tab.down) and "Open" or "Closed"
	if tab.kind ~= kind then
		tab.kind = kind
		for _, tex in ipairs(tab.base) do tex:SetTexture(tabFile(kind)) end
		for _, tex in ipairs(tab.lines) do tex:SetTexture(tabFile(kind .. "Lines")) end
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
	tab:RegisterForClicks("LeftButtonUp", "RightButtonUp", "MiddleButtonUp")
	local pill = pillsOn()
	if pill then
		tab.pill = true
		tab:SetHeight(PILL_H)
		tab.fill = UI.pillFill(tab, 0)
		tab.edge = UI.pillEdge(tab, 0)
	else
		tab:SetHeight(tabRise())
		tab.base = capped(tab, 1)
		tab.lines = capped(tab, 2, true)
	end
	local label = tab:CreateFontString(nil, "OVERLAY")
	Stoa:SetFont(label, "sans", pill and Stoa.typeSize.caption or Stoa.typeSize.body)
	label:SetShadowOffset(0, 0)
	label:SetPoint("CENTER", 0, pill and 0 or -3)
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
	if Console:Matte() then
		tab:SetScript("OnMouseDown", function(self) self.down = true paintTab(self) end)
		tab:SetScript("OnMouseUp", function(self) self.down = nil paintTab(self) end)
	end
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
		tab:SetWidth(width + (tab.pill and PILL_PAD or TAB_TEXT_PAD) * 2)
		tab:ClearAllPoints()
		tab:SetPoint("BOTTOMLEFT", strip, "BOTTOMLEFT", x, 0)
		-- The matte keys stand in one bank, side against side.
		x = x + tab:GetWidth() + (Console:Matte() and 0 or tab.pill and PILL_GAP or TAB_GAP)
		tab.selected = chatFrame == selected
		paintTab(tab)
		tab:Show()
	end
	for i = #windows + 1, #tabs do tabs[i]:Hide() end
end

-- The combat log's own row of quick filters ("What happened to me?" and
-- the rest) hangs from Blizzard's tab, which is unseen, so the row went
-- unseen with it while the log still left room for it. It shows again,
-- without its black bar.
local function showLogLinks()
	local bar = rawget(_G, "CombatLogQuickButtonFrame_Custom")
	if type(bar) ~= "table" or bar.stoaShown or (bar.IsForbidden and bar:IsForbidden()) then return end
	if not bar.SetIgnoreParentAlpha then return end
	bar.stoaShown = true
	bar:SetIgnoreParentAlpha(true)
	local ground = rawget(_G, "CombatLogQuickButtonFrame_CustomTexture")
	if type(ground) == "table" and ground.SetAlpha then ground:SetAlpha(0) end
end

local function buildTabs()
	showLogLinks()
	if strip then return end
	strip = CreateFrame("Frame", "StoaChatTabs", UIParent)
	-- Above the chat frames, so these take the clicks rather than
	-- Blizzard's invisible tabs underneath.
	strip:SetFrameStrata("MEDIUM")
	if pillsOn() then
		-- Standing just over the chat card's top edge.
		strip:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", (Console:PageInset()), Console:OpenHeight() + (Console.SLATE_TOP or 0) + PILL_LIFT)
		strip:SetSize(CHAT_WIDTH, PILL_H)
	else
		strip:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", (Console:PageInset()), Console:OpenHeight())
		strip:SetSize(CHAT_WIDTH, tabRise())
	end
	Console.tabArt = Console.tabArt or {}
	table.insert(Console.tabArt, strip)
	-- Blizzard's tab row stays where it is, working, just unseen.
	if GeneralDockManager then GeneralDockManager:SetAlpha(0) end
	refreshTabs()
end

local function safeRefresh()
	xpcall(refreshTabs, Stoa.catch)
	if strip then xpcall(showLogLinks, Stoa.catch) end
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
	-- The gold dividers the game draws between the main bar's buttons when
	-- they stand close together (a layout with Hide Bar Art unticked and
	-- the least padding, as STOA's own is).
	for _, key in ipairs({ "HorizontalDividersPool", "VerticalDividersPool" }) do
		local pool = bar[key]
		if pool and pool.EnumerateActive then
			for divider in pool:EnumerateActive() do divider:Hide() end
		end
	end
end

-- Bags and the game menu leave the action bar row for the console's top
-- edge on the right, mirroring the chat tabs on the left: the menu, a gap,
-- then the bags in the corner, a size down. At rest each row is hidden
-- behind a word on the rim, MENU and BAGS, and opens in the word's place
-- while the mouse is over the word or the row. They ride the console's top, so they come down
-- with it when it folds.
local MENU_SCALE = 0.8
local MENU_LIFT = 4
local MENU_GAP = 14
local MENU_WORD_ROOM = 16
local MENU_WORD_REST, MENU_WORD_FIGHT = 0.6, 0.3
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
	-- With a window docked on the right (Console:PlaceDocks), the rows hold
	-- the open console's height on the screen instead of riding its top
	-- down in a fight, where they would land on that window.
	if Console.frame and Console.docked then
		edge, point, lift = UIParent, "BOTTOMRIGHT", Console:OpenHeight() + MENU_LIFT
	end
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

-- For the console's slots: places the rows again, out of a fight.
function Console:ReplaceMenu()
	if not self.db.houseMenu then return end
	Stoa:AfterCombat(function() xpcall(placeMenu, Stoa.catch) end)
end

-- Blizzard puts the menu and bags back now and then: Edit Mode re-applies
-- their anchors (layout updates, the action bar showing again after a
-- vehicle or a cinematic), and the bottom frame manager re-stacks them.
-- Any move or rescale Stoa didn't make sends them back next frame, at most
-- a few times a second in case Blizzard answers each move with its own.
local pendingPlace
local placeWindow, placeCount = 0, 0

-- Whether the rows can be moved right now: always out of a fight, and in
-- one only while the game doesn't guard them.
local function menuFree()
	if not InCombatLockdown() then return true end
	local menu, bags = menuFrames()
	for _, frame in ipairs({ menu, bags }) do
		if frame and frame.IsProtected and frame:IsProtected() then return false end
	end
	return true
end

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
			-- In a fight the rows go straight back when the game allows it
			-- (it moves them on a level-up, say), and after it otherwise.
			if menuFree() then
				xpcall(placeMenu, Stoa.catch)
			else
				Stoa:AfterCombat(function() xpcall(placeMenu, Stoa.catch) end)
			end
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

-- Each row rests unseen behind its word and opens in the word's place
-- while the mouse is over the word or the row, so the hand only moves
-- across to its button; the word steps out while the row is up. The words
-- are Stoa's own frames laid on the game's rows' near corners, so they
-- follow wherever the rows are put. BAGS opens the bags on a click, as the
-- backpack does; MENU takes no clicks, so the button under it has them.
-- Slate: each word is a small chip of its own (the panel colour, rounded),
-- so it doesn't float loose over the world above the cards.
local CHIP_PAD, CHIP_H = 9, 18
local function menuWord(row, label, click)
	local word = CreateFrame("Button", nil, UIParent)
	local text = UI.caption(word, label)
	word.text = text
	if Console:Slate() then
		text:SetPoint("CENTER")
		local fill = UI.pillFill(word, 0)
		UI.tint(fill, "panel", 0.94)
		fill:SetVertexColor(Stoa:Color("panel"))
		word:SetSize(math.max(text:GetStringWidth() or 0, 24) + CHIP_PAD * 2, CHIP_H)
	else
		text:SetPoint("RIGHT")
		word:SetSize(math.max(text:GetStringWidth() or 0, 24) + 4, MENU_WORD_ROOM - 4)
	end
	if Console:Slate() and not Console.db.slim then
		-- Standing just over the cards' top edge, level with the chat's
		-- tab chips, rather than floating at the row's middle.
		word:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", 0, (Console.SLATE_TOP or 0) + PILL_LIFT - MENU_LIFT)
	else
		word:SetPoint("RIGHT", row, "RIGHT", 0, 0)
	end
	word:EnableMouse(click ~= nil)
	if click then word:SetScript("OnClick", click) end
	return word
end

local function watchMenu()
	local menu, bags = menuFrames()
	if not (menu or bags) then return end
	local rows = {}
	if menu then rows[#rows + 1] = { row = menu, word = menuWord(menu, "Menu") } end
	if bags then
		rows[#rows + 1] = { row = bags, word = menuWord(bags, "Bags", function()
			if ToggleAllBags then ToggleAllBags() end
		end) }
	end
	local function update()
		local fight = InCombatLockdown()
		for _, entry in ipairs(rows) do
			local row, word = entry.row, entry.word
			local seen = row:IsVisible()
			word:SetShown(seen)
			local over = seen and (row:IsMouseOver() or word:IsMouseOver())
			local state = over and 1 or (fight and 2 or 3)
			if state ~= entry.state then
				entry.state = state
				row:SetAlpha(over and 1 or 0)
				word.text:SetTextColor(Stoa:Color(over and "accent" or "muted"))
				-- (A Slate chip keeps its panel solid; its word is muted.)
				local rest = Console:Slate() and 1 or MENU_WORD_REST
				word:SetAlpha(over and 0 or (fight and MENU_WORD_FIGHT or rest))
			end
		end
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

-- Chat is housed unless a chat addon that draws its own frame and tabs
-- was kept for the job (Core/Conflicts.lua). Prat and Chatter change the
-- game's own window, so that window sits on the console all the same.
local function housesChat(db)
	local conflicts = Stoa.Conflicts
	return db.houseChat and not (conflicts and conflicts:SteppedAside("ChatLook") and conflicts:OwnWindow("chat"))
end
Console.HousesChat = function(self) return housesChat(self.db) end

-- Another chat addon was kept: the chat is theirs to dress, but Stoa's Edit
-- Mode layout rests it inside the console, where it would lie across the
-- pages. While it overlaps the console it is stood just above the edge;
-- anywhere else it is left alone.
local function liftChat()
	local chat = ChatFrame1
	if not chat or Console.bare then return end
	local bottom, top = chat:GetBottom(), Console:OpenHeight()
	if type(bottom) ~= "number" or (issecretvalue and issecretvalue(bottom)) or bottom >= top then return end
	if InCombatLockdown() and chat.IsProtected and chat:IsProtected() then return end
	chat:ClearAllPoints()
	chat:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", (Console:PageInset()), top + SLIM_CHAT_LIFT)
end

-- Daylight UI keeps "room along the bottom edge": its own data bar reports a
-- height and every piece the player hasn't placed by hand (chat, meters,
-- bars) starts above it. Stoa reports the console's height the same way, so
-- Daylight's pieces stand on the console instead of under it. Its frames are
-- never moved from here. True while Daylight is there to take the report.
local roomWatched = false

local function daylightRoom()
	local dui = _G.DaylightUI
	local movers = type(dui) == "table" and dui.Movers
	if not (type(movers) == "table" and type(movers.SetBottomRoom) == "function") then return false end
	if Console.bare then return true end
	local want = Console:OpenHeight()
	local function report()
		if InCombatLockdown() then return end
		local now = type(movers.BottomRoom) == "function" and movers.BottomRoom() or 0
		if type(now) == "number" and now < want then pcall(movers.SetBottomRoom, want) end
	end
	report()
	if not roomWatched and type(dui.On) == "function" then
		roomWatched = true
		-- Daylight's data bar reports its own height (or none) now and then.
		pcall(dui.On, "BottomRoomChanged", function(px)
			if type(px) == "number" and px < want then C_Timer.After(0, function() safely(report) end) end
		end)
	end
	return true
end

-- Daylight UI's chat kept, and the chat wanted in the console: its panel is
-- docked on the console's left page, where Stoa's own chat would stand.
-- Daylight's mover for it is suspended (its saved spot stays, and comes back
-- when the two part), and its size is overridden through
-- Daylight's plugin API, which never saves them. Daylight's code is only
-- called, never copied; if any call is missing the chat just stands above
-- the console.
local DOCK_PAD = 18 -- Daylight's panel is this much larger than its chat size
-- Daylight pads its panel itself, so it runs nearly edge to edge.
local DOCK_BOTTOM, DOCK_TOP, DOCK_SIDE = 6, 8, 8
local DOCK_TABS = 50 -- Daylight's tab row and the padding over it, clear of the border
local dockView, dockSized = nil, false

local function wantsDock(db)
	return db.houseChat and not db.slim and not Console.bare
		and Stoa.Conflicts and Stoa.Conflicts:SteppedAside("ChatLook")
		and C_AddOns and C_AddOns.IsAddOnLoaded and C_AddOns.IsAddOnLoaded("DaylightUI_Chat") or false
end
local ellDockedNow -- EllesmereUI's chat fitted on the page (set below)
Console.DocksChat = function(self) return wantsDock(self.db) or (ellDockedNow and ellDockedNow(self.db)) or false end

local function dockChat()
	if not wantsDock(Console.db) then return false end
	local dui = _G.DaylightUI
	local api = type(dui) == "table" and dui.API
	local movers = type(dui) == "table" and dui.Movers
	if not (type(api) == "table" and type(api.For) == "function" and type(movers) == "table"
		and type(movers.Suspend) == "function" and type(movers.Get) == "function") then return false end
	local entry = movers.Get("chat")
	local holder = type(entry) == "table" and entry.frame
	if not (type(holder) == "table" and holder.SetPoint and holder.GetScale) then return false end
	if InCombatLockdown() then return true end
	local scale = holder:GetScale()
	if type(scale) ~= "number" or scale <= 0 then scale = 1 end
	if not dockSized then
		dockSized = true
		dockView = dockView or api.For("STOA")
		if type(dockView) == "table" and type(dockView.Override) == "function" then
			local width = math.floor((Console:ChatWidth() + 2 * DOCK_SIDE) / scale) - DOCK_PAD
			-- With the art the gold border sits a little under the console's top.
			-- Daylight's tab row stands above that border, as Stoa's own tabs
			-- do, so the lines get the page's whole height.
			local top = (artOn() and ART_CHAT_GAP + 2 or DOCK_TOP) - DOCK_TABS
			local height = math.floor((Console:OpenHeight() - DOCK_BOTTOM - top) / scale) - DOCK_PAD
			pcall(dockView.Override, "Chat", "matchInfo", false)
			pcall(dockView.Override, "Chat", "width", width)
			pcall(dockView.Override, "Chat", "height", height)
			-- The panel keeps Daylight's own background: it fades in on
			-- hover and backs the tab row where that stands over the world.
		end
	end
	if not pcall(movers.Suspend, "chat", true) then return false end
	holder:ClearAllPoints()
	holder:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", (Console:PageInset() - DOCK_SIDE) / scale, DOCK_BOTTOM / scale)
	return true
end

-- EllesmereUI keeps its chat and its damage meter where its own saved
-- settings say and puts them back if another addon moves them, and it has no
-- way for an addon to ask for a place. Its chat's size is Edit Mode's and
-- the player's own: Stoa leaves it, and the player drags it narrower if it
-- covers At a glance. So Stoa fits them only when the
-- player asks (/stoa fit, or the button in Settings): it writes the two
-- positions into EllesmereUI's saved settings, keeps what was there before
-- in Stoa.db.ellesmereFit, and reloads so EllesmereUI places them itself.
-- /stoa fit undo puts the old ones back. Only its saved values are touched,
-- never its frames or code; if they move in a later EllesmereUI the fit
-- simply does nothing.
local ELL_SIDE = 34 -- EllesmereUI's icon column left of the chat lines
local ELL_EDIT = 42 -- its edit box under them
local ELL_METER = { point = "TOPLEFT", relPoint = "TOPLEFT", x = 0, y = 0 } -- where Stoa keeps its own

local function ellProfile(folder)
	local db = _G.EllesmereUIDB
	if type(db) ~= "table" or type(db.profiles) ~= "table" then return nil end
	local profile = db.profiles[db.activeProfile or "Default"]
	local addons = type(profile) == "table" and profile.addons
	local own = type(addons) == "table" and addons[folder]
	return type(own) == "table" and own or nil
end

-- The chat's settings sit one table down, under chat. `tidy` also drops the
-- two keys Stoa 1.5.2's test builds wrote a level too high, where
-- EllesmereUI never read them.
local function ellChat(tidy)
	local own = ellProfile("EllesmereUIChat")
	if not own then return nil end
	if tidy then own.chatPosition, own.chatSize = nil, nil end
	return type(own.chat) == "table" and own.chat or nil
end

-- The damage meter's first window: its settings sit one table down, under dm.
local function ellMeterWindow(meters)
	local dm = meters and type(meters.dm) == "table" and meters.dm
	local windows = dm and type(dm.windows) == "table" and dm.windows
	local window = windows and windows[1]
	return type(window) == "table" and window or nil
end

local function shallow(t)
	if type(t) ~= "table" then return false end
	local c = {}
	for k, v in pairs(t) do c[k] = v end
	return c
end

local function addonOn(name)
	return C_AddOns and C_AddOns.IsAddOnLoaded and C_AddOns.IsAddOnLoaded(name) or false
end

-- Where EllesmereUI's chat lines go on the console's left page: its tab row
-- stands on the console's top edge, as Stoa's own tabs do.
local function ellChatSpot()
	local chat = ChatFrame1
	local scale = chat and chat:GetScale() or 1
	if type(scale) ~= "number" or scale <= 0 then scale = 1 end
	local function r(v) return math.floor(v / scale + 0.5) end
	return r(Console:PageInset() + ELL_SIDE), r(DOCK_BOTTOM + ELL_EDIT)
end

-- True while EllesmereUI's saved chat spot is the one Stoa wrote.
local function ellDocked(db)
	local fit = Stoa.db.ellesmereFit
	if not (fit and fit.chatAt) or db.slim or Console.bare or not db.houseChat then return false end
	if not addonOn("EllesmereUIChat") then return false end
	local own = ellChat()
	local pos = own and own.chatPosition
	if type(pos) ~= "table" or type(pos.y) ~= "number" then return false end
	-- Still on the console: the player may have nudged or resized it since,
	-- which re-saves the spot, so only its height on the screen is asked.
	return pos.y < Console:OpenHeight()
end

ellDockedNow = ellDocked

function Console:CanFitEllesmere()
	return addonOn("EllesmereUIChat") or addonOn("EllesmereUIDamageMeters")
end

-- Writes the fit. Returns what was fitted as words, or nil and why not.
function Console:FitEllesmere()
	if self.bare or self.db.slim then return nil, "The fit needs the full console." end
	local fit = Stoa.db.ellesmereFit or {}
	local done = {}
	local chat = addonOn("EllesmereUIChat") and Stoa.Conflicts:SteppedAside("ChatLook") and self.db.houseChat
		and ellChat(true)
	if chat then
		if fit.chatBefore == nil then
			fit.chatBefore = { position = shallow(chat.chatPosition) }
		end
		local x, y = ellChatSpot()
		chat.chatPosition = { point = "BOTTOMLEFT", relPoint = "BOTTOMLEFT", x = x, y = y }
		fit.chatAt = { x = x, y = y }
		done[#done + 1] = "the chat"
	end
	local meters = addonOn("EllesmereUIDamageMeters") and ellProfile("EllesmereUIDamageMeters")
	local window = ellMeterWindow(meters)
	if type(window) == "table" then
		if fit.meterBefore == nil then fit.meterBefore = { position = shallow(window.position) } end
		window.position = shallow(ELL_METER)
		done[#done + 1] = "the damage meter"
	end
	if #done == 0 then return nil, "STOA found nothing of EllesmereUI's to fit (its chat must be the one kept)." end
	Stoa.db.ellesmereFit = fit
	return table.concat(done, " and ")
end

-- Puts back what EllesmereUI had before the fit. True when something was.
function Console:UnfitEllesmere()
	local fit = Stoa.db.ellesmereFit
	if not fit then return false end
	local chat = ellChat(true)
	if chat and fit.chatBefore then
		-- A spot that lay on the console (Stoa's Edit Mode layout rests the
		-- chat there), or none at all, would leave the chat seated:
		-- EllesmereUI takes where the chat stands as its spot. It goes back
		-- to standing on the console's edge instead.
		local before = fit.chatBefore.position
		local scale = ChatFrame1 and ChatFrame1:GetScale() or 1
		if type(scale) ~= "number" or scale <= 0 then scale = 1 end
		local edge = self:OpenHeight() / scale
		local low = type(before) ~= "table" or type(before.y) ~= "number"
			or ((before.point or ""):find("BOTTOM") and before.y < edge)
		if low then
			local x = ellChatSpot()
			before = { point = "BOTTOMLEFT", relPoint = "BOTTOMLEFT", x = x,
				y = math.floor(edge + (SLIM_CHAT_LIFT + ELL_EDIT) / scale + 0.5) }
		end
		chat.chatPosition = before
	end
	local meters = ellProfile("EllesmereUIDamageMeters")
	local window = ellMeterWindow(meters)
	if type(window) == "table" and fit.meterBefore then window.position = fit.meterBefore.position or nil end
	Stoa.db.ellesmereFit = nil
	return true
end

Stoa.commands.fit = function(rest)
	if InCombatLockdown() then
		Stoa:Print("Not in a fight. Try /stoa fit again after it.")
		return
	end
	local word = strtrim(rest or ""):lower()
	if word == "undo" then
		if Console:UnfitEllesmere() then
			Stoa:Reload()
		else
			Stoa:Print("STOA hasn't fitted anything of EllesmereUI's.")
		end
		return
	end
	local ok, what, why = pcall(Console.FitEllesmere, Console)
	if not ok then
		Stoa:Print("STOA couldn't read EllesmereUI's settings, so nothing was changed.")
		return
	end
	if not what then
		Stoa:Print(why or "Nothing to fit.")
		return
	end
	Stoa:Reload()
end

-- Whoever else has the chat: Daylight's panel is docked or stands above the
-- console; any other addon's chat is the game's frame, lifted if it lies on
-- the console.
local function clearChat()
	local ok, docked = pcall(dockChat)
	if ok and docked then return end
	if daylightRoom() then return end
	-- EllesmereUI's chat fitted on the page lies on the console on purpose.
	-- EllesmereUI's chat fitted on the page lies on the console on purpose,
	-- and EllesmereUI holds its spot and size with its own anchors: any
	-- re-anchoring from here would drop the size.
	if ellDocked(Console.db) then return end
	liftChat()
end

-- With the console switched off (the Minimal preset) there is no frame to
-- house things in, but Blizzard's bar art, menu, bags and chat still need
-- the same care: the gryphons and stone go, the menu and bags rest in the
-- bottom right corner, and the chat stands in the bottom left.
function Console:OnOff()
	self.bare = true
	local db = self.db
	local function apply()
		if housesChat(db) then
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
	if bar and bar.UpdateDividers then
		hooksecurefunc(bar, "UpdateDividers", function()
			if db.hideBarArt then safely(hideBarArt) end
		end)
	end
end

function Console:House()
	local db = self.db

	local function apply()
		if housesChat(db) then
			safely(placeChat)
			safely(guardChat)
			if artOn() or pillsOn() then safely(buildTabs) end
		elseif db.houseChat then
			safely(clearChat)
			-- The other addon and Edit Mode place the chat a moment after login.
			C_Timer.After(2, function() safely(clearChat) end)
		end
		-- Daylight's other pieces keep clear of the console too.
		safely(daylightRoom)
		if db.hideBarArt then safely(hideBarArt) end
		if db.houseMenu then
			safely(placeMenu)
			safely(dressMenu)
		end
	end

	if housesChat(db) or db.slim or wantsDock(db) or ellDocked(db) then
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

	if housesChat(db) and (artOn() or pillsOn()) then
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
	if bar and bar.UpdateDividers then
		hooksecurefunc(bar, "UpdateDividers", function()
			if db.hideBarArt then safely(hideBarArt) end
		end)
	end
end
