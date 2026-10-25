-- Stoa: the spellbook, read once and shared.
-- Several features need the same answers: which rank of a spell is the
-- best you know (auto-uprank, buff reminders), whether a spell is learned
-- (signatures, reminders) and what it costs (the mana arc). The book is read
-- when spells change and the answers are kept here.
local _, ns = ...
local Stoa = ns.Stoa

local Spells = {}
Stoa.Spells = Spells

-- best[name] = { id = spellID, rank = number }; ids[spellID] = name.
local best, ids = {}, {}

local function call(fn, ...)
	if type(fn) ~= "function" then return nil end
	local ok, a, b, c, d = pcall(fn, ...)
	if ok then return a, b, c, d end
end

-- "Rank 3" in any language ends in its number; spells without ranks are 0.
local function rankOf(subName)
	if type(subName) ~= "string" then return 0 end
	return tonumber(subName:match("(%d+)%s*$")) or 0
end

function Spells.name(spellID)
	if C_Spell and C_Spell.GetSpellName then return call(C_Spell.GetSpellName, spellID) end
	return (call(GetSpellInfo, spellID))
end

function Spells.knows(spellID)
	if not spellID then return false end
	if IsPlayerSpell and call(IsPlayerSpell, spellID) then return true end
	return call(IsSpellKnown, spellID) and true or false
end

local function note(name, spellID, subName)
	if not name or not spellID then return end
	ids[spellID] = name
	local rank = rankOf(subName or (C_Spell and C_Spell.GetSpellSubtext and call(C_Spell.GetSpellSubtext, spellID)))
	local current = best[name]
	if not current or rank > current.rank then
		best[name] = { id = spellID, rank = rank }
	end
end

-- Reads the player's spellbook. Modern clients have C_SpellBook; the older
-- global functions are the fallback.
function Spells.Scan()
	wipe(best)
	wipe(ids)
	local book = C_SpellBook
	local bank = Enum and Enum.SpellBookSpellBank and Enum.SpellBookSpellBank.Player
	if book and book.GetNumSpellBookSkillLines and book.GetSpellBookItemInfo then
		local lines = call(book.GetNumSpellBookSkillLines) or 0
		for line = 1, lines do
			local info = call(book.GetSpellBookSkillLineInfo, line)
			if type(info) == "table" and not info.offSpecID then
				local first = info.itemIndexOffset or 0
				for index = first + 1, first + (info.numSpellBookItems or 0) do
					local item = call(book.GetSpellBookItemInfo, index, bank)
					local isSpell = type(item) == "table" and (not Enum.SpellBookItemType or item.itemType == Enum.SpellBookItemType.Spell)
					if isSpell and not item.isPassive and not item.isOffSpec then
						note(item.name, item.spellID or item.actionID, item.subName)
					end
				end
			end
		end
	elseif GetNumSpellTabs and GetSpellBookItemName then
		for tab = 1, call(GetNumSpellTabs) or 0 do
			local _, _, offset, count = call(GetSpellTabInfo, tab)
			for index = (offset or 0) + 1, (offset or 0) + (count or 0) do
				local name, subName = call(GetSpellBookItemName, index, "spell")
				local _, spellID = call(GetSpellBookItemInfo, index, "spell")
				note(name, spellID, subName)
			end
		end
	end
	Stoa:Fire("STOA_SPELLS_CHANGED")
end

-- The highest rank you know of the spell with this ID or name, or nil when
-- you know none.
function Spells.best(spell)
	local name = type(spell) == "number" and (ids[spell] or Spells.name(spell)) or spell
	local entry = name and best[name]
	return entry and entry.id, entry and entry.rank
end

-- The rank number of a spell ID you know (0 for unranked), or nil.
function Spells.rank(spellID)
	local name = ids[spellID]
	if not name then return nil end
	return rankOf(C_Spell and C_Spell.GetSpellSubtext and call(C_Spell.GetSpellSubtext, spellID))
end

-- True when the spell ID is a lower rank than the best one you know.
function Spells.outranked(spellID)
	local name = ids[spellID] or Spells.name(spellID)
	local entry = name and best[name]
	return entry and entry.id ~= spellID and (Spells.rank(spellID) or 0) < entry.rank or false
end

-- What a spell costs in a power type (mana by default), as a plain number.
function Spells.cost(spellID, powerType)
	powerType = powerType or (Enum and Enum.PowerType and Enum.PowerType.Mana) or 0
	local costs = C_Spell and C_Spell.GetSpellPowerCost and call(C_Spell.GetSpellPowerCost, spellID)
	if type(costs) ~= "table" then return nil end
	for _, cost in ipairs(costs) do
		if cost.type == powerType then return Stoa:PlainNumber(cost.cost) end
	end
end

-- The spellbook changes on learning, a new rank and spec change. A short
-- wait folds a trainer's burst of LEARNED_SPELL events into one read.
local pending
local function later()
	if pending then return end
	pending = true
	C_Timer.After(0.5, function()
		pending = false
		xpcall(Spells.Scan, Stoa.catch)
	end)
end

Stoa:On("PLAYER_LOGIN", function() xpcall(Spells.Scan, Stoa.catch) end)
Stoa:On("SPELLS_CHANGED", later)
Stoa:On("LEARNED_SPELL_IN_TAB", later)
Stoa:On("LEARNED_SPELL_IN_SKILL_LINE", later)
