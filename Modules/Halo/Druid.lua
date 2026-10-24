-- Stoa: the Druid signatures.
-- A druid's spec is half its form, so the signature follows the form you
-- are in first and your role second: Bear Form shows the tank's, Cat Form
-- the cat's, and otherwise Balance for Ranged and Restoration for Healer.
--   Balance: coins M (Moonfire) and I (Insect Swarm) on the target; LUNAR
--     or SOLAR under them while an Eclipse is up, and CLEARCAST; the next
--     press follows the guides' two Starfires to one Wrath, or whichever
--     spell the Eclipse favours.
--   Cat: coins R (Rip), K (Rake) and F (Faerie Fire) on the target, your
--     combo points under them, Shred outlined on Clearcasting.
--   Bear: coins L (Lacerate, its stacks under it), D (Demoralizing Roar)
--     and F (Faerie Fire); TAUNT over the ring when your target is on
--     someone else in a group, with Growl outlined.
--   Restoration: coins S (Swiftmend), W (Wild Growth) and N (Nature's
--     Swiftness); REJUV n and REGROWTH n count yours on the group, and
--     Healing Touch is outlined while Nature's Swiftness or Clearcasting
--     is up.
-- Out of the form your role wants in a fight, its name shows over the ring.
--
-- Forever's guides don't give durations yet, so the timers below are the
-- classic ones; wherever the game shows the aura, its own time wins.
local _, ns = ...
local Stoa = ns.Stoa
local Sign = Stoa.Sign

local Druid = Stoa:NewModule("Druid", {})

local SPELLS = {
	moonfire = 8921,
	insectSwarm = 5570,
	wrath = 5176,
	starfire = 2912,
	moonkin = 24858,
	faerieFire = 770,
	faerieFeral = 16857,
	rake = 1822,
	rip = 1079,
	shred = 5221,
	claw = 1082,
	bite = 22568,
	tigersFury = 5217,
	berserk = 417141,
	shiftingPower = 1322605,
	catForm = 768,
	bearForm = 5487,
	lacerate = 1235827,
	primalBite = 407995,
	maul = 6807,
	demoRoar = 99,
	growl = 6795,
	rejuvenation = 774,
	regrowth = 8936,
	healingTouch = 5185,
	wildGrowth = 1238215,
	swiftmend = 18562,
	swiftness = 17116,
	clearcasting = 16870,
}
local nameOf = Sign.names(SPELLS)

-- English names for the Eclipse buffs, until their Forever IDs are known.
local LUNAR, SOLAR = "Lunar Eclipse", "Solar Eclipse"

local DURATIONS = {
	moonfire = 12, insectSwarm = 12, faerieFire = 40, faerieFeral = 40,
	rake = 9, rip = 12, lacerate = 15, demoRoar = 30,
}
local COOLDOWNS = { swiftmend = 15, wildGrowth = 6, swiftness = 180 }
local LACERATE_MAX = 5
-- Shifting Power is for when energy runs low.
local LOW_ENERGY = 60

function Druid:Mode()
	local _, classFile = UnitClass("player")
	if classFile ~= "DRUID" then return nil end
	local form = Sign.form()
	if form == "bear" then return "bear" end
	if form == "cat" then return "cat" end
	local role = Stoa:GetRole()
	if role == "RANGED" then return "balance" end
	if role == "HEALER" then return "resto" end
	if role == "TANK" then return "bear" end
	if role == "MELEE" then return "cat" end
end

function Druid:Active()
	return self:Mode() ~= nil
end

-- Faerie Fire is cast from forms as its feral version; either counts.
local function faerieKey()
	if Sign.form() and Sign.knows(SPELLS.faerieFeral) then return "faerieFeral" end
	return "faerieFire"
end

local function clearcasting()
	return Sign.aura("player", nameOf("clearcasting") or "Clearcasting", "HELPFUL") ~= nil
end

-- Casts -------------------------------------------------------------------------

local ON_TARGET = { moonfire = true, insectSwarm = true, faerieFire = true, faerieFeral = true, rake = true, rip = true, lacerate = true, demoRoar = true }

function Druid:NoteCast(name)
	for key in pairs(SPELLS) do
		if name == nameOf(key) then
			self.casts:Note(key, ON_TARGET[key])
			if key == "lacerate" then
				local record = self.lacerate
				local who = Sign.targetKey()
				if record and record.who == who and GetTime() - record.at < DURATIONS.lacerate then
					record.stacks = math.min(record.stacks + 1, LACERATE_MAX)
				else
					record = { who = who, stacks = 1 }
				end
				record.at = GetTime()
				self.lacerate = record
			elseif key == "starfire" then
				self.starfires = (self.starfires or 0) + 1
			elseif key == "wrath" then
				self.starfires = 0
			end
		end
	end
end

-- Lacerate's stacks on your target: the aura's own count when shown, else
-- counted from your casts.
function Druid:LacerateStacks(aura)
	local stacks = Sign.stacks(aura)
	if stacks then return stacks end
	local record = self.lacerate
	if record and record.who == Sign.targetKey() and GetTime() - record.at < DURATIONS.lacerate then
		return record.stacks
	end
	return aura and 1 or 0
end

-- Coins --------------------------------------------------------------------------

function Druid:Debuff(index, letter, key)
	local coin = self.coins[index]
	return Sign.debuff(coin, letter, nameOf(key), self.casts, key, DURATIONS[key])
end

function Druid:Cooldown(index, letter, key, active)
	return Sign.cooldown(self.coins[index], letter, SPELLS[key], self.casts:Last(key), COOLDOWNS[key], active)
end

function Druid:UpdateCoins(mode)
	local state, index = {}, 0
	local function add(key, fn)
		if not Sign.knows(SPELLS[key]) then return end
		index = index + 1
		state[key] = fn(index)
	end
	local hostile = Sign.hostileTarget()
	if mode == "balance" and hostile then
		add("moonfire", function(i) return self:Debuff(i, "M", "moonfire") end)
		add("insectSwarm", function(i) return self:Debuff(i, "I", "insectSwarm") end)
	elseif mode == "cat" and hostile then
		add("rip", function(i) return self:Debuff(i, "R", "rip") end)
		add("rake", function(i) return self:Debuff(i, "K", "rake") end)
		local ff = faerieKey()
		add(ff, function(i) return self:Debuff(i, "F", ff) end)
		state.faerie = state[ff]
	elseif mode == "bear" and hostile then
		add("lacerate", function(i)
			local result, aura = self:Debuff(i, "L", "lacerate")
			self.stacks = result ~= "off" and self:LacerateStacks(aura) or 0
			return result
		end)
		add("demoRoar", function(i) return self:Debuff(i, "D", "demoRoar") end)
		local ff = faerieKey()
		add(ff, function(i) return self:Debuff(i, "F", ff) end)
		state.faerie = state[ff]
	elseif mode == "resto" then
		add("swiftmend", function(i) return self:Cooldown(i, "S", "swiftmend") end)
		add("wildGrowth", function(i) return self:Cooldown(i, "W", "wildGrowth") end)
		add("swiftness", function(i)
			return self:Cooldown(i, "N", "swiftness", Sign.aura("player", nameOf("swiftness"), "HELPFUL") ~= nil)
		end)
	end
	Sign.hideFrom(self.coins, index + 1)
	self.state = state
end

function Druid:UpdateCaption(mode)
	local parts = {}
	local inCombat = Sign.inCombat()
	if inCombat and mode == "balance" then
		if Sign.aura("player", LUNAR, "HELPFUL") then parts[#parts + 1] = "LUNAR" end
		if Sign.aura("player", SOLAR, "HELPFUL") then parts[#parts + 1] = "SOLAR" end
	elseif inCombat and mode == "cat" then
		local points = Sign.comboPoints()
		if points and points > 0 then parts[#parts + 1] = "COMBO " .. points end
	elseif inCombat and mode == "bear" then
		if self.state and self.state.lacerate and self.state.lacerate ~= "off" then
			parts[#parts + 1] = ("LACERATE %d"):format(self.stacks or 1)
		end
	elseif inCombat and mode == "resto" then
		if Sign.knows(SPELLS.rejuvenation) then parts[#parts + 1] = "REJUV " .. Sign.countOnGroup(nameOf("rejuvenation")) end
		if Sign.knows(SPELLS.regrowth) then parts[#parts + 1] = "REGROWTH " .. Sign.countOnGroup(nameOf("regrowth")) end
	end
	if inCombat and mode and clearcasting() then parts[#parts + 1] = "CLEARCAST" end
	self.caption:SetText(table.concat(parts, "  "))
	self.caption:SetTextColor(Stoa:Color("accent"))
end

-- The form your role wants in a fight, by name over the ring when you're
-- out of it.
local WANTED_FORM = { TANK = { "bear", "bearForm" }, MELEE = { "cat", "catForm" }, RANGED = { "moonkin", "moonkin" } }

function Druid:UpdateWord(mode)
	local word = self.word
	local wanted = WANTED_FORM[Stoa:GetRole()]
	if mode and wanted and Sign.inCombat() and Sign.knows(SPELLS[wanted[2]]) and Sign.form() ~= wanted[1] then
		word:SetText((nameOf(wanted[2]) or ""):upper())
		word:SetTextColor(Stoa:Color("danger"))
		word:Show()
	elseif mode == "bear" and Sign.inCombat() and Sign.knows(SPELLS.growl) and Sign.wantsTaunt() then
		word:SetText("TAUNT")
		word:SetTextColor(Stoa:Color("danger"))
		word:Show()
	else
		word:Hide()
	end
end

-- Next press ---------------------------------------------------------------------

local function usable(key)
	return Sign.knows(SPELLS[key]) and Sign.ready(SPELLS[key]) ~= false
end

function Druid:NextPress(mode)
	local state = self.state or {}
	if mode == "resto" then
		local swift = Sign.aura("player", nameOf("swiftness"), "HELPFUL")
		if (swift or clearcasting()) and Sign.knows(SPELLS.healingTouch) then return nameOf("healingTouch") end
		return nil
	end
	if not Sign.hostileTarget() then return nil end
	if mode == "balance" then
		if state.moonfire == "off" then return nameOf("moonfire") end
		if state.insectSwarm == "off" then return nameOf("insectSwarm") end
		local starfire = Sign.knows(SPELLS.starfire)
		if starfire and (Sign.aura("player", LUNAR, "HELPFUL") or clearcasting()) then return nameOf("starfire") end
		if Sign.aura("player", SOLAR, "HELPFUL") then return nameOf("wrath") end
		if not starfire then return nameOf("wrath") end
		return (self.starfires or 0) >= 2 and nameOf("wrath") or nameOf("starfire")
	elseif mode == "cat" then
		if state.faerie == "off" then return nameOf(faerieKey()) end
		local shred = Sign.knows(SPELLS.shred) and "shred" or "claw"
		if clearcasting() then return nameOf(shred) end
		local energy = Sign.power()
		if energy and energy < LOW_ENERGY and usable("shiftingPower") then return nameOf("shiftingPower") end
		local points = Sign.comboPoints() or 0
		if points >= 5 and state.rip == "off" then return nameOf("rip") end
		if points >= 5 and Sign.knows(SPELLS.bite) then return nameOf("bite") end
		if state.rake == "off" then return nameOf("rake") end
		return nameOf(shred)
	elseif mode == "bear" then
		if Sign.wantsTaunt() and usable("growl") then return nameOf("growl") end
		if state.demoRoar == "off" then return nameOf("demoRoar") end
		if state.faerie == "off" then return nameOf(faerieKey()) end
		if Sign.knows(SPELLS.lacerate) and (state.lacerate == "off" or state.lacerate == "ending" or (self.stacks or 0) < LACERATE_MAX) then
			return nameOf("lacerate")
		end
		if usable("primalBite") and Sign.ready(SPELLS.primalBite) then return nameOf("primalBite") end
		return Sign.assisted() or nameOf("maul")
	end
end

-- Lifecycle ----------------------------------------------------------------------

function Druid:Refresh()
	local mode = self:Mode()
	self:UpdateCoins(mode)
	self:UpdateCaption(mode)
	self:UpdateWord(mode)
	Sign.setNext(self, mode and self:NextPress(mode))
end

function Druid:OnEnable()
	local _, classFile = UnitClass("player")
	if classFile ~= "DRUID" then return end
	local halo = Stoa.modules.Halo
	if not (halo and halo.frame) then return end
	self.coins = Sign.buildCoins(halo.frame)
	self.caption = Sign.buildCaption(halo.frame)
	self.word = Sign.buildWord(halo.frame)
	self.casts = Sign.casts()
	Sign.wire(self)
end
