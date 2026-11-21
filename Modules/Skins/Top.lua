-- Stoa: the top of the screen in Stoa's hand.
--   Buffs: cropped icons in a hairline square, the time under them in the
--   sans, muted until it runs short. Debuffs take an amber edge instead of
--   Blizzard's coloured frame.
--   Quest tracker: headers lose their gold bars for the display face over a
--   hairline; quest titles are bone (the [level] tag still says how hard),
--   the collapse buttons a quiet minus or plus.
--   Minimap header: the zone in the display face on a dark rounded panel,
--   the clock quiet beside it; tracking, calendar and the addon button wait
--   until you mouse over the header.
--
-- Frame names come from the Forever client's own UI code. Everything is
-- looked up and guarded, so a renamed frame costs one detail.
local _, ns = ...
local Stoa = ns.Stoa
local hooksecurefunc = Stoa.SafeHook
local UI = Stoa.UI

local Top = Stoa:NewModule("Top", {
	-- Buffs as a list: each with its name and time left beside the icon.
	buffList = false,
	-- In combat the quest list folds to its header.
	trackerFocus = true,
})

local function guarded(fn, ...)
	xpcall(fn, Stoa.catch, ...)
end

-- Textures moved here never draw again, whatever Blizzard does to them.
local vault = CreateFrame("Frame")
vault:Hide()
local function bury(tex)
	if tex and tex.SetParent then tex:SetParent(vault) end
end

-- Buffs ----------------------------------------------------------------------

-- The dark plate a buff's time sits on, under its icon.
local PLATE_H = 14
local PLATE_ALPHA = 0.25

local function auraDuration(button)
	local mine = button.stoaDuration
	if not mine then return end
	local theirs = button.Duration
	local shown = theirs and theirs:IsShown()
	mine:SetShown(shown or false)
	if mine.plate then mine.plate:SetShown((shown and not mine.inList) or false) end
	if not shown then return end
	mine:SetText(theirs:GetText())
	local left = button.timeLeft
	local short = left and not Stoa:IsSecret(left) and BUFF_DURATION_WARNING_TIME and left < BUFF_DURATION_WARNING_TIME
	mine:SetTextColor(Stoa:Color(short and "accent" or "text"))
end

-- List style: the buff's name to the left of its icon and the time before
-- it, as "59m  Gift of the Wild". Names can be hidden in combat; the last
-- one read stays until the button shows another aura.
local function auraName(button)
	local name = button.stoaName
	if not name then return end
	local list = Top.db.buffList and button.auraType ~= "Debuff" and button.auraType ~= "DeadlyDebuff"
	name:SetShown(list and true or false)
	if button.stoaDuration then
		button.stoaDuration:ClearAllPoints()
		if list then
			button.stoaDuration:SetPoint("RIGHT", name, "LEFT", -8, 0)
		else
			button.stoaDuration:SetPoint("TOP", button.Icon, "BOTTOM", 0, -3)
		end
		-- The plate hangs under the icon, so it only suits the time there.
		button.stoaDuration.inList = list and true or false
		if button.stoaDuration.plate then
			button.stoaDuration.plate:SetShown(not list and button.stoaDuration:IsShown())
		end
	end
	if not list then return end
	local info = button.buttonInfo
	local id = info and info.auraInstanceID
	if id ~= button.stoaNameFor then
		local text
		if info and info.auraType == "TempEnchant" then
			text = "Weapon"
		elseif id and C_UnitAuras and C_UnitAuras.GetAuraDataByAuraInstanceID then
			local ok, data = pcall(C_UnitAuras.GetAuraDataByAuraInstanceID, "player", id)
			if ok and data and not Stoa:IsSecret(data.name) then text = data.name end
		end
		if text then
			name:SetText(text)
			button.stoaNameFor = id
		end
	end
end

local function auraEdge(button)
	local edge = button.stoaEdge
	if not edge then return end
	local kind = button.auraType
	if kind == "Debuff" or kind == "DeadlyDebuff" then
		edge:Set(Stoa:Color("danger"))
	elseif kind == "TempEnchant" then
		edge:Set(Stoa:Color("accent"))
	else
		edge:Set(Stoa:Color("hairline"))
	end
end

local function dressAura(button)
	-- Private aura anchors share the list but hold a frame, not an icon.
	if not button or button.stoaDressed or not (button.Icon and button.Icon.SetTexCoord) then return end
	button.stoaDressed = true
	button.Icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	bury(button.DebuffBorder)
	bury(button.TempEnchantBorder)

	local frame = CreateFrame("Frame", nil, button)
	frame:SetAllPoints(button.Icon)
	button.stoaEdge = UI.border(frame, 1, 1)

	-- Blizzard's duration stays (it drives the timing) but goes unseen;
	-- Stoa's copy carries the words.
	if button.Duration then
		button.Duration:SetAlpha(0)
		local mine = frame:CreateFontString(nil, "OVERLAY")
		mine:SetPoint("TOP", button.Icon, "BOTTOM", 0, -3)
		-- Over the world with nothing behind it, so the time sits on a
		-- flat dark plate hung from the icon, the same width as the icon and
		-- its edge: readable on snow, sand and bright sky with no outline.
		Stoa:SetFont(mine, "sans", Stoa.typeSize.caption)
		mine:SetShadowColor(0, 0, 0, 0.9)
		mine:SetShadowOffset(1, -1)
		local plate = frame:CreateTexture(nil, "BACKGROUND")
		plate:SetColorTexture(0, 0, 0, PLATE_ALPHA)
		plate:SetPoint("TOPLEFT", button.Icon, "BOTTOMLEFT", -1, -1)
		plate:SetPoint("TOPRIGHT", button.Icon, "BOTTOMRIGHT", 1, -1)
		plate:SetHeight(PLATE_H)
		plate:Hide()
		mine.plate = plate
		mine:Hide()
		button.stoaDuration = mine
	end
	local name = frame:CreateFontString(nil, "OVERLAY")
	Stoa:SetFont(name, "sans", Stoa.typeSize.label)
	name:SetPoint("RIGHT", button.Icon, "LEFT", -6, 0)
	name:SetJustifyH("RIGHT")
	name:SetTextColor(Stoa:Color("text"))
	UI.legible(name)
	name:Hide()
	button.stoaName = name
	if button.Update then hooksecurefunc(button, "Update", function(own) guarded(auraName, own) end) end
	if button.Count then
		Stoa:SetFont(button.Count, "sans", Stoa.typeSize.body, "OUTLINE")
		button.Count:SetTextColor(Stoa:Color("text"))
	end

	if button.UpdateDuration then hooksecurefunc(button, "UpdateDuration", auraDuration) end
	if button.UpdateExpirationTime then hooksecurefunc(button, "UpdateExpirationTime", auraDuration) end
	if button.UpdateAuraType then hooksecurefunc(button, "UpdateAuraType", auraEdge) end
	auraEdge(button)
	auraDuration(button)
	auraName(button)
end

local function dressAuraFrame(frame)
	if not frame or not frame.auraFrames then return end
	for _, button in ipairs(frame.auraFrames) do guarded(dressAura, button) end
	if frame.ConsolidatedBuffs then guarded(dressAura, frame.ConsolidatedBuffs) end
	local toggle = frame.CollapseAndExpandButton
	if toggle and not toggle.stoaDressed then
		toggle.stoaDressed = true
		toggle:SetAlpha(0.5)
	end
end

function Top:Buffs()
	for _, frame in ipairs({ _G.BuffFrame, _G.DebuffFrame, _G.ExternalDefensivesFrame }) do
		guarded(dressAuraFrame, frame)
	end
end

function Top:RefreshBuffList()
	for _, button in ipairs(_G.BuffFrame and _G.BuffFrame.auraFrames or {}) do
		button.stoaNameFor = nil
		guarded(auraName, button)
	end
end

-- Quest tracker ----------------------------------------------------------------

-- Tracker words follow the tracker's own text size (Edit Mode), in Stoa's
-- faces: headers and quest titles in the display face, lines in the sans.
local function trackerFonts()
	local faces = { { _G.ObjectiveTrackerHeaderFont, "serif", 1 }, { _G.ObjectiveTrackerLineFont, "sans", 0 } }
	for _, entry in ipairs(faces) do
		local fontObject, kind, extra = entry[1], entry[2], entry[3]
		if fontObject and fontObject.GetFont then
			local _, size = fontObject:GetFont()
			local candidate = Stoa.fonts[kind] and Stoa.fonts[kind][1]
			if size and candidate then
				pcall(fontObject.SetFont, fontObject, candidate[1], (size + extra) * candidate[2], "")
				fontObject:SetShadowOffset(0, 0)
			end
		end
	end
end

local function titleColour(block)
	local header = block and block.HeaderText
	if not header then return end
	header:SetTextColor(Stoa:Color(block.isHighlighted and "accent" or "text"))
end

local function dressBlock(block)
	if not block or block.stoaDressed then return end
	block.stoaDressed = true
	if block.UpdateHighlight then hooksecurefunc(block, "UpdateHighlight", titleColour) end
	if block.SetHeader then hooksecurefunc(block, "SetHeader", titleColour) end
	titleColour(block)
end

local function dressHeader(header, collapsed)
	if not header or header.stoaDressed then return end
	header.stoaDressed = true
	bury(header.Background)
	if header.Text then header.Text:SetTextColor(Stoa:Color("text")) end
	local line = UI.line(header)
	line:SetPoint("BOTTOMLEFT", 7, 2)
	line:SetPoint("BOTTOMRIGHT", -2, 2)
	UI.applyTheme()
	if header.MinimizeButton then
		local fold = UI.foldGlyph(header.MinimizeButton)
		header.stoaFold = fold
		if header.SetCollapsed then hooksecurefunc(header, "SetCollapsed", function(_, value) fold(value) end) end
		fold(collapsed)
	end
end

local function dressModule(module)
	if not module or module.stoaDressed then return end
	module.stoaDressed = true
	dressHeader(module.Header, module.IsCollapsed and module:IsCollapsed())
	if module.AddBlock then
		hooksecurefunc(module, "AddBlock", function(_, block) guarded(dressBlock, block) end)
	end
	-- The tracker's own update runs through a saved function (not
	-- tracker.Update), so the overflow fade follows each section's layout.
	if module.EndLayout then
		hooksecurefunc(module, "EndLayout", function() Top:SoonFade() end)
	end
	if module.EnumerateActiveBlocks then
		module:EnumerateActiveBlocks(function(block) guarded(dressBlock, block) end)
	end
end

-- The tracker's height is left to the game: resizing it from addon code
-- taints its update queue for the rest of the session, and in a dungeon
-- fight the scenario section then fails reading secret auras ("Auras cannot
-- be accessed when secret while tainted by Stoa"). Instead, quests that
-- would run down over the console, the menu or the bags fade out (alpha
-- only, which touches none of the tracker's own data).
local FLOOR_GAP = 10

local function floorY()
	local best = 0
	local console = Stoa.modules.Grimoire
	if console and console.OpenHeight and console.frame and console.frame:IsShown() then
		best = (Stoa:PlainNumber(console:OpenHeight()) or 0) * UIParent:GetEffectiveScale()
	end
	for _, frame in ipairs({ _G.MicroMenuContainer or _G.MicroMenu, _G.BagsBar }) do
		if frame and frame:IsShown() and not (frame.IsForbidden and frame:IsForbidden()) then
			local ok, top = pcall(frame.GetTop, frame)
			top = ok and Stoa:PlainNumber(top)
			if top then best = math.max(best, top * frame:GetEffectiveScale()) end
		end
	end
	return best
end

local function below(frame, floor)
	local ok, bottom = pcall(frame.GetBottom, frame)
	bottom = ok and Stoa:PlainNumber(bottom)
	return bottom and bottom * frame:GetEffectiveScale() < floor
end

-- Once per frame, after every section has laid out.
function Top:SoonFade()
	if self.fadePending then return end
	self.fadePending = true
	C_Timer.After(0, function()
		Top.fadePending = false
		guarded(Top.FadeOverflow, Top)
	end)
end

function Top:FadeOverflow()
	local tracker = _G.ObjectiveTrackerFrame
	if not tracker or (tracker.IsForbidden and tracker:IsForbidden()) then return end
	local floor = floorY() + FLOOR_GAP * UIParent:GetEffectiveScale()
	for _, module in ipairs(tracker.modules or {}) do
		if not (module.IsForbidden and module:IsForbidden()) and module.EnumerateActiveBlocks then
			if module.Header then module.Header:SetAlpha(below(module.Header, floor) and 0 or 1) end
			module:EnumerateActiveBlocks(function(block)
				block:SetAlpha(below(block, floor) and 0 or 1)
			end)
		end
	end
end

function Top:Tracker()
	local tracker = _G.ObjectiveTrackerFrame
	if not tracker or self.trackerDressed then return end
	self.trackerDressed = true
	trackerFonts()
	if ObjectiveTrackerManager and ObjectiveTrackerManager.SetTextSize then
		hooksecurefunc(ObjectiveTrackerManager, "SetTextSize", function() guarded(trackerFonts) end)
	end
	dressHeader(tracker.Header, tracker.IsCollapsed and tracker:IsCollapsed())
	for _, module in ipairs(tracker.modules or {}) do guarded(dressModule, module) end
	if tracker.AddModule then
		hooksecurefunc(tracker, "AddModule", function(_, module) guarded(dressModule, module) end)
	end
	-- The tracker shows its sections again whenever it lays out; keep them folded.
	if tracker.Update then
		hooksecurefunc(tracker, "Update", function()
			if Top.trackerFocused then guarded(Top.FocusTracker, Top) end
			guarded(Top.FadeOverflow, Top)
		end)
	end
end

-- Minimap header ---------------------------------------------------------------

local function zoneColour()
	if MinimapZoneText then MinimapZoneText:SetTextColor(Stoa:Color("text")) end
end

function Top:Clock()
	local clock = _G.TimeManagerClockTicker
	if not clock or self.clockDressed then return end
	self.clockDressed = true
	Stoa:SetFont(clock, "sans", Stoa.typeSize.caption)
	clock:SetTextColor(Stoa:Color("muted"))
	clock:SetShadowOffset(0, 0)
	local button = _G.TimeManagerClockButton
	if button then
		for _, region in ipairs({ button:GetRegions() }) do
			if region.IsObjectType and region:IsObjectType("Texture") then bury(region) end
		end
	end
end

-- The header row (zone, clock, tracking) sits just above the minimap's
-- frame rather than at the top of the cluster, which left a wide gap over
-- the round or painted frame. The row's strip is moved, and what Blizzard
-- hangs on it follows. Edit Mode or a layout can put it back, so any move
-- Stoa didn't make is undone a frame later.
local seating
function Top:SeatHeader()
	local cluster, map = _G.MinimapCluster, _G.Minimap
	local strip = cluster and (cluster.BorderTop or cluster.ZoneTextButton)
	if not (strip and map and strip.SetPoint) or InCombatLockdown() then return end
	local width = Stoa:PlainNumber(strip:GetWidth())
	local style = Stoa.modules.Minimap
	local above = 4
	if style and style.painted then above = math.floor(map:GetWidth() * 0.065) + 6 end
	seating = true
	strip:ClearAllPoints()
	strip:SetPoint("BOTTOM", map, "TOP", 0, above)
	if width and width > 0 then strip:SetWidth(width) end
	seating = false
	if not strip.stoaSeatHooked then
		strip.stoaSeatHooked = true
		local pending
		hooksecurefunc(strip, "SetPoint", function()
			if seating or pending then return end
			pending = true
			C_Timer.After(0, function()
				pending = false
				Stoa:AfterCombat(function() xpcall(Top.SeatHeader, Stoa.catch, Top) end)
			end)
		end)
		for _, event in ipairs({ "PLAYER_ENTERING_WORLD", "UI_SCALE_CHANGED", "EDIT_MODE_LAYOUTS_UPDATED" }) do
			Stoa:On(event, function() Stoa:AfterCombat(function() xpcall(Top.SeatHeader, Stoa.catch, Top) end) end)
		end
	end
end

-- The day and night dial (Forever's Diel frame, MinimapCluster.DielFrame)
-- sat on the minimap's top-right corner, over the frame. It moves into the
-- header row at its right end, sized to the row, with the clock just
-- before it and the zone name stopping short of the clock. The game re-places
-- it when Edit Mode scales the minimap, so any outside move is undone.
local placingSun
function Top:PlaceSun()
	local cluster = _G.MinimapCluster
	local sun, zone = cluster and cluster.DielFrame, cluster and cluster.ZoneTextButton
	if not (sun and zone and sun.SetPoint) or InCombatLockdown() then return end
	if sun.IsForbidden and sun:IsForbidden() then return end
	local clock = _G.TimeManagerClockButton
	local rowHeight = Stoa:PlainNumber(zone:GetHeight()) or 0
	local own = Stoa:PlainNumber(sun:GetHeight()) or 0
	placingSun = true
	if rowHeight > 0 and own > 0 then
		-- Scale against the zone row's own effective scale.
		local ratio = (zone:GetEffectiveScale() or 1) / ((sun:GetParent() and sun:GetParent():GetEffectiveScale()) or 1)
		sun:SetScale(math.min(1, (rowHeight + 6) / own) * ratio)
	end
	sun:ClearAllPoints()
	sun:SetPoint("RIGHT", zone, "RIGHT", -3, 0)
	sun:SetFrameLevel(zone:GetFrameLevel() + 2)
	local before = sun
	if clock and clock.SetPoint and not (clock.IsForbidden and clock:IsForbidden()) then
		clock:ClearAllPoints()
		clock:SetPoint("RIGHT", sun, "LEFT", -2, -1)
		if clock:IsShown() then before = clock end
	end
	local text = _G.MinimapZoneText
	if text and text.SetPoint then
		text:ClearAllPoints()
		text:SetPoint("LEFT", zone, "LEFT", 8, -1)
		text:SetPoint("RIGHT", before, "LEFT", -4, 0)
		text:SetJustifyH("LEFT")
		text:SetWordWrap(false)
	end
	placingSun = false
	if not sun.stoaSunHooked then
		sun.stoaSunHooked = true
		local pending
		local function again()
			if placingSun or pending then return end
			pending = true
			C_Timer.After(0, function()
				pending = false
				Stoa:AfterCombat(function() xpcall(Top.PlaceSun, Stoa.catch, Top) end)
			end)
		end
		hooksecurefunc(sun, "SetPoint", again)
		hooksecurefunc(sun, "SetScale", again)
		sun.stoaAgain = again
	end
	-- The clock comes with its own addon, sometimes after the sun is placed.
	if clock and clock.SetPoint and not clock.stoaSunHooked and sun.stoaAgain then
		clock.stoaSunHooked = true
		hooksecurefunc(clock, "SetPoint", sun.stoaAgain)
		clock:HookScript("OnShow", sun.stoaAgain)
		clock:HookScript("OnHide", sun.stoaAgain)
	end
end

function Top:MinimapHeader()
	local cluster = _G.MinimapCluster
	local zone = cluster and cluster.ZoneTextButton
	if not zone then return end
	bury(zone.StateTexture)
	bury(zone.AddTexture)

	local panel = CreateFrame("Frame", nil, zone)
	panel:SetPoint("TOPLEFT", -2, 1)
	panel:SetPoint("BOTTOMRIGHT", 2, -1)
	panel:SetFrameLevel(math.max(zone:GetFrameLevel() - 1, 0))
	UI.roundPanel(panel, 0.9)

	if MinimapZoneText then
		Stoa:SetFont(MinimapZoneText, "serif", Stoa.typeSize.body)
		MinimapZoneText:SetShadowOffset(0, 0)
	end
	if _G.Minimap_Update then hooksecurefunc("Minimap_Update", zoneColour) end
	self:SeatHeader()
	xpcall(self.PlaceSun, Stoa.catch, self)
	zoneColour()

	-- The header's buttons wait for the mouse.
	local quiet = {}
	if cluster.Tracking then quiet[#quiet + 1] = cluster.Tracking end
	if _G.GameTimeFrame then quiet[#quiet + 1] = _G.GameTimeFrame end
	if _G.AddonCompartmentFrame then quiet[#quiet + 1] = _G.AddonCompartmentFrame end
	local hover = { zone }
	for _, frame in ipairs(quiet) do hover[#hover + 1] = frame end

	local function invitesWaiting()
		return _G.GameTimeCalendarInvitesTexture and _G.GameTimeCalendarInvitesTexture:IsShown()
	end
	local function settle()
		local over = false
		for _, frame in ipairs(hover) do
			if frame:IsMouseOver() then over = true end
		end
		for _, frame in ipairs(quiet) do
			local keep = over or (frame == _G.GameTimeFrame and invitesWaiting())
			frame:SetAlpha(keep and 1 or 0)
		end
	end
	for _, frame in ipairs(hover) do
		frame:HookScript("OnEnter", settle)
		frame:HookScript("OnLeave", function() C_Timer.After(0.15, settle) end)
	end
	settle()
end


-- Combat fold -------------------------------------------------------------------
-- In a fight the quest list is noise, so it folds to its header and comes
-- back after. Hovering the header opens it for as long as the mouse stays on
-- the list. The tracker's own collapse is left alone: setting it from addon
-- code would taint the list and block its quest item buttons, so the
-- sections are hidden instead and shown again as they were. A dungeon's
-- scenario objectives stay up.
local function foldable(module)
	return module ~= _G.ScenarioObjectiveTracker and not (module.IsForbidden and module:IsForbidden())
end

local function watchHide(module)
	if module.stoaHideWatched then return end
	module.stoaHideWatched = true
	-- The tracker hid it itself (nothing left to show): not ours to bring back.
	hooksecurefunc(module, "Hide", function(self) self.stoaFolded = nil end)
	-- Every relayout (a kill counted, an item looted) ends with the module
	-- showing itself again; while the list is folded for a fight it goes
	-- straight back.
	if module.EndLayout then
		hooksecurefunc(module, "EndLayout", function(self)
			if Top.trackerFocused and self:IsShown() then
				self:Hide()
				self.stoaFolded = true
			end
		end)
	end
end

function Top:FocusTracker()
	local tracker = _G.ObjectiveTrackerFrame
	if not tracker or (tracker.IsForbidden and tracker:IsForbidden()) then return end
	local header = tracker.Header
	local over = tracker:IsMouseOver() and (self.trackerPeek or (header and header:IsMouseOver()))
	-- The dungeon companion's card takes the list's place while it shows.
	local hold = (self.db.trackerFocus and Top.inFight) or self.companionHolds
	self.trackerPeek = ((Top.inFight or self.companionHolds) and over) or nil
	local folded = (hold and not over) or false
	for _, module in ipairs(tracker.modules or {}) do
		if foldable(module) then
			watchHide(module)
			if folded and module:IsShown() then
				module:Hide()
				module.stoaFolded = true
			elseif not folded and module.stoaFolded then
				module.stoaFolded = nil
				module:Show()
			end
		end
	end
	if header and header.stoaFold then
		header.stoaFold(folded or (tracker.IsCollapsed and tracker:IsCollapsed()) or false)
	end
	self.trackerFocused = folded
end

-- Quest timers -------------------------------------------------------------------

-- The game's quest timer box sits on top of the quest list and the list
-- only makes room for it at its next relayout, so it covered the headings.
-- STOA hides that box and shows the timers itself: a quiet card left of
-- the list's heading, one line per timed quest, counting down.
local function clock(seconds)
	seconds = math.max(0, math.floor(seconds))
	if seconds >= 3600 then return ("%d:%02d:%02d"):format(seconds / 3600, (seconds % 3600) / 60, seconds % 60) end
	return ("%d:%02d"):format(seconds / 60, seconds % 60)
end

function Top:QuestTimers()
	local log = C_QuestLog
	if not (log and log.GetQuestTimers) then return end
	local list = {}
	local ok, timers = pcall(log.GetQuestTimers)
	for _, info in ipairs(ok and type(timers) == "table" and timers or {}) do
		local left = Stoa:PlainNumber(info.questTimer)
		if left and left > 0 then
			local title = log.GetTitleForQuestID and Stoa.safe.plain(Stoa.safe.call(log.GetTitleForQuestID, info.questID))
			list[#list + 1] = { id = info.questID, ends = GetTime() + left, title = title or "Timed quest" }
		end
	end
	self.timers = list
	local box = _G.QuestTimerFrame
	if box and not (box.IsForbidden and box:IsForbidden()) and not box.stoaHidden then
		box.stoaHidden = true
		hooksecurefunc(box, "Show", function(frame) frame:Hide() end)
		box:Hide()
	end
	local card = self.timerCard
	if #list == 0 then
		if card then card:Hide() end
		if self.timerTicker then self.timerTicker:Cancel() self.timerTicker = nil end
		return
	end
	if not card then
		card = CreateFrame("Frame", "StoaQuestTimers", UIParent)
		card:SetFrameStrata("MEDIUM")
		card:SetWidth(220)
		UI.roundPanel(card)
		card.rows = {}
		self.timerCard = card
	end
	local tracker = _G.ObjectiveTrackerFrame
	card:ClearAllPoints()
	if tracker and tracker.Header and not (tracker.IsForbidden and tracker:IsForbidden()) then
		card:SetPoint("TOPRIGHT", tracker.Header, "TOPLEFT", -10, 4)
	else
		card:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", -320, -260)
	end
	for i, timer in ipairs(list) do
		local row = card.rows[i]
		if not row then
			row = {}
			row.name = UI.text(card, "sans", Stoa.typeSize.caption, "muted", "LEFT")
			row.name:SetPoint("TOPLEFT", card, "TOPLEFT", 12, -8 - (i - 1) * 22)
			row.name:SetPoint("RIGHT", card, "RIGHT", -64, 0)
			row.name:SetWordWrap(false)
			row.time = UI.text(card, "sans", Stoa.typeSize.body, "accent", "RIGHT")
			row.time:SetPoint("RIGHT", card, "RIGHT", -12, 0)
			row.time:SetPoint("TOP", row.name, "TOP", 0, 1)
			card.rows[i] = row
		end
		row.name:SetText(timer.title)
		row.name:Show()
		row.time:Show()
	end
	for i = #list + 1, #card.rows do card.rows[i].name:Hide() card.rows[i].time:Hide() end
	card:SetHeight(16 + #list * 22 - 6)
	local function tick()
		for i, timer in ipairs(self.timers or {}) do
			local row = card.rows[i]
			if row then row.time:SetText(clock(timer.ends - GetTime())) end
		end
	end
	tick()
	card:Show()
	if not self.timerTicker then self.timerTicker = C_Timer.NewTicker(1, function() guarded(tick) end) end
end

function Top:OnEnable()
	guarded(self.Buffs, self)
	guarded(self.Tracker, self)
	guarded(self.MinimapHeader, self)
	if _G.TimeManagerClockTicker then guarded(self.Clock, self) end
	Stoa:On("ADDON_LOADED", function(name)
		if name == "Blizzard_TimeManager" then
			guarded(Top.Clock, Top)
			C_Timer.After(0, function() guarded(Top.PlaceSun, Top) end)
		end
		if name == "Blizzard_ObjectiveTracker" and not Top.trackerDressed then guarded(Top.Tracker, Top) end
	end)
	-- Buff buttons can be made after login (the consolidation tooltip, edit mode).
	Stoa:On("PLAYER_ENTERING_WORLD", function()
		C_Timer.After(1, function() guarded(Top.Buffs, Top) end)
		-- The console, menu and bags settle after login.
		C_Timer.After(2, function() guarded(Top.FadeOverflow, Top) end)
	end)
	Stoa:On("PLAYER_REGEN_DISABLED", function() Top.inFight = true; guarded(Top.FocusTracker, Top) end)
	Stoa:On("PLAYER_REGEN_ENABLED", function() Top.inFight = false; guarded(Top.FocusTracker, Top) end)
	-- Practice combat folds it too, so the fight's look can be judged whole.
	Stoa:On("STOA_PRACTICE", function(on)
		Top.inFight = (on or InCombatLockdown()) and true or false
		guarded(Top.FocusTracker, Top)
	end)
	-- Hovering the header in a fight opens the list; leaving folds it again.
	Stoa:On("STOA_TICK", function()
		local tracker = _G.ObjectiveTrackerFrame
		if not (tracker and (Top.db.trackerFocus or Top.companionHolds)) then return end
		local header = tracker.Header
		local over = tracker:IsMouseOver() and (Top.trackerPeek or (header and header:IsMouseOver()))
		local hold = (Top.db.trackerFocus and Top.inFight) or Top.companionHolds
		local want = (hold and not over) or false
		if want ~= (Top.trackerFocused or false) then guarded(Top.FocusTracker, Top) end
	end)
	Stoa:On("QUEST_LOG_UPDATE", function() guarded(Top.QuestTimers, Top) end)
	Stoa:On("STOA_THEME_CHANGED", function()
		zoneColour()
		local tracker = _G.ObjectiveTrackerFrame
		for _, module in ipairs(tracker and tracker.modules or {}) do
			if module.EnumerateActiveBlocks then module:EnumerateActiveBlocks(titleColour) end
		end
	end)
end
