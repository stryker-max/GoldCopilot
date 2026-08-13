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
-- PRUEFUNG DER WISSENSBASIS
-- ===========================================================================

H.section("Wissensbasis")

local knowledgeProblems = GCP.Knowledge:Validate()
if #knowledgeProblems > 0 then
    for _, entry in ipairs(knowledgeProblems) do
        print(string.format("  Wissensproblem: %s %s - %s",
            entry.kind, entry.id, entry.problem))
    end
end
expectEqual(#knowledgeProblems, 0,
    "Die ausgelieferte Wissensbasis enthaelt keinen Widerspruch")
expectEqual(GCP.Knowledge:RejectedCount(), 0,
    "...und kein Eintrag wurde beim Laden verworfen")

local summary = GCP.Knowledge:Summary()
expect(summary.phases > 0, "Es gibt Phasen")
expect(summary.catalysts > 0, "...Catalysts")
expect(summary.edges > 0, "...Rezeptkanten")
expect(summary.items > 0, "...und Items")
expectEqual(summary.problems, 0, "Die Zusammenfassung meldet keine Probleme")

-- Jeder Catalyst traegt Provenance und Begruendung.
for _, catalyst in ipairs(GCP.Knowledge.catalysts) do
    expect(GCP.Knowledge.SOURCE_RANK[catalyst.sourceConfidence] ~= nil,
        "Catalyst " .. catalyst.id .. " hat eine Provenance")
    expect(type(catalyst.sourceName) == "string" and catalyst.sourceName ~= "",
        "Catalyst " .. catalyst.id .. " nennt seine Quelle")
    expect(type(catalyst.reason) == "string" and catalyst.reason ~= "",
        "Catalyst " .. catalyst.id .. " nennt seinen Grund")
    expectRange(catalyst.strength, 0.0001, 1,
        "Catalyst " .. catalyst.id .. " hat eine Staerke in 0..1")
end

-- Ein exakter Termin nur mit offizieller Quelle.
for _, phase in ipairs(GCP.Knowledge:GetPhases()) do
    if phase.release ~= nil then
        expectEqual(phase.sourceConfidence, "official",
            "Phase " .. phase.id .. ": ein Termin steht nur mit offizieller Quelle")
        expect(type(phase.sourceName) == "string" and phase.sourceName ~= "",
            "...und mit benannter Quelle")
    end
end

-- Die Pruefung findet eingebaute Fehler auch wirklich.
local injected = {
    id = "test-kaputt", itemID = 999999, type = "NEW_RAID", direction = "demand_up",
    strength = 0.5, confidence = "high", sourceConfidence = "official",
    sourceName = "Test", reason = "Testfall", phase = nil,
}
GCP.Knowledge.catalysts[#GCP.Knowledge.catalysts + 1] = injected
GCP.Knowledge.validationCache = nil
local injectedProblems = GCP.Knowledge:Validate()
local foundInjected = false
for _, entry in ipairs(injectedProblems) do
    if entry.id == "test-kaputt" then foundInjected = true end
end
expect(foundInjected, "Ein Catalyst auf ein unbekanntes Item faellt der Pruefung auf")
GCP.Knowledge.catalysts[#GCP.Knowledge.catalysts] = nil
GCP.Knowledge.validationCache = nil
expectEqual(#GCP.Knowledge:Validate(), 0, "...und nach dem Entfernen ist wieder alles sauber")

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

-- ===========================================================================
-- PREIS-PLAUSIBILITAET UND BESCHAFFBARKEIT
--
-- Die Rechnung kann stimmen und die Empfehlung trotzdem unbrauchbar sein. Zwei
-- getrennte Fragen, deshalb zwei getrennte Pruefungen:
--   1. Traegt der Verkaufspreis, aus dem die Marge gerechnet ist?
--   2. Laesst sich die Kaufseite ueberhaupt besorgen?
-- ===========================================================================

-- Eigener Block: Lua erlaubt 200 lokale Variablen je Chunk, und diese Datei
-- liegt nah daran. Was hier entsteht, wird hier auch wieder freigegeben.
do

H.section("Preis-Plausibilitaet")

local G = 10000     -- Kupfer je Gold

-- Der gemeldete Fall: eine einzelne Fantasie-Auktion auf Ruestung. Item 888 ist
-- die gebundene Testschulter (classID 4), hier nur als Ruestung interessant.
local BOOTS = 888
expectEqual((GCP.Prices:AssessSalePrice(BOOTS, 99 * G, 0.09 * G)), false,
    "99 g auf ein Ruestungsteil mit 50 s Haendlerwert ist kein Marktpreis")

-- Welcher Anker greift, haengt von den Zahlen ab, und die Begruendung muss den
-- richtigen nennen. Bei 99 g aus 0,09 g Material ist es der Materialeinsatz:
-- 50 s Haendlerwert mal 200 sind 100 g und damit noch nicht ueberschritten.
local _, whyMaterial = GCP.Prices:AssessSalePrice(BOOTS, 99 * G, 0.09 * G)
expect(type(whyMaterial) == "string" and whyMaterial:find("Material") ~= nil,
    "...und nennt den Materialeinsatz als den Anker, an dem es scheitert")

-- Ohne Materialangabe traegt allein der Haendlerwert - dann muss er auch
-- greifen, und zwar erst jenseits des Zweihundertfachen.
expectEqual((GCP.Prices:AssessSalePrice(BOOTS, 150 * G)), false,
    "150 g auf ein Ruestungsteil mit 50 s Haendlerwert ist das Dreihundertfache")
local _, whyVendor = GCP.Prices:AssessSalePrice(BOOTS, 150 * G)
expect(type(whyVendor) == "string" and whyVendor:find("Händler") ~= nil,
    "...und hier nennt die Begruendung den Haendlerwert")
expectEqual((GCP.Prices:AssessSalePrice(BOOTS, 90 * G)), true,
    "90 g bleiben unter dem Zweihundertfachen und damit unbeanstandet")

-- Rohstoffe: Der Haendlerpreis ist dort kein Anker, sondern Zufall.
-- Adamantiterz bringt 25 Kupfer beim Haendler - Faktor 4000 waere der
-- Normalfall und darf nichts ausloesen.
expectEqual((GCP.Prices:AssessSalePrice(23425, 100 * G)), true,
    "Adamantiterz zum Viertausendfachen des Haendlerwerts bleibt unbeanstandet")
expectEqual((GCP.Prices:AssessSalePrice(21877, 60 * G)), true,
    "Netherstoff ebenso - Handwerkswaren haben keinen Haendleranker")

-- Kleine Betraege werden gar nicht befragt: Ein Vielfaches ist bei billiger
-- Ware keine Aussage.
expectEqual((GCP.Prices:AssessSalePrice(BOOTS, 4 * G)), true,
    "Unter der Absurditaetsschwelle wird nicht gezweifelt")

-- Der Materialanker gilt fuer jede Chancenart, auch fuer Rohstoffe.
expectEqual((GCP.Prices:AssessSalePrice(23425, 300 * G, 10 * G)), false,
    "Das Dreissigfache des Materialeinsatzes ist ohne Beleg unglaubwuerdig")
expectEqual((GCP.Prices:AssessSalePrice(23425, 200 * G, 10 * G)), true,
    "Das Zwanzigfache bleibt stehen - der Deckel ist grosszuegig gesetzt")

-- Gegenbelege heben jeden Verdacht auf.
H.seedTrade(GCP, BOOTS, { quantity = 1, buyPrice = 10 * G, sellPrice = 99 * G,
    rounds = 1, holdHours = 4 })
GCP.Ledger:Touch()
expectEqual((GCP.Prices:AssessSalePrice(BOOTS, 99 * G, 0.09 * G)), true,
    "Ein eigener bestaetigter Verkauf schlaegt jeden Verdacht - da hat jemand gezahlt")

H.section("Beschaffbarkeit")

-- Die haerteste Aussage zuerst: Beim Aufheben gebundene Gegenstaende kommen nie
-- ins Auktionshaus. Item 60010 hat einen Marktpreis UND bindType 1 - das
-- Vorbild ist die Daemonische Rune, die man farmen muss und nicht kaufen kann.
expectEqual((GCP.Prices:AssessPurchase(60010)), false,
    "Beim Aufheben Gebundenes laesst sich nicht kaufen, egal wie voll das Haus ist")
local _, bindWhy = GCP.Prices:AssessPurchase(60010)
expect(type(bindWhy) == "string" and bindWhy:find("farmen") ~= nil,
    "...und die Begruendung sagt, was statt dessen zu tun waere")
-- Der Preis allein haette nichts gemerkt: Er ist da, die Ware nicht zu haben.
expect(GCP.Prices:GetMarketPrice(60010) ~= nil,
    "Genau das ist die Falle - ein Preis heisst nicht, dass jemand verkauft")

-- Ein Craft, dessen Zutatenliste ein gebundenes Reagenz enthaelt, ist nicht
-- ausfuehrbar, auch wenn es nicht die erste Zutat ist.
expectEqual((GCP.Opportunity:AssessInputs({
    itemID = 23571,
    execution = { inputs = {
        { itemID = 21877, count = 4 },
        { itemID = 60010, count = 1 },
    } },
})), false, "Ein gebundenes Reagenz an zweiter Stelle macht den Craft unausfuehrbar")
expectEqual((GCP.Opportunity:AssessInputs({
    itemID = 23571,
    execution = { inputs = { { itemID = 21877, count = 4 } } },
})), true, "Ein Craft aus handelbaren Zutaten bleibt ausfuehrbar")

-- Das Angebot selbst: Verglichen wird das Scanalter des Items mit dem des
-- Referenzguts. Ohne Referenz gibt es kein Urteil.
H.scanAge = {}
expectEqual((GCP.Prices:GetListingState(23425)), "unknown",
    "Ohne Scandaten wird ueber Angebote nicht geurteilt")
expectEqual((GCP.Prices:AssessPurchase(23425)), true,
    "...und ohne Urteil wird auch nichts abgelehnt")

H.scanAge = { [21877] = 0, [23425] = 0 }
expectEqual((GCP.Prices:GetListingState(23425)), "listed",
    "Frisch gescannt und dabei gesehen heisst: liegt im Haus")

H.scanAge = { [21877] = 0, [23425] = 6 }
expectEqual((GCP.Prices:GetListingState(23425)), "absent",
    "Heute gescannt, das Item aber sechs Tage nicht gesehen: keines im Haus")
expectEqual((GCP.Prices:AssessPurchase(23425)), false,
    "...und was nicht im Haus liegt, kauft auch niemand")

-- Der entscheidende Unterschied: Ein hohes Alter hat zwei Ursachen. Nur der
-- Vergleich trennt "Item fehlt" von "lange nicht gescannt".
H.scanAge = { [21877] = 6, [23425] = 6 }
expectEqual((GCP.Prices:GetListingState(23425)), "listed",
    "Ist der letzte Scan selbst sechs Tage alt, ist das Item nicht auffaellig - "
    .. "dann wurde nur lange nicht gescannt")

H.scanAge = {}

end     -- Ende des eigenen Blocks der Plausibilitaetstests

-- --- Position Sizing -------------------------------------------------------

H.section("Position Sizing")

local WIDE = 1000000000    -- Exposure-Basis so gross, dass sie hier nie bindet
-- Dieser Abschnitt prueft, ob die BEWERTUNGSFAKTOREN die Position bewegen.
-- Dafuer wird jede kappende Grenze abgeschaltet: die Exposure ueber WIDE, der
-- Stueckzahl-Deckel hier. Sonst laegen alle Ergebnisse auf demselben Deckel,
-- und die Vergleiche saehen gruen aus, ohne etwas zu zeigen. Der Deckel selbst
-- wird am Ende des Abschnitts eigens geprueft.
local savedUnitCap = GCP.db.options.maxUnitsPerPosition
GCP.db.options.maxUnitsPerPosition = 0

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

-- --- Stueckzahl-Deckel (1.0.0-beta.3) --------------------------------------
--
-- Kapitalanteil und Exposure begrenzen einen Betrag, keine Menge: Bei einem
-- 2-Gold-Item sind 20 % von 1000 Gold eben 100 Stueck. Ob der Markt 100 Stueck
-- aufnimmt, ist eine voellig andere Frage - und ohne Beleg lautet die Antwort
-- "wahrscheinlich nicht".
GCP.db.options.maxUnitsPerPosition = "auto"

local function sizeCheap(extra)
    local input = {
        unitCost = 20000, investable = 100000000, score = 95, confidence = "high",
        exposureBase = WIDE,
    }
    for key, value in pairs(extra or {}) do input[key] = value end
    return GCP.Capital:SizePosition(input)
end

local unproven = sizeCheap()
expectEqual(unproven.units, 5,
    "Ohne eigene Verkaufsdaten kauft eine Position hoechstens fuenf Stueck")
expectEqual(unproven.limitedBy, "keine Verkaufsdaten",
    "...und sagt auch, woran es liegt")
expectEqual(unproven.capital, 5 * 20000,
    "Der Kapitalbedarf folgt der gedeckelten Stueckzahl, nicht dem Budget")

local proven = sizeCheap({ liquidityConfidence = "high" })
expect(proven.units > unproven.units,
    "Mit belegter Liquiditaet darf eine Position groesser ausfallen")
expectEqual(proven.units, 20, "...aber auch dann nicht beliebig gross")

expectEqual(sizeCheap({ liquidityConfidence = "low" }).units, 5,
    "Eine duenne Liquiditaetsaussage ist kein Beleg")

GCP.db.options.maxUnitsPerPosition = 3
expectEqual(sizeCheap({ liquidityConfidence = "high" }).units, 3,
    "Eine eigene Obergrenze schlaegt den automatischen Deckel")
expectEqual(sizeCheap({ liquidityConfidence = "high" }).limitedBy, "Stückzahl-Limit",
    "...und nennt sich beim Namen")

GCP.db.options.maxUnitsPerPosition = 0
expect(sizeCheap().units > 20, "Abgeschaltet deckelt der Stueckzahlfilter nichts mehr")

-- Der Deckel begrenzt die Menge, nicht das Urteil: Eine teure Chance, deren
-- Budget ohnehin nur fuer wenige Stueck reicht, bleibt unberuehrt.
GCP.db.options.maxUnitsPerPosition = "auto"
local expensive = GCP.Capital:SizePosition({
    unitCost = 2000000, investable = 10000000, score = 95, confidence = "high",
    exposureBase = WIDE,
})
expect(expensive ~= nil and expensive.limitedBy ~= "keine Verkaufsdaten",
    "Wo das Budget schon vorher bindet, meldet sich der Deckel gar nicht erst")

-- --- Eigene Mengenvorgabe (1.0.0-beta.6) -----------------------------------
--
-- Der Deckel ist eine Vorsichtsregel, keine Wahl. Wer fuenf Roben nicht will,
-- soll drei nehmen duerfen - und wer mehr will als der Deckel erlaubt, auch.
GCP.db.options.maxUnitsPerPosition = "auto"

do
local forced = sizeCheap({ forceUnits = 3 })
expectEqual(forced.units, 3, "Eine eigene Vorgabe bestimmt die Stueckzahl")
expectEqual(forced.limitedBy, "deine Vorgabe", "...und sagt, dass sie es war")
expectEqual(forced.capital, 3 * 20000, "Der Kapitalbedarf folgt der Vorgabe")

expectEqual(sizeCheap({ forceUnits = 12 }).units, 12,
    "Eine Vorgabe ueber dem automatischen Deckel gilt ebenfalls - der Deckel "
    .. "ist Vorsicht, keine Vorschrift")

-- ...aber sie hebelt keine harte Grenze aus. Was das Gold nicht hergibt, laesst
-- sich auch auf Wunsch nicht kaufen.
local tooExpensive = GCP.Capital:SizePosition({
    unitCost = 2000000, investable = 100000000, score = 95, confidence = "high",
    exposureBase = WIDE, remainingCapital = 5000000, forceUnits = 50,
})
expect(tooExpensive == nil or tooExpensive.units <= 2,
    "Eine Vorgabe kauft nicht mehr, als das freie Kapital hergibt")
if tooExpensive then
    expect(tooExpensive.limitedBy:find("gekürzt", 1, true) ~= nil,
        "...und sagt, dass sie gekuerzt wurde")
end

-- Ebensowenig mehr, als der Markt ueberhaupt anbietet.
expectEqual(sizeCheap({ forceUnits = 30, maxUnits = 4 }).units, 4,
    "Eine Vorgabe kauft nicht mehr, als im Auktionshaus liegt")

expectEqual(sizeCheap({ forceUnits = 0 }).units, 5,
    "Ohne gueltige Vorgabe bleibt es beim Vorschlag des Addons")
end

GCP.db.options.maxUnitsPerPosition = savedUnitCap

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

-- Eine saubere Ausgangslage. Ohne sie prueft dieser Abschnitt nicht den
-- Allocator, sondern die Exposure, die frueherere Abschnitte hinterlassen
-- haben - und die hatte die Marktgruppe "Elementar" laengst ausgeschoepft.
local cleanSnapshot = {
    availableGold = 5000000, investedCapital = 0, reservedGold = 0,
    exposureBase = 5000000, exposure = {},
}
local plan = GCP.Capital:Allocate(pool,
    { capital = 5000000, risk = "medium", snapshot = cleanSnapshot })
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

-- Abhaengigkeiten. Seit 1.1.0-beta.5 steht zwischen Kauf und Herstellung der
-- Postgang: Ersteigertes landet in TBC im Briefkasten, nicht in den Taschen.
-- Der Herstellschritt haengt deshalb nicht mehr an den fuenf Kaeufen, sondern
-- an dem einen Gang, der sie alle abholt - und der wiederum an allen fuenfen.
do
    local craftAction, postAction, collectAction = nil, nil, nil
    for _, action in ipairs(craftPlan.actions) do
        if action.type == "CRAFT" then craftAction = action end
        if action.type == "POST_AUCTION" then postAction = action end
        if action.type == "MAIL_COLLECT" then collectAction = action end
    end
    expect(collectAction ~= nil, "Nach einem Kauf im Auktionshaus steht ein Postgang")
    expectEqual(#collectAction.dependencies, 5, "...und der haengt an allen fuenf Kaeufen")
    expectEqual(collectAction.location.kind, "MAILBOX", "...und fuehrt zum Briefkasten")
    expectEqual(#craftAction.dependencies, 1, "Der Herstellschritt haengt am Postgang")
    expectEqual(craftAction.dependencies[1], collectAction.id, "...und zwar genau daran")
    expectEqual(#postAction.dependencies, 1, "Der Einstellvorgang haengt am Herstellschritt")
    expectEqual(postAction.dependencies[1], craftAction.id, "...und zwar genau daran")
end

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
-- HAENDLERWARE (1.1.0-beta.5)
-- ===========================================================================

H.section("Händlerware")

-- Runenfaden ist der Musterfall: fester Haendlerpreis von 50 Silber, im
-- Auktionshaus regelmaessig teurer.
expectEqual(GCP.Vendors:GetBuyPrice(14341), 5000,
    "Die Wissensbasis kennt den Haendlerpreis von Runenfaden")
expectEqual(select(2, GCP.Vendors:GetBuyPrice(14341)), "Wissensbasis",
    "...und benennt, woher er kommt")
expectEqual(GCP.Vendors:GetBuyPrice(21877), nil,
    "Netherstoff steht bei keinem Haendler und bekommt deshalb keinen Preis")

-- Der Haendlerpreis ist NICHT der Verkaufswert aus GetItemInfo. Die beiden
-- zu verwechseln hiesse, den Einkauf zum Verkaufspreis zu planen.
do
    local acquisition, source = GCP.Prices:GetAcquisitionPrice(14341)
    expectEqual(acquisition, 5000, "Der Beschaffungspreis nimmt den guenstigeren Weg")
    expectEqual(source, "Händler", "...und sagt, welcher das ist")
end

-- Gelernt wird nur, was unbegrenzt verfuegbar ist und mit Gold bezahlt wird.
H.merchant = {
    { itemID = 14341, price = 4500, quantity = 1, numAvailable = -1 },
    { itemID = 2321, price = 400, quantity = 4, numAvailable = -1 },
    { itemID = 4404, price = 3000, quantity = 1, numAvailable = 3 },
    { itemID = 29434, price = 0, quantity = 1, numAvailable = -1, extendedCost = true },
}
expectEqual(GCP.Vendors:ScanMerchant(), 2,
    "Vom Haendlertresen wird nur unbegrenzte Goldware uebernommen")
expectEqual(GCP.Vendors:GetBuyPrice(14341), 4500,
    "Der selbst gesehene Preis schlaegt die Wissensbasis")
expectEqual(select(2, GCP.Vendors:GetBuyPrice(14341)), "gesehen",
    "...und sagt das auch")
expectEqual(GCP.Vendors:GetBuyPrice(2321), 100,
    "Ein Stapelpreis wird auf das einzelne Stueck heruntergerechnet")
expectEqual(GCP.Vendors:GetBuyPrice(4404), nil,
    "Begrenzter Vorrat wird nicht gelernt - darauf darf keine Route bauen")
expectEqual(GCP.Vendors:GetBuyPrice(29434), nil,
    "Was Marken statt Gold kostet, ist kein Haendlerpreis")
H.merchant = {}

-- Und der Kaufschritt fuehrt zum Haendler statt ins Auktionshaus.
do
    local recipe = {
        opportunity = { execution = { method = "craft", profession = "Schneiderei",
            inputs = {
                { itemID = 14341, count = 1, unitPrice = 6800 },   -- Haendler ist billiger
                { itemID = 21877, count = 4, unitPrice = 2000 },   -- gibt es nur im AH
                { itemID = 6260, count = 2, unitPrice = 30 },      -- AH ist billiger
            },
            outputs = { { itemID = 24252, count = 1 } },
            sellItemID = 24252, sellCount = 1, sellUnitPrice = 200000,
        } },
        key = "craft:24252", type = "craft", itemID = 24252, title = "Testrobe",
        units = 1, unitCost = 15000, capital = 15000, expectedProfit = 50000,
        confidence = "medium",
    }
    local plan = GCP.Execution:BuildPlan({ recipe }, { inventory = {} })
    local byItem = {}
    for _, action in ipairs(plan.actions) do
        if action.itemID then byItem[action.itemID] = action end
    end
    expectEqual(byItem[14341].type, "VENDOR_BUY",
        "Runenfaden wird beim Haendler gekauft, nicht im Auktionshaus")
    expectEqual(byItem[14341].location.kind, "VENDOR", "...und der Schritt fuehrt dorthin")
    expectEqual(byItem[14341].capitalRequired, 4500,
        "...und rechnet mit dem gesehenen Haendlerpreis, nicht mit dem Auktionspreis")
    expectEqual(byItem[21877].type, "BUY",
        "Netherstoff bleibt ein Kauf im Auktionshaus")
    expectEqual(byItem[6260].type, "BUY",
        "Auch Haendlerware wird im Haus gekauft, wenn sie dort billiger liegt")
end

-- ===========================================================================
-- GLEICHE KAEUFE SIND EIN KAUF (1.1.0-beta.5)
-- ===========================================================================

H.section("Zusammengefasste Käufe")

do
    local function threadCraft(product, key)
        return {
            opportunity = { execution = { method = "craft", profession = "Schneiderei",
                inputs = {
                    { itemID = 14341, count = 1, unitPrice = 6800 },
                    { itemID = 21877, count = 3, unitPrice = 2000 },
                },
                outputs = { { itemID = product, count = 1 } },
                sellItemID = product, sellCount = 1, sellUnitPrice = 200000,
            } },
            key = key, type = "craft", itemID = product, title = "Test " .. product,
            units = 1, unitCost = 12800, capital = 12800, expectedProfit = 40000,
            confidence = "medium",
        }
    end
    local plan = GCP.Execution:BuildPlan({
        threadCraft(24252, "craft:24252"),
        threadCraft(24253, "craft:24253"),
        threadCraft(24254, "craft:24254"),
    }, { inventory = {} })

    local threadBuys, clothBuys, threadAction, clothAction = 0, 0, nil, nil
    for _, action in ipairs(plan.actions) do
        if action.itemID == 14341 then threadBuys = threadBuys + 1 threadAction = action end
        if action.itemID == 21877 then clothBuys = clothBuys + 1 clothAction = action end
    end
    expectEqual(threadBuys, 1, "Drei Rezepte mit Runenfaden ergeben EINEN Haendlerkauf")
    expectEqual(threadAction.quantity, 3, "...ueber die volle Menge")
    expectEqual(threadAction.capitalRequired, 13500, "...und mit dem vollen Kapital")
    expectEqual(clothBuys, 1, "Dasselbe gilt fuer den Kauf im Auktionshaus")
    expectEqual(clothAction.quantity, 9, "...auch dort ueber die volle Menge")
    expectEqual(#threadAction.groupIDs, 3,
        "Der zusammengefasste Kauf weiss, welchen drei Chancen er dient")

    -- Jede der drei Herstellungen haengt weiterhin an beidem: an dem einen
    -- Haendlerkauf und an dem einen Postgang.
    local crafts = 0
    for _, action in ipairs(plan.actions) do
        if action.type == "CRAFT" then
            crafts = crafts + 1
            expectEqual(#action.dependencies, 2,
                "Jede Herstellung haengt am Haendlerkauf und am Postgang")
        end
    end
    expectEqual(crafts, 3, "Drei Rezepte bleiben drei Herstellungen")

    -- Und die Route daraus laeuft jeden Ort genau einmal an.
    local order = GCP.Route:Order(plan, nil)
    local steps = GCP.Route:InsertTravel(order, nil)
    local visits, last = {}, nil
    for _, step in ipairs(steps) do
        if step.location and step.location.kind ~= "ANYWHERE" then
            if step.location.kind ~= last then
                visits[#visits + 1] = step.location.kind
                last = step.location.kind
            end
        end
    end
    -- Erwartet ist genau ein Durchlauf: einmal einkaufen (Haendler und Haus),
    -- einmal Post holen, alles herstellen, alles einstellen. Fuenf Stationen
    -- fuer drei Rezepte - vor 1.1.0-beta.5 waren es drei volle Runden.
    expectEqual(#visits, 5, "Fuenf Stationen fuer drei Rezepte, nicht drei Runden")
    expectEqual(visits[#visits], "AUCTION_HOUSE", "Am Ende wird eingestellt")
    local seen = {}
    for _, kind in ipairs(visits) do
        seen[kind] = (seen[kind] or 0) + 1
    end
    expectEqual(seen.VENDOR, 1, "Der Haendler wird genau einmal angelaufen")
    expectEqual(seen.MAILBOX, 1, "Der Briefkasten genau einmal")
    expectEqual(seen.PROFESSION, 1, "Die Werkbank genau einmal")
    expectEqual(seen.AUCTION_HOUSE, 2,
        "Das Auktionshaus zweimal - einmal kaufen, einmal einstellen")
end

-- ===========================================================================
-- HERSTELLEN AUS DEM GUIDE (1.1.0-beta.5)
-- ===========================================================================

H.section("Herstellen aus dem Guide")

do
    -- Geschlossenes Berufsfenster: Der Client gibt keine Rezepte heraus, und
    -- der Knopf sagt das, statt einen Listenindex zu raten.
    H.tradeSkills = {}
    H.crafts = {}
    H.crafted = {}
    local ok, why = GCP.Crafts:Make(24252, 1)
    expectEqual(ok, false, "Ohne offenes Berufsfenster wird nichts hergestellt")
    expect(why:find("Berufsfenster") ~= nil, "...und der Grund steht dabei")

    -- Offenes Fenster, Rezept vorhanden.
    H.tradeSkills = {
        { name = "Stoff", header = true },
        { name = "Hexerzwirnrobe", itemID = 24252 },
        { name = "Netherstoffgürtel", itemID = 21874 },
    }
    local index, api = GCP.Crafts:FindOpenRecipe(24252)
    expectEqual(index, 2, "Das Rezept wird ueber den Item-Link gefunden")
    expectEqual(api, "trade", "...ueber die Berufs-API")
    expectEqual(GCP.Crafts:FindOpenRecipe(24252 + 999), nil,
        "Ein Rezept, das nicht in der Liste steht, wird nicht erfunden")

    local made, name = GCP.Crafts:Make(24252, 3)
    expectEqual(made, true, "Mit offener Liste laesst sich herstellen")
    expectEqual(name, "Hexerzwirnrobe", "...und der Knopf nennt das Rezept")
    expectEqual(#H.crafted, 1, "Genau ein Herstellbefehl")
    expectEqual(H.crafted[1].index, 2, "...an der richtigen Listenposition")
    expectEqual(H.crafted[1].count, 3, "...ueber die verlangte Stueckzahl")

    -- Verzauberkunst laeuft ueber die aeltere Craft-API.
    H.tradeSkills = {}
    H.crafts = { { name = "Öl der Sturmböe", itemID = 22521 } }
    H.crafted = {}
    expectEqual(GCP.Crafts:Make(22521, 1), true,
        "Auch die aeltere Craft-API wird bedient")
    expectEqual(H.crafted[1].api, "craft", "...und als solche erkannt")

    H.tradeSkills = {}
    H.crafts = {}
    H.crafted = {}
end

-- ===========================================================================
-- SELBER MACHEN ODER KAUFEN? (1.1.0-beta.5)
-- ===========================================================================

H.section("Beschaffung: selbst herstellen statt kaufen")

do
    local recipesBefore = GCP.db.recipes
    -- Netherstoffballen (21840) aus fuenf Netherstoff (21877). Der Stoff steht
    -- in H.marketPrices bei 6000 Kupfer, fuenf davon sind 30000.
    GCP.db.recipes = {
        ["Schneiderei"] = {
            scannedAt = GCP:Today(),
            list = {
                { name = "Netherstoffballen", product = 21840, numMade = 1,
                  mats = { { 21877, 5 } } },
            },
        },
    }
    GCP.Crafts.revision = (GCP.Crafts.revision or 0) + 1
    GCP.Crafts.costCache = nil

    expectEqual(GCP.Crafts:CraftCost(21840), 30000,
        "Fuenf Netherstoff zu 0,6 g ergeben einen Ballen fuer 3 g")

    -- Teurer im Haus: Der Beschaffungspreis nimmt den Herstellweg.
    H.setPrice(21840, 45000)
    do
        local price, source = GCP.Prices:GetAcquisitionPrice(21840)
        expectEqual(price, 30000, "Ist der Ballen im Haus teurer, zaehlt der Herstellpreis")
        expectEqual(source, "selbst herstellen", "...und die Quelle sagt das auch")
    end

    -- Billiger im Haus: dann wird gekauft. Selbermachen fuer denselben Preis
    -- ist ein Arbeitsschritt ohne Ersparnis.
    H.setPrice(21840, 20000)
    do
        local price, source = GCP.Prices:GetAcquisitionPrice(21840)
        expectEqual(price, 20000, "Ist der Ballen im Haus billiger, zaehlt der Kaufpreis")
        expectEqual(source, "AH", "...und die Quelle ebenfalls")
    end

    -- Und die Route plant den Unter-Craft, statt den Ballen zu kaufen.
    H.setPrice(21840, 45000)
    GCP.Crafts.costCache = nil
    do
        local allocation = {
            opportunity = { execution = { method = "craft", profession = "Schneiderei",
                inputs = { { itemID = 21840, count = 2, unitPrice = 45000 } },
                outputs = { { itemID = 24252, count = 1 } },
                sellItemID = 24252, sellCount = 1, sellUnitPrice = 300000,
            } },
            key = "craft:24252", type = "craft", itemID = 24252, title = "Testrobe",
            units = 1, unitCost = 90000, capital = 90000, expectedProfit = 100000,
            confidence = "medium",
        }
        local plan = GCP.Execution:BuildPlan({ allocation }, { inventory = {} })
        local boughtBolt, craftedBolt, boughtCloth = nil, nil, nil
        for _, action in ipairs(plan.actions) do
            if action.itemID == 21840 and action.type == "BUY" then boughtBolt = action end
            if action.itemID == 21840 and action.type == "CRAFT" then craftedBolt = action end
            if action.itemID == 21877 and action.type == "BUY" then boughtCloth = action end
        end
        expectEqual(boughtBolt, nil, "Der teurere Ballen wird nicht gekauft")
        expect(craftedBolt ~= nil, "...sondern selbst hergestellt")
        expectEqual(craftedBolt and craftedBolt.quantity, 2, "...zweimal")
        expect(boughtCloth ~= nil, "...und dafuer wird der Stoff gekauft")
        expectEqual(boughtCloth and boughtCloth.quantity, 10,
            "...zehn Stoff fuer zwei Ballen")

        -- Der Bestand zaehlt mit: Wer den Stoff schon hat, kauft ihn nicht.
        local stocked = GCP.Execution:BuildPlan({ allocation }, {
            inventory = { [21877] = { itemID = 21877, count = 10 } },
        })
        local stillBuying = false
        for _, action in ipairs(stocked.actions) do
            if action.type == "BUY" and action.itemID == 21877 then stillBuying = true end
        end
        expect(not stillBuying, "Eigener Stoff aus den Taschen wird nicht nachgekauft")
    end

    -- Ein Rezept, das sich selbst als Zutat hat, darf die Rechnung nicht im
    -- Kreis schicken.
    GCP.db.recipes = {
        ["Schneiderei"] = {
            scannedAt = GCP:Today(),
            list = {
                { name = "Kreis A", product = 60001, numMade = 1, mats = { { 60002, 1 } } },
                { name = "Kreis B", product = 60002, numMade = 1, mats = { { 60001, 1 } } },
            },
        },
    }
    GCP.Crafts.revision = (GCP.Crafts.revision or 0) + 1
    GCP.Crafts.costCache = nil
    expectEqual(GCP.Crafts:CraftCost(60001), nil,
        "Zwei Rezepte, die einander herstellen, ergeben keinen Herstellpreis")

    GCP.db.recipes = recipesBefore
    GCP.Crafts.revision = (GCP.Crafts.revision or 0) + 1
    GCP.Crafts.costCache = nil
    H.setPrice(21840, H.marketPrices[21840])
end

-- ===========================================================================
-- ANZEIGE: NAMEN UND ABSCHNITTE (1.1.0-beta.5)
-- ===========================================================================

H.section("Route: Namen und Abschnitte")

do
    -- Ein Rezeptprodukt, das der Client noch nicht kennt, bekommt beim Planen
    -- einen Platzhalter. Er darf nicht fuer immer stehenbleiben: Der Name kommt
    -- Sekunden spaeter nach.
    local unknownID = 999123
    local step = { type = "CRAFT", itemID = unknownID,
        title = "1× Item " .. unknownID .. " herstellen" }
    expectEqual(GCP.Execution:DisplayTitle(step),
        "1× Item " .. unknownID .. " herstellen",
        "Solange der Client das Item nicht kennt, bleibt der Platzhalter")
    H.items[unknownID] = { "Hexerzwirnturban", nil, 2 }
    expectEqual(GCP.Execution:DisplayTitle(step), "1× Hexerzwirnturban herstellen",
        "Sobald der Name da ist, steht er in der Anzeige")
    expectEqual(step.title, "1× Item " .. unknownID .. " herstellen",
        "...ohne den gespeicherten Schritt anzufassen")
    H.items[unknownID] = nil

    -- Ein Titel ohne Platzhalter bleibt unangetastet.
    expectEqual(GCP.Execution:DisplayTitle({ type = "BUY", itemID = 21877,
        title = "8× Netherstoff kaufen" }), "8× Netherstoff kaufen",
        "Ein fertiger Titel wird nicht angefasst")

    -- Abschnitte: Ein Weg gehoert zu dem Abschnitt, in den er FUEHRT.
    local steps = {
        { type = "GO_TO" },
        { type = "VENDOR_BUY" },
        { type = "GO_TO" },
        { type = "BUY" },
        { type = "BUY" },
        { type = "GO_TO" },
        { type = "MAIL_COLLECT" },
        { type = "GO_TO" },
        { type = "CRAFT" },
        { type = "GO_TO" },
        { type = "POST_AUCTION" },
    }
    local keys, counts = GCP.Execution:Sections(steps)
    expectEqual(keys[1], "VENDOR", "Der erste Weg fuehrt zum Haendler")
    expectEqual(keys[3], "BUY", "Der zweite ins Auktionshaus")
    expectEqual(keys[6], "COLLECT", "Der dritte zum Briefkasten")
    expectEqual(keys[8], "CRAFT", "Der vierte zur Werkbank")
    expectEqual(keys[10], "POST", "Der letzte zurueck zum Einstellen")
    expectEqual(counts.BUY, 3, "Der Einkauf zaehlt seinen Weg mit")
    expectEqual(counts.VENDOR, 2, "...der Haendlergang auch")
    expectEqual(GCP.Execution:SectionLabel("COLLECT"),
        "Aus Briefkasten und Bank holen", "Jeder Abschnitt hat eine Ueberschrift")
    expectEqual(GCP.Execution:SectionLabel("UNSINN"), nil,
        "...und eine erfundene Art bekommt keine")
end

-- ===========================================================================
-- VERKAUFEN: WER HAT WAS? (1.1.0-beta.5)
-- ===========================================================================

H.section("Verkaufen nach Charakter")

do
    local savedSyndicator = Syndicator
    Syndicator = {
        API = {
            GetAllCharacters = function()
                return { "Nexarius-Testrealm", "Zweitchar-Testrealm" }
            end,
            GetByCharacterFullName = function(name)
                if name == "Nexarius-Testrealm" then
                    return {
                        bags = { { { itemID = 21877, itemCount = 40 } } },
                        bank = { { { itemID = 23425, itemCount = 10 } } },
                    }
                end
                return { bags = { { { itemID = 21877, itemCount = 5 } } } }
            end,
        },
    }
    H.clearBags()

    local items = GCP.Inventory:ScanAccount()
    expectEqual(items[21877] and items[21877].count, 45,
        "Der Accountbestand zaehlt beide Charaktere zusammen")
    expectEqual(items[21877].owners["Nexarius-Testrealm"], 40,
        "...und weiss, bei wem der groessere Teil liegt")
    expectEqual(items[21877].owners["Zweitchar-Testrealm"], 5,
        "...und bei wem der kleinere")
    expectEqual(items[23425].owners["Nexarius-Testrealm"], 10,
        "Auch die Bank traegt ihren Charakter")

    local report = GCP.Advisor:BuildReport("account", "all", false, "owner")
    expectEqual(report.sort, "owner", "Der Bericht kennt seine Sortierung")
    local cloth = nil
    for _, row in ipairs(report.rows) do
        if row.itemID == 21877 then cloth = row end
    end
    expect(cloth ~= nil, "Der Stoff steht in der Liste")
    expectEqual(cloth and cloth.owner, "Nexarius-Testrealm",
        "Der Charakter mit dem groesseren Stapel ist der Hauptbesitzer")
    expectEqual(cloth and cloth.ownerLabel, "Nexarius",
        "...und in der Anzeige steht er ohne Realm")
    expectEqual(cloth and cloth.ownerCount, 2,
        "...die Zahl der beteiligten Charaktere steht dabei")

    -- Nach Charakter sortiert stehen die Zeilen eines Charakters beieinander.
    local previous = nil
    local ordered = true
    for _, row in ipairs(report.rows) do
        local owner = row.owner or "\255"
        if previous and owner < previous then ordered = false end
        previous = owner
    end
    expect(ordered, "Nach Charakter sortiert stehen die Zeilen gruppiert")

    -- Und die Gruppensumme stimmt mit den Zeilen ueberein.
    local group = report.byOwner["Nexarius-Testrealm"]
    expect(group ~= nil, "Zu jedem Charakter gibt es eine Gruppensumme")
    local sum = 0
    for _, row in ipairs(report.rows) do
        if row.owner == "Nexarius-Testrealm" then sum = sum + row.totalValue end
    end
    expectEqual(group and group.value, sum,
        "...und sie ist die Summe genau seiner Zeilen")

    -- Nach Wert sortiert bleibt es beim alten Verhalten.
    local byValue = GCP.Advisor:BuildReport("account", "all", false, nil)
    expectEqual(byValue.sort, "value", "Ohne Angabe wird nach Wert sortiert")
    local descending = true
    for index = 2, #byValue.rows do
        if byValue.rows[index].totalValue > byValue.rows[index - 1].totalValue then
            descending = false
        end
    end
    expect(descending, "...und zwar absteigend")

    Syndicator = savedSyndicator
end

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

-- ---------------------------------------------------------------------------
-- WAS SCHON IM HAUS LIEGT, IST KEINE NEUE CHANCE (1.1.0-beta.5)
--
-- Bis beta.4 schlug der Planer unmittelbar nach einer abgeschlossenen Route
-- dieselbe Route noch einmal vor. Die Chance war unveraendert gut - nur ist
-- das Kapital jetzt gebunden, und ob die Rechnung aufgeht, weiss erst der
-- Verkauf.
-- ---------------------------------------------------------------------------
do
    local reference = GCP.Route:Plan({ profile = "CUSTOM", minutes = 90 })
    local group = reference.groups and reference.groups[1]
    expect(group ~= nil, "Fuer die Gegenprobe steht eine geplante Chance bereit")
    local saleItemID = group and group.opportunity and group.opportunity.execution
        and group.opportunity.execution.sellItemID
    expect(saleItemID ~= nil, "...und sie hat ein Verkaufsitem")
    if saleItemID then
        H.seedOpenAuction(GCP, saleItemID, 1, 20000)
        GCP.Capital:Invalidate()
        local after = GCP.Route:Plan({ profile = "CUSTOM", minutes = 90 })
        local stillPlanned = false
        for _, candidate in ipairs(after.groups or {}) do
            if candidate.key == group.key then stillPlanned = true end
        end
        expect(not stillPlanned,
            "Eine Chance, deren Ergebnis schon im Auktionshaus liegt, wird zurueckgestellt")
        local named = false
        for _, entry in ipairs(after.waiting or {}) do
            if entry.itemID == saleItemID then named = true end
        end
        expect(named, "...sie steht namentlich in der Warteliste")
        local explained = false
        for _, warning in ipairs(after.warnings or {}) do
            if tostring(warning):find("Ergebnis abwarten", 1, true) then explained = true end
        end
        expect(explained, "...und die Route sagt in Worten, warum sie fehlt")
    end
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

-- STARTORT (1.1.0-beta.5). Der Spieler steht seit der Navigationssektion am
-- gelernten Auktionshaus. Bis beta.4 hat das niemand gefragt: Jede Route -
-- auch jede mitten im Haus neu geplante - begann mit "Gehe zu: Auktionshaus".
do
    local here = GCP.Navigation:CurrentLocation()
    expect(here ~= nil, "Am gelernten Ort weiss die Navigation, wo der Spieler steht")
    expectEqual(here and here.kind, "AUCTION_HOUSE", "...und benennt ihn")

    GCP.Guide:Start({ profile = "CUSTOM", minutes = 90 })
    local first = GCP.Guide:CurrentStep()
    expect(first ~= nil and not (first.type == "GO_TO"
        and first.location and first.location.kind == "AUCTION_HOUSE"),
        "Wer vor dem Auktionshaus steht, bekommt keinen Weg zum Auktionshaus")
    GCP.Guide:Abort()
end

-- Fuer den Rest der Sektion wieder mit unbekanntem Standort planen: Der Weg
-- zum Auktionshaus ist der Schritt, an dem die automatische Ankunftserkennung
-- haengt, und den braucht es hier.
local guidePosition = H.position
H.position = { x = 0.05, y = 0.05 }
expectEqual(GCP.Navigation:CurrentLocation(), nil,
    "Fernab jedes bekannten Ortes behauptet die Navigation keinen Standort")

local started = GCP.Guide:Start({ profile = "CUSTOM", minutes = 90 })
expectEqual(GCP.Guide:GetState(), "ACTIVE", "Nach dem Start laeuft die Route")
expect(GCP.Guide:StepCount() > 0, "...mit Schritten")
local step, index = GCP.Guide:CurrentStep()
expectEqual(index, 1, "Der erste offene Schritt ist Schritt 1")
expectEqual(step.type, "GO_TO", "...und das ist ein Weg")
H.position = guidePosition
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


-- --- Ankunft (1.0.0-beta.4) ------------------------------------------------
--
-- Bis hierher wurde ein Weg nur abgehakt, wenn das Ziel ein Fenster oeffnet.
-- Wer schon am Auktionshaus stand und es nicht noch einmal anklickte, blieb auf
-- "Gehe zu: Auktionshaus" stehen - mit "1 m" daneben im selben Fenster.
do
    local savedPosition = H.position
    -- Weit weg vom gelernten Auktionshaus (0.55/0.68 auf Karte 85).
    H.position = { x = 0.10, y = 0.10 }
    H.mapID = 85

    GCP.Guide:Abort()
    GCP.Guide:Start({ profile = "CUSTOM", minutes = 90 })
    local walkStep = GCP.Guide:CurrentStep()
    expectEqual(walkStep.type, "GO_TO", "Die Route beginnt mit einem Weg")

    expectEqual(GCP.Guide:CheckArrival(), false,
        "Aus der Ferne wird kein Weg abgehakt")
    expectEqual(GCP.Guide:CurrentStep().id, walkStep.id,
        "...und der Schritt bleibt derselbe")

    H.position = { x = 0.5501, y = 0.6801 }     -- direkt am Auktionshaus
    expectEqual(GCP.Guide:CheckArrival(), true,
        "Am Ziel angekommen hakt der Weg sich selbst ab")
    local guideStore = GCP:Profile().guide
    expect(guideStore.progress[walkStep.id].auto,
        "...und zwar als automatisch erkannt, nicht als von Hand bestaetigt")
    expect(GCP.Guide:CurrentStep().id ~= walkStep.id,
        "...danach steht der naechste Schritt an")

    -- Ausdruecklich nur Wege: Vor dem Auktionator zu stehen heisst nicht,
    -- gekauft zu haben.
    expectEqual(GCP.Guide:CurrentStep().type, "BUY", "Der naechste Schritt ist ein Kauf")
    expectEqual(GCP.Guide:CheckArrival(), false,
        "Ein Kauf gilt nicht als erledigt, nur weil man am Ort steht")

    H.position = savedPosition
end

-- --- Vorhaben und Teilschritte (1.0.0-beta.4) ------------------------------
--
-- Die Route buendelt nach Ort, damit man nicht dreimal zum Auktionshaus laeuft.
-- Dadurch liegen die Schritte zweier Crafts zwangslaeufig ineinander - dann
-- muss aber an jedem Schritt stehen, wozu er gehoert.
do
    GCP.Guide:Abort()
    GCP.Guide:Start({ profile = "CUSTOM", minutes = 120 })
    local guideStore = GCP:Profile().guide

    local grouped = nil
    for _, candidate in ipairs(guideStore.steps) do
        if candidate.groupID then grouped = candidate break end
    end
    expect(grouped ~= nil, "Mindestens ein Schritt gehoert zu einem Vorhaben")

    local info = GCP.Guide:GroupInfo(grouped)
    expect(info ~= nil and info.title ~= nil,
        "Das Vorhaben eines Schritts hat einen Titel - das Ziel, auf das er einzahlt")

    local position, total, groupIndex, groupCount = GCP.Guide:GroupPosition(grouped)
    expect(position ~= nil and total ~= nil, "Ein Schritt kennt seine Stelle im Vorhaben")
    expect(position >= 1 and position <= total, "...und die liegt im Rahmen")
    expect(groupIndex ~= nil and groupCount ~= nil, "...und sein Vorhaben unter allen")
    expect(groupIndex >= 1 and groupIndex <= groupCount, "...ebenfalls im Rahmen")

    -- Wege zwischen zwei Vorhaben behaupten keine Zugehoerigkeit.
    local loose = nil
    for _, candidate in ipairs(guideStore.steps) do
        if not candidate.groupID then loose = candidate break end
    end
    if loose then
        expectEqual(GCP.Guide:GroupInfo(loose), nil,
            "Ein Schritt ohne Vorhaben bekommt auch keines angedichtet")
    end

    -- Die Angaben ueberleben einen /reload: Sie liegen im Speicher, nicht im
    -- Laufzeitobjekt der Route.
    GCP.Guide.route = nil
    local afterReload = GCP.Guide:GroupInfo(grouped)
    expect(afterReload ~= nil and afterReload.title == info.title,
        "Das Vorhaben steht auch ohne Laufzeitobjekt noch da")
end

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

-- Offene Sitzung: alles zaehlt, was in die Taschen kommt.
H.clearBags()
local openSession = GCP.Farm:Start(nil, "Nagrand")
expect(openSession ~= nil, "Eine Sitzung ohne Zielliste laesst sich starten")
expect(openSession.open, "...und gilt als offene Sitzung")
H.farmRun(GCP, 900, { chunk = 300, itemID = 22785, perChunk = 4 })
H.addBagItem(21877, 12)
local openStatus = GCP.Farm:Status()
expectEqual(openStatus.totalItems, 12 + 12,
    "Eine offene Sitzung zaehlt jedes Item, das dazukommt")
expect(openStatus.yield[22785] ~= nil, "...das eine")
expect(openStatus.yield[21877] ~= nil, "...und das andere")
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

-- Der Guide startet und beendet die Farmsitzung von selbst.
GCP.Guide:Abort()
GCP.Capital:Invalidate()
GCP.Guide:Start({ profile = "FARMING", minutes = 60 })
local guard = 0
while guard < 20 do
    local step = GCP.Guide:CurrentStep()
    if not step then break end
    if step.type == "FARM" then break end
    GCP.Guide:Complete(step.id, false)
    guard = guard + 1
end
local farmStep = GCP.Guide:CurrentStep()
if farmStep and farmStep.type == "FARM" then
    expect(GCP.Farm:Current() ~= nil,
        "Beim Farmschritt startet der Guide die Messung von selbst")
    expect(GCP.Farm:Current().startedByGuide, "...und merkt sich, dass er es war")
    GCP.Guide:Complete(farmStep.id, false)
    expectEqual(GCP.Farm:Current(), nil,
        "Nach dem Farmschritt beendet er sie wieder")
end
GCP.Guide:Abort()

-- Die Slash-Befehle steuern dasselbe.
local slashFarm = SlashCmdList["GOLDCOPILOT"]
expect(pcall(slashFarm, "farm start"), "/gold farm start laeuft")
expect(GCP.Farm:Current() ~= nil, "...und startet eine Sitzung")
expect(pcall(slashFarm, "farm stop"), "/gold farm stop laeuft")
expectEqual(GCP.Farm:Current(), nil, "...und beendet sie")
expect(pcall(slashFarm, "farm unsinn"), "Ein unbekanntes Farmargument wird abgefangen")

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
        type = "craft", itemID = 23571, saleItemID = 23571,
        key = "craft:23571",
        expectedProfit = 100000, expectedROI = 0.3,
        opportunityScore = 80, confidence = "high",
        marketScore = 75, liquidityScore = 70,
        executedAt = H.now - index * 3600, entryPrice = 100000, entryQuantity = 1,
        soldAt = H.now - index * 1800, exitPrice = 140000,
        realizedProfit = index <= 36 and 40000 or -10000,
        realizedROI = index <= 36 and 0.4 or -0.1,
        holdingHours = 4,
        outcome = index <= 36 and "WIN" or "LOSS",
        -- 1.0.0-beta.10: Ein Craft-Ergebnis zaehlt nur mit belegter Zuordnung.
        -- Diese hier stammen aus abgehakten Guide-Schritten, also "claim".
        match = "claim",
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
-- AUDIT 1.0.0-beta.10
--
-- Regressionstests zu den Befunden eines externen Code-Reviews. Jeder Block
-- prueft genau die Aussage, die vorher NICHT stimmte - und dokumentiert damit,
-- warum die Aenderung noetig war.
--
-- Das Ganze steht in einer sofort aufgerufenen Funktion: Der Hauptteil dieser
-- Datei ist nahe an Luas Grenze von 200 lokalen Variablen je Funktion, und ein
-- eigener Rahmen bekommt sein eigenes Budget.
-- ===========================================================================

;(function()
H.section("Audit: Zuordnung von Vorhersagen")

do
    H.reset(GCP)
    H.seedRealm(GCP)
    local history = GCP.Opportunity:EnsureHistory()

    -- --- 1a) Resale wird weiterhin ueber die Item-Identitaet zugeordnet -----
    --
    -- Das ist der einzige Fall, in dem der alte Weg funktionierte: gekauft und
    -- verkauft wird dasselbe Item, und es gibt genau eine Zutat. Er muss
    -- weiterhin funktionieren - sonst waere die Verschaerfung ein Rueckschritt.
    history[1] = {
        timestamp = H.now - 7200, type = "resale", itemID = 21877,
        saleItemID = 21877, key = "resale:21877", identity = true,
        expectedProfit = 5000, opportunityScore = 75, confidence = "high",
    }
    GCP.Ledger:RecordPurchase({ itemID = 21877, quantity = 4, unitPrice = 3000,
        timestamp = H.now - 3600 })
    GCP.Opportunity:MatchHistoryOutcomes()
    expect(history[1].executedAt ~= nil, "Ein Resale wird ueber die Item-Identitaet zugeordnet")
    expectEqual(history[1].match, "identity", "...und die Art der Zuordnung steht dabei")
    expectEqual(history[1].entryPrice, 3000, "...mit dem tatsaechlichen Einstandspreis")

    -- --- 1b) Ein Craft wird NICHT ueber die Item-Identitaet zugeordnet ------
    --
    -- Der Kern des Befunds. Eine Craft-Empfehlung fuer Urmacht nennt als
    -- itemID das PRODUKT. Wer Urmacht kauft, hat sie gerade nicht hergestellt -
    -- der Kauf ist der Beleg fuer das Gegenteil der Empfehlung.
    H.reset(GCP)
    history = GCP.Opportunity:EnsureHistory()
    history[1] = {
        timestamp = H.now - 7200, type = "craft", itemID = 23571,
        saleItemID = 23571, key = "craft:23571", identity = false,
        expectedProfit = 100000, opportunityScore = 80, confidence = "high",
    }
    GCP.Ledger:RecordPurchase({ itemID = 23571, quantity = 1, unitPrice = 600000,
        timestamp = H.now - 3600 })
    GCP.Opportunity:MatchHistoryOutcomes()
    expectEqual(history[1].executedAt, nil,
        "Ein Kauf des Produkts bestaetigt keine Craft-Empfehlung")
    expectEqual(history[1].outcome, nil, "...und erzeugt auch kein Ergebnis")

    -- --- 1c) Der Kauf einer ZUTAT bestaetigt sie ebenfalls nicht allein ----
    --
    -- Ein Craft aus fuenf Zutaten laesst sich aus einem einzelnen Kauf nicht
    -- rekonstruieren: Dieselbe Zutat steckt in mehreren Rezepten, und wer sie
    -- kauft, kann jedes davon meinen - oder keines.
    GCP.Ledger:RecordPurchase({ itemID = 21884, quantity = 1, unitPrice = 200000,
        timestamp = H.now - 3500 })
    GCP.Opportunity:MatchHistoryOutcomes()
    expectEqual(history[1].executedAt, nil,
        "Auch der Kauf einer Zutat allein bestaetigt keine Craft-Empfehlung")

    -- --- 1d) Die gemeldete Ausfuehrung ordnet zu --------------------------
    expect(GCP.Opportunity:ClaimExecution({
        key = "craft:23571", type = "craft", saleItemID = 23571,
        runs = 2, units = 2, unitCost = 300000, timestamp = H.now - 3400,
    }), "Die vom Guide gemeldete Ausfuehrung findet ihre Empfehlung")
    expectEqual(history[1].match, "claim", "...und ist als belegt markiert")
    expectEqual(history[1].entryQuantity, 2, "...mit der geplanten Stueckzahl")
    expectEqual(history[1].entryPrice, 300000, "...und der Kostenbasis je Stueck")
    expectEqual(history[1].outcome, "OPEN", "...und gilt als offene Position")

    -- --- 1e) Eine zweite Meldung veraendert nichts ------------------------
    expectEqual(GCP.Opportunity:ClaimExecution({
        key = "craft:23571", type = "craft", saleItemID = 23571,
        runs = 9, units = 9, unitCost = 111, timestamp = H.now - 3300,
    }), false, "Eine zweite Meldung derselben Chance wird abgelehnt")
    expectEqual(history[1].entryQuantity, 2, "...und ueberschreibt nichts")

    -- --- 1f) Ohne passende Empfehlung passiert nichts ---------------------
    expectEqual(GCP.Opportunity:ClaimExecution({
        key = "craft:99999", type = "craft", saleItemID = 99999,
        runs = 1, units = 1, unitCost = 1000, timestamp = H.now,
    }), false, "Eine Meldung ohne Protokolleintrag erzeugt keinen")

    -- --- 1g) Eine Umwandlung schliesst ueber das VERKAUFSitem -------------
    --
    -- Bei "Urluft zu Urfeuer" wird Urluft gekauft und Urfeuer verkauft. Der
    -- Abschluss muss deshalb am Verkaufsitem haengen, nicht am gekauften.
    H.reset(GCP)
    history = GCP.Opportunity:EnsureHistory()
    history[1] = {
        timestamp = H.now - 7200, type = "conversion", itemID = 21884,
        saleItemID = 21884, key = "conversion:mote:21884", identity = false,
        expectedProfit = 20000, opportunityScore = 70, confidence = "high",
    }
    expect(GCP.Opportunity:ClaimExecution({
        key = "conversion:mote:21884", type = "conversion", saleItemID = 21884,
        runs = 1, units = 1, unitCost = 100000, timestamp = H.now - 3600,
    }), "Die Umwandlung wird ueber ihren Schluessel zugeordnet")
    GCP.Ledger:RecordSale({ itemID = 21884, quantity = 1, totalGross = 150000,
        source = "ah", timestamp = H.now - 1800 })
    GCP.Opportunity:MatchHistoryOutcomes()
    expectEqual(history[1].outcome, "WIN",
        "Der Verkauf des Ausgabe-Items schliesst die Umwandlung ab")
    expect(history[1].realizedProfit > 0, "...mit einem realisierten Gewinn")

    -- --- 1h) Unsichere Zuordnungen zaehlen in keiner Auswertung ------------
    H.reset(GCP)
    history = GCP.Opportunity:EnsureHistory()
    for index = 1, 12 do
        history[#history + 1] = {
            timestamp = H.now - index * 3600, type = "craft", itemID = 23571,
            expectedProfit = 1000, opportunityScore = 80, confidence = "high",
            executedAt = H.now - index * 3600, entryPrice = 1000, entryQuantity = 1,
            realizedProfit = 500, outcome = "WIN",
            -- Kein match-Feld und kein Resale: aus einer aelteren Fassung, in
            -- der die Zuordnung nicht belegt war.
        }
    end
    local report = GCP.Analytics:GetReport(true)
    expectEqual(report.total.n, 0,
        "Craft-Ergebnisse ohne belegte Zuordnung zaehlen in keiner Trefferquote")
    expectEqual(report.unknown, 12, "...werden aber als unsicher ausgewiesen")
    expectEqual(report.byType.craft, nil, "...und erzeugen keine Chancenart-Statistik")

    -- Und die Kalibrierung lernt daraus folgerichtig nichts.
    local ok, why = GCP.Calibration:Update(true)
    expectEqual(ok, false, "Die Kalibrierung laeuft ohne belastbare Faelle nicht an")
    expect(type(why) == "string", "...und sagt warum")
end

H.section("Audit: Economic Cost gegen Cash")

do
    -- Wirtschaftliche Kosten 400 g, alles im Bestand: Kapitalbedarf 0 g.
    local sizing = GCP.Capital:SizePosition({
        unitCost = 4000000, unitCashCost = 4000000, ownedUnits = 3,
        investable = 100000000, remainingCapital = 0,
        exposureBase = 1000000000, score = 80, confidence = "high",
        maxUnits = 3,
    })
    expect(sizing ~= nil, "Ein Craft aus eigenem Material bleibt planbar, auch ohne Gold")
    expectEqual(sizing.units, 3, "...und zwar so oft, wie der Bestand reicht")
    expectEqual(sizing.cashRequired, 0, "...ohne einen einzigen Kupfer Kapitalbedarf")
    expectEqual(sizing.capital, 3 * 4000000,
        "Wirtschaftlich zaehlt das Material trotzdem voll")

    -- Die Haelfte im Bestand: nur die fehlenden Durchgaenge kosten Gold.
    sizing = GCP.Capital:SizePosition({
        unitCost = 4000000, unitCashCost = 4000000, ownedUnits = 2,
        investable = 100000000, remainingCapital = 8000000,
        exposureBase = 1000000000, score = 80, confidence = "high",
        maxUnits = 4,
    })
    expectEqual(sizing.units, 4, "Bestand plus bezahlbarer Zukauf ergibt vier Durchgaenge")
    expectEqual(sizing.cashRequired, 2 * 4000000,
        "Bezahlt werden nur die beiden fehlenden")
    expectEqual(sizing.capital, 4 * 4000000, "Wirtschaftlich sind es trotzdem vier")

    -- Ohne Bestand bleibt alles wie vorher: Kosten gleich Kapitalbedarf.
    sizing = GCP.Capital:SizePosition({
        unitCost = 1000000, investable = 100000000, remainingCapital = 3000000,
        exposureBase = 1000000000, score = 80, confidence = "high", maxUnits = 10,
    })
    expectEqual(sizing.units, 3, "Ohne eigenen Bestand deckelt das freie Gold wie bisher")
    expectEqual(sizing.cashRequired, sizing.capital,
        "...und beide Zahlen sind dann dieselbe")
end

H.section("Audit: Angebot mehrerer Zutaten")

do
    H.reset(GCP)
    H.seedRealm(GCP)

    -- Ein Craft mit drei Zutaten. Der Markt gibt her:
    --   Urfeuer      50 Stueck, 1 je Durchgang  -> 50 Durchgaenge
    --   Urschatten    5 Stueck, 4 je Durchgang  ->  1 Durchgang
    --   Urerde      500 Stueck, 10 je Durchgang -> 50 Durchgaenge
    -- Moeglich ist genau EINER. Bis 1.0.0-beta.9 kamen hier 50 heraus, weil nur
    -- die erste Zutat gezaehlt wurde.
    local function depth(itemID, quantity, unitPrice)
        local listings = {}
        for index = 1, math.min(quantity, 40) do
            listings[index] = { count = math.ceil(quantity / math.min(quantity, 40)),
                buyoutTotal = unitPrice * math.ceil(quantity / math.min(quantity, 40)) }
        end
        GCP.Market:RecordDepth(itemID, listings, H.now)
    end
    depth(21884, 50, 200000)
    depth(22456, 5, 200000)
    depth(22452, 500, 20000)

    local fields = {
        itemID = 23571, saleItemID = 23571, cost = 1000000,
        execution = { method = "craft", inputs = {
            { itemID = 21884, count = 1, unitPrice = 200000 },
            { itemID = 22456, count = 4, unitPrice = 200000 },
            { itemID = 22452, count = 10, unitPrice = 20000 },
        }, sellItemID = 23571, sellCount = 1 },
    }
    local _, _, maxUnits, note, info = GCP.Opportunity:SupplyFor(fields)
    expectEqual(maxUnits, 1, "Die knappste Zutat bestimmt die Zahl der Durchgaenge")
    expectEqual(info.bindingItemID, 22456, "...und sie wird auch benannt")
    expectEqual(info.supplyKnown, true, "Alle drei Zutaten sind gemessen")
    expect(type(note) == "string" and note:find("Begrenzend") ~= nil,
        "Die Notiz sagt, welche Zutat begrenzt")

    -- Eigener Bestand zaehlt mit: Was im Beutel liegt, muss der Markt nicht
    -- liefern.
    H.addBagItem(22456, 16)
    GCP.Inventory.cache = nil
    fields.inventory = GCP.Inventory:ScanAccount()
    local _, _, withStock, _, stockInfo = GCP.Opportunity:SupplyFor(fields)
    -- 16 im Beutel + 5 im Angebot = 21, je Durchgang 4 -> 5 Durchgaenge.
    expectEqual(withStock, 5, "Bestand und Angebot zusammen ergeben die Obergrenze")
    -- Aus reinem Bestand geht dagegen KEIN Durchgang: Zu den anderen beiden
    -- Zutaten liegt nichts im Beutel, und ein halber Craft ist keiner. Auch
    -- diese Zahl ist ein Minimum ueber alle Zutaten, kein Maximum.
    expectEqual(stockInfo.stockRuns, 0,
        "Ohne alle Zutaten im Bestand ist kein Durchgang aus dem Bestand moeglich")
    for _, record in ipairs(stockInfo.inputs) do
        if record.itemID == 22456 then
            expectEqual(record.owned, 16, "Der eigene Bestand der knappen Zutat zaehlt mit")
            expectEqual(record.runs, 5, "...und hebt ihre Obergrenze von 1 auf 5")
        end
    end

    -- Eine Zutat ohne frische Messung macht die Grenze unsicher - aber nicht
    -- unendlich. Die gemessenen Zutaten liefern weiterhin eine Obergrenze.
    fields.execution.inputs[4] = { itemID = 22457, count = 1, unitPrice = 200000 }
    local _, _, partial, partialNote, partialInfo = GCP.Opportunity:SupplyFor(fields)
    expectEqual(partialInfo.supplyKnown, false,
        "Eine ungemessene Zutat macht die Angebotslage unvollstaendig")
    expectEqual(partialInfo.unknownInputs, 1, "...und das steht auch so da")
    expect(partial ~= nil and partial <= 5,
        "Unbekannt heisst nicht unbegrenzt: die Obergrenze bleibt bestehen")
    expect(type(partialNote) == "string" and partialNote:find("frische Angebotsmessung") ~= nil,
        "Die Notiz sagt, dass nicht jede Zutat gemessen ist")

    -- Gar keine Messung: keine Aussage. Das ist die ehrliche Antwort und nicht
    -- etwa "null Durchgaenge".
    GCP.Market:ResetDepth()
    local noDepth, _, noUnits = GCP.Opportunity:SupplyFor(fields)
    expectEqual(noDepth, nil, "Ohne jede Messung gibt es keine Angebotsaussage")
    expectEqual(noUnits, nil, "...und ausdruecklich keine Stueckzahl")
end

H.section("Audit: Greifbarer Bestand")

do
    -- Was schon im Auktionshaus liegt, ist Besitz - aber kein Material. Wer es
    -- fuer einen Craft einplant, muesste erst die Auktion abbrechen und die
    -- Einstellgebuehr abschreiben. Der Kapitalbedarf darf sich davon nicht
    -- kleinrechnen lassen.
    local fields = {
        itemID = 23571, saleItemID = 23571, cost = 1000000,
        inventory = {
            [21884] = { itemID = 21884, count = 10,
                sources = { ["Auktionen"] = 10 } },
        },
        execution = { method = "craft", inputs = {
            { itemID = 21884, count = 1, unitPrice = 200000 },
        }, sellItemID = 23571, sellCount = 1 },
    }
    local _, _, _, _, listedInfo = GCP.Opportunity:SupplyFor(fields)
    expectEqual(listedInfo.stockRuns, 0,
        "Was im Auktionshaus liegt, zaehlt nicht als greifbares Material")
    expectEqual(listedInfo.inputs[1].owned, 0, "...auch nicht je Zutat")

    -- Dasselbe in der Bank zaehlt dagegen sehr wohl: Die Execution Engine holt
    -- es dort ab, und das kostet kein Gold.
    fields.inventory[21884].sources = { ["Bank"] = 6, ["Auktionen"] = 4 }
    local _, _, _, _, bankInfo = GCP.Opportunity:SupplyFor(fields)
    expectEqual(bankInfo.stockRuns, 6,
        "Bank und Post zaehlen als greifbar, die Auktionen daneben nicht")

    -- Ohne Syndicator gibt es gar keine Quellenangabe. Dann sind es die eigenen
    -- Taschen, und die sind greifbar.
    fields.inventory[21884].sources = nil
    local _, _, _, _, bagInfo = GCP.Opportunity:SupplyFor(fields)
    expectEqual(bagInfo.stockRuns, 10,
        "Ohne Quellenangabe zaehlt der ganze Bestand - das sind die Taschen")

    -- Und die Execution Engine muss dasselbe meinen: Plant die eine Seite Gold
    -- ein, das die andere nicht ausgibt, stimmt der ganze Plan nicht mehr.
    local plan = { virtual = {}, bank = {}, mail = {} }
    GCP.Execution:SeedInventory(plan, {
        [21884] = { itemID = 21884, count = 10, sources = { ["Auktionen"] = 10 } },
    })
    expectEqual(plan.virtual[21884], 0,
        "Auch die Execution Engine greift nicht auf eingestellte Ware zu")
    GCP.Execution:SeedInventory(plan, {
        [21884] = { itemID = 21884, count = 10 },
    })
    expectEqual(plan.virtual[21884], 10,
        "...ohne Quellenangabe zaehlt sie den Bestand weiterhin voll")
end

H.section("Audit: Beschaffbarkeit trotz Bestand")

do
    H.reset(GCP)
    H.seedRealm(GCP)

    -- Item 60010 ist beim Aufheben gebunden - es steht nie im Auktionshaus.
    -- Ein Craft, der es braucht, ist mit Bestand ausfuehrbar und ohne nicht.
    local withStock = GCP.Opportunity:Make({
        type = "craft", key = "craft:test", itemID = 23571, saleItemID = 23571,
        title = "Testcraft", cost = 100000, expectedRevenue = 200000,
        confidence = "high", marketScore = 70,
        feasible = 2,
        execution = { method = "craft", inputs = { { itemID = 60010, count = 1,
            unitPrice = 100000 } }, sellItemID = 23571, sellCount = 1 },
    })
    expect(withStock ~= nil, "Mit eigenem Bestand bleibt der Craft eine Chance")
    expectEqual(withStock.purchasable, true, "...er ist ausfuehrbar")
    expectEqual(withStock.purchaseLimited, true, "...aber nur begrenzt")
    expectEqual(withStock.maxUnits, 2,
        "Ohne Nachschub ist der eigene Bestand die Obergrenze")
    expect(withStock.purchaseWarning:find("Bestand") ~= nil,
        "Die Warnung sagt, wie weit es trotzdem reicht")

    local withoutStock = GCP.Opportunity:Make({
        type = "craft", key = "craft:test2", itemID = 23571, saleItemID = 23571,
        title = "Testcraft", cost = 100000, expectedRevenue = 200000,
        confidence = "high", marketScore = 70,
        execution = { method = "craft", inputs = { { itemID = 60010, count = 1,
            unitPrice = 100000 } }, sellItemID = 23571, sellCount = 1 },
    })
    expect(withoutStock ~= nil, "Ohne Bestand entsteht die Chance ebenfalls ...")
    expectEqual(withoutStock.purchasable, false, "...ist aber nicht ausfuehrbar")
end

H.section("Audit: Erwartete Einstellgebuehren")

do
    H.reset(GCP)

    -- Zu wenig Daten: keine Schaetzung. Das ist der wichtigere der beiden
    -- Faelle - eine erfundene Gebuehr waere schlimmer als gar keine.
    H.seedTrade(GCP, 21877, { rounds = 2, quantity = 2, buyPrice = 1000,
        sellPrice = 2000, expiries = 0 })
    expectEqual(GCP.Ledger:ExpectedRelistCost(21877), nil,
        "Ohne belastbare Stichprobe entstehen keine Relisting-Kosten")

    -- Genug Daten mit echten Ablaeufen: der Erwartungswert entsteht.
    H.reset(GCP)
    local store = GCP.Ledger:EnsureStore()
    for round = 1, 10 do
        local at = H.now - (20 - round) * 86400
        GCP.Ledger:RecordAuctionPosted({ itemID = 23425, quantity = 2,
            unitPrice = 60000, deposit = 1000, durationHours = 12, timestamp = at })
        if round <= 8 then
            local _, quality = GCP.Ledger:MatchSale(store, 23425, 120000)
            GCP.Ledger:RecordSale({ itemID = 23425, quantity = 2,
                totalGross = 120000, source = "ah", timestamp = at + 3600,
                holdHours = 1, matchQuality = quality })
        else
            GCP.Ledger:RecordAuctionExpired({ itemID = 23425, quantity = 2,
                timestamp = at + 43200 })
        end
    end
    local perUnit, parts = GCP.Ledger:ExpectedRelistCost(23425)
    expect(perUnit ~= nil, "Mit genug eigenen Daten entsteht ein Erwartungswert")
    expectEqual(parts.soldQuantity, 16, "...auf Basis der verkauften Stueckzahl")
    -- Zwei abgelaufene Auktionen zu je 1000 Kupfer Gebuehr auf 16 verkaufte
    -- Stueck: 2000 / 16 = 125.
    expectEqual(perUnit, 125, "...und er ist die verbrannte Gebuehr je verkauftem Stueck")

    -- Und er landet als ZWEITE Zahl an der Chance, ohne die erste zu veraendern.
    local opportunity = GCP.Opportunity:Make({
        type = "resale", key = "resale:23425", itemID = 23425, saleItemID = 23425,
        title = "Test", cost = 50000, expectedRevenue = 60000,
        confidence = "high", marketScore = 70,
        execution = { method = "resale", inputs = { { itemID = 23425, count = 1,
            unitPrice = 50000 } }, sellItemID = 23425, sellCount = 1 },
    })
    expect(opportunity ~= nil, "Die Chance entsteht")
    expectEqual(opportunity.expectedProfit, 10000,
        "Die theoretische Marge bleibt unveraendert")
    expectEqual(opportunity.expectedRelistCost, 125, "...die Gebuehr steht daneben")
    expectEqual(opportunity.netExpectedProfit, 10000 - 125,
        "...und daraus die erwartete Marge nach eigener Erfahrung")
end

H.section("Audit: Persoenliche Marktaufnahme")

do
    H.reset(GCP)
    -- Ohne belastbare Stichprobe gibt es keine Wochenmenge.
    expectEqual(GCP.Ledger:AbsorptionPerWeek(23425), nil,
        "Ohne eigene Verkaufsdaten gibt es keine Marktaufnahme")

    -- Mit Daten: rund acht Stueck je Woche ueber vier Wochen.
    H.seedTrade(GCP, 23425, { rounds = 8, quantity = 4, buyPrice = 40000,
        sellPrice = 60000, startAt = H.now - 30 * 86400 })
    local perWeek, sample = GCP.Ledger:AbsorptionPerWeek(23425)
    expect(perWeek ~= nil, "Mit genug eigenen Verkaeufen entsteht eine Wochenmenge")
    expect(sample.spanDays >= 7, "...ueber mindestens eine Woche gemessen")

    -- Sie deckelt die Position - und nur nach unten.
    local cap, reason = GCP.Capital:UnitCap({
        liquidityConfidence = "high", absorptionPerWeek = 3,
    })
    expectEqual(cap, 6, "Drei Stueck je Woche erlauben zwei Wochen Vorrat")
    expectEqual(reason, "deine Verkaufsmenge", "...und die Begruendung sagt es")
    local wideCap = GCP.Capital:UnitCap({
        liquidityConfidence = "high", absorptionPerWeek = 500,
    })
    expectEqual(wideCap, GCP.Constants.CAPITAL.SIZING.MAX_UNITS_PROVEN,
        "Eine hohe Aufnahme hebt den bestehenden Deckel nicht an")
end

H.section("Audit: Markttrend")

do
    H.reset(GCP)
    -- Ein Markt, der ueber Wochen faellt: 100 -> 50. Der Preis steht am
    -- Ende historisch ganz unten - aber "billig" ist hier kein Einstieg,
    -- sondern ein fallendes Messer.
    local base = H.now - 30 * 86400
    for index = 0, 29 do
        local price = math.floor(100000 - index * 1600)
        GCP.Market:AddSnapshot(21877, price, base + index * 86400, "Auctionator")
    end
    H.marketPrices[21877] = 52000
    GCP.Market.statsCache = {}
    local falling = GCP.Market:GetStats(21877)
    expectEqual(falling.trend, "falling", "Ein fallender Markt wird als solcher erkannt")
    expect(falling.trendDamping ~= nil and falling.trendDamping < 1,
        "...und daempft den Score Richtung 50")
    expect(GCP.Market:DescribeScore(falling):find("Markt fällt") ~= nil,
        "Die Erklaerung nennt den Trend, statt ihn nur zu verrechnen")

    -- Derselbe Perzentilwert ohne Trend: kein Abschlag. Die Daempfung haengt am
    -- Trend, nicht am niedrigen Preis.
    H.reset(GCP)
    for index = 0, 29 do
        local price = (index % 5 == 4) and 52000 or 100000
        GCP.Market:AddSnapshot(21877, price, base + index * 86400, "Auctionator")
    end
    GCP.Market.statsCache = {}
    local spiky = GCP.Market:GetStats(21877)
    expect(spiky.trend ~= "falling",
        "Ein einzelner Ausreisser nach unten ist kein fallender Markt")
    expectEqual(spiky.trendDamping, nil, "...und wird deshalb auch nicht gedaempft")
    H.marketPrices[21877] = 1000
end

H.section("Audit: Market-Score-Sonde")

do
    H.reset(GCP)
    H.seedRealm(GCP)
    GCP.Market:ResetProbes()
    expectEqual(#GCP.Market:GetProbes(), 0, "Ohne Durchlauf gibt es keine Sonde")

    local written = GCP.Market:RecordScoreProbes(H.now)
    expect(written > 0, "Der Durchlauf schreibt Beobachtungspunkte")
    local probes = GCP.Market:GetProbes()
    expect(probes[1].score ~= nil and probes[1].price ~= nil,
        "Ein Punkt haelt Score und Preis fest")

    -- Ein Fenster, das dreimal aufgeht, ist keine dreifache Beobachtung.
    --
    -- Gezaehlt wird bis zur Erschoepfung: Ein Durchlauf schreibt hoechstens
    -- PROBE.MAX_PER_RUN Punkte, damit er im Spiel keinen Ruckler macht - wie
    -- viele Items ueberhaupt beobachtet werden, haengt an Rezepten und
    -- Preisquellen und darf diesen Test nicht entscheiden. Bis 1.1.0-beta.4
    -- lag die Zahl der Items zufaellig genau auf der Grenze, und der Test
    -- prueft seitdem die Grenze statt der Regel.
    local drained = 0
    for _ = 1, 20 do
        local more = GCP.Market:RecordScoreProbes(H.now + 60)
        if more == 0 then break end
        drained = drained + more
    end
    expectEqual(GCP.Market:RecordScoreProbes(H.now + 60), 0,
        "Ein Punkt je Item und Zeitfenster, nicht mehr")

    -- Die Auswertung braucht einen verstrichenen Horizont. Vorher gibt es
    -- ausdruecklich keine Aussage - auch keine Null.
    local validation = GCP.Analytics:ScoreValidation()
    expect(validation.probes > 0, "Die Auswertung kennt die Punkte")
    local anyBand = false
    for _, horizon in ipairs(validation.horizons) do
        for _ in pairs(horizon.bands) do anyBand = true end
    end
    expectEqual(anyBand, false,
        "Vor Ablauf des ersten Horizonts gibt es keine Aussage")
    local lines = table.concat(GCP.Analytics:ScoreValidationLines(), "\n")
    expect(lines:find("Beobachtungspunkt") ~= nil,
        "Die Ausgabe sagt, worauf sie beruht")
end

H.section("Audit: Farmraten")

do
    H.reset(GCP)
    -- Der Katalog traegt keine uebernommenen Stundenraten mehr.
    for _, farm in ipairs(GCP.Constants.FARM_CATALOG) do
        expectEqual(farm.ratePerHour, nil,
            "Kein Farmziel traegt eine Rate aus fremden Guides")
        expect(farm.zone ~= nil, "...die Ortsangabe bleibt aber erhalten")
    end
    -- Und ohne eigene Sitzung entsteht keine Gold/h-Zahl.
    expectEqual(#GCP.Farm:BuildOpportunities(60), 0,
        "Ohne eigene Sitzung entsteht kein Farmblock")
end

end)()

-- ===========================================================================
-- PHASE A: DEMAND EVIDENCE UND ACTIONABILITY (1.1.0)
--
-- Die Frage, die bis 1.0 an keiner Stelle gestellt wurde: Welche Belege gibt
-- es dafuer, dass dieses Item gekauft wird? Ein positiver Rechenweg ist keiner.
-- ===========================================================================

;(function()

H.section("Demand: strukturelle Nachfrage")

H.reset(GCP)

-- Priorwissen kommt aus der Wissensbasis - und nur fuer Items, die dort
-- stehen. Fuer alles andere gibt es keines, und das ist die Ausgangslage der
-- meisten Items.
expectEqual(GCP.Demand:StructuralFor(999999), nil,
    "Ohne Eintrag in der Wissensbasis gibt es kein Priorwissen")

-- Urluft ist ein Material: wird verbraucht, wird wieder gebraucht.
local air = GCP.Demand:StructuralFor(22451)
expect(air ~= nil, "Ein bekanntes Material hat eine Demand Identity")
expectEqual(air.type, "RECURRING", "...ein Material wird wieder gebraucht")
expectEqual(air.consumption, "CONSUMED", "...und dabei verbraucht")

-- Hergestellte Ausruestung ist der Gegenfall: einmal gekauft, danach nie
-- wieder - und ohne Weiterverwendung.
local gear = GCP.Demand:StructuralFor(32391)      -- Soulguard Slippers
expect(gear ~= nil, "Hergestellte Ausruestung hat ebenfalls eine Identity")
expectEqual(gear.type, "ONE_TIME", "...sie wird einmal gekauft")
expectEqual(gear.consumption, "DURABLE", "...und nicht verbraucht")
expectEqual(gear.breadth, "NARROW", "...und niemand baut etwas daraus")

-- Die Breite wird GEZAEHLT, nicht geschaetzt: Sie ist die Zahl der Produkte,
-- die im Dependency Graph an diesem Item haengen.
expect(type(air.breadthCount) == "number",
    "Die Verwendungsbreite ist eine gezaehlte Groesse")
expectEqual(gear.breadthCount, 0,
    "Ein Endprodukt hat keine Weiterverwendung - das ist die Aussage, keine Luecke")

-- Und das Obsoleszenzrisiko kommt aus den Catalysts, die ohnehin dastehen.
-- Die blauen Sockelsteine sind der einzige Fall der Wissensbasis, auf den ein
-- bekannter Grund nach unten zeigt.
local blueGem = GCP.Demand:StructuralFor(23436)   -- Living Ruby
expect(blueGem ~= nil, "Auch Sockelsteine haben eine Identity")
expect(blueGem.obsolescence == "HIGH" or blueGem.obsolescence == "MEDIUM",
    "Ein Catalyst nach unten erzeugt ein belegtes Obsoleszenzrisiko")

H.section("Demand: Evidence-Stufen")

H.reset(GCP)

-- STUFE 0. Ohne alles gibt es keine Belege - und ausdruecklich nicht
-- "keine Nachfrage".
local none = GCP.Demand:EvidenceFor(999999)
expectEqual(none.level, 0, "Ohne jede Information ist die Stufe null")
expectEqual(none.personal, nil, "...und es gibt keine eigenen Verkaufsdaten")

-- STUFE 1. Priorwissen allein.
local structural = GCP.Demand:EvidenceFor(22451)
expectEqual(structural.level, 1,
    "Priorwissen allein traegt genau eine Stufe")
expect(#structural.reasons > 0, "...und wird begruendet")

-- STUFE 2. Ein beobachteter Markt. Zwei Messungen sind das Minimum: Eine
-- einzelne ist eine Momentaufnahme.
GCP.Market:RecordDepth(22451, {
    { count = 5, buyoutTotal = 1000000 }, { count = 5, buyoutTotal = 1050000 },
}, H.now - 7200)
GCP.Market:RecordDepth(22451, {
    { count = 3, buyoutTotal = 600000 }, { count = 5, buyoutTotal = 1050000 },
}, H.now - 60)
local market = GCP.Demand:EvidenceFor(22451)
expectEqual(market.level, 2, "Ein beobachteter Markt traegt Stufe 2")
expect(market.realm.observations >= 2, "...aus mehreren Messungen")
-- Die einzige Nachfrageaussage ohne eigene Verkaeufe: Das Angebot ist
-- gesunken. Ob gekauft oder zurueckgezogen, laesst sich nicht trennen - und
-- genau das steht auch da.
expect(market.realm.supplyDrops > 0, "Ein gesunkenes Angebot wird bemerkt")
local dropText = table.concat(market.reasons, " ")
expect(dropText:find("zurückgezogen") ~= nil,
    "...und ausdruecklich nicht als Verkauf ausgegeben")

-- ENTSCHEIDEND: Fuenfzig Auktionen sind kein Nachfragebeleg. Sie sind
-- Angebot - moeglicherweise von zwanzig Verkaeufern, die darauf sitzenbleiben.
H.reset(GCP)
local many = {}
for index = 1, 50 do many[index] = { count = 20, buyoutTotal = 20 * 50000 } end
GCP.Market:RecordDepth(23425, many, H.now - 7200)
GCP.Market:RecordDepth(23425, many, H.now - 60)
local glut = GCP.Demand:EvidenceFor(23425)
expect(glut.level <= 2,
    "Auch ein riesiges Angebot kommt nie ueber Stufe 2 - Listings sind kein Verkauf")

H.section("Demand: eigene Verkaeufe schlagen alles")

H.reset(GCP)

-- STUFE 3. Ein einzelner belegter Verkauf.
H.seedTrade(GCP, 23425, { rounds = 1, quantity = 2, buyPrice = 40000,
    sellPrice = 60000, startAt = H.now - 3 * 86400 })
local first = GCP.Demand:EvidenceFor(23425)
expectEqual(first.level, 3, "Ein einzelner eigener Verkauf traegt Stufe 3")

-- STUFE 4. Wiederholte Verkaeufe mit belastbarer Sell-through.
H.reset(GCP)
H.seedTrade(GCP, 23425, { rounds = 5, quantity = 4, buyPrice = 40000,
    sellPrice = 60000, startAt = H.now - 12 * 86400 })
local repeated = GCP.Demand:EvidenceFor(23425)
expectEqual(repeated.level, 4, "Wiederholte Verkaeufe tragen Stufe 4")
expect(repeated.personal.sellThrough ~= nil, "...mit einer Sell-through-Rate")

-- STUFE 5. Stabile Historie: Stichprobe UND Zeitraum.
H.reset(GCP)
H.seedTrade(GCP, 23425, { rounds = 10, quantity = 4, buyPrice = 40000,
    sellPrice = 60000, startAt = H.now - 30 * 86400 })
local stable = GCP.Demand:EvidenceFor(23425)
expectEqual(stable.level, 5, "Eine stabile Historie traegt Stufe 5")

-- AKTUALITAET. Dieselbe Historie, aber lange her: Die Stufe faellt. Was vor
-- sechs Wochen ging, muss heute nicht mehr gehen.
H.reset(GCP)
H.seedTrade(GCP, 23425, { rounds = 10, quantity = 4, buyPrice = 40000,
    sellPrice = 60000, startAt = H.now - 90 * 86400 })
local stale = GCP.Demand:EvidenceFor(23425)
expectEqual(stale.stale, true, "Alte Verkaufsdaten werden als veraltet erkannt")
expect(stale.level < 5, "...und zaehlen eine Stufe weniger")
local staleText = table.concat(stale.caveats, " ")
expect(staleText:find("zurück") ~= nil, "...mit einem Satz, der sagt warum")

H.section("Demand: Aufnahmefaehigkeit")

H.reset(GCP)

-- Ohne beobachteten Markt gibt es keine Menge. Nicht einmal einen Test: Wer
-- nicht weiss, ob es diesen Markt gibt, soll ihn beobachten.
-- Ohne Belege gibt es genau einen Markttest. Nicht null - dann entstuende nie
-- Evidenz - und nicht zwanzig, weil das Kapital reicht.
local noCapacity = GCP.Demand:CapacityFor(999999)
expectEqual(noCapacity.units, 1, "Ohne Belege gibt es genau ein Teststueck")

-- Ein beobachteter Markt ohne eigenen Verkauf traegt genau einen Markttest.
GCP.Market:RecordDepth(22451, { { count = 9, buyoutTotal = 1800000 } }, H.now - 7200)
GCP.Market:RecordDepth(22451, { { count = 9, buyoutTotal = 1800000 } }, H.now - 60)
local testCapacity = GCP.Demand:CapacityFor(22451)
expectEqual(testCapacity.units, 1,
    "Ein beobachteter Markt ohne eigenen Verkauf traegt genau ein Teststueck")

-- Mit Historie entsteht eine gemessene Menge - konservativ gegen die
-- Testmenge geschrumpft.
H.reset(GCP)
H.seedTrade(GCP, 23425, { rounds = 10, quantity = 4, buyPrice = 40000,
    sellPrice = 60000, startAt = H.now - 30 * 86400 })
local measured = GCP.Demand:CapacityFor(23425)
expect(measured.units > 1, "Mit belegter Historie darf es mehr als ein Stueck sein")
expect(measured.units <= GCP.Constants.DEMAND.CAPACITY_MAX,
    "...aber nie mehr als die harte Obergrenze")
expect(measured.measured ~= nil, "Die gemessene Rate steht dabei")
expect(measured.units <= math.ceil(measured.measured),
    "Die Empfehlung liegt nie ueber der Messung - die Schrumpfung geht nach unten")

-- SCHLECHTE SELL-THROUGH SENKT DIE MENGE. Wer 10 von 30 verkauft, hat eine
-- andere Aufnahme als wer 10 von 10 verkauft.
H.reset(GCP)
H.seedTrade(GCP, 23425, { rounds = 10, quantity = 4, buyPrice = 40000,
    sellPrice = 60000, expiries = 20, startAt = H.now - 30 * 86400 })
local poor = GCP.Demand:CapacityFor(23425)
expect(poor.units < measured.units,
    "Viele abgelaufene Auktionen senken die empfohlene Menge")

H.section("Actionability: die vier Klassen")

H.reset(GCP)
H.seedRealm(GCP)

local function opportunity(fields)
    local base = {
        type = "craft", key = "craft:test", itemID = 23571, saleItemID = 23571,
        title = "Test", cost = 100000, cashRequired = 100000,
        expectedProfit = 50000, expectedRevenue = 150000,
        pricePlausible = true, purchasable = true,
    }
    for key, value in pairs(fields or {}) do base[key] = value end
    return base
end

-- BLOCKED. Keine Bewertung, sondern eine Beobachtung.
expectEqual(GCP.Actionability:Assess(opportunity({ pricePlausible = false })).class,
    "BLOCKED", "Ein unbelegter Verkaufspreis blockiert die Chance")
expectEqual(GCP.Actionability:Assess(opportunity({ purchasable = false })).class,
    "BLOCKED", "Eine nicht beschaffbare Kaufseite ebenfalls")
expectEqual(GCP.Actionability:Assess(opportunity({ expectedProfit = 0 })).class,
    "BLOCKED", "Und ohne positiven Gewinn gibt es nichts zu tun")
expectEqual(GCP.Actionability:Assess(nil).class, "BLOCKED",
    "Auch Unsinn fuehrt zu keiner Empfehlung")

-- TEST ist der Regelfall ohne Belege - nicht "gar nichts". Ein Addon, das bis
-- zum ersten Verkauf nichts vorschlaegt, hilft niemandem zum ersten Verkauf.
H.reset(GCP)
local cold = GCP.Actionability:Assess(opportunity())
expectEqual(cold.class, "TEST", "Ohne jede Beleglage entsteht ein Markttest")
expectEqual(cold.maxUnits, 1, "...und der ist genau ein Stueck")

-- TEST. Markt beobachtet, aber keine eigenen Verkaeufe.
-- Ein tragfaehiger Markt: mehrere Anbieter, nicht ein einzelnes Angebot.
-- Mit nur einem Angebot waere er duenn - und dann ist der eigene Verkauf nicht
-- der Test, sondern das ganze Angebot.
GCP.Market:RecordDepth(23571, {
    { count = 4, buyoutTotal = 4 * 900000 }, { count = 3, buyoutTotal = 3 * 920000 },
    { count = 5, buyoutTotal = 5 * 940000 }, { count = 2, buyoutTotal = 2 * 960000 },
}, H.now - 7200)
GCP.Market:RecordDepth(23571, {
    { count = 3, buyoutTotal = 3 * 900000 }, { count = 3, buyoutTotal = 3 * 920000 },
    { count = 5, buyoutTotal = 5 * 940000 }, { count = 2, buyoutTotal = 2 * 960000 },
}, H.now - 60)
local test = GCP.Actionability:Assess(opportunity())
expectEqual(test.class, "TEST", "Mit beobachtetem Markt entsteht ein Markttest")
expect(test.maxUnits >= 1 and test.maxUnits <= 2,
    "...und der ist ein Stueck, nicht zwanzig")

-- Ein sehr duenner Markt ohne eigene Belege ist kein Testfeld: Dort waere der
-- eigene Verkauf nicht der Versuch, sondern das ganze Angebot.
H.reset(GCP)
GCP.Market:RecordDepth(23571, { { count = 2, buyoutTotal = 2 * 900000 } }, H.now - 7200)
GCP.Market:RecordDepth(23571, { { count = 2, buyoutTotal = 2 * 900000 } }, H.now - 60)
local thin = GCP.Actionability:Assess(opportunity())
expectEqual(thin.class, "SPECULATIVE", "Ein sehr duenner Markt taugt nicht als Testfeld")
expect(thin.speculativeReason:find("dünner Markt") ~= nil, "...und sagt das auch")

-- Ein Test, der zu viel Gold bindet, ist kein Test mehr, sondern eine Wette.
-- Geprueft wird auf einem tragfaehigen Markt, damit wirklich der Betrag den
-- Ausschlag gibt und nicht die Marktbreite.
H.reset(GCP)
GCP.Market:RecordDepth(23571, {
    { count = 4, buyoutTotal = 4 * 9000000 }, { count = 3, buyoutTotal = 3 * 9200000 },
    { count = 5, buyoutTotal = 5 * 9400000 }, { count = 2, buyoutTotal = 2 * 9600000 },
}, H.now - 7200)
GCP.Market:RecordDepth(23571, {
    { count = 4, buyoutTotal = 4 * 9000000 }, { count = 3, buyoutTotal = 3 * 9200000 },
    { count = 5, buyoutTotal = 5 * 9400000 }, { count = 2, buyoutTotal = 2 * 9600000 },
}, H.now - 60)
-- Gemessen am Kapital: 900 g Einsatz bei 3000 g investierbar sind 30 % - fuer
-- einen Versuch ohne jeden Beleg zu viel.
local expensive = GCP.Actionability:Assess(opportunity({
    cost = 9000000, cashRequired = 9000000 }), { investable = 30000000 })
expectEqual(expensive.class, "SPECULATIVE",
    "Ein Teststueck fuer 900 g ist kein Versuch, sondern eine Wette")
expect(expensive.speculativeReason:find("Wette") ~= nil,
    "...und die Begruendung nennt den Anteil am eigenen Kapital als Grund")

-- Derselbe Betrag bei sehr viel mehr Kapital ist keine Wette mehr, sondern
-- eine Randnotiz. Eine feste Grenze waere fuer beide Spieler falsch.
local rich = GCP.Actionability:Assess(opportunity({
    cost = 9000000, cashRequired = 9000000 }), { investable = 2000000000 })
expectEqual(rich.class, "TEST",
    "Derselbe Einsatz ist bei grossem Kapital ein normaler Markttest")

-- PENDING (1.1.0-beta.5). Der Versuch laeuft schon: Das Ergebnis liegt
-- unverkauft im eigenen Auktionshaus. Bis beta.4 kam auf der Startseite
-- derselbe Markttest ein zweites Mal - obwohl das Kapital darin steckt.
H.reset(GCP)
GCP.Market:RecordDepth(23571, {
    { count = 3, buyoutTotal = 3 * 900000 }, { count = 3, buyoutTotal = 3 * 920000 },
    { count = 5, buyoutTotal = 5 * 940000 }, { count = 2, buyoutTotal = 2 * 960000 },
}, H.now - 7200)
GCP.Market:RecordDepth(23571, {
    { count = 3, buyoutTotal = 3 * 900000 }, { count = 3, buyoutTotal = 3 * 920000 },
    { count = 5, buyoutTotal = 5 * 940000 }, { count = 2, buyoutTotal = 2 * 960000 },
}, H.now - 60)
expectEqual(GCP.Actionability:Assess(opportunity()).class, "TEST",
    "Ohne eigene offene Auktion bleibt es ein Markttest")
H.seedOpenAuction(GCP, 23571, 1, 900000)
GCP.Capital:Invalidate()
do
    local pending = GCP.Actionability:Assess(opportunity())
    expectEqual(pending.class, "PENDING",
        "Liegt das Ergebnis schon im eigenen Auktionshaus, laeuft der Versuch bereits")
    expectEqual(pending.maxUnits, 0, "...und es wird nichts nachgelegt")
    expect(pending.pendingReason:find("Ergebnis") ~= nil,
        "...mit einer Begruendung, die das Warten benennt")
    expectEqual(GCP.Actionability:ClassLabel("PENDING"), "läuft bereits",
        "...und die Klasse hat einen Namen in Worten")
    expect(GCP.Actionability:Rank("PENDING") < GCP.Actionability:Rank("TEST"),
        "Eine laufende Chance ist keine Handlungsaufforderung")
end

-- PROVEN. Erst mit eigenen Verkaufsbelegen.
H.reset(GCP)
H.seedTrade(GCP, 23571, { rounds = 6, quantity = 2, buyPrice = 600000,
    sellPrice = 900000, startAt = H.now - 20 * 86400 })
local proven = GCP.Actionability:Assess(opportunity())
expectEqual(proven.class, "PROVEN", "Mit eigenen Verkaufsbelegen wird die Chance bewaehrt")
expect(proven.maxUnits >= 1, "...und traegt eine gemessene Menge")

-- ALLE Bedingungen muessen erfuellt sein. Eine schlechte Sell-through
-- verhindert die starke Empfehlung, auch bei vielen Verkaeufen.
H.reset(GCP)
H.seedTrade(GCP, 23571, { rounds = 6, quantity = 2, buyPrice = 600000,
    sellPrice = 900000, expiries = 14, startAt = H.now - 20 * 86400 })
local weak = GCP.Actionability:Assess(opportunity())
expect(weak.class ~= "PROVEN",
    "Eine schlechte Sell-through verhindert die starke Empfehlung")
expect(#weak.provenBlockers > 0, "...und der Grund steht dabei")

H.section("Actionability: das Pruefszenario aus dem Auftrag")

-- "20x Nischenruestung herstellen" - die eine Empfehlung, die dieses Addon
-- niemals geben darf. Die Rechnung stimmt, der Preis ist belegt, das Kapital
-- reicht, das Angebot ist da. Und trotzdem kauft niemand fuenf Brustplatten.
H.reset(GCP)
H.seedRealm(GCP)
H.money = 500000000                                  -- 50.000 Gold
GCP.Capital:Invalidate()
-- Sogar ein beobachteter Markt und ein riesiges Angebot.
local gearListings = {}
for index = 1, 30 do gearListings[index] = { count = 1, buyoutTotal = 5000000 } end
GCP.Market:RecordDepth(32391, gearListings, H.now - 7200)
GCP.Market:RecordDepth(32391, gearListings, H.now - 60)

local niche = GCP.Actionability:Assess({
    type = "craft", key = "craft:32391", itemID = 32391, saleItemID = 32391,
    title = "Nischenrüstung", cost = 500000, cashRequired = 500000,
    expectedProfit = 4500000,                        -- 450 g Marge je Stueck
    expectedRevenue = 5000000,
    pricePlausible = true, purchasable = true,
})
expect(niche.class ~= "PROVEN",
    "Eine Nischenruestung ohne einen einzigen eigenen Verkauf wird nie bewaehrt")
expect(niche.maxUnits <= GCP.Constants.DEMAND.FIRST_SALE_UNITS,
    "...und traegt hoechstens ein Teststueck, nicht zwanzig")
expect(niche.evidence.structural ~= nil,
    "Das Priorwissen kennt sie - als Einmalkauf ohne Weiterverwendung")
expectEqual(niche.evidence.structural.type, "ONE_TIME",
    "...genau das steht in der Demand Identity")
local nicheText = table.concat(GCP.Actionability:Explain(niche), "\n")
expect(nicheText:find("Markttest") ~= nil or nicheText:find("spekulativ") ~= nil,
    "Die Erklaerung sagt, dass es ein Versuch ist und keine Empfehlung")
H.money = 30000000

H.section("Phase B: Nachfrage begrenzt die Menge")

do
    -- Die Kette min(Kapital, Exposure, Angebot, Zeit, NACHFRAGE). Bis 1.0
    -- fehlte das letzte Glied, und aus "das Gold reicht fuer 20" wurde die
    -- Empfehlung "mach 20".
    local WIDE = 1000000000

    -- Unbekannte Nachfrage: Testmenge, egal wie viel Kapital da ist.
    local sizing = GCP.Capital:SizePosition({
        unitCost = 100000, investable = WIDE, remainingCapital = WIDE,
        exposureBase = WIDE, score = 90, confidence = "high",
        demandCapacity = 1, demandBasis = "Markttest",
    })
    expectEqual(sizing.units, 1, "Unbekannte Nachfrage deckelt auf die Testmenge")
    expectEqual(sizing.limitedBy, "Markttest", "...und sagt auch, warum")

    -- Viel Kapital, wenig Nachfrage: die Nachfrage begrenzt.
    sizing = GCP.Capital:SizePosition({
        unitCost = 10000, investable = WIDE, remainingCapital = WIDE,
        exposureBase = WIDE, score = 90, confidence = "high",
        demandCapacity = 4, demandBasis = "deine Absatzhistorie",
    })
    expectEqual(sizing.units, 4, "Viel Kapital und wenig Nachfrage: die Nachfrage bindet")
    expectEqual(sizing.limitedBy, "deine Absatzhistorie", "...und wird benannt")

    -- Viel Nachfrage, wenig Kapital: das Kapital begrenzt.
    sizing = GCP.Capital:SizePosition({
        unitCost = 100000, investable = WIDE, remainingCapital = 250000,
        exposureBase = WIDE, score = 90, confidence = "high",
        demandCapacity = 40,
    })
    expectEqual(sizing.units, 2, "Viel Nachfrage und wenig Kapital: das Kapital bindet")
    expectEqual(sizing.limitedBy, "verfügbares Kapital", "...und wird benannt")

    -- Viel Nachfrage, wenig Angebot: das Angebot begrenzt.
    sizing = GCP.Capital:SizePosition({
        unitCost = 10000, investable = WIDE, remainingCapital = WIDE,
        exposureBase = WIDE, score = 90, confidence = "high",
        maxUnits = 3, demandCapacity = 40,
    })
    expectEqual(sizing.units, 3, "Viel Nachfrage und wenig Angebot: das Angebot bindet")
    expectEqual(sizing.limitedBy, "Marktangebot", "...und wird benannt")

    -- Ohne Angabe bleibt alles wie vor 1.1: Wer die Grenze nicht mitgibt,
    -- bekommt die alte Rechnung.
    sizing = GCP.Capital:SizePosition({
        unitCost = 10000, investable = WIDE, remainingCapital = WIDE,
        exposureBase = WIDE, score = 90, confidence = "high", maxUnits = 30,
    })
    expect(sizing.units > 4, "Ohne Nachfragegrenze rechnet die Funktion wie bisher")
end

H.section("Phase B: das Pruefszenario im ganzen Ablauf")

do
    -- Der Endpunkt des Auftrags: Kann die Kette noch "20x Nischenruestung"
    -- als Zuteilung ausgeben? Sie bekommt dafuer alles, was sie braucht -
    -- riesiges Kapital, hohe Marge, belegter Preis, dickes Angebot - und
    -- ausdruecklich keinen einzigen eigenen Verkauf.
    H.reset(GCP)
    H.seedRealm(GCP)
    local listings = {}
    for index = 1, 40 do listings[index] = { count = 1, buyoutTotal = 5000000 } end
    GCP.Market:RecordDepth(32391, listings, H.now - 7200)
    GCP.Market:RecordDepth(32391, listings, H.now - 60)

    local niche = {
        key = "craft:32391", type = "craft", itemID = 32391, saleItemID = 32391,
        title = "Nischenrüstung", cost = 500000, cashRequired = 500000,
        expectedProfit = 4500000, expectedRevenue = 5000000,
        opportunityScore = 95, confidence = "high",
        pricePlausible = true, purchasable = true,
        execution = { method = "craft", inputs = { { itemID = 22449, count = 1,
            unitPrice = 500000 } }, sellItemID = 32391, sellCount = 1 },
    }
    local plan = GCP.Capital:Allocate({ niche }, {
        capital = 2000000000,
        snapshot = { availableGold = 2000000000, investedCapital = 0,
            reservedGold = 0, exposureBase = 2000000000, exposure = {} },
    })
    if #plan.allocations > 0 then
        expectEqual(plan.allocations[1].units, 1,
            "Auch mit 200.000 Gold bleibt es bei EINEM Teststueck")
        expect(plan.allocations[1].actionability ~= nil,
            "Die Zuteilung traegt ihre Einordnung mit")
        expect(plan.allocations[1].actionability.class ~= "PROVEN",
            "...und die ist niemals 'bewaehrt' ohne einen eigenen Verkauf")
    else
        expect(#plan.skipped > 0, "Oder sie wird gar nicht erst zugeteilt")
    end

    -- Und dieselbe Chance mit eigener Verkaufshistorie darf mehr.
    H.seedTrade(GCP, 32391, { rounds = 10, quantity = 1, buyPrice = 500000,
        sellPrice = 5000000, startAt = H.now - 30 * 86400 })
    local proven = GCP.Capital:Allocate({ niche }, {
        capital = 2000000000,
        snapshot = { availableGold = 2000000000, investedCapital = 0,
            reservedGold = 0, exposureBase = 2000000000, exposure = {} },
    })
    expect(#proven.allocations > 0, "Mit belegter Historie entsteht eine Zuteilung")
    expect(proven.allocations[1].units > 1,
        "...und sie darf ueber die Testmenge hinausgehen")
    expectEqual(proven.allocations[1].actionability.class, "PROVEN",
        "...weil die Chance jetzt belegt ist")
end

H.section("Phase C: Arbitrage gegen historische Unterbewertung")

do
    H.reset(GCP)
    H.seedRealm(GCP)

    -- ECHTE PREISLUECKE. Ein einzelnes Angebot zu 20 g, das naechste zu 29 g.
    -- Diese Luecke existiert JETZT und ist in Minuten weg.
    GCP.Market:RecordDepth(23425, {
        { count = 2, buyoutTotal = 2 * 200000 },
        { count = 6, buyoutTotal = 6 * 290000 },
        { count = 9, buyoutTotal = 9 * 300000 },
    }, H.now - 60)
    local gap = GCP.Opportunity:ArbitrageFor(23425)
    expect(gap ~= nil, "Eine echte Preisluecke wird erkannt")
    expectEqual(gap.buyPrice, 200000, "...mit dem guenstigsten Angebot als Einstieg")
    expectEqual(gap.quantity, 2, "...und der Menge, die dort liegt")
    expect(gap.sellPrice < gap.nextPrice,
        "Verkauft wird knapp UNTER der naechsten Stufe - wer sie trifft, steht dahinter")
    expect(gap.sellPrice > gap.buyPrice, "...und ueber dem Einstieg")

    -- KEINE LUECKE, nur ein gleichmaessig guenstiger Markt. Wer hier kauft,
    -- wettet auf eine Rueckkehr zum Median - das ist Lageraufbau, keine
    -- Arbitrage.
    H.reset(GCP)
    GCP.Market:RecordDepth(23425, {
        { count = 8, buyoutTotal = 8 * 200000 },
        { count = 9, buyoutTotal = 9 * 205000 },
        { count = 7, buyoutTotal = 7 * 210000 },
    }, H.now - 60)
    expectEqual(GCP.Opportunity:ArbitrageFor(23425), nil,
        "Ein gleichmaessiger Markt ist keine Preisluecke")

    -- Auch eine grosse Luecke ist keine, wenn an der guenstigen Stufe dreissig
    -- Stueck liegen: Dann ist das der Marktpreis und der Rest nur teurer.
    H.reset(GCP)
    GCP.Market:RecordDepth(23425, {
        { count = 30, buyoutTotal = 30 * 200000 },
        { count = 4, buyoutTotal = 4 * 400000 },
    }, H.now - 60)
    expectEqual(GCP.Opportunity:ArbitrageFor(23425), nil,
        "Dreissig Stueck an der guenstigsten Stufe sind der Marktpreis, keine Luecke")

    -- Und eine alte Messung ist keine Luecke mehr: Eine Preisluecke ist eine
    -- Momentaufnahme.
    H.reset(GCP)
    GCP.Market:RecordDepth(23425, {
        { count = 2, buyoutTotal = 2 * 200000 },
        { count = 6, buyoutTotal = 6 * 290000 },
    }, H.now - 3 * 86400)
    expectEqual(GCP.Opportunity:ArbitrageFor(23425), nil,
        "Eine drei Tage alte Messung belegt keine heutige Luecke")

    -- Die Einordnung: Eine Wette auf Rueckkehr ist ohne eigene Verkaufsbelege
    -- kein Markttest, sondern spekulativ - ein Markttest beantwortet eine
    -- Frage, ein Lageraufbau wartet nur.
    H.reset(GCP)
    GCP.Market:RecordDepth(23425, {
        { count = 8, buyoutTotal = 8 * 200000 }, { count = 9, buyoutTotal = 9 * 205000 },
        { count = 7, buyoutTotal = 7 * 210000 }, { count = 5, buyoutTotal = 5 * 215000 },
    }, H.now - 7200)
    GCP.Market:RecordDepth(23425, {
        { count = 8, buyoutTotal = 8 * 200000 }, { count = 9, buyoutTotal = 9 * 205000 },
        { count = 7, buyoutTotal = 7 * 210000 }, { count = 5, buyoutTotal = 5 * 215000 },
    }, H.now - 60)
    local reversion = GCP.Actionability:Assess({
        type = "resale", key = "resale:23425", itemID = 23425, saleItemID = 23425,
        title = "Adamantiterz", cost = 200000, cashRequired = 200000,
        expectedProfit = 60000, expectedRevenue = 260000,
        pricePlausible = true, purchasable = true,
        resaleKind = "reversion",
    })
    expectEqual(reversion.class, "SPECULATIVE",
        "Eine Wette auf Rueckkehr zum Median ist ohne eigene Belege spekulativ")
    expect(reversion.speculativeReason:find("Lageraufbau") ~= nil,
        "...und wird genau so benannt")

    -- Dieselbe Chance als echte Arbitrage darf getestet werden: Hier gibt es
    -- eine Luecke, die man sehen kann.
    local flip = GCP.Actionability:Assess({
        type = "resale", key = "resale:23425", itemID = 23425, saleItemID = 23425,
        title = "Adamantiterz", cost = 200000, cashRequired = 200000,
        expectedProfit = 60000, expectedRevenue = 260000,
        pricePlausible = true, purchasable = true,
        resaleKind = "arbitrage",
    })
    expectEqual(flip.class, "TEST",
        "Eine sichtbare Preisluecke ist ein Geschaeft, keine Wette")
end

H.section("Actionability: Erklaerbarkeit")

H.reset(GCP)
H.seedTrade(GCP, 23425, { rounds = 8, quantity = 4, buyPrice = 40000,
    sellPrice = 60000, startAt = H.now - 25 * 86400 })
local explained = GCP.Actionability:Assess({
    type = "resale", key = "resale:23425", itemID = 23425, saleItemID = 23425,
    title = "Adamantiterz", cost = 40000, cashRequired = 40000,
    expectedProfit = 15000, expectedRevenue = 55000,
    pricePlausible = true, purchasable = true,
})
local lines = GCP.Actionability:Explain(explained)
expect(#lines > 0, "Jede Einordnung laesst sich erklaeren")
local text = table.concat(lines, "\n")
expect(text:find("Belege:") ~= nil, "Die Erklaerung nennt die Beleglage")
expect(text:find("Verkauf") ~= nil, "...und die eigenen Verkaeufe")
expect(text:find("Stück") ~= nil, "...und beantwortet 'warum diese Menge'")

-- Auch eine leere Eingabe erklaert sich, statt abzustuerzen.
expectEqual(#GCP.Actionability:Explain(nil), 0,
    "Ohne Einordnung gibt es eine leere Erklaerung, keinen Absturz")

end)()

-- ===========================================================================
-- PHASE D+E: INCOME TRACKER UND SERVICE SESSIONS (1.1.0)
--
-- Der Spieler verdient sein Gold nicht nur im Auktionshaus. Ein Verzauberer in
-- Shattrath verdient womoeglich das Dreifache einer Farmstunde - und das Addon
-- wusste davon nichts.
-- ===========================================================================

;(function()

H.section("Income: keine Ursache erfinden")

H.reset(GCP)

-- DER WICHTIGSTE TEST DES MODULS. Der Goldstand steigt ohne jeden Kontext.
-- PLAYER_MONEY sagt DASS, nicht WARUM - und daraus wird nichts gemacht.
GCP.Income.lastGold = H.money
H.money = H.money + 500000
expect(GCP.Income:OnMoney(H.now), "Ein Zuwachs wird erfasst")
local events = GCP.Income:GetEvents()
expectEqual(#events, 1, "...als genau ein Ereignis")
expectEqual(events[1].source, "UNKNOWN",
    "Ohne Kontext hat der Zuwachs KEINE Ursache - und bekommt auch keine")
expectEqual(events[1].amount, 500000, "...aber der Betrag stimmt")

-- Ein Rueckgang ist kein Einkommen.
H.money = H.money - 200000
expectEqual(GCP.Income:OnMoney(H.now), false, "Ein Rueckgang ist kein Einkommen")

-- Kleinstbetraege sind Rauschen, kein Ereignis.
H.reset(GCP)
GCP.Income.lastGold = H.money
H.money = H.money + 50
expectEqual(GCP.Income:OnMoney(H.now), false,
    "Ein paar Kupfer sind kein Einkommensereignis")

-- Mit Kontext bekommt derselbe Zuwachs eine Ursache.
H.reset(GCP)
GCP.Income.lastGold = H.money
GCP.Income:SetContext("VENDOR", nil, H.now)
H.money = H.money + 300000
GCP.Income:OnMoney(H.now)
expectEqual(GCP.Income:GetEvents()[1].source, "VENDOR",
    "Mit Kontext bekommt der Zuwachs seine Ursache")

-- Der Kontext gilt nur kurz. Ein Zuwachs eine Minute spaeter gehoert nicht
-- mehr dazu.
H.reset(GCP)
GCP.Income.lastGold = H.money
GCP.Income:SetContext("VENDOR", nil, H.now - 600)
H.money = H.money + 300000
GCP.Income:OnMoney(H.now)
expectEqual(GCP.Income:GetEvents()[1].source, "UNKNOWN",
    "Ein abgelaufener Kontext gilt nicht mehr")

-- Und er gilt fuer genau EINEN Zufluss.
H.reset(GCP)
GCP.Income.lastGold = H.money
GCP.Income:SetContext("QUEST", nil, H.now)
H.money = H.money + 100000
GCP.Income:OnMoney(H.now)
H.money = H.money + 100000
GCP.Income:OnMoney(H.now)
local twice = GCP.Income:GetEvents()
expectEqual(twice[1].source, "QUEST", "Der erste Zufluss hat die Ursache")
expectEqual(twice[2].source, "UNKNOWN", "...der zweite nicht mehr")

H.section("Income: Handel klassifizieren")

H.reset(GCP)

-- HOCH: Der Kunde hat etwas in den SIEBTEN Slot gelegt - den
-- Verzauberungsslot, der ausdruecklich nicht getauscht wird. Das ist kein
-- Muster und keine zeitliche Naehe, das ist die Sache selbst.
H.trade = { partner = "Kunde", targetMoney = 200000, playerMoney = 0,
    targetItems = { [7] = "item:32837" }, playerItems = {} }
local snapshot = GCP.Income:SnapshotTrade(H.now)
expect(snapshot.enchantSlot ~= nil, "Der Verzauberungsslot wird gelesen")
local source, confidence, why = GCP.Income:ClassifyTrade(snapshot, H.now)
expectEqual(source, "SERVICE_ENCHANT", "Ein belegter Slot 7 belegt den Service")
expectEqual(confidence, GCP.Income.CONFIDENCE.HIGH, "...mit hoher Sicherheit")
expect(why:find("Verzauberungsslot") ~= nil, "...und sagt auch warum")

-- MITTEL: Kein Slot 7, aber kurz zuvor wurde verzaubert. Der Client sagt
-- nicht, zu welchem Kunden ein Zauber gehoert - deshalb nie "hoch".
H.reset(GCP)
H.trade = { partner = "Kunde", targetMoney = 200000, playerMoney = 0,
    targetItems = {}, playerItems = {} }
GCP.Income:OnEnchantCast(H.now - 30)
local _, mediumConfidence = GCP.Income:ClassifyTrade(
    GCP.Income:SnapshotTrade(H.now), H.now)
expectEqual(mediumConfidence, GCP.Income.CONFIDENCE.MEDIUM,
    "Zeitliche Naehe zu einem Zauber reicht nur fuer mittlere Sicherheit")

-- NIEDRIG: Gold ueber einen Handel, sonst nichts. Das ist ein HANDEL und
-- ausdruecklich kein Verzauberungsservice - aus einem Gildengeschenk wuerde
-- sonst eine Goldmethode.
H.reset(GCP)
H.trade = { partner = "Gildenkollege", targetMoney = 5000000, playerMoney = 0,
    targetItems = {}, playerItems = {} }
local plainSource, plainConfidence = GCP.Income:ClassifyTrade(
    GCP.Income:SnapshotTrade(H.now), H.now)
expectEqual(plainSource, "TRADE",
    "Ein Goldtransfer ohne Verzauberungskontext ist ein Handel, kein Service")
expectEqual(plainConfidence, GCP.Income.CONFIDENCE.LOW, "...mit niedriger Sicherheit")

-- Ohne erhaltenes Gold gibt es gar kein Einkommen.
H.trade = { partner = "Kunde", targetMoney = 0, playerMoney = 0,
    targetItems = { [7] = "item:32837" }, playerItems = {} }
expectEqual((GCP.Income:ClassifyTrade(GCP.Income:SnapshotTrade(H.now), H.now)),
    "UNKNOWN", "Ohne erhaltenes Gold ist ein Handel kein Einkommen")

H.section("Income: Kundenmaterial ist kein Einkommen")

H.reset(GCP)

-- Der Kunde bringt Materialien UND 20 g Trinkgeld. Das Einkommen ist 20 g -
-- nicht 20 g plus Materialwert. Die Materialien waren nie sein Gold.
local customerTrade = {
    targetMoney = 200000,
    playerMoney = 0,
    targetItems = { { slot = 1, link = "item:22449" }, { slot = 2, link = "item:22445" } },
    playerItems = {},
}
local value = GCP.Income:ValueOfTrade(customerTrade)
expectEqual(value.cashIncome, 200000, "Das Einkommen ist genau das erhaltene Gold")
expectEqual(value.customerMaterials, 2, "Die Kundenmaterialien werden gezaehlt ...")
expectEqual(value.ownMaterialValue, 0, "...aber nicht als eigener Einsatz bewertet")
expectEqual(value.economicProfit, 200000,
    "Der wirtschaftliche Gewinn ist der volle Betrag - es kostete nichts")

-- Der andere Fall: Der Spieler nimmt EIGENE Materialien. Dann ist ihr
-- Marktwert wirtschaftliche Kosten - dieselbe Trennung wie ueberall.
local ownTrade = {
    targetMoney = 1000000,
    playerMoney = 0,
    targetItems = {},
    playerItems = { { slot = 1, link = "item:22456" } },
}
local ownValue = GCP.Income:ValueOfTrade(ownTrade)
expectEqual(ownValue.cashIncome, 1000000, "Der Cashflow ist der volle Betrag ...")
expect(ownValue.ownMaterialValue > 0, "...die eigenen Materialien haben aber einen Wert")
expect(ownValue.economicProfit < ownValue.cashIncome,
    "...und der wirtschaftliche Gewinn ist entsprechend kleiner")

H.section("Income: der ganze Handelsablauf")

H.reset(GCP)
GCP.Income.lastGold = H.money

-- TRADE_CLOSED ist KEIN Abschluss - es feuert auch beim Abbrechen. Ein
-- abgebrochener Handel darf nichts hinterlassen.
H.trade = { partner = "Kunde", targetMoney = 200000, playerMoney = 0,
    targetItems = { [7] = "item:32837" }, playerItems = {} }
GCP.Income:OnTradeAccepted(H.now)
expect(GCP.Income.pendingTrade ~= nil, "Beim Bestaetigen entsteht der Abzug")
GCP.Income:OnTradeClosed()
expectEqual(GCP.Income.pendingTrade, nil, "Ein abgebrochener Handel hinterlaesst nichts")
H.money = H.money + 200000
GCP.Income:OnMoney(H.now)
expectEqual(GCP.Income:GetEvents()[1].source, "UNKNOWN",
    "...und der Goldzuwachs danach hat keine Ursache")

-- Der belegte Ablauf: bestaetigen, Systemmeldung, Gold.
H.reset(GCP)
GCP.Income.lastGold = H.money
H.trade = { partner = "Kunde", targetMoney = 200000, playerMoney = 0,
    targetItems = { [7] = "item:32837" }, playerItems = {} }
GCP.Income:OnTradeAccepted(H.now)
GCP.Income:OnTradeCompleted(H.now)
H.money = H.money + 200000
GCP.Income:OnMoney(H.now)
local serviceEvent = GCP.Income:GetEvents()[1]
expectEqual(serviceEvent.source, "SERVICE_ENCHANT",
    "Der belegte Ablauf erzeugt ein Service-Ereignis")
expectEqual(serviceEvent.confidenceLabel, "high", "...mit hoher Sicherheit")
expectEqual(serviceEvent.amount, 200000, "...und dem tatsaechlich erhaltenen Betrag")

-- ---------------------------------------------------------------------------
-- DERSELBE ABLAUF, ABER UEBER DIE EREIGNISSE (1.1.0-beta.5)
--
-- Alle Tests darueber rufen Income:OnTradeAccepted und OnTradeCompleted
-- direkt auf. Genau dadurch blieb bis beta.4 unentdeckt, dass der
-- Ereignisverteiler in Core.lua nur arg1 entgegennahm und arg2/arg3 als nil
-- weiterreichte: TRADE_ACCEPT_UPDATE prueft (arg1 == 1 and arg2 == 1) und war
-- damit nie erfuellt. Im Spiel wurde nie ein Handelsabzug genommen, jedes
-- Trinkgeld blieb UNKNOWN, und die Servicesitzung endete ohne einen einzigen
-- Kunden.
--
-- Dieser Test geht deshalb ausdruecklich durch H.fire.
-- ---------------------------------------------------------------------------
H.section("Income: der Ablauf ueber die echten Ereignisse")

H.reset(GCP)
GCP.Income.lastGold = H.money

-- Eine gewirkte Verzauberung. Sie ist der Kontext, nicht das Einkommen.
H.fire("UNIT_SPELLCAST_SUCCEEDED", "player", "cast-1", 13898)
expect(GCP.Income.lastEnchantAt ~= nil,
    "Eine gewirkte Verzauberung wird ueber das Ereignis erkannt")

-- Der Kunde legt sein Item in den Verzauberungsslot und zahlt 20 g.
H.trade = { partner = "Kunde", targetMoney = 200000, playerMoney = 0,
    targetItems = { [7] = "item:32837" }, playerItems = {} }
H.fire("TRADE_ACCEPT_UPDATE", 1, 1)
expect(GCP.Income.pendingTrade ~= nil,
    "Beidseitiges Bestaetigen nimmt den Handelsabzug - arg2 muss ankommen")
H.fire("UI_INFO_MESSAGE", 0, ERR_TRADE_COMPLETE)
H.money = H.money + 200000
H.fire("PLAYER_MONEY")
do
    local event = GCP.Income:GetEvents()[1]
    expect(event ~= nil, "Der Ablauf erzeugt ein Ereignis")
    expectEqual(event and event.source, "SERVICE_ENCHANT",
        "...und es ist als Verzauberungsservice erkannt")
    expectEqual(event and event.amount, 200000, "...mit dem erhaltenen Betrag")
end

-- ---------------------------------------------------------------------------
-- DAS GOLD KOMMT VOR DER SYSTEMMELDUNG (Fehler bis 1.1.0-beta.5)
--
-- In TBC feuert PLAYER_MONEY regelmaessig VOR ERR_TRADE_COMPLETE. Dann gab es
-- zum Zeitpunkt des Zuflusses noch keinen Kontext, und das Trinkgeld wurde als
-- UNKNOWN verbucht - eine laufende Servicesitzung sah davon nichts. Gemeldet
-- wurde das mit einem Arbeitsauftrag ueber 20 g, der im Fenster als 0.00 g
-- stand.
--
-- Der Kopf des Moduls kennt die Regel seit jeher: Ein Handel gilt als erfolgt,
-- wenn die Systemmeldung kam ODER das Gold tatsaechlich mehr wurde. Nur die
-- zweite Haelfte war nie umgesetzt.
-- ---------------------------------------------------------------------------
H.reset(GCP)
GCP.Income.lastGold = H.money
do
    GCP.Activity:StartManual("service.enchant", H.now)
    H.trade = { partner = "Kunde", targetMoney = 200000, playerMoney = 0,
        targetItems = { [7] = "item:32837" }, playerItems = {} }
    H.fire("TRADE_ACCEPT_UPDATE", 1, 1)
    -- Erst das Gold ...
    H.money = H.money + 200000
    H.fire("PLAYER_MONEY")
    local event = GCP.Income:GetEvents()[1]
    expectEqual(event and event.source, "SERVICE_ENCHANT",
        "Der Goldzuwachs allein belegt den Handel bereits")
    expectEqual(GCP.Activity:Current().gross, 200000,
        "...und landet in der laufenden Sitzung")
    -- ... und danach die Systemmeldung. Sie darf nichts verdoppeln.
    H.fire("UI_INFO_MESSAGE", 0, ERR_TRADE_COMPLETE)
    expectEqual(#GCP.Income:GetEvents(), 1,
        "Die nachgereichte Systemmeldung bucht nicht ein zweites Mal")
    expectEqual(GCP.Activity:Current().gross, 200000, "...und zaehlt nicht doppelt")
    GCP.Activity:Stop("Test", H.now)
end

-- ---------------------------------------------------------------------------
-- DER HANDEL OHNE (1,1) (Fehler bis 1.1.0-beta.5)
--
-- Bis beta.5 entstand der Handelsabzug ausschliesslich bei
-- TRADE_ACCEPT_UPDATE mit BEIDEN Flags auf 1. Diesen Moment meldet der Client
-- oft gar nicht - erst recht nicht, wenn ein Addon den Handel selbst ausfuehrt
-- (Pro Enchanters ruft PEdoTrade). Im Protokoll des Nutzers standen daraufhin
-- 84 Zufluesse ohne Ursache und zwei mit.
--
-- Hier laeuft derselbe Handel, ohne dass (1,1) je gemeldet wird: Der Kunde
-- legt Gold hinein, der Verzauberungsslot wird belegt, die Seite bestaetigt -
-- und danach kommt das Gold.
-- ---------------------------------------------------------------------------
H.reset(GCP)
GCP.Income.lastGold = H.money
do
    GCP.Activity:StartManual("service.enchant", H.now)
    H.trade = { partner = "Kunde", targetMoney = 50000, playerMoney = 0,
        targetItems = { [7] = "item:32837" }, playerItems = {} }
    -- Nur Inhaltsaenderungen und eine einseitige Bestaetigung.
    H.fire("TRADE_MONEY_CHANGED")
    H.fire("TRADE_TARGET_ITEM_CHANGED")
    H.fire("TRADE_ACCEPT_UPDATE", 0, 1)
    expect(GCP.Income.pendingTrade ~= nil,
        "Der Abzug entsteht schon bei einer Inhaltsaenderung")
    expectEqual(GCP.Income.pendingTrade.enchantSlot ~= nil, true,
        "...und sieht den belegten Verzauberungsslot")

    H.money = H.money + 50000
    H.fire("PLAYER_MONEY")
    do
        local event = GCP.Income:GetEvents()[1]
        expectEqual(event and event.source, "SERVICE_ENCHANT",
            "Auch ohne gemeldetes (1,1) wird der Verzauberungsservice erkannt")
        expectEqual(GCP.Activity:Current().gross, 50000,
            "...und das Trinkgeld landet in der Sitzung")
        expectEqual(GCP.Activity:Current().events, 1, "...als ein Kunde")
    end
    GCP.Activity:Stop("Test", H.now)
end

-- Ein spaeterer, leerer Abzug darf einen guten nicht ueberschreiben: Beim
-- Zugehen des Fensters antwortet die API nicht mehr.
H.reset(GCP)
GCP.Income.lastGold = H.money
do
    H.trade = { partner = "Kunde", targetMoney = 50000, playerMoney = 0,
        targetItems = { [7] = "item:32837" }, playerItems = {} }
    H.fire("TRADE_MONEY_CHANGED")
    H.trade = { partner = nil, targetMoney = 0, playerMoney = 0,
        targetItems = {}, playerItems = {} }
    H.fire("TRADE_ACCEPT_UPDATE", 1, 1)
    expectEqual(GCP.Income.pendingTrade.targetMoney, 50000,
        "Der inhaltsreichere Abzug bleibt stehen")
end

-- Ein ABGEBROCHENER Handel hinterlaesst weiterhin nichts: Ohne erhaltenes Gold
-- im Abzug gibt es auch keinen Beleg.
H.reset(GCP)
GCP.Income.lastGold = H.money
do
    H.trade = { partner = "Kunde", targetMoney = 0, playerMoney = 0,
        targetItems = {}, playerItems = {} }
    H.fire("TRADE_ACCEPT_UPDATE", 1, 1)
    H.money = H.money + 200000
    H.fire("PLAYER_MONEY")
    expectEqual(GCP.Income:GetEvents()[1].source, "UNKNOWN",
        "Ein Handel ohne erhaltenes Gold belegt keinen Zufluss")
end

-- Der erste Zufluss nach dem Einloggen ging verloren, weil OnMoney seinen
-- Bezugsstand erst beim ersten Aufruf anlegte.
H.reset(GCP)
do
    GCP.Income.lastGold = nil
    expect(GCP.Income:Prime(), "Der Bezugsstand laesst sich setzen")
    H.money = H.money + 150000
    GCP.Income:OnMoney(H.now)
    expectEqual(#GCP.Income:GetEvents(), 1,
        "Nach dem Einloggen zaehlt schon der erste Zufluss")
end

-- Und derselbe Ablauf fuellt eine laufende Sitzung. Ohne Ertrag verwirft
-- Activity:Stop sie als "zu kurz oder ohne Ertrag" - genau das war der
-- gemeldete Fehler.
H.reset(GCP)
GCP.Income.lastGold = H.money
GCP.Activity:StartManual("service.enchant", H.now)
expect(GCP.Activity:Current() ~= nil, "Die Servicesitzung laeuft")
for round = 1, 2 do
    H.trade = { partner = "Kunde " .. round, targetMoney = 150000,
        playerMoney = 0, targetItems = { [7] = "item:32837" }, playerItems = {} }
    H.fire("TRADE_ACCEPT_UPDATE", 1, 1)
    H.fire("UI_INFO_MESSAGE", 0, ERR_TRADE_COMPLETE)
    H.money = H.money + 150000
    H.fire("PLAYER_MONEY")
    H.advance(600)
end
do
    local session = GCP.Activity:Current()
    expectEqual(session and session.events, 2, "Zwei Kunden werden gezaehlt")
    expectEqual(session and session.gross, 300000, "...und ihr Gold zusammengerechnet")
    local record = GCP.Activity:Stop("Test", H.now)
    expect(record ~= nil, "Die beendete Sitzung wird aufgezeichnet statt verworfen")
    expectEqual(record and record.g, 300000, "...mit dem gemessenen Bruttoertrag")
    expect(record and record.m > 0, "...und der gemessenen Zeit")
end

H.section("Activity: Service Sessions")

H.reset(GCP)

-- Ein einzelnes Trinkgeld startet KEINE Sitzung. Eines allein ist ein
-- Gefallen, kein Geschaeft - und eine Rate aus einer Beobachtung waere keine.
GCP.Activity:OnIncome({ source = "SERVICE_ENCHANT", amount = 120000,
    confidence = GCP.Income.CONFIDENCE.HIGH, timestamp = H.now - 3600 })
expectEqual(GCP.Activity:Current(), nil,
    "Ein einzelnes Trinkgeld startet keine Sitzung")

-- Zwei in kurzer Folge schon.
GCP.Activity:OnIncome({ source = "SERVICE_ENCHANT", amount = 200000,
    confidence = GCP.Income.CONFIDENCE.HIGH, timestamp = H.now - 3500 })
local session = GCP.Activity:Current()
expect(session ~= nil, "Zwei Ereignisse in kurzer Folge starten eine Sitzung")
expectEqual(session.kind, "service.enchant", "...der richtigen Art")
expectEqual(session.startedAt, H.now - 3600,
    "Die Sitzung beginnt beim ERSTEN Ereignis, nicht beim zweiten")

-- Ein Handel unbekannter Herkunft startet nie eine Servicesitzung.
H.reset(GCP)
for index = 1, 4 do
    GCP.Activity:OnIncome({ source = "TRADE", amount = 500000,
        confidence = GCP.Income.CONFIDENCE.LOW, timestamp = H.now - index * 60 })
end
expectEqual(GCP.Activity:Current(), nil,
    "Handel unbekannter Herkunft startet keine Servicesitzung")

-- ---------------------------------------------------------------------------
-- PAUSE (1.1.0-beta.5)
--
-- Wer zwischendurch raidet, bietet in dieser Zeit keinen Service an. Eine
-- Rate, die diese Minuten mitzaehlt, ist zu niedrig - eine Pause, die den
-- Ertrag weiterzaehlt, zu hoch.
-- ---------------------------------------------------------------------------
H.section("Activity: Pause")

H.reset(GCP)
do
    GCP.Activity:StartManual("service.enchant", H.now)
    H.advance(600)                                  -- 10 Minuten Stand
    GCP.Activity:Tick(H.now)
    local before = GCP.Activity:LiveStats(H.now)
    expectNear(before.seconds, 600, 5, "Nach zehn Minuten stehen zehn Minuten da")
    expectEqual(before.paused, false, "...und die Sitzung laeuft")

    expect(GCP.Activity:Pause(H.now), "Die Sitzung laesst sich pausieren")
    expect(GCP.Activity:IsPaused(), "...und gilt dann als pausiert")
    expect(not GCP.Activity:Pause(H.now), "Zweimal pausieren tut nichts")

    H.advance(1800)                                 -- eine halbe Stunde Pause
    GCP.Activity:Tick(H.now)
    local paused = GCP.Activity:LiveStats(H.now)
    expectNear(paused.seconds, 600, 5, "Waehrend der Pause steht die Uhr")
    expectNear(paused.pausedSeconds, 1800, 5, "...und die Pausendauer laeuft mit")

    expect(GCP.Activity:Resume(H.now), "Die Sitzung laesst sich fortsetzen")
    expect(not GCP.Activity:IsPaused(), "...und laeuft danach wieder")
    H.advance(300)
    GCP.Activity:Tick(H.now)
    local after = GCP.Activity:LiveStats(H.now)
    expectNear(after.seconds, 900, 10,
        "Nach der Pause zaehlt die Uhr weiter, ohne die Pause nachzuholen")

    -- Eine pausierte Sitzung laeuft nicht leer - sie steht.
    GCP.Activity:Pause(H.now)
    H.advance(3 * 3600)
    expect(not GCP.Activity:CheckIdle(H.now),
        "Eine pausierte Sitzung endet nicht von selbst wegen Leerlaufs")

    -- Ein zahlender Kunde waehrend der Pause heisst: Es geht wieder los.
    GCP.Activity:OnIncome({ source = "SERVICE_ENCHANT", amount = 250000,
        confidence = GCP.Income.CONFIDENCE.HIGH, timestamp = H.now })
    expect(not GCP.Activity:IsPaused(),
        "Ein Kunde waehrend der Pause setzt die Sitzung fort")
    expectEqual(GCP.Activity:Current().gross, 250000, "...und sein Gold zaehlt")

    -- Und die pausierte Zeit steht am Ende NICHT in der Sitzung.
    H.advance(600)
    local record = GCP.Activity:Stop("Test", H.now)
    expect(record ~= nil, "Die Sitzung wird aufgezeichnet")
    expect(record and record.m < 60,
        "Die aufgezeichnete Dauer enthaelt die dreieinhalb Stunden Pause nicht")
end

-- Die Uhr als Text.
expectEqual(GCP.Activity:FormatDuration(0), "00:00", "Null Sekunden sind 00:00")
expectEqual(GCP.Activity:FormatDuration(75), "01:15", "75 Sekunden sind 01:15")
expectEqual(GCP.Activity:FormatDuration(3725), "1:02:05",
    "Ueber einer Stunde kommt die Stunde dazu")

-- ---------------------------------------------------------------------------
-- PORTALSERVICE (1.1.0-beta.5)
--
-- Derselbe Stand, anderer Zauber: Ein Magier stellt Portale, verbraucht dabei
-- eine Rune und bekommt Trinkgeld. Zahlt niemand, ist die Rune trotzdem weg -
-- und das gehoert in die Messung, nicht daneben.
-- ---------------------------------------------------------------------------
H.section("Activity: Portalservice")

H.reset(GCP)
do
    H.spells[10059] = "Portal: Sturmwind"
    H.spells[3561] = "Teleportieren: Sturmwind"
    expectEqual(GCP:ServiceSpellKind(nil, 10059), "portal",
        "Ein Portalzauber wird als Portal erkannt")
    expectEqual(GCP:ServiceSpellKind(nil, 3561), "portal",
        "Ein Teleport ebenso")
    expectEqual(GCP:ServiceSpellKind(nil, 13898), "enchant",
        "Eine Verzauberung bleibt eine Verzauberung")
    expectEqual(GCP:ServiceSpellKind(nil, 2018), nil,
        "Schmiedekunst ist keine Dienstleistung an einem Kunden")

    -- Der Portalkunde zahlt: Das Ereignis ist ein Portalservice.
    GCP.Income.lastGold = H.money
    H.fire("UNIT_SPELLCAST_SUCCEEDED", "player", "cast-p", 10059)
    H.trade = { partner = "Kunde", targetMoney = 100000, playerMoney = 0,
        targetItems = {}, playerItems = {} }
    H.fire("TRADE_ACCEPT_UPDATE", 1, 1)
    H.fire("UI_INFO_MESSAGE", 0, ERR_TRADE_COMPLETE)
    H.money = H.money + 100000
    H.fire("PLAYER_MONEY")
    do
        local event = GCP.Income:GetEvents()[1]
        expectEqual(event and event.source, "SERVICE_PORTAL",
            "Gold nach einem Portal ist ein Portalservice")
        expectEqual(event and event.amount, 100000, "...mit dem gezahlten Betrag")
    end
end

-- Und beides landet in DERSELBEN Sitzung: Es ist ein Stand, nicht zwei.
H.reset(GCP)
do
    GCP.Activity:StartManual("service.enchant", H.now)
    GCP.Activity:OnIncome({ source = "SERVICE_PORTAL", amount = 100000,
        confidence = GCP.Income.CONFIDENCE.MEDIUM, timestamp = H.now })
    GCP.Activity:OnIncome({ source = "SERVICE_ENCHANT", amount = 200000,
        confidence = GCP.Income.CONFIDENCE.HIGH, timestamp = H.now })
    expectEqual(GCP.Activity:Current().gross, 300000,
        "Portal und Verzauberung zaehlen in dieselbe Sitzung")
    expectEqual(GCP.Activity:Current().events, 2, "...als zwei Kunden")

    -- Blosses Handelsgold zaehlt in einer SELBST gestarteten Sitzung mit: Wer
    -- sie gestartet hat, hat gesagt, dass er gerade anbietet.
    GCP.Activity:OnIncome({ source = "TRADE", amount = 50000,
        confidence = GCP.Income.CONFIDENCE.LOW, timestamp = H.now })
    expectEqual(GCP.Activity:Current().gross, 350000,
        "Handelsgold zaehlt in einer selbst gestarteten Sitzung mit")
    GCP.Activity:Stop("Test", H.now + 1200)
end

-- Eine automatisch erkannte Sitzung nimmt blosses Handelsgold NICHT: Das waere
-- eine Vermutung auf einer Vermutung.
H.reset(GCP)
do
    GCP.Activity:Start("service.enchant", H.now)
    GCP.Activity:OnIncome({ source = "TRADE", amount = 50000,
        confidence = GCP.Income.CONFIDENCE.LOW, timestamp = H.now })
    expectEqual(GCP.Activity:Current().gross, 0,
        "In einer erkannten Sitzung bleibt Handelsgold aussen vor")
    GCP.Activity:Stop("Test", H.now + 1200)
end

-- Ohne Ertrag, aber mit belegten Kosten: Die Sitzung wird trotzdem
-- aufgezeichnet. Eine Stunde Portale fuer nichts ist eine Messung.
H.reset(GCP)
do
    GCP.Activity:StartManual("service.enchant", H.now)
    GCP.Activity:AddCost(40000, H.now)
    -- Der Herzschlag haelt das Lebenszeichen wach; ohne ihn endet die
    -- gerechnete Zeit fuenf Minuten nach dem letzten Ereignis (GRACE_SECONDS).
    H.advance(1800)
    GCP.Activity:Tick(H.now)
    local record = GCP.Activity:Stop("Test", H.now)
    expect(record ~= nil, "Eine Sitzung mit Kosten und ohne Ertrag zaehlt mit")
    expectEqual(record and record.g, 0, "...der Ertrag ist null")
    expectEqual(record and record.c, 40000, "...und die Kosten stehen da")
    local stats = GCP.Activity:MethodStats("service.enchant")
    expect(stats ~= nil and stats.medianGoldPerHour < 0,
        "...und die Stundenrate ist entsprechend negativ")
end

H.section("Activity: Gold je Stunde")

H.reset(GCP)

-- Eine Sitzung von Hand: 60 Minuten, 240 g. Das sind 240 g/h.
--
-- lastSeenAt steht auf jetzt, weil in der Wirklichkeit der Herzschlag
-- waehrend der Sitzung laeuft. Ohne Lebenszeichen wuerde nur bis zum letzten
-- bekannten Zeitpunkt gerechnet - genau so soll es sein.
GCP.Activity:Start("service.enchant", H.now - 3600)
local live = GCP.Activity:Current()
live.gross = 2400000
live.events = 12
live.lastEventAt = H.now
live.lastSeenAt = H.now
local record = GCP.Activity:Stop("fertig", H.now)
expect(record ~= nil, "Eine abgeschlossene Sitzung wird aufgeschrieben")
expectEqual(record.g, 2400000, "...mit dem erloesten Gold")
expectNear(record.m, 60, 0.5, "...und der aktiven Zeit in Minuten")

local stats = GCP.Activity:MethodStats("service.enchant")
expect(stats ~= nil, "Daraus entsteht eine Methodenstatistik")
expectNear(stats.medianGoldPerHour, 2400000, 1000, "240 g in 60 Minuten sind 240 g/h")
expectEqual(stats.confidence, "none", "Eine einzige Sitzung ist noch keine Datenlage")

-- Eine zu kurze Sitzung ist keine Messung. Zwei Minuten mit einem
-- grosszuegigen Trinkgeld waeren 3000 g/h.
H.reset(GCP)
GCP.Activity:Start("service.enchant", H.now - 120)
local short = GCP.Activity:Current()
short.gross = 1000000
short.lastSeenAt = H.now
expectEqual((GCP.Activity:Stop("fertig", H.now)), nil,
    "Eine zu kurze Sitzung wird nicht gewertet")

-- Und eine ohne Ertrag ebensowenig.
GCP.Activity:Start("service.enchant", H.now - 3600)
local empty = GCP.Activity:Current()
empty.lastSeenAt = H.now
expectEqual((GCP.Activity:Stop("fertig", H.now)), nil,
    "Eine Sitzung ohne Ertrag ist keine Messung")

H.section("Activity: Median schuetzt vor Ausreissern")

H.reset(GCP)

-- Sieben normale Sitzungen und ein einzelnes riesiges Trinkgeld. Der Median
-- bleibt bei den normalen - genau dafuer ist er da.
local function seedSession(gold, minutes, offsetDays)
    local store = GCP.Activity:EnsureStore()
    store.sessions[#store.sessions + 1] = {
        k = "service.enchant", s = H.now - offsetDays * 86400,
        e = H.now - offsetDays * 86400 + minutes * 60,
        m = minutes, g = gold, c = 0, n = 10, h = 19, w = 3,
    }
end
for index = 1, 7 do seedSession(2200000, 60, index) end
seedSession(50000000, 60, 8)          -- ein 5000-g-Trinkgeld
local robust = GCP.Activity:MethodStats("service.enchant")
expectNear(robust.medianGoldPerHour, 2200000, 50000,
    "Ein einzelnes riesiges Trinkgeld verschiebt den Median nicht")
expectEqual(robust.sessions, 8, "...alle Sitzungen zaehlen trotzdem mit")
expectEqual(robust.confidence, "medium", "Acht Sitzungen sind eine mittlere Datenlage")

H.section("Activity: Tageszeit nur bei genug Daten")

H.reset(GCP)
-- Drei Sitzungen um 19 Uhr sind keine Aussage ueber 19 Uhr.
for index = 1, 3 do seedSession(2200000, 60, index) end
expectEqual(GCP.Activity:ContextStats("service.enchant", 19), nil,
    "Drei Sitzungen sind keine Aussage ueber ein Zeitfenster")
-- Ab der Mindeststichprobe schon.
for index = 4, 8 do seedSession(2600000, 60, index) end
local evening = GCP.Activity:ContextStats("service.enchant", 19)
expect(evening ~= nil, "Mit genug Sitzungen entsteht eine Aussage ueber das Zeitfenster")
expect(evening.sessions >= 5, "...auf Basis der Sitzungen in genau diesem Fenster")

H.section("Activity: Methodenvergleich")

H.reset(GCP)
expectEqual(#GCP.Activity:AllMethods(), 0,
    "Ohne eigene Sitzungen gibt es keine Methode - und keine Gold/h")
expect(GCP.Activity:SummaryText():find("Noch keine") ~= nil,
    "...und einen Satz statt einer Null")

for index = 1, 8 do seedSession(2200000, 60, index) end
local methods = GCP.Activity:AllMethods()
expect(#methods >= 1, "Mit Sitzungen entsteht eine vergleichbare Methode")
expectEqual(methods[1].kind, "service.enchant", "...unter ihrem Namen")
expect(methods[1].label:find("Verzauber") ~= nil, "...mit lesbarer Bezeichnung")

end)()

-- ===========================================================================
-- PHASE F+G: METHODENVERGLEICH UND STARTSEITE (1.1.0)
--
-- Die Startseite beantwortete bis 1.0 "welches Item hat den hoechsten Score?".
-- Die Frage lautet "was soll ich jetzt tun?" - und darauf ist "gerade nichts"
-- eine gueltige Antwort.
-- ===========================================================================

;(function()

H.section("Phase H: preisabhaengige Nachfrage")

do
    H.reset(GCP)
    -- Eine Preisreihe, damit es ueberhaupt eine Vergleichszahl gibt.
    H.seedHistory(GCP, 23425, 50000, 40, 60, 0.02)

    -- Guenstig eingestellt: geht durch. Teuer eingestellt: laeuft ab.
    -- Genau diese Aussage steckt seit jeher in der Bilanz und wurde nie
    -- gefragt.
    local store = GCP.Ledger:EnsureStore()
    for index = 1, 8 do
        local at = H.now - (20 - index) * 86400
        GCP.Ledger:RecordAuctionPosted({ itemID = 23425, quantity = 1,
            unitPrice = 42000, deposit = 500, durationHours = 12, timestamp = at })
        local _, quality = GCP.Ledger:MatchSale(store, 23425, 42000)
        GCP.Ledger:RecordSale({ itemID = 23425, quantity = 1, totalGross = 42000,
            source = "ah", timestamp = at + 3600, holdHours = 1,
            matchQuality = quality })
    end
    for index = 1, 6 do
        local at = H.now - (12 - index) * 86400
        GCP.Ledger:RecordAuctionPosted({ itemID = 23425, quantity = 1,
            unitPrice = 75000, deposit = 500, durationHours = 12, timestamp = at })
        GCP.Ledger:RecordAuctionExpired({ itemID = 23425, quantity = 1,
            timestamp = at + 43200 })
    end

    local bands = GCP.Ledger:PriceBandStats(23425)
    expect(bands ~= nil, "Aus den eigenen Ereignissen entstehen Preisbaender")
    local cheap, expensive = nil, nil
    for _, band in ipairs(bands) do
        if band.max <= 0.90 then cheap = band end
        if band.max == math.huge then expensive = band end
    end
    expect(cheap ~= nil and cheap.sellThrough ~= nil,
        "Das guenstige Band hat eine belastbare Rate")
    expectNear(cheap.sellThrough, 1.0, 0.01,
        "Unter Marktpreis eingestellt geht alles durch")
    expect(expensive ~= nil and expensive.sellThrough ~= nil,
        "Das teure Band ebenfalls")
    expectNear(expensive.sellThrough, 0.0, 0.01,
        "Weit ueber Marktpreis eingestellt geht nichts durch")

    local lines = table.concat(GCP.Ledger:PriceBandLines(23425), "\n")
    expect(lines:find("gehen durch") ~= nil, "Die Aussage steht auch in Worten da")
    expect(lines:find("n=") ~= nil, "...mit der Stichprobe daneben")

    -- Ohne genuegend Faelle je Band gibt es KEINE Aussage ueber dieses Band.
    H.reset(GCP)
    H.seedHistory(GCP, 23425, 50000, 40, 60, 0.02)
    local few = GCP.Ledger:EnsureStore()
    for index = 1, 2 do
        local at = H.now - index * 86400
        GCP.Ledger:RecordAuctionPosted({ itemID = 23425, quantity = 1,
            unitPrice = 42000, deposit = 500, durationHours = 12, timestamp = at })
        local _, quality = GCP.Ledger:MatchSale(few, 23425, 42000)
        GCP.Ledger:RecordSale({ itemID = 23425, quantity = 1, totalGross = 42000,
            source = "ah", timestamp = at + 3600, holdHours = 1,
            matchQuality = quality })
    end
    expectEqual(GCP.Ledger:PriceBandStats(23425), nil,
        "Zwei Auktionen sind keine Aussage ueber ein Preisband")

    -- Und ohne Preisreihe gibt es keine Vergleichszahl - also auch keine
    -- Baender. Gegen den HEUTIGEN Preis zu vergleichen waere bequemer und
    -- wuerde eine andere Frage beantworten.
    H.reset(GCP)
    H.seedTrade(GCP, 23425, { rounds = 8, quantity = 1, buyPrice = 40000,
        sellPrice = 42000, startAt = H.now - 20 * 86400 })
    expectEqual(GCP.Ledger:PriceBandStats(23425), nil,
        "Ohne gespeicherte Preisreihe gibt es keinen Vergleichsmassstab")
end

H.section("Recommendation: nichts tun ist eine Antwort")

H.reset(GCP)

local nothing = GCP.Recommendation:Best({ allocations = {} })
expectEqual(nothing.kind, "NONE", "Ohne Kandidaten gibt es keine Empfehlung")
expectEqual(nothing.headline, "DERZEIT KEINE ÜBERZEUGENDE AKTION",
    "...und die Ueberschrift sagt das auch")
local nothingText = table.concat(GCP.Recommendation:Explain(nothing), "\n")
expect(nothingText:find("besser als eine schlechte Empfehlung") ~= nil,
    "Die Begruendung steht dazu")

-- Eine spekulative Zuteilung ist kein Kandidat: Sie ist rechnerisch
-- interessant und ohne Beleg.
local speculativeOnly = GCP.Recommendation:Best({ allocations = { {
    key = "x", title = "Spekulativ", units = 1, capital = 100000,
    expectedProfit = 50000,
    actionability = { class = "SPECULATIVE" },
} } })
expectEqual(speculativeOnly.kind, "NONE",
    "Eine spekulative Chance ist keine Handlungsempfehlung")

H.section("Recommendation: bewaehrt schlaegt Versuch")

H.reset(GCP)

local function itemAllocation(key, class, profit, units, minutes)
    return {
        key = key, title = "Item " .. key, units = units or 1,
        capital = 200000, cashRequired = 200000, expectedProfit = profit,
        confidence = "high", minutes = minutes,
        actionability = { class = class, capacity = { units = units or 1,
            basis = "Testlage" }, reasons = {} },
    }
end

local both = GCP.Recommendation:Best({ allocations = {
    itemAllocation("test", "TEST", 900000),
    itemAllocation("proven", "PROVEN", 300000),
} })
expectEqual(both.kind, "ITEM", "Es entsteht eine Item-Empfehlung")
expectEqual(both.choice.key, "proven",
    "Eine bewaehrte Chance schlaegt einen Markttest - auch mit weniger Gewinn")
expectEqual(both.headline, "BESTE KAPITALCHANCE",
    "...und heisst nach dem, was sie ist: eine Chance aus gebundenem Gold")

-- Bleibt nur ein Test, heisst die Ueberschrift MARKTTEST und nicht
-- "beste Aktion".
local testOnly = GCP.Recommendation:Best({ allocations = {
    itemAllocation("test", "TEST", 900000),
} })
expectEqual(testOnly.headline, "MARKTTEST",
    "Ein Versuch wird als Versuch ueberschrieben, nicht als beste Aktion")
local testText = table.concat(GCP.Recommendation:Explain(testOnly), "\n")
expect(testText:find("Versuch") ~= nil, "...und die Erklaerung sagt es noch einmal")
expect(testText:find("Warum diese Menge") ~= nil,
    "Jede Empfehlung beantwortet 'warum diese Menge'")

H.section("Recommendation: das zweite Pruefszenario aus dem Auftrag")

-- "Der Spieler hat ueber mehrere Sessions nachweislich sehr effizient Gold mit
-- Enchanting Services verdient. Erkennt Gold Copilot diese Methode als
-- persoenliche Goldstrategie und kann sie gegenueber schwaecheren AH-/Craft-/
-- Farm-Alternativen empfehlen?"

H.reset(GCP)
local function seedService(gold, minutes, offsetDays)
    local store = GCP.Activity:EnsureStore()
    store.sessions[#store.sessions + 1] = {
        k = "service.enchant", s = H.now - offsetDays * 86400,
        e = H.now - offsetDays * 86400 + minutes * 60,
        m = minutes, g = gold, c = 0, n = 12, h = 19, w = 3,
    }
end
-- Acht Sitzungen zu je rund 230 g/h. Das ist eine belegte Methode.
for index = 1, 8 do seedService(2300000, 60, index) end

-- Dagegen eine schwache Item-Aktion: 20 g Gewinn in 30 Minuten aktiver Zeit,
-- also 40 g/h.
local weakItem = itemAllocation("weak", "PROVEN", 200000, 1, 30)
local decided = GCP.Recommendation:Best({ allocations = { weakItem } })
-- BEIDE werden gezeigt, und keine verdraengt die andere: Die eine ist eine
-- wiederholbare Stundenrate, die andere ein einmaliger Gewinn aus gebundenem
-- Gold. Ein Sieger zwischen ihnen waere erfunden.
expectEqual(decided.kind, "BOTH",
    "Gemessene Methode und Kapitalchance stehen nebeneinander")
expect(decided.activeMethod ~= nil, "Die Methode wird als aktive Methode gefuehrt")
expect(decided.activeMethod.title:find("Verzauber") ~= nil,
    "...und beim Namen genannt")
expectNear(decided.activeMethod.goldPerHour, 2300000, 50000,
    "...mit der eigenen gemessenen Rate")
expect(decided.capitalOpportunity ~= nil, "Die Item-Aktion bleibt als Kapitalchance stehen")
local decidedText = table.concat(GCP.Recommendation:Explain(decided), "\n")
expect(decidedText:find("Sitzung") ~= nil, "Die Begruendung nennt die Stichprobe")
expect(decidedText:find("Kapital bindet sie keines") ~= nil,
    "...und den Unterschied zu einem Kapitalgeschaeft")
expect(decidedText:find("nicht seriös vergleichen") ~= nil,
    "...und sagt ausdruecklich, warum es keinen Sieger gibt")

-- UMGEKEHRT: Eine starke Item-Aktion wird ebensowenig verdraengt.
local strongItem = itemAllocation("strong", "PROVEN", 2500000, 6, 30)
local kept = GCP.Recommendation:Best({ allocations = { strongItem } })
expectEqual(kept.kind, "BOTH",
    "Auch umgekehrt verdraengt die Methode die Kapitalchance nicht")
expectEqual(kept.capitalOpportunity.key, "strong", "...die Chance bleibt stehen")

-- UND: Eine schwach belegte Methode schlaegt gar nichts. Zwei Sitzungen sind
-- keine Goldstrategie.
H.reset(GCP)
seedService(9000000, 60, 1)
local thinMethod = GCP.Recommendation:Best({
    allocations = { itemAllocation("proven", "PROVEN", 200000, 1, 30) } })
expectEqual(thinMethod.kind, "ITEM",
    "Eine einzelne Sitzung ist keine belegte Methode - egal wie gut sie lief")
expectEqual(thinMethod.activeMethod, nil, "...sie tritt gar nicht erst an")

H.section("Recommendation: Vergleich ueber aktive Zeit")

H.reset(GCP)
for index = 1, 8 do seedService(1000000, 60, index) end     -- 100 g/h

-- SZENARIO B AUS DEM AUFTRAG. Ein Flip mit wenig Bedienzeit darf nicht als
-- "1200 g/h und deshalb fuenfmal besser" erscheinen. Die Zahl gibt es weiter -
-- sie sagt, wie viel Aufwand die Aktion macht - aber sie heisst Bedienzeit und
-- tritt gegen keine gemessene Stundenrate an.
local quickFlip = itemAllocation("flip", "PROVEN", 400000, 2, 5)
local flipCase = GCP.Recommendation:Best({ allocations = { quickFlip } })
expectEqual(flipCase.kind, "BOTH",
    "Der Flip verdraengt die gemessene Methode nicht - beide stehen nebeneinander")
expectEqual(flipCase.capitalOpportunity.key, "flip", "Der Flip ist die Kapitalchance")
expectEqual(flipCase.activeMethod.kind, "METHOD", "Die Methode bleibt die Methode")
expectNear(flipCase.capitalOpportunity.profitPerActiveHour, 4800000, 1000,
    "Der Gewinn je Bedienstunde wird weiter ausgewiesen ...")
expectEqual(flipCase.capitalOpportunity.goldPerHour, nil,
    "...aber ausdruecklich NICHT als Stundenrate, die gegen eine Methode antritt")
local flipText = table.concat(GCP.Recommendation:Explain(flipCase), "\n")
expect(flipText:find("Bedienzeit") ~= nil,
    "Die Erklaerung nennt es Bedienzeit, nicht Stundenrate")
expect(flipText:find("wartet das Kapital, nicht du") ~= nil,
    "...und sagt, was in der Zwischenzeit passiert")

H.section("Recommendation: keine Gold/h ohne eigene Messung")

H.reset(GCP)
expectEqual(#GCP.Recommendation:MethodCandidates(), 0,
    "Ohne eigene Sitzungen tritt keine Methode an")
-- Auch nicht mit einer einzigen: Eine Rate aus einer Beobachtung ist keine.
seedService(5000000, 60, 1)
expectEqual(#GCP.Recommendation:MethodCandidates(), 0,
    "Eine einzige Sitzung reicht nicht fuer eine Methodenaussage")

end)()

-- ===========================================================================
-- FOLLOW-UP-AUDIT 1.1.0-beta.2
--
-- Zwei echte Messfehler und eine irrefuehrende Kennzahl. Jeder Block prueft
-- genau die Aussage, die vorher nicht stimmte.
-- ===========================================================================

;(function()

H.section("Follow-up: Pending-Trinkgelder gehen nicht mehr verloren")

H.reset(GCP)

-- DER BUG. Bis beta.1 merkte sich die Warteschlange nur ZEITPUNKTE. Beim
-- Sessionstart wurde nur der Betrag des ausloesenden Ereignisses uebernommen -
-- aus 20 g + 15 g wurden 15 g bei zwei gezaehlten Kunden.
GCP.Activity:OnIncome({ source = "SERVICE_ENCHANT", amount = 200000,
    confidence = GCP.Income.CONFIDENCE.HIGH, timestamp = H.now - 600 })
expectEqual(GCP.Activity:Current(), nil, "Ein einzelnes Trinkgeld startet nichts")

GCP.Activity:OnIncome({ source = "SERVICE_ENCHANT", amount = 150000,
    confidence = GCP.Income.CONFIDENCE.HIGH, timestamp = H.now - 540 })
local session = GCP.Activity:Current()
expect(session ~= nil, "Das zweite startet die Sitzung")
expectEqual(session.events, 2, "...mit beiden Kunden")
expectEqual(session.gross, 350000, "...UND mit beiden Trinkgeldern (20 g + 15 g)")
expectEqual(session.startedAt, H.now - 600,
    "...und beginnt beim ersten, nicht beim zweiten")

-- Ein drittes Ereignis zaehlt normal weiter - und zwar genau einmal.
GCP.Activity:OnIncome({ source = "SERVICE_ENCHANT", amount = 100000,
    confidence = GCP.Income.CONFIDENCE.HIGH, timestamp = H.now - 300 })
expectEqual(GCP.Activity:Current().gross, 450000, "Das dritte kommt sauber dazu")
expectEqual(GCP.Activity:Current().events, 3, "...ohne Doppelzaehlung")

-- Ereignisse ausserhalb des Fensters verfallen.
H.reset(GCP)
GCP.Activity:OnIncome({ source = "SERVICE_ENCHANT", amount = 200000,
    confidence = GCP.Income.CONFIDENCE.HIGH, timestamp = H.now - 7200 })
GCP.Activity:OnIncome({ source = "SERVICE_ENCHANT", amount = 150000,
    confidence = GCP.Income.CONFIDENCE.HIGH, timestamp = H.now })
expectEqual(GCP.Activity:Current(), nil,
    "Ein zwei Stunden altes Ereignis startet mit einem neuen keine Sitzung")

H.section("Follow-up: Warten auf Kunden ist Arbeitszeit")

H.reset(GCP)

-- SZENARIO A AUS DEM AUFTRAG. Eine Stunde Shattrath, Kunden alle zwoelf
-- Minuten. Bis beta.1 zaehlte das Tick-Modell NULL Minuten (jede Luecke war
-- groesser als das Tick-Fenster), und die Sitzung fiel als "zu kurz" heraus -
-- die Methode war praktisch nicht messbar.
local t0 = H.now - 3600
for index, amount in ipairs({ 200000, 150000, 300000, 250000, 400000 }) do
    GCP.Activity:OnIncome({ source = "SERVICE_ENCHANT", amount = amount,
        confidence = GCP.Income.CONFIDENCE.HIGH,
        timestamp = t0 + (index - 1) * 720 })
end
local running = GCP.Activity:Current()
expect(running ~= nil, "Die Sitzung laeuft")
expectEqual(running.gross, 1300000, "Alle fuenf Trinkgelder sind drin")
-- Der Herzschlag laeuft in der Wirklichkeit alle 60 Sekunden weiter, solange
-- der Charakter eingeloggt ist. Hier wird er von Hand nachgestellt: Er ist der
-- Grund, warum die letzten zwoelf Minuten ohne Kunden trotzdem zaehlen.
for tick = 2940, 3600, 60 do GCP.Activity:Tick(t0 + tick) end
local record = GCP.Activity:Stop("fertig", t0 + 3600)
expect(record ~= nil, "Und sie wird auch aufgeschrieben - anders als in beta.1")
expectNear(record.m, 60, 1, "Eine Stunde Stand ist eine Stunde Arbeitszeit")
expectEqual(record.g, 1300000, "...mit dem vollen Ertrag")

-- OHNE Lebenszeichen wird dagegen bewusst vorsichtig abgerechnet: bis zum
-- letzten bekannten Zeitpunkt plus Karenz. Wer sich ausloggt, bekommt die
-- Stunde danach nicht gutgeschrieben.
H.reset(GCP)
for index, amount in ipairs({ 200000, 150000 }) do
    GCP.Activity:OnIncome({ source = "SERVICE_ENCHANT", amount = amount,
        confidence = GCP.Income.CONFIDENCE.HIGH,
        timestamp = t0 + (index - 1) * 720 })
end
local abandoned = GCP.Activity:Stop("fertig", t0 + 3600)
expect(abandoned ~= nil, "Auch diese Sitzung wird aufgeschrieben")
expect(abandoned.m < 30,
    "...aber nur bis zum letzten Lebenszeichen plus Karenz, nicht bis zum Ende")

H.section("Follow-up: manuelle Service-Sitzung")

H.reset(GCP)

-- Der Fall aus dem Auftrag: Start 19:00, Kunden 19:15 / 19:35 / 19:55,
-- Ende 20:00. Die investierte Zeit sind 60 Minuten - nicht die Summe der
-- Abstaende zwischen den Trades.
local start = H.now - 3600
GCP.Activity:StartManual("service.enchant", start)
expect(GCP.Activity:IsManual(), "Die Sitzung ist als selbst gestartet vermerkt")
for _, offset in ipairs({ 900, 2100, 3300 }) do
    GCP.Activity:OnIncome({ source = "SERVICE_ENCHANT", amount = 500000,
        confidence = GCP.Income.CONFIDENCE.HIGH, timestamp = start + offset })
end
local manual = GCP.Activity:Current()
expectEqual(manual.events, 3, "Drei Kunden")
expectEqual(manual.gross, 1500000, "150 g Einnahmen")
local manualRecord = GCP.Activity:Stop("fertig", start + 3600)
expect(manualRecord ~= nil, "Die Sitzung wird aufgeschrieben")
expectNear(manualRecord.m, 60, 1, "60 Minuten investiert - die ganze Stunde")
expectEqual(manualRecord.mo, GCP.Constants.ACTIVITY.MODE.MANUAL,
    "...und der Modus steht dabei")
local manualStats = GCP.Activity:MethodStats("service.enchant")
expectNear(manualStats.medianGoldPerHour, 1500000, 30000,
    "150 g in 60 Minuten sind 150 g/h - nicht mehr")

H.section("Follow-up: manuelle Sitzung schlaegt Auto-Erkennung nicht doppelt")

H.reset(GCP)
GCP.Activity:StartManual("service.enchant", H.now - 1800)
GCP.Activity:OnIncome({ source = "SERVICE_ENCHANT", amount = 200000,
    confidence = GCP.Income.CONFIDENCE.HIGH, timestamp = H.now - 600 })
GCP.Activity:OnIncome({ source = "SERVICE_ENCHANT", amount = 150000,
    confidence = GCP.Income.CONFIDENCE.HIGH, timestamp = H.now - 300 })
local single = GCP.Activity:Current()
expectEqual(single.startedAt, H.now - 1800,
    "Die laufende manuelle Sitzung bleibt - die Erkennung startet keine zweite")
expectEqual(single.gross, 350000, "Die Trades landen in der bestehenden Sitzung")
expectEqual(single.events, 2, "...und werden dort gezaehlt")

H.section("Follow-up: Offline-Zeit zaehlt nicht")

H.reset(GCP)
-- Sitzung gestartet, letztes Lebenszeichen vor zwei Stunden - dazwischen war
-- der Spieler ausgeloggt. Abgerechnet wird bis zum Lebenszeichen, nicht bis
-- jetzt.
GCP.Activity:StartManual("service.enchant", H.now - 4 * 3600)
local stale = GCP.Activity:Current()
stale.gross = 2000000
stale.events = 5
stale.lastEventAt = H.now - 2 * 3600
stale.lastSeenAt = H.now - 2 * 3600
local recovered = GCP.Activity:RecoverSession(H.now)
expect(recovered ~= nil, "Eine unterbrochene Sitzung wird abgerechnet")
expectNear(recovered.m, 120, 6,
    "Gerechnet wird bis zum letzten Lebenszeichen, nicht bis zum Login")

-- Und eine Sitzung, deren Lebenszeichen frisch ist, laeuft einfach weiter -
-- ein /reload mitten im Service beendet sie nicht.
H.reset(GCP)
GCP.Activity:StartManual("service.enchant", H.now - 600)
GCP.Activity:Tick(H.now)                     -- der Herzschlag von eben
expectEqual(GCP.Activity:RecoverSession(H.now), nil,
    "Eine frische Sitzung wird nicht abgerechnet, sondern laeuft weiter")
expect(GCP.Activity:Current() ~= nil, "...und steht danach noch")

H.section("Follow-up: Service-Gold/h ist netto")

H.reset(GCP)
-- 60 Minuten, 300 g Einnahmen, 80 g eigene Materialien -> 220 g/h.
GCP.Activity:StartManual("service.enchant", H.now - 3600)
local netSession = GCP.Activity:Current()
netSession.gross = 3000000
netSession.events = 6
netSession.lastSeenAt = H.now
GCP.Activity:AddCost(800000, H.now)
local netRecord = GCP.Activity:Stop("fertig", H.now)
expectEqual(netRecord.c, 800000, "Die eigenen Materialien stehen als Kosten dabei")
local netStats = GCP.Activity:MethodStats("service.enchant")
expectNear(netStats.medianGoldPerHour, 2200000, 30000,
    "220 g netto je Stunde - nicht 300 g brutto")

H.section("Follow-up: Live-Anzeige nur mit realen Zahlen")

H.reset(GCP)
GCP.Activity:StartManual("service.enchant", H.now - 2520)   -- 42 Minuten
local liveSession = GCP.Activity:Current()
liveSession.gross = 1740000
liveSession.events = 8
liveSession.lastSeenAt = H.now
GCP.Activity:AddCost(240000, H.now)
local live = GCP.Activity:LiveStats(H.now)
expect(live ~= nil, "Eine laufende Sitzung hat eine Live-Anzeige")
expectNear(live.minutes, 42, 1, "...mit der bisherigen Dauer")
expectEqual(live.events, 8, "...den Kunden")
expectEqual(live.gross, 1740000, "...brutto")
expectEqual(live.net, 1500000, "...und netto nach eigenen Materialien")
expectNear(live.goldPerHour, 2142857, 20000,
    "Die Rate ist netto durch bisherige Dauer - keine Hochrechnung")

-- Zu kurz: keine Rate. Aus drei Minuten und einem Trinkgeld eine Stundenrate
-- zu bilden waere die unehrlichste Zahl der Oberflaeche.
H.reset(GCP)
GCP.Activity:StartManual("service.enchant", H.now - 180)
local younger = GCP.Activity:Current()
younger.gross = 500000
younger.lastSeenAt = H.now
expectEqual(GCP.Activity:LiveStats(H.now).goldPerHour, nil,
    "Eine drei Minuten alte Sitzung bekommt keine Stundenrate")
expect(GCP.Activity:LiveText(H.now):find("zu kurz") ~= nil, "...und sagt warum")

H.section("Follow-up: keine falsche Enchanting-Zuordnung")

do
    H.reset(GCP)
    GCP.Income.lastGold = H.money

    -- Ein normaler Handel: Spieler A gibt Spieler B 50 g. Keine Verzauberung,
    -- kein Slot 7, kein Zauber. Das ist ein HANDEL - und niemals ein Service.
    H.trade = { partner = "Gildenkollege", targetMoney = 500000, playerMoney = 0,
        targetItems = {}, playerItems = {} }
    GCP.Income:OnTradeAccepted(H.now)
    GCP.Income:OnTradeCompleted(H.now)
    H.money = H.money + 500000
    GCP.Income:OnMoney(H.now)
    local plain = GCP.Income:GetEvents()[1]
    expectEqual(plain.source, "TRADE", "Ein blosser Goldtransfer bleibt ein Handel")
    expectEqual(plain.confidenceLabel, "low", "...mit niedriger Sicherheit")
    expectEqual(GCP.Activity:Current(), nil,
        "...und startet keine Verzauberungs-Sitzung")

    -- Auch mehrere solche Handel starten keine Sitzung: Niedrige Sicherheit
    -- zaehlt gar nicht erst als Startsignal.
    for index = 1, 4 do
        GCP.Activity:OnIncome({ source = "TRADE", amount = 500000,
            confidence = GCP.Income.CONFIDENCE.LOW, timestamp = H.now + index })
    end
    expectEqual(GCP.Activity:Current(), nil,
        "Auch vier Handel unbekannter Herkunft ergeben keine Goldmethode")

    -- Zeitliche Naehe zu einem Zauber allein ergibt hoechstens mittlere
    -- Sicherheit - nie hohe. Der Client sagt nicht, zu wem der Zauber gehoerte.
    H.reset(GCP)
    GCP.Income:OnEnchantCast(H.now - 30)
    H.trade = { partner = "Kunde", targetMoney = 300000, playerMoney = 0,
        targetItems = {}, playerItems = {} }
    local _, nearConfidence = GCP.Income:ClassifyTrade(
        GCP.Income:SnapshotTrade(H.now), H.now)
    expectEqual(nearConfidence, GCP.Income.CONFIDENCE.MEDIUM,
        "Zeitliche Naehe allein erzeugt nie hohe Sicherheit")
    expect(nearConfidence < GCP.Income.CONFIDENCE.HIGH,
        "...dafuer braucht es den Verzauberungsslot")
end

H.section("Follow-up: Kundenmaterial bleibt Durchlaufmaterial")

do
    H.reset(GCP)
    GCP.Income.lastGold = H.money

    -- Der Kunde bringt Materialien UND 20 g. Einkommen sind 20 g - und die
    -- Materialien tauchen weder als Umsatz noch als Kosten auf.
    H.trade = { partner = "Kunde", targetMoney = 200000, playerMoney = 0,
        targetItems = { [1] = "item:22456", [2] = "item:22457",
            [7] = "item:32837" },
        playerItems = {} }
    GCP.Income:OnTradeAccepted(H.now)
    GCP.Income:OnTradeCompleted(H.now)
    H.money = H.money + 200000
    GCP.Income:OnMoney(H.now)
    local event = GCP.Income:GetEvents()[1]
    expectEqual(event.source, "SERVICE_ENCHANT", "Slot 7 belegt den Service")
    expectEqual(event.amount, 200000,
        "Einkommen ist genau das erhaltene Gold - nicht plus Materialwert")

    -- Und es entstehen KEINE Sitzungskosten aus Kundenmaterial.
    GCP.Activity:StartManual("service.enchant", H.now - 3600)
    GCP.Income:OnTradeAccepted(H.now)
    GCP.Income:OnTradeCompleted(H.now)
    expectEqual(GCP.Activity:Current().cost, 0,
        "Kundenmaterial erzeugt keine eigenen Kosten")

    -- Eigenes Material dagegen schon: Es ist der eigene Einsatz.
    H.trade = { partner = "Kunde", targetMoney = 1000000, playerMoney = 0,
        targetItems = {}, playerItems = { [1] = "item:22456" } }
    GCP.Income:OnTradeAccepted(H.now)
    GCP.Income:OnTradeCompleted(H.now)
    expect(GCP.Activity:Current().cost > 0,
        "Eigenes Material landet als wirtschaftliche Kosten in der Sitzung")
end

H.section("Follow-up: Kapitalchancen nach Attraktivitaet, nicht nach Betrag")

H.reset(GCP)

-- DER FALL AUS DEM AUFTRAG:
--   A: +200 g aus 2000 g Kapital, 24 h bis Verkauf
--   B: +170 g aus  300 g Kapital,  3 h bis Verkauf
-- A ist die groessere Zahl und das schlechtere Geschaeft.
local function capitalCandidate(key, profit, capital, hours, sellThrough)
    local velocity = GCP.Ledger:ProfitVelocity({
        expectedProfit = profit, capital = capital,
        sellThrough = sellThrough, holdingHours = hours,
    })
    return {
        key = key, title = "Chance " .. key, units = 1,
        capital = capital, cashRequired = capital, expectedProfit = profit,
        confidence = "high", minutes = 5,
        opportunity = { profitVelocity = velocity, expectedHours = hours,
            sellThrough = sellThrough },
        actionability = { class = "PROVEN", capacity = { units = 1,
            basis = "belegt" }, reasons = {} },
    }
end

local slow = capitalCandidate("A", 2000000, 20000000, 24, 0.9)
local quick = capitalCandidate("B", 1700000, 3000000, 3, 0.9)
local ranked = GCP.Recommendation:Best({ allocations = { slow, quick } })
expectEqual(ranked.capitalOpportunity.key, "B",
    "Die kapitaleffizientere Chance gewinnt - nicht die mit dem groesseren Betrag")
expectEqual(ranked.capitalRankBasis, "Profit Velocity",
    "...und die Rangfolge sagt, worauf sie beruht")
local rankedText = table.concat(GCP.Recommendation:Explain(ranked), "\n")
expect(rankedText:find("nicht nach dem größten absoluten Gewinn") ~= nil,
    "Die Erklaerung sagt es ausdruecklich")

-- Ohne Velocity faellt die Rangfolge sauber auf die ROI zurueck, statt zu
-- raten.
local noVelocity = {
    key = "C", title = "Chance C", units = 1, capital = 1000000,
    cashRequired = 1000000, expectedProfit = 500000, confidence = "high",
    minutes = 5, opportunity = {},
    actionability = { class = "PROVEN", capacity = { units = 1 }, reasons = {} },
}
local fallback = GCP.Recommendation:Best({ allocations = { noVelocity } })
expectEqual(fallback.capitalRankBasis, "ROI",
    "Ohne Profit Velocity wird die ROI zur Rangfolge - keine erfundene Kennzahl")

H.section("Follow-up: Markttest verdraengt keine belegte Methode")

H.reset(GCP)
local function seedService(gold, minutes, offsetDays)
    local store = GCP.Activity:EnsureStore()
    store.sessions[#store.sessions + 1] = {
        k = "service.enchant", s = H.now - offsetDays * 86400,
        e = H.now - offsetDays * 86400 + minutes * 60,
        m = minutes, g = gold, c = 0, n = 10, h = 19, w = 3,
        mo = GCP.Constants.ACTIVITY.MODE.MANUAL,
    }
end
for index = 1, 8 do seedService(2200000, 60, index) end

local testOnly = {
    key = "test", title = "Unbelegtes Item", units = 1, capital = 500000,
    cashRequired = 500000, expectedProfit = 3000000, confidence = "high",
    minutes = 10, opportunity = {},
    actionability = { class = "TEST", capacity = { units = 1,
        basis = "Markttest" }, reasons = {} },
}
local versus = GCP.Recommendation:Best({ allocations = { testOnly } })
expectEqual(versus.kind, "METHOD",
    "Ein Markttest ohne eigene Sales ist keine Kapitalchance und verdraengt nichts")
expect(versus.activeMethod ~= nil, "Die belegte Methode steht klar da")
expectEqual(versus.capitalOpportunity, nil, "...und der Test tritt nicht dagegen an")

end)()

-- ===========================================================================
-- MATERIALVERBRAUCH BEI DIENSTLEISTUNGEN (1.1.0-beta.3)
--
-- Der Bug: Die "eigenen Materialkosten" kamen aus dem HANDELSFENSTER. Bei
-- einem Verzauberungsservice legt der Enchanter dort aber nichts hinein - der
-- Zauber nimmt die Reagenzien direkt aus den Taschen. Gemessen wurden 0 g, und
-- die Stundenrate war systematisch zu hoch.
--
-- ALLE Tests hier laufen ueber den ECHTEN Datenpfad: Handel -> Zauber ->
-- Taschenaenderung. Kein direkter AddCost-Aufruf; der wuerde nur beweisen,
-- dass Addition funktioniert.
-- ===========================================================================

;(function()

-- Preise der Attrappe: 22456 = 133000, 22457 = 100000.
local DUST, ESSENCE = 22456, 22457
-- Verbrauchtes Material zaehlt mit dem BESCHAFFUNGSpreis, nicht mit dem
-- Erloeswert: Was ein aufgebrauchter Staub kostet, ist der Preis des
-- naechsten. Bis 1.1.0-beta.4 stand hier GetBestPlanningValue, also der
-- Auktionserloes nach Gebuehr - fuer Haendlerware (Portalrunen) lag das um den
-- Faktor vier daneben. Die Rechnungen darunter pruefen die Aufteilung zwischen
-- Kundenmaterial und eigenem Einsatz; der Stueckpreis kommt deshalb aus
-- derselben Quelle wie im Code.
local DUST_PRICE = GCP.Prices:GetAcquisitionPrice(DUST)
local ESSENCE_PRICE = GCP.Prices:GetAcquisitionPrice(ESSENCE)

-- Ein vollstaendiger Handel, so wie ihn der Client meldet.
local function customerTrade(gold, items, at)
    H.trade = { partner = "Kunde", targetMoney = gold, playerMoney = 0,
        targetItems = items or { [7] = "item:32837" }, playerItems = {} }
    GCP.Income:OnTradeAccepted(at)
    GCP.Income:OnTradeCompleted(at)
    H.money = H.money + gold
    GCP.Income:OnMoney(at)
end

-- Ein Enchant: Zauber gelingt, danach meldet der Client die Taschenaenderung.
local function castEnchant(consumption, at)
    GCP.Income:OnEnchantCast(at)
    for itemID, count in pairs(consumption or {}) do
        H.addBagItem(itemID, -count)
    end
    GCP.Inventory.cache = nil
    GCP.Materials:OnBagUpdate(at)
end

H.section("Material: A - der Kunde stellt alles")

do
    H.reset(GCP)
    GCP.Income.lastGold = H.money
    -- Der Kunde bringt die Reagenzien mit. Sie landen kurz in den eigenen
    -- Taschen und sind gleich darauf wieder weg.
    GCP.Activity:StartManual("service.enchant", H.now - 3600)
    H.addBagItem(DUST, 4)
    GCP.Inventory.cache = nil
    customerTrade(1000000,
        { [1] = { link = "item:" .. DUST, count = 4 }, [7] = "item:32837" }, H.now)
    castEnchant({ [DUST] = 4 }, H.now + 1)

    local session = GCP.Activity:Current()
    local settled = GCP.Materials:Settle(session)
    expect(settled.known, "Die Kosten sind bestimmbar")
    expectEqual(settled.value, 0,
        "Kundenmaterial erzeugt KEINE eigenen Kosten - es war nie sein Gold")
    local live = GCP.Activity:LiveStats(H.now + 1)
    expectEqual(live.net, 1000000, "Netto ist das volle Trinkgeld")
end

H.section("Material: B - der Enchanter stellt alles")

do
    H.reset(GCP)
    GCP.Income.lastGold = H.money
    -- Die Reagenzien liegen VORHER im Beutel. Kein Zufluss vom Kunden.
    H.addBagItem(DUST, 4)
    GCP.Inventory.cache = nil
    GCP.Activity:StartManual("service.enchant", H.now - 3600)
    customerTrade(1000000, { [7] = "item:32837" }, H.now)
    castEnchant({ [DUST] = 4 }, H.now + 1)

    local settled = GCP.Materials:Settle(GCP.Activity:Current())
    expect(settled.known, "Die Kosten sind bestimmbar")
    expectEqual(settled.value, 4 * DUST_PRICE,
        "Eigene verbrauchte Reagenzien zaehlen mit ihrem Beschaffungspreis")
    local live = GCP.Activity:LiveStats(H.now + 1)
    expectEqual(live.net, 1000000 - 4 * DUST_PRICE,
        "Netto ist Trinkgeld minus eigenem Materialeinsatz")
    expect(live.net < live.gross, "...und damit kleiner als brutto")
end

H.section("Material: C - gemischt")

do
    H.reset(GCP)
    GCP.Income.lastGold = H.money
    -- Der Kunde bringt zwei Staub mit, der Enchanter legt zwei eigene dazu.
    H.addBagItem(DUST, 2)                       -- eigener Bestand
    GCP.Inventory.cache = nil
    GCP.Activity:StartManual("service.enchant", H.now - 3600)
    H.addBagItem(DUST, 2)                       -- Zufluss vom Kunden
    GCP.Inventory.cache = nil
    customerTrade(1000000,
        { [1] = { link = "item:" .. DUST, count = 2 }, [7] = "item:32837" }, H.now)
    -- Verbraucht werden alle vier.
    castEnchant({ [DUST] = 4 }, H.now + 1)

    local settled = GCP.Materials:Settle(GCP.Activity:Current())
    expect(settled.known, "Die Kosten sind bestimmbar")
    expectEqual(settled.value, 2 * DUST_PRICE,
        "Nur der Teil ueber die Kundenlieferung hinaus ist eigener Einsatz")
    expectEqual(settled.items[DUST], 2, "...zwei Stueck, nicht vier und nicht null")
end

H.section("Material: D - abgebrochener Handel")

do
    H.reset(GCP)
    GCP.Income.lastGold = H.money
    H.addBagItem(DUST, 4)
    GCP.Inventory.cache = nil
    GCP.Activity:StartManual("service.enchant", H.now - 3600)

    -- Handel wird bestaetigt, aber NICHT abgeschlossen.
    H.trade = { partner = "Kunde", targetMoney = 1000000, playerMoney = 0,
        targetItems = { [7] = "item:32837" }, playerItems = {} }
    GCP.Income:OnTradeAccepted(H.now)
    GCP.Income:OnTradeClosed()

    local session = GCP.Activity:Current()
    expectEqual(session.gross, 0, "Ein abgebrochener Handel bringt keine Einnahmen")
    local settled = GCP.Materials:Settle(session)
    expectEqual(settled.value, 0, "...und erzeugt keine Materialkosten")
    expect(settled.known, "...und macht die Sitzung nicht unsicher")
end

H.section("Material: E - Kunde liefert kurz vorher")

do
    H.reset(GCP)
    GCP.Income.lastGold = H.money
    GCP.Activity:StartManual("service.enchant", H.now - 3600)
    -- Der Kunde uebergibt Staub UND Essenz, beides wandert in die Taschen.
    H.addBagItem(DUST, 4)
    H.addBagItem(ESSENCE, 2)
    GCP.Inventory.cache = nil
    customerTrade(1000000, {
        [1] = { link = "item:" .. DUST, count = 4 },
        [2] = { link = "item:" .. ESSENCE, count = 2 },
        [7] = "item:32837" }, H.now)
    -- Und unmittelbar danach werden sie verbraucht. Ein blosser
    -- Taschenvergleich saehe hier vier Staub und zwei Essenzen verschwinden
    -- und buchte eigene Kosten - genau das darf nicht passieren.
    castEnchant({ [DUST] = 4, [ESSENCE] = 2 }, H.now + 1)

    local settled = GCP.Materials:Settle(GCP.Activity:Current())
    expectEqual(settled.value, 0,
        "Material, das der Kunde eben gebracht hat, ist kein eigener Einsatz")
    expectEqual(next(settled.items), nil, "...und taucht in keiner Kostenzeile auf")
end

H.section("Material: F - eigener Bestand von vorher")

do
    H.reset(GCP)
    GCP.Income.lastGold = H.money
    -- Dieselbe Menge wie in E, aber ohne Kundenlieferung.
    H.addBagItem(DUST, 4)
    H.addBagItem(ESSENCE, 2)
    GCP.Inventory.cache = nil
    GCP.Activity:StartManual("service.enchant", H.now - 3600)
    customerTrade(1000000, { [7] = "item:32837" }, H.now)
    castEnchant({ [DUST] = 4, [ESSENCE] = 2 }, H.now + 1)

    local settled = GCP.Materials:Settle(GCP.Activity:Current())
    expectEqual(settled.value, 4 * DUST_PRICE + 2 * ESSENCE_PRICE,
        "Was vorher da lag und verbraucht wurde, ist eigener Einsatz")
    expectEqual(settled.items[DUST], 4, "...vier Staub")
    expectEqual(settled.items[ESSENCE], 2, "...und zwei Essenzen")
end

H.section("Material: G - Herkunft nicht feststellbar")

do
    -- Ein Zauber gelingt, aber es folgt keine zuzuordnende Taschenaenderung.
    -- Dann ist offen, ob und was er gekostet hat - und das wird auch so
    -- gesagt, statt null anzunehmen.
    H.reset(GCP)
    GCP.Income.lastGold = H.money
    GCP.Activity:StartManual("service.enchant", H.now - 3600)
    customerTrade(1000000, { [7] = "item:32837" }, H.now)
    GCP.Income:OnEnchantCast(H.now + 1)
    -- Die Taschenmeldung kommt erst lange danach - das Fenster ist zu.
    GCP.Materials:OnBagUpdate(H.now + 600)

    local settled = GCP.Materials:Settle(GCP.Activity:Current())
    expectEqual(settled.known, false, "Ohne zuzuordnende Aenderung sind die Kosten unbekannt")
    expect(settled.reason ~= nil, "...und der Grund steht dabei")
    local live = GCP.Activity:LiveStats(H.now + 600)
    expectEqual(live.costKnown, false, "Die Live-Anzeige sagt es ebenfalls")
    expectEqual(live.rateIsGross, true, "...und kennzeichnet die Rate als brutto")
    expect(GCP.Activity:LiveText(H.now + 600):find("unbekannt") ~= nil,
        "...in Worten")

    -- Und die abgeschlossene Sitzung speichert die Kosten NICHT als null.
    local record = GCP.Activity:Stop("fertig", H.now + 600)
    expect(record ~= nil, "Die Sitzung wird trotzdem aufgeschrieben")
    expectEqual(record.c, nil, "...aber ohne Kostenzahl - null waere eine Falschaussage")
    expectEqual(record.cu, 1, "...und mit der Markierung 'unbekannt'")
end

H.section("Material: unsichere Kosten schlagen auf die Methode durch")

do
    H.reset(GCP)
    local store = GCP.Activity:EnsureStore()
    local function seed(gold, cost, unknown, offsetDays)
        store.sessions[#store.sessions + 1] = {
            k = "service.enchant", s = H.now - offsetDays * 86400,
            e = H.now - offsetDays * 86400 + 3600, m = 60, g = gold,
            c = cost, cu = unknown and 1 or nil, n = 10, h = 19, w = 3, mo = 1,
        }
    end
    for index = 1, 8 do seed(3000000, 800000, false, index) end
    local clean = GCP.Activity:MethodStats("service.enchant")
    expectEqual(clean.netKnown, true, "Mit lauter bekannten Kosten ist die Rate netto")
    expectNear(clean.medianGoldPerHour, 2200000, 30000,
        "300 g brutto minus 80 g Material sind 220 g/h")

    -- Eine einzige Sitzung mit unbekannten Kosten macht die ganze Aussage
    -- brutto. Sie wird nicht verworfen - Zeit und Ertrag sind gemessen -, aber
    -- sie heisst dann auch so.
    seed(3000000, nil, true, 9)
    local dirty = GCP.Activity:MethodStats("service.enchant")
    expectEqual(dirty.netKnown, false, "Eine unsichere Sitzung macht die Rate brutto")
    expectEqual(dirty.grossOnlySessions, 1, "...und sagt, wie viele es betrifft")

    -- Und die Empfehlung stuft sie eine Stufe herab.
    local candidates = GCP.Recommendation:MethodCandidates()
    expect(#candidates > 0, "Die Methode tritt weiterhin an")
    expectEqual(candidates[1].netKnown, false, "...aber als Bruttorate gekennzeichnet")
    expectEqual(candidates[1].effectiveConfidence, "low",
        "...und mit einer Stufe weniger Datenlage als die neun Sitzungen hergaeben")
    local text = table.concat(GCP.Recommendation:Explain(
        GCP.Recommendation:Best({ allocations = {} })), "\n")
    expect(text:find("BRUTTO") ~= nil,
        "Die Erklaerung sagt ausdruecklich, dass die Rate brutto ist")
end

H.section("Material: keine Kosten ohne Zauber")

do
    -- Eine Taschenaenderung ohne vorangegangenen Zauber ist kein
    -- Materialverbrauch. Wer etwas verkauft oder einlagert, hat nichts
    -- verzaubert.
    H.reset(GCP)
    H.addBagItem(DUST, 10)
    GCP.Inventory.cache = nil
    GCP.Activity:StartManual("service.enchant", H.now - 3600)
    H.addBagItem(DUST, -10)
    GCP.Inventory.cache = nil
    GCP.Materials:OnBagUpdate(H.now)

    local settled = GCP.Materials:Settle(GCP.Activity:Current())
    expectEqual(settled.value, 0, "Ohne Zauber entstehen keine Materialkosten")
    expect(settled.known, "...und die Sitzung bleibt sicher")
end

H.section("Material: Entzaubern ist kein Verbrauch")

do
    -- Ein Kundenitem wird entzaubert und die Splitter gehen zurueck. Aus Sicht
    -- der Taschen verschwindet ein Gegenstand mit Marktwert - eingesetzt hat
    -- der Enchanter aber nichts. Faellt das in das Zuordnungsfenster einer
    -- vorangegangenen Verzauberung, darf es trotzdem nichts kosten.
    H.reset(GCP)
    GCP.Income.lastGold = H.money
    H.addBagItem(DUST, 10)
    GCP.Inventory.cache = nil
    GCP.Activity:StartManual("service.enchant", H.now - 3600)
    customerTrade(1000000, { [7] = "item:32837" }, H.now)

    -- Zauber gelingt, das Fenster ist offen ...
    GCP.Income:OnEnchantCast(H.now + 1)
    -- ... dann kommt ein Entzaubern dazwischen und schliesst es.
    expect(GCP.Materials:CancelPendingCast("Entzaubern"),
        "Entzaubern schliesst das offene Zuordnungsfenster")
    H.addBagItem(DUST, -10)
    GCP.Inventory.cache = nil
    GCP.Materials:OnBagUpdate(H.now + 2)

    local settled = GCP.Materials:Settle(GCP.Activity:Current())
    expectEqual(settled.value, 0, "Das entzauberte Item ist kein eigenes Material")
    expect(settled.known, "...und die Sitzung bleibt sicher, nicht 'unbekannt'")

    -- Ohne offenes Fenster gibt es auch nichts zu schliessen.
    expectEqual(GCP.Materials:CancelPendingCast("Entzaubern"), false,
        "Ohne offenes Fenster tut der Riegel nichts")
end

H.section("Material: Kostenrechnung abschaltbar")

do
    -- Wer ausschliesslich Kundenmaterial verarbeitet, will keinen Abzug sehen.
    -- Abgeschaltet heisst: keine Kosten UND keine Unsicherheit.
    H.reset(GCP)
    GCP.Income.lastGold = H.money
    H.addBagItem(DUST, 4)
    GCP.Inventory.cache = nil
    GCP.Activity:StartManual("service.enchant", H.now - 3600)
    customerTrade(1000000, { [7] = "item:32837" }, H.now)
    castEnchant({ [DUST] = 4 }, H.now + 1)

    expect(GCP.Materials:CostEnabled(), "Voreingestellt wird Material mitgerechnet")
    local withCost = GCP.Materials:Settle(GCP.Activity:Current())
    expectEqual(withCost.value, 4 * DUST_PRICE, "...und der eigene Einsatz zaehlt")

    GCP.db.options.countMaterialCost = false
    expectEqual(GCP.Materials:CostEnabled(), false, "Der Schalter greift")
    local without = GCP.Materials:Settle(GCP.Activity:Current())
    expectEqual(without.value, 0, "Abgeschaltet kostet Material nichts")
    expect(without.known, "...und die Rate gilt als sicher, nur eben brutto")
    expect(without.disabled, "...gekennzeichnet als bewusst abgeschaltet")
    expect(GCP.Materials:Describe(without):find("nicht mitgerechnet") ~= nil,
        "...mit einem Satz, der das sagt")

    local live = GCP.Activity:LiveStats(H.now + 1)
    expectEqual(live.cost, 0, "Die Live-Anzeige zieht nichts ab")
    expectEqual(live.net, 1000000, "...und Netto ist das volle Trinkgeld")

    GCP.db.options.countMaterialCost = true
end

end)()

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
