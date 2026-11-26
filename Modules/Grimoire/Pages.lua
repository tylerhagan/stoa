-- Stoa console: more pages for the right side's slots, for a character at
-- the level cap, where Journey has little left to say.
--   Reputation: the standings that moved last, each with its bar.
--   Cooldowns: the long ones (an hour or more) across your characters:
--     profession cooldowns, and items such as a teleporter or the
--     hearthstone. Your on-use trinkets fill any rows left over; other
--     short cooldowns are left to the bars.
--   This week: the raids and dungeons you're saved to, and when they open.
--
-- Each is registered with the console and built only when put in a slot
-- (Settings > Console > Right side). Nothing here runs otherwise, beyond
-- the cooldown note below, which only writes down a time.
local _, ns = ...
local Stoa = ns.Stoa
local UI = Stoa.UI
local Console = Stoa.modules.Grimoire

local Pages = Stoa:NewModule("Pages", {})

local ROWS = 3
local ROW_H = 15
local LONG = 3600        -- seconds: a cooldown this long or longer is "long"
local HEARTHSTONE = 6948
local HEARTH_SPELL = 8690

local function plain(v) return Stoa:PlainNumber(v) end

-- A colour code in the theme's muted tone, for a quiet word inside a line.
local function muted(word)
	local r, g, b = Stoa:Color("muted")
	return string.format("|cff%02x%02x%02x%s|r", (r or 0.5) * 255, (g or 0.5) * 255, (b or 0.5) * 255, word)
end

-- "2d 14h", "3h 20m", "12m", "under 1m".
local function span(seconds)
	seconds = math.max(0, math.floor(seconds))
	local d, h, m = math.floor(seconds / 86400), math.floor(seconds % 86400 / 3600), math.floor(seconds % 3600 / 60)
	if d > 0 then return d .. "d " .. h .. "h" end
	if h > 0 then return h .. "h " .. m .. "m" end
	if m > 0 then return m .. "m" end
	return seconds .. "s"
end

-- A page's frame: the big line with a small note at its right, and rows
-- of a name with a figure at the right.
-- `drop` lowers the rows, for a page with a bar under its big line.
local function scaffold(col, kit, label, drop)
	local rule = kit.heading(label)
	local big = UI.text(col, "serif", Stoa.typeSize.page, "text")
	big:SetPoint("TOPLEFT", rule, "BOTTOMLEFT", 0, -6)
	big:SetWordWrap(false)
	local note = UI.text(col, "sans", Stoa.typeSize.body, "muted", "RIGHT")
	-- Hung from the rule, not from the big line, which is cut short of it.
	note:SetPoint("TOPRIGHT", rule, "BOTTOMRIGHT", 0, -11)
	big:SetWidth(kit.width - 62)
	local rows = {}
	for i = 1, ROWS do
		local name = UI.text(col, "sans", Stoa.typeSize.body, "text")
		name:SetWordWrap(false)
		local value = UI.text(col, "sans", Stoa.typeSize.body, "muted", "RIGHT")
		-- Rows hang under the big line, so a short list sits close to it.
		local y = -(10 + (drop or 0) + (i - 1) * ROW_H)
		-- The figure hangs from the big line by one point, and the name runs
		-- up to it: neither may be anchored to the other both ways, which
		-- the game refuses (and the page then draws nothing).
		value:SetPoint("TOPRIGHT", big, "BOTTOMLEFT", kit.width, y)
		name:SetPoint("TOPLEFT", big, "BOTTOMLEFT", 0, y)
		name:SetPoint("TOPRIGHT", value, "TOPLEFT", -8, 0)
		rows[i] = { name = name, value = value }
	end
	return { big = big, note = note, rows = rows }
end

-- Colours a line from the theme as it stands. Not UI.paint: these lines
-- are coloured again on every refresh, and each paint is kept for the
-- theme passes, so the list of them grew for as long as a page showed.
local function tint(region, token)
	region:SetTextColor(Stoa:Color(token))
end

local function setRow(row, name, value, nameToken, valueToken)
	row.name:SetText(name or "")
	row.value:SetText(value or "")
	tint(row.name, nameToken or "text")
	tint(row.value, valueToken or "muted")
end

-- Refreshes a page now and then while it shows, and on its own events.
local function keep(col, seconds, update)
	local function run() if col:IsVisible() then xpcall(update, Stoa.catch) end end
	col:HookScript("OnShow", run)
	Stoa:NewTicker(seconds, run)
	run()
	return run
end

-- Reputation ----------------------------------------------------------------

-- Every faction with a standing the game lists (a folded heading hides its
-- own; STOA doesn't unfold it). Nothing of the game's list is changed.
local function factions()
	local list = {}
	local api = C_Reputation
	if not (api and api.GetNumFactions and api.GetFactionDataByIndex) then return list end
	for i = 1, plain(api.GetNumFactions()) or 0 do
		local data = api.GetFactionDataByIndex(i)
		if type(data) == "table" and data.factionID and (not data.isHeader or data.isHeaderWithRep) then
			local standing, floor, ceiling = plain(data.currentStanding), plain(data.currentReactionThreshold), plain(data.nextReactionThreshold)
			if type(data.name) == "string" and standing and floor and ceiling then
				list[#list + 1] = { id = data.factionID, name = data.name, standing = standing, floor = floor, ceiling = ceiling,
					reaction = plain(data.reaction), watched = data.isWatched and true or false }
			end
		end
	end
	return list
end

local function rank(f)
	return f.reaction and _G["FACTION_STANDING_LABEL" .. f.reaction] or ""
end

local function share(f)
	local room = f.ceiling - f.floor
	if room <= 0 then return 1 end
	return math.max(0, math.min(1, (f.standing - f.floor) / room))
end

-- Writes down when each standing last moved, so the page can lead with
-- what you're working on. Returns the list, most recent first.
local function movedFirst()
	Stoa.char.reps = Stoa.char.reps or {}
	local seen, now, list = Stoa.char.reps, time(), factions()
	for _, f in ipairs(list) do
		local note = seen[f.id]
		if not note then
			seen[f.id] = { standing = f.standing, moved = 0 }
		elseif note.standing ~= f.standing then
			note.standing, note.moved = f.standing, now
		end
		f.moved = seen[f.id].moved
	end
	-- The one you watch, then what moved last. Before anything has moved:
	-- the highest standing first, and the nearest to its next rank.
	table.sort(list, function(a, b)
		if a.watched ~= b.watched then return a.watched end
		if a.moved ~= b.moved then return a.moved > b.moved end
		if (a.reaction or 0) ~= (b.reaction or 0) then return (a.reaction or 0) > (b.reaction or 0) end
		if share(a) ~= share(b) then return share(a) > share(b) end
		return a.name < b.name
	end)
	return list
end

local function buildReputation(col, kit)
	local page = scaffold(col, kit, "Reputation", 8)
	local bar = Stoa.Figures.bar(col, kit.width, 4)
	bar:SetPoint("TOPLEFT", page.big, "BOTTOMLEFT", 0, -5)
	local update = keep(col, 60, function()
		local list = movedFirst()
		local first = list[1]
		if not first then
			page.big:SetText("None yet")
			page.note:SetText("")
			bar:Hide()
			for i = 1, ROWS do setRow(page.rows[i]) end
			return
		end
		page.big:SetText(first.name)
		page.note:SetText(rank(first))
		bar:Show()
		bar:Set(share(first), "accent")
		local left = first.ceiling - first.standing
		setRow(page.rows[1], left > 0 and (BreakUpLargeNumbers and BreakUpLargeNumbers(left) or left) .. " to the next rank" or "At the top", "", "muted")
		for i = 2, ROWS do
			local f = list[i]
			if f then
				-- The rank is the first word, so a long name gives way to it
				-- last: "Honored  Timbermaw Hold" and the share at the right.
				setRow(page.rows[i], muted(rank(f)) .. "  " .. f.name, math.floor(share(f) * 100) .. "%")
			else
				setRow(page.rows[i])
			end
		end
	end)
	Stoa:On("UPDATE_FACTION", function() C_Timer.After(0.2, update) end)
end

-- Cooldowns -----------------------------------------------------------------

-- Long cooldowns are written into the character's note (Core/Alts.lua's
-- store), by name, as the time they end: { name, ends, quiet }. `quiet`
-- ones (the hearthstone) drop off once ready rather than say so.
local function shelf()
	local Alts = Stoa.modules.Alts
	local key = Alts and Alts.me and Alts.me()
	if not (key and StoaDB and StoaDB.alts and StoaDB.alts[key]) then return nil end
	local entry = StoaDB.alts[key]
	entry.cooldowns = entry.cooldowns or {}
	return entry.cooldowns
end

local function noteCooldown(id, name, start, duration, quiet)
	start, duration = plain(start), plain(duration)
	if not (start and duration and type(name) == "string" and name ~= "") or duration < LONG then return end
	local store = shelf()
	if not store then return end
	store[id] = { name = name, ends = math.floor(time() + start + duration - GetTime()), quiet = quiet or nil }
end

-- Items in the bags and on the character that are cooling for an hour or
-- more. Out of combat only: the figures are hidden in a fight.
function Pages:ScanItems()
	if InCombatLockdown() then return end
	local container = C_Container
	if container and container.GetContainerNumSlots and container.GetContainerItemCooldown and container.GetContainerItemID then
		for bag = 0, 4 do
			for slot = 1, plain(container.GetContainerNumSlots(bag)) or 0 do
				local start, duration = container.GetContainerItemCooldown(bag, slot)
				if (plain(duration) or 0) >= LONG then
					local id = container.GetContainerItemID(bag, slot)
					local name = id and C_Item and C_Item.GetItemNameByID and C_Item.GetItemNameByID(id)
					if id and name then noteCooldown("item:" .. id, name, start, duration, id == HEARTHSTONE) end
				end
			end
		end
	end
	if GetInventoryItemCooldown and GetInventoryItemID then
		for slot = 1, 19 do
			local start, duration = GetInventoryItemCooldown("player", slot)
			if (plain(duration) or 0) >= LONG then
				local id = GetInventoryItemID("player", slot)
				local name = id and C_Item and C_Item.GetItemNameByID and C_Item.GetItemNameByID(id)
				if id and name then noteCooldown("item:" .. id, name, start, duration) end
			end
		end
	end
end

-- The profession cooldowns worth asking the game about at login, so one
-- that was cast before STOA could see it (an older version, a reset
-- profile) still shows. Transmutes share one cooldown, so they share one
-- row: the first that is cooling stands for all of them.
local TRANSMUTES = { 17187, 11479, 11480, 17559, 17560, 17561, 17562, 17563, 17564, 17565, 17566, 25146 }
local CRAFTS = { 18560 } -- Mooncloth
local TRANSMUTE_KEY = "spell:transmute"
local TRANSMUTE_NAME = "Transmute"
local isTransmute = {}
for _, id in ipairs(TRANSMUTES) do isTransmute[id] = true end

-- A spell you just cast that now cools for an hour or more: a profession
-- cooldown, mostly. Any spell counts; the game says how long.
function Pages:NoteSpell(spellID)
	-- The hearthstone is an item: the bag pass notes it, quietly.
	if spellID == HEARTH_SPELL then return end
	if InCombatLockdown() or not (C_Spell and C_Spell.GetSpellCooldown) then return end
	local info = C_Spell.GetSpellCooldown(spellID)
	if type(info) ~= "table" then return end
	local name = C_Spell.GetSpellName and C_Spell.GetSpellName(spellID)
	if type(name) == "string" and not Stoa:IsSecret(name) then
		if isTransmute[spellID] then
			noteCooldown(TRANSMUTE_KEY, TRANSMUTE_NAME, info.startTime, info.duration)
		else
			noteCooldown("spell:" .. spellID, name, info.startTime, info.duration)
		end
	end
end

-- The login pass over the list above. Out of combat only.
function Pages:ScanSpells()
	if InCombatLockdown() or not (C_Spell and C_Spell.GetSpellCooldown) then return end
	local store = shelf()
	if not store then return end
	local function cooling(spellID)
		local info = C_Spell.GetSpellCooldown(spellID)
		return type(info) == "table" and (plain(info.duration) or 0) >= LONG
	end
	for _, id in ipairs(TRANSMUTES) do
		-- A transmute an older version noted under its own spell moves to
		-- the shared row, so the two never stand side by side.
		local old = store["spell:" .. id]
		if old then
			local kept = store[TRANSMUTE_KEY]
			if not kept or (old.ends or 0) > (kept.ends or 0) then store[TRANSMUTE_KEY] = { name = TRANSMUTE_NAME, ends = old.ends } end
			store["spell:" .. id] = nil
		end
	end
	local noted = store[TRANSMUTE_KEY]
	if not (noted and (noted.ends or 0) > time()) then
		for _, id in ipairs(TRANSMUTES) do
			if cooling(id) then self:NoteSpell(id) break end
		end
	end
	for _, id in ipairs(CRAFTS) do
		if cooling(id) then self:NoteSpell(id) end
	end
end

-- Everything on the shelf across characters: ready first, then soonest.
local function shelved()
	local list, now = {}, time()
	local me = Stoa.modules.Alts and Stoa.modules.Alts.me and Stoa.modules.Alts.me()
	for key, entry in pairs(StoaDB and StoaDB.alts or {}) do
		if type(entry.cooldowns) == "table" then
			for id, cd in pairs(entry.cooldowns) do
				local left = (cd.ends or 0) - now
				-- Notes an older version kept by mistake: a cooldown with no
				-- name, and the hearthstone noted a second time by its spell.
				local stray = type(cd.name) ~= "string" or cd.name == "" or id == ("spell:" .. HEARTH_SPELL)
				if stray or (left <= 0 and cd.quiet) then
					entry.cooldowns[id] = nil
				else
					list[#list + 1] = { name = cd.name, left = left, who = key ~= me and entry.name or nil }
				end
			end
		end
	end
	table.sort(list, function(a, b)
		if (a.left <= 0) ~= (b.left <= 0) then return a.left <= 0 end
		if a.left ~= b.left then return a.left < b.left end
		return a.name < b.name
	end)
	return list
end

-- The trinkets you're wearing that can be used, read as they stand: they
-- take the rows the long cooldowns leave, and never the headline.
local TRINKET_SLOTS = { 13, 14 }
local function trinkets()
	local list = {}
	if InCombatLockdown() or not (GetInventoryItemCooldown and GetInventoryItemID and C_Item and C_Item.GetItemSpell and C_Item.GetItemNameByID) then return list end
	for _, slot in ipairs(TRINKET_SLOTS) do
		local id = GetInventoryItemID("player", slot)
		if id and C_Item.GetItemSpell(id) then
			local start, duration = GetInventoryItemCooldown("player", slot)
			start, duration = plain(start), plain(duration)
			local name = C_Item.GetItemNameByID(id)
			-- An hour or more is already on the shelf by its own note.
			if name and start and duration and duration < LONG then
				list[#list + 1] = { name = name, left = duration > 0 and (start + duration - GetTime()) or 0, minor = true }
			end
		end
	end
	return list
end

local function buildCooldowns(col, kit)
	local page = scaffold(col, kit, "Cooldowns")
	-- The big line breathes once when something comes off cooldown. Done by
	-- hand on a frame of its own: an animation group on the line itself
	-- left the line unseen on some logins, played or not.
	local breath = CreateFrame("Frame", nil, col)
	breath:Hide()
	local DIM, DOWN, UP = 0.35, 0.18, 0.3
	breath:SetScript("OnUpdate", function(self, elapsed)
		self.t = (self.t or 0) + elapsed
		local t = self.t
		if t >= DOWN + UP then
			page.big:SetAlpha(1)
			self:Hide()
		elseif t < DOWN then
			page.big:SetAlpha(1 - (1 - DIM) * (t / DOWN))
		else
			page.big:SetAlpha(DIM + (1 - DIM) * ((t - DOWN) / UP))
		end
	end)
	breath:SetScript("OnHide", function() page.big:SetAlpha(1) end)
	local wasReady
	local update = keep(col, 5, function()
		local list = shelved()
		local ready, soonest = 0, nil
		for _, cd in ipairs(list) do
			if cd.left <= 0 then ready = ready + 1 elseif not soonest then soonest = cd.left end
		end
		if #list == 0 then
			page.big:SetText("Nothing cooling")
			page.note:SetText("")
		else
			page.big:SetText(ready > 0 and (ready .. " ready") or "None ready")
			page.note:SetText(soonest and ("next " .. span(soonest)) or "")
		end
		tint(page.big, ready > 0 and "accent" or "text")
		if not breath:IsShown() then page.big:SetAlpha(1) end
		if wasReady and ready > wasReady then breath.t = 0 breath:Show() end
		wasReady = ready
		for _, trinket in ipairs(trinkets()) do list[#list + 1] = trinket end
		for i = 1, ROWS do
			local cd = list[i]
			if cd then
				local name = cd.who and (cd.name .. "  " .. muted(cd.who)) or cd.name
				setRow(page.rows[i], name, cd.left <= 0 and "ready" or span(cd.left), "text", cd.left <= 0 and "accent" or "muted")
			else
				setRow(page.rows[i])
			end
		end
	end)
	Pages.cooldownsChanged = update
	Pages:ScanItems()
	update()
end

-- This week -----------------------------------------------------------------

local function locks()
	local list, now = {}, time()
	local me = Stoa.modules.Alts and Stoa.modules.Alts.me and Stoa.modules.Alts.me()
	local mine, others = 0, {}
	for key, entry in pairs(StoaDB and StoaDB.alts or {}) do
		local count = 0
		for _, lock in ipairs(type(entry.lockouts) == "table" and entry.lockouts or {}) do
			if (lock.ends or 0) > now then
				count = count + 1
				if key == me then list[#list + 1] = { name = lock.name, left = lock.ends - now } end
			end
		end
		if key == me then mine = count elseif count > 0 then others[#others + 1] = (entry.name or "?") .. " " .. count end
	end
	table.sort(list, function(a, b) return a.left < b.left end)
	table.sort(others)
	return list, mine, others
end

local function buildWeek(col, kit)
	local page = scaffold(col, kit, "This week")
	local update = keep(col, 60, function()
		local list, mine, others = locks()
		page.big:SetText(mine == 0 and "All open" or (mine .. " saved"))
		local reset = C_DateAndTime and C_DateAndTime.GetSecondsUntilWeeklyReset and plain(C_DateAndTime.GetSecondsUntilWeeklyReset())
		page.note:SetText(reset and reset > 0 and ("resets " .. span(reset)) or "")
		local last = #others > 0 and ROWS - 1 or ROWS
		for i = 1, last do
			local lock = list[i]
			if lock and i == last and #list > last then
				setRow(page.rows[i], "and " .. (#list - last + 1) .. " more", "", "muted")
			elseif lock then
				setRow(page.rows[i], lock.name, span(lock.left))
			else
				setRow(page.rows[i])
			end
		end
		if #others > 0 then setRow(page.rows[ROWS], "Alts saved: " .. table.concat(others, ", "), "", "muted") end
	end)
	Stoa:On("UPDATE_INSTANCE_INFO", function() C_Timer.After(0.2, update) end)
	if RequestRaidInfo then RequestRaidInfo() end
end

if Console and Console.RegisterPage then
	Console:RegisterPage("reputation", "Reputation", buildReputation, "The standings that moved last")
	Console:RegisterPage("cooldowns", "Cooldowns", buildCooldowns, "Profession and item cooldowns")
	Console:RegisterPage("week", "This week", buildWeek, "What you're saved to")
end

function Pages:OnEnable()
	-- The cooldown note is kept whether or not the page is in a slot, so
	-- an alt's page knows this character's cooldowns. It is one bag pass
	-- a moment after the bags' cooldowns change, out of combat.
	local pending
	local function later()
		if pending then return end
		pending = true
		C_Timer.After(1.5, function()
			pending = false
			self:ScanItems()
			self:ScanSpells()
			if self.cooldownsChanged then self.cooldownsChanged() end
		end)
	end
	Stoa:On("BAG_UPDATE_COOLDOWN", later)
	Stoa:On("PLAYER_ENTERING_WORLD", later)
	Stoa:On("PLAYER_REGEN_ENABLED", later)
	Stoa:OnUnit("UNIT_SPELLCAST_SUCCEEDED", { "player" }, function(_, _, spellID)
		if type(spellID) ~= "number" or Stoa:IsSecret(spellID) then return end
		C_Timer.After(0.5, function()
			self:NoteSpell(spellID)
			if self.cooldownsChanged then self.cooldownsChanged() end
		end)
	end)
end
