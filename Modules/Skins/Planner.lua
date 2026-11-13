-- Stoa: the talent planner. Plans a build point by point over the game's own
-- talent trees, for levels you haven't reached yet: each planned talent
-- carries the level it's taken at, your next point glows in the trees, and a
-- panel beside the window lists the order, shows the build at any level and
-- shares plans as text. Plans are kept per class (account-wide), several
-- per class, each with a name.
--
-- STOA never spends a point: you click the talent as always. "Make game
-- loadout" hands the plan, up to your level, to the game's own loadout
-- import, and the game's Apply finishes it. Nothing of Blizzard's is
-- written or moved; STOA's marks sit over the talent buttons and only take
-- the mouse while planning.
local _, ns = ...
local Stoa = ns.Stoa
local UI = Stoa.UI

local Planner = Stoa:NewModule("Planner", { enabled = true, active = nil })

local guarded = Stoa.safe.guarded
local call = Stoa.safe.call

local FIRST_LEVEL, MAX_LEVEL = 10, 60
local PER_ROW = 5
local PANEL_WIDTH, PAD = 290, 18
local LIST_ROWS = 9

-- Plans ------------------------------------------------------------------------

local function classKey()
	local _, class = UnitClass("player")
	return class or "?"
end

local function store()
	StoaDB.talentPlans = StoaDB.talentPlans or {}
	local key = classKey()
	StoaDB.talentPlans[key] = StoaDB.talentPlans[key] or {}
	return StoaDB.talentPlans[key]
end

function Planner:Plans() return store() end

function Planner:Active()
	local plans = store()
	for _, plan in ipairs(plans) do
		if plan.name == self.db.active then return plan end
	end
	return plans[1]
end

function Planner:NewPlan(name, order)
	local plans = store()
	local base = name or "New plan"
	local taken = {}
	for _, plan in ipairs(plans) do taken[plan.name] = true end
	local pick, n = base, 1
	while taken[pick] do
		n = n + 1
		pick = base .. " " .. n
	end
	local plan = { name = pick, order = order or {} }
	plans[#plans + 1] = plan
	self.db.active = plan.name
	return plan
end

function Planner:Step(by)
	local plans = store()
	if #plans < 2 then return end
	local index = 1
	local active = self:Active()
	for i, plan in ipairs(plans) do if plan == active then index = i end end
	index = (index - 1 + by) % #plans + 1
	self.db.active = plans[index].name
	self:Refresh()
end

function Planner:DeletePlan()
	local plans = store()
	local active = self:Active()
	for i, plan in ipairs(plans) do
		if plan == active then table.remove(plans, i) break end
	end
	self.db.active = plans[1] and plans[1].name or nil
	self:Refresh()
end

-- "STOA1:" then each point as a node id (and the choice taken, after a dot).
function Planner.Encode(plan)
	local parts = {}
	for _, pick in ipairs(plan.order) do
		parts[#parts + 1] = pick.e and (pick.n .. "." .. pick.e) or tostring(pick.n)
	end
	return "STOA1:" .. table.concat(parts, ",")
end

function Planner.Decode(text)
	text = text and strtrim(text) or ""
	local body = text:match("^STOA1:(.*)$")
	if not body then return nil end
	local order = {}
	for piece in body:gmatch("[^,]+") do
		local node, entry = piece:match("^(%d+)%.?(%d*)$")
		if not node then return nil end
		order[#order + 1] = { n = tonumber(node), e = tonumber(entry) }
	end
	return order
end

-- The trees ---------------------------------------------------------------------

local function talentsFrame()
	return PlayerSpellsFrame and PlayerSpellsFrame.TalentsFrame
end

local function configID(talents)
	local id = talents and talents.GetConfigID and talents:GetConfigID()
	if not id and C_ClassTalents then id = call(C_ClassTalents.GetActiveConfigID) end
	return id
end

local function nodeInfo(talents, nodeID)
	local id = configID(talents)
	if not (id and C_Traits and C_Traits.GetNodeInfo) then return nil end
	return call(C_Traits.GetNodeInfo, id, nodeID)
end

-- A talent's name, from the entry it grants.
local nameCache = {}
local function nodeName(talents, nodeID, entryID)
	local key = nodeID .. "." .. (entryID or 0)
	if nameCache[key] then return nameCache[key] end
	local info = nodeInfo(talents, nodeID)
	local entry = entryID or (info and info.entryIDs and info.entryIDs[1])
	local id = configID(talents)
	local name
	if entry and id and C_Traits.GetEntryInfo then
		local entryInfo = call(C_Traits.GetEntryInfo, id, entry)
		local def = entryInfo and entryInfo.definitionID and call(C_Traits.GetDefinitionInfo, entryInfo.definitionID)
		local spell = def and (def.spellID or def.overriddenSpellID)
		if def and def.overrideName and def.overrideName ~= "" then name = def.overrideName end
		if not name and spell then
			name = (C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(spell)) or (GetSpellInfo and GetSpellInfo(spell))
		end
		nameCache[key .. ":spell"] = spell
	end
	name = name or "?"
	nameCache[key] = name
	return name
end

local function nodeSpell(talents, nodeID, entryID)
	nodeName(talents, nodeID, entryID)
	return nameCache[nodeID .. "." .. (entryID or 0) .. ":spell"]
end

-- Where each talent sits: its button, its tree (by the nearest tree
-- header) and its row in that tree, from the top.
function Planner:Layout(talents)
	local out = {}
	local headers = talents.treeHeaders
	if not (talents.EnumerateAllTalentButtons) then return out end
	local centres = {}
	for i, header in ipairs(headers or {}) do centres[i] = select(1, header:GetCenter()) end
	local rowsByTree = {}
	for button in talents:EnumerateAllTalentButtons() do
		local nodeID = button.GetNodeID and button:GetNodeID()
		local x, y = button:GetCenter()
		if nodeID and x and y and button:IsShown() then
			local tree, gap = 1, math.huge
			for i, cx in ipairs(centres) do
				if cx and math.abs(cx - x) < gap then tree, gap = i, math.abs(cx - x) end
			end
			-- Rounded to 6px, so a talent a pixel off its row still shares it.
			local rowY = math.floor(y / 6 + 0.5)
			out[nodeID] = { button = button, tree = tree, y = rowY }
			rowsByTree[tree] = rowsByTree[tree] or {}
			rowsByTree[tree][rowY] = true
		end
	end
	-- Rows, top first.
	local rank = {}
	for tree, ys in pairs(rowsByTree) do
		local list = {}
		for y in pairs(ys) do list[#list + 1] = y end
		table.sort(list, function(a, b) return a > b end)
		rank[tree] = {}
		for i, y in ipairs(list) do rank[tree][y] = i - 1 end
	end
	for _, spot in pairs(out) do spot.row = rank[spot.tree][spot.y] or 0 end
	self.layout = out
	return out
end

-- How the plan stands at a level: ranks per talent, the pick index each
-- talent was last raised at, and points per tree.
local function tally(plan, upTo)
	local ranks, at = {}, {}
	for i, pick in ipairs(plan and plan.order or {}) do
		if i > upTo then break end
		ranks[pick.n] = (ranks[pick.n] or 0) + 1
		at[pick.n] = i
	end
	return ranks, at
end

-- Whether a point can go here next: room in the talent, and enough points
-- already in its tree for its row.
function Planner:CanAdd(plan, nodeID)
	local talents = talentsFrame()
	local spot = self.layout and self.layout[nodeID]
	if not spot then return false end
	if #plan.order >= MAX_LEVEL - FIRST_LEVEL + 1 then return false, "The plan is full: 51 points." end
	local info = nodeInfo(talents, nodeID)
	local max = info and info.maxRanks or 1
	local ranks = tally(plan, #plan.order)
	if (ranks[nodeID] or 0) >= max then return false, "That talent is full." end
	local inTree = 0
	for _, pick in ipairs(plan.order) do
		local other = self.layout[pick.n]
		if other and other.tree == spot.tree then inTree = inTree + 1 end
	end
	if inTree < spot.row * PER_ROW then
		return false, ("That row needs %d points in this tree first."):format(spot.row * PER_ROW)
	end
	return true
end

-- Removing a talent's last point, unless a later pick leans on it (a
-- deeper row that would lose its points).
function Planner:Remove(plan, nodeID)
	for i = #plan.order, 1, -1 do
		if plan.order[i].n == nodeID then
			table.remove(plan.order, i)
			return true
		end
	end
	return false
end

-- The next point to spend: the first pick beyond what you have.
function Planner:Next(talents, plan)
	if not plan then return nil end
	local seen = {}
	for i, pick in ipairs(plan.order) do
		seen[pick.n] = (seen[pick.n] or 0) + 1
		local info = nodeInfo(talents, pick.n)
		local have = info and (info.ranksPurchased or info.currentRank or info.activeRank) or 0
		if seen[pick.n] > have then return i, pick end
	end
	return nil
end

-- Marks on the trees --------------------------------------------------------------

local function newMark(talents, button)
	local mark = CreateFrame("Button", nil, talents)
	mark:SetFrameLevel((button:GetFrameLevel() or 1) + 6)
	mark:SetAllPoints(button)
	mark:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	mark:EnableMouse(false)
	local ring = UI.roundBorder(mark, "CardEdge.tga", 1, 3)
	local veil = mark:CreateTexture(nil, "BACKGROUND")
	veil:SetTexture(UI.WHITE)
	veil:SetAllPoints()
	veil:SetVertexColor(0, 0, 0, 0.45)
	veil:Hide()
	local tag = CreateFrame("Frame", nil, mark)
	tag:SetSize(22, 15)
	tag:SetPoint("BOTTOMRIGHT", 6, -5)
	local fill = UI.pillFill(tag, 0)
	fill:SetVertexColor(0, 0, 0, 0.85)
	local number = UI.text(tag, "sans", Stoa.typeSize.caption, "accent")
	number:SetPoint("CENTER", 0, 0)
	tag:Hide()
	-- The next point breathes, gently.
	local glow = UI.roundBorder(mark, "CardEdge.tga", 2, 5)
	local breathe = mark:CreateAnimationGroup()
	breathe:SetLooping("BOUNCE")
	local fade = breathe:CreateAnimation("Alpha")
	fade:SetFromAlpha(1)
	fade:SetToAlpha(0.35)
	fade:SetDuration(0.7)
	fade:SetSmoothing("IN_OUT")
	mark.ring, mark.veil, mark.tag, mark.number, mark.glow, mark.breathe = ring, veil, tag, number, glow, breathe
	mark.tagIn = UI.intro(tag, 0, 3, UI.MOTION.quick)
	mark:SetScript("OnClick", function(own, mouse)
		Planner:ClickMark(own, mouse)
	end)
	mark:SetScript("OnEnter", function(own)
		local spell = own.nodeID and nodeSpell(talents, own.nodeID)
		GameTooltip:SetOwner(own, "ANCHOR_RIGHT")
		if spell then GameTooltip:SetSpellByID(spell) else GameTooltip:AddLine(nodeName(talents, own.nodeID)) end
		GameTooltip:AddLine("Click to plan a point here; right-click to take one off.", 0.8, 0.8, 0.8, true)
		GameTooltip:Show()
	end)
	mark:SetScript("OnLeave", GameTooltip_Hide)
	return mark
end

function Planner:ClickMark(mark, mouse)
	local plan = self:Active() or self:NewPlan()
	local nodeID = mark.nodeID
	if mouse == "RightButton" then
		self:Remove(plan, nodeID)
	else
		local ok, why = self:CanAdd(plan, nodeID)
		if not ok then
			if why then UIErrorsFrame:AddMessage(why, 1, 0.82, 0.4) end
			return
		end
		local info = nodeInfo(talentsFrame(), nodeID)
		local entry = info and info.entryIDs and #info.entryIDs > 1 and info.entryIDs[1] or nil
		plan.order[#plan.order + 1] = { n = nodeID, e = entry }
		-- Follow the plan as it grows.
		self.level = math.max(self.level or 0, FIRST_LEVEL - 1 + #plan.order)
	end
	self:Refresh()
end

function Planner:PaintMarks()
	local talents = talentsFrame()
	if not (talents and talents:IsVisible()) then return end
	local layout = self:Layout(talents)
	self.marks = self.marks or {}
	local plan = self:Active()
	local upTo = (self.level or MAX_LEVEL) - FIRST_LEVEL + 1
	local ranks, at = tally(plan, math.max(0, upTo))
	local nextIndex, nextPick = self:Next(talents, plan)
	for _, mark in pairs(self.marks) do mark:Hide() end
	for nodeID, spot in pairs(layout) do
		local mark = self.marks[spot.button]
		if not mark then
			mark = newMark(talents, spot.button)
			self.marks[spot.button] = mark
		end
		mark.nodeID = nodeID
		mark:EnableMouse(self.planning and true or false)
		local planned = ranks[nodeID]
		local isNext = nextPick and nextPick.n == nodeID
		if planned then
			mark.ring:Set(Stoa:Color("accent"))
			local lit = isNext and 1 or 0.55
			for _, tex in ipairs(mark.ring.edges or {}) do tex:SetAlpha(lit) end
			local wasShown = mark.tag:IsShown()
			mark.number:SetText(tostring(FIRST_LEVEL - 1 + at[nodeID]))
			mark.tag:Show()
			if not wasShown then mark.tagIn:Play() end
		else
			mark.ring:Clear()
			mark.tag:Hide()
		end
		if isNext then
			mark.glow:Set(Stoa:Color("accent"))
			if not mark.breathe:IsPlaying() then mark.breathe:Play() end
		else
			mark.glow:Clear()
			mark.breathe:Stop()
		end
		-- While planning, talents the plan leaves out step back.
		mark.veil:SetShown(self.planning and not planned)
		mark:Show()
	end
end

-- The panel ---------------------------------------------------------------------

local function wordButton(parent, label, onClick)
	local button = CreateFrame("Button", nil, parent)
	button:SetHeight(20)
	local text = UI.text(button, "sans", Stoa.typeSize.body, "muted", "LEFT")
	text:SetPoint("LEFT")
	text:SetText(label)
	button:SetWidth(math.max(20, (text:GetStringWidth() or 30) + 2))
	button.text = text
	button:SetScript("OnClick", onClick)
	button:SetScript("OnEnter", function() text:SetTextColor(Stoa:Color("accent")) end)
	button:SetScript("OnLeave", function() text:SetTextColor(Stoa:Color(button.lit and "text" or "muted")) end)
	return button
end

function Planner:BuildPanel()
	local panel = CreateFrame("Frame", "StoaPlanner", UIParent)
	panel:SetWidth(PANEL_WIDTH)
	panel:SetFrameStrata("HIGH")
	panel:EnableMouse(true)
	panel:Hide()
	UI.windowPanel(panel, 0.97, { header = 48 })
	panel.stoaRise = UI.intro(panel, 10, 0, UI.MOTION.open)
	panel:HookScript("OnShow", function(own) own.stoaRise:Play() end)

	-- Header: the plan's name (type to rename) and arrows between plans.
	local name = CreateFrame("EditBox", nil, panel)
	name:SetAutoFocus(false)
	name:SetHeight(26)
	name:SetPoint("LEFT", panel, "TOPLEFT", PAD - 4, -24)
	name:SetPoint("RIGHT", panel, "TOPRIGHT", -64, -24)
	name:SetMaxLetters(32)
	name:SetTextInsets(4, 4, 0, 0)
	Stoa:SetFont(name, "serif", Stoa.typeSize.title)
	name:SetTextColor(Stoa:Color("text"))
	name:SetScript("OnEnterPressed", function(box)
		local plan = self:Active()
		local text = strtrim(box:GetText() or "")
		if plan and text ~= "" then
			plan.name = text
			self.db.active = text
		end
		box:ClearFocus()
		self:Refresh()
	end)
	name:SetScript("OnEscapePressed", function(box) box:ClearFocus() self:Refresh() end)
	local back = wordButton(panel, "<", function() self:Step(-1) end)
	local forth = wordButton(panel, ">", function() self:Step(1) end)
	forth:SetPoint("RIGHT", panel, "TOPRIGHT", -PAD, -24)
	back:SetPoint("RIGHT", forth, "LEFT", -10, 0)
	panel.name, panel.back, panel.forth = name, back, forth

	-- Plan / Done, New, Delete.
	local plan = wordButton(panel, "Plan", function() self:SetPlanning(not self.planning) end)
	plan:SetPoint("TOPLEFT", PAD, -60)
	local new = wordButton(panel, "New", function()
		self:NewPlan()
		self:SetPlanning(true)
	end)
	new:SetPoint("LEFT", plan, "RIGHT", 16, 0)
	local clear = wordButton(panel, "Clear", function()
		local active = self:Active()
		if active then wipe(active.order) end
		self:Refresh()
	end)
	clear:SetPoint("LEFT", new, "RIGHT", 16, 0)
	local delete = wordButton(panel, "Delete", function() self:DeletePlan() end)
	delete:SetPoint("LEFT", clear, "RIGHT", 16, 0)
	panel.plan = plan

	-- The level the trees show the build at.
	local levelLabel = UI.text(panel, "sans", Stoa.typeSize.body, "muted", "LEFT")
	levelLabel:SetPoint("TOPLEFT", PAD, -94)
	levelLabel:SetText("Show the build at level")
	local levelValue = UI.text(panel, "sans", Stoa.typeSize.label, "text", "RIGHT")
	levelValue:SetPoint("TOPRIGHT", -PAD, -94)
	local slider = CreateFrame("Slider", nil, panel)
	slider:SetOrientation("HORIZONTAL")
	slider:SetHeight(16)
	slider:SetPoint("TOPLEFT", PAD, -114)
	slider:SetPoint("TOPRIGHT", -PAD, -114)
	slider:SetMinMaxValues(FIRST_LEVEL, MAX_LEVEL)
	slider:SetValueStep(1)
	slider:SetObeyStepOnDrag(true)
	local track = slider:CreateTexture(nil, "BACKGROUND")
	track:SetTexture(UI.WHITE)
	track:SetHeight(4)
	track:SetPoint("LEFT")
	track:SetPoint("RIGHT")
	track:SetVertexColor(1, 1, 1, 0.1)
	local filled = slider:CreateTexture(nil, "ARTWORK")
	filled:SetTexture(UI.WHITE)
	filled:SetHeight(4)
	filled:SetPoint("LEFT")
	UI.paint(filled, "accent")
	local thumb = slider:CreateTexture(nil, "OVERLAY")
	thumb:SetSize(12, 12)
	thumb:SetTexture(UI.WHITE)
	if thumb.SetMask then pcall(thumb.SetMask, thumb, "Interface\\CharacterFrame\\TempPortraitAlphaMask") end
	UI.paint(thumb, "text")
	slider:SetThumbTexture(thumb)
	slider:SetScript("OnValueChanged", function(own, value)
		value = math.floor(value + 0.5)
		levelValue:SetText(tostring(value))
		local width = own:GetWidth() or 0
		filled:SetWidth(math.max(1, width * (value - FIRST_LEVEL) / (MAX_LEVEL - FIRST_LEVEL)))
		if self.level ~= value then
			self.level = value
			if not self.painting then self:PaintMarks() self:FillList() end
		end
	end)
	panel.slider = slider

	-- The order: the next points from where you are.
	local head = UI.text(panel, "sans", Stoa.typeSize.caption, "accent", "LEFT")
	head:SetPoint("TOPLEFT", PAD, -146)
	head:SetText("NEXT POINTS")
	panel.head = head
	panel.rows = {}
	for i = 1, LIST_ROWS do
		local row = CreateFrame("Frame", nil, panel)
		row:SetHeight(24)
		row:SetPoint("TOPLEFT", PAD, -162 - (i - 1) * 24)
		row:SetPoint("RIGHT", panel, "RIGHT", -PAD, 0)
		local level = UI.text(row, "sans", Stoa.typeSize.body, "muted", "LEFT")
		level:SetPoint("LEFT")
		level:SetWidth(28)
		local what = UI.text(row, "sans", Stoa.typeSize.body, "text", "LEFT")
		what:SetPoint("LEFT", level, "RIGHT", 6, 0)
		what:SetPoint("RIGHT")
		what:SetWordWrap(false)
		local rule = UI.line(row, "hairline")
		rule:SetPoint("BOTTOMLEFT")
		rule:SetPoint("BOTTOMRIGHT")
		row.level, row.what = level, what
		row.intro = UI.intro(row, 0, 3, UI.MOTION.quick, (i - 1) * UI.MOTION.stagger)
		panel.rows[i] = row
	end
	local empty = UI.text(panel, "italic", Stoa.typeSize.body, "muted", "LEFT")
	empty:SetPoint("TOPLEFT", PAD, -166)
	empty:SetPoint("RIGHT", panel, "RIGHT", -PAD, 0)
	panel.empty = empty

	-- The game's loadout, and sharing.
	local y = -162 - LIST_ROWS * 24 - 16
	local loadout = UI.button(panel, "Make game loadout", PANEL_WIDTH - PAD * 2, function() self:MakeLoadout() end)
	loadout:SetPoint("TOPLEFT", PAD, y)
	panel.loadout = loadout
	local share = CreateFrame("EditBox", nil, panel)
	share:SetAutoFocus(false)
	share:SetHeight(26)
	share:SetPoint("TOPLEFT", PAD, y - 40)
	share:SetPoint("RIGHT", panel, "RIGHT", -PAD, 0)
	share:SetTextInsets(10, 10, 0, 0)
	Stoa:SetFont(share, "sans", Stoa.typeSize.caption)
	share:SetTextColor(Stoa:Color("text"))
	local shareBack = UI.pillFill(share, 0)
	shareBack:SetVertexColor(0, 0, 0, 0.4)
	local shareHint = UI.text(share, "sans", Stoa.typeSize.caption, "muted")
	shareHint:SetPoint("LEFT", 10, 0)
	shareHint:SetText("Paste a plan here and press Enter")
	share:SetScript("OnTextChanged", function(box) shareHint:SetShown(box:GetText() == "" and not box:HasFocus()) end)
	share:SetScript("OnEditFocusGained", function() shareHint:Hide() end)
	share:SetScript("OnEditFocusLost", function(box) shareHint:SetShown(box:GetText() == "") end)
	share:SetScript("OnEscapePressed", function(box) box:SetText("") box:ClearFocus() end)
	share:SetScript("OnEnterPressed", function(box)
		local order = Planner.Decode(box:GetText())
		if order then
			self:NewPlan("Pasted plan", order)
			box:SetText("")
			self:Say("Plan added.")
		else
			self:Say("That isn't a STOA plan.")
		end
		box:ClearFocus()
		self:Refresh()
	end)
	local copy = wordButton(panel, "Copy this plan", function()
		local active = self:Active()
		if not active then return end
		share:SetText(Planner.Encode(active))
		share:SetFocus()
		share:HighlightText()
		self:Say("Selected: press Ctrl+C to copy.")
	end)
	copy:SetPoint("TOPLEFT", share, "BOTTOMLEFT", 0, -8)
	local note = UI.text(panel, "sans", Stoa.typeSize.caption, "muted", "LEFT")
	note:SetPoint("TOPLEFT", copy, "BOTTOMLEFT", 0, -8)
	note:SetPoint("RIGHT", panel, "RIGHT", -PAD, 0)
	panel.note = note
	panel:SetHeight(-y + 40 + 28 + 26 + 20)
	self.panel = panel
end

function Planner:Say(words)
	if not self.panel then return end
	self.panel.note:SetText(words or "")
	if words then UI.fadeIn(self.panel.note, UI.MOTION.quick):Play() end
end

function Planner:SetPlanning(on)
	self.planning = on and true or false
	if self.planning and not self:Active() then self:NewPlan() end
	self:Refresh()
end

function Planner:FillList()
	local panel = self.panel
	if not panel then return end
	local talents = talentsFrame()
	local plan = self:Active()
	local from = self:Next(talents, plan) or ((plan and #plan.order or 0) + 1)
	local shown = 0
	for i, row in ipairs(panel.rows) do
		local index = from + i - 1
		local pick = plan and plan.order[index]
		local within = pick and (FIRST_LEVEL - 1 + index) <= (self.level or MAX_LEVEL)
		row:SetShown(pick ~= nil)
		if pick then
			shown = shown + 1
			local was = row.pick
			row.pick = pick
			row.level:SetText(tostring(FIRST_LEVEL - 1 + index))
			row.level:SetTextColor(Stoa:Color(i == 1 and "accent" or "muted"))
			row.what:SetText(nodeName(talents, pick.n, pick.e))
			row.what:SetTextColor(Stoa:Color(within and "text" or "muted"))
			if was ~= pick then row.intro:Play() end
		end
	end
	panel.head:SetText(shown > 0 and "NEXT POINTS" or "")
	if not plan or #plan.order == 0 then
		panel.empty:SetText(self.planning
			and "Click talents in the order you'll take them. Right-click takes a point off."
			or "No plan yet. Plan starts one.")
	elseif shown == 0 then
		panel.empty:SetText("You've taken every point in this plan.")
	else
		panel.empty:SetText("")
	end
	panel.empty:SetShown(shown == 0)
end

function Planner:Refresh()
	local talents = talentsFrame()
	local show = self.enabled and talents and talents:IsVisible()
	if not show then
		if self.panel then self.panel:Hide() end
		return
	end
	if not self.panel then self:BuildPanel() end
	local panel = self.panel
	panel:ClearAllPoints()
	panel:SetPoint("TOPLEFT", PlayerSpellsFrame, "TOPRIGHT", 8, 0)
	panel:Show()
	local plan = self:Active()
	if not panel.name:HasFocus() then panel.name:SetText(plan and plan.name or "No plan") end
	local many = #store() > 1
	panel.back:SetShown(many)
	panel.forth:SetShown(many)
	panel.plan.text:SetText(self.planning and "Done" or "Plan")
	panel.plan.lit = self.planning
	panel.plan.text:SetTextColor(Stoa:Color(self.planning and "accent" or "text"))
	panel.plan:SetWidth((panel.plan.text:GetStringWidth() or 30) + 2)
	if not self.level then
		local level = Stoa:PlainNumber(UnitLevel("player")) or FIRST_LEVEL
		self.level = math.max(FIRST_LEVEL, math.min(MAX_LEVEL, plan and (FIRST_LEVEL - 1 + #plan.order) or level))
		if self.level < FIRST_LEVEL then self.level = MAX_LEVEL end
	end
	self.painting = true
	panel.slider:SetValue(self.level)
	self.painting = false
	panel.loadout:SetEnabled(plan ~= nil and #plan.order > 0 and not InCombatLockdown())
	self:PaintMarks()
	self:FillList()
end

-- The game's loadout: the plan up to the points you have now, handed to the
-- game's own import. The game makes the loadout; its Apply spends them.
function Planner:MakeLoadout()
	local talents = talentsFrame()
	local plan = self:Active()
	if not (talents and plan) or InCombatLockdown() then return end
	if not (C_ClassTalents and C_ClassTalents.ImportLoadout) then
		self:Say("This client can't make loadouts from addons.")
		return
	end
	local level = Stoa:PlainNumber(UnitLevel("player")) or 0
	local points = math.max(0, math.min(#plan.order, level - FIRST_LEVEL + 1))
	if points == 0 then
		self:Say("No talent points yet at your level.")
		return
	end
	local ranks, entries = {}, {}
	for i = 1, points do
		local pick = plan.order[i]
		ranks[pick.n] = (ranks[pick.n] or 0) + 1
		entries[pick.n] = pick.e
	end
	local list = {}
	for nodeID, count in pairs(ranks) do
		list[#list + 1] = { nodeID = nodeID, ranksPurchased = count, ranksGranted = 0, selectionEntryID = entries[nodeID] }
	end
	local ok, success, err = pcall(C_ClassTalents.ImportLoadout, configID(talents), list, plan.name)
	if ok and success then
		self:Say(("Made the loadout \"%s\" with %d points: pick it in the loadout list and press Apply."):format(plan.name, points))
	else
		self:Say("The game didn't take it" .. ((type(err) == "string" and err ~= "") and (": " .. err) or ".") .. " The trees still show your next point.")
	end
end

function Planner:OnEnable()
	local function hook()
		local talents = talentsFrame()
		if not talents or talents.stoaPlanner then return end
		talents.stoaPlanner = true
		talents:HookScript("OnShow", function() C_Timer.After(0, function() guarded(Planner.Refresh, Planner) end) end)
		talents:HookScript("OnHide", function()
			Planner.planning = false
			if Planner.panel then Planner.panel:Hide() end
		end)
		local spellbook = Stoa.modules.Spellbook
		if spellbook then
			hooksecurefunc(Stoa.modules.Spellbook, "DressTrees", function() guarded(Planner.PaintMarks, Planner) end)
		end
	end
	hook()
	Stoa:On("ADDON_LOADED", function(name)
		if name == "Blizzard_PlayerSpells" then hook() end
	end)
	local pending
	local function soon()
		if pending then return end
		pending = true
		C_Timer.After(0.2, function()
			pending = false
			local talents = talentsFrame()
			if talents and talents:IsVisible() then guarded(Planner.Refresh, Planner) end
		end)
	end
	Stoa:On("TRAIT_CONFIG_UPDATED", soon)
	Stoa:On("TRAIT_NODE_CHANGED", soon)
	Stoa:On("PLAYER_LEVEL_UP", soon)
	Stoa:On("PLAYER_REGEN_ENABLED", soon)
	Stoa:On("PLAYER_REGEN_DISABLED", soon)
end

