-- Stoa: the Hunter signatures.
--   Coins on the Halo's right for Hunter's Mark (M) and Serpent Sting (S)
--   on the target and Rapid Fire (RF) on you.
--   NO ASPECT under them when none of your aspects is up, in the danger
--   colour: forgetting one is a word, not a missing buff icon. Your pet
--   has its own plaque, arc and words (Pet.lua); Mongoose Bite and
--   Counterattack are procs (Procs.lua).
--   Next press: Mark and Sting when they're down, then the game's own
--   suggestion or Arcane Shot.
--
-- Forever's guides don't give every number yet, so the timers below are
-- the classic ones; wherever the game shows them, its own wins.
local _, ns = ...
local Stoa = ns.Stoa
local Sign = Stoa.Sign

local Hunter = Stoa:NewModule("Hunter", {})

local SPELLS = {
	mark = 1130,
	serpentSting = 1978,
	rapidFire = 3045,
	arcaneShot = 3044,
	raptorStrike = 2973,
	aspectHawk = 13165,
	aspectMonkey = 13163,
	aspectCheetah = 5118,
	aspectPack = 13159,
	aspectBeast = 13161,
	aspectWild = 20043,
}
local nameOf = Sign.names(SPELLS)
local ASPECTS = { "aspectHawk", "aspectMonkey", "aspectCheetah", "aspectPack", "aspectBeast", "aspectWild" }

local LENGTHS = { mark = 120, serpentSting = 15 }
local COOLDOWNS = { rapidFire = 300 }

function Hunter:Active()
	local _, classFile = UnitClass("player")
	return classFile == "HUNTER"
end

function Hunter:NoteCast(name)
	for key in pairs(SPELLS) do
		if name == nameOf(key) then self.casts:Note(key, key == "mark" or key == "serpentSting") end
	end
end

-- Coins --------------------------------------------------------------------------

function Hunter:UpdateCoins()
	local state, index = {}, 0
	if Sign.hostileTarget() then
		for _, entry in ipairs({ { "mark", "M" }, { "serpentSting", "S" } }) do
			local key, letter = entry[1], entry[2]
			if Sign.knows(SPELLS[key]) then
				index = index + 1
				state[key] = Sign.debuff(self.coins[index], letter, nameOf(key), self.casts, key, LENGTHS[key])
			end
		end
	end
	if Sign.knows(SPELLS.rapidFire) then
		index = index + 1
		local active = Sign.aura("player", nameOf("rapidFire"), "HELPFUL") ~= nil
		state.rapidFire = Sign.cooldown(self.coins[index], "RF", SPELLS.rapidFire, self.casts:Last("rapidFire"), COOLDOWNS.rapidFire, active)
	end
	Sign.hideFrom(self.coins, index + 1)
	self.state = state
end

-- Whether one of your aspects is up; nil when you know none yet.
function Hunter:AspectUp()
	local known = false
	for _, key in ipairs(ASPECTS) do
		if Sign.knows(SPELLS[key]) then
			known = true
			if Sign.aura("player", nameOf(key), "HELPFUL") then return true end
		end
	end
	if not known then return nil end
	return false
end

function Hunter:UpdateCaption()
	if Sign.inCombat() and self:AspectUp() == false then
		self.caption:SetText("NO ASPECT")
		self.caption:SetTextColor(Stoa:Color("danger"))
	else
		self.caption:SetText("")
	end
end

-- Next press ---------------------------------------------------------------------

function Hunter:NextPress()
	if not Sign.hostileTarget() then return nil end
	local state = self.state or {}
	if state.mark == "off" then return nameOf("mark") end
	if state.serpentSting == "off" then return nameOf("serpentSting") end
	local melee = Stoa:GetRole() == "MELEE"
	if melee and Sign.knows(SPELLS.raptorStrike) and Sign.ready(SPELLS.raptorStrike) ~= false then
		return Sign.assisted() or nameOf("raptorStrike")
	end
	return Sign.assisted() or (Sign.knows(SPELLS.arcaneShot) and nameOf("arcaneShot")) or nil
end

-- Lifecycle ----------------------------------------------------------------------

function Hunter:Refresh()
	self:UpdateCoins()
	self:UpdateCaption()
	Sign.setNext(self, self:NextPress())
end

function Hunter:OnEnable()
	if not self:Active() then return end
	local halo = Stoa.modules.Halo
	if not (halo and halo.frame) then return end
	self.coins = Sign.buildCoins(halo.frame)
	self.caption = Sign.buildCaption(halo.frame)
	self.casts = Sign.casts()
	Sign.wire(self)
end
