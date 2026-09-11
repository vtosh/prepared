-- Core.lua
BossPrep = CreateFrame("Frame", "BossPrepFrame")
BossPrep.eventHandlers = {}

function BossPrep:On(event, fn)
	if not self.eventHandlers[event] then
		self.eventHandlers[event] = {}
		-- Some events differ (or don't exist) across client builds; never
		-- let one bad RegisterEvent call take the whole addon down.
		local ok = pcall(self.RegisterEvent, self, event)
		if not ok then
			self.eventHandlers[event] = nil
			return
		end
	end
	table.insert(self.eventHandlers[event], fn)
end

BossPrep:SetScript("OnEvent", function(self, event, ...)
	local handlers = self.eventHandlers[event]
	if not handlers then return end
	for _, fn in ipairs(handlers) do
		fn(...)
	end
end)

-------------------------------------------------
-- SavedVariables bootstrap
-------------------------------------------------
-- BossPrepDB layout:
-- BossPrepDB.chars["Name-Realm"] = {
--   activeProfile = "profile1",         -- which profile drives detection
--   nextProfileId = 3,
--   profiles = {
--    ["profile1"] = {
--     name = "Default", order = 1,
--     bossSource = { [instanceKey] = { [bossKey] = "profile2" } },  -- redirect: this
--                                     -- boss uses that profile's whole setup + trigger
--     data = {                          -- the loadout store for this profile:
--   __global = {                       -- profile-wide default loadout (no trigger).
--     equipmentSet, specGroup, specID, specName,
--     talents = { [tier]=col }, talentNames = { [tier]="Name" },
--     glyphs  = { [slot] = {..} or false },
--     trinkets = { [slot] = { itemID=.. } },
--     savedAt,
--   },
--   [instanceKey] = {
--     [bossKey] = {
--       trigger      = { type = "TARGET|ZONE|KILL", ... },  -- per-boss only
--       -- every loadout field below is OPTIONAL; when absent the boss
--       -- inherits the matching __global value.
--       equipmentSet = "SetName" or nil,
--       specGroup    = 1,
--       specID       = 12345,
--       specName     = "Fire",
--       talents      = { [1]=col, [2]=col, ... },
--       talentNames  = { [1]="Name", ... },   -- display only
--       glyphs       = { [slot] = { spellID=.., name=.. } or false },
--       trinkets     = { [slot] = { itemID=.. } },
--       cleared      = {                      -- "override to nothing" markers
--         equipmentSet=true, spec=true,
--         talents={[tier]=true}, glyphs={[slot]=true}, trinkets={[slot]=true},
--       },
--       savedAt      = time(),
--     }
--   }
--     },
--    },
--   },
-- }

local function GetCharKey()
	local name = UnitName("player") or "Unknown"
	local realm = GetRealmName() or "UnknownRealm"
	return name .. "-" .. realm
end
BossPrep.GetCharKey = GetCharKey

local function EnsureDB()
	BossPrepDB = BossPrepDB or {}
	BossPrepDB.chars = BossPrepDB.chars or {}
	local defaultSettings = {
		alertsEnabled = true,
		panelHighlights = true,        -- highlight the talent/glyph panels while a banner is up
		highlightStyle = "WASH",       -- "WASH" | "OUTLINE" | "BOTH"
		highlightIntensity = 55,       -- 0-100
		highlightPulse = true,         -- gently breathe the "switch to this" marker
		panelButton = true,            -- BossPrep badge on the talent/glyph panel
		resetOnLeaveInstance = true,   -- clear tracked boss when you leave the raid
		alertSoundMode = "SOUND",      -- "NONE" | "SOUND" | "TTS"
		-- alertSoundKey is intentionally absent here: leaving it nil lets
		-- BossPrepSound.GetSound() pick "Illidan: Not Prepared" as the default
		-- whenever some other addon's LibSharedMedia registration provides it,
		-- falling back to the raid-warning SoundKit otherwise. It's only ever
		-- written once the user actually picks something (see the migration
		-- below, and Options.lua's soundDropdown, which sets
		-- alertSoundKeyChosen alongside it).
		ttsVoiceID = nil,              -- nil = first available voice
		ttsVolume = 100,               -- 0-100
		ttsMinimal = false,            -- TTS says just "Changes required" instead of listing categories
	}
	BossPrepDB.settings = BossPrepDB.settings or {}
	for key, value in pairs(defaultSettings) do
		if BossPrepDB.settings[key] == nil then
			BossPrepDB.settings[key] = value
		end
	end

	-- One-time migration: versions before the dynamic default baked
	-- "RAID_WARNING" into every save file. If the user never explicitly chose
	-- a sound (alertSoundKeyChosen unset), clear it so the dynamic default
	-- can take over; a real explicit choice (even of "Raid warning" itself)
	-- is marked chosen and is never touched again.
	if BossPrepDB.settings.alertSoundKey == "RAID_WARNING" and not BossPrepDB.settings.alertSoundKeyChosen then
		BossPrepDB.settings.alertSoundKey = nil
	end

	local key = GetCharKey()
	BossPrepDB.chars[key] = BossPrepDB.chars[key] or {}
	return BossPrepDB
end

BossPrep:On("ADDON_LOADED", function(addonName)
	if addonName ~= "Prepared" then return end
	EnsureDB()
	print("|cff33ff99Prepared|r loaded. Type |cffffffff/prep|r to open, |cffffffff/prep check|r to check now, or |cffffffff/prep target|r to see the exact name to put in a boss's data entry.")
end)

BossPrep.EnsureDB = EnsureDB

-------------------------------------------------
-- Slash commands
-------------------------------------------------
SLASH_BOSSPREP1 = "/prepared"
SLASH_BOSSPREP2 = "/prep"
SlashCmdList["BOSSPREP"] = function(msg)
	msg = (msg or ""):lower():trim()

	if msg == "check" then
		BossPrepDetection:CheckNow(true)
	elseif msg == "target" then
		local name = UnitExists("target") and UnitName("target")
		if name then
			print("|cff33ff99Prepared|r current target name: '" .. name .. "' -- this is the exact string a boss's `name` (or `targetNames` alias) needs to match.")
		else
			print("|cff33ff99Prepared|r you have no target selected.")
		end
	elseif msg == "subzone" then
		print("|cff33ff99Prepared|r current sub-zone text: '" .. tostring(GetSubZoneText()) .. "' -- this is what a boss's `subZone` field needs to match.")
	elseif msg == "hl" then
		if BossPrepHighlight then
			BossPrepHighlight:Debug()
		else
			print("|cff33ff99Prepared|r Highlight.lua did NOT load. Check that the file is in your AddOns\\Prepared\\ folder and that there's no Lua error (/console scriptErrors 1, then /reload).")
		end
	elseif msg == "micro" then
		local tmb = _G.TalentMicroButton
		print("|cff33ff99Prepared|r micro-button probe:")
		print("  TalentMicroButton: " .. (tmb and "exists" or "MISSING"))
		if tmb then
			print(("    enabled=%s  shown=%s  visible=%s  mouse=%s")
				:format(tostring(tmb:IsEnabled()), tostring(tmb:IsShown()),
					tostring(tmb:IsVisible()), tostring(tmb:IsMouseEnabled())))
			print("    parent: " .. (tmb:GetParent() and (tmb:GetParent():GetName() or "(unnamed)") or "nil"))
			print("    OnClick script: " .. (tmb:GetScript("OnClick") and "set" or "NONE"))
		end
		print("  PlayerTalentFrame: " .. (_G.PlayerTalentFrame and "loaded" or "not loaded"))
		print("  ElvUI: " .. ((_G.ElvUI or _G.ElvPrivateDB) and "yes" or "no"))
		print("  Now type this straight into chat and hit Enter:  |cffffffff/click TalentMicroButton|r")
	elseif msg == "debug" then
		BossPrepDB.settings.debug = not BossPrepDB.settings.debug
		print("|cff33ff99Prepared|r debug mode: " .. tostring(BossPrepDB.settings.debug))
	else
		BossPrepUI:Toggle()
	end
end
