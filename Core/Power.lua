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

local call = Stoa.safe.call

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

-- Dressing a mana bar -------------------------------------------------------
-- Three quiet extras any mana bar can wear, shared by the Halo's arc and the
-- console's bar so they behave the same:
--   a spark that travels the bar while the five-second rule runs, then
--     pulses at the fill edge on each regen tick;
--   a dark shade over the mana the spell being cast will spend;
--   a slim second bar for a druid's mana while a form shows another power.
-- opts: place(tex, f) puts a dot at fraction f (0-1) along the bar;
-- shade(tex, from, to) stretches the shade between two fractions;
-- enabled(key) says whether "manaRule", "castCost" or "formMana" is on;
-- form = { bar = StatusBar, show = function(current, max) , hide = function() }
-- is optional. Everything is hidden whenever mana can't be read (secret in
-- combat).
local PULSE_SECONDS = 0.5

function Power.dress(sb, opts)
	local UI = Stoa.UI
	local dress = {}
	local spark = UI.circle(sb, "OVERLAY", 2, 5, "text")
	spark:Hide()
	local shade = sb:CreateTexture(nil, "OVERLAY", nil, 1)
	shade:SetTexture(opts.texture or UI.WHITE)
	UI.tint(shade, "panel", 0.75)
	shade:Hide()
	local driver = CreateFrame("Frame", nil, sb)
	local pulseAt, casting = nil, false
	dress.spark, dress.shade, dress.driver = spark, shade, driver

	-- The bar shows mana itself (not a druid's form power).
	local function onMana()
		return Power.usesMana() and not Power.manaHidden()
	end

	-- Draws the spark for this instant; false once it has nothing to show,
	-- which lets the driver go quiet.
	local function sweep()
		if not (opts.enabled("manaRule") and onMana()) then spark:Hide() return false end
		local left = Power.ruleLeft()
		if left > 0 then
			opts.place(spark, 1 - left / RULE_SECONDS)
			spark:SetAlpha(0.7)
			spark:Show()
			return true
		end
		local age = pulseAt and GetTime() - pulseAt
		local current, max = Power.mana()
		if age and age < PULSE_SECONDS and current then
			opts.place(spark, current / max)
			spark:SetAlpha(0.8 * (1 - age / PULSE_SECONDS))
			spark:Show()
			return true
		end
		spark:Hide()
		return false
	end

	local function wake()
		if sweep() then
			driver:SetScript("OnUpdate", Stoa:GuardUpdate(function(self)
				if not sweep() then self:SetScript("OnUpdate", nil) end
			end))
		end
	end

	function dress.Cost()
		local current, max = Power.mana()
		local cost = casting and opts.enabled("castCost") and onMana() and Power.castCost()
		if current and max and cost and cost > 0 then
			opts.shade(shade, math.max(current - cost, 0) / max, current / max)
			shade:Show()
		else
			shade:Hide()
		end
	end

	function dress.Form()
		local form = opts.form
		if not form then return end
		local current, max = Power.mana()
		if opts.enabled("formMana") and Power.manaHidden() and current then
			form.bar:SetMinMaxValues(0, max)
			form.bar:SetValue(current)
			form.bar:Show()
			form.show(current)
		else
			form.bar:Hide()
			form.hide()
		end
	end

	-- For when a setting changes or the character does.
	function dress.Refresh()
		wake()
		dress.Cost()
		dress.Form()
	end

	Stoa:On("STOA_POWER_RULE", wake)
	Stoa:On("STOA_POWER_TICK", function()
		pulseAt = GetTime()
		wake()
	end)
	local function started() casting = true dress.Cost() end
	local function stopped() casting = false dress.Cost() end
	for _, event in ipairs({ "UNIT_SPELLCAST_START", "UNIT_SPELLCAST_DELAYED" }) do
		Stoa:OnUnit(event, { "player" }, started)
	end
	for _, event in ipairs({ "UNIT_SPELLCAST_STOP", "UNIT_SPELLCAST_FAILED",
		"UNIT_SPELLCAST_INTERRUPTED", "UNIT_SPELLCAST_SUCCEEDED", "UNIT_SPELLCAST_CHANNEL_START" }) do
		Stoa:OnUnit(event, { "player" }, stopped)
	end
	for _, event in ipairs({ "UNIT_DISPLAYPOWER", "UNIT_POWER_UPDATE", "UNIT_MAXPOWER" }) do
		Stoa:OnUnit(event, { "player" }, function() dress.Cost() dress.Form() end)
	end
	Stoa:On("PLAYER_ENTERING_WORLD", dress.Refresh)
	return dress
end
