-- Stoa QoL: a cleaner chat, each part its own setting.
--   Times: every line starts with a quiet time and a thin rule, "17:16 | ",
--   so the messages line up in a column after it.
--   Air: a little more space between lines.
--   Rail: the chat's buttons (friends, channels, voice, the chat menu) in
--   one quiet column down the chat's left side, brightening under the mouse.
--   Input: the typing box as a dark strip under the messages with a fine
--   rule above, instead of Blizzard's gold-edged box.
-- Blizzard's chat still does all the work; Stoa only adds to each line as
-- it's written and moves Blizzard's own buttons. The combat log is left be.
local _, ns = ...
local Stoa = ns.Stoa
local UI = Stoa.UI
local hooksecurefunc = Stoa.SafeHook

local ChatLook = Stoa:NewModule("ChatLook", {
	times = true,
	air = true,
	rail = true,
	input = true,
})

local RAIL_WIDTH = 22
local RAIL_GAP = 6
local LINE_SPACE = 3
local INPUT_HEIGHT = 22

local function hex(r, g, b)
	return ("|cff%02x%02x%02x"):format(r * 255, g * 255, b * 255)
end

local function chatFrames()
	local list = {}
	for i = 1, (NUM_CHAT_WINDOWS or 10) do
		local frame = _G["ChatFrame" .. i]
		-- ChatFrame2 is the combat log.
		if frame and i ~= 2 then list[#list + 1] = frame end
	end
	return list
end

-- Times -------------------------------------------------------------------------

local function gameStamps()
	local get = (C_CVar and C_CVar.GetCVar) or GetCVar
	local value = get and get("showTimestamps")
	return value and value ~= "none" and value ~= ""
end

local function stamp(frame)
	if frame.stoaStamped then return end
	frame.stoaStamped = true
	local original = frame.AddMessage
	frame.AddMessage = function(own, text, ...)
		if ChatLook.db.times and not Stoa.chatQuiet and type(text) == "string" and not Stoa:IsSecret(text)
			and not gameStamps() then
			local mr, mg, mb = Stoa:Color("muted")
			local hr, hg, hb = Stoa:Color("hairline")
			text = hex(mr, mg, mb) .. date("%H:%M") .. "|r " .. hex(hr, hg, hb) .. "||" .. "|r " .. text
		end
		return original(own, text, ...)
	end
end

-- Air ---------------------------------------------------------------------------

function ChatLook:Air()
	for _, frame in ipairs(chatFrames()) do
		if frame.SetSpacing then frame:SetSpacing(self.db.air and LINE_SPACE or 0) end
	end
end

-- Rail --------------------------------------------------------------------------

-- OneForAll's hide-chat button would sit on top of the column; it joins it.
local RAIL_BUTTONS = {
	"OneForAllChatHideButton", "QuickJoinToastButton", "ChatFrameChannelButton", "ChatFrameToggleVoiceDeafenButton",
	"ChatFrameToggleVoiceMuteButton", "ChatFrameMenuButton",
}

local function quiet(button)
	if button.stoaQuiet then return end
	button.stoaQuiet = true
	button:SetAlpha(0.55)
	button:HookScript("OnEnter", function(own) own:SetAlpha(1) end)
	button:HookScript("OnLeave", function(own) own:SetAlpha(0.55) end)
end

function ChatLook:PlaceRail()
	if not self.db.rail or InCombatLockdown() then return end
	local chat = ChatFrame1
	if not chat then return end
	local rail = self.rail
	if not rail then
		rail = CreateFrame("Frame", "StoaChatRail", UIParent)
		rail:SetWidth(RAIL_WIDTH)
		rail:SetFrameStrata("MEDIUM")
		local rule = UI.line(rail)
		rule:SetHeight(0)
		rule:SetWidth(1)
		rule:SetPoint("TOPRIGHT", rail, "TOPRIGHT", RAIL_GAP / 2, 0)
		rule:SetPoint("BOTTOMRIGHT", rail, "BOTTOMRIGHT", RAIL_GAP / 2, 0)
		self.rail = rail
	end
	rail:ClearAllPoints()
	rail:SetPoint("TOPRIGHT", chat, "TOPLEFT", -RAIL_GAP, 0)
	rail:SetPoint("BOTTOMRIGHT", chat, "BOTTOMLEFT", -RAIL_GAP, 0)
	local above
	for _, name in ipairs(RAIL_BUTTONS) do
		local button = _G[name]
		if button and not (button.IsForbidden and button:IsForbidden()) and not (button.IsProtected and button:IsProtected()) then
			button:SetParent(rail)
			button:ClearAllPoints()
			if above then
				button:SetPoint("TOP", above, "BOTTOM", 0, -4)
			else
				button:SetPoint("TOP", rail, "TOP", 0, 0)
			end
			button:SetScale(0.85)
			quiet(button)
			if button:IsShown() then above = button end
		end
	end
	local holder = chat.buttonFrame or _G.ChatFrame1ButtonFrame
	if holder and holder.Background then holder.Background:SetAlpha(0) end
end

-- Input -------------------------------------------------------------------------

local INPUT_ART = { "Left", "Mid", "Right", "FocusLeft", "FocusMid", "FocusRight" }

function ChatLook:Input()
	if not self.db.input or InCombatLockdown() then return end
	local chat, box = ChatFrame1, ChatFrame1EditBox
	if not (chat and box) then return end
	if not box.stoaDressed then
		box.stoaDressed = true
		for _, part in ipairs(INPUT_ART) do
			local tex = _G["ChatFrame1EditBox" .. part] or box[part] or box[part:sub(1, 1):lower() .. part:sub(2)]
			if tex and tex.SetAlpha then tex:SetAlpha(0) end
		end
		local fill = box:CreateTexture(nil, "BACKGROUND", nil, -8)
		fill:SetAllPoints()
		UI.tint(fill, "panel", 0.85)
		fill:SetColorTexture(1, 1, 1)
		local rule = UI.line(box)
		rule:SetPoint("TOPLEFT")
		rule:SetPoint("TOPRIGHT")
		if box.HookScript then box:HookScript("OnShow", function() ChatLook:Input() end) end
		UI.applyTheme()
	end
	box:ClearAllPoints()
	box:SetPoint("TOPLEFT", chat, "BOTTOMLEFT", -4, -2)
	box:SetPoint("TOPRIGHT", chat, "BOTTOMRIGHT", 4, -2)
	box:SetHeight(INPUT_HEIGHT)
end

-- -----------------------------------------------------------------------------

function ChatLook:Apply()
	xpcall(self.Air, Stoa.catch, self)
	xpcall(self.PlaceRail, Stoa.catch, self)
	xpcall(self.Input, Stoa.catch, self)
end

function ChatLook:OnEnable()
	for _, frame in ipairs(chatFrames()) do stamp(frame) end
	if FCF_OpenNewWindow then
		hooksecurefunc("FCF_OpenNewWindow", function()
			for _, frame in ipairs(chatFrames()) do stamp(frame) end
			ChatLook:Air()
		end)
	end
	local function apply() Stoa:AfterCombat(function() self:Apply() end) end
	-- Blizzard puts its buttons back when the chat's side or dock changes.
	for _, name in ipairs({ "FCF_UpdateButtonSide", "FCF_DockUpdate" }) do
		if _G[name] then hooksecurefunc(name, apply) end
	end
	Stoa:On("PLAYER_ENTERING_WORLD", apply)
	Stoa:On("EDIT_MODE_LAYOUTS_UPDATED", apply)
	Stoa:On("STOA_THEME_CHANGED", apply)
	apply()
end
