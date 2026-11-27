-- Stoa: the Mage signatures.
-- Which tree you play is read from the talents you know (the deepest
-- talents of each tree), so one Ranged role covers all three:
--   Arcane: coins AP (Arcane Power), PM (Presence of Mind) and E
--     (Evocation); under them your Arcane Blast stacks, MISSILES while
--     Missile Barrage is up (Arcane Missiles outlined), and CLEARCAST
--     (Arcane Blast outlined, as the guides spend it).
--   Fire: coins FB (Fire Blast), C (Combustion) and, with Improved Scorch,
--     S for Fire Vulnerability on the target; HEATING UP while it stacks
--     and HOT STREAK at three stacks, Pyroblast outlined then.
--   Frost: coins N (Frost Nova), B (Ice Barrier) and IB (Ice Block);
--     FINGERS n under them while Fingers of Frost is up, Ice Lance
--     outlined then and while Frostbite holds the target.
-- The outline follows Warcraft Tavern's Forever guides (2026-11-26).
-- Cooldown coins are pale gold when ready, bone while their effect is up
-- and muted while they come back.
--
-- Forever's guides don't give every number yet, so cooldowns and timers
-- below are the classic ones; wherever the game shows them, its own wins.
local _, ns = ...
local Stoa = ns.Stoa
local Sign = Stoa.Sign

local Mage = Stoa:NewModule("Mage", {})

local SPELLS = {
	arcanePower = 12042,
	presence = 12043,
	evocation = 12051,
	arcaneBlast = 400573,
	missiles = 5143,
	missileBarrage = 400588,
	clearcasting = 12536,
	fireball = 133,
	fireBlast = 2136,
	pyroblast = 11366,
	scorch = 2948,
	combustion = 11129,
	-- In Forever this ID is Heating Up (one crit); two crits in a row give
	-- Hot Streak, a buff of its own found by name (no ID known yet).
	heatingUp = 400624,
	improvedScorch = 11095,
	vulnerability = 22959,
	blastWave = 11113,
	frostbolt = 116,
	iceLance = 400640,
	iceLanceAlt = 1312002,
	frostNova = 122,
	iceBarrier = 11426,
	iceBlock = 11958,
	coldSnap = 12472,
	fingers = 400647,
}
local nameOf = Sign.names(SPELLS)

local COOLDOWNS = {
	arcanePower = 180, presence = 180, evocation = 480,
	fireBlast = 8, combustion = 180,
	frostNova = 25, iceBarrier = 30, iceBlock = 300,
}
local VULNERABILITY_LENGTH = 30
-- The Hot Streak buff's name: the instant Pyroblast is ready.
local HOT_STREAK_NAMES = { "Hot Streak!", "Hot Streak" }
if not Stoa.english then HOT_STREAK_NAMES = { Stoa.Spells.unsureName(48108, "Hot Streak") } end

-- The deepest talents of each tree. The tree you know most of is yours.
local TREES = {
	arcane = { "arcanePower", "presence", "missileBarrage" },
	fire = { "combustion", "heatingUp", "blastWave", "improvedScorch" },
	frost = { "iceBarrier", "iceBlock", "coldSnap", "fingers" },
}

function Mage:Tree()
	local _, classFile = UnitClass("player")
	if classFile ~= "MAGE" then return nil end
	local best, most = nil, 0
	for tree, keys in pairs(TREES) do
		local count = 0
		for _, key in ipairs(keys) do
			if Sign.knows(SPELLS[key]) then count = count + 1 end
		end
		if count > most then best, most = tree, count end
	end
	return best
end

function Mage:Active()
	local _, classFile = UnitClass("player")
	return classFile == "MAGE"
end

local function iceLance()
	if Sign.knows(SPELLS.iceLance) then return nameOf("iceLance") end
	if Sign.knows(SPELLS.iceLanceAlt) then return nameOf("iceLanceAlt") end
end

local function buff(key)
	return Sign.aura("player", nameOf(key), "HELPFUL")
end

-- The tree's signature spell for the Halo's slot.
local SIGNATURE = {
	arcane = { "arcanePower", "presence", "evocation" },
	fire = { "combustion", "fireBlast" },
	frost = { "iceBarrier", "frostNova" },
}

function Mage:SignatureSpell()
	for _, key in ipairs(SIGNATURE[self.tree or ""] or {}) do
		if Sign.knows(SPELLS[key]) then return SPELLS[key] end
	end
end

-- Casts --------------------------------------------------------------------------

function Mage:NoteCast(name)
	for key in pairs(SPELLS) do
		if name == nameOf(key) then
			-- Scorch is what keeps Fire Vulnerability up.
			self.casts:Note(key == "scorch" and "vulnerability" or key, key == "scorch")
		end
	end
end

-- Coins --------------------------------------------------------------------------

local COINS = {
	arcane = { { "arcanePower", "AP" }, { "presence", "PM" }, { "evocation", "E" } },
	fire = { { "fireBlast", "FB" }, { "combustion", "C" }, { "vulnerability", "S" } },
	frost = { { "frostNova", "N" }, { "iceBarrier", "B" }, { "iceBlock", "IB" } },
}

function Mage:UpdateCoins()
	local state, index = {}, 0
	for _, entry in ipairs(COINS[self.tree or ""] or {}) do
		local key, letter = entry[1], entry[2]
		if key == "vulnerability" then
			if Sign.knows(SPELLS.improvedScorch) and Sign.hostileTarget() then
				index = index + 1
				state[key] = Sign.debuff(self.coins[index], letter, nameOf("vulnerability"), self.casts, key, Sign.length(SPELLS.vulnerability, VULNERABILITY_LENGTH))
			end
		elseif Sign.knows(SPELLS[key]) then
			index = index + 1
			local active = (key == "arcanePower" or key == "presence" or key == "combustion" or key == "iceBarrier") and buff(key) ~= nil
			state[key] = Sign.cooldown(self.coins[index], letter, SPELLS[key], self.casts:Last(key), COOLDOWNS[key], active)
		end
	end
	Sign.hideFrom(self.coins, index + 1)
	self.state = state
end

-- Heating Up stacks on each crit and makes Pyroblast quick at three.
local PYRO_STACKS = 3
-- Improved Scorch's Fire Vulnerability stacks to five.
local SCORCH_STACKS = 5

-- 2 with Hot Streak up or Heating Up at three, 1 while Heating Up, nil
-- with neither.
local function streak()
	for _, name in ipairs(HOT_STREAK_NAMES) do
		if Sign.aura("player", name, "HELPFUL") then return 2 end
	end
	local heating = buff("heatingUp")
	if heating then return (Sign.stacks(heating) or 1) >= PYRO_STACKS and 2 or 1 end
end

local function stacksOf(key)
	local aura = buff(key)
	if not aura then return nil end
	return Sign.stacks(aura) or 1
end

function Mage:UpdateCaption()
	local parts = {}
	if Sign.inCombat() then
		if self.tree == "arcane" then
			local blast = Sign.knows(SPELLS.arcaneBlast) and stacksOf("arcaneBlast")
			if blast then parts[#parts + 1] = "ARCANE BLAST " .. blast end
			if buff("missileBarrage") then parts[#parts + 1] = "MISSILES" end
		elseif self.tree == "fire" then
			local hot = streak()
			if hot == 2 then parts[#parts + 1] = "HOT STREAK" elseif hot == 1 then parts[#parts + 1] = "HEATING UP" end
		elseif self.tree == "frost" then
			local fingers = Sign.knows(SPELLS.fingers) and stacksOf("fingers")
			if fingers then parts[#parts + 1] = "FINGERS " .. fingers end
		end
		if self.tree and buff("clearcasting") then parts[#parts + 1] = "CLEARCAST" end
	end
	self.caption:SetText(table.concat(parts, "  "))
	self.caption:SetTextColor(Stoa:Color("accent"))
end

-- Next press ---------------------------------------------------------------------

local function ready(key)
	return Sign.knows(SPELLS[key]) and Sign.ready(SPELLS[key])
end

-- Arcane: Missiles on Barrage once Arcane Blast has 2 stacks, Pyroblast at
-- 3 Heating Up and Arcane Wrath at 4 stacks (3 when mana runs low), else
-- Arcane Blast. Fire: Scorch until 5 Fire Vulnerability or ending, Pyroblast
-- at 3 Heating Up, Fire Blast, Missiles on Barrage, Ice Lance on Fingers or
-- Frostbite with Frostfire Bolt, else your main bolt. Frost: Ice Lance on
-- Fingers or Frostbite, Missiles on Barrage, Frostbolt.
function Mage:NextPress()
	if not Sign.hostileTarget() then return nil end
	local state = self.state or {}
	local barrage = buff("missileBarrage") and Sign.knows(SPELLS.missiles)
	local lance = iceLance()
	local frozen = lance and (buff("fingers") or not Sign.missing("Frostbite"))
	if self.tree == "arcane" then
		local stacks = stacksOf("arcaneBlast") or 0
		if barrage and stacks >= 2 then return nameOf("missiles") end
		if streak() == 2 and stacks >= 3 and Sign.knows(SPELLS.pyroblast) then return nameOf("pyroblast") end
		local mana = Sign.manaShare()
		if stacks >= ((mana and mana < 0.35) and 3 or 4) and Sign.can("Arcane Wrath") then
			return C_Spell.GetSpellName(Sign.spell("Arcane Wrath"))
		end
		if Sign.knows(SPELLS.arcaneBlast) then return nameOf("arcaneBlast") end
		if barrage then return nameOf("missiles") end
	elseif self.tree == "fire" then
		if Sign.knows(SPELLS.improvedScorch) then
			local vulnerable = Sign.aura("target", nameOf("vulnerability"), "HARMFUL")
			if state.vulnerability == "off" or state.vulnerability == "ending" or (vulnerable and (Sign.stacks(vulnerable) or SCORCH_STACKS) < SCORCH_STACKS) then
				return nameOf("scorch")
			end
		end
		if streak() == 2 and Sign.knows(SPELLS.pyroblast) then return nameOf("pyroblast") end
		if ready("fireBlast") then return nameOf("fireBlast") end
		if barrage then return nameOf("missiles") end
		local frostfire = Sign.spell("Frostfire Bolt")
		if frostfire then
			if frozen then return lance end
			return C_Spell.GetSpellName(frostfire)
		end
		return nameOf("fireball")
	elseif self.tree == "frost" then
		if frozen then return lance end
		if barrage then return nameOf("missiles") end
		return nameOf("frostbolt")
	end
	return Sign.assisted()
end

-- Lifecycle ----------------------------------------------------------------------

function Mage:Refresh()
	local tree = self:Tree()
	if tree ~= self.tree then
		self.tree = tree
		if Stoa.modules.Halo.UpdateSignature then Stoa.modules.Halo:UpdateSignature() end
	end
	self:UpdateCoins()
	self:UpdateCaption()
	Sign.setNext(self, self:NextPress())
end

function Mage:OnEnable()
	local _, classFile = UnitClass("player")
	if classFile ~= "MAGE" then return end
	local halo = Stoa.modules.Halo
	if not (halo and halo.frame) then return end
	self.coins = Sign.buildCoins(halo.frame)
	self.caption = Sign.buildCaption(halo.frame)
	self.casts = Sign.casts()
	self.tree = self:Tree()
	Stoa.signatureFor = function() return self:SignatureSpell() end
	Sign.wire(self)
end
