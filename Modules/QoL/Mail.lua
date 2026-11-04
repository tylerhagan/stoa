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

local function money(copper)
	local format = (C_CurrencyInfo and C_CurrencyInfo.GetCoinTextureString) or GetCoinTextureString
	if format then return format(copper) end
	return ("%dg %ds %dc"):format(math.floor(copper / 10000), math.floor(copper / 100) % 100, copper % 100)
end

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

function Mail:Dress()
	if self.dressed then return end
	self.dressed = true
	local openAll = InboxFrame and (InboxFrame.OpenAllMail or _G.OpenAllMail)
	self:WatchOpenAll(openAll)
	if self.db.takeGold and InboxFrame then
		local gold = UI.button(InboxFrame, "Take gold", 96, function() self:TakeGold() end)
		gold:SetHeight(22)
		if openAll then
			gold:SetPoint("RIGHT", openAll, "LEFT", -8, 0)
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
