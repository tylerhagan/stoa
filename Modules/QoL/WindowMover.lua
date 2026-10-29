-- Stoa QoL: move Blizzard windows. Hold Shift and
-- drag a quest, gossip, merchant, bag, character, spellbook, mail or other
-- window by any empty part of it. It keeps that spot every time it opens,
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
	"ContainerFrame1",
}

WindowMover.windows = WINDOWS

local hooked = {}

local function spots()
	Stoa.db.windows = Stoa.db.windows or {}
	return Stoa.db.windows
end

-- A protected window can't move in combat.
local function canMove(frame)
	return not (InCombatLockdown() and frame:IsProtected())
end

local function place(name, frame)
	if Stoa:SharedBy("windows") then return end
	local spot = spots()[name]
	if not spot or not frame:IsShown() or not canMove(frame) then return end
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

	frame:HookScript("OnMouseDown", function(window, button)
		if not self:Wants() or not canMove(window) then return end
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
	end)
	frame:HookScript("OnMouseUp", function(window)
		if not window.stoaMoving then return end
		window.stoaMoving = nil
		window:StopMovingOrSizing()
		-- Stoa keeps the spot, not the game's layout cache.
		if window.SetUserPlaced then window:SetUserPlaced(false) end
		local left, top = window:GetLeft(), window:GetTop()
		if left and top then spots()[name] = { left, top } end
	end)
	frame:HookScript("OnShow", function(window)
		xpcall(place, Stoa.catch, name, window)
	end)
	xpcall(place, Stoa.catch, name, frame)
end

function WindowMover:HookAll()
	for _, name in ipairs(WINDOWS) do
		xpcall(self.Hook, Stoa.catch, self, name)
	end
end

-- Puts every open moved window back on its spot, after the game's own
-- layout has had its turn.
function WindowMover:PlaceAll()
	C_Timer.After(0, function()
		for name in pairs(spots()) do
			local frame = _G[name]
			if type(frame) == "table" and hooked[name] then xpcall(place, Stoa.catch, name, frame) end
		end
	end)
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
