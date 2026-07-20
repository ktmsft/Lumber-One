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

--------------------------------------------------------------------------------
-- Gathering zones
--
-- The "harvestable in this zone" marker matches on specific zones, not on
-- expansion. WoW has no reliable way to ask which expansion an arbitrary zone
-- belongs to, and guessing from the continent breaks precisely where it matters:
-- Mount Hyjal (Ashwood, Cataclysm) sits under Kalimdor, the same continent as
-- the classic zones where Ironwood drops. Named zones are unambiguous; that's
-- why the data below is zones rather than expansions.
--
-- These are the best farming zones for each lumber, by NAME. Core.lua resolves
-- the names to UiMap IDs at login by walking the map tree, so no IDs are stored
-- by hand. The `expac` field on each lumber above is tooltip text only — it
-- plays no part in matching.
--
-- A name here can be a single zone OR a whole region/continent — the same
-- resolver handles both, because the marker matches when the named map is
-- anywhere in the player's map chain. A zone matches only itself; a region
-- matches every zone beneath it. That's safe as long as the region isn't shared
-- with another lumber (Draenor and Quel'Thalas each stand alone; Kalimdor and
-- the Eastern Kingdoms are shared, which is why Ironwood and Ashwood name
-- specific zones instead).
--
-- Name resolution is by the client's own map names, normalised for case and a
-- leading "The", so it is English-only: a non-English client simply shows no
-- marker rather than erroring. Baking in IDs would make it locale-independent;
-- that's a future step.
--------------------------------------------------------------------------------

-- Each list is the REGION the lumber drops across, matching the `where` text
-- above, plus the best farming zone as a fallback in case the region name
-- doesn't resolve. Any name that resolves is used, and a match on any of them
-- shows the marker — so listing both is belt and braces, not duplication.
--
-- Region names are how the client labels them (see /lumber whereami), which is
-- not always the expansion's marketing name: Shadowlands is "The Shadowlands",
-- Legion's region is "Broken Isles".
ns.FARMING_ZONES = {
	-- Classic and Cataclysm both live on Kalimdor and the Eastern Kingdoms, so
	-- neither can name its region without lighting up in the other's zones.
	-- These two stay zone-specific; it's the ambiguity described at the top.
	ironwood   = { "Duskwood", "Ashenvale", "Elwynn Forest", "Teldrassil" },
	ashwood    = { "Mount Hyjal", "Deepholm", "Uldum", "Twilight Highlands" },

	-- Everything else gets its own region, so the marker shows anywhere the
	-- lumber actually drops rather than only in the best spot.
	olemba     = { "Outland", "Zangarmarsh" },
	coldwind   = { "Northrend", "Grizzly Hills" },
	bamboo     = { "Pandaria", "Kun-Lai Summit" },
	shadowmoon = { "Draenor" }, -- no zone fallback: its Shadowmoon Valley shares
	                            -- a name with Outland's, which would misfire
	feltouched = { "Broken Isles", "Azsuna" },
	darkpine   = { "Zandalar", "Kul Tiras", "Zuldazar" },
	arden      = { "The Shadowlands", "Ardenweald" },
	dragonpine = { "Dragon Isles", "The Azure Span" },
	dornicfir  = { "Khaz Algar", "Isle of Dorn" },
	thalassian = { "Quel'Thalas", "Eversong Woods", "Harandar" },
}

-- Filled at runtime by resolving FARMING_ZONES to map IDs. Anything left empty
-- (an unresolved name, or a lumber with no zone) never shows a marker. Hardcoded
-- IDs here are honoured and not overwritten, as a manual fallback.
ns.LUMBER_MAPS = {}
