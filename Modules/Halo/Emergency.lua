-- Stoa Halo: the emergency slot.
-- One button beside the Halo for the best way you carry to heal yourself:
-- a healthstone first, then your best healing potion, then your best
-- bandage. It nudges (full brightness and a LOW word) when your health
-- drops under the threshold.
--
-- On Forever your own health can be hidden from addons in combat, so the
-- nudge can't always be worked out there: in a fight the button simply
-- stays in view, quietly, one click away. Out of combat it only shows when
-- you're low. A secure state driver does the in-combat showing, since
-- secure buttons can't be shown by hand in a fight.
local _, ns = ...
local Stoa = ns.Stoa
local UI = Stoa.UI

local Emergency = Stoa:NewModule("Emergency", {
	threshold = 40,
})

local SIZE = 40
local QUIET = 0.5

-- Item IDs, best first in each group.
local HEALTHSTONES = {
	19013, 19012, 9421, -- major
	19011, 19010, 5510, -- greater
	19009, 19008, 5509, -- healthstone
	19007, 19006, 5511, -- lesser
	19005, 19004, 5512, -- minor
}
local POTIONS = {
	13446, -- major healing
	3928, -- superior healing
	1710, -- greater healing
	929, -- healing
	4596, -- discolored healing
	858, -- lesser healing
	118, -- minor healing
}
local BANDAGES = {
	14530, 14529, -- runecloth
	8545, 8544, -- mageweave
	6451, 6450, -- silk
	3531, 3530, -- wool
	2581, 1251, -- linen
}

local function owned(id)
	local count = C_Item and C_Item.GetItemCount or GetItemCount
	return count and (Stoa:PlainNumber(count(id)) or 0) > 0
end

-- The item to offer, as an item link-ish string, or nil.
function Emergency:Pick()
	for _, group in ipairs({ HEALTHSTONES, POTIONS, BANDAGES }) do
		for _, id in ipairs(group) do
			if owned(id) then return "item:" .. id end
		end
	end
end

-- Your health as a fraction, or nil while it's hidden.
local function health()
	local now, most = Stoa:PlainNumber(UnitHealth("player")), Stoa:PlainNumber(UnitHealthMax("player"))
	if not (now and most and most > 0) then return nil end
	return now / most
end

function Emergency:Build()
	if self.button then return end
	local button = UI.itemButton(UIParent, "StoaEmergency", SIZE)
	button:SetFrameStrata("MEDIUM")
	local halo = _G.StoaHalo
	if halo then
		button:SetPoint("RIGHT", halo, "LEFT", -60, -40)
	else
		button:SetPoint("CENTER", UIParent, "CENTER", -260, -80)
	end
	local word = UI.text(button, "sans", Stoa.typeSize.caption, "danger", "CENTER")
	word:SetPoint("TOP", button, "BOTTOM", 0, -3)
	word:SetText("LOW")
	UI.legible(word)
	word:Hide()
	button.word = word
	button:Hide()
	self.button = button
	Stoa:RegisterMover("emergency", button, "Emergency item")
end

-- Item and showing rules: out of combat only, as they touch the secure
-- button. In combat the state driver shows it.
function Emergency:Update()
	local button = self.button
	if not button or InCombatLockdown() then return end
	local pick = self:Pick()
	if pick ~= button.link then button:SetItem(pick) end
	local fraction = health()
	local low = pick and fraction and fraction * 100 < (self.db.threshold or 40)
	if not pick then
		UnregisterStateDriver(button, "visibility")
		button:Hide()
	elseif low then
		UnregisterStateDriver(button, "visibility")
		button:Show()
	else
		RegisterStateDriver(button, "visibility", "[combat] show; hide")
	end
	self:Nudge()
end

-- Brightness and the LOW word: any time, as they're only looks.
function Emergency:Nudge()
	local button = self.button
	if not button then return end
	local fraction = health()
	local low = fraction and fraction * 100 < (self.db.threshold or 40)
	button:SetAlpha(low and 1 or QUIET)
	button.word:SetShown(low and true or false)
end

function Emergency:OnEnable()
	Stoa:AfterCombat(function()
		xpcall(function()
			self:Build()
			self:Update()
		end, Stoa.catch)
	end)
	local function update() if self.button then self:Update() end end
	Stoa:On("BAG_UPDATE_DELAYED", update)
	Stoa:On("PLAYER_REGEN_ENABLED", update)
	Stoa:OnUnit("UNIT_HEALTH", { "player" }, function()
		if not self.button then return end
		if InCombatLockdown() then self:Nudge() else self:Update() end
	end)
	Stoa:On("BAG_UPDATE_COOLDOWN", function() if self.button then self.button:Refresh() end end)
end
