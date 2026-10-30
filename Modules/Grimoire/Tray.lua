-- Stoa: the icon tray. Other addons hang their buttons round the minimap's
-- edge, where they crowd the frame and the zone name. Stoa gathers them into
-- one small rounded button below the map's left corner; a click opens a
-- tray beside it with the icons in rows, dressed as Stoa's rounded sockets,
-- and it folds away again a moment after the mouse leaves.
--
-- Buttons made with LibDBIcon (most addons) are taken by name. Others are
-- found among the minimap's children: named buttons of icon size that
-- aren't Blizzard's own (mail, tracking, clock, zoom) or map pins.
-- /stoa tray lists what was gathered; /stoa tray leave <name> hands one
-- back to the minimap.
local _, ns = ...
local Stoa = ns.Stoa
local UI = Stoa.UI

local Tray = Stoa:NewModule("Tray", {
	-- Button names left on the minimap.
	leave = {},
})

local SIZE = 26
local GAP = 6
local PAD = 8
local COLUMNS = 5

-- Blizzard's own pieces and map pins stay where they are.
local BLIZZARD = {
	"^Minimap", "^MiniMap", "^GameTime", "^TimeManager", "^QueueStatus", "^AddonCompartment",
	"^GarrisonLandingPage", "^ExpansionLandingPage", "^Stoa", "^LibDBIcon10_$",
}
local PINS = { "Pin", "pin", "HereBeDragons", "HBD", "GatherMate", "HandyNotes", "TomTom", "Questie", "Arrow", "Ping" }

local function stays(name)
	for _, pattern in ipairs(BLIZZARD) do
		if name:find(pattern) then return true end
	end
	for _, word in ipairs(PINS) do
		if name:find(word, 1, true) then return true end
	end
	return false
end

-- Textures that make a button round: the tracking ring and dark disc.
local ROUND = { [136430] = true, [136467] = true }
local function roundArt(tex)
	local file = tex.GetTexture and tex:GetTexture()
	if type(file) == "number" then return ROUND[file] end
	if type(file) == "string" then
		local lower = file:lower()
		return lower:find("trackingborder", 1, true) or lower:find("minimap%-background") or lower:find("ui%-minimap%-background")
	end
end

local function libDBIcon()
	return _G.LibStub and _G.LibStub("LibDBIcon-1.0", true)
end

-- Gathering ---------------------------------------------------------------------

function Tray:Wanted(button, name)
	if not button or not name or self.taken[button] then return false end
	if self.db.leave[name] then return false end
	if button.IsProtected and button:IsProtected() then return false end
	return true
end

-- An addon's own button among the minimap's children: a named button of
-- icon size, square-ish, not Blizzard's and not a pin.
local function looksLikeButton(child)
	if not (child.GetObjectType and child:GetObjectType() == "Button") then return false end
	local name = child:GetName()
	if not name or stays(name) then return false end
	local width, height = child:GetWidth(), child:GetHeight()
	if not (width and height) or width < 18 or width > 42 or height < 18 or height > 42 then return false end
	return math.abs(width - height) <= 6
end

function Tray:Scan()
	local found = false
	local lib = libDBIcon()
	if lib and lib.GetButtonList then
		for _, name in ipairs(lib:GetButtonList() or {}) do
			local button = lib:GetMinimapButton(name)
			if self:Wanted(button, name) then
				self:Take(button, name, true)
				found = true
			end
		end
	end
	for _, parent in ipairs({ Minimap, MinimapBackdrop }) do
		if parent and parent.GetChildren then
			for _, child in ipairs({ parent:GetChildren() }) do
				if looksLikeButton(child) and self:Wanted(child, child:GetName()) then
					self:Take(child, child:GetName(), false)
					found = true
				end
			end
		end
	end
	if found then self:Layout() end
end

-- Moves a button into the tray and keeps it there: its addon may set its
-- spot again (a drag, a profile change), so each SetPoint is answered by
-- Stoa's own.
function Tray:Take(button, name, isLib)
	self.taken[button] = name
	table.insert(self.buttons, button)
	button:SetParent(self.tray)
	button:SetFrameStrata("DIALOG")
	button:SetScale(1)
	if button.RegisterForDrag then button:RegisterForDrag() end
	button:SetScript("OnDragStart", nil)
	button:SetScript("OnDragStop", nil)
	self:Dress(button, isLib)
	-- LibDBIcon can fade its buttons until the map is hovered; in the tray
	-- they always show.
	if button.fadeOut and button.fadeOut.Play then
		hooksecurefunc(button.fadeOut, "Play", function(anim)
			anim:Stop()
			button:SetAlpha(1)
		end)
	end
	hooksecurefunc(button, "SetPoint", function()
		if self.placing then return end
		self:Place(button)
	end)
	button:HookScript("OnShow", function() self:Layout() end)
	button:HookScript("OnHide", function() self:Layout() end)
	-- Hovering an icon keeps the tray open.
	button:HookScript("OnEnter", function() self:Hold() end)
	button:HookScript("OnLeave", function() self:Release() end)
end

-- A rounded socket under each icon, the round ring and disc taken off, and
-- the icon masked to Stoa's rounded square.
function Tray:Dress(button, isLib)
	for _, region in ipairs({ button:GetRegions() }) do
		if region.GetObjectType and region:GetObjectType() == "Texture" and roundArt(region) then
			region:SetAlpha(0)
		end
	end
	if isLib then
		if button.border then button.border:SetAlpha(0) end
		if button.background then button.background:SetAlpha(0) end
	end
	local socket = CreateFrame("Frame", nil, button)
	socket:SetPoint("TOPLEFT", -1, 1)
	socket:SetPoint("BOTTOMRIGHT", 1, -1)
	socket:SetFrameLevel(math.max(button:GetFrameLevel() - 1, 0))
	UI.roundPanel(socket, 0.9)
	local icon = button.icon
	if icon and icon.SetPoint then
		icon:ClearAllPoints()
		icon:SetPoint("TOPLEFT", 3, -3)
		icon:SetPoint("BOTTOMRIGHT", -3, 3)
		if icon.AddMaskTexture and not button.stoaMask then
			local mask = button:CreateMaskTexture()
			mask:SetTexture(UI.MEDIA .. "Textures\\ButtonMask", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
			mask:SetAllPoints(icon)
			icon:AddMaskTexture(mask)
			button.stoaMask = mask
		end
	end
	button.stoaSize = math.max(button:GetWidth(), button:GetHeight(), 1)
end

-- The tray ------------------------------------------------------------------------

function Tray:Build()
	local map = Minimap
	-- The painted frame reaches past the map; the button sits clear of it.
	local reach = 4
	local style = Stoa.modules.Minimap
	if style and style.painted then reach = math.floor(map:GetWidth() * 0.19) end

	local handle = CreateFrame("Button", "StoaTrayButton", map:GetParent() or UIParent)
	handle:SetSize(22, 22)
	handle:SetPoint("TOPRIGHT", map, "BOTTOMLEFT", -reach, -reach)
	handle:SetFrameStrata("MEDIUM")
	handle:SetFrameLevel(map:GetFrameLevel() + 6)
	UI.roundPanel(handle, 0.92)
	local glow = UI.roundBorder(handle, "CardEdge.tga", 1)
	-- Four small squares: a tray of things.
	local dots = {}
	for i = 1, 4 do
		local dot = handle:CreateTexture(nil, "OVERLAY")
		dot:SetSize(4, 4)
		dot:SetTexture(UI.WHITE)
		dot:SetPoint("CENTER", (i % 2 == 1) and -3 or 3, (i <= 2) and 3 or -3)
		dots[i] = dot
	end
	local function colour()
		local lit = handle:IsMouseOver() or (self.tray and self.tray:IsShown())
		for _, dot in ipairs(dots) do dot:SetVertexColor(Stoa:Color(lit and "accent" or "muted")) end
		if lit then glow:Set(Stoa:Color("accent")) else glow:Clear() end
	end
	handle:SetScript("OnClick", function()
		self.tray:SetShown(not self.tray:IsShown())
		colour()
	end)
	handle:SetScript("OnEnter", function()
		colour()
		self:Hold()
		if GameTooltip then
			GameTooltip:SetOwner(handle, "ANCHOR_LEFT")
			GameTooltip:AddLine("Addon icons")
			GameTooltip:AddLine(("%d gathered here. Click to open."):format(self:Count()), 1, 1, 1)
			GameTooltip:Show()
		end
	end)
	handle:SetScript("OnLeave", function()
		colour()
		self:Release()
		if GameTooltip then GameTooltip:Hide() end
	end)
	Stoa:On("STOA_THEME_CHANGED", colour)
	self.handle, self.colour = handle, colour

	local tray = CreateFrame("Frame", "StoaTray", handle)
	tray:SetPoint("TOPRIGHT", handle, "TOPLEFT", -6, 0)
	tray:SetFrameStrata("DIALOG")
	tray:EnableMouse(true)
	tray:SetScript("OnEnter", function() self:Hold() end)
	tray:SetScript("OnLeave", function() self:Release() end)
	tray:SetScript("OnHide", colour)
	tray:Hide()
	UI.roundPanel(tray, 0.96)
	self.tray = tray
	UI.applyTheme()
	colour()
end

-- Folds a moment after the mouse leaves both the button and the tray.
function Tray:Hold()
	self.leaving = (self.leaving or 0) + 1
end

function Tray:Release()
	self.leaving = (self.leaving or 0) + 1
	local mark = self.leaving
	C_Timer.After(1.2, function()
		if mark ~= self.leaving or not self.tray:IsShown() then return end
		if self.tray:IsMouseOver() or self.handle:IsMouseOver() then return end
		self.tray:Hide()
	end)
end

function Tray:Shown()
	local list = {}
	for _, button in ipairs(self.buttons) do
		-- A button its addon hides (often a setting there) stays hidden.
		local hidden = button.db and button.db.hide
		if button:IsShown() and not hidden then list[#list + 1] = button end
	end
	return list
end

function Tray:Count()
	return #self:Shown()
end

function Tray:Place(button)
	local index = self.index[button]
	self.placing = true
	button:ClearAllPoints()
	if index then
		local column = (index - 1) % COLUMNS
		local row = math.floor((index - 1) / COLUMNS)
		button:SetScale(SIZE / (button.stoaSize or SIZE))
		local scale = button:GetScale()
		button:SetPoint("TOPRIGHT", self.tray, "TOPRIGHT",
			-(PAD + column * (SIZE + GAP)) / scale, -(PAD + row * (SIZE + GAP)) / scale)
	else
		button:SetPoint("CENTER", self.tray, "CENTER")
	end
	button:SetAlpha(1)
	self.placing = false
end

function Tray:Layout()
	if self.laying then return end
	self.laying = true
	local list = self:Shown()
	table.sort(list, function(a, b) return (self.taken[a] or "") < (self.taken[b] or "") end)
	self.index = {}
	for i, button in ipairs(list) do self.index[button] = i end
	for _, button in ipairs(list) do self:Place(button) end
	local count = #list
	local columns = math.max(math.min(count, COLUMNS), 1)
	local rows = math.max(math.ceil(count / COLUMNS), 1)
	self.tray:SetSize(PAD * 2 + columns * SIZE + (columns - 1) * GAP, PAD * 2 + rows * SIZE + (rows - 1) * GAP)
	self.handle:SetShown(count > 0)
	if count == 0 then self.tray:Hide() end
	self.laying = false
end

function Tray:OnEnable()
	if not Minimap then return end
	self.taken, self.buttons, self.index = {}, {}, {}
	self:Build()
	self:Layout()
	local lib = libDBIcon()
	if lib and lib.RegisterCallback then
		lib.RegisterCallback(self, "LibDBIcon_IconCreated", function()
			C_Timer.After(0, function() xpcall(self.Scan, Stoa.catch, self) end)
		end)
	end
	-- Addons make their buttons as they load and some only at entering
	-- the world, so look again a little later too.
	local function scan() xpcall(self.Scan, Stoa.catch, self) end
	Stoa:On("PLAYER_ENTERING_WORLD", function()
		C_Timer.After(2, scan)
		C_Timer.After(8, scan)
	end)
	Stoa:On("ADDON_LOADED", function()
		if self.pending then return end
		self.pending = true
		C_Timer.After(1, function()
			self.pending = false
			scan()
		end)
	end)
	scan()

	Stoa.commands.tray = function(rest)
		local verb, name = (rest or ""):match("^(%S*)%s*(.-)%s*$")
		if verb == "leave" and name ~= "" then
			self.db.leave[name] = true
			Stoa:Print(("%s stays on the minimap after /reload."):format(name))
			return
		elseif verb == "take" and name ~= "" then
			self.db.leave[name] = nil
			Stoa:Print(("%s joins the tray after /reload."):format(name))
			return
		end
		local names = {}
		for _, each in pairs(self.taken) do names[#names + 1] = each end
		table.sort(names)
		Stoa:Print(("Icon tray: %s"):format(#names > 0 and table.concat(names, ", ") or "nothing gathered yet"))
		local left = {}
		for each in pairs(self.db.leave) do left[#left + 1] = each end
		if #left > 0 then Stoa:Print(("Left on the minimap: %s"):format(table.concat(left, ", "))) end
		Stoa:Print("/stoa tray leave <name> keeps one on the minimap; /stoa tray take <name> brings it back.")
	end
end
