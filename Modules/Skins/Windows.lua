-- Stoa: Blizzard's NPC windows in Stoa's dress.
-- Quest, gossip, merchant, trainer and bag windows lose their parchment and
-- stone frames for a dark rounded panel with a hairline edge; quest and
-- gossip text turns light to read on it, in Stoa's type.
--
-- Everything is looked up by name and guarded, so a window this client has
-- renamed or rebuilt is simply left as Blizzard drew it.
local _, ns = ...
local Stoa = ns.Stoa
local UI = Stoa.UI

local Windows = Stoa:NewModule("Windows")

-- Hides a frame's own textures, leaving its children (buttons, text, items).
local function strip(frame)
	if not (frame and frame.GetRegions) then return end
	for _, region in ipairs({ frame:GetRegions() }) do
		if region.IsObjectType and region:IsObjectType("Texture") then region:SetAlpha(0) end
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
	UI.roundPanel(frame)

	local title = titleOf(frame)
	if title then
		Stoa:SetFont(title, "serif", Stoa.typeSize.label + 2)
		title:SetTextColor(Stoa:Color("text"))
	end
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
	strip(frame.BottomInset)
	if frame.BottomInset then hide(frame.BottomInset.NineSlice) end
end

local function dressBags()
	if ContainerFrameCombinedBags then Windows:Dress(ContainerFrameCombinedBags) end
	for i = 1, 13 do
		local bag = _G["ContainerFrame" .. i]
		if bag then Windows:Dress(bag) end
	end
end

local function guarded(fn)
	xpcall(fn, geterrorhandler())
end

function Windows:OnEnable()
	guarded(questFonts)
	guarded(dressQuest)
	guarded(dressGossip)
	guarded(dressMerchant)
	guarded(dressBags)
	-- The trainer window loads with its own addon the first time it opens.
	if ClassTrainerFrame then
		guarded(dressTrainer)
	else
		Stoa:On("ADDON_LOADED", function(name)
			if name == "Blizzard_TrainerUI" then guarded(dressTrainer) end
		end)
	end
	Stoa:On("STOA_THEME_CHANGED", function() UI.applyTheme() end)
end
