-- Stoa: the Discipline signature.
-- A healer watches the group, so the party cards carry the most (your
-- shields, Weakened Soul, dispels). Around the Halo, Disc keeps its own
-- timing:
--   * coins on the ring's right for Penance (P), Inner Focus (I) and Power
--     Infusion (PI): pale gold when ready, muted and draining while they
--     come back; Inner Focus glows bone while it's waiting on your next
--     spell;
--   * SHIELDS n and RENEW n under the coins: how many in your group carry
--     your Power Word: Shield and Renew;
--   * with Inner Focus up, an outline on Greater Heal, the heal it's for.
--
-- Cooldowns are hidden in combat, so each coin times itself from your own
-- cast where the game won't say, and draws the client's own swipe where it
-- will.
local _, ns = ...
local Stoa = ns.Stoa
local UI = Stoa.UI

local Disc = Stoa:NewModule("Disc", {})

local COIN = 26
local RADIUS = 168
-- The same places as the other signatures' coins. 0 = due right.
local COIN_ANGLES = { 10, -12, -34 }

local SPELLS = {
	penance = 1240721,
	innerFocus = 14751,
	infusion = 10060,
	shield = 17,
	renew = 139,
	greaterHeal = 2060,
}

-- Cooldowns, for when the game hides them: the cast starts the timer.
local COOLDOWNS = { penance = 12, innerFocus = 180, infusion = 180 }

local COINS = {
	{ key = "penance", letter = "P" },
	{ key = "innerFocus", letter = "I" },
	{ key = "infusion", letter = "PI" },
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

local function auraByName(unit, name, filter)
	if not name or not (C_UnitAuras and C_UnitAuras.GetAuraDataBySpellName) then return nil end
	local ok, aura = pcall(C_UnitAuras.GetAuraDataBySpellName, unit, name, filter)
	if ok then return aura end
end

-- When a spell comes back and its cooldown's length; nil when it's ready.
-- The third value says whether the game would say at all (it won't in
-- combat; then your own last cast decides).
local function readyAt(key)
	local info = C_Spell and C_Spell.GetSpellCooldown and C_Spell.GetSpellCooldown(SPELLS[key])
	if type(info) ~= "table" then return nil, nil, false end
	local start, duration = Stoa:PlainNumber(info.startTime), Stoa:PlainNumber(info.duration)
	if not start or not duration then return nil, nil, false end
	if start == 0 or duration <= 1.5 then return nil, nil, true end
	return start + duration, duration, true
end

-- Everyone in your group, yourself included.
local function groupUnits()
	local units = { "player" }
	if IsInRaid() then
		units = {}
		for i = 1, GetNumGroupMembers() do units[#units + 1] = "raid" .. i end
	elseif IsInGroup() then
		for i = 1, GetNumSubgroupMembers() do units[#units + 1] = "party" .. i end
	end
	return units
end

function Disc:Active()
	local _, classFile = UnitClass("player")
	return classFile == "PRIEST" and Stoa:GetRole() == "HEALER"
end

-- Build -----------------------------------------------------------------------

function Disc:BuildCoins(halo)
	self.coins = {}
	for i, entry in ipairs(COINS) do
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
		cooldown:SetDrawEdge(false)
		cooldown:SetDrawBling(false)
		cooldown:SetHideCountdownNumbers(true)
		if cooldown.SetUseCircularEdge then cooldown:SetUseCircularEdge(true) end
		local face = CreateFrame("Frame", nil, coin)
		face:SetAllPoints()
		face:SetFrameLevel(cooldown:GetFrameLevel() + 2)
		local letter = UI.text(face, "serif", entry.letter:len() > 1 and Stoa.typeSize.body or Stoa.typeSize.label, "text", "CENTER")
		letter:SetPoint("CENTER", 0, 1)
		letter:SetText(entry.letter)
		UI.legible(letter)
		coin.ring, coin.cooldown, coin.letter, coin.key = ring, cooldown, letter, entry.key
		coin:Hide()
		self.coins[i] = coin
	end
	-- Shields and Renews out on the group, under the coins.
	local count = UI.caption(halo, "")
	local angle = math.rad(COIN_ANGLES[#COIN_ANGLES])
	count:SetPoint("TOP", halo, "CENTER", RADIUS * math.cos(angle), RADIUS * math.sin(angle) - COIN / 2 - 4)
	UI.legible(count)
	self.count = count
end

-- Updates ---------------------------------------------------------------------

local function paintCoin(coin, state)
	-- ready: pale gold, waiting on you; active: bone, in use; cooling: muted.
	local token = state == "ready" and "accent" or state == "active" and "text" or "muted"
	local r, g, b = Stoa:Color(token)
	coin.ring:SetVertexColor(r, g, b, state == "cooling" and 0.6 or 1)
	coin.letter:SetTextColor(Stoa:Color(state == "cooling" and "muted" or token))
end

function Disc:CoinState(coin)
	local key = coin.key
	if key == "innerFocus" and auraByName("player", nameOf("innerFocus"), "HELPFUL") then
		coin.cooldown:Clear()
		return "active"
	end
	local ends, length, readable = readyAt(key)
	if not readable then
		local cast = self.casts and self.casts[key]
		if cast and GetTime() - cast < COOLDOWNS[key] then
			ends, length = cast + COOLDOWNS[key], COOLDOWNS[key]
		end
		-- The client can still draw a hidden cooldown's swipe.
		if C_Spell.GetSpellCooldownDuration and coin.cooldown.SetCooldownFromDurationObject then
			local drawn = pcall(function()
				coin.cooldown:SetCooldownFromDurationObject(C_Spell.GetSpellCooldownDuration(SPELLS[key]))
			end)
			if drawn then return ends and "cooling" or "ready" end
		end
	end
	if ends and ends > GetTime() then
		coin.cooldown:SetCooldown(ends - length, length)
		return "cooling"
	end
	coin.cooldown:Clear()
	return "ready"
end

function Disc:UpdateCoins()
	local active = self:Active()
	for _, coin in ipairs(self.coins) do
		if active and knows(SPELLS[coin.key]) then
			paintCoin(coin, self:CoinState(coin))
			coin:Show()
		else
			coin.cooldown:Clear()
			coin:Hide()
		end
	end
end

function Disc:UpdateCount()
	local count = self.count
	if not self:Active() or Stoa:GetState() ~= Stoa.STATE_COMBAT then
		count:SetText("")
		return
	end
	local shields, renews = 0, 0
	for _, unit in ipairs(groupUnits()) do
		if UnitExists(unit) then
			if auraByName(unit, nameOf("shield"), "HELPFUL|PLAYER") then shields = shields + 1 end
			if auraByName(unit, nameOf("renew"), "HELPFUL|PLAYER") then renews = renews + 1 end
		end
	end
	local parts = {}
	if knows(SPELLS.shield) then parts[#parts + 1] = "SHIELDS " .. shields end
	if knows(SPELLS.renew) then parts[#parts + 1] = "RENEW " .. renews end
	count:SetText(table.concat(parts, "  "))
end

function Disc:NoteCast(spellID)
	if Stoa:IsSecret(spellID) or not spellID then return end
	local name = C_Spell.GetSpellName(spellID)
	if not name then return end
	self.casts = self.casts or {}
	for key in pairs(COOLDOWNS) do
		if name == nameOf(key) then self.casts[key] = GetTime() end
	end
end

-- Healing is read off the group, which Stoa can't judge for you; the one
-- press it can name is the heal Inner Focus is waiting for.
function Disc:UpdateNext()
	if not self:Active() then return end
	local bar = Stoa.modules.CombatBar
	if not (bar and bar.SetNext) then return end
	local inCombat = Stoa:GetState() == Stoa.STATE_COMBAT
	local focused = inCombat and auraByName("player", nameOf("innerFocus"), "HELPFUL")
	bar:SetNext(focused and nameOf("greaterHeal") or nil)
end

-- Lifecycle -------------------------------------------------------------------

function Disc:Refresh()
	self:UpdateCoins()
	self:UpdateCount()
	self:UpdateNext()
end

function Disc:OnEnable()
	local _, classFile = UnitClass("player")
	if classFile ~= "PRIEST" then return end
	local halo = Stoa.modules.Halo
	if not (halo and halo.frame) then return end
	self:BuildCoins(halo.frame)

	local function refresh() xpcall(self.Refresh, Stoa.catch, self) end
	Stoa:OnUnit("UNIT_SPELLCAST_SUCCEEDED", { "player" }, function(unit, _, spellID)
		xpcall(self.NoteCast, Stoa.catch, self, spellID)
		refresh()
	end)
	Stoa:OnUnit("UNIT_AURA", { "player" }, refresh)
	Stoa:On("SPELL_UPDATE_COOLDOWN", refresh)
	Stoa:On("GROUP_ROSTER_UPDATE", refresh)
	Stoa:On("STOA_ROLE_CHANGED", refresh)
	Stoa:On("STOA_STATE_CHANGED", refresh)
	Stoa:On("SPELLS_CHANGED", refresh)
	-- Timers tick without events; the group's auras are counted here too.
	local ticker
	ticker = Stoa:NewTicker(0.25, function()
		if Stoa:GetState() ~= Stoa.STATE_COMBAT or not self:Active() then return end
		if not xpcall(self.Refresh, Stoa.catch, self) then ticker:Cancel() end
	end)
	refresh()
end
