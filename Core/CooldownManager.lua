-- Stoa: reading the game's Cooldown Manager.
-- Forever has Blizzard's Cooldown Manager: rows of the spells and buffs a
-- player picks (Essential, Utility, Buff icons, Buff bars). The game's own
-- code fills those rows in combat, when it hides the same timings from
-- addons. With this switched on (Combat > "Read the game's Cooldown
-- Manager", off by default until it's been tried in game), Stoa keeps the
-- Manager running, out of sight, and asks its rows two things about a spell:
--   Ready(spellID): true or false, or nil when the Manager doesn't track it
--   or won't say (a hidden value). Halo coins then know ready from cooling.
--   Active(spellID): whether a tracked buff is up, the same way.
--   Draw(cooldown, spellID): copies the row's swipe onto one of Stoa's
--   cooldown widgets; the widget accepts values Stoa can't read itself.
-- Anything the Manager doesn't track or won't say falls back to Stoa's own
-- reading (Sign.lua), so switching this on can only add.
-- /stoa cdm lists what the Manager tracks and which of its values Stoa can
-- read; run it in a fight on launch day.
local _, ns = ...
local Stoa = ns.Stoa

local Manager = Stoa:NewModule("Manager", {
	enabled = false,
	showBlizzard = false,
})
Stoa.Manager = Manager

local VIEWERS = {
	{ "EssentialCooldownViewer", "cooldown" },
	{ "UtilityCooldownViewer", "cooldown" },
	{ "BuffIconCooldownViewer", "buff" },
	{ "BuffBarCooldownViewer", "buff" },
}

local function plain(value)
	if value == nil or Stoa:IsSecret(value) then return nil end
	return value
end

function Manager:Available()
	local api = C_CooldownViewer
	if not (api and api.GetCooldownViewerCooldownInfo) then return false, "no C_CooldownViewer" end
	if api.IsCooldownViewerAvailable then
		local ok, available, reason = pcall(api.IsCooldownViewerAvailable)
		if ok and available == false then return false, reason or "not available" end
	end
	for _, entry in ipairs(VIEWERS) do
		if _G[entry[1]] then return true end
	end
	return false, "no viewer frames"
end

-- Index ---------------------------------------------------------------------------
-- Spell ID -> the row showing it. A row can answer for its base spell, the
-- spell overriding it and the spells linked to it (a buff's aura).

local function cooldownInfo(item)
	local id = item.GetCooldownID and plain(item:GetCooldownID())
	if not id then return nil end
	local ok, info = pcall(C_CooldownViewer.GetCooldownViewerCooldownInfo, id)
	return ok and type(info) == "table" and info or nil, id
end

function Manager:Index()
	self.bySpell, self.count = {}, 0
	for _, entry in ipairs(VIEWERS) do
		local viewer = _G[entry[1]]
		local items = viewer and viewer.GetItemFrames and Stoa.safe.call(viewer.GetItemFrames, viewer)
		for _, item in ipairs(type(items) == "table" and items or {}) do
			local info = cooldownInfo(item)
			if info then
				self.count = self.count + 1
				item.stoaKind = entry[2]
				self:Watch(item)
				local function note(spellID)
					spellID = plain(spellID)
					if spellID and not self.bySpell[spellID] then self.bySpell[spellID] = item end
				end
				note(info.spellID)
				note(info.overrideSpellID)
				for _, linked in ipairs(info.linkedSpellIDs or {}) do note(linked) end
			end
		end
	end
end

-- A row redrawing tells Stoa's coins to look again, a moment later so a
-- burst of rows is one refresh.
function Manager:Watch(item)
	if item.stoaWatched then return end
	item.stoaWatched = true
	local function changed()
		if Manager.queued then return end
		Manager.queued = true
		C_Timer.After(0, function()
			Manager.queued = false
			Stoa:Fire("STOA_COOLDOWNS")
		end)
	end
	for _, method in ipairs({ "RefreshSpellCooldownInfo", "RefreshCooldownInfo", "SetIsActive" }) do
		if type(item[method]) == "function" then Stoa.SafeHook(item, method, changed) end
	end
	if type(item.OnCooldownIDSet) == "function" then
		Stoa.SafeHook(item, "OnCooldownIDSet", function() Manager:Reindex() end)
	end
end

function Manager:Reindex()
	if self.reindexing then return end
	self.reindexing = true
	C_Timer.After(0.2, function()
		self.reindexing = false
		xpcall(self.Index, Stoa.catch, self)
		Stoa:Fire("STOA_COOLDOWNS")
	end)
end

function Manager:Row(spellID)
	if not (self.enabled and self.bySpell and spellID) then return nil end
	local item = self.bySpell[spellID]
	if item and plain(item:GetCooldownID()) then return item end
end

-- Questions ------------------------------------------------------------------------

function Manager:Ready(spellID)
	local item = self:Row(spellID)
	if not item or item.stoaKind ~= "cooldown" then return nil end
	local cooling = plain(item.isOnActualCooldown)
	if cooling == nil then return nil end
	return not cooling
end

function Manager:Active(spellID)
	local item = self:Row(spellID)
	if not item or item.stoaKind ~= "buff" then return nil end
	return plain(item.isActive)
end

-- Copies the row's swipe; true when it drew.
function Manager:Draw(cooldown, spellID)
	local item = self:Row(spellID)
	if not (item and cooldown) then return false end
	local start, duration = item.cooldownStartTime, item.cooldownDuration
	if item.stoaKind == "buff" and item.GetCooldownValues then
		local ok, ends, length = pcall(item.GetCooldownValues, item)
		if not ok or ends == nil then return false end
		if Stoa:IsSecret(ends) or Stoa:IsSecret(length) then
			-- The row's own Cooldown widget holds what the game drew.
			return Manager:CopyWidget(item, cooldown)
		end
		start, duration = ends - length, length
	end
	if start == nil or duration == nil then return false end
	if Stoa:IsSecret(start) or Stoa:IsSecret(duration) then
		return pcall(cooldown.SetCooldown, cooldown, start, duration) or Manager:CopyWidget(item, cooldown)
	end
	if duration <= 0 then return false end
	cooldown:SetCooldown(start, duration)
	return true
end

function Manager:CopyWidget(item, cooldown)
	local source = item.GetCooldownFrame and item:GetCooldownFrame()
	if not (source and source.GetCooldownTimes) then return false end
	local ok, start, duration = pcall(source.GetCooldownTimes, source)
	if not ok or start == nil then return false end
	-- GetCooldownTimes is in milliseconds.
	return pcall(function() cooldown:SetCooldown(start / 1000, duration / 1000) end)
end

-- Keeping it running ---------------------------------------------------------------
-- The Manager only fills its rows while it's switched on and shown, so Stoa
-- turns the game's setting on (noted, put back when this is off) and makes
-- the rows see-through rather than hiding them.

function Manager:Quiet()
	if InCombatLockdown() then
		Stoa:AfterCombat(function() self:Quiet() end)
		return
	end
	local alpha = self.db.showBlizzard and 1 or 0
	for _, entry in ipairs(VIEWERS) do
		local viewer = _G[entry[1]]
		if viewer and not (viewer.IsForbidden and viewer:IsForbidden()) then
			pcall(viewer.SetAlpha, viewer, alpha)
			if viewer.EnableMouse then pcall(viewer.EnableMouse, viewer, alpha > 0) end
		end
	end
end

function Manager:OnEnable()
	local ok, why = self:Available()
	if not ok then
		self.missing = why
		return
	end
	Stoa.GameSettings:Set("Manager", "cooldownViewerEnabled", "1")
	local function index() xpcall(self.Index, Stoa.catch, self) Stoa:Fire("STOA_COOLDOWNS") end
	Stoa:On("PLAYER_ENTERING_WORLD", function() C_Timer.After(1, index) end)
	for _, event in ipairs({ "COOLDOWN_VIEWER_DATA_LOADED", "COOLDOWN_VIEWER_TABLE_HOTFIXED",
		"COOLDOWN_VIEWER_SPELL_OVERRIDE_UPDATED", "PLAYER_SPECIALIZATION_CHANGED", "SPELLS_CHANGED" }) do
		Stoa:On(event, function() self:Reindex() end)
	end
	for _, entry in ipairs(VIEWERS) do
		local viewer = _G[entry[1]]
		if viewer and type(viewer.RefreshLayout) == "function" then
			Stoa.SafeHook(viewer, "RefreshLayout", function() self:Reindex() end)
		end
		if viewer and viewer.HookScript then
			viewer:HookScript("OnShow", function() self:Quiet() end)
		end
	end
	self:Quiet()
	index()
end

-- /stoa cdm ------------------------------------------------------------------------

local FIELDS = {
	cooldown = { "isOnActualCooldown", "cooldownIsActive", "isOnGCD", "cooldownStartTime", "cooldownDuration" },
	buff = { "isActive" },
}

local function describe(value)
	if value == nil then return "nil" end
	if Stoa:IsSecret(value) then return "hidden" end
	if type(value) == "number" then return ("%.1f"):format(value) end
	return tostring(value)
end

function Manager:Probe()
	local ok, why = self:Available()
	Stoa:Print(("Cooldown Manager: %s%s. Stoa reading it: %s. In combat: %s."):format(
		ok and "here" or "missing", ok and "" or (" (" .. tostring(why) .. ")"),
		self.enabled and "on" or "off (Settings > Combat)", InCombatLockdown() and "yes" or "no"))
	if not ok then return end
	local get = (C_CVar and C_CVar.GetCVar) or GetCVar
	Stoa:Print("  Game setting cooldownViewerEnabled = " .. tostring(get and get("cooldownViewerEnabled")))
	if not self.bySpell then xpcall(self.Index, Stoa.catch, self) end
	Stoa:Print(("  %d rows tracked."):format(self.count or 0))
	local shown = 0
	for spellID, item in pairs(self.bySpell or {}) do
		if shown >= 12 then
			Stoa:Print("  ...")
			break
		end
		shown = shown + 1
		local name = C_Spell.GetSpellName and C_Spell.GetSpellName(spellID) or tostring(spellID)
		local parts = {}
		for _, field in ipairs(FIELDS[item.stoaKind] or {}) do
			parts[#parts + 1] = field .. "=" .. describe(item[field])
		end
		Stoa:Print(("  %s (%d, %s): %s; Stoa reads ready=%s active=%s"):format(name, spellID, item.stoaKind,
			table.concat(parts, " "), describe(self:Ready(spellID)), describe(self:Active(spellID))))
	end
end

Stoa.commands.cdm = function() xpcall(Manager.Probe, Stoa.catch, Manager) end
