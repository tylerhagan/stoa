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
	local _, classFile = UnitClass("player")
	entry.class = classFile
	entry.faction = plain(UnitFactionGroup("player"))
	local _, _, raceID = UnitRace("player")
	entry.raceID, entry.sex = plain(raceID), plain(UnitSex("player"))
	entry.seen = time()
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
-- One row per character, a Search tab that finds an item on every
-- character, and a side panel for the one you click: its model and gear.
-- Built the first time it opens; nothing runs while it is closed.

local WIDTH, HEIGHT, PAD, HEADER, FOOTER = 820, 560, 20, 48, 40
local ROWS, ROW_HEIGHT = 10, 42
local HITS, HIT_HEIGHT = 9, 44
local SIDE_WIDTH = 300
local COLUMNS = { { "Character", 0 }, { "Where", 190 }, { "Gold", 370 }, { "Rest", 470 }, { "Lockouts", 580 } }

local function money(copper)
	copper = copper or 0
	local g, s = math.floor(copper / 10000), math.floor(copper / 100) % 100
	if g > 0 then return ("%dg %02ds"):format(g, s) end
	return ("%ds %02dc"):format(s, copper % 100)
end

local function ago(seen)
	if not seen then return "" end
	local s = time() - seen
	if s < 3600 then return "Now" end
	if s < 86400 then return math.floor(s / 3600) .. "h ago" end
	return math.floor(s / 86400) .. "d ago"
end

-- Rest as a share of a level; it fills while logged out in an inn, so the
-- page adds what the hours away have earned (5% each 8 hours, up to 150%).
local function restText(entry)
	if not entry.xpMax or entry.xpMax <= 0 then return "" end
	local rested = entry.rested or 0
	if entry.seen then
		rested = rested + entry.xpMax * 0.05 * ((time() - entry.seen) / 28800)
	end
	rested = math.min(rested, entry.xpMax * 1.5)
	if rested <= 0 then return "" end
	if rested >= entry.xpMax * 1.5 then return "Fully rested" end
	return math.floor(rested / entry.xpMax * 100 + 0.5) .. "% rested"
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

local function paintName(fs, entry)
	local color = RAID_CLASS_COLORS and RAID_CLASS_COLORS[entry.class or ""]
	if color and Stoa.db.vision == "Standard" then
		fs:SetTextColor(color.r, color.g, color.b)
	else
		fs:SetTextColor(Stoa:Color("text"))
	end
end

local function liveLocks(entry)
	local out = {}
	for _, lock in ipairs(entry.lockouts or {}) do
		if lock.ends > time() then out[#out + 1] = lock end
	end
	return out
end

-- Motion -------------------------------------------------------------------------
-- Small eased moves, made with the game's own animation groups (no per-frame
-- addon code): a window rises in, the side panel slides out from the
-- window's edge, hover lifts fade, the tab mark grows from its middle and
-- search results arrive one after another.

local function intro(region, dx, dy, seconds, delay)
	local group = region:CreateAnimationGroup()
	local from = group:CreateAnimation("Translation")
	from:SetOffset(-dx, -dy)
	from:SetDuration(0)
	from:SetOrder(1)
	local move = group:CreateAnimation("Translation")
	move:SetOffset(dx, dy)
	move:SetDuration(seconds)
	move:SetOrder(2)
	move:SetSmoothing("OUT")
	local fade = group:CreateAnimation("Alpha")
	fade:SetFromAlpha(0)
	fade:SetToAlpha(1)
	fade:SetDuration(seconds)
	fade:SetOrder(2)
	fade:SetSmoothing("OUT")
	if delay and delay > 0 then
		-- Held hidden at the start point until its turn comes.
		local hold = group:CreateAnimation("Alpha")
		hold:SetFromAlpha(0)
		hold:SetToAlpha(0)
		hold:SetDuration(delay)
		hold:SetOrder(1)
	end
	return group
end

local function fadeIn(region, seconds)
	local group = region:CreateAnimationGroup()
	local fade = group:CreateAnimation("Alpha")
	fade:SetFromAlpha(0)
	fade:SetToAlpha(1)
	fade:SetDuration(seconds)
	fade:SetSmoothing("OUT")
	return group
end

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

-- Two lines in one cell: a value and a muted caption under it.
local function cell(row, x, width, token)
	local top = UI.text(row, "sans", Stoa.typeSize.body, token or "text", "LEFT")
	top:SetPoint("TOPLEFT", x, -6)
	top:SetWidth(width)
	top:SetWordWrap(false)
	local under = UI.text(row, "sans", Stoa.typeSize.caption, "muted", "LEFT")
	under:SetPoint("TOPLEFT", top, "BOTTOMLEFT", 0, -3)
	under:SetWidth(width)
	under:SetWordWrap(false)
	return top, under
end

local function hoverRow(row)
	local lift = row:CreateTexture(nil, "BACKGROUND", nil, 2)
	lift:SetTexture(UI.WHITE)
	lift:SetAllPoints()
	lift:SetVertexColor(1, 1, 1, 0.04)
	lift:Hide()
	row.lift = lift
	row.liftIn = fadeIn(lift, 0.12)
	local rule = UI.line(row, "hairline")
	rule:SetPoint("BOTTOMLEFT")
	rule:SetPoint("BOTTOMRIGHT")
end

function Alts:BuildRow(holder, i)
	local row = CreateFrame("Button", nil, holder)
	row:SetHeight(ROW_HEIGHT)
	row:SetPoint("TOPLEFT", 0, -(i - 1) * ROW_HEIGHT)
	row:SetPoint("RIGHT", holder, "RIGHT")
	hoverRow(row)
	row.name, row.class = cell(row, COLUMNS[1][2] + 8, 175, "text")
	Stoa:SetFont(row.name, "serif", Stoa.typeSize.label)
	row.zone, row.prof = cell(row, COLUMNS[2][2] + 8, 170)
	row.gold = cell(row, COLUMNS[3][2] + 8, 95, "accent")
	row.rest = cell(row, COLUMNS[4][2] + 8, 105, "muted")
	row.locks = cell(row, COLUMNS[5][2] + 8, 120, "muted")
	row.ilvl, row.seen = cell(row, 0, 70)
	row.ilvl:ClearAllPoints()
	row.ilvl:SetPoint("TOPRIGHT", -8, -6)
	row.ilvl:SetJustifyH("RIGHT")
	row.seen:SetJustifyH("RIGHT")
	row.seen:ClearAllPoints()
	row.seen:SetPoint("TOPRIGHT", row.ilvl, "BOTTOMRIGHT", 0, -3)
	row:SetScript("OnEnter", function()
		lift(row, true)
		local locks = row.entry and liveLocks(row.entry) or {}
		if #locks == 0 then return end
		GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
		GameTooltip:AddLine("Saved to", Stoa:Color("text"))
		for _, lock in ipairs(locks) do
			local hours = math.floor((lock.ends - time()) / 3600)
			GameTooltip:AddDoubleLine(lock.name .. (lock.killed and (" " .. lock.killed .. "/" .. (lock.bosses or "?")) or ""),
				hours >= 24 and (math.floor(hours / 24) .. "d") or (hours .. "h"), 1, 1, 1, 0.7, 0.7, 0.7)
		end
		GameTooltip:Show()
	end)
	row:SetScript("OnLeave", function()
		if Alts.picked ~= row.entry then lift(row, false) end
		GameTooltip_Hide()
	end)
	row:SetScript("OnClick", function()
		if not row.entry then return end
		Alts:Pick(Alts.picked ~= row.entry and row.entry or nil)
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
	local grow = mark:CreateAnimationGroup()
	local scale = grow:CreateAnimation("Scale")
	scale:SetScaleFrom(0.1, 1)
	scale:SetScaleTo(1, 1)
	scale:SetOrigin("CENTER", 0, 0)
	scale:SetDuration(0.2)
	scale:SetSmoothing("OUT")
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

function Alts:Build()
	local page = CreateFrame("Frame", "StoaAltsPage", UIParent)
	page:SetSize(WIDTH, HEIGHT)
	page:SetPoint("CENTER", -SIDE_WIDTH / 2, 40)
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
	page.intro = intro(page, 0, 10, 0.22)

	local title = UI.text(page, "serif", Stoa.typeSize.title, "text", "LEFT")
	title:SetPoint("LEFT", page, "TOPLEFT", PAD, -HEADER / 2)
	title:SetText("Characters")
	self.tabs = {
		list = tabWord(page, "Characters", function() Alts:ShowTab("list") end),
		search = tabWord(page, "Search", function() Alts:ShowTab("search") end),
	}
	self.tabs.list:SetPoint("LEFT", title, "RIGHT", 24, 0)
	self.tabs.search:SetPoint("LEFT", self.tabs.list, "RIGHT", 16, 0)
	local close = CreateFrame("Button", nil, page)
	close:SetSize(24, 24)
	close:SetPoint("RIGHT", page, "TOPRIGHT", -12, -HEADER / 2)
	local cross = UI.glyph(close, "Cross", 14, "muted")
	cross:SetPoint("CENTER")
	close:SetScript("OnClick", function() page:Hide() end)
	close:SetScript("OnEnter", function() cross:SetVertexColor(Stoa:Color("accent")) end)
	close:SetScript("OnLeave", function() cross:SetVertexColor(Stoa:Color("muted")) end)

	-- The list.
	local list = CreateFrame("Frame", nil, page)
	list:SetPoint("TOPLEFT", PAD, -HEADER - 10)
	list:SetPoint("BOTTOMRIGHT", -PAD, FOOTER + 6)
	self.listPane = list
	for _, column in ipairs(COLUMNS) do
		local head = UI.text(list, "sans", Stoa.typeSize.caption, "accent", "LEFT")
		head:SetPoint("TOPLEFT", column[2] + 8, 0)
		head:SetText(column[1]:upper())
	end
	local ilvlHead = UI.text(list, "sans", Stoa.typeSize.caption, "accent", "RIGHT")
	ilvlHead:SetPoint("TOPRIGHT", -8, 0)
	ilvlHead:SetText("ILVL")
	local rows = CreateFrame("Frame", nil, list)
	rows:SetPoint("TOPLEFT", 0, -20)
	rows:SetPoint("BOTTOMRIGHT")
	self.rows = {}
	for i = 1, ROWS do self.rows[i] = self:BuildRow(rows, i) end
	self.offset = 0
	list:EnableMouseWheel(true)
	list:SetScript("OnMouseWheel", function(_, delta)
		local maxOffset = math.max(#(self.list or {}) - ROWS, 0)
		self.offset = math.min(math.max(self.offset - delta * 2, 0), maxOffset)
		self:Refresh()
	end)
	local empty = UI.text(list, "italic", Stoa.typeSize.label, "muted")
	empty:SetPoint("CENTER")
	empty:SetText("Each character fills in when you play it.")
	self.empty = empty

	-- The search.
	self:BuildSearch(page)

	local count = UI.text(page, "sans", Stoa.typeSize.body, "muted", "LEFT")
	count:SetPoint("LEFT", page, "BOTTOMLEFT", PAD, FOOTER / 2)
	local total = UI.text(page, "sans", Stoa.typeSize.body, "muted", "RIGHT")
	total:SetPoint("RIGHT", page, "BOTTOMRIGHT", -PAD, FOOTER / 2)
	self.count, self.total = count, total

	page:SetScript("OnShow", function()
		self:Note()
		self:NoteGear()
		self:ShowTab(self.tab or "list")
		page.intro:Play()
	end)
	page:SetScript("OnHide", function()
		if self.side then self.side:Hide() end
		self.picked = nil
	end)
end

function Alts:ShowTab(which)
	self.tab = which
	self.tabs.list:SetSelected(which == "list")
	self.tabs.search:SetSelected(which == "search")
	self.listPane:SetShown(which == "list")
	self.searchPane:SetShown(which == "search")
	if which == "search" then
		self:Pick(nil)
		self.box:SetFocus()
		self:Search()
	else
		self.box:ClearFocus()
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
	for i, row in ipairs(self.rows) do
		local entry = list[i + self.offset]
		row.entry = entry
		row:SetShown(entry ~= nil)
		if entry then
			row.name:SetText(entry.name)
			paintName(row.name, entry)
			row.class:SetText(UI.join({ entry.level and tostring(entry.level), className(entry) }))
			row.zone:SetText(entry.zone or "")
			row.prof:SetText(entry.professions and entry.professions[1] or "")
			row.gold:SetText(money(entry.money))
			row.rest:SetText(isMe(entry) and "Playing" or restText(entry))
			local locks = liveLocks(entry)
			row.locks:SetText(#locks == 1 and locks[1].name or (#locks > 1 and (#locks .. " lockouts")) or "")
			row.ilvl:SetText(entry.ilvl and tostring(entry.ilvl) or "")
			row.seen:SetText(isMe(entry) and "Now" or ago(entry.seen))
			lift(row, self.picked == entry)
		end
	end
	self.count:SetText(#list == 1 and "1 character" or (#list .. " characters"))
	self.total:SetText("Total " .. Stoa:TintMoney(money(Alts.totalMoney())))
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
		row.intro = intro(row, 0, 4, 0.16, (i - 1) * 0.025)
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

-- Every item whose name holds the words, with who keeps it where.
function Alts:Search()
	local query = strtrim(self.box:GetText() or ""):lower()
	local found, byID = {}, {}
	self.waiting = false
	if #query >= 2 then
		for _, entry in pairs(store()) do
			for place, items in pairs({ Bags = entry.bags, Bank = entry.bank }) do
				for id, n in pairs(items or {}) do
					local name = itemName(id)
					if not name then
						self.waiting = true
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

local SLOTS = {
	{ 1, "Head" }, { 2, "Neck" }, { 3, "Shoulder" }, { 15, "Back" }, { 5, "Chest" },
	{ 9, "Wrist" }, { 10, "Hands" }, { 6, "Waist" }, { 7, "Legs" }, { 8, "Feet" },
	{ 11, "Ring" }, { 12, "Ring" }, { 13, "Trinket" }, { 14, "Trinket" },
	{ 16, "Main hand" }, { 17, "Off hand" }, { 18, "Ranged" },
}

function Alts:BuildSide()
	local side = CreateFrame("Frame", "StoaAltsSide", self.page)
	side:SetSize(SIDE_WIDTH, HEIGHT)
	side:SetPoint("TOPLEFT", self.page, "TOPRIGHT", 8, 0)
	side:EnableMouse(true)
	side:Hide()
	UI.windowPanel(side, 0.97, { header = HEADER })
	side.intro = intro(side, 14, 0, 0.24)
	local name = UI.text(side, "serif", Stoa.typeSize.title, "text", "LEFT")
	name:SetPoint("LEFT", side, "TOPLEFT", PAD, -HEADER / 2)
	local close = CreateFrame("Button", nil, side)
	close:SetSize(24, 24)
	close:SetPoint("RIGHT", side, "TOPRIGHT", -12, -HEADER / 2)
	local cross = UI.glyph(close, "Cross", 14, "muted")
	cross:SetPoint("CENTER")
	close:SetScript("OnClick", function() Alts:Pick(nil) end)
	close:SetScript("OnEnter", function() cross:SetVertexColor(Stoa:Color("accent")) end)
	close:SetScript("OnLeave", function() cross:SetVertexColor(Stoa:Color("muted")) end)

	local stage = CreateFrame("Frame", nil, side)
	stage:SetPoint("TOPLEFT", PAD, -HEADER - 10)
	stage:SetPoint("TOPRIGHT", -PAD, -HEADER - 10)
	stage:SetHeight(210)
	UI.well(stage, 0)
	local model = CreateFrame("DressUpModel", nil, stage)
	model:SetAllPoints()
	model.reveal = fadeIn(model, 0.35)
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
	noModel:SetWidth(SIDE_WIDTH - PAD * 2 - 20)

	local lines = {}
	for i, slot in ipairs(SLOTS) do
		local label = UI.text(side, "sans", Stoa.typeSize.caption, "muted", "LEFT")
		label:SetPoint("TOPLEFT", stage, "BOTTOMLEFT", 0, -12 - (i - 1) * 15)
		label:SetWidth(64)
		label:SetText(slot[2])
		local item = UI.text(side, "sans", Stoa.typeSize.caption, "text", "LEFT")
		item:SetPoint("LEFT", label, "RIGHT", 4, 0)
		item:SetPoint("RIGHT", side, "RIGHT", -PAD - 28, 0)
		item:SetWordWrap(false)
		local level = UI.text(side, "sans", Stoa.typeSize.caption, "muted", "RIGHT")
		level:SetPoint("RIGHT", side, "RIGHT", -PAD, 0)
		level:SetPoint("TOP", label, "TOP")
		lines[i] = { slot = slot[1], item = item, level = level }
	end
	side.name, side.model, side.noModel, side.lines = name, model, noModel, lines
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
	for slot, link in pairs(entry.gear) do
		pcall(model.TryOn, model, link)
	end
	return true
end

function Alts:FillSide(entry)
	local side = self.side
	side.name:SetText(entry.name)
	paintName(side.name, entry)
	local shown = dress(side.model, entry)
	side.model:SetShown(shown and true or false)
	if shown then
		if side.model.SetFacing then side.model:SetFacing(0.35) end
		side.model.reveal:Play()
	end
	side.noModel:SetShown(not shown)
	side.noModel:SetText(entry.name .. "'s model shows while you play them.")
	local gear = entry.gear or {}
	for _, line in ipairs(side.lines) do
		local link = gear[line.slot]
		line.item:SetText(link or "")
		local level = link and Stoa.Items.level(link)
		line.level:SetText(level and tostring(Stoa:PlainNumber(level) or "") or "")
	end
end

function Alts:Pick(entry)
	self.picked = entry
	for _, row in ipairs(self.rows or {}) do lift(row, entry ~= nil and row.entry == entry) end
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

-- /stoa alts opens the page; /stoa alts forget <name> drops a character.
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
