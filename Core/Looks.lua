-- Stoa: other addons in Stoa's look.
-- Some addons people keep beside Stoa have their own windows: Questie's quest
-- tracker, Bagnon's bags, Details' meters. Where an addon lets others dress
-- it (a skin list, or fonts and colours in its own settings), Stoa offers its
-- look once, after the "two addons, one job" questions are settled:
--   Use Stoa's look: the addon keeps working exactly as before, in Stoa's
--   type and colours. Its own settings are changed the way you could change
--   them yourself, and what they were is kept, so Leave it puts them back.
--   Leave it: nothing changes.
-- The answer is remembered account-wide; /stoa looks asks again.
--
-- Stoa's fonts and a flat bar are also offered through LibSharedMedia, so
-- any addon with a font or texture list can pick "Stoa Display", "Stoa UI"
-- or "Stoa Flat".
local _, ns = ...
local Stoa = ns.Stoa
local UI = Stoa.UI

local Looks = {}
Stoa.Looks = Looks

local FONT_DISPLAY = "Stoa Display"
local FONT_UI = "Stoa UI"
local BAR = "Stoa Flat"
local FONT_DISPLAY_FILE = UI.MEDIA .. "Fonts\\TenorSans-Regular.ttf"
local FONT_UI_FILE = UI.MEDIA .. "Fonts\\Inter-SemiBold.ttf"
local BAR_FILE = "Interface\\Buttons\\WHITE8X8"

local function isLoaded(folder)
	if C_AddOns and C_AddOns.IsAddOnLoaded then return C_AddOns.IsAddOnLoaded(folder) end
	return IsAddOnLoaded and IsAddOnLoaded(folder)
end

local function media()
	local lsm = LibStub and LibStub("LibSharedMedia-3.0", true)
	if not lsm then return end
	pcall(lsm.Register, lsm, "font", FONT_DISPLAY, FONT_DISPLAY_FILE)
	pcall(lsm.Register, lsm, "font", FONT_UI, FONT_UI_FILE)
	pcall(lsm.Register, lsm, "statusbar", BAR, BAR_FILE)
	return lsm
end

local function saved()
	Stoa.db.looks = Stoa.db.looks or {}
	return Stoa.db.looks
end

local function copy(value)
	if type(value) ~= "table" then return value end
	local out = {}
	for k, v in pairs(value) do out[k] = copy(v) end
	return out
end

-- Questie -------------------------------------------------------------------------
-- Questie reads its tracker's fonts by LibSharedMedia name from its profile.

local QUESTIE_KEYS = {
	trackerFontHeader = FONT_DISPLAY, trackerFontSizeHeader = 13,
	trackerFontZone = FONT_DISPLAY, trackerFontSizeZone = 12,
	trackerFontQuest = FONT_UI, trackerFontSizeQuest = 11,
	trackerFontObjective = FONT_UI, trackerFontSizeObjective = 10,
	trackerFontOutline = "",
	trackerBackdropEnabled = false, trackerBorderEnabled = false,
}

local function questieProfile()
	local questie = _G.Questie
	local db = type(questie) == "table" and questie.db
	return type(db) == "table" and type(db.profile) == "table" and db.profile or nil
end

local function questieRefresh()
	local loader = _G.QuestieLoader
	if type(loader) ~= "table" or type(loader.ImportModule) ~= "function" then return end
	local ok, tracker = pcall(loader.ImportModule, loader, "QuestieTracker")
	if ok and type(tracker) == "table" and type(tracker.Update) == "function" then pcall(tracker.Update, tracker) end
end

-- Bagnon --------------------------------------------------------------------------
-- Bagnon has a skin list other addons may add to. Stoa's skin is always in
-- it (pick "Stoa" in Bagnon's own options any time); the look sets it on
-- each of Bagnon's windows.

local BAGNON_FRAMES = { "inventory", "bank", "vault", "guild" }

local function bagnon()
	local addon = _G.Bagnon
	if type(addon) == "table" and type(addon.Skins) == "table" and type(addon.Skins.Register) == "function" then return addon end
end

local function dressBagnon(bg)
	if not bg.stoaDressed then
		bg.stoaDressed = true
		UI.windowPanel(bg, 0.96, { header = 34 })
	end
end

local function registerBagnon()
	local addon = bagnon()
	if not addon or addon.Skins:Get("Stoa") then return end
	pcall(addon.Skins.Register, addon.Skins, {
		id = "Stoa", template = "BackdropTemplate",
		x = 0, y = 0, x1 = 0, y1 = 0, margin = 2, inset = 4, closeX = -2, closeY = -2,
		load = function(bg) xpcall(dressBagnon, Stoa.catch, bg) end,
		-- Stoa's panel takes the theme's colours, whatever Bagnon's are set to.
		borderColor = function() end,
		centerColor = function() end,
	})
end

local function bagnonProfiles()
	local addon = bagnon()
	local player = addon and addon.player
	return type(player) == "table" and type(player.profile) == "table" and player.profile or nil
end

local function bagnonRefresh()
	local addon = bagnon()
	if addon and type(addon.SendSignal) == "function" then pcall(addon.SendSignal, addon, "UPDATE_ALL") end
end

-- Details -------------------------------------------------------------------------
-- Details has a skin list too. Stoa's is built on Details' own Minimalistic
-- skin, with no panel behind the rows (like Stoa's own meters), faint bars in
-- class colour and Stoa's type.

local function details()
	local addon = _G.Details
	if type(addon) == "table" and type(addon.InstallSkin) == "function" and type(addon.GetSkin) == "function" then return addon end
end

local function registerDetails()
	local addon = details()
	if not addon or addon:GetSkin("Stoa") then return end
	local base = addon:GetSkin("Minimalistic")
	if type(base) ~= "table" then return end
	local skin = copy(base)
	skin.author, skin.desc, skin.no_cache, skin.is_cached_skin = "Stoa", "Stoa's quiet meters: no panel, faint bars, Stoa's type.", true, nil
	local props = skin.instance_cprops or {}
	skin.instance_cprops = props
	props.bg_alpha = 0
	props.color = { 0, 0, 0, 0 }
	props.backdrop_texture = "None"
	if type(props.attribute_text) == "table" then props.attribute_text.text_face = FONT_DISPLAY end
	local rows = props.row_info or {}
	props.row_info = rows
	rows.font_face, rows.font_face_file, rows.font_size = FONT_UI, FONT_UI_FILE, 11
	rows.height = 18
	rows.texture, rows.texture_file = BAR, BAR_FILE
	rows.texture_class_colors = true
	rows.alpha = 0.35
	rows.textL_outline, rows.textR_outline = true, true
	rows.texture_background, rows.texture_background_file = BAR, BAR_FILE
	rows.fixed_texture_background_color = { 0, 0, 0, 0 }
	pcall(addon.InstallSkin, addon, "Stoa", skin)
end

local function detailsInstances()
	local addon = details()
	if not addon or type(addon.GetInstance) ~= "function" then return {} end
	local list = {}
	for id = 1, 10 do
		local ok, instance = pcall(addon.GetInstance, addon, id)
		if ok and type(instance) == "table" and type(instance.ChangeSkin) == "function" then list[#list + 1] = { id = id, instance = instance } end
	end
	return list
end

-- The looks -------------------------------------------------------------------------

local LOOKS = {
	{
		key = "questie", folder = "Questie", name = "Questie", what = "its quest tracker",
		available = function() return questieProfile() ~= nil end,
		apply = function(before)
			local profile = questieProfile()
			for key, value in pairs(QUESTIE_KEYS) do
				if before[key] == nil then before[key] = copy(profile[key]) end
				profile[key] = value
			end
			questieRefresh()
		end,
		restore = function(before)
			local profile = questieProfile()
			for key in pairs(QUESTIE_KEYS) do profile[key] = copy(before[key]) end
			questieRefresh()
		end,
	},
	{
		key = "bagnon", folder = "Bagnon", name = "Bagnon", what = "its bag windows",
		available = function() return bagnon() ~= nil and bagnonProfiles() ~= nil end,
		apply = function(before)
			local profiles = bagnonProfiles()
			for _, id in ipairs(BAGNON_FRAMES) do
				local profile = profiles[id]
				if type(profile) == "table" then
					if before[id] == nil then before[id] = profile.skin or false end
					profile.skin = "Stoa"
				end
			end
			bagnonRefresh()
		end,
		restore = function(before)
			local profiles = bagnonProfiles()
			for _, id in ipairs(BAGNON_FRAMES) do
				local profile = profiles[id]
				if type(profile) == "table" and before[id] ~= nil then profile.skin = before[id] or nil end
			end
			bagnonRefresh()
		end,
	},
	{
		key = "details", folder = "Details", name = "Details", what = "its meter windows",
		available = function() return details() ~= nil and details():GetSkin("Stoa") ~= nil end,
		apply = function(before)
			for _, each in ipairs(detailsInstances()) do
				local key = tostring(each.id)
				if before[key] == nil then before[key] = each.instance.skin or false end
				pcall(each.instance.ChangeSkin, each.instance, "Stoa")
			end
		end,
		restore = function(before)
			for _, each in ipairs(detailsInstances()) do
				local skin = before[tostring(each.id)]
				if skin then pcall(each.instance.ChangeSkin, each.instance, skin) end
			end
		end,
	},
}

Looks.list = LOOKS

local function ready(look)
	if not isLoaded(look.folder) then return false end
	local ok, yes = pcall(look.available)
	return ok and yes
end

-- For the welcome page: whether a look can be offered, and whether it's on.
function Looks:Ready(look)
	return ready(look)
end

function Looks:IsOn(look)
	local entry = saved()[look.key]
	return type(entry) == "table" and entry.on or false
end

-- Puts a look on (true) or takes it off (false), remembering the answer.
function Looks:Set(look, on)
	local entry = saved()[look.key]
	if type(entry) ~= "table" then entry = { before = {} } end
	entry.before = entry.before or {}
	if on then
		xpcall(look.apply, Stoa.catch, entry.before)
		entry.on = true
	else
		if entry.on then xpcall(look.restore, Stoa.catch, entry.before) end
		entry.on = false
		entry.before = {}
	end
	saved()[look.key] = entry
end

-- Puts back on any look Stoa wears, for windows an addon made since (Details
-- makes a new window with its default skin).
function Looks:Refresh()
	for _, look in ipairs(LOOKS) do
		local entry = saved()[look.key]
		if type(entry) == "table" and entry.on and ready(look) then xpcall(look.apply, Stoa.catch, entry.before) end
	end
end

-- The offer -------------------------------------------------------------------------

function Looks:Ask(look)
	if not self.page then
		self.page = Stoa.Conflicts:Page("StoaLooksPage",
			function() self:Answer(true) end,
			function() self:Answer(false) end)
	end
	local page = self.page
	self.asking = look
	page.title:SetText(look.name .. " in Stoa's look")
	page.body:SetText(("Stoa can dress %s in its own type and colours, so %s sits with the rest of your screen. %s keeps working exactly as it does now."):format(
		look.name, look.what, look.name))
	page.note:SetText(("You can change it back any time with /stoa looks, or in %s's own settings."):format(look.name))
	page.left.text:SetText("Use Stoa's look")
	page.right.text:SetText("Leave it")
	page:Show()
end

function Looks:Answer(on)
	local look = self.asking
	if not look then return end
	self.asking = nil
	self.page:Hide()
	self:Set(look, on)
	if on then
		Stoa:Print(("%s now wears Stoa's look. /stoa looks to change."):format(look.name))
	end
	self:Next()
end

-- Offers each look not answered before, one at a time.
function Looks:Next()
	if Stoa.Conflicts.asking then return end
	-- The welcome page offers them itself.
	if Stoa.Welcome and Stoa.Welcome:Pending() then return end
	for _, look in ipairs(LOOKS) do
		local entry = saved()[look.key]
		if not look.offered and type(entry) ~= "table" and ready(look) then
			look.offered = true
			Stoa:AfterCombat(function() self:Ask(look) end)
			return
		end
	end
end

Stoa:On("PLAYER_LOGIN", function()
	media()
	xpcall(registerBagnon, Stoa.catch)
	xpcall(registerDetails, Stoa.catch)
end)

Stoa:On("STOA_READY", function()
	C_Timer.After(2, function() Looks:Refresh() end)
	-- After the welcome page and any "two addons, one job" question.
	C_Timer.After(8, function() Looks:Next() end)
end)

-- Bagnon's skin draws Stoa's panel in the theme's colours: a new theme
-- repaints it through Stoa's own panels, nothing to do here.

Stoa.commands.looks = function()
	local any = false
	for _, look in ipairs(LOOKS) do
		if ready(look) then
			any = true
			local entry = saved()[look.key]
			local on = type(entry) == "table" and entry.on
			Stoa:Print(("%s: %s."):format(look.name, on and "in Stoa's look" or "its own look"))
			look.offered = nil
			if type(entry) == "table" and not entry.on then saved()[look.key] = nil end
		end
	end
	if not any then
		Stoa:Print("None of the addons Stoa can dress are here (Questie, Bagnon, Details).")
		return
	end
	-- Asks about each one again, starting with those in Stoa's look.
	for _, look in ipairs(LOOKS) do
		local entry = saved()[look.key]
		if type(entry) == "table" and entry.on then
			Looks.asking = look
			look.offered = true
			Looks:Ask(look)
			Looks.page.title:SetText(look.name .. " is in Stoa's look")
			Looks.page.left.text:SetText("Keep Stoa's look")
			Looks.page.right.text:SetText("Its own look")
			return
		end
	end
	Looks:Next()
end
