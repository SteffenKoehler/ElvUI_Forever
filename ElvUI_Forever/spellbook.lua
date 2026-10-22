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
local CLASS_SPELL_IDS -- filled at the end of the file

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

-- Hidden tooltip: the trainer gives no spell ID, its tooltip may (for chat links)
local scanTip = CreateFrame("GameTooltip", "ForeverSpellbookScanTip", nil, "GameTooltipTemplate")
scanTip:SetOwner(WorldFrame, "ANCHOR_NONE")

local function TrainerSpellID(index)
	scanTip:ClearLines()
	scanTip:SetTrainerService(index)
	local _, _, id = scanTip:GetSpell()
	return id
end
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
				id = TrainerSpellID(i),
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
-- Spell IDs for links: the trainer names spells only by name and rank. The ranked class
-- spells' IDs come from the client's data files (Spell.dbc / SkillLineAbility.dbc);
-- name and rank are read in-game with GetSpellInfo, so it works for every locale.

local idByNameRank

local function SpellIDFor(name, rank)
	if not idByNameRank then
		idByNameRank = {}
		local _, class = UnitClass("player")
		for _, id in ipairs(CLASS_SPELL_IDS[class] or {}) do
			local n, r = GetSpellInfo(id)
			if n then
				idByNameRank[n .. "|" .. (r or "")] = id
			end
		end
	end
	return idByNameRank[name .. "|" .. (rank or "")]
end

-- ID of an unlearned trainer spell: by name and rank, else what the trainer tooltip gave
-- (right for spells without ranks)
local function UnlearnedSpellID(e)
	return (e.rank and SpellIDFor(e.name, e.rank)) or (not e.rank and e.id) or nil
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
		-- Unknown spell whose trainer ranks start above 1: rank 1 is a talent
		-- (e.g. Sternenregen), the trainer only teaches the later ranks
		if not known[e.name] and RankNumber(e.rank) > 1 then
			e = setmetatable({rank = e.rank:gsub("%d+", "1", 1), talent = true}, {__index = e})
		end
		tinsert(list, {name = e.name, rank = e.rank, icon = e.icon, learned = false, data = e})
	end
	return list
end

-- Second line of an unlearned entry
local function UnlearnedInfo(e)
	if e.talent then
		return TALENT or "Talent", COLOR_REQ
	end
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
		local id = UnlearnedSpellID(e)
		if id then
			GameTooltip:SetHyperlink("spell:" .. id)
		else
			GameTooltip:AddDoubleLine(e.name, e.rank or "", 1, 1, 1, 0.5, 0.5, 0.5)
			if e.desc and e.desc ~= "" then
				GameTooltip:AddLine(e.desc, 1, 0.82, 0, true)
			end
		end
		local info, color = UnlearnedInfo(e)
		GameTooltip:AddLine(info, color[1], color[2], color[3])
	end
	GameTooltip:Show()
end

local function EntryOnClick(self, button)
	local entry = self.entry
	if not entry then
		return
	end
	if not entry.learned then
		-- Link when the trainer scan got the spell ID, otherwise the name as text
		if IsModifiedClick("CHATLINK") and ChatEdit_GetActiveWindow() then
			local e = entry.data
			local id = UnlearnedSpellID(e)
			local link = id and GetSpellLink(id)
			ChatEdit_InsertLink(link or ("[" .. e.name .. (e.rank and (" (" .. e.rank .. ")") or "") .. "]"))
		end
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

-- Ranked class spells per class (generated from the client data files, see above)
CLASS_SPELL_IDS = {
	DEATHKNIGHT = {
		43265, 45462, 45463, 45477, 45902, 47541, 48721, 48977, 48978, 48985, 48987, 49004, 49006, 49013, 49015, 49020,
		49024, 49042, 49137, 49143, 49145, 49158, 49175, 49182, 49184, 49194, 49203, 49217, 49219, 49224, 49390, 49391,
		49392, 49393, 49394, 49395, 49477, 49478, 49479, 49480, 49488, 49489, 49495, 49497, 49500, 49501, 49508, 49509,
		49526, 49538, 49588, 49589, 49610, 49611, 49627, 49628, 49654, 49655, 49657, 49786, 49787, 49788, 49789, 49892,
		49893, 49894, 49895, 49896, 49903, 49904, 49909, 49917, 49918, 49919, 49920, 49921, 49923, 49924, 49926, 49927,
		49928, 49929, 49930, 49936, 49937, 49938, 49939, 49940, 49941, 49998, 49999, 50029, 50031, 50040, 50041, 50043,
		50149, 50150, 50154, 50880, 50884, 50885, 50886, 50887, 51052, 51123, 51127, 51128, 51129, 51130, 51325, 51326,
		51327, 51328, 51409, 51410, 51411, 51416, 51417, 51418, 51419, 51423, 51424, 51425, 51456, 51459, 51462, 51463,
		51464, 51465, 55050, 55090, 55107, 55108, 55129, 55130, 55131, 55132, 55133, 55136, 55225, 55226, 55236, 55237,
		55258, 55259, 55260, 55261, 55262, 55265, 55268, 55270, 55271, 57330, 57623, 62905,
	},
	DRUID = {
		99, 339, 467, 740, 769, 774, 779, 780, 782, 1058, 1062, 1075, 1079, 1082, 1126, 1430,
		1735, 1822, 1823, 1824, 1850, 2090, 2091, 2637, 2908, 2912, 3029, 3627, 5176, 5177, 5178, 5179,
		5180, 5185, 5186, 5187, 5188, 5189, 5195, 5196, 5201, 5211, 5215, 5217, 5221, 5232, 5234, 5570,
		6756, 6778, 6780, 6783, 6785, 6787, 6793, 6798, 6800, 6807, 6808, 6809, 8903, 8905, 8907, 8910,
		8914, 8918, 8921, 8924, 8925, 8926, 8927, 8928, 8929, 8936, 8938, 8939, 8940, 8941, 8949, 8950,
		8951, 8955, 8972, 8983, 8992, 8998, 9000, 9005, 9007, 9490, 9492, 9493, 9745, 9747, 9750, 9752,
		9754, 9756, 9758, 9821, 9823, 9824, 9826, 9827, 9829, 9830, 9833, 9834, 9835, 9839, 9840, 9841,
		9845, 9846, 9849, 9850, 9852, 9853, 9856, 9857, 9858, 9862, 9863, 9866, 9867, 9875, 9876, 9880,
		9881, 9884, 9885, 9888, 9889, 9892, 9894, 9896, 9898, 9901, 9904, 9908, 9910, 9912, 9913, 16689,
		16810, 16811, 16812, 16813, 16914, 17329, 17401, 17402, 18657, 18658, 20484, 20739, 20742, 20747, 20748, 21849,
		21850, 22568, 22570, 22827, 22828, 22829, 22842, 24248, 24974, 24975, 24976, 24977, 25297, 25298, 25299, 26978,
		26979, 26980, 26981, 26982, 26983, 26984, 26985, 26986, 26987, 26988, 26989, 26990, 26991, 26992, 26994, 26995,
		26996, 26997, 26998, 27000, 27001, 27002, 27003, 27004, 27005, 27006, 27007, 27008, 27009, 27012, 27013, 31018,
		31709, 33357, 33745, 33763, 33876, 33878, 33982, 33983, 33986, 33987, 45477, 48377, 48378, 48389, 48392, 48393,
		48438, 48440, 48441, 48442, 48443, 48446, 48447, 48450, 48451, 48459, 48461, 48462, 48463, 48464, 48465, 48466,
		48468, 48469, 48470, 48477, 48479, 48480, 48488, 48489, 48491, 48505, 48514, 48532, 48535, 48536, 48537, 48559,
		48560, 48561, 48562, 48563, 48564, 48565, 48566, 48567, 48568, 48569, 48570, 48571, 48572, 48573, 48574, 48575,
		48576, 48577, 48578, 48579, 49020, 49024, 49042, 49137, 49143, 49175, 49184, 49203, 49538, 49657, 49786, 49787,
		49788, 49789, 49799, 49800, 49802, 49803, 49804, 49896, 49903, 49904, 49909, 50031, 50040, 50041, 50043, 50212,
		50213, 50464, 50516, 50763, 50764, 50765, 50766, 50767, 50768, 50769, 50880, 50884, 50885, 50886, 50887, 51123,
		51127, 51128, 51129, 51130, 51409, 51410, 51411, 51416, 51417, 51418, 51419, 51423, 51424, 51425, 51456, 52610,
		53199, 53200, 53201, 53223, 53225, 53226, 53227, 53248, 53249, 53251, 53307, 53308, 53312, 55268, 57330, 57623,
		62078,
	},
	HUNTER = {
		136, 1130, 1495, 1499, 1510, 1513, 1978, 2643, 2973, 3044, 3111, 3661, 3662, 3674, 13165, 13542,
		13543, 13544, 13549, 13550, 13551, 13552, 13553, 13554, 13555, 13795, 13813, 14260, 14261, 14262, 14263, 14264,
		14265, 14266, 14269, 14270, 14271, 14281, 14282, 14283, 14284, 14285, 14286, 14287, 14288, 14289, 14290, 14294,
		14295, 14302, 14303, 14304, 14305, 14310, 14311, 14316, 14317, 14318, 14319, 14320, 14321, 14322, 14323, 14324,
		14325, 14326, 14327, 19306, 19386, 19434, 19506, 20043, 20190, 20736, 20900, 20901, 20902, 20903, 20904, 20909,
		20910, 24132, 24133, 24406, 25294, 25295, 25296, 27014, 27016, 27019, 27021, 27022, 27023, 27025, 27044, 27045,
		27046, 27065, 27067, 27068, 34120, 36916, 45477, 48989, 48990, 48995, 48996, 48998, 48999, 49000, 49001, 49011,
		49012, 49020, 49024, 49042, 49044, 49045, 49047, 49048, 49049, 49050, 49051, 49052, 49055, 49056, 49066, 49067,
		49071, 49137, 49143, 49175, 49184, 49203, 49538, 49657, 49786, 49787, 49788, 49789, 49896, 49903, 49904, 49909,
		50031, 50040, 50041, 50043, 50880, 50884, 50885, 50886, 50887, 51123, 51127, 51128, 51129, 51130, 51409, 51410,
		51411, 51416, 51417, 51418, 51419, 51423, 51424, 51425, 51456, 53209, 53301, 53338, 53339, 53351, 55268, 56641,
		57330, 57623, 58431, 58434, 60051, 60052, 60053, 60192, 61005, 61006, 61846, 61847, 63668, 63669, 63670, 63671,
		63672,
	},
	MAGE = {
		10, 116, 118, 120, 122, 133, 143, 145, 168, 205, 543, 587, 597, 604, 759, 837,
		865, 990, 1008, 1449, 1459, 1460, 1461, 1463, 2120, 2121, 2136, 2137, 2138, 2948, 3140, 3552,
		5143, 5144, 5145, 5504, 5505, 5506, 6117, 6127, 6129, 6131, 6141, 6143, 6360, 7268, 7300, 7301,
		7302, 7320, 7322, 7813, 7814, 7815, 7816, 8400, 8401, 8402, 8406, 8407, 8408, 8412, 8413, 8416,
		8417, 8422, 8423, 8427, 8437, 8438, 8439, 8444, 8445, 8446, 8450, 8451, 8455, 8457, 8458, 8461,
		8462, 8492, 8494, 8495, 10053, 10054, 10138, 10139, 10140, 10144, 10145, 10148, 10149, 10150, 10151, 10156,
		10157, 10159, 10160, 10161, 10169, 10170, 10173, 10174, 10177, 10179, 10180, 10181, 10185, 10186, 10187, 10191,
		10192, 10193, 10197, 10199, 10201, 10202, 10205, 10206, 10207, 10211, 10212, 10215, 10216, 10219, 10220, 10223,
		10225, 10230, 11069, 11070, 11071, 11078, 11080, 11083, 11094, 11100, 11103, 11108, 11113, 11115, 11119, 11120,
		11124, 11151, 11160, 11170, 11175, 11180, 11185, 11189, 11190, 11207, 11210, 11213, 11222, 11232, 11237, 11242,
		11247, 11252, 11255, 11366, 11367, 11368, 11426, 11778, 11779, 11780, 11784, 11785, 12338, 12339, 12340, 12341,
		12349, 12350, 12351, 12353, 12357, 12358, 12378, 12398, 12399, 12400, 12463, 12464, 12467, 12469, 12473, 12484,
		12485, 12486, 12487, 12488, 12489, 12490, 12496, 12497, 12500, 12501, 12502, 12503, 12505, 12518, 12519, 12522,
		12523, 12524, 12525, 12526, 12569, 12571, 12574, 12575, 12576, 12577, 12592, 12598, 12605, 12606, 12672, 12824,
		12825, 12826, 12839, 12840, 12846, 12847, 12848, 12952, 12953, 12982, 12983, 13018, 13019, 13020, 13021, 13031,
		13032, 13033, 13043, 15047, 16763, 16765, 16766, 16769, 16770, 18809, 22782, 22783, 23028, 25304, 25306, 25345,
		27070, 27071, 27072, 27073, 27074, 27075, 27078, 27079, 27080, 27082, 27085, 27086, 27087, 27088, 27090, 27101,
		27124, 27125, 27126, 27127, 27128, 27130, 27131, 27132, 27133, 27134, 27274, 27275, 28332, 28592, 28593, 28609,
		28612, 29074, 29075, 29076, 29438, 29439, 29440, 29441, 29444, 30451, 30455, 30482, 31569, 31570, 31571, 31572,
		31574, 31575, 31579, 31582, 31583, 31584, 31585, 31586, 31587, 31588, 31638, 31639, 31640, 31641, 31642, 31656,
		31657, 31658, 31661, 31682, 31683, 32796, 33041, 33042, 33043, 33405, 33717, 33933, 33938, 33944, 33946, 34293,
		34295, 34296, 35578, 35581, 37420, 38692, 38697, 38699, 38704, 42832, 42833, 42841, 42842, 42843, 42846, 42858,
		42859, 42872, 42873, 42890, 42891, 42894, 42896, 42897, 42913, 42914, 42917, 42920, 42921, 42925, 42926, 42930,
		42931, 42939, 42940, 42944, 42945, 42949, 42950, 42955, 42956, 42985, 42995, 43002, 43008, 43010, 43012, 43015,
		43017, 43019, 43020, 43023, 43024, 43038, 43039, 43045, 43046, 43987, 44425, 44440, 44441, 44442, 44443, 44445,
		44446, 44448, 44449, 44457, 44469, 44470, 44471, 44472, 44543, 44545, 44546, 44548, 44549, 44557, 44560, 44561,
		44566, 44567, 44568, 44570, 44571, 44614, 44780, 44781, 45477, 47610, 47991, 47992, 49020, 49024, 49042, 49137,
		49143, 49175, 49184, 49203, 49538, 49657, 49786, 49787, 49788, 49789, 49896, 49903, 49904, 49909, 50031, 50040,
		50041, 50043, 50880, 50884, 50885, 50886, 50887, 51123, 51127, 51128, 51129, 51130, 51409, 51410, 51411, 51416,
		51417, 51418, 51419, 51423, 51424, 51425, 51456, 54354, 54747, 54749, 55268, 55359, 55360, 57330, 57623, 58659,
		61024, 61316,
	},
	PALADIN = {
		67, 465, 633, 635, 639, 643, 647, 853, 879, 1022, 1026, 1032, 1042, 2800, 2812, 3472,
		5588, 5589, 5599, 5614, 5615, 7294, 7328, 10278, 10290, 10291, 10292, 10293, 10298, 10299, 10300, 10301,
		10308, 10310, 10312, 10313, 10314, 10318, 10322, 10324, 10328, 10329, 19740, 19742, 19750, 19834, 19835, 19836,
		19837, 19838, 19850, 19852, 19853, 19854, 19876, 19888, 19891, 19895, 19896, 19897, 19898, 19899, 19900, 19939,
		19940, 19941, 19942, 19943, 20096, 20097, 20098, 20099, 20100, 20111, 20112, 20113, 20116, 20117, 20118, 20119,
		20120, 20121, 20143, 20144, 20145, 20146, 20147, 20185, 20186, 20187, 20196, 20197, 20198, 20425, 20473, 20772,
		20773, 20922, 20923, 20924, 20925, 20927, 20928, 20929, 20930, 24239, 24274, 24275, 25290, 25291, 25292, 25782,
		25894, 25916, 25918, 25997, 26017, 26573, 27135, 27136, 27137, 27138, 27139, 27140, 27141, 27142, 27143, 27149,
		27150, 27151, 27152, 27153, 27154, 27173, 27174, 27179, 27180, 31803, 31804, 31898, 31935, 32699, 32700, 33072,
		45477, 48781, 48782, 48784, 48785, 48788, 48800, 48801, 48805, 48806, 48816, 48817, 48818, 48819, 48820, 48821,
		48826, 48827, 48931, 48932, 48933, 48934, 48935, 48936, 48937, 48938, 48941, 48942, 48943, 48945, 48947, 48949,
		48950, 48951, 48952, 49020, 49024, 49137, 49143, 49175, 49184, 49203, 49538, 49657, 49896, 49903, 49904, 49909,
		50031, 50040, 50041, 50043, 50880, 50884, 50885, 50886, 50887, 51123, 51127, 51128, 51129, 51130, 51409, 51410,
		51411, 51416, 51417, 51418, 51419, 51423, 51424, 51425, 51456, 53600, 53601, 53726, 53733, 53742, 54043, 55268,
		57330, 57623, 61411,
	},
	PRIEST = {
		17, 139, 527, 585, 588, 589, 591, 592, 594, 596, 598, 600, 602, 724, 970, 976,
		984, 988, 992, 996, 1004, 1006, 1243, 1244, 1245, 2006, 2010, 2050, 2052, 2053, 2054, 2055,
		2060, 2061, 2096, 2767, 2791, 2944, 3747, 6060, 6063, 6064, 6065, 6066, 6074, 6075, 6076, 6077,
		6078, 7001, 7128, 8092, 8102, 8103, 8104, 8105, 8106, 8122, 8124, 9472, 9473, 9474, 9484, 9485,
		10880, 10881, 10888, 10890, 10892, 10893, 10894, 10898, 10899, 10900, 10901, 10909, 10915, 10916, 10917, 10927,
		10928, 10929, 10933, 10934, 10937, 10938, 10945, 10946, 10947, 10951, 10952, 10955, 10957, 10958, 10960, 10961,
		10963, 10964, 10965, 14752, 14818, 14819, 14914, 15237, 15261, 15262, 15263, 15264, 15265, 15266, 15267, 15407,
		15430, 15431, 17311, 17312, 17313, 17314, 18807, 19236, 19238, 19240, 19241, 19242, 19243, 19276, 19277, 19278,
		19279, 19280, 20770, 21562, 21564, 25210, 25213, 25217, 25218, 25221, 25222, 25233, 25235, 25308, 25312, 25314,
		25315, 25316, 25329, 25363, 25364, 25367, 25368, 25372, 25375, 25384, 25387, 25389, 25392, 25431, 25433, 25435,
		25437, 25467, 27681, 27683, 27799, 27800, 27801, 27841, 27870, 27871, 27873, 27874, 28275, 28276, 32379, 32546,
		32996, 32999, 33076, 34753, 34859, 34860, 34861, 34863, 34864, 34865, 34866, 34914, 34916, 34917, 39374, 45477,
		47540, 47788, 48040, 48045, 48062, 48063, 48065, 48066, 48067, 48068, 48070, 48071, 48072, 48073, 48074, 48075,
		48076, 48084, 48085, 48086, 48087, 48088, 48089, 48112, 48113, 48119, 48120, 48122, 48123, 48124, 48125, 48126,
		48127, 48134, 48135, 48155, 48156, 48157, 48158, 48159, 48160, 48161, 48162, 48168, 48169, 48170, 48171, 48172,
		48173, 48299, 48300, 49020, 49024, 49042, 49137, 49143, 49175, 49184, 49203, 49538, 49657, 49786, 49787, 49788,
		49789, 49896, 49903, 49904, 49909, 50031, 50040, 50041, 50043, 50880, 50884, 50885, 50886, 50887, 51123, 51127,
		51128, 51129, 51130, 51409, 51410, 51411, 51416, 51417, 51418, 51419, 51423, 51424, 51425, 51456, 52983, 52984,
		52985, 53023, 55268, 57330, 57623, 64843,
	},
	ROGUE = {
		53, 408, 703, 1329, 1752, 1757, 1758, 1759, 1760, 1784, 1785, 1786, 1787, 1856, 1857, 1943,
		1966, 2070, 2098, 2589, 2590, 2591, 2983, 5171, 5277, 6760, 6761, 6762, 6768, 6770, 6774, 8621,
		8623, 8624, 8631, 8632, 8633, 8637, 8639, 8640, 8643, 8676, 8696, 8721, 8724, 8725, 11267, 11268,
		11269, 11273, 11274, 11275, 11279, 11280, 11281, 11289, 11290, 11293, 11294, 11297, 11299, 11300, 11303, 11305,
		13706, 13709, 13800, 13801, 13802, 13803, 13804, 13805, 13806, 13807, 13960, 13961, 13962, 13963, 13964, 14186,
		14190, 14193, 14194, 14195, 16511, 17347, 17348, 25300, 25302, 26669, 26679, 26839, 26861, 26862, 26863, 26864,
		26865, 26867, 26884, 26889, 27441, 27448, 31016, 31122, 31123, 31130, 31131, 31226, 31227, 31228, 31229, 31230,
		31244, 31245, 31380, 31382, 31383, 32645, 32684, 34411, 34412, 34413, 45477, 48637, 48638, 48656, 48657, 48658,
		48659, 48660, 48663, 48666, 48667, 48668, 48671, 48672, 48673, 48674, 48675, 48676, 48689, 48690, 48691, 49020,
		49024, 49042, 49137, 49143, 49175, 49184, 49203, 49538, 49657, 49786, 49787, 49788, 49789, 49896, 49903, 49904,
		49909, 50031, 50040, 50041, 50043, 50880, 50884, 50885, 50886, 50887, 51123, 51127, 51128, 51129, 51130, 51409,
		51410, 51411, 51416, 51417, 51418, 51419, 51423, 51424, 51425, 51456, 51700, 51701, 51724, 55268, 57330, 57623,
		57992, 57993, 58410, 61329,
	},
	SHAMAN = {
		324, 325, 331, 332, 370, 403, 421, 529, 547, 548, 905, 913, 915, 930, 939, 943,
		945, 959, 974, 1064, 1535, 2008, 2860, 3599, 5394, 5675, 5730, 6041, 6363, 6364, 6365, 6375,
		6377, 6390, 6391, 6392, 8004, 8005, 8008, 8010, 8012, 8017, 8018, 8019, 8024, 8027, 8030, 8033,
		8038, 8042, 8044, 8045, 8046, 8050, 8052, 8053, 8056, 8058, 8071, 8075, 8134, 8154, 8155, 8160,
		8161, 8181, 8184, 8190, 8227, 8232, 8235, 8249, 8498, 8499, 10391, 10392, 10395, 10396, 10399, 10406,
		10407, 10408, 10412, 10413, 10414, 10427, 10428, 10431, 10432, 10437, 10438, 10442, 10447, 10448, 10456, 10462,
		10463, 10466, 10467, 10468, 10472, 10473, 10478, 10479, 10486, 10495, 10496, 10497, 10526, 10537, 10538, 10585,
		10586, 10587, 10595, 10600, 10601, 10605, 10622, 10623, 11314, 11315, 15207, 15208, 16252, 16253, 16254, 16255,
		16256, 16271, 16272, 16281, 16282, 16283, 16284, 16298, 16302, 16303, 16304, 16305, 16306, 16307, 16308, 16309,
		16339, 16341, 16342, 16355, 16356, 16362, 16387, 20609, 20610, 20776, 20777, 24398, 25357, 25361, 25391, 25396,
		25420, 25422, 25423, 25439, 25442, 25448, 25449, 25454, 25457, 25464, 25469, 25472, 25489, 25500, 25505, 25508,
		25509, 25525, 25528, 25533, 25546, 25547, 25552, 25557, 25560, 25563, 25567, 25570, 25574, 25590, 29082, 29084,
		29086, 29228, 30706, 32593, 32594, 33736, 45477, 49020, 49024, 49137, 49143, 49175, 49184, 49203, 49230, 49231,
		49232, 49233, 49235, 49236, 49237, 49238, 49268, 49269, 49272, 49273, 49275, 49276, 49277, 49280, 49281, 49283,
		49284, 49538, 49657, 49896, 49903, 49904, 49909, 50031, 50040, 50041, 50043, 50880, 50884, 50885, 50886, 50887,
		51123, 51127, 51128, 51129, 51130, 51409, 51410, 51411, 51416, 51417, 51418, 51419, 51423, 51424, 51425, 51456,
		51466, 51470, 51474, 51478, 51479, 51483, 51485, 51486, 51490, 51505, 51521, 51522, 51523, 51524, 51528, 51529,
		51530, 51531, 51532, 51562, 51563, 51564, 51565, 51566, 51730, 51988, 51991, 51992, 51993, 51994, 52127, 52129,
		52131, 52134, 52136, 52138, 55268, 55458, 55459, 57330, 57622, 57623, 57720, 57721, 57722, 57960, 58580, 58581,
		58582, 58643, 58649, 58652, 58656, 58699, 58703, 58704, 58731, 58734, 58737, 58739, 58741, 58745, 58746, 58749,
		58751, 58753, 58755, 58756, 58757, 58771, 58773, 58774, 58785, 58789, 58790, 58794, 58795, 58796, 58801, 58803,
		58804, 59156, 59158, 59159, 60043, 60103, 61295, 61299, 61300, 61301, 61649, 61657, 62097, 62098, 62099, 62100,
		62101,
	},
	WARLOCK = {
		172, 348, 603, 686, 687, 689, 693, 695, 696, 699, 702, 705, 706, 707, 709, 710,
		755, 980, 1010, 1014, 1086, 1088, 1094, 1098, 1106, 1108, 1120, 1454, 1455, 1456, 1490, 1714,
		1949, 2362, 2941, 3698, 3699, 3700, 5484, 5676, 5699, 5740, 5782, 6201, 6202, 6205, 6213, 6215,
		6217, 6219, 6222, 6223, 6229, 6353, 6366, 6789, 7641, 7646, 7648, 7651, 8288, 8289, 11659, 11660,
		11661, 11665, 11667, 11668, 11671, 11672, 11675, 11677, 11678, 11683, 11684, 11687, 11688, 11689, 11693, 11694,
		11695, 11699, 11700, 11707, 11708, 11711, 11712, 11713, 11719, 11721, 11722, 11725, 11726, 11729, 11730, 11733,
		11734, 11735, 11739, 11740, 17727, 17728, 17877, 17919, 17920, 17921, 17922, 17923, 17924, 17925, 17926, 17928,
		17951, 17952, 17953, 18094, 18095, 18220, 18647, 18867, 18868, 18869, 18870, 18871, 18937, 18938, 20752, 20755,
		20756, 20757, 25307, 25309, 25311, 27209, 27210, 27211, 27212, 27213, 27215, 27216, 27217, 27218, 27219, 27220,
		27222, 27223, 27224, 27228, 27230, 27238, 27243, 27250, 27259, 27260, 27263, 27265, 28172, 28176, 28189, 28610,
		29722, 29893, 30108, 30283, 30404, 30405, 30413, 30414, 30459, 30545, 30546, 30909, 30910, 32231, 34935, 34938,
		34939, 45477, 47206, 47793, 47808, 47809, 47810, 47811, 47812, 47813, 47814, 47815, 47819, 47820, 47822, 47823,
		47824, 47825, 47826, 47827, 47833, 47834, 47837, 47838, 47841, 47843, 47846, 47847, 47855, 47856, 47857, 47859,
		47860, 47863, 47864, 47865, 47867, 47871, 47878, 47884, 47886, 47888, 47889, 47890, 47891, 47892, 47893, 47897,
		48181, 49020, 49024, 49042, 49137, 49143, 49175, 49184, 49203, 49538, 49657, 49786, 49787, 49788, 49789, 49896,
		49903, 49904, 49909, 50031, 50040, 50041, 50043, 50511, 50796, 50880, 50884, 50885, 50886, 50887, 51123, 51127,
		51128, 51129, 51130, 51409, 51410, 51411, 51416, 51417, 51418, 51419, 51423, 51424, 51425, 51456, 55268, 57330,
		57623, 57946, 58887, 59092, 59161, 59163, 59164, 59170, 59171, 59172, 60219, 60220, 61191, 61290, 63349, 63351,
	},
	WARRIOR = {
		78, 100, 284, 285, 469, 772, 845, 1160, 1464, 1608, 2048, 5242, 5308, 6178, 6190, 6192,
		6343, 6546, 6547, 6548, 6572, 6574, 6673, 7369, 7379, 8198, 8204, 8205, 8820, 11549, 11550, 11551,
		11554, 11555, 11556, 11564, 11565, 11566, 11567, 11572, 11573, 11574, 11578, 11580, 11581, 11600, 11601, 11604,
		11605, 11608, 11609, 12163, 12281, 12282, 12284, 12285, 12286, 12287, 12289, 12290, 12294, 12295, 12297, 12298,
		12299, 12300, 12301, 12308, 12311, 12312, 12313, 12317, 12318, 12319, 12320, 12321, 12322, 12324, 12327, 12329,
		12330, 12658, 12663, 12664, 12665, 12666, 12668, 12676, 12677, 12695, 12696, 12697, 12700, 12701, 12702, 12703,
		12704, 12711, 12712, 12723, 12724, 12725, 12726, 12727, 12750, 12751, 12752, 12753, 12761, 12762, 12763, 12764,
		12781, 12783, 12784, 12785, 12797, 12798, 12799, 12803, 12804, 12810, 12811, 12812, 12813, 12814, 12815, 12818,
		12834, 12835, 12849, 12852, 12853, 12855, 12856, 12857, 12858, 12860, 12861, 12862, 12867, 12876, 12877, 12878,
		12879, 12886, 12950, 12958, 12959, 12960, 12963, 12967, 12968, 12969, 12970, 12999, 13000, 13001, 13002, 13045,
		13046, 13047, 13048, 16538, 16539, 16540, 16541, 16542, 20243, 20496, 20505, 20569, 20658, 20660, 20661, 20662,
		21551, 21552, 21553, 23695, 23922, 23923, 23924, 23925, 25202, 25203, 25208, 25231, 25234, 25236, 25241, 25242,
		25248, 25258, 25264, 25269, 25286, 25288, 25289, 29598, 29599, 29707, 29721, 29723, 29724, 29725, 29776, 29787,
		29790, 29792, 29801, 29834, 29836, 29838, 29859, 29888, 30016, 30022, 30324, 30330, 30356, 30357, 35446, 35448,
		35449, 45477, 46845, 46854, 46855, 46859, 46860, 46865, 46866, 46867, 46945, 46947, 46951, 46952, 46953, 47294,
		47295, 47296, 47436, 47437, 47439, 47440, 47449, 47450, 47465, 47470, 47471, 47474, 47475, 47485, 47486, 47487,
		47488, 47497, 47498, 47501, 47502, 47519, 47520, 49020, 49024, 49137, 49143, 49175, 49184, 49203, 49538, 49657,
		49896, 49903, 49904, 49909, 50031, 50040, 50041, 50043, 50685, 50686, 50687, 50880, 50884, 50885, 50886, 50887,
		51123, 51127, 51128, 51129, 51130, 51409, 51410, 51411, 51416, 51417, 51418, 51419, 51423, 51424, 51425, 51456,
		55268, 56611, 56612, 56613, 56614, 56636, 56637, 56638, 56927, 56929, 56930, 56931, 56932, 57330, 57623, 57823,
		58872, 58874, 61216, 61221, 61222,
	},
}
