-- Stoa: what you can dispel, at hand.
-- Right of the Halo in a fight, mirroring your own buffs on its left: a
-- well for each thing you can cure on yourself (a priest's Magic and
-- Disease; a paladin's Magic, Poison and Disease) and, for a priest, one
-- for a Magic buff on your enemy (Dispel Magic strips it). The game fills
-- each well with the aura's icon, type border and time, also in a fight
-- where addons can't read auras at all; STOA never learns what's shown.
-- Click a well to cast the cure on it.
--
-- Each well is a game AuraContainer with one slot, filtered to that
-- dispel type, over a secure button that casts the cure. Both are made and
-- changed out of combat only; state drivers show the row in a fight (the
-- enemy's well only with a living enemy targeted).
local _, ns = ...
local Stoa = ns.Stoa
local UI = Stoa.UI

local Cures = Stoa:NewModule("Cures", { show = true })

local SIZE = 30
local GAP = 6
local MASK = UI.MEDIA .. "Textures\\ButtonMask"
local SELF_DRIVER = "[combat] show; hide"
local ENEMY_DRIVER = "[combat,@target,harm,nodead] show; hide"

-- Per class: the wells, left to right. spells: the cures that clear it,
-- best first, by ID with the English name (matched by name, so Forever's
-- own IDs and every rank count).
local DISPEL_MAGIC = { { 527, "Dispel Magic" } }
local ROWS = {
	PRIEST = {
		{ key = "magic", unit = "player", filter = "HARMFUL", type = "Magic", spells = DISPEL_MAGIC },
		{ key = "disease", unit = "player", filter = "HARMFUL", type = "Disease", spells = { { 552, "Abolish Disease" }, { 528, "Cure Disease" } } },
		{ key = "enemy", unit = "target", filter = "HELPFUL", type = "Magic", spells = DISPEL_MAGIC, enemy = true },
	},
	PALADIN = {
		{ key = "magic", unit = "player", filter = "HARMFUL", type = "Magic", spells = { { 4987, "Cleanse" } } },
		{ key = "poison", unit = "player", filter = "HARMFUL", type = "Poison", spells = { { 4987, "Cleanse" }, { 1152, "Purify" } } },
		{ key = "disease", unit = "player", filter = "HARMFUL", type = "Disease", spells = { { 4987, "Cleanse" }, { 1152, "Purify" } } },
	},
}

-- The first cure of the well's you know, by name, or nil.
local function cureFor(def)
	for _, spell in ipairs(def.spells) do
		local name = Stoa.Spells.localName(spell[1], spell[2])
		if name and Stoa.Sign.spell(name) then return name end
	end
end

-- The game's aura button, dressed once as it is made: icon in STOA's
-- rounded square, the game's type border, a swipe with the time.
local function dress(button, well)
	button:SetAllPoints(well)
	if button.SetMouseClickEnabled then button:SetMouseClickEnabled(false) end
	local icon = button:CreateTexture(nil, "ARTWORK")
	icon:SetAllPoints()
	icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
	local mask = button:CreateMaskTexture()
	mask:SetAllPoints()
	mask:SetTexture(MASK, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
	icon:AddMaskTexture(mask)
	button:SetIcon(icon)
	local cooldown = CreateFrame("Cooldown", nil, button, "CooldownFrameTemplate")
	cooldown:SetAllPoints()
	cooldown:SetSwipeTexture(MASK)
	cooldown:SetDrawEdge(false)
	cooldown:SetDrawBling(false)
	pcall(button.SetDurationCooldown, button, cooldown)
	local overlay = CreateFrame("Frame", nil, button)
	overlay:SetAllPoints()
	overlay:SetFrameLevel(cooldown:GetFrameLevel() + 1)
	local border = overlay:CreateTexture(nil, "OVERLAY")
	border:SetPoint("TOPLEFT", -2, 2)
	border:SetPoint("BOTTOMRIGHT", 2, -2)
	local styles = Enum and Enum.CustomAuraButtonDispelTypeTextureStyle
	pcall(button.AddDispelTypeTexture, button, border, {
		showWhenHarmful = true, showWhenHelpful = true, showWithoutDispelType = false,
		style = styles and styles.Border or 0,
	})
	local count = UI.text(overlay, "sans", Stoa.typeSize.caption, "text", "RIGHT")
	count:SetPoint("BOTTOMRIGHT", -2, 2)
	pcall(button.SetApplicationCount, button, count)
	if button.SetTooltipAnchorPoint then button:SetTooltipAnchorPoint("ANCHOR_RIGHT") end
end

function Cures:BuildWell(def, i)
	local well = CreateFrame("Frame", nil, self.row)
	well:SetSize(SIZE, SIZE)
	well:SetPoint("LEFT", self.row, "LEFT", (i - 1) * (SIZE + GAP), 0)
	-- A faint socket, so the place reads as a place while it's empty.
	UI.roundPanel(well, 0.3)
	local click = CreateFrame("Button", nil, well, "SecureActionButtonTemplate")
	click:SetAllPoints()
	click:RegisterForClicks("AnyUp", "AnyDown")
	well.click = click
	local ok, container = pcall(CreateFrame, "AuraContainer", nil, well, "CustomAuraContainerTemplate")
	if ok and container then
		container:SetAllPoints()
		container:SetFrameLevel(click:GetFrameLevel() + 2)
		local built = pcall(function()
			container:SetUnit(def.unit)
			container:AddAuraSlot("StoaCure_" .. def.key, def.filter, {
				initializeFrame = function(button) pcall(dress, button, well) end,
				candidateFilters = { includeDispelTypes = { [def.type] = true } },
				sortMethod = 0,
				sortDirection = 0,
			})
		end)
		if built then well.container = container else container:Hide() end
	end
	RegisterStateDriver(well, "visibility", def.enemy and ENEMY_DRIVER or SELF_DRIVER)
	return well
end

-- Out of combat: which wells you have a cure for, what a click casts, and
-- where they sit.
function Cures:Arrange()
	if InCombatLockdown() or not self.row then return end
	local shown = 0
	for i, def in ipairs(self.defs) do
		local well = self.wells[i]
		local cure = self.db.show and cureFor(def)
		if cure then
			shown = shown + 1
			well:ClearAllPoints()
			well:SetPoint("LEFT", self.row, "LEFT", (shown - 1) * (SIZE + GAP), 0)
			well.click:SetAttribute("type", "spell")
			well.click:SetAttribute("spell", cure)
			well.click:SetAttribute("unit", def.unit)
			RegisterStateDriver(well, "visibility", def.enemy and ENEMY_DRIVER or SELF_DRIVER)
		else
			UnregisterStateDriver(well, "visibility")
			well:Hide()
		end
	end
end

function Cures:Build()
	local halo = Stoa.modules.Halo
	if not (halo and halo.frame) then return false end
	local row = CreateFrame("Frame", nil, UIParent)
	row:SetSize(SIZE, SIZE)
	row:SetPoint("LEFT", halo.frame, "RIGHT", 60, 24)
	self.row = row
	self.wells = {}
	for i, def in ipairs(self.defs) do self.wells[i] = self:BuildWell(def, i) end
	return true
end

function Cures:OnEnable()
	local _, classFile = UnitClass("player")
	self.defs = ROWS[classFile]
	if not self.defs or not Stoa:IsModuleEnabled("Halo") then return end
	if InCombatLockdown() then
		Stoa:On("PLAYER_REGEN_ENABLED", function() if not self.row then self:OnEnable() end end)
		return
	end
	if not self.row and not self:Build() then return end
	local function arrange() xpcall(self.Arrange, Stoa.catch, self) end
	for _, event in ipairs({ "SPELLS_CHANGED", "PLAYER_REGEN_ENABLED", "PLAYER_LEVEL_UP" }) do Stoa:On(event, arrange) end
	arrange()
end

function Cures:Refresh()
	self:Arrange()
end
