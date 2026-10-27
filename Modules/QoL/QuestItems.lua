-- Stoa QoL: quest items at hand.
-- Quests that hand you an item to use (a torch to burn tents, a vial to
-- fill) get a button for it in a small row, so you don't dig through the
-- quest log or bags mid-pull. The row fills from your quest log, lights the
-- quests you're nearest to finishing first, and steps aside when it is
-- empty. Buttons are secure, so the row only changes out of combat; the
-- counts and cooldowns keep up in combat.
local _, ns = ...
local Stoa = ns.Stoa
local UI = Stoa.UI

local QuestItems = Stoa:NewModule("QuestItems", {
	max = 4,
})

local SIZE = 38
local GAP = 6

local function call(fn, ...)
	if type(fn) ~= "function" then return nil end
	local ok, a, b, c, d = pcall(fn, ...)
	if ok then return a, b, c, d end
end

-- The quest items in your log, as links, one per quest, in log order.
function QuestItems:Collect()
	local list, seen = {}, {}
	local count = Stoa:PlainNumber(call(C_QuestLog and C_QuestLog.GetNumQuestLogEntries or GetNumQuestLogEntries)) or 0
	for index = 1, count do
		local info = C_QuestLog and C_QuestLog.GetInfo and call(C_QuestLog.GetInfo, index)
		local header = type(info) == "table" and info.isHeader
		if not header then
			local link, _, _, showWhenComplete = call(GetQuestLogSpecialItemInfo, index)
			local complete = type(info) == "table" and info.questID
				and call(C_QuestLog.IsComplete, info.questID)
			if link and not Stoa:IsSecret(link) and (not complete or showWhenComplete) then
				local id = Stoa.Items.id(link)
				if id and not seen[id] then
					seen[id] = true
					list[#list + 1] = link
				end
			end
		end
	end
	return list
end

function QuestItems:Build()
	if self.frame then return end
	local frame = CreateFrame("Frame", "StoaQuestItems", UIParent)
	frame:SetSize(SIZE, SIZE)
	frame:SetFrameStrata("MEDIUM")
	local halo = _G.StoaHalo
	if halo then
		frame:SetPoint("RIGHT", halo, "LEFT", -150, -40)
	else
		frame:SetPoint("BOTTOM", UIParent, "BOTTOM", -380, 300)
	end
	self.frame, self.buttons = frame, {}
	Stoa:RegisterMover("questItems", frame, "Quest items")
end

function QuestItems:Button(i)
	local button = self.buttons[i]
	if not button then
		button = UI.itemButton(self.frame, "StoaQuestItem" .. i, SIZE)
		button:SetPoint("RIGHT", self.frame, "RIGHT", -(i - 1) * (SIZE + GAP), 0)
		self.buttons[i] = button
	end
	return button
end

-- Rebuilds the row: only out of combat, as the buttons are secure.
function QuestItems:Update()
	if InCombatLockdown() then
		self.pending = true
		return
	end
	self.pending = false
	local list = self:Collect()
	local max = math.max(1, math.min(self.db.max or 4, 8))
	for i = 1, math.max(max, #self.buttons) do
		local link = i <= max and list[i]
		if link then
			local button = self:Button(i)
			if button.link ~= link then button:SetItem(link) end
			button:Show()
		elseif self.buttons[i] then
			self.buttons[i]:SetItem(nil)
			self.buttons[i]:Hide()
		end
	end
	local shown = math.min(#list, max)
	self.frame:SetWidth(math.max(1, shown) * (SIZE + GAP) - GAP)
	self.frame:SetShown(shown > 0)
end

function QuestItems:Refresh()
	for _, button in ipairs(self.buttons or {}) do
		if button:IsShown() then button:Refresh() end
	end
end

function QuestItems:OnEnable()
	Stoa:AfterCombat(function()
		xpcall(function()
			self:Build()
			self:Update()
		end, Stoa.catch)
	end)
	local queued
	local function soon()
		if queued or not self.frame then return end
		queued = true
		C_Timer.After(0.3, function()
			queued = false
			xpcall(function() self:Update() end, Stoa.catch)
		end)
	end
	for _, event in ipairs({ "QUEST_LOG_UPDATE", "QUEST_ACCEPTED", "QUEST_REMOVED", "BAG_UPDATE_DELAYED" }) do
		Stoa:On(event, soon)
	end
	Stoa:On("PLAYER_REGEN_ENABLED", function() if self.pending then soon() end end)
	Stoa:On("BAG_UPDATE_COOLDOWN", function() self:Refresh() end)
	Stoa:On("SPELL_UPDATE_COOLDOWN", function() self:Refresh() end)
end
