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
local UI = Stoa.UI

local Bags = Stoa:NewModule("Bags", { bagMode = "combined" })

local function guarded(fn, ...)
	xpcall(fn, geterrorhandler(), ...)
end

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
function Item.itemLevel(link)
	if not link or Stoa:IsSecret(link) then return nil end
	local equippable
	if C_Item and C_Item.IsEquippableItem then
		equippable = C_Item.IsEquippableItem(link)
	elseif IsEquippableItem then
		equippable = IsEquippableItem(link)
	end
	if not equippable then return nil end
	local level
	if C_Item and C_Item.GetDetailedItemLevelInfo then
		level = C_Item.GetDetailedItemLevelInfo(link)
	elseif GetDetailedItemLevelInfo then
		level = GetDetailedItemLevelInfo(link)
	end
	level = Stoa:PlainNumber(level)
	if level and level > 1 then return math.floor(level + 0.5) end
end

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
		if button.IconMask then pcall(icon.RemoveMaskTexture, icon, button.IconMask) end
		icon:AddMaskTexture(mask)
		for _, getter in ipairs({ "GetHighlightTexture", "GetPushedTexture" }) do
			local tex = button[getter] and button[getter](button)
			if tex then pcall(tex.AddMaskTexture, tex, mask) end
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

local function decorateButton(button)
	local bag, slot = bagIDOf(button), button.GetID and button:GetID()
	local info = bag and slot and C_Container and C_Container.GetContainerItemInfo and C_Container.GetContainerItemInfo(bag, slot)
	if not info then
		button.stoaLink = nil
		Item.markSlot(button, 0, nil)
		return
	end
	local link = info.hyperlink
	-- Reading the level costs a lookup, so an unchanged slot is left alone.
	if button.stoaLink ~= link or button.stoaQuality ~= info.quality then
		button.stoaLink, button.stoaQuality = link, info.quality
		button.stoaLevel = Item.itemLevel(link)
	end
	Item.markSlot(button, info.quality, button.stoaLevel)
end

-- Gold, silver and copper as letters, so nothing rests on coin colour.
local function moneyWords(copper)
	copper = Stoa:PlainNumber(copper) or 0
	local gold = math.floor(copper / 10000)
	local silver = math.floor(copper / 100) % 100
	local rest = copper % 100
	local out = {}
	if gold > 0 then out[#out + 1] = (BreakUpLargeNumbers and BreakUpLargeNumbers(gold) or gold) .. "g" end
	if silver > 0 or gold > 0 then out[#out + 1] = silver .. "s" end
	out[#out + 1] = rest .. "c"
	return table.concat(out, " ")
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

local function updateFooter(frame)
	local parts = frame.stoaBag
	if not parts then return end
	local free, size = freeSlots(frame)
	if free then
		local text = size and (free .. " of " .. size .. " free") or (free .. " free")
		parts.free:SetText(text)
		-- Full is said in words as well as the warm colour.
		if free == 0 then
			parts.free:SetText("FULL")
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
end

local function decorateFrame(frame)
	if not frame or not frame.stoaBag then return end
	for _, button in ipairs(items(frame)) do guarded(decorateButton, button) end
	updateFooter(frame)
end

function Bags:Dress(frame)
	if not frame or frame.stoaBag then return end
	local parts = {}
	frame.stoaBag = parts
	-- The common Stoa window: panel, title, close cross, no stone border.
	local windows = Stoa.modules.Windows
	if windows and windows.Dress then guarded(windows.Dress, windows, frame) end

	parts.free = UI.text(frame, "sans", Stoa.typeSize.caption + 1, "muted")
	parts.free:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 14, 10)
	parts.money = UI.text(frame, "sans", Stoa.typeSize.body, "text", "RIGHT")
	parts.money:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -14, 10)
	-- Blizzard's coin display steps aside only now that ours exists.
	if frame.MoneyFrame and frame.MoneyFrame.SetAlpha then frame.MoneyFrame:SetAlpha(0) end
	addSort(frame, parts)

	-- Update hooks: after Blizzard refreshes the item buttons, and when the
	-- window opens.
	if frame.UpdateItems then
		hooksecurefunc(frame, "UpdateItems", function() guarded(decorateFrame, frame) end)
	end
	frame:HookScript("OnShow", function() guarded(decorateFrame, frame) end)
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
	if SetCVar then
		guarded(SetCVar, "combinedBags", want)
		self.db.appliedMode = self.db.bagMode
	end
end

function Bags:OnEnable()
	guarded(function() self:ApplyMode() end)
	for _, frame in ipairs(allFrames()) do
		if frame then guarded(self.Dress, self, frame) end
	end
	Stoa:On("BAG_UPDATE_DELAYED", refreshShown)
	Stoa:On("PLAYER_MONEY", refreshShown)
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
