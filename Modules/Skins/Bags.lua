-- Stoa: Blizzard's bags in Stoa's dress.
-- The bag windows keep Blizzard's own item buttons (they are secure-ish, and
-- replacing them is not worth the risk); Stoa redraws them. Slots become
-- rounded squares with a hairline edge, the edge takes the item's quality
-- colour, and epic and better also get a small corner mark (one pip for epic,
-- two above that) so quality never rests on colour alone. Gear shows its item
-- level. Each bag gets a free-slot count, a money line in gold, silver and
-- copper letters, and a Sort button.
--
-- This file also holds the small item-slot helpers the character sheet and
-- inspect window use (Stoa.ItemSkin).
--
-- Everything is looked up by name and guarded: a frame or call this client
-- has renamed or left out is skipped without a word.
local _, ns = ...
local Stoa = ns.Stoa
local hooksecurefunc = Stoa.SafeHook
local UI = Stoa.UI

local Bags = Stoa:NewModule("Bags", { bagMode = "combined", reagentsInBag = true, bagView = "sections" })

local guarded = Stoa.safe.guarded

-- Item slot helpers ---------------------------------------------------------

local Item = {}
Stoa.ItemSkin = Item

local MASK = UI.MEDIA .. "Textures\\ButtonMask"
local EPIC = (Enum and Enum.ItemQuality and Enum.ItemQuality.Epic) or 4
local COMMON = (Enum and Enum.ItemQuality and Enum.ItemQuality.Common) or 1

-- Quality colour for an edge, or nil for grey and white (they keep the
-- plain hairline).
function Item.qualityColour(quality)
	quality = Stoa:PlainNumber(quality)
	if not quality or quality <= COMMON then return nil end
	if C_Item and C_Item.GetItemQualityColor then
		local ok, r, g, b = pcall(C_Item.GetItemQualityColor, quality)
		if ok and type(r) == "number" then return r, g, b end
	end
	local colours = ITEM_QUALITY_COLORS
	local c = type(colours) == "table" and colours[quality]
	if type(c) == "table" and type(c.r) == "number" then return c.r, c.g, c.b end
end

-- Effective item level of a link, only for things you can wear or wield.
Item.itemLevel = Stoa.Items.level

-- Draws the rounded slot once: square art hidden, icon masked, a dim socket
-- with a hairline edge, and the pieces quality and item level need.
local HIDDEN_ART = { "IconBorder", "Border", "SlotArt", "SlotBackground", "NormalTexture" }

local function hideSquareArt(button)
	for _, key in ipairs(HIDDEN_ART) do
		local art = button[key]
		if art and art.SetAlpha then art:SetAlpha(0) end
	end
	local normal = button.GetNormalTexture and button:GetNormalTexture()
	if normal then normal:SetAlpha(0) end
end

function Item.skinSlot(button)
	if not button or button.stoaItem then return button and button.stoaItem end
	local icon = button.icon or button.Icon
	if not (icon and button.CreateTexture) then return nil end
	local parts = {}
	button.stoaItem = parts
	hideSquareArt(button)
	icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
	if button.CreateMaskTexture then
		local mask = button:CreateMaskTexture()
		mask:SetAllPoints()
		mask:SetTexture(MASK, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
		-- Build 70634 gives item buttons their own icon mask (button.Mask, set on
		-- the icon, normal and pushed textures); two masks would clip twice.
		if button.IconMask then pcall(icon.RemoveMaskTexture, icon, button.IconMask) end
		if button.Mask then pcall(icon.RemoveMaskTexture, icon, button.Mask) end
		icon:AddMaskTexture(mask)
		for _, getter in ipairs({ "GetHighlightTexture", "GetPushedTexture", "GetNormalTexture" }) do
			local tex = button[getter] and button[getter](button)
			if tex then
				if button.Mask then pcall(tex.RemoveMaskTexture, tex, button.Mask) end
				if getter ~= "GetNormalTexture" then pcall(tex.AddMaskTexture, tex, mask) end
			end
		end
	end
	UI.roundPanel(button, 0.9)
	parts.edge = UI.roundBorder(button, "CardEdge.tga", 1)

	-- Corner marks: small squares, one for epic, two above that.
	parts.pips = {}
	for i = 1, 2 do
		local pip = button:CreateTexture(nil, "OVERLAY", nil, 6)
		pip:SetSize(5, 5)
		pip:SetPoint("TOPRIGHT", button, "TOPRIGHT", -3, -3 - (i - 1) * 7)
		pip:SetColorTexture(1, 1, 1, 1)
		pip:Hide()
		parts.pips[i] = pip
	end

	parts.level = button:CreateFontString(nil, "OVERLAY", nil, 7)
	Stoa:SetFont(parts.level, "sans", Stoa.typeSize.caption, "OUTLINE")
	parts.level:SetPoint("TOPLEFT", button, "TOPLEFT", 3, -3)
	parts.level:SetTextColor(Stoa:Color("text"))
	UI.paint(parts.level, "text")

	-- Blizzard puts its square art back when a slot's contents change.
	if button.UpdateButtonArt then hooksecurefunc(button, "UpdateButtonArt", hideSquareArt) end
	return parts
end

-- Sets what a slot shows for the item in it. level is the number to print
-- (nil prints none); quality 0 or nil with no link means an empty slot.
function Item.markSlot(button, quality, level)
	local parts = Item.skinSlot(button)
	if not parts then return end
	hideSquareArt(button)
	local r, g, b = Item.qualityColour(quality)
	if r then parts.edge:Set(r, g, b, 1) else parts.edge:Clear() end
	quality = Stoa:PlainNumber(quality) or 0
	local pips = quality > EPIC and 2 or quality == EPIC and 1 or 0
	for i, pip in ipairs(parts.pips) do
		if i <= pips and r then
			pip:SetColorTexture(r, g, b, 1)
			pip:Show()
		else
			pip:Hide()
		end
	end
	if level then parts.level:SetText(level) else parts.level:SetText("") end
	return parts
end

-- A small UP in the slot's foot for gear that beats what you wear, scored
-- for your role (Stoa.Items.upgrade, or Pawn's scales when Pawn is loaded).
function Item.markUpgrade(button, parts, on)
	if not parts then return end
	if on and not parts.up then
		parts.up = button:CreateFontString(nil, "OVERLAY", nil, 7)
		Stoa:SetFont(parts.up, "sans", Stoa.typeSize.micro, "OUTLINE")
		parts.up:SetPoint("BOTTOMLEFT", button, "BOTTOMLEFT", 3, 3)
		parts.up:SetText("UP")
	end
	if parts.up then
		parts.up:SetTextColor(Stoa:Color("accent"))
		parts.up:SetShown(on and true or false)
	end
end

-- Bags ----------------------------------------------------------------------

local function items(frame)
	if frame.EnumerateValidItems then
		local list = {}
		for _, button in frame:EnumerateValidItems() do list[#list + 1] = button end
		return list
	end
	return frame.Items or {}
end

local function bagIDOf(button)
	if button.GetBagID then return button:GetBagID() end
	local parent = button.GetParent and button:GetParent()
	return parent and parent.GetID and parent:GetID()
end

-- Junk marking ----------------------------------------------------------------
-- A "Junk" button on the bag turns marking on. While it is on, a clear
-- overlay of Stoa's own sits over each item and takes the click, so the
-- item underneath is never used or picked up by mistake. Blizzard's item
-- buttons are not touched. Marking turns itself off when the bag closes or
-- a fight starts.
Bags.junkMode = false

local function junkWord(button)
	local word = button.stoaJunkWord
	if not word and button.CreateFontString then
		word = button:CreateFontString(nil, "OVERLAY", nil, 7)
		Stoa:SetFont(word, "sans", Stoa.typeSize.micro, "OUTLINE")
		word:SetPoint("BOTTOM", button, "BOTTOM", 0, 3)
		word:SetTextColor(Stoa:Color("muted"))
		word:SetText("JUNK")
		button.stoaJunkWord = word
	end
	return word
end

local function markJunkWord(button, itemID)
	local marked = itemID and Stoa.Items.isMarkedJunk(itemID)
	local word = marked and junkWord(button) or button.stoaJunkWord
	if word then word:SetShown(marked and true or false) end
	-- Dimmed as well as worded, so it reads at a glance.
	local icon = button.icon or button.Icon
	if icon and icon.SetAlpha then icon:SetAlpha(marked and 0.55 or 1) end
end

local function overlayClick(overlay)
	local button = overlay:GetParent()
	local bag, slot = bagIDOf(button), button.GetID and button:GetID()
	local info = bag and slot and C_Container and C_Container.GetContainerItemInfo and C_Container.GetContainerItemInfo(bag, slot)
	if type(info) ~= "table" or not info.itemID then return end
	Stoa.Items.setJunk(info.itemID, not Stoa.Items.isMarkedJunk(info.itemID))
end

local function junkOverlay(button, on)
	local overlay = button.stoaJunkOverlay
	if not overlay then
		if not on or not CreateFrame then return end
		overlay = CreateFrame("Button", nil, button)
		overlay:SetAllPoints(button)
		overlay:SetFrameLevel((button:GetFrameLevel() or 1) + 5)
		overlay:RegisterForClicks("LeftButtonUp")
		overlay:SetScript("OnClick", function(self) xpcall(overlayClick, Stoa.catch, self) end)
		button.stoaJunkOverlay = overlay
	end
	overlay:SetShown(on and true or false)
end

local function applyJunkMode(frame)
	local parts = frame.stoaBag
	if parts and parts.junk then parts.junk:SetSelected(Bags.junkMode) end
	for _, button in ipairs(items(frame)) do junkOverlay(button, Bags.junkMode) end
end

function Bags:SetJunkMode(on)
	on = on and not InCombatLockdown() or false
	if on == self.junkMode then return end
	self.junkMode = on
	local list = self.frames or {}
	for i = 1, 14 do
		local frame = list[i]
		if frame and frame.stoaBag then guarded(applyJunkMode, frame) end
	end
end

local function addJunk(frame, parts)
	local junk = UI.button(frame, "Junk", 48, function() Bags:SetJunkMode(not Bags.junkMode) end)
	junk:SetHeight(20)
	if parts.sort then
		junk:SetPoint("RIGHT", parts.sort, "LEFT", -6, 0)
	else
		junk:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -90, -6)
	end
	parts.junk = junk
	aboveTitle(frame, junk)
end

local function decorateButton(button)
	local bag, slot = bagIDOf(button), button.GetID and button:GetID()
	local info = bag and slot and C_Container and C_Container.GetContainerItemInfo and C_Container.GetContainerItemInfo(bag, slot)
	if not info then
		button.stoaLink = nil
		Item.markUpgrade(button, Item.markSlot(button, 0, nil), false)
		markJunkWord(button, nil)
		return
	end
	markJunkWord(button, info.itemID)
	local link = info.hyperlink
	-- Reading the level costs a lookup, so an unchanged slot is left alone.
	if button.stoaLink ~= link or button.stoaQuality ~= info.quality then
		button.stoaLink, button.stoaQuality = link, info.quality
		button.stoaLevel = Item.itemLevel(link)
		local gain = Stoa.Items.upgrade(link)
		button.stoaUpgrade = gain and gain > 0
	end
	local parts = Item.markSlot(button, info.quality, button.stoaLevel)
	-- An item one of your quests still needs: the edge in the accent.
	if parts and Stoa.Items.questNeeds(info.itemID, info.itemName) then
		parts.edge:Set(Stoa:Color("accent"))
	end
	-- Another addon's gear planner marks upgrades in bags already (Core/Companions.lua).
	Item.markUpgrade(button, parts, button.stoaUpgrade and not Stoa:SharedBy("bagUpgrade"))
end

-- Gold, silver and copper with the game's coin icons, as the hover shows them.
local function moneyWords(copper)
	copper = Stoa:PlainNumber(copper) or 0
	local gold = math.floor(copper / 10000)
	local silver = math.floor(copper / 100) % 100
	local rest = copper % 100
	local out = {}
	if gold > 0 then out[#out + 1] = (BreakUpLargeNumbers and BreakUpLargeNumbers(gold) or gold) .. "g" end
	if silver > 0 or gold > 0 then out[#out + 1] = silver .. "s" end
	out[#out + 1] = rest .. "c"
	return Stoa:TintMoney(table.concat(out, " "))
end

local function freeSlots(frame)
	if not (C_Container and C_Container.GetContainerNumFreeSlots) then return nil end
	if frame.IsCombinedBagContainer and frame:IsCombinedBagContainer() then
		if C_Container.CalculateTotalNumberOfFreeBagSlots then
			return C_Container.CalculateTotalNumberOfFreeBagSlots()
		end
		local total = 0
		for bag = 0, (NUM_BAG_SLOTS or 4) + 1 do total = total + (C_Container.GetContainerNumFreeSlots(bag) or 0) end
		return total
	end
	local bag = frame.GetBagID and frame:GetBagID()
	if not bag then return nil end
	local free = C_Container.GetContainerNumFreeSlots(bag)
	local size = C_Container.GetContainerNumSlots and C_Container.GetContainerNumSlots(bag)
	return free, size
end

-- Currencies ticked "Show on Backpack" in the Currency tab, as icon and
-- count after the free count.
local function currencyWords()
	local get = C_CurrencyInfo and C_CurrencyInfo.GetBackpackCurrencyInfo
	if not get then return "" end
	local out = {}
	for i = 1, 8 do
		local ok, info = pcall(get, i)
		if not (ok and type(info) == "table") then break end
		local count = Stoa:PlainNumber(info.quantity) or 0
		local amount = BreakUpLargeNumbers and BreakUpLargeNumbers(count) or tostring(count)
		out[#out + 1] = ("|T%s:0:0:0:0:64:64:5:59:5:59|t %s"):format(info.iconFileID or 134400, amount)
	end
	if #out == 0 then return "" end
	return "   " .. table.concat(out, "   ")
end

local function updateFooter(frame)
	local parts = frame.stoaBag
	if not parts then return end
	local free, size = freeSlots(frame)
	if free then
		local text = size and (free .. " of " .. size .. " free") or (free .. " free")
		if frame.IsCombinedBagContainer and frame:IsCombinedBagContainer() then
			text = text .. currencyWords()
		end
		parts.free:SetText(text)
		-- Full is said in words as well as the warm colour.
		if free == 0 then
			parts.free:SetText("FULL" .. ((frame.IsCombinedBagContainer and frame:IsCombinedBagContainer()) and currencyWords() or ""))
			parts.free:SetTextColor(Stoa:Color("danger"))
		else
			parts.free:SetTextColor(Stoa:Color("muted"))
		end
	end
	if parts.money then parts.money:SetText(moneyWords(GetMoney and GetMoney())) end
	if parts.sort then
		local bag = frame.GetBagID and frame:GetBagID()
		local combined = frame.IsCombinedBagContainer and frame:IsCombinedBagContainer()
		parts.sort:SetShown(combined or bag == 0)
	end
end

-- Hovering the money lists every character's gold (Core/Alts.lua) and the
-- total, richest first.
local function moneyTooltip(owner)
	local alts = Stoa.Alts
	if not (alts and alts.all) then return end
	if alts.Note then pcall(alts.Note, alts) end
	local list = alts.all()
	GameTooltip:SetOwner(owner, "ANCHOR_TOP")
	GameTooltip:AddLine("Money")
	local me = alts.me and alts.me()
	local realm = me and select(3, alts.me())
	local myName = me and select(2, alts.me())
	for _, entry in ipairs(list) do
		local color = RAID_CLASS_COLORS and RAID_CLASS_COLORS[entry.class or ""]
		local name = entry.name or "?"
		if entry.realm and realm and entry.realm ~= realm then name = name .. " - " .. entry.realm end
		local r, g, b = 1, 1, 1
		if color then r, g, b = color.r, color.g, color.b end
		-- The character you are on: its sum in the accent, the rest quieter.
		local mr, mg, mb = Stoa:Color("muted")
		if myName and entry.name == myName and (not entry.realm or entry.realm == realm) then
			mr, mg, mb = Stoa:Color("text")
		end
		GameTooltip:AddDoubleLine(name, Stoa:Money(entry.money or 0), r, g, b, mr, mg, mb)
	end
	if #list > 1 then
		GameTooltip:AddLine(" ")
		local r, g, b = Stoa:Color("muted")
		GameTooltip:AddDoubleLine("Total", Stoa:Money(alts.totalMoney()), r, g, b, 1, 1, 1)
	end
	GameTooltip:Show()
end

local function moneyHover(frame, text)
	local hover = CreateFrame("Frame", nil, frame)
	hover:SetPoint("TOPRIGHT", text, "TOPRIGHT", 4, 4)
	hover:SetPoint("BOTTOMLEFT", text, "BOTTOMLEFT", -4, -4)
	hover:SetFrameLevel(frame:GetFrameLevel() + 20)
	hover:EnableMouse(true)
	hover:SetScript("OnEnter", function(self) guarded(moneyTooltip, self) end)
	hover:SetScript("OnLeave", function() GameTooltip:Hide() end)
	return hover
end

-- Blizzard lays an invisible button over the whole title strip that opens
-- the bag menu; the header words sit above it so their clicks reach them.
local function aboveTitle(frame, button)
	button:SetFrameLevel((frame:GetFrameLevel() or 1) + 10)
end

-- The Sort button, only where Blizzard has something to call.
local function addSort(frame, parts)
	if not (C_Container and C_Container.SortBags) then return end
	local sort = UI.button(frame, "Sort", 48, function()
		if InCombatLockdown() then return end
		guarded(C_Container.SortBags)
	end)
	sort:SetHeight(20)
	local close = frame.CloseButton or (frame.GetName and frame:GetName() and _G[frame:GetName() .. "CloseButton"])
	if close and close.GetObjectType then
		sort:SetPoint("RIGHT", close, "LEFT", -6, 0)
	else
		sort:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -36, -6)
	end
	parts.sort = sort
	aboveTitle(frame, sort)
end

local function decorateFrame(frame)
	if not frame or not frame.stoaBag then return end
	for _, button in ipairs(items(frame)) do
		guarded(decorateButton, button)
		if Bags.junkMode then guarded(junkOverlay, button, true) end
	end
	updateFooter(frame)
end

function Bags:Dress(frame)
	if not frame or frame.stoaBag then return end
	local parts = {}
	frame.stoaBag = parts
	-- The common Stoa window: panel, title, close cross, no stone border.
	local windows = Stoa.modules.Windows
	if windows and windows.Dress then guarded(windows.Dress, windows, frame) end
	-- Bags are small windows: their name is a label, not a window title.
	-- Windows seats the title on every show, so the size lives on the frame.
	frame.stoaTitleSize = Stoa.typeSize.label
	local title = (frame.TitleContainer and frame.TitleContainer.TitleText) or frame.TitleText
	if title and title.SetTextColor then Stoa:SetFont(title, "serif", Stoa.typeSize.label) end

	parts.free = UI.text(frame, "sans", Stoa.typeSize.body, "muted")
	parts.free:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 14, 10)
	parts.money = UI.text(frame, "sans", Stoa.typeSize.body, "text", "RIGHT")
	parts.money:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -14, 10)
	-- Blizzard's coin display steps aside only now that ours exists.
	if frame.MoneyFrame and frame.MoneyFrame.SetAlpha then frame.MoneyFrame:SetAlpha(0) end
	parts.moneyHover = moneyHover(frame, parts.money)
	addSort(frame, parts)
	addJunk(frame, parts)

	-- Update hooks: after Blizzard refreshes the item buttons, and when the
	-- window opens.
	if frame.UpdateItems then
		hooksecurefunc(frame, "UpdateItems", function() guarded(decorateFrame, frame) end)
	end
	frame:HookScript("OnShow", function() guarded(decorateFrame, frame) end)
	frame:HookScript("OnHide", function() guarded(Bags.SetJunkMode, Bags, false) end)
end

local function allFrames()
	local list = { ContainerFrameCombinedBags }
	for i = 1, 13 do list[#list + 1] = _G["ContainerFrame" .. i] end
	return list
end

local function refreshShown()
	for _, frame in ipairs(allFrames()) do
		if frame and frame.IsShown and frame:IsShown() then guarded(decorateFrame, frame) end
	end
end

-- Reagents in the combined bag ---------------------------------------------
-- The game keeps the reagent bag (bag 5) out of the combined bag, in a
-- window of its own. With the combined bag open, Stoa opens the reagent bag
-- too and seats it as the combined bag's bottom section: the combined bag
-- grows by the section's height, its items move up (they hang off its
-- hidden money frame, which moves up with them), and the reagent window,
-- its own panel, title and buttons hidden, sits in the room left above the
-- footer with its slots in the same ten columns. Blizzard's own windows and
-- item buttons do all the work; only places and sizes change.
local REAGENT_BAG = 5
local COLUMNS, GAP = 10, 5
local SECTION_TOP, SECTION_BOTTOM = 22, 8

local function reagentSlots()
	if not (C_Container and C_Container.GetContainerNumSlots) then return 0 end
	local ok, n = pcall(C_Container.GetContainerNumSlots, REAGENT_BAG)
	return ok and type(n) == "number" and n or 0
end

local function reagentFrame()
	for i = 1, 13 do
		local frame = _G["ContainerFrame" .. i]
		if frame and frame.IsShown and frame:IsShown() and frame.GetBagID and frame:GetBagID() == REAGENT_BAG then
			return frame
		end
	end
end

local function dockWanted()
	local combined = ContainerFrameCombinedBags
	return Bags.db.reagentsInBag ~= false and combined and combined:IsShown() and reagentSlots() > 0
end

-- The reagent window's own dress (panel, header, title, close, footer and
-- buttons) steps aside while it is a section, leaving only its item buttons
-- and the section's label and rule; all of it comes back when it stands
-- alone again.
local function sectionLook(frame, docked)
	if docked and not frame.stoaSection then
		local section = {}
		section.label = UI.text(frame, "sans", Stoa.typeSize.caption, "muted")
		section.label:SetPoint("TOPLEFT", frame, "TOPLEFT", 9, -4)
		section.rule = UI.fadeRule(frame, "text", 0.2)
		section.rule:SetPoint("LEFT", frame, "TOPLEFT", 7, -(SECTION_TOP - 5))
		section.rule:SetPoint("RIGHT", frame, "TOPRIGHT", -7, -(SECTION_TOP - 5))
		frame.stoaSection = section
	end
	local section = frame.stoaSection
	if not section then return end
	local keep = { [section.label] = true, [section.rule] = true }
	for _, button in ipairs(items(frame)) do keep[button] = true end
	frame.stoaHidden = frame.stoaHidden or {}
	local hidden = frame.stoaHidden
	local function each(region)
		if keep[region] or not region.IsShown then return end
		if docked then
			if region:IsShown() then
				hidden[region] = true
				region:Hide()
			end
		elseif hidden[region] then
			hidden[region] = nil
			region:Show()
		end
	end
	for _, region in ipairs({ frame:GetRegions() }) do each(region) end
	for _, child in ipairs({ frame:GetChildren() }) do
		-- Item buttons, and the pooled ones not in use, keep their own state.
		if not (child.GetBagID or child.isBag ~= nil) then each(child) end
	end
	section.label:SetShown(docked)
	section.rule:SetShown(docked)
end

local seatCombined

local function sectionHeight(slots, size)
	local rows = math.ceil(slots / COLUMNS)
	return SECTION_TOP + rows * size + (rows - 1) * GAP + SECTION_BOTTOM
end

-- The game's currency row (Currency > Show on Backpack) steps aside: the
-- footer names those currencies beside the free count instead, so the row's
-- height comes off the bag. `extra` is room added above the footer for the
-- reagent section. Returns the footer row's bottom offset.
seatCombined = function(combined, extra)
	local money = combined.MoneyFrame
	if not money then return 8 end
	local tracker = ContainerFrameSettingsManager and ContainerFrameSettingsManager.GetTokenTrackerIfShown
		and ContainerFrameSettingsManager:GetTokenTrackerIfShown(combined)
	local trackerRoom = 0
	if type(tracker) == "table" and tracker.GetHeight then
		trackerRoom = (tracker:GetHeight() or 0) + 3
		tracker:SetAlpha(0)
		if tracker.EnableMouse then tracker:EnableMouse(false) end
		for _, child in ipairs({ tracker:GetChildren() }) do
			if child.EnableMouse then child:EnableMouse(false) end
		end
	end
	local height = combined.CalculateHeight and combined:CalculateHeight()
	if type(height) == "number" then combined:SetHeight(height - trackerRoom + extra + (combined.stoaSectionExtra or 0)) end
	money:ClearAllPoints()
	money:SetPoint("BOTTOMLEFT", combined, "BOTTOMLEFT", 8, 8 + extra)
	money:SetPoint("BOTTOMRIGHT", combined, "BOTTOMRIGHT", -8, 8 + extra)
	return 8
end

function Bags:DockReagents()
	if self.docking then return end
	self.docking = true
	guarded(function()
		local combined = ContainerFrameCombinedBags
		local frame = reagentFrame()
		if not dockWanted() then
			-- reagentFrame() only finds a shown window; a docked one hides
			-- with the combined bag, so look for it by its mark too.
			if not frame then
				for i = 1, 13 do
					local each = _G["ContainerFrame" .. i]
					if each and each.stoaDocked then frame = each end
				end
			end
			local wasDocked = frame and frame.stoaDocked
			if wasDocked then
				frame.stoaDocked = nil
				sectionLook(frame, false)
				frame:SetParent(frame.stoaParent or UIParent)
			end
			-- A docked reagent bag goes with the combined bag.
			if (wasDocked or Bags.openedReagents) and not (combined and combined:IsShown()) then
				Bags.openedReagents = nil
				if frame and CloseBag then CloseBag(REAGENT_BAG) end
			elseif wasDocked and UpdateContainerFrameAnchors then
				UpdateContainerFrameAnchors()
			end
			if combined and combined:IsShown() then seatCombined(combined, 0) end
			return
		end
		if not frame then
			if OpenBag then OpenBag(REAGENT_BAG) end
			frame = reagentFrame()
			if not frame then return end
			Bags.openedReagents = true
		end
		local buttons = items(frame)
		table.sort(buttons, function(a, b) return (a:GetID() or 0) < (b:GetID() or 0) end)
		local first = buttons[1]
		local size = first and first:GetWidth() or 37
		if size <= 0 then size = 37 end
		local section = sectionHeight(#buttons, size)
		local money = combined.MoneyFrame
		if not money then return end
		local moneyHeight = money:GetHeight() or 13
		-- The section sits between the items and the footer: the footer
		-- keeps its row at the bottom, the items move up by the section.
		local extra = section + moneyHeight + 4

		local base = seatCombined(combined, extra)

		-- The reagent window in the room above the footer, as a child of
		-- the combined bag: drawn over its panel whichever window the game
		-- raised last, and hidden with it.
		frame.stoaDocked = true
		sectionLook(frame, true)
		if frame:GetParent() ~= combined then
			frame.stoaParent = frame:GetParent()
			frame:SetParent(combined)
		end
		frame:SetScale(1)
		frame:SetFrameLevel(combined:GetFrameLevel() + 5)
		frame:ClearAllPoints()
		frame:SetPoint("BOTTOMLEFT", combined, "BOTTOMLEFT", 0, base + moneyHeight + 4)
		frame:SetPoint("BOTTOMRIGHT", combined, "BOTTOMRIGHT", 0, base + moneyHeight + 4)
		frame:SetHeight(section)
		for i, button in ipairs(buttons) do
			local col, row = (i - 1) % COLUMNS, math.floor((i - 1) / COLUMNS)
			button:ClearAllPoints()
			button:SetPoint("TOPLEFT", frame, "TOPLEFT", 7 + col * (size + GAP), -(SECTION_TOP + row * (size + GAP)))
		end
		local free = C_Container.GetContainerNumFreeSlots and C_Container.GetContainerNumFreeSlots(REAGENT_BAG)
		local name = C_Container.GetBagName and C_Container.GetBagName(REAGENT_BAG)
		frame.stoaSection.label:SetText(((name and name ~= "") and name or "Reagents"):upper()
			.. (free and (Stoa.UI.WIDE_SEP .. free .. " free") or ""))
	end)
	self.docking = false
end

-- Sections ------------------------------------------------------------------
-- The combined bag can sort its slots into sections (new, consumables, trade
-- goods, quest, equipment, other, junk, then empty slots) or keep the game's
-- one grid in bag order. A word in the header switches between them.
-- Blizzard's item buttons stay as they are; only their places change, laid
-- out after the game's own layout from the same anchor (the money row), so
-- the reagent section and footer below are untouched. The bag grows by the
-- room the section labels need.
local LABEL_H, SECTION_GAP = 18, 8
local SECTIONS = {
	{ key = "new", label = NEW or "New", token = "accent" },
	{ key = "consumable", label = BAG_FILTER_CONSUMABLES or "Consumables" },
	{ key = "trade", label = BAG_FILTER_TRADE_GOODS or "Trade Goods" },
	{ key = "quest", label = QUESTS_LABEL or "Quests" },
	{ key = "equipment", label = BAG_FILTER_EQUIPMENT or "Equipment" },
	{ key = "other", label = OTHER or "Other" },
	{ key = "junk", label = BAG_FILTER_JUNK or "Junk", token = "muted" },
	{ key = "empty", label = EMPTY or "Empty", token = "muted" },
}
local CLASS_SECTION = { [0] = "consumable", [2] = "equipment", [4] = "equipment", [3] = "trade", [5] = "trade", [7] = "trade", [9] = "trade", [12] = "quest" }

function Bags.SectionOf(bag, slot)
	local info = C_Container.GetContainerItemInfo(bag, slot)
	if type(info) ~= "table" or not info.itemID then return "empty" end
	if C_NewItems and C_NewItems.IsNewItem and C_NewItems.IsNewItem(bag, slot) then return "new" end
	local quality = Stoa:PlainNumber(info.quality)
	if quality == 0 or Stoa.Items.isMarkedJunk(info.itemID) then return "junk" end
	local quest = C_Container.GetContainerItemQuestInfo and C_Container.GetContainerItemQuestInfo(bag, slot)
	if type(quest) == "table" and (quest.isQuestItem or quest.questID) then return "quest" end
	local classID = C_Item and C_Item.GetItemInfoInstant and select(6, C_Item.GetItemInfoInstant(info.itemID))
	return CLASS_SECTION[classID] or "other"
end

function Bags:SectionsOn()
	return self.db.bagView ~= "grid"
end

local function sectionLabel(combined, i)
	combined.stoaSectionLabels = combined.stoaSectionLabels or {}
	local label = combined.stoaSectionLabels[i]
	if not label then
		label = {
			name = UI.text(combined, "sans", Stoa.typeSize.caption, "muted"),
			count = UI.text(combined, "sans", Stoa.typeSize.caption, "muted", "RIGHT"),
		}
		combined.stoaSectionLabels[i] = label
	end
	return label
end

local function hideLabels(combined, from)
	for i = from, #(combined.stoaSectionLabels or {}) do
		local label = combined.stoaSectionLabels[i]
		label.name:Hide()
		label.count:Hide()
	end
end

function Bags:LayOutSections()
	local combined = ContainerFrameCombinedBags
	if not (combined and combined.stoaBag and combined:IsShown()) then return end
	if self.laying then return end
	local money = combined.MoneyFrame
	local buttons = items(combined)
	if not money or #buttons == 0 then return end
	if InCombatLockdown() and (combined:IsProtected() or buttons[1]:IsProtected()) then
		Stoa:AfterCombat(function() Bags:LayOutSections() end)
		return
	end
	self.laying = true
	guarded(function()
		if not self:SectionsOn() then
			hideLabels(combined, 1)
			if (combined.stoaSectionExtra or 0) ~= 0 or combined.stoaSectioned then
				combined.stoaSectionExtra, combined.stoaSectioned = 0, nil
				-- The game's own grid again.
				if combined.UpdateItemLayout then combined:UpdateItemLayout() end
				Bags:DockReagents()
			end
			return
		end
		local groups = {}
		for _, button in ipairs(buttons) do
			local bag, slot = bagIDOf(button), button:GetID()
			local key = bag and slot and Bags.SectionOf(bag, slot) or "other"
			groups[key] = groups[key] or {}
			table.insert(groups[key], button)
		end
		local size = buttons[1]:GetWidth() or 37
		if size <= 0 then size = 37 end
		local cols = combined.GetColumns and combined:GetColumns() or COLUMNS
		local width = cols * size + (cols - 1) * GAP
		-- Top-down offsets first, then placed from the money row up.
		local placed, labels, top = {}, {}, 0
		for _, section in ipairs(SECTIONS) do
			local list = groups[section.key]
			if list and #list > 0 then
				table.sort(list, function(a, b)
					local ba, bb = bagIDOf(a) or 0, bagIDOf(b) or 0
					if ba ~= bb then return ba < bb end
					return a:GetID() < b:GetID()
				end)
				labels[#labels + 1] = { section = section, top = top, count = #list }
				top = top + LABEL_H
				for i, button in ipairs(list) do
					local col, row = (i - 1) % cols, math.floor((i - 1) / cols)
					placed[#placed + 1] = { button, col * (size + GAP), top + row * (size + GAP) }
				end
				local rows = math.ceil(#list / cols)
				top = top + rows * size + (rows - 1) * GAP + SECTION_GAP
			end
		end
		local height = top - SECTION_GAP
		local base = 4 + height
		for _, p in ipairs(placed) do
			p[1]:ClearAllPoints()
			p[1]:SetPoint("TOPLEFT", money, "TOPRIGHT", -width + p[2], base - p[3])
		end
		for i, l in ipairs(labels) do
			local label = sectionLabel(combined, i)
			label.name:ClearAllPoints()
			label.name:SetPoint("TOPLEFT", money, "TOPRIGHT", -width + 2, base - l.top - 3)
			label.name:SetText(l.section.label:upper())
			label.name:SetTextColor(Stoa:Color(l.section.token or "text"))
			label.count:ClearAllPoints()
			label.count:SetPoint("TOPRIGHT", money, "TOPRIGHT", -2, base - l.top - 3)
			label.count:SetText(l.count)
			label.name:Show()
			label.count:Show()
		end
		hideLabels(combined, #labels + 1)
		local rows = math.ceil(#buttons / cols)
		combined.stoaSectionExtra = height - (rows * size + (rows - 1) * GAP)
		combined.stoaSectioned = true
		Bags:DockReagents()
	end)
	self.laying = false
end

function Bags:SetView(view)
	if InCombatLockdown() then return end
	self.db.bagView = view
	local combined = ContainerFrameCombinedBags
	local word = combined and combined.stoaBag and combined.stoaBag.view
	if word then word.text:SetText(view == "grid" and "Sections" or "Grid") end
	self:LayOutSections()
end

-- "Grid" or "Sections" in the header, left of Junk: the view it switches to.
local function addViewWord(frame, parts)
	local word = UI.button(frame, Bags:SectionsOn() and "Grid" or "Sections", 64, function()
		Bags:SetView(Bags:SectionsOn() and "grid" or "sections")
	end)
	word:SetHeight(20)
	if parts.junk then
		word:SetPoint("RIGHT", parts.junk, "LEFT", -6, 0)
	else
		word:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -146, -6)
	end
	parts.view = word
	aboveTitle(frame, word)
end
Bags.AddViewWord = addViewWord

-- Combined or separate bags is Blizzard's "combinedBags" setting. It is set
-- once when the choice changes, so the bag menu's own toggle still works
-- afterwards.
function Bags:ApplyMode()
	local want = self.db.bagMode == "separate" and 0 or 1
	if self.db.appliedMode == self.db.bagMode then return end
	if InCombatLockdown() then
		Stoa:AfterCombat(function() self:ApplyMode() end)
		return
	end
	Stoa.GameSettings:Set("Bags", "combinedBags", want)
	self.db.appliedMode = self.db.bagMode
end

function Bags:OnEnable()
	guarded(function() self:ApplyMode() end)
	self.frames = allFrames()
	for _, frame in ipairs(allFrames()) do
		if frame then guarded(self.Dress, self, frame) end
	end
	Stoa:On("BAG_UPDATE_DELAYED", refreshShown)
	-- The search box runs the bag's full width, up to the clean-up button.
	local function placeSearch(frame)
		local box = BagItemSearchBox
		if not (box and box.anchorBag == frame) then return end
		box:ClearAllPoints()
		box:SetPoint("TOPLEFT", frame, "TOPLEFT", 14, -37)
		local clean = BagItemAutoSortButton
		if clean and clean:IsShown() and clean:GetParent() == frame then
			box:SetPoint("TOPRIGHT", clean, "TOPLEFT", -8, -3)
		else
			box:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -14, -37)
		end
	end
	for _, frame in ipairs(allFrames()) do
		if frame and frame.UpdateSearchBox then
			hooksecurefunc(frame, "UpdateSearchBox", function(f) guarded(placeSearch, f) end)
		end
	end

	-- The reagent section is seated again whenever the game re-places,
	-- re-sizes or re-lays the bags.
	local function dock() Bags:DockReagents() end
	if UpdateContainerFrameAnchors then hooksecurefunc("UpdateContainerFrameAnchors", dock) end
	local combined = ContainerFrameCombinedBags
	if combined then
		for _, method in ipairs({ "UpdateFrameSize", "UpdateItemLayout", "UpdateCurrencyFrames" }) do
			if combined[method] then hooksecurefunc(combined, method, dock) end
		end
		combined:HookScript("OnShow", dock)
		combined:HookScript("OnHide", dock)
		-- Sections: laid out again after the game lays the bag out, and
		-- whenever items move between sections.
		if combined.stoaBag then guarded(addViewWord, combined, combined.stoaBag) end
		local function sections() Bags:LayOutSections() end
		for _, method in ipairs({ "UpdateItemLayout", "UpdateFrameSize" }) do
			if combined[method] then hooksecurefunc(combined, method, sections) end
		end
		combined:HookScript("OnShow", sections)
		Stoa:On("BAG_UPDATE_DELAYED", sections)
		Stoa:On("STOA_JUNK_CHANGED", sections)
		Stoa:On("STOA_QUEST_NEEDS_CHANGED", sections)
	end
	for i = 1, 13 do
		local frame = _G["ContainerFrame" .. i]
		if frame then
			for _, method in ipairs({ "UpdateFrameSize", "UpdateItemLayout" }) do
				if frame[method] then hooksecurefunc(frame, method, function(f)
					if f.GetBagID and f:GetBagID() == REAGENT_BAG then dock() end
				end) end
			end
		end
	end
	Stoa:On("BAG_UPDATE_DELAYED", function() if dockWanted() then dock() end end)
	Stoa:On("STOA_JUNK_CHANGED", refreshShown)
	Stoa:On("STOA_QUEST_NEEDS_CHANGED", refreshShown)
	Stoa:On("PLAYER_REGEN_DISABLED", function() Bags:SetJunkMode(false) end)
	Stoa:On("PLAYER_MONEY", refreshShown)
	Stoa:On("CURRENCY_DISPLAY_UPDATE", refreshShown)
	-- Ticking "Show on Backpack" fires no event, so follow the call itself.
	for _, name in ipairs({ "SetCurrencyBackpack", "SetCurrencyBackpackByID" }) do
		if C_CurrencyInfo and C_CurrencyInfo[name] then
			hooksecurefunc(C_CurrencyInfo, name, function() C_Timer.After(0, refreshShown) end)
		end
	end
	-- What counts as an upgrade moves with your gear and your role.
	local function rescore()
		for _, frame in ipairs(allFrames()) do
			if frame and frame.stoaBag then
				guarded(function()
					for _, button in ipairs(items(frame)) do button.stoaLink = nil end
				end)
			end
		end
		refreshShown()
	end
	Stoa:On("PLAYER_EQUIPMENT_CHANGED", rescore)
	Stoa:On("STOA_ROLE_CHANGED", rescore)
	Stoa:On("PLAYER_LEVEL_UP", function() C_Timer.After(1, rescore) end)
	-- Item links load a moment after the bag does.
	Stoa:On("GET_ITEM_INFO_RECEIVED", function()
		for _, frame in ipairs(allFrames()) do
			if frame and frame.stoaBag and frame.IsShown and frame:IsShown() then
				guarded(function()
					for _, button in ipairs(items(frame)) do button.stoaLink = nil end
				end)
			end
		end
		refreshShown()
	end)
end
