-- Stoa: design tokens. Every colour, font and spacing value in the suite comes
-- from here, so a theme swap restyles everything at once.
--
-- Every state carries a label or shape, never red against green alone, and
-- the palettes are tuned for red-green colour blindness: states differ in
-- lightness, and where a class's own colour sits near the warning amber
-- (Druid orange, Rogue yellow, Hunter green), the warning moves well away
-- from it. Other kinds of colour blindness are served by the colour vision
-- swaps further down.
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

	-- Class themes: the class colour as the accent, the panel and words
	-- tinted toward it. "Class" in the theme list follows whoever you log in.
	Warrior = {
		text    = rgb("EEE6D8"),
		muted   = rgb("A89E90"),
		panel   = rgb("14110E", 0.92),
		hairline = rgb("EEE6D8", 0.22),
		health  = rgb("E2D7C4"),
		mana    = rgb("6F9BFF"),
		danger  = rgb("FF7A45"),
		shield  = rgb("E6C9A0", 0.9),
		accent  = rgb("C9A47C"),
		magic   = rgb("6F9BFF"),
		disease = rgb("C9A0FF"),
		classTint = true,
	},
	Paladin = {
		text    = rgb("F2E9EE"),
		muted   = rgb("AC9EA6"),
		panel   = rgb("151014", 0.92),
		hairline = rgb("F2E9EE", 0.22),
		health  = rgb("EADFE3"),
		mana    = rgb("6F9BFF"),
		danger  = rgb("F0A04B"),
		shield  = rgb("F7C6DC", 0.9),
		accent  = rgb("F4A3C8"),
		magic   = rgb("6F9BFF"),
		disease = rgb("C9A0FF"),
		classTint = true,
	},
	Hunter = {
		text    = rgb("E9EDE0"),
		muted   = rgb("9EA592"),
		panel   = rgb("10130E", 0.92),
		hairline = rgb("E9EDE0", 0.22),
		health  = rgb("DDE3CF"),
		mana    = rgb("6F9BFF"),
		danger  = rgb("FFD08A"),
		shield  = rgb("C9DFA5", 0.9),
		accent  = rgb("93B85E"),
		magic   = rgb("6F9BFF"),
		disease = rgb("C9A0FF"),
		classTint = true,
	},
	Rogue = {
		text    = rgb("EFEDDD"),
		muted   = rgb("A6A390"),
		panel   = rgb("12120D", 0.92),
		hairline = rgb("EFEDDD", 0.22),
		health  = rgb("E4E0C8"),
		mana    = rgb("6F9BFF"),
		danger  = rgb("E8743A"),
		shield  = rgb("FFF3A8", 0.9),
		accent  = rgb("F2E06B"),
		magic   = rgb("6F9BFF"),
		disease = rgb("C9A0FF"),
		classTint = true,
	},
	Priest = {
		text    = rgb("F4F3F7"),
		muted   = rgb("A7A5B0"),
		panel   = rgb("121216", 0.92),
		hairline = rgb("F4F3F7", 0.24),
		health  = rgb("E6E4EC"),
		mana    = rgb("6F9BFF"),
		danger  = rgb("F0A04B"),
		shield  = rgb("FFFFFF", 0.85),
		accent  = rgb("D2CCF2"),
		magic   = rgb("6F9BFF"),
		disease = rgb("E8C27A"),
		classTint = true,
	},
	Shaman = {
		text    = rgb("E2EAF4"),
		muted   = rgb("95A4B8"),
		panel   = rgb("0C1220", 0.92),
		hairline = rgb("E2EAF4", 0.22),
		health  = rgb("D7E0EC"),
		mana    = rgb("5ED3E6"),
		danger  = rgb("F0A04B"),
		shield  = rgb("A8C8FF", 0.9),
		accent  = rgb("4C94FF"),
		magic   = rgb("5ED3E6"),
		disease = rgb("C9A0FF"),
		classTint = true,
	},
	Mage = {
		text    = rgb("E4F0F6"),
		muted   = rgb("96A9B4"),
		panel   = rgb("0C141A", 0.92),
		hairline = rgb("E4F0F6", 0.22),
		health  = rgb("D9E6EE"),
		mana    = rgb("5B7CFF"),
		danger  = rgb("F0A04B"),
		shield  = rgb("C4ECFF", 0.9),
		accent  = rgb("7FD3F4"),
		magic   = rgb("5B7CFF"),
		disease = rgb("C9A0FF"),
		classTint = true,
	},
	Warlock = {
		text    = rgb("ECE8F4"),
		muted   = rgb("A49DB4"),
		panel   = rgb("110E17", 0.92),
		hairline = rgb("ECE8F4", 0.22),
		health  = rgb("E1DCEC"),
		mana    = rgb("6F9BFF"),
		danger  = rgb("F0A04B"),
		shield  = rgb("D2C6F5", 0.9),
		accent  = rgb("A894E6"),
		magic   = rgb("6F9BFF"),
		disease = rgb("E8C27A"),
		classTint = true,
	},
	Druid = {
		text    = rgb("F1E9DF"),
		muted   = rgb("AA9E90"),
		panel   = rgb("15100C", 0.92),
		hairline = rgb("F1E9DF", 0.22),
		health  = rgb("E6DCCB"),
		mana    = rgb("6F9BFF"),
		danger  = rgb("FFF4E8"),
		shield  = rgb("FFD3A6", 0.9),
		accent  = rgb("F28A3A"),
		magic   = rgb("6F9BFF"),
		disease = rgb("C9A0FF"),
		classTint = true,
	},
}

Stoa.themeOrder = {
	"Bone", "Tide", "Graphite", "Class",
	"Druid", "Hunter", "Mage", "Paladin", "Priest", "Rogue", "Shaman", "Warlock", "Warrior",
}

-- "Class" follows the character: each class file name to its theme.
local CLASS_THEMES = {
	WARRIOR = "Warrior", PALADIN = "Paladin", HUNTER = "Hunter", ROGUE = "Rogue", PRIEST = "Priest",
	SHAMAN = "Shaman", MAGE = "Mage", WARLOCK = "Warlock", DRUID = "Druid",
}

-- Spacing scale in pixels (4 px grid) and type sizes.
Stoa.space = { xs = 4, s = 8, m = 12, l = 16, xl = 24, xxl = 36 }
Stoa.typeSize = { caption = 11, body = 12, label = 14, title = 20, display = 28, hero = 38 }

-- Fonts. Bundled files go in Media\Fonts. Each kind tries its candidates in
-- order, so a display face dropped in wins over the older one, and the game's
-- own fonts always catch the rest. Scale evens out faces that run small.
local MEDIA = "Interface\\AddOns\\Stoa\\Media\\Fonts\\"
local DISPLAY = { MEDIA .. "TenorSans-Regular.ttf", 1 }
local CORMORANT_SCALE = 1.2
Stoa.fonts = {
	serif = { DISPLAY, { MEDIA .. "CormorantGaramond-SemiBold.ttf", CORMORANT_SCALE }, { "Fonts\\FRIZQT__.TTF", 1 } },
	-- Tenor Sans has no italic, so the upright stands in for it.
	italic = { DISPLAY, { MEDIA .. "CormorantGaramond-SemiBoldItalic.ttf", CORMORANT_SCALE }, { "Fonts\\FRIZQT__.TTF", 1 } },
	sans = { { MEDIA .. "Inter-SemiBold.ttf", 1 }, { STANDARD_TEXT_FONT, 1 } },
}

-- SetFont raises an error for a missing file, so each candidate is tried in a
-- pcall and the first one that loads wins.
function Stoa:SetFont(fontString, kind, size, flags)
	for _, candidate in ipairs(self.fonts[kind] or self.fonts.sans) do
		local path, scale = candidate[1], candidate[2]
		local ok, loaded = pcall(fontString.SetFont, fontString, path, size * scale, flags or "")
		if ok and loaded ~= false then
			return
		end
	end
	fontString:SetFontObject(GameFontNormal)
end

-- Theme access --------------------------------------------------------------

-- The theme in use, with "Class" resolved to this character's class.
function Stoa:ThemeName()
	local name = self.db and self.db.theme or "Bone"
	if name == "Class" then
		local _, classFile = UnitClass("player")
		name = CLASS_THEMES[classFile] or "Bone"
	end
	return self.themes[name] and name or "Bone"
end

-- Colour vision ------------------------------------------------------------
-- Every theme already pairs each state with a word or a shape. On top of
-- that, a colour vision setting swaps only the state colours (warnings,
-- the accent, mana, dispel types, shields and health) for a set chosen for
-- that kind of colour blindness, leaving the theme's panels and words as
-- they are. Class colours on names are turned off in these modes, since
-- nine classes can't all stay apart for every eye.
--   Red-green (protan, deutan): blue against orange and yellow (Okabe-Ito).
--   Blue-yellow (tritan): red against teal, with pink and white.
--   No colour (achromat): states differ by lightness alone.
Stoa.visions = {
	RedGreen = {
		accent  = rgb("F0E442"),
		danger  = rgb("E69F00"),
		mana    = rgb("56B4E9"),
		magic   = rgb("56B4E9"),
		disease = rgb("F5F0E6"),
		shield  = rgb("F0E442", 0.85),
		health  = rgb("E8E2D6"),
	},
	BlueYellow = {
		accent  = rgb("F7C6D9"),
		danger  = rgb("FF5A4E"),
		mana    = rgb("3FD0E0"),
		magic   = rgb("3FD0E0"),
		disease = rgb("FF9EC4"),
		shield  = rgb("FFFFFF", 0.85),
		health  = rgb("E8E2D6"),
	},
	NoColour = {
		text    = rgb("EDEDED"),
		muted   = rgb("9A9A9A"),
		accent  = rgb("FFFFFF"),
		danger  = rgb("FFFFFF"),
		mana    = rgb("7C7C7C"),
		magic   = rgb("C4C4C4"),
		disease = rgb("6A6A6A"),
		shield  = rgb("FFFFFF", 0.9),
		health  = rgb("D2D2D2"),
	},
}
Stoa.visionOrder = { "Standard", "RedGreen", "BlueYellow", "NoColour" }
Stoa.VISION_LABELS = {
	Standard = "Standard",
	RedGreen = "Red-green (protan, deutan)",
	BlueYellow = "Blue-yellow (tritan)",
	NoColour = "No colour (lightness only)",
}

local blended = {}

-- The theme in use, with the colour vision swaps laid over it.
function Stoa:Theme()
	local name = self:ThemeName()
	local vision = self.db and self.db.vision
	local swaps = vision and self.visions[vision]
	if not swaps then return self.themes[name] end
	local key = name .. ":" .. vision
	if not blended[key] then
		local theme = {}
		for token, value in pairs(self.themes[name]) do theme[token] = value end
		for token, value in pairs(swaps) do theme[token] = value end
		theme.classTint = false
		blended[key] = theme
	end
	return blended[key]
end

function Stoa:SetVision(name)
	if name ~= "Standard" and not self.visions[name] then return end
	self.db.vision = name
	self:Fire("STOA_THEME_CHANGED", self.db.theme)
end

function Stoa:Color(token)
	return unpack(self:Theme()[token])
end

function Stoa:SetTheme(name)
	if not self.themes[name] and name ~= "Class" then return end
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

-- /stoa vision cycles the colour vision modes; /stoa vision redgreen etc.
Stoa.commands.vision = function(rest)
	local wanted = rest and rest:lower():gsub("[%s%-]", "")
	local pick
	for _, name in ipairs(Stoa.visionOrder) do
		if wanted ~= "" and name:lower() == wanted then pick = name end
	end
	if not pick then
		local current = Stoa.db.vision or "Standard"
		for i, name in ipairs(Stoa.visionOrder) do
			if name == current then pick = Stoa.visionOrder[i % #Stoa.visionOrder + 1] end
		end
	end
	Stoa:SetVision(pick or "Standard")
	Stoa:Print("Colour vision:", Stoa.VISION_LABELS[Stoa.db.vision])
end

