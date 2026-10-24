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

local Top = Stoa:NewModule("Top")

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
	if button.Count then
		Stoa:SetFont(button.Count, "sans", Stoa.typeSize.body, "OUTLINE")
		button.Count:SetTextColor(Stoa:Color("text"))
	end

	if button.UpdateDuration then hooksecurefunc(button, "UpdateDuration", auraDuration) end
	if button.UpdateExpirationTime then hooksecurefunc(button, "UpdateExpirationTime", auraDuration) end
	if button.UpdateAuraType then hooksecurefunc(button, "UpdateAuraType", auraEdge) end
	auraEdge(button)
	auraDuration(button)
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
		Stoa:SetFont(MinimapZoneText, "serif", Stoa.typeSize.body + 1)
		MinimapZoneText:SetShadowOffset(0, 0)
	end
	if _G.Minimap_Update then hooksecurefunc("Minimap_Update", zoneColour) end
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

function Top:OnEnable()
	guarded(self.Buffs, self)
	guarded(self.Tracker, self)
	guarded(self.MinimapHeader, self)
	if _G.TimeManagerClockTicker then guarded(self.Clock, self) end
	Stoa:On("ADDON_LOADED", function(name)
		if name == "Blizzard_TimeManager" then guarded(Top.Clock, Top) end
		if name == "Blizzard_ObjectiveTracker" and not Top.trackerDressed then guarded(Top.Tracker, Top) end
	end)
	-- Buff buttons can be made after login (the consolidation tooltip, edit mode).
	Stoa:On("PLAYER_ENTERING_WORLD", function() C_Timer.After(1, function() guarded(Top.Buffs, Top) end) end)
	Stoa:On("STOA_THEME_CHANGED", function()
		zoneColour()
		local tracker = _G.ObjectiveTrackerFrame
		for _, module in ipairs(tracker and tracker.modules or {}) do
			if module.EnumerateActiveBlocks then module:EnumerateActiveBlocks(titleColour) end
		end
	end)
end
