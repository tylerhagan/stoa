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
		if entry.gradient then
			UI.setGradient(entry.region, entry.gradient, r, g, b, a)
		elseif entry.vertex then
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

-- A colour that fades across a texture: `gradient` is { orientation, start,
-- finish }, the alpha at each end as a share of `a`. HORIZONTAL runs left
-- to right, VERTICAL bottom to top. Flat at the average where the client
-- can't blend.
function UI.setGradient(tex, gradient, r, g, b, a)
	local orientation, from, to = gradient[1], gradient[2], gradient[3]
	if tex.SetGradient and CreateColor then
		tex:SetVertexColor(1, 1, 1, 1)
		local ok = pcall(tex.SetGradient, tex, orientation, CreateColor(r, g, b, a * from), CreateColor(r, g, b, a * to))
		if ok then return end
	end
	tex:SetVertexColor(r, g, b, a * (from + to) / 2)
end

-- Registers a themed fade (see UI.setGradient).
function UI.gradient(tex, token, alpha, orientation, from, to)
	table.insert(themed, { region = tex, token = token, alpha = alpha, gradient = { orientation, from, to } })
	return tex
end

-- Tints a texture that has its own image (not a flat colour) with a token.
function UI.tint(tex, token, alpha)
	table.insert(themed, { region = tex, token = token, alpha = alpha, vertex = true })
	return tex
end

-- The Painted ornament (Stoa.db.ornament): leather and brass frames on the
-- few one-of-a-kind pieces instead of fine lines.
function UI.ornate()
	return Stoa.db and Stoa.db.ornament == "painted"
end

-- A small leather and brass ring (Tools/art/coin_frame.py) round a circle
-- the given size, on the parent's overlay. Returns the leather and the
-- brass; tint the brass yourself.
local COIN_FRAME_SCALE = 1.455
function UI.coinFrame(parent, size)
	local frameSize = size * COIN_FRAME_SCALE
	local base = parent:CreateTexture(nil, "OVERLAY", nil, 0)
	base:SetTexture(UI.MEDIA .. "Textures\\CoinFrame")
	base:SetSize(frameSize, frameSize)
	base:SetPoint("CENTER")
	local lines = parent:CreateTexture(nil, "OVERLAY", nil, 1)
	lines:SetTexture(UI.MEDIA .. "Textures\\CoinFrameLines")
	lines:SetAllPoints(base)
	return base, lines
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
-- Words that float over the game world rather than sit on a panel: a fine
-- outline plus a dark shadow, so they hold up over snow and bright sky.
function UI.legible(fs)
	if not (fs and fs.GetFont) then return fs end
	local path, size = fs:GetFont()
	if path and size then pcall(fs.SetFont, fs, path, size, "OUTLINE") end
	fs:SetShadowColor(0, 0, 0, 0.9)
	fs:SetShadowOffset(1, -1)
	return fs
end

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
	frame.stoaFade:SetScript("OnUpdate", Stoa:GuardUpdate(function(self)
		local progress = math.min((GetTime() - start) / seconds, 1)
		frame:SetAlpha(from + (to - from) * progress)
		if progress >= 1 then self:SetScript("OnUpdate", nil) end
	end))
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
	-- The compact raid cell: health fills the cell behind the name, and one
	-- word or the percent sits on the right.
	cell = { pad = 5, name = 11, cell = true },
	-- The same, a size down, for forty players.
	tiny = { pad = 4, name = 10, cell = true },
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

local function sliced(parent, layer, file, outset, margin)
	if not parent.CreateTexture then return nil end
	local tex = parent:CreateTexture(nil, layer)
	if not tex.SetTextureSliceMargins then
		tex:Hide()
		return nil
	end
	tex:SetTexture(UI.MEDIA .. "Textures\\" .. file)
	margin = margin or CARD_SLICE
	tex:SetTextureSliceMargins(margin, margin, margin, margin)
	if tex.SetTextureSliceMode and Enum and Enum.UITextureSliceMode then
		tex:SetTextureSliceMode(Enum.UITextureSliceMode.Stretched)
	end
	outset = outset or 0
	tex:SetPoint("TOPLEFT", -outset, outset)
	tex:SetPoint("BOTTOMRIGHT", outset, -outset)
	return tex
end

UI.sliced = sliced

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

-- Small rounded pieces for thin bars (nameplates): a filled pill behind
-- the bar and a 1px rounded outline that can be set and cleared like
-- UI.border. Square where slicing isn't available.
local PLATE_SLICE = 5

function UI.pillFill(frame, outset)
	local tex = sliced(frame, "BACKGROUND", "PlateFill.tga", outset, PLATE_SLICE)
	if not tex then
		tex = frame:CreateTexture(nil, "BACKGROUND")
		tex:SetColorTexture(1, 1, 1)
		tex:SetPoint("TOPLEFT", -outset, outset)
		tex:SetPoint("BOTTOMRIGHT", outset, -outset)
	end
	tex:SetDrawLayer("BACKGROUND", -8)
	return tex
end

function UI.pillEdge(frame, outset)
	local tex = sliced(frame, "OVERLAY", "PlateEdge.tga", outset, PLATE_SLICE)
	if not tex then return UI.border(frame, 1, outset) end
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

-- Blizzard's collapse buttons as a quiet minus or plus that warms to the
-- accent under the mouse. Returns a function taking the collapsed state.
function UI.foldGlyph(button)
	local function plain()
		for _, getter in ipairs({ "GetNormalTexture", "GetPushedTexture", "GetHighlightTexture" }) do
			local tex = button[getter] and button[getter](button)
			if tex then tex:SetAlpha(0) end
		end
	end
	local glyph = button:CreateFontString(nil, "OVERLAY")
	Stoa:SetFont(glyph, "sans", Stoa.typeSize.label)
	glyph:SetPoint("CENTER", 0, 1)
	glyph:SetTextColor(Stoa:Color("muted"))
	button:HookScript("OnEnter", function() glyph:SetTextColor(Stoa:Color("accent")) end)
	button:HookScript("OnLeave", function() glyph:SetTextColor(Stoa:Color("muted")) end)
	return function(collapsed)
		plain()
		glyph:SetText(collapsed and "+" or "–")
	end
end

-- A rounded panel with a hairline edge behind a whole frame, for windows
-- Stoa restyles. `kind` "window" takes the window corners (10px) instead
-- of the card ones. Square where slicing isn't available.
function UI.roundPanel(frame, alpha, kind)
	local fill, edgeFile = "CardFill.tga", "CardEdge.tga"
	if kind == "window" then fill, edgeFile = "WindowFill.tga", "WindowEdge.tga" end
	local bg = sliced(frame, "BACKGROUND", fill)
	if bg then
		bg:SetDrawLayer("BACKGROUND", -8)
		UI.tint(bg, "panel", alpha or 0.96)
	else
		bg = frame:CreateTexture(nil, "BACKGROUND", nil, -8)
		bg:SetAllPoints()
		UI.paint(bg, "panel", alpha or 0.96)
	end
	local edge = UI.roundBorder(frame, edgeFile, 1)
	for _, tex in ipairs(edge.edges) do
		UI.tint(tex, "hairline")
		tex:Show()
	end
	frame.stoaPanelEdge = edge
	UI.applyTheme()
	return bg
end

-- A hairline that fades out at both ends, for dividing sections. Returns a
-- frame to place like any line (set its two side points).
function UI.fadeRule(parent, token, alpha)
	local rule = CreateFrame("Frame", nil, parent)
	rule:SetHeight(1)
	for i, side in ipairs({ "LEFT", "RIGHT" }) do
		local tex = rule:CreateTexture(nil, "BORDER")
		tex:SetTexture(UI.WHITE)
		tex:SetPoint("TOP" .. side)
		tex:SetPoint("BOTTOM" .. side)
		tex:SetPoint(i == 1 and "RIGHT" or "LEFT", rule, "CENTER")
		UI.gradient(tex, token or "text", alpha or 0.28, "HORIZONTAL", i == 1 and 0 or 1, i == 1 and 1 or 0)
	end
	UI.applyTheme()
	return rule
end

-- A soft shadow under a raised band: a dark line and a short fade below it.
function UI.shadowLine(parent, anchor)
	local line = parent:CreateTexture(nil, "BORDER", nil, 2)
	line:SetTexture(UI.WHITE)
	line:SetVertexColor(0, 0, 0, 0.7)
	line:SetHeight(1)
	line:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT")
	line:SetPoint("TOPRIGHT", anchor, "BOTTOMRIGHT")
	local fall = parent:CreateTexture(nil, "BORDER", nil, 1)
	fall:SetTexture(UI.WHITE)
	fall:SetHeight(4)
	fall:SetPoint("TOPLEFT", line, "BOTTOMLEFT")
	fall:SetPoint("TOPRIGHT", line, "BOTTOMRIGHT")
	UI.setGradient(fall, { "VERTICAL", 0, 1 }, 0, 0, 0, 0.35)
	return line, fall
end

-- Window stone ----------------------------------------------------------------
-- Tyler's stone, its faint rings and grain, laid over the body of every
-- window (quests, merchants, bags, Stoa's own pages) but never the console,
-- buttons or tooltips. The texture is white with alpha and takes the
-- theme's text colour, so it sits on any theme's panel. Each window shows
-- a slice of it at its natural size rather than stretching it, and it
-- fades out towards the top, where titles and text start.

local STONE = UI.MEDIA .. "Textures\\WindowStone"
local STONE_SIZE = 1024
local STONE_INSET = 2
UI.STONE_STRENGTH = 0.26
-- The stone's strength at the top of a body, as a share of the bottom's.
local STONE_TOP = 0.3
local stones = {}

local function fitStone(tex)
	local width, height = tex:GetWidth(), tex:GetHeight()
	if Stoa:IsSecret(width) or Stoa:IsSecret(height) or not width or width <= 0 then return end
	tex:SetTexCoord(0, width / STONE_SIZE, 0, height / STONE_SIZE)
end

-- `top` and `bottom` are what the stone sits between (the header and the
-- footer), or nothing for the whole window.
function UI.stone(frame, top, bottom)
	if not frame or not frame.CreateTexture or frame.stoaStone then return end
	local tex = frame:CreateTexture(nil, "BACKGROUND", nil, -7)
	tex:SetTexture(STONE, "REPEAT", "REPEAT")
	if top then
		tex:SetPoint("TOPLEFT", top, "BOTTOMLEFT")
		tex:SetPoint("TOPRIGHT", top, "BOTTOMRIGHT")
	else
		tex:SetPoint("TOPLEFT", STONE_INSET, -STONE_INSET)
		tex:SetPoint("TOPRIGHT", -STONE_INSET, -STONE_INSET)
	end
	if bottom then
		tex:SetPoint("BOTTOM", bottom, "TOP")
	else
		tex:SetPoint("BOTTOM", 0, STONE_INSET)
	end
	UI.gradient(tex, "text", UI.STONE_STRENGTH, "VERTICAL", 1, STONE_TOP)
	frame.stoaStone = tex
	stones[#stones + 1] = tex
	if frame.HookScript then
		pcall(frame.HookScript, frame, "OnSizeChanged", function() pcall(fitStone, tex) end)
	end
	pcall(fitStone, tex)
	tex:SetShown(Stoa.db == nil or Stoa.db.windowStone ~= false)
	UI.applyTheme()
	return tex
end

-- Header tints by what a window is for: warm for trade, cool for people,
-- the plain light band for the rest.
UI.WINDOW_FAMILIES = {
	trade = { token = "accent", alpha = 0.10 },
	social = { token = "mana", alpha = 0.10 },
	plain = { token = "text", alpha = 0.06 },
}
local FOOTER_SHADE = 0.32

-- A window's panel: the rounded panel, a lighter header band with a soft
-- shadow under it, a dark footer tray, and the stone in the body between.
-- `opts`: header and footer (pixels, or a region the band meets: the
-- header ends at its top, the footer starts at its bottom), family (a
-- UI.WINDOW_FAMILIES key). Either band can be left out.
function UI.windowPanel(frame, alpha, opts)
	opts = opts or {}
	local bg = UI.roundPanel(frame, alpha, "window")
	local header, footer
	if opts.header then
		header = sliced(frame, "BACKGROUND", "WindowTop.tga")
		if header then
			header:ClearAllPoints()
			header:SetPoint("TOPLEFT")
			header:SetPoint("TOPRIGHT")
			if type(opts.header) == "number" then
				header:SetHeight(opts.header)
			else
				header:SetPoint("BOTTOM", opts.header, "TOP")
			end
			header:SetDrawLayer("BACKGROUND", -6)
			local family = UI.WINDOW_FAMILIES[opts.family or "plain"] or UI.WINDOW_FAMILIES.plain
			UI.tint(header, family.token, family.alpha)
			frame.stoaHeader = header
			UI.shadowLine(frame, header)
		end
	end
	if opts.footer then
		footer = sliced(frame, "BACKGROUND", "WindowBottom.tga")
		if footer then
			footer:ClearAllPoints()
			footer:SetPoint("BOTTOMLEFT")
			footer:SetPoint("BOTTOMRIGHT")
			if type(opts.footer) == "number" then
				footer:SetHeight(opts.footer)
			else
				footer:SetPoint("TOP", opts.footer, "BOTTOM")
			end
			footer:SetDrawLayer("BACKGROUND", -6)
			footer:SetVertexColor(0, 0, 0, FOOTER_SHADE)
			local line = frame:CreateTexture(nil, "BORDER", nil, 2)
			line:SetTexture(UI.WHITE)
			line:SetVertexColor(0, 0, 0, 0.6)
			line:SetHeight(1)
			line:SetPoint("BOTTOMLEFT", footer, "TOPLEFT")
			line:SetPoint("BOTTOMRIGHT", footer, "TOPRIGHT")
			frame.stoaFooter = footer
		end
	end
	UI.stone(frame, header, footer)
	UI.applyTheme()
	return bg
end

-- Darker rounded ground behind a group of things inside a window (quest
-- rewards, bag slots).
function UI.well(frame, outset)
	if not frame or not frame.CreateTexture or frame.stoaWell then return end
	local tex = sliced(frame, "BACKGROUND", "CardFill.tga", outset or 6)
	if not tex then return end
	tex:SetDrawLayer("BACKGROUND", -5)
	tex:SetVertexColor(0, 0, 0, 0.22)
	frame.stoaWell = tex
	return tex
end

function UI.showStone(on)
	Stoa.db.windowStone = on and true or false
	for _, tex in ipairs(stones) do tex:SetShown(on and true or false) end
end

-- A Stoa button: a dark rounded panel with a word in the sans, warming to
-- the accent under the mouse. SetSelected marks the chosen one of a row.
function UI.button(parent, label, width, onClick)
	local button = CreateFrame("Button", nil, parent)
	button:SetSize(width or 110, 26)
	UI.roundPanel(button, 0.95)
	local glow = UI.roundBorder(button, "CardEdge.tga", 1)
	local text = button:CreateFontString(nil, "OVERLAY")
	Stoa:SetFont(text, "sans", Stoa.typeSize.body)
	text:SetPoint("CENTER")
	text:SetText(label)
	button.text = text
	local function colour()
		local lit = button.selected or button:IsMouseOver()
		text:SetTextColor(Stoa:Color(lit and "accent" or "text"))
		if lit then glow:Set(Stoa:Color("accent")) else glow:Clear() end
	end
	function button:SetSelected(selected)
		self.selected = selected and true or false
		colour()
	end
	button:SetScript("OnEnter", colour)
	button:SetScript("OnLeave", colour)
	if onClick then button:SetScript("OnClick", onClick) end
	Stoa:On("STOA_THEME_CHANGED", colour)
	colour()
	return button
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

-- A plaque: the tank watch and the target, dressed as small pieces of the
-- console so they read as yours rather than as party cards. Warm leather,
-- a gold hairline with a fainter one inside, a soft emboss, and a portrait
-- coin on the side that faces the Halo.
local PLAQUE_FILL = { 0.11, 0.096, 0.083, 0.95 }
local SILVER = { 0.79, 0.8, 0.82 }
local COIN = 52
local PLAQUE_INLAY = 4

function UI.plaque(frame, coinSide)
	local plaque = {}
	local fill = sliced(frame, "BACKGROUND", "CardFill.tga")
	if fill then
		fill:SetVertexColor(unpack(PLAQUE_FILL))
	else
		fill = frame:CreateTexture(nil, "BACKGROUND")
		fill:SetAllPoints()
		fill:SetColorTexture(unpack(PLAQUE_FILL))
	end
	-- Painted: the console's leather inlaid in the card, a few points in
	-- from the rounded edge, at the console's grain size.
	if UI.ornate() then
		local leather = frame:CreateTexture(nil, "BACKGROUND", nil, 1)
		leather:SetTexture(UI.MEDIA .. "Textures\\ConsoleLeather", "REPEAT", "REPEAT")
		leather:SetPoint("TOPLEFT", PLAQUE_INLAY, -PLAQUE_INLAY)
		leather:SetPoint("BOTTOMRIGHT", -PLAQUE_INLAY, PLAQUE_INLAY)
		leather:SetAlpha(0.8)
		local function tile()
			local width, height = leather:GetWidth(), leather:GetHeight()
			if not width or width <= 0 then return end
			local scale = Stoa.modules.Grimoire and Stoa.modules.Grimoire.ART_SCALE or 0.556
			leather:SetTexCoord(0, width / scale / 1024, 0, height / scale / 256)
		end
		tile()
		frame:HookScript("OnSizeChanged", tile)
	end

	-- The emboss: light catching the top edge, shadow under the bottom.
	local light = frame:CreateTexture(nil, "BORDER")
	light:SetColorTexture(1, 0.94, 0.82, 0.06)
	light:SetHeight(1)
	light:SetPoint("TOPLEFT", 10, -1)
	light:SetPoint("TOPRIGHT", -10, -1)
	local shade = frame:CreateTexture(nil, "BORDER")
	shade:SetColorTexture(0, 0, 0, 0.5)
	shade:SetHeight(1)
	shade:SetPoint("BOTTOMLEFT", 10, 1)
	shade:SetPoint("BOTTOMRIGHT", -10, 1)

	local outer = sliced(frame, "BORDER", "CardEdge.tga")
	local inner = sliced(frame, "BORDER", "CardEdge.tga", -5)
	plaque.lines = { outer, inner }

	-- The coin straddles the edge that faces the Halo.
	local coin = CreateFrame("Frame", nil, frame)
	coin:SetSize(COIN, COIN)
	coin:SetPoint("CENTER", frame, coinSide, coinSide == "LEFT" and 1 or -1, 0)
	coin:SetFrameLevel(frame:GetFrameLevel() + 3)
	local gap = UI.circle(coin, "BACKGROUND", 0, COIN)
	gap:SetPoint("CENTER")
	gap:SetColorTexture(unpack(PLAQUE_FILL))
	local ring = UI.circle(coin, "BORDER", 0, COIN - 6)
	ring:SetPoint("CENTER")
	ring:SetColorTexture(1, 1, 1)
	local portrait = UI.circle(coin, "ARTWORK", 0, COIN - 10)
	portrait:SetPoint("CENTER")
	plaque.coin, plaque.ring, plaque.portrait = coin, ring, portrait
	-- Painted: the brass ring stands in for the plain one and carries the rank.
	local brass
	if UI.ornate() then
		ring:Hide()
		local _
		_, brass = UI.coinFrame(coin, COIN - 10)
	end

	-- Gold for everyone; elite doubles the gold, rare turns it silver.
	function plaque:SetRank(rank)
		plaque.rank = rank
		local r, g, b = Stoa:Color("accent")
		if rank == "rare" then r, g, b = unpack(SILVER) end
		local strong = rank == "elite" or rank == "rare"
		if outer then outer:SetVertexColor(r, g, b, strong and 1 or 0.55) end
		if inner then inner:SetVertexColor(r, g, b, strong and 0.7 or 0.16) end
		ring:SetVertexColor(r, g, b, 1)
		if brass then brass:SetVertexColor(r, g, b, 1) end
	end
	plaque:SetRank(nil)
	-- The rank colours follow the theme's accent, so repaint on a change.
	Stoa:On("STOA_THEME_CHANGED", function() plaque:SetRank(plaque.rank) end)
	return plaque
end

-- Health as a whole percent. Combat health can be secret: newer clients
-- hand out a percent that is safe to show; failing that, the plain health.
function UI.setHealthPercent(fs, unit, fraction)
	if not fraction then
		local health, max = UnitHealth(unit), UnitHealthMax(unit)
		if not Stoa:IsSecret(health) and not Stoa:IsSecret(max) and max and max > 0 then
			fraction = health / max
		end
	end
	if fraction then
		fs:SetText(math.floor(fraction * 100 + 0.5))
		return
	end
	if UnitHealthPercent and CurveConstants and CurveConstants.ScaleTo100 then
		local ok = pcall(function()
			fs:SetFormattedText("%d", UnitHealthPercent(unit, true, CurveConstants.ScaleTo100))
		end)
		if ok then return end
	end
	fs:SetText(UnitHealth(unit))
end

-- Fine engraved ticks at a quarter, half and three quarters of a bar.
function UI.engrave(bar, width)
	for _, at in ipairs({ 0.25, 0.5, 0.75 }) do
		local tick = bar:CreateTexture(nil, "OVERLAY", nil, 7)
		tick:SetColorTexture(0.07, 0.08, 0.09, 0.85)
		tick:SetWidth(1)
		tick:SetPoint("TOP", bar, "TOPLEFT", width * at, 0)
		tick:SetPoint("BOTTOM", bar, "BOTTOMLEFT", width * at, 0)
	end
end

-- Lays out a card's insides for a style. Out of combat for party cards,
-- since the sizes follow the role.
function UI.styleCard(card, styleName)
	local style = UI.CARD_STYLES[styleName] or UI.CARD_STYLES.party
	card.style = style
	local pad = style.pad
	if style.cell then
		Stoa:SetFont(card.name, "sans", style.name, "")
		card.name:ClearAllPoints()
		card.name:SetPoint("LEFT", pad, 0)
		card.name:SetPoint("RIGHT", card.percent, "LEFT", -3, 0)
		Stoa:SetFont(card.percent, "sans", style.name - 1, "")
		card.percent:ClearAllPoints()
		card.percent:SetPoint("RIGHT", -pad, 0)
		-- Dimmed, so the name stays readable over a full bar.
		card.hp:ClearAllPoints()
		card.hp:SetPoint("TOPLEFT", 2, -2)
		card.hp:SetPoint("BOTTOMRIGHT", -2, 2)
		card.hp:SetAlpha(0.4)
		card.hp.track:Hide()
		card.absorb:SetWidth(math.max(1, (card:GetWidth() or 90) - 4))
		for _, pip in ipairs(card.pips) do pip:Hide() end
		return
	end
	card.hp:SetAlpha(1)
	card.hp.track:Show()

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

-- A compact cell has no pip row: the most urgent word takes the percent's
-- place, in its colour. Returns true when it did.
local CELL_WORDS = {
	MAGIC = "MAG", DISEASE = "DIS", CURSE = "CUR", POISON = "POI", DISPEL = "DSP",
	LOW = "LOW", DEAD = "DEAD", OFFLINE = "OFF",
	READY = "RDY", ["NOT READY"] = "NOT", WAITING = "...",
}
function UI.cellWord(card, word, token)
	if not (card.style and card.style.cell) then return false end
	for _, pip in ipairs(card.pips) do pip:Hide() end
	if not word then return false end
	card.percent:SetText(CELL_WORDS[word] or word)
	card.percent:SetTextColor(Stoa:Color(token or "muted"))
	return true
end

-- Fills the pip row. Each pip is { text, fill } where fill is a theme token
-- for a solid chip (dark text on it), or nil for a quiet chip.
function UI.setPips(card, list)
	if card.style and card.style.cell then return end
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
