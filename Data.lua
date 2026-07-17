local ADDON, ns = ...

-- One entry per housing-decor lumber, in expansion order.
--
--   key    stable identifier for saved variables — never change these
--   id     retail item ID
--   expac  expansion label shown in the tooltip
--   where  where you actually go to chop it
--
-- Item IDs are not contiguous: most sit in a 2517xx run, but Olemba, Ironwood,
-- Dornic Fir and Thalassian were added in separate patches and fall well
-- outside it. Don't derive these by offset.

ns.LUMBER = {
	{
		key = "ironwood",
		name = "Ironwood Lumber",
		id = 245586,
		expac = "Classic",
		where = "Kalimdor and the Eastern Kingdoms — any classic Azeroth zone.",
	},
	{
		key = "olemba",
		name = "Olemba Lumber",
		id = 242691,
		expac = "The Burning Crusade",
		where = "Outland, every zone except Hellfire Peninsula. Also drops in Eversong Woods, Ghostlands, Azuremyst, Bloodmyst and the Isle of Quel'Danas.",
	},
	{
		key = "coldwind",
		name = "Coldwind Lumber",
		id = 251762,
		expac = "Wrath of the Lich King",
		where = "Anywhere in Northrend.",
	},
	{
		key = "ashwood",
		name = "Ashwood Lumber",
		id = 251764,
		expac = "Cataclysm",
		where = "The Cataclysm zones of post-Shattering Azeroth.",
	},
	{
		key = "bamboo",
		name = "Bamboo Lumber",
		id = 251763,
		expac = "Mists of Pandaria",
		where = "Pandaria. The east side of Kun-Lai Summit is a dense route.",
	},
	{
		key = "shadowmoon",
		name = "Shadowmoon Lumber",
		id = 251766,
		expac = "Warlords of Draenor",
		where = "Anywhere in Draenor.",
	},
	{
		key = "feltouched",
		name = "Fel-Touched Lumber",
		id = 251767,
		expac = "Legion",
		where = "The Broken Isles. Azsuna is the flattest route to run.",
	},
	{
		key = "darkpine",
		name = "Darkpine Lumber",
		id = 251768,
		expac = "Battle for Azeroth",
		where = "Zandalar and Kul Tiras, plus Nazjatar and Mechagon.",
	},
	{
		key = "arden",
		name = "Arden Lumber",
		id = 251772,
		expac = "Shadowlands",
		where = "The Shadowlands. Ardenweald is far and away the best.",
	},
	{
		key = "dragonpine",
		name = "Dragonpine Lumber",
		id = 251773,
		expac = "Dragonflight",
		where = "The Dragon Isles — Ohn'ahran Plains and the Waking Shores.",
	},
	{
		key = "dornicfir",
		name = "Dornic Fir Lumber",
		id = 248012,
		expac = "The War Within",
		where = "Khaz Algar — Isle of Dorn, Hallowfall and Azj-Kahet.",
	},
	{
		key = "thalassian",
		name = "Thalassian Lumber",
		id = 256963,
		expac = "Midnight",
		where = "Quel'Thalas — Eversong Woods and around Silvermoon — and Harandar.",
	},
}
