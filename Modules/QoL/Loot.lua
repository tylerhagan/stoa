-- Stoa QoL: loot feed and gold an hour. A quiet list of the last few things
-- you looted sits above the chat out of combat and fades after a few
-- seconds. Behind it Stoa keeps this session's takings: gold gained from
-- looting and selling, per hour, and the vendor value of what you looted.
-- Both can be picked as lines in the tally.
local _, ns = ...
local Stoa = ns.Stoa
local UI = Stoa.UI

local Loot = Stoa:NewModule("Loot", {
	show = "WORLD",
	lines = 5,
	seconds = 8,
})

local FADE_SECONDS = 2
local MIN_SECONDS_FOR_RATE = 60

local call = Stoa.safe.call

-- Session totals.
local session = { gold = 0, value = 0, start = nil }

function Loot:ResetSession()
	session.gold, session.value, session.start = 0, 0, GetTime()
	self.entries = {}
	if self.ClearRate then self:ClearRate() end
	self:Render()
end

-- Text patterns -----------------------------------------------------------------

-- "You receive loot: %s." -> the words in front of the link.
local function prefixOf(global, fallback)
	local text = type(global) == "string" and global or fallback
	return text:match("^(.-)%%s") or ""
end

local function selfLoot(text)
	local prefixes = {
		prefixOf(LOOT_ITEM_SELF, "You receive loot: %s."),
		prefixOf(LOOT_ITEM_SELF_MULTIPLE, "You receive loot: %sx%d."),
		prefixOf(LOOT_ITEM_PUSHED_SELF, "You receive item: %s."),
		prefixOf(LOOT_ITEM_PUSHED_SELF_MULTIPLE, "You receive item: %sx%d."),
	}
	for _, prefix in ipairs(prefixes) do
		if prefix ~= "" and text:sub(1, #prefix) == prefix then return true end
	end
	return false
end

-- The pieces of "You loot 1 Gold 4 Silver 30 Copper" (any language that
-- uses the game's own amount strings).
local function amountPattern(global, fallback)
	local text = type(global) == "string" and global or fallback
	local pattern = text:gsub("([%^%$%(%)%.%[%]%*%+%-%?])", "%%%1"):gsub("%%d", "(%%d+)")
	return pattern
end

local function copperIn(text)
	local gold = tonumber(text:match(amountPattern(GOLD_AMOUNT, "%d Gold"))) or 0
	local silver = tonumber(text:match(amountPattern(SILVER_AMOUNT, "%d Silver"))) or 0
	local copper = tonumber(text:match(amountPattern(COPPER_AMOUNT, "%d Copper"))) or 0
	return gold * 10000 + silver * 100 + copper
end

-- The feed ----------------------------------------------------------------------

function Loot:Add(text)
	local entries = self.entries
	table.insert(entries, { text = text, at = GetTime() })
	while #entries > self.db.lines do table.remove(entries, 1) end
	self:Render()
end

-- Newest at the bottom, nearest the chat; each line fades out at the end.
function Loot:Render()
	local frame = self.frame
	if not frame then return end
	local now = GetTime()
	local live = {}
	for _, entry in ipairs(self.entries) do
		local age = now - entry.at
		if age < self.db.seconds then live[#live + 1] = { entry = entry, age = age } end
	end
	for i, fs in ipairs(self.rows) do
		local item = live[#live - (i - 1)]
		if item then
			fs:SetText(item.entry.text)
			local left = self.db.seconds - item.age
			fs:SetAlpha(left < FADE_SECONDS and math.max(left / FADE_SECONDS, 0) or 1)
			fs:Show()
		else
			fs:SetText("")
			fs:Hide()
		end
	end
end

function Loot:Build()
	local frame = CreateFrame("Frame", "StoaLootFeed", UIParent)
	frame:SetSize(300, 90)
	frame:SetFrameStrata("LOW")
	if ChatFrame1 then
		frame:SetPoint("BOTTOMLEFT", ChatFrame1, "TOPLEFT", 4, 34)
	else
		frame:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", 24, 240)
	end
	self.frame = frame
	self.rows = {}
	for i = 1, 8 do
		local fs = UI.text(frame, "sans", Stoa.typeSize.label, "text")
		UI.legible(fs)
		fs:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 0, (i - 1) * 16)
		fs:Hide()
		self.rows[i] = fs
	end
	Stoa.Rules.watch(frame, function() return self.db.show end)
end

-- Events ------------------------------------------------------------------------

function Loot:OnLoot(text)
	if Stoa:IsSecret(text) or type(text) ~= "string" or not selfLoot(text) then return end
	local link = text:match("(|c%x+|Hitem:.-|h%[.-%]|h|r)") or text:match("(|Hitem:.-|h%[.-%]|h)")
	if not link then return end
	local count = tonumber(text:match("|h|rx(%d+)")) or tonumber(text:match("|hx(%d+)")) or 1
	session.value = session.value + (Stoa.Items.sellPrice(link) or 0) * count
	self:Add(count > 1 and (link .. " x" .. count) or link)
end

function Loot:OnMoney(text)
	if Stoa:IsSecret(text) or type(text) ~= "string" then return end
	local copper = copperIn(text)
	if copper <= 0 then return end
	session.gold = session.gold + copper
	self.looted = (self.looted or 0) + copper
	self:Add("+" .. Stoa.Items.money(copper))
end

-- Sales: money that arrives while a vendor is open and was not loot.
function Loot:OnPlayerMoney()
	local now = Stoa:PlainNumber(call(GetMoney))
	if not now then return end
	local before = self.money
	self.money = now
	if not before or now <= before then return end
	local gain = now - before
	if self.looted and self.looted > 0 then
		local used = math.min(self.looted, gain)
		self.looted = self.looted - used
		gain = gain - used
	end
	if gain > 0 and self.atVendor then session.gold = session.gold + gain end
end

local function perHour()
	if not session.start then return nil end
	local seconds = GetTime() - session.start
	if seconds < MIN_SECONDS_FOR_RATE then return nil end
	return session.gold / (seconds / 3600)
end

function Loot:Rate() return perHour() end

-- Gold an hour once a minute, the last twelve, for At a glance's line chart.
local history, historyAt = {}, nil
function Loot:RecordRate()
	local rate = perHour()
	if not rate then return end
	local now = GetTime()
	if historyAt and now - historyAt < 60 then return end
	historyAt = now
	table.insert(history, rate)
	while #history > 12 do table.remove(history, 1) end
end

function Loot:ClearRate()
	for i = #history, 1, -1 do history[i] = nil end
	historyAt = nil
end
function Loot:Totals() return session.gold, session.value end

function Loot:OnEnable()
	self.entries = {}
	session.start = GetTime()
	self.money = Stoa:PlainNumber(call(GetMoney))
	self:Build()
	Stoa:On("CHAT_MSG_LOOT", function(text) self:OnLoot(text) end)
	Stoa:On("CHAT_MSG_MONEY", function(text) self:OnMoney(text) end)
	Stoa:On("PLAYER_MONEY", function() self:OnPlayerMoney() end)
	Stoa:On("MERCHANT_SHOW", function() self.atVendor, self.looted = true, 0 end)
	Stoa:On("MERCHANT_CLOSED", function() self.atVendor = false end)
	Stoa:NewTicker(1, function() self:Render() self:RecordRate() end)

	local tally = Stoa.modules.Tally
	if tally and tally.Register then
		tally:Register("goldHour", {
			label = "Gold an hour",
			value = function()
				local rate = perHour()
				if not rate then return "Counting" end
				return Stoa.Items.money(rate) .. " / h"
			end,
			figure = function() return "spark", history end,
			detail = function(add)
				local gold, value = self:Totals()
				add("Gold this session", Stoa.Items.money(gold))
				add("Loot at vendor prices", Stoa.Items.money(value))
			end,
			action = "Totals in chat",
			open = function() Stoa.commands.loot("") end,
		}, "Kit")
		tally:Register("lootValue", {
			label = "Loot value",
			value = function() return Stoa.Items.money(session.value) end,
			action = "Totals in chat",
			open = function() Stoa.commands.loot("") end,
		}, "Kit")
	end
end

Stoa.commands.loot = function(rest)
	if (rest or ""):lower():match("^reset") then
		Loot:ResetSession()
		Stoa:Print("Loot totals reset.")
		return
	end
	local gold, value = Loot:Totals()
	Stoa:Print(("This session: %s gained, %s of loot at vendor prices. /stoa loot reset starts again."):format(Stoa.Items.money(gold), Stoa.Items.money(value)))
end
