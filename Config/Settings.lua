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

	-- Look
	header("Look")
	local themes = {}
	for _, name in ipairs(Stoa.themeOrder) do
		table.insert(themes, { name, name })
	end
	dropdown(Stoa.db, "theme", "Theme", "Bone is warm and class-tinted. Tide is all blues. Graphite is greyscale with one amber accent. All three are colour-blind safe.", "Bone", themes, function(_, value)
		Stoa:SetTheme(value)
	end)
	checkbox(Stoa.modules.Grimoire.db, "enabled", "Show the Grimoire console", "The ink console along the bottom of the screen. Takes effect after /reload.", true)
	checkbox(Stoa.modules.Grimoire.db, "houseChat", "Hold chat in the console", "Chat sits on the console's left page and Stoa's notes appear in chat. Takes effect after /reload.", true)
	checkbox(Stoa.modules.Grimoire.db, "hideBarArt", "Hide action bar art", "Removes the gryphons and border so the bar sits on the ink. Takes effect after /reload.", true)

	-- Halo
	local halo = Stoa.modules.Halo.db
	local party = Stoa.modules.Party.db
	header("Combat")
	checkbox(halo, "enabled", "Show the Halo in combat", "Health, mana, your signature spell, target and cast around your character. Takes effect after /reload.", true)
	checkbox(halo, "hidePlayerFrame", "Hide Blizzard's player frame", "The seal and the Halo show the same. Also hides Blizzard's cast bar. Takes effect after /reload.", true)
	checkbox(halo, "hideTargetFrame", "Hide Blizzard's target frame", "Stoa shows your target beside the Halo. Takes effect after /reload.", true)
	checkbox(party, "enabled", "Show Stoa party cards", "Large beside the Halo when you heal, compact on the left otherwise. Takes effect after /reload.", true)
	checkbox(party, "hideBlizzardParty", "Hide Blizzard's party frames", "Takes effect after /reload.", true)

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
