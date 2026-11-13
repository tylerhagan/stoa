-- Stoa: the spellbook in STOA's dress.
-- Forever's spellbook is Blizzard's new one (search, all ranks, school
-- tabs), so STOA keeps it and its spell buttons (dragging to bars, casting,
-- tooltips) and only redraws around them: the book's parchment goes so the
-- window's dark panel shows, the spell names take STOA's type, and a "To
-- train" word opens STOA's training page docked beside the book.
--
-- MoreWindows already gives PlayerSpellsFrame its panel and header band.
-- Nothing secure is moved; the items are hooked through Blizzard's mixin
-- (hooksecurefunc), so they're dressed as the book draws them.
local _, ns = ...
local Stoa = ns.Stoa
local UI = Stoa.UI

local Spellbook = Stoa:NewModule("Spellbook", { layout = true, view = "list", talents = true })

local hide = Stoa.frames.hide
local guarded = Stoa.safe.guarded

local function on()
	return Spellbook.db and Spellbook.db.layout ~= false
end

-- The book's own art: the parchment pages, the top bar, the bookmark and the
-- page-turn corner.
local ART = { "TopBar", "BookBGHalved", "BookBGLeft", "BookBGRight", "Bookmark", "BookCornerFlipbook" }

local function hideBook(book)
	for _, key in ipairs(ART) do hide(book[key]) end
end

-- One spell: its name in STOA's type and light, the rank or "Passive"
-- under it quiet, "Available at level 30" or "Trainable" in the accent.
-- Blizzard fades unlearned ones by alpha, which this keeps.
function Spellbook.DressItem(item)
	if not (item and item.Name) then return end
	if not item.stoaDressed then
		item.stoaDressed = true
		hide(item.Backplate)
		Stoa:SetFont(item.Name, "sans", Stoa.typeSize.label)
		if item.SubName then Stoa:SetFont(item.SubName, "sans", Stoa.typeSize.caption) end
		if item.RequiredLevel then Stoa:SetFont(item.RequiredLevel, "sans", Stoa.typeSize.caption) end
	end
	item.Name:SetTextColor(Stoa:Color("text"))
	if item.SubName then item.SubName:SetTextColor(Stoa:Color("muted")) end
	if item.RequiredLevel then item.RequiredLevel:SetTextColor(Stoa:Color("accent")) end
end

-- "To train · 3": opens STOA's training page beside the book.
local function trainerWord(frame, book)
	if frame.stoaTrainWord then return frame.stoaTrainWord end
	local word = CreateFrame("Button", nil, book)
	word:SetHeight(24)
	word.text = UI.text(word, "sans", Stoa.typeSize.body, "accent", "RIGHT")
	word.text:SetPoint("RIGHT")
	word:SetScript("OnClick", function() Spellbook:ToggleTraining() end)
	word:SetScript("OnEnter", function(self)
		self.text:SetTextColor(Stoa:Color("text"))
		GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
		GameTooltip:SetText("Training")
		GameTooltip:AddLine("What your trainer has for you now and what the next levels bring, with what each costs.", 1, 1, 1, true)
		GameTooltip:Show()
	end)
	word:SetScript("OnLeave", function(self)
		GameTooltip:Hide()
		Spellbook:PaintTrainerWord()
	end)
	-- Left of Blizzard's search box, on the book's top row.
	local search = book.SearchBox
	if search then
		word:SetPoint("RIGHT", search, "LEFT", -24, 0)
	else
		word:SetPoint("TOPRIGHT", book, "TOPRIGHT", -280, -26)
	end
	frame.stoaTrainWord = word
	return word
end

function Spellbook:PaintTrainerWord()
	local frame = PlayerSpellsFrame
	local word = frame and frame.stoaTrainWord
	if not word then return end
	local trainer = Stoa.modules.Trainer
	local enabled = trainer and trainer.enabled and trainer.Count
	word:SetShown(enabled and true or false)
	if not enabled then return end
	local count = trainer:Count()
	local label = "To train"
	word.text:SetText(count > 0 and (label .. UI.WIDE_SEP .. count) or label)
	word.text:SetTextColor(Stoa:Color(count > 0 and "accent" or "muted"))
	word:SetWidth(math.ceil(word.text:GetStringWidth()) + 4)
end

-- The training page, docked to the book's right edge while the book is open.
function Spellbook:ToggleTraining()
	local trainer = Stoa.modules.Trainer
	if not (trainer and trainer.Open) then return end
	if trainer.page and trainer.page:IsShown() and trainer.page.stoaDocked then
		trainer.page:Hide()
		return
	end
	trainer:Open()
	local page, frame = trainer.page, PlayerSpellsFrame
	if not (page and frame) then return end
	page:ClearAllPoints()
	page:SetPoint("TOPLEFT", frame, "TOPRIGHT", 10, 0)
	page.stoaDocked = true
	if not page.stoaUndock then
		page.stoaUndock = true
		page:HookScript("OnDragStart", function(self) self.stoaDocked = nil end)
	end
end

-- The list view ----------------------------------------------------------
-- Every spell you know on one scrolling page, grouped by school: its rank,
-- what it costs, its cast time and when its next rank comes (or "Train now").
-- It lies over Blizzard's pages, which fade out under it; a word on the
-- book's top row switches back to them. Each row is a secure spell button,
-- so a click casts, a drag puts it on a bar and Shift-click links it. Rows
-- are filled out of combat only (a secure button can't change in a fight).
local ROW_H, ROWS, LIST_TOP, LIST_BOTTOM = 32, 16, 72, 28
local COLS = { rank = 90, cost = 80, cast = 70, next = 120 }
local COL_ORDER = { "next", "cast", "cost", "rank" }
-- Narrower than this (the book's compact one-page size) the list drops
-- the cost and cast columns so the names keep room.
local WIDE = 700

-- Seats one set of column texts (a row's, or the headings) from the right,
-- leaving out cost and cast when compact. Returns the leftmost one.
local function placeColumns(set, parent, compact, point, y)
	local x, leftmost = 0, nil
	for _, key in ipairs(COL_ORDER) do
		local fs = set[key]
		local skip = compact and (key == "cost" or key == "cast")
		fs.stoaSkip = skip
		fs:ClearAllPoints()
		if not skip then
			fs:SetPoint(point, parent, point == "RIGHT" and "RIGHT" or "TOPRIGHT", -x, y or 0)
			x = x + COLS[key] + 12
			leftmost = fs
		end
		fs:SetShown(not skip)
	end
	return leftmost
end
local call = Stoa.safe.call
local bank = function() return Enum and Enum.SpellBookSpellBank and Enum.SpellBookSpellBank.Player end

local function castText(spellID, passive)
	if passive then return rawget(_G, "SPELL_PASSIVE") or "Passive" end
	local info = C_Spell and C_Spell.GetSpellInfo and call(C_Spell.GetSpellInfo, spellID)
	local ms = type(info) == "table" and Stoa:PlainNumber(info.castTime)
	if not ms then return "" end
	if ms <= 0 then return rawget(_G, "SPELL_CAST_TIME_INSTANT_NO_MANA") or "Instant" end
	local text = ("%.1f s"):format(ms / 1000):gsub("%.0 s", " s")
	return text
end

local function costText(spellID, passive)
	if passive then return "" end
	local costs = C_Spell and C_Spell.GetSpellPowerCost and call(C_Spell.GetSpellPowerCost, spellID)
	local first = type(costs) == "table" and costs[1]
	local amount = first and Stoa:PlainNumber(first.cost)
	if not amount or amount <= 0 then return "" end
	local mana = Enum and Enum.PowerType and first.type == Enum.PowerType.Mana
	return mana and tostring(amount) or (amount .. " " .. tostring(first.name or ""):lower())
end

-- When the next rank of each spell comes, by name: the level, or true when
-- your trainer has it now.
local function nextRanks()
	local trainer = Stoa.modules.Trainer
	local out = {}
	if not (trainer and trainer.enabled and trainer.Spells) then return out end
	local level = Stoa:PlainNumber(UnitLevel("player")) or 1
	for _, entry in ipairs(trainer:Spells(1, 80)) do
		local name = Stoa.Spells.name(entry.id)
		if name and not entry.skipped and out[name] == nil then
			out[name] = entry.level <= level and true or entry.level
		end
	end
	return out
end

-- Your spells as rows: a heading per school, then its spells by name, the
-- best rank of each. Search text narrows them by name.
function Spellbook:ListRows(filter)
	local rows, book = {}, C_SpellBook
	if not (book and book.GetNumSpellBookSkillLines) then return rows end
	filter = filter and filter ~= "" and filter:lower() or nil
	local upcoming = nextRanks()
	for line = 1, call(book.GetNumSpellBookSkillLines) or 0 do
		local info = call(book.GetSpellBookSkillLineInfo, line)
		if type(info) == "table" and not info.shouldHide and not info.offSpecID then
			local byName, names = {}, {}
			local first = info.itemIndexOffset or 0
			for slot = first + 1, first + (info.numSpellBookItems or 0) do
				local item = call(book.GetSpellBookItemInfo, slot, bank())
				local spell = type(item) == "table" and item.name and item.spellID
					and (not Enum.SpellBookItemType or item.itemType == Enum.SpellBookItemType.Spell)
					and not item.isOffSpec
				if spell and (not filter or item.name:lower():find(filter, 1, true)) then
					if not byName[item.name] then names[#names + 1] = item.name end
					-- The book lists ranks low to high: the last is the best.
					byName[item.name] = { slot = slot, spellID = item.spellID, name = item.name, icon = item.iconID,
						rank = item.subName, passive = item.isPassive }
				end
			end
			if #names > 0 then
				rows[#rows + 1] = { heading = (info.name or ""):upper() }
				table.sort(names)
				for _, name in ipairs(names) do
					local entry = byName[name]
					local nextAt = upcoming[name]
					entry.next = nextAt == true and "Train now" or (nextAt and ("Next at " .. nextAt)) or ""
					entry.trainNow = nextAt == true
					rows[#rows + 1] = entry
				end
			end
		end
	end
	return rows
end

local function buildRow(list, i)
	local row = CreateFrame("Button", nil, list, "SecureActionButtonTemplate")
	row:SetHeight(ROW_H)
	row:SetPoint("TOPLEFT", 0, -(i - 1) * ROW_H)
	row:SetPoint("TOPRIGHT", 0, -(i - 1) * ROW_H)
	-- On release only, so pressing to drag a spell doesn't cast it.
	row:RegisterForClicks("AnyUp")
	row:SetAttribute("useOnKeyDown", false)
	row:RegisterForDrag("LeftButton")
	-- A plain click casts; Shift-click links instead (in PostClick).
	row:SetAttribute("type1", "spell")
	row:SetAttribute("shift-type1", "stoalink")
	local hover = row:CreateTexture(nil, "BACKGROUND")
	hover:SetAllPoints()
	hover:SetColorTexture(1, 1, 1, 0.05)
	hover:Hide()
	row.hover = hover
	row.icon = row:CreateTexture(nil, "ARTWORK")
	row.icon:SetSize(ROW_H - 6, ROW_H - 6)
	row.icon:SetPoint("LEFT", 4, 0)
	row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	row.name = UI.text(row, "sans", Stoa.typeSize.label, "text", "LEFT")
	row.name:SetPoint("LEFT", row.icon, "RIGHT", 10, 0)
	row.name:SetWordWrap(false)
	row.head = UI.text(row, "sans", Stoa.typeSize.micro, "accent", "LEFT")
	row.head:SetPoint("BOTTOMLEFT", 4, 6)
	row.rule = row:CreateTexture(nil, "BORDER")
	row.rule:SetHeight(1)
	row.rule:SetPoint("BOTTOMLEFT")
	row.rule:SetPoint("BOTTOMRIGHT")
	row.rule:SetColorTexture(1, 1, 1)
	UI.tint(row.rule, "accent", 0.25)
	for _, key in ipairs(COL_ORDER) do
		local fs = UI.text(row, "sans", Stoa.typeSize.body, "muted", "LEFT")
		fs:SetWidth(COLS[key])
		fs:SetWordWrap(false)
		row[key] = fs
	end
	row:SetScript("OnEnter", function(self)
		if not self.entry or self.entry.heading then return end
		self.hover:Show()
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		if GameTooltip.SetSpellBookItem then
			pcall(GameTooltip.SetSpellBookItem, GameTooltip, self.entry.slot, bank())
		else
			GameTooltip:SetSpellByID(self.entry.spellID)
		end
		GameTooltip:Show()
	end)
	row:SetScript("OnLeave", function(self)
		self.hover:Hide()
		GameTooltip:Hide()
	end)
	row:SetScript("OnDragStart", function(self)
		local entry = self.entry
		if not entry or entry.heading or InCombatLockdown() then return end
		if C_SpellBook and C_SpellBook.PickupSpellBookItem then
			pcall(C_SpellBook.PickupSpellBookItem, entry.slot, bank())
		elseif C_Spell and C_Spell.PickupSpell then
			pcall(C_Spell.PickupSpell, entry.spellID)
		end
	end)
	row:HookScript("PostClick", function(self, _, down)
		local entry = self.entry
		if down or not (entry and not entry.heading and IsShiftKeyDown()) then return end
		local link = C_Spell and C_Spell.GetSpellLink and call(C_Spell.GetSpellLink, entry.spellID)
		if link and ChatEdit_InsertLink then ChatEdit_InsertLink(link) end
	end)
	return row
end

function Spellbook:FillList()
	local list = self.list
	if not (list and list:IsShown()) then return end
	if InCombatLockdown() then
		self.fillAfterCombat = true
		return
	end
	local book = PlayerSpellsFrame and PlayerSpellsFrame.SpellBookFrame
	local search = book and book.SearchBox and book.SearchBox:GetText()
	local rows = self:ListRows(search)
	self.rows = rows
	local compact = (list:GetWidth() or 0) < WIDE
	if list.compact ~= compact then
		list.compact = compact
		placeColumns(list.heads, list, compact, "BOTTOMRIGHT", 6)
		for _, row in ipairs(list.rows) do
			local leftmost = placeColumns(row, row, compact, "RIGHT")
			row.name:ClearAllPoints()
			row.name:SetPoint("LEFT", row.icon, "RIGHT", 10, 0)
			row.name:SetPoint("RIGHT", leftmost, "LEFT", -12, 0)
		end
	end
	local shown = math.max(1, math.floor((list:GetHeight() or ROW_H * ROWS) / ROW_H))
	shown = math.min(shown, ROWS)
	self.offset = math.min(self.offset or 0, math.max(#rows - shown, 0))
	for i, row in ipairs(list.rows) do
		local entry = i <= shown and rows[i + self.offset] or nil
		row.entry = entry
		row:SetShown(entry and true or false)
		if entry then
			local heading = entry.heading and true or false
			row.head:SetShown(heading)
			row.rule:SetShown(heading)
			row.icon:SetShown(not heading)
			row.name:SetShown(not heading)
			for _, key in ipairs(COL_ORDER) do row[key]:SetShown(not heading and not row[key].stoaSkip) end
			if heading then
				row.head:SetText(entry.heading)
				row:SetAttribute("spell", nil)
			else
				row.icon:SetTexture(entry.icon)
				row.name:SetText(entry.name)
				row.rank:SetText(entry.rank or "")
				row.cost:SetText(costText(entry.spellID, entry.passive))
				row.cast:SetText(castText(entry.spellID, entry.passive))
				row.next:SetText(entry.next)
				row.next:SetTextColor(Stoa:Color(entry.trainNow and "accent" or "muted"))
				row:SetAttribute("spell", not entry.passive and entry.spellID or nil)
			end
		end
	end
	list.empty:SetShown(#rows == 0)
end

local function buildList(book)
	local list = CreateFrame("Frame", nil, book)
	list:SetPoint("TOPLEFT", book, "TOPLEFT", 40, -LIST_TOP)
	list:SetPoint("BOTTOMRIGHT", book, "BOTTOMRIGHT", -40, LIST_BOTTOM)
	list:SetFrameLevel(book:GetFrameLevel() + 60)
	list:EnableMouse(true)
	list:EnableMouseWheel(true)
	list.rows = {}
	for i = 1, ROWS do list.rows[i] = buildRow(list, i) end
	list:SetScript("OnMouseWheel", function(_, delta)
		if InCombatLockdown() then return end
		local shown = math.min(ROWS, math.max(1, math.floor(list:GetHeight() / ROW_H)))
		local maxOffset = math.max(#(Spellbook.rows or {}) - shown, 0)
		Spellbook.offset = math.min(math.max((Spellbook.offset or 0) - delta * 3, 0), maxOffset)
		Spellbook:FillList()
	end)
	list:SetScript("OnSizeChanged", function() Spellbook:FillList() end)
	-- Column names along the top.
	list.heads = {}
	for _, key in ipairs(COL_ORDER) do
		local fs = UI.text(list, "sans", Stoa.typeSize.micro, "muted", "LEFT")
		fs:SetWidth(COLS[key])
		fs:SetText(({ next = "NEXT RANK", cast = "CAST", cost = "COST", rank = "RANK" })[key])
		list.heads[key] = fs
	end
	list.empty = UI.text(list, "sans", Stoa.typeSize.body, "muted", "CENTER")
	list.empty:SetPoint("TOP", 0, -40)
	list.empty:SetText("No spells match.")
	list:Hide()
	return list
end

-- List or Blizzard's pages, remembered.
function Spellbook:ShowView(view)
	if InCombatLockdown() then return end
	local book = PlayerSpellsFrame and PlayerSpellsFrame.SpellBookFrame
	if not book then return end
	self.db.view = view
	local listOn = view == "list"
	if listOn and not self.list then self.list = buildList(book) end
	if self.list then self.list:SetShown(listOn) end
	if book.PagedSpellsFrame then book.PagedSpellsFrame:SetAlpha(listOn and 0 or 1) end
	local word = PlayerSpellsFrame.stoaViewWord
	if word then
		word.text:SetText(listOn and "Pages" or "List")
		word:SetWidth(math.ceil(word.text:GetStringWidth()) + 4)
	end
	if listOn then self:FillList() end
end

local function viewWord(frame, book)
	local word = CreateFrame("Button", nil, book)
	word:SetHeight(24)
	word.text = UI.text(word, "sans", Stoa.typeSize.body, "muted", "RIGHT")
	word.text:SetPoint("RIGHT")
	word:SetScript("OnClick", function()
		Spellbook:ShowView(Spellbook.db.view == "list" and "pages" or "list")
	end)
	word:SetScript("OnEnter", function(self) self.text:SetTextColor(Stoa:Color("text")) end)
	word:SetScript("OnLeave", function(self) self.text:SetTextColor(Stoa:Color("muted")) end)
	local anchor = frame.stoaTrainWord
	if anchor then
		word:SetPoint("RIGHT", anchor, "LEFT", -20, 0)
	else
		word:SetPoint("TOPRIGHT", book, "TOPRIGHT", -380, -26)
	end
	frame.stoaViewWord = word
	return word
end

local function dressBook()
	local frame = PlayerSpellsFrame
	local book = frame and frame.SpellBookFrame
	if not book or book.stoaBook then return end
	book.stoaBook = true
	hideBook(book)
	-- Blizzard shows the page-turn corner again on each show.
	book:HookScript("OnShow", function(self)
		hideBook(self)
		Spellbook:PaintTrainerWord()
	end)
	if SpellBookItemMixin then
		hooksecurefunc(SpellBookItemMixin, "UpdateVisuals", function(item) guarded(Spellbook.DressItem, item) end)
	end
	trainerWord(frame, book)
	Spellbook:PaintTrainerWord()
	viewWord(frame, book)
	Stoa:AfterCombat(function() guarded(Spellbook.ShowView, Spellbook, Spellbook.db.view or "list") end)
	book:HookScript("OnShow", function()
		Stoa:AfterCombat(function() guarded(Spellbook.FillList, Spellbook) end)
	end)
	if book.SearchBox then
		book.SearchBox:HookScript("OnTextChanged", function()
			Spellbook.offset = 0
			guarded(Spellbook.FillList, Spellbook)
		end)
	end
	-- The docked training page goes with the book.
	frame:HookScript("OnHide", function()
		local trainer = Stoa.modules.Trainer
		local page = trainer and trainer.page
		if page and page.stoaDocked then page:Hide() end
	end)
end

-- Talents ---------------------------------------------------------------
-- Forever's talent window is Blizzard's node tree: three classic trees side
-- by side, Primary and Secondary tabs, loadouts, search and Apply. STOA keeps
-- every node (learning, refunds, tooltips stay Blizzard's) and redraws around
-- them: no painted spec art or rings, each tree's name and points spent as
-- words, quiet rules between the trees, the tabs as words, and a line by
-- Apply while changes are waiting. Points placed are only a preview until
-- Apply, so a build can be tried and undone freely.

local function talentsOn()
	return Spellbook.db and Spellbook.db.talents ~= false
end

-- The window's painted art; BackgroundBorder stays as the anchor Blizzard
-- places the trees from, just unseen.
local TALENT_ART = {
	"Background", "ClassBackground", "OverlayBackgroundRight", "OverlayBackgroundMid",
	"Clouds1", "Clouds2", "AirParticlesClose", "AirParticlesFar", "BottomBar",
	"BackgroundBorder", "DividerHorizontalLeft", "DividerHorizontalRight",
	"DividerVerticalLeft", "DividerVerticalRight",
}
local HEADER_ART = { "MainRing", "TextBackground", "Divider", "Icon" }
-- Blizzard spaces its tree headers this far apart (Camelot talents).
local TREE_SPACING = 400

local function hideTalentArt(talents)
	for _, key in ipairs(TALENT_ART) do
		local region = talents[key]
		if region and region.Hide then
			region:SetAlpha(0)
			region:Hide()
		end
	end
end

-- One tree's header: "SHADOW  19", the tree with the most points in the
-- accent, the rest quiet; empty trees dim further.
function Spellbook.DressTreeHeaders(talents)
	local headers = talents.treeHeaders
	if not headers then return end
	local most, top = 0, nil
	for i, header in ipairs(headers) do
		local spent = tonumber(header.Text and header.Text:GetText()) or 0
		if spent > most then most, top = spent, i end
	end
	for i, header in ipairs(headers) do
		for _, key in ipairs(HEADER_ART) do hide(header[key]) end
		local name, text = header.Name, header.Text
		if name and text then
			if not header.stoaDressed then
				header.stoaDressed = true
				Stoa:SetFont(name, "sans", Stoa.typeSize.caption)
				Stoa:SetFont(text, "serif", Stoa.typeSize.title)
				name:SetShadowOffset(0, 0)
				text:SetShadowOffset(0, 0)
				name:ClearAllPoints()
				name:SetPoint("RIGHT", header, "CENTER", -6, 0)
				name:SetJustifyH("RIGHT")
				text:ClearAllPoints()
				text:SetPoint("LEFT", header, "CENTER", 6, 0)
				text:SetJustifyH("LEFT")
			end
			name:SetText((name:GetText() or ""):upper())
			local spent = tonumber(text:GetText()) or 0
			local token = i == top and "accent" or spent > 0 and "text" or "muted"
			name:SetTextColor(Stoa:Color(token))
			text:SetTextColor(Stoa:Color(token))
		end
	end
	-- Quiet rules halfway between neighbouring trees, down to the foot.
	talents.stoaRules = talents.stoaRules or {}
	local border = talents.BackgroundBorder
	local height = border and border.GetHeight and border:GetHeight() or 0
	for i = 1, #headers - 1 do
		local rule = talents.stoaRules[i]
		if not rule then
			rule = talents:CreateTexture(nil, "BACKGROUND", nil, 1)
			UI.pixel(rule, "width")
			UI.paint(rule, "hairline")
			talents.stoaRules[i] = rule
		end
		rule:ClearAllPoints()
		rule:SetPoint("TOP", headers[i], "CENTER", TREE_SPACING / 2, 10)
		rule:SetHeight(height > 80 and height - 60 or 560)
		rule:Show()
	end
	for i = #headers, #talents.stoaRules do talents.stoaRules[i]:Hide() end
end

-- Points left: the label quiet, the number in the display face and accent.
local function dressCurrency(talents)
	local display = talents.ClassCurrencyDisplay
	if not display or display.stoaDressed then return end
	display.stoaDressed = true
	hide(display.Border)
	if display.UnspentLabel then
		Stoa:SetFont(display.UnspentLabel, "sans", Stoa.typeSize.body)
		display.UnspentLabel:SetShadowOffset(0, 0)
		display.UnspentLabel:SetTextColor(Stoa:Color("muted"))
	end
	local amount = display.CurrentAmountContainer and display.CurrentAmountContainer.CurrencyAmount
	if amount then
		Stoa:SetFont(amount, "serif", Stoa.typeSize.display)
		amount:SetShadowOffset(0, 0)
		amount:SetTextColor(Stoa:Color("accent"))
	end
end

-- Primary and Secondary as words: the chosen one in the accent with a fine
-- rule under it. Blizzard's own tab art goes.
function Spellbook.PaintTalentTabs(talents)
	local system = talents.TabSystem
	if not (system and system.GetChildren) then return end
	for _, tab in ipairs({ system:GetChildren() }) do
		if not tab.stoaDressed then
			tab.stoaDressed = true
			Stoa.frames.strip(tab)
			local label = tab.Text or (tab.GetFontString and tab:GetFontString())
			if label then
				Stoa:SetFont(label, "sans", Stoa.typeSize.label)
				label:SetShadowOffset(0, 0)
			end
			tab.stoaLabel = label
			local under = tab:CreateTexture(nil, "OVERLAY")
			UI.pixel(under, "height", 2)
			UI.paint(under, "accent")
			under:SetPoint("BOTTOMLEFT", tab, "BOTTOMLEFT", 16, 4)
			under:SetPoint("BOTTOMRIGHT", tab, "BOTTOMRIGHT", -16, 4)
			tab.stoaUnder = under
			if tab.SetTabSelected then
				hooksecurefunc(tab, "SetTabSelected", function() guarded(Spellbook.PaintTalentTabs, talents) end)
			end
		end
		Stoa.frames.strip(tab)
		local chosen = tab.isSelected
		if chosen == nil and talents.GetTab and tab.tabID then chosen = talents:GetTab() == tab.tabID end
		if tab.stoaLabel then tab.stoaLabel:SetTextColor(Stoa:Color(chosen and "accent" or "muted")) end
		tab.stoaUnder:SetShown(chosen and true or false)
	end
end

-- "Changes wait for Apply" beside the Apply button while points placed are
-- still only a preview.
function Spellbook.PaintWaiting(talents)
	local apply = talents.ApplyButton
	if not apply then return end
	local line = talents.stoaWaiting
	if not line then
		line = UI.text(talents, "sans", Stoa.typeSize.body, "accent", "LEFT")
		line:SetPoint("LEFT", apply, "RIGHT", 16, 0)
		line:SetText("Changes wait for Apply")
		talents.stoaWaiting = line
	end
	local waiting = false
	if talents.HasAnyConfigChanges and not (talents.IsInspecting and talents:IsInspecting()) then
		waiting = talents:HasAnyConfigChanges() and true or false
	end
	line:SetShown(waiting)
end

local function dressTalents()
	local frame = PlayerSpellsFrame
	local talents = frame and frame.TalentsFrame
	if not talents or talents.stoaTalents then return end
	talents.stoaTalents = true
	hideTalentArt(talents)
	-- Blizzard paints the spec art again on spec changes and each show.
	talents:HookScript("OnShow", function(self)
		hideTalentArt(self)
		guarded(Spellbook.PaintTalentTabs, self)
		guarded(Spellbook.PaintWaiting, self)
	end)
	if talents.RefreshTreeHeaders then
		hooksecurefunc(talents, "RefreshTreeHeaders", function(self) guarded(Spellbook.DressTreeHeaders, self) end)
	end
	if talents.UpdateConfigButtonsState then
		hooksecurefunc(talents, "UpdateConfigButtonsState", function(self) guarded(Spellbook.PaintWaiting, self) end)
	end
	if talents.UpdateTabs then
		hooksecurefunc(talents, "UpdateTabs", function(self) guarded(Spellbook.PaintTalentTabs, self) end)
	end
	if talents.SetTab then
		hooksecurefunc(talents, "SetTab", function(self) hideTalentArt(self) end)
	end
	dressCurrency(talents)
	local windows = Stoa.modules.Windows
	if windows and windows.DressButtonsIn then windows.DressButtonsIn(talents, 2) end
	Spellbook.DressTreeHeaders(talents)
	Spellbook.PaintTalentTabs(talents)
	Spellbook.PaintWaiting(talents)
end

local function dressPlayerSpells()
	if on() then guarded(dressBook) end
	if talentsOn() then guarded(dressTalents) end
end

function Spellbook:OnEnable()
	-- The book and the talents load with their own addon the first time
	-- either opens.
	dressPlayerSpells()
	Stoa:On("ADDON_LOADED", function(name)
		if name == "Blizzard_PlayerSpells" then dressPlayerSpells() end
	end)
	if not on() then return end
	Stoa:On("STOA_SPELLS_CHANGED", function()
		guarded(Spellbook.PaintTrainerWord, Spellbook)
		guarded(Spellbook.FillList, Spellbook)
	end)
	Stoa:On("PLAYER_REGEN_ENABLED", function()
		if Spellbook.fillAfterCombat then
			Spellbook.fillAfterCombat = nil
			guarded(Spellbook.FillList, Spellbook)
		end
	end)
	Stoa:On("PLAYER_LEVEL_UP", function() C_Timer.After(1.5, function() guarded(Spellbook.PaintTrainerWord, Spellbook) end) end)
end
