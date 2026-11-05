-- Stoa: Blizzard's NPC windows in Stoa's dress.
-- Quest, gossip, merchant, trainer and bag windows lose their parchment and
-- stone frames for a dark rounded panel with a hairline edge; quest and
-- gossip text turns light to read on it, in Stoa's type.
--
-- Everything is looked up by name and guarded, so a window this client has
-- renamed or rebuilt is simply left as Blizzard drew it.
local _, ns = ...
local Stoa = ns.Stoa
local hooksecurefunc = Stoa.SafeHook
local UI = Stoa.UI

local Windows = Stoa:NewModule("Windows")

local strip = Stoa.frames.strip

-- Strips the plain frames inside a window too, down a few levels, leaving
-- buttons, bars and edit boxes (and their icons) alone.
local KEEP = { Button = true, CheckButton = true, StatusBar = true, EditBox = true, Cooldown = true }
local function stripInside(frame, depth)
	if not (frame and frame.GetChildren) or depth <= 0 then return end
	for _, child in ipairs({ frame:GetChildren() }) do
		local kind = child.GetObjectType and child:GetObjectType()
		if not KEEP[kind] then
			strip(child)
			stripInside(child, depth - 1)
		end
	end
end

local hide = Stoa.frames.hide

local function titleOf(frame)
	if frame.TitleContainer and frame.TitleContainer.TitleText then return frame.TitleContainer.TitleText end
	if frame.TitleText then return frame.TitleText end
	if frame.GetTitleText then return frame:GetTitleText() end
end

-- Buttons ------------------------------------------------------------------

-- Blizzard's red panel buttons become dark rounded keys with light words;
-- the edge warms to the accent under the mouse. Textures only, so this is
-- fine on secure buttons too.
local PANEL_PARTS = { "Left", "Middle", "Right", "LeftSeparator", "RightSeparator" }

local function isPanelButton(button)
	return button.Left and button.Middle and button.Right
end

local function plainTextures(button)
	for _, key in ipairs(PANEL_PARTS) do hide(button[key]) end
	for _, getter in ipairs({ "GetNormalTexture", "GetPushedTexture", "GetHighlightTexture", "GetDisabledTexture" }) do
		local tex = button[getter] and button[getter](button)
		if tex then tex:SetAlpha(0) end
	end
end

local function dressButton(button)
	if not button or button.stoaDressed then return end
	button.stoaDressed = true
	plainTextures(button)
	-- Blizzard puts the art back on some state changes.
	button:HookScript("OnShow", plainTextures)
	button:HookScript("OnEnable", plainTextures)
	button:HookScript("OnDisable", plainTextures)
	UI.roundPanel(button, 0.95)
	local glow = UI.roundBorder(button, "CardEdge.tga", 1)
	local text = button.GetFontString and button:GetFontString()
	if text then
		Stoa:SetFont(text, "sans", Stoa.typeSize.body)
		text:SetShadowOffset(0, 0)
	end
	local function colour(over)
		if text then
			local enabled = not button.IsEnabled or button:IsEnabled()
			text:SetTextColor(Stoa:Color(not enabled and "muted" or over and "accent" or "text"))
		end
		if over then glow:Set(Stoa:Color("accent")) else glow:Clear() end
	end
	button:HookScript("OnEnter", function() colour(true) end)
	button:HookScript("OnLeave", function() colour(false) end)
	button:HookScript("OnShow", function() colour(false) end)
	button.stoaColour = colour
	colour(false)
end

-- The close X: just a quiet cross, warming to the accent under the mouse.
local function dressClose(button)
	if not button or button.stoaDressed then return end
	button.stoaDressed = true
	plainTextures(button)
	button:HookScript("OnShow", plainTextures)
	local cross = button:CreateFontString(nil, "OVERLAY")
	Stoa:SetFont(cross, "sans", Stoa.typeSize.title)
	cross:SetPoint("CENTER", 0, 1)
	cross:SetText("×")
	cross:SetTextColor(Stoa:Color("muted"))
	button:HookScript("OnEnter", function() cross:SetTextColor(Stoa:Color("accent")) end)
	button:HookScript("OnLeave", function() cross:SetTextColor(Stoa:Color("muted")) end)
end

-- Every red button inside a window, however deep.
local function dressButtonsIn(frame, depth)
	if not (frame and frame.GetChildren) or depth <= 0 then return end
	for _, child in ipairs({ frame:GetChildren() }) do
		if child.IsObjectType and child:IsObjectType("Button") and isPanelButton(child) then
			dressButton(child)
		end
		dressButtonsIn(child, depth - 1)
	end
end

Windows.DressButtonsIn = dressButtonsIn

-- Window tabs stay where Blizzard hangs them, under the window, dressed as
-- tabs of the window: a dark rounded tab tucked under its edge, the chosen
-- one in the footer's shade with its word in the text colour over a short
-- accent underline, the rest darker with quiet words. Blizzard disables
-- the selected tab.
local TAB_SHADE = { selected = 0.32, other = 0.5 }

local function tabSelected(tab)
	if tab.isSelected ~= nil then return tab.isSelected and true or false end
	return tab.IsEnabled and not tab:IsEnabled()
end

local function colourTabs(frame)
	for _, tab in ipairs(frame.stoaTabs or {}) do
		local selected = tabSelected(tab)
		local text = tab.Text or (tab.GetFontString and tab:GetFontString())
		if text then text:SetTextColor(Stoa:Color(selected and "text" or "muted")) end
		if tab.stoaShade then
			tab.stoaShade:SetVertexColor(0, 0, 0, selected and TAB_SHADE.selected or TAB_SHADE.other)
			tab.stoaUnderline:SetShown(selected)
		end
	end
end

local function tabArt(tab)
	if tab.stoaShade then return end
	local base = UI.sliced(tab, "BACKGROUND", "TabFill.tga")
	if not base then return end
	-- Reaches up over the window's bottom edge so the tab reads as part of it.
	base:SetPoint("TOPLEFT", 0, 3)
	base:SetDrawLayer("BACKGROUND", -8)
	UI.tint(base, "panel", 0.97)
	local shade = UI.sliced(tab, "BACKGROUND", "TabFill.tga")
	shade:SetPoint("TOPLEFT", 0, 3)
	shade:SetDrawLayer("BACKGROUND", -7)
	local edge = UI.sliced(tab, "BORDER", "TabEdge.tga")
	if edge then
		edge:SetPoint("TOPLEFT", 0, 3)
		UI.tint(edge, "hairline")
	end
	local underline = tab:CreateTexture(nil, "ARTWORK")
	underline:SetHeight(2)
	local text = tab.Text or (tab.GetFontString and tab:GetFontString())
	if text then
		underline:SetPoint("TOPLEFT", text, "BOTTOMLEFT", -2, -3)
		underline:SetPoint("TOPRIGHT", text, "BOTTOMRIGHT", 2, -3)
	else
		underline:SetPoint("BOTTOMLEFT", 10, 6)
		underline:SetPoint("BOTTOMRIGHT", -10, 6)
	end
	UI.paint(underline, "accent")
	tab.stoaShade, tab.stoaUnderline = shade, underline
	UI.applyTheme()
end

local function dressTabs(frame)
	local name = frame.GetName and frame:GetName()
	local tabs = frame.Tabs
	if not tabs and name then
		tabs = {}
		for i = 1, 6 do
			local tab = _G[name .. "Tab" .. i]
			if tab then tabs[#tabs + 1] = tab end
		end
	end
	if not tabs or #tabs == 0 then return end
	frame.stoaTabs = tabs
	for _, tab in ipairs(tabs) do
		strip(tab)
		for _, key in ipairs({ "Left", "Middle", "Right", "LeftActive", "MiddleActive", "RightActive", "LeftHighlight", "MiddleHighlight", "RightHighlight" }) do
			hide(tab[key])
		end
		local text = tab.Text or (tab.GetFontString and tab:GetFontString())
		if text then
			Stoa:SetFont(text, "sans", Stoa.typeSize.body)
			text:SetShadowOffset(0, 0)
		end
		xpcall(tabArt, Stoa.catch, tab)
		tab:HookScript("OnEnter", function(self)
			local words = self.Text or (self.GetFontString and self:GetFontString())
			if words and not tabSelected(self) then words:SetTextColor(Stoa:Color("accent")) end
		end)
		tab:HookScript("OnLeave", function() colourTabs(frame) end)
	end
	colourTabs(frame)
	frame:HookScript("OnShow", function() colourTabs(frame) end)
end

local hookedTabs
local function hookTabs()
	if hookedTabs or not PanelTemplates_UpdateTabs then return end
	hookedTabs = true
	hooksecurefunc("PanelTemplates_UpdateTabs", function(frame)
		if frame and frame.stoaTabs then colourTabs(frame) end
	end)
end

-- Header tints by what a window is for (see UI.WINDOW_FAMILIES).
local FAMILY = {
	MerchantFrame = "trade", MailFrame = "trade", OpenMailFrame = "trade",
	AuctionHouseFrame = "trade", BankFrame = "trade",
	FriendsFrame = "social", CommunitiesFrame = "social", GuildFrame = "social",
	PVEFrame = "social", LFDParentFrame = "social", RaidParentFrame = "social",
}
-- The rulebook's band is BAND tall on every window with room for it.
-- Where Blizzard's content starts higher (its inset, or bag slots on a
-- window with no inset) the band stops there instead, so it never runs
-- under content; without an inset it is HEADER_FALLBACK, the compact band.
local BAND = 44
local HEADER_FALLBACK = 30
local TITLE_INSET = 18
Windows.FAMILY, Windows.HEADER_FALLBACK, Windows.BAND = FAMILY, HEADER_FALLBACK, BAND

-- Windows Stoa never dresses. The game menu and the settings panel are a
-- known cause of blocked-action errors when addons touch them; the rest
-- are drawn over live content or are Blizzard's own small prompts.
Windows.LEAVE = {
	GameMenuFrame = true, SettingsPanel = true, InterfaceOptionsFrame = true,
	VideoOptionsFrame = true, StaticPopup1 = true, StaticPopup2 = true, StaticPopup3 = true,
}

function Windows:Leaves(frame)
	local name = frame and frame.GetName and frame:GetName()
	return name ~= nil and self.LEAVE[name] == true
end

-- The band's height gives the title room above and below: the title sits
-- in the middle of it on the left, the close cross on the right. Out of
-- combat only, so moving them never touches a locked frame.
local function seatTitle(frame, title, close)
	local header = frame.stoaHeader
	if not header or InCombatLockdown() then return end
	if title then
		title:ClearAllPoints()
		title:SetPoint("LEFT", header, "LEFT", TITLE_INSET, 0)
		title:SetJustifyH("LEFT")
	end
	if close then
		close:ClearAllPoints()
		close:SetPoint("RIGHT", header, "RIGHT", -8, 0)
	end
end

-- Settling --------------------------------------------------------------------
-- Blizzard lays a window out again when it shows (and some parts a frame
-- later), so each dressed window has one settle step: the band takes its
-- height from where content now starts, Blizzard's border art is hidden
-- again, the title and close are seated, then any extra steps a skin
-- registered with Windows:OnSettle. It runs on show and on the next frame.

local function bandHeight(frame)
	local inset = frame.Inset
	if not (inset and inset.GetTop and frame.GetTop) then return nil end
	local top, start = frame:GetTop(), inset:GetTop()
	if Stoa:IsSecret(top) or Stoa:IsSecret(start) or not top or not start then return nil end
	local gap = top - start
	-- A window with a two-line header asks for more (frame.stoaBandHeight).
	-- "inset" makes the band reach all the way down to where content starts.
	-- A dark strip meets Blizzard's dark content with no light gap between.
	if (frame.stoaBandHeight == "inset" or frame.stoaPlainHeader) and gap >= HEADER_FALLBACK then return math.floor(gap + 0.5) end
	local want = tonumber(frame.stoaBandHeight) or BAND
	if gap >= want then return want end
	return nil
end

function Windows:Settle(frame)
	if not frame or InCombatLockdown() then return end
	hide(frame.NineSlice)
	hide(frame.PortraitContainer)
	local header = frame.stoaHeader
	local height = header and bandHeight(frame)
	if height and header.stoaHeight ~= height then
		header:ClearAllPoints()
		header:SetPoint("TOPLEFT")
		header:SetPoint("TOPRIGHT")
		header:SetHeight(height)
		header.stoaHeight = height
	end
	if not frame.stoaBorderOnly then
		local name = frame.GetName and frame:GetName()
		pcall(seatTitle, frame, titleOf(frame), frame.CloseButton or (name and _G[name .. "CloseButton"]))
	end
	for _, step in ipairs(frame.stoaSettlers or {}) do
		xpcall(step, Stoa.catch, frame)
	end
end

-- Adds a step to a window's settle (it runs now if the window is shown).
function Windows:OnSettle(frame, step)
	if not frame then return end
	frame.stoaSettlers = frame.stoaSettlers or {}
	table.insert(frame.stoaSettlers, step)
	if frame:IsShown() then xpcall(step, Stoa.catch, frame) end
end

function Windows:KeepSettled(frame)
	if not frame or frame.stoaSettling or not frame.HookScript then return end
	frame.stoaSettling = true
	frame:HookScript("OnShow", function(self)
		Windows:Settle(self)
		C_Timer.After(0, function() Windows:Settle(self) end)
	end)
end

-- The common window: no portrait, no stone border, a Stoa panel with a
-- header band, a dark footer tray below Blizzard's inset, and the title in
-- the header.
function Windows:Dress(frame)
	if not frame or frame.stoaDressed or self:Leaves(frame) then return end
	frame.stoaDressed = true
	strip(frame)
	for _, key in ipairs({ "NineSlice", "Bg", "TopTileStreaks", "PortraitContainer", "portrait", "PortraitFrame" }) do
		hide(frame[key])
	end
	if frame.TitleContainer then strip(frame.TitleContainer) end
	local inset = frame.Inset
	if inset then
		strip(inset)
		hide(inset.NineSlice)
		hide(inset.Bg)
	end
	local name = frame.GetName and frame:GetName()
	local title = titleOf(frame)
	UI.windowPanel(frame, nil, {
		header = inset or (title and HEADER_FALLBACK) or nil,
		footer = inset,
		family = FAMILY[name or ""],
		-- Blizzard's windows carry a lot in their top strip already (tabs,
		-- buttons, search), so the title sits on the panel without a band.
		plainHeader = true,
	})

	if title then
		Stoa:SetFont(title, "serif", Stoa.typeSize.title)
		title:SetTextColor(Stoa:Color("text"))
	end

	local close = frame.CloseButton or (name and _G[name .. "CloseButton"])
	dressClose(close)
	pcall(seatTitle, frame, title, close)
	dressButtonsIn(frame, 5)
	dressTabs(frame)
	hookTabs()
	self:KeepSettled(frame)
	self:Settle(frame)
end

-- Quest text ----------------------------------------------------------------

local function light(fs, title)
	if not (fs and fs.SetTextColor) then return end
	if title then
		fs:SetTextColor(Stoa:Color("accent"))
	else
		fs:SetTextColor(Stoa:Color("text"))
	end
end

-- Quest titles in the gossip and quest greeting lists carry their colour in
-- the text itself (NORMAL_QUEST_DISPLAY is "|cff000000%s|r", black for the
-- parchment), so a text colour alone can't lift them. The black code is
-- taken out; other colours (trivial, ignored) stay.
local function unblack(button)
	if not (button and button.GetText and button.SetText) then return end
	local text = button:GetText()
	if type(text) ~= "string" or Stoa:IsSecret(text) then return end
	local clean, found = text:gsub("|[cC][fF][fF]000000", "")
	if found > 0 then button:SetText(clean) end
	local fs = button.GetFontString and button:GetFontString()
	if fs then light(fs) end
end

local function unblackAll(parent, depth)
	if not (parent and parent.GetChildren) or (depth or 0) > 4 then return end
	for _, child in ipairs({ parent:GetChildren() }) do
		if child.IsObjectType and child:IsObjectType("Button") then unblack(child) end
		unblackAll(child, (depth or 0) + 1)
	end
end

-- Blizzard picks text colours to suit the parchment; on a dark panel they
-- need to be light, so every colour it sets is set again.
-- The map's quest log shows the same quest text on Blizzard's parchment,
-- which Stoa leaves alone, so its dark colours stay there.
local function onParchment()
	return QuestInfoFrame and QuestInfoFrame.questLog
end

local function lightQuestText()
	if QuestFrame_SetTitleTextColor then
		hooksecurefunc("QuestFrame_SetTitleTextColor", function(fs) if not onParchment() then light(fs, true) end end)
	end
	if QuestFrame_SetTextColor then
		hooksecurefunc("QuestFrame_SetTextColor", function(fs) if not onParchment() then light(fs) end end)
	end
	local function recolour()
		if onParchment() then return end
		for _, name in ipairs({ "QuestInfoTitleHeader", "QuestInfoDescriptionHeader", "QuestInfoObjectivesHeader", "QuestProgressTitleText" }) do
			light(_G[name], true)
		end
		for _, name in ipairs({
			"QuestInfoDescriptionText", "QuestInfoObjectivesText", "QuestInfoGroupSize", "QuestInfoRewardText",
			"QuestProgressText", "QuestProgressRequiredItemsText", "QuestProgressRequiredMoneyText",
			"GreetingText", "CurrentQuestsText", "AvailableQuestsText",
		}) do
			light(_G[name])
		end
		local rewards = QuestInfoRewardsFrame
		if rewards then
			light(rewards.Header, true)
			light(rewards.ItemChooseText)
			light(rewards.ItemReceiveText)
			light(rewards.PlayerTitleText)
			if rewards.XPFrame then light(rewards.XPFrame.ReceiveText) end
		end
		local objectives = QuestInfoObjectivesFrame and QuestInfoObjectivesFrame.Objectives
		for _, line in ipairs(objectives or {}) do light(line) end
	end
	if QuestInfo_Display then hooksecurefunc("QuestInfo_Display", recolour) end
	if QuestFrameProgressItems_Update then hooksecurefunc("QuestFrameProgressItems_Update", recolour) end
	if QuestFrameGreetingPanel then
		QuestFrameGreetingPanel:HookScript("OnShow", recolour)
		-- Its title buttons are filled in as it shows.
		QuestFrameGreetingPanel:HookScript("OnShow", function(panel)
			C_Timer.After(0, function() xpcall(unblackAll, Stoa.catch, panel) end)
		end)
	end
end

-- Quest fonts in Stoa's type: titles in the display face, body in Inter.
local function questFonts()
	local display, sans = Stoa.fonts.serif[1], Stoa.fonts.sans[1]
	local function face(fontObject, file, size)
		if fontObject and fontObject.SetFont then pcall(fontObject.SetFont, fontObject, file[1], size * file[2], "") end
	end
	face(QuestTitleFont, display, 18)
	face(QuestTitleFontBlackShadow, display, 18)
	face(QuestFont, sans, 13)
	face(QuestFontNormalSmall, sans, 12)
end

local function dressQuest()
	local frame = QuestFrame
	if not frame then return end
	Windows:Dress(frame)
	for _, name in ipairs({ "QuestFrameDetailPanel", "QuestFrameProgressPanel", "QuestFrameRewardPanel", "QuestFrameGreetingPanel" }) do
		local panel = _G[name]
		strip(panel)
		if panel then hide(panel.Bg) hide(panel.SealMaterialBG) hide(panel.MaterialTopLeft) end
	end
	for _, name in ipairs({ "QuestDetailScrollFrame", "QuestProgressScrollFrame", "QuestRewardScrollFrame", "QuestGreetingScrollFrame" }) do
		strip(_G[name])
	end
	-- The rewards sit together in a darker well.
	if QuestInfoRewardsFrame then UI.well(QuestInfoRewardsFrame, 4) end
	lightQuestText()
end

-- Gossip: the greeting and option lines live in a scroll box that remakes
-- its rows, so each row is recoloured as it's laid out.
local function dressGossip()
	local frame = GossipFrame
	if not frame then return end
	Windows:Dress(frame)
	local greeting = frame.GreetingPanel
	if not greeting then return end
	strip(greeting)
	local box = greeting.ScrollBox
	local function recolour()
		if not (box and box.ForEachFrame) then return end
		box:ForEachFrame(function(row)
			light(row.GreetingText)
			if row.GetFontString and row:GetFontString() then light(row:GetFontString()) end
			-- Quest rows set their title again whenever the quest updates.
			if row.UpdateTitleForQuest and not row.stoaUnblack then
				row.stoaUnblack = true
				hooksecurefunc(row, "UpdateTitleForQuest", unblack)
			end
			unblack(row)
		end)
	end
	if frame.Update then hooksecurefunc(frame, "Update", recolour) end
	-- The gossip frame is a theme container: it colours each line for the
	-- parchment as it registers it, after the rows are laid out.
	if frame.RegisterFontString then
		hooksecurefunc(frame, "RegisterFontString", function(_, fs) light(fs) end)
	end
	if box and box.RegisterCallback and ScrollBoxListMixin and ScrollBoxListMixin.Event then
		box:RegisterCallback(ScrollBoxListMixin.Event.OnDataRangeChanged, recolour, Windows)
	end
	frame:HookScript("OnShow", recolour)
end

local function dressMerchant()
	local frame = MerchantFrame
	if not frame then return end
	Windows:Dress(frame)
	for _, name in ipairs({ "MerchantFrameInset", "MerchantMoneyInset", "MerchantMoneyBg", "MerchantExtraCurrencyInset", "MerchantExtraCurrencyBg" }) do
		local part = _G[name]
		strip(part)
		if part then hide(part.NineSlice) hide(part.Bg) end
	end
	strip(frame.BottomInset)
	for i = 1, 12 do
		hide(_G["MerchantItem" .. i .. "SlotTexture"])
		hide(_G["MerchantItem" .. i .. "NameFrame"])
	end
	hide(MerchantBuyBackItemSlotTexture)
	hide(MerchantBuyBackItemNameFrame)
end

local function dressTrainer()
	local frame = ClassTrainerFrame
	if not frame then return end
	Windows:Dress(frame)
	stripInside(frame, 4)
	-- Blizzard hangs its Settings/Filters dropdown at the top right, where
	-- Stoa's header seats the close button: it moves in beside the close.
	Windows:OnSettle(frame, function()
		local dropdown, close = frame.FilterDropdown, frame.CloseButton or _G.ClassTrainerFrameCloseButton
		if dropdown and close and dropdown.ClearAllPoints then
			dropdown:ClearAllPoints()
			dropdown:SetPoint("RIGHT", close, "LEFT", -8, 0)
		end
		-- Your money sits at the left of the footer, level with Train.
		local money, train = frame.money, frame.TrainButton
		if money and money.ClearAllPoints then
			local lift = train and train.GetHeight and (train:GetHeight() / 2) or 11
			money:ClearAllPoints()
			money:SetPoint("LEFT", frame, "BOTTOMLEFT", 14, lift)
		end
	end)
end

local function dressBags()
	if ContainerFrameCombinedBags then Windows:Dress(ContainerFrameCombinedBags) end
	for i = 1, 13 do
		local bag = _G["ContainerFrame" .. i]
		if bag then Windows:Dress(bag) end
	end
end

-- Tooltips: the same dark rounded panel, a thin health bar, and the
-- default spot lifted to sit above the console's right corner instead of
-- over it.
local TOOLTIPS = { "GameTooltip", "ItemRefTooltip", "ShoppingTooltip1", "ShoppingTooltip2", "EmbeddedItemTooltip" }
local TOOLTIP_GAP = 16

local function dressTooltip(tip)
	if not tip or tip.stoaDressed then return end
	tip.stoaDressed = true
	hide(tip.NineSlice)
	UI.surface(tip, "card", { alpha = 0.96 })
	-- Blizzard re-applies its backdrop style each time a tooltip shows.
	tip:HookScript("OnShow", function(self) hide(self.NineSlice) end)
end

local function dressTooltips()
	for _, name in ipairs(TOOLTIPS) do dressTooltip(_G[name]) end
	local bar = GameTooltipStatusBar
	if bar then
		bar:SetStatusBarTexture(UI.WHITE)
		bar:SetHeight(3)
		bar:ClearAllPoints()
		bar:SetPoint("TOPLEFT", GameTooltip, "BOTTOMLEFT", 8, -3)
		bar:SetPoint("TOPRIGHT", GameTooltip, "BOTTOMRIGHT", -8, -3)
		UI.surface(bar, "well", { outset = 1 })
		hooksecurefunc(bar, "SetStatusBarColor", function(self)
			if self.stoaColouring then return end
			self.stoaColouring = true
			self:SetStatusBarColor(Stoa:Color("health"))
			self.stoaColouring = false
		end)
	end
	if GameTooltip_SetDefaultAnchor then
		hooksecurefunc("GameTooltip_SetDefaultAnchor", function(tooltip, parent)
			if (tooltip.IsForbidden and tooltip:IsForbidden()) or tooltip:GetOwner() ~= parent then return end
			local cards = Stoa.modules.Tooltip
			if cards and cards.Anchor and Stoa:IsModuleEnabled("Tooltip") and cards:Anchor(tooltip, parent) then return end
			local console = Stoa.modules.Grimoire
			local floor = console and console.db and console.db.enabled ~= false and console.OpenHeight and console:OpenHeight() or 0
			tooltip:ClearAllPoints()
			tooltip:SetPoint("BOTTOMRIGHT", UIParent, "BOTTOMRIGHT", -Stoa.space.xxl, floor + TOOLTIP_GAP)
		end)
	end
end

-- The ready check prompt: the listener frame is the window; the frame
-- around it only carries events. The Ready and Not ready buttons are dressed
-- with the rest. Off with the kit's ready check setting.
local function dressReadyCheck()
	local kit = Stoa.modules.Kit
	if kit and kit.db and kit.db.readyCheck == false then return end
	local frame = ReadyCheckListenerFrame
	if not frame then return end
	Windows:Dress(frame)
	hide(frame.FrameGlow)
	hide(frame.Bg)
	strip(ReadyCheckFrame)
	local text = frame.Text or ReadyCheckFrameText
	if text then
		Stoa:SetFont(text, "sans", Stoa.typeSize.body)
		text:SetTextColor(Stoa:Color("text"))
	end
	-- The text is set again each time the prompt opens.
	frame:HookScript("OnShow", function()
		xpcall(function()
			if text then text:SetTextColor(Stoa:Color("text")) end
			dressButtonsIn(frame, 3)
		end, Stoa.catch)
	end)
end

local guarded = Stoa.safe.guarded

function Windows:OnEnable()
	guarded(questFonts)
	guarded(dressQuest)
	guarded(dressGossip)
	guarded(dressMerchant)
	guarded(dressBags)
	guarded(dressTooltips)
	guarded(dressReadyCheck)
	-- The trainer window loads with its own addon the first time it opens.
	if ClassTrainerFrame then
		guarded(dressTrainer)
	else
		Stoa:On("ADDON_LOADED", function(name)
			if name == "Blizzard_TrainerUI" then guarded(dressTrainer) end
		end)
	end
	Stoa:On("STOA_THEME_CHANGED", function() UI.applyTheme() end)
	-- Quest and gossip buttons are made when a panel first opens.
	for _, frame in ipairs({ QuestFrame, GossipFrame, MerchantFrame }) do
		if frame then
			frame:HookScript("OnShow", function() guarded(function() dressButtonsIn(frame, 5) end) end)
		end
	end
end
