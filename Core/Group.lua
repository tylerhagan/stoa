-- Stoa: your group, as a list of units.
-- Buff reminders and the threat meter walk the same group.
-- Stoa:GroupUnits() gives the units in order (you first), and
-- STOA_GROUP_CHANGED fires once when the group's make-up settles.
local _, ns = ...
local Stoa = ns.Stoa

local units = { "player" }

local function count(fn)
	local ok, n = pcall(fn)
	return ok and type(n) == "number" and n or 0
end

local function rebuild()
	wipe(units)
	if IsInRaid() then
		for i = 1, count(GetNumGroupMembers) do units[#units + 1] = "raid" .. i end
	else
		units[1] = "player"
		for i = 1, math.min(4, count(GetNumSubgroupMembers)) do units[#units + 1] = "party" .. i end
	end
end

-- The units in your group, you included. Don't change the list you get.
function Stoa:GroupUnits()
	return units
end

-- "solo", "party" or "raid".
function Stoa:GroupKind()
	if IsInRaid() then return "raid" end
	if IsInGroup() then return "party" end
	return "solo"
end

-- True when you lead the group or are an assistant in a raid, so raid
-- markers and countdowns are yours to use.
function Stoa:CanLead()
	if not IsInGroup() then return true end
	if UnitIsGroupLeader("player") then return true end
	return IsInRaid() and UnitIsGroupAssistant and UnitIsGroupAssistant("player") or false
end

local pending
local function changed()
	if pending then return end
	pending = true
	C_Timer.After(0.2, function()
		pending = false
		rebuild()
		Stoa:Fire("STOA_GROUP_CHANGED", Stoa:GroupKind())
	end)
end

Stoa:On("PLAYER_LOGIN", rebuild)
Stoa:On("GROUP_ROSTER_UPDATE", changed)
Stoa:On("PLAYER_ENTERING_WORLD", changed)

-- Your heals on the group, in a fight -----------------------------------------
-- Forever hides every unit's auras from addons in combat, so the party cards
-- and the Discipline count lose your Shield and Renew the moment a pull
-- starts. Your own casts still come through, so these are noted as you cast
-- them: who it went on (the card you clicked, the name the game sent, your
-- mouseover, your target, or yourself), and for how long. A shield that
-- breaks early still counts until its time is up. Out of combat the auras
-- are read as normal and this list is cleared.

local OWN_HEALS = {
	shield = { id = 17, english = "Power Word: Shield", lasts = 30, also = "ws" },
	renew = { id = 139, english = "Renew", lasts = 15 },
}
local LASTS = { ws = 15 }
local ledger = {}      -- [GUID] = { [key] = GetTime() it runs out }
local sentTo = {}      -- [castGUID] = GUID the game said it went to
local lastClick        -- { unit, at }: the card you clicked, just before the cast

local function plainString(value)
	if type(value) ~= "string" or Stoa:IsSecret(value) or value == "" then return nil end
	return value
end

local function keyFor(spellID)
	if spellID == nil or Stoa:IsSecret(spellID) then return nil end
	local name = C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(spellID)
	if Stoa:IsSecret(name) then return nil end
	for key, heal in pairs(OWN_HEALS) do
		if spellID == heal.id then return key end
		local spells = Stoa.Spells
		local own = spells and spells.localName and spells.localName(heal.id, heal.english) or heal.english
		if name and name == own then return key end
	end
end

-- A helpable unit's GUID, when the game will say.
local function guidOf(unit)
	if not unit then return nil end
	local ok, exists = pcall(UnitExists, unit)
	if not ok or exists ~= true then return nil end
	local okHelp, help = pcall(UnitCanAssist, "player", unit)
	if not okHelp or help ~= true then return nil end
	local okGuid, guid = pcall(UnitGUID, unit)
	guid = okGuid and plainString(guid)
	if guid then return guid end
	-- GUID hidden too: the group slot they're in stands in for it.
	for _, member in ipairs(units) do
		local same = member == unit
		if not same then
			local okSame, answer = pcall(UnitIsUnit, unit, member)
			same = okSame and answer == true
		end
		if same then return "slot:" .. member end
	end
end

-- The group member with this name (names are read before they turn secret).
local nameToGUID = {}
local function learnNames()
	local fresh = {}
	for _, unit in ipairs(units) do
		local ok, name, realm = pcall(UnitName, unit)
		name = ok and plainString(name)
		local guid = guidOf(unit)
		if name and guid then
			fresh[name] = guid
			realm = plainString(realm)
			if realm then fresh[name .. "-" .. realm] = guid end
		end
	end
	-- Names hidden (a fight already started): keep the list from before.
	if next(fresh) then nameToGUID = fresh end
end

local function note(castGUID, spellID)
	local key = keyFor(spellID)
	if not key then return end
	local now = GetTime()
	local guid
	if lastClick and now - lastClick.at < 1 then guid = guidOf(lastClick.unit) end
	guid = guid or (castGUID and sentTo[castGUID]) or guidOf("mouseover") or guidOf("target") or guidOf("player")
	if castGUID then sentTo[castGUID] = nil end
	if not guid then return end
	local heal = OWN_HEALS[key]
	local entry = ledger[guid] or {}
	ledger[guid] = entry
	entry[key] = now + heal.lasts
	if heal.also then entry[heal.also] = now + LASTS[heal.also] end
	Stoa:Fire("STOA_OWN_HEALS")
end

-- Seconds left on your heal (shield, renew, or ws for Weakened Soul) on this
-- unit, from your casts this fight; nil when there's none to go on.
function Stoa:OwnHealLeft(unit, key)
	local guid = guidOf(unit)
	local entry = guid and ledger[guid]
	local ends = entry and entry[key]
	if not ends then return nil end
	local left = ends - GetTime()
	if left <= 0 then entry[key] = nil return nil end
	return left
end

-- The unit a click-cast frame is for, noted just before its click casts.
function Stoa:NoteClickUnit(frame)
	local ok, unit = pcall(frame.GetAttribute, frame, "unit")
	unit = ok and plainString(unit) or frame.unit
	if unit then lastClick = { unit = unit, at = GetTime() } end
end

Stoa:OnUnit("UNIT_SPELLCAST_SENT", { "player" }, function(_, target, castGUID, spellID)
	if not keyFor(spellID) then return end
	target = plainString(target)
	castGUID = plainString(castGUID)
	if target and castGUID then sentTo[castGUID] = nameToGUID[target] end
end)
Stoa:OnUnit("UNIT_SPELLCAST_SUCCEEDED", { "player" }, function(_, castGUID, spellID)
	note(plainString(castGUID), spellID)
end)
Stoa:On("PLAYER_REGEN_ENABLED", function()
	wipe(ledger)
	wipe(sentTo)
	learnNames()
	Stoa:Fire("STOA_OWN_HEALS")
end)
Stoa:On("PLAYER_REGEN_DISABLED", learnNames)
Stoa:On("STOA_GROUP_CHANGED", learnNames)
