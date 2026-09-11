-- Alert.lua
BossPrepAlert = {}
local A = BossPrepAlert

local T = BossPrepTheme
local u = T.u

local frame = CreateFrame("Frame", "BossPrepAlertFrame", UIParent)
frame:SetSize(340, 120)
frame:SetPoint("TOP", UIParent, "TOP", 0, -160)
frame:SetMovable(true)
frame:EnableMouse(true)
frame:RegisterForDrag("LeftButton")
frame:SetScript("OnDragStart", function(self)
	self.wasDrag = true
	self:StartMoving()
end)
frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
frame:SetClampedToScreen(true)
frame:SetFrameStrata("HIGH")
frame:Hide()

T.Panel(frame, "dangerBG", "border")
T.SetBorderColor(frame, "danger")

-- red accent bar down the left edge
local accent = frame:CreateTexture(nil, "OVERLAY")
accent:SetPoint("TOPLEFT")
accent:SetPoint("BOTTOMLEFT")
accent:SetWidth(3)
accent:SetColorTexture(u(T.color.danger))

local title = T.FontString(frame, 14, "textBright", "")
title:SetPoint("TOPLEFT", 14, -12)
title:SetText("SWITCH SETUP")
frame.title = title

local close = T.CloseButton(frame)
close:SetPoint("TOPRIGHT", -4, -4)
close:SetScript("OnClick", function() frame:Hide() end)

local sub = T.FontString(frame, 12, "danger", "")
sub:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -3)
frame.sub = sub

local body = T.FontString(frame, 12, "text", "")
body:SetPoint("TOPLEFT", sub, "BOTTOMLEFT", 0, -8)
body:SetPoint("RIGHT", frame, "RIGHT", -14, 0)
body:SetJustifyH("LEFT")
body:SetJustifyV("TOP")
body:SetSpacing(3)
frame.body = body

-- Per-boss note (BossPrepProfiles:GetBossNote for the tracked boss). Gold, and
-- set apart under the problem list.
local noteText = T.FontString(frame, 12, "textBright", "")
noteText:SetPoint("TOPLEFT", body, "BOTTOMLEFT", 0, -7)
noteText:SetPoint("RIGHT", frame, "RIGHT", -14, 0)
noteText:SetJustifyH("LEFT")
noteText:SetJustifyV("TOP")
noteText:SetSpacing(2)
noteText:SetTextColor(1, 0.82, 0.2)
noteText:Hide()
frame.noteText = noteText

local dismissHint = T.FontString(frame, 10, "textDim", "")
dismissHint:SetPoint("BOTTOMRIGHT", -10, 6)
dismissHint:SetText("button below: next fix  |cff555555·|r  right-click: dismiss")

-------------------------------------------------
-- The single "fix it" button, under the banner. Every fix goes through it (the
-- banner body itself only drags / right-click-dismisses).
--
-- BossPrep can't touch talents/glyphs from addon code (the mutation APIs are
-- Blizzard-only, and even *opening* the panels taints them). So it's a
-- SecureActionButtonTemplate that runs a /click macro on the *player's* click -
-- the whole chain then runs in a hardware-triggered secure context, so it can
-- drive Blizzard's own talent/glyph UI (open panel, jump to tab, pick a
-- talent, hit Learn, cast a glyph, click a socket, confirm the game's reagent
-- popups) with zero taint.
--
-- Physical gear (set / cloak / trinkets) isn't protected out of combat, so for
-- those steps the macro is empty and the button's PreClick equips directly via
-- D:EquipItems instead.
--
-- A:ComputeSecureStep() reads live state and returns (label, macrotext, kind)
-- for the *next* step; a full talent/glyph fix is usually several presses
-- (open -> select -> Learn, or open -> pick glyph -> socket -> confirm popup).
-------------------------------------------------
local MAJOR_SOCKETS = { 2, 4, 6 } -- GlyphFrameGlyph<n> ids for the 3 major slots

-- Parented to UIParent, NOT the alert frame: it's a protected (secure) frame,
-- and having a protected descendant makes frame:Show() get blocked in combat
-- (the alert would fire its cue but never appear). It's anchored just below
-- the banner instead, and hidden/shown alongside it.
local openBtn = CreateFrame("Button", "BossPrepAlertFixButton", UIParent, "SecureActionButtonTemplate")
openBtn:SetFrameStrata("HIGH")
openBtn:SetHeight(22)
openBtn:SetPoint("TOPLEFT", frame, "BOTTOMLEFT", 8, -3)
openBtn:SetPoint("TOPRIGHT", frame, "BOTTOMRIGHT", -8, -3)
T.Panel(openBtn, "raised", "borderStrong")
do
	local hl = openBtn:CreateTexture(nil, "HIGHLIGHT")
	hl:SetAllPoints()
	hl:SetColorTexture(T.color.accent[1], T.color.accent[2], T.color.accent[3], 0.16)
end
openBtn.label = T.FontString(openBtn, 11, "textBright", "")
openBtn.label:SetPoint("LEFT", 6, 0)
openBtn.label:SetPoint("RIGHT", -6, 0)
openBtn.label:SetJustifyH("CENTER")
openBtn.label:SetWordWrap(false)
-- Register BOTH up and down: SecureActionButton_OnClick only performs on the
-- edge that matches the ActionButtonUseKeyDown cvar, and its own logic makes
-- exactly one of the two fire. Registering only "AnyUp" means the action is
-- silently skipped for anyone with cast-on-key-down enabled.
openBtn:RegisterForClicks("AnyUp", "AnyDown")
openBtn:SetAttribute("useOnKeyDown", false)
openBtn:SetAttribute("type", "macro") -- macrotext set per-step in A:RefreshFixButton
openBtn:SetScript("OnEnter", function(self) T.SetBorderColor(self, "accentDim") end)
openBtn:SetScript("OnLeave", function(self) T.SetBorderColor(self, "border") end)
openBtn:Hide()
A.openBtn = openBtn

-- Find the glyph browse-list button showing `wanted` ({glyphID=, name=}).
-- Scans the visible rows; if it's scrolled out of view, name-filters the list
-- (same call Blizzard's search box uses - no taint) and rescans.
function A:FindGlyphListButton(wanted)
	local sf = _G.GlyphFrameScrollFrame
	local buttons = sf and sf.buttons
	if not buttons then return nil end

	local function matches(glyphIndex)
		local ok, name, _, isKnown, _, glyphID = pcall(_G.GetGlyphInfo, glyphIndex)
		if not (ok and name and name ~= "header" and isKnown) then return false end
		if wanted.glyphID and glyphID == wanted.glyphID then return true end
		if wanted.name and name == wanted.name then return true end
		return false
	end

	local function scan()
		for _, b in ipairs(buttons) do
			if b:IsShown() and b.glyphIndex and matches(b.glyphIndex) then
				return b:GetName()
			end
		end
	end

	local hit = scan()
	if hit then return hit end
	if _G.SetGlyphNameFilter and wanted.name then
		pcall(_G.SetGlyphNameFilter, wanted.name)
		if _G.GlyphFrame_UpdateGlyphList then pcall(_G.GlyphFrame_UpdateGlyphList) end
		hit = scan()
		if hit then
			A._glyphFiltered = true
		else
			-- Don't leave the browse list filtered to nothing (would look like
			-- "you know no glyphs" until the banner clears).
			A:ClearGlyphFilter()
		end
	end
	return hit
end

-- Undo any name filter FindGlyphListButton set, so the browse list shows every
-- known glyph again. Safe to call any time.
function A:ClearGlyphFilter()
	if not A._glyphFiltered then return end
	A._glyphFiltered = nil
	if _G.SetGlyphNameFilter then pcall(_G.SetGlyphNameFilter, "") end
	if _G.GlyphFrame_UpdateGlyphList then pcall(_G.GlyphFrame_UpdateGlyphList) end
end

-- Returns label, macrotext, kind for the next step the fix button should offer:
--   kind "gear"      - physical gear (set/cloak/trinkets); macrotext nil, the
--                      button's PreClick runs D:EquipItems
--   kind "spec"      - a dual-spec swap (macrotext); PreClick sets the role
--   kind "gear+spec" - gear (PreClick D:EquipItems + role) AND a dual-spec swap
--                      (macrotext) together on one press
--   kind nil         - a talent/glyph panel step (macrotext is the secure
--                      /click chain), or, with macrotext also nil, either a
--                      hand-only hint or nothing left to do (button hidden)
--
-- A dual-spec swap for `setup`: returned only when the boss's spec sits on the
-- player's other, inactive talent group - the one case swapping is a free,
-- instant secure /click instead of a class-trainer visit. Returns (specName,
-- macrotext) or nil.
local function dualSpecSwapStep(setup, C, panelOpen)
	if not setup.specID then return end
	local _, _, curSpec = C.GetCurrentSpec()
	if not (curSpec and curSpec ~= setup.specID) then return end
	local active = C.GetActiveSpecGroup()
	local other = (active == 1) and 2 or 1
	if C.GetNumSpecGroups() >= 2 and C.GetSpecIDForGroup(other) == setup.specID then
		return (setup.specName or "your other spec"),
			(panelOpen and "" or "/click TalentMicroButton\n")
				.. "/click PlayerSpecTab" .. other
				.. "\n/click PlayerTalentFrameActivateButton"
	end
end

function A:ComputeSecureStep()
	local C = BossPrepCompat
	local D = BossPrepDetection
	if not (C and D and BossPrepProfiles) then return end

	local ik, bk = D:GetCurrentBoss()
	if not (ik and bk) then return end
	local setup = BossPrepProfiles:ResolveBossLoadout(ik, bk)
	if BossPrepProfiles:LoadoutIsEmpty(setup) then return end

	local ptf = _G.PlayerTalentFrame
	local panelOpen = ptf and ptf:IsShown()
	local tab = panelOpen and _G.PanelTemplates_GetSelectedTab and _G.PanelTemplates_GetSelectedTab(ptf)
	local activeGroup = C.GetActiveSpecGroup() or 1
	-- If the panel's already open, just click the tab (a second /click on the
	-- micro button would TOGGLE it shut). For the Talents/Glyphs tabs also click
	-- the active spec-group tab: a fresh open (or a dual-spec swap) can leave the
	-- panel previewing the *other* group, so the rows/sockets we then /click and
	-- highlight would be the wrong spec's.
	local openTo = function(n)
		local m = panelOpen and ("/click PlayerTalentFrameTab" .. n)
			or ("/click TalentMicroButton\n/click PlayerTalentFrameTab" .. n)
		if n ~= 1 then m = m .. "\n/click PlayerSpecTab" .. activeGroup end
		return m
	end
	-- Standalone "put the panel back on the active group" step, for when it's
	-- already open on the right tab but previewing the wrong group.
	local function specTabFixStep()
		if not panelOpen then return end
		local shown = ptf and ptf.talentGroup
		if shown and shown ~= activeGroup then
			return "Show your active spec", "/click PlayerSpecTab" .. activeGroup
		end
	end

	-- Physical gear first (the button's PreClick equips it directly - not
	-- protected out of combat). One press does the set, the cloak and both
	-- trinkets together. If a dual-spec swap is also due, that rides along on
	-- the same press (macro); the re-check then moves on to talents/glyphs.
	local gearBits = {}
	if setup.equipmentSet and C.IsEquipmentSetActive(setup.equipmentSet) == false then
		gearBits[#gearBits + 1] = "gear set"
	end
	if setup.cloak and setup.cloak.itemID then
		local cur = C.GetCurrentCloak()
		if not cur or cur.itemID ~= setup.cloak.itemID then gearBits[#gearBits + 1] = "cloak" end
	end
	if setup.trinkets then
		local cur = C.GetCurrentTrinkets()
		local equipped = {}
		for _, t in pairs(cur) do if t and t.itemID then equipped[t.itemID] = true end end
		for i = 1, 2 do
			local w = setup.trinkets[i]
			if w and w.itemID and not equipped[w.itemID] then
				gearBits[#gearBits + 1] = "trinkets"
				break
			end
		end
	end
	if #gearBits > 0 then
		local swapName, swapMacro = dualSpecSwapStep(setup, C, panelOpen)
		if swapMacro then
			return "Equip gear + switch to " .. swapName, swapMacro, "gear+spec"
		end
		return "Equip " .. table.concat(gearBits, " + "), nil, "gear"
	end

	-- SPEC
	if setup.specID then
		local _, _, curSpec = C.GetCurrentSpec()
		if curSpec and curSpec ~= setup.specID then
			-- Dual spec: if the boss's spec is on the *other* talent group, one
			-- secure click swaps to it (free + instant). Note it swaps the
			-- whole loadout - talents + glyphs move to that group's set too.
			local swapName, swapMacro = dualSpecSwapStep(setup, C, panelOpen)
			if swapMacro then
				return "Switch to " .. swapName, swapMacro, "spec"
			end
			-- Otherwise a real respec needs a class trainer - just open the pane.
			if not (panelOpen and tab == 1) then
				return "Open specialization", openTo(1)
			end
			return nil
		end
	end

	-- TALENTS
	if setup.talents then
		local current = C.GetCurrentTalents()
		local specGroup = C.GetActiveSpecGroup()
		for tier = 1, (C.MAX_TALENT_TIERS or 6) do
			local wantCol = setup.talents[tier]
			if wantCol == false and current[tier] then
				-- Tier should be empty. Best-effort: right-click the talent you
				-- have, which pops the game's own "unlearn talent" confirm
				-- (RemoveTalent can't be called directly - Blizzard-only - but a
				-- hardware /click on its own button runs the popup securely).
				if not (panelOpen and tab == 2) then
					return "Open talents", openTo(2)
				end
				local gl, gm = specTabFixStep()
				if gm then return gl, gm end
				return "Unlearn tier " .. tier,
					"/click PlayerTalentFrameTalentsTalentRow" .. tier .. "Talent" .. current[tier] .. " RightButton"
			elseif wantCol and current[tier] ~= wantCol then
				if not (panelOpen and tab == 2) then
					return "Open talents", openTo(2)
				end
				local gl, gm = specTabFixStep()
				if gm then return gl, gm end
				local choice = C.GetTalentChoice(tier, wantCol, specGroup)
				local nm = (setup.talentNames and setup.talentNames[tier])
					or (choice and choice.name) or ("the tier " .. tier .. " talent")
				local wantID = choice and choice.talentID
				local row = _G.PlayerTalentFrameTalents and _G.PlayerTalentFrameTalents["tier" .. tier]
				local pending = row and row.selectionId
				local talentBtn = "PlayerTalentFrameTalentsTalentRow" .. tier .. "Talent" .. wantCol
				local learnBtn = "PlayerTalentFrameTalentsLearnButton"

				if wantID and pending == wantID then
					return "Learn " .. nm, "/click " .. learnBtn
				elseif current[tier] then
					return "Unlearn tier " .. tier .. ", switch to " .. nm,
						"/click " .. talentBtn -- pops the game's Tome-of-the-Clear-Mind confirm
				else
					return "Learn " .. nm, "/click " .. talentBtn .. "\n/click " .. learnBtn
				end
			end
		end
	end

	-- GLYPHS
	if setup.glyphs then
		local current = C.GetCurrentMajorGlyphs()
		local wantSet = {}
		for _, w in pairs(setup.glyphs) do
			if type(w) == "table" then
				if w.glyphID then wantSet[w.glyphID] = true end
				if w.spellID then wantSet[w.spellID] = true end
			end
		end
		local seen = {}
		for i = 1, 3 do
			local wanted = setup.glyphs[i]
			local dup = false
			if type(wanted) == "table" then
				for _, s in ipairs(seen) do
					if C.GlyphChoicesMatch(s, wanted) then dup = true break end
				end
				if not dup then seen[#seen + 1] = wanted end
			end
			if not dup and type(wanted) == "table" and (wanted.glyphID or wanted.spellID) then
				local socketed = false
				for _, have in pairs(current) do
					if have and C.GlyphChoicesMatch(have, wanted) then socketed = true break end
				end
				if not socketed then
					local glyphPaneOpen = panelOpen and tab == 3
						and _G.GlyphFrame and _G.GlyphFrame:IsShown()
					if not glyphPaneOpen then
						return "Open glyphs", openTo(3)
					end
					local gl, gm = specTabFixStep()
					if gm then return gl, gm end
					local listBtn = self:FindGlyphListButton(wanted)
					if not listBtn then
						-- already on the glyph tab but can't locate it in the
						-- list; the highlights still point at it
						return nil
					end
					local socket = MAJOR_SOCKETS[1]
					for uiSlot = 1, 3 do
						local have = current[uiSlot]
						local keep = have and ((have.glyphID and wantSet[have.glyphID])
							or (have.spellID and wantSet[have.spellID]))
						if not have or not keep then socket = MAJOR_SOCKETS[uiSlot]; break end
					end
					return "Socket " .. (wanted.name or "glyph"),
						"/click " .. listBtn .. "\n/click GlyphFrameGlyph" .. socket, "glyph"
				end
			end
		end

		-- An explicitly-emptied slot with a non-wanted glyph socketed. BossPrep
		-- can't clear a socket (no click gesture; RemoveGlyphFromSocket is
		-- Blizzard-only), but it can get the player to the panel so the red
		-- highlight shows which one - then the button hides and they clear it.
		local exhaustive = false
		for i = 1, 3 do if setup.glyphs[i] == false then exhaustive = true break end end
		if exhaustive then
			for uiSlot = 1, 3 do
				local have = current[uiSlot]
				local keep = have and ((have.glyphID and wantSet[have.glyphID])
					or (have.spellID and wantSet[have.spellID]))
				if have and (have.glyphID or have.spellID) and not keep then
					local glyphPaneOpen = panelOpen and tab == 3
						and _G.GlyphFrame and _G.GlyphFrame:IsShown()
					if not glyphPaneOpen then
						return "Open glyphs (unlearn " .. (have.name or "a glyph") .. " by hand)", openTo(3)
					end
					return nil -- on the panel; the red wash shows the socket
				end
			end
		end
	end

	return nil
end

-- (Re)label / show / hide the fix button. Protected frame -> combat = leave it.
function A:RefreshFixButton()
	if InCombatLockdown and InCombatLockdown() then return end

	local label, macrotext, kind
	if frame:IsShown() then
		label, macrotext, kind = self:ComputeSecureStep()
	end
	A._stepKind = kind
	if kind ~= "glyph" then self:ClearGlyphFilter() end -- not browsing to a glyph: unfilter the list

	if label and (macrotext or kind == "gear") then
		openBtn.label:SetText(label)
		-- "gear" steps run in the button's PreClick, not a secure macro.
		openBtn:SetAttribute("macrotext", macrotext or "")
		openBtn:SetAlpha(1)
		openBtn:Show()
	else
		openBtn:Hide()
	end
end

-- The non-secure side of a press: equip physical gear (not protected out of
-- combat) and set the group/raid role for a spec swap - both run here in the
-- (hardware-triggered) PreClick, before the secure macrotext runs. Talent/glyph
-- steps carry only a macro and this does nothing for them beyond the timestamp.
openBtn:SetScript("PreClick", function()
	if InCombatLockdown and InCombatLockdown() then return end
	-- The button registers both click edges (see RegisterForClicks note above),
	-- so PreClick fires on press AND release - debounce to one run per click.
	local now = GetTime()
	if A._lastPre and (now - A._lastPre) < 0.3 then return end
	A._lastPre = now

	local D = BossPrepDetection
	if D then D.lastApplyAt = now end -- keeps the UI_ERROR_MESSAGE relay armed

	local kind = A._stepKind
	if not (D and BossPrepProfiles and kind) then return end -- panel step: macro-only
	local ik, bk = D:GetCurrentBoss()
	if not (ik and bk) then return end
	local resolved = BossPrepProfiles:ResolveBossLoadout(ik, bk)

	-- Spec swap: match the role to the new spec first (see
	-- C.SetPlayerRoleForSpec) so the server doesn't bounce the swap.
	if (kind == "spec" or kind == "gear+spec") and BossPrepCompat.SetPlayerRoleForSpec then
		BossPrepCompat.SetPlayerRoleForSpec(resolved and resolved.specID)
	end

	if kind == "gear" or kind == "gear+spec" then
		D:EquipItems(resolved)
		if kind == "gear+spec" and C_Timer and C_Timer.After then
			-- The secure macro on this same click also swaps spec, and a spec
			-- can carry its own assigned gear set that would land on top of
			-- ours. Re-equip once that settles so the boss's set wins (no-op if
			-- already correct).
			C_Timer.After(0.5, function()
				if not (InCombatLockdown and InCombatLockdown()) then D:EquipItems(resolved) end
			end)
		end
	end
end)

-- Re-evaluate whenever the talent / glyph panels open, close or switch tabs.
local function hookPanels()
	local defer = function()
		if C_Timer and C_Timer.After then
			C_Timer.After(0, function() A:RefreshFixButton() end)
		end
	end
	for _, name in ipairs({ "PlayerTalentFrame", "GlyphFrame" }) do
		local f = _G[name]
		if f and not A["_hooked_" .. name] then
			A["_hooked_" .. name] = true
			f:HookScript("OnShow", defer)
			f:HookScript("OnHide", defer)
		end
	end
	for i = 1, 4 do
		local t = _G["PlayerTalentFrameTab" .. i]
		if t and not A["_hookedTab" .. i] then
			A["_hookedTab" .. i] = true
			t:HookScript("OnClick", defer)
		end
	end
end
BossPrep:On("ADDON_LOADED", function(n)
	if n == "Blizzard_TalentUI" or n == "Blizzard_GlyphUI" then hookPanels() end
end)
hookPanels()

-- Combat blocks touching the (protected) fix button; re-sync when it ends.
BossPrep:On("PLAYER_REGEN_ENABLED", function() A:RefreshFixButton() end)

-- Right-click dismisses the banner. All fixes go through the button below it
-- (a single consistent path); the banner body itself only drags and dismisses.
frame:SetScript("OnMouseUp", function(self, button)
	if button == "RightButton" then
		self:Hide()
	end
	self.wasDrag = nil
end)

-- Any hide (X, right-click, boss died, wipe, /prep) also kills the audio cue.
frame:SetScript("OnHide", function(self)
	if self.pulse then self.pulse:Stop() end
	if BossPrepSound then BossPrepSound.StopCue() end
	if BossPrepHighlight then BossPrepHighlight:Stop() end
	if A.openBtn then
		if InCombatLockdown and InCombatLockdown() then
			A.openBtn:SetAlpha(0) -- can't Hide a protected frame in combat
		else
			A.openBtn:Hide()
		end
	end
	A._glyphFiltered = true -- force ClearGlyphFilter to run the update too
	A:ClearGlyphFilter()
end)

frame.pulse = frame:CreateAnimationGroup()
local grow = frame.pulse:CreateAnimation("Scale")
grow:SetScale(1.04, 1.04)
grow:SetDuration(0.4)
grow:SetOrder(1)
local shrink = frame.pulse:CreateAnimation("Scale")
shrink:SetScale(1 / 1.04, 1 / 1.04)
shrink:SetDuration(0.4)
shrink:SetOrder(2)

A.frame = frame

function A:Show(bossName, problems, forceCue)
	if BossPrepDB and BossPrepDB.settings and BossPrepDB.settings.alertsEnabled == false then
		return
	end

	problems = problems or {}
	frame.sub:SetText(bossName or "")
	local lines = {}
	for _, p in ipairs(problems) do
		local text = type(p) == "table" and p.text or p
		table.insert(lines, "|cffff5555\226\128\162|r " .. text)
	end
	frame.body:SetText(table.concat(lines, "\n"))
	frame.title:SetText(#problems > 0 and "SWITCH SETUP" or "BOSS NOTE")

	-- Per-boss note for whichever boss is tracked right now.
	local note, noteAnnounce
	if BossPrepDetection and BossPrepProfiles then
		local ik, bk = BossPrepDetection:GetCurrentBoss() -- (2 returns; don't wrap in `and`)
		if ik and bk then
			note, noteAnnounce = BossPrepProfiles:GetBossNote(ik, bk)
		end
	end
	frame.noteText:SetText(note or "")
	frame.noteText:SetShown(note ~= nil)

	A._lineCount = #problems
	local bodyH = frame.body:GetStringHeight()
	if not bodyH or bodyH < 1 then bodyH = #problems * 16 end
	local h = 58 + bodyH
	if note then
		local nh = frame.noteText:GetStringHeight()
		if not nh or nh < 1 then
			local n = 1
			for _ in note:gmatch("\n") do n = n + 1 end
			nh = n * 15
		end
		h = h + nh + 16
	end
	frame:SetHeight(math.max(h, 74))

	local firstShow = not frame:IsShown()
	if firstShow then
		frame:Show()
		frame.pulse:Play()
	end

	self:RefreshFixButton()

	-- Cue on every fresh appearance, and again on a manual re-check.
	if (firstShow or forceCue) and BossPrepSound then
		BossPrepSound.PlayCue(problems, (note and noteAnnounce) and note or nil)
	end

	-- Refresh the talent/glyph panel outlines (no-op unless a panel is open).
	if BossPrepHighlight then BossPrepHighlight:Kick() end
end

function A:Hide()
	frame:Hide()
end
