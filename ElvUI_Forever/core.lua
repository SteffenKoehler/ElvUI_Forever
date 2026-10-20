-- ElvUI_Forever: ElvUI's unit frame bars (health, power, castbar) in the look of the
-- Forever Modern nameplates: dark rounded background with a light rim, gradient fill.
-- Hooks only, ElvUI itself stays untouched.
local E, L, V, P, G = unpack(ElvUI)
local UF = E:GetModule("UnitFrames")
local EP = LibStub("LibElvUIPlugin-1.0")
local addonName = ...

local F = E:NewModule("Forever")
F.Version = GetAddOnMetadata(addonName, "Version")

local MEDIA = "Interface\\AddOns\\ElvUI_Forever\\media\\"
local FILL = MEDIA .. "UnitFill"
local CAST_FILL = MEDIA .. "CastFill"

-- Bar.tga / Rim.tga: region 88,0 - 220,18 in 256 x 32, nine-slice margins left, right,
-- top, bottom (tools/textures.py). Placed around a bar with OUTSETS (left, right, top,
-- bottom) the rim lies 1.5 px outside the bar.
local ART = {tw = 256, th = 32, x0 = 88, y0 = 0, x1 = 220, y1 = 18, l = 6, r = 9, t = 6, b = 8}
local OUTSETS = {3, 5, 3, 5}

P["Forever"] = {
	enable = true,
	castbar = true,
	units = {
		player = true,
		target = true,
		targettarget = true,
		focus = true,
		focustarget = true,
		pet = true,
		party = true,
	},
}

-- unitframeType -> option key (party children share the party option)
local UNIT_KEY = {
	player = "player",
	target = "target",
	targettarget = "targettarget",
	focus = "focus",
	focustarget = "focustarget",
	pet = "pet",
	party = "party",
	partypet = "party",
	partytarget = "party",
}

-- Bars styled so far: [bar] = fill texture (for re-applying after texture updates)
local Styled = {}

-- Nine-slice: corners keep their size (scaled down on very small bars), edges and center
-- stretch
local function CreateSlice(parent, layer, file)
	local xs = {ART.x0, ART.x0 + ART.l, ART.x1 - ART.r, ART.x1}
	local ys = {ART.y0, ART.y0 + ART.t, ART.y1 - ART.b, ART.y1}
	local slice = {}
	for row = 1, 3 do
		for col = 1, 3 do
			local tex = parent:CreateTexture(nil, layer)
			tex:SetTexture(MEDIA .. file)
			tex:SetTexCoord(xs[col] / ART.tw, xs[col + 1] / ART.tw, ys[row] / ART.th, ys[row + 1] / ART.th)
			tex.row, tex.col = row, col
			slice[#slice + 1] = tex
		end
	end
	return slice
end

-- Anchors the slice around rel, grown by OUTSETS. Corner size factor s keeps the
-- corners from overlapping on bars lower than the art (e.g. thin power bars).
local function PlaceSlice(slice, rel)
	local h = rel:GetHeight() or 0
	local s = math.min(1, (h + OUTSETS[3] + OUTSETS[4]) / (ART.t + ART.b))
	if slice.rel == rel and slice.s == s then
		return
	end
	slice.rel, slice.s = rel, s
	local l, r, t, b = ART.l * s, ART.r * s, ART.t * s, ART.b * s
	local left, right, top, bottom = OUTSETS[1] * s, OUTSETS[2] * s, OUTSETS[3] * s, OUTSETS[4] * s
	local xs = {-left, -left + l, right - r, right}
	local ys = {top, top - t, -bottom + b, -bottom}
	local hPoint = {"LEFT", "LEFT", "RIGHT", "RIGHT"}
	local vPoint = {"TOP", "TOP", "BOTTOM", "BOTTOM"}
	for i = 1, #slice do
		local tex = slice[i]
		local c, rw = tex.col, tex.row
		tex:ClearAllPoints()
		tex:SetPoint("TOPLEFT", rel, vPoint[rw] .. hPoint[c], xs[c], ys[rw])
		tex:SetPoint("BOTTOMRIGHT", rel, vPoint[rw + 1] .. hPoint[c + 1], xs[c + 1], ys[rw + 1])
	end
end

local function ShowSlice(slice, shown)
	for i = 1, #slice do
		if shown then
			slice[i]:Show()
		else
			slice[i]:Hide()
		end
	end
end

-- Background (below the fill) and rim (above it: covers the fill's square corners)
local function EnsureArt(bar)
	local art = bar.forever
	if art then
		return art
	end
	art = {}
	local back = CreateFrame("Frame", nil, bar)
	back:SetFrameLevel(math.max(0, bar:GetFrameLevel() - 1))
	back:SetAllPoints(bar)
	art.back = back
	art.bg = CreateSlice(back, "BACKGROUND", "Bar")
	local front = CreateFrame("Frame", nil, bar)
	front:SetFrameLevel(bar:GetFrameLevel() + 1)
	front:SetAllPoints(bar)
	art.front = front
	art.rim = CreateSlice(front, "OVERLAY", "Rim")
	-- keep up with size changes (e.g. after changing the frame height in the options)
	bar:HookScript("OnSizeChanged", function(self)
		if self.forever and self.forever.on then
			self.forever.bg.rel, self.forever.rim.rel = nil, nil
			PlaceSlice(self.forever.bg, self)
			PlaceSlice(self.forever.rim, self)
		end
	end)
	bar.forever = art
	return art
end

local function ApplyBar(bar, fill)
	local art = EnsureArt(bar)
	art.on = true
	art.back:SetFrameLevel(math.max(0, bar:GetFrameLevel() - 1))
	art.front:SetFrameLevel(bar:GetFrameLevel() + 1)
	PlaceSlice(art.bg, bar)
	PlaceSlice(art.rim, bar)
	ShowSlice(art.bg, true)
	ShowSlice(art.rim, true)
	-- ElvUI's square border and its colored background give way to ours
	if bar.backdrop then
		bar.backdrop:SetAlpha(0)
	end
	if bar.bg then
		bar.bg:SetAlpha(0)
	end
	bar:SetStatusBarTexture(fill)
	if bar.texture then
		bar.texture = fill -- oUF power element keeps its own copy
	end
	Styled[bar] = fill
end

local function RemoveBar(bar)
	local art = bar.forever
	if not art or not art.on then
		return
	end
	art.on = false
	ShowSlice(art.bg, false)
	ShowSlice(art.rim, false)
	if bar.backdrop then
		bar.backdrop:SetAlpha(1)
	end
	if bar.bg then
		bar.bg:SetAlpha(1)
	end
	Styled[bar] = nil
	-- ElvUI's own texture comes back with the next UF:Update_StatusBars
end

function F:IsStyled(frame, isCastbar)
	local db = E.db.Forever
	if not (db and db.enable) then
		return false
	end
	if isCastbar and not db.castbar then
		return false
	end
	local key = frame and UNIT_KEY[frame.unitframeType]
	return key and db.units[key] or false
end

local function StyleBar(frame, bar, fill, isCastbar)
	if not bar then
		return
	end
	if F:IsStyled(frame, isCastbar) then
		ApplyBar(bar, fill)
	else
		RemoveBar(bar)
	end
end

function F:UpdateAll()
	UF:Update_AllFrames()
	UF:Update_StatusBars()
end

-- ElvUI's locale if it has the string, else our English fallback
local function T(key, fallback)
	return rawget(L, key) or fallback
end

function F:InsertOptions()
	local function units(info)
		return E.db.Forever.units[info[#info]]
	end
	local function setUnits(info, value)
		E.db.Forever.units[info[#info]] = value
		F:UpdateAll()
	end
	E.Options.args.Forever = {
		order = 100,
		type = "group",
		name = "|cffffd100Forever|r",
		args = {
			header = {order = 1, type = "header", name = "ElvUI Forever " .. (F.Version or "")},
			desc = {
				order = 2,
				type = "description",
				name = "Unit frame bars in the look of the Forever Modern nameplates: rounded bars with a light rim and a gradient fill.\n",
			},
			enable = {
				order = 3,
				type = "toggle",
				name = T("Enable", "Enable"),
				get = function() return E.db.Forever.enable end,
				set = function(_, value)
					E.db.Forever.enable = value
					F:UpdateAll()
				end,
			},
			castbar = {
				order = 4,
				type = "toggle",
				name = T("Castbar", "Castbar"),
				get = function() return E.db.Forever.castbar end,
				set = function(_, value)
					E.db.Forever.castbar = value
					F:UpdateAll()
				end,
				disabled = function() return not E.db.Forever.enable end,
			},
			units = {
				order = 5,
				type = "group",
				guiInline = true,
				name = T("Units", "Units"),
				get = units,
				set = setUnits,
				disabled = function() return not E.db.Forever.enable end,
				args = {
					player = {order = 1, type = "toggle", name = T("Player", "Player")},
					target = {order = 2, type = "toggle", name = T("Target", "Target")},
					targettarget = {order = 3, type = "toggle", name = T("TargetTarget", "Target of Target")},
					focus = {order = 4, type = "toggle", name = T("Focus", "Focus")},
					focustarget = {order = 5, type = "toggle", name = T("FocusTarget", "Focus Target")},
					pet = {order = 6, type = "toggle", name = T("Pet", "Pet")},
					party = {order = 7, type = "toggle", name = T("Party", "Party")},
				},
			},
		},
	}
end

function F:Initialize()
	hooksecurefunc(UF, "Configure_HealthBar", function(_, frame)
		StyleBar(frame, frame.Health, FILL)
	end)
	hooksecurefunc(UF, "Configure_Power", function(_, frame)
		StyleBar(frame, frame.Power, FILL)
	end)
	hooksecurefunc(UF, "Configure_Castbar", function(_, frame)
		StyleBar(frame, frame.Castbar, CAST_FILL, true)
	end)
	-- ElvUI sets the statusbar texture of every bar from its option: ours again on top
	hooksecurefunc(UF, "Update_StatusBars", function()
		for bar, fill in pairs(Styled) do
			bar:SetStatusBarTexture(fill)
			if bar.texture then
				bar.texture = fill
			end
		end
	end)
	EP:RegisterPlugin(addonName, F.InsertOptions)
	F:UpdateAll()
end

E:RegisterModule(F:GetName())
