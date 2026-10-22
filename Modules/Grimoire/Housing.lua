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
	-- With the leather art the chat keeps clear of its gold top border.
	local bottom, topPad = CHAT_BOTTOM, CHAT_TOP_PAD + (Console.db.art and 8 or 0)
	chat:ClearAllPoints()
	chat:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", (Console:PageInset()), bottom)
	chat:SetSize(CHAT_WIDTH, Console:OpenHeight() - bottom - topPad - CHAT_TAB_HEIGHT)
	-- The ink panel is the background, so the chat window's own goes.
	if FCF_SetWindowAlpha then FCF_SetWindowAlpha(chat, 0) end
end

-- Chat tabs as plain words: Blizzard's tab art goes, the selected tab reads
-- in the accent and the rest in muted bone, in Stoa's caption type.
local function tabText(tab)
	return tab.Text or (tab.GetFontString and tab:GetFontString())
end

local function colourTab(tab, selected)
	local text = tabText(tab)
	if not text then return end
	if selected == nil then
		selected = SELECTED_CHAT_FRAME and tab:GetID() == SELECTED_CHAT_FRAME:GetID()
	end
	text:SetTextColor(Stoa:Color(selected and "accent" or "muted"))
end

local function styleTabs()
	for i = 1, tonumber(NUM_CHAT_WINDOWS) or 10 do
		local tab = _G["ChatFrame" .. i .. "Tab"]
		if tab and not tab.stoaStyled then
			tab.stoaStyled = true
			for _, region in ipairs({ tab:GetRegions() }) do
				if region:IsObjectType("Texture") then region:SetAlpha(0) end
			end
			local text = tabText(tab)
			if text then
				Stoa:SetFont(text, "sans", Stoa.typeSize.caption + 1)
				text:SetShadowOffset(0, 0)
			end
		end
		if tab then colourTab(tab) end
	end
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
		if db.houseChat then
			safely(placeChat)
			safely(styleTabs)
		end
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

	if db.houseChat then
		-- Blizzard recolours tabs on every selection and new window.
		if FCFTab_UpdateColors then
			hooksecurefunc("FCFTab_UpdateColors", function(tab, selected)
				if tab.stoaStyled then colourTab(tab, selected) end
			end)
		end
		if FCF_OpenNewWindow then hooksecurefunc("FCF_OpenNewWindow", function() safely(styleTabs) end) end
		Stoa:On("STOA_THEME_CHANGED", function() safely(styleTabs) end)
	end

	local bar = actionBar()
	if bar and bar.UpdateEndCaps then
		hooksecurefunc(bar, "UpdateEndCaps", function()
			if db.hideBarArt then safely(hideBarArt) end
		end)
	end
end
