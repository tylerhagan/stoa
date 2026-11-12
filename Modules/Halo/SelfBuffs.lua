-- Stoa Halo: your own buffs, at hand.
-- The long buffs you keep on yourself (Inner Fire, an aura and a blessing,
-- Arcane Intellect and an armor, Demon Armor, Lightning Shield) show as small
-- icons left of the Halo when one is missing or about to run out, out of
-- combat only. Click one to cast it. A missing buff breathes softly; one
-- running out shows its time left under it. Nothing shows while all is well,
-- and the row hides in a fight, where the Halo's words take over.
--
-- The buttons are secure, so the row only changes out of combat; a state
-- driver hides it the moment a fight starts.
local _, ns = ...
local Stoa = ns.Stoa
local UI = Stoa.UI

local SelfBuffs = Stoa:NewModule("SelfBuffs", {})

local SIZE = 30
local GAP = 6

-- Each buff: the spells that count when found on you (auras), and the ones
-- a click may cast (cast, best first). pick: when several can be cast, the
-- one you had on last is cast again, else the first you know (or the role's
-- choice). roles: only for these roles. Spells by ID with their English
-- names; matched by the name in the game's language.
local FORT = { { 1243, "Power Word: Fortitude" }, { 21562, "Prayer of Fortitude" } }
local SPIRIT = { { 14752, "Divine Spirit" }, { 27681, "Prayer of Spirit" } }
local MARK = { { 1126, "Mark of the Wild" }, { 21849, "Gift of the Wild" } }
local INTELLECT = { { 1459, "Arcane Intellect" }, { 23028, "Arcane Brilliance" } }
local AURAS = {
	{ 465, "Devotion Aura" }, { 7294, "Retribution Aura" }, { 19746, "Concentration Aura" },
	{ 20218, "Sanctity Aura" }, { 19876, "Shadow Resistance Aura" }, { 19888, "Frost Resistance Aura" },
	{ 19891, "Fire Resistance Aura" }, { 32223, "Crusader Aura" },
}
local BLESSINGS = {
	{ 19740, "Blessing of Might" }, { 19742, "Blessing of Wisdom" }, { 20217, "Blessing of Kings" },
	{ 20911, "Blessing of Sanctuary" }, { 19977, "Blessing of Light" }, { 1038, "Blessing of Salvation" },
	{ 25782, "Greater Blessing of Might" }, { 25894, "Greater Blessing of Wisdom" }, { 25898, "Greater Blessing of Kings" },
	{ 25899, "Greater Blessing of Sanctuary" }, { 25890, "Greater Blessing of Light" }, { 25895, "Greater Blessing of Salvation" },
}
local MAGE_ARMOR = { { 30482, "Molten Armor" }, { 6117, "Mage Armor" }, { 7302, "Ice Armor" }, { 168, "Frost Armor" } }
local DEMON_ARMOR = { { 28176, "Fel Armor" }, { 706, "Demon Armor" }, { 687, "Demon Skin" } }
local SHIELDS = { { 324, "Lightning Shield" }, { 24398, "Water Shield" } }

local BY_CLASS = {
	PRIEST = {
		{ key = "innerFire", auras = { { 588, "Inner Fire" } } },
		{ key = "fortitude", auras = FORT, cast = { FORT[1] } },
		{ key = "spirit", auras = SPIRIT, cast = { SPIRIT[1] } },
		{ key = "shadowform", auras = { { 15473, "Shadowform" } }, roles = { RANGED = true } },
	},
	PALADIN = {
		{ key = "aura", auras = AURAS, pick = true,
			byRole = { HEALER = "Concentration Aura", MELEE = "Sanctity Aura", TANK = "Devotion Aura" } },
		{ key = "blessing", auras = BLESSINGS, cast = { BLESSINGS[1], BLESSINGS[2], BLESSINGS[3], BLESSINGS[4] }, pick = true,
			byRole = { HEALER = "Blessing of Wisdom", MELEE = "Blessing of Might", TANK = "Blessing of Kings" } },
		{ key = "fury", auras = { { 25780, "Righteous Fury" } }, roles = { TANK = true } },
	},
	DRUID = {
		{ key = "mark", auras = MARK, cast = { MARK[1] } },
		{ key = "omen", auras = { { 16864, "Omen of Clarity" } } },
	},
	MAGE = {
		{ key = "intellect", auras = INTELLECT, cast = { INTELLECT[1] } },
		{ key = "armor", auras = MAGE_ARMOR, pick = true },
	},
	WARLOCK = {
		{ key = "armor", auras = DEMON_ARMOR },
	},
	SHAMAN = {
		{ key = "shield", auras = SHIELDS, pick = true },
	},
	HUNTER = {
		{ key = "trueshot", auras = { { 19506, "Trueshot Aura" } } },
	},
}

local call = Stoa.safe.call

local function localNames(spells)
	local list = {}
	for _, spell in ipairs(spells) do list[#list + 1] = Stoa.Spells.localName(spell[1], spell[2]) end
	return list
end

-- The class list with names in the game's language, made on first use.
local LIST
local function buffList()
	if LIST then return LIST end
	LIST = {}
	local _, classFile = UnitClass("player")
	for _, entry in ipairs(BY_CLASS[classFile] or {}) do
		local byRole
		if entry.byRole then
			byRole = {}
			for role, english in pairs(entry.byRole) do
				for _, spell in ipairs(entry.auras) do
					if spell[2] == english then byRole[role] = Stoa.Spells.localName(spell[1], english) end
				end
			end
		end
		LIST[#LIST + 1] = {
			key = entry.key, roles = entry.roles, pick = entry.pick, byRole = byRole,
			auras = localNames(entry.auras), cast = localNames(entry.cast or entry.auras),
		}
	end
	return LIST
end

-- Your aura of one of these names: the aura, false when you have none, nil
-- when it can't be read.
local function find(names)
	if Stoa:AurasHidden() then return nil end
	local lookup = C_UnitAuras and C_UnitAuras.GetAuraDataBySpellName
	if not lookup then return nil end
	for _, name in ipairs(names) do
		local ok, aura = pcall(lookup, "player", name, "HELPFUL")
		if not ok or Stoa:IsSecret(aura) then return nil end
		if aura then return aura end
	end
	return false
end

-- Seconds left on an aura, or nil for one that doesn't run out (or can't be read).
local function timeLeft(aura)
	local ends, length = Stoa:PlainNumber(aura.expirationTime), Stoa:PlainNumber(aura.duration)
	if not (ends and length and ends > 0 and length > 0) then return nil end
	return ends - GetTime(), length
end

-- Running out: under a tenth of its length, between 30 seconds and 2 minutes.
local function ending(left, length)
	return left and left < math.min(120, math.max(30, length * 0.1))
end

-- The spell a click casts: the one you had on last, the role's choice, or
-- the first you know.
function SelfBuffs:Choice(entry)
	local known = {}
	for _, name in ipairs(entry.cast) do
		if Stoa.Spells.best(name) then known[#known + 1] = name end
	end
	if #known == 0 then return nil end
	if entry.pick then
		local last = self.db.last and self.db.last[entry.key]
		local role = entry.byRole and entry.byRole[Stoa:GetRole() or ""]
		for _, wanted in ipairs({ last, role }) do
			for _, name in ipairs(known) do
				if name == wanted then return name end
			end
		end
	end
	return known[1]
end

-- What wants your attention now: { { name, left } }, left nil when missing.
function SelfBuffs:Due()
	local list = {}
	if InCombatLockdown() or UnitIsDeadOrGhost("player") or (UnitOnTaxi and UnitOnTaxi("player")) then return list end
	local role = Stoa:GetRole()
	for _, entry in ipairs(buffList()) do
		if not entry.roles or entry.roles[role or ""] then
			local cast = self:Choice(entry)
			if cast then
				local aura = find(entry.auras)
				if aura == false then
					list[#list + 1] = { name = cast }
				elseif aura then
					-- What you had on is what a click casts again later.
					if entry.pick and type(aura.name) == "string" and not Stoa:IsSecret(aura.name) then
						self.db.last = self.db.last or {}
						self.db.last[entry.key] = aura.name
					end
					local left, length = timeLeft(aura)
					if ending(left, length) then list[#list + 1] = { name = self:Choice(entry), left = left } end
				end
			end
		end
	end
	return list
end

-- Build ------------------------------------------------------------------------

function SelfBuffs:Build()
	if self.frame then return end
	local frame = CreateFrame("Frame", "StoaSelfBuffs", UIParent)
	frame:SetSize(SIZE, SIZE)
	frame:SetFrameStrata("MEDIUM")
	-- Gone the moment a fight starts, though the buttons can't be touched then.
	RegisterStateDriver(frame, "visibility", "[combat] hide; show")
	self.frame, self.buttons = frame, {}
	self:Place()
	Stoa:RegisterMover("selfBuffs", frame, "Your buffs", { default = function() self:Place() end })
end

local function box(frame)
	if not (frame and frame.IsShown and frame:IsShown() and frame.GetRect) then return end
	local left, bottom, width, height = frame:GetRect()
	left, bottom = Stoa:PlainNumber(left), Stoa:PlainNumber(bottom)
	width, height = Stoa:PlainNumber(width), Stoa:PlainNumber(height)
	if not (left and bottom and width and height and width > 1) then return end
	local k = (frame:GetEffectiveScale() or 1) / (UIParent:GetEffectiveScale() or 1)
	return left * k, bottom * k, (left + width) * k, (bottom + height) * k
end

-- Left of the Halo, a little above the emergency and quest item buttons. If
-- the group frames sit there, the row goes just above them.
function SelfBuffs:Place()
	local frame = self.frame
	if not frame or InCombatLockdown() or Stoa:HasSavedPosition("selfBuffs") then return end
	local halo = _G.StoaHalo
	frame:ClearAllPoints()
	if halo then
		frame:SetPoint("RIGHT", halo, "LEFT", -60, 24)
	else
		frame:SetPoint("BOTTOM", UIParent, "BOTTOM", -300, 380)
	end
	local group = IsInRaid() and _G.StoaRaid or IsInGroup() and _G.StoaParty or nil
	local al, ab, ar, at = box(frame)
	local bl, bb, br, bt = box(group)
	if al and bl and al < br and ar > bl and ab < bt and at > bb then
		frame:ClearAllPoints()
		frame:SetPoint("BOTTOMRIGHT", group, "TOPRIGHT", 0, 12)
	end
end

local function clock(seconds)
	if seconds >= 60 then return ("%dm"):format(math.ceil(seconds / 60)) end
	return ("%ds"):format(math.max(0, math.floor(seconds)))
end

function SelfBuffs:Button(i)
	local button = self.buttons[i]
	if button then return button end
	button = CreateFrame("Button", "StoaSelfBuff" .. i, self.frame, "SecureActionButtonTemplate")
	button:SetSize(SIZE, SIZE)
	button:SetPoint("RIGHT", self.frame, "RIGHT", -(i - 1) * (SIZE + GAP), 0)
	-- Press or release, whichever the "cast on key down" setting acts on.
	button:RegisterForClicks("AnyUp", "AnyDown")
	button:SetAttribute("type", "spell")
	button:SetAttribute("unit", "player")
	local icon = button:CreateTexture(nil, "ARTWORK")
	icon:SetAllPoints()
	-- In the theme's colour: the spell's art in grey, tinted, so the row
	-- reads as STOA's and follows a theme change.
	icon:SetDesaturated(true)
	icon:SetVertexColor(Stoa:Color("accent"))
	UI.tint(icon, "accent")
	button.icon = icon
	if Stoa.ItemSkin and Stoa.ItemSkin.skinSlot then Stoa.ItemSkin.skinSlot(button) end
	local left = UI.text(button, "sans", Stoa.typeSize.caption, "accent", "CENTER")
	left:SetPoint("TOP", button, "BOTTOM", 0, -3)
	UI.legible(left)
	button.left = left
	-- A missing buff breathes, slowly, between dim and full.
	local breathe = button:CreateAnimationGroup()
	breathe:SetLooping("BOUNCE")
	local fade = breathe:CreateAnimation("Alpha")
	fade:SetFromAlpha(1)
	fade:SetToAlpha(0.55)
	fade:SetDuration(1.4)
	fade:SetSmoothing("IN_OUT")
	button.breathe = breathe
	button:SetScript("OnEnter", function(self)
		if not self.spell then return end
		GameTooltip:SetOwner(self, "ANCHOR_TOP")
		local id = Stoa.Spells.best(self.spell)
		if not (id and pcall(GameTooltip.SetSpellByID, GameTooltip, id)) then GameTooltip:SetText(self.spell) end
		GameTooltip:AddLine("Click to cast it.", 1, 1, 1)
		GameTooltip:Show()
	end)
	button:SetScript("OnLeave", function() GameTooltip:Hide() end)
	self.buttons[i] = button
	return button
end

-- Rebuilds the row: only out of combat, as the buttons are secure.
function SelfBuffs:Update()
	if not self.frame or InCombatLockdown() then return end
	local due = self:Due()
	for i = 1, math.max(#due, #self.buttons) do
		local item = due[i]
		if item then
			local button = self:Button(i)
			if button.spell ~= item.name then
				button.spell = item.name
				button:SetAttribute("spell", item.name)
				local id = Stoa.Spells.best(item.name)
				local texture = id and C_Spell and C_Spell.GetSpellTexture and call(C_Spell.GetSpellTexture, id)
				button.icon:SetTexture(texture or 136243)
			end
			button.left:SetText(item.left and clock(item.left) or "")
			if item.left then
				button.breathe:Stop()
				button:SetAlpha(1)
			elseif not button.breathe:IsPlaying() then
				button.breathe:Play()
			end
			if not button:IsShown() then
				button:SetAlpha(0)
				button:Show()
				UI.fade(button, 1, 0.4)
				if not item.left then C_Timer.After(0.45, function() if button.spell and button:IsShown() then button.breathe:Play() end end) end
			end
		elseif self.buttons[i] then
			local button = self.buttons[i]
			button.breathe:Stop()
			button.spell = nil
			button:SetAttribute("spell", nil)
			button:Hide()
		end
	end
	self.frame:SetWidth(math.max(1, #due) * (SIZE + GAP) - GAP)
	if #due > 0 then self:Place() end
end

function SelfBuffs:Soon()
	if self.pending then return end
	self.pending = true
	C_Timer.After(0.3, function()
		self.pending = false
		xpcall(self.Update, Stoa.catch, self)
	end)
end

function SelfBuffs:OnEnable()
	if #buffList() == 0 then return end
	Stoa:AfterCombat(function()
		xpcall(function()
			self:Build()
			self:Update()
		end, Stoa.catch)
	end)
	Stoa:On("UNIT_AURA", function(unit) if unit == "player" then self:Soon() end end)
	for _, event in ipairs({ "STOA_SPELLS_CHANGED", "STOA_ROLE_CHANGED", "PLAYER_REGEN_ENABLED", "PLAYER_ENTERING_WORLD",
		"PLAYER_UNGHOST", "PLAYER_ALIVE", "GROUP_ROSTER_UPDATE", "PLAYER_CONTROL_GAINED" }) do
		Stoa:On(event, function() self:Soon() end)
	end
	-- Time left counts down between aura events.
	Stoa:NewTicker(1, function()
		if self.frame and self.frame:IsVisible() and not InCombatLockdown() then
			local any
			for _, button in ipairs(self.buttons) do
				if button:IsShown() and button.left:GetText() ~= "" then any = true end
			end
			if any or GetTime() - (self.looked or 0) > 5 then
				self.looked = GetTime()
				xpcall(self.Update, Stoa.catch, self)
			end
		end
	end)
end
