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
local UI = Stoa.UI

local CHAT_WIDTH = 440
local CHAT_BOTTOM = 20
local CHAT_TOP_PAD = 16
local CHAT_TAB_HEIGHT = 22
-- With the leather art the chat starts just under the gold top border and
-- its tabs stand on that border.
local ART_CHAT_GAP = 14

-- Tab art, in texture pixels (drawn at the console art's scale): the tab's
-- sides at X0 and 128 - X0, its top at TOP and the console's top edge at
-- FOOT. Caps are CAP wide; the middle column stretches.
local TAB_ART = { size = 128, x0 = 32, top = 24, foot = 70, cap = 52 }
local TAB_TEXT_PAD = 26

local function artOn()
	return Console.db.art
end

local function tabRise()
	return (TAB_ART.foot - TAB_ART.top) * Console.ART_SCALE
end

local function placeChat()
	local chat = ChatFrame1
	if not chat then return end
	local bottom = CHAT_BOTTOM
	local top = artOn() and ART_CHAT_GAP or CHAT_TOP_PAD + CHAT_TAB_HEIGHT
	chat:ClearAllPoints()
	chat:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", (Console:PageInset()), bottom)
	chat:SetSize(CHAT_WIDTH, Console:OpenHeight() - bottom - top)
	-- The ink panel is the background, so the chat window's own goes.
	if FCF_SetWindowAlpha then FCF_SetWindowAlpha(chat, 0) end
end

-- With the art the tab row stands on the console's top edge.
local function placeDock()
	local dock = GeneralDockManager
	if not (artOn() and dock) then return end
	dock:ClearAllPoints()
	dock:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", (Console:PageInset()), Console:OpenHeight())
	dock:SetSize(CHAT_WIDTH, tabRise())
end

-- Chat tabs. Blizzard's tab art goes. With the leather art each tab is cut
-- from the console's own top edge: the selected tab opens into the console,
-- its gold border running up and round it; the rest sit behind the edge,
-- dimmer, with the border running across their foot. Without the art they
-- are plain words. Either way the selected tab reads in the accent and the
-- rest in muted bone.
local function tabText(tab)
	return tab.Text or (tab.GetFontString and tab:GetFontString())
end

local function isSelected(tab)
	return SELECTED_CHAT_FRAME and tab:GetID() == SELECTED_CHAT_FRAME:GetID()
end

-- Left cap, stretched middle and right cap of one texture file.
local function capped(holder, sublevel, gold)
	local s = Console.ART_SCALE
	local size, cap = TAB_ART.size, TAB_ART.cap
	local parts = {}
	for i = 1, 3 do
		local tex = holder:CreateTexture(nil, "BACKGROUND", nil, sublevel)
		tex:SetHeight(size * s)
		if gold then
			UI.tint(tex, "accent")
			tex:SetVertexColor(Stoa:Color("accent"))
		end
		parts[i] = tex
	end
	local left, middle, right = parts[1], parts[2], parts[3]
	left:SetWidth(cap * s)
	right:SetWidth(cap * s)
	left:SetTexCoord(0, cap / size, 0, 1)
	middle:SetTexCoord((size / 2) / size, (size / 2 + 1) / size, 0, 1)
	right:SetTexCoord(1 - cap / size, 1, 0, 1)
	middle:SetPoint("TOPLEFT", left, "TOPRIGHT")
	middle:SetPoint("BOTTOMRIGHT", right, "BOTTOMLEFT")
	return { parts = parts }
end

local function placeTabArt(tab)
	local art = tab.stoaArt
	if not art then return end
	local s = Console.ART_SCALE
	-- Where the tab's foot should be against where it is, in case the dock
	-- holds its tabs off its bottom edge.
	local drift = 0
	local bottom = tab:GetBottom()
	if bottom and Console.frame and Console.frame:GetTop() then
		drift = bottom * tab:GetEffectiveScale() / UIParent:GetEffectiveScale() - Console:OpenHeight()
	end
	for _, layer in ipairs({ art.base, art.lines }) do
		local left, right = layer.parts[1], layer.parts[3]
		left:ClearAllPoints()
		right:ClearAllPoints()
		left:SetPoint("TOPLEFT", tab, "BOTTOMLEFT", -TAB_ART.x0 * s, TAB_ART.foot * s - drift)
		right:SetPoint("TOPRIGHT", tab, "BOTTOMRIGHT", TAB_ART.x0 * s, TAB_ART.foot * s - drift)
	end
end

local function setTabArt(tab, selected)
	local art = tab.stoaArt
	if not art then return end
	local kind = selected and "Open" or "Closed"
	if art.kind ~= kind then
		art.kind = kind
		for _, tex in ipairs(art.base.parts) do
			tex:SetTexture(UI.MEDIA .. "Textures\\ChatTab" .. kind)
		end
		for _, tex in ipairs(art.lines.parts) do
			tex:SetTexture(UI.MEDIA .. "Textures\\ChatTab" .. kind .. "Lines")
		end
	end
	-- Below the tab's own words, with the open tab in front so its border
	-- reads over its neighbours'.
	art.holder:SetFrameStrata(tab:GetFrameStrata())
	art.holder:SetFrameLevel(math.max(tab:GetFrameLevel() - (selected and 1 or 2), 0))
end

-- Blizzard nudges a tab's words up or down as it's selected; pin them
-- centred in the tab's body, below its border.
local function anchorText(tab)
	local text = tabText(tab)
	if not (text and tab.stoaArt) then return end
	text:ClearAllPoints()
	text:SetPoint("CENTER", tab, "CENTER", 0, -3)
end

local function colourTab(tab, selected)
	anchorText(tab)
	if selected == nil then selected = isSelected(tab) end
	local text = tabText(tab)
	if text then
		local hover = not selected and tab.stoaHover
		text:SetTextColor(Stoa:Color((selected and "accent") or (hover and "text") or "muted"))
	end
	setTabArt(tab, selected)
end

local function sizeTab(tab)
	if not tab.stoaArt then return end
	local text = tabText(tab)
	tab:SetHeight(tabRise())
	if text then
		anchorText(tab)
		local width = text:GetStringWidth()
		if type(width) == "number" and width > 0 then
			tab:SetWidth(width + TAB_TEXT_PAD * 2)
		end
	end
	placeTabArt(tab)
end

local function artTab(tab)
	-- The art spills past the tab, and docked tabs live in a scroll frame
	-- that clips, so it hangs off its own frame and follows the tab.
	local holder = CreateFrame("Frame", nil, UIParent)
	holder:SetShown(tab:IsShown())
	tab:HookScript("OnShow", function() holder:Show() end)
	tab:HookScript("OnHide", function() holder:Hide() end)
	local art = {
		holder = holder,
		base = capped(holder, 1),
		lines = capped(holder, 2, true),
	}
	tab.stoaArt = art
	Console.tabArt = Console.tabArt or {}
	for _, layer in ipairs({ art.base, art.lines }) do
		for _, tex in ipairs(layer.parts) do
			table.insert(Console.tabArt, tex)
		end
	end
	tab:HookScript("OnEnter", function() tab.stoaHover = true; colourTab(tab) end)
	tab:HookScript("OnLeave", function() tab.stoaHover = false; colourTab(tab) end)
end

local function styleTabs()
	placeDock()
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
			if artOn() then artTab(tab) end
		end
		if tab then
			sizeTab(tab)
			colourTab(tab)
		end
	end
	if artOn() then
		-- Tabs stay up rather than fading out when the mouse leaves chat.
		CHAT_FRAME_TAB_SELECTED_NOMOUSE_ALPHA = 1
		CHAT_FRAME_TAB_NORMAL_NOMOUSE_ALPHA = 1
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
		-- Renaming or re-docking a tab resizes it; put it back on the edge.
		for _, name in ipairs({ "FCF_SetWindowName", "FCFDock_UpdateTabs" }) do
			if _G[name] then hooksecurefunc(name, function() safely(styleTabs) end) end
		end
		for _, name in ipairs({ "PanelTemplates_SelectTab", "PanelTemplates_DeselectTab", "PanelTemplates_TabResize" }) do
			if _G[name] then
				hooksecurefunc(name, function(tab)
					if tab and tab.stoaArt then anchorText(tab) end
				end)
			end
		end
		Stoa:On("STOA_THEME_CHANGED", function() safely(styleTabs) end)
	end

	local bar = actionBar()
	if bar and bar.UpdateEndCaps then
		hooksecurefunc(bar, "UpdateEndCaps", function()
			if db.hideBarArt then safely(hideBarArt) end
		end)
	end
end
