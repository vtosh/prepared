-- Bosses\SiegeOfOrgrimmar.lua
-- The "name" fields must match the encounter name exactly as it appears
-- in-game (this is what ENCOUNTER_START fires with). If Blizzard's client
-- shows a slightly different string than expected, use "/bp encountername"
-- while the boss's health bar is up to print the exact live name, and fix
-- it here.
--
-- `subZone` is the default GetSubZoneText() string for the boss's room, used
-- by the "When I enter its zone" trigger. Players can override it per
-- character with the "Set to my current sub-zone" button in the UI (that
-- override always wins over the value here). Use `/bp subzone` in the room
-- to read the exact live string. `subZones` (a list) also works if a room
-- reports more than one name.

BossPrepData:RegisterInstance({
	key = "SOO",
	name = "Siege of Orgrimmar",
	order = 1,
	bosses = {
		{ key = "IMMERSEUS",         name = "Immerseus" },
		{ key = "FALLEN_PROTECTORS", name = "The Fallen Protectors",
			subZone = "Scarred Vale", defaultTrigger = { type = "ZONE" } },
		{ key = "NORUSHEN",          name = "Norushen",
			subZone = "Chamber of Purification", defaultTrigger = { type = "ZONE" } },
		{ key = "SHA_OF_PRIDE",      name = "Sha of Pride" },
		{ key = "GALAKRAS",          name = "Galakras",
			subZone = "Dranosh'ar Landing", defaultTrigger = { type = "ZONE" } },
		{ key = "IRON_JUGGERNAUT",   name = "Iron Juggernaut" },
		{ key = "DARK_SHAMAN",       name = "Kor'kron Dark Shaman" },
		{ key = "NAZGRIM",           name = "General Nazgrim" },
		{ key = "MALKOROK",          name = "Malkorok" },
		{ key = "SPOILS",            name = "Spoils of Pandaria",
			subZone = "Artifact Storage", defaultTrigger = { type = "ZONE" } },
		{ key = "THOK",              name = "Thok the Bloodthirsty" },
		{ key = "SIEGECRAFTER",      name = "Siegecrafter Blackfuse" },
		{ key = "KLAXXI_PARAGONS",   name = "Paragons of the Klaxxi",
			subZone = "Chamber of the Paragons", defaultTrigger = { type = "ZONE" } },
		{ key = "GARROSH",           name = "Garrosh Hellscream" },
	},
})
