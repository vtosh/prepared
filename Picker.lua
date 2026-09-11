-- Picker.lua
-- A single reusable popup: "here's a list of things you could pick, click
-- one" plus an optional "Save Current" shortcut. Used by UI.lua for the
-- gear set / spec / talent tier / glyph slot click-to-choose flow.
BossPrepPicker = {}
local Picker = BossPrepPicker

local T = BossPrepTheme
local u = T.u

local W, H = 340, 400

local frame = CreateFrame("Frame", "BossPrepPickerFrame", UIParent)
frame:SetSize(W, H)
frame:SetPoint("CENTER", 0, 0)
frame:SetFrameStrata("FULLSCREEN_DIALOG")
frame:SetMovable(true)
frame:EnableMouse(true)
frame:SetClampedToScreen(true)
frame:Hide()
if UISpecialFrames then tinsert(UISpecialFrames, "BossPrepPickerFrame") end

T.Window(frame, "")

local hint = T.FontString(frame, 11, "textDim", "")
hint:SetPoint("TOPLEFT", 14, -38)
hint:SetText("Click an option to select it")

local listInset = CreateFrame("Frame", nil, frame)
listInset:SetPoint("TOPLEFT", 12, -56)
listInset:SetPoint("BOTTOMRIGHT", -14, 48)
T.Panel(listInset, "insetBG", "border")

local scrollFrame = CreateFrame("ScrollFrame", "BossPrepPickerScroll", listInset, "UIPanelScrollFrameTemplate")
scrollFrame:SetPoint("TOPLEFT", 4, -4)
scrollFrame:SetPoint("BOTTOMRIGHT", -6, 4)
T.SkinScrollFrame(scrollFrame)

local scrollChild = CreateFrame("Frame", nil, scrollFrame)
scrollChild:SetSize(W - 44, 1)
scrollFrame:SetScrollChild(scrollChild)

local saveCurrentBtn = T.Button(frame, "Save Current", 240, 24)
saveCurrentBtn:SetPoint("BOTTOM", 0, 14)

local rowPool = {}
local ROW_HEIGHT = 30

local function GetRow(index)
	local row = rowPool[index]
	if row then return row end

	row = CreateFrame("Button", nil, scrollChild)
	row:SetSize(W - 48, ROW_HEIGHT)

	local hl = row:CreateTexture(nil, "HIGHLIGHT")
	hl:SetAllPoints()
	hl:SetColorTexture(T.color.accent[1], T.color.accent[2], T.color.accent[3], 0.14)

	row.selTex = row:CreateTexture(nil, "BACKGROUND")
	row.selTex:SetAllPoints()
	row.selTex:SetColorTexture(T.color.accent[1], T.color.accent[2], T.color.accent[3], 0.10)
	row.selTex:Hide()

	row.icon = row:CreateTexture(nil, "ARTWORK")
	row.icon:SetSize(20, 20)
	row.icon:SetPoint("LEFT", 8, 0)
	row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

	row.text = T.FontString(row, 12, "text", "")
	row.text:SetPoint("LEFT", row.icon, "RIGHT", 8, 0)
	row.text:SetPoint("RIGHT", -8, 0)
	row.text:SetJustifyH("LEFT")
	row.text:SetWordWrap(false)

	row.check = T.FontString(row, 12, "accent", "")
	row.check:SetPoint("RIGHT", -6, 0)
	row.check:SetText("\226\128\162") -- bullet (U+2022; renders in the default fonts)

	rowPool[index] = row
	return row
end

-- opts = {
--   title = "Pick a Major Glyph",
--   items = { { icon=, text=, selected=bool, onClick=function() end }, ... },
--   onSaveCurrent = function() end,     -- omit to hide the button entirely
--   saveCurrentLabel = "Save Current Glyph",
--   emptyText = "shown if items is empty",
-- }
function Picker:Open(opts)
	frame.__bpTitle:SetText(opts.title or "")

	local items = opts.items or {}

	for i, item in ipairs(items) do
		local row = GetRow(i)
		row:ClearAllPoints()
		row:SetPoint("TOPLEFT", 4, -(i - 1) * ROW_HEIGHT - 4)
		row:Show()
		if item.icon then
			row.icon:SetTexture(item.icon)
			row.icon:Show()
			row.text:SetPoint("LEFT", row.icon, "RIGHT", 8, 0)
		else
			row.icon:Hide()
			row.text:SetPoint("LEFT", row, "LEFT", 10, 0)
		end
		row.text:SetText(item.text or "")
		row.text:SetTextColor(u(item.selected and T.color.accent or T.color.text))
		row.check:SetShown(item.selected and true or false)
		row.selTex:SetShown(item.selected and true or false)
		row:SetScript("OnClick", function()
			if item.onClick then item.onClick() end
			frame:Hide()
		end)
	end

	for i = #items + 1, #rowPool do
		rowPool[i]:Hide()
	end

	if #items == 0 then
		local row = GetRow(1)
		row:ClearAllPoints()
		row:SetPoint("TOPLEFT", 4, -4)
		row:Show()
		row.icon:Hide()
		row.check:Hide()
		row.selTex:Hide()
		row.text:SetPoint("LEFT", row, "LEFT", 10, 0)
		row.text:SetTextColor(u(T.color.textDim))
		row.text:SetText(opts.emptyText or "|cff808080Nothing available.|r")
		row:SetScript("OnClick", nil)
		for i = 2, #rowPool do rowPool[i]:Hide() end
	end

	scrollChild:SetHeight(math.max(1, math.max(#items, 1) * ROW_HEIGHT + 8))

	if opts.onSaveCurrent then
		saveCurrentBtn:Show()
		saveCurrentBtn:SetText(opts.saveCurrentLabel or "Save Current")
		saveCurrentBtn:SetScript("OnClick", function()
			opts.onSaveCurrent()
			frame:Hide()
		end)
	else
		saveCurrentBtn:Hide()
	end

	frame:Show()
end
