-- Stoa: chat in combat.
-- The console folds in combat and takes the chat with it, so party, raid
-- and whisper lines that arrive mid-fight surface for a few seconds just
-- above the folded console, then fade. Nothing to press or hold.
local _, ns = ...
local Stoa = ns.Stoa
local UI = Stoa.UI

local Chat = Stoa:NewModule("CombatChat", {})

local LINES = 3
local SHOW_SECONDS = 8
local LEFT = 36
local ABOVE = 34
local WIDTH = 560

-- The channels worth seeing mid-fight, and the word each one carries.
local CHANNELS = {
	CHAT_MSG_PARTY = "PARTY",
	CHAT_MSG_PARTY_LEADER = "PARTY",
	CHAT_MSG_RAID = "RAID",
	CHAT_MSG_RAID_LEADER = "RAID",
	CHAT_MSG_RAID_WARNING = "WARNING",
	CHAT_MSG_INSTANCE_CHAT = "GROUP",
	CHAT_MSG_INSTANCE_CHAT_LEADER = "GROUP",
	CHAT_MSG_WHISPER = "WHISPER",
	CHAT_MSG_BN_WHISPER = "WHISPER",
}

-- Names can be secret in combat; a secret one is shown as it comes.
local function shortName(name)
	if Stoa:IsSecret(name) or not Ambiguate then return name end
	local ok, short = pcall(Ambiguate, name, "short")
	return ok and short or name
end

function Chat:Build()
	local frame = CreateFrame("Frame", "StoaCombatChat", UIParent)
	frame:SetFrameStrata("LOW")
	frame:SetSize(WIDTH, LINES * 20)
	frame:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", LEFT, ABOVE)
	self.frame = frame
	self.lines = {}
	for i = 1, LINES do
		local line = CreateFrame("Frame", nil, frame)
		line:SetSize(WIDTH, 18)
		line:SetPoint("BOTTOMLEFT", 0, (i - 1) * 20)
		line:SetAlpha(0)
		local tag = UI.caption(line, "")
		tag:SetPoint("LEFT")
		tag:SetWidth(64)
		local name = UI.text(line, "sans", Stoa.typeSize.body, "accent")
		name:SetPoint("LEFT", tag, "RIGHT", 4, 0)
		local text = UI.text(line, "sans", Stoa.typeSize.body, "text")
		text:SetPoint("LEFT", name, "RIGHT", 8, 0)
		text:SetPoint("RIGHT")
		text:SetWordWrap(false)
		for _, fs in ipairs({ tag, name, text }) do UI.legible(fs) end
		line.tag, line.name, line.text = tag, name, text
		self.lines[i] = line
	end
end

-- Newest at the bottom; the others step up, the oldest drops off.
function Chat:Add(word, sender, message)
	local lines = self.lines
	for i = LINES, 2, -1 do
		local to, from = lines[i], lines[i - 1]
		to.tag:SetText(from.tag:GetText())
		to.name:SetText(from.name:GetText())
		to.text:SetText(from.text:GetText())
		to:SetAlpha(from:GetAlpha())
		to.serial = from.serial
	end
	local line = lines[1]
	line.tag:SetText(word)
	line.name:SetText(shortName(sender))
	line.text:SetText(message)
	line:SetAlpha(1)
	self.serial = (self.serial or 0) + 1
	line.serial = self.serial
	local serial = self.serial
	C_Timer.After(SHOW_SECONDS, function()
		for _, each in ipairs(lines) do
			if each.serial == serial then UI.fade(each, 0, 1) end
		end
	end)
end

function Chat:Clear()
	for _, line in ipairs(self.lines) do
		line:SetAlpha(0)
		line.serial = nil
	end
end

function Chat:OnEnable()
	-- Only when the console holds the chat; otherwise the chat window is
	-- still on screen in combat.
	local console = Stoa.modules.Grimoire
	if not (Stoa:IsModuleEnabled("Grimoire") and console.db.houseChat) then return end
	self:Build()
	for event, word in pairs(CHANNELS) do
		Stoa:On(event, function(message, sender)
			if Stoa:GetState() ~= Stoa.STATE_COMBAT then return end
			xpcall(self.Add, geterrorhandler(), self, word, sender, message)
		end)
	end
	Stoa:On("STOA_STATE_CHANGED", function(state)
		if state ~= Stoa.STATE_COMBAT then self:Clear() end
	end)
end
