-- Stoa: the Shadow signature.
-- What a Shadow Priest watches, kept around the Halo:
--   * three coins along the ring's right side for Shadow Word: Pain,
--     Devouring Plague and Vampiric Embrace on your target, each draining
--     as its timer runs and calling out in the warning colour when it's off;
--   * an outline on the combat bar's next press (DoTs first, then Mind
--     Blast and Shadow Word: Death when ready, then Mind Flay);
--   * SHADOWFORM over the ring when you've dropped out of form;
--   * a PAIN count when more than one enemy is in the fight (the plates
--     show Blizzard's own Pain icon);
--   * Shadow Weaving stacks on the target plaque.
-- Mind Flay's tick marks live with the cast line in Halo.lua.
--
-- Aura details can be secret in combat. Lookups go by name through the
-- client where it can match them for us, and anything unreadable just
-- shows less rather than guessing. /stoa probe reports what's readable.
local _, ns = ...
local Stoa = ns.Stoa
local UI = Stoa.UI

local Shadow = Stoa:NewModule("Shadow", {})

local COIN = 26
local RADIUS = 168
-- The coins sit on the right of the ring, clear of the target plaque above
-- and the mana number below. Angles in degrees, 0 = due right.
local COIN_ANGLES = { 10, -12, -34 }
-- Reapplying early is wasted, so a coin only calls for a refresh once
-- it's off. Below this many seconds left it brightens as a heads-up.
local ENDING = 3
local WEAVING_MAX = 5

local SPELLS = {
	pain = 589,         -- Shadow Word: Pain
	plague = 2944,      -- Devouring Plague
	embrace = 15286,    -- Vampiric Embrace
	blast = 8092,       -- Mind Blast
	death = 32379,      -- Shadow Word: Death
	flay = 15407,       -- Mind Flay
	form = 15473,       -- Shadowform
	weaving = 15258,    -- Shadow Weaving (the debuff)
}

-- How long each lasts, for the times the game won't show the aura itself:
-- then the coin runs from your own cast on this target.
local DURATIONS = { pain = 18, plague = 24, embrace = 30 }

local DOTS = {
	{ key = "pain", letter = "P" },
	{ key = "plague", letter = "D" },
	{ key = "embrace", letter = "V" },
}

local function knows(spellID)
	if IsPlayerSpell and IsPlayerSpell(spellID) then return true end
	return IsSpellKnown and IsSpellKnown(spellID) or false
end

local names = {}
local function nameOf(key)
	if not names[key] then
		local name = C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(SPELLS[key])
		if name then names[key] = name end
	end
	return names[key]
end

-- Your aura of this spell on the unit, or nil. The client matches the name
-- itself where it can, which works even when the aura's own fields are
-- secret; otherwise the debuffs are walked and compared where readable.
local function findAura(unit, key, filter)
	local name = nameOf(key)
	if not name then return nil end
	filter = filter or "HARMFUL|PLAYER"
	if C_UnitAuras and C_UnitAuras.GetAuraDataBySpellName then
		local ok, aura = pcall(C_UnitAuras.GetAuraDataBySpellName, unit, name, filter)
		if ok then return aura end
	end
	if not (C_UnitAuras and C_UnitAuras.GetAuraDataByIndex) then return nil end
	for i = 1, 40 do
		local ok, aura = pcall(C_UnitAuras.GetAuraDataByIndex, unit, i, filter)
		if not ok or not aura then return nil end
		if not Stoa:IsSecret(aura.name) and aura.name == name then return aura end
	end
end

local auraLeft = Stoa.aura.left

-- Whether a spell is off cooldown (the global cooldown aside), or nil when
-- the game won't say.
local function ready(key)
	local info = C_Spell and C_Spell.GetSpellCooldown and C_Spell.GetSpellCooldown(SPELLS[key])
	if type(info) ~= "table" then return nil end
	local start, duration = Stoa:PlainNumber(info.startTime), Stoa:PlainNumber(info.duration)
	if not start or not duration then return nil end
	return start == 0 or duration <= 1.5 or (start + duration - GetTime()) <= 0.3
end

local function hostileTarget()
	if not UnitExists("target") then return false end
	local hostile = UnitCanAttack("player", "target")
	if Stoa:IsSecret(hostile) then return true end
	local dead = UnitIsDeadOrGhost("target")
	return hostile and not (not Stoa:IsSecret(dead) and dead)
end

function Shadow:Active()
	local _, classFile = UnitClass("player")
	return classFile == "PRIEST" and Stoa:GetRole() == "RANGED"
end

-- Build ---------------------------------------------------------------------

function Shadow:BuildCoins(halo)
	self.coins = {}
	for i, dot in ipairs(DOTS) do
		local coin = CreateFrame("Frame", nil, halo)
		coin:SetSize(COIN, COIN)
		local angle = math.rad(COIN_ANGLES[i])
		coin:SetPoint("CENTER", halo, "CENTER", RADIUS * math.cos(angle), RADIUS * math.sin(angle))
		local ring = UI.circle(coin, "BORDER", 0, COIN)
		ring:SetPoint("CENTER")
		ring:SetColorTexture(1, 1, 1)
		local fill = UI.circle(coin, "BORDER", 1, COIN - 4, "panel")
		fill:SetPoint("CENTER")
		local cooldown = CreateFrame("Cooldown", nil, coin, "CooldownFrameTemplate")
		cooldown:SetPoint("CENTER")
		cooldown:SetSize(COIN - 4, COIN - 4)
		cooldown:SetSwipeTexture(UI.CIRCLE_MASK)
		cooldown:SetSwipeColor(0, 0, 0, 0.65)
		cooldown:SetReverse(true)
		cooldown:SetDrawEdge(false)
		cooldown:SetDrawBling(false)
		cooldown:SetHideCountdownNumbers(true)
		if cooldown.SetUseCircularEdge then cooldown:SetUseCircularEdge(true) end
		-- A cooldown frame hides itself when it has nothing to draw, so the
		-- letter sits on its own layer above it.
		local face = CreateFrame("Frame", nil, coin)
		face:SetAllPoints()
		face:SetFrameLevel(cooldown:GetFrameLevel() + 2)
		local letter = UI.text(face, "serif", Stoa.typeSize.label, "text", "CENTER")
		letter:SetPoint("CENTER", 0, 1)
		letter:SetText(dot.letter)
		UI.legible(letter)
		coin.ring, coin.cooldown, coin.letter, coin.key = ring, cooldown, letter, dot.key
		coin:Hide()
		self.coins[i] = coin
	end
	-- How many enemies in the fight carry your Pain, under the coins.
	local count = UI.caption(halo, "")
	local angle = math.rad(COIN_ANGLES[#COIN_ANGLES])
	count:SetPoint("TOP", halo, "CENTER", RADIUS * math.cos(angle), RADIUS * math.sin(angle) - COIN / 2 - 4)
	UI.legible(count)
	self.painCount = count
end

function Shadow:BuildForm(halo)
	local word = UI.text(halo, "serif", Stoa.typeSize.title, "danger", "CENTER")
	word:SetPoint("BOTTOM", halo, "TOP", 0, 6)
	word:SetText("SHADOWFORM")
	Stoa:SetFont(word, "serif", Stoa.typeSize.title, "OUTLINE")
	word:Hide()
	self.formWord = word
end

-- Weaving on the target plaque: the word and five pips under the bar,
-- opposite the threat word.
function Shadow:BuildWeaving(target)
	local holder = CreateFrame("Frame", nil, target)
	holder:SetSize(120, 10)
	holder:SetPoint("TOPLEFT", target.hp, "BOTTOMLEFT", 0, -6)
	local word = UI.caption(holder, "Weaving")
	word:SetPoint("LEFT")
	holder.pips = {}
	for i = 1, WEAVING_MAX do
		local pip = UI.circle(holder, "ARTWORK", 0, 5)
		pip:SetPoint("LEFT", word, "RIGHT", 6 + (i - 1) * 8, 0)
		pip:SetColorTexture(1, 1, 1)
		holder.pips[i] = pip
	end
	-- When the stack count is hidden it's shown as a number instead.
	local number = UI.caption(holder, "")
	number:SetPoint("LEFT", word, "RIGHT", 6, 0)
	holder.number = number
	holder:Hide()
	self.weaving = holder
end

-- Updates -------------------------------------------------------------------

local function paintCoin(coin, state)
	local token = state == "off" and "danger" or state == "ending" and "accent" or "muted"
	local r, g, b = Stoa:Color(token)
	coin.ring:SetVertexColor(r, g, b, state == "on" and 0.7 or 1)
	coin.letter:SetTextColor(Stoa:Color(state == "on" and "text" or token))
	UI.coinArt(coin, SPELLS[coin.key])
	UI.coinLit(coin, state ~= "off")
end

function Shadow:UpdateCoins()
	local hostile = self:Active() and hostileTarget()
	self.state = self.state or {}
	for _, coin in ipairs(self.coins) do
		local key = coin.key
		if not hostile or not knows(SPELLS[key]) then
			coin:Hide()
			self.state[key] = nil
		else
			local aura = findAura("target", key)
			-- Your own cast timing wins whenever the aura's times are hidden.
			local cast = not (aura and auraLeft(aura)) and self:CastOn(key)
			if cast then
				coin.cooldown:SetCooldown(cast, DURATIONS[key])
				local left = cast + DURATIONS[key] - GetTime()
				local state = left < ENDING and "ending" or "on"
				paintCoin(coin, state)
				self.state[key] = state
			elseif aura then
				-- Newer clients hand out a duration object the swipe takes
				-- even when the times are secret.
				local drawn = false
				if C_UnitAuras.GetAuraDuration and coin.cooldown.SetCooldownFromDurationObject then
					drawn = pcall(function()
						coin.cooldown:SetCooldownFromDurationObject(C_UnitAuras.GetAuraDuration("target", aura.auraInstanceID))
					end)
				end
				if not drawn then
					pcall(function()
						if aura.duration > 0 then
							coin.cooldown:SetCooldown(aura.expirationTime - aura.duration, aura.duration)
						end
					end)
				end
				local left = auraLeft(aura)
				local state = left and left < ENDING and "ending" or "on"
				paintCoin(coin, state)
				self.state[key] = state
			else
				coin.cooldown:Clear()
				paintCoin(coin, "off")
				self.state[key] = "off"
			end
			coin:Show()
		end
	end
end

-- When the game hides auras in combat, your own casts still say when a DoT
-- went on. Each lasts its known duration on the target you cast it at, and
-- each target keeps its own, so switching back shows the time left. If the
-- game hides which target is which, a target change forgets them instead.
local LONGEST = 60

local function unitKey(unit)
	local guid = UnitGUID(unit)
	if guid and not Stoa:IsSecret(guid) then return guid end
end

local function targetKey()
	return unitKey("target") or "target"
end

function Shadow:NoteCast(spellID)
	if Stoa:IsSecret(spellID) or not spellID then return end
	local name = C_Spell.GetSpellName(spellID)
	if not name then return end
	local now = GetTime()
	self.casts = self.casts or {}
	-- Forget targets whose DoTs have all run out.
	for who, list in pairs(self.casts) do
		local live = false
		for _, at in pairs(list) do
			if now - at < LONGEST then live = true end
		end
		if not live then self.casts[who] = nil end
	end
	for key in pairs(DURATIONS) do
		if nameOf(key) == name then
			local who = targetKey()
			self.casts[who] = self.casts[who] or {}
			self.casts[who][key] = now
		end
	end
end

function Shadow:CastOn(key)
	local list = self.casts and self.casts[targetKey()]
	local at = list and list[key]
	if at and GetTime() - at < DURATIONS[key] then return at end
end

-- Whether your own cast put this DoT on a unit (a nameplate, say) and it
-- hasn't run out.
function Shadow:CastOnUnit(unit, key)
	local who = unitKey(unit)
	local list = who and self.casts and self.casts[who]
	local at = list and list[key]
	return at ~= nil and GetTime() - at < DURATIONS[key]
end

function Shadow:ForgetHiddenTarget()
	if self.casts then self.casts.target = nil end
end

-- The guide's single-target order: DoTs when they're off, Mind Blast and
-- Shadow Word: Death when ready, Embrace when it's off, Mind Flay to fill.
function Shadow:NextPress()
	if not self:Active() or not hostileTarget() then return nil end
	local state = self.state or {}
	local function wants(key)
		return knows(SPELLS[key]) and state[key] == "off"
	end
	if wants("pain") then return nameOf("pain") end
	if wants("plague") and ready("plague") ~= false then return nameOf("plague") end
	for _, key in ipairs({ "blast", "death" }) do
		if knows(SPELLS[key]) and ready(key) then return nameOf(key) end
	end
	-- Cooldowns are hidden in combat, so for the rest the game's own
	-- suggestion is asked, where there is one.
	if C_AssistedCombat and C_AssistedCombat.GetNextCastSpell then
		local ok, spellID = pcall(C_AssistedCombat.GetNextCastSpell, false)
		if ok and spellID and not Stoa:IsSecret(spellID) then
			local name = C_Spell.GetSpellName(spellID)
			if name then return name end
		end
	end
	if wants("embrace") then return nameOf("embrace") end
	if knows(SPELLS.flay) then return nameOf("flay") end
end

function Shadow:UpdateNext()
	local bar = Stoa.modules.CombatBar
	-- Other specs' signatures own the outline when this one isn't active.
	if not (bar and bar.SetNext) or not self:Active() then return end
	local inCombat = Stoa:GetState() == Stoa.STATE_COMBAT
	bar:SetNext(inCombat and self:NextPress() or nil)
end

local function inForm()
	if GetShapeshiftForm then
		local form = GetShapeshiftForm()
		if not Stoa:IsSecret(form) and form and form > 0 then return true end
	end
	if C_UnitAuras and C_UnitAuras.GetPlayerAuraBySpellID then
		local ok, aura = pcall(C_UnitAuras.GetPlayerAuraBySpellID, SPELLS.form)
		if ok and aura then return true end
	end
	return findAura("player", "form", "HELPFUL") ~= nil
end

function Shadow:UpdateForm()
	local missing = self:Active() and knows(SPELLS.form) and not inForm()
	self.formWord:SetShown(missing and true or false)
end

function Shadow:UpdateWeaving()
	local holder = self.weaving
	if not holder then return end
	local aura = self:Active() and hostileTarget() and findAura("target", "weaving", "HARMFUL")
	if not aura then
		holder:Hide()
		return
	end
	local stacks = aura.applications
	local plain = Stoa:PlainNumber(stacks)
	for i, pip in ipairs(holder.pips) do
		pip:SetShown(plain ~= nil)
		if plain then
			local r, g, b = Stoa:Color(i <= plain and "accent" or "muted")
			pip:SetVertexColor(r, g, b, i <= plain and 1 or 0.35)
		end
	end
	holder.number:SetShown(plain == nil)
	if plain == nil then holder.number:SetText(stacks) end
	holder:Show()
end

-- Nameplates ----------------------------------------------------------------
-- Blizzard's plates already show your Pain as a debuff icon with its time,
-- so Stoa only counts which enemies in the fight carry it.

function Shadow:UpdatePlate(unit)
	local has = self:Active() and (findAura(unit, "pain") ~= nil or self:CastOnUnit(unit, "pain"))
	self.pained = self.pained or {}
	self.pained[unit] = has or nil
end

function Shadow:UpdatePainCount()
	local count = self.painCount
	if not self:Active() or not knows(SPELLS.pain) or Stoa:GetState() ~= Stoa.STATE_COMBAT then
		count:SetText("")
		return
	end
	local fighting, pained = 0, 0
	for unit in pairs(self.plates or {}) do
		local hostile = UnitCanAttack("player", unit)
		local inFight = UnitAffectingCombat(unit)
		if not Stoa:IsSecret(hostile) and hostile and not Stoa:IsSecret(inFight) and inFight then
			fighting = fighting + 1
			if self.pained and self.pained[unit] then pained = pained + 1 end
		end
	end
	count:SetText(fighting > 1 and ("PAIN %d/%d"):format(pained, fighting) or "")
end

-- Probe ---------------------------------------------------------------------
-- /stoa probe: what the game shows addons right now. Run it in a fight with
-- an enemy targeted to see what's hidden in combat.

local function describe(value)
	if Stoa:IsSecret(value) then return "hidden" end
	if value == nil then return "none" end
	return tostring(value)
end

function Shadow:Probe()
	local say = function(...) Stoa:Print(...) end
	say(("Probe: in combat %s, target %s."):format(tostring(InCombatLockdown()), UnitExists("target") and "yes" or "none"))
	say(("APIs: aura by name %s, aura duration %s, spell cooldown duration %s, assisted combat %s."):format(
		tostring(C_UnitAuras and C_UnitAuras.GetAuraDataBySpellName ~= nil),
		tostring(C_UnitAuras and C_UnitAuras.GetAuraDuration ~= nil),
		tostring(C_Spell and C_Spell.GetSpellCooldownDuration ~= nil),
		tostring(C_AssistedCombat ~= nil)))
	local ok, aura = pcall(C_UnitAuras.GetAuraDataByIndex, "target", 1, "HARMFUL|PLAYER")
	if ok and aura then
		say(("Your first debuff on the target: name %s, spell %s, ends %s, stacks %s."):format(
			describe(aura.name), describe(aura.spellId), describe(aura.expirationTime), describe(aura.applications)))
	else
		say("No debuff of yours on the target to read.")
	end
	say(("Found by name: Pain %s, Plague %s, Embrace %s."):format(
		findAura("target", "pain") and "yes" or "no",
		findAura("target", "plague") and "yes" or "no",
		findAura("target", "embrace") and "yes" or "no"))
	local info = C_Spell.GetSpellCooldown(SPELLS.blast)
	say(("Mind Blast cooldown: start %s, length %s."):format(describe(info and info.startTime), describe(info and info.duration)))
	say(("Target hostile %s, health %s."):format(describe(UnitCanAttack("player", "target")), describe(UnitHealth("target"))))
	local any = 0
	for i = 1, 40 do
		local okAny, each = pcall(C_UnitAuras.GetAuraDataByIndex, "target", i, "HARMFUL")
		if not okAny or not each then break end
		any = any + 1
	end
	say(("Debuffs on the target from anyone: %d. Pain from your casts: %s."):format(any, self:CastOn("pain") and "yes" or "no"))
	local probe = UIParent:CreateFontString(nil, "OVERLAY")
	local fonts = {}
	for _, kind in ipairs({ "serif", "sans" }) do
		Stoa:SetFont(probe, kind, 14)
		local path = probe:GetFont()
		if type(path) == "string" then path = path:match("([^\\]+)$") or path end
		fonts[#fonts + 1] = kind .. " " .. tostring(path)
	end
	say("Fonts: " .. table.concat(fonts, ", ") .. ".")
end

-- Lifecycle -----------------------------------------------------------------

function Shadow:Refresh()
	self:UpdateCoins()
	self:UpdateWeaving()
	self:UpdateForm()
	self:UpdateNext()
	-- Plates whose Pain came from your casts run out without an aura event.
	for unit in pairs(self.plates or {}) do self:UpdatePlate(unit) end
	self:UpdatePainCount()
end

function Shadow:OnEnable()
	local halo = Stoa.modules.Halo
	if not (halo and halo.frame) then return end
	self:BuildCoins(halo.frame)
	self:BuildForm(halo.frame)
	if halo.target and halo.target.hp then self:BuildWeaving(halo.target) end
	self.plates = {}

	Stoa.commands.probe = function() xpcall(self.Probe, Stoa.catch, self) end

	local function refresh() xpcall(self.Refresh, Stoa.catch, self) end
	Stoa:On("PLAYER_TARGET_CHANGED", function()
		self:ForgetHiddenTarget()
		refresh()
	end)
	Stoa:OnUnit("UNIT_SPELLCAST_SUCCEEDED", { "player" }, function(unit, _, spellID)
		self:NoteCast(spellID)
		refresh()
	end)
	Stoa:On("STOA_ROLE_CHANGED", refresh)
	Stoa:On("STOA_STATE_CHANGED", refresh)
	Stoa:On("SPELLS_CHANGED", refresh)
	Stoa:On("UPDATE_SHAPESHIFT_FORM", refresh)
	Stoa:On("UNIT_AURA", function(unit)
		if unit == "target" or unit == "player" then refresh() end
		if unit and self.plates[unit] then
			xpcall(self.UpdatePlate, Stoa.catch, self, unit)
		end
	end)
	Stoa:On("NAME_PLATE_UNIT_ADDED", function(unit)
		self.plates[unit] = true
		xpcall(self.UpdatePlate, Stoa.catch, self, unit)
	end)
	Stoa:On("NAME_PLATE_UNIT_REMOVED", function(unit)
		self.plates[unit] = nil
		if self.pained then self.pained[unit] = nil end
	end)
	-- Timers and cooldowns tick without events, on the combat clock. If an
	-- update ever errors the listener stops rather than repeating the error.
	local ticking = true
	Stoa:On("STOA_TICK", function()
		if not ticking or not self:Active() then return end
		if not xpcall(self.Refresh, Stoa.catch, self) then ticking = false end
	end)
	refresh()
end
