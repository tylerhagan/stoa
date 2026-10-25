-- Stoa QoL: best quest reward. When a quest offers a choice of rewards, the
-- one that beats what you wear is marked UPGRADE (the biggest gain wins);
-- if none does, the one that sells for most is marked VALUE. A thin accent
-- outline and a small word on the button, nothing more. Every frame is
-- looked up by name and skipped if this client calls it something else.
local _, ns = ...
local Stoa = ns.Stoa
local hooksecurefunc = Stoa.SafeHook
local UI = Stoa.UI

local Reward = Stoa:NewModule("QuestReward", {})

local function call(fn, ...)
	if type(fn) ~= "function" then return nil end
	local ok, a, b, c, d = pcall(fn, ...)
	if ok then return a, b, c, d end
end

-- The button for choice number i, by either of the names it has had.
local function choiceButton(i)
	local button = _G["QuestInfoRewardsFrameQuestInfoItem" .. i]
	if not button then
		local rewards = QuestInfoRewardsFrame
		button = type(rewards) == "table" and type(rewards.RewardButtons) == "table" and rewards.RewardButtons[i]
	end
	if type(button) ~= "table" or not button.CreateFontString then return nil end
	if button.type and button.type ~= "choice" then return nil end
	return button
end

local function parts(button)
	if button.stoaPick then return button.stoaPick end
	local p = {}
	button.stoaPick = p
	p.edge = UI.roundBorder and UI.roundBorder(button, "CardEdge.tga", 1)
	p.word = button:CreateFontString(nil, "OVERLAY", nil, 7)
	Stoa:SetFont(p.word, "sans", Stoa.typeSize.caption, "OUTLINE")
	p.word:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -2, 2)
	return p
end

local function clear(button)
	local p = button.stoaPick
	if not p then return end
	if p.edge then p.edge:Clear() end
	p.word:SetText("")
end

-- Picks the choice to mark: returns index, "UPGRADE" or "VALUE", or nil.
function Reward:Pick()
	local count = Stoa:PlainNumber(call(GetNumQuestChoices)) or 0
	if count < 2 or not GetQuestItemLink then return nil end
	local bestGain, gainIndex, bestValue, valueIndex = 0, nil, 0, nil
	for i = 1, count do
		local link = call(GetQuestItemLink, "choice", i)
		if link and not Stoa:IsSecret(link) then
			local delta = Stoa.Items.compare(link)
			if delta and delta > bestGain then bestGain, gainIndex = delta, i end
			local _, _, amount = call(GetQuestItemInfo, "choice", i)
			amount = Stoa:PlainNumber(amount) or 1
			local value = (Stoa.Items.sellPrice(link) or 0) * amount
			if value > bestValue then bestValue, valueIndex = value, i end
		end
	end
	if gainIndex then return gainIndex, "UPGRADE" end
	if valueIndex then return valueIndex, "VALUE" end
end

function Reward:Refresh()
	local count = Stoa:PlainNumber(call(GetNumQuestChoices)) or 0
	for i = 1, math.max(count, 6) do
		local button = choiceButton(i)
		if button then clear(button) end
	end
	self.marked = nil
	local index, kind = self:Pick()
	if not index then return end
	local button = choiceButton(index)
	if not button then return end
	local p = parts(button)
	if p.edge then p.edge:Set(Stoa:Color("accent")) end
	p.word:SetText(kind)
	p.word:SetTextColor(Stoa:Color(kind == "UPGRADE" and "accent" or "muted"))
	self.marked = { index = index, kind = kind }
end

function Reward:OnEnable()
	local function refresh() xpcall(function() Reward:Refresh() end, Stoa.catch) end
	if QuestInfo_Display then hooksecurefunc("QuestInfo_Display", refresh) end
	if QuestFrameRewardPanel and QuestFrameRewardPanel.HookScript then
		QuestFrameRewardPanel:HookScript("OnShow", refresh)
	end
	-- Item details arrive a moment after the window opens.
	Stoa:On("GET_ITEM_INFO_RECEIVED", function()
		if QuestFrameRewardPanel and QuestFrameRewardPanel.IsShown and QuestFrameRewardPanel:IsShown() then refresh() end
	end)
	Stoa:On("QUEST_ITEM_UPDATE", refresh)
end
