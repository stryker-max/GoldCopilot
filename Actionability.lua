local addonName, GCP = ...

GCP.Actionability = {}
local Actionability = GCP.Actionability

-- ---------------------------------------------------------------------------
-- ACTIONABILITY (1.1.0)
--
-- Zwischen "die Rechnung traegt" und "tu das jetzt" fehlte eine Ebene.
--
-- Bis 1.0 wurde jede Chance mit positivem Gewinn und brauchbaren Preisdaten zur
-- Empfehlung. Das ist die Ursache der einen Empfehlung, die dieses Addon
-- niemals geben darf:
--
--     20x Nischenruestung herstellen, +180 g je Stueck
--
-- Die Rechnung stimmt. Der Preis ist belegt. Das Kapital reicht. Und trotzdem
-- ist es die schlechteste Empfehlung, die man geben kann - weil niemand fuenf
-- Brustplatten kauft, geschweige denn zwanzig.
--
-- Dieses Modul beantwortet genau eine Frage:
--
--     Reichen die BELEGE, um dieser Chance Gold und Zeit anzuvertrauen?
--
-- WAS ES NICHT TUT:
--   * Es rechnet nichts nach. Marge, ROI und Score kommen unveraendert aus der
--     Opportunity Engine.
--   * Es hebt nichts an. Eine Klasse laesst sich nur nach unten erreichen -
--     keine Zahl der Welt macht aus einer unbelegten Chance eine bewaehrte.
--   * Es verwirft nichts. Eine spekulative Chance bleibt im Chancen-Tab
--     sichtbar; sie kommt nur nicht auf die Startseite.
--
-- DIE VIER KLASSEN, absteigend:
--
--   PROVEN       Eigene Verkaufsbelege, brauchbare Sell-through, heutige Lage
--                plausibel. Darf "Beste Aktion jetzt" sein.
--   TEST         Rechnung traegt, Markt existiert, Belege fehlen. Genau ein
--                Stueck - so entsteht Evidenz ueberhaupt erst.
--   SPECULATIVE  Rechnerisch interessant, Belege zu duenn. Nur im Chancen-Tab.
--   BLOCKED      Nicht ausfuehrbar: nicht beschaffbar, Preis unbelegt.
-- ---------------------------------------------------------------------------

local function config()
    return GCP.Constants.ACTIONABILITY
end

Actionability.CLASS = {
    PROVEN = "PROVEN",
    TEST = "TEST",
    SPECULATIVE = "SPECULATIVE",
    BLOCKED = "BLOCKED",
}

function Actionability:ClassLabel(class)
    return config().CLASS_LABEL[class or ""] or class
end

-- Rangfolge fuer den Vergleich. Hoeher ist handlungsreifer.
local RANK = { BLOCKED = 0, SPECULATIVE = 1, TEST = 2, PROVEN = 3 }

function Actionability:Rank(class)
    return RANK[class or ""] or 0
end

-- ---------------------------------------------------------------------------
-- Die Einordnung
--
-- Rueckgabe:
--   { class, maxUnits, evidence, capacity, reasons, blockers }
--
-- maxUnits ist die Obergrenze AUS SICHT DER NACHFRAGE. Kapital, Exposure,
-- Angebot und Zeit begrenzen weiter unten in Capital.lua; hier steht nur, wie
-- viele Stueck die Belege tragen.
-- ---------------------------------------------------------------------------

function Actionability:Assess(opportunity, options)
    local A = config()
    local D = GCP.Constants.DEMAND
    if type(options) ~= "table" then options = {} end
    local result = {
        class = Actionability.CLASS.SPECULATIVE,
        maxUnits = 0,
        reasons = {},
        blockers = {},
    }
    if type(opportunity) ~= "table" then
        result.class = Actionability.CLASS.BLOCKED
        result.blockers[1] = "Keine Chance."
        return result
    end

    local function blocker(text)
        result.blockers[#result.blockers + 1] = text
    end
    local function reason(text)
        if text then result.reasons[#result.reasons + 1] = text end
    end

    -- --- BLOCKED: harte Ausschluesse --------------------------------------
    --
    -- Das sind keine Bewertungen, sondern Beobachtungen. Was sich nicht kaufen
    -- laesst, laesst sich nicht kaufen; ein unbelegter Preis bleibt unbelegt.
    if opportunity.pricePlausible == false then
        blocker(opportunity.priceWarning or "Der Verkaufspreis ist nicht belegt.")
    end
    if opportunity.purchasable == false then
        blocker(opportunity.purchaseWarning or "Die Kaufseite ist nicht zu beschaffen.")
    end
    if type(opportunity.expectedProfit) ~= "number" or opportunity.expectedProfit <= 0 then
        blocker("Kein positiver erwarteter Gewinn.")
    end
    if #result.blockers > 0 then
        result.class = Actionability.CLASS.BLOCKED
        return result
    end

    -- --- Belege einholen ---------------------------------------------------
    --
    -- Gefragt wird nach dem VERKAUFSITEM. Wie gut sich Urerde verkauft, sagt
    -- nichts darueber, ob jemand die daraus hergestellte Urmacht kauft.
    local saleItemID = opportunity.saleItemID
    local evidence, capacity
    if type(saleItemID) == "number" then
        evidence = GCP.Demand:EvidenceFor(saleItemID)
        capacity = GCP.Demand:CapacityFor(saleItemID, evidence)
    else
        -- Beim Entzaubern gibt es kein Verkaufsitem - was herauskommt, steht
        -- vorher nicht fest. Eine Nachfrageaussage ist damit unmoeglich, und
        -- das ist keine Luecke, sondern die Natur der Sache.
        evidence = { level = D.LEVEL.NONE, reasons = {}, caveats = {},
            label = D.LEVEL_LABEL[D.LEVEL.NONE] }
        capacity = { units = 0, basis = "kein bekanntes Verkaufsitem" }
    end
    result.evidence = evidence
    result.capacity = capacity
    result.maxUnits = capacity.units

    for _, text in ipairs(evidence.reasons or {}) do reason(text) end

    -- --- PROVEN ------------------------------------------------------------
    --
    -- ALLE Bedingungen muessen erfuellt sein. Eine Chance wird nicht dadurch
    -- bewaehrt, dass sie in drei von vier Punkten gut aussieht.
    local personal = evidence.personal
    local sellThrough = personal and personal.sellThrough
    local hours = personal and personal.medianHours

    local provenBlockers = {}
    if evidence.level < A.PROVEN_MIN_LEVEL then
        provenBlockers[#provenBlockers + 1] = string.format(
            "Belege reichen nicht: %s", evidence.label or "unbekannt")
    end
    if sellThrough == nil then
        provenBlockers[#provenBlockers + 1] = "Keine belastbare Sell-through-Rate."
    elseif sellThrough < A.PROVEN_MIN_SELL_THROUGH then
        provenBlockers[#provenBlockers + 1] = string.format(
            "Sell-through nur %.0f %%.", sellThrough * 100)
    end
    if hours and hours > A.PROVEN_MAX_HOURS then
        provenBlockers[#provenBlockers + 1] = string.format(
            "Median bis Verkauf %s – das ist kein Tagesgeschäft.",
            GCP.Opportunity:FormatHours(hours))
    end

    if #provenBlockers == 0 then
        result.class = Actionability.CLASS.PROVEN
        return result
    end
    result.provenBlockers = provenBlockers

    -- --- SPEKULATIV: die roten Flaggen -------------------------------------
    --
    -- Der Regelfall ohne Belege ist NICHT "gar nichts", sondern ein Markttest:
    -- Ein Addon, das bis zum ersten Verkauf nichts vorschlaegt, hilft niemandem
    -- zum ersten Verkauf. Spekulativ wird eine Chance erst, wenn ein konkreter
    -- Grund gegen den Versuch spricht.
    local structural = evidence.structural
    local perUnit = opportunity.cashRequired or opportunity.cost or 0

    if capacity.units <= 0 then
        result.class = Actionability.CLASS.SPECULATIVE
        result.maxUnits = 0
        result.speculativeReason = capacity.basis
            and ("Keine Menge ableitbar: " .. capacity.basis)
            or "Keine Menge ableitbar."
        return result
    end

    -- 1) Ein Versuch, der zu viel Gold bindet, ist kein Versuch mehr, sondern
    --    eine Wette. Der Unterschied ist nicht die Absicht, sondern der Betrag -
    --    und der bemisst sich am eigenen Kapital, nicht an einer festen Zahl.
    local investable = tonumber(options.investable)
    if investable and investable > 0 then
        local limit = math.max(A.TEST_MIN_CAPITAL, investable * A.TEST_MAX_SHARE)
        if perUnit > limit then
            result.class = Actionability.CLASS.SPECULATIVE
            result.maxUnits = 0
            result.speculativeReason = string.format(
                "Ein Teststück bindet %s – das sind über %.0f %% deines "
                .. "investierbaren Kapitals und damit keine Probe, sondern eine Wette.",
                GCP.Prices:FormatMoney(perUnit), A.TEST_MAX_SHARE * 100)
            return result
        end
    end

    -- 2) Ein bekannter Grund spricht gegen die kuenftige Nachfrage. Dann ist
    --    auch ein Test die falsche Richtung: Wer in ein auslaufendes Item
    --    einsteigt, lernt daraus nichts, was ihm morgen nutzt.
    if structural and structural.obsolescence == "HIGH"
        and evidence.level < D.LEVEL.REPEATED then
        result.class = Actionability.CLASS.SPECULATIVE
        result.maxUnits = 0
        result.speculativeReason =
            "Ein bekannter Grund spricht gegen die künftige Nachfrage dieses Items."
        return result
    end

    -- 3) Eine Wette auf die Rueckkehr zum Median ist kein Markttest.
    --    Ein Markttest beantwortet eine Frage ("kauft das jemand?") und ist
    --    danach klueger. Ein Lageraufbau auf einem gefallenen Markt beantwortet
    --    nichts - er wartet. Ohne eigene Verkaufsbelege bleibt er spekulativ,
    --    und zwar ausdruecklich sichtbar im Chancen-Tab.
    if opportunity.resaleKind == "reversion"
        and evidence.level < D.LEVEL.FIRST_SALE then
        result.class = Actionability.CLASS.SPECULATIVE
        result.maxUnits = 0
        result.speculativeReason =
            "Keine sofortige Preislücke – der ganze Markt liegt unter seinem Median. "
            .. "Das ist Lageraufbau auf Verdacht, kein Geschäft."
        return result
    end

    -- 4) Sehr duenner Markt ohne eigene Belege. Dort ist der eigene Verkauf
    --    nicht der Test, sondern das ganze Angebot.
    if evidence.realm and evidence.realm.supplyState == "thin"
        and evidence.level < D.LEVEL.FIRST_SALE then
        result.class = Actionability.CLASS.SPECULATIVE
        result.maxUnits = 0
        result.speculativeReason =
            "Sehr dünner Markt und kein eigener Verkauf – hier lässt sich nichts messen."
        return result
    end

    -- --- TEST --------------------------------------------------------------
    --
    -- Ein Markttest ist die einzige Art, wie Evidenz ueberhaupt entsteht.
    result.class = Actionability.CLASS.TEST
    -- Ein Test ist ein Test. Auch wenn die Kapazitaetsrechnung mehr hergeben
    -- wuerde, wird hier nicht skaliert - dafuer ist die naechste Stufe da.
    result.maxUnits = math.min(capacity.units, D.FIRST_SALE_UNITS)
    reason(evidence.level >= D.LEVEL.FIRST_SALE
        and "Erst ein einzelner eigener Verkauf – deshalb weiter vorsichtig."
        or "Noch keine eigenen Verkäufe – deshalb Markttest.")
    return result
end

-- ---------------------------------------------------------------------------
-- Erklaerung
--
-- Jede Empfehlung muss "Warum?" und "Warum diese Menge?" beantworten koennen.
-- Das ist keine Kosmetik: Eine Empfehlung, der niemand folgen kann, weil sie
-- sich nicht begruenden laesst, ist keine.
-- ---------------------------------------------------------------------------

function Actionability:Explain(assessment)
    local lines = {}
    if type(assessment) ~= "table" then return lines end
    lines[#lines + 1] = "Einordnung: " .. (self:ClassLabel(assessment.class) or "–")
    if assessment.evidence and assessment.evidence.label then
        lines[#lines + 1] = "Belege: " .. assessment.evidence.label
    end
    for _, text in ipairs(assessment.reasons or {}) do
        lines[#lines + 1] = "• " .. text
    end
    for _, text in ipairs(assessment.blockers or {}) do
        lines[#lines + 1] = "Nicht ausführbar: " .. text
    end
    for _, text in ipairs(assessment.provenBlockers or {}) do
        lines[#lines + 1] = "Gegen eine starke Empfehlung: " .. text
    end
    if assessment.speculativeReason then
        lines[#lines + 1] = assessment.speculativeReason
    end
    for _, text in ipairs((assessment.evidence or {}).caveats or {}) do
        lines[#lines + 1] = "Achtung: " .. text
    end
    if assessment.capacity then
        local text = GCP.Demand:ExplainCapacity(assessment.capacity)
        if text then lines[#lines + 1] = text end
    end
    return lines
end
