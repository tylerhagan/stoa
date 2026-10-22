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

-- A 2 px border drawn with four textures, for cues like a dispellable debuff.
-- Hidden until set.
function UI.border(frame, size)
	size = size or 2
	local edges = {}
	for _, side in ipairs({ "TOP", "BOTTOM", "LEFT", "RIGHT" }) do
		local tex = frame:CreateTexture(nil, "OVERLAY")
		tex:SetColorTexture(1, 1, 1)
		if side == "TOP" or side == "BOTTOM" then
			tex:SetPoint(side .. "LEFT")
			tex:SetPoint(side .. "RIGHT")
			tex:SetHeight(size)
		else
			tex:SetPoint("TOP" .. side)
			tex:SetPoint("BOTTOM" .. side)
			tex:SetWidth(size)
		end
		tex:Hide()
		edges[#edges + 1] = tex
	end
	return {
		Set = function(_, r, g, b)
			for _, tex in ipairs(edges) do
				tex:SetVertexColor(r, g, b)
				tex:Show()
			end
		end,
		Clear = function()
			for _, tex in ipairs(edges) do tex:Hide() end
		end,
	}
end

-- The healer details every unit card shares: a shield line under the health
-- bar and a dispel border. Cards made with this get them filled in by
-- Party:UpdateCard.
function UI.unitDetails(card)
	local absorb = UI.bar(card, 10, 2, "shield")
	absorb.track:Hide()
	absorb:SetPoint("TOPLEFT", card.hp, "BOTTOMLEFT", 0, -1)
	absorb:SetPoint("TOPRIGHT", card.hp, "BOTTOMRIGHT", 0, -1)
	absorb:SetValue(0)
	card.absorb = absorb
	card.dispel = UI.border(card)
end
