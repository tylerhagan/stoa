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
	-- In combat the quest list dims to the quest you're working on.
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

local function auraDuration(button)
	local mine = button.stoaDuration
	if not mine then return end
	local theirs = button.Duration
	local shown = theirs and theirs:IsShown()
	mine:SetShown(shown or false)
	if not shown then return end
	mine:SetText(theirs:GetText())
	local left = button.timeLeft
	local short = left and not Stoa:IsSecret(left) and BUFF_DURATION_WARNING_TIME and left < BUFF_DURATION_WARNING_TIME
	mine:SetTextColor(Stoa:Color(short and "accent" or "muted"))
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
		Stoa:SetFont(mine, "sans", Stoa.typeSize.caption)
		mine:SetPoint("TOP", button.Icon, "BOTTOM", 0, -3)
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
	if module.EnumerateActiveBlocks then
		module:EnumerateActiveBlocks(function(block) guarded(dressBlock, block) end)
	end
end

-- The tracker grows down to its Edit Mode height (or the screen's foot),
-- which with a long quest log ran it over the bags, the menu and the
-- console. Its height is capped so it stops above the highest of them; the
-- tracker then folds what doesn't fit, as it does at its own limit.
local FLOOR_GAP = 10

local function floorY(scale)
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
	return best / scale
end

function Top:FitTracker()
	local tracker = _G.ObjectiveTrackerFrame
	if not tracker or (tracker.IsForbidden and tracker:IsForbidden()) then return end
	local ok, top = pcall(tracker.GetTop, tracker)
	top = ok and Stoa:PlainNumber(top)
	local height = Stoa:PlainNumber(tracker:GetHeight())
	if not (top and height) then return end
	local room = top - floorY(tracker:GetEffectiveScale()) - FLOOR_GAP
	if room > 60 and height > room + 0.5 then tracker:SetHeight(room) end
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
	if tracker.UpdateHeight then
		hooksecurefunc(tracker, "UpdateHeight", function() guarded(Top.FitTracker, Top) end)
	end
	guarded(self.FitTracker, self)
	if tracker.AddModule then
		hooksecurefunc(tracker, "AddModule", function(_, module) guarded(dressModule, module) end)
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


-- Combat focus -----------------------------------------------------------------
-- In a fight the long quest list is noise. While you're in combat every quest
-- dims except the one you're working on: the last one whose objectives moved,
-- or the one you've chosen to follow on the map. Hovering the list brings it
-- all back; after the fight it returns as it was. Only alpha changes, so
-- nothing here touches the tracker's buttons in combat.
local DIM = 0.22
local counts, focusQuest = {}, nil

local function questProgress(questID)
	if not (C_QuestLog and C_QuestLog.GetQuestObjectives) then return nil end
	local ok, list = pcall(C_QuestLog.GetQuestObjectives, questID)
	if not ok or type(list) ~= "table" then return nil end
	local parts = {}
	for i, objective in ipairs(list) do
		local done = Stoa.safe.plain(objective.numFulfilled)
		local text = Stoa.safe.plain(objective.text)
		parts[i] = tostring(done or text or "")
	end
	return table.concat(parts, "|")
end

local function watched()
	local out = {}
	if not (C_QuestLog and C_QuestLog.GetNumQuestWatches and C_QuestLog.GetQuestIDForQuestWatchIndex) then return out end
	for i = 1, (Stoa.safe.plain(C_QuestLog.GetNumQuestWatches()) or 0) do
		local id = Stoa.safe.plain(C_QuestLog.GetQuestIDForQuestWatchIndex(i))
		if id then out[#out + 1] = id end
	end
	return out
end

-- Notes which watched quest just moved on.
local function noteProgress()
	for _, id in ipairs(watched()) do
		local now = questProgress(id)
		if now and counts[id] and counts[id] ~= now then focusQuest = id end
		counts[id] = now
	end
end

local function chosenQuest()
	if C_SuperTrack and C_SuperTrack.GetSuperTrackedQuestID then
		local ok, id = pcall(C_SuperTrack.GetSuperTrackedQuestID)
		id = ok and Stoa.safe.plain(id)
		if id and id ~= 0 then return id end
	end
end

function Top:FocusTracker()
	local tracker = _G.ObjectiveTrackerFrame
	if not tracker or (tracker.IsForbidden and tracker:IsForbidden()) then return end
	local fighting = self.db.trackerFocus and Top.inFight and not tracker:IsMouseOver()
	local keep = focusQuest or chosenQuest()
	if tracker.Header then tracker.Header:SetAlpha(fighting and DIM or 1) end
	for _, module in ipairs(tracker.modules or {}) do
		if module.Header then module.Header:SetAlpha(fighting and DIM or 1) end
		if module.EnumerateActiveBlocks then
			module:EnumerateActiveBlocks(function(block)
				local id = block and Stoa.safe.plain(block.id)
				block:SetAlpha((not fighting or (keep and id == keep)) and 1 or DIM)
			end)
		end
	end
	self.trackerFocused = fighting
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
		-- The menu and bags settle after login; fit the tracker to where they end up.
		C_Timer.After(2, function() if Top.trackerDressed then guarded(Top.FitTracker, Top) end end)
	end)
	Stoa:On("QUEST_LOG_UPDATE", function()
		guarded(noteProgress)
		if Top.trackerFocused then guarded(Top.FocusTracker, Top) end
	end)
	Stoa:On("PLAYER_REGEN_DISABLED", function() Top.inFight = true; guarded(Top.FocusTracker, Top) end)
	Stoa:On("PLAYER_REGEN_ENABLED", function() Top.inFight = false; guarded(Top.FocusTracker, Top) end)
	-- Hovering the list in a fight shows it all; leaving dims it again.
	Stoa:On("STOA_TICK", function()
		local tracker = _G.ObjectiveTrackerFrame
		if not (tracker and Top.db.trackerFocus) then return end
		local want = Top.inFight and not tracker:IsMouseOver()
		if want ~= (Top.trackerFocused or false) then guarded(Top.FocusTracker, Top) end
	end)
	Stoa:On("STOA_THEME_CHANGED", function()
		zoneColour()
		local tracker = _G.ObjectiveTrackerFrame
		for _, module in ipairs(tracker and tracker.modules or {}) do
			if module.EnumerateActiveBlocks then module:EnumerateActiveBlocks(titleColour) end
		end
	end)
end
