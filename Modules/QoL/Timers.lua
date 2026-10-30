-- Stoa QoL: timers worth a glance.
-- A slim bar near the top of the screen for the waits the game makes you
-- sit through:
--   Flights: where you're flying and how long is left, from the known
--   flight times (Data/FlightTimes.lua). A route not listed is timed the
--   first time you fly it and remembered (StoaDB.flights). The flight map's
--   tooltips gain the time too.
--   Breath, fatigue and feign death: the game's own mirror timers, in
--   Stoa's bar instead of Blizzard's, worded rather than coloured.
local _, ns = ...
local Stoa = ns.Stoa
local UI = Stoa.UI

local Timers = Stoa:NewModule("Timers", {
	flights = true,
	mirror = true,
})

local WIDTH, HEIGHT, GAP = 240, 6, 22

local call = Stoa.safe.call

local function clock(seconds)
	seconds = math.max(0, math.floor(seconds + 0.5))
	return ("%d:%02d"):format(math.floor(seconds / 60), seconds % 60)
end

-- Bars -------------------------------------------------------------------------

function Timers:Build()
	if self.frame then return end
	local frame = CreateFrame("Frame", "StoaTimers", UIParent)
	frame:SetSize(WIDTH, HEIGHT)
	frame:SetPoint("TOP", UIParent, "TOP", 0, -150)
	frame:SetFrameStrata("MEDIUM")
	frame:EnableMouse(false)
	self.frame, self.bars = frame, {}
	Stoa:RegisterMover("timers", frame, "Timers")
end

-- One bar per kind ("flight", "BREATH" ...), stacked down from the anchor.
function Timers:Bar(kind)
	local bar = self.bars[kind]
	if bar then return bar end
	bar = UI.bar(self.frame, WIDTH, HEIGHT, "accent")
	bar.word = UI.text(bar, "sans", Stoa.typeSize.caption, "text", "LEFT")
	bar.word:SetPoint("BOTTOMLEFT", bar, "TOPLEFT", 0, 4)
	bar.time = UI.text(bar, "sans", Stoa.typeSize.caption, "muted", "RIGHT")
	bar.time:SetPoint("BOTTOMRIGHT", bar, "TOPRIGHT", 0, 4)
	UI.legible(bar.word)
	UI.legible(bar.time)
	bar:Hide()
	self.bars[kind] = bar
	return bar
end

function Timers:Layout()
	local y = 0
	for _, kind in ipairs({ "flight", "BREATH", "EXHAUSTION", "FEIGNDEATH" }) do
		local bar = self.bars[kind]
		if bar and bar:IsShown() then
			bar:ClearAllPoints()
			bar:SetPoint("TOP", self.frame, "TOP", 0, -y)
			y = y + HEIGHT + GAP
		end
	end
end

-- Runs a bar. With a duration it counts down; without one it counts up
-- (a flight being timed for the first time). label is the word above it.
function Timers:Start(kind, label, duration, token, opts)
	self:Build()
	local bar = self:Bar(kind)
	opts = opts or {}
	bar.word:SetText(label)
	UI.paint(bar, token or "accent")
	bar.started = GetTime()
	bar.duration = duration
	bar.remaining = opts.remaining or duration
	bar.rate = opts.rate or 1
	bar.paused = opts.paused
	bar:SetMinMaxValues(0, duration or 1)
	bar:SetScript("OnUpdate", function(self, elapsed)
		if self.paused then return end
		if self.duration then
			self.remaining = self.remaining - elapsed * self.rate
			if self.remaining <= 0 and not opts.hold then
				Timers:Stop(kind)
				return
			end
			self:SetValue(math.max(self.remaining, 0))
			self.time:SetText(clock(math.max(self.remaining, 0)))
		else
			self:SetValue(1)
			self.time:SetText(clock(GetTime() - self.started) .. "  timing")
		end
	end)
	bar:Show()
	self:Layout()
	return bar
end

function Timers:Stop(kind)
	local bar = self.bars and self.bars[kind]
	if not bar then return end
	bar:SetScript("OnUpdate", nil)
	bar:Hide()
	self:Layout()
end

-- Flights -------------------------------------------------------------------------
-- The flight map names its nodes by slot; the times are kept by the game's
-- node IDs, so each time the map opens the slots are matched to IDs.

local nodes = { slot = {}, name = {} }

local function faction()
	return (UnitFactionGroup("player"))
end

local function learned()
	local f = faction()
	if not (f and Stoa.db) then return {} end
	Stoa.db.flights = Stoa.db.flights or {}
	Stoa.db.flights[f] = Stoa.db.flights[f] or {}
	return Stoa.db.flights[f]
end

-- Seconds from one node to another, either way round, or nil.
local function legTime(from, to)
	if not (from and to) then return nil end
	local known = Stoa.FLIGHT_TIMES and Stoa.FLIGHT_TIMES[faction()] or {}
	local mine = learned()
	return (mine[from] and mine[from][to]) or (known[from] and known[from][to])
		or (mine[to] and mine[to][from]) or (known[to] and known[to][from])
end

function Timers:ReadMap()
	wipe(nodes.slot)
	nodes.current = nil
	local map = C_Map and call(C_Map.GetBestMapForUnit, "player")
	local list = map and C_TaxiMap and call(C_TaxiMap.GetAllTaxiNodes, map)
	if type(list) ~= "table" then return end
	local current = Enum and Enum.FlightPathState and Enum.FlightPathState.Current
	for _, node in pairs(list) do
		if type(node) == "table" and node.nodeID and node.slotIndex then
			nodes.slot[node.slotIndex] = node.nodeID
			nodes.name[node.nodeID] = node.name
			if current and node.state == current then nodes.current = node.nodeID end
		end
	end
end

-- The whole trip to a map slot: the direct time if known, else the legs
-- added up. Returns seconds (or nil), the destination node and its name.
function Timers:TripTime(slot)
	local dest = nodes.slot[slot]
	local name = call(TaxiNodeName, slot) or (dest and nodes.name[dest])
	local direct = legTime(nodes.current, dest)
	if direct then return direct, dest, name end
	local hops = Stoa:PlainNumber(call(GetNumRoutes, slot)) or 0
	if hops < 1 then return nil, dest, name end
	local total = 0
	for hop = 1, hops do
		local from = nodes.slot[call(TaxiGetNodeSlot, slot, hop, true) or -1]
		local to = nodes.slot[call(TaxiGetNodeSlot, slot, hop, false) or -1]
		local leg = legTime(from, to)
		if not leg then return nil, dest, name end
		total = total + leg
	end
	return total, dest, name
end

local function shortName(name)
	return name and (name:match("^([^,]+)") or name) or "your stop"
end

function Timers:TookTaxi(slot)
	if not self.db.flights then return end
	local seconds, dest, name = self:TripTime(slot)
	self.trip = { from = nodes.current, to = dest, name = name, seconds = seconds, asked = GetTime() }
end

function Timers:FlightStarted()
	local trip = self.trip
	if not trip or GetTime() - trip.asked > 3 then return end
	trip.started = GetTime()
	self:Start("flight", "TO " .. shortName(trip.name):upper(), trip.seconds, "accent", { hold = true })
end

function Timers:FlightEnded()
	local trip = self.trip
	self.trip = nil
	self:Stop("flight")
	if not (trip and trip.started and trip.from and trip.to) then return end
	-- A route flown for the first time is remembered, whole trip as one.
	local took = GetTime() - trip.started
	if not trip.seconds and took > 10 then
		local mine = learned()
		mine[trip.from] = mine[trip.from] or {}
		mine[trip.from][trip.to] = math.floor(took + 0.5)
	end
end

-- The flight map's tooltip: the time to each reachable stop.
function Timers:TaxiTooltip(button)
	if not self.db.flights or not (button and button.GetID) then return end
	local slot = button:GetID()
	if call(TaxiNodeGetType, slot) ~= "REACHABLE" then return end
	local seconds = self:TripTime(slot)
	if not seconds or not GameTooltip or GameTooltip:IsForbidden() then return end
	GameTooltip:AddLine(clock(seconds) .. " flight", Stoa:Color("muted"))
	GameTooltip:Show()
end

-- Mirror timers ---------------------------------------------------------------------

local MIRROR_WORDS = { BREATH = "BREATH", EXHAUSTION = "FATIGUE", FEIGNDEATH = "FEIGN DEATH" }

function Timers:HideBlizzardMirrors()
	for i = 1, 3 do
		local timer = _G["MirrorTimer" .. i]
		if timer and timer.SetAlpha then timer:SetAlpha(0) end
	end
	local container = _G.MirrorTimerContainer
	if container and container.SetAlpha then container:SetAlpha(0) end
end

function Timers:MirrorStart(name, value, maxValue, scale, paused, label)
	if not self.db.mirror or not MIRROR_WORDS[name] then return end
	value, maxValue = Stoa:PlainNumber(value), Stoa:PlainNumber(maxValue)
	if not (value and maxValue and maxValue > 0) then return end
	self:HideBlizzardMirrors()
	local rate = -(Stoa:PlainNumber(scale) or -1)
	local bar = self:Start(name, MIRROR_WORDS[name], maxValue / 1000, name == "BREATH" and "mana" or "danger", {
		remaining = value / 1000, rate = rate, paused = paused and paused ~= 0, hold = true,
	})
	bar:SetValue(value / 1000)
end

function Timers:OnEnable()
	self:Build()
	if TakeTaxiNode then Stoa.SafeHook("TakeTaxiNode", function(slot) self:TookTaxi(slot) end) end
	if TaxiNodeOnButtonEnter then
		Stoa.SafeHook("TaxiNodeOnButtonEnter", function(button) self:TaxiTooltip(button) end)
	end
	Stoa:On("TAXIMAP_OPENED", function() self:ReadMap() end)
	Stoa:On("PLAYER_CONTROL_LOST", function() self:FlightStarted() end)
	Stoa:On("PLAYER_CONTROL_GAINED", function() self:FlightEnded() end)
	Stoa:On("MIRROR_TIMER_START", function(...) self:MirrorStart(...) end)
	Stoa:On("MIRROR_TIMER_PAUSE", function(name, paused)
		local bar = self.bars[name]
		if bar then bar.paused = paused and paused ~= 0 end
	end)
	Stoa:On("MIRROR_TIMER_STOP", function(name) self:Stop(name) end)
	-- After a reload mid-flight there's no trip to time, but the bar from
	-- before would be gone anyway; nothing to restore.
	Stoa.commands.timers = function()
		self:Start("flight", "TO BOOTY BAY", 95, "accent")
		self:Start("BREATH", "BREATH", 60, "mana", { remaining = 42 })
		Stoa:Print("Showing sample timers.")
	end
end
