-- Stoa: the Rogue signatures.
--   Coins on the Halo's right for Slice and Dice (S) on you, Rupture (R)
--   on the target and your big cooldown: Adrenaline Rush (A), else Blade
--   Flurry (BF), else Evasion (E).
--   COMBO n under them, pale gold at five; Stoa hides the game's player
--   and target frames, which is where it draws combo points.
--   Next press: Slice and Dice when it's down and you have a point,
--   Rupture or Eviscerate at five, else the game's own suggestion or
--   Sinister Strike. Riposte is a proc (Procs.lua).
--
-- Slice and Dice and Rupture last longer per point; the lengths below are
-- the five-point classic ones for when the game hides the timer.
local _, ns = ...
local Stoa = ns.Stoa
local Sign = Stoa.Sign

local Rogue = Stoa:NewModule("Rogue", {})

local SPELLS = {
	sliceAndDice = 5171,
	rupture = 1943,
	eviscerate = 2098,
	sinisterStrike = 1752,
	adrenalineRush = 13750,
	bladeFlurry = 13877,
	evasion = 5277,
	stealth = 1784,
}
local nameOf = Sign.names(SPELLS)

local LENGTHS = { sliceAndDice = 21, rupture = 16 }
local COOLDOWNS = { adrenalineRush = 300, bladeFlurry = 120, evasion = 300 }
local MAX_POINTS = 5

function Rogue:Active()
	local _, classFile = UnitClass("player")
	return classFile == "ROGUE"
end

function Rogue:NoteCast(name)
	for key in pairs(SPELLS) do
		if name == nameOf(key) then self.casts:Note(key, key == "rupture") end
	end
end

-- Coins --------------------------------------------------------------------------

local BIG = { { "adrenalineRush", "A" }, { "bladeFlurry", "BF" }, { "evasion", "E" } }

function Rogue:UpdateCoins()
	local state, index = {}, 0
	if Sign.knows(SPELLS.sliceAndDice) then
		index = index + 1
		state.sliceAndDice = Sign.buff(self.coins[index], "S", nameOf("sliceAndDice"), self.casts, "sliceAndDice", LENGTHS.sliceAndDice)
	end
	if Sign.knows(SPELLS.rupture) and Sign.hostileTarget() then
		index = index + 1
		state.rupture = Sign.debuff(self.coins[index], "R", nameOf("rupture"), self.casts, "rupture", LENGTHS.rupture)
	end
	for _, entry in ipairs(BIG) do
		local key, letter = entry[1], entry[2]
		if Sign.knows(SPELLS[key]) then
			index = index + 1
			local active = Sign.aura("player", nameOf(key), "HELPFUL") ~= nil
			state[key] = Sign.cooldown(self.coins[index], letter, SPELLS[key], self.casts:Last(key), COOLDOWNS[key], active)
			break
		end
	end
	Sign.hideFrom(self.coins, index + 1)
	self.state = state
end

function Rogue:UpdateCaption()
	local points = Sign.inCombat() and Sign.comboPoints() or nil
	if points and points > 0 then
		self.caption:SetText("COMBO " .. points)
		self.caption:SetTextColor(Stoa:Color(points >= MAX_POINTS and "accent" or "text"))
	else
		self.caption:SetText("")
	end
end

-- Next press ---------------------------------------------------------------------

function Rogue:NextPress()
	if not Sign.hostileTarget() then return nil end
	local state = self.state or {}
	local points = Sign.comboPoints() or 0
	if points >= 1 and state.sliceAndDice == "off" and Sign.knows(SPELLS.sliceAndDice) then return nameOf("sliceAndDice") end
	if points >= MAX_POINTS then
		if state.rupture == "off" and Sign.knows(SPELLS.rupture) then return nameOf("rupture") end
		if Sign.knows(SPELLS.eviscerate) then return nameOf("eviscerate") end
	end
	return Sign.assisted() or nameOf("sinisterStrike")
end

-- Lifecycle ----------------------------------------------------------------------

function Rogue:Refresh()
	self:UpdateCoins()
	self:UpdateCaption()
	Sign.setNext(self, self:NextPress())
end

function Rogue:OnEnable()
	if not self:Active() then return end
	local halo = Stoa.modules.Halo
	if not (halo and halo.frame) then return end
	self.coins = Sign.buildCoins(halo.frame)
	self.caption = Sign.buildCaption(halo.frame)
	self.casts = Sign.casts()
	Stoa:OnUnit("UNIT_POWER_UPDATE", { "player" }, function() xpcall(self.UpdateCaption, Stoa.catch, self) end)
	Sign.wire(self)
end
