-- Stoa: mana, as the game spends and returns it.
-- Spirit returns mana every two seconds, but only once five seconds have
-- passed since you last spent any (the "five-second rule"). Knowing both is
-- the heart of playing a mana class well, so this keeps track of them for
-- any frame that wants to show them: the Halo's arc, the console bar.
--
-- The rule starts on any cast that cost mana. Ticks are found by watching
-- mana rise while the rule is quiet; when mana can't be read (secret in
-- combat) the rule still runs from your casts, and the tick is left out.
local _, ns = ...
local Stoa = ns.Stoa

local Power = {}
Stoa.Power = Power

local RULE_SECONDS = 5
local TICK_SECONDS = 2

local MANA = Enum and Enum.PowerType and Enum.PowerType.Mana or 0

local lastSpend, lastTick, lastMana = 0, nil, nil

local function call(fn, ...)
	if type(fn) ~= "function" then return nil end
	local ok, a, b = pcall(fn, ...)
	if ok then return a, b end
end

-- Mana and its maximum as plain numbers, whatever form you're in, or nil
-- when the game keeps them hidden.
function Power.mana()
	local current = Stoa:PlainNumber(call(UnitPower, "player", MANA))
	local max = Stoa:PlainNumber(call(UnitPowerMax, "player", MANA))
	if current and max and max > 0 then return current, max end
end

-- True when you have mana but your bar shows something else: a druid in
-- cat or bear form.
function Power.manaHidden()
	local kind = Stoa:PlainNumber((call(UnitPowerType, "player")))
	if kind == nil or kind == MANA then return false end
	local max = Stoa:PlainNumber(call(UnitPowerMax, "player", MANA))
	return max ~= nil and max > 0
end

function Power.usesMana()
	local max = Stoa:PlainNumber(call(UnitPowerMax, "player", MANA))
	return max ~= nil and max > 0
end

-- Seconds until spirit regen returns, 0 once it has.
function Power.ruleLeft()
	return math.max(0, lastSpend + RULE_SECONDS - GetTime())
end

-- Seconds to the next regen tick, or nil when ticks aren't known (just
-- logged in, mana hidden) or you're still inside the rule.
function Power.nextTick()
	if not lastTick or Power.ruleLeft() > 0 then return nil end
	local now = GetTime()
	local since = (now - lastTick) % TICK_SECONDS
	return TICK_SECONDS - since
end

-- The mana the spell you're casting will take, or nil.
function Power.castCost()
	local _, _, _, _, _, _, _, _, spellID = call(UnitCastingInfo, "player")
	spellID = Stoa:PlainNumber(spellID)
	if not spellID then return nil end
	return Stoa.Spells and Stoa.Spells.cost(spellID, MANA)
end

Power.RULE_SECONDS = RULE_SECONDS
Power.TICK_SECONDS = TICK_SECONDS

Stoa:On("UNIT_SPELLCAST_SUCCEEDED", function(unit, _, spellID)
	if unit ~= "player" then return end
	spellID = Stoa:PlainNumber(spellID)
	local cost = spellID and Stoa.Spells and Stoa.Spells.cost(spellID, MANA)
	if cost and cost > 0 then
		lastSpend = GetTime()
		Stoa:Fire("STOA_POWER_RULE", RULE_SECONDS)
	end
end)

local function watch(unit, kind)
	if unit ~= "player" or (kind and kind ~= "MANA") then return end
	local current = Power.mana()
	if current and lastMana and current > lastMana and Power.ruleLeft() == 0 then
		lastTick = GetTime()
		Stoa:Fire("STOA_POWER_TICK")
	elseif current and lastMana and current < lastMana and Power.ruleLeft() == 0 then
		-- Spending outside a cast we saw (a channel tick, a proc): the rule
		-- starts here too.
		lastSpend = GetTime()
		Stoa:Fire("STOA_POWER_RULE", RULE_SECONDS)
	end
	lastMana = current
end

Stoa:On("UNIT_POWER_FREQUENT", watch)
Stoa:On("UNIT_POWER_UPDATE", watch)
Stoa:On("PLAYER_ENTERING_WORLD", function()
	lastMana = Power.mana()
end)
