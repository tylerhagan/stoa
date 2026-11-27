-- Stoa: the Hunter signatures.
--   Coins on the Halo's right for Hunter's Mark (M) and Serpent Sting (S)
--   on the target and Rapid Fire (RF) on you.
--   NO ASPECT under them when none of your aspects is up, in the danger
--   colour: forgetting one is a word, not a missing buff icon. Your pet
--   has its own plaque, arc and words (Pet.lua); Mongoose Bite and
--   Counterattack are procs (Procs.lua).
--   Next press (Warcraft Tavern's Forever guides, 2026-11-26): Serpent
--   Sting and Hunter's Mark when they're down; in melee Raptor Strike,
--   Mongoose Bite and Strider Kick; then Summon Hawk, Sniper Shot, Aimed
--   Shot and Arcane Shot as they come ready, then Rapid Fire and Bestial
--   Wrath. Each only once you know it.
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
	-- An aspect cast in a fight counts as up from then on.
	for _, key in ipairs(ASPECTS) do
		if name == nameOf(key) then self.aspectOn = true end
	end
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
				state[key] = Sign.debuff(self.coins[index], letter, nameOf(key), self.casts, key, Sign.length(SPELLS[key], LENGTHS[key]))
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
-- The game can keep your own buffs from being read by name in a fight, so
-- an aspect is looked for three ways (as a stance, by its spell, by its
-- name), and what was last seen out of a fight stands in when none of
-- them answers during one.
local function aspectSeen(key)
	local id = SPELLS[key]
	if C_UnitAuras and C_UnitAuras.GetPlayerAuraBySpellID then
		local ok, aura = pcall(C_UnitAuras.GetPlayerAuraBySpellID, id)
		if ok and aura then return true end
	end
	return Sign.aura("player", nameOf(key), "HELPFUL") ~= nil
end

function Hunter:AspectUp()
	local known, seen = false, false
	for _, key in ipairs(ASPECTS) do
		if Sign.knows(SPELLS[key]) then
			known = true
			if aspectSeen(key) then seen = true break end
		end
	end
	if not known then return nil end
	if not seen and GetShapeshiftForm then
		local form = GetShapeshiftForm()
		if not Stoa:IsSecret(form) and form and form > 0 then seen = true end
	end
	if seen then
		self.aspectOn = true
	elseif not InCombatLockdown() then
		self.aspectOn = false
	end
	return self.aspectOn and true or false
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

-- Forever's newer shots are found by name.
local MELEE = { "Mongoose Bite", "Strider Kick" }
local SHOTS = { "Summon Hawk", "Sniper Shot", "Aimed Shot" }
local LAST = { "Rapid Fire", "Bestial Wrath" }

local function first(list)
	for _, name in ipairs(list) do
		if Sign.can(name) then return C_Spell.GetSpellName(Sign.spell(name)) end
	end
end

function Hunter:NextPress()
	if not Sign.hostileTarget() then return nil end
	local state = self.state or {}
	if state.serpentSting == "off" then return nameOf("serpentSting") end
	if state.mark == "off" then return nameOf("mark") end
	if Stoa:GetRole() == "MELEE" and Sign.knows(SPELLS.raptorStrike) then
		if Sign.ready(SPELLS.raptorStrike) ~= false then return nameOf("raptorStrike") end
		local melee = first(MELEE)
		if melee then return melee end
	end
	local shot = first(SHOTS)
	if shot then return shot end
	if Sign.knows(SPELLS.arcaneShot) and Sign.ready(SPELLS.arcaneShot) then return nameOf("arcaneShot") end
	return first(LAST) or Sign.assisted() or (Sign.knows(SPELLS.arcaneShot) and nameOf("arcaneShot")) or nil
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
