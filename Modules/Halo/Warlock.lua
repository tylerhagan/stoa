-- Stoa: the Warlock signatures.
--   Coins on the Halo's right for Corruption (C), Curse of Agony (A) and
--   Immolate (I) on the target, timed from your casts when the game hides
--   them, like the Shadow Priest's.
--   SHARDS n under them from your bags, and TAP when your mana is low and
--   your health can spare it. Your demon has its own plaque, arc and words
--   (Pet.lua); Shadow Trance and Decimation are procs (Procs.lua).
--   Next press: whichever of the three is down, then the game's own
--   suggestion or Shadow Bolt.
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
				state[key] = Sign.debuff(self.coins[index], letter, nameOf(key), self.casts, key, LENGTHS[key])
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

function Warlock:NextPress()
	if not Sign.hostileTarget() then return nil end
	local state = self.state or {}
	if self:WantsTap() then return nameOf("lifeTap") end
	for _, entry in ipairs(COINS) do
		if state[entry[1]] == "off" then return nameOf(entry[1]) end
	end
	return Sign.assisted() or nameOf("shadowBolt")
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
