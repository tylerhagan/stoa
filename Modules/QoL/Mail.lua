-- Stoa QoL: the mailbox. The game opens all mail itself now; Stoa adds what
-- it doesn't: Take gold (money only, items stay), one line saying what came
-- out of the box, and a To list of your own characters and the people you
-- mailed lately. Letters with cash on delivery and from game masters are
-- always left for you to open.
local _, ns = ...
local Stoa = ns.Stoa
local UI = Stoa.UI

local Mail = Stoa:NewModule("Mail", {
	takeGold = true,
	summary = true,
	toList = true,
})

local RECENT = 10
local STEP = 0.3

local function money(copper) return Stoa:Money(copper) end

local function recent()
	StoaDB.mailRecent = StoaDB.mailRecent or {}
	return StoaDB.mailRecent
end

local function remember(name)
	if type(name) ~= "string" or name == "" or Stoa:IsSecret(name) then return end
	name = strtrim(name)
	local list = recent()
	for i = #list, 1, -1 do
		if list[i]:lower() == name:lower() then table.remove(list, i) end
	end
	table.insert(list, 1, name)
	while #list > RECENT do table.remove(list) end
end

-- Money in a letter Stoa may take: no cash on delivery, not from a GM.
local function takeable(i)
	local _, _, _, _, cash, cod, _, _, _, _, _, _, isGM = GetInboxHeaderInfo(i)
	if isGM or (cod and cod > 0) then return 0 end
	return cash or 0
end

function Mail:TakeGold()
	if self.taking or not (GetInboxNumItems and TakeInboxMoney) then return end
	local start = GetMoney()
	local i = GetInboxNumItems()
	self.taking = true
	self.goldButton:Disable()
	local function finish()
		self.taking = false
		if self.goldButton then self.goldButton:Enable() end
		local got = GetMoney() - start
		if got > 0 then Stoa:Note("mail", ("Took %s from your mail."):format(money(got))) end
	end
	local function step()
		if not self.taking then return end
		if IsShiftKeyDown() or not (MailFrame and MailFrame:IsShown()) then return finish() end
		while i > 0 and takeable(i) == 0 do i = i - 1 end
		if i <= 0 then return finish() end
		pcall(TakeInboxMoney, i)
		i = i - 1
		C_Timer.After(STEP, step)
	end
	step()
end

-- Whatever came out while the game's Open All ran, said once at the end.
function Mail:WatchOpenAll(button)
	if not (button and button.StartOpening and button.StopOpening) then return end
	hooksecurefunc(button, "StartOpening", function()
		self.openStart = GetMoney()
		self.openItems = self:BagCount()
	end)
	hooksecurefunc(button, "StopOpening", function()
		if not (self.db.summary and self.openStart) then return end
		local gold = GetMoney() - self.openStart
		local items = self:BagCount() - (self.openItems or 0)
		self.openStart = nil
		local parts = {}
		if gold > 0 then parts[#parts + 1] = money(gold) end
		if items > 0 then parts[#parts + 1] = items == 1 and "1 item" or (items .. " items") end
		if #parts > 0 then Stoa:Note("mail", "From your mail: " .. table.concat(parts, " and ") .. ".") end
	end)
end

function Mail:BagCount()
	local n = 0
	if Stoa.Items and Stoa.Items.eachBagSlot then
		Stoa.Items.eachBagSlot(function(_, _, info) n = n + (info.stackCount or 1) end)
	end
	return n
end

function Mail:ToMenu(owner)
	if not (MenuUtil and MenuUtil.CreateContextMenu) then return end
	local box = SendMailNameEditBox
	local function pick(name)
		return function()
			box:SetText(name)
			box:SetCursorPosition(#name)
			if SendMailSubjectEditBox then SendMailSubjectEditBox:SetFocus() end
		end
	end
	MenuUtil.CreateContextMenu(owner, function(_, root)
		local mine = Stoa.Alts and Stoa.Alts.names(true) or {}
		root:CreateTitle("Your characters")
		if #mine == 0 then root:CreateTitle("(each shows once you've played it)") end
		for _, entry in ipairs(mine) do root:CreateButton(entry.name, pick(entry.name)) end
		local list = recent()
		if #list > 0 then
			root:CreateDivider()
			root:CreateTitle("Mailed lately")
			for _, name in ipairs(list) do root:CreateButton(name, pick(name)) end
		end
	end)
end

-- Blizzard's inbox puts Open All and the Prev / Next page buttons on one
-- row, so a button beside Open All lands on Prev. With Take gold the inbox
-- is a row taller: actions on the upper row, the pages on their own row
-- below. Only the inbox tab grows; Send Mail keeps the usual height.
local EXTRA_ROW = 32
local ACTION_WIDTH, ACTION_HEIGHT, ACTION_GAP = 110, 24, 8

-- A page button as a quiet word: the arrow art goes, the word takes
-- Stoa's type, muted at rest and accent under the mouse, dim when there is
-- no page that way.
local function dressPage(button, side)
	if not (button and button.GetRegions) or button.stoaPage then return end
	button.stoaPage = true
	for _, getter in ipairs({ "GetNormalTexture", "GetPushedTexture", "GetDisabledTexture", "GetHighlightTexture" }) do
		local tex = button[getter] and button[getter](button)
		if tex then tex:SetAlpha(0) end
	end
	local word
	for _, region in ipairs({ button:GetRegions() }) do
		if region.IsObjectType and region:IsObjectType("FontString") then word = region break end
	end
	if not word then return end
	Stoa:SetFont(word, "sans", Stoa.typeSize.body)
	word:ClearAllPoints()
	-- A drawn chevron at the button's outer edge, the word inside it.
	local chevron = Stoa.UI.glyph(button, "Chevron", 12, "text")
	if side == "left" then
		chevron:SetTexCoord(1, 0, 0, 1)
		chevron:SetPoint("LEFT", button, "LEFT", -2, 0)
		word:SetPoint("LEFT", chevron, "RIGHT", 1, 0)
	else
		chevron:SetPoint("RIGHT", button, "RIGHT", 2, 0)
		word:SetPoint("RIGHT", chevron, "LEFT", -1, 0)
	end
	word:SetText(side == "left" and (PREV or "Prev") or (NEXT or "Next"))
	local function colour(over)
		local enabled = button:IsEnabled()
		word:SetTextColor(Stoa:Color(not enabled and "muted" or over and "accent" or "text"))
		word:SetAlpha(enabled and 1 or 0.5)
		chevron:SetVertexColor(Stoa:Color(not enabled and "muted" or over and "accent" or "text"))
		chevron:SetAlpha(enabled and 1 or 0.5)
	end
	button:HookScript("OnEnter", function() colour(true) end)
	button:HookScript("OnLeave", function() colour(false) end)
	button:HookScript("OnEnable", function() colour(false) end)
	button:HookScript("OnDisable", function() colour(false) end)
	button:HookScript("OnShow", function() colour(false) end)
	colour(false)
end

-- The inbox a row taller: Take gold and Open All, one size, centred as a
-- pair under the letters; Prev and Next at the bottom edge as quiet words
-- on a row of their own. Only the inbox tab grows.
function Mail:TwoRows(openAll, gold)
	local frame = MailFrame
	if not (frame and InboxFrame and openAll and frame.GetHeight) then return end
	local base = Stoa:PlainNumber(frame:GetHeight())
	if not base then return end
	local function fit()
		if InCombatLockdown() then return end
		frame:SetHeight(InboxFrame:IsShown() and (base + EXTRA_ROW) or base)
	end
	local row = 26 + EXTRA_ROW
	local half = (ACTION_WIDTH + ACTION_GAP) / 2
	openAll:SetSize(ACTION_WIDTH, ACTION_HEIGHT)
	openAll:ClearAllPoints()
	openAll:SetPoint("CENTER", InboxFrame, "BOTTOM", half, row)
	if gold then
		gold:SetSize(ACTION_WIDTH, ACTION_HEIGHT)
		gold:ClearAllPoints()
		gold:SetPoint("CENTER", InboxFrame, "BOTTOM", -half, row)
	end
	dressPage(InboxFrame.PrevPageButton or _G.InboxPrevPageButton, "left")
	dressPage(InboxFrame.NextPageButton or _G.InboxNextPageButton, "right")
	InboxFrame:HookScript("OnShow", fit)
	InboxFrame:HookScript("OnHide", fit)
	fit()
end

function Mail:Dress()
	if self.dressed then return end
	self.dressed = true
	local openAll = InboxFrame and (InboxFrame.OpenAllMail or _G.OpenAllMail)
	self:WatchOpenAll(openAll)
	if self.db.takeGold and InboxFrame then
		local gold = UI.button(InboxFrame, "Take gold", ACTION_WIDTH, function() self:TakeGold() end)
		gold:SetHeight(ACTION_HEIGHT)
		if openAll then
			gold:SetPoint("RIGHT", openAll, "LEFT", -ACTION_GAP, 0)
			xpcall(self.TwoRows, Stoa.catch, self, openAll, gold)
		else
			gold:SetPoint("BOTTOM", InboxFrame, "BOTTOM", 0, 100)
		end
		gold:SetScript("OnEnter", function(b)
			GameTooltip:SetOwner(b, "ANCHOR_TOP")
			GameTooltip:AddLine("Take the money from every letter")
			GameTooltip:AddLine("Items stay. Cash on delivery and GM letters are left for you. Shift stops.", 0.7, 0.7, 0.7, true)
			GameTooltip:Show()
		end)
		gold:SetScript("OnLeave", GameTooltip_Hide)
		self.goldButton = gold
	end
	local box = SendMailNameEditBox
	if self.db.toList and box then
		local to = UI.button(box:GetParent() or SendMailFrame, "Mine", 52, function(b) self:ToMenu(b) end)
		to:SetHeight(20)
		to:SetPoint("LEFT", box, "RIGHT", 6, 0)
		self.toButton = to
	end
end

function Mail:OnEnable()
	Stoa:On("MAIL_SHOW", function() xpcall(self.Dress, Stoa.catch, self) end)
	Stoa:On("MAIL_CLOSED", function() self.taking = false end)
	if SendMail then
		hooksecurefunc("SendMail", function(to) remember(to) end)
	end
end
