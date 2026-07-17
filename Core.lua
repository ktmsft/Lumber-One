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
-- Public API
--------------------------------------------------------------------------------

function ns.GetCharKey()
	return charKey
end

-- The account-wide total: every character's bags and bank, plus the shared
-- Warband bank counted exactly once.
function ns.GetTotal(key)
	local total = LumberOneDB.warband[key] or 0
	for _, char in pairs(LumberOneDB.chars) do
		total = total + ((char.bags and char.bags[key]) or 0)
		              + ((char.bank and char.bank[key]) or 0)
	end
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

	for ck, char in pairs(LumberOneDB.chars) do
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
			}
		end
		result.total = result.total + bags + bank
	end

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

		bagGroups = BuildBagGroups()

	elseif event == "PLAYER_LOGIN" then
		ns.BuildUI()
		ScanBags()
		ns.Refresh()
		if LumberOneDB.ui.shown then ns.Show() end

	elseif event == "BANKFRAME_OPENED" then
		bankOpen = true
		QueueRefresh()

	elseif event == "BANKFRAME_CLOSED" then
		bankOpen = false
		ns.Refresh()

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
	elseif cmd == "debug" then
		-- Bare /lumber debug just reports; "tint" is the destructive one.
		if rest == "tint" then
			local on = ns.ToggleArtDebug()
			Print("art tint " .. (on and "ON — bg purple, rails green/yellow, top red, bottom blue."
				or "off."))
		end
		Print("geometry:")
		print(ns.DescribeGeometry())
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
