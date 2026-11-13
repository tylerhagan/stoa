-- Stoa QoL: the session recap's numbers. From login to logout Stoa counts
-- what a play session brought: time played, levels and experience, gold,
-- quests handed in, deaths and the best thing you picked up. They survive a
-- /reload (kept in the character's saved settings) and start again at the
-- next login. A card shows them when you log out (during the game's own
-- countdown; it never stops or delays the logout) and on /stoa recap, and
-- the away screen can show a short version. Only a handful of events, and
-- nothing runs every frame.
local _, ns = ...
local Stoa = ns.Stoa

local Session = Stoa:NewModule("Session", {
	enabled = true,
	-- The card during the logout countdown.
	onLogout = true,
	-- A short version on the away screen, where no whispers came.
	onAway = false,
})
local UI = Stoa.UI

local call = Stoa.safe.call

local function plain(value)
	return Stoa:PlainNumber(value)
end

-- A fresh count, from what the character has now.
function Session:Start()
	self.db.now = {
		started = time(),
		level = plain(call(UnitLevel, "player")) or 0,
		money = plain(call(GetMoney)) or 0,
		xp = 0,
		quests = 0,
		deaths = 0,
	}
	self:NoteXP()
end

function Session:Current()
	return self.db.now
end

-- Experience gained, across level-ups: a drop in the bar's value means a
-- new level, and the rest of the old bar counts too.
function Session:NoteXP()
	local now = self.db.now
	if not now then return end
	local xp = plain(call(UnitXP, "player"))
	local max = plain(call(UnitXPMax, "player"))
	if not xp or not max then return end
	if now.lastXP and now.lastMax then
		local gain = xp - now.lastXP
		if gain < 0 then gain = (now.lastMax - now.lastXP) + xp end
		if gain > 0 then now.xp = now.xp + gain end
	end
	now.lastXP, now.lastMax = xp, max
end

-- The best item you picked up: higher quality first, then item level.
local function lootLink(text)
	if Stoa:IsSecret(text) or type(text) ~= "string" then return nil end
	local mine = false
	for _, global in ipairs({ LOOT_ITEM_SELF, LOOT_ITEM_SELF_MULTIPLE, LOOT_ITEM_PUSHED_SELF, LOOT_ITEM_PUSHED_SELF_MULTIPLE }) do
		local prefix = type(global) == "string" and global:match("^(.-)%%s") or ""
		if prefix ~= "" and text:sub(1, #prefix) == prefix then mine = true break end
	end
	if not mine then return nil end
	return text:match("(|c%x+|Hitem:.-|h%[.-%]|h|r)") or text:match("(|Hitem:.-|h%[.-%]|h)")
end

function Session:NoteLoot(text)
	local now = self.db.now
	local link = now and lootLink(text)
	if not link then return end
	local quality = Stoa.Items.info(link)
	quality = plain(quality)
	if not quality or quality < 2 then return end
	local level = plain(Stoa.Items.level(link)) or 0
	local best = now.best
	if best and (best.quality > quality or (best.quality == quality and best.level >= level)) then return end
	now.best = { link = link, quality = quality, level = level }
end

function Session:OnEnable()
	Stoa:On("PLAYER_ENTERING_WORLD", function(isLogin)
		-- A login starts a new session; a /reload or a loading screen keeps it.
		if isLogin or not self.db.now then self:Start() end
	end)
	Stoa:On("PLAYER_XP_UPDATE", function(unit)
		if unit == nil or unit == "player" then self:NoteXP() end
	end)
	Stoa:On("QUEST_TURNED_IN", function()
		if self.db.now then self.db.now.quests = self.db.now.quests + 1 end
	end)
	Stoa:On("PLAYER_DEAD", function()
		if self.db.now then self.db.now.deaths = self.db.now.deaths + 1 end
	end)
	Stoa:On("CHAT_MSG_LOOT", function(text) xpcall(self.NoteLoot, Stoa.catch, self, text) end)
	-- The game's logout countdown: the card shows beside it. Cancelling the
	-- logout (moving, or the game's own Cancel) puts it away.
	Stoa:On("PLAYER_CAMPING", function()
		if self.db.onLogout and self.db.now then xpcall(self.ShowCard, Stoa.catch, self) end
	end)
	Stoa:On("LOGOUT_CANCEL", function() if self.card then self.card:Hide() end end)
end

local function duration(seconds)
	seconds = math.max(0, math.floor(seconds or 0))
	local h, m = math.floor(seconds / 3600), math.floor(seconds / 60) % 60
	if h > 0 then return ("%dh %02dm"):format(h, m) end
	return ("%dm"):format(m)
end

-- The numbers, ready to show: each entry is { label, words }.
function Session:Lines()
	local now = self.db.now
	if not now then return {} end
	local seconds = time() - now.started
	local level = plain(call(UnitLevel, "player")) or now.level
	local money = (plain(call(GetMoney)) or now.money) - now.money
	local lines = {}
	local function add(label, words) lines[#lines + 1] = { label, words } end
	add("Played", duration(seconds))
	add("Level", level ~= now.level and (now.level .. " to " .. level) or tostring(level))
	if seconds >= 600 and now.xp > 0 then
		add("Experience an hour", BreakUpLargeNumbers and BreakUpLargeNumbers(math.floor(now.xp / (seconds / 3600))) or tostring(math.floor(now.xp / (seconds / 3600))))
	end
	add("Gold", (money < 0 and "-" or "+") .. Stoa.Items.money(math.abs(money)))
	add("Quests handed in", tostring(now.quests))
	add("Deaths", tostring(now.deaths))
	if now.best then add("Best find", now.best.link) end
	return lines
end

-- Four short lines for the away screen.
function Session:Short()
	local now = self.db.now
	if not now then return {} end
	local seconds = time() - now.started
	local level = plain(call(UnitLevel, "player")) or now.level
	local money = (plain(call(GetMoney)) or now.money) - now.money
	local out = {}
	out[1] = duration(seconds) .. (level ~= now.level and (UI.WIDE_SEP .. "level " .. now.level .. " to " .. level) or "")
	if seconds >= 600 and now.xp > 0 then
		out[#out + 1] = ("%s experience an hour"):format(BreakUpLargeNumbers and BreakUpLargeNumbers(math.floor(now.xp / (seconds / 3600))) or math.floor(now.xp / (seconds / 3600)))
	end
	out[#out + 1] = ("%s%s gold%s%d quests"):format(money < 0 and "-" or "+", Stoa.Items.money(math.abs(money)), UI.WIDE_SEP, now.quests)
	if now.best then out[#out + 1] = now.best.link end
	return out
end

-- The card ---------------------------------------------------------------------

local CARD_WIDTH = 360
local PAD = 20

function Session:BuildCard()
	local card = CreateFrame("Frame", "StoaRecap", UIParent)
	card:SetWidth(CARD_WIDTH)
	card:SetFrameStrata("DIALOG")
	card:SetPoint("CENTER", UIParent, "CENTER", 0, 120)
	card:Hide()
	UI.windowPanel(card, nil, { header = 44, plainHeader = true })
	local title = UI.text(card, "serif", Stoa.typeSize.title, "text", "LEFT")
	title:SetPoint("LEFT", card, "TOPLEFT", PAD, -22)
	title:SetText("This session")
	local who = UI.text(card, "sans", Stoa.typeSize.caption, "muted", "RIGHT")
	who:SetPoint("RIGHT", card, "TOPRIGHT", -44, -22)
	local close = CreateFrame("Button", nil, card)
	close:SetSize(20, 20)
	close:SetPoint("RIGHT", card, "TOPRIGHT", -12, -22)
	local cross = UI.glyph(close, "Cross", 14, "muted")
	cross:SetPoint("CENTER")
	close:SetScript("OnClick", function() card:Hide() end)
	close:SetScript("OnEnter", function() cross:SetVertexColor(Stoa:Color("accent")) end)
	close:SetScript("OnLeave", function() cross:SetVertexColor(Stoa:Color("muted")) end)
	card.who, card.rows = who, {}
	if UISpecialFrames then table.insert(UISpecialFrames, "StoaRecap") end
	self.card = card
end

function Session:ShowCard()
	if not self.card then self:BuildCard() end
	local card = self.card
	local lines = self:Lines()
	card.who:SetText(Stoa.safe.plain(UnitName("player")) or "")
	for _, row in ipairs(card.rows) do row.label:Hide() row.value:Hide() end
	local y = -44 - 14
	for i, line in ipairs(lines) do
		local row = card.rows[i]
		if not row then
			row = {
				label = UI.text(card, "sans", Stoa.typeSize.body, "muted", "LEFT"),
				value = UI.text(card, "sans", Stoa.typeSize.label, "text", "RIGHT"),
			}
			card.rows[i] = row
		end
		row.label:ClearAllPoints()
		row.label:SetPoint("TOPLEFT", PAD, y)
		row.value:ClearAllPoints()
		row.value:SetPoint("TOPRIGHT", -PAD, y)
		row.label:SetText(line[1])
		row.value:SetText(line[2])
		if line[1] == "Gold" then row.value:SetTextColor(Stoa:Color("accent")) else row.value:SetTextColor(Stoa:Color("text")) end
		row.label:Show()
		row.value:Show()
		y = y - 22
	end
	card:SetHeight(-y + PAD - 4)
	card:Show()
end

Stoa.commands.recap = function()
	if not Session.enabled then return end
	if not Session.db.now then Stoa:Print("No session yet.") return end
	Session:ShowCard()
end
