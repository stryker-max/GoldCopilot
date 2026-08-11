-- End-to-End-Simulation fuer Gold Copilot (0.9.0)
--
-- smoke.lua prueft Rechenwege, ui.lua die Oberflaeche, engine.lua die
-- Entscheidungsschicht. Was allen dreien fehlt, ist die Frage, auf die es am
-- Ende ankommt:
--
--     Funktioniert eine GANZE SITZUNG?
--
-- Hier laufen achtzehn vollstaendige Szenarien durch die komplette Kette:
-- Realmdaten -> Chancen -> Kapital -> Aktionen -> Route -> Guide -> Ereignisse
-- -> Ledger -> Ergebnis. Jedes Szenario startet mit einer frischen Welt und
-- einer frischen Datenbank; die Simulationsbausteine stehen in harness.lua.
--
-- Start ueber "node tests/run.mjs" aus dem Repo-Wurzelverzeichnis.

local H = dofile("tests/harness.lua")
local expect, expectEqual = H.expect, H.expectEqual
local expectRange, expectNear = H.expectRange, H.expectNear

local GCP = H.boot()

local function scenario(number, title)
    H.section(string.format("%d. %s", number, title))
    H.reset(GCP)
end

-- Fuehrt eine Route bis zum Ende durch, indem jeder Schritt von Hand
-- abgeschlossen wird. Rueckgabe: Zahl der Schritte, Sicherheitszaehler.
local function walkRoute(limit)
    local walked = 0
    while GCP.Guide:GetState() ~= "COMPLETED" and walked < (limit or 100) do
        local step = GCP.Guide:CurrentStep()
        if not step then break end
        GCP.Guide:Complete(step.id, false)
        walked = walked + 1
    end
    return walked
end

-- ===========================================================================
-- 1. Frische Installation, keine Daten
-- ===========================================================================

scenario(1, "Frische Installation")

-- Eine wirklich frische Installation hat auch noch keine Preisquelle: Ohne
-- Auctionator-Scan gibt es keinen einzigen Preis, und genau das ist der
-- Zustand, den ein Spieler nach der Installation sieht.
local savedAuctionatorCold = Auctionator
Auctionator = nil

expectEqual(GCP.db.version, GCP.Constants.VERSION, "Die Datenbank legt sich an")
expectEqual(GCP:ProfileCount(), 1, "...mit genau einem Realmprofil")
expectEqual(GCP.Market:SnapshotCount(21884), 0, "Keine Markthistorie")
expectEqual(GCP.Ledger:HasData(), false, "Keine Handelsdaten")
expectEqual(GCP.Farm:SessionCount(), 0, "Keine Farmhistorie")
expectEqual(GCP.Navigation:KnownCount(), 0, "Keine gelernten Orte")
expectEqual(GCP.Guide:GetState(), "IDLE", "Kein laufender Guide")

local coldRoute = GCP.Route:Plan({ profile = "CUSTOM", minutes = 60 })
expectEqual(#coldRoute.steps, 0, "Ohne Daten gibt es keine Route")
expect(coldRoute.summary:find("Keine Route", 1, true) ~= nil,
    "...und die Zusammenfassung sagt das in Worten")
local coldGuide, coldProblem = GCP.Guide:Start({ profile = "CUSTOM" })
expectEqual(GCP.Guide:GetState(), "IDLE", "Ein Start ohne Route bleibt untaetig")
expect(coldProblem ~= nil, "...und nennt einen Grund")
expect(GCP.Capital:SummaryText():find("noch keine offenen Positionen", 1, true) ~= nil,
    "Die Kapitalsicht sagt, dass es keine Positionen gibt")
expect(pcall(GCP.PrintDiagnostics, GCP), "Die Diagnose laeuft auch ohne Daten")

-- Sobald eine Preisquelle da ist, entsteht auch ohne eigene Historie etwas -
-- aber ausdruecklich mit niedriger Datenbasis.
Auctionator = savedAuctionatorCold
GCP.Opportunity:Invalidate()
GCP.Market:InvalidateCaches()
local firstReport = GCP.Opportunity:BuildReport(true)
for _, opportunity in ipairs(firstReport.opportunities) do
    expect(opportunity.confidence ~= "high",
        "Ohne eigene Historie ist keine Chance hochsicher")
end

-- ===========================================================================
-- 2. Marktdaten vorhanden, kein Ledger
-- ===========================================================================

scenario(2, "Marktdaten ohne Handelsdaten")

H.seedRealm(GCP)
local report = GCP.Opportunity:BuildReport(true)
expect(#report.opportunities > 0, "Mit Realmdaten entstehen Chancen")
expectEqual(report.withLiquidity, 0, "...aber keine einzige mit Liquiditaetsaussage")
for _, opportunity in ipairs(report.opportunities) do
    expectEqual(opportunity.liquidityScore, nil,
        "Ohne eigene Verkaeufe bleibt die Liquiditaet unbekannt statt null")
    expectEqual(opportunity.profitVelocity, nil, "...und die Profit Velocity ebenso")
    expectRange(opportunity.opportunityScore, 0, 100, "Jeder Score bleibt zwischen 0 und 100")
end
local route2 = GCP.Route:Plan({ profile = "CUSTOM", minutes = 60 })
expect(#route2.steps > 0, "Es entsteht trotzdem eine Route")
expect(route2.totals.capital <= route2.snapshot.availableGold,
    "...die die Kapitalgrenze einhaelt")

-- ===========================================================================
-- 3. Markt und Ledger
-- ===========================================================================

scenario(3, "Markt und Handelsdaten")

H.seedRealm(GCP)
H.seedTrade(GCP, 21884, { quantity = 5, buyPrice = 180000, sellPrice = 230000,
    rounds = 8, holdHours = 5 })
GCP.Opportunity:Invalidate()
local liquidity = GCP.Ledger:GetLiquidity(21884)
expect(liquidity ~= nil, "Nach eigenen Verkaeufen gibt es eine Liquiditaetsaussage")
expect(liquidity.liquidityScore ~= nil, "...mit Score")
expect(liquidity.expectedHours ~= nil, "...und gemessener Verkaufsdauer")

local warm = GCP.Opportunity:BuildReport(true)
local withLiquidity = 0
for _, opportunity in ipairs(warm.opportunities) do
    if opportunity.liquidityScore then withLiquidity = withLiquidity + 1 end
end
expect(withLiquidity > 0, "Die Chancenliste nutzt die eigenen Verkaufsdaten")

-- ===========================================================================
-- 4. Craft-Chance vom Rezept bis zum Einstellen
-- ===========================================================================

scenario(4, "Craft-Chance")

H.seedRealm(GCP)
H.money = 50000000
GCP.Capital:Invalidate()
local craftRoute = GCP.Route:Plan({ profile = "CRAFTING", minutes = 90 })
expect(#craftRoute.groups > 0, "Das Craft-Profil findet eine Chance")
local sawBuy, sawCraft, sawPost = false, false, false
for _, step in ipairs(craftRoute.steps) do
    if step.type == "BUY" then sawBuy = true end
    if step.type == "CRAFT" then sawCraft = true end
    if step.type == "POST_AUCTION" then sawPost = true end
end
expect(sawBuy, "Die Route kauft Material")
expect(sawCraft, "...stellt her")
expect(sawPost, "...und stellt ein")

-- Reihenfolge: kaufen vor herstellen vor einstellen.
local firstBuy, craftAt, postAt = nil, nil, nil
for index, step in ipairs(craftRoute.steps) do
    if step.type == "BUY" and not firstBuy then firstBuy = index end
    if step.type == "CRAFT" and not craftAt then craftAt = index end
    if step.type == "POST_AUCTION" and not postAt then postAt = index end
end
expect(firstBuy < craftAt, "Erst kaufen, dann herstellen")
expect(craftAt < postAt, "Erst herstellen, dann einstellen")

-- ===========================================================================
-- 5. Conversion-Chance
-- ===========================================================================

scenario(5, "Conversion-Chance")

H.seedRealm(GCP)
H.money = 50000000
GCP.Capital:Invalidate()
local conversionRoute = GCP.Route:Plan({ profile = "TRADING", minutes = 60 })
local sawConversion = false
for _, group in ipairs(conversionRoute.groups) do
    if group.type == "conversion" then sawConversion = true end
end
expect(sawConversion, "Das Handelsprofil findet eine Umwandlung")
for _, step in ipairs(conversionRoute.steps) do
    if step.type == "CONVERT" then
        expect(step.detail == nil or step.detail:find("zurück") ~= nil,
            "Eine unumkehrbare Umwandlung sagt das auch")
    end
end

-- ===========================================================================
-- 6. Zukunftschance mit bekanntem Catalyst
-- ===========================================================================

scenario(6, "Zukunftschance")

H.seedRealm(GCP)
local known = GCP.Future:KnownItems()
expect(#known > 0, "Die Wissensbasis kennt Items")
local futureRoute = GCP.Route:Plan({ profile = "FUTURE_INVESTING", minutes = 60 })
expect(futureRoute ~= nil, "Das Zukunftsprofil erzeugt eine Route oder sagt warum nicht")
local futureRecord = GCP.Future:GetItemRecord(known[1])
expect(futureRecord ~= nil, "Zu einem bekannten Item gibt es einen Datensatz")
if futureRecord.futureDemandScore then
    expectRange(futureRecord.futureDemandScore, 0, 100,
        "Der Future Demand Score bleibt zwischen 0 und 100")
end

-- ===========================================================================
-- 7. Hoher Hype
-- ===========================================================================

scenario(7, "Hoher Hype")

-- Ein Preis, der ueber Tage steil steigt: genau das misst der Hype Score.
local hypeItem = 22456
local base = H.now - 12 * 86400
for step = 0, 30 do
    local stamp = base + step * 9 * 3600
    GCP.Market:AddSnapshot(hypeItem, math.floor(60000 * (1 + step * 0.06)),
        stamp, "Auctionator")
end
H.setPrice(hypeItem, 200000)
GCP.Market:InvalidateCaches()
GCP.Future:Invalidate()
local hypeRecord = GCP.Future:GetItemRecord(hypeItem)
expect(hypeRecord.hypeScore ~= nil, "Ein steiler Anstieg ergibt einen Hype Score")
expect(hypeRecord.hypeScore > 50, "...und der liegt oben")
expect(hypeRecord.dontChase ~= nil or hypeRecord.entryPrice ~= nil,
    "Zu einem heissen Item gibt es eine Einstiegsaussage")

-- Ein heisses Item bekommt eine kleinere Position als dasselbe ohne Hype.
-- Geprueft wird die Wirkung des Hype-Faktors, deshalb wird der
-- Stueckzahl-Deckel hier abgeschaltet - wie die Exposure ueber exposureBase.
-- Sonst laegen beide Seiten auf demselben Deckel und der Vergleich zeigte
-- nichts. Der Deckel hat seine eigenen Tests in engine.lua.
local savedUnitCap = GCP.db.options.maxUnitsPerPosition
GCP.db.options.maxUnitsPerPosition = 0
local sizingHot = GCP.Capital:SizePosition({
    unitCost = 100000, investable = 20000000, score = 80, confidence = "high",
    exposureBase = 1000000000, hypeScore = hypeRecord.hypeScore,
})
local sizingCalm = GCP.Capital:SizePosition({
    unitCost = 100000, investable = 20000000, score = 80, confidence = "high",
    exposureBase = 1000000000,
})
if hypeRecord.hypeScore >= GCP.Constants.CAPITAL.SIZING.HYPE_HOT then
    expect(sizingHot.capital < sizingCalm.capital,
        "Ein bereits gelaufener Hype verkleinert die Position")
end
GCP.db.options.maxUnitsPerPosition = savedUnitCap

-- ===========================================================================
-- 8. Geringe Liquiditaet
-- ===========================================================================

scenario(8, "Geringe Liquiditaet")

H.seedRealm(GCP)
-- Zwoelf Einstellungen, zwei Verkaeufe: eine belegte, schlechte Sell-through.
H.seedTrade(GCP, 22452, { quantity = 5, buyPrice = 70000, sellPrice = 95000,
    rounds = 2, holdHours = 40, expiries = 10 })
GCP.Opportunity:Invalidate()
local slow = GCP.Ledger:GetLiquidity(22452)
expect(slow ~= nil, "Auch schlechte Liquiditaet ist eine Aussage")
expect(slow.sellThrough < 0.5, "...und sie ist niedrig")
local slowStats = GCP.Ledger:GetItemStats(22452)
expect(slowStats.liquidityScore < 60, "Der Liquidity Score faellt entsprechend aus")

-- Auch hier geht es um den Faktor, nicht um die Menge: Deckel aus, damit der
-- Liquiditaetsfaktor sichtbar wird.
local savedLiquidityCap = GCP.db.options.maxUnitsPerPosition
GCP.db.options.maxUnitsPerPosition = 0
local liquidSizing = GCP.Capital:SizePosition({
    unitCost = 50000, investable = 20000000, score = 80, confidence = "high",
    exposureBase = 1000000000, liquidityScore = slowStats.liquidityScore,
})
local unknownSizing = GCP.Capital:SizePosition({
    unitCost = 50000, investable = 20000000, score = 80, confidence = "high",
    exposureBase = 1000000000, liquidityScore = 90,
})
expect(liquidSizing.capital < unknownSizing.capital,
    "Eine zaehe Position faellt kleiner aus als eine liquide")
GCP.db.options.maxUnitsPerPosition = savedLiquidityCap

-- ===========================================================================
-- 9. Spieler mit wenig Kapital
-- ===========================================================================

scenario(9, "Wenig Kapital")

H.seedRealm(GCP)
H.money = 500000       -- 50 g
GCP.Capital:Invalidate()
local poorSnapshot = GCP.Capital:GetSnapshot(true)
expectEqual(poorSnapshot.currentGold, 500000, "Der Goldstand wird uebernommen")
expectEqual(poorSnapshot.reservedGold, 100000, "20 % bleiben als Reserve stehen")
local poorRoute = GCP.Route:Plan({ profile = "CUSTOM", minutes = 60 })
expect(poorRoute.totals.capital <= poorSnapshot.availableGold,
    "Die Route bleibt im Rahmen des freien Goldes")
expect(poorRoute.totals.capital + poorSnapshot.reservedGold <= poorSnapshot.currentGold,
    "Die Reserve wird nie angetastet")

-- ===========================================================================
-- 10. Spieler mit viel Kapital
-- ===========================================================================

scenario(10, "Viel Kapital")

H.seedRealm(GCP)
H.money = 5000000000   -- 500.000 g
GCP.Capital:Invalidate()
local richRoute = GCP.Route:Plan({ profile = "MAX_PROFIT", minutes = 120 })
expect(#richRoute.steps > 0, "Auch mit viel Gold entsteht eine Route")
local richSnapshot = richRoute.snapshot
for _, allocation in ipairs(richRoute.allocations) do
    expect(allocation.share <= GCP.Constants.CAPITAL.SIZING.MAX_SHARE + 1e-9,
        "Keine Allokation ueberschreitet den Maximalanteil - kein All-In")
    expect(allocation.capital <= richSnapshot.availableGold,
        "...und keine mehr als das freie Kapital")
end
expect(richRoute.totals.capital <= richSnapshot.availableGold,
    "Auch die Summe bleibt im Rahmen")

-- ===========================================================================
-- 11. Preise aendern sich waehrend der Route
-- ===========================================================================

scenario(11, "Preisaenderung waehrend der Route")

H.seedRealm(GCP)
H.money = 50000000
GCP.Capital:Invalidate()
GCP.Guide:Start({ profile = "CUSTOM", minutes = 90 })
expectEqual(GCP.Guide:GetState(), "ACTIVE", "Die Route laeuft")

-- Zum ersten Kaufschritt vorruecken.
local buyStep = nil
local guard = 0
while guard < 30 do
    local step = GCP.Guide:CurrentStep()
    if not step then break end
    if step.type == "BUY" and step.maxBuyPrice then
        buyStep = step
        break
    end
    GCP.Guide:Complete(step.id, false)
    guard = guard + 1
end
expect(buyStep ~= nil, "Die Route enthaelt einen Kaufschritt mit Preisgrenze")

if buyStep then
    expect(GCP.Route:ValidateStep(buyStep), "Beim geplanten Preis ist er gueltig")
    -- Der Markt zieht deutlich an.
    H.setPrice(buyStep.itemID, buyStep.maxBuyPrice * 4)
    GCP.Market:InvalidateCaches()
    GCP.Opportunity:Invalidate()
    local ok, reason = GCP.Route:ValidateStep(buyStep)
    expect(not ok, "Ein deutlich hoeherer Preis macht ihn ungueltig")
    expectEqual(reason, "price_above_max", "...mit benanntem Grund")

    local doneBefore = GCP.Guide:DoneCount()
    GCP.Guide.lastReplan = nil
    GCP.Guide:Verify()
    expect(GCP.Guide:DoneCount() >= doneBefore,
        "Die Neuplanung verliert keinen erledigten Schritt")
    expect(GCP.Guide:GetState() ~= "IDLE", "Der Guide bleibt ansprechbar")
end
GCP.Guide:Abort()

-- ===========================================================================
-- 12. Item nicht mehr verfuegbar
-- ===========================================================================

scenario(12, "Item nicht verfuegbar")

H.seedRealm(GCP)
H.money = 50000000
GCP.Capital:Invalidate()
GCP.Guide:Start({ profile = "CUSTOM", minutes = 90 })
local missingStep = nil
for _, step in ipairs(GCP:Profile().guide.steps) do
    if step.type == "BUY" and step.itemID then missingStep = step break end
end
expect(missingStep ~= nil, "Die Route will etwas kaufen")
if missingStep then
    -- Kein Marktpreis mehr: das Item ist verschwunden.
    local restorePrice = H.marketPrices[missingStep.itemID]
    H.marketPrices[missingStep.itemID] = nil
    GCP.Market:InvalidateCaches()
    GCP.Opportunity:Invalidate()
    expect(GCP.Route:ValidateStep(missingStep),
        "Ohne Preis wird der Schritt nicht faelschlich fuer ungueltig erklaert")
    -- Der Spieler ueberspringt ihn - alles Abhaengige faellt mit weg.
    local skipped = GCP.Guide:Skip(missingStep.id)
    expect(skipped, "Der Schritt laesst sich ueberspringen")
    local store = GCP:Profile().guide
    expect(store.skipped[missingStep.id] ~= nil, "...und ist als uebersprungen vermerkt")
    -- Den Preis wieder herstellen. H.marketPrices ist eine Tabelle der
    -- Attrappe und ueberlebt H.reset - ein hier geloeschter Preis fehlte sonst
    -- in JEDEM folgenden Szenario, und ein Craft ohne vollstaendige Zutaten-
    -- preise faellt aus der Chancenliste. Genau das ist lange unbemerkt
    -- passiert.
    H.marketPrices[missingStep.itemID] = restorePrice
    GCP.Market:InvalidateCaches()
    GCP.Opportunity:Invalidate()
end
GCP.Guide:Abort()

-- ===========================================================================
-- 13. Spieler ueberspringt einen Schritt
-- ===========================================================================

scenario(13, "Uebersprungener Schritt")

H.seedRealm(GCP)
H.money = 50000000
GCP.Capital:Invalidate()
GCP.Guide:Start({ profile = "CRAFTING", minutes = 90 })
local store13 = GCP:Profile().guide
local target = nil
for _, step in ipairs(store13.steps) do
    if step.type == "BUY" then target = step break end
end
if target then
    local dependents = {}
    for _, step in ipairs(store13.steps) do
        for _, dependency in ipairs(step.dependencies or {}) do
            if dependency == target.id then dependents[#dependents + 1] = step.id end
        end
    end
    GCP.Guide:Skip(target.id)
    for _, id in ipairs(dependents) do
        expect(store13.skipped[id] ~= nil,
            "Was auf einem uebersprungenen Schritt aufbaut, faellt mit weg")
        expect(store13.skipped[id].cascade, "...und zwar als Folge, nicht als Wahl")
    end
    expect(GCP.Personal:GetStats("craft") == nil
        or GCP.Personal:GetStats("craft").skipped >= 0,
        "Der Personal Brain zaehlt das Ueberspringen mit")
end
GCP.Guide:Abort()

-- ===========================================================================
-- 14. Farmsitzung bleibt unter dem eigenen Median
-- ===========================================================================

scenario(14, "Schwache Farmsitzung")

H.seedRealm(GCP)
H.zoneName = "Nagrand"
for round = 1, 5 do
    GCP.Farm:Start({ 23425 }, "Nagrand")
    H.farmRun(GCP, 1800, { chunk = 300, itemID = 23425, perChunk = 6 })
    GCP.Farm:Stop("Test")
end
local farmRate = GCP.Farm:GetRate("Nagrand")
expect(farmRate ~= nil, "Nach fuenf Sitzungen gibt es eine eigene Rate")
expectEqual(farmRate.sessions, 5, "...aus allen fuenf")

GCP.Farm:Start({ 23425 }, "Nagrand")
H.farmRun(GCP, 900, { chunk = 300, itemID = 23425, perChunk = 1 })
local assessment = GCP.Farm:Assess()
expect(assessment.below, "Eine schwache Sitzung faellt auf")
expect(assessment.text:find("%%") ~= nil, "...und wird beziffert")
if assessment.alternative then
    expect(assessment.alternative.text:find("höhere erwartete aktive Goldrate", 1, true) ~= nil,
        "Eine bessere Alternative wird benannt")
end
GCP.Farm:Stop("Test")

-- ===========================================================================
-- 15. Vollstaendige, erfolgreiche Gold Route
-- ===========================================================================

scenario(15, "Vollstaendige Gold Route")

H.seedRealm(GCP)
H.money = 50000000
GCP.Capital:Invalidate()
local fullRoute = GCP.Guide:Start({ profile = "CUSTOM", minutes = 120, goal = 2000000 })
expect(#fullRoute.steps > 0, "Es entsteht eine Route")
expectEqual(GCP.Guide:GetState(), "ACTIVE", "...die sofort laeuft")
local plannedSteps = GCP.Guide:StepCount()

-- Der Spieler betritt das Auktionshaus: der erste Weg schliesst sich selbst.
local firstStep = GCP.Guide:CurrentStep()
if firstStep and firstStep.type == "GO_TO"
    and firstStep.location.kind == "AUCTION_HOUSE" then
    expect(GCP.Guide:OnEvent("AUCTION_HOUSE_SHOW"),
        "Das Betreten des Auktionshauses hakt den Weg automatisch ab")
    expect(GCP:Profile().guide.progress[firstStep.id].auto,
        "...und zwar als bestaetigt")
end

local walked = walkRoute(plannedSteps + 5)
expectEqual(GCP.Guide:GetState(), "COMPLETED", "Die Route laeuft bis zum Ende durch")
local finalProgress = GCP.Guide:Progress()
expectEqual(finalProgress.remaining, 0, "Am Ende ist nichts mehr offen")
expectEqual(finalProgress.remainingProfit, 0, "...und kein Restpotenzial mehr da")
expect(finalProgress.done > 0, "Es wurden Schritte erledigt")
expect(GCP.Personal:EnsureStore().routes.completed >= 1,
    "Der Personal Brain zaehlt die abgeschlossene Route")

-- Ein spaeterer Verkauf schliesst den Kreis: Ledger -> Ergebnis -> Personal.
--
-- ZUORDNUNG EINER CRAFT-EMPFEHLUNG (1.0.0-beta.10). Bis beta.9 stand hier eine
-- Craft-Empfehlung fuer Urmacht, danach ein KAUF von Urmacht - und das galt als
-- ihre Ausfuehrung. Das war der Fehler: Wer Urmacht kauft, hat sie gerade nicht
-- hergestellt. Der Kauf belegt das Gegenteil der Empfehlung.
--
-- Erwartet wird jetzt: Der blosse Kauf des Produkts laesst die Empfehlung
-- unberuehrt. Zugeordnet wird sie erst, wenn der Guide sagt, dass sie
-- ausgefuehrt wurde.
GCP:Profile().opportunityHistory[1] = {
    timestamp = H.now - 3600, type = "craft", itemID = 23571, saleItemID = 23571,
    key = "craft:23571", identity = false,
    expectedProfit = 100000, opportunityScore = 80, confidence = "high",
}
GCP.Ledger:RecordPurchase({ itemID = 23571, quantity = 1, unitPrice = 600000,
    timestamp = H.now - 1800 })
GCP.Opportunity:MatchHistoryOutcomes()
expectEqual(GCP:Profile().opportunityHistory[1].executedAt, nil,
    "Ein Kauf des Produkts bestaetigt keine Craft-Empfehlung")

-- Jetzt der belegte Weg: Die Ausfuehrung wird gemeldet, wie der Guide es beim
-- Abhaken tut. Kostenbasis ist der wirtschaftliche Materialeinsatz je Stueck.
expect(GCP.Opportunity:ClaimExecution({
    key = "craft:23571", type = "craft", saleItemID = 23571,
    runs = 1, units = 1, unitCost = 600000, timestamp = H.now - 1750,
}), "Die gemeldete Ausfuehrung findet ihre Empfehlung")

GCP.Ledger:RecordAuctionPosted({ itemID = 23571, quantity = 1, unitPrice = 900000,
    deposit = 300, durationHours = 12, timestamp = H.now - 1700 })
local ledgerStore = GCP.Ledger:EnsureStore()
local posting, quality = GCP.Ledger:MatchSale(ledgerStore, 23571, 900000)
GCP.Ledger:RecordSale({ itemID = 23571, quantity = 1, totalGross = 900000,
    source = "ah", timestamp = H.now - 600, holdHours = 0.3,
    matchQuality = quality })
-- Die Zuordnung laeuft bereits beim Verkauf an (Ledger meldet es dem Personal
-- Brain); der zweite Aufruf ist deshalb bewusst idempotent.
GCP.Opportunity:MatchHistoryOutcomes()
local outcome = GCP:Profile().opportunityHistory[1]
expect(outcome.executedAt ~= nil, "Der Kauf wird der Empfehlung zugeordnet")
expectEqual(outcome.entryPrice, 600000, "...mit dem tatsaechlichen Einstandspreis")
expectEqual(outcome.match, "claim", "...und die Zuordnung ist als belegt markiert")
expect(outcome.outcome == "WIN" or outcome.outcome == "LOSS" or outcome.outcome == "OPEN",
    "Die Empfehlung bekommt ein Ergebnis")
GCP.Personal:SyncOutcomes()

-- ===========================================================================
-- 16. ReloadUI mitten in der Route
-- ===========================================================================

scenario(16, "ReloadUI waehrend der Route")

H.seedRealm(GCP)
H.money = 50000000
GCP.Capital:Invalidate()
GCP.Guide:Start({ profile = "CUSTOM", minutes = 90 })
local beforeSteps = GCP.Guide:StepCount()
expect(beforeSteps >= 3, "Fuer diesen Test braucht es eine Route mit mehreren Schritten")
-- Zwei Schritte erledigen und mitten in der Route stehenbleiben. Bewusst
-- nicht ueberspringen: Ein uebersprungener Kaufschritt nimmt die ganze Kette
-- mit und beendete die Route sofort - das ist richtig so, taugt hier aber
-- nicht als Ausgangslage.
local first = GCP.Guide:CurrentStep()
GCP.Guide:Complete(first.id, false)
local second = GCP.Guide:CurrentStep()
if second then GCP.Guide:Complete(second.id, false) end
local doneBefore, skippedBefore = GCP.Guide:DoneCount()
expect(doneBefore + skippedBefore < beforeSteps,
    "Es sind noch Schritte offen, wenn der Reload kommt")
local indexBefore = GCP:Profile().guide.currentIndex
local savedDatabase = GoldCopilotDB

-- Ein /reload: Laufzeitzustand weg, SavedVariables bleiben.
GCP.Guide.route = nil
GCP.Guide.baseline = nil
GCP.profileCache = nil
GoldCopilotDB = savedDatabase
GCP:EnsureDB()

local doneAfter, skippedAfter = GCP.Guide:DoneCount()
expectEqual(GCP.Guide:StepCount(), beforeSteps, "Nach dem Reload stehen alle Schritte")
expectEqual(doneAfter, doneBefore, "...alle erledigten sind noch erledigt")
expectEqual(skippedAfter, skippedBefore, "...alle uebersprungenen noch uebersprungen")
expectEqual(GCP:Profile().guide.currentIndex, indexBefore, "...und die Position stimmt")
expectEqual(GCP.Guide:GetState(), "PAUSED",
    "Nach einem Reload steht die Route pausiert - sie laeuft nicht heimlich weiter")
GCP.Guide:Resume()
expectEqual(GCP.Guide:GetState(), "ACTIVE", "...und laesst sich fortsetzen")
GCP.Guide:Abort()

-- ===========================================================================
-- 17. Optionale Addons fehlen
-- ===========================================================================

scenario(17, "Optionale Addons fehlen")

local savedAuctionator, savedTSM = Auctionator, TSM_API
Auctionator, TSM_API, Syndicator, TomTom = nil, nil, nil, nil

expect(not GCP:HasAddon("Auctionator"), "Ein fehlendes Auctionator wird erkannt")
expect(not GCP:HasAddon("Syndicator"), "...und ein fehlendes Syndicator")
expect(not GCP:HasAddon("TSM"), "...und ein fehlendes TSM")
expect(not GCP:HasAddon("TomTom"), "...und ein fehlendes TomTom")
expectEqual(GCP.Prices:GetMarketPrice(21884), nil,
    "Ohne Preisquelle gibt es keinen Preis - und keinen erfundenen")
expect(GCP.Prices:GetActiveSourceLabel() ~= nil,
    "Die Preisquelle wird trotzdem benannt")

expect(pcall(GCP.Route.Plan, GCP.Route, { profile = "CUSTOM" }),
    "Der Routenplaner laeuft auch ohne optionale Addons")
expect(pcall(GCP.Opportunity.BuildReport, GCP.Opportunity, true),
    "Die Chancenliste ebenfalls")
expect(pcall(GCP.Capital.GetSnapshot, GCP.Capital, true),
    "Die Kapitalsicht ebenfalls")
expect(pcall(GCP.PrintDiagnostics, GCP), "Die Diagnose ebenfalls")
local noAddonRoute = GCP.Route:Plan({ profile = "CUSTOM" })
expectEqual(#noAddonRoute.steps, 0, "Ohne Preise gibt es nichts zu planen")
expect(noAddonRoute.summary:find("Keine Route", 1, true) ~= nil,
    "...und das steht auch da")

-- Navigation ohne TomTom
expect(not GCP.Navigation:HasTomTom(), "TomTom fehlt")
H.mapID = 85
H.position = { x = 0.5, y = 0.5 }
expect(GCP.Navigation:Learn("AUCTION_HOUSE", nil), "Orte lernt Gold Copilot selbst")
expect(GCP.Navigation:GetWaypoint({ kind = "AUCTION_HOUSE" }) ~= nil,
    "...und liefert auch ohne TomTom einen Wegpunkt")

Auctionator, TSM_API = savedAuctionator, savedTSM

-- ===========================================================================
-- 19. Von der Chance bis zum Ergebnis: die vollstaendige Kette
--
-- Der Befund, der dieses Szenario noetig gemacht hat: Eine Craft-Empfehlung
-- konnte nie als ausgefuehrt erkannt werden, weil das Protokoll die Item-ID des
-- PRODUKTS mit der Item-ID eines KAUFS verglich - und gekauft werden bei einem
-- Craft die Zutaten.
--
-- Geprueft wird deshalb der ganze Weg, so wie er im Spiel entsteht:
--
--   Chance -> Zuteilung -> Route -> Guide haakt ab -> Protokoll -> Verkauf
--
-- Ohne einen einzigen handgeschriebenen Protokolleintrag.
-- ===========================================================================

scenario(19, "Craft-Empfehlung von der Route bis zum Ergebnis")

H.reset(GCP)
H.seedRealm(GCP)
H.money = 50000000
GCP.Capital:Invalidate()

-- Damit die Chance ueberhaupt ins Protokoll kommt, muss sie die Schwellen aus
-- C.OPPORTUNITY.HISTORY nehmen. Statt sie abzusenken wird der Eintrag hier
-- ueber den regulaeren Weg erzeugt: LogReport schreibt genau das, was auch im
-- Spiel geschrieben wuerde.
local report = GCP.Opportunity:BuildReport(true)
local craftOpportunity = nil
for _, entry in ipairs(report.opportunities) do
    if entry.type == "craft" then craftOpportunity = entry break end
end

if craftOpportunity then
    expect(craftOpportunity.key ~= nil, "Die Craft-Chance traegt einen Schluessel")
    expectEqual(craftOpportunity.saleItemID, craftOpportunity.itemID,
        "...und benennt ihr Verkaufsitem")
    expectEqual(GCP.Opportunity:IsIdentityMatchable(craftOpportunity), false,
        "Ein Craft ist ausdruecklich NICHT ueber die Item-Identitaet zuzuordnen")

    -- Den Protokolleintrag wie im Spiel erzeugen, aber mit gesenkter Schwelle:
    -- Der Testrealm hat nicht zwangslaeufig eine Chance ueber MIN_SCORE, und
    -- geprueft werden soll die Zuordnung, nicht die Aufzeichnungsschwelle.
    local savedScore = GCP.Constants.OPPORTUNITY.HISTORY.MIN_SCORE
    local savedConfidence = GCP.Constants.OPPORTUNITY.HISTORY.MIN_CONFIDENCE
    GCP.Constants.OPPORTUNITY.HISTORY.MIN_SCORE = 0
    GCP.Constants.OPPORTUNITY.HISTORY.MIN_CONFIDENCE = "none"
    GCP.Opportunity:LogReport({ opportunities = { craftOpportunity } }, H.now - 600)
    GCP.Constants.OPPORTUNITY.HISTORY.MIN_SCORE = savedScore
    GCP.Constants.OPPORTUNITY.HISTORY.MIN_CONFIDENCE = savedConfidence

    local history = GCP.Opportunity:EnsureHistory()
    local logged = nil
    for _, entry in ipairs(history) do
        if entry.key == craftOpportunity.key then logged = entry end
    end
    expect(logged ~= nil, "Die Chance steht mit ihrem Schluessel im Protokoll")
    expectEqual(logged.identity, nil,
        "...und ist als nicht identitaetsfaehig vermerkt (nil statt true)")

    -- Jetzt der echte Weg: planen, laufen, abhaken.
    local route = GCP.Guide:Start({ profile = "CUSTOM", minutes = 120 })
    expect(route ~= nil, "Es entsteht eine Route")
    local storeGroups = GCP:Profile().guide.groups or {}
    local sawKey = false
    for _, group in pairs(storeGroups) do
        if group.key then sawKey = true end
    end
    expect(sawKey, "Die gespeicherten Gruppen tragen ihren Chancenschluessel")

    walkRoute(60)
    -- Wurde die Craft-Gruppe wirklich gelaufen, ist die Empfehlung jetzt
    -- zugeordnet - ohne dass irgendwo eine Item-ID verglichen wurde.
    -- Und das ist der Kern: Die Empfehlung ist zugeordnet, obwohl NIRGENDS
    -- eine Item-ID verglichen wurde. Gekauft wurden Urfeuer, Urwasser, Urluft,
    -- Urerde und Urmana; die Empfehlung lautete auf Urmacht.
    expect(logged.executedAt ~= nil,
        "Die durchgelaufene Craft-Empfehlung gilt als ausgefuehrt")
    expectEqual(logged.match, "claim",
        "Die Zuordnung stammt vom Guide, nicht aus einem Item-Vergleich")
    expect(logged.entryQuantity >= 1, "...mit einer Stueckzahl")
    expectEqual(logged.outcome, "OPEN", "...und gilt als offene Position")
end

-- ===========================================================================
-- 18. Teilweise kaputte SavedVariables
-- ===========================================================================

scenario(18, "Kaputte SavedVariables")

-- Eine Datenbank, in der mehrere Speicher Unsinn enthalten.
GoldCopilotDB = {
    version = "0.8.0",
    options = { priceSource = "auto", ignored = {} },
    questGold = {},
    roadmap = { day = GCP:ResetPeriodKey(), checked = {}, baseline = {} },
    goldHistory = { ["2026-01-01"] = 4242 },
    profiles = {
        ["Testrealm|Horde"] = {
            marketHistory = "kaputt",
            ledger = { version = 1, events = "auch kaputt" },
            guide = { version = 1, steps = 5, state = 42 },
            capital = 17,
            farm = { version = 99 },
            personal = false,
            calibration = { version = 1, model = 99, factors = "nein" },
            priceHistory = "nein",
            watchlist = 3,
            opportunityHistory = "auch nicht",
            marketProbes = { version = 1, points = "nein", epoch = "auch nein" },
        },
    },
    profileVersion = 1,
}
GCP.profileCache = nil
expect(pcall(GCP.EnsureDB, GCP), "Eine kaputte Datenbank reisst den Start nicht mit")

local repairedProfile = GCP:Profile()
expect(type(repairedProfile.priceHistory) == "table", "Die Preishistorie wird repariert")
expect(type(repairedProfile.watchlist) == "table", "...die Beobachtungsliste auch")
expect(type(repairedProfile.opportunityHistory) == "table", "...und das Protokoll")
expect(type(GCP.Market:EnsureStore()) == "table", "Die Markthistorie wird ersetzt")
expect(type(GCP.Ledger:EnsureStore().events) == "table", "Die Handelsbilanz ebenso")
expect(type(GCP.Capital:EnsureStore()) == "table", "Die Kapitalsicht ebenso")
expect(type(GCP.Farm:EnsureStore().sessions) == "table", "Die Farmhistorie ebenso")
expect(type(GCP.Personal:EnsureStore().types) == "table", "Die persoenliche Statistik ebenso")
expect(type(GCP.Calibration:EnsureStore().factors) == "table", "Die Kalibrierung ebenso")
expect(type(GCP.Market:EnsureProbeStore().points) == "table",
    "...und die Score-Sonden werden ersetzt statt weiterbenutzt")
expect(type(GCP.Market:EnsureProbeStore().epoch) == "number",
    "...samt einem brauchbaren Bezugszeitpunkt")
expect(pcall(GCP.Market.GetProbes, GCP.Market), "Sie lassen sich danach lesen")
expect(pcall(GCP.Analytics.ScoreValidation, GCP.Analytics),
    "...und die Selbstpruefung laeuft ueber sie hinweg")
expectEqual(GCP.Guide:GetState(), "IDLE", "Der Guide startet sauber im Leerlauf")
expectEqual(GoldCopilotDB.goldHistory["2026-01-01"], 4242,
    "Was heil war, bleibt unangetastet")
expect(pcall(GCP.Route.Plan, GCP.Route, { profile = "CUSTOM" }),
    "Nach der Reparatur laesst sich wieder planen")
expect(pcall(GCP.PrintDiagnostics, GCP), "...und die Diagnose laeuft")


-- ===========================================================================
-- INVARIANTEN
--
-- Keine Szenarien, sondern Zusicherungen, die IMMER gelten muessen - geprueft
-- ueber viele erzeugte Eingaben statt an einem Beispiel. Wenn eine davon
-- faellt, ist eine Rechnung kaputt, nicht ein Testfall.
-- ===========================================================================

H.section("Invarianten")
H.reset(GCP)
H.seedRealm(GCP)

-- --- Score immer 0..100 ----------------------------------------------------

local scoreViolations = 0
for roiStep = 1, 12 do
    for profitStep = 1, 8 do
        for _, confidence in ipairs({ "low", "medium", "high" }) do
            local score = GCP.Opportunity:ScoreOf({
                type = "craft",
                roi = roiStep * 0.35,
                profit = profitStep * 90000,
                cost = profitStep * 130000,
                marketScore = (roiStep * 9) % 101,
                volatility = (profitStep % 7) * 0.12,
                confidence = confidence,
                liquidityScore = (roiStep * 13) % 101,
                liquidityConfidence = confidence,
            })
            if score ~= nil and (score < 0 or score > 100 or score ~= math.floor(score)) then
                scoreViolations = scoreViolations + 1
            end
        end
    end
end
expectEqual(scoreViolations, 0,
    "Der Opportunity Score bleibt ueber alle Eingaben ganzzahlig zwischen 0 und 100")

-- Ohne Datenlage gibt es gar keinen Score - nicht etwa null.
expectEqual(GCP.Opportunity:ScoreOf({ type = "craft", roi = 1, profit = 1000,
    cost = 1000, confidence = "none" }), nil,
    "Ohne Datenlage gibt es keinen Score statt einer Null")

-- --- ROI wird bei Kosten 0 nie gerechnet -----------------------------------

expectEqual(GCP.Opportunity:Make({ type = "craft", key = "x", itemID = 1,
    cost = 0, expectedRevenue = 1000 }), nil,
    "Ohne Kapitaleinsatz entsteht keine Chance - und keine Division durch null")
expectEqual(GCP.Opportunity:Make({ type = "craft", key = "x", itemID = 1,
    cost = -5, expectedRevenue = 1000 }), nil,
    "Ein negativer Kapitaleinsatz ebenso wenig")
expectEqual(GCP.Opportunity:Make({ type = "craft", key = "x", itemID = 1,
    cost = 1000, expectedRevenue = 900 }), nil,
    "Ein Verlustgeschaeft wird nicht als Chance gefuehrt")

-- --- Positionsgroesse: nie negativ, nie All-In, immer ganzzahlig -----------

local sizingViolations = 0
for scoreStep = 0, 10 do
    for _, confidence in ipairs({ "none", "low", "medium", "high" }) do
        local sizing = GCP.Capital:SizePosition({
            unitCost = 10000 + scoreStep * 7000,
            investable = 30000000,
            exposureBase = 1000000000,
            score = scoreStep * 10,
            confidence = confidence,
            volatility = (scoreStep % 6) * 0.12,
            liquidityScore = (scoreStep * 11) % 101,
        })
        if sizing then
            if sizing.units < 1 or sizing.units ~= math.floor(sizing.units) then
                sizingViolations = sizingViolations + 1
            end
            if sizing.capital > 30000000 then sizingViolations = sizingViolations + 1 end
            if sizing.share > GCP.Constants.CAPITAL.SIZING.MAX_SHARE + 1e-9 then
                sizingViolations = sizingViolations + 1
            end
        end
    end
end
expectEqual(sizingViolations, 0,
    "Positionsgroessen sind immer ganzzahlig, positiv, gedeckelt und im Kapitalrahmen")

-- --- Allokation und Reserve ------------------------------------------------

local allocationViolations = 0
for goldStep = 1, 12 do
    H.money = goldStep * 4000000
    GCP.Capital:Invalidate()
    local snapshot = GCP.Capital:GetSnapshot(true)
    local plan = GCP.Capital:Allocate(
        GCP.Opportunity:BuildReport(true).opportunities, { snapshot = snapshot })
    local sum = 0
    for _, allocation in ipairs(plan.allocations) do
        sum = sum + allocation.capital
        if allocation.units < 1 then allocationViolations = allocationViolations + 1 end
        if allocation.capital ~= allocation.units * allocation.unitCost then
            allocationViolations = allocationViolations + 1
        end
    end
    if sum > snapshot.availableGold then allocationViolations = allocationViolations + 1 end
    if sum + snapshot.reservedGold > snapshot.currentGold then
        allocationViolations = allocationViolations + 1
    end
    if plan.unused < 0 then allocationViolations = allocationViolations + 1 end
end
expectEqual(allocationViolations, 0,
    "Ueber alle Kapitalstaende gilt: Allokation <= frei, Reserve unangetastet")

-- --- Routen: Abhaengigkeiten, Budgets, keine Doppelungen -------------------

local routeViolations = 0
for minutesStep = 1, 8 do
    H.money = 40000000
    GCP.Capital:Invalidate()
    local route = GCP.Route:Plan({ profile = "CUSTOM", minutes = minutesStep * 15 })
    local position = {}
    local seen = {}
    for index, step in ipairs(route.steps) do
        if step.id then
            if seen[step.id] then routeViolations = routeViolations + 1 end
            seen[step.id] = true
            position[step.id] = index
        end
        if step.quantity and step.quantity < 0 then routeViolations = routeViolations + 1 end
    end
    for _, step in ipairs(route.steps) do
        for _, dependency in ipairs(step.dependencies or {}) do
            if position[dependency] and position[dependency] > position[step.id] then
                routeViolations = routeViolations + 1
            end
        end
    end
    if route.totals.capital > route.snapshot.availableGold then
        routeViolations = routeViolations + 1
    end
    if route.totals.steps > GCP.Constants.ROUTE.MAX_STEPS then
        routeViolations = routeViolations + 1
    end
end
expectEqual(routeViolations, 0,
    "Ueber alle Zeitbudgets gilt: keine Doppelungen, Abhaengigkeiten zuerst, Budgets eingehalten")

-- --- Ein erledigter Schritt wird nie zweimal erledigt ----------------------

H.money = 40000000
GCP.Capital:Invalidate()
GCP.Guide:Start({ profile = "CUSTOM", minutes = 90 })
local repeatStep = GCP.Guide:CurrentStep()
expect(GCP.Guide:Complete(repeatStep.id, false), "Ein Schritt laesst sich abschliessen")
expect(not GCP.Guide:Complete(repeatStep.id, false), "...aber kein zweites Mal")
expect(not GCP.Guide:Skip(repeatStep.id), "...und auch nicht nachtraeglich ueberspringen")
GCP.Guide:Abort()

-- --- Abgebrochen ist nicht abgelaufen --------------------------------------

H.reset(GCP)
GCP.Ledger:RecordAuctionPosted({ itemID = 23425, quantity = 5, unitPrice = 50000,
    deposit = 300, durationHours = 12, timestamp = H.now - 7200 })
GCP.Ledger:RecordAuctionCancelled({ itemID = 23425, quantity = 5, timestamp = H.now })
local cancelledStats = GCP.Ledger:GetItemStats(23425)
expectEqual(cancelledStats.cancelledAuctions, 1, "Ein Abbruch wird als Abbruch gezaehlt")
expectEqual(cancelledStats.expiredAuctions, 0, "...und nicht als Ablauf")
expectEqual(cancelledStats.sellThrough, nil,
    "Ein Abbruch sagt nichts ueber die Sell-through - also gibt es keine")

GCP.Ledger:RecordAuctionPosted({ itemID = 23425, quantity = 5, unitPrice = 50000,
    deposit = 300, durationHours = 12, timestamp = H.now })
GCP.Ledger:RecordAuctionExpired({ itemID = 23425, quantity = 5, timestamp = H.now + 3600 })
local expiredStats = GCP.Ledger:GetItemStats(23425)
expectEqual(expiredStats.expiredAuctions, 1, "Ein Ablauf wird als Ablauf gezaehlt")
expectEqual(expiredStats.cancelledAuctions, 1, "...und der Abbruch bleibt ein Abbruch")

-- --- UNKNOWN wird nie stillschweigend zu 0 --------------------------------

H.reset(GCP)
expectEqual(GCP.Ledger:GetLiquidity(23425), nil, "Ohne Daten keine Liquiditaet")
expectEqual(GCP.Farm:GetRate("Nirgendwo"), nil, "Ohne Sitzungen keine Farmrate")
expectEqual(GCP.Market:GetDepth(23425), nil, "Ohne Suche keine Angebotsmenge")
local emptyStats = GCP.Market:GetMarketScore(23425)
expectEqual(emptyStats and emptyStats.score or nil, nil,
    "Ohne Historie gibt es keinen Market Score - der aktuelle Preis allein ist keiner")
expectEqual(GCP.Personal:ExpectedValueText("craft"), nil,
    "Ohne Stichprobe keine persoenliche Aussage")
local emptySnapshot = GCP.Capital:GetSnapshot(true)
expectEqual(emptySnapshot.unrealizedPnL, nil, "Ohne Positionen kein unrealisierter Gewinn")

-- --- Confidence steigt nicht durch weniger Daten --------------------------

H.reset(GCP)
local confidenceOrder = { "none", "low", "medium", "high" }
local previousRank = 0
local confidenceViolations = 0
for points = 0, 30, 2 do
    GCP.Market:Reset()
    local start = H.now - 12 * 86400
    for index = 1, points do
        GCP.Market:AddSnapshot(23425, 50000 + index * 10,
            start + index * 9 * 3600, "Auctionator")
    end
    local stats = GCP.Market:GetMarketScore(23425)
    local rank = stats and GCP.Opportunity:ConfidenceRank(stats.confidence) or 0
    if rank < previousRank then confidenceViolations = confidenceViolations + 1 end
    previousRank = rank
end
expectEqual(confidenceViolations, 0,
    "Mehr Messpunkte senken die Sicherheit nie")

-- --- Schlechte Daten verbessern den Score nicht ---------------------------

H.reset(GCP)
H.seedRealm(GCP)
local cleanReport = GCP.Opportunity:BuildReport(true)
local cleanBest = cleanReport.opportunities[1]
if cleanBest then
    -- Ein einzelner absurder Ausreisser in der Historie darf den Score nicht
    -- nach oben treiben.
    GCP.Market:AddSnapshot(cleanBest.itemID, 1, H.now - 60, "Auctionator")
    GCP.Market:InvalidateCaches()
    GCP.Opportunity:Invalidate()
    local dirtyReport = GCP.Opportunity:BuildReport(true)
    local dirtyBest = nil
    for _, opportunity in ipairs(dirtyReport.opportunities) do
        if opportunity.key == cleanBest.key then dirtyBest = opportunity end
    end
    if dirtyBest then
        expect(dirtyBest.opportunityScore <= cleanBest.opportunityScore + 5,
            "Ein einzelner Ausreisser hebt den Score nicht sprunghaft an")
    end
end

-- --- Neuplanung verliert keine erledigten Schritte -------------------------

H.reset(GCP)
H.seedRealm(GCP)
H.money = 40000000
GCP.Capital:Invalidate()
GCP.Guide:Start({ profile = "CUSTOM", minutes = 90 })
local replanViolations = 0
for round = 1, 5 do
    local step = GCP.Guide:CurrentStep()
    if not step then break end
    GCP.Guide:Complete(step.id, false)
    local doneBefore = GCP.Guide:DoneCount()
    GCP.Guide.lastReplan = nil
    GCP.Guide:Replan("market_revision")
    if GCP.Guide:DoneCount() < doneBefore then
        replanViolations = replanViolations + 1
    end
end
expectEqual(replanViolations, 0,
    "Ueber mehrere Neuplanungen hinweg geht kein erledigter Schritt verloren")
GCP.Guide:Abort()

-- --- Neuplanung laeuft nicht in eine Schleife ------------------------------

H.reset(GCP)
H.seedRealm(GCP)
H.money = 40000000
GCP.Capital:Invalidate()
GCP.Guide:Start({ profile = "CUSTOM", minutes = 90 })
local accepted = 0
for round = 1, 30 do
    if GCP.Guide:RequestReplan("market_revision") then accepted = accepted + 1 end
end
expect(accepted <= 1, "Ohne Zeitfortschritt wird hoechstens einmal neu geplant")
GCP:Profile().guide.replans = GCP.Constants.ROUTE.REPLAN.MAX_PER_SESSION
GCP.Guide.lastReplan = nil
expect(not GCP.Guide:RequestReplan("market_revision"),
    "Die Zahl der Neuplanungen je Sitzung ist gedeckelt")
GCP.Guide:Abort()

-- --- AH-Gebuehr genau einmal ----------------------------------------------

H.reset(GCP)
local gross = 1000000
local net = GCP.Prices:NetAuction(gross)
expectEqual(net, math.floor(gross * (1 - GCP.Constants.AH_CUT)),
    "Die AH-Gebuehr wird genau einmal abgezogen")
GCP.Ledger:RecordSale({ itemID = 23425, quantity = 10, totalGross = gross,
    source = "ah", timestamp = H.now })
local feeStats = GCP.Ledger:GetItemStats(23425)
expectEqual(feeStats.revenueGross, gross, "Der Bruttoerloes bleibt brutto")
expectEqual(feeStats.revenueNet, net, "Der Nettoerloes traegt die Gebuehr genau einmal")

-- Nennt die Rechnung des Clients die Gebuehr selbst, gilt genau diese.
GCP.Ledger:RecordSale({ itemID = 22785, quantity = 1, totalGross = 200000,
    consignment = 7000, source = "ah", timestamp = H.now })
local invoiceStats = GCP.Ledger:GetItemStats(22785)
expectEqual(invoiceStats.revenueNet, 193000,
    "Die vom Client genannte Gebuehr schlaegt die pauschale Rechnung")

-- --- Unbekannte Item-Infos ------------------------------------------------

H.reset(GCP)
local unknownItem = 987654
expect(GCP.Market:RegisterItem(unknownItem, "Test"), "Ein unbekanntes Item laesst sich beobachten")
expect(pcall(GCP.Market.AddSnapshot, GCP.Market, unknownItem, 5000, H.now, "Auctionator"),
    "...und bekommt Messpunkte, auch ohne Namen")
expect(pcall(GCP.Capital.GetSnapshot, GCP.Capital, true),
    "Die Kapitalsicht kommt mit unbekannten Items zurecht")


-- ===========================================================================
-- ROBUSTHEIT
--
-- Ein Lua-Fehler in einem Addon reisst in WoW alles mit, was danach im selben
-- Aufruf haette laufen sollen. Deshalb wird hier jede oeffentliche Funktion
-- mit Unsinn gefuettert: nil, falsche Typen, negative Zahlen, leere Tabellen.
-- Erwartet wird kein sinnvolles Ergebnis - erwartet wird, dass nichts fliegt.
-- ===========================================================================

H.section("Robustheit")
H.reset(GCP)
H.seedRealm(GCP)

-- nil laesst sich nicht in eine Liste schreiben, ohne dass ipairs dort aufhoert.
-- Deshalb ein Platzhalter, der beim Aufruf zu nil wird.
local NIL = {}
local GARBAGE = { NIL, 0, -1, "", "unsinn", {}, { 1, 2, 3 }, true, 1e15, -1e15, 0.5 }
-- Zwei zweite Argumente genuegen: Der erste Parameter ist ueberall der
-- interessante, und jede weitere Kombination kostet Laufzeit, ohne eine neue
-- Aussage zu belegen.
local SECOND = { NIL, {} }
local function unwrap(value)
    if value == NIL then return nil end
    return value
end

local FUZZ = {
    { GCP.Market, { "GetMarketScore", "GetStats", "SnapshotCount", "LastSnapshot",
        "RegisterItem", "UnregisterItem", "IsWatched", "GetWatchEntry",
        "RegisterWatchItem", "RemoveWatchItem", "ToggleWatchItem", "GetTrackReason",
        "ScoreBand", "ConfidenceLabel", "FormatCount", "FormatBytes",
        "GetDepth", "ComputeDepth", "DescribeDepth", "DepthSignals", "PruneDepth",
        -- 1.0.0-beta.10
        "GetProbes", "PriceAt", "RecordScoreProbes", "PruneProbes",
        "LastProbeByItem", "DescribeScore" } },
    { GCP.Ledger, { "GetItemStats", "GetLiquidity", "GetGlobalStats", "GetRecentTrades",
        "RecordPurchase", "RecordSale", "RecordAuctionPosted", "RecordAuctionExpired",
        "RecordAuctionCancelled", "CountOpenPostings", "ScoreBand", "ConfidenceLabel",
        "FormatVelocity", "BuildReport", "DurationHours", "ResolveName",
        -- 1.0.0-beta.10
        "ExpectedRelistCost", "AbsorptionPerWeek" } },
    { GCP.Opportunity, { "ScoreOf", "ScoreBand", "TypeLabel", "Make", "Get",
        "ConfidenceRank", "ConfidenceFromDays", "FormatROI", "FormatHours",
        "Explain", "SummaryText", "StatusLabel", "ExecutionStatus", "SupplyFor",
        "LiquidityOf", "SetSortMode",
        -- 1.0.0-beta.10
        "ClaimExecution", "IsIdentityMatchable", "InputsOf", "AssessInputs",
        "RelistCostFor", "MatchHistoryOutcomes" } },
    -- 1.1.0
    { GCP.Demand, { "StructuralFor", "RealmFor", "PersonalFor", "CurrentFor",
        "EvidenceFor", "CapacityFor", "ExplainCapacity", "DescribeStructural" } },
    { GCP.Actionability, { "Assess", "Explain", "ClassLabel", "Rank" } },
    { GCP.Income, { "Record", "GetEvents", "Summary", "Lines", "SourceLabel",
        "ClassifyTrade", "ValueOfTrade", "SnapshotTrade", "OnMoney", "Prune",
        "SetContext", "ActiveContext", "OnEnchantCast" } },
    { GCP.Activity, { "Start", "Stop", "Tick", "CheckIdle", "OnIncome", "AddCost",
        "MethodStats", "AllMethods", "ContextStats", "ConfidenceOf", "SummaryText" } },
    { GCP.Recommendation, { "Best", "Explain", "Headline", "ItemCandidate",
        "MethodCandidates" } },
    { GCP.Knowledge, { "DemandIdentity", "GetItem", "ItemName",
        "GetCatalystsForItem", "GetProductsOf" } },
    { GCP.Opportunity, { "ArbitrageFor" } },
        { GCP.Future, { "GetItemRecord", "GetCatalysts", "GetFutureDemandScore",
        "GetHypeScore", "GetItemKnowledge", "GetExplanation", "ScoreBand",
        "PhaseTiming", "TimingLabel", "GetPhases", "Watch" } },
    { GCP.Capital, { "ComputeReserve", "SetReserve", "SizePosition",
        "ExplainAllocation", "SummaryText", "GetPositionMeta", "RememberPositionMeta",
        "CostBasisFor", "UnitValue", "ExposureShare", "ExposureValue",
        "ExposureWarnings", "PruneMeta",
        -- 1.0.0-beta.10
        "UnitCap", "AbsorptionFor", "Allocate" } },
    { GCP.Execution, { "MinutesFor", "Validate", "TopologicalOrder",
        "Describe", "Explain", "TypeLabel", "StockOf" } },
    { GCP.Route, { "ProfileSetup", "ProfileLabel", "TravelMinutes",
        "MinutesPerUnit", "ValidateStep", "Validate", "DescribeProblem",
        "ShouldReplace", "Totals", "EvaluateGoal", "Confidence", "SummaryText",
        "CompletionForLocation" } },
    { GCP.Guide, { "GetState", "SetState", "CurrentStep", "Complete", "Skip",
        "Progress", "Why", "StepTitle", "StepLines", "HeaderText", "OnEvent",
        "OnLedgerEvent", "GroupOf", "CountInBags", "RealizedSince", "PackStep" } },
    { GCP.Navigation, { "GetWaypoint", "SetTarget", "FindLocation", "Learn",
        "KnownCount", "Forget", "CompassText", "FormatDistance", "DescribeTarget",
        "Bearing", "WorldPosition", "DistanceYards", "OnEvent", "SendToTomTom" } },
    { GCP.Farm, { "Start", "Stop", "Status", "Assess", "GetRate", "BuildOpportunities",
        "ConfidenceOf", "CountOf", "Snapshot", "BetterAlternative", "SummaryText" } },
    { GCP.Personal, { "GetStats", "RecordStep", "RecordSkip", "RecordOutcome",
        "RecordFarmSession", "RecordRouteFinished", "ExpectedValueText",
        "OnLedgerEvent", "SummaryText" } },
    { GCP.Analytics, { "BandOf", "FormatCell", "DimensionPerformance" } },
    { GCP.Calibration, { "FactorFor", "SetEnabled", "MeasuredFactor",
        "ModelLabel", "Lines" } },
    { GCP.Knowledge, { "GetPhase", "GetCatalystsForItem", "GetCatalystsForPhase",
        "GetMaterialsOf", "GetProductsOf", "GetItem", "ItemName", "PhaseStatus",
        "RegisterLocation", "RegisterFarmRoute", "GetLocation",
        "GetLocationsOfKind", "GetFarmRoutesForItem" } },
    { GCP.Prices, { "GetMarketPrice", "GetVendorPrice", "IsAuctionable",
        "GetDisenchantPrice", "GetScanAgeDays", "NetAuction", "FormatMoney",
        "FormatGold", "GetPlanningPrice", "GetPlanningPriceInfo",
        "GetBestPlanningValue", "ConfidenceLabel", "FormatPlanningBasis" } },
}

local crashes = 0
local calls = 0
local timing = {}
local seenCrash = {}
for _, entry in ipairs(FUZZ) do
    local module, names = entry[1], entry[2]
    for _, name in ipairs(names) do
        local fn = module[name]
        expect(type(fn) == "function", "Funktion " .. name .. " existiert")
        if type(fn) == "function" then
            local started = os.clock()
            for _, rawFirst in ipairs(GARBAGE) do
                for _, rawSecond in ipairs(SECOND) do
                    local first, second = unwrap(rawFirst), unwrap(rawSecond)
                    calls = calls + 1
                    local ok, err = pcall(fn, module, first, second)
                    if not ok then
                        crashes = crashes + 1
                        if not seenCrash[name] then
                            seenCrash[name] = true
                            print(string.format("  Absturz in %s(%s, %s): %s",
                                name, tostring(first), tostring(second), tostring(err)))
                        end
                    end
                end
            end
            timing[#timing + 1] = { name = name, seconds = os.clock() - started }
        end
    end
end

-- PERFORMANCE-INVARIANTE. Der Robustheitstest ist nebenbei ein Waechter gegen
-- entartete Schleifen: Eine Funktion, die fuer zweiundzwanzig Aufrufe mit
-- Unsinn laenger als eine halbe Sekunde braucht, hat eine Grenze, die vom
-- ARGUMENT abhaengt statt von den Daten. Genau so wurde die Schleife gefunden,
-- die ein negativer Deckel in den Kuerzungen ausloeste - sie lief bis in den
-- negativen Zahlenbereich und damit praktisch nie zu Ende.
table.sort(timing, function(a, b) return a.seconds > b.seconds end)
local slow = 0
for _, entry in ipairs(timing) do
    if entry.seconds > 0.5 then
        slow = slow + 1
        print(string.format("  LANGSAM: %s braucht %.2fs für %d Aufrufe",
            entry.name, entry.seconds, #GARBAGE * #SECOND))
    end
end
expectEqual(slow, 0,
    "Keine Funktion braucht für 22 Unsinns-Aufrufe mehr als eine halbe Sekunde")

-- Die teuren Einstiegspunkte bekommen eine eigene, kurze Runde: Ein voller
-- Planungslauf je Argumentkombination waere Minuten an Rechenzeit fuer eine
-- Aussage, die vier Kombinationen genauso gut belegen.
local HEAVY = {
    { GCP.Route, "Plan" },
    { GCP.Capital, "Allocate" },
    { GCP.Capital, "BuildPositions" },
    { GCP.Execution, "BuildPlan" },
    { GCP.Opportunity, "Get" },
    { GCP.Guide, "RequestReplan" },
    { GCP.Guide, "Replan" },
    { GCP.Analytics, "GetReport" },
    { GCP.Calibration, "Update" },
    { GCP.Farm, "BuildOpportunities" },
}
for _, entry in ipairs(HEAVY) do
    local module, name = entry[1], entry[2]
    local fn = module[name]
    expect(type(fn) == "function", "Funktion " .. name .. " existiert")
    if type(fn) == "function" then
        for _, raw in ipairs({ NIL, "unsinn", {}, -1 }) do
            calls = calls + 1
            local ok, err = pcall(fn, module, unwrap(raw))
            if not ok then
                crashes = crashes + 1
                if not seenCrash[name] then
                    seenCrash[name] = true
                    print(string.format("  Absturz in %s(%s): %s",
                        name, tostring(raw), tostring(err)))
                end
            end
        end
    end
end

expect(calls > 1500, "Der Robustheitstest ruft jede Funktion vielfach auf")
expectEqual(crashes, 0,
    "Keine oeffentliche Funktion stuerzt bei unsinnigen Argumenten ab")

-- Nach dem Beschuss muss alles weiterlaufen.
H.reset(GCP)
H.seedRealm(GCP)
expect(pcall(GCP.Route.Plan, GCP.Route, { profile = "CUSTOM" }),
    "Nach dem Robustheitstest laesst sich weiter planen")
expect(pcall(GCP.PrintDiagnostics, GCP), "...und die Diagnose laeuft")

H.report("simulation.lua")
