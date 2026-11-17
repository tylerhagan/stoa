-- Stoa QoL: whisper card. A whisper is easy to miss among the rest of the
-- chat, so a small card rises just above the chat tabs: who whispered (in
-- their class colour) and the start of what they said. More from the same
-- person adds to the count. Click to answer, right-click to put it away;
-- it fades on its own after a while, and waits while the mouse is on it.
local _, ns = ...
local Stoa = ns.Stoa
local UI = Stoa.UI

local Whispers = Stoa:NewModule("Whispers", {
	enabled = true,
})

local WIDTH, HEIGHT = 300, 44
local STAY = 12

local function short(name)
	if Stoa:IsSecret(name) or type(name) ~= "string" then return nil end
	return Ambiguate and Ambiguate(name, "short") or name
end

function Whispers:Build()
	local card = CreateFrame("Button", "StoaWhisperCard", UIParent)
	card:SetSize(WIDTH, HEIGHT)
	card:SetFrameStrata("MEDIUM")
	card:SetClampedToScreen(true)
	UI.roundPanel(card)
	card:RegisterForClicks("LeftButtonUp", "RightButtonUp")

	local mark = card:CreateTexture(nil, "ARTWORK")
	mark:SetSize(6, 6)
	mark:SetPoint("LEFT", card, "LEFT", 12, 0)
	mark:SetRotation(math.rad(45))
	UI.paint(mark, "accent")

	local who = UI.text(card, "sans", Stoa.typeSize.label, "text", "LEFT")
	who:SetPoint("TOPLEFT", card, "TOPLEFT", 26, -8)
	who:SetPoint("RIGHT", card, "RIGHT", -12, 0)
	who:SetWordWrap(false)
	local said = UI.text(card, "sans", Stoa.typeSize.caption, "muted", "LEFT")
	said:SetPoint("TOPLEFT", who, "BOTTOMLEFT", 0, -3)
	said:SetPoint("RIGHT", card, "RIGHT", -12, 0)
	said:SetWordWrap(false)

	card:SetScript("OnClick", function(_, button)
		if button == "LeftButton" then self:Reply() end
		self:Dismiss()
	end)
	card:SetScript("OnEnter", function()
		self.held = true
		GameTooltip:SetOwner(card, "ANCHOR_TOP")
		GameTooltip:AddLine("Click to answer", 1, 1, 1)
		GameTooltip:AddLine("Right-click to put it away", Stoa:Color("muted"))
		GameTooltip:Show()
	end)
	card:SetScript("OnLeave", function()
		self.held = false
		self.until_ = GetTime() + 4
		GameTooltip:Hide()
	end)
	card:Hide()
	UI.riseOnShow(card)
	card.who, card.said = who, said
	self.card = card
end

-- Just above the chat tabs, wherever the chat sits now.
function Whispers:Place()
	local card = self.card
	card:ClearAllPoints()
	local tab = _G.ChatFrame1Tab
	if tab and tab:GetBottom() then
		card:SetPoint("BOTTOMLEFT", tab, "TOPLEFT", 0, 8)
	elseif ChatFrame1 then
		card:SetPoint("BOTTOMLEFT", ChatFrame1, "TOPLEFT", 0, 36)
	else
		card:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", 16, 260)
	end
end

function Whispers:Heard(text, author, guid, bnet)
	local away = Stoa.modules.Away
	if away and away.shown then return end
	if not self.card then self:Build() end
	local name = short(author)
	-- Several from one person add up; someone new starts again.
	if name and name == self.from then
		self.count = (self.count or 1) + 1
	else
		self.count = 1
	end
	self.from, self.reply, self.bnet = name, author, bnet

	local label = name or "Someone"
	local r, g, b = Stoa:Color("text")
	if bnet then
		r, g, b = 0.51, 0.77, 1
	elseif guid and not Stoa:IsSecret(guid) and GetPlayerInfoByGUID then
		local ok, _, class = pcall(GetPlayerInfoByGUID, guid)
		local color = ok and class and not Stoa:IsSecret(class) and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
		if color then r, g, b = color.r, color.g, color.b end
	end
	local card = self.card
	card.who:SetText(label .. " whispered" .. (self.count > 1 and ("  ·  " .. self.count) or ""))
	card.who:SetTextColor(r, g, b)
	if not pcall(card.said.SetText, card.said, text or "") then card.said:SetText("") end

	self:Place()
	self.until_ = GetTime() + STAY
	UI.softShow(card, true)
	if not self.ticker then
		self.ticker = C_Timer.NewTicker(1, function()
			if not self.held and GetTime() >= (self.until_ or 0) then self:Dismiss() end
		end)
	end
end

function Whispers:Reply()
	local to = self.reply
	if not to or Stoa:IsSecret(to) then return end
	local util = ChatFrameUtil
	if self.bnet and util and util.SendBNetTell then
		util.SendBNetTell(to)
	elseif util and util.SendTell then
		util.SendTell(to)
	elseif ChatFrame_SendTell then
		ChatFrame_SendTell(to)
	end
end

function Whispers:Dismiss()
	if self.ticker then self.ticker:Cancel() self.ticker = nil end
	self.from, self.count, self.held = nil, nil, false
	if self.card then
		self.card:Hide()
		GameTooltip:Hide()
	end
end

function Whispers:OnEnable()
	Stoa:On("CHAT_MSG_WHISPER", function(text, author, _, _, _, _, _, _, _, _, _, guid)
		xpcall(self.Heard, Stoa.catch, self, text, author, guid, false)
	end)
	Stoa:On("CHAT_MSG_BN_WHISPER", function(text, author)
		xpcall(self.Heard, Stoa.catch, self, text, author, nil, true)
	end)
	-- Answering by any route puts the card away.
	Stoa:On("CHAT_MSG_WHISPER_INFORM", function() self:Dismiss() end)
	Stoa:On("CHAT_MSG_BN_WHISPER_INFORM", function() self:Dismiss() end)
end

-- /stoa whisper shows a sample card.
Stoa.commands.whisper = function()
	Whispers:Heard("Want to run the Stockade after this?", UnitName("player"), UnitGUID and UnitGUID("player"), false)
end
