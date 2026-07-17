local ADDON, ns = ...

local ROW_HEIGHT = 24
local MIN_SCALE, MAX_SCALE = 0.5, 2.0

-- Opacity floors at 0.2: below that the frame is invisible enough to look broken
-- or lost, and there's no obvious way back other than a slash command.
local MIN_OPACITY, MAX_OPACITY = 0.2, 1.0

-- Header type is sized explicitly rather than left to the stock font objects:
-- the title bar is only as tall as the art's beam, and GameFontNormal's default
-- 12pt overhangs it.
local TITLE_FONT_SIZE  = 11
local HEADER_FONT_SIZE = 9

-- Row columns. The widths are sized to the longest label the addon can actually
-- show ("Fel-Touched", once " Lumber" is stripped) rather than to round numbers,
-- which is what keeps the frame narrow. The row width is the one measurement
-- every skin shares — each solves its own frame width around it — so adjusting a
-- column here re-flows all three styles and can't leave a gap behind.
local ICON_SIZE = 18
local NAME_WIDTH = 88
local COUNT_WIDTH = 42
local GOAL_WIDTH = 32     -- sized for 3 digits; GOAL_MAX_DIGITS keeps input in step
local GOAL_MAX_DIGITS = 4
local COLUMN_GAP = 8

-- Clearance at each end of the row. Split evenly rather than the 2/6 it used to
-- be, so a skin whose rails draw inward (see railBoost) can't reach the icon or
-- the goal box. The total is unchanged, so the row width — and every skin's frame
-- width with it — stays exactly where it was.
local ROW_MARGIN = 4

-- The row's fixed part: icon, name, count. The goal column is optional, so the
-- row width — and with it every skin's frame width — depends on whether it shows.
local ROW_BASE_WIDTH = ROW_MARGIN + ICON_SIZE + 6 + NAME_WIDTH + 4 + COUNT_WIDTH + ROW_MARGIN
local GOAL_COLUMN_WIDTH = COLUMN_GAP + GOAL_WIDTH

-- Defaults to on: this runs before the saved variables exist.
local function ShowingGoals()
	return not LumberOneDB or LumberOneDB.ui.showGoals ~= false
end

local function RowWidth()
	return ROW_BASE_WIDTH + (ShowingGoals() and GOAL_COLUMN_WIDTH or 0)
end

local FALLBACK_ICON = "Interface\\Icons\\INV_Misc_Log_01"

local function Round(v) return math.floor(v + 0.5) end

--------------------------------------------------------------------------------
-- Skins
--
-- Each art set is one matched group drawn against a window of some native width,
-- so every piece shares a single scale factor and keeps its proportions.
--
-- Nothing here is a measurement of the finished frame — it is all measurements
-- *of the source files*, and the geometry is solved from them. That matters
-- because the sets disagree: the wood rails are 69px of a 921px window, the
-- nature rails 92px of 941. Each therefore implies a different frame width,
-- padding and header height, so a skin is not a texture swap — it is a relayout.
--
-- Plank pieces come from images\keyed\, where the white matte the generator
-- baked in has been turned back into transparency. images\ holds the originals
-- and the backgrounds (those only needed a crop, not keying).
--
--   artWidth        native width of the top piece; the whole set scales to match
--   topH/bottomH    native heights of those pieces
--   railW           native rail width
--   topBeamStart    display row where the top plank's beam begins
--   topBeamEnd      display row where the top plank's beam finishes
--   bottomBeamTop   display row where the bottom plank's beam starts
--   bgW/bgH         background dimensions, needed for the border crop
--
-- The beam rows matter because both planks carry heavy transparent padding: the
-- corner posts run the full height while the beam itself doesn't. Left alone
-- that padding shows as a dead band between the plank and the rows, so the rows
-- start at the beam and let the posts overhang them transparently.
--------------------------------------------------------------------------------

local IMG_PATH   = "Interface\\AddOns\\LumberOne\\images\\"
local KEYED_PATH = IMG_PATH .. "keyed\\"

local SKINS = {
	{
		key = "blizzard",
		name = "Blizzard",
		desc = "The stock UI dialog frame.",
		-- No art. These are used as-is rather than solved for.
		padding = 8, headerHeight = 28, footerHeight = 16,
	},
	{
		key = "wood",
		name = "Wood",
		desc = "Hand-hewn planks and rope.",
		prefix = "1_",
		artWidth = 921, topH = 166, bottomH = 141, railW = 69, railH = 386,
		topBeamStart = 23, topBeamEnd = 81,
		bottomBeamTop = 71, bottomBeamEnd = 124,
		bgW = 377, bgH = 373,
	},
	{
		key = "nature",
		name = "Nature",
		desc = "Mossy timber and growth.",
		prefix = "2_",
		artWidth = 924, topH = 161, bottomH = 145, railW = 76, railH = 341,
		topBeamStart = 34, topBeamEnd = 77,
		bottomBeamTop = 73, bottomBeamEnd = 116,
		bgW = 384, bgH = 376,
		-- Vines and leaves smear when pulled 3x; wood grain survives it. This set's
		-- rail was drawn to repeat — 2px of padding at each end, and its top and
		-- bottom silhouettes match across all but 4 of its 76 columns.
		tileRails = true,
		-- This set's rail post measures 9.7px on screen against an 11.4px top beam,
		-- so the frame reads as spindly-sided with chunky ends. Drawing the rail
		-- 3px wider brings the post to ~11.2px. It grows inward across ROW_MARGIN,
		-- which is why that margin is 4 and not 2 — and it tightens the gap between
		-- the rails without moving the frame width.
		railBoost = 3,
	},
}

local DEFAULT_SKIN = "wood"

local SKIN_BY_KEY = {}
for i, skin in ipairs(SKINS) do
	skin.index = i
	SKIN_BY_KEY[skin.key] = skin
end

-- How far the rails run *under* the top and bottom planks. The corners are baked
-- into those pieces, so the rails have to disappear beneath them well before the
-- joint, or the butt-end of each rail shows as a seam.
local ART_OVERLAP = 24

-- How far the top and bottom planks overhang the frame's sides, so they close
-- over the rails instead of meeting them edge-to-edge. Costs a little horizontal
-- stretch in those two pieces, which is cheaper than a visible corner gap.
local ART_BLEED = 6

-- The backgrounds carry a 1-2px white border. Cropping exactly its thickness
-- leaves the sample landing on the white/wood boundary, where filtering blends
-- the white back in — so take a few pixels of wood with it.
local BG_INSET   = 3
local BG_OVERLAP = 6 -- tucks the fill under the planks so no hairline shows

local BLIZZARD_BACKDROP = {
	bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
	edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
	tile = true, tileSize = 32, edgeSize = 16,
	insets = { left = 4, right = 4, top = 4, bottom = 4 },
}

-- Solves the frame width for a skin. The rails are a fixed *fraction* of that
-- width rather than a fixed pixel count — widening the frame widens the rails,
-- which eats back into the space the rows need. Hence the division: it lands the
-- rows and both rails exactly on frameWidth instead of chasing it.
local function ComputeGeometry(skin)
	local rowWidth = RowWidth()

	if not skin.prefix then
		return {
			rowWidth      = rowWidth,
			frameWidth    = rowWidth + skin.padding * 2,
			padding       = skin.padding,
			railWidth     = skin.padding, -- no art to draw, but keep the shape uniform
			headerHeight  = skin.headerHeight,
			footerHeight  = skin.footerHeight,
			topDisplay    = skin.headerHeight,
			bottomDisplay = skin.footerHeight,
			closeSize     = skin.headerHeight - 2,
			textOffsetY   = 0,
			bottomDrop    = 0, -- no art to drop, but keep the shape uniform
		}
	end

	-- Solve for the width where the rows and both rails land exactly, then round
	-- the *padding* and derive the width back from it. Rounding both independently
	-- lets them disagree by a pixel — the rows then overhang the rail on some
	-- combinations (166px rows on the wood set was one) and the frame edge shows
	-- a hairline gap.
	local ideal = rowWidth / (1 - 2 * skin.railW / skin.artWidth)
	local padding = Round(skin.railW * ideal / skin.artWidth)
	local frameWidth = rowWidth + padding * 2

	local s = frameWidth / skin.artWidth
	local headerHeight = Round(skin.topBeamEnd * s)

	-- The beam stops short of its own file's bottom edge — 16 rows on wood, 31 on
	-- nature. Anchored flush, that padding becomes dead space under the beam and the
	-- frame reads as not closing. Drop the piece by exactly that much so the beam's
	-- underside lands on the frame's edge; the corner posts simply overhang, which
	-- is what they should do anyway.
	local bottomDrop = Round((skin.bottomH - 1 - skin.bottomBeamEnd) * s)

	return {
		rowWidth   = rowWidth,
		frameWidth = frameWidth,
		artScale   = s,
		padding    = padding,
		-- Drawn width of the rails. Normally the same as the content inset, but a
		-- skin can widen them inward over ROW_MARGIN when its post is thinner than
		-- its beam. Only the drawing changes — the layout still solves on padding.
		railWidth = padding + (skin.railBoost or 0),
		-- Drawn at true proportions, transparent padding included.
		topDisplay    = Round(skin.topH * s),
		bottomDisplay = Round(skin.bottomH * s),
		-- Rows start and stop at the beams, not at the edge of the art.
		headerHeight = headerHeight,
		-- Measured against the *dropped* beam, or the rows would stop where the beam
		-- used to be and leave the gap this was meant to close.
		footerHeight = Round((skin.bottomH - skin.bottomBeamTop) * s) - bottomDrop,
		bottomDrop   = bottomDrop,
		railNaturalH = skin.railH * s,
		tileRails    = skin.tileRails,
		-- The close button fits the beam rather than a fixed scale: it is 32px
		-- native, so a constant would overhang a shallow beam on one skin and
		-- look lost on another.
		closeSize = headerHeight - 2,
		-- Header type centres on the beam, not on the header box. The beam sits
		-- low in the art, so text centred on the box reads a few pixels high.
		textOffsetY = Round(headerHeight / 2 - (skin.topBeamStart + skin.topBeamEnd) / 2 * s),
	}
end

-- How far the close button's right edge sits from the frame's right edge. It is
-- pushed out over the rail deliberately: parked inside the content area it lands
-- directly above the first row's goal box, which is a misclick waiting to happen.
local CLOSE_EDGE = 4

local frame
local rows = {}
local G = ComputeGeometry(SKIN_BY_KEY[DEFAULT_SKIN]) -- live geometry

-- Rails can tile instead of stretch. The repeat count depends on the frame
-- height, so it has to be refreshed whenever rows show or hide.
local function UpdateRailTexCoords()
	if not frame or not G.tileRails then return end
	local span = frame:GetHeight() - (G.topDisplay - ART_OVERLAP) - (G.bottomDisplay - ART_OVERLAP)
	local repeats = span / G.railNaturalH
	frame.artLeft:SetTexCoord(0, 1, 0, repeats)
	frame.artRight:SetTexCoord(0, 1, 0, repeats)
end

--------------------------------------------------------------------------------
-- Tooltip
--------------------------------------------------------------------------------

local function ClassColor(class)
	local c = class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
	if c then return c.r, c.g, c.b end
	return 1, 1, 1
end

local function ShowRowTooltip(row)
	local entry = row.entry
	if not entry then return end

	GameTooltip:SetOwner(row, "ANCHOR_RIGHT")

	if entry.id then
		GameTooltip:SetItemByID(entry.id)
	else
		GameTooltip:SetText(entry.name, 1, 1, 1)
	end

	local data = ns.GetBreakdown(entry.key)
	local goal = ns.GetGoal(entry.key)

	GameTooltip:AddLine(" ")
	GameTooltip:AddLine(entry.expac, 0.6, 0.6, 0.6)
	GameTooltip:AddLine("Where to chop it:", 1, 0.82, 0)
	GameTooltip:AddLine(entry.where, 1, 1, 1, true)

	GameTooltip:AddLine(" ")

	if #data.chars == 0 and data.warband == 0 then
		GameTooltip:AddLine("None anywhere on the account.", 0.6, 0.6, 0.6)
	else
		for _, char in ipairs(data.chars) do
			local r, g, b = ClassColor(char.class)
			local label = char.name .. (char.isCurrent and " (here)" or "")
			local detail = ("%d"):format(char.total)
			if char.bags > 0 and char.bank > 0 then
				detail = ("%d  |cff808080(%d bags, %d bank)|r"):format(char.total, char.bags, char.bank)
			elseif char.bank > 0 then
				detail = ("%d  |cff808080(bank)|r"):format(char.total)
			end
			GameTooltip:AddDoubleLine(label, detail, r, g, b, 1, 1, 1)
		end

		if data.warband > 0 then
			GameTooltip:AddDoubleLine("Warband bank", tostring(data.warband), 0.6, 0.8, 1, 1, 1, 1)
		end
	end

	GameTooltip:AddDoubleLine("Total", tostring(data.total), 1, 0.82, 0, 1, 0.82, 0)

	if goal > 0 then
		GameTooltip:AddLine(" ")
		if data.total >= goal then
			GameTooltip:AddLine(("Goal of %d met."):format(goal), 0.3, 1, 0.3)
		else
			GameTooltip:AddLine(("%d more to reach %d."):format(goal - data.total, goal), 1, 0.6, 0.2)
		end
	end

	if not ns.HasBankData() then
		GameTooltip:AddLine(" ")
		GameTooltip:AddLine("Visit a bank once to count your bank and Warband stock.", 0.6, 0.6, 0.6, true)
	end

	GameTooltip:Show()
end

--------------------------------------------------------------------------------
-- Header tooltip: how fresh is this data?
--------------------------------------------------------------------------------

local function ShowHeaderTooltip(self)
	local info = ns.GetScanInfo()

	GameTooltip:SetOwner(self, "ANCHOR_BOTTOMRIGHT")
	GameTooltip:SetText("Lumber One", 1, 0.82, 0)
	GameTooltip:AddLine("Totals cover every character on the account.", 0.6, 0.6, 0.6, true)
	GameTooltip:AddLine(" ")

	local text, r, g, b = ns.FormatAge(info.warbandSeen)
	if info.warbandSeen and info.warbandSeenBy then
		text = text .. " |cff808080(" .. info.warbandSeenBy .. ")|r"
	end
	GameTooltip:AddDoubleLine("Warband bank scanned", text, 0.6, 0.8, 1, r, g, b)

	GameTooltip:AddLine(" ")
	GameTooltip:AddLine("Last seen", 1, 0.82, 0)

	for _, char in ipairs(info.chars) do
		local cr, cg, cb = ClassColor(char.class)
		local bagsText = ns.FormatAge(char.bagsSeen)
		local bankText, br, bg, bb = ns.FormatAge(char.bankSeen)
		GameTooltip:AddDoubleLine(
			char.name .. (char.isCurrent and " (here)" or ""),
			("bags %s"):format(bagsText),
			cr, cg, cb, 0.8, 0.8, 0.8)
		GameTooltip:AddDoubleLine(" ", ("bank %s"):format(bankText), 1, 1, 1, br, bg, bb)
	end

	GameTooltip:AddLine(" ")
	GameTooltip:AddLine("Bags update live. Bank and Warband numbers are from the last bank visit.", 0.6, 0.6, 0.6, true)
	GameTooltip:AddLine(" ")
	if LumberOneDB.ui.locked then
		GameTooltip:AddLine("Frame is locked. /lumber unlock to move or resize.", 0.6, 0.6, 0.6)
	else
		GameTooltip:AddLine("Drag this bar to move. Drag the corner to resize.", 0.4, 0.8, 1)
	end
	GameTooltip:Show()
end

--------------------------------------------------------------------------------
-- Rows
--------------------------------------------------------------------------------

local function CreateRow(parent, index)
	local row = CreateFrame("Button", nil, parent)
	row:SetSize(RowWidth(), ROW_HEIGHT)

	row.glow = row:CreateTexture(nil, "BACKGROUND")
	row.glow:SetAllPoints()
	row.glow:SetColorTexture(0.2, 0.9, 0.2, 0.18)
	row.glow:Hide()

	local pulse = row.glow:CreateAnimationGroup()
	pulse:SetLooping("BOUNCE")
	local alpha = pulse:CreateAnimation("Alpha")
	alpha:SetFromAlpha(1)
	alpha:SetToAlpha(0.35)
	alpha:SetDuration(1.1)
	row.pulse = pulse

	row.highlight = row:CreateTexture(nil, "HIGHLIGHT")
	row.highlight:SetAllPoints()
	row.highlight:SetColorTexture(1, 1, 1, 0.07)

	row.icon = row:CreateTexture(nil, "ARTWORK")
	row.icon:SetSize(ICON_SIZE, ICON_SIZE)
	row.icon:SetPoint("LEFT", ROW_MARGIN, 0)
	row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

	row.name = row:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
	row.name:SetPoint("LEFT", row.icon, "RIGHT", 6, 0)
	row.name:SetWidth(NAME_WIDTH)
	row.name:SetJustifyH("LEFT")
	-- Truncate rather than wrap: a wrapped name would spill out of the row.
	row.name:SetWordWrap(false)

	row.count = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
	row.count:SetPoint("LEFT", row.name, "RIGHT", 4, 0)
	row.count:SetWidth(COUNT_WIDTH)
	row.count:SetJustifyH("RIGHT")

	row.goal = CreateFrame("EditBox", nil, row, "InputBoxTemplate")
	row.goal:SetSize(GOAL_WIDTH, 18)
	row.goal:SetPoint("RIGHT", -ROW_MARGIN, 0)
	row.goal:SetAutoFocus(false)
	row.goal:SetNumeric(true)
	-- Capped to what the box can actually show, so a long entry can't scroll out
	-- of sight while you type it.
	row.goal:SetMaxLetters(GOAL_MAX_DIGITS)
	row.goal:SetJustifyH("CENTER")
	row.goal:SetFontObject("GameFontHighlightSmall")

	row.goal:SetScript("OnEnterPressed", function(self)
		ns.SetGoal(row.entry.key, self:GetText())
		self:ClearFocus()
	end)
	row.goal:SetScript("OnEscapePressed", function(self)
		self:ClearFocus()
		ns.Refresh()
	end)
	row.goal:SetScript("OnEditFocusLost", function(self)
		ns.SetGoal(row.entry.key, self:GetText())
	end)

	row:SetScript("OnEnter", ShowRowTooltip)
	row:SetScript("OnLeave", function() GameTooltip:Hide() end)

	rows[index] = row
	return row
end

--------------------------------------------------------------------------------
-- Frame
--------------------------------------------------------------------------------

function ns.BuildUI()
	if frame then return frame end

	-- BackdropTemplate is carried even though the art skins don't use it: the
	-- Blizzard skin needs SetBackdrop, and the mixin can only be applied at
	-- creation.
	frame = CreateFrame("Frame", "LumberOneFrame", UIParent, "BackdropTemplate")
	frame:SetClampedToScreen(true)

	----------------------------------------------------------------------------
	-- Border art. Created once, re-pointed by ApplySkin: the top and bottom are
	-- fixed art with their corners baked in (the frame never changes width within
	-- a skin), the rails stretch, and the fill stretches.
	--
	-- The fill is stretched rather than tiled. Tiling repeated the file's white
	-- border as a grid of seams; cropping that border off is only possible in
	-- texture space, which rules out the REPEAT wrap tiling needs.
	----------------------------------------------------------------------------

	frame.bg = frame:CreateTexture(nil, "BACKGROUND")

	-- Rails draw under the top and bottom pieces so the corners baked into those
	-- overlap the rail ends rather than butting against them.
	frame.artLeft  = frame:CreateTexture(nil, "BORDER")
	frame.artRight = frame:CreateTexture(nil, "BORDER")
	frame.artTop    = frame:CreateTexture(nil, "ARTWORK")
	frame.artBottom = frame:CreateTexture(nil, "ARTWORK")

	frame:SetMovable(true)
	frame:EnableMouse(true)
	frame:RegisterForDrag("LeftButton")
	frame:SetFrameStrata("MEDIUM")
	frame:Hide()

	local function StartMove()
		if not LumberOneDB.ui.locked then frame:StartMoving() end
	end

	local function StopMove()
		frame:StopMovingOrSizing()
		local point, _, relPoint, x, y = frame:GetPoint()
		LumberOneDB.ui.point, LumberOneDB.ui.relPoint = point, relPoint
		LumberOneDB.ui.x, LumberOneDB.ui.y = x, y
	end

	frame:SetScript("OnDragStart", StartMove)
	frame:SetScript("OnDragStop", StopMove)

	-- The title bar, and the frame's advertised grab point. The whole frame
	-- accepts drags, but this strip is mouse-enabled and would otherwise swallow
	-- the click exactly where people reach for it — so it does the moving.
	-- Spans the top plank, so the wood itself is the thing you grab. No painted
	-- background or underline any more — the art supplies both.
	frame.header = CreateFrame("Button", nil, frame)
	frame.header:RegisterForDrag("LeftButton")
	frame.header:SetScript("OnDragStart", StartMove)
	frame.header:SetScript("OnDragStop", StopMove)
	frame.header:SetScript("OnEnter", ShowHeaderTooltip)
	frame.header:SetScript("OnLeave", function() GameTooltip:Hide() end)

	-- Buttons show their HIGHLIGHT layer on mouseover for free, which is what
	-- tells you the plank is grabbable now that there's no painted bar.
	frame.header.highlight = frame.header:CreateTexture(nil, "HIGHLIGHT")
	frame.header.highlight:SetAllPoints()
	frame.header.highlight:SetColorTexture(1, 0.82, 0, 0.10)

	frame.title = frame.header:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	local titleFont, _, titleFlags = frame.title:GetFont()
	frame.title:SetFont(titleFont, TITLE_FONT_SIZE, titleFlags)
	frame.title:SetPoint("LEFT", 4, 0)
	frame.title:SetText("Lumber One")
	frame.title:SetShadowOffset(1, -1)
	frame.title:SetShadowColor(0, 0, 0, 1)

	-- Centred on the title bar rather than jammed into the frame's corner, so the
	-- whole header reads as one row. ApplySkin scales it to fit the beam rather
	-- than pinning a constant: the header is only as tall as the art says it is,
	-- and the button is 32px native, so a fixed scale would overhang a shallow
	-- beam on one skin while looking lost on another.
	frame.close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
	frame.close:SetScript("OnClick", function() ns.Hide() end)

	-- Parented to the header so it draws above the bar's background, and anchored
	-- to it so it shares the bar's vertical centre. Anchoring to the close button
	-- instead would inherit that button's 0.8 scale and land off-centre.
	frame.goalHeader = frame.header:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	local goalFont, _, goalFlags = frame.goalHeader:GetFont()
	frame.goalHeader:SetFont(goalFont, HEADER_FONT_SIZE, goalFlags)
	frame.goalHeader:SetPoint("RIGHT", frame.header, "RIGHT", -6, 0)
	frame.goalHeader:SetText("Have / Goal")
	frame.goalHeader:SetTextColor(1, 1, 1)
	frame.goalHeader:SetShadowOffset(1, -1)
	frame.goalHeader:SetShadowColor(0, 0, 0, 1)

	--------------------------------------------------------------------------
	-- Resize grip
	--
	-- Dragging it drives ui.scale rather than the frame's pixel size: the height
	-- is derived from the visible row count on every Refresh, so a real resize
	-- would have its vertical axis stamped back the next time anything changed.
	--------------------------------------------------------------------------

	-- Centred in the bottom plank by ApplySkin rather than pinned to the frame
	-- corner, which would bury it in the wood.
	frame.grip = CreateFrame("Button", nil, frame)
	frame.grip:SetSize(14, 14)
	frame.grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
	frame.grip:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
	frame.grip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")

	local function GripUpdate(self)
		local cursorX, cursorY = GetCursorPosition()
		local uiScale = UIParent:GetEffectiveScale()
		cursorX, cursorY = cursorX / uiScale, cursorY / uiScale

		-- Down-and-right grows it. Averaging the axes makes the grip track the
		-- diagonal instead of whichever direction happened to move furthest.
		local delta = ((cursorX - self.startX) + (self.startY - cursorY)) / 2

		-- Always measured against the scale at mouse-down, so rounding can't
		-- accumulate across frames.
		ns.SetScale(self.startScale * (1 + delta / 150))
	end

	frame.grip:SetScript("OnMouseDown", function(self)
		if LumberOneDB.ui.locked then return end
		local cursorX, cursorY = GetCursorPosition()
		local uiScale = UIParent:GetEffectiveScale()
		self.startX, self.startY = cursorX / uiScale, cursorY / uiScale
		self.startScale = LumberOneDB.ui.scale
		self:SetScript("OnUpdate", GripUpdate)
	end)

	frame.grip:SetScript("OnMouseUp", function(self)
		self:SetScript("OnUpdate", nil)
	end)

	frame.grip:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		if LumberOneDB.ui.locked then
			GameTooltip:SetText("Frame is locked.", 1, 0.6, 0.2)
			GameTooltip:AddLine("/lumber unlock to resize.", 0.6, 0.6, 0.6)
		else
			GameTooltip:SetText("Drag to resize", 1, 0.82, 0)
			GameTooltip:AddLine(("%d%%  |cff808080(/lumber reset restores 100%%)|r")
				:format(math.floor(LumberOneDB.ui.scale * 100 + 0.5)), 1, 1, 1)
		end
		GameTooltip:Show()
	end)
	frame.grip:SetScript("OnLeave", function() GameTooltip:Hide() end)

	for i = 1, #ns.LUMBER do
		CreateRow(frame, i)
	end

	ns.ApplySkin(LumberOneDB.ui.skin)
	ns.RestorePosition()
	return frame
end

--------------------------------------------------------------------------------
-- Skinning
--------------------------------------------------------------------------------

function ns.GetSkins()
	return SKINS
end

function ns.GetSkin()
	return (LumberOneDB and LumberOneDB.ui.skin) or DEFAULT_SKIN
end

-- Swaps the art and re-solves the layout. Every anchor that depends on the skin
-- lives here rather than in BuildUI, because the frame width, padding, header
-- and footer all change with the art — a skin is a relayout, not a repaint.
function ns.ApplySkin(key)
	local skin = SKIN_BY_KEY[key] or SKIN_BY_KEY[DEFAULT_SKIN]

	if LumberOneDB then LumberOneDB.ui.skin = skin.key end
	if not frame then return end

	G = ComputeGeometry(skin)

	local art = { frame.bg, frame.artLeft, frame.artRight, frame.artTop, frame.artBottom }

	if skin.prefix then
		frame:SetBackdrop(nil)

		frame.bg:SetTexture(IMG_PATH .. skin.prefix .. "bg.tga")
		frame.bg:SetTexCoord(BG_INSET / skin.bgW, 1 - BG_INSET / skin.bgW,
		                     BG_INSET / skin.bgH, 1 - BG_INSET / skin.bgH)
		-- A tiling rail repeats its art down the frame instead of pulling one
		-- copy to fit; the REPEAT wrap is what makes texture coords past 1 stack
		-- rather than clamp. Stretching is fine for grain but smears foliage.
		local wrap = skin.tileRails and "REPEAT" or "CLAMP"
		frame.artLeft:SetTexture(KEYED_PATH .. skin.prefix .. "leftrail.tga", "CLAMP", wrap)
		frame.artRight:SetTexture(KEYED_PATH .. skin.prefix .. "rightrail.tga", "CLAMP", wrap)
		if not skin.tileRails then
			frame.artLeft:SetTexCoord(0, 1, 0, 1)
			frame.artRight:SetTexCoord(0, 1, 0, 1)
		end

		frame.artTop:SetTexture(KEYED_PATH .. skin.prefix .. "top.tga")
		frame.artBottom:SetTexture(KEYED_PATH .. skin.prefix .. "bottom.tga")

		for _, tex in ipairs(art) do tex:Show() end

		frame.bg:ClearAllPoints()
		frame.bg:SetPoint("TOPLEFT", G.padding - BG_OVERLAP, -(G.headerHeight - BG_OVERLAP))
		frame.bg:SetPoint("BOTTOMRIGHT", -(G.padding - BG_OVERLAP), G.footerHeight - BG_OVERLAP)

		-- Rails anchor against the art's full height, not the beam, or the
		-- overlap would be measured from the wrong place.
		frame.artLeft:ClearAllPoints()
		frame.artLeft:SetWidth(G.railWidth)
		frame.artLeft:SetPoint("TOPLEFT", 0, -(G.topDisplay - ART_OVERLAP))
		frame.artLeft:SetPoint("BOTTOMLEFT", 0, G.bottomDisplay - ART_OVERLAP)

		frame.artRight:ClearAllPoints()
		frame.artRight:SetWidth(G.railWidth)
		frame.artRight:SetPoint("TOPRIGHT", 0, -(G.topDisplay - ART_OVERLAP))
		frame.artRight:SetPoint("BOTTOMRIGHT", 0, G.bottomDisplay - ART_OVERLAP)

		frame.artTop:ClearAllPoints()
		frame.artTop:SetHeight(G.topDisplay)
		frame.artTop:SetPoint("TOPLEFT", -ART_BLEED, 0)
		frame.artTop:SetPoint("TOPRIGHT", ART_BLEED, 0)

		frame.artBottom:ClearAllPoints()
		frame.artBottom:SetHeight(G.bottomDisplay)
		frame.artBottom:SetPoint("BOTTOMLEFT", -ART_BLEED, -G.bottomDrop)
		frame.artBottom:SetPoint("BOTTOMRIGHT", ART_BLEED, -G.bottomDrop)
	else
		for _, tex in ipairs(art) do tex:Hide() end
		frame:SetBackdrop(BLIZZARD_BACKDROP)
	end

	frame:SetWidth(G.frameWidth)

	-- The drag bar stops short of the close button rather than reserving a fixed
	-- slab, since the button's size now tracks the beam.
	frame.header:ClearAllPoints()
	frame.header:SetPoint("TOPLEFT", G.padding, 0)
	frame.header:SetPoint("TOPRIGHT", -(CLOSE_EDGE + G.closeSize + 2), 0)
	frame.header:SetHeight(G.headerHeight)

	frame.close:SetScale(G.closeSize / 32)
	frame.close:ClearAllPoints()
	frame.close:SetPoint("RIGHT", frame, "TOPRIGHT",
		-CLOSE_EDGE, -(G.headerHeight / 2) + G.textOffsetY)

	frame.title:ClearAllPoints()
	frame.title:SetPoint("LEFT", frame.header, "LEFT", 4, G.textOffsetY)

	frame.goalHeader:ClearAllPoints()
	frame.goalHeader:SetPoint("RIGHT", frame.header, "RIGHT", -6, G.textOffsetY)
	frame.goalHeader:SetText(ShowingGoals() and "Have / Goal" or "Have")

	frame.grip:ClearAllPoints()
	frame.grip:SetPoint("BOTTOMRIGHT", -G.padding, Round((G.footerHeight - 14) / 2))

	for _, row in ipairs(rows) do
		row:SetWidth(G.rowWidth)
		row.goal:SetShown(ShowingGoals())
	end

	ns.Refresh()
end

-- Paints every border piece a flat colour, so you can see where each one actually
-- lands independently of whether its texture loaded. A piece that shows up as a
-- coloured bar is positioned correctly and its art is at fault; a piece that stays
-- invisible is a layout problem. Toggled with /lumber debug.
local debugging = false

function ns.ToggleArtDebug()
	if not frame then return false end
	debugging = not debugging

	if debugging then
		-- Flat colours ignore tiling, so drop any repeat coords first.
		frame.artLeft:SetTexCoord(0, 1, 0, 1)
		frame.artRight:SetTexCoord(0, 1, 0, 1)
		frame.bg:SetColorTexture(0.4, 0, 0.5, 0.7)        -- purple
		frame.artLeft:SetColorTexture(0, 0.8, 0, 0.7)     -- green
		frame.artRight:SetColorTexture(0.9, 0.9, 0, 0.7)  -- yellow
		frame.artTop:SetColorTexture(1, 0, 0, 0.7)        -- red
		frame.artBottom:SetColorTexture(0, 0.4, 1, 0.7)   -- blue
		for _, tex in ipairs({ frame.bg, frame.artLeft, frame.artRight, frame.artTop, frame.artBottom }) do
			tex:Show()
		end
	else
		ns.ApplySkin(ns.GetSkin())
	end

	return debugging
end

-- Reports what the texture objects ACTUALLY are, not what the geometry intends.
-- The two can disagree — a texture that fails to load still reports its rect, and
-- an anchor that didn't take still computes fine on paper.
function ns.DescribeGeometry()
	if not frame then return "UI not built yet." end

	local lines = {
		("%s: frame %dx%d  rail=%d header=%d footer=%d drop=%d textY=%d")
			:format(ns.GetSkin(), Round(frame:GetWidth()), Round(frame:GetHeight()),
				G.padding, G.headerHeight, G.footerHeight, G.bottomDrop, G.textOffsetY),
		("  intended: topArt=%d botArt=%d railNatural=%s tile=%s")
			:format(G.topDisplay, G.bottomDisplay,
				G.railNaturalH and Round(G.railNaturalH) or "-", tostring(G.tileRails)),
	}

	local function report(name, tex)
		local file = tex:GetTexture()
		-- GetTexCoord returns eight values (UL, LL, UR, LR as x,y pairs), so the
		-- vertical range is the 2nd and 4th — not the 3rd and 4th.
		local _, upperY, _, lowerY = tex:GetTexCoord()
		lines[#lines + 1] = ("  %-9s %3dx%-3d  v=%.2f..%.2f  %s"):format(
			name, Round(tex:GetWidth() or 0), Round(tex:GetHeight() or 0),
			upperY or 0, lowerY or 0,
			file and tostring(file):match("[^\\]+$") or "|cffff0000NO TEXTURE|r")
	end

	report("bg", frame.bg)
	report("artTop", frame.artTop)
	report("artBottom", frame.artBottom)
	report("artLeft", frame.artLeft)
	report("artRight", frame.artRight)

	return table.concat(lines, "\n")
end

-- Goals are account-wide and rarely changed once set, so the column is worth
-- reclaiming. Hiding it narrows the row, which re-solves the frame width for
-- whichever skin is active — hence the full ApplySkin rather than a Refresh.
function ns.SetShowGoals(show)
	LumberOneDB.ui.showGoals = show and true or false
	ns.ApplySkin(ns.GetSkin())
end

function ns.GetShowGoals()
	return ShowingGoals()
end

-- Re-applies every saved display setting: where the frame sits, how big it is and
-- how solid. Called wherever the frame is (re)established.
function ns.RestorePosition()
	if not frame then return end
	local ui = LumberOneDB.ui
	frame:ClearAllPoints()
	frame:SetPoint(ui.point, UIParent, ui.relPoint, ui.x, ui.y)
	frame:SetScale(ui.scale)
	frame:SetAlpha(ui.opacity or 1)
end

-- Alpha on the frame cascades to every child, so one call fades the art, the rows
-- and the goal boxes together.
function ns.SetOpacity(value)
	value = tonumber(value)
	if not value then return false end
	value = math.max(MIN_OPACITY, math.min(MAX_OPACITY, value))

	LumberOneDB.ui.opacity = value
	if frame then frame:SetAlpha(value) end
	return true
end

function ns.GetOpacity()
	return (LumberOneDB and LumberOneDB.ui.opacity) or 1
end

function ns.GetOpacityBounds()
	return MIN_OPACITY, MAX_OPACITY
end

-- The single way scale changes, whether from the grip or /lumber scale.
function ns.SetScale(value)
	value = tonumber(value)
	if not value then return false end
	value = math.max(MIN_SCALE, math.min(MAX_SCALE, value))

	local ui = LumberOneDB.ui
	local old = ui.scale or 1
	if math.abs(value - old) < 0.001 then return true end

	-- A point's offsets are expressed in the frame's own scaled coordinates, so
	-- changing scale drags the frame across the screen unless the offsets are
	-- rescaled to compensate. Anchor stays put; the frame grows around it.
	ui.x = ui.x * old / value
	ui.y = ui.y * old / value
	ui.scale = value

	ns.RestorePosition()
	return true
end

function ns.GetScaleBounds()
	return MIN_SCALE, MAX_SCALE
end

--------------------------------------------------------------------------------
-- Refresh
--------------------------------------------------------------------------------

function ns.Refresh()
	if not frame then return end

	local visible = 0

	for i, entry in ipairs(ns.LUMBER) do
		local row = rows[i]
		local total = ns.GetTotal(entry.key)
		local goal = ns.GetGoal(entry.key)

		if LumberOneDB.ui.hideZero and total == 0 and goal == 0 then
			row:Hide()
		else
			visible = visible + 1
			row:ClearAllPoints()
			row:SetPoint("TOPLEFT", G.padding, -(G.headerHeight + (visible - 1) * ROW_HEIGHT))
			row:Show()

			row.entry = entry
			row.icon:SetTexture((entry.id and C_Item.GetItemIconByID(entry.id)) or FALLBACK_ICON)
			row.name:SetText(entry.name:gsub(" Lumber$", ""))
			row.count:SetText(tostring(total))

			if not row.goal:HasFocus() then
				row.goal:SetText(goal > 0 and tostring(goal) or "")
			end

			local met = goal > 0 and total >= goal
			if met then
				row.name:SetTextColor(0.4, 1, 0.4)
				row.count:SetTextColor(0.4, 1, 0.4)
				row.glow:Show()
				if not row.pulse:IsPlaying() then row.pulse:Play() end
			else
				row.name:SetTextColor(1, 0.82, 0)
				row.count:SetTextColor(1, 1, 1)
				if row.pulse:IsPlaying() then row.pulse:Stop() end
				row.glow:Hide()
			end
		end
	end

	frame:SetHeight(G.headerHeight + math.max(visible, 1) * ROW_HEIGHT + G.footerHeight)
	UpdateRailTexCoords()

	if GameTooltip:IsOwned(frame) then GameTooltip:Hide() end
end

--------------------------------------------------------------------------------
-- Show / Hide
--------------------------------------------------------------------------------

function ns.Show()
	ns.BuildUI()
	ns.RestorePosition()
	frame:Show()
	LumberOneDB.ui.shown = true
	ns.Refresh()
end

function ns.Hide()
	if frame then frame:Hide() end
	LumberOneDB.ui.shown = false
end

function ns.Toggle()
	if frame and frame:IsShown() then
		ns.Hide()
	else
		ns.Show()
	end
end
