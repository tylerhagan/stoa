-- Stoa QoL: the away screen. When you go away (/afk, or idle long enough
-- for the game to mark you) out of a fight and outside dungeons and raids,
-- the interface steps aside and the camera turns slowly around your
-- character over a band of the console's leather: the wordmark, your name,
-- level and zone, how long you've been away, your rest, and any whispers
-- that came meanwhile. Moving, a fight or Back brings everything back.
local _, ns = ...
local Stoa = ns.Stoa
local UI = Stoa.UI

local Away = Stoa:NewModule("Away", {
	enabled = true,
	spin = true,
	inInstances = false,
})

local BAND = 150
local SPIN = 0.03
local WHISPERS = 4

local function clock(seconds)
	seconds = math.max(0, math.floor(seconds))
	local h, m, s = math.floor(seconds / 3600), math.floor(seconds / 60) % 60, seconds % 60
	if h > 0 then return ("%d:%02d:%02d"):format(h, m, s) end
	return ("%d:%02d"):format(m, s)
end

function Away:Build()
	local frame = CreateFrame("Frame", "StoaAway", WorldFrame)
	frame:SetAllPoints(WorldFrame)
	frame:SetFrameStrata("FULLSCREEN")
	frame:SetScale(UIParent:GetEffectiveScale() / WorldFrame:GetEffectiveScale())
	frame:Hide()

	-- A soft fade from the top so the band doesn't sit on a hard edge.
	local shade = frame:CreateTexture(nil, "BACKGROUND")
	shade:SetPoint("BOTTOMLEFT")
	shade:SetPoint("BOTTOMRIGHT")
	shade:SetHeight(BAND + 120)
	shade:SetColorTexture(1, 1, 1)
	if shade.SetGradient and CreateColor then
		shade:SetGradient("VERTICAL", CreateColor(0, 0, 0, 0.6), CreateColor(0, 0, 0, 0))
	end

	local band = CreateFrame("Frame", nil, frame)
	band:SetPoint("BOTTOMLEFT")
	band:SetPoint("BOTTOMRIGHT")
	band:SetHeight(BAND)
	local leather = band:CreateTexture(nil, "BACKGROUND")
	leather:SetTexture(UI.MEDIA .. "Textures\\ConsoleLeather", "REPEAT", "REPEAT")
	leather:SetAllPoints()
	band:SetScript("OnSizeChanged", function(_, w, h)
		local scale = Stoa.modules.Grimoire and Stoa.modules.Grimoire.ART_SCALE or 0.556
		leather:SetTexCoord(0, w / scale / 1024, 0, h / scale / 256)
	end)
	local line = band:CreateTexture(nil, "BORDER")
	line:SetPoint("TOPLEFT", 0, -6)
	line:SetPoint("TOPRIGHT", 0, -6)
	UI.pixel(line, "height")
	UI.paint(line, "accent", 0.45)
	local fine = band:CreateTexture(nil, "BORDER")
	fine:SetPoint("TOPLEFT", 0, -10)
	fine:SetPoint("TOPRIGHT", 0, -10)
	UI.pixel(fine, "height")
	UI.paint(fine, "accent", 0.18)

	local mark = band:CreateTexture(nil, "ARTWORK")
	mark:SetTexture(UI.MEDIA .. "Textures\\Wordmark")
	mark:SetSize(176, 44)
	mark:SetPoint("LEFT", 48, -4)
	UI.tint(mark, "accent")

	local name = UI.text(band, "serif", Stoa.typeSize.display + 8, "text", "LEFT")
	name:SetPoint("TOPLEFT", mark, "TOPRIGHT", 48, 10)
	local about = UI.text(band, "sans", Stoa.typeSize.label, "muted", "LEFT")
	about:SetPoint("TOPLEFT", name, "BOTTOMLEFT", 0, -8)
	local rest = UI.text(band, "sans", Stoa.typeSize.label, "muted", "LEFT")
	rest:SetPoint("TOPLEFT", about, "BOTTOMLEFT", 0, -6)

	local caption = UI.caption(band, "Away")
	caption:SetPoint("TOP", band, "TOP", 0, -34)
	local timer = UI.text(band, "serif", Stoa.typeSize.display + 8, "text", "CENTER")
	timer:SetPoint("TOP", caption, "BOTTOM", 0, -6)

	local heard = UI.caption(band, "")
	heard:SetPoint("TOPLEFT", band, "TOPRIGHT", -620, -30)
	local lines = {}
	for i = 1, WHISPERS do
		local fs = UI.text(band, "sans", Stoa.typeSize.label, "text", "LEFT")
		fs:SetPoint("TOPLEFT", i == 1 and heard or lines[i - 1], "BOTTOMLEFT", 0, i == 1 and -8 or -4)
		fs:SetWidth(420)
		fs:SetWordWrap(false)
		lines[i] = fs
	end

	local back = UI.button(band, "Back", 88, function() self:Hide(true) end)
	back:SetPoint("RIGHT", band, "RIGHT", -48, -4)

	frame:SetScript("OnUpdate", function(_, elapsed)
		self.tick = (self.tick or 0) + elapsed
		if self.tick < 0.5 then return end
		self.tick = 0
		timer:SetText(clock(GetTime() - (self.since or GetTime())))
	end)

	self.frame, self.name, self.about, self.rest, self.timer = frame, name, about, rest, timer
	self.heard, self.lines = heard, lines
end

function Away:Fill()
	local plain = Stoa.safe.plain
	self.name:SetText(plain(UnitName("player")) or "")
	local level = plain(UnitLevel("player")) or ""
	local className = UnitClass("player") or ""
	local zone = GetRealZoneText and GetRealZoneText() or ""
	local guild = GetGuildInfo and GetGuildInfo("player")
	local words = { ("Level %s %s"):format(level, className), zone }
	if guild then words[#words + 1] = "<" .. guild .. ">" end
	self.about:SetText(table.concat(words, "  ·  "))
	local max = plain(UnitXPMax("player"))
	local rested = GetXPExhaustion and GetXPExhaustion() or 0
	if max and max > 0 and rested > 0 then
		self.rest:SetText(("%d%% of a level rested%s"):format(math.floor(rested / max * 100 + 0.5), IsResting() and ", resting" or ""))
	else
		self.rest:SetText(IsResting() and "Resting" or "")
	end
	self:FillWhispers()
end

function Away:FillWhispers()
	local list = self.whispers or {}
	self.heard:SetText(#list > 0 and "WHILE YOU WERE AWAY" or "")
	for i, fs in ipairs(self.lines) do
		local entry = list[#list - i + 1]
		fs:SetText(entry and ("|cffa39e94%s|r  %s"):format(entry[1], entry[2]) or "")
	end
end

function Away:Allowed()
	if not self.db.enabled or InCombatLockdown() then return false end
	if not self.db.inInstances and IsInInstance() then return false end
	if UnitIsDeadOrGhost("player") or UnitOnTaxi("player") then return false end
	return true
end

function Away:Show()
	if self.shown or not self:Allowed() then return end
	if not self.frame then self:Build() end
	self.shown, self.since, self.whispers = true, GetTime(), {}
	self:Fill()
	if UIParent:IsShown() then
		UIParent:Hide()
		self.hidUI = true
	end
	self.frame:SetAlpha(0)
	self.frame:Show()
	UI.fade(self.frame, 1, 0.6)
	if self.db.spin and MoveViewLeftStart then
		MoveViewLeftStart(SPIN)
		self.spinning = true
	end
end

-- dismissed: Back was pressed, so stay out of the way until you come back.
function Away:Hide(dismissed)
	if not self.shown then return end
	self.shown = false
	self.dismissed = dismissed and true or nil
	if self.spinning and MoveViewLeftStop then MoveViewLeftStop() end
	self.spinning = false
	if self.frame then self.frame:Hide() end
	if self.hidUI then
		UIParent:Show()
		self.hidUI = false
	end
	local list = self.whispers or {}
	if #list > 0 then
		Stoa:Note("away", (#list == 1 and "1 whisper" or (#list .. " whispers")) .. " came while you were away; they're in your chat.")
	end
end

function Away:Check()
	local afk = Stoa.safe.plain(UnitIsAFK("player"))
	if afk then
		if not self.dismissed then self:Show() end
	else
		self.dismissed = nil
		self:Hide()
	end
end

function Away:OnEnable()
	Stoa:On("PLAYER_FLAGS_CHANGED", function(unit)
		if unit == "player" then xpcall(self.Check, Stoa.catch, self) end
	end)
	Stoa:On("PLAYER_REGEN_DISABLED", function() self:Hide() end)
	Stoa:On("PLAYER_ENTERING_WORLD", function() self:Hide() end)
	Stoa:On("CINEMATIC_START", function() self:Hide() end)
	local function heard(text, author)
		if not self.shown or Stoa:IsSecret(text) or Stoa:IsSecret(author) then return end
		local list = self.whispers
		list[#list + 1] = { Ambiguate and Ambiguate(author or "", "short") or author, text }
		while #list > 20 do table.remove(list, 1) end
		self:FillWhispers()
	end
	Stoa:On("CHAT_MSG_WHISPER", heard)
	Stoa:On("CHAT_MSG_BN_WHISPER", function(text, author) heard(text, author) end)
end

-- /stoa away shows it now, for a look.
Stoa.commands.away = function()
	if Away.shown then Away:Hide(true) return end
	if InCombatLockdown() then return end
	local was = Away.db.inInstances
	Away.db.inInstances = true
	Away:Show()
	Away.db.inInstances = was
end
