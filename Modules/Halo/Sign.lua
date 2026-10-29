-- Stoa: the signature kit.
-- What every spec signature is made of, so a new class is mostly a list of
-- its spells: coins on the Halo's right (a timer that drains, or a
-- cooldown that comes back), a caption under them, a large word over the
-- ring, and the outline on the combat bar's next press.
--
-- Aura details and cooldowns can be secret in combat. Lookups go by name
-- through the client, your own casts stand in for timers the game hides,
-- and anything unreadable shows less rather than guessing.
local _, ns = ...
local Stoa = ns.Stoa
local UI = Stoa.UI

local Sign = {}
Stoa.Sign = Sign

Sign.COIN = 26
Sign.RADIUS = 168
-- Right of the ring, clear of the target plaque above and the mana number
-- below. 0 = due right.
Sign.ANGLES = { 10, -12, -34 }
-- Below this many seconds left, a timer brightens as a heads-up.
Sign.ENDING = 3

function Sign.knows(spellID)
	if not spellID then return false end
	if IsPlayerSpell and IsPlayerSpell(spellID) then return true end
	return IsSpellKnown and IsSpellKnown(spellID) or false
end

-- A lookup from keys to spell names, read from the client once each so
-- the names match whatever language it runs in.
function Sign.names(spells)
	local cache = {}
	return function(key)
		if not cache[key] and spells[key] then
			local name = C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(spells[key])
			if name then cache[key] = name end
		end
		return cache[key]
	end
end

function Sign.aura(unit, name, filter)
	if not name or not (C_UnitAuras and C_UnitAuras.GetAuraDataBySpellName) then return nil end
	local ok, aura = pcall(C_UnitAuras.GetAuraDataBySpellName, unit, name, filter)
	if ok then return aura end
end

-- Seconds left on an aura, or nil when the times are hidden.
function Sign.left(aura)
	local expires = Stoa:PlainNumber(aura and aura.expirationTime)
	if not expires or expires == 0 then return nil end
	return expires - GetTime()
end

-- An aura's stacks, or nil when hidden.
function Sign.stacks(aura)
	return Stoa:PlainNumber(aura and aura.applications)
end

-- When a spell comes back and its cooldown's length; nil when it's ready.
-- The third value says whether the game would say at all.
function Sign.readyAt(spellID)
	local info = C_Spell and C_Spell.GetSpellCooldown and C_Spell.GetSpellCooldown(spellID)
	if type(info) ~= "table" then return nil, nil, false end
	local start, duration = Stoa:PlainNumber(info.startTime), Stoa:PlainNumber(info.duration)
	if not start or not duration then return nil, nil, false end
	if start == 0 or duration <= 1.5 then return nil, nil, true end
	return start + duration, duration, true
end

-- Whether a spell is off cooldown (the global cooldown aside), or nil when
-- the game won't say.
function Sign.ready(spellID)
	local ends, _, readable = Sign.readyAt(spellID)
	if not readable then return nil end
	return not ends or ends - GetTime() <= 0.3
end

function Sign.hostileTarget()
	if not UnitExists("target") then return false end
	local hostile = UnitCanAttack("player", "target")
	if Stoa:IsSecret(hostile) then return true end
	local dead = UnitIsDeadOrGhost("target")
	return hostile and not (not Stoa:IsSecret(dead) and dead)
end

function Sign.unitKey(unit)
	local guid = UnitGUID(unit)
	if guid and not Stoa:IsSecret(guid) then return guid end
end

function Sign.targetKey()
	return Sign.unitKey("target") or "target"
end

-- The game's own suggested next spell, by name, where it offers one.
function Sign.assisted()
	if not (C_AssistedCombat and C_AssistedCombat.GetNextCastSpell) then return nil end
	local ok, spellID = pcall(C_AssistedCombat.GetNextCastSpell, false)
	if ok and spellID and not Stoa:IsSecret(spellID) then
		return C_Spell.GetSpellName(spellID)
	end
end

function Sign.inCombat()
	return Stoa:GetState() == Stoa.STATE_COMBAT
end

-- The druid form you're in: "bear", "cat", "moonkin", "travel" or nil.
local FORMS = { [1] = "cat", [5] = "bear", [8] = "bear", [31] = "moonkin", [3] = "travel", [4] = "travel", [27] = "travel", [29] = "travel" }
function Sign.form()
	if not GetShapeshiftFormID then return nil end
	local id = GetShapeshiftFormID()
	if Stoa:IsSecret(id) then return nil end
	return id and FORMS[id] or nil
end

-- Building -----------------------------------------------------------------------

function Sign.buildCoins(halo)
	local coins = {}
	for i = 1, #Sign.ANGLES do
		local coin = CreateFrame("Frame", nil, halo)
		coin:SetSize(Sign.COIN, Sign.COIN)
		local angle = math.rad(Sign.ANGLES[i])
		coin:SetPoint("CENTER", halo, "CENTER", Sign.RADIUS * math.cos(angle), Sign.RADIUS * math.sin(angle))
		local ring = UI.circle(coin, "BORDER", 0, Sign.COIN)
		ring:SetPoint("CENTER")
		ring:SetColorTexture(1, 1, 1)
		local fill = UI.circle(coin, "BORDER", 1, Sign.COIN - 4, "panel")
		fill:SetPoint("CENTER")
		local cooldown = CreateFrame("Cooldown", nil, coin, "CooldownFrameTemplate")
		cooldown:SetPoint("CENTER")
		cooldown:SetSize(Sign.COIN - 4, Sign.COIN - 4)
		cooldown:SetSwipeTexture(UI.CIRCLE_MASK)
		cooldown:SetSwipeColor(0, 0, 0, 0.65)
		cooldown:SetDrawEdge(false)
		cooldown:SetDrawBling(false)
		cooldown:SetHideCountdownNumbers(true)
		if cooldown.SetUseCircularEdge then cooldown:SetUseCircularEdge(true) end
		-- The letter sits above the cooldown, which hides itself when idle.
		local face = CreateFrame("Frame", nil, coin)
		face:SetAllPoints()
		face:SetFrameLevel(cooldown:GetFrameLevel() + 2)
		local letter = UI.text(face, "serif", Stoa.typeSize.label, "text", "CENTER")
		letter:SetPoint("CENTER", 0, 1)
		UI.legible(letter)
		coin.ring, coin.cooldown, coin.letter = ring, cooldown, letter
		coin:Hide()
		coins[i] = coin
	end
	return coins
end

-- The caption under the coins: counts, procs, stacks.
function Sign.buildCaption(halo)
	local caption = UI.caption(halo, "")
	local angle = math.rad(Sign.ANGLES[#Sign.ANGLES])
	caption:SetPoint("TOP", halo, "CENTER", Sign.RADIUS * math.cos(angle), Sign.RADIUS * math.sin(angle) - Sign.COIN / 2 - 4)
	UI.legible(caption)
	return caption
end

-- The large word over the ring (TAUNT, a missing form).
function Sign.buildWord(halo, text)
	local word = UI.text(halo, "serif", Stoa.typeSize.title, "danger", "CENTER")
	word:SetPoint("BOTTOM", halo, "TOP", 0, 6)
	Stoa:SetFont(word, "serif", Stoa.typeSize.title, "OUTLINE")
	word:SetText(text or "")
	word:Hide()
	return word
end

-- Coins ------------------------------------------------------------------------
-- A timer coin (a DoT, a buff you keep up) drains as it runs and turns to
-- the warning colour once it's off. A cooldown coin is pale gold when
-- ready, bone while its effect is up, and muted while it comes back.

local function paintTimer(coin, state)
	local token = state == "off" and "danger" or state == "ending" and "accent" or "muted"
	local r, g, b = Stoa:Color(token)
	coin.ring:SetVertexColor(r, g, b, state == "on" and 0.7 or 1)
	coin.letter:SetTextColor(Stoa:Color(state == "on" and "text" or token))
end

local function paintCooldown(coin, state)
	local token = state == "ready" and "accent" or state == "active" and "text" or "muted"
	local r, g, b = Stoa:Color(token)
	coin.ring:SetVertexColor(r, g, b, state == "cooling" and 0.6 or 1)
	coin.letter:SetTextColor(Stoa:Color(state == "cooling" and "muted" or token))
end

local function letter(coin, text)
	coin.letter:SetText(text)
	Stoa:SetFont(coin.letter, "serif", text:len() > 1 and Stoa.typeSize.body or Stoa.typeSize.label)
end

-- A timer running until `ends` out of `length`. With no time known but an
-- aura seen, the client may still draw the swipe from the aura. Returns
-- "on", "ending" or "off".
function Sign.timer(coin, text, ends, length, aura, unit)
	letter(coin, text)
	coin.cooldown:SetReverse(true)
	coin:Show()
	if ends and ends > GetTime() then
		coin.cooldown:SetCooldown(ends - length, length)
		local state = ends - GetTime() < Sign.ENDING and "ending" or "on"
		paintTimer(coin, state)
		return state
	end
	if aura then
		if C_UnitAuras.GetAuraDuration and coin.cooldown.SetCooldownFromDurationObject then
			pcall(function()
				coin.cooldown:SetCooldownFromDurationObject(C_UnitAuras.GetAuraDuration(unit, aura.auraInstanceID))
			end)
		end
		paintTimer(coin, "on")
		return "on"
	end
	coin.cooldown:Clear()
	paintTimer(coin, "off")
	return "off"
end

-- A cooldown coin for a spell. `castAt` is your last cast of it, for when
-- the game hides the cooldown; `active` shows its effect is up. Returns
-- "ready", "active" or "cooling".
function Sign.cooldown(coin, text, spellID, castAt, length, active)
	letter(coin, text)
	coin.cooldown:SetReverse(false)
	coin:Show()
	if active then
		coin.cooldown:Clear()
		paintCooldown(coin, "active")
		return "active"
	end
	local ends, duration, readable = Sign.readyAt(spellID)
	if not readable then
		if castAt and length and GetTime() - castAt < length then
			ends, duration = castAt + length, length
		end
		-- The client can still draw a hidden cooldown's swipe.
		if C_Spell.GetSpellCooldownDuration and coin.cooldown.SetCooldownFromDurationObject then
			local drawn = pcall(function()
				coin.cooldown:SetCooldownFromDurationObject(C_Spell.GetSpellCooldownDuration(spellID))
			end)
			if drawn then
				local state = ends and "cooling" or "ready"
				paintCooldown(coin, state)
				return state
			end
		end
	end
	if ends and ends > GetTime() then
		coin.cooldown:SetCooldown(ends - duration, duration)
		paintCooldown(coin, "cooling")
		return "cooling"
	end
	coin.cooldown:Clear()
	paintCooldown(coin, "ready")
	return "ready"
end

function Sign.hideFrom(coins, first)
	for i = first, #coins do
		coins[i].cooldown:Clear()
		coins[i]:Hide()
	end
end

-- Casts --------------------------------------------------------------------------
-- Your casts, kept per target, so a DoT's time survives switching targets
-- and a hidden cooldown can still be timed.

local Casts = {}
Casts.__index = Casts

function Sign.casts(longest)
	return setmetatable({ onTarget = {}, own = {}, longest = longest or 60 }, Casts)
end

function Casts:Note(key, onTarget)
	local now = GetTime()
	self.own[key] = now
	if not onTarget then return end
	for who, list in pairs(self.onTarget) do
		local live = false
		for _, at in pairs(list) do
			if now - at < self.longest then live = true end
		end
		if not live then self.onTarget[who] = nil end
	end
	local who = Sign.targetKey()
	self.onTarget[who] = self.onTarget[who] or {}
	self.onTarget[who][key] = now
end

-- When you last cast this at your target, if within `length` seconds.
function Casts:On(key, length)
	local list = self.onTarget[Sign.targetKey()]
	local at = list and list[key]
	if at and GetTime() - at < length then return at end
end

-- When you last cast this at all.
function Casts:Last(key)
	return self.own[key]
end

-- If the game hides which target is which, a target change forgets them.
function Casts:ForgetHidden()
	self.onTarget.target = nil
end

-- A DoT or debuff of yours on the target: the aura's own time when shown,
-- otherwise your cast at this target.
function Sign.debuff(coin, text, name, casts, key, length)
	local aura = Sign.aura("target", name, "HARMFUL|PLAYER")
	local left = Sign.left(aura)
	if left then return Sign.timer(coin, text, GetTime() + left, length, aura, "target"), aura end
	local at = casts:On(key, length)
	if at then return Sign.timer(coin, text, at + length, length), aura end
	return Sign.timer(coin, text, nil, length, aura, "target"), aura
end

-- A buff of yours on yourself, the same way.
function Sign.buff(coin, text, name, casts, key, length)
	local aura = Sign.aura("player", name, "HELPFUL")
	local left = Sign.left(aura)
	if left then return Sign.timer(coin, text, GetTime() + left, length, aura, "player"), aura end
	local at = not aura and casts:Last(key)
	if at and GetTime() - at < length then return Sign.timer(coin, text, at + length, length), aura end
	return Sign.timer(coin, text, nil, length, aura, "player"), aura
end

-- Everyone in your group, yourself included.
function Sign.groupUnits()
	local units = { "player" }
	if IsInRaid() then
		units = {}
		for i = 1, GetNumGroupMembers() do units[#units + 1] = "raid" .. i end
	elseif IsInGroup() then
		for i = 1, GetNumSubgroupMembers() do units[#units + 1] = "party" .. i end
	end
	return units
end

-- How many in your group carry your aura of this name.
function Sign.countOnGroup(name)
	local count = 0
	for _, unit in ipairs(Sign.groupUnits()) do
		if UnitExists(unit) and Sign.aura(unit, name, "HELPFUL|PLAYER") then count = count + 1 end
	end
	return count
end

-- Whether your target is fighting someone else and wants a taunt.
function Sign.wantsTaunt()
	if not IsInGroup() or not Sign.hostileTarget() then return false end
	local fighting = UnitAffectingCombat("target")
	if Stoa:IsSecret(fighting) or not fighting then return false end
	local status = UnitThreatSituation("player", "target")
	if Stoa:IsSecret(status) then return false end
	return status == nil or status <= 1
end

-- Combo points on the target, or nil when hidden.
function Sign.comboPoints()
	local points
	if Enum and Enum.PowerType and Enum.PowerType.ComboPoints and UnitPower then
		points = Stoa:PlainNumber(UnitPower("player", Enum.PowerType.ComboPoints))
	end
	if not points and GetComboPoints then
		points = Stoa:PlainNumber(GetComboPoints("player", "target"))
	end
	return points
end

function Sign.power()
	return Stoa:PlainNumber(UnitPower("player"))
end

-- A signature module: runs Refresh on the events every signature cares
-- about and on a short ticker in combat. `extra` lists more events.
function Sign.wire(module, extra)
	local function refresh() xpcall(module.Refresh, Stoa.catch, module) end
	Stoa:On("PLAYER_TARGET_CHANGED", function()
		if module.casts then module.casts:ForgetHidden() end
		refresh()
	end)
	Stoa:OnUnit("UNIT_SPELLCAST_SUCCEEDED", { "player" }, function(unit, _, spellID)
		if module.NoteCast and spellID and not Stoa:IsSecret(spellID) then
			local name = C_Spell.GetSpellName(spellID)
			if name then xpcall(module.NoteCast, Stoa.catch, module, name, spellID) end
		end
		refresh()
	end)
	Stoa:OnUnit("UNIT_AURA", { "player", "target" }, refresh)
	for _, event in ipairs({ "SPELL_UPDATE_COOLDOWN", "UPDATE_SHAPESHIFT_FORM", "UNIT_THREAT_LIST_UPDATE",
		"GROUP_ROSTER_UPDATE", "STOA_ROLE_CHANGED", "STOA_STATE_CHANGED", "SPELLS_CHANGED" }) do
		Stoa:On(event, refresh)
	end
	for _, event in ipairs(extra or {}) do Stoa:On(event, refresh) end
	local ticking = true
	Stoa:On("STOA_TICK", function()
		if not ticking or not Sign.inCombat() or not module:Active() then return end
		if not xpcall(module.Refresh, Stoa.catch, module) then ticking = false end
	end)
	refresh()
end

-- Sets the combat bar's outline, when this signature owns it.
function Sign.setNext(module, spellName)
	local bar = Stoa.modules.CombatBar
	if not (bar and bar.SetNext) or not module:Active() then return end
	bar:SetNext(Sign.inCombat() and spellName or nil)
end

-- Every other class ------------------------------------------------------------------
-- Classes without a signature of their own still get the combat bar's
-- outline: the game's own suggestion for the next press, where it gives
-- one. The Halo's slot shows their main cooldown (Halo.lua).

local Assist = Stoa:NewModule("Assist", {})

local SIGNED = { PRIEST = true, PALADIN = true, DRUID = true, MAGE = true }

function Assist:Active()
	local _, classFile = UnitClass("player")
	return classFile ~= nil and not SIGNED[classFile]
end

function Assist:Refresh()
	Sign.setNext(self, Sign.hostileTarget() and Sign.assisted() or nil)
end

function Assist:OnEnable()
	if not self:Active() then return end
	Sign.wire(self)
end
