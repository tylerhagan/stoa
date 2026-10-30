-- Stoa: its place under Options > AddOns. Stoa's own settings window
-- (Config/Window.lua) holds every setting; the game's panel keeps a page
-- that opens it, so players who look there find it.
local _, ns = ...
local Stoa = ns.Stoa

local category

local function build()
	local layout
	category, layout = Settings.RegisterVerticalLayoutCategory("Stoa")
	if CreateSettingsButtonInitializer then
		layout:AddInitializer(CreateSettingsButtonInitializer("Stoa settings", "Open", function()
			-- The game's panel covers the screen, so step out of its way first.
			if not InCombatLockdown() and SettingsPanel and SettingsPanel:IsShown() then HideUIPanel(SettingsPanel) end
			Stoa:OpenSettings()
		end, "Every Stoa setting, by page, with search. Also /stoa.", true))
		layout:AddInitializer(CreateSettingsButtonInitializer("Safe mode", "Turn on", function()
			Stoa.commands.safe()
		end, "If a Stoa skin ever breaks the game's own windows: turns off every skin that reaches into them and reloads. /stoa safe", true))
	end
	Settings.RegisterAddOnCategory(category)
end

Stoa:On("STOA_READY", build)

function Stoa:OpenSettings(page)
	if InCombatLockdown() then
		self:Print("Settings open once combat ends.")
		self:AfterCombat(function() Stoa.SettingsWindow:Show(page) end)
		return
	end
	Stoa.SettingsWindow:Show(page)
end

-- /stoa safe: if a Stoa skin ever breaks Blizzard's own UI, this turns off
-- every piece that reaches into Blizzard frames and reloads. Each can be
-- turned back on in Stoa's settings (/stoa).
Stoa.commands.safe = function()
	local m = Stoa.modules
	if m.Grimoire then
		m.Grimoire.db.houseChat = false
		m.Grimoire.db.houseMenu = false
		m.Grimoire.db.hideBarArt = false
	end
	if m.ActionBars then m.ActionBars.db.enabled = false end
	if m.Windows then m.Windows.db.enabled = false end
	if m.MoreWindows then m.MoreWindows.db.enabled = false end
	if m.Tooltip then m.Tooltip.db.enabled = false end
	if m.Bags then m.Bags.db.enabled = false end
	if m.Character then m.Character.db.enabled = false end
	if m.Meters then m.Meters.db.enabled = false end
	if m.Top then m.Top.db.enabled = false end
	if m.Plates then m.Plates.db.enabled = false end
	if m.Swing then m.Swing.db.enabled = false end
	if m.Map then m.Map.db.enabled = false end
	if m.Chat then m.Chat.db.enabled = false end
	if m.QuestReward then m.QuestReward.db.enabled = false end
	ReloadUI()
end
