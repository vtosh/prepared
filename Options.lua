-- Options.lua
-- Small settings window: alert audio cue (sound effect / text-to-speech) plus
-- the global toggles. Opened from the "Options" button on the main window.

BossPrepOptions = {}
local O = BossPrepOptions

local T = BossPrepTheme
local u = T.u

-- Taller than it used to be: the voice/volume block now shows alongside the
-- sound-effect picker (SOUND mode + TTS available is the tallest combo since
-- notes can announce through TTS no matter which mode is chosen), plus the
-- note-delay slider under the sound-effect picker.
local W, H = 470, 465

local frame = CreateFrame("Frame", "BossPrepOptionsFrame", UIParent)
frame:SetSize(W, H)
frame:SetPoint("CENTER", 40, 0)
frame:SetFrameStrata("DIALOG")
frame:SetToplevel(true)
frame:SetMovable(true)
frame:EnableMouse(true)
frame:SetClampedToScreen(true)
frame:Hide()
if UISpecialFrames then tinsert(UISpecialFrames, "BossPrepOptionsFrame") end

T.Window(frame, "Prepared Options")

local function settings()
	BossPrep.EnsureDB()
	return BossPrepDB.settings
end

-------------------------------------------------
-- Alert cue
-------------------------------------------------
local cueHeader = T.SectionHeader(frame, "Alert Sound")
cueHeader:SetPoint("TOPLEFT", 18, -42)

O.modeDropdown = T.Dropdown(frame, 210, function(value)
	settings().alertSoundMode = value
	O:RefreshCueControls()
end)
O.modeDropdown:SetPoint("TOPLEFT", cueHeader, "BOTTOMLEFT", 0, -8)
O.modeDropdown:SetOptions({
	{ text = "Text-to-speech", value = "TTS" },
	{ text = "No sound", value = "NONE" },
	{ text = "Sound effect", value = "SOUND" },
})

-- Sound-effect sub-group ---------------------------------------------------
-- No separate "Test" button here - picking an option previews it immediately
-- (see onSelect below), and "Test the alert cue" further down covers the
-- full cue including any announced note.
local soundLabel = T.FontString(frame, 10, "textDim", "")
soundLabel:SetPoint("TOPLEFT", O.modeDropdown, "BOTTOMLEFT", 0, -16)
soundLabel:SetText("SOUND EFFECT")

O.soundDropdown = T.Dropdown(frame, 210, function(value)
	settings().alertSoundKey = value
	settings().alertSoundKeyChosen = true
	BossPrepSound.PlaySound(value)
end)
O.soundDropdown:SetPoint("TOPLEFT", soundLabel, "BOTTOMLEFT", 0, -6)

-- How long to wait after the sound effect before speaking an announced note,
-- so the two don't talk over each other. Only meaningful in SOUND mode: TTS
-- mode folds the note into the same spoken phrase, and NONE mode has no
-- sound effect to wait on.
local delayLabel = T.FontString(frame, 10, "textDim", "")
delayLabel:SetPoint("TOPLEFT", O.soundDropdown, "BOTTOMLEFT", 0, -16)
delayLabel:SetText("NOTE DELAY")

O.delaySlider = T.Slider(frame, 0, 4, 0.5)
O.delaySlider:SetPoint("TOPLEFT", delayLabel, "BOTTOMLEFT", 2, -10)
O.delaySlider:SetPoint("RIGHT", frame, "LEFT", 228, 0)
O.delaySlider.format = function(v) return string.format("%.1fs", v) end
O.delaySlider.onChange = function(value)
	settings().noteAnnounceDelay = math.floor(value * 10 + 0.5) / 10
end

-- TTS sub-group - voice/volume apply to spoken boss notes no matter which
-- alert-sound mode is chosen (notes always speak via TTS when their own
-- "announce" box is on), so this is shown whenever TTS is available at all,
-- not just while mode == TTS. Its vertical position shifts below the
-- sound-effect block in RefreshCueControls.
local voiceLabel = T.FontString(frame, 10, "textDim", "")
voiceLabel:SetPoint("TOPLEFT", O.modeDropdown, "BOTTOMLEFT", 0, -16)
voiceLabel:SetText("VOICE")

O.voiceDropdown = T.Dropdown(frame, 210, function(value)
	settings().ttsVoiceID = value
	BossPrepSound.Speak("Boss prep")
end)
O.voiceDropdown:SetPoint("TOPLEFT", voiceLabel, "BOTTOMLEFT", 0, -6)

local volumeLabel = T.FontString(frame, 10, "textDim", "")
volumeLabel:SetPoint("TOPLEFT", O.voiceDropdown, "BOTTOMLEFT", 0, -18)
volumeLabel:SetText("VOLUME")
O.volumeLabel = volumeLabel

O.volumeSlider = T.Slider(frame, 0, 100, 5)
O.volumeSlider:SetPoint("TOPLEFT", volumeLabel, "BOTTOMLEFT", 2, -10)
O.volumeSlider:SetPoint("RIGHT", frame, "LEFT", 228, 0)
O.volumeSlider.onChange = function(value)
	settings().ttsVolume = math.floor(value + 0.5)
end

O.cbTtsMinimal = T.Checkbox(frame, "Minimal alerts")
O.cbTtsMinimal:SetPoint("TOPLEFT", O.volumeSlider, "BOTTOMLEFT", -2, -18)
O.cbTtsMinimal:SetScript("OnClick", function(self)
	settings().ttsMinimal = self:GetChecked() and true or false
end)

O.ttsMissing = T.FontString(frame, 11, "danger", "")
O.ttsMissing:SetPoint("TOPLEFT", voiceLabel, "TOPLEFT", 0, -2)
O.ttsMissing:SetPoint("RIGHT", frame, "LEFT", 230, 0)
O.ttsMissing:SetJustifyH("LEFT")
O.ttsMissing:SetText("Text-to-speech isn't available on this client, so boss notes can't be announced.")

-- Preview -----------------------------------------------------------------
O.testCueBtn = T.Button(frame, "Test the alert cue", 200, 24)
-- position set in O:RefreshCueControls (below the TTS block, which varies in height)
O.testCueBtn:SetScript("OnClick", function()
	BossPrepSound.TestCue()
end)

-------------------------------------------------
-- Panel highlights (top-right column)
-------------------------------------------------
local hlSep = frame:CreateTexture(nil, "ARTWORK")
hlSep:SetColorTexture(u(T.color.borderStrong))
hlSep:SetWidth(1)
hlSep:SetPoint("TOP", frame, "TOPLEFT", 238, -40)
hlSep:SetHeight(283)

local hlHeader = T.SectionHeader(frame, "Panel Highlights")
hlHeader:SetPoint("TOPLEFT", 252, -42)

local hlHint = T.FontString(frame, 10, "textDim", "")
hlHint:SetPoint("TOPLEFT", hlHeader, "BOTTOMLEFT", 0, -6)
hlHint:SetPoint("RIGHT", frame, "RIGHT", -18, 0)
hlHint:SetJustifyH("LEFT")
hlHint:SetText("Shown on the talent / glyph panels while an alert is up.")

O.cbHighlights = T.Checkbox(frame, "Enable")
O.cbHighlights:SetPoint("TOPLEFT", hlHint, "BOTTOMLEFT", 0, -10)
O.cbHighlights:SetScript("OnClick", function(self)
	settings().panelHighlights = self:GetChecked() and true or false
	O:RefreshHlControls()
	if BossPrepHighlight then BossPrepHighlight:Refresh() end
end)
O.cbHighlights.Refresh = function(self)
	self:SetChecked(settings().panelHighlights ~= false)
end

local hlStyleLabel = T.FontString(frame, 10, "textDim", "")
hlStyleLabel:SetPoint("TOPLEFT", O.cbHighlights, "BOTTOMLEFT", 0, -12)
hlStyleLabel:SetText("STYLE")

O.hlStyleDropdown = T.Dropdown(frame, 196, function(value)
	settings().highlightStyle = value
	if BossPrepHighlight then BossPrepHighlight:Refresh() end
end)
O.hlStyleDropdown:SetPoint("TOPLEFT", hlStyleLabel, "BOTTOMLEFT", 0, -6)
O.hlStyleDropdown:SetOptions({
	{ text = "Soft wash", value = "WASH" },
	{ text = "Outline", value = "OUTLINE" },
	{ text = "Wash + outline", value = "BOTH" },
})

O.cbHlPulse = T.Checkbox(frame, "Gently pulse the target")
O.cbHlPulse:SetPoint("TOPLEFT", O.hlStyleDropdown, "BOTTOMLEFT", 0, -12)
O.cbHlPulse:SetScript("OnClick", function(self)
	settings().highlightPulse = self:GetChecked() and true or false
	if BossPrepHighlight then BossPrepHighlight:Refresh() end
end)
O.cbHlPulse.Refresh = function(self)
	self:SetChecked(settings().highlightPulse ~= false)
end

local hlIntLabel = T.FontString(frame, 10, "textDim", "")
hlIntLabel:SetPoint("TOPLEFT", O.cbHlPulse, "BOTTOMLEFT", 0, -14)
hlIntLabel:SetText("INTENSITY")

O.hlIntensitySlider = T.Slider(frame, 0, 100, 5)
O.hlIntensitySlider:SetPoint("TOPLEFT", hlIntLabel, "BOTTOMLEFT", 2, -10)
O.hlIntensitySlider:SetPoint("RIGHT", frame, "RIGHT", -24, 0)
O.hlIntensitySlider.format = function(v) return math.floor(v + 0.5) .. "%" end
O.hlIntensitySlider.onChange = function(v)
	settings().highlightIntensity = math.floor(v + 0.5)
	if BossPrepHighlight then BossPrepHighlight:Refresh() end
end

-------------------------------------------------
-- Other toggles
-------------------------------------------------
local otherDivider = T.Divider(frame)
otherDivider:SetPoint("TOPLEFT", 14, -339)
otherDivider:SetPoint("TOPRIGHT", -14, -339)

local otherHeader = T.SectionHeader(frame, "General")
otherHeader:SetPoint("TOPLEFT", 18, -353)

local function MakeToggle(labelText, yOff, key, onChange)
	local cb = T.Checkbox(frame, labelText)
	cb:SetPoint("TOPLEFT", otherHeader, "BOTTOMLEFT", 0, yOff)
	cb:SetScript("OnClick", function(self)
		settings()[key] = self:GetChecked() and true or false
		if onChange then onChange() end
	end)
	cb.Refresh = function(self)
		self:SetChecked(settings()[key] and true or false)
	end
	return cb
end

O.cbAlerts    = MakeToggle("Show on-screen alerts", -12, "alertsEnabled")
O.cbPanelBtn  = MakeToggle("Prepared button on the talent panel", -38, "panelButton", function()
	if BossPrepPanelButton then BossPrepPanelButton:Refresh() end
end)
O.cbReset     = MakeToggle("Reset tracking when I leave the raid", -64, "resetOnLeaveInstance")

-------------------------------------------------
-- Refresh
-------------------------------------------------
function O:RefreshHlControls()
	local on = settings().panelHighlights ~= false
	local a = on and 1 or 0.35
	for _, w in ipairs({ self.hlStyleDropdown, self.cbHlPulse, self.hlIntensitySlider }) do
		w:SetAlpha(a)
		w:EnableMouse(on)
	end
end

-- Lays out the conditional blocks top-to-bottom under the mode dropdown:
-- sound-effect picker + note-delay slider (SOUND mode only), then the TTS
-- voice/volume block (whenever TTS is available, independent of mode - boss
-- notes speak through it regardless of the chosen alert sound), then the
-- "Minimal alerts" checkbox (TTS mode only - it only affects the loadout
-- phrase).
function O:RefreshCueControls()
	local mode = settings().alertSoundMode or "SOUND"
	local hasTTS = BossPrepSound.HasTTS()

	local anchor, offset = self.modeDropdown, -16

	local soundShown = (mode == "SOUND")
	soundLabel:SetShown(soundShown)
	self.soundDropdown:SetShown(soundShown)
	delayLabel:SetShown(soundShown)
	self.delaySlider:SetShown(soundShown)
	if soundShown then
		soundLabel:ClearAllPoints()
		soundLabel:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, offset)
		self.soundDropdown:ClearAllPoints()
		self.soundDropdown:SetPoint("TOPLEFT", soundLabel, "BOTTOMLEFT", 0, -6)
		delayLabel:ClearAllPoints()
		delayLabel:SetPoint("TOPLEFT", self.soundDropdown, "BOTTOMLEFT", 0, -16)
		self.delaySlider:ClearAllPoints()
		self.delaySlider:SetPoint("TOPLEFT", delayLabel, "BOTTOMLEFT", 2, -10)
		self.delaySlider:SetPoint("RIGHT", frame, "LEFT", 228, 0)
		anchor, offset = self.delaySlider, -18
	end

	self.ttsMissing:SetShown(not hasTTS)
	voiceLabel:SetShown(hasTTS)
	self.voiceDropdown:SetShown(hasTTS)
	self.volumeLabel:SetShown(hasTTS)
	self.volumeSlider:SetShown(hasTTS)
	if hasTTS then
		voiceLabel:ClearAllPoints()
		voiceLabel:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, offset)
		self.voiceDropdown:ClearAllPoints()
		self.voiceDropdown:SetPoint("TOPLEFT", voiceLabel, "BOTTOMLEFT", 0, -6)
		self.volumeLabel:ClearAllPoints()
		self.volumeLabel:SetPoint("TOPLEFT", self.voiceDropdown, "BOTTOMLEFT", 0, -18)
		self.volumeSlider:ClearAllPoints()
		self.volumeSlider:SetPoint("TOPLEFT", self.volumeLabel, "BOTTOMLEFT", 2, -10)
		self.volumeSlider:SetPoint("RIGHT", frame, "LEFT", 228, 0)
		anchor, offset = self.volumeSlider, -18
	else
		self.ttsMissing:ClearAllPoints()
		self.ttsMissing:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, offset)
		self.ttsMissing:SetPoint("RIGHT", frame, "LEFT", 230, 0)
		anchor, offset = self.ttsMissing, -14
	end

	local minimalShown = (mode == "TTS") and hasTTS
	self.cbTtsMinimal:SetShown(minimalShown)
	if minimalShown then
		self.cbTtsMinimal:ClearAllPoints()
		self.cbTtsMinimal:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", -2, offset)
		anchor, offset = self.cbTtsMinimal, -14
	end

	self.testCueBtn:ClearAllPoints()
	self.testCueBtn:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 2, offset)
end

function O:Refresh()
	local s = settings()

	local mode = s.alertSoundMode or "SOUND"
	local modeText = ({ NONE = "No sound", SOUND = "Sound effect", TTS = "Text-to-speech" })[mode]
	self.modeDropdown:SetSelected(mode, modeText)

	local soundOpts = {}
	for _, snd in ipairs(BossPrepSound.GetAllSounds()) do
		table.insert(soundOpts, { text = snd.label, value = snd.key })
	end
	self.soundDropdown:SetOptions(soundOpts)
	local snd = BossPrepSound.GetSound(s.alertSoundKey)
	self.soundDropdown:SetSelected(snd and snd.key, snd and snd.label or "(pick one)")
	self.delaySlider:SetValueSilent(tonumber(s.noteAnnounceDelay) or 1.5)

	local voiceOpts, selName = {}, nil
	for _, v in ipairs(BossPrepSound.GetVoices()) do
		table.insert(voiceOpts, { text = v.name, value = v.voiceID })
		if v.voiceID == s.ttsVoiceID then selName = v.name end
	end
	self.voiceDropdown:SetOptions(voiceOpts)
	if s.ttsVoiceID ~= nil and selName then
		self.voiceDropdown:SetSelected(s.ttsVoiceID, selName)
	else
		self.voiceDropdown:SetSelected(s.ttsVoiceID, voiceOpts[1] and (voiceOpts[1].text .. " (default)") or "(no voices)")
	end

	self.volumeSlider:SetValueSilent(s.ttsVolume or 100)
	self.cbTtsMinimal:SetChecked(s.ttsMinimal and true or false)

	self.cbAlerts:Refresh()
	self.cbPanelBtn:Refresh()
	self.cbReset:Refresh()

	self.cbHighlights:Refresh()
	self.cbHlPulse:Refresh()
	local hs = s.highlightStyle or "WASH"
	local hsText = ({ WASH = "Soft wash", OUTLINE = "Outline", BOTH = "Wash + outline" })[hs] or "Soft wash"
	self.hlStyleDropdown:SetSelected(hs, hsText)
	self.hlIntensitySlider:SetValueSilent(type(s.highlightIntensity) == "number" and s.highlightIntensity or 55)
	self:RefreshHlControls()

	self:RefreshCueControls()
end

function O:Toggle()
	if frame:IsShown() then
		frame:Hide()
		return
	end
	self:Refresh()
	frame:Show()
	frame:Raise()
end
