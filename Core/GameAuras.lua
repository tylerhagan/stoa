-- Stoa: auras the game draws for us.
-- In combat Forever hides aura details from addons, but its own aura
-- container (Blizzard_AuraContainer) can still show them: Stoa hands it a
-- frame and the spells to watch, and the game fills in the icon, the time
-- left and the stacks, in combat or out. Stoa never learns the state, so
-- anything that needs to know (a sound, a word) keeps its own reading.
--
-- Slots can only be added out of combat; ones asked for in a fight wait
-- for it to end. Everything here is guarded: if the container is missing
-- or refuses a slot, callers get nil and carry on with their own art.
local _, ns = ...
local Stoa = ns.Stoa
local UI = Stoa.UI

local GameAuras = {}
Stoa.GameAuras = GameAuras

local containers = {}
local broken = false

local function try(label, fn, ...)
	local ok, result = pcall(fn, ...)
	if not ok then
		GameAuras.lastError = label .. ": " .. tostring(result)
		return nil
	end
	return result
end

function GameAuras:Available()
	if broken then return false end
	local load = (C_AddOns and C_AddOns.LoadAddOn) or LoadAddOn
	if load then pcall(load, "Blizzard_AuraContainer") end
	return true
end

-- One container per unit, covering the screen; slot frames are placed by hand.
function GameAuras:Container(unit)
	if containers[unit] then return containers[unit] end
	if not self:Available() then return nil end
	local name = "StoaGameAuras" .. unit:gsub("^%l", string.upper)
	local container = try("container", CreateFrame, "AuraContainer", name, UIParent, "CustomAuraContainerTemplate")
	if not container then
		broken = true
		return nil
	end
	try("place", container.SetAllPoints, container, UIParent)
	try("strata", container.SetFrameStrata, container, "MEDIUM")
	try("unit", container.SetUnit, container, unit)
	try("enable", container.SetEnabled, container, true)
	containers[unit] = container
	return container
end

-- Dresses a frame the game made: a rounded icon, a draining swipe, the
-- time left and the stack count, all handed back to the game to fill.
local function dress(button, size)
	button:SetSize(size, size)
	UI.roundPanel(button, 0.9)
	local icon = button:CreateTexture(nil, "ARTWORK")
	icon:SetAllPoints()
	icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
	local cooldown = CreateFrame("Cooldown", nil, button, "CooldownFrameTemplate")
	cooldown:SetAllPoints()
	cooldown:SetReverse(true)
	cooldown:SetDrawEdge(false)
	cooldown:SetDrawBling(false)
	cooldown:SetHideCountdownNumbers(true)
	local left = UI.text(button, "sans", Stoa.typeSize.caption, "text", "CENTER")
	left:SetPoint("TOP", button, "BOTTOM", 0, -2)
	UI.legible(left)
	local count = UI.text(button, "sans", Stoa.typeSize.caption, "text", "RIGHT")
	count:SetPoint("BOTTOMRIGHT", 2, -1)
	Stoa:SetFont(count, "sans", Stoa.typeSize.caption, "OUTLINE")
	try("icon", button.SetIcon, button, icon)
	try("swipe", button.SetDurationCooldown, button, cooldown)
	try("time", button.SetDurationText, button, left)
	try("stacks", button.SetApplicationCount, button, count)
	button.stoaIcon, button.stoaLeft = icon, left
end

local pending = {}

-- Asks the game to show one aura on a unit.
--   key      : unique name for the slot
--   unit     : "player", "target", "party1" ...
--   filter   : "HELPFUL" or "HARMFUL" (add "|PLAYER" for your own)
--   spellIDs : list of spell IDs to show (any rank)
--   place    : function(frame) that anchors the frame
--   size     : pixels (default 30)
-- Returns the frame, or nil (not available, or waiting for combat to end).
function GameAuras:Slot(key, unit, filter, spellIDs, place, size)
	if InCombatLockdown() then
		pending[key] = { unit, filter, spellIDs, place, size }
		return nil
	end
	local container = self:Container(unit)
	if not (container and container.AddAuraSlot) then return nil end
	local slotKey = "stoa_" .. key
	if container.HasAuraSlot and container:HasAuraSlot(slotKey) then
		return container.GetAuraSlotFrame and container:GetAuraSlotFrame(slotKey)
	end
	local ids = {}
	for _, id in ipairs(spellIDs) do ids[id] = true end
	local built
	local frame = try("slot " .. key, container.AddAuraSlot, container, slotKey, filter, {
		initializeFrame = function(button)
			if built then return end
			built = true
			xpcall(dress, Stoa.catch, button, size or 30)
		end,
		candidateFilters = { includeSpellIDs = ids },
	})
	if type(frame) == "table" then
		if not built then
			built = true
			xpcall(dress, Stoa.catch, frame, size or 30)
		end
		if place then xpcall(place, Stoa.catch, frame) end
	end
	return frame
end

function GameAuras:SetShown(key, unit, shown)
	local container = containers[unit]
	if container and container.SetAuraSlotEnabled then
		try("toggle " .. key, container.SetAuraSlotEnabled, container, "stoa_" .. key, shown and true or false)
	end
end

Stoa:On("PLAYER_REGEN_ENABLED", function()
	local waiting = pending
	pending = {}
	for key, args in pairs(waiting) do
		GameAuras:Slot(key, unpack(args))
	end
end)

-- /stoa probe auras: puts the game's frames for your own auras on yourself
-- and your target beside the screen centre, to see on launch day whether
-- they keep counting down in combat.
function GameAuras:Probe(ids)
	Stoa:Print(("Aura container: available %s."):format(tostring(self:Available())))
	if InCombatLockdown() then
		Stoa:Print("Run it out of combat; the frames can only be made then.")
		return
	end
	local spells = ids or {}
	if #spells == 0 then
		-- Common long auras of each class, any of them will do.
		spells = { 589, 139, 17, 1243, 21562, 19740, 20217, 1126, 774, 8936, 1459, 168, 6673, 2457, 687, 172, 324, 19506, 1784 }
	end
	local player = self:Slot("probe_player", "player", "HELPFUL", spells, function(frame)
		frame:ClearAllPoints()
		frame:SetPoint("CENTER", UIParent, "CENTER", -120, 120)
	end, 36)
	local target = self:Slot("probe_target", "target", "HARMFUL|PLAYER", spells, function(frame)
		frame:ClearAllPoints()
		frame:SetPoint("CENTER", UIParent, "CENTER", 120, 120)
	end, 36)
	Stoa:Print(("Player frame %s, target frame %s%s."):format(
		player and "made" or "not made", target and "made" or "not made",
		self.lastError and (" (" .. self.lastError .. ")") or ""))
	Stoa:Print("Now cast a buff on yourself and a DoT or debuff on a target, then fight: the frames should keep their timers.")
end

-- /stoa auras [spellID ...]
Stoa.commands.auras = function(rest)
	local ids = {}
	for id in (rest or ""):gmatch("%d+") do ids[#ids + 1] = tonumber(id) end
	xpcall(GameAuras.Probe, Stoa.catch, GameAuras, ids)
end
