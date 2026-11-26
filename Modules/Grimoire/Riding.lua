-- Stoa Grimoire: riding. On a mount or a flight out of a fight, the console
-- folds to a slim travel line: your speed on the left with the zone beside
-- it, and the next stop of the quest you follow on the right, with how far
-- it is and a bar filling as you close in. Chat stays as it is, standing
-- above the line as it does over the folded console. The action bars and
-- pages fade back. A fight, getting off or landing brings the full console
-- back.
--
-- Lean: one check on the mount and taxi events, and a speed and distance
-- read twice a second only while riding. The full console only; Slim is a
-- line already.
local _, ns = ...
local Stoa = ns.Stoa
local UI = Stoa.UI
local Console = Stoa.modules.Grimoire

local RIDE_HEIGHT = 44
local TICK = 0.5
local RUN_SPEED = 7
local TRACK_WIDTH = 200
Console.RIDE_HEIGHT = RIDE_HEIGHT

-- The action bars Edit Mode sets over the console. They are secure, so only
-- their alpha changes, which the game allows at any time.
local BARS = { "MainActionBar", "MainMenuBar", "MultiBarBottomLeft", "MultiBarBottomRight", "MultiBar5", "MultiBar6", "MultiBar7", "StanceBar", "PetActionBar" }

local plain = function(v) return Stoa.safe.plain(v) end

function Console:RidingWanted()
	if self.db.riding == false or self.db.slim or self.bare or not self.frame then return false end
	if InCombatLockdown() or Stoa:GetState() ~= Stoa.STATE_WORLD then return false end
	local mounted = IsMounted and plain(IsMounted())
	local flying = UnitOnTaxi and plain(UnitOnTaxi("player"))
	return (mounted or flying) and true or false
end

function Console:BuildRide()
	local band = CreateFrame("Frame", nil, self.frame)
	band:SetPoint("BOTTOMLEFT", self.frame, "BOTTOMLEFT", 0, 0)
	band:SetPoint("BOTTOMRIGHT", self.frame, "BOTTOMRIGHT", 0, 0)
	band:SetHeight(RIDE_HEIGHT)
	band:SetFrameLevel(self.frame:GetFrameLevel() + 6)
	band:Hide()
	local inset = (self:PageInset())

	local speed = UI.text(band, "serif", Stoa.typeSize.title, "text", "LEFT")
	speed:SetPoint("LEFT", band, "LEFT", inset, -2)
	local unit = UI.text(band, "sans", Stoa.typeSize.caption, "muted", "LEFT")
	unit:SetPoint("BOTTOMLEFT", speed, "BOTTOMRIGHT", 3, 2)
	unit:SetText("%")
	local zone = UI.text(band, "serif", Stoa.typeSize.label, "text", "LEFT")
	zone:SetPoint("TOPLEFT", speed, "TOPRIGHT", 28, 2)
	local sub = UI.text(band, "sans", Stoa.typeSize.caption, "muted", "LEFT")
	sub:SetPoint("TOPLEFT", zone, "BOTTOMLEFT", 0, -2)

	-- The next stop: a diamond, the quest, how far, and a bar closing in.
	local stop = CreateFrame("Frame", nil, band)
	stop:SetSize(TRACK_WIDTH, 26)
	stop:SetPoint("RIGHT", band, "RIGHT", -inset, -2)
	local title = UI.text(stop, "sans", Stoa.typeSize.caption, "text", "LEFT")
	title:SetPoint("TOPLEFT")
	title:SetPoint("TOPRIGHT", -52, 0)
	title:SetWordWrap(false)
	local far = UI.text(stop, "sans", Stoa.typeSize.caption, "muted", "RIGHT")
	far:SetPoint("TOPRIGHT")
	local well = stop:CreateTexture(nil, "BACKGROUND")
	well:SetPoint("BOTTOMLEFT")
	well:SetPoint("BOTTOMRIGHT")
	well:SetHeight(3)
	well:SetColorTexture(0, 0, 0, 0.6)
	local fill = stop:CreateTexture(nil, "ARTWORK")
	fill:SetPoint("BOTTOMLEFT")
	fill:SetHeight(3)
	fill:SetTexture(UI.WHITE)
	UI.paint(fill, "accent")
	local mark = stop:CreateTexture(nil, "ARTWORK")
	mark:SetSize(5, 5)
	mark:SetPoint("RIGHT", stop, "LEFT", -10, 0)
	mark:SetRotation(math.rad(45))
	mark:SetColorTexture(Stoa:Color("accent"))
	Stoa:On("STOA_THEME_CHANGED", function() mark:SetColorTexture(Stoa:Color("accent")) end)

	band.speed, band.zone, band.sub = speed, zone, sub
	band.stop, band.title, band.far, band.fill, band.mark = stop, title, far, fill, mark
	self.ride = band
end

-- The quest you follow (the one the map points at, else the first tracked)
-- and how far its next objective is, in yards.
local function nextStop()
	local log = C_QuestLog
	if not (log and log.GetDistanceSqToQuest) then return end
	local id = C_SuperTrack and C_SuperTrack.GetSuperTrackedQuestID and plain(C_SuperTrack.GetSuperTrackedQuestID())
	if not id or id == 0 then
		local count = log.GetNumQuestWatches and plain(log.GetNumQuestWatches()) or 0
		for i = 1, count do
			local watched = plain(log.GetQuestIDForQuestWatchIndex(i))
			if watched and watched ~= 0 and plain(log.GetDistanceSqToQuest(watched)) then id = watched break end
		end
	end
	if not id or id == 0 then return end
	local squared = plain(log.GetDistanceSqToQuest(id))
	if not squared then return end
	return id, log.GetTitleForQuestID and plain(log.GetTitleForQuestID(id)) or "", math.sqrt(squared)
end

function Console:FillRide()
	local band = self.ride
	if not band then return end
	local moving = GetUnitSpeed and plain(GetUnitSpeed("player")) or 0
	band.speed:SetText(("%d"):format(math.floor(moving / RUN_SPEED * 100 + 0.5)))
	band.zone:SetText(GetZoneText and GetZoneText() or "")
	local onTaxi = UnitOnTaxi and plain(UnitOnTaxi("player"))
	local sub = GetSubZoneText and GetSubZoneText() or ""
	band.sub:SetText(onTaxi and "On a flight" or sub)

	local id, title, yards = nextStop()
	band.stop:SetShown(id ~= nil)
	band.mark:SetShown(id ~= nil)
	if not id then return end
	-- The bar runs from where you were when this stop came up to the stop.
	if band.stopID ~= id or yards > (band.stopFrom or 0) then band.stopID, band.stopFrom = id, math.max(yards, 1) end
	band.title:SetText(title)
	band.far:SetText(yards >= 1000 and ("%.1f km"):format(yards * 0.9144 / 1000) or ("%d yd"):format(math.floor(yards + 0.5)))
	local share = 1 - math.min(yards / band.stopFrom, 1)
	band.fill:SetWidth(math.max(1, TRACK_WIDTH * share))
end

local function fadeBars(alpha)
	for _, name in ipairs(BARS) do
		local bar = _G[name]
		if bar and bar.SetAlpha and not (bar.IsForbidden and bar:IsForbidden()) then
			if alpha < 1 then
				if bar.stoaRideAlpha == nil then bar.stoaRideAlpha = bar:GetAlpha() end
				bar:SetAlpha(alpha)
			elseif bar.stoaRideAlpha ~= nil then
				bar:SetAlpha(bar.stoaRideAlpha)
				bar.stoaRideAlpha = nil
			end
		end
	end
end

-- Into or out of the travel line. The console's own fold does the motion;
-- this decides its height and what rides on it.
function Console:SetRiding(on)
	on = on and true or false
	if on == (self.riding or false) then return end
	self.riding = on
	if on and not self.ride then self:BuildRide() end
	fadeBars(on and 0 or 1)
	local bars = Stoa.modules.ActionBars
	if bars and bars.enabled and bars.UpdateTray then xpcall(bars.UpdateTray, Stoa.catch, bars) end
	if on then
		self:FillRide()
		UI.softShow(self.ride, true)
		self.rideTicker = self.rideTicker or C_Timer.NewTicker(TICK, function()
			xpcall(self.FillRide, Stoa.catch, self)
		end)
	else
		if self.ride then self.ride:Hide() end
		if self.rideTicker then self.rideTicker:Cancel() self.rideTicker = nil end
	end
	self:Refold()
	-- The chat's foot steps up over the travel line, and back down after.
	if self.ReplaceChat then self:ReplaceChat() end
	-- The target leaves its seat on the open console's rim for its Halo spot.
	local halo = Stoa.modules.Halo
	if halo and halo.enabled and halo.PlaceTarget then halo:PlaceTarget() end
end

function Console:CheckRiding()
	xpcall(function() self:SetRiding(self:RidingWanted()) end, Stoa.catch)
end

Stoa:On("STOA_READY", function()
	if not Console.frame then return end
	for _, event in ipairs({ "PLAYER_MOUNT_DISPLAY_CHANGED", "PLAYER_CONTROL_LOST", "PLAYER_CONTROL_GAINED", "PLAYER_ENTERING_WORLD", "STOA_STATE_CHANGED" }) do
		Stoa:On(event, function() Console:CheckRiding() end)
	end
	-- A fight takes the travel line away before anything else.
	Stoa:On("PLAYER_REGEN_DISABLED", function() Console:SetRiding(false) end)
	Console:CheckRiding()
end)

-- /stoa ride previews the travel line on foot; again puts it back.
Stoa.commands.ride = function()
	if not Console.frame then return end
	Console:SetRiding(not Console.riding)
end
