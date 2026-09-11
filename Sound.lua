-- Sound.lua
-- Audio cue for the alert banner: a chosen sound effect, or text-to-speech
-- that names which categories of your loadout need switching.

BossPrepSound = {}
local S = BossPrepSound

-------------------------------------------------
-- Sound effects (raw SoundKit IDs - stable across the Classic clients)
-------------------------------------------------
S.SOUNDS = {
	{ key = "RAID_WARNING",   label = "Raid warning",   id = 8959 },
	{ key = "READY_CHECK",    label = "Ready check",     id = 8960 },
	{ key = "ALARM_CLOCK",    label = "Alarm clock",     id = 12889 },
	{ key = "MAP_PING",       label = "Map ping",        id = 3175 },
	{ key = "QUEST_COMPLETE", label = "Quest complete",  id = 878 },
	{ key = "INVITE_CHIME",   label = "Invite chime",    id = 880 },
	{ key = "PVP_QUEUE",      label = "PvP queue pop",   id = 8458 },
}

-- Optional: LibSharedMedia-3.0, if some other addon on this account has it
-- loaded. It's a shared registry that any addon can register sound files
-- into, so this pulls in whatever custom alert sounds the user's other
-- addons (raid tools, sound packs, etc.) have already contributed - no
-- bundling of our own copy required.
local function getLSM()
	return LibStub and LibStub:GetLibrary("LibSharedMedia-3.0", true)
end

-- Combined list of built-in SoundKit effects plus anything LibSharedMedia
-- knows about. LSM entries are file-based (played with PlaySoundFile), so
-- they carry `file` instead of `id`.
function S.GetAllSounds()
	local list = {}
	for _, s in ipairs(S.SOUNDS) do table.insert(list, s) end

	local LSM = getLSM()
	if LSM then
		local tbl = LSM:HashTable(LSM.MediaType.SOUND)
		local names = {}
		for name in pairs(tbl) do
			if name ~= "None" then table.insert(names, name) end
		end
		table.sort(names)
		for _, name in ipairs(names) do
			table.insert(list, { key = "LSM:" .. name, label = name, file = tbl[name] })
		end
	end

	return list
end

-- Preferred default when the user hasn't explicitly picked a sound: Illidan's
-- "You are not prepared!" line, if some other addon's LibSharedMedia
-- registration happens to provide it. Matched loosely since different addons
-- register it under slightly different names.
local function isIllidanNotPrepared(label)
	if not label then return false end
	local l = label:lower()
	return l:find("illidan", 1, true) and l:find("prepared", 1, true)
end

function S.DefaultSoundKey()
	for _, s in ipairs(S.GetAllSounds()) do
		if isIllidanNotPrepared(s.label) then return s.key end
	end
	return "RAID_WARNING"
end

function S.GetSound(key)
	local all = S.GetAllSounds()
	for _, s in ipairs(all) do
		if key and s.key == key then return s end
	end
	local defKey = S.DefaultSoundKey()
	for _, s in ipairs(all) do
		if s.key == defKey then return s end
	end
	return all[1]
end

function S.PlaySound(key)
	local s = S.GetSound(key)
	if not s then return false end
	-- PlaySound(File) -> willPlay, soundHandle; keep the handle so StopCue can kill it
	local ok, willPlay, handle
	if s.file then
		ok, willPlay, handle = pcall(PlaySoundFile, s.file, "Master")
	else
		ok, willPlay, handle = pcall(PlaySound, s.id, "Master", false)
		if not ok then
			ok, willPlay, handle = pcall(PlaySound, s.id)
		end
	end
	S.lastHandle = ok and handle or nil
	return ok and willPlay ~= false
end

-------------------------------------------------
-- Text-to-speech
-------------------------------------------------
function S.HasTTS()
	return (C_VoiceChat and C_VoiceChat.SpeakText and C_VoiceChat.GetTtsVoices) and true or false
end

-- List of { voiceID = number, name = string }. Cached after the first
-- successful enumeration - GetTtsVoices() can come back empty on later calls
-- before the engine has re-enumerated.
function S.GetVoices()
	if not (C_VoiceChat and C_VoiceChat.GetTtsVoices) then return {} end
	local ok, voices = pcall(C_VoiceChat.GetTtsVoices)
	if ok and type(voices) == "table" and #voices > 0 then
		S.voiceCache = voices
	end
	return S.voiceCache or {}
end

local function resolveVoiceID()
	local s = BossPrepDB and BossPrepDB.settings or {}
	if s.ttsVoiceID ~= nil then
		-- make sure it still exists
		for _, v in ipairs(S.GetVoices()) do
			if v.voiceID == s.ttsVoiceID then return s.ttsVoiceID end
		end
	end
	local voices = S.GetVoices()
	return voices[1] and voices[1].voiceID or nil
end

function S.Speak(text)
	if not S.HasTTS() or not text or text == "" then return false end

	local voiceID = resolveVoiceID()
	if voiceID == nil then return false end

	local s = BossPrepDB and BossPrepDB.settings or {}
	local rate = 0
	if C_TTSSettings and C_TTSSettings.GetSpeechRate then
		local r = C_TTSSettings.GetSpeechRate()
		if type(r) == "number" then rate = r end
	end
	local volume = s.ttsVolume or 100

	-- Don't call StopSpeakingText() here - doing so immediately before
	-- SpeakText() can leave the TTS engine in a state where every later
	-- SpeakText() is silently dropped (the "speaks once, then never again"
	-- bug). Interrupting is only done from StopCue() on banner dismiss.
	-- Classic signature: SpeakText(voiceID, text, rate, volume, overlap)
	local ok, err = pcall(C_VoiceChat.SpeakText, voiceID, text, rate, volume, false)
	if ok then
		S.lastSpeakAt = GetTime()
	elseif BossPrepDB and BossPrepDB.settings and BossPrepDB.settings.debug then
		print("|cff33ff99Prepared|r TTS error: " .. tostring(err))
	end
	return ok
end

-------------------------------------------------
-- Turn a list of Diff problems ({ cat=, text= }) into a spoken phrase.
-------------------------------------------------
local CAT_ORDER = { "spec", "talent", "glyph", "gear", "cloak", "trinket" }
local CAT_WORD = {
	spec    = "spec",
	talent  = "talents",
	glyph   = "glyphs",
	gear    = "gear set",
	cloak   = "cloak",
	trinket = "trinkets",
}

function S.ProblemPhrase(problems)
	local seen = {}
	for _, p in ipairs(problems or {}) do
		if type(p) == "table" and p.cat then seen[p.cat] = true end
	end

	local parts = {}
	for _, c in ipairs(CAT_ORDER) do
		if seen[c] then table.insert(parts, CAT_WORD[c]) end
	end

	if #parts == 0 then return "Check your setup" end

	local joined
	if #parts == 1 then
		joined = parts[1]
	elseif #parts == 2 then
		joined = parts[1] .. " and " .. parts[2]
	else
		joined = table.concat(parts, ", ", 1, #parts - 1) .. ", and " .. parts[#parts]
	end
	return "Switch " .. joined
end

-------------------------------------------------
-- The cue itself - called by Alert:Show when the banner first appears.
-------------------------------------------------
-- Strip UI escape sequences so TTS doesn't read "pipe c f f..." aloud.
local function plain(text)
	if not text then return nil end
	text = text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
	text = text:gsub("|H.-|h(.-)|h", "%1"):gsub("|T.-|t", "")
	return text
end

-- `note` (optional): the per-boss note to speak (the caller passes it only
-- when its own "announce" checkbox is on). Note speech always goes through
-- TTS regardless of the chosen alert-sound mode - that's why the voice and
-- volume options in the settings panel apply no matter which sound mode is
-- selected as the main cue. In TTS mode the note is folded into the same
-- phrase as the loadout problems instead of being spoken twice.
function S.PlayCue(problems, note)
	local s = BossPrepDB and BossPrepDB.settings or {}
	local mode = s.alertSoundMode or "SOUND"
	note = plain(note)
	local hasNote = note and note ~= ""

	if mode == "NONE" then
		if hasNote then S.Speak(note) end
		return
	elseif mode == "TTS" and S.HasTTS() then
		local hasProblems = problems and #problems > 0
		if not hasProblems and not hasNote then return end -- nothing to say
		local phrase
		if hasProblems then
			phrase = s.ttsMinimal and "Changes required" or S.ProblemPhrase(problems)
		end
		if hasNote then
			phrase = phrase and (phrase .. ". " .. note) or note
		end
		S.Speak(phrase)
	else
		S.PlaySound(s.alertSoundKey)
		if hasNote then S.Speak(note) end
	end
end

-- Stop whatever the cue is currently playing (sound effect or speech).
-- Called when the alert banner is dismissed.
function S.StopCue()
	if S.lastHandle and StopSound then
		pcall(StopSound, S.lastHandle)
	end
	S.lastHandle = nil
	-- Only interrupt speech that could still be playing - calling
	-- StopSpeakingText when nothing is speaking has been flaky.
	if C_VoiceChat and C_VoiceChat.StopSpeakingText
		and S.lastSpeakAt and (GetTime() - S.lastSpeakAt) < 12 then
		pcall(C_VoiceChat.StopSpeakingText)
		S.lastSpeakAt = nil
	end
end

-- Preview for the options panel: plays the configured cue with a sample of
-- every category so TTS says a full sentence.
function S.TestCue()
	local sample = {
		{ cat = "spec" }, { cat = "talent" }, { cat = "glyph" },
	}
	S.PlayCue(sample)
end
