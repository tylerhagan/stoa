-- Stoa: the character sheet and inspect window in Stoa's dress.
-- The character frame gets a dark rounded panel; every equipment slot is a
-- rounded square with a quality edge and corner mark (the same look as the
-- bags), its item level, and a word when the item is worn out: "WORN" under
-- 30% durability and "BROKEN" at 0, so it never rests on colour alone. An
-- average item level line sits under the title. The inspect window (it
-- loads with its own addon) gets the item levels and quality marks.
--
-- Blizzard's slot buttons stay; only textures and extra text are added.
-- Every name is looked up and guarded, so a frame this client lacks is
-- skipped.
--
-- STOA's layout (on by default, Character.db.layout): the sheet grows
-- wider and lays Blizzard's own slot buttons out in two columns down the
-- sides with each item's name in its quality colour and its item level
-- beside it, the weapons in a row under the model with their names, the
-- stats on a quiet column at the right, the window's tabs as words in the
-- header band, and a footer with your durability. The buttons keep their
-- drag, swap, tooltips and gear sets; they are only moved, out of combat,
-- once the sheet opens. Nothing is built until the sheet first opens.
local _, ns = ...
local Stoa = ns.Stoa
local hooksecurefunc = Stoa.SafeHook
local UI = Stoa.UI

local Character = Stoa:NewModule("Character", { layout = true })

local guarded = Stoa.safe.guarded
local hide = Stoa.frames.hide

-- In a fight a protected frame can't be moved or sized. The character
-- window and its tabs aren't protected, so STOA keeps them in shape when
-- the sheet opens mid-fight; anything that is protected waits.
local function blocked(region)
	return InCombatLockdown() and region and region.IsProtected and region:IsProtected() and true or false
end

local SLOTS = {
	"Head", "Neck", "Shoulder", "Back", "Chest", "Shirt", "Tabard", "Wrist",
	"Hands", "Waist", "Legs", "Feet", "Finger0", "Finger1", "Trinket0", "Trinket1",
	"MainHand", "SecondaryHand", "Ranged",
}
local WORN_BELOW = 0.3

local function slotButtons(prefix)
	local list = {}
	for _, slot in ipairs(SLOTS) do
		local button = _G[prefix .. slot .. "Slot"]
		if button and button.GetID then list[#list + 1] = button end
	end
	return list
end

-- Durability as a word, nil while the item is in good shape.
local function wearWord(slotID)
	if not GetInventoryItemDurability then return nil end
	local current, maximum = GetInventoryItemDurability(slotID)
	current, maximum = Stoa:PlainNumber(current), Stoa:PlainNumber(maximum)
	if not current or not maximum or maximum <= 0 then return nil end
	if current <= 0 then return "BROKEN" end
	if current / maximum < WORN_BELOW then return "WORN" end
end

local function wearText(button)
	local parts = button.stoaItem
	if not parts then return nil end
	if not parts.wear then
		parts.wear = button:CreateFontString(nil, "OVERLAY", nil, 7)
		Stoa:SetFont(parts.wear, "sans", Stoa.typeSize.micro, "OUTLINE")
		parts.wear:SetPoint("BOTTOM", button, "BOTTOM", 0, 3)
	end
	return parts.wear
end

-- Redraws one slot. unit is "player" on the character sheet, the inspected
-- unit on the inspect window.
local function updateSlot(button, unit, withWear)
	local slotID = button:GetID()
	local link = GetInventoryItemLink and GetInventoryItemLink(unit, slotID)
	local quality = link and GetInventoryItemQuality and GetInventoryItemQuality(unit, slotID)
	local level = link and Stoa.ItemSkin.itemLevel(link)
	-- With the words beside the slot, the level and wear go there instead.
	local beside = button.stoaSide and withWear
	local parts = Stoa.ItemSkin.markSlot(button, link and quality or 0, not beside and level or nil)
	if not (parts and withWear) then return end
	local word = link and wearWord(slotID)
	if beside then Character.fillSide(button, link, quality, level, word) end
	local fs = wearText(button)
	if not fs then return end
	fs:SetText(not beside and word or "")
	-- Amber and bold words: the word carries the meaning, the colour helps.
	fs:SetTextColor(Stoa:Color(word == "BROKEN" and "accent" or "danger"))
end

-- Equipment slots ------------------------------------------------------------

local function averageText(frame)
	if not frame.stoaAverage then
		local fs = UI.text(frame, "sans", Stoa.typeSize.body, "muted")
		fs:SetPoint("TOP", frame, "TOP", 0, -30)
		frame.stoaAverage = fs
	end
	return frame.stoaAverage
end

-- The character sheet's band reaches down to where the sheet starts and
-- holds two lines on the left, close together and centred in it: the name,
-- then "Level 4 Priest · Item level 12" in quiet type. Blizzard centres the
-- level line in the middle of the band on every update, so it is seated
-- again after each one.
local function seatLevel()
	local frame, level = CharacterFrame, CharacterLevelText
	if not (frame and level and frame.stoaHeader) or blocked(frame) then return end
	local title = (frame.TitleContainer and frame.TitleContainer.TitleText) or frame.TitleText
	-- On the sheet the title sits high with the level line under it; the
	-- other pages have no level line, so their title sits level with the
	-- tab words (centred 29 below the window's top, see PlaceTabs).
	local onSheet = (frame.activeSubframe or "PaperDollFrame") == "PaperDollFrame"
	-- On the sheet the name and the level line sit close together, the
	-- pair centred up and down in the band.
	Stoa:SetFont(level, "sans", Stoa.typeSize.body)
	local GAP = 4
	local nameHeight = title and (title:GetStringHeight() or 0) or 0
	if nameHeight <= 0 then nameHeight = Stoa.typeSize.title end
	local levelHeight = level:GetStringHeight() or 0
	if levelHeight <= 0 then levelHeight = Stoa.typeSize.body end
	local band = frame.stoaHeader:GetHeight() or 0
	local nameTop = math.max(6, math.floor((band - (nameHeight + GAP + levelHeight)) / 2 + 0.5))
	if title then
		title:ClearAllPoints()
		if onSheet then
			title:SetPoint("TOPLEFT", frame.stoaHeader, "TOPLEFT", 18, -nameTop)
		else
			local headerTop, frameTop = frame.stoaHeader:GetTop(), frame:GetTop()
			local drop = (headerTop and frameTop) and (frameTop - headerTop) or 0
			title:SetPoint("LEFT", frame.stoaHeader, "TOPLEFT", 18, -29 + drop)
		end
		title:SetJustifyH("LEFT")
	end
	-- The close cross sits level with the name, in the band's upper half,
	-- rather than halfway down the two-line header.
	local close = frame.CloseButton or _G.CharacterFrameCloseButton
	if close then
		close:ClearAllPoints()
		close:SetPoint("RIGHT", frame.stoaHeader, "TOPRIGHT", -8, -(nameTop + nameHeight / 2))
	end
	level:ClearAllPoints()
	if title then
		level:SetPoint("TOPLEFT", frame.stoaHeader, "TOPLEFT", 18, -(nameTop + nameHeight + GAP))
	else
		level:SetPoint("LEFT", frame.stoaHeader, "LEFT", 18, 0)
	end
	level:SetWidth(0)
	level:SetJustifyH("LEFT")
	level:SetTextColor(Stoa:Color("muted"))
	local average = averageText(frame)
	average:ClearAllPoints()
	average:SetPoint("LEFT", level, "RIGHT", 12, 0)
end

-- The average item level of what you're wearing (shirt and tabard aside).
local function wornAverage()
	local total, count = 0, 0
	for slotID = 1, 18 do
		if slotID ~= 4 then
			local link = GetInventoryItemLink and GetInventoryItemLink("player", slotID)
			local level = link and Stoa.ItemSkin and Stoa.ItemSkin.itemLevel(link)
			if level then total, count = total + level, count + 1 end
		end
	end
	if count > 0 then return total / count end
end

function Character:Refresh()
	if not (CharacterFrame and CharacterFrame.IsShown and CharacterFrame:IsShown()) then return end
	for _, button in ipairs(slotButtons("Character")) do
		guarded(updateSlot, button, "player", true)
	end
	do
		local overall, equipped
		if GetAverageItemLevel then
			overall, equipped = GetAverageItemLevel()
			overall, equipped = Stoa:PlainNumber(overall), Stoa:PlainNumber(equipped)
		end
		-- Forever reports 0 here, so the worn gear is averaged by hand.
		if not overall or overall <= 0 then
			overall, equipped = wornAverage(), nil
		end
		-- In STOA's layout the number heads the stats column; in Blizzard's
		-- it stays beside the level line in the header.
		local pane = CharacterStatsPaneScrollBox
		local block = pane and pane.stoaLevel
		local differs = overall and equipped and math.floor(equipped + 0.5) ~= math.floor(overall + 0.5)
		if block then
			block.number:SetText(overall and overall > 0 and tostring(math.floor(overall + 0.5)) or "")
			block.worn:SetText(differs and ("worn " .. math.floor(equipped + 0.5)) or "")
			averageText(CharacterFrame):SetText("")
		elseif overall and overall > 0 then
			local text = "Item level " .. math.floor(overall + 0.5)
			if differs then text = text .. Stoa.UI.WIDE_SEP .. "worn " .. math.floor(equipped + 0.5) end
			averageText(CharacterFrame):SetText(Stoa.UI.DOT .. "  " .. text)
		else
			averageText(CharacterFrame):SetText("")
		end
	end
	if self.UpdateFooter then self:UpdateFooter() end
end

-- STOA's layout -----------------------------------------------------------

local LEFT_W = 684       -- the slots and model, Blizzard's 398 widened
local SHEET_H = 560      -- Blizzard's 484, with room for the names
local BLIZZ_LEFT_W = 398 -- Blizzard's left pane, the model's width
local SLOT, SLOT_GAP = 40, 6
local SIDE = 20          -- from the window's edge to the slot columns
local SLOTS_TOP = 72     -- under the header band
local NAME_W = 150
local WEAPON_W = 170     -- each weapon: its slot and its name
local FOOTER_H = 40
-- The model's frame: Blizzard's 398 wide and as tall as Blizzard's
-- (484, less its 20 title and 36 strip), under the header band.
local MODEL_TOP, MODEL_H = 60, 428
local LEFT_SLOTS = { "Head", "Neck", "Shoulder", "Back", "Chest", "Shirt", "Tabard", "Wrist" }
local RIGHT_SLOTS = { "Hands", "Waist", "Legs", "Feet", "Finger0", "Finger1", "Trinket0", "Trinket1" }
local WEAPONS = { "MainHand", "SecondaryHand", "Ranged" }
-- The window's tabs, in the game's own words.
local TAB_WORDS = { "CHARACTER", "REPUTATION", "SKILLS", "PVP", "CURRENCY", "STATISTICS" }

local function layoutOn()
	return Character.db and Character.db.layout ~= false
end

local function onSheet()
	local frame = CharacterFrame
	return frame and (frame.activeSubframe == "PaperDollFrame" or (PaperDollFrame and PaperDollFrame:IsShown()))
end

-- The words beside a slot: the item's name in its quality colour, and
-- under it its item level and WORN or BROKEN, or the slot's name, dim,
-- while it's empty. side is "LEFT" (words right of the slot) or "RIGHT".
local function sideWords(button, side, width)
	if button.stoaSide then return button.stoaSide end
	-- On the slots' own layer, above the model.
	local holder = PaperDollItemsFrame or PaperDollFrame or CharacterFrame
	local name = UI.text(holder, "sans", Stoa.typeSize.body, "text", side == "LEFT" and "LEFT" or "RIGHT")
	name:SetWidth(width)
	name:SetWordWrap(false)
	local sub = UI.text(holder, "sans", Stoa.typeSize.caption, "muted", side == "LEFT" and "LEFT" or "RIGHT")
	sub:SetWidth(width)
	sub:SetWordWrap(false)
	-- The equipment manager's little arrow (pick another item for the slot)
	-- sits right beside the slot, so the words step aside while it shows.
	local popout = button.popoutButton
	local function place()
		local gap = (popout and popout:IsShown()) and 22 or 10
		name:ClearAllPoints()
		if side == "LEFT" then
			name:SetPoint("TOPLEFT", button, "TOPRIGHT", gap, -4)
		else
			name:SetPoint("TOPRIGHT", button, "TOPLEFT", -gap, -4)
		end
	end
	if side == "LEFT" then
		sub:SetPoint("TOPLEFT", name, "BOTTOMLEFT", 0, -4)
	else
		sub:SetPoint("TOPRIGHT", name, "BOTTOMRIGHT", 0, -4)
	end
	place()
	if popout and popout.HookScript then
		popout:HookScript("OnShow", place)
		popout:HookScript("OnHide", place)
	end
	button.stoaSide = { name = name, sub = sub, side = side }
	return button.stoaSide
end

local function slotWord(button)
	local key = button:GetName():gsub("^Character", ""):upper()
	return rawget(_G, key) or ""
end

-- Fills a slot's side words (layout on).
local SIDE_CHIP_GAP = 7
local function fillSide(button, link, quality, level, word)
	local side = button.stoaSide
	if not side then return end
	if not link then
		side.name:SetText(slotWord(button))
		side.name:SetTextColor(Stoa:Color("muted"))
		side.sub:SetText("")
		if side.chip then side.chip:Hide() end
		return
	end
	side.name:SetText(link:match("%[(.-)%]") or "")
	local r, g, b = Stoa.ItemSkin.qualityColour(quality)
	if r then side.name:SetTextColor(r, g, b) else side.name:SetTextColor(Stoa:Color("text")) end
	local words = {}
	if level then
		local pattern = rawget(_G, "ITEM_LEVEL")
		words[#words + 1] = type(pattern) == "string" and pattern:find("%%d") and pattern:format(level) or ("Item level " .. level)
	end
	-- Slate: the slot's name under the item, and its level on a chip.
	local chipped = UI.slate() and level
	if chipped then words = { slotWord(button) } end
	if word then words[#words + 1] = Stoa:Hex(word == "BROKEN" and "accent" or "danger") .. word .. "|r" end
	side.sub:SetText(UI.join(words))
	if chipped then
		if not side.chip then
			side.chip = UI.badge(side.sub:GetParent(), nil, "muted")
		end
		side.chip:Set(tostring(level), "muted")
		local width = Stoa:PlainNumber(side.sub:GetStringWidth()) or 0
		side.chip:ClearAllPoints()
		if side.side == "LEFT" then
			side.chip:SetPoint("LEFT", side.sub, "LEFT", width + SIDE_CHIP_GAP, 0)
		else
			side.chip:SetPoint("RIGHT", side.sub, "RIGHT", -(width + SIDE_CHIP_GAP), 0)
		end
	elseif side.chip then
		side.chip:Hide()
	end
end
Character.fillSide = fillSide

-- The footer: your durability, the lowest of what you wear, and how much
-- of it needs repair.
local footerBar
local function footer()
	local frame = CharacterFrame
	if footerBar then return footerBar end
	local bar = CreateFrame("Frame", nil, PaperDollFrame or frame)
	bar:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 0, 0)
	bar:SetSize(LEFT_W, FOOTER_H)
	local line = bar:CreateTexture(nil, "BORDER")
	line:SetHeight(1)
	line:SetPoint("TOPLEFT")
	line:SetPoint("TOPRIGHT")
	line:SetColorTexture(1, 1, 1)
	line:SetVertexColor(Stoa:Color("accent"))
	line:SetAlpha(0.35)
	UI.tint(line, "accent", 0.35)
	local text = UI.text(bar, "sans", Stoa.typeSize.body, "text", "LEFT")
	text:SetPoint("LEFT", 22, 0)
	bar.text = text
	footerBar = bar
	return bar
end

-- The stats column's pages (stats, titles, equipment sets, your pet) as
-- words along the footer's right, in place of Blizzard's icon tabs. Each
-- word clicks Blizzard's own tab, which stays hidden.
local SIDEBAR_WORDS = {
	{ "PAPERDOLL_SIDEBAR_STATS", "Stats" },
	{ "EQUIPMENT_MANAGER", "Equipment sets" },
	{ "PAPERDOLL_SIDEBAR_TITLES", "Titles" },
	{ "PET", "Pet" },
}
local function sidebarName(i)
	local bar = rawget(_G, "PAPERDOLL_SIDEBARS")
	local entry = type(bar) == "table" and bar[i]
	local name = type(entry) == "table" and entry.name
	if type(name) == "string" and name ~= "" then return name end
	local fallback = SIDEBAR_WORDS[i]
	return fallback and (rawget(_G, fallback[1]) or fallback[2])
end

function Character:PaintSidebarWords()
	local bar = footerBar
	if not (bar and bar.words) then return end
	local previous
	for i = #bar.words, 1, -1 do
		local word = bar.words[i]
		local tab = word.tab
		local shown = tab:IsShown()
		word:SetShown(shown)
		if shown then
			word:ClearAllPoints()
			word:SetSize(math.ceil(word.text:GetStringWidth()) + 4, FOOTER_H - 8)
			if previous then
				word:SetPoint("RIGHT", previous, "LEFT", -18, 0)
			else
				word:SetPoint("RIGHT", bar, "RIGHT", -22, 0)
			end
			previous = word
			local on = tab.GetChecked and tab:GetChecked()
			local usable = not tab.IsEnabled or tab:IsEnabled()
			word.text:SetTextColor(Stoa:Color(on and "text" or "muted"))
			word:SetAlpha(usable and 1 or 0.4)
			word.under:SetVertexColor(Stoa:Color("accent"))
			word.under:SetShown(on and true or false)
			if word.gem then word.gem:SetShown(on and true or false) end
		end
	end
end

local function sidebarWords(bar)
	if bar.words or not _G.PaperDollSidebarTab1 then return end
	bar.words = {}
	for i = 1, 4 do
		local tab = _G["PaperDollSidebarTab" .. i]
		local name = tab and sidebarName(i)
		if name then
			local word = CreateFrame("Button", nil, bar)
			word.tab = tab
			word.text = UI.text(word, "sans", Stoa.typeSize.body, "muted", "CENTER")
			word.text:SetPoint("CENTER", 0, 1)
			word.text:SetText(name)
			local under = word:CreateTexture(nil, "OVERLAY")
			under:SetHeight(2)
			under:SetPoint("BOTTOMLEFT", 0, 4)
			under:SetPoint("BOTTOMRIGHT", 0, 4)
			under:SetColorTexture(1, 1, 1)
			word.under = under
			if UI.tooled() then
				word.gem = UI.chosenMark(word, 6)
				word.gem:SetPoint("CENTER", under, "CENTER", 0, -1)
			end
			word:SetScript("OnClick", function(self)
				if not self.tab.IsEnabled or self.tab:IsEnabled() then self.tab:Click() end
			end)
			word:SetScript("OnEnter", function(self)
				if self.tab.IsEnabled and not self.tab:IsEnabled() then
					local why = self.tab.disabledTooltip
					if type(why) == "function" then why = why(self.tab) end
					GameTooltip:SetOwner(self, "ANCHOR_TOP")
					GameTooltip:SetText(name)
					if type(why) == "string" then GameTooltip:AddLine(why, Stoa:Color("danger")) end
					GameTooltip:Show()
				else
					self.text:SetTextColor(Stoa:Color("text"))
				end
			end)
			word:SetScript("OnLeave", function()
				GameTooltip:Hide()
				Character:PaintSidebarWords()
			end)
			bar.words[#bar.words + 1] = word
		end
	end
	if #bar.words == 0 then return end
	-- Blizzard's icon tabs stay, unseen and out of the mouse's way.
	if PaperDollSidebarTabs then PaperDollSidebarTabs:SetAlpha(0) end
	for i = 1, 4 do
		local tab = _G["PaperDollSidebarTab" .. i]
		if tab and tab.EnableMouse then tab:EnableMouse(false) end
	end
	if PaperDollFrame_UpdateSidebarTabs then
		hooksecurefunc("PaperDollFrame_UpdateSidebarTabs", function() guarded(Character.PaintSidebarWords, Character) end)
	end
	Character:PaintSidebarWords()
end

function Character:UpdateFooter()
	local bar = footerBar
	if not bar then return end
	local lowest, worn = nil, 0
	if GetInventoryItemDurability then
		for slotID = 1, 19 do
			local current, maximum = GetInventoryItemDurability(slotID)
			current, maximum = Stoa:PlainNumber(current), Stoa:PlainNumber(maximum)
			if current and maximum and maximum > 0 then
				local share = current / maximum
				if not lowest or share < lowest then lowest = share end
				if share < WORN_BELOW then worn = worn + 1 end
			end
		end
	end
	local label = Stoa:Hex("muted") .. (rawget(_G, "DURABILITY") or "Durability") .. "|r  "
	local text = label .. (lowest and (math.floor(lowest * 100 + 0.5) .. "%") or "-")
	if worn > 0 then
		text = text .. UI.WIDE_SEP .. Stoa:Hex("danger") .. worn .. " " .. (worn == 1 and "needs" or "need") .. " repair|r"
	end
	bar.text:SetText(text)
end

-- The tabs: Blizzard's own buttons, their art hidden, as words along the
-- header band's right, gold under the one you're on.
local TAB_CHIP_INSET, TAB_CHIP_PAD, TAB_CHIP_GAP = 3, 11, 4
local function dressTab(tab, index)
	if tab.stoaWord then return end
	for _, region in ipairs({ tab:GetRegions() }) do
		if region.IsObjectType and region:IsObjectType("Texture") then region:SetAlpha(0) end
	end
	for _, getter in ipairs({ "GetNormalTexture", "GetPushedTexture", "GetHighlightTexture", "GetCheckedTexture", "GetDisabledTexture" }) do
		local tex = tab[getter] and tab[getter](tab)
		if tex then tex:SetAlpha(0) end
	end
	local word = UI.text(tab, "sans", Stoa.typeSize.body, "muted", "CENTER")
	word:SetPoint("CENTER", 0, 1)
	word:SetText(rawget(_G, TAB_WORDS[index] or "") or "")
	local under = tab:CreateTexture(nil, "OVERLAY")
	under:SetHeight(2)
	under:SetPoint("BOTTOMLEFT", 0, 0)
	under:SetPoint("BOTTOMRIGHT", 0, 0)
	under:SetColorTexture(1, 1, 1)
	tab.stoaWord, tab.stoaUnder = word, under
	-- Slate: the tab you're on is a soft chip in the accent, no rule.
	if UI.slate() then
		local chip = CreateFrame("Frame", nil, tab)
		chip:SetPoint("TOPLEFT", 0, -TAB_CHIP_INSET)
		chip:SetPoint("BOTTOMRIGHT", 0, TAB_CHIP_INSET - 2)
		chip:SetFrameLevel(math.max(0, tab:GetFrameLevel() - 1))
		chip.fill = UI.pillFill(chip, 0)
		chip.edge = UI.pillEdge(chip, 0)
		tab.stoaChip = chip
	end
	tab:HookScript("OnEnter", function(self)
		if not Character.TabOn(self) then self.stoaWord:SetTextColor(Stoa:Color("text")) end
		-- The tab's own name label is the word itself now.
		if GameTooltip and GameTooltip:GetOwner() == self then GameTooltip:Hide() end
	end)
	tab:HookScript("OnLeave", function() Character:PaintTabs() end)
end

-- The tab you're on: the game's own record of the chosen tab first (Skills
-- never gets its check, its page is named differently from its tab), then
-- the tab's check.
function Character.TabOn(tab)
	local chosen = CharacterFrame and CharacterFrame.selectedTab
	if chosen and tab.GetID then return tab:GetID() == chosen end
	return tab.GetChecked and tab:GetChecked() and true or false
end

function Character:PaintTabs()
	local tabs = CharacterFrame and CharacterFrame.ModeTabs and CharacterFrame.ModeTabs.Tabs
	for _, tab in ipairs(tabs or {}) do
		if tab.stoaWord then
			local on = Character.TabOn(tab)
			tab.stoaWord:SetTextColor(Stoa:Color((on and (tab.stoaChip and "accent" or "text")) or "muted"))
			tab.stoaUnder:SetVertexColor(Stoa:Color("accent"))
			tab.stoaUnder:SetShown(on and not tab.stoaChip and true or false)
			if tab.stoaChip then
				local r, g, b = Stoa:Color("accent")
				tab.stoaChip.fill:SetVertexColor(r, g, b, 0.16)
				tab.stoaChip.edge:Set(r, g, b, 0.55)
				tab.stoaChip:SetShown(on and true or false)
			end
		end
	end
end

function Character:PlaceTabs()
	local frame = CharacterFrame
	local tabs = frame and frame.ModeTabs and frame.ModeTabs.Tabs
	if not tabs or blocked(frame) then return end
	local previous
	for i = #tabs, 1, -1 do
		local tab = tabs[i]
		dressTab(tab, i)
		if tab:IsShown() then
			tab:ClearAllPoints()
			local chip = tab.stoaChip
			tab:SetSize(math.ceil(tab.stoaWord:GetStringWidth()) + (chip and TAB_CHIP_PAD * 2 or 4), 28)
			if previous then
				tab:SetPoint("RIGHT", previous, "LEFT", chip and -TAB_CHIP_GAP or -18, 0)
			else
				tab:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -52, -15)
			end
			previous = tab
		end
	end
	self:PlaceAllCharacters(previous)
	self:PaintTabs()
end

-- "All characters" left of the tab words, set apart by a short rule: STOA's
-- Characters window,
-- where every character's gold, rest, gear and bags are. STOA's own word,
-- not one of Blizzard's tabs, so clicking it touches nothing of theirs.
function Character:PlaceAllCharacters(firstTab)
	local frame = CharacterFrame
	if not (frame and Stoa.Alts) then return end
	local word = frame.stoaAllCharacters
	if not word then
		word = CreateFrame("Button", nil, frame)
		word:SetHeight(28)
		local text = UI.text(word, "sans", Stoa.typeSize.body, "muted", "LEFT")
		text:SetPoint("LEFT", 0, 1)
		text:SetText("All characters")
		word:SetWidth(math.ceil(text:GetStringWidth() or 90) + 4)
		word.text = text
		word:SetScript("OnClick", function() Stoa.Alts:Toggle() end)
		word:SetScript("OnEnter", function(own)
			own.text:SetTextColor(Stoa:Color("accent"))
			GameTooltip:SetOwner(own, "ANCHOR_BOTTOM")
			GameTooltip:AddLine("All characters", 1, 1, 1)
			GameTooltip:AddLine("Gold, rest, gear and bags on every character you've played.", 0.8, 0.8, 0.8, true)
			GameTooltip:Show()
		end)
		word:SetScript("OnLeave", function(own)
			own.text:SetTextColor(Stoa:Color("muted"))
			GameTooltip_Hide()
		end)
		local rule = word:CreateTexture(nil, "ARTWORK")
		rule:SetSize(1, 14)
		rule:SetPoint("LEFT", word, "RIGHT", 13, 1)
		rule:SetColorTexture(1, 1, 1)
		UI.tint(rule, "text", 0.18)
		frame.stoaAllCharacters = word
	end
	word:ClearAllPoints()
	if firstTab then
		word:SetPoint("RIGHT", firstTab, "LEFT", -27, 0)
	else
		word:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -52, -15)
	end
	word:Show()
end

local function hideArt()
	local scene = CharacterModelScene
	-- Slate: the model's turn and zoom buttons lose their gold and sit back.
	local control = scene and scene.ControlFrame
	if control and UI.slate() and not control.stoaQuiet and control.GetChildren then
		control.stoaQuiet = true
		for _, button in ipairs({ control:GetChildren() }) do
			for _, region in ipairs({ button:GetRegions() }) do
				if region.SetDesaturated then region:SetDesaturated(true) end
			end
		end
		control:SetAlpha(0.7)
	end
	if scene then
		for _, key in ipairs({ "BackgroundTopLeft", "BackgroundTopRight", "BackgroundBotLeft", "BackgroundBotRight", "BackgroundOverlay" }) do
			local region = scene[key]
			if region then
				hide(region)
				region:Hide()
			end
		end
		-- Blizzard sets the dark overlay's alpha again each time the model
		-- updates, which left a darker band behind the model.
		if not scene.stoaOverlayHooked and SetPaperDollBackgroundOverlayAlpha then
			scene.stoaOverlayHooked = true
			hooksecurefunc("SetPaperDollBackgroundOverlayAlpha", function(overlay)
				if overlay and overlay.SetAlpha then overlay:SetAlpha(0) end
			end)
		end
	end
	local strip = PaperDollFrame and PaperDollFrame.TopBackgroundStripHost
	if strip then Stoa.frames.strip(strip) end
	local frame = CharacterFrame
	for _, host in ipairs({ frame.LeftPaneHost, frame.RightPaneHost }) do
		Stoa.frames.strip(host)
		for _, child in ipairs({ host:GetChildren() }) do Stoa.frames.strip(child) end
	end
	for _, pane in ipairs({ CharacterStatsPaneScrollBox, CharacterStatsPanePetScrollBox }) do
		if pane then Stoa.frames.strip(pane) end
	end
	-- The stats column: a shade lighter than the panel, a hairline at its left.
	local host = frame.RightPaneHost
	if host and not host.stoaShade then
		local shade = host:CreateTexture(nil, "BACKGROUND", nil, 2)
		shade:SetPoint("TOPLEFT", 0, -38)
		shade:SetPoint("BOTTOMRIGHT")
		shade:SetColorTexture(1, 1, 1, 0.025)
		local rule = host:CreateTexture(nil, "BORDER", nil, 2)
		rule:SetWidth(1)
		rule:SetPoint("TOPLEFT", 0, -38)
		rule:SetPoint("BOTTOMLEFT")
		rule:SetColorTexture(1, 1, 1, 0.08)
		host.stoaShade = shade
	end
end

-- The stats: Blizzard's list, with its labels and numbers in STOA's type,
-- quiet labels, light numbers and gold headings, on no art.
local function dressStatRow(row)
	if not row or row.stoaStat then return end
	row.stoaStat = true
	hide(row.Background)
	if row.Title then
		Stoa:SetFont(row.Title, "sans", Stoa.typeSize.caption)
		row.Title:SetTextColor(Stoa:Color("muted"))
		row.Title:ClearAllPoints()
		row.Title:SetPoint("BOTTOMLEFT", 11, 6)
	end
	if row.Label then
		Stoa:SetFont(row.Label, "sans", Stoa.typeSize.body)
		row.Label:SetTextColor(Stoa:Color("muted"))
	end
	if row.Value then
		Stoa:SetFont(row.Value, "sans", Stoa.typeSize.body)
		row.Value:SetTextColor(Stoa:Color("text"))
	end
end

-- Your role's numbers first: a tank sees Defence on top, melee and hunters
-- Weapons, healers and casters the block with spell power.
local function roleCategory()
	local role = Stoa.GetRole and Stoa:GetRole()
	local _, class = UnitClass("player")
	if role == "TANK" then return rawget(_G, "STAT_CATEGORY_DEFENSE") end
	if role == "MELEE" or class == "HUNTER" then return rawget(_G, "STAT_CATEGORY_WEAPONS") end
	if role == "HEALER" or role == "RANGED" then return rawget(_G, "STAT_CATEGORY_MODIFIERS") end
end
Character.roleCategory = roleCategory

-- Moves the role's block (its heading and rows) to the top of a stats
-- list. Returns the new list, or nil when nothing moves.
local function roleOrder(data, first)
	if type(data) ~= "table" or not first or (data[1] and data[1].name == first) then return nil end
	local blocks, block = {}, nil
	for _, entry in ipairs(data) do
		if entry.isHeader or not block then
			block = {}
			blocks[#blocks + 1] = block
		end
		block[#block + 1] = entry
	end
	local at
	for i, b in ipairs(blocks) do
		if b[1].isHeader and b[1].name == first then at = i break end
	end
	if not at then return nil end
	table.insert(blocks, 1, table.remove(blocks, at))
	local out = {}
	for _, b in ipairs(blocks) do
		for _, entry in ipairs(b) do out[#out + 1] = entry end
	end
	return out
end
Character.roleOrder = roleOrder

local function orderStats(pane)
	if pane:GetUnit() ~= "player" then return end
	local out = roleOrder(pane.elementData, roleCategory())
	if out and CreateDataProvider and pane.ScrollBox then
		pane.elementData = out
		pane.ScrollBox:SetDataProvider(CreateDataProvider(out), ScrollBoxConstants and ScrollBoxConstants.RetainScrollPosition)
	end
end

local function dressStats()
	for _, pane in ipairs({ CharacterStatsPaneScrollBox, CharacterStatsPanePetScrollBox }) do
		local box = pane and pane.ScrollBox
		if box and not box.stoaHooked and box.ForEachFrame then
			box.stoaHooked = true
			local function each() box:ForEachFrame(function(row) guarded(dressStatRow, row) end) end
			hooksecurefunc(box, "Update", each)
			each()
		end
		local windows = Stoa.modules.Windows
		if pane and windows and windows.DressScrollBar then guarded(windows.DressScrollBar, pane.ScrollBar) end
		-- Role-first ordering is off: handing the pane a reordered list from
		-- STOA's code tainted Blizzard's stats data, and opening the window
		-- then broke the player frame's health text (secret values compared
		-- in tainted code). Kept for a taint-free way back.
		local _ = orderStats
	end
end

-- Blizzard's detail panes on the other pages (a skill, a faction, your
-- rank) start just under the top of the stats column, which is inside
-- STOA's taller header, so their titles ran into the tab words. They start
-- under the header instead.
local DETAIL_PAGES = { "SkillsFrame", "ReputationFrame", "PVPRankFrame", "TokenFrame", "CurrencyFrame" }
local function seatPane(pane, frame, drop)
	if pane.stoaSeated or not pane.GetNumPoints then return end
	local points, top = {}, nil
	for i = 1, pane:GetNumPoints() do
		local point, rel, relPoint, x, y = pane:GetPoint(i)
		local stone = frame.RightPaneHost and frame.RightPaneHost.StoneBg
		if point == "TOPLEFT" and (rel == frame.RightPaneHost or (stone and rel == stone)) then
			top = x or 0
		else
			points[#points + 1] = { point, rel, relPoint, x, y }
		end
	end
	if not top then return end
	pane.stoaSeated = true
	pane:ClearAllPoints()
	for _, p in ipairs(points) do pane:SetPoint(p[1], p[2], p[3], p[4], p[5]) end
	pane:SetPoint("TOPLEFT", frame.stoaHeader, "BOTTOMLEFT", LEFT_W + top, -12 - (drop or 0))
end

-- Your item level heads the stats column, as players expect to find it
-- there: a gold heading and the number large beside it, over a hairline.
-- It belongs to the stats list (its child), so it shows only with it.
local ILVL_H = 44

-- Under the item level: four tiles with your role's headline figures, so
-- a caster finds spell power without scrolling past Strength. They are
-- STOA's own figures, read from the game's stat functions; the game's list
-- below is not reordered (doing that from addon code tainted it).
local TILE_H, TILE_GAP, TILES_TOP = 44, 8, 12
-- The block's sides: in line with the list's own headings and labels
-- below it on the left, with the item level figure on the right.
local SIDE_L, SIDE_R = 21, 10
-- Under the tiles: how far your hit chance is toward never missing a raid
-- boss (a skull, three levels up), with a tick where an enemy of your own
-- level stops being missed. Forever's caps: spells 4% and 17%, attacks 5%
-- and 8%, two weapons 24% and 29%. Healers have no gauge: heals can't miss.
local CAP_H, CAP_GAP = 30, 12
local TILES_H = TILES_TOP + TILE_H * 2 + TILE_GAP + CAP_GAP + CAP_H
local HIT_CAPS = { spell = { 4, 17 }, attack = { 5, 8 }, dual = { 24, 29 } }

local function plainOf(fn, ...)
	if type(fn) ~= "function" then return nil end
	local ok, a, b = pcall(fn, ...)
	if not ok then return nil end
	return Stoa:PlainNumber(a), Stoa:PlainNumber(b)
end
local function bestSchool(name)
	local fn, best = rawget(_G, name), nil
	for school = 2, 7 do
		local v = plainOf(fn, school)
		if v and (not best or v > best) then best = v end
	end
	return best
end
local function sumOf(...)
	local total, any = 0, false
	for i = 1, select("#", ...) do
		local v = select(i, ...)
		if v then total, any = total + v, true end
	end
	return any and total or nil
end
local function whole(v) return v and BreakUpLargeNumbers and BreakUpLargeNumbers(math.floor(v + 0.5)) or v and tostring(math.floor(v + 0.5)) or "--" end
local function percent(v) return v and ("%.2f%%"):format(v) or "--" end
local function rating(key) return plainOf(rawget(_G, "GetCombatRatingBonus"), rawget(_G, key)) end

local FIGURES = {
	spellPower = { "Spell power", function() return whole(bestSchool("GetSpellBonusDamage")) end },
	healing = { "Healing", function() return whole((plainOf(rawget(_G, "GetSpellBonusHealing")))) end },
	spellHit = { "Spell hit", function() return percent(sumOf(rating("CR_HIT_SPELL"), (plainOf(rawget(_G, "GetSpellHitModifier"))))) end },
	spellCrit = { "Spell crit", function() return percent(bestSchool("GetSpellCritChance")) end },
	regen = { "Mana per 5s", function()
		local base = plainOf(rawget(_G, "GetManaRegen"))
		return whole(base and base * 5)
	end },
	mana = { "Mana", function() return whole((plainOf(UnitPowerMax, "player", 0))) end },
	health = { "Health", function() return whole((plainOf(UnitHealthMax, "player"))) end },
	attack = { "Attack power", function()
		local base, pos = plainOf(UnitAttackPower, "player")
		local ok, _, _, neg = pcall(UnitAttackPower, "player")
		return whole(sumOf(base, pos, ok and Stoa:PlainNumber(neg) or nil))
	end },
	ranged = { "Ranged power", function()
		local base, pos = plainOf(UnitRangedAttackPower, "player")
		local ok, _, _, neg = pcall(UnitRangedAttackPower, "player")
		return whole(sumOf(base, pos, ok and Stoa:PlainNumber(neg) or nil))
	end },
	hit = { "Hit", function() return percent(sumOf(rating("CR_HIT_MELEE"), (plainOf(rawget(_G, "GetHitModifier"))))) end },
	rangedHit = { "Hit", function() return percent(sumOf(rating("CR_HIT_RANGED"), (plainOf(rawget(_G, "GetHitModifier"))))) end },
	crit = { "Crit", function() return percent((plainOf(rawget(_G, "GetCritChance")))) end },
	rangedCrit = { "Crit", function() return percent((plainOf(rawget(_G, "GetRangedCritChance")))) end },
	armor = { "Armor", function()
		local _, effective = plainOf(UnitArmor, "player")
		return whole(effective)
	end },
	dodge = { "Dodge", function() return percent((plainOf(rawget(_G, "GetDodgeChance")))) end },
	parry = { "Parry", function() return percent((plainOf(rawget(_G, "GetParryChance")))) end },
}
-- Every figure a tile can show, in the order its menu lists them.
local FIGURE_MENU = {
	{ "spellPower", "Spell power" }, { "healing", "Healing" }, { "spellHit", "Spell hit" },
	{ "spellCrit", "Spell crit" }, { "regen", "Mana per 5s" }, { "mana", "Mana" }, { "health", "Health" },
	{ "attack", "Attack power" }, { "hit", "Melee hit" }, { "crit", "Melee crit" },
	{ "ranged", "Ranged power" }, { "rangedHit", "Ranged hit" }, { "rangedCrit", "Ranged crit" },
	{ "armor", "Armor" }, { "dodge", "Dodge" }, { "parry", "Parry" },
}
local function roleKey()
	return (Stoa.GetRole and Stoa:GetRole()) or "RANGED"
end
local function usualSet()
	local role = roleKey()
	local _, class = UnitClass("player")
	if role == "TANK" then return { "health", "armor", "dodge", "parry" } end
	if role == "HEALER" then return { "healing", "spellCrit", "regen", "mana" } end
	if class == "HUNTER" then return { "ranged", "rangedHit", "rangedCrit", "attack" } end
	if role == "MELEE" then return { "attack", "hit", "crit", "armor" } end
	return { "spellPower", "spellHit", "spellCrit", "mana" }
end
-- Your role's usual four, with any tile you picked yourself in its place
-- (Character.db.tiles, kept per role, so an off-spec has its own).
local function figureSet()
	local set = usualSet()
	local own = Character.db and Character.db.tiles and Character.db.tiles[roleKey()]
	if own then
		for i = 1, 4 do
			if own[i] and FIGURES[own[i]] then set[i] = own[i] end
		end
	end
	return set
end

-- Your hit chance and which caps it is measured against, or nil (healers).
local function hitToward()
	local role = Stoa.GetRole and Stoa:GetRole()
	local _, class = UnitClass("player")
	if role == "HEALER" then return nil end
	if role == "RANGED" and class ~= "HUNTER" then
		return sumOf(rating("CR_HIT_SPELL"), (plainOf(rawget(_G, "GetSpellHitModifier")))) or 0, HIT_CAPS.spell
	end
	if class == "HUNTER" then
		return sumOf(rating("CR_HIT_RANGED"), (plainOf(rawget(_G, "GetHitModifier")))) or 0, HIT_CAPS.attack
	end
	local both = rawget(_G, "IsDualWielding")
	local ok, dual = pcall(both or tostring)
	dual = both and ok and Stoa.safe.plain(dual) == true
	return sumOf(rating("CR_HIT_MELEE"), (plainOf(rawget(_G, "GetHitModifier")))) or 0, dual and HIT_CAPS.dual or HIT_CAPS.attack, dual
end

local function fillCap(block)
	local cap = block.cap
	if not cap then return end
	local hit, caps, dual = hitToward()
	cap:SetShown(hit ~= nil)
	if not hit then return end
	local same, boss = caps[1], caps[2]
	local wide = tonumber(cap.track:GetWidth()) or 0
	if Stoa:IsSecret(wide) or wide <= 0 then wide = 160 end
	local share = math.max(0, math.min(hit / boss, 1))
	cap.fill:SetShown(share > 0)
	cap.fill:SetWidth(math.max(wide * share, 0.001))
	cap.tick:ClearAllPoints()
	cap.tick:SetPoint("CENTER", cap.track, "LEFT", wide * same / boss, 0)
	local reached = hit >= boss
	UI.paint(cap.fill, reached and "health" or "text", reached and 0.8 or 0.5)
	cap.label:SetText(dual and "HIT, TWO WEAPONS" or "HIT")
	if reached then
		cap.words:SetText("Boss cap reached")
	else
		cap.words:SetText(("%.1f%% to boss cap"):format(boss - hit))
	end
	cap.words:SetTextColor(Stoa:Color(reached and "muted" or "text"))
	cap.same, cap.boss, cap.hit = same, boss, hit
end

-- A tile is narrow, so a small mark says the kind (flame for spell,
-- dagger for melee, bow for ranged, shield for defence) and a short word follows it;
-- the tooltip and the menu keep the full name.
local TILE_WORD = {
	spellPower = "Power", spellHit = "Hit", spellCrit = "Crit",
	attack = "Power", hit = "Hit", crit = "Crit",
	ranged = "Power", rangedHit = "Hit", rangedCrit = "Crit", regen = "Regen",
}
local TILE_MARK = {
	spellPower = "MarkFlame", spellHit = "MarkFlame", spellCrit = "MarkFlame", healing = "MarkFlame",
	attack = "MarkDagger", hit = "MarkDagger", crit = "MarkDagger",
	ranged = "MarkBow", rangedHit = "MarkBow", rangedCrit = "MarkBow",
	armor = "MarkShield", dodge = "MarkShield", parry = "MarkShield",
}
local TILE_MARK_SIZE = 12

local function fillTiles(block)
	if not (block and block.tiles and block:IsVisible()) then return end
	guarded(fillCap, block)
	local set = figureSet()
	for i, tile in ipairs(block.tiles) do
		local figure = FIGURES[set[i]]
		tile.label:SetText(figure and (TILE_WORD[set[i]] or figure[1]) or "")
		local mark = figure and TILE_MARK[set[i]]
		if mark then tile.mark:SetTexture(UI.MEDIA .. "Textures\\" .. mark) end
		tile.mark:SetShown(mark and true or false)
		tile.label:SetPoint("TOPLEFT", mark and (10 + TILE_MARK_SIZE + 4) or 10, -8)
		tile.full = figure and figure[1]
		local ok, words = pcall(figure and figure[2] or tostring, "")
		tile.value:SetText(ok and words or "--")
	end
end

local function buildTiles(block)
	block.tiles = {}
	for i = 1, 4 do
		local tile = CreateFrame("Button", nil, block)
		tile:SetHeight(TILE_H)
		tile.index = i
		local y = -ILVL_H - TILES_TOP - (i > 2 and (TILE_H + TILE_GAP) or 0)
		if i % 2 == 1 then
			tile:SetPoint("TOPLEFT", block, "TOPLEFT", SIDE_L, y)
			tile:SetPoint("RIGHT", block, "CENTER", -TILE_GAP / 2, 0)
		else
			tile:SetPoint("TOPRIGHT", block, "TOPRIGHT", -SIDE_R, y)
			tile:SetPoint("LEFT", block, "CENTER", TILE_GAP / 2, 0)
		end
		-- Leather and Matte: a well pressed into the material. Slate: a
		-- flat dark tile with a fine edge.
		if UI.tooled() then
			UI.pressIn(tile, "CardFill.tga")
		else
			local fill = UI.sliced(tile, "BACKGROUND", "CardFill.tga")
			if fill then fill:SetVertexColor(0, 0, 0, 0.24) end
			local edge = UI.roundBorder(tile, "CardEdge.tga", 1)
			local r, g, b = Stoa:Color("text")
			edge:Set(r, g, b, 0.07)
		end
		tile.label = UI.text(tile, "sans", Stoa.typeSize.micro, "muted", "LEFT")
		tile.mark = tile:CreateTexture(nil, "OVERLAY")
		tile.mark:SetSize(TILE_MARK_SIZE, TILE_MARK_SIZE)
		tile.mark:SetPoint("LEFT", tile.label, "LEFT", -(TILE_MARK_SIZE + 4), 0)
		tile.mark:SetVertexColor(0.85, 0.85, 0.85, 0.9)
		tile.mark:Hide()
		tile.label:SetPoint("TOPLEFT", 10, -8)
		tile.label:SetPoint("RIGHT", -8, 0)
		tile.label:SetWordWrap(false)
		tile.value = UI.text(tile, "sans", Stoa.typeSize.label, "text", "LEFT")
		tile.value:SetPoint("BOTTOMLEFT", 10, 8)
		tile.value:SetPoint("RIGHT", -8, 0)
		tile.value:SetWordWrap(false)
		-- A click picks what the tile shows, from the same list the
		-- settings' choices use.
		tile:SetScript("OnClick", function(self)
			local window = Stoa.SettingsWindow
			if not (window and window.OpenMenu) then return end
			local options = { { "usual", "Your role's usual" } }
			for _, entry in ipairs(FIGURE_MENU) do options[#options + 1] = entry end
			window.OpenMenu(self, {
				options = options,
				get = function() return figureSet()[self.index] end,
				set = function(v)
					local db = Character.db
					if not db then return end
					db.tiles = db.tiles or {}
					local own = db.tiles[roleKey()] or {}
					own[self.index] = v ~= "usual" and v or nil
					db.tiles[roleKey()] = own
					guarded(fillTiles, block)
				end,
			})
		end)
		tile:SetScript("OnEnter", function(self)
			self.label:SetTextColor(Stoa:Color("text"))
			if GameTooltip then
				GameTooltip:SetOwner(self, "ANCHOR_TOP")
				GameTooltip:SetText(self.full or "Figure")
				GameTooltip:AddLine("Click to choose what this tile shows", 0.7, 0.7, 0.7)
				GameTooltip:Show()
			end
		end)
		tile:SetScript("OnLeave", function(self)
			self.label:SetTextColor(Stoa:Color("muted"))
			if GameTooltip then GameTooltip:Hide() end
		end)
		block.tiles[i] = tile
	end
	local cap = CreateFrame("Frame", nil, block)
	cap:SetHeight(CAP_H)
	cap:SetPoint("TOPLEFT", block, "TOPLEFT", SIDE_L, -ILVL_H - TILES_TOP - TILE_H * 2 - TILE_GAP - CAP_GAP)
	cap:SetPoint("RIGHT", block, "RIGHT", -SIDE_R, 0)
	cap.label = UI.text(cap, "sans", Stoa.typeSize.micro, "muted", "LEFT")
	cap.label:SetPoint("TOPLEFT", 0, 0)
	cap.words = UI.text(cap, "sans", Stoa.typeSize.micro, "text", "RIGHT")
	cap.words:SetPoint("TOPRIGHT", 0, 0)
	cap.track = cap:CreateTexture(nil, "BACKGROUND")
	cap.track:SetTexture(UI.WHITE)
	cap.track:SetVertexColor(0, 0, 0, 0.4)
	cap.track:SetHeight(4)
	cap.track:SetPoint("BOTTOMLEFT", 0, 6)
	cap.track:SetPoint("BOTTOMRIGHT", 0, 6)
	-- Leather and Matte: the track is pressed in, a catch of light under it.
	if UI.tooled() then
		cap.track:SetVertexColor(0, 0, 0, 0.55)
		local catch = cap:CreateTexture(nil, "BACKGROUND")
		catch:SetTexture(UI.WHITE)
		UI.pixel(catch, "height")
		catch:SetPoint("TOPLEFT", cap.track, "BOTTOMLEFT")
		catch:SetPoint("TOPRIGHT", cap.track, "BOTTOMRIGHT")
		UI.paint(catch, "text", UI.TOOLED.catch)
	end
	cap.fill = cap:CreateTexture(nil, "BORDER")
	cap.fill:SetTexture(UI.WHITE)
	cap.fill:SetHeight(4)
	cap.fill:SetPoint("LEFT", cap.track, "LEFT", 0, 0)
	cap.tick = cap:CreateTexture(nil, "ARTWORK")
	cap.tick:SetTexture(UI.WHITE)
	cap.tick:SetSize(1, 9)
	UI.paint(cap.tick, "muted", 0.9)
	cap:EnableMouse(true)
	cap:SetScript("OnEnter", function(self)
		if not (self.boss and GameTooltip) then return end
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:SetText("Hit chance")
		GameTooltip:AddLine(("Yours is %.2f%%."):format(self.hit or 0), 1, 1, 1, true)
		GameTooltip:AddLine(("%d%% never misses an enemy of your level (the tick)."):format(self.same), 1, 1, 1, true)
		GameTooltip:AddLine(("%d%% never misses a raid boss."):format(self.boss), 1, 1, 1, true)
		GameTooltip:AddLine("Talents that add hit to some spells are not counted here, and a low weapon skill misses more.", Stoa:Color("muted"))
		GameTooltip:Show()
	end)
	cap:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
	block.cap = cap
	block:HookScript("OnShow", function() guarded(fillTiles, block) end)
	local function later() guarded(fillTiles, block) end
	for _, event in ipairs({ "UNIT_STATS", "PLAYER_EQUIPMENT_CHANGED", "COMBAT_RATING_UPDATE", "UNIT_MAXPOWER", "UNIT_MAXHEALTH", "UNIT_ATTACK_POWER", "PLAYER_DAMAGE_DONE_MODS" }) do
		Stoa:On(event, later)
	end
end
local ILVL_LEFT = SIDE_L
local function levelBlock()
	local pane = CharacterStatsPaneScrollBox
	if not pane or blocked(pane) then return nil end
	if pane.stoaLevel then return pane.stoaLevel end
	local block = CreateFrame("Frame", nil, pane)
	block:SetHeight(ILVL_H + TILES_H)
	block:SetPoint("BOTTOMLEFT", pane, "TOPLEFT", 0, 0)
	block:SetPoint("BOTTOMRIGHT", pane.ScrollBox or pane, "TOPRIGHT", 0, 0)
	local heading = UI.text(block, "sans", Stoa.typeSize.caption, "muted", "LEFT")
	heading:SetPoint("LEFT", block, "TOPLEFT", ILVL_LEFT, -ILVL_H / 2)
	heading:SetText(rawget(_G, "STAT_AVERAGE_ITEM_LEVEL") or "Item Level")
	-- The sheet's one key figure: in the accent under Leather and Matte.
	block.number = UI.text(block, "serif", Stoa.typeSize.title, UI.tooled() and "accent" or "text", "RIGHT")
	block.number:SetPoint("RIGHT", block, "TOPRIGHT", -SIDE_R, -ILVL_H / 2)
	block.worn = UI.text(block, "sans", Stoa.typeSize.caption, "muted", "RIGHT")
	block.worn:SetPoint("RIGHT", block.number, "LEFT", -10, 0)
	local rule
	if UI.tooled() then
		rule = UI.crease(block)
	else
		rule = block:CreateTexture(nil, "ARTWORK")
		rule:SetHeight(1)
		rule:SetColorTexture(1, 1, 1, 0.08)
	end
	rule:SetPoint("TOPLEFT", ILVL_LEFT, -ILVL_H)
	rule:SetPoint("TOPRIGHT", -SIDE_R, -ILVL_H)
	guarded(buildTiles, block)
	pane.stoaLevel = block
	return block
end

-- The stats column's own pages (stats, titles, sets) hung under Blizzard's
-- icon tabs, which are words in the footer now: they start under the header.
local function seatStatPanes(frame)
	local list = { CharacterStatsPaneScrollBox, CharacterStatsPanePetScrollBox, rawget(_G, "CharacterStatsPane") }
	if PaperDollFrame then
		for _, key in ipairs({ "TitleManagerPane", "EquipmentManagerPane" }) do list[#list + 1] = PaperDollFrame[key] end
	end
	for _, pane in pairs(list) do
		seatPane(pane, frame, pane == CharacterStatsPaneScrollBox and levelBlock() and (ILVL_H + TILES_H) or 0)
	end
end

-- The skills and reputation lists: Blizzard's brown heading bars, framed
-- bars and gold words become STOA's own (a heading word over a hairline,
-- flat bars, quiet text). Only the look of Blizzard's rows changes; what
-- they hold and what a click does stay Blizzard's.
local LIST_BAR_H = 14
local function forbiddenRow(frame)
	return type(frame) ~= "table" or (frame.IsForbidden and frame:IsForbidden())
end

-- One of Blizzard's framed progress bars as a flat track and fill. Its own
-- fill is masked art sized by SetFillWidth, so STOA's follows that width.
local function dressListBar(bar, token)
	if forbiddenRow(bar) or bar.stoaBar or not (bar.Fill and bar.FillArea and bar.CreateTexture) then return end
	bar.stoaBar = true
	local r, g, b = bar.Fill:GetVertexColor()
	for _, region in ipairs({ bar:GetRegions() }) do
		if region ~= bar.Fill and region.GetObjectType and region:GetObjectType() == "Texture" then region:SetAlpha(0) end
	end
	local track = bar:CreateTexture(nil, "BACKGROUND")
	track:SetTexture(UI.WHITE)
	track:SetVertexColor(0, 0, 0, 0.38)
	track:SetPoint("LEFT", bar.FillArea, "LEFT", 0, 0)
	track:SetPoint("RIGHT", bar.FillArea, "RIGHT", 0, 0)
	track:SetHeight(LIST_BAR_H)
	local fill = bar:CreateTexture(nil, "BORDER")
	fill:SetTexture(UI.WHITE)
	fill:SetPoint("LEFT", bar.FillArea, "LEFT", 0, 0)
	fill:SetHeight(LIST_BAR_H)
	bar.stoaFill = fill
	local function width(_, w)
		w = tonumber(w) or 0
		fill:SetShown(w > 0)
		fill:SetWidth(math.max(w, 0.001))
	end
	local function colour(red, green, blue)
		if token then red, green, blue = Stoa:Color(token) end
		fill:SetVertexColor(red or 1, green or 1, blue or 1, 0.62)
		-- Recolouring Blizzard's fill brings it back, so it goes again.
		bar.Fill:SetAlpha(0)
	end
	if bar.SetFillWidth then hooksecurefunc(bar, "SetFillWidth", width) end
	if bar.UpdateBarColor then
		hooksecurefunc(bar, "UpdateBarColor", function(self)
			if token then colour() else colour(self.Fill:GetVertexColor()) end
		end)
	end
	if bar.SetFillTextureByColorType then hooksecurefunc(bar, "SetFillTextureByColorType", function() colour(r, g, b) end) end
	width(nil, (bar.fillPercent or 0) * (bar.FillArea:GetWidth() or 0))
	colour(r, g, b)
	if bar.Text then
		Stoa:SetFont(bar.Text, "sans", Stoa.typeSize.caption)
		bar.Text:SetTextColor(Stoa:Color("text"))
	end
end

local function dressListRow(row, token)
	if forbiddenRow(row) or row.stoaList then return end
	row.stoaList = true
	local content = row.Content
	if not content and not row.StateIcon then
		-- A plain sub-heading (currency groups): just its word.
		if row.Text and row.Text.SetTextColor then
			Stoa:SetFont(row.Text, "sans", Stoa.typeSize.body)
			row.Text:SetTextColor(Stoa:Color("muted"))
		end
		return
	end
	if not content then
		-- A heading: its bar goes, the word takes the accent (Slate: muted) over a rule.
		for _, region in ipairs({ row:GetRegions() }) do
			if region.GetObjectType and region:GetObjectType() == "Texture" then region:SetAlpha(0) end
		end
		if row.Name then
			Stoa:SetFont(row.Name, "sans", Stoa.typeSize.caption)
			row.Name:SetTextColor(Stoa:Color("muted"))
			row.Name:ClearAllPoints()
			row.Name:SetPoint("BOTTOMLEFT", 4, 8)
		end
		local rule = row:CreateTexture(nil, "BORDER")
		rule:SetTexture(UI.WHITE)
		rule:SetHeight(1)
		rule:SetPoint("BOTTOMLEFT", 2, 3)
		rule:SetPoint("BOTTOMRIGHT", -2, 3)
		UI.tint(rule, "hairline")
		local glyph = UI.glyph(row, "Minus", 10, "muted")
		glyph:SetPoint("RIGHT", -8, -3)
		local function fold(self)
			local data = self.elementData
			glyph:SetTexture(UI.MEDIA .. "Textures\\Glyph" .. ((type(data) == "table" and data.isCollapsed) and "Plus" or "Minus"))
			if self.StateIcon then self.StateIcon:SetAlpha(0) end
		end
		if row.Initialize then hooksecurefunc(row, "Initialize", fold) end
		row:HookScript("OnEnter", function() glyph:SetVertexColor(Stoa:Color("accent")) end)
		row:HookScript("OnLeave", function() glyph:SetVertexColor(Stoa:Color("muted")) end)
		fold(row)
		return
	end
	if content.Name then
		Stoa:SetFont(content.Name, "sans", Stoa.typeSize.body)
		content.Name:SetTextColor(Stoa:Color("text"))
	end
	-- A statistic's value, a currency's count.
	for _, key in ipairs({ "Value", "Count" }) do
		local figure = content[key]
		if figure and figure.SetTextColor then
			Stoa:SetFont(figure, "sans", Stoa.typeSize.body)
			figure:SetTextColor(Stoa:Color("text"))
		end
	end
	local toggle = row.ToggleCollapseButton
	-- Statistics, under Slate, read as a tree: a group's name stays in the
	-- text colour beside its fold mark, and the lines under it are label
	-- and figure like the console's rows, the label quiet, the figure
	-- bright, an empty "--" dimmed, with a hairline down their left edge
	-- that ties the lines of one group together.
	if UI.slate() and content.Value and content.Name then
		local guide = row:CreateTexture(nil, "BORDER")
		guide:SetTexture(UI.WHITE)
		guide:SetWidth(1)
		guide:SetPoint("TOP", row, "TOP", 0, 0)
		guide:SetPoint("BOTTOM", row, "BOTTOM", 0, 0)
		guide:SetPoint("RIGHT", content.Name, "LEFT", -9, 0)
		UI.tint(guide, "hairline")
		local function level()
			local group = type(toggle) == "table" and toggle.IsShown and toggle:IsShown()
			guide:SetShown(not group)
			content.Name:SetTextColor(Stoa:Color(group and "text" or "muted"))
			local figure = content.Value:GetText()
			local empty = figure == nil or figure == "" or figure == "--"
			local r, g, b = Stoa:Color(empty and "muted" or "text")
			content.Value:SetTextColor(r, g, b, empty and 0.5 or 1)
		end
		if row.Initialize then hooksecurefunc(row, "Initialize", function() guarded(level) end) end
		guarded(level)
	end
	-- A group inside a list (boss kills): Blizzard's red fold button as
	-- STOA's quiet plus and minus.
	if type(toggle) == "table" and toggle.CreateTexture and UI.foldGlyph then
		local set = UI.foldGlyph(toggle)
		local function fold()
			local data = row.elementData
			local shut = row.IsCollapsed and row:IsCollapsed()
			if shut == nil and type(data) == "table" then shut = data.isCollapsed end
			set(shut and true or false)
		end
		if toggle.RefreshIcon then hooksecurefunc(toggle, "RefreshIcon", fold) end
		if row.Initialize then hooksecurefunc(row, "Initialize", fold) end
		guarded(fold)
	end
	-- The chosen and hovered row: a flat wash in place of the painted one
	-- (Blizzard still sets how strong it is, and red for a faction at war).
	local wash = content.BackgroundHighlight
	for _, region in ipairs((wash and wash.TextureRegions) or {}) do
		if region.SetTexture then region:SetTexture(UI.WHITE) end
	end
	dressListBar(content.ReputationBar or content.SkillsBar, token)
end

local LISTS = {
	{ frame = "SkillsFrame", pane = "SkillDetailFrame", bar = "RankBar", token = "accent" },
	{ frame = "ReputationFrame", pane = "ReputationDetailFrame", bar = "StandingBar" },
	{ frame = "TokenFrame", pane = "DetailFrame" },
	{ frame = "StatisticsFrame" },
}

-- Blizzard's gold words (labels, captions) read as quiet ones, and its
-- typeface as STOA's, through a pane and the frames inside it. Words in
-- any other colour (white values, red warnings) keep theirs.
local function sizeFor(height)
	local sizes = Stoa.typeSize
	return height <= 11 and sizes.caption or height <= 13 and sizes.body or height <= 15 and sizes.label or sizes.name
end
local function quietWords(frame, depth)
	if forbiddenRow(frame) or not frame.GetRegions then return end
	for _, region in ipairs({ frame:GetRegions() }) do
		if region.GetObjectType and region:GetObjectType() == "FontString" then
			if not region.stoaWord then
				region.stoaWord = true
				local _, height = region:GetFont()
				Stoa:SetFont(region, "sans", sizeFor(tonumber(height) or 12))
			end
			local r, g, b = region:GetTextColor()
			if r and r > 0.9 and g > 0.7 and g < 0.9 and b < 0.2 then region:SetTextColor(Stoa:Color("muted")) end
		end
	end
	if (depth or 0) > 0 and frame.GetChildren then
		for _, child in ipairs({ frame:GetChildren() }) do quietWords(child, depth - 1) end
	end
end

-- Blizzard's small tick boxes in a pane: the brown box goes grey and the
-- gold tick takes the accent.
local function dressTicks(frame)
	if forbiddenRow(frame) or not frame.GetChildren then return end
	for _, child in ipairs({ frame:GetChildren() }) do
		if not forbiddenRow(child) and child.GetObjectType and child:GetObjectType() == "CheckButton" and not child.stoaTick then
			child.stoaTick = true
			for _, getter in ipairs({ "GetNormalTexture", "GetPushedTexture" }) do
				local tex = child[getter] and child[getter](child)
				if tex and tex.SetDesaturated then
					tex:SetDesaturated(true)
					tex:SetVertexColor(0.75, 0.78, 0.82)
				end
			end
			for _, getter in ipairs({ "GetCheckedTexture", "GetDisabledCheckedTexture" }) do
				local tex = child[getter] and child[getter](child)
				if tex and tex.SetDesaturated then
					tex:SetDesaturated(true)
					UI.tint(tex, "accent")
				end
			end
		end
	end
end

-- The honour page: its gold words, the glow line under your rank and the
-- brown reward button.
local function dressRank()
	local page = rawget(_G, "PVPRankFrame")
	if forbiddenRow(page) then return end
	local function words() guarded(quietWords, page, 4) end
	if not page.stoaRank then
		page.stoaRank = true
		local main = page.MainInfoFrame
		if type(main) == "table" and main.Line and main.Line.SetAlpha then main.Line:SetAlpha(0) end
		local windows = Stoa.modules.Windows
		local pane = page.DetailFrame
		if type(pane) == "table" and not forbiddenRow(pane) then
			if pane.Divider and pane.Divider.SetAlpha then pane.Divider:SetAlpha(0) end
			if windows and windows.DressButtonsIn then guarded(windows.DressButtonsIn, pane, 3) end
			if windows and windows.DressScrollBar then guarded(windows.DressScrollBar, pane.DescriptionScrollBar) end
			if pane.Refresh then hooksecurefunc(pane, "Refresh", words) end
		end
		page:HookScript("OnShow", words)
		if page.Update then hooksecurefunc(page, "Update", words) end
	end
	words()
end
local function dressLists()
	local windows = Stoa.modules.Windows
	for _, list in ipairs(LISTS) do
		local page = rawget(_G, list.frame)
		local box = type(page) == "table" and page.ScrollBox
		if box and not forbiddenRow(box) and not box.stoaListRows then
			box.stoaListRows = true
			local function each(_, row) guarded(dressListRow, row, list.token) end
			if ScrollUtil and ScrollUtil.AddAcquiredFrameCallback then
				ScrollUtil.AddAcquiredFrameCallback(box, each, box, true)
			elseif box.ForEachFrame then
				box:ForEachFrame(function(row) each(nil, row) end)
			end
			-- The painted lines closing the list top and bottom.
			for _, child in ipairs({ box:GetChildren() }) do
				if child ~= box.ScrollTarget and child.GetRegions then
					for _, region in ipairs({ child:GetRegions() }) do
						if region.GetAtlas and region:GetAtlas() == "UI-Character-Info-ScrollLine-Long" then region:SetAlpha(0) end
					end
				end
			end
			if windows and windows.DressScrollBar then guarded(windows.DressScrollBar, page.ScrollBar) end
			local pane = page[list.pane]
			if type(pane) == "table" and not forbiddenRow(pane) then
				guarded(dressListBar, pane[list.bar], list.token)
				if windows and windows.DressScrollBar then guarded(windows.DressScrollBar, pane.DescriptionScrollBar) end
				for _, key in ipairs({ "Title", "Subtitle" }) do
					local text = pane[key]
					if text and text.SetTextColor then
						Stoa:SetFont(text, "sans", key == "Title" and Stoa.typeSize.body or Stoa.typeSize.caption)
						text:SetTextColor(Stoa:Color(key == "Title" and "text" or "muted"))
					end
				end
				if pane.Divider and pane.Divider.SetAlpha then pane.Divider:SetAlpha(0) end
				-- The pane's gold labels (its tick boxes), now and each
				-- time Blizzard fills it again.
				local function words() guarded(quietWords, pane, 3) end
				if pane.Refresh then hooksecurefunc(pane, "Refresh", words) end
				guarded(dressTicks, pane)
				if pane.Content then guarded(dressTicks, pane.Content) end
				pane:HookScript("OnShow", words)
				words()
			end
		end
	end
	guarded(dressRank)
end

local function seatDetailPanes(frame)
	if not (frame.stoaHeader and frame.RightPaneHost) then return end
	for _, name in ipairs(DETAIL_PAGES) do
		local page = rawget(_G, name)
		if page and page.GetChildren then
			for _, child in ipairs({ page:GetChildren() }) do seatPane(child, frame) end
		end
	end	guarded(dressLists)
end

local laidOut
-- Moves the slots and sizes the window. Out of combat only; run again
-- whenever Blizzard sizes the window (each tab change).
function Character:LayOut(early)
	local frame = CharacterFrame
	if not (frame and layoutOn()) then return end
	if InCombatLockdown() then
		-- Blizzard sizes the window and its tabs on every show; put the size
		-- and tabs back (neither is protected) and do the rest after.
		self.layOutAfterCombat = true
		if not blocked(frame) then
			local right = frame.RightPaneHost
			local collapsed = frame.IsRightPaneCollapsed and frame:IsRightPaneCollapsed()
			frame:SetSize(LEFT_W + ((not collapsed and right and right:GetWidth()) or 0), SHEET_H)
			if frame.LeftPaneHost then frame.LeftPaneHost:SetWidth(LEFT_W) end
			self:PlaceTabs()
			guarded(seatLevel)
		end
		return
	end
	-- One size for every tab, so the window never jumps as you switch and
	-- the tabs always fit in its header: Blizzard's other pages (skills,
	-- reputation) fill the same wider left pane.
	local left = frame.LeftPaneHost
	local collapsed = frame.IsRightPaneCollapsed and frame:IsRightPaneCollapsed()
	local right = frame.RightPaneHost
	local rightW = (not collapsed and right and right:GetWidth()) or 0
	frame:SetSize(LEFT_W + rightW, SHEET_H)
	if left then left:SetWidth(LEFT_W) end
	-- The item level line belongs to the sheet; Blizzard gives other pages
	-- their own title, in its gold, which STOA sets light again.
	-- Early (before the sheet first opens) lays the sheet out as well, so
	-- opening it first in a fight finds it ready.
	local sheet = early or onSheet()
	if frame.stoaAverage then frame.stoaAverage:SetShown(sheet and true or false) end
	local title = (frame.TitleContainer and frame.TitleContainer.TitleText) or frame.TitleText
	if title then title:SetTextColor(Stoa:Color("text")) end
	if not sheet then
		seatDetailPanes(frame)
		self:PlaceTabs()
		return
	end
	if not laidOut then
		laidOut = true
		hideArt()
		dressStats()
		sidebarWords(footer())
		seatStatPanes(frame)
		self:Refresh()
		-- The toggle for the stats column stays only while it's folded, so
		-- the column can always be brought back.
		local toggle = frame.RightPaneToggleButton
		if toggle then
			-- While hidden it must not take clicks either: it sits by the
			-- tab words, and a stray click there folded the window.
			local function seat()
				local folded = frame.IsRightPaneCollapsed and frame:IsRightPaneCollapsed() and true or false
				toggle:SetAlpha(folded and 1 or 0)
				if toggle.EnableMouse and not blocked(toggle) then toggle:EnableMouse(folded) end
			end
			hooksecurefunc(frame, "UpdateRightPaneToggleButton", seat)
			seat()
		end
	end
	for i, slot in ipairs(LEFT_SLOTS) do
		local button = _G["Character" .. slot .. "Slot"]
		if button then
			button:ClearAllPoints()
			button:SetPoint("TOPLEFT", frame, "TOPLEFT", SIDE, -SLOTS_TOP - (i - 1) * (SLOT + SLOT_GAP))
			sideWords(button, "LEFT", NAME_W)
		end
	end
	for i, slot in ipairs(RIGHT_SLOTS) do
		local button = _G["Character" .. slot .. "Slot"]
		if button then
			button:ClearAllPoints()
			button:SetPoint("TOPRIGHT", frame, "TOPLEFT", LEFT_W - SIDE, -SLOTS_TOP - (i - 1) * (SLOT + SLOT_GAP))
			sideWords(button, "RIGHT", NAME_W)
		end
	end
	-- The model keeps Blizzard's size, centred between the columns: stretched
	-- to the wider sheet its camera zooms in on the chest.
	local scene = CharacterModelScene
	if scene then
		scene:ClearAllPoints()
		scene:SetPoint("TOP", frame, "TOPLEFT", LEFT_W / 2, -MODEL_TOP)
		scene:SetSize(BLIZZ_LEFT_W, MODEL_H)
	end
	local start = LEFT_W / 2 - WEAPON_W * #WEAPONS / 2
	for i, slot in ipairs(WEAPONS) do
		local button = _G["Character" .. slot .. "Slot"]
		if button then
			button:ClearAllPoints()
			button:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", start + (i - 1) * WEAPON_W, FOOTER_H + 12)
			sideWords(button, "LEFT", WEAPON_W - SLOT - 18)
		end
	end
	local ammo = _G.CharacterAmmoSlot
	if ammo then
		ammo:ClearAllPoints()
		ammo:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", start + #WEAPONS * WEAPON_W, FOOTER_H + 16)
	end
	self:PlaceTabs()
	self:Refresh()
end

local function dressCharacter()
	local frame = CharacterFrame
	if not frame or frame.stoaCharacter then return end
	frame.stoaCharacter = true
	local windows = Stoa.modules.Windows
	if windows and windows.Dress then windows:Dress(frame) end
	-- The sheet is built from nested frames with their own stone borders.
	for _, name in ipairs({ "CharacterFrameInset", "CharacterFrameInsetRight", "PaperDollInnerBorderBottom", "PaperDollInnerBorderBottom2", "PaperDollInnerBorderBottomLeft", "PaperDollInnerBorderBottomRight", "PaperDollInnerBorderLeft", "PaperDollInnerBorderRight", "PaperDollInnerBorderTop", "PaperDollInnerBorderTopLeft", "PaperDollInnerBorderTopRight" }) do
		local part = _G[name]
		if part and part.SetAlpha then part:SetAlpha(0) end
	end
	for _, key in ipairs({ "Inset", "InsetRight" }) do
		local part = frame[key]
		if part then
			if part.NineSlice then part.NineSlice:SetAlpha(0) end
			if part.Bg then part.Bg:SetAlpha(0) end
		end
	end
	for _, button in ipairs(slotButtons("Character")) do
		guarded(Stoa.ItemSkin.skinSlot, button)
	end
	if PaperDollItemSlotButton_Update then
		hooksecurefunc("PaperDollItemSlotButton_Update", function(button)
			if button and button.stoaItem then guarded(updateSlot, button, "player", true) end
		end)
	end
	-- Title and level make a two-line header, so this window's band reaches
	-- down to where the sheet starts; the level is seated as its settle step.
	frame.stoaBandHeight = 58
	if windows and windows.OnSettle then windows:OnSettle(frame, function() guarded(seatLevel) end) end
	frame:HookScript("OnShow", function()
		guarded(seatLevel)
		guarded(Character.Refresh, Character)
	end)
	if layoutOn() then
		-- Blizzard sizes the window on every tab change; the layout follows.
		if frame.UpdateSize then hooksecurefunc(frame, "UpdateSize", function() guarded(Character.LayOut, Character) end) end
		if frame.UpdateTabLayout then hooksecurefunc(frame, "UpdateTabLayout", function() guarded(Character.PlaceTabs, Character) end) end
		-- Blizzard colours each page's title gold; STOA keeps it light.
		if frame.UpdateTitle then
			hooksecurefunc(frame, "UpdateTitle", function()
				local title = (frame.TitleContainer and frame.TitleContainer.TitleText) or frame.TitleText
				if title then title:SetTextColor(Stoa:Color("text")) end
			end)
		end
		if frame.SetSelectedModeTabByFrame then hooksecurefunc(frame, "SetSelectedModeTabByFrame", function() guarded(Character.PaintTabs, Character) end) end
		if frame.OnModeTabClicked then hooksecurefunc(frame, "OnModeTabClicked", function() guarded(Character.PaintTabs, Character) end) end
		-- The title's place depends on the page.
		for _, method in ipairs({ "SetSelectedModeTabByFrame", "UpdateTitle" }) do
			if frame[method] then hooksecurefunc(frame, method, function() guarded(seatLevel) end) end
		end
		frame:HookScript("OnShow", function() guarded(Character.LayOut, Character) end)
		Stoa:On("PLAYER_REGEN_ENABLED", function()
			if Character.layOutAfterCombat then
				Character.layOutAfterCombat = nil
				guarded(Character.LayOut, Character)
			end
		end)
	end
	for _, name in ipairs({ "PaperDollFrame_SetLevel", "PaperDollFrame_SetPetLevel" }) do
		if _G[name] then hooksecurefunc(name, function() guarded(seatLevel) end) end
	end
	guarded(seatLevel)
end


-- Inspect --------------------------------------------------------------------

local function refreshInspect()
	local frame = InspectFrame
	if not (frame and frame.IsShown and frame:IsShown()) then return end
	local unit = frame.unit or "target"
	for _, button in ipairs(slotButtons("Inspect")) do
		guarded(updateSlot, button, unit, false)
	end
	if C_PaperDollInfo and C_PaperDollInfo.GetInspectItemLevel then
		local level = Stoa:PlainNumber(C_PaperDollInfo.GetInspectItemLevel(unit))
		if level and level > 0 then
			averageText(frame):SetText("Item level " .. math.floor(level + 0.5))
		end
	end
end

local function dressInspect()
	local frame = InspectFrame
	if not frame or frame.stoaInspect then return end
	frame.stoaInspect = true
	local windows = Stoa.modules.Windows
	if windows and windows.Dress then windows:Dress(frame) end
	for _, button in ipairs(slotButtons("Inspect")) do
		guarded(Stoa.ItemSkin.skinSlot, button)
	end
	if InspectPaperDollItemSlotButton_Update then
		hooksecurefunc("InspectPaperDollItemSlotButton_Update", function(button)
			if button and button.stoaItem then
				guarded(updateSlot, button, (InspectFrame and InspectFrame.unit) or "target", false)
			end
		end)
	end
	frame:HookScript("OnShow", function() guarded(refreshInspect) end)
	guarded(refreshInspect)
end

function Character:OnEnable()
	guarded(dressCharacter)
	-- The inspect window loads with its own addon the first time it's used.
	if InspectFrame then
		guarded(dressInspect)
	else
		Stoa:On("ADDON_LOADED", function(name)
			if name == "Blizzard_InspectUI" then guarded(dressInspect) end
		end)
	end
	-- Laid out ahead, out of combat, so the sheet is in shape even if it
	-- first opens in a fight.
	Stoa:On("PLAYER_ENTERING_WORLD", function()
		C_Timer.After(2, function()
			if not laidOut and CharacterFrame and not CharacterFrame:IsShown() then
				Stoa:AfterCombat(function() guarded(Character.LayOut, Character, true) end)
			end
		end)
	end)
	Stoa:On("UPDATE_INVENTORY_DURABILITY", function() Character:Refresh() end)
	Stoa:On("PLAYER_EQUIPMENT_CHANGED", function() Character:Refresh() end)
	Stoa:On("INSPECT_READY", function() guarded(refreshInspect) end)
	Stoa:On("GET_ITEM_INFO_RECEIVED", function()
		Character:Refresh()
		guarded(refreshInspect)
	end)
end
