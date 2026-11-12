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

local SLOTS = {
	"Head", "Neck", "Shoulder", "Back", "Chest", "Shirt", "Tabard", "Wrist",
	"Hands", "Waist", "Legs", "Feet", "Finger0", "Finger1", "Trinket0", "Trinket1",
	"MainHand", "SecondaryHand",
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
-- holds two lines on the left: the name, then "Level 4 Priest · Item level
-- 12" in quiet type. Blizzard centres the
-- level line in the middle of the band on every update, so it is seated
-- again after each one.
local function seatLevel()
	local frame, level = CharacterFrame, CharacterLevelText
	if not (frame and level and frame.stoaHeader) or InCombatLockdown() then return end
	local title = (frame.TitleContainer and frame.TitleContainer.TitleText) or frame.TitleText
	if title then
		title:ClearAllPoints()
		title:SetPoint("TOPLEFT", frame.stoaHeader, "TOPLEFT", 18, -10)
		title:SetJustifyH("LEFT")
	end
	-- The close cross sits level with the name, in the band's upper half,
	-- rather than halfway down the two-line header.
	local close = frame.CloseButton or _G.CharacterFrameCloseButton
	if close then
		close:ClearAllPoints()
		close:SetPoint("RIGHT", frame.stoaHeader, "TOPRIGHT", -8, -(10 + Stoa.typeSize.title / 2))
	end
	level:ClearAllPoints()
	if title then
		-- The level line keeps its own spot; the title sits higher above it.
		level:SetPoint("TOPLEFT", frame.stoaHeader, "TOPLEFT", 18, -42)
	else
		level:SetPoint("LEFT", frame.stoaHeader, "LEFT", 18, 0)
	end
	level:SetWidth(0)
	level:SetJustifyH("LEFT")
	Stoa:SetFont(level, "sans", Stoa.typeSize.body)
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
		if overall and overall > 0 then
			local text = "Item level " .. math.floor(overall + 0.5)
			if equipped and math.floor(equipped + 0.5) ~= math.floor(overall + 0.5) then
				text = text .. Stoa.UI.WIDE_SEP .. "worn " .. math.floor(equipped + 0.5)
			end
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
local BLIZZ_LEFT_W = 398
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
	if side == "LEFT" then
		name:SetPoint("TOPLEFT", button, "TOPRIGHT", 10, -4)
		sub:SetPoint("TOPLEFT", name, "BOTTOMLEFT", 0, -4)
	else
		name:SetPoint("TOPRIGHT", button, "TOPLEFT", -10, -4)
		sub:SetPoint("TOPRIGHT", name, "BOTTOMRIGHT", 0, -4)
	end
	button.stoaSide = { name = name, sub = sub }
	return button.stoaSide
end

local function slotWord(button)
	local key = button:GetName():gsub("^Character", ""):upper()
	return rawget(_G, key) or ""
end

-- Fills a slot's side words (layout on).
local function fillSide(button, link, quality, level, word)
	local side = button.stoaSide
	if not side then return end
	if not link then
		side.name:SetText(slotWord(button))
		side.name:SetTextColor(Stoa:Color("muted"))
		side.sub:SetText("")
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
	if word then words[#words + 1] = Stoa:Hex(word == "BROKEN" and "accent" or "danger") .. word .. "|r" end
	side.sub:SetText(UI.join(words))
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
	tab:HookScript("OnEnter", function(self)
		if not (self.GetChecked and self:GetChecked()) then self.stoaWord:SetTextColor(Stoa:Color("text")) end
	end)
	tab:HookScript("OnLeave", function() Character:PaintTabs() end)
end

function Character:PaintTabs()
	local tabs = CharacterFrame and CharacterFrame.ModeTabs and CharacterFrame.ModeTabs.Tabs
	for _, tab in ipairs(tabs or {}) do
		if tab.stoaWord then
			local on = tab.GetChecked and tab:GetChecked()
			tab.stoaWord:SetTextColor(Stoa:Color(on and "accent" or "muted"))
			tab.stoaUnder:SetVertexColor(Stoa:Color("accent"))
			tab.stoaUnder:SetShown(on and true or false)
		end
	end
end

function Character:PlaceTabs()
	local frame = CharacterFrame
	local tabs = frame and frame.ModeTabs and frame.ModeTabs.Tabs
	if not tabs or InCombatLockdown() then return end
	local close = frame.CloseButton or _G.CharacterFrameCloseButton
	local previous
	for i = #tabs, 1, -1 do
		local tab = tabs[i]
		dressTab(tab, i)
		if tab:IsShown() then
			tab:ClearAllPoints()
			tab:SetSize(math.ceil(tab.stoaWord:GetStringWidth()) + 4, 28)
			if previous then
				tab:SetPoint("RIGHT", previous, "LEFT", -18, 0)
			else
				tab:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -52, -15)
			end
			previous = tab
		end
	end
	self:PaintTabs()
end

local function hideArt()
	local scene = CharacterModelScene
	if scene then
		for _, key in ipairs({ "BackgroundTopLeft", "BackgroundTopRight", "BackgroundBotLeft", "BackgroundBotRight", "BackgroundOverlay" }) do
			hide(scene[key])
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
		row.Title:SetTextColor(Stoa:Color("accent"))
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

local function dressStats()
	for _, pane in ipairs({ CharacterStatsPaneScrollBox, CharacterStatsPanePetScrollBox }) do
		local box = pane and pane.ScrollBox
		if box and not box.stoaHooked and box.ForEachFrame then
			box.stoaHooked = true
			local function each() box:ForEachFrame(function(row) guarded(dressStatRow, row) end) end
			hooksecurefunc(box, "Update", each)
			each()
		end
	end
end

local laidOut
-- Moves the slots and sizes the window. Out of combat only; run again
-- whenever Blizzard sizes the window (each tab change).
function Character:LayOut()
	local frame = CharacterFrame
	if not (frame and layoutOn()) then return end
	if InCombatLockdown() then
		self.layOutAfterCombat = true
		return
	end
	local left = frame.LeftPaneHost
	if not onSheet() then
		if left and left:GetWidth() ~= BLIZZ_LEFT_W then left:SetWidth(BLIZZ_LEFT_W) end
		self:PlaceTabs()
		return
	end
	local collapsed = frame.IsRightPaneCollapsed and frame:IsRightPaneCollapsed()
	local right = frame.RightPaneHost
	local rightW = (not collapsed and right and right:GetWidth()) or 0
	frame:SetSize(LEFT_W + rightW, SHEET_H)
	if left then left:SetWidth(LEFT_W) end
	if not laidOut then
		laidOut = true
		hideArt()
		dressStats()
		footer()
		-- The toggle for the stats column stays only while it's folded, so
		-- the column can always be brought back.
		local toggle = frame.RightPaneToggleButton
		if toggle then
			local function seat() toggle:SetAlpha(frame.IsRightPaneCollapsed and frame:IsRightPaneCollapsed() and 1 or 0) end
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
	local windows = Stoa.modules.Windows
	if windows and windows.OnSettle then windows:OnSettle(frame, function() guarded(seatLevel) end) end
	frame:HookScript("OnShow", function()
		guarded(seatLevel)
		guarded(Character.Refresh, Character)
	end)
	if layoutOn() then
		-- Blizzard sizes the window on every tab change; the layout follows.
		if frame.UpdateSize then hooksecurefunc(frame, "UpdateSize", function() guarded(Character.LayOut, Character) end) end
		if frame.UpdateTabLayout then hooksecurefunc(frame, "UpdateTabLayout", function() guarded(Character.PlaceTabs, Character) end) end
		if frame.SetSelectedModeTabByFrame then hooksecurefunc(frame, "SetSelectedModeTabByFrame", function() guarded(Character.PaintTabs, Character) end) end
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
	Stoa:On("UPDATE_INVENTORY_DURABILITY", function() Character:Refresh() end)
	Stoa:On("PLAYER_EQUIPMENT_CHANGED", function() Character:Refresh() end)
	Stoa:On("INSPECT_READY", function() guarded(refreshInspect) end)
	Stoa:On("GET_ITEM_INFO_RECEIVED", function()
		Character:Refresh()
		guarded(refreshInspect)
	end)
end
