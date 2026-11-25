-- Stoa QoL: move Blizzard windows. Hold Shift and
-- drag a quest, gossip, merchant, bag, character, spellbook, mail or other
-- window by any empty part of it, its header too. It keeps that spot every time it opens,
-- since the game would otherwise put it back. Shift and right-click puts a
-- window back where the game wants it.
--
-- Dragging starts from the window itself, never from an item or button on
-- it, so Shift-clicking an item still splits a stack or links it.
local _, ns = ...
local Stoa = ns.Stoa
local hooksecurefunc = Stoa.SafeHook

-- Shift only: Alt and Ctrl are left free for the player's own bindings.
local WindowMover = Stoa:NewModule("WindowMover", {})

-- Windows that can be moved. Load-on-demand ones are picked up when their
-- Blizzard addon loads.
local WINDOWS = {
	"QuestFrame", "QuestLogFrame", "GossipFrame", "MerchantFrame", "ClassTrainerFrame",
	"CharacterFrame", "InspectFrame", "DressUpFrame", "SpellBookFrame", "PlayerSpellsFrame",
	"PlayerTalentFrame", "TalentFrame", "MailFrame", "OpenMailFrame", "FriendsFrame",
	"CommunitiesFrame", "AuctionHouseFrame", "BankFrame", "GuildBankFrame", "TradeFrame",
	"PVEFrame", "LFGParentFrame", "ItemTextFrame", "TaxiFrame", "TradeSkillFrame",
	"ProfessionsFrame", "CraftFrame", "AchievementFrame", "ContainerFrameCombinedBags",
	"ContainerFrame1", "WorldMapFrame", "ProfessionsBookFrame", "MacroFrame", "CollectionsJournal",
	"EncounterJournal", "StableFrame", "ItemSocketingFrame",
}

-- Windows that stay put in one of their states: the map fills the screen
-- when maximised, so only its windowed size moves.
local HELD = {
	WorldMapFrame = function(frame) return frame.IsMaximized and frame:IsMaximized() end,
}

WindowMover.windows = WINDOWS

local hooked = {}

local function spots()
	Stoa.db.windows = Stoa.db.windows or {}
	return Stoa.db.windows
end

-- A protected window can't move in combat.
local function canMove(frame, name)
	if InCombatLockdown() and frame:IsProtected() then return false end
	local held = name and HELD[name]
	return not (held and held(frame))
end

local function place(name, frame)
	if Stoa:SharedBy("windows") then return end
	local spot = spots()[name]
	if not spot or not frame:IsShown() or not canMove(frame, name) then return end
	frame:ClearAllPoints()
	frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", spot[1], spot[2])
end

-- Another addon moving these windows already (Core/Companions.lua) keeps
-- them: Stoa neither starts a drag nor puts a window back on its own spot.
local function shared()
	return Stoa:SharedBy("windows")
end

function WindowMover:Wants()
	return IsShiftKeyDown() and not shared()
end

function WindowMover:Hook(name)
	local frame = _G[name]
	if hooked[name] or type(frame) ~= "table" or not frame.HookScript then return end
	if frame.IsForbidden and frame:IsForbidden() then return end
	hooked[name] = true

	local function down(window, button)
		if not self:Wants() or not canMove(window, name) then return end
		if button == "RightButton" then
			spots()[name] = nil
			Stoa:Print(("%s goes back to its usual place next time it opens."):format(name:gsub("Frame$", "")))
			return
		end
		if button ~= "LeftButton" then return end
		window:SetMovable(true)
		window:SetClampedToScreen(true)
		window:StartMoving()
		window.stoaMoving = true
	end
	local function up(window)
		if not window.stoaMoving then return end
		window.stoaMoving = nil
		window:StopMovingOrSizing()
		-- Stoa keeps the spot, not the game's layout cache.
		if window.SetUserPlaced then window:SetUserPlaced(false) end
		local left, top = window:GetLeft(), window:GetTop()
		if left and top then spots()[name] = { left, top } end
	end
	frame:HookScript("OnMouseDown", down)
	frame:HookScript("OnMouseUp", up)
	frame.stoaMoveDown, frame.stoaMoveUp = down, up
	-- The header is often a frame of its own that takes the mouse (the
	-- title bar), so a drag there never reached the window: hand it on.
	self:HookHeader(frame, down, up)
	frame:HookScript("OnShow", function(window)
		xpcall(place, Stoa.catch, name, window)
		-- Laid out now, so the frames along its top can be found.
		xpcall(self.HookHeader, Stoa.catch, self, window, down, up)
	end)
	xpcall(place, Stoa.catch, name, frame)
end

local HEADER_KEYS = { "TitleContainer", "TitleBar", "DragBar", "TitleButton", "Header", "TitleRegion" }
local HEADER_REACH = 48

function WindowMover:HookHeader(frame, down, up)
	local function take(child)
		if type(child) ~= "table" or child.stoaHeaderHooked or not child.HookScript then return end
		if child.IsForbidden and child:IsForbidden() then return end
		-- Buttons keep their clicks (close, tabs, dropdowns).
		if child.IsObjectType and child:IsObjectType("Button") then return end
		child.stoaHeaderHooked = true
		child:HookScript("OnMouseDown", function(_, button) down(frame, button) end)
		child:HookScript("OnMouseUp", function() up(frame) end)
	end
	for _, key in ipairs(HEADER_KEYS) do take(frame[key]) end
	-- Any other mouse-taking frame along the top edge.
	local okTop, top = pcall(frame.GetTop, frame)
	if not okTop then return end
	-- Some children are forbidden (the game's own secure frames): asking
	-- them anything is an error, so they're skipped, and each look is guarded.
	for _, child in ipairs({ frame:GetChildren() }) do
		local forbidden = child.IsForbidden and child:IsForbidden()
		if not forbidden then
			local ok, childTop, height, mouse = pcall(function()
				return child:GetTop(), child:GetHeight(), child.IsMouseEnabled and child:IsMouseEnabled()
			end)
			if ok and top and childTop and height and mouse and height <= HEADER_REACH * 1.5
				and top - childTop <= HEADER_REACH then
				take(child)
			end
		end
	end
end

-- A page that rises into its window's header after the window is laid out
-- (the talents) brings frames of its own up there, which took the press
-- before the window saw it. Its frames along the header hand a Shift-drag
-- on to the window too. `page` is searched a few levels down.
function WindowMover:HookRaised(frame, page)
	local down, up = frame and frame.stoaMoveDown, frame and frame.stoaMoveUp
	if not (down and up and page) then return end
	local okTop, top = pcall(frame.GetTop, frame)
	if not okTop or not top then return end
	local function look(parent, depth)
		for _, child in ipairs({ parent:GetChildren() }) do
			if not (child.IsForbidden and child:IsForbidden()) then
				local ok, childTop, mouse, button = pcall(function()
					return child:GetTop(), child.IsMouseEnabled and child:IsMouseEnabled(), child.IsObjectType and child:IsObjectType("Button")
				end)
				if ok and childTop and top - childTop <= HEADER_REACH * 1.5 then
					if mouse and not button and not child.stoaHeaderHooked and child.HookScript then
						child.stoaHeaderHooked = true
						child:HookScript("OnMouseDown", function(_, which) down(frame, which) end)
						child:HookScript("OnMouseUp", function() up(frame) end)
					end
					if depth < 3 then look(child, depth + 1) end
				end
			end
		end
	end
	pcall(look, page, 1)
end

function WindowMover:HookAll()
	for _, name in ipairs(WINDOWS) do
		xpcall(self.Hook, Stoa.catch, self, name)
	end
end

-- Puts every open moved window back on its spot, after the game's own
-- layout has had its turn.
function WindowMover:PlaceAll()
	local function all()
		for name in pairs(spots()) do
			local frame = _G[name]
			if type(frame) == "table" and hooked[name] then xpcall(place, Stoa.catch, name, frame) end
		end
	end
	-- At once, so a moved window is never drawn for a frame on the game's
	-- spot and then seen to jump back (opening the spellbook beside the
	-- character sheet did that to both), and once more when the game has
	-- finished, in case it lays things out again after this.
	all()
	C_Timer.After(0, all)
end

function WindowMover:OnEnable()
	self:HookAll()
	Stoa:On("ADDON_LOADED", function(addon)
		if type(addon) == "string" and addon:find("^Blizzard_") then self:HookAll() end
	end)
	-- The game lays its side panels out again whenever one opens or
	-- closes, and the bags whenever a bag does.
	if UpdateUIPanelPositions then hooksecurefunc("UpdateUIPanelPositions", function() self:PlaceAll() end) end
	if UpdateContainerFrameAnchors then hooksecurefunc("UpdateContainerFrameAnchors", function() self:PlaceAll() end) end
end

-- /stoa windows reset puts every window back.
Stoa.commands.windows = function(rest)
	if rest == "reset" then
		wipe(spots())
		Stoa:Print("Windows go back to their usual places as they next open.")
	else
		Stoa:Print("Hold Shift and drag a window to move it; Shift and right-click puts it back. /stoa windows reset puts them all back.")
	end
end
