-- Stoa: small shared helpers.
local _, ns = ...
local Stoa = ns.Stoa

-- Secret values -------------------------------------------------------------
-- On Forever, many unit values are "secret" in combat: they can be shown by a
-- widget (StatusBar:SetValue, FontString:SetText) but not compared or used in
-- maths. Every place that reads a unit value goes through these helpers.

local issecret = _G.issecretvalue or function() return false end

function Stoa:IsSecret(value)
	return issecret(value)
end

-- Returns the value when it is a plain number, otherwise nil. Use this before
-- any comparison or arithmetic.
function Stoa:PlainNumber(value)
	if issecret(value) or type(value) ~= "number" then
		return nil
	end
	return value
end

-- True while the game hides aura details from addons (C_Secrets). A list of
-- auras read then can come back empty or unreadable, which must not be
-- taken for "no auras": callers treat it as "can't tell".
function Stoa:AurasHidden()
	local secrets = _G.C_Secrets
	if not (secrets and secrets.ShouldAurasBeSecret) then return false end
	local ok, hidden = pcall(secrets.ShouldAurasBeSecret)
	return ok and hidden == true
end

-- Safe calls ----------------------------------------------------------------
-- The game's own functions can be missing on this client or fail on a value
-- they won't give an addon. These never raise.

Stoa.safe = {}

-- Passes on every result after a clean pcall, not just two: UnitCastingInfo's
-- spell ID is its ninth.
local function passOn(ok, ...)
	if ok then return ... end
end

-- Calls fn(...) when fn is a function; returns what it returns, or nothing
-- if it is missing or fails.
function Stoa.safe.call(fn, ...)
	if type(fn) ~= "function" then return nil end
	return passOn(pcall(fn, ...))
end

-- Runs fn(...) and sends a failure to Stoa.catch instead of stopping the caller.
function Stoa.safe.guarded(fn, ...)
	xpcall(fn, Stoa.catch, ...)
end

-- The value, or nil when it is nil or secret.
function Stoa.safe.plain(value)
	if value == nil or Stoa:IsSecret(value) then return nil end
	return value
end

-- Auras ---------------------------------------------------------------------

Stoa.aura = {}

-- The unit's aura of this name, or nil.
function Stoa.aura.byName(unit, name, filter)
	if not name or not (C_UnitAuras and C_UnitAuras.GetAuraDataBySpellName) then return nil end
	local ok, aura = pcall(C_UnitAuras.GetAuraDataBySpellName, unit, name, filter)
	if ok then return aura end
end

-- Seconds left on an aura, or nil when the times are hidden.
function Stoa.aura.left(aura)
	local expires = Stoa:PlainNumber(aura and aura.expirationTime)
	if not expires or expires == 0 then return nil end
	return expires - GetTime()
end

-- Frames --------------------------------------------------------------------

Stoa.frames = {}

-- Makes a frame or region see-through without hiding it.
function Stoa.frames.hide(region)
	if region and region.SetAlpha then region:SetAlpha(0) end
end

-- Hides a frame's own textures, leaving its children (buttons, text, items).
function Stoa.frames.strip(frame)
	if not (frame and frame.GetRegions) then return end
	for _, region in ipairs({ frame:GetRegions() }) do
		if region.IsObjectType and region:IsObjectType("Texture") then region:SetAlpha(0) end
	end
end

-- Combat lockdown -----------------------------------------------------------
-- Protected changes (moving secure frames, changing bindings) cannot happen in
-- combat. Queue them and run them when combat ends.

local queue = {}

function Stoa:AfterCombat(fn)
	if InCombatLockdown() then
		table.insert(queue, fn)
	else
		fn()
	end
end

Stoa:On("PLAYER_REGEN_ENABLED", function()
	local pending = queue
	queue = {}
	-- One failing change must not stop the rest.
	for i = 1, #pending do
		xpcall(pending[i], Stoa.catch)
	end
end)

-- Tables --------------------------------------------------------------------

-- Fills missing keys in target from defaults, recursively, without
-- overwriting what the player has already set.
function Stoa:ApplyDefaults(target, defaults)
	for key, value in pairs(defaults) do
		if type(value) == "table" then
			if type(target[key]) ~= "table" then
				target[key] = {}
			end
			self:ApplyDefaults(target[key], value)
		elseif target[key] == nil then
			target[key] = value
		end
	end
	return target
end
