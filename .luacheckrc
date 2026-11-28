-- Lint settings for STOA (luacheck). The game's own API is thousands of
-- names, so reading an unknown global is not flagged here: Tools/sim/run.py
-- checks every name against Forever's UI source instead. Writing one is
-- flagged, apart from the few STOA means to make.
std = "lua51"
max_line_length = false
exclude_files = { "Tools", "docs", "dist" }
ignore = {
	"113", -- reading an undefined global (the game's API; the sim checks names)
	"212", -- unused argument (callbacks take what the game hands them)
	"213", -- unused loop variable
	"431", "432", -- shadowing an upvalue
	"542", -- empty if branch
}
globals = {
	"Stoa", "StoaDB", "StoaCharDB",
	"SLASH_STOA1", "SlashCmdList",
	"Stoa_OnCompartmentClick", "Stoa_OnCompartmentEnter", "Stoa_OnCompartmentLeave",
	"BINDING_HEADER_STOA", "BINDING_NAME_STOA_CHARACTERS", "BINDING_NAME_STOA_MOUNT",
	"StoaRaidButton_OnLoad", "StoaRaidCard_OnLoad", "StoaRaidCell_OnLoad", "StoaRaidTiny_OnLoad",
}
