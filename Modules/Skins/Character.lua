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
local _, ns = ...
local Stoa = ns.Stoa
local hooksecurefunc = Stoa.SafeHook
local UI = Stoa.UI

local Character = Stoa:NewModule("Character")

local guarded = Stoa.safe.guarded

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
	local parts = Stoa.ItemSkin.markSlot(button, link and quality or 0, level)
	if not (parts and withWear) then return end
	local word = link and wearWord(slotID)
	local fs = wearText(button)
	if not fs then return end
	fs:SetText(word or "")
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
	level:ClearAllPoints()
	if title then
		level:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -5)
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
				text = text .. "  ·  worn " .. math.floor(equipped + 0.5)
			end
			averageText(CharacterFrame):SetText("·  " .. text)
		else
			averageText(CharacterFrame):SetText("")
		end
	end
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
