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
	-- In the window's header band, left of the maximise button: the book's
	-- top row is taken by its school tabs, which grow with your spells.
	local maximise = frame.MaximizeMinimizeButton
	local close = frame.CloseButton
	if maximise then
		word:SetPoint("RIGHT", maximise, "LEFT", -14, 0)
	elseif close then
		word:SetPoint("RIGHT", close, "LEFT", -40, 0)
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
-- Every spell you know on one scrolling page, grouped by school. Each row is
-- two lines: the name, then its rank, cost and cast time, quiet. When its
-- next rank comes ("Next at 26") or "Train now" sits in a pill on the right.
-- Passives close each school, in grey. In this view STOA's own toolbar
-- (school words and a search box) lies over Blizzard's school icons and
-- search, which fade out under it and come back for Pages; nothing of
-- Blizzard's is moved. Each row is a secure spell button, so a click casts,
-- a drag puts it on a bar and Shift-click links it. Rows are filled out of
-- combat only (a secure button can't change in a fight).
local ROW_H, HEAD_H, ROWS, LIST_TOP, LIST_BOTTOM, TOOLS_TOP, TOOLS_H = 38, 30, 18, 58, 24, 14, 30
local ICON = 26

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
	return amount .. " " .. (mana and "mana" or tostring(first.name or ""):lower())
end

-- The quiet second line: rank, cost and cast time, or what a passive is.
local function detailText(entry)
	if entry.passive then
		local rank = entry.rank or ""
		return rank ~= "" and rank or (rawget(_G, "SPELL_PASSIVE") or "Passive")
	end
	local parts = {}
	for _, part in ipairs({ entry.rank or "", costText(entry.spellID), castText(entry.spellID) }) do
		if part ~= "" then parts[#parts + 1] = part end
	end
	return table.concat(parts, UI.SEP)
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

-- A few school names Forever spells out longer than players say them
-- (the priest's "Shadow Magic" is Shadow); shown short in STOA's words,
-- headings and talent cards. The game's own names are left as they are.
local SHORT_SCHOOL = { ["Shadow Magic"] = "Shadow" }
local function schoolLabel(name)
	if type(name) ~= "string" then return name end
	return SHORT_SCHOOL[name] or SHORT_SCHOOL[name:gsub("(%a)(%w*)", function(a, b) return a:upper() .. b:lower() end)] or name
end
Spellbook.SchoolLabel = schoolLabel

-- The schools in the book's order, by name.
function Spellbook:Schools()
	local out, book = {}, C_SpellBook
	if not (book and book.GetNumSpellBookSkillLines) then return out end
	for line = 1, call(book.GetNumSpellBookSkillLines) or 0 do
		local info = call(book.GetSpellBookSkillLineInfo, line)
		if type(info) == "table" and not info.shouldHide and not info.offSpecID and info.name and (info.numSpellBookItems or 0) > 0 then
			out[#out + 1] = info.name
		end
	end
	return out
end

-- Your spells as rows: a heading per school (with its count), then its
-- spells by name, the best rank of each, passives last. Search text narrows
-- them by name; a school name keeps only that school.
function Spellbook:ListRows(filter, school)
	local rows, book = {}, C_SpellBook
	if not (book and book.GetNumSpellBookSkillLines) then return rows end
	filter = filter and filter ~= "" and filter:lower() or nil
	local upcoming = nextRanks()
	for line = 1, call(book.GetNumSpellBookSkillLines) or 0 do
		local info = call(book.GetSpellBookSkillLineInfo, line)
		if type(info) == "table" and not info.shouldHide and not info.offSpecID and (not school or info.name == school) then
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
						rank = item.subName, passive = item.isPassive and true or false }
				end
			end
			if #names > 0 then
				rows[#rows + 1] = { heading = (schoolLabel(info.name) or ""):upper(), count = #names }
				table.sort(names, function(a, b)
					local pa, pb = byName[a].passive, byName[b].passive
					if pa ~= pb then return not pa end
					return a < b
				end)
				for _, name in ipairs(names) do
					local entry = byName[name]
					local nextAt = upcoming[name]
					entry.trainNow = nextAt == true
					entry.nextAt = type(nextAt) == "number" and nextAt or nil
					entry.next = entry.trainNow and "Train now" or (entry.nextAt and ("Next at " .. entry.nextAt)) or ""
					rows[#rows + 1] = entry
				end
			end
		end
	end
	return rows
end

-- "Next at 26" quiet in an outlined pill; "Train now" dark on the accent.
local function setPill(pill, entry)
	if entry.next == "" or entry.passive then
		pill:Hide()
		return
	end
	pill.text:SetText(entry.next)
	if entry.trainNow then
		pill.fill:SetVertexColor(Stoa:Color("accent"))
		pill.text:SetTextColor(0.08, 0.08, 0.09)
		pill.edge:Clear()
	else
		pill.fill:SetVertexColor(0, 0, 0, 0.3)
		pill.text:SetTextColor(Stoa:Color("muted"))
		pill.edge:Set(Stoa:Color("hairline"))
	end
	local width = pill.text:GetStringWidth()
	if not width or Stoa:IsSecret(width) or width <= 0 then width = #entry.next * 6 end
	pill:SetWidth(math.floor(width + 16 + 0.5))
	pill:Show()
end

local function buildRow(list)
	local row = CreateFrame("Button", nil, list, "SecureActionButtonTemplate")
	row:SetHeight(ROW_H)
	-- On release only, so pressing to drag a spell doesn't cast it.
	row:RegisterForClicks("AnyUp")
	row:SetAttribute("useOnKeyDown", false)
	row:RegisterForDrag("LeftButton")
	-- A plain click casts; Shift-click links instead (in PostClick).
	row:SetAttribute("type1", "spell")
	row:SetAttribute("shift-type1", "stoalink")
	-- Under the mouse: a faint lift and a short accent edge at the left.
	local hover = row:CreateTexture(nil, "BACKGROUND")
	hover:SetAllPoints()
	hover:SetColorTexture(1, 1, 1, 0.045)
	hover:Hide()
	row.hover = hover
	local edge = row:CreateTexture(nil, "ARTWORK")
	edge:SetWidth(2)
	edge:SetPoint("TOPLEFT", 0, -7)
	edge:SetPoint("BOTTOMLEFT", 0, 7)
	edge:SetTexture(UI.WHITE)
	UI.tint(edge, "accent")
	edge:Hide()
	row.edge = edge
	row.icon = row:CreateTexture(nil, "ARTWORK")
	row.icon:SetSize(ICON, ICON)
	row.icon:SetPoint("LEFT", 8, 0)
	row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	-- A dark rim a pixel round the icon, so it sits in the page.
	row.rim = row:CreateTexture(nil, "BORDER")
	row.rim:SetPoint("TOPLEFT", row.icon, -1, 1)
	row.rim:SetPoint("BOTTOMRIGHT", row.icon, 1, -1)
	row.rim:SetColorTexture(0, 0, 0, 0.7)
	-- The pill on the right, then the two lines between it and the icon.
	local pill = CreateFrame("Frame", nil, row)
	pill:SetHeight(18)
	pill:SetPoint("RIGHT", -8, 0)
	pill.fill = UI.pillFill(pill, 0)
	pill.edge = UI.pillEdge(pill, 0)
	pill.text = pill:CreateFontString(nil, "OVERLAY")
	Stoa:SetFont(pill.text, "sans", Stoa.typeSize.caption)
	pill.text:SetPoint("CENTER", 0, 0)
	pill:Hide()
	row.pill = pill
	row.name = UI.text(row, "sans", Stoa.typeSize.label, "text", "LEFT")
	row.name:SetPoint("TOPLEFT", row.icon, "TOPRIGHT", 11, 0)
	row.name:SetPoint("RIGHT", pill, "LEFT", -10, 0)
	row.name:SetWordWrap(false)
	row.detail = UI.text(row, "sans", Stoa.typeSize.caption, "muted", "LEFT")
	row.detail:SetPoint("BOTTOMLEFT", row.icon, "BOTTOMRIGHT", 11, 0)
	row.detail:SetPoint("RIGHT", pill, "LEFT", -10, 0)
	row.detail:SetWordWrap(false)
	-- A school heading: its name in the accent, the count quiet, a rule.
	row.head = UI.text(row, "sans", Stoa.typeSize.micro, "accent", "LEFT")
	row.head:SetPoint("BOTTOMLEFT", 2, 7)
	row.count = UI.text(row, "sans", Stoa.typeSize.micro, "muted", "LEFT")
	row.count:SetPoint("LEFT", row.head, "RIGHT", 8, 0)
	row.rule = row:CreateTexture(nil, "BORDER")
	row.rule:SetHeight(1)
	row.rule:SetPoint("BOTTOMLEFT")
	row.rule:SetPoint("BOTTOMRIGHT")
	row.rule:SetTexture(UI.WHITE)
	UI.tint(row.rule, "hairline")
	row:SetScript("OnEnter", function(self)
		if not self.entry or self.entry.heading then return end
		self.hover:Show()
		self.edge:Show()
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
		self.edge:Hide()
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

local function searchText()
	local box = Spellbook.tools and Spellbook.tools.box
	return box and box:GetText() or ""
end

function Spellbook:FillList()
	local list = self.list
	if not (list and list:IsShown()) then return end
	if InCombatLockdown() then
		self.fillAfterCombat = true
		return
	end
	self:PaintSchools()
	local rows = self:ListRows(searchText(), self.school)
	self.rows = rows
	-- Rows differ in height (headings are shorter), so they're stacked
	-- from the scroll offset until the list is full.
	local room = list:GetHeight() or (ROW_H * 12)
	if Stoa:IsSecret(room) or room <= 0 then room = ROW_H * 12 end
	self.offset = math.min(self.offset or 0, math.max(#rows - 1, 0))
	local y, used = 0, 0
	for i, row in ipairs(list.rows) do
		local entry = rows[i + self.offset]
		local height = entry and (entry.heading and HEAD_H or ROW_H) or ROW_H
		if entry and y + height > room then entry = nil end
		row.entry = entry
		row:SetShown(entry and true or false)
		if entry then
			used = i
			row:ClearAllPoints()
			row:SetPoint("TOPLEFT", 0, -y)
			row:SetPoint("TOPRIGHT", 0, -y)
			row:SetHeight(height)
			y = y + height
			local heading = entry.heading and true or false
			for _, key in ipairs({ "head", "count", "rule" }) do row[key]:SetShown(heading) end
			for _, key in ipairs({ "icon", "rim", "name", "detail" }) do row[key]:SetShown(not heading) end
			if heading then
				row.head:SetText(entry.heading)
				row.count:SetText(entry.count or "")
				row.pill:Hide()
				row:SetAttribute("spell", nil)
			else
				row.icon:SetTexture(entry.icon)
				row.icon:SetDesaturated(entry.passive)
				row.icon:SetAlpha(entry.passive and 0.75 or 1)
				row.name:SetText(entry.name)
				row.name:SetTextColor(Stoa:Color(entry.passive and "muted" or "text"))
				row.detail:SetText(detailText(entry))
				setPill(row.pill, entry)
				row:SetAttribute("spell", not entry.passive and entry.spellID or nil)
			end
		end
	end
	self.shownRows = used
	list.empty:SetShown(#rows == 0)
end

-- The toolbar: school words at the left (All first), the search at the
-- right. It takes the mouse over its strip, so Blizzard's faded controls
-- under it can't be clicked by mistake.
local function wordButton(parent, label)
	local word = CreateFrame("Button", nil, parent)
	word:SetHeight(TOOLS_H)
	word.text = UI.text(word, "sans", Stoa.typeSize.body, "muted", "LEFT")
	word.text:SetPoint("LEFT")
	word.text:SetText(label)
	word.line = word:CreateTexture(nil, "ARTWORK")
	word.line:SetHeight(2)
	word.line:SetPoint("TOPLEFT", word.text, "BOTTOMLEFT", 0, -5)
	word.line:SetPoint("TOPRIGHT", word.text, "BOTTOMRIGHT", 0, -5)
	word.line:SetTexture(UI.WHITE)
	UI.tint(word.line, "accent")
	word.line:Hide()
	word:SetScript("OnEnter", function(self) if not self.chosen then self.text:SetTextColor(Stoa:Color("text")) end end)
	word:SetScript("OnLeave", function(self) if not self.chosen then self.text:SetTextColor(Stoa:Color("muted")) end end)
	return word
end

local function buildTools(book)
	local tools = CreateFrame("Frame", nil, book)
	tools:SetPoint("TOPLEFT", book, "TOPLEFT", 40, -TOOLS_TOP)
	tools:SetPoint("TOPRIGHT", book, "TOPRIGHT", -40, -TOOLS_TOP)
	tools:SetHeight(TOOLS_H)
	tools:SetFrameLevel(book:GetFrameLevel() + 60)
	tools:EnableMouse(true)
	local box = CreateFrame("EditBox", nil, tools)
	box:SetAutoFocus(false)
	box:SetSize(170, 24)
	box:SetPoint("RIGHT", 0, 0)
	box:SetMaxLetters(40)
	box:SetTextInsets(10, 10, 0, 0)
	Stoa:SetFont(box, "sans", Stoa.typeSize.body)
	box:SetTextColor(Stoa:Color("text"))
	local back = UI.pillFill(box, 0)
	back:SetVertexColor(0, 0, 0, 0.35)
	local edge = UI.pillEdge(box, 0)
	local hint = UI.text(box, "sans", Stoa.typeSize.body, "muted")
	hint:SetPoint("LEFT", 10, 0)
	hint:SetText("Search spells")
	local function paintBox()
		hint:SetShown(box:GetText() == "" and not box:HasFocus())
		edge:Set(Stoa:Color(box:HasFocus() and "accent" or "hairline"))
	end
	box:SetScript("OnEditFocusGained", paintBox)
	box:SetScript("OnEditFocusLost", paintBox)
	box:SetScript("OnEscapePressed", function(self) self:SetText("") self:ClearFocus() end)
	box:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
	box:SetScript("OnTextChanged", function()
		paintBox()
		Spellbook.offset = 0
		guarded(Spellbook.FillList, Spellbook)
	end)
	paintBox()
	tools.box = box
	tools.words = {}
	tools:Hide()
	return tools
end

-- The school words, made as the schools are known; the chosen one in the
-- text colour over a short accent line.
function Spellbook:PaintSchools()
	local tools = self.tools
	if not tools then return end
	local schools = self:Schools()
	if self.school and not tContains(schools, self.school) then self.school = nil end
	local labels = { "All" }
	for _, name in ipairs(schools) do labels[#labels + 1] = name end
	local room = tools:GetWidth()
	if not room or Stoa:IsSecret(room) or room <= 0 then room = 600 end
	local x, limit = 0, room - 190
	for i, label in ipairs(labels) do
		local word = tools.words[i]
		if not word then
			word = wordButton(tools, label)
			word:SetScript("OnClick", function(self)
				Spellbook.school = self.school
				Spellbook.offset = 0
				guarded(Spellbook.FillList, Spellbook)
			end)
			tools.words[i] = word
		end
		word.school = i > 1 and label or nil
		word.text:SetText(schoolLabel(label))
		local width = word.text:GetStringWidth()
		if not width or Stoa:IsSecret(width) or width <= 0 then width = #label * 7 end
		width = math.ceil(width)
		word:SetWidth(width)
		word:ClearAllPoints()
		word:SetPoint("LEFT", tools, "LEFT", x, 0)
		local fits = x + width <= limit
		word:SetShown(fits)
		x = x + width + 16
		word.chosen = word.school == self.school
		word.text:SetTextColor(Stoa:Color(word.chosen and "text" or "muted"))
		word.line:SetShown(word.chosen)
	end
	for i = #labels + 1, #tools.words do tools.words[i]:Hide() end
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
		local maxOffset = math.max(#(Spellbook.rows or {}) - (Spellbook.shownRows or 1), 0)
		Spellbook.offset = math.min(math.max((Spellbook.offset or 0) - delta * 3, 0), maxOffset)
		Spellbook:FillList()
	end)
	list:SetScript("OnSizeChanged", function() Spellbook:FillList() end)
	list.empty = UI.text(list, "sans", Stoa.typeSize.body, "muted", "CENTER")
	list.empty:SetPoint("TOP", 0, -40)
	list.empty:SetText("No spells match.")
	list:Hide()
	return list
end

-- Blizzard's own controls across the book's top (school tabs, search,
-- settings, the help plate, the rotation button) fade out under STOA's
-- toolbar in List view, by alpha only; nothing is hidden or moved.
local BOOK_TOP = { "CategoryTabSystem", "SearchBox", "SettingsDropdown", "HelpPlateButton", "AssistedCombatRotationSpellFrame" }
local function fadeBookTop(book, faded)
	for _, key in ipairs(BOOK_TOP) do
		local child = book[key]
		if child and child.SetAlpha then
			if faded then
				child.stoaFaded = true
				child:SetAlpha(0)
			elseif child.stoaFaded then
				child.stoaFaded = nil
				child:SetAlpha(1)
			end
		end
	end
end

-- List or Blizzard's pages, remembered.
function Spellbook:ShowView(view)
	if InCombatLockdown() then return end
	local book = PlayerSpellsFrame and PlayerSpellsFrame.SpellBookFrame
	if not book then return end
	self.db.view = view
	local listOn = view == "list"
	if listOn and not self.list then self.list = buildList(book) end
	if listOn and not self.tools then self.tools = buildTools(book) end
	if self.list then self.list:SetShown(listOn) end
	if self.tools then self.tools:SetShown(listOn) end
	if book.PagedSpellsFrame then book.PagedSpellsFrame:SetAlpha(listOn and 0 or 1) end
	fadeBookTop(book, listOn)
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
			name:SetText((schoolLabel(name:GetText()) or ""):upper())
			local spent = tonumber(text:GetText()) or 0
			local token = i == top and "accent" or spent > 0 and "text" or "muted"
			name:SetTextColor(Stoa:Color(token))
			text:SetTextColor(Stoa:Color(token))
		end
	end
	-- The trees' cards and rails wait a frame: Blizzard places the talent
	-- buttons after the headers.
	Spellbook.DressTrees(talents)
	if C_Timer and not talents.stoaTreesPending then
		talents.stoaTreesPending = true
		C_Timer.After(0, function()
			talents.stoaTreesPending = nil
			guarded(Spellbook.DressTrees, talents)
		end)
	end
end

-- Each tree on its own recessed card, with rails for its rows: every row
-- of talents is a faint band labelled with the points the tree needs before
-- it opens (5 a row), rows you have reached a touch lighter. Under the name
-- a thin bar fills toward the next row. Only STOA's own textures; the
-- talent buttons are read for their places and never moved.
local TIER_POINTS = 5

local function treeParts(talents, i)
	talents.stoaTrees = talents.stoaTrees or {}
	local parts = talents.stoaTrees[i]
	if parts then return parts end
	parts = { rails = {}, labels = {}, lines = {} }
	parts.fill = UI.sliced(talents, "BACKGROUND", "CardFill.tga")
	if parts.fill then
		parts.fill:SetDrawLayer("BACKGROUND", 1)
		parts.fill:SetVertexColor(0, 0, 0, 0.22)
	end
	parts.edge = UI.sliced(talents, "BACKGROUND", "CardEdge.tga")
	if parts.edge then
		parts.edge:SetDrawLayer("BACKGROUND", 3)
		UI.tint(parts.edge, "hairline")
	end
	parts.track = talents:CreateTexture(nil, "BACKGROUND", nil, 3)
	parts.track:SetTexture(UI.WHITE)
	parts.track:SetVertexColor(0, 0, 0, 0.45)
	parts.bar = talents:CreateTexture(nil, "BACKGROUND", nil, 4)
	parts.bar:SetTexture(UI.WHITE)
	UI.paint(parts.bar, "accent")
	parts.next = UI.text(talents, "sans", Stoa.typeSize.caption, "muted", "LEFT")
	talents.stoaTrees[i] = parts
	UI.applyTheme()
	return parts
end

local function hideTree(parts)
	for _, key in ipairs({ "fill", "edge", "track", "bar", "next" }) do
		if parts[key] then parts[key]:Hide() end
	end
	for _, tex in ipairs(parts.rails) do tex:Hide() end
	for _, label in ipairs(parts.labels) do label:Hide() end
	for _, line in ipairs(parts.lines) do line:Hide() end
end

-- The card's head (name and points, the bar, the "more to open" line)
-- sits this much higher than Blizzard's header, for room between them.
local HEAD_LIFT = 8

function Spellbook.DressTrees(talents)
	-- The window's stone rings fight the cards; the window is dressed after
	-- the talents first show, so this runs again here.
	local host = talents.GetParent and talents:GetParent()
	if host and host.stoaStone and talents:IsVisible() then host.stoaStone:SetAlpha(0) end
	local headers = talents.treeHeaders
	for _, rule in ipairs(talents.stoaRules or {}) do rule:Hide() end
	if not (headers and #headers > 0 and talents.EnumerateAllTalentButtons) then return end
	local left, top = talents:GetLeft(), talents:GetTop()
	if not (left and top) then return end
	-- Where each tree's talents sit, by the header nearest them.
	local centres = {}
	for i, header in ipairs(headers) do centres[i] = select(1, header:GetCenter()) end
	local trees = {}
	for i = 1, #headers do trees[i] = { rows = {}, bottom = nil, size = 0 } end
	-- Only buttons inside the window count: pooled spares parked elsewhere
	-- stretched a card far below it.
	local right, bottom = talents:GetRight(), talents:GetBottom()
	for button in talents:EnumerateAllTalentButtons() do
		local x, y = button:GetCenter()
		if x and y and button:IsVisible() and x > left and y < top
			and (not right or x < right) and (not bottom or y > bottom) then
			local best, gap = 1, math.huge
			for i, cx in ipairs(centres) do
				if cx and math.abs(cx - x) < gap then best, gap = i, math.abs(cx - x) end
			end
			local tree = trees[best]
			local row = math.floor(y + 0.5)
			tree.rows[row] = true
			local size = button:GetHeight() or 0
			if size > tree.size then tree.size = size end
			if not tree.bottom or y < tree.bottom then tree.bottom = y end
			if not tree.minX or x < tree.minX then tree.minX = x end
			if not tree.maxX or x > tree.maxX then tree.maxX = x end
		end
	end
	-- One width for every card: the closest two trees less a gap, and no
	-- wider than keeps the outer cards inside the window.
	local mids = {}
	for _, tree in ipairs(trees) do
		if tree.minX then mids[#mids + 1] = (tree.minX + tree.maxX) / 2 end
	end
	local cardWidth = 460
	for k = 2, #mids do cardWidth = math.min(cardWidth, mids[k] - mids[k - 1] - 18) end
	if mids[1] then cardWidth = math.min(cardWidth, 2 * (mids[1] - left - 14)) end
	if right and mids[#mids] then cardWidth = math.min(cardWidth, 2 * (right - 14 - mids[#mids])) end
	local firstX0, lastRight, rowTop
	for i, header in ipairs(headers) do
		local parts = treeParts(talents, i)
		local tree = trees[i]
		local cx, cy = header:GetCenter()
		if not (cx and cy and tree.bottom) then
			hideTree(parts)
		else
			-- The card is centred on the tree's own columns (Blizzard's
			-- header sits left of them) and as wide as the trees' spacing
			-- allows, every card the same width, all inside the window. The
			-- name sits at its top left and the points at its top right.
			local width = cardWidth
			local x0 = (tree.minX + tree.maxX) / 2 - left - width / 2
			cx = left + x0 + width / 2
			local name, text = header.Name, header.Text
			if name and text then
				name:ClearAllPoints()
				name:SetPoint("LEFT", talents, "TOPLEFT", x0 + 18, cy - top + HEAD_LIFT)
				name:SetJustifyH("LEFT")
				text:ClearAllPoints()
				text:SetPoint("RIGHT", talents, "TOPLEFT", x0 + width - 18, cy - top + HEAD_LIFT)
				text:SetJustifyH("RIGHT")
			end
			local cardTop = cy - top + 22 + HEAD_LIFT
			if not firstX0 then firstX0 = x0 end
			lastRight, rowTop = x0 + width, cardTop
			local cardBottom = tree.bottom - top - tree.size / 2 - 18
			if bottom then cardBottom = math.max(cardBottom, bottom - top + 50) end
			for _, key in ipairs({ "fill", "edge" }) do
				local tex = parts[key]
				if tex then
					tex:ClearAllPoints()
					tex:SetPoint("TOPLEFT", talents, "TOPLEFT", x0, cardTop)
					tex:SetPoint("BOTTOMRIGHT", talents, "TOPLEFT", x0 + width, cardBottom)
					tex:Show()
				end
			end
			-- Rows, top first, one band each.
			local ys = {}
			for y in pairs(tree.rows) do ys[#ys + 1] = y end
			table.sort(ys, function(a, b) return a > b end)
			local step = #ys > 1 and (ys[1] - ys[2]) or (tree.size + 12)
			local spent = tonumber(header.Text and header.Text:GetText()) or 0
			local reached = math.floor(spent / TIER_POINTS)
			for r, y in ipairs(ys) do
				local band = parts.rails[r]
				if not band then
					band = talents:CreateTexture(nil, "BACKGROUND", nil, 2)
					band:SetTexture(UI.WHITE)
					parts.rails[r] = band
				end
				local open = (r - 1) <= reached
				band:ClearAllPoints()
				band:SetPoint("TOPLEFT", talents, "TOPLEFT", x0 + 1, y - top + step / 2)
				band:SetSize(width - 2, step)
				if open then
					local ar, ag, ab = Stoa:Color("accent")
					band:SetVertexColor(ar, ag, ab, 0.035)
				else
					band:SetVertexColor(0, 0, 0, 0.18)
				end
				band:Show()
				-- A hairline along each row's top, brighter once reached.
				local line = parts.lines[r]
				if not line then
					line = talents:CreateTexture(nil, "BACKGROUND", nil, 3)
					line:SetTexture(UI.WHITE)
					parts.lines[r] = line
				end
				line:ClearAllPoints()
				line:SetPoint("TOPLEFT", band, "TOPLEFT")
				line:SetPoint("TOPRIGHT", band, "TOPRIGHT")
				line:SetHeight(1)
				local tr, tg, tb = Stoa:Color("text")
				line:SetVertexColor(tr, tg, tb, open and 0.10 or 0.05)
				line:Show()
				local label = parts.labels[r]
				if not label then
					label = UI.text(talents, "sans", Stoa.typeSize.caption, "muted", "LEFT")
					-- Coloured here by reach, not by the theme pass.
					if UI.unpaint then UI.unpaint(label) end
					parts.labels[r] = label
				end
				label:ClearAllPoints()
				label:SetPoint("LEFT", talents, "TOPLEFT", x0 + 18, y - top)
				label:SetText((r - 1) * TIER_POINTS)
				if open then label:SetTextColor(Stoa:Color("accent")) else label:SetTextColor(Stoa:Color("muted")) end
				label:SetAlpha(open and 0.75 or 0.6)
				label:Show()
			end
			for r = #ys + 1, #parts.rails do
				parts.rails[r]:Hide()
				if parts.labels[r] then parts.labels[r]:Hide() end
				if parts.lines[r] then parts.lines[r]:Hide() end
			end
			-- Toward the next row: a thin bar under the name.
			local barWidth = width - 36
			local barY = cy - top - 12
			parts.track:ClearAllPoints()
			parts.track:SetPoint("TOPLEFT", talents, "TOPLEFT", x0 + 18, barY)
			parts.track:SetSize(barWidth, 3)
			parts.track:Show()
			local last = (#ys - 1) <= reached
			local share = last and 1 or (spent % TIER_POINTS) / TIER_POINTS
			parts.bar:ClearAllPoints()
			parts.bar:SetPoint("TOPLEFT", parts.track, "TOPLEFT")
			parts.bar:SetSize(math.max(0.01, barWidth * share), 3)
			parts.bar:SetShown(share > 0)
			parts.next:ClearAllPoints()
			parts.next:SetPoint("TOPLEFT", talents, "TOPLEFT", x0 + 18, barY - 12)
			if last then
				parts.next:SetText("Every row open")
			else
				local need = (reached + 1) * TIER_POINTS - spent
				parts.next:SetText(("%d more to open row %d"):format(need, reached + 2))
			end
			parts.next:Show()
		end
	end
	for i = #headers + 1, #(talents.stoaTrees or {}) do hideTree(talents.stoaTrees[i]) end
	if firstX0 then
		talents.stoaRow = { left = firstX0, right = lastRight, y = rowTop + 24 }
		Spellbook.PlaceHeaderRow(talents)
	end
end

-- The window's top as one row just over the cards: Primary and Secondary
-- at the left, the search in the middle, points left to spend at the
-- right, each lined up with the cards' edges. Only moved, never resized;
-- none of them is a protected frame.
function Spellbook.PlaceHeaderRow(talents)
	local row = talents.stoaRow
	if not row then return end
	local tabs, search, points = talents.TabSystem, talents.SearchBox, talents.ClassCurrencyDisplay
	if tabs then
		tabs:ClearAllPoints()
		tabs:SetPoint("LEFT", talents, "TOPLEFT", row.left - 14, row.y)
	end
	if search then
		search:ClearAllPoints()
		search:SetPoint("CENTER", talents, "TOPLEFT", (row.left + row.right) / 2, row.y)
	end
	if points then
		points:ClearAllPoints()
		points:SetPoint("RIGHT", talents, "TOPLEFT", row.right, row.y)
	end
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
		-- Its own mark: the window dress may already have marked the tab.
		if not tab.stoaTalentTab then
			tab.stoaTalentTab = true
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
		if tab.stoaUnder then tab.stoaUnder:SetShown(chosen and true or false) end
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

-- The talents page keeps a tall empty band at its top, where Blizzard's spec
-- art sat. While the talents show, the window is that much shorter: it
-- hangs from its top and the talents from its bottom, so they rise into
-- the band. Blizzard sizes the window per tab (UpdateSize), and this runs
-- after it. Out of combat only; nothing of Blizzard's is written.
local TALENTS_LIFT = 94
function Spellbook.FitWindow(talents)
	local frame = talents:GetParent()
	if not (frame and frame.SetHeight) then return end
	if InCombatLockdown() then
		Stoa:AfterCombat(function() guarded(Spellbook.FitWindow, talents) end)
		return
	end
	local base = frame.stoaBaseHeight or frame:GetHeight()
	frame.stoaBaseHeight = base
	local want = talents:IsShown() and base - TALENTS_LIFT or base
	if math.abs(frame:GetHeight() - want) > 0.5 then frame:SetHeight(want) end
	-- The lifted page reaches up over the header, where it caught the
	-- Shift-drag that moves the window: its top no longer takes the mouse.
	if talents.SetHitRectInsets then talents:SetHitRectInsets(0, 0, talents:IsShown() and TALENTS_LIFT or 0, 0) end
	-- The spec's Activate button sat in that band: it joins the row.
	local active, search = talents.ActiveSpec, talents.SearchBox
	if talents:IsShown() and active and search and not active.stoaMoved then
		active.stoaMoved = true
		active:ClearAllPoints()
		active:SetPoint("RIGHT", search, "LEFT", -28, 0)
	end
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
		guarded(Spellbook.DressTrees, self)
		-- The window's stone rings fight the cards, so talents go without.
		if frame.stoaStone then frame.stoaStone:SetAlpha(0) end
		guarded(Spellbook.FitWindow, self)
	end)
	talents:HookScript("OnHide", function(self)
		if frame.stoaStone then frame.stoaStone:SetAlpha(1) end
		guarded(Spellbook.FitWindow, self)
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
	if frame.UpdateSize then
		hooksecurefunc(frame, "UpdateSize", function(self)
			self.stoaBaseHeight = self:GetHeight()
			guarded(Spellbook.FitWindow, talents)
		end)
	end
	-- Blizzard puts the search back at its corner on each layout.
	if talents.SetSearchBoxDefaultPosition then
		hooksecurefunc(talents, "SetSearchBoxDefaultPosition", function(self) guarded(Spellbook.PlaceHeaderRow, self) end)
	end
	if talents.SetTab then
		hooksecurefunc(talents, "SetTab", function(self) hideTalentArt(self) end)
	end
	dressCurrency(talents)
	local windows = Stoa.modules.Windows
	-- Apply and the spec buttons in the window's dress; the Primary and
	-- Secondary tabs are left to PaintTalentTabs, as words.
	if windows and windows.DressButton then
		for _, button in ipairs({ talents.ApplyButton, talents.InspectCopyButton, talents.ActiveSpec and talents.ActiveSpec.ActivateButton }) do
			guarded(windows.DressButton, button)
		end
	end
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
