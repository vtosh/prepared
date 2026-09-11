-- Compat.lua
-- MoP Classic (5.5.x) ships on a modernized client. Blizzard moved the
-- specialization / talent APIs into the C_SpecializationInfo namespace and
-- the old globals (GetSpecialization, GetSpecializationInfo, GetActiveSpecGroup,
-- and the tier/column form of GetTalentInfo) are either gone entirely or only
-- present as Cata-era-signature shims gated behind the `loadDeprecationFallbacks`
-- CVar. The glyph type numbering also differs from what older docs describe
-- (major = 1, minor = 2). This file is the one place that knows all of that;
-- everything else in the addon talks to BossPrepCompat.

BossPrepCompat = {}
local C = BossPrepCompat

-- Pick the first value that's actually a function, from a list of candidates.
local function firstFn(...)
	for i = 1, select("#", ...) do
		local f = select(i, ...)
		if type(f) == "function" then return f end
	end
	return nil
end

local CSI = C_SpecializationInfo -- real namespace on MoP Classic; nil on much older clients

-------------------------------------------------
-- Equipment Sets
-------------------------------------------------
-- Returns a list of { name = "SetName", icon = fileID/path } for every
-- equipment set the character has saved in the Blizzard Equipment Manager.
function C.GetEquipmentSets()
	local sets = {}

	if C_EquipmentSet and C_EquipmentSet.GetEquipmentSetIDs then
		-- Newer namespace (present on MoP Classic)
		local ids = C_EquipmentSet.GetEquipmentSetIDs()
		for _, id in ipairs(ids) do
			local name, icon = C_EquipmentSet.GetEquipmentSetInfo(id)
			if name then
				table.insert(sets, { name = name, icon = icon, id = id })
			end
		end
		return sets, "new"
	elseif GetNumEquipmentSets then
		-- Legacy global API (very old clients)
		local n = GetNumEquipmentSets()
		for i = 1, n do
			local name, icon = GetEquipmentSetInfo(i)
			if name then
				table.insert(sets, { name = name, icon = icon, id = i })
			end
		end
		return sets, "old"
	end

	return sets, "none"
end

-- Equips a set by name. Returns true/false, and an error string on failure.
function C.UseEquipmentSet(name)
	if not name then return false, "no set name configured" end

	if InCombatLockdown and InCombatLockdown() then
		return false, "can't swap gear in combat"
	end

	if C_EquipmentSet and C_EquipmentSet.UseEquipmentSet then
		local sets = select(1, C.GetEquipmentSets())
		for _, s in ipairs(sets) do
			if s.name == name then
				C_EquipmentSet.UseEquipmentSet(s.id)
				return true
			end
		end
		return false, "set '" .. name .. "' not found"
	elseif UseEquipmentSet then
		local ok = pcall(UseEquipmentSet, name)
		if ok then return true end
		return false, "UseEquipmentSet failed for '" .. name .. "'"
	end

	return false, "no equipment set API available on this client"
end

-- Is the named set currently equipped?
function C.IsEquipmentSetActive(name)
	if not name then return nil end

	if C_EquipmentSet and C_EquipmentSet.GetEquipmentSetIDs then
		local ids = C_EquipmentSet.GetEquipmentSetIDs()
		for _, id in ipairs(ids) do
			local setName, _, _, isEquipped = C_EquipmentSet.GetEquipmentSetInfo(id)
			if setName == name then
				return isEquipped and true or false
			end
		end
		return nil -- set no longer exists
	elseif GetEquipmentSetInfoByName then
		local _, _, _, isEquipped = GetEquipmentSetInfoByName(name)
		if isEquipped == nil then return nil end
		return isEquipped and true or false
	end

	return nil
end

function C.CreateEquipmentSetFromCurrent(name, icon)
	if not name or name == "" then return false, "no name given" end
	icon = icon or "INV_Misc_QuestionMark"

	if C_EquipmentSet and C_EquipmentSet.CreateEquipmentSet then
		local ok = pcall(C_EquipmentSet.CreateEquipmentSet, name, icon)
		if ok then return true end
		return false, "C_EquipmentSet.CreateEquipmentSet failed"
	elseif SaveEquipmentSet then
		local ok = pcall(SaveEquipmentSet, name, icon)
		if ok then return true end
		return false, "SaveEquipmentSet failed"
	end
	return false, "no equipment set creation API available on this client"
end

-- Name of the equipment set that is currently fully equipped, or nil.
function C.GetActiveEquipmentSetName()
	if C_EquipmentSet and C_EquipmentSet.GetEquipmentSetIDs then
		for _, id in ipairs(C_EquipmentSet.GetEquipmentSetIDs()) do
			local name, _, _, isEquipped = C_EquipmentSet.GetEquipmentSetInfo(id)
			if isEquipped and name then return name end
		end
		return nil
	elseif GetNumEquipmentSets and GetEquipmentSetInfo then
		for i = 1, GetNumEquipmentSets() do
			local name, _, _, isEquipped = GetEquipmentSetInfo(i)
			if isEquipped and name then return name end
		end
	end
	return nil
end

-------------------------------------------------
-- Trinkets (tracked separately from gear sets)
-------------------------------------------------
local TRINKET_SLOTS = { INVSLOT_TRINKET1 or 13, INVSLOT_TRINKET2 or 14 }

-- Bag helpers: MoP Classic moved the container API into C_Container.
local function containerNumSlots(bag)
	if C_Container and C_Container.GetContainerNumSlots then return C_Container.GetContainerNumSlots(bag) end
	if GetContainerNumSlots then return GetContainerNumSlots(bag) end
	return 0
end
local function containerItemID(bag, slot)
	if C_Container and C_Container.GetContainerItemID then return C_Container.GetContainerItemID(bag, slot) end
	if GetContainerItemID then return GetContainerItemID(bag, slot) end
	return nil
end

-- name, icon for an itemID (best effort - may be nil until the client caches it).
function C.GetItemDisplay(itemID)
	if not itemID then return nil end
	local name, _, _, _, _, _, _, _, _, icon = GetItemInfo(itemID)
	return name, icon
end

-- Currently equipped trinket for uiSlot 1 or 2: { itemID, name, icon } or nil.
function C.GetCurrentTrinket(uiSlot)
	local invSlot = TRINKET_SLOTS[uiSlot]
	if not invSlot then return nil end
	local itemID = GetInventoryItemID and GetInventoryItemID("player", invSlot)
	if not itemID then return nil end
	local name, icon = C.GetItemDisplay(itemID)
	icon = icon or (GetInventoryItemTexture and GetInventoryItemTexture("player", invSlot))
	return { itemID = itemID, name = name or ("Item #" .. itemID), icon = icon }
end

function C.GetCurrentTrinkets()
	return { [1] = C.GetCurrentTrinket(1), [2] = C.GetCurrentTrinket(2) }
end

-- Every trinket the player currently owns (equipped or in bags), sorted by name:
-- { { itemID, name, icon }, ... }
function C.GetUsableTrinkets()
	local list, seen = {}, {}

	local function consider(itemID)
		if not itemID or seen[itemID] then return end
		local name, _, _, _, _, _, _, _, equipLoc, icon = GetItemInfo(itemID)
		if name and equipLoc == "INVTYPE_TRINKET" then
			seen[itemID] = true
			table.insert(list, { itemID = itemID, name = name, icon = icon })
		end
	end

	for _, invSlot in ipairs(TRINKET_SLOTS) do
		if GetInventoryItemID then consider(GetInventoryItemID("player", invSlot)) end
	end
	for bag = 0, (NUM_BAG_SLOTS or 4) do
		for slot = 1, containerNumSlots(bag) do
			consider(containerItemID(bag, slot))
		end
	end

	table.sort(list, function(a, b) return (a.name or "") < (b.name or "") end)
	return list
end

-------------------------------------------------
-- Cloak (back slot) - tracked as a single item, like a trinket slot.
-------------------------------------------------
local CLOAK_SLOT = INVSLOT_BACK or 15
C.CLOAK_SLOT = CLOAK_SLOT

-- Currently equipped cloak: { itemID, name, icon } or nil.
function C.GetCurrentCloak()
	local itemID = GetInventoryItemID and GetInventoryItemID("player", CLOAK_SLOT)
	if not itemID then return nil end
	local name, icon = C.GetItemDisplay(itemID)
	icon = icon or (GetInventoryItemTexture and GetInventoryItemTexture("player", CLOAK_SLOT))
	return { itemID = itemID, name = name or ("Item #" .. itemID), icon = icon }
end

-- Every cloak the player owns (equipped or in bags), sorted by name.
function C.GetUsableCloaks()
	local list, seen = {}, {}

	local function consider(itemID)
		if not itemID or seen[itemID] then return end
		local name, _, _, _, _, _, _, _, equipLoc, icon = GetItemInfo(itemID)
		if name and equipLoc == "INVTYPE_CLOAK" then
			seen[itemID] = true
			table.insert(list, { itemID = itemID, name = name, icon = icon })
		end
	end

	if GetInventoryItemID then consider(GetInventoryItemID("player", CLOAK_SLOT)) end
	for bag = 0, (NUM_BAG_SLOTS or 4) do
		for slot = 1, containerNumSlots(bag) do
			consider(containerItemID(bag, slot))
		end
	end

	table.sort(list, function(a, b) return (a.name or "") < (b.name or "") end)
	return list
end

-- Equip an item (by ID) into a specific inventory slot (13 / 14 for trinkets,
-- 15 for the cloak).
function C.EquipItem(itemID, invSlot)
	if not itemID then return false, "no item" end
	if InCombatLockdown and InCombatLockdown() then
		return false, "can't change gear in combat"
	end
	if not EquipItemByName then return false, "EquipItemByName not available" end
	local ok, err = pcall(EquipItemByName, itemID, invSlot)
	if ok then return true end
	return false, "equip failed: " .. tostring(err)
end

-------------------------------------------------
-- Specialization / talent group
-------------------------------------------------
function C.GetActiveSpecGroup()
	local f = firstFn(
		CSI and CSI.GetActiveSpecGroup,
		_G.GetActiveSpecGroup,
		_G.GetActiveTalentGroup
	)
	if f then
		local ok, grp = pcall(f)
		if ok and grp then return grp end
	end
	return 1
end

local function specializationFn()
	return firstFn(
		CSI and CSI.GetSpecialization,
		_G.GetSpecialization,
		_G.GetPrimaryTalentTree
	)
end

local function specializationInfoFn()
	return firstFn(
		CSI and CSI.GetSpecializationInfo,
		_G.GetSpecializationInfo
	)
end

-- Number of specs available to the player's class.
local function numSpecs()
	if _G.GetNumSpecializations then
		local ok, n = pcall(_G.GetNumSpecializations)
		if ok and type(n) == "number" and n > 0 then return n end
	end
	local byClass = CSI and CSI.GetNumSpecializationsForClassID
	if byClass then
		local _, _, classID = UnitClass("player")
		if classID then
			local ok, n = pcall(byClass, classID)
			if ok and type(n) == "number" and n > 0 then return n end
		end
	end
	return 0
end

-- Current spec: returns specIndex, specName, specID (any may be nil).
function C.GetCurrentSpec()
	local getSpec = specializationFn()
	if not getSpec then return nil end

	local ok, specIndex = pcall(getSpec)
	if not ok or not specIndex or specIndex == 0 then return nil end

	local name, id
	local getInfo = specializationInfoFn()
	if getInfo then
		-- GetSpecializationInfo(index) -> specID, name, description, icon, role, primaryStat
		local ok2, gid, gname = pcall(getInfo, specIndex)
		if ok2 then id, name = gid, gname end
	end

	return specIndex, name, id
end

-- Dual spec: how many talent groups the player has (1, or 2 once dual spec
-- is bought).
function C.GetNumSpecGroups()
	local f = _G.GetNumSpecGroups or (CSI and CSI.GetNumSpecGroups)
	if f then
		local ok, n = pcall(f)
		if ok and type(n) == "number" and n > 0 then return n end
	end
	return 1
end

-- specID assigned to talent group `group` (1 or 2), or nil. Used to spot when
-- a boss's saved spec is sitting on the player's *inactive* dual-spec group -
-- swapping to it (SetActiveSpecGroup) is free and instant, unlike a real
-- respec which needs a class trainer.
function C.GetSpecIDForGroup(group)
	local getSpec = specializationFn()
	local getInfo = specializationInfoFn()
	if not (getSpec and getInfo) then return nil end
	-- GetSpecialization(isInspect, isPet, specGroup)
	local ok, idx = pcall(getSpec, false, false, group)
	if not ok or not idx or idx == 0 then return nil end
	local ok2, id = pcall(getInfo, idx)
	if ok2 and id and id ~= 0 then return id end
	return nil
end

-- Group/raid role for a specID: "TANK" | "HEALER" | "DAMAGER", or nil.
function C.GetRoleForSpecID(specID)
	if not specID then return nil end
	local byID = firstFn(CSI and CSI.GetSpecializationInfoByID, _G.GetSpecializationInfoByID)
	if byID then
		-- GetSpecializationInfoByID(specID) -> id, name, description, icon, role, ...
		local ok, _, _, _, _, role = pcall(byID, specID)
		if ok and type(role) == "string" and role ~= "" then return role end
	end
	-- Fallback: scan the class's own specs for a matching id.
	local getInfo = specializationInfoFn()
	if getInfo then
		for i = 1, numSpecs() do
			local ok, id, _, _, _, role = pcall(getInfo, i)
			if ok and id == specID and type(role) == "string" and role ~= "" then
				return role
			end
		end
	end
	return nil
end

-- Set the player's group/raid role to match a spec (so a spec change doesn't
-- leave them mis-queued, and the server doesn't bounce the change on a role
-- mismatch). Best-effort; returns the role string on success, false otherwise.
function C.SetPlayerRoleForSpec(specID)
	local role = C.GetRoleForSpecID(specID)
	if not (role and _G.UnitSetRole) then return false end
	local ok = pcall(_G.UnitSetRole, "player", role)
	return ok and role or false
end

-- Every spec the player's class can be, as { specIndex, id, name, icon }.
function C.GetAvailableSpecs()
	local list = {}
	local getInfo = specializationInfoFn()
	local n = numSpecs()
	if not getInfo or n == 0 then return list end

	for i = 1, n do
		local ok, id, name, _, icon = pcall(getInfo, i)
		if ok and id and id ~= 0 then
			table.insert(list, { specIndex = i, id = id, name = name, icon = icon })
		end
	end
	return list
end

-------------------------------------------------
-- Talents (MoP tiered system: 6 tiers x 3 columns per spec group)
-------------------------------------------------
local TALENT_TIERS = _G.MAX_NUM_TALENT_TIERS or _G.MAX_TALENT_TIERS or 6
local TALENT_COLUMNS = 3
do
	local ok, c = pcall(function()
		return Constants and Constants.TalentConsts and Constants.TalentConsts.NumTalentColumns
	end)
	if ok and type(c) == "number" and c > 0 then TALENT_COLUMNS = c end
	TALENT_COLUMNS = TALENT_COLUMNS or _G.NUM_TALENT_COLUMNS or 3
end
C.MAX_TALENT_TIERS = TALENT_TIERS

-- Info for one talent cell. Returns { name, icon, talentID, selected } or nil.
function C.GetTalentChoice(tier, column, specGroup)
	specGroup = specGroup or C.GetActiveSpecGroup()

	-- Preferred: the real C_SpecializationInfo namespace (MoP Classic).
	local csiGet = CSI and CSI.GetTalentInfo
	if csiGet then
		local ok, info = pcall(csiGet, {
			tier = tier,
			column = column,
			groupIndex = specGroup,
		})
		if ok and info and info.name then
			return {
				name = info.name,
				icon = info.icon,
				talentID = info.talentID,
				selected = info.selected and true or false,
			}
		end
		return nil
	end

	-- Fallback: legacy global GetTalentInfo. Its signature varies across
	-- clients, so sniff the return shape rather than assuming one.
	if _G.GetTalentInfo then
		local ok, a, b, c, d, e = pcall(_G.GetTalentInfo, tier, column, specGroup)
		if ok and a ~= nil then
			if type(a) == "number" and type(b) == "string" then
				-- modern shim: talentID, name, icon, selected, ...
				return { name = b, icon = c, talentID = a, selected = d and true or false }
			elseif type(a) == "string" then
				-- Cata-era: name, icon, tier, column, selected, ...
				return { name = a, icon = b, talentID = nil, selected = e and true or false }
			end
		end
	end
	return nil
end

-- { [tier] = selectedColumn or false }, plus { [tier] = "Talent Name" }.
function C.GetCurrentTalents()
	local selection, names = {}, {}
	local specGroup = C.GetActiveSpecGroup()

	for tier = 1, TALENT_TIERS do
		selection[tier] = false
		for column = 1, TALENT_COLUMNS do
			local choice = C.GetTalentChoice(tier, column, specGroup)
			if choice and choice.selected then
				selection[tier] = column
				names[tier] = choice.name
			end
		end
	end

	return selection, names
end

-- NOTE: BossPrep deliberately does NOT open the talent / glyph panes itself.
-- Calling ToggleTalentFrame() / OpenGlyphFrame() from an addon triggers
-- UIParentLoadAddOn() in an insecure context; if that's the first load of
-- Blizzard_TalentUI / Blizzard_GlyphUI the whole addon comes up tainted and
-- the player then can't change talents/glyphs manually until a /reload
-- ("tried to call the protected function 'CastGlyph()'"). So for
-- spec / talents / glyphs the banner just tells the player which panel to
-- open; once they open it, Highlight.lua marks what to change.

-------------------------------------------------
-- Glyphs
-- MoP: 3 major + 3 minor sockets. Majors are the even socket indices (2/4/6).
-- Glyph type numbering: 1 = major, 2 = minor (NOT the pre-Cata prime scheme).
-------------------------------------------------
local GLYPH_MAJOR_TYPE = 1
local MAJOR_SOCKETS = {
	_G.GLYPH_ID_MAJOR_1 or 2,
	_G.GLYPH_ID_MAJOR_2 or 4,
	_G.GLYPH_ID_MAJOR_3 or 6,
}

-- spellID for a given glyphID, via C_GlyphInfo (nil if unavailable).
local function glyphSpellFromID(glyphID)
	if glyphID and C_GlyphInfo and C_GlyphInfo.GetGlyphInfoByID then
		-- GetGlyphInfoByID(id) -> name, glyphType, isKnown, icon, spellID, link
		local ok, _, _, _, _, spellID = pcall(C_GlyphInfo.GetGlyphInfoByID, glyphID)
		if ok then return spellID end
	end
	return nil
end

-- Best-effort name + icon for a stored glyph choice ({ glyphID=, spellID= }).
-- Returns name, icon.
function C.GetGlyphDisplay(choice)
	if type(choice) ~= "table" then return nil end
	local glyphID, spellID = choice.glyphID, choice.spellID

	if glyphID and C_GlyphInfo and C_GlyphInfo.GetGlyphInfoByID then
		local ok, name, _, _, icon, sid = pcall(C_GlyphInfo.GetGlyphInfoByID, glyphID)
		if ok and name and name ~= "" then
			spellID = spellID or sid
			if not icon and spellID and GetSpellTexture then icon = GetSpellTexture(spellID) end
			return name, icon
		end
	end
	-- Fall back to the glyph's spell (this is how Blizzard's own glyph UI
	-- resolves a socketed glyph's name).
	if spellID and GetSpellInfo then
		local n, _, icon = GetSpellInfo(spellID)
		if n then return n, icon end
	end
	return choice.name, choice.icon
end

-- { [1..3] = { glyphID=, spellID=, name=, icon= } or false }, keyed by major slot.
function C.GetCurrentMajorGlyphs()
	local result = {}
	local specGroup = C.GetActiveSpecGroup()

	for uiSlot, socket in ipairs(MAJOR_SOCKETS) do
		-- GetGlyphSocketInfo -> enabled, glyphType, glyphTooltipIndex, glyphSpell, iconFilename, glyphID
		local ok, enabled, _, _, glyphSpell, iconFilename, glyphID = pcall(GetGlyphSocketInfo, socket, specGroup)
		if ok and enabled and (glyphSpell or glyphID) then
			local name
			if glyphSpell and GetSpellInfo then name = GetSpellInfo(glyphSpell) end
			result[uiSlot] = {
				glyphID = glyphID,
				spellID = glyphSpell,
				name = name or ("Glyph #" .. tostring(glyphID or glyphSpell)),
				icon = iconFilename,
			}
		else
			result[uiSlot] = false
		end
	end

	return result
end

-- Every Major glyph your class currently knows, sorted by name:
-- { { name, glyphID, spellID, icon }, ... }.
function C.GetKnownMajorGlyphs()
	local list = {}
	if not (GetNumGlyphs and GetGlyphInfo) then return list end

	local ok, n = pcall(GetNumGlyphs)
	if not ok or not n then return list end

	local seen = {}
	for i = 1, n do
		-- GetGlyphInfo(i) -> name, glyphType, isKnown, icon, glyphID, _, subText
		-- The list is interleaved with "header" rows; skip those.
		local ok2, name, glyphType, isKnown, icon, glyphID = pcall(GetGlyphInfo, i)
		if ok2 and name and name ~= "header" and isKnown
			and glyphType == GLYPH_MAJOR_TYPE and glyphID and not seen[glyphID] then
			seen[glyphID] = true
			table.insert(list, {
				name = name,
				glyphID = glyphID,
				spellID = glyphSpellFromID(glyphID),
				icon = icon,
			})
		end
	end

	table.sort(list, function(a, b) return (a.name or "") < (b.name or "") end)
	return list
end

-- Do two glyph references point at the same glyph? Matches on glyphID or
-- spellID, so choices saved from either API line up.
function C.GlyphChoicesMatch(a, b)
	if not a or not b then return a == b end
	if a.glyphID and b.glyphID and a.glyphID == b.glyphID then return true end
	if a.spellID and b.spellID and a.spellID == b.spellID then return true end
	return false
end

