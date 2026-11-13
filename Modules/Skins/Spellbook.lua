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

local Spellbook = Stoa:NewModule("Spellbook", { layout = true })

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
	-- The docked training page goes with the book.
	frame:HookScript("OnHide", function()
		local trainer = Stoa.modules.Trainer
		local page = trainer and trainer.page
		if page and page.stoaDocked then page:Hide() end
	end)
end

function Spellbook:OnEnable()
	if not on() then return end
	-- The book loads with its own addon the first time it opens.
	guarded(dressBook)
	Stoa:On("ADDON_LOADED", function(name)
		if name == "Blizzard_PlayerSpells" then guarded(dressBook) end
	end)
	Stoa:On("STOA_SPELLS_CHANGED", function() guarded(Spellbook.PaintTrainerWord, Spellbook) end)
	Stoa:On("PLAYER_LEVEL_UP", function() C_Timer.After(1.5, function() guarded(Spellbook.PaintTrainerWord, Spellbook) end) end)
end
