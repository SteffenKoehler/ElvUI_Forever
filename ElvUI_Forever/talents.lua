-- Talent window: all three trees side by side in ElvUI style (idea from DragonUI by
-- NeticSoul, MIT; own implementation, no retail art). Blizzard's talent frame stays
-- reachable for glyphs and pet talents.
local E, L, V, P, G = unpack(ElvUI)
local S = E:GetModule("Skins")
local F = E:GetModule("Forever")

local NUM_TREES, NUM_COLUMNS, POINTS_PER_TIER = 3, 4, 5
local BUTTON, STEP_X, STEP_Y = 32, 48, 44
local TREE_PAD, HEADER, TREE_BOTTOM = 14, 40, 12
local TREE_W = 2 * TREE_PAD + (NUM_COLUMNS - 1) * STEP_X + BUTTON
local TREE_GAP, MARGIN, TOP_BAR, FOOTER = 8, 10, 34, 40
local LINE = 2

local COLOR_MAX = {1, 0.82, 0}
local COLOR_OPEN = {0.25, 1, 0.25}
local COLOR_LINE_ON = {1, 0.82, 0}
local COLOR_LINE_OFF = {0.4, 0.4, 0.4}
local COLOR_WHITE = {1, 1, 1}

local Window
local viewGroup = 1
local bypass -- open Blizzard's frame without redirecting it

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

local function PreviewMode(group)
	return GetCVarBool("previewTalents") and group == GetActiveTalentGroup(false, false)
end

local function ButtonOffset(tier, column)
	return TREE_PAD + (column - 1) * STEP_X, -(HEADER + (tier - 1) * STEP_Y)
end

--------------------------------
-- Talent buttons

local function TalentOnEnter(self)
	GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
	GameTooltip:SetTalent(self.tab, self.index, false, false, viewGroup, PreviewMode(viewGroup))
	GameTooltip:Show()
end

local function TalentOnClick(self, button)
	local group = viewGroup
	if group ~= GetActiveTalentGroup(false, false) then
		return
	end
	if GetCVarBool("previewTalents") then
		AddPreviewTalentPoints(self.tab, self.index, button == "RightButton" and -1 or 1, false, group)
	elseif button == "LeftButton" then
		LearnTalent(self.tab, self.index, false, group)
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

-- Blizzard's tree art from the client: 4 pieces, 300 x 331 visible
local ART = {
	{"TopLeft", 0, 0, 256, 256, 1, 1},
	{"TopRight", 256, 0, 44, 256, 44 / 64, 1},
	{"BottomLeft", 0, 256, 256, 75, 1, 75 / 128},
	{"BottomRight", 256, 256, 44, 75, 44 / 64, 75 / 128},
}

local function CreateTree(index, height)
	local tree = CreateFrame("Frame", nil, Window)
	tree:Size(TREE_W, height)
	tree:Point("TOPLEFT", Window, "TOPLEFT", MARGIN + (index - 1) * (TREE_W + TREE_GAP), -TOP_BAR)
	tree:SetTemplate("Default")

	local artH = height - HEADER + 8
	local sx, sy = TREE_W / 300, artH / 331
	tree.art = {}
	for i, piece in ipairs(ART) do
		local tex = tree:CreateTexture(nil, "BACKGROUND", nil, 1)
		tex:Point("TOPLEFT", tree, "TOPLEFT", piece[2] * sx, -(HEADER - 8) - piece[3] * sy)
		tex:Size(piece[4] * sx, piece[5] * sy)
		tex:SetTexCoord(0, piece[6], 0, piece[7])
		tex:SetAlpha(0.45)
		tree.art[i] = {tex = tex, suffix = piece[1]}
	end

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
	tree.index = index
	return tree
end

local function UpdateTree(tree, group, preview, pointsLeft)
	local t = tree.index
	local name, icon, spent, background, previewSpent = GetTalentTabInfo(t, false, false, group)
	local treeSpent = spent + (preview and previewSpent or 0)
	local canSpend = pointsLeft > 0 and group == GetActiveTalentGroup(false, false)

	tree.icon:SetTexture(icon)
	tree.name:SetText(name)
	tree.points:SetText(treeSpent)
	for _, piece in ipairs(tree.art) do
		if background then
			piece.tex:SetTexture("Interface\\TalentFrame\\" .. background .. "-" .. piece.suffix)
			piece.tex:Show()
		else
			piece.tex:Hide()
		end
	end

	for _, line in ipairs(tree.lines) do
		line:Hide()
	end
	tree.numLines = 0

	local numTalents = GetNumTalents(t, false, false)
	for i = 1, numTalents do
		local b = tree.buttons[i] or CreateTalentButton(tree)
		tree.buttons[i] = b
		local _, tIcon, tier, column, rank, maxRank, _, meetsPrereq, previewRank, meetsPreviewPrereq = GetTalentInfo(t, i, false, false, group)
		if preview then
			rank, meetsPrereq = previewRank, meetsPreviewPrereq
		end
		local available = meetsPrereq and treeSpent >= (tier - 1) * POINTS_PER_TIER
		local lit = rank > 0 or (available and canSpend)

		b.tab, b.index = t, i
		b:ClearAllPoints()
		b:Point("TOPLEFT", tree, "TOPLEFT", ButtonOffset(tier, column))
		b.icon:SetTexture(tIcon)
		b.icon:SetDesaturated(not lit)
		b.icon:SetAlpha(lit and 1 or 0.6)

		local color
		if rank >= maxRank then
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

		local prereqs = {GetTalentPrereqs(t, i, false, false, group)}
		for k = 1, #prereqs, 3 do
			DrawPrereq(tree, prereqs[k], prereqs[k + 1], tier, column, meetsPrereq and COLOR_LINE_ON or COLOR_LINE_OFF)
		end
	end
	for i = numTalents + 1, #tree.buttons do
		tree.buttons[i]:Hide()
	end
end

--------------------------------
-- Window

local function UpdateWindow()
	if not (Window and Window:IsShown()) then
		return
	end
	local numGroups = GetNumTalentGroups(false, false) or 1
	if viewGroup > numGroups then
		viewGroup = GetActiveTalentGroup(false, false)
	end
	local active = GetActiveTalentGroup(false, false)
	local preview = PreviewMode(viewGroup)
	local unspent = GetUnspentTalentPoints(false, false, viewGroup)
	local previewSpent = preview and GetGroupPreviewTalentPointsSpent(false, viewGroup) or 0
	local pointsLeft = unspent - previewSpent

	for _, tree in ipairs(Window.trees) do
		UpdateTree(tree, viewGroup, preview, pointsLeft)
	end

	Window.pointsText:SetFormattedText("%s: |cffffffff%d|r", TALENT_POINTS or "Talent Points", pointsLeft)

	for g, tab in ipairs(Window.specTabs) do
		SetShown(tab, numGroups > 1)
		tab.text:SetTextColor(unpack(g == viewGroup and COLOR_MAX or COLOR_WHITE))
		SetShown(tab.active, g == active)
	end
	SetShown(Window.activate, numGroups > 1 and viewGroup ~= active)

	local showPreview = preview and previewSpent > 0
	SetShown(Window.learn, showPreview)
	SetShown(Window.reset, showPreview)
	SetShown(Window.pet, HasPetUI() and (GetNumTalentTabs(false, true) or 0) > 0)
end

local function OpenBlizzard(glyphs)
	bypass = true
	Window:Hide()
	if glyphs and ToggleGlyphFrame then
		ToggleGlyphFrame()
	else
		TalentFrame_LoadUI()
		ShowUIPanel(PlayerTalentFrame)
		if glyphs and PlayerTalentFrameTab4 then
			PlayerTalentFrameTab4:Click()
		end
	end
end

local function CreateButton(parent, text, width)
	local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
	b:Size(width or 90, 22)
	b:SetText(text)
	S:HandleButton(b)
	return b
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
	Window:Size(2 * MARGIN + NUM_TREES * TREE_W + (NUM_TREES - 1) * TREE_GAP, TOP_BAR + treeH + FOOTER)
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
	Window.title:SetText(TALENTS or "Talents")

	local close = CreateFrame("Button", nil, Window, "UIPanelCloseButton")
	S:HandleCloseButton(close)
	close:Point("TOPRIGHT", Window, "TOPRIGHT", 2, 2)

	-- Dual spec: view either group, activate the viewed one
	Window.specTabs = {}
	local specNames = {TALENT_SPEC_PRIMARY or "Primary", TALENT_SPEC_SECONDARY or "Secondary"}
	for g = 1, 2 do
		local tab = CreateButton(Window, specNames[g], 120)
		tab:Point("TOPLEFT", Window, "TOPLEFT", MARGIN + (g - 1) * 124, -6)
		tab.text = tab:GetFontString()
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
	Window.activate = CreateButton(Window, TALENT_SPEC_ACTIVATE or "Activate", 110)
	Window.activate:Point("LEFT", Window.specTabs[2], "RIGHT", 6, 0)
	Window.activate:SetScript("OnClick", function()
		SetActiveTalentGroup(viewGroup)
	end)

	Window.trees = {}
	for t = 1, NUM_TREES do
		Window.trees[t] = CreateTree(t, treeH)
	end

	Window.pointsText = Window:CreateFontString(nil, "OVERLAY")
	Window.pointsText:FontTemplate(nil, 13, "OUTLINE")
	Window.pointsText:Point("BOTTOMLEFT", Window, "BOTTOMLEFT", MARGIN + 4, 14)

	Window.reset = CreateButton(Window, RESET or "Reset")
	Window.reset:Point("BOTTOMRIGHT", Window, "BOTTOMRIGHT", -MARGIN, 9)
	Window.reset:SetScript("OnClick", function()
		ResetGroupPreviewTalentPoints(false, viewGroup)
	end)
	Window.learn = CreateButton(Window, LEARN or "Learn")
	Window.learn:Point("RIGHT", Window.reset, "LEFT", -4, 0)
	Window.learn:SetScript("OnClick", function()
		LearnPreviewTalents(false)
	end)

	Window.glyphs = CreateButton(Window, GLYPHS or "Glyphs")
	Window.glyphs:Point("BOTTOM", Window, "BOTTOM", -48, 9)
	Window.glyphs:SetScript("OnClick", function()
		OpenBlizzard(true)
	end)
	Window.pet = CreateButton(Window, PET or "Pet")
	Window.pet:Point("LEFT", Window.glyphs, "RIGHT", 6, 0)
	Window.pet:SetScript("OnClick", function()
		OpenBlizzard(false)
	end)

	for _, event in ipairs({"PLAYER_TALENT_UPDATE", "CHARACTER_POINTS_CHANGED", "PREVIEW_TALENT_POINTS_CHANGED",
		"ACTIVE_TALENT_GROUP_CHANGED", "PLAYER_LEVEL_UP", "UNIT_PET"}) do
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

local function ToggleWindow()
	if not Window then
		CreateWindow()
	end
	if Window:IsShown() then
		Window:Hide()
	else
		viewGroup = GetActiveTalentGroup(false, false)
		Window:Show()
	end
end

--------------------------------
-- Redirect: Blizzard's talent frame opens our window instead, except for glyphs, pet
-- talents and when opened from our window

local function HookTalentFrame()
	if not PlayerTalentFrame or PlayerTalentFrame.foreverHooked then
		return
	end
	PlayerTalentFrame.foreverHooked = true
	PlayerTalentFrame:HookScript("OnShow", function(self)
		if bypass or not Enabled() or self.pet then
			return
		end
		if PanelTemplates_GetSelectedTab(self) == (GLYPH_TALENT_TAB or 4) then
			return
		end
		HideUIPanel(self)
		ToggleWindow()
	end)
	PlayerTalentFrame:HookScript("OnHide", function(self)
		bypass = nil
		-- Otherwise the talent key would reopen the glyph tab next time
		if PanelTemplates_GetSelectedTab(self) == (GLYPH_TALENT_TAB or 4) then
			PanelTemplates_SetTab(self, 1)
		end
	end)
end

local loader = CreateFrame("Frame")
loader:RegisterEvent("ADDON_LOADED")
loader:RegisterEvent("PLAYER_LOGIN")
loader:SetScript("OnEvent", function(_, event, name)
	if event == "PLAYER_LOGIN" or name == "Blizzard_TalentUI" then
		if IsAddOnLoaded("Blizzard_TalentUI") then
			HookTalentFrame()
		end
	end
end)

F.ToggleTalentWindow = ToggleWindow
