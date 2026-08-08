local addonName, GCP = ...

GCP.UI = {}
local UI = GCP.UI

-- ---------------------------------------------------------------------------
-- Designsystem: flache dunkle Flaechen, 1-Pixel-Raender, eine Goldakzentfarbe,
-- enge Typo-Hierarchie. Bewusst keine Blizzard-Dialogtexturen und -Buttons.
-- ---------------------------------------------------------------------------

local COLOR = {
    bg          = { 0.055, 0.055, 0.070, 0.96 },
    panel       = { 0.100, 0.100, 0.125, 1 },
    panelLight  = { 0.145, 0.145, 0.175, 1 },
    border      = { 0.230, 0.230, 0.270, 1 },
    accent      = { 0.850, 0.660, 0.200, 1 },
    accentSoft  = { 0.850, 0.660, 0.200, 0.16 },
    text        = { 0.930, 0.930, 0.945 },
    textDim     = { 0.600, 0.600, 0.660 },
    green       = { 0.350, 0.800, 0.350 },
    red         = { 0.880, 0.360, 0.360 },
    zebra       = { 1, 1, 1, 0.024 },
    hover       = { 0.850, 0.660, 0.200, 0.07 },
}

local FONT = "Fonts\\FRIZQT__.TTF"
local FONT_NUM = "Fonts\\ARIALN.TTF"
local WHITE = "Interface\\Buttons\\WHITE8x8"
local LOGO = "Interface\\AddOns\\GoldCopilot\\Media\\GoldCopilotLogo"

local ROW_HEIGHT = 26
local SECTION_HEIGHT = 32
local FRAME_WIDTH = 860
local FRAME_HEIGHT = 620

local qualityColors = {
    [0] = "|cff9d9d9d", [1] = "|cffffffff", [2] = "|cff1eff00",
    [3] = "|cff0070dd", [4] = "|cffa335ee", [5] = "|cffff8000",
}

local channelColor = {
    ["AH"] = { 0.30, 0.75, 1.00 },
    ["Händler"] = { 0.85, 0.66, 0.20 },
    ["Entzaubern"] = { 0.64, 0.21, 0.93 },
}

local function rgb(color)
    return color[1], color[2], color[3], color[4]
end

local function applyBackdrop(frame, bgColor, borderColor)
    frame.gcpBg = frame.gcpBg or frame:CreateTexture(nil, "BACKGROUND")
    frame.gcpBg:SetAllPoints()
    frame.gcpBg:SetTexture(WHITE)
    frame.gcpBg:SetVertexColor(rgb(bgColor))
    if borderColor then
        if not frame.gcpBorders then
            frame.gcpBorders = {}
            for i = 1, 4 do
                frame.gcpBorders[i] = frame:CreateTexture(nil, "BORDER")
                frame.gcpBorders[i]:SetTexture(WHITE)
            end
            frame.gcpBorders[1]:SetPoint("TOPLEFT", 0, 0)
            frame.gcpBorders[1]:SetPoint("TOPRIGHT", 0, 0)
            frame.gcpBorders[1]:SetHeight(1)
            frame.gcpBorders[2]:SetPoint("BOTTOMLEFT", 0, 0)
            frame.gcpBorders[2]:SetPoint("BOTTOMRIGHT", 0, 0)
            frame.gcpBorders[2]:SetHeight(1)
            frame.gcpBorders[3]:SetPoint("TOPLEFT", 0, 0)
            frame.gcpBorders[3]:SetPoint("BOTTOMLEFT", 0, 0)
            frame.gcpBorders[3]:SetWidth(1)
            frame.gcpBorders[4]:SetPoint("TOPRIGHT", 0, 0)
            frame.gcpBorders[4]:SetPoint("BOTTOMRIGHT", 0, 0)
            frame.gcpBorders[4]:SetWidth(1)
        end
        for i = 1, 4 do
            frame.gcpBorders[i]:SetVertexColor(rgb(borderColor))
        end
    end
end

local function createText(parent, size, color, numeric, flags)
    local text = parent:CreateFontString(nil, "OVERLAY")
    text:SetFont(numeric and FONT_NUM or FONT, size, flags or "")
    local c = color or COLOR.text
    text:SetTextColor(c[1], c[2], c[3])
    text:SetShadowColor(0, 0, 0, 0.9)
    text:SetShadowOffset(1, -1)
    return text
end

-- Flacher Button mit Hover und aktivem Zustand (goldene Unterlinie).
local function createFlatButton(parent, label, width, height)
    local button = CreateFrame("Button", nil, parent)
    button:SetSize(width or 110, height or 24)
    applyBackdrop(button, COLOR.panel, COLOR.border)
    button.label = createText(button, 12, COLOR.textDim)
    button.label:SetPoint("CENTER", 0, 0)
    button.label:SetText(label or "")
    button.underline = button:CreateTexture(nil, "OVERLAY")
    button.underline:SetTexture(WHITE)
    button.underline:SetVertexColor(rgb(COLOR.accent))
    button.underline:SetPoint("BOTTOMLEFT", 1, 1)
    button.underline:SetPoint("BOTTOMRIGHT", -1, 1)
    button.underline:SetHeight(2)
    button.underline:Hide()
    button:SetScript("OnEnter", function(self)
        if not self.active then
            self.gcpBg:SetVertexColor(rgb(COLOR.panelLight))
        end
    end)
    button:SetScript("OnLeave", function(self)
        if not self.active then
            self.gcpBg:SetVertexColor(rgb(COLOR.panel))
        end
    end)
    function button:SetActive(active)
        self.active = active
        if active then
            self.gcpBg:SetVertexColor(rgb(COLOR.panelLight))
            self.label:SetTextColor(COLOR.accent[1], COLOR.accent[2], COLOR.accent[3])
            self.underline:Show()
        else
            self.gcpBg:SetVertexColor(rgb(COLOR.panel))
            self.label:SetTextColor(COLOR.textDim[1], COLOR.textDim[2], COLOR.textDim[3])
            self.underline:Hide()
        end
    end
    function button:SetLabel(text)
        self.label:SetText(text)
    end
    return button
end

-- Kleines farbiges Etikett ("Pill") fuer Kanal, Empfehlung oder Bestand.
local function createPill(parent)
    local pill = CreateFrame("Frame", nil, parent)
    pill:SetHeight(16)
    pill.bg = pill:CreateTexture(nil, "BACKGROUND")
    pill.bg:SetAllPoints()
    pill.bg:SetTexture(WHITE)
    pill.text = createText(pill, 11, COLOR.text)
    pill.text:SetPoint("CENTER", 0, 0)
    function pill:Set(label, color)
        if not label then
            self:Hide()
            return
        end
        self.text:SetText(label)
        local c = color or COLOR.textDim
        self.bg:SetVertexColor(c[1], c[2], c[3], 0.16)
        self.text:SetTextColor(c[1] * 0.75 + 0.25, c[2] * 0.75 + 0.25, c[3] * 0.75 + 0.25)
        self:SetWidth(self.text:GetStringWidth() + 14)
        self:Show()
    end
    return pill
end

-- ---------------------------------------------------------------------------
-- Fensteraufbau
-- ---------------------------------------------------------------------------

function UI:EnsureFrame()
    if self.frame then return self.frame end

    local frame = CreateFrame("Frame", "GoldCopilotFrame", UIParent)
    frame:SetSize(FRAME_WIDTH, FRAME_HEIGHT)
    frame:SetPoint("CENTER")
    frame:SetFrameStrata("HIGH")
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    frame:SetClampedToScreen(true)
    applyBackdrop(frame, COLOR.bg, COLOR.border)
    frame:Hide()
    tinsert(UISpecialFrames, "GoldCopilotFrame")

    -- Kopfzeile
    local logo = frame:CreateTexture(nil, "ARTWORK")
    logo:SetSize(34, 34)
    logo:SetPoint("TOPLEFT", 14, -10)
    logo:SetTexture(LOGO)
    frame.logo = logo

    local title = createText(frame, 19, COLOR.accent, false, "")
    title:SetPoint("TOPLEFT", 56, -14)
    title:SetText("Gold Copilot")

    local version = createText(frame, 11, COLOR.textDim)
    version:SetPoint("BOTTOMLEFT", title, "BOTTOMRIGHT", 8, 1)
    version:SetText("v" .. GCP.Constants.VERSION)

    local trend = createText(frame, 11, COLOR.textDim)
    trend:SetPoint("TOPLEFT", 56, -37)
    trend:SetJustifyH("LEFT")
    frame.trend = trend

    local source = createText(frame, 11, COLOR.textDim)
    source:SetPoint("TOPRIGHT", -44, -18)
    source:SetJustifyH("RIGHT")
    frame.source = source

    local close = CreateFrame("Button", nil, frame)
    close:SetSize(26, 26)
    close:SetPoint("TOPRIGHT", -8, -8)
    applyBackdrop(close, COLOR.panel, COLOR.border)
    close.label = createText(close, 14, COLOR.textDim)
    close.label:SetPoint("CENTER", 0, 0)
    close.label:SetText("×")
    close:SetScript("OnEnter", function(self)
        self.gcpBg:SetVertexColor(0.6, 0.15, 0.15, 1)
        self.label:SetTextColor(1, 1, 1)
    end)
    close:SetScript("OnLeave", function(self)
        self.gcpBg:SetVertexColor(rgb(COLOR.panel))
        self.label:SetTextColor(COLOR.textDim[1], COLOR.textDim[2], COLOR.textDim[3])
    end)
    close:SetScript("OnClick", function() frame:Hide() end)

    local headerLine = frame:CreateTexture(nil, "ARTWORK")
    headerLine:SetTexture(WHITE)
    headerLine:SetVertexColor(rgb(COLOR.accent))
    headerLine:SetAlpha(0.55)
    headerLine:SetPoint("TOPLEFT", 12, -52)
    headerLine:SetPoint("TOPRIGHT", -12, -52)
    headerLine:SetHeight(1)

    -- Tab-Leiste
    frame.tabs = {}
    local tabDefs = {
        { key = "today", label = "Heute" },
        { key = "sell", label = "Verkaufen" },
        { key = "flips", label = "Flips" },
        { key = "crafts", label = "Crafts" },
        { key = "options", label = "Optionen" },
    }
    local previous
    for _, def in ipairs(tabDefs) do
        local tab = createFlatButton(frame, def.label, 118, 26)
        if previous then
            tab:SetPoint("LEFT", previous, "RIGHT", 4, 0)
        else
            tab:SetPoint("TOPLEFT", 14, -60)
        end
        tab:SetScript("OnClick", function()
            UI:SelectTab(def.key)
        end)
        frame.tabs[def.key] = tab
        previous = tab
    end

    -- Werkzeugleiste (nur Verkaufen- und Crafts-Tab)
    local toolbar = CreateFrame("Frame", nil, frame)
    toolbar:SetPoint("TOPLEFT", 14, -92)
    toolbar:SetPoint("TOPRIGHT", -14, -92)
    toolbar:SetHeight(24)
    frame.toolbar = toolbar

    frame.scopeButton = createFlatButton(toolbar, "Umfang: Account", 140, 22)
    frame.scopeButton:SetPoint("LEFT")
    frame.scopeButton:SetScript("OnClick", function()
        UI.scope = UI.scope == "account" and "bags" or "account"
        UI:Refresh()
    end)

    frame.filterButton = createFlatButton(toolbar, "Filter: Alles", 130, 22)
    frame.filterButton:SetPoint("LEFT", frame.scopeButton, "RIGHT", 4, 0)
    frame.filterButton:SetScript("OnClick", function()
        local order = { all = "mats", mats = "gear", gear = "all" }
        UI.filter = order[UI.filter or "all"]
        UI:Refresh()
    end)

    frame.boundButton = createFlatButton(toolbar, "Gebundenes: an", 130, 22)
    frame.boundButton:SetPoint("LEFT", frame.filterButton, "RIGHT", 4, 0)
    frame.boundButton:SetScript("OnClick", function()
        GCP.db.options.hideBound = not GCP.db.options.hideBound
        UI:Refresh()
    end)

    frame.ignoredButton = createFlatButton(toolbar, "Ignoriert (0)", 120, 22)
    frame.ignoredButton:SetPoint("LEFT", frame.boundButton, "RIGHT", 4, 0)
    frame.ignoredButton:SetScript("OnClick", function()
        UI.showIgnored = not UI.showIgnored
        UI:Refresh()
    end)

    frame.craftableButton = createFlatButton(toolbar, "Nur machbare: aus", 150, 22)
    frame.craftableButton:SetPoint("LEFT")
    frame.craftableButton:SetScript("OnClick", function()
        UI.onlyCraftable = not UI.onlyCraftable
        UI:Refresh()
    end)

    frame.refreshButton = createFlatButton(toolbar, "Aktualisieren", 110, 22)
    frame.refreshButton:SetPoint("RIGHT")
    frame.refreshButton:SetScript("OnClick", function()
        GCP.Prices:RecordObservedPrices()
        UI:Refresh()
    end)

    -- Status: Zusammenfassung links, Tagesfortschritt rechts
    local summary = createText(frame, 12, COLOR.text)
    summary:SetPoint("TOPLEFT", 16, -124)
    summary:SetJustifyH("LEFT")
    frame.summary = summary

    local progressLabel = createText(frame, 11, COLOR.textDim, true)
    progressLabel:SetPoint("TOPRIGHT", -180, -124)
    frame.progressLabel = progressLabel

    local progress = CreateFrame("Frame", nil, frame)
    progress:SetSize(160, 8)
    progress:SetPoint("TOPRIGHT", -14, -126)
    applyBackdrop(progress, COLOR.panel, COLOR.border)
    progress.fill = progress:CreateTexture(nil, "ARTWORK")
    progress.fill:SetTexture(WHITE)
    progress.fill:SetVertexColor(rgb(COLOR.accent))
    progress.fill:SetPoint("TOPLEFT", 1, -1)
    progress.fill:SetPoint("BOTTOMLEFT", 1, 1)
    progress.fill:SetWidth(1)
    frame.progress = progress

    -- Scrollbereich
    local scroll = CreateFrame("ScrollFrame", "GoldCopilotScrollFrame", frame, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 14, -142)
    scroll:SetPoint("BOTTOMRIGHT", -30, 14)
    local content = CreateFrame("Frame", nil, scroll)
    content:SetSize(FRAME_WIDTH - 44, 100)
    scroll:SetScrollChild(content)
    frame.scroll = scroll
    frame.content = content

    -- Optionen als eigenes Panel statt Zeilenliste
    frame.optionsPanel = self:BuildOptionsPanel(frame)
    frame.optionsPanel:SetPoint("TOPLEFT", 14, -142)
    frame.optionsPanel:SetPoint("BOTTOMRIGHT", -14, 14)
    frame.optionsPanel:Hide()

    -- GetItemInfo liefert asynchron nach; ein gebuendelter Refresh reicht.
    frame:RegisterEvent("GET_ITEM_INFO_RECEIVED")
    frame:SetScript("OnEvent", function()
        if frame:IsShown() and not UI.pendingRefresh then
            UI.pendingRefresh = true
            C_Timer.After(0.4, function()
                UI.pendingRefresh = false
                if frame:IsShown() then
                    UI:Refresh()
                end
            end)
        end
    end)
    frame:SetScript("OnShow", function()
        GCP:RecordGold()
        GCP.Prices:RecordObservedPrices()
        UI:Refresh()
    end)

    self.frame = frame
    self.rows = {}
    self.scope = "account"
    self.filter = "all"
    self.activeTab = "today"
    return frame
end

-- ---------------------------------------------------------------------------
-- Zeilen-Pool
-- ---------------------------------------------------------------------------

local function rowOnEnter(row)
    row.hoverTex:Show()
    local data = row.data
    if not data then return end
    if data.link or data.itemID then
        GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
        local shown = false
        if data.link then
            shown = pcall(GameTooltip.SetHyperlink, GameTooltip, data.link)
        elseif data.itemID then
            shown = pcall(GameTooltip.SetItemByID, GameTooltip, data.itemID)
        end
        if data.breakdown then
            if shown then GameTooltip:AddLine(" ") end
            for _, line in ipairs(data.breakdown) do
                GameTooltip:AddLine(line, 0.9, 0.9, 0.9, true)
            end
        end
        GameTooltip:Show()
    end
end

local function rowOnLeave(row)
    row.hoverTex:Hide()
    GameTooltip:Hide()
end

local function rowOnClick(row)
    local data = row.data
    if data and data.link and IsShiftKeyDown() and ChatEdit_InsertLink then
        ChatEdit_InsertLink(data.link)
    end
end

local function rowOnDoubleClick(row)
    local data = row.data
    if data and data.ignorable then
        GCP.Advisor:ToggleIgnored(data.ignorable)
        UI:Refresh()
    end
end

function UI:AcquireRow(index)
    local row = self.rows[index]
    if row then
        row:Show()
        return row
    end
    local content = self.frame.content
    row = CreateFrame("Button", nil, content)
    row:SetHeight(ROW_HEIGHT)

    row.zebraTex = row:CreateTexture(nil, "BACKGROUND")
    row.zebraTex:SetAllPoints()
    row.zebraTex:SetTexture(WHITE)
    row.zebraTex:SetVertexColor(rgb(COLOR.zebra))

    row.hoverTex = row:CreateTexture(nil, "BACKGROUND", nil, 1)
    row.hoverTex:SetAllPoints()
    row.hoverTex:SetTexture(WHITE)
    row.hoverTex:SetVertexColor(rgb(COLOR.hover))
    row.hoverTex:Hide()

    row.sectionLine = row:CreateTexture(nil, "ARTWORK")
    row.sectionLine:SetTexture(WHITE)
    row.sectionLine:SetVertexColor(rgb(COLOR.accent))
    row.sectionLine:SetAlpha(0.35)
    row.sectionLine:SetPoint("BOTTOMLEFT", 2, 4)
    row.sectionLine:SetPoint("BOTTOMRIGHT", -2, 4)
    row.sectionLine:SetHeight(1)

    row:EnableMouse(true)
    row:SetScript("OnEnter", rowOnEnter)
    row:SetScript("OnLeave", rowOnLeave)
    row:SetScript("OnClick", rowOnClick)
    row:SetScript("OnDoubleClick", rowOnDoubleClick)

    -- Eigene flache Checkbox
    row.check = CreateFrame("Button", nil, row)
    row.check:SetSize(16, 16)
    row.check:SetPoint("LEFT", 4, 0)
    applyBackdrop(row.check, COLOR.panel, COLOR.border)
    row.check.mark = row.check:CreateTexture(nil, "OVERLAY")
    row.check.mark:SetTexture("Interface\\Buttons\\UI-CheckBox-Check")
    row.check.mark:SetPoint("CENTER", 0, 0)
    row.check.mark:SetSize(20, 20)
    row.check.mark:Hide()
    row.check:SetScript("OnClick", function(check)
        local data = check:GetParent().data
        if data and data.roadmapKey and not data.autoDone then
            local nowChecked = not data.checked
            GCP.Roadmap:SetChecked(data.roadmapKey, nowChecked)
            UI:Refresh()
        end
    end)

    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(20, 20)
    row.icon:SetPoint("LEFT", 28, 0)
    row.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)

    row.text = createText(row, 12, COLOR.text)
    row.text:SetPoint("LEFT", 54, 0)
    row.text:SetJustifyH("LEFT")
    row.text:SetWordWrap(false)

    row.autoPill = createPill(row)
    row.autoPill:SetPoint("RIGHT", -280, 0)

    row.pill = createPill(row)
    row.pill:SetPoint("RIGHT", -160, 0)

    row.value2 = createText(row, 12, COLOR.textDim, true)
    row.value2:SetPoint("RIGHT", -84, 0)
    row.value2:SetJustifyH("RIGHT")

    row.value = createText(row, 13, COLOR.text, true)
    row.value:SetPoint("RIGHT", -6, 0)
    row.value:SetJustifyH("RIGHT")

    self.rows[index] = row
    return row
end

local function resetRow(row)
    row.data = nil
    row.isHeader = false
    row:SetHeight(ROW_HEIGHT)
    row.zebraTex:Show()
    row.sectionLine:Hide()
    row.check:Hide()
    row.check.mark:Hide()
    row.icon:SetTexture(nil)
    row.icon:Hide()
    row.text:SetText("")
    row.text:SetFont(FONT, 12, "")
    row.text:SetTextColor(rgb(COLOR.text))
    row.text:SetPoint("LEFT", 54, 0)
    row.text:SetPoint("RIGHT", -300, 0)
    row.autoPill:Hide()
    row.pill:Hide()
    row.value:SetText("")
    row.value:SetTextColor(rgb(COLOR.text))
    row.value2:SetText("")
end

function UI:AddHeaderRow(index, text)
    local row = self:AcquireRow(index)
    resetRow(row)
    row.isHeader = true
    row:SetHeight(SECTION_HEIGHT)
    row.zebraTex:Hide()
    row.sectionLine:Show()
    row.text:SetFont(FONT, 13, "")
    row.text:SetTextColor(rgb(COLOR.accent))
    row.text:SetText(text)
    row.text:SetPoint("LEFT", 4, -3)
    return row
end

function UI:AddDataRow(index, zebra)
    local row = self:AcquireRow(index)
    resetRow(row)
    if zebra ~= nil and zebra % 2 == 0 then
        row.zebraTex:Hide()
    end
    return row
end

function UI:LayoutRows(count)
    local content = self.frame.content
    local y = 0
    for index = 1, count do
        local row = self.rows[index]
        row:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -y)
        row:SetPoint("TOPRIGHT", content, "TOPRIGHT", 0, -y)
        y = y + row:GetHeight()
    end
    for index = count + 1, #self.rows do
        self.rows[index]:Hide()
    end
    content:SetHeight(math.max(y + 8, 100))
end

-- ---------------------------------------------------------------------------
-- Heute
-- ---------------------------------------------------------------------------

function UI:RenderToday()
    local Prices = GCP.Prices
    local plan = GCP.Roadmap:Generate()
    local index, zebra = 0, 0
    local lastCategory
    for _, entry in ipairs(plan.entries) do
        if entry.category ~= lastCategory then
            index = index + 1
            self:AddHeaderRow(index, entry.category)
            lastCategory = entry.category
            zebra = 0
        end
        index = index + 1
        zebra = zebra + 1
        local row = self:AddDataRow(index, zebra)
        row.data = {
            roadmapKey = entry.key,
            checked = entry.done,
            autoDone = entry.autoDone,
        }
        row.check:Show()
        row.check.mark:SetShown(entry.done)
        row.check.mark:SetDesaturated(false)
        if entry.done then
            row.text:SetTextColor(rgb(COLOR.textDim))
        end
        row.text:SetText(entry.text)
        if entry.autoDone then
            row.autoPill:Set("automatisch erkannt", COLOR.accent)
        end
        if entry.value then
            local color = entry.done and COLOR.textDim or COLOR.green
            row.value:SetTextColor(rgb(color))
            row.value:SetText(Prices:FormatGold(entry.value))
        end
    end
    if index == 0 then
        index = 1
        local row = self:AddDataRow(index)
        row.text:SetText("Keine Vorschläge – fehlt die Preisbasis? Im AH einen Auctionator-Scan starten.")
    end
    self.frame.summary:SetText(string.format(
        "Offen: |cff59cc59%s|r   ·   Erledigt: |cff9d9d9d%s|r",
        Prices:FormatGold(plan.openValue), Prices:FormatGold(plan.doneValue)))

    self.frame.progressLabel:SetText(string.format("%d/%d", plan.doneCount, plan.totalCount))
    local fraction = plan.totalCount > 0 and (plan.doneCount / plan.totalCount) or 0
    self.frame.progress.fill:SetWidth(math.max(1, 158 * fraction))
    self.frame.progressLabel:Show()
    self.frame.progress:Show()
    self:LayoutRows(index)
end

-- ---------------------------------------------------------------------------
-- Verkaufen
-- ---------------------------------------------------------------------------

function UI:RenderSell()
    local Prices = GCP.Prices
    local report = GCP.Advisor:BuildReport(self.scope, self.filter, self.showIgnored)
    local index, zebra = 0, 0

    if self.showIgnored then
        index = index + 1
        self:AddHeaderRow(index, "Ignorierte Items – Doppelklick holt sie zurück")
    end

    for _, item in ipairs(report.rows) do
        index = index + 1
        zebra = zebra + 1
        local row = self:AddDataRow(index, zebra)
        local sourcesText = {}
        for label, count in pairs(item.sources or {}) do
            sourcesText[#sourcesText + 1] = string.format("%s ×%d", label, count)
        end
        table.sort(sourcesText)
        local breakdown = {
            string.format("Bester Kanal: %s – %s je Stück",
                item.channel, Prices:FormatMoney(item.unitValue)),
        }
        if item.marketUnit then
            breakdown[#breakdown + 1] = string.format("AH (%s): %s brutto » %s nach 5 %% Gebühr",
                item.marketSource or "?", Prices:FormatMoney(item.marketUnit),
                Prices:FormatMoney(Prices:NetAuction(item.marketUnit)))
        end
        if item.vendorUnit then
            breakdown[#breakdown + 1] = "Händler: " .. Prices:FormatMoney(item.vendorUnit)
        end
        if item.disenchantUnit then
            breakdown[#breakdown + 1] = "Entzaubern: ≈ " .. Prices:FormatMoney(item.disenchantUnit)
        end
        if #sourcesText > 0 then
            breakdown[#breakdown + 1] = "Lagerorte: " .. table.concat(sourcesText, ", ")
        end
        breakdown[#breakdown + 1] = "Doppelklick: Item ausblenden · Shift-Klick: in den Chat verlinken"
        row.data = {
            itemID = item.itemID,
            link = item.link,
            breakdown = breakdown,
            ignorable = item.itemID,
        }
        if item.icon then
            row.icon:SetTexture(item.icon)
            row.icon:Show()
        end
        local color = qualityColors[item.quality or 1] or "|cffffffff"
        row.text:SetText(string.format("%s%s|r  |cff8a8a94×%d|r",
            color, item.name or ("Item " .. item.itemID), item.count))
        row.pill:Set(item.channel, channelColor[item.channel])
        if item.bound then
            row.autoPill:Set("gebunden", COLOR.textDim)
        end
        row.value:SetText(Prices:FormatGold(item.totalValue))
    end
    if index == 0 or (self.showIgnored and index == 1) then
        index = index + 1
        local row = self:AddDataRow(index)
        row.text:SetText(self.showIgnored
            and "Keine ignorierten Items."
            or "Nichts gefunden – anderer Filter, oder erst ein Auctionator-Scan?")
    end

    local scopeText = report.accountWide and "Account" or "Taschen"
    local hint = report.missingPrice > 0
        and string.format("   ·   |cff8a8a94%d ohne Marktpreis|r", report.missingPrice) or ""
    self.frame.summary:SetText(string.format(
        "Gesamtwert (%s): |cff59cc59%s|r%s",
        scopeText, Prices:FormatGold(report.totalValue), hint))
    self.frame.ignoredButton:SetLabel(string.format("Ignoriert (%d)", report.ignoredCount))
    self.frame.ignoredButton:SetActive(self.showIgnored)
    self:LayoutRows(index)
end

-- ---------------------------------------------------------------------------
-- Flips
-- ---------------------------------------------------------------------------

function UI:RenderFlips()
    local Prices = GCP.Prices
    local C = GCP.Constants
    local flips = GCP.Flips:Build()
    local threshold = (GCP.db.options.minRoadmapValue) or 0
    local hidden = 0
    local index, zebra = 0, 0

    index = index + 1
    self:AddHeaderRow(index, "Motes » Ur-Partikel  (10:1, Kombinieren ist endgültig)")
    zebra = 0
    for _, row in ipairs(flips.motes) do
        local relevant = math.max(row.buyProfit, row.combineDelta * math.max(row.ownedCombines, 1))
        if relevant >= threshold or row.ownedMotes > 0 then
            index = index + 1
            zebra = zebra + 1
            local line = self:AddDataRow(index, zebra)
            line.data = { itemID = row.primalID }
            if row.icon then
                line.icon:SetTexture(row.icon)
                line.icon:Show()
            end
            line.text:SetText(string.format("%s  |cff8a8a94Mote %s · Partikel %s|r",
                row.name or "?", Prices:FormatGold(row.motePrice),
                Prices:FormatGold(row.primalPrice)))
            if row.ownedMotes > 0 then
                line.autoPill:Set(string.format("%d Motes", row.ownedMotes), COLOR.accent)
            end
            line.pill:Set(row.combineDelta > 0 and "kombinieren" or "einzeln verkaufen",
                row.combineDelta > 0 and COLOR.green or COLOR.textDim)
            line.value2:SetText("Kauf-Flip")
            local profitColor = row.buyProfit > 0 and COLOR.green or COLOR.red
            line.value:SetTextColor(rgb(profitColor))
            line.value:SetText(Prices:FormatGold(row.buyProfit))
        else
            hidden = hidden + 1
        end
    end
    if #flips.motes == 0 then
        index = index + 1
        self:AddDataRow(index).text:SetText("Keine Mote-Preise vorhanden – Auctionator-Scan nötig.")
    end

    index = index + 1
    self:AddHeaderRow(index, "Essenzen 3:1  (benötigt Verzauberkunst)")
    zebra = 0
    for _, row in ipairs(flips.essences) do
        if row.profit >= threshold then
            index = index + 1
            zebra = zebra + 1
            local line = self:AddDataRow(index, zebra)
            line.data = { itemID = row.greaterID }
            if row.icon then
                line.icon:SetTexture(row.icon)
                line.icon:Show()
            end
            line.text:SetText(string.format("%s  |cff8a8a94niedere %s · hohe %s|r",
                row.name or "?", Prices:FormatGold(row.lesserPrice),
                Prices:FormatGold(row.greaterPrice)))
            line.pill:Set(row.direction == "up" and "3 niedere » 1 hohe" or "1 hohe » 3 niedere",
                COLOR.textDim)
            local profitColor = row.profit > 0 and COLOR.green or COLOR.red
            line.value:SetTextColor(rgb(profitColor))
            line.value:SetText(Prices:FormatGold(row.profit))
        else
            hidden = hidden + 1
        end
    end
    if #flips.essences == 0 then
        index = index + 1
        self:AddDataRow(index).text:SetText("Keine Essenz-Preise vorhanden – Auctionator-Scan nötig.")
    end

    local hiddenText = hidden > 0
        and string.format("   ·   |cff8a8a94%d unter Mindestgewinn (%s) ausgeblendet|r",
            hidden, Prices:FormatGold(threshold)) or ""
    self.frame.summary:SetText(
        "Kauf-Flip: Zutaten im AH kaufen, Ergebnis mit Gewinn einstellen. Alle Werte nach 5 % Gebühr."
        .. hiddenText)
    self:LayoutRows(index)
end

-- ---------------------------------------------------------------------------
-- Crafts
-- ---------------------------------------------------------------------------

function UI:RenderCrafts()
    local Prices = GCP.Prices
    local report = GCP.Crafts:BuildReport()
    local threshold = (GCP.db.options.minRoadmapValue) or 0
    local index, zebra = 0, 0
    local hidden = 0

    if #report.professions == 0 then
        index = index + 1
        local row = self:AddDataRow(index)
        row.text:SetText("Noch keine Rezepte bekannt – öffne einmal jedes Berufsfenster, Gold Copilot merkt sie sich dauerhaft.")
        self.frame.summary:SetText("Craft-Radar: Erlös netto (nach 5 % Gebühr) minus Zutaten zum Marktpreis.")
        self:LayoutRows(index)
        return
    end

    index = index + 1
    self:AddHeaderRow(index, "Profitable Rezepte  (Erlös netto − Zutaten zum Marktpreis)")
    local shown = 0
    for _, row in ipairs(report.rows) do
        if shown >= 60 then break end
        local passes = row.profit >= math.max(threshold, 1)
            and (not self.onlyCraftable or row.craftable > 0)
        if passes then
            shown = shown + 1
            index = index + 1
            zebra = zebra + 1
            local line = self:AddDataRow(index, zebra)
            line.data = {
                itemID = row.product,
                breakdown = {
                    string.format("Beruf: %s", row.profession),
                    string.format("Zutaten: %s", Prices:FormatMoney(row.matCost)),
                    string.format("Erlös netto (×%.1f): %s", row.numMade, Prices:FormatMoney(row.revenue)),
                    row.hasCooldown and "Achtung: Rezept mit Cooldown" or nil,
                },
            }
            local color = qualityColors[row.quality or 1] or "|cffffffff"
            if row.icon then
                line.icon:SetTexture(row.icon)
                line.icon:Show()
            end
            line.text:SetText(string.format("%s%s|r  |cff8a8a94%s|r",
                color, row.name, row.profession))
            if row.craftable > 0 then
                line.autoPill:Set(string.format("×%d machbar", row.craftable), COLOR.accent)
            end
            if row.hasCooldown then
                line.pill:Set("Cooldown", COLOR.textDim)
            end
            line.value2:SetText(string.format("Mats %s", Prices:FormatGold(row.matCost)))
            line.value:SetTextColor(rgb(COLOR.green))
            line.value:SetText("+" .. Prices:FormatGold(row.profit))
        elseif row.profit > 0 then
            hidden = hidden + 1
        end
    end
    if shown == 0 then
        index = index + 1
        self:AddDataRow(index).text:SetText("Kein Rezept über dem Mindestgewinn – Schwelle in den Optionen senken?")
    end

    local parts = {}
    for _, profession in ipairs(report.professions) do
        parts[#parts + 1] = string.format("%s (%d)", profession.name, profession.count)
    end
    local hiddenText = hidden > 0
        and string.format("   ·   |cff8a8a94%d weitere unter Schwelle|r", hidden) or ""
    self.frame.summary:SetText("Gescannt: " .. table.concat(parts, ", ") .. hiddenText)
    self.frame.craftableButton:SetLabel(self.onlyCraftable and "Nur machbare: an" or "Nur machbare: aus")
    self.frame.craftableButton:SetActive(self.onlyCraftable)
    self:LayoutRows(index)
end

-- ---------------------------------------------------------------------------
-- Optionen
-- ---------------------------------------------------------------------------

local function optionHeading(panel, text, anchor, offsetY)
    local heading = createText(panel, 13, COLOR.accent)
    heading:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, offsetY or -18)
    heading:SetText(text)
    return heading
end

function UI:BuildOptionsPanel(frame)
    local panel = CreateFrame("Frame", nil, frame)

    local sourceHeading = createText(panel, 13, COLOR.accent)
    sourceHeading:SetPoint("TOPLEFT", 4, -6)
    sourceHeading:SetText("Preisquelle")

    panel.sourceButtons = {}
    local sourceDefs = {
        { key = "auto", label = "Automatisch" },
        { key = "auctionator", label = "Nur Auctionator" },
        { key = "tsm", label = "Nur TSM" },
    }
    local previous
    for _, def in ipairs(sourceDefs) do
        local button = createFlatButton(panel, def.label, 150, 24)
        if previous then
            button:SetPoint("LEFT", previous, "RIGHT", 6, 0)
        else
            button:SetPoint("TOPLEFT", sourceHeading, "BOTTOMLEFT", 0, -8)
        end
        button:SetScript("OnClick", function()
            GCP.db.options.priceSource = def.key
            UI:Refresh()
        end)
        panel.sourceButtons[def.key] = button
        previous = button
    end

    local sourceNote = createText(panel, 11, COLOR.textDim)
    sourceNote:SetPoint("TOPLEFT", panel.sourceButtons.auto, "BOTTOMLEFT", 0, -6)
    sourceNote:SetJustifyH("LEFT")
    sourceNote:SetText("Automatisch: erst Auctionator-Scanpreis dieses Realms, dann TSM dbmarket.")

    local minHeading = optionHeading(panel, "Mindestgewinn für Vorschläge", sourceNote, -20)
    panel.minButtons = {}
    local minDefs = {
        { value = 0, label = "aus" },
        { value = 10000, label = "1 g" },
        { value = 50000, label = "5 g" },
        { value = 100000, label = "10 g" },
        { value = 250000, label = "25 g" },
    }
    previous = nil
    for _, def in ipairs(minDefs) do
        local button = createFlatButton(panel, def.label, 76, 24)
        if previous then
            button:SetPoint("LEFT", previous, "RIGHT", 6, 0)
        else
            button:SetPoint("TOPLEFT", minHeading, "BOTTOMLEFT", 0, -8)
        end
        button:SetScript("OnClick", function()
            GCP.db.options.minRoadmapValue = def.value
            UI:Refresh()
        end)
        panel.minButtons[def.value] = button
        previous = button
    end

    local minNote = createText(panel, 11, COLOR.textDim)
    minNote:SetPoint("TOPLEFT", panel.minButtons[0], "BOTTOMLEFT", 0, -6)
    minNote:SetText("Gilt für Tagesplan, Flips und Craft-Radar. Daily-Quests sind sicheres Gold und immer sichtbar.")

    local dataHeading = optionHeading(panel, "Daten", minNote, -20)
    panel.dataText = createText(panel, 11, COLOR.textDim)
    panel.dataText:SetPoint("TOPLEFT", dataHeading, "BOTTOMLEFT", 0, -8)
    panel.dataText:SetJustifyH("LEFT")
    panel.dataText:SetSpacing(3)

    panel.clearIgnored = createFlatButton(panel, "Ignorierte Items zurücksetzen", 220, 24)
    panel.clearIgnored:SetPoint("TOPLEFT", panel.dataText, "BOTTOMLEFT", 0, -10)
    panel.clearIgnored:SetScript("OnClick", function()
        GCP.db.options.ignored = {}
        UI:Refresh()
    end)

    local mathHeading = optionHeading(panel, "So wird gerechnet", panel.clearIgnored, -20)
    local mathText = createText(panel, 11, COLOR.textDim)
    mathText:SetPoint("TOPLEFT", mathHeading, "BOTTOMLEFT", 0, -8)
    mathText:SetJustifyH("LEFT")
    mathText:SetSpacing(3)
    mathText:SetText(table.concat({
        "· AH-Erlöse sind immer netto: 5 % Auktionshausgebühr abgezogen.",
        "· Einzahlung (Deposit) wird bei erfolgreichem Verkauf erstattet und daher nicht abgezogen.",
        "· Empfehlungen rechnen mit dem 7-Tage-Median deiner beobachteten Preise – eine einzelne",
        "  Dumping-Auktion verschiebt den Plan nicht. Der Verkaufen-Tab zeigt den aktuellen Scanpreis.",
        "· Craft-Ausbeute bei Zufallsmenge: Mittelwert aus Minimum und Maximum.",
        "· Zutaten zählen zum Marktpreis, auch wenn du sie besitzt (sie hätten verkauft werden können).",
        "· Farm-Tipps: Marktpreis × konservativ geschätzte Sammelrate pro Stunde.",
    }, "\n"))

    return panel
end

function UI:RenderOptions()
    local panel = self.frame.optionsPanel
    local options = GCP.db.options
    for key, button in pairs(panel.sourceButtons) do
        button:SetActive(options.priceSource == key)
    end
    for value, button in pairs(panel.minButtons) do
        button:SetActive(options.minRoadmapValue == value)
    end
    local ignoredCount = 0
    for _ in pairs(options.ignored or {}) do ignoredCount = ignoredCount + 1 end
    local professionCount, recipeCount = 0, 0
    for _, data in pairs(GCP.db.recipes or {}) do
        professionCount = professionCount + 1
        recipeCount = recipeCount + #(data.list or {})
    end
    local observedCount = 0
    for _ in pairs(GCP.db.priceHistory or {}) do observedCount = observedCount + 1 end
    panel.dataText:SetText(table.concat({
        string.format("Rezepte: %d aus %d Beruf(en) – Berufsfenster öffnen aktualisiert sie.",
            recipeCount, professionCount),
        string.format("Preisverlauf: %d Items in Beobachtung (14 Tage).", observedCount),
        string.format("Ignorierte Items: %d.", ignoredCount),
    }, "\n"))
    self.frame.summary:SetText("Einstellungen wirken sofort und werden pro Account gespeichert.")
end

-- ---------------------------------------------------------------------------
-- Steuerung
-- ---------------------------------------------------------------------------

function UI:SelectTab(key)
    self.activeTab = key
    self:Refresh()
end

function UI:RefreshIfShown()
    if self.frame and self.frame:IsShown() then
        self:Refresh()
    end
end

function UI:Refresh()
    local frame = self:EnsureFrame()
    for tabKey, tab in pairs(frame.tabs) do
        tab:SetActive(tabKey == self.activeTab)
    end

    local isSell = self.activeTab == "sell"
    local isCrafts = self.activeTab == "crafts"
    local isOptions = self.activeTab == "options"
    frame.toolbar:SetShown(isSell or isCrafts)
    frame.scopeButton:SetShown(isSell)
    frame.filterButton:SetShown(isSell)
    frame.boundButton:SetShown(isSell)
    frame.ignoredButton:SetShown(isSell)
    frame.craftableButton:SetShown(isCrafts)
    frame.refreshButton:Show()
    frame.progress:Hide()
    frame.progressLabel:Hide()
    frame.scroll:SetShown(not isOptions)
    frame.optionsPanel:SetShown(isOptions)

    if isSell then
        frame.scopeButton:SetLabel(self.scope == "account" and "Umfang: Account" or "Umfang: Taschen")
        local filterLabels = { all = "Filter: Alles", mats = "Filter: Mats", gear = "Filter: Ausrüstung" }
        frame.filterButton:SetLabel(filterLabels[self.filter or "all"])
        frame.boundButton:SetLabel(GCP.db.options.hideBound and "Gebundenes: aus" or "Gebundenes: an")
        frame.boundButton:SetActive(GCP.db.options.hideBound)
    end

    frame.source:SetText("Preise: " .. GCP.Prices:GetActiveSourceLabel())

    local trendDelta = GCP.Roadmap:GetGoldTrend()
    if trendDelta then
        local color = trendDelta >= 0 and "|cff59cc59" or "|cffe05c5c"
        local sign = trendDelta >= 0 and "+" or ""
        frame.trend:SetText(string.format("Gold, 7 Tage: %s%s%s|r  ·  Konto gesamt: %s",
            color, sign, GCP.Prices:FormatGold(trendDelta),
            GCP.Prices:FormatGold(GCP.db.goldHistory[GCP:Today()] or 0)))
    else
        frame.trend:SetText("Goldverlauf entsteht ab morgen – einfach täglich einloggen.")
    end

    if self.activeTab == "today" then
        self:RenderToday()
    elseif isSell then
        self:RenderSell()
    elseif self.activeTab == "flips" then
        self:RenderFlips()
    elseif isCrafts then
        self:RenderCrafts()
    else
        self:RenderOptions()
    end
end

function UI:Toggle()
    local frame = self:EnsureFrame()
    if frame:IsShown() then
        frame:Hide()
    else
        frame:Show()
    end
end
