-- Stoa: Unlock mode. Any Stoa frame registered here can be dragged while
-- unlocked; positions are saved per character. Blizzard frames are left to
-- Edit Mode.
local _, ns = ...
local Stoa = ns.Stoa

local movers = {}
local unlocked = false

local function savePosition(key, frame)
	local point, _, relativePoint, x, y = frame:GetPoint(1)
	Stoa.char.positions[key] = { point, relativePoint, x, y }
end

local function restorePosition(key, frame)
	local saved = Stoa.char.positions[key]
	if not saved then return end
	frame:ClearAllPoints()
	frame:SetPoint(saved[1], UIParent, saved[2], saved[3], saved[4])
end

local function makeOverlay(frame, label)
	local overlay = CreateFrame("Frame", nil, frame, "BackdropTemplate")
	overlay:SetAllPoints()
	overlay:SetFrameLevel(frame:GetFrameLevel() + 20)
	overlay:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
	overlay:SetBackdropColor(0, 0, 0, 0.35)
	overlay:SetBackdropBorderColor(Stoa:Color("accent"))

	local text = overlay:CreateFontString(nil, "OVERLAY")
	Stoa:SetFont(text, "sans", Stoa.typeSize.caption)
	text:SetPoint("CENTER")
	text:SetText(label:upper())
	text:SetTextColor(Stoa:Color("text"))

	overlay:Hide()
	return overlay
end

-- key: a stable id for saving. frame: a non-secure frame Stoa owns.
function Stoa:RegisterMover(key, frame, label)
	local overlay = makeOverlay(frame, label or key)
	frame:SetMovable(true)
	frame:SetClampedToScreen(true)
	frame:RegisterForDrag("LeftButton")
	frame:SetScript("OnDragStart", function(f)
		if unlocked then f:StartMoving() end
	end)
	frame:SetScript("OnDragStop", function(f)
		f:StopMovingOrSizing()
		savePosition(key, f)
	end)
	movers[key] = { frame = frame, overlay = overlay }
	self:AfterCombat(function() restorePosition(key, frame) end)
end

local function setUnlocked(value)
	unlocked = value
	for _, mover in pairs(movers) do
		mover.frame:EnableMouse(unlocked)
		mover.overlay:SetShown(unlocked)
	end
end

function Stoa:ToggleMovers()
	if InCombatLockdown() then
		self:Print("Frames can be moved once combat ends.")
		return
	end
	setUnlocked(not unlocked)
	self:Print(unlocked and "Frames unlocked. Drag to move, /stoa unlock to lock." or "Frames locked.")
end

-- Entering combat always locks, so a stray drag can't move frames mid-fight.
Stoa:On("PLAYER_REGEN_DISABLED", function()
	if unlocked then
		setUnlocked(false)
		Stoa:Print("Frames locked for combat.")
	end
end)

-- /stoa reset puts every moved frame back in its default spot.
Stoa.commands.reset = function()
	wipe(Stoa.char.positions)
	Stoa:Print("Frame positions reset. /reload to see the defaults.")
end
