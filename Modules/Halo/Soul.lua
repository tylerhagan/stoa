-- Stoa: your shield's time and Weakened Soul, for priests.
-- Beside the Halo's shield gauge (under your health number): the seconds
-- left on your own Power Word: Shield, and WS with the seconds until you
-- can shield yourself again. Nothing shows when neither is running.
-- Auras can't be read in a fight, so both run from your own casts there
-- (Core/Group.lua's ledger); out of a fight Weakened Soul is read from you,
-- so a shield from another priest counts too.
local _, ns = ...
local Stoa = ns.Stoa
local UI = Stoa.UI

local Soul = Stoa:NewModule("Soul", { show = true })

local WEAKENED_SOUL = 6788
local TICK = 0.2

local function auraLeft(spellID)
	if Stoa:AurasHidden() or not (C_UnitAuras and C_UnitAuras.GetPlayerAuraBySpellID) then return nil end
	local ok, aura = pcall(C_UnitAuras.GetPlayerAuraBySpellID, spellID)
	if not ok or not aura then return nil end
	local ends = Stoa:PlainNumber(aura.expirationTime)
	if not ends or ends == 0 then return nil end
	local left = ends - GetTime()
	return left > 0 and left or nil
end

function Soul:Build()
	local halo = Stoa.modules.Halo
	if not (halo and halo.frame and halo.healthText) then return false end
	local frame = halo.frame
	local shield = UI.text(frame, "sans", Stoa.typeSize.caption, "accent", "LEFT")
	local ws = UI.text(frame, "sans", Stoa.typeSize.caption, "muted", "LEFT")
	UI.legible(shield)
	UI.legible(ws)
	if halo.shield then
		shield:SetPoint("LEFT", halo.shield, "RIGHT", 4, 0)
	else
		shield:SetPoint("TOPLEFT", halo.healthText, "BOTTOMRIGHT", 4, -6)
	end
	ws:SetPoint("LEFT", shield, "RIGHT", 6, 0)
	self.shieldText, self.wsText = shield, ws
	return true
end

function Soul:Update()
	if not self.shieldText then return end
	local halo = Stoa.modules.Halo
	local gauge = halo and halo.shield
	-- Your shield's time, only while the gauge shows it holding.
	local shieldLeft = Stoa:OwnHealLeft("player", "shield")
	if gauge and not gauge:IsShown() then shieldLeft = nil end
	local wsLeft = auraLeft(WEAKENED_SOUL) or Stoa:OwnHealLeft("player", "ws")
	if not self.db.show then shieldLeft, wsLeft = nil, nil end
	self.shieldText:SetText(shieldLeft and tostring(math.floor(shieldLeft + 0.5)) or "")
	self.wsText:SetText(wsLeft and ("WS " .. math.floor(wsLeft + 0.5)) or "")
	self.running = shieldLeft ~= nil or wsLeft ~= nil
end

function Soul:OnEnable()
	local _, classFile = UnitClass("player")
	if classFile ~= "PRIEST" or not Stoa:IsModuleEnabled("Halo") or not self:Build() then return end
	local function update() xpcall(self.Update, Stoa.catch, self) end
	Stoa:On("STOA_OWN_HEALS", update)
	Stoa:OnUnit("UNIT_AURA", { "player" }, update)
	Stoa:On("PLAYER_REGEN_ENABLED", update)
	-- A light tick while something is counting down.
	Stoa:NewTicker(TICK, function()
		if self.running then update() end
	end)
	update()
end
