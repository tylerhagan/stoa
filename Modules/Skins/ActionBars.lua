-- Stoa: round, quiet action buttons.
-- Blizzard's own buttons keep doing the work; Stoa only redraws them. The
-- square slot art goes, icons are masked round inside a hairline ring, an
-- empty slot is a dim socket, and cooldowns sweep in a circle. Key labels
-- and counts use Stoa's type.
--
-- Only textures and fonts change, which is allowed on secure buttons; it
-- all happens out of combat at load.
local _, ns = ...
local Stoa = ns.Stoa
local UI = Stoa.UI

local Bars = Stoa:NewModule("ActionBars")

local PREFIXES = {
	"ActionButton", "MultiBarBottomLeftButton", "MultiBarBottomRightButton",
	"MultiBarRightButton", "MultiBarLeftButton", "MultiBar5Button",
	"MultiBar6Button", "MultiBar7Button", "PetActionButton", "StanceButton",
}
local HIDDEN_ART = { "SlotArt", "SlotBackground", "Border", "FloatingBG", "NormalTexture" }

local function hideSquareArt(button)
	for _, key in ipairs(HIDDEN_ART) do
		local art = button[key]
		if art and art.SetAlpha then art:SetAlpha(0) end
	end
	local normal = button.GetNormalTexture and button:GetNormalTexture()
	if normal then normal:SetAlpha(0) end
end

local function roundMask(button)
	local mask = button.IconMask
	if not mask then
		mask = button:CreateMaskTexture()
		mask:SetAllPoints()
		local icon = button.icon or button.Icon
		if icon then icon:AddMaskTexture(mask) end
	end
	mask:SetTexture(UI.CIRCLE_MASK, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
	return mask
end

function Bars:Skin(button)
	if not button or button.stoaRound then return end
	button.stoaRound = true
	hideSquareArt(button)

	local icon = button.icon or button.Icon
	if icon then icon:SetTexCoord(0.07, 0.93, 0.07, 0.93) end
	local mask = roundMask(button)

	-- Highlight, pressed and checked states follow the round shape.
	for _, getter in ipairs({ "GetHighlightTexture", "GetPushedTexture", "GetCheckedTexture" }) do
		local tex = button[getter] and button[getter](button)
		if tex then pcall(tex.AddMaskTexture, tex, mask) end
	end

	-- The socket: a hairline ring with a dark disc, seen through an empty slot.
	local ring = UI.circle(button, "BACKGROUND", -8, 10, "hairline")
	ring:ClearAllPoints()
	ring:SetPoint("TOPLEFT", -1, 1)
	ring:SetPoint("BOTTOMRIGHT", 1, -1)
	local socket = UI.circle(button, "BACKGROUND", -7, 10, "panel")
	socket:ClearAllPoints()
	socket:SetPoint("TOPLEFT", 0, 0)
	socket:SetPoint("BOTTOMRIGHT", 0, 0)

	local cooldown = button.cooldown or button.Cooldown
	if cooldown then
		if cooldown.SetSwipeTexture then cooldown:SetSwipeTexture(UI.CIRCLE_MASK) end
		if cooldown.SetUseCircularEdge then cooldown:SetUseCircularEdge(true) end
	end

	local hotkey = button.HotKey
	if hotkey then
		Stoa:SetFont(hotkey, "sans", Stoa.typeSize.caption - 1, "OUTLINE")
		hotkey:SetTextColor(Stoa:Color("muted"))
	end
	local count = button.Count
	if count then Stoa:SetFont(count, "sans", Stoa.typeSize.body, "OUTLINE") end
	local macro = button.Name
	if macro then macro:SetAlpha(0) end

	-- Blizzard redraws the slot art when a button's contents change.
	if button.UpdateButtonArt then
		hooksecurefunc(button, "UpdateButtonArt", hideSquareArt)
	end
	if button.Update then
		hooksecurefunc(button, "Update", hideSquareArt)
	end
	UI.applyTheme()
end

function Bars:SkinAll()
	for _, prefix in ipairs(PREFIXES) do
		for i = 1, 12 do
			local button = _G[prefix .. i]
			if button then xpcall(self.Skin, geterrorhandler(), self, button) end
		end
	end
end

function Bars:OnEnable()
	Stoa:AfterCombat(function() self:SkinAll() end)
	-- Hotkey colours follow the theme.
	Stoa:On("STOA_THEME_CHANGED", function()
		for _, prefix in ipairs(PREFIXES) do
			for i = 1, 12 do
				local button = _G[prefix .. i]
				if button and button.stoaRound and button.HotKey then
					button.HotKey:SetTextColor(Stoa:Color("muted"))
				end
			end
		end
	end)
end
