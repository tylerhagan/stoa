-- Stoa: the threat meter.
-- Up to five people in your group, ranked by how close each is to pulling
-- the enemy you are looking at (or, with no target of your own, the enemy
-- your tank is fighting). It is dressed like the damage meters: outlined
-- words over faint bars, no panel. Your row takes the accent, names carry
-- class colour, and whoever holds the enemy is marked TANK.
--
-- Shown in combat while grouped and with an enemy to read, unless you pick
-- another rule. Threat numbers may be hidden by the game; a hidden number
-- is left out rather than guessed.
local _, ns = ...
local Stoa = ns.Stoa
local UI = Stoa.UI

local Threat = Stoa:NewModule("Threat", {
	show = "GROUP",
	combatOnly = true,
})

local ROWS = 5
local WIDTH, ROW_HEIGHT = 220, 16
local THROTTLE = 0.25
local INSET = 6

local call = Stoa.safe.call

local plain = Stoa.safe.plain

-- The enemy to read: your target if you can attack it, else whatever your
-- group's tank is facing.
function Threat:Mob()
	local function hostile(unit)
		if not UnitExists(unit) then return false end
		local attackable = plain(call(UnitCanAttack, "player", unit))
		local dead = plain(call(UnitIsDead, unit))
		return attackable == true and dead ~= true
	end
	if hostile("target") then return "target" end
	for _, unit in ipairs(Stoa:GroupUnits()) do
		if unit ~= "player" and UnitExists(unit) then
			local role = plain(call(UnitGroupRolesAssigned, unit))
			if role == "TANK" and hostile(unit .. "target") then return unit .. "target" end
		end
	end
end

-- A list of { unit, name, class, percent, tanking }, the tank first and
-- then highest threat first.
function Threat:Gather()
	local mob = self:Mob()
	if not mob then return {}, nil end
	local list = {}
	for _, unit in ipairs(Stoa:GroupUnits()) do
		if UnitExists(unit) then
			local tanking, _, scaled = call(UnitDetailedThreatSituation, unit, mob)
			tanking, scaled = plain(tanking), plain(scaled)
			if type(scaled) == "number" or tanking == true then
				local name = plain(call(UnitName, unit))
				local _, class = call(UnitClass, unit)
				list[#list + 1] = {
					unit = unit, name = type(name) == "string" and name or "?",
					class = plain(class), percent = type(scaled) == "number" and scaled or 100,
					tanking = tanking == true,
				}
			end
		end
	end
	table.sort(list, function(a, b)
		if a.tanking ~= b.tanking then return a.tanking end
		return a.percent > b.percent
	end)
	return list, mob
end

-- Frame ----------------------------------------------------------------------

local function font(fs, token)
	Stoa:SetFont(fs, "sans", Stoa.typeSize.body)
	UI.legible(fs)
	fs:SetTextColor(Stoa:Color(token or "text"))
end

function Threat:Build()
	if self.frame then return self.frame end
	local frame = CreateFrame("Frame", "StoaThreat", UIParent)
	frame:SetSize(WIDTH, ROWS * ROW_HEIGHT)
	frame:SetFrameStrata("LOW")
	frame:EnableMouse(false)
	-- Under the damage meters' strip when it is there, else the same corner.
	local meters = Stoa.modules.Meters
	local anchor = meters and meters.Anchor and meters:Anchor()
	if anchor then
		frame:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", INSET, -8)
	else
		frame:SetPoint("TOPLEFT", UIParent, "TOPLEFT", INSET, -184)
	end
	frame:SetAlpha(0)
	frame.rows = {}
	for i = 1, ROWS do
		local row = CreateFrame("Frame", nil, frame)
		row:SetSize(WIDTH, ROW_HEIGHT - 2)
		row:SetPoint("TOPLEFT", 0, -(i - 1) * ROW_HEIGHT)
		row.bar = row:CreateTexture(nil, "BACKGROUND")
		row.bar:SetTexture(UI.WHITE)
		row.bar:SetPoint("TOPLEFT")
		row.bar:SetPoint("BOTTOMLEFT")
		row.bar:SetWidth(1)
		row.name = row:CreateFontString(nil, "OVERLAY")
		font(row.name, "text")
		row.name:SetPoint("LEFT", 4, 0)
		row.name:SetWidth(WIDTH - 70)
		row.name:SetJustifyH("LEFT")
		row.name:SetWordWrap(false)
		row.value = row:CreateFontString(nil, "OVERLAY")
		font(row.value, "text")
		row.value:SetPoint("RIGHT", -4, 0)
		row.value:SetJustifyH("RIGHT")
		row:Hide()
		frame.rows[i] = row
	end
	self.frame = frame
	Stoa:RegisterMover("threat", frame, "Threat meter")
	return frame
end

local function paintRow(row, entry)
	if not entry then row:Hide() return end
	row:Show()
	local mine = entry.unit == "player"
	local r, g, b = Stoa:Color(mine and "accent" or "muted")
	row.bar:SetVertexColor(r, g, b, mine and 0.55 or 0.3)
	row.bar:SetWidth(math.max(1, WIDTH * math.min(entry.percent, 100) / 100))
	row.name:SetText(entry.name)
	local color = Stoa:Theme().classTint and entry.class and RAID_CLASS_COLORS[entry.class]
	if color then
		row.name:SetTextColor(color.r, color.g, color.b)
	else
		row.name:SetTextColor(Stoa:Color("text"))
	end
	row.value:SetText(entry.tanking and "TANK" or (math.floor(entry.percent + 0.5) .. "%"))
	row.value:SetTextColor(Stoa:Color(mine and "accent" or "text"))
end

function Threat:Refresh()
	local frame = self.frame
	if not frame then return end
	local list, mob = self:Gather()
	self.mob, self.list = mob, list
	for i = 1, ROWS do paintRow(frame.rows[i], list[i]) end
	-- Whether there is anything to show can change without a target change.
	local has = mob ~= nil
	if has ~= self.had then
		self.had = has
		Stoa:Fire("STOA_RULES_CHANGED")
	end
end

-- Folds the busy threat events into one pass every quarter second.
function Threat:Soon()
	if self.pending then return end
	self.pending = true
	C_Timer.After(THROTTLE, function()
		self.pending = false
		xpcall(self.Refresh, Stoa.catch, self)
	end)
end

-- Out of combat, or with nobody to read, the meter steps aside whatever
-- the setting says.
function Threat:Rule()
	local db = self.db
	if db.show == "NEVER" then return "NEVER" end
	if db.combatOnly and Stoa:GetState() ~= Stoa.STATE_COMBAT then return "NEVER" end
	if not self.mob then return "NEVER" end
	return db.show or "GROUP"
end

function Threat:OnEnable()
	self:Build()
	Stoa.Rules.watch(self.frame, function() return self:Rule() end)
	for _, event in ipairs({ "UNIT_THREAT_LIST_UPDATE", "UNIT_THREAT_SITUATION_UPDATE", "PLAYER_TARGET_CHANGED", "STOA_GROUP_CHANGED", "STOA_STATE_CHANGED", "PLAYER_REGEN_DISABLED", "STOA_THEME_CHANGED" }) do
		Stoa:On(event, function() self:Soon() end)
	end
	self:Refresh()
end
