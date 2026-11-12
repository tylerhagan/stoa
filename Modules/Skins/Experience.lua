-- Stoa: Blizzard's experience bar in STOA's dress.
-- The experience bar, wherever Edit Mode puts it (and the reputation, honor and
-- other bars that share its place) loses its frame, its segmented art and
-- its glossy fill for a thin flat bar in the same rounded dark track as the
-- nameplates and the swing timer. Experience fills in the accent like the
-- medallion's bezel, the rested stretch runs on in mana blue, and the
-- segment dividers become fine dark notches over the filled part. In a
-- fight it fades away with the console and comes back after. Edit Mode
-- still places it.
local _, ns = ...
local Stoa = ns.Stoa
local hooksecurefunc = Stoa.SafeHook
local UI = Stoa.UI

local XPBar = Stoa:NewModule("XPBar", {
	-- In a fight the bar fades away with the console.
	combatFade = true,
	-- A paler stretch past the fill for the experience your finished quests
	-- will give when you hand them in.
	questXP = true,
})

local HEIGHT = 6
local PAD = 2
local CONTAINERS = { "MainStatusTrackingBarContainer", "SecondaryStatusTrackingBarContainer" }

local guarded = Stoa.safe.guarded

-- Textures moved here never draw again, whatever Blizzard does to them.
local vault = CreateFrame("Frame")
vault:Hide()
local function bury(tex)
	if tex and tex.SetParent then tex:SetParent(vault) end
end

-- Reputation by standing, Hated to Exalted: red, orange, bone, then green.
-- A paragon or friendship bar Blizzard draws blue runs in mana blue.
local GREEN = { 0.56, 0.76, 0.50 }
local STANDING = { "hostile", "hostile", "danger", "text", GREEN, GREEN, GREEN, GREEN }

local function barColour(bar)
	local enum = StatusTrackingBarInfo and StatusTrackingBarInfo.BarsEnum
	local kind = bar.stoaColour
	if not kind and enum then
		if bar.barIndex == enum.Honor then kind = "hostile" end
	end
	kind = kind or "accent"
	if type(kind) == "table" then return kind[1], kind[2], kind[3] end
	return Stoa:Color(kind)
end

local function colourBar(bar)
	local status = bar.StatusBar
	if not status then return end
	if not status.stoaTexture then
		status:SetStatusBarTexture(UI.WHITE)
		status.stoaTexture = true
	end
	local r, g, b = barColour(bar)
	status:SetStatusBarColor(r, g, b, 1)
	local fill = status:GetStatusBarTexture()
	if fill then fill:SetVertexColor(r, g, b, 1) end
	local rested = bar.ExhaustionLevelFillBar
	if rested then
		local mr, mg, mb = Stoa:Color("mana")
		rested:SetVertexColor(mr, mg, mb, 0.55)
	end
	if bar.stoaTick then
		local mr, mg, mb = Stoa:Color("mana")
		bar.stoaTick:SetVertexColor(mr, mg, mb, 0.95)
	end
end

-- Blizzard swaps the fill's art as you level, go rested or change faction;
-- each swap is turned back to the flat fill straight away.
local function keepFlat(status)
	status.stoaTexture = nil
	local bar = status:GetParent()
	if bar then colourBar(bar) end
end

local function fitBar(bar)
	local status = bar.StatusBar
	if status then status:SetHeight(HEIGHT) end
end

local function dressBar(bar)
	if not bar or bar.stoaDressed or not bar.StatusBar then return end
	bar.stoaDressed = true
	local status = bar.StatusBar
	bury(status.Background)
	fitBar(bar)

	-- The track sits on the bar's own frame, under the rested stretch and
	-- the fill (the fill's frame draws over its parent).
	local track = UI.pillFill(bar, 0)
	track:ClearAllPoints()
	track:SetPoint("TOPLEFT", status, "TOPLEFT", -PAD, PAD)
	track:SetPoint("BOTTOMRIGHT", status, "BOTTOMRIGHT", PAD, -PAD)
	UI.tint(track, "panel", 0.85)
	UI.pillEdge(status, PAD):Set(0, 0, 0, 0.9)

	if status.SetBarTexture then hooksecurefunc(status, "SetBarTexture", keepFlat) end

	-- Reputation: the standing decides the colour.
	if bar.UpdateBarTextures then
		hooksecurefunc(bar, "UpdateBarTextures", function(own, level, blue)
			own.stoaColour = blue and "mana" or STANDING[level or 4] or "text"
			colourBar(own)
		end)
	end

	-- Experience: the rested stretch flat and the height of the fill, and a
	-- fine blue line where it ends instead of Blizzard's pip.
	local rested = bar.ExhaustionLevelFillBar
	if rested then
		rested:SetTexture(UI.WHITE)
		rested:ClearAllPoints()
		rested:SetPoint("TOPLEFT", status, "TOPLEFT")
		rested:SetPoint("BOTTOMLEFT", status, "BOTTOMLEFT")
	end
	local pip = bar.ExhaustionTick
	if pip then
		for _, key in ipairs({ "Normal", "Highlight" }) do
			if pip[key] then pip[key]:SetAlpha(0) end
		end
		local tick = pip:CreateTexture(nil, "OVERLAY")
		tick:SetTexture(UI.WHITE)
		tick:SetSize(1, HEIGHT + PAD * 2)
		tick:SetPoint("CENTER")
		bar.stoaTick = tick
	end

	local text = bar.OverlayFrame and bar.OverlayFrame.Text
	if text then
		Stoa:SetFont(text, "sans", Stoa.typeSize.caption)
		UI.legible(text)
	end
	colourBar(bar)
end

-- How far the bar on show has filled, 0 to 1.
local function filled(container)
	local bar = container.GetShownBar and container:GetShownBar()
	local status = bar and bar.StatusBar
	if not status then return 0 end
	local low, high = status:GetMinMaxValues()
	low, high = Stoa:PlainNumber(low), Stoa:PlainNumber(high)
	local value = Stoa:PlainNumber(status:GetValue())
	if not (low and high and value) or high <= low then return 0 end
	return (value - low) / (high - low)
end

-- Blizzard's dividers (20 on Forever's bar) as fine dark notches that only
-- show where the bar has filled; the empty track stays plain.
local function notch(container)
	local pool = container.HorizontalDividersPool
	if not pool or not pool.EnumerateActive then return end
	local share = filled(container)
	local width = Stoa:PlainNumber(container:GetWidth()) or 0
	for divider in pool:EnumerateActive() do
		local tex = divider.BarDividerTexture
		if tex then
			if not divider.stoaNotch then
				tex:SetTexture(UI.WHITE)
				tex:SetVertexColor(0, 0, 0, 0.55)
				tex:ClearAllPoints()
				tex:SetPoint("CENTER")
				tex:SetSize(1, HEIGHT)
				divider.stoaNotch = true
			end
			local _, _, _, x = divider:GetPoint(1)
			x = Stoa:PlainNumber(x)
			tex:SetShown(x ~= nil and width > 0 and x / width < share)
		end
	end
end

local function dressContainer(container)
	if not container or container.stoaDressed or type(container.bars) ~= "table" then return end
	container.stoaDressed = true
	bury(container.BarFrameTexture)
	for _, bar in pairs(container.bars) do guarded(dressBar, bar) end
	if container.UpdateDividers then
		hooksecurefunc(container, "UpdateDividers", notch)
	end
	-- The notches follow the fill as it grows, and the bar on show.
	for _, bar in pairs(container.bars) do
		local status = bar.StatusBar
		if status and status.HookScript then
			status:HookScript("OnValueChanged", function() guarded(notch, container) end)
		end
	end
	if container.ApplyPendingBarToShow then
		hooksecurefunc(container, "ApplyPendingBarToShow", notch)
	end
	if container.ResizeContainerBars then
		hooksecurefunc(container, "ResizeContainerBars", function(own)
			for _, bar in pairs(own.bars) do fitBar(bar) end
		end)
	end
	notch(container)
end

function XPBar:Dress()
	for _, name in ipairs(CONTAINERS) do
		guarded(dressContainer, _G[name])
	end
	UI.applyTheme()
	self.dressed = true
end

function XPBar:Recolour()
	for _, name in ipairs(CONTAINERS) do
		local container = _G[name]
		if container and container.stoaDressed then
			for _, bar in pairs(container.bars) do
				if bar.stoaDressed then guarded(colourBar, bar) end
			end
		end
	end
end

-- In a fight the bar fades out over a quarter second, and back after.
local FADE = 0.25
function XPBar:Fade(hidden)
	local manager = _G.StatusTrackingBarManager
	if not manager then return end
	local target = hidden and 0 or 1
	local fader = self.fader
	if not fader then
		fader = CreateFrame("Frame")
		fader:Hide()
		fader:SetScript("OnUpdate", function(own, elapsed)
			local now = Stoa:PlainNumber(manager:GetAlpha()) or 1
			local step = elapsed / FADE
			local nextAlpha = now < own.target and math.min(own.target, now + step) or math.max(own.target, now - step)
			manager:SetAlpha(nextAlpha)
			if nextAlpha == own.target then own:Hide() end
		end)
		self.fader = fader
	end
	fader.target = target
	fader:Show()
end

-- Finished quests ---------------------------------------------------------------
-- Quests you've finished but not handed in show as a paler gold stretch
-- running on from the fill, so you see how far turning them in takes you.
-- Hovering the bar adds a line with the count and the experience. Waits
-- while a companion (OneForAll's quest XP) draws its own.
local call = Stoa.safe.call

function XPBar:QuestXP()
	local total, count = 0, 0
	local log = C_QuestLog
	if not (log and log.GetNumQuestLogEntries and log.GetInfo and log.IsComplete and GetQuestLogRewardXP) then return 0, 0 end
	for index = 1, Stoa:PlainNumber(call(log.GetNumQuestLogEntries)) or 0 do
		local info = call(log.GetInfo, index)
		local id = type(info) == "table" and not info.isHeader and info.questID
		if id and call(log.IsComplete, id) then
			local xp = Stoa:PlainNumber(call(GetQuestLogRewardXP, id))
			if xp and xp > 0 then
				total, count = total + xp, count + 1
			end
		end
	end
	return total, count
end

-- The experience bar on show (the one with a rested stretch), if any.
local function xpBar()
	for _, name in ipairs(CONTAINERS) do
		local container = _G[name]
		if container and type(container.bars) == "table" then
			for _, bar in pairs(container.bars) do
				if bar.ExhaustionLevelFillBar and bar.StatusBar and bar:IsVisible() then return bar end
			end
		end
	end
end

function XPBar:UpdateQuests()
	local bar = xpBar()
	local on = self.db.questXP ~= false and not Stoa:SharedBy("questXP")
	if self.questStretch and (not bar or self.questStretch:GetParent() ~= bar.StatusBar) then self.questStretch:Hide() end
	if not bar then return end
	local status = bar.StatusBar
	local stretch = status.stoaQuests
	if not stretch then
		stretch = status:CreateTexture(nil, "ARTWORK", nil, 3)
		stretch:SetTexture(UI.WHITE)
		status.stoaQuests = stretch
		-- Kept in step as the bar fills and when Edit Mode resizes it.
		status:HookScript("OnValueChanged", function() guarded(self.UpdateQuests, self) end)
		status:HookScript("OnSizeChanged", function() guarded(self.UpdateQuests, self) end)
		bar:HookScript("OnEnter", function(own) guarded(self.QuestTooltip, self, own) end)
	end
	self.questStretch = stretch
	local xp = on and self:QuestXP() or 0
	local most = Stoa:PlainNumber(UnitXPMax("player")) or 0
	local width = Stoa:PlainNumber(status:GetWidth()) or 0
	local share = 0
	local low, high = status:GetMinMaxValues()
	low, high = Stoa:PlainNumber(low), Stoa:PlainNumber(high)
	local value = Stoa:PlainNumber(status:GetValue())
	if low and high and value and high > low then share = (value - low) / (high - low) end
	if xp <= 0 or most <= 0 or width <= 0 or share >= 1 then stretch:Hide() return end
	local span = math.min(xp / most, 1 - share)
	local r, g, b = Stoa:Color("accent")
	stretch:SetVertexColor(r, g, b, 0.42)
	stretch:ClearAllPoints()
	stretch:SetPoint("TOPLEFT", status, "TOPLEFT", width * share, 0)
	stretch:SetPoint("BOTTOMLEFT", status, "BOTTOMLEFT", width * share, 0)
	stretch:SetWidth(math.max(1, width * span))
	stretch:Show()
end

function XPBar:QuestTooltip(bar)
	if self.db.questXP == false or Stoa:SharedBy("questXP") then return end
	-- Blizzard's tooltip for the bar sits in the default corner (its owner is
	-- the screen, not the bar), and is only made while you're rested; without
	-- one STOA starts its own there.
	C_Timer.After(0, function()
		if not (bar:IsMouseOver()) then return end
		local xp, count = self:QuestXP()
		if count == 0 then return end
		if not GameTooltip:IsShown() then
			if not GameTooltip_SetDefaultAnchor then return end
			GameTooltip_SetDefaultAnchor(GameTooltip, UIParent)
			local most = Stoa:PlainNumber(UnitXPMax("player")) or 0
			local now = Stoa:PlainNumber(UnitXP("player")) or 0
			GameTooltip:SetText(("%s / %s"):format(BreakUpLargeNumbers and BreakUpLargeNumbers(now) or now, BreakUpLargeNumbers and BreakUpLargeNumbers(most) or most))
		else
			GameTooltip:AddLine(" ")
		end
		local most = Stoa:PlainNumber(UnitXPMax("player")) or 0
		local share = most > 0 and ("  (%d%%)"):format(math.floor(xp / most * 100 + 0.5)) or ""
		local number = BreakUpLargeNumbers and BreakUpLargeNumbers(xp) or tostring(xp)
		local r, g, b = Stoa:Color("accent")
		GameTooltip:AddLine(("%d finished %s: +%s XP%s"):format(count, count == 1 and "quest" or "quests", number, share), r, g, b)
		GameTooltip:Show()
	end)
end

function XPBar:QuestsSoon()
	if self.questsPending then return end
	self.questsPending = true
	C_Timer.After(0.5, function()
		self.questsPending = false
		guarded(self.UpdateQuests, self)
	end)
end

function XPBar:OnEnable()
	Stoa:On("STOA_THEME_CHANGED", function() XPBar:Recolour() end)
	self:Dress()
	for _, event in ipairs({ "QUEST_LOG_UPDATE", "PLAYER_XP_UPDATE", "PLAYER_LEVEL_UP", "PLAYER_ENTERING_WORLD", "UPDATE_FACTION" }) do
		Stoa:On(event, function() XPBar:QuestsSoon() end)
	end
	if _G.StatusTrackingBarManager and _G.StatusTrackingBarManager.UpdateBarsShown then
		hooksecurefunc(_G.StatusTrackingBarManager, "UpdateBarsShown", function() XPBar:QuestsSoon() end)
	end
	Stoa:On("STOA_STATE_CHANGED", function(state)
		if XPBar.db.combatFade == false then return end
		XPBar:Fade(state == Stoa.STATE_COMBAT)
	end)
end
