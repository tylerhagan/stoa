-- Stoa: design tokens. Every colour, font and spacing value in the suite comes
-- from here, so a theme swap restyles everything at once.
--
-- All three themes are colour-blind safe: states differ in lightness and always
-- carry a label or shape, never red against green alone.
local _, ns = ...
local Stoa = ns.Stoa

local function rgb(hex, alpha)
	local r = tonumber(hex:sub(1, 2), 16) / 255
	local g = tonumber(hex:sub(3, 4), 16) / 255
	local b = tonumber(hex:sub(5, 6), 16) / 255
	return { r, g, b, alpha or 1 }
end

Stoa.themes = {
	Bone = {
		text    = rgb("ECE6DA"),
		muted   = rgb("A39E94"),
		panel   = rgb("111113", 0.92),
		hairline = rgb("ECE6DA", 0.22),
		health  = rgb("E4DCCB"),
		mana    = rgb("6F9BFF"),
		danger  = rgb("F0A04B"),
		shield  = rgb("F2D58A", 0.9),
		accent  = rgb("F2D58A"),
		magic   = rgb("6F9BFF"),
		disease = rgb("C9A0FF"),
		classTint = true,
	},
	Tide = {
		text    = rgb("DCE6F2"),
		muted   = rgb("93A7BE"),
		panel   = rgb("0D131A", 0.92),
		hairline = rgb("DCE6F2", 0.2),
		health  = rgb("7FA6D6"),
		mana    = rgb("3F6FD8"),
		danger  = rgb("FFFFFF"),
		shield  = rgb("D6E8FF", 0.85),
		accent  = rgb("A9CBFF"),
		magic   = rgb("A9CBFF"),
		disease = rgb("DCE6F2"),
		classTint = false,
	},
	Graphite = {
		text    = rgb("EDEDED"),
		muted   = rgb("A3A3A3"),
		panel   = rgb("111111", 0.92),
		hairline = rgb("EDEDED", 0.2),
		health  = rgb("D4D4D4"),
		mana    = rgb("8A8A8A"),
		danger  = rgb("F2A541"),
		shield  = rgb("FFFFFF", 0.75),
		accent  = rgb("F2A541"),
		magic   = rgb("F2A541"),
		disease = rgb("EDEDED"),
		classTint = false,
	},
}

Stoa.themeOrder = { "Bone", "Tide", "Graphite" }

-- Spacing scale in pixels (4 px grid) and type sizes.
Stoa.space = { xs = 4, s = 8, m = 12, l = 16, xl = 24, xxl = 36 }
Stoa.typeSize = { caption = 10, body = 12, label = 14, title = 20, display = 28, hero = 38 }

-- Fonts. Bundled files go in Media\Fonts; until they are added, Stoa falls back
-- to the game's own fonts so nothing breaks.
local MEDIA = "Interface\\AddOns\\Stoa\\Media\\Fonts\\"
Stoa.fonts = {
	serif = { MEDIA .. "CormorantGaramond-SemiBold.ttf", "Fonts\\MORPHEUS.TTF" },
	italic = { MEDIA .. "CormorantGaramond-SemiBoldItalic.ttf", "Fonts\\MORPHEUS.TTF" },
	sans = { MEDIA .. "Inter-SemiBold.ttf", STANDARD_TEXT_FONT },
}

-- SetFont raises an error for a missing file, so each candidate is tried in a
-- pcall and the first one that loads wins.
function Stoa:SetFont(fontString, kind, size, flags)
	for _, path in ipairs(self.fonts[kind] or self.fonts.sans) do
		local ok, loaded = pcall(fontString.SetFont, fontString, path, size, flags or "")
		if ok and loaded ~= false then
			return
		end
	end
	fontString:SetFontObject(GameFontNormal)
end

-- Theme access --------------------------------------------------------------

function Stoa:Theme()
	return self.themes[self.db and self.db.theme] or self.themes.Bone
end

function Stoa:Color(token)
	return unpack(self:Theme()[token])
end

function Stoa:SetTheme(name)
	if not self.themes[name] then return end
	self.db.theme = name
	self:Fire("STOA_THEME_CHANGED", name)
end

function Stoa:CycleTheme()
	local current = self.db.theme
	for i, name in ipairs(self.themeOrder) do
		if name == current then
			self:SetTheme(self.themeOrder[i % #self.themeOrder + 1])
			self:Print("Theme:", self.db.theme)
			return
		end
	end
	self:SetTheme("Bone")
end
