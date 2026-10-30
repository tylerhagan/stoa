-- Stoa offline load test: a rough stand-in for the game's API, enough to
-- load every file, fire the login events and run each /stoa command.
-- It can't prove anything works in game; it catches typos, nil calls and
-- names this mock (and so maybe the game) doesn't know.
local unknown, errors = {}, {}
SIM_UNKNOWN, SIM_ERRORS = unknown, errors
SIM_PATHS = {}

local function noop() end

-- The names the Forever client really has (Tools/sim/api.txt, made by
-- apilist.py) plus Tools/sim/known_missing.txt. Anything else a Stoa file
-- reaches for is INVENTED.
local ALLOWED, METHODS = {}, {}
do
	local dir = SIM_DIR or "Tools/sim/"
	local section
	for line in io.lines(dir .. "api.txt") do
		local head = line:match("^# section: (.*)")
		if head then section = head
		elseif line ~= "" and line:sub(1, 1) ~= "#" then
			if section == "widget methods" then METHODS[line] = true else ALLOWED[line] = true end
		end
	end
	for line in io.lines(dir .. "known_missing.txt") do
		local name = line:gsub("#.*", ""):match("^%s*(.-)%s*$")
		if name ~= "" then ALLOWED[name] = true end
	end
end
SIM_ALLOWED = function(name) return ALLOWED[name] or false end
SIM_REMOVED, SIM_UNKNOWN_METHODS, SIM_FIELD_MISSES, SIM_ABSENT = {}, {}, {}, {}

-- The game's xpcall passes extra arguments on, as Lua 5.2 does.
local rawxpcall = xpcall
xpcall = function(fn, handler, ...)
	local n, args = select("#", ...), { ... }
	return rawxpcall(function() return fn(unpack(args, 1, n)) end, function(e) return handler(tostring(e) .. "\n" .. debug.traceback()) end)
end
local objects = {}
local Object = {}

local special = {
	GetName = function(self) return self.__name end,
	GetParent = function(self) return self.__parent end,
	GetObjectType = function(self) return self.__type or "Frame" end,
	IsObjectType = function() return true end,
	GetPoint = function() return "CENTER", UIParent, "CENTER", 0, 0 end,
	GetNumPoints = function() return 1 end,
	GetText = function(self) return self.__text end,
	SetText = function(self, t) self.__text = t end,
	SetFormattedText = function(self, f, ...) self.__text = string.format(f, ...) end,
	GetScript = function(self, k) return self.__scripts[k] end,
	SetScript = function(self, k, fn) self.__scripts[k] = fn end,
	HookScript = function(self, k, fn) self.__scripts[k] = self.__scripts[k] or fn end,
	GetAttribute = function(self, k) return self.__attr[k] end,
	SetAttribute = function(self, k, v) self.__attr[k] = v end,
	Show = function(self) self.__shown = true end,
	Hide = function(self) self.__shown = false end,
	SetShown = function(self, v) self.__shown = v and true or false end,
	IsShown = function(self) return self.__shown end,
	IsVisible = function(self) return self.__shown end,
	GetFont = function() return "Fonts\\FRIZQT__.TTF", 12, "" end,
	GetChildren = function() end,
	GetRegions = function() end,
	GetID = function(self) return self.__id or 1 end,
	SetID = function(self, v) self.__id = v end,
	GetMinMaxValues = function() return 0, 1 end,
	SetTexture = function(self, path) if type(path) == "string" then SIM_PATHS[path] = true end end,
	SetFont = function(self, path) if type(path) == "string" then SIM_PATHS[path] = true end return true end,
	SetStatusBarTexture = function(self, path) if type(path) == "string" then SIM_PATHS[path] = true end end,
	SetMask = function(self, path) if type(path) == "string" then SIM_PATHS[path] = true end end,
	GetStatusBarTexture = function(self) return self:CreateTexture() end,
	GetCenter = function() return 500, 300 end,
	GetRect = function() return 0, 0, 100, 100 end,
	GetSize = function() return 100, 100 end,
	GetVertexColor = function() return 1, 1, 1, 1 end,
	GetTextColor = function() return 1, 1, 1, 1 end,
	GetTexCoord = function() return 0, 0, 0, 1, 1, 0, 1, 1 end,
	GetEffectiveScale = function() return 1 end,
	GetScale = function() return 1 end,
	GetAlpha = function() return 1 end,
	GetFrameLevel = function() return 1 end,
	GetFrameStrata = function() return "MEDIUM" end,
	GetStringWidth = function() return 50 end,
	GetUnboundedStringWidth = function() return 50 end,
	GetStringHeight = function() return 12 end,
	GetNumLines = function() return 0 end,
	GetValue = function() return 0 end,
	IsForbidden = function() return false end,
	IsProtected = function() return false end,
	CanChangeProtectedState = function() return true end,
	GetUnit = function() return nil end,
	GetItem = function() return nil end,
	GetSpell = function() return nil end,
	GetOwner = function() return nil end,
	GetDrawLayer = function() return "ARTWORK", 0 end,
	GetTexture = function() return nil end,
	GetAtlas = function() return nil end,
	GetJustifyH = function() return "LEFT" end,
	GetHitRectInsets = function() return 0, 0, 0, 0 end,
	GetInsertMode = function() return nil end,
	GetCursorPosition = function() return 0 end,
	GetNumMessages = function() return 0 end,
	GetMessageInfo = function() return nil end,
	GetFontObject = function() return GameFontNormal end,
	GetBackdrop = function() return nil end,
	GetScrollChild = function() return nil end,
	CreateAnimationGroup = function(self) return NewObject("AnimationGroup", self) end,
	CreateAnimation = function(self) return NewObject("Animation", self) end,
	RegisterEvent = function(self, e) EVENT_FRAMES[self] = true; self.__events[e] = true end,
	RegisterUnitEvent = function(self, e) EVENT_FRAMES[self] = true; self.__events[e] = true end,
	UnregisterEvent = function(self, e) self.__events[e] = nil end,
	UnregisterAllEvents = function(self) self.__events = {} end,
	IsEventRegistered = function(self, e) return self.__events[e] and true or false end,
}

Object.__call = function() return nil end
Object.__index = function(t, k)
	if type(k) == "string" and not METHODS[k] and k:find("^[A-Z]") and (special[k] or k:find("^Enumerate") or k:find("^Create")
		or k:find("^Acquire") or k:find("^Get") or k:find("^Set") or k:find("^Is") or k:find("^Has") or k:find("^Can") or k:find("^Num")) then
		SIM_UNKNOWN_METHODS[k] = (SIM_UNKNOWN_METHODS[k] or 0) + 1
	end
	local f = special[k]
	if f then return f end
	if type(k) ~= "string" then return nil end
	if k:find("^Enumerate") or k:find("Iterator$") then
		f = function() return function() end end
	elseif k:find("^Create") or k:find("^Acquire") then
		f = function(self, name, ...)
			local kind = k:match("^Create(.*)") or "Frame"
			return NewObject(kind, self, type(name) == "string" and name or nil)
		end
	elseif k:find("^Get") and (k:find("Texture$") or k:find("Frame$") or k:find("Region$") or k:find("Container$")
		or k:find("Button$") or k:find("String$") or k:find("Bar$") or k:find("Text$") or k:find("Icon$")
		or k:find("Highlight$") or k:find("Library$") or k:find("Border$") or k:find("Entry$") or k:find("Window$")) then
		f = function(self) return NewObject("Texture", self) end
	elseif k:find("^Get") or k:find("^Num") then
		f = function() return 0 end
	elseif k:find("^Is") or k:find("^Has") or k:find("^Can") or k:find("^Should") then
		f = function() return false end
	elseif k:find("^[A-Z]") then
		-- A method or a child region: the game has both under capital
		-- names, so this answers as either (a callable object).
		local child = NewObject("Frame", t, nil)
		rawset(t, k, child)
		return child
	else
		return nil
	end
	special[k] = f
	return f
end

function NewObject(kind, parent, name)
	local o = setmetatable({ __type = kind, __parent = parent, __name = name, __scripts = {}, __attr = {}, __events = {}, __shown = true }, Object)
	if name and name ~= "" then
		name = name:gsub("%$parent", parent and parent.__name or "")
		o.__name = name
		rawset(_G, name, o)
	end
	objects[#objects + 1] = o
	return o
end
EVENT_FRAMES = setmetatable({}, { __mode = "k" })
SIM_OBJECTS = objects

function CreateFrame(kind, name, parent, template)
	local o = NewObject(kind, parent or UIParent, name)
	if template and template:find("Mixin") then end
	return o
end

-- Values --------------------------------------------------------------------
local now = 1000
function GetTime() return now end
function GetServerTime() return 1800000000 end
function time() return 1800000000 end
function date(f) return os.date(f) end
function debugprofilestop() return now * 1000 end
SIM_ADVANCE = function(s) now = now + s end

local timers = {}
SIM_TIMERS = timers
C_Timer = {
	After = function(s, fn) timers[#timers + 1] = fn end,
	NewTimer = function(s, fn) timers[#timers + 1] = fn; return NewObject("Timer") end,
	NewTicker = function(s, fn) local t = NewObject("Ticker"); t.Cancel = noop; t.__fn = fn; timers[#timers + 1] = fn; return t end,
}

UnitLevel = function() return 24 end
UnitClass = function(u) return "Priest", SIM_CLASS or "PRIEST", 5 end
UnitRace = function() return "Human", "Human", 1 end
UnitFactionGroup = function() return "Alliance", "Alliance" end
UnitName = function(u) return u == "player" and "Taer" or nil, nil end
UnitFullName = UnitName
UnitGUID = function(u) return u == "player" and "Player-1-0001" or nil end
UnitExists = function(u) return u == "player" end
UnitIsUnit = function(a, b) return a == b end
UnitHealth = function() return 700 end
UnitHealthMax = function() return 1000 end
UnitPower = function() return 500 end
UnitPowerMax = function() return 1000 end
UnitPowerType = function() return 0, "MANA" end
UnitXP = function() return 3000 end
UnitXPMax = function() return 10000 end
GetXPExhaustion = function() return 1500 end
GetMaxPlayerLevel = function() return 60 end
UnitAffectingCombat = function() return false end
UnitIsDeadOrGhost = function() return false end
UnitIsConnected = function() return true end
UnitCanAttack = function() return false end
UnitIsFriend = function() return true end
UnitReaction = function() return 5 end
UnitSex = function() return 2 end
UnitClassification = function() return "normal" end
UnitGroupRolesAssigned = function() return "NONE" end
UnitInParty = function() return false end
UnitInRaid = function() return nil end
UnitIsPlayer = function(u) return u == "player" end
UnitIsGroupLeader = function() return false end
UnitThreatSituation = function() return nil end
UnitCastingInfo = function() return nil end
UnitChannelInfo = function() return nil end
UnitStat = function() return 50, 50, 0, 0 end
UnitArmor = function() return 500, 500 end
UnitAttackPower = function() return 100, 0, 0 end
UnitRangedAttackPower = function() return 100, 0, 0 end
UnitAttackSpeed = function() return 2.0 end
UnitDamage = function() return 10, 20 end
UnitOnTaxi = function() return false end
UnitIsAFK = function() return false end
InCombatLockdown = function() return false end
IsInGroup = function() return false end
IsInRaid = function() return false end
IsInInstance = function() return false, "none" end
GetNumGroupMembers = function() return 0 end
GetNumSubgroupMembers = function() return 0 end
IsShiftKeyDown = function() return false end
IsAltKeyDown = function() return false end
IsControlKeyDown = function() return false end
IsModifierKeyDown = function() return false end
IsPlayerSpell = function() return false end
IsSpellKnown = function() return false end
IsUsableSpell = function() return true end
GetSpellInfo = function(id) return "Spell" .. tostring(id), nil, 136243, 0, 0, 40, id end
GetLocale = function() return "enUS" end
GetRealmName = function() return "Realm" end
GetCVar = function() return "0" end
GetCVarBool = function() return false end
SetCVar = noop
GetBuildInfo = function() return "1.60.1", "70009", "Nov 1 2026", 16001 end
GetScreenWidth = function() return 3440 end
GetScreenHeight = function() return 1440 end
GetPhysicalScreenSize = function() return 3440, 1440 end
GetMoney = function() return 123456 end
GetRaidTargetIndex = function() return nil end
GetSpecialization = function() return 3 end
GetActiveTalentGroup = function() return 1 end
GetNumTalentTabs = function() return 3 end
GetTalentTabInfo = function(i) return "Tab" .. i, nil, 10, "Tab" .. i end
GetShapeshiftForm = function() return 0 end
GetZoneText = function() return "Elwynn Forest" end
GetSubZoneText = function() return "" end
GetMinimapZoneText = function() return "Goldshire" end
GetRealZoneText = GetZoneText
GetInventoryItemLink = function() return nil end
GetInventoryItemID = function() return nil end
GetInventorySlotInfo = function() return 1, nil end
GetContainerNumSlots = function() return 0 end
GetNumQuestLogEntries = function() return 0, 0 end
GetQuestLogSpecialItemInfo = function() return nil end
GetFramerate = function() return 60 end
GetNetStats = function() return 0, 0, 30, 30 end
GetGameTime = function() return 12, 0 end
IsResting = function() return false end
IsMounted = function() return false end
IsFlying = function() return false end
IsSwimming = function() return false end
IsStealthed = function() return false end
IsAddOnLoaded = function() return false end
IsLoggedIn = function() return false end
GetAddOnMetadata = function() return "0.9.0" end
GetCurrentRegion = function() return 1 end
PlaySound = noop
PlaySoundFile = noop
hooksecurefunc = function(a, b, c)
	if type(a) == "table" then if a[b] == nil then error("hooksecurefunc: no method " .. tostring(b), 2) end
	elseif rawget(_G, a) == nil then error("hooksecurefunc: no function " .. tostring(a), 2) end
end
RegisterStateDriver = noop
UnregisterStateDriver = noop
RegisterAttributeDriver = noop
SecureHandlerWrapScript = noop
SecureHandlerSetFrameRef = noop
issecretvalue = function() return false end
geterrorhandler = function() return function(e) errors[#errors + 1] = tostring(e) end end
seterrorhandler = noop
securecall = function(f, ...) return f(...) end
SetOverrideBindingClick = noop
ClearOverrideBindings = noop
GetBindingKey = function() return nil end
ReloadUI = noop
print = function(...) local t = {} for i = 1, select("#", ...) do t[#t+1] = tostring((select(i, ...))) end SIM_PRINTS[#SIM_PRINTS+1] = table.concat(t, " ") end
SIM_PRINTS = {}
SlashCmdList = {}
StaticPopupDialogs = {}
UISpecialFrames = {}
CUSTOM_CLASS_COLORS = nil
RAID_CLASS_COLORS = setmetatable({}, { __index = function() return { r = 1, g = 1, b = 1, colorStr = "ffffffff", GenerateHexColor = function() return "ffffffff" end } end })
CLASS_ICON_TCOORDS = setmetatable({}, { __index = function() return { 0, 1, 0, 1 } end })
ITEM_QUALITY_COLORS = setmetatable({}, { __index = function() return { r = 1, g = 1, b = 1, hex = "|cffffffff" } end })
MAX_PARTY_MEMBERS = 4
MAX_RAID_MEMBERS = 40
NUM_BAG_SLOTS = 4
NUM_CHAT_WINDOWS = 10
WOW_PROJECT_ID = 18
WOW_PROJECT_CAMELOT = 18
WOW_PROJECT_MAINLINE = 1
WOW_PROJECT_CLASSIC = 2
STANDARD_TEXT_FONT = "Fonts\\FRIZQT__.TTF"
LE_PARTY_CATEGORY_HOME = 1
Enum = setmetatable({}, { __index = function(t, k) local v = setmetatable({}, { __index = function(_, kk) return 0 end }); rawset(t, k, v); return v end })
wipe = function(t) for k in pairs(t) do t[k] = nil end return t end
table.wipe = wipe
tinsert, tremove = table.insert, table.remove
strtrim = function(s, c) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end
strsplit = function(sep, s, n)
	local out = {}
	for piece in (s .. sep):gmatch("(.-)" .. sep:gsub("%p", "%%%0")) do out[#out + 1] = piece end
	return unpack(out)
end
strjoin = function(sep, ...) return table.concat({ ... }, sep) end
strupper, strlower, strfind, strsub, strlen, format, gsub, strmatch, strrep, strbyte, strchar = string.upper, string.lower, string.find, string.sub, string.len, string.format, string.gsub, string.match, string.rep, string.byte, string.char
string.trim = strtrim
string.split = function(s, sep) return strsplit(sep, s) end
floor, ceil, abs, max, min, sqrt, mod = math.floor, math.ceil, math.abs, math.max, math.min, math.sqrt, math.fmod
tContains = function(t, v) for _, x in pairs(t) do if x == v then return true end end return false end
CopyTable = function(t) local o = {} for k, v in pairs(t) do o[k] = type(v) == "table" and CopyTable(v) or v end return o end
Mixin = function(o, ...) for i = 1, select("#", ...) do for k, v in pairs((select(i, ...))) do o[k] = v end end return o end
CreateFromMixins = function(...) return Mixin({}, ...) end
CreateColor = function(r, g, b, a) return { r = r, g = g, b = b, a = a, GetRGB = function() return r, g, b end, GetRGBA = function() return r, g, b, a end, GenerateHexColor = function() return "ffffffff" end, WrapTextInColorCode = function(_, s) return s end } end
CreateVector2D = function(x, y) return { x = x, y = y } end
GetClassColor = function() return 1, 1, 1, "ffffffff" end
BreakUpLargeNumbers = function(n) return tostring(n) end
AbbreviateNumbers = BreakUpLargeNumbers
AbbreviateLargeNumbers = BreakUpLargeNumbers
SecondsToTime = function(s) return tostring(s) .. "s" end
Clamp = function(v, a, b) return math.min(math.max(v, a), b) end
Lerp = function(a, b, t) return a + (b - a) * t end
EasingUtil = { InOutQuadratic = function(t) return t end, OutQuadratic = function(t) return t end }
AuraUtil = { ForEachAura = noop, FindAuraByName = function() return nil end }
C_AddOns = { GetAddOnMetadata = function() return "0.9.0" end, IsAddOnLoaded = function() return false end, LoadAddOn = function() return false end }
C_Spell = { GetSpellName = function(id) return "Spell" .. tostring(id) end, GetSpellInfo = function(id) return { name = "Spell" .. tostring(id), iconID = 136243, spellID = id } end, GetSpellTexture = function() return 136243 end, GetSpellSubtext = function() return "Rank 1" end, GetSpellCooldown = function() return { startTime = 0, duration = 0, isEnabled = true } end, IsSpellUsable = function() return true end, DoesSpellExist = function() return true end, RequestLoadSpellData = noop }
C_SpellBook = { GetNumSpellBookSkillLines = function() return 1 end, GetSpellBookSkillLineInfo = function() return { itemIndexOffset = 0, numSpellBookItems = 2 } end, GetSpellBookItemInfo = function(i) return { spellID = 585 + i, name = "Smite", subName = "Rank " .. i, itemType = 1 } end, GetSpellBookItemName = function() return "Smite", "Rank 1" end }
C_Item = { GetItemInfo = function() return nil end, GetItemCount = function() return 0 end, GetItemStats = function() return {} end, GetItemInfoInstant = function(id) return tonumber(tostring(id):match("%d+")) end, GetItemQualityColor = function() return 1, 1, 1, "ffffffff" end, GetItemIconByID = function() return 134400 end, RequestLoadItemDataByID = noop, GetItemNameByID = function() return nil end, GetDetailedItemLevelInfo = function() return 10 end, IsEquippableItem = function() return false end, GetItemSpell = function() return nil end, GetItemCooldown = function() return 0, 0, 1 end, GetItemLink = function() return nil end }
C_Container = { GetContainerNumSlots = function() return 0 end, GetContainerItemInfo = function() return nil end, GetContainerItemLink = function() return nil end, GetContainerItemID = function() return nil end, UseContainerItem = noop, GetContainerNumFreeSlots = function() return 0, 0 end, GetContainerItemCooldown = function() return 0, 0, 1 end }
C_UnitAuras = { GetAuraDataByIndex = function() return nil end, GetAuraDataBySpellName = function() return nil end, GetPlayerAuraBySpellID = function() return nil end, GetBuffDataByIndex = function() return nil end, GetDebuffDataByIndex = function() return nil end }
C_Secrets = { ShouldAurasBeSecret = function() return false end }
C_QuestLog = { GetNumQuestLogEntries = function() return 0, 0 end, GetInfo = function() return nil end, IsComplete = function() return false end, GetQuestWatchType = function() return nil end, GetNumQuestWatches = function() return 0 end, GetQuestIDForQuestWatchIndex = function() return nil end, GetTitleForQuestID = function() return nil end, GetQuestObjectives = function() return {} end, GetLogIndexForQuestID = function() return nil end, GetDistanceSqToQuest = function() return nil end }
C_Map = { GetBestMapForUnit = function() return 1429 end, GetPlayerMapPosition = function() return nil end, GetMapInfo = function() return { name = "Elwynn Forest" } end }
C_TaxiMap = { GetAllTaxiNodes = function() return {} end }
C_FriendList = { GetNumFriends = function() return 0 end, GetNumOnlineFriends = function() return 0 end, GetFriendInfoByIndex = function() return nil end, IsFriend = function() return false end, ShowFriends = noop }
C_BattleNet = { GetFriendAccountInfo = function() return nil end, GetFriendNumGameAccounts = function() return 0 end, GetFriendGameAccountInfo = function() return nil end }
BNGetNumFriends = function() return 0, 0 end
C_GuildInfo = { GuildRoster = noop }
GetNumGuildMembers = function() return 0, 0, 0 end
IsInGuild = function() return false end
C_ChatInfo = { RegisterAddonMessagePrefix = function() return true end, SendAddonMessage = noop, SendChatMessage = noop }
C_PartyInfo = { InviteUnit = noop, DoCountdown = noop, LeaveParty = noop, ConvertToRaid = noop }
C_AssistedCombat = { GetNextCastSpell = function() return nil end, IsAvailable = function() return false end }
C_CVar = { GetCVar = function() return "0" end, SetCVar = noop, GetCVarBool = function() return false end, RegisterCVar = noop }
C_DateAndTime = { GetCurrentCalendarTime = function() return { hour = 12, minute = 0 } end }
C_Timer.Ticker = nil
C_NamePlate = { GetNamePlateForUnit = function() return nil end, GetNamePlates = function() return {} end }
C_TooltipInfo = {}
TooltipDataProcessor = { AddTooltipPostCall = noop }
C_Container.SortBags = noop
C_StringUtil = nil
MenuUtil = { CreateContextMenu = noop }
Settings = { RegisterVerticalLayoutCategory = function(n) return NewObject("Category"), NewObject("Layout") end, RegisterCanvasLayoutCategory = function() return NewObject("Category") end, RegisterAddOnCategory = noop, RegisterAddOnSetting = function() return NewObject("Setting") end, RegisterProxySetting = function() return NewObject("Setting") end, CreateCheckbox = function() return NewObject("Init") end, CreateDropdown = function() return NewObject("Init") end, CreateSlider = function() return NewObject("Init") end, CreateSliderOptions = function() return NewObject("Options") end, CreateControlTextContainer = function() local c = NewObject("Container"); c.GetData = function() return {} end return c end, OpenToCategory = noop, VarType = { Boolean = "boolean", Number = "number", String = "string" }, Default = { True = true, False = false } }
CreateSettingsListSectionHeaderInitializer = function() return NewObject("Init") end
CreateSettingsButtonInitializer = function() return NewObject("Init") end
MinimalSliderWithSteppersMixin = { Label = { Right = 1 } }
EventRegistry = NewObject("EventRegistry")
EditModeManagerFrame = nil
GameTooltip = nil
DEFAULT_CHAT_FRAME = nil

-- Blizzard's named frames and other upper-case globals this mock doesn't
-- define become plain objects when the client has them (listed under UNKNOWN
-- GLOBALS). A name the client does not have stays nil, like in the game, so
-- Stoa's own existence checks behave; using it unguarded errors and run.py
-- reports it as INVENTED.
setmetatable(_G, { __index = function(t, k)
	if type(k) ~= "string" then return nil end
	if k:find("^[A-Z][%w_]*$") and not k:find("^C_") and not k:find("^[A-Z_0-9]+$") then
		if not ALLOWED[k] then SIM_ABSENT[k] = (SIM_ABSENT[k] or 0) + 1; return nil end
		unknown[k] = (unknown[k] or 0) + 1
		local o = NewObject("Frame", nil, nil)
		o.__name = k
		rawset(t, k, o)
		return o
	end
	unknown[k] = (unknown[k] or 0) + 1
	return nil
end })
for _, name in ipairs({ "QuestInfo_Display", "UpdateUIPanelPositions", "TakeTaxiNode", "UpdateContainerFrameAnchors",
	"CompactUnitFrame_UpdateHealthColor", "TaxiNodeOnButtonEnter", "ContainerFrame_UpdateAll", "ContainerFrame_Update",
	"FCF_SetWindowAlpha", "FCFDock_GetSelectedWindow", "RegisterUnitWatch", "UnregisterUnitWatch", "GetAverageItemLevel",
	"ToggleDropDownMenu", "PaperDollItemSlotButton_Update", "SetItemButtonQuality", "ChatFrame_AddMessageEventFilter" }) do
	_G[name] = function() return nil end
end
LibStub = setmetatable({}, { __call = function() return nil end })
UIParent = NewObject("Frame", nil, "UIParent")
WorldFrame = NewObject("Frame", nil, "WorldFrame")
GameTooltip = NewObject("GameTooltip", UIParent, "GameTooltip")
DEFAULT_CHAT_FRAME = NewObject("ScrollingMessageFrame", UIParent, "ChatFrame1")
for i = 1, 10 do if i > 1 then NewObject("ScrollingMessageFrame", UIParent, "ChatFrame" .. i) end NewObject("Button", UIParent, "ChatFrame" .. i .. "Tab") end

-- Combat: secure changes are locked and unit values turn secret. A secret
-- errors on maths and comparison, like the game's.
local function refuse() error("attempt to use a secret value", 2) end
SECRET = setmetatable({}, { __add = refuse, __sub = refuse, __mul = refuse, __div = refuse, __lt = refuse, __le = refuse,
	__concat = refuse, __unm = refuse, __mod = refuse, __pow = refuse, __index = refuse, __len = refuse, __tostring = function() return "<secret>" end })
function SIM_ENTER_COMBAT()
	InCombatLockdown = function() return true end
	UnitAffectingCombat = function() return true end
	issecretvalue = function(v) return v == SECRET end
	for _, name in ipairs({ "UnitHealth", "UnitHealthMax", "UnitPower", "UnitPowerMax", "UnitThreatSituation" }) do
		_G[name] = function() return SECRET end
	end
	C_Secrets.ShouldAurasBeSecret = function() return true end
	C_UnitAuras.GetAuraDataByIndex = function(u, i) if i == 1 then return { name = SECRET, auraInstanceID = SECRET, dispelName = SECRET, duration = SECRET, expirationTime = SECRET, applications = SECRET, icon = SECRET } end end
	C_UnitAuras.GetAuraDataBySpellName = function() return { name = SECRET, auraInstanceID = SECRET, duration = SECRET, expirationTime = SECRET } end
end

-- Drop what the mock made up itself: upper-case global functions and C_
-- functions the client does not have go away, so a Stoa guard such as
-- `if C_Foo and C_Foo.Bar` sees what the game would show. Reads of a missing
-- C_ field are noted with their line so run.py can name the call that failed.
local keep = { NewObject = true }
for k, v in pairs(_G) do
	if type(k) == "string" and not keep[k] and not k:find("^SIM_") then
		if type(v) == "function" and k:find("^[A-Z]") and not ALLOWED[k] then
			SIM_REMOVED[k] = true
		elseif type(v) == "table" and k:find("^C_") then
			if not ALLOWED[k] then
				SIM_REMOVED[k] = true
			else
				for fk, fv in pairs(v) do
					if type(fv) == "function" and not ALLOWED[k .. "." .. fk] then SIM_REMOVED[k .. "." .. fk] = true end
				end
			end
		end
	end
end
for name in pairs(SIM_REMOVED) do
	local ns, fn = name:match("^(C_%w+)%.(%w+)$")
	if ns then _G[ns][fn] = nil else rawset(_G, name, nil) end
end
for k, v in pairs(_G) do
	if type(k) == "string" and k:find("^C_") and type(v) == "table" and getmetatable(v) == nil then
		setmetatable(v, { __index = function(_, field)
			local info = debug.getinfo(2, "Sl")
			if info and type(field) == "string" then SIM_FIELD_MISSES[info.short_src .. ":" .. info.currentline .. ":" .. field] = k .. "." .. field end
			return nil
		end })
	end
end
