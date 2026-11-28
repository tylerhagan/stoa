-- Stoa: error record and /stoa report.
-- Errors from Stoa's own code come through Stoa:Fail. Each is kept once with
-- a count, so /stoa report can show what went wrong this session. If one
-- error repeats fast enough to be a loop (a handler failing every frame),
-- the part of Stoa it came from is switched off until the next reload, so
-- an error can never lock up the screen.
local _, ns = ...
local Stoa = ns.Stoa
local UI

local Report = {}
Stoa.Report = Report

local MAX_KEPT = 50
local LOOP_COUNT = 20
local LOOP_SECONDS = 5
-- After this many, the same error is counted but no longer shown again.
local MAX_SHOWN = 3

-- Files whose module goes by another name.
local FILE_MODULES = { Console = "Grimoire", Housing = "Grimoire", Preview = "Raid", Raid = "Raid" }

local kept, byMessage = {}, {}
Report.errors = kept

-- "Interface action failed because of an AddOn": the game names the addon
-- and the protected function it was blocked from, so the report can say
-- who it was, STOA or another addon.
local blocked, blockedByKey = {}, {}
Report.blocked = blocked
local MAX_BLOCKED = 20
local MAX_KEPT_BLOCKED = 8

local function noteBlocked(event, addon, func)
	local key = tostring(addon) .. ":" .. tostring(func)
	local entry = blockedByKey[key]
	if not entry then
		entry = { addon = tostring(addon), func = tostring(func), count = 0, forbidden = event == "ADDON_ACTION_FORBIDDEN" }
		-- The first time: when, whether in a fight, and what the mouse was
		-- over, so there is something to go on.
		local over = "nothing"
		local ok, foci = pcall(function() return GetMouseFoci and GetMouseFoci() end)
		local focus = ok and type(foci) == "table" and foci[1]
		if focus then
			local named, name = pcall(function() return focus.GetDebugName and focus:GetDebugName() or focus:GetName() end)
			over = named and type(name) == "string" and name or "an unnamed frame"
		end
		entry.where = ("%s, %s, mouse over %s"):format(date and date("%H:%M:%S") or "?", InCombatLockdown() and "in combat" or "out of combat", over)
		blockedByKey[key] = entry
		if #blocked < MAX_BLOCKED then blocked[#blocked + 1] = entry end
		-- Kept past a reload too: the reload that follows one of these used
		-- to wipe the only record of it. The last few, newest last.
		if Stoa.db then
			local log = Stoa.db.blockedLog
			if type(log) ~= "table" then log = {} Stoa.db.blockedLog = log end
			log[#log + 1] = ("%s  %s calling %s%s, %s"):format(date and date("%d %b") or "?", entry.addon, entry.func, entry.forbidden and " (forbidden)" or "", entry.where)
			while #log > MAX_KEPT_BLOCKED do table.remove(log, 1) end
		end
	end
	entry.count = entry.count + 1
end
Stoa:On("ADDON_ACTION_BLOCKED", function(addon, func) noteBlocked("ADDON_ACTION_BLOCKED", addon, func) end)
Stoa:On("ADDON_ACTION_FORBIDDEN", function(addon, func) noteBlocked("ADDON_ACTION_FORBIDDEN", addon, func) end)
-- Some refusals never reach those events: the game only writes its line
-- in chat. That line is watched for too, and noted with what was going on
-- (the fight, your health, the events STOA had just answered).
Stoa:On("CHAT_MSG_SYSTEM", function(text)
	if Stoa:IsSecret(text) or type(text) ~= "string" then return end
	local line = rawget(_G, "INTERFACE_ACTION_BLOCKED")
	if not line or text ~= line then return end
	local now, events = GetTime and GetTime() or 0, {}
	local names, times = Stoa:RecentEvents()
	for i, name in ipairs(names) do
		if name ~= "CHAT_MSG_SYSTEM" then
			events[#events + 1] = ("%s -%.1fs"):format(name, now - (times[i] or now))
		end
	end
	local health, max = UnitHealth("player"), UnitHealthMax("player")
	local share = not Stoa:IsSecret(health) and not Stoa:IsSecret(max) and max and max > 0 and math.floor(health / max * 100) .. "%" or "hidden"
	local dead = UnitIsDeadOrGhost and UnitIsDeadOrGhost("player")
	noteBlocked("ADDON_ACTION_BLOCKED", "unnamed (chat line only)",
		("health %s%s; events before it: %s"):format(share, dead == true and ", dead" or "", table.concat(events, ", ")))
end)

-- The game's own taint log names what these miss. Level 1 only: it
-- records blocked actions. Level 2 writes every tainted read and makes
-- the game stutter. /stoa taint keeps it
-- switched on (it does not always stay on by itself); the log is the file
-- Logs\taint.log, written when you reload or log out.
local function taintLog(level)
	local set = (C_CVar and C_CVar.SetCVar) or SetCVar
	if set then pcall(set, "taintLog", level) end
end
Stoa:On("PLAYER_LOGIN", function()
	if Stoa.db and Stoa.db.taintWatch then taintLog("1") end
end)
Stoa.commands = Stoa.commands or {}
Stoa.commands.taint = function()
	Stoa.db.taintWatch = not Stoa.db.taintWatch or nil
	taintLog(Stoa.db.taintWatch and "1" or "0")
	Stoa:Print(Stoa.db.taintWatch and "The game's taint log is on and STOA will keep it on. After the next \"Interface action failed\" line, /reload so the game writes it."
		or "The game's taint log is off again.")
end

-- The same refusal reached through a macro or a secure click names only
-- the function, not the addon.
Stoa:On("MACRO_ACTION_BLOCKED", function(func) noteBlocked("ADDON_ACTION_BLOCKED", "a macro or secure click", func) end)
Stoa:On("MACRO_ACTION_FORBIDDEN", function(func) noteBlocked("ADDON_ACTION_FORBIDDEN", "a macro or secure click", func) end)

local function now()
	return GetTime and GetTime() or 0
end

-- Which module an error came from, from the file it names.
local function moduleOf(message)
	local file = message:match("Stoa[\\/].-([%w_]+)%.lua") or message:match("([%w_]+)%.lua:%d+")
	if not file then return nil end
	local name = FILE_MODULES[file] or file
	return Stoa.modules[name] and name or nil
end

-- The first line of the stack outside the error handler, for the report.
local function firstStackLine()
	if not debugstack then return nil end
	for line in debugstack(3, 6, 0):gmatch("[^\n]+") do
		if not line:find("Report%.lua") and not line:find("Init%.lua") then return strtrim(line) end
	end
end

-- Turns a module off for the rest of the session. Stoa's handlers and
-- guarded timers skip a tripped module; its frames stay as they were.
function Report:Trip(name)
	local module = Stoa.modules[name]
	if not module or module.tripped then return end
	module.tripped = true
	if module.OnTrip then pcall(module.OnTrip, module) end
	Stoa:Print(("%s kept erroring, so it's switched off until you /reload. /stoa report has the details."):format(name))
end

-- Records an error. Returns true when the module it came from has just been
-- switched off, so the caller can drop the handler.
function Stoa:Fail(err, owner)
	local message = tostring(err)
	local entry = byMessage[message]
	local time = now()
	if not entry then
		local ok, where = pcall(firstStackLine)
		entry = { message = message, count = 0, owner = owner or moduleOf(message), where = ok and where or nil, windowStart = time, windowCount = 0 }
		byMessage[message] = entry
		if #kept < MAX_KEPT then kept[#kept + 1] = entry end
	end
	entry.count = entry.count + 1
	entry.last = time
	if time - entry.windowStart > LOOP_SECONDS then
		entry.windowStart, entry.windowCount = time, 0
	end
	entry.windowCount = entry.windowCount + 1
	if entry.count <= MAX_SHOWN then geterrorhandler()(err) end
	if entry.windowCount > LOOP_COUNT and entry.owner then
		local module = Stoa.modules[entry.owner]
		if module and not module.tripped then
			Report:Trip(entry.owner)
			return true
		end
	end
	return false
end

-- For xpcall: xpcall(fn, Stoa.catch, ...).
function Stoa.catch(err)
	Stoa:Fail(err)
	return err
end

-- Wraps a ticker, OnUpdate or hook callback so an error in it is recorded
-- and, once its module is switched off, it stops running at all.
function Stoa:Guard(fn, owner)
	owner = owner or self.loading
	return function(...)
		local module = owner and Stoa.modules[owner]
		if module and module.tripped then return end
		return select(2, xpcall(fn, function(err) Stoa:Fail(err, owner) end, ...))
	end
end

-- A repeating timer whose callback is guarded the same way.
function Stoa:NewTicker(seconds, fn, iterations)
	return C_Timer.NewTicker(seconds, self:Guard(fn), iterations)
end

-- An OnUpdate script that stops itself on its first error, since it would
-- otherwise fail again every frame.
function Stoa:GuardUpdate(fn, owner)
	owner = owner or self.loading
	return function(frame, ...)
		if not xpcall(fn, function(err) Stoa:Fail(err, owner) end, frame, ...) then
			frame:SetScript("OnUpdate", nil)
		end
	end
end

-- hooksecurefunc with the hook guarded. Modules that hook Blizzard code
-- take this in place of the global, so a hook that fails on every call is
-- recorded and quietened rather than shown each time.
function Stoa.SafeHook(target, method, fn)
	if fn then
		return hooksecurefunc(target, method, Stoa:Guard(fn))
	end
	return hooksecurefunc(target, Stoa:Guard(method))
end

-- The page --------------------------------------------------------------------

local function enabledModules()
	local on, off = {}, {}
	for name, module in pairs(Stoa.modules) do
		if module.tripped then
			off[#off + 1] = name .. " (switched off after errors)"
		elseif Stoa:IsModuleEnabled(name) and module.enabled ~= false then
			on[#on + 1] = name
		else
			off[#off + 1] = name
		end
	end
	table.sort(on)
	table.sort(off)
	return on, off
end

-- Resolution, UI scale and whether the game's own scale setting is on.
local function screen()
	local parts = {}
	if GetPhysicalScreenSize then
		local w, h = GetPhysicalScreenSize()
		if w and h then parts[#parts + 1] = ("%dx%d"):format(w, h) end
	end
	if UIParent and UIParent.GetScale then parts[#parts + 1] = ("UI scale %.2f"):format(UIParent:GetScale()) end
	local get = (C_CVar and C_CVar.GetCVar) or GetCVar
	local useScale = get and get("useUiScale")
	if useScale == "1" then parts[#parts + 1] = "scale set in the game's options" end
	return #parts > 0 and table.concat(parts, ", ") or "?"
end

-- Other addons switched on, by folder name.
local function otherAddons()
	local list = {}
	local count = C_AddOns and C_AddOns.GetNumAddOns and C_AddOns.GetNumAddOns() or 0
	for i = 1, count do
		local name = C_AddOns.GetAddOnInfo(i)
		if name and name ~= "Stoa" and C_AddOns.IsAddOnLoaded(i) then list[#list + 1] = name end
	end
	table.sort(list)
	return list
end

function Report:Text()
	local lines = {}
	local function add(...)
		local parts = { ... }
		for i = 1, select("#", ...) do parts[i] = tostring(parts[i]) end
		lines[#lines + 1] = table.concat(parts)
	end
	local version, build, date, interface = "", "", "", ""
	if GetBuildInfo then version, build, date, interface = GetBuildInfo() end
	add("STOA ", Stoa.version or "dev")
	add("Game ", tostring(version), " (", tostring(build), ", ", tostring(date), "), interface ", tostring(interface))
	local className, classFile = UnitClass("player")
	local spec = (C_SpecializationInfo and C_SpecializationInfo.GetActiveSpecGroup and C_SpecializationInfo.GetActiveSpecGroup())
		or (GetActiveTalentGroup and GetActiveTalentGroup()) or "?"
	add("Character: ", tostring(className or classFile), ", level ", tostring(UnitLevel and UnitLevel("player") or "?"), ", spec slot ", tostring(spec), ", role ", tostring(Stoa:GetRole()))
	add("Theme: ", tostring(Stoa.db and Stoa.db.theme), Stoa.ThemeName and (" (" .. Stoa:ThemeName() .. ")") or "")
	add("Screen: ", screen())
	add("Language: ", tostring(GetLocale and GetLocale() or "?"))
	local held = Stoa.GameSettings and Stoa.GameSettings:List() or {}
	add("Game settings STOA holds: ", #held > 0 and table.concat(held, ", ") or "none")
	local on, off = enabledModules()
	add("On: ", table.concat(on, ", "))
	add("Off: ", #off > 0 and table.concat(off, ", ") or "none")
	local others = otherAddons()
	add("Other addons (", #others, "): ", #others > 0 and table.concat(others, ", ") or "none")
	add("")
	if Stoa.Check then
		local ok, text = pcall(Stoa.Check.Text, Stoa.Check)
		if ok then add(text) add("") end
	end
	local console = Stoa.modules and Stoa.modules.Grimoire
	if console and console.ChatState then
		local ok, text = pcall(console.ChatState, console)
		if ok then add("Chat: ", text, InCombatLockdown() and " (in combat)" or "") add("") end
	end
	do
		local get = (C_CVar and C_CVar.GetCVar) or GetCVar
		local level = get and get("taintLog")
		add("Taint log: ", tostring(level), Stoa.db and Stoa.db.taintWatch and " (kept on by /stoa taint)" or "")
		add("")
	end
	if #blocked > 0 then
		add("Blocked actions this session (the game's \"Interface action failed because of an AddOn\"):")
		for _, entry in ipairs(blocked) do
			add("  x", entry.count, " ", entry.addon, " calling ", entry.func, entry.forbidden and " (forbidden)" or "")
			if entry.where then add("     first at ", entry.where) end
		end
		add("")
	end
	local earlier = Stoa.db and Stoa.db.blockedLog
	if type(earlier) == "table" and #earlier > 0 then
		add("Blocked actions kept from this and earlier sessions (newest last):")
		for _, text in ipairs(earlier) do add("  ", tostring(text)) end
		add("")
	end
	if #kept == 0 then
		add("No errors from STOA this session.")
	else
		add(#kept, #kept == 1 and " error" or " errors", " this session:")
		for i, entry in ipairs(kept) do
			add("")
			add(i, ". x", entry.count, entry.owner and (" in " .. entry.owner) or "", ": ", entry.message)
			if entry.where then add("   at ", entry.where) end
		end
	end
	return table.concat(lines, "\n")
end

local WIDTH, HEIGHT = 600, 400
local PAD = 24 -- Stoa.space.xl; Tokens.lua loads after this file

function Report:Build()
	UI = Stoa.UI
	local page = CreateFrame("Frame", "StoaReportPage", UIParent)
	page:SetSize(WIDTH, HEIGHT)
	UI.riseOnShow(page)
	page:SetPoint("CENTER", 0, 60)
	page:SetFrameStrata("DIALOG")
	page:EnableMouse(true)
	page:SetMovable(true)
	page:RegisterForDrag("LeftButton")
	page:SetScript("OnDragStart", page.StartMoving)
	page:SetScript("OnDragStop", page.StopMovingOrSizing)
	page:Hide()
	table.insert(UISpecialFrames, "StoaReportPage")
	UI.windowPanel(page, 0.97, { header = 98, footer = 66 })
	self.page = page

	local title = UI.text(page, "serif", Stoa.typeSize.display, "text")
	title:SetPoint("TOPLEFT", PAD, -PAD)
	title:SetText("Report")
	local lede = UI.text(page, "italic", Stoa.typeSize.label, "muted", "LEFT")
	lede:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -6)
	lede:SetPoint("RIGHT", page, "RIGHT", -PAD, 0)
	lede:SetText("Your setup and any errors STOA caught this session. Copy it and send it along with what you were doing.")

	local holder = CreateFrame("Frame", nil, page)
	holder:SetPoint("TOPLEFT", PAD, -110)
	holder:SetPoint("BOTTOMRIGHT", -PAD, 78)
	UI.well(holder, 0)
	local scroll = CreateFrame("ScrollFrame", nil, holder, "UIPanelScrollFrameTemplate")
	scroll:SetPoint("TOPLEFT", 8, -8)
	scroll:SetPoint("BOTTOMRIGHT", -28, 8)
	local box = CreateFrame("EditBox", nil, scroll)
	box:SetMultiLine(true)
	box:SetAutoFocus(false)
	box:SetWidth(WIDTH - PAD * 2 - 40)
	Stoa:SetFont(box, "sans", Stoa.typeSize.caption)
	box:SetTextColor(Stoa:Color("text"))
	box:SetScript("OnEscapePressed", function(edit) edit:ClearFocus() end)
	scroll:SetScrollChild(box)
	holder:EnableMouse(true)
	holder:SetScript("OnMouseDown", function() box:SetFocus() end)
	self.box = box

	local copy = UI.button(page, "Select all to copy", 150, function()
		box:SetText(self:Text())
		box:SetFocus()
		box:HighlightText()
	end)
	copy:SetPoint("BOTTOMLEFT", PAD, PAD - 8)
	copy:SetMain()
	local clear = UI.button(page, "Clear errors", 120, function()
		wipe(kept)
		wipe(byMessage)
		box:SetText(self:Text())
	end)
	clear:SetPoint("LEFT", copy, "RIGHT", 8, 0)
	local close = UI.button(page, "Close", 80, function() page:Hide() end)
	close:SetPoint("BOTTOMRIGHT", -PAD, PAD - 8)
	UI.applyTheme()
end

function Report:Show()
	if not self.page then self:Build() end
	self.box:SetText(self:Text())
	self.box:SetCursorPosition(0)
	self.page:Show()
end

Stoa.commands.report = function() Report:Show() end
