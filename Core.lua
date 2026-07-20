local ADDON, ns = ...

--------------------------------------------------------------------------------
-- Lookups
--------------------------------------------------------------------------------

ns.byID = {}
ns.byName = {}

for index, entry in ipairs(ns.LUMBER) do
	entry.index = index
	ns.byName[entry.name:lower()] = entry
	if entry.id then
		ns.byID[entry.id] = entry
	end
end

--------------------------------------------------------------------------------
-- Saved variables
--------------------------------------------------------------------------------

local DB_VERSION = 1

local defaults = {
	version = DB_VERSION,

	-- Everything the addon *counts* is account-wide: each character contributes
	-- its bags and bank as it logs in, and the totals shown are the sum across
	-- the whole roster. Only presentation lives in `ui`.
	warband = {},       -- [key] = count, cached from the last bank visit by anyone
	warbandSeen = nil,  -- timestamp of that visit
	warbandSeenBy = nil,-- which character made it
	chars = {},         -- [charKey] = { bags, bank, bagsSeen, bankSeen, name, realm, class }
	goals = {},         -- [key] = number, account-wide (they measure account totals)
	learned = {},       -- [key] = itemID discovered by name match
	learnedZones = {},  -- [key] = { [mapID] = true }, zones proven by looting there
	ui = {
		point = "CENTER",
		relPoint = "CENTER",
		x = 0,
		y = 0,
		shown = true,
		locked = false,
		scale = 1.0,
		hideZero = false,
		showGoals = true,
		zoneMarker = true,
		opacity = 1.0,
		skin = "wood",
	},
}

local function ApplyDefaults(target, source)
	for k, v in pairs(source) do
		if type(v) == "table" then
			if type(target[k]) ~= "table" then target[k] = {} end
			ApplyDefaults(target[k], v)
		elseif target[k] == nil then
			target[k] = v
		end
	end
end

local charKey

--------------------------------------------------------------------------------
-- Bag groups
--
-- Bag index numbering has shifted across expansions (the 11.2 bank rework
-- renamed the character bank containers), so derive the groups from
-- Enum.BagIndex by name instead of hardcoding IDs.
--------------------------------------------------------------------------------

local bagGroups

local function BuildBagGroups()
	local bags, bank, warband = {}, {}, {}

	for name, id in pairs(Enum.BagIndex) do
		if name == "Backpack" or name == "ReagentBag" or name:find("^Bag_%d") then
			bags[#bags + 1] = id
		elseif name:find("^AccountBankTab") then
			warband[#warband + 1] = id
		elseif name:find("^CharacterBankTab") or name:find("^BankBag_%d")
			or name == "Bank" or name == "Reagentbank" then
			bank[#bank + 1] = id
		end
	end

	table.sort(bags)
	table.sort(bank)
	table.sort(warband)

	return { bags = bags, bank = bank, warband = warband }
end

--------------------------------------------------------------------------------
-- Scanning
--------------------------------------------------------------------------------

-- Bank and Warband containers only report their contents while a bank frame is
-- open. Everywhere else they read as zero slots, so we scan them on visit and
-- serve cached numbers the rest of the time.
local bankOpen = false

local function ResolveEntry(info)
	if not info then return nil end

	local entry = info.itemID and ns.byID[info.itemID]
	if entry then return entry end

	-- Fall back to matching on name, and remember the ID once we see it, so the
	-- addon still works if an ID in Data.lua is wrong or Blizzard adds a lumber
	-- in a later patch.
	--
	-- Only entries with no known ID are eligible. Name matching against an entry
	-- we already have an ID for would be actively wrong: there is an old WotLK
	-- quest item (36733) also called "Coldwind Lumber", and it would otherwise
	-- both count toward the total and overwrite the real ID (251762).
	if info.hyperlink and info.itemID then
		local itemName = C_Item.GetItemInfo(info.hyperlink)
		if itemName then
			entry = ns.byName[itemName:lower()]
			if entry and not entry.id then
				entry.id = info.itemID
				ns.byID[info.itemID] = entry
				LumberOneDB.learned[entry.key] = info.itemID
				return entry
			end
		end
	end

	return nil
end

local function ScanGroup(ids)
	local counts = {}
	for _, bag in ipairs(ids) do
		local slots = C_Container.GetContainerNumSlots(bag) or 0
		for slot = 1, slots do
			local info = C_Container.GetContainerItemInfo(bag, slot)
			local entry = ResolveEntry(info)
			if entry then
				counts[entry.key] = (counts[entry.key] or 0) + (info.stackCount or 1)
			end
		end
	end
	return counts
end

local function ScanBags()
	local char = LumberOneDB.chars[charKey]
	char.bags = ScanGroup(bagGroups.bags)
	char.bagsSeen = time()
end

local function ScanBank()
	if not bankOpen then return end
	local char = LumberOneDB.chars[charKey]
	char.bank = ScanGroup(bagGroups.bank)
	char.bankSeen = time()

	-- The Warband bank is one shared inventory, so the newest scan by any
	-- character replaces it wholesale rather than adding to it.
	LumberOneDB.warband = ScanGroup(bagGroups.warband)
	LumberOneDB.warbandSeen = time()
	LumberOneDB.warbandSeenBy = charKey
end

--------------------------------------------------------------------------------
-- Reconciling against live counts
--
-- Bank and Warband figures are snapshots from the last bank visit, because the
-- container APIs only report those slots while a bank frame is open. That was
-- fine when the only way to spend lumber was to take it out of the bank first.
--
-- Crafting broke that assumption: a work order pulls reagents straight out of the
-- Warband bank, so nothing in bags changes, no event we watch fires, and the
-- snapshot keeps insisting the lumber is still there.
--
-- C_Item.GetItemCount does report bank and account-bank contents away from a
-- bank, so it can be used to notice the shortfall. It only says how much the
-- CURRENT character can reach, which is bags + their own bank + Warband — enough
-- to tell that something was spent, though not from which of the two.
--
-- So this only ever reduces. Inflating totals from a partial view would be much
-- worse than briefly under-reporting, and the next bank visit restores exact
-- figures anyway.
--------------------------------------------------------------------------------

-- Widest form first: bags + bank + reagent bank + account bank. Older or changed
-- signatures fall back, and if none work we simply never reconcile.
local function LiveReachableCount(itemID)
	if not (C_Item and C_Item.GetItemCount) then return nil end

	for _, args in ipairs({
		{ itemID, true, false, true, true },  -- ..., includeReagentBank, includeAccountBank
		{ itemID, true, false, true },
		{ itemID, true },
	}) do
		local ok, count = pcall(C_Item.GetItemCount, unpack(args))
		if ok and type(count) == "number" then return count end
	end

	return nil
end

local function ReconcileLive()
	if not (LumberOneDB and charKey) then return end
	local char = LumberOneDB.chars[charKey]
	if not char then return end

	local changed = false

	for _, entry in ipairs(ns.LUMBER) do
		if entry.id then
			local live = LiveReachableCount(entry.id)
			if live then
				local bags = (char.bags and char.bags[entry.key]) or 0
				local bank = (char.bank and char.bank[entry.key]) or 0
				local warband = LumberOneDB.warband[entry.key] or 0
				local deficit = (bags + bank + warband) - live

				if deficit > 0 then
					-- Bags were just rescanned and are accurate, so the shortfall is
					-- in the cached figures. Take it from this character's own bank
					-- before the shared Warband bank: getting the shared number wrong
					-- affects every character, so it's the more cautious order.
					local fromBank = math.min(bank, deficit)
					if fromBank > 0 then
						char.bank[entry.key] = bank - fromBank
						deficit = deficit - fromBank
						changed = true
					end
					if deficit > 0 and warband > 0 then
						LumberOneDB.warband[entry.key] = math.max(0, warband - deficit)
						changed = true
					end
				end
			end
		end
	end

	return changed
end

--------------------------------------------------------------------------------
-- DataStore (optional)
--
-- If the player happens to have DataStore installed, it already knows about
-- characters this addon has never seen — alts that haven't logged in since it was
-- installed. Borrowing that fills in the one real gap in the design.
--
-- Rules, in order of importance:
--
--   * Absolutely nothing happens if DataStore isn't there. No error, no chat
--     line, no options row, no suggestion to go install it. It's declared as an
--     OptionalDep, never a Dependency, so the addon loads fine either way.
--   * Our own scan always wins. DataStore only supplies characters missing from
--     LumberOneDB.chars, so a logged-in alt is never counted twice.
--   * The Warband bank is never taken from DataStore. It's shared account-wide
--     and we already store it once; adding a per-character figure on top would
--     multiply it by the size of the roster. DataStore keeps warband in a
--     separate account-level module for the same reason, so its per-character
--     counts can't contain it.
--
-- Every call is feature-detected and wrapped, because an addon we don't ship
-- can change shape underneath us at any time. Anything unexpected means we
-- quietly report no data.
--------------------------------------------------------------------------------

local function DataStoreReady()
	return type(DataStore) == "table"
		and type(DataStore.IterateCharacters) == "function"
		and type(DataStore.GetContainerItemCount) == "function"
end

-- [charKey] = { bags = {[lumberKey]=n}, bank = {...}, name, realm } for characters
-- we have no scan of. Rebuilt on login rather than cached in saved variables, so
-- it can never go stale or outlive DataStore being uninstalled.
local borrowed = {}

local function RefreshBorrowed()
	borrowed = {}
	if not DataStoreReady() then return end

	local ok = pcall(function()
		DataStore:IterateCharacters(function(key, id)
			-- Keys look like "Account.Realm.Name"; ours are "Name-Realm".
			local _, realm, name = strsplit(".", key)
			if not (realm and name) then return end

			local ourKey = name .. "-" .. realm
			if LumberOneDB.chars[ourKey] then return end -- we have our own scan

			local bags, bank
			for _, entry in ipairs(ns.LUMBER) do
				if entry.id then
					-- Returns bags, bank and reagent bag separately, counting only
					-- this character's own containers.
					local got, bagCount, bankCount, reagentCount =
						pcall(DataStore.GetContainerItemCount, DataStore, id or key, entry.id)

					if got then
						local inBags = (bagCount or 0) + (reagentCount or 0)
						local inBank = bankCount or 0
						if inBags > 0 then
							bags = bags or {}
							bags[entry.key] = inBags
						end
						if inBank > 0 then
							bank = bank or {}
							bank[entry.key] = inBank
						end
					end
				end
			end

			if bags or bank then
				borrowed[ourKey] = {
					bags = bags or {},
					bank = bank or {},
					name = name,
					realm = realm,
					fromDataStore = true,
				}
			end
		end)
	end)

	if not ok then borrowed = {} end
end

-- Every character contributing to the totals: ours first, then anything DataStore
-- knows that we don't. Callers must not care which is which.
local function EachCharacter(callback)
	for ck, char in pairs(LumberOneDB.chars) do
		callback(ck, char, false)
	end
	for ck, char in pairs(borrowed) do
		if not LumberOneDB.chars[ck] then
			callback(ck, char, true)
		end
	end
end

function ns.HasDataStore()
	return DataStoreReady()
end

function ns.GetBorrowedCount()
	local n = 0
	for _ in pairs(borrowed) do n = n + 1 end
	return n
end

--------------------------------------------------------------------------------
-- Public API
--------------------------------------------------------------------------------

function ns.GetCharKey()
	return charKey
end

-- The account-wide total: every character's bags and bank, plus the shared
-- Warband bank counted exactly once.
-- The Warband figure is added once, outside the character loop, and is always our
-- own — never DataStore's. That's what keeps it from being multiplied by the
-- roster size.
function ns.GetTotal(key)
	local total = LumberOneDB.warband[key] or 0
	EachCharacter(function(_, char)
		total = total + ((char.bags and char.bags[key]) or 0)
		              + ((char.bank and char.bank[key]) or 0)
	end)
	return total
end

-- Per-character detail for the tooltip. Characters holding none of this lumber
-- are omitted; the current character sorts first, then by holdings descending.
function ns.GetBreakdown(key)
	local result = {
		chars = {},
		warband = LumberOneDB.warband[key] or 0,
		total = 0,
	}

	EachCharacter(function(ck, char, fromDataStore)
		local bags = (char.bags and char.bags[key]) or 0
		local bank = (char.bank and char.bank[key]) or 0
		if bags + bank > 0 then
			result.chars[#result.chars + 1] = {
				key = ck,
				name = char.name or ck,
				realm = char.realm,
				class = char.class,
				bags = bags,
				bank = bank,
				total = bags + bank,
				isCurrent = (ck == charKey),
				-- The tooltip says where a figure came from, because the freshness
				-- it reports is ours, and this one isn't.
				fromDataStore = fromDataStore,
			}
		end
		result.total = result.total + bags + bank
	end)

	result.total = result.total + result.warband

	table.sort(result.chars, function(a, b)
		if a.isCurrent ~= b.isCurrent then return a.isCurrent end
		if a.total ~= b.total then return a.total > b.total end
		return a.name < b.name
	end)

	return result
end

-- Roster scan freshness, newest bank visit first, for the header tooltip.
function ns.GetScanInfo()
	local info = {
		warbandSeen = LumberOneDB.warbandSeen,
		warbandSeenBy = LumberOneDB.warbandSeenBy,
		chars = {},
	}

	for ck, char in pairs(LumberOneDB.chars) do
		info.chars[#info.chars + 1] = {
			key = ck,
			name = char.name or ck,
			realm = char.realm,
			class = char.class,
			bagsSeen = char.bagsSeen,
			bankSeen = char.bankSeen,
			isCurrent = (ck == charKey),
		}
	end

	table.sort(info.chars, function(a, b)
		if a.isCurrent ~= b.isCurrent then return a.isCurrent end
		return (a.bankSeen or 0) > (b.bankSeen or 0)
	end)

	return info
end

-- "3 minutes ago" etc, plus a colour that fades as the data goes stale.
function ns.FormatAge(timestamp)
	if not timestamp then
		return "never", 1, 0.4, 0.4
	end

	local delta = time() - timestamp
	local text

	if delta < 60 then
		text = "just now"
	elseif delta < 3600 then
		local n = math.floor(delta / 60)
		text = ("%d minute%s ago"):format(n, n == 1 and "" or "s")
	elseif delta < 86400 then
		local n = math.floor(delta / 3600)
		text = ("%d hour%s ago"):format(n, n == 1 and "" or "s")
	else
		local n = math.floor(delta / 86400)
		text = ("%d day%s ago"):format(n, n == 1 and "" or "s")
	end

	if delta < 3600 then
		return text, 0.4, 1, 0.4
	elseif delta < 86400 then
		return text, 1, 1, 1
	else
		return text, 1, 0.6, 0.2
	end
end

function ns.GetGoal(key)
	return LumberOneDB.goals[key] or 0
end

function ns.SetGoal(key, value)
	value = tonumber(value)
	if not value or value <= 0 then
		LumberOneDB.goals[key] = nil
	else
		LumberOneDB.goals[key] = math.floor(value)
	end
	ns.Refresh()
end

-- True once any character on the account has visited a bank, so the UI can say
-- "never scanned" instead of silently showing 0.
function ns.HasBankData()
	return LumberOneDB.warbandSeen ~= nil
end

function ns.IsBankOpen()
	return bankOpen
end

--------------------------------------------------------------------------------
-- Current-zone lookup, for the "harvestable here" marker
--------------------------------------------------------------------------------

-- The player's map and every parent up to the continent, as a set. A lumber is
-- harvestable here if any ID in its LUMBER_MAPS list is in this set, which lets a
-- single list mix specific zones and whole continents: a continent ID is an
-- ancestor of the current zone and so matches, a zone ID matches only itself.
local currentMaps = {}
local currentZone      -- innermost map, the one a learned zone is recorded against
local currentZoneName

local function RefreshZone()
	for k in pairs(currentMaps) do currentMaps[k] = nil end
	currentZone, currentZoneName = nil, nil
	if not C_Map then return end

	local id = C_Map.GetBestMapForUnit("player")
	currentZone = id
	local guard = 0 -- the map tree is shallow; this only guards a broken cycle
	while id and id > 0 and guard < 30 do
		currentMaps[id] = true
		local info = C_Map.GetMapInfo(id)
		if id == currentZone then currentZoneName = info and info.name end
		id = info and info.parentMapID
		guard = guard + 1
	end
end

function ns.HarvestableHere(key)
	local maps = ns.LUMBER_MAPS and ns.LUMBER_MAPS[key]
	if maps then
		for i = 1, #maps do
			if currentMaps[maps[i]] then return true end
		end
	end

	-- Zones learned by actually looting the stuff here.
	local learned = LumberOneDB and LumberOneDB.learnedZones and LumberOneDB.learnedZones[key]
	if learned then
		for mapID in pairs(learned) do
			if currentMaps[mapID] then return true end
		end
	end

	return false
end

--------------------------------------------------------------------------------
-- Learning zones by looting
--
-- The authored zone lists can't be complete — nobody has walked every zone in
-- the game with every lumber. So when a lumber is LOOTED somewhere the lists
-- don't cover, record that zone.
--
-- Loot specifically, not a bag-count increase: buying from the auction house in
-- Valdrakken, taking mail, or a trade all raise the count without saying
-- anything about where the stuff grows, and would teach the addon nonsense.
-- CHAT_MSG_LOOT fires only for looting, and the item ID is read out of the
-- hyperlink, so no part of this depends on the client's language.
--
-- Cost: one string match per loot message, and a table write only the first time
-- a given lumber is seen in a given zone. Nothing here touches rendering.
--------------------------------------------------------------------------------

-- Item-transfer windows that produce a loot message without anything being
-- gathered from the world: taking a mail attachment is the one that started this,
-- and a vendor, trade, bank or guild bank are the same kind of false positive.
-- You can't harvest a node with any of these open, so learning is suppressed
-- while one is. Tracked as a set so a missed close event only over-suppresses
-- (miss a real learn) rather than falsely learning — the safe direction.
local transferOpen = {}

local TRANSFER_EVENTS = {
	MAIL_SHOW              = { "mail", true },     MAIL_CLOSED            = { "mail", false },
	MERCHANT_SHOW          = { "merchant", true }, MERCHANT_CLOSED        = { "merchant", false },
	AUCTION_HOUSE_SHOW     = { "auction", true },  AUCTION_HOUSE_CLOSED   = { "auction", false },
	GUILDBANKFRAME_OPENED  = { "guild", true },    GUILDBANKFRAME_CLOSED  = { "guild", false },
	TRADE_SHOW             = { "trade", true },    TRADE_CLOSED           = { "trade", false },
}

local function InTransferUI()
	return bankOpen or next(transferOpen) ~= nil
end

local function LearnFromLoot(message)
	if not (currentZone and LumberOneDB) then return end

	-- Not gathered from the world if a mailbox, vendor, bank or trade is open.
	if InTransferUI() then return end

	local itemID = tonumber(message:match("|Hitem:(%d+)"))
	if not itemID then return end

	local entry = ns.byID[itemID]
	if not entry then return end

	-- Already covered by the authored lists? Then there's nothing to learn.
	if ns.HarvestableHere(entry.key) then return end

	LumberOneDB.learnedZones[entry.key] = LumberOneDB.learnedZones[entry.key] or {}
	if LumberOneDB.learnedZones[entry.key][currentZone] then return end

	LumberOneDB.learnedZones[entry.key][currentZone] = true
	print(("|cff8fce00Lumber One|r: learned that %s can be gathered in %s.")
		:format(entry.name, currentZoneName or ("map " .. currentZone)))
	ns.Refresh()
end

function ns.GetLearnedZones()
	local out = {}
	for key, zones in pairs((LumberOneDB and LumberOneDB.learnedZones) or {}) do
		local ids = {}
		for mapID in pairs(zones) do ids[#ids + 1] = mapID end
		if #ids > 0 then
			table.sort(ids)
			out[#out + 1] = { key = key, ids = ids }
		end
	end
	table.sort(out, function(a, b) return a.key < b.key end)
	return out
end

function ns.ForgetLearnedZones()
	if LumberOneDB then LumberOneDB.learnedZones = {} end
	ns.Refresh()
end

-- Zone names come from the client's own map data, so they arrive in whatever
-- language the client runs in. Normalising for case and a leading "The" lets the
-- English names in Data.lua match "The Azure Span" and the like without an exact
-- string. It does not translate — a non-English client just won't match, which
-- is a silent no-marker, not an error.
local function NormalizeZone(name)
	if not name then return nil end
	return name:lower():gsub("^the%s+", "")
end

-- Walks up from the player's map to the topmost parent, which is the tree's root.
local function FindRootMap()
	if not C_Map then return nil end
	local id = C_Map.GetBestMapForUnit("player")
	local guard = 0
	while id do
		local info = C_Map.GetMapInfo(id)
		local parent = info and info.parentMapID
		if not parent or parent == 0 then return id end
		id = parent
		guard = guard + 1
		if guard > 30 then return id end
	end
	return nil
end

-- Turns FARMING_ZONES (names, authored) into LUMBER_MAPS (IDs, matched against).
-- Runs once at login. A lumber that already has IDs — a manual fallback someone
-- pasted in — is left alone.
local resolvedZones = false
local unresolvedNames = {} -- [lumber key] = { names that found no map }
local indexedMaps = 0      -- how many maps the index covers, for zonecheck

function ns.ResolveZones()
	if resolvedZones then return end
	if not (C_Map and ns.FARMING_ZONES) then return end

	-- Index from the top of the map tree so EVERY zone in the game is covered, not
	-- just the continent you happen to be standing on — otherwise the lists would
	-- only resolve for wherever you logged in.
	--
	-- The root is normally found by walking up from the player, but that fails in
	-- places whose map tree is detached (some instances), which would silently
	-- index a fraction of the world. So try the known cosmic/world roots too and
	-- merge whatever they return.
	local roots, seenRoot = {}, {}
	for _, candidate in ipairs({ FindRootMap(), 946, 947 }) do
		if candidate and not seenRoot[candidate] then
			seenRoot[candidate] = true
			roots[#roots + 1] = candidate
		end
	end

	local zones = {}
	for _, root in ipairs(roots) do
		local ok, found = pcall(C_Map.GetMapChildrenInfo, root, nil, true)
		if ok and type(found) == "table" then
			for _, z in ipairs(found) do zones[#zones + 1] = z end
		end
	end
	if #zones == 0 then return end

	-- Every ID for a name, not just one: map names are not unique (Draenor and
	-- Outland both have a Shadowmoon Valley, and zones often have a sibling map
	-- of the same name). Keeping one would silently pick the wrong place, so a
	-- name matches if the player is in ANY map that carries it.
	local byName, seenID = {}, {}
	for _, z in ipairs(zones) do
		-- Merging several roots can hand back the same map twice; keep it once.
		if z.name and z.mapID and not seenID[z.mapID] then
			seenID[z.mapID] = true
			local n = NormalizeZone(z.name)
			local list = byName[n]
			if not list then list = {}; byName[n] = list end
			list[#list + 1] = z.mapID
		end
	end
	indexedMaps = 0
	for _ in pairs(seenID) do indexedMaps = indexedMaps + 1 end

	for key, names in pairs(ns.FARMING_ZONES) do
		if #(ns.LUMBER_MAPS[key] or {}) == 0 then
			local ids, misses = {}, {}
			for _, n in ipairs(names) do
				local found = byName[NormalizeZone(n)]
				if found then
					for _, id in ipairs(found) do ids[#ids + 1] = id end
				else
					misses[#misses + 1] = n
				end
			end
			ns.LUMBER_MAPS[key] = ids
			unresolvedNames[key] = #misses > 0 and misses or nil
		end
	end

	resolvedZones = true
end

-- For /lumber zonecheck. Reports per NAME rather than per lumber: a lumber that
-- lists a region plus fallback zones can half-resolve, and the failed name is
-- the thing worth knowing — it's the one whose spelling is wrong.
function ns.GetIndexedMapCount()
	return indexedMaps
end

function ns.GetZoneResolution()
	local working, broken = 0, {}
	for key, names in pairs(ns.FARMING_ZONES or {}) do
		local found = #(ns.LUMBER_MAPS[key] or {})
		working = working + found
		for _, n in ipairs(unresolvedNames[key] or {}) do
			broken[#broken + 1] = ("%s: \"%s\"%s"):format(
				key, n, found > 0 and " (other names for it did resolve)" or "")
		end
	end
	return working, broken
end

--------------------------------------------------------------------------------
-- Events
--------------------------------------------------------------------------------

local refreshPending = false

local function QueueRefresh()
	if refreshPending then return end
	refreshPending = true
	C_Timer.After(0.2, function()
		refreshPending = false
		ScanBags()
		ScanBank()
		-- After the scans: bags must be current before the cached figures can be
		-- checked against what the character can actually reach.
		ReconcileLive()
		ns.Refresh()
	end)
end

local frame = CreateFrame("Frame")

for _, event in ipairs({
	"ADDON_LOADED",
	"PLAYER_LOGIN",
	"BAG_UPDATE_DELAYED",
	"BANKFRAME_OPENED",
	"BANKFRAME_CLOSED",
	"ZONE_CHANGED_NEW_AREA",
	"CHAT_MSG_LOOT",
}) do
	frame:RegisterEvent(event)
end

-- Legacy bank events that the 12.0 bank rework removed, and which throw on
-- RegisterEvent if the client no longer knows them. BAG_UPDATE_DELAYED already
-- covers bank containers on modern clients, so these are belt-and-braces for
-- older builds only — register them individually so one unknown name can't take
-- the rest of the block down with it.
for _, event in ipairs({
	"PLAYERBANKSLOTS_CHANGED",
	"PLAYERBANKBAGSLOTS_CHANGED",
}) do
	pcall(frame.RegisterEvent, frame, event)
end

-- Spending reagents on a craft or a work order can take them straight from the
-- Warband bank, which changes nothing in bags and so fires no bag event. These
-- give us a moment to re-check the live counts. Registered individually under
-- pcall because an event name the client doesn't know throws and would take the
-- rest of the block down with it — the same trap the legacy bank events set.
for _, event in ipairs({
	"ITEM_COUNT_CHANGED",
	"TRADE_SKILL_ITEM_CRAFTED_RESULT",
	"CRAFTINGORDERS_ORDER_PLACED",
	"CRAFTINGORDERS_CLAIMED_ORDER_UPDATED",
	"CRAFTINGORDERS_UPDATE_ORDER_COUNT",
}) do
	pcall(frame.RegisterEvent, frame, event)
end

-- The item-transfer windows whose loot messages must not teach a zone.
for event in pairs(TRANSFER_EVENTS) do
	pcall(frame.RegisterEvent, frame, event)
end

frame:SetScript("OnEvent", function(_, event, arg1)
	if event == "ADDON_LOADED" then
		if arg1 ~= ADDON then return end

		LumberOneDB = LumberOneDB or {}
		ApplyDefaults(LumberOneDB, defaults)

		local name, realm = UnitFullName("player")
		realm = realm or GetRealmName()
		charKey = name .. "-" .. realm
		LumberOneDB.chars[charKey] = LumberOneDB.chars[charKey] or {}

		local char = LumberOneDB.chars[charKey]
		char.bags = char.bags or {}
		char.bank = char.bank or {}
		char.name = name
		char.realm = realm
		char.class = select(2, UnitClass("player"))

		-- Re-apply any item IDs learned by name matching in earlier sessions.
		for key, id in pairs(LumberOneDB.learned) do
			for _, entry in ipairs(ns.LUMBER) do
				if entry.key == key then
					entry.id = id
					ns.byID[id] = entry
				end
			end
		end

		ns.EnsureMarkerDefault()
		bagGroups = BuildBagGroups()

	elseif event == "PLAYER_LOGIN" then
		ns.BuildUI()
		ns.ResolveZones()
		RefreshZone()
		-- After our own scan, so characters we can see for ourselves always win.
		ScanBags()
		RefreshBorrowed()
		ns.Refresh()
		if LumberOneDB.ui.shown then ns.Show() end

	elseif event == "BANKFRAME_OPENED" then
		bankOpen = true
		QueueRefresh()

	elseif event == "BANKFRAME_CLOSED" then
		bankOpen = false
		ns.Refresh()

	elseif event == "ZONE_CHANGED_NEW_AREA" then
		-- Retry resolution if logging in somewhere left the map tree unreadable;
		-- it no-ops once it has succeeded, so this costs nothing afterwards.
		ns.ResolveZones()
		-- Then just re-evaluate the marker; the zone change didn't touch any bags.
		RefreshZone()
		ns.Refresh()

	elseif event == "CHAT_MSG_LOOT" then
		LearnFromLoot(arg1 or "")

	elseif TRANSFER_EVENTS[event] then
		-- Just note that a transfer window opened or closed, so loot arriving while
		-- it's open isn't mistaken for gathering. No scan — nothing moved yet.
		local family, open = TRANSFER_EVENTS[event][1], TRANSFER_EVENTS[event][2]
		transferOpen[family] = open or nil

	else
		QueueRefresh()
	end
end)

--------------------------------------------------------------------------------
-- Slash commands
--------------------------------------------------------------------------------

SLASH_LUMBERONE1 = "/lumber"
SLASH_LUMBERONE2 = "/lumberone"
SLASH_LUMBERONE3 = "/l1"

local function Print(msg)
	print("|cff8fce00Lumber One|r: " .. msg)
end

SlashCmdList.LUMBERONE = function(msg)
	local cmd, rest = msg:lower():match("^(%S*)%s*(.-)$")

	if cmd == "lock" then
		LumberOneDB.ui.locked = true
		Print("frame locked.")
	elseif cmd == "unlock" then
		LumberOneDB.ui.locked = false
		Print("frame unlocked — drag it anywhere.")
	elseif cmd == "reset" then
		LumberOneDB.ui.point, LumberOneDB.ui.relPoint = "CENTER", "CENTER"
		LumberOneDB.ui.x, LumberOneDB.ui.y, LumberOneDB.ui.scale = 0, 0, 1.0
		ns.RestorePosition()
		Print("position reset.")
	elseif cmd == "hidezero" then
		LumberOneDB.ui.hideZero = not LumberOneDB.ui.hideZero
		ns.Refresh()
		Print("rows with zero lumber are now " .. (LumberOneDB.ui.hideZero and "hidden" or "shown") .. ".")
	elseif cmd == "goals" then
		ns.SetShowGoals(not ns.GetShowGoals())
		Print("goal boxes are now " .. (ns.GetShowGoals() and "shown" or "hidden") .. ".")
	elseif cmd == "opacity" or cmd == "alpha" then
		local min, max = ns.GetOpacityBounds()
		local v = tonumber(rest)
		if v and v >= min and v <= max then
			ns.SetOpacity(v)
			Print(("opacity set to %d%%."):format(math.floor(v * 100 + 0.5)))
		else
			Print(("usage: /lumber opacity %s-%s (currently %d%%)")
				:format(min, max, math.floor(ns.GetOpacity() * 100 + 0.5)))
		end
	elseif cmd == "options" or cmd == "config" then
		ns.OpenOptions()
	elseif cmd == "zone" or cmd == "marker" then
		LumberOneDB.ui.zoneMarker = not LumberOneDB.ui.zoneMarker
		ns.Refresh()
		Print("zone marker is now " .. (LumberOneDB.ui.zoneMarker and "shown" or "hidden") .. ".")
	--@debug@
	-- Diagnostics. Everything between a --@debug@ / --@end-debug@ pair is stripped
	-- by tools/build.ps1, so these exist while developing and never ship.
	elseif cmd == "zonecheck" then
		local _, broken = ns.GetZoneResolution()
		local covered = 0
		Print(("indexed %d maps — every zone in the game, from anywhere.")
			:format(ns.GetIndexedMapCount()))
		for _, entry in ipairs(ns.LUMBER) do
			local ids = ns.LUMBER_MAPS[entry.key] or {}
			if #ids > 0 then covered = covered + 1 end
			-- Names, not just IDs: a number proves it resolved to something, a name
			-- proves it resolved to the RIGHT something, without going there.
			local parts = {}
			for _, id in ipairs(ids) do
				local info = C_Map and C_Map.GetMapInfo(id)
				parts[#parts + 1] = ("%s (%d)"):format(info and info.name or "?", id)
			end
			print(("  %-12s %s"):format(entry.key,
				#parts > 0 and table.concat(parts, ", ") or "|cffff8000none|r"))
		end
		print(("  %d of %d lumbers can show a marker."):format(covered, #ns.LUMBER))
		if #broken > 0 then
			print("  names that matched no map (harmless if the lumber resolved anyway):")
			for _, b in ipairs(broken) do print("    " .. b) end
		end
	elseif cmd == "blip" then
		ns.OpenBlipPicker()
		Print("pick a cell for the marker. Current: " .. ns.GetMarkerArt())
	--@end-debug@
	elseif cmd == "learned" then
		local learned = ns.GetLearnedZones()
		if #learned == 0 then
			Print("no zones learned yet. Loot a lumber somewhere unlisted and it'll record it.")
		else
			Print("zones learned by looting:")
			for _, l in ipairs(learned) do
				print(("  %-12s %s"):format(l.key, table.concat(l.ids, ", ")))
			end
			print("  /lumber forgetzones clears these.")
		end
	elseif cmd == "forgetzones" then
		ns.ForgetLearnedZones()
		Print("forgot every learned zone.")
	--@debug@
	elseif cmd == "whereami" then
		if not C_Map then
			Print("the map API isn't available here.")
			return
		end
		local id = C_Map.GetBestMapForUnit("player")
		if not id then
			Print("no map for your location (in an instance, or still loading?).")
			return
		end
		Print("zone map chain — innermost first:")
		local guard = 0
		while id and id > 0 and guard < 30 do
			local info = C_Map.GetMapInfo(id)
			print(("  %d — %s"):format(id, info and info.name or "?"))
			id = info and info.parentMapID
			guard = guard + 1
		end

		-- The bit that explains an absent marker: nothing gatherable here is the
		-- normal case, and without saying so it reads as the feature being broken.
		local here = {}
		for _, entry in ipairs(ns.LUMBER) do
			if ns.HarvestableHere(entry.key) then here[#here + 1] = entry.name end
		end
		if #here > 0 then
			print("  |cff40ff40gatherable here: " .. table.concat(here, ", ") .. "|r")
		else
			print("  gatherable here: nothing — no marker is expected in this zone.")
		end
	elseif cmd == "testmarker" then
		local on = ns.ToggleMarkerTest()
		Print("marker test " .. (on and ("ON — every lumber should show a pin (" .. ns.GetMarkerArt() .. ").")
			or "off."))
	elseif cmd == "debug" then
		-- Bare /lumber debug just reports; "tint" is the destructive one.
		if rest == "tint" then
			local on = ns.ToggleArtDebug()
			Print("art tint " .. (on and "ON — bg purple, rails green/yellow, top red, bottom blue."
				or "off."))
		end
		Print("geometry:")
		print(ns.DescribeGeometry())
	--@end-debug@
	elseif cmd == "skin" or cmd == "style" then
		local names = {}
		for _, skin in ipairs(ns.GetSkins()) do
			names[#names + 1] = skin.key
			if skin.key == rest then
				ns.ApplySkin(skin.key)
				Print("style set to " .. skin.name .. ".")
				return
			end
		end
		Print("usage: /lumber skin <" .. table.concat(names, " | ") .. ">")
		Print("current: " .. ns.GetSkin() .. ". Or use /lumber options.")
	elseif cmd == "scale" then
		local min, max = ns.GetScaleBounds()
		local v = tonumber(rest)
		if v and v >= min and v <= max then
			ns.SetScale(v)
			Print("scale set to " .. v .. ". (Or just drag the bottom-right corner.)")
		else
			Print(("usage: /lumber scale %s-%s"):format(min, max))
		end
	elseif cmd == "chars" then
		Print("characters contributing to the totals:")
		for _, c in ipairs(ns.GetScanInfo().chars) do
			local bags = ns.FormatAge(c.bagsSeen)
			local bank = ns.FormatAge(c.bankSeen)
			print(("  %s — bags %s, bank %s"):format(c.key, bags, bank))
		end
	elseif cmd == "forget" then
		if rest == "" then
			Print("usage: /lumber forget <Name-Realm> (see /lumber chars)")
		else
			local target
			for ck in pairs(LumberOneDB.chars) do
				if ck:lower() == rest then target = ck end
			end
			if not target then
				Print("no character matching '" .. rest .. "'. Try /lumber chars.")
			elseif target == ns.GetCharKey() then
				Print("can't forget the character you're logged into.")
			else
				LumberOneDB.chars[target] = nil
				ns.Refresh()
				Print("forgot " .. target .. ".")
			end
		end
	elseif cmd == "help" then
		Print("commands:")
		print("  /lumber — toggle the window")
		print("  /lumber options — open the settings panel")
		print("  /lumber skin <blizzard | wood | nature> — change the frame style")
		print("  /lumber lock | unlock — freeze or free the frame")
		print("  /lumber scale <0.5-2.0> — resize (or drag the bottom-right corner)")
		print("  /lumber opacity <0.2-1.0> — fade the whole window")
		print("  /lumber hidezero — toggle hiding lumber you have none of")
		print("  /lumber goals — toggle the goal boxes")
		print("  /lumber zone — toggle the harvestable-here marker")
		--@debug@
		print("  /lumber whereami — current zone, and what's gatherable in it")
		print("  /lumber testmarker — force every marker on, to check it renders")
		print("  /lumber zonecheck — which zone names resolved to map IDs")
		print("  /lumber debug [tint] — frame geometry, and colour the border art")
		--@end-debug@
		print("  /lumber reset — recentre the frame")
		print("  /lumber chars — list characters and when they were last scanned")
		print("  /lumber forget <Name-Realm> — drop a deleted character's data")
	else
		ns.Toggle()
	end
end

-- Addon Compartment (the button on the minimap's addon list).
function LumberOne_OnAddonCompartmentClick()
	ns.Toggle()
end
