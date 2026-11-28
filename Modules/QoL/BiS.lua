-- Stoa QoL: best in slot. A small list per spec build of the gear to aim
-- for before raids, each slot's pick and the next two behind it (the
-- alternates), from Data/BiS.lua: WoWSims Forever's simmed sets plus sets
-- players shared as WoWSims links, written by Tools/bis/build.py.
--
-- The list follows your role (Settings' role for each spec), and the build
-- within it is yours to pick (kept per character and role). It shows:
--   * a pane beside the character sheet (the BiS word in its footer, or
--     /stoa bis): each slot's pick, where it comes from and whether you wear
--     it or have it, by slot or by the place you still have to go;
--   * a gold diamond on the pick in bags, on the sheet, at a vendor and on
--     quest rewards (an open diamond for an alternate), and a line on the
--     item's tooltip;
--   * at max level, the place with the most picks still to get on the
--     console's Journey column, and the picks a dungeon drops on the
--     dungeon companion's card.
--
-- Nothing is read until something asks: a lookup is one table index.
local _, ns = ...
local Stoa = ns.Stoa
local UI = Stoa.UI
local hooksecurefunc = Stoa.SafeHook

local BiS = Stoa:NewModule("BiS", {
	enabled = true,
	-- "slot" or "place".
	view = "slot",
})
Stoa.BiS = BiS

local call = Stoa.safe.call
local GLYPH = UI.MEDIA .. "Textures\\Glyph"
local DIAMOND, OPEN = GLYPH .. "Diamond", GLYPH .. "DiamondOpen"

local SLOT_WORDS = {
	HEAD = "Head", NECK = "Neck", SHOULDER = "Shoulder", BACK = "Back", CHEST = "Chest",
	WRIST = "Wrist", HANDS = "Hands", WAIST = "Waist", LEGS = "Legs", FEET = "Feet",
	FINGER1 = "Ring", FINGER2 = "Ring", TRINKET1 = "Trinket", TRINKET2 = "Trinket",
	MAINHAND = "Main hand", OFFHAND = "Off hand", RANGED = "Ranged",
}
-- Rings and trinkets: either slot of the pair counts as wearing it.
local PAIR = { [11] = 12, [12] = 11, [13] = 14, [14] = 13 }
local MONTHS = { "Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec" }

-- Data -------------------------------------------------------------------------

local function data() return Stoa.BiSData end

-- "27 Nov" from the data's date.
function BiS:Date()
	local d = data()
	local y, m, day = tostring(d and d.date or ""):match("^(%d+)-(%d+)-(%d+)$")
	if not y then return nil end
	return ("%d %s"):format(tonumber(day), MONTHS[tonumber(m)] or m)
end

function BiS:Enabled()
	return self.enabled and data() ~= nil and Stoa:IsModuleEnabled("BiS")
end

-- Lists you imported (account-wide, StoaDB.bisLists), shaped like the
-- data's builds. Made once from the saved strings.
local mine
local function myLists()
	if mine then return mine end
	mine = {}
	for _, line in ipairs(Stoa.db and Stoa.db.bisLists or {}) do
		local build = BiS:Parse(line)
		if build then mine[#mine + 1] = build end
	end
	return mine
end

-- "STOA-BIS1|CLASS|ROLE|name|credit|slot;slot;..." with 17 slots, each
-- "id+alt+alt~suffix" or empty (Tools/bis/build.py --strings writes them).
function BiS:Parse(line)
	if type(line) ~= "string" then return nil end
	local class, role, name, credit, rest = line:match("^%s*STOA%-BIS1|(%u+)|(%u+)|([^|]+)|([^|]*)|(.-)%s*$")
	if not class then return nil end
	local slots, count = {}, 0
	for field in (rest .. ";"):gmatch("([^;]*);") do
		count = count + 1
		local ids, suffix = field:match("^([^~]*)~?(.*)$")
		local list = {}
		for id in (ids or ""):gmatch("%d+") do list[#list + 1] = tonumber(id) end
		if list[1] then
			local alts = {}
			for i = 2, #list do alts[#alts + 1] = list[i] end
			slots[count] = { list[1], suffix ~= "" and suffix or nil, #alts > 0 and alts or nil }
		else
			slots[count] = false
		end
	end
	if count ~= 17 then return nil end
	return { class = class, role = role, name = name, credit = credit ~= "" and credit or nil, slots = slots, mine = true, line = line }
end

-- Adds every list in some pasted text; returns how many were added.
function BiS:Import(text)
	Stoa.db.bisLists = Stoa.db.bisLists or {}
	local added = 0
	for line in tostring(text or ""):gmatch("[^\r\n]+") do
		local build = self:Parse(line)
		if build then
			local keep = {}
			for _, old in ipairs(Stoa.db.bisLists) do
				local was = self:Parse(old)
				if not (was and was.class == build.class and was.role == build.role and was.name == build.name) then keep[#keep + 1] = old end
			end
			keep[#keep + 1] = build.line
			Stoa.db.bisLists = keep
			added = added + 1
		end
	end
	mine = nil
	if added > 0 then self:Changed() end
	return added
end

function BiS:Remove(build)
	local keep = {}
	for _, old in ipairs(Stoa.db.bisLists or {}) do
		if old ~= build.line then keep[#keep + 1] = old end
	end
	Stoa.db.bisLists = keep
	mine = nil
	self:Changed()
end

-- The builds for your class and current role: your imported lists first
-- (you brought them for a reason), then the shipped ones in the data's order.
function BiS:Builds(role)
	local list = {}
	local d = data()
	if not d then return list end
	local _, class = UnitClass("player")
	role = role or Stoa:GetRole()
	for _, build in ipairs(myLists()) do
		if build.class == class and build.role == role then list[#list + 1] = build end
	end
	for _, build in ipairs(d.builds) do
		if build.class == class and build.role == role then list[#list + 1] = build end
	end
	return list
end

-- The build you picked for this role, else its first.
function BiS:Build(role)
	role = role or Stoa:GetRole()
	local list = self:Builds(role)
	local picked = Stoa.char and Stoa.char.bisBuild and Stoa.char.bisBuild[role or ""]
	for _, build in ipairs(list) do
		if build.name == picked then return build end
	end
	return list[1]
end

function BiS:Pick(name)
	local role = Stoa:GetRole()
	if not (Stoa.char and role) then return end
	Stoa.char.bisBuild = Stoa.char.bisBuild or {}
	Stoa.char.bisBuild[role] = name
	self:Changed()
end

-- itemID = { slot index, rank } for a build: rank 1 is the pick, 2 and 3
-- the alternates. Made once per build.
local index = setmetatable({}, { __mode = "k" })
local function indexOf(build)
	if index[build] then return index[build] end
	local map = {}
	for i, slot in ipairs(build.slots) do
		if slot then
			if not map[slot[1]] then map[slot[1]] = { i, 1 } end
			for rank, alt in ipairs(slot[3] or {}) do
				if not map[alt] then map[alt] = { i, rank + 1 } end
			end
		end
	end
	index[build] = map
	return map
end

-- How an item stands in your current build: rank (1 pick, 2-3 alternate),
-- the slot index, the build. Nil when it isn't on the list.
function BiS:Rank(item)
	if not self:Enabled() then return nil end
	local id = Stoa.Items.id(item)
	local build = id and self:Build()
	local entry = build and indexOf(build)[id]
	if not entry then return nil end
	return entry[2], entry[1], build
end

-- Your other role's build, when the item is its pick (Disc for a Shadow
-- priest, Prot for a Ret paladin).
function BiS:OtherRank(item)
	local id = Stoa.Items.id(item)
	if not (id and Stoa.char and Stoa.char.roles) then return nil end
	local here = Stoa:GetRole()
	for slot = 1, 2 do
		local role = Stoa.char.roles["slot" .. slot]
		if role == "AUTO" then role = Stoa:DefaultRole() end
		if role and role ~= here then
			local build = self:Build(role)
			local entry = build and indexOf(build)[id]
			if entry then return entry[2], build end
		end
	end
end

local function myFaction()
	local faction = UnitFactionGroup and UnitFactionGroup("player")
	return faction == "Alliance" and 1 or faction == "Horde" and 2 or 0
end

-- Where an item comes from: words for a row ("Stratholme · The Unforgiven")
-- and the place it groups under in the by-place view.
function BiS:Source(id)
	local entry = data() and data().items[id]
	if not entry then return "", "Elsewhere" end
	local mine = myFaction()
	local rec
	for i = 3, #entry do
		local r = entry[i]
		if r[4] == 0 or r[4] == mine then rec = r break end
	end
	rec = rec or entry[3]
	local kind, place, who = rec[1], rec[2], rec[3]
	if kind == "drop" then
		return (who ~= "" and place ~= "") and (place .. UI.SEP .. who) or (place ~= "" and place or "Drop"), place ~= "" and place or "World drops"
	elseif kind == "vendor" then
		return "Vendor" .. UI.SEP .. who .. (place ~= "" and (", " .. place) or ""), place ~= "" and place or "Vendors"
	elseif kind == "quest" then
		return "Quest" .. UI.SEP .. who, place ~= "" and place or "Quests"
	elseif kind == "crafted" then
		return place, place
	elseif kind == "rep" then
		return place .. " reputation", place
	elseif kind == "pvp" then
		return "PvP", "PvP"
	end
	return "World drop", "World drops"
end

function BiS:Name(id)
	local name = C_Item and C_Item.GetItemNameByID and call(C_Item.GetItemNameByID, id)
	if type(name) == "string" and name ~= "" and not Stoa:IsSecret(name) then return name end
	if C_Item and C_Item.RequestLoadItemDataByID then call(C_Item.RequestLoadItemDataByID, id) end
	local entry = data() and data().items[id]
	return entry and entry[1] or ("Item " .. id)
end

function BiS:Quality(id)
	local entry = data() and data().items[id]
	return entry and entry[2] or 1
end

-- "worn", "have" (bags or bank) or "need".
function BiS:State(id, invSlot)
	if GetInventoryItemID then
		if call(GetInventoryItemID, "player", invSlot) == id then return "worn" end
		local pair = PAIR[invSlot]
		if pair and call(GetInventoryItemID, "player", pair) == id then return "worn" end
	end
	local count = C_Item and C_Item.GetItemCount and Stoa:PlainNumber(call(C_Item.GetItemCount, id, true))
	if count and count > 0 then return "have" end
	return "need"
end

-- Each slot of the build with its state, in the build's order.
function BiS:Rows(build)
	local rows = {}
	local slots = data().slots
	for i, slot in ipairs(build.slots) do
		if slot then
			local id = slot[1]
			local words, place = self:Source(id)
			rows[#rows + 1] = {
				index = i, id = id, key = slots[i][1], invSlot = slots[i][2], suffix = slot[2], alts = slot[3],
				state = self:State(id, slots[i][2]), source = words, place = place,
			}
		end
	end
	return rows
end

-- The picks still to get, by place, the place with most first.
function BiS:Places(rows)
	local by, order = {}, {}
	for _, row in ipairs(rows) do
		if row.state == "need" then
			if not by[row.place] then
				by[row.place] = {}
				order[#order + 1] = row.place
			end
			table.insert(by[row.place], row)
		end
	end
	table.sort(order, function(a, b)
		if #by[a] ~= #by[b] then return #by[a] > #by[b] end
		return a < b
	end)
	return order, by
end

-- Marks ------------------------------------------------------------------------

-- A diamond in a button's foot-right corner: filled for the pick, open for
-- an alternate, gone for anything else.
function BiS:Mark(button, item)
	if not (button and button.CreateTexture) then return end
	local rank = item and self:Rank(item)
	local mark = button.stoaBiS
	if not rank then
		if mark then mark:Hide() end
		return
	end
	if not mark then
		mark = button:CreateTexture(nil, "OVERLAY", nil, 7)
		mark:SetSize(11, 11)
		mark:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -3, 3)
		button.stoaBiS = mark
	end
	mark:SetTexture(rank == 1 and DIAMOND or OPEN)
	mark:SetVertexColor(Stoa:Color("accent"))
	mark:Show()
end

local function inline(rank)
	return "|T" .. (rank == 1 and DIAMOND or OPEN) .. ":0|t "
end

-- Lines on an item's tooltip. On the character sheet a slot that doesn't
-- hold its pick says what the pick is.
function BiS:TooltipLines(tip, link)
	if not self:Enabled() or not link or Stoa:IsSecret(link) then return end
	local id = Stoa.Items.id(link)
	if not id then return end
	local added = false
	local rank, _, build = self:Rank(id)
	local ar, ag, ab = Stoa:Color("accent")
	local mr, mg, mb = Stoa:Color("muted")
	if rank then
		local label = rank == 1 and "BiS" or ("BiS #" .. rank)
		tip:AddLine(inline(rank) .. label .. UI.SEP .. build.name, ar, ag, ab)
		tip:AddLine(self:Source(id), mr, mg, mb)
		added = true
	else
		local other, otherBuild = self:OtherRank(id)
		if other then
			tip:AddLine(inline(other) .. (other == 1 and "BiS" or "BiS #" .. other) .. UI.SEP .. otherBuild.name, mr, mg, mb)
			added = true
		end
	end
	-- Hovering a slot on the sheet: its pick, when you don't wear it.
	local owner = tip.GetOwner and tip:GetOwner()
	local ownerName = owner and owner.GetName and owner:GetName()
	if rank ~= 1 and type(ownerName) == "string" and ownerName:match("^Character.+Slot$") and owner.GetID then
		local pick = self:PickFor(owner:GetID())
		if pick and pick ~= id then
			tip:AddLine(inline(1) .. "BiS here: " .. self:Name(pick), ar, ag, ab)
			tip:AddLine(self:Source(pick), mr, mg, mb)
			added = true
		end
	end
	if added then tip:Show() end
end

-- The pick for an inventory slot in your current build.
function BiS:PickFor(invSlot)
	local build = self:Enabled() and self:Build()
	if not build then return nil end
	for i, entry in ipairs(data().slots) do
		if entry[2] == invSlot and build.slots[i] then
			-- For a ring or trinket the slot's own pick, or the pair's other
			-- one when you wear this slot's elsewhere.
			local id = build.slots[i][1]
			local pair = PAIR[invSlot]
			if pair and call(GetInventoryItemID, "player", pair) == id then
				for j, other in ipairs(data().slots) do
					if other[2] == pair and build.slots[j] then return build.slots[j][1] end
				end
			end
			return id
		end
	end
end

-- Vendors and quest rewards --------------------------------------------------------

function BiS:MarkMerchant()
	if not (MerchantFrame and MerchantFrame:IsShown() and GetMerchantItemLink) then return end
	local perPage = rawget(_G, "MERCHANT_ITEMS_PER_PAGE") or 10
	local page = MerchantFrame.page or 1
	local buying = (MerchantFrame.selectedTab or 1) == 1
	for i = 1, perPage do
		local button = _G["MerchantItem" .. i .. "ItemButton"]
		if button then
			local link = buying and call(GetMerchantItemLink, (page - 1) * perPage + i)
			self:Mark(button, type(link) == "string" and link or nil)
		end
	end
end

function BiS:MarkRewards()
	local frame = rawget(_G, "QuestInfoRewardsFrame")
	local buttons = frame and frame.RewardButtons
	if type(buttons) ~= "table" then return end
	local inLog = QuestInfoFrame and QuestInfoFrame.questLog
	for _, button in ipairs(buttons) do
		local link
		if button:IsShown() and button.type and button.GetID then
			local get = inLog and GetQuestLogItemLink or GetQuestItemLink
			link = get and call(get, button.type, button:GetID())
		end
		self:Mark(button, type(link) == "string" and link or nil)
	end
end

-- The pane ---------------------------------------------------------------------

local WIDTH, PAD, HEADER, ROW_H, HEAD_H, FOOT_H = 360, 16, 74, 34, 26, 36

local function rowButton(pane, i)
	local row = pane.rows[i]
	if row then return row end
	row = CreateFrame("Button", nil, pane)
	row:SetHeight(ROW_H)
	row.icon = row:CreateTexture(nil, "ARTWORK")
	row.icon:SetSize(26, 26)
	row.icon:SetPoint("LEFT", 0, 0)
	row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	row.state = UI.text(row, "sans", Stoa.typeSize.caption, "muted", "RIGHT")
	row.state:SetPoint("RIGHT", 0, 0)
	row.mark = row:CreateTexture(nil, "OVERLAY")
	row.mark:SetSize(10, 10)
	row.mark:SetPoint("RIGHT", row.state, "LEFT", -5, 0)
	row.name = UI.text(row, "sans", Stoa.typeSize.body, "text", "LEFT")
	row.name:SetPoint("TOPLEFT", row.icon, "TOPRIGHT", 10, 0)
	row.name:SetPoint("RIGHT", row.mark, "LEFT", -8, 0)
	row.name:SetWordWrap(false)
	row.sub = UI.text(row, "sans", Stoa.typeSize.caption, "muted", "LEFT")
	row.sub:SetPoint("BOTTOMLEFT", row.icon, "BOTTOMRIGHT", 10, 0)
	row.sub:SetPoint("RIGHT", row.mark, "LEFT", -8, 0)
	row.sub:SetWordWrap(false)
	row.head = UI.text(row, "serif", Stoa.typeSize.label, "accent", "LEFT")
	row.head:SetPoint("LEFT", 0, -2)
	row.count = UI.text(row, "sans", Stoa.typeSize.caption, "muted", "RIGHT")
	row.count:SetPoint("RIGHT", 0, -2)
	local glow = row:CreateTexture(nil, "BACKGROUND")
	glow:SetPoint("TOPLEFT", -6, 0)
	glow:SetPoint("BOTTOMRIGHT", 6, 0)
	glow:SetTexture(UI.WHITE)
	glow:Hide()
	row.glow = glow
	row:SetScript("OnEnter", function(own)
		if not own.data then return end
		local r, g, b = Stoa:Color("text")
		glow:SetVertexColor(r, g, b, 0.06)
		glow:Show()
		BiS:RowTooltip(own)
	end)
	row:SetScript("OnLeave", function()
		glow:Hide()
		GameTooltip:Hide()
	end)
	pane.rows[i] = row
	return row
end

-- The game's own item tooltip, then the alternates under it.
function BiS:RowTooltip(row)
	local d = row.data
	GameTooltip:SetOwner(row, "ANCHOR_LEFT")
	if GameTooltip.SetItemByID then GameTooltip:SetItemByID(d.id) else GameTooltip:SetText(self:Name(d.id)) end
	local mr, mg, mb = Stoa:Color("muted")
	if d.suffix then GameTooltip:AddLine("The pick is the one " .. d.suffix .. ".", mr, mg, mb) end
	if d.alts and #d.alts > 0 then
		GameTooltip:AddLine(" ")
		GameTooltip:AddLine("Next best", Stoa:Color("accent"))
		for rank, alt in ipairs(d.alts) do
			local r, g, b = Stoa.ItemSkin.qualityColour(self:Quality(alt))
			GameTooltip:AddDoubleLine(inline(rank + 1) .. self:Name(alt), self:Source(alt), r or 1, g or 1, b or 1, mr, mg, mb)
		end
	end
	GameTooltip:Show()
end

local function word(parent, onClick)
	local button = CreateFrame("Button", nil, parent)
	button.text = UI.text(button, "sans", Stoa.typeSize.body, "muted", "CENTER")
	button.text:SetPoint("CENTER", 0, 1)
	button.under = button:CreateTexture(nil, "OVERLAY")
	button.under:SetHeight(2)
	button.under:SetPoint("BOTTOMLEFT", 0, 2)
	button.under:SetPoint("BOTTOMRIGHT", 0, 2)
	button.under:SetColorTexture(1, 1, 1)
	button:SetScript("OnClick", onClick)
	function button:Set(words, on)
		self.text:SetText(words)
		self:SetSize(math.ceil(self.text:GetStringWidth()) + 4, 24)
		self.text:SetTextColor(Stoa:Color(on and "accent" or "muted"))
		self.under:SetVertexColor(Stoa:Color("accent"))
		self.under:SetShown(on and true or false)
	end
	return button
end

function BiS:BuildPane()
	local pane = CreateFrame("Frame", "StoaBiS", UIParent)
	pane:SetSize(WIDTH, 400)
	pane:SetFrameStrata("HIGH")
	pane:SetToplevel(true)
	pane:EnableMouse(true)
	pane:Hide()
	UI.windowPanel(pane, 0.96, { header = HEADER, plainHeader = true })
	UI.riseOnShow(pane)
	table.insert(UISpecialFrames, "StoaBiS")

	local title = UI.text(pane, "serif", Stoa.typeSize.title, "text", "LEFT")
	title:SetPoint("TOPLEFT", PAD, -14)
	title:SetText("Best in slot")
	local close = CreateFrame("Button", nil, pane)
	close:SetSize(20, 20)
	close:SetPoint("TOPRIGHT", -12, -14)
	local cross = UI.glyph(close, "Cross", 14, "muted")
	cross:SetPoint("CENTER")
	close:SetScript("OnClick", function() pane:Hide() end)
	close:SetScript("OnEnter", function() cross:SetVertexColor(Stoa:Color("accent")) end)
	close:SetScript("OnLeave", function() cross:SetVertexColor(Stoa:Color("muted")) end)
	-- The build: its name, a click moves to the next, hover lists them.
	local build = word(pane, function(own, mouse)
		local list = self:Builds()
		if #list < 2 then return end
		local current = self:Build()
		local at = 1
		for i, b in ipairs(list) do if b == current then at = i end end
		at = mouse == "RightButton" and (at - 2) % #list + 1 or at % #list + 1
		self:Pick(list[at].name)
		self:ShowBuilds(own)
	end)
	build:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	build:SetPoint("TOPLEFT", title, "BOTTOMLEFT", -2, -4)
	build:SetScript("OnEnter", function(own) self:ShowBuilds(own) end)
	build:SetScript("OnLeave", function() GameTooltip:Hide() end)
	local from = UI.text(pane, "sans", Stoa.typeSize.caption, "muted", "LEFT")
	from:SetPoint("LEFT", build, "RIGHT", 8, -1)

	-- Progress: "6 of 16 worn" over a bar, worn in the accent and the ones
	-- you have in the mana blue.
	local count = UI.text(pane, "sans", Stoa.typeSize.caption, "text", "LEFT")
	count:SetPoint("TOPLEFT", PAD, -HEADER - 12)
	local bar = CreateFrame("Frame", nil, pane)
	bar:SetHeight(4)
	bar:SetPoint("TOPLEFT", PAD, -HEADER - 30)
	bar:SetPoint("TOPRIGHT", -PAD, -HEADER - 30)
	bar.back = bar:CreateTexture(nil, "BACKGROUND")
	bar.back:SetAllPoints()
	bar.back:SetTexture(UI.WHITE)
	bar.worn = bar:CreateTexture(nil, "ARTWORK")
	bar.worn:SetTexture(UI.WHITE)
	bar.worn:SetPoint("TOPLEFT")
	bar.worn:SetPoint("BOTTOMLEFT")
	bar.have = bar:CreateTexture(nil, "ARTWORK")
	bar.have:SetTexture(UI.WHITE)
	bar.have:SetPoint("TOPLEFT", bar.worn, "TOPRIGHT")
	bar.have:SetPoint("BOTTOMLEFT", bar.worn, "BOTTOMRIGHT")

	-- Footer: by slot or by place, and the data's date.
	local bySlot = word(pane, function() self.db.view = "slot" self:Fill() end)
	bySlot:SetPoint("BOTTOMLEFT", PAD - 2, (FOOT_H - 24) / 2)
	local byPlace = word(pane, function() self.db.view = "place" self:Fill() end)
	byPlace:SetPoint("LEFT", bySlot, "RIGHT", 14, 0)
	local note = UI.text(pane, "sans", Stoa.typeSize.caption, "muted", "RIGHT")
	note:SetPoint("BOTTOMRIGHT", -PAD, FOOT_H / 2 - 6)
	local import = word(pane, function() self:ShowImport() end)
	import:SetPoint("BOTTOMRIGHT", -PAD + 2, (FOOT_H - 24) / 2)
	import:Set("Import", false)
	local remove = word(pane, function()
		local build = self:Build()
		if build and build.mine then self:Remove(build) end
	end)
	remove:SetPoint("RIGHT", import, "LEFT", -14, 0)
	remove:Set("Remove list", false)
	pane.import, pane.remove = import, remove

	pane.build, pane.from, pane.count, pane.bar = build, from, count, bar
	pane.bySlot, pane.byPlace, pane.note, pane.rows = bySlot, byPlace, note, {}
	pane:SetScript("OnShow", function() self:Fill() end)
	self.pane = pane
end

function BiS:ShowBuilds(owner)
	local list = self:Builds()
	if #list < 2 then return end
	local current = self:Build()
	GameTooltip:SetOwner(owner, "ANCHOR_BOTTOM")
	GameTooltip:AddLine("Builds")
	for _, b in ipairs(list) do
		local r, g, b2 = Stoa:Color(b == current and "accent" or "text")
		GameTooltip:AddLine(b.name, r, g, b2)
	end
	GameTooltip:AddLine("Click for the next, right-click for the one before.", Stoa:Color("muted"))
	GameTooltip:Show()
end

-- A box to paste lists into (one per line, as Tools/bis/build.py writes
-- them); Import adds them, Escape closes.
function BiS:ShowImport()
	local box = self.importBox
	if not box then
		box = CreateFrame("Frame", nil, self.pane)
		box:SetPoint("TOPLEFT", self.pane, "TOPLEFT", 8, -HEADER)
		box:SetPoint("BOTTOMRIGHT", self.pane, "BOTTOMRIGHT", -8, FOOT_H)
		box:SetFrameLevel(self.pane:GetFrameLevel() + 20)
		box:EnableMouse(true)
		UI.roundPanel(box, 0.98)
		local hint = UI.text(box, "sans", Stoa.typeSize.body, "muted", "LEFT")
		hint:SetPoint("TOPLEFT", PAD - 8, -12)
		hint:SetPoint("RIGHT", box, "RIGHT", -PAD, 0)
		hint:SetText("Paste lists here, one per line (STOA-BIS1|...). They stay on your account.")
		local scroll = CreateFrame("ScrollFrame", nil, box, "UIPanelScrollFrameTemplate")
		scroll:SetPoint("TOPLEFT", 8, -48)
		scroll:SetPoint("BOTTOMRIGHT", -28, 44)
		local edit = CreateFrame("EditBox", nil, scroll)
		edit:SetMultiLine(true)
		edit:SetAutoFocus(false)
		edit:SetWidth(WIDTH - 60)
		Stoa:SetFont(edit, "sans", Stoa.typeSize.caption)
		edit:SetScript("OnEscapePressed", function() box:Hide() end)
		scroll:SetScrollChild(edit)
		local go = UI.button(box, "Import", 90, function()
			local n = self:Import(edit:GetText())
			if n > 0 then
				Stoa:Print(("added %d BiS %s."):format(n, n == 1 and "list" or "lists"))
				edit:SetText("")
				box:Hide()
			else
				hint:SetText("Nothing to import: each list starts with STOA-BIS1|.")
			end
		end)
		go:SetPoint("BOTTOMRIGHT", -12, 10)
		local cancel = UI.button(box, "Cancel", 90, function() box:Hide() end)
		cancel:SetPoint("RIGHT", go, "LEFT", -8, 0)
		box.edit = edit
		self.importBox = box
	end
	box:Show()
	box.edit:SetFocus()
end

-- Beside the character window when it's open, else in the middle.
function BiS:Place()
	local pane = self.pane
	pane:ClearAllPoints()
	if CharacterFrame and CharacterFrame:IsShown() then
		pane:SetPoint("TOPLEFT", CharacterFrame, "TOPRIGHT", 10, 0)
	else
		pane:SetPoint("CENTER", UIParent, "CENTER", 0, 60)
	end
end

function BiS:Toggle()
	if not self:Enabled() then return end
	if InCombatLockdown() and not self.pane then return end
	if not self.pane then self:BuildPane() end
	if self.pane:IsShown() then
		self.pane:Hide()
	else
		self:Place()
		self.pane:Show()
	end
	self:PaintWord()
end

function BiS:Fill()
	local pane = self.pane
	if not (pane and pane:IsShown()) then return end
	for _, row in ipairs(pane.rows) do row:Hide() end
	local build = self:Build()
	local multi = #self:Builds() > 1
	pane.build:Set(build and build.name or "No list for this spec yet", multi)
	pane.build.text:SetTextColor(Stoa:Color(build and "accent" or "muted"))
	pane.build.under:SetShown(false)
	local date = self:Date()
	local credit = build and (build.mine and (build.credit or "Imported") or ("WoWSims" .. (date and (", " .. date) or "")))
	pane.from:SetText(credit or "")
	pane.bySlot:Set("By slot", self.db.view ~= "place")
	pane.byPlace:Set("By place", self.db.view == "place")
	pane.note:SetText("")
	pane.remove:SetShown(build and build.mine and true or false)
	if not build then
		pane.count:SetText("")
		pane.bar:Hide()
		pane:SetHeight(HEADER + 60 + FOOT_H)
		return
	end
	local rows = self:Rows(build)
	local worn, have = 0, 0
	for _, row in ipairs(rows) do
		if row.state == "worn" then worn = worn + 1 elseif row.state == "have" then have = have + 1 end
	end
	pane.count:SetText(("%d of %d worn"):format(worn, #rows) .. (have > 0 and (UI.SEP .. have .. " in bags") or ""))
	local full = WIDTH - PAD * 2
	local tr, tg, tb = Stoa:Color("text")
	pane.bar.back:SetVertexColor(tr, tg, tb, 0.1)
	pane.bar.worn:SetVertexColor(Stoa:Color("accent"))
	pane.bar.have:SetVertexColor(Stoa:Color("mana"))
	pane.bar.worn:SetWidth(math.max(0.01, full * worn / #rows))
	pane.bar.have:SetWidth(math.max(0.01, full * have / #rows))
	pane.bar:Show()

	local y = -HEADER - 46
	local used = 0
	local function place(row, height)
		row:ClearAllPoints()
		row:SetPoint("TOPLEFT", pane, "TOPLEFT", PAD, y)
		row:SetPoint("TOPRIGHT", pane, "TOPRIGHT", -PAD, y)
		row:SetHeight(height)
		row:Show()
		y = y - height
	end
	local function item(d, sub)
		used = used + 1
		local row = rowButton(pane, used)
		row.data = d
		row.head:Hide()
		row.count:Hide()
		for _, part in ipairs({ row.icon, row.name, row.sub, row.state, row.mark }) do part:Show() end
		row.icon:SetTexture((C_Item and C_Item.GetItemIconByID and call(C_Item.GetItemIconByID, d.id)) or 134400)
		row.name:SetText(self:Name(d.id) .. (d.suffix and (" " .. d.suffix) or ""))
		local r, g, b = Stoa.ItemSkin.qualityColour(self:Quality(d.id))
		if r then row.name:SetTextColor(r, g, b) else row.name:SetTextColor(Stoa:Color("text")) end
		row.name:SetAlpha(d.state == "need" and 0.8 or 1)
		row.sub:SetText(sub)
		local token = d.state == "worn" and "accent" or d.state == "have" and "mana" or "muted"
		row.mark:SetTexture(d.state == "worn" and DIAMOND or OPEN)
		row.mark:SetVertexColor(Stoa:Color(token))
		row.mark:SetAlpha(d.state == "need" and 0.5 or 1)
		row.state:SetText(d.state == "worn" and "Worn" or d.state == "have" and "In bags" or "")
		row.state:SetTextColor(Stoa:Color(token))
		place(row, ROW_H)
	end
	local function head(words, right)
		used = used + 1
		local row = rowButton(pane, used)
		row.data = nil
		for _, part in ipairs({ row.icon, row.name, row.sub, row.state, row.mark }) do part:Hide() end
		row.head:SetText(words)
		row.count:SetText(right or "")
		row.head:Show()
		row.count:Show()
		place(row, HEAD_H)
	end
	if self.db.view == "place" then
		local order, by = self:Places(rows)
		if #order == 0 then head("Nothing left to get") end
		for _, where in ipairs(order) do
			head(where, #by[where] .. " to get")
			for _, d in ipairs(by[where]) do item(d, SLOT_WORDS[d.key] .. UI.SEP .. d.source) end
		end
	else
		for _, d in ipairs(rows) do item(d, SLOT_WORDS[d.key] .. UI.SEP .. d.source) end
	end
	pane:SetHeight(-y + 8 + FOOT_H)
end

-- The footer word on the character sheet: left of the sheet's own words.
function BiS:SheetWord()
	local character = Stoa.modules.Character
	local bar = character and character.footerBar
	if not bar or self.sheetWord or not self:Enabled() then return end
	local button = word(bar, function() self:Toggle() end)
	button:SetScript("OnEnter", function(own)
		GameTooltip:SetOwner(own, "ANCHOR_TOP")
		GameTooltip:SetText("Best in slot")
		GameTooltip:AddLine("Your spec's pre-raid list beside the sheet.", Stoa:Color("muted"))
		GameTooltip:Show()
	end)
	button:SetScript("OnLeave", function() GameTooltip:Hide() end)
	self.sheetWord = button
	self:PaintWord()
end

function BiS:PaintWord()
	local button = self.sheetWord
	if not button then return end
	local bar = button:GetParent()
	local left
	for _, w in ipairs(bar.words or {}) do
		if w:IsShown() and (not left or w:GetLeft() and left:GetLeft() and w:GetLeft() < left:GetLeft()) then left = w end
	end
	button:ClearAllPoints()
	if left then
		button:SetPoint("RIGHT", left, "LEFT", -18, 0)
	else
		button:SetPoint("RIGHT", bar, "RIGHT", -22, 0)
	end
	button:Set("BiS", self.pane and self.pane:IsShown())
end

-- Console and dungeon card -----------------------------------------------------------

-- At max level, under "Level 60" on the Journey column: the place with the
-- most picks still to get. Click opens the pane by place.
function BiS:UpdateConsole()
	local console = Stoa.modules.Grimoire
	local level = console and console.levelText
	if not level then return end
	local line = self.consoleLine
	local maxLevel = GetMaxPlayerLevel and GetMaxPlayerLevel()
	local build = self:Enabled() and maxLevel and UnitLevel("player") >= maxLevel and self:Build()
	local words
	if build then
		local order, by = self:Places(self:Rows(build))
		if order[1] then
			local n = #by[order[1]]
			words = ("Next BiS: %s" .. UI.SEP .. "%d %s"):format(order[1], n, n == 1 and "piece" or "pieces")
		end
	end
	if not words then
		if line then line:Hide() end
		return
	end
	if not line then
		line = CreateFrame("Button", nil, level:GetParent())
		line:SetHeight(14)
		line.mark = line:CreateTexture(nil, "ARTWORK")
		line.mark:SetSize(9, 9)
		line.mark:SetPoint("LEFT", 0, 0)
		line.mark:SetTexture(DIAMOND)
		line.text = UI.text(line, "sans", Stoa.typeSize.body, "accent", "LEFT")
		line.text:SetPoint("LEFT", line.mark, "RIGHT", 6, 0)
		line.text:SetWordWrap(false)
		line:SetScript("OnClick", function()
			if InCombatLockdown() then return end
			self.db.view = "place"
			if not (self.pane and self.pane:IsShown()) then self:Toggle() else self:Fill() end
		end)
		line:SetScript("OnEnter", function(own)
			own.text:SetTextColor(Stoa:Color("text"))
			GameTooltip:SetOwner(own, "ANCHOR_TOP")
			GameTooltip:SetText("Best in slot")
			GameTooltip:AddLine("Click for your list by place.", Stoa:Color("muted"))
			GameTooltip:Show()
		end)
		line:SetScript("OnLeave", function(own)
			own.text:SetTextColor(Stoa:Color("accent"))
			GameTooltip:Hide()
		end)
		line:SetPoint("TOPLEFT", level, "BOTTOMLEFT", 0, -8)
		self.consoleLine = line
	end
	line.text:SetText(words)
	line.mark:SetVertexColor(Stoa:Color("accent"))
	line:SetWidth(math.ceil(line.text:GetStringWidth()) + 16)
	line:Show()
end

-- The picks a dungeon drops, for the companion's card: { name, boss, got }.
function BiS:Here(where)
	local build = self:Enabled() and where and self:Build()
	if not build then return {} end
	local list = {}
	local dungeons = Stoa.Dungeons
	for _, row in ipairs(self:Rows(build)) do
		local entry = data().items[row.id]
		for i = 3, #(entry or {}) do
			local r = entry[i]
			if r[1] == "drop" and (r[2] == where.name or (dungeons and dungeons.find and where.dungeon and dungeons.find(r[2]) == where.dungeon)) then
				list[#list + 1] = { name = self:Name(row.id), boss = r[3], got = row.state ~= "need" }
				break
			end
		end
	end
	return list
end

-- Wiring -------------------------------------------------------------------------

function BiS:Changed()
	if self.pane and self.pane:IsShown() then self:Fill() end
	self:PaintWord()
	self:UpdateConsole()
	local bags = Stoa.modules.Bags
	if bags and bags.Refresh then pcall(bags.Refresh, bags) end
	local companion = Stoa.modules.Companion
	if companion and companion.Refresh then pcall(companion.Refresh, companion) end
end

function BiS:OnEnable()
	if not data() then return end
	Stoa.commands.bis = function(rest)
		if rest and rest:find("^%s*STOA%-BIS1") then
			Stoa:Print(("added %d BiS list(s)."):format(self:Import(rest)))
		else
			self:Toggle()
		end
	end
	local soon
	local function later()
		if soon then return end
		soon = true
		C_Timer.After(0.5, function()
			soon = false
			if self.pane and self.pane:IsShown() then self:Fill() end
			self:UpdateConsole()
		end)
	end
	Stoa:On("BAG_UPDATE_DELAYED", later)
	Stoa:On("PLAYER_EQUIPMENT_CHANGED", later)
	Stoa:On("PLAYER_LEVEL_UP", later)
	Stoa:On("PLAYER_ENTERING_WORLD", later)
	Stoa:On("STOA_ROLE_CHANGED", function() self:Changed() end)
	Stoa:On("MERCHANT_SHOW", function() self:MarkMerchant() end)
	if rawget(_G, "MerchantFrame_UpdateMerchantInfo") then
		hooksecurefunc("MerchantFrame_UpdateMerchantInfo", function() xpcall(self.MarkMerchant, Stoa.catch, self) end)
	end
	if rawget(_G, "QuestInfo_Display") then
		hooksecurefunc("QuestInfo_Display", function() xpcall(self.MarkRewards, Stoa.catch, self) end)
	end
	local character = Stoa.modules.Character
	if character and character.PaintSidebarWords then
		hooksecurefunc(character, "PaintSidebarWords", function()
			xpcall(function()
				self:SheetWord()
				self:PaintWord()
			end, Stoa.catch)
		end)
	end
	if CharacterFrame then
		CharacterFrame:HookScript("OnHide", function()
			if self.pane and self.pane:IsShown() and self.pane:GetPoint(1) == "TOPLEFT" then self.pane:Hide() end
		end)
	end
end
