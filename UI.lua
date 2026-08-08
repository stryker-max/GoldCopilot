local addonName, GCP = ...

GCP.UI = {}
local UI = GCP.UI

local ROW_HEIGHT = 24
local HEADER_HEIGHT = 30
local FRAME_WIDTH = 780
local FRAME_HEIGHT = 560

local qualityColors = {
    [0] = "|cff9d9d9d", [1] = "|cffffffff", [2] = "|cff1eff00",
    [3] = "|cff0070dd", [4] = "|cffa335ee", [5] = "|cffff8000",
}

local function coloredItemName(row)
    local color = qualityColors[row.quality or 1] or "|cffffffff"
    return color .. (row.name or ("Item " .. tostring(row.itemID))) .. "|r"
end

local channelColors = {
    ["AH"] = "|cff4ec9ff",
    ["Händler"] = "|cffd9a834",
    ["Entzaubern"] = "|cffa335ee",
}

-- ---------------------------------------------------------------------------
-- Fensteraufbau
-- ---------------------------------------------------------------------------

function UI:EnsureFrame()
    if self.frame then return self.frame end

    local frame = CreateFrame("Frame", "GoldCopilotFrame", UIParent, "BackdropTemplate")
    frame:SetSize(FRAME_WIDTH, FRAME_HEIGHT)
    frame:SetPoint("CENTER")
    frame:SetFrameStrata("HIGH")
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    frame:SetClampedToScreen(true)
    frame:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true, tileSize = 32, edgeSize = 32,
        insets = { left = 8, right = 8, top = 8, bottom = 8 },
    })
    frame:Hide()
    tinsert(UISpecialFrames, "GoldCopilotFrame")

    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 16, -14)
    title:SetText(GCP.Constants.COLOR_GOLD .. "Gold Copilot|r " .. GCP.Constants.VERSION)
    frame.title = title

    local trend = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    trend:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -2)
    trend:SetJustifyH("LEFT")
    frame.trend = trend

    local source = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    source:SetPoint("TOPRIGHT", -36, -18)
    source:SetJustifyH("RIGHT")
    frame.source = source

    local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -6, -6)

    -- Tab-Leiste
    frame.tabs = {}
    local tabDefs = {
        { key = "today", label = "Heute" },
        { key = "sell", label = "Verkaufen" },
        { key = "flips", label = "Flips" },
    }
    local previous
    for _, def in ipairs(tabDefs) do
        local tab = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
        tab:SetSize(110, 24)
        if previous then
            tab:SetPoint("LEFT", previous, "RIGHT", 6, 0)
        else
            tab:SetPoint("TOPLEFT", 16, -52)
        end
        tab:SetText(def.label)
        tab.key = def.key
        tab:SetScript("OnClick", function()
            UI:SelectTab(def.key)
        end)
        frame.tabs[def.key] = tab
        previous = tab
    end

    -- Werkzeugleiste des Verkaufen-Tabs
    local toolbar = CreateFrame("Frame", nil, frame)
    toolbar:SetPoint("TOPLEFT", 16, -82)
    toolbar:SetPoint("TOPRIGHT", -36, -82)
    toolbar:SetHeight(24)
    frame.toolbar = toolbar

    local scopeButton = CreateFrame("Button", nil, toolbar, "UIPanelButtonTemplate")
    scopeButton:SetSize(130, 22)
    scopeButton:SetPoint("LEFT")
    scopeButton:SetScript("OnClick", function()
        UI.scope = UI.scope == "account" and "bags" or "account"
        UI:Refresh()
    end)
    frame.scopeButton = scopeButton

    local filterButton = CreateFrame("Button", nil, toolbar, "UIPanelButtonTemplate")
    filterButton:SetSize(130, 22)
    filterButton:SetPoint("LEFT", scopeButton, "RIGHT", 6, 0)
    filterButton:SetScript("OnClick", function()
        local order = { all = "mats", mats = "gear", gear = "all" }
        UI.filter = order[UI.filter or "all"]
        UI:Refresh()
    end)
    frame.filterButton = filterButton

    local refreshButton = CreateFrame("Button", nil, toolbar, "UIPanelButtonTemplate")
    refreshButton:SetSize(110, 22)
    refreshButton:SetPoint("RIGHT")
    refreshButton:SetText("Aktualisieren")
    refreshButton:SetScript("OnClick", function()
        UI:Refresh()
    end)

    local summary = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    summary:SetPoint("TOPLEFT", 18, -112)
    summary:SetPoint("TOPRIGHT", -36, -112)
    summary:SetJustifyH("LEFT")
    frame.summary = summary

    -- Scrollbereich
    local scroll = CreateFrame("ScrollFrame", "GoldCopilotScrollFrame", frame, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 16, -134)
    scroll:SetPoint("BOTTOMRIGHT", -36, 16)
    local content = CreateFrame("Frame", nil, scroll)
    content:SetSize(FRAME_WIDTH - 60, 100)
    scroll:SetScrollChild(content)
    frame.scroll = scroll
    frame.content = content

    -- Nachladende Item-Daten (GetItemInfo ist asynchron) druecken sich als
    -- GET_ITEM_INFO_RECEIVED-Events aus; ein gebuendelter Refresh reicht.
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
    local data = row.data
    if not data then return end
    GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
    local shown = false
    if data.link then
        local ok = pcall(GameTooltip.SetHyperlink, GameTooltip, data.link)
        shown = ok
    elseif data.itemID then
        local ok = pcall(GameTooltip.SetItemByID, GameTooltip, data.itemID)
        shown = ok
    end
    if data.breakdown then
        if shown then GameTooltip:AddLine(" ") end
        for _, line in ipairs(data.breakdown) do
            GameTooltip:AddLine(line, 0.9, 0.9, 0.9)
        end
    end
    GameTooltip:Show()
end

local function rowOnLeave()
    GameTooltip:Hide()
end

local function rowOnClick(row)
    local data = row.data
    if data and data.link and IsShiftKeyDown() and ChatEdit_InsertLink then
        ChatEdit_InsertLink(data.link)
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
    row:SetPoint("LEFT", 2, 0)
    row:SetPoint("RIGHT", -2, 0)
    row:EnableMouse(true)
    row:SetScript("OnEnter", rowOnEnter)
    row:SetScript("OnLeave", rowOnLeave)
    row:SetScript("OnClick", rowOnClick)

    local highlight = row:CreateTexture(nil, "HIGHLIGHT")
    highlight:SetAllPoints()
    highlight:SetColorTexture(1, 0.82, 0.2, 0.08)

    row.check = CreateFrame("CheckButton", nil, row, "UICheckButtonTemplate")
    row.check:SetSize(22, 22)
    row.check:SetPoint("LEFT", 0, 0)
    row.check:SetScript("OnClick", function(check)
        local data = check:GetParent().data
        if data and data.roadmapKey then
            GCP.Roadmap:SetChecked(data.roadmapKey, check:GetChecked())
            UI:Refresh()
        end
    end)

    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(18, 18)
    row.icon:SetPoint("LEFT", 26, 0)

    row.text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    row.text:SetPoint("LEFT", 50, 0)
    row.text:SetPoint("RIGHT", -240, 0)
    row.text:SetJustifyH("LEFT")
    row.text:SetWordWrap(false)

    row.badge = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.badge:SetPoint("RIGHT", -130, 0)
    row.badge:SetJustifyH("RIGHT")

    row.value = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    row.value:SetPoint("RIGHT", -4, 0)
    row.value:SetJustifyH("RIGHT")

    self.rows[index] = row
    return row
end

-- Setzt eine Zeile komplett zurueck, damit kein Zustand des vorherigen
-- Tabs durchscheint.
local function resetRow(row)
    row.data = nil
    row.check:Hide()
    row.icon:SetTexture(nil)
    row.icon:Hide()
    row.text:SetText("")
    row.text:SetPoint("LEFT", 50, 0)
    row.badge:SetText("")
    row.value:SetText("")
end

function UI:LayoutRows(count)
    local content = self.frame.content
    local y = 0
    for index = 1, count do
        local row = self.rows[index]
        row:SetPoint("TOPLEFT", content, "TOPLEFT", 2, -y)
        row:SetPoint("TOPRIGHT", content, "TOPRIGHT", -2, -y)
        y = y + (row.isHeader and HEADER_HEIGHT or ROW_HEIGHT)
    end
    for index = count + 1, #self.rows do
        self.rows[index]:Hide()
    end
    content:SetHeight(math.max(y + 8, 100))
end

-- ---------------------------------------------------------------------------
-- Tab-Inhalte
-- ---------------------------------------------------------------------------

function UI:AddHeaderRow(index, text)
    local row = self:AcquireRow(index)
    resetRow(row)
    row.isHeader = true
    row:SetHeight(HEADER_HEIGHT)
    row.text:SetText(GCP.Constants.COLOR_GOLD .. text .. "|r")
    row.text:SetPoint("LEFT", 4, -4)
    return row
end

function UI:AddDataRow(index)
    local row = self:AcquireRow(index)
    resetRow(row)
    row.isHeader = false
    row:SetHeight(ROW_HEIGHT)
    return row
end

function UI:RenderToday()
    local Prices = GCP.Prices
    local plan = GCP.Roadmap:Generate()
    local index = 0
    local lastCategory
    for _, entry in ipairs(plan.entries) do
        if entry.category ~= lastCategory then
            index = index + 1
            self:AddHeaderRow(index, entry.category)
            lastCategory = entry.category
        end
        index = index + 1
        local row = self:AddDataRow(index)
        row.data = { roadmapKey = entry.key }
        row.check:Show()
        row.check:SetChecked(entry.done)
        local text = entry.text
        if entry.done then
            text = GCP.Constants.COLOR_GRAY .. text .. "|r"
        end
        row.text:SetText(text)
        row.text:SetPoint("LEFT", 50, 0)
        if entry.value then
            row.value:SetText(GCP.Constants.COLOR_GREEN .. Prices:FormatGold(entry.value) .. "|r")
        end
    end
    if index == 0 then
        index = 1
        local row = self:AddDataRow(index)
        row.text:SetText("Keine Vorschläge – fehlt die Preisbasis? Im AH einen Auctionator-Scan starten.")
    end
    self.frame.summary:SetText(string.format(
        "Offenes Tagespotenzial: %s%s|r   ·   Bereits erledigt: %s%s|r",
        GCP.Constants.COLOR_GREEN, Prices:FormatGold(plan.openValue),
        GCP.Constants.COLOR_GRAY, Prices:FormatGold(plan.doneValue)))
    self:LayoutRows(index)
end

function UI:RenderSell()
    local Prices = GCP.Prices
    local report = GCP.Advisor:BuildReport(self.scope, self.filter)
    local index = 0
    for _, item in ipairs(report.rows) do
        index = index + 1
        local row = self:AddDataRow(index)
        local sourcesText = {}
        for label, count in pairs(item.sources or {}) do
            sourcesText[#sourcesText + 1] = string.format("%s ×%d", label, count)
        end
        table.sort(sourcesText)
        local breakdown = {
            string.format("Bester Kanal: %s%s|r – %s je Stück",
                channelColors[item.channel] or "", item.channel, Prices:FormatMoney(item.unitValue)),
        }
        if item.marketUnit then
            breakdown[#breakdown + 1] = string.format("AH-Preis (%s): %s brutto, %s nach Gebühr",
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
        row.data = {
            itemID = item.itemID,
            link = item.link,
            breakdown = breakdown,
        }
        if item.icon then
            row.icon:SetTexture(item.icon)
            row.icon:Show()
        end
        row.text:SetText(string.format("%s  ×%d", coloredItemName(item), item.count))
        local channelColor = channelColors[item.channel] or ""
        row.badge:SetText(channelColor .. item.channel .. "|r")
        row.value:SetText(Prices:FormatMoney(item.totalValue))
    end
    if index == 0 then
        index = 1
        local row = self:AddDataRow(index)
        row.text:SetText("Nichts gefunden – anderer Filter, oder erst ein Auctionator-Scan?")
    end
    local scopeText = report.accountWide and "Account (Syndicator)" or "nur Taschen"
    local hint = report.missingPrice > 0
        and string.format("   ·   %d Items ohne Marktpreis", report.missingPrice) or ""
    self.frame.summary:SetText(string.format(
        "Gesamtwert (%s): %s%s|r%s",
        scopeText, GCP.Constants.COLOR_GREEN, Prices:FormatGold(report.totalValue), hint))
    self:LayoutRows(index)
end

function UI:RenderFlips()
    local Prices = GCP.Prices
    local C = GCP.Constants
    local flips = GCP.Flips:Build()
    local index = 0

    index = index + 1
    self:AddHeaderRow(index, "Motes → Ur-Partikel (10:1, Kombinieren ist endgültig)")
    for _, row in ipairs(flips.motes) do
        index = index + 1
        local line = self:AddDataRow(index)
        line.data = { itemID = row.primalID }
        if row.icon then
            line.icon:SetTexture(row.icon)
            line.icon:Show()
        end
        local ownText = row.ownedMotes > 0
            and string.format("  (du hast %d Motes)", row.ownedMotes) or ""
        line.text:SetText(string.format("%s – Mote %s, Partikel %s%s",
            row.name or "?", Prices:FormatMoney(row.motePrice),
            Prices:FormatMoney(row.primalPrice), ownText))
        local profitColor = row.buyProfit > 0 and C.COLOR_GREEN or C.COLOR_RED
        line.badge:SetText(row.combineDelta > 0 and "kombinieren" or "einzeln verkaufen")
        line.value:SetText(string.format("%sKauf-Flip %s|r",
            profitColor, Prices:FormatGold(row.buyProfit)))
    end
    if #flips.motes == 0 then
        index = index + 1
        self:AddDataRow(index).text:SetText("Keine Mote-Preise vorhanden – Auctionator-Scan nötig.")
    end

    index = index + 1
    self:AddHeaderRow(index, "Essenzen 3:1 (benötigt Verzauberkunst)")
    for _, row in ipairs(flips.essences) do
        index = index + 1
        local line = self:AddDataRow(index)
        line.data = { itemID = row.greaterID }
        if row.icon then
            line.icon:SetTexture(row.icon)
            line.icon:Show()
        end
        line.text:SetText(string.format("%s – niedere %s, hohe %s",
            row.name or "?", Prices:FormatMoney(row.lesserPrice),
            Prices:FormatMoney(row.greaterPrice)))
        line.badge:SetText(row.direction == "up" and "3 niedere → 1 hohe" or "1 hohe → 3 niedere")
        local profitColor = row.profit > 0 and C.COLOR_GREEN or C.COLOR_RED
        line.value:SetText(profitColor .. Prices:FormatGold(row.profit) .. "|r")
    end
    if #flips.essences == 0 then
        index = index + 1
        self:AddDataRow(index).text:SetText("Keine Essenz-Preise vorhanden – Auctionator-Scan nötig.")
    end

    self.frame.summary:SetText("Kauf-Flip = Zutaten im AH kaufen, Ergebnis mit Gewinn wieder einstellen. Alle Werte nach 5 % AH-Gebühr.")
    self:LayoutRows(index)
end

-- ---------------------------------------------------------------------------
-- Steuerung
-- ---------------------------------------------------------------------------

function UI:SelectTab(key)
    self.activeTab = key
    self:Refresh()
end

function UI:Refresh()
    local frame = self:EnsureFrame()
    for tabKey, tab in pairs(frame.tabs) do
        tab:SetEnabled(tabKey ~= self.activeTab)
    end
    local isSell = self.activeTab == "sell"
    frame.toolbar:SetShown(isSell)
    if isSell then
        frame.scopeButton:SetText(self.scope == "account" and "Umfang: Account" or "Umfang: Taschen")
        local filterLabels = { all = "Filter: Alles", mats = "Filter: Mats", gear = "Filter: Ausrüstung" }
        frame.filterButton:SetText(filterLabels[self.filter or "all"])
    end

    frame.source:SetText("Preise: " .. GCP.Prices:GetActiveSourceLabel())
    local trendDelta = GCP.Roadmap:GetGoldTrend()
    if trendDelta then
        local color = trendDelta >= 0 and GCP.Constants.COLOR_GREEN or GCP.Constants.COLOR_RED
        local sign = trendDelta >= 0 and "+" or ""
        frame.trend:SetText(string.format("Goldverlauf 7 Tage: %s%s%s|r",
            color, sign, GCP.Prices:FormatGold(trendDelta)))
    else
        frame.trend:SetText(GCP.Constants.COLOR_GRAY .. "Goldverlauf entsteht ab morgen – einfach täglich einloggen.|r")
    end

    if self.activeTab == "today" then
        self:RenderToday()
    elseif self.activeTab == "sell" then
        self:RenderSell()
    else
        self:RenderFlips()
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
