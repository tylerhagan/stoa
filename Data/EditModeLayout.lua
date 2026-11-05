-- Stoa's starting Edit Mode layout: the game's own export string (Edit Mode,
-- the layout menu, Copy to clipboard). Empty until one is chosen; the Layout
-- module then leaves Edit Mode alone.
local _, ns = ...
local Stoa = ns.Stoa

Stoa.EDIT_MODE_LAYOUT = ""
-- The extra action bars Stoa's layout uses (2 to 8), switched on with it.
Stoa.EDIT_MODE_BARS = { 2, 3 }
