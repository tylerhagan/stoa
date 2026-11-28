-- Stoa QoL: the rider. One key for getting on and off a mount.
--   Tap it: off if you're mounted; else a random favourite you can use
--   here (a swimmer in water, a flyer where you can fly), never the same
--   one twice running. Shift + tap: your everyday mount.
--   Hold it: a ring of your favourites opens round the cursor. Let go over
--   one to ride it, in the middle for a random one, or well off the ring to
--   change your mind. Shift as you let go also makes it your everyday mount.
-- Favourites are the ones you star in the Mount Journal (right-click a
-- mount there); with none starred, every mount you own takes part. Forever
-- hides the journal's own random-favourite button, which is why this
-- exists. Nothing can mount in a fight, so the key rests then.
--
-- Also here: saving for riding. From level 30 until you've trained it,
-- the Gold line in At a glance draws how close you are to Apprentice
-- Riding (100 gold at 40), then from 50 to Journeyman (1,000 at 60), and
-- a small job says when you can go and train.
--
-- Lean: nothing runs until the key is pressed, the wheel's OnUpdate only
-- while it's open, and the saving check on money and level changes.
local _, ns = ...
local Stoa = ns.Stoa
local UI = Stoa.UI

local Rider = Stoa:NewModule("Rider", {
	key = true,
	wheel = true,
	saving = true,
	-- The travel line's arrival times and the medallion's summoning sweep
	-- (Grimoire/Riding.lua reads these two).
	arrival = true,
	summon = true,
	-- The mount Shift summons (a mount id).
	everyday = nil,
})
Stoa.Rider = Rider

BINDING_NAME_STOA_MOUNT = "Mount (tap: random favourite, hold: wheel)"

local call = Stoa.safe.call
local function plain(v) return Stoa.safe.plain(v) end

local HOLD = 0.22
local SLOT = 44
local MAX_SLOTS = 12
local CENTRE = 34
local CANCEL = 70

-- The journal's mount types (mountTypeID) that swim or fly.
local SWIMS = { [231] = true, [232] = true, [254] = true, [407] = true, [412] = true }
local FLIES = { [247] = true, [248] = true, [398] = true, [402] = true, [407] = true, [424] = true, [436] = true, [437] = true }

-- Mounts ----------------------------------------------------------------------

local function journal() return C_MountJournal and C_MountJournal.GetMountIDs and C_MountJournal end

local function info(id)
	local mj = journal()
	if not mj then return end
	local name, spellID, icon, active, usable, _, favourite, _, _, hidden, collected = call(mj.GetMountInfoByID, id)
	if not name or not plain(collected) or plain(hidden) then return end
	local kind = mj.GetMountInfoExtraByID and select(5, call(mj.GetMountInfoExtraByID, id))
	return {
		id = id, name = name, spell = spellID, icon = icon, active = plain(active), usable = plain(usable),
		favourite = plain(favourite), kind = plain(kind),
	}
end

-- Your favourites, or every mount you own when none are starred.
function Rider:Mounts()
	local mj = journal()
	if not mj then return {} end
	local all, starred = {}, {}
	for _, id in ipairs(call(mj.GetMountIDs) or {}) do
		local m = info(id)
		if m then
			all[#all + 1] = m
			if m.favourite then starred[#starred + 1] = m end
		end
	end
	local list = #starred > 0 and starred or all
	table.sort(list, function(a, b) return a.name < b.name end)
	return list
end

local function fits(m, swimming, flying)
	if swimming then return SWIMS[m.kind] end
	if flying then return FLIES[m.kind] end
	return not SWIMS[m.kind]
end

-- The mount a tap would summon here, or nil.
function Rider:Pick(shift)
	if shift and self.db.everyday then
		local m = info(self.db.everyday)
		if m and m.usable then return m end
	end
	local usable = {}
	for _, m in ipairs(self:Mounts()) do
		if m.usable then usable[#usable + 1] = m end
	end
	if #usable == 0 then return nil end
	local swimming = plain(call(IsSwimming))
	local flying = not swimming and plain(call(IsFlyableArea)) and not plain(call(IsIndoors))
	local best = {}
	for _, m in ipairs(usable) do
		if fits(m, swimming, flying) and m.id ~= self.last then best[#best + 1] = m end
	end
	if #best == 0 then
		for _, m in ipairs(usable) do
			if fits(m, swimming, flying) then best[#best + 1] = m end
		end
	end
	if #best == 0 then best = usable end
	return best[math.random(#best)]
end

local function say(words)
	if UIErrorsFrame and UIErrorsFrame.AddMessage then UIErrorsFrame:AddMessage(words, 1, 0.82, 0.3) end
end

function Rider:Summon(m)
	if not m or InCombatLockdown() then return end
	local mj = journal()
	if not (mj and mj.SummonByID) then return end
	self.last = m.id
	call(mj.SummonByID, m.id)
end

local function mounted() return IsMounted and plain(IsMounted()) end

function Rider:GetOff()
	local mj = journal()
	if mj and mj.Dismiss then call(mj.Dismiss) elseif Dismount then call(Dismount) end
end

function Rider:Tap(shift)
	if InCombatLockdown() then return end
	if UnitOnTaxi and plain(UnitOnTaxi("player")) then return end
	if mounted() then self:GetOff() return end
	local m = self:Pick(shift)
	if m then self:Summon(m) else say("No mount you can ride here") end
end

-- The key ---------------------------------------------------------------------
-- Bindings.xml calls this on press (down) and on release.

function Rider:Key(down)
	if not (self.enabled and self.db.key) then return end
	if down then
		if InCombatLockdown() then self.pressed = nil return end
		-- Off at once: there's nothing to choose when you're getting off.
		if mounted() then self.pressed = nil self:GetOff() return end
		local press = {}
		self.pressed = press
		local looking = IsMouselooking and IsMouselooking()
		if self.db.wheel and not looking then
			C_Timer.After(HOLD, function()
				if self.pressed == press and not InCombatLockdown() then self:OpenWheel() end
			end)
		end
		return
	end
	local press = self.pressed
	self.pressed = nil
	if self.wheel and self.wheel:IsShown() then
		self:ReleaseWheel()
	elseif press then
		self:Tap(IsShiftKeyDown())
	end
end

-- The wheel -------------------------------------------------------------------

local function radiusFor(count)
	return count <= 6 and 78 or 100
end

function Rider:BuildWheel()
	local wheel = CreateFrame("Frame", "StoaMountWheel", UIParent)
	wheel:SetFrameStrata("DIALOG")
	wheel:SetSize(300, 300)
	wheel:SetClampedToScreen(true)
	wheel:Hide()

	local hub = CreateFrame("Frame", nil, wheel)
	hub:SetSize(CENTRE * 2, CENTRE * 2)
	hub:SetPoint("CENTER")
	local disc = UI.circle(hub, "BACKGROUND", 0, CENTRE * 2, "panel", 0.94)
	disc:SetPoint("CENTER")
	local rim = UI.circle(hub, "BACKGROUND", -1, CENTRE * 2 + 3, "accent", 0.55)
	rim:SetPoint("CENTER")
	local name = UI.text(hub, "serif", Stoa.typeSize.body, "text", "CENTER")
	name:SetPoint("CENTER", 0, 4)
	name:SetWidth(CENTRE * 2 - 10)
	name:SetMaxLines(2)
	local hint = UI.text(hub, "sans", Stoa.typeSize.micro, "muted", "CENTER")
	hint:SetPoint("TOP", name, "BOTTOM", 0, -2)
	hub.name, hub.hint, hub.rim = name, hint, rim
	wheel.hub = hub

	-- A faint ring the slots sit on.
	local track = UI.circle(wheel, "BACKGROUND", -2, 200, "text", 0.05)
	track:SetPoint("CENTER")
	wheel.track = track

	wheel.slots = {}
	local open = wheel:CreateAnimationGroup()
	local grow = open:CreateAnimation("Scale")
	grow:SetScaleFrom(0.86, 0.86)
	grow:SetScaleTo(1, 1)
	grow:SetDuration(UI.MOTION.open)
	grow:SetSmoothing("OUT")
	local fade = open:CreateAnimation("Alpha")
	fade:SetFromAlpha(0)
	fade:SetToAlpha(1)
	fade:SetDuration(UI.MOTION.open)
	fade:SetSmoothing("OUT")
	wheel.open = open

	wheel:SetScript("OnUpdate", function() self:TrackWheel() end)
	self.wheel = wheel
end

function Rider:Slot(i)
	local wheel = self.wheel
	local slot = wheel.slots[i]
	if slot then return slot end
	slot = CreateFrame("Button", nil, wheel)
	slot:SetSize(SLOT, SLOT)
	local well = UI.circle(slot, "BACKGROUND", 0, SLOT + 4, "panel", 0.95)
	well:SetPoint("CENTER")
	local ring = UI.circle(slot, "BACKGROUND", -1, SLOT + 8, "accent", 0.9)
	ring:SetPoint("CENTER")
	ring:Hide()
	local icon = UI.circle(slot, "ARTWORK", 0, SLOT - 4)
	icon:SetPoint("CENTER")
	icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	local mark = UI.circle(slot, "OVERLAY", 0, 7, "accent")
	mark:SetPoint("CENTER", slot, "TOP", 0, -1)
	mark:Hide()
	slot.icon, slot.ring, slot.mark = icon, ring, mark
	slot:SetScript("OnClick", function(button)
		if button.mount then
			if IsShiftKeyDown() then self.db.everyday = button.mount.id end
			self:CloseWheel()
			self:Summon(button.mount)
		end
	end)
	wheel.slots[i] = slot
	return slot
end

function Rider:OpenWheel()
	if not self.wheel then self:BuildWheel() end
	local wheel = self.wheel
	local list = self:Mounts()
	-- The everyday mount first (starred or not), then the rest by name.
	local everyday = self.db.everyday
	if everyday then
		local found = false
		for _, m in ipairs(list) do found = found or m.id == everyday end
		local m = not found and info(everyday)
		if m then table.insert(list, m) end
	end
	table.sort(list, function(a, b)
		if (a.id == everyday) ~= (b.id == everyday) then return a.id == everyday end
		return a.name < b.name
	end)
	local count = math.min(#list, MAX_SLOTS)
	if count == 0 then
		say("No mounts yet")
		return
	end
	local radius = radiusFor(count)
	wheel.track:SetSize(radius * 2 + SLOT, radius * 2 + SLOT)
	wheel.radius, wheel.count = radius, count
	for i, slot in ipairs(wheel.slots) do slot:Hide() end
	for i = 1, count do
		local m = list[i]
		local slot = self:Slot(i)
		-- Clockwise from the top.
		local angle = math.pi / 2 - (i - 1) / count * 2 * math.pi
		slot.angle = angle
		slot:ClearAllPoints()
		slot:SetPoint("CENTER", wheel, "CENTER", math.cos(angle) * radius, math.sin(angle) * radius)
		slot.icon:SetTexture(m.icon)
		slot.icon:SetDesaturated(not m.usable)
		slot.icon:SetAlpha(m.usable and 1 or 0.4)
		slot.mark:SetShown(m.id == everyday)
		slot.ring:Hide()
		slot:SetScale(1)
		slot.mount = m
		slot:Show()
	end
	local scale = UIParent:GetEffectiveScale()
	local x, y = GetCursorPosition()
	wheel:ClearAllPoints()
	wheel:SetPoint("CENTER", UIParent, "BOTTOMLEFT", x / scale, y / scale)
	wheel.chosen = false
	self:ShowChoice(nil)
	wheel:Show()
	wheel.open:Play()
end

function Rider:CloseWheel()
	if self.wheel then self.wheel:Hide() end
end

-- What's under the cursor: a slot, "random" in the middle, or nil off the ring.
function Rider:WheelChoice()
	local wheel = self.wheel
	local scale = wheel:GetEffectiveScale()
	local x, y = GetCursorPosition()
	local cx, cy = wheel:GetCenter()
	if not cx then return end
	local dx, dy = x / scale - cx, y / scale - cy
	local far = math.sqrt(dx * dx + dy * dy)
	if far < CENTRE then return "random" end
	if far > wheel.radius + CANCEL then return nil end
	local angle = math.atan2(dy, dx)
	local best, gap
	for i = 1, wheel.count do
		local slot = wheel.slots[i]
		local d = math.abs((angle - slot.angle + math.pi) % (2 * math.pi) - math.pi)
		if not gap or d < gap then best, gap = slot, d end
	end
	return best
end

function Rider:ShowChoice(choice)
	local hub = self.wheel.hub
	if choice == "random" then
		hub.name:SetText("Random")
		hub.hint:SetText(self.db.everyday and "Shift: everyday" or "")
		hub.rim:SetAlpha(0.9)
	elseif type(choice) == "table" and choice.mount then
		hub.name:SetText(choice.mount.name)
		hub.hint:SetText(not choice.mount.usable and "Not here" or (IsShiftKeyDown() and "Make everyday" or ""))
		hub.rim:SetAlpha(0.55)
	else
		hub.name:SetText("")
		hub.hint:SetText("Let go to cancel")
		hub.rim:SetAlpha(0.3)
	end
end

function Rider:TrackWheel()
	local wheel = self.wheel
	if InCombatLockdown() then self:CloseWheel() return end
	local choice = self:WheelChoice()
	if choice == wheel.choice and IsShiftKeyDown() == wheel.shift then return end
	wheel.choice, wheel.shift = choice, IsShiftKeyDown()
	for i = 1, wheel.count do
		local slot = wheel.slots[i]
		local on = slot == choice
		slot.ring:SetShown(on)
		slot:SetScale(on and 1.12 or 1)
	end
	self:ShowChoice(choice)
end

function Rider:ReleaseWheel()
	local choice = self:WheelChoice()
	local shift = IsShiftKeyDown()
	self:CloseWheel()
	if choice == "random" then
		self:Tap(false)
	elseif type(choice) == "table" and choice.mount then
		if shift then self.db.everyday = choice.mount.id end
		if choice.mount.usable then self:Summon(choice.mount) else say("You can't ride that here") end
	end
end

-- Saving for riding -------------------------------------------------------------

local RIDING_SKILL = 762
local STEPS = {
	{ name = "Apprentice Riding", short = "Apprentice", spell = 33388, rank = 75, level = 40, gold = 100, from = 30 },
	{ name = "Journeyman Riding", short = "Journeyman", spell = 33391, rank = 150, level = 60, gold = 1000, from = 50 },
}

local function ridingRank()
	local skill = C_SkillInfo and C_SkillInfo.GetSkillLineInfoByID and call(C_SkillInfo.GetSkillLineInfoByID, RIDING_SKILL)
	return type(skill) == "table" and plain(skill.rank) or nil
end

local function trained(step)
	local rank = ridingRank()
	if rank and rank >= step.rank then return true end
	return IsPlayerSpell and plain(call(IsPlayerSpell, step.spell)) and true or false
end

-- The next riding step you're saving for, or nil: the step, your gold in
-- copper, and its cost in copper.
function Rider:Goal()
	if not (self.enabled and self.db.saving) then return end
	local level = plain(UnitLevel("player")) or 0
	for _, step in ipairs(STEPS) do
		if not trained(step) then
			if level < step.from then return end
			return step, plain(call(GetMoney)) or 0, step.gold * 10000
		end
	end
end

-- Gold an hour this session, once there's enough of it to go on.
function Rider:Pace()
	local start = self.start
	if not start then return end
	local now = plain(call(GetMoney))
	local hours = (GetTime() - start.at) / 3600
	if not now or hours < 0.25 then return end
	local gained = now - start.money
	if gained <= 0 then return end
	return gained / hours
end

local function goldText(copper)
	return Stoa:TintMoney(("%dg"):format(math.floor(copper / 10000)))
end

-- Lines for the Gold line's tooltip.
function Rider:Detail(add)
	local step, have, cost = self:Goal()
	if not step then return end
	add("Saving for", step.name)
	add("Gold", ("%s of %s"):format(goldText(math.min(have, cost)), goldText(cost)))
	local level = plain(UnitLevel("player")) or 0
	if level < step.level then add("Trainable at", ("level %d (you're %d)"):format(step.level, level)) end
	if have < cost then
		local pace = self:Pace()
		if pace then
			local hours = (cost - have) / pace
			add("At this session's pace", hours < 1 and ("about %d min"):format(math.max(1, math.floor(hours * 60 + 0.5))) or ("about %.1f hours"):format(hours))
		end
	end
	add("Note", "Cheaper at Honored with your race's city")
end

-- The small job when you can go and train now.
function Rider:Job()
	local step, have, cost = self:Goal()
	if not step then return end
	if have >= cost and (plain(UnitLevel("player")) or 0) >= step.level then
		return step.short .. " Riding can be trained"
	end
end

function Rider:OnEnable()
	self.start = { money = plain(call(GetMoney)) or 0, at = GetTime() }
	local wasJob = self:Job()
	local function check()
		local job = self:Job()
		if job == wasJob then return end
		wasJob = job
		local console = Stoa.modules.Grimoire
		if console and console.UpdateJobs then console:UpdateJobs() end
	end
	for _, event in ipairs({ "PLAYER_MONEY", "PLAYER_LEVEL_UP", "SKILL_LINES_CHANGED", "LEARNED_SPELL_IN_TAB" }) do
		Stoa:On(event, check)
	end
	Stoa:On("PLAYER_REGEN_DISABLED", function()
		self.pressed = nil
		self:CloseWheel()
	end)
end

-- /stoa mount: the same as a tap; /stoa mount wheel opens the wheel until
-- you click a slot or move away.
Stoa.commands.mount = function(rest)
	if rest == "wheel" then
		Rider:OpenWheel()
		C_Timer.After(5, function() if Rider.wheel and Rider.wheel:IsShown() and not Rider.pressed then Rider:CloseWheel() end end)
	else
		Rider:Tap(IsShiftKeyDown())
	end
end
