-- Stoa QoL: a first layout for Blizzard's own frames. A new character starts
-- on the game's preset Edit Mode layout with one action bar, which leaves
-- the bars, buffs and boxes where Stoa doesn't expect them. Once per
-- character, while the preset is still active, Stoa adds its own Edit Mode
-- layout (named "Stoa", shared by the account) from Data/EditModeLayout.lua,
-- switches to it, and turns on the action bars it uses. A layout of your own
-- is never replaced; /stoa editmode applies Stoa's on demand. When Stoa
-- ships a newer layout (Stoa.EDIT_MODE_VERSION), a saved "Stoa" layout is
-- refreshed to it at the next login, while it is the active one.
-- The "Same as Designer" preset uses a second layout the same way
-- ("Stoa Designer", Stoa.DESIGNER_LAYOUT).
local _, ns = ...
local Stoa = ns.Stoa

local Layout = Stoa:NewModule("Layout", {
	enabled = true,
	-- Switch to the compact layout on narrow screens (and back).
	compact = true,
})

-- Each layout Stoa can add: its saved name, string, version and the
-- account key that remembers which version was saved.
local KINDS = {
	stoa = { name = "Stoa", text = "EDIT_MODE_LAYOUT", version = "EDIT_MODE_VERSION", saved = "editModeVersion" },
	designer = { name = "Stoa Designer", text = "DESIGNER_LAYOUT", version = "DESIGNER_LAYOUT_VERSION", saved = "designerLayoutVersion" },
	compact = { name = "Stoa Compact", text = "COMPACT_LAYOUT", version = "COMPACT_LAYOUT_VERSION", saved = "compactLayoutVersion" },
	quiet = { name = "Stoa Quiet", text = "QUIET_LAYOUT", version = "QUIET_LAYOUT_VERSION", saved = "quietLayoutVersion" },
	-- The slim console's own pair: the bars stand above the line.
	slim = { name = "Stoa Slim", text = "SLIM_LAYOUT", version = "SLIM_LAYOUT_VERSION", saved = "slimLayoutVersion" },
	slimCompact = { name = "Stoa Slim Compact", text = "SLIM_COMPACT_LAYOUT", version = "SLIM_LAYOUT_VERSION", saved = "slimCompactLayoutVersion" },
}

-- Below this many UI units wide, the wide layout's bar row crowds the
-- console (1920x1200 with the UI scale off is about 1230; 3440x1440 at a
-- small scale is well over 2000).
local COMPACT_BELOW = 2000

-- The layout this account wants: the designer's or the Quiet preset's
-- while that preset is on.
function Layout:Kind()
	if Stoa.db and Stoa.db.preset == "quiet" and type(Stoa.QUIET_LAYOUT) == "string" then return "quiet" end
	return Stoa.db and Stoa.db.preset == "taer" and type(Stoa.DESIGNER_LAYOUT) == "string" and "designer" or "stoa"
end

-- True when the screen is narrow enough for the compact layout.
function Layout:Narrow()
	local width = UIParent and UIParent:GetWidth()
	return type(width) == "number" and width < COMPACT_BELOW
end

-- The layout to be on right now: compact on a narrow screen, else the
-- preset's.
function Layout:Wanted()
	local narrow = self.db.compact ~= false and self:Narrow()
	if self:Slim() then
		if narrow and type(Stoa.SLIM_COMPACT_LAYOUT) == "string" then return "slimCompact" end
		if type(Stoa.SLIM_LAYOUT) == "string" then return "slim" end
	end
	if narrow and type(Stoa.COMPACT_LAYOUT) == "string" then return "compact" end
	return self:Kind()
end

-- True while the slim console is the one on screen.
function Layout:Slim()
	local console = Stoa.modules.Grimoire
	return console and console.db and console.db.slim and Stoa:IsModuleEnabled("Grimoire") or false
end

local function kindOf(kind)
	return KINDS[kind or Layout:Kind()] or KINDS.stoa
end

local function ready(kind)
	local k = kindOf(kind)
	return C_EditMode and C_EditMode.GetLayouts and C_EditMode.SaveLayouts
		and C_EditMode.ConvertStringToLayoutInfo and Enum and Enum.EditModeLayoutType
		and Enum.EditModePresetLayoutsMeta and type(Stoa[k.text]) == "string"
		and Stoa[k.text] ~= ""
end

local function presets()
	return Enum.EditModePresetLayoutsMeta.NumValues or 2
end

-- True while the active layout is one of the game's presets.
function Layout:OnPreset()
	local info = C_EditMode.GetLayouts()
	return info and info.activeLayout and info.activeLayout <= presets()
end

-- The extra bars, through the game's own toggles (bars 2 to 8).
function Layout:Bars()
	if not (GetActionBarToggles and SetActionBarToggles) then return end
	local toggles = { GetActionBarToggles() }
	for _, bar in ipairs(Stoa.EDIT_MODE_BARS or {}) do
		if bar >= 2 and bar <= 8 then toggles[bar - 1] = true end
	end
	SetActionBarToggles(unpack(toggles))
end

-- True when the saved layout came from an older Stoa string.
function Layout:Stale(kind)
	local k = kindOf(kind)
	return (Stoa.db[k.saved] or 1) < (Stoa[k.version] or 1)
end

-- Where a layout sits in the saved list, if it's there.
local function find(info, name)
	for i, layout in ipairs(info.layouts) do
		if layout.layoutName == name then return i end
	end
end

-- True while one of Stoa's layouts is the active one (any kind when none
-- is named).
function Layout:OnStoa(kind)
	local info = C_EditMode.GetLayouts()
	if not (info and info.layouts) then return false end
	for key, k in pairs(KINDS) do
		if not kind or key == kind then
			local index = find(info, k.name)
			if index and info.activeLayout == presets() + index then return true end
		end
	end
	return false
end

-- Adds Stoa's layout (or the designer's) if it isn't saved yet, or
-- refreshes one saved from an older string, and switches to it.
function Layout:Apply(quiet, kind)
	kind = kind or self:Wanted()
	local k = kindOf(kind)
	local NAME = k.name
	if not ready(kind) then
		if not quiet then Stoa:Print("STOA has no Edit Mode layout to apply yet.") end
		return
	end
	if InCombatLockdown() then
		Stoa:AfterCombat(function() self:Apply(quiet, kind) end)
		return
	end
	local info = C_EditMode.GetLayouts()
	if not (info and info.layouts) then return end
	local index = find(info, NAME)
	local refresh = index and self:Stale(kind)
	if not index or refresh then
		local ok, layout = pcall(C_EditMode.ConvertStringToLayoutInfo, Stoa[k.text])
		if not (ok and layout) then
			Stoa:Print("STOA's Edit Mode layout couldn't be read; nothing was changed.")
			return
		end
		layout.layoutName = NAME
		if refresh then
			layout.layoutType = info.layouts[index].layoutType or Enum.EditModeLayoutType.Account
			info.layouts[index] = layout
			C_EditMode.SaveLayouts(info)
		else
			layout.layoutType = Enum.EditModeLayoutType.Account
			-- After the account layouts and before any character ones, as
			-- the game itself orders them.
			index = 1
			for i, saved in ipairs(info.layouts) do
				if saved.layoutType == Enum.EditModeLayoutType.Account then index = i + 1 end
			end
			table.insert(info.layouts, index, layout)
			C_EditMode.SaveLayouts(info)
			if C_EditMode.OnLayoutAdded then
				C_EditMode.OnLayoutAdded(presets() + index, true, true)
			end
		end
		Stoa.db[k.saved] = Stoa[k.version] or 1
	end
	C_EditMode.SetActiveLayout(presets() + index)
	self:Bars()
	Stoa.char.layoutApplied = true
	if not quiet then
		if kind == "slim" or kind == "slimCompact" then
			Stoa:Print("Switched to STOA's Edit Mode layout for the slim console: the bars stand above the line. Edit Mode can change it or pick another.")
		elseif kind == "compact" then
			Stoa:Print("Switched to STOA's compact Edit Mode layout for this screen size. /stoa editmode wide keeps the wide one.")
		else
			local whose = kind == "designer" and "the designer's" or "STOA's"
			Stoa:Print(refresh and ("Switched to " .. whose .. " Edit Mode layout, updated to the newest version.")
				or ("Switched to " .. whose .. " Edit Mode layout. Edit Mode can change it or pick another."))
		end
	end
end

-- On one of Stoa's layouts, follows the screen: compact when narrow, wide
-- when not. A layout of the player's own is never touched.
function Layout:FollowScreen()
	if InCombatLockdown() or not self:OnStoa() then return end
	local kind = self:Wanted()
	if ready(kind) and not self:OnStoa(kind) then self:Apply(false, kind) end
end

function Layout:OnEnable()
	local queued = false
	local function follow()
		if queued then return end
		queued = true
		C_Timer.After(0.5, function()
			queued = false
			if InCombatLockdown() then
				Stoa:AfterCombat(function() self:FollowScreen() end)
			else
				self:FollowScreen()
			end
		end)
	end
	Stoa:On("UI_SCALE_CHANGED", follow)
	Stoa:On("DISPLAY_SIZE_CHANGED", follow)
	-- A windowed resize doesn't always send either event; UIParent's own
	-- size always changes.
	UIParent:HookScript("OnSizeChanged", follow)

	Stoa:On("PLAYER_ENTERING_WORLD", function()
		local kind = self:Wanted()
		if not ready(kind) then return end
		-- Edit Mode finishes loading its layouts just after this event.
		C_Timer.After(1, function()
			if InCombatLockdown() then return end
			-- On one of Stoa's layouts: follow the preset (Stoa's or the
			-- designer's), and refresh a saved one from an older string.
			local onOther = self:OnStoa() and not self:OnStoa(kind)
			if onOther or (self:Stale(kind) and self:OnStoa(kind)) then
				self:Apply(false, kind)
				return
			end
			if Stoa.char.layoutApplied then return end
			if self:OnPreset() then
				self:Apply(false, kind)
			else
				-- A layout of the player's own: leave it, and don't ask again.
				Stoa.char.layoutApplied = true
			end
		end)
	end)
end

-- /stoa layout is the backup page's shareable line (Config/Backup.lua).
Stoa.commands.editmode = function(rest)
	local word = strtrim(rest or ""):lower()
	if word == "wide" or word == "stoa" or word == "designer" then
		-- Choosing the wide layout by hand keeps it on any screen.
		Layout.db.compact = false
		Layout:Apply(false, word ~= "wide" and word or Layout:Kind())
		Stoa:Print("STOA won't switch to the compact layout on narrow screens now. /stoa editmode auto turns that back on.")
	elseif word == "compact" then
		Layout:Apply(false, "compact")
	elseif word == "status" then
		local info = C_EditMode and C_EditMode.GetLayouts and C_EditMode.GetLayouts()
		local active = info and info.activeLayout and info.layouts and info.layouts[info.activeLayout - presets()]
		Stoa:Print(("Screen %d UI units wide (compact below %d). Wants %s; active layout: %s; switching %s."):format(
			math.floor(UIParent:GetWidth() or 0), COMPACT_BELOW, kindOf(Layout:Wanted()).name,
			active and active.layoutName or "a game preset", Layout.db.compact ~= false and "on" or "off"))
	elseif word == "auto" then
		Layout.db.compact = true
		Layout:Apply(false, Layout:Wanted())
	else
		Layout:Apply(false, Layout:Wanted())
	end
end
