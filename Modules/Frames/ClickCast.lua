-- Stoa: click-casting on Stoa's unit frames.
-- Five mouse buttons (left, right, wheel click, two thumb buttons) with no
-- modifier, Shift or Ctrl give fifteen bindings per role. Alt is left free
-- for peeking at the console. A binding is a spell name, "target" or "menu".
--
-- Bindings are plain secure attributes, so no secure code runs. They can
-- only be changed out of combat; a change made in combat waits for it to end.
local _, ns = ...
local Stoa = ns.Stoa
local UI = Stoa.UI

local ClickCast = Stoa:NewModule("ClickCast")

ClickCast.BUTTONS = {
	{ id = "1", label = "Left" },
	{ id = "2", label = "Right" },
	{ id = "3", label = "Wheel click" },
	{ id = "4", label = "Thumb back" },
	{ id = "5", label = "Thumb forward" },
}
ClickCast.MODIFIERS = {
	{ prefix = "", label = "Click" },
	{ prefix = "shift-", label = "Shift" },
	{ prefix = "ctrl-", label = "Ctrl" },
}

-- Starting bindings. Spell names a character hasn't learned simply do
-- nothing until it has.
local BASE = { ["1"] = "target", ["2"] = "menu" }

local DEFAULTS = {
	PRIEST = {
		HEALER = {
			["3"] = "Flash Heal", ["4"] = "Dispel Magic", ["5"] = "Cure Disease",
			["shift-1"] = "Power Word: Shield", ["shift-2"] = "Renew", ["shift-3"] = "Heal",
			["shift-4"] = "Power Infusion", ["shift-5"] = "Prayer of Mending",
			["ctrl-1"] = "Lesser Heal", ["ctrl-2"] = "Resurrection", ["ctrl-3"] = "Greater Heal",
			["ctrl-4"] = "Fear Ward", ["ctrl-5"] = "Power Word: Fortitude",
		},
		OTHER = {
			["3"] = "Flash Heal", ["4"] = "Dispel Magic",
			["shift-1"] = "Power Word: Shield", ["shift-2"] = "Renew",
			["ctrl-2"] = "Resurrection", ["ctrl-5"] = "Power Word: Fortitude",
		},
	},
	PALADIN = {
		OTHER = {
			["3"] = "Flash of Light", ["4"] = "Cleanse", ["5"] = "Lay on Hands",
			["shift-1"] = "Holy Light", ["shift-2"] = "Blessing of Protection",
			["shift-3"] = "Blessing of Freedom", ["shift-4"] = "Purify",
			["ctrl-1"] = "Blessing of Might", ["ctrl-2"] = "Redemption", ["ctrl-3"] = "Blessing of Kings",
			["ctrl-4"] = "Blessing of Wisdom", ["ctrl-5"] = "Divine Intervention",
		},
	},
}

local frames = {}
local pending = false

function ClickCast:DefaultsFor(role)
	local _, classFile = UnitClass("player")
	local class = DEFAULTS[classFile] or {}
	local bindings = {}
	for key, action in pairs(BASE) do bindings[key] = action end
	for key, action in pairs(class[role] or class.OTHER or {}) do bindings[key] = action end
	return bindings
end

-- The bindings for the current role, created from defaults the first time.
function ClickCast:Bindings(role)
	role = role or Stoa:GetRole() or "OTHER"
	local clicks = Stoa.char.clicks
	if not clicks[role] then
		clicks[role] = self:DefaultsFor(role)
	end
	return clicks[role]
end

local function applyTo(frame, bindings)
	for _, button in ipairs(ClickCast.BUTTONS) do
		for _, modifier in ipairs(ClickCast.MODIFIERS) do
			local key = modifier.prefix .. button.id
			local action = bindings[key]
			local typeAttr = modifier.prefix .. "type" .. button.id
			local spellAttr = modifier.prefix .. "spell" .. button.id
			if action == "target" then
				frame:SetAttribute(typeAttr, "target")
				frame:SetAttribute(spellAttr, nil)
			elseif action == "menu" then
				frame:SetAttribute(typeAttr, "togglemenu")
				frame:SetAttribute(spellAttr, nil)
			elseif action and action ~= "" then
				frame:SetAttribute(typeAttr, "spell")
				frame:SetAttribute(spellAttr, action)
			else
				frame:SetAttribute(typeAttr, nil)
				frame:SetAttribute(spellAttr, nil)
			end
		end
	end
end

-- Applies the current bindings to every registered frame, now or as soon
-- as combat ends.
function ClickCast:Apply()
	if pending then return end
	pending = true
	Stoa:AfterCombat(function()
		pending = false
		-- Until the role is known at login there is nothing to apply;
		-- STOA_ROLE_CHANGED brings us back.
		if not Stoa:GetRole() then return end
		local bindings = self:Bindings()
		for frame in pairs(frames) do
			applyTo(frame, bindings)
		end
		Stoa:Fire("STOA_CLICKS_CHANGED")
	end)
end

-- Unit frames call this once for each secure unit button they make.
-- The raid header can make cells in combat, so everything here waits for
-- combat to end.
function Stoa:RegisterClickFrame(frame)
	Stoa:AfterCombat(function()
		frame:RegisterForClicks("AnyUp")
		frames[frame] = true
		if Stoa:IsModuleEnabled("ClickCast") then
			ClickCast:Apply()
		end
	end)
end

-- Binding page --------------------------------------------------------------
-- A small Stoa-styled page: one row per mouse button, one column per
-- modifier. Type a spell name, or drag a spell from the spellbook onto a
-- field. "target" and "menu" also work; empty means nothing.

local function spellFromCursor()
	local kind, _, _, spellID = GetCursorInfo()
	if kind ~= "spell" then return nil end
	local name = spellID and C_Spell.GetSpellName and C_Spell.GetSpellName(spellID)
	ClearCursor()
	return name
end

function ClickCast:BuildPage()
	local page = CreateFrame("Frame", "StoaClickCastPage", UIParent)
	page:SetSize(720, 380)
	page:SetPoint("CENTER")
	page:SetFrameStrata("DIALOG")
	page:EnableMouse(true)
	page:SetMovable(true)
	page:RegisterForDrag("LeftButton")
	page:SetScript("OnDragStart", page.StartMoving)
	page:SetScript("OnDragStop", page.StopMovingOrSizing)
	page:Hide()
	table.insert(UISpecialFrames, "StoaClickCastPage")
	self.page = page

	local bg = page:CreateTexture(nil, "BACKGROUND")
	bg:SetAllPoints()
	UI.paint(bg, "panel", 0.97)
	local top = UI.line(page, "accent")
	top:SetPoint("TOPLEFT")
	top:SetPoint("TOPRIGHT")

	local title = UI.text(page, "serif", Stoa.typeSize.display, "text")
	title:SetPoint("TOPLEFT", 28, -22)
	self.title = title
	local hint = UI.text(page, "italic", Stoa.typeSize.label, "muted")
	hint:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -4)
	hint:SetText("Type a spell, or drag one from your spellbook. \"target\" and \"menu\" work too.")

	local close = CreateFrame("Button", nil, page, "UIPanelCloseButton")
	close:SetPoint("TOPRIGHT", -4, -4)

	local columnX = { 170, 350, 530 }
	for i, modifier in ipairs(self.MODIFIERS) do
		local heading = UI.caption(page, modifier.label)
		heading:SetPoint("TOPLEFT", columnX[i], -100)
	end

	self.fields = {}
	for row, button in ipairs(self.BUTTONS) do
		local y = -124 - (row - 1) * 38
		local label = UI.text(page, "serif", Stoa.typeSize.label, "text")
		label:SetPoint("TOPLEFT", 28, y - 6)
		label:SetText(button.label)
		for i, modifier in ipairs(self.MODIFIERS) do
			local key = modifier.prefix .. button.id
			local field = CreateFrame("EditBox", nil, page)
			field:SetSize(164, 26)
			field:SetPoint("TOPLEFT", columnX[i], y)
			field:SetAutoFocus(false)
			field:SetTextInsets(6, 6, 0, 0)
			Stoa:SetFont(field, "sans", Stoa.typeSize.body)
			field:SetTextColor(Stoa:Color("text"))
			local fieldBg = field:CreateTexture(nil, "BACKGROUND")
			fieldBg:SetAllPoints()
			UI.paint(fieldBg, "text", 0.06)
			local underline = UI.line(field)
			underline:SetPoint("BOTTOMLEFT")
			underline:SetPoint("BOTTOMRIGHT")

			local function save()
				local value = strtrim(field:GetText() or "")
				self:Bindings()[key] = value ~= "" and value or nil
				self:Apply()
			end
			field:SetScript("OnEnterPressed", function(box) save(); box:ClearFocus() end)
			field:SetScript("OnEditFocusLost", save)
			field:SetScript("OnEscapePressed", function(box) box:ClearFocus() end)
			local function drop()
				local name = spellFromCursor()
				if name then
					field:SetText(name)
					save()
				end
			end
			field:SetScript("OnReceiveDrag", drop)
			field:SetScript("OnMouseUp", drop)
			self.fields[key] = field
		end
	end

	local reset = CreateFrame("Button", nil, page, "UIPanelButtonTemplate")
	reset:SetSize(150, 24)
	reset:SetPoint("BOTTOMLEFT", 28, 20)
	reset:SetText("Reset to defaults")
	reset:SetScript("OnClick", function()
		local role = Stoa:GetRole() or "OTHER"
		Stoa.char.clicks[role] = self:DefaultsFor(role)
		self:Refresh()
		self:Apply()
	end)

	local note = UI.text(page, "italic", Stoa.typeSize.body, "muted", "RIGHT")
	note:SetPoint("BOTTOMRIGHT", -28, 26)
	note:SetText("Saved for this character and role. Changes made in combat apply when it ends.")

	UI.applyTheme()
end

function ClickCast:Refresh()
	local role = Stoa:GetRole()
	self.title:SetText("Clicks · " .. (role and Stoa.ROLE_LABELS[role] or "Any role"))
	local bindings = self:Bindings()
	for key, field in pairs(self.fields) do
		field:SetText(bindings[key] or "")
		field:SetCursorPosition(0)
	end
end

function ClickCast:TogglePage()
	if not self.page then self:BuildPage() end
	if self.page:IsShown() then
		self.page:Hide()
	else
		self:Refresh()
		self.page:Show()
	end
end

function ClickCast:OnEnable()
	Stoa.commands.clicks = function() self:TogglePage() end
	Stoa.commands.bind = Stoa.commands.clicks
	Stoa:On("STOA_ROLE_CHANGED", function()
		self:Apply()
		if self.page and self.page:IsShown() then self:Refresh() end
	end)
	self:Apply()
end
