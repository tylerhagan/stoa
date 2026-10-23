-- Stoa: quiet, rounded action buttons.
-- Blizzard's own buttons keep doing the work; Stoa only redraws them. The
-- square slot art goes, icons get the party cards' rounded corners inside a
-- hairline edge, and an empty slot is a dim socket. Key labels and counts
-- use Stoa's type.
--
-- Only textures and fonts change, which is allowed on secure buttons; it
-- all happens out of combat at load.
local _, ns = ...
local Stoa = ns.Stoa
local UI = Stoa.UI

local Bars = Stoa:NewModule("ActionBars", { tray = true, combatHide = true })

local PREFIXES = {
	"ActionButton", "MultiBarBottomLeftButton", "MultiBarBottomRightButton",
	"MultiBarRightButton", "MultiBarLeftButton", "MultiBar5Button",
	"MultiBar6Button", "MultiBar7Button", "PetActionButton", "StanceButton",
}
local HIDDEN_ART = { "SlotArt", "SlotBackground", "Border", "FloatingBG", "NormalTexture" }

local function hideSquareArt(button)
	for _, key in ipairs(HIDDEN_ART) do
		local art = button[key]
		if art and art.SetAlpha then art:SetAlpha(0) end
	end
	local normal = button.GetNormalTexture and button:GetNormalTexture()
	if normal then normal:SetAlpha(0) end
end

local MASK = UI.MEDIA .. "Textures\\ButtonMask"

-- Swaps Blizzard's icon mask for Stoa's rounded square.
local function roundMask(button, icon)
	local mask = button:CreateMaskTexture()
	mask:SetAllPoints()
	mask:SetTexture(MASK, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
	if icon then
		if button.IconMask then pcall(icon.RemoveMaskTexture, icon, button.IconMask) end
		icon:AddMaskTexture(mask)
	end
	return mask
end

function Bars:Skin(button)
	if not button or button.stoaRound then return end
	button.stoaRound = true
	hideSquareArt(button)

	local icon = button.icon or button.Icon
	if icon then icon:SetTexCoord(0.07, 0.93, 0.07, 0.93) end
	local mask = roundMask(button, icon)

	-- Highlight, pressed and checked states follow the rounded shape.
	for _, getter in ipairs({ "GetHighlightTexture", "GetPushedTexture", "GetCheckedTexture" }) do
		local tex = button[getter] and button[getter](button)
		if tex then pcall(tex.AddMaskTexture, tex, mask) end
	end

	-- The socket: a dark rounded square with a hairline edge, seen through
	-- an empty slot and framing a full one.
	UI.roundPanel(button, 0.9)

	local cooldown = button.cooldown or button.Cooldown
	if cooldown and cooldown.SetSwipeTexture then cooldown:SetSwipeTexture(MASK) end

	local hotkey = button.HotKey
	if hotkey then
		Stoa:SetFont(hotkey, "sans", Stoa.typeSize.caption - 1, "OUTLINE")
		hotkey:SetTextColor(Stoa:Color("muted"))
	end
	local count = button.Count
	if count then Stoa:SetFont(count, "sans", Stoa.typeSize.body, "OUTLINE") end
	local macro = button.Name
	if macro then macro:SetAlpha(0) end

	-- Blizzard redraws the slot art when a button's contents change.
	if button.UpdateButtonArt then
		hooksecurefunc(button, "UpdateButtonArt", hideSquareArt)
	end
	if button.Update then
		hooksecurefunc(button, "Update", hideSquareArt)
	end
	UI.applyTheme()
end

function Bars:SkinAll()
	for _, prefix in ipairs(PREFIXES) do
		for i = 1, 12 do
			local button = _G[prefix .. i]
			if button then xpcall(self.Skin, geterrorhandler(), self, button) end
		end
	end
end

-- Tray ----------------------------------------------------------------------
-- Out of combat only your main bar shows in the console; the other rows
-- that sit in it rest hidden and come up while the mouse is over the bar
-- area, while a spell or item is on the cursor (to place it), and in Edit
-- Mode. In combat the Halo's combat bar takes over and the console's rows,
-- main bar included, step aside; your keys still reach them. Without the
-- combat bar, combat brings every row up at once.
--
-- Only alpha changes, which is allowed on secure bars at any time. Which
-- rows count as the tray is worked out from where they sit, out of combat.

local TRAY_BARS = {
	"MultiBarBottomLeft", "MultiBarBottomRight", "MultiBarRight", "MultiBarLeft",
	"MultiBar5", "MultiBar6", "MultiBar7", "PetActionBar", "StanceBar",
}
local MAIN_BARS = { "MainActionBar", "MainMenuBar" }
local TRAY_FADE_IN, TRAY_FADE_OUT = 0.12, 0.4

-- The height under which a bar counts as part of the console.
local function consoleTop()
	local console = Stoa.modules.Grimoire
	if console and console.enabled and console.OpenHeight then
		return console:OpenHeight() + 8
	end
	return UIParent:GetHeight() * 0.22
end

-- Where a bar's middle sits, so a tall side bar that merely reaches down
-- to the console doesn't count as part of it.
local function middleOf(frame)
	local _, middle = frame:GetCenter()
	if not middle then return nil end
	return middle * frame:GetEffectiveScale() / UIParent:GetEffectiveScale()
end

function Bars:FindTray()
	local top = consoleTop()
	local tray, area = {}, {}
	for _, name in ipairs(TRAY_BARS) do
		local bar = _G[name]
		local middle = bar and bar:IsShown() and middleOf(bar)
		if middle and middle < top then
			table.insert(tray, bar)
			table.insert(area, bar)
		elseif bar and self.tray then
			-- No longer in the console: give it back its full alpha.
			for _, old in ipairs(self.tray) do
				if old == bar then bar:SetAlpha(1) end
			end
		end
	end
	local main
	for _, name in ipairs(MAIN_BARS) do
		if _G[name] then main = _G[name] break end
	end
	if main then table.insert(area, main) end
	self.tray, self.trayArea, self.main = tray, area, main
	self.trayLit = nil
	self:UpdateTray()
end

-- One fader for the whole tray, kept off Blizzard's own frames.
local trayFader = CreateFrame("Frame")
local function fadeTray(bars, targets, seconds)
	local from, start = {}, GetTime()
	for i, bar in ipairs(bars) do from[i] = bar:GetAlpha() end
	trayFader:SetScript("OnUpdate", function(fader)
		local progress = math.min((GetTime() - start) / seconds, 1)
		for i, bar in ipairs(bars) do
			bar:SetAlpha(from[i] + (targets[i] - from[i]) * progress)
		end
		if progress >= 1 then fader:SetScript("OnUpdate", nil) end
	end)
end

local function inCombat()
	return InCombatLockdown() or Stoa:GetState() == Stoa.STATE_COMBAT
end

-- In combat the Halo's own bar takes over, when there is one.
local function handedToHalo(self)
	if not self.db.combatHide or not inCombat() then return false end
	local combatBar = Stoa.modules.CombatBar
	return combatBar and combatBar.enabled and combatBar.shown and #combatBar.shown > 0
end

local function trayWanted(self)
	if not self.db.tray then return true end
	if inCombat() then return true end
	if GetCursorInfo() then return true end
	if EditModeManagerFrame and EditModeManagerFrame:IsShown() then return true end
	for _, name in ipairs({ "SpellBookFrame", "PlayerSpellsFrame" }) do
		if _G[name] and _G[name]:IsShown() then return true end
	end
	for _, bar in ipairs(self.trayArea or {}) do
		if bar:IsVisible() and bar:IsMouseOver() then return true end
	end
	return false
end

function Bars:UpdateTray()
	if not self.tray then return end
	local halo = handedToHalo(self)
	local lit = not halo and trayWanted(self)
	local state = halo and "halo" or lit and "lit" or "rest"
	if state == self.trayLit then return end
	self.trayLit = state
	local bars, targets = {}, {}
	for _, bar in ipairs(self.tray) do
		table.insert(bars, bar)
		table.insert(targets, lit and 1 or 0)
	end
	if self.main then
		table.insert(bars, self.main)
		table.insert(targets, halo and 0 or 1)
	end
	-- Combat shows the rows straight away rather than fading them in.
	if lit and InCombatLockdown() then
		trayFader:SetScript("OnUpdate", nil)
		for i, bar in ipairs(bars) do bar:SetAlpha(targets[i]) end
	else
		local seconds = halo and TRAY_FADE_IN or lit and TRAY_FADE_IN or TRAY_FADE_OUT
		fadeTray(bars, targets, seconds)
	end
end

function Bars:StartTray()
	local function find()
		Stoa:AfterCombat(function() xpcall(self.FindTray, geterrorhandler(), self) end)
	end
	Stoa:On("PLAYER_ENTERING_WORLD", function() C_Timer.After(0.5, find) end)
	Stoa:On("EDIT_MODE_LAYOUTS_UPDATED", find)
	Stoa:On("UI_SCALE_CHANGED", find)
	if EventRegistry then
		EventRegistry:RegisterCallback("EditMode.Exit", find, self)
	end
	Stoa:On("PLAYER_REGEN_DISABLED", function() self:UpdateTray() end)
	Stoa:On("STOA_STATE_CHANGED", function() self:UpdateTray() end)
	-- If the tray ever errors it stops, rather than repeating ten times a
	-- second; the rows are left showing.
	local ticker
	ticker = C_Timer.NewTicker(0.1, function()
		if not xpcall(self.UpdateTray, geterrorhandler(), self) then
			ticker:Cancel()
			for _, bar in ipairs(self.tray or {}) do bar:SetAlpha(1) end
			if self.main then self.main:SetAlpha(1) end
		end
	end)
	find()
end

-- The settings checkboxes take effect without a reload.
function Bars:SetOption(key, on)
	self.db[key] = on
	self.trayLit = nil
	self:UpdateTray()
end

function Bars:OnEnable()
	Stoa:AfterCombat(function() self:SkinAll() end)
	self:StartTray()
	-- Hotkey colours follow the theme.
	Stoa:On("STOA_THEME_CHANGED", function()
		for _, prefix in ipairs(PREFIXES) do
			for i = 1, 12 do
				local button = _G[prefix .. i]
				if button and button.stoaRound and button.HotKey then
					button.HotKey:SetTextColor(Stoa:Color("muted"))
				end
			end
		end
	end)
end
