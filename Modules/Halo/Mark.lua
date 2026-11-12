-- Stoa: the class mark.
-- One buff per class you keep up, drawn like the shield (a painted silver emblem that
-- empties) at the top of the medallion beside the shield and under the
-- Halo's power number:
--   Warrior: Battle Shout, a horn, emptying as its two minutes run.
--   Rogue: Slice and Dice, a dagger, emptying as it runs.
--   Paladin: your seal, emptying over its thirty seconds.
--   Shaman: Lightning or Water Shield, an orb, one step per charge.
--   Priest: Inner Fire, a flame, one step per charge.
-- It shows while the buff is up. Inner Fire, and a seal in a fight, show
-- empty and dimmed when they're missing, in place of the warning words. In a fight the game hides buff times and
-- charges, so timers run from your own cast, and charges hold at the last
-- count seen (a charge spent mid-fight shows once the fight ends).
local _, ns = ...
local Stoa = ns.Stoa
local UI = Stoa.UI
local Sign = Stoa.Sign

local Mark = {}
Stoa.Mark = Mark

local ART = UI.MEDIA .. "Textures\\Mark"

-- Forever's guides don't give every number yet; these are the classic
-- ones, and wherever the game shows a buff's own length, that wins.
local MARKS = {
	WARRIOR = { art = "Horn", kind = "timer", spell = 6673, length = 120 },
	ROGUE = { art = "Dagger", kind = "timer", spell = 5171, length = 21 },
	PALADIN = { art = "Seal", kind = "seal", length = 30, remind = "combat" },
	SHAMAN = { art = "Orb", kind = "charges", spells = { 24398, 324 }, charges = 3 },
	PRIEST = { art = "Flame", kind = "charges", spell = 588, charges = 20, remind = "always" },
}

local gauges, listeners = {}, {}
local castAt = {} -- spell name -> when you last cast it
local lastSeal -- { name, at }
local seen = {} -- spell name -> last share seen, for a fight that hides charges
local most = {} -- spell name -> the most charges seen

local function mark()
	local _, classFile = UnitClass("player")
	return MARKS[classFile]
end

local function spellName(id)
	return id and C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(id)
end

local function clamp(share)
	return math.max(0, math.min(1, share))
end

-- A timed buff: the aura's own time where the game shows it, else your
-- cast. Returns the share left, or nil when it isn't up.
local function timed(name, length, cast)
	local aura = Sign.aura("player", name, "HELPFUL")
	local left = Sign.left(aura)
	if left then
		local full = Stoa:PlainNumber(aura.duration)
		if not full or full <= 0 then full = length end
		return clamp(left / full)
	end
	if cast and GetTime() - cast < length then return clamp((cast + length - GetTime()) / length) end
	if aura then return 1 end
end

-- A buff with charges: its stacks where shown, else the last count seen.
local function charged(name, charges)
	local aura = Sign.aura("player", name, "HELPFUL")
	local stacks = Sign.stacks(aura)
	if stacks then
		most[name] = math.max(most[name] or charges, stacks)
		seen[name] = clamp(stacks / most[name])
		return seen[name], true
	end
	if aura or Sign.inCombat() then return seen[name], true end
	seen[name] = nil
end

-- The share left and whether a change should glide, or nil to hide.
local function share(def)
	if def.kind == "timer" then
		if not Sign.knows(def.spell) then return nil end
		local name = spellName(def.spell)
		return name and timed(name, def.length, castAt[name])
	elseif def.kind == "seal" then
		local paladin = Stoa.modules.Paladin
		if paladin and paladin.Seal and paladin.enabled then
			local ok, name, ends = pcall(paladin.Seal, paladin)
			if not ok then return nil end
			if ends then return clamp((ends - GetTime()) / def.length) end
			return name and 1 or nil
		end
		if lastSeal then return timed(lastSeal.name, def.length, lastSeal.at) end
	elseif def.kind == "charges" then
		for _, id in ipairs(def.spells or { def.spell }) do
			local name = Sign.knows(id) and spellName(id)
			if name then
				local value, glide = charged(name, def.charges)
				if value then return value, glide end
			end
		end
	end
end

-- Whether the buff this mark reminds you of is missing: known, not up,
-- and readable (a fight that hides buffs can't tell missing from hidden,
-- except for a seal, which is read from your casts).
local function missing(def)
	if not def.remind then return false end
	local fighting = Sign.inCombat()
	if def.remind == "combat" then return fighting end
	if fighting or Stoa:AurasHidden() then return false end
	return def.spell and Sign.knows(def.spell) or false
end

local function update()
	local def = mark()
	local value, glide, empty
	if def then value, glide = share(def) end
	if def and not value and missing(def) then value, glide, empty = 0, false, true end
	for gauge, onShown in pairs(gauges) do
		local was = gauge:IsShown()
		if value then
			gauge:SetShare(value, glide)
			gauge:SetMissing(empty)
			gauge:Show()
		else
			gauge:Hide()
		end
		if was ~= gauge:IsShown() and onShown ~= true then onShown() end
	end
	return value
end

local driver
local function wire()
	driver = CreateFrame("Frame")
	local wait = 0
	-- Timers drain between events, so they're set a few times a second.
	driver:SetScript("OnUpdate", function(_, elapsed)
		wait = wait - elapsed
		if wait > 0 then return end
		wait = 0.1
		local def = mark()
		if def and def.kind ~= "charges" then update() end
	end)
	Stoa:OnUnit("UNIT_SPELLCAST_SUCCEEDED", { "player" }, function(_, _, spellID)
		if not spellID or Stoa:IsSecret(spellID) then return end
		local name = spellName(spellID)
		if not name then return end
		castAt[name] = GetTime()
		if name:sub(1, 8) == "Seal of " then lastSeal = { name = name, at = GetTime() } end
		-- A fresh cast refills the charges, whatever the fight hides.
		if seen[name] ~= nil or Sign.inCombat() then seen[name] = 1 end
		update()
	end)
	Stoa:OnUnit("UNIT_AURA", { "player" }, update)
	for _, event in ipairs({ "PLAYER_ENTERING_WORLD", "SPELLS_CHANGED", "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED" }) do
		Stoa:On(event, update)
	end
end

-- Whether this character has a mark at all.
function Mark.has()
	return mark() ~= nil
end

-- A mark on `parent`, kept up to date. `onShown` runs when it appears or
-- goes, for a parent that lays it out beside something else.
function Mark.attach(parent, size, onShown)
	local def = mark()
	if not def then return nil end
	local gauge = UI.markGauge(parent, size, ART .. def.art)
	gauges[gauge] = onShown or true
	if not driver then wire() end
	update()
	return gauge
end
