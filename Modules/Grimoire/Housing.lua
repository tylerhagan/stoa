-- Stoa: houses Blizzard's chat and action bar inside the Grimoire console.
-- Chat takes the console's left page and margin notes move into chat. The
-- action bar keeps its Edit Mode position in the console's centre, but loses
-- its gryphons and border so it sits on the ink.
--
-- Both frames belong to Edit Mode, which re-places them whenever a layout is
-- applied, so Stoa puts them back after each apply. Nothing here runs in
-- combat.
local _, ns = ...
local Stoa = ns.Stoa
local Console = Stoa.modules.Grimoire

local CHAT_WIDTH = 440
local CHAT_BOTTOM = 20
local CHAT_TOP_PAD = 16
local CHAT_TAB_HEIGHT = 22

local function placeChat()
	local chat = ChatFrame1
	if not chat then return end
	chat:ClearAllPoints()
	chat:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", (Console:PageInset()), CHAT_BOTTOM)
	chat:SetSize(CHAT_WIDTH, Console:OpenHeight() - CHAT_BOTTOM - CHAT_TOP_PAD - CHAT_TAB_HEIGHT)
	-- The ink panel is the background, so the chat window's own goes.
	if FCF_SetWindowAlpha then FCF_SetWindowAlpha(chat, 0) end
end

local function actionBar()
	return MainActionBar or MainMenuBar
end

local function hideBarArt()
	local bar = actionBar()
	if not bar then return end
	for _, key in ipairs({ "EndCaps", "BorderArt", "Background" }) do
		local art = bar[key]
		if art and art.Hide then art:Hide() end
	end
end

-- Runs fn now, or after combat if it can't run yet. Each step is guarded so a
-- renamed Blizzard frame costs one feature, not the console.
local function safely(fn)
	Stoa:AfterCombat(function()
		xpcall(fn, geterrorhandler())
	end)
end

function Console:House()
	local db = self.db

	local function apply()
		if db.houseChat then safely(placeChat) end
		if db.hideBarArt then safely(hideBarArt) end
	end

	if db.houseChat then
		-- Notes now arrive in chat, so the notes page steps aside.
		self.leftPage:Hide()
		Stoa.notesInConsole = false
	end

	apply()
	Stoa:On("PLAYER_ENTERING_WORLD", apply)
	Stoa:On("UI_SCALE_CHANGED", apply)
	Stoa:On("EDIT_MODE_LAYOUTS_UPDATED", apply)
	if EventRegistry then
		EventRegistry:RegisterCallback("EditMode.Exit", apply, self)
	end

	local bar = actionBar()
	if bar and bar.UpdateEndCaps then
		hooksecurefunc(bar, "UpdateEndCaps", function()
			if db.hideBarArt then safely(hideBarArt) end
		end)
	end
end
