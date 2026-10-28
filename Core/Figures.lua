-- Stoa: small figures. Numbers drawn as shapes instead of sentences, from
-- plain textures and lines, so they need no art and take the theme.
--   segments: a row of cells lit out of a count (gear wear on Ready);
--   columns: one upright bar per bag, filling as it fills;
--   bar: a slim bar for one share (a line in At a glance);
--   spark: a small line chart of recent values, with a dot on the last;
--   xp: the experience bar with rest behind it and a mark for where an hour
--       at your pace would take you.
-- Each returns a frame with :Set(...). Colours that change with the value
-- (worn, full) are set in Set; the rest follow the theme.
local _, ns = ...
local Stoa = ns.Stoa
local UI = Stoa.UI

local Figures = {}
Stoa.Figures = Figures

local WHITE = "Interface\\Buttons\\WHITE8x8"

local function fill(parent, layer, token, alpha)
	local tex = parent:CreateTexture(nil, layer or "ARTWORK")
	tex:SetTexture(WHITE)
	if token then UI.tint(tex, token, alpha) end
	return tex
end

local function color(tex, token, alpha)
	local r, g, b = Stoa:Color(token)
	tex:SetVertexColor(r, g, b, alpha or 1)
end

-- The warning colour below a quarter, the accent below a half, else text.
function Figures.wear(fraction)
	if fraction < 0.25 then return "danger" end
	if fraction < 0.5 then return "accent" end
	return "text"
end

-- Segments ------------------------------------------------------------------------

function Figures.segments(parent, count, width, height, gap)
	gap = gap or 2
	local frame = CreateFrame("Frame", nil, parent)
	frame:SetSize(width, height)
	local cell = (width - gap * (count - 1)) / count
	frame.cells = {}
	for i = 1, count do
		local tex = fill(frame)
		tex:SetSize(cell, height)
		tex:SetPoint("LEFT", frame, "LEFT", (i - 1) * (cell + gap), 0)
		frame.cells[i] = tex
	end
	-- fraction 0..1; token for the lit cells (defaults to the wear colour).
	function frame:Set(fraction, token)
		fraction = math.max(0, math.min(1, fraction or 0))
		local lit = math.floor(fraction * count + 0.5)
		if fraction > 0 and lit == 0 then lit = 1 end
		token = token or Figures.wear(fraction)
		for i, tex in ipairs(self.cells) do
			if i <= lit then color(tex, token) else color(tex, "text", 0.13) end
		end
	end
	return frame
end

-- Columns -------------------------------------------------------------------------

function Figures.columns(parent, count, columnWidth, height, gap)
	gap = gap or 3
	local frame = CreateFrame("Frame", nil, parent)
	frame:SetSize(count * columnWidth + (count - 1) * gap, height)
	frame.bars = {}
	for i = 1, count do
		local track = fill(frame, "BACKGROUND")
		track:SetSize(columnWidth, height)
		track:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", (i - 1) * (columnWidth + gap), 0)
		color(track, "text", 0.12)
		local used = fill(frame)
		used:SetWidth(columnWidth)
		used:SetPoint("BOTTOMLEFT", track, "BOTTOMLEFT")
		frame.bars[i] = { track = track, used = used }
	end
	frame.height = height
	-- list of { used share 0..1, full }; columns past the list are hidden.
	function frame:Set(list)
		for i, column in ipairs(self.bars) do
			local entry = list[i]
			column.track:SetShown(entry ~= nil)
			column.used:SetShown(entry ~= nil and entry[1] > 0)
			if entry then
				column.used:SetHeight(math.max(1, self.height * math.min(1, entry[1])))
				if entry[2] then color(column.used, "danger") else color(column.used, "text", 0.6) end
			end
		end
	end
	return frame
end

-- Bar ---------------------------------------------------------------------------

function Figures.bar(parent, width, height)
	local frame = CreateFrame("Frame", nil, parent)
	frame:SetSize(width, height)
	local track = fill(frame, "BACKGROUND")
	track:SetAllPoints()
	color(track, "text", 0.14)
	local value = fill(frame)
	value:SetPoint("TOPLEFT")
	value:SetPoint("BOTTOMLEFT")
	frame.track, frame.value = track, value
	function frame:Set(fraction, token)
		fraction = math.max(0, math.min(1, fraction or 0))
		self.value:SetShown(fraction > 0)
		self.value:SetWidth(math.max(1, width * fraction))
		color(self.track, "text", 0.14)
		color(self.value, token or "text")
	end
	return frame
end

-- Spark -------------------------------------------------------------------------
-- Lines where the client draws them; otherwise a dot per value.

local SPARK_POINTS = 12

function Figures.spark(parent, width, height)
	local frame = CreateFrame("Frame", nil, parent)
	frame:SetSize(width, height)
	frame.lines, frame.dots = {}, {}
	local hasLines = type(frame.CreateLine) == "function"
	for i = 1, SPARK_POINTS do
		if hasLines and i > 1 then
			local segment = frame:CreateLine(nil, "ARTWORK")
			segment:SetTexture(WHITE)
			segment:SetThickness(1.5)
			frame.lines[i] = segment
		end
		local dot = fill(frame, "OVERLAY")
		dot:SetSize(hasLines and 4 or 2, hasLines and 4 or 2)
		frame.dots[i] = dot
	end
	local floor = fill(frame, "BACKGROUND")
	floor:SetPoint("BOTTOMLEFT")
	floor:SetPoint("BOTTOMRIGHT")
	floor:SetHeight(1)
	frame.floor = floor
	-- values: a list of numbers, oldest first; the last is marked.
	function frame:Set(values)
		local n = math.min(#values, SPARK_POINTS)
		local first = #values - n
		local low, high
		for i = first + 1, #values do
			local v = values[i]
			if not low or v < low then low = v end
			if not high or v > high then high = v end
		end
		color(self.floor, "text", 0.14)
		local span = (high and low and high > low) and (high - low) or 1
		local points = {}
		for i = 1, n do
			local v = values[first + i]
			local x = n > 1 and (i - 1) / (n - 1) * width or width
			local y = 2 + ((v - (low or 0)) / span) * (height - 4)
			if high == low then y = height / 2 end
			points[i] = { x, y }
		end
		for i = 1, SPARK_POINTS do
			local dot, segment, point = self.dots[i], self.lines[i], points[i]
			local last = i == n
			if point and (last or not hasLines) then
				dot:ClearAllPoints()
				dot:SetPoint("CENTER", self, "BOTTOMLEFT", point[1], point[2])
				color(dot, last and "accent" or "text", last and 1 or 0.7)
				dot:Show()
			else
				dot:Hide()
			end
			if segment then
				local before = points[i - 1]
				if point and before then
					segment:SetStartPoint("BOTTOMLEFT", self, before[1], before[2])
					segment:SetEndPoint("BOTTOMLEFT", self, point[1], point[2])
					color(segment, "text", 0.9)
					segment:Show()
				else
					segment:Hide()
				end
			end
		end
		self:SetShown(n >= 2)
	end
	return frame
end

-- Experience --------------------------------------------------------------------

function Figures.xp(parent, width, height)
	local frame = CreateFrame("Frame", nil, parent)
	frame:SetSize(width, height)
	local track = fill(frame, "BACKGROUND", "text", 0.12)
	track:SetAllPoints()
	local rested = fill(frame, "BORDER", "mana", 0.55)
	rested:SetPoint("TOPLEFT")
	rested:SetPoint("BOTTOMLEFT")
	local earned = fill(frame, "ARTWORK", "text")
	earned:SetPoint("TOPLEFT")
	earned:SetPoint("BOTTOMLEFT")
	local mark = fill(frame, "OVERLAY", "accent")
	mark:SetSize(2, height + 8)
	frame.rested, frame.earned, frame.mark = rested, earned, mark
	local function share(tex, fraction)
		fraction = math.max(0, math.min(1, fraction or 0))
		tex:SetShown(fraction > 0)
		tex:SetWidth(math.max(1, width * fraction))
	end
	-- Shares of the bar: earned, earned plus rest, and where an hour at
	-- your pace gets you (nil hides the mark).
	function frame:Set(earnedShare, restedShare, hourShare)
		share(self.earned, earnedShare)
		share(self.rested, restedShare)
		self.mark:SetShown(hourShare ~= nil)
		if hourShare then
			self.mark:ClearAllPoints()
			self.mark:SetPoint("CENTER", self, "LEFT", width * math.max(0, math.min(1, hourShare)), 0)
		end
	end
	return frame
end

-- A swatch and a word, for the experience bar's key.
function Figures.key(parent, token, alpha)
	local frame = CreateFrame("Frame", nil, parent)
	frame:SetSize(8, 10)
	local swatch = fill(frame, "ARTWORK", token, alpha)
	swatch:SetSize(8, 3)
	swatch:SetPoint("LEFT")
	local label = UI.text(frame, "sans", Stoa.typeSize.caption, "muted")
	label:SetPoint("LEFT", swatch, "RIGHT", 4, 0)
	frame.label = label
	function frame:SetText(words)
		self.label:SetText(words or "")
		self:SetWidth(12 + (self.label:GetStringWidth() or 0))
		self:SetShown(words ~= nil and words ~= "")
	end
	return frame
end
