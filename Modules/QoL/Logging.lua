-- Stoa QoL: a reminder to log.
-- Warcraft Logs and similar sites read the game's combat log file, which
-- only fills while combat logging is on. Entering a dungeon or a raid with
-- it off, a plaque at the top of the screen says NOT LOGGING with a Start
-- logging button (which also turns on the game's advanced logging, noted
-- in the game settings ledger). Once on, it says LOGGING and fades away.
-- Logging Stoa started stops again when you leave, unless you'd rather not.
local _, ns = ...
local Stoa = ns.Stoa
local UI = Stoa.UI

local Logging = Stoa:NewModule("Logging", {
	remind = "both", -- "both", "raid" or "off"
	auto = false,
	stopOnLeave = true,
})

local WIDTH, HEIGHT = 340, 96

function Logging:IsLogging()
	if C_ChatInfo and C_ChatInfo.IsLoggingCombat then
		local ok, on = pcall(C_ChatInfo.IsLoggingCombat)
		if ok and not Stoa:IsSecret(on) then return on and true or false end
	end
	if LoggingCombat then
		local ok, on = pcall(LoggingCombat)
		if ok then return on and true or false end
	end
	return nil
end

-- "party", "raid" or nil, by the instance you're in.
local function instanceKind()
	local inside, kind = IsInInstance()
	if not inside or Stoa:IsSecret(kind) then return nil end
	if kind == "party" or kind == "raid" then return kind end
end

local function instanceName()
	local name = GetInstanceInfo and GetInstanceInfo()
	if type(name) == "string" and not Stoa:IsSecret(name) then return name end
end

function Logging:Wants(kind)
	local remind = self.db.remind
	if remind == "off" or not kind then return false end
	return remind == "both" or kind == remind
end

function Logging:Start()
	if not LoggingCombat then return end
	Stoa.GameSettings:Set("Logging", "advancedCombatLogging", "1")
	pcall(LoggingCombat, true)
	self.started = true
	self:Show("on")
end

function Logging:Stop()
	if LoggingCombat then pcall(LoggingCombat, false) end
	self.started = false
end

-- The plaque ------------------------------------------------------------------

function Logging:Build()
	local frame = CreateFrame("Frame", "StoaLogging", UIParent)
	frame:SetSize(WIDTH, HEIGHT)
	frame:SetPoint("TOP", UIParent, "TOP", 0, -120)
	frame:SetFrameStrata("HIGH")
	UI.roundPanel(frame, 0.94)
	UI.roundBorder(frame, "CardEdge.tga", 1)

	-- A recording light: a ring with a dot that breathes while it waits.
	local dot = UI.circle(frame, "OVERLAY", 0, 10)
	dot:SetColorTexture(1, 1, 1, 1)
	dot:SetPoint("TOPLEFT", 20, -22)
	frame.dot = dot
	local pulse = dot:CreateAnimationGroup()
	pulse:SetLooping("BOUNCE")
	local fade = pulse:CreateAnimation("Alpha")
	fade:SetFromAlpha(1)
	fade:SetToAlpha(0.25)
	fade:SetDuration(0.8)
	frame.pulse = pulse

	local word = frame:CreateFontString(nil, "OVERLAY")
	Stoa:SetFont(word, "serif", Stoa.typeSize.label)
	word:SetPoint("LEFT", dot, "RIGHT", 10, 0)
	frame.word = word

	local place = frame:CreateFontString(nil, "OVERLAY")
	Stoa:SetFont(place, "sans", Stoa.typeSize.caption)
	place:SetPoint("TOPLEFT", dot, "BOTTOMLEFT", 0, -8)
	place:SetPoint("RIGHT", frame, "RIGHT", -20, 0)
	place:SetJustifyH("LEFT")
	frame.place = place

	frame.start = UI.button(frame, "Start logging", 130, function() Logging:Start() end)
	frame.start:SetPoint("BOTTOMLEFT", 18, 14)
	frame.later = UI.button(frame, "Not now", 90, function() Logging:Hide() end)
	frame.later:SetPoint("LEFT", frame.start, "RIGHT", 8, 0)
	local never = CreateFrame("Button", nil, frame)
	never:SetSize(70, 20)
	never:SetPoint("BOTTOMRIGHT", -16, 17)
	local neverText = never:CreateFontString(nil, "OVERLAY")
	Stoa:SetFont(neverText, "sans", Stoa.typeSize.caption)
	neverText:SetPoint("RIGHT")
	neverText:SetText("Don't ask")
	never:SetScript("OnEnter", function()
		neverText:SetTextColor(Stoa:Color("text"))
		GameTooltip:SetOwner(never, "ANCHOR_TOP")
		GameTooltip:SetText("Stop these reminders. Settings > Comforts brings them back.")
		GameTooltip:Show()
	end)
	never:SetScript("OnLeave", function()
		neverText:SetTextColor(Stoa:Color("muted"))
		GameTooltip:Hide()
	end)
	never:SetScript("OnClick", function()
		Logging.db.remind = "off"
		Logging:Hide()
		Stoa:Print("Logging reminders are off. Settings > Comforts > Remind me to log brings them back.")
	end)
	frame.never, frame.neverText = never, neverText

	frame:Hide()
	self.frame = frame
	Stoa:RegisterMover("logging", frame, "Logging reminder")
	Stoa:On("STOA_THEME_CHANGED", function() if frame:IsShown() then self:Paint() end end)
end

function Logging:Paint()
	local frame = self.frame
	local on = frame.state == "on"
	frame.word:SetText(on and "LOGGING" or "NOT LOGGING")
	frame.word:SetTextColor(Stoa:Color(on and "accent" or "danger"))
	frame.dot:SetVertexColor(Stoa:Color(on and "accent" or "danger"))
	frame.place:SetTextColor(Stoa:Color("muted"))
	frame.neverText:SetTextColor(Stoa:Color("muted"))
	local name = instanceName()
	if on then
		frame.place:SetText(("Your combat log is on%s. Upload it when you're done."):format(name and (" for " .. name) or ""))
	else
		frame.place:SetText(("%s isn't being logged, so it won't reach Warcraft Logs."):format(name or "This instance"))
	end
	frame.start:SetShown(not on)
	frame.later:SetShown(not on)
	frame.never:SetShown(not on)
	frame:SetHeight(on and 64 or HEIGHT)
end

function Logging:Show(state)
	if not self.frame then self:Build() end
	local frame = self.frame
	frame.state = state
	if frame.fadeTimer then frame.fadeTimer:Cancel() end
	frame:SetAlpha(1)
	self:Paint()
	frame:Show()
	if state == "on" then
		frame.pulse:Stop()
		frame.dot:SetAlpha(1)
		frame.fadeTimer = C_Timer.NewTimer(3, function()
			UI.fade(frame, 0, 0.6)
			C_Timer.After(0.7, function() if frame.state == "on" then frame:Hide() end end)
		end)
	else
		frame.pulse:Play()
	end
end

function Logging:Hide()
	if self.frame then
		self.frame.pulse:Stop()
		self.frame:Hide()
	end
end

-- Where you are ---------------------------------------------------------------

function Logging:Check()
	local kind = instanceKind()
	if not kind then
		self:Hide()
		self.askedFor = nil
		if self.started and self.db.stopOnLeave then self:Stop() end
		return
	end
	if not self:Wants(kind) or self:IsLogging() ~= false then return end
	-- Once per visit: "Not now" holds until you leave.
	local key = instanceName() or kind
	if self.askedFor == key then return end
	self.askedFor = key
	if self.db.auto then
		self:Start()
	else
		self:Show("off")
	end
end

function Logging:OnEnable()
	local function check() C_Timer.After(2, function() xpcall(self.Check, Stoa.catch, self) end) end
	Stoa:On("PLAYER_ENTERING_WORLD", check)
	Stoa:On("ZONE_CHANGED_NEW_AREA", check)
	Stoa.commands.log = function(rest)
		local arg = strtrim(rest or "")
		if arg == "stop" then
			self:Stop()
			Stoa:Print("Combat logging is off.")
		elseif arg == "test" then
			self:Show("off")
		else
			self:Start()
			Stoa:Print("Combat logging is on. /stoa log stop turns it off.")
		end
	end
end
