-- Stoa QoL: the dungeon companion. Inside a five-player dungeon, out of a
-- fight, a quiet card says where you are in it: the bosses (ticked off as
-- they fall), your quests for it, and the loot in it that would be an
-- upgrade for you. It takes the quest list's place while it shows (the list
-- folds to its header, as in a fight) and folds away itself in a fight.
-- A switch turns it into one slim line over the console instead.
--
-- Bosses and loot come from the game's own Adventure Guide data, so nothing
-- here needs updating when the game adds or changes a dungeon. Quests are
-- the ones under the dungeon's name in your quest log.
local _, ns = ...
local Stoa = ns.Stoa
local UI = Stoa.UI

local Companion = Stoa:NewModule("Companion", {
	enabled = true,
	-- "card" or "line".
	view = "card",
})

local call = Stoa.safe.call
local WIDTH = 300
local PAD = 16
local ROW = 18
local MAX_LOOT = 3
-- A run is forgotten when you come back to the dungeon after this long.
local RUN_GAP = 2 * 3600

local function plain(value) return Stoa:PlainNumber(value) end

-- Data -------------------------------------------------------------------------

-- The dungeon you are in, or nil: its name, map, Adventure Guide id.
function Companion:Where()
	local inside, kind = IsInInstance()
	if not inside or kind ~= "party" then return nil end
	local name, _, _, _, _, _, _, instanceID = GetInstanceInfo()
	if not name or Stoa:IsSecret(name) then return nil end
	local mapID = C_Map and C_Map.GetBestMapForUnit and call(C_Map.GetBestMapForUnit, "player")
	local lookup = EJ_GetInstanceForMap or (C_EncounterJournal and C_EncounterJournal.GetInstanceForGameMap)
	local journal = mapID and plain(call(lookup, mapID))
	if journal == 0 then journal = nil end
	return { name = name, instanceID = instanceID, mapID = mapID, journal = journal }
end

-- The run: which bosses fell, kept over a /reload.
function Companion:Run(where)
	local run = self.db.run
	local now = time()
	if not run or run.instanceID ~= where.instanceID or (now - (run.seen or 0)) > RUN_GAP then
		run = { instanceID = where.instanceID, killed = {} }
		self.db.run = run
	end
	run.seen = now
	return run
end

-- The Adventure Guide is read only while its window is closed: choosing a
-- dungeon there would change the page someone is reading.
local function guideFree()
	local guide = _G.EncounterJournal
	return not (guide and guide.IsShown and guide:IsShown())
end

-- The game's own bosses for the dungeon, in the guide's order. Where the
-- client lacks the guide's list, the bosses pinned on the dungeon's map
-- stand in.
function Companion:Bosses(where)
	local list = {}
	if not where.journal or not guideFree() then return list end
	if EJ_GetEncounterInfoByIndex then
		if EJ_SelectInstance then call(EJ_SelectInstance, where.journal) end
		for i = 1, 20 do
			local name, _, _, _, _, _, dungeonEncounterID = call(EJ_GetEncounterInfoByIndex, i, where.journal)
			if not name then break end
			list[#list + 1] = { name = name, id = dungeonEncounterID }
		end
	end
	local onMap = C_EncounterJournal and C_EncounterJournal.GetEncountersOnMap
	if #list == 0 and onMap and EJ_GetEncounterInfo and where.mapID then
		for _, pin in ipairs(call(onMap, where.mapID) or {}) do
			local name, _, _, _, _, _, dungeonEncounterID = call(EJ_GetEncounterInfo, pin.encounterID)
			if name then list[#list + 1] = { name = name, id = dungeonEncounterID } end
		end
	end
	return list
end

-- The quests under the dungeon's name in your log.
function Companion:Quests(where)
	local list = {}
	local log = C_QuestLog
	if not (log and log.GetNumQuestLogEntries and log.GetInfo) then return list end
	local count = plain(call(log.GetNumQuestLogEntries)) or 0
	local under = false
	for i = 1, count do
		local info = call(log.GetInfo, i)
		if type(info) == "table" then
			if info.isHeader then
				under = info.title == where.name
			elseif under and info.questID then
				local done = call(log.IsComplete, info.questID) and true or false
				local progress
				if not done and log.GetQuestObjectives then
					for _, goal in ipairs(call(log.GetQuestObjectives, info.questID) or {}) do
						if not goal.finished then
							local have, need = plain(goal.numFulfilled), plain(goal.numRequired)
							if have and need and need > 1 then progress = ("%d / %d"):format(have, need) end
							break
						end
					end
				end
				list[#list + 1] = { name = info.title, done = done, progress = progress }
			end
		end
	end
	return list
end

-- Loot in the dungeon that would be an upgrade for you, best first.
function Companion:Loot(where)
	local list = {}
	local get = C_EncounterJournal and C_EncounterJournal.GetLootInfoByIndex
	if not (where.journal and get and EJ_GetNumLoot and EJ_SelectInstance) or not guideFree() then return list end
	if EJ_SelectInstance then call(EJ_SelectInstance, where.journal) end
	if EJ_SetLootFilter then
		local _, _, classID = UnitClass("player")
		call(EJ_SetLootFilter, classID or 0, 0)
	end
	for i = 1, plain(call(EJ_GetNumLoot)) or 0 do
		local item = call(get, i)
		local link = type(item) == "table" and item.link
		if link and not Stoa:IsSecret(link) then
			local gain = Stoa.Items.upgrade(link)
			if gain and gain > 0 then
				list[#list + 1] = { link = link, gain = gain }
			end
		end
	end
	-- The guide's own filter goes back to how it was for when you open it.
	if EJ_ResetLootFilter then call(EJ_ResetLootFilter) end
	table.sort(list, function(a, b) return a.gain > b.gain end)
	while #list > MAX_LOOT do table.remove(list) end
	return list
end

function Companion:Gather()
	local where = self:Where()
	if not where then return nil end
	local run = self:Run(where)
	-- The guide's lists are read once per dungeon; the loot again when your
	-- gear changes or the game sends more item data.
	local cache = self.cache
	if not cache or cache.journal ~= where.journal or cache.name ~= where.name then
		cache = { journal = where.journal, name = where.name }
		self.cache = cache
	end
	if not cache.bosses or #cache.bosses == 0 then cache.bosses = self:Bosses(where) end
	if not cache.loot then cache.loot = self:Loot(where) end
	local bosses = {}
	for i, boss in ipairs(cache.bosses) do bosses[i] = { name = boss.name, id = boss.id } end
	local down = 0
	local nextBoss
	for _, boss in ipairs(bosses) do
		boss.dead = boss.id and run.killed[boss.id] or false
		if boss.dead then down = down + 1 elseif not nextBoss then nextBoss = boss end
	end
	if nextBoss then nextBoss.next = true end
	local quests = self:Quests(where)
	local questsDone = 0
	for _, quest in ipairs(quests) do if quest.done then questsDone = questsDone + 1 end end
	local map = Stoa.modules.Map
	return {
		where = where,
		levels = map and map.Levels and map:Levels(where.name, where.mapID),
		bosses = bosses, down = down, nextBoss = nextBoss,
		quests = quests, questsDone = questsDone,
		loot = cache.loot,
	}
end

-- The card ---------------------------------------------------------------------

local function line(parent)
	local left = UI.text(parent, "sans", Stoa.typeSize.body, "text", "LEFT")
	local right = UI.text(parent, "sans", Stoa.typeSize.body, "muted", "RIGHT")
	left:SetWordWrap(false)
	right:SetWordWrap(false)
	return { left = left, right = right }
end

function Companion:BuildCard()
	local card = CreateFrame("Frame", "StoaCompanion", UIParent)
	card:SetSize(WIDTH, 120)
	card:SetFrameStrata("MEDIUM")
	card:Hide()
	UI.roundPanel(card, 0.94)

	local title = UI.text(card, "serif", Stoa.typeSize.name, "text", "LEFT")
	title:SetPoint("TOPLEFT", PAD, -PAD + 2)
	title:SetPoint("RIGHT", card, "RIGHT", -PAD - 70, 0)
	title:SetWordWrap(false)
	local levels = UI.text(card, "sans", Stoa.typeSize.caption, "muted", "RIGHT")
	levels:SetPoint("RIGHT", card, "TOPRIGHT", -PAD - 22, -PAD - 6)
	local sub = UI.text(card, "sans", Stoa.typeSize.caption, "muted", "LEFT")
	sub:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -4)

	-- Folds the card to the slim line.
	local fold = CreateFrame("Button", nil, card)
	fold:SetSize(18, 18)
	fold:SetPoint("TOPRIGHT", -8, -10)
	local glyph = UI.glyph(fold, "Minus", 12, "muted")
	glyph:SetPoint("CENTER")
	fold:SetScript("OnClick", function() self:SetView("line") end)
	fold:SetScript("OnEnter", function(button)
		glyph:SetVertexColor(Stoa:Color("accent"))
		GameTooltip:SetOwner(button, "ANCHOR_LEFT")
		GameTooltip:SetText("Make it one line")
		GameTooltip:Show()
	end)
	fold:SetScript("OnLeave", function()
		glyph:SetVertexColor(Stoa:Color("muted"))
		GameTooltip:Hide()
	end)

	local rule = card:CreateTexture(nil, "BORDER")
	UI.pixel(rule, "height")
	UI.paint(rule, "hairline")
	rule:SetPoint("TOPLEFT", sub, "BOTTOMLEFT", -PAD, -10)
	rule:SetPoint("RIGHT", card, "RIGHT")

	card.title, card.levels, card.sub, card.rule = title, levels, sub, rule
	card.heads, card.lines = {}, {}
	self.card = card
	Stoa:RegisterMover("companion", card, "Dungeon companion", { default = function() self:PlaceCard() end })
	self:PlaceCard()
end

-- Where the quest list starts, under the minimap, unless moved.
function Companion:PlaceCard()
	if Stoa:HasSavedPosition("companion") or InCombatLockdown() then return end
	local card = self.card
	card:ClearAllPoints()
	local tracker = _G.ObjectiveTrackerFrame
	local header = tracker and tracker.Header
	if header and not (tracker.IsForbidden and tracker:IsForbidden()) then
		card:SetPoint("TOPRIGHT", header, "BOTTOMRIGHT", 0, -6)
	else
		card:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", -24, -260)
	end
end

local function sectionHead(card, index, words)
	local head = card.heads[index]
	if not head then
		head = UI.text(card, "sans", Stoa.typeSize.caption, "accent", "LEFT")
		card.heads[index] = head
	end
	head:SetText(words:upper())
	return head
end

function Companion:FillCard(data)
	local card = self.card
	card.title:SetText(data.where.name)
	card.levels:SetText(data.levels and data.levels:gsub("^Level ", "") or "")
	local bits = {}
	if #data.bosses > 0 then bits[#bits + 1] = ("%d of %d bosses"):format(data.down, #data.bosses) end
	if #data.quests > 0 then bits[#bits + 1] = ("%d of %d quests done"):format(data.questsDone, #data.quests) end
	card.sub:SetText(UI.join(bits))

	for _, head in ipairs(card.heads) do head:Hide() end
	for _, row in ipairs(card.lines) do row.left:Hide() row.right:Hide() end
	local y = -(PAD + 46)
	local heads, rows = 0, 0
	local function head(words)
		heads = heads + 1
		local fs = sectionHead(card, heads, words)
		fs:ClearAllPoints()
		fs:SetPoint("TOPLEFT", PAD, y - 6)
		fs:Show()
		y = y - 6 - ROW
	end
	local function row(left, right, state)
		rows = rows + 1
		local r = card.lines[rows]
		if not r then
			r = line(card)
			card.lines[rows] = r
		end
		r.left:ClearAllPoints()
		r.left:SetPoint("TOPLEFT", PAD, y)
		r.left:SetPoint("RIGHT", card, "RIGHT", -PAD - 110, 0)
		r.right:ClearAllPoints()
		r.right:SetPoint("TOPRIGHT", -PAD, y)
		r.left:SetText(left)
		r.right:SetText(right or "")
		local token = state == "done" and "muted" or "text"
		r.left:SetTextColor(Stoa:Color(token))
		r.right:SetTextColor(Stoa:Color(state == "next" and "accent" or "muted"))
		r.left:SetAlpha(state == "done" and 0.6 or 1)
		r.left:Show()
		r.right:Show()
		y = y - ROW
	end

	if #data.bosses > 0 then
		head("Bosses")
		for _, boss in ipairs(data.bosses) do
			row(boss.name, boss.dead and "done" or (boss.next and "next") or "", boss.dead and "done" or (boss.next and "next"))
		end
	end
	if #data.quests > 0 then
		head("Your quests here")
		for _, quest in ipairs(data.quests) do
			row(quest.name, quest.done and "done" or quest.progress, quest.done and "done")
		end
	end
	if #data.loot > 0 then
		head("Worth a roll for you")
		for _, item in ipairs(data.loot) do
			row(item.link, ("+%d%%"):format(math.floor(item.gain + 0.5)))
		end
	end
	card:SetHeight(-y + PAD - 4)
end

-- The line ---------------------------------------------------------------------

local DOT = 8

function Companion:BuildLine()
	local bar = CreateFrame("Button", "StoaCompanionLine", UIParent)
	bar:SetHeight(30)
	bar:SetFrameStrata("MEDIUM")
	bar:Hide()
	UI.roundPanel(bar, 0.94)
	local name = UI.text(bar, "serif", Stoa.typeSize.label, "text", "LEFT")
	name:SetPoint("LEFT", PAD, 0)
	local rest = UI.text(bar, "sans", Stoa.typeSize.body, "muted", "LEFT")
	bar.name, bar.rest, bar.dots = name, rest, {}
	bar:SetScript("OnClick", function() self:SetView("card") end)
	bar:SetScript("OnEnter", function(button)
		local data = self.data
		GameTooltip:SetOwner(button, "ANCHOR_TOP")
		GameTooltip:SetText(data and data.where.name or "Dungeon companion")
		for _, item in ipairs(data and data.loot or {}) do
			GameTooltip:AddDoubleLine(item.link, ("+%d%%"):format(math.floor(item.gain + 0.5)), 1, 1, 1, 0.6, 0.6, 0.6)
		end
		GameTooltip:AddLine("Click for the full card.", 0.6, 0.6, 0.6)
		GameTooltip:Show()
	end)
	bar:SetScript("OnLeave", function() GameTooltip:Hide() end)
	self.bar = bar
	self:PlaceLine()
end

-- Centred just above the console (or the bottom of the screen).
function Companion:PlaceLine()
	if InCombatLockdown() then return end
	local bar = self.bar
	bar:ClearAllPoints()
	local console = _G.StoaConsole
	if console and console:IsShown() then
		bar:SetPoint("BOTTOM", console, "TOP", 0, 8)
	else
		bar:SetPoint("BOTTOM", UIParent, "BOTTOM", 0, 140)
	end
end

function Companion:FillLine(data)
	local bar = self.bar
	bar.name:SetText(data.where.name)
	local x = PAD + math.ceil(bar.name:GetStringWidth()) + 14
	for _, dot in ipairs(bar.dots) do dot:Hide() end
	for i, boss in ipairs(data.bosses) do
		local dot = bar.dots[i]
		if not dot then
			dot = bar:CreateTexture(nil, "ARTWORK")
			dot:SetTexture(UI.MEDIA .. "Textures\\GlyphDot")
			bar.dots[i] = dot
		end
		local size = boss.next and DOT + 2 or DOT
		dot:SetSize(size, size)
		dot:ClearAllPoints()
		dot:SetPoint("LEFT", bar, "LEFT", x, 0)
		dot:SetVertexColor(Stoa:Color(boss.next and "accent" or "muted"))
		dot:SetAlpha(boss.dead and 0.5 or (boss.next and 1 or 0.9))
		dot:Show()
		x = x + size + 5
	end
	local bits = {}
	if data.nextBoss then bits[#bits + 1] = "Next " .. Stoa:Hex("accent") .. data.nextBoss.name .. "|r" end
	if #data.quests > 0 then bits[#bits + 1] = ("Quests %d / %d"):format(data.questsDone, #data.quests) end
	if #data.loot > 0 then bits[#bits + 1] = #data.loot == 1 and "1 upgrade here" or (#data.loot .. " upgrades here") end
	bar.rest:ClearAllPoints()
	bar.rest:SetPoint("LEFT", bar, "LEFT", x + (#data.bosses > 0 and 10 or 0), 0)
	bar.rest:SetText(UI.join(bits, true))
	bar:SetWidth(x + 10 + math.ceil(bar.rest:GetStringWidth()) + PAD)
end

-- Showing ------------------------------------------------------------------------

local function holdTracker(on)
	local top = Stoa.modules.Top
	if not top or top.companionHolds == on then return end
	top.companionHolds = on or nil
	if top.FocusTracker then xpcall(top.FocusTracker, Stoa.catch, top) end
end

function Companion:SetView(view)
	self.db.view = view
	self:Refresh()
end

function Companion:Refresh()
	if not self.enabled or not self.db.enabled then
		if self.card then self.card:Hide() end
		if self.bar then self.bar:Hide() end
		holdTracker(false)
		return
	end
	local data = self:Gather()
	self.data = data
	local fighting = InCombatLockdown() or Stoa.modules.Top and Stoa.modules.Top.inFight
	local asCard = self.db.view ~= "line"
	if not data or fighting then
		if self.card then self.card:Hide() end
		if self.bar then self.bar:Hide() end
		holdTracker(false)
		return
	end
	if asCard then
		if not self.card then self:BuildCard() end
		if self.bar then self.bar:Hide() end
		self:FillCard(data)
		self.card:Show()
	else
		if not self.bar then self:BuildLine() end
		if self.card then self.card:Hide() end
		self:PlaceLine()
		self:FillLine(data)
		self.bar:Show()
	end
	holdTracker(asCard)
end

-- Many events come in bursts (the quest log), so a refresh waits a moment.
function Companion:Soon()
	if self.pending then return end
	self.pending = true
	C_Timer.After(0.3, function()
		self.pending = false
		xpcall(self.Refresh, Stoa.catch, self)
	end)
end

function Companion:OnEnable()
	local function soon() self:Soon() end
	Stoa:On("PLAYER_ENTERING_WORLD", soon)
	Stoa:On("ZONE_CHANGED_NEW_AREA", soon)
	Stoa:On("QUEST_LOG_UPDATE", function() if self.data then soon() end end)
	local function freshLoot()
		if self.cache then self.cache.loot = nil end
		if self.data then soon() end
	end
	Stoa:On("PLAYER_EQUIPMENT_CHANGED", freshLoot)
	Stoa:On("EJ_LOOT_DATA_RECIEVED", freshLoot)
	Stoa:On("PLAYER_REGEN_DISABLED", soon)
	Stoa:On("PLAYER_REGEN_ENABLED", soon)
	Stoa:On("ENCOUNTER_END", function(encounterID, _, _, _, success)
		local id = plain(encounterID)
		if not id or plain(success) ~= 1 then return end
		local where = self:Where()
		if where then self:Run(where).killed[id] = true end
		soon()
	end)
end

-- /stoa companion shows it now in any dungeon you're in, or says why not.
Stoa.commands.companion = function()
	if not Companion:Where() then
		Stoa:Print("The dungeon companion shows inside five-player dungeons.")
		return
	end
	Companion:Refresh()
end
