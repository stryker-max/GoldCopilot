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

H.report("engine.lua")
