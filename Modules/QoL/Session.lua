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
	if seconds < 60 then return "Under a minute" end
	local h, m = math.floor(seconds / 3600), math.floor(seconds / 60) % 60
	if h > 0 then return ("%dh %02dm"):format(h, m) end
	return ("%dm"):format(m)
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
	local parts = {}
	if money ~= 0 then parts[#parts + 1] = ("%s%s gold"):format(money < 0 and "-" or "+", Stoa.Items.money(math.abs(money))) end
	if now.quests > 0 then parts[#parts + 1] = ("%d quests"):format(now.quests) end
	if #parts > 0 then out[#out + 1] = table.concat(parts, UI.WIDE_SEP) end
	if now.best then out[#out + 1] = now.best.link end
	return out
end

-- The card ---------------------------------------------------------------------
-- A header band with your name in your class colour; a hero line with the
-- time played and your level (a level-up lit in the accent); a grid of
-- tiles for the rest, each a big number over a small label on a dark well;
-- and the best find as an item row with its icon, in its quality colour.

local CARD_WIDTH = 380
local PAD = 20
local HEADER = 44
local GAP = 8
local TILE_H = 54

local function classColour()
	local _, class = UnitClass("player")
	local colour = class and (C_ClassColor and C_ClassColor.GetClassColor and C_ClassColor.GetClassColor(class) or (RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]))
	if colour then return colour.r, colour.g, colour.b end
	return Stoa:Color("text")
end

local function caption(parent, token)
	return UI.text(parent, "sans", Stoa.typeSize.micro, token or "muted", "LEFT")
end

function Session:BuildCard()
	local card = CreateFrame("Frame", "StoaRecap", UIParent)
	card:SetWidth(CARD_WIDTH)
	card:SetFrameStrata("DIALOG")
	card:SetPoint("CENTER", UIParent, "CENTER", 0, 120)
	card:Hide()
	UI.windowPanel(card, nil, { header = HEADER, plainHeader = true })
	UI.riseOnShow(card)
	local title = UI.text(card, "serif", Stoa.typeSize.title, "text", "LEFT")
	title:SetPoint("LEFT", card, "TOPLEFT", PAD, -HEADER / 2)
	title:SetText("This session")
	local who = UI.text(card, "sans", Stoa.typeSize.body, "text", "RIGHT")
	who:SetPoint("RIGHT", card, "TOPRIGHT", -44, -HEADER / 2)
	local close = CreateFrame("Button", nil, card)
	close:SetSize(20, 20)
	close:SetPoint("RIGHT", card, "TOPRIGHT", -12, -HEADER / 2)
	local cross = UI.glyph(close, "Cross", 14, "muted")
	cross:SetPoint("CENTER")
	close:SetScript("OnClick", function() card:Hide() end)
	close:SetScript("OnEnter", function() cross:SetVertexColor(Stoa:Color("accent")) end)
	close:SetScript("OnLeave", function() cross:SetVertexColor(Stoa:Color("muted")) end)

	-- Hero: time played on the left, level on the right.
	local playedCap = caption(card)
	playedCap:SetPoint("TOPLEFT", PAD, -HEADER - 16)
	playedCap:SetText("PLAYED")
	local played = UI.text(card, "serif", Stoa.typeSize.display, "text", "LEFT")
	played:SetPoint("TOPLEFT", playedCap, "BOTTOMLEFT", 0, -4)
	local levelCap = caption(card)
	levelCap:SetJustifyH("RIGHT")
	levelCap:SetPoint("TOPRIGHT", -PAD, -HEADER - 16)
	local level = UI.text(card, "serif", Stoa.typeSize.display, "text", "RIGHT")
	level:SetPoint("TOPRIGHT", levelCap, "BOTTOMRIGHT", 0, -4)
	local rule = card:CreateTexture(nil, "BORDER")
	UI.pixel(rule, "height")
	rule:SetTexture(UI.WHITE)
	rule:SetPoint("TOPLEFT", PAD, -HEADER - 72)
	rule:SetPoint("TOPRIGHT", -PAD, -HEADER - 72)

	-- The best find: icon, name in its quality colour, item level.
	local find = CreateFrame("Button", nil, card)
	find:SetHeight(44)
	UI.well(find, 0)
	local findCap = caption(find)
	findCap:SetText("BEST FIND")
	local icon = find:CreateTexture(nil, "ARTWORK")
	icon:SetSize(30, 30)
	icon:SetPoint("LEFT", 8, 0)
	icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	local ring = find:CreateTexture(nil, "OVERLAY")
	ring:SetPoint("TOPLEFT", icon, -1, 1)
	ring:SetPoint("BOTTOMRIGHT", icon, 1, -1)
	ring:SetTexture(UI.WHITE)
	ring:SetDrawLayer("ARTWORK", -1)
	findCap:SetPoint("TOPLEFT", icon, "TOPRIGHT", 10, 0)
	local findName = UI.text(find, "sans", Stoa.typeSize.body, "text", "LEFT")
	findName:SetPoint("BOTTOMLEFT", icon, "BOTTOMRIGHT", 10, 1)
	findName:SetPoint("RIGHT", find, "RIGHT", -52, 0)
	findName:SetWordWrap(false)
	local findLevel = UI.text(find, "sans", Stoa.typeSize.caption, "muted", "RIGHT")
	findLevel:SetPoint("RIGHT", -10, 0)
	find:SetScript("OnEnter", function(own)
		if not own.link then return end
		GameTooltip:SetOwner(own, "ANCHOR_RIGHT")
		GameTooltip:SetHyperlink(own.link)
		GameTooltip:Show()
	end)
	find:SetScript("OnLeave", function() GameTooltip:Hide() end)

	card.who, card.played, card.level, card.levelCap, card.rule = who, played, level, levelCap, rule
	card.find, card.findIcon, card.findRing, card.findName, card.findLevel = find, icon, ring, findName, findLevel
	card.tiles = {}
	if UISpecialFrames then table.insert(UISpecialFrames, "StoaRecap") end
	self.card = card
end

-- The tiles: { label, value, token } for what the session counted.
function Session:Tiles()
	local now = self.db.now
	local seconds = time() - now.started
	local money = (plain(call(GetMoney)) or now.money) - now.money
	local tiles = {}
	if seconds >= 600 and now.xp > 0 then
		local rate = math.floor(now.xp / (seconds / 3600))
		tiles[#tiles + 1] = { "Experience an hour", BreakUpLargeNumbers and BreakUpLargeNumbers(rate) or tostring(rate) }
	end
	if money ~= 0 then tiles[#tiles + 1] = { money > 0 and "Gold earned" or "Gold spent", Stoa.Items.money(math.abs(money)), money > 0 and "accent" or "text" } end
	if now.quests > 0 then tiles[#tiles + 1] = { now.quests == 1 and "Quest handed in" or "Quests handed in", tostring(now.quests) } end
	if now.deaths > 0 then tiles[#tiles + 1] = { now.deaths == 1 and "Death" or "Deaths", tostring(now.deaths), "danger" } end
	return tiles
end

function Session:ShowCard()
	if not self.card then self:BuildCard() end
	local card = self.card
	local now = self.db.now
	card.who:SetText(Stoa.fullName() or "")
	card.who:SetTextColor(classColour())
	local tr, tg, tb = Stoa:Color("text")
	card.rule:SetVertexColor(tr, tg, tb, 0.1)

	card.played:SetText(duration(time() - now.started))
	local level = plain(call(UnitLevel, "player")) or now.level
	if level ~= now.level then
		card.levelCap:SetText("LEVEL UP")
		card.levelCap:SetTextColor(Stoa:Color("accent"))
		card.level:SetText(now.level .. Stoa:Hex("muted") .. " to |r" .. Stoa:Hex("accent") .. level .. "|r")
	else
		card.levelCap:SetText("LEVEL")
		card.levelCap:SetTextColor(Stoa:Color("muted"))
		card.level:SetText(tostring(level))
	end

	-- The tiles, two to a row.
	for _, tile in ipairs(card.tiles) do tile:Hide() end
	local tiles = self:Tiles()
	local width = (CARD_WIDTH - PAD * 2 - GAP) / 2
	local top = HEADER + 84
	for i, info in ipairs(tiles) do
		local tile = card.tiles[i]
		if not tile then
			tile = CreateFrame("Frame", nil, card)
			UI.well(tile, 0)
			tile.value = UI.text(tile, "sans", Stoa.typeSize.name, "text", "LEFT")
			tile.value:SetPoint("TOPLEFT", 12, -10)
			tile.label = caption(tile)
			tile.label:SetPoint("BOTTOMLEFT", 12, 10)
			card.tiles[i] = tile
		end
		local col, rowIndex = (i - 1) % 2, math.floor((i - 1) / 2)
		tile:ClearAllPoints()
		tile:SetSize(width, TILE_H)
		tile:SetPoint("TOPLEFT", card, "TOPLEFT", PAD + col * (width + GAP), -(top + rowIndex * (TILE_H + GAP)))
		tile.value:SetText(info[2])
		tile.value:SetTextColor(Stoa:Color(info[3] or "text"))
		tile.label:SetText(info[1]:upper())
		tile:Show()
	end
	local y = top + math.ceil(#tiles / 2) * (TILE_H + GAP)
	if #tiles == 0 then y = top end

	-- The best find.
	local find = card.find
	local best = now.best
	if best then
		find.link = best.link
		find:ClearAllPoints()
		find:SetPoint("TOPLEFT", card, "TOPLEFT", PAD, -y)
		find:SetPoint("TOPRIGHT", card, "TOPRIGHT", -PAD, -y)
		local iconFile = C_Item and C_Item.GetItemIconByID and call(C_Item.GetItemIconByID, best.link) or (GetItemIcon and call(GetItemIcon, best.link))
		card.findIcon:SetTexture(iconFile or 134400)
		local r, g, b = 1, 1, 1
		local colour = ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[best.quality]
		if colour then r, g, b = colour.r, colour.g, colour.b end
		card.findRing:SetVertexColor(r, g, b, 0.9)
		local name = best.link:match("%[(.-)%]") or best.link
		card.findName:SetText(name)
		card.findName:SetTextColor(r, g, b)
		card.findLevel:SetText(best.level and best.level > 0 and ("ilvl " .. best.level) or "")
		find:Show()
		y = y + 44 + GAP
	else
		find:Hide()
	end
	card:SetHeight(y + PAD - GAP)
	card:Show()
end

Stoa.commands.recap = function()
	if not Session.enabled then return end
	if not Session.db.now then Stoa:Print("No session yet.") return end
	Session:ShowCard()
end
