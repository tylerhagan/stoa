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

local call = Stoa.safe.call

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
	self.frame, self.buttons = frame, {}
	self:Place()
	Stoa:RegisterMover("questItems", frame, "Quest items", { default = function() self:Place() end })
end

-- A frame's box in UIParent's units (group frames can carry their own scale).
local function box(frame)
	if not (frame and frame.IsShown and frame:IsShown() and frame.GetRect) then return end
	local left, bottom, width, height = frame:GetRect()
	if not (left and width and width > 1) then return end
	local k = (frame:GetEffectiveScale() or 1) / (UIParent:GetEffectiveScale() or 1)
	return left * k, bottom * k, (left + width) * k, (bottom + height) * k
end

local function overlaps(a, b)
	local al, ab, ar, at = box(a)
	local bl, bb, br, bt = box(b)
	if not (al and bl) then return false end
	return al < br and ar > bl and ab < bt and at > bb
end

-- Left of the Halo, beside the emergency buttons. If the group frames sit
-- there (a party row, a moved group), the row steps to the group's left
-- so it never covers a name or a health bar. Out of combat only: the
-- buttons are secure. A spot you set with /stoa move wins.
function QuestItems:Place()
	local frame = self.frame
	if not frame or InCombatLockdown() or Stoa:HasSavedPosition("questItems") then return end
	local halo = _G.StoaHalo
	frame:ClearAllPoints()
	if halo then
		frame:SetPoint("RIGHT", halo, "LEFT", -150, -40)
	else
		frame:SetPoint("BOTTOM", UIParent, "BOTTOM", -380, 300)
	end
	-- Only the group frames you can see in your group count: solo, an
	-- empty holder could still claim the spot and send the row to the
	-- screen's edge.
	local group = IsInRaid() and _G.StoaRaid or IsInGroup() and _G.StoaParty or nil
	if group and overlaps(frame, group) then
		frame:ClearAllPoints()
		local left = box(group)
		local k = (UIParent:GetEffectiveScale() or 1) / (frame:GetEffectiveScale() or 1)
		if left and left * k > frame:GetWidth() + 24 then
			frame:SetPoint("TOPRIGHT", group, "TOPLEFT", -12, 0)
		else
			-- No room to its left (a column at the screen's edge): above it.
			frame:SetPoint("BOTTOMLEFT", group, "TOPLEFT", 0, 12)
		end
	end
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
	if shown > 0 then self:Place() end
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
	for _, event in ipairs({ "QUEST_LOG_UPDATE", "QUEST_ACCEPTED", "QUEST_REMOVED", "BAG_UPDATE_DELAYED", "GROUP_ROSTER_UPDATE", "ACTIVE_TALENT_GROUP_CHANGED" }) do
		Stoa:On(event, soon)
	end
	Stoa:On("PLAYER_REGEN_ENABLED", function() if self.pending then soon() end end)
	Stoa:On("BAG_UPDATE_COOLDOWN", function() self:Refresh() end)
	Stoa:On("SPELL_UPDATE_COOLDOWN", function() self:Refresh() end)
end
