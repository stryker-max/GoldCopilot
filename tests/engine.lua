-- Tests der Entscheidungsschicht ab 0.9.0: Capital Brain, Execution Engine,
-- Route Planner, Guide Engine, Navigation, Farm Brain, Personal Brain,
-- Analytics, Kalibrierung und Markttiefe.
--
-- smoke.lua prueft die Rechenwege der Bewertungsmodule, ui.lua die Oberflaeche.
-- Hier geht es um die Frage, die 0.9 zum ersten Mal beantwortet: Was soll der
-- Spieler jetzt tun - und haelt der Plan seine eigenen Zusagen ein?
--
-- Start ueber "node tests/run.mjs" aus dem Repo-Wurzelverzeichnis.

local H = dofile("tests/harness.lua")
local expect, expectEqual = H.expect, H.expectEqual
local expectRange, expectNear = H.expectRange, H.expectNear

local GCP = H.boot()

-- ===========================================================================
-- CAPITAL BRAIN
-- ===========================================================================

H.section("Capital")

-- --- Reserve ---------------------------------------------------------------

local reserve = GCP.Capital:GetReserveSettings()
expectEqual(reserve.mode, "percent", "Die Cash-Reserve ist voreingestellt prozentual")
expectEqual(reserve.percent, 0.20, "...und liegt bei 20 %")
expectEqual(GCP.Capital:ComputeReserve(10000000), 2000000,
    "20 % von 1000 g sind 200 g Reserve")
expectEqual(GCP.Capital:ComputeReserve(0), 0,
    "Ohne Gold gibt es keine Reserve statt einer negativen")

expect(GCP.Capital:SetReserve("absolute", 5000000), "Die Reserve laesst sich fest setzen")
expectEqual(GCP.Capital:ComputeReserve(10000000), 5000000,
    "Eine feste Reserve von 500 g gilt unveraendert")
expectEqual(GCP.Capital:ComputeReserve(3000000), 3000000,
    "Eine feste Reserve kann nie groesser sein als das vorhandene Gold")
expect(not GCP.Capital:SetReserve("unsinn", 1), "Ein unbekannter Reservemodus wird abgelehnt")
GCP.Capital:SetReserve("percent", 0.2)

expect(GCP.Capital:SetReserve("percent", 5), "Ein absurder Prozentwert wird angenommen ...")
expect(GCP.Capital:GetReserveSettings().percent <= 0.9, "... aber auf das Maximum gedeckelt")
GCP.Capital:SetReserve("percent", 0.2)

-- --- Kaltstart -------------------------------------------------------------

H.money = 30000000
GCP.Capital:Invalidate()
local cold = GCP.Capital:GetSnapshot(true)
expectEqual(cold.currentGold, 30000000, "Das aktuelle Gold kommt aus GetMoney")
expectEqual(cold.reservedGold, 6000000, "Die Reserve betraegt 20 % davon")
expectEqual(cold.availableGold, 24000000, "Frei verfuegbar ist der Rest")
expectEqual(cold.investedCapital, 0, "Ohne Positionen ist nichts investiert")
expectEqual(cold.openPositions, 0, "Ohne Auktionen und Kaeufe gibt es keine Position")
expectEqual(cold.unrealizedPnL, nil,
    "Ohne Positionen gibt es keinen unrealisierten Gewinn - auch nicht null")
expect(GCP.Capital:SummaryText(cold):find("noch keine offenen Positionen", 1, true) ~= nil,
    "Der Kaltstart sagt ausdruecklich, dass es keine Positionen gibt")

-- --- Positionen aus offenen Auktionen --------------------------------------

H.seedTrade(GCP, 21884, { quantity = 5, buyPrice = 150000, sellPrice = 210000, rounds = 8 })
-- Nachkauf: Ohne ihn waeren alle gekauften Stuecke laengst verkauft, und dann
-- haette die neue Auktion zu Recht keinen belegten Einstand.
GCP.Ledger:RecordPurchase({ itemID = 21884, quantity = 10, unitPrice = 150000,
    timestamp = H.now - 7200 })
H.seedOpenAuction(GCP, 21884, 10, 220000)
GCP.Capital:Invalidate()
local snapshot = GCP.Capital:GetSnapshot(true)
expectEqual(snapshot.openPositions, 1, "Die offene Auktion ist genau eine Position")
local position = snapshot.positions[1]
expectEqual(position.itemID, 21884, "...auf das eingestellte Item")
expectEqual(position.quantity, 10, "...mit der eingestellten Stueckzahl")
expectEqual(position.source, "auction", "...als Auktionsposition erkannt")
expectEqual(position.costBasis, 150000, "Die Kostenbasis kommt aus den eigenen Kaeufen")
expect(position.costBasisKnown, "...und gilt als bekannt")
expectEqual(position.capitalAllocated, 1500000, "Gebundenes Kapital = Einstand x Menge")
expect(position.depositAtRisk > 0, "Die Einstellgebuehr steht als Risiko an der Position")

-- Die Kostenbasis deckt nur, was auch gekauft wurde.
H.seedOpenAuction(GCP, 22456, 20, 150000)
GCP.Capital:Invalidate()
snapshot = GCP.Capital:GetSnapshot(true)
local unknown = nil
for _, entry in ipairs(snapshot.positions) do
    if entry.itemID == 22456 then unknown = entry end
end
expect(unknown ~= nil, "Auch ein nie gekauftes Item wird zur Position, sobald es im AH liegt")
expectEqual(unknown.costBasis, nil, "...aber ohne Kaufhistorie bleibt der Einstand UNKNOWN")
expectEqual(unknown.capitalAllocated, nil, "...und damit auch das gebundene Kapital")
expectEqual(unknown.unrealizedPnL, nil, "...und der unrealisierte Gewinn")
expect(snapshot.unknownCostPositions >= 1, "Der Snapshot zaehlt Positionen ohne Einstand")

-- --- Bestand ist kein Investment -------------------------------------------

H.clearBags()
H.addBagItem(60003, 20)      -- Manatraenke: nie gekauft
H.addBagItem(21885, 8)       -- Urwasser: nie gekauft
GCP.Capital:Invalidate()
snapshot = GCP.Capital:GetSnapshot(true)
local hasPotion = false
for _, entry in ipairs(snapshot.positions) do
    if entry.itemID == 60003 then hasPotion = true end
end
expect(not hasPotion, "Ein nie gekaufter Beutelbestand wird nicht zur Position erklaert")
expect(snapshot.inventoryValue > 0, "Der Bestandswert wird trotzdem beziffert")

-- Gekaufter Bestand dagegen schon.
GCP.Ledger:RecordPurchase({ itemID = 22574, quantity = 30, unitPrice = 17000,
    timestamp = H.now - 3600 })
H.addBagItem(22574, 30)
GCP.Capital:Invalidate()
snapshot = GCP.Capital:GetSnapshot(true)
local motes = nil
for _, entry in ipairs(snapshot.positions) do
    if entry.itemID == 22574 then motes = entry end
end
expect(motes ~= nil, "Nachweislich gekaufter Bestand ist eine Position")
if motes then
    expectEqual(motes.quantity, 30, "...in der gekauften Menge")
    expectEqual(motes.costBasis, 17000, "...mit dem eigenen Einkaufspreis")
    expect(motes.currentValue ~= nil, "...und einem heutigen Wert")
end

-- --- Exposure --------------------------------------------------------------

expect(snapshot.exposureBase > 0, "Die Exposure-Basis ist das investierbare Kapital")
local itemShare = GCP.Capital:ExposureShare(snapshot.exposure, "item", 21884)
expect(type(itemShare) == "number", "Es gibt einen Exposure-Anteil je Item")
expectRange(itemShare, 0, 1, "Der Anteil liegt zwischen 0 und 1")
local groupShare = GCP.Capital:ExposureShare(snapshot.exposure, "group", "Handwerkswaren/Elementar")
expect(type(groupShare) == "number", "Marktgruppen bekommen ein eigenes Exposure")

-- Eine kuenstlich riesige Position muss eine Warnung ausloesen.
H.seedOpenAuction(GCP, 22457, 400, 100000)
GCP.Ledger:RecordPurchase({ itemID = 22457, quantity = 400, unitPrice = 90000,
    timestamp = H.now - 7200 })
GCP.Capital:Invalidate()
snapshot = GCP.Capital:GetSnapshot(true)
local warned = false
for _, warning in ipairs(snapshot.warnings) do
    if warning.dimension == "item" and warning.key == 22457 then warned = true end
end
expect(warned, "Eine sehr grosse Einzelposition erzeugt eine Exposure-Warnung")

-- --- Position Sizing -------------------------------------------------------

H.section("Position Sizing")

local WIDE = 1000000000    -- Exposure-Basis so gross, dass sie hier nie bindet
local sizing = GCP.Capital:SizePosition({
    unitCost = 100000, investable = 10000000, score = 50, confidence = "high",
    exposureBase = WIDE,
})
expect(sizing ~= nil, "Eine neutrale Chance bekommt eine Positionsgroesse")
expect(sizing.units >= 1, "...von mindestens einem Stueck")
expect(sizing.capital <= 10000000, "...und niemals mehr als das investierbare Kapital")
expect(sizing.share <= 0.35 + 1e-9, "Die Positionsgroesse ist nie All-In")

local weak = GCP.Capital:SizePosition({
    unitCost = 100000, investable = 10000000, score = 50, confidence = "none",
    exposureBase = WIDE,
})
expect(weak == nil or weak.capital < sizing.capital,
    "Ohne Datenlage faellt die Position kleiner aus")

local strong = GCP.Capital:SizePosition({
    unitCost = 100000, investable = 10000000, score = 95, confidence = "high",
    liquidityScore = 90, exposureBase = WIDE,
})
expect(strong.capital > sizing.capital, "Ein hoher Score mit Liquiditaet erlaubt mehr")
expect(strong.share <= 0.35 + 1e-9, "...aber weiterhin nicht mehr als das Maximum")

-- Ohne weite Exposure-Basis greift der Item-Deckel und begrenzt genau dort.
local narrow = GCP.Capital:SizePosition({
    unitCost = 100000, investable = 10000000, score = 95, confidence = "high",
    liquidityScore = 90,
})
expect(narrow.capital < strong.capital,
    "Ohne Spielraum begrenzt das Item-Exposure die Position")
expectEqual(narrow.limitedBy, "Exposure Item", "...und sagt auch, wodurch")

local volatile = GCP.Capital:SizePosition({
    unitCost = 100000, investable = 10000000, score = 95, confidence = "high",
    liquidityScore = 90, volatility = 0.6, exposureBase = WIDE,
})
expect(volatile.capital < strong.capital, "Hohe Schwankung verkleinert die Position")

local hyped = GCP.Capital:SizePosition({
    unitCost = 100000, investable = 10000000, score = 95, confidence = "high",
    liquidityScore = 90, hypeScore = 85, exposureBase = WIDE,
})
expect(hyped.capital < strong.capital, "Ein bereits gelaufener Hype verkleinert die Position")

local capped = GCP.Capital:SizePosition({
    unitCost = 100000, investable = 10000000, score = 95, confidence = "high",
    exposureBase = 10000000, itemExposure = 2000000,
})
expect(capped == nil or capped.capital == 0 or capped.limitedBy:find("Exposure"),
    "Ein bereits ausgeschoepftes Item-Exposure begrenzt die naechste Position")

expectEqual(GCP.Capital:SizePosition({ unitCost = 0, investable = 100000 }), nil,
    "Ohne Kapitalbedarf gibt es keine Positionsgroesse")
expectEqual(GCP.Capital:SizePosition({ unitCost = 1000, investable = 0 }), nil,
    "Ohne freies Kapital gibt es keine Positionsgroesse")
expectEqual(GCP.Capital:SizePosition({ unitCost = 900000000, investable = 1000 }), nil,
    "Reicht es nicht fuer ein Stueck, gibt es keine halbe Position")

local timed = GCP.Capital:SizePosition({
    unitCost = 1000, investable = 100000000, score = 90, confidence = "high",
    timeBudgetMinutes = 10, minutesPerUnit = 2, exposureBase = WIDE,
})
expect(timed ~= nil and timed.units <= 5, "Das Zeitbudget deckelt die Stueckzahl")

-- --- Capital Allocator -----------------------------------------------------

H.section("Allocator")

local function fakeOpportunity(key, kind, itemID, cost, profit, score, confidence)
    return {
        key = key, type = kind, itemID = itemID, saleItemID = itemID,
        title = "Test " .. key, cost = cost, expectedProfit = profit,
        roi = profit / cost, opportunityScore = score, confidence = confidence or "high",
    }
end

local pool = {
    fakeOpportunity("a", "craft", 23571, 400000, 120000, 88),
    fakeOpportunity("b", "conversion", 21884, 180000, 30000, 74),
    fakeOpportunity("c", "resale", 23425, 50000, 9000, 66),
    fakeOpportunity("d", "craft", 21885, 250000, 40000, 61),
    fakeOpportunity("e", "resale", 21877, 6000, 900, 55),
}

local plan = GCP.Capital:Allocate(pool, { capital = 5000000, risk = "medium" })
expect(#plan.allocations > 0, "Der Allocator verteilt Kapital auf mehrere Chancen")
expect(#plan.allocations > 1, "...nicht alles auf die beste")
local sum = 0
for _, allocation in ipairs(plan.allocations) do
    sum = sum + allocation.capital
    expect(allocation.units >= 1, "Jede Allokation umfasst mindestens ein Stueck")
    expectEqual(allocation.units, math.floor(allocation.units),
        "Stueckzahlen sind ganzzahlig")
    expect(allocation.capital == allocation.units * allocation.unitCost,
        "Kapital = Stueckzahl x Stueckkosten")
    expect(#GCP.Capital:ExplainAllocation(allocation) >= 3,
        "Jede Allokation laesst sich erklaeren")
end
expectEqual(sum, plan.invested, "Die Summe der Allokationen ist das investierte Kapital")
expect(plan.invested <= plan.investable,
    "Der Allocator verplant nie mehr als das investierbare Kapital")
expect(plan.unused >= 0, "Der ungenutzte Rest ist nie negativ")

-- Die Reserve bleibt unangetastet, wenn kein Kapital vorgegeben wird.
GCP.Capital:Invalidate()
local live = GCP.Capital:Allocate(pool, {})
expect(live.invested <= live.snapshot.availableGold,
    "Ohne Vorgabe verplant der Allocator hoechstens das frei verfuegbare Gold")
expect(live.invested + live.snapshot.reservedGold <= live.snapshot.currentGold,
    "Die Cash-Reserve wird nie angetastet")

-- Filter nach Chancenart.
local onlyCraft = GCP.Capital:Allocate(pool, { capital = 5000000, types = { craft = true } })
for _, allocation in ipairs(onlyCraft.allocations) do
    expectEqual(allocation.type, "craft", "Der Aktivitaetsfilter laesst nur Crafts durch")
end

-- Kein Kapital, keine Allokation.
local broke = GCP.Capital:Allocate(pool, { capital = 0 })
expectEqual(#broke.allocations, 0, "Ohne Kapital wird nichts zugeteilt")
expectEqual(broke.invested, 0, "...und nichts investiert")

-- Diversifikation: die zweite Chance derselben Art bekommt weniger Anteil.
local twoCrafts = GCP.Capital:Allocate({
    fakeOpportunity("x1", "craft", 23571, 100000, 30000, 80),
    fakeOpportunity("x2", "craft", 21885, 100000, 30000, 80),
}, { capital = 10000000 })
if #twoCrafts.allocations == 2 then
    expect(twoCrafts.allocations[2].capital <= twoCrafts.allocations[1].capital,
        "Die zweite Chance derselben Art bekommt nicht mehr als die erste")
end

-- Ein Risikoprofil veraendert die Groesse, nicht die Reihenfolge.
local cautious = GCP.Capital:Allocate(pool, { capital = 5000000, risk = "low" })
local bold = GCP.Capital:Allocate(pool, { capital = 5000000, risk = "high" })
expect(cautious.invested <= bold.invested,
    "Ein vorsichtiges Profil bindet nicht mehr Kapital als ein mutiges")

-- ===========================================================================
-- EXECUTION ENGINE
-- ===========================================================================

H.section("Execution")

-- Die Kapitalsektion hat mit Absicht ein voellig ueberkonzentriertes Depot
-- gebaut (52 % in einer Marktgruppe). Genau das soll die Allokation blockieren
-- - und tut es auch, wie der folgende Test zeigt. Fuer die Routentests wird
-- danach zurueckgesetzt, sonst prueft jeder weitere Test nur noch den Deckel.
local blockedRoute = GCP.Route:Plan({ profile = "CUSTOM", minutes = 90 })
expectEqual(#blockedRoute.steps, 0,
    "Ein ueberkonzentriertes Depot laesst keine neue Position zu")
expect(blockedRoute.blocker ~= nil, "...und der Planer benennt den Grund")
expect(#blockedRoute.warnings > 0, "...als sichtbaren Hinweis statt einer leeren Liste")
expect(blockedRoute.summary:find("Keine Route", 1, true) ~= nil,
    "...und sagt in Worten, dass es keine Route gibt")

expect(GCP.Ledger:Reset() > 0, "Die Handelsbilanz laesst sich zuruecksetzen")
GCP.Capital:Invalidate()
expectEqual(GCP.Capital:GetSnapshot(true).openPositions, 0,
    "Nach dem Zuruecksetzen gibt es keine Positionen mehr")

-- Ein Realm mit Historie, damit ueberhaupt Chancen entstehen.
for itemID, price in pairs(H.marketPrices) do
    H.seedHistory(GCP, itemID, price, 12, 24, 0.10)
end
-- Ein Rezept, das die Chancenliste als Craft aufnimmt.
GCP.db.recipes = {
    ["Alchemie"] = {
        scannedAt = GCP:Today(),
        list = {
            { name = "Urmacht", product = 23571, numMade = 1,
              mats = { { 21884, 1 }, { 21885, 1 }, { 22451, 1 }, { 22452, 1 }, { 22457, 1 } },
              hasCooldown = true },
        },
    },
}
GCP.Crafts.revision = (GCP.Crafts.revision or 0) + 1
GCP.Market:InvalidateCaches()
GCP.Opportunity:Invalidate()
GCP.Future:Invalidate()

local function allocationFor(kind, itemID, units)
    local report = GCP.Opportunity:BuildReport(true)
    for _, opportunity in ipairs(report.opportunities) do
        if opportunity.type == kind and (itemID == nil or opportunity.itemID == itemID) then
            return {
                opportunity = opportunity, key = opportunity.key, type = kind,
                itemID = opportunity.itemID, title = opportunity.title,
                units = units or 2, unitCost = opportunity.cost,
                capital = opportunity.cost * (units or 2),
                expectedProfit = opportunity.expectedProfit * (units or 2),
                confidence = opportunity.confidence,
            }
        end
    end
    return nil
end

local craftAllocation = allocationFor("craft", 23571, 2)
expect(craftAllocation ~= nil, "Die Chancenliste enthaelt einen Craft mit Bauplan")

H.clearBags()
local craftPlan = GCP.Execution:BuildPlan({ craftAllocation }, { inventory = {} })
expect(craftPlan.valid, "Der erzeugte Aktionsgraph ist gueltig")
expectEqual(#craftPlan.errors, 0, "...und meldet keine Fehler")
expect(#craftPlan.actions >= 7, "Ein Craft aus fuenf Materialien wird in viele Aktionen zerlegt")

local buys, crafts, posts = 0, 0, 0
for _, action in ipairs(craftPlan.actions) do
    if action.type == "BUY" then buys = buys + 1 end
    if action.type == "CRAFT" then crafts = crafts + 1 end
    if action.type == "POST_AUCTION" then posts = posts + 1 end
end
expectEqual(buys, 5, "Fuenf fehlende Materialien ergeben fuenf Kaeufe")
expectEqual(crafts, 1, "...einen Herstellschritt")
expectEqual(posts, 1, "...und genau einen Einstellvorgang")

-- Abhaengigkeiten: Herstellen haengt an allen Kaeufen, Einstellen am Herstellen.
local craftAction, postAction = nil, nil
for _, action in ipairs(craftPlan.actions) do
    if action.type == "CRAFT" then craftAction = action end
    if action.type == "POST_AUCTION" then postAction = action end
end
expectEqual(#craftAction.dependencies, 5, "Der Herstellschritt haengt an allen fuenf Kaeufen")
expectEqual(#postAction.dependencies, 1, "Der Einstellvorgang haengt am Herstellschritt")
expectEqual(postAction.dependencies[1], craftAction.id, "...und zwar genau daran")

-- Kaufmengen richten sich nach der Zahl der Durchgaenge.
for _, action in ipairs(craftPlan.actions) do
    if action.type == "BUY" then
        expectEqual(action.quantity, 2, "Zwei Durchgaenge brauchen je zwei Materialien")
        expect(action.maxBuyPrice > 0, "Jeder Kauf traegt eine Preisobergrenze")
    end
end

-- Bestandsabgleich: Was da ist, wird nicht gekauft.
local stocked = GCP.Execution:BuildPlan({ craftAllocation }, {
    inventory = {
        [21884] = { itemID = 21884, count = 5 },
        [21885] = { itemID = 21885, count = 5 },
    },
})
local stockedBuys = 0
for _, action in ipairs(stocked.actions) do
    if action.type == "BUY" then stockedBuys = stockedBuys + 1 end
end
expectEqual(stockedBuys, 3, "Vorhandene Materialien fallen aus der Einkaufsliste")

-- Teilbestand: nur die fehlende Menge wird gekauft.
local partial = GCP.Execution:BuildPlan({ craftAllocation }, {
    inventory = { [21884] = { itemID = 21884, count = 1 } },
})
for _, action in ipairs(partial.actions) do
    if action.type == "BUY" and action.itemID == 21884 then
        expectEqual(action.quantity, 1, "Bei Teilbestand wird nur die fehlende Menge gekauft")
    end
end

-- Zwei Chancen duerfen sich nicht denselben Bestand teilen.
local doubled = GCP.Execution:BuildPlan({ craftAllocation, craftAllocation }, {
    inventory = { [21884] = { itemID = 21884, count = 2 } },
})
local fireBought = 0
for _, action in ipairs(doubled.actions) do
    if action.type == "BUY" and action.itemID == 21884 then
        fireBought = fireBought + action.quantity
    end
end
expectEqual(fireBought, 2, "Der Bestand wird nur einmal angerechnet, nicht je Chance")

-- Bank und Post statt Kauf.
local banked = GCP.Execution:BuildPlan({ craftAllocation }, {
    inventory = {
        [21884] = { itemID = 21884, count = 4, sources = { Bank = 4 } },
        [21885] = { itemID = 21885, count = 4, sources = { Post = 4 } },
    },
})
local sawBank, sawMail = false, false
for _, action in ipairs(banked.actions) do
    if action.type == "BANK_WITHDRAW" then sawBank = true end
    if action.type == "MAIL" then sawMail = true end
end
expect(sawBank, "Material in der Bank erzeugt einen Bankgang statt eines Kaufs")
expect(sawMail, "Material in der Post erzeugt einen Briefkastengang")

-- Topologische Reihenfolge: Abhaengigkeiten kommen immer zuerst.
local order, complete = GCP.Execution:TopologicalOrder(craftPlan)
expect(complete, "Die topologische Sortierung ist vollstaendig")
local seenAt = {}
for index, action in ipairs(order) do seenAt[action.id] = index end
for _, action in ipairs(order) do
    for _, dependency in ipairs(action.dependencies) do
        expect(seenAt[dependency] < seenAt[action.id],
            "Jede Abhaengigkeit steht vor der Aktion, die sie braucht")
    end
end

-- Zyklen werden erkannt und nicht stillschweigend verschluckt.
local cyclic = { actions = {}, groups = {}, warnings = {}, nextID = 1, virtual = {},
    bank = {}, mail = {} }
GCP.Execution:AddAction(cyclic, { type = "BUY", itemID = 21884, quantity = 1 })
GCP.Execution:AddAction(cyclic, { type = "CRAFT", itemID = 23571, quantity = 1,
    dependencies = { "a1" } })
cyclic.actions[1].dependencies = { "a2" }
cyclic.byID = { a1 = cyclic.actions[1], a2 = cyclic.actions[2] }
local cycleOK, cycleErrors = GCP.Execution:Validate(cyclic)
expect(not cycleOK, "Ein Abhaengigkeitszyklus faellt der Pruefung auf")
expect(table.concat(cycleErrors, " "):find("zyklus") ~= nil,
    "...und wird als Zyklus benannt")

-- Entzaubern: kein erfundener Verkaufsschritt.
local disenchantBlueprint = {
    opportunity = {
        execution = {
            method = "disenchant", unknownOutput = true,
            inputs = { { itemID = 777, count = 1, unitPrice = 100000 } },
            profession = "Verzauberkunst",
        },
    },
    key = "disenchant:777", type = "disenchant", itemID = 777, title = "Testklinge",
    units = 1, unitCost = 100000, capital = 100000, expectedProfit = 40000,
    confidence = "medium",
}
local dePlan = GCP.Execution:BuildPlan({ disenchantBlueprint }, { inventory = {} })
local dePost = nil
for _, action in ipairs(dePlan.actions) do
    if action.type == "POST_AUCTION" then dePost = action end
end
expect(dePost ~= nil, "Auch beim Entzaubern steht ein Einstellschritt")
expectEqual(dePost.itemID, nil, "...aber ohne behauptetes Ergebnis-Item")
expectEqual(dePost.minSellPrice, nil, "...und ohne erfundenen Mindestpreis")
expect(dePost.optional, "...und ausdruecklich als optional markiert")
expectEqual(dePost.completionCondition, "MANUAL",
    "Ein unbekanntes Ergebnis kann nicht automatisch abgehakt werden")

-- Eine Chance ohne Bauplan landet nicht in der Route, sondern in den Hinweisen.
local blind = GCP.Execution:BuildPlan({ { key = "x", title = "Ohne Bauplan",
    units = 1, opportunity = {} } }, { inventory = {} })
expectEqual(#blind.actions, 0, "Ohne Bauplan entsteht keine Aktion")
expect(#blind.warnings > 0, "...aber ein Hinweis darauf")

-- ===========================================================================
-- ROUTE PLANNER
-- ===========================================================================

H.section("Route")

H.money = 50000000
GCP.Capital:Invalidate()
local route = GCP.Route:Plan({ profile = "CUSTOM", minutes = 90 })
expect(#route.steps > 0, "Der Planer erzeugt eine Route")
expect(route.totals.minutes <= 90 + 1, "Die Route haelt das Zeitbudget ein")
expect(route.totals.capital <= route.snapshot.availableGold,
    "Die Route verplant nie mehr als das frei verfuegbare Gold")

-- Wege werden eingesetzt, sobald der Ort wechselt.
local travelSteps, ahSteps = 0, 0
for _, step in ipairs(route.steps) do
    if step.travel then travelSteps = travelSteps + 1 end
    if step.location and step.location.kind == "AUCTION_HOUSE" then ahSteps = ahSteps + 1 end
end
expect(travelSteps > 0, "Die Route enthaelt Wege")
expect(ahSteps > 0, "...und Schritte im Auktionshaus")
expectEqual(route.steps[1].type, "GO_TO", "Der erste Schritt ist ein Weg")

-- Ortsbuendelung: kein Hin und Her zwischen denselben zwei Orten.
local switches = 0
local lastKind = nil
for _, step in ipairs(route.steps) do
    if step.location and step.location.kind ~= "ANYWHERE" then
        if lastKind and step.location.kind ~= lastKind then switches = switches + 1 end
        lastKind = step.location.kind
    end
end
expect(switches <= #route.groups + 2,
    "Die Route wechselt den Ort nicht oefter als noetig")

-- Abhaengigkeiten bleiben auch nach dem Einsetzen der Wege intakt.
local position = {}
for index, step in ipairs(route.steps) do
    if step.id then position[step.id] = index end
end
for _, step in ipairs(route.steps) do
    for _, dependency in ipairs(step.dependencies or {}) do
        expect((position[dependency] or 0) < position[step.id],
            "Auch in der fertigen Route steht jede Abhaengigkeit vorher")
    end
end

-- Zeitbudget: 10 Minuten ergeben eine kuerzere Route als 120.
local shortRoute = GCP.Route:Plan({ profile = "CUSTOM", minutes = 10 })
local longRoute = GCP.Route:Plan({ profile = "CUSTOM", minutes = 120 })
expect(shortRoute.totals.minutes <= longRoute.totals.minutes,
    "Ein kleines Zeitbudget ergibt keine laengere Route")
expect(shortRoute.totals.steps <= longRoute.totals.steps,
    "...und keine Route mit mehr Schritten")

-- Kapitalgrenze
local poor = GCP.Route:Plan({ profile = "CUSTOM", minutes = 90, capital = 20000 })
expect(poor.totals.capital <= 20000, "Eine harte Kapitalgrenze wird eingehalten")

-- Profile
for _, profile in ipairs({ "QUICK_GOLD", "MAX_PROFIT", "LOW_RISK", "GROW_CAPITAL",
    "TRADING", "CRAFTING", "FUTURE_INVESTING", "CUSTOM" }) do
    local planned = GCP.Route:Plan({ profile = profile })
    expect(planned ~= nil, "Profil " .. profile .. " erzeugt eine Route")
    expect(type(planned.summary) == "string", "...mit einer Zusammenfassung")
    expect(planned.totals.capital <= planned.snapshot.availableGold,
        "...die die Kapitalgrenze einhaelt")
end
local tradingRoute = GCP.Route:Plan({ profile = "TRADING" })
for _, group in ipairs(tradingRoute.groups) do
    expect(group.type == "resale" or group.type == "conversion",
        "Das Handelsprofil enthaelt nur Handelschancen")
end

-- Goldziel: Realismus statt Wunschzahl.
local goalRoute = GCP.Route:Plan({ profile = "CUSTOM", minutes = 90, goal = 100000000 })
expectEqual(goalRoute.goal.reachable, false, "Ein unerreichbares Ziel wird nicht behauptet")
expect(goalRoute.goal.text:find("geschätzte Potenzial", 1, true) ~= nil
    or goalRoute.goal.text:find("keine belastbare", 1, true) ~= nil,
    "...sondern das tatsaechliche Potenzial genannt")
expect(goalRoute.goal.shortfall > 0, "...und die Luecke beziffert")

local easyGoal = GCP.Route:Plan({ profile = "CUSTOM", minutes = 90, goal = 1 })
expectEqual(easyGoal.goal.reachable, true, "Ein leicht erreichbares Ziel gilt als erreichbar")

-- Hysteresis
local stable = { totals = { profit = 1000000 }, steps = { 1 } }
local marginal = { totals = { profit = 1020000 }, steps = { 1 } }
local better = { totals = { profit = 2000000 }, steps = { 1 } }
expect(not (GCP.Route:ShouldReplace(stable, marginal)),
    "Eine minimal bessere Route ersetzt die laufende nicht")
expect(GCP.Route:ShouldReplace(stable, better),
    "Eine deutlich bessere Route ersetzt sie schon")
expect(GCP.Route:ShouldReplace(stable, marginal, "invalid"),
    "Eine ungueltige laufende Route wird immer ersetzt")
expect(GCP.Route:ShouldReplace(nil, marginal), "Ohne laufende Route wird immer geplant")
expect(not GCP.Route:ShouldReplace(stable, { totals = { profit = 5000000 }, steps = {} }),
    "Eine leere Route ersetzt nie eine laufende")

-- Gueltigkeit: ein Preis ueber der Einstiegszone macht den Schritt ungueltig.
local buyStep = nil
for _, step in ipairs(route.steps) do
    if step.type == "BUY" and step.itemID and step.maxBuyPrice then buyStep = step end
end
expect(buyStep ~= nil, "Die Route enthaelt einen Kaufschritt mit Preisgrenze")
if buyStep then
    expect(GCP.Route:ValidateStep(buyStep), "Beim Planungspreis ist der Schritt gueltig")
    H.setPrice(buyStep.itemID, buyStep.maxBuyPrice * 3)
    local ok, reason = GCP.Route:ValidateStep(buyStep)
    expect(not ok, "Ein deutlich hoeherer Marktpreis macht ihn ungueltig")
    expectEqual(reason, "price_above_max", "...mit benanntem Grund")
    local problem = { step = buyStep, reason = reason, price = buyStep.maxBuyPrice * 3 }
    expect(GCP.Route:DescribeProblem(problem):find("Einstiegszone", 1, true) ~= nil,
        "...und einer Erklaerung in Worten")
    H.setPrice(buyStep.itemID, H.marketPrices[buyStep.itemID] / 3)
end


-- ===========================================================================
-- NAVIGATION
-- ===========================================================================

H.section("Navigation")

expectEqual(GCP.Navigation:KnownCount(), 0,
    "Beim ersten Start kennt Gold Copilot keinen einzigen Ort")
expectEqual(GCP.Knowledge:CountLocations(), 0,
    "Die Wissensbasis enthaelt bewusst keine geratenen Koordinaten")

local unknownWaypoint, unknownReason = GCP.Navigation:GetWaypoint(
    { kind = "AUCTION_HOUSE" })
expectEqual(unknownWaypoint, nil, "Ohne gelernten Ort gibt es keinen Pfeil")
expectEqual(unknownReason, "unbekannt", "...und der Grund wird benannt")
local label, hint = GCP.Navigation:DescribeTarget({ kind = "AUCTION_HOUSE" }, nil)
expectEqual(label, "Auktionshaus", "Der Guide nennt das Ziel trotzdem beim Namen")
expect(hint:find("einmal hingehen", 1, true) ~= nil,
    "...und erklaert, wie der Pfeil entsteht")

-- Der Spieler oeffnet ein Auktionshaus: damit ist der Ort belegt.
H.mapID = 85
H.position = { x = 0.55, y = 0.68 }
H.zoneName = "Orgrimmar"
expect(GCP.Navigation:OnEvent("AUCTION_HOUSE_SHOW"), "Ein AH-Besuch lernt den Ort")
expectEqual(GCP.Navigation:KnownCount("AUCTION_HOUSE"), 1, "...genau einen")

-- Derselbe Ort, drei Schritte weiter: kein zweiter Eintrag.
H.position = { x = 0.5535, y = 0.6815 }
GCP.Navigation:OnEvent("AUCTION_HOUSE_SHOW")
expectEqual(GCP.Navigation:KnownCount("AUCTION_HOUSE"), 1,
    "Ein zweiter Auktionator daneben ist derselbe Ort")

-- Ein anderes Auktionshaus auf einer anderen Karte ist ein neuer Ort.
H.mapID = 84
H.position = { x = 0.61, y = 0.72 }
H.zoneName = "Sturmwind"
GCP.Navigation:OnEvent("AUCTION_HOUSE_SHOW")
expectEqual(GCP.Navigation:KnownCount("AUCTION_HOUSE"), 2,
    "Ein Auktionshaus auf einer anderen Karte ist ein eigener Ort")

-- Pfeil: Richtung und Entfernung.
H.mapID = 85
H.position = { x = 0.55, y = 0.78 }     -- suedlich des Ziels
H.facing = 0                            -- Blick nach Norden
local waypoint = GCP.Navigation:GetWaypoint({ kind = "AUCTION_HOUSE" })
expect(waypoint ~= nil, "Nach dem Lernen gibt es einen Wegpunkt")
expectEqual(waypoint.mapID, 85, "...auf der eigenen Karte")
expect(waypoint.distance ~= nil, "...mit einer Entfernung")
expect(waypoint.relative ~= nil, "...und einer Richtung")
expectEqual(GCP.Navigation:CompassText(waypoint.relative), "vorwärts",
    "Nach Norden blickend liegt ein noerdliches Ziel geradeaus")

H.facing = math.pi                      -- Blick nach Sueden
waypoint = GCP.Navigation:GetWaypoint({ kind = "AUCTION_HOUSE" })
expectEqual(GCP.Navigation:CompassText(waypoint.relative), "zurück",
    "Umgedreht liegt dasselbe Ziel hinter dem Spieler")

H.facing = math.pi / 2                  -- Blick nach Westen
waypoint = GCP.Navigation:GetWaypoint({ kind = "AUCTION_HOUSE" })
expectEqual(GCP.Navigation:CompassText(waypoint.relative), "rechts",
    "Nach Westen blickend liegt ein noerdliches Ziel rechts")
H.facing = 0

-- Ankunft
H.position = { x = 0.5501, y = 0.6801 }
waypoint = GCP.Navigation:GetWaypoint({ kind = "AUCTION_HOUSE" })
expect(waypoint.arrived, "Direkt am Ziel gilt der Wegpunkt als erreicht")

-- Berufsorte tragen den Beruf als Schluessel.
H.position = { x = 0.30, y = 0.30 }
GCP.Navigation:Learn("PROFESSION", "Alchemie")
local alchemy = GCP.Navigation:GetWaypoint({ kind = "PROFESSION", key = "Alchemie" })
expect(alchemy ~= nil, "Ein gelernter Berufsort ist auffindbar")
expectEqual(GCP.Navigation:GetWaypoint({ kind = "PROFESSION", key = "Schneiderei" }), nil,
    "...aber nicht unter einem anderen Beruf")

-- ANYWHERE erzeugt nie einen Pfeil.
expectEqual(GCP.Navigation:GetWaypoint({ kind = "ANYWHERE" }), nil,
    "Fuer Schritte ohne Ort gibt es keinen Pfeil")

-- Realmtrennung: ein anderer Realm kennt die Orte nicht.
local realmBefore = H.realm
H.realm = "AndererRealm"
expectEqual(GCP.Navigation:KnownCount("AUCTION_HOUSE"), 0,
    "Ein anderer Realm erbt keine gelernten Orte")
H.realm = realmBefore
expectEqual(GCP.Navigation:KnownCount("AUCTION_HOUSE"), 2,
    "...und der eigene Realm behaelt seine")

local factionBefore = H.faction
H.faction = "Alliance"
expectEqual(GCP.Navigation:KnownCount("AUCTION_HOUSE"), 0,
    "Die andere Fraktion kennt die eigenen Orte ebenfalls nicht")
H.faction = factionBefore

-- TomTom ist optional.
expect(not GCP.Navigation:HasTomTom(), "Ohne TomTom laeuft die Navigation weiter")
TomTom = { AddWaypoint = function() return "handle" end,
    RemoveWaypoint = function() return true end }
expect(GCP.Navigation:HasTomTom(), "Mit TomTom wird es erkannt")
expect(GCP.Navigation:SendToTomTom(waypoint), "...und ein Wegpunkt gesetzt")
expect(GCP.Navigation:ClearTomTom(), "...der sich wieder entfernen laesst")
TomTom = nil

-- Ortswissen laesst sich verwerfen.
expect(GCP.Navigation:Forget("AUCTION_HOUSE") > 0, "Gelernte Orte lassen sich loeschen")
expectEqual(GCP.Navigation:KnownCount("AUCTION_HOUSE"), 0, "...und sind dann weg")
H.mapID = 85
H.position = { x = 0.55, y = 0.68 }
GCP.Navigation:OnEvent("AUCTION_HOUSE_SHOW")

-- Ungueltige Ortseintraege in der Wissensbasis werden verworfen, nicht benutzt.
local rejectedBefore = #GCP.Knowledge.rejected
expect(not GCP.Knowledge:RegisterLocation({ id = "kaputt", kind = "AUCTION_HOUSE",
    mapID = -1, x = 0.5, y = 0.5, name = "X", sourceConfidence = "official",
    sourceName = "Test" }), "Eine negative MapID wird abgelehnt")
expect(not GCP.Knowledge:RegisterLocation({ id = "kaputt2", kind = "AUCTION_HOUSE",
    mapID = 85, x = 1.5, y = 0.5, name = "X", sourceConfidence = "official",
    sourceName = "Test" }), "Eine Koordinate ausserhalb 0..1 wird abgelehnt")
expect(not GCP.Knowledge:RegisterLocation({ id = "kaputt3", kind = "UNSINN",
    mapID = 85, x = 0.5, y = 0.5, name = "X", sourceConfidence = "official",
    sourceName = "Test" }), "Eine unbekannte Ortsart wird abgelehnt")
expect(not GCP.Knowledge:RegisterLocation({ id = "kaputt4", kind = "AUCTION_HOUSE",
    mapID = 85, x = 0.5, y = 0.5, name = "X" }), "Ein Ort ohne Provenance wird abgelehnt")
expect(GCP.Knowledge:RegisterLocation({ id = "gut", kind = "AUCTION_HOUSE",
    mapID = 85, x = 0.5, y = 0.5, name = "Testauktionshaus",
    sourceConfidence = "official", sourceName = "Test" }),
    "Ein vollstaendiger Ort wird angenommen")
expect(not GCP.Knowledge:RegisterLocation({ id = "gut", kind = "BANK",
    mapID = 85, x = 0.5, y = 0.5, name = "Doppelt",
    sourceConfidence = "official", sourceName = "Test" }),
    "Eine doppelte Kennung wird abgelehnt")
expectEqual(#GCP.Knowledge.rejected - rejectedBefore, 5,
    "Jeder verworfene Eintrag wird gezaehlt statt still geschluckt")

-- ===========================================================================
-- GUIDE ENGINE
-- ===========================================================================

H.section("Guide")

expectEqual(GCP.Guide:GetState(), "IDLE", "Ohne Route ist der Guide untaetig")
expectEqual(GCP.Guide:StepCount(), 0, "...und hat keine Schritte")
expect(GCP.Guide:HeaderText():find("Keine Route", 1, true) ~= nil,
    "...und sagt das auch")

H.money = 50000000
GCP.Capital:Invalidate()
local started = GCP.Guide:Start({ profile = "CUSTOM", minutes = 90 })
expectEqual(GCP.Guide:GetState(), "ACTIVE", "Nach dem Start laeuft die Route")
expect(GCP.Guide:StepCount() > 0, "...mit Schritten")
local step, index = GCP.Guide:CurrentStep()
expectEqual(index, 1, "Der erste offene Schritt ist Schritt 1")
expectEqual(step.type, "GO_TO", "...und das ist ein Weg")
expect(GCP.Guide:HeaderText():find("Schritt 1 /", 1, true) ~= nil,
    "Die Kopfzeile zaehlt Schritte")

-- Automatische Erkennung: Auktionshaus betreten.
expect(GCP.Guide:OnEvent("AUCTION_HOUSE_SHOW"), "Das Betreten des AH hakt den Weg ab")
local store = GCP:Profile().guide
expect(store.progress[step.id].auto, "...und zwar als automatisch erkannt")
local buyStep2 = GCP.Guide:CurrentStep()
expectEqual(buyStep2.type, "BUY", "Danach steht der Kauf an")

-- Ein Ereignis, das nicht zum Schritt passt, hakt nichts ab.
expect(not GCP.Guide:OnEvent("BANKFRAME_OPENED"),
    "Ein fremdes Ereignis schliesst keinen Schritt ab")

-- Der bestaetigte Kauf aus dem Ledger schliesst den Kaufschritt.
GCP.Ledger:RecordPurchase({ itemID = buyStep2.itemID, quantity = buyStep2.quantity,
    unitPrice = buyStep2.maxBuyPrice })
expect(store.progress[buyStep2.id] ~= nil, "Ein bestaetigter Kauf hakt den Kaufschritt ab")
expect(store.progress[buyStep2.id].auto, "...automatisch")

-- Die Provenance der Position ist damit bekannt.
local meta = GCP.Capital:GetPositionMeta(buyStep2.itemID)
expect(meta ~= nil, "Der Guide merkt sich, aus welcher Chance ein Kauf stammt")

-- Manuelles Abschliessen ist immer moeglich - und wird als manuell gefuehrt.
local manualStep = GCP.Guide:CurrentStep()
expect(GCP.Guide:Complete(manualStep.id, false), "Ein Schritt laesst sich von Hand abhaken")
expectEqual(store.progress[manualStep.id].auto, false,
    "...und gilt dann ausdruecklich nicht als bestaetigt")
expect(not GCP.Guide:Complete(manualStep.id, false),
    "Ein bereits erledigter Schritt laesst sich nicht doppelt abhaken")

-- Ueberspringen nimmt alles mit, was darauf aufbaut.
local before = GCP.Guide:DoneCount()
local skipStep = GCP.Guide:CurrentStep()
local dependents = 0
for _, candidate in ipairs(store.steps) do
    for _, dependency in ipairs(candidate.dependencies or {}) do
        if dependency == skipStep.id then dependents = dependents + 1 end
    end
end
expect(GCP.Guide:Skip(skipStep.id), "Ein Schritt laesst sich ueberspringen")
expect(store.skipped[skipStep.id] ~= nil, "...und ist danach als uebersprungen vermerkt")
if dependents > 0 then
    local cascaded = 0
    for _, entry in pairs(store.skipped) do
        if entry.cascade then cascaded = cascaded + 1 end
    end
    expect(cascaded > 0, "Was auf einem uebersprungenen Schritt aufbaut, faellt mit weg")
end

-- Pause und Fortsetzen
expect(GCP.Guide:Pause(), "Die Route laesst sich pausieren")
expectEqual(GCP.Guide:GetState(), "PAUSED", "...und ist dann pausiert")
expect(not GCP.Guide:OnEvent("AUCTION_HOUSE_SHOW"),
    "Pausiert wird nichts automatisch abgehakt")
expect(GCP.Guide:Resume(), "...und laesst sich fortsetzen")
expectEqual(GCP.Guide:GetState(), "ACTIVE", "...danach laeuft sie wieder")

-- Aktive Zeit zaehlt nur waehrend der Route und nicht ueber Pausen hinweg.
local secondsBefore = GCP:Profile().guide.activeSeconds
H.advance(30)
GCP.Guide:Tick()
expect(GCP:Profile().guide.activeSeconds > secondsBefore, "Aktive Zeit laeuft mit")
GCP.Guide:Pause()
H.advance(3600)
GCP.Guide:Tick()
local pausedSeconds = GCP:Profile().guide.activeSeconds
GCP.Guide:Resume()
H.advance(10)
GCP.Guide:Tick()
expect(GCP:Profile().guide.activeSeconds - pausedSeconds < 60,
    "Eine Stunde Pause zaehlt nicht als aktive Zeit")

-- Fortschritt
local progress = GCP.Guide:Progress()
expect(progress.done >= 2, "Der Fortschritt zaehlt erledigte Schritte")
expect(progress.steps >= progress.done, "...nie mehr als es Schritte gibt")
expect(progress.remaining >= 0, "Die Restzahl ist nie negativ")
expect(progress.remainingProfit >= 0, "Das Restpotenzial ist nie negativ")

-- Warum-Engine
local why = GCP.Guide:Why(GCP.Guide:CurrentStep())
expect(type(why.positive) == "table", "Jeder Schritt kann Gruende nennen")
expect(#why.context > 0, "Jeder Schritt nennt mindestens seinen Kontext")
-- Auch ein reiner Weg muss etwas sagen koennen.
for _, candidate in ipairs(GCP:Profile().guide.steps) do
    local answer = GCP.Guide:Why(candidate)
    expect(#answer.context + #answer.positive + #answer.warnings + #answer.unknown > 0,
        "Zu jedem Schritt der Route gibt es eine Antwort auf \"Warum?\"")
end

-- Reload mitten in der Route: nichts geht verloren.
local doneBefore, skippedBefore = GCP.Guide:DoneCount()
local stepsBefore = GCP.Guide:StepCount()
local indexBefore = GCP:Profile().guide.currentIndex
GCP.Guide:Restore()
local doneAfter, skippedAfter = GCP.Guide:DoneCount()
expectEqual(doneAfter, doneBefore, "Ein Reload verliert keinen erledigten Schritt")
expectEqual(skippedAfter, skippedBefore, "...und keinen uebersprungenen")
expectEqual(GCP.Guide:StepCount(), stepsBefore, "...und keine Schritte")
expectEqual(GCP:Profile().guide.currentIndex, indexBefore, "...und nicht die Position")
expectEqual(GCP.Guide:GetState(), "PAUSED",
    "Nach einem Reload steht die Route pausiert und laeuft nicht heimlich weiter")
GCP.Guide:Resume()

-- Neuplanung verliert keine erledigten Schritte.
local doneBeforeReplan = GCP.Guide:DoneCount()
GCP.Guide.lastReplan = nil
local replanned = GCP.Guide:Replan("market_revision")
local doneAfterReplan = GCP.Guide:DoneCount()
expect(doneAfterReplan >= doneBeforeReplan,
    "Eine Neuplanung verliert keinen erledigten Schritt")

-- Drosselung: zweimal hintereinander gibt es keine zweite Neuplanung.
GCP.Guide.lastReplan = nil
GCP.Guide:RequestReplan("market_revision")
local blocked, blockReason = GCP.Guide:RequestReplan("market_revision")
expect(not blocked, "Zwei Neuplanungen direkt hintereinander werden gedrosselt")
expectEqual(blockReason, "gedrosselt", "...mit benanntem Grund")

-- Obergrenze je Sitzung
GCP:Profile().guide.replans = 999
GCP.Guide.lastReplan = nil
local capped, cappedReason = GCP.Guide:RequestReplan("market_revision")
expect(not capped, "Die Zahl der Neuplanungen ist gedeckelt")
expect(cappedReason:find("grenze") ~= nil, "...und der Deckel wird benannt")
GCP:Profile().guide.replans = 0

-- Abbrechen
expect(GCP.Guide:Abort(), "Die Route laesst sich abbrechen")
expectEqual(GCP.Guide:GetState(), "IDLE", "...danach ist der Guide wieder untaetig")
expectEqual(GCP.Guide:StepCount(), 0, "...und hat keine Schritte mehr")

-- Vollstaendiger Durchlauf bis COMPLETED
GCP.Capital:Invalidate()
GCP.Guide:Start({ profile = "CUSTOM", minutes = 120 })
local guard = 0
while GCP.Guide:GetState() ~= "COMPLETED" and guard < 100 do
    local current = GCP.Guide:CurrentStep()
    if not current then break end
    GCP.Guide:Complete(current.id, false)
    guard = guard + 1
end
expectEqual(GCP.Guide:GetState(), "COMPLETED", "Eine abgearbeitete Route gilt als fertig")
expect(GCP.Guide:HeaderText():find("abgeschlossen", 1, true) ~= nil,
    "...und sagt das in Worten")
local finalProgress = GCP.Guide:Progress()
expectEqual(finalProgress.remaining, 0, "Am Ende ist nichts mehr offen")
expectEqual(finalProgress.remainingProfit, 0, "...und kein Restpotenzial mehr da")

-- Interrupts
GCP.Guide:Abort()
GCP.Capital:Invalidate()
GCP.Guide:Start({ profile = "CRAFTING", minutes = 60 })
GCP.Guide.lastInterruptAt = nil
local interrupt = GCP.Guide:CheckInterrupt()
if interrupt then
    expect(interrupt.opportunity ~= nil, "Ein Interrupt nennt die Chance")
    expect(type(interrupt.text) == "string", "...und beschreibt sie")
    local stepsBeforeInsert = GCP.Guide:StepCount()
    expect(GCP.Guide:AcceptInterrupt(), "Ein Interrupt laesst sich einfuegen")
    expect(GCP.Guide:StepCount() > stepsBeforeInsert, "...und verlaengert die Route")
end
GCP.Guide.interrupt = { opportunity = {}, text = "x" }
expect(GCP.Guide:DismissInterrupt(), "Ein Interrupt laesst sich ignorieren")
expectEqual(GCP.Guide.interrupt, nil, "...und ist danach weg")
expectEqual(GCP.db.options.guideAutoInsert, false,
    "Automatisches Einfuegen ist voreingestellt aus")
GCP.Guide:Abort()


-- ===========================================================================
-- FARM BRAIN
-- ===========================================================================

H.section("Farm")

expectEqual(GCP.Farm:SessionCount(), 0, "Beim ersten Start gibt es keine Farmhistorie")
expectEqual(GCP.Farm:GetRate("Nagrand"), nil,
    "Ohne Sitzungen gibt es keine Farmrate - auch keine Null")
expect(GCP.Farm:SummaryText():find("Noch keine Farmhistorie", 1, true) ~= nil,
    "...und die Oberflaeche sagt genau das")
expectEqual(#GCP.Farm:BuildOpportunities(60), 0,
    "Ohne gemessene Rate entsteht kein Farmblock")
expectEqual(GCP.Knowledge:CountFarmRoutes(), 0,
    "Es gibt bewusst keine erfundenen Farmrouten")

-- Eine Sitzung: Start, Ausbeute, Ende.
H.clearBags()
H.zoneName = "Nagrand"
local session = GCP.Farm:Start({ 23425 }, "Nagrand")
expect(session ~= nil, "Eine Farmsitzung laesst sich starten")
expectEqual(GCP.Farm:Current().zone, "Nagrand", "...mit Zone")
expectEqual(GCP.Farm:Status().totalItems, 0, "Am Anfang ist die Ausbeute null")

-- Die Ausbeute kommt nach und nach, wie im Spiel: 5 Stueck alle 5 Minuten.
H.farmRun(GCP, 1800, { chunk = 300, itemID = 23425, perChunk = 5 })
local status = GCP.Farm:Status()
expectEqual(status.totalItems, 30, "Die Ausbeute wird aus dem Bestandszuwachs gemessen")
expect(status.estimatedValue > 0, "...und mit Marktpreisen bewertet")
expect(status.activeMinutes >= 29, "Die aktive Zeit laeuft mit")
expect(status.itemsPerHour ~= nil, "Ab der Mindestdauer gibt es eine Rate")
expectNear(status.itemsPerHour, 60, 3, "30 Stueck in 30 Minuten sind 60 Stueck/h")

local finished, reason, stored = GCP.Farm:Stop("Test")
expect(stored, "Die Sitzung wird aufgeschrieben")
expectEqual(GCP.Farm:SessionCount(), 1, "...als genau eine Sitzung")
expectEqual(GCP.Farm:Current(), nil, "...und laeuft danach nicht weiter")

-- Eine zu kurze Sitzung ist keine Messung.
GCP.Farm:Start({ 23425 }, "Nagrand")
H.farmRun(GCP, 60, { chunk = 30, itemID = 23425, perChunk = 2 })
local _, _, tooShort = GCP.Farm:Stop("kurz")
expect(not tooShort, "Eine Sitzung unter der Mindestdauer wird nicht gewertet")
expectEqual(GCP.Farm:SessionCount(), 1, "...und aendert die Historie nicht")

-- Eine Sitzung ohne Ausbeute ebenfalls nicht.
GCP.Farm:Start({ 22785 }, "Zangarmarschen")
H.farmRun(GCP, 1800, { chunk = 300 })
expectEqual(GCP.Farm:Current(), nil,
    "Eine Sitzung ohne Ausbeute beendet sich nach der Leerlaufgrenze von selbst")
expectEqual(GCP.Farm:SessionCount(), 1, "...und wird nicht gewertet")

-- Mehrere Sitzungen ergeben einen Median.
for round = 1, 4 do
    GCP.Farm:Start({ 23425 }, "Nagrand")
    H.farmRun(GCP, 1800, { chunk = 300, itemID = 23425, perChunk = 4 + round })
    GCP.Farm:Stop("Test")
end
local rate = GCP.Farm:GetRate("Nagrand")
expect(rate ~= nil, "Nach mehreren Sitzungen gibt es eine Rate")
expectEqual(rate.sessions, 5, "...aus allen gewerteten Sitzungen")
expect(rate.medianItemsPerHour > 0, "...mit einem Median")
expect(rate.medianGoldPerHour > 0, "...auch in Gold")
expectEqual(rate.confidence, "medium", "Fuenf Sitzungen ergeben mittlere Sicherheit")
expectEqual(GCP.Farm:GetRate("Nagrand", 23425).itemID, 23425,
    "Die Rate laesst sich auf ein Item einschraenken")
expectEqual(GCP.Farm:GetRate("Nethersturm"), nil,
    "Eine Zone ohne eigene Sitzungen hat keine Rate")

-- Adaptives Farmen: aktuelle Rate gegen den eigenen Median.
GCP.Farm:Start({ 23425 }, "Nagrand")
H.farmRun(GCP, 900, { chunk = 300, itemID = 23425, perChunk = 1 })
local assessment = GCP.Farm:Assess()
expect(assessment ~= nil, "Waehrend einer Sitzung gibt es eine Einschaetzung")
expect(assessment.below, "Eine deutlich schlechtere Rate wird als solche erkannt")
expect(assessment.text:find("unter deinem", 1, true) ~= nil,
    "...und in Worten gesagt")
GCP.Farm:Stop("Test")

-- Farmbloecke fuer die Route
local blocks = GCP.Farm:BuildOpportunities(60)
expect(#blocks > 0, "Mit gemessener Rate entstehen Farmbloecke")
local block = blocks[1]
expectEqual(block.type, "farm", "...vom Typ farm")
expectEqual(block.cost, 0, "...ohne Kapitalbedarf")
expect(block.quantity >= 1, "...mit einer erwarteten Stueckzahl")
expect(block.execution ~= nil, "...und einem Bauplan")
expectEqual(block.execution.method, "farm", "...der als Farmblock markiert ist")
expect(table.concat(block.explanation, " "):find("erfindet keine Gold/h", 1, true) ~= nil,
    "Die Erklaerung sagt ausdruecklich, woher die Rate stammt")

-- Der Farmblock landet in einer Farmroute.
GCP.Capital:Invalidate()
local farmRoute = GCP.Route:Plan({ profile = "FARMING", minutes = 60 })
local farmSteps = 0
for _, step in ipairs(farmRoute.steps) do
    if step.type == "FARM" then farmSteps = farmSteps + 1 end
end
expect(farmSteps > 0, "Das Farmprofil erzeugt Farmschritte")
expectEqual(farmRoute.totals.capital, 0, "Ein Farmblock bindet kein Kapital")

-- ===========================================================================
-- PERSONAL BRAIN
-- ===========================================================================

H.section("Personal")

expect(type(GCP.Personal.GetStats) == "function", "Der Personal Brain ist ansprechbar")
expect(GCP.Personal:SummaryText() ~= nil, "...und hat immer einen Satz parat")
expectEqual(GCP.Personal:ExpectedValueText("craft"), nil,
    "Ohne genuegend Ergebnisse gibt es keine persoenliche Aussage")

-- Ergebnisse aus dem Chancen-Protokoll uebernehmen.
local history = GCP.Opportunity:EnsureHistory()
-- 45 abgeschlossene Faelle: genug fuer die Kalibrierung, die unter 40
-- Gesamtergebnissen bewusst gar nicht erst anlaeuft.
for index = 1, 45 do
    history[#history + 1] = {
        timestamp = H.now - index * 3600,
        type = "craft", itemID = 23571,
        expectedProfit = 100000, expectedROI = 0.3,
        opportunityScore = 80, confidence = "high",
        marketScore = 75, liquidityScore = 70,
        executedAt = H.now - index * 3600, entryPrice = 100000, entryQuantity = 1,
        soldAt = H.now - index * 1800, exitPrice = 140000,
        realizedProfit = index <= 36 and 40000 or -10000,
        realizedROI = index <= 36 and 0.4 or -0.1,
        holdingHours = 4,
        outcome = index <= 36 and "WIN" or "LOSS",
    }
end
local counted = GCP.Personal:SyncOutcomes()
expectEqual(counted, 45, "Alle abgeschlossenen Ergebnisse werden uebernommen")
expectEqual(GCP.Personal:SyncOutcomes(), 0,
    "Ein zweiter Durchlauf zaehlt nichts doppelt")

local craftStats = GCP.Personal:GetStats("craft")
expect(craftStats ~= nil, "Es gibt eine Statistik je Chancenart")
expectEqual(craftStats.wins, 36, "...mit den Gewinnen")
expectEqual(craftStats.losses, 9, "...und den Verlusten")
expectNear(craftStats.hitRate, 0.8, 0.001, "...und der Trefferquote")
expect(not craftStats.lowSample, "45 Faelle sind keine duenne Stichprobe mehr")
local text = GCP.Personal:ExpectedValueText("craft")
expect(text ~= nil, "Ab der Mindeststichprobe gibt es eine persoenliche Aussage")
expect(text:find("Du erreichst", 1, true) ~= nil, "...und zwar in der zweiten Person")
expect(text:find("n=", 1, true) ~= nil, "...mit Stichprobengroesse")

-- Uebersprungene Aktivitaeten
for index = 1, 8 do
    GCP.Personal:RecordSkip({ opportunityType = "disenchant" })
end
GCP.Personal:RecordStep({}, { type = "disenchant" }, 2)
local skipped = GCP.Personal:SkippedActivities()
local sawDisenchant = false
for _, entry in ipairs(skipped) do
    if entry.type == "disenchant" then sawDisenchant = true end
end
expect(sawDisenchant, "Haeufig uebersprungene Aktivitaeten fallen auf")
expect(GCP.Personal:HasData(), "Danach gibt es persoenliche Daten")

-- ===========================================================================
-- ANALYTICS
-- ===========================================================================

H.section("Analytics")

local analytics = GCP.Analytics:GetReport(true)
expectEqual(analytics.total.n, 45, "Die Auswertung zaehlt alle abgeschlossenen Faelle")
expectNear(analytics.total.hitRate, 0.8, 0.001, "...mit der Gesamttrefferquote")
expect(analytics.byType.craft ~= nil, "...aufgeschluesselt nach Chancenart")
expectEqual(analytics.byType.craft.n, 45, "...mit Stichprobengroesse")
expect(analytics.byScoreBand["70–84"] ~= nil, "...und nach Score-Band")
expect(analytics.byMarketBand ~= nil, "Der Market Score wird eigens ausgewertet")
expect(analytics.byLiquidityBand ~= nil, "Die Liquiditaet ebenfalls")

-- Kleine Stichproben werden markiert.
history[#history + 1] = {
    timestamp = H.now - 100, type = "resale", itemID = 21877,
    expectedProfit = 5000, opportunityScore = 90, confidence = "high",
    executedAt = H.now - 100, entryPrice = 5000, entryQuantity = 1,
    realizedProfit = 2000, outcome = "WIN",
}
analytics = GCP.Analytics:GetReport(true)
expect(analytics.byType.resale.lowSample,
    "Eine Chancenart mit einem einzigen Fall wird als duenne Stichprobe markiert")
local lines = table.concat(GCP.Analytics:Lines(), "\n")
expect(lines:find("LOW SAMPLE", 1, true) ~= nil,
    "...und die Ausgabe sagt LOW SAMPLE")
expect(lines:find("n=", 1, true) ~= nil, "Jede Zeile nennt die Stichprobengroesse")

-- Offene Empfehlungen zaehlen nicht als Ergebnis.
history[#history + 1] = {
    timestamp = H.now - 50, type = "craft", itemID = 23571,
    expectedProfit = 1000, opportunityScore = 70, confidence = "high",
    executedAt = H.now - 50, entryPrice = 1000, entryQuantity = 1,
    outcome = "OPEN",
}
analytics = GCP.Analytics:GetReport(true)
expectEqual(analytics.byType.craft.n, 45,
    "Eine offene Empfehlung veraendert keine Trefferquote")
expect(analytics.open >= 1, "...wird aber als offen gezaehlt")

-- ===========================================================================
-- KALIBRIERUNG
-- ===========================================================================

H.section("Kalibrierung")

expect(not GCP.Calibration:IsEnabled(), "Die Kalibrierung ist voreingestellt aus")
expectEqual(GCP.Calibration:FactorFor("craft"), 1,
    "Abgeschaltet ist jeder Faktor exakt 1")
expectEqual(GCP.Calibration:ModelLabel(), "STANDARD", "...und das Modell heisst STANDARD")

local okUpdate, updateReason = GCP.Calibration:Update()
expect(not okUpdate, "Abgeschaltet wird nicht kalibriert")
expectEqual(updateReason, "abgeschaltet", "...mit benanntem Grund")

GCP.Calibration:SetEnabled(true)
local okUpdate2, changed = GCP.Calibration:Update()
expect(okUpdate2, "Mit genug Ergebnissen laesst sich kalibrieren")
local craftFactor = GCP.Calibration:FactorFor("craft")
expectRange(craftFactor, 0.75, 1.25, "Jeder Faktor bleibt in den harten Grenzen")
expect(math.abs(craftFactor - 1) <= 0.05 + 1e-9,
    "Ein Durchlauf bewegt einen Faktor hoechstens um den Maximalschritt")
expectEqual(GCP.Calibration:FactorFor("resale"), 1,
    "Eine Chancenart unter der Mindeststichprobe wird nicht angefasst")

-- Wiederholte Durchlaeufe naehern sich an, springen aber nie.
local previous = craftFactor
for _ = 1, 5 do
    GCP.Calibration:Update()
    local current = GCP.Calibration:FactorFor("craft")
    expect(math.abs(current - previous) <= 0.05 + 1e-9,
        "Auch weitere Durchlaeufe bewegen den Faktor nur in kleinen Schritten")
    expectRange(current, 0.75, 1.25, "...und bleiben in den Grenzen")
    previous = current
end

expect(GCP.Calibration:ModelLabel():find("PERSÖNLICH", 1, true) ~= nil,
    "Nach der Kalibrierung heisst das Modell persoenlich kalibriert")
local calibrationLines = table.concat(GCP.Calibration:Lines(), "\n")
expect(calibrationLines:find("Grenzen", 1, true) ~= nil,
    "Die Ausgabe nennt die harten Grenzen")

-- Die Kalibrierung veraendert Scores, aber sie sprengt keine Grenzen.
GCP.Opportunity:Invalidate()
local calibrated = GCP.Opportunity:BuildReport(true)
for _, opportunity in ipairs(calibrated.opportunities) do
    expectRange(opportunity.opportunityScore, 0, 100,
        "Auch kalibriert bleibt jeder Score zwischen 0 und 100")
end

-- Zuruecksetzen
expect(GCP.Calibration:Reset(), "Die Kalibrierung laesst sich zuruecksetzen")
expectEqual(GCP.Calibration:FactorFor("craft"), 1, "...danach gilt wieder der Standard")
expectEqual(GCP.Calibration:ModelLabel(), "STANDARD", "...und das Modell heisst STANDARD")

-- Zu wenig Daten: keine Kalibrierung.
GCP.Calibration:SetEnabled(true)
for index = #history, 1, -1 do history[index] = nil end
GCP.Analytics:Invalidate()
local okThin, thinReason = GCP.Calibration:Update()
expect(not okThin, "Ohne Ergebnisse wird nicht kalibriert")
expect(thinReason:find("zu wenige", 1, true) ~= nil, "...und der Grund wird benannt")
GCP.Calibration:SetEnabled(false)


-- ===========================================================================
-- MARKTTIEFE
-- ===========================================================================

H.section("Markttiefe")

expectEqual(GCP.Market:GetDepth(21884), nil,
    "Ohne eigene Suche gibt es keine Angebotsdaten - auch keine Null")
expect(GCP.Market:DescribeDepth(nil):find("Keine Angebotsdaten", 1, true) ~= nil,
    "...und die Oberflaeche sagt genau das")

local computed = GCP.Market:ComputeDepth({
    { count = 5, buyoutTotal = 50000, owner = "A" },
    { count = 10, buyoutTotal = 110000, owner = "B" },
    { count = 20, buyoutTotal = 240000, owner = "B" },
    { count = 3, buyoutTotal = nil, owner = "C" },     -- nur Gebot, kein Sofortkauf
})
expectEqual(computed.listingCount, 4, "Alle Angebote werden gezaehlt")
expectEqual(computed.availableQuantity, 38, "Die Gesamtmenge zaehlt auch Gebotsauktionen")
expectEqual(computed.buyoutQuantity, 35, "Die Sofortkaufmenge zaehlt sie nicht")
expectEqual(computed.lowestUnitPrice, 10000, "Der guenstigste Stueckpreis wird erkannt")
expectEqual(#computed.priceLevels, 3, "Gleiche Stueckpreise fallen zu einer Stufe zusammen")
expectEqual(computed.depthNearMarket, 15,
    "Nahe am Marktpreis zaehlt, was hoechstens 10 % ueber dem guenstigsten liegt")
expectEqual(GCP.Market:ComputeDepth({}), nil, "Eine leere Liste ergibt keine Tiefe")

-- Aufzeichnen und wieder auslesen.
expect(GCP.Market:RecordDepth(21884, {
    { count = 5, buyoutTotal = 1050000, owner = "A" },
    { count = 5, buyoutTotal = 1060000, owner = "B" },
}), "Eine Tiefenmessung laesst sich aufzeichnen")
local depth = GCP.Market:GetDepth(21884)
expect(depth ~= nil, "...und wieder auslesen")
expectEqual(depth.availableQuantity, 10, "...mit der gemessenen Menge")
expect(depth.isLowerBound, "...ausdruecklich als Untergrenze markiert")
expect(GCP.Market:DescribeDepth(depth):find("mindestens", 1, true) ~= nil,
    "...und die Beschreibung sagt \"mindestens\"")

-- Drosselung
local again, throttled = GCP.Market:RecordDepth(21884, { { count = 1, buyoutTotal = 200000 } })
expect(not again, "Zwei Messungen kurz hintereinander werden gedrosselt")
expectEqual(throttled, "gedrosselt", "...mit benanntem Grund")

-- Duenner Markt
GCP.Market:RecordDepth(22456, { { count = 2, buyoutTotal = 300000, owner = "A" } },
    H.now + 1000)
local thin = GCP.Market:GetDepth(22456)
local sawThin = false
for _, signal in ipairs(thin.signals) do
    if signal.code == "THIN_MARKET" then sawThin = true end
end
expect(sawThin, "Ein sehr duenner Markt wird als solcher benannt")
expectEqual(thin.supplyState, "thin", "...und als duenn eingestuft")

-- Angebotsschock: erst Historie aufbauen, dann eine Vervielfachung.
for round = 1, 5 do
    GCP.Market:RecordDepth(22457, {
        { count = 10, buyoutTotal = 1000000, owner = "A" .. round },
        { count = 10, buyoutTotal = 1010000, owner = "B" .. round },
    }, H.now + round * 1000)
end
GCP.Market:RecordDepth(22457, {
    { count = 100, buyoutTotal = 9000000, owner = "A" },
    { count = 100, buyoutTotal = 9100000, owner = "B" },
    { count = 100, buyoutTotal = 9200000, owner = "C" },
}, H.now + 20000)
local shock = GCP.Market:GetDepth(22457)
local sawShock = false
for _, signal in ipairs(shock.signals) do
    if signal.code == "SUPPLY_SHOCK" then sawShock = true end
end
expect(sawShock, "Eine Vervielfachung des Angebots faellt auf")
expectEqual(shock.supplyState, "glut", "...und gilt als Ueberversorgung")
local shockText = ""
for _, signal in ipairs(shock.signals) do shockText = shockText .. signal.text end
expect(shockText:find("Manipulation") == nil,
    "Gold Copilot behauptet nie Marktmanipulation")

-- Preismauer
GCP.Market:RecordDepth(22452, {
    { count = 2, buyoutTotal = 180000, owner = "A" },
    { count = 40, buyoutTotal = 3640000, owner = "B" },
    { count = 3, buyoutTotal = 285000, owner = "C" },
    { count = 2, buyoutTotal = 200000, owner = "D" },
}, H.now + 30000)
local wall = GCP.Market:GetDepth(22452)
local sawWall = false
for _, signal in ipairs(wall.signals) do
    if signal.code == "PRICE_WALL" then sawWall = true end
end
expect(sawWall, "Eine Preismauer wird erkannt")

-- Ausreisser nach unten
GCP.Market:RecordDepth(21885, {
    { count = 1, buyoutTotal = 30000, owner = "A" },
    { count = 5, buyoutTotal = 550000, owner = "B" },
    { count = 5, buyoutTotal = 600000, owner = "C" },
}, H.now + 40000)
local outlier = GCP.Market:GetDepth(21885)
local sawOutlier = false
for _, signal in ipairs(outlier.signals) do
    if signal.code == "PRICE_OUTLIER" then sawOutlier = true end
end
expect(sawOutlier, "Ein einzelnes Angebot weit unter dem Rest faellt auf")

-- Konzentration auf eine Quelle
GCP.Market:RecordDepth(22451, {
    { count = 5, buyoutTotal = 600000, owner = "Einer" },
    { count = 5, buyoutTotal = 610000, owner = "Einer" },
    { count = 5, buyoutTotal = 620000, owner = "Einer" },
    { count = 5, buyoutTotal = 630000, owner = "Einer" },
    { count = 5, buyoutTotal = 640000, owner = "Anderer" },
}, H.now + 50000)
local concentrated = GCP.Market:GetDepth(22451)
local sawConcentration = false
local concentrationText = ""
for _, signal in ipairs(concentrated.signals) do
    if signal.code == "UNUSUAL_LISTING_CONCENTRATION" then
        sawConcentration = true
        concentrationText = signal.text
    end
end
expect(sawConcentration, "Eine ungewoehnliche Angebotskonzentration wird beschrieben")
expect(concentrationText:find("weiß Gold Copilot nicht", 1, true) ~= nil,
    "...ausdruecklich ohne Unterstellung eines Grundes")

-- Die Angebotslage begrenzt die Stueckzahl einer Chance und steht im Tooltip.
GCP.Opportunity:Invalidate()
local supplyReport = GCP.Opportunity:BuildReport(true)
local withDepth = nil
for _, opportunity in ipairs(supplyReport.opportunities) do
    if opportunity.depth then withDepth = opportunity end
end
if withDepth then
    local explanation = table.concat(GCP.Opportunity:Explain(withDepth), "\n")
    expect(explanation:find("ANGEBOTSLAGE", 1, true) ~= nil,
        "Der Tooltip zeigt die Angebotslage, sobald es sie gibt")
    expect(explanation:find("mindestens", 1, true) ~= nil,
        "...und sagt, dass es eine Untergrenze ist")
end

-- Erfassung aus dem Auktionshaus-Browser
H.auctionQuery = 23425
H.auctionListings[23425] = {
    { count = 20, buyoutTotal = 1000000, owner = "Verkäufer1" },
    { count = 20, buyoutTotal = 1020000, owner = "Verkäufer2" },
}
expect(GCP.Market:HasAuctionBrowseAPI(), "Die Browser-API wird erkannt")
local capturedID, capturedList = GCP.Market:ReadAuctionList()
expectEqual(capturedID, 23425, "Die Liste liefert die Item-ID")
expectEqual(#capturedList, 2, "...und alle Zeilen")
H.advance(2000)
expect(GCP.Market:CaptureAuctionList(), "Die Liste wird uebernommen")
expectEqual(GCP.Market:GetDepth(23425).availableQuantity, 40,
    "...mit der gesamten angebotenen Menge")

-- Aufraeumen und Zuruecksetzen
expect(GCP.Market:DepthOverview().items > 0, "Die Diagnose zaehlt die Tiefendaten")
expect(GCP.Market:ResetDepth() > 0, "Die Tiefendaten lassen sich loeschen")
expectEqual(GCP.Market:GetDepth(23425), nil, "...und sind danach weg")
expectEqual(GCP.Market:DepthOverview().items, 0, "...auch in der Diagnose")


-- ===========================================================================
-- DIAGNOSE UND BEFEHLE
-- ===========================================================================

H.section("Diagnose")

local diagnostics = GCP:BuildDiagnostics()
expect(#diagnostics >= 15, "Die Diagnose nennt alle wichtigen Kennzahlen")
local byLabel = {}
for _, entry in ipairs(diagnostics) do byLabel[entry.label] = entry.value end
for _, label in ipairs({ "Version", "DB-Version", "Wissensstand", "Market Items",
    "Markttiefe", "Ledger-Ereignisse", "Chancen", "Positionen", "Route",
    "Gelernte Orte", "Farmsitzungen", "Modell", "Cache-Revisionen",
    "Auctionator", "Syndicator", "TSM", "TomTom" }) do
    expect(byLabel[label] ~= nil, "Die Diagnose nennt \"" .. label .. "\"")
end
expectEqual(byLabel.Version, GCP.Constants.VERSION, "...mit der richtigen Version")
expectEqual(byLabel.Syndicator, "nicht erkannt",
    "Ein fehlendes optionales Addon wird als fehlend gemeldet, nicht verschwiegen")
expect(byLabel.Auctionator:find("erkannt", 1, true) == 1,
    "Ein vorhandenes wird erkannt")
GCP.Market:TryRegisterAuctionatorCallback()
GCP.Market.overviewCache = nil
local withCallback = {}
for _, entry in ipairs(GCP:BuildDiagnostics()) do withCallback[entry.label] = entry.value end
expectEqual(withCallback.Auctionator, "erkannt (Callback aktiv)",
    "...samt registriertem Datenbank-Callback")

expect(pcall(GCP.PrintDiagnostics, GCP), "Die Diagnose laesst sich ausgeben")

-- Debug ist aus und sagt das auch.
GCP.db.options.debug = false
expect(not GCP:Debug("route"), "Ohne Debugmodus gibt es keine Debugausgabe")
GCP.db.options.debug = true
for topic in pairs(GCP.DEBUG_TOPICS) do
    expect(GCP:Debug(topic), "Debugbereich \"" .. topic .. "\" laesst sich ausgeben")
end
expect(not GCP:Debug("gibtesnicht"), "Ein unbekannter Bereich wird abgelehnt")
GCP.db.options.debug = false

-- Slash-Befehle
local slash = SlashCmdList["GOLDCOPILOT"]
expect(type(slash) == "function", "Der Slash-Befehl ist registriert")
expect(pcall(slash, "ziel 500"), "/gold ziel 500 laeuft")
expectEqual(GCP.db.options.goalAmount, 5000000, "...und setzt das Ziel in Kupfer")
expect(pcall(slash, "zeit 45"), "/gold zeit 45 laeuft")
expectEqual(GCP.db.options.goalMinutes, 45, "...und setzt das Zeitbudget")
expect(pcall(slash, "diagnostics"), "/gold diagnostics laeuft")
expect(pcall(slash, "hilfe"), "/gold hilfe laeuft")
expect(pcall(slash, "debug on"), "/gold debug on laeuft")
expectEqual(GCP.db.options.debug, true, "...und schaltet Debug ein")
expect(pcall(slash, "debug off"), "/gold debug off laeuft")
expectEqual(GCP.db.options.debug, false, "...und wieder aus")
expect(pcall(slash, "farm"), "/gold farm laeuft")
expect(pcall(slash, "route quick_gold"), "/gold route quick_gold laeuft")
expect(pcall(slash, "route unsinn"), "Ein unbekanntes Profil wird abgefangen")


-- ===========================================================================
-- SAVEDVARIABLES: VERSIONIERUNG, KAPPEN, KORRUPTION
-- ===========================================================================

H.section("Speicher")

-- Jeder Speicher traegt eine Formatversion.
local profile = GCP:Profile()
local STORES = {
    { key = "marketHistory", ensure = function() return GCP.Market:EnsureStore() end,
      version = GCP.Constants.MARKET.STORE_VERSION },
    { key = "marketDepth", ensure = function() return GCP.Market:EnsureDepthStore() end,
      version = GCP.Constants.MARKET.DEPTH.STORE_VERSION },
    { key = "ledger", ensure = function() return GCP.Ledger:EnsureStore() end,
      version = GCP.Constants.LEDGER.STORE_VERSION },
    { key = "capital", ensure = function() return GCP.Capital:EnsureStore() end,
      version = GCP.Constants.CAPITAL.STORE_VERSION },
    { key = "farm", ensure = function() return GCP.Farm:EnsureStore() end,
      version = GCP.Constants.FARM.STORE_VERSION },
    { key = "personal", ensure = function() return GCP.Personal:EnsureStore() end,
      version = GCP.Constants.PERSONAL.STORE_VERSION },
    { key = "calibration", ensure = function() return GCP.Calibration:EnsureStore() end,
      version = GCP.Constants.CALIBRATION.STORE_VERSION },
    { key = "guide", ensure = function() return GCP.Guide:EnsureStore() end,
      version = GCP.Constants.GUIDE.STORE_VERSION },
}
for _, entry in ipairs(STORES) do
    local store = entry.ensure()
    expect(store ~= nil, entry.key .. " legt sich an")
    expectEqual(store.version, entry.version, entry.key .. " traegt seine Formatversion")
end

-- Eine unbekannte Formatversion wird verworfen - und nur sie.
for _, entry in ipairs(STORES) do
    GCP:Profile()[entry.key] = { version = 9999, kaputt = true }
    local store = entry.ensure()
    expectEqual(store.version, entry.version,
        entry.key .. ": eine unbekannte Formatversion wird ersetzt")
    expectEqual(store.kaputt, nil, "...und der alte Inhalt verworfen")
end

-- Voellig kaputte Daten (falscher Typ) werden ebenfalls aufgefangen.
for _, entry in ipairs(STORES) do
    GCP:Profile()[entry.key] = "das ist keine Tabelle"
    local ok, store = pcall(entry.ensure)
    expect(ok, entry.key .. ": kaputte Daten reissen nichts mit")
    expect(ok and store ~= nil, "...und werden durch einen frischen Speicher ersetzt")
end

-- Auch halb kaputte Strukturen: Die Felder werden einzeln geprueft.
GCP:Profile().ledger = { version = GCP.Constants.LEDGER.STORE_VERSION,
    epoch = H.now, events = {}, items = {}, open = "kaputt", names = 5, mail = false }
local repaired = GCP.Ledger:EnsureStore()
expect(type(repaired.open) == "table", "Ein kaputtes Feld wird durch ein leeres ersetzt")
expect(type(repaired.names) == "table", "...auch der Namensindex")
expect(type(repaired.mail) == "table", "...und der Briefkastenabgleich")

GCP:Profile().guide = { version = GCP.Constants.GUIDE.STORE_VERSION,
    steps = "kaputt", progress = 7, state = "GIBTESNICHT", currentIndex = -5 }
local guideStore = GCP.Guide:EnsureStore()
expect(type(guideStore.steps) == "table", "Kaputte Schritte werden geleert")
expect(type(guideStore.progress) == "table", "...und der Fortschritt auch")
expectEqual(guideStore.state, "IDLE", "Ein unbekannter Zustand faellt auf IDLE zurueck")
expectEqual(guideStore.currentIndex, 1, "Ein unsinniger Index wird korrigiert")

-- Kappen: Die Farmhistorie waechst nicht unbegrenzt.
GCP.Farm:Reset()
local farmStore = GCP.Farm:EnsureStore()
for index = 1, GCP.Constants.FARM.MAX_SESSIONS + 20 do
    farmStore.sessions[#farmStore.sessions + 1] =
        { z = "Test", s = H.now, e = H.now, m = 10, y = { [23425] = 5 }, g = 1000 }
end
GCP.Farm:Start({ 23425 }, "Test")
H.farmRun(GCP, 600, { chunk = 300, itemID = 23425, perChunk = 5 })
GCP.Farm:Stop("Test")
expect(#farmStore.sessions <= GCP.Constants.FARM.MAX_SESSIONS,
    "Die Farmhistorie ist hart gedeckelt")

-- Kappen: Positions-Provenance
local capitalStore = GCP.Capital:EnsureStore()
for index = 1, GCP.Constants.CAPITAL.MAX_POSITION_META + 50 do
    GCP.Capital:RememberPositionMeta(100000 + index, { opportunityType = "craft" })
end
local metaCount = 0
for _ in pairs(capitalStore.meta) do metaCount = metaCount + 1 end
expect(metaCount <= GCP.Constants.CAPITAL.MAX_POSITION_META,
    "Die Positions-Provenance ist hart gedeckelt")

-- Kappen: gelernte Orte je Art
for index = 1, GCP.Constants.NAVIGATION.MAX_PER_KIND + 10 do
    H.position = { x = (index % 90) / 100 + 0.05, y = (index % 70) / 100 + 0.05 }
    GCP.Navigation:Learn("VENDOR", nil)
end
expect(GCP.Navigation:KnownCount("VENDOR") <= GCP.Constants.NAVIGATION.MAX_PER_KIND,
    "Die gelernten Orte sind je Art gedeckelt")

-- Retention: alte Tiefendaten fallen heraus.
GCP.Market:ResetDepth()
GCP.Market:RecordDepth(23425, { { count = 5, buyoutTotal = 250000 } },
    H.now - 30 * 86400)
expect(GCP.Market:GetDepth(23425) ~= nil, "Eine frisch geschriebene Messung ist da")
GCP.Market:PruneDepth(H.now)
expectEqual(GCP.Market:GetDepth(23425), nil,
    "Eine Messung jenseits der Aufbewahrungsfrist wird aufgeraeumt")

-- Ein Profil ohne Datenbank stuerzt nicht ab.
local savedDB = GoldCopilotDB
GoldCopilotDB = nil
GCP.profileCache = nil
expect(type(GCP:Profile()) == "table", "Ohne Datenbank gibt es eine leere Ersatztabelle")
GoldCopilotDB = savedDB
GCP.profileCache = nil
GCP:EnsureDB()

H.report("engine.lua")
