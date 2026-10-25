-- Stoa: the public face for other addons.
-- Small addons can add to Stoa without reaching into its insides. Everything
-- here is meant to keep working across Stoa versions; StoaAPI.version goes
-- up when something is added.
--
--   StoaAPI:RegisterTally(key, { label = "Name", value = function() return "12", warn end }, "Group")
--       A line other players can pick for the tally beside the chat.
--   StoaAPI:On(message, fn)
--       Stoa's own messages: STOA_STATE_CHANGED (state), STOA_ROLE_CHANGED
--       (role, previous), STOA_THEME_CHANGED, STOA_GROUP_CHANGED (kind).
--   StoaAPI:GetState()  "WORLD" or "COMBAT"
--   StoaAPI:GetRole()   "TANK", "HEALER", "MELEE" or "RANGED"
--   StoaAPI:Color(token) r, g, b for a theme colour: text, muted, accent,
--       health, mana, danger, panel...
--   StoaAPI:Font(fontString, kind, size)  kind "serif" or "sans"
--   StoaAPI:Note(text)  a line in chat in Stoa's voice
local _, ns = ...
local Stoa = ns.Stoa

local API = { version = 1 }
_G.StoaAPI = API

function API:RegisterTally(key, entry, group)
	local tally = Stoa.modules.Tally
	if tally and tally.Register then tally:Register(key, entry, group) end
end

function API:On(message, fn)
	if type(message) == "string" and message:find("^STOA_") and type(fn) == "function" then
		Stoa:On(message, fn)
	end
end

function API:GetState() return Stoa:GetState() end
function API:GetRole() return Stoa:GetRole() end
function API:Color(token) return Stoa:Color(token) end

function API:Font(fontString, kind, size)
	if fontString and fontString.SetFont then Stoa:SetFont(fontString, kind or "sans", size or Stoa.typeSize.body) end
end

function API:Note(text)
	Stoa:Print(tostring(text))
end
