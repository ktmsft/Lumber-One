local ADDON, ns = ...

--------------------------------------------------------------------------------
-- Options panel
--
-- Registered into the game's own Settings list rather than rolled as a floating
-- window, so it lives where people already look for addon settings.
--
-- Nothing here reads LumberOneDB at load: this file runs during ADDON_LOADED,
-- before the saved variables are populated, so every control takes its state
-- from OnShow instead.
--------------------------------------------------------------------------------

local panel = CreateFrame("Frame")
panel.name = "Lumber One"

local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
title:SetPoint("TOPLEFT", 16, -16)
title:SetText("Lumber One")

local subtitle = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
subtitle:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
subtitle:SetPoint("RIGHT", panel, "RIGHT", -32, 0)
subtitle:SetJustifyH("LEFT")
subtitle:SetText("An account-wide tally of every housing lumber across your bags, "
	.. "bank and Warband bank.")

--------------------------------------------------------------------------------
-- Frame style
--------------------------------------------------------------------------------

local skinLabel = panel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
skinLabel:SetPoint("TOPLEFT", subtitle, "BOTTOMLEFT", 0, -24)
skinLabel:SetText("Frame style")

local skinHint = panel:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
skinHint:SetPoint("TOPLEFT", skinLabel, "BOTTOMLEFT", 0, -4)
skinHint:SetText("Each style has its own proportions, so the window resizes to suit it.")

local radios = {}

local function SelectSkin(key)
	ns.ApplySkin(key)
	for _, radio in ipairs(radios) do
		radio:SetChecked(radio.skinKey == key)
	end
end

local previous
for index, skin in ipairs(ns.GetSkins()) do
	local radio = CreateFrame("CheckButton", nil, panel, "UIRadioButtonTemplate")
	radio.skinKey = skin.key

	if previous then
		radio:SetPoint("TOPLEFT", previous, "BOTTOMLEFT", 0, -10)
	else
		radio:SetPoint("TOPLEFT", skinHint, "BOTTOMLEFT", 4, -10)
	end

	local name = radio:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
	name:SetPoint("LEFT", radio, "RIGHT", 4, 0)
	name:SetText(skin.name)

	local desc = radio:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
	desc:SetPoint("LEFT", name, "RIGHT", 10, 0)
	desc:SetText(skin.desc)

	radio:SetScript("OnClick", function(self)
		SelectSkin(self.skinKey)
	end)

	radios[index] = radio
	previous = radio
end

--------------------------------------------------------------------------------
-- Toggles
--------------------------------------------------------------------------------

local function MakeCheck(anchor, label, tooltip, onClick)
	local check = CreateFrame("CheckButton", nil, panel, "UICheckButtonTemplate")
	check:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -8)
	check:SetScript("OnClick", function(self) onClick(self:GetChecked()) end)

	local text = check:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
	text:SetPoint("LEFT", check, "RIGHT", 2, 0)
	text:SetText(label)

	check:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:SetText(label, 1, 1, 1)
		GameTooltip:AddLine(tooltip, 0.7, 0.7, 0.7, true)
		GameTooltip:Show()
	end)
	check:SetScript("OnLeave", function() GameTooltip:Hide() end)

	return check
end

local behaviourLabel = panel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
behaviourLabel:SetPoint("TOPLEFT", previous, "BOTTOMLEFT", -4, -20)
behaviourLabel:SetText("Behaviour")

local hideZero = MakeCheck(behaviourLabel, "Hide lumber you have none of",
	"Rows with no lumber and no goal are hidden, and the window shrinks to fit.",
	function(checked)
		LumberOneDB.ui.hideZero = checked
		ns.Refresh()
	end)

local showGoals = MakeCheck(hideZero, "Show goal boxes",
	"Turning these off narrows the window, since the goal column is what makes it wide.",
	function(checked) ns.SetShowGoals(checked) end)

local locked = MakeCheck(showGoals, "Lock the frame",
	"Stops the window being dragged or resized.",
	function(checked) LumberOneDB.ui.locked = checked end)

--------------------------------------------------------------------------------
-- Opacity
--------------------------------------------------------------------------------

local opacityLabel = panel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
opacityLabel:SetPoint("TOPLEFT", locked, "BOTTOMLEFT", 4, -24)
opacityLabel:SetText("Opacity")

local opacityValue = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
opacityValue:SetPoint("LEFT", opacityLabel, "RIGHT", 8, 0)

local minOpacity, maxOpacity = ns.GetOpacityBounds()

local opacity = CreateFrame("Slider", nil, panel, "UISliderTemplate")
opacity:SetPoint("TOPLEFT", opacityLabel, "BOTTOMLEFT", 4, -12)
opacity:SetOrientation("HORIZONTAL")
opacity:SetSize(220, 16)
opacity:SetMinMaxValues(minOpacity, maxOpacity)
opacity:SetValueStep(0.05)
opacity:SetObeyStepOnDrag(true)

local lowLabel = opacity:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
lowLabel:SetPoint("TOPLEFT", opacity, "BOTTOMLEFT", 0, -2)
lowLabel:SetText(("%d%%"):format(minOpacity * 100))

local highLabel = opacity:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
highLabel:SetPoint("TOPRIGHT", opacity, "BOTTOMRIGHT", 0, -2)
highLabel:SetText(("%d%%"):format(maxOpacity * 100))

-- OnValueChanged also fires when OnShow seeds the slider, which would write the
-- saved value straight back over itself. Harmless today, but it would fight any
-- future clamping, so the seeding pass is flagged and skipped.
local seeding = false

opacity:SetScript("OnValueChanged", function(self, value)
	opacityValue:SetText(("%d%%"):format(math.floor(value * 100 + 0.5)))
	if not seeding then ns.SetOpacity(value) end
end)

local footer = panel:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
footer:SetPoint("TOPLEFT", opacity, "BOTTOMLEFT", -4, -32)
footer:SetJustifyH("LEFT")
footer:SetText("Drag the title bar to move the window, or its bottom-right corner "
	.. "to resize.\n/lumber help lists every command.")

--------------------------------------------------------------------------------
-- State
--------------------------------------------------------------------------------

panel:SetScript("OnShow", function()
	if not LumberOneDB then return end
	local current = ns.GetSkin()
	for _, radio in ipairs(radios) do
		radio:SetChecked(radio.skinKey == current)
	end
	hideZero:SetChecked(LumberOneDB.ui.hideZero)
	showGoals:SetChecked(ns.GetShowGoals())
	locked:SetChecked(LumberOneDB.ui.locked)

	seeding = true
	opacity:SetValue(ns.GetOpacity())
	seeding = false
end)

local category = Settings.RegisterCanvasLayoutCategory(panel, "Lumber One")
category.ID = "LumberOne"
Settings.RegisterAddOnCategory(category)

function ns.OpenOptions()
	Settings.OpenToCategory(category.ID)
end
