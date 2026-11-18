-- Stoa: small shared helpers.
local _, ns = ...
local Stoa = ns.Stoa

-- Tables ---------------------------------------------------------------------------

-- A deep copy of a value: tables copied through, everything else as is.
function Stoa.copy(value)
	if type(value) ~= "table" then return value end
	local out = {}
	for k, v in pairs(value) do out[k] = Stoa.copy(v) end
	return out
end

-- Money ----------------------------------------------------------------------------

-- Copper as the game writes it, with coin icons; plain letters without them.
function Stoa:Money(copper)
	copper = self:PlainNumber(copper) or 0
	local format = (C_CurrencyInfo and C_CurrencyInfo.GetCoinTextureString) or GetCoinTextureString
	if format then return format(copper) end
	return ("%dg %ds %dc"):format(math.floor(copper / 10000), math.floor(copper / 100) % 100, copper % 100)
end

-- Money written as letters (12g 04s 30c) takes the game's coin icons in
-- place of the letters, the way the money hover and Blizzard's frames draw it.
local COIN = {
	g = "|TInterface\\MoneyFrame\\UI-GoldIcon:0:0:2:0|t",
	s = "|TInterface\\MoneyFrame\\UI-SilverIcon:0:0:2:0|t",
	c = "|TInterface\\MoneyFrame\\UI-CopperIcon:0:0:2:0|t",
}

function Stoa:TintMoney(text)
	if type(text) ~= "string" then return text end
	return (text:gsub("(%d)([gsc])%f[%A]", function(digit, letter) return digit .. COIN[letter] end))
end

-- Colour escapes ---------------------------------------------------------------

-- The chat colour code for a colour, from numbers or a token name.
function Stoa:Hex(r, g, b)
	if type(r) == "string" then r, g, b = self:Color(r) end
	return ("|cff%02x%02x%02x"):format(r * 255, g * 255, b * 255)
end

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

-- Your name with your surname, where the realm has them (WoW Forever's
-- unique names): UnitName gives the surname as its second value there.
function Stoa.fullName()
	local name, surname = UnitName("player")
	name = Stoa.safe and Stoa.safe.plain and Stoa.safe.plain(name) or name
	if not name then return nil end
	local unique = RegionalUniqueNamesEnabled and RegionalUniqueNamesEnabled()
	if unique and type(surname) == "string" and surname ~= "" and not (Stoa.IsSecret and Stoa:IsSecret(surname)) then
		return name .. " " .. surname, surname
	end
	return name
end

-- Creature kinds ------------------------------------------------------------
-- UnitCreatureType answers in the game's language, so a kind is asked for
-- by its English word here and matched through the game's own type IDs.

local CREATURE_TYPES = {
	Beast = 1, Dragonkin = 2, Demon = 3, Elemental = 4, Giant = 5, Undead = 6,
	Humanoid = 7, Critter = 8, Mechanical = 9, ["Not specified"] = 10,
}
local creatureWords = {}

local function creatureWord(english)
	local word = creatureWords[english]
	if word == nil then
		local info = C_CreatureInfo and C_CreatureInfo.GetCreatureTypeInfo
			and Stoa.safe.call(C_CreatureInfo.GetCreatureTypeInfo, CREATURE_TYPES[english])
		word = type(info) == "table" and Stoa.safe.plain(info.name) or false
		creatureWords[english] = word
	end
	return word
end

-- Whether the unit is one of these kinds: Stoa.creatureIs("target", "Undead", "Demon").
function Stoa.creatureIs(unit, ...)
	local kind = Stoa.safe.plain(UnitCreatureType(unit))
	if not kind then return false end
	for i = 1, select("#", ...) do
		local english = select(i, ...)
		if kind == english or kind == creatureWord(english) then return true end
	end
	return false
end

-- Frames --------------------------------------------------------------------

Stoa.frames = {}

-- Makes a frame or region see-through without hiding it.
function Stoa.frames.hide(region)
	if region and region.SetAlpha and not (region.IsForbidden and region:IsForbidden()) then region:SetAlpha(0) end
end

-- Hides a frame's own textures, leaving its children (buttons, text, items).
function Stoa.frames.strip(frame)
	if not (frame and frame.GetRegions) or (frame.IsForbidden and frame:IsForbidden()) then return end
	for _, region in ipairs({ frame:GetRegions() }) do
		if region.IsObjectType and region:IsObjectType("Texture") then region:SetAlpha(0) end
	end
end

-- Combat lockdown -----------------------------------------------------------
-- Protected changes (moving secure frames, changing bindings) cannot happen in
-- combat. Queue them and run them when combat ends.

local queue = {}

-- Every reload Stoa asks for. If the game blocks the call (it prints
-- "Interface action failed because of an AddOn" and carries on), the player
-- is told to finish by hand instead of being left with half a change.
function Stoa:Reload()
	local reload = (C_UI and C_UI.Reload) or ReloadUI
	if reload then pcall(reload) end
	C_Timer.After(1, function()
		Stoa:Print("The game didn't let STOA reload. Type /reload to finish.")
	end)
end

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
