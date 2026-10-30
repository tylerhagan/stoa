-- Stoa: the game settings Stoa changes, and putting them back.
-- A few of Stoa's features work through the game's own settings (CVars): the
-- far camera, the map fading while you move, the size of your target's
-- nameplate, combined bags, the game's proc art. Every such change goes
-- through Stoa.GameSettings:Set, which notes what the setting held before
-- Stoa's first change (account-wide, in StoaDB.gameSettings) and what Stoa
-- left it at.
--   Restore puts one back, but only while it still holds Stoa's value: one
--   the player has changed since is theirs and stays.
--   At login, a setting whose part of Stoa is switched off is put back.
--   /stoa restore puts every one back (and /stoa safe does it for the skins).
-- Some settings can't change in combat, so a change waits for the fight's end.
local _, ns = ...
local Stoa = ns.Stoa

local GameSettings = {}
Stoa.GameSettings = GameSettings

local function get(name)
	local fn = (C_CVar and C_CVar.GetCVar) or GetCVar
	if not fn then return nil end
	local ok, value = pcall(fn, name)
	if ok and not Stoa:IsSecret(value) then return value end
end

local function set(name, value)
	local fn = (C_CVar and C_CVar.SetCVar) or SetCVar
	if not fn then return false end
	return pcall(fn, name, value)
end

local function ledger()
	Stoa.db.gameSettings = Stoa.db.gameSettings or {}
	return Stoa.db.gameSettings
end

-- Sets name to value for owner (a module name), noting the value before.
function GameSettings:Set(owner, name, value)
	value = tostring(value)
	if InCombatLockdown() then
		Stoa:AfterCombat(function() self:Set(owner, name, value) end)
		return
	end
	local entry = ledger()[name]
	local now = get(name)
	if not entry then
		if now == nil then return end
		entry = { before = now, owner = owner }
		ledger()[name] = entry
	end
	entry.stoa = value
	if now ~= value then set(name, value) end
end

-- Puts name back as it was before Stoa, unless the player has changed it.
function GameSettings:Restore(name)
	local entry = ledger()[name]
	if not entry then return end
	if InCombatLockdown() then
		Stoa:AfterCombat(function() self:Restore(name) end)
		return
	end
	if get(name) == entry.stoa then set(name, entry.before) end
	ledger()[name] = nil
end

-- Every setting a module changed.
function GameSettings:RestoreOwner(owner)
	for name, entry in pairs(ledger()) do
		if entry.owner == owner then self:Restore(name) end
	end
end

function GameSettings:RestoreAll()
	for name in pairs(ledger()) do self:Restore(name) end
end

-- Whether Stoa holds name now, for settings pages and /stoa report.
function GameSettings:Held(name)
	return ledger()[name] ~= nil
end

-- At login: settings whose part of Stoa is off go back.
function GameSettings:Tidy()
	for name, entry in pairs(ledger()) do
		if entry.owner and Stoa.modules[entry.owner] and not Stoa:IsModuleEnabled(entry.owner) then
			self:Restore(name)
		end
	end
end

Stoa:On("STOA_READY", function()
	xpcall(GameSettings.Tidy, Stoa.catch, GameSettings)
end)

Stoa.commands.restore = function()
	local count = 0
	for _ in pairs(ledger()) do count = count + 1 end
	GameSettings:RestoreAll()
	if count == 0 then
		Stoa:Print("Stoa hasn't changed any game settings.")
	else
		Stoa:Print(("Put back %d game setting%s Stoa had changed. Parts still switched on set theirs again at the next login; switch them off to keep the game's."):format(count, count == 1 and "" or "s"))
	end
end
