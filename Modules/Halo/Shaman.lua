-- Stoa: the Shaman signatures.
--   Elemental and Enhancement (Ranged and Melee roles): coins on the Halo's
--     right for Flame Shock (F) on the target, your shield (S: Water
--     Shield, else Lightning Shield) with its charges, and Earth Shock (E).
--   Restoration (Healer role): your shield (S), Nature's Swiftness (NS)
--     and Mana Tide Totem (MT).
--   TOTEMS n under them: how many of your four are down in a fight. The
--   game's own totem bar stays (Halo.lua keeps it out of the hidden player
--   frame). Clearcasting is a proc (Procs.lua).
--   Next press: Flame Shock when it's down, Stormstrike for Enhancement,
--   then the game's own suggestion or Earth Shock when ready, else
--   Lightning Bolt.
--
-- Forever's guides don't give every number yet, so the timers below are
-- the classic ones; wherever the game shows them, its own wins.
local _, ns = ...
local Stoa = ns.Stoa
local Sign = Stoa.Sign

local Shaman = Stoa:NewModule("Shaman", {})

local SPELLS = {
	flameShock = 8050,
	earthShock = 8042,
	lightningBolt = 403,
	stormstrike = 17364,
	lightningShield = 324,
	waterShield = 24398,
	swiftness = 16188,
	manaTide = 16190,
}
local nameOf = Sign.names(SPELLS)

local LENGTHS = { flameShock = 12, lightningShield = 600, waterShield = 600 }
local COOLDOWNS = { earthShock = 6, swiftness = 180, manaTide = 300 }
local TOTEMS = 4

function Shaman:Active()
	local _, classFile = UnitClass("player")
	return classFile == "SHAMAN"
end

function Shaman:Healer()
	return Stoa:GetRole() == "HEALER"
end

function Shaman:NoteCast(name)
	for key in pairs(SPELLS) do
		if name == nameOf(key) then self.casts:Note(key, key == "flameShock") end
	end
end

-- Coins --------------------------------------------------------------------------

local function shieldKey()
	if Sign.knows(SPELLS.waterShield) then return "waterShield" end
	if Sign.knows(SPELLS.lightningShield) then return "lightningShield" end
end

function Shaman:UpdateCoins()
	local state, index = {}, 0
	local shield = shieldKey()
	if not self:Healer() and Sign.knows(SPELLS.flameShock) and Sign.hostileTarget() then
		index = index + 1
		state.flameShock = Sign.debuff(self.coins[index], "F", nameOf("flameShock"), self.casts, "flameShock", LENGTHS.flameShock)
	end
	if shield then
		index = index + 1
		local aura
		state.shield, aura = Sign.buff(self.coins[index], "S", nameOf(shield), self.casts, shield, LENGTHS[shield])
		self.charges = aura and Sign.stacks(aura) or nil
	else
		self.charges = nil
	end
	local rest = self:Healer() and { { "swiftness", "NS" }, { "manaTide", "MT" } } or { { "earthShock", "E" } }
	for _, entry in ipairs(rest) do
		local key, letter = entry[1], entry[2]
		if Sign.knows(SPELLS[key]) and index < #self.coins then
			index = index + 1
			local active = key == "swiftness" and Sign.aura("player", nameOf(key), "HELPFUL") ~= nil
			state[key] = Sign.cooldown(self.coins[index], letter, SPELLS[key], self.casts:Last(key), COOLDOWNS[key], active)
		end
	end
	Sign.hideFrom(self.coins, index + 1)
	self.state = state
end

-- How many of your totems are down, or nil when the game won't say.
function Shaman:TotemsDown()
	if not GetTotemInfo then return nil end
	local down = 0
	for slot = 1, TOTEMS do
		local ok, have, _, start = pcall(GetTotemInfo, slot)
		if ok and have and not Stoa:IsSecret(have) and (Stoa:PlainNumber(start) or 0) > 0 then down = down + 1 end
	end
	return down
end

function Shaman:UpdateCaption()
	local parts = {}
	if Sign.inCombat() then
		if self.charges and self.charges > 0 then parts[#parts + 1] = "SHIELD " .. self.charges end
		local down = self:TotemsDown()
		if down then parts[#parts + 1] = ("TOTEMS %d/%d"):format(down, TOTEMS) end
	end
	self.caption:SetText(table.concat(parts, "  "))
	self.caption:SetTextColor(Stoa:Color("accent"))
end

-- Next press ---------------------------------------------------------------------

local function usable(key)
	return Sign.knows(SPELLS[key]) and Sign.ready(SPELLS[key]) ~= false
end

function Shaman:NextPress()
	if self:Healer() or not Sign.hostileTarget() then return nil end
	local state = self.state or {}
	if state.shield == "off" and shieldKey() then return nameOf(shieldKey()) end
	if state.flameShock == "off" then return nameOf("flameShock") end
	if Stoa:GetRole() == "MELEE" and usable("stormstrike") and Sign.ready(SPELLS.stormstrike) then return nameOf("stormstrike") end
	local suggested = Sign.assisted()
	if suggested then return suggested end
	if usable("earthShock") and Sign.ready(SPELLS.earthShock) then return nameOf("earthShock") end
	return nameOf("lightningBolt")
end

-- Lifecycle ----------------------------------------------------------------------

function Shaman:Refresh()
	self:UpdateCoins()
	self:UpdateCaption()
	Sign.setNext(self, self:NextPress())
end

function Shaman:OnEnable()
	if not self:Active() then return end
	local halo = Stoa.modules.Halo
	if not (halo and halo.frame) then return end
	self.coins = Sign.buildCoins(halo.frame)
	self.caption = Sign.buildCaption(halo.frame)
	self.casts = Sign.casts()
	Sign.wire(self, { "PLAYER_TOTEM_UPDATE" })
end
