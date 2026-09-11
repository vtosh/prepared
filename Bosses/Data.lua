-- Bosses\Data.lua
--
-- This is the extension point. BossPrepData is just a list of instances,
-- each with a list of bosses. To add a new raid, copy
-- Bosses\SiegeOfOrgrimmar.lua, rename it, edit the table, and add one line
-- to BossPrep.toc so it gets loaded. No other code needs to change.
--
-- Each boss entry:
--   key         -- stable internal id, never rename once you've saved setups against it
--   name        -- display name AND the string we match against your current
--                  target's unit name, so this must match the boss's actual
--                  in-game unit name (what you see when you /tar or mouse over it)
--   order       -- sort order in the UI (list order also determines "next boss" for kill-advance)
--   targetNames -- optional list of extra unit-name aliases to also match on
--                  target (e.g. a boss with multiple forms/names)
--   subZone     -- optional exact GetSubZoneText() string for this boss's
--                  room/area, enables the "entered boss zone" trigger
--   defaultTrigger -- optional starting trigger for a boss with no saved
--                  config yet, e.g. { type = "ZONE" } or
--                  { type = "KILL", killAfterBossKey = "SOME_KEY" }.
--                  Defaults to { type = "TARGET" } when omitted. The player
--                  can still change it in the UI.
--
-- Each instance entry:
--   key, name, order, bosses = { ... }

BossPrepData = {
	instances = {},
}

-- Call this from each Bosses\<Raid>.lua file.
function BossPrepData:RegisterInstance(instance)
	assert(instance.key, "instance needs a unique key")
	assert(instance.bosses, "instance needs a bosses table")
	table.insert(self.instances, instance)
	table.sort(self.instances, function(a, b) return (a.order or 99) < (b.order or 99) end)
end

-- Convenience lookups used throughout the addon.
function BossPrepData:GetInstance(instanceKey)
	for _, inst in ipairs(self.instances) do
		if inst.key == instanceKey then return inst end
	end
end

function BossPrepData:GetBoss(instanceKey, bossKey)
	local inst = self:GetInstance(instanceKey)
	if not inst then return nil end
	for _, boss in ipairs(inst.bosses) do
		if boss.key == bossKey then return boss, inst end
	end
end

-- The trigger a boss starts with before the player has configured anything.
-- Returns a fresh table (safe to store) - { type = "TARGET" } unless the
-- boss's data entry overrides it with `defaultTrigger`.
function BossPrepData:GetDefaultTrigger(instanceKey, bossKey)
	local boss = self:GetBoss(instanceKey, bossKey)
	local dt = boss and boss.defaultTrigger
	if dt and dt.type then
		return { type = dt.type, killAfterBossKey = dt.killAfterBossKey }
	end
	return { type = "TARGET" }
end

-- Find a boss by the unit name you have targeted (or its nameplate/unit
-- name generally). instanceKeyHint narrows the search to one instance
-- first (recommended - pass the instance matching your current zone) but
-- falls back to searching everything if no hint is given or nothing in the
-- hinted instance matches. Checks both the boss's primary `name` and any
-- `targetNames` aliases.
function BossPrepData:FindBossByUnitName(unitName, instanceKeyHint)
	if not unitName then return nil end

	local function searchInstance(inst)
		for _, boss in ipairs(inst.bosses) do
			if boss.name == unitName then
				return boss, inst
			end
			if boss.targetNames then
				for _, alias in ipairs(boss.targetNames) do
					if alias == unitName then
						return boss, inst
					end
				end
			end
		end
	end

	if instanceKeyHint then
		local inst = self:GetInstance(instanceKeyHint)
		if inst then
			local boss, foundInst = searchInstance(inst)
			if boss then return boss, foundInst end
		end
	end

	for _, inst in ipairs(self.instances) do
		local boss, foundInst = searchInstance(inst)
		if boss then return boss, foundInst end
	end
end

-- Find a boss by sub-zone text (GetSubZoneText()). Only bosses with a
-- `subZone` field set are matchable this way.
function BossPrepData:FindBossBySubZone(subZoneText, instanceKeyHint)
	if not subZoneText or subZoneText == "" then return nil end

	local function searchInstance(inst)
		for _, boss in ipairs(inst.bosses) do
			if boss.subZone and boss.subZone == subZoneText then
				return boss, inst
			end
		end
	end

	if instanceKeyHint then
		local inst = self:GetInstance(instanceKeyHint)
		if inst then
			local boss, foundInst = searchInstance(inst)
			if boss then return boss, foundInst end
		end
	end

	for _, inst in ipairs(self.instances) do
		local boss, foundInst = searchInstance(inst)
		if boss then return boss, foundInst end
	end
end

-- Returns the previous boss (in registration order) before bossKey within
-- instanceKey, or nil if bossKey was the first one (or wasn't found).
function BossPrepData:GetPreviousBoss(instanceKey, bossKey)
	local inst = self:GetInstance(instanceKey)
	if not inst then return nil end
	for i, boss in ipairs(inst.bosses) do
		if boss.key == bossKey then
			local prevBoss = inst.bosses[i - 1]
			if prevBoss then return prevBoss, inst end
			return nil
		end
	end
end

-- Returns the next boss (in registration order) after bossKey within
-- instanceKey, or nil if bossKey was the last one (or wasn't found).
function BossPrepData:GetNextBoss(instanceKey, bossKey)
	local inst = self:GetInstance(instanceKey)
	if not inst then return nil end
	for i, boss in ipairs(inst.bosses) do
		if boss.key == bossKey then
			local nextBoss = inst.bosses[i + 1]
			if nextBoss then return nextBoss, inst end
			return nil
		end
	end
end
