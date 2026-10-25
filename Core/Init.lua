-- Stoa: namespace, event bus and lifecycle.
local ADDON, ns = ...

local Stoa = {}
ns.Stoa = Stoa
_G.Stoa = Stoa

Stoa.name = ADDON
Stoa.version = C_AddOns and C_AddOns.GetAddOnMetadata(ADDON, "Version") or "dev"

-- Event bus -----------------------------------------------------------------
-- Modules subscribe with Stoa:On(event, fn). Game events and Stoa's own
-- messages ("STOA_STATE_CHANGED", "STOA_ROLE_CHANGED", ...) share one table.

local frame = CreateFrame("Frame")
local handlers = {}

-- Errors from Stoa's own code go through Stoa:Fail, which Core/Report.lua
-- takes over to keep a record. Until then they just reach the game's handler.
function Stoa:Fail(err)
	geterrorhandler()(err)
end

-- For xpcall: xpcall(fn, Stoa.catch, ...).
function Stoa.catch(err)
	return Stoa:Fail(err)
end

-- The module whose OnInitialize or OnEnable is running, so handlers and
-- timers made there can be traced back to it.
Stoa.loading = nil

function Stoa:On(event, fn)
	if not handlers[event] then
		handlers[event] = {}
		if not event:find("^STOA_") then
			-- A name this client doesn't know must not stop the module
			-- that asked for it.
			pcall(frame.RegisterEvent, frame, event)
		end
	end
	local owner = Stoa.loading
	local entry = { fn = fn, owner = owner }
	-- If one handler keeps failing, Stoa:Fail says so and it is dropped.
	entry.handler = function(err)
		if Stoa:Fail(err, owner) then entry.dead = true end
	end
	table.insert(handlers[event], entry)
end

function Stoa:Fire(event, ...)
	local list = handlers[event]
	if not list then return end
	for i = 1, #list do
		local entry = list[i]
		local module = entry.owner and Stoa.modules[entry.owner]
		if not entry.dead and not (module and module.tripped) then
			xpcall(entry.fn, entry.handler, ...)
		end
	end
end

frame:SetScript("OnEvent", function(_, event, ...)
	Stoa:Fire(event, ...)
end)

-- Unit events for one or two units only. UNIT_AURA and UNIT_POWER_FREQUENT
-- fire for every unit nearby; asking the game for just the units you want
-- (RegisterUnitEvent) keeps a 40-man raid from waking every handler.
-- Stoa:OnUnit("UNIT_AURA", { "player", "target" }, fn) gets fn(unit, ...).
function Stoa:OnUnit(event, units, fn)
	local owner = Stoa.loading
	local listener = CreateFrame("Frame")
	local ok = pcall(listener.RegisterUnitEvent, listener, event, units[1], units[2])
	if not ok then return Stoa:On(event, function(unit, ...)
		if unit == units[1] or unit == units[2] then return fn(unit, ...) end
	end) end
	local function handler(err)
		if Stoa:Fail(err, owner) then listener:UnregisterAllEvents() end
	end
	listener:SetScript("OnEvent", function(_, _, unit, ...)
		local module = owner and Stoa.modules[owner]
		if module and module.tripped then return end
		xpcall(fn, handler, unit, ...)
	end)
	return listener
end

-- Modules -------------------------------------------------------------------
-- A module is a table with optional OnInitialize (after saved variables load)
-- and OnEnable (after the player enters the world). Modules can be switched
-- off in settings; a disabled module is never enabled.

Stoa.modules = {}
local moduleOrder = {}

function Stoa:NewModule(name, defaults)
	local module = { name = name, defaults = defaults or {} }
	self.modules[name] = module
	table.insert(moduleOrder, name)
	return module
end

function Stoa:IsModuleEnabled(name)
	local settings = self.db and self.db.modules[name]
	return not settings or settings.enabled ~= false
end

local function initializeModules()
	for _, name in ipairs(moduleOrder) do
		local module = Stoa.modules[name]
		if module.OnInitialize then
			Stoa.loading = name
			xpcall(module.OnInitialize, function(err) Stoa:Fail(err, name) end, module)
		end
	end
	Stoa.loading = nil
end

local function enableModules()
	for _, name in ipairs(moduleOrder) do
		local module = Stoa.modules[name]
		-- One module failing must not stop the others from loading.
		if module.OnEnable and Stoa:IsModuleEnabled(name) then
			Stoa.loading = name
			module.enabled = xpcall(module.OnEnable, function(err) Stoa:Fail(err, name) end, module)
		end
	end
	Stoa.loading = nil
end

Stoa:On("ADDON_LOADED", function(name)
	if name ~= ADDON then return end
	Stoa:InitializeDatabase()
	initializeModules()
end)

Stoa:On("PLAYER_LOGIN", function()
	enableModules()
	Stoa:Fire("STOA_READY")
end)

-- Slash command and addon compartment ---------------------------------------

-- Modules add their own /stoa words here: Stoa.commands.word = function(rest).
Stoa.commands = {}

function Stoa:Print(...)
	print("|cffd8b66aStoa|r", ...)
end

SLASH_STOA1 = "/stoa"
SlashCmdList.STOA = function(input)
	local command, rest = strtrim(input or ""):match("^(%S*)%s*(.-)$")
	command = command:lower()
	if command == "keywords" then
		local invite = Stoa.modules.AutoInvite.db
		if rest ~= "" then invite.keywords = rest end
		Stoa:Print("Auto-invite keywords:", invite.keywords)
	elseif command == "unlock" or command == "move" then
		Stoa:ToggleMovers()
	elseif command == "theme" then
		Stoa:CycleTheme()
	elseif command == "state" then
		Stoa:Print("State:", Stoa:GetState(), "· Role:", Stoa:GetRole())
	elseif Stoa.commands[command] then
		Stoa.commands[command](rest)
	else
		Stoa:OpenSettings()
	end
end

function Stoa_OnCompartmentClick(_, button)
	if button == "RightButton" then
		Stoa:ToggleMovers()
	else
		Stoa:OpenSettings()
	end
end

function Stoa_OnCompartmentEnter(_, menuButton)
	GameTooltip:SetOwner(menuButton, "ANCHOR_LEFT")
	GameTooltip:AddLine("Stoa")
	GameTooltip:AddLine("Left-click: settings", 1, 1, 1)
	GameTooltip:AddLine("Right-click: move frames", 1, 1, 1)
	GameTooltip:Show()
end

function Stoa_OnCompartmentLeave()
	GameTooltip:Hide()
end
