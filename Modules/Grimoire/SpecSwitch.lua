-- Stoa Grimoire: switch layout from the role word.
-- Clicking the role under Ready (Healer, Ranged DPS...) opens a small card
-- with STOA's four role layouts. Click one and this spec uses it from now
-- on (the same as Settings > Roles). Below them, the other talent spec:
-- click it to start the game's spec switch (a short cast). Built the
-- first time it's opened, so it costs nothing until then.
local _, ns = ...
local Stoa = ns.Stoa
local UI = Stoa.UI

local SpecSwitch = Stoa:NewModule("SpecSwitch", {
	enabled = true,
})

local WIDTH, ROW_H, SPEC_H, PAD = 260, 26, 40, 12

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
	return (chosen and chosen ~= "AUTO" and chosen) or Stoa:DefaultRole()
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

-- A row: a lamp, a name, a word at the right. Roles use one line; the
-- spec row adds its tree split under the name.
local function row(card, height)
	local button = CreateFrame("Button", nil, card)
	button:SetSize(WIDTH - PAD * 2, height)
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
	if height > ROW_H then name:SetPoint("TOPLEFT", 24, -5) else name:SetPoint("LEFT", 24, 0) end
	local state = UI.text(button, "sans", Stoa.typeSize.caption, "muted", "RIGHT")
	state:SetPoint("RIGHT", -8, 0)
	button.lit, button.dot, button.ring, button.name, button.state = lit, dot, ring, name, state
	return button
end

local function lamp(button, on)
	button.lit:SetShown(on)
	button.dot:SetShown(on)
	button.ring:SetShown(not on)
end

function SpecSwitch:Build()
	local card = CreateFrame("Frame", "StoaSpecCard", UIParent)
	card:SetFrameStrata("DIALOG")
	card:SetClampedToScreen(true)
	card:EnableMouse(true)
	card:Hide()
	UI.roundPanel(card, 0.98)
	card.heading = UI.caption(card, "Layout for this spec")
	card.heading:SetPoint("TOPLEFT", PAD, -PAD)
	-- The four role layouts.
	card.roles = {}
	local above = card.heading
	for i, role in ipairs(Stoa.ROLES) do
		local button = row(card, ROW_H)
		button:SetPoint("TOPLEFT", above, "BOTTOMLEFT", 0, i == 1 and -6 or -2)
		button.role = role
		button.name:SetText(Stoa.ROLE_LABELS[role])
		button:SetScript("OnClick", function(own)
			if own.active or InCombatLockdown() then return end
			Stoa:SetRoleForSlot(Stoa.ActiveSpecSlot(), own.role)
			self:Refresh()
		end)
		card.roles[i] = button
		above = button
	end
	-- The other talent spec, when there is one.
	local specHead = UI.caption(card, "Talent spec")
	specHead:SetPoint("TOPLEFT", above, "BOTTOMLEFT", 0, -12)
	local spec = row(card, SPEC_H)
	spec:SetPoint("TOPLEFT", specHead, "BOTTOMLEFT", 0, -6)
	local trees = UI.text(spec, "sans", Stoa.typeSize.caption, "muted")
	trees:SetPoint("TOPLEFT", spec.name, "BOTTOMLEFT", 0, -2)
	spec.trees = trees
	spec:SetScript("OnClick", function(own)
		if own.locked or InCombatLockdown() then return end
		local set = C_SpecializationInfo and C_SpecializationInfo.SetActiveSpecGroup or SetActiveTalentGroup
		if set then pcall(set, own.slot) end
		card:Hide()
	end)
	card.spec, card.specHead, card.lastRole = spec, specHead, above
	card.rule = UI.line(card)
	local rule = card.rule
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
	local current = roleFor(active)
	for _, button in ipairs(card.roles) do
		button.active = button.role == current
		lamp(button, button.active)
		button.state:SetText(button.active and "In use" or "")
	end
	-- The spec you're not in, with its layout and tree split. Before dual
	-- spec is learned (level 40) the card is the four layouts alone.
	local spec, other = card.spec, active == 1 and 2 or 1
	local dual = numGroups() > 1
	spec.slot, spec.locked = other, not dual
	spec:SetShown(dual)
	card.specHead:SetShown(dual)
	if dual then
		lamp(spec, false)
		local role = roleFor(other)
		spec.name:SetText(Stoa.ROLE_LABELS[role] or role)
		spec.trees:SetText(treeLine(other) or (other == 1 and "Primary" or "Secondary"))
		spec.state:SetText(InCombatLockdown() and "" or "Switch")
		UI.paint(spec.state, "accent")
	end
	local below = dual and spec or card.lastRole
	card.rule:ClearAllPoints()
	card.rule:SetPoint("TOPLEFT", below, "BOTTOMLEFT", 0, -8)
	card.rule:SetPoint("TOPRIGHT", below, "BOTTOMRIGHT", 0, -8)
	local height = PAD * 2 + 14 + 6 + #Stoa.ROLES * (ROW_H + 2) + 8 + 22
	if dual then height = height + 12 + 14 + 6 + SPEC_H end
	card:SetSize(WIDTH, height)
	card.note:SetText(InCombatLockdown() and "Not in combat" or "")
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
