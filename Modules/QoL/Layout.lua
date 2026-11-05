-- Stoa QoL: a first layout for Blizzard's own frames. A new character starts
-- on the game's preset Edit Mode layout with one action bar, which leaves
-- the bars, buffs and boxes where Stoa doesn't expect them. Once per
-- character, while the preset is still active, Stoa adds its own Edit Mode
-- layout (named "Stoa", shared by the account) from Data/EditModeLayout.lua,
-- switches to it, and turns on the action bars it uses. A layout of your own
-- is never replaced; /stoa editmode applies Stoa's on demand. When Stoa
-- ships a newer layout (Stoa.EDIT_MODE_VERSION), a saved "Stoa" layout is
-- refreshed to it at the next login, while it is the active one.
local _, ns = ...
local Stoa = ns.Stoa

local Layout = Stoa:NewModule("Layout", {
	enabled = true,
})

local NAME = "Stoa"

local function ready()
	return C_EditMode and C_EditMode.GetLayouts and C_EditMode.SaveLayouts
		and C_EditMode.ConvertStringToLayoutInfo and Enum and Enum.EditModeLayoutType
		and Enum.EditModePresetLayoutsMeta and type(Stoa.EDIT_MODE_LAYOUT) == "string"
		and Stoa.EDIT_MODE_LAYOUT ~= ""
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

-- True when the saved "Stoa" layout came from an older Stoa string.
function Layout:Stale()
	return (Stoa.db.editModeVersion or 1) < (Stoa.EDIT_MODE_VERSION or 1)
end

-- Where the "Stoa" layout sits in the saved list, if it's there.
local function find(info)
	for i, layout in ipairs(info.layouts) do
		if layout.layoutName == NAME then return i end
	end
end

-- True while the "Stoa" layout is the active one.
function Layout:OnStoa()
	local info = C_EditMode.GetLayouts()
	local index = info and info.layouts and find(info)
	return index ~= nil and info.activeLayout == presets() + index
end

-- Adds Stoa's layout if it isn't saved yet (or refreshes one saved from an
-- older string), and switches to it.
function Layout:Apply(quiet)
	if not ready() then
		if not quiet then Stoa:Print("Stoa has no Edit Mode layout to apply yet.") end
		return
	end
	if InCombatLockdown() then
		Stoa:AfterCombat(function() self:Apply(quiet) end)
		return
	end
	local info = C_EditMode.GetLayouts()
	if not (info and info.layouts) then return end
	local index = find(info)
	local refresh = index and self:Stale()
	if not index or refresh then
		local ok, layout = pcall(C_EditMode.ConvertStringToLayoutInfo, Stoa.EDIT_MODE_LAYOUT)
		if not (ok and layout) then
			Stoa:Print("Stoa's Edit Mode layout couldn't be read; nothing was changed.")
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
		Stoa.db.editModeVersion = Stoa.EDIT_MODE_VERSION or 1
	end
	C_EditMode.SetActiveLayout(presets() + index)
	self:Bars()
	Stoa.char.layoutApplied = true
	if not quiet then
		Stoa:Print(refresh and "Stoa's Edit Mode layout is updated to the newest version."
			or "Switched to Stoa's Edit Mode layout. Edit Mode can change it or pick another.")
	end
end

function Layout:OnEnable()
	Stoa:On("PLAYER_ENTERING_WORLD", function()
		if not ready() then return end
		if Stoa.char.layoutApplied and not self:Stale() then return end
		-- Edit Mode finishes loading its layouts just after this event.
		C_Timer.After(1, function()
			if self:Stale() and self:OnStoa() then
				-- A newer Stoa layout: refresh the saved one while it's in use.
				self:Apply(false)
				return
			end
			if Stoa.char.layoutApplied then return end
			if self:OnPreset() then
				self:Apply(false)
			else
				-- A layout of the player's own: leave it, and don't ask again.
				Stoa.char.layoutApplied = true
			end
		end)
	end)
end

-- /stoa layout is the backup page's shareable line (Config/Backup.lua).
Stoa.commands.editmode = function()
	Layout:Apply(false)
end
