-- Stoa QoL: the raid marker strip.
-- A quiet row of the eight raid target icons and a clear button, for tanks
-- and group leaders. Click an icon to mark your target; Shift-click it to
-- put that world marker on the ground. It sits under the tank watch by
-- default and can be moved.
--
-- World markers are a protected action, so each icon is a secure button,
-- made once out of combat. The strip hides and shows by its container, which
-- is a plain frame, so that works in combat too.
local _, ns = ...
local Stoa = ns.Stoa
local UI = Stoa.UI

local Markers = Stoa:NewModule("Markers", {
	show = "GROUP",
})

local ICON = 20
local GAP = 4
local QUIET = 0.6
local TEXTURE = "Interface\\TargetingFrame\\UI-RaidTargetingIcons"
local NAMES = { "Star", "Circle", "Diamond", "Triangle", "Moon", "Square", "Cross", "Skull" }

-- Only tanks and those who may lead get the strip.
function Markers:Eligible()
	if not IsInGroup() then return false end
	return Stoa:GetRole() == "TANK" or Stoa:CanLead()
end

function Markers:Rule()
	if not self:Eligible() then return "NEVER" end
	return self.db.show or "GROUP"
end

local function mark(index)
	if not UnitExists("target") then return end
	if SetRaidTarget then pcall(SetRaidTarget, "target", index) end
end

local function tip(button, text)
	button:SetScript("OnEnter", function(self)
		self:SetAlpha(1)
		if GameTooltip and GameTooltip.SetOwner then
			GameTooltip:SetOwner(self, "ANCHOR_TOP")
			GameTooltip:SetText(text)
			GameTooltip:Show()
		end
	end)
	button:SetScript("OnLeave", function(self)
		self:SetAlpha(QUIET)
		if GameTooltip and GameTooltip.Hide then GameTooltip:Hide() end
	end)
end

-- One icon. Secure, so a Shift-click can place a world marker; the plain
-- click marks the target from a post-click script.
function Markers:MakeIcon(parent, index)
	local button = CreateFrame("Button", "StoaMarker" .. index, parent, "SecureActionButtonTemplate")
	button:SetSize(ICON, ICON)
	button:RegisterForClicks("AnyUp")
	button:SetAlpha(QUIET)
	local tex = button:CreateTexture(nil, "ARTWORK")
	tex:SetAllPoints()
	tex:SetTexture(TEXTURE)
	local col, row = (index - 1) % 4, math.floor((index - 1) / 4)
	tex:SetTexCoord(col * 0.25, (col + 1) * 0.25, row * 0.25, (row + 1) * 0.25)
	if self.worldMarkers then
		button:SetAttribute("shift-type1", "worldmarker")
		button:SetAttribute("shift-marker1", index)
		button:SetAttribute("shift-action1", "set")
	end
	button:SetScript("PostClick", function(_, mouse)
		if mouse == "LeftButton" and not IsShiftKeyDown() then mark(index) end
	end)
	tip(button, NAMES[index] .. (self.worldMarkers and "  ·  Shift: on the ground" or ""))
	return button
end

function Markers:MakeClear(parent)
	local button = CreateFrame("Button", "StoaMarkerClear", parent)
	button:SetSize(ICON, ICON)
	button:RegisterForClicks("LeftButtonUp")
	button:SetAlpha(QUIET)
	local word = UI.text(button, "sans", Stoa.typeSize.caption, "text", "CENTER")
	word:SetPoint("CENTER")
	word:SetText("×")
	button:SetScript("OnClick", function() mark(0) end)
	tip(button, "Clear the mark")
	return button
end

function Markers:Build()
	if self.frame then return end
	-- World markers need the secure action; skip the Shift-click if this
	-- client has no such call.
	self.worldMarkers = type(PlaceRaidMarker) == "function"
	local width = 9 * ICON + 8 * GAP
	local frame = CreateFrame("Frame", "StoaMarkers", UIParent)
	frame:SetSize(width, ICON)
	frame:SetFrameStrata("LOW")
	frame:EnableMouse(false)
	local watch = _G.StoaTankWatch
	if watch then
		frame:SetPoint("TOP", watch, "BOTTOM", 0, -8)
	else
		frame:SetPoint("CENTER", UIParent, "CENTER", -380, 40)
	end
	frame:SetAlpha(0)
	frame:Hide()
	self.frame, self.buttons = frame, {}
	for i = 1, 8 do
		local button = self:MakeIcon(frame, i)
		button:SetPoint("LEFT", (i - 1) * (ICON + GAP), 0)
		self.buttons[i] = button
	end
	local clear = self:MakeClear(frame)
	clear:SetPoint("LEFT", 8 * (ICON + GAP), 0)
	self.buttons[9] = clear
	Stoa:RegisterMover("markers", frame, "Raid markers")
end

function Markers:OnEnable()
	-- Secure buttons can only be made out of combat.
	Stoa:AfterCombat(function()
		xpcall(function()
			self:Build()
			Stoa.Rules.watch(self.frame, function() return self:Rule() end, {
				alpha = 1, fade = false,
				onChange = function(shown) self.frame:SetShown(shown) end,
			})
		end, Stoa.catch)
	end)
	for _, event in ipairs({ "STOA_ROLE_CHANGED", "PARTY_LEADER_CHANGED" }) do
		Stoa:On(event, function() Stoa:Fire("STOA_RULES_CHANGED") end)
	end
end
