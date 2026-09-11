-- Detection.lua
BossPrepDetection = {}
local D = BossPrepDetection

D.currentInstanceKey = nil
D.currentBossKey = nil

-------------------------------------------------
-- Diffing
-------------------------------------------------
-- Compares the given saved `setup` to the player's live state.
-- Returns a list of { cat = "gear|spec|talent|glyph|trinket", text = "..." }
-- mismatch entries (empty list = all good). The audio cue uses `cat`; the
-- banner shows `text`.
function D:Diff(setup)
	local problems = {}
	if not setup then return problems end

	local function add(cat, text)
		table.insert(problems, { cat = cat, text = text })
	end

	-- Gear
	if setup.equipmentSet then
		local active = BossPrepCompat.IsEquipmentSetActive(setup.equipmentSet)
		if active == false then
			add("gear", "Gear set: switch to '" .. setup.equipmentSet .. "'")
		elseif active == nil then
			add("gear", "Gear set: '" .. setup.equipmentSet .. "' no longer exists (re-save it)")
		end
	end

	-- Spec
	if setup.specID then
		local _, _, currentSpecID = BossPrepCompat.GetCurrentSpec()
		if currentSpecID and currentSpecID ~= setup.specID then
			add("spec", "Spec: switch to " .. (setup.specName or "the saved spec"))
		end
	end

	-- Cloak
	if setup.cloak and setup.cloak.itemID then
		local cur = BossPrepCompat.GetCurrentCloak()
		if not cur or cur.itemID ~= setup.cloak.itemID then
			add("cloak", "Cloak: equip '" .. (setup.cloak.name or "?") .. "'")
		end
	end

	-- Talents (only compare tiers we actually captured a selection for; a
	-- wantedColumn of `false` = "this tier should be empty", flag if it isn't)
	if setup.talents then
		local current = BossPrepCompat.GetCurrentTalents()
		for tier, wantedColumn in pairs(setup.talents) do
			if wantedColumn and current[tier] ~= wantedColumn then
				local wantedName = setup.talentNames and setup.talentNames[tier]
				add("talent", "Talent tier " .. tier .. ": switch to " .. (wantedName or ("column " .. wantedColumn)))
			elseif wantedColumn == false and current[tier] then
				add("talent", "Talent tier " .. tier .. ": unlearn it (no replacement)")
			end
		end
	end

	-- Glyphs (order-independent: each saved major glyph just has to be socketed
	-- in one of the 3 major slots, any order). If any slot is explicitly empty
	-- (`false`), the list is treated as exhaustive - any *extra* major glyph
	-- socketed is flagged for removal.
	if setup.glyphs then
		local current = BossPrepCompat.GetCurrentMajorGlyphs()
		local exhaustive = false
		local wantedList = {}
		for i = 1, 3 do
			local wanted = setup.glyphs[i]
			if wanted == false then
				exhaustive = true
			elseif type(wanted) == "table" and (wanted.glyphID or wanted.spellID) then
				local dup = false
				for _, w in ipairs(wantedList) do
					if BossPrepCompat.GlyphChoicesMatch(w, wanted) then dup = true break end
				end
				if not dup then
					wantedList[#wantedList + 1] = wanted
					local socketed = false
					for _, have in pairs(current) do
						if have and BossPrepCompat.GlyphChoicesMatch(have, wanted) then
							socketed = true
							break
						end
					end
					if not socketed then
						add("glyph", "Glyph: socket '" .. (wanted.name or "?") .. "'")
					end
				end
			end
		end
		if exhaustive then
			for _, have in pairs(current) do
				if have and (have.glyphID or have.spellID) then
					local keep = false
					for _, w in ipairs(wantedList) do
						if BossPrepCompat.GlyphChoicesMatch(have, w) then keep = true break end
					end
					if not keep then
						add("glyph", "Glyph: unlearn '" .. (have.name or "?") .. "'")
					end
				end
			end
		end
	end

	-- Trinkets (order-independent: each saved trinket just has to be equipped
	-- in one of the two trinket slots)
	if setup.trinkets then
		local current = BossPrepCompat.GetCurrentTrinkets()
		local equipped = {}
		for _, t in pairs(current) do
			if t and t.itemID then equipped[t.itemID] = true end
		end
		for _, wanted in pairs(setup.trinkets) do
			if wanted and wanted.itemID and not equipped[wanted.itemID] then
				add("trinket", "Trinket: equip '" .. (wanted.name or "?") .. "'")
			end
		end
	end

	return problems
end

-------------------------------------------------
-- "Which boss am I looking at" resolution
-------------------------------------------------
D.currentBossName = nil      -- the live in-game unit name of the tracked boss
D.handledDeathGUIDs = {}     -- guards against reprocessing the same dead unit repeatedly

function D:SetCurrentBoss(instanceKey, bossKey)
	self.currentInstanceKey = instanceKey
	self.currentBossKey = bossKey
	self.currentBossZoneFired = nil -- set by CheckZoneTrigger when it's the one that tracked this boss
	if instanceKey and bossKey then
		local boss = BossPrepData:GetBoss(instanceKey, bossKey)
		self.currentBossName = boss and boss.name
	else
		self.currentBossName = nil
	end
end

function D:GetCurrentBoss()
	return self.currentInstanceKey, self.currentBossKey
end

-- The effective trigger for a boss: the player's saved trigger if they've set
-- one, otherwise the boss's data-file default (which is { type = "TARGET" }
-- unless the data entry says otherwise).
function D:GetTrigger(instanceKey, bossKey)
	local setup = BossPrepProfiles:GetResolvedBossSetup(instanceKey, bossKey)
	if setup and setup.trigger and setup.trigger.type then
		return setup.trigger
	end
	return BossPrepData:GetDefaultTrigger(instanceKey, bossKey)
end

-- Figures out which registered instance (if any) matches the raid you're
-- currently standing in, by comparing GetInstanceInfo()'s display name
-- against each instance's `name`. Used to disambiguate target/subzone
-- matches when two raids happen to share a boss name.
function D:GetCurrentZoneInstanceKey()
	local inInstance, instanceType = IsInInstance()
	if not inInstance or instanceType ~= "raid" then return nil end

	local zoneName = GetInstanceInfo()
	if not zoneName then return nil end

	for _, inst in ipairs(BossPrepData.instances) do
		if inst.name == zoneName then
			return inst.key
		end
	end
	-- fall back to a loose match in case of minor text differences
	for _, inst in ipairs(BossPrepData.instances) do
		if zoneName:find(inst.name, 1, true) then
			return inst.key
		end
	end
	return nil
end

-- Called when a boss is detected as dead (regardless of whether it was the
-- currently-tracked one). Hides the alert if it *was* the tracked boss, and
-- looks for any boss in the same instance whose trigger is configured as
-- "on kill of <this boss>" - if found, starts tracking + silently
-- pre-checks it, so the next pull's requirements show up immediately with
-- no need to target anything.
function D:OnBossDefeated(instanceKey, bossKey)
	if self.currentInstanceKey == instanceKey and self.currentBossKey == bossKey then
		BossPrepAlert:Hide()
	end

	if BossPrepDB.settings.debug then
		local boss = BossPrepData:GetBoss(instanceKey, bossKey)
		print("|cff33ff99Prepared|r detected kill: " .. tostring(boss and boss.name or bossKey))
	end

	local inst = BossPrepData:GetInstance(instanceKey)
	if not inst then return end

	for _, candidate in ipairs(inst.bosses) do
		local trigger = self:GetTrigger(instanceKey, candidate.key)
		if trigger.type == "KILL" and trigger.killAfterBossKey == bossKey then
			local deadBoss = BossPrepData:GetBoss(instanceKey, bossKey)
			print("|cff33ff99Prepared|r " .. (deadBoss and deadBoss.name or bossKey) ..
				" down. Next up: " .. candidate.name .. ".")
			self:SetCurrentBoss(instanceKey, candidate.key)
			self:CheckNow(false)
			return
		end
	end
end
-- verbose = true means "print something even if there's nothing wrong or
-- nothing configured" (used for the manual /prep check and UI button).
function D:CheckNow(verbose)
	local instanceKey, bossKey = self:GetCurrentBoss()
	if not instanceKey or not bossKey then
		if verbose then
			print("|cff33ff99Prepared|r no boss selected. Pick one in the UI or wait for a pull.")
		end
		return
	end

	local boss, inst = BossPrepData:GetBoss(instanceKey, bossKey)
	local effective = BossPrepProfiles:ResolveBossLoadout(instanceKey, bossKey)
	local note = BossPrepProfiles:GetBossNote(instanceKey, bossKey)

	if BossPrepProfiles:LoadoutIsEmpty(effective) and not note then
		if verbose then
			print("|cff33ff99Prepared|r no setup saved yet for " .. (boss and boss.name or bossKey) .. ".")
		end
		BossPrepAlert:Hide()
		return
	end

	local problems = self:Diff(effective)

	if #problems > 0 or note then
		-- verbose = a manual "/prep check" or the UI button: replay the cue even
		-- if the banner is already up.
		BossPrepAlert:Show(boss and boss.name or bossKey, problems, verbose)
	else
		BossPrepAlert:Hide()
		if verbose then
			print("|cff33ff99Prepared|r you're set up correctly for " .. (boss and boss.name or bossKey) .. ".")
		end
	end
end

-------------------------------------------------
-- Click-to-apply: the secure button under the alert banner handles the next
-- mismatch, one press at a time, in a fixed order (gear -> spec -> talents ->
-- glyphs). Alert.lua owns that button and the step ordering; this file just
-- provides D:EquipItems, the non-secure worker for the physical-gear steps
-- (set, cloak, both trinkets). Spec/talents/glyphs can't be touched from addon
-- code - the mutation APIs are Blizzard-only and even opening those panels
-- taints them - so the button /click-chains Blizzard's own UI in a secure
-- context, and Highlight.lua marks what to change once the panel is open.
-------------------------------------------------
-- Trinkets are order-independent: when we need to slot a missing one, target
-- a slot whose current occupant isn't something we want to keep.
local function pickTrinketInvSlot(wantedTrinkets, current)
	local want = {}
	for _, w in pairs(wantedTrinkets) do
		if w and w.itemID then want[w.itemID] = true end
	end
	local INV = { 13, 14 } -- uiSlot 1 -> INVSLOT_TRINKET1, uiSlot 2 -> ...2
	for uiSlot = 1, 2 do
		local t = current[uiSlot]
		if not (t and t.itemID and want[t.itemID]) then
			return INV[uiSlot]
		end
	end
	return 13
end

-- Equip everything BossPrep can equip directly for the given resolved loadout
-- - the gear set, the cloak, and both trinkets - in a single press. Driven by
-- the alert banner's secure button (its PreClick) when the next mismatch is
-- physical gear. Spec / talents / glyphs are driven by that same button via
-- secure /click chains.
function D:EquipItems(setup)
	if not setup then return end
	if InCombatLockdown and InCombatLockdown() then
		print("|cff33ff99Prepared|r can't change your gear in combat.")
		return
	end

	local C = BossPrepCompat
	local done, failed = {}, {}

	-- Gear set
	if setup.equipmentSet and C.IsEquipmentSetActive(setup.equipmentSet) == false then
		local ok, err = C.UseEquipmentSet(setup.equipmentSet)
		if ok then table.insert(done, "gear set '" .. setup.equipmentSet .. "'")
		else table.insert(failed, "gear set (" .. tostring(err) .. ")") end
	end

	-- Cloak
	if setup.cloak and setup.cloak.itemID then
		local cur = C.GetCurrentCloak()
		if not cur or cur.itemID ~= setup.cloak.itemID then
			local ok, err = C.EquipItem(setup.cloak.itemID, C.CLOAK_SLOT)
			if ok then table.insert(done, "cloak '" .. (setup.cloak.name or "?") .. "'")
			else table.insert(failed, "cloak (" .. tostring(err) .. ")") end
		end
	end

	-- Trinkets (order-independent - keep a local view of the slots so the
	-- second trinket lands in the slot the first one didn't take).
	if setup.trinkets then
		local current = C.GetCurrentTrinkets()
		local equipped = {}
		for _, t in pairs(current) do if t and t.itemID then equipped[t.itemID] = true end end
		for uiSlot = 1, 2 do
			local wanted = setup.trinkets[uiSlot]
			if wanted and wanted.itemID and not equipped[wanted.itemID] then
				local invSlot = pickTrinketInvSlot(setup.trinkets, current)
				local ok, err = C.EquipItem(wanted.itemID, invSlot)
				if ok then
					equipped[wanted.itemID] = true
					current[invSlot == 14 and 2 or 1] = { itemID = wanted.itemID }
					table.insert(done, "trinket '" .. (wanted.name or "?") .. "'")
				else
					table.insert(failed, "trinket (" .. tostring(err) .. ")")
				end
			end
		end
	end

	if #done > 0 then
		print("|cff33ff99Prepared|r equipping: " .. table.concat(done, ", ") .. ".")
	end
	if #failed > 0 then
		print("|cff33ff99Prepared|r couldn't equip: " .. table.concat(failed, ", ") .. ".")
	end
	if #done == 0 and #failed == 0 then
		print("|cff33ff99Prepared|r gear, cloak and trinkets already match.")
	end

	if C_Timer and C_Timer.After then
		C_Timer.After(0.5, function() D:CheckNow(false) end)
	end
end

-------------------------------------------------
-- Event wiring
-------------------------------------------------

-- The effective trigger type for a boss (saved choice, else the data-file
-- default, else TARGET).
local function GetTriggerType(instanceKey, bossKey)
	return D:GetTrigger(instanceKey, bossKey).type
end

-- TRIGGER: targeting a boss (this boss's own trigger must be set to TARGET).
BossPrep:On("PLAYER_TARGET_CHANGED", function()
	if not UnitExists("target") then return end
	local unitName = UnitName("target")
	if not unitName then return end

	local instHint = D:GetCurrentZoneInstanceKey()
	local boss, inst = BossPrepData:FindBossByUnitName(unitName, instHint)
	if not (boss and inst) then return end
	if GetTriggerType(inst.key, boss.key) ~= "TARGET" then return end

	if BossPrepDB.settings.debug then
		print("|cff33ff99Prepared|r targeted boss: " .. boss.name)
	end
	D:SetCurrentBoss(inst.key, boss.key)
	D:CheckNow(false)
end)

-- Every zone string that should fire this boss's ZONE trigger: the player's
-- per-character override (setup.trigger.subZone) wins, otherwise the
-- `subZone` / `subZones` defaults from the boss's data file.
function D:GetZoneStrings(instanceKey, bossKey)
	local override
	local setup = BossPrepProfiles:GetResolvedBossSetup(instanceKey, bossKey)
	if setup and setup.trigger and setup.trigger.subZone and setup.trigger.subZone ~= "" then
		override = setup.trigger.subZone
	end

	local defaults = {}
	local boss = BossPrepData:GetBoss(instanceKey, bossKey)
	if boss then
		if boss.subZone then table.insert(defaults, boss.subZone) end
		if boss.subZones then
			for _, z in ipairs(boss.subZones) do table.insert(defaults, z) end
		end
	end

	return override, defaults
end

-- What the ZONE trigger will actually match on (override if set, else defaults).
function D:GetEffectiveZoneStrings(instanceKey, bossKey)
	local override, defaults = self:GetZoneStrings(instanceKey, bossKey)
	if override then return { override } end
	return defaults
end

-- TRIGGER: entering a boss's named sub-zone (this boss's trigger must be
-- set to ZONE, and it needs either a `subZone` in its data file or a
-- per-character override set via the UI button).
local function CheckZoneTrigger()
	local here = {
		GetSubZoneText and GetSubZoneText() or "",
		GetMinimapZoneText and GetMinimapZoneText() or "",
		GetZoneText and GetZoneText() or "",
	}

	local function matchesHere(want)
		if not want or want == "" then return false end
		for _, cur in ipairs(here) do
			if cur ~= "" and (cur == want or cur:find(want, 1, true)) then
				return true
			end
		end
		return false
	end

	local instHint = D:GetCurrentZoneInstanceKey()

	local function tryInstance(inst)
		if not inst then return false end
		for _, boss in ipairs(inst.bosses) do
			if GetTriggerType(inst.key, boss.key) == "ZONE" then
				for _, want in ipairs(D:GetEffectiveZoneStrings(inst.key, boss.key)) do
					if matchesHere(want) then
						if BossPrepDB.settings.debug then
							print("|cff33ff99Prepared|r entered zone for: " .. boss.name .. " (" .. want .. ")")
						end
						-- Switching which boss the banner is for: drop the old
						-- one first so CheckNow re-shows from scratch and the
						-- audio cue fires again (a plain update while it's up
						-- wouldn't re-cue, and the old boss's TTS could still be
						-- mid-sentence).
						local pik, pbk = D:GetCurrentBoss()
						if pik and (pik ~= inst.key or pbk ~= boss.key) then
							BossPrepAlert:Hide()
						end
						D:SetCurrentBoss(inst.key, boss.key)
						D.currentBossZoneFired = true
						D:CheckNow(false)
						return true
					end
				end
			end
		end
		return false
	end

	if instHint and tryInstance(BossPrepData:GetInstance(instHint)) then return end
	for _, inst in ipairs(BossPrepData.instances) do
		if inst.key ~= instHint and tryInstance(inst) then return end
	end

	-- Didn't enter any ZONE-boss's area. If the boss we're tracking was tracked
	-- *by* a zone trigger and we've now left its area, dismiss its banner
	-- (walking back in re-fires the trigger and re-checks). A boss picked
	-- manually in the UI - even a ZONE one - keeps its banner.
	local ik, bk = D:GetCurrentBoss()
	if ik and bk and D.currentBossZoneFired then
		local stillHere = false
		for _, want in ipairs(D:GetEffectiveZoneStrings(ik, bk)) do
			if matchesHere(want) then stillHere = true break end
		end
		if not stillHere then
			if BossPrepDB.settings.debug then
				local boss = BossPrepData:GetBoss(ik, bk)
				print("|cff33ff99Prepared|r left the zone for " ..
					(boss and boss.name or bk) .. " - dismissing.")
			end
			D:SetCurrentBoss(nil, nil)
			BossPrepAlert:Hide()
		end
	end
end
BossPrep:On("ZONE_CHANGED_NEW_AREA", CheckZoneTrigger)
BossPrep:On("ZONE_CHANGED", CheckZoneTrigger)
BossPrep:On("ZONE_CHANGED_INDOORS", CheckZoneTrigger)

-- TRIGGER: a boss dying (used both to clear the banner for whichever boss
-- was tracked, and to fire any *other* boss whose trigger is "on kill of
-- this one"). We deliberately avoid BOSS_KILL (only added in patch 6.1.0,
-- i.e. after MoP - not guaranteed to exist on a MoP Classic client) and
-- instead watch unit health directly on units that could plausibly be a
-- boss. GUIDs (not names) dedupe so a wipe-and-reset on the same boss is
-- handled fresh on the next kill.
local BOSS_UNIT_TOKENS = { "target", "boss1", "boss2", "boss3", "boss4", "boss5" }
BossPrep:On("UNIT_HEALTH", function(unit)
	local isTracked = false
	for _, token in ipairs(BOSS_UNIT_TOKENS) do
		if unit == token then isTracked = true break end
	end
	if not isTracked then return end
	if not UnitIsDeadOrGhost(unit) then return end

	local guid = UnitGUID and UnitGUID(unit)
	if not guid or D.handledDeathGUIDs[guid] then return end

	local unitName = UnitName(unit)
	if not unitName then return end

	local instHint = D:GetCurrentZoneInstanceKey()
	local deadBoss, deadInst = BossPrepData:FindBossByUnitName(unitName, instHint)
	if not (deadBoss and deadInst) then return end

	D.handledDeathGUIDs[guid] = true
	D:OnBossDefeated(deadInst.key, deadBoss.key)
end)

-- Safety net: if the fight ends in a wipe, clear the banner even though
-- nothing "died". Wrapped like everything else so a missing event on some
-- client build can't break the addon.
BossPrep:On("ENCOUNTER_END", function()
	BossPrepAlert:Hide()
end)

-- Also re-check whenever gear/talents/glyphs/spec change, in case the
-- player fixes things mid-alert, or breaks things mid-fight.
local recheckEvents = {
	"PLAYER_EQUIPMENT_CHANGED",
	"PLAYER_TALENT_UPDATE",
	"ACTIVE_TALENT_GROUP_CHANGED",
	"PLAYER_SPECIALIZATION_CHANGED",
	"GLYPH_ADDED",
	"GLYPH_REMOVED",
	"GLYPH_UPDATED",
}
for _, ev in ipairs(recheckEvents) do
	BossPrep:On(ev, function()
		if D.currentBossKey then
			D:CheckNow(false)
		end
	end)
end

-- Click-to-apply feedback: a talent learn that the game rejects (usually
-- "needs a Tome of the Clear Mind" or a level requirement) fires this.
BossPrep:On("PLAYER_LEARN_TALENT_FAILED", function()
	print("|cff33ff99Prepared|r that talent change was rejected - you likely need a Tome of the Clear Mind, or a class trainer.")
end)

-- If the server rejects a change we just tried to apply (most commonly a spec
-- change blocked by "doesn't match your assigned role"), relay the reason.
BossPrep:On("UI_ERROR_MESSAGE", function(a, b)
	-- payload is (messageType, message) on modern clients, (message) on older
	local message = (type(b) == "string" and b) or (type(a) == "string" and a)
	if not message then return end
	if D.lastApplyAt and (GetTime() - D.lastApplyAt) < 3 then
		print("|cff33ff99Prepared|r the game rejected that: " .. message)
		if message:lower():find("role") then
			print("|cff33ff99Prepared|r set your group/raid role to match the spec first (right-click your unit frame -> Set Role).")
		end
	end
end)

BossPrep:On("PLAYER_ENTERING_WORLD", function()
	BossPrep.EnsureDB()
	if not BossPrepDB.settings.resetOnLeaveInstance then return end
	local inInstance, instanceType = IsInInstance()
	if not inInstance or instanceType ~= "raid" then
		D:SetCurrentBoss(nil, nil)
		BossPrepAlert:Hide()
	end
end)
