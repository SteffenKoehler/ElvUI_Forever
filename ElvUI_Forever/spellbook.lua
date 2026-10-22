-- Spellbook: one ElvUI window like the talent window. All spells of a tab on one page,
-- unlearned spells greyed in between (learned from the class trainer of this server),
-- Clique docked on the right. Blizzard's spellbook is redirected to it.
-- Casting: the window itself is not protected (opens, switches tabs and drags in combat
-- too); out of combat an invisible secure button lies over the spell under the cursor.
local E, L, V, P, G = unpack(ElvUI)
local S = E:GetModule("Skins")
local F = E:GetModule("Forever")

local W, H = 648, 598 -- same size as the talent window
local MARGIN, TOP_BAR, FOOTER, TAB_H = 10, 34, 40, 24
local COLS, ROW_H, ICON = 3, 44, 34
local CONTENT_TOP = TOP_BAR + TAB_H + 8

local COLOR_GOLD = {1, 0.82, 0}
local COLOR_WHITE = {1, 1, 1}
local COLOR_SUB = {0.67, 0.67, 0.67}
local COLOR_DIM = {0.43, 0.43, 0.43}
local COLOR_LEVEL = {0.9, 0.31, 0.27}
local COLOR_NOW = {0.25, 1, 0.25}
local COLOR_REQ = {0.47, 0.63, 0.86}
local COLOR_CLIQUE = {0.27, 0.86, 0.27}

local PET_TAB = 99

local Window
local currentTab = 2
local page = 1
local showUnlearned = true
local searchText

local function Enabled()
	local db = E.db.Forever
	return db and db.enable and db.spellbook
end

local function SetShown(region, show)
	if show then
		region:Show()
	else
		region:Hide()
	end
end

local function RankNumber(rank)
	return tonumber(rank and rank:match("(%d+)")) or 0
end

local function MoneyText(copper)
	if not copper or copper <= 0 then
		return nil
	end
	local g, s, c = floor(copper / 10000), floor(copper / 100) % 100, copper % 100
	local parts = {}
	if g > 0 then tinsert(parts, g .. "g") end
	if s > 0 then tinsert(parts, s .. "s") end
	if c > 0 and g == 0 then tinsert(parts, c .. "c") end
	return table.concat(parts, " ")
end

--------------------------------
-- Trainer data: the class trainer lists every spell of the class, also those for later
-- levels. Stored account-wide per class whenever a class trainer is open.

local function DB()
	ElvUI_ForeverDB = ElvUI_ForeverDB or {}
	ElvUI_ForeverDB.trainer = ElvUI_ForeverDB.trainer or {}
	return ElvUI_ForeverDB.trainer
end

local TRAINER_FILTERS = {"available", "unavailable", "used"}
local scanning

local function ScanTrainer()
	if scanning or IsTradeskillTrainer() then
		return
	end
	-- Only tabs of this class's spellbook count (skips weapon masters, pet trainers)
	local tabNames, spellNames = {}, {}
	for t = 1, GetNumSpellTabs() do
		local name, _, offset, num = GetSpellTabInfo(t)
		if name then
			tabNames[name] = true
		end
		for i = offset + 1, offset + num do
			local spell = GetSpellName(i, BOOKTYPE_SPELL)
			if spell then
				spellNames[spell] = true
			end
		end
	end

	scanning = true
	local saved = {}
	for _, filter in ipairs(TRAINER_FILTERS) do
		saved[filter] = GetTrainerServiceTypeFilter(filter)
		SetTrainerServiceTypeFilter(filter, 1)
	end
	ExpandTrainerSkillLine(0)

	local entries = {}
	local header
	for i = 1, GetNumTrainerServices() do
		local name, rank, category = GetTrainerServiceInfo(i)
		-- The list is grouped under headers named like the spellbook tabs
		local line = header
		if category == "header" then
			header = name
		elseif GetTrainerServiceSkillLine then
			line = GetTrainerServiceSkillLine(i) or header
		end
		if name and category ~= "header" then
			local reqs
			for r = 1, (GetTrainerServiceNumAbilityReq(i) or 0) do
				local ability, has = GetTrainerServiceAbilityReq(i, r)
				if ability then
					reqs = reqs or {}
					tinsert(reqs, ability)
				end
			end
			tinsert(entries, {
				name = name,
				rank = rank ~= "" and rank or nil,
				level = GetTrainerServiceLevelReq(i) or 0,
				cost = (GetTrainerServiceCost(i)) or 0,
				icon = GetTrainerServiceIcon(i),
				line = line or "?",
				desc = GetTrainerServiceDescription(i),
				reqs = reqs,
			})
		end
	end

	for _, filter in ipairs(TRAINER_FILTERS) do
		SetTrainerServiceTypeFilter(filter, saved[filter] and 1 or 0)
	end
	scanning = nil

	-- A class trainer: its groups are this book's tabs, or it teaches spells of this book
	-- (weapon masters and pet trainers match neither)
	local classTrainer
	for _, e in ipairs(entries) do
		if tabNames[e.line] or spellNames[e.name] then
			classTrainer = true
			break
		end
	end
	if classTrainer then
		local _, class = UnitClass("player")
		DB()[class] = {time = time(), entries = entries}
		if Window and Window:IsShown() then
			Window:Refresh()
		end
	end
end

--------------------------------
-- Spell lists

-- Highest known rank per spell name (all player tabs); the book shows one rank per spell
local function KnownRanks()
	local known, knownTab = {}, {}
	for t = 1, GetNumSpellTabs() do
		local _, _, offset, num = GetSpellTabInfo(t)
		for i = offset + 1, offset + num do
			local name, rank = GetSpellName(i, BOOKTYPE_SPELL)
			if name then
				local r = RankNumber(rank)
				if r >= (known[name] or 0) then
					known[name] = r
				end
				knownTab[name] = t
			end
		end
	end
	return known, knownTab
end

local function TabExists(name)
	for t = 1, GetNumSpellTabs() do
		if GetSpellTabInfo(t) == name then
			return true
		end
	end
	return false
end

local function Matches(name)
	return not searchText or (name and strlower(name):find(searchText, 1, true))
end

-- Entries of one tab: learned spells in book order, then the next unlearned rank of each
-- spell from the trainer data, sorted by level
local function BuildEntries(tab)
	local list = {}
	if tab == PET_TAB then
		local num = HasPetSpells() or 0
		for i = 1, num do
			local name, rank = GetSpellName(i, BOOKTYPE_PET)
			if name and Matches(name) then
				tinsert(list, {index = i, book = BOOKTYPE_PET, name = name, rank = rank,
					icon = GetSpellTexture(i, BOOKTYPE_PET), learned = true})
			end
		end
		return list
	end

	local tabName, _, offset, num = GetSpellTabInfo(tab)
	-- The book holds every rank; like Blizzard's book only the highest one unless
	-- "Alle Zauberraenge anzeigen" is on (the ranks of a spell follow each other)
	local allRanks = GetCVarBool("ShowAllSpellRanks")
	for i = offset + 1, offset + num do
		local name, rank = GetSpellName(i, BOOKTYPE_SPELL)
		if name and Matches(name) and (allRanks or GetSpellName(i + 1, BOOKTYPE_SPELL) ~= name or i == offset + num) then
			tinsert(list, {index = i, book = BOOKTYPE_SPELL, name = name, rank = rank,
				icon = GetSpellTexture(i, BOOKTYPE_SPELL), learned = true})
		end
	end

	if not showUnlearned then
		return list
	end
	local _, class = UnitClass("player")
	local data = DB()[class]
	if not data then
		return list
	end
	local known, knownTab = KnownRanks()
	local nextRank = {}
	for _, e in ipairs(data.entries) do
		-- Trainer group = tab name; otherwise the tab where a lower rank already is
		local inTab = e.line == tabName or (knownTab[e.name] == tab and not TabExists(e.line))
		if inTab and Matches(e.name) then
			local r = RankNumber(e.rank)
			local unknown
			if known[e.name] then
				unknown = r > known[e.name]
			else
				unknown = true
			end
			if unknown then
				local best = nextRank[e.name]
				if not best or RankNumber(best.rank) > r then
					nextRank[e.name] = e
				end
			end
		end
	end
	local unlearned = {}
	for _, e in pairs(nextRank) do
		tinsert(unlearned, e)
	end
	sort(unlearned, function(a, b)
		if a.level ~= b.level then
			return a.level < b.level
		end
		return a.name < b.name
	end)
	for _, e in ipairs(unlearned) do
		tinsert(list, {name = e.name, rank = e.rank, icon = e.icon, learned = false, data = e})
	end
	return list
end

-- Second line of an unlearned entry
local function UnlearnedInfo(e)
	local level = UnitLevel("player")
	local cost = MoneyText(e.cost)
	if e.level > level then
		return format("Ab Stufe %d%s", e.level, cost and (" · " .. cost) or ""), COLOR_LEVEL
	end
	if e.reqs then
		local known = KnownRanks()
		for _, req in ipairs(e.reqs) do
			-- "Sternenfeuer (Rang 1)": the previous rank, met when that rank is known
			local name, rank = req:match("^(.-)%s*%((.-)%)$")
			name = name or req
			if not known[name] or known[name] < RankNumber(rank) then
				return "Benötigt: " .. req, COLOR_REQ
			end
		end
	end
	return "Beim Lehrer lernbar" .. (cost and (" · " .. cost) or ""), COLOR_NOW
end

--------------------------------
-- Clique: binding by clicking a spell while Clique's window is open

local function CliqueOpen()
	return CliqueFrame and CliqueFrame:IsVisible()
end

local function CliqueBind(entry, button)
	local CL = Clique.Locals
	local rank = entry.rank
	if rank == CL.RACIAL_PASSIVE or rank == CL.PASSIVE then
		StaticPopup_Show("CLIQUE_PASSIVE_SKILL")
		return
	end
	if Clique.editSet == Clique.clicksets[CL.CLICKSET_HARMFUL] then
		button = format("%s%d", "harmbutton", Clique:GetButtonNumber(button))
	elseif Clique.editSet == Clique.clicksets[CL.CLICKSET_HELPFUL] then
		button = format("%s%d", "helpbutton", Clique:GetButtonNumber(button))
	else
		button = Clique:GetButtonNumber(button)
	end
	if not GetCVarBool("ShowAllSpellRanks") then
		rank = nil
	end
	local t = {
		button = button,
		modifier = Clique:GetModifierText(),
		texture = entry.icon,
		type = "spell",
		arg1 = entry.name,
		arg2 = rank,
	}
	local key = t.modifier .. t.button
	if Clique:CheckBinding(key) then
		StaticPopup_Show("CLIQUE_BINDING_PROBLEM")
		return
	end
	Clique.editSet[key] = t
	Clique:ListScrollUpdate()
	Clique:UpdateClicks()
	Clique:PLAYER_REGEN_ENABLED()
end

local function DockClique()
	if not CliqueFrame then
		return
	end
	CliqueFrame:SetParent(Window)
	CliqueFrame:ClearAllPoints()
	-- Right of the book, or left when the screen edge would push it over the book
	local scale = CliqueFrame:GetEffectiveScale() / UIParent:GetEffectiveScale()
	local width = CliqueFrame:GetWidth() * scale
	if (Window:GetRight() or 0) + 4 + width <= UIParent:GetRight() then
		CliqueFrame:SetPoint("TOPLEFT", Window, "TOPRIGHT", 4 / scale, 0)
	else
		CliqueFrame:SetPoint("TOPRIGHT", Window, "TOPLEFT", -4 / scale, 0)
	end
	CliqueFrame:SetFrameLevel(Window:GetFrameLevel() + 5)
	if not CliqueFrame.foreverHooked then
		CliqueFrame.foreverHooked = true
		-- Closed with its own button: bind mode and tab color follow
		CliqueFrame:HookScript("OnShow", function()
			DockClique()
			Window:Refresh()
		end)
		CliqueFrame:HookScript("OnHide", function() Window:Refresh() end)
	end
end

local function ToggleClique()
	if not Clique then
		return
	end
	if InCombatLockdown() then
		UIErrorsFrame:AddMessage("Clique kann im Kampf nicht geöffnet werden.", 1, 0.1, 0.1)
		return
	end
	Clique:Toggle()
	DockClique()
	Window:Refresh()
end

--------------------------------
-- Secure cast overlay

local Overlay

local function OverlayOnEnter(self)
	local entry = self.entry
	if not entry then
		return
	end
	GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
	GameTooltip:SetSpell(entry.index, entry.book)
	GameTooltip:Show()
end

-- Off the window: a protected frame anchored to the window would make moving or hiding
-- the window protected in combat
local function ParkOverlay()
	if Overlay and not InCombatLockdown() then
		Overlay:Hide()
		Overlay:ClearAllPoints()
		Overlay:SetPoint("CENTER", UIParent, "CENTER")
		Overlay.entry = nil
	end
end

local function CreateOverlay()
	Overlay = CreateFrame("Button", "ForeverSpellbookCast", UIParent, "SecureActionButtonTemplate")
	Overlay:SetFrameStrata("DIALOG")
	Overlay:RegisterForClicks("AnyUp")
	Overlay:RegisterForDrag("LeftButton")
	Overlay:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
	Overlay:SetScript("OnEnter", OverlayOnEnter)
	Overlay:SetScript("OnLeave", function()
		GameTooltip:Hide()
		ParkOverlay()
	end)
	-- Shift-click links the spell instead of casting it
	Overlay:SetAttribute("shift-type1", "none")
	Overlay:HookScript("PreClick", function(self)
		if self.entry and IsModifiedClick("CHATLINK") and ChatEdit_GetActiveWindow() then
			local link = GetSpellLink(self.entry.index, self.entry.book)
			if link then
				ChatEdit_InsertLink(link)
			end
		end
	end)
	Overlay:SetScript("OnDragStart", function(self)
		if self.entry then
			PickupSpell(self.entry.index, self.entry.book)
		end
	end)
	Overlay:Hide()
end

local function PlaceOverlay(button)
	if InCombatLockdown() or CliqueOpen() then
		return
	end
	local entry = button.entry
	Overlay.entry = entry
	Overlay:ClearAllPoints()
	Overlay:SetAllPoints(button)
	Overlay:SetAttribute("type1", "spell")
	Overlay:SetAttribute("spell1", entry.name)
	if entry.book == BOOKTYPE_PET then
		Overlay:SetAttribute("type2", "macro")
		Overlay:SetAttribute("macrotext2", "/petautocasttoggle " .. entry.name)
	else
		Overlay:SetAttribute("type2", "spell")
		Overlay:SetAttribute("spell2", entry.name)
	end
	Overlay:Show()
	OverlayOnEnter(Overlay)
end

--------------------------------
-- Entry buttons

local function EntryOnEnter(self)
	local entry = self.entry
	if not entry then
		return
	end
	if entry.learned then
		if not CliqueOpen() and not InCombatLockdown() then
			PlaceOverlay(self)
			return
		end
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:SetSpell(entry.index, entry.book)
	else
		local e = entry.data
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:AddDoubleLine(e.name, e.rank or "", 1, 1, 1, 0.5, 0.5, 0.5)
		if e.desc and e.desc ~= "" then
			GameTooltip:AddLine(e.desc, 1, 0.82, 0, true)
		end
		local info, color = UnlearnedInfo(e)
		GameTooltip:AddLine(info, color[1], color[2], color[3])
	end
	GameTooltip:Show()
end

local function EntryOnClick(self, button)
	local entry = self.entry
	if not entry or not entry.learned then
		return
	end
	if IsModifiedClick("CHATLINK") and ChatEdit_GetActiveWindow() then
		local link = GetSpellLink(entry.index, entry.book)
		if link then
			ChatEdit_InsertLink(link)
		end
		return
	end
	if CliqueOpen() then
		CliqueBind(entry, button)
	end
end

local function CreateEntry(parent)
	local b = CreateFrame("Button", nil, parent)
	b:SetSize((W - 2 * MARGIN - 24) / COLS, ROW_H - 4)
	b:RegisterForClicks("AnyUp")
	b:RegisterForDrag("LeftButton")

	b.iconFrame = CreateFrame("Frame", nil, b)
	b.iconFrame:SetSize(ICON, ICON)
	b.iconFrame:SetPoint("LEFT", b, "LEFT", 0, 0)
	b.iconFrame:SetTemplate("Default")
	b.icon = b.iconFrame:CreateTexture(nil, "ARTWORK")
	b.icon:SetInside()
	b.icon:SetTexCoord(unpack(E.TexCoords))

	b.name = b:CreateFontString(nil, "OVERLAY")
	b.name:FontTemplate(nil, 13, "OUTLINE")
	b.name:SetPoint("TOPLEFT", b.iconFrame, "TOPRIGHT", 8, -1)
	b.name:SetPoint("RIGHT", b, "RIGHT", -4, 0)
	b.name:SetJustifyH("LEFT")

	b.sub = b:CreateFontString(nil, "OVERLAY")
	b.sub:FontTemplate(nil, 11, "OUTLINE")
	b.sub:SetPoint("TOPLEFT", b.name, "BOTTOMLEFT", 0, -3)
	b.sub:SetPoint("RIGHT", b, "RIGHT", -4, 0)
	b.sub:SetJustifyH("LEFT")

	b:SetScript("OnEnter", EntryOnEnter)
	b:SetScript("OnLeave", GameTooltip_Hide)
	b:SetScript("OnClick", EntryOnClick)
	b:SetScript("OnDragStart", function(self)
		if self.entry and self.entry.learned then
			PickupSpell(self.entry.index, self.entry.book)
		end
	end)
	return b
end

local function UpdateEntry(b, entry, clique)
	b.entry = entry
	b.icon:SetTexture(entry.icon)
	b.name:SetText(entry.name)
	if entry.learned then
		b.icon:SetDesaturated(false)
		b.icon:SetVertexColor(1, 1, 1)
		b.name:SetTextColor(unpack(COLOR_GOLD))
		b.sub:SetText(entry.rank or "")
		b.sub:SetTextColor(unpack(COLOR_SUB))
		b.iconFrame:SetBackdropBorderColor(unpack(clique and COLOR_CLIQUE or E.media.bordercolor))
	else
		b.icon:SetDesaturated(true)
		b.icon:SetVertexColor(0.6, 0.6, 0.6)
		b.name:SetTextColor(unpack(COLOR_DIM))
		local info, color = UnlearnedInfo(entry.data)
		b.sub:SetText((entry.rank and (entry.rank .. " · ") or "") .. info)
		b.sub:SetTextColor(unpack(color))
		b.iconFrame:SetBackdropBorderColor(0.2, 0.2, 0.2)
	end
	b:Show()
end

--------------------------------
-- Background: the tab's talent tree art, cover-cropped over the content, dimmed

-- suffix, x, y, width, height of the piece in the 300 x 331 picture, texture width, height
local ART = {
	{"TopLeft", 0, 0, 256, 256, 256, 256},
	{"TopRight", 256, 0, 44, 256, 64, 256},
	{"BottomLeft", 0, 256, 256, 75, 256, 128},
	{"BottomRight", 256, 256, 44, 75, 64, 128},
}

local function PlaceArt(frame, pieces)
	local w, h = frame:GetWidth(), frame:GetHeight()
	local s = math.max(w / 300, h / 331)
	local cw, ch = w / s, h / s
	local x0, y0 = (300 - cw) / 2, 0
	for i, p in ipairs(ART) do
		local tex = pieces[i]
		local ix0, ix1 = math.max(p[2], x0), math.min(p[2] + p[4], x0 + cw)
		local iy0, iy1 = math.max(p[3], y0), math.min(p[3] + p[5], y0 + ch)
		tex:ClearAllPoints()
		if ix1 > ix0 and iy1 > iy0 then
			tex:SetPoint("TOPLEFT", frame, "TOPLEFT", (ix0 - x0) * s, -(iy0 - y0) * s)
			tex:SetSize((ix1 - ix0) * s, (iy1 - iy0) * s)
			tex:SetTexCoord((ix0 - p[2]) / p[6], (ix1 - p[2]) / p[6], (iy0 - p[3]) / p[7], (iy1 - p[3]) / p[7])
			tex.used = true
		else
			tex.used = false
		end
	end
end

local function SetArt(background)
	for i, tex in ipairs(Window.art) do
		if background and tex.used then
			tex:SetTexture("Interface\\TalentFrame\\" .. background .. "-" .. ART[i][1])
			tex:Show()
		else
			tex:Hide()
		end
	end
end

local function TabBackground(tab)
	if tab == PET_TAB then
		local _, _, _, background = GetTalentTabInfo(1, false, true)
		return background
	end
	-- Spell tabs 2-4 are the talent trees 1-3; the general tab uses the first tree
	local tree = tab >= 2 and tab - 1 or 1
	if tree > (GetNumTalentTabs(false, false) or 0) then
		return nil
	end
	local _, _, _, background = GetTalentTabInfo(tree, false, false)
	return background
end

--------------------------------
-- Window

local function CreateButton(parent, text, width)
	local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
	b:SetSize(width or 90, TAB_H)
	b:SetText(text)
	S:HandleButton(b)
	b.text = b:GetFontString()
	return b
end

local function UpdateTabs()
	local x = MARGIN
	local numTabs = GetNumSpellTabs()
	for t, tab in ipairs(Window.tabs) do
		local name, icon = GetSpellTabInfo(t)
		if t <= numTabs and name then
			tab:SetText(format("|T%s:16:16:0:0:64:64:5:59:5:59|t %s", icon, name))
			tab:SetWidth(tab.text:GetStringWidth() + 20)
			tab:ClearAllPoints()
			tab:SetPoint("TOPLEFT", Window, "TOPLEFT", x, -TOP_BAR)
			x = x + tab:GetWidth() + 4
			tab.text:SetTextColor(unpack(t == currentTab and COLOR_GOLD or COLOR_WHITE))
			tab:Show()
		else
			tab:Hide()
		end
	end
	local pet = Window.petTab
	if (HasPetSpells() or 0) > 0 then
		pet:ClearAllPoints()
		pet:SetPoint("TOPLEFT", Window, "TOPLEFT", x, -TOP_BAR)
		pet.text:SetTextColor(unpack(currentTab == PET_TAB and COLOR_GOLD or COLOR_WHITE))
		pet:Show()
	else
		pet:Hide()
		if currentTab == PET_TAB then
			currentTab = 2
		end
	end
	SetShown(Window.clique, Clique ~= nil)
	if Clique then
		Window.clique.text:SetTextColor(unpack(CliqueOpen() and COLOR_CLIQUE or COLOR_WHITE))
	end
end

local function Refresh()
	if not (Window and Window:IsShown()) then
		return
	end
	if currentTab ~= PET_TAB and currentTab > GetNumSpellTabs() then
		currentTab = 1
	end
	UpdateTabs()
	SetArt(TabBackground(currentTab))

	local list = BuildEntries(currentTab)
	local perPage = Window.rows * COLS
	local pages = math.max(1, ceil(#list / perPage))
	if page > pages then
		page = pages
	end
	local clique = CliqueOpen()
	local first = (page - 1) * perPage
	for slot, b in ipairs(Window.entries) do
		local entry = list[first + slot]
		if entry then
			UpdateEntry(b, entry, clique)
		else
			b:Hide()
		end
	end

	SetShown(Window.cliqueHint, clique)
	SetShown(Window.pager, pages > 1)
	Window.pager.text:SetFormattedText("%d / %d", page, pages)

	local _, class = UnitClass("player")
	SetShown(Window.noData, showUnlearned and currentTab ~= PET_TAB and not DB()[class])
	Window.unlearnedCheck:SetChecked(showUnlearned)
	Window.ranksCheck:SetChecked(GetCVarBool("ShowAllSpellRanks"))
	ParkOverlay()
end

local function SelectTab(tab)
	currentTab = tab
	page = 1
	Refresh()
end

local function CreateWindow()
	Window = CreateFrame("Frame", "ForeverSpellbookFrame", UIParent)
	Window:SetSize(W, H)
	Window:SetPoint("CENTER", UIParent, "CENTER", 0, 40)
	Window:SetTemplate("Transparent")
	Window:SetFrameStrata("HIGH")
	Window:SetToplevel(true)
	Window:EnableMouse(true)
	Window:EnableMouseWheel(true)
	Window:SetMovable(true)
	Window:SetClampedToScreen(true)
	Window:RegisterForDrag("LeftButton")
	Window:SetScript("OnDragStart", Window.StartMoving)
	Window:SetScript("OnDragStop", Window.StopMovingOrSizing)
	Window:Hide()
	tinsert(UISpecialFrames, "ForeverSpellbookFrame")
	Window.Refresh = Refresh

	Window.title = Window:CreateFontString(nil, "OVERLAY")
	Window.title:FontTemplate(nil, 14, "OUTLINE")
	Window.title:SetPoint("TOP", Window, "TOP", 0, -10)
	Window.title:SetText(SPELLBOOK or "Spellbook")

	local close = CreateFrame("Button", nil, Window, "UIPanelCloseButton")
	S:HandleCloseButton(close)
	close:SetPoint("TOPRIGHT", Window, "TOPRIGHT", 2, 2)

	-- Content area with the tree art
	local content = CreateFrame("Frame", nil, Window)
	content:SetSize(W - 2 * MARGIN, H - CONTENT_TOP - FOOTER)
	content:SetPoint("TOPLEFT", Window, "TOPLEFT", MARGIN, -CONTENT_TOP)
	content:SetTemplate("Default")
	Window.content = content
	Window.art = {}
	for i = 1, #ART do
		local tex = content:CreateTexture(nil, "BORDER") -- above the ElvUI backdrop
		tex:SetVertexColor(0.4, 0.4, 0.4)
		tex:SetAlpha(0.85)
		Window.art[i] = tex
	end
	PlaceArt(content, Window.art)

	-- Tabs: spell tabs of the book, pet, Clique
	Window.tabs = {}
	for t = 1, 8 do
		local tab = CreateButton(Window, "", 100)
		tab:SetScript("OnClick", function()
			SelectTab(t)
		end)
		Window.tabs[t] = tab
	end
	Window.petTab = CreateButton(Window, PET or "Pet", 90)
	Window.petTab:SetScript("OnClick", function()
		SelectTab(PET_TAB)
	end)
	Window.clique = CreateButton(Window, "|TInterface\\AddOns\\Clique\\images\\CliqueIcon:16:16|t Clique", 92)
	Window.clique:SetPoint("TOPRIGHT", Window, "TOPRIGHT", -MARGIN, -TOP_BAR)
	Window.clique:SetScript("OnClick", ToggleClique)

	-- Entries
	Window.rows = floor((content:GetHeight() - 12) / ROW_H)
	Window.entries = {}
	local colW = (W - 2 * MARGIN - 24) / COLS
	for slot = 1, Window.rows * COLS do
		local b = CreateEntry(content)
		local col, row = (slot - 1) % COLS, floor((slot - 1) / COLS)
		b:SetPoint("TOPLEFT", content, "TOPLEFT", 12 + col * colW, -(10 + row * ROW_H))
		b:SetFrameLevel(content:GetFrameLevel() + 2)
		Window.entries[slot] = b
	end

	Window.cliqueHint = CreateFrame("Frame", nil, content)
	Window.cliqueHint:SetHeight(22)
	Window.cliqueHint:SetPoint("BOTTOMLEFT", content, "BOTTOMLEFT", 6, 6)
	Window.cliqueHint:SetPoint("BOTTOMRIGHT", content, "BOTTOMRIGHT", -6, 6)
	Window.cliqueHint:SetTemplate("Default")
	Window.cliqueHint:SetBackdropBorderColor(unpack(COLOR_CLIQUE))
	Window.cliqueHint:SetFrameLevel(content:GetFrameLevel() + 4)
	local hint = Window.cliqueHint:CreateFontString(nil, "OVERLAY")
	hint:FontTemplate(nil, 12, "OUTLINE")
	hint:SetPoint("CENTER")
	hint:SetTextColor(unpack(COLOR_CLIQUE))
	hint:SetText("Clique: Zauber mit der gewünschten Maustaste (+ Shift/Strg/Alt) anklicken, um ihn zu binden")

	Window.noData = content:CreateFontString(nil, "OVERLAY")
	Window.noData:FontTemplate(nil, 12, "OUTLINE")
	Window.noData:SetPoint("BOTTOM", content, "BOTTOM", 0, 34)
	Window.noData:SetTextColor(unpack(COLOR_SUB))
	Window.noData:SetText("Klassenlehrer einmal ansprechen, um auch die noch nicht gelernten Zauber zu sehen.")

	-- Footer: search, pages, unlearned toggle
	local search = CreateFrame("EditBox", "ForeverSpellbookSearch", Window, "InputBoxTemplate")
	search:SetSize(150, 20)
	search:SetPoint("BOTTOMLEFT", Window, "BOTTOMLEFT", MARGIN + 6, 10)
	search:SetAutoFocus(false)
	S:HandleEditBox(search)
	search.placeholder = search:CreateFontString(nil, "OVERLAY")
	search.placeholder:FontTemplate(nil, 12)
	search.placeholder:SetPoint("LEFT", search, "LEFT", 4, 0)
	search.placeholder:SetTextColor(unpack(COLOR_DIM))
	search.placeholder:SetText(SEARCH or "Suchen")
	search:SetScript("OnTextChanged", function(self)
		local text = self:GetText()
		searchText = text ~= "" and strlower(text) or nil
		SetShown(self.placeholder, not searchText)
		page = 1
		Refresh()
	end)
	search:SetScript("OnEscapePressed", function(self)
		self:SetText("")
		self:ClearFocus()
	end)
	search:SetScript("OnEnterPressed", search.ClearFocus)

	local check = CreateFrame("CheckButton", nil, Window, "UICheckButtonTemplate")
	check:SetSize(22, 22)
	check:SetPoint("BOTTOMRIGHT", Window, "BOTTOMRIGHT", -150, 9)
	S:HandleCheckBox(check)
	check.label = check:CreateFontString(nil, "OVERLAY")
	check.label:FontTemplate(nil, 12, "OUTLINE")
	check.label:SetPoint("LEFT", check, "RIGHT", 4, 0)
	check.label:SetText("Ungelernte anzeigen")
	check:SetScript("OnClick", function(self)
		showUnlearned = self:GetChecked() and true or false
		Refresh()
	end)
	Window.unlearnedCheck = check

	local ranks = CreateFrame("CheckButton", nil, Window, "UICheckButtonTemplate")
	ranks:SetSize(22, 22)
	ranks:SetPoint("BOTTOMLEFT", Window, "BOTTOMLEFT", MARGIN + 170, 9)
	S:HandleCheckBox(ranks)
	ranks.label = ranks:CreateFontString(nil, "OVERLAY")
	ranks.label:FontTemplate(nil, 12, "OUTLINE")
	ranks.label:SetPoint("LEFT", ranks, "RIGHT", 4, 0)
	ranks.label:SetText("Alle Ränge")
	ranks:SetScript("OnClick", function(self)
		SetCVar("ShowAllSpellRanks", self:GetChecked() and "1" or "0")
		page = 1
		Refresh()
	end)
	Window.ranksCheck = ranks

	local pager = CreateFrame("Frame", nil, Window)
	pager:SetSize(110, 22)
	pager:SetPoint("BOTTOMLEFT", Window, "BOTTOMLEFT", MARGIN + 290, 9)
	pager.text = pager:CreateFontString(nil, "OVERLAY")
	pager.text:FontTemplate(nil, 12, "OUTLINE")
	pager.text:SetPoint("CENTER")
	local prev = CreateButton(pager, "<", 24)
	prev:SetPoint("LEFT", pager, "LEFT", 0, 0)
	prev:SetScript("OnClick", function()
		page = math.max(1, page - 1)
		Refresh()
	end)
	local nxt = CreateButton(pager, ">", 24)
	nxt:SetPoint("RIGHT", pager, "RIGHT", 0, 0)
	nxt:SetScript("OnClick", function()
		page = page + 1
		Refresh()
	end)
	Window.pager = pager
	Window:SetScript("OnMouseWheel", function(_, delta)
		page = math.max(1, page - delta)
		Refresh()
	end)

	for _, event in ipairs({"SPELLS_CHANGED", "LEARNED_SPELL_IN_TAB", "PLAYER_LEVEL_UP", "UNIT_PET",
		"PET_BAR_UPDATE", "PLAYER_REGEN_ENABLED"}) do
		Window:RegisterEvent(event)
	end
	Window:SetScript("OnEvent", Refresh)
	Window:SetScript("OnShow", function()
		PlaySound("igSpellBookOpen")
		DockClique()
		Refresh()
	end)
	Window:SetScript("OnHide", function()
		PlaySound("igSpellBookClose")
		if CliqueFrame and CliqueFrame:IsShown() and not InCombatLockdown() then
			Clique:Toggle()
		end
		ParkOverlay()
	end)

	CreateOverlay()
end

local function ShowBook(tab)
	if not Window then
		CreateWindow()
	end
	if tab then
		currentTab = tab
		page = 1
	end
	if Window:IsShown() then
		Refresh()
	else
		Window:Show()
	end
end

--------------------------------
-- Redirect Blizzard's spellbook

local hooked
local function HookSpellBook()
	if hooked or not SpellBookFrame then
		return
	end
	hooked = true
	SpellBookFrame:HookScript("OnShow", function(self)
		if not Enabled() then
			return
		end
		local pet = self.bookType == BOOKTYPE_PET
		HideUIPanel(self)
		if Window and Window:IsShown() and ((pet and currentTab == PET_TAB) or (not pet and currentTab ~= PET_TAB)) then
			Window:Hide()
		else
			ShowBook(pet and PET_TAB or (currentTab == PET_TAB and 2 or nil))
		end
	end)
end

local trainerTimer = CreateFrame("Frame")
trainerTimer:Hide()
trainerTimer:SetScript("OnUpdate", function(self)
	self:Hide()
	ScanTrainer()
end)

local loader = CreateFrame("Frame")
loader:RegisterEvent("PLAYER_LOGIN")
loader:RegisterEvent("TRAINER_SHOW")
loader:RegisterEvent("PLAYER_REGEN_DISABLED")
loader:SetScript("OnEvent", function(_, event)
	if event == "PLAYER_LOGIN" then
		HookSpellBook()
	elseif event == "PLAYER_REGEN_DISABLED" then
		-- Last moment before the lockdown: the secure overlay must not stay on the window
		ParkOverlay()
	elseif event == "TRAINER_SHOW" then
		-- One frame later, when the list is filled. Not on TRAINER_UPDATE: changing the
		-- filters during the scan fires it again
		trainerTimer:Show()
	end
end)

F.ToggleSpellbook = function()
	if Window and Window:IsShown() then
		Window:Hide()
	else
		ShowBook()
	end
end

-- /foreverbook: what the trainer scan stored for this class, per trainer group
SLASH_FOREVERBOOK1 = "/foreverbook"
SlashCmdList.FOREVERBOOK = function()
	local _, class = UnitClass("player")
	local data = DB()[class]
	if not data then
		print("Forever: noch keine Lehrerdaten fuer " .. class)
		return
	end
	local count = {}
	for _, e in ipairs(data.entries) do
		count[e.line] = (count[e.line] or 0) + 1
	end
	print(format("Forever: %d Eintraege fuer %s (%s)", #data.entries, class, date("%d.%m. %H:%M", data.time)))
	for line, n in pairs(count) do
		print(format("  %s: %d%s", line, n, TabExists(line) and "" or " (kein Reiter)"))
	end
end
