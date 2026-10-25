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

-- Hides a frame's own textures, leaving its children (buttons, text, items).
local function strip(frame)
	if not (frame and frame.GetRegions) then return end
	for _, region in ipairs({ frame:GetRegions() }) do
		if region.IsObjectType and region:IsObjectType("Texture") then region:SetAlpha(0) end
	end
end

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

local function hide(frame)
	if frame and frame.SetAlpha then frame:SetAlpha(0) end
end

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

-- Window tabs (merchant's Merchant/Buyback) as plain words, the selected one
-- in the accent. Blizzard disables the selected tab.
local function colourTabs(frame)
	for _, tab in ipairs(frame.stoaTabs or {}) do
		local text = tab.Text or (tab.GetFontString and tab:GetFontString())
		if text then
			local selected = tab.IsEnabled and not tab:IsEnabled()
			text:SetTextColor(Stoa:Color(selected and "accent" or "muted"))
		end
	end
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

-- The common window: no portrait, no stone border, a Stoa panel and title.
function Windows:Dress(frame)
	if not frame or frame.stoaDressed then return end
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
	UI.windowPanel(frame)

	local title = titleOf(frame)
	if title then
		Stoa:SetFont(title, "serif", Stoa.typeSize.label + 2)
		title:SetTextColor(Stoa:Color("text"))
	end

	local name = frame.GetName and frame:GetName()
	dressClose(frame.CloseButton or (name and _G[name .. "CloseButton"]))
	dressButtonsIn(frame, 5)
	dressTabs(frame)
	hookTabs()
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

-- Blizzard picks text colours to suit the parchment; on a dark panel they
-- need to be light, so every colour it sets is set again.
local function lightQuestText()
	if QuestFrame_SetTitleTextColor then
		hooksecurefunc("QuestFrame_SetTitleTextColor", function(fs) light(fs, true) end)
	end
	if QuestFrame_SetTextColor then
		hooksecurefunc("QuestFrame_SetTextColor", function(fs) light(fs) end)
	end
	local function recolour()
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
	if QuestFrameGreetingPanel then QuestFrameGreetingPanel:HookScript("OnShow", recolour) end
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
		end)
	end
	if frame.Update then hooksecurefunc(frame, "Update", recolour) end
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
	UI.roundPanel(tip, 0.96)
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

local function guarded(fn)
	xpcall(fn, Stoa.catch)
end

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
