local addonName, GCP = ...

GCP.Route = {}
local Route = GCP.Route

-- ---------------------------------------------------------------------------
-- ROUTE PLANNER (0.9.0)
--
-- Aus Aktionen wird eine Reihenfolge. Sieben Ziele, in dieser Rangfolge:
--
--   1. Abhaengigkeiten erfuellen        - unverhandelbar
--   2. Kapitalgrenze einhalten          - unverhandelbar
--   3. Zeitbudget einhalten             - unverhandelbar, aber gerundet
--   4. Reisewege reduzieren
--   5. Aktionen am gleichen Ort buendeln
--   6. Gewinn und Profit Velocity maximieren
--   7. Risiko beruecksichtigen
--
-- Die ersten drei sind harte Bedingungen und werden geprueft, nicht optimiert.
-- Die letzten vier sind eine Heuristik: Bei jedem Schritt wird aus den gerade
-- moeglichen Aktionen die guenstigste gewaehlt (Ortswechsel kostet, Gewinn
-- zieht). Ein exakter Rundreise-Solver waere hier verschwendet - die Zahl der
-- Orte ist einstellig, und die Reisezeiten sind ohnehin Schaetzungen.
--
-- WAS DIESES MODUL NICHT TUT:
--   * Es verspricht kein Goldziel. Findet es nur Chancen fuer 180 g, steht da
--     180 g - und daneben, dass 500 g gewuenscht waren. Ein Ziel ist ein Ziel,
--     keine Zusage.
--   * Es erfindet keine Reisezeiten je Zone. Die Reisematrix hat vier Stufen,
--     und die stehen in Constants.lua.
--   * Es sortiert eine laufende Route nicht wegen jeder Preisbewegung um
--     (siehe ShouldReplace).
-- ---------------------------------------------------------------------------

local function config()
    return GCP.Constants.ROUTE
end

local function isPositive(value)
    return type(value) == "number" and value > 0
end

Route.revision = 0

-- ---------------------------------------------------------------------------
-- Profile
--
-- Ein Profil ist kein eigener Algorithmus, sondern ein Satz Vorgaben fuer
-- denselben. Das haelt die Zahl der Wege klein, die getestet werden muessen.
-- ---------------------------------------------------------------------------

Route.PROFILE_SETUP = {
    QUICK_GOLD = {
        minutes = 30, risk = "medium", rank = "velocity",
        types = { conversion = true, resale = true, craft = true, disenchant = true },
        requireLiquidity = false,
        note = "Bevorzugt Chancen, die sich schnell wieder in Gold verwandeln.",
    },
    MAX_PROFIT = {
        minutes = 90, risk = "high", rank = "profit",
        note = "Sortiert nach absolutem Potenzial, unabhängig von der Dauer.",
    },
    LOW_RISK = {
        minutes = 60, risk = "low", rank = "score", minConfidence = "medium",
        maxVolatility = 0.35,
        note = "Nur Chancen mit belastbarer Datenlage und ruhigem Preisverlauf.",
    },
    GROW_CAPITAL = {
        minutes = 60, risk = "medium", rank = "roi",
        note = "Sortiert nach Kapitaleffizienz statt nach absolutem Gewinn.",
    },
    TRADING = {
        minutes = 45, risk = "medium", rank = "score",
        types = { resale = true, conversion = true },
        note = "Nur Auktionshaus: kaufen, umwandeln, wieder einstellen.",
    },
    CRAFTING = {
        minutes = 60, risk = "medium", rank = "profit",
        types = { craft = true },
        note = "Nur Herstellung aus gelernten Rezepten.",
    },
    FARMING = {
        minutes = 60, risk = "low", rank = "score",
        types = { farm = true },
        note = "Nur Sammelaktivitäten mit eigener, gemessener Rate.",
    },
    FUTURE_INVESTING = {
        minutes = 45, risk = "medium", rank = "future",
        types = { resale = true, conversion = true },
        note = "Bevorzugt Items mit bekannten Catalysts der kommenden Phasen.",
    },
    CUSTOM = {
        minutes = 60, risk = "medium", rank = "score",
        note = "Deine eigenen Vorgaben.",
    },
}

function Route:ProfileSetup(profile)
    return self.PROFILE_SETUP[profile] or self.PROFILE_SETUP.CUSTOM
end

function Route:ProfileLabel(profile)
    return config().PROFILE_LABEL[profile] or profile
end

-- ---------------------------------------------------------------------------
-- Reisekosten
--
-- Vier Stufen statt einer Weltkarte: gleicher Ort, gleicher Knotenpunkt (AH
-- und Briefkasten liegen in jeder Stadt beieinander), gleiche Zone, andere
-- Zone. Alles darueber hinaus waere geraten.
-- ---------------------------------------------------------------------------

local HUB_KINDS = {
    AUCTION_HOUSE = true, BANK = true, MAILBOX = true, VENDOR = true,
}

function Route:TravelMinutes(from, to)
    local T = config().TRAVEL
    if not to or to.kind == "ANYWHERE" then return 0 end
    if not from then return T.UNKNOWN end
    if from.kind == to.kind and from.key == to.key then return T.SAME_SPOT end
    if HUB_KINDS[from.kind] and HUB_KINDS[to.kind] then return T.SAME_HUB end
    if from.zone and to.zone and from.zone == to.zone then return T.SAME_ZONE end
    if to.kind == "FARM_AREA" or from.kind == "FARM_AREA" then return T.OTHER_ZONE end
    return T.SAME_ZONE
end

local function sameLocation(a, b)
    if not a or not b then return false end
    return a.kind == b.kind and a.key == b.key
end

-- ---------------------------------------------------------------------------
-- Kandidaten
-- ---------------------------------------------------------------------------

local RANKERS = {
    score = function(o) return o.opportunityScore or 0 end,
    profit = function(o) return o.expectedProfit or 0 end,
    roi = function(o) return (o.roi or 0) * 1000 end,
    velocity = function(o)
        if isPositive(o.profitVelocity) then
            return (o.opportunityScore or 0) + math.min(o.profitVelocity / 500, 40)
        end
        return (o.opportunityScore or 0) * 0.8
    end,
    future = function(o)
        return (o.opportunityScore or 0) + ((o.futureDemandScore or 50) - 50)
    end,
}

function Route:CollectOpportunities(setup, options)
    local report = GCP.Opportunity:BuildReport()
    local list = {}
    local minRank = GCP.Opportunity:ConfidenceRank(setup.minConfidence or "none")
    for _, opportunity in ipairs(report.opportunities or {}) do
        local keep = opportunity.execution ~= nil
        if keep and setup.types and not setup.types[opportunity.type] then keep = false end
        if keep and options.types and next(options.types) ~= nil
            and not options.types[opportunity.type] then
            keep = false
        end
        if keep and setup.minConfidence
            and GCP.Opportunity:ConfidenceRank(opportunity.confidence) < minRank then
            keep = false
        end
        if keep and setup.maxVolatility and isPositive(opportunity.volatility)
            and opportunity.volatility > setup.maxVolatility then
            keep = false
        end
        if keep then
            -- Zukunftssignale anreichern, wo es sie gibt. Sie aendern die
            -- Bewertung der Chance nicht - sie fliessen nur in die
            -- Positionsgroesse und in die Rangfolge des Zukunftsprofils ein.
            if GCP.Future then
                local record = GCP.Future:GetItemRecord(opportunity.saleItemID
                    or opportunity.itemID)
                if record then
                    opportunity.futureDemandScore = record.futureDemandScore
                    opportunity.hypeScore = record.hypeScore
                    opportunity.phase = record.phase
                    if type(record.catalysts) == "table" then
                        local ids = {}
                        for _, entry in ipairs(record.catalysts) do
                            if entry.catalyst and entry.catalyst.id then
                                ids[#ids + 1] = entry.catalyst.id
                            end
                        end
                        if #ids > 0 then opportunity.catalystIDs = ids end
                    end
                end
            end
            -- Wie viele Durchgaenge sind ueberhaupt sinnvoll? Bei Chancen aus
            -- dem eigenen Bestand (Entzaubern) ist der Bestand die Grenze.
            if opportunity.type == "disenchant" then
                -- Entzaubern geht nur mit dem, was im Beutel liegt. Gibt es
                -- daneben eine gemessene Angebotsmenge, gilt die kleinere der
                -- beiden Grenzen.
                local owned = opportunity.feasible or 1
                opportunity.maxUnits = opportunity.maxUnits
                    and math.min(opportunity.maxUnits, owned) or owned
            end
            opportunity.minutesPerUnit = self:MinutesPerUnit(opportunity)
            list[#list + 1] = opportunity
        end
    end

    local ranker = RANKERS[setup.rank] or RANKERS.score
    table.sort(list, function(a, b)
        local av, bv = ranker(a), ranker(b)
        if av ~= bv then return av > bv end
        return tostring(a.key) < tostring(b.key)
    end)
    return list, report
end

-- ---------------------------------------------------------------------------
-- FARMBLOECKE
--
-- Farmen kostet Zeit, kein Kapital - deshalb laeuft es nicht ueber den
-- Allocator, der Kapital verteilt. Ein Farmblock kommt nur zustande, wenn es
-- eine GEMESSENE eigene Rate gibt (Farm.lua); ohne sie waeren Minutenzahl und
-- Potenzial geraten, und geratene Zahlen haben in einer Route nichts verloren.
-- ---------------------------------------------------------------------------

function Route:CollectFarmBlocks(setup, options, minutesLeft)
    if not GCP.Farm then return {} end
    if setup.types and not setup.types.farm then return {} end
    if options.types and next(options.types) ~= nil and not options.types.farm then
        return {}
    end
    if not isPositive(minutesLeft) then return {} end
    local blocks = GCP.Farm:BuildOpportunities(minutesLeft)
    local allocations = {}
    local used = 0
    for _, block in ipairs(blocks) do
        local minutes = block.blockMinutes or 20
        if used + minutes > minutesLeft then break end
        used = used + minutes
        allocations[#allocations + 1] = {
            opportunity = block,
            key = block.key,
            type = "farm",
            itemID = block.itemID,
            title = block.title,
            units = 1,
            unitCost = 0,
            capital = 0,
            expectedProfit = block.expectedProfit,
            confidence = block.confidence,
            limitedBy = "Zeitbudget",
            factors = {},
        }
        if #allocations >= (options.maxFarmBlocks or 2) then break end
    end
    return allocations
end

-- Grobe Bedienzeit eines Durchgangs: Was die Execution Engine fuer die
-- Einzelaktionen ansetzt, hier vorab summiert. Der Planer braucht sie, bevor
-- der Plan existiert.
function Route:MinutesPerUnit(opportunity)
    local blueprint = opportunity.execution
    if type(blueprint) ~= "table" then return nil end
    local minutes = 0
    for _, input in ipairs(blueprint.inputs or {}) do
        minutes = minutes + GCP.Execution:MinutesFor("BUY", input.count or 1)
    end
    if blueprint.method == "craft" then
        minutes = minutes + GCP.Execution:MinutesFor("CRAFT", 1)
    elseif blueprint.method == "convert" then
        minutes = minutes + GCP.Execution:MinutesFor("CONVERT", 1)
    elseif blueprint.method == "disenchant" then
        minutes = minutes + GCP.Execution:MinutesFor("DISENCHANT", 1)
    end
    if blueprint.sellItemID or blueprint.unknownOutput then
        minutes = minutes + GCP.Execution:MinutesFor("POST_AUCTION", blueprint.sellCount or 1)
    end
    return minutes
end

-- ---------------------------------------------------------------------------
-- Reihenfolge
-- ---------------------------------------------------------------------------

function Route:Order(plan, startLocation)
    local current = startLocation
    local groupRank = {}
    for index, group in ipairs(plan.groups) do
        groupRank[group.id] = #plan.groups - index + 1
    end

    local order = GCP.Execution:TopologicalOrder(plan, function(ready)
        local bestIndex, bestValue = nil, nil
        for index, action in ipairs(ready) do
            local travel = self:TravelMinutes(current, action.location)
            -- Gewinn zieht, Reise kostet. Die Gewichtung ist bewusst grob:
            -- Sie soll gleichwertige Aktionen am selben Ort buendeln, nicht
            -- eine lohnende Aktion wegoptimieren.
            local pull = (groupRank[action.groupID] or 0) * 0.5
            local value = -travel + pull
            -- Bei sonst gleichem Wert gewinnt die frueher erzeugte Aktion,
            -- damit derselbe Plan immer dieselbe Route ergibt.
            if bestValue == nil or value > bestValue
                or (value == bestValue and action.index < ready[bestIndex].index) then
                bestIndex, bestValue = index, value
            end
        end
        local chosen = ready[bestIndex]
        if chosen and chosen.location and chosen.location.kind ~= "ANYWHERE" then
            current = chosen.location
        end
        return chosen, bestIndex
    end)
    return order
end

-- Setzt die Wege ein. Erst jetzt, weil erst jetzt feststeht, wohin es
-- ueberhaupt geht - und weil ein GO_TO, das schon in der Zerlegung entsteht,
-- bei jeder Umsortierung falsch waere.
function Route:InsertTravel(order, startLocation)
    local steps = {}
    local current = startLocation
    local counter = 0
    for _, action in ipairs(order) do
        local target = action.location
        if target and target.kind ~= "ANYWHERE" and not sameLocation(current, target) then
            counter = counter + 1
            local label = target.label or GCP.Execution.LOCATION_LABEL[target.kind] or "Ziel"
            steps[#steps + 1] = {
                id = "t" .. counter,
                type = "GO_TO",
                location = target,
                travel = true,
                expectedMinutes = self:TravelMinutes(current, target),
                capitalRequired = 0,
                expectedProfit = 0,
                dependencies = {},
                completionCondition = self:CompletionForLocation(target.kind),
                title = "Gehe zu: " .. label,
                detail = target.kind == "PROFESSION"
                    and "Dein Beruf – falls ein Arbeitsplatz nötig ist." or nil,
            }
            current = target
        end
        steps[#steps + 1] = action
        if target and target.kind ~= "ANYWHERE" then current = target end
    end
    return steps
end

function Route:CompletionForLocation(kind)
    local COMPLETION = GCP.Execution.COMPLETION
    if kind == "AUCTION_HOUSE" then return COMPLETION.AT_AUCTION_HOUSE end
    if kind == "BANK" then return COMPLETION.AT_BANK end
    if kind == "MAILBOX" then return COMPLETION.AT_MAILBOX end
    if kind == "PROFESSION" then return COMPLETION.AT_PROFESSION end
    if kind == "FARM_AREA" then return COMPLETION.IN_ZONE end
    return COMPLETION.MANUAL
end

-- ---------------------------------------------------------------------------
-- Budgets
-- ---------------------------------------------------------------------------

function Route:Totals(steps)
    local totals = { steps = #steps, minutes = 0, capital = 0, profit = 0,
        travelMinutes = 0, actionCount = 0 }
    for _, step in ipairs(steps) do
        totals.minutes = totals.minutes + (step.expectedMinutes or 0)
        totals.capital = totals.capital + (step.capitalRequired or 0)
        totals.profit = totals.profit + (step.expectedProfit or 0)
        if step.travel then
            totals.travelMinutes = totals.travelMinutes + (step.expectedMinutes or 0)
        else
            totals.actionCount = totals.actionCount + 1
        end
    end
    totals.minutes = math.floor(totals.minutes + 0.5)
    totals.travelMinutes = math.floor(totals.travelMinutes + 0.5)
    return totals
end

-- Welche Gruppen passen ins Zeitbudget? Gerechnet wird ueber die fertige
-- Reihenfolge: Eine Gruppe gilt als abgeschlossen, wenn ihre letzte Aktion
-- erledigt ist. Alles, was danach anfaengt, faellt weg - und zwar ganz, nicht
-- halb. Eine halbe Craft-Kette ist gebundenes Kapital ohne Verkauf.
function Route:GroupsWithinBudget(steps, minutes)
    if not isPositive(minutes) then return nil end
    local elapsed = 0
    local finished, dropped = {}, {}
    local pending = {}
    for _, step in ipairs(steps) do
        elapsed = elapsed + (step.expectedMinutes or 0)
        if step.groupID then
            pending[step.groupID] = elapsed
        end
    end
    for groupID, endsAt in pairs(pending) do
        if endsAt <= minutes then
            finished[groupID] = true
        else
            dropped[groupID] = true
        end
    end
    return finished, dropped
end

-- ---------------------------------------------------------------------------
-- Planung
-- ---------------------------------------------------------------------------

function Route:Now()
    if type(time) == "function" then
        local ok, now = pcall(time)
        if ok and type(now) == "number" then return now end
    end
    return 0
end

function Route:Plan(options)
    options = options or {}
    local C = config()
    local profile = options.profile or "CUSTOM"
    local setup = self:ProfileSetup(profile)
    local minutes = options.minutes or setup.minutes or C.DEFAULT_MINUTES
    minutes = math.max(math.min(minutes, C.MAX_MINUTES), C.MIN_MINUTES)
    local risk = options.risk or setup.risk or "medium"

    local candidates, report = self:CollectOpportunities(setup, options)
    local snapshot = GCP.Capital:GetSnapshot()
    local inventory = options.inventory or GCP.Inventory:ScanAccount()

    local allocationPlan = GCP.Capital:Allocate(candidates, {
        snapshot = snapshot,
        capital = options.capital,
        risk = risk,
        timeBudgetMinutes = minutes,
        types = options.types,
        minScore = options.minScore,
    })

    -- Farmbloecke kommen nach der Kapitalverteilung dazu: Sie konkurrieren
    -- nicht um Gold, sondern um Zeit.
    local allocations = allocationPlan.allocations
    local plannedMinutes = 0
    for _, allocation in ipairs(allocations) do
        local perUnit = allocation.opportunity and allocation.opportunity.minutesPerUnit
        if isPositive(perUnit) then
            plannedMinutes = plannedMinutes + perUnit * (allocation.units or 1)
        end
    end
    for _, block in ipairs(self:CollectFarmBlocks(setup, options,
        minutes - plannedMinutes)) do
        allocations[#allocations + 1] = block
    end

    -- Bis zu drei Durchlaeufe: Plan bauen, Reihenfolge bilden, was nicht ins
    -- Zeitbudget passt herausnehmen und noch einmal bauen. Neu bauen statt
    -- abschneiden, weil der Bestandsabgleich sonst falsche Kaufmengen behielte.
    local plan, steps, totals
    for attempt = 1, 3 do
        plan = GCP.Execution:BuildPlan(allocations, { inventory = inventory })
        local order = self:Order(plan, options.startLocation)
        steps = self:InsertTravel(order, options.startLocation)
        totals = self:Totals(steps)
        if totals.minutes <= minutes or #allocations <= 1 or attempt == 3 then
            break
        end
        local _, dropped = self:GroupsWithinBudget(steps, minutes)
        -- Gruppen ueber ihren Schluessel zuordnen, nicht ueber die Position:
        -- Eine Zuteilung ohne Bauplan erzeugt keine Gruppe, und dann waeren
        -- die Indizes verschoben - die falsche Chance floege heraus.
        local droppedKeys = {}
        for _, group in ipairs(plan.groups) do
            if dropped[group.id] then droppedKeys[group.key] = true end
        end
        local keep = {}
        for _, allocation in ipairs(allocations) do
            if not droppedKeys[allocation.key] then
                keep[#keep + 1] = allocation
            end
        end
        if #keep == #allocations then
            -- Nichts fiel heraus, obwohl die Zeit nicht reicht: dann ist schon
            -- die erste Gruppe zu lang. Die kuerzt niemand weg.
            break
        end
        if #keep == 0 then keep = { allocations[1] } end
        allocations = keep
    end

    if #steps > C.MAX_STEPS then
        for index = #steps, C.MAX_STEPS + 1, -1 do steps[index] = nil end
        totals = self:Totals(steps)
    end

    self.revision = self.revision + 1
    local route = {
        id = "r" .. self.revision,
        revision = self.revision,
        createdAt = self:Now(),
        profile = profile,
        profileLabel = self:ProfileLabel(profile),
        note = setup.note,
        risk = risk,
        budgetMinutes = minutes,
        steps = steps,
        plan = plan,
        groups = plan.groups,
        allocations = allocations,
        totals = totals,
        warnings = {},
        snapshot = snapshot,
        opportunityReport = report,
        candidates = #candidates,
    }

    for _, warning in ipairs(plan.warnings or {}) do
        route.warnings[#route.warnings + 1] = warning
    end
    for _, warning in ipairs(snapshot.warnings or {}) do
        route.warnings[#route.warnings + 1] = warning.text
    end
    -- Eine leere Route ohne Begruendung ist die schlechteste Antwort. Gab es
    -- Kandidaten, aber keine Zuteilung, steht hier, was sie verhindert hat.
    route.blocker = allocationPlan.blocker
    if #allocations == 0 and #candidates > 0 then
        route.warnings[#route.warnings + 1] = string.format(
            "%d Chance(n) gefunden, aber keine passt: %s.", #candidates,
            allocationPlan.blocker or "zu wenig freies Kapital")
    end

    route.confidence = self:Confidence(allocations)
    route.goal = self:EvaluateGoal(options.goal, totals.profit, minutes, totals.minutes)
    route.summary = self:SummaryText(route)
    return route
end

function Route:Confidence(allocations)
    if #allocations == 0 then return "none" end
    local levels = {}
    for _, allocation in ipairs(allocations) do
        levels[#levels + 1] = allocation.confidence or "none"
    end
    return GCP.Opportunity:WeakestConfidence(unpack(levels))
end

-- Ein Goldziel ist ein Ziel, keine Zusage. Findet der Planer weniger, steht
-- genau das da - und nicht die Wunschzahl.
function Route:EvaluateGoal(target, expected, budgetMinutes, plannedMinutes)
    if not isPositive(target) then
        return { target = nil, expected = expected, reachable = nil }
    end
    local reachable = expected >= target
    local text
    if reachable then
        text = string.format("Ziel %s – die geplanten Schritte kommen auf ca. %s.",
            GCP.Prices:FormatGold(target), GCP.Prices:FormatGold(expected))
    elseif expected <= 0 then
        text = string.format("Ziel %s – Gold Copilot findet derzeit keine belastbare "
            .. "Chance, mit der sich das planen ließe.", GCP.Prices:FormatGold(target))
    else
        text = string.format("Ziel %s – mit den aktuell bekannten Chancen liegt das "
            .. "geschätzte Potenzial bei ca. %s.",
            GCP.Prices:FormatGold(target), GCP.Prices:FormatGold(expected))
    end
    return {
        target = target,
        expected = expected,
        reachable = reachable,
        shortfall = math.max(target - expected, 0),
        text = text,
        budgetMinutes = budgetMinutes,
        plannedMinutes = plannedMinutes,
    }
end

function Route:SummaryText(route)
    if #route.steps == 0 then
        return "Keine Route – Gold Copilot findet gerade keine Chance, "
            .. "die zu Kapital, Zeit und Datenlage passt."
    end
    return string.format("%d Schritte · ca. %d Minuten · %s Kapital · Potenzial %s · Sicherheit %s",
        route.totals.steps, route.totals.minutes,
        GCP.Prices:FormatGold(route.totals.capital),
        GCP.Prices:FormatGold(route.totals.profit),
        GCP.Market:ConfidenceLabel(route.confidence))
end

-- ---------------------------------------------------------------------------
-- STABILITAET / HYSTERESIS
--
-- Eine laufende Route wird NICHT wegen jeder Preisbewegung umsortiert. Sie
-- wird ersetzt, wenn genau eines gilt:
--   * die laufende Route ist ungueltig geworden (Chance weg, Preis daneben),
--   * oder die neue ist MATERIELL besser: mindestens 12 % mehr erwarteter
--     Gewinn UND mindestens 5 g mehr.
--
-- Ohne diese Schwelle wuerde der Guide bei jeder Aktualisierung eine andere
-- Reihenfolge zeigen, und niemand koennte ihm folgen.
-- ---------------------------------------------------------------------------

function Route:ShouldReplace(current, candidate, reason)
    local R = config().REPLAN
    if not current then return true, "keine laufende Route" end
    if not candidate or #candidate.steps == 0 then return false, "kein besserer Plan" end
    if reason == "invalid" then return true, "laufende Route ungültig" end

    local currentValue = current.remainingProfit or current.totals.profit or 0
    local candidateValue = candidate.totals.profit or 0
    local gain = candidateValue - currentValue
    if gain <= 0 then return false, "kein Mehrwert" end
    if gain < R.MIN_GAIN_ABSOLUTE then return false, "Unterschied zu klein" end
    if currentValue > 0 and (gain / currentValue) < R.MIN_GAIN_RATIO then
        return false, "Unterschied zu klein"
    end
    return true, string.format("neuer Plan liegt %s höher", GCP.Prices:FormatGold(gain))
end

-- ---------------------------------------------------------------------------
-- Gueltigkeit einer laufenden Route
--
-- Geprueft wird nur, was sich belegen laesst: Ist der Kaufpreis ueber die
-- Grenze gelaufen? Ist der erzielbare Preis unter den Mindestpreis gefallen?
-- Alles andere (Angebot verschwunden, Rezept nicht mehr machbar) meldet die
-- Guide Engine, wenn sie es sieht.
-- ---------------------------------------------------------------------------

function Route:ValidateStep(step)
    if not step or step.travel then return true end
    local R = config().REPLAN
    if step.type == "BUY" and step.itemID and isPositive(step.maxBuyPrice) then
        local price = GCP.Prices:GetMarketPrice(step.itemID)
        if isPositive(price) and price > step.maxBuyPrice * (1 + R.PRICE_TOLERANCE) then
            return false, "price_above_max", price
        end
    end
    if step.type == "POST_AUCTION" and step.itemID and isPositive(step.minSellPrice) then
        local price = GCP.Prices:GetMarketPrice(step.itemID)
        if isPositive(price) and price < step.minSellPrice * (1 - R.PRICE_TOLERANCE) then
            return false, "price_below_min", price
        end
    end
    return true
end

function Route:Validate(route)
    if not route then return false, {} end
    local problems = {}
    for index, step in ipairs(route.steps) do
        local ok, reason, price = self:ValidateStep(step)
        if not ok then
            problems[#problems + 1] = {
                index = index, step = step, reason = reason, price = price,
            }
        end
    end
    return #problems == 0, problems
end

function Route:DescribeProblem(problem)
    if not problem then return "" end
    local step = problem.step
    local name = step.itemID and ((GetItemInfo and GetItemInfo(step.itemID))
        or ("Item " .. step.itemID)) or "Der Schritt"
    if problem.reason == "price_above_max" then
        return string.format("%s liegt mit %s über deiner maximalen Einstiegszone von %s.",
            name, GCP.Prices:FormatMoney(problem.price),
            GCP.Prices:FormatMoney(step.maxBuyPrice))
    end
    if problem.reason == "price_below_min" then
        return string.format("%s liegt mit %s unter dem geplanten Mindestpreis von %s.",
            name, GCP.Prices:FormatMoney(problem.price),
            GCP.Prices:FormatMoney(step.minSellPrice))
    end
    return "Die Marktlage hat sich geändert."
end
