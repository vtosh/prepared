-- Profiles.lua
BossPrepProfiles = {}
local P = BossPrepProfiles

-- Reserved key inside a character's table for the character-wide "global
-- default" loadout. Anything that iterates a char table must skip it.
local GLOBAL_KEY = "__global"

local function deepcopy(t)
	if type(t) ~= "table" then return t end
	local r = {}
	for k, v in pairs(t) do r[k] = deepcopy(v) end
	return r
end

function P:GetCharData(charKey)
	BossPrep.EnsureDB()
	charKey = charKey or BossPrep.GetCharKey()
	BossPrepDB.chars[charKey] = BossPrepDB.chars[charKey] or {}
	return BossPrepDB.chars[charKey]
end

-------------------------------------------------
-- Profiles: each character has one or more named profiles, each holding its
-- own Global Default + per-boss setups. One is "active" and drives detection.
-- `cd.profiles[id].data` has the exact shape the whole char table used to have
-- (a __global key + [instanceKey][bossKey] setups), so the accessors below
-- just scope themselves to one profile.
-------------------------------------------------
-- Lazily upgrades a pre-profiles char table and repairs a dangling active id.
local function ensureProfiles(cd)
	if not cd.profiles then
		local moved = {}
		for k in pairs(cd) do moved[k] = cd[k]; cd[k] = nil end
		cd.profiles = {
			profile1 = { name = "Default", order = 1, data = moved, bossSource = {} },
		}
		cd.activeProfile = "profile1"
		cd.nextProfileId = 2
	end
	if not (cd.activeProfile and cd.profiles[cd.activeProfile]) then
		cd.activeProfile = next(cd.profiles)
	end
	return cd
end

function P:GetActiveProfileId(charKey)
	return ensureProfiles(self:GetCharData(charKey)).activeProfile
end

function P:GetActiveProfile(charKey)
	local cd = ensureProfiles(self:GetCharData(charKey))
	return cd.profiles[cd.activeProfile]
end

function P:GetProfile(charKey, profileId)
	local cd = ensureProfiles(self:GetCharData(charKey))
	return cd.profiles[profileId or cd.activeProfile]
end

-- The old "char data" surface (a __global key + instance tables), scoped to
-- one profile (the active one unless profileId is given).
function P:GetProfileData(charKey, profileId)
	local prof = self:GetProfile(charKey, profileId) or self:GetActiveProfile(charKey)
	prof.data = prof.data or {}
	return prof.data
end

function P:SetActiveProfile(charKey, profileId)
	local cd = ensureProfiles(self:GetCharData(charKey))
	if cd.profiles[profileId] then cd.activeProfile = profileId end
end

-- Sorted list: { { id=, name=, order=, active=bool }, ... }
function P:GetProfiles(charKey)
	local cd = ensureProfiles(self:GetCharData(charKey))
	local list = {}
	for id, prof in pairs(cd.profiles) do
		list[#list + 1] = {
			id = id, name = prof.name or id,
			order = prof.order or 99, active = (id == cd.activeProfile),
		}
	end
	table.sort(list, function(a, b)
		if a.order ~= b.order then return a.order < b.order end
		return (a.name or "") < (b.name or "")
	end)
	return list
end

function P:CreateProfile(charKey, name)
	local cd = ensureProfiles(self:GetCharData(charKey))
	local id = "profile" .. (cd.nextProfileId or 1)
	cd.nextProfileId = (cd.nextProfileId or 1) + 1
	local maxOrder = 0
	for _, prof in pairs(cd.profiles) do maxOrder = math.max(maxOrder, prof.order or 0) end
	cd.profiles[id] = { name = name or "Profile", order = maxOrder + 1, data = {}, bossSource = {} }
	return id
end

function P:RenameProfile(charKey, profileId, name)
	local prof = self:GetProfile(charKey, profileId)
	if prof and name and name ~= "" then prof.name = name end
end

function P:DuplicateProfile(charKey, profileId)
	local cd = ensureProfiles(self:GetCharData(charKey))
	local src = cd.profiles[profileId]
	if not src then return nil end
	local id = self:CreateProfile(charKey, (src.name or "Profile") .. " copy")
	cd.profiles[id].data = deepcopy(src.data or {})
	cd.profiles[id].bossSource = deepcopy(src.bossSource or {})
	return id
end

-- Deletes a profile. Refuses the last one. Any OTHER profile's per-boss
-- redirect that pointed here is cleared (that boss reverts to its own setup).
-- If the active profile is deleted, another becomes active.
function P:DeleteProfile(charKey, profileId)
	local cd = ensureProfiles(self:GetCharData(charKey))
	if not cd.profiles[profileId] then return false, "no such profile" end
	local count = 0
	for _ in pairs(cd.profiles) do count = count + 1 end
	if count <= 1 then return false, "can't delete your only profile" end

	cd.profiles[profileId] = nil
	if cd.activeProfile == profileId then cd.activeProfile = next(cd.profiles) end

	for _, prof in pairs(cd.profiles) do
		if prof.bossSource then
			for ik, bosses in pairs(prof.bossSource) do
				for bk, target in pairs(bosses) do
					if target == profileId then bosses[bk] = nil end
				end
				if next(bosses) == nil then prof.bossSource[ik] = nil end
			end
		end
	end
	return true
end

-------------------------------------------------
-- Copy another profile's set(s) INTO the active profile as independent copies
-- (not a live borrow). Backs the detail panel's "Copy from" control.
-------------------------------------------------

-- Copy `fromProfileId`'s Global Default set over the active profile's.
function P:CopyGlobalSetupFrom(fromProfileId, charKey)
	if not self:GetProfile(charKey, fromProfileId) then return false end
	if fromProfileId == self:GetActiveProfileId(charKey) then return false end
	local src = self:GetGlobalSetup(charKey, fromProfileId)
	self:GetProfileData(charKey)[GLOBAL_KEY] = src and deepcopy(src) or nil
	return true
end

-- Copy `fromProfileId`'s setup for one boss (loadout + trigger) into the active
-- profile, replacing whatever's there, and drop any redirect for that boss so
-- the copy is what shows. Returns (ok, copiedSomething) - copiedSomething is
-- false when the source profile has no per-boss set for that boss.
function P:CopyBossSetupFrom(instanceKey, bossKey, fromProfileId, charKey)
	if not self:GetProfile(charKey, fromProfileId) then return false, false end
	if fromProfileId == self:GetActiveProfileId(charKey) then return false, false end
	local src = self:GetBossSetup(instanceKey, bossKey, charKey, fromProfileId)
	if not src then return true, false end
	self:SetBossSetup(instanceKey, bossKey, deepcopy(src), charKey)
	self:SetBossSource(instanceKey, bossKey, nil, charKey)
	return true, true
end

-------------------------------------------------
-- Per-boss "use another profile's setup for this boss" redirect, stored on
-- the active profile's bossSource map.
-------------------------------------------------
function P:GetBossSource(instanceKey, bossKey, charKey)
	local m = self:GetActiveProfile(charKey).bossSource
	return m and m[instanceKey] and m[instanceKey][bossKey]
end

function P:SetBossSource(instanceKey, bossKey, targetProfileId, charKey)
	local prof = self:GetActiveProfile(charKey)
	prof.bossSource = prof.bossSource or {}
	if targetProfileId then
		prof.bossSource[instanceKey] = prof.bossSource[instanceKey] or {}
		prof.bossSource[instanceKey][bossKey] = targetProfileId
	elseif prof.bossSource[instanceKey] then
		prof.bossSource[instanceKey][bossKey] = nil
		if next(prof.bossSource[instanceKey]) == nil then prof.bossSource[instanceKey] = nil end
	end
end

-------------------------------------------------
-- Per-boss setup storage (scoped to a profile's data table)
-------------------------------------------------
function P:GetBossSetup(instanceKey, bossKey, charKey, profileId)
	local data = self:GetProfileData(charKey, profileId)
	data[instanceKey] = data[instanceKey] or {}
	return data[instanceKey][bossKey] -- may be nil if never configured
end

function P:SetBossSetup(instanceKey, bossKey, setup, charKey)
	local data = self:GetProfileData(charKey)
	data[instanceKey] = data[instanceKey] or {}
	data[instanceKey][bossKey] = setup
end

function P:DeleteBossSetup(instanceKey, bossKey, charKey)
	local data = self:GetProfileData(charKey)
	if data[instanceKey] then
		data[instanceKey][bossKey] = nil
	end
end

-- Returns the setup table for this boss, creating a minimal one (just a
-- default trigger) if none exists yet. The returned table is the actual
-- stored table (not a copy) - callers may mutate it directly, but should
-- prefer the Set* helpers below for clarity.
function P:EnsureSetup(instanceKey, bossKey, charKey)
	local setup = self:GetBossSetup(instanceKey, bossKey, charKey)
	if not setup then
		setup = { trigger = BossPrepData:GetDefaultTrigger(instanceKey, bossKey) }
		self:SetBossSetup(instanceKey, bossKey, setup, charKey)
	end
	setup.trigger = setup.trigger or BossPrepData:GetDefaultTrigger(instanceKey, bossKey)
	return setup
end

-------------------------------------------------
-- Character-wide "global default" loadout. Same shape as a per-boss setup
-- minus the trigger; every boss inherits these values for any loadout field
-- it doesn't override.
-------------------------------------------------
function P:GetGlobalSetup(charKey, profileId)
	return self:GetProfileData(charKey, profileId)[GLOBAL_KEY]
end

function P:EnsureGlobalSetup(charKey)
	local data = self:GetProfileData(charKey)
	data[GLOBAL_KEY] = data[GLOBAL_KEY] or {}
	return data[GLOBAL_KEY]
end

function P:DeleteGlobalSetup(charKey)
	self:GetProfileData(charKey)[GLOBAL_KEY] = nil
end

-------------------------------------------------
-- "cleared" markers: a boss field that's been explicitly overridden to
-- *nothing* (as opposed to just left inheriting the global default).
-------------------------------------------------
local function clearClearedFlag(setup, kind, idx)
	local c = setup.cleared
	if not c then return end
	if kind == "equipmentSet" then c.equipmentSet = nil
	elseif kind == "spec" then c.spec = nil
	elseif kind == "cloak" then c.cloak = nil
	elseif kind == "talent" then if c.talents then c.talents[idx] = nil end
	elseif kind == "glyph" then if c.glyphs then c.glyphs[idx] = nil end
	elseif kind == "trinket" then if c.trinkets then c.trinkets[idx] = nil end
	end
end

local function setClearedFlag(setup, kind, idx)
	setup.cleared = setup.cleared or {}
	local c = setup.cleared
	if kind == "equipmentSet" then c.equipmentSet = true
	elseif kind == "spec" then c.spec = true
	elseif kind == "cloak" then c.cloak = true
	elseif kind == "talent" then c.talents = c.talents or {}; c.talents[idx] = true
	elseif kind == "glyph" then c.glyphs = c.glyphs or {}; c.glyphs[idx] = true
	elseif kind == "trinket" then c.trinkets = c.trinkets or {}; c.trinkets[idx] = true
	end
end

-------------------------------------------------
-- Granular field setters, for the click-a-slot-to-pick UI. Each works
-- standalone without requiring a full "Capture Current Setup". Writing a
-- real value also drops any "explicitly none" marker for that field.
-------------------------------------------------
function P:SetTrigger(instanceKey, bossKey, triggerTable, charKey)
	local setup = self:EnsureSetup(instanceKey, bossKey, charKey)
	setup.trigger = triggerTable
end

-- Per-character override for the ZONE trigger's sub-zone string. Pass nil to
-- clear it and fall back to the boss's data-file default.
function P:SetTriggerSubZone(instanceKey, bossKey, subZone, charKey)
	local setup = self:EnsureSetup(instanceKey, bossKey, charKey)
	setup.trigger = setup.trigger or { type = "ZONE" }
	setup.trigger.subZone = subZone
end

-------------------------------------------------
-- Per-boss free-text note (shown on the alert banner; also spoken by the TTS
-- cue, but only when its "announce" box is checked -> setup.noteAnnounceTTS
-- = true. Off by default so new notes stay silent until opted in.
-------------------------------------------------
function P:SetBossNote(instanceKey, bossKey, text, charKey)
	local setup = self:EnsureSetup(instanceKey, bossKey, charKey)
	text = text and text:gsub("^%s+", ""):gsub("%s+$", "")
	setup.note = (text and text ~= "") and text or nil
end

function P:SetBossNoteAnnounceTTS(instanceKey, bossKey, announce, charKey)
	local setup = self:EnsureSetup(instanceKey, bossKey, charKey)
	setup.noteAnnounceTTS = announce and true or nil
end

-- Returns (note, announceTTS) for the boss under the active profile. A
-- redirected boss with no note of its own falls back to the source profile's
-- note.
function P:GetBossNote(instanceKey, bossKey, charKey)
	local setup = self:GetBossSetup(instanceKey, bossKey, charKey)
	if setup and setup.note and setup.note ~= "" then
		return setup.note, setup.noteAnnounceTTS and true or false
	end
	local srcId = self:GetBossSource(instanceKey, bossKey, charKey)
	if srcId and srcId ~= self:GetActiveProfileId(charKey) then
		local s = self:GetBossSetup(instanceKey, bossKey, charKey, srcId)
		if s and s.note and s.note ~= "" then
			return s.note, s.noteAnnounceTTS and true or false
		end
	end
	return nil, false
end

function P:SetEquipmentSetChoice(instanceKey, bossKey, setName, charKey)
	local setup = self:EnsureSetup(instanceKey, bossKey, charKey)
	setup.equipmentSet = setName
	clearClearedFlag(setup, "equipmentSet")
end

function P:SetSpecChoice(instanceKey, bossKey, specID, specName, charKey)
	local setup = self:EnsureSetup(instanceKey, bossKey, charKey)
	setup.specID = specID
	setup.specName = specName
	clearClearedFlag(setup, "spec")
end

function P:SetCloakChoice(instanceKey, bossKey, choiceOrNil, charKey)
	local setup = self:EnsureSetup(instanceKey, bossKey, charKey)
	setup.cloak = choiceOrNil
	if choiceOrNil then clearClearedFlag(setup, "cloak") end
end

function P:SetTalentTierChoice(instanceKey, bossKey, tier, column, talentName, charKey)
	local setup = self:EnsureSetup(instanceKey, bossKey, charKey)
	setup.talents = setup.talents or {}
	setup.talentNames = setup.talentNames or {}
	setup.talents[tier] = column
	setup.talentNames[tier] = talentName
	clearClearedFlag(setup, "talent", tier)
end

-- A given major glyph can only sit in one socket, so it must not appear in two
-- slots of a setup. After `keepSlot` was just set to `glyph`, walk the other
-- two slots: whichever currently *resolves* to that same glyph (its own stored
-- choice, or what it inherits from the base / global set) gets vacated - it
-- falls back to whatever the base set has for that slot, in slot order, and if
-- that's the same glyph again it goes to blank (`false`). Every slot's final
-- value is checked against the ones already kept, so no duplicate can survive.
local function dedupeGlyphSlots(self, instanceKey, bossKey, keepSlot, charKey)
	local setup = self:GetBossSetup(instanceKey, bossKey, charKey)
	if not (setup and setup.glyphs) then return end

	local _, _, _, base = self:ResolveBossLoadout(instanceKey, bossKey, charKey)
	local baseGlyphs = base and base.glyphs
	if not baseGlyphs then
		local g = self:GetGlobalSetup(charKey)
		baseGlyphs = g and g.glyphs
	end

	local M = BossPrepCompat.GlyphChoicesMatch
	local function taken(list, glyph)
		for _, u in ipairs(list) do if M(u, glyph) then return true end end
		return false
	end
	-- What slot `s` currently resolves to (stored table, or inherited), or nil.
	local function eff(s)
		local v = setup.glyphs[s]
		if type(v) == "table" then return v end
		if v == false then return nil end
		local inh = baseGlyphs and baseGlyphs[s]
		return type(inh) == "table" and inh or nil
	end

	local kept = {}
	local k = eff(keepSlot)
	if k then kept[#kept + 1] = k end

	for s = 1, 3 do
		if s ~= keepSlot then
			local cur = eff(s)
			if cur and taken(kept, cur) then
				local inh = baseGlyphs and baseGlyphs[s]
				if type(inh) == "table" and not taken(kept, inh) then
					setup.glyphs[s] = nil -- fall back to the inherited glyph
					clearClearedFlag(setup, "glyph", s)
					kept[#kept + 1] = inh
				else
					setup.glyphs[s] = false -- blank it
					setClearedFlag(setup, "glyph", s)
				end
			elseif cur then
				kept[#kept + 1] = cur
			end
		end
	end
end

function P:SetGlyphSlotChoice(instanceKey, bossKey, uiSlot, glyphOrFalse, charKey)
	local setup = self:EnsureSetup(instanceKey, bossKey, charKey)
	setup.glyphs = setup.glyphs or {}
	setup.glyphs[uiSlot] = glyphOrFalse
	if glyphOrFalse then clearClearedFlag(setup, "glyph", uiSlot) end
	if type(glyphOrFalse) == "table" then
		dedupeGlyphSlots(self, instanceKey, bossKey, uiSlot, charKey)
	end
end

function P:SetTrinketChoice(instanceKey, bossKey, uiSlot, choiceOrNil, charKey)
	local setup = self:EnsureSetup(instanceKey, bossKey, charKey)
	setup.trinkets = setup.trinkets or {}
	setup.trinkets[uiSlot] = choiceOrNil
	if choiceOrNil then clearClearedFlag(setup, "trinket", uiSlot) end
end

-- If glyph slot `idx` now resolves to the same glyph as another slot, blank it
-- (`false`) - the other slot's choice wins. Used after a revert, which can
-- otherwise resurrect a duplicate (the inherited glyph is already sitting
-- explicitly in another slot).
local function antiDupeGlyphSlot(self, instanceKey, bossKey, idx, charKey)
	local eff = select(1, self:ResolveBossLoadout(instanceKey, bossKey, charKey)).glyphs
	local mine = eff and eff[idx]
	if type(mine) ~= "table" then return end
	local M = BossPrepCompat.GlyphChoicesMatch
	for s = 1, 3 do
		if s ~= idx and type(eff[s]) == "table" and M(eff[s], mine) then
			local setup = self:GetBossSetup(instanceKey, bossKey, charKey)
			if setup then
				setup.glyphs = setup.glyphs or {}
				setup.glyphs[idx] = false
				setClearedFlag(setup, "glyph", idx)
			end
			return
		end
	end
end

-- "Go back to inheriting the global default for this field."
function P:RevertBossField(instanceKey, bossKey, kind, idx, charKey)
	local setup = self:GetBossSetup(instanceKey, bossKey, charKey)
	if not setup then return end
	if kind == "equipmentSet" then setup.equipmentSet = nil
	elseif kind == "spec" then setup.specID, setup.specName = nil, nil
	elseif kind == "cloak" then setup.cloak = nil
	elseif kind == "talent" then
		if setup.talents then setup.talents[idx] = nil end
		if setup.talentNames then setup.talentNames[idx] = nil end
	elseif kind == "glyph" then if setup.glyphs then setup.glyphs[idx] = nil end
	elseif kind == "trinket" then if setup.trinkets then setup.trinkets[idx] = nil end
	end
	clearClearedFlag(setup, kind, idx)
	if kind == "glyph" then antiDupeGlyphSlot(self, instanceKey, bossKey, idx, charKey) end
end

-- "This boss explicitly uses nothing here" (overrides a global value with empty).
function P:OverrideBossFieldNone(instanceKey, bossKey, kind, idx, charKey)
	local setup = self:EnsureSetup(instanceKey, bossKey, charKey)
	if kind == "equipmentSet" then setup.equipmentSet = nil
	elseif kind == "spec" then setup.specID, setup.specName = nil, nil
	elseif kind == "cloak" then setup.cloak = nil
	elseif kind == "talent" then if setup.talents then setup.talents[idx] = nil end
	elseif kind == "glyph" then
		setup.glyphs = setup.glyphs or {}
		setup.glyphs[idx] = false
	elseif kind == "trinket" then if setup.trinkets then setup.trinkets[idx] = nil end
	end
	setClearedFlag(setup, kind, idx)
end

-------------------------------------------------
-- Global-default field setters (mirror the per-boss ones).
-------------------------------------------------
function P:SetGlobalEquipmentSetChoice(setName, charKey)
	self:EnsureGlobalSetup(charKey).equipmentSet = setName
end

function P:SetGlobalSpecChoice(specID, specName, charKey)
	local g = self:EnsureGlobalSetup(charKey)
	g.specID = specID
	g.specName = specName
end

function P:SetGlobalCloakChoice(choiceOrNil, charKey)
	self:EnsureGlobalSetup(charKey).cloak = choiceOrNil
end

function P:SetGlobalTalentTierChoice(tier, column, talentName, charKey)
	local g = self:EnsureGlobalSetup(charKey)
	g.talents = g.talents or {}
	g.talentNames = g.talentNames or {}
	g.talents[tier] = column
	g.talentNames[tier] = talentName
	g.specGroup = g.specGroup or BossPrepCompat.GetActiveSpecGroup()
end

function P:SetGlobalGlyphSlotChoice(uiSlot, glyphOrFalse, charKey)
	local g = self:EnsureGlobalSetup(charKey)
	g.glyphs = g.glyphs or {}
	g.glyphs[uiSlot] = glyphOrFalse
	-- Same glyph can't sit in two sockets - drop it from the other slots.
	-- The global set has nothing below it to fall back to, so they just clear.
	if type(glyphOrFalse) == "table" then
		local M = BossPrepCompat.GlyphChoicesMatch
		for s = 1, 3 do
			if s ~= uiSlot and type(g.glyphs[s]) == "table" and M(g.glyphs[s], glyphOrFalse) then
				g.glyphs[s] = nil
			end
		end
	end
end

function P:SetGlobalTrinketChoice(uiSlot, choiceOrNil, charKey)
	local g = self:EnsureGlobalSetup(charKey)
	g.trinkets = g.trinkets or {}
	g.trinkets[uiSlot] = choiceOrNil
end

-------------------------------------------------
-- Resolution: merge one profile's global default with that profile's per-boss
-- overrides.
--
-- Returns (effective, source):
--   effective - a setup-shaped table (no trigger) with the values that
--               actually apply for this boss. Same shape the old raw setup
--               had, so Detection/Alert/Highlight can consume it unchanged.
--   source    - parallel table saying where each value came from:
--                 "boss"   - an explicit per-boss override (incl. an explicit
--                            "use nothing here")
--                 "global" - inherited from the profile's global default
--                 nil      - nothing set anywhere
--               shape: { equipmentSet=, spec=, talents={[tier]=},
--                        glyphs={[slot]=}, trinkets={[slot]=} }
-------------------------------------------------
local function resolveWithin(b, g)
	b = b or {}
	g = g or {}
	local bc = b.cleared or {}

	local effective = { talents = {}, talentNames = {}, glyphs = {}, trinkets = {} }
	local source = { talents = {}, glyphs = {}, trinkets = {} }

	-- Equipment set (scalar)
	if b.equipmentSet ~= nil then
		effective.equipmentSet, source.equipmentSet = b.equipmentSet, "boss"
	elseif bc.equipmentSet then
		source.equipmentSet = "boss"
	elseif g.equipmentSet ~= nil then
		effective.equipmentSet, source.equipmentSet = g.equipmentSet, "global"
	end

	-- Spec (specID + specName travel together)
	if b.specID ~= nil then
		effective.specID, effective.specName, source.spec = b.specID, b.specName, "boss"
	elseif bc.spec then
		source.spec = "boss"
	elseif g.specID ~= nil then
		effective.specID, effective.specName, source.spec = g.specID, g.specName, "global"
	end

	-- Cloak (scalar item)
	if type(b.cloak) == "table" then
		effective.cloak, source.cloak = b.cloak, "boss"
	elseif bc.cloak then
		source.cloak = "boss"
	elseif type(g.cloak) == "table" then
		effective.cloak, source.cloak = g.cloak, "global"
	end

	-- Talents (per tier). `effective.talents[tier] == false` means "explicitly
	-- no talent this tier" (unlearn, don't relearn) - distinct from nil = unset.
	local bct = bc.talents or {}
	for tier = 1, (BossPrepCompat.MAX_TALENT_TIERS or 6) do
		if b.talents and b.talents[tier] then
			effective.talents[tier] = b.talents[tier]
			effective.talentNames[tier] = b.talentNames and b.talentNames[tier]
			effective.specGroup = effective.specGroup or b.specGroup
			source.talents[tier] = "boss"
		elseif (b.talents and b.talents[tier] == false) or bct[tier] then
			effective.talents[tier] = false
			source.talents[tier] = "boss"
		elseif g.talents and g.talents[tier] then
			effective.talents[tier] = g.talents[tier]
			effective.talentNames[tier] = g.talentNames and g.talentNames[tier]
			effective.specGroup = effective.specGroup or g.specGroup
			source.talents[tier] = "global"
		end
	end

	-- Glyphs (per slot 1-3). `effective.glyphs[slot] == false` means "explicitly
	-- empty" (a stored `false` or a cleared marker) - distinct from nil = unset.
	local bcg = bc.glyphs or {}
	for slot = 1, 3 do
		local bg = b.glyphs and b.glyphs[slot]
		if type(bg) == "table" then
			effective.glyphs[slot], source.glyphs[slot] = bg, "boss"
		elseif bg == false or bcg[slot] then
			effective.glyphs[slot] = false
			source.glyphs[slot] = "boss"
		elseif g.glyphs and type(g.glyphs[slot]) == "table" then
			effective.glyphs[slot], source.glyphs[slot] = g.glyphs[slot], "global"
		end
	end

	-- Trinkets (per slot 1-2)
	local bck = bc.trinkets or {}
	for slot = 1, 2 do
		local bt = b.trinkets and b.trinkets[slot]
		if type(bt) == "table" and bt.itemID then
			effective.trinkets[slot], source.trinkets[slot] = bt, "boss"
		elseif bck[slot] then
			source.trinkets[slot] = "boss"
		elseif g.trinkets and type(g.trinkets[slot]) == "table" and g.trinkets[slot].itemID then
			effective.trinkets[slot], source.trinkets[slot] = g.trinkets[slot], "global"
		end
	end

	effective.specGroup = effective.specGroup or b.specGroup or g.specGroup
	return effective, source
end

-- Redirect-aware resolution for a boss under the ACTIVE profile.
--
-- Returns (effective, source, redirectName, redirectBase):
--   redirectName - if this boss draws its base loadout from another profile
--                  ("From: X"), that profile's display name; nil otherwise.
--                  The trigger still comes wholesale from that profile (shown
--                  read-only in the UI, edited there), but the loadout is only
--                  a *base*: the active profile's own per-boss slots override
--                  it, exactly the way they override the Global Default.
--   redirectBase - only when redirected: the effective-shaped base the active
--                  per-boss overrides sit on top of, merging (low -> high):
--                    active profile Global Default
--                    -> source profile Global Default
--                    -> source profile per-boss setup for this boss
--
--   source values: "boss"   - an active-profile per-boss override wins here
--                  "global" - inherited (from the base / Global Default)
--                  nil      - nothing set anywhere
function P:ResolveBossLoadout(instanceKey, bossKey, charKey)
	local srcId = self:GetBossSource(instanceKey, bossKey, charKey)
	if srcId and srcId ~= self:GetActiveProfileId(charKey) then
		local prof = self:GetProfile(charKey, srcId)
		if prof then
			-- active Global Default  ->  source Global Default
			local base = resolveWithin(
				self:GetGlobalSetup(charKey, srcId),
				self:GetGlobalSetup(charKey))
			-- ...  ->  source's per-boss setup for this boss
			base = resolveWithin(
				self:GetBossSetup(instanceKey, bossKey, charKey, srcId),
				base)
			-- ...  ->  this profile's own per-boss overrides
			local effective, source = resolveWithin(
				self:GetBossSetup(instanceKey, bossKey, charKey),
				base)
			return effective, source, (prof.name or srcId), base
		end
	end
	return resolveWithin(
		self:GetBossSetup(instanceKey, bossKey, charKey),
		self:GetGlobalSetup(charKey))
end

-- The raw per-boss setup table whose trigger governs this boss under the
-- active profile: the source profile's when redirected, else the active one's.
function P:GetResolvedBossSetup(instanceKey, bossKey, charKey)
	local srcId = self:GetBossSource(instanceKey, bossKey, charKey)
	if srcId and srcId ~= self:GetActiveProfileId(charKey) and self:GetProfile(charKey, srcId) then
		return self:GetBossSetup(instanceKey, bossKey, charKey, srcId)
	end
	return self:GetBossSetup(instanceKey, bossKey, charKey)
end

-- True if the resolved loadout has nothing to act on at all.
function P:LoadoutIsEmpty(effective)
	if not effective then return true end
	if effective.equipmentSet ~= nil or effective.specID ~= nil or effective.cloak ~= nil then return false end
	if next(effective.talents or {}) ~= nil then return false end
	if next(effective.glyphs or {}) ~= nil then return false end
	if next(effective.trinkets or {}) ~= nil then return false end
	return true
end

-- True if this boss has any per-boss configuration of its own (trigger,
-- a loadout override, or an explicit "none"). Used for the boss-list dimming.
function P:BossHasOverrides(instanceKey, bossKey, charKey)
	if self:GetBossSource(instanceKey, bossKey, charKey) then return true end
	local setup = self:GetBossSetup(instanceKey, bossKey, charKey)
	if not setup then return false end
	if setup.trigger then return true end
	if setup.note and setup.note ~= "" then return true end
	if setup.equipmentSet ~= nil or setup.specID ~= nil or setup.cloak ~= nil then return true end
	if setup.talents and next(setup.talents) ~= nil then return true end
	if setup.glyphs and next(setup.glyphs) ~= nil then return true end
	if setup.trinkets and next(setup.trinkets) ~= nil then return true end
	local c = setup.cleared
	if c then
		if c.equipmentSet or c.spec or c.cloak then return true end
		if c.talents and next(c.talents) ~= nil then return true end
		if c.glyphs and next(c.glyphs) ~= nil then return true end
		if c.trinkets and next(c.trinkets) ~= nil then return true end
	end
	return false
end

-------------------------------------------------
-- "Capture what I'm on right now"
-------------------------------------------------
local function liveTrinkets()
	local t = {}
	for i = 1, 2 do
		local live = BossPrepCompat.GetCurrentTrinket(i)
		if live then t[i] = { itemID = live.itemID, name = live.name, icon = live.icon } end
	end
	return t
end

local function liveGlyphList(glyphs)
	local list = {}
	for slot = 1, 3 do
		local x = glyphs and glyphs[slot]
		if type(x) == "table" and (x.glyphID or x.spellID) then table.insert(list, x) end
	end
	return list
end

local function glyphSetKey(list)
	local ids = {}
	for _, x in ipairs(list) do ids[#ids + 1] = tostring(x.glyphID or x.spellID or x.name) end
	table.sort(ids)
	return table.concat(ids, "|")
end

local function trinketSetKey(tbl)
	local ids = {}
	for _, x in pairs(tbl or {}) do
		if type(x) == "table" and x.itemID then ids[#ids + 1] = tostring(x.itemID) end
	end
	table.sort(ids)
	return table.concat(ids, "|")
end

-- Capture the player's live loadout as the character-wide global default.
function P:CaptureCurrentAsGlobal(charKey)
	local _, specName, specID = BossPrepCompat.GetCurrentSpec()
	local talents, talentNames = BossPrepCompat.GetCurrentTalents()
	local glyphs = BossPrepCompat.GetCurrentMajorGlyphs()
	local prev = self:GetGlobalSetup(charKey)

	local liveCloak = BossPrepCompat.GetCurrentCloak()
	local g = {
		equipmentSet = BossPrepCompat.GetActiveEquipmentSetName() or (prev and prev.equipmentSet) or nil,
		specGroup    = BossPrepCompat.GetActiveSpecGroup(),
		specID       = specID,
		specName     = specName,
		cloak        = liveCloak and { itemID = liveCloak.itemID, name = liveCloak.name, icon = liveCloak.icon } or nil,
		talents      = talents,
		talentNames  = talentNames,
		glyphs       = glyphs,
		trinkets     = liveTrinkets(),
		savedAt      = time(),
	}
	self:GetProfileData(charKey)[GLOBAL_KEY] = g
	return g
end

-- Capture the player's live loadout as this boss's setup, but store only the
-- fields that DIFFER from the global default - anything matching global is
-- left inheriting. Preserves the existing trigger config.
-- For a "From: X" boss the deltas are measured against that resolved base
-- (active global -> X global -> X per-boss), not the bare Global Default, so a
-- capture only stores what actually differs from what X already gives.
function P:CaptureCurrentAsBossOverrides(instanceKey, bossKey, charKey)
	local setup = self:EnsureSetup(instanceKey, bossKey, charKey)
	local _, _, _, base = self:ResolveBossLoadout(instanceKey, bossKey, charKey)
	local g = base or self:GetGlobalSetup(charKey) or {}

	local specGroup = BossPrepCompat.GetActiveSpecGroup()
	local _, specName, specID = BossPrepCompat.GetCurrentSpec()
	local talents, talentNames = BossPrepCompat.GetCurrentTalents()
	local glyphs = BossPrepCompat.GetCurrentMajorGlyphs()
	local trinkets = liveTrinkets()
	local liveGear = BossPrepCompat.GetActiveEquipmentSetName()
	local liveCloak = BossPrepCompat.GetCurrentCloak()

	setup.cleared = {}
	setup.specGroup = specGroup

	-- Gear
	setup.equipmentSet = nil
	if liveGear and liveGear ~= g.equipmentSet then
		setup.equipmentSet = liveGear
	elseif not liveGear and g.equipmentSet then
		setup.cleared.equipmentSet = true
	end

	-- Spec
	setup.specID, setup.specName = nil, nil
	if specID and specID ~= g.specID then
		setup.specID, setup.specName = specID, specName
	elseif not specID and g.specID then
		setup.cleared.spec = true
	end

	-- Cloak
	setup.cloak = nil
	local gCloakID = type(g.cloak) == "table" and g.cloak.itemID or nil
	if liveCloak and liveCloak.itemID ~= gCloakID then
		setup.cloak = { itemID = liveCloak.itemID, name = liveCloak.name, icon = liveCloak.icon }
	elseif not liveCloak and gCloakID then
		setup.cleared.cloak = true
	end

	-- Talents (per tier)
	setup.talents, setup.talentNames, setup.cleared.talents = {}, {}, {}
	for tier = 1, (BossPrepCompat.MAX_TALENT_TIERS or 6) do
		local live = talents and talents[tier]
		local gv = g.talents and g.talents[tier]
		if live and live ~= gv then
			setup.talents[tier] = live
			setup.talentNames[tier] = talentNames and talentNames[tier]
		elseif not live and gv then
			setup.cleared.talents[tier] = true
		end
	end

	-- Glyphs (matched as an unordered set)
	local liveGL = liveGlyphList(glyphs)
	local globalGL = liveGlyphList(g.glyphs)
	setup.glyphs = nil
	if glyphSetKey(liveGL) ~= glyphSetKey(globalGL) then
		setup.glyphs = {}
		if #liveGL == 0 then
			setup.glyphs = { [1] = false, [2] = false, [3] = false }
		else
			for i, x in ipairs(liveGL) do
				setup.glyphs[i] = { glyphID = x.glyphID, spellID = x.spellID, name = x.name, icon = x.icon }
			end
		end
	end

	-- Trinkets (matched as an unordered set)
	setup.trinkets, setup.cleared.trinkets = nil, nil
	if trinketSetKey(trinkets) ~= trinketSetKey(g.trinkets) then
		setup.trinkets, setup.cleared.trinkets = {}, {}
		local globalHasTrinkets = trinketSetKey(g.trinkets) ~= ""
		for i = 1, 2 do
			if trinkets[i] then
				setup.trinkets[i] = trinkets[i]
			elseif globalHasTrinkets then
				setup.cleared.trinkets[i] = true
			end
		end
	end

	setup.savedAt = time()
	return setup
end

