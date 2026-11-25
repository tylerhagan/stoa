-- Stoa QoL: full bags. When the game says "Inventory is full", a small card
-- names the two or three least valuable stacks you carry, by what a vendor
-- pays, and one click on a row destroys that stack to make room.
--
-- Offered, in order: grey junk, then what you marked as junk, then other
-- white items with a price. Never a quest item, gear that isn't junk,
-- anything you keep in Restock, or anything a vendor won't buy. Grey goes
-- on one click; anything else turns red and asks for a second.
--
-- With the loot window open, the card also weighs what is left in it: a
-- quest item is named, and loot worth less than your cheapest stack is
-- called not worth the room.
--
-- STOA destroys only on a click of yours, and only the item it showed:
-- the slot is read again and the cursor checked before anything is deleted.
-- Nothing here runs until the game's own "Inventory is full" line.
local _, ns = ...
local Stoa = ns.Stoa
local UI = Stoa.UI

local FullBags = Stoa:NewModule("FullBags", {})

local call = Stoa.safe.call
local WIDTH, PAD = 262, 12
local ROW_H = 30
local MAX_ROWS = 3
local ALONE_SECONDS = 15   -- the card's life with no loot window open
local AFTER_LOOT = 6       -- and after the loot window closes
local DONE_SECONDS = 2.5   -- once there is room again
local POOR, COMMON = 0, 1
local QUEST_CLASS = 12

local Items

-- Candidates ---------------------------------------------------------------

local function isQuestItem(bag, slot, id, name, classID)
	if classID == QUEST_CLASS then return true end
	local quest = C_Container.GetContainerItemQuestInfo and call(C_Container.GetContainerItemQuestInfo, bag, slot)
	if type(quest) == "table" and (quest.isQuestItem or quest.questID) then return true end
	return Items.questNeeds(id, name) and true or false
end

-- The stacks that may go, least valuable first within grey, marked, white.
local function candidates()
	local list = {}
	local keep = Stoa.Restock and Stoa.Restock.list and Stoa.Restock.list() or {}
	Items.eachBagSlot(function(bag, slot, info)
		local id = info.itemID
		if not id or info.isLocked or info.hasNoValue then return end
		local quality, price, equipLoc, classID = Items.info(id)
		if not quality or price <= 0 then return end
		local marked = Items.isMarkedJunk(id)
		local tier = quality == POOR and 1 or marked and 2 or quality == COMMON and 3 or nil
		if not tier or keep[id] then return end
		-- Gear goes only as junk: a white sword may be the one you swing.
		if tier == 3 and type(equipLoc) == "string" and equipLoc ~= "" and equipLoc ~= "INVTYPE_NON_EQUIP_IGNORE" then return end
		if isQuestItem(bag, slot, id, info.itemName, classID) then return end
		local count = Stoa:PlainNumber(info.stackCount) or 1
		list[#list + 1] = { bag = bag, slot = slot, id = id, name = info.itemName, icon = info.iconFileID,
			count = count, value = price * count, quality = quality, tier = tier }
	end)
	table.sort(list, function(a, b)
		if a.tier ~= b.tier then return a.tier < b.tier end
		if a.value ~= b.value then return a.value < b.value end
		if a.bag ~= b.bag then return a.bag < b.bag end
		return a.slot < b.slot
	end)
	return list
end

-- What is left in the loot window: a quest item's name if there is one,
-- else the most valuable thing and its worth (nil when it can't be told).
local function lootLeft()
	if not (GetNumLootItems and GetLootSlotInfo and GetLootSlotLink) then return nil end
	local best, bestValue
	for slot = 1, Stoa:PlainNumber(call(GetNumLootItems)) or 0 do
		local _, name, quantity, _, _, _, isQuestItem = call(GetLootSlotInfo, slot)
		local link = call(GetLootSlotLink, slot)
		if type(name) == "string" and not Stoa:IsSecret(name) and type(link) == "string" then
			if isQuestItem or Items.questNeeds(link, name) then return name, nil, true end
			local _, price, _, classID = Items.info(link)
			if classID == QUEST_CLASS then return name, nil, true end
			-- A price not loaded yet: say nothing rather than guess.
			if not price then return nil end
			local value = price * (Stoa:PlainNumber(quantity) or 1)
			if not bestValue or value > bestValue then best, bestValue = name, value end
		end
	end
	return best, bestValue, false
end

local function freeSlots()
	local free = 0
	for bag = 0, NUM_BAG_SLOTS or 4 do
		local n, family = call(C_Container.GetContainerNumFreeSlots, bag)
		-- A quiver or soul bag's room is no use to loot.
		if (Stoa:PlainNumber(family) or 0) == 0 then free = free + (Stoa:PlainNumber(n) or 0) end
	end
	return free
end

local function qualityColour(quality)
	if C_Item and C_Item.GetItemQualityColor then
		local ok, r, g, b = pcall(C_Item.GetItemQualityColor, quality)
		if ok and type(r) == "number" then return r, g, b end
	end
	return Stoa:Color("text")
end

local function stackName(c)
	return c.count > 1 and ("%s x%d"):format(c.name or "?", c.count) or (c.name or "?")
end

-- Destroying ---------------------------------------------------------------

-- Only ever from a row's click. The slot is read again, and the cursor
-- must hold that very item, or nothing is deleted.
local function destroy(c)
	if not (C_Container.PickupContainerItem and DeleteCursorItem and GetCursorInfo and ClearCursor) then return false end
	local info = call(C_Container.GetContainerItemInfo, c.bag, c.slot)
	if type(info) ~= "table" or info.itemID ~= c.id or info.isLocked then return false end
	ClearCursor()
	if GetCursorInfo() then return false end
	C_Container.PickupContainerItem(c.bag, c.slot)
	local kind, id = GetCursorInfo()
	if kind == "item" and id == c.id then
		DeleteCursorItem()
		return GetCursorInfo() == nil
	end
	ClearCursor()
	return false
end

-- The card -----------------------------------------------------------------

function FullBags:Build()
	local card = CreateFrame("Frame", "StoaFullBags", UIParent)
	card:SetFrameStrata("DIALOG")
	card:SetClampedToScreen(true)
	card:EnableMouse(true)
	card:SetWidth(WIDTH)
	UI.roundPanel(card, 0.98)
	card:Hide()
	card.rise = UI.intro(card, 0, 4, UI.MOTION.quick)
	card:HookScript("OnShow", function(own) own.rise:Play() end)
	-- A right-click anywhere on it puts it away.
	card:SetScript("OnMouseUp", function(_, button) if button == "RightButton" then self:Hide() end end)

	card.cap = UI.caption(card, "Bags full")
	card.cap:SetPoint("TOPLEFT", PAD, -10)
	UI.paint(card.cap, "danger")
	card.head = UI.text(card, "sans", Stoa.typeSize.body, "muted")
	card.head:SetPoint("TOPLEFT", card.cap, "BOTTOMLEFT", 0, -4)
	card.head:SetWidth(WIDTH - PAD * 2)
	card.head:SetJustifyH("LEFT")
	card.head:SetWordWrap(true)
	card.head:SetSpacing(2)
	card.rule = UI.line(card)
	card.foot = UI.text(card, "sans", Stoa.typeSize.caption, "muted")
	card.foot:SetWidth(WIDTH - PAD * 2)
	card.foot:SetJustifyH("LEFT")
	card.foot:SetWordWrap(true)

	card.rows = {}
	for i = 1, MAX_ROWS do
		local row = CreateFrame("Button", nil, card)
		row:SetHeight(ROW_H)
		row.glow = row:CreateTexture(nil, "BACKGROUND")
		row.glow:SetTexture(UI.WHITE)
		row.glow:SetAllPoints()
		row.glow:Hide()
		row.icon = row:CreateTexture(nil, "ARTWORK")
		row.icon:SetSize(20, 20)
		row.icon:SetPoint("LEFT", PAD, 0)
		row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
		row.word = UI.caption(row, "Destroy")
		row.word:SetPoint("RIGHT", -PAD, 0)
		row.value = UI.text(row, "sans", Stoa.typeSize.body, "muted", "RIGHT")
		row.value:SetPoint("RIGHT", row.word, "LEFT", -8, 0)
		row.name = UI.text(row, "sans", Stoa.typeSize.body, "text")
		row.name:SetPoint("LEFT", row.icon, "RIGHT", 8, 0)
		row.name:SetPoint("RIGHT", row.value, "LEFT", -8, 0)
		row.name:SetJustifyH("LEFT")
		row.name:SetWordWrap(false)
		row:SetScript("OnEnter", function(own)
			own.over = true
			self:PaintRow(own)
			local c = own.candidate
			if c and GameTooltip and GameTooltip.SetBagItem then
				GameTooltip:SetOwner(own, "ANCHOR_RIGHT")
				pcall(GameTooltip.SetBagItem, GameTooltip, c.bag, c.slot)
				GameTooltip:Show()
			end
		end)
		row:SetScript("OnLeave", function(own)
			-- Moving away takes back a first click.
			own.over, own.asked = nil, nil
			self:PaintRow(own)
			if self.asking == own then self.asking = nil; self:Say() end
			GameTooltip:Hide()
		end)
		row:SetScript("OnClick", function(own, button)
			if button == "RightButton" then self:Hide() return end
			xpcall(self.Click, Stoa.catch, self, own)
		end)
		row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
		card.rows[i] = row
	end
	self.card = card
end

function FullBags:PaintRow(row)
	local c = row.candidate
	if not c then return end
	row.glow:SetShown(row.over or row.asked)
	if row.asked then
		row.glow:SetVertexColor(Stoa:Color("hostile"))
		row.glow:SetAlpha(0.18)
		row.word:SetText("CLICK AGAIN")
		UI.paint(row.word, "hostile")
	else
		local r, g, b = Stoa:Color("text")
		row.glow:SetVertexColor(r, g, b, 0.07)
		row.word:SetText("DESTROY")
		UI.paint(row.word, row.over and "hostile" or "muted")
	end
end

-- The quiet line at the foot: what just happened, or how the list is made.
function FullBags:Say(text, token)
	local foot = self.card.foot
	foot:SetText(text or (self.asking and "Not junk, so it asks once. Move the mouse away to cancel.") or "Ranked by what a vendor pays for the stack.")
	UI.paint(foot, token or "muted")
end

function FullBags:Click(row)
	local c = row.candidate
	if not c then return end
	if c.quality ~= POOR and not row.asked then
		row.asked = true
		self.asking = row
		self:PaintRow(row)
		self:Say()
		self:Fit()
		return
	end
	row.asked, self.asking = nil, nil
	if self.preview then
		self.said = "A preview: nothing was destroyed."
	elseif destroy(c) then
		self.said = stackName(c) .. " destroyed."
	else
		self.said = "The game wouldn't let that one go."
	end
	GameTooltip:Hide()
	-- The bags' own update brings the fresh list; this covers a refusal.
	self:Refresh()
end

-- Lays the card out from what it holds, and stands it by the loot window.
function FullBags:Fit()
	local card = self.card
	local y = -10 - (tonumber(card.cap:GetStringHeight()) or 10) - 4 - (tonumber(card.head:GetStringHeight()) or 14) - 9
	local shown = 0
	for _, row in ipairs(card.rows) do
		if row:IsShown() then
			if shown == 0 then
				card.rule:ClearAllPoints()
				card.rule:SetPoint("TOPLEFT", 1, y)
				card.rule:SetPoint("TOPRIGHT", -1, y)
			end
			row:ClearAllPoints()
			row:SetPoint("TOPLEFT", 1, y)
			row:SetPoint("TOPRIGHT", -1, y)
			y = y - ROW_H
			shown = shown + 1
		end
	end
	card.rule:SetShown(shown > 0)
	card.foot:ClearAllPoints()
	card.foot:SetPoint("TOPLEFT", PAD, y - (shown > 0 and 7 or 0))
	local footH = card.foot:GetText() ~= "" and (tonumber(card.foot:GetStringHeight()) or 12) + (shown > 0 and 7 or 0) or 0
	card:SetHeight(-y + footH + 11)
end

function FullBags:Place()
	local card = self.card
	card:ClearAllPoints()
	local loot = LootFrame
	if self.looting and loot and loot.IsShown and loot:IsShown() then
		card:SetPoint("TOPLEFT", loot, "TOPRIGHT", 8, 0)
	elseif self.at then
		card:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", self.at[1] + 24, self.at[2] + 40)
	else
		card:SetPoint("CENTER", UIParent, "CENTER", 260, 0)
	end
end

function FullBags:Refresh()
	local card = self.card
	if not card then return end
	local list = candidates()
	-- The preview shows the list whether or not the bags are full.
	local free = self.preview and 0 or freeSlots()
	local name, value, quest
	if self.looting then name, value, quest = lootLeft() end

	local head
	if free > 0 then
		head = free == 1 and "Room for one more now." or ("%d slots free now."):format(free)
	elseif #list == 0 then
		head = "Nothing here is safe to destroy. STOA won't offer quest items, gear or what you keep in Restock; open your bags to choose yourself."
	elseif quest and name then
		head = ("You need |cffffffff%s|r for a quest."):format(name)
	elseif name and value and value < list[1].value then
		head = ("Not worth making room for. |cffffffff%s|r sells for %s; your cheapest, |cffffffff%s|r, for %s."):format(name, Stoa:Money(value), stackName(list[1]), Stoa:Money(list[1].value))
	else
		head = "Destroy the least valuable to make room."
	end
	card.head:SetText(head)

	for i, row in ipairs(card.rows) do
		local c = free == 0 and list[i] or nil
		row.candidate = c
		row.asked = nil
		row:SetShown(c ~= nil)
		if c then
			row.icon:SetTexture(c.icon)
			row.name:SetText(stackName(c))
			row.name:SetTextColor(qualityColour(c.quality))
			row.value:SetText(Stoa:Money(c.value))
			self:PaintRow(row)
		end
	end
	self.asking = nil
	if free > 0 or #list == 0 then
		self:Say(self.said or "", self.said and "accent" or "muted")
	else
		self:Say(self.said, self.said and "accent" or nil)
	end
	self:Fit()
	if free > 0 then self:Expire(DONE_SECONDS) end
end

-- Puts the card away after a while, unless the mouse is on it.
function FullBags:Expire(seconds)
	self.token = (self.token or 0) + 1
	local token = self.token
	if not seconds then return end
	C_Timer.After(seconds, function()
		if token ~= self.token or not self.card:IsShown() then return end
		if self.card:IsMouseOver() then self:Expire(2) return end
		self:Hide()
	end)
end

function FullBags:Hide()
	self.token = (self.token or 0) + 1
	self.said, self.asking, self.preview = nil, nil, nil
	if self.card then self.card:Hide() end
	GameTooltip:Hide()
end

function FullBags:Show()
	if not self.card then self:Build() end
	local card = self.card
	if not card:IsShown() then
		self.said = nil
		local x, y = GetCursorPosition()
		local scale = UIParent:GetEffectiveScale()
		x, y = Stoa:PlainNumber(x), Stoa:PlainNumber(y)
		self.at = x and y and scale and scale > 0 and { x / scale, y / scale } or nil
	end
	self:Refresh()
	self:Place()
	card:Show()
	-- By the loot window it stays while that is open; alone, for a while.
	self:Expire(not self.looting and ALONE_SECONDS or nil)
end

function FullBags:OnEnable()
	Items = Stoa.Items
	if not (Items and C_Container and C_Container.GetContainerNumFreeSlots and C_Container.PickupContainerItem and DeleteCursorItem) then return end
	Stoa:On("UI_ERROR_MESSAGE", function(_, message)
		if type(message) ~= "string" or Stoa:IsSecret(message) or message ~= ERR_INV_FULL then return end
		-- A failed pick-up says it once a slot: one card for the burst.
		if self.queued then return end
		self.queued = true
		C_Timer.After(0.05, function()
			self.queued = false
			self.preview = nil
			xpcall(self.Show, Stoa.catch, self)
		end)
	end)
	Stoa:On("LOOT_OPENED", function() self.looting = true end)
	Stoa:On("LOOT_CLOSED", function()
		self.looting = false
		if self.card and self.card:IsShown() then self:Expire(AFTER_LOOT) end
	end)
	local function changed()
		if self.card and self.card:IsShown() then xpcall(self.Refresh, Stoa.catch, self) end
	end
	Stoa:On("BAG_UPDATE_DELAYED", changed)
	Stoa:On("LOOT_SLOT_CLEARED", changed)
end

-- /stoa fullbags: the card as it would show now, to see it without filling up.
Stoa.commands.fullbags = function()
	if not Items then Stoa:Print("The full bags card is off: Settings > Comforts.") return end
	FullBags.preview = true
	FullBags:Show()
end
