-- Stoa: Unlock mode. Any Stoa frame registered here can be dragged while
-- unlocked. Positions are saved per character and per role layout, so a
-- healer layout and a damage layout each keep their own spots; a character
-- saved before layouts existed keeps its old spots until a layout moves a
-- frame. Blizzard frames are left to Edit Mode.
--
-- The drag handle is an overlay, never the frame itself: the overlay is ours
-- and safe to show, hide and click, while the frame may be secure or hidden
-- by a state driver. The frame only moves when a drop is committed, and only
-- out of combat, since secure frames cannot be moved in combat.
local _, ns = ...
local Stoa = ns.Stoa

local movers = {}
local order = {}
local unlocked = false
local selected
local showGrid = false

local GRID_STEP = 100
local BAR_WIDTH = 520

-- Saved positions -----------------------------------------------------------
-- layouts[role][key] is { point, relativePoint, x, y }, or false once the
-- player has reset that frame in that layout (so the older per-character
-- spot stops applying there). Missing means "no opinion", and the older
-- spot, if any, applies.

local function layouts()
	Stoa.char.layouts = Stoa.char.layouts or {}
	return Stoa.char.layouts
end

local function lookup(key)
	local role = Stoa:GetRole()
	local layout = role and layouts()[role]
	local saved = layout and layout[key]
	if saved == false then return nil end
	return saved or Stoa.char.positions[key]
end

-- True when the player has put this frame somewhere in the current layout.
-- Modules that place their own frames by default check it before doing so.
function Stoa:HasSavedPosition(key)
	return lookup(key) ~= nil
end

local function store(key, value)
	local role = Stoa:GetRole()
	if not role then
		Stoa.char.positions[key] = value or nil
		return
	end
	local all = layouts()
	all[role] = all[role] or {}
	all[role][key] = value
end

-- Where a frame is now, as an offset from the screen: its first anchor when
-- that is already the screen, otherwise worked out from its edges.
local function currentPosition(frame)
	local point, relativeTo, relativePoint, x, y = frame:GetPoint(1)
	if point and (relativeTo == nil or relativeTo == UIParent) and type(x) == "number" and type(y) == "number" then
		return { point, relativePoint or point, x, y }
	end
	local left, bottom = frame:GetLeft(), frame:GetBottom()
	if type(left) == "number" and type(bottom) == "number" then
		return { "BOTTOMLEFT", "BOTTOMLEFT", left, bottom }
	end
end

local function place(frame, saved)
	frame:ClearAllPoints()
	frame:SetPoint(saved[1], UIParent, saved[2], saved[3], saved[4])
end

local function remember(frame)
	local points = {}
	local count = frame.GetNumPoints and frame:GetNumPoints()
	if type(count) ~= "number" then count = 1 end
	for i = 1, count do
		local point, relativeTo, relativePoint, x, y = frame:GetPoint(i)
		if not point then break end
		points[i] = { point, relativeTo, relativePoint, x, y }
	end
	return points
end

local function putBack(mover)
	if mover.default then
		mover.default(mover.frame)
	elseif #mover.points > 0 then
		local frame = mover.frame
		frame:ClearAllPoints()
		for _, p in ipairs(mover.points) do
			frame:SetPoint(p[1], p[2], p[3], p[4], p[5])
		end
	end
end

-- Overlays -------------------------------------------------------------------

local function styleOverlay(mover)
	local chosen = selected == mover.key
	mover.overlay:SetBackdropColor(0, 0, 0, chosen and 0.6 or 0.4)
	mover.overlay:SetBackdropBorderColor(Stoa:Color(chosen and "accent" or "muted"))
	mover.text:SetTextColor(Stoa:Color(chosen and "accent" or "text"))
	-- A marker as well as a colour, for anyone who can't tell them apart.
	mover.text:SetText((chosen and "> " or "") .. mover.label:upper())
end

-- The overlay covers the frame it stands for. Its scale matches the frame's,
-- so the offsets it ends a drag with mean the same thing to the frame.
local function fitOverlay(mover)
	local overlay, frame = mover.overlay, mover.frame
	local scale = frame:GetScale()
	overlay:SetScale(type(scale) == "number" and scale > 0 and scale or 1)
	overlay:ClearAllPoints()
	overlay:SetAllPoints(frame)
end

-- Moves a frame to a saved spot and keeps its overlay on it.
local function commit(mover, saved)
	local ok = xpcall(place, Stoa.catch, mover.frame, saved)
	if ok then mover.moved = true end
	fitOverlay(mover)
end

local function move(mover, saved)
	store(mover.key, saved)
	Stoa:AfterCombat(function() commit(mover, saved) end)
end

local function applyOne(mover)
	local saved = lookup(mover.key)
	if saved then
		commit(mover, saved)
	elseif mover.moved then
		mover.moved = false
		xpcall(putBack, Stoa.catch, mover)
		fitOverlay(mover)
	end
end

local function applyAll()
	for _, key in ipairs(order) do applyOne(movers[key]) end
end

local function resetOne(mover)
	if InCombatLockdown() then
		Stoa:Print("Frames can be moved once combat ends.")
		return
	end
	store(mover.key, false)
	Stoa.char.positions[mover.key] = nil
	applyOne(mover)
end

local function choose(key)
	selected = key
	for _, mover in pairs(movers) do styleOverlay(mover) end
end

local function dropped(mover)
	local overlay = mover.overlay
	overlay:StopMovingOrSizing()
	local saved = currentPosition(overlay)
	if saved then
		move(mover, saved)
	else
		fitOverlay(mover)
	end
end

local function makeOverlay(mover)
	local overlay = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
	overlay:SetFrameStrata("DIALOG")
	overlay:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
	overlay:EnableMouse(true)
	overlay:SetMovable(true)
	overlay:SetClampedToScreen(true)
	overlay:RegisterForDrag("LeftButton")
	overlay:SetScript("OnMouseDown", function(_, button)
		if button == "LeftButton" then choose(mover.key) end
	end)
	overlay:SetScript("OnMouseUp", function(_, button)
		if button == "RightButton" then
			choose(mover.key)
			resetOne(mover)
		end
	end)
	overlay:SetScript("OnDragStart", function(f)
		if InCombatLockdown() then return end
		choose(mover.key)
		f:StartMoving()
	end)
	overlay:SetScript("OnDragStop", function() dropped(mover) end)

	local text = overlay:CreateFontString(nil, "OVERLAY")
	Stoa:SetFont(text, "sans", Stoa.typeSize.caption)
	text:SetPoint("CENTER")
	mover.text = text
	overlay:Hide()
	return overlay
end

-- key: a stable id for saving. frame: a frame Stoa owns, anchored to the
-- screen or to something Stoa owns. label: its name on the overlay.
-- options.default: how to put the frame back when no spot is saved, for
-- frames whose module places them itself; otherwise the anchors the frame has
-- now are kept and used.
function Stoa:RegisterMover(key, frame, label, options)
	local mover = {
		key = key,
		frame = frame,
		label = label or key,
		default = options and options.default,
		points = remember(frame),
	}
	mover.overlay = makeOverlay(mover)
	movers[key] = mover
	table.insert(order, key)
	frame:SetMovable(true)
	frame:SetClampedToScreen(true)
	fitOverlay(mover)
	styleOverlay(mover)
	-- Placed once at load; role changes re-place it.
	self:AfterCombat(function()
		local saved = lookup(key)
		if saved then commit(mover, saved) end
	end)
	return mover
end

-- The grid -----------------------------------------------------------------------
-- Faint lines to line frames up against: the centre of the screen, and a
-- square every hundred units.

local grid

local function buildGrid()
	grid = CreateFrame("Frame", "StoaMoverGrid", UIParent)
	grid:SetAllPoints(UIParent)
	grid:SetFrameStrata("MEDIUM")
	grid:EnableMouse(false)
	grid.lines = {}
	grid:Hide()
end

local function gridLine(index, vertical, offset, centre)
	local tex = grid.lines[index]
	if not tex then
		tex = grid:CreateTexture(nil, "BACKGROUND")
		grid.lines[index] = tex
	end
	tex:ClearAllPoints()
	if vertical then
		tex:SetWidth(centre and 2 or 1)
		tex:SetPoint("TOP", grid, "TOP", offset, 0)
		tex:SetPoint("BOTTOM", grid, "BOTTOM", offset, 0)
	else
		tex:SetHeight(centre and 2 or 1)
		tex:SetPoint("LEFT", grid, "LEFT", 0, offset)
		tex:SetPoint("RIGHT", grid, "RIGHT", 0, offset)
	end
	local r, g, b = Stoa:Color(centre and "accent" or "text")
	tex:SetColorTexture(r, g, b, centre and 0.5 or 0.12)
	tex:Show()
end

local function refreshGrid()
	if not grid then buildGrid() end
	if not (unlocked and showGrid) then
		grid:Hide()
		return
	end
	local width, height = UIParent:GetWidth(), UIParent:GetHeight()
	width = type(width) == "number" and width or 1920
	height = type(height) == "number" and height or 1080
	local used = 0
	local function add(vertical, offset, centre)
		used = used + 1
		gridLine(used, vertical, offset, centre)
	end
	add(true, 0, true)
	add(false, 0, true)
	for offset = GRID_STEP, width / 2, GRID_STEP do
		add(true, offset)
		add(true, -offset)
	end
	for offset = GRID_STEP, height / 2, GRID_STEP do
		add(false, offset)
		add(false, -offset)
	end
	for i = used + 1, #grid.lines do grid.lines[i]:Hide() end
	grid:Show()
end

-- The bar ---------------------------------------------------------------------------
-- A small floating bar while unlocked: the way out, a reset for this layout,
-- and the grid. It also listens for the arrow keys.

local bar

local function roleName()
	local role = Stoa:GetRole()
	return role and (Stoa.ROLE_LABELS and Stoa.ROLE_LABELS[role] or role) or "this"
end

local function setStatus(text)
	if bar then bar.status:SetText(text) end
end

local function nudge(dx, dy)
	local mover = selected and movers[selected]
	if not mover or InCombatLockdown() then return end
	local saved = currentPosition(mover.frame)
	if not saved then return end
	move(mover, { saved[1], saved[2], saved[3] + dx, saved[4] + dy })
end

local ARROWS = {
	LEFT = { -1, 0 }, RIGHT = { 1, 0 }, UP = { 0, 1 }, DOWN = { 0, -1 },
}

local function onKey(self, key)
	-- Keyboard propagation can't change in combat; movers lock then anyway.
	if InCombatLockdown() then return end
	local step = ARROWS[key]
	-- Keys other than the arrows carry on to the game as usual.
	local handled = step and selected and true or false
	pcall(self.SetPropagateKeyboardInput, self, not handled)
	if handled then
		local size = IsShiftKeyDown() and 10 or 1
		xpcall(nudge, Stoa.catch, step[1] * size, step[2] * size)
	end
end

local function resetLayout()
	if InCombatLockdown() then
		Stoa:Print("Frames can be moved once combat ends.")
		return
	end
	for _, key in ipairs(order) do
		-- False, not nil, so an older per-character spot stops applying.
		store(key, false)
		Stoa.char.positions[key] = nil
	end
	applyAll()
	setStatus("The " .. roleName():lower() .. " layout is back to its defaults.")
end

local function buildBar()
	local UI = Stoa.UI
	bar = CreateFrame("Frame", "StoaMoverBar", UIParent)
	bar:SetSize(BAR_WIDTH, 78)
	bar:SetPoint("TOP", UIParent, "TOP", 0, -90)
	bar:SetFrameStrata("FULLSCREEN_DIALOG")
	bar:EnableMouse(true)
	bar:EnableKeyboard(true)
	pcall(bar.SetPropagateKeyboardInput, bar, true)
	bar:SetScript("OnKeyDown", onKey)
	UI.roundPanel(bar, 0.97)

	local title = UI.text(bar, "serif", Stoa.typeSize.label, "text")
	title:SetPoint("TOPLEFT", 14, -10)
	bar.title = title
	local status = UI.text(bar, "italic", Stoa.typeSize.caption, "muted", "LEFT")
	status:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -3)
	status:SetPoint("RIGHT", bar, "RIGHT", -14, 0)
	bar.status = status

	local lock = UI.button(bar, "Lock", 80, function() Stoa:ToggleMovers() end)
	lock:SetPoint("BOTTOMRIGHT", -12, 10)

	-- Reset asks twice; the second click within a few seconds does it.
	local armed = 0
	local reset
	reset = UI.button(bar, "Reset this layout", 170, function()
		if armed > 0 then
			armed = 0
			reset.text:SetText("Reset this layout")
			resetLayout()
			return
		end
		armed = GetTime() + 4
		reset.text:SetText("Click again to confirm")
		setStatus("This puts every frame in the " .. roleName():lower() .. " layout back to its default spot.")
		C_Timer.After(4, function()
			if armed > 0 and GetTime() >= armed then
				armed = 0
				reset.text:SetText("Reset this layout")
			end
		end)
	end)
	reset:SetPoint("RIGHT", lock, "LEFT", -8, 0)
	bar.reset = reset

	local gridButton = UI.button(bar, "Grid", 70, function(button)
		showGrid = not showGrid
		button:SetSelected(showGrid)
		refreshGrid()
	end)
	gridButton:SetPoint("RIGHT", reset, "LEFT", -8, 0)
	bar.gridButton = gridButton

	local hint = UI.text(bar, "sans", Stoa.typeSize.caption, "muted", "LEFT")
	hint:SetPoint("BOTTOMLEFT", 14, 16)
	hint:SetText("Drag a frame. Arrows nudge it, Shift for 10. Right-click resets it.")
	hint:SetWidth(BAR_WIDTH - 14 - 80 - 8 - 170 - 8 - 70 - 30)
	hint:SetWordWrap(true)
	bar:Hide()
	UI.applyTheme()
end

-- Locking and unlocking ---------------------------------------------------------------

local function setUnlocked(value)
	unlocked = value
	if value and not bar then buildBar() end
	if not value then selected = nil end
	for _, mover in pairs(movers) do
		if value then fitOverlay(mover) end
		styleOverlay(mover)
		mover.overlay:SetShown(value)
	end
	if bar then
		bar:SetShown(value)
		bar.gridButton:SetSelected(showGrid)
		bar.title:SetText("Moving frames: " .. roleName() .. " layout")
		setStatus("Frames you move here are saved for this layout only.")
	end
	refreshGrid()
end

function Stoa:ToggleMovers()
	if InCombatLockdown() then
		self:Print("Frames can be moved once combat ends.")
		return
	end
	setUnlocked(not unlocked)
	self:Print(unlocked and "Frames unlocked. Drag to move, /stoa unlock to lock." or "Frames locked.")
end

function Stoa:MoversUnlocked()
	return unlocked
end

-- Entering combat always locks, so a stray drag can't move frames mid-fight.
Stoa:On("PLAYER_REGEN_DISABLED", function()
	if unlocked then
		setUnlocked(false)
		Stoa:Print("Frames locked for combat.")
	end
end)

-- Each role keeps its own spots, so a new role brings its own into place.
-- Frames can't move in combat, so that waits for it to end.
Stoa:On("STOA_ROLE_CHANGED", function()
	Stoa:AfterCombat(function()
		xpcall(applyAll, Stoa.catch)
		if unlocked and bar then
			bar.title:SetText("Moving frames: " .. roleName() .. " layout")
		end
	end)
end)

Stoa:On("STOA_THEME_CHANGED", function()
	for _, mover in pairs(movers) do styleOverlay(mover) end
	if grid and grid:IsShown() then refreshGrid() end
end)

-- /stoa reset puts every moved frame back in its default spot, in every
-- layout.
Stoa.commands.reset = function()
	if InCombatLockdown() then
		Stoa:Print("Frames can be reset once combat ends.")
		return
	end
	wipe(Stoa.char.positions)
	wipe(layouts())
	applyAll()
	Stoa:Print("Frame positions reset.")
end

-- Exposed for tests.
Stoa.Movers = { movers = movers, lookup = lookup, applyAll = applyAll, dropped = dropped, nudge = nudge, onKey = onKey, select = choose }
