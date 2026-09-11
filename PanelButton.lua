-- PanelButton.lua
-- A small Prepared badge that clings to the bottom-right edge of Blizzard's
-- talent / glyph panel, so you can open your loadout setup without typing /prep.
--   left-click  -> open the Prepared window
--   right-click -> open the alert options
--
-- Best-effort like the rest of the addon: the talent/glyph UI is load-on-
-- demand and reskinned by things like ElvUI, so we just anchor to whatever
-- Blizzard frame turns up and never hard-fail if it doesn't.

BossPrepPanelButton = {}
local PB = BossPrepPanelButton

local T = BossPrepTheme
local u = T.u

local ICON = "Interface\\AddOns\\Prepared\\Textures\\BossPrepIcon.tga"
local SIZE = 30

local function enabled()
	return not (BossPrepDB and BossPrepDB.settings and BossPrepDB.settings.panelButton == false)
end

local buttons = {} -- [blizzardFrameName] = Button

local function MakeButton(parent)
	local b = CreateFrame("Button", nil, parent)
	b:SetSize(SIZE, SIZE)
	b:SetFrameStrata(parent:GetFrameStrata())
	b:SetFrameLevel((parent:GetFrameLevel() or 1) + 20)
	b:RegisterForClicks("LeftButtonUp", "RightButtonUp")

	-- accent plate, only visible on hover
	local plate = b:CreateTexture(nil, "BACKGROUND")
	plate:SetPoint("TOPLEFT", -2, 2)
	plate:SetPoint("BOTTOMRIGHT", 2, -2)
	plate:SetColorTexture(u(T.color.accent, 0.16))
	plate:Hide()
	b.plate = plate

	local icon = b:CreateTexture(nil, "ARTWORK")
	icon:SetAllPoints()
	icon:SetTexture(ICON)
	icon:SetAlpha(0.92)
	b.iconTex = icon

	b:SetScript("OnEnter", function(self)
		self.plate:Show()
		self.iconTex:SetAlpha(1)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:AddLine("Prepared")
		GameTooltip:AddLine("Left-click  |cffffffffopen loadout setup|r", 0.7, 0.7, 0.7)
		GameTooltip:AddLine("Right-click  |cffffffffalert options|r", 0.7, 0.7, 0.7)
		GameTooltip:Show()
	end)
	b:SetScript("OnLeave", function(self)
		self.plate:Hide()
		self.iconTex:SetAlpha(0.92)
		GameTooltip:Hide()
	end)
	b:SetScript("OnClick", function(_, click)
		if click == "RightButton" then
			if BossPrepOptions then BossPrepOptions:Toggle() end
		elseif BossPrepUI then
			BossPrepUI:Toggle()
		end
	end)

	-- Hang just below the frame's bottom-right corner. Anywhere on the right
	-- edge itself collides with the glyph list once the Glyphs tab is open;
	-- below the corner is clear on all three tabs.
	b:SetPoint("TOPRIGHT", parent, "BOTTOMRIGHT", -6, 1)
	return b
end

local function attach(name)
	if buttons[name] then return end
	local f = _G[name]
	if not f then return end
	local b = MakeButton(f)
	b:SetShown(enabled())
	buttons[name] = b
end

function PB:Attach()
	-- In this client the Specialization / Talents / Glyphs panes are all tabs
	-- of the one PlayerTalentFrame window, so a single button covers them all.
	-- (GlyphFrame is that window's glyph tab, not a separate frame.)
	attach("PlayerTalentFrame")
end

function PB:Refresh()
	for _, b in pairs(buttons) do
		b:SetShown(enabled())
	end
end

BossPrep:On("ADDON_LOADED", function(name)
	if name == "Blizzard_TalentUI" or name == "Blizzard_GlyphUI" or name == "Prepared" then
		PB:Attach()
	end
end)
PB:Attach() -- in case the panels are already loaded
