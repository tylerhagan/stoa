-- Stoa Grimoire: switch spec from the role word.
-- Clicking the role under Ready (Healer, Ranged DPS...) opens a small card
-- with both talent specs: the role STOA uses for each and its tree split.
-- Click the other spec to start the game's spec switch (a short cast);
-- the console's role follows when it lands. Built the first time it's
-- opened, so it costs nothing until then.
local _, ns = ...
local Stoa = ns.Stoa
local UI = Stoa.UI

local SpecSwitch = Stoa:NewModule("SpecSwitch", {
	enabled = true,
})

local WIDTH, ROW_H, PAD = 260, 40, 12

local function call(fn, ...)
	if not fn then return nil end
	local ok, a = pcall(fn, ...)
	if ok then return a end
end

local function numGroups()
	return call(GetNumSpecGroups) or 1
end

local function roleFor(slot)
	local roles = Stoa.char and Stoa.char.roles
	local chosen = roles and roles["slot" .. slot]
	local role = (chosen and chosen ~= "AUTO" and chosen) or Stoa:DefaultRole()
	return Stoa.ROLE_LABELS[role] or role
end

-- "Shadow · 0 / 15 / 36": the tree with the most points, then each tree's
-- points in the game's order. Nil when the game can't say (no talents
-- loaded for that spec yet).
local function treeLine(slot)
	if not (C_SpecializationInfo and C_SpecializationInfo.GetCombatConfigIDForSpecGroup and C_Traits) then return nil end
	local configID = call(C_SpecializationInfo.GetCombatConfigIDForSpecGroup, slot)
	local config = configID and call(C_Traits.GetConfigInfo, configID)
	local treeID = config and config.treeIDs and config.treeIDs[1]
	local displays = treeID and call(C_Traits.GetGroupDisplayInfoByTreeID, treeID)
	if not (displays and #displays > 0) then return nil end
	local ids = {}
	for i, display in ipairs(displays) do ids[i] = display.groupID end
	local spent = {}
	for _, info in ipairs(call(C_Traits.GetGroupCurrencyInfo, configID, ids) or {}) do
		local currency = info.currencyInfos and info.currencyInfos[1]
		spent[info.traitNodeGroupID] = currency and Stoa:PlainNumber(currency.spent) or 0
	end
	local points, best, most = {}, nil, -1
	for i, display in ipairs(displays) do
		local n = spent[display.groupID] or 0
		points[i] = n
		if n > most then best, most = display.displayName, n end
	end
	if most <= 0 then return "No points spent" end
	return ("%s%s%s"):format(best or "", UI.SEP, table.concat(points, " / "))
end

local function row(card, index)
	local button = CreateFrame("Button", nil, card)
	button:SetSize(WIDTH - PAD * 2, ROW_H)
	button:SetPoint("TOPLEFT", card.heading, "BOTTOMLEFT", 0, -6 - (index - 1) * (ROW_H + 4))
	button:RegisterForClicks("LeftButtonUp")
	local lit = button:CreateTexture(nil, "BACKGROUND")
	lit:SetAllPoints()
	UI.paint(lit, "accent", 0.08)
	local hover = button:CreateTexture(nil, "HIGHLIGHT")
	hover:SetAllPoints()
	UI.paint(hover, "accent", 0.06)
	local dot = UI.circle(button, "ARTWORK", 0, 7, "accent")
	dot:SetPoint("LEFT", 8, 0)
	local ring = UI.circle(button, "ARTWORK", 1, 7, "muted", 0.4)
	ring:SetPoint("CENTER", dot)
	local name = UI.text(button, "serif", Stoa.typeSize.name, "text")
	name:SetPoint("TOPLEFT", 24, -5)
	local trees = UI.text(button, "sans", Stoa.typeSize.caption, "muted")
	trees:SetPoint("TOPLEFT", name, "BOTTOMLEFT", 0, -2)
	local state = UI.text(button, "sans", Stoa.typeSize.caption, "muted", "RIGHT")
	state:SetPoint("RIGHT", -8, 0)
	button.lit, button.dot, button.ring, button.name, button.trees, button.state = lit, dot, ring, name, trees, state
	button:SetScript("OnClick", function(own)
		if own.active or own.locked or InCombatLockdown() then return end
		local set = C_SpecializationInfo and C_SpecializationInfo.SetActiveSpecGroup or SetActiveTalentGroup
		if set then pcall(set, own.slot) end
		card:Hide()
	end)
	return button
end

function SpecSwitch:Build()
	local card = CreateFrame("Frame", "StoaSpecCard", UIParent)
	card:SetSize(WIDTH, PAD * 2 + 20 + (ROW_H + 4) * 2 + 26)
	card:SetFrameStrata("DIALOG")
	card:SetClampedToScreen(true)
	card:EnableMouse(true)
	card:Hide()
	UI.roundPanel(card, 0.98)
	card.heading = UI.caption(card, "Specs")
	card.heading:SetPoint("TOPLEFT", PAD, -PAD)
	card.rows = { row(card, 1), row(card, 2) }
	local rule = UI.line(card)
	rule:SetPoint("TOPLEFT", card.rows[2], "BOTTOMLEFT", 0, -8)
	rule:SetPoint("TOPRIGHT", card.rows[2], "BOTTOMRIGHT", 0, -8)
	-- "Open talents": the words, with a secure button over them (placed in
	-- Toggle) that clicks the game's own talent button. Opening the talent
	-- window from STOA's code would taint it.
	local talents = CreateFrame("Frame", nil, card)
	talents:SetSize(90, 16)
	talents:SetPoint("TOPLEFT", rule, "BOTTOMLEFT", 0, -5)
	local words = UI.text(talents, "sans", Stoa.typeSize.caption, "accent")
	words:SetPoint("LEFT")
	words:SetText("Open talents")
	card.talents = talents
	card.note = UI.text(card, "sans", Stoa.typeSize.caption, "muted", "RIGHT")
	card.note:SetPoint("TOPRIGHT", rule, "BOTTOMRIGHT", 0, -6)
	-- Esc closes it; so does a click anywhere else.
	table.insert(UISpecialFrames, "StoaSpecCard")
	card:SetScript("OnShow", function(own) own:RegisterEvent("GLOBAL_MOUSE_DOWN") end)
	card:SetScript("OnHide", function(own)
		own:UnregisterEvent("GLOBAL_MOUSE_DOWN")
		local proxy = self.proxy
		if proxy and not InCombatLockdown() then proxy:Hide() end
	end)
	card:SetScript("OnEvent", function(own)
		if own:IsMouseOver() or (own.owner and own.owner:IsMouseOver()) then return end
		if self.proxy and self.proxy:IsMouseOver() then return end
		own:Hide()
	end)
	UI.riseOnShow(card)
	self.card = card
	return card
end

function SpecSwitch:Refresh()
	local card = self.card
	if not card then return end
	local active = Stoa.ActiveSpecSlot()
	local groups = numGroups()
	local fighting = InCombatLockdown()
	for slot, button in ipairs(card.rows) do
		local locked = slot > groups
		button.slot, button.active, button.locked = slot, slot == active, locked
		button.name:SetText(locked and "Second spec" or roleFor(slot))
		button.trees:SetText(locked and "Not learned yet" or (treeLine(slot) or (slot == 1 and "Primary" or "Secondary")))
		button.state:SetText(button.active and "Active" or (locked or fighting) and "" or "Switch")
		UI.paint(button.state, button.active and "muted" or "accent")
		button.lit:SetShown(button.active)
		button.dot:SetShown(button.active)
		button.ring:SetShown(not button.active)
		button:SetAlpha(locked and 0.5 or 1)
	end
	card.note:SetText(fighting and "Not in combat" or "Short cast")
end

-- The secure button over "Open talents". A secure frame can't hang from
-- STOA's own frames, so it goes over the words by screen position.
function SpecSwitch:Proxy()
	if self.proxy ~= nil then return self.proxy or nil end
	local micro = _G.PlayerSpellsMicroButton or _G.TalentMicroButton
	if not micro then self.proxy = false return nil end
	local ok, proxy = pcall(CreateFrame, "Button", "StoaSpecTalents", UIParent, "SecureActionButtonTemplate")
	if not ok or not proxy then self.proxy = false return nil end
	-- Press and release both, as the game acts on either (ActionButtonUseKeyDown).
	proxy:RegisterForClicks("AnyUp", "AnyDown")
	proxy:SetAttribute("type1", "click")
	proxy:SetAttribute("clickbutton1", micro)
	proxy:HookScript("OnClick", function(_, _, down)
		if not down and self.card then self.card:Hide() end
	end)
	proxy:RegisterEvent("PLAYER_REGEN_DISABLED")
	proxy:SetScript("OnEvent", function(button) button:Hide() end)
	proxy:Hide()
	self.proxy = proxy
	return proxy
end

function SpecSwitch:PlaceProxy()
	local proxy, words = self:Proxy(), self.card and self.card.talents
	if not (proxy and words) or InCombatLockdown() then return end
	local left, bottom, width, height = words:GetRect()
	if not left then return end
	local ratio = words:GetEffectiveScale() / UIParent:GetEffectiveScale()
	proxy:ClearAllPoints()
	proxy:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", left * ratio, bottom * ratio)
	proxy:SetSize(width * ratio, height * ratio)
	proxy:SetFrameStrata("DIALOG")
	proxy:SetFrameLevel(self.card:GetFrameLevel() + 10)
	proxy:Show()
end

-- Open under (above, on the console) the word that was clicked; a second
-- click closes it.
function SpecSwitch:Toggle(owner)
	local card = self.card or self:Build()
	if card:IsShown() then card:Hide() return end
	card.owner = owner
	card:ClearAllPoints()
	card:SetPoint("BOTTOMLEFT", owner, "TOPLEFT", -PAD, 8)
	self:Refresh()
	card:Show()
	-- Placed a frame later, once the card has its spot on the screen.
	C_Timer.After(0, function() if card:IsShown() then self:PlaceProxy() end end)
end

Stoa:On("ACTIVE_TALENT_GROUP_CHANGED", function() SpecSwitch:Refresh() end)
Stoa:On("PLAYER_REGEN_DISABLED", function() if SpecSwitch.card then SpecSwitch.card:Hide() end end)
