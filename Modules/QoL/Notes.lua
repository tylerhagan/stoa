-- Stoa QoL: player notes. A line about someone you played with, good or
-- bad, written from their right-click menu (or /stoa note Name) and shown
-- again where it matters: on their tooltip, on their party card, on the
-- whisper card, as a diamond on their chat lines, and as one chat line when
-- they join your group. Every
-- character on the account shares the notes. Nothing runs until a noted
-- player turns up: the notes are one saved table, looked up by name.
local _, ns = ...
local Stoa = ns.Stoa
local UI = Stoa.UI

local Notes = Stoa:NewModule("Notes", {
	enabled = true,
	joinLine = true,
	chatMark = true,
})
Stoa.Notes = Notes

local plain = function(v) return Stoa.safe.plain(v) end
local GLYPH = UI.MEDIA .. "Textures\\Glyph"
local MAX_LETTERS = 80

-- Three kinds, each with its own shape so none rests on colour alone.
local KINDS = {
	good = { word = "Good", glyph = "Diamond", token = "mana" },
	bad = { word = "Bad", glyph = "DiamondOpen", token = "danger" },
	note = { word = "Just a note", glyph = "DiamondSmall", token = "muted" },
}
local ORDER = { "good", "bad", "note" }

local function store()
	StoaDB.people = StoaDB.people or {}
	return StoaDB.people
end

local function on()
	return Stoa:IsModuleEnabled("Notes")
end

local function myRealm()
	local realm = GetNormalizedRealmName and GetNormalizedRealmName()
	if type(realm) ~= "string" or realm == "" then realm = GetRealmName and GetRealmName() or "" end
	return (realm:gsub("[%s%-]", ""))
end

-- "Name-Realm" for a name as chat, a menu or the game gives it, and the
-- bare name beside it.
function Notes:Key(name, realm)
	name, realm = plain(name), plain(realm)
	if type(name) ~= "string" or name == "" then return nil end
	local short, theirs = name:match("^([^%-]+)%-(.+)$")
	if short then name, realm = short, theirs end
	if type(realm) ~= "string" or realm == "" then realm = myRealm() end
	return name .. "-" .. (realm:gsub("%s", "")), name
end

-- The same for a unit, when it is a player the game will name.
function Notes:UnitKey(unit)
	if type(unit) ~= "string" or Stoa:IsSecret(unit) then return nil end
	if not plain(UnitExists(unit)) or not plain(UnitIsPlayer(unit)) then return nil end
	local ok, name, realm = pcall(UnitFullName or UnitName, unit)
	if not ok then return nil end
	return self:Key(name, realm)
end

local function unitMeta(unit)
	local meta = {}
	local className, classFile = UnitClass(unit)
	meta.className, meta.class = plain(className), plain(classFile)
	local level = plain(UnitLevel(unit))
	if type(level) == "number" and level > 0 then meta.level = level end
	return meta
end

function Notes:Get(key)
	return key and store()[key] or nil
end

function Notes:Set(key, name, kind, text, meta)
	if not key then return end
	local old = store()[key]
	meta = meta or {}
	store()[key] = {
		name = name,
		kind = KINDS[kind] and kind or "note",
		text = text ~= "" and text or nil,
		when = time(),
		where = (GetRealZoneText and plain(GetRealZoneText())) or (old and old.where) or nil,
		class = meta.class or (old and old.class) or nil,
		className = meta.className or (old and old.className) or nil,
		level = meta.level or (old and old.level) or nil,
	}
	Stoa:Fire("STOA_NOTES_CHANGED")
end

function Notes:Remove(key)
	if not (key and store()[key]) then return end
	store()[key] = nil
	Stoa:Fire("STOA_NOTES_CHANGED")
end

-- The kind's diamond inside a line of text, in the theme's colour.
function Notes:Icon(kind, size)
	local look = KINDS[kind] or KINDS.note
	local r, g, b = Stoa:Color(look.token)
	size = size or 10
	return ("|T%s%s:%d:%d:0:0:32:32:0:32:0:32:%d:%d:%d|t"):format(GLYPH, look.glyph, size, size, r * 255, g * 255, b * 255)
end

-- What a note says: its line, or just "Good" when nothing was written.
local function words(entry)
	return entry.text or (KINDS[entry.kind] or KINDS.note).word
end

local function ago(when)
	local seconds = time() - (when or time())
	if seconds < 3600 then return "just now" end
	if seconds < 86400 then
		local hours = math.floor(seconds / 3600)
		return hours == 1 and "1 hour ago" or (hours .. " hours ago")
	end
	local days = math.floor(seconds / 86400)
	return days == 1 and "yesterday" or (days .. " days ago")
end

local function whereWhen(entry)
	return entry.where and (entry.where .. "  ·  " .. ago(entry.when)) or ago(entry.when)
end

local function classColour(entry)
	local colour = entry and entry.class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[entry.class]
	if colour then return colour.r, colour.g, colour.b end
	return Stoa:Color("text")
end

-- The note card ---------------------------------------------------------------

local CARD_W, HEAD, PAD = 340, 48, 16

local function field(parent, hintText)
	local box = CreateFrame("EditBox", nil, parent)
	box:SetAutoFocus(false)
	box:SetHeight(26)
	box:SetTextInsets(10, 10, 0, 0)
	Stoa:SetFont(box, "sans", Stoa.typeSize.body)
	box:SetTextColor(Stoa:Color("text"))
	local back = UI.pillFill(box, 0)
	back:SetVertexColor(0, 0, 0, 0.4)
	local edge = UI.pillEdge(box, 0)
	edge:Set(1, 1, 1, 0.12)
	local hint = UI.text(box, "sans", Stoa.typeSize.body, "muted", "LEFT")
	hint:SetPoint("LEFT", 10, 0)
	hint:SetText(hintText)
	box.hint = hint
	box:SetScript("OnEditFocusGained", function() edge:Set(Stoa:Color("accent")) end)
	box:SetScript("OnEditFocusLost", function() edge:Set(1, 1, 1, 0.12) end)
	return box
end

function Notes:BuildCard()
	local card = CreateFrame("Frame", "StoaNoteCard", UIParent)
	card:SetSize(CARD_W, HEAD + 14 + 26 + 10 + 26 + 14 + 26 + 12)
	card:SetPoint("CENTER", 0, 140)
	card:SetFrameStrata("DIALOG")
	card:SetFrameLevel(60)
	card:EnableMouse(true)
	card:SetMovable(true)
	card:SetClampedToScreen(true)
	card:RegisterForDrag("LeftButton")
	card:SetScript("OnDragStart", card.StartMoving)
	card:SetScript("OnDragStop", card.StopMovingOrSizing)
	card:Hide()
	if UISpecialFrames then table.insert(UISpecialFrames, "StoaNoteCard") end
	UI.windowPanel(card, 0.97, { header = HEAD })
	card.intro = UI.intro(card, 0, UI.MOTION.rise, UI.MOTION.open)

	local title = UI.text(card, "serif", Stoa.typeSize.name, "text", "LEFT")
	title:SetPoint("TOPLEFT", PAD, -9)
	title:SetPoint("RIGHT", -PAD, 0)
	title:SetWordWrap(false)
	local sub = UI.text(card, "sans", Stoa.typeSize.caption, "muted", "LEFT")
	sub:SetPoint("TOPLEFT", PAD, -29)
	sub:SetPoint("RIGHT", -PAD, 0)
	sub:SetWordWrap(false)
	card.title, card.sub = title, sub

	-- Good, Bad, Just a note.
	card.kinds = {}
	local widths = { good = 84, bad = 84, note = CARD_W - PAD * 2 - 84 * 2 - 12 }
	local x = PAD
	for _, kind in ipairs(ORDER) do
		local button = UI.button(card, KINDS[kind].word, widths[kind], function() self:PickKind(kind) end)
		button:SetPoint("TOPLEFT", x, -(HEAD + 14))
		x = x + widths[kind] + 6
		card.kinds[kind] = button
	end

	local box = field(card, "What happened? One line.")
	box:SetPoint("TOPLEFT", PAD, -(HEAD + 14 + 26 + 10))
	box:SetPoint("RIGHT", -PAD, 0)
	box:SetMaxLetters(MAX_LETTERS)
	box:SetScript("OnTextChanged", function(own) own.hint:SetShown(own:GetText() == "") end)
	box:SetScript("OnEnterPressed", function() self:Save() end)
	box:SetScript("OnEscapePressed", function() card:Hide() end)
	card.box = box

	local save = UI.button(card, "Save", 84, function() self:Save() end)
	save:SetPoint("BOTTOMRIGHT", -PAD, 12)
	local remove = CreateFrame("Button", nil, card)
	remove:SetHeight(26)
	local removeText = UI.text(remove, "sans", Stoa.typeSize.body, "muted", "RIGHT")
	removeText:SetPoint("RIGHT")
	removeText:SetText("Remove")
	remove:SetWidth((removeText:GetStringWidth() or 50) + 4)
	remove:SetPoint("RIGHT", save, "LEFT", -14, 0)
	remove:SetScript("OnEnter", function() removeText:SetTextColor(Stoa:Color("danger")) end)
	remove:SetScript("OnLeave", function() removeText:SetTextColor(Stoa:Color("muted")) end)
	remove:SetScript("OnClick", function()
		self:Remove(card.key)
		card:Hide()
	end)
	card.remove = remove
	local shared = UI.text(card, "sans", Stoa.typeSize.caption, "muted", "LEFT")
	shared:SetPoint("LEFT", card, "BOTTOMLEFT", PAD, 25)
	shared:SetText("Shared by all your characters")
	card.shared = shared

	card:SetScript("OnHide", function() box:ClearFocus() end)
	self.card = card
end

function Notes:PickKind(kind)
	local card = self.card
	card.kind = kind
	for id, button in pairs(card.kinds) do
		button.text:SetText(self:Icon(id, 11) .. "  " .. KINDS[id].word)
		button:SetSelected(id == kind)
	end
	card.box:SetFocus()
end

-- Opens the card for a player: a new note, or the one already written.
function Notes:Open(key, name, meta)
	if not key then return end
	if not self.card then self:BuildCard() end
	local card = self.card
	local old = self:Get(key)
	card.key, card.name, card.meta = key, name or (old and old.name) or key, meta or {}
	card.title:SetText(card.name)
	card.title:SetTextColor(classColour({ class = card.meta.class or (old and old.class) }))
	local parts = {}
	local level, class = card.meta.level or (old and old.level), card.meta.className or (old and old.className)
	if level and class then
		parts[#parts + 1] = ("Level %d %s"):format(level, class)
	elseif class then
		parts[#parts + 1] = class
	end
	if old then parts[#parts + 1] = "noted " .. ago(old.when) end
	card.sub:SetText(#parts > 0 and table.concat(parts, "  ·  ") or "A note only you can see")
	card.remove:SetShown(old ~= nil)
	card.shared:SetShown(old == nil)
	card.box:SetText(old and old.text or "")
	card.box:SetCursorPosition(#(old and old.text or ""))
	local opening = not card:IsShown()
	card:Show()
	self:PickKind(old and old.kind or "note")
	if opening then card.intro:Play() end
end

function Notes:Save()
	local card = self.card
	if not (card and card.key) then return end
	local text = strtrim(card.box:GetText() or "")
	-- A plain note with nothing written says nothing: it is put away.
	if card.kind == "note" and text == "" then
		self:Remove(card.key)
	else
		self:Set(card.key, card.name, card.kind, text, card.meta)
	end
	card:Hide()
end

-- The right-click menu ----------------------------------------------------------

local MENUS = {
	"MENU_UNIT_PLAYER", "MENU_UNIT_PARTY", "MENU_UNIT_RAID_PLAYER", "MENU_UNIT_FRIEND",
	"MENU_UNIT_ENEMY_PLAYER", "MENU_UNIT_GUILD", "MENU_UNIT_COMMUNITIES_GUILD_MEMBER",
	"MENU_UNIT_TARGET", "MENU_UNIT_FOCUS",
}

local function menuEntry(root, context)
	if not on() or type(context) ~= "table" then return end
	local key, name, meta
	local unit = plain(context.unit)
	if unit and plain(UnitExists(unit)) then
		key, name = Notes:UnitKey(unit)
		if not key then return end
		if plain(UnitIsUnit(unit, "player")) then return end
		meta = unitMeta(unit)
	else
		key, name = Notes:Key(context.name, context.server)
	end
	if not key then return end
	root:CreateDivider()
	root:CreateButton(Notes:Get(key) and "Edit STOA note" or "STOA note", function()
		Notes:Open(key, name, meta)
	end)
end

function Notes:HookMenus()
	if not (Menu and Menu.ModifyMenu) then return end
	for _, tag in ipairs(MENUS) do
		pcall(Menu.ModifyMenu, tag, function(_, root, context)
			xpcall(menuEntry, Stoa.catch, root, context)
		end)
	end
end

-- Where a note shows again --------------------------------------------------------

function Notes:HookTooltip()
	if not (TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType) then return end
	TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Unit, Stoa:Guard(function(tip)
		if tip ~= GameTooltip or (tip.IsForbidden and tip:IsForbidden()) then return end
		if not on() or not next(store()) then return end
		local ok, _, unit = pcall(tip.GetUnit, tip)
		if not ok then return end
		local entry = self:Get(self:UnitKey(unit))
		if not entry then return end
		local r, g, b = Stoa:Color("text")
		tip:AddLine(self:Icon(entry.kind, 10) .. "  " .. words(entry), r, g, b, true)
		tip:AddLine(whereWhen(entry), Stoa:Color("muted"))
		tip:Show()
	end, "Notes"))
end

-- A party card's note rides its top left corner, as the raid mark rides the
-- right one.
function Notes:MarkCard(card, unit)
	local entry
	if on() and next(store()) and unit ~= "player" then entry = self:Get(self:UnitKey(unit)) end
	local mark = card.noteMark
	if not entry then
		if mark then mark:Hide() end
		return
	end
	if not mark then
		local corner = CreateFrame("Frame", nil, card)
		corner:SetSize(12, 12)
		corner:SetPoint("CENTER", card, "TOPLEFT", 3, -3)
		corner:SetFrameLevel(card:GetFrameLevel() + 6)
		mark = corner:CreateTexture(nil, "OVERLAY")
		mark:SetAllPoints()
		card.noteMark = mark
	end
	local look = KINDS[entry.kind] or KINDS.note
	mark:SetTexture(GLYPH .. look.glyph)
	mark:SetVertexColor(Stoa:Color(look.token))
	mark:Show()
end

function Notes:MarkCards()
	local party = Stoa.modules.Party
	if not (party and party.cards) then return end
	for _, card in ipairs(party.cards) do
		if card.unit and not card.preview then xpcall(self.MarkCard, Stoa.catch, self, card, card.unit) end
	end
end

-- The line a whisper card adds under a whisper from someone noted.
function Notes:WhisperLine(author)
	if not on() or not next(store()) then return nil end
	local entry = self:Get((self:Key(author)))
	if not entry then return nil end
	return self:Icon(entry.kind, 9) .. "  " .. words(entry)
end

-- The mark on a noted player's chat lines: their diamond at the start of
-- what they say. One lookup per line, and none while no one is noted.
-- Stands down when another addon has the chat.
local CHAT_EVENTS = {
	"CHAT_MSG_SAY", "CHAT_MSG_YELL", "CHAT_MSG_GUILD", "CHAT_MSG_OFFICER",
	"CHAT_MSG_PARTY", "CHAT_MSG_PARTY_LEADER", "CHAT_MSG_RAID", "CHAT_MSG_RAID_LEADER",
	"CHAT_MSG_RAID_WARNING", "CHAT_MSG_INSTANCE_CHAT", "CHAT_MSG_INSTANCE_CHAT_LEADER",
	"CHAT_MSG_WHISPER", "CHAT_MSG_WHISPER_INFORM", "CHAT_MSG_CHANNEL",
}

function Notes.ChatFilter(_, _, message, author, ...)
	local people = StoaDB.people
	if not people or not next(people) or not Notes.db.chatMark or not on() then return false end
	if type(message) ~= "string" or type(author) ~= "string" then return false end
	if Stoa:IsSecret(message) or Stoa:IsSecret(author) then return false end
	local entry = people[(Notes:Key(author))]
	if not entry then return false end
	return false, Notes:Icon(entry.kind, 10) .. " " .. message, author, ...
end

function Notes:HookChat()
	local taken = Stoa.Conflicts and Stoa.Conflicts.SteppedAside
	if taken and (Stoa.Conflicts:SteppedAside("Chat") or Stoa.Conflicts:SteppedAside("ChatLook")) then return end
	local add = (ChatFrameUtil and ChatFrameUtil.AddMessageEventFilter) or ChatFrame_AddMessageEventFilter
	if not add then return end
	for _, event in ipairs(CHAT_EVENTS) do add(event, Notes.ChatFilter) end
end

-- Says once, to you alone, when someone noted is in your group.
function Notes:CheckGroup(quiet)
	if not IsInGroup() then
		self.told = nil
		return
	end
	self.told = self.told or {}
	if not next(store()) then return end
	local mine = self:UnitKey("player")
	for _, unit in ipairs(Stoa:GroupUnits()) do
		local key = self:UnitKey(unit)
		if key and key ~= mine and not self.told[key] then
			self.told[key] = true
			local entry = store()[key]
			if entry and not quiet and self.db.joinLine then
				Stoa:Print(("%s  %s: %s (%s)"):format(self:Icon(entry.kind, 10), entry.name or key, words(entry), ago(entry.when)))
			end
		end
	end
end

-- The People list, a tab of the Characters window ---------------------------------

local ROW_H = 30
local FILTERS = { { "all", "All" }, { "good", "Good" }, { "bad", "Bad" }, { "note", "Notes" } }

local function matches(entry, key, filter, query)
	if filter ~= "all" and entry.kind ~= filter then return false end
	if not query or query == "" then return true end
	local hay = ((entry.name or key) .. " " .. (entry.text or "") .. " " .. (entry.where or "")):lower()
	return hay:find(query, 1, true) ~= nil
end

function Notes:BuildPane(pane)
	self.pane = pane
	self.filter, self.offset = "all", 0
	pane.filters = {}
	for _, info in ipairs(FILTERS) do
		local word = CreateFrame("Button", nil, pane)
		word:SetHeight(24)
		local text = UI.text(word, "sans", Stoa.typeSize.body, "muted", "LEFT")
		text:SetPoint("LEFT")
		word.text, word.id, word.label = text, info[1], info[2]
		word:SetScript("OnClick", function()
			self.filter, self.offset = info[1], 0
			self:FillPane()
		end)
		word:SetScript("OnEnter", function() text:SetTextColor(Stoa:Color("accent")) end)
		word:SetScript("OnLeave", function() text:SetTextColor(Stoa:Color(self.filter == word.id and "text" or "muted")) end)
		pane.filters[#pane.filters + 1] = word
	end

	local box = field(pane, "Search names and notes")
	box:SetWidth(240)
	box:SetPoint("TOPRIGHT", 0, 0)
	box:SetMaxLetters(40)
	box:SetScript("OnTextChanged", function(own)
		own.hint:SetShown(own:GetText() == "")
		self.query, self.offset = own:GetText():lower(), 0
		self:FillPane()
	end)
	box:SetScript("OnEscapePressed", function(own) own:ClearFocus() end)
	box:SetScript("OnEnterPressed", function(own) own:ClearFocus() end)
	pane.box = box

	local rule = UI.line(pane, "hairline")
	rule:SetPoint("TOPLEFT", 0, -34)
	rule:SetPoint("TOPRIGHT", 0, -34)

	pane.rows = {}
	local count = math.max(1, math.floor(((pane:GetHeight() or 400) - 38) / ROW_H))
	for i = 1, count do
		local row = CreateFrame("Button", nil, pane)
		row:SetHeight(ROW_H)
		row:SetPoint("TOPLEFT", 0, -38 - (i - 1) * ROW_H)
		row:SetPoint("RIGHT")
		row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
		local lift = row:CreateTexture(nil, "BACKGROUND", nil, 2)
		lift:SetTexture(UI.WHITE)
		lift:SetAllPoints()
		lift:SetVertexColor(1, 1, 1, 0.045)
		lift:Hide()
		local liftIn = UI.fadeIn(lift, UI.MOTION.quick)
		local line = UI.line(row, "hairline")
		line:SetPoint("BOTTOMLEFT")
		line:SetPoint("BOTTOMRIGHT")
		local mark = row:CreateTexture(nil, "ARTWORK")
		mark:SetSize(12, 12)
		mark:SetPoint("LEFT", 8, 0)
		local name = UI.text(row, "sans", Stoa.typeSize.label, "text", "LEFT")
		name:SetPoint("LEFT", 32, 0)
		name:SetWidth(150)
		name:SetWordWrap(false)
		local when = UI.text(row, "sans", Stoa.typeSize.caption, "muted", "RIGHT")
		when:SetPoint("RIGHT", -8, 0)
		when:SetWidth(96)
		local text = UI.text(row, "sans", Stoa.typeSize.body, "muted", "LEFT")
		text:SetPoint("LEFT", name, "RIGHT", 14, 0)
		text:SetPoint("RIGHT", when, "LEFT", -12, 0)
		text:SetWordWrap(false)
		row.mark, row.name, row.text, row.when = mark, name, text, when
		row:SetScript("OnEnter", function(own)
			lift:Show()
			liftIn:Play()
			local entry = own.entry
			if not entry then return end
			GameTooltip:SetOwner(own, "ANCHOR_RIGHT")
			GameTooltip:AddLine(entry.name or own.key, classColour(entry))
			local r, g, b = Stoa:Color("text")
			GameTooltip:AddLine(self:Icon(entry.kind, 10) .. "  " .. words(entry), r, g, b, true)
			GameTooltip:AddLine(whereWhen(entry), Stoa:Color("muted"))
			GameTooltip:AddLine("Click to edit, right-click to remove", Stoa:Color("muted"))
			GameTooltip:Show()
		end)
		row:SetScript("OnLeave", function()
			lift:Hide()
			GameTooltip_Hide()
		end)
		row:SetScript("OnClick", function(own, button)
			if not own.key then return end
			if button == "RightButton" then
				self:Remove(own.key)
				GameTooltip_Hide()
			else
				self:Open(own.key, own.entry and own.entry.name)
			end
		end)
		pane.rows[i] = row
	end

	local empty = UI.text(pane, "italic", Stoa.typeSize.label, "muted")
	empty:SetPoint("CENTER", 0, 0)
	pane.empty = empty

	pane:EnableMouseWheel(true)
	pane:SetScript("OnMouseWheel", function(_, delta)
		local most = math.max((self.shown or 0) - #pane.rows, 0)
		self.offset = math.min(math.max((self.offset or 0) - delta, 0), most)
		self:FillPane()
	end)
end

-- Draws the list; tells the window how many are showing through pane.onCount.
function Notes:FillPane()
	local pane = self.pane
	if not pane then return end
	local counts = { all = 0, good = 0, bad = 0, note = 0 }
	local list = {}
	for key, entry in pairs(store()) do
		counts.all = counts.all + 1
		counts[entry.kind] = (counts[entry.kind] or 0) + 1
		if matches(entry, key, self.filter, self.query) then list[#list + 1] = { key = key, entry = entry } end
	end
	table.sort(list, function(a, b)
		if (a.entry.when or 0) ~= (b.entry.when or 0) then return (a.entry.when or 0) > (b.entry.when or 0) end
		return a.key < b.key
	end)
	self.shown = #list
	self.offset = math.min(self.offset or 0, math.max(#list - #pane.rows, 0))

	local x = 0
	for _, word in ipairs(pane.filters) do
		word.text:SetText(("%s %d"):format(word.label, counts[word.id] or 0))
		word.text:SetTextColor(Stoa:Color(self.filter == word.id and "text" or "muted"))
		word:SetWidth((word.text:GetStringWidth() or 40) + 2)
		word:ClearAllPoints()
		word:SetPoint("TOPLEFT", x, -1)
		x = x + word:GetWidth() + 18
	end

	for i, row in ipairs(pane.rows) do
		local item = list[i + self.offset]
		row.key, row.entry = item and item.key, item and item.entry
		row:SetShown(item ~= nil)
		if item then
			local entry = item.entry
			local look = KINDS[entry.kind] or KINDS.note
			row.mark:SetTexture(GLYPH .. look.glyph)
			row.mark:SetVertexColor(Stoa:Color(look.token))
			row.name:SetText(entry.name or item.key)
			row.name:SetTextColor(classColour(entry))
			row.text:SetText(words(entry))
			row.when:SetText(ago(entry.when))
		end
	end
	if counts.all == 0 then
		pane.empty:SetText("No notes yet. Right-click a player and choose STOA note.")
	else
		pane.empty:SetText("Nobody matches.")
	end
	pane.empty:SetShown(#list == 0)
	if pane.onCount then pane.onCount(#list, counts.all) end
end

-- Opens the Characters window on its People tab.
function Notes:ShowPeople()
	local alts = Stoa.Alts
	if not (alts and alts.OpenPeople) then return end
	alts:OpenPeople()
end

function Notes:OnEnable()
	self:HookMenus()
	self:HookTooltip()
	xpcall(self.HookChat, Stoa.catch, self)
	local function roster()
		C_Timer.After(0.5, function()
			xpcall(self.CheckGroup, Stoa.catch, self)
			xpcall(self.MarkCards, Stoa.catch, self)
		end)
	end
	Stoa:On("GROUP_ROSTER_UPDATE", roster)
	Stoa:On("STOA_NOTES_CHANGED", function()
		xpcall(self.MarkCards, Stoa.catch, self)
		if self.pane and self.pane:IsVisible() then self:FillPane() end
	end)
	-- Whoever is already in the group at login is not announced again.
	C_Timer.After(2, function()
		xpcall(self.CheckGroup, Stoa.catch, self, true)
		xpcall(self.MarkCards, Stoa.catch, self)
	end)
end

-- /stoa note [Name] writes a note (your target with no name); /stoa people lists them.
Stoa.commands.note = function(rest)
	if not on() then
		Stoa:Print("Player notes are switched off in Settings > Comforts.")
		return
	end
	local name = strtrim(rest or ""):match("^(%S+)")
	if not name then
		local key, short = Notes:UnitKey("target")
		if key then
			Notes:Open(key, short, unitMeta("target"))
		else
			Stoa:Print("Target a player, or type /stoa note and their name.")
		end
		return
	end
	local key, short = Notes:Key(name:sub(1, 1):upper() .. name:sub(2))
	Notes:Open(key, short)
end
Stoa.commands.people = function() Notes:ShowPeople() end
Stoa.commands.notes = Stoa.commands.people
