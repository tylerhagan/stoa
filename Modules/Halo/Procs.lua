-- Stoa Halo: procs, shown with Blizzard's own art.
-- When something lights up (Clearcasting, Overpower, Shadow Trance...) you
-- get what the game would show, placed where Stoa's eye already is:
--   * the game's proc art (the curved flames, arcane swirls and so on),
--     either side of the Halo instead of mid-screen
--   * the game's proc flipbook round the combat bar button that holds the
--     spell, as the default action bars do
--   * the game's own proc sound
-- Two sources:
--   * the game's own proc events (SPELL_ACTIVATION_OVERLAY_*), which carry
--     the art to use; Stoa only moves them to the Halo
--   * Stoa's own reading for procs the game doesn't announce. Forever
--     hides your buffs in combat, so these watch what a proc changes: a
--     spell turning usable (Overpower), a cost dropping to nothing
--     (Clearcasting) or a cast becoming much quicker (Shadow Trance).
-- Settings: art, glow and sound each on their own; "Move the game's"
-- turns off the game's own mid-screen art while Stoa shows it by the Halo.
local _, ns = ...
local Stoa = ns.Stoa

local Procs = Stoa:NewModule("Procs", {
	art = true,
	glow = true,
	sound = true,
	-- Moves the game's own proc art to the Halo (turns the game's off).
	takeOver = true,
	scale = 1,
	-- The game's setting as it was before Stoa turned it off.
	savedGameArt = nil,
})

-- Proc art lives under Textures\SpellActivationOverlays in modern clients; the
-- Interface folder (checked against build 70634's art export) only holds the
-- icon alert pieces. Both are tried, newest first.
local ART = { "Textures\\SpellActivationOverlays\\", "Interface\\SpellActivationOverlay\\" }
-- Tried in order when a proc names art the client doesn't have.
local FALLBACK_ART = { "Generic_Arc_01", "Generic_Top_01" }

-- Each proc: what lights it, the spell whose button glows, and the art.
--   mode "usable": shown while the game says the spell can be cast;
--                  hidden for `hold` seconds after you cast it (the game
--                  still says usable while it's cooling down)
--   mode "free"  : shown while any `watch` spell costs nothing
--   mode "faster": shown while `watch` casts in under `ratio` of its
--                  usual time (0 = instant)
--   buff         : the proc's buff, read out of combat when the game allows
--   art, side    : file under Interface\SpellActivationOverlay and where it
--                  sits: "both" (left and mirrored right) or "top"
-- Spell IDs are the base rank; names are read from the client so every
-- rank and language matches.
local PROCS = {
	WARRIOR = {
		{ key = "overpower", mode = "usable", spell = 7384, hold = 5, combat = true, art = "Sudden_Death", side = "both" },
		{ key = "revenge", mode = "usable", spell = 6572, hold = 5, combat = true, art = "Sword_and_Board", side = "top" },
		{ key = "execute", mode = "usable", spell = 5308, art = "Blood_Surge", side = "both" },
		{ key = "victory", mode = "usable", spell = 402927, hold = 30, art = "Ultimatum", side = "top" },
	},
	ROGUE = {
		{ key = "riposte", mode = "usable", spell = 14251, hold = 6, combat = true, art = "Sudden_Death", side = "both" },
	},
	HUNTER = {
		{ key = "mongoose", mode = "usable", spell = 1495, hold = 5, combat = true, art = "Lock_and_Load", side = "both" },
		{ key = "counter", mode = "usable", spell = 19306, hold = 5, combat = true, art = "Sudden_Death", side = "top" },
	},
	MAGE = {
		{ key = "clearcasting", mode = "free", buff = 12536, watch = { 133, 116, 2136 }, art = "Generic_Arc_01", side = "both" },
		{ key = "barrage", mode = "free", buff = 400589, watch = { 5143 }, glowSpell = 5143, unless = "clearcasting", art = "Arcane_Missiles", side = "both" },
		{ key = "heating", mode = "faster", watch = { 11366 }, ratio = 0.5, art = "Hot_Streak", side = "both" },
	},
	WARLOCK = {
		{ key = "trance", mode = "faster", buff = 17941, watch = { 686 }, ratio = 0.1, art = "Nightfall", side = "both" },
		{ key = "decimation", mode = "faster", buff = 440873, watch = { 6353 }, ratio = 0.7, art = "Imp_Empowerment", side = "top" },
	},
	DRUID = {
		{ key = "clearcasting", mode = "free", buff = 16870, watch = { 5176, 5185, 5221, 6807, 8936 }, art = "Feral_OmenOfClarity", side = "both" },
	},
	SHAMAN = {
		{ key = "clearcasting", mode = "free", buff = 16246, watch = { 403, 421, 331 }, art = "Generic_Arc_01", side = "both" },
	},
	PRIEST = {},
	PALADIN = {},
}

local GAME_SOUND = SOUNDKIT and SOUNDKIT.UI_POWER_AURA_GENERIC

local function spellName(id)
	return id and C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(id)
end

-- Art ------------------------------------------------------------------------

local function setArt(texture, file)
	for _, name in ipairs({ file, unpack(FALLBACK_ART) }) do
		if name then
			if type(name) == "number" or name:find("\\") then
				texture:SetTexture(name)
				if type(name) == "number" or type(texture:GetTextureFileID()) == "number" then return true end
			else
				for _, folder in ipairs(ART) do
					texture:SetTexture(folder .. name)
					if type(texture:GetTextureFileID()) == "number" then return true end
				end
			end
		end
	end
	return false
end

function Procs:BuildArt()
	if self.art then return end
	local holder = CreateFrame("Frame", "StoaProcArt", UIParent)
	holder:SetFrameStrata("BACKGROUND")
	holder:SetSize(300, 300)
	holder:EnableMouse(false)
	local halo = _G.StoaHalo
	if halo then
		holder:SetPoint("CENTER", halo, "CENTER")
	else
		holder:SetPoint("CENTER", UIParent, "CENTER", 0, -60)
	end
	holder:SetScale(self.db.scale or 1)
	self.art = holder
	self.pieces = {}
end

-- One piece of art in a spot round the Halo, faded in like the game's.
local function makePiece(holder, spot)
	local piece = CreateFrame("Frame", nil, holder)
	local texture = piece:CreateTexture(nil, "ARTWORK")
	texture:SetAllPoints()
	texture:SetBlendMode("ADD")
	piece.texture = texture
	local fade = piece:CreateAnimationGroup()
	local alpha = fade:CreateAnimation("Alpha")
	alpha:SetFromAlpha(0)
	alpha:SetToAlpha(1)
	alpha:SetDuration(0.2)
	piece.fade = fade
	local pulse = piece:CreateAnimationGroup()
	pulse:SetLooping("REPEAT")
	local grow = pulse:CreateAnimation("Scale")
	grow:SetScale(1.06, 1.06)
	grow:SetDuration(0.5)
	grow:SetSmoothing("IN_OUT")
	grow:SetOrder(1)
	local shrink = pulse:CreateAnimation("Scale")
	shrink:SetScale(1 / 1.06, 1 / 1.06)
	shrink:SetDuration(0.5)
	shrink:SetSmoothing("IN_OUT")
	shrink:SetOrder(2)
	piece.pulse = pulse

	local long, short = 300, 150
	if spot == "left" then
		piece:SetSize(short, long)
		piece:SetPoint("RIGHT", holder, "LEFT", 10, 0)
	elseif spot == "right" then
		piece:SetSize(short, long)
		piece:SetPoint("LEFT", holder, "RIGHT", -10, 0)
		texture:SetTexCoord(1, 0, 0, 1)
	elseif spot == "top" then
		piece:SetSize(long, short)
		piece:SetPoint("BOTTOM", holder, "TOP", 0, -10)
	else
		piece:SetSize(long, short)
		piece:SetPoint("TOP", holder, "BOTTOM", 0, 10)
		texture:SetTexCoord(0, 1, 1, 0)
	end
	piece:Hide()
	return piece
end

-- Game positions (Enum.ScreenLocationType) to Stoa's spots.
local SPOTS = {
	[0] = { "top" }, [1] = { "left" }, [2] = { "right" }, [3] = { "top" }, [4] = { "bottom" },
	[5] = { "left" }, [6] = { "right" }, [7] = { "left" }, [8] = { "right" },
	[9] = { "left", "right" }, [10] = { "top", "bottom" }, [11] = { "left", "right" },
}

function Procs:ShowArt(owner, art, spots, r, g, b)
	if not self.db.art then return end
	self:BuildArt()
	local list = self.pieces[owner] or {}
	self.pieces[owner] = list
	local fresh = false
	for _, spot in ipairs(spots) do
		local piece = list[spot]
		if not piece then
			piece = makePiece(self.art, spot)
			list[spot] = piece
		end
		if not piece:IsShown() then
			setArt(piece.texture, art)
			piece.texture:SetVertexColor(r or 1, g or 1, b or 1)
			piece:Show()
			piece.fade:Play()
			piece.pulse:Play()
			fresh = true
		end
	end
	if fresh and self.db.sound and GAME_SOUND then PlaySound(GAME_SOUND) end
end

function Procs:HideArt(owner)
	for _, piece in pairs(self.pieces and self.pieces[owner] or {}) do
		piece.pulse:Stop()
		piece:Hide()
	end
end

-- Button glow ----------------------------------------------------------------
-- The default action bars' proc art (ActionButtonSpellAlertTemplate) on the
-- combat bar button holding the spell, matched by name across ranks.

local glowing = {}

local function alertFor(button)
	if button.stoaAlert then return button.stoaAlert end
	local ok, alert = pcall(CreateFrame, "Frame", nil, button, "ActionButtonSpellAlertTemplate")
	if not ok or not alert then return nil end
	local w, h = button:GetSize()
	alert:SetSize(w * 1.4, h * 1.4)
	alert:SetPoint("CENTER")
	button.stoaAlert = alert
	return alert
end

local function playAlert(alert)
	alert:Show()
	if alert.ProcStartAnim and alert.ProcLoop then
		alert.ProcStartAnim:SetScript("OnFinished", function() alert.ProcLoop:Play() end)
		alert.ProcStartAnim:Play()
	elseif alert.ProcLoop then
		alert.ProcLoop:Play()
	end
end

local function stopAlert(alert)
	if alert.ProcStartAnim then alert.ProcStartAnim:Stop() end
	if alert.ProcLoop then alert.ProcLoop:Stop() end
	alert:Hide()
end

function Procs:UpdateGlows()
	local bar = Stoa.modules.CombatBar
	local want = {}
	if self.db.glow then
		for name in pairs(glowing) do want[name] = true end
	end
	for _, button in ipairs(bar and bar.all or {}) do
		local match = false
		if next(want) and button.slot and GetActionInfo then
			local kind, id = GetActionInfo(button.slot)
			if kind == "spell" and id and not Stoa:IsSecret(id) then
				match = want[C_Spell.GetSpellName(id) or false] or false
			end
		end
		local alert = button.stoaAlert
		if match and button:IsVisible() then
			alert = alertFor(button)
			if alert and not alert:IsShown() then playAlert(alert) end
		elseif alert and alert:IsShown() then
			stopAlert(alert)
		end
	end
end

function Procs:Glow(owner, spellID, on)
	local name = spellName(spellID)
	if not name then return end
	glowing[name] = glowing[name] or {}
	glowing[name][owner] = on or nil
	if not next(glowing[name]) then glowing[name] = nil end
	self:UpdateGlows()
end

-- Stoa's own reading -----------------------------------------------------------

local castAt = {}
local usualCast = {}

local function usable(id)
	local name = spellName(id)
	if not name then return false end
	local check = (C_Spell and C_Spell.IsSpellUsable) or IsUsableSpell
	if not check then return false end
	local ok, yes = pcall(check, name)
	return ok and yes == true
end

local function cost(id)
	local name = spellName(id)
	if not (name and C_Spell and C_Spell.GetSpellPowerCost) then return nil end
	local ok, list = pcall(C_Spell.GetSpellPowerCost, name)
	if not ok or type(list) ~= "table" or not list[1] then return nil end
	return Stoa:PlainNumber(list[1].cost)
end

local function castTime(id)
	local name = spellName(id)
	if not (name and C_Spell and C_Spell.GetSpellInfo) then return nil end
	local ok, info = pcall(C_Spell.GetSpellInfo, name)
	return ok and type(info) == "table" and Stoa:PlainNumber(info.castTime) or nil
end

local function hasBuff(id)
	if not (id and C_UnitAuras and C_UnitAuras.GetPlayerAuraBySpellID) then return nil end
	local ok, aura = pcall(C_UnitAuras.GetPlayerAuraBySpellID, id)
	if not ok or Stoa:IsSecret(aura) then return nil end
	return aura ~= nil
end

local function knows(proc)
	local id = proc.spell or (proc.watch and proc.watch[1])
	if not id then return false end
	if IsPlayerSpell and IsPlayerSpell(id) then return true end
	local name = spellName(id)
	return name and C_Spell.GetSpellInfo and C_Spell.GetSpellInfo(name) ~= nil or false
end

local function lit(proc, active)
	if proc.combat and not InCombatLockdown() then return false end
	if proc.unless and active[proc.unless] then return false end
	-- Out of combat the buff itself can be read; trust it when it can.
	if proc.buff and not InCombatLockdown() then
		local seen = hasBuff(proc.buff)
		if seen ~= nil and proc.mode ~= "usable" then return seen end
	end
	if proc.mode == "usable" then
		local last = castAt[proc.key]
		if last and proc.hold and GetTime() - last < proc.hold then return false end
		return usable(proc.spell)
	elseif proc.mode == "free" then
		for _, id in ipairs(proc.watch) do
			if cost(id) == 0 and (usualCast["cost" .. id] or 0) > 0 then return true end
		end
		return false
	elseif proc.mode == "faster" then
		local id = proc.watch[1]
		local now, usual = castTime(id), usualCast[id]
		if not (now and usual and usual > 0) then return false end
		return now <= usual * proc.ratio
	end
	return false
end

-- Learns each watched spell's normal cost and cast time while nothing is lit.
function Procs:Learn()
	for _, proc in ipairs(self.list or {}) do
		for _, id in ipairs(proc.watch or {}) do
			local price = cost(id)
			if price and price > 0 then usualCast["cost" .. id] = math.max(usualCast["cost" .. id] or 0, price) end
			local time = castTime(id)
			if time and time > 0 then usualCast[id] = math.max(usualCast[id] or 0, time) end
		end
	end
end

function Procs:Check()
	local active = self.active
	for _, proc in ipairs(self.list or {}) do
		local on = proc.known and lit(proc, active) or false
		if on ~= (active[proc.key] or false) then
			active[proc.key] = on or nil
			local owner = "own:" .. proc.key
			if on then
				local spots = proc.side == "top" and { "top" } or { "left", "right" }
				self:ShowArt(owner, proc.art, spots)
			else
				self:HideArt(owner)
			end
			self:Glow(owner, proc.glowSpell or proc.spell or proc.watch[1], on)
		end
	end
end

function Procs:Refresh()
	local _, class = UnitClass("player")
	self.list = PROCS[class] or {}
	for _, proc in ipairs(self.list) do proc.known = knows(proc) end
	self:Learn()
	self:Check()
end

-- The game's own proc events -------------------------------------------------

function Procs:TakeOver(on)
	local get = (C_CVar and C_CVar.GetCVar) or GetCVar
	local set = (C_CVar and C_CVar.SetCVar) or SetCVar
	if not (get and set) then return end
	if on then
		if self.db.savedGameArt == nil then self.db.savedGameArt = get("displaySpellActivationOverlays") or "1" end
		pcall(set, "displaySpellActivationOverlays", "0")
	elseif self.db.savedGameArt ~= nil then
		pcall(set, "displaySpellActivationOverlays", self.db.savedGameArt)
		self.db.savedGameArt = nil
	end
end

function Procs:OnGameShow(spellID, texture, location, _, r, g, b)
	if Stoa:IsSecret(spellID) or Stoa:IsSecret(texture) then return end
	if not self.db.takeOver then return end
	self:ShowArt("game:" .. tostring(spellID), texture, SPOTS[location] or { "left", "right" }, r, g, b)
end

-- Test ----------------------------------------------------------------------

function Procs:Test()
	self:ShowArt("test", "Generic_Arc_01", { "left", "right" })
	local first = self.list and self.list[1]
	if first then self:Glow("test", first.glowSpell or first.spell or first.watch[1], true) end
	C_Timer.After(4, function()
		self:HideArt("test")
		if first then self:Glow("test", first.glowSpell or first.spell or first.watch[1], false) end
	end)
	Stoa:Print("Proc art for four seconds by the Halo" .. (first and ", and the glow on its combat bar button." or "."))
end

function Procs:OnEnable()
	self.active = {}
	self:TakeOver(self.db.takeOver and self.db.art)
	Stoa:On("SPELL_ACTIVATION_OVERLAY_SHOW", function(...) xpcall(self.OnGameShow, Stoa.catch, self, ...) end)
	Stoa:On("SPELL_ACTIVATION_OVERLAY_HIDE", function(spellID)
		if spellID == nil then
			for owner in pairs(self.pieces or {}) do
				if owner:find("^game:") then self:HideArt(owner) end
			end
		elseif not Stoa:IsSecret(spellID) then
			self:HideArt("game:" .. tostring(spellID))
		end
	end)
	Stoa:On("SPELL_ACTIVATION_OVERLAY_GLOW_SHOW", function(spellID)
		if not Stoa:IsSecret(spellID) then self:Glow("game", spellID, true) end
	end)
	Stoa:On("SPELL_ACTIVATION_OVERLAY_GLOW_HIDE", function(spellID)
		if not Stoa:IsSecret(spellID) then self:Glow("game", spellID, false) end
	end)
	Stoa:OnUnit("UNIT_SPELLCAST_SUCCEEDED", { "player" }, function(_, _, spellID)
		if Stoa:IsSecret(spellID) then return end
		local name = spellName(spellID)
		for _, proc in ipairs(self.list or {}) do
			if proc.mode == "usable" and name and name == spellName(proc.spell) then castAt[proc.key] = GetTime() end
		end
		self:Check()
	end)
	local function refresh() xpcall(self.Refresh, Stoa.catch, self) end
	for _, event in ipairs({ "SPELLS_CHANGED", "PLAYER_REGEN_ENABLED", "PLAYER_ENTERING_WORLD" }) do
		Stoa:On(event, refresh)
	end
	local function check() xpcall(self.Check, Stoa.catch, self) end
	for _, event in ipairs({ "SPELL_UPDATE_USABLE", "PLAYER_TARGET_CHANGED", "PLAYER_REGEN_DISABLED" }) do
		Stoa:On(event, check)
	end
	Stoa:OnUnit("UNIT_AURA", { "player" }, check)
	Stoa:On("ACTIONBAR_SLOT_CHANGED", function() self:UpdateGlows() end)
	-- Windows close on their own (a proc running out fires nothing).
	-- On the combat clock in a fight; a slower ticker covers them out of combat,
	-- where procs still open and close.
	Stoa:On("STOA_TICK", function() if self.list and #self.list > 0 then self:Check() end end)
	Stoa:NewTicker(0.5, function()
		if Stoa:GetState() ~= Stoa.STATE_COMBAT and self.list and #self.list > 0 then self:Check() end
	end)
	refresh()
	Stoa.commands.procs = function(rest)
		if rest == "test" then
			self:Test()
		else
			Stoa:Print("/stoa procs test shows the proc art and glow. Options are in Settings, Procs.")
		end
	end
end

function Procs:OnDisable()
	self:TakeOver(false)
end
