-- Talent window: all three trees side by side in ElvUI style, pet talents and glyphs as
-- further views of the same window (idea from DragonUI by NeticSoul, MIT; own
-- implementation, no retail art). Blizzard's talent frame is redirected to it.
local E, L, V, P, G = unpack(ElvUI)
local S = E:GetModule("Skins")
local F = E:GetModule("Forever")

local NUM_TREES, NUM_COLUMNS, POINTS_PER_TIER = 3, 4, 5
local BUTTON, STEP_X, STEP_Y = 32, 48, 44
local TREE_PAD, HEADER, TREE_BOTTOM = 14, 40, 12
local TREE_W = 2 * TREE_PAD + (NUM_COLUMNS - 1) * STEP_X + BUTTON
local TREE_GAP, MARGIN, TOP_BAR, FOOTER = 8, 10, 34, 40
local CONTENT_W = NUM_TREES * TREE_W + (NUM_TREES - 1) * TREE_GAP
local LINE = 2

local COLOR_MAX = {1, 0.82, 0}
local COLOR_OPEN = {0.25, 1, 0.25}
local COLOR_LINE_ON = {1, 0.82, 0}
local COLOR_LINE_OFF = {0.4, 0.4, 0.4}
local COLOR_WHITE = {1, 1, 1}

local Window
local viewGroup = 1
local viewMode = "talents" -- "talents", "pet", "glyphs"

local function Enabled()
	local db = E.db.Forever
	return db and db.enable and db.talents
end

-- 3.3.5 has no Region:SetShown
local function SetShown(region, show)
	if show then
		region:Show()
	else
		region:Hide()
	end
end

local function HasPetTalents()
	return HasPetUI() and (GetNumTalentTabs(false, true) or 0) > 0
end

local function PetGroup()
	return GetActiveTalentGroup(false, true) or 1
end

-- Group shown by a tree: the pet has its own active group, the player the viewed one
local function TreeGroup(isPet)
	return isPet and PetGroup() or viewGroup
end

local function PreviewMode(isPet)
	if not GetCVarBool("previewTalents") then
		return false
	end
	return isPet or viewGroup == GetActiveTalentGroup(false, false)
end

local function ButtonOffset(tier, column)
	return TREE_PAD + (column - 1) * STEP_X, -(HEADER + (tier - 1) * STEP_Y)
end

local function SlotOffset(slot)
	return MARGIN + (slot - 1) * (TREE_W + TREE_GAP)
end

--------------------------------
-- Talent buttons

local function TalentOnEnter(self)
	GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
	GameTooltip:SetTalent(self.tab, self.index, false, self.isPet, TreeGroup(self.isPet), PreviewMode(self.isPet))
	GameTooltip:Show()
end

local function TalentOnClick(self, button)
	local isPet = self.isPet
	local group = TreeGroup(isPet)
	if not isPet and group ~= GetActiveTalentGroup(false, false) then
		return
	end
	if GetCVarBool("previewTalents") then
		AddPreviewTalentPoints(self.tab, self.index, button == "RightButton" and -1 or 1, isPet, group)
	elseif button == "LeftButton" then
		LearnTalent(self.tab, self.index, isPet, group)
	end
end

local function CreateTalentButton(tree)
	local b = CreateFrame("Button", nil, tree)
	b:Size(BUTTON)
	b:SetTemplate("Default")
	b:SetFrameLevel(tree:GetFrameLevel() + 3)
	b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	b:StyleButton(nil, true)

	b.icon = b:CreateTexture(nil, "ARTWORK")
	b.icon:SetInside()
	b.icon:SetTexCoord(unpack(E.TexCoords))

	b.rank = b:CreateFontString(nil, "OVERLAY")
	b.rank:FontTemplate(nil, 12, "OUTLINE")
	b.rank:Point("BOTTOMRIGHT", b, "BOTTOMRIGHT", 3, -3)

	b:SetScript("OnEnter", TalentOnEnter)
	b:SetScript("OnLeave", GameTooltip_Hide)
	b:SetScript("OnClick", TalentOnClick)
	return b
end

--------------------------------
-- Prerequisite lines: straight down in the same column, sideways in the same tier,
-- otherwise sideways at the prerequisite's height and then down (as Blizzard routes them)

local function GetLine(tree)
	tree.numLines = tree.numLines + 1
	local line = tree.lines[tree.numLines]
	if not line then
		line = tree.lineFrame:CreateTexture(nil, "ARTWORK")
		line:SetTexture(E.media.blankTex)
		tree.lines[tree.numLines] = line
	end
	line:ClearAllPoints()
	line:Show()
	return line
end

local function DrawSegment(tree, x1, y1, x2, y2, color)
	local line = GetLine(tree)
	line:SetVertexColor(unpack(color))
	if x1 == x2 then
		line:Point("TOPLEFT", tree, "TOPLEFT", x1 - LINE / 2, math.max(y1, y2))
		line:Size(LINE, math.abs(y1 - y2))
	else
		line:Point("TOPLEFT", tree, "TOPLEFT", math.min(x1, x2), y1 + LINE / 2)
		line:Size(math.abs(x1 - x2), LINE)
	end
end

local function DrawPrereq(tree, ptier, pcol, tier, column, color)
	local px, py = ButtonOffset(ptier, pcol)
	local tx, ty = ButtonOffset(tier, column)
	local half = BUTTON / 2
	if pcol == column then
		DrawSegment(tree, px + half, py - BUTTON, tx + half, ty, color)
	elseif ptier == tier then
		local fromX = pcol < column and px + BUTTON or px
		local toX = pcol < column and tx or tx + BUTTON
		DrawSegment(tree, fromX, py - half, toX, ty - half, color)
	else
		local fromX = pcol < column and px + BUTTON or px
		DrawSegment(tree, fromX, py - half, tx + half, py - half, color)
		DrawSegment(tree, tx + half, py - half, tx + half, ty, color)
	end
end

--------------------------------
-- Trees

-- Blizzard's tree art from the client: 4 pieces forming a 300 x 331 picture (the right
-- and bottom pieces are mostly its dark vignette). The tree is much narrower and taller,
-- so the picture is scaled to the tree's height and a vertical strip of it is shown
-- (cover crop, no distortion), centered a bit left of the middle where most motifs are.
local ART_W, ART_H, ART_FOCUS = 300, 331, 135
-- suffix, x, y, width, height of the piece in the picture, texture width, height
local ART = {
	{"TopLeft", 0, 0, 256, 256, 256, 256},
	{"TopRight", 256, 0, 44, 256, 64, 256},
	{"BottomLeft", 0, 256, 256, 75, 256, 128},
	{"BottomRight", 256, 256, 44, 75, 64, 128},
}

local function PlaceArt(tree)
	local width, height = tree:GetWidth(), tree:GetHeight()
	local s = height / ART_H
	local cropW = width / s
	local x0 = math.max(0, math.min(ART_W - cropW, ART_FOCUS - cropW / 2))
	for _, piece in ipairs(tree.art) do
		local p, tex = piece.def, piece.tex
		local ix0, ix1 = math.max(p[2], x0), math.min(p[2] + p[4], x0 + cropW)
		tex:ClearAllPoints()
		if ix1 > ix0 then
			tex:Point("TOPLEFT", tree, "TOPLEFT", (ix0 - x0) * s, -p[3] * s)
			tex:Size((ix1 - ix0) * s, p[5] * s)
			tex:SetTexCoord((ix0 - p[2]) / p[6], (ix1 - p[2]) / p[6], 0, p[5] / p[7])
			piece.used = true
		else
			piece.used = false
		end
	end
end

local function CreateTree(slot, height, tab, isPet)
	local tree = CreateFrame("Frame", nil, Window)
	tree:Size(TREE_W, height)
	tree:Point("TOPLEFT", Window, "TOPLEFT", SlotOffset(slot), -TOP_BAR)
	tree:SetTemplate("Default")

	tree.art = {}
	for i, def in ipairs(ART) do
		-- BORDER, not BACKGROUND: the ElvUI backdrop lives in BACKGROUND and the order
		-- within one layer is undefined (the backdrop covered the art at random)
		local tex = tree:CreateTexture(nil, "BORDER")
		tex:SetAlpha(0.7)
		tree.art[i] = {tex = tex, def = def}
	end
	PlaceArt(tree)

	-- Darker band behind the tree name
	tree.headerShade = tree:CreateTexture(nil, "ARTWORK")
	tree.headerShade:SetTexture(E.media.blankTex)
	tree.headerShade:SetVertexColor(0, 0, 0, 0.55)
	tree.headerShade:Point("TOPLEFT", tree, "TOPLEFT", 1, -1)
	tree.headerShade:Point("TOPRIGHT", tree, "TOPRIGHT", -1, -1)
	tree.headerShade:Height(HEADER - 8)

	tree.icon = tree:CreateTexture(nil, "ARTWORK")
	tree.icon:Size(22)
	tree.icon:Point("TOPLEFT", tree, "TOPLEFT", 8, -8)
	tree.icon:SetTexCoord(unpack(E.TexCoords))

	tree.name = tree:CreateFontString(nil, "OVERLAY")
	tree.name:FontTemplate(nil, 13, "OUTLINE")
	tree.name:Point("LEFT", tree.icon, "RIGHT", 6, 0)

	tree.points = tree:CreateFontString(nil, "OVERLAY")
	tree.points:FontTemplate(nil, 13, "OUTLINE")
	tree.points:Point("RIGHT", tree, "TOPRIGHT", -8, -19)

	tree.lineFrame = CreateFrame("Frame", nil, tree)
	tree.lineFrame:SetAllPoints()
	tree.lineFrame:SetFrameLevel(tree:GetFrameLevel() + 2)
	tree.lines, tree.numLines = {}, 0
	tree.buttons = {}
	tree.tab, tree.isPet = tab, isPet
	return tree
end

local function SetTreeArt(tree, background)
	for _, piece in ipairs(tree.art) do
		if background and piece.used then
			piece.tex:SetTexture("Interface\\TalentFrame\\" .. background .. "-" .. piece.def[1])
			piece.tex:Show()
		else
			piece.tex:Hide()
		end
	end
end

local function UpdateTree(tree, pointsLeft)
	local t, isPet = tree.tab, tree.isPet
	local group = TreeGroup(isPet)
	local preview = PreviewMode(isPet)
	local name, icon, spent, background, previewSpent = GetTalentTabInfo(t, false, isPet, group)
	local treeSpent = (spent or 0) + (preview and previewSpent or 0)
	local canSpend = pointsLeft > 0 and (isPet or group == GetActiveTalentGroup(false, false))

	tree.icon:SetTexture(icon)
	tree.name:SetText(name)
	tree.points:SetText(treeSpent)
	SetTreeArt(tree, background)

	for _, line in ipairs(tree.lines) do
		line:Hide()
	end
	tree.numLines = 0

	local numTalents = GetNumTalents(t, false, isPet) or 0
	for i = 1, numTalents do
		local b = tree.buttons[i] or CreateTalentButton(tree)
		tree.buttons[i] = b
		local _, tIcon, tier, column, rank, maxRank, _, _, previewRank = GetTalentInfo(t, i, false, isPet, group)
		if preview then
			rank = previewRank
		end
		-- Per prerequisite: tier, column, isLearnable, isPreviewLearnable (met = maxed)
		local prereqs = {GetTalentPrereqs(t, i, false, isPet, group)}
		local meetsPrereq = true
		for k = 1, #prereqs - 1, 4 do
			if not prereqs[k + (preview and 3 or 2)] then
				meetsPrereq = false
			end
		end
		local available = meetsPrereq and treeSpent >= (tier - 1) * POINTS_PER_TIER
		local lit = rank > 0 or (available and canSpend)

		b.tab, b.index, b.isPet = t, i, isPet
		b:ClearAllPoints()
		b:Point("TOPLEFT", tree, "TOPLEFT", ButtonOffset(tier, column))
		b.icon:SetTexture(tIcon)
		b.icon:SetDesaturated(not lit)
		b.icon:SetAlpha(lit and 1 or 0.6)

		local color
		if maxRank and maxRank > 0 and rank >= maxRank then
			color = COLOR_MAX
		elseif lit then
			color = COLOR_OPEN
		end
		if color then
			b:SetBackdropBorderColor(unpack(color))
			b.rank:SetText(rank)
			b.rank:SetTextColor(unpack(color))
		else
			b:SetBackdropBorderColor(unpack(E.media.bordercolor))
			b.rank:SetText(rank > 0 and rank or "")
		end
		b:Show()

		for k = 1, #prereqs - 1, 4 do
			DrawPrereq(tree, prereqs[k], prereqs[k + 1], tier, column, meetsPrereq and COLOR_LINE_ON or COLOR_LINE_OFF)
		end
	end
	for i = numTalents + 1, #tree.buttons do
		tree.buttons[i]:Hide()
	end
end

--------------------------------
-- Pet view: model and info left, talent tree in the middle

local function CreatePetView(height)
	local view = CreateFrame("Frame", nil, Window)
	view:SetAllPoints()

	local info = CreateFrame("Frame", nil, view)
	info:Size(TREE_W, height)
	info:Point("TOPLEFT", Window, "TOPLEFT", SlotOffset(1), -TOP_BAR)
	info:SetTemplate("Default")

	info.name = info:CreateFontString(nil, "OVERLAY")
	info.name:FontTemplate(nil, 14, "OUTLINE")
	info.name:Point("TOP", info, "TOP", 0, -12)
	info.family = info:CreateFontString(nil, "OVERLAY")
	info.family:FontTemplate(nil, 12, "OUTLINE")
	info.family:Point("TOP", info.name, "BOTTOM", 0, -4)

	info.model = CreateFrame("PlayerModel", nil, info)
	info.model:Point("TOPLEFT", info, "TOPLEFT", 4, -50)
	info.model:Point("BOTTOMRIGHT", info, "BOTTOMRIGHT", -4, 4)

	view.info = info
	-- Pet talent trees have a single tab
	view.tree = CreateTree(2, height, 1, true)
	view.tree:SetParent(view)
	return view
end

local function UpdatePetView(pointsLeft)
	local view = Window.petView
	local info = view.info
	info.name:SetText(UnitName("pet") or "")
	local family = UnitCreatureFamily("pet")
	local level = UnitLevel("pet")
	info.family:SetText(family and level and format("%s %d", family, level) or family or "")
	info.model:SetUnit("pet")
	UpdateTree(view.tree, pointsLeft)
end

--------------------------------
-- Glyph view: Blizzard's glyph page from the client atlas Interface\Spellbook\UI-GlyphFrame
-- (512 x 512): the parchment with the circle, orbs and rings for the six sockets.
-- Coordinates measured from the atlas; socket positions from Blizzard's frame.

local GLYPH_ATLAS = "Interface\\Spellbook\\UI-GlyphFrame"
local GLYPH_LOCK = "Interface\\LFGFrame\\UI-LFG-ICON-LOCK"
-- Atlas pixel rectangles: left, top, right, bottom
-- Inner parchment (the crop ElvUI's glyph skin uses), framed by an ElvUI border
local GLYPH_PARCHMENT = {21, 72, 336, 412}
local GLYPH_CENTER = {179, 237} -- center of the circle (fitted to its rings)
local GLYPH_SPRITE = {
	ringMinor = {404, 18, 465, 79},
	ringMajor = {394, 166, 474, 247},
	glow = {382, 251, 486, 355},
	disc = {402, 360, 464, 422},
	orbMajor = {2, 448, 64, 510},
	orbMinor = {69, 448, 131, 510},
}
-- Socket centers relative to the circle center (atlas pixels, y up): the six circles
-- printed on the parchment, a regular hexagon of radius 110; 1, 4, 6 are major
local GLYPH_POS = {{0, 110}, {0, -110}, {-95, 55}, {95, -55}, {95, 55}, {-95, -55}}
-- Ring, orb and rune size in atlas pixels
local GLYPH_SIZE = {
	major = {ring = 86, orb = 62, rune = 56},
	minor = {ring = 68, orb = 48, rune = 42},
}
-- Rune colors as on Blizzard's page: red on the orange orb, blue on the silver one
local RUNE_MAJOR = {1, 0.25, 0}
local RUNE_MINOR = {0, 0.25, 1}

local function SetSprite(tex, rect)
	tex:SetTexture(GLYPH_ATLAS)
	tex:SetTexCoord(rect[1] / 512, rect[3] / 512, rect[2] / 512, rect[4] / 512)
end

local function GlyphOnEnter(self)
	self.hover:Show()
	GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
	GameTooltip:SetGlyph(self.socket, viewGroup)
	local _, _, spell = GetGlyphSocketInfo(self.socket, viewGroup)
	if spell and viewGroup == GetActiveTalentGroup(false, false) then
		GameTooltip:AddLine("Shift-Rechtsklick: Glyphe entfernen", 0.6, 0.6, 0.6)
	end
	GameTooltip:Show()
end

local function GlyphOnLeave(self)
	self.hover:Hide()
	GameTooltip:Hide()
end

local function GlyphOnClick(self, button)
	local socket, group = self.socket, viewGroup
	local _, _, spell = GetGlyphSocketInfo(socket, group)
	if IsModifiedClick("CHATLINK") and ChatEdit_GetActiveWindow() then
		local link = GetGlyphLink(socket, group)
		if link then
			ChatEdit_InsertLink(link)
		end
		return
	end
	if group ~= GetActiveTalentGroup(false, false) then
		return
	end
	if button == "RightButton" then
		if IsShiftKeyDown() and spell then
			StaticPopup_Show("FOREVER_GLYPH_REMOVE", GetSpellInfo(spell), nil, socket)
		end
	elseif GlyphMatchesSocket(socket) then
		if spell then
			StaticPopup_Show("FOREVER_GLYPH_REPLACE", nil, nil, socket)
		else
			PlaceGlyphInSocket(socket)
		end
	end
end

StaticPopupDialogs.FOREVER_GLYPH_REMOVE = {
	text = CONFIRM_REMOVE_GLYPH or "Remove %s?",
	button1 = YES,
	button2 = NO,
	OnAccept = function(_, socket)
		RemoveGlyphFromSocket(socket)
	end,
	timeout = 0,
	whileDead = 1,
	hideOnEscape = 1,
}
StaticPopupDialogs.FOREVER_GLYPH_REPLACE = {
	text = CONFIRM_GLYPH_PLACEMENT or "Replace the existing glyph?",
	button1 = YES,
	button2 = NO,
	OnAccept = function(_, socket)
		PlaceGlyphInSocket(socket)
	end,
	timeout = 0,
	whileDead = 1,
	hideOnEscape = 1,
}

local function CreateGlyphView(height)
	local view = CreateFrame("Frame", nil, Window)
	view:Size(CONTENT_W, height)
	view:Point("TOPLEFT", Window, "TOPLEFT", MARGIN, -TOP_BAR)
	view:SetTemplate("Default")

	local p = GLYPH_PARCHMENT
	local s = (view:GetHeight() - 16) / (p[4] - p[2])
	local page = CreateFrame("Frame", nil, view)
	page:SetSize((p[3] - p[1]) * s, (p[4] - p[2]) * s)
	page:SetPoint("CENTER", view, "CENTER", 0, 0)
	page:SetTemplate("Default")
	local art = page:CreateTexture(nil, "BORDER") -- above the ElvUI backdrop
	SetSprite(art, p)
	art:SetInside(page)
	view.art = art

	-- Circle center relative to the art's center
	local cx = (GLYPH_CENTER[1] - (p[1] + p[3]) / 2) * s
	local cy = ((p[2] + p[4]) / 2 - GLYPH_CENTER[2]) * s

	view.sockets = {}
	for i = 1, 6 do
		local b = CreateFrame("Button", nil, view)
		b:SetFrameLevel(page:GetFrameLevel() + 3)
		b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
		b:SetPoint("CENTER", art, "CENTER", cx + GLYPH_POS[i][1] * s, cy + GLYPH_POS[i][2] * s)
		b.scale = s

		b.orb = b:CreateTexture(nil, "BACKGROUND")
		b.orb:SetPoint("CENTER")
		b.rune = b:CreateTexture(nil, "ARTWORK")
		b.rune:SetPoint("CENTER")
		b.ring = b:CreateTexture(nil, "OVERLAY")
		b.ring:SetPoint("CENTER")
		b.lock = b:CreateTexture(nil, "OVERLAY")
		b.lock:SetTexture(GLYPH_LOCK)
		b.lock:SetPoint("CENTER")
		-- Lights up while a glyph for this socket is on the cursor
		b.glow = b:CreateTexture(nil, "OVERLAY")
		SetSprite(b.glow, GLYPH_SPRITE.glow)
		b.glow:SetBlendMode("ADD")
		b.glow:SetPoint("CENTER")
		b.hover = b:CreateTexture(nil, "HIGHLIGHT")
		SetSprite(b.hover, GLYPH_SPRITE.glow)
		b.hover:SetBlendMode("ADD")
		b.hover:SetAlpha(0.5)
		b.hover:SetPoint("CENTER")
		b.hover:Hide()

		b.socket = i
		b:SetScript("OnEnter", GlyphOnEnter)
		b:SetScript("OnLeave", GlyphOnLeave)
		b:SetScript("OnClick", GlyphOnClick)
		view.sockets[i] = b
	end

	return view
end

local function UpdateGlyphView()
	local active = viewGroup == GetActiveTalentGroup(false, false)
	for i, b in ipairs(Window.glyphView.sockets) do
		local enabled, glyphType, spell, icon = GetGlyphSocketInfo(i, viewGroup)
		local minor = glyphType == 2
		local size = minor and GLYPH_SIZE.minor or GLYPH_SIZE.major
		local s = b.scale
		b:SetSize(size.ring * s, size.ring * s)
		b.ring:SetSize(size.ring * s, size.ring * s)
		b.orb:SetSize(size.orb * s, size.orb * s)
		b.rune:SetSize(size.rune * s, size.rune * s)
		b.lock:SetSize(size.orb * 0.5 * s, size.orb * 0.5 * s)
		b.glow:SetSize(size.ring * 1.3 * s, size.ring * 1.3 * s)
		b.hover:SetSize(size.ring * 1.2 * s, size.ring * 1.2 * s)
		SetSprite(b.ring, minor and GLYPH_SPRITE.ringMinor or GLYPH_SPRITE.ringMajor)

		if not enabled then
			SetSprite(b.orb, GLYPH_SPRITE.disc)
			b.orb:SetDesaturated(true)
			b.orb:SetAlpha(0.8)
			b.ring:SetDesaturated(true)
			b.rune:Hide()
			b.lock:Show()
		else
			SetSprite(b.orb, minor and GLYPH_SPRITE.orbMinor or GLYPH_SPRITE.orbMajor)
			b.orb:SetDesaturated(not active)
			b.ring:SetDesaturated(not active)
			b.lock:Hide()
			if spell then
				b.orb:SetAlpha(1)
				b.rune:SetTexture(icon)
				b.rune:SetVertexColor(unpack(minor and RUNE_MINOR or RUNE_MAJOR))
				b.rune:SetDesaturated(not active)
				b.rune:Show()
			else
				-- Free socket: dim orb
				b.orb:SetAlpha(0.45)
				b.rune:Hide()
				end
		end
		SetShown(b.glow, enabled and active and GlyphMatchesSocket(i))
	end
end

--------------------------------
-- Window

local function UpdateSpecTabs(numGroups, active)
	for g, tab in ipairs(Window.specTabs) do
		SetShown(tab, numGroups > 1 and viewMode ~= "pet")
		-- Like Blizzard's spec tabs: icon and name of the tree with the most points
		local mainName, mainIcon, mainPoints
		for t = 1, NUM_TREES do
			local name, icon, points = GetTalentTabInfo(t, false, false, g)
			if points and points > (mainPoints or 0) then
				mainName, mainIcon, mainPoints = name, icon, points
			end
		end
		if mainName then
			tab:SetText(format("|T%s:16:16:0:0:64:64:5:59:5:59|t %s", mainIcon, mainName))
		else
			tab:SetText("Spec " .. g)
		end
		tab.text:SetTextColor(unpack(g == viewGroup and COLOR_MAX or COLOR_WHITE))
		SetShown(tab.active, g == active)
	end
	SetShown(Window.activate, numGroups > 1 and viewMode ~= "pet" and viewGroup ~= active)
end

local function UpdateWindow()
	if not (Window and Window:IsShown()) then
		return
	end
	if viewMode == "pet" and not HasPetTalents() then
		viewMode = "talents"
	end
	local numGroups = GetNumTalentGroups(false, false) or 1
	if viewGroup > numGroups then
		viewGroup = GetActiveTalentGroup(false, false)
	end
	local active = GetActiveTalentGroup(false, false)
	local isPet = viewMode == "pet"

	for _, tree in ipairs(Window.trees) do
		SetShown(tree, viewMode == "talents")
	end
	SetShown(Window.petView, isPet)
	SetShown(Window.glyphView, viewMode == "glyphs")

	local preview, previewSpent, pointsLeft = false, 0, 0
	if viewMode == "glyphs" then
		Window.title:SetText(GLYPHS or "Glyphs")
		UpdateGlyphView()
	else
		local group = TreeGroup(isPet)
		preview = PreviewMode(isPet)
		previewSpent = preview and GetGroupPreviewTalentPointsSpent(isPet, group) or 0
		pointsLeft = (GetUnspentTalentPoints(false, isPet, group) or 0) - previewSpent
		if isPet then
			Window.title:SetText(PET or "Pet")
			UpdatePetView(pointsLeft)
		else
			Window.title:SetText(TALENTS or "Talents")
			for _, tree in ipairs(Window.trees) do
				UpdateTree(tree, pointsLeft)
			end
		end
	end

	SetShown(Window.pointsText, viewMode ~= "glyphs")
	Window.pointsText:SetFormattedText("%s: |cffffffff%d|r", TALENT_POINTS or "Talent Points", pointsLeft)
	UpdateSpecTabs(numGroups, active)

	local showPreview = preview and previewSpent > 0
	SetShown(Window.learn, showPreview)
	SetShown(Window.reset, showPreview)

	for mode, tab in pairs(Window.viewTabs) do
		tab.text:SetTextColor(unpack(mode == viewMode and COLOR_MAX or COLOR_WHITE))
	end
	SetShown(Window.viewTabs.pet, HasPetTalents())
end

local function CreateButton(parent, text, width)
	local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
	b:Size(width or 90, 22)
	b:SetText(text)
	S:HandleButton(b)
	b.text = b:GetFontString()
	return b
end

local function SetView(mode)
	viewMode = mode
	UpdateWindow()
end

local function CreateWindow()
	-- Deepest tier of all trees (11 in WotLK)
	local tiers = 1
	for t = 1, NUM_TREES do
		for i = 1, GetNumTalents(t, false, false) do
			local _, _, tier = GetTalentInfo(t, i, false, false, 1)
			tiers = math.max(tiers, tier or 1)
		end
	end
	local treeH = HEADER + (tiers - 1) * STEP_Y + BUTTON + TREE_BOTTOM

	Window = CreateFrame("Frame", "ForeverTalentFrame", UIParent)
	Window:Size(2 * MARGIN + CONTENT_W, TOP_BAR + treeH + FOOTER)
	Window:Point("CENTER", UIParent, "CENTER", 0, 40)
	Window:SetTemplate("Transparent")
	Window:SetFrameStrata("HIGH")
	Window:SetToplevel(true)
	Window:EnableMouse(true)
	Window:SetMovable(true)
	Window:SetClampedToScreen(true)
	Window:RegisterForDrag("LeftButton")
	Window:SetScript("OnDragStart", Window.StartMoving)
	Window:SetScript("OnDragStop", Window.StopMovingOrSizing)
	Window:Hide()
	tinsert(UISpecialFrames, "ForeverTalentFrame")

	Window.title = Window:CreateFontString(nil, "OVERLAY")
	Window.title:FontTemplate(nil, 14, "OUTLINE")
	Window.title:Point("TOP", Window, "TOP", 0, -10)

	local close = CreateFrame("Button", nil, Window, "UIPanelCloseButton")
	S:HandleCloseButton(close)
	close:Point("TOPRIGHT", Window, "TOPRIGHT", 2, 2)

	-- Dual spec: view either group, activate the viewed one
	Window.specTabs = {}
	-- Blizzard's names ("Erste Talentspezialisierung") do not fit a button: tooltip
	local specNames = {TALENT_SPEC_PRIMARY or "Primary Talents", TALENT_SPEC_SECONDARY or "Secondary Talents"}
	for g = 1, 2 do
		local tab = CreateButton(Window, "Spec " .. g, 136)
		tab:Point("TOPLEFT", Window, "TOPLEFT", MARGIN + (g - 1) * 140, -6)
		tab:HookScript("OnEnter", function(self)
			GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
			GameTooltip:AddLine(specNames[g])
			GameTooltip:Show()
		end)
		tab:HookScript("OnLeave", GameTooltip_Hide)
		tab.active = tab:CreateTexture(nil, "OVERLAY")
		tab.active:SetTexture("Interface\\Buttons\\UI-CheckBox-Check")
		tab.active:Size(16)
		tab.active:Point("RIGHT", tab, "RIGHT", -2, 0)
		tab:SetScript("OnClick", function()
			viewGroup = g
			UpdateWindow()
		end)
		Window.specTabs[g] = tab
	end
	Window.activate = CreateButton(Window, TALENT_SPEC_ACTIVATE or "Activate", 170)
	Window.activate:Point("TOPRIGHT", Window, "TOPRIGHT", -34, -6)
	Window.activate:SetScript("OnClick", function()
		SetActiveTalentGroup(viewGroup)
	end)

	Window.trees = {}
	for t = 1, NUM_TREES do
		Window.trees[t] = CreateTree(t, treeH, t, false)
	end
	Window.petView = CreatePetView(treeH)
	Window.glyphView = CreateGlyphView(treeH)

	Window.pointsText = Window:CreateFontString(nil, "OVERLAY")
	Window.pointsText:FontTemplate(nil, 13, "OUTLINE")
	Window.pointsText:Point("BOTTOMLEFT", Window, "BOTTOMLEFT", MARGIN + 4, 14)

	Window.reset = CreateButton(Window, RESET or "Reset")
	Window.reset:Point("BOTTOMRIGHT", Window, "BOTTOMRIGHT", -MARGIN, 9)
	Window.reset:SetScript("OnClick", function()
		local isPet = viewMode == "pet"
		ResetGroupPreviewTalentPoints(isPet, TreeGroup(isPet))
	end)
	Window.learn = CreateButton(Window, LEARN or "Learn")
	Window.learn:Point("RIGHT", Window.reset, "LEFT", -4, 0)
	Window.learn:SetScript("OnClick", function()
		LearnPreviewTalents(viewMode == "pet")
	end)

	-- Views: talents, pet talents, glyphs
	Window.viewTabs = {}
	local views = {
		{"talents", TALENTS or "Talents"},
		{"pet", PET or "Pet"},
		{"glyphs", GLYPHS or "Glyphs"},
	}
	for i, v in ipairs(views) do
		local tab = CreateButton(Window, v[2])
		tab:Point("BOTTOM", Window, "BOTTOM", (i - 2) * 96, 9)
		tab:SetScript("OnClick", function()
			SetView(v[1])
		end)
		Window.viewTabs[v[1]] = tab
	end

	for _, event in ipairs({"PLAYER_TALENT_UPDATE", "CHARACTER_POINTS_CHANGED", "PREVIEW_TALENT_POINTS_CHANGED",
		"PET_TALENT_UPDATE", "PREVIEW_PET_TALENT_POINTS_CHANGED", "ACTIVE_TALENT_GROUP_CHANGED", "PLAYER_LEVEL_UP",
		"UNIT_PET", "GLYPH_ADDED", "GLYPH_REMOVED", "GLYPH_UPDATED", "USE_GLYPH"}) do
		Window:RegisterEvent(event)
	end
	Window:SetScript("OnEvent", UpdateWindow)
	Window:SetScript("OnShow", function()
		PlaySound("igCharacterInfoOpen")
		UpdateWindow()
	end)
	Window:SetScript("OnHide", function()
		PlaySound("igCharacterInfoClose")
	end)
end

local function ShowWindow(mode)
	if not Window then
		CreateWindow()
	end
	viewMode = mode or "talents"
	if Window:IsShown() then
		UpdateWindow()
	else
		viewGroup = GetActiveTalentGroup(false, false)
		Window:Show()
	end
end

local function ToggleWindow()
	if Window and Window:IsShown() then
		Window:Hide()
	else
		ShowWindow("talents")
	end
end

--------------------------------
-- Redirect: Blizzard's talent frame opens our window instead. Glyph requests (using a
-- glyph, ToggleGlyphFrame) switch to the glyph view one frame later, after Blizzard
-- has shown its frame and selected the glyph tab.

local glyphOpener = CreateFrame("Frame")
glyphOpener:Hide()
glyphOpener:SetScript("OnUpdate", function(self)
	self:Hide()
	if PlayerTalentFrame and PlayerTalentFrame:IsShown() then
		HideUIPanel(PlayerTalentFrame)
	end
	ShowWindow("glyphs")
end)

local function OpenGlyphsSoon()
	if Enabled() then
		glyphOpener:Show()
	end
end

local function HookTalentFrame()
	if not PlayerTalentFrame or PlayerTalentFrame.foreverHooked then
		return
	end
	PlayerTalentFrame.foreverHooked = true
	PlayerTalentFrame:HookScript("OnShow", function(self)
		if not Enabled() then
			return
		end
		HideUIPanel(self)
		ToggleWindow()
	end)
	PlayerTalentFrame:HookScript("OnHide", function(self)
		-- Otherwise Blizzard's frame would come back on the glyph tab
		if PanelTemplates_GetSelectedTab(self) == (GLYPH_TALENT_TAB or 4) then
			PanelTemplates_SetTab(self, 1)
		end
	end)
end

local loader = CreateFrame("Frame")
loader:RegisterEvent("ADDON_LOADED")
loader:RegisterEvent("PLAYER_LOGIN")
loader:RegisterEvent("USE_GLYPH")
loader:SetScript("OnEvent", function(_, event, name)
	if event == "USE_GLYPH" then
		OpenGlyphsSoon()
	elseif event == "PLAYER_LOGIN" or name == "Blizzard_TalentUI" then
		if IsAddOnLoaded("Blizzard_TalentUI") then
			HookTalentFrame()
		end
		if event == "PLAYER_LOGIN" and ToggleGlyphFrame then
			hooksecurefunc("ToggleGlyphFrame", OpenGlyphsSoon)
		end
	end
end)

F.ToggleTalentWindow = ToggleWindow

-- /forevertex: which art textures the client actually loaded (GetTexture is nil when not)
SLASH_FOREVERTEX1 = "/forevertex"
SlashCmdList.FOREVERTEX = function()
	if not Window then
		print("Forever: Talentfenster noch nicht geoeffnet")
		return
	end
	for t, tree in ipairs(Window.trees) do
		for _, piece in ipairs(tree.art) do
			print(format("Baum %d %s: %s (%s)", t, piece.def[1], tostring(piece.tex:GetTexture()),
				piece.tex:IsShown() and "sichtbar" or "aus"))
		end
	end
	print("Glyphen: " .. tostring(Window.glyphView.art:GetTexture()))
end
