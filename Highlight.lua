-- Highlight.lua
-- While the "SWITCH SETUP" banner is up, wash Blizzard's talent and glyph
-- panels with a soft colour so you can see at a glance what to change:
--   * red  wash  -> this is currently picked and is wrong
--   * green wash (gently breathing) -> switch to this one
--
-- Everything here is best-effort and wrapped so a miss can never break the
-- alert itself. Blizzard's talent/glyph frame names have shifted between
-- client builds, so each lookup tries a few schemes and the code degrades
-- to "no highlight" rather than erroring. `/prep hl` dumps what it found.

BossPrepHighlight = {}
local H = BossPrepHighlight

local GOOD = { 0.15, 1.00, 0.42, 1 } -- switch TO this
local BAD  = { 1.00, 0.20, 0.20, 1 } -- this is wrong

-- User-facing look, from BossPrepDB.settings (Options window):
--   highlightStyle     "WASH" | "OUTLINE" | "BOTH"   (default WASH)
--   highlightIntensity  0..100                        (default 55)
--   highlightPulse      bool                           (default true)
local function hlOpts()
	local s = (BossPrepDB and BossPrepDB.settings) or {}
	local style = s.highlightStyle or "WASH"
	local n = s.highlightIntensity
	if type(n) ~= "number" then n = 55 end
	local intensity = math.max(0, math.min(100, n)) / 100
	local pulse = s.highlightPulse
	if pulse == nil then pulse = true end
	return style, intensity, pulse
end

-------------------------------------------------
-- Marker pool: a soft coloured wash + a hairline border, anchored over a
-- target widget. Green (switch-to) breathes gently; red (wrong) is static.
-------------------------------------------------
local pool, used = {}, 0

local function newMarker()
	local m = CreateFrame("Frame", nil, UIParent)
	m:SetFrameStrata("TOOLTIP")
	m:EnableMouse(false)
	m:Hide()

	m.fill = m:CreateTexture(nil, "ARTWORK")
	m.fill:SetAllPoints()
	m.fill:SetColorTexture(1, 1, 1, 1)

	m.edges = {}
	for _, side in ipairs({ "TOP", "BOTTOM", "LEFT", "RIGHT" }) do
		local e = m:CreateTexture(nil, "OVERLAY")
		if side == "TOP" then
			e:SetPoint("TOPLEFT"); e:SetPoint("TOPRIGHT"); e:SetHeight(1)
		elseif side == "BOTTOM" then
			e:SetPoint("BOTTOMLEFT"); e:SetPoint("BOTTOMRIGHT"); e:SetHeight(1)
		elseif side == "LEFT" then
			e:SetPoint("TOPLEFT"); e:SetPoint("BOTTOMLEFT"); e:SetWidth(1)
		else
			e:SetPoint("TOPRIGHT"); e:SetPoint("BOTTOMRIGHT"); e:SetWidth(1)
		end
		m.edges[side] = e
	end

	-- Slow, smooth breathe for the "switch to this" marker. The Alpha
	-- animation API has varied across builds, so set every spelling.
	m.pulse = m:CreateAnimationGroup()
	m.pulse:SetLooping("BOUNCE")
	local a = m.pulse:CreateAnimation("Alpha")
	a:SetDuration(0.9)
	if a.SetSmoothing then a:SetSmoothing("IN_OUT") end
	if a.SetFromAlpha then a:SetFromAlpha(1) end
	if a.SetToAlpha then a:SetToAlpha(0.55) end
	if a.SetChange then a:SetChange(-0.45) end

	return m
end

local function releaseAll()
	for i = 1, used do
		local m = pool[i]
		if m then
			if m.pulse then m.pulse:Stop() end
			m:Hide()
		end
	end
	used = 0
	H._sig = nil
end

-- Add "highlight this widget" to a plan. opts = { pad=, pulse= }.
-- The plan is applied all at once by H:Apply, which only rebuilds the markers
-- when the plan actually changed (so the driver's frequent re-checks don't
-- restart the pulse animation every tick).
local function want(plan, target, color, opts)
	if not (target and target.IsVisible and target:IsVisible()) then return end
	opts = opts or {}
	table.insert(plan, {
		target = target,
		color = color,
		pad = opts.pad or 2,
		pulse = opts.pulse and true or false,
	})
end

local function planSignature(plan)
	local parts = {}
	for _, p in ipairs(plan) do
		parts[#parts + 1] = tostring(p.target) .. ":" .. tostring(p.color)
			.. ":" .. p.pad .. ":" .. tostring(p.pulse)
	end
	return table.concat(parts, "|")
end

function H:Apply(plan)
	local style, intensity, pulseOn = hlOpts()
	-- Fold the look settings into the signature so dragging the Options
	-- slider rebuilds a highlight that's currently on screen.
	local sig = style .. ":" .. string.format("%.2f", intensity)
		.. ":" .. tostring(pulseOn) .. "#" .. planSignature(plan)
	if sig == self._sig then return end

	releaseAll()
	self._sig = sig

	local showFill = (style == "WASH" or style == "BOTH")
	local heavyBorder = (style == "OUTLINE" or style == "BOTH")

	for _, p in ipairs(plan) do
		used = used + 1
		local m = pool[used]
		if not m then m = newMarker(); pool[used] = m end

		local r, g, b = p.color[1], p.color[2], p.color[3]
		local isBad = (p.color == BAD)

		if showFill then
			-- Red carries a touch more since it doesn't move. Scales with the
			-- intensity slider; even at 0 it stays faintly visible.
			local a = (isBad and 0.08 or 0.05) + intensity * (isBad and 0.30 or 0.26)
			m.fill:SetColorTexture(r, g, b, a)
			m.fill:Show()
		else
			m.fill:Hide()
		end

		local bt, ba
		if heavyBorder then
			bt = 2
			ba = 0.30 + intensity * 0.55
		else
			bt = 1
			ba = showFill and 0.55 or 0 -- wash keeps a hairline for definition
		end
		for side, e in pairs(m.edges) do
			e:SetColorTexture(r, g, b, ba)
			if side == "TOP" or side == "BOTTOM" then e:SetHeight(bt) else e:SetWidth(bt) end
			e:SetShown(ba > 0)
		end

		m:ClearAllPoints()
		m:SetPoint("TOPLEFT", p.target, "TOPLEFT", -p.pad, p.pad)
		m:SetPoint("BOTTOMRIGHT", p.target, "BOTTOMRIGHT", p.pad, -p.pad)
		m:SetFrameStrata("TOOLTIP")
		m:SetAlpha(1)
		m:Show()

		if p.pulse and pulseOn then
			m.pulse:Play()
		else
			m.pulse:Stop()
			m:SetAlpha(1)
		end
	end
end

-------------------------------------------------
-- Talent panel
-------------------------------------------------
-- The Blizzard talent button for a tier/column, across a few name schemes.
function H:TalentButton(tier, column)
	local names = {
		("PlayerTalentFrameTalentsTalentRow%dTalent%d"):format(tier, column),
		("PlayerTalentFrameTalentRow%dTalent%d"):format(tier, column),
		("PlayerTalentFrameTalent%d"):format((tier - 1) * 3 + column),
	}
	for _, n in ipairs(names) do
		if _G[n] then return _G[n] end
	end
	local talents = _G.PlayerTalentFrameTalents
	if talents then
		local row = talents["TalentRow" .. tier]
			or (talents.TalentRow and talents.TalentRow[tier])
		if row then return row["Talent" .. column] or row["talent" .. column] end
	end
	return nil
end

-- Is the talent frame open? We don't gate on which tab is selected - the
-- per-widget IsVisible() check in want() already suppresses markers when the
-- Talents pane isn't the one on screen, and that avoids depending on the
-- tab-index constants (which vary by build).
function H:TalentPaneShown()
	local f = _G.PlayerTalentFrame
	return f and f:IsShown() and true or false
end

function H:PlanTalents(setup, plan)
	if not setup.talents then return end
	if not self:TalentPaneShown() then return end

	local current = BossPrepCompat.GetCurrentTalents()
	for tier = 1, (BossPrepCompat.MAX_TALENT_TIERS or 6) do
		local wantCol = setup.talents[tier]
		if wantCol and current[tier] ~= wantCol then
			-- the one you have picked in this tier (if any) is wrong
			if current[tier] then
				want(plan, self:TalentButton(tier, current[tier]), BAD, { pad = 2 })
			end
			-- the one to switch to
			want(plan, self:TalentButton(tier, wantCol), GOOD, { pad = 2, pulse = true })
		elseif wantCol == false and current[tier] then
			-- tier should be empty - mark the one you have (no green replacement)
			want(plan, self:TalentButton(tier, current[tier]), BAD, { pad = 2 })
		end
	end
end

-------------------------------------------------
-- Glyph panel
-- Glyphs are order-independent (any saved major glyph just has to be socketed
-- in one of the 3 major slots), so the highlight is: red-outline the major
-- sockets you could free up, and green-pulse the glyph(s) to socket in the
-- browse list.
-------------------------------------------------
function H:GlyphPaneShown()
	local f = _G.GlyphFrame
	return f and f:IsShown() and true or false
end

-- Green-mark rows in the glyph browse list whose name matches a missing glyph.
function H:PlanGlyphListRows(missing, plan)
	local wantName = {}
	for _, w in ipairs(missing) do
		if w.name then wantName[w.name:lower()] = true end
	end

	local scroll = _G.GlyphFrameScrollFrame
	local buttons = scroll and scroll.buttons
	if not buttons then
		buttons = {}
		for i = 1, 40 do
			local b = _G["GlyphFrameScrollFrameButton" .. i]
			if not b then break end
			buttons[i] = b
		end
	end

	for _, b in ipairs(buttons) do
		if b and b.IsVisible and b:IsVisible() then
			local txt = (b.name and b.name.GetText and b.name:GetText())
				or (b.GetText and b:GetText())
			if txt and wantName[txt:lower()] then
				want(plan, b, GOOD, { pad = 1, pulse = true })
			end
		end
	end
end

function H:PlanGlyphs(setup, plan)
	if not setup.glyphs then return end
	if not self:GlyphPaneShown() then return end

	local wanted, exhaustive = {}, false
	for i = 1, 3 do
		local w = setup.glyphs[i]
		if w == false then
			exhaustive = true
		elseif w and (w.glyphID or w.spellID) then
			table.insert(wanted, w)
		end
	end
	if #wanted == 0 and not exhaustive then return end

	local current = BossPrepCompat.GetCurrentMajorGlyphs() -- { [1..3] = {..} or false }

	-- Which wanted glyphs aren't socketed anywhere yet?
	local missing = {}
	for _, w in ipairs(wanted) do
		local have = false
		for _, cur in pairs(current) do
			if cur and BossPrepCompat.GlyphChoicesMatch(cur, w) then
				have = true
				break
			end
		end
		if not have then table.insert(missing, w) end
	end
	-- With an exhaustive list we still care about extra sockets even when
	-- nothing's missing.
	if #missing == 0 and not exhaustive then return end

	-- Red-outline any major socket whose current glyph isn't one we want to
	-- keep - those are the slots to swap out. MoP major sockets = 2/4/6, and
	-- Blizzard names the on-screen sockets GlyphFrameGlyph<socketIndex>.
	local MAJOR_SOCKETS = { 2, 4, 6 }
	for uiSlot, socketIndex in ipairs(MAJOR_SOCKETS) do
		local cur = current[uiSlot]
		local keep = false
		if cur then
			for _, w in ipairs(wanted) do
				if BossPrepCompat.GlyphChoicesMatch(cur, w) then
					keep = true
					break
				end
			end
		end
		if cur and not keep then
			want(plan, _G["GlyphFrameGlyph" .. socketIndex], BAD, { pad = 3 })
		end
	end

	self:PlanGlyphListRows(missing, plan)
end

-------------------------------------------------
-- Refresh
-------------------------------------------------
function H:Enabled()
	if not (BossPrepDB and BossPrepDB.settings) then return true end
	return BossPrepDB.settings.panelHighlights ~= false
end

function H:DoRefresh()
	local plan = {}

	repeat
		if not self:Enabled() then break end

		-- Only while the banner is actually up.
		local banner = BossPrepAlert and BossPrepAlert.frame
		if not (banner and banner:IsShown()) then break end

		local instanceKey, bossKey = BossPrepDetection:GetCurrentBoss()
		if not (instanceKey and bossKey) then break end
		local setup = BossPrepProfiles:ResolveBossLoadout(instanceKey, bossKey)
		if BossPrepProfiles:LoadoutIsEmpty(setup) then break end

		-- After a spec swap the panel can still preview the group you left; its
		-- talent/glyph widgets are then the wrong spec's, so don't mark them
		-- until it catches up (the fix button prompts the tab switch).
		local ptf = _G.PlayerTalentFrame
		if ptf and ptf.talentGroup and BossPrepCompat.GetActiveSpecGroup
			and ptf.talentGroup ~= BossPrepCompat.GetActiveSpecGroup() then
			break
		end

		self:PlanTalents(setup, plan)
		self:PlanGlyphs(setup, plan)
	until true

	self:Apply(plan)
end

function H:Refresh()
	local ok, err = pcall(function() self:DoRefresh() end)
	if not ok then
		releaseAll()
		if BossPrepDB and BossPrepDB.settings and BossPrepDB.settings.debug then
			print("|cff33ff99Prepared|r highlight error: " .. tostring(err))
		end
	end
end

-------------------------------------------------
-- Driver: while the banner is up, re-mark a few times a second. Cheaper and
-- far more robust than hooking Blizzard's list-scroll / tab-switch internals.
-------------------------------------------------
local driver = CreateFrame("Frame")
driver:Hide()
driver.t = 0
driver:SetScript("OnUpdate", function(self, elapsed)
	self.t = self.t + elapsed
	if self.t < 0.2 then return end
	self.t = 0

	local banner = BossPrepAlert and BossPrepAlert.frame
	if not (banner and banner:IsShown()) then
		if used > 0 then releaseAll() end
		self:Hide()
		return
	end
	H:Refresh()
end)

-- Banner appeared (or a panel opened while it's up).
function H:Kick()
	local banner = BossPrepAlert and BossPrepAlert.frame
	if banner and banner:IsShown() then driver:Show() end
	self:Refresh()
end

-- Banner gone.
function H:Stop()
	driver:Hide()
	releaseAll()
end

-------------------------------------------------
-- Hook the Blizzard panels once they exist (both are load-on-demand). The
-- driver covers anything a missed hook wouldn't.
-------------------------------------------------
local hooked = {}
local function hookShowHide(name)
	local f = _G[name]
	if not f or hooked[name] then return end
	hooked[name] = true
	f:HookScript("OnShow", function() H:Kick() end)
	f:HookScript("OnHide", function() H:Refresh() end)
end

local function tryHooks()
	hookShowHide("PlayerTalentFrame")
	hookShowHide("GlyphFrame")
	for i = 1, 4 do
		local tab = _G["PlayerTalentFrameTab" .. i]
		if tab and not hooked["tab" .. i] then
			hooked["tab" .. i] = true
			tab:HookScript("OnClick", function() H:Refresh() end)
		end
	end
end

BossPrep:On("ADDON_LOADED", function(name)
	if name == "Blizzard_TalentUI" or name == "Blizzard_GlyphUI" or name == "Prepared" then
		tryHooks()
	end
end)
tryHooks() -- in case they're already loaded

-------------------------------------------------
-- `/prep hl` - probe what the highlight code can see right now
-------------------------------------------------
local function frameKind(v)
	if type(v) ~= "table" then return nil end
	local ok, ot = pcall(function() return v.GetObjectType and v:GetObjectType() end)
	if ok then return ot end
	return nil
end

-- List global frames whose name contains `needle` (case-insensitive). Helps
-- find the real Blizzard/ElvUI frame names on a client build we haven't seen.
local function dumpMatching(needle, max)
	needle = needle:lower()
	local hits = {}
	for name, v in pairs(_G) do
		if type(name) == "string" and name:lower():find(needle, 1, true) then
			local kind = frameKind(v)
			if kind == "Frame" or kind == "Button" or kind == "CheckButton" then
				hits[#hits + 1] = name
			end
		end
	end
	table.sort(hits)
	print(("  -- %d global frames matching '%s':"):format(#hits, needle))
	for i = 1, math.min(#hits, max or 40) do
		local f = _G[hits[i]]
		local shown = ""
		local ok, s = pcall(function() return f:IsShown() end)
		if ok then shown = s and " [shown]" or "" end
		print("     " .. hits[i] .. shown)
	end
	if #hits > (max or 40) then print("     ...(" .. (#hits - (max or 40)) .. " more)") end
end

function H:Debug()
	print("|cff33ff99Prepared|r highlight probe:")
	print("  Highlight.lua loaded OK.  ElvUI: " .. tostring(_G.ElvUI ~= nil or _G.ElvPrivateDB ~= nil))

	local banner = BossPrepAlert and BossPrepAlert.frame
	print("  banner shown: " .. tostring(banner and banner:IsShown() or false))
	local ik, bk = BossPrepDetection:GetCurrentBoss()
	print("  tracked boss: " .. tostring(ik) .. " / " .. tostring(bk))
	local setup = ik and bk and BossPrepProfiles:ResolveBossLoadout(ik, bk)
	print("  resolved loadout empty: " .. tostring(BossPrepProfiles:LoadoutIsEmpty(setup))
		.. (setup and ("  talents=" .. tostring(next(setup.talents or {}) ~= nil) .. " glyphs=" .. tostring(next(setup.glyphs or {}) ~= nil)) or ""))

	local ptf = _G.PlayerTalentFrame or _G.PlayerSpellsFrame or _G.ClassTalentFrame
	print("  talent frame global: " .. (ptf and (ptf:GetName() or "?") or "NONE of PlayerTalentFrame/PlayerSpellsFrame/ClassTalentFrame")
		.. (ptf and ("  shown=" .. tostring(ptf:IsShown())) or ""))
	for tier = 1, (BossPrepCompat.MAX_TALENT_TIERS or 6) do
		local b = self:TalentButton(tier, 1)
		print(("  tier %d col1 button: %s"):format(tier, b and (b:GetName() or "(unnamed frame)") or "MISSING"))
	end

	local gf = _G.GlyphFrame
	print("  GlyphFrame: " .. tostring(gf ~= nil) .. (gf and ("  shown=" .. tostring(gf:IsShown())) or ""))
	print("  markers active: " .. used)

	-- Open the panel you care about, THEN run /prep hl, so the real names show:
	dumpMatching("talent", 50)
	dumpMatching("glyph", 50)
end
