-- Stoa QoL: hover keybinding. /stoa bind (or the button in settings), then
-- hover any action, pet or stance button and press a key, a mouse button or
-- the wheel, with any modifier. Backspace clears the button's keys; Esc or
-- Done keeps the changes, Discard puts them all back. Out of combat only: a
-- fight starting keeps what you've done and ends it.
local _, ns = ...
local Stoa = ns.Stoa
local UI = Stoa.UI

local Bind = Stoa:NewModule("Bind", {})

-- Each bar's buttons and the binding they answer to, for buttons that
-- don't say themselves (button.bindingAction / commandName).
local BARS = {
	{ "ActionButton", "ACTIONBUTTON", 12 },
	{ "MultiBarBottomLeftButton", "MULTIACTIONBAR1BUTTON", 12 },
	{ "MultiBarBottomRightButton", "MULTIACTIONBAR2BUTTON", 12 },
	{ "MultiBarRightButton", "MULTIACTIONBAR3BUTTON", 12 },
	{ "MultiBarLeftButton", "MULTIACTIONBAR4BUTTON", 12 },
	{ "MultiBar5Button", "MULTIACTIONBAR5BUTTON", 12 },
	{ "MultiBar6Button", "MULTIACTIONBAR6BUTTON", 12 },
	{ "MultiBar7Button", "MULTIACTIONBAR7BUTTON", 12 },
	{ "PetActionButton", "BONUSACTIONBUTTON", 10 },
	{ "StanceButton", "SHAPESHIFTBUTTON", 10 },
}

-- Keys that only modify, and mouse buttons that click as usual.
local IGNORE = {
	LSHIFT = true, RSHIFT = true, LCTRL = true, RCTRL = true, LALT = true, RALT = true,
	LMETA = true, RMETA = true, UNKNOWN = true, LeftButton = true, RightButton = true,
}
local MOUSE = { MiddleButton = "BUTTON3", Button4 = "BUTTON4", Button5 = "BUTTON5" }

local function command(button)
	return button.bindingAction or button.commandName or button.stoaBindCommand
end

local function withModifiers(key)
	local out = ""
	if IsAltKeyDown() then out = out .. "ALT-" end
	if IsControlKeyDown() then out = out .. "CTRL-" end
	if IsShiftKeyDown() then out = out .. "SHIFT-" end
	return out .. key
end

local function keysOf(action)
	return { GetBindingKey(action) }
end

local function keyLabel(key)
	return GetBindingText and GetBindingText(key) or key
end

function Bind:Buttons()
	if self.buttons then return self.buttons end
	local list = {}
	for _, bar in ipairs(BARS) do
		for i = 1, bar[3] do
			local button = _G[bar[1] .. i]
			if button then
				if not command(button) then button.stoaBindCommand = bar[2] .. i end
				list[#list + 1] = button
			end
		end
	end
	self.buttons = list
	return list
end

function Bind:Tooltip()
	local button = self.over
	if not button then return end
	GameTooltip:SetOwner(self.catcher, "ANCHOR_TOP")
	local action = command(button)
	local name = GetBindingName and GetBindingName(action) or action
	GameTooltip:AddLine(name, Stoa:Color("text"))
	local keys = keysOf(action)
	if #keys == 0 then
		GameTooltip:AddLine("No key yet. Press one.", 0.7, 0.7, 0.7)
	else
		local labels = {}
		for _, key in ipairs(keys) do labels[#labels + 1] = keyLabel(key) end
		GameTooltip:AddLine(table.concat(labels, ", "), 1, 1, 1)
		GameTooltip:AddLine("Backspace clears.", 0.7, 0.7, 0.7)
	end
	GameTooltip:Show()
end

function Bind:Press(key)
	if not self.over or IGNORE[key] then return end
	if key == "ESCAPE" then return self:Stop(true) end
	local action = command(self.over)
	if key == "BACKSPACE" or key == "DELETE" then
		for _, old in ipairs(keysOf(action)) do SetBinding(old) end
		self.changed = true
		Stoa:Note("bind", (GetBindingName and GetBindingName(action) or action) .. " has no key now.")
	else
		key = withModifiers(key)
		-- One key, one button: taking it from wherever it was.
		local before = GetBindingAction(key)
		if SetBinding(key, action) then
			self.changed = true
			if before and before ~= "" and before ~= action then
				Stoa:Note("bind", ("%s moved here from %s."):format(keyLabel(key), GetBindingName and GetBindingName(before) or before))
			end
		end
	end
	self:Tooltip()
end

function Bind:BuildCatcher()
	local catcher = CreateFrame("Button", "StoaBindCatcher", UIParent)
	catcher:SetFrameStrata("DIALOG")
	catcher:EnableMouse(true)
	catcher:EnableKeyboard(true)
	catcher:EnableMouseWheel(true)
	catcher:RegisterForClicks("AnyUp")
	local glow = catcher:CreateTexture(nil, "OVERLAY")
	glow:SetAllPoints()
	UI.paint(glow, "accent", 0.25)
	catcher:SetScript("OnKeyDown", function(_, key) self:Press(key) end)
	catcher:SetScript("OnMouseUp", function(_, button) if MOUSE[button] then self:Press(MOUSE[button]) end end)
	catcher:SetScript("OnMouseWheel", function(_, delta) self:Press(delta > 0 and "MOUSEWHEELUP" or "MOUSEWHEELDOWN") end)
	catcher:SetScript("OnLeave", function()
		catcher:Hide()
		self.over = nil
		GameTooltip:Hide()
	end)
	catcher:Hide()
	self.catcher = catcher
end

function Bind:BuildBar()
	local bar = CreateFrame("Frame", "StoaBindBar", UIParent)
	bar:SetSize(420, 96)
	bar:SetPoint("TOP", 0, -120)
	bar:SetFrameStrata("DIALOG")
	bar:EnableMouse(true)
	-- Esc closes it like any window, which finishes and keeps the keys.
	table.insert(UISpecialFrames, "StoaBindBar")
	bar:SetScript("OnHide", function() self:Stop(true) end)
	UI.windowPanel(bar, 0.97, { header = 40, footer = 0 })
	local title = UI.text(bar, "serif", Stoa.typeSize.title, "text", "LEFT")
	title:SetPoint("TOPLEFT", 16, -12)
	title:SetText("Keybinding")
	local lede = UI.text(bar, "sans", Stoa.typeSize.caption + 1, "muted", "LEFT")
	lede:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -10)
	lede:SetWidth(390)
	lede:SetText("Hover a button and press a key, mouse button or wheel. Backspace clears. Esc finishes.")
	local done = UI.button(bar, "Done", 80, function() self:Stop(true) end)
	done:SetPoint("TOPRIGHT", -12, -10)
	local discard = UI.button(bar, "Discard", 80, function() self:Stop(false) end)
	discard:SetPoint("RIGHT", done, "LEFT", -8, 0)
	bar:Hide()
	self.bar = bar
end

function Bind:Start()
	if InCombatLockdown() then
		Stoa:Print("Keybinding waits until the fight is over.")
		return
	end
	if not self.catcher then
		self:BuildCatcher()
		self:BuildBar()
	end
	if not self.hooked then
		self.hooked = true
		for _, button in ipairs(self:Buttons()) do
			button:HookScript("OnEnter", function(b)
				if not self.active or InCombatLockdown() then return end
				self.over = b
				self.catcher:ClearAllPoints()
				self.catcher:SetAllPoints(b)
				self.catcher:Show()
				self:Tooltip()
			end)
		end
	end
	self.active, self.changed = true, false
	self.bar:Show()
	if ActionButtonUtil and ActionButtonUtil.ShowAllActionButtonGrids then pcall(ActionButtonUtil.ShowAllActionButtonGrids) end
	Stoa:Fire("STOA_BINDING", true)
end

function Bind:Stop(keep)
	if not self.active then return end
	self.active = false
	self.catcher:Hide()
	self.bar:Hide()
	GameTooltip:Hide()
	if ActionButtonUtil and ActionButtonUtil.HideAllActionButtonGrids then pcall(ActionButtonUtil.HideAllActionButtonGrids) end
	local set = GetCurrentBindingSet and GetCurrentBindingSet() or 1
	if keep then
		if self.changed then
			SaveBindings(set)
			Stoa:Note("bind", "Keys saved.")
		end
	elseif self.changed then
		LoadBindings(set)
		Stoa:Note("bind", "Keys put back as they were.")
	end
	Stoa:Fire("STOA_BINDING", false)
end

function Bind:Toggle()
	if self.active then self:Stop(true) else self:Start() end
end

function Bind:OnEnable()
	Stoa:On("PLAYER_REGEN_DISABLED", function() self:Stop(true) end)
end

Stoa.commands.bind = function() Bind:Toggle() end
Stoa.commands.kb = Stoa.commands.bind
