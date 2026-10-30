-- Stoa: will your DoTs finish it? Drawn on the target plaque.
-- DoesItDie (MIT, by Joe Greive) learns what your DoTs still have to deal
-- from your casts and the hits the game still shows in combat, and hands that
-- out through its public API. When it is installed, Stoa draws its numbers in
-- Stoa's look:
--   Marker: the health bar's last stretch, as much as your DoTs will still
--   take off, in bone, ending at the health's edge.
--   Skull: slides over the portrait coin when they will kill it.
-- The target's health is secret in combat, so Lua never compares the two:
-- StatusBars do. The marker is a reversed bar scaled to the target's maximum
-- and pinned to the health fill's edge. The skull rides the fill edge of a
-- long bar scaled to the target's health inside a clipped window, so it only
-- comes into view once the DoTs' damage reaches the health.
-- Without DoesItDie this module does nothing.
local _, ns = ...
local Stoa = ns.Stoa
local UI = Stoa.UI

local Lethal = Stoa:NewModule("Lethal", { marker = true, skull = true })

local UPDATE = 0.1
-- How long the skull's bar is; the skull starts sliding in at its own width
-- short of lethal (under 1% of the health).
local SLIDE = 4000
local SKULL = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_8"

local function api()
	local did = rawget(_G, "DoesItDie")
	if type(did) == "table" and type(did.GetRemainingDamage) == "function" then return did end
end

function Lethal:Available()
	return api() ~= nil
end

function Lethal:Build()
	local halo = Stoa.modules.Halo
	local target = halo and halo.target
	if not (target and target.hp and target.plaque) then return false end
	local hp = target.hp

	-- Marker, clipped to the health bar so damage past the health doesn't
	-- spill over the plaque.
	local clip = CreateFrame("Frame", nil, target)
	clip:SetPoint("TOPLEFT", hp, "TOPLEFT", 0, 1)
	clip:SetPoint("BOTTOMRIGHT", hp, "BOTTOMRIGHT", 0, -1)
	clip:SetClipsChildren(true)
	clip:SetFrameLevel(hp:GetFrameLevel() + 2)
	local marker = CreateFrame("StatusBar", nil, clip)
	marker:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
	marker:SetReverseFill(true)
	marker:SetPoint("TOP", clip, "TOP")
	marker:SetPoint("BOTTOM", clip, "BOTTOM")
	marker:SetPoint("RIGHT", hp:GetStatusBarTexture(), "RIGHT")
	marker:SetWidth(hp:GetWidth())
	local edge = marker:CreateTexture(nil, "OVERLAY")
	Stoa.UI.pixel(edge, "width")
	edge:SetPoint("TOPLEFT", marker:GetStatusBarTexture(), "TOPLEFT")
	edge:SetPoint("BOTTOMLEFT", marker:GetStatusBarTexture(), "BOTTOMLEFT")
	self.clip, self.marker, self.markerEdge = clip, marker, edge

	-- Skull over the portrait coin: a dark disc and the skull, sliding in.
	local coin = target.plaque.coin
	local size = coin:GetWidth()
	local window = CreateFrame("Frame", nil, coin)
	window:SetAllPoints(coin)
	window:SetClipsChildren(true)
	window:SetFrameLevel(coin:GetFrameLevel() + 4)
	local slide = CreateFrame("StatusBar", nil, window)
	slide:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
	slide:SetStatusBarColor(0, 0, 0, 0)
	slide:SetSize(SLIDE, size)
	slide:SetPoint("RIGHT", window, "RIGHT")
	local holder = CreateFrame("Frame", nil, slide)
	holder:SetSize(size, size)
	holder:SetPoint("RIGHT", slide:GetStatusBarTexture(), "RIGHT")
	local shade = UI.circle(holder, "ARTWORK", 0, size - 10)
	shade:SetPoint("CENTER")
	shade:SetColorTexture(0, 0, 0, 0.6)
	local skull = holder:CreateTexture(nil, "OVERLAY")
	skull:SetSize(size * 0.5, size * 0.5)
	skull:SetPoint("CENTER")
	skull:SetTexture(SKULL)
	skull:SetDesaturated(true)
	self.window, self.slide, self.skull = window, slide, skull

	self:Paint()
	Stoa:On("STOA_THEME_CHANGED", function() self:Paint() end)
	self:Hide()
	return true
end

function Lethal:Paint()
	self.marker:SetStatusBarColor(Stoa:Color("text"))
	self.marker:GetStatusBarTexture():SetAlpha(0.7)
	self.markerEdge:SetColorTexture(0, 0, 0, 0.8)
	self.skull:SetVertexColor(Stoa:Color("danger"))
end

function Lethal:Hide()
	if not self.clip then return end
	self.clip:Hide()
	self.window:Hide()
end

function Lethal:Update()
	local did = api()
	if not self.clip then return end
	if not did or not UnitExists("target") then return self:Hide() end
	local dead = UnitIsDead("target")
	if Stoa:IsSecret(dead) then dead = false end
	local ok, damage, count = pcall(did.GetRemainingDamage, "target")
	if dead or not ok or not count or count == 0 or not damage or damage <= 0 then return self:Hide() end
	local drawn = pcall(function()
		self.marker:SetWidth(Stoa.modules.Halo.target.hp:GetWidth())
		self.marker:SetMinMaxValues(0, UnitHealthMax("target"))
		self.marker:SetValue(damage)
		self.slide:SetMinMaxValues(0, UnitHealth("target"))
		self.slide:SetValue(damage)
	end)
	if not drawn then return self:Hide() end
	self.clip:SetShown(self.db.marker)
	self.window:SetShown(self.db.skull)
end

function Lethal:OnEnable()
	if not self:Available() then return end
	if not Stoa:IsModuleEnabled("Halo") or not self:Build() then return end
	-- The API says when its numbers change; health moves on its own, so a
	-- light tick keeps the bars' scale current while DoTs are up.
	pcall(DoesItDie.RegisterCallback, "Stoa", function(_, unit)
		if unit == "target" then self:Update() end
	end)
	Stoa:On("PLAYER_TARGET_CHANGED", function() self:Update() end)
	local elapsed = 0
	self.clip:GetParent():HookScript("OnUpdate", function(_, delta)
		elapsed = elapsed + delta
		if elapsed < UPDATE then return end
		elapsed = 0
		if self.clip:IsShown() or self.window:IsShown() then self:Update() end
	end)
	self:Update()
end
