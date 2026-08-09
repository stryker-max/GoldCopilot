-- Render-Test fuer UI.lua: baut das Fenster mit einer Frame-Attrappe auf und
-- zeichnet jeden Tab einmal ohne und einmal mit Markthistorie. smoke.lua prueft
-- die Rechenwege, dieser Test die Oberflaeche - Layoutfehler, vergessene
-- Spalten und Tooltips, die nie erscheinen, faellt sonst niemandem auf.
--
-- Bewusst eine eigene Datei mit eigenem Lua-Zustand: Die reichhaltigere
-- Attrappe darf das Verhalten der bestehenden Tests nicht verschieben.
-- Start ueber "node tests/run.mjs" aus dem Repo-Wurzelverzeichnis.

unpack = unpack or table.unpack

local passed, failed = 0, 0
local function expect(condition, label)
    if condition then
        passed = passed + 1
    else
        failed = failed + 1
        print("FEHLSCHLAG: " .. label)
    end
end

local function expectEqual(actual, wanted, label)
    expect(actual == wanted, string.format("%s (erwartet %s, erhalten %s)",
        label, tostring(wanted), tostring(actual)))
end

local mockNow = os.time({ year = 2026, month = 9, day = 1, hour = 8 })
function date(fmt, t) return os.date(fmt, t or mockNow) end
function time(spec)
    if type(spec) == "table" then return os.time(spec) end
    return mockNow
end
function GetTime() return mockNow end
function GetQuestResetTime() return 3600 end
function GetMoney() return 100000 end
function UnitLevel() return 70 end
function InCombatLockdown() return false end
function IsShiftKeyDown() return false end

DEFAULT_CHAT_FRAME = { AddMessage = function() end }
SlashCmdList = {}
UISpecialFrames = {}
function tinsert(list, value) list[#list + 1] = value end

local timers = {}
C_Timer = { After = function(_, fn) timers[#timers + 1] = fn end }

-- --- Attrappen fuer Texturen, Fontstrings und Frames ------------------------

local function newTexture()
    local tex = { _shown = true }
    return setmetatable(tex, { __index = function(t, key)
        if key == "IsShown" then return function(self) return self._shown end end
        if key == "Show" then return function(self) self._shown = true end end
        if key == "Hide" then return function(self) self._shown = false end end
        if key == "SetShown" then return function(self, v) self._shown = v and true or false end end
        if type(key) == "string" and key:match("^%u") then return function() end end
        return nil
    end })
end

local function newFontString()
    local fs = { _text = "", _shown = true }
    function fs:SetFont(font, size) assert(type(font) == "string", "SetFont ohne Font")
        assert(type(size) == "number", "SetFont ohne Groesse") end
    function fs:SetText(text)
        assert(text == nil or type(text) == "string" or type(text) == "number",
            "SetText mit " .. type(text))
        self._text = text and tostring(text) or ""
    end
    function fs:GetText() return self._text end
    function fs:SetTextColor(r, g, b)
        assert(type(r) == "number" and type(g) == "number" and type(b) == "number",
            "SetTextColor ohne Farbe")
    end
    function fs:GetStringWidth() return #self._text * 6 end
    function fs:Show() self._shown = true end
    function fs:Hide() self._shown = false end
    function fs:IsShown() return self._shown end
    function fs:SetShown(v) self._shown = v and true or false end
    return setmetatable(fs, { __index = function(_, key)
        if type(key) == "string" and key:match("^%u") then return function() end end
        return nil
    end })
end

local frameMethods = {}
local frameMeta = { __index = function(t, key)
    local method = frameMethods[key]
    if method then return method end
    if type(key) == "string" and key:match("^%u") then return function() end end
    return nil
end }

function frameMethods.CreateTexture() return newTexture() end
function frameMethods.CreateFontString() return newFontString() end
function frameMethods.SetScript(self, name, fn) self._scripts[name] = fn end
function frameMethods.GetScript(self, name) return self._scripts[name] end
function frameMethods.Show(self) self._shown = true
    local fn = self._scripts.OnShow; if fn then fn(self) end end
function frameMethods.Hide(self) self._shown = false end
function frameMethods.IsShown(self) return self._shown end
function frameMethods.SetShown(self, v) self._shown = v and true or false end
function frameMethods.SetHeight(self, h) self._height = h end
function frameMethods.GetHeight(self) return self._height or 26 end
function frameMethods.SetWidth(self, w) self._width = w end
function frameMethods.GetWidth(self) return self._width or 100 end
function frameMethods.SetSize(self, w, h) self._width, self._height = w, h end
function frameMethods.GetParent(self) return self._parent end
function frameMethods.RegisterEvent(self, event)
    assert(type(event) == "string", "RegisterEvent ohne Ereignisnamen")
end

function CreateFrame(_, _, parent)
    return setmetatable({ _shown = false, _scripts = {}, _parent = parent }, frameMeta)
end

UIParent = CreateFrame("Frame")

GameTooltip = setmetatable({}, { __index = function(_, key)
    if type(key) == "string" and key:match("^%u") then return function() return true end end
    return nil
end })

-- --- Daten ------------------------------------------------------------------

local items = {
    [21884] = { "Urfeuer", "item:21884", 1, 65, 0, "Handwerkswaren", "Elementar", 20, "", 101, 0, 7 },
    [22574] = { "Feuerpartikel", "item:22574", 1, 65, 0, "Handwerkswaren", "Elementar", 20, "", 108, 0, 7 },
    [23425] = { "Adamantiterz", "item:23425", 1, 65, 0, "Handwerkswaren", "Metall", 20, "", 116, 25, 7 },
    [22785] = { "Teufelsgras", "item:22785", 1, 60, 0, "Handwerkswaren", "Kraut", 20, "", 117, 5, 7 },
    [10938] = { "Niedere Magieessenz", "item:10938", 2, 15, 0, "Handwerkswaren", "Verzauberung", 10, "", 119, 0, 7 },
    [10939] = { "Hohe Magieessenz", "item:10939", 2, 20, 0, "Handwerkswaren", "Verzauberung", 10, "", 120, 0, 7 },
    [60001] = { "Knusperschlange", "item:60001", 1, 70, 0, "Verbrauchbar", "Essen", 20, "", 126, 2, 0 },
    [60002] = { "Schlangenfleisch", "item:60002", 1, 65, 0, "Handwerkswaren", "Fleisch", 20, "", 127, 1, 7 },
}
function GetItemInfo(item)
    local id = tonumber(item) or tonumber(tostring(item):match("item:(%d+)"))
    local entry = items[id]
    if not entry then return nil end
    return unpack(entry)
end
C_Item = { GetItemInfo = GetItemInfo }

local marketPrices = {
    [21884] = 1300, [22574] = 100, [23425] = 50000, [22785] = 800,
    [10938] = 100, [10939] = 400, [60001] = 8000, [60002] = 2000,
}
Auctionator = { API = { v1 = {
    GetAuctionPriceByItemID = function(_, id) return marketPrices[id] end,
    GetDisenchantPriceByItemLink = function() return nil end,
    GetAuctionAgeByItemID = function() return 0 end,
    RegisterForDBUpdate = function() end,
} } }

local bags = {
    [0] = { { itemID = 23425, stackCount = 40, hyperlink = "item:23425" },
            { itemID = 22574, stackCount = 25, hyperlink = "item:22574" } },
}
C_Container = {
    GetContainerNumSlots = function(bag) return bags[bag] and #bags[bag] or 0 end,
    GetContainerItemInfo = function(bag, slot) return bags[bag] and bags[bag][slot] end,
}

function GetNumSkillLines() return 2 end
function GetSkillLineInfo(index)
    if index == 1 then return "Kräuterkunde", false, nil, 375 end
    return "Bergbau", false, nil, 375
end
function IsPlayerSpell() return true end
function GetSpellCooldown() return 0, 0, 1 end
C_QuestLog = { IsQuestFlaggedCompleted = function() return false end }
function GetNumQuestLogEntries() return 0 end

-- --- Addon laden und alle Tabs rendern --------------------------------------

local GCP = {}
for _, file in ipairs({
    "Constants.lua", "Core.lua",
    "Knowledge/Knowledge.lua", "Knowledge/Phases.lua", "Knowledge/Items.lua",
    "Knowledge/Recipes.lua", "Knowledge/Catalysts.lua", "Knowledge/Locations.lua",
    "Prices.lua", "Inventory.lua", "Advisor.lua",
    "Flips.lua", "Crafts.lua", "Market.lua", "Ledger.lua", "Opportunity.lua", "Future.lua", "Capital.lua", "Execution.lua", "Route.lua", "Navigation.lua", "Guide.lua",
    "Quests.lua", "Roadmap.lua", "UI.lua",
}) do
    local chunk, err = loadfile(file)
    assert(chunk, "Ladefehler in " .. file .. ": " .. tostring(err))
    chunk("GoldCopilot", GCP)
end

GCP:EnsureDB()

local TABS = { "today", "sell", "flips", "crafts", "market", "chancen", "zukunft", "handel", "options" }

-- Kaltstart: jeder Tab muss auch ohne eine einzige Zeile Historie zeichnen.
for _, tab in ipairs(TABS) do
    local ok, err = pcall(GCP.UI.SelectTab, GCP.UI, tab)
    expect(ok, string.format("Tab \"%s\" zeichnet beim Kaltstart (%s)", tab, tostring(err)))
end

GCP.UI:SelectTab("market")
local coldSummary = GCP.UI.frame.summary:GetText()
expect(coldSummary:find("beobachtet") ~= nil,
    "Der Markt-Tab nennt die Zahl der beobachteten Märkte")
expect(coldSummary:find("noch keine Preispunkte") ~= nil,
    "Der Kaltstart sagt ausdrücklich, dass noch keine Daten vorliegen")
local coldText = {}
for _, row in ipairs(GCP.UI.rows) do
    coldText[#coldText + 1] = row.text:GetText() or ""
end
expect(table.concat(coldText, "\n"):find("lernt deinen Realm") ~= nil,
    "Der Kaltstart erklärt, dass das Addon erst lernt")

-- Historie ueber gut eine Woche, damit Score und Confidence etwas zu tun haben.
local base = mockNow - 8 * 86400
for step = 0, 15 do
    local stamp = base + step * 12 * 3600
    for itemID, price in pairs(marketPrices) do
        local wobble = 1 + ((step % 4) - 1.5) * 0.08
        GCP.Market:AddSnapshot(itemID, math.floor(price * wobble), stamp, "Auctionator")
    end
end
GCP.Market:InvalidateCaches()

for _, tab in ipairs(TABS) do
    local ok, err = pcall(GCP.UI.SelectTab, GCP.UI, tab)
    expect(ok, string.format("Tab \"%s\" zeichnet mit Historie (%s)", tab, tostring(err)))
end

-- Kopfzeile und Spalten des Markt-Tabs.
GCP.UI:SelectTab("market")
local header = GCP.UI.rows[1]
expectEqual(header.cols[1]:GetText(), "PERZENTIL", "Spaltenkopf Perzentil")
expectEqual(header.cols[2]:GetText(), "30T MEDIAN", "Spaltenkopf 30-Tage-Median")
expectEqual(header.cols[3]:GetText(), "7T MEDIAN", "Spaltenkopf 7-Tage-Median")
expectEqual(header.cols[4]:GetText(), "JETZT", "Spaltenkopf Jetzt")
expectEqual(header.value:GetText(), "SCORE", "Spaltenkopf Score")

local warmSummary = GCP.UI.frame.summary:GetText()
expect(warmSummary:find("Preispunkte") ~= nil, "Die Kopfzeile zählt die Preispunkte")
expect(warmSummary:find("Historie") ~= nil, "Die Kopfzeile nennt die Länge der Historie")

-- Erste Datenzeile: alle fuenf Spalten gefuellt, Tooltip vollstaendig.
local row = GCP.UI.rows[2]
expect(row ~= nil, "Der Markt-Tab erzeugt Datenzeilen")
expect(row.text:GetText() ~= "", "Die Zeile nennt das Item")
for column = 1, 4 do
    expect(row.cols[column]:GetText() ~= "",
        string.format("Spalte %d der Datenzeile ist gefüllt", column))
end
expect(row.value:GetText() ~= "", "Die Score-Spalte ist gefüllt")
expect(row.autoPill:IsShown(), "Die Confidence steht als eigenes Etikett daneben")

local breakdown = table.concat(row.data.breakdown, "\n")
for _, needle in ipairs({
    "Aktuell:", "24h Median:", "7d Median:", "30d Median:", "7d Range:",
    "Perzentil:", "Volatilität:", "Snapshots:", "Historientage:",
    "Market Score:", "Confidence:",
}) do
    expect(breakdown:find(needle, 1, true) ~= nil,
        "Der Tooltip nennt \"" .. needle .. "\"")
end
expect(breakdown:find("Nachfrage", 1, true) ~= nil,
    "Der Tooltip sagt ausdrücklich, was der Score nicht bedeutet")

-- Sortierung: der Score faellt von oben nach unten.
local previous = nil
for index = 2, #GCP.UI.rows do
    local line = GCP.UI.rows[index]
    -- Nur sichtbare Zeilen: Der Zeilen-Pool traegt hinter der letzten Zeile noch
    -- die Zahlen des zuletzt gezeichneten Tabs.
    local score = line:IsShown() and tonumber(line.value:GetText() or "") or nil
    if score then
        if previous then
            expect(score <= previous, "Der Markt-Tab sortiert nach Score absteigend")
        end
        previous = score
    end
end

-- Mausereignisse und Klick dürfen nicht in die Wand laufen.
expect(pcall(row:GetScript("OnEnter"), row), "Tooltip einer Marktzeile öffnet")
expect(pcall(row:GetScript("OnLeave"), row), "Tooltip einer Marktzeile schließt")
expect(pcall(row:GetScript("OnClick"), row, "LeftButton"), "Klick auf eine Marktzeile")

-- --- Chancen-Tab ------------------------------------------------------------

-- Mit den Standardfiltern (5 g Mindestprofit) faellt eine 235-Kupfer-Chance
-- durch. Genau dieser Zustand muss auch etwas Verstaendliches zeichnen.
GCP.UI:SelectTab("chancen")
local filteredSummary = GCP.UI.frame.summary:GetText()
expect(filteredSummary:find("Chance") ~= nil,
    "Der Chancen-Tab zeigt auch mit leerer Liste eine Kopfzeile")
local filteredText = {}
for _, line in ipairs(GCP.UI.rows) do
    filteredText[#filteredText + 1] = line.text:GetText() or ""
end
expect(table.concat(filteredText, "\n"):find("Mindestprofit") ~= nil,
    "Ausgefilterte Chancen werden als Filterergebnis erklärt, nicht verschwiegen")

-- Ohne Filter bleiben die Conversion-Chancen der Attrappe stehen.
GCP.db.options.opportunityMinProfit = 0
GCP.db.options.opportunityMinROI = 0
GCP.Opportunity:Invalidate()
GCP.UI:SelectTab("chancen")

local oppHead = GCP.UI.rows[1]
expectEqual(oppHead.value:GetText(), "SCORE", "Spaltenkopf Score")
expectEqual(oppHead.typeText:GetText(), "TYP", "Spaltenkopf Typ")
expectEqual(oppHead.text:GetText(), "AKTION", "Spaltenkopf Aktion")
expectEqual(oppHead.cols[1]:GetText(), "LIQ.", "Spaltenkopf Liquidität")
expectEqual(oppHead.cols[2]:GetText(), "ROI", "Spaltenkopf ROI")
expectEqual(oppHead.cols[3]:GetText(), "PROFIT", "Spaltenkopf Profit")
expectEqual(oppHead.cols[4]:GetText(), "KAPITAL", "Spaltenkopf Kapital")

local oppSummary = GCP.UI.frame.summary:GetText()
expect(oppSummary:find("Gold Copilot hat") ~= nil,
    "Die Kopfzeile nennt die Zahl der gefundenen Chancen")
expect(oppSummary:find("KAUF") == nil and oppSummary:find("kaufen!") == nil,
    "Die Kopfzeile schreit nicht \"kaufen\"")

local oppRow = GCP.UI.rows[2]
expect(oppRow ~= nil, "Der Chancen-Tab erzeugt Datenzeilen")
expect(tonumber(oppRow.value:GetText()) ~= nil, "Die Score-Spalte trägt eine Zahl")
expect(oppRow.typeText:GetText() ~= "", "Die Typ-Spalte ist gefüllt")
expect(oppRow.text:GetText() ~= "", "Die Aktion ist benannt")
for column = 1, 3 do
    expect(oppRow.cols[column]:GetText() ~= "",
        string.format("Spalte %d der Chancenzeile ist gefüllt", column))
end
expect(oppRow.pill:IsShown(), "Die Einordnung steht als eigenes Etikett daneben")

local oppBreakdown = table.concat(oppRow.data.breakdown, "\n")
for _, needle in ipairs({
    "Kapitaleinsatz:", "Erlös netto:", "Theoretischer Gewinn:", "ROI:",
    "Opportunity Score:", "Confidence:",
}) do
    expect(oppBreakdown:find(needle, 1, true) ~= nil,
        "Der Tooltip nennt \"" .. needle .. "\"")
end
expect(oppBreakdown:find("Liquidität unbekannt", 1, true) ~= nil,
    "Ohne eigene Verkäufe sagt der Tooltip ausdrücklich \"unbekannt\"")
expect(oppBreakdown:find("PROFIT VELOCITY", 1, true) == nil,
    "...und zeigt keine Profit Velocity, die es nicht gibt")
expect(GCP.UI.frame.summary:GetText():find("Liquidität unbekannt", 1, true) ~= nil,
    "Die Kopfzeile des Chancen-Tabs sagt es ebenfalls")
expectEqual(oppRow.cols[1]:GetText(), "–",
    "Die Liquiditätsspalte trägt einen Strich statt einer erfundenen Zahl")
expect(oppBreakdown:find("keine Zusage", 1, true) ~= nil,
    "Der Tooltip verspricht ausdrücklich keinen Gewinn")

-- Sortierung: der Score faellt von oben nach unten.
local previousOpportunity = nil
for index = 2, #GCP.UI.rows do
    local line = GCP.UI.rows[index]
    -- Nur sichtbare Zeilen: Der Zeilen-Pool traegt hinter der letzten Zeile
    -- noch die Beschriftung des zuletzt gezeichneten Tabs.
    local score = line:IsShown() and tonumber(line.value:GetText() or "") or nil
    if score then
        if previousOpportunity then
            expect(score <= previousOpportunity, "Der Chancen-Tab sortiert nach Score absteigend")
        end
        previousOpportunity = score
    end
end

-- Rechtsklick nimmt in die Beobachtung auf und wieder heraus.
local watchedItem = oppRow.data.watchable
expect(watchedItem ~= nil, "Eine Chancenzeile lässt sich beobachten")
expectEqual(GCP.Market:IsWatched(watchedItem), false, "Vorher ist sie es nicht")
expect(pcall(oppRow:GetScript("OnClick"), oppRow, "RightButton"),
    "Rechtsklick auf eine Chancenzeile")
expectEqual(GCP.Market:IsWatched(watchedItem), true,
    "Rechtsklick nimmt das Item zur Beobachtung auf")
expect(GCP.UI.frame.watchButton.label:GetText():find("1") ~= nil,
    "Der Knopf zeigt die Zahl der beobachteten Items")

GCP.UI:SelectTab("chancen")
GCP.UI.onlyWatched = true
GCP.UI:Refresh()
for index = 2, #GCP.UI.rows do
    local line = GCP.UI.rows[index]
    if line:IsShown() and line.data and line.data.watchable then
        expectEqual(GCP.Market:IsWatched(line.data.watchable), true,
            "Die Beobachtungsansicht zeigt nur beobachtete Items")
    end
end
GCP.UI.onlyWatched = false

expect(pcall(oppRow:GetScript("OnEnter"), oppRow), "Tooltip einer Chancenzeile öffnet")
expect(pcall(oppRow:GetScript("OnLeave"), oppRow), "Tooltip einer Chancenzeile schließt")
expect(pcall(oppRow:GetScript("OnClick"), oppRow, "RightButton"),
    "Rechtsklick nimmt das Item wieder heraus")
expectEqual(GCP.Market:IsWatched(watchedItem), false, "...und danach ist es das auch")

-- Der Markt-Tab kann dasselbe.
GCP.UI:SelectTab("market")
local marketRow = GCP.UI.rows[2]
expect(marketRow.data.watchable ~= nil, "Auch eine Marktzeile lässt sich beobachten")
expect(pcall(marketRow:GetScript("OnClick"), marketRow, "RightButton"),
    "Rechtsklick auf eine Marktzeile")
expectEqual(GCP.Market:IsWatched(marketRow.data.watchable), true,
    "Rechtsklick im Markt-Tab nimmt zur Beobachtung auf")
GCP.Market:RemoveWatchItem(marketRow.data.watchable)

-- Optionen: die neuen Chancen-Filter sind da und getrennt vom Mindestgewinn.
GCP.db.options.minRoadmapValue = 50000
GCP.UI:SelectTab("options")
local panel = GCP.UI.frame.optionsPanel
expect(panel.oppProfitButtons ~= nil, "Die Optionen kennen den Mindestprofit der Chancen")
expect(panel.oppROIButtons ~= nil, "Die Optionen kennen den Mindest-ROI der Chancen")
expect(panel.oppProfitButtons[500000] ~= nil, "Es gibt eine 50-g-Stufe")
expect(panel.oppROIButtons[0.30] ~= nil, "Es gibt eine 30-%-Stufe")
expect(pcall(panel.oppProfitButtons[100000]:GetScript("OnClick")),
    "Ein Klick auf den Mindestprofit der Chancen")
expectEqual(GCP.db.options.opportunityMinProfit, 100000, "...setzt genau diese Option")
expectEqual(GCP.db.options.minRoadmapValue, 50000,
    "...und lässt den Mindestgewinn des Tagesplans in Ruhe")
expect(pcall(panel.oppROIButtons[0.20]:GetScript("OnClick")),
    "Ein Klick auf den Mindest-ROI der Chancen")
expectEqual(GCP.db.options.opportunityMinROI, 0.20, "...setzt genau diese Option")
GCP.db.options.opportunityMinProfit = 0
GCP.db.options.opportunityMinROI = 0

-- --- Zukunft-Tab ------------------------------------------------------------

-- Die Uhr wird relativ zum Phase-3-Termin gestellt: So ist der Abstand exakt
-- zwoelf Tage, egal in welcher Zeitzone der Test laeuft.
local phase3 = GCP.Knowledge:GetPhase("phase3")
mockNow = phase3.release - 12 * 86400 - 3600
GCP.Market:InvalidateCaches()
GCP.Future:Invalidate()
GCP.UI:SelectTab("zukunft")

local futureHead = GCP.UI.rows[1]
expect((futureHead.text:GetText() or ""):find("Nächster bekannter Catalyst") ~= nil,
    "Der Zukunft-Tab beginnt mit dem nächsten bekannten Catalyst")

local futureText = {}
for _, line in ipairs(GCP.UI.rows) do
    if line:IsShown() then futureText[#futureText + 1] = line.text:GetText() or "" end
end
futureText = table.concat(futureText, "\n")
expect(futureText:find("Schwarzer Tempel") ~= nil, "Die nächste Phase wird benannt")
expect(futureText:find("Illidan") ~= nil, "Ihr Inhalt steht darunter")
expect(futureText:find("Wissensstand") ~= nil, "Der Wissensstand steht sichtbar dabei")
expect(GCP.UI.rows[2].value:GetText() == "12 T",
    "Die Tage bis zum Termin stehen an der Phase")

-- Kopfzeile der Tabelle.
local futureTableHead = nil
for index, line in ipairs(GCP.UI.rows) do
    if line:IsShown() and (line.text:GetText() or ""):find("TOP FUTURE") then
        futureTableHead = index
        break
    end
end
expect(futureTableHead ~= nil, "Die Tabelle hat eine eigene Kopfzeile")
local futureCaptions = GCP.UI.rows[futureTableHead]
expectEqual(futureCaptions.value:GetText(), "SIGNAL", "Spaltenkopf Signal")
expectEqual(futureCaptions.cols[1]:GetText(), "CATALYST", "Spaltenkopf Catalyst")
expectEqual(futureCaptions.cols[2]:GetText(), "HYPE", "Spaltenkopf Hype")
expectEqual(futureCaptions.cols[3]:GetText(), "DEMAND", "Spaltenkopf Demand")
expectEqual(futureCaptions.cols[4]:GetText(), "MARKT", "Spaltenkopf Markt")

local futureRow = GCP.UI.rows[futureTableHead + 1]
expect(futureRow ~= nil and futureRow:IsShown(), "Der Zukunft-Tab erzeugt Datenzeilen")
expect(futureRow.text:GetText() ~= "", "Die Zeile nennt das Item")
expect(tonumber(futureRow.cols[3]:GetText()) ~= nil, "Die Demand-Spalte trägt eine Zahl")
expect(futureRow.cols[1]:GetText() ~= "", "Die Catalyst-Spalte ist gefüllt")
expect(futureRow.value:GetText() ~= "", "Die Signal-Spalte ist gefüllt")

local futureBreak = table.concat(futureRow.data.breakdown, "\n")
for _, needle in ipairs({
    "Aktueller Realm-Preis:", "7d Median:", "30d Median:", "Market Score:",
    "FUTURE DEMAND", "Catalysts:", "HYPE", "SIGNAL", "Wissensstand:",
}) do
    expect(futureBreak:find(needle, 1, true) ~= nil,
        "Der Tooltip nennt \"" .. needle .. "\"")
end
expect(futureBreak:find("keine Preisgarantie", 1, true) ~= nil,
    "Der Tooltip sagt ausdrücklich, dass er nichts garantiert")
expect(futureBreak:find("(Modell)", 1, true) ~= nil,
    "Modellwerte sind als solche gekennzeichnet")
expect(futureBreak:find("KAUFEN", 1, true) == nil, "Nirgends steht \"KAUFEN\"")

-- Sortierung: das Signal faellt von oben nach unten.
local previousSignal = nil
for index = futureTableHead + 1, #GCP.UI.rows do
    local line = GCP.UI.rows[index]
    local score = line:IsShown() and tonumber(line.value:GetText() or "") or nil
    if score then
        if previousSignal then
            expect(score <= previousSignal, "Der Zukunft-Tab sortiert nach Signal absteigend")
        end
        previousSignal = score
    end
end

-- Rechtsklick nimmt mit These in die Beobachtung auf.
GCP.db.watchlist = {}
local futureItem = futureRow.data.watchable
expect(futureItem ~= nil, "Eine Zukunftszeile lässt sich beobachten")
expect(pcall(futureRow:GetScript("OnClick"), futureRow, "RightButton"),
    "Rechtsklick auf eine Zukunftszeile")
expectEqual(GCP.Market:IsWatched(futureItem), true, "Das Item ist danach beobachtet")
expectEqual(GCP.Market:GetWatchEntry(futureItem).reason, "future",
    "...mit der Zukunft als Grund")
expectEqual(GCP.Market:GetWatchEntry(futureItem).phase, "phase3",
    "...und der Phase als These")
expect(pcall(futureRow:GetScript("OnEnter"), futureRow), "Tooltip einer Zukunftszeile öffnet")
expect(pcall(futureRow:GetScript("OnLeave"), futureRow), "Tooltip einer Zukunftszeile schließt")
GCP.db.watchlist = {}

-- Eine Phase ohne bekannten Termin muss genauso sauber zeichnen.
local savedRelease = phase3.release
phase3.release = nil
GCP.Future:Invalidate()
expect(pcall(GCP.UI.SelectTab, GCP.UI, "zukunft"),
    "Der Zukunft-Tab zeichnet auch ohne bekannten Termin")
local unknownText = {}
for _, line in ipairs(GCP.UI.rows) do
    if line:IsShown() then
        unknownText[#unknownText + 1] = (line.text:GetText() or "")
            .. " " .. (line.value:GetText() or "")
    end
end
expect(table.concat(unknownText, "\n"):find("Termin offen") ~= nil,
    "Ohne Ankündigung steht \"Termin offen\" statt einer erfundenen Zahl")
phase3.release = savedRelease
GCP.Future:Invalidate()

-- --- Handel-Tab (0.8.0) -----------------------------------------------------

-- Kaltstart: Ohne einen einzigen eigenen Verkauf muss der Tab erklaeren, was er
-- vorhat, statt eine leere Tabelle zu zeigen.
GCP.UI:SelectTab("handel")
local coldLedger = {}
for _, line in ipairs(GCP.UI.rows) do
    if line:IsShown() then coldLedger[#coldLedger + 1] = line.text:GetText() or "" end
end
local coldLedgerText = table.concat(coldLedger, "\n")
expect(coldLedgerText:find("lernt deine Verkäufe", 1, true) ~= nil,
    "Der Handel-Tab sagt beim Kaltstart, dass er erst lernt")
expect(coldLedgerText:find("Kapitalrotation", 1, true) ~= nil,
    "...und wozu die Daten gut sind")
expect(coldLedgerText:find("lokal", 1, true) ~= nil,
    "...und dass nichts den Rechner verlässt")
expect(coldLedgerText:find("7 Tage", 1, true) ~= nil,
    "Die Sieben-Tage-Kopfzeile steht auch im Kaltstart")
expect(GCP.UI.frame.summary:GetText():find("Noch keine eigenen Handelsdaten", 1, true) ~= nil,
    "Die Kopfzeile sagt es ebenfalls")
expect(GCP.UI.frame.ledgerSortButton:IsShown(), "Der Sortierknopf des Handel-Tabs ist sichtbar")

-- Mit Daten: eine gut laufende und eine zaehe Reihe, dazu ein Verkauf ohne
-- zuordenbare Einstellung.
local ledgerBase = mockNow - 6 * 86400
for index = 1, 10 do
    GCP.Ledger:RecordAuctionPosted({ itemID = 23425, quantity = 5, unitPrice = 50000,
        deposit = 400, timestamp = ledgerBase + index * 7200 })
    GCP.Ledger:ApplySaleInvoice({ itemName = "Adamantiterz", total = 250000,
        consignment = 12500, arrivedAt = ledgerBase + index * 7200 + 3 * 3600 })
end
GCP.Ledger:RecordPurchase({ itemID = 23425, quantity = 60, unitPrice = 40000,
    timestamp = ledgerBase })
GCP.Ledger:RecordAuctionPosted({ itemID = 22785, quantity = 20, unitPrice = 800,
    deposit = 100, timestamp = ledgerBase })
GCP.Ledger:RecordAuctionExpired({ itemID = 22785, quantity = 20,
    timestamp = ledgerBase + 48 * 3600 })
GCP.UI:SelectTab("handel")

local ledgerHead = nil
for index, line in ipairs(GCP.UI.rows) do
    if line:IsShown() and line.text:GetText() == "ITEM" then ledgerHead = index end
end
expect(ledgerHead ~= nil, "Der Handel-Tab hat eine Tabellenkopfzeile")
local ledgerCaptions = GCP.UI.rows[ledgerHead]
expectEqual(ledgerCaptions.value:GetText(), "LIQUIDITÄT", "Spaltenkopf Liquidität")
expectEqual(ledgerCaptions.cols[1]:GetText(), "REAL. MARGE", "Spaltenkopf realisierte Marge")
expectEqual(ledgerCaptions.cols[2]:GetText(), "ZEIT", "Spaltenkopf Zeit")
expectEqual(ledgerCaptions.cols[3]:GetText(), "SELL-THROUGH", "Spaltenkopf Sell-through")
expectEqual(ledgerCaptions.cols[4]:GetText(), "ABGELAUFEN", "Spaltenkopf abgelaufen")
expectEqual(ledgerCaptions.cols[5]:GetText(), "VERKAUFT", "Spaltenkopf verkauft")

local ledgerRow = GCP.UI.rows[ledgerHead + 1]
expect(ledgerRow ~= nil, "Der Handel-Tab erzeugt Datenzeilen")
expect(ledgerRow.text:GetText() ~= "", "Die Zeile nennt das Item")
for column = 1, 5 do
    expect(ledgerRow.cols[column]:GetText() ~= "",
        string.format("Spalte %d der Handelszeile ist gefüllt", column))
end
expect(tonumber(ledgerRow.value:GetText()) ~= nil,
    "Die beste Zeile trägt einen echten Liquidity Score")

local ledgerBreak = table.concat(ledgerRow.data.breakdown, "\n")
for _, needle in ipairs({
    "Eingestellt:", "Verkauft:", "Abgelaufen:", "Zurückgezogen:",
    "Sell-through (Stückzahl):", "Median bis Verkauf:", "Dein Einkauf (Median):",
    "Dein Verkauf netto (Median):", "Realisierte Marge:", "Liquidity Score:",
}) do
    expect(ledgerBreak:find(needle, 1, true) ~= nil,
        "Der Handel-Tooltip nennt \"" .. needle .. "\"")
end
expect(ledgerBreak:find("kein Fehlschlag", 1, true) ~= nil,
    "Der Tooltip sagt, dass ein Abbruch kein Fehlschlag ist")
expect(ledgerBreak:find("lokal", 1, true) ~= nil,
    "...und dass die Daten lokal bleiben")

local ledgerSummary = GCP.UI.frame.summary:GetText()
expect(ledgerSummary:find("Verkauf", 1, true) ~= nil,
    "Die Kopfzeile nennt die Zahl der Verkäufe")
expect(ledgerSummary:find("Umsatz netto", 1, true) ~= nil, "...und den Nettoumsatz")

-- Sortierung: der Knopf schaltet um, und die Liste folgt.
local sortedByLiquidity = {}
for index = ledgerHead + 1, #GCP.UI.rows do
    local line = GCP.UI.rows[index]
    local score = line:IsShown() and tonumber(line.value:GetText() or "") or nil
    if score then sortedByLiquidity[#sortedByLiquidity + 1] = score end
end
for index = 2, #sortedByLiquidity do
    expect(sortedByLiquidity[index] <= sortedByLiquidity[index - 1],
        "Der Handel-Tab sortiert nach Liquidity Score absteigend")
end
expect(pcall(GCP.UI.frame.ledgerSortButton:GetScript("OnClick")),
    "Der Sortierknopf des Handel-Tabs lässt sich klicken")
expectEqual(GCP.db.options.ledgerSort, "profit", "...und schaltet auf den realisierten Gewinn")
expect(pcall(GCP.UI.SelectTab, GCP.UI, "handel"),
    "Der Handel-Tab zeichnet auch in der zweiten Sortierung")
expect(GCP.UI.frame.ledgerSortButton.label:GetText():find("Gewinn", 1, true) ~= nil,
    "Der Knopf beschriftet die aktive Sortierung")
GCP.db.options.ledgerSort = "liquidity"

-- Tooltip und Rechtsklick einer Handelszeile.
GCP.db.watchlist = {}
GCP.UI:SelectTab("handel")
local watchRow = GCP.UI.rows[ledgerHead + 1]
expect(pcall(watchRow:GetScript("OnEnter"), watchRow), "Tooltip einer Handelszeile öffnet")
expect(pcall(watchRow:GetScript("OnLeave"), watchRow), "Tooltip einer Handelszeile schließt")
expect(pcall(watchRow:GetScript("OnClick"), watchRow, "RightButton"),
    "Rechtsklick auf eine Handelszeile")
expectEqual(GCP.Market:IsWatched(watchRow.data.watchable), true,
    "...nimmt das Item in die Beobachtung auf")
GCP.db.watchlist = {}

-- Ein Verkauf ohne zuordenbare Einstellung schaltet die stueckzahlbasierte
-- Rate ab - und die Oberflaeche sagt das mit einem Stern statt einer Zahl,
-- die zu niedrig waere.
GCP.Ledger:ApplySaleInvoice({ itemName = "Adamantiterz", total = 99999,
    arrivedAt = mockNow - 600 })
GCP.UI:SelectTab("handel")
local starText = {}
for index = ledgerHead, #GCP.UI.rows do
    local line = GCP.UI.rows[index]
    if line:IsShown() then starText[#starText + 1] = line.cols[3]:GetText() or "" end
end
expect(table.concat(starText, " "):find("*", 1, true) ~= nil,
    "Eine Rate je Auktion statt je Stück wird mit * gekennzeichnet")

-- --- Erweiterte Tooltips mit Handelsdaten -----------------------------------

GCP.db.options.opportunityMinProfit = 0
GCP.db.options.opportunityMinROI = 0
GCP.Opportunity:Invalidate()

-- Welche Chance die Attrappe gerade hergibt, ist fuer diese Pruefung egal -
-- entscheidend ist, dass genau die Chance mit eigener Verkaufsgeschichte sie
-- auch im Tooltip zeigt. Also bekommt das Item der ersten Chance eine.
local coldOpportunities = GCP.Opportunity:BuildReport(true).opportunities
expect(#coldOpportunities > 0, "Die Attrappe liefert mindestens eine Chance")
local oppItemID = coldOpportunities[1].itemID
local oppItemName = GetItemInfo(oppItemID)
for index = 1, 8 do
    GCP.Ledger:RecordAuctionPosted({ itemID = oppItemID, quantity = 4, unitPrice = 25000,
        timestamp = ledgerBase + index * 7200 })
    GCP.Ledger:ApplySaleInvoice({ itemName = oppItemName, total = 100000,
        consignment = 5000, arrivedAt = ledgerBase + index * 7200 + 5 * 3600 })
end
GCP.Ledger:RecordAuctionPosted({ itemID = oppItemID, quantity = 4, unitPrice = 25000,
    timestamp = ledgerBase + 90 * 3600 })
GCP.Ledger:RecordAuctionExpired({ itemID = oppItemID, quantity = 4,
    timestamp = ledgerBase + 138 * 3600 })
GCP.Opportunity:Invalidate()

GCP.UI:SelectTab("chancen")
local warmOpp, warmText = nil, nil
for index = 2, #GCP.UI.rows do
    local line = GCP.UI.rows[index]
    if line:IsShown() and line.data and line.data.breakdown then
        local text = table.concat(line.data.breakdown, "\n")
        if text:find("DEINE VERKAUFSDATEN", 1, true) then
            warmOpp, warmText = line, text
            break
        end
    end
end
expect(warmOpp ~= nil, "Eine Chance mit eigenen Verkaufsdaten zeigt sie im Tooltip")
if warmOpp then
    for _, needle in ipairs({ "Sell-through", "Median bis Verkauf", "Verkäufe:",
        "Liquidity Score:" }) do
        expect(warmText:find(needle, 1, true) ~= nil,
            "Der Chancen-Tooltip nennt \"" .. needle .. "\"")
    end
    expect(warmText:find("PROFIT VELOCITY", 1, true) ~= nil,
        "Der Chancen-Tooltip zeigt die Profit Velocity, sobald es sie gibt")
    expect(warmText:find("100 g / Tag", 1, true) ~= nil,
        "...und zwar als Gewinn je 100 g gebundenem Kapital und Tag")
    expect(warmText:find("nicht je Menge", 1, true) ~= nil,
        "...mit dem Hinweis, dass die Markttiefe unbekannt bleibt")
    expect(warmText:find("KAUFEN", 1, true) == nil,
        "Auch mit Verkaufsdaten steht nirgends \"KAUFEN\"")
    expect(warmOpp.cols[1]:GetText() ~= "–",
        "Die Liquiditätsspalte der Zeile trägt jetzt eine Zahl")
    expect(warmText:find("Deine Spur zu diesem Item", 1, true) ~= nil,
        "Der Tooltip nennt den belegten Ausführungsstatus")
    expect(warmOpp.autoPill:IsShown(), "...und die Zeile trägt ihn als Etikett")
end

-- Der Zukunft-Tooltip bekommt dieselbe Dimension - ohne den Demand zu ruehren.
GCP.Future:Invalidate()
GCP.UI:SelectTab("zukunft")
local futureLiquidity = {}
for _, line in ipairs(GCP.UI.rows) do
    if line:IsShown() and line.data and line.data.breakdown then
        futureLiquidity[#futureLiquidity + 1] = table.concat(line.data.breakdown, "\n")
    end
end
expect(table.concat(futureLiquidity, "\n"):find("Liquidität", 1, true) ~= nil,
    "Der Zukunft-Tooltip nennt die persönliche Liquidität als eigene Dimension")

GCP.db.options.opportunityMinProfit = 0
GCP.db.options.opportunityMinROI = 0

-- Fenster oeffnen loest OnShow samt Aufzeichnung aus.
-- Die Optionen weisen die Handelsbilanz mitsamt Datenschutzsatz aus.
GCP.UI:SelectTab("options")
local optionsData = GCP.UI.frame.optionsPanel.dataText:GetText()
expect(optionsData:find("Handelsbilanz", 1, true) ~= nil,
    "Die Datenübersicht nennt die Handelsbilanz")
expect(optionsData:find("bleibt lokal", 1, true) ~= nil,
    "...und sagt ausdrücklich, dass sie den Rechner nicht verlässt")

expect(pcall(GCP.UI.Toggle, GCP.UI), "Das Fenster lässt sich öffnen")
for _, fn in ipairs(timers) do fn() end
expect(GCP.UI.frame:IsShown(), "Nach dem Öffnen ist das Fenster sichtbar")

print(string.format("ui.lua: %d Tests bestanden, %d fehlgeschlagen", passed, failed))
if failed > 0 then
    error("Es gibt fehlgeschlagene Tests.")
end
