-- Stoa QoL: the dungeon companion. Inside a five-player dungeon, out of a
-- fight, a quiet card says where you are in it: the bosses (ticked off as
-- they fall) and your quests for it. It takes the quest list's place while it shows (the list
-- folds to its header, as in a fight) and folds away itself in a fight.
-- A switch turns it into one slim line over the console instead.
--
-- Forever keeps the Adventure Guide closed to addons, so the bosses come
-- from STOA's own list (Data/Dungeons.lua) and a boss is ticked off by the
-- name the game gives its kill. Quests are the ones under the dungeon's
-- name in your quest log.
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
-- A run is forgotten when you come back to the dungeon after this long.
local RUN_GAP = 2 * 3600

local function plain(value) return Stoa:PlainNumber(value) end

-- Data -------------------------------------------------------------------------

-- The dungeon you are in, or nil: its name, map, Adventure Guide id.
function Companion:Where()
	if self.preview then return self.preview end
	local inside, kind = IsInInstance()
	if not inside or kind ~= "party" then return nil end
	local name, _, _, _, _, _, _, instanceID = GetInstanceInfo()
	if not name or Stoa:IsSecret(name) then return nil end
	return { name = name, instanceID = instanceID, dungeon = Stoa.Dungeons and Stoa.Dungeons.find(name) }
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

-- The bosses for the dungeon, as { name, wing }: one wing's once a kill
-- shows which wing you are in, otherwise every wing's.
function Companion:Bosses(where, run)
	local dungeon = where.dungeon
	local list = {}
	if not dungeon then return list end
	if not dungeon.wings then
		for _, name in ipairs(dungeon.bosses) do list[#list + 1] = { name = name, listed = true } end
		return list
	end
	for _, wing in ipairs(dungeon.wings) do
		if not run.wing or run.wing == wing.name then
			for _, name in ipairs(wing.bosses) do list[#list + 1] = { name = name, wing = wing.name, listed = true } end
		end
	end
	return list
end

-- A boss fell: ticked off by name, and its wing becomes the one you're in.
function Companion:Killed(name)
	local where = self:Where()
	if not where or type(name) ~= "string" then return end
	local run = self:Run(where)
	if not run.killed[name:lower()] then
		run.fell = run.fell or {}
		run.fell[#run.fell + 1] = name
	end
	run.killed[name:lower()] = true
	for _, wing in ipairs(where.dungeon and where.dungeon.wings or {}) do
		for _, boss in ipairs(wing.bosses) do
			if boss:lower() == name:lower() then run.wing = wing.name end
		end
	end
end

-- A click on a boss's row ticks it by hand, or unticks it: for a death
-- STOA missed, or a boss the group has decided to skip.
function Companion:Tick(name)
	local where = self:Where()
	if not where or type(name) ~= "string" then return end
	local run = self:Run(where)
	local key = name:lower()
	if run.killed[key] then run.killed[key] = nil else self:Killed(name) end
	self:Refresh()
end

-- Some bosses don't count as an encounter for the game (optional ones
-- such as Highland Horror), so no kill comes. A listed boss also falls
-- when you target or point at its corpse, or have it targeted as the
-- fight ends.
function Companion:CheckCorpse(unit)
	if not self.data or not UnitExists(unit) or not (UnitIsDead and UnitIsDead(unit)) then return end
	local name = UnitName(unit)
	if type(name) ~= "string" or Stoa:IsSecret(name) then return end
	local want = name:lower()
	for _, boss in ipairs(self.data.bosses) do
		if not boss.dead and boss.name:lower() == want then
			self:Killed(boss.name)
			self:Soon()
			return
		end
	end
end

-- As a fight ends the dead boss is rarely your own target when you heal:
-- it is the tank's, or still stands as a nameplate. Every unit that may be
-- it is looked at, then and a moment later (the death can land after the
-- fight's end does).
function Companion:CheckCorpses()
	if not self.data then return end
	local units = { "target", "focus", "mouseover" }
	for i = 1, 4 do units[#units + 1] = "party" .. i .. "target" end
	for i = 1, 5 do units[#units + 1] = "boss" .. i end
	local plates = C_NamePlate and C_NamePlate.GetNamePlates and call(C_NamePlate.GetNamePlates)
	for _, plate in ipairs(type(plates) == "table" and plates or {}) do
		local unit = plate.namePlateUnitToken or (plate.UnitFrame and plate.UnitFrame.unit)
		if type(unit) == "string" then units[#units + 1] = unit end
	end
	for _, unit in ipairs(units) do pcall(self.CheckCorpse, self, unit) end
end

-- What the game itself has down for this run, where it keeps a lock for
-- the dungeon: each boss it marks killed is ticked.
function Companion:CheckLock()
	if not (GetInstanceLockTimeRemaining and GetInstanceLockTimeRemainingEncounter) then return end
	local _, _, total = call(GetInstanceLockTimeRemaining)
	for i = 1, plain(total) or 0 do
		local name, _, dead = call(GetInstanceLockTimeRemainingEncounter, i)
		if dead and type(name) == "string" and not Stoa:IsSecret(name) and name ~= "" then
			local where = self:Where()
			local run = where and self:Run(where)
			if run and not run.killed[name:lower()] then self:Killed(name) end
		end
	end
end

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
				-- The log may head them with another name for the dungeon
				-- ("The Stockade" inside "Stormwind Stockade").
				local title = Stoa.safe.plain(info.title)
				under = title == where.name
					or (where.dungeon ~= nil and Stoa.Dungeons.find(title) == where.dungeon)
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
				list[#list + 1] = { name = info.title, id = info.questID, done = done, progress = progress }
			end
		end
	end
	return list
end

function Companion:Gather()
	local where = self:Where()
	if not where then return nil end
	local run = self:Run(where)
	local bosses = self:Bosses(where, run)
	local down = 0
	local nextBoss
	local listed = {}
	for _, boss in ipairs(bosses) do listed[boss.name:lower()] = true end
	-- The game doesn't always name a fight as the list names its boss
	-- ("Handler Ashka" for War Handler Ashka). A kill that isn't on the
	-- list ticks the one listed boss whose name holds it, or is held by it,
	-- as whole words; with none or several it stays a row of its own.
	local alias, claimed = {}, {}
	for _, name in ipairs(run.fell or {}) do
		local want = name:lower()
		if not listed[want] then
			local found, several
			for _, boss in ipairs(bosses) do
				local have = boss.name:lower()
				local held = (" " .. have .. " "):find(" " .. want .. " ", 1, true) or (" " .. want .. " "):find(" " .. have .. " ", 1, true)
				if held and not claimed[have] then
					if found then several = true else found = have end
				end
			end
			if found and not several then
				alias[want] = true
				claimed[found] = true
			end
		end
	end
	-- Next is the first boss still standing after the last one that fell:
	-- a boss the group skipped, or whose death STOA missed, doesn't hold
	-- "Next" back for the rest of the run.
	local firstUp
	for _, boss in ipairs(bosses) do
		local have = boss.name:lower()
		boss.dead = (run.killed[have] or claimed[have]) and true or false
		if boss.dead then
			down = down + 1
			nextBoss = nil
		else
			firstUp = firstUp or boss
			nextBoss = nextBoss or boss
		end
	end
	nextBoss = nextBoss or firstUp
	-- A kill STOA's list doesn't have (a new dungeon, or the game names the
	-- boss differently) still shows, ticked off, after the listed ones.
	for _, name in ipairs(run.fell or {}) do
		if not listed[name:lower()] and not alias[name:lower()] then
			bosses[#bosses + 1] = { name = name, dead = true }
			down = down + 1
		end
	end
	if nextBoss then nextBoss.next = true end
	local quests = self:Quests(where)
	local questsDone = 0
	for _, quest in ipairs(quests) do if quest.done then questsDone = questsDone + 1 end end
	local map = Stoa.modules.Map
	return {
		where = where,
		levels = map and map.Levels and map:Levels(where.name),
		bosses = bosses, down = down, nextBoss = nextBoss,
		quests = quests, questsDone = questsDone,
	}
end

-- The card ---------------------------------------------------------------------

-- Made to read at a glance: a header band with the dungeon and its levels,
-- a strip with one segment per boss, then the bosses and your quests as
-- rows with a marker each (a tick once done, a dot while waiting, the next
-- boss lit in the accent on a soft band of its own).
local HEADER = 52
local ROW_H = 22
local MARK = 22

function Companion:BuildCard()
	local card = CreateFrame("Frame", "StoaCompanion", UIParent)
	card:SetSize(WIDTH, 160)
	card:SetFrameStrata("MEDIUM")
	card:Hide()
	UI.windowPanel(card, 0.95, { header = HEADER, plainHeader = true })
	UI.riseOnShow(card)

	local title = UI.text(card, "serif", Stoa.typeSize.name, "text", "LEFT")
	title:SetPoint("TOPLEFT", PAD, -12)
	title:SetPoint("RIGHT", card, "RIGHT", -PAD - 24, 0)
	title:SetWordWrap(false)
	local levels = UI.text(card, "sans", Stoa.typeSize.caption, "muted", "LEFT")
	levels:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -3)

	-- Folds the card to the slim line.
	local fold = CreateFrame("Button", nil, card)
	fold:SetSize(20, 20)
	fold:SetPoint("TOPRIGHT", -10, -12)
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

	-- Progress: words over a strip of one segment per boss.
	local bossCount = UI.text(card, "sans", Stoa.typeSize.caption, "text", "LEFT")
	bossCount:SetPoint("TOPLEFT", PAD, -HEADER - 12)
	local questCount = UI.text(card, "sans", Stoa.typeSize.caption, "muted", "RIGHT")
	questCount:SetPoint("TOPRIGHT", -PAD, -HEADER - 12)
	local strip = CreateFrame("Frame", nil, card)
	strip:SetHeight(4)
	strip:SetPoint("TOPLEFT", PAD, -HEADER - 30)
	strip:SetPoint("TOPRIGHT", -PAD, -HEADER - 30)

	-- The next boss's band: a soft accent wash with a bar at its left.
	local band = card:CreateTexture(nil, "BACKGROUND", nil, 6)
	band:SetTexture(UI.WHITE)
	local bar = card:CreateTexture(nil, "BORDER")
	bar:SetTexture(UI.WHITE)
	bar:SetWidth(2)
	bar:SetPoint("TOPLEFT", band, "TOPLEFT")
	bar:SetPoint("BOTTOMLEFT", band, "BOTTOMLEFT")

	card.title, card.levels, card.fold = title, levels, fold
	card.bossCount, card.questCount, card.strip, card.segments = bossCount, questCount, strip, {}
	card.band, card.bandBar = band, bar
	card.heads, card.rules, card.lines = {}, {}, {}
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

-- The strip: done segments in the accent, the next one half lit.
function Companion:FillStrip(bosses)
	local card = self.card
	local strip, segments = card.strip, card.segments
	for _, seg in ipairs(segments) do seg:Hide() end
	local count = #bosses
	strip:SetShown(count > 0)
	if count == 0 then return end
	local gap = 3
	local width = (WIDTH - PAD * 2 - gap * (count - 1)) / count
	local ar, ag, ab = Stoa:Color("accent")
	local tr, tg, tb = Stoa:Color("text")
	for i, boss in ipairs(bosses) do
		local seg = segments[i]
		if not seg then
			seg = strip:CreateTexture(nil, "ARTWORK")
			seg:SetTexture(UI.WHITE)
			segments[i] = seg
		end
		seg:ClearAllPoints()
		seg:SetPoint("TOPLEFT", strip, "TOPLEFT", (i - 1) * (width + gap), 0)
		seg:SetSize(width, 4)
		if boss.dead then
			seg:SetVertexColor(ar, ag, ab, 0.95)
		elseif boss.next then
			seg:SetVertexColor(ar, ag, ab, 0.4)
		else
			seg:SetVertexColor(tr, tg, tb, 0.12)
		end
		seg:Show()
	end
end

local function sectionHead(card, index, words)
	local head = card.heads[index]
	if not head then
		head = UI.text(card, "sans", Stoa.typeSize.micro, "accent", "LEFT")
		card.heads[index] = head
		local rule = card:CreateTexture(nil, "BORDER")
		UI.pixel(rule, "height")
		rule:SetTexture(UI.WHITE)
		rule:SetPoint("LEFT", head, "RIGHT", 8, 0)
		rule:SetPoint("RIGHT", card, "RIGHT", -PAD, 0)
		card.rules[index] = rule
	end
	local r, g, b = Stoa:Color("text")
	card.rules[index]:SetVertexColor(r, g, b, 0.1)
	head:SetText(words:upper())
	return head, card.rules[index]
end

local function makeRow(card)
	local row = {}
	row.mark = card:CreateTexture(nil, "OVERLAY")
	row.left = UI.text(card, "sans", Stoa.typeSize.body, "text", "LEFT")
	row.right = UI.text(card, "sans", Stoa.typeSize.caption, "muted", "RIGHT")
	row.left:SetWordWrap(false)
	row.right:SetWordWrap(false)
	-- A quest's row opens its details in the quest log (out of a fight;
	-- the card hides in one anyway).
	local hit = CreateFrame("Button", nil, card)
	local glow = hit:CreateTexture(nil, "BACKGROUND")
	glow:SetAllPoints()
	glow:SetTexture(UI.WHITE)
	glow:Hide()
	hit:SetScript("OnEnter", function(self)
		local r, g, b = Stoa:Color("text")
		glow:SetVertexColor(r, g, b, 0.06)
		glow:Show()
		GameTooltip:SetOwner(self, "ANCHOR_LEFT")
		GameTooltip:SetText(row.left:GetText() or "")
		GameTooltip:AddLine(row.questID and "Click for the quest's details." or "Click to tick or untick this boss.", 0.6, 0.6, 0.6)
		GameTooltip:Show()
	end)
	hit:SetScript("OnLeave", function()
		glow:Hide()
		GameTooltip:Hide()
	end)
	hit:SetScript("OnClick", function()
		if row.bossName then
			Stoa.modules.Companion:Tick(row.bossName)
			return
		end
		if InCombatLockdown() or not row.questID then return end
		local open = _G.QuestMapFrame_OpenToQuestDetails or _G.QuestLog_OpenToQuest
		if open then xpcall(open, Stoa.catch, row.questID) end
	end)
	hit:Hide()
	row.hit = hit
	return row
end

function Companion:FillCard(data)
	local card = self.card
	card.title:SetText(data.where.name)
	card.levels:SetText(data.levels or (self.preview and "Preview" or ""))

	local bosses = #data.bosses
	card.bossCount:SetText(bosses > 0 and ("%d of %d bosses"):format(data.down, bosses) or "Bosses show as they fall")
	card.questCount:SetText(#data.quests > 0 and ("%d of %d quests done"):format(data.questsDone, #data.quests) or "")
	self:FillStrip(data.bosses)

	for i, head in ipairs(card.heads) do head:Hide() card.rules[i]:Hide() end
	for _, row in ipairs(card.lines) do row.mark:Hide() row.left:Hide() row.right:Hide() row.hit:Hide() end
	card.band:Hide()
	card.bandBar:Hide()
	local y = -(HEADER + (bosses > 0 and 46 or 34))
	local heads, rows = 0, 0
	local ar, ag, ab = Stoa:Color("accent")
	local function head(words)
		heads = heads + 1
		local fs, rule = sectionHead(card, heads, words)
		fs:ClearAllPoints()
		fs:SetPoint("TOPLEFT", PAD, y - 8)
		fs:Show()
		rule:Show()
		y = y - 8 - 18
	end
	-- state: "done", "next" or nil (still to come).
	local function row(left, right, state, questID, bossName)
		rows = rows + 1
		local r = card.lines[rows]
		if not r then
			r = makeRow(card)
			card.lines[rows] = r
		end
		local mid = y - ROW_H / 2
		r.mark:ClearAllPoints()
		r.mark:SetPoint("CENTER", card, "TOPLEFT", PAD + 5, mid)
		if state == "done" then
			r.mark:SetTexture(UI.MEDIA .. "Textures\\GlyphTick")
			r.mark:SetSize(14, 14)
			r.mark:SetVertexColor(ar, ag, ab, 0.75)
		else
			r.mark:SetTexture(UI.MEDIA .. "Textures\\GlyphDot")
			local size = state == "next" and 10 or 7
			r.mark:SetSize(size, size * 2)
			if state == "next" then
				r.mark:SetVertexColor(ar, ag, ab, 1)
			else
				local mr, mg, mb = Stoa:Color("muted")
				r.mark:SetVertexColor(mr, mg, mb, 0.6)
			end
		end
		r.left:ClearAllPoints()
		r.left:SetPoint("LEFT", card, "TOPLEFT", PAD + MARK - 4, mid)
		r.left:SetPoint("RIGHT", card, "RIGHT", -PAD - 90, 0)
		r.right:ClearAllPoints()
		r.right:SetPoint("RIGHT", card, "TOPRIGHT", -PAD, mid)
		r.left:SetText(left)
		r.right:SetText(right or "")
		r.left:SetTextColor(Stoa:Color(state == "done" and "muted" or "text"))
		r.left:SetAlpha(state == "done" and 0.6 or 1)
		r.right:SetTextColor(Stoa:Color(state == "next" and "accent" or "muted"))
		if state == "next" then
			card.band:ClearAllPoints()
			card.band:SetPoint("TOPLEFT", card, "TOPLEFT", PAD - 8, y + 1)
			card.band:SetPoint("BOTTOMRIGHT", card, "TOPRIGHT", -PAD + 8, y - ROW_H - 1)
			card.band:SetVertexColor(ar, ag, ab, 0.09)
			card.bandBar:SetVertexColor(ar, ag, ab, 0.9)
			card.band:Show()
			card.bandBar:Show()
		end
		r.questID, r.bossName = questID, bossName
		if questID or bossName then
			r.hit:ClearAllPoints()
			r.hit:SetPoint("TOPLEFT", card, "TOPLEFT", PAD - 8, y)
			r.hit:SetPoint("BOTTOMRIGHT", card, "TOPRIGHT", -PAD + 8, y - ROW_H)
			r.hit:Show()
		end
		r.mark:Show()
		r.left:Show()
		r.right:Show()
		y = y - ROW_H
	end

	local wing
	for i, boss in ipairs(data.bosses) do
		if i == 1 or boss.wing ~= wing then
			wing = boss.wing
			head(wing and (wing .. " bosses") or "Bosses")
		end
		row(boss.name, boss.dead and "Done" or (boss.next and "Next") or "", boss.dead and "done" or (boss.next and "next"), nil, boss.listed and boss.name)
	end
	if #data.quests > 0 then
		head("Dungeon quests")
		for _, quest in ipairs(data.quests) do
			row(quest.name, quest.done and "Ready" or quest.progress, quest.done and "done", quest.id)
		end
	end
	card:SetHeight(-y + PAD)
end

-- The line ---------------------------------------------------------------------

local DOT = 8

function Companion:BuildLine()
	local bar = CreateFrame("Button", "StoaCompanionLine", UIParent)
	bar:SetHeight(30)
	bar:SetFrameStrata("MEDIUM")
	bar:Hide()
	UI.roundPanel(bar, 0.94)
	UI.riseOnShow(bar)
	local name = UI.text(bar, "serif", Stoa.typeSize.label, "text", "LEFT")
	name:SetPoint("LEFT", PAD, 0)
	local rest = UI.text(bar, "sans", Stoa.typeSize.body, "muted", "LEFT")
	bar.name, bar.rest, bar.dots = name, rest, {}
	bar:SetScript("OnClick", function() self:SetView("card") end)
	bar:SetScript("OnEnter", function(button)
		local data = self.data
		GameTooltip:SetOwner(button, "ANCHOR_TOP")
		GameTooltip:SetText(data and data.where.name or "Dungeon companion")
		for _, boss in ipairs(data and data.bosses or {}) do
			local r, g, b = Stoa:Color(boss.next and "accent" or (boss.dead and "muted" or "text"))
			GameTooltip:AddLine(boss.name, r, g, b)
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
		-- Slate's own card (name, health, portrait) stands on the console's
		-- rim in the middle; the line clears its portrait.
		local grimoire = Stoa.modules.Grimoire
		local you = grimoire and grimoire.youCard and grimoire.YOU_CARD
		local lift = you and (you.y + you.height / 2 + 14) or 8
		bar:SetPoint("BOTTOM", console, "TOP", 0, lift)
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
	Stoa:On("PLAYER_ENTERING_WORLD", function()
		self.preview = nil
		soon()
	end)
	Stoa:On("ZONE_CHANGED_NEW_AREA", soon)
	Stoa:On("QUEST_LOG_UPDATE", function() if self.data then soon() end end)
	Stoa:On("PLAYER_REGEN_DISABLED", soon)
	Stoa:On("PLAYER_REGEN_ENABLED", function()
		local function look()
			pcall(self.CheckCorpses, self)
			pcall(self.CheckLock, self)
			soon()
		end
		look()
		C_Timer.After(2, look)
	end)
	-- Some bosses send this and no end of an encounter.
	Stoa:On("BOSS_KILL", function(_, name)
		if type(name) ~= "string" or Stoa:IsSecret(name) or name == "" then return end
		self:Killed(name)
		soon()
	end)
	Stoa:On("PLAYER_TARGET_CHANGED", function() pcall(self.CheckCorpse, self, "target") end)
	Stoa:On("UPDATE_MOUSEOVER_UNIT", function() pcall(self.CheckCorpse, self, "mouseover") end)
	Stoa:On("ENCOUNTER_END", function(_, encounterName, _, _, success)
		if plain(success) ~= 1 or Stoa:IsSecret(encounterName) then return end
		self:Killed(encounterName)
		soon()
	end)
end

-- /stoa companion shows it now in any dungeon you're in, or says why not.
-- /stoa companion <part of a name> previews that dungeon's card anywhere;
-- /stoa companion off ends it.
Stoa.commands.companion = function(rest)
	rest = rest and strtrim(rest) or ""
	if rest:lower() == "off" then
		Companion.preview = nil
		Companion:Refresh()
		return
	end
	if rest ~= "" then
		local dungeon = Stoa.Dungeons and Stoa.Dungeons.search(rest)
		if not dungeon then
			local names = {}
			for _, known in ipairs(Stoa.Dungeons or {}) do names[#names + 1] = known.name end
			Stoa:Print(("No dungeon matches %q. STOA knows: %s."):format(rest, table.concat(names, ", ")))
			return
		end
		Companion.preview = { name = dungeon.name, instanceID = "preview:" .. dungeon.name, dungeon = dungeon }
		Companion:Refresh()
		Stoa:Print("Previewing the companion for " .. dungeon.name .. ". /stoa companion off ends it.")
		return
	end
	if not Companion:Where() then
		Stoa:Print("The dungeon companion shows inside five-player dungeons. Try /stoa companion stockade (any part of a dungeon's name) for a preview.")
		return
	end
	Companion:Refresh()
end
