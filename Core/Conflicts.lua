-- Stoa: other addons doing the same job.
-- When a bag, nameplate, chat, tooltip, bar, minimap, group frame or
-- click-casting addon is loaded beside Stoa, the two would dress the same
-- Blizzard frames (or draw two sets of frames). At login Stoa looks for the
-- well-known ones and asks once which should do the job:
--   Keep theirs: Stoa's own part steps aside, remembered account-wide. If the
--   other addon is later removed, Stoa's part comes back by itself.
--   Use Stoa's: the other addon is turned off and the UI reloads.
-- Until a choice is made, Stoa's part steps aside, so nothing fights.
-- A full UI suite (ElvUI and the like) covers everything, so that question
-- is which of the two addons to run at all.
-- /stoa addons lists what was found and asks again.
local _, ns = ...
local Stoa = ns.Stoa
local UI = Stoa.UI

local Conflicts = {}
Stoa.Conflicts = Conflicts

-- Each rule: the Stoa modules it covers, what they do (for the question) and
-- the other addons by folder name, with the name players know them by.
local RULES = {
	{
		key = "suite", job = "your whole screen", suite = true,
		addons = {
			{ "ElvUI", "ElvUI" }, { "Tukui", "Tukui" }, { "SpartanUI", "SpartanUI" },
			{ "NDui", "NDui" }, { "GW2_UI", "GW2 UI" }, { "KkthnxUI", "KkthnxUI" },
			{ "LUI", "LUI" }, { "RealUI", "RealUI" },
		},
	},
	{
		key = "bags", job = "your bags", modules = { "Bags" },
		addons = {
			{ "Bagnon", "Bagnon" }, { "Baganator", "Baganator" }, { "AdiBags", "AdiBags" },
			{ "ArkInventory", "ArkInventory" }, { "BetterBags", "BetterBags" },
			{ "Combuctor", "Combuctor" }, { "LiteBag", "LiteBag" }, { "Inventorian", "Inventorian" },
			{ "Sorted", "Sorted" },
		},
	},
	{
		key = "plates", job = "nameplates", modules = { "Plates" },
		addons = {
			{ "Plater", "Plater" }, { "TidyPlates_ThreatPlates", "Threat Plates" },
			{ "TidyPlates", "TidyPlates" }, { "Kui_Nameplates", "KuiNameplates" },
			{ "NeatPlates", "NeatPlates" }, { "Platynator", "Platynator" },
		},
	},
	{
		key = "chat", job = "the chat", modules = { "ChatLook" },
		addons = {
			{ "Prat-3.0", "Prat" }, { "Chattynator", "Chattynator" },
			{ "Glass", "Glass" }, { "Chatter", "Chatter" },
		},
	},
	{
		key = "tooltip", job = "tooltips", modules = { "Tooltip" },
		addons = { { "TipTac", "TipTac" }, { "TinyTooltip", "TinyTooltip" }, { "TipTop", "TipTop" } },
	},
	{
		key = "bars", job = "action bars", modules = { "ActionBars" },
		addons = { { "Bartender4", "Bartender" }, { "Dominos", "Dominos" } },
	},
	{
		key = "minimap", job = "the minimap", modules = { "Minimap" },
		addons = { { "SexyMap", "SexyMap" }, { "BasicMinimap", "BasicMinimap" } },
	},
	{
		key = "group", job = "party and raid frames", modules = { "Party", "Raid" },
		addons = {
			{ "VuhDo", "VuhDo" }, { "Grid2", "Grid2" }, { "Cell", "Cell" },
			{ "HealBot", "HealBot" }, { "ShadowedUnitFrames", "Shadowed Unit Frames" },
		},
	},
	{
		key = "clicks", job = "click-casting", modules = { "ClickCast" },
		addons = { { "Clique", "Clique" } },
	},
	{
		key = "movers", job = "moving Blizzard's windows", modules = { "WindowMover" },
		addons = { { "BlizzMove", "BlizzMove" }, { "MoveAny", "MoveAny" } },
	},
	{
		key = "map", job = "the world map", modules = { "Map" },
		addons = { { "Mapster", "Mapster" } },
	},
}

local function isLoaded(folder)
	if C_AddOns and C_AddOns.IsAddOnLoaded then return C_AddOns.IsAddOnLoaded(folder) end
	return IsAddOnLoaded and IsAddOnLoaded(folder)
end

local function disable(folder)
	if C_AddOns and C_AddOns.DisableAddOn then
		C_AddOns.DisableAddOn(folder)
	elseif DisableAddOn then
		DisableAddOn(folder)
	end
end

local function choices()
	Stoa.db.addons = Stoa.db.addons or {}
	return Stoa.db.addons
end

-- "Bagnon", "Bagnon and AdiBags", "Bagnon, AdiBags and Sorted".
local function names(found)
	local list = {}
	for i, addon in ipairs(found) do list[i] = addon[2] end
	if #list < 2 then return list[1] or "" end
	return table.concat(list, ", ", 1, #list - 1) .. " and " .. list[#list]
end

-- Modules held back this session, by name, with the rule that holds them.
local aside = {}
local found = {}

function Conflicts:SteppedAside(name)
	return aside[name]
end

-- Called once at login, before modules are enabled.
function Conflicts:Check()
	wipe(aside)
	wipe(found)
	for _, rule in ipairs(RULES) do
		local loaded = {}
		for _, addon in ipairs(rule.addons) do
			if isLoaded(addon[1]) then loaded[#loaded + 1] = addon end
		end
		-- A part the player already switched off has nothing to fight over.
		local running = rule.suite
		for _, name in ipairs(rule.modules or {}) do
			local settings = Stoa.db.modules[name]
			if not settings or settings.enabled ~= false then running = true end
		end
		if #loaded > 0 and running then
			found[#found + 1] = { rule = rule, loaded = loaded }
			if not rule.suite then
				for _, name in ipairs(rule.modules) do aside[name] = rule end
			end
		end
	end
end

-- The question ------------------------------------------------------------------

local WIDTH, HEIGHT = 460, 220
local PAD = 26

function Conflicts:Build()
	local page = CreateFrame("Frame", "StoaAddonsPage", UIParent)
	page:SetSize(WIDTH, HEIGHT)
	page:SetPoint("CENTER", 0, 120)
	page:SetFrameStrata("DIALOG")
	page:EnableMouse(true)
	page:SetMovable(true)
	page:RegisterForDrag("LeftButton")
	page:SetScript("OnDragStart", page.StartMoving)
	page:SetScript("OnDragStop", page.StopMovingOrSizing)
	page:Hide()
	UI.windowPanel(page, 0.97, { header = 64, footer = 58 })
	self.page = page

	local title = UI.text(page, "serif", Stoa.typeSize.title, "text", "LEFT")
	title:SetPoint("TOPLEFT", PAD, -PAD + 4)
	title:SetText("Two addons, one job")

	local body = UI.text(page, "sans", Stoa.typeSize.label, "text", "LEFT")
	body:SetPoint("TOPLEFT", PAD, -82)
	body:SetPoint("RIGHT", page, "RIGHT", -PAD, 0)
	body:SetWordWrap(true)
	page.body = body

	local note = UI.text(page, "italic", Stoa.typeSize.body, "muted", "LEFT")
	note:SetPoint("TOPLEFT", body, "BOTTOMLEFT", 0, -10)
	note:SetPoint("RIGHT", page, "RIGHT", -PAD, 0)
	note:SetWordWrap(true)
	page.note = note

	page.theirs = UI.button(page, "", 200, function() self:Answer("theirs") end)
	page.theirs:SetPoint("BOTTOMLEFT", PAD, PAD - 10)
	page.ours = UI.button(page, "", 200, function() self:Answer("ours") end)
	page.ours:SetPoint("BOTTOMRIGHT", -PAD, PAD - 10)
end

function Conflicts:Ask(entry)
	if not self.page then self:Build() end
	local page, rule = self.page, entry.rule
	local them = names(entry.loaded)
	self.asking = entry
	local single = #entry.loaded == 1
	local everyone = { unpack(entry.loaded) }
	everyone[#everyone + 1] = { "Stoa", "Stoa" }
	page.body:SetText(("%s %s look after %s. Pick one so they don't get in each other's way."):format(names(everyone), single and "both" or "all", rule.job))
	page.theirs.text:SetText(single and ("Keep " .. them) or "Keep theirs")
	if rule.suite then
		page.ours.text:SetText("Use Stoa")
		page.note:SetText("Either way the other one is turned off and the game reloads.")
	else
		page.ours.text:SetText("Use Stoa's")
		page.note:SetText(("Stoa's part waits until you choose. Using Stoa's turns %s off and reloads; /stoa addons asks again."):format(them))
	end
	page:Show()
end

function Conflicts:Answer(choice)
	local entry = self.asking
	if not entry then return end
	self.asking = nil
	self.page:Hide()
	local rule = entry.rule
	if choice == "ours" then
		for _, addon in ipairs(entry.loaded) do disable(addon[1]) end
		choices()[rule.key] = nil
		ReloadUI()
	elseif rule.suite then
		disable("Stoa")
		ReloadUI()
	else
		choices()[rule.key] = "theirs"
		Stoa:Print(("Leaving %s to %s. /stoa addons to change."):format(rule.job, names(entry.loaded)))
		self:Next()
	end
end

-- Asks about each clash not settled before, one at a time.
function Conflicts:Next()
	local saved = choices()
	for _, entry in ipairs(found) do
		if not entry.asked and saved[entry.rule.key] ~= "theirs" then
			entry.asked = true
			Stoa:AfterCombat(function() self:Ask(entry) end)
			return
		end
	end
end

Stoa:On("STOA_READY", function()
	if #found == 0 then return end
	C_Timer.After(4, function() Conflicts:Next() end)
end)

Stoa.commands.addons = function()
	if #found == 0 then
		Stoa:Print("No other addon is doing one of Stoa's jobs.")
		return
	end
	for _, entry in ipairs(found) do
		Stoa:Print(("%s also %s after %s."):format(names(entry.loaded), #entry.loaded == 1 and "looks" or "look", entry.rule.job))
		choices()[entry.rule.key] = nil
		entry.asked = nil
	end
	Conflicts:Next()
end
