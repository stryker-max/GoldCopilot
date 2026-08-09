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
local FRAME_WIDTH = 900
local FRAME_HEIGHT = 640

-- Der Markt-Tab braucht fuenf Zahlenspalten statt der zwei, die eine normale
-- Zeile hat. Breiten von rechts nach links: Perzentil, 30T, 7T, Jetzt - der
-- Score sitzt ganz rechts in row.value.
local MARKET_COLUMNS = { 62, 86, 86, 86 }
local MARKET_SCORE_WIDTH = 46
local MARKET_ROW_LIMIT = 120

-- Chancen-Tab. Der Score steht hier links statt rechts: Er ist die Sortierung
-- und damit das Erste, was gelesen wird. Rechts stehen die Zahlen, auf die es
-- danach ankommt - von rechts nach links Liquidität (0.8.0), ROI, Profit,
-- Kapital. Gelesen wird die Zeile damit als "so viel kostet es, so viel bringt
-- es, so effizient ist es, so schnell komme ich wieder raus".
local OPPORTUNITY_COLUMNS = { 58, 66, 86, 86 }
local OPPORTUNITY_SCORE_WIDTH = 30
local OPPORTUNITY_TYPE_WIDTH = 92

-- Zukunft-Tab (0.7.0). Von rechts nach links: Catalyst, Hype, Demand, Markt -
-- das Signal sitzt wie im Markt-Tab ganz rechts in row.value. Die
-- Catalyst-Spalte ist die einzige mit Text statt Zahl und deshalb breiter.
local FUTURE_COLUMNS = { 108, 56, 56, 56 }
local FUTURE_SCORE_WIDTH = 46

-- Handel-Tab (0.8.0). Von rechts nach links: reale Marge, Zeit bis Verkauf,
-- Sell-through, abgelaufen, verkauft - der Liquidity Score sitzt wie im
-- Markt-Tab ganz rechts in row.value. Fuenf Zahlenspalten sind die breiteste
-- Zeile des Addons; darunter bleibt genug Platz fuer den Itemnamen.
local LEDGER_COLUMNS = { 70, 62, 78, 62, 58 }
local LEDGER_SCORE_WIDTH = 46
local LEDGER_ROW_LIMIT = 80

-- Der Zeilen-Pool legt so viele Zahlenspalten an, wie der breiteste Tab
-- braucht. Sonst greift ein Tab mit einer Spalte mehr ins Leere, sobald jemand
-- eine ergaenzt.
local MAX_COLUMNS = math.max(#MARKET_COLUMNS, #OPPORTUNITY_COLUMNS,
    #FUTURE_COLUMNS, #LEDGER_COLUMNS)

-- Hoehe des Optionen-Inhalts. Er ist laenger als das Fenster und liegt deshalb
-- in einem eigenen Scrollbereich; die Zahl muss nur groesser sein als der
-- Inhalt, nicht exakt.
local OPTIONS_PANEL_HEIGHT = 1020

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
    -- Das eigene Logo liegt als TGA nur vor, wenn es jemand erzeugt hat
    -- (siehe Media/LIES-MICH.txt). Fehlt es, wuerde hier eine leere Flaeche
    -- stehen - deshalb liegt darunter ein Muenz-Icon des Spiels, das immer da
    -- ist, und das eigene Logo deckt es ab, sobald es existiert.
    local logoFallback = frame:CreateTexture(nil, "ARTWORK")
    logoFallback:SetSize(30, 30)
    logoFallback:SetPoint("TOPLEFT", 16, -12)
    logoFallback:SetTexture("Interface\\Icons\\INV_Misc_Coin_02")
    logoFallback:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    local logo = frame:CreateTexture(nil, "OVERLAY")
    logo:SetSize(36, 36)
    logo:SetPoint("CENTER", logoFallback, "CENTER", 0, 0)
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
        { key = "market", label = "Markt" },
        { key = "chancen", label = "Chancen" },
        { key = "zukunft", label = "Zukunft" },
        { key = "handel", label = "Handel" },
        { key = "options", label = "Optionen" },
    }
    -- Neun Tabs passen nur schmaler in die Leiste: 14 Rand + 9 x 93 + 8 x 4
    -- Abstand bleiben unter der Fensterbreite.
    local previous
    for _, def in ipairs(tabDefs) do
        local tab = createFlatButton(frame, def.label, 93, 26)
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

    -- Beobachtung: zeigt die Groesse der Watchlist und schaltet die Ansicht auf
    -- genau diese Items um. Aufgenommen wird per Rechtsklick auf eine Zeile.
    frame.watchButton = createFlatButton(toolbar, "Beobachtung (0)", 160, 22)
    frame.watchButton:SetPoint("LEFT")
    frame.watchButton:SetScript("OnClick", function()
        UI.onlyWatched = not UI.onlyWatched
        UI:Refresh()
    end)

    -- Sortierung (0.8.0). Zwei getrennte Knoepfe, weil es zwei getrennte Listen
    -- mit verschiedenen Kriterien sind - ein gemeinsamer waere im jeweils
    -- anderen Tab beschriftet, aber wirkungslos.
    frame.opportunitySortButton = createFlatButton(toolbar, "Sortierung", 210, 22)
    frame.opportunitySortButton:SetPoint("LEFT", frame.watchButton, "RIGHT", 4, 0)
    frame.opportunitySortButton:SetScript("OnClick", function()
        GCP.Opportunity:CycleSortMode()
        GCP.Opportunity:Invalidate()
        UI:Refresh()
    end)

    frame.ledgerSortButton = createFlatButton(toolbar, "Sortierung", 210, 22)
    frame.ledgerSortButton:SetPoint("LEFT")
    frame.ledgerSortButton:SetScript("OnClick", function()
        local order = { liquidity = "profit", profit = "sales", sales = "liquidity" }
        GCP.db.options.ledgerSort = order[GCP.db.options.ledgerSort or "liquidity"]
            or "liquidity"
        UI:Refresh()
    end)

    frame.refreshButton = createFlatButton(toolbar, "Aktualisieren", 110, 22)
    frame.refreshButton:SetPoint("RIGHT")
    frame.refreshButton:SetScript("OnClick", function()
        GCP.Prices:RecordObservedPrices()
        -- Ein Klick ist keine Flut: hier darf sofort geschrieben werden, das
        -- 30-Minuten-Fenster je Item bleibt trotzdem gueltig.
        GCP.Market:RecordSnapshots("Aktualisieren", true)
        -- Wer ausdruecklich aktualisiert, meint auch die Chancenliste - und nur
        -- hier wird ihr kurzer Cache von Hand verworfen.
        GCP.Opportunity:Invalidate()
        GCP.Future:Invalidate()
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
    content:SetSize(FRAME_WIDTH - 48, 100)
    scroll:SetScrollChild(content)
    frame.scroll = scroll
    frame.content = content

    -- Optionen als eigenes Panel statt Zeilenliste. Seit 0.6.0 in einem
    -- eigenen Scrollbereich: Mit den Chancen-Filtern reicht die Fensterhoehe
    -- nicht mehr fuer alle Abschnitte, und ein abgeschnittener Erklaertext ist
    -- schlimmer als eine Bildlaufleiste.
    local optionsScroll = CreateFrame("ScrollFrame", "GoldCopilotOptionsScrollFrame",
        frame, "UIPanelScrollFrameTemplate")
    optionsScroll:SetPoint("TOPLEFT", 14, -142)
    optionsScroll:SetPoint("BOTTOMRIGHT", -30, 14)
    frame.optionsPanel = self:BuildOptionsPanel(optionsScroll)
    frame.optionsPanel:SetSize(FRAME_WIDTH - 48, OPTIONS_PANEL_HEIGHT)
    optionsScroll:SetScrollChild(frame.optionsPanel)
    optionsScroll:Hide()
    frame.optionsScroll = optionsScroll

    -- GetItemInfo liefert asynchron nach, und die Selbsterkennung soll ohne
    -- Fensterwechsel greifen: Wer eine Daily abgibt oder etwas verkauft,
    -- sieht den Haken sofort. Alle Ereignisse laufen in denselben
    -- gebuendelten Refresh, damit ein Loot-Schwall nicht zwanzigmal rechnet.
    frame:RegisterEvent("GET_ITEM_INFO_RECEIVED")
    frame:RegisterEvent("QUEST_TURNED_IN")
    frame:RegisterEvent("QUEST_LOG_UPDATE")
    frame:RegisterEvent("BAG_UPDATE_DELAYED")
    frame:RegisterEvent("SPELL_UPDATE_COOLDOWN")
    frame:SetScript("OnEvent", function()
        if frame:IsShown() and not UI.pendingRefresh then
            UI.pendingRefresh = true
            C_Timer.After(1.5, function()
                UI.pendingRefresh = false
                -- Im Kampf wird nicht neu gerechnet: Der Plan interessiert
                -- dort niemanden, ein voller Bestandsscan aber schon.
                if frame:IsShown() and not (InCombatLockdown and InCombatLockdown()) then
                    UI:Refresh()
                end
            end)
        end
    end)
    frame:SetScript("OnShow", function()
        GCP:RecordGold()
        GCP.Prices:RecordObservedPrices()
        -- Gedrosselt ueber den gemeinsamen Debounce: Wer das Fenster fuenfmal
        -- auf- und zumacht, loest keine fuenf Durchlaeufe aus.
        GCP.Market:OnDatabaseUpdate("Fenster geöffnet")
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

-- Der Tooltip zeigt das Item, sofern es eines gibt, und darunter die Rechnung.
-- Bis 0.3.0 hing er komplett an Item oder Link - Tagesplanzeilen ohne Item
-- (Dailies, Quests, Zielplan) hatten damit eine Erklaerung, die nie erschien.
local function rowOnEnter(row)
    row.hoverTex:Show()
    local data = row.data
    if not data then return end
    local hasBreakdown = data.breakdown and #data.breakdown > 0
    if not (data.link or data.itemID or hasBreakdown) then return end

    GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
    local shown = false
    if data.link then
        shown = pcall(GameTooltip.SetHyperlink, GameTooltip, data.link)
    elseif data.itemID then
        shown = pcall(GameTooltip.SetItemByID, GameTooltip, data.itemID)
    end
    if hasBreakdown then
        if shown then
            GameTooltip:AddLine(" ")
        elseif data.title then
            GameTooltip:AddLine(data.title, 1, 1, 1, true)
        end
        for _, line in ipairs(data.breakdown) do
            GameTooltip:AddLine(line, 0.9, 0.9, 0.9, true)
        end
    end
    GameTooltip:Show()
end

local function rowOnLeave(row)
    row.hoverTex:Hide()
    GameTooltip:Hide()
end

-- Der Doppelklick wird selbst erkannt statt ueber OnDoubleClick: Ob dieses
-- Skript feuert, haengt an der Klick-Registrierung des Knopfes und ist je
-- nach Clientfassung verschieden - der Zeitvergleich funktioniert immer.
local DOUBLE_CLICK_SECONDS = 0.5

local function rowOnClick(row, mouseButton)
    local data = row.data
    if not data then return end

    if mouseButton == "LeftButton" and IsShiftKeyDown() and data.link and ChatEdit_InsertLink then
        ChatEdit_InsertLink(data.link)
        return
    end

    -- Markt- und Chancen-Zeilen haben nichts zum Ausblenden, dafuer etwas zum
    -- Beobachten: Ein Rechtsklick nimmt das Item in die Watchlist auf oder
    -- wieder heraus.
    if data.watchable and mouseButton == "RightButton" then
        -- watchMeta traegt die optionalen Zusatzfelder aus 0.7.0 (Phase, These,
        -- Wunsch-Einstieg). Die anderen Tabs uebergeben schlicht nichts.
        GCP.Market:ToggleWatchItem(data.watchable, data.watchReason or "manuell",
            data.watchMeta)
        UI:Refresh()
        return
    end

    if not data.ignorable then return end

    local now = GetTime()
    local isSecondClick = row.lastClickAt
        and row.lastClickItem == data.ignorable
        and (now - row.lastClickAt) <= DOUBLE_CLICK_SECONDS
    if mouseButton == "RightButton" or isSecondClick then
        row.lastClickAt = nil
        row.lastClickItem = nil
        GCP.Advisor:ToggleIgnored(data.ignorable)
        UI:Refresh()
        return
    end
    row.lastClickAt = now
    row.lastClickItem = data.ignorable
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
    row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    row:SetScript("OnEnter", rowOnEnter)
    row:SetScript("OnLeave", rowOnLeave)
    row:SetScript("OnClick", rowOnClick)

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
    row.pill = createPill(row)

    row.value2 = createText(row, 11, COLOR.textDim)
    row.value2:SetJustifyH("RIGHT")

    row.value = createText(row, 13, COLOR.text, true)
    row.value:SetJustifyH("RIGHT")

    -- Zusatzspalten des Markt-Tabs. Sie kosten vier Fontstrings je Zeile und
    -- bleiben in allen anderen Tabs schlicht leer.
    row.cols = {}
    for column = 1, MAX_COLUMNS do
        local text = createText(row, 12, COLOR.textDim, true)
        text:SetJustifyH("RIGHT")
        row.cols[column] = text
    end

    -- Linke Textspalte des Chancen-Tabs (die Art der Chance). In allen anderen
    -- Tabs bleibt sie leer.
    row.typeText = createText(row, 11, COLOR.textDim)
    row.typeText:SetJustifyH("LEFT")
    row.typeText:SetWordWrap(false)

    self.rows[index] = row
    return row
end

local function resetRow(row)
    row.data = nil
    row.isHeader = false
    row.textLeft = 54
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
    row.autoPill:Hide()
    row.pill:Hide()
    row.value:SetText("")
    row.value:SetTextColor(rgb(COLOR.text))
    row.value:SetJustifyH("RIGHT")
    -- Breite 0 heisst "so breit wie der Text". Ohne das behielte eine Zeile die
    -- feste Spaltenbreite des Markt- oder Chancen-Tabs, sobald der Zeilen-Pool
    -- sie im naechsten Tab wiederverwendet - und schnitte dort den Betrag ab.
    row.value:SetWidth(0)
    row.value2:SetText("")
    row.typeText:SetText("")
    row.typeText:SetFont(FONT, 11, "")
    row.typeText:SetTextColor(rgb(COLOR.textDim))
    for column = 1, MAX_COLUMNS do
        row.cols[column]:SetText("")
        row.cols[column]:SetFont(FONT_NUM, 12, "")
        row.cols[column]:SetTextColor(rgb(COLOR.textDim))
    end
end

-- Die rechte Haelfte einer Zeile wird von rechts nach links gesetzt, und der
-- Text bekommt danach den ganzen Rest. Vorher standen hier feste Abstaende
-- (-280, -160, -84): Die haben dem Text auch dann 300 Pixel weggenommen,
-- wenn rechts gar nichts stand - daher die abgeschnittenen Zeilen.
local function finishRow(row)
    local used = 8
    row.value:ClearAllPoints()
    row.value:SetPoint("RIGHT", -8, 0)
    local valueText = row.value:GetText()
    if valueText and valueText ~= "" then
        used = used + row.value:GetStringWidth() + 12
    end

    local noteText = row.value2:GetText()
    if noteText and noteText ~= "" then
        row.value2:ClearAllPoints()
        row.value2:SetPoint("RIGHT", -used, 0)
        used = used + row.value2:GetStringWidth() + 12
    end

    if row.pill:IsShown() then
        row.pill:ClearAllPoints()
        row.pill:SetPoint("RIGHT", -used, 0)
        used = used + row.pill:GetWidth() + 10
    end

    if row.autoPill:IsShown() then
        row.autoPill:ClearAllPoints()
        row.autoPill:SetPoint("RIGHT", -used, 0)
        used = used + row.autoPill:GetWidth() + 10
    end

    row.text:ClearAllPoints()
    row.text:SetPoint("LEFT", row.textLeft, row.isHeader and -3 or 0)
    row.text:SetPoint("RIGHT", -used, 0)
end

-- Zeilenabschluss des Markt-Tabs: feste Spaltenbreiten statt der sonst
-- inhaltsabhaengigen Ausrichtung, damit die Zahlen untereinander stehen.
local function finishMarketRow(row)
    local used = 8
    row.value:ClearAllPoints()
    row.value:SetPoint("RIGHT", -used, 0)
    row.value:SetWidth(MARKET_SCORE_WIDTH)
    used = used + MARKET_SCORE_WIDTH + 10
    for column = 1, #MARKET_COLUMNS do
        local text = row.cols[column]
        text:ClearAllPoints()
        text:SetPoint("RIGHT", -used, 0)
        text:SetWidth(MARKET_COLUMNS[column])
        used = used + MARKET_COLUMNS[column] + 10
    end
    -- Etiketten stehen links der Zahlenspalten; sie sind die einzigen Elemente
    -- hier mit inhaltsabhaengiger Breite, deshalb kommen sie zuletzt.
    if row.pill:IsShown() then
        row.pill:ClearAllPoints()
        row.pill:SetPoint("RIGHT", -used, 0)
        used = used + row.pill:GetWidth() + 10
    end
    if row.autoPill:IsShown() then
        row.autoPill:ClearAllPoints()
        row.autoPill:SetPoint("RIGHT", -used, 0)
        used = used + row.autoPill:GetWidth() + 10
    end
    row.text:ClearAllPoints()
    row.text:SetPoint("LEFT", row.textLeft, row.isHeader and -3 or 0)
    row.text:SetPoint("RIGHT", -used, 0)
end

-- Zeilenabschluss des Chancen-Tabs. Der Score sitzt links, danach Icon und
-- Art der Chance mit fester Breite; die Aktion bekommt den Rest, die drei
-- Zahlenspalten stehen rechts untereinander.
local function finishOpportunityRow(row)
    row.value:ClearAllPoints()
    row.value:SetPoint("LEFT", 8, 0)
    row.value:SetWidth(OPPORTUNITY_SCORE_WIDTH)
    row.value:SetJustifyH("LEFT")

    row.icon:ClearAllPoints()
    row.icon:SetPoint("LEFT", 46, 0)

    row.typeText:ClearAllPoints()
    row.typeText:SetPoint("LEFT", 72, row.isHeader and -3 or 0)
    row.typeText:SetWidth(OPPORTUNITY_TYPE_WIDTH)

    local used = 8
    for column = 1, #OPPORTUNITY_COLUMNS do
        local text = row.cols[column]
        text:ClearAllPoints()
        text:SetPoint("RIGHT", -used, 0)
        text:SetWidth(OPPORTUNITY_COLUMNS[column])
        used = used + OPPORTUNITY_COLUMNS[column] + 10
    end
    if row.pill:IsShown() then
        row.pill:ClearAllPoints()
        row.pill:SetPoint("RIGHT", -used, 0)
        used = used + row.pill:GetWidth() + 10
    end
    if row.autoPill:IsShown() then
        row.autoPill:ClearAllPoints()
        row.autoPill:SetPoint("RIGHT", -used, 0)
        used = used + row.autoPill:GetWidth() + 10
    end

    row.text:ClearAllPoints()
    row.text:SetPoint("LEFT", 72 + OPPORTUNITY_TYPE_WIDTH + 8, row.isHeader and -3 or 0)
    row.text:SetPoint("RIGHT", -used, 0)
end

-- Zeilenabschluss des Zukunft-Tabs. Wie im Markt-Tab feste Spaltenbreiten,
-- damit die drei Kennzahlen untereinander stehen und sich vergleichen lassen -
-- nur mit einer Textspalte fuer den Catalyst dazwischen.
local function finishFutureRow(row)
    local used = 8
    row.value:ClearAllPoints()
    row.value:SetPoint("RIGHT", -used, 0)
    row.value:SetWidth(FUTURE_SCORE_WIDTH)
    used = used + FUTURE_SCORE_WIDTH + 10
    for column = 1, #FUTURE_COLUMNS do
        local text = row.cols[column]
        text:ClearAllPoints()
        text:SetPoint("RIGHT", -used, 0)
        text:SetWidth(FUTURE_COLUMNS[column])
        used = used + FUTURE_COLUMNS[column] + 10
    end
    if row.pill:IsShown() then
        row.pill:ClearAllPoints()
        row.pill:SetPoint("RIGHT", -used, 0)
        used = used + row.pill:GetWidth() + 10
    end
    if row.autoPill:IsShown() then
        row.autoPill:ClearAllPoints()
        row.autoPill:SetPoint("RIGHT", -used, 0)
        used = used + row.autoPill:GetWidth() + 10
    end
    row.text:ClearAllPoints()
    row.text:SetPoint("LEFT", row.textLeft, row.isHeader and -3 or 0)
    row.text:SetPoint("RIGHT", -used, 0)
end

-- Zeilenabschluss des Handel-Tabs. Wie im Markt-Tab feste Spaltenbreiten - nur
-- mit fuenf Zahlenspalten statt vier, damit sich Sell-through, Verkaufszeit und
-- Marge zeilenweise vergleichen lassen.
local function finishLedgerRow(row)
    local used = 8
    row.value:ClearAllPoints()
    row.value:SetPoint("RIGHT", -used, 0)
    row.value:SetWidth(LEDGER_SCORE_WIDTH)
    used = used + LEDGER_SCORE_WIDTH + 10
    for column = 1, #LEDGER_COLUMNS do
        local text = row.cols[column]
        text:ClearAllPoints()
        text:SetPoint("RIGHT", -used, 0)
        text:SetWidth(LEDGER_COLUMNS[column])
        used = used + LEDGER_COLUMNS[column] + 10
    end
    if row.pill:IsShown() then
        row.pill:ClearAllPoints()
        row.pill:SetPoint("RIGHT", -used, 0)
        used = used + row.pill:GetWidth() + 10
    end
    if row.autoPill:IsShown() then
        row.autoPill:ClearAllPoints()
        row.autoPill:SetPoint("RIGHT", -used, 0)
        used = used + row.autoPill:GetWidth() + 10
    end
    row.text:ClearAllPoints()
    row.text:SetPoint("LEFT", row.textLeft, row.isHeader and -3 or 0)
    row.text:SetPoint("RIGHT", -used, 0)
end

function UI:AddHeaderRow(index, text, value)
    local row = self:AcquireRow(index)
    resetRow(row)
    row.isHeader = true
    row.textLeft = 4
    row:SetHeight(SECTION_HEIGHT)
    row.zebraTex:Hide()
    row.sectionLine:Show()
    row.text:SetFont(FONT, 13, "")
    row.text:SetTextColor(rgb(COLOR.accent))
    row.text:SetText(text)
    if value then
        row.value:SetFont(FONT_NUM, 12, "")
        row.value:SetTextColor(rgb(COLOR.accent))
        row.value:SetText(value)
    end
    finishRow(row)
    return row
end

function UI:AddDataRow(index, zebra)
    local row = self:AcquireRow(index)
    resetRow(row)
    row.value:SetFont(FONT_NUM, 13, "")
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

local function formatMinutes(minutes)
    if minutes >= 90 then
        return string.format("%.1f Std.", minutes / 60)
    end
    return string.format("%d Min.", math.ceil(minutes))
end

function UI:RenderToday()
    local Prices = GCP.Prices
    local plan = GCP.Roadmap:Generate()
    local index, zebra = 0, 0
    local lastCategory

    -- Kopfzeile des Zielplans: was fehlt noch, und wie lange dauert es.
    local goal = plan.goal
    if goal.goalValue > 0 then
        index = index + 1
        local header = self:AddHeaderRow(index, string.format("Tagesziel %s",
            Prices:FormatGold(goal.goalValue)))
        index = index + 1
        local row = self:AddDataRow(index, 1)
        if goal.earned >= goal.goalValue then
            row.text:SetText("Ziel erreicht – alles Weitere ist Zugabe.")
            row.value:SetTextColor(rgb(COLOR.green))
            row.value:SetText(Prices:FormatGold(goal.earned))
        elseif #goal.steps == 0 then
            row.text:SetText("Keine bewertbaren Aufgaben offen – Auctionator-Scan oder Berufsfenster fehlt?")
        else
            row.text:SetText(string.format(
                "%d Schritte bis zum Ziel – sie sind unten mit ihrer Reihenfolge markiert",
                #goal.steps))
            row.pill:Set(goal.reached and "Ziel erreichbar" or "Ziel knapp",
                goal.reached and COLOR.green or COLOR.red)
            row.value2:SetText("ca. " .. formatMinutes(goal.minutes))
            row.value:SetTextColor(rgb(COLOR.green))
            row.value:SetText(Prices:FormatGold(goal.gold))
        end
        finishRow(row)
    end

    for _, entry in ipairs(plan.entries) do
        if entry.category ~= lastCategory then
            index = index + 1
            local bucket = plan.categories[entry.category]
            local sum = bucket and bucket.open or 0
            self:AddHeaderRow(index, entry.category,
                sum > 0 and ("offen " .. Prices:FormatGold(sum)) or nil)
            lastCategory = entry.category
            zebra = 0
        end
        index = index + 1
        zebra = zebra + 1
        local row = self:AddDataRow(index, zebra)
        -- Erst die Rechnung des Eintrags, dann die generischen Zeilen: Wer
        -- wissen will, warum ein Vorschlag oben steht, liest zuerst Werte.
        local breakdown = {}
        for _, line in ipairs(entry.breakdown or {}) do
            breakdown[#breakdown + 1] = line
        end
        if entry.minutes then
            breakdown[#breakdown + 1] = string.format("Zeitschätzung: %s",
                formatMinutes(entry.minutes))
            if entry.value then
                breakdown[#breakdown + 1] = string.format("Gold je Minute: %s",
                    Prices:FormatGold(entry.value / entry.minutes))
            end
        end
        if entry.estimated then
            breakdown[#breakdown + 1] =
                "Goldbetrag geschätzt – der echte wird beim ersten Abgeben gelernt."
        end
        row.data = {
            roadmapKey = entry.key,
            checked = entry.done,
            autoDone = entry.autoDone,
            itemID = entry.itemID,
            link = entry.link,
            title = entry.text,
            breakdown = #breakdown > 0 and breakdown or nil,
        }
        row.check:Show()
        row.check.mark:SetShown(entry.done)
        if entry.done then
            row.text:SetTextColor(rgb(COLOR.textDim))
        end
        row.text:SetText(entry.text)
        if entry.autoDone then
            row.autoPill:Set("erkannt", COLOR.accent)
        elseif entry.goalRank then
            row.autoPill:Set("Plan " .. entry.goalRank, COLOR.accent)
        end
        if entry.note then
            row.value2:SetText(entry.note)
        end
        if entry.value then
            local color = entry.done and COLOR.textDim or COLOR.green
            row.value:SetTextColor(rgb(color))
            row.value:SetText((entry.estimated and "ca. " or "") .. Prices:FormatGold(entry.value))
        end
        finishRow(row)
    end

    if index == 0 then
        index = 1
        local row = self:AddDataRow(index)
        row.text:SetText("Keine Vorschläge – fehlt die Preisbasis? Im AH einen Auctionator-Scan starten.")
        finishRow(row)
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
        if item.keep then
            breakdown[#breakdown + 1] = "Eigenbedarf: Verbrauchbares wird nie zum Verkauf vorgeschlagen."
        end
        breakdown[#breakdown + 1] = "Rechtsklick oder Doppelklick: ausblenden · Shift-Klick: in den Chat verlinken"
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
        if item.keep then
            row.autoPill:Set("Eigenbedarf", COLOR.textDim)
        elseif item.bound then
            row.autoPill:Set("gebunden", COLOR.textDim)
        end
        row.value:SetText(Prices:FormatGold(item.totalValue))
        finishRow(row)
    end
    if index == 0 or (self.showIgnored and index == 1) then
        index = index + 1
        local row = self:AddDataRow(index)
        row.text:SetText(self.showIgnored
            and "Keine ignorierten Items – Rechtsklick auf eine Zeile blendet eine aus."
            or "Nichts gefunden – anderer Filter, oder erst ein Auctionator-Scan?")
        finishRow(row)
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
            line.data = {
                itemID = row.primalID,
                breakdown = {
                    string.format("Einkauf: %d Motes zu je %s = %s",
                        C.MOTES_PER_PRIMAL, Prices:FormatMoney(row.motePrice),
                        Prices:FormatMoney(C.MOTES_PER_PRIMAL * row.motePrice)),
                    "Verkauf netto: " .. Prices:FormatMoney(Prices:NetAuction(row.primalPrice)),
                    "Gewinn (Kauf-Flip): " .. Prices:FormatMoney(row.buyProfit),
                    "Gewinn beim Kombinieren eigener Motes: "
                        .. Prices:FormatMoney(row.combineDelta),
                    Prices:FormatPlanningBasis(row.priceDays),
                },
            }
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
            finishRow(line)
        else
            hidden = hidden + 1
        end
    end
    if #flips.motes == 0 then
        index = index + 1
        local row = self:AddDataRow(index)
        row.text:SetText("Keine Mote-Preise vorhanden – Auctionator-Scan nötig.")
        finishRow(row)
    end

    index = index + 1
    self:AddHeaderRow(index, "Essenzen 3:1  (benötigt Verzauberkunst)")
    zebra = 0
    for _, row in ipairs(flips.essences) do
        if row.profit >= threshold then
            index = index + 1
            zebra = zebra + 1
            local line = self:AddDataRow(index, zebra)
            local buy, sell
            if row.direction == "up" then
                buy = C.ESSENCES_PER_GREATER * row.lesserPrice
                sell = Prices:NetAuction(row.greaterPrice)
            else
                buy = row.greaterPrice
                sell = C.ESSENCES_PER_GREATER * Prices:NetAuction(row.lesserPrice)
            end
            line.data = {
                itemID = row.greaterID,
                breakdown = {
                    "Einkauf/Zutaten: " .. Prices:FormatMoney(buy),
                    "Verkauf netto: " .. Prices:FormatMoney(sell),
                    "Gewinn: " .. Prices:FormatMoney(row.profit),
                    Prices:FormatPlanningBasis(row.priceDays),
                },
            }
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
            finishRow(line)
        else
            hidden = hidden + 1
        end
    end
    if #flips.essences == 0 then
        index = index + 1
        local row = self:AddDataRow(index)
        row.text:SetText("Keine Essenz-Preise vorhanden – Auctionator-Scan nötig.")
        finishRow(row)
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
        finishRow(row)
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
                    string.format("Zutatenwert: %s", Prices:FormatMoney(row.matCost)),
                    string.format("Produktwert netto (×%.1f): %s",
                        row.numMade, Prices:FormatMoney(row.revenue)),
                    string.format("Erwarteter Gewinn: %s", Prices:FormatMoney(row.profit)),
                    Prices:FormatPlanningBasis(row.priceDays),
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
            finishRow(line)
        elseif row.profit > 0 then
            hidden = hidden + 1
        end
    end
    if shown == 0 then
        index = index + 1
        local row = self:AddDataRow(index)
        row.text:SetText("Kein Rezept über dem Mindestgewinn – Schwelle in den Optionen senken?")
        finishRow(row)
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
-- Markt
--
-- Die Tabelle beantwortet ausschliesslich "wie steht der aktuelle Preis zu
-- seiner eigenen Historie". Bewusst keine Kauf- oder Verkaufsaufforderung: 0.5
-- kennt weder Nachfrage noch Liquiditaet, und ein historisch billiges Item kann
-- billig sein, weil es niemand mehr will.
-- ---------------------------------------------------------------------------

local scoreColors = {
    [90] = { 0.35, 0.85, 0.45 },
    [75] = { 0.55, 0.80, 0.35 },
    [50] = { 0.80, 0.78, 0.45 },
    [25] = { 0.88, 0.60, 0.32 },
    [0]  = { 0.88, 0.40, 0.40 },
}

local function scoreColor(score)
    if type(score) ~= "number" then return COLOR.textDim end
    local _, floor = GCP.Market:ScoreBand(score)
    return scoreColors[floor or 0] or COLOR.textDim
end

function UI:RenderMarket()
    local Prices = GCP.Prices
    local Market = GCP.Market
    local report = Market:BuildReport(MARKET_ROW_LIMIT)
    local overview = report.overview
    local index, zebra = 0, 0

    index = index + 1
    local head = self:AddHeaderRow(index, "Beobachtete Märkte", "SCORE")
    local captions = { "PERZENTIL", "30T MEDIAN", "7T MEDIAN", "JETZT" }
    for column = 1, #captions do
        head.cols[column]:SetFont(FONT, 11, "")
        head.cols[column]:SetText(captions[column])
        head.cols[column]:SetTextColor(rgb(COLOR.accent))
    end
    head.value:SetFont(FONT, 11, "")
    finishMarketRow(head)

    -- Kaltstart: ein frisch installiertes Addon hat keine Historie, und das
    -- muss dort stehen, wo der Nutzer die Zahlen erwartet - nicht im README.
    if overview.snapshots == 0 then
        index = index + 1
        local row = self:AddDataRow(index)
        row.text:SetText("Gold Copilot lernt deinen Realm.")
        finishRow(row)
        index = index + 1
        row = self:AddDataRow(index)
        row.text:SetTextColor(rgb(COLOR.textDim))
        row.text:SetText("Für belastbare Marktsignale werden mehrere Tage Preisdaten benötigt. "
            .. "Im Auktionshaus einen Auctionator-Scan starten – der Rest passiert von selbst.")
        finishRow(row)
        self.frame.summary:SetText(string.format(
            "Gold Copilot beobachtet %d Märkte   ·   |cff8a8a94noch keine Preispunkte|r",
            overview.tracked))
        self:LayoutRows(index)
        return
    end

    for _, row in ipairs(report.rows) do
        index = index + 1
        zebra = zebra + 1
        local line = self:AddDataRow(index, zebra)
        local stats = row.stats
        local band = Market:ScoreBand(stats.score)

        local breakdown = {
            "Aktuell: " .. (stats.current and Prices:FormatMoney(stats.current) or "–")
                .. (stats.currentIsLive and "" or "  (letzter gespeicherter Wert)"),
            "24h Median: " .. (stats.median24 and Prices:FormatMoney(stats.median24) or "–"),
            "7d Median: " .. (stats.median7 and Prices:FormatMoney(stats.median7) or "–"),
            "30d Median: " .. (stats.median30 and Prices:FormatMoney(stats.median30) or "–"),
            "7d Range: " .. ((stats.min7 and stats.max7)
                and (Prices:FormatMoney(stats.min7) .. " – " .. Prices:FormatMoney(stats.max7))
                or "–"),
            "Perzentil: " .. Market:FormatPercentile(stats.percentile),
            "Volatilität: " .. Market:FormatVolatility(stats.volatility),
            string.format("Snapshots: %d", stats.snapshots),
            string.format("Historientage: %d", stats.days),
            " ",
            stats.score
                and string.format("Market Score: %d/100  (%s)", stats.score, band or "–")
                or "Market Score: noch keiner – zu wenig Daten",
            "Confidence: " .. Market:ConfidenceLabel(stats.confidence),
            " ",
            Market:DescribeScore(stats),
            " ",
            "Der Score vergleicht nur mit deiner eigenen Historie. Er sagt nichts über "
                .. "Nachfrage, Liquidität oder Verkaufsdauer.",
        }
        if row.reason then
            breakdown[#breakdown + 1] = "Beobachtet als: " .. row.reason
        end
        if stats.source then
            breakdown[#breakdown + 1] = "Datenquelle: " .. Market:SourceLabel(stats.source)
        end
        local watched = Market:IsWatched(row.itemID)
        breakdown[#breakdown + 1] = watched
            and "Rechtsklick: aus der Beobachtung nehmen"
            or "Rechtsklick: zur Beobachtung hinzufügen"
        line.data = {
            itemID = row.itemID,
            title = row.name,
            breakdown = breakdown,
            watchable = row.itemID,
            watchReason = "Markt-Tab",
        }
        if watched then
            line.pill:Set("beobachtet", COLOR.accent)
        end
        if row.icon then
            line.icon:SetTexture(row.icon)
            line.icon:Show()
        end
        local color = qualityColors[row.quality or 1] or "|cffffffff"
        line.text:SetText(string.format("%s%s|r", color,
            row.name or ("Item " .. row.itemID)))

        line.cols[4]:SetText(stats.current and Prices:FormatGold(stats.current) or "–")
        if stats.current and not stats.currentIsLive then
            line.cols[4]:SetTextColor(rgb(COLOR.textDim))
        else
            line.cols[4]:SetTextColor(rgb(COLOR.text))
        end
        line.cols[3]:SetText(stats.median7 and Prices:FormatGold(stats.median7) or "–")
        line.cols[2]:SetText(stats.median30 and Prices:FormatGold(stats.median30) or "–")
        line.cols[1]:SetText(stats.percentile and Market:FormatPercentile(stats.percentile) or "–")

        if stats.score then
            line.value:SetTextColor(rgb(scoreColor(stats.score)))
            line.value:SetText(tostring(stats.score))
        else
            line.value:SetTextColor(rgb(COLOR.textDim))
            line.value:SetText("–")
        end
        -- Die Confidence steht als Etikett daneben, nicht im Score: ein hoher
        -- Score aus duenner Datenlage darf nicht wie ein sicherer aussehen.
        if stats.confidence == "high" then
            line.autoPill:Set("sicher", COLOR.green)
        elseif stats.confidence == "medium" then
            line.autoPill:Set("mittel", COLOR.accent)
        else
            line.autoPill:Set("wenig Daten", COLOR.textDim)
        end
        finishMarketRow(line)
    end

    if #report.rows == 0 then
        index = index + 1
        local row = self:AddDataRow(index)
        row.text:SetText("Noch keine auswertbaren Märkte – ein Auctionator-Scan fehlt.")
        finishRow(row)
    end

    local spanText = overview.spanDays > 0
        and string.format("%d Tag%s Historie", overview.spanDays,
            overview.spanDays == 1 and "" or "e")
        or "noch keine Historie"
    self.frame.summary:SetText(string.format(
        "Gold Copilot beobachtet %d Märkte   ·   |cff8a8a94%s Preispunkte · %s|r",
        overview.itemsWithHistory, Market:FormatCount(overview.snapshots), spanText))
    self:LayoutRows(index)
end

-- ---------------------------------------------------------------------------
-- Chancen
--
-- Der Tab beantwortet zum ersten Mal "ist das eine interessante Gold-Chance?"
-- statt nur "ist der Preis historisch guenstig?". Bewusst zurueckhaltend
-- formuliert: Es steht "interessant" da, nicht "kaufen", und jede Zeile nennt
-- im Tooltip ihre komplette Rechnung samt der Grenzen dieser Version.
-- ---------------------------------------------------------------------------

local opportunityColors = {
    [80] = { 0.35, 0.85, 0.45 },
    [60] = { 0.55, 0.80, 0.35 },
    [40] = { 0.80, 0.78, 0.45 },
    [0]  = { 0.70, 0.70, 0.76 },
}

local function opportunityColor(score)
    if type(score) ~= "number" then return COLOR.textDim end
    local _, floor = GCP.Opportunity:ScoreBand(score)
    return opportunityColors[floor or 0] or COLOR.textDim
end

local typeColors = {
    craft = { 0.85, 0.66, 0.20 },
    conversion = { 0.30, 0.75, 1.00 },
    disenchant = { 0.64, 0.21, 0.93 },
    resale = { 0.45, 0.80, 0.55 },
}

-- Farbskala des Liquidity Scores (0.8.0). Sie steht hier oben, weil sowohl der
-- Chancen- als auch der Handel-Tab sie braucht - und der Chancen-Tab kommt
-- zuerst.
local liquidityColors = {
    [80] = { 0.35, 0.85, 0.45 },
    [60] = { 0.55, 0.80, 0.35 },
    [40] = { 0.80, 0.78, 0.45 },
    [20] = { 0.85, 0.60, 0.35 },
    [0]  = { 0.70, 0.70, 0.76 },
}

local function liquidityColor(score)
    if type(score) ~= "number" then return COLOR.textDim end
    local _, floor = GCP.Ledger:ScoreBand(score)
    return liquidityColors[floor or 0] or COLOR.textDim
end

function UI:RenderChancen()
    local Prices = GCP.Prices
    local Opportunity = GCP.Opportunity
    local Market = GCP.Market
    local report = Opportunity:BuildReport()
    local index, zebra = 0, 0

    -- Die Kopfzeile ist hier reine Spaltenbeschriftung; der Satz darueber sagt
    -- bereits, worum es geht.
    index = index + 1
    local head = self:AddHeaderRow(index, "AKTION")
    head.text:SetFont(FONT, 11, "")
    head.value:SetFont(FONT, 11, "")
    head.value:SetTextColor(rgb(COLOR.accent))
    head.value:SetText("SCORE")
    head.typeText:SetFont(FONT, 11, "")
    head.typeText:SetTextColor(rgb(COLOR.accent))
    head.typeText:SetText("TYP")
    local captions = { "LIQ.", "ROI", "PROFIT", "KAPITAL" }
    for column = 1, #captions do
        head.cols[column]:SetFont(FONT, 11, "")
        head.cols[column]:SetText(captions[column])
        head.cols[column]:SetTextColor(rgb(COLOR.accent))
    end
    finishOpportunityRow(head)

    local rows = report.opportunities
    if self.onlyWatched then
        local filtered = {}
        for _, opportunity in ipairs(rows) do
            if Market:IsWatched(opportunity.itemID) then
                filtered[#filtered + 1] = opportunity
            end
        end
        rows = filtered
    end

    for _, opportunity in ipairs(rows) do
        index = index + 1
        zebra = zebra + 1
        local line = self:AddDataRow(index, zebra)
        local band = Opportunity:ScoreBand(opportunity.opportunityScore)
        local watched = Market:IsWatched(opportunity.itemID)

        local breakdown = Opportunity:Explain(opportunity)
        local statusText = Opportunity:StatusLabel(
            Opportunity:ExecutionStatus(opportunity.saleItemID))
        if statusText then
            breakdown[#breakdown + 1] = " "
            breakdown[#breakdown + 1] = "Deine Spur zu diesem Item: " .. statusText
                .. " – aus deiner Handelsbilanz, nicht geraten."
        end
        breakdown[#breakdown + 1] = " "
        breakdown[#breakdown + 1] = watched
            and "Rechtsklick: aus der Beobachtung nehmen"
            or "Rechtsklick: zur Beobachtung hinzufügen"
        line.data = {
            itemID = opportunity.itemID,
            title = opportunity.title,
            breakdown = breakdown,
            watchable = opportunity.itemID,
            watchReason = "Chancen-Tab",
        }

        line.value:SetFont(FONT_NUM, 14, "")
        line.value:SetTextColor(rgb(opportunityColor(opportunity.opportunityScore)))
        line.value:SetText(tostring(opportunity.opportunityScore))

        if opportunity.icon then
            line.icon:SetTexture(opportunity.icon)
            line.icon:Show()
        end

        local typeColor = typeColors[opportunity.type] or COLOR.textDim
        line.typeText:SetTextColor(typeColor[1], typeColor[2], typeColor[3])
        line.typeText:SetText(Opportunity:TypeLabel(opportunity.type))

        local color = qualityColors[opportunity.quality or 1] or "|cffffffff"
        line.text:SetText(string.format("%s%s|r", color, opportunity.title or "?"))

        -- Ausfuehrungsstatus (0.8.0). Er steht vor allen anderen Etiketten:
        -- "das liegt schon im Auktionshaus" ist die Information, die eine
        -- Entscheidung sofort aendert. Gesetzt wird er nur, wenn die
        -- Handelsbilanz ihn eindeutig hergibt - nichts davon wird geraten.
        local status = Opportunity:ExecutionStatus(opportunity.saleItemID)
        local statusLabel = Opportunity:StatusLabel(status)

        -- Ein Item kann ueber mehrere Wege auftauchen. Die Zeilen bleiben
        -- getrennt - es sind verschiedene Geschaefte -, sagen es aber dazu.
        if statusLabel then
            line.autoPill:Set(statusLabel,
                status == "SOLD" and COLOR.green or COLOR.accent)
        elseif opportunity.alsoTypes and #opportunity.alsoTypes > 0 then
            local labels = {}
            for _, kind in ipairs(opportunity.alsoTypes) do
                labels[#labels + 1] = Opportunity:TypeLabel(kind)
            end
            line.autoPill:Set("auch " .. table.concat(labels, "/"), COLOR.textDim)
        elseif watched then
            line.autoPill:Set("beobachtet", COLOR.accent)
        elseif opportunity.feasible then
            line.autoPill:Set(string.format("×%d machbar", opportunity.feasible), COLOR.accent)
        end
        line.pill:Set(band, band == "sehr interessant" and COLOR.green or COLOR.textDim)

        line.cols[4]:SetText(Prices:FormatGold(opportunity.cost))
        line.cols[3]:SetText("+" .. Prices:FormatGold(opportunity.expectedProfit))
        line.cols[3]:SetTextColor(rgb(COLOR.green))
        line.cols[2]:SetText(Opportunity:FormatROI(opportunity.roi))
        -- Ein Strich heisst hier "noch nie selbst verkauft", nicht "verkauft
        -- sich schlecht". Deshalb steht er in Grau und nicht in Rot.
        if opportunity.liquidityScore then
            line.cols[1]:SetText(tostring(opportunity.liquidityScore))
            line.cols[1]:SetTextColor(rgb(liquidityColor(opportunity.liquidityScore)))
        else
            line.cols[1]:SetText("–")
            line.cols[1]:SetTextColor(rgb(COLOR.textDim))
        end
        finishOpportunityRow(line)
    end

    if #rows == 0 then
        index = index + 1
        local row = self:AddDataRow(index)
        if self.onlyWatched then
            row.text:SetText("Keine Chance unter deinen beobachteten Items – "
                .. "Rechtsklick auf eine Zeile nimmt eines auf.")
        elseif report.total > 0 then
            row.text:SetText(string.format(
                "%d Chance(n) berechnet, aber keine über deinen Filtern – "
                .. "Mindestprofit oder Mindest-ROI in den Optionen senken?",
                report.total))
        else
            row.text:SetText("Noch keine belastbare Chance gefunden.")
            finishRow(row)
            index = index + 1
            row = self:AddDataRow(index)
            row.text:SetTextColor(rgb(COLOR.textDim))
            row.text:SetText("Gold Copilot rechnet aus deinen eigenen Preisen. "
                .. "Im Auktionshaus einen Auctionator-Scan starten und einmal jedes "
                .. "Berufsfenster öffnen – danach entsteht hier etwas.")
        end
        finishRow(row)
    end

    index = index + 1
    local note = self:AddDataRow(index)
    note.text:SetTextColor(rgb(COLOR.textDim))
    note.text:SetText("Alle Beträge sind theoretische Margen aus deinen beobachteten Preisen. "
        .. Opportunity:LiquidityNote())
    finishRow(note)

    local notes = {}
    -- Wie viele Zeilen ueberhaupt eine eigene Liquiditaetsaussage haben. Steht
    -- oben statt an jeder Zeile: "unbekannt" ist der Normalfall, solange das
    -- Addon noch nicht mitgehandelt hat.
    if report.withLiquidity == 0 then
        notes[#notes + 1] = "Liquidität unbekannt – noch keine eigenen Verkäufe"
    else
        notes[#notes + 1] = string.format("%d von %d mit eigenen Verkaufsdaten",
            report.withLiquidity, report.listed)
    end
    local hidden = report.hiddenByProfit + report.hiddenByROI
    if hidden > 0 then
        notes[#notes + 1] = string.format("%d unter Mindestprofit (%s) oder Mindest-ROI (%s)",
            hidden, Prices:FormatGold(report.minProfit),
            Opportunity:FormatROI(report.minROI))
    end
    -- Ein stiller Deckel waere eine Falschaussage: Wenn die Liste gekappt ist,
    -- steht das da.
    if report.truncated > 0 then
        notes[#notes + 1] = string.format("%d weitere nicht angezeigt", report.truncated)
    end
    if self.onlyWatched then
        notes[#notes + 1] = string.format("nur beobachtete Items (%d von %d)",
            #rows, report.listed)
    end
    local noteText = #notes > 0
        and ("   ·   |cff8a8a94" .. table.concat(notes, " · ") .. "|r") or ""
    self.frame.summary:SetText(Opportunity:SummaryText(report) .. noteText)
    self.frame.watchButton:SetLabel(string.format("Beobachtung (%d)", Market:CountWatchItems()))
    self.frame.watchButton:SetActive(self.onlyWatched)
    self.frame.opportunitySortButton:SetLabel("Sortierung: "
        .. Opportunity:SortLabel(report.sortMode))
    self.frame.opportunitySortButton:SetActive(report.sortMode ~= "score")
    self:LayoutRows(index)
end

-- ---------------------------------------------------------------------------
-- Zukunft
--
-- Der Tab beantwortet: "Welche bereits bekannten Veraenderungen im Spiel
-- koennten die Nachfrage nach diesem Item veraendern?" Oben steht der naechste
-- bekannte Catalyst mit Termin und Wissensstand, darunter die Items, fuer die
-- es ueberhaupt eine belegte Zukunftsaussage gibt.
--
-- Jede Zeile trennt Fakt und Modell: Was Blizzard angekuendigt oder das Spiel
-- vorgegeben hat, steht als Fakt da; Demand, Hype und Signal sind ausdruecklich
-- als Einschaetzung dieses Addons gekennzeichnet. Nirgends steht ein Zielpreis.
-- ---------------------------------------------------------------------------

local futureColors = {
    [90] = { 0.35, 0.85, 0.45 },
    [75] = { 0.55, 0.80, 0.35 },
    [60] = { 0.80, 0.78, 0.45 },
    [40] = { 0.70, 0.70, 0.76 },
    [25] = { 0.88, 0.60, 0.32 },
    [0]  = { 0.88, 0.40, 0.40 },
}

local function futureColor(score)
    if type(score) ~= "number" then return COLOR.textDim end
    local _, floor = GCP.Future:ScoreBand(score)
    return futureColors[floor or 0] or COLOR.textDim
end

-- Demand und Hype haben ihre eigene Farblogik: 50 ist die Mitte, und ein hoher
-- Hype ist kein guter Wert, sondern eine Warnung.
local function demandColor(score)
    if type(score) ~= "number" then return COLOR.textDim end
    if score >= 65 then return COLOR.green end
    if score <= 40 then return COLOR.red end
    return COLOR.text
end

local function hypeColor(score)
    if type(score) ~= "number" then return COLOR.textDim end
    if score >= 70 then return COLOR.red end
    if score >= 45 then return { 0.88, 0.60, 0.32 } end
    return COLOR.green
end

local function futureBreakdown(record)
    local Prices = GCP.Prices
    local Market = GCP.Market
    local Future = GCP.Future
    local stats = record.stats
    local lines = {}
    local function push(text) lines[#lines + 1] = text end

    push("Aktueller Realm-Preis: " .. ((stats and stats.current)
        and Prices:FormatMoney(stats.current) or "–"))
    push("7d Median: " .. ((stats and stats.median7)
        and Prices:FormatMoney(stats.median7) or "–"))
    push("30d Median: " .. ((stats and stats.median30)
        and Prices:FormatMoney(stats.median30) or "–"))
    push("Market Score: " .. (record.marketScore
        and string.format("%d/100", record.marketScore)
        or "noch keiner – zu wenig Historie"))

    push(" ")
    push(string.format("FUTURE DEMAND (Modell): %d/100", record.futureDemandScore))
    local explanation = Future:GetExplanation(record.itemID)
    if #explanation.positive > 0 then
        push("Catalysts:")
        for _, entry in ipairs(explanation.positive) do
            push("• " .. entry.text)
        end
    end
    if #explanation.negative > 0 then
        push("Dagegen spricht:")
        for _, entry in ipairs(explanation.negative) do
            push("• " .. entry.text)
        end
    end

    if #explanation.facts > 0 then
        push(" ")
        push("Fakten aus dem Spiel:")
        for _, entry in ipairs(explanation.facts) do
            push("• " .. entry.text)
        end
    end

    push(" ")
    if record.hypeScore then
        push(string.format("HYPE (Modell): %d/100", record.hypeScore))
        if stats and stats.current and stats.median30 and stats.median30 > 0 then
            local delta = (stats.current - stats.median30) / stats.median30
            push(string.format("Der Preis liegt aktuell %.0f %% %s seinem 30-Tage-Median.",
                math.abs(delta) * 100, delta < 0 and "unter" or "über"))
        end
    else
        push("HYPE: noch nicht berechenbar – zu wenig Realm-Historie")
    end

    push(" ")
    if record.entryPrice then
        push("Interessant unter: " .. Prices:FormatMoney(record.entryPrice)
            .. "  (unteres Quartil deiner 30-Tage-Reihe, abzüglich Hype-Abschlag)")
    else
        push("Einstiegszone: noch keine belastbare – dafür fehlen Preispunkte")
    end
    if record.dontChase then
        push("NICHT HINTERHERLAUFEN – " .. (record.dontChaseReason or ""))
    end

    push(" ")
    if record.futureOpportunityScore then
        local band = Future:ScoreBand(record.futureOpportunityScore)
        push(string.format("SIGNAL (Modell): %d/100 – %s",
            record.futureOpportunityScore, band or "–"))
    else
        push("SIGNAL: nicht berechenbar")
    end
    push("Wissens-Confidence: " .. Market:ConfidenceLabel(record.confidence)
        .. "  ·  Realm-Datenlage: " .. Market:ConfidenceLabel(record.marketConfidence))

    push(" ")
    for _, entry in ipairs(explanation.warnings) do
        push(entry.text)
    end
    push("Wissensstand: " .. GCP.Knowledge.VERSION_LABEL)
    return lines
end

function UI:RenderZukunft()
    local Future = GCP.Future
    local Market = GCP.Market
    local Knowledge = GCP.Knowledge
    local report = Future:BuildReport()
    local index, zebra = 0, 0

    -- 1. Der naechste bekannte Catalyst. Er steht ganz oben, weil er die
    --    Ueberschrift ueber allem darunter ist.
    index = index + 1
    self:AddHeaderRow(index, "Nächster bekannter Catalyst")

    local nextPhase = report.nextPhase
    if nextPhase then
        index = index + 1
        local row = self:AddDataRow(index)
        row.text:SetText(string.format("|cffd9a834%s|r – %s",
            nextPhase.shortName or nextPhase.id, nextPhase.name))
        local timing = report.timing
        if timing and timing.daysUntil then
            row.value:SetTextColor(rgb(COLOR.accent))
            row.value:SetText(string.format("%d T", timing.daysUntil))
            row.value2:SetText(date("%d.%m.%Y", nextPhase.release))
        else
            row.value:SetTextColor(rgb(COLOR.textDim))
            row.value:SetFont(FONT, 12, "")
            row.value:SetText("Termin offen")
        end
        row.pill:Set(Knowledge.SOURCE_LABEL[nextPhase.sourceConfidence or "inferred"],
            nextPhase.sourceConfidence == "official" and COLOR.green or COLOR.textDim)
        finishRow(row)

        for _, entry in ipairs(nextPhase.content or {}) do
            index = index + 1
            local line = self:AddDataRow(index)
            line.text:SetTextColor(rgb(COLOR.textDim))
            line.text:SetText("•  " .. entry.text)
            finishRow(line)
        end

        if timing and timing.zone then
            index = index + 1
            local line = self:AddDataRow(index)
            line.text:SetTextColor(rgb(COLOR.textDim))
            line.text:SetText("Zeitfenster: " .. Future:TimingLabel(timing.zone)
                .. "  ·  Nähe allein ist kein Kaufgrund – kurz vor Release ist eine "
                .. "bekannte Ankündigung oft längst eingepreist.")
            finishRow(line)
        end
    else
        index = index + 1
        local row = self:AddDataRow(index)
        row.text:SetText("Aktuell ist keine weitere Phase bekannt.")
        finishRow(row)
    end

    index = index + 1
    local versionRow = self:AddDataRow(index)
    versionRow.text:SetTextColor(rgb(COLOR.textDim))
    versionRow.text:SetText(string.format(
        "Wissensstand: %s  ·  %d Phasen, %d Catalysts, %d Rezeptkanten  ·  "
        .. "Die Wissensbasis wird mit dem Addon ausgeliefert, nicht aus dem Netz geladen.",
        report.knowledgeLabel, report.knowledge.phases, report.knowledge.catalysts,
        report.graph.edges))
    finishRow(versionRow)

    -- 2. Die Tabelle.
    index = index + 1
    local head = self:AddHeaderRow(index, "TOP FUTURE OPPORTUNITIES", "SIGNAL")
    head.text:SetFont(FONT, 11, "")
    head.value:SetFont(FONT, 11, "")
    local captions = { "CATALYST", "HYPE", "DEMAND", "MARKT" }
    for column = 1, #captions do
        head.cols[column]:SetFont(FONT, 11, "")
        head.cols[column]:SetText(captions[column])
        head.cols[column]:SetTextColor(rgb(COLOR.accent))
    end
    finishFutureRow(head)

    local rows = report.rows
    if self.onlyWatched then
        local filtered = {}
        for _, record in ipairs(rows) do
            if Market:IsWatched(record.itemID) then filtered[#filtered + 1] = record end
        end
        rows = filtered
    end

    for _, record in ipairs(rows) do
        index = index + 1
        zebra = zebra + 1
        local line = self:AddDataRow(index, zebra)
        local watched = Market:IsWatched(record.itemID)

        local breakdown = futureBreakdown(record)
        breakdown[#breakdown + 1] = " "
        breakdown[#breakdown + 1] = watched
            and "Rechtsklick: aus der Beobachtung nehmen"
            or "Rechtsklick: mit These beobachten"

        local leading = record.demand.leading
        local thesis = leading
            and (Knowledge.TYPE_LABEL[leading.catalyst.type] or leading.catalyst.type)
            or nil
        line.data = {
            itemID = record.itemID,
            title = record.name,
            breakdown = breakdown,
            watchable = record.itemID,
            watchReason = "future",
            watchMeta = {
                phase = record.phase,
                thesis = thesis,
                targetEntry = record.entryPrice,
            },
        }

        if record.icon then
            line.icon:SetTexture(record.icon)
            line.icon:Show()
        end
        local color = qualityColors[record.quality or 1] or "|cffffffff"
        line.text:SetText(string.format("%s%s|r", color,
            record.name or ("Item " .. record.itemID)))

        if record.dontChase then
            line.pill:Set("nicht hinterherlaufen", COLOR.red)
        elseif watched then
            line.pill:Set("beobachtet", COLOR.accent)
        elseif record.entryPrice then
            line.pill:Set("unter " .. GCP.Prices:FormatGold(record.entryPrice), COLOR.textDim)
        end

        local phase = record.phase and Knowledge:GetPhase(record.phase)
        local catalystText = phase and (phase.shortName or phase.id) or "–"
        if record.daysUntilCatalyst then
            catalystText = string.format("%s · %d T", catalystText, record.daysUntilCatalyst)
        end
        line.cols[1]:SetFont(FONT, 11, "")
        line.cols[1]:SetText(catalystText)
        line.cols[2]:SetText(record.hypeScore and tostring(record.hypeScore) or "–")
        line.cols[2]:SetTextColor(rgb(hypeColor(record.hypeScore)))
        line.cols[3]:SetText(tostring(record.futureDemandScore))
        line.cols[3]:SetTextColor(rgb(demandColor(record.futureDemandScore)))
        line.cols[4]:SetText(record.marketScore and tostring(record.marketScore) or "–")
        line.cols[4]:SetTextColor(rgb(record.marketScore
            and scoreColor(record.marketScore) or COLOR.textDim))

        if record.futureOpportunityScore then
            line.value:SetTextColor(rgb(futureColor(record.futureOpportunityScore)))
            line.value:SetText(tostring(record.futureOpportunityScore))
        else
            line.value:SetTextColor(rgb(COLOR.textDim))
            line.value:SetText("–")
        end
        finishFutureRow(line)
    end

    if #rows == 0 then
        index = index + 1
        local row = self:AddDataRow(index)
        if self.onlyWatched then
            row.text:SetText("Keines deiner beobachteten Items hat einen bekannten Catalyst.")
        else
            row.text:SetText("Für keinen bekannten Catalyst liegt ein Item vor.")
        end
        finishRow(row)
    end

    index = index + 1
    local note = self:AddDataRow(index)
    note.text:SetTextColor(rgb(COLOR.textDim))
    note.text:SetText("Demand, Hype und Signal sind Einschätzungen dieses Addons aus "
        .. "bekannten Spielzusammenhängen und deinen eigenen Realm-Preisen – keine "
        .. "Preisprognose und keine Garantie.")
    finishRow(note)

    local notes = {}
    if report.truncated > 0 then
        notes[#notes + 1] = string.format("%d weitere nicht angezeigt", report.truncated)
    end
    if self.onlyWatched then
        notes[#notes + 1] = string.format("nur beobachtete Items (%d von %d)",
            #rows, report.listed)
    end
    local noteText = #notes > 0
        and ("   ·   |cff8a8a94" .. table.concat(notes, " · ") .. "|r") or ""
    self.frame.summary:SetText(string.format("%s   ·   |cff8a8a94Wissensstand %s|r%s",
        Future:SummaryText(report), report.knowledgeLabel, noteText))
    self.frame.watchButton:SetLabel(string.format("Beobachtung (%d)", Market:CountWatchItems()))
    self.frame.watchButton:SetActive(self.onlyWatched)
    self:LayoutRows(index)
end

-- ---------------------------------------------------------------------------
-- Handel (0.8.0)
--
-- Der erste Tab, der nicht ueber den Markt spricht, sondern ueber den Nutzer:
-- Was hast DU verkauft, wie schnell ging es, und was ist dabei
-- herausgekommen? Oben die letzten sieben und dreissig Tage, darunter die
-- Items mit eigener Handelsgeschichte.
--
-- Jede Zahl hier ist gemessen, keine einzige geschaetzt. Wo etwas fehlt, steht
-- ein Strich und im Tooltip der Grund - nicht ein plausibel aussehender
-- Platzhalter.
-- ---------------------------------------------------------------------------

local LEDGER_SORT_LABEL = {
    liquidity = "Sortierung: Liquidität",
    profit = "Sortierung: realisierter Gewinn",
    sales = "Sortierung: Verkäufe",
}

local function percentText(value)
    if type(value) ~= "number" then return "–" end
    return string.format("%.0f %%", value * 100)
end

local function signedPercentText(value)
    if type(value) ~= "number" then return "–" end
    return string.format("%+.1f %%", value * 100)
end

-- Kopfzeile eines Zeitfensters. Bewusst vier Zahlen und kein Diagramm: Umsatz,
-- Gewinn, Sell-through und Verkaufszeit sind die Groessen, nach denen der
-- naechste Handel entschieden wird.
--
-- Die Zeile nutzt ausdruecklich NICHT die Zahlenspalten der Tabelle darunter:
-- Deren Breiten gehoeren zu anderen Groessen, und der Zeilen-Pool reicht sie
-- weiter. Ein "Umsatz 1.234 g" in einer 58 Pixel breiten Spalte waere
-- abgeschnitten - hier stehen die Zahlen deshalb im Fliesstext.
function UI:AddLedgerPeriodRow(index, label, stats)
    local Prices = GCP.Prices
    local Opportunity = GCP.Opportunity
    local row = self:AddDataRow(index)

    local profitText = "–"
    if stats.realizedProfitKnown and stats.realizedProfit then
        profitText = (stats.realizedProfit >= 0 and "+" or "")
            .. Prices:FormatGold(stats.realizedProfit)
    end
    local sellThroughText = stats.sellThrough and percentText(stats.sellThrough)
        or (stats.sellThroughAuctions
            and (percentText(stats.sellThroughAuctions) .. "*") or "–")

    row.text:SetText(string.format(
        "%s   ·   Umsatz %s   ·   Profit %s   ·   Sell-through %s   ·   Median %s",
        label, Prices:FormatGold(stats.revenueNet), profitText, sellThroughText,
        stats.medianHours and Opportunity:FormatHours(stats.medianHours) or "–"))
    row.text:SetTextColor(rgb(COLOR.text))
    row.value:SetFont(FONT, 11, "")
    row.value:SetTextColor(rgb(COLOR.textDim))
    row.value:SetText(string.format("%d verkauft · %d abgelaufen",
        stats.sales, stats.expiries))

    local breakdown = {
        string.format("Zeitraum: letzte %d Tage", stats.days or 0),
        "Umsatz brutto: " .. Prices:FormatMoney(stats.revenueGross),
        "Umsatz netto (nach AH-Gebühr): " .. Prices:FormatMoney(stats.revenueNet),
        "Einkauf im selben Zeitraum: " .. Prices:FormatMoney(stats.purchaseCost),
        "Verlorene Einstellgebühren: " .. Prices:FormatMoney(stats.depositLost),
        " ",
        string.format("Verkauft: %d Auktion(en), %d Stück", stats.sales, stats.soldQuantity),
        string.format("Abgelaufen: %d Auktion(en), %d Stück", stats.expiries, stats.expiredQuantity),
        string.format("Zurückgezogen: %d Auktion(en) – zählen bewusst nicht als Fehlschlag",
            stats.cancels),
        " ",
    }
    if stats.realizedProfitKnown then
        breakdown[#breakdown + 1] = "Realisierter Gewinn: " .. profitText
        breakdown[#breakdown + 1] = "= Nettoerlös der zugeordneten Verkäufe – gewichteter "
            .. "Einkaufspreis × verkaufte Stückzahl – verlorene Einstellgebühren."
    else
        breakdown[#breakdown + 1] = "Realisierter Gewinn: unbekannt"
        breakdown[#breakdown + 1] = "Für die verkauften Stücke fehlt eine belegte "
            .. "Kostenbasis – selbst gefarmte oder hergestellte Ware bekommt "
            .. "ausdrücklich keinen Einkaufspreis von 0."
    end
    if stats.unmatchedSales > 0 then
        breakdown[#breakdown + 1] = " "
        breakdown[#breakdown + 1] = string.format(
            "%d Verkauf/Verkäufe ohne zuordenbare Einstellung – für sie ist die "
            .. "Stückzahl unbekannt, deshalb steht die stückzahlbasierte "
            .. "Sell-through-Rate hier mit * als Rate je Auktion.",
            stats.unmatchedSales)
    end
    row.data = { title = label, breakdown = breakdown }
    finishRow(row)
    return row
end

function UI:RenderHandel()
    local Prices = GCP.Prices
    local Ledger = GCP.Ledger
    local Opportunity = GCP.Opportunity
    local sortMode = (GCP.db.options and GCP.db.options.ledgerSort) or "liquidity"
    local report = Ledger:BuildReport(sortMode, LEDGER_ROW_LIMIT)
    local index, zebra = 0, 0

    index = index + 1
    self:AddHeaderRow(index, "Deine letzten Tage")
    index = index + 1
    self:AddLedgerPeriodRow(index, "7 Tage", report.week)
    index = index + 1
    self:AddLedgerPeriodRow(index, "30 Tage", report.month)

    -- Kaltstart. Er steht dort, wo der Nutzer die Zahlen erwartet, und er sagt
    -- offen, dass das Addon hier erst lernt.
    if not Ledger:HasData() then
        index = index + 1
        local row = self:AddDataRow(index)
        row.text:SetText("Gold Copilot lernt deine Verkäufe.")
        finishRow(row)
        index = index + 1
        row = self:AddDataRow(index)
        row.text:SetTextColor(rgb(COLOR.textDim))
        row.text:SetText("Je mehr du handelst, desto besser kann es Kapitalrotation "
            .. "einschätzen. Erfasst werden ausschließlich bestätigte "
            .. "Auktionshaus-Vorgänge: eingestellt, verkauft, abgelaufen, "
            .. "zurückgezogen, gekauft.")
        finishRow(row)
        index = index + 1
        row = self:AddDataRow(index)
        row.text:SetTextColor(rgb(COLOR.textDim))
        row.text:SetText("Nichts davon wird geschätzt, und nichts verlässt deinen "
            .. "Rechner – alles liegt lokal in deinen SavedVariables.")
        finishRow(row)
        self.frame.summary:SetText("Noch keine eigenen Handelsdaten   ·   "
            .. "|cff8a8a94Verkaufe etwas im Auktionshaus und öffne danach deinen "
            .. "Briefkasten|r")
        self.frame.ledgerSortButton:SetLabel(LEDGER_SORT_LABEL[sortMode] or "Sortierung")
        self:LayoutRows(index)
        return
    end

    index = index + 1
    local head = self:AddHeaderRow(index, "ITEM", "LIQUIDITÄT")
    head.text:SetFont(FONT, 11, "")
    head.value:SetFont(FONT, 11, "")
    local captions = { "REAL. MARGE", "ZEIT", "SELL-THROUGH", "ABGELAUFEN", "VERKAUFT" }
    for column = 1, #captions do
        head.cols[column]:SetFont(FONT, 11, "")
        head.cols[column]:SetText(captions[column])
        head.cols[column]:SetTextColor(rgb(COLOR.accent))
    end
    finishLedgerRow(head)

    for _, row in ipairs(report.rows) do
        index = index + 1
        zebra = zebra + 1
        local line = self:AddDataRow(index, zebra)
        local stats = row.stats
        local band = Ledger:ScoreBand(stats.liquidityScore)

        local breakdown = {
            string.format("Eingestellt: %d Auktion(en), %d Stück",
                stats.postedAuctions, stats.postedQuantity),
            string.format("Verkauft: %d Auktion(en), %d Stück",
                stats.soldAuctions, stats.soldQuantity),
            string.format("Abgelaufen: %d Auktion(en), %d Stück",
                stats.expiredAuctions, stats.expiredQuantity),
            string.format("Zurückgezogen: %d Auktion(en) – kein Fehlschlag",
                stats.cancelledAuctions),
            string.format("Gekauft: %d Mal, %d Stück", stats.purchases, stats.boughtQuantity),
            " ",
            "Sell-through (Stückzahl): " .. (stats.sellThrough
                and percentText(stats.sellThrough)
                or "unbekannt – nicht jeder Verkauf ließ sich einer Einstellung zuordnen"),
            "Sell-through (je Auktion): " .. (stats.sellThroughAuctions
                and percentText(stats.sellThroughAuctions) or "–"),
            "Datenlage: " .. GCP.Market:ConfidenceLabel(stats.confidence),
            " ",
            "Median bis Verkauf: " .. (stats.medianHours
                and Opportunity:FormatHours(stats.medianHours)
                or "unbekannt – keine Einstellung zuzuordnen"),
        }
        if stats.p25Hours and stats.p75Hours then
            breakdown[#breakdown + 1] = string.format("Streuung: %s (25 %%) bis %s (75 %%)",
                Opportunity:FormatHours(stats.p25Hours),
                Opportunity:FormatHours(stats.p75Hours))
        end
        if stats.medianHoldHours and stats.medianHours
            and stats.medianHoldHours > stats.medianHours then
            breakdown[#breakdown + 1] = "Über Neu-Einstellungen hinweg gebunden: "
                .. Opportunity:FormatHours(stats.medianHoldHours)
        end
        if stats.salesPerWeek then
            breakdown[#breakdown + 1] = string.format("Verkäufe je Woche: %.1f",
                stats.salesPerWeek)
        end
        breakdown[#breakdown + 1] = " "
        breakdown[#breakdown + 1] = "Dein Einkauf (Median): "
            .. (stats.medianBuyPrice and Prices:FormatMoney(stats.medianBuyPrice) or "–")
        breakdown[#breakdown + 1] = "Dein Verkauf netto (Median): "
            .. (stats.medianSellPrice and Prices:FormatMoney(stats.medianSellPrice) or "–")
        breakdown[#breakdown + 1] = "Realisierte Marge: " .. signedPercentText(stats.realizedMargin)
        if stats.costBasisKnown and stats.realizedProfit then
            breakdown[#breakdown + 1] = string.format("Realisierter Gewinn: %s%s",
                stats.realizedProfit >= 0 and "+" or "",
                Prices:FormatMoney(stats.realizedProfit))
            breakdown[#breakdown + 1] = string.format(
                "= %s Nettoerlös – %s Einkauf (gewichteter Durchschnitt) – %s Gebühren",
                Prices:FormatMoney(stats.matchedRevenueNet),
                Prices:FormatMoney(stats.attributableCost or 0),
                Prices:FormatMoney(stats.depositLost))
        elseif stats.costBasisCoverage then
            breakdown[#breakdown + 1] = string.format(
                "Realisierter Gewinn: unbekannt – nur %.0f %% der verkauften Stücke "
                .. "haben einen belegten Einkaufspreis. Selbst gefarmte oder "
                .. "hergestellte Ware bekommt keine Kostenbasis 0.",
                stats.costBasisCoverage * 100)
        end
        breakdown[#breakdown + 1] = " "
        if stats.liquidityScore then
            breakdown[#breakdown + 1] = string.format("Liquidity Score: %d/100  (%s)",
                stats.liquidityScore, band or "–")
            local parts = stats.liquidityParts or {}
            breakdown[#breakdown + 1] = string.format(
                "Sell-through %.1f + Geschwindigkeit %s + Wiederholung %s von %d möglichen Punkten",
                parts.sellThrough or 0,
                parts.speed and string.format("%.1f", parts.speed) or "–",
                parts.repetition and string.format("%.1f", parts.repetition) or "–",
                parts.availableWeight or 0)
        else
            breakdown[#breakdown + 1] = "Liquidity Score: noch keiner – "
                .. "ohne stückzahlbasierte Sell-through-Rate gibt es keine Aussage."
        end
        if stats.openPostings > 0 then
            breakdown[#breakdown + 1] = string.format("Aktuell offen: %d Einstellung(en)",
                stats.openPostings)
        end
        breakdown[#breakdown + 1] = " "
        breakdown[#breakdown + 1] = "Alle Zahlen stammen aus deinen eigenen, bestätigten "
            .. "Auktionshaus-Vorgängen und bleiben lokal."

        line.data = {
            itemID = row.itemID,
            title = row.name,
            breakdown = breakdown,
            watchable = row.itemID,
            watchReason = "Handel-Tab",
        }
        if row.icon then
            line.icon:SetTexture(row.icon)
            line.icon:Show()
        end
        local color = qualityColors[row.quality or 1] or "|cffffffff"
        line.text:SetText(string.format("%s%s|r", color,
            row.name or ("Item " .. row.itemID)))

        line.cols[5]:SetText(tostring(stats.soldQuantity))
        line.cols[4]:SetText(tostring(stats.expiredQuantity))
        if stats.sellThrough then
            line.cols[3]:SetText(percentText(stats.sellThrough))
        elseif stats.sellThroughAuctions then
            line.cols[3]:SetText(percentText(stats.sellThroughAuctions) .. "*")
            line.cols[3]:SetTextColor(rgb(COLOR.textDim))
        else
            line.cols[3]:SetText("–")
        end
        line.cols[2]:SetText(stats.medianHours
            and Opportunity:FormatHours(stats.medianHours) or "–")
        line.cols[1]:SetText(signedPercentText(stats.realizedMargin))
        if stats.realizedMargin then
            line.cols[1]:SetTextColor(rgb(stats.realizedMargin >= 0 and COLOR.green or COLOR.red))
        end

        if stats.liquidityScore then
            line.value:SetTextColor(rgb(liquidityColor(stats.liquidityScore)))
            line.value:SetText(tostring(stats.liquidityScore))
        else
            line.value:SetTextColor(rgb(COLOR.textDim))
            line.value:SetText("–")
        end
        if stats.openPostings > 0 then
            line.pill:Set(string.format("%d offen", stats.openPostings), COLOR.accent)
        end
        if stats.confidence == "high" then
            line.autoPill:Set("sicher", COLOR.green)
        elseif stats.confidence == "medium" then
            line.autoPill:Set("mittel", COLOR.accent)
        else
            line.autoPill:Set("wenig Daten", COLOR.textDim)
        end
        finishLedgerRow(line)
    end

    if #report.rows == 0 then
        index = index + 1
        local row = self:AddDataRow(index)
        row.text:SetText("Noch kein Item mit auswertbarer Handelsgeschichte.")
        finishRow(row)
    end

    index = index + 1
    local note = self:AddDataRow(index)
    note.text:SetTextColor(rgb(COLOR.textDim))
    note.text:SetText("Zurückgezogene Auktionen zählen nicht als Fehlschlag. Ein * bei "
        .. "der Sell-through-Rate heißt: je Auktion statt je Stück, weil zu einem "
        .. "Verkauf keine Einstellung gefunden wurde.")
    finishRow(note)

    local lifetime = report.lifetime
    local truncatedText = report.truncated > 0
        and string.format(" · %d weitere nicht angezeigt", report.truncated) or ""
    self.frame.summary:SetText(string.format(
        "Gold Copilot kennt %d Item(s) aus deinem Handel   ·   "
        .. "|cff8a8a94%d Verkauf/Verkäufe · %s Umsatz netto insgesamt%s|r",
        report.total, lifetime.sales, Prices:FormatGold(lifetime.revenueNet), truncatedText))
    self.frame.ledgerSortButton:SetLabel(LEDGER_SORT_LABEL[sortMode] or "Sortierung")
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

    -- Die Chancen filtern nach zwei Groessen statt einer: absoluter Gewinn und
    -- Kapitaleffizienz. Bewusst eigene Optionen - der Mindestgewinn des
    -- Tagesplans bleibt davon unberuehrt.
    local oppHeading = optionHeading(panel, "Chancen: Mindestprofit", minNote, -20)
    panel.oppProfitButtons = {}
    local oppProfitDefs = {
        { value = 0, label = "aus" },
        { value = 10000, label = "1 g" },
        { value = 50000, label = "5 g" },
        { value = 100000, label = "10 g" },
        { value = 250000, label = "25 g" },
        { value = 500000, label = "50 g" },
    }
    previous = nil
    for _, def in ipairs(oppProfitDefs) do
        local button = createFlatButton(panel, def.label, 76, 24)
        if previous then
            button:SetPoint("LEFT", previous, "RIGHT", 6, 0)
        else
            button:SetPoint("TOPLEFT", oppHeading, "BOTTOMLEFT", 0, -8)
        end
        button:SetScript("OnClick", function()
            GCP.db.options.opportunityMinProfit = def.value
            GCP.Opportunity:Invalidate()
            UI:Refresh()
        end)
        panel.oppProfitButtons[def.value] = button
        previous = button
    end

    local roiHeading = optionHeading(panel, "Chancen: Mindest-ROI",
        panel.oppProfitButtons[0], -20)
    panel.oppROIButtons = {}
    local oppROIDefs = {
        { value = 0, label = "aus" },
        { value = 0.05, label = "5 %" },
        { value = 0.10, label = "10 %" },
        { value = 0.20, label = "20 %" },
        { value = 0.30, label = "30 %" },
    }
    previous = nil
    for _, def in ipairs(oppROIDefs) do
        local button = createFlatButton(panel, def.label, 76, 24)
        if previous then
            button:SetPoint("LEFT", previous, "RIGHT", 6, 0)
        else
            button:SetPoint("TOPLEFT", roiHeading, "BOTTOMLEFT", 0, -8)
        end
        button:SetScript("OnClick", function()
            GCP.db.options.opportunityMinROI = def.value
            GCP.Opportunity:Invalidate()
            UI:Refresh()
        end)
        panel.oppROIButtons[def.value] = button
        previous = button
    end

    local oppNote = createText(panel, 11, COLOR.textDim)
    oppNote:SetPoint("TOPLEFT", panel.oppROIButtons[0], "BOTTOMLEFT", 0, -6)
    oppNote:SetText("Gilt nur für den Chancen-Tab. ROI = theoretischer Gewinn geteilt durch Kapitaleinsatz.")

    local goalHeading = optionHeading(panel, "Tagesziel", oppNote, -20)
    panel.goalButtons = {}
    local goalDefs = {
        { value = 0, label = "aus" },
        { value = 1000000, label = "100 g" },
        { value = 2500000, label = "250 g" },
        { value = 5000000, label = "500 g" },
        { value = 10000000, label = "1.000 g" },
        { value = 25000000, label = "2.500 g" },
    }
    previous = nil
    for _, def in ipairs(goalDefs) do
        local button = createFlatButton(panel, def.label, 88, 24)
        if previous then
            button:SetPoint("LEFT", previous, "RIGHT", 6, 0)
        else
            button:SetPoint("TOPLEFT", goalHeading, "BOTTOMLEFT", 0, -8)
        end
        button:SetScript("OnClick", function()
            GCP.db.options.dailyGoal = def.value
            UI:Refresh()
        end)
        panel.goalButtons[def.value] = button
        previous = button
    end

    local goalNote = createText(panel, 11, COLOR.textDim)
    goalNote:SetPoint("TOPLEFT", panel.goalButtons[0], "BOTTOMLEFT", 0, -6)
    goalNote:SetText("Der Tab „Heute“ zeigt dann den schnellsten Weg dorthin – Aufgaben nach Gold je Minute sortiert.")

    local keepHeading = optionHeading(panel, "Eigenbedarf", goalNote, -20)
    panel.keepButton = createFlatButton(panel, "Verbrauchbares behalten", 220, 24)
    panel.keepButton:SetPoint("TOPLEFT", keepHeading, "BOTTOMLEFT", 0, -8)
    panel.keepButton:SetScript("OnClick", function()
        GCP.db.options.keepConsumables = not GCP.db.options.keepConsumables
        UI:Refresh()
    end)
    local keepNote = createText(panel, 11, COLOR.textDim)
    keepNote:SetPoint("TOPLEFT", panel.keepButton, "BOTTOMLEFT", 0, -6)
    keepNote:SetText("An: Tränke, Elixiere und Essen werden nie zum Verkauf vorgeschlagen – ihr Wert steht trotzdem im Verkaufen-Tab.")

    local dataHeading = optionHeading(panel, "Daten", keepNote, -20)
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
        "· Der Tooltip nennt zu jeder Empfehlung die Preisbasis: 0 Tageswerte = Momentanpreis,",
        "  1–2 = wenig Daten, 3–5 = mittlere, 6–7 = gute Datenbasis.",
        "· Markt-Tab: eigene Markthistorie, höchstens ein Preispunkt je Item und 30 Minuten,",
        "  30 Tage aufbewahrt. Der Market Score sagt nur, wie günstig der aktuelle Preis",
        "  gegenüber deiner eigenen Historie ist – nichts über Nachfrage oder Liquidität.",
        "· Chancen-Tab: Opportunity Score aus Kapitaleffizienz (ROI), absoluter Größe des",
        "  Gewinns, Market Score der Kaufseite und Datenqualität, abzüglich Volatilitäts- und",
        "  Kapitalrisiko. Eine dünne Datenlage deckelt ihn hart (niedrig 55, mittel 80).",
        "  ROI = theoretischer Gewinn geteilt durch Kapitaleinsatz.",
        "· Resale rechnet mit einem konservativen Zielpreis: min(7-Tage-Median, 30-Tage-Median),",
        "  davon 5 % AH-Gebühr. Liquidität und Verkaufsdauer kennt auch 0.6 noch nicht.",
        "· Entzaubern: Datenquelle ist Auctionators Entzauberwert – eigene Dropchancen werden",
        "  nicht geschätzt. Die AH-Gebühr fällt einmal an, beim Verkauf der Materialien.",
        "· Craft-Ausbeute bei Zufallsmenge: Mittelwert aus Minimum und Maximum.",
        "· Zutaten zählen zum Marktpreis, auch wenn du sie besitzt (sie hätten verkauft werden können).",
        "· Farm-Tipps: Marktpreis × konservativ geschätzte Sammelrate pro Stunde.",
        "· Questbelohnungen zählen mit max(AH netto, Händlerpreis) – ohne Marktpreis bleibt der",
        "  Händlerwert; bei Auswahlbelohnungen zählt nur die beste.",
        "· Der Tagesplan setzt sich am WoW-Daily-Reset zurück, nicht um lokale Mitternacht.",
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
    for value, button in pairs(panel.oppProfitButtons) do
        button:SetActive(options.opportunityMinProfit == value)
    end
    for value, button in pairs(panel.oppROIButtons) do
        button:SetActive(options.opportunityMinROI == value)
    end
    for value, button in pairs(panel.goalButtons) do
        button:SetActive(options.dailyGoal == value)
    end
    panel.keepButton:SetActive(options.keepConsumables)
    panel.keepButton:SetLabel(options.keepConsumables
        and "Verbrauchbares behalten" or "Verbrauchbares mitverkaufen")
    local ignoredCount = 0
    for _ in pairs(options.ignored or {}) do ignoredCount = ignoredCount + 1 end
    local professionCount, recipeCount = 0, 0
    for _, data in pairs(GCP.db.recipes or {}) do
        professionCount = professionCount + 1
        recipeCount = recipeCount + #(data.list or {})
    end
    local observedCount = 0
    for _ in pairs(GCP.db.priceHistory or {}) do observedCount = observedCount + 1 end
    local learnedQuests = 0
    for _ in pairs(GCP.db.questGold or {}) do learnedQuests = learnedQuests + 1 end
    local Market = GCP.Market
    local market = Market:GetOverview()
    local knowledgeSummary = GCP.Knowledge:Summary()
    local futureGraph = GCP.Future:GetGraph()
    local ledger = GCP.Ledger:GetOverview()
    panel.dataText:SetText(table.concat({
        string.format("Rezepte: %d aus %d Beruf(en) – Berufsfenster öffnen aktualisiert sie.",
            recipeCount, professionCount),
        string.format("Preisverlauf: %d Items in Beobachtung (14 Tage).", observedCount),
        string.format("Markthistorie: %d beobachtete Märkte, %s Preispunkte, %d Tag(e), ~%s"
            .. " – Auctionator-Callback %s.",
            market.itemsWithHistory, Market:FormatCount(market.snapshots), market.spanDays,
            Market:FormatBytes(Market:EstimateBytes()),
            market.callback and "aktiv" or "nicht verfügbar"),
        string.format("Quest-Gold: %d echte Beträge gelernt (Rest sind Schätzungen).", learnedQuests),
        string.format("Beobachtungsliste: %d Item(s) – Rechtsklick im Markt- oder "
            .. "Chancen-Tab nimmt eines auf.", Market:CountWatchItems()),
        string.format("Chancen-Protokoll: %d Einträge (90 Tage) – Grundlage für "
            .. "spätere Treffsicherheits-Auswertungen.", #(GCP.db.opportunityHistory or {})),
        -- Die persoenliche Handelsbilanz gehoert sichtbar hierher, samt dem
        -- Satz, dass sie den Rechner nicht verlaesst.
        string.format("Handelsbilanz: %s Ereignisse (60 Tage) über %d Item(s), "
            .. "%d offene Einstellung(en), ~%s. Erfassung: %s, Briefkasten %s. "
            .. "Alles bleibt lokal – nichts wird übertragen.",
            Market:FormatCount(ledger.events), ledger.items, ledger.openPostings,
            Market:FormatBytes(GCP.Ledger:EstimateBytes()),
            ledger.hooked and "Einstell-Hook aktiv" or "Einstell-Hook nicht eingehängt",
            ledger.mailScanAt and "gelesen" or "noch nicht geöffnet"),
        -- Der Wissensstand gehoert sichtbar in die Optionen: Er ist das einzige
        -- Datum im Addon, das nicht mitwaechst, sondern mit einem Update kommt.
        string.format("Wissensbasis: Stand %s – %d Phasen, %d Catalysts, %d Rezeptkanten. "
            .. "Wird mit dem Addon ausgeliefert, keine Abfragen aus dem Netz.",
            GCP.Knowledge.VERSION_LABEL, knowledgeSummary.phases,
            knowledgeSummary.catalysts, futureGraph.edgeCount),
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
    local isMarket = self.activeTab == "market"
    local isChancen = self.activeTab == "chancen"
    local isZukunft = self.activeTab == "zukunft"
    local isHandel = self.activeTab == "handel"
    local isOptions = self.activeTab == "options"
    -- Im Markt-Tab bleibt von der Werkzeugleiste nur "Aktualisieren" stehen:
    -- Umfang, Filter und Bestandsknöpfe haben dort keine Bedeutung.
    frame.toolbar:SetShown(isSell or isCrafts or isMarket or isChancen
        or isZukunft or isHandel)
    frame.scopeButton:SetShown(isSell)
    frame.filterButton:SetShown(isSell)
    frame.boundButton:SetShown(isSell)
    frame.ignoredButton:SetShown(isSell)
    frame.craftableButton:SetShown(isCrafts)
    frame.watchButton:SetShown(isChancen or isZukunft)
    frame.opportunitySortButton:SetShown(isChancen)
    frame.ledgerSortButton:SetShown(isHandel)
    frame.refreshButton:Show()
    frame.progress:Hide()
    frame.progressLabel:Hide()
    frame.scroll:SetShown(not isOptions)
    frame.optionsScroll:SetShown(isOptions)

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
    elseif isMarket then
        self:RenderMarket()
    elseif isChancen then
        self:RenderChancen()
    elseif isZukunft then
        self:RenderZukunft()
    elseif isHandel then
        self:RenderHandel()
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
