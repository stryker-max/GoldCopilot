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
    -- Gold je aktiver Stunde. Ohne bekannte Zeit gibt es sie nicht - und dann
    -- tritt diese Aktion im Zeitvergleich nicht an, sondern nur im Vergleich
    -- der Item-Aktionen untereinander.
    if isPositive(minutes) then
        candidate.goldPerHour = allocation.expectedProfit / (minutes / 60)
    end
    return candidate
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
        if rank >= minRank and isPositive(method.medianGoldPerHour)
            and method.medianGoldPerHour >= R.MIN_GOLD_PER_HOUR then
            list[#list + 1] = {
                kind = Recommendation.KIND.METHOD,
                class = "PROVEN",
                key = "method:" .. tostring(method.kind),
                title = method.label or method.kind,
                goldPerHour = method.medianGoldPerHour,
                confidence = method.confidence,
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
-- Die Entscheidung
--
-- Bewusst schlicht und in Worten nachvollziehbar:
--
--   1. Belegte Item-Aktionen (PROVEN) schlagen Markttests. Ein Test ist ein
--      Versuch, kein Geschaeft.
--   2. Eine gemessene Methode verdraengt eine belegte Item-Aktion nur, wenn
--      sie DEUTLICH mehr bringt. Bei Gleichstand gewinnt das Konkretere:
--      "kauf diese sechs" hilft mehr als "verzaubere irgendwas".
--   3. Bleibt nur ein Markttest, heisst die Antwort MARKTTEST - nicht
--      "beste Aktion".
--   4. Bleibt gar nichts, heisst die Antwort: gerade nichts. Das ist ein
--      Ergebnis, kein Fehler.
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

    local items = {}
    for _, allocation in ipairs(options.allocations or {}) do
        local candidate = self:ItemCandidate(allocation, options.route)
        if candidate then items[#items + 1] = candidate end
    end
    local methods = self:MethodCandidates()
    result.considered = #items + #methods

    -- Item-Aktionen: belegt vor Test, danach nach erwartetem Gewinn.
    table.sort(items, function(a, b)
        if (a.class == "PROVEN") ~= (b.class == "PROVEN") then
            return a.class == "PROVEN"
        end
        if a.expectedProfit ~= b.expectedProfit then
            return a.expectedProfit > b.expectedProfit
        end
        return tostring(a.key) < tostring(b.key)
    end)
    local bestItem = items[1]
    local bestMethod = methods[1]

    for _, entry in ipairs(items) do result.candidates[#result.candidates + 1] = entry end
    for _, entry in ipairs(methods) do result.candidates[#result.candidates + 1] = entry end

    -- Nichts da: Das ist eine Antwort.
    if not bestItem and not bestMethod then
        result.reason = options.blocker
            or "Keine bekannte Methode hat gerade genug Belege für eine Empfehlung."
        return result
    end

    -- Nur eine Methode.
    if not bestItem then
        result.kind = Recommendation.KIND.METHOD
        result.headline = R.HEADLINE.METHOD
        result.choice = bestMethod
        return result
    end

    -- Nur eine Item-Aktion.
    if not bestMethod then
        result.kind = Recommendation.KIND.ITEM
        result.choice = bestItem
        result.headline = bestItem.class == "PROVEN"
            and R.HEADLINE.PROVEN or R.HEADLINE.TEST
        return result
    end

    -- Beides. Eine Methode muss DEUTLICH besser sein, um zu verdraengen -
    -- und gegen einen blossen Markttest gewinnt sie ohnehin: Ein Versuch ohne
    -- Belege verliert gegen eine gemessene Rate.
    local itemRate = bestItem.goldPerHour
    local methodWins
    if bestItem.class ~= "PROVEN" then
        methodWins = true
    elseif not isPositive(itemRate) then
        -- Ohne bekannte Zeit laesst sich die Item-Aktion nicht in Gold je
        -- Stunde ausdruecken. Dann gewinnt sie: Sie ist die konkretere
        -- Aussage, und eine erfundene Zeit waere die schlechtere Grundlage.
        methodWins = false
    else
        methodWins = bestMethod.goldPerHour >= itemRate * R.METHOD_MARGIN
    end

    if methodWins then
        result.kind = Recommendation.KIND.METHOD
        result.headline = R.HEADLINE.METHOD
        result.choice = bestMethod
        result.alternative = bestItem
    else
        result.kind = Recommendation.KIND.ITEM
        result.choice = bestItem
        result.headline = bestItem.class == "PROVEN"
            and R.HEADLINE.PROVEN or R.HEADLINE.TEST
        result.alternative = bestMethod
    end
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

    local choice = result.choice
    if not choice then return lines end

    if choice.kind == Recommendation.KIND.METHOD then
        lines[#lines + 1] = string.format("Warum? Deine eigenen Daten zeigen hier %s/h "
            .. "aus %d Sitzung(en), Datenlage %s.",
            money(choice.goldPerHour), choice.sessions or 0,
            GCP.Market:ConfidenceLabel(choice.confidence))
        lines[#lines + 1] = "Diese Aktion bindet kein Kapital – sie kostet Zeit."
    else
        lines[#lines + 1] = string.format("Wie viel? %d Stück, Kapital %s.",
            choice.units or 0, money(choice.capital))
        if choice.cashRequired and choice.cashRequired < (choice.capital or 0) then
            lines[#lines + 1] = string.format(
                "Davon tatsächlich auszugeben: %s – der Rest steckt in Material, "
                .. "das du schon hast.", money(choice.cashRequired))
        end
        lines[#lines + 1] = string.format("Erwarteter Gewinn: %s.",
            money(choice.expectedProfit))
        -- "Warum diese Menge?" - die wichtigste der drei Fragen, weil sie die
        -- Antwort auf "warum nicht zwanzig?" ist.
        if choice.assessment and choice.assessment.capacity then
            local text = GCP.Demand:ExplainCapacity(choice.assessment.capacity)
            if text then lines[#lines + 1] = "Warum diese Menge? " .. text end
        end
        for _, text in ipairs((choice.assessment or {}).reasons or {}) do
            lines[#lines + 1] = "• " .. text
        end
        if choice.class == "TEST" then
            lines[#lines + 1] = "Das ist ein Versuch, keine bewährte Chance – "
                .. "nach dem ersten Verkauf weiß Gold Copilot mehr."
        end
    end

    -- "Warum ist das besser als meine Alternative?"
    local alternative = result.alternative
    if alternative then
        if alternative.kind == Recommendation.KIND.METHOD then
            lines[#lines + 1] = string.format(
                "Alternative: %s mit %s/h (Datenlage %s) – reicht nicht, um diese "
                .. "Aktion zu verdrängen.", alternative.title,
                money(alternative.goldPerHour),
                GCP.Market:ConfidenceLabel(alternative.confidence))
        else
            lines[#lines + 1] = string.format(
                "Alternative: %s (%s erwartet%s) – die gemessene Methode liegt darüber.",
                alternative.title, money(alternative.expectedProfit),
                isPositive(alternative.goldPerHour)
                    and (", " .. money(alternative.goldPerHour) .. "/h") or "")
        end
    end
    return lines
end

-- Der kurze Satz fuer die Startseite. Details gehoeren in den Tooltip.
function Recommendation:Headline(result)
    if type(result) ~= "table" then return nil, nil end
    if result.kind == Recommendation.KIND.NONE then
        return result.headline, result.reason
    end
    local choice = result.choice
    if not choice then return result.headline, nil end
    if choice.kind == Recommendation.KIND.METHOD then
        return result.headline, string.format("%s  ·  %s/h  ·  Datenlage %s",
            choice.title, GCP.Prices:FormatGold(choice.goldPerHour),
            GCP.Market:ConfidenceLabel(choice.confidence))
    end
    return result.headline, string.format("%d× %s", choice.units or 0,
        choice.title or "–")
end
