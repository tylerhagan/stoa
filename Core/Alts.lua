-- Stoa: your characters. Each character writes down what it carries, its
-- money, rest and raid lockouts as it plays, account-wide in StoaDB.alts, so
-- the others can read it: item tooltips count copies on every character,
-- mail offers your own names, and /stoa alts opens a page of them all.
local _, ns = ...
local Stoa = ns.Stoa
local UI = Stoa.UI

local Alts = Stoa:NewModule("Alts", {
	tooltipCounts = true,
})
Stoa.Alts = Alts

local plain = function(v) return Stoa.safe.plain(v) end

local function store()
	StoaDB.alts = StoaDB.alts or {}
	return StoaDB.alts
end

-- "Name - Realm", the same key saved setups use.
function Alts.me()
	local name = plain(UnitName("player"))
	if not name then return nil end
	local realm = GetRealmName and GetRealmName() or ""
	return name .. (realm ~= "" and (" - " .. realm) or ""), name, realm
end

local function record()
	local key, name, realm = Alts.me()
	if not key then return nil end
	local all = store()
	local entry = all[key] or {}
	all[key] = entry
	entry.name, entry.realm = name, realm
	entry.surname = select(2, Stoa.fullName())
	local _, classFile = UnitClass("player")
	entry.class = classFile
	entry.faction = plain(UnitFactionGroup("player"))
	local _, _, raceID = UnitRace("player")
	entry.raceID, entry.sex = plain(raceID), plain(UnitSex("player"))
	entry.guid = plain(UnitGUID("player"))
	entry.seen = time()
	-- A realm can change its name, which left this same character listed
	-- twice. A note under another realm name for the same name, class, race
	-- and sex (and not known to be someone else) is this one's old self.
	for other, old in pairs(all) do
		if other ~= key and old.name == name and old.class == entry.class
			and old.raceID == entry.raceID and old.sex == entry.sex
			and (not old.guid or not entry.guid or old.guid == entry.guid) then
			all[other] = nil
		end
	end
	return entry
end

-- Counts by item ID across a set of bags.
local function countBags(first, last, extra)
	local out = {}
	local numSlots = C_Container and C_Container.GetContainerNumSlots
	local itemInfo = C_Container and C_Container.GetContainerItemInfo
	if not (numSlots and itemInfo) then return out end
	local function scan(bag)
		local ok, slots = pcall(numSlots, bag)
		if not ok or type(slots) ~= "number" then return end
		for slot = 1, slots do
			local okInfo, info = pcall(itemInfo, bag, slot)
			if okInfo and type(info) == "table" and info.itemID then
				out[info.itemID] = (out[info.itemID] or 0) + (info.stackCount or 1)
			end
		end
	end
	for bag = first, last do scan(bag) end
	for _, bag in ipairs(extra or {}) do scan(bag) end
	return out
end

function Alts:Note()
	local entry = record()
	if not entry then return end
	entry.level = plain(UnitLevel("player"))
	-- While the character is loading in or logging out the game answers 0
	-- for money; a 0 then must not replace what was written down. In the
	-- world a 0 is real (everything spent).
	local money = GetMoney and Stoa:PlainNumber(GetMoney())
	if money and (money > 0 or self.inWorld) then entry.money = money end
	entry.xp, entry.xpMax = plain(UnitXP("player")), plain(UnitXPMax("player"))
	entry.rested = GetXPExhaustion and GetXPExhaustion() or 0
	entry.zone = GetRealZoneText and GetRealZoneText() or entry.zone
end

function Alts:NoteBags()
	local entry = record()
	if not entry or InCombatLockdown() then return end
	entry.bags = countBags(0, NUM_BAG_SLOTS or 4)
end

-- The bank only reads while it is open: the main slots, the bank bags and,
-- on clients with bank tabs, each tab.
function Alts:NoteBank()
	local entry = record()
	if not entry then return end
	local extra = { (Enum.BagIndex and Enum.BagIndex.Bank) or -1 }
	if Enum.BagIndex then
		for i = 1, 8 do
			local tab = Enum.BagIndex["CharacterBankTab_" .. i]
			if tab then extra[#extra + 1] = tab end
		end
	end
	local first = (NUM_BAG_SLOTS or 4) + 1
	entry.bank = countBags(first, first + (NUM_BANKBAGSLOTS or 7) - 1, extra)
end

-- What the character wears (for the Characters window's gear list and its
-- stand-in model) and its average item level. Read when the gear changes.
function Alts:NoteGear()
	local entry = record()
	if not entry then return end
	local gear = {}
	for slot = 1, 19 do
		local link = GetInventoryItemLink("player", slot)
		if type(link) == "string" and not Stoa:IsSecret(link) then gear[slot] = link end
	end
	entry.gear = gear
	if GetAverageItemLevel then
		local _, equipped = GetAverageItemLevel()
		equipped = plain(equipped)
		if type(equipped) == "number" and equipped > 0 then entry.ilvl = math.floor(equipped + 0.5) end
	end
end

-- The two main professions, as "Tailoring 300".
function Alts:NoteProfessions()
	local entry = record()
	if not entry or not Stoa.readProfessions then return end
	local found = Stoa.readProfessions()
	local list = {}
	for _, key in ipairs({ "prof1", "prof2" }) do
		local prof = found[key]
		if prof and prof[1] then list[#list + 1] = prof[1] .. (prof[2] and (" " .. prof[2]) or "") end
	end
	entry.professions = list
end

function Alts:NoteLockouts()
	local entry = record()
	if not entry or not (GetNumSavedInstances and GetSavedInstanceInfo) then return end
	local list = {}
	for i = 1, GetNumSavedInstances() or 0 do
		local name, _, reset, _, locked, _, _, _, _, difficultyName, numBosses, killed = GetSavedInstanceInfo(i)
		if name and locked and reset and reset > 0 then
			list[#list + 1] = { name = name, ends = time() + reset, difficulty = difficultyName, bosses = numBosses, killed = killed }
		end
	end
	entry.lockouts = list
end

-- Everyone but you who holds this item: { { name, count, class }, ... }.
function Alts.holders(id)
	local out = {}
	local me = Alts.me()
	for key, entry in pairs(store()) do
		if key ~= me then
			local n = ((entry.bags or {})[id] or 0) + ((entry.bank or {})[id] or 0)
			if n > 0 then out[#out + 1] = { entry.name or key, n, entry.class } end
		end
	end
	table.sort(out, function(a, b) return a[2] > b[2] end)
	return out
end

-- Your characters on this realm (and faction), for the mail's To list.
function Alts.names(sameRealm)
	local out = {}
	local me, _, realm = Alts.me()
	local faction = plain(UnitFactionGroup("player"))
	for key, entry in pairs(store()) do
		if key ~= me and (not sameRealm or (entry.realm == realm and (not entry.faction or entry.faction == faction))) then
			out[#out + 1] = entry
		end
	end
	table.sort(out, function(a, b) return (a.name or "") < (b.name or "") end)
	return out
end

-- Every character noted, richest first.
function Alts.all()
	local out = {}
	for _, entry in pairs(store()) do out[#out + 1] = entry end
	table.sort(out, function(a, b)
		if (a.money or 0) ~= (b.money or 0) then return (a.money or 0) > (b.money or 0) end
		return (a.name or "") < (b.name or "")
	end)
	return out
end

function Alts.totalMoney()
	local total = 0
	for _, entry in pairs(store()) do total = total + (entry.money or 0) end
	return total
end

function Alts:OnEnable()
	self:Note()
	Stoa:AfterCombat(function() self:NoteBags() end)
	if RequestRaidInfo then RequestRaidInfo() end
	local pending
	local function bagsLater()
		if pending then return end
		pending = true
		C_Timer.After(2, function()
			pending = false
			self:NoteBags()
		end)
	end
	Stoa:On("BAG_UPDATE_DELAYED", bagsLater)
	Stoa:On("PLAYER_REGEN_ENABLED", bagsLater)
	Stoa:On("PLAYER_ENTERING_WORLD", function()
		C_Timer.After(1, function()
			self.inWorld = true
			self:Note()
		end)
	end)
	Stoa:On("PLAYER_LEAVING_WORLD", function() self.inWorld = false end)
	Stoa:On("PLAYER_MONEY", function() self:Note() end)
	Stoa:On("PLAYER_XP_UPDATE", function() self:Note() end)
	Stoa:On("UPDATE_EXHAUSTION", function() self:Note() end)
	Stoa:On("PLAYER_LEVEL_UP", function() self:Note() end)
	Stoa:On("ZONE_CHANGED_NEW_AREA", function() self:Note() end)
	Stoa:On("PLAYER_LOGOUT", function() self:Note() end)
	Stoa:On("BANKFRAME_OPENED", function() C_Timer.After(0.5, function() self:NoteBank() end) end)
	Stoa:On("BANKFRAME_CLOSED", function() self:NoteBank() end)
	Stoa:On("UPDATE_INSTANCE_INFO", function() self:NoteLockouts() end)
	local gearPending
	local function gearLater()
		if gearPending then return end
		gearPending = true
		C_Timer.After(1, function()
			gearPending = false
			self:NoteGear()
		end)
	end
	Stoa:On("PLAYER_EQUIPMENT_CHANGED", gearLater)
	Stoa:On("PLAYER_ENTERING_WORLD", gearLater)
	Stoa:On("SKILL_LINES_CHANGED", function() C_Timer.After(1, function() self:NoteProfessions() end) end)
	C_Timer.After(3, function() self:NoteProfessions() end)
end

-- The Characters window ----------------------------------------------------------
-- A band of account totals, one row per character, a Search tab that finds an
-- item on every character, and a side panel for the one you click: its model
-- and gear by group. Built the first time it opens; nothing runs while it is
-- closed.

local WIDTH, HEIGHT, PAD, HEADER, FOOTER = 840, 600, 20, 48, 40
local BAND_HEIGHT, BAND_GAP = 58, 10
local ROWS, ROW_HEIGHT = 7, 54
local HITS, HIT_HEIGHT = 9, 44
local SIDE_WIDTH = 320
local CREST = 34
-- Columns: x from the row's left edge.
local COLUMNS = { { "Character", 0 }, { "Where", 270 }, { "Gold", 470 }, { "Status", 590 } }
local LIST_TOP = HEADER + 14 + BAND_HEIGHT + 20

local function money(copper)
	copper = copper or 0
	local g, s = math.floor(copper / 10000), math.floor(copper / 100) % 100
	if g > 0 then return ("%dg %02ds"):format(g, s) end
	return ("%ds %02dc"):format(s, copper % 100)
end

local function ago(seen)
	if not seen then return "" end
	local s = time() - seen
	if s < 3600 then return "Seen just now" end
	if s < 86400 then return "Seen " .. math.floor(s / 3600) .. "h ago" end
	return "Seen " .. math.floor(s / 86400) .. "d ago"
end

-- Rest as a share of a level; it fills while logged out in an inn, so the
-- page adds what the hours away have earned (5% each 8 hours, up to 150%).
local function restShare(entry)
	if not entry.xpMax or entry.xpMax <= 0 then return 0 end
	local rested = entry.rested or 0
	if entry.seen then
		rested = rested + entry.xpMax * 0.05 * ((time() - entry.seen) / 28800)
	end
	return math.min(rested, entry.xpMax * 1.5) / entry.xpMax
end

local function restText(entry)
	local share = restShare(entry)
	if share <= 0 then return "" end
	if share >= 1.5 then return "Fully rested" end
	return math.floor(share * 100 + 0.5) .. "% rested"
end

local function keyOf(entry)
	return entry.name .. ((entry.realm or "") ~= "" and (" - " .. entry.realm) or "")
end

local function isMe(entry)
	local me = Alts.me()
	return me and entry.name and keyOf(entry) == me
end

local function className(entry)
	local names = LOCALIZED_CLASS_NAMES_MALE or {}
	return names[entry.class or ""] or ""
end

local function classColour(entry)
	local color = RAID_CLASS_COLORS and RAID_CLASS_COLORS[entry.class or ""]
	if color and Stoa.db.vision == "Standard" then return color.r, color.g, color.b end
	return Stoa:Color("text")
end

local function paintName(fs, entry)
	fs:SetTextColor(classColour(entry))
end

local function liveLocks(entry)
	local out = {}
	for _, lock in ipairs(entry.lockouts or {}) do
		if lock.ends > time() then out[#out + 1] = lock end
	end
	return out
end

-- The class's round crest, from the game's class icon sheet.
local function crest(parent, size)
	local holder = CreateFrame("Frame", nil, parent)
	holder:SetSize(size, size)
	-- The game's round class icons, cut from one sheet (a masked texture
	-- can't take tex coords, so the round sheet does the rounding).
	local icon = holder:CreateTexture(nil, "ARTWORK")
	icon:SetAllPoints()
	holder.icon = icon
	function holder:Set(entry)
		local coords = CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[entry.class or ""]
		if coords then
			icon:SetTexture("Interface\\TargetingFrame\\UI-Classes-Circles")
			icon:SetTexCoord(coords[1], coords[2], coords[3], coords[4])
		else
			icon:SetTexture(nil)
		end
	end
	return holder
end

-- Motion -------------------------------------------------------------------------
-- Small eased moves from the shared helpers in Core/Widgets.lua (animation
-- groups, no per-frame addon code): a window rises in, the side panel slides
-- out from the window's edge, hover lifts fade, the tab mark grows from its
-- middle, rows and search results arrive one after another.

local intro, fadeIn = UI.intro, UI.fadeIn

local function lift(row, on)
	if on then
		if not row.lift:IsShown() then
			row.lift:Show()
			row.liftIn:Play()
		end
	else
		row.lift:Hide()
	end
end

local function hoverRow(row)
	local liftTex = row:CreateTexture(nil, "BACKGROUND", nil, 2)
	liftTex:SetTexture(UI.WHITE)
	liftTex:SetAllPoints()
	liftTex:SetVertexColor(1, 1, 1, 0.045)
	liftTex:Hide()
	row.lift = liftTex
	row.liftIn = fadeIn(liftTex, UI.MOTION.quick)
	local rule = UI.line(row, "hairline")
	rule:SetPoint("BOTTOMLEFT")
	rule:SetPoint("BOTTOMRIGHT")
end

-- Two lines in one cell: a value and a muted caption under it.
local function cell(row, x, width, token)
	local top = UI.text(row, "sans", Stoa.typeSize.body, token or "text", "LEFT")
	top:SetPoint("TOPLEFT", x, -11)
	top:SetWidth(width)
	top:SetWordWrap(false)
	local under = UI.text(row, "sans", Stoa.typeSize.caption, "muted", "LEFT")
	under:SetPoint("TOPLEFT", top, "BOTTOMLEFT", 0, -5)
	under:SetWidth(width)
	under:SetWordWrap(false)
	return top, under
end

-- A thin bar: the level so far, and the rest waiting beyond it.
local function levelBar(row)
	local track = row:CreateTexture(nil, "ARTWORK")
	track:SetTexture(UI.WHITE)
	track:SetHeight(2)
	track:SetVertexColor(1, 1, 1, 0.08)
	local rest = row:CreateTexture(nil, "ARTWORK", nil, 1)
	rest:SetTexture(UI.WHITE)
	rest:SetHeight(2)
	rest:SetPoint("LEFT", track, "LEFT")
	local fill = row:CreateTexture(nil, "ARTWORK", nil, 2)
	fill:SetTexture(UI.WHITE)
	fill:SetHeight(2)
	fill:SetPoint("LEFT", track, "LEFT")
	return track, fill, rest
end

local function setBar(row, entry, width)
	local share = (entry.xp and entry.xpMax and entry.xpMax > 0) and math.min(entry.xp / entry.xpMax, 1) or nil
	local shown = share ~= nil and (entry.level or 0) < (MAX_PLAYER_LEVEL or 60)
	row.track:SetShown(shown)
	row.fill:SetShown(shown and share > 0)
	row.restBar:SetShown(shown)
	if not shown then return end
	local r, g, b = classColour(entry)
	row.fill:SetVertexColor(r, g, b, 0.9)
	row.fill:SetWidth(math.max(1, width * share))
	local rest = math.min(share + restShare(entry), 1)
	local ar, ag, ab = Stoa:Color("accent")
	row.restBar:SetVertexColor(ar, ag, ab, 0.35)
	row.restBar:SetWidth(math.max(1, width * rest))
end

function Alts:BuildRow(holder, i)
	local row = CreateFrame("Button", nil, holder)
	row:SetHeight(ROW_HEIGHT)
	row:SetPoint("TOPLEFT", 0, -(i - 1) * ROW_HEIGHT)
	row:SetPoint("RIGHT", holder, "RIGHT")
	hoverRow(row)
	-- The class's edge, which turns to the accent while picked.
	local edge = row:CreateTexture(nil, "ARTWORK")
	edge:SetTexture(UI.WHITE)
	edge:SetWidth(2)
	edge:SetPoint("TOPLEFT", 0, -6)
	edge:SetPoint("BOTTOMLEFT", 0, 6)
	row.edge = edge
	row.crest = crest(row, CREST)
	row.crest:SetPoint("LEFT", 14, 0)
	row.level = UI.badge(row, "1", "text")
	row.level:SetPoint("CENTER", row.crest, "BOTTOMRIGHT", -3, 3)
	row.level:SetFrameLevel(row:GetFrameLevel() + 3)
	local x = CREST + 26
	row.name = UI.text(row, "serif", Stoa.typeSize.label, "text", "LEFT")
	row.name:SetPoint("TOPLEFT", x, -9)
	row.name:SetWidth(COLUMNS[2][2] - x - 16)
	row.name:SetWordWrap(false)
	row.class = UI.text(row, "sans", Stoa.typeSize.caption, "muted", "LEFT")
	row.class:SetPoint("TOPLEFT", row.name, "BOTTOMLEFT", 0, -4)
	row.track, row.fill, row.restBar = levelBar(row)
	row.track:SetPoint("TOPLEFT", row.class, "BOTTOMLEFT", 0, -6)
	row.track:SetWidth(150)
	row.zone, row.prof = cell(row, COLUMNS[2][2], 185)
	row.gold, row.goldUnder = cell(row, COLUMNS[3][2], 110)
	row.status, row.locks = cell(row, COLUMNS[4][2], 110, "muted")
	row.ilvl = UI.text(row, "sans", Stoa.typeSize.label, "text", "RIGHT")
	row.ilvl:SetPoint("TOPRIGHT", -12, -10)
	row.seen = UI.text(row, "sans", Stoa.typeSize.caption, "muted", "RIGHT")
	row.seen:SetPoint("TOPRIGHT", row.ilvl, "BOTTOMRIGHT", 0, -5)
	row.intro = intro(row, 0, 4, UI.MOTION.quick, (i - 1) * UI.MOTION.stagger)
	row:SetScript("OnEnter", function()
		lift(row, true)
		local entry = row.entry
		if not entry then return end
		GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
		GameTooltip:AddLine(entry.name, classColour(entry))
		local mr, mg, mb = Stoa:Color("muted")
		local tr, tg, tb = Stoa:Color("text")
		if entry.professions and #entry.professions > 0 then
			GameTooltip:AddDoubleLine("Professions", table.concat(entry.professions, ", "), mr, mg, mb, tr, tg, tb)
		end
		local locks = liveLocks(entry)
		for _, lock in ipairs(locks) do
			local hours = math.floor((lock.ends - time()) / 3600)
			GameTooltip:AddDoubleLine(lock.name .. (lock.killed and (" " .. lock.killed .. "/" .. (lock.bosses or "?")) or ""),
				"resets in " .. (hours >= 24 and (math.floor(hours / 24) .. "d") or (hours .. "h")), mr, mg, mb, tr, tg, tb)
		end
		local ar, ag, ab = Stoa:Color("accent")
		GameTooltip:AddDoubleLine("Click", Alts.picked == entry and "Close gear" or "Model and gear", mr, mg, mb, ar, ag, ab)
		GameTooltip:Show()
	end)
	row:SetScript("OnLeave", function()
		if Alts.picked ~= row.entry then lift(row, false) end
		GameTooltip_Hide()
	end)
	row:SetScript("OnClick", function()
		if not row.entry then return end
		Alts:Pick(Alts.picked ~= row.entry and row.entry or nil)
		GameTooltip_Hide()
	end)
	return row
end

-- Header words: Characters and Search.
local function tabWord(page, label, onClick)
	local tab = CreateFrame("Button", nil, page)
	tab:SetHeight(24)
	local text = UI.text(tab, "sans", Stoa.typeSize.label, "muted", "LEFT")
	text:SetPoint("LEFT")
	text:SetText(label)
	tab:SetWidth(math.max(40, (text:GetStringWidth() or 60) + 2))
	local mark = UI.line(tab, "accent")
	mark:SetPoint("BOTTOMLEFT", 0, 0)
	mark:SetPoint("BOTTOMRIGHT", 0, 0)
	tab.text, tab.mark = text, mark
	local grow = UI.growIn(mark)
	function tab:SetSelected(on)
		if on and not self.on then grow:Play() end
		self.on = on
		mark:SetShown(on)
		text:SetTextColor(Stoa:Color(on and "text" or "muted"))
	end
	tab:SetScript("OnClick", onClick)
	tab:SetScript("OnEnter", function() text:SetTextColor(Stoa:Color("accent")) end)
	tab:SetScript("OnLeave", function() tab:SetSelected(tab.on) end)
	return tab
end

local function closeButton(parent, onClick)
	local close = CreateFrame("Button", nil, parent)
	close:SetSize(24, 24)
	close:SetPoint("RIGHT", parent, "TOPRIGHT", -12, -HEADER / 2)
	local cross = UI.glyph(close, "Cross", 14, "muted")
	cross:SetPoint("CENTER")
	close:SetScript("OnClick", onClick)
	close:SetScript("OnEnter", function() cross:SetVertexColor(Stoa:Color("accent")) end)
	close:SetScript("OnLeave", function() cross:SetVertexColor(Stoa:Color("muted")) end)
	return close
end

-- The band of account totals over the list.
function Alts:BuildBand(pane)
	local band = CreateFrame("Frame", nil, pane)
	band:SetPoint("TOPLEFT", 0, 0)
	band:SetPoint("TOPRIGHT", 0, 0)
	band:SetHeight(BAND_HEIGHT)
	self.tiles = {}
	local count = 4
	local width = (WIDTH - PAD * 2 - BAND_GAP * (count - 1)) / count
	for i = 1, count do
		local tile = CreateFrame("Frame", nil, band)
		tile:SetSize(width, BAND_HEIGHT)
		tile:SetPoint("TOPLEFT", (i - 1) * (width + BAND_GAP), 0)
		UI.well(tile, 0)
		local cap = UI.text(tile, "sans", Stoa.typeSize.caption, "muted", "LEFT")
		cap:SetPoint("TOPLEFT", 14, -11)
		local value = UI.text(tile, "sans", Stoa.typeSize.title, "text", "LEFT")
		value:SetPoint("BOTTOMLEFT", 14, 9)
		value:SetPoint("RIGHT", -12, 0)
		value:SetWordWrap(false)
		tile.cap, tile.value = cap, value
		tile.intro = intro(tile, 0, 4, UI.MOTION.quick, (i - 1) * UI.MOTION.stagger * 2)
		self.tiles[i] = tile
	end
end

function Alts:FillBand(list)
	local best, rested = nil, 0
	for _, entry in ipairs(list) do
		if not best or (entry.level or 0) > (best.level or 0) then best = entry end
		if not isMe(entry) and restShare(entry) >= 0.5 then rested = rested + 1 end
	end
	local tiles = self.tiles
	tiles[1].cap:SetText("GOLD ON ALL")
	tiles[1].value:SetText(Stoa:TintMoney(money(Alts.totalMoney())))
	tiles[1].value:SetTextColor(Stoa:Color("text"))
	tiles[2].cap:SetText("CHARACTERS")
	tiles[2].value:SetText(tostring(#list))
	tiles[2].value:SetTextColor(Stoa:Color("text"))
	tiles[3].cap:SetText("HIGHEST")
	if best then
		tiles[3].value:SetText(best.name .. Stoa:Hex("muted") .. "  " .. (best.level or "?") .. "|r")
		tiles[3].value:SetTextColor(classColour(best))
	else
		tiles[3].value:SetText("")
	end
	tiles[4].cap:SetText("WELL RESTED")
	tiles[4].value:SetText(rested == 0 and "None yet" or (rested == 1 and "1 character" or (rested .. " characters")))
	tiles[4].value:SetTextColor(Stoa:Color(rested > 0 and "accent" or "muted"))
end

function Alts:Build()
	local page = CreateFrame("Frame", "StoaAltsPage", UIParent)
	page:SetSize(WIDTH, HEIGHT)
	page:SetPoint("CENTER", -SIDE_WIDTH / 2, 30)
	page:SetFrameStrata("DIALOG")
	page:EnableMouse(true)
	page:SetMovable(true)
	page:SetClampedToScreen(true)
	page:RegisterForDrag("LeftButton")
	page:SetScript("OnDragStart", page.StartMoving)
	page:SetScript("OnDragStop", page.StopMovingOrSizing)
	page:Hide()
	table.insert(UISpecialFrames, "StoaAltsPage")
	UI.windowPanel(page, 0.97, { header = HEADER, footer = FOOTER })
	self.page = page
	page.intro = intro(page, 0, 8, UI.MOTION.open)

	local title = UI.text(page, "serif", Stoa.typeSize.title, "text", "LEFT")
	title:SetPoint("LEFT", page, "TOPLEFT", PAD, -HEADER / 2)
	title:SetText("Characters")
	self.tabs = {
		list = tabWord(page, "Characters", function() Alts:ShowTab("list") end),
		search = tabWord(page, "Search", function() Alts:ShowTab("search") end),
	}
	self.tabs.list:SetPoint("LEFT", title, "RIGHT", 28, 0)
	self.tabs.search:SetPoint("LEFT", self.tabs.list, "RIGHT", 18, 0)
	closeButton(page, function() page:Hide() end)

	-- People: the players you've written a note about (Modules/QoL/Notes.lua).
	local notes = Stoa.Notes
	if notes and Stoa:IsModuleEnabled("Notes") then
		self.tabs.people = tabWord(page, "People", function() Alts:ShowTab("people") end)
		self.tabs.people:SetPoint("LEFT", self.tabs.search, "RIGHT", 18, 0)
		local people = CreateFrame("Frame", nil, page)
		people:SetPoint("TOPLEFT", PAD, -HEADER - 12)
		people:SetPoint("BOTTOMRIGHT", -PAD, FOOTER + 6)
		people:SetSize(WIDTH - PAD * 2, HEIGHT - HEADER - FOOTER - 18)
		people:Hide()
		people.onCount = function(shown, all)
			if self.tab ~= "people" then return end
			self.count:SetText(all == 0 and "" or (shown == all and (all == 1 and "1 person noted" or (all .. " people noted")) or (shown .. " of " .. all .. " showing")))
			self.total:SetText(all == 0 and "" or "Click to edit  ·  Right-click to remove")
		end
		self.peoplePane = people
		xpcall(notes.BuildPane, Stoa.catch, notes, people)
	end

	-- The list: totals, column heads, rows.
	local list = CreateFrame("Frame", nil, page)
	list:SetPoint("TOPLEFT", PAD, -HEADER - 14)
	list:SetPoint("BOTTOMRIGHT", -PAD, FOOTER + 6)
	self.listPane = list
	self:BuildBand(list)
	local headY = -(LIST_TOP - HEADER - 14)
	for _, column in ipairs(COLUMNS) do
		local head = UI.text(list, "sans", Stoa.typeSize.caption, UI.slate() and "muted" or "accent", "LEFT")
		head:SetPoint("TOPLEFT", column[2] + (column[2] == 0 and (CREST + 26) or 0), headY)
		head:SetText(column[1]:upper())
	end
	local ilvlHead = UI.text(list, "sans", Stoa.typeSize.caption, UI.slate() and "muted" or "accent", "RIGHT")
	ilvlHead:SetPoint("TOPRIGHT", -12, headY)
	ilvlHead:SetText("ITEM LEVEL")
	local headRule = UI.line(list, "hairline")
	headRule:SetPoint("TOPLEFT", 0, headY - 18)
	headRule:SetPoint("TOPRIGHT", 0, headY - 18)
	local rows = CreateFrame("Frame", nil, list)
	rows:SetPoint("TOPLEFT", 0, headY - 20)
	rows:SetPoint("BOTTOMRIGHT")
	self.rows = {}
	for i = 1, ROWS do self.rows[i] = self:BuildRow(rows, i) end
	self.offset = 0
	list:EnableMouseWheel(true)
	list:SetScript("OnMouseWheel", function(_, delta)
		local maxOffset = math.max(#(self.list or {}) - ROWS, 0)
		self.offset = math.min(math.max(self.offset - delta, 0), maxOffset)
		self:Refresh()
	end)
	local empty = UI.text(list, "italic", Stoa.typeSize.label, "muted")
	empty:SetPoint("CENTER", 0, -40)
	empty:SetText("Each character fills in when you play it.")
	self.empty = empty

	-- The search.
	self:BuildSearch(page)

	local hint = UI.text(page, "sans", Stoa.typeSize.body, "muted", "LEFT")
	hint:SetPoint("LEFT", page, "BOTTOMLEFT", PAD, FOOTER / 2)
	local more = UI.text(page, "sans", Stoa.typeSize.body, "muted", "RIGHT")
	more:SetPoint("RIGHT", page, "BOTTOMRIGHT", -PAD, FOOTER / 2)
	self.count, self.total = hint, more

	page:SetScript("OnShow", function()
		self:Note()
		self:NoteGear()
		self.arrive = true
		self:ShowTab(self.tab or "list")
		page.intro:Play()
		for _, tile in ipairs(self.tiles) do tile.intro:Play() end
	end)
	page:SetScript("OnHide", function()
		if self.side then self.side:Hide() end
		self.picked = nil
	end)
end

function Alts:ShowTab(which)
	if which == "people" and not self.peoplePane then which = "list" end
	self.tab = which
	for id, tab in pairs(self.tabs) do tab:SetSelected(id == which) end
	self.listPane:SetShown(which == "list")
	self.searchPane:SetShown(which == "search")
	if self.peoplePane then self.peoplePane:SetShown(which == "people") end
	if which == "people" then
		self:Pick(nil)
		self.box:ClearFocus()
		Stoa.Notes:FillPane()
	elseif which == "search" then
		self:Pick(nil)
		self.box:SetFocus()
		self:Search()
	else
		self.box:ClearFocus()
		self.arrive = true
		self:Refresh()
	end
end

function Alts:Refresh()
	if not self.page then return end
	local list = {}
	for _, entry in pairs(store()) do
		if entry.name then list[#list + 1] = entry end
	end
	table.sort(list, function(a, b)
		if isMe(a) ~= isMe(b) then return isMe(a) end
		if (a.level or 0) ~= (b.level or 0) then return (a.level or 0) > (b.level or 0) end
		return (a.name or "") < (b.name or "")
	end)
	self.list = list
	self.empty:SetShown(#list == 0)
	self:FillBand(list)
	local arrive = self.arrive
	self.arrive = false
	for i, row in ipairs(self.rows) do
		local entry = list[i + self.offset]
		local was = row.entry
		row.entry = entry
		row:SetShown(entry ~= nil)
		if entry then
			if arrive or was ~= entry then row.intro:Play() end
			row.crest:Set(entry)
			row.level:Set(tostring(entry.level or "?"), "text")
			row.name:SetText(entry.name)
			paintName(row.name, entry)
			local about = {}
			if className(entry) ~= "" then about[#about + 1] = className(entry) end
			row.class:SetText(UI.join(about))
			setBar(row, entry, 150)
			row.zone:SetText(entry.zone or "Not seen yet")
			row.prof:SetText(UI.join(entry.professions or {}))
			row.gold:SetText(Stoa:TintMoney(money(entry.money)))
			row.goldUnder:SetText("")
			local playing = isMe(entry)
			row.status:SetText(playing and "Playing now" or restText(entry))
			row.status:SetTextColor(Stoa:Color(playing and "accent" or "muted"))
			local locks = liveLocks(entry)
			row.locks:SetText(#locks == 1 and locks[1].name or (#locks > 1 and (#locks .. " lockouts")) or "")
			row.ilvl:SetText(entry.ilvl and tostring(entry.ilvl) or "")
			row.seen:SetText(playing and "" or ago(entry.seen))
			local picked = self.picked == entry
			if picked then
				row.edge:SetVertexColor(Stoa:Color("accent"))
			else
				local r, g, b = classColour(entry)
				row.edge:SetVertexColor(r, g, b, 0.7)
			end
			lift(row, picked)
		end
	end
	self.count:SetText(#list > 0 and "Click a character for their model and gear" or "")
	local hidden = math.max(#list - ROWS, 0)
	self.total:SetText(hidden > 0 and ("Scroll for " .. hidden .. " more") or "")
	if self.picked and self.side and self.side:IsShown() then self:FillSide(self.picked) end
end

-- Search -------------------------------------------------------------------------

function Alts:BuildSearch(page)
	local pane = CreateFrame("Frame", nil, page)
	pane:SetPoint("TOPLEFT", PAD, -HEADER - 12)
	pane:SetPoint("BOTTOMRIGHT", -PAD, FOOTER + 6)
	pane:Hide()
	self.searchPane = pane

	local box = CreateFrame("EditBox", "StoaAltsSearch", pane)
	box:SetAutoFocus(false)
	box:SetHeight(30)
	box:SetPoint("TOPLEFT")
	box:SetPoint("TOPRIGHT")
	box:SetTextInsets(12, 26, 0, 0)
	box:SetMaxLetters(50)
	Stoa:SetFont(box, "sans", Stoa.typeSize.body)
	box:SetTextColor(Stoa:Color("text"))
	local back = UI.pillFill(box, 0)
	back:SetVertexColor(0, 0, 0, 0.4)
	local edge = UI.pillEdge(box, 0)
	local hint = UI.text(box, "sans", Stoa.typeSize.body, "muted")
	hint:SetPoint("LEFT", 12, 0)
	hint:SetText("Find an item on any character")
	local function paint()
		hint:SetShown(box:GetText() == "" and not box:HasFocus())
		edge:Set(Stoa:Color(box:HasFocus() and "accent" or "hairline"))
	end
	box:SetScript("OnTextChanged", function()
		paint()
		Alts:Search()
	end)
	box:SetScript("OnEscapePressed", function(b)
		if b:GetText() ~= "" then b:SetText("") else b:ClearFocus() end
	end)
	box:SetScript("OnEnterPressed", function(b) b:ClearFocus() end)
	box:SetScript("OnEditFocusGained", paint)
	box:SetScript("OnEditFocusLost", paint)
	self.box = box

	self.hits = {}
	for i = 1, HITS do
		local row = CreateFrame("Button", nil, pane)
		row:SetHeight(HIT_HEIGHT)
		row:SetPoint("TOPLEFT", 0, -40 - (i - 1) * HIT_HEIGHT)
		row:SetPoint("RIGHT", pane, "RIGHT")
		hoverRow(row)
		local icon = row:CreateTexture(nil, "ARTWORK")
		icon:SetSize(30, 30)
		icon:SetPoint("LEFT", 6, 0)
		icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
		local name = UI.text(row, "sans", Stoa.typeSize.label, "text", "LEFT")
		name:SetPoint("TOPLEFT", icon, "TOPRIGHT", 10, 0)
		name:SetPoint("RIGHT", -70, 0)
		name:SetWordWrap(false)
		local where = UI.text(row, "sans", Stoa.typeSize.caption, "muted", "LEFT")
		where:SetPoint("TOPLEFT", name, "BOTTOMLEFT", 0, -4)
		where:SetPoint("RIGHT", -70, 0)
		where:SetWordWrap(false)
		local total = UI.text(row, "sans", Stoa.typeSize.label, "text", "RIGHT")
		total:SetPoint("RIGHT", -8, 0)
		row.icon, row.name, row.where, row.total = icon, name, where, total
		row:SetScript("OnEnter", function()
			lift(row, true)
			if row.itemID then
				GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
				GameTooltip:SetItemByID(row.itemID)
				GameTooltip:Show()
			end
		end)
		row:SetScript("OnLeave", function()
			lift(row, false)
			GameTooltip_Hide()
		end)
		row:Hide()
		row.intro = intro(row, 0, 4, 0.12, (i - 1) * 0.015)
		self.hits[i] = row
	end
	self.hitOffset = 0
	pane:EnableMouseWheel(true)
	pane:SetScript("OnMouseWheel", function(_, delta)
		local maxOffset = math.max(#(self.found or {}) - HITS, 0)
		self.hitOffset = math.min(math.max(self.hitOffset - delta * 2, 0), maxOffset)
		self:DrawHits()
	end)
	local note = UI.text(pane, "italic", Stoa.typeSize.label, "muted")
	note:SetPoint("CENTER", 0, -10)
	self.searchNote = note

	-- Names the game hadn't loaded yet arrive later; search again then.
	Stoa:On("GET_ITEM_INFO_RECEIVED", function()
		if not (self.waiting and pane:IsVisible()) or self.again then return end
		self.again = true
		C_Timer.After(0.3, function()
			self.again = false
			self:Search()
		end)
	end)
end

local function itemName(id)
	local name = C_Item and C_Item.GetItemNameByID and C_Item.GetItemNameByID(id)
	if not name and GetItemInfo then name = GetItemInfo(id) end
	return name
end

-- Every item whose name holds the words, with who keeps it where. skip is a
-- character key left out (the bag search leaves out who is playing). The
-- second answer is true while some names are still loading.
function Alts.find(query, skip)
	local found, byID, waiting = {}, {}, false
	if #query < 2 then return found, waiting end
	for key, entry in pairs(store()) do
		if key ~= skip then
			for place, items in pairs({ Bags = entry.bags, Bank = entry.bank }) do
				for id, n in pairs(items or {}) do
					local name = itemName(id)
					if not name then
						waiting = true
						if C_Item and C_Item.RequestLoadItemDataByID then C_Item.RequestLoadItemDataByID(id) end
					elseif name:lower():find(query, 1, true) then
						local hit = byID[id]
						if not hit then
							hit = { id = id, name = name, total = 0, holders = {} }
							byID[id] = hit
							found[#found + 1] = hit
						end
						hit.total = hit.total + n
						local who = hit.holders[entry.name]
						if not who then
							who = { entry = entry }
							hit.holders[entry.name] = who
							hit.holders[#hit.holders + 1] = who
						end
						who[place] = (who[place] or 0) + n
					end
				end
			end
		end
	end
	return found, waiting
end

function Alts:Search()
	local query = strtrim(self.box:GetText() or ""):lower()
	local found, waiting = Alts.find(query)
	self.waiting = waiting
	table.sort(found, function(a, b)
		if a.total ~= b.total then return a.total > b.total end
		return a.name < b.name
	end)
	self.found = found
	self.hitOffset = 0
	if #query < 2 then
		self.searchNote:SetText("Bags and bank on every character, from when each last played.")
	elseif #found == 0 then
		self.searchNote:SetText(self.waiting and "Looking..." or "None of your characters holds that.")
	end
	self.searchNote:SetShown(#found == 0)
	self:DrawHits(true)
end

function Alts:DrawHits(arrive)
	local found = self.found or {}
	for i, row in ipairs(self.hits) do
		local hit = found[i + self.hitOffset]
		local was = row.itemID
		row.itemID = hit and hit.id
		row:SetShown(hit ~= nil)
		if hit and arrive and was ~= hit.id then row.intro:Play() end
		if hit then
			row.icon:SetTexture(C_Item and C_Item.GetItemIconByID and C_Item.GetItemIconByID(hit.id) or 134400)
			row.name:SetText(hit.name)
			local quality = C_Item and C_Item.GetItemQualityByID and C_Item.GetItemQualityByID(hit.id)
			local color = quality and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[quality]
			if color then row.name:SetTextColor(color.r, color.g, color.b) else row.name:SetTextColor(Stoa:Color("text")) end
			local parts = {}
			for _, who in ipairs(hit.holders) do
				local places = {}
				if who.Bags then places[#places + 1] = "bags " .. who.Bags end
				if who.Bank then places[#places + 1] = "bank " .. who.Bank end
				parts[#parts + 1] = who.entry.name .. " " .. table.concat(places, ", ")
			end
			row.where:SetText(table.concat(parts, UI.WIDE_SEP or "   "))
			row.total:SetText(tostring(hit.total))
		end
	end
end

-- The side panel -----------------------------------------------------------------

local GROUPS = {
	{ "Armour", { { 1, "Head" }, { 3, "Shoulder" }, { 15, "Back" }, { 5, "Chest" }, { 9, "Wrist" },
		{ 10, "Hands" }, { 6, "Waist" }, { 7, "Legs" }, { 8, "Feet" } } },
	{ "Jewellery", { { 2, "Neck" }, { 11, "Ring" }, { 12, "Ring" }, { 13, "Trinket" }, { 14, "Trinket" } } },
	{ "Weapons", { { 16, "Main hand" }, { 17, "Off hand" }, { 18, "Ranged" } } },
}
local STAGE_HEIGHT, LINE_HEIGHT, GROUP_HEAD = 172, 16, 24

-- One gear line: icon, the item's name in its quality colour, its level.
-- Hovering shows the item.
local function gearLine(side, label)
	local line = CreateFrame("Button", nil, side)
	line:SetHeight(LINE_HEIGHT)
	local liftTex = line:CreateTexture(nil, "BACKGROUND")
	liftTex:SetTexture(UI.WHITE)
	liftTex:SetPoint("TOPLEFT", -6, 1)
	liftTex:SetPoint("BOTTOMRIGHT", 6, -1)
	liftTex:SetVertexColor(1, 1, 1, 0.05)
	liftTex:Hide()
	line.lift, line.liftIn = liftTex, fadeIn(liftTex, UI.MOTION.quick)
	local icon = line:CreateTexture(nil, "ARTWORK")
	icon:SetSize(14, 14)
	icon:SetPoint("LEFT", 0, 0)
	icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	local slot = UI.text(line, "sans", Stoa.typeSize.caption, "muted", "LEFT")
	slot:SetPoint("LEFT", icon, "RIGHT", 8, 0)
	slot:SetWidth(62)
	slot:SetText(label)
	local item = UI.text(line, "sans", Stoa.typeSize.caption, "text", "LEFT")
	item:SetPoint("LEFT", slot, "RIGHT", 4, 0)
	item:SetPoint("RIGHT", line, "RIGHT", -30, 0)
	item:SetWordWrap(false)
	local level = UI.text(line, "sans", Stoa.typeSize.caption, "muted", "RIGHT")
	level:SetPoint("RIGHT", 0, 0)
	line.icon, line.slotText, line.item, line.level = icon, slot, item, level
	line:SetScript("OnEnter", function(own)
		own.lift:Show()
		own.liftIn:Play()
		if own.link then
			GameTooltip:SetOwner(own, "ANCHOR_LEFT")
			pcall(GameTooltip.SetHyperlink, GameTooltip, own.link)
			GameTooltip:Show()
		end
	end)
	line:SetScript("OnLeave", function(own)
		own.lift:Hide()
		GameTooltip_Hide()
	end)
	return line
end

function Alts:BuildSide()
	local side = CreateFrame("Frame", "StoaAltsSide", self.page)
	side:SetSize(SIDE_WIDTH, HEIGHT)
	side:SetPoint("TOPLEFT", self.page, "TOPRIGHT", 8, 0)
	side:EnableMouse(true)
	side:Hide()
	UI.windowPanel(side, 0.97, { header = HEADER })
	side.intro = intro(side, 10, 0, UI.MOTION.open)
	local name = UI.text(side, "serif", Stoa.typeSize.title, "text", "LEFT")
	name:SetPoint("LEFT", side, "TOPLEFT", PAD, -HEADER / 2)
	closeButton(side, function() Alts:Pick(nil) end)
	local about = UI.text(side, "sans", Stoa.typeSize.caption, "muted", "LEFT")
	about:SetPoint("TOPLEFT", PAD, -HEADER - 12)
	about:SetPoint("RIGHT", side, "RIGHT", -PAD, 0)
	about:SetWordWrap(false)

	-- The stage: the model in a well, item level on its corner, a soft
	-- shade at its foot.
	local stage = CreateFrame("Frame", nil, side)
	stage:SetPoint("TOPLEFT", PAD, -HEADER - 32)
	stage:SetPoint("TOPRIGHT", -PAD, -HEADER - 32)
	stage:SetHeight(STAGE_HEIGHT)
	UI.well(stage, 0)
	local shade = stage:CreateTexture(nil, "BACKGROUND", nil, 1)
	shade:SetTexture(UI.WHITE)
	shade:SetPoint("BOTTOMLEFT")
	shade:SetPoint("BOTTOMRIGHT")
	shade:SetHeight(STAGE_HEIGHT * 0.45)
	if shade.SetGradient and CreateColor then
		pcall(shade.SetGradient, shade, "VERTICAL", CreateColor(0, 0, 0, 0.45), CreateColor(0, 0, 0, 0))
	else
		shade:SetVertexColor(0, 0, 0, 0.2)
	end
	local model = CreateFrame("DressUpModel", nil, stage)
	model:SetAllPoints()
	model.reveal = fadeIn(model, 0.2)
	-- Drag to turn the model; it settles where you let go.
	model:EnableMouse(true)
	model:SetScript("OnMouseDown", function(m, button)
		if button ~= "LeftButton" then return end
		m.turnFrom, m.facingFrom = GetCursorPosition(), m:GetFacing() or 0
		m:SetScript("OnUpdate", function()
			local x = GetCursorPosition()
			m:SetFacing(m.facingFrom + (x - m.turnFrom) / 80)
		end)
	end)
	model:SetScript("OnMouseUp", function(m) m:SetScript("OnUpdate", nil) end)
	model:SetScript("OnHide", function(m) m:SetScript("OnUpdate", nil) end)
	local noModel = UI.text(stage, "italic", Stoa.typeSize.body, "muted")
	noModel:SetPoint("CENTER")
	noModel:SetWidth(SIDE_WIDTH - PAD * 2 - 30)
	local ilvlCap = UI.text(stage, "sans", Stoa.typeSize.caption, "muted", "LEFT")
	ilvlCap:SetPoint("TOPLEFT", 12, -10)
	ilvlCap:SetText("ITEM LEVEL")
	local ilvl = UI.text(stage, "sans", Stoa.typeSize.title, "text", "LEFT")
	ilvl:SetPoint("TOPLEFT", ilvlCap, "BOTTOMLEFT", 0, -4)
	local turn = UI.text(stage, "sans", Stoa.typeSize.caption, "muted", "RIGHT")
	turn:SetPoint("BOTTOMRIGHT", -10, 8)
	turn:SetText("Drag to turn")
	turn:SetAlpha(0.7)

	-- Gear, by group.
	local lines = {}
	local y = -HEADER - 32 - STAGE_HEIGHT - 16
	for _, group in ipairs(GROUPS) do
		local head = UI.text(side, "sans", Stoa.typeSize.caption, "accent", "LEFT")
		head:SetPoint("TOPLEFT", PAD, y)
		head:SetText(group[1]:upper())
		local rule = UI.line(side, "hairline")
		rule:SetPoint("LEFT", head, "RIGHT", 8, 0)
		rule:SetPoint("RIGHT", side, "RIGHT", -PAD, 0)
		y = y - 18
		for _, slot in ipairs(group[2]) do
			local line = gearLine(side, slot[2])
			line:SetPoint("TOPLEFT", PAD, y)
			line:SetPoint("RIGHT", side, "RIGHT", -PAD, 0)
			line.slot = slot[1]
			lines[#lines + 1] = line
			y = y - LINE_HEIGHT
		end
		y = y - (GROUP_HEAD - 18)
	end
	side:SetHeight(math.max(HEIGHT, -y + 10))
	side.name, side.about, side.model, side.noModel, side.lines, side.ilvl, side.turn = name, about, model, noModel, lines, ilvl, turn
	self.side = side
end

-- The model: the real one for the character you are on; for the others a
-- stand-in of their race wearing what they last wore, where the game lets
-- an addon dress one up (hair and face stay the game's defaults).
local function dress(model, entry)
	if isMe(entry) then
		return pcall(model.SetUnit, model, "player")
	end
	if not (model.SetCustomRace and entry.raceID and entry.sex and entry.gear) then return false end
	local ok = pcall(model.SetCustomRace, model, entry.raceID, entry.sex == 3 and 1 or 0)
	if not ok then return false end
	if model.Undress then pcall(model.Undress, model) end
	for _, link in pairs(entry.gear) do
		pcall(model.TryOn, model, link)
	end
	return true
end

-- An item link's name without brackets, in its quality colour.
-- The quality comes from the item itself: newer links carry a named
-- colour (|cnIQ3:) instead of hex, so the link's own prefix can't be trusted.
local function linkName(link)
	local name = link:match("%[(.-)%]") or link
	name = name:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|cn[^:]*:", ""):gsub("|r", "")
	local id = tonumber(link:match("item:(%d+)"))
	local quality = id and C_Item and C_Item.GetItemQualityByID and C_Item.GetItemQualityByID(id)
	if not quality then quality = tonumber(link:match("|cnIQ(%d+):")) end
	local color = quality and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[quality]
	if color and color.hex then return color.hex .. name .. "|r" end
	if color and color.r then
		return ("|cff%02x%02x%02x"):format(color.r * 255, color.g * 255, color.b * 255) .. name .. "|r"
	end
	local colour = link:match("^(|c%x%x%x%x%x%x%x%x)")
	return (colour or "") .. name .. (colour and "|r" or "")
end

local function linkIcon(link)
	local id = tonumber(link:match("item:(%d+)"))
	return id and C_Item and C_Item.GetItemIconByID and C_Item.GetItemIconByID(id) or nil
end

function Alts:FillSide(entry)
	local side = self.side
	side.name:SetText(entry.surname and (entry.name .. " " .. entry.surname) or entry.name)
	paintName(side.name, entry)
	local about = {}
	if entry.level then about[#about + 1] = "Level " .. entry.level end
	if className(entry) ~= "" then about[#about + 1] = className(entry) end
	if entry.zone then about[#about + 1] = entry.zone end
	side.about:SetText(UI.join(about))
	local shown = dress(side.model, entry)
	side.model:SetShown(shown and true or false)
	side.turn:SetShown(shown and true or false)
	if shown then
		if side.model.SetFacing then side.model:SetFacing(0.35) end
		side.model.reveal:Play()
	end
	side.noModel:SetShown(not shown)
	side.noModel:SetText(entry.name .. "'s model shows while you play them.")
	side.ilvl:SetText(entry.ilvl and tostring(entry.ilvl) or "-")
	local gear = entry.gear or {}
	for _, line in ipairs(side.lines) do
		local link = gear[line.slot]
		line.link = link
		if link then
			line.item:SetText(linkName(link))
			line.icon:SetTexture(linkIcon(link) or 134400)
			line.icon:SetDesaturated(false)
			line.icon:SetAlpha(1)
			line.slotText:SetTextColor(Stoa:Color("muted"))
			local level = Stoa.Items.level(link)
			line.level:SetText(level and tostring(Stoa:PlainNumber(level) or "") or "")
		else
			line.item:SetText(Stoa:Hex("muted") .. "Empty|r")
			line.icon:SetTexture(134400)
			line.icon:SetDesaturated(true)
			line.icon:SetAlpha(0.25)
			line.slotText:SetTextColor(Stoa:Color("muted"))
			line.level:SetText("")
		end
	end
end

function Alts:Pick(entry)
	self.picked = entry
	for _, row in ipairs(self.rows or {}) do
		local on = entry ~= nil and row.entry == entry
		lift(row, on)
		if row.entry then
			if on then
				row.edge:SetVertexColor(Stoa:Color("accent"))
			else
				local r, g, b = classColour(row.entry)
				row.edge:SetVertexColor(r, g, b, 0.7)
			end
		end
	end
	if not entry then
		if self.side then self.side:Hide() end
		return
	end
	if not self.side then self:BuildSide() end
	local opening = not self.side:IsShown()
	self:FillSide(entry)
	self.side:Show()
	if opening then self.side.intro:Play() end
end

function Alts:Toggle()
	if not self.page then self:Build() end
	self.page:SetShown(not self.page:IsShown())
end

-- Opens the window on its Search tab, already searched for the words.
function Alts:OpenSearch(query)
	if not self.page then self:Build() end
	self.page:Show()
	self.box:SetText(query or "")
	self:ShowTab("search")
	self.box:SetCursorPosition(#(query or ""))
end

-- Opens the window on its People tab.
function Alts:OpenPeople()
	if not self.page then self:Build() end
	self.tab = "people"
	if self.page:IsShown() then self:ShowTab("people") else self.page:Show() end
end

-- A key for it in the game's Key Bindings, under AddOns > STOA (Bindings.xml).
BINDING_HEADER_STOA = "STOA"
BINDING_NAME_STOA_CHARACTERS = "Characters window"

-- /stoa alts (or /stoa characters) opens the page; /stoa alts forget <name> drops a character.
Stoa.commands.alts = function(rest)
	local action, who = (rest or ""):match("^(%S*)%s*(.-)$")
	if action:lower() == "forget" and who ~= "" then
		for key, entry in pairs(store()) do
			if (entry.name or ""):lower() == who:lower() or key:lower() == who:lower() then
				store()[key] = nil
				Stoa:Print(entry.name .. " is forgotten.")
				if Alts.page and Alts.page:IsShown() then Alts:Refresh() end
				return
			end
		end
		Stoa:Print("No character called " .. who .. ".")
		return
	end
	Alts:Toggle()
end
Stoa.commands.characters = Stoa.commands.alts
