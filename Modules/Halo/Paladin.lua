-- Stoa: the Paladin signatures, Retribution and Protection.
-- Forever's paladin keeps a seal up for thirty seconds (Judgement no longer
-- eats it), judges once for a forty second mark, and fights around Holy
-- Strike. Around the Halo:
--   * coins on the ring's right, like Shadow's DoTs:
--       Retribution: S for your seal, J for your Judgement mark on the
--       target (shown once you've judged Crusader, Wisdom, Light or
--       Justice; Holy Strike keeps it fresh with Sacred Arbiter);
--       Protection: S for Seal of Fury (amber while another seal runs),
--       H for Holy Shield, C for Consecration on the ground;
--   * an outline on the combat bar's next press;
--   * as a tank in a group, TAUNT over the ring when your target is on
--     someone else: Judgement with Seal of Fury makes it attack you;
--   * for Retribution with Twist of Light, the moment a swing lands the
--     other seal of the pair (Command and Righteousness) is outlined and
--     named under the coins, so the next swing carries both.
--
-- Aura details can be secret in combat. Lookups go by name through the
-- client, and your own casts stand in for timers the game hides.
local _, ns = ...
local Stoa = ns.Stoa
local UI = Stoa.UI

local Paladin = Stoa:NewModule("Paladin", {})

local COIN = 26
local RADIUS = 168
-- The same places as Shadow's coins: right of the ring, clear of the
-- target plaque above and the mana number below. 0 = due right.
local COIN_ANGLES = { 10, -12, -34 }
local ENDING = 3

local SPELLS = {
	holyStrike = 679,
	judgement = 20271,
	consecration = 26573,
	holyShield = 20925,
	sealFury = 1311649,
	command = 20375,
	righteousness = 21084,
	crusader = 21082,
	exorcism = 879,
}

-- Talents found by name, since their Forever spell IDs aren't settled.
local TALENTS = {
	arbiter = "Sacred Arbiter",
	twist = "Twist of Light",
}

-- The seals Twist of Light swaps between, each to the other.
local TWIST_PAIRS = { command = "righteousness", righteousness = "command" }

local SEAL_LENGTH = 30
local MARK_LENGTH = 40
local DURATIONS = { holyShield = 10, consecration = 8 }

-- Judging these seals leaves a mark on the target; the rest only hit.
local MARKS = {
	["Seal of the Crusader"] = { name = "Judgement of the Crusader", length = MARK_LENGTH },
	["Seal of Wisdom"] = { name = "Judgement of Wisdom", length = MARK_LENGTH },
	["Seal of Light"] = { name = "Judgement of Light", length = MARK_LENGTH },
	["Seal of Justice"] = { name = "Judgement of Justice", length = 10 },
}

local COINS = {
	MELEE = {
		{ key = "seal", letter = "S" },
		{ key = "mark", letter = "J" },
	},
	TANK = {
		{ key = "seal", letter = "S" },
		{ key = "holyShield", letter = "H" },
		{ key = "consecration", letter = "C" },
	},
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

local function hasTalent(key)
	local info = C_Spell and C_Spell.GetSpellInfo and C_Spell.GetSpellInfo(TALENTS[key])
	local id = type(info) == "table" and info.spellID
	return id and not Stoa:IsSecret(id) and knows(id) or false
end

local auraByName = Stoa.aura.byName

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

local function targetKey()
	local guid = UnitGUID("target")
	if guid and not Stoa:IsSecret(guid) then return guid end
	return "target"
end

function Paladin:Role()
	local _, classFile = UnitClass("player")
	if classFile ~= "PALADIN" then return nil end
	local role = Stoa:GetRole()
	return COINS[role] and role or nil
end

-- Seal -----------------------------------------------------------------------

-- The seal you're running and when it ends, or nil. Your buffs are read by
-- name where the game shows them; otherwise the last seal you cast stands
-- in, for its thirty seconds (a seal only ends early when another
-- replaces it, and that's a cast too).
function Paladin:Seal()
	local cast = self.sealCast
	if cast and GetTime() - cast.at < SEAL_LENGTH then
		local aura = auraByName("player", cast.name, "HELPFUL")
		local left = auraLeft(aura)
		return cast.name, left and (GetTime() + left) or (cast.at + SEAL_LENGTH), aura
	end
	if not (C_UnitAuras and C_UnitAuras.GetAuraDataByIndex) then return nil end
	for i = 1, 40 do
		local ok, aura = pcall(C_UnitAuras.GetAuraDataByIndex, "player", i, "HELPFUL")
		if not ok or not aura then break end
		local name = aura.name
		if not Stoa:IsSecret(name) and name and name:sub(1, 8) == "Seal of " then
			local left = auraLeft(aura)
			return name, left and (GetTime() + left), aura
		end
	end
end

-- Judgement marks -------------------------------------------------------------

-- The mark of yours on the target and when it ends: by name on the
-- target's debuffs (anyone's counts, since paladins refresh each other's),
-- else from your own Judgement on this target.
function Paladin:Mark()
	local record = self.marks and self.marks[targetKey()]
	local names = {}
	if record then names[1] = record.name end
	for _, mark in pairs(MARKS) do
		if not record or mark.name ~= record.name then names[#names + 1] = mark.name end
	end
	for _, name in ipairs(names) do
		local aura = auraByName("target", name, "HARMFUL")
		if aura then
			local left = auraLeft(aura)
			if left then return name, GetTime() + left, aura end
			if record and record.name == name then return name, record.at + record.length, aura end
			return name, nil, aura
		end
	end
	if record and GetTime() - record.at < record.length then
		return record.name, record.at + record.length
	end
end

-- Casts -----------------------------------------------------------------------

function Paladin:NoteCast(spellID)
	if Stoa:IsSecret(spellID) or not spellID then return end
	local name = C_Spell.GetSpellName(spellID)
	if not name then return end
	local now = GetTime()
	self.marks = self.marks or {}
	self.casts = self.casts or {}
	for who, record in pairs(self.marks) do
		if now - record.at > record.length then self.marks[who] = nil end
	end

	if name:sub(1, 8) == "Seal of " then
		self.sealCast = { name = name, at = now }
		if self.twist and self.twist.seal == name then self.twist = nil end
		-- The seal you fight with, for when it drops.
		if not MARKS[name] then self.mainSeal = name end
	elseif name == nameOf("judgement") then
		local seal = self:Seal()
		local mark = seal and MARKS[seal]
		if mark then
			self.marks[targetKey()] = { name = mark.name, at = now, length = mark.length }
			self.judges = true
		end
		self.judgedAt = now
	elseif name == nameOf("holyStrike") then
		-- Sacred Arbiter starts the target's marks over.
		local record = self.marks[targetKey()]
		if record and hasTalent("arbiter") then record.at = now end
	end
	for key in pairs(DURATIONS) do
		if name == nameOf(key) then self.casts[key] = now end
	end
end

function Paladin:ForgetHiddenTarget()
	if self.marks then self.marks.target = nil end
end

-- Build -----------------------------------------------------------------------

function Paladin:BuildCoins(halo)
	self.coins = {}
	for i = 1, #COIN_ANGLES do
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
		-- The letter sits above the cooldown, which hides itself when idle.
		local face = CreateFrame("Frame", nil, coin)
		face:SetAllPoints()
		face:SetFrameLevel(cooldown:GetFrameLevel() + 2)
		local letter = UI.text(face, "serif", Stoa.typeSize.label, "text", "CENTER")
		letter:SetPoint("CENTER", 0, 1)
		UI.legible(letter)
		coin.ring, coin.cooldown, coin.letter = ring, cooldown, letter
		coin:Hide()
		self.coins[i] = coin
	end
end

-- Twist of Light ---------------------------------------------------------------
-- The game tells addons when each swing lands (Blizzard's swing timer runs
-- on it). Right after a main-hand swing is the time to change seals.

function Paladin:BuildTwist(halo)
	local word = UI.caption(halo, "")
	local angle = math.rad(COIN_ANGLES[#COIN_ANGLES])
	word:SetPoint("TOP", halo, "CENTER", RADIUS * math.cos(angle), RADIUS * math.sin(angle) - COIN / 2 - 4)
	UI.legible(word)
	self.twistWord = word
end

function Paladin:NoteSwing(duration, swingType)
	local mainHand = Enum and Enum.PlayerSwingType and Enum.PlayerSwingType.MainHand
	if mainHand ~= nil and swingType ~= mainHand then return end
	if self:Role() ~= "MELEE" or not hasTalent("twist") then return end
	local seal = self:Seal()
	for key, partner in pairs(TWIST_PAIRS) do
		if seal == nameOf(key) and knows(SPELLS[partner]) then
			local length = Stoa:PlainNumber(duration) or 3
			self.twist = { seal = nameOf(partner), ends = GetTime() + length }
			return
		end
	end
end

function Paladin:Twist()
	local twist = self.twist
	if twist and GetTime() < twist.ends then return twist.seal end
	self.twist = nil
end

function Paladin:UpdateTwist()
	local word = self.twistWord
	if not word then return end
	local seal = Stoa:GetState() == Stoa.STATE_COMBAT and self:Twist()
	word:SetText(seal and ("TWIST: " .. seal:gsub("^Seal of ", ""):upper()) or "")
	word:SetTextColor(Stoa:Color("accent"))
end

function Paladin:BuildTaunt(halo)
	local word = UI.text(halo, "serif", Stoa.typeSize.title, "danger", "CENTER")
	word:SetPoint("BOTTOM", halo, "TOP", 0, 6)
	Stoa:SetFont(word, "serif", Stoa.typeSize.title, "OUTLINE")
	word:SetText("TAUNT")
	word:Hide()
	self.tauntWord = word
end

-- Updates ---------------------------------------------------------------------

local function paintCoin(coin, state)
	local token = state == "off" and "danger" or state == "ending" and "accent" or "muted"
	local r, g, b = Stoa:Color(token)
	coin.ring:SetVertexColor(r, g, b, state == "on" and 0.7 or 1)
	coin.letter:SetTextColor(Stoa:Color(state == "on" and "text" or token))
	UI.coinLit(coin, state ~= "off")
end

-- Shows a coin running until `ends` out of `length`, or off.
local function setCoin(coin, ends, length, aura, unit)
	if ends then
		coin.cooldown:SetCooldown(ends - length, length)
		paintCoin(coin, ends - GetTime() < ENDING and "ending" or "on")
		return ends - GetTime() < ENDING and "ending" or "on"
	end
	if aura then
		-- The times are hidden, but the client can still draw the swipe.
		if C_UnitAuras.GetAuraDuration and coin.cooldown.SetCooldownFromDurationObject then
			pcall(function()
				coin.cooldown:SetCooldownFromDurationObject(C_UnitAuras.GetAuraDuration(unit, aura.auraInstanceID))
			end)
		end
		paintCoin(coin, "on")
		return "on"
	end
	coin.cooldown:Clear()
	paintCoin(coin, "off")
	return "off"
end

function Paladin:CoinState(key, coin)
	local now = GetTime()
	if key == "seal" then
		local seal, ends, aura = self:Seal()
		-- A tank wants Fury; any other seal counts as off.
		if self:Role() == "TANK" and knows(SPELLS.sealFury) and seal and seal ~= nameOf("sealFury") then
			ends, aura = nil, nil
		end
		return setCoin(coin, seal and ends, SEAL_LENGTH, seal and aura, "player")
	elseif key == "mark" then
		local _, ends, aura = self:Mark()
		return setCoin(coin, ends, MARK_LENGTH, aura, "target")
	elseif key == "holyShield" then
		local aura = auraByName("player", nameOf("holyShield"), "HELPFUL")
		local left = auraLeft(aura)
		local cast = self.casts and self.casts.holyShield
		local ends = left and (now + left) or (not aura and cast and now - cast < DURATIONS.holyShield and cast + DURATIONS.holyShield) or nil
		return setCoin(coin, ends, DURATIONS.holyShield, aura, "player")
	elseif key == "consecration" then
		local cast = self.casts and self.casts.consecration
		local ends = cast and now - cast < DURATIONS.consecration and cast + DURATIONS.consecration or nil
		return setCoin(coin, ends, DURATIONS.consecration)
	end
end

-- The spell whose art sits behind a coin's letter: the seal you run (Seal of
-- Fury for a tank), Judgement for the mark, or the coin's own spell.
function Paladin:CoinSpell(key)
	if key == "seal" then
		if self:Role() == "TANK" and knows(SPELLS.sealFury) then return SPELLS.sealFury end
		return self:Seal() or SPELLS.righteousness
	end
	if key == "mark" then return SPELLS.judgement end
	return SPELLS[key]
end

local function coinApplies(self, key)
	if key == "seal" then return true end
	if key == "mark" then return knows(SPELLS.judgement) and self.judges end
	return knows(SPELLS[key])
end

function Paladin:UpdateCoins()
	local role = self:Role()
	local list = role and hostileTarget() and COINS[role] or {}
	self.state = {}
	local index = 0
	for _, entry in ipairs(list) do
		if coinApplies(self, entry.key) then
			index = index + 1
			local coin = self.coins[index]
			coin.letter:SetText(entry.letter)
			UI.coinArt(coin, self:CoinSpell(entry.key))
			self.state[entry.key] = self:CoinState(entry.key, coin)
			coin:Show()
		end
	end
	for i = index + 1, #self.coins do
		self.coins[i].cooldown:Clear()
		self.coins[i]:Hide()
	end
end

-- Whether your target is fighting someone else and wants a taunt.
function Paladin:WantsTaunt()
	if self:Role() ~= "TANK" or not IsInGroup() or not hostileTarget() then return false end
	if not knows(SPELLS.judgement) then return false end
	local fighting = UnitAffectingCombat("target")
	if Stoa:IsSecret(fighting) or not fighting then return false end
	local status = UnitThreatSituation("player", "target")
	if Stoa:IsSecret(status) then return false end
	return status == nil or status <= 1
end

function Paladin:UpdateTaunt()
	local inCombat = Stoa:GetState() == Stoa.STATE_COMBAT
	self.tauntWord:SetShown(inCombat and self:WantsTaunt() or false)
end

local function assisted()
	if not (C_AssistedCombat and C_AssistedCombat.GetNextCastSpell) then return nil end
	local ok, spellID = pcall(C_AssistedCombat.GetNextCastSpell, false)
	if ok and spellID and not Stoa:IsSecret(spellID) then
		return C_Spell.GetSpellName(spellID)
	end
end

local function undeadOrDemon()
	local kind = UnitCreatureType("target")
	if Stoa:IsSecret(kind) or not kind then return false end
	return kind == "Undead" or kind == "Demon"
end

-- The guides' priority. Cooldowns are hidden in combat, so where it comes
-- down to what's ready the game's own suggestion is asked first.
function Paladin:NextPress()
	local role = self:Role()
	if not role or not hostileTarget() then return nil end
	local state = self.state or {}
	if role == "TANK" then
		if state.seal == "off" then
			return knows(SPELLS.sealFury) and nameOf("sealFury") or self.mainSeal or nameOf("righteousness")
		end
		if self:WantsTaunt() then return nameOf("judgement") end
		if state.holyShield == "off" then return nameOf("holyShield") end
		if state.consecration == "off" then return nameOf("consecration") end
	else
		if state.seal == "off" then
			return self.mainSeal or (knows(SPELLS.command) and nameOf("command")) or nameOf("righteousness")
		end
		if state.mark == "off" then
			local seal = self:Seal()
			if seal and MARKS[seal] then return nameOf("judgement") end
			return nameOf("crusader")
		end
		local twist = self:Twist()
		if twist then return twist end
		if undeadOrDemon() and knows(SPELLS.exorcism) and ready("exorcism") then return nameOf("exorcism") end
	end
	for _, key in ipairs({ "holyStrike", "judgement" }) do
		if knows(SPELLS[key]) and ready(key) then return nameOf(key) end
	end
	local suggested = assisted()
	if suggested then return suggested end
	if knows(SPELLS.holyStrike) and ready("holyStrike") ~= false then return nameOf("holyStrike") end
end

function Paladin:UpdateNext()
	local bar = Stoa.modules.CombatBar
	if not (bar and bar.SetNext) then return end
	local inCombat = Stoa:GetState() == Stoa.STATE_COMBAT
	bar:SetNext(inCombat and self:NextPress() or nil)
end

-- Lifecycle -------------------------------------------------------------------

function Paladin:Refresh()
	self:UpdateCoins()
	self:UpdateTaunt()
	self:UpdateTwist()
	self:UpdateNext()
end

function Paladin:OnEnable()
	local _, classFile = UnitClass("player")
	if classFile ~= "PALADIN" then return end
	local halo = Stoa.modules.Halo
	if not (halo and halo.frame) then return end
	self:BuildCoins(halo.frame)
	self:BuildTaunt(halo.frame)
	self:BuildTwist(halo.frame)

	local function refresh() xpcall(self.Refresh, Stoa.catch, self) end
	Stoa:On("PLAYER_TARGET_CHANGED", function()
		self:ForgetHiddenTarget()
		refresh()
	end)
	Stoa:OnUnit("UNIT_SPELLCAST_SUCCEEDED", { "player" }, function(unit, _, spellID)
		xpcall(self.NoteCast, Stoa.catch, self, spellID)
		refresh()
	end)
	Stoa:OnUnit("UNIT_AURA", { "player", "target" }, refresh)
	Stoa:On("UNIT_THREAT_LIST_UPDATE", refresh)
	Stoa:On("PLAYER_SWING", function(duration, swingType)
		xpcall(self.NoteSwing, Stoa.catch, self, duration, swingType)
		refresh()
	end)
	Stoa:On("STOA_ROLE_CHANGED", refresh)
	Stoa:On("STOA_STATE_CHANGED", refresh)
	Stoa:On("SPELLS_CHANGED", refresh)
	-- Timers tick without events, on the combat clock. If an update ever
	-- errors the listener stops rather than repeating the error.
	local ticking = true
	Stoa:On("STOA_TICK", function()
		if not ticking or not self:Role() then return end
		if not xpcall(self.Refresh, Stoa.catch, self) then ticking = false end
	end)
	refresh()
end
