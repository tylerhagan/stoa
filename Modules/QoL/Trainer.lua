-- Stoa QoL: new spells at your trainer.
-- Counts the spells and ranks your class trainer would teach you now that
-- you don't know yet (Data/TrainerSpells.lua), and shows the count on the
-- console under Journey: "TRAINER  3 new". Reaching a level that brings new
-- ones leaves a note too, and /stoa trainer lists them by name.
--
-- Later ranks count only when you know an earlier one, so a talent you
-- skipped doesn't nag; spells for another race or faction are left out.
local _, ns = ...
local Stoa = ns.Stoa

local Trainer = Stoa:NewModule("Trainer", {
	note = true,
})

local function race()
	local _, token = UnitRace("player")
	return token
end

-- Missing spells, as { id, level } sorted by level, for your class.
function Trainer:Missing()
	local _, class = UnitClass("player")
	local byLevel = Stoa.TRAINER_SPELLS and Stoa.TRAINER_SPELLS[class]
	if not byLevel then return {} end
	local level = Stoa:PlainNumber(UnitLevel("player")) or 1
	local myRace, faction = race(), UnitFactionGroup("player")
	local Spells = Stoa.Spells
	local list, seen = {}, {}
	for at, ids in pairs(byLevel) do
		if at <= level then
			for _, id in ipairs(ids) do
				local races = Stoa.TRAINER_RACE[id]
				local side = Stoa.TRAINER_FACTION[id]
				local fits = (not races or races[myRace]) and (not side or side == faction)
				if fits and not seen[id] and not Spells.knows(id) then
					seen[id] = true
					-- A later rank waits for an earlier one you know.
					if not Stoa.TRAINER_RANKED[id] or Spells.best(id) then
						list[#list + 1] = { id = id, level = at }
					end
				end
			end
		end
	end
	table.sort(list, function(a, b) return a.level < b.level or (a.level == b.level and a.id < b.id) end)
	return list
end

function Trainer:Count()
	if self.cached == nil then self.cached = #self:Missing() end
	return self.cached
end

function Trainer:UpdateConsole()
	local console = Stoa.modules.Grimoire
	if not (console and console.trainerNote) then return end
	local count = self:Count()
	if count > 0 then
		console.trainerNote:SetText(("TRAINER  %d new %s"):format(count, count == 1 and "spell" or "spells"))
	else
		console.trainerNote:SetText("")
	end
end

function Trainer:Refresh()
	self.cached = nil
	self:UpdateConsole()
end

function Trainer:OnEnable()
	Stoa:On("STOA_SPELLS_CHANGED", function() self:Refresh() end)
	Stoa:On("PLAYER_LEVEL_UP", function(level)
		-- The spellbook and level settle a moment after the event.
		C_Timer.After(1, function()
			xpcall(function()
				local before = self.cached or 0
				self:Refresh()
				local count = self:Count()
				if self.db.note and count > before then
					Stoa:Note("trainer", ("Level %s: %d new %s at your trainer."):format(
						tostring(Stoa:PlainNumber(level) or UnitLevel("player")), count, count == 1 and "spell" or "spells"))
				end
			end, Stoa.catch)
		end)
	end)
	Stoa.commands.trainer = function()
		local list = self:Missing()
		if #list == 0 then
			Stoa:Print("Nothing new at your trainer.")
			return
		end
		Stoa:Print(("%d new at your trainer:"):format(#list))
		for _, entry in ipairs(list) do
			local name = Stoa.Spells.name(entry.id) or ("spell " .. entry.id)
			local sub = C_Spell and C_Spell.GetSpellSubtext and select(2, pcall(C_Spell.GetSpellSubtext, entry.id))
			Stoa:Print(("  %d  %s%s"):format(entry.level, name, type(sub) == "string" and sub ~= "" and (" (" .. sub .. ")") or ""))
		end
	end
	self:Refresh()
end
