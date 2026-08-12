local addonName, GCP = ...

GCP.Recommendation = {}
local Recommendation = GCP.Recommendation

-- ---------------------------------------------------------------------------
-- RECOMMENDATION (1.1.0)
--
-- Die Startseite beantwortete bis 1.0 eine Frage, die niemand gestellt hat:
--
--     "Welches Item hat den hoechsten Opportunity Score?"
--
-- Die Frage lautet:
--
--     "Was soll ich JETZT tun?"
--
-- Der Unterschied ist nicht kosmetisch. Die erste Frage hat immer eine
-- Antwort - auch dann, wenn keine der gefundenen Chancen einen Beleg hat. Die
-- zweite darf ausdruecklich mit "gerade nichts" beantwortet werden, und genau
-- das ist manchmal die richtige Antwort.
--
-- VERGLICHEN WERDEN AKTIONEN, NICHT ITEMS. Ein Verzauberungsservice, ein
-- Farmblock und ein Flip sind drei verschiedene Geschaefte:
--
--   Active Gold/h        Farmen, Services - Gold je eingesetzter Spielzeit
--   Kapitaleffizienz     Resale, Crafts - Rendite je gebundenem Gold
--   Zeitbindung          AH-Geschaefte binden Kapital lange, Zeit kaum
--
-- Sie in EINE Kennzahl zu pressen waere genau die Vereinfachung, die falsche
-- Empfehlungen erzeugt. Verglichen wird deshalb ueber den erwarteten Gewinn je
-- AKTIVER Minute - wer fuenf Minuten braucht, um 40 g zu verdienen, und danach
-- wartet, hat aktiv 480 g/h verdient. Das Warten kostet Kapital, nicht Zeit,
-- und die Kapitalbindung steht als eigene Zeile in der Begruendung.
--
-- WAS HIER NICHT PASSIERT:
--   * Keine Zahl wird erfunden. Verglichen wird nur, was Demand, Capital und
--     Activity belegt haben.
--   * Keine Methode ohne eigene Sitzungen. Ohne Messung keine Gold/h, ohne
--     Gold/h kein Vergleich.
--   * Kein Zwang zu einem Gewinner.
-- ---------------------------------------------------------------------------

local function config()
    return GCP.Constants.RECOMMENDATION
end

local function isPositive(value)
    return type(value) == "number" and value > 0
end

local CONFIDENCE_RANK = { none = 0, low = 1, medium = 2, high = 3 }
local CONFIDENCE_NAME = { [0] = "none", [1] = "low", [2] = "medium", [3] = "high" }

Recommendation.KIND = { ITEM = "ITEM", METHOD = "METHOD", NONE = "NONE" }

-- ---------------------------------------------------------------------------
-- Kandidaten aus Item-Aktionen
--
-- Grundlage ist die fertige Zuteilung: Sie kennt Stueckzahl, Kapital und
-- erwarteten Gewinn und traegt seit 1.1 ihre Einordnung mit. Hier wird nichts
-- nachgerechnet, nur vergleichbar gemacht.
-- ---------------------------------------------------------------------------

function Recommendation:ItemCandidate(allocation, route)
    if type(allocation) ~= "table" then return nil end
    local assessment = allocation.actionability
    local class = assessment and assessment.class or nil
    if class ~= "PROVEN" and class ~= "TEST" then return nil end
    if not isPositive(allocation.expectedProfit) then return nil end

    -- Aktive Zeit: Was kostet diese Aktion an Spielzeit? Die Route weiss es;
    -- ohne Route bleibt es bei der Zeit der Aktion selbst.
    local minutes = allocation.minutes
    if not isPositive(minutes) and route and isPositive(route.totals
        and route.totals.minutes) then
        minutes = route.totals.minutes
    end
    if not isPositive(minutes) then
        local opportunity = allocation.opportunity or {}
        if isPositive(opportunity.minutesPerUnit) then
            minutes = opportunity.minutesPerUnit * (allocation.units or 1)
        end
    end

    local candidate = {
        kind = Recommendation.KIND.ITEM,
        class = class,
        key = allocation.key,
        title = allocation.title,
        units = allocation.units,
        capital = allocation.capital,
        cashRequired = allocation.cashRequired,
        expectedProfit = allocation.expectedProfit,
        confidence = allocation.confidence,
        allocation = allocation,
        assessment = assessment,
        minutes = minutes,
    }
    -- BEDIENZEIT, NICHT STUNDENRATE (1.1.0-beta.2).
    --
    -- Bis beta.1 hiess dieses Feld goldPerHour und wurde gegen die gemessene
    -- Rate einer Methode gestellt. Das war irrefuehrend: 100 g Gewinn in fuenf
    -- Minuten Bedienzeit sind keine 1200 g/h. Die Chance ist nach diesen fuenf
    -- Minuten weg, das Gold liegt zwei Tage im Auktionshaus, und wiederholen
    -- laesst sie sich auch nicht.
    --
    -- Die Zahl bleibt - sie sagt, wie viel Aufwand die Aktion macht - aber sie
    -- heisst jetzt, was sie ist, und sie tritt gegen keine Methode an.
    candidate.serviceMinutes = minutes
    if isPositive(minutes) then
        candidate.profitPerActiveHour = allocation.expectedProfit / (minutes / 60)
    end

    -- PROFIT VELOCITY als Rangfolge innerhalb der Kapitalchancen.
    --
    -- Sie ist genau die Groesse, die hier gebraucht wird, und sie liegt bereits
    -- vor: erwarteter Gewinn x eigene Sell-through, geteilt durch gebundenes
    -- Kapital und eigene Haltedauer. Alle vier Eingaben stammen aus den
    -- eigenen Verkaufsdaten - dieselben, die eine Chance ueberhaupt erst
    -- "bewaehrt" machen. Fuer PROVEN ist sie deshalb immer da.
    local opportunity = allocation.opportunity or {}
    candidate.profitVelocity = opportunity.profitVelocity
    candidate.expectedHours = opportunity.expectedHours
    candidate.sellThrough = opportunity.sellThrough
    candidate.roi = isPositive(allocation.capital)
        and (allocation.expectedProfit / allocation.capital) or nil
    return candidate
end

-- Der Rang einer Kapitalchance. Ausdruecklich NICHT der absolute Gewinn:
--
--   A: +200 g aus 2000 g Kapital, 24 h bis Verkauf
--   B: +170 g aus  300 g Kapital,  3 h bis Verkauf
--
-- A ist die groessere Zahl und das schlechtere Geschaeft. B bindet ein Siebtel
-- des Kapitals und ist am selben Abend durch.
--
-- Gerechnet wird mit der Profit Velocity, wo sie vorliegt - sie enthaelt genau
-- diese vier Groessen. Wo sie fehlt (ein Markttest hat keine eigenen
-- Verkaufsdaten), faellt die Rangfolge auf die ROI zurueck und erst dann auf
-- den absoluten Gewinn. Keine neue Kennzahl, keine Gewichtungsformel.
function Recommendation:CapitalRank(candidate)
    if type(candidate) ~= "table" then return 0, "keine Angabe" end
    if isPositive(candidate.profitVelocity) then
        return candidate.profitVelocity, "Profit Velocity"
    end
    if isPositive(candidate.roi) then return candidate.roi, "ROI" end
    return 0, "absoluter Gewinn"
end

-- ---------------------------------------------------------------------------
-- Kandidaten aus gemessenen Methoden
--
-- Eine Methode tritt nur an, wenn es eigene Sitzungen gibt. "Verzaubern
-- bringt 300 g/h" aus einem Guide waere hier genauso falsch wie eine
-- Farmrate aus einem Guide.
-- ---------------------------------------------------------------------------

function Recommendation:MethodCandidates()
    local list = {}
    if not GCP.Activity then return list end
    local R = config()
    local minRank = CONFIDENCE_RANK[R.METHOD_MIN_CONFIDENCE] or 1
    for _, method in ipairs(GCP.Activity:AllMethods()) do
        local rank = CONFIDENCE_RANK[method.confidence or "none"] or 0
        -- BRUTTORATE ZAEHLT WENIGER (1.1.0-beta.3). Konnten die Materialkosten
        -- einer Sitzung nicht bestimmt werden, ist die Rate zu hoch - um einen
        -- unbekannten Betrag. Sie wird nicht verworfen (Zeit und Ertrag sind
        -- gemessen), aber sie darf nicht als gleichwertig mit einer belegten
        -- Nettorate gelten. Eine Stufe weniger, und die Kennzeichnung wandert
        -- mit bis in die Erklaerung.
        if method.netKnown == false and rank > 0 then rank = rank - 1 end
        if rank >= minRank and isPositive(method.medianGoldPerHour)
            and method.medianGoldPerHour >= R.MIN_GOLD_PER_HOUR then
            list[#list + 1] = {
                kind = Recommendation.KIND.METHOD,
                class = "PROVEN",
                key = "method:" .. tostring(method.kind),
                title = method.label or method.kind,
                -- Eine gemessene, wiederholbare Stundenrate. Nicht zu
                -- verwechseln mit dem Gewinn je Bedienminute einer
                -- Kapitalchance - das ist eine andere Groesse.
                goldPerHour = method.medianGoldPerHour,
                confidence = method.confidence,
                -- Die abgewertete Stufe, mit der die Methode wirklich antritt.
                effectiveConfidence = CONFIDENCE_NAME[rank] or method.confidence,
                netKnown = method.netKnown ~= false,
                grossOnlySessions = method.grossOnlySessions,
                sessions = method.sessions,
                method = method,
                -- Eine Methode bindet kein Kapital. Genau das ist ihr
                -- Vorteil gegenueber einem Flip - und er gehoert in die
                -- Begruendung, nicht in die Zahl.
                capital = 0,
            }
        end
    end
    return list
end

-- ---------------------------------------------------------------------------
-- DIE ENTSCHEIDUNG (1.1.0-beta.2: zwei Kategorien statt eines Siegers)
--
-- Bis beta.1 wurde ein Gewinner gekuert - und dafuer eine Kapitalchance ueber
-- ihren Gewinn je Bedienminute mit einer gemessenen Stundenrate verglichen.
-- Diese beiden Zahlen beschreiben verschiedene Dinge:
--
--   250 g/h Verzauberungsservice  eine reale, wiederholbare Rate. Wer zwei
--                                 Stunden steht, verdient ungefaehr 500 g.
--   1200 g/h "aktiv" aus einem Flip   nicht wiederholbar (die Chance ist nach
--                                 fuenf Minuten weg), 5000 g gebunden, 48
--                                 Stunden Wartezeit, Verkaufsrisiko.
--
-- Deshalb entscheidet die Engine nicht mehr zwischen ihnen. Sie zeigt beide,
-- jede mit ihrer eigenen Zahl, und ueberlaesst dem Spieler die einzige Frage,
-- die eine Formel nicht beantworten kann: Habe ich jetzt eine Stunde Zeit -
-- oder will ich nebenbei Kapital einsetzen?
--
-- Verglichen wird nur INNERHALB einer Kategorie:
--   * Methoden nach gemessener Gold/h.
--   * Kapitalchancen nach Profit Velocity (siehe CapitalRank).
--
-- Ein Markttest ist keine Kapitalchance. Er tritt nur an, wenn es keine
-- belegte gibt - ein Versuch ist keine Empfehlung.
-- ---------------------------------------------------------------------------

function Recommendation:Best(options)
    if type(options) ~= "table" then options = {} end
    local R = config()
    local result = {
        kind = Recommendation.KIND.NONE,
        headline = R.HEADLINE.NONE,
        candidates = {},
        considered = 0,
    }

    local proven, tests = {}, {}
    for _, allocation in ipairs(options.allocations or {}) do
        local candidate = self:ItemCandidate(allocation, options.route)
        if candidate then
            if candidate.class == "PROVEN" then
                proven[#proven + 1] = candidate
            else
                tests[#tests + 1] = candidate
            end
        end
    end
    local methods = self:MethodCandidates()
    result.considered = #proven + #tests + #methods

    -- Kapitalchancen nach wirtschaftlicher Attraktivitaet, nicht nach der
    -- groessten Zahl.
    local function sortCapital(list)
        table.sort(list, function(a, b)
            local av = Recommendation:CapitalRank(a)
            local bv = Recommendation:CapitalRank(b)
            if av ~= bv then return av > bv end
            -- Gleichstand: der groessere Gewinn, dann der Schluessel - damit
            -- derselbe Datenstand immer dieselbe Reihenfolge ergibt.
            if a.expectedProfit ~= b.expectedProfit then
                return a.expectedProfit > b.expectedProfit
            end
            return tostring(a.key) < tostring(b.key)
        end)
    end
    sortCapital(proven)
    sortCapital(tests)

    for _, entry in ipairs(proven) do result.candidates[#result.candidates + 1] = entry end
    for _, entry in ipairs(methods) do result.candidates[#result.candidates + 1] = entry end
    for _, entry in ipairs(tests) do result.candidates[#result.candidates + 1] = entry end

    result.activeMethod = methods[1]
    result.capitalOpportunity = proven[1]
    if proven[1] then
        _, result.capitalRankBasis = self:CapitalRank(proven[1])
    end

    -- Beide Kategorien belegt: beide zeigen. Kein kuenstlicher Sieger.
    if result.activeMethod and result.capitalOpportunity then
        result.kind = "BOTH"
        result.headline = R.HEADLINE.BOTH
        return result
    end
    if result.activeMethod then
        result.kind = Recommendation.KIND.METHOD
        result.headline = R.HEADLINE.METHOD
        result.choice = result.activeMethod
        return result
    end
    if result.capitalOpportunity then
        result.kind = Recommendation.KIND.ITEM
        result.headline = R.HEADLINE.ITEM
        result.choice = result.capitalOpportunity
        return result
    end

    -- Nur ein Markttest. Er heisst auch so - ein Versuch ist keine Empfehlung.
    if tests[1] then
        result.kind = "TEST"
        result.headline = R.HEADLINE.TEST
        result.choice = tests[1]
        result.test = tests[1]
        return result
    end

    result.reason = options.blocker
        or "Keine bekannte Methode hat gerade genug Belege für eine Empfehlung."
    return result
end

-- ---------------------------------------------------------------------------
-- ERKLAERUNG
--
-- Jede Empfehlung muss drei Fragen beantworten koennen: Warum? Warum diese
-- Menge? Warum ist das besser als die Alternative? Eine Empfehlung, der
-- niemand folgen kann, weil sie sich nicht begruenden laesst, ist keine.
-- ---------------------------------------------------------------------------

function Recommendation:Explain(result)
    local lines = {}
    if type(result) ~= "table" then return lines end
    local money = function(value) return GCP.Prices:FormatGold(value or 0) end

    if result.kind == Recommendation.KIND.NONE then
        lines[#lines + 1] = result.reason or "Gerade keine belastbare Aktion."
        if result.considered > 0 then
            lines[#lines + 1] = string.format(
                "%d Möglichkeit(en) geprüft – keine davon hat genug Belege.",
                result.considered)
        end
        lines[#lines + 1] = "Nichts zu tun ist besser als eine schlechte Empfehlung."
        return lines
    end

    -- Eine Methode: gemessene, wiederholbare Stundenrate.
    local method = result.activeMethod
    if method then
        lines[#lines + 1] = "AKTIVE METHODE: " .. (method.title or "–")
        lines[#lines + 1] = string.format(
            "Warum? Deine eigenen Daten zeigen hier %s/h aus %d Sitzung(en), "
            .. "Datenlage %s.", money(method.goldPerHour), method.sessions or 0,
            GCP.Market:ConfidenceLabel(method.confidence))
        lines[#lines + 1] = "Das ist eine gemessene Stundenrate: Wer zwei Stunden "
            .. "dransitzt, verdient ungefähr das Doppelte. Kapital bindet sie keines."
        if method.netKnown == false then
            lines[#lines + 1] = string.format(
                "Achtung: Bei %d Sitzung(en) waren die eigenen Materialkosten nicht "
                .. "bestimmbar. Die Rate gilt deshalb BRUTTO – der tatsächliche "
                .. "Ertrag liegt darunter, um einen unbekannten Betrag.",
                method.grossOnlySessions or 0)
        end
    end

    -- Eine Kapitalchance: erwarteter Gewinn aus gebundenem Gold.
    local capital = result.capitalOpportunity or result.test
        or (result.choice and result.choice.kind == Recommendation.KIND.ITEM
            and result.choice or nil)
    if capital then
        if method then lines[#lines + 1] = " " end
        lines[#lines + 1] = (capital.class == "PROVEN" and "KAPITALCHANCE: "
            or "MARKTTEST: ") .. string.format("%d× %s", capital.units or 0,
            capital.title or "–")
        lines[#lines + 1] = string.format("Erwarteter Gewinn %s bei %s Kapital.",
            money(capital.expectedProfit), money(capital.capital))
        if capital.cashRequired and capital.cashRequired < (capital.capital or 0) then
            lines[#lines + 1] = string.format(
                "Davon tatsächlich auszugeben: %s – der Rest steckt in Material, "
                .. "das du schon hast.", money(capital.cashRequired))
        end
        if isPositive(capital.serviceMinutes) then
            -- Ausdruecklich BEDIENZEIT und nicht "Stundenrate": Die Chance ist
            -- danach weg, das Gold liegt weiter im Auktionshaus.
            lines[#lines + 1] = string.format(
                "Bedienzeit ca. %d Minute(n) – danach wartet das Kapital, nicht du.",
                math.ceil(capital.serviceMinutes))
        end
        if isPositive(capital.expectedHours) then
            lines[#lines + 1] = string.format("Typisch bis zum Verkauf: %s%s.",
                GCP.Opportunity:FormatHours(capital.expectedHours),
                isPositive(capital.sellThrough) and string.format(
                    " · %.0f %% deiner Auktionen gehen durch",
                    capital.sellThrough * 100) or "")
        end
        if result.capitalRankBasis and capital.class == "PROVEN" then
            lines[#lines + 1] = "Vorgereiht nach: " .. result.capitalRankBasis
                .. " – nicht nach dem größten absoluten Gewinn."
        end
        if capital.assessment and capital.assessment.capacity then
            local text = GCP.Demand:ExplainCapacity(capital.assessment.capacity)
            if text then lines[#lines + 1] = "Warum diese Menge? " .. text end
        end
        for _, text in ipairs((capital.assessment or {}).reasons or {}) do
            lines[#lines + 1] = "• " .. text
        end
        if capital.class == "TEST" then
            lines[#lines + 1] = "Das ist ein Versuch, keine bewährte Chance – "
                .. "nach dem ersten Verkauf weiß Gold Copilot mehr."
        end
    end

    -- Warum kein Sieger? Weil die beiden Zahlen verschiedene Dinge messen.
    if result.kind == "BOTH" then
        lines[#lines + 1] = " "
        lines[#lines + 1] = "Beide stehen nebeneinander, weil sie sich nicht "
            .. "seriös vergleichen lassen: Die eine ist eine wiederholbare "
            .. "Stundenrate, die andere ein einmaliger Gewinn aus gebundenem "
            .. "Gold. Hast du jetzt eine Stunde Zeit, nimm die Methode; willst "
            .. "du nebenbei Kapital einsetzen, die Kapitalchance."
    end
    return lines
end

-- Der kurze Satz fuer die Startseite. Details gehoeren in den Tooltip.
function Recommendation:Headline(result)
    if type(result) ~= "table" then return nil, nil end
    if result.kind == Recommendation.KIND.NONE then
        return result.headline, result.reason
    end
    local money = function(value) return GCP.Prices:FormatGold(value or 0) end
    if result.kind == "BOTH" then
        return result.headline, string.format("%s ≈ %s/h  ·  %d× %s für %s",
            result.activeMethod.title, money(result.activeMethod.goldPerHour),
            result.capitalOpportunity.units or 0,
            result.capitalOpportunity.title or "–",
            money(result.capitalOpportunity.capital))
    end
    local choice = result.choice
    if not choice then return result.headline, nil end
    if choice.kind == Recommendation.KIND.METHOD then
        return result.headline, string.format("%s  ·  %s/h  ·  Datenlage %s",
            choice.title, money(choice.goldPerHour),
            GCP.Market:ConfidenceLabel(choice.confidence))
    end
    return result.headline, string.format("%d× %s", choice.units or 0,
        choice.title or "–")
end
