-- Stoa QoL: chat comforts, each its own setting.
--   Links: web addresses in chat become clickable. The game can't open a
--   browser, so a click shows the address in a small box, selected, ready
--   to copy.
--   Copy: a quiet "copy" mark on the chat (or Shift-click a chat tab) shows
--   the window's last 200 lines in the same kind of box.
--   History: the main chat window's last 100 lines are kept per character
--   and put back after a /reload or a new login, dimmed, above a faint
--   "earlier" line.
-- Nothing here changes how Blizzard's chat works: links go through a
-- registered link type, history is written with the window's own AddMessage.
local _, ns = ...
local Stoa = ns.Stoa
local UI = Stoa.UI

local Chat = Stoa:NewModule("Chat", {
	links = true,
	copy = true,
	history = true,
})

local COPY_LINES = 200
local HISTORY_LINES = 100
local LINE_LIMIT = 500
local URL_LIMIT = 200
local SHOWN_LIMIT = 60
local LINK_TYPE = "stoaurl"
local EARLIER = "- - -  earlier  - - -"

-- Web addresses -----------------------------------------------------------------

-- Endings that make a bare name an address ("wowhead.com"). Kept short on
-- purpose, so ordinary talk ("done.it") is left alone.
local ENDINGS = {
	com = true, net = true, org = true, io = true, gg = true, tv = true, uk = true,
	de = true, fr = true, eu = true, info = true, gl = true, ly = true, app = true,
	dev = true, xyz = true,
}

-- True when text, taken as one word, is a web address.
local function isAddress(text)
	local lower = text:lower()
	if lower:find("^https?://[%w]") or lower:find("^www%.[%w%-]+%.%a") then return true end
	local host = lower:match("^([%w][%w%-%.]*)")
	if not host then return false end
	local after = lower:sub(#host + 1, #host + 1)
	if after ~= "" and after ~= "/" and after ~= ":" and after ~= "?" and after ~= "#" then return false end
	local ending = host:match("%.(%a+)$")
	return ending ~= nil and ENDINGS[ending] == true and host:find("^[%w%-]+%.") ~= nil
end

local function hex(r, g, b)
	return ("|cff%02x%02x%02x"):format(r * 255, g * 255, b * 255)
end

local function makeLink(address, colour)
	local shown = address
	if #shown > SHOWN_LIMIT then shown = shown:sub(1, SHOWN_LIMIT - 1) .. "..." end
	return colour .. "|H" .. LINK_TYPE .. ":" .. address .. "|h[" .. shown .. "]|h|r"
end

-- One run of plain text with no escape codes in it.
local function linkWords(text, colour)
	return (text:gsub("[^%s]+", function(word)
		local lead, core, trail = word:match("^([%(%[<\"']*)(.-)([%.,;:!%?%)%]>\"']*)$")
		if not core or core == "" or #core > URL_LIMIT or not isAddress(core) then return nil end
		return lead .. makeLink(core, colour) .. trail
	end))
end

-- Wraps every web address in message in a Stoa link, leaving colour codes,
-- other links and textures exactly as they were. Returns the new text, or
-- the old text if nothing changed.
function Chat.linkify(message, colour)
	if type(message) ~= "string" or message == "" then return message end
	if not (message:find("http", 1, true) or message:find("www", 1, true) or message:find(".", 1, true)) then
		return message
	end
	colour = colour or hex(Stoa:Color("accent"))
	local out, pos, length = {}, 1, #message
	while pos <= length do
		local bar = message:find("|", pos, true)
		if not bar then
			out[#out + 1] = linkWords(message:sub(pos), colour)
			break
		end
		if bar > pos then out[#out + 1] = linkWords(message:sub(pos, bar - 1), colour) end
		local code = message:sub(bar + 1, bar + 1)
		local stop
		if code == "H" then
			-- A whole link: up to the second |h.
			local first = message:find("|h", bar + 2, true)
			local second = first and message:find("|h", first + 2, true)
			stop = second and second + 1 or length
		elseif code == "c" then
			stop = bar + 9
		elseif code == "T" then
			local close = message:find("|t", bar + 2, true)
			stop = close and close + 1 or length
		else
			stop = bar + 1
		end
		out[#out + 1] = message:sub(bar, math.min(stop, length))
		pos = stop + 1
	end
	return table.concat(out)
end

-- Plain text for the copy box: links become their words, colours go.
function Chat.plain(text)
	if type(text) ~= "string" then return "" end
	text = text:gsub("|H.-|h(.-)|h", "%1")
	text = text:gsub("|T.-|t", "")
	text = text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
	text = text:gsub("|K.-|k", "?")
	text = text:gsub("||", "|")
	return text
end

local FILTERED = {
	"CHAT_MSG_SAY", "CHAT_MSG_YELL", "CHAT_MSG_EMOTE", "CHAT_MSG_GUILD", "CHAT_MSG_OFFICER",
	"CHAT_MSG_PARTY", "CHAT_MSG_PARTY_LEADER", "CHAT_MSG_RAID", "CHAT_MSG_RAID_LEADER",
	"CHAT_MSG_RAID_WARNING", "CHAT_MSG_INSTANCE_CHAT", "CHAT_MSG_INSTANCE_CHAT_LEADER",
	"CHAT_MSG_WHISPER", "CHAT_MSG_WHISPER_INFORM", "CHAT_MSG_BN_WHISPER",
	"CHAT_MSG_BN_WHISPER_INFORM", "CHAT_MSG_CHANNEL", "CHAT_MSG_COMMUNITIES_CHANNEL",
}

local function chatFilter(_, _, message, ...)
	if not Chat.db.links or Stoa:IsSecret(message) or type(message) ~= "string" then return false end
	local linked = Chat.linkify(message)
	if linked == message then return false end
	return false, linked, ...
end

local function addFilter(event)
	if ChatFrameUtil and ChatFrameUtil.AddMessageEventFilter then
		ChatFrameUtil.AddMessageEventFilter(event, chatFilter)
	elseif ChatFrame_AddMessageEventFilter then
		ChatFrame_AddMessageEventFilter(event, chatFilter)
	end
end

-- The copy box -------------------------------------------------------------------
-- A Stoa page with a text box holding what to copy, selected. Typing in it
-- puts the text back, so a stray key can't change what you copy.

local pages = {}

local function buildPage(key, name, width, height)
	local PAD = 28
	local page = CreateFrame("Frame", name, UIParent)
	page:SetSize(width, height)
	page:SetPoint("CENTER", 0, 60)
	page:SetFrameStrata("DIALOG")
	page:EnableMouse(true)
	page:SetMovable(true)
	page:RegisterForDrag("LeftButton")
	page:SetScript("OnDragStart", page.StartMoving)
	page:SetScript("OnDragStop", page.StopMovingOrSizing)
	page:Hide()
	table.insert(UISpecialFrames, name)
	UI.windowPanel(page, 0.97, { header = 98, footer = 66 })

	local title = UI.text(page, "serif", Stoa.typeSize.display, "text")
	title:SetPoint("TOPLEFT", PAD, -PAD)
	page.title = title
	local lede = UI.text(page, "italic", Stoa.typeSize.label, "muted", "LEFT")
	lede:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -6)
	lede:SetPoint("RIGHT", page, "RIGHT", -PAD, 0)
	page.lede = lede

	local holder = CreateFrame("Frame", nil, page)
	holder:SetPoint("TOPLEFT", PAD, -110)
	holder:SetPoint("BOTTOMRIGHT", -PAD, 78)
	UI.well(holder, 0)
	local scroll = CreateFrame("ScrollFrame", nil, holder, "UIPanelScrollFrameTemplate")
	scroll:SetPoint("TOPLEFT", 8, -8)
	scroll:SetPoint("BOTTOMRIGHT", -28, 8)
	local box = CreateFrame("EditBox", nil, scroll)
	box:SetMultiLine(true)
	box:SetAutoFocus(false)
	box:SetWidth(width - PAD * 2 - 40)
	Stoa:SetFont(box, "sans", Stoa.typeSize.caption)
	box:SetTextColor(Stoa:Color("text"))
	box:SetScript("OnEscapePressed", function() page:Hide() end)
	box:SetScript("OnTextChanged", function(edit, byUser)
		if byUser and page.held and edit:GetText() ~= page.held then
			edit:SetText(page.held)
			edit:HighlightText()
		end
	end)
	scroll:SetScrollChild(box)
	holder:EnableMouse(true)
	holder:SetScript("OnMouseDown", function() box:SetFocus() end)
	page.box = box

	local close = UI.button(page, "Close", 80, function() page:Hide() end)
	close:SetPoint("BOTTOMRIGHT", -PAD, PAD - 8)
	local hint = UI.text(page, "sans", Stoa.typeSize.body, "muted", "LEFT")
	hint:SetPoint("BOTTOMLEFT", PAD, PAD - 4)
	hint:SetText("Press Ctrl+C to copy. Escape closes this.")
	UI.applyTheme()
	pages[key] = page
	return page
end

-- Shows text in a copy box. kind is "url" (small) or "chat" (large).
function Chat:ShowCopy(kind, title, lede, text, scrollToEnd)
	local page = pages[kind]
	if not page then
		if kind == "url" then
			page = buildPage("url", "StoaCopyUrl", 560, 270)
		else
			page = buildPage("chat", "StoaCopyChat", 640, 440)
		end
	end
	page.title:SetText(title)
	page.lede:SetText(lede)
	page.held = text
	page.box:SetText(text)
	page:Show()
	page.box:SetFocus()
	if scrollToEnd then
		page.box:SetCursorPosition(#text)
	else
		page.box:HighlightText()
	end
	return page
end

function Chat:ShowUrl(address)
	if type(address) ~= "string" or address == "" then return end
	self:ShowCopy("url", "Web address",
		"The game can't open a browser, so copy this and paste it into yours.", address)
end

-- Copy chat ------------------------------------------------------------------------

function Chat:CopyFrame(frame)
	frame = frame or SELECTED_CHAT_FRAME or ChatFrame1
	if not (frame and frame.GetNumMessages and frame.GetMessageInfo) then return end
	local total = frame:GetNumMessages() or 0
	local lines = {}
	for i = math.max(1, total - COPY_LINES + 1), total do
		local ok, text = pcall(frame.GetMessageInfo, frame, i)
		if ok and type(text) == "string" and not Stoa:IsSecret(text) then
			text = Chat.plain(text)
			if text ~= EARLIER then lines[#lines + 1] = text end
		end
	end
	if #lines == 0 then
		Stoa:Print("There's no chat to copy yet.")
		return
	end
	local name = frame.GetName and frame:GetName()
	local tab = name and _G[name .. "Tab"]
	local label = tab and tab.GetText and tab:GetText()
	if type(label) ~= "string" or label == "" then label = "Chat" end
	self:ShowCopy("chat", label, ("The last %d lines of this window."):format(#lines),
		table.concat(lines, "\n"), true)
end

-- A quiet mark at the chat's top right, and Shift-click on any chat tab.
function Chat:BuildCopyButton()
	local chat = ChatFrame1
	if not (chat and chat.CreateFontString) then return end
	local button = CreateFrame("Button", nil, chat)
	button:SetSize(36, 14)
	button:SetPoint("TOPRIGHT", chat, "TOPRIGHT", -4, 0)
	button:SetFrameLevel(chat:GetFrameLevel() + 5)
	local label = UI.text(button, "sans", Stoa.typeSize.caption, "muted", "RIGHT")
	label:SetPoint("RIGHT")
	label:SetText("copy")
	button:SetAlpha(0.35)
	button:SetScript("OnEnter", function(self)
		self:SetAlpha(1)
		GameTooltip:SetOwner(self, "ANCHOR_LEFT")
		GameTooltip:AddLine("Copy this chat window")
		GameTooltip:Show()
	end)
	button:SetScript("OnLeave", function(self)
		self:SetAlpha(0.35)
		GameTooltip:Hide()
	end)
	button:SetScript("OnClick", function()
		xpcall(Chat.CopyFrame, Stoa.catch, Chat, SELECTED_CHAT_FRAME or ChatFrame1)
	end)
	self.copyButton = button

	for i = 1, type(NUM_CHAT_WINDOWS) == "number" and NUM_CHAT_WINDOWS or 10 do
		local tab, frame = _G["ChatFrame" .. i .. "Tab"], _G["ChatFrame" .. i]
		if tab and frame and tab.HookScript then
			tab:HookScript("OnClick", Stoa:Guard(function(_, mouse)
				if mouse == "LeftButton" and IsShiftKeyDown() and Chat.db.copy then Chat:CopyFrame(frame) end
			end, "Chat"))
		end
	end
end

-- History ----------------------------------------------------------------------------

-- Reads the main window's last lines, oldest first, as stored text.
function Chat:Collect()
	local frame = ChatFrame1
	if not (frame and frame.GetNumMessages and frame.GetMessageInfo) then return nil end
	local total = frame:GetNumMessages() or 0
	local lines = {}
	for i = math.max(1, total - HISTORY_LINES * 2 + 1), total do
		local ok, text = pcall(frame.GetMessageInfo, frame, i)
		if ok and type(text) == "string" and not Stoa:IsSecret(text) and text ~= "" then
			-- Colours go; they are dimmed again on the way back. Links stay.
			text = text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
			if text ~= EARLIER and #text <= LINE_LIMIT then lines[#lines + 1] = text end
		end
	end
	while #lines > HISTORY_LINES do table.remove(lines, 1) end
	return lines
end

function Chat:Save()
	if not self.db.history then
		Stoa.char.chatHistory = nil
		return
	end
	local lines = self:Collect()
	if lines and #lines > 0 then Stoa.char.chatHistory = lines end
end

function Chat:Restore()
	local frame = ChatFrame1
	local lines = Stoa.char.chatHistory
	if not (frame and frame.AddMessage) or type(lines) ~= "table" or #lines == 0 then return end
	local r, g, b = Stoa:Color("muted")
	local colour = hex(r, g, b)
	for _, text in ipairs(lines) do
		if type(text) == "string" then frame:AddMessage(colour .. text .. "|r", r, g, b) end
	end
	local dr, dg, db = Stoa:Color("hairline")
	frame:AddMessage(hex(dr, dg, db) .. EARLIER .. "|r", dr, dg, db)
end

-- Switching on --------------------------------------------------------------------------

function Chat:OnEnable()
	if self.db.links then
		if LinkUtil and LinkUtil.RegisterLinkHandler then
			-- The game's own link router: our type is handled here, so the
			-- default item tooltip is never asked about it.
			if not (LinkUtil.IsLinkHandlerRegistered and LinkUtil.IsLinkHandlerRegistered(LINK_TYPE)) then
				LinkUtil.RegisterLinkHandler(LINK_TYPE, Stoa:Guard(function(_, _, linkData)
					Chat:ShowUrl(linkData and linkData.options)
				end, "Chat"))
			end
			for _, event in ipairs(FILTERED) do addFilter(event) end
		end
	end
	if self.db.copy then xpcall(self.BuildCopyButton, Stoa.catch, self) end
	if self.db.history then xpcall(self.Restore, Stoa.catch, self) end
	Stoa:On("PLAYER_LOGOUT", function() Chat:Save() end)
end

Stoa.commands.copychat = function() Chat:CopyFrame() end
