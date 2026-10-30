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
	entry.money = GetMoney and GetMoney() or entry.money
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
	Stoa:On("PLAYER_MONEY", function() self:Note() end)
	Stoa:On("PLAYER_XP_UPDATE", function() self:Note() end)
	Stoa:On("UPDATE_EXHAUSTION", function() self:Note() end)
	Stoa:On("PLAYER_LEVEL_UP", function() self:Note() end)
	Stoa:On("ZONE_CHANGED_NEW_AREA", function() self:Note() end)
	Stoa:On("PLAYER_LOGOUT", function() self:Note() end)
	Stoa:On("BANKFRAME_OPENED", function() C_Timer.After(0.5, function() self:NoteBank() end) end)
	Stoa:On("BANKFRAME_CLOSED", function() self:NoteBank() end)
	Stoa:On("UPDATE_INSTANCE_INFO", function() self:NoteLockouts() end)
end

-- The page -------------------------------------------------------------------

local WIDTH, HEIGHT, PAD, ROWS, ROW_HEIGHT = 620, 520, 24, 12, 28

local function money(copper)
	copper = copper or 0
	local g, s = math.floor(copper / 10000), math.floor(copper / 100) % 100
	if g > 0 then return ("%dg %02ds"):format(g, s) end
	return ("%ds %02dc"):format(s, copper % 100)
end

local function ago(seen)
	if not seen then return "" end
	local s = time() - seen
	if s < 3600 then return "now" end
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
	return math.floor(rested / entry.xpMax * 100 + 0.5) .. "% rested"
end

function Alts:BuildRow(page, i)
	local row = CreateFrame("Frame", nil, page)
	row:SetHeight(ROW_HEIGHT)
	row:SetPoint("TOPLEFT", PAD, -110 - (i - 1) * ROW_HEIGHT)
	row:SetPoint("RIGHT", page, "RIGHT", -PAD, 0)
	row:EnableMouse(true)
	local name = UI.text(row, "serif", Stoa.typeSize.label, "text", "LEFT")
	name:SetPoint("LEFT", 4, 0)
	name:SetWidth(140)
	name:SetWordWrap(false)
	local level = UI.text(row, "sans", Stoa.typeSize.caption + 1, "muted", "RIGHT")
	level:SetPoint("LEFT", name, "RIGHT", 4, 0)
	level:SetWidth(24)
	local rest = UI.text(row, "sans", Stoa.typeSize.caption + 1, "muted", "LEFT")
	rest:SetPoint("LEFT", level, "RIGHT", 16, 0)
	rest:SetWidth(110)
	local locks = UI.text(row, "sans", Stoa.typeSize.caption + 1, "muted", "LEFT")
	locks:SetPoint("LEFT", rest, "RIGHT", 8, 0)
	locks:SetWidth(120)
	locks:SetWordWrap(false)
	local gold = UI.text(row, "sans", Stoa.typeSize.caption + 1, "text", "RIGHT")
	gold:SetPoint("RIGHT", -4, 0)
	gold:SetWidth(110)
	row:SetScript("OnEnter", function()
		local entry = row.entry
		if not entry then return end
		GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
		GameTooltip:AddLine(entry.name or "?", Stoa:Color("text"))
		if entry.zone then GameTooltip:AddLine(entry.zone, 1, 1, 1) end
		GameTooltip:AddLine("Last played " .. ago(entry.seen), 0.7, 0.7, 0.7)
		for _, lock in ipairs(entry.lockouts or {}) do
			if lock.ends > time() then
				local hours = math.floor((lock.ends - time()) / 3600)
				GameTooltip:AddDoubleLine(lock.name .. (lock.killed and (" " .. lock.killed .. "/" .. (lock.bosses or "?")) or ""),
					hours >= 24 and (math.floor(hours / 24) .. "d") or (hours .. "h"), 1, 1, 1, 0.7, 0.7, 0.7)
			end
		end
		GameTooltip:Show()
	end)
	row:SetScript("OnLeave", GameTooltip_Hide)
	row.name, row.level, row.rest, row.locks, row.gold = name, level, rest, locks, gold
	return row
end

function Alts:Build()
	local page = CreateFrame("Frame", "StoaAltsPage", UIParent)
	page:SetSize(WIDTH, HEIGHT)
	page:SetPoint("CENTER", 0, 60)
	page:SetFrameStrata("DIALOG")
	page:EnableMouse(true)
	page:SetMovable(true)
	page:RegisterForDrag("LeftButton")
	page:SetScript("OnDragStart", page.StartMoving)
	page:SetScript("OnDragStop", page.StopMovingOrSizing)
	page:Hide()
	table.insert(UISpecialFrames, "StoaAltsPage")
	UI.windowPanel(page, 0.97, { header = 92, footer = 60 })
	self.page = page

	local title = UI.text(page, "serif", Stoa.typeSize.display, "text")
	title:SetPoint("TOPLEFT", PAD, -PAD)
	title:SetText("Characters")
	local lede = UI.text(page, "italic", Stoa.typeSize.label, "muted", "LEFT")
	lede:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -6)
	lede:SetText("Each character fills in when you play it. Hover for zone and raid lockouts.")

	self.rows = {}
	for i = 1, ROWS do self.rows[i] = self:BuildRow(page, i) end
	self.offset = 0
	page:EnableMouseWheel(true)
	page:SetScript("OnMouseWheel", function(_, delta)
		local maxOffset = math.max(#(self.list or {}) - ROWS, 0)
		self.offset = math.min(math.max(self.offset - delta * 3, 0), maxOffset)
		self:Refresh()
	end)
	local total = UI.text(page, "sans", Stoa.typeSize.caption + 1, "muted", "LEFT")
	total:SetPoint("BOTTOMLEFT", PAD, PAD)
	self.total = total
	local close = UI.button(page, "Close", 80, function() page:Hide() end)
	close:SetPoint("BOTTOMRIGHT", -PAD, PAD - 8)
	page:SetScript("OnShow", function()
		self:Note()
		self:Refresh()
	end)
end

function Alts:Refresh()
	local list = {}
	for _, entry in pairs(store()) do list[#list + 1] = entry end
	table.sort(list, function(a, b)
		if (a.level or 0) ~= (b.level or 0) then return (a.level or 0) > (b.level or 0) end
		return (a.name or "") < (b.name or "")
	end)
	self.list = list
	local me = Alts.me()
	for i, row in ipairs(self.rows) do
		local entry = list[i + self.offset]
		row.entry = entry
		row:SetShown(entry ~= nil)
		if entry then
			local mine = me and (entry.name .. (entry.realm ~= "" and (" - " .. entry.realm) or "")) == me
			row.name:SetText(entry.name or "?")
			local color = RAID_CLASS_COLORS and RAID_CLASS_COLORS[entry.class or ""]
			if color and Stoa.db.vision == "Standard" then
				row.name:SetTextColor(color.r, color.g, color.b)
			else
				row.name:SetTextColor(Stoa:Color("text"))
			end
			row.level:SetText(entry.level or "")
			row.rest:SetText(mine and "playing" or restText(entry))
			local n = 0
			for _, lock in ipairs(entry.lockouts or {}) do
				if lock.ends > time() then n = n + 1 end
			end
			row.locks:SetText(n > 0 and (n == 1 and "1 lockout" or (n .. " lockouts")) or "")
			row.gold:SetText(money(entry.money))
		end
	end
	self.total:SetText(("%d characters · %s in all"):format(#list, money(Alts.totalMoney())))
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
