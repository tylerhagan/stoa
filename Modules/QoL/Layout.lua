-- Stoa QoL: a first layout for Blizzard's own frames. A new character starts
-- on the game's preset Edit Mode layout with one action bar, which leaves
-- the bars, buffs and boxes where Stoa doesn't expect them. Once per
-- character, while the preset is still active, Stoa adds its own Edit Mode
-- layout (named "Stoa", shared by the account) from Data/EditModeLayout.lua,
-- switches to it, and turns on the action bars it uses. A layout of your own
-- is never replaced; /stoa layout applies Stoa's on demand.
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

-- Adds Stoa's layout if it isn't saved yet, and switches to it.
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
	local index
	for i, layout in ipairs(info.layouts) do
		if layout.layoutName == NAME then index = i end
	end
	if not index then
		local ok, layout = pcall(C_EditMode.ConvertStringToLayoutInfo, Stoa.EDIT_MODE_LAYOUT)
		if not (ok and layout) then
			Stoa:Print("Stoa's Edit Mode layout couldn't be read; nothing was changed.")
			return
		end
		layout.layoutName = NAME
		layout.layoutType = Enum.EditModeLayoutType.Account
		-- After the account layouts and before any character ones, as the
		-- game itself orders them.
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
	C_EditMode.SetActiveLayout(presets() + index)
	self:Bars()
	Stoa.char.layoutApplied = true
	if not quiet then Stoa:Print("Switched to Stoa's Edit Mode layout. Edit Mode can change it or pick another.") end
end

function Layout:OnEnable()
	Stoa:On("PLAYER_ENTERING_WORLD", function()
		if Stoa.char.layoutApplied or not ready() then return end
		-- Edit Mode finishes loading its layouts just after this event.
		C_Timer.After(1, function()
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

Stoa.commands.layout = function()
	Layout:Apply(false)
end
