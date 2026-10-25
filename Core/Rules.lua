-- Stoa: when things show.
-- One small rule decides whether a piece of Stoa is shown, so every
-- element can offer the same choices and they all behave alike:
--   ALWAYS, COMBAT (in a fight), WORLD (out of one), GROUP (in a party or
--   raid), RAID, SOLO, TARGET (while you have a target), HOVER (only under
--   the mouse) and NEVER.
-- Any rule can also step aside while mounted or resting in town.
--
-- Stoa.Rules.watch(frame, getRule) keeps a frame's alpha in step with its
-- rule. Fading is by alpha only, so secure frames are safe to watch.
local _, ns = ...
local Stoa = ns.Stoa
local UI = Stoa.UI

local Rules = {}
Stoa.Rules = Rules

Rules.ORDER = { "ALWAYS", "COMBAT", "WORLD", "GROUP", "RAID", "SOLO", "TARGET", "HOVER", "NEVER" }
Rules.LABELS = {
	ALWAYS = "Always", COMBAT = "In combat", WORLD = "Out of combat", GROUP = "In a group",
	RAID = "In a raid", SOLO = "On your own", TARGET = "With a target", HOVER = "On mouseover", NEVER = "Never",
}

-- Settings dropdown options for a rule, in order.
function Rules.options(only)
	local list = {}
	for _, name in ipairs(only or Rules.ORDER) do list[#list + 1] = { name, Rules.LABELS[name] } end
	return list
end

local function inCombat()
	return Stoa:GetState() == Stoa.STATE_COMBAT
end

-- rule is a name above, or { show = name, mounted = "hide", resting = "hide" }.
function Rules.passes(rule, frame)
	if type(rule) == "table" then
		if rule.mounted == "hide" and IsMounted and IsMounted() then return false end
		if rule.resting == "hide" and IsResting and IsResting() and not inCombat() then return false end
		rule = rule.show
	end
	rule = rule or "ALWAYS"
	if rule == "ALWAYS" then return true end
	if rule == "NEVER" then return false end
	if rule == "COMBAT" then return inCombat() end
	if rule == "WORLD" then return not inCombat() end
	if rule == "GROUP" then return IsInGroup() end
	if rule == "RAID" then return IsInRaid() end
	if rule == "SOLO" then return not IsInGroup() end
	if rule == "TARGET" then return UnitExists("target") end
	if rule == "HOVER" then return frame and frame.IsMouseOver and frame:IsMouseOver() or false end
	return true
end

local watched = {}

local function apply(entry)
	local shown = Rules.passes(entry.rule(), entry.frame)
	if shown == entry.shown then return end
	entry.shown = shown
	local to = shown and (entry.alpha or 1) or 0
	if UI and UI.fade and entry.fade ~= false then
		UI.fade(entry.frame, to, shown and 0.2 or 0.4)
	else
		entry.frame:SetAlpha(to)
	end
	if entry.onChange then entry.onChange(shown) end
end

function Rules.refresh()
	for _, entry in ipairs(watched) do xpcall(apply, Stoa.catch, entry) end
end

-- Keeps frame shown or faded by its rule. getRule returns the current rule
-- (so a settings change takes effect on the next refresh); opts.alpha is the
-- shown alpha, opts.onChange(shown) runs on each change.
function Rules.watch(frame, getRule, opts)
	opts = opts or {}
	local entry = { frame = frame, rule = getRule, alpha = opts.alpha, onChange = opts.onChange, fade = opts.fade }
	watched[#watched + 1] = entry
	if frame.HookScript then
		-- Mouseover rules check as the mouse comes and goes; the frame needs
		-- to take the mouse for that, which only hover rules ask of it.
		frame:HookScript("OnEnter", function() xpcall(apply, Stoa.catch, entry) end)
		frame:HookScript("OnLeave", function() C_Timer.After(0.05, function() xpcall(apply, Stoa.catch, entry) end) end)
	end
	xpcall(apply, Stoa.catch, entry)
	return entry
end

for _, event in ipairs({ "STOA_STATE_CHANGED", "STOA_GROUP_CHANGED", "PLAYER_TARGET_CHANGED", "PLAYER_UPDATE_RESTING", "PLAYER_MOUNT_DISPLAY_CHANGED", "PLAYER_ENTERING_WORLD", "STOA_RULES_CHANGED" }) do
	Stoa:On(event, Rules.refresh)
end
