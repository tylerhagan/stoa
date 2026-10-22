-- Stoa: shared building blocks for every Stoa frame. Anything painted here
-- follows the theme, and unit values go straight into widgets so secret
-- values in combat are never compared or calculated with.
local _, ns = ...
local Stoa = ns.Stoa

local UI = {}
Stoa.UI = UI

UI.CIRCLE_MASK = "Interface\\CharacterFrame\\TempPortraitAlphaMask"
UI.WHITE = "Interface\\Buttons\\WHITE8x8"
UI.MEDIA = "Interface\\AddOns\\Stoa\\Media\\"

local themed = {}

-- Paints a texture, status bar or font string with a theme token now and on
-- every theme change.
function UI.paint(region, token, alpha)
	table.insert(themed, { region = region, token = token, alpha = alpha })
	return region
end

function UI.applyTheme()
	for _, entry in ipairs(themed) do
		local r, g, b, a = Stoa:Color(entry.token)
		a = entry.alpha or a
		if entry.vertex then
			entry.region:SetVertexColor(r, g, b, a)
		elseif entry.region.SetColorTexture then
			entry.region:SetColorTexture(r, g, b, a)
		elseif entry.region.SetStatusBarColor then
			entry.region:SetStatusBarColor(r, g, b, a)
		else
			entry.region:SetTextColor(r, g, b, a)
		end
	end
end

Stoa:On("STOA_THEME_CHANGED", UI.applyTheme)

-- Tints a texture that has its own image (not a flat colour) with a token.
function UI.tint(tex, token, alpha)
	table.insert(themed, { region = tex, token = token, alpha = alpha, vertex = true })
	return tex
end

function UI.circle(parent, layer, sublevel, size, token, alpha)
	local tex = parent:CreateTexture(nil, layer, nil, sublevel)
	tex:SetSize(size, size)
	local mask = parent:CreateMaskTexture()
	mask:SetTexture(UI.CIRCLE_MASK, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
	mask:SetAllPoints(tex)
	tex:AddMaskTexture(mask)
	if token then UI.paint(tex, token, alpha) end
	return tex
end

function UI.line(parent, token, alpha)
	local tex = parent:CreateTexture(nil, "BORDER")
	tex:SetHeight(1)
	UI.paint(tex, token or "hairline", alpha)
	return tex
end

function UI.text(parent, kind, size, token, justify)
	local fs = parent:CreateFontString(nil, "OVERLAY")
	Stoa:SetFont(fs, kind, size)
	fs:SetJustifyH(justify or "LEFT")
	UI.paint(fs, token or "text")
	return fs
end

-- Small caps label, the section heading used everywhere.
function UI.caption(parent, label)
	local fs = UI.text(parent, "sans", Stoa.typeSize.caption, "muted")
	fs:SetText(label:upper())
	return fs
end

function UI.bar(parent, width, height, token)
	local sb = CreateFrame("StatusBar", nil, parent)
	sb:SetSize(width, height)
	sb:SetStatusBarTexture(UI.WHITE)
	UI.paint(sb, token)
	local track = sb:CreateTexture(nil, "BACKGROUND")
	track:SetAllPoints()
	UI.paint(track, "text", 0.08)
	sb.track = track
	sb:SetMinMaxValues(0, 1)
	sb:SetValue(1)
	return sb
end

function UI.setUnitBar(sb, unit, kind)
	if kind == "health" then
		sb:SetMinMaxValues(0, UnitHealthMax(unit))
		sb:SetValue(UnitHealth(unit))
	else
		sb:SetMinMaxValues(0, UnitPowerMax(unit))
		sb:SetValue(UnitPower(unit))
	end
end

function UI.classColor(unit)
	local _, classFile = UnitClass(unit)
	if not Stoa:Theme().classTint or not classFile or Stoa:IsSecret(classFile) then
		return Stoa:Color("text")
	end
	local color = RAID_CLASS_COLORS[classFile]
	if not color then return Stoa:Color("text") end
	return color.r, color.g, color.b
end

-- Eases a frame's alpha. Alpha is safe to change on any frame in combat.
function UI.fade(frame, to, seconds)
	local from, start = frame:GetAlpha(), GetTime()
	frame.stoaFade = frame.stoaFade or CreateFrame("Frame")
	frame.stoaFade:SetScript("OnUpdate", function(self)
		local progress = math.min((GetTime() - start) / seconds, 1)
		frame:SetAlpha(from + (to - from) * progress)
		if progress >= 1 then self:SetScript("OnUpdate", nil) end
	end)
end

-- A hidden parent for Blizzard frames Stoa replaces.
UI.hidden = CreateFrame("Frame")
UI.hidden:Hide()

-- A border drawn with four textures, for cues like a dispellable debuff.
-- outset pushes it outside the frame, for a soft halo around a border.
-- Hidden until set.
function UI.border(frame, size, outset)
	size, outset = size or 2, outset or 0
	local edges = {}
	for _, side in ipairs({ "TOP", "BOTTOM", "LEFT", "RIGHT" }) do
		local tex = frame:CreateTexture(nil, "OVERLAY")
		tex:SetColorTexture(1, 1, 1)
		if side == "TOP" or side == "BOTTOM" then
			local y = side == "TOP" and outset or -outset
			tex:SetPoint(side .. "LEFT", -outset, y)
			tex:SetPoint(side .. "RIGHT", outset, y)
			tex:SetHeight(size)
		else
			local x = side == "LEFT" and -outset or outset
			tex:SetPoint("TOP" .. side, x, outset)
			tex:SetPoint("BOTTOM" .. side, x, -outset)
			tex:SetWidth(size)
		end
		tex:Hide()
		edges[#edges + 1] = tex
	end
	return {
		edges = edges,
		Set = function(_, r, g, b, a)
			for _, tex in ipairs(edges) do
				tex:SetVertexColor(r, g, b, a or 1)
				tex:Show()
			end
		end,
		Clear = function()
			for _, tex in ipairs(edges) do tex:Hide() end
		end,
	}
end

-- Unit cards ------------------------------------------------------------------
-- Party cards and raid cells share one card, after the Halo healer mockup:
-- name and health percent on top, a thick health bar with shields laid on
-- its empty end, and a row of word pips for your own buffs and dispels.
-- Party:UpdateCard fills them in.

UI.CARD_STYLES = {
	party = { pad = 9, name = 16, bar = 12, pip = 16, pipFont = 11, gap = 6 },
	compact = { pad = 7, name = 14, bar = 8, pip = 14, pipFont = 10, gap = 5 },
	raid = { pad = 7, name = 15, bar = 9, pip = 14, pipFont = 10, gap = 5 },
}

local MAX_PIPS = 3

local function makePip(card)
	local pip = CreateFrame("Frame", nil, card)
	local bg = pip:CreateTexture(nil, "BACKGROUND")
	bg:SetAllPoints()
	bg:SetColorTexture(1, 1, 1)
	pip.bg = bg
	local text = pip:CreateFontString(nil, "OVERLAY")
	text:SetPoint("CENTER", 0, 0)
	pip.text = text
	pip:Hide()
	return pip
end

-- Rounded card pieces: one small image each, nine-sliced so the corners
-- keep their shape at any size. Clients without slicing get square ones.
local CARD_SLICE = 12

local function sliced(parent, layer, file, outset)
	if not parent.CreateTexture then return nil end
	local tex = parent:CreateTexture(nil, layer)
	if not tex.SetTextureSliceMargins then
		tex:Hide()
		return nil
	end
	tex:SetTexture(UI.MEDIA .. "Textures\\" .. file)
	tex:SetTextureSliceMargins(CARD_SLICE, CARD_SLICE, CARD_SLICE, CARD_SLICE)
	if tex.SetTextureSliceMode and Enum and Enum.UITextureSliceMode then
		tex:SetTextureSliceMode(Enum.UITextureSliceMode.Stretched)
	end
	outset = outset or 0
	tex:SetPoint("TOPLEFT", -outset, outset)
	tex:SetPoint("BOTTOMRIGHT", outset, -outset)
	return tex
end

-- A rounded border with the same Set and Clear as UI.border, falling back
-- to it where slicing isn't available.
function UI.roundBorder(frame, file, size, outset)
	local tex = sliced(frame, "OVERLAY", file, outset)
	if not tex then return UI.border(frame, size, outset) end
	tex:Hide()
	return {
		edges = { tex },
		Set = function(_, r, g, b, a)
			tex:SetVertexColor(r, g, b, a or 1)
			tex:Show()
		end,
		Clear = function() tex:Hide() end,
	}
end

-- A rounded panel with a hairline edge behind a whole frame, for windows
-- Stoa restyles. Square where slicing isn't available.
function UI.roundPanel(frame, alpha)
	local bg = sliced(frame, "BACKGROUND", "CardFill.tga")
	if bg then
		bg:SetDrawLayer("BACKGROUND", -8)
		UI.tint(bg, "panel", alpha or 0.96)
	else
		bg = frame:CreateTexture(nil, "BACKGROUND", nil, -8)
		bg:SetAllPoints()
		UI.paint(bg, "panel", alpha or 0.96)
	end
	local edge = UI.roundBorder(frame, "CardEdge.tga", 1)
	for _, tex in ipairs(edge.edges) do
		UI.tint(tex, "hairline")
		tex:Show()
	end
	UI.applyTheme()
	return bg
end

function UI.unitCard(card, styleName)
	local bg = sliced(card, "BACKGROUND", "CardFill.tga")
	if bg then
		UI.tint(bg, "panel", 0.96)
	else
		bg = card:CreateTexture(nil, "BACKGROUND")
		bg:SetAllPoints()
		UI.paint(bg, "panel", 0.96)
	end

	-- A hairline frame always, and a stronger border for states: a dispel,
	-- low health or your target. Dispels also get a soft halo outside.
	local frameEdge = UI.roundBorder(card, "CardEdge.tga", 1)
	for _, tex in ipairs(frameEdge.edges) do
		tex:SetDrawLayer("BORDER")
		UI.tint(tex, "hairline")
		tex:Show()
	end
	card.state = UI.roundBorder(card, "CardState.tga", 2)
	card.glow = UI.roundBorder(card, "CardGlow.tga", 3, 3)
	-- Kept for older callers: a dispel border is the state border.
	card.dispel = card.state

	-- Not painted: the name takes its class colour on every update.
	local name = card:CreateFontString(nil, "OVERLAY")
	name:SetJustifyH("LEFT")
	name:SetWordWrap(false)
	card.name = name

	local percent = UI.text(card, "serif", Stoa.typeSize.label, "text", "RIGHT")
	card.percent = percent

	local hp = UI.bar(card, 10, 10, "health")
	card.hp = hp

	-- Shields sit on the empty end of the health bar, starting where health
	-- stops. The bar clips them so a big shield never spills past the card.
	local absorb = UI.bar(hp, 10, 10, "shield")
	absorb.track:Hide()
	absorb:SetPoint("TOPLEFT", hp:GetStatusBarTexture(), "TOPRIGHT")
	absorb:SetPoint("BOTTOMLEFT", hp:GetStatusBarTexture(), "BOTTOMRIGHT")
	absorb:SetValue(0)
	if hp.SetClipsChildren then hp:SetClipsChildren(true) end
	card.absorb = absorb

	card.pips = {}
	for i = 1, MAX_PIPS do card.pips[i] = makePip(card) end

	UI.styleCard(card, styleName)
	UI.applyTheme()
end

-- Lays out a card's insides for a style. Out of combat for party cards,
-- since the sizes follow the role.
function UI.styleCard(card, styleName)
	local style = UI.CARD_STYLES[styleName] or UI.CARD_STYLES.party
	card.style = style
	local pad = style.pad

	Stoa:SetFont(card.name, "serif", style.name)
	card.name:ClearAllPoints()
	card.name:SetPoint("TOPLEFT", pad, -pad + 1)
	card.name:SetPoint("RIGHT", card.percent, "LEFT", -6, 0)
	Stoa:SetFont(card.percent, "serif", style.name)
	card.percent:ClearAllPoints()
	card.percent:SetPoint("TOPRIGHT", -pad, -pad + 1)

	card.hp:ClearAllPoints()
	card.hp:SetPoint("TOPLEFT", pad, -(pad + style.name + 3))
	card.hp:SetPoint("TOPRIGHT", -pad, -(pad + style.name + 3))
	card.hp:SetHeight(style.bar)
	card.absorb:SetWidth(math.max(1, (card:GetWidth() or 100) - pad * 2))

	for i, pip in ipairs(card.pips) do
		pip:ClearAllPoints()
		if i == 1 then
			pip:SetPoint("TOPLEFT", card.hp, "BOTTOMLEFT", 0, -style.gap)
		else
			pip:SetPoint("LEFT", card.pips[i - 1], "RIGHT", 4, 0)
		end
		pip:SetHeight(style.pip)
		Stoa:SetFont(pip.text, "sans", style.pipFont)
	end
end

-- Fills the pip row. Each pip is { text, fill } where fill is a theme token
-- for a solid chip (dark text on it), or nil for a quiet chip.
function UI.setPips(card, list)
	for i, pip in ipairs(card.pips) do
		local entry = list and list[i]
		if entry then
			pip.text:SetText(entry[1])
			if entry[2] then
				local r, g, b = Stoa:Color(entry[2])
				pip.bg:SetVertexColor(r, g, b, 1)
				pip.text:SetTextColor(Stoa:Color("panel"))
			else
				local r, g, b = Stoa:Color("text")
				pip.bg:SetVertexColor(r, g, b, 0.14)
				pip.text:SetTextColor(Stoa:Color(entry[3] or "text"))
			end
			pip:SetWidth(math.ceil(pip.text:GetStringWidth()) + 10)
			pip:Show()
		else
			pip:Hide()
		end
	end
end
