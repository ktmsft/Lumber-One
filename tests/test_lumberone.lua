-- Lumber One - Copyright (c) 2026 KTM (abitofmoss). All Rights Reserved.
-- No redistribution or reuse of this code or assets without permission. See LICENSE.
--
-- Focused checks for the scanning, zone, goal-box and character-key code. Not a
-- full mock of the game: just enough stubs to load Data.lua, Core.lua and UI.lua
-- and drive them through events.
--
--   luajit tests/test_lumberone.lua            (from the addon folder)
--   luajit tests/test_lumberone.lua <srcdir>   (run against another copy)
--
-- Development only. tools/build.ps1 ships an explicit file list, so tests/ never
-- goes out.

-- The garbage check below counts bytes, and the JIT can sink or move allocations.
if jit then jit.off(); jit.flush() end

local say = print -- the world replaces print, so keep the real one
local SRC = arg[1] or (arg[0]:match("^(.*)[/\\]tests[/\\][^/\\]+$") or ".")
local ADDON = "LumberOne"

--------------------------------------------------------------------------------
-- Tiny test runner
--------------------------------------------------------------------------------

local failures, passes = 0, 0

local function check(cond, msg)
	if not cond then error(msg or "check failed", 2) end
end

local function eq(a, b, msg)
	if a ~= b then
		error(("%s: expected %s, got %s"):format(msg or "eq", tostring(b), tostring(a)), 2)
	end
end

local function test(name, fn)
	local ok, err = pcall(fn)
	if ok then
		passes = passes + 1
		say("PASS  " .. name)
	else
		failures = failures + 1
		say("FAIL  " .. name .. "\n      " .. tostring(err))
	end
end

--------------------------------------------------------------------------------
-- Secrets: any use other than passing one to issecretvalue throws
--------------------------------------------------------------------------------

local SecretMT = {}
for _, mm in ipairs({ "__index", "__newindex", "__concat", "__add", "__sub", "__lt",
	"__le", "__eq", "__len", "__call", "__tostring" }) do
	SecretMT[mm] = function() error("attempt to use a secret value") end
end
local function NewSecret() return setmetatable({}, SecretMT) end

--------------------------------------------------------------------------------
-- Widgets
--------------------------------------------------------------------------------

local function noop() end
local W -- the current world

local Methods = {}
-- Unknown methods are no-ops. Only capitalised names, though: a lowercase key is
-- a field the addon hung on the widget, and must read as nil until it's set.
local ObjMT = { __index = function(_, k)
	if Methods[k] then return Methods[k] end
	if type(k) == "string" and k:find("^%u") then return noop end
end }

local function NewObj(kind, parent)
	local o = setmetatable({ kind = kind, scripts = {}, shown = true, text = "", children = {} }, ObjMT)
	if parent then parent.children[#parent.children + 1] = o end
	return o
end

local function Run(obj, script, ...)
	local fn = obj.scripts[script]
	if fn then return fn(obj, ...) end
end

function Methods.SetScript(self, name, fn) self.scripts[name] = fn end
function Methods.GetScript(self, name) return self.scripts[name] end
function Methods.HookScript(self, name, fn)
	local prev = self.scripts[name]
	if prev then
		self.scripts[name] = function(...) prev(...); fn(...) end
	else
		self.scripts[name] = fn
	end
end
function Methods.RegisterEvent(self, event)
	self.events = self.events or {}
	self.events[event] = true
	W.eventFrames[#W.eventFrames + 1] = self
end
function Methods.Show(self) self.shown = true end
function Methods.Hide(self)
	if self.shown then self.shown = false; Run(self, "OnHide") end
end
function Methods.SetShown(self, v) if v then self:Show() else self:Hide() end end
function Methods.IsShown(self) return self.shown end
function Methods.CreateTexture(self) return NewObj("Texture", self) end
function Methods.CreateFontString(self) return NewObj("FontString", self) end
function Methods.CreateAnimationGroup(self) return NewObj("AnimationGroup", self) end
function Methods.CreateAnimation(self) return NewObj("Animation", self) end
function Methods.GetFont() return "Fonts\\FRIZQT__.TTF", 12, "" end
function Methods.SetText(self, t) self.text = t end
function Methods.GetText(self) return self.text end
function Methods.SetHeight(self, h) self.height = h end
function Methods.GetHeight(self) return self.height or 100 end
function Methods.GetStringWidth() return 40 end
function Methods.GetPoint() return "CENTER", nil, "CENTER", 0, 0 end
function Methods.IsPlaying(self) return self.playing end
function Methods.Play(self) self.playing = true end
function Methods.Stop(self) self.playing = false end
function Methods.HasFocus(self) return self.focus end
function Methods.SetFocus(self)
	self.focus = true
	Run(self, "OnEditFocusGained")
end
function Methods.ClearFocus(self)
	if not self.focus then return end
	self.focus = false
	if W.asyncFocusLost then
		W.pendingFocusLost[#W.pendingFocusLost + 1] = self
	else
		Run(self, "OnEditFocusLost")
	end
end

--------------------------------------------------------------------------------
-- The world: containers, maps, timers, and the globals the addon reads
--------------------------------------------------------------------------------

local BAGS    = { 0, 1, 2, 3, 4, 5 }
local BANK    = { 6, 7 }
local WARBAND = { 12, 13 }
local SLOTS   = { bags = 16, bank = 28, warband = 28 }
local JUNK_ID = 1234

local MAP_NAMES = {
	[946] = "Cosmic", [947] = "Azeroth", [101] = "Outland", [572] = "Draenor",
	[1550] = "The Shadowlands", [12] = "Kalimdor", [13] = "Eastern Kingdoms",
	[113] = "Northrend", [424] = "Pandaria", [619] = "Broken Isles",
	[63] = "Ashenvale", [198] = "Mount Hyjal", [57] = "Teldrassil", [249] = "Uldum",
	[10] = "Duskwood", [37] = "Elwynn Forest", [241] = "Twilight Highlands",
	[102] = "Zangarmarsh", [104] = "Shadowmoon Valley", [539] = "Shadowmoon Valley",
	[1565] = "Ardenweald", [630] = "Azsuna", [116] = "Grizzly Hills",
	[9000] = "Detached Root", [9001] = "Some Dungeon",
}
local MAP_CHILDREN = {
	[946] = { 947, 101, 572, 1550 },
	[947] = { 12, 13, 113, 424, 619 },
	[12] = { 63, 198, 57, 249 },
	[13] = { 10, 37, 241 },
	[113] = { 116 },
	[619] = { 630 },
	[101] = { 102, 104 },
	[572] = { 539 },
	[1550] = { 1565 },
	[9000] = { 9001 },
}
local MAP_PARENT = {}
for parent, kids in pairs(MAP_CHILDREN) do
	for _, kid in ipairs(kids) do MAP_PARENT[kid] = parent end
end

local function Descendants(root, out)
	out = out or {}
	for _, kid in ipairs(MAP_CHILDREN[root] or {}) do
		out[#out + 1] = kid
		Descendants(kid, out)
	end
	return out
end

local function NewWorld(opts)
	opts = opts or {}
	local w = {
		eventFrames = {},
		timers = {},
		now = 1000000,
		bankOpen = false,
		containers = {},
		reads = 0,
		mapCalls = {},
		pendingFocusLost = {},
		playerMap = opts.playerMap == nil and 37 or opts.playerMap,
		failRoots = opts.failRoots or {},
		name = opts.name or "Main",
		realm = opts.realm or "Realm",
	}
	W = w

	local groupOf = {}
	for _, b in ipairs(BAGS) do groupOf[b] = "bags" end
	for _, b in ipairs(BANK) do groupOf[b] = "bank" end
	for _, b in ipairs(WARBAND) do groupOf[b] = "warband" end
	w.groupOf = groupOf
	for bag, group in pairs(groupOf) do
		w.containers[bag] = { slots = SLOTS[group], items = {} }
	end

	-- Addon globals from a previous world must not leak into this one.
	LumberOneDB, LumberOneDevDB, LumberOneFrame, DataStore = nil, nil, nil, nil

	CreateFrame = function(kind, name, parent, template)
		local o = NewObj(kind, parent)
		if template == "InputBoxTemplate" then
			-- The stock template highlights on focus and clears it on focus loss.
			o.scripts.OnEditFocusGained = function(self) self.highlighted = true end
			o.scripts.OnEditFocusLost = function(self) self.highlighted = false end
		end
		if name then _G[name] = o end
		return o
	end
	UIParent = NewObj("Frame")
	GameTooltip = NewObj("GameTooltip")
	SlashCmdList = {}
	RAID_CLASS_COLORS = {}
	print = function() end

	issecretvalue = function(v) return getmetatable(v) == SecretMT end
	strsplit = function(sep, s)
		local out = {}
		for part in (s .. sep):gmatch("(.-)%" .. sep) do out[#out + 1] = part end
		return unpack(out)
	end
	time = function() return w.now end

	C_Timer = { After = function(_, fn) w.timers[#w.timers + 1] = fn end }
	C_AddOns = { GetAddOnMetadata = function() return "Lumber One" end }

	UnitFullName = opts.UnitFullName or function() return w.name, w.realm end
	UnitName = opts.UnitName or function() return w.name end
	GetRealmName = function() return w.realm end
	UnitClass = function() return "Warrior", "WARRIOR" end

	Enum = { BagIndex = {
		Backpack = 0, Bag_1 = 1, Bag_2 = 2, Bag_3 = 3, Bag_4 = 4, ReagentBag = 5,
		CharacterBankTab_1 = 6, CharacterBankTab_2 = 7,
		AccountBankTab_1 = 12, AccountBankTab_2 = 13,
	} }

	C_Container = {
		GetContainerNumSlots = function(bag)
			local c = w.containers[bag]
			if not c then return 0 end
			if groupOf[bag] ~= "bags" and not w.bankOpen then return 0 end
			return c.slots
		end,
		GetContainerItemInfo = function(bag, slot)
			w.reads = w.reads + 1
			local item = w.containers[bag] and w.containers[bag].items[slot]
			if not item then return nil end
			return { itemID = item.id, stackCount = item.count, hyperlink = "|Hitem:" .. item.id .. "|h" }
		end,
	}

	C_Item = {
		-- Like the real one: reports bank and account bank away from a bank.
		GetItemCount = function(itemID)
			local n = 0
			for _, c in pairs(w.containers) do
				for _, item in pairs(c.items) do
					if item.id == itemID then n = n + item.count end
				end
			end
			return n
		end,
		GetItemInfo = function() return "Linen Cloth" end,
		GetItemIconByID = function() return 134400 end,
	}

	C_Map = {
		GetBestMapForUnit = function() return w.playerMap end,
		GetMapInfo = function(id)
			if not MAP_NAMES[id] then return nil end
			return { mapID = id, name = MAP_NAMES[id], parentMapID = MAP_PARENT[id] or 0 }
		end,
		GetMapChildrenInfo = function(root)
			w.mapCalls[#w.mapCalls + 1] = root
			if w.failRoots[root] then error("map query failed") end
			local out = {}
			for _, id in ipairs(Descendants(root)) do
				out[#out + 1] = { mapID = id, name = MAP_NAMES[id], parentMapID = MAP_PARENT[id] }
			end
			return out
		end,
	}

	function w.fire(event, ...)
		for _, f in ipairs(w.eventFrames) do
			if f.events[event] then Run(f, "OnEvent", event, ...) end
		end
	end

	function w.runTimers()
		local ran = 0
		while #w.timers > 0 do
			local fn = table.remove(w.timers, 1)
			fn()
			ran = ran + 1
		end
		return ran
	end

	return w
end

local function LoadAddon(w)
	local ns = {}
	for _, file in ipairs({ "Data.lua", "Core.lua", "UI.lua" }) do
		local chunk = assert(loadfile(SRC .. "/" .. file))
		chunk(ADDON, ns)
	end
	w.ns = ns
	return ns
end

local function Boot(opts)
	opts = opts or {}
	local w = NewWorld(opts)
	LoadAddon(w)
	-- Saved variables exist from here on, as in the client: after the files run,
	-- before ADDON_LOADED.
	if opts.before then opts.before(w) end
	w.fire("ADDON_LOADED", ADDON)
	if not opts.noLogin then
		w.fire("PLAYER_LOGIN")
		w.runTimers()
	end
	return w
end

--------------------------------------------------------------------------------
-- Helpers
--------------------------------------------------------------------------------

local seed = 12345
local function rand(n)
	seed = (seed * 1103515245 + 12345) % 2147483648
	return seed % n + 1
end

local function LumberIDs(ns)
	local ids = {}
	for _, e in ipairs(ns.LUMBER) do ids[#ids + 1] = e.id end
	return ids
end

-- What a full read of a group would give: the answer incremental scans must match.
local function Brute(w, ns, bags)
	local out = {}
	for _, bag in ipairs(bags) do
		for _, item in pairs(w.containers[bag].items) do
			local e = ns.byID[item.id]
			if e then out[e.key] = (out[e.key] or 0) + item.count end
		end
	end
	return out
end

local function SameCounts(ns, got, want, label)
	for _, e in ipairs(ns.LUMBER) do
		local g, x = (got and got[e.key]) or 0, want[e.key] or 0
		if g ~= x then
			error(("%s: %s is %d, a full scan says %d"):format(label, e.key, g, x), 2)
		end
	end
end

local function Fill(w, ns, bags)
	local ids = LumberIDs(ns)
	for _, bag in ipairs(bags) do
		local c = w.containers[bag]
		for slot = 1, c.slots do
			local r = rand(4)
			if r == 1 then c.items[slot] = { id = ids[rand(#ids)], count = rand(200) }
			elseif r == 2 then c.items[slot] = { id = JUNK_ID, count = 1 }
			else c.items[slot] = nil end
		end
	end
end

local function Mutate(w, ns, bag)
	local ids = LumberIDs(ns)
	local c = w.containers[bag]
	local slot = rand(c.slots)
	local r = rand(3)
	if r == 1 then c.items[slot] = { id = ids[rand(#ids)], count = rand(200) }
	elseif r == 2 then c.items[slot] = { id = JUNK_ID, count = 1 }
	else c.items[slot] = nil end
end

local function Char(w) return LumberOneDB.chars[w.ns.GetCharKey()] end

local function BagSlotTotal()
	local n = 0
	for _ in ipairs(BAGS) do n = n + SLOTS.bags end
	return n
end

--------------------------------------------------------------------------------
-- 1. ResolveZones queries the world tree once, and still covers detached trees
--------------------------------------------------------------------------------

local function CallList(w) return table.concat(w.mapCalls, ",") end

local function HasAll(list, ids, label)
	local set = {}
	for _, id in ipairs(list or {}) do set[id] = true end
	for _, id in ipairs(ids) do
		check(set[id], ("%s: map %d missing (got %s)"):format(label, id, table.concat(list or {}, ",")))
	end
	eq(#(list or {}), #ids, label .. " map count")
end

test("zones: standing in the world asks for 946's subtree only", function()
	local w = Boot({ playerMap = 37 })
	eq(CallList(w), "946", "map queries")
	HasAll(w.ns.LUMBER_MAPS.ironwood, { 10, 63, 37, 57 }, "ironwood")
	HasAll(w.ns.LUMBER_MAPS.olemba, { 101, 102 }, "olemba")
	HasAll(w.ns.LUMBER_MAPS.shadowmoon, { 572 }, "shadowmoon")
	HasAll(w.ns.LUMBER_MAPS.feltouched, { 619, 630 }, "feltouched")
	HasAll(w.ns.LUMBER_MAPS.arden, { 1550, 1565 }, "arden")
	eq(w.ns.GetIndexedMapCount(), #Descendants(946), "indexed maps")
end)

test("zones: a detached tree is indexed and the world is still added", function()
	local w = Boot({ playerMap = 9001 })
	eq(CallList(w), "9000,946", "map queries")
	HasAll(w.ns.LUMBER_MAPS.ironwood, { 10, 63, 37, 57 }, "ironwood")
	eq(w.ns.GetIndexedMapCount(), #Descendants(946) + 1, "indexed maps")
end)

test("zones: no map for the player still falls back to the fixed roots", function()
	local w = Boot({ playerMap = false })
	eq(CallList(w), "946", "map queries")
	HasAll(w.ns.LUMBER_MAPS.coldwind, { 113, 116 }, "coldwind")
end)

test("zones: 947 is asked for itself when 946 fails", function()
	local w = Boot({ playerMap = 37, failRoots = { [946] = true } })
	eq(CallList(w), "946,947", "map queries")
	HasAll(w.ns.LUMBER_MAPS.ironwood, { 10, 63, 37, 57 }, "ironwood")
end)

--------------------------------------------------------------------------------
-- 2. Bag scans read only what changed, and always agree with a full scan
--------------------------------------------------------------------------------

test("scan: a one-bag change reads only that bag", function()
	local w = Boot()
	local ns = w.ns
	Fill(w, ns, BAGS); Fill(w, ns, BANK); Fill(w, ns, WARBAND)
	w.fire("BAG_UPDATE_DELAYED"); w.runTimers() -- nothing named: full read
	SameCounts(ns, Char(w).bags, Brute(w, ns, BAGS), "after full read")

	Mutate(w, ns, 2)
	w.reads = 0
	w.fire("BAG_UPDATE", 2)
	w.fire("BAG_UPDATE_DELAYED")
	w.runTimers()
	eq(w.reads, SLOTS.bags, "slot reads for one bag")
	SameCounts(ns, Char(w).bags, Brute(w, ns, BAGS), "after one bag")
end)

test("scan: incremental totals match a full scan through bank visits", function()
	local w = Boot()
	local ns = w.ns
	Fill(w, ns, BAGS); Fill(w, ns, BANK); Fill(w, ns, WARBAND)
	w.fire("BAG_UPDATE_DELAYED"); w.runTimers()

	-- Bank shut: only bags change.
	for _ = 1, 150 do
		local n = rand(3)
		local touched = {}
		for _ = 1, n do
			local bag = BAGS[rand(#BAGS)]
			Mutate(w, ns, bag)
			touched[#touched + 1] = bag
		end
		for _, bag in ipairs(touched) do w.fire("BAG_UPDATE", bag) end
		w.fire("BAG_UPDATE_DELAYED")
		w.runTimers()
		SameCounts(ns, Char(w).bags, Brute(w, ns, BAGS), "bags, bank shut")
	end

	-- Open the bank: bank and Warband are read in full.
	w.bankOpen = true
	w.reads = 0
	w.fire("BANKFRAME_OPENED")
	w.runTimers()
	eq(w.reads, BagSlotTotal() + #BANK * SLOTS.bank + #WARBAND * SLOTS.warband, "reads on bank open")
	SameCounts(ns, Char(w).bank, Brute(w, ns, BANK), "bank on open")
	SameCounts(ns, LumberOneDB.warband, Brute(w, ns, WARBAND), "warband on open")

	-- Bank open: anything can change.
	local all = {}
	for _, b in ipairs(BAGS) do all[#all + 1] = b end
	for _, b in ipairs(BANK) do all[#all + 1] = b end
	for _, b in ipairs(WARBAND) do all[#all + 1] = b end
	for _ = 1, 150 do
		local bag = all[rand(#all)]
		Mutate(w, ns, bag)
		w.reads = 0
		w.fire("BAG_UPDATE", bag)
		w.fire("BAG_UPDATE_DELAYED")
		w.runTimers()
		eq(w.reads, w.containers[bag].slots, "reads for one container with the bank open")
		SameCounts(ns, Char(w).bags, Brute(w, ns, BAGS), "bags, bank open")
		SameCounts(ns, Char(w).bank, Brute(w, ns, BANK), "bank, bank open")
		SameCounts(ns, LumberOneDB.warband, Brute(w, ns, WARBAND), "warband, bank open")
	end

	-- Shut it again. A stray bank-tab update now reads nothing.
	w.bankOpen = false
	w.fire("BANKFRAME_CLOSED")
	local bankBefore = Brute(w, ns, BANK)
	w.reads = 0
	w.fire("BAG_UPDATE", BANK[1])
	w.fire("BAG_UPDATE_DELAYED")
	w.runTimers()
	eq(w.reads, 0, "reads for a bank tab with the bank shut")
	SameCounts(ns, Char(w).bank, bankBefore, "bank kept after closing")

	for _ = 1, 50 do
		local bag = BAGS[rand(#BAGS)]
		Mutate(w, ns, bag)
		w.fire("BAG_UPDATE", bag)
		w.fire("BAG_UPDATE_DELAYED")
		w.runTimers()
		SameCounts(ns, Char(w).bags, Brute(w, ns, BAGS), "bags after the bank")
	end
end)

test("scan: a refresh that names no bag reads everything", function()
	local w = Boot()
	local ns = w.ns
	Fill(w, ns, BAGS)

	-- Contents changed with no BAG_UPDATE at all: the safety net catches it.
	w.reads = 0
	w.fire("BAG_UPDATE_DELAYED")
	w.runTimers()
	eq(w.reads, BagSlotTotal(), "reads with nothing named")
	SameCounts(ns, Char(w).bags, Brute(w, ns, BAGS), "after safety net")

	-- A crafting event alongside a named bag still forces a full read.
	Mutate(w, ns, 1); Mutate(w, ns, 4)
	w.reads = 0
	w.fire("BAG_UPDATE", 1)
	w.fire("TRADE_SKILL_ITEM_CRAFTED_RESULT")
	w.runTimers()
	eq(w.reads, BagSlotTotal(), "reads after a crafting event")
	SameCounts(ns, Char(w).bags, Brute(w, ns, BAGS), "after crafting event")
end)

test("scan: a burst of updates is one scan 0.2s later", function()
	local w = Boot()
	local ns = w.ns
	for i = 1, 5 do
		Mutate(w, ns, BAGS[i])
		w.fire("BAG_UPDATE", BAGS[i])
		w.fire("BAG_UPDATE_DELAYED")
	end
	eq(#w.timers, 1, "timers queued")
	w.reads = 0
	eq(w.runTimers(), 1, "scans run")
	eq(w.reads, 5 * SLOTS.bags, "reads for five named bags")
	SameCounts(ns, Char(w).bags, Brute(w, ns, BAGS), "after burst")
end)

--------------------------------------------------------------------------------
-- 3. GetTotal: same answer, no garbage per call
--------------------------------------------------------------------------------

test("total: counts every character once and allocates nothing", function()
	local w
	w = Boot({ before = function(world)
		LumberOneDB = {
			chars = { ["Other-Realm"] = { bags = { ironwood = 5 }, bank = { ironwood = 7, olemba = 2 } } },
			warband = { ironwood = 100 },
		}
		-- One alt only DataStore knows, plus two it knows that we scanned ourselves
		-- and so must not be counted again.
		DataStore = {
			IterateCharacters = function(_, cb)
				cb("Default.Realm.Alt", "alt")
				cb("Default.Realm.Other", "other")
				cb("Default.Realm.Main", "main")
			end,
			GetContainerItemCount = function(_, id, itemID)
				if id == "alt" then
					if itemID == 245586 then return 3, 4, 1 end
					return 0, 0, 0
				end
				return 1000, 1000, 1000
			end,
		}
		-- The Warband figure has to be real, or reconciling would trim it.
		world.containers[12].items[1] = { id = 245586, count = 100 }
		world.containers[0].items[1] = { id = 245586, count = 11 }
	end })
	local ns = w.ns

	eq(ns.GetTotal("ironwood"), 100 + 11 + 5 + 7 + (3 + 1) + 4, "ironwood total")
	eq(ns.GetTotal("olemba"), 2, "olemba total")

	collectgarbage("collect")
	collectgarbage("stop")
	local before = collectgarbage("count")
	for _ = 1, 5000 do ns.GetTotal("ironwood") end
	local grew = collectgarbage("count") - before
	collectgarbage("restart")
	check(grew < 16, ("GetTotal allocated %.1f KB over 5000 calls"):format(grew))
end)

--------------------------------------------------------------------------------
-- 4. Goal box: Escape cancels, Enter and clicking away save
--------------------------------------------------------------------------------

local function GoalBoxes()
	local boxes = {}
	for _, child in ipairs(LumberOneFrame.children) do
		if child.goal then boxes[#boxes + 1] = child.goal end
	end
	return boxes
end

local function GoalTests(async)
	local label = async and " (focus loss arrives later)" or ""
	test("goal: Escape restores and doesn't save" .. label, function()
		local w = Boot()
		local ns = w.ns
		w.asyncFocusLost = async
		local function settle()
			while #w.pendingFocusLost > 0 do
				Run(table.remove(w.pendingFocusLost, 1), "OnEditFocusLost")
			end
		end
		local box = GoalBoxes()[1] -- ironwood
		check(box, "no goal box found")

		ns.SetGoal("ironwood", 50)
		box:SetFocus()
		check(box.highlighted, "template highlight on focus was lost")
		box:SetText("999")
		Run(box, "OnEscapePressed"); settle()
		eq(ns.GetGoal("ironwood"), 50, "goal after Escape")
		eq(box:GetText(), "50", "box text after Escape")

		-- No goal before: Escape leaves none, and an empty box.
		local box2 = GoalBoxes()[2] -- olemba
		box2:SetFocus(); box2:SetText("5")
		Run(box2, "OnEscapePressed"); settle()
		eq(ns.GetGoal("olemba"), 0, "olemba goal after Escape")
		eq(box2:GetText(), "", "olemba box after Escape")

		-- Enter saves.
		box:SetFocus(); box:SetText("120")
		Run(box, "OnEnterPressed"); settle()
		eq(ns.GetGoal("ironwood"), 120, "goal after Enter")

		-- Clicking elsewhere saves, including straight after an Escape.
		box:SetFocus(); box:SetText("7")
		Run(box, "OnEscapePressed"); settle()
		box:SetFocus(); box:SetText("75")
		box:ClearFocus(); settle()
		eq(ns.GetGoal("ironwood"), 75, "goal after clicking away")
	end)
end
GoalTests(false)
GoalTests(true)

--------------------------------------------------------------------------------
-- 5. Character key survives a nil or secret name at ADDON_LOADED
--------------------------------------------------------------------------------

test("char: nil from UnitFullName falls back to UnitName and the realm", function()
	local w = Boot({ UnitFullName = function() return nil, nil end })
	eq(w.ns.GetCharKey(), "Main-Realm", "char key")
	check(LumberOneDB.chars["Main-Realm"].bags, "char has bags")
end)

test("char: a secret name waits, scans don't error, and login picks it up", function()
	local secretNow = true
	local w = Boot({
		noLogin = true,
		UnitFullName = function()
			if secretNow then return NewSecret(), NewSecret() end
			return "Main", "Realm"
		end,
		UnitName = function()
			if secretNow then return NewSecret() end
			return "Main"
		end,
	})
	local ns = w.ns
	eq(ns.GetCharKey(), nil, "char key while secret")

	Fill(w, ns, BAGS)
	w.fire("BAG_UPDATE", 1)
	w.fire("BAG_UPDATE_DELAYED")
	w.runTimers()

	secretNow = false
	w.fire("PLAYER_LOGIN")
	w.runTimers()
	eq(ns.GetCharKey(), "Main-Realm", "char key after login")
	SameCounts(ns, Char(w).bags, Brute(w, ns, BAGS), "bags after late key")

	for _, char in pairs(LumberOneDB.chars) do
		for k, v in pairs(char) do
			check(not issecretvalue(v), "secret stored in saved variables: " .. k)
		end
	end
end)

test("char: still unreadable at login, then resolved by a later refresh", function()
	local secretNow = true
	local w = Boot({
		UnitFullName = function()
			if secretNow then return NewSecret(), "Realm" end
			return "Main", "Realm"
		end,
		UnitName = function()
			if secretNow then return nil end
			return "Main"
		end,
	})
	local ns = w.ns
	eq(ns.GetCharKey(), nil, "char key at login")
	Fill(w, ns, BAGS)
	w.fire("BAG_UPDATE_DELAYED"); w.runTimers()

	secretNow = false
	w.fire("BAG_UPDATE_DELAYED"); w.runTimers()
	eq(ns.GetCharKey(), "Main-Realm", "char key after a refresh")
	SameCounts(ns, Char(w).bags, Brute(w, ns, BAGS), "bags after late key")
end)

--------------------------------------------------------------------------------

print(("\n%d passed, %d failed"):format(passes, failures))
os.exit(failures == 0 and 0 or 1)
