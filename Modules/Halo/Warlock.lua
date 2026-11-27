-- Stoa: the Warlock signatures.
--   Coins on the Halo's right for Corruption (C), Bane of Agony (A) and
--   Immolate (I) on the target, timed from your casts when the game hides
--   them, like the Shadow Priest's.
--   SHARDS n under them from your bags, and TAP when your mana is low and
--   your health can spare it. Your demon has its own plaque, arc and words
--   (Pet.lua); Shadow Trance and Decimation are procs (Procs.lua).
--   Next press (Warcraft Tavern's Forever guides, 2026-11-26), read from
--   the spells you know:
--     Affliction (Wrack): Bane of Agony, your Curse, Corruption, Siphon
--     Life, Shadow Bolt under Shadow Trance, Life Tap under 40% mana, Wrack.
--     Destruction (Conflagrate or Incinerate): Bane, Curse, Immolate,
--     Corruption, Conflagrate, Shadowburn, Life Tap, Incinerate.
--     Otherwise (Demonology, levelling): Searing Pain for Demonic Brand,
--     Bane, Curse, Immolate, Soul Fire under Decimation, Corruption, Life
--     Tap, Shadow Bolt.
--   Bane of Doom stands in for Agony on a boss outside Affliction. Your
--   Curse is the one you cast last.
--
-- Forever's guides don't give every number yet, so the timers below are
-- the classic ones; wherever the game shows them, its own wins.
local _, ns = ...
local Stoa = ns.Stoa
local Sign = Stoa.Sign

local Warlock = Stoa:NewModule("Warlock", {})

local SPELLS = {
	corruption = 172,
	agony = 980,
	immolate = 348,
	shadowBolt = 686,
	lifeTap = 1454,
}
local nameOf = Sign.names(SPELLS)

local LENGTHS = { corruption = 18, agony = 24, immolate = 15 }
local SOUL_SHARD = 6265
local TAP_MANA, TAP_HEALTH = 0.25, 0.5

function Warlock:Active()
	local _, classFile = UnitClass("player")
	return classFile == "WARLOCK"
end

function Warlock:NoteCast(name)
	for key in pairs(LENGTHS) do
		if name == nameOf(key) then self.casts:Note(key, true) end
	end
	if name:find("^Curse of ") then self.curse = name end
end

-- Coins --------------------------------------------------------------------------

local COINS = { { "corruption", "C" }, { "agony", "A" }, { "immolate", "I" } }

function Warlock:UpdateCoins()
	local state, index = {}, 0
	if Sign.hostileTarget() then
		for _, entry in ipairs(COINS) do
			local key, letter = entry[1], entry[2]
			if Sign.knows(SPELLS[key]) then
				index = index + 1
				state[key] = Sign.debuff(self.coins[index], letter, nameOf(key), self.casts, key, Sign.length(SPELLS[key], LENGTHS[key]))
			end
		end
	end
	Sign.hideFrom(self.coins, index + 1)
	self.state = state
end

function Warlock:Shards()
	local count = C_Item and C_Item.GetItemCount or GetItemCount
	if not count then return nil end
	local ok, n = pcall(count, SOUL_SHARD)
	return ok and Stoa:PlainNumber(n) or nil
end

local function fraction(value, most)
	value, most = Stoa:PlainNumber(value), Stoa:PlainNumber(most)
	if not value or not most or most == 0 then return nil end
	return value / most
end

function Warlock:WantsTap()
	if not Sign.knows(SPELLS.lifeTap) then return false end
	local mana = fraction(UnitPower("player"), UnitPowerMax("player"))
	local health = fraction(UnitHealth("player"), UnitHealthMax("player"))
	return mana and health and mana < TAP_MANA and health > TAP_HEALTH
end

function Warlock:UpdateCaption()
	local parts, colour = {}, "accent"
	if Sign.inCombat() then
		local shards = self:Shards()
		if shards then parts[#parts + 1] = "SHARDS " .. shards end
		if self:WantsTap() then
			parts[#parts + 1] = "TAP"
			colour = "danger"
		end
	end
	self.caption:SetText(table.concat(parts, "  "))
	self.caption:SetTextColor(Stoa:Color(colour))
end

-- Next press ---------------------------------------------------------------------

local AFFLICTION_TAP = 0.4

local function named(name)
	local id = Sign.spell(name)
	return id and C_Spell.GetSpellName(id)
end

local function ready(name)
	return Sign.can(name) and named(name)
end

-- Your DoT of this name is due: known, and not on the target.
local function due(name)
	return Sign.spell(name) ~= nil and Sign.missing(name)
end

local function boss()
	local level = UnitLevel("target")
	return not Stoa:IsSecret(level) and level == -1
end

function Warlock:NextPress()
	if not Sign.hostileTarget() then return nil end
	local state = self.state or {}
	local affliction = Sign.spell("Wrack") ~= nil
	local destruction = not affliction and (Sign.spell("Conflagrate") or Sign.spell("Incinerate")) ~= nil
	if not affliction and not destruction and due("Demonic Brand") and Sign.spell("Searing Pain") then
		return named("Searing Pain")
	end
	-- Your Bane: any of yours on the target counts.
	if Sign.knows(SPELLS.agony) and state.agony == "off" and Sign.missing("Bane of Doom") and Sign.missing("Bane of Havoc") then
		if not affliction and boss() and Sign.spell("Bane of Doom") then return named("Bane of Doom") end
		return nameOf("agony")
	end
	if self.curse and not Sign.aura("target", self.curse, "HARMFUL") then return self.curse end
	if affliction then
		if state.corruption == "off" then return nameOf("corruption") end
		if due("Siphon Life") then return named("Siphon Life") end
		if Sign.aura("player", "Shadow Trance", "HELPFUL") then return nameOf("shadowBolt") end
		local mana = Sign.manaShare()
		if mana and mana < AFFLICTION_TAP and Sign.knows(SPELLS.lifeTap) then return nameOf("lifeTap") end
		return named("Wrack") or nameOf("shadowBolt")
	end
	if state.immolate == "off" then return nameOf("immolate") end
	if not destruction and Sign.aura("player", "Decimation", "HELPFUL") and Sign.spell("Soul Fire") then return named("Soul Fire") end
	if state.corruption == "off" then return nameOf("corruption") end
	if destruction then
		local burst = ready("Conflagrate") or ((self:Shards() or 0) > 0 and ready("Shadowburn"))
		if burst then return burst end
	end
	if self:WantsTap() then return nameOf("lifeTap") end
	return (destruction and named("Incinerate")) or nameOf("shadowBolt")
end

-- Lifecycle ----------------------------------------------------------------------

function Warlock:Refresh()
	self:UpdateCoins()
	self:UpdateCaption()
	Sign.setNext(self, self:NextPress())
end

function Warlock:OnEnable()
	if not self:Active() then return end
	local halo = Stoa.modules.Halo
	if not (halo and halo.frame) then return end
	self.coins = Sign.buildCoins(halo.frame)
	self.caption = Sign.buildCaption(halo.frame)
	self.casts = Sign.casts()
	Stoa:On("BAG_UPDATE_DELAYED", function() xpcall(self.UpdateCaption, Stoa.catch, self) end)
	Sign.wire(self)
end
