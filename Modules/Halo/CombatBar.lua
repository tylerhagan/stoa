-- Stoa: the combat bar.
-- In combat the console folds away and a compact row of your main bar's
-- spells sits under the Halo, close to your eyes: rounded icons, the key
-- under each, a sweep for cooldowns, dimmed when you can't use them.
--
-- The buttons are Stoa's own secure action buttons pointing at the same
-- action slots as Blizzard's main bar, so your keybinds keep working on
-- Blizzard's buttons and a click here casts the same spell. The row follows
-- the main bar's page, so a transform or vehicle shows its own spells.
-- Which buttons rest in the row is worked out out of combat; the game
-- shows the row only in combat.
--
-- One or two more rows can follow from the bottom-left and bottom-right
-- bars, each a step smaller so the rotation stays biggest. Long cooldowns
-- sit dim until they're ready.
local _, ns = ...
local Stoa = ns.Stoa
local UI = Stoa.UI

local Bar = Stoa:NewModule("CombatBar", { count = 12, rows = "2", healerRows = "1" })
-- Each spec keeps its own number of rows.
Stoa:SpecSettings(Bar, { "rows", "healerRows" })

local SIZE = 38
local GAP = 8
local TOP = -74
-- Rows after the main bar: the bar each one mirrors (as its page of action
-- slots and its key bindings) and its button size.
local EXTRA_ROWS = {
	{ page = 6, binding = "MULTIACTIONBAR1BUTTON", size = 34, gap = 7 },
	{ page = 5, binding = "MULTIACTIONBAR2BUTTON", size = 30, gap = 6 },
}
-- Room for the keys under a row, and between rows.
local KEY_ROOM = 18
-- A cooldown longer than this dims its button until it's ready.
local LONG_COOLDOWN = 30
local WAITING_ALPHA = 0.38
local MASK = UI.MEDIA .. "Textures\\ButtonMask"

-- Newer clients keep the action API under C_ActionBar.
local function api(name)
	return (C_ActionBar and C_ActionBar[name]) or _G[name]
end
local HasAction = api("HasAction")
local GetActionTexture = api("GetActionTexture")
local IsUsableAction = api("IsUsableAction")
local IsActionInRange = api("IsActionInRange")
local GetActionCount = api("GetActionCount")
local GetActionInfo = api("GetActionInfo")

local function plain(value)
	if Stoa:IsSecret(value) then return nil end
	return value
end

-- "SHIFT-Q" reads as "s-Q", like Blizzard's short labels.
local function shortKey(key)
	if type(key) ~= "string" then return "" end
	key = key:gsub("SHIFT%-", "s-"):gsub("CTRL%-", "c-"):gsub("ALT%-", "a-")
	key = key:gsub("BUTTON", "M"):gsub("MOUSEWHEELUP", "WU"):gsub("MOUSEWHEELDOWN", "WD")
	return key
end

-- The main bar's page, as Blizzard's own main bar picks it: a transform,
-- vehicle or possession brings its own page, as do stances and bar paging.
-- An attribute driver keeps it current in combat with no secure code.
local function pageConditions()
	local function index(name, fallback)
		local fn = api(name)
		return tonumber(plain(fn and fn())) or fallback
	end
	local override = index("GetOverrideBarIndex", 14)
	local vehicle = index("GetVehicleBarIndex", 12)
	local temp = index("GetTempShapeshiftBarIndex", 13)
	return ("[overridebar] %d; [vehicleui] %d; [possessbar] %d; [shapeshift] %d; "
		.. "[bonusbar:5] 11; [bonusbar:1] 7; [bonusbar:2] 8; [bonusbar:3] 9; [bonusbar:4] 10; "
		.. "[bar:2] 2; [bar:3] 3; [bar:4] 4; [bar:5] 5; [bar:6] 6; 1"):format(override, vehicle, vehicle, temp)
end

-- While one of these is up the page is swapped for the transform's own.
local SWAPPED = "[combat,overridebar][combat,vehicleui][combat,possessbar][combat,shapeshift][combat,bonusbar:5] show; hide"
local RESTING = "[overridebar][vehicleui][possessbar][shapeshift][bonusbar:5] hide; [combat] show; hide"
-- Pages past the six bars belong to a transform, vehicle or possession.
local LAST_BAR_PAGE = 10

function Bar:Page()
	return tonumber((self.pager:GetAttribute("actionpage"))) or 1
end

function Bar:MakeButton(name, parent, size)
	local button = CreateFrame("Button", name, parent, "SecureActionButtonTemplate")
	button:SetFrameStrata("LOW")
	button:SetSize(size, size)
	button.size = size
	button:RegisterForClicks("AnyUp")
	button:Hide()

	-- An outline behind the button for the suggested next press.
	local nextRing = button:CreateTexture(nil, "BACKGROUND", nil, -8)
	nextRing:SetPoint("TOPLEFT", -3, 3)
	nextRing:SetPoint("BOTTOMRIGHT", 3, -3)
	nextRing:SetTexture(MASK)
	UI.tint(nextRing, "accent")
	nextRing:Hide()
	button.nextRing = nextRing

	UI.roundPanel(button, 0.9)
	local icon = button:CreateTexture(nil, "ARTWORK")
	icon:SetAllPoints()
	icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
	local mask = button:CreateMaskTexture()
	mask:SetAllPoints()
	mask:SetTexture(MASK, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
	icon:AddMaskTexture(mask)
	button.icon = icon

	local highlight = button:CreateTexture(nil, "HIGHLIGHT")
	highlight:SetAllPoints()
	highlight:SetColorTexture(1, 1, 1, 0.15)
	highlight:AddMaskTexture(mask)

	local cooldown = CreateFrame("Cooldown", nil, button, "CooldownFrameTemplate")
	cooldown:SetAllPoints()
	cooldown:SetSwipeTexture(MASK)
	cooldown:SetDrawEdge(false)
	cooldown:SetDrawBling(false)
	button.cooldown = cooldown
	-- A long cooldown finishing brings its button back up.
	cooldown:HookScript("OnCooldownDone", function()
		button.waiting = nil
		Bar.RefreshAlpha(button)
	end)

	local count = UI.text(button, "sans", Stoa.typeSize.caption, "text", "RIGHT")
	count:SetPoint("BOTTOMRIGHT", 1, 1)
	Stoa:SetFont(count, "sans", Stoa.typeSize.caption, "OUTLINE")
	button.count = count
	-- The key sits under the button, where the eye already is.
	local key = UI.text(button, "sans", Stoa.typeSize.label, "muted", "CENTER")
	key:SetPoint("TOP", button, "BOTTOM", 0, -3)
	UI.legible(key)
	button.key = key

	button:SetScript("OnEnter", function(own)
		if own.slot then
			GameTooltip_SetDefaultAnchor(GameTooltip, own)
			GameTooltip:SetAction(own.slot)
		end
	end)
	button:SetScript("OnLeave", GameTooltip_Hide)
	return button
end

-- The default spot: under the Halo, or mid-screen until the Halo exists.
function Bar:PlaceAnchor()
	local anchor, halo = self.anchor, _G.StoaHalo
	anchor:ClearAllPoints()
	if halo then
		anchor:SetPoint("TOP", halo, "BOTTOM", 0, TOP)
	else
		anchor:SetPoint("TOP", UIParent, "CENTER", 0, -60 + TOP)
	end
	self.anchored = halo ~= nil
end

function Bar:Build()
	local pager = CreateFrame("Frame", "StoaCombatBarPager", UIParent)
	RegisterAttributeDriver(pager, "actionpage", pageConditions())
	pager:HookScript("OnAttributeChanged", function(_, name)
		if name == "actionpage" then self:UpdateAll() end
	end)
	self.pager = pager

	-- The rows hang from this frame, so one mover shifts the whole bar. By
	-- default it sits under the Halo, where the rows always went.
	local anchor = CreateFrame("Frame", "StoaCombatBarAnchor", UIParent)
	anchor:SetSize(12 * SIZE + 11 * GAP, SIZE)
	anchor:SetFrameStrata("LOW")
	self.anchor = anchor
	self:PlaceAnchor()
	Stoa:RegisterMover("combatbar", anchor, "Combat bar", { default = function() self:PlaceAnchor() end })

	self.buttons, self.all = {}, {}
	for i = 1, 12 do
		local button = self:MakeButton("StoaCombatButton" .. i, pager, SIZE)
		-- Button i acts on slot i of whatever page the pager holds.
		button:SetID(i)
		button:SetAttribute("type", "action")
		button:SetAttribute("useparent-actionpage", true)
		button.binding = "ACTIONBUTTON" .. i
		self.buttons[i] = button
		self.all[#self.all + 1] = button
	end

	-- The extra rows point at fixed slots, so no paging.
	self.extra = {}
	for r, row in ipairs(EXTRA_ROWS) do
		local buttons = {}
		for i = 1, 12 do
			local button = self:MakeButton(("StoaCombatRow%dButton%d"):format(r + 1, i), UIParent, row.size)
			button.fixed = i + (row.page - 1) * 12
			button:SetAttribute("type", "action")
			button:SetAttribute("action", button.fixed)
			button.binding = row.binding .. i
			buttons[i] = button
			self.all[#self.all + 1] = button
		end
		self.extra[r] = buttons
	end
end

-- How many rows show in combat: healers keep their eyes on the group, so
-- they default to one.
function Bar:RowCount()
	local wanted = Stoa:GetRole() == "HEALER" and self.db.healerRows or self.db.rows
	return math.max(1, math.min(#EXTRA_ROWS + 1, tonumber(wanted) or 1))
end

-- Where the group frames sit under the Halo while the combat rows show.
function Bar:GroupOffset()
	return self.groupOffset or -136
end

-- Out of combat only: lays out the buttons the current page fills, centred
-- under the Halo, to show in combat. At rest the others wait to the right
-- and show only while a transform swaps the page; while transformed, the
-- transform's spells sit centred and your resting ones wait to the right
-- for when it ends. Empty buttons fade out either way.
function Bar:Layout()
	local halo = _G.StoaHalo
	if not halo or InCombatLockdown() then return end
	if not self.anchored and not Stoa:HasSavedPosition("combatbar") then self:PlaceAnchor() end
	local GetPage = api("GetActionBarPage")
	local base = tonumber(plain(GetPage and GetPage())) or 1
	local page = self:Page()
	local swapped = page > LAST_BAR_PAGE
	local function has(i, onPage) return plain(HasAction(i + (onPage - 1) * 12)) end
	local filled, spare = {}, {}
	for i, button in ipairs(self.buttons) do
		UnregisterStateDriver(button, "visibility")
		button:Hide()
		if i <= self.db.count then
			local now = has(i, swapped and page or base)
			local other = swapped and has(i, base)
			if now then
				filled[#filled + 1] = { button, (not swapped or other) and "[combat] show; hide" or SWAPPED }
			elseif swapped then
				if other then spare[#spare + 1] = { button, RESTING } end
			else
				spare[#spare + 1] = { button, SWAPPED }
			end
		end
	end
	local width = #filled * SIZE + (#filled - 1) * GAP
	local x = -width / 2
	self.shown = {}
	for _, list in ipairs({ filled, spare }) do
		for _, entry in ipairs(list) do
			local button, driver = entry[1], entry[2]
			button:ClearAllPoints()
			button:SetPoint("TOPLEFT", self.anchor, "TOP", x, 0)
			x = x + SIZE + GAP
			RegisterStateDriver(button, "visibility", driver)
			if list == filled then self.shown[#self.shown + 1] = button end
		end
	end

	-- The extra rows: only filled buttons, centred, each row under the last.
	-- They step aside while a transform has the main row.
	local y = TOP - SIZE - KEY_ROOM
	local rows = self:RowCount()
	for r, buttons in ipairs(self.extra) do
		local row = EXTRA_ROWS[r]
		local used = {}
		for _, button in ipairs(buttons) do
			UnregisterStateDriver(button, "visibility")
			button:Hide()
			if r < rows and plain(HasAction(button.fixed)) then used[#used + 1] = button end
		end
		if #used > 0 then
			local rowX = -(#used * row.size + (#used - 1) * row.gap) / 2
			for _, button in ipairs(used) do
				button:ClearAllPoints()
				button:SetPoint("TOPLEFT", self.anchor, "TOP", rowX, y - TOP)
				rowX = rowX + row.size + row.gap
				RegisterStateDriver(button, "visibility", RESTING)
				self.shown[#self.shown + 1] = button
			end
			y = y - row.size - KEY_ROOM
		end
	end
	local offset = y - 6
	if offset ~= self.groupOffset then
		self.groupOffset = offset
		Stoa:Fire("STOA_COMBAT_LAYOUT", Stoa:CombatLayout())
	end
	self:UpdateAll()
end

-- Empty buttons vanish; ones waiting on a long cooldown sit dim. Alpha can
-- change in combat where showing and hiding can't.
function Bar.RefreshAlpha(button)
	button:SetAlpha(button.empty and 0 or button.waiting and WAITING_ALPHA or 1)
end

-- Outlines the button holding the named spell, or none. Spell ranks have
-- their own IDs, so buttons are matched by name.
function Bar:SetNext(spellName)
	for _, button in ipairs(self.all or {}) do
		local match = false
		if spellName and button.slot and GetActionInfo and button:IsVisible() then
			local kind, id = GetActionInfo(button.slot)
			if kind == "spell" and not Stoa:IsSecret(id) and id then
				match = C_Spell.GetSpellName(id) == spellName
			end
		end
		button.nextRing:SetShown(match)
	end
end

function Bar:UpdateKeys()
	for _, button in ipairs(self.all or {}) do
		button.key:SetText(shortKey(GetBindingKey(button.binding)))
	end
end

-- Seconds left on a slot's cooldown, or nil when the game won't say.
function Bar:CooldownLeft(slot)
	local start, duration
	if C_ActionBar and C_ActionBar.GetActionCooldown then
		local ok, info = pcall(C_ActionBar.GetActionCooldown, slot)
		if ok and type(info) == "table" then start, duration = info.startTime, info.duration end
	elseif GetActionCooldown then
		start, duration = GetActionCooldown(slot)
	end
	start, duration = plain(start), plain(duration)
	if type(start) ~= "number" or type(duration) ~= "number" then return nil end
	if start == 0 or duration == 0 then return 0 end
	return start + duration - GetTime()
end

function Bar:UpdateCooldowns()
	for _, button in ipairs(self.all or {}) do
		local cooldown, slot = button.cooldown, button.slot
		-- A button not yet laid out (combat at login) has no slot to read.
		if not slot then
			-- nothing to show yet
		-- Cooldowns may be secret in combat; newer clients hand out a
		-- duration object the cooldown frame can draw without reading it.
		elseif C_ActionBar and C_ActionBar.GetActionCooldownDuration and cooldown.SetCooldownFromDurationObject then
			pcall(function()
				cooldown:SetCooldownFromDurationObject(C_ActionBar.GetActionCooldownDuration(slot))
			end)
		else
			local start, duration
			if C_ActionBar and C_ActionBar.GetActionCooldown then
				local info = C_ActionBar.GetActionCooldown(slot)
				if type(info) == "table" then start, duration = info.startTime, info.duration end
			elseif GetActionCooldown then
				start, duration = GetActionCooldown(slot)
			end
			if start then pcall(cooldown.SetCooldown, cooldown, start, duration) end
		end
		-- Dim while a long cooldown runs. If the game keeps the times secret
		-- the button just keeps its sweep.
		local waiting = self:CooldownLeft(slot)
		if waiting ~= nil then
			button.waiting = waiting > LONG_COOLDOWN or nil
			Bar.RefreshAlpha(button)
		end
	end
end

-- Usable, out of mana, or out of range: dimmed, blue-tinted, or dimmed with
-- its key in the warning colour, so range reads as a word-free shape cue
-- rather than red alone.
function Bar:UpdateState()
	for _, button in ipairs(self.all or {}) do
		local slot = button.slot
		if not slot then break end
		local usable, noMana = IsUsableAction(slot)
		usable, noMana = plain(usable), plain(noMana)
		local inRange = IsActionInRange and plain(IsActionInRange(slot))
		local icon = button.icon
		if noMana then
			-- Short of mana: tinted toward the theme's mana colour.
			local r, g, b = Stoa:Color("mana")
			icon:SetVertexColor(0.3 + r * 0.4, 0.3 + g * 0.4, 0.3 + b * 0.4)
		elseif usable == false then
			icon:SetVertexColor(0.4, 0.4, 0.4)
		else
			icon:SetVertexColor(1, 1, 1)
		end
		local far = inRange == false
		icon:SetAlpha(far and 0.5 or 1)
		button.key:SetTextColor(Stoa:Color(far and "danger" or "muted"))
	end
end

function Bar:UpdateAll()
	if not self.buttons then return end
	local page = self:Page()
	for i, button in ipairs(self.all) do
		local slot = button.fixed or i + (page - 1) * 12
		button.slot = slot
		button.icon:SetTexture(GetActionTexture(slot))
		button.empty = plain(HasAction(slot)) == false
		Bar.RefreshAlpha(button)
		local count = GetActionCount and plain(GetActionCount(slot))
		button.count:SetText(count and count > 1 and count or "")
	end
	self:UpdateKeys()
	self:UpdateCooldowns()
	self:UpdateState()
end

function Bar:OnEnable()
	self:Build()
	local function layout()
		Stoa:AfterCombat(function() xpcall(self.Layout, Stoa.catch, self) end)
	end
	Stoa:On("PLAYER_ENTERING_WORLD", function() C_Timer.After(0.5, layout) end)
	Stoa:On("ACTIONBAR_SLOT_CHANGED", function()
		self:UpdateAll()
		layout()
	end)
	-- A page swap shows straight away; the resting layout follows after
	-- combat.
	for _, event in ipairs({ "ACTIONBAR_PAGE_CHANGED", "UPDATE_BONUS_ACTIONBAR", "UPDATE_OVERRIDE_ACTIONBAR", "UPDATE_VEHICLE_ACTIONBAR", "UPDATE_POSSESS_BAR", "UPDATE_SHAPESHIFT_FORM" }) do
		Stoa:On(event, function()
			self:UpdateAll()
			layout()
		end)
	end
	-- The page driver can land a moment after the game's events.
	self.pager:HookScript("OnAttributeChanged", function(_, name)
		if name == "actionpage" then layout() end
	end)
	Stoa:On("UPDATE_BINDINGS", function() self:UpdateKeys() end)
	Stoa:On("STOA_ROLE_CHANGED", layout)
	Stoa:On("ACTIONBAR_UPDATE_COOLDOWN", function() self:UpdateCooldowns() end)
	Stoa:On("SPELL_UPDATE_COOLDOWN", function() self:UpdateCooldowns() end)
	Stoa:On("ACTIONBAR_UPDATE_USABLE", function() self:UpdateState() end)
	Stoa:On("SPELL_UPDATE_USABLE", function() self:UpdateState() end)
	Stoa:On("PLAYER_TARGET_CHANGED", function() self:UpdateState() end)
	Stoa:OnUnit("UNIT_POWER_FREQUENT", { "player" }, function() self:UpdateState() end)
	Stoa:On("BAG_UPDATE_DELAYED", function() self:UpdateAll() end)
	-- Range has no event. If an update ever errors the ticker stops rather
	-- than repeating.
	local ticker
	ticker = Stoa:NewTicker(0.25, function()
		if not InCombatLockdown() then return end
		if not xpcall(self.UpdateState, Stoa.catch, self) then ticker:Cancel() end
	end)
	-- /stoa combat practice: the game only shows the row in real combat,
	-- so the filled buttons are shown by hand while practising.
	Stoa:On("STOA_STATE_CHANGED", function()
		if InCombatLockdown() then return end
		if Stoa:IsPractising() then
			for _, button in ipairs(self.shown or {}) do
				UnregisterStateDriver(button, "visibility")
				button:Show()
			end
		else
			layout()
		end
	end)
	layout()
end

-- A spec change can bring its own number of rows.
Stoa:On("STOA_SPEC_SETTINGS", function()
	if Bar.enabled then Stoa:AfterCombat(function() Bar:Layout() end) end
end)
