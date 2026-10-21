-- Stoa: the Grimoire console, the world state.
-- A full-width ink panel along the bottom of the screen. Your portrait seal
-- rises out of its centre with health and mana either side; the left page
-- holds margin notes, the right page your fellowship and who is online.
-- In combat it folds to a thin spine; hold Alt to peek.
--
-- The console sits on the BACKGROUND strata so Blizzard's action bars,
-- placed in its centre with Edit Mode, draw on top of it. Housing.lua moves
-- chat onto the left page.
local _, ns = ...
local Stoa = ns.Stoa

local Console = Stoa:NewModule("Grimoire", {
	height = 150,
	houseChat = true,
	hideBarArt = true,
})

local SPINE_HEIGHT = 22
local ARCH_SIZE = 220
local SEAL_SIZE = 76
local FOLD_SECONDS = 0.3
local MAX_NOTES = 4
local NOTE_SECONDS = 30

local CIRCLE_MASK = "Interface\\CharacterFrame\\TempPortraitAlphaMask"
local WHITE = "Interface\\Buttons\\WHITE8x8"

-- Helpers -------------------------------------------------------------------

local themed = {}

-- Paints a texture or font string with a theme token now and on every theme
-- change.
local function paint(region, token, alpha)
	local entry = { region = region, token = token, alpha = alpha }
	table.insert(themed, entry)
	return region
end

local function applyTheme()
	for _, entry in ipairs(themed) do
		local r, g, b, a = Stoa:Color(entry.token)
		a = entry.alpha or a
		if entry.region.SetColorTexture then
			entry.region:SetColorTexture(r, g, b, a)
		elseif entry.region.SetStatusBarColor then
			entry.region:SetStatusBarColor(r, g, b, a)
		else
			entry.region:SetTextColor(r, g, b, a)
		end
	end
end

local function circle(parent, layer, sublevel, size, token, alpha)
	local tex = parent:CreateTexture(nil, layer, nil, sublevel)
	tex:SetSize(size, size)
	local mask = parent:CreateMaskTexture()
	mask:SetTexture(CIRCLE_MASK, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
	mask:SetAllPoints(tex)
	tex:AddMaskTexture(mask)
	if token then paint(tex, token, alpha) end
	return tex
end

local function line(parent, token, alpha)
	local tex = parent:CreateTexture(nil, "BORDER")
	tex:SetHeight(1)
	paint(tex, token or "hairline", alpha)
	return tex
end

local function text(parent, kind, size, token, justify)
	local fs = parent:CreateFontString(nil, "OVERLAY")
	Stoa:SetFont(fs, kind, size)
	fs:SetJustifyH(justify or "LEFT")
	paint(fs, token or "text")
	return fs
end

-- Small caps label, the console's section heading.
local function caption(parent, label)
	local fs = text(parent, "sans", Stoa.typeSize.caption, "muted")
	fs:SetText(label:upper())
	return fs
end

local function bar(parent, width, height, token)
	local sb = CreateFrame("StatusBar", nil, parent)
	sb:SetSize(width, height)
	sb:SetStatusBarTexture(WHITE)
	paint(sb, token)
	local track = sb:CreateTexture(nil, "BACKGROUND")
	track:SetAllPoints()
	paint(track, "text", 0.08)
	sb:SetMinMaxValues(0, 1)
	sb:SetValue(1)
	return sb
end

-- Secret-safe unit display: StatusBar and FontString accept secret values,
-- so values go straight in and are never compared.
local function setUnitBar(sb, unit, kind)
	if kind == "health" then
		sb:SetMinMaxValues(0, UnitHealthMax(unit))
		sb:SetValue(UnitHealth(unit))
	else
		sb:SetMinMaxValues(0, UnitPowerMax(unit))
		sb:SetValue(UnitPower(unit))
	end
end

local function classColor(unit)
	local _, classFile = UnitClass(unit)
	if not Stoa:Theme().classTint or not classFile or Stoa:IsSecret(classFile) then
		return Stoa:Color("text")
	end
	local color = RAID_CLASS_COLORS[classFile]
	if not color then return Stoa:Color("text") end
	return color.r, color.g, color.b
end

-- Build ---------------------------------------------------------------------

function Console:Build()
	local db = self.db
	local space = Stoa.space

	local frame = CreateFrame("Frame", "StoaConsole", UIParent)
	frame:SetFrameStrata("BACKGROUND")
	frame:SetPoint("BOTTOMLEFT")
	frame:SetPoint("BOTTOMRIGHT")
	frame:SetHeight(db.height)
	self.frame = frame

	-- Ink panel and its top hairlines. The top line is split around the arch
	-- so it doesn't cut across it.
	local bg = frame:CreateTexture(nil, "BACKGROUND", nil, -6)
	bg:SetAllPoints()
	paint(bg, "panel")

	local leftEdge = line(frame)
	leftEdge:SetPoint("TOPLEFT")
	leftEdge:SetPoint("TOPRIGHT", frame, "TOP", -ARCH_SIZE / 2, 0)
	local rightEdge = line(frame)
	rightEdge:SetPoint("TOPRIGHT")
	rightEdge:SetPoint("TOPLEFT", frame, "TOP", ARCH_SIZE / 2, 0)
	local inner = line(frame, "hairline", 0.1)
	inner:SetPoint("TOPLEFT", 0, -5)
	inner:SetPoint("TOPRIGHT", 0, -5)

	-- The arch: a hairline circle behind a panel circle, both centred on the
	-- console's top edge; the panel hides their lower halves.
	local archRing = circle(frame, "BACKGROUND", -8, ARCH_SIZE + 2, "hairline")
	archRing:SetPoint("CENTER", frame, "TOP")
	local arch = circle(frame, "BACKGROUND", -7, ARCH_SIZE, "panel")
	arch:SetPoint("CENTER", frame, "TOP")

	-- When folded the arch fades away and this hairline closes the gap, so the
	-- spine reads as one clean line.
	local bridge = line(frame)
	bridge:SetPoint("TOPLEFT", leftEdge, "TOPRIGHT")
	bridge:SetPoint("TOPRIGHT", rightEdge, "TOPLEFT")
	bridge:SetAlpha(0)
	self.archParts = { archRing, arch }
	self.bridge = bridge

	self:BuildSeal(frame)
	self:BuildNotes(frame, space)
	self:BuildFellowship(frame, space)

	applyTheme()
	Stoa:On("STOA_THEME_CHANGED", function()
		applyTheme()
		self:UpdateSeal()
		self:UpdateFellowship()
	end)
end

function Console:BuildSeal(frame)
	local seal = CreateFrame("Frame", nil, frame)
	seal:SetSize(SEAL_SIZE + 12, SEAL_SIZE + 12)
	seal:SetPoint("CENTER", frame, "TOP", 0, 6)
	self.seal = seal

	local outer = circle(seal, "BORDER", 0, SEAL_SIZE + 12, "hairline")
	outer:SetPoint("CENTER")
	local gap = circle(seal, "BORDER", 1, SEAL_SIZE + 10, "panel")
	gap:SetPoint("CENTER")
	local ring = circle(seal, "BORDER", 2, SEAL_SIZE + 4, "accent")
	ring:SetPoint("CENTER")

	local portrait = circle(seal, "ARTWORK", 0, SEAL_SIZE)
	portrait:SetPoint("CENTER")
	self.portrait = portrait

	local role = text(seal, "italic", Stoa.typeSize.label, "accent", "CENTER")
	role:SetPoint("TOP", seal, "BOTTOM", 0, -2)
	self.roleText = role

	-- Health on the left, filling towards the seal; mana on the right.
	local health = bar(frame, 150, 3, "health")
	health:SetReverseFill(true)
	health:SetPoint("RIGHT", seal, "LEFT", -24, -4)
	local healthText = text(frame, "serif", Stoa.typeSize.title, "text", "RIGHT")
	healthText:SetPoint("BOTTOMRIGHT", health, "TOPRIGHT", 0, 4)
	local healthCap = caption(frame, "Health")
	healthCap:SetPoint("TOPRIGHT", health, "BOTTOMRIGHT", 0, -5)

	local mana = bar(frame, 150, 3, "mana")
	mana:SetPoint("LEFT", seal, "RIGHT", 24, -4)
	local manaText = text(frame, "serif", Stoa.typeSize.title, "mana")
	manaText:SetPoint("BOTTOMLEFT", mana, "TOPLEFT", 0, 4)
	local manaCap = caption(frame, "Mana")
	manaCap:SetPoint("TOPLEFT", mana, "BOTTOMLEFT", 0, -5)

	self.health, self.healthText = health, healthText
	self.mana, self.manaText = mana, manaText
	self.resourceParts = { health, healthText, healthCap, mana, manaText, manaCap }
end

function Console:BuildNotes(frame, space)
	local page = CreateFrame("Frame", nil, frame)
	page:SetPoint("TOPLEFT", space.xxl, -space.xl)
	page:SetSize(420, 110)
	self.leftPage = page

	local heading = caption(page, "Notes")
	heading:SetPoint("TOPLEFT")
	local rule = line(page)
	rule:SetPoint("TOPLEFT", heading, "BOTTOMLEFT", 0, -6)
	rule:SetPoint("RIGHT", page, "RIGHT")

	self.notes = {}
	for i = 1, MAX_NOTES do
		local fs = text(page, "italic", Stoa.typeSize.label, "text")
		fs:SetPoint("TOPLEFT", rule, "BOTTOMLEFT", 0, -6 - (i - 1) * 20)
		fs:SetPoint("RIGHT", page, "RIGHT")
		fs:SetWordWrap(false)
		self.notes[i] = fs
	end
	self.noteLog = {}
end

function Console:BuildFellowship(frame, space)
	local page = CreateFrame("Frame", nil, frame)
	page:SetPoint("TOPRIGHT", -space.xxl, -space.xl)
	page:SetSize(470, 110)
	self.rightPage = page

	-- Fellowship: up to four party members.
	local heading = caption(page, "Fellowship")
	heading:SetPoint("TOPLEFT")
	local rule = line(page)
	rule:SetPoint("TOPLEFT", heading, "BOTTOMLEFT", 0, -6)
	rule:SetWidth(280)

	self.members = {}
	for i = 1, 4 do
		local row = CreateFrame("Frame", nil, page)
		row:SetSize(280, 18)
		row:SetPoint("TOPLEFT", rule, "BOTTOMLEFT", 0, -6 - (i - 1) * 20)
		local name = text(row, "serif", Stoa.typeSize.label, "text")
		name:SetPoint("LEFT")
		name:SetWidth(110)
		name:SetWordWrap(false)
		local hp = bar(row, 160, 3, "health")
		hp:SetPoint("LEFT", name, "RIGHT", 10, 0)
		row.name, row.hp, row.unit = name, hp, "party" .. i
		self.members[i] = row
	end
	self.alone = text(page, "italic", Stoa.typeSize.label, "muted")
	self.alone:SetPoint("TOPLEFT", rule, "BOTTOMLEFT", 0, -6)
	self.alone:SetText("Travelling alone")

	-- Friends and guild online.
	local socialHeading = caption(page, "Friends and guild")
	socialHeading:SetPoint("TOPLEFT", page, "TOPLEFT", 310, 0)
	local socialRule = line(page)
	socialRule:SetPoint("TOPLEFT", socialHeading, "BOTTOMLEFT", 0, -6)
	socialRule:SetPoint("RIGHT", page, "RIGHT")
	local count = text(page, "serif", Stoa.typeSize.hero, "text")
	count:SetPoint("TOPLEFT", socialRule, "BOTTOMLEFT", 0, -6)
	local sub = text(page, "italic", Stoa.typeSize.label, "muted")
	sub:SetPoint("TOPLEFT", count, "BOTTOMLEFT", 0, -2)
	sub:SetText("online now")
	self.onlineCount = count
end

-- Updates -------------------------------------------------------------------

function Console:UpdateSeal()
	SetPortraitTexture(self.portrait, "player")
	local role = Stoa:GetRole()
	self.roleText:SetText(role and Stoa.ROLE_LABELS[role] or "")
end

function Console:UpdateResources()
	setUnitBar(self.health, "player", "health")
	self.healthText:SetText(UnitHealth("player"))
	setUnitBar(self.mana, "player", "power")
	self.manaText:SetText(UnitPower("player"))
end

function Console:UpdateFellowship()
	local any = false
	for _, row in ipairs(self.members) do
		if UnitExists(row.unit) then
			any = true
			row.name:SetText(UnitName(row.unit))
			row.name:SetTextColor(classColor(row.unit))
			setUnitBar(row.hp, row.unit, "health")
			row:Show()
		else
			row:Hide()
		end
	end
	self.alone:SetShown(not any)
end

function Console:UpdateOnline()
	local friends = C_FriendList.GetNumOnlineFriends() or 0
	local _, bnetOnline = BNGetNumFriends()
	local guild = 0
	if IsInGuild() then
		local _, online = GetNumGuildMembers()
		-- The guild count includes you.
		guild = math.max((online or 1) - 1, 0)
	end
	self.onlineCount:SetText(friends + (bnetOnline or 0) + guild)
end

function Console:AddNote(_, message)
	table.insert(self.noteLog, 1, { text = message, at = GetTime() })
	while #self.noteLog > MAX_NOTES do
		table.remove(self.noteLog)
	end
	self:RenderNotes()
end

function Console:RenderNotes()
	local now = GetTime()
	for i, fs in ipairs(self.notes) do
		local note = self.noteLog[i]
		if note and now - note.at < NOTE_SECONDS then
			fs:SetText(note.text)
			fs:SetAlpha(i == 1 and 1 or 0.7)
		else
			fs:SetText(i == 1 and not note and "Nothing to note." or "")
			fs:SetAlpha(0.5)
		end
	end
end

-- Folding -------------------------------------------------------------------
-- The console is not a secure frame, so it can resize in combat.

function Console:SetOpen(open, instant)
	local target = open and self.db.height or SPINE_HEIGHT
	local frame = self.frame
	local from = frame:GetHeight()
	local start = GetTime()

	local pagesAlpha = open and 1 or 0
	local sealScale = open and 1 or 0.4

	local function step(progress)
		frame:SetHeight(from + (target - from) * progress)
		self.leftPage:SetAlpha(open and progress or 1 - progress)
		self.rightPage:SetAlpha(open and progress or 1 - progress)
		for _, part in ipairs(self.resourceParts) do
			part:SetAlpha(open and progress or 1 - progress)
		end
		for _, part in ipairs(self.archParts) do
			part:SetAlpha(open and progress or 1 - progress)
		end
		self.bridge:SetAlpha(open and 1 - progress or progress)
		local scale = self.seal:GetScale()
		self.seal:SetScale(scale + (sealScale - scale) * progress)
	end

	if instant then
		step(1)
		frame:SetScript("OnUpdate", nil)
		return
	end

	frame:SetScript("OnUpdate", function()
		local progress = math.min((GetTime() - start) / FOLD_SECONDS, 1)
		-- Ease out so the fold settles rather than stops.
		progress = 1 - (1 - progress) ^ 3
		step(progress)
		if progress >= 1 then
			frame:SetScript("OnUpdate", nil)
			self.leftPage:SetAlpha(pagesAlpha)
			self.rightPage:SetAlpha(pagesAlpha)
		end
	end)
end

local function shouldBeOpen()
	return Stoa:GetState() == Stoa.STATE_WORLD or Stoa:IsPeeking()
end

-- Lifecycle -----------------------------------------------------------------

function Console:OnEnable()
	self:Build()
	Stoa.notesInConsole = true
	self:House()

	self:UpdateSeal()
	self:UpdateResources()
	self:UpdateFellowship()
	self:UpdateOnline()
	self:RenderNotes()
	self:SetOpen(shouldBeOpen(), true)

	Stoa:On("STOA_NOTE", function(kind, message) self:AddNote(kind, message) end)
	Stoa:On("STOA_ROLE_CHANGED", function() self:UpdateSeal() end)
	Stoa:On("STOA_STATE_CHANGED", function() self:SetOpen(shouldBeOpen()) end)
	Stoa:On("STOA_PEEK_CHANGED", function() self:SetOpen(shouldBeOpen()) end)

	Stoa:On("UNIT_PORTRAIT_UPDATE", function(unit)
		if unit == "player" then self:UpdateSeal() end
	end)
	Stoa:On("PLAYER_ENTERING_WORLD", function()
		self:UpdateSeal()
		self:UpdateResources()
		self:UpdateFellowship()
		if IsInGuild() then C_GuildInfo.GuildRoster() end
	end)

	Stoa:On("UNIT_HEALTH", function(unit)
		if unit == "player" then
			setUnitBar(self.health, "player", "health")
			self.healthText:SetText(UnitHealth("player"))
		elseif unit and unit:find("^party") then
			self:UpdateFellowship()
		end
	end)
	Stoa:On("UNIT_MAXHEALTH", function(unit)
		if unit == "player" then self:UpdateResources() end
	end)
	Stoa:On("UNIT_POWER_UPDATE", function(unit)
		if unit == "player" then
			setUnitBar(self.mana, "player", "power")
			self.manaText:SetText(UnitPower("player"))
		end
	end)
	Stoa:On("UNIT_MAXPOWER", function(unit)
		if unit == "player" then self:UpdateResources() end
	end)
	Stoa:On("GROUP_ROSTER_UPDATE", function() self:UpdateFellowship() end)

	Stoa:On("FRIENDLIST_UPDATE", function() self:UpdateOnline() end)
	Stoa:On("BN_FRIEND_INFO_CHANGED", function() self:UpdateOnline() end)
	Stoa:On("GUILD_ROSTER_UPDATE", function() self:UpdateOnline() end)

	-- Notes fade after NOTE_SECONDS.
	C_Timer.NewTicker(5, function() self:RenderNotes() end)
end
