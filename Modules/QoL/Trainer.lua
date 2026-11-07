-- Stoa QoL: new spells at your trainer.
-- Counts the spells and ranks your class trainer would teach you now that
-- you don't know yet (Data/TrainerSpells.lua), and shows the count on the
-- console under Journey: "3 spells to train". Reaching a level that brings new
-- ones leaves a note too, and /stoa trainer lists them by name.
--
-- Later ranks count only when you know an earlier one, so a talent you
-- skipped doesn't nag; spells for another race or faction are left out.
--
-- /stoa trainer, a click on that line, or the Training button on your class
-- trainer's window opens a page of what's waiting now and what the next two
-- training levels bring, with what each costs. Costs are learned the first
-- time you open any trainer of your class (the trainer lists every spell it
-- will ever teach, priced), and kept account-wide. Right-click a spell you'll
-- never train to skip it: it stops counting, on this character.
local _, ns = ...
local Stoa = ns.Stoa
local UI = Stoa.UI

local Trainer = Stoa:NewModule("Trainer", {
	note = true,
})

local function race()
	local _, token = UnitRace("player")
	return token
end

local function myLevel()
	return Stoa:PlainNumber(UnitLevel("player")) or 1
end

-- Skipped spells by name (every rank), on this character.
function Trainer:Skips()
	Stoa.char.trainerSkip = Stoa.char.trainerSkip or {}
	return Stoa.char.trainerSkip
end

function Trainer:Skipped(id)
	local name = Stoa.Spells.name(id)
	return name and self:Skips()[name] or false
end

function Trainer:SetSkipped(id, on)
	local name = Stoa.Spells.name(id)
	if not name then return end
	self:Skips()[name] = on and true or nil
	self:Refresh()
end

-- What a spell costs at the trainer, when a trainer has shown it.
function Trainer:Cost(id)
	return Stoa.db.trainerCosts and Stoa.db.trainerCosts[id]
end

-- When each spell comes, by level: Stoa's list (Data/TrainerSpells.lua),
-- corrected by what your class trainer has shown. The trainer lists every
-- spell it will ever teach with the level it needs, so once you've opened
-- it the levels are the game's own (Forever moved a few from classic).
local function schedule(class)
	local byLevel = Stoa.TRAINER_SPELLS and Stoa.TRAINER_SPELLS[class]
	local seen = Stoa.db.trainerLevels and Stoa.db.trainerLevels[class]
	if not seen or not next(seen) then return byLevel end
	local merged = {}
	for at, ids in pairs(byLevel or {}) do
		for _, id in ipairs(ids) do
			if not seen[id] then
				merged[at] = merged[at] or {}
				table.insert(merged[at], id)
			end
		end
	end
	for id, at in pairs(seen) do
		merged[at] = merged[at] or {}
		table.insert(merged[at], id)
	end
	return merged
end

-- Spells you don't know, as { id, level, skipped } sorted by level, from
-- levels first..last. A later rank waits for an earlier one you know, or
-- (looking ahead) one you could train first.
function Trainer:Spells(first, last)
	local _, class = UnitClass("player")
	local byLevel = schedule(class)
	if not byLevel then return {} end
	local myRace, faction = race(), UnitFactionGroup("player")
	local Spells = Stoa.Spells
	local list, seen = {}, {}
	for at, ids in pairs(byLevel) do
		if at >= first and at <= last then
			for _, id in ipairs(ids) do
				local races = Stoa.TRAINER_RACE[id]
				local side = Stoa.TRAINER_FACTION[id]
				local fits = (not races or races[myRace]) and (not side or side == faction)
				-- A spell this client doesn't know by ID isn't on Forever.
				if fits and not seen[id] and Spells.name(id) and not Spells.covered(id) then
					seen[id] = true
					if not Stoa.TRAINER_RANKED[id] or Spells.best(id) then
						list[#list + 1] = { id = id, level = at, skipped = self:Skipped(id) }
					end
				end
			end
		end
	end
	table.sort(list, function(a, b) return a.level < b.level or (a.level == b.level and a.id < b.id) end)
	return list
end

-- Missing spells now, skipped ones left out.
function Trainer:Missing()
	local list = {}
	for _, entry in ipairs(self:Spells(1, myLevel())) do
		if not entry.skipped then list[#list + 1] = entry end
	end
	return list
end

-- The next two levels that bring something new, and their spells.
function Trainer:Coming()
	local _, class = UnitClass("player")
	local byLevel = schedule(class)
	if not byLevel then return {}, nil end
	local level, levels = myLevel(), {}
	for at in pairs(byLevel) do
		if at > level then levels[#levels + 1] = at end
	end
	table.sort(levels)
	local last = levels[2] or levels[1]
	if not last then return {}, nil end
	return self:Spells(level + 1, last), last
end

-- The cost of a list, and whether every spell in it has a known price.
function Trainer:Total(list)
	local total, known = 0, true
	for _, entry in ipairs(list) do
		if not entry.skipped then
			local cost = self:Cost(entry.id)
			if cost then total = total + cost else known = false end
		end
	end
	return total, known
end

function Trainer:Count()
	if self.cached == nil then self.cached = #self:Missing() end
	return self.cached
end

local function money(copper)
	copper = Stoa:PlainNumber(copper) or 0
	local gold, silver, rest = math.floor(copper / 10000), math.floor(copper / 100) % 100, copper % 100
	local out = {}
	if gold > 0 then out[#out + 1] = gold .. "g" end
	if silver > 0 then out[#out + 1] = silver .. "s" end
	if rest > 0 or #out == 0 then out[#out + 1] = rest .. "c" end
	return table.concat(out, " ")
end

function Trainer:UpdateConsole()
	local console = Stoa.modules.Grimoire
	if not (console and console.trainerNote) then return end
	local count = self:Count()
	-- Training waiting now reads in the accent; otherwise the next training
	-- level, quieter, under the nearest quest (Console:SettleNext).
	local kind
	if count > 0 then
		local total, known = self:Total(self:Missing())
		local cost = total > 0 and ("  ·  %s%s"):format(known and "" or "~", money(total)) or ""
		console.trainerNote:SetText(("%d %s to train%s"):format(count, count == 1 and "spell" or "spells", cost))
		kind = "now"
	else
		local coming = self:Coming()
		local first = coming[1] and coming[1].level
		local at = 0
		for _, entry in ipairs(coming) do
			if entry.level == first and not entry.skipped then at = at + 1 end
		end
		if first and at > 0 then
			console.trainerNote:SetText(("Next training: level %d  ·  %d %s"):format(first, at, at == 1 and "spell" or "spells"))
			kind = "next"
		else
			console.trainerNote:SetText("")
		end
	end
	console.trainerKind = kind
	console.trainerNote:SetTextColor(Stoa:Color(kind == "next" and "muted" or "accent"))
	if self.noteButton then self.noteButton:SetShown(kind ~= nil) end
	if console.SettleNext then console:SettleNext() end
end

function Trainer:Refresh()
	self.cached = nil
	self:UpdateConsole()
	self:Fill()
end

-- True when the open trainer is your class's: it lists at least one spell
-- from your class's list (Data/TrainerSpells.lua). Profession trainers and
-- other classes' trainers list none.
function Trainer:IsMyClassTrainer(class)
	local ours = {}
	for _, ids in pairs(Stoa.TRAINER_SPELLS and Stoa.TRAINER_SPELLS[class] or {}) do
		for _, id in ipairs(ids) do ours[id] = true end
	end
	for i = 1, Stoa:PlainNumber(GetNumTrainerServices()) or 0 do
		local ok, data = pcall(C_TooltipInfo.GetTrainerService, i)
		local id = ok and type(data) == "table" and Stoa:PlainNumber(data.id)
		if id and ours[id] then return true end
	end
	return false
end

-- Before 2026-11-07 every trainer's list was learned as your class's, so
-- profession recipes and other classes' spells crept in. Those lists are
-- dropped once; your class trainer fills them again on the next visit.
local function cleanOldLists()
	if Stoa.db.trainerListsV == 2 then return end
	Stoa.db.trainerLevels = nil
	Stoa.db.trainerGroups = nil
	Stoa.db.trainerListsV = 2
end

-- Prices from an open trainer: every spell it lists, priced, even the ones
-- for later levels. Only for your class's trainer, and only out of combat
-- (the tooltip data is kept from tainted code in combat).
function Trainer:Learn()
	if InCombatLockdown() or not (GetNumTrainerServices and GetTrainerServiceCost) then return end
	if not (C_TooltipInfo and C_TooltipInfo.GetTrainerService) then return end
	Stoa.db.trainerCosts = Stoa.db.trainerCosts or {}
	local _, class = UnitClass("player")
	Stoa.db.trainerLevels = Stoa.db.trainerLevels or {}
	Stoa.db.trainerLevels[class] = Stoa.db.trainerLevels[class] or {}
	local costs, levels, learned = Stoa.db.trainerCosts, Stoa.db.trainerLevels[class], false
	-- Levels and headings come only from your own class's trainer: a
	-- profession trainer (Smelt Heavy Thorium) or another class's (Fear)
	-- would otherwise land on your list. Prices are kept by spell either way.
	local mine = self:IsMyClassTrainer(class)
	Stoa.db.trainerGroups = Stoa.db.trainerGroups or {}
	Stoa.db.trainerGroups[class] = Stoa.db.trainerGroups[class] or {}
	local groups, group = Stoa.db.trainerGroups[class], nil
	for i = 1, Stoa:PlainNumber(GetNumTrainerServices()) or 0 do
		-- The trainer lists its spells under headers (Holy, Protection...);
		-- each spell keeps the header above it, for the page's sections.
		if GetTrainerServiceInfo then
			local fine, label, _, kind = pcall(GetTrainerServiceInfo, i)
			if fine and kind == "header" and type(label) == "string" and not Stoa:IsSecret(label) and label ~= "" then
				group = label
			end
		end
		local ok, data = pcall(C_TooltipInfo.GetTrainerService, i)
		local id = ok and type(data) == "table" and Stoa:PlainNumber(data.id)
		local cost = id and Stoa:PlainNumber((GetTrainerServiceCost(i)))
		if mine and id and group and groups[id] ~= group then
			groups[id] = group
			learned = true
		end
		if id and cost and cost > 0 and costs[id] ~= cost then
			costs[id] = cost
			learned = true
		end
		-- The level it needs, from the trainer's own list.
		if mine and id and GetTrainerServiceInfo then
			local fine, _, _, _, need = pcall(GetTrainerServiceInfo, i)
			need = fine and Stoa:PlainNumber(need)
			if need then
				need = math.max(need, 1)
				if levels[id] ~= need then levels[id] = need; learned = true end
			end
		end
	end
	if learned then self:Refresh() end
end

-- The page --------------------------------------------------------------------

local WIDTH, HEIGHT = 440, 560
local PAD = 24
local ROWS = 15
local ROW_HEIGHT = 24

function Trainer:BuildRow(page, i)
	local row = CreateFrame("Button", nil, page)
	row:SetHeight(ROW_HEIGHT)
	row:SetPoint("TOPLEFT", PAD, -112 - (i - 1) * ROW_HEIGHT)
	row:SetPoint("RIGHT", page, "RIGHT", -PAD, 0)
	row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	local hover = row:CreateTexture(nil, "BACKGROUND")
	hover:SetAllPoints()
	UI.paint(hover, "text", 0.06)
	hover:Hide()
	local icon = row:CreateTexture(nil, "ARTWORK")
	icon:SetSize(18, 18)
	icon:SetPoint("LEFT", 4, 0)
	icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	local mask = row:CreateMaskTexture()
	mask:SetTexture(UI.MEDIA .. "Textures\\ButtonMask", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
	mask:SetAllPoints(icon)
	icon:AddMaskTexture(mask)
	local name = UI.text(row, "serif", Stoa.typeSize.label, "text", "LEFT")
	name:SetPoint("LEFT", icon, "RIGHT", 8, 0)
	name:SetWidth(220)
	name:SetWordWrap(false)
	local level = UI.text(row, "sans", Stoa.typeSize.body, "muted", "RIGHT")
	level:SetPoint("LEFT", name, "RIGHT", 4, 0)
	level:SetWidth(28)
	local cost = UI.text(row, "sans", Stoa.typeSize.body, "muted", "RIGHT")
	cost:SetPoint("RIGHT", -4, 0)
	cost:SetWidth(80)
	-- Section headings use the same row: a caption and the section's total.
	-- Headings fold: a quiet plus or minus before the caption.
	local fold = UI.text(row, "sans", Stoa.typeSize.label, "muted", "CENTER")
	fold:SetPoint("LEFT", 0, -1)
	fold:SetWidth(14)
	local head = UI.text(row, "sans", Stoa.typeSize.caption, "accent", "LEFT")
	head:SetPoint("LEFT", fold, "RIGHT", 4, -1)
	local rule = UI.line(row, "hairline", 0.8)
	rule:SetPoint("BOTTOMLEFT", 0, 2)
	rule:SetPoint("BOTTOMRIGHT", 0, 2)
	Stoa.UI.pixel(rule, "height")
	row:SetScript("OnEnter", function()
		if not row.entry then return end
		if row.entry.key then
			hover:Show()
			fold:SetTextColor(Stoa:Color("accent"))
			return
		end
		if row.entry.heading then return end
		hover:Show()
		if GameTooltip then
			GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
			pcall(GameTooltip.SetSpellByID, GameTooltip, row.entry.id)
			GameTooltip:AddLine(row.entry.skipped and "Right-click to count it again." or "Right-click to skip it.", Stoa:Color("muted"))
			GameTooltip:Show()
		end
	end)
	row:SetScript("OnLeave", function()
		hover:Hide()
		fold:SetTextColor(Stoa:Color("muted"))
		if GameTooltip then GameTooltip:Hide() end
	end)
	row:SetScript("OnClick", function(_, button)
		local entry = row.entry
		if not entry then return end
		if entry.key then
			self:SetFolded(entry.key, not self:Folded(entry.key))
		elseif not entry.heading and button == "RightButton" then
			self:SetSkipped(entry.id, not entry.skipped)
		end
	end)
	row.icon, row.name, row.level, row.cost, row.head, row.rule, row.fold = icon, name, level, cost, head, rule, fold
	return row
end

function Trainer:Build()
	local page = CreateFrame("Frame", "StoaTrainerPage", UIParent)
	page:SetSize(WIDTH, HEIGHT)
	page:SetPoint("CENTER", 0, 60)
	page:SetFrameStrata("DIALOG")
	page:EnableMouse(true)
	page:SetMovable(true)
	page:RegisterForDrag("LeftButton")
	page:SetScript("OnDragStart", page.StartMoving)
	page:SetScript("OnDragStop", page.StopMovingOrSizing)
	page:Hide()
	table.insert(UISpecialFrames, "StoaTrainerPage")
	UI.windowPanel(page, 0.97, { header = 92, footer = 60, family = "trade" })
	self.page = page

	local title = UI.text(page, "serif", Stoa.typeSize.display, "text")
	title:SetPoint("TOPLEFT", PAD, -PAD)
	title:SetText("Training")
	local lede = UI.text(page, "italic", Stoa.typeSize.label, "muted", "LEFT")
	lede:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -6)
	lede:SetWidth(WIDTH - PAD * 2)
	lede:SetWordWrap(false)
	lede:SetText("What you can train now, and what's coming.")

	self.rows = {}
	for i = 1, ROWS do self.rows[i] = self:BuildRow(page, i) end
	self.offset = 0
	page:EnableMouseWheel(true)
	page:SetScript("OnMouseWheel", function(_, delta)
		local maxOffset = math.max(#(self.list or {}) - ROWS, 0)
		self.offset = math.min(math.max(self.offset - delta * 3, 0), maxOffset)
		self:Fill()
	end)
	local foot = UI.text(page, "sans", Stoa.typeSize.body, "muted", "LEFT")
	foot:SetPoint("BOTTOMLEFT", PAD, PAD)
	self.foot = foot
	local close = UI.button(page, "Close", 80, function() page:Hide() end)
	close:SetPoint("BOTTOMRIGHT", -PAD, PAD - 8)
	page:SetScript("OnShow", function() self:Fill() end)
	UI.applyTheme()
end

-- Folded sections, on this character, by key ("now", "now:Holy"...).
function Trainer:Folds()
	Stoa.char.trainerFolds = Stoa.char.trainerFolds or {}
	return Stoa.char.trainerFolds
end

function Trainer:Folded(key)
	return self:Folds()[key] or false
end

function Trainer:SetFolded(key, on)
	self:Folds()[key] = on and true or nil
	self:Fill()
end

-- The trainer's own header for a spell (Holy, Protection...), once you've
-- opened a trainer of your class; spells it hasn't shown share "Other".
local OTHER = "Other"
function Trainer:Group(id)
	local _, class = UnitClass("player")
	local groups = Stoa.db.trainerGroups and Stoa.db.trainerGroups[class]
	return groups and groups[id] or OTHER
end

local function priceOf(self, spells)
	local total, known = self:Total(spells)
	return total > 0 and ((known and "" or "about ") .. money(total)) or ""
end

-- Headings and spells as one list for the rows: NOW and NEXT, each split
-- into the trainer's groups when there's more than one. Every heading folds.
function Trainer:Rows()
	local list = {}
	local function section(key, label, spells, emptyText)
		local folded = self:Folded(key)
		list[#list + 1] = { heading = label, key = key, folded = folded, price = #spells > 0 and priceOf(self, spells) or nil }
		if folded then return end
		if #spells == 0 then
			list[#list + 1] = { heading = "", empty = emptyText }
			return
		end
		local byGroup, names = {}, {}
		for _, entry in ipairs(spells) do
			local group = self:Group(entry.id)
			if not byGroup[group] then byGroup[group] = {}; names[#names + 1] = group end
			table.insert(byGroup[group], entry)
		end
		if #names == 1 then
			for _, entry in ipairs(spells) do list[#list + 1] = entry end
			return
		end
		table.sort(names, function(a, b)
			if a == OTHER or b == OTHER then return b == OTHER and a ~= OTHER end
			return a < b
		end)
		for _, group in ipairs(names) do
			local items, subKey = byGroup[group], key .. ":" .. group
			local subFolded = self:Folded(subKey)
			list[#list + 1] = { heading = ("%s  ·  %d"):format(group, #items), key = subKey, sub = true,
				folded = subFolded, price = priceOf(self, items) }
			if not subFolded then
				for _, entry in ipairs(items) do
					entry.indent = true
					list[#list + 1] = entry
				end
			end
		end
	end
	section("now", "NOW", self:Spells(1, myLevel()), "Nothing waiting. You know it all.")
	local coming, last = self:Coming()
	if last then section("next", ("NEXT  ·  to level %d"):format(last), coming, "Nothing new for a while.") end
	return list
end

function Trainer:Fill()
	if not (self.page and self.page:IsShown()) then return end
	local list = self:Rows()
	self.list = list
	self.offset = math.min(self.offset or 0, math.max(#list - ROWS, 0))
	for i, row in ipairs(self.rows) do
		local entry = list[i + self.offset]
		row.entry = entry
		local spell = entry and not entry.heading
		row.icon:SetShown(spell)
		row.name:SetShown(spell)
		row.level:SetShown(spell)
		row.head:SetShown(entry and entry.heading and true or false)
		row.rule:SetShown(entry and entry.heading and entry.heading ~= "" and not entry.sub and true or false)
		row.fold:SetShown(entry and entry.key and true or false)
		row.fold:ClearAllPoints()
		row.fold:SetPoint("LEFT", entry and entry.sub and 14 or 0, -1)
		row.icon:ClearAllPoints()
		row.icon:SetPoint("LEFT", spell and entry.indent and 18 or 4, 0)
		row.cost:SetShown(entry and true or false)
		if spell then
			local name = Stoa.Spells.name(entry.id) or ("spell " .. entry.id)
			local ok, sub = pcall(C_Spell.GetSpellSubtext, entry.id)
			if ok and type(sub) == "string" and sub ~= "" then name = name .. "  " .. sub end
			row.name:SetText(name)
			row.name:SetTextColor(Stoa:Color(entry.skipped and "muted" or "text"))
			local tex = C_Spell and C_Spell.GetSpellTexture and select(2, pcall(C_Spell.GetSpellTexture, entry.id))
			row.icon:SetTexture(tex)
			row.icon:SetDesaturated(entry.skipped)
			row.icon:SetAlpha(entry.skipped and 0.5 or 1)
			row.level:SetText(entry.level)
			local cost = self:Cost(entry.id)
			row.cost:SetText(entry.skipped and "SKIPPED" or (cost and money(cost) or "?"))
			row.cost:SetTextColor(Stoa:Color("muted"))
		elseif entry then
			row.head:SetText(entry.empty or entry.heading)
			row.head:SetTextColor(Stoa:Color((entry.empty or entry.sub) and "muted" or "accent"))
			if entry.key then row.fold:SetText(entry.folded and "+" or "–") end
			row.cost:SetText(entry.price or "")
			row.cost:SetTextColor(Stoa:Color("text"))
		end
	end
	local skipped = 0
	for _ in pairs(self:Skips()) do skipped = skipped + 1 end
	local known = 0
	for _ in pairs(Stoa.db.trainerCosts or {}) do known = known + 1 end
	self.foot:SetText(known == 0 and "Prices show once you've opened your trainer."
		or skipped > 0 and ("%d skipped on this character."):format(skipped) or "")
end

function Trainer:Open()
	if not self.page then self:Build() end
	self.page:Show()
	self:Fill()
end

function Trainer:Toggle()
	if self.page and self.page:IsShown() then self.page:Hide() else self:Open() end
end

-- Ways in besides /stoa trainer: the TRAINER line under Journey on the
-- console, and a Training button on your class trainer's own window.
function Trainer:HookConsole()
	local console = Stoa.modules.Grimoire
	local note = console and console.trainerNote
	if not note or self.noteButton then return end
	local button = CreateFrame("Button", nil, note:GetParent())
	button:SetAllPoints(note)
	button:SetScript("OnClick", function() self:Toggle() end)
	button:SetScript("OnEnter", function()
		note:SetTextColor(Stoa:Color("text"))
		if GameTooltip then
			GameTooltip:SetOwner(button, "ANCHOR_TOP")
			GameTooltip:AddLine("Training")
			GameTooltip:AddLine("Click to see what's waiting and what's coming.", 1, 1, 1)
			GameTooltip:Show()
		end
	end)
	button:SetScript("OnLeave", function()
		note:SetTextColor(Stoa:Color(console.trainerKind == "next" and "muted" or "accent"))
		if GameTooltip then GameTooltip:Hide() end
	end)
	self.noteButton = button
	self:UpdateConsole()
end

function Trainer:HookTrainerWindow()
	local frame = _G.ClassTrainerFrame
	if not frame or self.trainerButton then return end
	local button = UI.button(frame, "Training", 96, function() self:Toggle() end)
	button:SetHeight(22)
	-- Just outside the window's right edge, clear of its filter and close button.
	button:SetPoint("TOPLEFT", frame, "TOPRIGHT", 6, -40)
	self.trainerButton = button
end

function Trainer:ShowTrainerButton()
	self:HookTrainerWindow()
	local button = self.trainerButton
	if not button then return end
	-- Only at a class trainer: profession and pet trainers teach nothing Training lists.
	local isClass = true
	if C_Trainer and C_Trainer.GetTrainerType and Enum and Enum.TrainerType then
		local ok, kind = pcall(C_Trainer.GetTrainerType)
		isClass = not ok or kind == Enum.TrainerType.General
	end
	button:SetShown(isClass)
end

function Trainer:OnEnable()
	cleanOldLists()
	Stoa:On("STOA_SPELLS_CHANGED", function() self:Refresh() end)
	Stoa:On("PLAYER_LEVEL_UP", function(level)
		-- The spellbook and level settle a moment after the event.
		C_Timer.After(1, function()
			xpcall(function()
				local before = self.cached or 0
				self:Refresh()
				local count = self:Count()
				if self.db.note and count > before then
					Stoa:Note("trainer", ("Level %s: %d new %s at your trainer."):format(
						tostring(Stoa:PlainNumber(level) or UnitLevel("player")), count, count == 1 and "spell" or "spells"))
				end
			end, Stoa.catch)
		end)
	end)
	Stoa:On("TRAINER_SHOW", function()
		C_Timer.After(0.2, function()
			xpcall(self.Learn, Stoa.catch, self)
			xpcall(self.ShowTrainerButton, Stoa.catch, self)
		end)
	end)
	-- The console builds its pages as it enables; hook its line once it has.
	C_Timer.After(0, function() xpcall(self.HookConsole, Stoa.catch, self) end)
	Stoa:On("TRAINER_UPDATE", function() xpcall(self.Learn, Stoa.catch, self) end)
	Stoa.commands.trainer = function(rest)
		if (rest or ""):match("^%s*list") == nil then
			self:Open()
			return
		end
		local list = self:Missing()
		if #list == 0 then
			Stoa:Print("Nothing new at your trainer.")
			return
		end
		Stoa:Print(("%d new at your trainer:"):format(#list))
		for _, entry in ipairs(list) do
			local name = Stoa.Spells.name(entry.id) or ("spell " .. entry.id)
			local sub = C_Spell and C_Spell.GetSpellSubtext and select(2, pcall(C_Spell.GetSpellSubtext, entry.id))
			Stoa:Print(("  %d  %s%s"):format(entry.level, name, type(sub) == "string" and sub ~= "" and (" (" .. sub .. ")") or ""))
		end
	end
	self:Refresh()
end
