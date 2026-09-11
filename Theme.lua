-- Theme.lua
-- One shared dark / flat skin for every BossPrep window (main config, picker
-- popup, alert banner). Everything visual funnels through here so the look
-- stays consistent and is tweakable in one place.

BossPrepTheme = {}
local T = BossPrepTheme

-------------------------------------------------
-- Palette
-------------------------------------------------
T.color = {
	windowBG     = { 0.055, 0.06, 0.075, 0.97 },
	panelBG      = { 0.10, 0.11, 0.13, 0.96 },
	insetBG      = { 0.03, 0.035, 0.045, 0.92 },
	raised       = { 0.15, 0.16, 0.19, 1 },
	titleBG      = { 0.12, 0.13, 0.16, 1 },
	border       = { 1, 1, 1, 0.08 },
	borderStrong = { 1, 1, 1, 0.16 },
	accent       = { 0.20, 1.0, 0.60 },        -- the addon's #33ff99
	accentDim    = { 0.20, 1.0, 0.60, 0.55 },
	text         = { 0.86, 0.87, 0.90 },
	textDim      = { 0.52, 0.54, 0.60 },
	textBright   = { 1, 1, 1 },
	danger       = { 0.97, 0.33, 0.35 },
	dangerBG     = { 0.16, 0.05, 0.06, 0.97 },
}

local function u(c, a) return c[1], c[2], c[3], a or c[4] or 1 end
T.u = u

local FONT = STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF"

-------------------------------------------------
-- Fonts
-------------------------------------------------
function T.FontString(parent, size, colorKey, flags)
	local fs = parent:CreateFontString(nil, "OVERLAY")
	fs:SetFont(FONT, size or 12, flags)
	fs:SetTextColor(u(T.color[colorKey or "text"]))
	fs:SetShadowColor(0, 0, 0, 0.75)
	fs:SetShadowOffset(1, -1)
	return fs
end

local btnFont = CreateFont("BossPrepButtonFont")
btnFont:SetFont(FONT, 12, "")
btnFont:SetTextColor(u(T.color.text))
btnFont:SetShadowColor(0, 0, 0, 0.75)
btnFont:SetShadowOffset(1, -1)

local btnFontHi = CreateFont("BossPrepButtonFontHi")
btnFontHi:SetFont(FONT, 12, "")
btnFontHi:SetTextColor(u(T.color.textBright))
btnFontHi:SetShadowColor(0, 0, 0, 0.75)
btnFontHi:SetShadowOffset(1, -1)

local btnFontDis = CreateFont("BossPrepButtonFontDis")
btnFontDis:SetFont(FONT, 12, "")
btnFontDis:SetTextColor(u(T.color.textDim))

-------------------------------------------------
-- Borders & panels
-------------------------------------------------
function T.Border(frame, colorKey)
	if frame.__bpBorder then return frame.__bpBorder end
	local r, g, b, a = u(T.color[colorKey or "border"])
	local lines = {}
	local defs = {
		top    = { { "TOPLEFT", 0, 0 },    { "TOPRIGHT", 0, 0 },    nil, 1 },
		bottom = { { "BOTTOMLEFT", 0, 0 }, { "BOTTOMRIGHT", 0, 0 }, nil, 1 },
		left   = { { "TOPLEFT", 0, 0 },    { "BOTTOMLEFT", 0, 0 },  1,   nil },
		right  = { { "TOPRIGHT", 0, 0 },   { "BOTTOMRIGHT", 0, 0 }, 1,   nil },
	}
	for name, d in pairs(defs) do
		local tx = frame:CreateTexture(nil, "BORDER")
		tx:SetColorTexture(r, g, b, a)
		tx:SetPoint(d[1][1], frame, d[1][1], d[1][2], d[1][3])
		tx:SetPoint(d[2][1], frame, d[2][1], d[2][2], d[2][3])
		if d[3] then tx:SetWidth(d[3]) end
		if d[4] then tx:SetHeight(d[4]) end
		lines[name] = tx
	end
	frame.__bpBorder = lines
	return lines
end

function T.SetBorderColor(frame, colorKey)
	if not frame.__bpBorder then return end
	local r, g, b, a = u(T.color[colorKey] or T.color.border)
	for _, tx in pairs(frame.__bpBorder) do tx:SetColorTexture(r, g, b, a) end
end

function T.Panel(frame, bgKey, borderKey)
	if not frame.__bpBG then
		local bg = frame:CreateTexture(nil, "BACKGROUND")
		bg:SetAllPoints()
		frame.__bpBG = bg
	end
	frame.__bpBG:SetColorTexture(u(T.color[bgKey or "panelBG"]))
	T.Border(frame, borderKey)
	return frame
end

function T.SetPanelColor(frame, bgKey)
	if frame.__bpBG then frame.__bpBG:SetColorTexture(u(T.color[bgKey])) end
end

function T.Divider(parent)
	local tx = parent:CreateTexture(nil, "ARTWORK")
	tx:SetColorTexture(u(T.color.border))
	tx:SetHeight(1)
	return tx
end

function T.SectionHeader(parent, text)
	local fs = T.FontString(parent, 11, "accent", "")
	fs:SetText(string.upper(text or ""))
	return fs
end

-------------------------------------------------
-- Close (X) button
-------------------------------------------------
function T.CloseButton(parent)
	local b = CreateFrame("Button", nil, parent)
	b:SetSize(22, 22)
	local x = T.FontString(b, 16, "textDim", "")
	x:SetPoint("CENTER")
	x:SetText("\195\151") -- multiplication sign
	b:SetScript("OnEnter", function() x:SetTextColor(u(T.color.danger)) end)
	b:SetScript("OnLeave", function() x:SetTextColor(u(T.color.textDim)) end)
	return b
end

-------------------------------------------------
-- Window: dark panel + title strip + close button + drag handle
-------------------------------------------------
function T.Window(frame, titleText)
	T.Panel(frame, "windowBG", "borderStrong")

	local bar = CreateFrame("Frame", nil, frame)
	bar:SetPoint("TOPLEFT", 1, -1)
	bar:SetPoint("TOPRIGHT", -1, -1)
	bar:SetHeight(30)

	local barBG = bar:CreateTexture(nil, "ARTWORK")
	barBG:SetAllPoints()
	barBG:SetColorTexture(u(T.color.titleBG))

	local underline = bar:CreateTexture(nil, "OVERLAY")
	underline:SetPoint("BOTTOMLEFT", 0, 0)
	underline:SetPoint("BOTTOMRIGHT", 0, 0)
	underline:SetHeight(1)
	underline:SetColorTexture(u(T.color.accentDim))

	local title = T.FontString(bar, 14, "textBright", "")
	title:SetPoint("LEFT", 12, 0)
	title:SetText(titleText or "")
	frame.__bpTitle = title

	local close = T.CloseButton(bar)
	close:SetPoint("RIGHT", -5, 0)
	close:SetScript("OnClick", function() frame:Hide() end)
	frame.__bpClose = close

	if frame:IsMovable() then
		bar:EnableMouse(true)
		bar:RegisterForDrag("LeftButton")
		bar:SetScript("OnDragStart", function() frame:StartMoving() end)
		bar:SetScript("OnDragStop", function() frame:StopMovingOrSizing() end)
	end

	frame.__bpBar = bar
	return bar
end

-------------------------------------------------
-- Flat button
-------------------------------------------------
function T.Button(parent, text, w, h)
	local b = CreateFrame("Button", nil, parent)
	b:SetSize(w or 120, h or 22)
	T.Panel(b, "raised", "border")

	local hl = b:CreateTexture(nil, "HIGHLIGHT")
	hl:SetAllPoints()
	hl:SetColorTexture(T.color.accent[1], T.color.accent[2], T.color.accent[3], 0.13)

	local fs = b:CreateFontString(nil, "OVERLAY")
	fs:SetPoint("CENTER")
	b:SetFontString(fs)
	b:SetNormalFontObject(btnFont)
	b:SetHighlightFontObject(btnFontHi)
	b:SetDisabledFontObject(btnFontDis)
	if b.SetPushedTextOffset then b:SetPushedTextOffset(0, -1) end
	b:SetText(text or "")
	b.text = fs

	b:SetScript("OnEnter", function(self) T.SetBorderColor(self, "borderStrong") end)
	b:SetScript("OnLeave", function(self) T.SetBorderColor(self, "border") end)
	b:HookScript("OnDisable", function(self) T.SetPanelColor(self, "insetBG") end)
	b:HookScript("OnEnable", function(self) T.SetPanelColor(self, "raised") end)

	return b
end

-------------------------------------------------
-- Horizontal slider
--   returns a Slider; set slider.onChange = function(value) end
--   and slider.format = function(value) return "text" end (optional)
-------------------------------------------------
function T.Slider(parent, minV, maxV, step)
	local s = CreateFrame("Slider", nil, parent)
	s:SetOrientation("HORIZONTAL")
	s:SetHeight(14)
	s:SetHitRectInsets(0, 0, -10, -10)
	s:SetMinMaxValues(minV, maxV)
	s:SetValueStep(step or 1)
	if s.SetObeyStepOnDrag then s:SetObeyStepOnDrag(true) end

	local track = s:CreateTexture(nil, "BACKGROUND")
	track:SetPoint("LEFT")
	track:SetPoint("RIGHT")
	track:SetHeight(4)
	track:SetColorTexture(u(T.color.insetBG))

	local thumb = s:CreateTexture(nil, "OVERLAY")
	thumb:SetSize(10, 16)
	thumb:SetColorTexture(u(T.color.accent))
	s:SetThumbTexture(thumb)

	local valueText = T.FontString(s, 11, "textDim", "")
	valueText:SetPoint("BOTTOMRIGHT", s, "TOPRIGHT", 0, 1)
	s.valueText = valueText

	s:SetScript("OnValueChanged", function(self, value)
		local shown = self.format and self.format(value) or tostring(math.floor(value + 0.5))
		self.valueText:SetText(shown)
		if self.onChange and not self.__suppress then self.onChange(value) end
	end)

	-- set the value without firing onChange (for initial sync)
	function s:SetValueSilent(v)
		self.__suppress = true
		self:SetValue(v)
		self.__suppress = false
	end

	return s
end

-------------------------------------------------
-- Checkbox
-------------------------------------------------
function T.Checkbox(parent, labelText)
	local cb = CreateFrame("CheckButton", nil, parent)
	cb:SetSize(16, 16)
	T.Panel(cb, "insetBG", "border")

	cb:SetCheckedTexture("Interface\\Buttons\\WHITE8X8")
	local ck = cb:GetCheckedTexture()
	ck:SetVertexColor(u(T.color.accent))
	ck:ClearAllPoints()
	ck:SetPoint("TOPLEFT", 3, -3)
	ck:SetPoint("BOTTOMRIGHT", -3, 3)

	local hl = cb:CreateTexture(nil, "HIGHLIGHT")
	hl:SetAllPoints()
	hl:SetColorTexture(1, 1, 1, 0.08)
	cb:SetHighlightTexture(hl)

	local fs = T.FontString(cb, 12, "text", "")
	fs:SetPoint("LEFT", cb, "RIGHT", 7, 0)
	fs:SetText(labelText or "")
	cb.text = fs

	cb:SetScript("OnEnter", function(self) T.SetBorderColor(self, "borderStrong") end)
	cb:SetScript("OnLeave", function(self) T.SetBorderColor(self, "border") end)
	return cb
end

-------------------------------------------------
-- Icon slot (click to open a picker)
-------------------------------------------------
function T.IconSlot(parent, size)
	size = size or 36
	local b = CreateFrame("Button", nil, parent)
	b:SetSize(size, size)
	b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	T.Panel(b, "insetBG", "border")

	b.icon = b:CreateTexture(nil, "ARTWORK")
	b.icon:SetPoint("TOPLEFT", 2, -2)
	b.icon:SetPoint("BOTTOMRIGHT", -2, 2)
	b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

	b.plus = T.FontString(b, 15, "textDim", "")
	b.plus:SetPoint("CENTER")
	b.plus:SetText("+")

	-- Source marker: a thin bar along the bottom edge. Accent = this is a
	-- per-boss override; dim = the value shown is inherited from the global
	-- default set. Hidden when the slot is empty.
	b.srcBar = b:CreateTexture(nil, "OVERLAY")
	b.srcBar:SetPoint("BOTTOMLEFT", 1, 1)
	b.srcBar:SetPoint("BOTTOMRIGHT", -1, 1)
	b.srcBar:SetHeight(2)
	b.srcBar:Hide()

	-- Tiny "G" in the corner when the value is inherited from the global set.
	b.tag = T.FontString(b, 8, "accent", "")
	b.tag:SetPoint("TOPLEFT", 2, -1)
	b.tag:SetText("")

	local hl = b:CreateTexture(nil, "HIGHLIGHT")
	hl:SetAllPoints()
	hl:SetColorTexture(1, 1, 1, 0.10)

	b.label = T.FontString(b, 10, "textDim", "")
	b.label:SetPoint("TOP", b, "BOTTOM", 0, -3)
	b.label:SetWidth(size + 44)
	b.label:SetJustifyH("CENTER")
	b.label:SetWordWrap(false)

	b:SetScript("OnEnter", function(self)
		T.SetBorderColor(self, "accentDim")
		if self.tooltipText then
			GameTooltip:SetOwner(self, "ANCHOR_TOP")
			GameTooltip:SetText(self.tooltipText, 1, 1, 1, 1, true)
			GameTooltip:Show()
		end
	end)
	b:SetScript("OnLeave", function(self)
		T.SetBorderColor(self, "border")
		GameTooltip:Hide()
	end)

	-- opts (optional): { faded = bool, mark = "override" | "global" | nil }
	b.SetContent = function(self, icon, label, tooltipText, opts)
		opts = opts or {}
		local a = opts.faded and 0.4 or 1
		if icon then
			self.icon:SetTexture(icon)
			self.icon:SetAlpha(a)
			self.icon:Show()
			self.plus:Hide()
		else
			self.icon:Hide()
			self.plus:SetAlpha(a)
			self.plus:Show()
		end
		self.label:SetText(label or "")
		self.label:SetAlpha(opts.faded and 0.6 or 1)
		self.tooltipText = tooltipText

		if opts.mark == "override" then
			self.srcBar:SetColorTexture(u(T.color.accent))
			self.srcBar:Show()
		elseif opts.mark == "global" or opts.mark == "profile" then
			self.srcBar:SetColorTexture(u(T.color.textDim))
			self.srcBar:Show()
		else
			self.srcBar:Hide()
		end
		self.tag:SetText(opts.tag or (opts.mark == "global" and "G") or "")
	end

	return b
end

-------------------------------------------------
-- Custom flat dropdown (replaces UIDropDownMenuTemplate)
-- Keeps the same surface the rest of the addon expects:
--   dd.options, dd.selectedValue, dd.onSelect
--   dd:SetOptions(list), dd:SetSelected(value, text)
-------------------------------------------------
local menu = CreateFrame("Frame", "BossPrepDropdownMenu", UIParent)
menu:SetFrameStrata("FULLSCREEN_DIALOG")
menu:Hide()
T.Panel(menu, "panelBG", "borderStrong")
menu.rows = {}

local ROWH = 20
local MAX_VISIBLE_ROWS = 12
local SCROLLBAR_W = 12

-- Rows live in a scroll child so long lists (e.g. the sound-effect dropdown
-- once LibSharedMedia contributes its entries) clip and scroll instead of
-- growing the menu off the bottom of the screen.
local scrollFrame = CreateFrame("ScrollFrame", nil, menu)
scrollFrame:SetPoint("TOPLEFT", 3, -4)
scrollFrame:EnableMouseWheel(true)

local content = CreateFrame("Frame", nil, scrollFrame)
content:SetSize(1, 1)
scrollFrame:SetScrollChild(content)

local scrollbar = CreateFrame("Slider", nil, menu)
scrollbar:SetOrientation("VERTICAL")
scrollbar:SetWidth(8)
scrollbar:SetHitRectInsets(-4, -4, 0, 0)
scrollbar:SetValueStep(ROWH)
if scrollbar.SetObeyStepOnDrag then scrollbar:SetObeyStepOnDrag(true) end
scrollbar:Hide()

local sbTrack = scrollbar:CreateTexture(nil, "BACKGROUND")
sbTrack:SetPoint("TOP", 0, -2)
sbTrack:SetPoint("BOTTOM", 0, 2)
sbTrack:SetWidth(4)
sbTrack:SetColorTexture(u(T.color.insetBG))

local sbThumb = scrollbar:CreateTexture(nil, "OVERLAY")
sbThumb:SetSize(8, 26)
sbThumb:SetColorTexture(u(T.color.accent))
scrollbar:SetThumbTexture(sbThumb)

scrollbar:SetScript("OnValueChanged", function(self, value)
	scrollFrame:SetVerticalScroll(value)
end)
scrollFrame:SetScript("OnMouseWheel", function(self, delta)
	scrollbar:SetValue(scrollbar:GetValue() - delta * ROWH * 3)
end)

local blocker = CreateFrame("Button", nil, UIParent)
blocker:SetAllPoints(UIParent)
blocker:SetFrameStrata("FULLSCREEN_DIALOG")
blocker:EnableMouse(true)
blocker:Hide()

local function closeMenu()
	menu:Hide()
	blocker:Hide()
	menu.owner = nil
end
blocker:SetScript("OnClick", closeMenu)
menu:SetFrameLevel(blocker:GetFrameLevel() + 10)
scrollbar:SetFrameLevel(menu:GetFrameLevel() + 1)

local function openMenu(dd)
	if menu:IsShown() and menu.owner == dd then
		closeMenu()
		return
	end
	menu.owner = dd

	for _, r in ipairs(menu.rows) do r:Hide() end

	local width = math.max(dd:GetWidth(), 120)
	local opts = dd.options or {}
	if #opts == 0 then
		opts = { { text = "|cff808080(nothing available)|r", value = nil, disabled = true } }
	end

	local scrollable = #opts > MAX_VISIBLE_ROWS
	local rowWidth = scrollable and (width - SCROLLBAR_W) or width

	local y = 0
	local selIndex
	for i, opt in ipairs(opts) do
		local row = menu.rows[i]
		if not row then
			row = CreateFrame("Button", nil, content)
			row:SetHeight(ROWH)
			local h = row:CreateTexture(nil, "HIGHLIGHT")
			h:SetAllPoints()
			h:SetColorTexture(T.color.accent[1], T.color.accent[2], T.color.accent[3], 0.16)
			row.text = T.FontString(row, 12, "text", "")
			row.text:SetPoint("LEFT", 9, 0)
			row.text:SetPoint("RIGHT", -9, 0)
			row.text:SetJustifyH("LEFT")
			row.text:SetWordWrap(false)
			menu.rows[i] = row
		end
		row:SetWidth(rowWidth)
		row:ClearAllPoints()
		row:SetPoint("TOPLEFT", 0, y)
		row.text:SetText(opt.text or "")
		local isSel = (dd.selectedValue ~= nil and dd.selectedValue == opt.value)
		if isSel then selIndex = i end
		row.text:SetTextColor(u(isSel and T.color.accent or T.color.text))
		if opt.disabled then
			row:SetScript("OnClick", nil)
		else
			row:SetScript("OnClick", function()
				dd:SetSelected(opt.value, opt.text)
				closeMenu()
				if dd.onSelect then dd.onSelect(opt.value, opt.text) end
			end)
		end
		row:Show()
		y = y - ROWH
	end

	local totalRowsHeight = #opts * ROWH
	local visibleHeight = math.min(totalRowsHeight, MAX_VISIBLE_ROWS * ROWH)
	local maxScroll = totalRowsHeight - visibleHeight

	-- Open scrolled so the current selection sits in the middle of the
	-- visible rows, instead of always starting at the top of a long list.
	local initialScroll = 0
	if selIndex then
		local selCenter = (selIndex - 1) * ROWH + ROWH / 2
		initialScroll = math.max(0, math.min(maxScroll, selCenter - visibleHeight / 2))
	end

	content:SetSize(rowWidth, totalRowsHeight)
	scrollFrame:SetSize(rowWidth, visibleHeight)
	scrollFrame:SetVerticalScroll(initialScroll)

	menu:SetWidth(width + 6 + (scrollable and SCROLLBAR_W or 0))
	menu:SetHeight(visibleHeight + 8)
	menu:ClearAllPoints()
	menu:SetPoint("TOPLEFT", dd, "BOTTOMLEFT", 0, -2)

	if scrollable then
		scrollbar:ClearAllPoints()
		scrollbar:SetPoint("TOPRIGHT", menu, "TOPRIGHT", -3, -4)
		scrollbar:SetPoint("BOTTOMRIGHT", menu, "BOTTOMRIGHT", -3, 4)
		scrollbar:SetMinMaxValues(0, maxScroll)
		scrollbar:SetValue(initialScroll)
		scrollbar:Show()
	else
		scrollbar:Hide()
	end

	blocker:Show()
	menu:Show()
end

function T.Dropdown(parent, width, onSelect)
	local dd = CreateFrame("Button", nil, parent)
	dd:SetSize(width or 160, 22)
	T.Panel(dd, "insetBG", "border")

	local hl = dd:CreateTexture(nil, "HIGHLIGHT")
	hl:SetAllPoints()
	hl:SetColorTexture(1, 1, 1, 0.05)

	local label = T.FontString(dd, 12, "text", "")
	label:SetPoint("LEFT", 8, 0)
	label:SetPoint("RIGHT", -18, 0)
	label:SetJustifyH("LEFT")
	label:SetWordWrap(false)
	dd.label = label

	-- Down-caret as a texture, not a glyph - the default fonts (and font
	-- replacements like ElvUI's) don't all carry U+25BC and render tofu.
	local arrow = dd:CreateTexture(nil, "OVERLAY")
	arrow:SetSize(12, 12)
	arrow:SetPoint("RIGHT", -6, -1)
	arrow:SetTexture("Interface\\ChatFrame\\ChatFrameExpandArrow")
	arrow:SetVertexColor(u(T.color.textDim))

	dd.options = {}
	dd.selectedValue = nil
	dd.onSelect = onSelect

	function dd:SetOptions(list) self.options = list or {} end
	function dd:SetSelected(value, text)
		self.selectedValue = value
		self.label:SetText(text or value or "(none)")
	end

	dd:SetScript("OnEnter", function(self) T.SetBorderColor(self, "borderStrong") end)
	dd:SetScript("OnLeave", function(self) T.SetBorderColor(self, "border") end)
	dd:SetScript("OnClick", function(self) openMenu(self) end)
	dd:HookScript("OnHide", function(self) if menu.owner == self then closeMenu() end end)

	return dd
end

-------------------------------------------------
-- Thin the default scroll bar on a UIPanelScrollFrameTemplate
-------------------------------------------------
function T.SkinScrollFrame(scrollFrame)
	-- Make sure the wheel scrolls it (we hide the arrow buttons below).
	scrollFrame:EnableMouseWheel(true)
	scrollFrame:SetScript("OnMouseWheel", function(self, delta)
		local range = self:GetVerticalScrollRange() or 0
		local cur = self:GetVerticalScroll() or 0
		local new = math.min(math.max(cur - delta * 24, 0), range)
		self:SetVerticalScroll(new)
	end)

	local name = scrollFrame:GetName()
	local sb = (name and _G[name .. "ScrollBar"]) or scrollFrame.ScrollBar
	if not sb then return end

	local thumb = sb.GetThumbTexture and sb:GetThumbTexture()
	for _, region in ipairs({ sb:GetRegions() }) do
		if region ~= thumb and region.GetObjectType and region:GetObjectType() == "Texture" then
			region:SetTexture(nil)
		end
	end
	if thumb then
		thumb:SetColorTexture(T.color.accent[1], T.color.accent[2], T.color.accent[3], 0.35)
		thumb:SetWidth(4)
	end

	for _, suffix in ipairs({ "ScrollUpButton", "ScrollDownButton" }) do
		local btn = (name and _G[name .. "ScrollBar" .. suffix]) or sb[suffix]
		if btn then
			btn:SetAlpha(0)
			btn:EnableMouse(false)
			btn:SetHeight(1)
		end
	end

	sb:ClearAllPoints()
	sb:SetPoint("TOPRIGHT", scrollFrame, "TOPRIGHT", 4, -4)
	sb:SetPoint("BOTTOMRIGHT", scrollFrame, "BOTTOMRIGHT", 4, 4)
	sb:SetWidth(6)
end
