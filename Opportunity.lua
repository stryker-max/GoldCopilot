local addonName, GCP = ...

GCP.Opportunity = {}
local Opportunity = GCP.Opportunity

local GetItemInfoCompat = (C_Item and C_Item.GetItemInfo) or GetItemInfo

-- ---------------------------------------------------------------------------
-- OPPORTUNITY ENGINE (0.6.0)
--
-- 0.5.0 beantwortet: "Ist der aktuelle Preis relativ zur eigenen Historie
-- guenstig?" Das ist der Market Score, und er bleibt unveraendert genau das.
--
-- 0.6.0 beantwortet zum ersten Mal: "Ist das eine interessante Gold-Chance?"
--
-- Dieses Modul erfindet dafuer keine neue Rechnung, sondern orchestriert die
-- vorhandenen: Market.lua liefert Marktlage und Volatilitaet, Prices.lua die
-- Planungspreise und die AH-Gebuehr, Crafts.lua die Rezeptgewinne, Flips.lua
-- die Umwandlungen, Inventory.lua den Bestand. Jede Kennzahl wird dort geholt,
-- wo sie ohnehin entsteht - insbesondere wird die AH-Gebuehr genau einmal
-- abgezogen, naemlich auf der Verkaufsseite, und Materialkosten zaehlen genau
-- einmal.
--
-- WAS 0.6 AUSDRUECKLICH NICHT KANN:
--   * Liquiditaet. Wie schnell sich etwas verkauft, weiss das Addon nicht.
--   * Verkaufsdauer und Sell-Through. Dafuer fehlt die Datenbasis.
--   * Zukuenftige Nachfrage. Kommt fruehestens mit Future Market 0.7.
-- Deshalb heisst hier nichts "Gewinn", sondern "theoretischer Gewinn", und
-- keine Zeile sagt "kaufen".
--
-- DATENMODELL EINER CHANCE (Felder, die 0.7 ergaenzen wird, stehen bewusst als
-- nil drin statt mit erfundenen Standardwerten):
--
--   {
--       type = "craft" | "conversion" | "disenchant" | "resale",
--       key = "craft:23571",           -- Deduplikationsschluessel
--       itemID = 23571,                -- das Item, um das es geht
--       title = "Urmacht",
--       action = "Herstellen und verkaufen",
--       cost = 648000,                 -- Kapitalbedarf je Durchgang
--       expectedRevenue = 841000,      -- netto, AH-Gebuehr bereits abgezogen
--       expectedProfit = 193000,       -- theoretisch, ohne Liquiditaet
--       roi = 0.2978,                  -- expectedProfit / cost
--       confidence = "high",
--       opportunityScore = 71,
--       marketScore = 84,              -- Market Score der Kaufseite, falls da
--       volatility = 0.12,
--       feasible = 3,                  -- machbare Stueckzahl, falls bekannt
--       explanation = { "..." },       -- die komplette Rechnung in Worten
--
--       -- Vorbereitet, in 0.6 immer nil:
--       liquidity = nil, sellThrough = nil, expectedHours = nil,
--       profitVelocity = nil, futureDemandScore = nil, liquidityScore = nil,
--       hypeScore = nil, riskScore = nil, catalysts = nil, phase = nil,
--       exitWindow = nil,
--   }
-- ---------------------------------------------------------------------------

-- Laufzeitzustand. Gehoert nicht in die SavedVariables: ein Cache muss keinen
-- Reload ueberleben.
Opportunity.cache = nil

local function config()
    return GCP.Constants.OPPORTUNITY
end

local function clamp(value, low, high)
    if value < low then return low end
    if value > high then return high end
    return value
end

-- Saettigungskurve value / (value + half): 0 bei 0, 0,5 bei half, naehert sich
-- 1. Monoton, ohne Sprungstelle, ohne Obergrenze im Eingang - genau das, was
-- eine Kennzahl braucht, die "mehr ist besser, aber nicht linear" abbildet.
local function saturate(value, half)
    if type(value) ~= "number" or value <= 0 then return 0 end
    if type(half) ~= "number" or half <= 0 then return 1 end
    return value / (value + half)
end

local CONFIDENCE_RANK = { none = 0, low = 1, medium = 2, high = 3 }
local RANK_CONFIDENCE = { [0] = "none", [1] = "low", [2] = "medium", [3] = "high" }

function Opportunity:ConfidenceRank(confidence)
    return CONFIDENCE_RANK[confidence or "none"] or 0
end

-- Die schwaechste beteiligte Datenbasis bestimmt die Aussagekraft: Ein sieben
-- Tage belegtes Produkt hilft nicht, wenn die teuerste Zutat nur einen
-- Momentanpreis hat.
function Opportunity:WeakestConfidence(...)
    local weakest = 3
    local seen = false
    for index = 1, select("#", ...) do
        local value = select(index, ...)
        if value ~= nil then
            seen = true
            local rank = self:ConfidenceRank(value)
            if rank < weakest then weakest = rank end
        end
    end
    if not seen then return "none" end
    return RANK_CONFIDENCE[weakest]
end

-- Preisbasis (Anzahl Tageswerte hinter Prices:GetPlanningPrice) als
-- Confidence-Stufe. 0 Tageswerte sind ein echter Momentanpreis ohne Historie -
-- das ist "niedrig", nicht "keine Daten". Ohne Preis gibt es gar keine Stufe.
function Opportunity:ConfidenceFromDays(days, hasPrice)
    if hasPrice == false then return "none" end
    if type(days) ~= "number" then return "low" end
    local P = config().PRICE_CONFIDENCE
    if days >= P.HIGH_DAYS then return "high" end
    if days >= P.MEDIUM_DAYS then return "medium" end
    return "low"
end

-- ---------------------------------------------------------------------------
-- OPPORTUNITY SCORE 0-100
--
-- Bewusst KEINE gewichtete Fantasieformel aus zehn Faktoren, sondern ein
-- Punktebudget aus vier Gutschriften und zwei Abschlaegen. Jeder Summand
-- beantwortet genau eine Frage, hat eine eigene Obergrenze und laesst sich
-- einzeln an echten Realm-Daten nachjustieren (alle Zahlen stehen in
-- Constants.lua unter OPPORTUNITY.SCORE).
--
--   Opportunity Score =
--         Margin Quality        (0-35)   Kapitaleffizienz, aus der ROI
--       + Profit Scale          (0-15)   absolute Groesse des Gewinns
--       + Market Attractiveness (0-25)   Market Score der Kaufseite
--       + Data Quality          (0-25)   Confidence als eigener Summand
--       - Volatility Risk       (0-15)   Schwankung der beteiligten Reihe
--       - Capital Penalty       (0-15)   gebundenes Gold
--   danach hart gedeckelt durch die Confidence, dann auf 0..100 begrenzt.
--
-- Im Einzelnen:
--
-- 1. MARGIN QUALITY - 35 * roi / (roi + 0,25)
--    Die ROI ist die eigentliche Frage jeder Chance: Was macht mein Gold in
--    einem Durchgang? Die Saettigungskurve gibt bei 25 % ROI die halbe
--    Punktzahl und flacht danach ab. Linear waere falsch: 500 % ist besser als
--    50 %, aber nicht zehnmal so gut - ab einer gewissen Marge entscheidet
--    nicht mehr die Marge, sondern ob die Rechnung stimmt.
--
-- 2. PROFIT SCALE - 15 * profit / (profit + 10 g)
--    Getrennt von der ROI, weil beides verschiedene Dinge sind: 80 % auf 50 g
--    und 5 % auf 500 g sind zwei verschiedene Geschaefte. Der kleinere
--    Punktetopf sorgt dafuer, dass eine dicke, aber lahme Chance eine schlanke,
--    schnelle nicht automatisch schlaegt - und umgekehrt.
--
-- 3. MARKET ATTRACTIVENESS - 25 * marketScore / 100
--    Der Market Score aus 0.5.0, unveraendert uebernommen: Ist die Kaufseite
--    gemessen an ihrer eigenen Historie gerade guenstig? Fehlt er (zu wenig
--    Historie), zaehlen 50 Punkte - "keine Aussage", nicht "schlecht". Eine
--    fehlende Zahl darf keine Behauptung werden.
--
-- 4. DATA QUALITY - 0 / 8 / 17 / 25 nach Confidence
--    Datenqualitaet ist kein Beiwerk, sondern ein eigener Summand. Score und
--    Confidence bleiben trotzdem getrennt ausgewiesen: Der Score ist die
--    Aussage, die Confidence ihr Gewicht.
--
-- 5. VOLATILITY RISK - bis -15
--    In einem stark schwankenden Markt ist eine gute Rechnung weniger wert:
--    Der Preis, mit dem sie rechnet, gilt womoeglich morgen nicht mehr.
--    Gemessen am Quartilsabstand (Market.lua), gedeckelt bei 0,6.
--
-- 6. CAPITAL PENALTY - bis -15
--    Gebundenes Gold ist Risiko und fehlt woanders. Halber Abschlag bei 250 g
--    Einsatz. Damit ist eine 500-g-Chance mit 5 % ROI nie automatisch besser
--    als eine 50-g-Chance mit 80 % ROI - genau darum geht es.
--
-- 7. LIQUIDITY ADJUSTMENT (0.8.0) - bis +-15
--    Der einzige Eingriff, den 0.8 am Score vornimmt, und bewusst ein Zuschlag
--    auf die fertige Rechnung statt eines siebten Summanden im Budget:
--
--        adjust = 15 * clamp((liquidityScore - 55) / 50 ; -1 ; +1) * gewicht
--        gewicht = 0 / 0,25 / 0,65 / 1,0  nach Sell-Through-Confidence
--
--    * OHNE eigene Verkaufsdaten ist der Zuschlag exakt 0. Eine 0.6-Bewertung
--      bleibt damit Punkt fuer Punkt dieselbe - die Oberflaeche sagt dann
--      "Liquidität unbekannt", und das ist die ganze Aussage.
--    * Zwei Auktionen ergeben "low" und damit hoechstens 3,75 Punkte
--      Verschiebung. Eine einzelne gescheiterte Auktion darf keine gute
--      Chance zerstoeren.
--    * 55 statt 50 als Nullpunkt: Ein Item, das gerade eben die Haelfte
--      seiner Auktionen durchbringt, ist kein neutrales Geschaeft, sondern
--      ein zaehes.
--    * Der Zuschlag wirkt VOR dem Confidence-Deckel. Ein Abschlag zieht damit
--      immer, ein Zuschlag nur so weit, wie die Preisdaten ihn tragen: Wer
--      den Gewinn nicht sicher kennt, wird durch schnelle Verkaeufe nicht
--      sicherer.
--
-- HARTE DECKEL:
--    * Ohne Datenbasis (confidence "none") gibt es gar keinen Score - nil, nicht
--      0. "Weiss ich nicht" ist keine schlechte Bewertung, sondern keine.
--    * Ohne positiven Gewinn oder ohne Kapitaleinsatz gibt es keinen Score:
--      eine ROI ohne Nenner ist keine Kennzahl.
--    * Die Confidence deckelt zusaetzlich: niedrig hoechstens 55, mittel
--      hoechstens 80. Eine duenne Datenlage kann nie "sehr interessant" ergeben.
--
-- Der Score ist ausdruecklich keine Zusage. Er ordnet Chancen untereinander -
-- mehr nicht.
-- ---------------------------------------------------------------------------

function Opportunity:ScoreOf(input)
    if type(input) ~= "table" then return nil end
    local S = config().SCORE

    local confidence = input.confidence or "none"
    local confidencePoints = S.CONFIDENCE_POINTS[confidence]
    if confidencePoints == nil or confidence == "none" then return nil end

    local roi, profit, cost = input.roi, input.profit, input.cost
    if type(cost) ~= "number" or cost <= 0 then return nil end
    if type(profit) ~= "number" or profit ~= profit or profit <= 0 then return nil end
    if type(roi) ~= "number" or roi ~= roi or roi <= 0 then return nil end

    local margin = S.MARGIN_POINTS * saturate(roi, S.ROI_HALF)
    local scale = S.PROFIT_POINTS * saturate(profit, S.PROFIT_HALF)

    local marketScore = input.marketScore
    if type(marketScore) ~= "number" then
        marketScore = S.NEUTRAL_MARKET_SCORE
    end
    local market = S.MARKET_POINTS * clamp(marketScore, 0, 100) / 100

    local volatilityRisk = 0
    if type(input.volatility) == "number" and input.volatility > 0 then
        local capped = math.min(input.volatility, S.VOLATILITY_CAP)
        volatilityRisk = S.VOLATILITY_PENALTY * (capped / S.VOLATILITY_CAP)
    end
    local capitalRisk = S.CAPITAL_PENALTY * saturate(cost, S.CAPITAL_HALF)

    -- Liquiditaet aus der eigenen Handelsbilanz. Ohne Daten bleibt sie exakt 0
    -- und der Score ist der aus 0.6.
    local liquidityAdjust = 0
    if type(input.liquidityScore) == "number" then
        local weight = S.LIQUIDITY_WEIGHT[input.liquidityConfidence or "none"] or 0
        if weight > 0 then
            local offset = clamp(
                (input.liquidityScore - S.LIQUIDITY_NEUTRAL) / S.LIQUIDITY_SPAN, -1, 1)
            liquidityAdjust = S.LIQUIDITY_POINTS * offset * weight
        end
    end

    local raw = margin + scale + market + confidencePoints
        - volatilityRisk - capitalRisk + liquidityAdjust
    local ceiling = S.CONFIDENCE_CAP[confidence] or 100

    -- Persoenliche Kalibrierung (0.9.0). Ohne genuegend eigene Ergebnisse ist
    -- der Faktor exakt 1, und dann ist dieser Score Punkt fuer Punkt derselbe
    -- wie in 0.8. Die Confidence-Obergrenze bleibt in jedem Fall bestehen:
    -- Eine duenne Datenlage darf durch Kalibrierung nicht besser aussehen.
    local factor = 1
    if GCP.Calibration and input.type then
        factor = GCP.Calibration:FactorFor(input.type) or 1
    end
    local calibrated = math.min(raw, ceiling) * factor

    return clamp(math.floor(math.min(calibrated, ceiling) + 0.5), 0, 100), {
        margin = margin,
        scale = scale,
        market = market,
        confidence = confidencePoints,
        volatilityRisk = volatilityRisk,
        capitalRisk = capitalRisk,
        liquidityAdjust = liquidityAdjust,
        raw = raw,
        ceiling = ceiling,
        calibration = factor,
    }
end

function Opportunity:ScoreBand(score)
    if type(score) ~= "number" then return nil end
    for _, band in ipairs(config().BANDS) do
        if score >= band.min then return band.label, band.min end
    end
    return nil
end

function Opportunity:TypeLabel(kind)
    return config().TYPE_LABEL[kind or ""] or "Chance"
end

-- ---------------------------------------------------------------------------
-- Bausteine
-- ---------------------------------------------------------------------------

local function itemName(itemID, fallback)
    local name = GetItemInfoCompat(itemID)
    return name or fallback or ("Item " .. tostring(itemID))
end

local function itemIcon(itemID)
    return select(10, GetItemInfoCompat(itemID))
end

-- Marktlage der Kaufseite. Kein Score bedeutet nicht "kein Ergebnis", sondern
-- "keine Aussage" - deshalb kommen Score und Volatilitaet getrennt zurueck.
local function marketFacts(itemID)
    if not GCP.Market or type(itemID) ~= "number" then return nil, nil, nil end
    local stats = GCP.Market:GetMarketScore(itemID)
    if not stats then return nil, nil, nil end
    return stats.score, stats.volatility, stats
end

-- Marktlage eines ganzen Zutatenkorbs, wie ihn ein Craft braucht.
--
-- Der Score wird nach Kostenanteil gewichtet: Ob das billigste von fuenf
-- Reagenzien gerade guenstig ist, aendert an der Rechnung wenig; ob es die
-- teuerste Zutat ist, aendert alles. Zutaten ohne eigenen Score bleiben aussen
-- vor - eine fehlende Zahl darf den Durchschnitt nicht nach unten ziehen.
--
-- Die Volatilitaet dagegen ist das Maximum, kein Durchschnitt: Das Risiko
-- eines Crafts haengt an seiner unruhigsten Zutat, nicht am Mittelwert.
--
-- mats: Liste aus { itemID, Anzahl, Preis } - genau das, was Crafts:BuildReport
-- ohnehin berechnet hat.
function Opportunity:BasketFacts(mats)
    local weightSum, scoreSum = 0, 0
    local worstVolatility = nil
    for _, mat in ipairs(mats or {}) do
        local score, volatility = marketFacts(mat[1])
        local weight = (type(mat[3]) == "number" and mat[3] or 0) * (mat[2] or 1)
        if score and weight > 0 then
            weightSum = weightSum + weight
            scoreSum = scoreSum + score * weight
        end
        if volatility and (worstVolatility == nil or volatility > worstVolatility) then
            worstVolatility = volatility
        end
    end
    if weightSum <= 0 then return nil, worstVolatility end
    return math.floor(scoreSum / weightSum + 0.5), worstVolatility
end

-- Persoenliche Liquiditaet der VERKAUFSSEITE (0.8.0). Ausdruecklich nicht die
-- der Kaufseite: Ob sich Urerde gut verkauft, sagt nichts darueber, wie schnell
-- die daraus hergestellte Urmacht wieder zu Gold wird. Gefragt wird deshalb
-- immer nach dem Item, das am Ende im Auktionshaus landet - und jede Chancenart
-- benennt es selbst ueber fields.saleItemID.
--
-- Beim Entzaubern gibt es dieses Item nicht: Was dabei herauskommt, weiss
-- niemand vorher; Auctionator liefert nur einen Erwartungswert in Gold, keine
-- Materialliste. Diese Chancenart traegt deshalb bewusst gar keine
-- Liquiditaetsaussage - die des gekauften Items waere schlicht die falsche.
function Opportunity:LiquidityOf(itemID)
    if not GCP.Ledger or type(itemID) ~= "number" then return nil end
    return GCP.Ledger:GetLiquidity(itemID)
end

-- Baut eine Chance und rechnet ihren Score. Rueckgabe nil, wenn die Rechnung
-- nicht traegt: fehlende Preise, kein positiver Gewinn, kein Kapitaleinsatz
-- oder keine Datenbasis. Lieber keine Zeile als eine erfundene.
function Opportunity:Make(fields)
    local cost = fields.cost
    local revenue = fields.expectedRevenue
    if type(cost) ~= "number" or cost <= 0 then return nil end
    if type(revenue) ~= "number" then return nil end

    local profit = revenue - cost
    if profit <= 0 then return nil end
    local roi = profit / cost

    local liquidity = self:LiquidityOf(fields.saleItemID)
    local score, parts = self:ScoreOf({
        type = fields.type,
        roi = roi,
        profit = profit,
        cost = cost,
        marketScore = fields.marketScore,
        volatility = fields.volatility,
        confidence = fields.confidence,
        liquidityScore = liquidity and liquidity.liquidityScore or nil,
        liquidityConfidence = liquidity and liquidity.confidence or nil,
    })
    if not score then return nil end

    -- Profit Velocity braucht beides: eine Sell-Through-Rate und eine gemessene
    -- Haltedauer. Fehlt eines davon, bleibt sie nil - eine geschaetzte
    -- Verkaufsdauer waere hier der teuerste Fehler.
    local velocity, velocityParts = nil, nil
    if liquidity then
        velocity, velocityParts = GCP.Ledger:ProfitVelocity({
            expectedProfit = profit,
            capital = cost,
            sellThrough = liquidity.sellThrough,
            holdingHours = liquidity.holdingHours,
        })
    end

    return {
        type = fields.type,
        key = fields.key,
        itemID = fields.itemID,
        -- Das Item, das am Ende verkauft wird. Bei allen Chancenarten ausser
        -- dem Entzaubern ist das itemID; dort gibt es keines (siehe LiquidityOf).
        saleItemID = fields.saleItemID,
        title = fields.title,
        action = fields.action,
        icon = fields.icon,
        quality = fields.quality,

        cost = cost,
        expectedRevenue = revenue,
        expectedProfit = profit,
        roi = roi,

        confidence = fields.confidence,
        opportunityScore = score,
        scoreParts = parts,
        marketScore = fields.marketScore,
        volatility = fields.volatility,
        priceDays = fields.priceDays,
        feasible = fields.feasible,
        explanation = fields.explanation or {},

        -- 0.9.0: Der Bauplan der Chance. Ohne ihn ist eine Chance eine Zahl;
        -- mit ihm kann Execution.lua sie in Kaufen/Herstellen/Einstellen
        -- zerlegen, ohne die Rechnung ein zweites Mal zu fuehren. Fehlt er,
        -- taucht die Chance in der Liste auf, aber in keiner Route - das ist
        -- besser als eine geratene Zerlegung.
        execution = fields.execution,

        -- Die in 0.6 vorbereiteten Liquiditaetsfelder. Sie sind ab 0.8 gefuellt,
        -- WENN es eigene Verkaufsdaten zu diesem Item gibt - und sonst weiter
        -- nil. Ein erfundener Standardwert waere schlimmer als eine fehlende
        -- Zahl, und "unbekannt" ist hier eine ehrliche Antwort.
        liquidity = liquidity,
        sellThrough = liquidity and liquidity.sellThrough or nil,
        expectedHours = liquidity and liquidity.expectedHours or nil,
        liquidityScore = liquidity and liquidity.liquidityScore or nil,
        liquidityConfidence = liquidity and liquidity.confidence or nil,
        profitVelocity = velocity,
        profitVelocityParts = velocityParts,

        -- Datenmodell fuer spaeter. Der Zukunft-Tab fuellt seine eigenen Felder
        -- in Future.lua; hier bleiben sie nil.
        futureDemandScore = nil,
        hypeScore = nil,
        riskScore = nil,
        catalysts = nil,
        phase = nil,
        exitWindow = nil,
    }
end

local LIQUIDITY_NOTE =
    "Liquidität und Verkaufszeit stammen ausschließlich aus deinen eigenen Verkäufen – "
    .. "ohne eigene Daten bleiben sie unbekannt."

function Opportunity:LiquidityNote()
    return LIQUIDITY_NOTE
end

-- Der Satz, der an einer Chance ohne Verkaufsdaten steht. Ausdruecklich
-- "unbekannt", nicht "schlecht" - und beim Entzaubern mit dem richtigen Grund:
-- Dort fehlt nicht die Erfahrung, sondern das Item, auf das sie sich beziehen
-- koennte.
function Opportunity:UnknownLiquidityNote(kind)
    if kind == "disenchant" then
        return "Liquidität unbekannt – was beim Entzaubern herauskommt, steht "
            .. "vorher nicht fest, also gibt es kein Item, dessen Verkaufsdaten "
            .. "hier gelten würden."
    end
    return "Liquidität unbekannt – Gold Copilot hat für dieses Item noch keinen "
        .. "eigenen Verkauf gesehen."
end

local function money(copper)
    return GCP.Prices:FormatMoney(copper)
end

local function percent(value)
    if type(value) ~= "number" then return "–" end
    return string.format("%.1f %%", value * 100)
end

-- Sammelt Erklaerzeilen und laesst nil einfach weg. Ein Tabellenkonstruktor
-- mit einem nil in der Mitte haette ein Loch, ueber das ipairs stolpert - und
-- genau solche Zeilen sind bedingt.
local function explainLines(...)
    local lines = {}
    for index = 1, select("#", ...) do
        local line = select(index, ...)
        if line ~= nil then lines[#lines + 1] = line end
    end
    return lines
end

function Opportunity:FormatROI(roi)
    return percent(roi)
end

-- Stunden lesbar: unter einem Tag mit Nachkommastelle, darueber in Tagen. Eine
-- Verkaufszeit von "0,3 Tagen" liest niemand gern.
function Opportunity:FormatHours(hours)
    if type(hours) ~= "number" then return "–" end
    if hours < 1 then
        return string.format("%d Min.", math.floor(hours * 60 + 0.5))
    end
    if hours < 48 then
        return string.format("%.1f h", hours)
    end
    return string.format("%.1f Tage", hours / 24)
end

-- ---------------------------------------------------------------------------
-- A) CONVERSION ARBITRAGE
--
-- Umwandlungen, die es im Spiel wirklich gibt und die Flips.lua bereits
-- rechnet: 10 Motes -> 1 Ur-Partikel (Einbahnstrasse) und Essenzen 3:1 in beide
-- Richtungen. Die Zahlen kommen unveraendert von dort, damit es genau eine
-- Wahrheit gibt; hier kommen nur Kapitalbedarf, ROI und Bewertung dazu.
-- ---------------------------------------------------------------------------

function Opportunity:BuildConversions(inventory)
    local C = GCP.Constants
    local Prices = GCP.Prices
    local list = {}

    for _, row in ipairs(GCP.Flips:BuildMoteRows(inventory)) do
        local cost = C.MOTES_PER_PRIMAL * row.motePrice
        local revenue = Prices:NetAuction(row.primalPrice)
        local marketScore, volatility = marketFacts(row.moteID)
        local confidence = self:ConfidenceFromDays(row.priceDays, true)
        local moteName = itemName(row.moteID)
        local primalName = row.name or itemName(row.primalID)
        local opportunity = self:Make({
            type = "conversion",
            key = "conversion:mote:" .. row.primalID,
            itemID = row.primalID,
            saleItemID = row.primalID,
            title = string.format("%s » %s", moteName, primalName),
            action = string.format("%d %s kaufen, kombinieren, %s einstellen",
                C.MOTES_PER_PRIMAL, moteName, primalName),
            icon = row.icon,
            cost = cost,
            expectedRevenue = revenue,
            marketScore = marketScore,
            volatility = volatility,
            confidence = confidence,
            priceDays = row.priceDays,
            feasible = row.ownedCombines > 0 and row.ownedCombines or nil,
            execution = {
                method = "convert",
                inputs = { { itemID = row.moteID, count = C.MOTES_PER_PRIMAL,
                    unitPrice = row.motePrice } },
                outputs = { { itemID = row.primalID, count = 1 } },
                sellItemID = row.primalID,
                sellCount = 1,
                sellUnitPrice = row.primalPrice,
                irreversible = true,
            },
            explanation = explainLines(
                string.format("Einkauf: %d × %s zu je %s = %s",
                    C.MOTES_PER_PRIMAL, moteName, money(row.motePrice), money(cost)),
                string.format("Marktpreis %s: %s", primalName, money(row.primalPrice)),
                string.format("Erlös netto (nach %d %% AH-Gebühr): %s",
                    C.AH_CUT * 100, money(revenue)),
                Prices:FormatPlanningBasis(row.priceDays),
                row.ownedMotes > 0 and string.format(
                    "Eigener Bestand: %d %s (%d Kombination(en) ohne Zukauf)",
                    row.ownedMotes, moteName, row.ownedCombines) or nil,
                "Kombinieren ist endgültig – der Weg zurück existiert nicht."
            ),
        })
        if opportunity then list[#list + 1] = opportunity end
    end

    for _, row in ipairs(GCP.Flips:BuildEssenceRows(inventory)) do
        local lesserName = itemName(row.lesserID)
        local greaterName = row.name or itemName(row.greaterID)
        local cost, revenue, itemID, title, action, buyName
        if row.direction == "up" then
            cost = C.ESSENCES_PER_GREATER * row.lesserPrice
            revenue = Prices:NetAuction(row.greaterPrice)
            itemID, buyName = row.greaterID, lesserName
            title = string.format("%s » %s", lesserName, greaterName)
            action = string.format("%d %s kaufen, umwandeln, %s einstellen",
                C.ESSENCES_PER_GREATER, lesserName, greaterName)
        else
            cost = row.greaterPrice
            revenue = C.ESSENCES_PER_GREATER * GCP.Prices:NetAuction(row.lesserPrice)
            itemID, buyName = row.lesserID, greaterName
            title = string.format("%s » %s", greaterName, lesserName)
            action = string.format("1 %s kaufen, umwandeln, %d %s einstellen",
                greaterName, C.ESSENCES_PER_GREATER, lesserName)
        end
        local buyID = row.direction == "up" and row.lesserID or row.greaterID
        local marketScore, volatility = marketFacts(buyID)
        local buyCount = row.direction == "up" and C.ESSENCES_PER_GREATER or 1
        local buyPrice = row.direction == "up" and row.lesserPrice or row.greaterPrice
        local sellCount = row.direction == "up" and 1 or C.ESSENCES_PER_GREATER
        local sellPrice = row.direction == "up" and row.greaterPrice or row.lesserPrice
        local opportunity = self:Make({
            type = "conversion",
            key = "conversion:essence:" .. row.greaterID .. ":" .. row.direction,
            itemID = itemID,
            saleItemID = itemID,
            title = title,
            action = action,
            icon = row.icon,
            cost = cost,
            expectedRevenue = revenue,
            marketScore = marketScore,
            volatility = volatility,
            confidence = self:ConfidenceFromDays(row.priceDays, true),
            priceDays = row.priceDays,
            execution = {
                method = "convert",
                inputs = { { itemID = buyID, count = buyCount, unitPrice = buyPrice } },
                outputs = { { itemID = itemID, count = sellCount } },
                sellItemID = itemID,
                sellCount = sellCount,
                sellUnitPrice = sellPrice,
                profession = "Verzauberkunst",
            },
            explanation = {
                string.format("Einkauf %s: %s", buyName, money(cost)),
                string.format("Erlös netto (nach %d %% AH-Gebühr): %s",
                    C.AH_CUT * 100, money(revenue)),
                Prices:FormatPlanningBasis(row.priceDays),
                "Benötigt Verzauberkunst.",
            },
        })
        if opportunity then list[#list + 1] = opportunity end
    end

    return list
end

-- ---------------------------------------------------------------------------
-- B) CRAFT ARBITRAGE
--
-- Die Gewinnrechnung steht seit 0.4 in Crafts:BuildReport und wird hier nicht
-- wiederholt: Erloes ist dort bereits netto, Zutaten zaehlen bereits genau
-- einmal, Rezepte ohne vollstaendige Preise tauchen dort gar nicht erst auf.
-- Dieses Modul ergaenzt Kapitalbedarf, ROI und Bewertung.
--
-- Je Produkt bleibt das beste Rezept stehen. Zwei Wege zum selben Item sind
-- fuer die Chancenliste eine Chance, nicht zwei.
-- ---------------------------------------------------------------------------

-- Die Zutatenliste aus Crafts:BuildReport ({ itemID, Anzahl, Stueckpreis })
-- in das Eingabeformat der Execution Engine. Bewusst eine eigene Tabelle: Der
-- Bericht darf sich nicht darauf verlassen, dass niemand seine Zeilen aendert.
local function craftInputs(mats)
    local inputs = {}
    for _, mat in ipairs(mats or {}) do
        if type(mat[1]) == "number" and type(mat[2]) == "number" and mat[2] > 0 then
            inputs[#inputs + 1] = { itemID = mat[1], count = mat[2], unitPrice = mat[3] }
        end
    end
    return inputs
end

function Opportunity:BuildCrafts(inventory)
    local Prices = GCP.Prices
    local report = GCP.Crafts:BuildReport(inventory)
    local best = {}
    local dropped = 0

    for _, row in ipairs(report.rows) do
        if row.profit > 0 and row.matCost > 0 then
            -- Die Marktlage der Zutaten, nicht die des Produkts: Ein
            -- historisch billiges Produkt ist fuer den, der es verkaufen will,
            -- kein Vorteil - und sein niedriger Preis steckt ohnehin schon im
            -- Erloes. Guenstige Zutaten sind das eigentliche Signal.
            local marketScore, volatility = self:BasketFacts(row.mats)
            local confidence = self:ConfidenceFromDays(row.priceDays, true)
            local opportunity = self:Make({
                type = "craft",
                key = "craft:" .. row.product,
                itemID = row.product,
                saleItemID = row.product,
                title = row.name,
                action = string.format("%s herstellen und einstellen", row.name),
                icon = row.icon,
                quality = row.quality,
                cost = row.matCost,
                expectedRevenue = row.revenue,
                marketScore = marketScore,
                volatility = volatility,
                confidence = confidence,
                priceDays = row.priceDays,
                feasible = row.craftable > 0 and row.craftable or nil,
                execution = {
                    method = "craft",
                    inputs = craftInputs(row.mats),
                    outputs = { { itemID = row.product, count = row.numMade } },
                    sellItemID = row.product,
                    sellCount = row.numMade,
                    profession = row.profession,
                    cooldown = row.hasCooldown and true or false,
                    recipeName = row.recipeName,
                },
                explanation = explainLines(
                    string.format("Beruf: %s", row.profession),
                    string.format("Materialkosten: %s", money(row.matCost)),
                    string.format("Produkterlös netto (×%.1f): %s",
                        row.numMade, money(row.revenue)),
                    string.format("Machbar aus deinem Bestand: %d×", row.craftable),
                    Prices:FormatPlanningBasis(row.priceDays),
                    row.hasCooldown and "Achtung: Rezept mit Cooldown." or nil
                ),
            })
            if opportunity then
                local existing = best[row.product]
                if not existing then
                    best[row.product] = opportunity
                else
                    dropped = dropped + 1
                    if opportunity.expectedProfit > existing.expectedProfit then
                        best[row.product] = opportunity
                    end
                end
            end
        end
    end

    local list = {}
    for _, opportunity in pairs(best) do
        list[#list + 1] = opportunity
    end
    return list, report.missingPrices, dropped
end

-- ---------------------------------------------------------------------------
-- C) DISENCHANT ARBITRAGE
--
-- Auctionator liefert ueber GetDisenchantPriceByItemLink einen Erwartungswert
-- fuer das, was beim Entzaubern herauskommt - berechnet aus den Marktpreisen
-- der moeglichen Materialien. Genau dieser Wert ist die Datenquelle; eigene
-- Drop-Wahrscheinlichkeiten werden ausdruecklich nicht erfunden.
--
-- Die AH-Gebuehr faellt genau einmal an: nicht beim Kauf des Items, sondern
-- beim Verkauf der gewonnenen Materialien. Deshalb steht NetAuction auf der
-- Erloesseite und nirgends sonst.
--
-- Geprueft werden nur Items, von denen Gold Copilot einen Item-Link hat - die
-- Auctionator-API braucht einen. In der Praxis ist das der eigene Bestand.
-- ---------------------------------------------------------------------------

local CLASS_WEAPON, CLASS_ARMOR = 2, 4

function Opportunity:IsDisenchantable(entry)
    if type(entry) ~= "table" then return false end
    if entry.bound then return false end
    if type(entry.link) ~= "string" then return false end
    if entry.classID ~= CLASS_WEAPON and entry.classID ~= CLASS_ARMOR then return false end
    if type(entry.quality) ~= "number" or entry.quality < 2 then return false end
    return true
end

function Opportunity:BuildDisenchants(inventory)
    local Prices = GCP.Prices
    local list = {}
    for itemID, entry in pairs(inventory or {}) do
        GCP.Inventory:Describe(entry)
        if self:IsDisenchantable(entry) and Prices:IsAuctionable(itemID) then
            local disenchant = Prices:GetDisenchantPrice(entry.link)
            local price, days = Prices:GetPlanningPrice(itemID)
            if disenchant and price then
                local revenue = Prices:NetAuction(disenchant)
                local marketScore, volatility = marketFacts(itemID)
                local opportunity = self:Make({
                    type = "disenchant",
                    key = "disenchant:" .. itemID,
                    itemID = itemID,
                    title = entry.name or itemName(itemID),
                    action = string.format("%s kaufen und entzaubern",
                        entry.name or itemName(itemID)),
                    icon = entry.icon,
                    quality = entry.quality,
                    cost = price,
                    expectedRevenue = revenue,
                    marketScore = marketScore,
                    volatility = volatility,
                    confidence = self:ConfidenceFromDays(days, true),
                    priceDays = days,
                    execution = {
                        method = "disenchant",
                        inputs = { { itemID = itemID, count = 1, unitPrice = price } },
                        -- Was herauskommt, steht vorher nicht fest. Deshalb
                        -- KEINE erfundene Ausgabeliste und kein sellItemID -
                        -- die Route endet hier mit "einstellen, was dabei
                        -- herauskommt".
                        outputs = nil,
                        profession = "Verzauberkunst",
                        unknownOutput = true,
                    },
                    explanation = {
                        string.format("Kaufpreis: %s", money(price)),
                        string.format("Entzauber-Erwartungswert (Auctionator): %s",
                            money(disenchant)),
                        string.format("Erlös netto der Materialien (nach %d %% AH-Gebühr): %s",
                            GCP.Constants.AH_CUT * 100, money(revenue)),
                        Prices:FormatPlanningBasis(days),
                        "Datenquelle ist Auctionators Entzauberwert – Gold Copilot "
                            .. "erfindet keine eigenen Dropchancen.",
                        "Benötigt Verzauberkunst.",
                    },
                })
                if opportunity then list[#list + 1] = opportunity end
            end
        end
    end
    return list
end

-- ---------------------------------------------------------------------------
-- D) RESALE / HISTORICAL UNDERVALUATION
--
-- Ein Item liegt deutlich unter seinem eigenen historischen Wert. Das ist die
-- einzige Chancenart, die vollstaendig auf der Markthistorie aus 0.5 beruht -
-- und die mit Abstand vorsichtigste, weil ihr das fehlt, was die anderen drei
-- haben: einen Grund, warum jemand kauft.
--
-- KONSERVATIVER ZIELPREIS: min(7-Tage-Median, 30-Tage-Median), davon die
-- AH-Gebuehr abgezogen. Warum nicht der 30-Tage-Median?
--   * Ist der 7-Tage-Median niedriger, ist der Markt gerade gefallen. Dann auf
--     den 30-Tage-Median zu setzen hiesse, auf eine Rueckkehr zu wetten, fuer
--     die es keinen Beleg gibt.
--   * Ist der 7-Tage-Median hoeher, waere es der bequemere Wert - genau
--     deshalb wird er nicht genommen. Das Minimum ist in beiden Richtungen die
--     unbequeme Wahl, und nur die ist konservativ.
--
-- Zusaetzlich muss der Market Score belastbar hoch sein (RESALE_MIN_SCORE) -
-- sonst ist ein Preis nicht "guenstig", sondern nur irgendwo in seiner Spanne.
-- Und es bleibt bei "interessant": Ohne Liquiditaet ist eine Rueckkehr zum
-- Median eine Erwartung, keine Zusage.
-- ---------------------------------------------------------------------------

function Opportunity:TargetPrice(stats)
    if type(stats) ~= "table" then return nil end
    local median7, median30 = stats.median7, stats.median30
    if type(median7) == "number" and type(median30) == "number" then
        return math.min(median7, median30)
    end
    return median30 or median7
end

function Opportunity:BuildResales()
    local Market = GCP.Market
    local Prices = GCP.Prices
    local O = config()
    local list = {}
    if not Market then return list end

    local store = Market:EnsureStore()
    if not store then return list end

    for _, itemID in ipairs(Market:GetTrackedItems()) do
        if store.items[itemID] then
            local stats = Market:GetMarketScore(itemID)
            if stats and stats.score and stats.score >= O.RESALE_MIN_SCORE
                and stats.current and stats.current > 0 then
                local target = self:TargetPrice(stats)
                if target then
                    local revenue = Prices:NetAuction(target)
                    local name = itemName(itemID)
                    local opportunity = self:Make({
                        type = "resale",
                        key = "resale:" .. itemID,
                        itemID = itemID,
                        saleItemID = itemID,
                        title = name,
                        action = string.format("%s günstig kaufen und wieder einstellen", name),
                        icon = itemIcon(itemID),
                        cost = stats.current,
                        expectedRevenue = revenue,
                        marketScore = stats.score,
                        volatility = stats.volatility,
                        confidence = stats.confidence,
                        execution = {
                            method = "resale",
                            inputs = { { itemID = itemID, count = 1,
                                unitPrice = stats.current } },
                            outputs = { { itemID = itemID, count = 1 } },
                            sellItemID = itemID,
                            sellCount = 1,
                            sellUnitPrice = target,
                        },
                        explanation = {
                            string.format("Aktueller Preis: %s%s", money(stats.current),
                                stats.currentIsLive and "" or "  (letzter gespeicherter Wert)"),
                            string.format("7d Median: %s",
                                stats.median7 and money(stats.median7) or "–"),
                            string.format("30d Median: %s",
                                stats.median30 and money(stats.median30) or "–"),
                            string.format("Konservativer Zielpreis: %s  (min aus 7d und 30d)",
                                money(target)),
                            string.format("Erlös netto (nach %d %% AH-Gebühr): %s",
                                GCP.Constants.AH_CUT * 100, money(revenue)),
                            -- Market Score und Confidence stehen ohnehin im
                            -- gemeinsamen Teil der Erklaerung; hier nur, worauf
                            -- sie beruhen.
                            string.format("Preispunkte: %d an %d Tag(en)",
                                stats.snapshots, stats.days),
                            Market:DescribeScore(stats),
                        },
                    })
                    if opportunity then list[#list + 1] = opportunity end
                end
            end
        end
    end
    return list
end

-- ---------------------------------------------------------------------------
-- Bericht
--
-- CACHE: Ein voller Durchlauf scannt den Accountbestand, bewertet alle Rezepte
-- und rechnet ueber alle beobachteten Reihen. Das darf nicht bei jedem
-- Frame-Refresh passieren. Der Cache haengt an zwei Dingen:
--   1. einer Signatur aus allem, was das Ergebnis wirklich aendert -
--      Marktstand (Market.revision), Rezeptstand (Crafts.revision), die
--      Filteroptionen, die Preisquelle und die Groesse der Watchlist;
--   2. einer kurzen Frist (CACHE_SECONDS), weil der Bestand keine
--      Invalidierungs-Ereignisse liefert - ein gepluenderter Stapel meldet
--      sich bei niemandem an.
-- Aendert sich die Signatur, wird sofort neu gerechnet, egal wie frisch der
-- Cache ist.
-- ---------------------------------------------------------------------------

local function cacheSignature()
    local db = GCP.db
    local options = (db and db.options) or {}
    local watched = 0
    for _ in pairs((db and db.watchlist) or {}) do watched = watched + 1 end
    return table.concat({
        tostring(GCP.Market and GCP.Market.revision or 0),
        tostring(GCP.Crafts and GCP.Crafts.revision or 0),
        -- Ein neues Handelsereignis aendert Score und Sortierung; ohne die
        -- Revision hier bliebe die Liste bis zum Ablauf des Caches falsch.
        tostring(GCP.Ledger and GCP.Ledger.revision or 0),
        tostring(options.opportunityMinProfit or 0),
        tostring(options.opportunityMinROI or 0),
        tostring(options.opportunitySort or "score"),
        tostring(options.priceSource or "auto"),
        tostring(watched),
    }, "|")
end

function Opportunity:Now()
    if GCP.Market then return GCP.Market:Now() end
    if type(time) == "function" then
        local ok, now = pcall(time)
        if ok and type(now) == "number" then return now end
    end
    return 0
end

function Opportunity:Invalidate()
    self.cache = nil
end

function Opportunity:GetFilters()
    local O = config()
    local options = (GCP.db and GCP.db.options) or {}
    local minProfit = options.opportunityMinProfit
    if type(minProfit) ~= "number" or minProfit < 0 then
        minProfit = O.DEFAULT_MIN_PROFIT
    end
    local minROI = options.opportunityMinROI
    if type(minROI) ~= "number" or minROI < 0 then
        minROI = O.DEFAULT_MIN_ROI
    end
    return minProfit, minROI
end

-- ---------------------------------------------------------------------------
-- Rangfolge
--
-- Standard bleibt der Opportunity Score, und das ist seit 0.8 kein Rueckschritt,
-- sondern der Grund, warum es hier keine automatische Umschaltung gibt: Die
-- Liquiditaet steckt im Score selbst. Eine Sortierung, die je nach Datenlage
-- zwischen zwei Kriterien hin und her springt, waere fuer den Nutzer nicht
-- nachvollziehbar - dieselbe Liste saehe an zwei Tagen ohne erkennbaren Grund
-- anders aus.
--
-- Die vier weiteren Modi sind ausdrueckliche Entscheidungen des Nutzers.
-- Chancen ohne die jeweilige Zahl stehen dabei immer hinten: Eine fehlende
-- Kennzahl ist kein Nullwert und darf nicht als schlechtester Platz gelesen
-- werden - sie ist gar kein Platz.
-- ---------------------------------------------------------------------------

local SORT_FIELD = {
    velocity = "profitVelocity",
    liquidity = "liquidityScore",
    profit = "expectedProfit",
    roi = "roi",
}

function Opportunity:SortModes()
    return config().SORT_MODES
end

function Opportunity:SortLabel(mode)
    return config().SORT_LABEL[mode or "score"] or "Opportunity Score"
end

function Opportunity:GetSortMode()
    local options = (GCP.db and GCP.db.options) or {}
    local mode = options.opportunitySort
    if type(mode) ~= "string" or not config().SORT_LABEL[mode] then
        return "score"
    end
    return mode
end

function Opportunity:SetSortMode(mode)
    if not GCP.db then return false end
    if type(mode) ~= "string" or not config().SORT_LABEL[mode] then return false end
    GCP.db.options.opportunitySort = mode
    return true
end

function Opportunity:CycleSortMode()
    local modes = self:SortModes()
    local current = self:GetSortMode()
    for index, mode in ipairs(modes) do
        if mode == current then
            self:SetSortMode(modes[(index % #modes) + 1])
            return self:GetSortMode()
        end
    end
    self:SetSortMode(modes[1])
    return self:GetSortMode()
end

local function sortOpportunities(list, mode)
    local field = SORT_FIELD[mode or "score"]
    table.sort(list, function(a, b)
        if field then
            local va, vb = a[field], b[field]
            if (va ~= nil) ~= (vb ~= nil) then return va ~= nil end
            if va and vb and va ~= vb then return va > vb end
        end
        if a.opportunityScore ~= b.opportunityScore then
            return a.opportunityScore > b.opportunityScore
        end
        if a.expectedProfit ~= b.expectedProfit then
            return a.expectedProfit > b.expectedProfit
        end
        return (a.title or "") < (b.title or "")
    end)
end

-- DEDUPLIKATION UND GRUPPIERUNG
--
-- Zwei Stufen, weil es zwei verschiedene Doppelungen gibt:
--   1. Dieselbe Chance zweimal (gleicher key) - das ist ein Fehler und fliegt
--      raus, die bessere bleibt.
--   2. Dasselbe Item ueber verschiedene Wege - Urfeuer kann gleichzeitig
--      historisch guenstig, Conversion-Ziel und Craft-Zutat sein. Das sind
--      echte, unabhaengige Chancen; sie bleiben getrennt, wissen aber
--      voneinander (groupSize, alsoTypes) und die Oberflaeche sagt es dazu.
local function deduplicate(list)
    local byKey = {}
    local unique = {}
    local dropped = 0
    for _, opportunity in ipairs(list) do
        local key = opportunity.key or (tostring(opportunity.type) .. ":" .. tostring(opportunity.itemID))
        local existing = byKey[key]
        if not existing then
            byKey[key] = opportunity
            unique[#unique + 1] = opportunity
        else
            dropped = dropped + 1
            if opportunity.opportunityScore > existing.opportunityScore then
                for index, candidate in ipairs(unique) do
                    if candidate == existing then
                        unique[index] = opportunity
                        break
                    end
                end
                byKey[key] = opportunity
            end
        end
    end
    return unique, dropped
end

local function group(list)
    local groups, order = {}, {}
    for _, opportunity in ipairs(list) do
        local itemID = opportunity.itemID
        local bucket = groups[itemID]
        if not bucket then
            bucket = { itemID = itemID, opportunities = {}, types = {}, typeList = {} }
            groups[itemID] = bucket
            order[#order + 1] = bucket
        end
        bucket.opportunities[#bucket.opportunities + 1] = opportunity
        if not bucket.types[opportunity.type] then
            bucket.types[opportunity.type] = true
            bucket.typeList[#bucket.typeList + 1] = opportunity.type
        end
        if not bucket.best or opportunity.opportunityScore > bucket.best.opportunityScore then
            bucket.best = opportunity
            bucket.title = opportunity.title
        end
    end
    -- Jede Chance erfaehrt, mit wem sie sich das Item teilt. Die Oberflaeche
    -- braucht das, um Mehrfachnennungen als das zu zeigen, was sie sind.
    for _, bucket in pairs(groups) do
        for _, opportunity in ipairs(bucket.opportunities) do
            opportunity.groupSize = #bucket.opportunities
            if #bucket.typeList > 1 then
                local others = {}
                for _, kind in ipairs(bucket.typeList) do
                    if kind ~= opportunity.type then
                        others[#others + 1] = kind
                    end
                end
                opportunity.alsoTypes = others
            end
        end
    end
    return groups, order
end

function Opportunity:Collect()
    local inventory = GCP.Inventory:ScanAccount()
    local all = {}
    local function append(list)
        for _, opportunity in ipairs(list or {}) do
            all[#all + 1] = opportunity
        end
    end

    append(self:BuildConversions(inventory))
    local crafts, missingPrices, droppedCrafts = self:BuildCrafts(inventory)
    append(crafts)
    append(self:BuildDisenchants(inventory))
    append(self:BuildResales())

    return all, missingPrices or 0, droppedCrafts or 0
end

function Opportunity:ComputeReport()
    local O = config()
    local minProfit, minROI = self:GetFilters()

    local all, missingPrices, droppedCrafts = self:Collect()
    local unique, duplicates = deduplicate(all)
    -- Zwei Rezepte zum selben Produkt fallen schon in BuildCrafts zusammen;
    -- fuer die Anzeige ist das dieselbe Art von Doppelung.
    duplicates = duplicates + droppedCrafts

    local shown, hiddenByProfit, hiddenByROI = {}, 0, 0
    for _, opportunity in ipairs(unique) do
        if opportunity.expectedProfit < minProfit then
            hiddenByProfit = hiddenByProfit + 1
        elseif opportunity.roi < minROI then
            hiddenByROI = hiddenByROI + 1
        else
            shown[#shown + 1] = opportunity
        end
    end

    local sortMode = self:GetSortMode()
    sortOpportunities(shown, sortMode)
    -- Gruppiert wird vor dem Deckel: Get(itemID) soll alle Chancen eines Items
    -- kennen, auch wenn die Liste nicht alle zeigt.
    local groups, groupOrder = group(shown)

    local byType = {}
    for _, opportunity in ipairs(shown) do
        byType[opportunity.type] = (byType[opportunity.type] or 0) + 1
    end

    -- Der Deckel begrenzt die Liste, nicht die Zaehlung: Wie viele Chancen
    -- gefunden wurden, bleibt shownCount - eine still gekappte Zahl waere eine
    -- Falschaussage.
    -- Wie viele Chancen ueberhaupt eine eigene Liquiditaetsaussage haben. Die
    -- Oberflaeche braucht die Zahl, um "Liquidität unbekannt" nicht an jede
    -- einzelne Zeile schreiben zu muessen.
    local withLiquidity, withVelocity = 0, 0
    for _, opportunity in ipairs(shown) do
        if opportunity.liquidityScore then withLiquidity = withLiquidity + 1 end
        if opportunity.profitVelocity then withVelocity = withVelocity + 1 end
    end

    local matched = #shown
    if #shown > O.MAX_ROWS then
        for index = #shown, O.MAX_ROWS + 1, -1 do
            shown[index] = nil
        end
    end

    return {
        opportunities = shown,
        sortMode = sortMode,
        withLiquidity = withLiquidity,
        withVelocity = withVelocity,
        groups = groups,
        groupOrder = groupOrder,
        byType = byType,
        total = #unique,
        shownCount = matched,
        listed = #shown,
        truncated = matched - #shown,
        hiddenByProfit = hiddenByProfit,
        hiddenByROI = hiddenByROI,
        duplicates = duplicates,
        missingPrices = missingPrices,
        minProfit = minProfit,
        minROI = minROI,
        computedAt = self:Now(),
    }
end

function Opportunity:BuildReport(force)
    local now = self:Now()
    local signature = cacheSignature()
    local cache = self.cache
    if not force and cache and cache.signature == signature
        and (now - cache.computedAt) < config().CACHE_SECONDS then
        return cache.report
    end

    local report = self:ComputeReport()
    self.cache = { computedAt = now, signature = signature, report = report }
    -- Nur beim echten Neuberechnen mitschreiben, nie bei einem Cache-Treffer -
    -- ein Fenster, das dreimal aufgeht, ist keine dreifache Beobachtung.
    self:LogReport(report)
    return report
end

-- Alle Chancen zu einem Item, ungefiltert nach Score sortiert. Die
-- oeffentliche Einzelabfrage der Engine.
function Opportunity:Get(itemID)
    if type(itemID) ~= "number" then return nil end
    local report = self:BuildReport()
    local bucket = report.groups[itemID]
    if not bucket then return nil end
    return bucket
end

-- ---------------------------------------------------------------------------
-- Prediction Tracking (Datenmodell fuer 0.7)
--
-- Damit spaeter ueberhaupt pruefbar wird, ob die Engine recht hatte, muss
-- festgehalten werden, was sie wann behauptet hat. Aufgeschrieben wird
-- absichtlich sparsam:
--   * nur Chancen mit belastbarer Datenlage und ab MIN_SCORE Punkten,
--   * dieselbe Chance hoechstens alle sechs Stunden,
--   * dazwischen nur, wenn sich Score oder Gewinn merklich bewegt haben,
--   * 90 Tage Aufbewahrung, harte Obergrenze an Eintraegen.
-- Ein UI-Refresh allein schreibt nie etwas: BuildReport ruft das hier nur beim
-- echten Neuberechnen auf.
--
--   db.opportunityHistory = {
--       { timestamp, type, itemID, marketPrice, expectedProfit,
--         opportunityScore, confidence }
--   }
-- ---------------------------------------------------------------------------

function Opportunity:EnsureHistory()
    local db = GCP.db
    if not db then return nil end
    if type(db.opportunityHistory) ~= "table" then db.opportunityHistory = {} end
    return db.opportunityHistory
end

function Opportunity:PruneHistory(now)
    local history = self:EnsureHistory()
    if not history then return 0 end
    local H = config().HISTORY
    now = now or self:Now()
    local cutoff = now - H.RETENTION_DAYS * 86400

    local kept = {}
    for _, entry in ipairs(history) do
        if type(entry) == "table" and type(entry.timestamp) == "number"
            and entry.timestamp >= cutoff then
            kept[#kept + 1] = entry
        end
    end
    -- Obergrenze: die aeltesten Eintraege fallen zuerst.
    local overflow = #kept - H.MAX_ENTRIES
    if overflow > 0 then
        local trimmed = {}
        for index = overflow + 1, #kept do
            trimmed[#trimmed + 1] = kept[index]
        end
        kept = trimmed
    end

    local removed = #history - #kept
    if removed > 0 then
        for index = #history, 1, -1 do history[index] = nil end
        for index = 1, #kept do history[index] = kept[index] end
    end
    return removed
end

-- Letzter Eintrag zu dieser Chance, oder nil.
function Opportunity:LastLogged(kind, itemID)
    local history = self:EnsureHistory()
    if not history then return nil end
    for index = #history, 1, -1 do
        local entry = history[index]
        if type(entry) == "table" and entry.type == kind and entry.itemID == itemID then
            return entry
        end
    end
    return nil
end

-- Ist diese Chance neu oder merklich anders als beim letzten Mal?
function Opportunity:ShouldLog(opportunity, now)
    local H = config().HISTORY
    if type(opportunity) ~= "table" then return false end
    if type(opportunity.opportunityScore) ~= "number"
        or opportunity.opportunityScore < H.MIN_SCORE then
        return false
    end
    if self:ConfidenceRank(opportunity.confidence)
        < self:ConfidenceRank(H.MIN_CONFIDENCE) then
        return false
    end
    local previous = self:LastLogged(opportunity.type, opportunity.itemID)
    if not previous then return true end
    now = now or self:Now()
    if (now - (previous.timestamp or 0)) >= H.MIN_INTERVAL then return true end

    local scoreDelta = math.abs(opportunity.opportunityScore - (previous.opportunityScore or 0))
    if scoreDelta >= H.SCORE_DELTA then return true end
    local previousProfit = previous.expectedProfit or 0
    if previousProfit > 0 then
        local change = math.abs(opportunity.expectedProfit - previousProfit) / previousProfit
        if change >= H.PROFIT_DELTA then return true end
    end
    return false
end

function Opportunity:LogReport(report, now)
    local history = self:EnsureHistory()
    if not history or type(report) ~= "table" then return 0 end
    now = now or self:Now()
    local written = 0
    for _, opportunity in ipairs(report.opportunities or {}) do
        if self:ShouldLog(opportunity, now) then
            -- 0.9.0: Vollstaendige Vorhersage statt nur Score und Gewinn.
            -- Erst damit laesst sich spaeter fragen, WELCHE Dimension etwas
            -- getaugt hat - und nicht nur, ob die Chance insgesamt aufging.
            local entry = {
                timestamp = now,
                type = opportunity.type,
                itemID = opportunity.itemID,
                marketPrice = opportunity.cost,
                expectedProfit = opportunity.expectedProfit,
                expectedROI = opportunity.roi,
                opportunityScore = opportunity.opportunityScore,
                confidence = opportunity.confidence,
                marketScore = opportunity.marketScore,
                volatility = opportunity.volatility,
                liquidityScore = opportunity.liquidityScore,
                futureDemandScore = opportunity.futureDemandScore,
                hypeScore = opportunity.hypeScore,
                phase = opportunity.phase,
            }
            if type(opportunity.catalystIDs) == "table"
                and #opportunity.catalystIDs > 0 then
                local ids = {}
                for index = 1, math.min(#opportunity.catalystIDs, 4) do
                    ids[index] = opportunity.catalystIDs[index]
                end
                entry.catalysts = ids
            end
            history[#history + 1] = entry
            written = written + 1
        end
    end
    if written > 0 then
        self:PruneHistory(now)
    end
    return written
end

-- ---------------------------------------------------------------------------
-- PREDICTION TRACKING 0.8: ERGEBNIS EINER ALTEN CHANCE
--
-- Bis 0.7 hielt das Protokoll nur fest, was die Engine wann behauptet hat. Ab
-- 0.8 gibt es zum ersten Mal eine Gegenprobe: Wurde daraus wirklich ein
-- Geschaeft, und was kam dabei heraus?
--
-- Ergaenzt werden, WENN die Zuordnung eindeutig ist:
--   executedAt, entryPrice   erster Kauf dieses Items nach der Aufzeichnung
--   soldAt, exitPrice        erster Verkauf danach
--   holdingHours             Spanne dazwischen
--   realizedProfit           (Nettoerloes - Einkauf) je Stueck x Stueckzahl
--   outcome                  WIN | LOSS | OPEN | UNKNOWN
--
-- DIE REGELN SIND ABSICHTLICH STRENG:
--   * Ein Kauf gehoert immer nur zu EINEM Protokolleintrag - dem juengsten,
--     der vor ihm liegt und noch keinen hat. Sonst wuerde ein einziger Kauf
--     fuenf alte Eintraege gleichzeitig "bestaetigen".
--   * Zwischen Aufzeichnung und Kauf duerfen hoechstens MATCH_WINDOW Stunden
--     liegen. Ein Kauf drei Wochen spaeter hat mit der damaligen Chance
--     nichts mehr zu tun.
--   * Ein bereits gesetztes Ergebnis wird nie ueberschrieben. Nur OPEN darf zu
--     WIN oder LOSS werden - das ist keine Korrektur, sondern der Abschluss.
--   * Ohne eindeutige Zuordnung passiert GAR NICHTS. Kein UNKNOWN-Eintrag,
--     keine Vermutung, keine Mutation der Historie.
--
-- 0.8 wertet daraus noch nichts aus. Es passt keine Gewichte an und lernt
-- nichts nach - es legt nur die Daten sauber ab, damit 0.9 es kann.
-- ---------------------------------------------------------------------------

local OUTCOME = { WIN = "WIN", LOSS = "LOSS", OPEN = "OPEN", UNKNOWN = "UNKNOWN" }
Opportunity.OUTCOME = OUTCOME

function Opportunity:MatchHistoryOutcomes(now)
    local history = self:EnsureHistory()
    if not history or not GCP.Ledger then return 0 end
    local H = config().HISTORY
    now = now or self:Now()

    local purchases = GCP.Ledger:GetRecentTrades(400, GCP.Ledger.KIND.PURCHASE)
    local sales = GCP.Ledger:GetRecentTrades(400, GCP.Ledger.KIND.SALE)
    if #purchases == 0 then return 0 end

    -- Protokolleintraege nach Zeit, aeltester zuerst; ein Kauf sucht sich
    -- darunter den juengsten passenden Eintrag vor sich.
    local open = {}
    for _, entry in ipairs(history) do
        if type(entry) == "table" and type(entry.timestamp) == "number"
            and type(entry.itemID) == "number" then
            open[#open + 1] = entry
        end
    end
    table.sort(open, function(a, b) return a.timestamp < b.timestamp end)

    local changed = 0
    for index = #purchases, 1, -1 do
        local purchase = purchases[index]
        if purchase.itemID and purchase.quantity then
            local candidate = nil
            for _, entry in ipairs(open) do
                if entry.itemID == purchase.itemID
                    and entry.executedAt == nil
                    and entry.timestamp <= purchase.timestamp
                    and (purchase.timestamp - entry.timestamp) <= H.MATCH_WINDOW then
                    candidate = entry
                end
            end
            if candidate then
                candidate.executedAt = purchase.timestamp
                candidate.entryPrice = purchase.unitPrice
                candidate.entryQuantity = purchase.quantity
                candidate.outcome = OUTCOME.OPEN
                changed = changed + 1
            end
        end
    end

    -- Verkaeufe schliessen offene Positionen. Ein Verkauf ohne bekannte
    -- Stueckzahl schliesst nichts: Ohne sie waere der realisierte Gewinn
    -- geraten.
    for index = #sales, 1, -1 do
        local sale = sales[index]
        if sale.itemID and sale.quantity then
            for _, entry in ipairs(open) do
                if entry.itemID == sale.itemID
                    and entry.outcome == OUTCOME.OPEN
                    and entry.executedAt
                    and sale.timestamp >= entry.executedAt then
                    local quantity = math.min(entry.entryQuantity or sale.quantity, sale.quantity)
                    local profit = (sale.unitNet - (entry.entryPrice or 0)) * quantity
                    entry.soldAt = sale.timestamp
                    entry.exitPrice = sale.unitNet
                    entry.holdingHours = (sale.timestamp - entry.executedAt) / 3600
                    entry.realizedProfit = profit
                    -- Realisierte ROI: nur, wenn der Einstand bekannt ist.
                    -- Eine ROI ohne Kostenbasis waere eine Division durch eine
                    -- Zahl, die niemand kennt.
                    local invested = (entry.entryPrice or 0) * quantity
                    if invested > 0 then
                        entry.realizedROI = profit / invested
                    end
                    entry.outcome = profit >= 0 and OUTCOME.WIN or OUTCOME.LOSS
                    changed = changed + 1
                    break
                end
            end
        end
    end
    return changed
end

-- Ausfuehrungsstatus einer Chance. Ausdruecklich nur dann gesetzt, wenn die
-- Handelsbilanz es eindeutig hergibt - nichts hiervon wird geraten.
--
--   PURCHASED  gekauft, liegt aber noch nicht im Auktionshaus
--   POSTED     eingestellt und noch offen
--   SOLD       seit dem Kauf verkauft
--   AVAILABLE  keine eigene Spur zu diesem Item
local STATUS_LABEL = {
    PURCHASED = "gekauft",
    POSTED = "eingestellt",
    SOLD = "verkauft",
}

function Opportunity:StatusLabel(status)
    return STATUS_LABEL[status or ""]
end

function Opportunity:ExecutionStatus(itemID, since)
    if not GCP.Ledger or type(itemID) ~= "number" then return "AVAILABLE" end
    local stats = GCP.Ledger:GetItemStats(itemID)
    if not stats then return "AVAILABLE" end
    if (stats.openPostings or 0) > 0 then return "POSTED" end
    local window = since or (self:Now() - config().HISTORY.MATCH_WINDOW)
    if stats.lastAt and stats.lastAt >= window then
        if (stats.soldAuctions or 0) > 0 then return "SOLD" end
        if (stats.purchases or 0) > 0 then return "PURCHASED" end
    end
    return "AVAILABLE"
end

-- ---------------------------------------------------------------------------
-- Watchlist. Die Daten liegen bei der Market Engine, weil dort die
-- Beobachtungsliste entsteht; hier stehen sie nur unter dem Namen, unter dem
-- die Oberflaeche der Chancen sie sucht.
-- ---------------------------------------------------------------------------

function Opportunity:RegisterWatchItem(itemID, reason)
    return GCP.Market:RegisterWatchItem(itemID, reason)
end

function Opportunity:RemoveWatchItem(itemID)
    return GCP.Market:RemoveWatchItem(itemID)
end

function Opportunity:IsWatched(itemID)
    return GCP.Market:IsWatched(itemID)
end

function Opportunity:ToggleWatchItem(itemID, reason)
    return GCP.Market:ToggleWatchItem(itemID, reason)
end

function Opportunity:GetWatchlist()
    return GCP.Market:GetWatchlist()
end

-- ---------------------------------------------------------------------------
-- Aufbereitung fuer die Oberflaeche
-- ---------------------------------------------------------------------------

-- Kopfzeile des Chancen-Tabs. Bewusst eine Zahl und ein Wort, kein Ausrufezeichen.
function Opportunity:SummaryText(report)
    if not report or report.shownCount == 0 then
        if report and report.total > 0 then
            return "Gold Copilot hat keine Chance über deinen Filtern gefunden"
        end
        return "Gold Copilot hat noch keine belastbare Chance gefunden"
    end
    if report.shownCount == 1 then
        return "Gold Copilot hat 1 interessante Chance gefunden"
    end
    return string.format("Gold Copilot hat %d interessante Chancen gefunden",
        report.shownCount)
end

-- Die komplette Rechnung fuer den Tooltip: erst die Zahlen der Chance, dann
-- die Einordnung, dann die Grenzen dieser Version.
function Opportunity:Explain(opportunity)
    if type(opportunity) ~= "table" then return {} end
    local lines = {}
    for _, line in ipairs(opportunity.explanation or {}) do
        lines[#lines + 1] = line
    end
    lines[#lines + 1] = " "
    lines[#lines + 1] = string.format("Kapitaleinsatz: %s", money(opportunity.cost))
    lines[#lines + 1] = string.format("Erlös netto: %s", money(opportunity.expectedRevenue))
    lines[#lines + 1] = string.format("Theoretischer Gewinn: %s",
        money(opportunity.expectedProfit))
    lines[#lines + 1] = string.format("ROI: %s", percent(opportunity.roi))
    if opportunity.feasible then
        lines[#lines + 1] = string.format("Machbar: %d×", opportunity.feasible)
    end
    lines[#lines + 1] = " "
    local band = self:ScoreBand(opportunity.opportunityScore)
    lines[#lines + 1] = string.format("Opportunity Score: %d/100  (%s)",
        opportunity.opportunityScore, band or "–")
    if type(opportunity.marketScore) == "number" then
        lines[#lines + 1] = string.format("Market Score der Kaufseite: %d/100",
            math.floor(opportunity.marketScore + 0.5))
    else
        lines[#lines + 1] = "Market Score der Kaufseite: noch keiner – zu wenig Historie"
    end
    lines[#lines + 1] = "Confidence: " .. GCP.Market:ConfidenceLabel(opportunity.confidence)

    -- DEINE VERKAUFSDATEN. Der ganze Block erscheint nur, wenn es sie gibt -
    -- und wenn nicht, steht genau ein Satz da, der das sagt.
    local liquidity = opportunity.liquidity
    lines[#lines + 1] = " "
    if liquidity then
        lines[#lines + 1] = "DEINE VERKAUFSDATEN"
        if liquidity.sellThrough then
            lines[#lines + 1] = string.format("Sell-through: %s  (%d verkauft / %d abgelaufen)",
                percent(liquidity.sellThrough),
                liquidity.soldQuantity or 0, liquidity.expiredQuantity or 0)
        elseif liquidity.sellThroughAuctions then
            lines[#lines + 1] = string.format(
                "Sell-through je Auktion: %s  (%d Verkauf/Verkäufe ohne bekannte Stückzahl)",
                percent(liquidity.sellThroughAuctions), liquidity.unmatchedSales or 0)
        end
        if liquidity.expectedHours then
            lines[#lines + 1] = string.format("Median bis Verkauf: %s",
                self:FormatHours(liquidity.expectedHours))
        else
            lines[#lines + 1] = "Median bis Verkauf: unbekannt – keine Einstellung zuzuordnen"
        end
        lines[#lines + 1] = string.format("Verkäufe: %d", liquidity.soldAuctions or 0)
        if liquidity.liquidityScore then
            local band = GCP.Ledger:ScoreBand(liquidity.liquidityScore)
            lines[#lines + 1] = string.format("Liquidity Score: %d/100  (%s · Datenlage %s)",
                liquidity.liquidityScore, band or "–",
                GCP.Market:ConfidenceLabel(liquidity.confidence))
        else
            lines[#lines + 1] = "Liquidity Score: noch keiner – zu wenig eigene Verkäufe"
        end
        if liquidity.realizedMargin and liquidity.medianBuyPrice and liquidity.medianSellPrice then
            lines[#lines + 1] = string.format(
                "Dein Einkauf (Median): %s · dein Verkauf netto: %s · realisierte Marge: %s",
                money(liquidity.medianBuyPrice), money(liquidity.medianSellPrice),
                percent(liquidity.realizedMargin))
        end
    else
        lines[#lines + 1] = self:UnknownLiquidityNote(opportunity.type)
    end

    if opportunity.profitVelocity and opportunity.profitVelocityParts then
        lines[#lines + 1] = " "
        lines[#lines + 1] = "PROFIT VELOCITY"
        lines[#lines + 1] = "+" .. GCP.Ledger:FormatVelocity(
            opportunity.profitVelocityParts.perReferenceCapital)
        lines[#lines + 1] = string.format(
            "= %s erwarteter Gewinn (%s × Sell-through) je %s Kapital in %s",
            money(opportunity.profitVelocityParts.expectedProfit),
            money(opportunity.expectedProfit), money(opportunity.cost),
            self:FormatHours(opportunity.profitVelocityParts.holdingHours))
        if opportunity.profitVelocityParts.clamped then
            lines[#lines + 1] = "Haltedauer auf die Mindestdauer angehoben – "
                .. "sonst wäre die Rate rechnerisch überzeichnet."
        end
        lines[#lines + 1] = "Die Rate gilt je eingesetztem Gold, nicht je Menge: "
            .. "Wie viele Stück der Markt am Tag abnimmt, weiß Gold Copilot nicht."
    end

    if opportunity.alsoTypes and #opportunity.alsoTypes > 0 then
        local labels = {}
        for _, kind in ipairs(opportunity.alsoTypes) do
            labels[#labels + 1] = self:TypeLabel(kind)
        end
        lines[#lines + 1] = "Dieses Item taucht auch auf als: " .. table.concat(labels, ", ")
    end
    lines[#lines + 1] = " "
    lines[#lines + 1] = "Alle Beträge sind theoretische Margen aus deinen beobachteten "
        .. "Preisen – keine Zusage."
    lines[#lines + 1] = LIQUIDITY_NOTE
    return lines
end
