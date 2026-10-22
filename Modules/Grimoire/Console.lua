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
	art = true,
})

local SPINE_HEIGHT = 22
local ARCH_SIZE = 220
local SEAL_SIZE = 76
local ART_SEAL_SIZE = 92

-- The leather panel art. Each piece is 256 texels tall with the panel
-- running from texel 129 to the bottom; it bleeds off the screen's sides and
-- bottom. The console's open height is the panel's, and the art scales with it.
local ART_HEIGHT = 136
local ART_TEXELS, ART_TOP = 256, 129
local ART_SCALE = ART_HEIGHT / (ART_TEXELS - ART_TOP)
local ART_CENTRE = 512
local FOLD_SECONDS = 0.3
local MAX_NOTES = 4
local NOTE_SECONDS = 30

local UI = Stoa.UI
local paint, circle, line, text, caption, bar = UI.paint, UI.circle, UI.line, UI.text, UI.caption, UI.bar
local setUnitBar, classColor = UI.setUnitBar, UI.classColor

-- Build ---------------------------------------------------------------------

function Console:Build()
	local db = self.db
	local space = Stoa.space

	local frame = CreateFrame("Frame", "StoaConsole", UIParent)
	frame:SetFrameStrata("BACKGROUND")
	frame:SetPoint("BOTTOMLEFT")
	frame:SetPoint("BOTTOMRIGHT")
	frame:SetHeight(self:OpenHeight())
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
	-- Parts drawn only while the console is folded, when the art is on.
	self.flatParts = {}

	if db.art then
		-- The leather panel replaces the drawn panel, lines and arch while
		-- open; folded, the drawn spine takes over again.
		archRing:Hide()
		arch:Hide()
		self.archParts = self:BuildArt(frame)
		self.flatParts = { bg, leftEdge, rightEdge, inner }
	end

	self:BuildSeal(frame)
	self:BuildNotes(frame, space)
	self:BuildFellowship(frame, space)

	UI.applyTheme()
	Stoa:On("STOA_THEME_CHANGED", function()
		self:UpdateSeal()
		self:UpdateFellowship()
	end)
end

-- Where the pages start: below the leather's gold top border when it's on.
function Console:PageInset()
	if self.db.art then return Stoa.space.xxl, -26, 20 end
	return Stoa.space.xxl, -Stoa.space.xl, 20
end

-- The console's height when open.
function Console:OpenHeight()
	return self.db.art and ART_HEIGHT or self.db.height
end

-- Lays the leather pieces along the console: the arch in the centre and a
-- plain stretch out to each screen edge. Each piece is a leather
-- base with a line layer on top tinted in the theme's accent.
function Console:BuildArt(frame)
	local parts = {}
	local height = ART_TEXELS * ART_SCALE

	local function piece(file, sublevel)
		local base = frame:CreateTexture(nil, "BACKGROUND", nil, sublevel)
		base:SetTexture(UI.MEDIA .. "Textures\\Console" .. file)
		local lines = frame:CreateTexture(nil, "BACKGROUND", nil, sublevel + 1)
		lines:SetTexture(UI.MEDIA .. "Textures\\Console" .. file .. "Lines")
		lines:SetAllPoints(base)
		UI.tint(lines, "accent")
		base:SetHeight(height)
		parts[#parts + 1] = base
		parts[#parts + 1] = lines
		return base
	end

	local centre = piece("Centre", -3)
	centre:SetWidth(ART_CENTRE * ART_SCALE)
	centre:SetPoint("BOTTOM")

	local leftFill = piece("Fill", -5)
	leftFill:SetPoint("BOTTOMLEFT")
	leftFill:SetPoint("BOTTOMRIGHT", centre, "BOTTOMLEFT")
	local rightFill = piece("Fill", -5)
	rightFill:SetPoint("BOTTOMLEFT", centre, "BOTTOMRIGHT")
	rightFill:SetPoint("BOTTOMRIGHT")
	return parts
end

function Console:BuildSeal(frame)
	-- With the leather art the seal sits in the art's arch, a size larger,
	-- and the arch's own gold ring stands in for the seal's outer rings.
	local art = self.db.art
	local size = art and ART_SEAL_SIZE or SEAL_SIZE
	local seal = CreateFrame("Frame", nil, frame)
	seal:SetSize(size + 12, size + 12)
	seal:SetPoint("CENTER", frame, "TOP", 0, art and 4 or 6)
	self.seal = seal

	if not art then
		local outer = circle(seal, "BORDER", 0, size + 12, "hairline")
		outer:SetPoint("CENTER")
		local gap = circle(seal, "BORDER", 1, size + 10, "panel")
		gap:SetPoint("CENTER")
	end
	local ring = circle(seal, "BORDER", 2, size + 4, "accent")
	ring:SetPoint("CENTER")

	local portrait = circle(seal, "ARTWORK", 0, size)
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
	local inset, top, rowGap = self:PageInset()
	local page = CreateFrame("Frame", nil, frame)
	page:SetPoint("TOPLEFT", inset, top)
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
		fs:SetPoint("TOPLEFT", rule, "BOTTOMLEFT", 0, -6 - (i - 1) * rowGap)
		fs:SetPoint("RIGHT", page, "RIGHT")
		fs:SetWordWrap(false)
		self.notes[i] = fs
	end
	self.noteLog = {}
end

function Console:BuildFellowship(frame, space)
	local inset, top, rowGap = self:PageInset()
	local page = CreateFrame("Frame", nil, frame)
	page:SetPoint("TOPRIGHT", -inset, top)
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
		row:SetPoint("TOPLEFT", rule, "BOTTOMLEFT", 0, -6 - (i - 1) * rowGap)
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
	local target = open and self:OpenHeight() or SPINE_HEIGHT
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
		for _, part in ipairs(self.flatParts) do
			part:SetAlpha(open and 1 - progress or progress)
		end
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
