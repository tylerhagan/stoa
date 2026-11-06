-- Stoa: the gallery.
-- /stoa gallery opens one page showing every piece of the rulebook side by
-- side (Core/Widgets.lua "The rulebook"): the five surfaces, the edges, the
-- type scale (eight sizes), the spacing scale, every state word as a badge, buttons and
-- bars. Anything that drifts from the rest shows up here at a glance, so
-- check new work against it before it ships.
local _, ns = ...
local Stoa = ns.Stoa
local UI = Stoa.UI

local Gallery = {}
Stoa.Gallery = Gallery

local S = Stoa.space
local T = Stoa.typeSize
local WIDTH, HEIGHT = 980, 640
local HEADER, FOOTER = 76, 48
local COLUMN = 290

local function heading(parent, label, x, y)
	local fs = UI.caption(parent, label)
	fs:SetPoint("TOPLEFT", x, y)
	return fs
end

-- A small labelled sample: its name in muted caption under it.
local function label(parent, anchor, words)
	local fs = UI.text(parent, "sans", T.caption, "muted", "LEFT")
	fs:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -S.xs)
	fs:SetText(words)
	return fs
end

local function buildSurfaces(page, x, y)
	heading(page, "Surfaces", x, y)

	-- Panel: band, body with stone, tray.
	local panel = CreateFrame("Frame", nil, page)
	panel:SetSize(COLUMN - S.l, 132)
	panel:SetPoint("TOPLEFT", x, y - S.l - S.xs)
	panel:SetFrameLevel(page:GetFrameLevel() + 2)
	UI.band(panel, 34)
	UI.tray(panel, 26)
	UI.surface(panel, "panel")
	local title = UI.text(panel, "serif", T.title, "text")
	title:SetPoint("TOPLEFT", S.m, -S.s)
	title:SetText("Panel")
	local body = UI.text(panel, "sans", T.body, "muted", "LEFT")
	body:SetPoint("TOPLEFT", S.m, -34 - S.m)
	body:SetText("Band, body with stone, tray")
	label(page, panel, "panel  ·  band  ·  tray")

	-- Card with a bar on a well.
	local card = CreateFrame("Frame", nil, page)
	card:SetSize(COLUMN - S.l, 62)
	card:SetPoint("TOPLEFT", panel, "BOTTOMLEFT", 0, -S.xl)
	card:SetFrameLevel(page:GetFrameLevel() + 2)
	UI.surface(card, "card")
	local name = UI.text(card, "serif", T.label, "text")
	name:SetPoint("TOPLEFT", S.m, -S.m)
	name:SetText("Webwood Spider")
	local badge = UI.badge(card, "EVEN")
	badge:SetPoint("TOPRIGHT", -S.m, -S.m + 1)
	local bar = UI.bar(card, COLUMN - S.l - S.m * 2, 7, "health")
	bar:SetPoint("BOTTOMLEFT", S.m, S.m)
	bar:SetValue(0.62)
	bar.track:Hide()
	UI.surface(bar, "well", { outset = 2 })
	label(page, card, "card  ·  bar on a well  ·  badge")

	-- Inset ground inside a window.
	local inset = CreateFrame("Frame", nil, page)
	inset:SetSize(COLUMN - S.l - 12, 36)
	inset:SetPoint("TOPLEFT", card, "BOTTOMLEFT", 6, -S.xl - 6)
	UI.surface(inset, "inset", { outset = 6 })
	local words = UI.text(inset, "sans", T.body, "text", "LEFT")
	words:SetPoint("LEFT", S.s, 0)
	words:SetText("Inset: a group inside a window")
	label(page, inset, "inset")
end

local function buildType(page, x, y)
	heading(page, "Type", x, y)
	local rows = {
		{ "hero", "serif" }, { "display", "serif" }, { "title", "serif" },
		{ "name", "serif" }, { "label", "sans" }, { "body", "sans" },
		{ "caption", "sans" }, { "micro", "sans" },
	}
	local last
	for _, row in ipairs(rows) do
		local key, kind = row[1], row[2]
		local fs = UI.text(page, kind, T[key], "text", "LEFT")
		if last then
			fs:SetPoint("TOPLEFT", last, "BOTTOMLEFT", 0, -S.s)
		else
			fs:SetPoint("TOPLEFT", x, y - S.l - S.xs)
		end
		fs:SetText(key == "hero" and "STOA" or (key:sub(1, 1):upper() .. key:sub(2)))
		local size = UI.text(page, "sans", T.caption, "muted", "LEFT")
		size:SetPoint("BOTTOMLEFT", fs, "BOTTOMRIGHT", S.s, 2)
		size:SetText(T[key] .. "  " .. (kind == "serif" and "Tenor Sans" or "Inter"))
		last = fs
	end

	local spaceHead = UI.caption(page, "Spacing")
	spaceHead:SetPoint("TOPLEFT", last, "BOTTOMLEFT", 0, -S.xl)
	local prev
	for _, key in ipairs({ "xs", "s", "m", "l", "xl", "xxl" }) do
		local box = page:CreateTexture(nil, "ARTWORK")
		box:SetSize(S[key], S[key])
		UI.paint(box, "accent", 0.7)
		if prev then
			box:SetPoint("BOTTOMLEFT", prev, "BOTTOMRIGHT", S.l, 0)
		else
			box:SetPoint("TOPLEFT", spaceHead, "BOTTOMLEFT", 0, -S.s - S.xxl + S.xs)
		end
		local fs = UI.text(page, "sans", T.caption, "muted", "LEFT")
		fs:SetPoint("TOP", box, "BOTTOM", 0, -S.xs)
		fs:SetText(S[key])
		prev = box
	end
	UI.applyTheme()
end

local function buildStates(page, x, y)
	heading(page, "State words", x, y)
	-- Grouped by colour so a word in the wrong group stands out.
	local groups = {}
	for word, token in pairs(Stoa.states) do
		groups[token] = groups[token] or {}
		table.insert(groups[token], word)
	end
	local order = { "muted", "text", "accent", "danger", "mana" }
	local rowY = y - S.l - S.xs
	for _, token in ipairs(order) do
		local words = groups[token]
		if words then
			table.sort(words)
			local tag = UI.text(page, "sans", T.caption, "muted", "LEFT")
			tag:SetPoint("TOPLEFT", x, rowY - 2)
			tag:SetText(token)
			local cx, line = x + 54, 0
			for _, word in ipairs(words) do
				local badge = UI.badge(page, word)
				local w = badge:GetWidth()
				if cx + w > x + COLUMN + 60 then
					cx, line = x + 54, line + 1
				end
				badge:SetPoint("TOPLEFT", cx, rowY - line * (UI.BADGE.height + S.xs))
				cx = cx + w + S.xs
			end
			rowY = rowY - (line + 1) * (UI.BADGE.height + S.xs) - S.s
		end
	end

	local edgeHead = UI.caption(page, "Edges")
	edgeHead:SetPoint("TOPLEFT", x, rowY - S.m)
	local edges = {
		{ "Normal", nil },
		{ "Elite", { Stoa:Color("accent") } },
		{ "Rare", { 0.78, 0.8, 0.84 } },
	}
	local prev
	for _, spec in ipairs(edges) do
		local card = CreateFrame("Frame", nil, page)
		card:SetSize(96, 40)
		if prev then
			card:SetPoint("TOPLEFT", prev, "TOPRIGHT", S.s, 0)
		else
			card:SetPoint("TOPLEFT", edgeHead, "BOTTOMLEFT", 0, -S.s)
		end
		card:SetFrameLevel(page:GetFrameLevel() + 2)
		UI.surface(card, "card")
		if spec[2] then
			local edge = UI.roundBorder(card, "CardEdge.tga", 1)
			edge:Set(spec[2][1], spec[2][2], spec[2][3], 0.9)
		end
		local fs = UI.text(card, "sans", T.body, "text")
		fs:SetPoint("CENTER")
		fs:SetText(spec[1])
		prev = card
	end

	local buttonHead = UI.caption(page, "Buttons and bars")
	buttonHead:SetPoint("TOPLEFT", edgeHead, "BOTTOMLEFT", 0, -40 - S.s * 2 - S.m)
	local plain = UI.button(page, "Button", 110)
	plain:SetPoint("TOPLEFT", buttonHead, "BOTTOMLEFT", 0, -S.s)
	local chosen = UI.button(page, "Chosen", 110)
	chosen:SetPoint("LEFT", plain, "RIGHT", S.s, 0)
	chosen:SetSelected(true)
	local bars = { { "health", 0.8 }, { "mana", 0.55 }, { "danger", 0.3 } }
	local above = plain
	for _, spec in ipairs(bars) do
		local bar = UI.bar(page, 228, 7, spec[1])
		bar:SetPoint("TOPLEFT", above, "BOTTOMLEFT", 2, above == plain and -S.m - 2 or -S.s - 4)
		bar:SetValue(spec[2])
		bar.track:Hide()
		UI.surface(bar, "well", { outset = 2 })
		local fs = UI.text(page, "sans", T.caption, "muted", "LEFT")
		fs:SetPoint("LEFT", bar, "RIGHT", S.s, 0)
		fs:SetText(spec[1])
		above = bar
	end
end

function Gallery:Build()
	local page = CreateFrame("Frame", "StoaGalleryPage", UIParent)
	page:SetSize(WIDTH, HEIGHT)
	page:SetPoint("CENTER")
	page:SetFrameStrata("DIALOG")
	page:EnableMouse(true)
	page:SetMovable(true)
	page:RegisterForDrag("LeftButton")
	page:SetScript("OnDragStart", page.StartMoving)
	page:SetScript("OnDragStop", page.StopMovingOrSizing)
	page:Hide()
	table.insert(UISpecialFrames, "StoaGalleryPage")
	UI.windowPanel(page, 0.97, { header = HEADER, footer = FOOTER })
	self.page = page

	local title = UI.text(page, "serif", T.display, "text")
	title:SetPoint("TOPLEFT", S.xl, -S.l)
	title:SetText("Gallery")
	local lede = UI.text(page, "sans", T.body, "muted", "LEFT")
	lede:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -S.xs)
	lede:SetText("Every surface, edge, size and state word in the rulebook, side by side.")

	local top = -HEADER - S.l
	buildSurfaces(page, S.xl, top)
	buildType(page, S.xl + COLUMN + S.xl, top)
	buildStates(page, S.xl + (COLUMN + S.xl) * 2 - 40, top)

	local theme = UI.text(page, "sans", T.caption, "muted", "LEFT")
	theme:SetPoint("BOTTOMLEFT", S.xl, (FOOTER - T.caption) / 2)
	self.theme = theme
	local close = UI.button(page, "Close", 80, function() page:Hide() end)
	close:SetPoint("BOTTOMRIGHT", -S.l, (FOOTER - 26) / 2)
	page:SetScript("OnShow", function()
		theme:SetText("Theme: " .. tostring(Stoa.ThemeName and Stoa:ThemeName() or Stoa.db.theme))
	end)
	UI.applyTheme()
end

function Gallery:Show()
	if InCombatLockdown() then
		Stoa:Print("The gallery opens out of combat.")
		return
	end
	if not self.page then self:Build() end
	self.page:SetShown(not self.page:IsShown())
end

Stoa.commands.gallery = function() Gallery:Show() end
