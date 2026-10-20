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
	aurabars = true,
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

-- Background (below the fill) and rim (above it: covers the fill's square corners).
-- Both hang on art.box, which spans the bar alone or health + power together (one frame
-- around both, rounded only at the top of the health and the bottom of the power bar).
local function EnsureArt(bar)
	local art = bar.forever
	if art then
		return art
	end
	art = {}
	local box = CreateFrame("Frame", nil, bar)
	art.box = box
	local back = CreateFrame("Frame", nil, bar)
	back:SetAllPoints(box)
	art.back = back
	art.bg = CreateSlice(back, "BACKGROUND", "Bar")
	local front = CreateFrame("Frame", nil, bar)
	front:SetAllPoints(box)
	art.front = front
	art.rim = CreateSlice(front, "OVERLAY", "Rim")
	-- keep up with size changes (frame height in the options, power bar shown/hidden)
	box:SetScript("OnSizeChanged", function(self)
		if art.on then
			art.bg.rel, art.rim.rel = nil, nil
			PlaceSlice(art.bg, self)
			PlaceSlice(art.rim, self)
		end
	end)
	bar.forever = art
	return art
end

-- ElvUI's square border and colored background give way to ours (power bars call
-- their background BG)
local function HideElvBackground(bar, hidden)
	local a = hidden and 0 or 1
	if bar.backdrop then
		bar.backdrop:SetAlpha(a)
	end
	if bar.bg then
		bar.bg:SetAlpha(a)
	end
	if bar.BG then
		bar.BG:SetAlpha(a)
	end
end

local function SetFill(bar, fill)
	bar:SetStatusBarTexture(fill)
	if bar.texture then
		bar.texture = fill -- oUF power element keeps its own copy
	end
	Styled[bar] = fill
end

local function ShowArt(art, shown)
	ShowSlice(art.bg, shown)
	ShowSlice(art.rim, shown)
end

-- spanTo: the frame spans down to the bottom of this bar (health + power); backLevel:
-- the background lies below both bars
local function ApplyBar(bar, fill, spanTo, backLevel)
	local art = EnsureArt(bar)
	art.on = true
	local box = art.box
	box:ClearAllPoints()
	box:SetPoint("TOPLEFT", bar, "TOPLEFT", 0, 0)
	box:SetPoint("BOTTOMRIGHT", spanTo or bar, "BOTTOMRIGHT", 0, 0)
	art.back:SetFrameLevel(math.max(0, backLevel or (bar:GetFrameLevel() - 1)))
	art.front:SetFrameLevel(bar:GetFrameLevel() + 1)
	art.bg.rel, art.rim.rel = nil, nil
	PlaceSlice(art.bg, box)
	PlaceSlice(art.rim, box)
	ShowArt(art, true)
	HideElvBackground(bar, true)
	SetFill(bar, fill)
end

-- Bar inside another bar's frame (power below the health): fill only, no own art
local function ApplyFillOnly(bar, fill)
	if bar.forever and bar.forever.on then
		bar.forever.on = false
		ShowArt(bar.forever, false)
	end
	HideElvBackground(bar, true)
	SetFill(bar, fill)
end

local function RemoveBar(bar)
	if bar.forever and bar.forever.on then
		bar.forever.on = false
		ShowArt(bar.forever, false)
	end
	if Styled[bar] then
		HideElvBackground(bar, false)
		Styled[bar] = nil
		-- ElvUI's own texture comes back with the next UF:Update_StatusBars
	end
end

-- part: nil (health/power), "castbar" or "aurabars"
function F:IsStyled(frame, part)
	local db = E.db.Forever
	if not (db and db.enable) then
		return false
	end
	if part and not db[part] then
		return false
	end
	local key = frame and UNIT_KEY[frame.unitframeType]
	return key and db.units[key] or false
end

-- Power bar directly below the health bar (not detached, offset, inset or mini)
local function PowerAttached(frame)
	return frame.USE_POWERBAR and frame.Power and not frame.POWERBAR_DETACHED and not frame.USE_POWERBAR_OFFSET
		and not frame.USE_INSET_POWERBAR and not frame.USE_MINI_POWERBAR
end

local function StyleHealth(frame)
	local health = frame.Health
	if not health then
		return
	end
	if not F:IsStyled(frame) then
		RemoveBar(health)
		return
	end
	if PowerAttached(frame) then
		ApplyBar(health, FILL, frame.Power, frame.Power:GetFrameLevel() - 1)
	else
		ApplyBar(health, FILL)
	end
end

local function StylePower(frame)
	local power = frame.Power
	if not power then
		return
	end
	if not (F:IsStyled(frame) and frame.USE_POWERBAR) then
		RemoveBar(power)
	elseif PowerAttached(frame) then
		ApplyFillOnly(power, FILL)
	else
		ApplyBar(power, FILL)
	end
	-- the health frame spans the power bar only while it is attached
	StyleHealth(frame)
end

-- Icon (castbar, aura bar): ElvUI's square border made invisible, our rim around it
local function StyleIcon(holder, icon, on)
	if not holder or not icon or not holder.SetBackdropBorderColor then
		return
	end
	local art = holder.forever
	if on then
		if not art then
			art = {}
			local front = CreateFrame("Frame", nil, holder)
			front:SetAllPoints(holder)
			front:SetFrameLevel(holder:GetFrameLevel() + 2)
			art.rim = CreateSlice(front, "OVERLAY", "Rim")
			holder.forever = art
		end
		art.on = true
		holder:SetBackdropColor(0, 0, 0, 0)
		holder:SetBackdropBorderColor(0, 0, 0, 0)
		icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
		art.rim.rel = nil
		PlaceSlice(art.rim, icon)
		ShowSlice(art.rim, true)
	elseif art and art.on then
		art.on = false
		ShowSlice(art.rim, false)
		holder:SetTemplate(nil, nil, nil, UF.thinBorders, true)
	end
end

-- Bright spark at the end of the fill (ElvUI's own spark texture, always on while
-- styled, sized to the bar). Off again with ElvUI's spark option when unstyled.
local function StyleCastSpark(frame, castbar, on)
	local spark = castbar.Spark_
	if not spark then
		return
	end
	if on then
		local h = castbar:GetHeight()
		if not h or h <= 0 then
			h = frame.db and frame.db.castbar and frame.db.castbar.height or 18
		end
		castbar.Spark = spark
		castbar.foreverSpark = true
		spark:ClearAllPoints()
		spark:SetPoint("CENTER", castbar:GetStatusBarTexture(), "RIGHT", 0, 0)
		spark:SetWidth(math.max(10, h * 0.9))
		spark:SetHeight(h * 2.2)
		spark:SetAlpha(1)
	elseif castbar.foreverSpark then
		castbar.foreverSpark = nil
		local db = frame.db and frame.db.castbar
		if not (db and db.spark) then
			spark:Hide()
			castbar.Spark = nil
		else
			spark:SetWidth(20)
			spark:SetHeight(db.height * 2)
		end
	end
end

local function StyleCastIcon(castbar, on)
	local icon = castbar.ButtonIcon
	-- ElvUI sets castbar.Icon only while the icon is shown
	StyleIcon(icon and icon.bg, icon, on and castbar.Icon ~= nil)
end

-- Aura bars (ElvUI's buff/debuff bars above player/target): the bar frame's square
-- template made invisible, the status bar inside gets our background, rim and fill
local function StyleAuraBar(barFrame, on)
	local sb = barFrame and barFrame.statusBar
	if not sb then
		return
	end
	if on then
		barFrame:SetBackdropColor(0, 0, 0, 0)
		barFrame:SetBackdropBorderColor(0, 0, 0, 0)
		ApplyBar(sb, FILL)
		StyleIcon(sb.iconHolder, sb.icon, true)
		barFrame.foreverStyled = true
	elseif barFrame.foreverStyled then
		barFrame.foreverStyled = nil
		RemoveBar(sb)
		StyleIcon(sb.iconHolder, sb.icon, false)
		barFrame:SetTemplate(nil, nil, nil, UF.thinBorders, true)
	end
end

local function StyleAuraBars(frame)
	local element = frame.AuraBars
	if not element then
		return
	end
	if not element.foreverHooked then
		element.foreverHooked = true
		-- bars are created on demand: style each new one (oUF calls PostCreateBar(barFrame))
		hooksecurefunc(element, "PostCreateBar", function(barFrame)
			StyleAuraBar(barFrame, F:IsStyled(frame, "aurabars"))
		end)
	end
	local on = F:IsStyled(frame, "aurabars")
	if element.bars then
		for i = 1, #element.bars do
			StyleAuraBar(element.bars[i], on)
		end
	end
end

local function StyleCastbar(frame)
	local castbar = frame.Castbar
	if not castbar then
		return
	end
	if F:IsStyled(frame, "castbar") then
		ApplyBar(castbar, CAST_FILL)
		StyleCastIcon(castbar, true)
		StyleCastSpark(frame, castbar, true)
	else
		RemoveBar(castbar)
		StyleCastIcon(castbar, false)
		StyleCastSpark(frame, castbar, false)
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
			aurabars = {
				order = 4.5,
				type = "toggle",
				name = T("Aura Bars", "Aura Bars"),
				get = function() return E.db.Forever.aurabars end,
				set = function(_, value)
					E.db.Forever.aurabars = value
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
		StyleHealth(frame)
	end)
	hooksecurefunc(UF, "Configure_Power", function(_, frame)
		StylePower(frame)
	end)
	hooksecurefunc(UF, "Configure_Castbar", function(_, frame)
		StyleCastbar(frame)
	end)
	hooksecurefunc(UF, "Configure_AuraBars", function(_, frame)
		StyleAuraBars(frame)
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
