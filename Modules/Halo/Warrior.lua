-- Stoa: the Warrior signatures.
--   Arms and Fury (Melee role): coins on the Halo's right for Rend (R) on
--     the target, Sunder Armor (S) with SUNDER n under them, and Battle
--     Shout (B) on you.
--   Protection (Tank role): Sunder Armor (S), Thunder Clap (T) and
--     Demoralizing Shout (D) on the target; TAUNT over the ring when
--     something in your group has the enemy's attention and Taunt is ready.
-- The caption names your stance in a fight, so a wrong stance is a word,
-- not a greyed-out button. Overpower, Revenge, Execute and Victory Rush
-- are procs (Procs.lua).
--
-- Forever's guides don't give every number yet, so the timers below are
-- the classic ones; wherever the game shows them, its own wins.
local _, ns = ...
local Stoa = ns.Stoa
local Sign = Stoa.Sign

local Warrior = Stoa:NewModule("Warrior", {})

local SPELLS = {
	rend = 772,
	sunder = 7386,
	battleShout = 6673,
	thunderClap = 6343,
	demoShout = 1160,
	taunt = 355,
	heroicStrike = 78,
	bloodthirst = 23881,
	mortalStrike = 12294,
	shieldSlam = 23922,
	revenge = 6572,
}
local nameOf = Sign.names(SPELLS)

local LENGTHS = { rend = 21, sunder = 30, battleShout = 120, thunderClap = 30, demoShout = 30 }
local SUNDER_MAX = 5
local STANCES = { [17] = "BATTLE", [18] = "DEFENSIVE", [19] = "BERSERKER" }

function Warrior:Active()
	local _, classFile = UnitClass("player")
	return classFile == "WARRIOR"
end

function Warrior:Tank()
	return Stoa:GetRole() == "TANK"
end

-- Casts --------------------------------------------------------------------------

function Warrior:NoteCast(name)
	for key in pairs(SPELLS) do
		if name == nameOf(key) then
			self.casts:Note(key, key ~= "battleShout")
		end
	end
end

-- Coins --------------------------------------------------------------------------

local COINS = {
	melee = { { "rend", "R" }, { "sunder", "S" }, { "battleShout", "B" } },
	tank = { { "sunder", "S" }, { "thunderClap", "T" }, { "demoShout", "D" } },
}

function Warrior:UpdateCoins()
	local state, index = {}, 0
	local hostile = Sign.hostileTarget()
	for _, entry in ipairs(COINS[self:Tank() and "tank" or "melee"]) do
		local key, letter = entry[1], entry[2]
		if Sign.knows(SPELLS[key]) then
			if key == "battleShout" then
				index = index + 1
				state[key] = Sign.buff(self.coins[index], letter, nameOf(key), self.casts, key, LENGTHS[key])
			elseif hostile then
				index = index + 1
				local aura
				state[key], aura = Sign.debuff(self.coins[index], letter, nameOf(key), self.casts, key, LENGTHS[key])
				if key == "sunder" then self.sunders = aura and (Sign.stacks(aura) or 1) or 0 end
			end
		end
	end
	if not hostile then self.sunders = 0 end
	Sign.hideFrom(self.coins, index + 1)
	self.state = state
end

function Warrior:Stance()
	if not GetShapeshiftFormID then return nil end
	local id = GetShapeshiftFormID()
	if Stoa:IsSecret(id) then return nil end
	return STANCES[id]
end

function Warrior:UpdateCaption()
	local parts = {}
	if Sign.inCombat() then
		local stance = self:Stance()
		if stance then parts[#parts + 1] = stance end
		if Sign.knows(SPELLS.sunder) and (self.sunders or 0) > 0 then
			parts[#parts + 1] = ("SUNDER %d/%d"):format(math.min(self.sunders, SUNDER_MAX), SUNDER_MAX)
		end
	end
	self.caption:SetText(table.concat(parts, "  "))
	self.caption:SetTextColor(Stoa:Color("accent"))
end

function Warrior:UpdateWord()
	local show = Sign.inCombat() and self:Tank() and Sign.knows(SPELLS.taunt)
		and Sign.wantsTaunt() and Sign.ready(SPELLS.taunt) ~= false
	self.word:SetShown(show and true or false)
end

-- Next press ---------------------------------------------------------------------

local function usable(key)
	return Sign.knows(SPELLS[key]) and Sign.ready(SPELLS[key]) ~= false
end

function Warrior:NextPress()
	if not Sign.hostileTarget() then return nil end
	local state = self.state or {}
	if self:Tank() then
		if Sign.wantsTaunt() and usable("taunt") then return nameOf("taunt") end
		if Sign.knows(SPELLS.sunder) and (self.sunders or 0) < SUNDER_MAX then return nameOf("sunder") end
		if state.demoShout == "off" then return nameOf("demoShout") end
		if state.thunderClap == "off" then return nameOf("thunderClap") end
		if usable("shieldSlam") and Sign.ready(SPELLS.shieldSlam) then return nameOf("shieldSlam") end
		return Sign.assisted() or nameOf("heroicStrike")
	end
	if state.battleShout == "off" and Sign.knows(SPELLS.battleShout) then return nameOf("battleShout") end
	if state.rend == "off" then return nameOf("rend") end
	if usable("mortalStrike") and Sign.ready(SPELLS.mortalStrike) then return nameOf("mortalStrike") end
	if usable("bloodthirst") and Sign.ready(SPELLS.bloodthirst) then return nameOf("bloodthirst") end
	if Sign.knows(SPELLS.sunder) and (self.sunders or 0) < SUNDER_MAX then return nameOf("sunder") end
	return Sign.assisted() or nameOf("heroicStrike")
end

-- Lifecycle ----------------------------------------------------------------------

function Warrior:Refresh()
	self:UpdateCoins()
	self:UpdateCaption()
	self:UpdateWord()
	Sign.setNext(self, self:NextPress())
end

function Warrior:OnEnable()
	if not self:Active() then return end
	local halo = Stoa.modules.Halo
	if not (halo and halo.frame) then return end
	self.coins = Sign.buildCoins(halo.frame)
	self.caption = Sign.buildCaption(halo.frame)
	self.word = Sign.buildWord(halo.frame, "TAUNT")
	self.casts = Sign.casts()
	Sign.wire(self)
end
