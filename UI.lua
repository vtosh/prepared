-- UI.lua
BossPrepUI = {}
local UI = BossPrepUI

local T = BossPrepTheme
local u = T.u

local PANEL_W, PANEL_H = 760, 620
local selectedInstanceKey = nil
local selectedBossKey = nil
local editingGlobal = false  -- true while the "Global Default Set" row is selected

-- Themed widget shortcuts (same call signatures the old helpers had)
local CreateDropdown = T.Dropdown
local CreateIconSlot = T.IconSlot

-- StaticPopups default to DIALOG strata - below our FULLSCREEN_DIALOG windows
-- (the picker, the profile manager), so a raw StaticPopup_Show can open
-- *behind* them where it's invisible. Raise the shown popup above them.
local function showPopup(which)
	local f = StaticPopup_Show(which)
	if f then
		f:SetFrameStrata("FULLSCREEN_DIALOG")
		if f.SetToplevel then f:SetToplevel(true) end
		f:Raise()
	end
	return f
end

-- The edit box on a StaticPopup: `dialog.editBox` isn't populated on every
-- client build, so fall back to dialog:GetEditBox() / the named global.
local function popupEditBox(dialog)
	if dialog.GetEditBox then
		local ok, eb = pcall(dialog.GetEditBox, dialog)
		if ok and eb then return eb end
	end
	if dialog and dialog.editBox then return dialog.editBox end
	local name = dialog and dialog.GetName and dialog:GetName()
	if name and _G[name .. "EditBox"] then return _G[name .. "EditBox"] end
	-- last resort: the currently-shown StaticPopup's edit box
	for i = 1, 4 do
		local eb = _G["StaticPopup" .. i .. "EditBox"]
		if eb and eb:IsShown() then return eb end
	end
	return nil
end

local function popupText(dialog)
	local eb = popupEditBox(dialog)
	return strtrim(eb and eb:GetText() or "")
end

-------------------------------------------------
-- Boss-list row button
-------------------------------------------------
local function MakeBossButton(parent)
	local b = CreateFrame("Button", nil, parent)
	b:SetHeight(24)

	local hl = b:CreateTexture(nil, "HIGHLIGHT")
	hl:SetAllPoints()
	hl:SetColorTexture(1, 1, 1, 0.06)

	b.sel = b:CreateTexture(nil, "BACKGROUND")
	b.sel:SetAllPoints()
	b.sel:SetColorTexture(T.color.accent[1], T.color.accent[2], T.color.accent[3], 0.12)
	b.sel:Hide()

	b.bar = b:CreateTexture(nil, "ARTWORK")
	b.bar:SetPoint("TOPLEFT")
	b.bar:SetPoint("BOTTOMLEFT")
	b.bar:SetWidth(2)
	b.bar:SetColorTexture(u(T.color.accent))
	b.bar:Hide()

	-- Right-aligned "(profile)" tag when this boss borrows another profile's
	-- setup; empty otherwise. Sized to its content so the boss name can run
	-- up against it.
	b.srcText = T.FontString(b, 11, "accentDim", "")
	b.srcText:SetPoint("RIGHT", -6, 0)
	b.srcText:SetJustifyH("RIGHT")
	b.srcText:SetWordWrap(false)

	b.text = T.FontString(b, 12, "text", "")
	b.text:SetPoint("LEFT", 10, 0)
	b.text:SetPoint("RIGHT", b.srcText, "LEFT", -6, 0)
	b.text:SetJustifyH("LEFT")
	b.text:SetWordWrap(false)

	function b:SetSelected(on)
		self.sel:SetShown(on)
		self.bar:SetShown(on)
	end

	-- name = another profile's display name (this boss borrows it), or nil.
	function b:SetSource(name)
		self.srcText:SetText((name and name ~= "") and ("(" .. name .. ")") or "")
	end

	return b
end

-------------------------------------------------
-- Main frame
-------------------------------------------------
local main = CreateFrame("Frame", "BossPrepMainFrame", UIParent)
main:SetSize(PANEL_W, PANEL_H)
main:SetPoint("CENTER")
main:SetMovable(true)
main:EnableMouse(true)
main:RegisterForDrag("LeftButton")
main:SetScript("OnDragStart", main.StartMoving)
main:SetScript("OnDragStop", main.StopMovingOrSizing)
main:SetClampedToScreen(true)
main:SetFrameStrata("DIALOG")
main:Hide()
tinsert(UISpecialFrames, "BossPrepMainFrame") -- Esc closes it

T.Window(main, "Prepared")

-------------------------------------------------
-- Character / profile row (top)
-------------------------------------------------
local charLabel = T.FontString(main, 12, "textDim", "")
charLabel:SetPoint("TOPLEFT", 18, -42)
charLabel:SetText("Character")

local charValue = T.FontString(main, 12, "text", "")
charValue:SetPoint("LEFT", charLabel, "RIGHT", 8, 0)
charValue:SetText(BossPrep.GetCharKey())

local manageBtn = T.Button(main, "Manage...", 84, 22)
manageBtn:SetPoint("TOPRIGHT", -16, -38)
manageBtn:SetScript("OnClick", function() UI:ToggleProfileManager() end)

local profileLabel = T.FontString(main, 12, "textDim", "")
profileLabel:SetText("Profile")

UI.profileDropdown = CreateDropdown(main, 180, function(value)
	BossPrepProfiles:SetActiveProfile(nil, value)
	-- keep whatever boss (or the Global row) was selected - just re-render it
	-- under the newly active profile.
	UI:RefreshProfileDropdown()
	UI:RebuildBossList()
	UI:RefreshDetailPanel()
end)
UI.profileDropdown:SetPoint("RIGHT", manageBtn, "LEFT", -8, 0)
profileLabel:SetPoint("RIGHT", UI.profileDropdown, "LEFT", -8, 0)

function UI:RefreshProfileDropdown()
	local options, active = {}, nil
	for _, p in ipairs(BossPrepProfiles:GetProfiles()) do
		table.insert(options, { text = p.name, value = p.id })
		if p.active then active = p end
	end
	self.profileDropdown:SetOptions(options)
	self.profileDropdown:SetSelected(active and active.id, active and active.name or "(none)")
end

local headerDivider = T.Divider(main)
headerDivider:SetPoint("TOPLEFT", 14, -66)
headerDivider:SetPoint("TOPRIGHT", -14, -66)

-------------------------------------------------
-- Left column: instance selector + boss list
-------------------------------------------------
local listPanel = CreateFrame("Frame", nil, main)
listPanel:SetPoint("TOPLEFT", 16, -104)
listPanel:SetPoint("BOTTOMLEFT", 16, 46)
listPanel:SetWidth(220)
T.Panel(listPanel, "insetBG", "border")

UI.instanceDropdown = CreateDropdown(main, 220, function(value)
	selectedInstanceKey = value
	selectedBossKey = nil
	editingGlobal = false
	UI:RebuildBossList()
	UI:RefreshDetailPanel()
end)
UI.instanceDropdown:SetPoint("BOTTOMLEFT", listPanel, "TOPLEFT", 0, 6)

-- Always-present row at the top of the list: the character-wide default that
-- every boss inherits from.
local globalBtn = MakeBossButton(listPanel)
globalBtn:SetPoint("TOPLEFT", listPanel, "TOPLEFT", 2, -6)
globalBtn:SetPoint("TOPRIGHT", listPanel, "TOPRIGHT", -2, -6)
globalBtn.text:SetText("Global Default Set")
globalBtn.text:SetTextColor(u(T.color.accent))
globalBtn:SetScript("OnClick", function() UI:SelectGlobal() end)

local globalDivider = T.Divider(listPanel)
globalDivider:SetPoint("TOPLEFT", globalBtn, "BOTTOMLEFT", 0, -3)
globalDivider:SetPoint("TOPRIGHT", globalBtn, "BOTTOMRIGHT", 0, -3)

local scrollFrame = CreateFrame("ScrollFrame", "BossPrepBossScroll", listPanel, "UIPanelScrollFrameTemplate")
scrollFrame:SetPoint("TOPLEFT", 6, -36)
scrollFrame:SetPoint("BOTTOMRIGHT", -10, 6)
T.SkinScrollFrame(scrollFrame)

local scrollChild = CreateFrame("Frame", nil, scrollFrame)
scrollChild:SetSize(200, 1)
scrollFrame:SetScrollChild(scrollChild)

local bossButtons = {}

function UI:RefreshBossListHighlight()
	globalBtn:SetSelected(editingGlobal)
	globalBtn.text:SetTextColor(u(BossPrepProfiles:GetGlobalSetup() and T.color.accent or T.color.accentDim))
	for _, btn in ipairs(bossButtons) do
		btn:SetSelected(not editingGlobal
			and btn.bossKey == selectedBossKey and btn.instanceKey == selectedInstanceKey)
	end
end

function UI:SelectBoss(instanceKey, bossKey)
	editingGlobal = false
	selectedInstanceKey = instanceKey
	selectedBossKey = bossKey
	self:RefreshDetailPanel()
	self:RefreshBossListHighlight()
end

function UI:SelectGlobal()
	editingGlobal = true
	selectedBossKey = nil
	self:RefreshDetailPanel()
	self:RefreshBossListHighlight()
end

function UI:RebuildBossList()
	for _, btn in ipairs(bossButtons) do btn:Hide() end
	wipe(bossButtons)

	local inst = BossPrepData:GetInstance(selectedInstanceKey)
	if not inst then return end

	local activeId = BossPrepProfiles:GetActiveProfileId()
	local profileName = {}
	for _, p in ipairs(BossPrepProfiles:GetProfiles()) do profileName[p.id] = p.name end

	local y = 0
	for _, boss in ipairs(inst.bosses) do
		local btn = MakeBossButton(scrollChild)
		btn:SetPoint("TOPLEFT", 2, -y)
		btn:SetPoint("RIGHT", scrollChild, "RIGHT", -2, 0)
		btn.text:SetText(boss.name)
		btn.instanceKey = inst.key
		btn.bossKey = boss.key

		local srcId = BossPrepProfiles:GetBossSource(inst.key, boss.key)
		btn:SetSource((srcId and srcId ~= activeId) and profileName[srcId] or nil)

		local hasOwn = BossPrepProfiles:BossHasOverrides(inst.key, boss.key)
		btn.text:SetTextColor(u(hasOwn and T.color.text or T.color.textDim))

		btn:SetScript("OnClick", function() UI:SelectBoss(inst.key, boss.key) end)
		btn:SetSelected(not editingGlobal
			and boss.key == selectedBossKey and inst.key == selectedInstanceKey)
		table.insert(bossButtons, btn)
		y = y + 25
	end
	scrollChild:SetHeight(math.max(1, y))
	self:RefreshBossListHighlight()
end

function UI:RefreshInstanceDropdown()
	local options = {}
	for _, inst in ipairs(BossPrepData.instances) do
		table.insert(options, { text = inst.name, value = inst.key })
	end
	self.instanceDropdown:SetOptions(options)
	if not selectedInstanceKey and BossPrepData.instances[1] then
		selectedInstanceKey = BossPrepData.instances[1].key
	end
	local inst = BossPrepData:GetInstance(selectedInstanceKey)
	self.instanceDropdown:SetSelected(selectedInstanceKey, inst and inst.name)
end

-------------------------------------------------
-- Right column: detail panel for the selected boss
-------------------------------------------------
local detail = CreateFrame("Frame", nil, main)
detail:SetPoint("TOPLEFT", listPanel, "TOPRIGHT", 20, 0)
detail:SetPoint("BOTTOMRIGHT", -18, 46)

local detailTitle = T.FontString(detail, 15, "textBright", "")
detailTitle:SetPoint("TOPLEFT", 0, -2)

-- Per-boss "where does this boss's loadout + trigger come from" selector,
-- top-right of the detail panel (level with the boss title).
UI.loadoutSourceDropdown = CreateDropdown(detail, 210, function(value)
	if editingGlobal or not (selectedInstanceKey and selectedBossKey) then return end
	BossPrepProfiles:SetBossSource(selectedInstanceKey, selectedBossKey,
		(value ~= "__self") and value or nil)
	UI:RebuildBossList()
	UI:RefreshDetailPanel()
end)
UI.loadoutSourceDropdown:SetPoint("TOPRIGHT", detail, "TOPRIGHT", 0, -1)

local detailDivider = T.Divider(detail)
detailDivider:SetPoint("TOPLEFT", 0, -24)
detailDivider:SetPoint("TOPRIGHT", 0, -24)

--- Trigger section ----------------------------------------------------
local triggerHeader = T.SectionHeader(detail, "Trigger")
triggerHeader:SetPoint("TOPLEFT", 0, -38)

UI.triggerTypeDropdown = CreateDropdown(detail, 200, function(value)
	UI:OnTriggerTypeChanged(value)
end)
UI.triggerTypeDropdown:SetPoint("TOPLEFT", triggerHeader, "BOTTOMLEFT", 0, -6)
UI.triggerTypeDropdown:SetOptions({
	{ text = "When I target it", value = "TARGET" },
	{ text = "When I enter its zone", value = "ZONE" },
	{ text = "When another boss dies", value = "KILL" },
})

UI.killAfterDropdown = CreateDropdown(detail, 200, function(value)
	UI:SaveTrigger("KILL", value)
end)
UI.killAfterDropdown:SetPoint("LEFT", UI.triggerTypeDropdown, "RIGHT", 10, 0)

-- ZONE trigger: stamp the player's current sub-zone as a per-character
-- override, plus a button to reset back to the boss's data-file default.
UI.zoneSetBtn = T.Button(detail, "Set to my sub-zone", 150, 22)
UI.zoneSetBtn:SetPoint("LEFT", UI.triggerTypeDropdown, "RIGHT", 10, 0)
UI.zoneSetBtn:Hide()
UI.zoneSetBtn:SetScript("OnClick", function()
	if not (selectedInstanceKey and selectedBossKey) then return end
	local here = GetSubZoneText()
	if not here or here == "" then here = GetMinimapZoneText() end
	if not here or here == "" then here = GetZoneText() end
	if not here or here == "" then
		print("|cff33ff99Prepared|r your current spot has no zone name to save.")
		return
	end
	BossPrepProfiles:SetTriggerSubZone(selectedInstanceKey, selectedBossKey, here)
	print("|cff33ff99Prepared|r this boss now fires on sub-zone: '" .. here .. "'")
	UI:RebuildBossList()
	UI:RefreshDetailPanel()
end)

UI.zoneResetBtn = T.Button(detail, "Reset to default", 118, 22)
UI.zoneResetBtn:SetPoint("LEFT", UI.zoneSetBtn, "RIGHT", 6, 0)
UI.zoneResetBtn:Hide()
UI.zoneResetBtn:SetScript("OnClick", function()
	if not (selectedInstanceKey and selectedBossKey) then return end
	BossPrepProfiles:SetTriggerSubZone(selectedInstanceKey, selectedBossKey, nil)
	print("|cff33ff99Prepared|r cleared the sub-zone override; using the default.")
	UI:RebuildBossList()
	UI:RefreshDetailPanel()
end)

local zoneHint = T.FontString(detail, 11, "textDim", "")
zoneHint:SetPoint("TOPLEFT", UI.triggerTypeDropdown, "BOTTOMLEFT", 0, -6)
zoneHint:SetPoint("RIGHT", detail, "RIGHT", 0, 0)
zoneHint:SetJustifyH("LEFT")
zoneHint:SetWordWrap(false)
zoneHint:SetText("")

-- Read-only trigger line, shown in place of the dropdown when the selected
-- boss borrows another profile's setup (its trigger isn't editable here).
local triggerReadOnlyText = T.FontString(detail, 12, "text", "")
triggerReadOnlyText:SetPoint("TOPLEFT", triggerHeader, "BOTTOMLEFT", 0, -8)
triggerReadOnlyText:SetPoint("RIGHT", detail, "RIGHT", 0, 0)
triggerReadOnlyText:SetJustifyH("LEFT")
triggerReadOnlyText:SetWordWrap(false)
triggerReadOnlyText:Hide()

function UI:SaveTrigger(triggerType, killAfterBossKey)
	if not (selectedInstanceKey and selectedBossKey) then return end
	local existing = BossPrepProfiles:GetBossSetup(selectedInstanceKey, selectedBossKey)
	local keepSubZone = existing and existing.trigger and existing.trigger.subZone
	BossPrepProfiles:SetTrigger(selectedInstanceKey, selectedBossKey, {
		type = triggerType,
		killAfterBossKey = (triggerType == "KILL") and killAfterBossKey or nil,
		subZone = keepSubZone,
	})
	self:RebuildBossList()
end

-- Updates the ZONE buttons + hint line for the selected boss.
function UI:RefreshZoneControls(triggerType)
	local isZone = (triggerType == "ZONE")
	self.zoneSetBtn:SetShown(isZone)
	if not isZone then
		self.zoneResetBtn:Hide()
		zoneHint:SetText("")
		return
	end

	local override, defaults = BossPrepDetection:GetZoneStrings(selectedInstanceKey, selectedBossKey)
	self.zoneSetBtn:SetText(override and "Change my sub-zone" or "Set to my sub-zone")
	self.zoneResetBtn:SetShown(override ~= nil)

	if override then
		zoneHint:SetText("|cff33ff99Fires in:|r " .. override .. "  |cff808080(your override)|r")
	elseif defaults[1] then
		zoneHint:SetText("|cff33ff99Fires in:|r " .. table.concat(defaults, ", ") .. "  |cff808080(default)|r")
	else
		zoneHint:SetText("|cff808080No sub-zone yet - stand in the boss's room and click the button.|r")
	end
end

function UI:OnTriggerTypeChanged(triggerType)
	if triggerType == "KILL" then
		self.killAfterDropdown:Show()
		local setup = BossPrepProfiles:GetBossSetup(selectedInstanceKey, selectedBossKey)
		local current = setup and setup.trigger and setup.trigger.killAfterBossKey
		local def = BossPrepData:GetDefaultTrigger(selectedInstanceKey, selectedBossKey)
		local prevBoss = BossPrepData:GetPreviousBoss(selectedInstanceKey, selectedBossKey)
		local chosen = current
			or (def.type == "KILL" and def.killAfterBossKey)
			or (prevBoss and prevBoss.key)
		self:RefreshKillAfterDropdown(chosen)
		self:SaveTrigger("KILL", chosen)
	else
		self.killAfterDropdown:Hide()
		self:SaveTrigger(triggerType, nil)
	end
	self:RefreshZoneControls(triggerType)
end

function UI:RefreshKillAfterDropdown(selectedKey)
	local inst = BossPrepData:GetInstance(selectedInstanceKey)
	local options = {}
	if inst then
		for _, boss in ipairs(inst.bosses) do
			if boss.key ~= selectedBossKey then
				table.insert(options, { text = boss.name, value = boss.key })
			end
		end
	end
	self.killAfterDropdown:SetOptions(options)
	local boss = selectedKey and BossPrepData:GetBoss(selectedInstanceKey, selectedKey)
	self.killAfterDropdown:SetSelected(selectedKey, boss and boss.name)
end

--- Loadout section ---------------------------------------------------
-- One row: SPEC | GEAR SET | TRINKET 1 | TRINKET 2 | CLOAK
-- then TALENTS, then MAJOR GLYPHS.
local loadoutHeader = T.SectionHeader(detail, "Loadout")
loadoutHeader:SetPoint("TOPLEFT", 0, -102)

local LOADOUT_PITCH = 94
local function LoadoutSlot(headerText, xOffset, onClick)
	local hdr = T.FontString(detail, 10, "textDim", "")
	hdr:SetText(headerText)
	local slot = CreateIconSlot(detail)
	slot.label:SetWidth(LOADOUT_PITCH - 8)
	slot:SetPoint("TOPLEFT", loadoutHeader, "BOTTOMLEFT", xOffset, -20)
	hdr:SetPoint("BOTTOMLEFT", slot, "TOPLEFT", 0, 4)
	slot:SetScript("OnClick", onClick)
	return slot
end

local specSlot   = LoadoutSlot("SPEC",      0,                 function(_, b) UI:SlotClicked("spec", nil, b) end)
local gearSlot   = LoadoutSlot("GEAR SET",  LOADOUT_PITCH,     function(_, b) UI:SlotClicked("equipmentSet", nil, b) end)
local trinketSlots = {
	LoadoutSlot("TRINKET 1", LOADOUT_PITCH * 2, function(_, b) UI:SlotClicked("trinket", 1, b) end),
	LoadoutSlot("TRINKET 2", LOADOUT_PITCH * 3, function(_, b) UI:SlotClicked("trinket", 2, b) end),
}
local cloakSlot  = LoadoutSlot("CLOAK",     LOADOUT_PITCH * 4, function(_, b) UI:SlotClicked("cloak", nil, b) end)

local talentsLabel = T.FontString(detail, 10, "textDim", "")
talentsLabel:SetPoint("TOPLEFT", specSlot, "BOTTOMLEFT", 0, -18)
talentsLabel:SetText("TALENTS")

local talentSlots = {}
for tier = 1, 6 do
	local slot = CreateIconSlot(detail)
	slot.label:SetWidth(50)
	if tier == 1 then
		slot:SetPoint("TOPLEFT", talentsLabel, "BOTTOMLEFT", 0, -6)
	else
		slot:SetPoint("LEFT", talentSlots[tier - 1], "RIGHT", 16, 0)
	end
	slot:SetScript("OnClick", function(_, b) UI:SlotClicked("talent", tier, b) end)
	talentSlots[tier] = slot
end

local glyphsLabel = T.FontString(detail, 10, "textDim", "")
glyphsLabel:SetPoint("TOPLEFT", talentSlots[1], "BOTTOMLEFT", 0, -18)
glyphsLabel:SetText("MAJOR GLYPHS")

local glyphSlots = {}
for slotNum = 1, 3 do
	local slot = CreateIconSlot(detail)
	slot.label:SetWidth(150)
	if slotNum == 1 then
		slot:SetPoint("TOPLEFT", glyphsLabel, "BOTTOMLEFT", 0, -6)
	else
		slot:SetPoint("LEFT", glyphSlots[slotNum - 1], "RIGHT", 118, 0)
	end
	slot:SetScript("OnClick", function(_, b) UI:SlotClicked("glyph", slotNum, b) end)
	glyphSlots[slotNum] = slot
end

--- Per-boss note (below the glyphs, above the action buttons) ----------
-- Free text shown on the alert banner. Silent by default - check the box to
-- have it spoken by the TTS cue too (-> setup.noteAnnounceTTS).
local noteHeader = T.SectionHeader(detail, "Note")
noteHeader:SetPoint("TOPLEFT", glyphSlots[1], "BOTTOMLEFT", 0, -18)

local noteAnnounceCb = T.Checkbox(detail, "Announce in voice alert")
noteAnnounceCb:SetPoint("LEFT", noteHeader, "LEFT", 200, 0)
noteAnnounceCb:SetScript("OnClick", function(self)
	if editingGlobal or not (selectedInstanceKey and selectedBossKey) then return end
	BossPrepProfiles:SetBossNoteAnnounceTTS(selectedInstanceKey, selectedBossKey, self:GetChecked() and true or false)
end)

local noteBox = CreateFrame("EditBox", nil, detail)
noteBox:SetMultiLine(true)
noteBox:SetAutoFocus(false)
noteBox:SetFontObject(ChatFontNormal)
noteBox:SetTextColor(u(T.color.text))
noteBox:SetJustifyH("LEFT")
noteBox:SetTextInsets(7, 7, 6, 6)
noteBox:SetMaxLetters(400)
noteBox:SetPoint("TOPLEFT", noteHeader, "BOTTOMLEFT", 0, -6)
noteBox:SetPoint("RIGHT", detail, "RIGHT", -2, 0)
noteBox:SetHeight(42)
T.Panel(noteBox, "insetBG", "border")
noteBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
noteBox:SetScript("OnEnter", function(self) T.SetBorderColor(self, "borderStrong") end)
noteBox:SetScript("OnLeave", function(self) T.SetBorderColor(self, "border") end)

local settingNote = false -- guards the programmatic SetText in RefreshNoteSection
local function saveNote()
	if settingNote or editingGlobal or not (selectedInstanceKey and selectedBossKey) then return end
	BossPrepProfiles:SetBossNote(selectedInstanceKey, selectedBossKey, noteBox:GetText())
end
noteBox:SetScript("OnTextChanged", saveNote)
noteBox:SetScript("OnEditFocusLost", function()
	saveNote()
	UI:RebuildBossList() -- refresh the boss-list dim state now that we're done
end)

function UI:SetNoteSectionShown(shown)
	noteHeader:SetShown(shown)
	noteAnnounceCb:SetShown(shown)
	noteBox:SetShown(shown)
	if not shown and noteBox:HasFocus() then noteBox:ClearFocus() end
end

function UI:RefreshNoteSection()
	local setup = selectedBossKey
		and BossPrepProfiles:GetBossSetup(selectedInstanceKey, selectedBossKey)
	if not noteBox:HasFocus() then
		settingNote = true
		noteBox:SetText((setup and setup.note) or "")
		settingNote = false
	end
	noteAnnounceCb:SetChecked(setup and setup.noteAnnounceTTS and true or false)
end

-- Commit any half-typed note now (called before a check / boss switch).
function UI:CommitNote()
	if noteBox:HasFocus() then noteBox:ClearFocus() else saveNote() end
end

local savedAtText = T.FontString(detail, 11, "textDim", "")
savedAtText:SetPoint("TOPLEFT", noteBox, "BOTTOMLEFT", 0, -8)
savedAtText:SetPoint("RIGHT", detail, "RIGHT", 0, 0)
savedAtText:SetJustifyH("LEFT")

--- Action buttons (one row below the loadout) --------------------------
local checkNowBtn = T.Button(detail, "Check Now", 92, 22)
checkNowBtn:SetPoint("TOPLEFT", savedAtText, "BOTTOMLEFT", 0, -10)
checkNowBtn:SetScript("OnClick", function()
	if not (selectedInstanceKey and selectedBossKey) then return end
	UI:CommitNote() -- in case a note is half-typed
	BossPrepDetection:SetCurrentBoss(selectedInstanceKey, selectedBossKey)
	BossPrepDetection:CheckNow(true)
end)

local captureAllBtn = T.Button(detail, "Capture Now", 108, 22)
captureAllBtn:SetPoint("LEFT", checkNowBtn, "RIGHT", 8, 0)
captureAllBtn:SetScript("OnClick", function()
	if editingGlobal then
		BossPrepProfiles:CaptureCurrentAsGlobal()
		print("|cff33ff99Prepared|r captured your current loadout as the Global Default set.")
	else
		if not (selectedInstanceKey and selectedBossKey) then return end
		BossPrepProfiles:CaptureCurrentAsBossOverrides(selectedInstanceKey, selectedBossKey)
		print("|cff33ff99Prepared|r captured this boss's differences from the Global Default set.")
	end
	UI:RebuildBossList()
	UI:RefreshDetailPanel()
end)

local deleteBtn = T.Button(detail, "Delete", 74, 22)
deleteBtn:SetPoint("LEFT", captureAllBtn, "RIGHT", 8, 0)
deleteBtn:SetScript("OnClick", function()
	if editingGlobal then
		BossPrepProfiles:DeleteGlobalSetup()
	else
		if not (selectedInstanceKey and selectedBossKey) then return end
		BossPrepProfiles:DeleteBossSetup(selectedInstanceKey, selectedBossKey)
	end
	UI:RebuildBossList()
	UI:RefreshDetailPanel()
end)

-- Copy this boss's set (or, in Global mode, the Global Default set) from
-- another profile into the active one, as an independent, editable copy.
local copyFromDD = CreateDropdown(detail, 116, function(value)
	if value then UI:CopyLoadoutFrom(value) end
end)
copyFromDD:SetPoint("LEFT", deleteBtn, "RIGHT", 8, 0)
copyFromDD:Hide()

-- Shown only when the selected boss borrows another profile's setup: jump to
-- that profile (keeping this boss selected) to edit it.
local editSourceBtn = T.Button(detail, "Edit source profile", 220, 22)
editSourceBtn:SetPoint("TOPLEFT", checkNowBtn, "TOPLEFT", 0, 0)
editSourceBtn:Hide()
editSourceBtn:SetScript("OnClick", function()
	if not (selectedInstanceKey and selectedBossKey) then return end
	local srcId = BossPrepProfiles:GetBossSource(selectedInstanceKey, selectedBossKey)
	if not srcId then return end
	BossPrepProfiles:SetActiveProfile(nil, srcId)
	editingGlobal = false
	UI:RefreshProfileDropdown()
	UI:RebuildBossList()
	UI:RefreshDetailPanel()
end)

-- Shows/hides the whole Trigger section (hidden while editing the Global set).
function UI:SetTriggerSectionShown(shown)
	triggerHeader:SetShown(shown)
	self.triggerTypeDropdown:SetShown(shown)
	zoneHint:SetShown(shown)
	triggerReadOnlyText:Hide()
	if not shown then
		self.killAfterDropdown:Hide()
		self.zoneSetBtn:Hide()
		self.zoneResetBtn:Hide()
	end
end

-- The trigger rendered as a plain, non-editable line - used when the boss
-- borrows another profile's setup, so its trigger lives (and is edited) there.
function UI:TriggerSummary(trigger)
	local t = trigger and trigger.type
	if t == "ZONE" then
		local override, defaults = BossPrepDetection:GetZoneStrings(selectedInstanceKey, selectedBossKey)
		local where = override or (defaults[1] and table.concat(defaults, ", "))
		return "When I enter its zone" .. (where and ("   |cff808080" .. where .. "|r") or "")
	elseif t == "KILL" then
		local bk = trigger.killAfterBossKey
		local b = bk and BossPrepData:GetBoss(selectedInstanceKey, bk)
		return "After " .. ((b and b.name) or bk or "another boss") .. " dies"
	end
	return "When I target it"
end

function UI:ShowReadOnlyTrigger()
	triggerHeader:Show()
	self.triggerTypeDropdown:Hide()
	self.killAfterDropdown:Hide()
	self.zoneSetBtn:Hide()
	self.zoneResetBtn:Hide()
	zoneHint:Hide()
	local trigger = BossPrepDetection:GetTrigger(selectedInstanceKey, selectedBossKey)
	triggerReadOnlyText:SetText(self:TriggerSummary(trigger))
	triggerReadOnlyText:Show()
end

function UI:SetGlobalModeButtons(isGlobal)
	checkNowBtn:SetShown(not isGlobal)
	-- Check Now is the leftmost button; when it's hidden (Global mode) the row
	-- would start with a gap, so re-anchor Capture Now to the row origin.
	captureAllBtn:ClearAllPoints()
	captureAllBtn:Show()
	if isGlobal then
		captureAllBtn:SetPoint("TOPLEFT", savedAtText, "BOTTOMLEFT", 0, -10)
	else
		captureAllBtn:SetPoint("LEFT", checkNowBtn, "RIGHT", 8, 0)
	end
	-- Delete sits after Capture Now in both modes; the "From: X" branch below
	-- hides Capture Now and re-anchors this next to Check Now instead.
	deleteBtn:ClearAllPoints()
	deleteBtn:SetPoint("LEFT", captureAllBtn, "RIGHT", 8, 0)
	deleteBtn:SetText(isGlobal and "Clear" or "Delete")
end

-- Populates + shows the "Copy from" dropdown (lists the other profiles).
-- `shown` is false in states where copying doesn't apply (no boss selected, or
-- a borrowed setup that's edited in its own profile).
function UI:RefreshCopyFrom(shown)
	local profiles = BossPrepProfiles:GetProfiles()
	if not shown or #profiles < 2 then
		copyFromDD:Hide()
		return
	end
	local activeId = BossPrepProfiles:GetActiveProfileId()
	local opts = {}
	for _, p in ipairs(profiles) do
		if p.id ~= activeId then
			opts[#opts + 1] = { text = "From: " .. p.name, value = p.id }
		end
	end
	copyFromDD:SetOptions(opts)
	copyFromDD:SetSelected(nil, "Copy from")
	copyFromDD:Show()
end

function UI:CopyLoadoutFrom(fromProfileId)
	copyFromDD:SetSelected(nil, "Copy from")
	local nm = fromProfileId
	for _, p in ipairs(BossPrepProfiles:GetProfiles()) do
		if p.id == fromProfileId then nm = p.name end
	end
	if editingGlobal then
		BossPrepProfiles:CopyGlobalSetupFrom(fromProfileId)
		print("|cff33ff99Prepared|r copied the Global Default set from '" .. nm .. "'.")
	elseif selectedInstanceKey and selectedBossKey then
		local _, copied = BossPrepProfiles:CopyBossSetupFrom(
			selectedInstanceKey, selectedBossKey, fromProfileId)
		if copied then
			print("|cff33ff99Prepared|r copied this boss's set from '" .. nm .. "'.")
		else
			print("|cff33ff99Prepared|r '" .. nm .. "' has no custom set for this boss - nothing copied.")
		end
	else
		return
	end
	UI:RebuildBossList()
	UI:RefreshDetailPanel()
end

-------------------------------------------------
-- Loadout slot helpers (shared by the detail panel + the pickers)
-------------------------------------------------
-- src = "boss" | "global" | nil  ->  IconSlot:SetContent opts
-- fromName: when the inherited base is another profile ("From: X"), its display
-- name - inherited slots then get that profile's initial as a corner tag.
local function markOpts(src, fromName)
	if src == "global" then
		if fromName then
			return { faded = true, mark = "profile", tag = fromName:sub(1, 1):upper() }
		end
		return { faded = true, mark = "global" }
	end
	if src == "boss" then return { mark = "override" } end
	return nil
end

local function slotTip(src, valueName, emptyHint, fromName)
	local prefix = valueName and (valueName .. "  -  ") or ""
	if src == "global" then
		local base = fromName and ("from the '" .. fromName .. "' profile")
			or "from Global Default set"
		return prefix .. base .. " (left-click to override for this boss)"
	elseif src == "boss" then
		return prefix .. "per-boss override (right-click to revert)"
	end
	return valueName or emptyHint
end

-- Context for whichever slot a picker is about to edit.
function UI:LoadoutCtx()
	if editingGlobal then
		return { mode = "global", global = BossPrepProfiles:GetGlobalSetup() }
	end
	local effective, source, redirectName, redirectBase =
		BossPrepProfiles:ResolveBossLoadout(selectedInstanceKey, selectedBossKey)
	return {
		mode = "boss",
		ik = selectedInstanceKey, bk = selectedBossKey,
		effective = effective, source = source,
		-- The layer a per-boss slot falls back to when it has no override:
		-- the "From: X" base if this boss borrows one, else the Global Default.
		global = redirectBase or BossPrepProfiles:GetGlobalSetup(),
		baseName = redirectName,
	}
end

-- Does the global default hold a real value for this field?
local function globalHasValue(g, kind, idx)
	if not g then return false end
	if kind == "equipmentSet" then return g.equipmentSet ~= nil end
	if kind == "spec" then return g.specID ~= nil end
	if kind == "cloak" then return type(g.cloak) == "table" and g.cloak.itemID ~= nil end
	if kind == "talent" then return g.talents and g.talents[idx] ~= nil end
	if kind == "glyph" then return g.glyphs and type(g.glyphs[idx]) == "table" end
	if kind == "trinket" then return g.trinkets and type(g.trinkets[idx]) == "table" and g.trinkets[idx].itemID ~= nil end
	return false
end

-- Current picker state for a slot: "inherit" | "none" | <value>
local function slotState(ctx, kind, idx)
	if ctx.mode == "global" then
		local g = ctx.global
		if not g then return "none" end
		local v
		if kind == "equipmentSet" then v = g.equipmentSet
		elseif kind == "spec" then v = g.specID
		elseif kind == "cloak" then local x = g.cloak; v = (type(x) == "table" and x.itemID) and x or nil
		elseif kind == "talent" then v = g.talents and g.talents[idx]
		elseif kind == "glyph" then local x = g.glyphs and g.glyphs[idx]; v = type(x) == "table" and x or nil
		elseif kind == "trinket" then local x = g.trinkets and g.trinkets[idx]; v = (type(x) == "table" and x.itemID) and x or nil
		end
		if v == nil then return "none" end
		return v
	end
	local s, val
	if kind == "equipmentSet" then s, val = ctx.source.equipmentSet, ctx.effective.equipmentSet
	elseif kind == "spec" then s, val = ctx.source.spec, ctx.effective.specID
	elseif kind == "cloak" then s, val = ctx.source.cloak, ctx.effective.cloak
	elseif kind == "talent" then s, val = ctx.source.talents[idx], ctx.effective.talents[idx]
	elseif kind == "glyph" then s, val = ctx.source.glyphs[idx], ctx.effective.glyphs[idx]
	elseif kind == "trinket" then s, val = ctx.source.trinkets[idx], ctx.effective.trinkets[idx]
	end
	if s == "boss" then
		if val == nil or val == false then return "none" end -- false = explicitly emptied
		return val
	end
	return "inherit"
end

-- Right-click on a slot: clear its per-boss override (or its global value).
function UI:SlotClicked(kind, idx, button)
	if button == "RightButton" then
		if editingGlobal then
			UI:ClearGlobalField(kind, idx)
		elseif selectedInstanceKey and selectedBossKey then
			BossPrepProfiles:RevertBossField(selectedInstanceKey, selectedBossKey, kind, idx)
		else
			return
		end
		UI:RebuildBossList()
		UI:RefreshDetailPanel()
		return
	end
	if kind == "equipmentSet" then UI:OpenGearPicker()
	elseif kind == "spec" then UI:OpenSpecPicker()
	elseif kind == "cloak" then UI:OpenCloakPicker()
	elseif kind == "trinket" then UI:OpenTrinketPicker(idx)
	elseif kind == "talent" then UI:OpenTalentPicker(idx)
	elseif kind == "glyph" then UI:OpenGlyphPicker(idx)
	end
end

function UI:ClearGlobalField(kind, idx)
	local g = BossPrepProfiles:GetGlobalSetup()
	if not g then return end
	if kind == "equipmentSet" then g.equipmentSet = nil
	elseif kind == "spec" then g.specID, g.specName = nil, nil
	elseif kind == "cloak" then g.cloak = nil
	elseif kind == "talent" then
		if g.talents then g.talents[idx] = nil end
		if g.talentNames then g.talentNames[idx] = nil end
	elseif kind == "glyph" then if g.glyphs then g.glyphs[idx] = nil end
	elseif kind == "trinket" then if g.trinkets then g.trinkets[idx] = nil end
	end
end

-- Picker "(none)" row was chosen for this slot.
function UI:PickLoadoutNone(kind, idx, ctx)
	if ctx.mode == "global" then
		if kind == "equipmentSet" then BossPrepProfiles:SetGlobalEquipmentSetChoice(nil)
		elseif kind == "spec" then BossPrepProfiles:SetGlobalSpecChoice(nil, nil)
		elseif kind == "cloak" then BossPrepProfiles:SetGlobalCloakChoice(nil)
		elseif kind == "talent" then UI:ClearGlobalField("talent", idx)
		elseif kind == "glyph" then BossPrepProfiles:SetGlobalGlyphSlotChoice(idx, nil)
		elseif kind == "trinket" then BossPrepProfiles:SetGlobalTrinketChoice(idx, nil)
		end
		return
	end
	-- Talents/glyphs: "(none)" is an active instruction - unlearn what's there,
	-- don't relearn - so always record it explicitly, even with nothing to
	-- inherit. (Right-click the slot to drop back to inheriting.) Other fields
	-- only need the explicit marker when there's an inherited value to suppress.
	if kind == "talent" or kind == "glyph" or globalHasValue(ctx.global, kind, idx) then
		BossPrepProfiles:OverrideBossFieldNone(ctx.ik, ctx.bk, kind, idx)
	else
		BossPrepProfiles:RevertBossField(ctx.ik, ctx.bk, kind, idx)
	end
end

-- Fills all 12 loadout slots. source == nil => plain (global-edit mode).
-- inheritedName: display name of the profile an inherited slot falls back to
-- when this boss borrows a base with "From: X" (nil = the Global Default).
function UI:FillLoadoutSlots(effective, source, inheritedName)
	local S = source or {}
	local baseMarkOpts, baseSlotTip = markOpts, slotTip
	local function markOpts(src) return baseMarkOpts(src, inheritedName) end
	local function slotTip(src, v, h) return baseSlotTip(src, v, h, inheritedName) end

	local gearIcon
	if effective.equipmentSet then
		for _, s in ipairs(BossPrepCompat.GetEquipmentSets()) do
			if s.name == effective.equipmentSet then gearIcon = s.icon break end
		end
	end
	gearSlot:SetContent(gearIcon, effective.equipmentSet or "(none)",
		slotTip(S.equipmentSet, effective.equipmentSet, "Click to pick a gear set"),
		markOpts(S.equipmentSet))

	local specIcon
	if effective.specID then
		for _, s in ipairs(BossPrepCompat.GetAvailableSpecs()) do
			if s.id == effective.specID then specIcon = s.icon break end
		end
	end
	specSlot:SetContent(specIcon, effective.specName or "(none)",
		slotTip(S.spec, effective.specName, "Click to pick a spec"), markOpts(S.spec))

	do
		local c = effective.cloak
		if c and c.itemID then
			local name, icon = BossPrepCompat.GetItemDisplay(c.itemID)
			cloakSlot:SetContent(icon or c.icon, name or c.name or ("Item #" .. c.itemID),
				slotTip(S.cloak, name or c.name, "Click to pick a cloak"), markOpts(S.cloak))
		else
			cloakSlot:SetContent(nil, "(none)",
				slotTip(S.cloak, nil, "Click to pick a cloak"), markOpts(S.cloak))
		end
	end

	for i = 1, 2 do
		local t = effective.trinkets[i]
		if t and t.itemID then
			local name, icon = BossPrepCompat.GetItemDisplay(t.itemID)
			trinketSlots[i]:SetContent(icon or t.icon, name or t.name or ("Item #" .. t.itemID),
				slotTip(S.trinkets and S.trinkets[i], name or t.name, "Click to pick a trinket"),
				markOpts(S.trinkets and S.trinkets[i]))
		else
			trinketSlots[i]:SetContent(nil, "(none)",
				slotTip(S.trinkets and S.trinkets[i], nil, "Click to pick a trinket"),
				markOpts(S.trinkets and S.trinkets[i]))
		end
	end

	for tier = 1, 6 do
		local col = effective.talents[tier]
		local name = effective.talentNames and effective.talentNames[tier]
		local icon
		if col then
			local choice = BossPrepCompat.GetTalentChoice(tier, col, effective.specGroup)
			if choice then icon = choice.icon end
		elseif col == false then
			name = "no talent (unlearn)"
		end
		talentSlots[tier]:SetContent(icon, "T" .. tier,
			slotTip(S.talents and S.talents[tier], name, "Click to pick this tier's talent"),
			markOpts(S.talents and S.talents[tier]))
	end

	for slotNum = 1, 3 do
		local gl = effective.glyphs[slotNum]
		if type(gl) == "table" then
			local name, icon = BossPrepCompat.GetGlyphDisplay(gl)
			glyphSlots[slotNum]:SetContent(icon or gl.icon, name or gl.name,
				slotTip(S.glyphs and S.glyphs[slotNum], name or gl.name, "Click to pick a glyph"),
				markOpts(S.glyphs and S.glyphs[slotNum]))
		else
			glyphSlots[slotNum]:SetContent(nil, gl == false and "(none)" or "(empty)",
				slotTip(S.glyphs and S.glyphs[slotNum],
					gl == false and "no glyph (keep this socket clear)" or nil,
					"Click to pick a glyph"),
				markOpts(S.glyphs and S.glyphs[slotNum]))
		end
	end
end

-- The per-boss "Source" dropdown (top-right of the detail panel).
function UI:RefreshLoadoutSourceDropdown()
	local activeId = BossPrepProfiles:GetActiveProfileId()
	local profiles = BossPrepProfiles:GetProfiles()

	-- Only meaningful once there's another profile to borrow from.
	if editingGlobal or not selectedBossKey or #profiles < 2 then
		self.loadoutSourceDropdown:Hide()
		return
	end
	self.loadoutSourceDropdown:Show()
	local options, activeName = {}, "this profile"
	for _, p in ipairs(profiles) do
		if p.id == activeId then
			activeName = p.name
			table.insert(options, { text = "This profile (" .. p.name .. ")", value = "__self" })
		else
			table.insert(options, { text = "From: " .. p.name, value = p.id })
		end
	end
	self.loadoutSourceDropdown:SetOptions(options)

	local src = BossPrepProfiles:GetBossSource(selectedInstanceKey, selectedBossKey)
	if src and src ~= activeId then
		local nm = src
		for _, p in ipairs(profiles) do if p.id == src then nm = p.name end end
		self.loadoutSourceDropdown:SetSelected(src, "From: " .. nm)
	else
		self.loadoutSourceDropdown:SetSelected("__self", "This profile (" .. activeName .. ")")
	end
end

-------------------------------------------------
-- Pickers
--
-- All six loadout pickers share OpenLoadoutPicker: it prepends a "Use Global
-- Default" row (per-boss editing only, when the global set has a value here)
-- and a "(none)" row, then the real options, wiring each to the right global
-- vs per-boss setter.
-------------------------------------------------
function UI:OpenLoadoutPicker(kind, idx, opts)
	local ctx = self:LoadoutCtx()
	if ctx.mode == "boss" and not (ctx.ik and ctx.bk) then return end

	local state = slotState(ctx, kind, idx)
	local matches = opts.matches or function(s, v) return s == v end
	local items = {}

	if ctx.mode == "boss" and globalHasValue(ctx.global, kind, idx) then
		local inheritLabel = ctx.baseName
			and ("Use '" .. ctx.baseName .. "' profile")
			or "Use Global Default"
		table.insert(items, {
			text = "|cff33ff99" .. inheritLabel .. "|r  (" .. tostring(opts.globalName(ctx.global)) .. ")",
			selected = (state == "inherit"),
			onClick = function()
				BossPrepProfiles:RevertBossField(ctx.ik, ctx.bk, kind, idx)
				UI:RebuildBossList(); UI:RefreshDetailPanel()
			end,
		})
	end

	table.insert(items, {
		text = opts.noneLabel or "|cff808080(none)|r",
		selected = (state == "none"),
		onClick = function()
			UI:PickLoadoutNone(kind, idx, ctx)
			UI:RebuildBossList(); UI:RefreshDetailPanel()
		end,
	})

	for _, it in ipairs(opts.options(ctx) or {}) do
		table.insert(items, {
			icon = it.icon,
			text = it.text,
			selected = (state ~= "inherit" and state ~= "none" and matches(state, it.value)),
			onClick = function()
				opts.apply(ctx, it.value, it)
				UI:RebuildBossList(); UI:RefreshDetailPanel()
			end,
		})
	end

	BossPrepPicker:Open({
		title = opts.title,
		items = items,
		emptyText = opts.emptyText,
		saveCurrentLabel = opts.saveCurrentLabel,
		onSaveCurrent = opts.onSaveCurrent and function()
			opts.onSaveCurrent(ctx)
			UI:RebuildBossList(); UI:RefreshDetailPanel()
		end or nil,
	})
end

function UI:OpenGearPicker()
	self:OpenLoadoutPicker("equipmentSet", nil, {
		title = editingGlobal and "Global Gear Set" or "Choose a Gear Set",
		noneLabel = "|cff808080(none - no gear set here)|r",
		emptyText = "|cff808080No saved Equipment Manager sets found.|r",
		globalName = function(g) return g.equipmentSet end,
		options = function()
			local t = {}
			for _, s in ipairs(BossPrepCompat.GetEquipmentSets()) do
				t[#t + 1] = { icon = s.icon, text = s.name, value = s.name }
			end
			return t
		end,
		apply = function(ctx, name)
			if ctx.mode == "global" then
				BossPrepProfiles:SetGlobalEquipmentSetChoice(name)
			else
				BossPrepProfiles:SetEquipmentSetChoice(ctx.ik, ctx.bk, name)
			end
		end,
		saveCurrentLabel = "Save Current Gear as New Set...",
		onSaveCurrent = function() showPopup("BOSSPREP_NEW_GEAR_SET") end,
	})
end

function UI:OpenSpecPicker()
	self:OpenLoadoutPicker("spec", nil, {
		title = editingGlobal and "Global Spec" or "Choose a Spec",
		noneLabel = "|cff808080(none - don't track spec)|r",
		emptyText = "|cff808080Couldn't read specializations on this client.|r",
		globalName = function(g) return g.specName or ("spec " .. tostring(g.specID)) end,
		options = function()
			local t = {}
			for _, s in ipairs(BossPrepCompat.GetAvailableSpecs()) do
				t[#t + 1] = { icon = s.icon, text = s.name, value = s.id, name = s.name }
			end
			return t
		end,
		apply = function(ctx, id, it)
			if ctx.mode == "global" then
				BossPrepProfiles:SetGlobalSpecChoice(id, it.name)
			else
				BossPrepProfiles:SetSpecChoice(ctx.ik, ctx.bk, id, it.name)
			end
		end,
		saveCurrentLabel = "Save Current Spec",
		onSaveCurrent = function(ctx)
			local _, specName, specID = BossPrepCompat.GetCurrentSpec()
			if ctx.mode == "global" then
				BossPrepProfiles:SetGlobalSpecChoice(specID, specName)
			else
				BossPrepProfiles:SetSpecChoice(ctx.ik, ctx.bk, specID, specName)
			end
		end,
	})
end

function UI:OpenTrinketPicker(uiSlot)
	self:OpenLoadoutPicker("trinket", uiSlot, {
		title = (editingGlobal and "Global Trinket Slot " or "Trinket Slot ") .. uiSlot,
		noneLabel = "|cff808080(none - don't track this slot)|r",
		emptyText = "|cff808080No trinkets found in your bags or equipped.|r",
		matches = function(s, v) return type(s) == "table" and s.itemID == v end,
		globalName = function(g)
			local x = g.trinkets and g.trinkets[uiSlot]
			return x and x.name or "?"
		end,
		options = function()
			local t = {}
			for _, tr in ipairs(BossPrepCompat.GetUsableTrinkets()) do
				t[#t + 1] = {
					icon = tr.icon, text = tr.name, value = tr.itemID,
					choice = { itemID = tr.itemID, name = tr.name, icon = tr.icon },
				}
			end
			return t
		end,
		apply = function(ctx, _, it)
			if ctx.mode == "global" then
				BossPrepProfiles:SetGlobalTrinketChoice(uiSlot, it.choice)
			else
				BossPrepProfiles:SetTrinketChoice(ctx.ik, ctx.bk, uiSlot, it.choice)
			end
		end,
		saveCurrentLabel = "Save Currently Equipped",
		onSaveCurrent = function(ctx)
			local live = BossPrepCompat.GetCurrentTrinket(uiSlot)
			local choice = live and { itemID = live.itemID, name = live.name, icon = live.icon } or nil
			if not choice then
				print("|cff33ff99Prepared|r trinket slot " .. uiSlot .. " is currently empty.")
			end
			if ctx.mode == "global" then
				BossPrepProfiles:SetGlobalTrinketChoice(uiSlot, choice)
			else
				BossPrepProfiles:SetTrinketChoice(ctx.ik, ctx.bk, uiSlot, choice)
			end
		end,
	})
end

function UI:OpenCloakPicker()
	self:OpenLoadoutPicker("cloak", nil, {
		title = editingGlobal and "Global Cloak" or "Choose a Cloak",
		noneLabel = "|cff808080(none - don't track the cloak)|r",
		emptyText = "|cff808080No cloaks found in your bags or equipped.|r",
		matches = function(s, v) return type(s) == "table" and s.itemID == v end,
		globalName = function(g) return type(g.cloak) == "table" and g.cloak.name or "?" end,
		options = function()
			local t = {}
			for _, cl in ipairs(BossPrepCompat.GetUsableCloaks()) do
				t[#t + 1] = {
					icon = cl.icon, text = cl.name, value = cl.itemID,
					choice = { itemID = cl.itemID, name = cl.name, icon = cl.icon },
				}
			end
			return t
		end,
		apply = function(ctx, _, it)
			if ctx.mode == "global" then
				BossPrepProfiles:SetGlobalCloakChoice(it.choice)
			else
				BossPrepProfiles:SetCloakChoice(ctx.ik, ctx.bk, it.choice)
			end
		end,
		saveCurrentLabel = "Save Currently Equipped",
		onSaveCurrent = function(ctx)
			local live = BossPrepCompat.GetCurrentCloak()
			local choice = live and { itemID = live.itemID, name = live.name, icon = live.icon } or nil
			if not choice then print("|cff33ff99Prepared|r you have no cloak equipped right now.") end
			if ctx.mode == "global" then
				BossPrepProfiles:SetGlobalCloakChoice(choice)
			else
				BossPrepProfiles:SetCloakChoice(ctx.ik, ctx.bk, choice)
			end
		end,
	})
end

function UI:OpenTalentPicker(tier)
	local specGroup = BossPrepCompat.GetActiveSpecGroup()
	self:OpenLoadoutPicker("talent", tier, {
		title = (editingGlobal and "Global Tier " or "Tier ") .. tier .. " Talent",
		noneLabel = editingGlobal and "|cff808080(none - don't track this tier)|r"
			or "|cff808080(none - unlearn this tier, no replacement)|r",
		emptyText = "|cff808080Couldn't read this talent tier.|r",
		globalName = function(g)
			return (g.talentNames and g.talentNames[tier])
				or ("column " .. tostring(g.talents and g.talents[tier]))
		end,
		options = function()
			local t = {}
			for column = 1, 3 do
				local choice = BossPrepCompat.GetTalentChoice(tier, column, specGroup)
				if choice and choice.name then
					t[#t + 1] = { icon = choice.icon, text = choice.name, value = column, name = choice.name }
				end
			end
			return t
		end,
		apply = function(ctx, column, it)
			if ctx.mode == "global" then
				BossPrepProfiles:SetGlobalTalentTierChoice(tier, column, it.name)
			else
				BossPrepProfiles:SetTalentTierChoice(ctx.ik, ctx.bk, tier, column, it.name)
			end
		end,
		saveCurrentLabel = "Save Current Selection",
		onSaveCurrent = function(ctx)
			local current, names = BossPrepCompat.GetCurrentTalents()
			local column = current[tier]
			if not column then
				print("|cff33ff99Prepared|r you don't have a talent chosen in tier " .. tier .. " right now.")
				return
			end
			if ctx.mode == "global" then
				BossPrepProfiles:SetGlobalTalentTierChoice(tier, column, names[tier])
			else
				BossPrepProfiles:SetTalentTierChoice(ctx.ik, ctx.bk, tier, column, names[tier])
			end
		end,
	})
end

function UI:OpenGlyphPicker(uiSlot)
	self:OpenLoadoutPicker("glyph", uiSlot, {
		title = (editingGlobal and "Global Major Glyph Slot " or "Major Glyph Slot ") .. uiSlot,
		noneLabel = editingGlobal and "|cff808080(none - leave this socket empty)|r"
			or "|cff808080(none - unlearn any glyph here, no replacement)|r",
		emptyText = "|cff808080No known major glyphs found for your class.|r",
		matches = function(s, v) return type(s) == "table" and BossPrepCompat.GlyphChoicesMatch(s, v) end,
		globalName = function(g)
			local x = g.glyphs and g.glyphs[uiSlot]
			return (type(x) == "table" and x.name) or "?"
		end,
		options = function()
			local t = {}
			for _, gg in ipairs(BossPrepCompat.GetKnownMajorGlyphs()) do
				t[#t + 1] = {
					icon = gg.icon, text = gg.name, value = gg,
					choice = { glyphID = gg.glyphID, spellID = gg.spellID, name = gg.name, icon = gg.icon },
				}
			end
			return t
		end,
		apply = function(ctx, _, it)
			if ctx.mode == "global" then
				BossPrepProfiles:SetGlobalGlyphSlotChoice(uiSlot, it.choice)
			else
				BossPrepProfiles:SetGlyphSlotChoice(ctx.ik, ctx.bk, uiSlot, it.choice)
			end
		end,
		saveCurrentLabel = "Save Currently Socketed Glyph",
		onSaveCurrent = function(ctx)
			local live = BossPrepCompat.GetCurrentMajorGlyphs()[uiSlot]
			local choice = live and
				{ glyphID = live.glyphID, spellID = live.spellID, name = live.name, icon = live.icon } or nil
			if ctx.mode == "global" then
				BossPrepProfiles:SetGlobalGlyphSlotChoice(uiSlot, choice)
			elseif choice then
				BossPrepProfiles:SetGlyphSlotChoice(ctx.ik, ctx.bk, uiSlot, choice)
			else
				print("|cff33ff99Prepared|r that major glyph socket is currently empty.")
				BossPrepProfiles:SetGlyphSlotChoice(ctx.ik, ctx.bk, uiSlot, false)
			end
		end,
	})
end

-------------------------------------------------
-- Detail panel refresh
-------------------------------------------------
function UI:RefreshDetailPanel()
	if editingGlobal then
		return self:RefreshGlobalPanel()
	end

	self:SetTriggerSectionShown(true)
	self:SetGlobalModeButtons(false)
	self:RefreshLoadoutSourceDropdown()

	if not selectedBossKey then
		detailTitle:SetText("Select a boss on the left")
		gearSlot:SetContent(nil, "", nil)
		specSlot:SetContent(nil, "", nil)
		cloakSlot:SetContent(nil, "", nil)
		for i = 1, 2 do trinketSlots[i]:SetContent(nil, "", nil) end
		for i = 1, 6 do talentSlots[i]:SetContent(nil, "T" .. i, nil) end
		for i = 1, 3 do glyphSlots[i]:SetContent(nil, "", nil) end
		savedAtText:SetText("")
		self.triggerTypeDropdown:SetSelected(nil, "-")
		self.killAfterDropdown:Hide()
		self.zoneSetBtn:Hide()
		self.zoneResetBtn:Hide()
		zoneHint:SetText("")
		editSourceBtn:Hide()
		checkNowBtn:Hide(); captureAllBtn:Hide(); deleteBtn:Hide()
		self:RefreshCopyFrom(false)
		self:SetNoteSectionShown(false)
		return
	end

	self:SetNoteSectionShown(true)
	self:RefreshNoteSection()

	local boss = BossPrepData:GetBoss(selectedInstanceKey, selectedBossKey)
	detailTitle:SetText(boss and boss.name or selectedBossKey)

	local effective, source, redirectName =
		BossPrepProfiles:ResolveBossLoadout(selectedInstanceKey, selectedBossKey)

	-- This boss draws its base loadout + trigger from another profile ("From:
	-- X"). The trigger is read-only here (edit it in X); the loadout slots stay
	-- editable and layer on top of X's setup, same as they would the Global
	-- Default. Faded slots follow X; marked slots override it for this profile.
	if redirectName then
		self:ShowReadOnlyTrigger()
		self:FillLoadoutSlots(effective, source, redirectName)
		-- Row: Check + Reset on the left, "Edit 'X' profile" pinned right.
		-- Capture Now doesn't apply (the base lives in X, not here).
		checkNowBtn:Show(); captureAllBtn:Hide(); deleteBtn:Show()
		deleteBtn:SetText("Reset")
		deleteBtn:ClearAllPoints()
		deleteBtn:SetPoint("LEFT", checkNowBtn, "RIGHT", 8, 0)
		self:RefreshCopyFrom(false)
		editSourceBtn:Show()
		editSourceBtn:SetText("Edit '" .. redirectName .. "' profile")
		editSourceBtn:ClearAllPoints()
		editSourceBtn:SetPoint("TOPRIGHT", savedAtText, "BOTTOMRIGHT", 0, -10)
		local setup = BossPrepProfiles:GetBossSetup(selectedInstanceKey, selectedBossKey)
		if setup and setup.savedAt then
			savedAtText:SetText("|cff808080Base + trigger from the '" .. redirectName ..
				"' profile; marked slots override it - last captured " ..
				date("%Y-%m-%d %H:%M", setup.savedAt) .. ".|r")
		else
			savedAtText:SetText("|cff808080Base loadout + trigger from the '" .. redirectName ..
				"' profile. Change any slot to override it for this profile.|r")
		end
		return
	end

	editSourceBtn:Hide()
	checkNowBtn:Show(); captureAllBtn:Show(); deleteBtn:Show()
	self:RefreshCopyFrom(true)

	local setup = BossPrepProfiles:GetBossSetup(selectedInstanceKey, selectedBossKey)
	local trigger = (setup and setup.trigger)
		or BossPrepData:GetDefaultTrigger(selectedInstanceKey, selectedBossKey)

	local triggerLabelText = ({ TARGET = "When I target it", ZONE = "When I enter its zone", KILL = "When another boss dies" })[trigger.type]
	self.triggerTypeDropdown:SetSelected(trigger.type, triggerLabelText)
	if trigger.type == "KILL" then
		self:RefreshKillAfterDropdown(trigger.killAfterBossKey)
		self.killAfterDropdown:Show()
	else
		self.killAfterDropdown:Hide()
	end
	self:RefreshZoneControls(trigger.type)

	self:FillLoadoutSlots(effective, source)

	if BossPrepProfiles:LoadoutIsEmpty(effective) then
		savedAtText:SetText("|cff808080No per-boss setup - faded slots follow the Global Default.|r")
	elseif setup and setup.savedAt then
		savedAtText:SetText("|cff808080Last captured " .. date("%Y-%m-%d %H:%M", setup.savedAt) .. "|r")
	else
		savedAtText:SetText("")
	end
end

-- Detail panel while the "Global Default Set" row is selected: same loadout
-- slots, no trigger section, values shown plainly (they're the source of
-- truth, not an inheritance).
function UI:RefreshGlobalPanel()
	self:SetTriggerSectionShown(false)
	self:SetGlobalModeButtons(true)
	self:RefreshLoadoutSourceDropdown()
	self:SetNoteSectionShown(false) -- notes are per-boss
	editSourceBtn:Hide()
	captureAllBtn:Show(); deleteBtn:Show()
	self:RefreshCopyFrom(true)
	self.triggerTypeDropdown:SetSelected(nil, "-")
	detailTitle:SetText("Global Default Set")

	local g = BossPrepProfiles:GetGlobalSetup()
	local effective = { talents = {}, talentNames = {}, glyphs = {}, trinkets = {} }
	if g then
		effective.equipmentSet = g.equipmentSet
		effective.specID, effective.specName = g.specID, g.specName
		effective.specGroup = g.specGroup
		if type(g.cloak) == "table" and g.cloak.itemID then effective.cloak = g.cloak end
		effective.talents = g.talents or {}
		effective.talentNames = g.talentNames or {}
		for i = 1, 3 do
			local x = g.glyphs and g.glyphs[i]
			if type(x) == "table" then effective.glyphs[i] = x end
		end
		for i = 1, 2 do
			local x = g.trinkets and g.trinkets[i]
			if type(x) == "table" and x.itemID then effective.trinkets[i] = x end
		end
	end

	self:FillLoadoutSlots(effective, nil)

	if g and g.savedAt then
		savedAtText:SetText("|cff808080Captured " .. date("%Y-%m-%d %H:%M", g.savedAt) ..
			" - the baseline every boss inherits.|r")
	else
		savedAtText:SetText("|cff808080The baseline every boss inherits unless it overrides.|r")
	end
end

-------------------------------------------------
-- Bottom row
-------------------------------------------------
local settingsDivider = T.Divider(main)
settingsDivider:SetPoint("BOTTOMLEFT", 14, 38)
settingsDivider:SetPoint("BOTTOMRIGHT", -14, 38)

local optionsBtn = T.Button(main, "Options / Alert Sound", 170, 22)
optionsBtn:SetPoint("BOTTOMLEFT", main, "BOTTOMLEFT", 18, 9)
optionsBtn:SetScript("OnClick", function() BossPrepOptions:Toggle() end)

local hintText = T.FontString(main, 11, "textDim", "")
hintText:SetPoint("LEFT", optionsBtn, "RIGHT", 12, 0)
hintText:SetText("/prep check  |cff606060·|r  /prep target  |cff606060·|r  /prep subzone")

-------------------------------------------------
-- Profile manager dialog
-------------------------------------------------
local pm = CreateFrame("Frame", "BossPrepProfileManager", UIParent)
pm:SetSize(360, 380)
pm:SetPoint("CENTER")
pm:SetFrameStrata("FULLSCREEN_DIALOG")
pm:SetMovable(true)
pm:EnableMouse(true)
pm:RegisterForDrag("LeftButton")
pm:SetScript("OnDragStart", pm.StartMoving)
pm:SetScript("OnDragStop", pm.StopMovingOrSizing)
pm:SetClampedToScreen(true)
pm:Hide()
if UISpecialFrames then tinsert(UISpecialFrames, "BossPrepProfileManager") end
T.Window(pm, "Profiles")

local pmHint = T.FontString(pm, 11, "textDim", "")
pmHint:SetPoint("TOPLEFT", 16, -38)
pmHint:SetText("Each profile is a full, independent set of boss loadouts.")

local pmList = CreateFrame("Frame", nil, pm)
pmList:SetPoint("TOPLEFT", 14, -56)
pmList:SetPoint("TOPRIGHT", -14, -56)
pmList:SetHeight(214)
T.Panel(pmList, "insetBG", "border")

local pmRows = {}
local pmSelectedId = nil

local function pmMakeRow(i)
	local r = pmRows[i]
	if r then return r end
	r = CreateFrame("Button", nil, pmList)
	r:SetHeight(24)
	r:SetPoint("TOPLEFT", 4, -4 - (i - 1) * 25)
	r:SetPoint("TOPRIGHT", -4, -4 - (i - 1) * 25)
	local hl = r:CreateTexture(nil, "HIGHLIGHT")
	hl:SetAllPoints()
	hl:SetColorTexture(1, 1, 1, 0.06)
	r.sel = r:CreateTexture(nil, "BACKGROUND")
	r.sel:SetAllPoints()
	r.sel:SetColorTexture(T.color.accent[1], T.color.accent[2], T.color.accent[3], 0.12)
	r.sel:Hide()
	r.text = T.FontString(r, 12, "text", "")
	r.text:SetPoint("LEFT", 10, 0)
	r.text:SetPoint("RIGHT", -10, 0)
	r.text:SetJustifyH("LEFT")
	r.text:SetWordWrap(false)
	r:SetScript("OnClick", function(self)
		pmSelectedId = self.profileId
		UI:RefreshProfileManager()
	end)
	r:SetScript("OnDoubleClick", function(self)
		BossPrepProfiles:SetActiveProfile(nil, self.profileId)
		UI:RefreshProfileDropdown()
		UI:RebuildBossList()
		UI:RefreshDetailPanel()
		UI:RefreshProfileManager()
	end)
	pmRows[i] = r
	return r
end

local pmSetActiveBtn = T.Button(pm, "Set Active", 96, 22)
pmSetActiveBtn:SetPoint("TOPLEFT", pmList, "BOTTOMLEFT", 0, -10)
pmSetActiveBtn:SetScript("OnClick", function()
	if not pmSelectedId then return end
	BossPrepProfiles:SetActiveProfile(nil, pmSelectedId)
	UI:RefreshProfileDropdown()
	UI:RebuildBossList()
	UI:RefreshDetailPanel()
	UI:RefreshProfileManager()
end)

local pmNewBtn = T.Button(pm, "New", 68, 22)
pmNewBtn:SetPoint("LEFT", pmSetActiveBtn, "RIGHT", 6, 0)
pmNewBtn:SetScript("OnClick", function()
	UI._pmRenameId = nil
	showPopup("BOSSPREP_PROFILE_NAME")
end)

local pmDupBtn = T.Button(pm, "Duplicate", 90, 22)
pmDupBtn:SetPoint("LEFT", pmNewBtn, "RIGHT", 6, 0)
pmDupBtn:SetScript("OnClick", function()
	if not pmSelectedId then return end
	local id = BossPrepProfiles:DuplicateProfile(nil, pmSelectedId)
	if id then pmSelectedId = id end
	UI:RefreshProfileDropdown()
	UI:RefreshProfileManager()
end)

local pmRenameBtn = T.Button(pm, "Rename", 80, 22)
pmRenameBtn:SetPoint("TOPLEFT", pmSetActiveBtn, "BOTTOMLEFT", 0, -6)
pmRenameBtn:SetScript("OnClick", function()
	if not pmSelectedId then return end
	UI._pmRenameId = pmSelectedId
	showPopup("BOSSPREP_PROFILE_NAME")
end)

local pmDelBtn = T.Button(pm, "Delete", 80, 22)
pmDelBtn:SetPoint("LEFT", pmRenameBtn, "RIGHT", 6, 0)
pmDelBtn:SetScript("OnClick", function()
	if not pmSelectedId then return end
	showPopup("BOSSPREP_PROFILE_DELETE")
end)

function UI:RefreshProfileManager()
	local profiles = BossPrepProfiles:GetProfiles()

	local valid = false
	for _, p in ipairs(profiles) do if p.id == pmSelectedId then valid = true end end
	if not valid then
		pmSelectedId = nil
		for _, p in ipairs(profiles) do if p.active then pmSelectedId = p.id end end
		pmSelectedId = pmSelectedId or (profiles[1] and profiles[1].id)
	end

	for i, p in ipairs(profiles) do
		local r = pmMakeRow(i)
		r.profileId = p.id
		r.text:SetText(p.name .. (p.active and "  |cff33ff99(active)|r" or ""))
		r.sel:SetShown(p.id == pmSelectedId)
		r:Show()
	end
	for i = #profiles + 1, #pmRows do pmRows[i]:Hide() end

	pmDelBtn:SetEnabled(#profiles > 1 and pmSelectedId ~= nil)
end

function UI:ToggleProfileManager()
	if pm:IsShown() then
		pm:Hide()
		return
	end
	pmSelectedId = BossPrepProfiles:GetActiveProfileId()
	UI:RefreshProfileManager()
	pm:Show()
end

-------------------------------------------------
-- Toggle / open
-------------------------------------------------
function UI:Toggle()
	if main:IsShown() then
		main:Hide()
		return
	end

	BossPrep.EnsureDB()
	charValue:SetText(BossPrep.GetCharKey())
	self:RefreshProfileDropdown()
	self:RefreshInstanceDropdown()
	self:RebuildBossList()
	self:RefreshDetailPanel()

	main:Show()
end

-------------------------------------------------
-- "Save current gear as a new set" name prompt
-------------------------------------------------
StaticPopupDialogs["BOSSPREP_NEW_GEAR_SET"] = {
	text = "Name for the new gear set (created from what you're wearing now):",
	button1 = "Create",
	button2 = "Cancel",
	hasEditBox = true,
	maxLetters = 32,
	OnAccept = function(dialog)
		local name = popupText(dialog)
		if name == "" then return end
		local ok, err = BossPrepCompat.CreateEquipmentSetFromCurrent(name)
		if ok then
			if editingGlobal then
				BossPrepProfiles:SetGlobalEquipmentSetChoice(name)
			elseif selectedInstanceKey and selectedBossKey then
				BossPrepProfiles:SetEquipmentSetChoice(selectedInstanceKey, selectedBossKey, name)
			end
			UI:RebuildBossList()
			UI:RefreshDetailPanel()
		else
			print("|cff33ff99Prepared|r couldn't create gear set: " .. tostring(err))
		end
	end,
	EditBoxOnEnterPressed = function(editBox)
		local dialog = editBox:GetParent()
		if dialog.button1 then dialog.button1:Click() end
	end,
	timeout = 0,
	whileDead = true,
	hideOnEscape = true,
}

-------------------------------------------------
-- Profile create / rename prompt (shared)
-------------------------------------------------
StaticPopupDialogs["BOSSPREP_PROFILE_NAME"] = {
	text = "Profile name:",
	button1 = "OK",
	button2 = "Cancel",
	hasEditBox = true,
	maxLetters = 24,
	OnShow = function(dialog)
		local cur = ""
		if UI._pmRenameId then
			for _, p in ipairs(BossPrepProfiles:GetProfiles()) do
				if p.id == UI._pmRenameId then cur = p.name end
			end
		end
		local eb = popupEditBox(dialog)
		if eb then
			eb:SetText(cur)
			eb:SetFocus()
			eb:HighlightText()
		end
	end,
	OnAccept = function(dialog)
		local name = popupText(dialog)
		if name == "" then return end
		if UI._pmRenameId then
			BossPrepProfiles:RenameProfile(nil, UI._pmRenameId, name)
			print("|cff33ff99Prepared|r profile renamed to '" .. name .. "'.")
		else
			pmSelectedId = BossPrepProfiles:CreateProfile(nil, name)
			print("|cff33ff99Prepared|r created profile '" .. name .. "'.")
		end
		UI._pmRenameId = nil
		UI:RefreshProfileDropdown()
		if UI.RefreshProfileManager then UI:RefreshProfileManager() end
		UI:RebuildBossList()
		UI:RefreshDetailPanel()
	end,
	EditBoxOnEnterPressed = function(editBox)
		local dialog = editBox:GetParent()
		if dialog.button1 then dialog.button1:Click() end
	end,
	timeout = 0,
	whileDead = true,
	hideOnEscape = true,
}

StaticPopupDialogs["BOSSPREP_PROFILE_DELETE"] = {
	text = "Delete this profile? Bosses in other profiles that borrow from it will revert to their own setup. This can't be undone.",
	button1 = "Delete",
	button2 = "Cancel",
	showAlert = true,
	OnAccept = function()
		if not pmSelectedId then return end
		local ok, err = BossPrepProfiles:DeleteProfile(nil, pmSelectedId)
		if not ok then
			print("|cff33ff99Prepared|r " .. tostring(err))
			return
		end
		pmSelectedId = BossPrepProfiles:GetActiveProfileId()
		UI:RefreshProfileDropdown()
		if UI.RefreshProfileManager then UI:RefreshProfileManager() end
		UI:RebuildBossList()
		UI:RefreshDetailPanel()
	end,
	timeout = 0,
	whileDead = true,
	hideOnEscape = true,
}
