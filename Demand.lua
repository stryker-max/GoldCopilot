local addonName, GCP = ...

GCP.Demand = {}
local Demand = GCP.Demand

-- ---------------------------------------------------------------------------
-- DEMAND EVIDENCE (1.1.0)
--
-- Bis 1.0 beantwortet die Kette eine Frage sehr gut und eine gar nicht.
--
--     GUT:  "Rechnet sich das?"      Preis, Marge, ROI, Kapitalbedarf.
--     GAR NICHT: "Kauft das jemand?"
--
-- Die zweite Frage ist die wichtigere. Ein Craft mit 200 g Marge ist keine
-- gute Empfehlung, wenn das Produkt drei Wochen im Auktionshaus steht. Und
-- "zwanzigmal herstellbar" ist keine Aussage darueber, ob der Markt zwanzig
-- Stueck aufnimmt - es ist eine Aussage ueber den eigenen Beutel.
--
-- Dieses Modul sammelt BELEGE. Es bewertet nicht, es empfiehlt nicht, es
-- rechnet keinen Score. Es sagt, was bekannt ist und wie sicher.
--
-- VIER GETRENNTE QUELLEN, absteigend nach Beweiskraft:
--
--   D) Aktuelle Marktlage    kann eine Stufe SENKEN, nie heben
--   C) Eigene Verkaeufe      der einzige echte Nachfragebeleg
--   B) Realm-Markt           beweist ANGEBOT, nicht Nachfrage
--   A) Struktur              Priorwissen, beweist gar nichts
--
-- Sie werden nie miteinander verrechnet. Eine breite strukturelle Verwendung
-- macht aus null Verkaeufen keinen halben Verkauf.
--
-- DER WICHTIGSTE SATZ: Listings sind Angebot. Fuenfzig Auktionen eines Items
-- koennen genauso gut heissen, dass zwanzig Verkaeufer darauf sitzenbleiben.
-- Realm-Evidenz erreicht deshalb nie mehr als Stufe 2, und Stufe 2 traegt
-- hoechstens einen Markttest.
-- ---------------------------------------------------------------------------

local function config()
    return GCP.Constants.DEMAND
end

local function isItemID(value)
    return type(value) == "number" and value > 0 and value == math.floor(value)
end

Demand.cache = nil
Demand.cacheRevision = nil

function Demand:Now()
    if type(time) == "function" then
        local ok, value = pcall(time)
        if ok and type(value) == "number" then return value end
    end
    return 0
end

function Demand:Invalidate()
    self.cache = nil
    self.cacheRevision = nil
end

-- ---------------------------------------------------------------------------
-- A) STRUKTURELLE NACHFRAGE
--
-- Priorwissen aus der Wissensbasis: Was IST dieses Item, wie viele koennten es
-- brauchen, und kommen sie wieder? Das ist der Kaltstart und sonst nichts.
--
-- Ausdruecklich KEIN Nachfragebeleg. Es beantwortet "waere es plausibel?",
-- nicht "passiert es?".
-- ---------------------------------------------------------------------------

function Demand:StructuralFor(itemID)
    if not GCP.Knowledge or not isItemID(itemID) then return nil end
    local identity = GCP.Knowledge:DemandIdentity(itemID)
    if not identity then return nil end
    return identity
end

-- Der Satz dazu. Er sagt bewusst "koennte" und nie "wird".
function Demand:DescribeStructural(identity)
    if type(identity) ~= "table" then return nil end
    local parts = {}
    if identity.type == "RECURRING" then
        parts[#parts + 1] = "wird verbraucht und wieder gebraucht"
    elseif identity.type == "ONE_TIME" then
        parts[#parts + 1] = "wird einmal gekauft und dann nicht wieder"
    end
    if identity.breadthCount and identity.breadthCount > 0 then
        parts[#parts + 1] = string.format("%d bekannte Verwendung(en)",
            identity.breadthCount)
    elseif identity.breadth == "NARROW" then
        parts[#parts + 1] = "keine bekannte Weiterverwendung"
    end
    if identity.obsolescence == "HIGH" then
        parts[#parts + 1] = "bekannter Grund spricht gegen die Nachfrage"
    end
    if #parts == 0 then return nil end
    return table.concat(parts, " · ")
end

-- ---------------------------------------------------------------------------
-- B) REALM-MARKT
--
-- Was wurde auf DIESEM Realm tatsaechlich beobachtet? Datenquelle ist
-- ausschliesslich die Auktionsliste, die der Spieler selbst durchgeblaettert
-- hat.
--
-- Was sich daraus ableiten laesst: dass es diesen Markt gibt. Mehr nicht.
--
-- Die einzige Nachfrageaussage, die ohne eigene Verkaeufe moeglich ist, ist die
-- FLUKTUATION: Faellt die Angebotsmenge zwischen zwei Beobachtungen, hat
-- jemand gekauft - oder zurueckgezogen. Welches von beidem, weiss niemand,
-- und deshalb hebt auch das die Stufe nicht ueber 2.
-- ---------------------------------------------------------------------------

function Demand:RealmFor(itemID)
    if not GCP.Market or not isItemID(itemID) then return nil end
    local depth = GCP.Market:GetDepth(itemID)
    if not depth then return nil end

    local D = config()
    local observations = math.max(depth.samples or 0, 1)
    local drops, absorbed = 0, 0
    local history = depth.quantityHistory or {}
    for index = 2, #history do
        local delta = (history[index - 1].quantity or 0) - (history[index].quantity or 0)
        if delta > 0 then
            drops = drops + 1
            absorbed = absorbed + delta
        end
    end

    return {
        itemID = itemID,
        observations = observations,
        listingCount = depth.listingCount,
        availableQuantity = depth.availableQuantity,
        supplyState = depth.supplyState,
        priceLevels = depth.priceLevels,
        ageSeconds = depth.ageSeconds,
        -- Rueckgaenge im Angebot. Ausdruecklich nicht "verkaufte Stueck":
        -- Zurueckgezogen sieht genauso aus.
        supplyDrops = drops,
        supplyDropQuantity = absorbed,
        active = observations >= D.MARKET_MIN_OBSERVATIONS
            and (depth.listingCount or 0) > 0,
    }
end

-- ---------------------------------------------------------------------------
-- C) EIGENE VERKAEUFE
--
-- Der einzige echte Nachfragebeleg. Alles darueber ist Vermutung, alles
-- darunter ist Angebot.
-- ---------------------------------------------------------------------------

function Demand:PersonalFor(itemID)
    if not GCP.Ledger or not isItemID(itemID) then return nil end
    local stats = GCP.Ledger:GetItemStats(itemID)
    if not stats then return nil end
    if (stats.soldAuctions or 0) <= 0 then return nil end
    return {
        itemID = itemID,
        soldAuctions = stats.soldAuctions or 0,
        soldQuantity = stats.soldQuantity or 0,
        expiredAuctions = stats.expiredAuctions or 0,
        sellThrough = stats.sellThrough,
        sellThroughAuctions = stats.sellThroughAuctions,
        medianHours = stats.medianHours,
        salesPerWeek = stats.salesPerWeek,
        spanDays = stats.spanDays,
        realizedMargin = stats.realizedMargin,
        lastAt = stats.lastAt,
        confidence = stats.confidence,
    }
end

-- ---------------------------------------------------------------------------
-- D) AKTUELLE MARKTLAGE
--
-- Historische Nachfrage ist keine heutige. Wer zwanzig Stueck verkauft hat,
-- aber seit dem Phasenwechsel keines mehr, hat keine belastbare Lage mehr -
-- er hat eine Erinnerung.
--
-- Diese Quelle kann eine Stufe nur SENKEN. Sie ist der Einwand, nicht der
-- Beleg.
-- ---------------------------------------------------------------------------

function Demand:CurrentFor(itemID)
    if not isItemID(itemID) then return nil end
    local state = { itemID = itemID }
    if GCP.Market then
        local stats = GCP.Market:GetMarketScore(itemID)
        if stats then
            state.marketScore = stats.score
            state.trend = stats.trend
            state.current = stats.current
            state.volatility = stats.volatility
        end
    end
    if GCP.Future then
        local record = GCP.Future:GetItemRecord(itemID)
        if record then
            state.phase = record.phase
            state.futureDemandScore = record.futureDemandScore
        end
    end
    return state
end

-- ---------------------------------------------------------------------------
-- DIE STUFE
--
-- Sie entsteht aus der stärksten vorhandenen Quelle, nicht aus ihrer Summe.
-- Danach greift genau ein Abschlag: veraltete Verkaufsdaten.
-- ---------------------------------------------------------------------------

function Demand:EvidenceFor(itemID)
    local D = config()
    local evidence = {
        itemID = itemID,
        level = D.LEVEL.NONE,
        reasons = {},
        caveats = {},
    }
    if not isItemID(itemID) then return evidence end

    local function reason(text)
        if text then evidence.reasons[#evidence.reasons + 1] = text end
    end
    local function caveat(text)
        if text then evidence.caveats[#evidence.caveats + 1] = text end
    end

    -- A) Struktur. Hoechstens Stufe 1, und nur wenn die Wissensbasis dieses
    -- Item ueberhaupt kennt.
    local structural = self:StructuralFor(itemID)
    evidence.structural = structural
    if structural then
        evidence.level = D.LEVEL.STRUCTURAL
        reason(self:DescribeStructural(structural))
        if structural.obsolescence == "HIGH" then
            caveat("Ein bekannter Grund spricht gegen die künftige Nachfrage.")
        end
        if structural.breadth == "NARROW" then
            caveat("Keine bekannte Weiterverwendung – der Käuferkreis ist eng.")
        end
    end

    -- B) Realm-Markt. Hoechstens Stufe 2 - und ausdruecklich nicht, weil dort
    -- viel liegt, sondern weil dort ueberhaupt etwas passiert.
    local realm = self:RealmFor(itemID)
    evidence.realm = realm
    if realm and realm.active then
        evidence.level = math.max(evidence.level, D.LEVEL.MARKET)
        reason(string.format("Markt beobachtet: %d Angebot(e), %d Messung(en)",
            realm.listingCount or 0, realm.observations or 0))
        if realm.supplyDrops > 0 then
            reason(string.format(
                "Das Angebot ist %dmal gesunken (insgesamt %d Stück) – "
                .. "gekauft oder zurückgezogen, das lässt sich nicht trennen.",
                realm.supplyDrops, realm.supplyDropQuantity))
        end
        if realm.supplyState == "thin" then
            caveat("Sehr dünner Markt.")
        elseif realm.supplyState == "glut" then
            caveat("Ungewöhnlich hohes Angebot.")
        end
    end

    -- C) Eigene Verkaeufe. Ab hier wird aus Vermutung Beleg.
    local personal = self:PersonalFor(itemID)
    evidence.personal = personal
    if personal then
        local level = D.LEVEL.FIRST_SALE
        if personal.soldAuctions >= D.REPEATED_AUCTIONS and personal.sellThrough then
            level = D.LEVEL.REPEATED
        end
        if personal.soldAuctions >= D.STABLE_AUCTIONS
            and (personal.spanDays or 0) >= D.STABLE_DAYS
            and (personal.sellThrough or 0) >= D.STABLE_SELL_THROUGH then
            level = D.LEVEL.STABLE
        end
        evidence.level = math.max(evidence.level, level)
        reason(string.format("%d eigene(r) Verkauf/Verkäufe%s",
            personal.soldAuctions,
            personal.sellThrough
                and string.format(" · %.0f %% Sell-through", personal.sellThrough * 100)
                or ""))
        if personal.medianHours then
            reason(string.format("Median bis Verkauf: %s",
                GCP.Opportunity:FormatHours(personal.medianHours)))
        end
        -- Preisabhaengige Nachfrage. Sie ist der genaueste Beleg, den die
        -- eigene Bilanz hergibt - aber nur, wo die Stichprobe je Band reicht.
        local bands = GCP.Ledger:PriceBandStats(itemID)
        if bands then
            evidence.priceBands = bands
            for _, band in ipairs(bands) do
                if band.sellThrough then
                    reason(string.format("%s: %.0f %% gehen durch (n=%d)",
                        band.label, band.sellThrough * 100, band.n))
                end
            end
        end
        if personal.sellThrough and personal.sellThrough < D.STABLE_SELL_THROUGH then
            caveat(string.format("Nur %.0f %% deiner Auktionen gehen durch.",
                personal.sellThrough * 100))
        end
    end

    -- D) Aktuelle Lage. Nur Einwaende, keine Gutschriften.
    evidence.current = self:CurrentFor(itemID)
    if evidence.current then
        if evidence.current.trend == "falling" then
            caveat("Der Markt fällt gerade.")
        end
    end

    -- PHASENWECHSEL (1.1.0). Der zweite Grund, warum alte Daten weniger
    -- zaehlen: Ein Item, das sich in Phase 2 hervorragend verkauft hat, ist
    -- nach dem Start von Phase 3 womoeglich ein anderes Geschaeft. Wer seither
    -- nichts mehr verkauft hat, hat keine Aussage ueber die heutige Phase - er
    -- hat eine Erinnerung an die vorige.
    --
    -- Geprueft wird gegen den belegten Starttermin der laufenden Phase, nicht
    -- gegen eine erfundene Frist.
    if personal and personal.lastAt and GCP.Future then
        local phase = GCP.Future:GetCurrentPhase()
        if phase and type(phase.release) == "number"
            and personal.lastAt < phase.release
            and evidence.level > D.LEVEL.MARKET then
            evidence.level = evidence.level - 1
            evidence.beforePhase = true
            caveat(string.format(
                "Deine Verkäufe liegen vor dem Start von %s – seit dem "
                .. "Phasenwechsel ist keiner mehr dazugekommen.",
                phase.name or "der aktuellen Phase"))
        end
    end

    -- Aktualitaet: Verkaufsdaten altern, und ein Markt, in dem seit drei Wochen
    -- nichts mehr durchging, ist nicht mehr derselbe.
    if personal and personal.lastAt then
        local ageDays = (self:Now() - personal.lastAt) / 86400
        evidence.ageDays = ageDays
        if ageDays > D.STALE_DAYS and evidence.level > D.LEVEL.MARKET then
            evidence.level = evidence.level - 1
            evidence.stale = true
            caveat(string.format(
                "Dein letzter Verkauf liegt %d Tage zurück – die Belege zählen "
                .. "eine Stufe weniger.", math.floor(ageDays)))
        end
    end

    evidence.label = D.LEVEL_LABEL[evidence.level]
    return evidence
end

-- ---------------------------------------------------------------------------
-- AUFNAHMEFAEHIGKEIT
--
-- "Wie viele Stueck werde ich in einem sinnvollen Zeitraum los?"
--
-- Ohne Belege: ein Markttest. Nicht null - dann entstuende nie Evidenz - und
-- nicht zwanzig, weil das Kapital reicht.
--
-- Mit Belegen: die eigene Verkaufsrate, mit zwei Korrekturen.
--   1. Sell-through. Wer 15 von 18 verkauft, hat eine andere Aufnahme als wer
--      15 von 60 verkauft - die Ablaeufe zaehlen mit.
--   2. Schrumpfung gegen die Testmenge:
--          menge = 1 + (gemessen - 1) * n / (n + PRIOR)
--      Dieselbe Formel wie die Kalibrierung. Bei wenigen Daten bleibt fast
--      alles beim Markttest, bei vielen naehert es sich der Messung an, und es
--      springt nie. Ein einzelner guter Verkaufstag wird damit nicht zur
--      Grundlage einer Zwanzigerposition.
-- ---------------------------------------------------------------------------

function Demand:CapacityFor(itemID, evidence)
    local D = config()
    -- Ein uebergebener Beleg muss auch einer sein. Ein halbes Ergebnis von
    -- aussen darf hier nicht zu einer Menge fuehren.
    if type(evidence) ~= "table" or type(evidence.level) ~= "number" then
        evidence = self:EvidenceFor(itemID)
    end
    local capacity = {
        itemID = itemID,
        level = evidence.level,
        units = 0,
        basis = "keine Belege",
    }

    -- OHNE BELEGE: EIN MARKTTEST.
    --
    -- Nicht null - dann entstuende nie Evidenz, und ein Addon, das bis zum
    -- ersten Verkauf nichts vorschlaegt, hilft niemandem beim ersten Verkauf.
    -- Und nicht zwanzig, weil das Kapital reicht. Ein Stueck ist die Menge, bei
    -- der ein Irrtum nichts kostet und ein Treffer alles Weitere traegt.
    if evidence.level <= D.LEVEL.MARKET then
        capacity.units = D.TEST_UNITS
        capacity.basis = evidence.level >= D.LEVEL.MARKET
            and "Markttest – Markt beobachtet, aber noch kein eigener Verkauf"
            or "Markttest – für dieses Item gibt es noch keine Belege"
        return capacity
    end

    if evidence.level == D.LEVEL.FIRST_SALE then
        capacity.units = D.FIRST_SALE_UNITS
        capacity.basis = "ein einzelner eigener Verkauf"
        return capacity
    end

    -- Ab hier gibt es eine gemessene Rate.
    local personal = evidence.personal
    if not personal then
        capacity.units = D.TEST_UNITS
        capacity.basis = "Markttest"
        return capacity
    end

    local perWeek = personal.salesPerWeek
    local measured
    if perWeek and perWeek > 0 then
        -- salesPerWeek zaehlt AUKTIONEN. Gefragt ist die Stueckzahl, also wird
        -- mit der typischen Stapelgroesse hochgerechnet - der eigenen, nicht
        -- einer angenommenen.
        local perAuction = personal.soldAuctions > 0
            and (personal.soldQuantity / personal.soldAuctions) or 1
        measured = perWeek * perAuction * (D.CAPACITY_DAYS / 7)
    elseif (personal.spanDays or 0) > 0 then
        measured = personal.soldQuantity * (D.CAPACITY_DAYS / personal.spanDays)
    end
    if not measured or measured <= 0 then
        capacity.units = D.FIRST_SALE_UNITS
        capacity.basis = "zu wenig Verlauf für eine Rate"
        return capacity
    end

    -- Sell-through: Die Rate zaehlt, was durchging. Was nicht durchging, ist
    -- der Teil der Antwort, den eine reine Verkaufszahl verschweigt.
    if personal.sellThrough then
        measured = measured * personal.sellThrough
    end

    local n = personal.soldAuctions
    local weight = n / (n + D.CAPACITY_PRIOR)
    local shrunk = D.TEST_UNITS + (measured - D.TEST_UNITS) * weight
    local units = math.floor(shrunk)
    if units < D.TEST_UNITS then units = D.TEST_UNITS end
    if units > D.CAPACITY_MAX then units = D.CAPACITY_MAX end

    capacity.units = units
    capacity.measured = measured
    capacity.weight = weight
    capacity.basis = string.format(
        "deine Absatzhistorie: %d Verkauf/Verkäufe%s",
        n, personal.sellThrough
            and string.format(" bei %.0f %% Sell-through", personal.sellThrough * 100)
            or "")
    return capacity
end

-- Der Satz fuer die Startseite: "Warum diese Menge?"
function Demand:ExplainCapacity(capacity)
    if type(capacity) ~= "table" or type(capacity.units) ~= "number" then
        return nil
    end
    local D = config()
    if capacity.units <= 0 then
        return "Keine Menge empfohlen – für diesen Markt gibt es noch keine Belege."
    end
    if capacity.units <= D.TEST_UNITS then
        return "Ein Stück als Markttest – es gibt noch keinen eigenen Verkauf, "
            .. "an dem sich eine Menge messen ließe."
    end
    if capacity.measured then
        return string.format(
            "%d Stück: %s. Gerechnet wird vorsichtig gegen die Testmenge, "
            .. "damit eine kleine Stichprobe keine große Position trägt.",
            capacity.units, capacity.basis)
    end
    return string.format("%d Stück – %s.", capacity.units, capacity.basis)
end
