"""Stoa offline load test.

Loads every file in Stoa.toc under a mock of the game's API (mock.lua), fires
the login events and a round of common game events, runs every /stoa command,
then prints the errors and the global names the mock didn't know.

    python3 Tools/sim/run.py [CLASS] [-v] [--lenient]     # needs: pip install lupa
    STOA_SIM_ADDONS=Bagnon,ElvUI python3 Tools/sim/run.py   # other addons loaded

Names are checked against Tools/sim/api.txt (what Forever's own UI source
has, see apilist.py) and Tools/sim/known_missing.txt. A call to a global
function, C_ function or named frame that is in neither is INVENTED, and the
run exits 1 unless --lenient is given. Names Stoa only tests for existence
(`if C_Foo and C_Foo.Bar then`) are not counted: names outside the lists read
as nil, as in the game, and only an unguarded use fails.
"""
import os
import re
import sys

from lupa import lua51

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
ARGS = [a for a in sys.argv[1:] if not a.startswith("-")]
CLASS = (ARGS[0] if ARGS else "PRIEST").upper()
LENIENT = "--lenient" in sys.argv

lua = lua51.LuaRuntime(unpack_returned_tuples=True)
G = lua.globals()
G.SIM_CLASS = CLASS
G.SIM_DIR = os.path.join(ROOT, "Tools/sim") + "/"
lua.execute(open(os.path.join(ROOT, "Tools/sim/mock.lua")).read())
others = lua.table()
for folder in filter(None, os.environ.get("STOA_SIM_ADDONS", "").split(",")):
    others[folder.strip()] = True
G.SIM_OTHER_ADDONS = others
if os.environ.get("STOA_SIM_INTERFACE"):
    lua.execute("local i = %d; GetBuildInfo = function() return '1.15.8', '99999', 'Oct 1 2026', i end" % int(os.environ["STOA_SIM_INTERFACE"]))
lua.execute("""
C_AddOns.IsAddOnLoaded = function(name) return SIM_OTHER_ADDONS[name] or false end
C_AddOns.DisableAddOn = function(name) SIM_OTHER_ADDONS[name] = nil end
ReloadUI = ReloadUI or function() end
if SIM_OTHER_ADDONS.DoesItDie then
	DoesItDie = { API_VERSION = 1, callbacks = {} }
	function DoesItDie.GetRemainingDamage(unit) return 480, 2 end
	function DoesItDie.RegisterCallback(owner, fn) DoesItDie.callbacks[owner] = fn end
end
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
if os.environ.get("SIM_EXTRA"):  # a scratch Lua file run after the toc, to try the checks
    files.append(os.environ["SIM_EXTRA"])
for f in files:
    loader(open(os.path.join(ROOT, f), encoding="utf-8").read(), f, ns)

# STOA_SIM_SETUP=slim or minimal starts the run on that console setting (as a
# saved account would), so those builds are exercised too.
if os.environ.get("STOA_SIM_SETUP") == "slim":
    lua.execute("StoaDB = { modules = { Grimoire = { slim = true } } }")
elif os.environ.get("STOA_SIM_SETUP") == "minimal":
    lua.execute("StoaDB = { modules = { Grimoire = { enabled = false }, Halo = { restArcs = true, restFade = true }, Party = { restFade = true } } }")

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
if Stoa.blocked then
	-- Another client: nothing may have run, and the saved settings stay untouched.
	if Stoa.db ~= nil or Stoa.modules.Halo.db ~= nil then SIM_ERRORS[#SIM_ERRORS + 1] = "Client gate: Stoa touched its settings" end
	SIM_RAN = "(client gate: Stoa stayed off)"
	do return end
end
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
-- Procs with every talent known: the game-drawn coins, the list, the art
-- (the mock finds no file, so the own-arc fallback runs too).
do
	local real = IsPlayerSpell
	IsPlayerSpell = function() return true end
	local ok, e = xpcall(function()
		local procs = Stoa.modules.Procs
		if procs and procs.enabled then
			procs:Refresh()
			SlashCmdList.STOA("procs list")
			SlashCmdList.STOA("procs test")
			procs:ShowArt("sim", "Hot_Streak", { "left", "right", "top", "bottom" })
			procs:HideArt("sim")
		end
	end, function(e) return tostring(e) .. "\n" .. debug.traceback() end)
	if not ok then SIM_ERRORS[#SIM_ERRORS + 1] = "procs: " .. e end
	IsPlayerSpell = real
	drain()
end
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
-- DoesItDie: its callback and the plaque's marker and skull.
if DoesItDie and Stoa.modules.Lethal then
	local realExists = UnitExists
	UnitExists = function(u) return u == "player" or u == "target" end
	local ok, e = xpcall(function()
		for _, fn in pairs(DoesItDie.callbacks) do fn("DOTS_CHANGED", "target") end
		Stoa.modules.Lethal:Update()
		if not (Stoa.modules.Lethal.clip and Stoa.modules.Lethal.clip:IsShown()) then SIM_ERRORS[#SIM_ERRORS + 1] = "DoesItDie: marker not shown" end
	end, function(e) return tostring(e) .. "\n" .. debug.traceback() end)
	UnitExists = realExists
	if not ok then SIM_ERRORS[#SIM_ERRORS + 1] = "DoesItDie: " .. e end
end
-- Game settings: Stoa's change is noted and put back; the player's own change stays.
do
	local ok, e = xpcall(function()
		local gs = Stoa.GameSettings
		SIM_CVARS.simTest = "7"
		gs:Set("Comforts", "simTest", "9")
		assert(SIM_CVARS.simTest == "9", "set")
		gs:Restore("simTest")
		assert(SIM_CVARS.simTest == "7", "restore")
		gs:Set("Comforts", "simTest", "9")
		SIM_CVARS.simTest = "3"
		gs:Restore("simTest")
		assert(SIM_CVARS.simTest == "3", "player's value kept")
		Stoa.modules.Comforts:Camera()
		assert(gs:Held("cameraDistanceMaxZoomFactor"), "far camera noted")
		SlashCmdList.STOA("restore")
		assert(not gs:Held("cameraDistanceMaxZoomFactor"), "restore all")
		assert(SIM_CVARS.cameraDistanceMaxZoomFactor == "0", "camera put back")
	end, function(e) return tostring(e) .. "\n" .. debug.traceback() end)
	if not ok then SIM_ERRORS[#SIM_ERRORS + 1] = "Game settings: " .. e end
end
-- Cooldown Manager: rows found, ready and active read, hidden values left to Stoa.
do
	local ok, e = xpcall(function()
		local function item(id, kind, fields)
			local f = CreateFrame("Frame")
			f.cooldownID = id
			function f:GetCooldownID() return self.cooldownID end
			function f:RefreshSpellCooldownInfo() end
			function f:SetIsActive(v) self.isActive = v end
			function f:GetCooldownFrame() return self.cd end
			f.cd = CreateFrame("Cooldown")
			for k, v in pairs(fields) do f[k] = v end
			return f
		end
		local rows = {
			essential = { item(1, "cooldown", { isOnActualCooldown = true, cooldownStartTime = 100, cooldownDuration = 30 }),
				item(2, "cooldown", { isOnActualCooldown = false }) },
			buffs = { item(3, "buff", { isActive = true }) },
		}
		local spells = { [1] = 10060, [2] = 14751, [3] = 15473 }
		C_CooldownViewer = {
			IsCooldownViewerAvailable = function() return true end,
			GetCooldownViewerCooldownInfo = function(id) return { cooldownID = id, spellID = spells[id], linkedSpellIDs = {} } end,
		}
		EssentialCooldownViewer = CreateFrame("Frame")
		function EssentialCooldownViewer:GetItemFrames() return rows.essential end
		BuffIconCooldownViewer = CreateFrame("Frame")
		function BuffIconCooldownViewer:GetItemFrames() return rows.buffs end
		local m = Stoa.modules.Manager
		SIM_CVARS.cooldownViewerEnabled = "0"
		m.db.enabled = true
		m:OnEnable()
		m.enabled = true
		m:Index()
		assert(m.count == 3, "three rows, got " .. tostring(m.count))
		assert(m:Ready(10060) == false, "cooling read")
		assert(m:Ready(14751) == true, "ready read")
		assert(m:Active(15473) == true, "buff active")
		assert(m:Ready(99999) == nil, "untracked spell")
		assert(Stoa.Sign.ready(14751) == true, "Sign asks the Manager")
		local cd = CreateFrame("Cooldown")
		assert(m:Draw(cd, 10060), "draws the swipe")
		assert(SIM_CVARS.cooldownViewerEnabled == "1", "game setting on")
		local realSecret = Stoa.IsSecret
		Stoa.IsSecret = function(_, v) return v == SECRET end
		rows.essential[1].isOnActualCooldown = SECRET
		assert(m:Ready(10060) == nil, "hidden value left to Stoa")
		Stoa.IsSecret = realSecret
		rows.essential[1].isOnActualCooldown = true
		SlashCmdList.STOA("cdm")
		m.enabled = false
		assert(SIM_CVARS.cooldownViewerEnabled == "1", "still on before restore")
		Stoa.GameSettings:Restore("cooldownViewerEnabled")
		assert(SIM_CVARS.cooldownViewerEnabled == "0", "game setting put back")
	end, function(e) return tostring(e) .. "\n" .. debug.traceback() end)
	if not ok then SIM_ERRORS[#SIM_ERRORS + 1] = "Cooldown Manager: " .. e end
end
-- Logging reminder: entering a raid unlogged asks; Start logs; leaving stops.
if Stoa.modules.Logging and Stoa.modules.Logging.enabled then
	local ok, e = xpcall(function()
		local L = Stoa.modules.Logging
		local logging = false
		LoggingCombat = function(on) if on ~= nil then logging = on end return logging end
		local realInstance, realInfo = IsInInstance, GetInstanceInfo
		IsInInstance = function() return true, "raid" end
		GetInstanceInfo = function() return "Molten Core" end
		SIM_CVARS.advancedCombatLogging = "0"
		L:Check()
		assert(L.frame and L.frame:IsShown() and L.frame.state == "off", "asks in a raid")
		L:Start()
		assert(logging and L.frame.state == "on", "starts logging")
		assert(SIM_CVARS.advancedCombatLogging == "1", "advanced logging on")
		IsInInstance = function() return false, "none" end
		L:Check()
		assert(not logging, "stops on leaving")
		SlashCmdList.STOA("log test")
		IsInInstance, GetInstanceInfo = realInstance, realInfo
		Stoa.GameSettings:Restore("advancedCombatLogging")
	end, function(e) return tostring(e) .. "\n" .. debug.traceback() end)
	if not ok then SIM_ERRORS[#SIM_ERRORS + 1] = "Logging: " .. e end
end
-- Pets: with a hungry pet out of a fight, the plaque fills and FEED shows;
-- with none, a Hunter is told to call one.
if Stoa.Pet and Stoa.Pet.enabled then
	local ok, e = xpcall(function()
		local P = Stoa.Pet
		local real = { UnitExists, C_PetInfo, GetPetActionInfo, UnitName, P.Keeper, UnitHealth, UnitHealthMax, Stoa.GetState }
		UnitHealth = function() return 700 end
		UnitHealthMax = function() return 1000 end
		Stoa.GetState = function() return "world" end
		UnitExists = function(u) return u == "player" or u == "pet" end
		UnitName = function(u) return u == "pet" and "Ashmane" or "Taer" end
		C_PetInfo = { GetPetHappiness = function() return 1, 75, 0 end, CanPetEatItem = function() return false end }
		GetPetActionInfo = function(i)
			if i == 9 then return "PET_MODE_DEFENSIVE", "PET_MODE_DEFENSIVE", true, true end
			return nil
		end
		P:UpdateAll()
		local words = table.concat(P:Words(), ",")
		assert(words:find("FEED ASHMANE"), "feed word: " .. words)
		UnitExists = function(u) return u == "player" end
		P.Keeper = function() return "HUNTER" end
		words = table.concat(P:Words(), ",")
		assert(words:find("CALL PET"), "call word: " .. words)
		UnitExists, C_PetInfo, GetPetActionInfo, UnitName, P.Keeper, UnitHealth, UnitHealthMax, Stoa.GetState = unpack(real)
		P:UpdateAll()
	end, function(e) return tostring(e) .. "\n" .. debug.traceback() end)
	if not ok then SIM_ERRORS[#SIM_ERRORS + 1] = "Pet: " .. e end
end
-- Cast sequences: a /castsequence macro on a bar is found, and its
-- current step is read back by the spell's proper name.
do
	local ok, e = xpcall(function()
		local real = { GetActionInfo, GetMacroInfo, SecureCmdOptionParse, QueryCastSequence, C_Spell.GetSpellIDForSpellIdentifier, C_Spell.GetSpellName }
		local asked
		GetActionInfo = function(slot) if slot == 5 then return "macro", 1 end end
		GetMacroInfo = function() return "Shadow", 136207, "#showtooltip\r\n/castsequence reset=target Mind Blast, Shadow Word: Pain, Mind Flay" end
		SecureCmdOptionParse = function(msg) return msg end
		QueryCastSequence = function(seq) asked = seq return 2, nil, "shadow word: pain" end
		C_Spell.GetSpellIDForSpellIdentifier = function(name) return name == "shadow word: pain" and 589 or nil end
		C_Spell.GetSpellName = function(id) return id == 589 and "Shadow Word: Pain" or (real[6] and real[6](id)) end
		Stoa.Spells.ScanSequences()
		local seq = Stoa.Spells.anySequence()
		assert(seq == "reset=target Mind Blast, Shadow Word: Pain, Mind Flay", "sequence: " .. tostring(seq))
		local step = Stoa.Spells.sequenceStep(seq)
		assert(asked == seq and step == "Shadow Word: Pain", "step: " .. tostring(step))
		GetActionInfo, GetMacroInfo, SecureCmdOptionParse, QueryCastSequence, C_Spell.GetSpellIDForSpellIdentifier, C_Spell.GetSpellName = unpack(real)
		Stoa.Spells.ScanSequences()
	end, function(e) return tostring(e) .. "\n" .. debug.traceback() end)
	if not ok then SIM_ERRORS[#SIM_ERRORS + 1] = "Sequence: " .. e end
end
-- Restock: tops a bundled item up to the count, in whole bundles.
if Stoa.Restock then
	local ok, e = xpcall(function()
		local real = { GetMerchantNumItems, GetMerchantItemLink, BuyMerchantItem, C_MerchantFrame, C_Item.GetItemCount, GetMoney }
		local bought = 0
		GetMerchantNumItems = function() return 1 end
		GetMerchantItemLink = function() return "|Hitem:159::|h[Refreshing Spring Water]|h" end
		BuyMerchantItem = function(_, n) bought = bought + (n or 1) end
		C_MerchantFrame = { GetItemInfo = function() return { name = "Refreshing Spring Water", price = 25, stackCount = 5, numAvailable = -1, isPurchasable = true } end }
		C_Item.GetItemCount = function() return 3 end
		GetMoney = function() return 100000 end
		Stoa.char.restock = { [159] = 20 }
		Stoa.Restock:Run()
		assert(bought == 20, "bought " .. bought .. " of 20")
		GetMerchantNumItems, GetMerchantItemLink, BuyMerchantItem, C_MerchantFrame, C_Item.GetItemCount, GetMoney = unpack(real)
		Stoa.char.restock = {}
	end, function(e) return tostring(e) .. "\n" .. debug.traceback() end)
	if not ok then SIM_ERRORS[#SIM_ERRORS + 1] = "Restock: " .. e end
end
-- Shared layout: positions and look round-trip; a bad spot is refused.
do
	local ok, e = xpcall(function()
		local B = Stoa.Backup
		Stoa.char.positions = { halo = { "CENTER", "CENTER", 10, -20 } }
		Stoa.char.layouts = { HEALER = { party = { "TOP", "TOP", 0, -300 }, target = false } }
		Stoa.db.theme = "Tide"
		local text = B:ExportLayout()
		assert(text:find("^STOA%-LAYOUT1:"), "prefix")
		Stoa.char.positions, Stoa.char.layouts, Stoa.db.theme = {}, {}, "Bone"
		assert(B:Import(text), "imports")
		assert(Stoa.char.positions.halo[3] == 10, "position back")
		assert(Stoa.char.layouts.HEALER.party[4] == -300 and Stoa.char.layouts.HEALER.target == false, "role layout back")
		assert(Stoa.db.theme == "Tide", "look back")
		local good = B:Import('STOA-LAYOUT1:{["positions"]={["halo"]={"CENTER",1}},}')
		assert(not good, "bad spot refused")
		SlashCmdList.STOA("layout")
		Stoa.db.theme = "Bone"
	end, function(e) return tostring(e) .. "\n" .. debug.traceback() end)
	if not ok then SIM_ERRORS[#SIM_ERRORS + 1] = "Shared layout: " .. e end
end
-- Pull countdown: in a raid the combat look comes early and goes again on cancel.
do
	local ok, e = xpcall(function()
		local realRaid = IsInRaid
		IsInRaid = function() return true end
		if Stoa:IsPractising() then SlashCmdList.STOA("combat") end
		assert(Stoa:GetState() == Stoa.STATE_WORLD, "starts out of combat")
		Stoa.db.countdownCombat = "raid"
		Stoa:Fire("START_PLAYER_COUNTDOWN", "Player-1", 10, 10, true)
		assert(Stoa:GetState() == Stoa.STATE_COMBAT, "countdown brings the combat look")
		Stoa:Fire("CANCEL_PLAYER_COUNTDOWN", "Player-1", true)
		assert(Stoa:GetState() == Stoa.STATE_WORLD, "cancel puts it back")
		Stoa.db.countdownCombat = "off"
		Stoa:Fire("START_PLAYER_COUNTDOWN", "Player-1", 10, 10, true)
		assert(Stoa:GetState() == Stoa.STATE_WORLD, "off leaves it")
		Stoa.db.countdownCombat = "raid"
		IsInRaid = realRaid
	end, function(e) return tostring(e) .. "\n" .. debug.traceback() end)
	if not ok then SIM_ERRORS[#SIM_ERRORS + 1] = "Pull countdown: " .. e end
end
-- Settings window: every page and a search drawn, every setting changed
-- and put back, the lists added to and taken from, a dropdown by keys.
do
	local ok, e = xpcall(function()
		local O, W = Stoa.Options, Stoa.SettingsWindow
		assert(#O.list > 120, "settings listed: " .. #O.list)
		-- Tests above changed reload settings since login; count from here.
		O.snapshot()
		SlashCmdList.STOA("")
		assert(W.page and W.page:IsShown(), "window shows")
		for _, page in ipairs(O.PAGES) do
			W:Show(page[1])
			for _, entry in ipairs(O.onPage(page[1])) do W:Describe(entry) end
		end
		W.search:SetText("camera")
		W.search:GetScript("OnTextChanged")(W.search)
		assert(#O.search("camera") > 0, "search finds camera")
		assert(#O.search("zzzz nothing") == 0, "search finds nothing")
		W.search:SetText("")
		W.search:GetScript("OnTextChanged")(W.search)
		for _, entry in ipairs(O.list) do
			W:Show(entry.page)
			if entry.kind == "toggle" then
				local was = O.value(entry)
				O.set(entry, not was); O.set(entry, was)
				assert(O.value(entry) == was, entry.id .. " put back")
			elseif entry.kind == "choice" and not entry.set then
				local was = O.value(entry)
				for _, option in ipairs(entry.options) do O.set(entry, option[1]) end
				O.set(entry, was)
			elseif entry.kind == "words" then
				local before, had = #entry.items(), {}
				for _, item in ipairs(entry.items()) do had[item[1]] = true end
				entry.add((entry.id == "junkList" and "6948") or (entry.id == "restockList" and "6948 5") or "Simword")
				assert(#entry.items() == before + 1, entry.id .. " added")
				local last
				for _, item in ipairs(entry.items()) do if not had[item[1]] then last = item[1] end end
				entry.remove(last)
				assert(#entry.items() == before, entry.id .. " taken off")
			end
		end
		local waiting = {}
		for _, entry in ipairs(O.list) do if O.waiting(entry) then waiting[#waiting + 1] = entry.id .. "=" .. tostring(O.start[entry.id]) .. ">" .. tostring(O.value(entry)) end end
		assert(#waiting == 0, "nothing waits for a reload after putting back: " .. table.concat(waiting, " "))
		-- A reload setting changed shows in the footer.
		W:Show("plates")
		O.set(O.byId.platesOn, false)
		assert(O.pending() == 1, "one change waits")
		O.set(O.byId.platesOn, true)
		-- The theme list: open it, step down by key, choose with Enter.
		W:Show("look")
		local was = Stoa.db.theme
		local select = W.rowFor(O.byId.theme).control
		select:GetScript("OnClick")(select)
		local menu = StoaSettingsMenu
		assert(menu and menu:IsShown(), "theme list open")
		menu:GetScript("OnKeyDown")(menu, "DOWN")
		menu:GetScript("OnKeyDown")(menu, "ENTER")
		assert(Stoa.db.theme ~= was, "theme chosen by keys")
		O.set(O.byId.theme, was)
		-- Click a toggle and a segment as a player would.
		W:Show("comforts")
		local toggle = W.rowFor(O.byId.fastLoot).control
		toggle:GetScript("OnClick")(toggle)
		assert(Stoa.modules.Comforts.db.fastLoot == false, "toggle clicked")
		toggle:GetScript("OnClick")(toggle)
		W:Show("console")
		local glanceRow = W.rowFor(O.byId.glanceLines)
		local line = glanceRow.lines[1]
		line:GetScript("OnClick")(line)
		line.pin:GetScript("OnClick")(line.pin)
		line.pin:GetScript("OnClick")(line.pin)
		line:GetScript("OnClick")(line)
		glanceRow.places.buttons[3]:GetScript("OnClick")(glanceRow.places.buttons[3])
		W:Show("console")
		W:Show("mapchat")
		W:Defaults(); W:Defaults()
		W:Hide()
	end, function(e) return tostring(e) .. "\n" .. debug.traceback() end)
	if not ok then SIM_ERRORS[#SIM_ERRORS + 1] = "Settings window: " .. e end
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
-- The experience bar: a stand-in for Blizzard's container (an experience
-- bar and a reputation bar, two dividers), dressed, then swapped about the
-- way Blizzard does as you level and change faction.
do
	local xpbar = Stoa.modules.XPBar
	if xpbar and xpbar.Dress then
		local ok, e = xpcall(function()
			local container = NewObject("Frame", UIParent, "MainStatusTrackingBarContainer")
			container.BarFrameTexture = container:CreateTexture()
			local function bar(index)
				local b = NewObject("Frame", container)
				b.barIndex = index
				b.StatusBar = NewObject("StatusBar", b)
				b.StatusBar.Background = b.StatusBar:CreateTexture()
				b.StatusBar.SetBarTexture = function(own, tex) own:SetStatusBarTexture(tex) end
				b.OverlayFrame = NewObject("Frame", b)
				b.OverlayFrame.Text = b.OverlayFrame:CreateFontString()
				return b
			end
			local xp, rep = bar(4), bar(1)
			xp.ExhaustionLevelFillBar = xp:CreateTexture()
			xp.ExhaustionTick = NewObject("Button", xp)
			xp.ExhaustionTick.Normal = xp.ExhaustionTick:CreateTexture()
			rep.UpdateBarTextures = function(own, level, blue) own.StatusBar:SetBarTexture("rep") end
			container.bars = { [1] = rep, [4] = xp }
			local dividers = {}
			for i = 1, 2 do
				local d = NewObject("Frame", container)
				d.BarDividerTexture = d:CreateTexture()
				dividers[i] = d
			end
			container.HorizontalDividersPool = { EnumerateActive = function() local i = 0 return function() i = i + 1 return dividers[i] end end }
			container.UpdateDividers = function() end
			container.ResizeContainerBars = function() end
			container.ApplyPendingBarToShow = function() end
			container.GetShownBar = function() return xp end
			StatusTrackingBarManager = NewObject("Frame", UIParent, "StatusTrackingBarManager")
			xpbar:Dress()
			xp.StatusBar:SetValue(0.5)
			container:ApplyPendingBarToShow()
			xpbar:Fade(true)
			xpbar:Fade(false)
			xp.StatusBar:SetBarTexture("UI-HUD-ExperienceBar-Fill-Rested")
			rep:UpdateBarTextures(6, false)
			rep:UpdateBarTextures(2, true)
			container:UpdateDividers(20)
			container:ResizeContainerBars()
			Stoa:Fire("STOA_THEME_CHANGED")
			if not (xp.stoaDressed and rep.stoaDressed and container.stoaDressed) then
				error("not dressed")
			end
		end, function(e) return tostring(e) .. "\n" .. debug.traceback() end)
		if not ok then SIM_ERRORS[#SIM_ERRORS + 1] = "Experience bar: " .. e end
		drain()
	end
end
-- Your shield: shown out of combat with a plain amount, hidden at none.
UnitGetTotalAbsorbs = function() return 1200 end
fire("UNIT_ABSORB_AMOUNT_CHANGED", "player")
drain()
do
	local halo = Stoa.modules.Halo
	if halo and halo.shield and not halo.shield:IsShown() then
		SIM_ERRORS[#SIM_ERRORS + 1] = "Shield gauge: hidden with a shield up"
	end
end
-- Items your quests still need, read from the log's item goals.
do
	local realNum, realInfo, realGoals = C_QuestLog.GetNumQuestLogEntries, C_QuestLog.GetInfo, C_QuestLog.GetQuestObjectives
	C_QuestLog.GetNumQuestLogEntries = function() return 2, 2 end
	C_QuestLog.GetInfo = function(i) return { questID = 100 + i, isHeader = false } end
	C_QuestLog.GetQuestObjectives = function(id)
		if id == 101 then return { { type = "item", text = "Scaber Stalk: 2/5", finished = false } } end
		return { { type = "item", text = "Death Cap: 1/1", finished = true }, { type = "monster", text = "Defias slain: 0/5" } }
	end
	fire("QUEST_LOG_UPDATE")
	drain()
	local items = Stoa.Items
	if not items.questNeeds(nil, "Scaber Stalk") then SIM_ERRORS[#SIM_ERRORS + 1] = "Quest needs: Scaber Stalk missed" end
	if items.questNeeds(nil, "Death Cap") then SIM_ERRORS[#SIM_ERRORS + 1] = "Quest needs: a finished goal counted" end
	if items.questNeeds(nil, "Defias") then SIM_ERRORS[#SIM_ERRORS + 1] = "Quest needs: a kill goal counted" end
	C_QuestLog.GetNumQuestLogEntries, C_QuestLog.GetInfo, C_QuestLog.GetQuestObjectives = realNum, realInfo, realGoals
	fire("QUEST_LOG_UPDATE")
	drain()
end
-- The sparkle under the game's interact icon: shown for an object's
-- plate, hidden for an NPC's or none.
do
	local comforts = Stoa.modules.Comforts
	if comforts then
		comforts.db.questGlow = true
		local plate = CreateFrame("Frame", nil, UIParent)
		local realExists, realGO, realPlate = UnitExists, UnitIsGameObject, C_NamePlate.GetNamePlateForUnit
		local isObject = true
		UnitExists = function(u) if u == "softinteract" then return true end return realExists(u) end
		UnitIsGameObject = function(u) return u == "softinteract" and isObject end
		C_NamePlate.GetNamePlateForUnit = function(u) if u == "softinteract" then return plate end end
		fire("PLAYER_SOFT_INTERACT_CHANGED", "", "")
		drain()
		local frame = comforts.sparkleFrame
		if not (frame and frame:IsShown()) then SIM_ERRORS[#SIM_ERRORS + 1] = "Sparkle: not shown for an object" end
		isObject = false
		fire("PLAYER_SOFT_INTERACT_CHANGED", "", "")
		drain()
		if frame and frame:IsShown() then SIM_ERRORS[#SIM_ERRORS + 1] = "Sparkle: shown for an NPC" end
		UnitExists, UnitIsGameObject, C_NamePlate.GetNamePlateForUnit = realExists, realGO, realPlate
		comforts.db.questGlow = false
		fire("PLAYER_SOFT_INTERACT_CHANGED", "", "")
		drain()
	end
end
-- Finished quests on the experience bar: a stretch past the fill for the
-- experience a finished quest gives, and none without one.
do
	local xpbar = Stoa.modules.XPBar
	if xpbar and xpbar.enabled then
		local container = CreateFrame("Frame", "MainStatusTrackingBarContainer", UIParent)
		local bar = CreateFrame("Frame", nil, container)
		bar:SetSize(1000, 10)
		bar.StatusBar = CreateFrame("StatusBar", nil, bar)
		bar.StatusBar:SetSize(1000, 6)
		bar.StatusBar.GetWidth = function() return 1000 end
		bar.StatusBar:SetMinMaxValues(0, 10000)
		bar.StatusBar:SetValue(2500)
		bar.ExhaustionLevelFillBar = bar:CreateTexture()
		container.bars = { bar }
		local realNum, realInfo, realComplete, realXP = C_QuestLog.GetNumQuestLogEntries, C_QuestLog.GetInfo, C_QuestLog.IsComplete, GetQuestLogRewardXP
		C_QuestLog.GetNumQuestLogEntries = function() return 2 end
		C_QuestLog.GetInfo = function(i) return { questID = 100 + i, title = "Q" .. i } end
		C_QuestLog.IsComplete = function(id) return id == 101 end
		GetQuestLogRewardXP = function(id) return 1500 end
		xpbar:UpdateQuests()
		local stretch = bar.StatusBar.stoaQuests
		if not (stretch and stretch:IsShown()) then SIM_ERRORS[#SIM_ERRORS + 1] = "Quest XP: no stretch for a finished quest"
		else
			local width
			stretch.SetWidth = function(_, w) width = w end
			xpbar:UpdateQuests()
			if not (width and math.abs(width - 150) < 1) then SIM_ERRORS[#SIM_ERRORS + 1] = "Quest XP: stretch width " .. tostring(width) end
		end
		C_QuestLog.IsComplete = function() return false end
		xpbar:UpdateQuests()
		if stretch and stretch:IsShown() then SIM_ERRORS[#SIM_ERRORS + 1] = "Quest XP: stretch shown with nothing finished" end
		C_QuestLog.GetNumQuestLogEntries, C_QuestLog.GetInfo, C_QuestLog.IsComplete, GetQuestLogRewardXP = realNum, realInfo, realComplete, realXP
		container.bars = {}
	end
end
-- The price of one in a stack: 6 scales selling for 4s 50c are 75c each.
do
	local tooltip = Stoa.modules.Tooltip
	if tooltip and tooltip.EachPrice then
		local added
		local tip = { GetItem = function() return "Slimy Murloc Scale", "|Hitem:5784|h[Slimy Murloc Scale]|h" end, AddLine = function(_, text) added = text end }
		local realInfo = C_Item.GetItemInfo
		C_Item.GetItemInfo = function() return "Slimy Murloc Scale", nil, 1, 10, 0, "Tradeskill", "Trade Goods", 20, "", 0, 75 end
		tooltip:EachPrice(tip, { price = 450 })
		if not (added and added:find("Each")) then SIM_ERRORS[#SIM_ERRORS + 1] = "Each price: no line for a stack of 6" end
		added = nil
		tooltip:EachPrice(tip, { price = 75 })
		if added then SIM_ERRORS[#SIM_ERRORS + 1] = "Each price: a line for a single item" end
		C_Item.GetItemInfo = realInfo
	end
end
-- The target plaque: a medallion with a level badge, docked while it rests
-- on the full console, and a cast bar that shows for the target's cast.
do
	local halo = Stoa.modules.Halo
	local target = halo and halo.enabled and halo.target
	if target then
		local plaque = target.plaque
		if not (plaque.medallion and plaque.SetLevel) then SIM_ERRORS[#SIM_ERRORS + 1] = "Target plaque: no medallion" end
		plaque:SetLevel("15")
		if not plaque.badge:IsShown() then SIM_ERRORS[#SIM_ERRORS + 1] = "Target plaque: level badge hidden" end
		if (halo.targetResting and true or false) ~= (plaque.docked and true or false) then
			SIM_ERRORS[#SIM_ERRORS + 1] = "Target plaque: docked doesn't follow resting"
		end
		if not plaque.bare then
			plaque:SetDocked(true, 302)
			if not (plaque.dock and plaque.dock.join:IsShown()) then SIM_ERRORS[#SIM_ERRORS + 1] = "Target plaque: join missing when docked" end
			halo:LayoutTarget(302)
			if not target.laidDocked then SIM_ERRORS[#SIM_ERRORS + 1] = "Target plaque: not laid out docked" end
			plaque:SetDocked(false)
			halo:LayoutTarget(nil)
			if plaque.dock and plaque.dock.join:IsShown() then SIM_ERRORS[#SIM_ERRORS + 1] = "Target plaque: join stays undocked" end
			if target.laidDocked then SIM_ERRORS[#SIM_ERRORS + 1] = "Target plaque: still laid out docked" end
			halo:PlaceTarget()
		end
		local realCasting, realExists = UnitCastingInfo, UnitExists
		UnitExists = function(unit) return unit == "target" or realExists(unit) end
		UnitCastingInfo = function(unit)
			if unit == "target" then return "Fireball", "Fireball", nil, GetTime() * 1000, GetTime() * 1000 + 2500, false, 1, false end
		end
		halo:UpdateTargetCast()
		if not target.castBar:IsShown() then SIM_ERRORS[#SIM_ERRORS + 1] = "Target cast: no bar for a cast" end
		UnitCastingInfo = function() return nil end
		halo:UpdateTargetCast()
		if target.castBar:IsShown() then SIM_ERRORS[#SIM_ERRORS + 1] = "Target cast: bar stays after the cast" end
		UnitCastingInfo, UnitExists = realCasting, realExists
	end
end
-- Your own buffs: a priest without Inner Fire gets a button for it, and
-- none once it's on with time to spare.
do
	local buffs = Stoa.modules.SelfBuffs
	local _, classFile = UnitClass("player")
	if buffs and buffs.enabled and classFile == "PRIEST" then
		local realBest, realAura = Stoa.Spells.best, C_UnitAuras.GetAuraDataBySpellName
		Stoa.Spells.best = function(name) if name == "Spell588" then return 588, 1 end return realBest(name) end
		buffs:Build()
		buffs:Update()
		local first = buffs.buttons[1]
		if not (first and first:IsShown() and first.spell == "Spell588") then SIM_ERRORS[#SIM_ERRORS + 1] = "Own buffs: Inner Fire missing but no button" end
		C_UnitAuras.GetAuraDataBySpellName = function(_, name)
			if name == "Spell588" then return { name = "Spell588", duration = 600, expirationTime = GetTime() + 500 } end
		end
		buffs:Update()
		if first and first:IsShown() then SIM_ERRORS[#SIM_ERRORS + 1] = "Own buffs: button stays with Inner Fire on" end
		C_UnitAuras.GetAuraDataBySpellName = function(_, name)
			if name == "Spell588" then return { name = "Spell588", duration = 600, expirationTime = GetTime() + 40 } end
		end
		buffs:Update()
		if not (first and first:IsShown() and first.left:GetText() == "40s") then SIM_ERRORS[#SIM_ERRORS + 1] = "Own buffs: no time left shown for an ending buff (" .. tostring(first and first.left:GetText()) .. ")" end
		Stoa.Spells.best, C_UnitAuras.GetAuraDataBySpellName = realBest, realAura
		buffs:Update()
	end
end
-- Hovering the medallion's shield and mark.
do
	local console = Stoa.modules.Grimoire
	for _, key in ipairs({ "sealShield", "sealMark" }) do
		local gauge = console and console[key]
		if gauge then
			local enter, leave = gauge:GetScript("OnEnter"), gauge:GetScript("OnLeave")
			if not enter then SIM_ERRORS[#SIM_ERRORS + 1] = "Crest " .. key .. ": no tooltip" end
			local ok, e = pcall(function() enter(gauge) leave(gauge) end)
			if not ok then SIM_ERRORS[#SIM_ERRORS + 1] = "Crest " .. key .. ": " .. tostring(e) end
		end
	end
end
UnitGetTotalAbsorbs = function() return 0 end
fire("UNIT_ABSORB_AMOUNT_CHANGED", "player")
drain()
-- And again in combat, with secret values.
SIM_ENTER_COMBAT()
fire("PLAYER_REGEN_DISABLED")
drain()
UnitGetTotalAbsorbs = function() return SECRET end
fire("UNIT_ABSORB_AMOUNT_CHANGED", "player")
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

# A call that reached a name the client does not have shows up as Lua's
# "attempt to call/index ... (a nil value)" at the line that made it.
invented = {}
GLOBAL_USE = re.compile(r"(\S+?\.lua:\d+): attempt to (?:call|index) global '([A-Z]\w*)'")
FIELD_CALL = re.compile(r"(\S+?\.lua:\d+): attempt to call field '(\w+)'")
rest = []
for e in errs:
    head = e.split("\n")[0]
    m = GLOBAL_USE.search(head)
    if m and not G.SIM_ALLOWED(m.group(2)):
        invented.setdefault(m.group(2), set()).add(m.group(1))
        continue
    m = FIELD_CALL.search(head)
    if m:
        full = G.SIM_FIELD_MISSES[m.group(1) + ":" + m.group(2)]
        if full:
            invented.setdefault(full, set()).add(m.group(1))
            continue
    rest.append(e)
errs = rest
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
    methods = G.SIM_UNKNOWN_METHODS
    print("UNKNOWN METHODS (not in the widget list; informational):", " ".join(sorted(k for k in methods.keys())))
    absent = set(k for k in G.SIM_ABSENT.keys()) | set(v for v in G.SIM_FIELD_MISSES.values())
    print("ABSENT (read but not in api.txt; Stoa guarded them or never called them; informational):", " ".join(sorted(absent - set(invented))))
    for name in sorted(invented):
        print("INVENTED", name, " ".join(sorted(invented[name])))
    print("INVENTED:", len(invented))
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

# Forever's client has per-addon object caps (LimitedLuaResources in Logs/General.log;
# off on build 70634, but the numbers are there). Everything the sim made, every
# preview and /stoa command included, so a high-water mark, not a typical session.
CAPS = {"Frame": 10000, "Texture": 40000, "FontString": 5000, "AnimGroup": 2000, "Timer": 500}
FRAMES = {"Frame", "Button", "CheckButton", "StatusBar", "EditBox", "ScrollFrame", "Slider", "Cooldown", "GameTooltip", "Model", "PlayerModel", "MessageFrame", "ScrollingMessageFrame"}
made = {k: 0 for k in CAPS}
objects = G.SIM_OBJECTS
for i in range(1, len(objects) + 1):
    if not objects[i]["__made"]:
        continue
    kind = objects[i]["__type"]
    if kind in FRAMES:
        kind = "Frame"
    elif kind in ("MaskTexture", "Line"):
        kind = "Texture"
    elif kind == "AnimationGroup":
        kind = "AnimGroup"
    elif kind in ("Ticker",):
        kind = "Timer"
    if kind in made:
        made[kind] += 1
print("Objects made vs Forever's per-addon caps:", ", ".join("%s %d/%d" % (k, made[k], CAPS[k]) for k in CAPS))
over = [k for k in CAPS if made[k] > CAPS[k] * 0.5]
if over:
    print("OVER HALF A CAP:", " ".join(over))

if "-v" in sys.argv:
    prints = G.SIM_PRINTS
    for i in range(1, len(prints) + 1):
        print("PRINT", prints[i])

if "-v" in sys.argv:
    print("MOCK STAND-INS DROPPED (not in api.txt):", " ".join(sorted(k for k in G.SIM_REMOVED.keys())))
if invented and not LENIENT:
    sys.exit(1)
