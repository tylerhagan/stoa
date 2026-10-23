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
local _, ns = ...
local Stoa = ns.Stoa
local UI = Stoa.UI

local Bar = Stoa:NewModule("CombatBar", { count = 12 })

local SIZE = 38
local GAP = 8
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

-- While one of these is up, every button shows, filled at rest or not.
local SWAPPED = "[combat,overridebar][combat,vehicleui][combat,possessbar][combat,shapeshift][combat,bonusbar:5] show; hide"

function Bar:Page()
	return tonumber((self.pager:GetAttribute("actionpage"))) or 1
end

function Bar:Build()
	local pager = CreateFrame("Frame", "StoaCombatBarPager", UIParent)
	RegisterAttributeDriver(pager, "actionpage", pageConditions())
	pager:HookScript("OnAttributeChanged", function(_, name)
		if name == "actionpage" then self:UpdateAll() end
	end)
	self.pager = pager

	self.buttons = {}
	for i = 1, 12 do
		local button = CreateFrame("Button", "StoaCombatButton" .. i, pager, "SecureActionButtonTemplate")
		button:SetFrameStrata("LOW")
		button:SetSize(SIZE, SIZE)
		-- Button i acts on slot i of whatever page the pager holds.
		button:SetID(i)
		button:SetAttribute("type", "action")
		button:SetAttribute("useparent-actionpage", true)
		button.binding = "ACTIONBUTTON" .. i
		button:RegisterForClicks("AnyUp")
		button:Hide()

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
		self.buttons[i] = button
	end
end

-- Out of combat only: lays out the buttons your resting page fills,
-- centred under the Halo, to show in combat. The rest wait to the right
-- and show only while a transform or vehicle swaps the page.
function Bar:Layout()
	local halo = _G.StoaHalo
	if not halo or InCombatLockdown() then return end
	local GetPage = api("GetActionBarPage")
	local base = tonumber(plain(GetPage and GetPage())) or 1
	local filled, spare = {}, {}
	for i, button in ipairs(self.buttons) do
		UnregisterStateDriver(button, "visibility")
		button:Hide()
		if i <= self.db.count then
			local slot = i + (base - 1) * 12
			table.insert(plain(HasAction(slot)) and filled or spare, button)
		end
	end
	local width = #filled * SIZE + (#filled - 1) * GAP
	local x = -width / 2
	for _, button in ipairs(filled) do
		button:ClearAllPoints()
		button:SetPoint("TOPLEFT", halo, "BOTTOM", x, -74)
		x = x + SIZE + GAP
		RegisterStateDriver(button, "visibility", "[combat] show; hide")
	end
	for _, button in ipairs(spare) do
		button:ClearAllPoints()
		button:SetPoint("TOPLEFT", halo, "BOTTOM", x, -74)
		x = x + SIZE + GAP
		RegisterStateDriver(button, "visibility", SWAPPED)
	end
	self.shown = filled
	self:UpdateAll()
end

function Bar:UpdateKeys()
	for _, button in ipairs(self.buttons or {}) do
		button.key:SetText(shortKey(GetBindingKey(button.binding)))
	end
end

function Bar:UpdateCooldowns()
	for _, button in ipairs(self.buttons or {}) do
		local cooldown, slot = button.cooldown, button.slot
		-- Cooldowns may be secret in combat; newer clients hand out a
		-- duration object the cooldown frame can draw without reading it.
		if C_ActionBar and C_ActionBar.GetActionCooldownDuration and cooldown.SetCooldownFromDurationObject then
			pcall(cooldown.SetCooldownFromDurationObject, cooldown, C_ActionBar.GetActionCooldownDuration(slot))
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
	end
end

-- Usable, out of mana, or out of range: dimmed, blue-tinted, or dimmed with
-- its key in the warning colour, so range reads as a word-free shape cue
-- rather than red alone.
function Bar:UpdateState()
	for _, button in ipairs(self.buttons or {}) do
		local slot = button.slot
		local usable, noMana = IsUsableAction(slot)
		usable, noMana = plain(usable), plain(noMana)
		local inRange = IsActionInRange and plain(IsActionInRange(slot))
		local icon = button.icon
		if noMana then
			icon:SetVertexColor(0.45, 0.55, 1)
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
	for i, button in ipairs(self.buttons) do
		local slot = i + (page - 1) * 12
		button.slot = slot
		button.icon:SetTexture(GetActionTexture(slot))
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
		Stoa:AfterCombat(function() xpcall(self.Layout, geterrorhandler(), self) end)
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
	Stoa:On("UPDATE_BINDINGS", function() self:UpdateKeys() end)
	Stoa:On("ACTIONBAR_UPDATE_COOLDOWN", function() self:UpdateCooldowns() end)
	Stoa:On("SPELL_UPDATE_COOLDOWN", function() self:UpdateCooldowns() end)
	Stoa:On("ACTIONBAR_UPDATE_USABLE", function() self:UpdateState() end)
	Stoa:On("SPELL_UPDATE_USABLE", function() self:UpdateState() end)
	Stoa:On("PLAYER_TARGET_CHANGED", function() self:UpdateState() end)
	Stoa:On("UNIT_POWER_FREQUENT", function(unit)
		if unit == "player" then self:UpdateState() end
	end)
	Stoa:On("BAG_UPDATE_DELAYED", function() self:UpdateAll() end)
	-- Range has no event. If an update ever errors the ticker stops rather
	-- than repeating.
	local ticker
	ticker = C_Timer.NewTicker(0.25, function()
		if not InCombatLockdown() then return end
		if not xpcall(self.UpdateState, geterrorhandler(), self) then ticker:Cancel() end
	end)
	layout()
end
