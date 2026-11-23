-- Stoa QoL: group loot rolls. The game stacks its Need / Greed / Pass cards
-- up from the bottom of the screen, right over the action bars. STOA hangs
-- them from a spot of its own instead ("Loot rolls" in unlock mode), and
-- shows who chose what: under each card while you decide, then, once your
-- own card has gone, a small result card with every choice, the rolls and
-- the winner, which stays a few seconds after the roll ends.
--
-- Everything comes from the game's loot history (C_LootHistory); nothing is
-- read from chat. The game's cards are only moved and given a child frame:
-- their buttons, timer and data are never touched.
local _, ns = ...
local Stoa = ns.Stoa
local UI = Stoa.UI

local Rolls = Stoa:NewModule("Rolls", {})

local call = Stoa.safe.call
local CARD_W, CARD_H = 286, 76
local GAP = 8
local LINE_H = 14
local HOLD = 6       -- seconds a result card stays after the roll ends
local MAX_RESULTS = 3

-- EncounterLootDropRollState: 0 need, 1 off-spec need, 2 transmog, 3 greed,
-- 4 not chosen yet, 5 pass.
local NOT_YET, PASS = 4, 5
local GROUPS = {
	{ states = { [0] = true }, label = "Need", token = "accent" },
	{ states = { [1] = true }, label = "Off-spec", token = "accent" },
	{ states = { [2] = true, [3] = true }, label = "Greed", token = "text" },
	{ states = { [PASS] = true }, label = "Pass", token = "muted" },
}
local WORD = { [0] = "Need", [1] = "Off-spec", [2] = "Transmog", [3] = "Greed", [5] = "Pass" }

local function secret(value) return Stoa:IsSecret(value) end

local function colored(name, class)
	if type(name) ~= "string" or secret(name) then return nil end
	name = name:match("^[^%-]+") or name
	local color = type(class) == "string" and not secret(class) and RAID_CLASS_COLORS[class]
	if color and color.WrapTextInColorCode then return color:WrapTextInColorCode(name) end
	return name
end

local function hex(token)
	local r, g, b = Stoa:Color(token)
	return string.format("|cff%02x%02x%02x", (r or 1) * 255, (g or 1) * 255, (b or 1) * 255)
end

-- Drops we saw while they were still rolling, by "encounter:key". Old
-- history from before this session never shows.
local drops = {}

local function finished(info)
	return info.winner ~= nil or info.allPassed
end

local function plainInfo(info)
	if type(info) ~= "table" or secret(info.itemHyperlink) then return nil end
	if type(info.rollInfos) ~= "table" then return nil end
	return info
end

-- Cards ----------------------------------------------------------------------

local function gamepad()
	return InputUtil and InputUtil.IsGamepadUIEnabled and InputUtil.IsGamepadUIEnabled()
end

-- The drop a game card is showing: same item, still rolling, not already
-- claimed by another card (two of the same item drop often enough).
local function dropFor(frame, taken)
	local link = frame.rollID and call(GetLootRollItemLink, frame.rollID)
	if type(link) ~= "string" or secret(link) then return nil end
	local best
	for id, drop in pairs(drops) do
		if not taken[id] and not drop.ended and drop.info.itemHyperlink == link then
			if not best or drop.seen > drops[best].seen then best = id end
		end
	end
	return best
end

local function chooserLines(info)
	local lines = {}
	for _, group in ipairs(GROUPS) do
		local names = {}
		for _, roll in ipairs(info.rollInfos) do
			if group.states[roll.state] then
				local name = colored(roll.playerName, roll.playerClass)
				if name then table.insert(names, name) end
			end
		end
		if #names > 0 then
			table.insert(lines, hex(group.token) .. group.label .. "|r   " .. table.concat(names, ", "))
		end
	end
	return lines
end

function Rolls:WhoPanel(frame)
	if frame.stoaWho then return frame.stoaWho end
	local panel = CreateFrame("Frame", nil, frame)
	panel:SetPoint("TOPLEFT", frame, "BOTTOMLEFT", 0, 1)
	panel:SetPoint("TOPRIGHT", frame, "BOTTOMRIGHT", 0, 1)
	panel:SetHeight(LINE_H)
	UI.surface(panel, "card", { alpha = 0.96 })
	panel.text = UI.text(panel, "sans", Stoa.typeSize.caption, "text")
	panel.text:SetPoint("TOPLEFT", 12, -5)
	panel.text:SetPoint("TOPRIGHT", -12, -5)
	panel.text:SetSpacing(3)
	panel:Hide()
	frame.stoaWho = panel
	return panel
end

-- Results --------------------------------------------------------------------

local results = {}

function Rolls:ResultCard(i)
	if results[i] then return results[i] end
	local card = CreateFrame("Frame", nil, self.anchor)
	card:SetSize(CARD_W, 40)
	UI.surface(card, "card", { alpha = 0.96 })
	card.icon = card:CreateTexture(nil, "ARTWORK")
	card.icon:SetSize(24, 24)
	card.icon:SetPoint("TOPLEFT", 10, -8)
	card.name = UI.text(card, "serif", Stoa.typeSize.body, "text")
	card.name:SetPoint("LEFT", card.icon, "RIGHT", 8, 0)
	card.name:SetPoint("RIGHT", card, "RIGHT", -110, 0)
	card.name:SetWordWrap(false)
	card.status = UI.text(card, "sans", Stoa.typeSize.caption, "accent", "RIGHT")
	card.status:SetPoint("RIGHT", card, "TOPRIGHT", -10, -20)
	card.list = UI.text(card, "sans", Stoa.typeSize.caption, "text")
	card.list:SetPoint("TOPLEFT", card.icon, "BOTTOMLEFT", 0, -6)
	card.list:SetPoint("RIGHT", card, "RIGHT", -10, 0)
	card.list:SetSpacing(3)
	card:Hide()
	results[i] = card
	return card
end

local function resultLines(info)
	local entries = {}
	for _, roll in ipairs(info.rollInfos) do
		local name = colored(roll.playerName, roll.playerClass)
		if name and roll.state ~= NOT_YET then
			local word = WORD[roll.state] or ""
			local number = type(roll.roll) == "number" and not secret(roll.roll) and (" " .. roll.roll) or ""
			local token = roll.state == PASS and "muted" or (roll.state <= 1 and "accent" or "text")
			table.insert(entries, name .. " " .. hex(token) .. word .. number .. "|r")
		end
	end
	-- Two to a line keeps a raid's worth short.
	local lines = {}
	for i = 1, #entries, 2 do
		table.insert(lines, entries[i] .. (entries[i + 1] and ("     " .. entries[i + 1]) or ""))
	end
	return lines
end

local function statusOf(info)
	if info.allPassed then return hex("muted") .. "Everyone passed|r" end
	local winner = info.winner and colored(info.winner.playerName, info.winner.playerClass)
	if winner then return "Won by " .. winner end
	local waiting = 0
	for _, roll in ipairs(info.rollInfos) do
		if roll.state == NOT_YET then waiting = waiting + 1 end
	end
	if waiting > 0 then return hex("muted") .. waiting .. " still choosing|r" end
	return ""
end

local function fillResult(card, drop)
	local info = drop.info
	local icon = call(C_Item and C_Item.GetItemIconByID, info.itemHyperlink)
	card.icon:SetTexture(icon or 134400)
	local _, _, quality = call(C_Item and C_Item.GetItemInfo, info.itemHyperlink)
	card.name:SetText(info.itemHyperlink:match("%[(.-)%]") or "")
	local color = quality and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[quality]
	if color then card.name:SetTextColor(color.r, color.g, color.b) else UI.paint(card.name, "text") end
	card.status:SetText(statusOf(info))
	local lines = resultLines(info)
	card.list:SetText(table.concat(lines, "\n"))
	card:SetHeight(40 + #lines * LINE_H + (#lines > 0 and 4 or 0))
end

-- Layout ---------------------------------------------------------------------

-- Places the game's cards and STOA's result cards up from the anchor. Runs
-- after the game lays out its own cards, and when the history changes.
function Rolls:Layout()
	if gamepad() then return end
	local container = _G.GroupLootContainer
	local frames = container and container.rollFrames
	local taken, y = {}, 0
	if type(frames) == "table" then
		for i = 1, (container.maxIndex or 0) do
			local frame = frames[i]
			if frame and frame.IsShown and frame:IsShown() then
				local id = dropFor(frame, taken)
				local panel = self:WhoPanel(frame)
				local lines = id and chooserLines(drops[id].info) or {}
				local extra = 0
				if #lines > 0 then
					taken[id] = true
					panel.text:SetText(table.concat(lines, "\n"))
					extra = 10 + #lines * LINE_H
					panel:SetHeight(extra)
					panel:Show()
				else
					if id then taken[id] = true end
					panel:Hide()
				end
				frame:ClearAllPoints()
				frame:SetPoint("BOTTOM", self.anchor, "BOTTOM", 0, y + extra)
				y = y + extra + (frame:GetHeight() or CARD_H) + GAP
			end
		end
	end

	-- Drops your own card has left: still rolling, or ended a moment ago.
	local now, shown = GetTime(), {}
	for id, drop in pairs(drops) do
		if not taken[id] and (not drop.ended or now - drop.ended < HOLD) then
			table.insert(shown, drop)
		end
	end
	table.sort(shown, function(a, b) return a.seen < b.seen end)
	local first = math.max(1, #shown - MAX_RESULTS + 1)
	for i = 1, MAX_RESULTS do
		local card, drop = results[i], shown[first + i - 1]
		if drop then
			card = self:ResultCard(i)
			fillResult(card, drop)
			card:ClearAllPoints()
			card:SetPoint("BOTTOM", self.anchor, "BOTTOM", 0, y)
			y = y + card:GetHeight() + GAP
			if not card:IsShown() then
				card:Show()
				if UI.fadeIn then UI.fadeIn(card) end
			end
		elseif card then
			card:Hide()
		end
	end
end

function Rolls:OnDrop(encounterID, key)
	if secret(encounterID) or secret(key) then return end
	local info = plainInfo(call(C_LootHistory.GetSortedInfoForDrop, encounterID, key))
	if not info then return end
	local id = encounterID .. ":" .. key
	local drop = drops[id]
	if not drop then
		-- Only drops we see rolling: an ended one is old history.
		if finished(info) then return end
		drop = { seen = GetTime() }
		drops[id] = drop
	end
	drop.info = info
	if finished(info) and not drop.ended then
		drop.ended = GetTime()
		C_Timer.After(HOLD + 0.1, function()
			drops[id] = nil
			self:Layout()
		end)
	end
	self:Layout()
end

-- Default spot: right of the middle of the screen, clear of the bars, the
-- Halo and the party cards.
function Rolls:Place()
	self.anchor:ClearAllPoints()
	self.anchor:SetPoint("BOTTOM", UIParent, "CENTER", 380, -120)
end

function Rolls:OnEnable()
	if not (C_LootHistory and C_LootHistory.GetSortedInfoForDrop) then return end
	local anchor = CreateFrame("Frame", "StoaRollsAnchor", UIParent)
	anchor:SetSize(CARD_W, CARD_H)
	self.anchor = anchor
	self:Place()
	Stoa:RegisterMover("lootRolls", anchor, "Loot rolls", { default = function() self:Place() end })

	if type(_G.GroupLootContainer_Update) == "function" then
		hooksecurefunc("GroupLootContainer_Update", function()
			xpcall(self.Layout, Stoa.catch, self)
		end)
	end
	Stoa:On("LOOT_HISTORY_UPDATE_DROP", function(encounterID, key) self:OnDrop(encounterID, key) end)
	Stoa:On("LOOT_HISTORY_CLEAR_HISTORY", function()
		wipe(drops)
		self:Layout()
	end)
	-- Names can be hidden in combat; fill them in once it ends.
	Stoa:On("PLAYER_REGEN_ENABLED", function() self:Layout() end)
end

-- /stoa rolls: a sample result card, to see and place it.
Stoa.commands.rolls = function()
	if not Rolls.anchor then return end
	local me, class = UnitName("player"), select(2, UnitClass("player"))
	drops["sample"] = {
		seen = GetTime(), ended = GetTime(),
		info = {
			itemHyperlink = "|cff0070dd|Hitem:6948::::::::1:::::::::|h[Sample loot]|h|r",
			winner = { playerName = me, playerClass = class },
			rollInfos = {
				{ playerName = me, playerClass = class, state = 0, roll = 74 },
				{ playerName = "Moria", playerClass = "PALADIN", state = 3, roll = 88 },
				{ playerName = "Isel", playerClass = "MAGE", state = 3, roll = 12 },
				{ playerName = "Vex", playerClass = "WARLOCK", state = PASS },
			},
		},
	}
	C_Timer.After(HOLD + 0.1, function()
		drops["sample"] = nil
		Rolls:Layout()
	end)
	Rolls:Layout()
end
