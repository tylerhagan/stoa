"""Stoa offline load test.

Loads every file in Stoa.toc under a mock of the game's API (mock.lua), fires
the login events and a round of common game events, runs every /stoa command,
then prints the errors and the global names the mock didn't know.

    python3 Tools/sim/run.py [CLASS]     # needs: pip install lupa
    STOA_SIM_ADDONS=Bagnon,ElvUI python3 Tools/sim/run.py   # other addons loaded
"""
import os
import sys

from lupa import lua51

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
CLASS = (sys.argv[1] if len(sys.argv) > 1 else "PRIEST").upper()

lua = lua51.LuaRuntime(unpack_returned_tuples=True)
G = lua.globals()
G.SIM_CLASS = CLASS
lua.execute(open(os.path.join(ROOT, "Tools/sim/mock.lua")).read())
others = lua.table()
for folder in filter(None, os.environ.get("STOA_SIM_ADDONS", "").split(",")):
    others[folder.strip()] = True
G.SIM_OTHER_ADDONS = others
lua.execute("""
C_AddOns.IsAddOnLoaded = function(name) return SIM_OTHER_ADDONS[name] or false end
C_AddOns.DisableAddOn = function(name) SIM_OTHER_ADDONS[name] = nil end
ReloadUI = ReloadUI or function() end
""")

errors = G.SIM_ERRORS
loader = lua.eval("""function(src, name, ns)
	local fn, err = loadstring(src, "@" .. name)
	if not fn then SIM_ERRORS[#SIM_ERRORS + 1] = err return end
	local ok, e = xpcall(function() return fn("Stoa", ns) end, function(e) return tostring(e) .. "\\n" .. debug.traceback() end)
	if not ok then SIM_ERRORS[#SIM_ERRORS + 1] = e end
end""")

ns = lua.table()
files = []
for line in open(os.path.join(ROOT, "Stoa.toc"), encoding="utf-8"):
    line = line.strip()
    if line and not line.startswith("#") and line.endswith(".lua"):
        files.append(line.replace("\\", "/"))
for f in files:
    loader(open(os.path.join(ROOT, f), encoding="utf-8").read(), f, ns)

lua.execute(r"""
local function fire(event, ...)
	for frame in pairs(EVENT_FRAMES) do
		if frame.__events[event] and frame.__scripts.OnEvent then
			local args = { ... }
			local ok, e = xpcall(function() frame.__scripts.OnEvent(frame, event, unpack(args)) end, function(e) return tostring(e) .. "\n" .. debug.traceback() end)
			if not ok then SIM_ERRORS[#SIM_ERRORS + 1] = event .. ": " .. e end
		end
	end
end
SIM_FIRE = fire
local function drain()
	for round = 1, 5 do
		local list = {}
		for i, fn in ipairs(SIM_TIMERS) do list[i] = fn end
		for i = #SIM_TIMERS, 1, -1 do SIM_TIMERS[i] = nil end
		for _, fn in ipairs(list) do
			local ok, e = xpcall(fn, function(e) return tostring(e) .. "\n" .. debug.traceback() end)
			if not ok then SIM_ERRORS[#SIM_ERRORS + 1] = "timer: " .. e end
		end
	end
end
local function updates()
	for _, o in ipairs(SIM_OBJECTS) do
		local fn = o.__scripts.OnUpdate
		if fn then
			local ok, e = xpcall(function() fn(o, 0.1) end, function(e) return tostring(e) .. "\n" .. debug.traceback() end)
			if not ok then SIM_ERRORS[#SIM_ERRORS + 1] = "OnUpdate " .. tostring(o.__name) .. ": " .. e end
		end
	end
end
fire("ADDON_LOADED", "Stoa")
fire("VARIABLES_LOADED")
fire("PLAYER_LOGIN")
fire("PLAYER_ENTERING_WORLD", true, false)
drain()
SIM_ADVANCE(1)
updates()
for _, e in ipairs({ "SPELLS_CHANGED", "PLAYER_LEVEL_UP", "GROUP_ROSTER_UPDATE", "PLAYER_TARGET_CHANGED",
	"PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED", "BAG_UPDATE_DELAYED", "QUEST_LOG_UPDATE", "UNIT_AURA",
	"PLAYER_EQUIPMENT_CHANGED", "ZONE_CHANGED_NEW_AREA", "PLAYER_XP_UPDATE", "UPDATE_EXHAUSTION",
	"TAXIMAP_OPENED", "MIRROR_TIMER_START", "PLAYER_CONTROL_LOST", "PLAYER_CONTROL_GAINED", "MERCHANT_SHOW",
	"LOOT_READY", "READY_CHECK", "UNIT_HEALTH", "UNIT_POWER_UPDATE", "PLAYER_SPECIALIZATION_CHANGED",
	"ACTIVE_TALENT_GROUP_CHANGED", "UPDATE_SHAPESHIFT_FORM", "CHAT_MSG_WHISPER", "FRIENDLIST_UPDATE" }) do
	local args = { player = true }
	if e == "PLAYER_LEVEL_UP" then fire(e, 25)
	elseif e == "MIRROR_TIMER_START" then fire(e, "BREATH", 50000, 60000, -1, 0, "Breath")
	elseif e:find("^UNIT_") then fire(e, "player")
	elseif e == "CHAT_MSG_WHISPER" then fire(e, "inv", "Friend-Realm")
	else fire(e) end
	drain()
end
SIM_ADVANCE(2)
updates()
local skip = { reset = true, safe = true, backup = true }
local words = {}
for word in pairs(Stoa.commands) do if not skip[word] then words[#words + 1] = word end end
table.sort(words)
SIM_RAN = table.concat(words, " ")
for _, word in ipairs(words) do
	local ok, e = xpcall(function() SlashCmdList.STOA(word) end, function(e) return tostring(e) .. "\n" .. debug.traceback() end)
	if not ok then SIM_ERRORS[#SIM_ERRORS + 1] = "/stoa " .. word .. ": " .. e end
	drain()
end
updates()
-- Small figures: bags with room, worn gear, a pace and gold history.
do
	local realSlots, realFree, realDurability = C_Container.GetContainerNumSlots, C_Container.GetContainerNumFreeSlots, GetInventoryItemDurability
	C_Container.GetContainerNumSlots = function(bag) return bag == 4 and 0 or 16 end
	C_Container.GetContainerNumFreeSlots = function(bag) return bag == 1 and 0 or 3, 0 end
	GetInventoryItemDurability = function(slot) return slot == 5 and 12 or 80, 100 end
	local ok, e = xpcall(function()
		local console, kit, loot = Stoa.modules.Grimoire, Stoa.modules.Kit, Stoa.modules.Loot
		if kit and kit.enabled then
			kit.windowStart = GetTime() - 600
			kit.samples = { { at = GetTime() - 300, gain = 2000 } }
			for i = 1, 4 do kit.pacedAt = nil; kit:RecordPace() end
		end
		if loot and loot.RecordRate then for i = 1, 3 do loot:RecordRate() end end
		if console and console.UpdateKit then console:UpdateKit(); console:UpdateJourney() end
		for _, button in ipairs({ console and console.gear, console and console.bags }) do
			for _, script in ipairs({ "OnEnter", "OnClick", "OnLeave" }) do
				local fn = button and button:GetScript(script)
				if fn then fn(button) end
			end
		end
		local glance = Stoa.modules.Tally
		if glance and glance.rows then
			glance.columns = 2
			for _, key in ipairs({ "durability", "bags", "goldHour", "reputation", "prof1" }) do glance:Pin(key) end
			glance:Refresh()
			for _, key in ipairs({ "durability", "bags", "goldHour", "reputation", "prof1" }) do glance:Pin(key) end
		end
	end, function(e) return tostring(e) .. "\n" .. debug.traceback() end)
	if not ok then SIM_ERRORS[#SIM_ERRORS + 1] = "Small figures: " .. e end
	C_Container.GetContainerNumSlots, C_Container.GetContainerNumFreeSlots, GetInventoryItemDurability = realSlots, realFree, realDurability
	drain()
end
-- Other addons: answer each question, keeping theirs and then Stoa's.
do
	local ok, e = xpcall(function()
		local c = Stoa.Conflicts
		for _, choice in ipairs({ "theirs", "ours" }) do
			for i = 1, 12 do
				local page = c.page
				if not (page and page:IsShown()) then break end
				page[choice]:GetScript("OnClick")(page[choice])
				drain()
			end
			SlashCmdList.STOA("addons")
			drain()
		end
	end, function(e) return tostring(e) .. "\n" .. debug.traceback() end)
	if not ok then SIM_ERRORS[#SIM_ERRORS + 1] = "Other addons: " .. e end
end
-- At a glance: every situation, hover and click each line, pin and reset.
local glance = Stoa.modules.Tally
if glance and glance.rows then
	local realInstance = IsInInstance
	glance.columns = 2
	for _, kind in ipairs({ "none", "party", "raid" }) do
		IsInInstance = function() return kind ~= "none", kind end
		local ok, e = xpcall(function()
			glance:Refresh()
			for _, row in ipairs(glance.rows) do
				if row.key then
					local enter, click, leave = row:GetScript("OnEnter"), row:GetScript("OnClick"), row:GetScript("OnLeave")
					if enter then enter(row) end
					if click then click(row, "LeftButton") end
					if leave then leave(row) end
				end
			end
			local first = glance:Chosen()[1]
			if first then glance:Pin(first); glance:Pin(first) end
			glance:Toggle("clock"); glance:Toggle("clock"); glance:Reset()
		end, function(e) return tostring(e) .. "\n" .. debug.traceback() end)
		if not ok then SIM_ERRORS[#SIM_ERRORS + 1] = "At a glance (" .. kind .. "): " .. e end
		drain()
	end
	IsInInstance = realInstance
end
-- And again in combat, with secret values.
SIM_ENTER_COMBAT()
fire("PLAYER_REGEN_DISABLED")
drain()
for _, e in ipairs({ "UNIT_HEALTH", "UNIT_POWER_UPDATE", "UNIT_AURA", "UNIT_SPELLCAST_SUCCEEDED", "UNIT_SPELLCAST_START" }) do
	fire(e, "player", "Cast-1", 589)
	fire(e, "target", "Cast-1", 589)
	drain()
end
for _, e in ipairs({ "PLAYER_TARGET_CHANGED", "GROUP_ROSTER_UPDATE", "SPELL_UPDATE_COOLDOWN", "BAG_UPDATE_COOLDOWN", "PLAYER_SWING" }) do
	fire(e)
	drain()
end
SIM_ADVANCE(1)
updates()
""")

# Places where the game's own frames return something the mock can't guess
# (the damage meter's entries hand back font strings from GetName/GetValue).
KNOWN = ["Modules/Skins/Meters.lua:41"]
errs = [errors[i] for i in range(1, len(errors) + 1)]
errs = [e for e in errs if not any(k in e for k in KNOWN)]
seen = set()
print(f"Class {CLASS}: {len(files)} files, {len(errs)} errors")
print("Commands run:", G.SIM_RAN)
for e in errs:
    head = e.split("\n")[0]
    if head in seen:
        continue
    seen.add(head)
    print("ERROR", "\n      ".join(e.split("\n")[:6]))
unknown = G.SIM_UNKNOWN
names = sorted(k for k in unknown.keys())
try:
    print("UNKNOWN GLOBALS:", " ".join(names))
except BrokenPipeError:
    pass

# Every texture and font Stoa asked for from its own folder must exist.
import glob
paths = G.SIM_PATHS
missing = []
for path in list(paths.keys()):
    norm = path.replace("\\", "/")
    if "/AddOns/Stoa/" not in norm:
        continue
    rel = norm.split("/AddOns/Stoa/", 1)[1]
    base = os.path.join(ROOT, rel)
    if not (os.path.exists(base) or glob.glob(base + ".*")):
        missing.append(rel)
print("Own files used:", sum(1 for p in paths.keys() if "AddOns" in p.replace("\\", "/")), "missing:", " ".join(sorted(missing)) or "none")

if "-v" in sys.argv:
    prints = G.SIM_PRINTS
    for i in range(1, len(prints) + 1):
        print("PRINT", prints[i])
