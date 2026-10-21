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

function Stoa:On(event, fn)
	if not handlers[event] then
		handlers[event] = {}
		if not event:find("^STOA_") then
			frame:RegisterEvent(event)
		end
	end
	table.insert(handlers[event], fn)
end

function Stoa:Fire(event, ...)
	local list = handlers[event]
	if not list then return end
	for i = 1, #list do
		local ok, err = pcall(list[i], ...)
		if not ok then
			geterrorhandler()(err)
		end
	end
end

frame:SetScript("OnEvent", function(_, event, ...)
	Stoa:Fire(event, ...)
end)

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
			xpcall(module.OnInitialize, geterrorhandler(), module)
		end
	end
end

local function enableModules()
	for _, name in ipairs(moduleOrder) do
		local module = Stoa.modules[name]
		-- One module failing must not stop the others from loading.
		if module.OnEnable and Stoa:IsModuleEnabled(name) then
			module.enabled = xpcall(module.OnEnable, geterrorhandler(), module)
		end
	end
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
