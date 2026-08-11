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

-- ---------------------------------------------------------------------------
-- Layoutraster
--
-- Bis 1.0.0-beta.1 stand jeder Abstand einzeln im Code - mal 4, mal 6, mal 14
-- Pixel, je nachdem wann die Stelle entstanden ist. Das Ergebnis war ein
-- gedraengtes Fenster mit ungleichen Kanten. Seitdem kommen alle Abstaende aus
-- diesen sechs Zahlen. Wer es luftiger oder enger will, dreht hier - nicht an
-- zweihundert SetPoint-Aufrufen.
-- ---------------------------------------------------------------------------
local PAD = 18          -- Abstand zum Fensterrand
local INSET = 16        -- Innenabstand einer Flaeche
local GAP = 8           -- Abstand zweier Elemente nebeneinander
local BLOCK_GAP = 14    -- Abstand zweier Bloecke untereinander
local TEXT_GAP = 10     -- Abstand zwischen Beschriftung und Inhalt
local LINE_SPACING = 4  -- Zeilenabstand innerhalb eines mehrzeiligen Textes

-- Zeilen der Listen-Tabs. 30 statt der frueheren 26 Pixel: Bei 12-Punkt-Schrift
-- blieben oben und unten je 7 Pixel Luft, jetzt sind es 9 - genug, dass sich
-- zwei Zeilen nicht mehr beruehren.
local ROW_HEIGHT = 30
local SECTION_HEIGHT = 38
-- Innenabstand einer Listenzeile und Abstand zweier Zahlenspalten. Links
-- stehen Haken, Symbol und Text in drei festen Spalten - sonst wandert der
-- Text je nach Zeileninhalt hin und her.
local ROW_EDGE = 12
local COL_GAP = 12
local ROW_ICON_LEFT = 32
local ROW_TEXT_LEFT = 64

-- 1.0.0-beta.2: Elf Tabs und fuenf Kapitalkacheln nebeneinander brauchen
-- Breite, das Command Center braucht Hoehe. 1000x700 passt weiterhin in die
-- 768 Einheiten hohe Standardoberflaeche, und das Fenster ist am Bildschirm
-- geklemmt.
local FRAME_WIDTH = 1000
local FRAME_HEIGHT = 700

-- Senkrechter Aufbau der Kopfzeile: Titel, Trennlinie bei 64, Tableiste bei 76
-- (28 hoch), Werkzeugleiste bei 118 (26 hoch), Statuszeile bei 158. Darunter
-- beginnt der Inhalt.
local TABBAR_BOTTOM = 104
local SCROLL_TOP = 180
local SCROLLBAR_WIDTH = 16
local CONTENT_WIDTH = FRAME_WIDTH - PAD - (PAD + SCROLLBAR_WIDTH)

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
local OPTIONS_PANEL_HEIGHT = 1900

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
    -- Mehrzeilige Texte bekommen ihren Zeilenabstand hier ein einziges Mal.
    -- Einzeilige merken davon nichts.
    text:SetSpacing(LINE_SPACING)
    return text
end

-- Flacher Button mit Hover und aktivem Zustand (goldene Unterlinie).
local function createFlatButton(parent, label, width, height)
    local button = CreateFrame("Button", nil, parent)
    button:SetSize(width or 120, height or 26)
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
    -- Ein Knopf, der nichts bewirken kann, sagt das auch. Enable/Disable allein
    -- reicht dafuer nicht: Diese Knoepfe haben keine Schrift fuer den
    -- deaktivierten Zustand, also wird die Beschriftung von Hand abgedunkelt.
    function button:SetDisabled(disabled)
        self.disabled = disabled and true or false
        if disabled then
            self:Disable()
            self.label:SetTextColor(COLOR.border[1], COLOR.border[2], COLOR.border[3])
        else
            self:Enable()
            if not self.active then
                self.label:SetTextColor(COLOR.textDim[1], COLOR.textDim[2], COLOR.textDim[3])
            end
        end
    end
    return button
end

-- Kleines farbiges Etikett ("Pill") fuer Kanal, Empfehlung oder Bestand.
local function createPill(parent)
    local pill = CreateFrame("Frame", nil, parent)
    pill:SetHeight(18)
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
        self:SetWidth(self.text:GetStringWidth() + 18)
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
    logoFallback:SetSize(32, 32)
    logoFallback:SetPoint("TOPLEFT", PAD, -16)
    logoFallback:SetTexture("Interface\\Icons\\INV_Misc_Coin_02")
    logoFallback:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    local logo = frame:CreateTexture(nil, "OVERLAY")
    logo:SetSize(38, 38)
    logo:SetPoint("CENTER", logoFallback, "CENTER", 0, 0)
    logo:SetTexture(LOGO)
    frame.logo = logo

    local title = createText(frame, 19, COLOR.accent, false, "")
    title:SetPoint("TOPLEFT", PAD + 44, -16)
    title:SetText("Gold Copilot")

    local version = createText(frame, 11, COLOR.textDim)
    version:SetPoint("BOTTOMLEFT", title, "BOTTOMRIGHT", 10, 1)
    version:SetText("v" .. GCP.Constants.VERSION)

    local trend = createText(frame, 11, COLOR.textDim)
    trend:SetPoint("TOPLEFT", PAD + 44, -42)
    trend:SetJustifyH("LEFT")
    frame.trend = trend

    local source = createText(frame, 11, COLOR.textDim)
    source:SetPoint("TOPRIGHT", -(PAD + 34), -22)
    source:SetJustifyH("RIGHT")
    frame.source = source

    local close = CreateFrame("Button", nil, frame)
    close:SetSize(26, 26)
    close:SetPoint("TOPRIGHT", -10, -10)
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
    headerLine:SetPoint("TOPLEFT", PAD - 4, -64)
    headerLine:SetPoint("TOPRIGHT", -(PAD - 4), -64)
    headerLine:SetHeight(1)

    -- Tab-Leiste
    frame.tabs = {}
    local tabDefs = {
        -- 0.9.0: Die Zentrale steht vorn und ist der Normalfall. Alles
        -- dahinter bleibt unveraendert bestehen - das ist der Expertenmodus.
        { key = "zentrale", label = "Zentrale" },
        { key = "route", label = "Route" },
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
    -- Elf Tabs in einer Leiste sind die engste Reihe des Fensters und deshalb
    -- die einzige mit einem eigenen, kleineren Abstand: 2 x 18 Rand +
    -- 11 x 82 + 10 x 5 = 988 und damit knapp unter der Fensterbreite.
    local TAB_WIDTH, TAB_GAP = 82, 5
    local previous
    for _, def in ipairs(tabDefs) do
        local tab = createFlatButton(frame, def.label, TAB_WIDTH, 28)
        if previous then
            tab:SetPoint("LEFT", previous, "RIGHT", TAB_GAP, 0)
        else
            tab:SetPoint("TOPLEFT", PAD, -76)
        end
        tab:SetScript("OnClick", function()
            UI:SelectTab(def.key)
        end)
        frame.tabs[def.key] = tab
        previous = tab
    end

    -- Werkzeugleiste (nur Verkaufen- und Crafts-Tab)
    local toolbar = CreateFrame("Frame", nil, frame)
    toolbar:SetPoint("TOPLEFT", PAD, -118)
    toolbar:SetPoint("TOPRIGHT", -PAD, -118)
    toolbar:SetHeight(26)
    frame.toolbar = toolbar

    frame.scopeButton = createFlatButton(toolbar, "Umfang: Account", 150, 26)
    frame.scopeButton:SetPoint("LEFT")
    frame.scopeButton:SetScript("OnClick", function()
        UI.scope = UI.scope == "account" and "bags" or "account"
        UI:Refresh()
    end)

    frame.filterButton = createFlatButton(toolbar, "Filter: Alles", 140, 26)
    frame.filterButton:SetPoint("LEFT", frame.scopeButton, "RIGHT", GAP, 0)
    frame.filterButton:SetScript("OnClick", function()
        local order = { all = "mats", mats = "gear", gear = "all" }
        UI.filter = order[UI.filter or "all"]
        UI:Refresh()
    end)

    frame.boundButton = createFlatButton(toolbar, "Gebundenes: an", 140, 26)
    frame.boundButton:SetPoint("LEFT", frame.filterButton, "RIGHT", GAP, 0)
    frame.boundButton:SetScript("OnClick", function()
        GCP.db.options.hideBound = not GCP.db.options.hideBound
        UI:Refresh()
    end)

    frame.ignoredButton = createFlatButton(toolbar, "Ignoriert (0)", 130, 26)
    frame.ignoredButton:SetPoint("LEFT", frame.boundButton, "RIGHT", GAP, 0)
    frame.ignoredButton:SetScript("OnClick", function()
        UI.showIgnored = not UI.showIgnored
        UI:Refresh()
    end)

    frame.craftableButton = createFlatButton(toolbar, "Nur machbare: aus", 160, 26)
    frame.craftableButton:SetPoint("LEFT")
    frame.craftableButton:SetScript("OnClick", function()
        UI.onlyCraftable = not UI.onlyCraftable
        UI:Refresh()
    end)

    -- Beobachtung: zeigt die Groesse der Watchlist und schaltet die Ansicht auf
    -- genau diese Items um. Aufgenommen wird per Rechtsklick auf eine Zeile.
    frame.watchButton = createFlatButton(toolbar, "Beobachtung (0)", 170, 26)
    frame.watchButton:SetPoint("LEFT")
    frame.watchButton:SetScript("OnClick", function()
        UI.onlyWatched = not UI.onlyWatched
        UI:Refresh()
    end)

    -- Sortierung (0.8.0). Zwei getrennte Knoepfe, weil es zwei getrennte Listen
    -- mit verschiedenen Kriterien sind - ein gemeinsamer waere im jeweils
    -- anderen Tab beschriftet, aber wirkungslos.
    frame.opportunitySortButton = createFlatButton(toolbar, "Sortierung", 220, 26)
    frame.opportunitySortButton:SetPoint("LEFT", frame.watchButton, "RIGHT", GAP, 0)
    frame.opportunitySortButton:SetScript("OnClick", function()
        GCP.Opportunity:CycleSortMode()
        GCP.Opportunity:Invalidate()
        UI:Refresh()
    end)

    frame.ledgerSortButton = createFlatButton(toolbar, "Sortierung", 220, 26)
    frame.ledgerSortButton:SetPoint("LEFT")
    frame.ledgerSortButton:SetScript("OnClick", function()
        local order = { liquidity = "profit", profit = "sales", sales = "liquidity" }
        GCP.db.options.ledgerSort = order[GCP.db.options.ledgerSort or "liquidity"]
            or "liquidity"
        UI:Refresh()
    end)

    frame.refreshButton = createFlatButton(toolbar, "Aktualisieren", 120, 26)
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
        -- Auch der geplante Routenvorschlag ist ein Zwischenstand. Ohne diese
        -- drei Zeilen zeigte der Route-Tab nach dem Klick weiter denselben
        -- Plan: Er wurde einmal berechnet und danach nur noch angezeigt.
        UI.plannedRoute = nil
        UI.plannedSignature = nil
        UI.plannedAt = nil

        -- Laeuft eine Route, sind ihre Schritte gespeichert - ein Neuzeichnen
        -- aendert daran nichts, und genau deshalb sah dieser Knopf bis
        -- 1.0.0-beta.5 wirkungslos aus. Jetzt plant er den REST mit den
        -- frischen Preisen neu und behaelt das Erledigte. Findet sich kein
        -- besserer Plan, bleibt die Route stehen - und das steht dann auch da,
        -- statt dass gar nichts passiert.
        local progress = GCP.Guide:Progress()
        local state = progress and progress.state
        if progress and progress.steps > 0
            and state ~= "IDLE" and state ~= "COMPLETED" then
            local replanned, why = GCP.Guide:RequestReplan("manual")
            UI.refreshNote = replanned
                and "Route mit frischen Preisen neu geplant."
                or ("Route unverändert – " .. (why or "kein besserer Plan gefunden"))
            UI:RefreshGuide()
        else
            UI.refreshNote = nil
        end
        UI:Refresh()
    end)

    -- Nur im Route-Tab. Verwirft eine abgeschlossene oder abgebrochene Route
    -- und plant von vorn - der Weg, den es bis 1.0.0-beta.2 nur ueber die
    -- Zentrale gab. Bei laufender Route fragt er einmal nach; siehe
    -- UI:PlanNewRoute.
    frame.newRouteButton = createFlatButton(toolbar, "Neue Route", 160, 26)
    frame.newRouteButton:SetPoint("LEFT")
    frame.newRouteButton:SetScript("OnClick", function()
        UI:PlanNewRoute()
    end)

    -- Status: Zusammenfassung links, Tagesfortschritt rechts
    local summary = createText(frame, 12, COLOR.text)
    summary:SetPoint("TOPLEFT", PAD + 2, -158)
    summary:SetJustifyH("LEFT")
    frame.summary = summary

    local progressLabel = createText(frame, 11, COLOR.textDim, true)
    progressLabel:SetPoint("TOPRIGHT", -(PAD + 182), -158)
    frame.progressLabel = progressLabel

    local progress = CreateFrame("Frame", nil, frame)
    progress:SetSize(170, 8)
    progress:SetPoint("TOPRIGHT", -PAD, -160)
    applyBackdrop(progress, COLOR.panel, COLOR.border)
    progress.fill = progress:CreateTexture(nil, "ARTWORK")
    progress.fill:SetTexture(WHITE)
    progress.fill:SetVertexColor(rgb(COLOR.accent))
    progress.fill:SetPoint("TOPLEFT", 1, -1)
    progress.fill:SetPoint("BOTTOMLEFT", 1, 1)
    progress.fill:SetWidth(1)
    frame.progress = progress

    -- Scrollbereich. Rechts bleibt neben dem Fensterrand die Breite der
    -- Bildlaufleiste frei, sonst klebt sie an der letzten Zahlenspalte.
    local scroll = CreateFrame("ScrollFrame", "GoldCopilotScrollFrame", frame, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", PAD, -SCROLL_TOP)
    scroll:SetPoint("BOTTOMRIGHT", -(PAD + SCROLLBAR_WIDTH), PAD)
    local content = CreateFrame("Frame", nil, scroll)
    content:SetSize(CONTENT_WIDTH, 100)
    scroll:SetScrollChild(content)
    frame.scroll = scroll
    frame.content = content

    -- Optionen als eigenes Panel statt Zeilenliste. Seit 0.6.0 in einem
    -- eigenen Scrollbereich: Mit den Chancen-Filtern reicht die Fensterhoehe
    -- nicht mehr fuer alle Abschnitte, und ein abgeschnittener Erklaertext ist
    -- schlimmer als eine Bildlaufleiste.
    local optionsScroll = CreateFrame("ScrollFrame", "GoldCopilotOptionsScrollFrame",
        frame, "UIPanelScrollFrameTemplate")
    optionsScroll:SetPoint("TOPLEFT", PAD, -SCROLL_TOP)
    optionsScroll:SetPoint("BOTTOMRIGHT", -(PAD + SCROLLBAR_WIDTH), PAD)
    frame.optionsPanel = self:BuildOptionsPanel(optionsScroll)
    frame.optionsPanel:SetSize(CONTENT_WIDTH, OPTIONS_PANEL_HEIGHT)
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

    -- Command Center (0.9.0). Eigene Flaeche statt Zeilenliste: Die Startseite
    -- ist keine Tabelle, sondern eine Antwort.
    frame.commandPanel = self:BuildCommandPanel(frame)
    frame.commandPanel:SetPoint("TOPLEFT", PAD, -(TABBAR_BOTTOM + BLOCK_GAP))
    frame.commandPanel:SetPoint("BOTTOMRIGHT", -PAD, PAD)
    frame.commandPanel:Hide()

    self.frame = frame
    self.rows = {}
    self.scope = "account"
    self.filter = "all"
    self.activeTab = "zentrale"
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

    -- Ablehnen (1.0.0-beta.4). Ein Item, das man nicht will, verschwindet aus
    -- allen Chancen und aus jeder kuenftigen Route - und die Route wird sofort
    -- neu geplant. Das ist die Antwort auf "der Guide schlaegt immer dasselbe
    -- vor": Ohne eine Moeglichkeit abzulehnen hat der Planer bei gleicher
    -- Datenlage auch keine andere Wahl.
    --
    -- Auf Alt gelegt, weil der einfache Rechtsklick im Chancen- und Markt-Tab
    -- schon die Watchlist bedient. Ein Klick, der je nach Tab etwas anderes
    -- taete, waere schlimmer als ein Zusatztaste.
    if data.rejectable and mouseButton == "RightButton" and IsAltKeyDown() then
        UI:ToggleRejected(data.rejectable)
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
    row.sectionLine:SetPoint("BOTTOMLEFT", 2, 6)
    row.sectionLine:SetPoint("BOTTOMRIGHT", -2, 6)
    row.sectionLine:SetHeight(1)

    row:EnableMouse(true)
    row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    row:SetScript("OnEnter", rowOnEnter)
    row:SetScript("OnLeave", rowOnLeave)
    row:SetScript("OnClick", rowOnClick)

    -- Eigene flache Checkbox
    row.check = CreateFrame("Button", nil, row)
    row.check:SetSize(16, 16)
    row.check:SetPoint("LEFT", ROW_EDGE - 4, 0)
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
    row.icon:SetSize(22, 22)
    row.icon:SetPoint("LEFT", ROW_ICON_LEFT, 0)
    row.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)

    row.text = createText(row, 12, COLOR.text)
    row.text:SetPoint("LEFT", ROW_TEXT_LEFT, 0)
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
    row.textLeft = ROW_TEXT_LEFT
    row:SetHeight(ROW_HEIGHT)
    row.zebraTex:Show()
    row.sectionLine:Hide()
    row.check:Hide()
    row.check.mark:Hide()
    row.icon:SetTexture(nil)
    row.icon:Hide()
    -- Der Chancen-Tab haengt das Symbol hinter die Score-Spalte um. Ohne diese
    -- Zeile behaelt eine Zeile aus dem gemeinsamen Pool diesen Anker im
    -- naechsten Tab bei - und das Symbol liegt dort auf dem ersten Buchstaben
    -- des Itemnamens.
    row.icon:ClearAllPoints()
    row.icon:SetPoint("LEFT", ROW_ICON_LEFT, 0)
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
    -- Aus demselben Grund wie beim Symbol: Der Chancen-Tab setzt hier eine
    -- feste Spaltenbreite, die sonst in jeden folgenden Tab mitwandert.
    row.typeText:SetWidth(0)
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
    local used = ROW_EDGE
    row.value:ClearAllPoints()
    row.value:SetPoint("RIGHT", -ROW_EDGE, 0)
    local valueText = row.value:GetText()
    if valueText and valueText ~= "" then
        used = used + row.value:GetStringWidth() + COL_GAP
    end

    local noteText = row.value2:GetText()
    if noteText and noteText ~= "" then
        row.value2:ClearAllPoints()
        row.value2:SetPoint("RIGHT", -used, 0)
        used = used + row.value2:GetStringWidth() + COL_GAP
    end

    if row.pill:IsShown() then
        row.pill:ClearAllPoints()
        row.pill:SetPoint("RIGHT", -used, 0)
        used = used + row.pill:GetWidth() + COL_GAP
    end

    if row.autoPill:IsShown() then
        row.autoPill:ClearAllPoints()
        row.autoPill:SetPoint("RIGHT", -used, 0)
        used = used + row.autoPill:GetWidth() + COL_GAP
    end

    row.text:ClearAllPoints()
    row.text:SetPoint("LEFT", row.textLeft, row.isHeader and -3 or 0)
    row.text:SetPoint("RIGHT", -used, 0)
end

-- Zeilenabschluss des Markt-Tabs: feste Spaltenbreiten statt der sonst
-- inhaltsabhaengigen Ausrichtung, damit die Zahlen untereinander stehen.
local function finishMarketRow(row)
    local used = ROW_EDGE
    row.value:ClearAllPoints()
    row.value:SetPoint("RIGHT", -used, 0)
    row.value:SetWidth(MARKET_SCORE_WIDTH)
    used = used + MARKET_SCORE_WIDTH + COL_GAP
    for column = 1, #MARKET_COLUMNS do
        local text = row.cols[column]
        text:ClearAllPoints()
        text:SetPoint("RIGHT", -used, 0)
        text:SetWidth(MARKET_COLUMNS[column])
        used = used + MARKET_COLUMNS[column] + COL_GAP
    end
    -- Etiketten stehen links der Zahlenspalten; sie sind die einzigen Elemente
    -- hier mit inhaltsabhaengiger Breite, deshalb kommen sie zuletzt.
    if row.pill:IsShown() then
        row.pill:ClearAllPoints()
        row.pill:SetPoint("RIGHT", -used, 0)
        used = used + row.pill:GetWidth() + COL_GAP
    end
    if row.autoPill:IsShown() then
        row.autoPill:ClearAllPoints()
        row.autoPill:SetPoint("RIGHT", -used, 0)
        used = used + row.autoPill:GetWidth() + COL_GAP
    end
    row.text:ClearAllPoints()
    row.text:SetPoint("LEFT", row.textLeft, row.isHeader and -3 or 0)
    row.text:SetPoint("RIGHT", -used, 0)
end

-- Zeilenabschluss des Chancen-Tabs. Der Score sitzt links, danach Icon und
-- Art der Chance mit fester Breite; die Aktion bekommt den Rest, die drei
-- Zahlenspalten stehen rechts untereinander.
local function finishOpportunityRow(row)
    local scoreLeft = ROW_EDGE
    local iconLeft = scoreLeft + OPPORTUNITY_SCORE_WIDTH + COL_GAP
    local typeLeft = iconLeft + 22 + GAP

    row.value:ClearAllPoints()
    row.value:SetPoint("LEFT", scoreLeft, 0)
    row.value:SetWidth(OPPORTUNITY_SCORE_WIDTH)
    row.value:SetJustifyH("LEFT")

    row.icon:ClearAllPoints()
    row.icon:SetPoint("LEFT", iconLeft, 0)

    row.typeText:ClearAllPoints()
    row.typeText:SetPoint("LEFT", typeLeft, row.isHeader and -3 or 0)
    row.typeText:SetWidth(OPPORTUNITY_TYPE_WIDTH)

    local used = ROW_EDGE
    for column = 1, #OPPORTUNITY_COLUMNS do
        local text = row.cols[column]
        text:ClearAllPoints()
        text:SetPoint("RIGHT", -used, 0)
        text:SetWidth(OPPORTUNITY_COLUMNS[column])
        used = used + OPPORTUNITY_COLUMNS[column] + COL_GAP
    end
    if row.pill:IsShown() then
        row.pill:ClearAllPoints()
        row.pill:SetPoint("RIGHT", -used, 0)
        used = used + row.pill:GetWidth() + COL_GAP
    end
    if row.autoPill:IsShown() then
        row.autoPill:ClearAllPoints()
        row.autoPill:SetPoint("RIGHT", -used, 0)
        used = used + row.autoPill:GetWidth() + COL_GAP
    end

    row.text:ClearAllPoints()
    row.text:SetPoint("LEFT", typeLeft + OPPORTUNITY_TYPE_WIDTH + COL_GAP,
        row.isHeader and -3 or 0)
    row.text:SetPoint("RIGHT", -used, 0)
end

-- Zeilenabschluss des Zukunft-Tabs. Wie im Markt-Tab feste Spaltenbreiten,
-- damit die drei Kennzahlen untereinander stehen und sich vergleichen lassen -
-- nur mit einer Textspalte fuer den Catalyst dazwischen.
local function finishFutureRow(row)
    local used = ROW_EDGE
    row.value:ClearAllPoints()
    row.value:SetPoint("RIGHT", -used, 0)
    row.value:SetWidth(FUTURE_SCORE_WIDTH)
    used = used + FUTURE_SCORE_WIDTH + COL_GAP
    for column = 1, #FUTURE_COLUMNS do
        local text = row.cols[column]
        text:ClearAllPoints()
        text:SetPoint("RIGHT", -used, 0)
        text:SetWidth(FUTURE_COLUMNS[column])
        used = used + FUTURE_COLUMNS[column] + COL_GAP
    end
    if row.pill:IsShown() then
        row.pill:ClearAllPoints()
        row.pill:SetPoint("RIGHT", -used, 0)
        used = used + row.pill:GetWidth() + COL_GAP
    end
    if row.autoPill:IsShown() then
        row.autoPill:ClearAllPoints()
        row.autoPill:SetPoint("RIGHT", -used, 0)
        used = used + row.autoPill:GetWidth() + COL_GAP
    end
    row.text:ClearAllPoints()
    row.text:SetPoint("LEFT", row.textLeft, row.isHeader and -3 or 0)
    row.text:SetPoint("RIGHT", -used, 0)
end

-- Zeilenabschluss des Handel-Tabs. Wie im Markt-Tab feste Spaltenbreiten - nur
-- mit fuenf Zahlenspalten statt vier, damit sich Sell-through, Verkaufszeit und
-- Marge zeilenweise vergleichen lassen.
local function finishLedgerRow(row)
    local used = ROW_EDGE
    row.value:ClearAllPoints()
    row.value:SetPoint("RIGHT", -used, 0)
    row.value:SetWidth(LEDGER_SCORE_WIDTH)
    used = used + LEDGER_SCORE_WIDTH + COL_GAP
    for column = 1, #LEDGER_COLUMNS do
        local text = row.cols[column]
        text:ClearAllPoints()
        text:SetPoint("RIGHT", -used, 0)
        text:SetWidth(LEDGER_COLUMNS[column])
        used = used + LEDGER_COLUMNS[column] + COL_GAP
    end
    if row.pill:IsShown() then
        row.pill:ClearAllPoints()
        row.pill:SetPoint("RIGHT", -used, 0)
        used = used + row.pill:GetWidth() + COL_GAP
    end
    if row.autoPill:IsShown() then
        row.autoPill:ClearAllPoints()
        row.autoPill:SetPoint("RIGHT", -used, 0)
        used = used + row.autoPill:GetWidth() + COL_GAP
    end
    row.text:ClearAllPoints()
    row.text:SetPoint("LEFT", row.textLeft, row.isHeader and -3 or 0)
    row.text:SetPoint("RIGHT", -used, 0)
end

function UI:AddHeaderRow(index, text, value)
    local row = self:AcquireRow(index)
    resetRow(row)
    row.isHeader = true
    row.textLeft = ROW_EDGE - 4
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
    content:SetHeight(math.max(y + BLOCK_GAP, 100))
end

-- ---------------------------------------------------------------------------
-- COMMAND CENTER (0.9.0)
--
-- Die Startseite beantwortet genau eine Frage: WAS SOLL ICH JETZT TUN?
--
-- Oben stehen fuenf Zahlen zum Kapital, darunter die beste Aktion mit einem
-- Knopf, darunter der Zielmodus. Keine Tabelle, keine Sortierung, keine
-- Filter - die gibt es alle noch, aber in den Tabs dahinter.
-- ---------------------------------------------------------------------------

local KPI_KEYS = {
    { key = "gold", label = "Gold" },
    { key = "free", label = "Frei verfügbar" },
    { key = "invested", label = "Investiert" },
    { key = "today", label = "Heute realisiert" },
    { key = "potential", label = "Offenes Potenzial" },
}

local GOAL_PRESETS = { 2500000, 5000000, 10000000, 25000000 }
local RISK_DEFS = {
    { key = "low", label = "Niedrig" },
    { key = "medium", label = "Mittel" },
    { key = "high", label = "Hoch" },
}
local ACTIVITY_DEFS = {
    { key = "craft", label = "Crafting" },
    { key = "conversion", label = "Conversion" },
    { key = "resale", label = "Trading" },
    { key = "disenchant", label = "Entzaubern" },
    { key = "farm", label = "Farmen" },
}
local QUICK_PROFILES = {
    { key = "QUICK_GOLD", label = "Schnelles Gold" },
    { key = "GROW_CAPITAL", label = "Kapital aufbauen" },
    { key = "FUTURE_INVESTING", label = "Zukunft" },
    { key = "CRAFTING", label = "Crafting" },
    { key = "TRADING", label = "Handel" },
    { key = "FARMING", label = "Farmen" },
}

-- Senkrechter Bauplan des Command Centers. Die Summe aus Kachelhoehe, den
-- Hoehen der drei Flaechen und vier Blockabstaenden muss in die Panelhoehe
-- passen (Fensterhoehe minus Kopfzeile minus Rand): 56 + 144 + 250 + 28 + 28
-- + 4 x 14 = 562 bei 564 verfuegbaren Pixeln.
local KPI_HEIGHT = 56
local BEST_HEIGHT = 144
local GOAL_HEIGHT = 250
local QUICK_HEIGHT = 28
local FARM_HEIGHT = 28
-- Breite der Beschriftungsspalte im Zielmodus. Vorher hingen die Knopfreihen
-- an der Breite ihrer eigenen Beschriftung - "Aktivitäten" ist laenger als
-- "Zeit", also begann jede Reihe an einer anderen Stelle. Eine feste Spalte
-- stellt sie untereinander.
local GOAL_LABEL_WIDTH = 104

function UI:BuildCommandPanel(parent)
    local panel = CreateFrame("Frame", nil, parent)
    -- Alles, was der Willkommensschirm beim ersten Start verdeckt.
    panel.blocks = {}

    -- --- Kapitalzeile ------------------------------------------------------
    -- Fuenf gleich breite Kacheln ueber die volle Breite statt fester 176
    -- Pixel: So bleibt rechts kein angebrochener Rest stehen.
    local panelWidth = FRAME_WIDTH - 2 * PAD
    local kpiWidth = math.floor((panelWidth - (#KPI_KEYS - 1) * GAP) / #KPI_KEYS)
    panel.kpi = {}
    local previous
    for _, def in ipairs(KPI_KEYS) do
        local box = CreateFrame("Frame", nil, panel)
        box:SetSize(kpiWidth, KPI_HEIGHT)
        applyBackdrop(box, COLOR.panel, COLOR.border)
        if previous then
            box:SetPoint("LEFT", previous, "RIGHT", GAP, 0)
        else
            box:SetPoint("TOPLEFT", 0, 0)
        end
        box.caption = createText(box, 10, COLOR.textDim)
        box.caption:SetPoint("TOPLEFT", 12, -10)
        box.caption:SetText(def.label)
        box.value = createText(box, 16, COLOR.text, true)
        box.value:SetPoint("BOTTOMLEFT", 12, 12)
        box.value:SetText("–")
        panel.kpi[def.key] = box
        panel.blocks[#panel.blocks + 1] = box
        previous = box
    end

    -- --- Beste Aktion ------------------------------------------------------
    -- Rechts stehen zwei Knoepfe, links vier Textzeilen. Die Texte enden
    -- deshalb vor der Knopfspalte, statt unter ihr durchzulaufen.
    local BEST_BUTTON_WIDTH = 190
    local best = CreateFrame("Frame", nil, panel)
    best:SetPoint("TOPLEFT", panel.kpi.gold, "BOTTOMLEFT", 0, -BLOCK_GAP)
    best:SetPoint("RIGHT", panel, "RIGHT", 0, 0)
    best:SetHeight(BEST_HEIGHT)
    applyBackdrop(best, COLOR.panel, COLOR.border)
    local textRight = -(INSET + BEST_BUTTON_WIDTH + INSET)
    best.caption = createText(best, 11, COLOR.accent)
    best.caption:SetPoint("TOPLEFT", INSET, -INSET)
    best.caption:SetText("BESTE AKTION JETZT")
    best.title = createText(best, 17, COLOR.text)
    best.title:SetPoint("TOPLEFT", INSET, -38)
    best.title:SetPoint("RIGHT", best, "RIGHT", textRight, 0)
    best.title:SetJustifyH("LEFT")
    best.title:SetWordWrap(false)
    best.detail = createText(best, 12, COLOR.textDim)
    best.detail:SetPoint("TOPLEFT", INSET, -66)
    best.detail:SetPoint("RIGHT", best, "RIGHT", textRight, 0)
    best.detail:SetJustifyH("LEFT")
    best.numbers = createText(best, 12, COLOR.text, true)
    best.numbers:SetPoint("TOPLEFT", INSET, -100)
    best.numbers:SetJustifyH("LEFT")
    best.note = createText(best, 11, COLOR.textDim)
    best.note:SetPoint("BOTTOMLEFT", INSET, TEXT_GAP + 2)
    -- Rechte Grenze wie bei Titel und Detail: Die Notiz liegt auf derselben
    -- Hoehe wie die unterste Zeile der Knopfspalte und lief seit
    -- 1.0.0-beta.6 unter sie, weil ihr als einziger Zeile die Begrenzung fehlte.
    best.note:SetPoint("RIGHT", best, "RIGHT", textRight, 0)
    best.note:SetJustifyH("LEFT")
    best.startButton = createFlatButton(best, "ROUTE STARTEN", BEST_BUTTON_WIDTH, 30)
    best.startButton:SetPoint("TOPRIGHT", -INSET, -INSET)
    best.startButton:SetScript("OnClick", function() UI:StartRouteFromGoal() end)
    best.guideButton = createFlatButton(best, "Guide anzeigen", BEST_BUTTON_WIDTH, 26)
    best.guideButton:SetPoint("TOPRIGHT", best.startButton, "BOTTOMRIGHT", 0, -GAP)
    -- "Guide anzeigen" macht die Route auch laufen. Ein Guide-Fenster ohne
    -- laufende Route ist eine Anzeige ohne Inhalt, und zwei Knoepfe fuer einen
    -- Vorgang ("ROUTE FORTSETZEN", dann "Guide anzeigen") sind einer zu viel.
    -- Das Zumachen bleibt reines Zumachen: Wer das Fenster schliesst, will die
    -- Route nicht abbrechen.
    best.guideButton:SetScript("OnClick", function() UI:ShowGuideAndRun() end)

    -- Mengenwahl (1.0.0-beta.6). Das Addon schlaegt eine Stueckzahl vor, aber ob
    -- man auf zwanzig Roben sitzenbleiben will, entscheidet niemand ausser dem
    -- Spieler. Kapital, Potenzial und ROI rechnen live mit.
    --
    -- Sie steht in der rechten Knopfspalte unter "Route starten" und nicht links
    -- unter den Zahlen: Der senkrechte Bauplan des Command Centers ist auf zwei
    -- Pixel genau ausgereizt (siehe BEST_HEIGHT), links waere keine Zeile mehr
    -- frei gewesen - der erste Versuch lag prompt auf der Routennotiz. Rechts
    -- endet die Knopfspalte bei -80 und laesst 60 Pixel uebrig.
    --
    -- Bewusst hier und nicht im laufenden Guide: Mitten in der Route waere eine
    -- Mengenaenderung ein Eingriff in einen Abhaengigkeitsgraphen - kaufe 20,
    -- stelle 10 her, verkaufe 10 - und wuerde die Folgeschritte falsch machen,
    -- statt sie anzupassen.
    --
    -- Breite von rechts: 26 (+) + 8 + 38 (Zahl) + 8 + 26 (-) + 8 + Beschriftung
    -- = 149 von 190 verfuegbaren Pixeln.
    best.amountPlus = createFlatButton(best, "+", 26, 22)
    best.amountPlus:SetPoint("TOPRIGHT", best.guideButton, "BOTTOMRIGHT", 0, -GAP)
    best.amountPlus:SetScript("OnClick", function() UI:StepManualUnits(1) end)

    best.amountValue = createText(best, 13, COLOR.text, true)
    best.amountValue:SetPoint("RIGHT", best.amountPlus, "LEFT", -GAP, 0)
    best.amountValue:SetWidth(38)
    best.amountValue:SetJustifyH("CENTER")

    best.amountMinus = createFlatButton(best, "-", 26, 22)
    best.amountMinus:SetPoint("RIGHT", best.amountValue, "LEFT", -GAP, 0)
    best.amountMinus:SetScript("OnClick", function() UI:StepManualUnits(-1) end)

    best.amountLabel = createText(best, 11, COLOR.textDim)
    best.amountLabel:SetPoint("RIGHT", best.amountMinus, "LEFT", -GAP, 0)
    best.amountLabel:SetText("Menge")

    best.amountReset = createFlatButton(best, "Vorschlag", 190, 22)
    best.amountReset:SetPoint("TOPRIGHT", best.amountPlus, "BOTTOMRIGHT", 0, -GAP / 2)
    best.amountReset:SetScript("OnClick", function()
        if UI.bestKey then UI:SetManualUnits(UI.bestKey, nil) end
    end)

    panel.best = best
    panel.blocks[#panel.blocks + 1] = best

    -- --- Zielmodus ---------------------------------------------------------
    -- Vier Reihen aus Beschriftung und Knoepfen. Die Reihen haengen an festen
    -- Hoehen statt aneinander: Ein Textfeld ist zwei Pixel hoeher als das
    -- naechste, und diese zwei Pixel summierten sich frueher ueber vier Reihen
    -- zu schiefen Abstaenden.
    local GOAL_ROW_HEIGHT = 26
    local GOAL_ROW_GAP = 12
    local goalRowTop = {}
    for index = 1, 4 do
        goalRowTop[index] = 48 + (index - 1) * (GOAL_ROW_HEIGHT + GOAL_ROW_GAP)
    end
    -- Die Beschriftung sitzt mittig zur Knopfreihe daneben.
    local labelDrop = math.floor((GOAL_ROW_HEIGHT - 14) / 2)

    local goal = CreateFrame("Frame", nil, panel)
    goal:SetPoint("TOPLEFT", best, "BOTTOMLEFT", 0, -BLOCK_GAP)
    goal:SetPoint("RIGHT", panel, "RIGHT", 0, 0)
    goal:SetHeight(GOAL_HEIGHT)
    applyBackdrop(goal, COLOR.panel, COLOR.border)
    goal.caption = createText(goal, 11, COLOR.accent)
    goal.caption:SetPoint("TOPLEFT", INSET, -INSET)
    goal.caption:SetText("WAS MÖCHTEST DU ERREICHEN?")

    goal.goalLabel = createText(goal, 12, COLOR.textDim)
    goal.goalLabel:SetPoint("TOPLEFT", INSET, -(goalRowTop[1] + labelDrop))
    goal.goalLabel:SetText("Goldziel")
    goal.goalButtons = {}
    previous = nil
    for _, amount in ipairs(GOAL_PRESETS) do
        local button = createFlatButton(goal, GCP.Prices:FormatGold(amount), 104, GOAL_ROW_HEIGHT)
        if previous then
            button:SetPoint("LEFT", previous, "RIGHT", GAP, 0)
        else
            button:SetPoint("TOPLEFT", INSET + GOAL_LABEL_WIDTH, -goalRowTop[1])
        end
        button:SetScript("OnClick", function()
            GCP.db.options.goalAmount = amount
            UI:Refresh()
        end)
        goal.goalButtons[amount] = button
        previous = button
    end
    -- Freies Feld daneben: Wer ein anderes Ziel hat, soll es eintragen koennen.
    -- Eingegeben wird in Gold; intern rechnet alles in Kupfer.
    local input = CreateFrame("EditBox", nil, goal, "InputBoxTemplate")
    input:SetSize(84, 22)
    input:SetPoint("LEFT", previous, "RIGHT", INSET, 0)
    input:SetAutoFocus(false)
    input:SetMaxLetters(7)
    input:SetScript("OnEnterPressed", function(self)
        local text = self.GetText and self:GetText() or nil
        local value = tonumber(text)
        if value and value > 0 then
            GCP.db.options.goalAmount = math.floor(value * 10000)
        end
        if self.ClearFocus then self:ClearFocus() end
        UI:Refresh()
    end)
    input:SetScript("OnEscapePressed", function(self)
        if self.ClearFocus then self:ClearFocus() end
    end)
    goal.goalInput = input
    goal.goalInputLabel = createText(goal, 11, COLOR.textDim)
    goal.goalInputLabel:SetPoint("LEFT", input, "RIGHT", GAP, 0)
    goal.goalInputLabel:SetText("g (eigenes Ziel, Enter)")

    goal.timeLabel = createText(goal, 12, COLOR.textDim)
    goal.timeLabel:SetPoint("TOPLEFT", INSET, -(goalRowTop[2] + labelDrop))
    goal.timeLabel:SetText("Zeit")
    goal.timeButtons = {}
    previous = nil
    for _, minutes in ipairs(GCP.Constants.GUIDE.TIME_PRESETS) do
        -- Volle Stunden als "1h", alles andere in Minuten. "1,5h" liest
        -- niemand gern, "90m" schon.
        local label = (minutes >= 60 and minutes % 60 == 0)
            and string.format("%dh", math.floor(minutes / 60))
            or (minutes .. "m")
        local button = createFlatButton(goal, label, 104, GOAL_ROW_HEIGHT)
        if previous then
            button:SetPoint("LEFT", previous, "RIGHT", GAP, 0)
        else
            button:SetPoint("TOPLEFT", INSET + GOAL_LABEL_WIDTH, -goalRowTop[2])
        end
        button:SetScript("OnClick", function()
            GCP.db.options.goalMinutes = minutes
            UI:Refresh()
        end)
        goal.timeButtons[minutes] = button
        previous = button
    end

    goal.riskLabel = createText(goal, 12, COLOR.textDim)
    goal.riskLabel:SetPoint("TOPLEFT", INSET, -(goalRowTop[3] + labelDrop))
    goal.riskLabel:SetText("Risiko")
    goal.riskButtons = {}
    previous = nil
    for _, def in ipairs(RISK_DEFS) do
        local button = createFlatButton(goal, def.label, 104, GOAL_ROW_HEIGHT)
        if previous then
            button:SetPoint("LEFT", previous, "RIGHT", GAP, 0)
        else
            button:SetPoint("TOPLEFT", INSET + GOAL_LABEL_WIDTH, -goalRowTop[3])
        end
        button:SetScript("OnClick", function()
            GCP.db.options.goalRisk = def.key
            UI:Refresh()
        end)
        goal.riskButtons[def.key] = button
        previous = button
    end

    goal.activityLabel = createText(goal, 12, COLOR.textDim)
    goal.activityLabel:SetPoint("TOPLEFT", INSET, -(goalRowTop[4] + labelDrop))
    goal.activityLabel:SetText("Aktivitäten")
    goal.activityButtons = {}
    previous = nil
    for _, def in ipairs(ACTIVITY_DEFS) do
        local button = createFlatButton(goal, def.label, 128, GOAL_ROW_HEIGHT)
        if previous then
            button:SetPoint("LEFT", previous, "RIGHT", GAP, 0)
        else
            button:SetPoint("TOPLEFT", INSET + GOAL_LABEL_WIDTH, -goalRowTop[4])
        end
        button:SetScript("OnClick", function()
            local types = GCP.db.options.goalTypes
            types[def.key] = not types[def.key]
            UI:Refresh()
        end)
        goal.activityButtons[def.key] = button
        previous = button
    end

    goal.createButton = createFlatButton(goal, "GOLD ROUTE ERSTELLEN", 230, 30)
    goal.createButton:SetPoint("BOTTOMLEFT", INSET, INSET)
    goal.createButton:SetScript("OnClick", function() UI:PlanRouteFromGoal() end)

    goal.capitalNote = createText(goal, 11, COLOR.textDim)
    goal.capitalNote:SetPoint("LEFT", goal.createButton, "RIGHT", INSET, 0)
    goal.capitalNote:SetPoint("RIGHT", goal, "RIGHT", -INSET, 0)
    goal.capitalNote:SetJustifyH("LEFT")
    panel.goal = goal
    panel.blocks[#panel.blocks + 1] = goal

    -- --- Schnellprofile ----------------------------------------------------
    -- Sechs Knoepfe ueber die volle Breite, gleich breit wie die Kacheln oben.
    local quickWidth = math.floor((panelWidth - (#QUICK_PROFILES - 1) * GAP) / #QUICK_PROFILES)
    local quick = CreateFrame("Frame", nil, panel)
    quick:SetPoint("TOPLEFT", goal, "BOTTOMLEFT", 0, -BLOCK_GAP)
    quick:SetPoint("RIGHT", panel, "RIGHT", 0, 0)
    quick:SetHeight(QUICK_HEIGHT)
    panel.quickButtons = {}
    previous = nil
    for _, def in ipairs(QUICK_PROFILES) do
        local button = createFlatButton(quick, def.label, quickWidth, QUICK_HEIGHT)
        if previous then
            button:SetPoint("LEFT", previous, "RIGHT", GAP, 0)
        else
            button:SetPoint("TOPLEFT", 0, 0)
        end
        button:SetScript("OnClick", function()
            UI:PlanRouteFromGoal(def.key)
        end)
        panel.quickButtons[def.key] = button
        previous = button
    end
    panel.quick = quick
    panel.blocks[#panel.blocks + 1] = quick

    -- --- Farmsitzung -------------------------------------------------------
    -- Farmraten entstehen nur aus gemessenen Sitzungen. Damit sie ueberhaupt
    -- entstehen koennen, braucht es einen sichtbaren Knopf - nicht nur einen
    -- Slash-Befehl, den niemand findet.
    local farm = CreateFrame("Frame", nil, panel)
    farm:SetPoint("TOPLEFT", quick, "BOTTOMLEFT", 0, -BLOCK_GAP)
    farm:SetPoint("RIGHT", panel, "RIGHT", 0, 0)
    farm:SetHeight(FARM_HEIGHT)
    farm.button = createFlatButton(farm, "Farmsitzung starten", 190, FARM_HEIGHT)
    farm.button:SetPoint("TOPLEFT", 0, 0)
    farm.button:SetScript("OnClick", function()
        if GCP.Farm:Current() then
            GCP.Farm:Stop("manuell")
        else
            GCP.Farm:Start(nil, nil)
        end
        UI:Refresh()
    end)
    farm.text = createText(farm, 11, COLOR.textDim)
    farm.text:SetPoint("LEFT", farm.button, "RIGHT", INSET, 0)
    farm.text:SetPoint("RIGHT", farm, "RIGHT", 0, 0)
    farm.text:SetJustifyH("LEFT")
    panel.farm = farm
    panel.blocks[#panel.blocks + 1] = farm

    -- --- Willkommen (erster Start) -----------------------------------------
    -- Der Schirm liegt ueber der ganzen Flaeche. "Darueber" allein reicht
    -- nicht: Gleichrangige Frames zeichnen ihre Schriften ueber jeden
    -- Hintergrund derselben Ebene, der Begruessungstext lag deshalb mitten in
    -- den Zahlen dahinter. Er bekommt jetzt eine eigene, hoehere Ebene - und
    -- die Bloecke dahinter werden zusaetzlich weggeblendet, damit auch ein
    -- halbdurchsichtiger Hintergrund nichts durchscheinen laesst.
    local welcome = CreateFrame("Frame", nil, panel)
    welcome:SetAllPoints()
    welcome:SetFrameLevel((panel:GetFrameLevel() or 0) + 10)
    applyBackdrop(welcome, COLOR.bg, COLOR.border)
    welcome.title = createText(welcome, 20, COLOR.accent)
    welcome.title:SetPoint("TOPLEFT", 32, -32)
    welcome.title:SetText("Willkommen bei Gold Copilot.")
    welcome.body = createText(welcome, 13, COLOR.text)
    welcome.body:SetPoint("TOPLEFT", 32, -78)
    welcome.body:SetPoint("RIGHT", welcome, "RIGHT", -32, 0)
    welcome.body:SetJustifyH("LEFT")
    welcome.body:SetText(
        "Gold Copilot lernt deinen Realm und deine persönlichen Handelsdaten.\n\n"
        .. "Für bessere Empfehlungen:\n"
        .. "  1. Auctionator verwenden\n"
        .. "  2. das Auktionshaus regelmäßig scannen\n"
        .. "  3. normal handeln – Kauf, Verkauf und Ablauf werden erfasst\n"
        .. "  4. Gold Copilot sammelt alles lokal in deinen SavedVariables\n\n"
        .. "Nichts davon verlässt deinen Rechner. Solange Daten fehlen, sagt\n"
        .. "Gold Copilot das – es erfindet keine Zahlen.")
    -- Der Knopf haengt am Text, nicht an einer festen Hoehe: Uebersetzungen
    -- und Schriftgroessen aendern die Zeilenzahl, ein fester Abstand von 250
    -- Pixeln haette den Knopf dann in den Text geschoben.
    welcome.button = createFlatButton(welcome, "Los geht's", 190, 30)
    welcome.button:SetPoint("TOPLEFT", welcome.body, "BOTTOMLEFT", 0, -32)
    welcome.button:SetScript("OnClick", function()
        GCP.db.options.seenWelcome = true
        UI:Refresh()
    end)
    welcome:Hide()
    panel.welcome = welcome

    -- Entweder der Willkommensschirm oder die Zentrale - nie beides.
    function panel:SetWelcome(shown)
        self.welcome:SetShown(shown)
        for _, block in ipairs(self.blocks) do
            block:SetShown(not shown)
        end
    end

    return panel
end

-- Die Vorgaben des Zielmodus, so wie sie der Planer braucht.
function UI:GoalOptions(profile)
    local options = GCP.db.options
    local types = {}
    local any = false
    for key, enabled in pairs(options.goalTypes or {}) do
        if enabled then
            types[key] = true
            any = true
        end
    end
    return {
        profile = profile or "CUSTOM",
        goal = options.goalAmount,
        minutes = options.goalMinutes,
        risk = options.goalRisk,
        types = any and types or nil,
        -- Eigene Stueckzahlen je Chance. Laufzeitzustand, keine Einstellung:
        -- Eine Menge gilt fuer diese eine Route, nicht auf Dauer.
        unitLimits = self.manualUnits,
    }
end

-- Die Menge der gerade angezeigten besten Aktion um delta veraendern. Basis ist
-- die zuletzt gezeigte Stueckzahl, egal ob sie vom Nutzer oder vom Addon kam -
-- so faengt "+1" dort an, wo der Vorschlag aufgehoert hat.
function UI:StepManualUnits(delta)
    if not self.bestKey then return false end
    local current = (self.manualUnits and self.manualUnits[self.bestKey])
        or self.bestUnits or 1
    return self:SetManualUnits(self.bestKey, current + delta)
end

-- Vom Nutzer gewaehlte Stueckzahl fuer eine Chance setzen oder loeschen.
-- key ist der Schluessel der Chance ("craft:23571"), nil setzt zurueck auf den
-- Vorschlag des Addons.
function UI:SetManualUnits(key, units)
    if type(key) ~= "string" then return false end
    self.manualUnits = self.manualUnits or {}
    if type(units) ~= "number" or units < 1 then
        self.manualUnits[key] = nil
    else
        self.manualUnits[key] = math.floor(math.min(units, 999))
    end
    -- Der Vorschlag muss neu gerechnet werden, sonst zeigt die Zentrale
    -- weiterhin Kapital und Potenzial der alten Menge.
    self.plannedRoute = nil
    self.plannedSignature = nil
    self.plannedAt = nil
    self:Refresh()
    return true
end

function UI:PlanRouteFromGoal(profile)
    local route = GCP.Route:Plan(self:GoalOptions(profile))
    self.plannedRoute = route
    self.plannedProfile = profile
    self.plannedSignature = nil
    self.plannedAt = (type(GetTime) == "function" and GetTime()) or 0
    self:SelectTab("route")
    return route
end

-- Ein Item ablehnen oder wieder zulassen. Eigene Liste, nicht die des
-- Verkaufen-Tabs - die Begruendung steht in Core.lua bei options.rejected.
--
-- Wichtig ist, was danach passiert: Chancen-Cache verwerfen und den geplanten
-- Vorschlag wegwerfen. Sonst zeigt die Oberflaeche weiter die Route, in der das
-- gerade abgelehnte Item noch steht.
function UI:ToggleRejected(itemID)
    if type(itemID) ~= "number" then return false end
    local list = GCP.db.options.rejected
    list[itemID] = (not list[itemID]) or nil
    local rejected = list[itemID] and true or false
    local name = (GetItemInfo and GetItemInfo(itemID)) or ("Item " .. itemID)
    GCP.Opportunity:Invalidate()
    self.plannedRoute = nil
    self.plannedSignature = nil
    self.plannedAt = nil
    GCP:Print(rejected
        and string.format("%s abgelehnt – kommt in keiner Chance und keiner "
            .. "Route mehr vor. (Optionen: „Abgelehnte Items zurücksetzen“)", name)
        or string.format("%s wieder zugelassen.", name))
    self:Refresh()
    return rejected
end

-- "Neue Route": Eine abgeschlossene oder abgebrochene Route wird verworfen und
-- der Plan neu gerechnet. Eine LAUFENDE Route bleibt ausdruecklich stehen -
-- sie wegzuwerfen, weil jemand einen Knopf in der Werkzeugleiste drueckt, waere
-- der teuerste Fehler dieses Fensters. Wer sie wirklich beenden will, hat dafuer
-- "Route abbrechen" im Guide.
-- Wie lange die Nachfrage von "Neue Route" scharf bleibt. Dasselbe Muster wie
-- beim Ausblenden einer Zeile: kein Popup, sondern ein Knopf, der einmal
-- nachfragt.
local NEW_ROUTE_CONFIRM_SECONDS = 5

function UI:PlanNewRoute(profile)
    local progress = GCP.Guide:Progress()
    local state = progress and progress.state
    local running = progress and progress.steps > 0
        and state ~= "IDLE" and state ~= "COMPLETED"

    -- Eine laufende Route wegzuwerfen kostet den Fortschritt einer Sitzung.
    -- Bis 1.0.0-beta.5 lehnte dieser Knopf deshalb stillschweigend ab - mit
    -- einer Chatzeile, die man leicht uebersieht, und einem Knopf, der aussah,
    -- als sei er kaputt. Jetzt fragt er einmal nach und tut es dann.
    if running then
        local now = (type(GetTime) == "function" and GetTime()) or 0
        if not self.newRouteArmedAt
            or (now - self.newRouteArmedAt) > NEW_ROUTE_CONFIRM_SECONDS then
            self.newRouteArmedAt = now
            GCP:Print(string.format(
                "Es läuft eine Route (%d von %d Schritten erledigt). Nochmal "
                .. "„Neue Route“ klicken ersetzt sie – der Fortschritt geht "
                .. "dabei verloren.", progress.done, progress.steps))
            self:Refresh()
            return nil
        end
        self.newRouteArmedAt = nil
        if GCP.Personal then GCP.Personal:RecordRouteAborted() end
    end
    -- Eine fertige Route hat ihren Zweck erfuellt; ihre Schritte stehen dem
    -- naechsten Plan nur im Weg.
    if progress and progress.steps > 0 then GCP.Guide:Abort() end
    self.plannedRoute = nil
    self.plannedSignature = nil
    self.plannedAt = nil
    GCP.Opportunity:Invalidate()
    local route = GCP.Route:Plan(self:GoalOptions(profile or self.plannedProfile))
    self.plannedRoute = route
    self.plannedProfile = profile or self.plannedProfile
    self.plannedAt = (type(GetTime) == "function" and GetTime()) or 0
    self:RefreshGuide()
    self:SelectTab("route")
    return route
end

function UI:StartRouteFromGoal(profile)
    local route, problem = GCP.Guide:Start(self:GoalOptions(profile))
    self.plannedRoute = route
    if GCP.Personal then GCP.Personal:RecordRouteStarted() end
    if route and #route.steps > 0 then
        self:ShowGuideViewer()
    elseif problem then
        GCP:Print(problem)
    end
    self:SelectTab("route")
    return route
end

function UI:RenderZentrale()
    local panel = self.frame.commandPanel
    local Prices = GCP.Prices
    local options = GCP.db.options

    -- Erster Start: nur der Willkommenstext, sonst nichts.
    if not options.seenWelcome then
        panel:SetWelcome(true)
        self.frame.summary:SetText("Gold Copilot ist bereit.")
        return
    end
    panel:SetWelcome(false)

    local snapshot = GCP.Capital:GetSnapshot()
    local today = GCP.Ledger and GCP.Ledger:GetGlobalStats(1) or nil
    panel.kpi.gold.value:SetText(Prices:FormatGold(snapshot.currentGold))
    panel.kpi.free.value:SetText(Prices:FormatGold(snapshot.availableGold))
    if snapshot.investedCapital > 0 then
        panel.kpi.invested.value:SetText(Prices:FormatGold(snapshot.investedCapital))
    elseif snapshot.openPositions > 0 then
        panel.kpi.invested.value:SetText("Einstand unbekannt")
    else
        panel.kpi.invested.value:SetText("–")
    end
    if today and today.revenueNet and today.revenueNet > 0 then
        panel.kpi.today.value:SetTextColor(rgb(COLOR.green))
        panel.kpi.today.value:SetText("+" .. Prices:FormatGold(today.revenueNet))
    else
        panel.kpi.today.value:SetTextColor(rgb(COLOR.textDim))
        panel.kpi.today.value:SetText("noch nichts")
    end

    -- Offenes Potenzial: die laufende Route, sonst der beste Plan aus dem
    -- aktuellen Ziel. Ohne belastbare Chance steht dort ein Satz, keine Null.
    local guideProgress = GCP.Guide:Progress()
    local running = guideProgress and guideProgress.steps > 0
        and guideProgress.state ~= "IDLE" and guideProgress.state ~= "COMPLETED"
    -- Die Vorschau wird nicht bei jedem Refresh neu geplant: Ein voller
    -- Planungslauf scannt Bestand, Chancen und Kapital. Neu gerechnet wird,
    -- wenn sich der Markt-, Handels- oder Kapitalstand bewegt hat - oder nach
    -- einer Frist, weil der Bestand keine Ereignisse meldet.
    local preview = self.plannedRoute
    if not running then
        local signature = table.concat({
            tostring(GCP.Market.revision or 0), tostring(GCP.Ledger.revision or 0),
            tostring(GCP.Capital.revision or 0), tostring(options.goalAmount),
            tostring(options.goalMinutes), tostring(options.goalRisk),
            tostring(self.plannedProfile),
        }, "|")
        local now = (type(GetTime) == "function" and GetTime()) or 0
        if not preview or self.plannedSignature ~= signature
            or not self.plannedAt or (now - self.plannedAt) > 30 then
            preview = GCP.Route:Plan(self:GoalOptions(self.plannedProfile))
            self.plannedRoute = preview
            self.plannedSignature = signature
            self.plannedAt = now
        end
    end

    local potential = running and guideProgress.remainingProfit
        or (preview and preview.totals.profit or 0)
    if potential and potential > 0 then
        panel.kpi.potential.value:SetTextColor(rgb(COLOR.green))
        panel.kpi.potential.value:SetText("+" .. Prices:FormatGold(potential))
    else
        panel.kpi.potential.value:SetTextColor(rgb(COLOR.textDim))
        panel.kpi.potential.value:SetText("keine Chance")
    end

    -- --- Beste Aktion ------------------------------------------------------
    local best = panel.best
    -- Die Mengenwahl gilt fuer den VORSCHLAG. Laeuft die Route schon, ist die
    -- Menge Teil eines Plans, dessen Folgeschritte darauf aufbauen - dann wird
    -- sie nicht mehr angeboten.
    local amountShown = not running
    for _, widget in ipairs({ best.amountLabel, best.amountMinus, best.amountValue,
        best.amountPlus, best.amountReset }) do
        widget:SetShown(amountShown)
    end

    if running then
        local step = GCP.Guide:CurrentStep()
        best.caption:SetText("ROUTE LÄUFT · " .. GCP.Guide:HeaderText())
        best.title:SetText(GCP.Guide:StepTitle(step))
        best.detail:SetText(step and step.detail or "")
        best.numbers:SetText(string.format("Rest: %s Potenzial · %d Schritt(e) · ca. %d Min.",
            Prices:FormatGold(guideProgress.remainingProfit),
            guideProgress.remaining, math.ceil(guideProgress.remainingMinutes)))
        best.note:SetText("Sicherheit: "
            .. GCP.Market:ConfidenceLabel(guideProgress.confidence))
        best.startButton:SetLabel("ROUTE FORTSETZEN")
        best.startButton:SetScript("OnClick", function()
            GCP.Guide:Resume()
            UI:ShowGuideViewer()
            UI:Refresh()
        end)
    else
        best.caption:SetText("BESTE AKTION JETZT")
        best.startButton:SetLabel("ROUTE STARTEN")
        best.startButton:SetScript("OnClick", function() UI:StartRouteFromGoal() end)
        local allocation = preview and preview.allocations and preview.allocations[1]
        if allocation then
            best.title:SetText(allocation.title or "–")
            best.detail:SetText(string.format("%d× · %s",
                allocation.units, GCP.Opportunity:TypeLabel(allocation.type) or "–"))
            local roi = allocation.capital > 0
                and (allocation.expectedProfit / allocation.capital) or nil
            best.numbers:SetText(string.format(
                "Kapital %s · Potenzial %s%s",
                Prices:FormatGold(allocation.capital),
                Prices:FormatGold(allocation.expectedProfit),
                roi and string.format(" · ROI %.1f %%", roi * 100) or ""))
            -- Die Mengenwahl haengt an genau dieser Chance. Der Schluessel
            -- wandert mit, damit die Knoepfe nicht die Menge eines Vorschlags
            -- verstellen, der laengst ein anderer ist.
            self.bestKey = allocation.key
            self.bestUnits = allocation.units
            best.amountValue:SetText(tostring(allocation.units))
            local manual = self.manualUnits and self.manualUnits[allocation.key]
            best.amountReset:SetDisabled(manual == nil)

            -- Woher die Menge kommt, steht in derselben Zeile wie der Rest der
            -- Routenangaben. Ein eigenes Textfeld daneben hatte im ersten
            -- Versuch schlicht keinen Platz.
            local amountNote
            if manual and allocation.units < manual then
                amountNote = string.format("|cffe05c5c%d× gewünscht, mehr geht nicht: %s|r",
                    manual, allocation.limitedBy or "Grenze erreicht")
            elseif manual then
                amountNote = "Menge von dir gewählt"
            else
                amountNote = string.format("Menge vorgeschlagen (%s)",
                    allocation.limitedBy or "Kapitalanteil")
            end
            best.note:SetText(string.format("Route: %d Schritte · ca. %d Minuten · %s · %s",
                preview.totals.steps, preview.totals.minutes,
                "Sicherheit " .. GCP.Market:ConfidenceLabel(preview.confidence),
                amountNote))
        else
            best.title:SetText("Noch keine belastbare Chance.")
            best.detail:SetText(preview and preview.warnings[1]
                or "Gold Copilot braucht Preisdaten deines Realms – "
                .. "einmal das Auktionshaus scannen genügt für den Anfang.")
            best.numbers:SetText("")
            best.note:SetText("")
            self.bestKey = nil
            self.bestUnits = nil
            for _, widget in ipairs({ best.amountLabel, best.amountMinus,
                best.amountValue, best.amountPlus, best.amountReset }) do
                widget:Hide()
            end
        end
    end

    -- --- Zielmodus ---------------------------------------------------------
    local goal = panel.goal
    for amount, button in pairs(goal.goalButtons) do
        button:SetActive(options.goalAmount == amount)
    end
    for minutes, button in pairs(goal.timeButtons) do
        button:SetActive(options.goalMinutes == minutes)
    end
    for key, button in pairs(goal.riskButtons) do
        button:SetActive(options.goalRisk == key)
    end
    for key, button in pairs(goal.activityButtons) do
        button:SetActive(options.goalTypes and options.goalTypes[key] or false)
    end
    goal.capitalNote:SetText(string.format(
        "Kapital automatisch erkannt: %s frei von %s · Reserve %s (%s)",
        Prices:FormatGold(snapshot.availableGold),
        Prices:FormatGold(snapshot.currentGold),
        Prices:FormatGold(snapshot.reservedGold), snapshot.reserveLabel))

    for key, button in pairs(panel.quickButtons) do
        button:SetActive(self.plannedProfile == key)
    end

    -- --- Farmsitzung -------------------------------------------------------
    local farmSession = GCP.Farm:Current()
    if farmSession then
        local status = GCP.Farm:Status()
        panel.farm.button:SetLabel("Farmsitzung beenden")
        panel.farm.button:SetActive(true)
        local assessment = GCP.Farm:Assess()
        panel.farm.text:SetText(string.format("%s · %d Stück in %d Minuten%s",
            tostring(status.zone), status.totalItems,
            math.floor(status.activeMinutes),
            assessment and assessment.text and ("  ·  " .. assessment.text) or ""))
    else
        panel.farm.button:SetLabel("Farmsitzung starten")
        panel.farm.button:SetActive(false)
        panel.farm.text:SetText(GCP.Farm:SummaryText())
    end

    self.frame.summary:SetText(GCP.Capital:SummaryText(snapshot))
end

-- ---------------------------------------------------------------------------
-- Route
-- ---------------------------------------------------------------------------

local STEP_COLOR = {
    GO_TO = COLOR.textDim,
    BUY = COLOR.accent,
    POST_AUCTION = COLOR.green,
    CRAFT = COLOR.text,
    CONVERT = COLOR.text,
    DISENCHANT = COLOR.text,
    FARM = COLOR.text,
}

function UI:RenderRoute()
    local Prices = GCP.Prices
    local index = 0
    local progress = GCP.Guide:Progress()
    local store = GCP:Profile().guide
    -- Eine abgeschlossene Route ist keine laufende. Bis 1.0.0-beta.2 zaehlte
    -- hier allein die Schrittzahl - damit blieb der Tab nach dem letzten
    -- Schritt fuer immer auf derselben fertigen Liste stehen, und
    -- "Aktualisieren" konnte daran nichts aendern. Die Zentrale hat diese
    -- Unterscheidung schon immer gemacht; jetzt macht der Route-Tab sie auch.
    local state = progress and progress.state
    local running = progress and progress.steps > 0
        and state ~= "IDLE" and state ~= "COMPLETED"
    local finished = progress and progress.steps > 0 and state == "COMPLETED"

    if running then
        self.frame.summary:SetText(string.format(
            "%s · %s · %d von %d Schritten erledigt · aktive Zeit %d Min.%s",
            GCP.Guide:HeaderText(), progress.stateLabel or "",
            progress.done, progress.steps, math.floor(progress.activeMinutes),
            -- Was der letzte Klick auf "Aktualisieren" bewirkt hat. Ohne diese
            -- Rueckmeldung sieht ein Neuplanungslauf, der nichts Besseres
            -- findet, genauso aus wie ein kaputter Knopf.
            self.refreshNote and ("   ·   |cff8a8a94" .. self.refreshNote .. "|r") or ""))
        index = index + 1
        self:AddHeaderRow(index, "Laufende Route", string.format(
            "Rest %s", Prices:FormatGold(progress.remainingProfit)))
        local zebra = 0
        for position, step in ipairs(store.steps) do
            index = index + 1
            zebra = zebra + 1
            local row = self:AddDataRow(index, zebra)
            local done = store.progress[step.id]
            local skipped = store.skipped[step.id]
            local why = GCP.Guide:Why(step)
            local breakdown = {}
            for _, group in ipairs({ why.context, why.positive, why.warnings, why.unknown }) do
                for _, line in ipairs(group) do breakdown[#breakdown + 1] = line end
            end
            row.data = {
                itemID = step.itemID,
                title = step.title,
                breakdown = #breakdown > 0 and breakdown or nil,
                rejectable = step.itemID,
            }
            row.check:Show()
            row.check.mark:SetShown(done ~= nil)
            local prefix = string.format("%d. ", position)
            row.text:SetText(prefix .. (step.title or step.type))
            local color = STEP_COLOR[step.type] or COLOR.text
            if done then
                row.text:SetTextColor(rgb(COLOR.textDim))
                row.autoPill:Set(done.auto and "erkannt" or "erledigt",
                    done.auto and COLOR.accent or COLOR.textDim)
            elseif skipped then
                row.text:SetTextColor(rgb(COLOR.textDim))
                row.autoPill:Set(skipped.cascade and "entfällt" or "übersprungen", COLOR.red)
            else
                row.text:SetTextColor(rgb(color))
                if position == progress.step then
                    row.autoPill:Set("jetzt", COLOR.accent)
                end
            end
            if step.capitalRequired and step.capitalRequired > 0 then
                row.value2:SetText(Prices:FormatGold(step.capitalRequired))
            end
            if step.expectedProfit and step.expectedProfit > 0 then
                row.value:SetTextColor(rgb(COLOR.green))
                row.value:SetText("+" .. Prices:FormatGold(step.expectedProfit))
            elseif step.expectedMinutes and step.expectedMinutes > 0 then
                row.value:SetTextColor(rgb(COLOR.textDim))
                row.value:SetText(string.format("%.0f min", step.expectedMinutes))
            end
            finishRow(row)
        end
        self:LayoutRows(index)
        return
    end

    -- Keine laufende Route: der zuletzt geplante Vorschlag.
    local route = self.plannedRoute
    if not route then
        route = GCP.Route:Plan(self:GoalOptions(self.plannedProfile))
        self.plannedRoute = route
        self.plannedAt = (type(GetTime) == "function" and GetTime()) or 0
    end

    -- Die letzte Route hat ihr Ende erreicht. Das gehoert obenhin, sonst sieht
    -- der neue Plan aus wie der alte, der nie weiterging.
    if finished then
        index = index + 1
        local doneRow = self:AddDataRow(index, 1)
        doneRow.text:SetTextColor(rgb(COLOR.textDim))
        doneRow.text:SetText(string.format(
            "Letzte Route abgeschlossen: %d Schritte erledigt, %d übersprungen. "
            .. "Unten steht der neue Plan – „Neue Route“ verwirft die alte.",
            progress.done, progress.skipped))
        finishRow(doneRow)
    end

    if #route.steps == 0 then
        self.frame.summary:SetText(route.summary)
        index = index + 1
        local row = self:AddDataRow(index, 1)
        row.text:SetText(route.warnings[1]
            or "Gold Copilot findet gerade keine Chance, die zu Kapital, Zeit "
            .. "und Datenlage passt.")
        finishRow(row)
        self:LayoutRows(index)
        return
    end

    self.frame.summary:SetText(route.summary)
    index = index + 1
    self:AddHeaderRow(index, "GOLD ROUTE READY", string.format("%d Schritte", #route.steps))

    index = index + 1
    local summaryRow = self:AddDataRow(index, 1)
    summaryRow.text:SetText(string.format(
        "geschätzte aktive Zeit %d Minuten · Kapitalbedarf %s · Potenzial %s · Sicherheit %s",
        route.totals.minutes, Prices:FormatGold(route.totals.capital),
        Prices:FormatGold(route.totals.profit),
        GCP.Market:ConfidenceLabel(route.confidence)))
    finishRow(summaryRow)

    if route.goal and route.goal.text then
        index = index + 1
        local goalRow = self:AddDataRow(index, 2)
        goalRow.text:SetText(route.goal.text)
        goalRow.text:SetTextColor(rgb(route.goal.reachable and COLOR.green or COLOR.red))
        finishRow(goalRow)
    end

    -- Was die Route enthaelt, in Worten.
    local byType = {}
    for _, group in ipairs(route.groups) do
        byType[group.type] = (byType[group.type] or 0) + 1
    end
    local parts = {}
    for kind, count in pairs(byType) do
        parts[#parts + 1] = string.format("%d× %s", count,
            GCP.Opportunity:TypeLabel(kind) or kind)
    end
    if #parts > 0 then
        index = index + 1
        local contentRow = self:AddDataRow(index, 3)
        contentRow.text:SetText("Enthält: " .. table.concat(parts, ", "))
        contentRow.text:SetTextColor(rgb(COLOR.textDim))
        finishRow(contentRow)
    end

    for _, warning in ipairs(route.warnings) do
        index = index + 1
        local warnRow = self:AddDataRow(index, 4)
        warnRow.text:SetText(warning)
        warnRow.text:SetTextColor(rgb(COLOR.red))
        finishRow(warnRow)
    end

    index = index + 1
    self:AddHeaderRow(index, "Schritte")

    index = index + 1
    local hintRow = self:AddDataRow(index)
    hintRow.text:SetTextColor(rgb(COLOR.textDim))
    hintRow.text:SetText("Etwas dabei, das du nicht willst? Alt + Rechtsklick auf die "
        .. "Zeile lehnt das Item ab; „Neue Route“ plant dann ohne es.")
    finishRow(hintRow)

    local zebra = 0
    for position, step in ipairs(route.steps) do
        index = index + 1
        zebra = zebra + 1
        local row = self:AddDataRow(index, zebra)
        row.data = {
            itemID = step.itemID,
            title = step.title,
            breakdown = GCP.Execution:Explain(step, nil),
            rejectable = step.itemID,
        }
        row.text:SetText(string.format("%d. %s", position, step.title or step.type))
        row.text:SetTextColor(rgb(STEP_COLOR[step.type] or COLOR.text))
        if step.capitalRequired and step.capitalRequired > 0 then
            row.value2:SetText(Prices:FormatGold(step.capitalRequired))
        end
        if step.expectedProfit and step.expectedProfit > 0 then
            row.value:SetTextColor(rgb(COLOR.green))
            row.value:SetText("+" .. Prices:FormatGold(step.expectedProfit))
        elseif step.expectedMinutes and step.expectedMinutes > 0 then
            row.value:SetTextColor(rgb(COLOR.textDim))
            row.value:SetText(string.format("%.0f min", step.expectedMinutes))
        end
        finishRow(row)
    end
    self:LayoutRows(index)
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
    self:AddHeaderRow(index, "Partikel » Urelemente  (10:1, Kombinieren ist endgültig)")
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
                    string.format("Einkauf: %d Partikel zu je %s = %s",
                        C.MOTES_PER_PRIMAL, Prices:FormatMoney(row.motePrice),
                        Prices:FormatMoney(C.MOTES_PER_PRIMAL * row.motePrice)),
                    "Verkauf netto: " .. Prices:FormatMoney(Prices:NetAuction(row.primalPrice)),
                    "Gewinn (Kauf-Flip): " .. Prices:FormatMoney(row.buyProfit),
                    "Gewinn beim Kombinieren eigener Partikel: "
                        .. Prices:FormatMoney(row.combineDelta),
                    Prices:FormatPlanningBasis(row.priceDays),
                },
            }
            if row.icon then
                line.icon:SetTexture(row.icon)
                line.icon:Show()
            end
            -- Die Zeile heisst nach dem Urelement (z. B. "Urleben"); daneben
            -- stehen der Preis eines einzelnen Partikels und der des fertigen
            -- Urelements.
            line.text:SetText(string.format("%s  |cff8a8a94Partikel %s · Urelement %s|r",
                row.name or "?", Prices:FormatGold(row.motePrice),
                Prices:FormatGold(row.primalPrice)))
            if row.ownedMotes > 0 then
                line.autoPill:Set(string.format("%d Partikel", row.ownedMotes), COLOR.accent)
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
        row.text:SetText("Keine Partikelpreise vorhanden – Auctionator-Scan nötig.")
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
        breakdown[#breakdown + 1] = "Alt + Rechtsklick: ablehnen – dieses Item "
            .. "kommt in keiner Chance und keiner Route mehr vor"
        line.data = {
            itemID = opportunity.itemID,
            title = opportunity.title,
            breakdown = breakdown,
            watchable = opportunity.itemID,
            watchReason = "Chancen-Tab",
            rejectable = opportunity.itemID,
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
                .. "Mindestprofit oder Mindest-ROI in den Optionen senken?%s",
                report.total, (report.hiddenByPrice or 0) > 0 and string.format(
                    " (%d davon wegen unbelegter Preise)", report.hiddenByPrice) or ""))
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
    -- Aussortiertes wird gezaehlt, nicht verschwiegen: Ein Filter, von dem
    -- niemand weiss, ist nicht besser als gar keiner.
    if (report.hiddenByPrice or 0) > 0 then
        notes[#notes + 1] = string.format("%d mit unbelegtem Preis ausgeblendet",
            report.hiddenByPrice)
    end
    if (report.hiddenBySupply or 0) > 0 then
        notes[#notes + 1] = string.format("%d nicht im Angebot", report.hiddenBySupply)
    end
    if (report.hiddenByIgnore or 0) > 0 then
        notes[#notes + 1] = string.format("%d von dir abgelehnt", report.hiddenByIgnore)
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
    heading:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, offsetY or -26)
    heading:SetText(text)
    return heading
end

function UI:BuildOptionsPanel(frame)
    local panel = CreateFrame("Frame", nil, frame)

    local sourceHeading = createText(panel, 13, COLOR.accent)
    sourceHeading:SetPoint("TOPLEFT", 4, -GAP)
    sourceHeading:SetText("Preisquelle")

    panel.sourceButtons = {}
    local sourceDefs = {
        { key = "auto", label = "Automatisch" },
        { key = "auctionator", label = "Nur Auctionator" },
        { key = "tsm", label = "Nur TSM" },
    }
    local previous
    for _, def in ipairs(sourceDefs) do
        local button = createFlatButton(panel, def.label, 158, 26)
        if previous then
            button:SetPoint("LEFT", previous, "RIGHT", GAP, 0)
        else
            button:SetPoint("TOPLEFT", sourceHeading, "BOTTOMLEFT", 0, -TEXT_GAP)
        end
        button:SetScript("OnClick", function()
            GCP.db.options.priceSource = def.key
            UI:Refresh()
        end)
        panel.sourceButtons[def.key] = button
        previous = button
    end

    local sourceNote = createText(panel, 11, COLOR.textDim)
    sourceNote:SetPoint("TOPLEFT", panel.sourceButtons.auto, "BOTTOMLEFT", 0, -GAP)
    sourceNote:SetJustifyH("LEFT")
    sourceNote:SetText("Automatisch: erst Auctionator-Scanpreis dieses Realms, dann TSM dbmarket.")

    local minHeading = optionHeading(panel, "Mindestgewinn für Vorschläge", sourceNote, -26)
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
        local button = createFlatButton(panel, def.label, 82, 26)
        if previous then
            button:SetPoint("LEFT", previous, "RIGHT", GAP, 0)
        else
            button:SetPoint("TOPLEFT", minHeading, "BOTTOMLEFT", 0, -TEXT_GAP)
        end
        button:SetScript("OnClick", function()
            GCP.db.options.minRoadmapValue = def.value
            UI:Refresh()
        end)
        panel.minButtons[def.value] = button
        previous = button
    end

    local minNote = createText(panel, 11, COLOR.textDim)
    minNote:SetPoint("TOPLEFT", panel.minButtons[0], "BOTTOMLEFT", 0, -GAP)
    minNote:SetText("Gilt für Tagesplan, Flips und Craft-Radar. Daily-Quests sind sicheres Gold und immer sichtbar.")

    -- Die Chancen filtern nach zwei Groessen statt einer: absoluter Gewinn und
    -- Kapitaleffizienz. Bewusst eigene Optionen - der Mindestgewinn des
    -- Tagesplans bleibt davon unberuehrt.
    local oppHeading = optionHeading(panel, "Chancen: Mindestprofit", minNote, -26)
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
        local button = createFlatButton(panel, def.label, 82, 26)
        if previous then
            button:SetPoint("LEFT", previous, "RIGHT", GAP, 0)
        else
            button:SetPoint("TOPLEFT", oppHeading, "BOTTOMLEFT", 0, -TEXT_GAP)
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
        panel.oppProfitButtons[0], -26)
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
        local button = createFlatButton(panel, def.label, 82, 26)
        if previous then
            button:SetPoint("LEFT", previous, "RIGHT", GAP, 0)
        else
            button:SetPoint("TOPLEFT", roiHeading, "BOTTOMLEFT", 0, -TEXT_GAP)
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
    oppNote:SetPoint("TOPLEFT", panel.oppROIButtons[0], "BOTTOMLEFT", 0, -GAP)
    oppNote:SetText("Gilt nur für den Chancen-Tab. ROI = theoretischer Gewinn geteilt durch "
        .. "Kapitaleinsatz: 10 g Einsatz, 2 g Gewinn = 20 % ROI. Er sagt, wie hart dein Gold "
        .. "arbeitet – nicht, wie viel dabei herauskommt. Dafür ist der Mindestprofit da.")

    -- 1.0.0-beta.3: Preis-Plausibilität und Stückzahl. Beides sind Filter gegen
    -- Rechnungen, die formal stimmen und praktisch unbrauchbar sind.
    local sanityHeading = optionHeading(panel, "Chancen: unbelegte Preise", oppNote, -26)
    panel.sanityButton = createFlatButton(panel, "Fantasie-Auktionen ausblenden", 260, 26)
    panel.sanityButton:SetPoint("TOPLEFT", sanityHeading, "BOTTOMLEFT", 0, -TEXT_GAP)
    panel.sanityButton:SetScript("OnClick", function()
        GCP.db.options.hideImplausible = not GCP.db.options.hideImplausible
        GCP.Opportunity:Invalidate()
        UI.plannedRoute = nil
        UI:Refresh()
    end)
    local sanityNote = createText(panel, 11, COLOR.textDim)
    sanityNote:SetPoint("TOPLEFT", panel.sanityButton, "BOTTOMLEFT", 0, -GAP)
    sanityNote:SetText("An: Chancen, deren Verkaufspreis auf einer einzelnen überteuerten "
        .. "Auktion beruht, fliegen raus – erkannt am Vergleich mit Händlerpreis und "
        .. "Materialkosten. Ein Item, das du selbst schon verkauft hast oder das mehrere "
        .. "Anbieter führen, bleibt immer drin.")

    local unitHeading = optionHeading(panel, "Stückzahl je Position", sanityNote, -26)
    panel.unitButtons = {}
    local unitDefs = {
        { value = "auto", label = "automatisch" },
        { value = 1, label = "1" },
        { value = 3, label = "3" },
        { value = 5, label = "5" },
        { value = 10, label = "10" },
        { value = 25, label = "25" },
        { value = 0, label = "aus" },
    }
    previous = nil
    for _, def in ipairs(unitDefs) do
        local button = createFlatButton(panel, def.label, 82, 26)
        if previous then
            button:SetPoint("LEFT", previous, "RIGHT", GAP, 0)
        else
            button:SetPoint("TOPLEFT", unitHeading, "BOTTOMLEFT", 0, -TEXT_GAP)
        end
        button:SetScript("OnClick", function()
            GCP.db.options.maxUnitsPerPosition = def.value
            UI.plannedRoute = nil
            UI.plannedSignature = nil
            UI:Refresh()
        end)
        panel.unitButtons[def.value] = button
        previous = button
    end
    local unitNote = createText(panel, 11, COLOR.textDim)
    unitNote:SetPoint("TOPLEFT", panel.unitButtons["auto"], "BOTTOMLEFT", 0, -GAP)
    unitNote:SetText("Wie viele Stück eines Items eine Route höchstens kaufen darf. "
        .. "„Automatisch“ heißt 5 ohne eigene Verkaufsdaten und 20 mit – dein Gold reicht "
        .. "vielleicht für 26 Stück, der Markt nimmt sie deswegen noch lange nicht ab.")

    local goalHeading = optionHeading(panel, "Tagesziel", unitNote, -26)
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
        local button = createFlatButton(panel, def.label, 94, 26)
        if previous then
            button:SetPoint("LEFT", previous, "RIGHT", GAP, 0)
        else
            button:SetPoint("TOPLEFT", goalHeading, "BOTTOMLEFT", 0, -TEXT_GAP)
        end
        button:SetScript("OnClick", function()
            GCP.db.options.dailyGoal = def.value
            UI:Refresh()
        end)
        panel.goalButtons[def.value] = button
        previous = button
    end

    local goalNote = createText(panel, 11, COLOR.textDim)
    goalNote:SetPoint("TOPLEFT", panel.goalButtons[0], "BOTTOMLEFT", 0, -GAP)
    goalNote:SetText("Der Tab „Heute“ zeigt dann den schnellsten Weg dorthin – Aufgaben nach Gold je Minute sortiert.")

    local keepHeading = optionHeading(panel, "Eigenbedarf", goalNote, -26)
    panel.keepButton = createFlatButton(panel, "Verbrauchbares behalten", 226, 26)
    panel.keepButton:SetPoint("TOPLEFT", keepHeading, "BOTTOMLEFT", 0, -TEXT_GAP)
    panel.keepButton:SetScript("OnClick", function()
        GCP.db.options.keepConsumables = not GCP.db.options.keepConsumables
        UI:Refresh()
    end)
    local keepNote = createText(panel, 11, COLOR.textDim)
    keepNote:SetPoint("TOPLEFT", panel.keepButton, "BOTTOMLEFT", 0, -GAP)
    keepNote:SetText("An: Tränke, Elixiere und Essen werden nie zum Verkauf vorgeschlagen – ihr Wert steht trotzdem im Verkaufen-Tab.")

    -- ---------------------------------------------------------------------
    -- Guide, Navigation und Kapital (0.9.0)
    -- ---------------------------------------------------------------------
    local guideHeading = optionHeading(panel, "Gold Route und Guide", keepNote, -26)
    panel.guideButtons = {}
    local guideDefs = {
        { key = "guideViewer", label = "Guide-Fenster" },
        { key = "guideArrow", label = "Richtungspfeil" },
        { key = "guideAutoInsert", label = "Chancen automatisch einfügen" },
        { key = "navigationTomTom", label = "TomTom-Wegpunkte" },
    }
    previous = nil
    for _, def in ipairs(guideDefs) do
        local button = createFlatButton(panel, def.label, 216, 26)
        if previous then
            button:SetPoint("LEFT", previous, "RIGHT", GAP, 0)
        else
            button:SetPoint("TOPLEFT", guideHeading, "BOTTOMLEFT", 0, -TEXT_GAP)
        end
        button:SetScript("OnClick", function()
            GCP.db.options[def.key] = not GCP.db.options[def.key]
            if def.key == "guideViewer" then UI:RefreshGuide() end
            UI:Refresh()
        end)
        panel.guideButtons[def.key] = button
        previous = button
    end
    local guideNote = createText(panel, 11, COLOR.textDim)
    guideNote:SetPoint("TOPLEFT", panel.guideButtons.guideViewer, "BOTTOMLEFT", 0, -GAP)
    guideNote:SetJustifyH("LEFT")
    guideNote:SetText(table.concat({
        "Der Pfeil erscheint nur für Orte, die du selbst schon besucht hast – "
            .. "Gold Copilot rät keine Koordinaten.",
        "Chancen automatisch einfügen ist voreingestellt aus: Eine laufende Route "
            .. "soll sich nicht unter dir verändern.",
        "TomTom ist optional. Fehlt es, bringt Gold Copilot seinen eigenen Pfeil mit.",
    }, "\n"))

    local reserveHeading = optionHeading(panel, "Cash-Reserve", guideNote, -26)
    panel.reserveButtons = {}
    local reserveDefs = {
        { mode = "percent", value = 0,    label = "keine" },
        { mode = "percent", value = 0.10, label = "10 %" },
        { mode = "percent", value = 0.20, label = "20 %" },
        { mode = "percent", value = 0.35, label = "35 %" },
        { mode = "absolute", value = 5000000,  label = "fest 500 g" },
        { mode = "absolute", value = 20000000, label = "fest 2000 g" },
    }
    previous = nil
    for index, def in ipairs(reserveDefs) do
        local button = createFlatButton(panel, def.label, 124, 26)
        if previous then
            button:SetPoint("LEFT", previous, "RIGHT", GAP, 0)
        else
            button:SetPoint("TOPLEFT", reserveHeading, "BOTTOMLEFT", 0, -TEXT_GAP)
        end
        button:SetScript("OnClick", function()
            GCP.Capital:SetReserve(def.mode, def.value)
            UI:Refresh()
        end)
        panel.reserveButtons[index] = button
        previous = button
    end
    local reserveNote = createText(panel, 11, COLOR.textDim)
    reserveNote:SetPoint("TOPLEFT", panel.reserveButtons[1], "BOTTOMLEFT", 0, -GAP)
    reserveNote:SetText("Die Reserve wird nie verplant – weder vom Routenplaner noch von der Kapitalverteilung.")

    local calibrationHeading = optionHeading(panel, "Modell", reserveNote, -26)
    panel.calibrationButton = createFlatButton(panel, "Persönliche Kalibrierung", 226, 26)
    panel.calibrationButton:SetPoint("TOPLEFT", calibrationHeading, "BOTTOMLEFT", 0, -TEXT_GAP)
    panel.calibrationButton:SetScript("OnClick", function()
        GCP.Calibration:SetEnabled(not GCP.Calibration:IsEnabled())
        GCP.Calibration:Update()
        UI:Refresh()
    end)
    panel.calibrationReset = createFlatButton(panel, "Zurücksetzen", 146, 26)
    panel.calibrationReset:SetPoint("LEFT", panel.calibrationButton, "RIGHT", GAP, 0)
    panel.calibrationReset:SetScript("OnClick", function()
        GCP.Calibration:Reset()
        UI:Refresh()
    end)
    panel.calibrationText = createText(panel, 11, COLOR.textDim)
    panel.calibrationText:SetPoint("TOPLEFT", panel.calibrationButton, "BOTTOMLEFT", 0, -GAP)
    panel.calibrationText:SetJustifyH("LEFT")

    local dataHeading = optionHeading(panel, "Daten", panel.calibrationText, -26)
    panel.dataText = createText(panel, 11, COLOR.textDim)
    panel.dataText:SetPoint("TOPLEFT", dataHeading, "BOTTOMLEFT", 0, -TEXT_GAP)
    panel.dataText:SetJustifyH("LEFT")

    panel.clearIgnored = createFlatButton(panel, "Ignorierte Items zurücksetzen", 226, 26)
    panel.clearIgnored:SetPoint("TOPLEFT", panel.dataText, "BOTTOMLEFT", 0, -10)
    panel.clearIgnored:SetScript("OnClick", function()
        GCP.db.options.ignored = {}
        UI:Refresh()
    end)

    -- Zwei Listen, zwei Knoepfe. "Ignoriert" heisst "behalte ich, schlag es mir
    -- nicht zum Verkauf vor", "abgelehnt" heisst "damit will ich nicht
    -- handeln". Ein gemeinsamer Knopf wuerde beim Druecken mehr loeschen, als
    -- der Beschriftung nach zu erwarten waere.
    panel.clearRejected = createFlatButton(panel, "Abgelehnte Items zurücksetzen", 236, 26)
    panel.clearRejected:SetPoint("TOPLEFT", panel.clearIgnored, "BOTTOMLEFT", 0, -GAP)
    panel.clearRejected:SetScript("OnClick", function()
        GCP.db.options.rejected = {}
        GCP.Opportunity:Invalidate()
        UI.plannedRoute = nil
        UI:Refresh()
    end)

    local mathHeading = optionHeading(panel, "So wird gerechnet", panel.clearRejected, -26)
    local mathText = createText(panel, 11, COLOR.textDim)
    mathText:SetPoint("TOPLEFT", mathHeading, "BOTTOMLEFT", 0, -TEXT_GAP)
    mathText:SetJustifyH("LEFT")
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
    local hideImplausible = options.hideImplausible ~= false
    panel.sanityButton:SetActive(hideImplausible)
    panel.sanityButton:SetLabel(hideImplausible
        and "Fantasie-Auktionen ausblenden" or "Auch unbelegte Preise zeigen")
    local unitOption = options.maxUnitsPerPosition
    if unitOption == nil then unitOption = "auto" end
    for value, button in pairs(panel.unitButtons) do
        button:SetActive(unitOption == value)
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
    for _ in pairs(GCP:Profile().priceHistory or {}) do observedCount = observedCount + 1 end
    local learnedQuests = 0
    for _ in pairs(GCP.db.questGold or {}) do learnedQuests = learnedQuests + 1 end
    local Market = GCP.Market
    local market = Market:GetOverview()
    local knowledgeSummary = GCP.Knowledge:Summary()
    local futureGraph = GCP.Future:GetGraph()
    local ledger = GCP.Ledger:GetOverview()
    for key, button in pairs(panel.guideButtons) do
        button:SetActive(options[key] and true or false)
    end
    local reserve = GCP.Capital:GetReserveSettings()
    panel.reserveButtons[1]:SetActive(reserve.mode == "percent" and reserve.percent == 0)
    panel.reserveButtons[2]:SetActive(reserve.mode == "percent" and reserve.percent == 0.10)
    panel.reserveButtons[3]:SetActive(reserve.mode == "percent" and reserve.percent == 0.20)
    panel.reserveButtons[4]:SetActive(reserve.mode == "percent" and reserve.percent == 0.35)
    panel.reserveButtons[5]:SetActive(reserve.mode == "absolute" and reserve.absolute == 5000000)
    panel.reserveButtons[6]:SetActive(reserve.mode == "absolute" and reserve.absolute == 20000000)
    panel.calibrationButton:SetActive(GCP.Calibration:IsEnabled())
    panel.calibrationText:SetText(table.concat(GCP.Calibration:Lines(), "\n"))

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
            .. "spätere Treffsicherheits-Auswertungen.", #(GCP:Profile().opportunityHistory or {})),
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
        -- 0.9.0: Die neuen Speicher gehoeren sichtbar dazu - samt dem Satz,
        -- dass auch sie den Rechner nicht verlassen.
        string.format("Markttiefe: %d Item(s) mit gemessenen Angebotsmengen "
            .. "(nur aus deinen eigenen AH-Suchen).", GCP.Market:DepthOverview().items),
        string.format("Gelernte Orte: %d (Auktionshaus, Bank, Briefkasten, Beruf, "
            .. "Händler) – getrennt je Realm und Fraktion.",
            GCP.Navigation:KnownCount()),
        string.format("Farmhistorie: %s", GCP.Farm:SummaryText()),
        string.format("Persönliche Statistik: %s", GCP.Personal:SummaryText()),
        string.format("Ignorierte Items: %d.", ignoredCount),
    }, "\n"))
    self.frame.summary:SetText("Einstellungen wirken sofort und werden pro Account gespeichert.")
end

-- ---------------------------------------------------------------------------
-- Steuerung
-- ---------------------------------------------------------------------------

-- ---------------------------------------------------------------------------
-- GUIDE VIEWER (0.9.0)
--
-- Ein kleines, dauerhaft einblendbares Fenster - nicht das grosse Hauptfenster.
-- Es zeigt genau einen Schritt, die Zahlen dazu und drei Knoepfe. Wer ihm
-- folgt, muss keine Tabelle lesen.
--
--   ┌──────────────────────────────┐
--   │ GOLD ROUTE        +184/500g  │
--   │ Schritt 4 / 11               │
--   │ KAUFE 20x URFEUER            │
--   │ Max. 21 g / Stück            │
--   │ Kapital: 420 g               │
--   │ Potenzial: +86 g             │
--   │ Confidence: HOCH             │
--   │ [Warum?] [Überspringen]      │
--   └──────────────────────────────┘
--
-- DER PFEIL. Er zeigt die Richtung zum naechsten Ort - aber nur, wenn Gold
-- Copilot diesen Ort kennt (siehe Navigation.lua). Gedreht wird bewusst NICHT
-- ueber Texture:SetRotation: Die gibt es nicht in jeder Clientfassung.
--
-- Bis 1.0.0-beta.4 standen hier acht Glyphen aus dem Unicode-Block "Geometric
-- Shapes" (▲ ◥ ▶ ...). Die Standardschrift des Clients, FRIZQT__.TTF, enthaelt
-- diesen Block nicht - im Spiel erschien deshalb ausnahmslos ein leeres
-- Kaestchen, und zwar seit es diesen Pfeil gibt. Eine Schrift, die eine
-- fehlende Glyphe zeigt, tut das ueberall gleich schlecht.
--
-- Jetzt reines ASCII. Das ist weniger huebsch und dafuer immer da; die genaue
-- Richtung steht ohnehin als Text daneben ("links voraus"), der Pfeil ist die
-- schnell erfassbare Zusammenfassung davon.
-- ---------------------------------------------------------------------------

local ARROW_GLYPHS = { "^", "/", ">", "\\", "v", "/", "<", "\\" }

local function arrowGlyph(relative)
    if type(relative) ~= "number" then return nil end
    local index = math.floor((relative + math.pi / 8) / (math.pi / 4)) % 8 + 1
    return ARROW_GLYPHS[index]
end

-- Der Guide steht waehrend des Spielens offen und ist deshalb das engste
-- Fenster des Addons. 340 statt 320 Pixel Breite: Seit 1.0.0-beta.3 steht der
-- Schritt-zurueck-Knopf mit in der Reihe. Nachgerechnet von links nach rechts:
-- 12 Rand + 30 (Zurueck) + 4 + 74 (Warum) + 4 + 80 (Erledigt) + 4 + 112
-- (Überspringen) + 12 Rand = 332, also acht Pixel Luft.
--
-- 292 statt 262 Pixel hoch: Seit 1.0.0-beta.4 stehen ueber der Handlung das
-- Vorhaben und der Teilschritt. Ohne die beiden Zeilen sagt der Guide "Gehe zu:
-- Auktionshaus" und nirgends, wozu.
local GUIDE_WIDTH = 340
local GUIDE_HEIGHT = 292
local GUIDE_INSET = 12
-- Kantenlaenge des Item-Symbols neben der Handlung. Es traegt den Tooltip:
-- Was der Guide eigentlich will, soll man sehen koennen, nicht raten muessen.
local GUIDE_ICON = 26
-- Oberkante der oberen Knopfreihe, gemessen von der Unterkante des Fensters:
-- 12 Rand + 24 (Warum/Erledigt/Überspringen) + 8 Abstand + 22 (Pause/Abbruch).
local GUIDE_BUTTONS_TOP = 66

function UI:EnsureGuideViewer()
    if self.guideFrame then return self.guideFrame end

    local frame = CreateFrame("Frame", "GoldCopilotGuideFrame", UIParent)
    frame:SetSize(GUIDE_WIDTH, GUIDE_HEIGHT)
    frame:SetFrameStrata("MEDIUM")
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetClampedToScreen(true)
    applyBackdrop(frame, COLOR.bg, COLOR.accent)
    frame:Hide()

    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        UI:SaveGuidePosition()
    end)

    frame.title = createText(frame, 12, COLOR.accent)
    frame.title:SetPoint("TOPLEFT", GUIDE_INSET, -GUIDE_INSET)
    frame.title:SetText("GOLD ROUTE")

    frame.close = createFlatButton(frame, "×", 20, 20)
    frame.close:SetPoint("TOPRIGHT", -GUIDE_INSET + 2, -GUIDE_INSET + 2)
    frame.close:SetScript("OnClick", function() UI:HideGuideViewer() end)

    frame.minimize = createFlatButton(frame, "–", 20, 20)
    frame.minimize:SetPoint("RIGHT", frame.close, "LEFT", -GAP / 2, 0)
    frame.minimize:SetScript("OnClick", function() UI:ToggleGuideMinimized() end)

    -- Der Zielstand endet vor den beiden Knoepfen, statt sie zu beruehren.
    frame.goal = createText(frame, 12, COLOR.green, true)
    frame.goal:SetPoint("RIGHT", frame.minimize, "LEFT", -GAP, 0)
    frame.goal:SetJustifyH("RIGHT")

    frame.step = createText(frame, 11, COLOR.textDim)
    frame.step:SetPoint("TOPLEFT", GUIDE_INSET, -32)

    -- Das Vorhaben. Eine Route buendelt nach Ort, damit man nicht dreimal zum
    -- Auktionshaus laeuft - deshalb liegen die Schritte zweier Crafts
    -- zwangslaeufig ineinander. Genau dann muss an jedem Schritt stehen, wozu er
    -- gehoert, sonst liest sich die Route als eine flache Liste ohne Zusammenhang.
    frame.goalLine = createText(frame, 12, COLOR.accent)
    frame.goalLine:SetPoint("TOPLEFT", GUIDE_INSET, -50)
    frame.goalLine:SetWidth(GUIDE_WIDTH - 2 * GUIDE_INSET)
    frame.goalLine:SetJustifyH("LEFT")

    frame.arrow = createText(frame, 26, COLOR.accent)
    frame.arrow:SetPoint("TOPRIGHT", -GUIDE_INSET, -68)

    frame.distance = createText(frame, 10, COLOR.textDim)
    frame.distance:SetPoint("TOPRIGHT", -GUIDE_INSET, -102)
    frame.distance:SetJustifyH("RIGHT")

    -- Das Item als Knopf statt als Textur: Nur so laesst sich der Tooltip des
    -- Clients daran haengen, und genau der beantwortet "was will der Guide
    -- eigentlich von mir".
    frame.itemButton = CreateFrame("Button", nil, frame)
    frame.itemButton:SetSize(GUIDE_ICON, GUIDE_ICON)
    frame.itemButton:SetPoint("TOPLEFT", GUIDE_INSET, -70)
    frame.itemButton:EnableMouse(true)
    frame.itemButton.icon = frame.itemButton:CreateTexture(nil, "ARTWORK")
    frame.itemButton.icon:SetAllPoints()
    frame.itemButton.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    frame.itemButton:SetScript("OnEnter", function(button)
        if not button.itemID then return end
        GameTooltip:SetOwner(button, "ANCHOR_RIGHT")
        if not pcall(GameTooltip.SetItemByID, GameTooltip, button.itemID) then
            GameTooltip:Hide()
            return
        end
        GameTooltip:Show()
    end)
    frame.itemButton:SetScript("OnLeave", function() GameTooltip:Hide() end)
    -- Shift-Klick fuegt den Link in die Chateingabe ein, wie ueberall sonst.
    frame.itemButton:SetScript("OnClick", function(button)
        if button.itemID and IsShiftKeyDown() and ChatEdit_InsertLink then
            local _, link = GetItemInfo(button.itemID)
            if link then ChatEdit_InsertLink(link) end
        end
    end)
    frame.itemButton:Hide()

    frame.action = createText(frame, 15, COLOR.text)
    frame.action:SetPoint("TOPLEFT", GUIDE_INSET, -72)
    frame.action:SetWidth(GUIDE_WIDTH - 2 * GUIDE_INSET - 46)
    frame.action:SetJustifyH("LEFT")

    frame.detail = createText(frame, 11, COLOR.textDim)
    frame.detail:SetPoint("TOPLEFT", GUIDE_INSET, -118)
    frame.detail:SetWidth(GUIDE_WIDTH - 2 * GUIDE_INSET)
    frame.detail:SetJustifyH("LEFT")

    frame.numbers = createText(frame, 11, COLOR.text, true)
    frame.numbers:SetPoint("TOPLEFT", GUIDE_INSET, -150)
    frame.numbers:SetJustifyH("LEFT")

    frame.confidence = createText(frame, 10, COLOR.textDim)
    frame.confidence:SetPoint("TOPLEFT", GUIDE_INSET, -170)

    -- Die Chancenmeldung sitzt in einem festen Kasten zwischen Sicherheit und
    -- Knopfreihe. Frueher hing sie an einer festen Hoehe und lag damit auf den
    -- Knoepfen, sobald sie erschien.
    frame.interrupt = createText(frame, 11, COLOR.accent)
    frame.interrupt:SetPoint("TOPLEFT", GUIDE_INSET, -190)
    frame.interrupt:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT",
        -GUIDE_INSET, GUIDE_BUTTONS_TOP + GAP)
    frame.interrupt:SetJustifyH("LEFT")
    frame.interrupt:Hide()

    -- Schritt zurueck. Der einzige Knopf des Guides, der eine Entscheidung
    -- ruecknimmt statt eine zu treffen - und deshalb ganz links, abgesetzt von
    -- der Reihe, die vorwaerts fuehrt.
    frame.backButton = createFlatButton(frame, "<", 30, 24)
    frame.backButton:SetPoint("BOTTOMLEFT", GUIDE_INSET, GUIDE_INSET)
    frame.backButton:SetScript("OnClick", function()
        if not GCP.Guide:StepBack() then
            GCP:Print("Kein Schritt zum Zurückgehen – hier ist der Anfang der Route.")
        end
        UI:RefreshGuide()
        UI:RefreshIfShown()
    end)

    frame.whyButton = createFlatButton(frame, "Warum?", 74, 24)
    frame.whyButton:SetPoint("LEFT", frame.backButton, "RIGHT", GAP / 2, 0)
    frame.whyButton:SetScript("OnClick", function() UI:PrintGuideWhy() end)

    frame.doneButton = createFlatButton(frame, "Erledigt", 80, 24)
    frame.doneButton:SetPoint("LEFT", frame.whyButton, "RIGHT", GAP / 2, 0)
    frame.doneButton:SetScript("OnClick", function()
        local step = GCP.Guide:CurrentStep()
        if step then GCP.Guide:Complete(step.id, false) end
        UI:RefreshGuide()
        UI:RefreshIfShown()
    end)

    -- "Überspringen" IST der Schritt vorwaerts. Ein zweiter Knopf daneben, der
    -- dasselbe taete, waere nur eine zweite Beschriftung fuer dieselbe Sache -
    -- deshalb traegt dieser hier beides.
    frame.skipButton = createFlatButton(frame, "Überspringen >", 112, 24)
    frame.skipButton:SetPoint("LEFT", frame.doneButton, "RIGHT", GAP / 2, 0)
    frame.skipButton:SetScript("OnClick", function()
        GCP.Guide:StepForward()
        UI:RefreshGuide()
        UI:RefreshIfShown()
    end)

    -- Nur am Ende der Route sichtbar, an der Stelle der Schrittknoepfe: Dort
    -- steht bis 1.0.0-beta.2 eine Reihe, die nichts mehr bewirkt.
    frame.newRouteButton = createFlatButton(frame, "Neue Route planen", 176, 24)
    frame.newRouteButton:SetPoint("LEFT", frame.backButton, "RIGHT", GAP / 2, 0)
    frame.newRouteButton:SetScript("OnClick", function()
        UI:PlanNewRoute()
        UI:EnsureFrame():Show()
        UI:SelectTab("route")
    end)
    frame.newRouteButton:Hide()

    frame.pauseButton = createFlatButton(frame, "Pause", 84, 22)
    frame.pauseButton:SetPoint("BOTTOMLEFT", frame.backButton, "TOPLEFT", 0, GAP)
    frame.pauseButton:SetScript("OnClick", function()
        if GCP.Guide:GetState() == "PAUSED" then
            GCP.Guide:Resume()
        else
            GCP.Guide:Pause()
        end
        UI:RefreshGuide()
    end)

    frame.abortButton = createFlatButton(frame, "Route abbrechen", 130, 22)
    frame.abortButton:SetPoint("LEFT", frame.pauseButton, "RIGHT", GAP, 0)
    frame.abortButton:SetScript("OnClick", function()
        if GCP.Personal then GCP.Personal:RecordRouteAborted() end
        GCP.Guide:Abort()
        UI:RefreshGuide()
        UI:RefreshIfShown()
    end)

    -- Gespeicherte Position und Groesse wiederherstellen.
    local saved = GCP.db and GCP.db.options.guidePoint
    if type(saved) == "table" and saved.point then
        frame:SetPoint(saved.point, UIParent, saved.relativePoint or saved.point,
            saved.x or 0, saved.y or 0)
    else
        frame:SetPoint("CENTER", UIParent, "CENTER", 340, 120)
    end
    if type(GCP.db and GCP.db.options.guideScale) == "number" then
        frame:SetScale(GCP.db.options.guideScale)
    end

    self.guideFrame = frame
    return frame
end

function UI:SaveGuidePosition()
    local frame = self.guideFrame
    if not frame or not GCP.db then return false end
    local point, _, relativePoint, x, y = frame:GetPoint()
    if not point then return false end
    GCP.db.options.guidePoint = {
        point = point, relativePoint = relativePoint, x = x, y = y,
    }
    return true
end

function UI:SetGuideScale(scale)
    if type(scale) ~= "number" then return false end
    scale = math.max(math.min(scale, 2.0), 0.6)
    GCP.db.options.guideScale = scale
    local frame = self:EnsureGuideViewer()
    frame:SetScale(scale)
    return true
end

function UI:ToggleGuideMinimized()
    GCP.db.options.guideMinimized = not GCP.db.options.guideMinimized
    self:RefreshGuide()
    return GCP.db.options.guideMinimized
end

function UI:ShowGuideViewer()
    local frame = self:EnsureGuideViewer()
    GCP.db.options.guideViewer = true
    frame:Show()
    self:RefreshGuide()
    return frame
end

function UI:HideGuideViewer()
    GCP.db.options.guideViewer = false
    if self.guideFrame then self.guideFrame:Hide() end
    return true
end

function UI:ToggleGuideViewer()
    if self.guideFrame and self.guideFrame:IsShown() then
        return self:HideGuideViewer()
    end
    return self:ShowGuideViewer()
end

-- Guide zeigen UND die Route laufen lassen. Je nach Zustand heisst das etwas
-- anderes, und genau deshalb steht es hier an einer Stelle statt verteilt an
-- den Knoepfen:
--   pausiert       -> fortsetzen
--   nichts geplant -> planen und starten
--   laeuft schon   -> nur zeigen
-- Eine abgeschlossene Route wird NICHT stillschweigend durch eine neue ersetzt;
-- dafuer gibt es "Neue Route planen" im Guide selbst.
function UI:ShowGuideAndRun()
    local progress = GCP.Guide:Progress()
    local state = progress and progress.state
    local hasSteps = progress and progress.steps > 0

    if hasSteps and state == "PAUSED" then
        GCP.Guide:Resume()
    elseif not hasSteps or state == "IDLE" then
        local route, problem = GCP.Guide:Start(self:GoalOptions(self.plannedProfile))
        self.plannedRoute = route
        if GCP.Personal then GCP.Personal:RecordRouteStarted() end
        if not (route and #route.steps > 0) then
            GCP:Print(problem or "Gold Copilot findet gerade keine Route.")
            return false
        end
    end

    self:ShowGuideViewer()
    self:RefreshIfShown()
    return true
end

function UI:PrintGuideWhy()
    local step = GCP.Guide:CurrentStep()
    if not step then
        GCP:Print("Kein aktiver Schritt.")
        return false
    end
    local why = GCP.Guide:Why(step)
    GCP:Print("Warum: " .. GCP.Guide:StepTitle(step))
    for _, group in ipairs({ why.context, why.positive, why.negative,
        why.warnings, why.unknown }) do
        for _, line in ipairs(group) do
            if line ~= " " then GCP:Print("  " .. line) end
        end
    end
    return true
end

-- Der Pfeil muss sich bewegen, waehrend der Spieler laeuft. Ein OnUpdate waere
-- dafuer die teuerste denkbare Loesung (60 Aufrufe je Sekunde); statt dessen
-- plant sich der Viewer selbst neu ein, solange er sichtbar ist und eine Route
-- laeuft - zweimal je Sekunde, und keinen Aufruf mehr, sobald er zu ist.
local GUIDE_TICK = 0.5

function UI:ScheduleGuideTick()
    if self.guideTickScheduled then return false end
    if type(C_Timer) ~= "table" or type(C_Timer.After) ~= "function" then return false end
    self.guideTickScheduled = true
    C_Timer.After(GUIDE_TICK, function()
        UI.guideTickScheduled = false
        if UI.guideFrame and UI.guideFrame:IsShown() then
            UI:RefreshGuide()
        end
    end)
    return true
end

-- Der Viewer wird von Ereignissen angestossen, nicht von einem OnUpdate.
function UI:RefreshGuide()
    local options = GCP.db and GCP.db.options
    if not options then return false end
    if not options.guideViewer then
        if self.guideFrame then self.guideFrame:Hide() end
        return false
    end
    local progress = GCP.Guide:Progress()
    if not progress or progress.steps == 0 or progress.state == "IDLE" then
        if self.guideFrame then self.guideFrame:Hide() end
        return false
    end

    local frame = self:EnsureGuideViewer()
    frame:Show()
    GCP.Guide:Tick()
    -- Ankunft VOR dem Zeichnen pruefen, sonst zeigt das Fenster noch einen
    -- halben Takt lang "Gehe zu: Auktionshaus", waehrend man davorsteht.
    -- Wird ein Schritt dabei fertig, aendert sich der aktuelle Schritt - der
    -- Rest dieser Funktion arbeitet dann schon mit dem naechsten.
    if GCP.Guide:CheckArrival() then
        progress = GCP.Guide:Progress()
        self:RefreshIfShown()
    end
    self:ScheduleGuideTick()

    local Prices = GCP.Prices
    local minimized = options.guideMinimized and true or false
    for _, child in ipairs({ frame.action, frame.detail, frame.numbers,
        frame.confidence, frame.backButton, frame.whyButton, frame.doneButton,
        frame.skipButton, frame.pauseButton, frame.abortButton, frame.arrow,
        frame.distance, frame.goalLine }) do
        child:SetShown(not minimized)
    end
    frame.newRouteButton:Hide()
    frame.itemButton:Hide()
    frame:SetHeight(minimized and 52 or GUIDE_HEIGHT)

    frame.step:SetText(GCP.Guide:HeaderText())
    if progress.goal and progress.goal > 0 then
        local achieved = progress.realizedNet or 0
        frame.goal:SetText(string.format("+%s / %s",
            Prices:FormatGold(achieved), Prices:FormatGold(progress.goal)))
    elseif progress.remainingProfit > 0 then
        frame.goal:SetText("Rest " .. Prices:FormatGold(progress.remainingProfit))
    else
        frame.goal:SetText("")
    end
    if minimized then return true end

    local step = GCP.Guide:CurrentStep()
    if progress.state == "COMPLETED" or not step then
        frame.action:SetText("Route abgeschlossen.")
        frame.detail:SetText(string.format("%d Schritte erledigt, %d übersprungen.",
            progress.done, progress.skipped))
        frame.numbers:SetText("")
        frame.confidence:SetText("")
        frame.arrow:SetText("")
        frame.distance:SetText("")
        -- Am Ende der Route bewirken Erledigt, Überspringen und Pause nichts
        -- mehr. Statt sie anzubieten, steht dort der einzige Knopf, der jetzt
        -- noch etwas tut - und "◀" daneben, falls der letzte Haken falsch war.
        frame.whyButton:Hide()
        frame.doneButton:Hide()
        frame.skipButton:Hide()
        frame.pauseButton:Hide()
        frame.newRouteButton:Show()
        frame.backButton:Show()
        frame.backButton:SetDisabled(not GCP.Guide:CanStepBack())
        frame.goalLine:SetText("")
        return true
    end
    frame.backButton:SetDisabled(not GCP.Guide:CanStepBack())

    -- Wozu dient dieser Schritt? Vorhaben, Teilschritt darin und die Nummer des
    -- Vorhabens - drei Angaben, die aus einer flachen Schrittliste einen Plan
    -- machen. Schritte ohne Gruppe (Wege zwischen zwei Vorhaben) lassen die
    -- Zeile leer, statt eine Zugehoerigkeit zu behaupten.
    local groupInfo = GCP.Guide:GroupInfo(step)
    local position, total, groupIndex, groupCount = GCP.Guide:GroupPosition(step)
    if groupInfo and groupInfo.title then
        local parts = { groupInfo.title }
        if position and total and total > 1 then
            parts[#parts + 1] = string.format("Teilschritt %d/%d", position, total)
        end
        if groupIndex and groupCount and groupCount > 1 then
            parts[#parts + 1] = string.format("Vorhaben %d/%d", groupIndex, groupCount)
        end
        frame.goalLine:SetText(table.concat(parts, "  ·  "))
    else
        frame.goalLine:SetText("")
    end

    -- Das Item des Schritts, sonst das des Vorhabens: Bei "Gehe zu:
    -- Auktionshaus" traegt der Schritt selbst keines, das Ziel dahinter schon.
    local iconItem = step.itemID or (groupInfo and groupInfo.itemID) or nil
    local iconTexture = iconItem and select(10, GetItemInfo(iconItem)) or nil
    -- Der Text rueckt neben das Symbol und bekommt entsprechend weniger Breite.
    -- ClearAllPoints, weil sonst der Anker der vorigen Zeichnung stehen bliebe.
    local textLeft = GUIDE_INSET
    if iconItem and iconTexture then
        frame.itemButton.itemID = iconItem
        frame.itemButton.icon:SetTexture(iconTexture)
        frame.itemButton:Show()
        textLeft = GUIDE_INSET + GUIDE_ICON + GAP
    else
        frame.itemButton.itemID = nil
        frame.itemButton:Hide()
    end
    frame.action:ClearAllPoints()
    frame.action:SetPoint("TOPLEFT", textLeft, -72)
    frame.action:SetWidth(GUIDE_WIDTH - textLeft - GUIDE_INSET - 46)

    frame.action:SetText(GCP.Guide:StepTitle(step))
    frame.detail:SetText(step.detail or "")
    local numbers = {}
    if step.capitalRequired and step.capitalRequired > 0 then
        numbers[#numbers + 1] = "Kapital: " .. Prices:FormatGold(step.capitalRequired)
    end
    if step.expectedProfit and step.expectedProfit > 0 then
        numbers[#numbers + 1] = "Potenzial: +" .. Prices:FormatGold(step.expectedProfit)
    end
    frame.numbers:SetText(table.concat(numbers, "  ·  "))
    frame.confidence:SetText(string.format("Sicherheit: %s%s",
        GCP.Market:ConfidenceLabel(step.confidence or progress.confidence),
        progress.state == "PAUSED" and "  ·  PAUSIERT" or ""))
    frame.pauseButton:SetLabel(progress.state == "PAUSED" and "Weiter" or "Pause")

    -- Pfeil und Entfernung
    if options.guideArrow and step.location and GCP.Navigation then
        local waypoint = GCP.Navigation:Refresh()
            or GCP.Navigation:SetTarget(step.location)
        local glyph = waypoint and arrowGlyph(waypoint.relative)
        frame.arrow:SetText(glyph or "")
        if waypoint then
            local label, detail = GCP.Navigation:DescribeTarget(step.location, waypoint)
            frame.distance:SetText(detail ~= "" and detail or label)
        else
            local _, hint = GCP.Navigation:DescribeTarget(step.location, nil)
            frame.distance:SetText("kein Pfeil")
            if step.detail == nil then frame.detail:SetText(hint) end
        end
    else
        frame.arrow:SetText("")
        frame.distance:SetText("")
    end

    -- Opportunity Interrupt
    local interrupt = GCP.Guide.interrupt
    if interrupt then
        frame.interrupt:Show()
        frame.interrupt:SetText("NEUE CHANCE: " .. interrupt.text)
    else
        frame.interrupt:Hide()
    end
    return true
end

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

    local isZentrale = self.activeTab == "zentrale"
    local isRoute = self.activeTab == "route"
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
        or isZukunft or isHandel or isRoute)
    frame.scopeButton:SetShown(isSell)
    frame.filterButton:SetShown(isSell)
    frame.boundButton:SetShown(isSell)
    frame.ignoredButton:SetShown(isSell)
    frame.craftableButton:SetShown(isCrafts)
    frame.watchButton:SetShown(isChancen or isZukunft)
    frame.opportunitySortButton:SetShown(isChancen)
    frame.ledgerSortButton:SetShown(isHandel)
    frame.newRouteButton:SetShown(isRoute)
    -- Die Nachfrage steht am Knopf, nicht nur im Chat: Dort sieht man sie.
    local armed = self.newRouteArmedAt and (type(GetTime) == "function")
        and (GetTime() - self.newRouteArmedAt) <= NEW_ROUTE_CONFIRM_SECONDS
    frame.newRouteButton:SetLabel(armed and "Wirklich ersetzen?" or "Neue Route")
    frame.newRouteButton:SetActive(armed and true or false)
    frame.refreshButton:Show()
    frame.progress:Hide()
    frame.progressLabel:Hide()
    frame.scroll:SetShown(not isOptions and not isZentrale)
    frame.optionsScroll:SetShown(isOptions)
    frame.commandPanel:SetShown(isZentrale)
    frame.toolbar:SetShown(frame.toolbar:IsShown() and not isZentrale)

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

    if isZentrale then
        self:RenderZentrale()
    elseif isRoute then
        self:RenderRoute()
    elseif self.activeTab == "today" then
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
    self:RefreshGuide()
    if frame:IsShown() then
        frame:Hide()
    else
        frame:Show()
    end
end
