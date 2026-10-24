-- Stoa: settings panel, built on the game's Settings API so it lives under
-- Options > AddOns alongside everything else.
local _, ns = ...
local Stoa = ns.Stoa

local category, layout

local function checkbox(variableTbl, key, name, tooltip, default, onChange)
	local setting = Settings.RegisterAddOnSetting(category, "Stoa_" .. name:gsub("%W", ""), key, variableTbl, Settings.VarType.Boolean, name, default)
	if onChange then setting:SetValueChangedCallback(onChange) end
	Settings.CreateCheckbox(category, setting, tooltip)
	return setting
end

local function dropdown(variableTbl, key, name, tooltip, default, options, onChange)
	local setting = Settings.RegisterAddOnSetting(category, "Stoa_" .. name:gsub("%W", ""), key, variableTbl, Settings.VarType.String, name, default)
	if onChange then setting:SetValueChangedCallback(onChange) end
	Settings.CreateDropdown(category, setting, function()
		local container = Settings.CreateControlTextContainer()
		for _, option in ipairs(options) do
			container:Add(option[1], option[2])
		end
		return container:GetData()
	end, tooltip)
	return setting
end

local function header(text)
	layout:AddInitializer(CreateSettingsListSectionHeaderInitializer(text))
end

local function build()
	category, layout = Settings.RegisterVerticalLayoutCategory("Stoa")

	-- Setup
	header("Setup")
	if CreateSettingsButtonInitializer then
		layout:AddInitializer(CreateSettingsButtonInitializer("Welcome page", "Open", function()
			Stoa.Welcome:Show()
		end, "Choose what each spec plays and your theme, and preview the party frames and combat. /stoa welcome", true))
		layout:AddInitializer(CreateSettingsButtonInitializer("Backup", "Open", function()
			Stoa.Backup:Show()
		end, "All of Stoa's settings as one line of text to keep safe, and a place to paste one back. /stoa backup", true))
		layout:AddInitializer(CreateSettingsButtonInitializer("Report a problem", "Open", function()
			Stoa.Report:Show()
		end, "Your setup and any errors Stoa caught this session, ready to copy and send. /stoa report", true))
	end

	-- Look
	header("Look")
	local themes = {}
	for _, name in ipairs(Stoa.themeOrder) do
		table.insert(themes, { name, name == "Class" and "Your class (follows the character)" or name })
	end
	dropdown(Stoa.db, "theme", "Theme", "Bone is warm and class-tinted. Tide is all blues. Graphite is greyscale with one amber accent. Each class has its own, and Your class picks the one for whoever you log in. All suit red-green colour blindness; for other kinds, set Colour vision below.", "Bone", themes, function(_, value)
		Stoa:SetTheme(value)
	end)
	local visions = {}
	for _, name in ipairs(Stoa.visionOrder) do
		table.insert(visions, { name, Stoa.VISION_LABELS[name] })
	end
	dropdown(Stoa.db, "vision", "Colour vision", "Swaps the warning, accent, mana and dispel colours for a set made for that kind of colour blindness, on top of any theme. Every state also keeps its word or shape. Modes other than Standard show names in the theme's text colour rather than class colours.", "Standard", visions, function(_, value)
		Stoa:SetVision(value)
	end)
	checkbox(Stoa.modules.Grimoire.db, "enabled", "Show the Grimoire console", "The ink console along the bottom of the screen. Takes effect after /reload.", true)
	checkbox(Stoa.modules.Grimoire.db, "art", "Leather console", "Dress the console in tooled leather, its lines in your theme's accent. Off gives the plain ink panel. Takes effect after /reload.", true)
	checkbox(Stoa.modules.Grimoire.db, "houseChat", "Hold chat in the console", "Chat sits on the console's left page and Stoa's notes appear in chat. Takes effect after /reload.", true)
	checkbox(Stoa.modules.Minimap.db, "enabled", "Style the minimap", "Rings in the theme colours, serif zone name, wheel to zoom. Takes effect after /reload.", true)
	checkbox(Stoa.modules.ActionBars.db, "enabled", "Rounded action buttons", "Rounded-square icons with a hairline edge, dim sockets for empty slots. Takes effect after /reload.", true)
	checkbox(Stoa.modules.CombatBar.db, "enabled", "Combat bar under the Halo", "In combat, a compact row of your main bar's spells under the Halo, with their keys. Your keybinds keep working as before. Takes effect after /reload.", true)
	local rowChoices = { { "1", "Main bar only" }, { "2", "Main + bottom-left" }, { "3", "Main + both bottom bars" } }
	local function relayout() Stoa:AfterCombat(function() Stoa.modules.CombatBar:Layout() end) end
	dropdown(Stoa.modules.CombatBar.db, "rows", "Combat rows", "How many rows show under the Halo in combat when you tank or deal damage. Each extra row is a step smaller and shows only the buttons you've filled.", "2", rowChoices, relayout)
	dropdown(Stoa.modules.CombatBar.db, "healerRows", "Combat rows when healing", "The same, for healing. One keeps the group frames close under your spells.", "1", rowChoices, relayout)
	checkbox(Stoa.modules.ActionBars.db, "combatHide", "Hand the bars to the Halo in combat", "With the combat bar on, the console's action bars step aside in combat and only the compact bar under the Halo shows. Your keybinds keep working.", true, function(_, value)
		Stoa.modules.ActionBars:SetOption("combatHide", value)
	end)
	checkbox(Stoa.modules.ActionBars.db, "hoverTray", "Extra rows on mouseover", "Out of combat only your main bar shows in the console; the other rows come up while you mouse over the bars. Off shows every row out of combat.", false, function(_, value)
		Stoa.modules.ActionBars:SetOption("hoverTray", value)
	end)
	checkbox(Stoa.modules.Windows.db, "enabled", "Restyle Blizzard windows", "Quest, gossip, merchant, trainer and bag windows on Stoa's dark panels with light text. Takes effect after /reload.", true)
	checkbox(Stoa.modules.MoreWindows.db, "enabled", "Restyle more windows", "Spellbook, talents, world map border, mail, auction house, group finder, friends and guild, game menu and settings on the same dark panels. Takes effect after /reload.", true)
	checkbox(Stoa.modules.Bags.db, "enabled", "Restyle bags", "Bags with rounded slots, a coloured edge by quality plus a corner mark for epic and above, item level on gear, free slots, your money in letters and a Sort button. Takes effect after /reload.", true)
	dropdown(Stoa.modules.Bags.db, "bagMode", "Bag layout", "One combined bag, or a window for each bag. You can still switch from the bag's own menu; this applies when you change it here.", "combined", { { "combined", "One combined bag" }, { "separate", "Separate bags" } }, function()
		Stoa.modules.Bags.db.appliedMode = nil
		Stoa.modules.Bags:ApplyMode()
	end)
	checkbox(Stoa.modules.Character.db, "enabled", "Restyle the character sheet", "A dark panel, item level and quality edges on every slot, the words WORN and BROKEN on gear that needs repair, and an average item level line. The inspect window gets item levels too. Takes effect after /reload.", true)
	checkbox(Stoa.modules.Top.db, "enabled", "Restyle the top of the screen", "Buffs as cropped icons with quiet timers, the quest tracker in Stoa's type without the gold bars, and the minimap's zone header on a dark panel with its buttons waiting for the mouse. Takes effect after /reload.", true)
	checkbox(Stoa.modules.Plates.db, "enabled", "Restyle nameplates", "Flat bars coloured by what you can do: amber for enemies, pale gold for neutral, blue for friends, and grey only for tapped or dead. A bone edge marks your target. Takes effect after /reload.", true)
	checkbox(Stoa.modules.Swing.db, "enabled", "Restyle the swing timer", "Blizzard's swing timer as a flat bar in a rounded dark track: pale gold for the main hand, blue for the off hand. Place it in Edit Mode. Takes effect after /reload.", true)
	checkbox(Stoa.modules.Meters.db, "enabled", "Restyle the damage meter", "Blizzard's damage and healing meters as words over the world with no panel: faint bone bars, your own bar in the accent, class colour on names only. Takes effect after /reload.", true)
	checkbox(Stoa.modules.Meters.db, "place", "Meters in the top-left corner", "Every meter window shown sits side by side in one strip flush with the top-left corner of the screen, the same size, in and out of combat. Off leaves them where Edit Mode and your dragging put them.", true, function(_, value)
		if value then Stoa.modules.Meters:Place() end
	end)
	checkbox(Stoa.modules.Grimoire.db, "houseMenu", "Bags and menu in the console corner", "Moves the bag slots and game menu off the action bar row into the console's bottom-right corner, quiet until you mouse over them. Takes effect after /reload.", true)
	checkbox(Stoa.modules.Grimoire.db, "hideBarArt", "Hide action bar art", "Removes the gryphons and border so the bar sits on the ink. Takes effect after /reload.", true)

	-- Halo
	local halo = Stoa.modules.Halo.db
	local party = Stoa.modules.Party.db
	header("Combat")
	checkbox(halo, "enabled", "Show the Halo in combat", "Health, mana, your signature spell, target and cast around your character. Takes effect after /reload.", true)
	checkbox(halo, "hidePlayerFrame", "Hide Blizzard's player frame", "The seal and the Halo show the same. Also hides Blizzard's cast bar. Takes effect after /reload.", true)
	checkbox(halo, "hideTargetFrame", "Hide Blizzard's target frame", "Stoa shows your target beside the Halo. Takes effect after /reload.", true)
	checkbox(party, "enabled", "Show Stoa party cards", "Large beside the Halo when you heal, compact on the left otherwise. Takes effect after /reload.", true)
	checkbox(party, "quietCards", "Quiet group frames when not healing", "Tanking or dealing damage, party and raid cards show health and only the words you can act on: a debuff you can dispel, dead or offline. No buff words.", true, function()
		if Stoa.modules.Party.cards then Stoa.modules.Party:UpdateAll() end
	end)
	checkbox(party, "hideBlizzardParty", "Hide Blizzard's party frames", "Takes effect after /reload.", true)
	local raid = Stoa.modules.Raid.db
	checkbox(raid, "enabled", "Show Stoa raid frames", "A grid of compact cards, one column per group. Takes effect after /reload.", true)
	checkbox(raid, "hideBlizzardRaid", "Hide Blizzard's raid frames", "Takes effect after /reload.", true)
	checkbox(Stoa.modules.ClickCast.db, "enabled", "Click-casting", "Mouse bindings on Stoa's party and raid frames. Set them with /stoa clicks. Takes effect after /reload.", true)
	if CreateSettingsButtonInitializer then
		layout:AddInitializer(CreateSettingsButtonInitializer("Click bindings", "Open", function()
			Stoa.modules.ClickCast:TogglePage()
		end, "Fifteen bindings per role: five mouse buttons, plain, Shift and Ctrl.", true))
	end

	-- Dungeon kit
	local kit = Stoa.modules.Kit.db
	header("Levelling and dungeons")
	checkbox(kit, "xpRate", "Experience pace on the console", "Experience an hour and time to level under the Journey bar, worked out over the last half hour and started again at each level. /stoa xp prints it. Hidden at the highest level.", true, function()
		Stoa.modules.Kit:UpdateConsole()
	end)
	checkbox(kit, "questLine", "Nearest quest on the console", "When you are not in a group, one line under Journey with the progress of the watched quest nearest you.", true, function()
		Stoa.modules.Kit:UpdateConsole()
	end)
	checkbox(kit, "bigNumber", "Big number for the pull timer", "/stoa pull 10 shows a large number in the middle of the screen when the game's own group countdown can't be used (you aren't a leader, or you are alone). Group chat gets 3, 2, 1 when you are grouped.", true)
	checkbox(kit, "readyCheck", "Ready check dress and words", "The ready check prompt on Stoa's panel, and READY, NOT READY or WAITING on each party card while it runs. Takes effect after /reload.", true)
	checkbox(kit, "kickCue", "KICK cue on the target", "The word KICK on the target plaque while it casts something you can interrupt.", true, function()
		Stoa.modules.Kit:UpdateKick()
	end)

	-- Move frames
	header("Move frames")
	if CreateSettingsButtonInitializer then
		layout:AddInitializer(CreateSettingsButtonInitializer("Move frames", "Unlock", function()
			-- Settings covers the screen, so step out of its way first.
			if not InCombatLockdown() and SettingsPanel and SettingsPanel:IsShown() then HideUIPanel(SettingsPanel) end
			Stoa:ToggleMovers()
		end, "Drag the Halo, party, raid, target, cast bar and more where you like. Each role keeps its own spots. Arrow keys nudge, right-click puts one back. /stoa unlock", true))
	end

	-- Roles
	header("Roles for this character")
	local roles = { { "AUTO", "Class default" } }
	for _, role in ipairs(Stoa.ROLES) do
		table.insert(roles, { role, Stoa.ROLE_LABELS[role] })
	end
	for slot = 1, 2 do
		dropdown(Stoa.char.roles, "slot" .. slot, ("Spec %d plays as"):format(slot), "Stoa picks the layout from this when you change spec.", "AUTO", roles, function()
			Stoa:UpdateRole()
		end)
	end

	-- Comforts
	local comforts = Stoa.modules.Comforts.db
	header("Comforts")
	checkbox(comforts, "fastLoot", "Faster loot", "With auto loot on, everything lands in your bags the moment the loot window would open. Hold Shift to see the window.", true)
	checkbox(comforts, "farCamera", "Pull the camera further out", "Raises the camera's maximum zoom distance.", true, function() Stoa.modules.Comforts:Camera() end)
	checkbox(comforts, "skipGossip", "Skip one-option gossip", "When an NPC has no quests and only one thing to say, Stoa picks it for you. Hold Shift to stop.", true)
	checkbox(comforts, "acceptQuests", "Accept quests", "Picks up offered quests. Hold Shift to read one first.", false)
	checkbox(comforts, "turnInQuests", "Hand in quests", "Hands in finished quests. A quest with a choice of reward always waits for you. Hold Shift to stop.", false)
	checkbox(comforts, "skipCinematics", "Skip cinematics", "Cancels cinematics and movies as they start. Hold Shift to watch.", false)
	checkbox(comforts, "quietErrors", "Quiet errors in combat", "Hides the red \"Not enough mana\" and \"Out of range\" text while you fight; it comes back after.", false)

	-- Merchant
	local merchant = Stoa.modules.Merchant.db
	header("Merchants")
	checkbox(merchant, "sellJunk", "Sell grey junk", nil, true)
	checkbox(merchant, "autoRepair", "Repair gear", nil, true)
	checkbox(merchant, "useGuildFunds", "Use guild funds when allowed", nil, true)

	-- Moving Blizzard windows
	local windows = Stoa.modules.WindowMover.db
	header("Moving windows")
	checkbox(windows, "enabled", "Hold a key and drag to move windows", "Quest, gossip, merchant, bags, character, spellbook, mail and similar windows: hold the key and drag the window by its title or edge. Each keeps its spot when it opens again; the key and right-click puts one back. /stoa windows reset puts them all back. Takes effect after /reload.", true)
	dropdown(windows, "modifier", "Key to hold", nil, "SHIFT", { { "SHIFT", "Shift" }, { "ALT", "Alt" }, { "CTRL", "Ctrl" } })

	-- Social
	local social = Stoa.modules.Social.db
	header("Social")
	checkbox(social, "acceptFriendInvites", "Accept friend and guild invites", nil, true)
	checkbox(social, "declineStrangerInvites", "Decline stranger invites", nil, false)
	checkbox(social, "declineStrangerDuels", "Decline stranger duels", nil, true)
	checkbox(social, "declineStrangerGuildInvites", "Decline stranger guild invites", nil, true)

	-- Auto-invite
	local invite = Stoa.modules.AutoInvite.db
	header("Auto-invite")
	checkbox(invite, "enabled", "Invite on whispered \"inv\"", "Friends and guild only. Change the keywords with /stoa keywords <words>.", true)
	checkbox(invite, "strangersToo", "Invite strangers too", nil, false)
	checkbox(invite, "convertToRaid", "Make a raid when full", nil, true)
	checkbox(invite, "guildChat", "Keyword works in guild chat", "A guildmate saying just the keyword in guild chat gets an invite.", false)
	if CreateSettingsButtonInitializer then
		layout:AddInitializer(CreateSettingsButtonInitializer("Company", "Open", function()
			Stoa.modules.Roster:Toggle()
		end, "Friends and guildmates who are online: click to whisper, Shift-click to invite. /stoa friends", true))
	end

	Settings.RegisterAddOnCategory(category)
end

Stoa:On("STOA_READY", build)

function Stoa:OpenSettings()
	if not category then return end
	if InCombatLockdown() then
		self:Print("Settings open once combat ends.")
		self:AfterCombat(function() Settings.OpenToCategory(category:GetID()) end)
		return
	end
	Settings.OpenToCategory(category:GetID())
end

-- /stoa safe: if a Stoa skin ever breaks Blizzard's own UI, this turns off
-- every piece that reaches into Blizzard frames and reloads. Each can be
-- turned back on in Options > AddOns > Stoa.
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
	if m.Bags then m.Bags.db.enabled = false end
	if m.Character then m.Character.db.enabled = false end
	if m.Meters then m.Meters.db.enabled = false end
	if m.Top then m.Top.db.enabled = false end
	if m.Plates then m.Plates.db.enabled = false end
	if m.Swing then m.Swing.db.enabled = false end
	ReloadUI()
end
