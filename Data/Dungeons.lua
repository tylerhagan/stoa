-- Stoa data: the five-player dungeons and their bosses, in the order you
-- usually meet them. Forever keeps the Adventure Guide closed to addons, so
-- the dungeon companion reads its bosses from here. The names are the game's
-- own (as the dungeon's name and the boss kill's name come back from the
-- game). A dungeon with wings that share one name lists each wing; the
-- companion shows the wing you are in once it can tell.
local _, ns = ...
local Stoa = ns.Stoa

Stoa.Dungeons = {
	{ name = "Ragefire Chasm", bosses = { "Oggleflint", "Taragaman the Hungerer", "Jergosh the Invoker", "Bazzalan" } },
	{ name = "Wailing Caverns", bosses = { "Lady Anacondra", "Lord Cobrahn", "Kresh", "Lord Pythas", "Skum", "Lord Serpentis", "Verdan the Everliving", "Mutanus the Devourer" } },
	{ name = "The Deadmines", bosses = { "Rhahk'Zor", "Sneed", "Gilnid", "Mr. Smite", "Captain Greenskin", "Edwin VanCleef", "Cookie" } },
	{ name = "Shadowfang Keep", bosses = { "Rethilgore", "Razorclaw the Butcher", "Baron Silverlaine", "Commander Springvale", "Odo the Blindwatcher", "Fenrus the Devourer", "Wolf Master Nandos", "Archmage Arugal" } },
	{ name = "Blackfathom Deeps", bosses = { "Ghamoo-ra", "Lady Sarevess", "Gelihast", "Lorgus Jett", "Baron Aquanis", "Twilight Lord Kelris", "Old Serra'kis", "Aku'mai" } },
	{ name = "The Stockade", aka = { "Stormwind Stockade" }, bosses = { "Targorr the Dread", "Kam Deepfury", "Hamhock", "Bazil Thredd", "Dextren Ward" } },
	{ name = "Gnomeregan", bosses = { "Grubbis", "Viscous Fallout", "Electrocutioner 6000", "Crowd Pummeler 9-60", "Mekgineer Thermaplugg" } },
	{ name = "Razorfen Kraul", bosses = { "Roogug", "Aggem Thorncurse", "Death Speaker Jargba", "Overlord Ramtusk", "Agathelos the Raging", "Charlga Razorflank" } },
	{ name = "Scarlet Monastery", wings = {
		{ name = "Graveyard", bosses = { "Interrogator Vishas", "Bloodmage Thalnos" } },
		{ name = "Library", bosses = { "Houndmaster Loksey", "Arcanist Doan" } },
		{ name = "Armory", bosses = { "Herod" } },
		{ name = "Cathedral", bosses = { "High Inquisitor Fairbanks", "Scarlet Commander Mograine", "High Inquisitor Whitemane" } },
	} },
	{ name = "Razorfen Downs", bosses = { "Tuten'kash", "Mordresh Fire Eye", "Glutton", "Amnennar the Coldbringer" } },
	{ name = "Uldaman", bosses = { "Revelosh", "Baelog", "Ironaya", "Obsidian Sentinel", "Ancient Stone Keeper", "Galgann Firehammer", "Grimlok", "Archaedas" } },
	{ name = "Zul'Farrak", bosses = { "Antu'sul", "Theka the Martyr", "Witch Doctor Zum'rah", "Nekrum Gutchewer", "Shadowpriest Sezz'ziz", "Sergeant Bly", "Hydromancer Velratha", "Gahz'rilla", "Chief Ukorz Sandscalp" } },
	{ name = "Maraudon", bosses = { "Noxxion", "Razorlash", "Lord Vyletongue", "Celebras the Cursed", "Landslide", "Tinkerer Gizlock", "Rotgrip", "Princess Theradras" } },
	{ name = "The Temple of Atal'Hakkar", aka = { "Sunken Temple" }, bosses = { "Atal'alarion", "Dreamscythe", "Weaver", "Avatar of Hakkar", "Jammal'an the Prophet", "Ogom the Wretched", "Morphaz", "Hazzas", "Shade of Eranikus" } },
	{ name = "Blackrock Depths", bosses = { "High Interrogator Gerstahn", "Lord Roccor", "Houndmaster Grebmar", "Bael'Gar", "Lord Incendius", "Fineous Darkvire", "General Angerforge", "Golem Lord Argelmach", "Hurley Blackbreath", "Phalanx", "Ambassador Flamelash", "Magmus", "Emperor Dagran Thaurissan" } },
	{ name = "Blackrock Spire", wings = {
		{ name = "Lower", bosses = { "Highlord Omokk", "Shadow Hunter Vosh'gajin", "War Master Voone", "Mother Smolderweb", "Urok Doomhowl", "Quartermaster Zigris", "Halycon", "Gizrul the Slavener", "Overlord Wyrmthalak" } },
		{ name = "Upper", bosses = { "Pyroguard Emberseer", "Solakar Flamewreath", "Goraluk Anvilcrack", "Warchief Rend Blackhand", "The Beast", "General Drakkisath" } },
	} },
	{ name = "Dire Maul", wings = {
		{ name = "East", bosses = { "Pusillin", "Zevrim Thornhoof", "Hydrospawn", "Lethtendris", "Alzzin the Wildshaper" } },
		{ name = "West", bosses = { "Tendris Warpwood", "Illyanna Ravenoak", "Magister Kalendris", "Immol'thar", "Prince Tortheldrin" } },
		{ name = "North", bosses = { "Guard Mol'dar", "Stomper Kreeg", "Guard Fengus", "Guard Slip'kik", "Captain Kromcrush", "King Gordok" } },
	} },
	{ name = "Scholomance", bosses = { "Kirtonos the Herald", "Jandice Barov", "Rattlegore", "Marduk Blackpool", "Vectus", "Ras Frostwhisper", "Instructor Malicia", "Doctor Theolen Krastinov", "Lorekeeper Polkelt", "The Ravenian", "Lord Alexei Barov", "Lady Illucia Barov", "Darkmaster Gandling" } },
	{ name = "Stratholme", wings = {
		{ name = "Main Gate", bosses = { "Timmy the Cruel", "Malor the Zealous", "Cannon Master Willey", "Archivist Galford", "Balnazzar" } },
		{ name = "Service Entrance", bosses = { "Magistrate Barthilas", "Nerub'enkan", "Baroness Anastari", "Maleki the Pallid", "Ramstein the Gorger", "Baron Rivendare" } },
	} },
}

-- A name to compare: lower case, without a leading "The" or punctuation
-- ("The Deadmines" and "Deadmines" match).
local function key(name)
	return (name:lower():gsub("^the%s+", ""):gsub("[^%w%s]", ""):gsub("%s+", " "))
end

-- The dungeon by the game's name for it, or nil. Forever names some
-- dungeons differently from the old lists (Stormwind Stockade), so a name
-- holding a dungeon's name, or held in it, counts as well.
function Stoa.Dungeons.find(name)
	if type(name) ~= "string" or name == "" then return nil end
	local want = key(name)
	for _, dungeon in ipairs(Stoa.Dungeons) do
		if key(dungeon.name) == want then return dungeon end
		for _, other in ipairs(dungeon.aka or {}) do
			if key(other) == want then return dungeon end
		end
	end
	if #want < 6 then return nil end
	for _, dungeon in ipairs(Stoa.Dungeons) do
		local mine = key(dungeon.name)
		if want:find(mine, 1, true) or mine:find(want, 1, true) then return dungeon end
	end
end

-- The first dungeon whose name holds `part` (any case), or nil.
function Stoa.Dungeons.search(part)
	part = type(part) == "string" and part:lower() or ""
	if part == "" then return nil end
	for _, dungeon in ipairs(Stoa.Dungeons) do
		if dungeon.name:lower():find(part, 1, true) then return dungeon end
		for _, other in ipairs(dungeon.aka or {}) do
			if other:lower():find(part, 1, true) then return dungeon end
		end
	end
end
