-- Stoa: settings backup.
-- /stoa backup opens a page holding all of Stoa's settings (account-wide
-- and this character's) as one line of text. Copy it somewhere safe; paste
-- one back and import to restore, which reloads the UI.
--
-- The text is Stoa's own small format, read back by a parser that only
-- understands tables, strings, numbers and booleans, so a pasted line can
-- never run code.
local _, ns = ...
local Stoa = ns.Stoa
local UI = Stoa.UI

local Backup = {}
Stoa.Backup = Backup

local PREFIX = "STOA1:"
local MAX_DEPTH = 24

-- Writing ---------------------------------------------------------------------

local function quote(text)
	text = text:gsub("\\", "\\\\"):gsub("\"", "\\\""):gsub("\n", "\\n"):gsub("\r", "\\r")
	text = text:gsub("%c", function(c) return ("\\%03d"):format(c:byte()) end)
	return "\"" .. text .. "\""
end

local function write(value, out, depth)
	local kind = type(value)
	if kind == "string" then
		out[#out + 1] = quote(value)
	elseif kind == "number" then
		-- Infinity and NaN don't round-trip; settings never hold them.
		if value ~= value or value == math.huge or value == -math.huge then value = 0 end
		out[#out + 1] = ("%.17g"):format(value)
	elseif kind == "boolean" then
		out[#out + 1] = value and "true" or "false"
	elseif kind == "table" and depth < MAX_DEPTH then
		out[#out + 1] = "{"
		-- Sorted keys, so the same settings always give the same text.
		local keys = {}
		for key in pairs(value) do
			local keyKind = type(key)
			if keyKind == "string" or keyKind == "number" then keys[#keys + 1] = key end
		end
		table.sort(keys, function(a, b)
			if type(a) == type(b) then return a < b end
			return type(a) == "number"
		end)
		for _, key in ipairs(keys) do
			local item = value[key]
			local itemKind = type(item)
			if itemKind == "string" or itemKind == "number" or itemKind == "boolean" or itemKind == "table" then
				out[#out + 1] = "["
				write(key, out, depth + 1)
				out[#out + 1] = "]="
				write(item, out, depth + 1)
				out[#out + 1] = ","
			end
		end
		out[#out + 1] = "}"
	else
		out[#out + 1] = "false"
	end
end

function Backup:Export()
	local out = { PREFIX }
	write({ account = StoaDB, character = StoaCharDB }, out, 0)
	return table.concat(out)
end

-- Reading ---------------------------------------------------------------------

local ESCAPES = { n = "\n", r = "\r", ["\\"] = "\\", ["\""] = "\"" }

-- Returns the value read from text, or nil and why not.
local function parse(text)
	local pos = 1
	local function fail(why) error({ stoa = why }, 0) end
	local function space()
		pos = text:find("[^%s]", pos) or #text + 1
	end
	local value
	local function readString()
		pos = pos + 1
		local parts = {}
		while true do
			local c = text:sub(pos, pos)
			if c == "" then fail("a quote is never closed") end
			if c == "\"" then
				pos = pos + 1
				return table.concat(parts)
			elseif c == "\\" then
				local nextChar = text:sub(pos + 1, pos + 1)
				local digits = text:match("^%d%d%d", pos + 1)
				if ESCAPES[nextChar] then
					parts[#parts + 1] = ESCAPES[nextChar]
					pos = pos + 2
				elseif digits then
					parts[#parts + 1] = string.char(tonumber(digits) % 256)
					pos = pos + 4
				else
					fail("an unknown escape")
				end
			else
				parts[#parts + 1] = c
				pos = pos + 1
			end
		end
	end
	local function readTable(depth)
		if depth > MAX_DEPTH then fail("it nests too deeply") end
		pos = pos + 1
		local result = {}
		while true do
			space()
			local c = text:sub(pos, pos)
			if c == "}" then
				pos = pos + 1
				return result
			end
			if c ~= "[" then fail("a table entry is malformed") end
			pos = pos + 1
			space()
			local key = value(depth + 1)
			local keyKind = type(key)
			if keyKind ~= "string" and keyKind ~= "number" then fail("a key is not a name or number") end
			space()
			if text:sub(pos, pos + 1) ~= "]=" then fail("a table entry is malformed") end
			pos = pos + 2
			space()
			result[key] = value(depth + 1)
			space()
			if text:sub(pos, pos) == "," then pos = pos + 1 end
		end
	end
	value = function(depth)
		space()
		local c = text:sub(pos, pos)
		if c == "{" then return readTable(depth) end
		if c == "\"" then return readString() end
		if text:sub(pos, pos + 3) == "true" then
			pos = pos + 4
			return true
		end
		if text:sub(pos, pos + 4) == "false" then
			pos = pos + 5
			return false
		end
		local number = text:match("^-?%d+%.?%d*[eE]?[-+]?%d*", pos)
		if number and tonumber(number) then
			pos = pos + #number
			return tonumber(number)
		end
		fail("there's something it can't read")
	end
	local ok, result = pcall(function()
		local read = value(0)
		space()
		if pos <= #text then fail("there's extra text at the end") end
		return read
	end)
	if ok then return result end
	return nil, type(result) == "table" and result.stoa or "it can't be read"
end

-- Replaces the contents of a saved table, keeping the table itself (the
-- game saves the one it handed out at login).
local function replace(target, source)
	for key in pairs(target) do target[key] = nil end
	for key, item in pairs(source) do target[key] = item end
end

-- Checks a pasted line and, if it's good, restores it and reloads.
function Backup:Import(text)
	text = strtrim(text or "")
	if text:sub(1, #PREFIX) ~= PREFIX then
		return false, "That isn't a Stoa backup: it should start with " .. PREFIX
	end
	local data, why = parse(text:sub(#PREFIX + 1))
	if not data then return false, "That backup can't be read: " .. why .. "." end
	if type(data) ~= "table" or type(data.account) ~= "table" or type(data.character) ~= "table" then
		return false, "That backup is missing its settings."
	end
	replace(StoaDB, data.account)
	replace(StoaCharDB, data.character)
	ReloadUI()
	return true
end

-- Page ------------------------------------------------------------------------

local WIDTH, HEIGHT = 600, 380
local PAD = 28

function Backup:Build()
	local page = CreateFrame("Frame", "StoaBackupPage", UIParent)
	page:SetSize(WIDTH, HEIGHT)
	page:SetPoint("CENTER", 0, 60)
	page:SetFrameStrata("DIALOG")
	page:EnableMouse(true)
	page:SetMovable(true)
	page:RegisterForDrag("LeftButton")
	page:SetScript("OnDragStart", page.StartMoving)
	page:SetScript("OnDragStop", page.StopMovingOrSizing)
	page:Hide()
	table.insert(UISpecialFrames, "StoaBackupPage")
	UI.roundPanel(page, 0.97)
	self.page = page

	local title = UI.text(page, "serif", Stoa.typeSize.display, "text")
	title:SetPoint("TOPLEFT", PAD, -PAD)
	title:SetText("Backup")
	local lede = UI.text(page, "italic", Stoa.typeSize.label, "muted", "LEFT")
	lede:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -6)
	lede:SetPoint("RIGHT", page, "RIGHT", -PAD, 0)
	lede:SetText("All of Stoa's settings, account-wide and this character's. Copy it somewhere safe, or paste one in and import it.")

	-- The text sits in a scrolling box, since a backup is long.
	local holder = CreateFrame("Frame", nil, page)
	holder:SetPoint("TOPLEFT", PAD, -110)
	holder:SetPoint("BOTTOMRIGHT", -PAD, 76)
	local holderBg = holder:CreateTexture(nil, "BACKGROUND")
	holderBg:SetAllPoints()
	UI.paint(holderBg, "text", 0.06)
	local scroll = CreateFrame("ScrollFrame", nil, holder, "UIPanelScrollFrameTemplate")
	scroll:SetPoint("TOPLEFT", 8, -8)
	scroll:SetPoint("BOTTOMRIGHT", -28, 8)
	local box = CreateFrame("EditBox", nil, scroll)
	box:SetMultiLine(true)
	box:SetAutoFocus(false)
	box:SetWidth(WIDTH - PAD * 2 - 40)
	Stoa:SetFont(box, "sans", Stoa.typeSize.caption)
	box:SetTextColor(Stoa:Color("text"))
	box:SetScript("OnEscapePressed", function(edit) edit:ClearFocus() end)
	scroll:SetScrollChild(box)
	holder:EnableMouse(true)
	holder:SetScript("OnMouseDown", function() box:SetFocus() end)
	self.box = box

	local status = UI.text(page, "sans", Stoa.typeSize.body, "muted", "LEFT")
	status:SetPoint("BOTTOMLEFT", PAD, PAD + 34)
	status:SetPoint("RIGHT", page, "RIGHT", -PAD, 0)
	self.status = status

	local function say(text, token)
		status:SetText(text)
		status:SetTextColor(Stoa:Color(token or "muted"))
	end
	self.say = say

	local copy = UI.button(page, "Select all to copy", 150, function()
		box:SetText(self:Export())
		box:SetFocus()
		box:HighlightText()
		say("Selected. Press Ctrl+C to copy it.")
	end)
	copy:SetPoint("BOTTOMLEFT", PAD, PAD - 8)
	local clear = UI.button(page, "Clear to paste", 130, function()
		box:SetText("")
		box:SetFocus()
		say("Paste a backup with Ctrl+V, then import it.")
	end)
	clear:SetPoint("LEFT", copy, "RIGHT", 8, 0)
	local import = UI.button(page, "Import and reload", 150, function()
		if InCombatLockdown() then
			say("Import once combat ends.", "danger")
			return
		end
		local ok, why = self:Import(box:GetText())
		if not ok then say(why, "danger") end
	end)
	import:SetPoint("LEFT", clear, "RIGHT", 8, 0)
	local close = UI.button(page, "Close", 80, function() page:Hide() end)
	close:SetPoint("BOTTOMRIGHT", -PAD, PAD - 8)

	UI.applyTheme()
end

function Backup:Show()
	if not self.page then self:Build() end
	self.box:SetText(self:Export())
	self.box:SetCursorPosition(0)
	self.say("This is your current setup. Importing one replaces it and reloads.")
	self.page:Show()
end

Stoa.commands.backup = function() Backup:Show() end
