-- Stoa: the Grimoire console, the world state.
-- A full-width ink panel along the bottom of the screen. Your portrait seal
-- rises out of its centre with health and mana either side; the left page
-- holds margin notes, the right page your fellowship and who is online.
-- In combat it folds to a thin spine.
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
	houseMenu = true,
	art = true,
	-- Quiet mana play on the mana bar, as on the Halo.
	manaRule = true,
	castCost = true,
	formMana = true,
})

local SPINE_HEIGHT = 22
local ARCH_SIZE = 220
local SEAL_SIZE = 76
local ART_SEAL_SIZE = 110

-- The leather panel art: a repeating leather tile for the panel, a gold
-- top edge along it, and the medallion around the seal, all cut from one
-- painting and drawn at one scale so the medallion's flares run straight
-- into the edge's lines. Texel sizes below are in the painting's pixels;
-- the top of the panel is texel 37 of the edge strip and 257 of the
-- medallion, and the leather starts 17 texels down, under the gold lines.
-- Tools/art/console_cut.py cuts the edge and medallion from the painting
-- (Tools/art/source/console-basis-flourish.png, cut with ring 124, width
-- 1024 and "frame") and prints these rows.
local ART_HEIGHT = 176
local ART_SCALE = 0.556
Console.ART_SCALE = ART_SCALE
-- The leather tile (Tools/art/leather_tile.py) is drawn one texel per screen
-- pixel, so its grain stays sharp at any UI scale.
local LEATHER_W, LEATHER_H = 2048, 512
local EDGE_H, EDGE_TOP, LEATHER_TOP = 64, 36, 10
local MEDALLION_WIDTH, MEDALLION_LINE = 1024, 257
-- The ring's centre row in the medallion texture; the seal sits on it.
local MEDALLION_CENTRE = 267.6
local MEDALLION_SCALE = ART_SCALE
-- How far either side of centre the medallion's shoulders reach.
local MEDALLION_REACH = 310 * MEDALLION_SCALE
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

-- Lays the leather along the console: the tile repeating edge to edge
-- (not stretched, so the grain keeps its size), the gold edge on top and
-- the medallion over the centre. Gold layers take the theme accent.
function Console:BuildArt(frame)
	local parts = {}
	local function layer(file, sublevel)
		local tex = frame:CreateTexture(nil, "BACKGROUND", nil, sublevel)
		tex:SetTexture(UI.MEDIA .. "Textures\\Console" .. file)
		parts[#parts + 1] = tex
		return tex
	end
	local function gold(base, file, sublevel)
		local lines = layer(file, sublevel)
		lines:SetAllPoints(base)
		UI.tint(lines, "accent")
	end

	local leather = layer("Leather", -6)
	leather:SetTexture(UI.MEDIA .. "Textures\\ConsoleLeather", "REPEAT", "REPEAT")
	leather:SetPoint("TOPLEFT", 0, -LEATHER_TOP * ART_SCALE)
	leather:SetPoint("BOTTOMRIGHT")
	local function tileLeather()
		local width, height = leather:GetWidth(), leather:GetHeight()
		if not width or width <= 0 then return end
		-- Screen pixels per UI unit here; the painting's scale if unknown.
		local perUnit = 1 / ART_SCALE
		local _, screenHeight = GetPhysicalScreenSize and GetPhysicalScreenSize()
		local scale = leather:GetEffectiveScale()
		if screenHeight and screenHeight > 0 and scale and scale > 0 then
			perUnit = scale * screenHeight / 768
		end
		leather:SetTexCoord(0, width * perUnit / LEATHER_W, 0, height * perUnit / LEATHER_H)
	end
	tileLeather()
	frame:HookScript("OnSizeChanged", tileLeather)

	local edge = layer("Edge", -5)
	edge:SetHeight(EDGE_H * ART_SCALE)
	edge:SetPoint("TOPLEFT", 0, EDGE_TOP * ART_SCALE)
	edge:SetPoint("TOPRIGHT", 0, EDGE_TOP * ART_SCALE)
	gold(edge, "EdgeLines", -4)

	local medallion = layer("Medallion", -3)
	medallion:SetSize(MEDALLION_WIDTH * MEDALLION_SCALE, 512 * MEDALLION_SCALE)
	medallion:SetPoint("TOP", frame, "TOP", 0, MEDALLION_LINE * MEDALLION_SCALE)
	gold(medallion, "MedallionLines", -2)
	return parts
end

function Console:BuildSeal(frame)
	-- With the leather art the seal sits in the art's arch, a size larger,
	-- and the arch's own gold ring stands in for the seal's outer rings.
	local art = self.db.art
	local size = art and ART_SEAL_SIZE or SEAL_SIZE
	local seal = CreateFrame("Frame", nil, frame)
	seal:SetSize(size + 12, size + 12)
	local sealY = art and (MEDALLION_LINE - MEDALLION_CENTRE) * MEDALLION_SCALE or 6
	seal:SetPoint("CENTER", frame, "TOP", 0, sealY)
	self.seal = seal

	-- Click the seal to target yourself; right click for your unit menu.
	-- It's a secure button, so it's pinned to the screen where the open seal
	-- sits rather than to the console (which folds in combat), and steps
	-- away in combat when the console folds.
	local button = CreateFrame("Button", "StoaSealButton", UIParent, "SecureUnitButtonTemplate")
	button:SetSize(size, size)
	button:SetPoint("CENTER", UIParent, "BOTTOM", 0, self:OpenHeight() + sealY)
	button:SetFrameStrata("LOW")
	button:SetAttribute("unit", "player")
	button:SetAttribute("type1", "target")
	button:SetAttribute("type2", "togglemenu")
	button:RegisterForClicks("AnyUp")
	button:SetScript("OnEnter", function(self)
		GameTooltip_SetDefaultAnchor(GameTooltip, self)
		GameTooltip:SetUnit("player")
	end)
	button:SetScript("OnLeave", GameTooltip_Hide)
	RegisterStateDriver(button, "visibility", "[combat] hide; show")

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

	-- The progress ring, the level plate, the moment glow (BuildRing).
	self:BuildRing(seal, portrait, size)

	-- In an inn or a city: a small word across the foot of the portrait, in
	-- the rested blue the experience bar uses.
	local rest = UI.badge(seal, "RESTING")
	rest:SetFrameLevel(seal:GetFrameLevel() + 4)
	rest:SetPoint("BOTTOM", portrait, "BOTTOM", 0, math.floor(size * 0.1) + 4)
	rest:Hide()
	self.restMark = rest

	-- Without the art the role sits under the seal. With it, the role and
	-- any missing self-buffs go on the right page (see BuildFellowship), so
	-- nothing floats over the world.
	local role = text(seal, "italic", Stoa.typeSize.label, "accent", "CENTER")
	role:SetPoint("TOP", seal, "BOTTOM", 0, -2)
	role:SetShown(not art)
	self.roleText = role

	if art then
		self:BuildResources(frame)
		return
	end

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
	self:BuildManaPlay(mana, manaCap)
end

-- With the art: health and mana sit down in the leather either side of
-- the medallion, _ O _, a little above the ring's foot. The number sits
-- nearest the seal, the caption at the outer end, and the bar fills
-- towards the seal.
local RESOURCE_WIDTH = 170
-- Out to the brackets either side of the ring.
local RING_RADIUS = 150 * ART_SCALE
local RESOURCE_Y = -44

function Console:BuildResources(frame)
	local gap = RING_RADIUS + 22
	local function resource(side, token, label)
		local inner = side == "left" and "RIGHT" or "LEFT"
		local outer = side == "left" and "LEFT" or "RIGHT"
		local sign = side == "left" and -1 or 1
		local barFrame = bar(frame, RESOURCE_WIDTH, 3, token)
		barFrame:SetPoint(inner, frame, "TOP", sign * gap, RESOURCE_Y)
		if side == "left" then barFrame:SetReverseFill(true) end
		local number = text(frame, "serif", Stoa.typeSize.title, token == "health" and "text" or "mana", inner)
		number:SetPoint("BOTTOM" .. inner, barFrame, "TOP" .. inner, 0, 4)
		local cap = caption(frame, label)
		cap:SetPoint("BOTTOM" .. outer, barFrame, "TOP" .. outer, 0, 5)
		return barFrame, number, cap
	end
	local health, healthText, healthCap = resource("left", "health", "Health")
	local mana, manaText, manaCap = resource("right", "mana", "Mana")
	self.health, self.healthText = health, healthText
	self.mana, self.manaText = mana, manaText
	self.resourceParts = { health, healthText, healthCap, mana, manaText, manaCap }
	self:BuildManaPlay(mana, manaCap)
end

-- Mana play on the mana bar (shared with the Halo, see Power.dress): a
-- spark along it for the five-second rule, a shade over what the cast will
-- spend, and, for a druid in a form, a hairline of mana under the bar with
-- the amount in the caption.
function Console:BuildManaPlay(mana, manaCap)
	local db = self.db
	local form = bar(mana, 150, 1, "mana")
	form:SetPoint("TOPLEFT", mana, "BOTTOMLEFT", 0, -1)
	form:SetPoint("TOPRIGHT", mana, "BOTTOMRIGHT", 0, -1)
	form:Hide()
	self.manaPlay = Stoa.Power.dress(mana, {
		enabled = function(key) return db[key] end,
		place = function(tex, f)
			tex:ClearAllPoints()
			tex:SetPoint("CENTER", mana, "LEFT", f * mana:GetWidth(), 0)
		end,
		shade = function(tex, from, to)
			local width = mana:GetWidth()
			tex:ClearAllPoints()
			tex:SetPoint("TOPLEFT", mana, "TOPLEFT", from * width, 0)
			tex:SetPoint("BOTTOMRIGHT", mana, "BOTTOMLEFT", to * width, 0)
		end,
		form = {
			bar = form,
			show = function(current) manaCap:SetText("MANA " .. current) end,
			hide = function() manaCap:SetText("MANA") end,
		},
	})
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

-- The right page: three short columns about you, out of combat.
--   Ready: your role, any self-buff you're missing, gear wear as ten cells
--     and bag room as one column per bag.
--   Journey: level and experience, with rest and where an hour at your pace
--     gets you marked on the bar, and the pace as a small line chart.
--   Company: your party, or who's online when you travel alone.
local COLUMN_WIDTH = 196
local COLUMN_GAP = 40

local function column(page, index, label)
	local x = (index - 1) * (COLUMN_WIDTH + COLUMN_GAP)
	local heading = caption(page, label)
	heading:SetPoint("TOPLEFT", page, "TOPLEFT", x, 0)
	local rule = line(page)
	rule:SetPoint("TOPLEFT", heading, "BOTTOMLEFT", 0, -6)
	rule:SetWidth(COLUMN_WIDTH)
	return rule
end

function Console:BuildFellowship(frame, space)
	local inset, top, rowGap = self:PageInset()
	local page = CreateFrame("Frame", nil, frame)
	page:SetPoint("TOPRIGHT", -inset, top)
	page:SetSize(COLUMN_WIDTH * 3 + COLUMN_GAP * 2, 110)
	self.rightPage = page

	-- Ready.
	local ready = column(page, 1, "Ready")
	local role = text(page, "serif", Stoa.typeSize.title, "accent")
	role:SetPoint("TOPLEFT", ready, "BOTTOMLEFT", 0, -6)
	local note = text(page, "italic", Stoa.typeSize.label, "danger")
	note:SetPoint("TOPLEFT", role, "BOTTOMLEFT", 0, -3)
	note:SetWidth(COLUMN_WIDTH)
	note:SetWordWrap(false)
	-- Gear: the most worn piece as ten cells, its share on the right.
	local Figures = Stoa.Figures
	local gear = CreateFrame("Button", nil, page)
	gear:SetSize(COLUMN_WIDTH, 12)
	gear:SetPoint("TOPLEFT", note, "BOTTOMLEFT", 0, -8)
	local gearLabel = text(gear, "sans", Stoa.typeSize.body, "muted")
	gearLabel:SetPoint("LEFT")
	gearLabel:SetText("Gear")
	local gearValue = text(gear, "sans", Stoa.typeSize.body, "text", "RIGHT")
	gearValue:SetPoint("RIGHT")
	local cells = Figures.segments(gear, 10, COLUMN_WIDTH - 40 - 36, 6)
	cells:SetPoint("LEFT", gear, "LEFT", 40, 0)
	gear.cells, gear.value = cells, gearValue
	-- Bags: one column per bag, the free count to the right.
	local bags = CreateFrame("Button", nil, page)
	bags:SetSize(COLUMN_WIDTH, 22)
	bags:SetPoint("TOPLEFT", gear, "BOTTOMLEFT", 0, -9)
	local columns = Figures.columns(bags, 5, 6, 22, 3)
	columns:SetPoint("BOTTOMLEFT")
	local free = text(bags, "serif", Stoa.typeSize.name, "text")
	free:SetPoint("BOTTOMLEFT", columns, "BOTTOMRIGHT", 8, 9)
	local of = text(bags, "sans", Stoa.typeSize.caption, "muted")
	of:SetPoint("BOTTOMLEFT", columns, "BOTTOMRIGHT", 8, -1)
	bags.columns, bags.free, bags.of = columns, free, of
	-- Hover explains, click opens (the same as At a glance's lines).
	for button, key in pairs({ [gear] = "durability", [bags] = "bags" }) do
		button:SetScript("OnEnter", function(own)
			local glance = Stoa.modules.Tally
			if glance and glance.ShowDetail then glance:ShowDetail(own, key) end
		end)
		button:SetScript("OnLeave", function() GameTooltip:Hide() end)
		button:SetScript("OnClick", function()
			local glance = Stoa.modules.Tally
			if glance and glance.Open and not InCombatLockdown() then glance:Open(key) end
		end)
	end
	-- Group buffs you could cast that someone near you lacks.
	local groupBuffs = text(page, "sans", Stoa.typeSize.body, "accent")
	groupBuffs:SetPoint("TOPLEFT", bags, "BOTTOMLEFT", 0, -5)
	groupBuffs:SetWidth(COLUMN_WIDTH)
	groupBuffs:SetWordWrap(false)
	self.roleWord, self.roleNote, self.gear, self.bags, self.groupBuffs = role, note, gear, bags, groupBuffs

	-- Journey.
	local journey = column(page, 2, "Journey")
	local level = text(page, "serif", Stoa.typeSize.title, "text")
	level:SetPoint("TOPLEFT", journey, "BOTTOMLEFT", 0, -6)
	-- Earned in the text colour, rest in blue behind it, and an accent mark
	-- where an hour at your pace would take you.
	-- Your share of the level on the same row, at the column's right edge.
	local share = text(page, "sans", Stoa.typeSize.body, "muted", "RIGHT")
	share:SetPoint("BOTTOMRIGHT", level, "BOTTOMLEFT", COLUMN_WIDTH, 2)
	local xp = Figures.xp(page, COLUMN_WIDTH, 5)
	xp:SetPoint("TOPLEFT", level, "BOTTOMLEFT", 0, -8)
	-- The bar's key (earned, rested to, in an hour) on hover, not as a row.
	local xpHover = CreateFrame("Frame", nil, page)
	xpHover:SetPoint("TOPLEFT", xp, "TOPLEFT", 0, 6)
	xpHover:SetPoint("BOTTOMRIGHT", xp, "BOTTOMRIGHT", 0, -6)
	xpHover:EnableMouse(true)
	xpHover:SetScript("OnEnter", function(own)
		local keys = self.xpKeyWords
		if not keys then return end
		GameTooltip:SetOwner(own, "ANCHOR_TOP")
		GameTooltip:AddLine("Experience")
		for _, key in ipairs(keys) do
			local r, g, b = Stoa:Color(key[1])
			GameTooltip:AddLine(key[2], r, g, b)
		end
		GameTooltip:Show()
	end)
	xpHover:SetScript("OnLeave", function() GameTooltip:Hide() end)
	-- The one key kept on the page: what the gold mark is, under the bar's
	-- right end.
	local hourKey = Figures.key(page, "accent")
	hourKey:SetPoint("TOPRIGHT", xp, "BOTTOMRIGHT", 0, -4)
	hourKey:SetText(nil)
	self.levelText, self.levelShare, self.xpBar, self.hourKey = level, share, xp, hourKey
	-- The dungeon kit (Kit.lua): your pace as a line chart over the last
	-- half hour, experience an hour and time to level beside it, and the
	-- nearest watched quest's progress when alone.
	local pace = CreateFrame("Frame", nil, page)
	pace:SetSize(COLUMN_WIDTH, 26)
	pace:SetPoint("TOPLEFT", xp, "BOTTOMLEFT", 0, -17)
	local spark = Figures.spark(pace, 54, 18)
	spark:SetPoint("BOTTOMLEFT", 0, 2)
	local perHour = text(pace, "serif", Stoa.typeSize.name, "text")
	perHour:SetPoint("TOPLEFT", pace, "TOPLEFT", 62, 0)
	local perHourCap = text(pace, "sans", Stoa.typeSize.caption, "muted")
	perHourCap:SetPoint("TOPLEFT", perHour, "BOTTOMLEFT", 0, -2)
	-- Time to level halfway along what's left, so the two captions under
	-- the numbers ("xp an hour", "to 12") never run into each other.
	local toLevel = text(pace, "serif", Stoa.typeSize.name, "text")
	toLevel:SetPoint("TOPLEFT", pace, "TOPLEFT", 62 + math.floor((COLUMN_WIDTH - 62) / 2), 0)
	local toLevelCap = text(pace, "sans", Stoa.typeSize.caption, "muted")
	toLevelCap:SetPoint("TOPLEFT", toLevel, "BOTTOMLEFT", 0, -2)
	pace.spark, pace.perHour, pace.perHourCap, pace.toLevel, pace.toLevelCap = spark, perHour, perHourCap, toLevel, toLevelCap
	pace:Hide()
	-- While the pace is still being worked out, a line of words instead.
	local rate = text(page, "sans", Stoa.typeSize.body, "muted")
	rate:SetPoint("TOPLEFT", xp, "BOTTOMLEFT", 0, -17)
	rate:SetWidth(COLUMN_WIDTH)
	rate:SetWordWrap(false)
	self.pace = pace
	local quest = text(page, "italic", Stoa.typeSize.body, "muted")
	quest:SetPoint("TOPLEFT", pace, "BOTTOMLEFT", 0, -9)
	quest:SetWidth(COLUMN_WIDTH)
	quest:SetWordWrap(false)
	-- New spells waiting at your trainer, or the next training level
	-- (Trainer.lua), on the quest line's row (Console:SettleNext places it).
	local trainer = text(page, "sans", Stoa.typeSize.body, "accent")
	trainer:SetPoint("TOPLEFT", quest, "TOPLEFT")
	trainer:SetWidth(COLUMN_WIDTH)
	trainer:SetWordWrap(false)
	self.rateNote, self.questNote, self.trainerNote = rate, quest, trainer

	-- Company.
	local company = column(page, 3, "Company")
	self.members = {}
	for i = 1, 4 do
		local row = CreateFrame("Frame", nil, page)
		row:SetSize(COLUMN_WIDTH, 18)
		row:SetPoint("TOPLEFT", company, "BOTTOMLEFT", 0, -6 - (i - 1) * rowGap)
		local name = text(row, "serif", Stoa.typeSize.label, "text")
		name:SetPoint("LEFT")
		name:SetWidth(90)
		name:SetWordWrap(false)
		local hp = bar(row, COLUMN_WIDTH - 98, 3, "health")
		hp:SetPoint("LEFT", name, "RIGHT", 8, 0)
		row.name, row.hp, row.unit = name, hp, "party" .. i
		self.members[i] = row
	end
	self.alone = text(page, "italic", Stoa.typeSize.label, "muted")
	self.alone:SetPoint("TOPLEFT", company, "BOTTOMLEFT", 0, -6)
	self.alone:SetText("Travelling alone")
	local online = text(page, "sans", Stoa.typeSize.body, "muted")
	online:SetPoint("TOPLEFT", self.alone, "BOTTOMLEFT", 0, -4)
	self.onlineCount = online
	-- A few of them by name, so the column says who as well as how many.
	local names = text(page, "serif", Stoa.typeSize.label, "text")
	names:SetPoint("TOPLEFT", online, "BOTTOMLEFT", 0, -4)
	names:SetWidth(COLUMN_WIDTH)
	names:SetWordWrap(false)
	self.onlineNames = names

	-- The whole column opens the roster.
	local open = CreateFrame("Button", nil, page)
	open:SetPoint("TOPLEFT", company, "TOPLEFT", 0, 22)
	open:SetSize(COLUMN_WIDTH, 104)
	open:SetScript("OnClick", function()
		if Stoa.modules.Roster then Stoa.modules.Roster:Toggle() end
	end)
	open:SetScript("OnEnter", function(button)
		GameTooltip:SetOwner(button, "ANCHOR_TOP")
		GameTooltip:AddLine("Company")
		GameTooltip:AddLine("Click for friends and guild online.", 1, 1, 1)
		GameTooltip:Show()
	end)
	open:SetScript("OnLeave", function() GameTooltip:Hide() end)
end

-- The medallion ring --------------------------------------------------------
-- Round the portrait: a bezel of fine ticks that fill with experience (lit
-- in the accent, the rested stretch in mana blue, the rest faint), and a
-- small plate at its foot with your level. At the level cap the bezel sits
-- evenly lit. A soft glow behind the ring marks moments and then settles:
-- a level gained, a ready check, stepping into rest, low health out of
-- combat. Nothing moves otherwise.

local TICKS = 48
local TICK_LENGTH = 5
local TICK_GAP = 7
local GLOW_SPREAD = 22

function Console:BuildRing(seal, portrait, size)
	local radius = size / 2 + TICK_GAP
	local ticks = {}
	for i = 1, TICKS do
		-- Clockwise from the top, like a dial.
		local angle = math.pi / 2 - (i - 0.5) / TICKS * 2 * math.pi
		local tick = seal:CreateTexture(nil, "ARTWORK", nil, 3)
		tick:SetTexture(UI.WHITE)
		tick:SetSize(1.5, TICK_LENGTH)
		tick:SetPoint("CENTER", portrait, "CENTER", math.cos(angle) * radius, math.sin(angle) * radius)
		if tick.SetRotation then tick:SetRotation(angle - math.pi / 2) end
		ticks[i] = tick
	end
	self.ringTicks = ticks

	-- The level in the display serif, a size up from the badge's caption, on
	-- an opaque plate so the bezel ticks under it don't read as digits.
	local plate = UI.badge(seal, nil, "accent")
	Stoa:SetFont(plate.text, "serif", Stoa.typeSize.label)
	plate:SetHeight(18)
	plate.fill:SetVertexColor(0, 0, 0, 0.95)
	plate:Set("1", "accent")
	plate:SetFrameLevel(seal:GetFrameLevel() + 5)
	plate:SetPoint("CENTER", portrait, "BOTTOM", 0, -TICK_GAP + 1)
	self.levelPlate = plate

	-- A soft halo (Tools/art/ring_glow.py), empty over the face.
	local glow = seal:CreateTexture(nil, "BORDER", nil, 4)
	glow:SetTexture(UI.MEDIA .. "Textures\\RingGlow")
	glow:SetSize(size + GLOW_SPREAD * 2, size + GLOW_SPREAD * 2)
	glow:SetPoint("CENTER", portrait, "CENTER")
	glow:SetBlendMode("ADD")
	glow:SetAlpha(0)
	self.ringGlow = glow
	local pulse = glow:CreateAnimationGroup()
	local rise = pulse:CreateAnimation("Alpha")
	rise:SetFromAlpha(0)
	rise:SetToAlpha(0.45)
	rise:SetDuration(0.7)
	rise:SetSmoothing("OUT")
	rise:SetOrder(1)
	local fall = pulse:CreateAnimation("Alpha")
	fall:SetFromAlpha(0.45)
	fall:SetToAlpha(0)
	fall:SetDuration(1.1)
	fall:SetSmoothing("IN")
	fall:SetOrder(2)
	pulse:SetScript("OnFinished", function()
		glow:SetAlpha(0)
		self.pulsesLeft = (self.pulsesLeft or 1) - 1
		if self.pulsesLeft > 0 or self.pulseHold then pulse:Play() else self.moment = nil end
	end)
	self.ringPulse = pulse
end

-- Lights the glow in a state colour. `times` pulses, or `hold` keeps
-- pulsing until Settle; a stronger moment replaces a weaker one.
local MOMENT_RANK = { rest = 1, low = 2, ready = 3, level = 4 }
local MOMENT_TOKEN = { rest = "mana", low = "danger", ready = "accent", level = "accent" }

function Console:Moment(kind, times, hold)
	if not self.ringPulse then return end
	if self.moment and (MOMENT_RANK[self.moment] or 0) > (MOMENT_RANK[kind] or 0) then return end
	self.moment = kind
	self.pulsesLeft = times or 1
	self.pulseHold = hold and true or false
	local r, g, b = Stoa:Color(MOMENT_TOKEN[kind] or "accent")
	self.ringGlow:SetVertexColor(r, g, b)
	if not self.ringPulse:IsPlaying() then self.ringPulse:Play() end
end

function Console:Settle(kind)
	if self.moment == kind then
		self.pulseHold = false
		self.pulsesLeft = 0
	end
end

function Console:UpdateRing()
	local ticks = self.ringTicks
	if not ticks then return end
	local level = Stoa:PlainNumber(UnitLevel("player")) or 0
	local maxLevel = GetMaxPlayerLevel and GetMaxPlayerLevel()
	self.levelPlate:Set(tostring(level), "accent")
	local done, rested = 1, 1
	if not (maxLevel and level >= maxLevel) and not (IsXPUserDisabled and IsXPUserDisabled()) then
		local xp, xpMax = Stoa:PlainNumber(UnitXP("player")), Stoa:PlainNumber(UnitXPMax("player"))
		if xp and xpMax and xpMax > 0 then
			local extra = Stoa:PlainNumber(GetXPExhaustion and GetXPExhaustion()) or 0
			done = xp / xpMax
			rested = math.min(xp + extra, xpMax) / xpMax
		end
	end
	local ar, ag, ab = Stoa:Color("accent")
	local mr, mg, mb = Stoa:Color("mana")
	local tr, tg, tb = Stoa:Color("text")
	for i, tick in ipairs(ticks) do
		local at = (i - 0.5) / TICKS
		if at <= done then
			tick:SetVertexColor(ar, ag, ab, done >= 1 and 0.55 or 0.9)
		elseif at <= rested then
			tick:SetVertexColor(mr, mg, mb, 0.75)
		else
			tick:SetVertexColor(tr, tg, tb, 0.16)
		end
	end
end

-- Low health out of combat (the console folds in combat, and health is
-- hidden then anyway): a slow danger pulse until you heal past the line.
local LOW_HEALTH = 0.35

function Console:CheckLowHealth()
	if InCombatLockdown() then return end
	local hp, hpMax = Stoa:PlainNumber(UnitHealth("player")), Stoa:PlainNumber(UnitHealthMax("player"))
	if not hp or not hpMax or hpMax <= 0 or UnitIsDeadOrGhost("player") then
		self:Settle("low")
		return
	end
	if hp / hpMax < LOW_HEALTH then
		if self.moment ~= "low" then self:Moment("low", 1, true) end
	else
		self:Settle("low")
	end
end

-- Updates -------------------------------------------------------------------

function Console:UpdateSeal()
	SetPortraitTexture(self.portrait, "player")
	local resting = IsResting and IsResting() and true or false
	if self.restMark then self.restMark:SetShown(resting) end
	if resting and self.wasResting == false then self:Moment("rest", 1) end
	self.wasResting = resting
	self:UpdateRing()
	local role = Stoa:GetRole()
	local label = role and Stoa.ROLE_LABELS[role] or ""
	-- A missing self-buff (Inner Fire, an aura, Righteous Fury) shows beside
	-- the role, in the warning colour, so it's caught before the pull.
	local missing = Stoa.missingBuffs
	if missing and #missing > 0 then
		local r, g, b = Stoa:Color("danger")
		local words = table.concat(missing, " · "):lower():gsub("^%l", string.upper)
		label = string.format("%s  |cff%02x%02x%02x%s|r", label, r * 255, g * 255, b * 255, words)
	end
	self.roleText:SetText(label)
	if self.roleWord then
		self.roleWord:SetText(role and Stoa.ROLE_LABELS[role] or "")
		local note = ""
		if missing and #missing > 0 then
			note = (table.concat(missing, " · "):lower():gsub("^%l", string.upper))
		end
		self.roleNote:SetText(note)
		self.roleNote:SetShown(note ~= "")
	end
	if self.groupBuffs then self.groupBuffs:SetText(Stoa.groupBuffLine or "") end
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
	self.onlineCount:SetShown(not any)
	if self.onlineNames then self.onlineNames:SetShown(not any) end
end

function Console:UpdateOnline()
	local friends = C_FriendList.GetNumOnlineFriends() or 0
	local _, bnetOnline = 0, 0
	if BNGetNumFriends then _, bnetOnline = BNGetNumFriends() end
	local guild = 0
	if IsInGuild() then
		local _, online = GetNumGuildMembers()
		-- The guild count includes you.
		guild = math.max((online or 1) - 1, 0)
	end
	local total = friends + (bnetOnline or 0) + guild
	self.onlineCount:SetText(total == 1 and "1 friend online" or (total .. " friends online"))
	if self.onlineNames then
		local names = {}
		if C_FriendList and C_FriendList.GetNumFriends then
			for i = 1, C_FriendList.GetNumFriends() or 0 do
				local info = C_FriendList.GetFriendInfoByIndex(i)
				if info and info.connected and #names < 3 then names[#names + 1] = Ambiguate(info.name, "short") end
			end
		end
		self.onlineNames:SetText(table.concat(names, ", "))
	end
end

-- Gear wear (the most worn piece) and free bag slots.
local GEAR_SLOTS = { 1, 3, 5, 6, 7, 8, 9, 10, 16, 17, 18 }

function Console:UpdateKit()
	if not self.gear then return end
	local lowest
	if GetInventoryItemDurability then
		for _, slot in ipairs(GEAR_SLOTS) do
			local current, max = GetInventoryItemDurability(slot)
			current, max = Stoa:PlainNumber(current), Stoa:PlainNumber(max)
			if current and max and max > 0 then
				local fraction = current / max
				if not lowest or fraction < lowest then lowest = fraction end
			end
		end
	end
	local share = lowest or 1
	self.gear.cells:Set(share)
	self.gear.value:SetText(math.floor(share * 100 + 0.5) .. "%")
	self.gear.value:SetTextColor(Stoa:Color(share < 0.25 and "danger" or "text"))
	-- Bags: how full each one is, and the free slots in all of them.
	local getFree = C_Container and C_Container.GetContainerNumFreeSlots or GetContainerNumFreeSlots
	local getSize = C_Container and C_Container.GetContainerNumSlots or GetContainerNumSlots
	local list, free, total = {}, 0, 0
	if getFree and getSize then
		for bag = 0, 4 do
			local size = Stoa:PlainNumber(getSize(bag)) or 0
			if size > 0 then
				local open = Stoa:PlainNumber(getFree(bag)) or 0
				free, total = free + open, total + size
				list[#list + 1] = { (size - open) / size, open == 0 }
			end
		end
	end
	self.bags.columns:Set(list)
	self.bags.free:SetText(free .. " free")
	self.bags.free:SetTextColor(Stoa:Color(free <= 2 and "danger" or "text"))
	self.bags.of:SetText("of " .. total)
end

function Console:UpdateJourney()
	if not self.levelText then return end
	local level = UnitLevel("player")
	local maxLevel = GetMaxPlayerLevel and GetMaxPlayerLevel()
	self.levelText:SetText("Level " .. level)
	local atMax = maxLevel and level >= maxLevel
	self.xpBar:SetShown(not atMax)
	self.levelShare:SetShown(not atMax)
	if atMax then
		self.hourKey:SetText(nil)
		self.xpKeyWords = nil
		self:UpdateKitLines()
		return
	end
	local xp, xpMax = Stoa:PlainNumber(UnitXP("player")), Stoa:PlainNumber(UnitXPMax("player"))
	if not xp or not xpMax or xpMax <= 0 then return end
	local rested = Stoa:PlainNumber(GetXPExhaustion and GetXPExhaustion()) or 0
	-- Where an hour at your pace would take you, from the kit.
	local kit = Stoa.modules.Kit
	local rate = kit and kit.enabled and kit.Rate and kit:Rate()
	local hour = rate and (xp + rate) / xpMax or nil
	self.xpBar:Set(xp / xpMax, math.min(xp + rested, xpMax) / xpMax, hour)
	local earned = math.floor(xp / xpMax * 100)
	self.levelShare:SetText(earned .. "%")
	local keys = { { "text", "Earned " .. earned .. "%" } }
	if rested > 0 then
		keys[#keys + 1] = { "mana", "Rested to " .. math.floor(math.min(xp + rested, xpMax) / xpMax * 100) .. "%" }
	end
	if hour then keys[#keys + 1] = { "accent", "The gold mark: where an hour at your pace gets you" } end
	self.xpKeyWords = keys
	self.hourKey:SetText(hour and "In an hour" or nil)
	self:UpdateKitLines()
end

-- The kit's lines under the experience bar, if the kit is on.
function Console:UpdateKitLines()
	local kit = Stoa.modules.Kit
	if kit and kit.UpdateConsole and kit.enabled then kit:UpdateConsole() end
	local trainer = Stoa.modules.Trainer
	if trainer and trainer.UpdateConsole and trainer.enabled then trainer:UpdateConsole() end
	self:SettleNext()
end

-- The nearest quest and the trainer share one row. With both, the quest
-- keeps the left and the trainer becomes a short tag at the right end
-- ("3 to train", "Train at 12"); alone, either has the whole row.
function Console:SettleNext()
	if not (self.trainerNote and self.questNote) then return end
	local full, short = self.trainerFull or (self.trainerNote:GetText() or ""), self.trainerShort or ""
	local training = full ~= ""
	local quest = (self.questNote:GetText() or "") ~= ""
	local note = self.trainerNote
	note:ClearAllPoints()
	if training and quest then
		note:SetText(short ~= "" and short or full)
		note:SetWidth(0)
		note:SetJustifyH("RIGHT")
		note:SetPoint("TOPRIGHT", self.questNote, "TOPLEFT", COLUMN_WIDTH, 0)
		local tag = Stoa:PlainNumber(note:GetStringWidth()) or 0
		self.questNote:SetWidth(math.max(COLUMN_WIDTH - tag - 10, 40))
	else
		note:SetText(full)
		note:SetJustifyH("LEFT")
		note:SetPoint("TOPLEFT", self.questNote, "TOPLEFT")
		note:SetWidth(COLUMN_WIDTH)
		self.questNote:SetWidth(COLUMN_WIDTH)
	end
	self.questNote:SetShown(quest)
	note:SetShown(training)
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
		for _, page in ipairs(self.extraPages or {}) do
			page:SetAlpha(open and progress or 1 - progress)
		end
		for _, part in ipairs(self.resourceParts) do
			part:SetAlpha(open and progress or 1 - progress)
		end
		for _, part in ipairs(self.archParts) do
			part:SetAlpha(open and progress or 1 - progress)
		end
		self.bridge:SetAlpha(open and 1 - progress or progress)
		for _, part in ipairs(self.tabArt or {}) do
			part:SetAlpha(open and progress or 1 - progress)
		end
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

	frame:SetScript("OnUpdate", Stoa:GuardUpdate(function()
		local seconds = Stoa.TRANSITION and (open and Stoa.TRANSITION.out or Stoa.TRANSITION.into) or FOLD_SECONDS
		local progress = math.min((GetTime() - start) / seconds, 1)
		-- Ease out so the fold settles rather than stops.
		progress = 1 - (1 - progress) ^ 3
		step(progress)
		if progress >= 1 then
			frame:SetScript("OnUpdate", nil)
			self.leftPage:SetAlpha(pagesAlpha)
			self.rightPage:SetAlpha(pagesAlpha)
			for _, page in ipairs(self.extraPages or {}) do page:SetAlpha(pagesAlpha) end
		end
	end))
end

-- Another module's page on the console (the tally): it fades with the
-- console's own pages as it folds and opens.
function Console:AddPage(page)
	self.extraPages = self.extraPages or {}
	table.insert(self.extraPages, page)
	page:SetAlpha(self.leftPage and self.leftPage:GetAlpha() or 1)
end

-- Folded in combat, unless the player keeps it open (Settings: In combat).
-- The console only folds when the Halo is there to take its place.
local function shouldBeOpen()
	return Stoa:GetState() == Stoa.STATE_WORLD or Stoa.db.combatConsole ~= "fold"
		or not Stoa:IsModuleEnabled("Halo")
end

function Console:Refold()
	self:SetOpen(shouldBeOpen(), Stoa.db.foldInstant)
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
	self:UpdateKit()
	self:UpdateJourney()
	self:RenderNotes()
	self:SetOpen(shouldBeOpen(), true)

	Stoa:On("STOA_NOTE", function(kind, message) self:AddNote(kind, message) end)
	Stoa:On("STOA_ROLE_CHANGED", function() self:UpdateSeal() end)
	Stoa:On("PLAYER_UPDATE_RESTING", function() self:UpdateSeal() end)
	Stoa:On("STOA_REMINDERS_CHANGED", function() self:UpdateSeal() end)
	Stoa:On("STOA_STATE_CHANGED", function() self:SetOpen(shouldBeOpen(), Stoa.db.foldInstant) end)

	Stoa:On("UNIT_PORTRAIT_UPDATE", function(unit)
		if unit == "player" then self:UpdateSeal() end
	end)
	Stoa:On("PLAYER_ENTERING_WORLD", function()
		self:UpdateSeal()
		self:UpdateResources()
		self:UpdateFellowship()
		if IsInGuild() and C_GuildInfo and C_GuildInfo.GuildRoster then C_GuildInfo.GuildRoster() end
	end)

	Stoa:On("UNIT_HEALTH", function(unit)
		if unit == "player" then
			setUnitBar(self.health, "player", "health")
			self.healthText:SetText(UnitHealth("player"))
			self:CheckLowHealth()
		elseif unit and unit:find("^party") then
			self:UpdateFellowship()
		end
	end)
	Stoa:OnUnit("UNIT_MAXHEALTH", { "player" }, function(unit)
		if unit == "player" then self:UpdateResources() end
	end)
	Stoa:OnUnit("UNIT_POWER_UPDATE", { "player" }, function(unit)
		if unit == "player" then
			setUnitBar(self.mana, "player", "power")
			self.manaText:SetText(UnitPower("player"))
		end
	end)
	Stoa:OnUnit("UNIT_MAXPOWER", { "player" }, function(unit)
		if unit == "player" then self:UpdateResources() end
	end)
	Stoa:On("GROUP_ROSTER_UPDATE", function() self:UpdateFellowship() end)

	for _, event in ipairs({ "PLAYER_XP_UPDATE", "UPDATE_EXHAUSTION", "PLAYER_LEVEL_UP" }) do
		Stoa:On(event, function()
			self:UpdateJourney()
			self:UpdateRing()
		end)
	end
	Stoa:On("PLAYER_LEVEL_UP", function()
		self:Moment("level", 3)
		-- UnitLevel catches up a moment after the event.
		C_Timer.After(0.5, function() self:UpdateRing() end)
	end)
	Stoa:On("READY_CHECK", function() self:Moment("ready", 1, true) end)
	Stoa:On("READY_CHECK_FINISHED", function() self:Settle("ready") end)
	Stoa:On("READY_CHECK_CONFIRM", function(unit)
		if unit and UnitIsUnit(unit, "player") then self:Settle("ready") end
	end)
	Stoa:On("PLAYER_REGEN_ENABLED", function() self:CheckLowHealth() end)
	Stoa:On("PLAYER_REGEN_DISABLED", function() self:Settle("low") end)
	Stoa:On("STOA_THEME_CHANGED", function() self:UpdateRing() end)
	for _, event in ipairs({ "UPDATE_INVENTORY_DURABILITY", "BAG_UPDATE_DELAYED", "PLAYER_EQUIPMENT_CHANGED" }) do
		Stoa:On(event, function() self:UpdateKit() end)
	end
	Stoa:On("FRIENDLIST_UPDATE", function() self:UpdateOnline() end)
	Stoa:On("BN_FRIEND_INFO_CHANGED", function() self:UpdateOnline() end)
	Stoa:On("GUILD_ROSTER_UPDATE", function() self:UpdateOnline() end)

	-- Notes fade after NOTE_SECONDS.
	Stoa:NewTicker(5, function() self:RenderNotes() end)
end
