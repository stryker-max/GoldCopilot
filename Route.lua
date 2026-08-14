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
    if type(to) ~= "table" or to.kind == "ANYWHERE" then return 0 end
    if type(from) ~= "table" then return T.UNKNOWN end
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

local function locationKey(spec)
    if type(spec) ~= "table" or not spec.kind then return "?" end
    return spec.kind .. "|" .. tostring(spec.key)
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

-- Die Rangfolge eines Profils, damit sie die Kapitalverteilung ueberhaupt
-- erreicht (1.1.0-beta.7).
--
-- Bis beta.6 sortierte CollectOpportunities die Chancen weiter unten nach dem
-- Profil - und Capital:Allocate sortierte dieselbe Liste unmittelbar danach
-- nach seinem eigenen RankValue neu. Das Profil-Ranking wurde also gerechnet
-- und weggeworfen. Sichtbar war das als immer derselben Route: "Zukunft" und
-- "Handel" haben dieselben Chancenarten und unterschieden sich nur im Rang -
-- also in nichts.
function Route:Ranker(key)
    return RANKERS[key]
end

-- ---------------------------------------------------------------------------
-- WAS SCHON IM AUKTIONSHAUS LIEGT, IST KEINE NEUE CHANCE (1.1.0-beta.5)
--
-- Wer eine Route abgeschlossen hat, hat das Ergebnis eingestellt. Bis beta.4
-- schlug der Planer unmittelbar danach dieselbe Route noch einmal vor: Die
-- Chance war ja unveraendert gut. Nur ist das Kapital jetzt gebunden, und ob
-- die Rechnung aufgeht, weiss erst der Verkauf.
--
-- Belegt ist das aus der eigenen Handelsbilanz: Capital fuehrt jede offene
-- Einstellung als Position mit source = "auction". Es ist keine Vermutung,
-- sondern die eigene Auktion.
-- ---------------------------------------------------------------------------
function Route:PostedItems(snapshot)
    local posted = {}
    if type(snapshot) ~= "table" then return posted end
    for _, position in ipairs(snapshot.positions or {}) do
        if type(position) == "table" and position.source == "auction"
            and isPositive(position.quantity) and position.itemID then
            posted[position.itemID] = position.quantity
        end
    end
    return posted
end

-- Welches Item entsteht am Ende dieser Chance? Bei einem Craft das Produkt,
-- beim Weiterverkauf das Item selbst. Ohne Verkaufsitem (Entzaubern) gibt es
-- nichts zu vergleichen.
local function saleItemOf(opportunity)
    local blueprint = opportunity.execution
    if type(blueprint) == "table" then
        if blueprint.unknownOutput then return nil end
        if blueprint.sellItemID then return blueprint.sellItemID end
    end
    return opportunity.saleItemID or opportunity.itemID
end

-- Rueckgabe: Kandidaten, Chancenbericht, Liste der zurueckgestellten Chancen.
function Route:CollectOpportunities(setup, options, snapshot)
    if type(setup) ~= "table" then setup = {} end
    if type(options) ~= "table" then options = {} end
    local report = GCP.Opportunity:BuildReport()
    local list = {}
    local waiting = {}
    local posted = self:PostedItems(snapshot)
    local minRank = GCP.Opportunity:ConfidenceRank(setup.minConfidence or "none")
    for _, opportunity in ipairs(report.opportunities or {}) do
        local keep = opportunity.execution ~= nil
        if keep then
            local saleItemID = saleItemOf(opportunity)
            local open = saleItemID and posted[saleItemID] or nil
            if open then
                keep = false
                waiting[#waiting + 1] = {
                    key = opportunity.key,
                    title = opportunity.title,
                    itemID = saleItemID,
                    quantity = open,
                }
            end
        end
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
            -- ---------------------------------------------------------------
            -- WIE VIELE DURCHGAENGE SIND MOEGLICH? (Semantik seit 1.0.0-beta.10)
            --
            -- Die Frage hat vier verschiedene Antworten, und sie wurden bis
            -- beta.9 in einem einzigen Feld "feasible" vermischt - das
            -- ausserdem nur beim Entzaubern ueberhaupt mengenwirksam war.
            --
            --   feasibleFromStock  aus vorhandenem Bestand machbar
            --   maxUnits           mit zusaetzlichen Kaeufen machbar
            --   maxUnits == 0      Markt gibt nichts her und Bestand auch nicht
            --   supplyKnown=false  unbekannt: maxUnits ist dann die Obergrenze
            --                      aus dem, was GEMESSEN wurde - nicht die
            --                      Zusage, dass so viel geht
            --
            -- Crafts werden bewusst NICHT auf den Bestand begrenzt: Zukaufen
            -- ist erlaubt und meistens der Sinn der Sache. Begrenzt wird, was
            -- der Markt nach eigener Messung hergibt - und das rechnet
            -- Opportunity:SupplyFor jetzt ueber alle Zutaten.
            if opportunity.type == "disenchant" then
                -- Entzaubern ist die Ausnahme: Es geht ausschliesslich mit
                -- dem, was im Beutel liegt - das Item wird dabei verbraucht
                -- und nicht nachgekauft. Gibt es daneben eine gemessene
                -- Angebotsmenge, gilt die kleinere der beiden Grenzen.
                local owned = opportunity.feasibleFromStock or opportunity.feasible or 1
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
    table.sort(waiting, function(a, b)
        return tostring(a.key) < tostring(b.key)
    end)
    return list, report, waiting
end

-- Der Satz zu einer zurueckgestellten Chance. Er sagt, WARUM sie fehlt - eine
-- Chance, die kommentarlos verschwindet, sieht aus wie ein Fehler.
function Route:WaitingText(entry)
    if type(entry) ~= "table" then return nil end
    local name = entry.itemID
        and ((GetItemInfo and GetItemInfo(entry.itemID)) or ("Item " .. entry.itemID))
        or (entry.title or "Diese Chance")
    return string.format("%d× %s liegt schon im Auktionshaus – erst das "
        .. "Ergebnis abwarten.", math.floor(entry.quantity or 1), name)
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
    if type(setup) ~= "table" then setup = {} end
    if type(options) ~= "table" then options = {} end
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
    if type(opportunity) ~= "table" then return nil end
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

-- ---------------------------------------------------------------------------
-- REIHENFOLGE: DER ORT SCHLAEGT DEN RANG (1.1.0-beta.5)
--
-- Bis beta.4 stand hier eine Abwaegung: Reisezeit kostet, Gruppenrang zieht.
-- Bei drei Chancen ging das gut. Bei zwoelf gewann der Rang, und die Route
-- lief Gruppe fuer Gruppe ab - Auktionshaus, herstellen, einstellen, zurueck
-- zum Auktionshaus, herstellen, einstellen. Zwoelf Wege, wo einer gereicht
-- haette.
--
-- Die Regel ist jetzt einfacher und in dieser Reihenfolge zwingend:
--
--   1. Was am aktuellen Ort erledigt werden kann, wird jetzt erledigt.
--      Ausnahmslos. Ein Schritt an Ort und Stelle kostet keine Reise, also
--      gibt es keinen Grund, ihn aufzuheben.
--   2. Ist hier nichts mehr offen, entscheidet der naechste Ort - und zwar
--      nach Weg UND nach der Menge Arbeit, die dort wartet. Ein Gang, der
--      acht Schritte erledigt, ist einen laengeren Weg wert als einer, der
--      einen erledigt.
--   3. Der Gruppenrang entscheidet nur noch Gleichstaende.
--
-- Was dabei herauskommt, ist der Ablauf, den ein Mensch von selbst waehlt:
-- einmal einkaufen, einmal Post holen, alles herstellen, alles einstellen.
-- ---------------------------------------------------------------------------

function Route:Order(plan, startLocation)
    local current = startLocation
    local groupRank = {}
    for index, group in ipairs(plan.groups) do
        groupRank[group.id] = #plan.groups - index + 1
    end

    local order = GCP.Execution:TopologicalOrder(plan, function(ready)
        -- Wieviel Arbeit wartet je Ziel? Wird bei jedem Schritt neu gezaehlt;
        -- die Liste der offenen Aktionen ist einstellig bis zweistellig.
        local waiting = {}
        for _, action in ipairs(ready) do
            local key = locationKey(action.location)
            waiting[key] = (waiting[key] or 0) + 1
        end

        local hereIndex, hereValue = nil, nil
        local nextIndex, nextValue = nil, nil
        for index, action in ipairs(ready) do
            local travel = self:TravelMinutes(current, action.location)
            if travel <= 0 then
                -- Hier und jetzt. Unter diesen entscheidet der Rang.
                local value = groupRank[action.groupID] or 0
                if hereValue == nil or value > hereValue
                    or (value == hereValue and action.index < ready[hereIndex].index) then
                    hereIndex, hereValue = index, value
                end
            else
                local value = -travel
                    + (waiting[locationKey(action.location)] or 0) * 0.75
                    + (groupRank[action.groupID] or 0) * 0.05
                if nextValue == nil or value > nextValue
                    or (value == nextValue and action.index < ready[nextIndex].index) then
                    nextIndex, nextValue = index, value
                end
            end
        end

        local chosenIndex = hereIndex or nextIndex
        local chosen = chosenIndex and ready[chosenIndex] or nil
        if chosen and chosen.location and chosen.location.kind ~= "ANYWHERE" then
            current = chosen.location
        end
        return chosen, chosenIndex
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
    if kind == "VENDOR" then return COMPLETION.AT_VENDOR end
    if kind == "FARM_AREA" then return COMPLETION.IN_ZONE end
    return COMPLETION.MANUAL
end

-- ---------------------------------------------------------------------------
-- Budgets
-- ---------------------------------------------------------------------------

function Route:Totals(steps)
    if type(steps) ~= "table" then steps = {} end
    local totals = { steps = #steps, minutes = 0, capital = 0, profit = 0,
        travelMinutes = 0, actionCount = 0 }
    for _, step in ipairs(steps) do
        if type(step) ~= "table" then step = {} end
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

-- ---------------------------------------------------------------------------
-- ZEITBUDGET: WELCHE CHANCE FAELLT RAUS?
--
-- Bis beta.4 galt eine Gruppe als "passt nicht", wenn ihre letzte Aktion nach
-- Ablauf des Budgets lag. Das setzte voraus, dass die Gruppen NACHEINANDER
-- abgearbeitet werden - genau das tun sie seit der Ortsbuendelung nicht mehr.
-- Jetzt enden alle ungefaehr gleichzeitig, und die alte Rechnung haette
-- entweder alle oder keine gestrichen.
--
-- Gestrichen wird deshalb von hinten: Die Zuteilungen stehen nach
-- Attraktivitaet sortiert, die letzte ist die schwaechste. Sie faellt ganz
-- weg, nicht halb - eine halbe Craft-Kette ist gebundenes Kapital ohne
-- Verkauf. Die erste bleibt immer stehen; passt schon sie nicht ins Budget,
-- ist das eine Aussage ueber das Budget und keine ueber die Chance.
--
-- Reisezeit gehoert dabei keiner Gruppe: Ein Weg zum Auktionshaus dient
-- allen, die dort etwas vorhaben.
-- ---------------------------------------------------------------------------
function Route:TrimToBudget(plan, allocations, steps, plannedMinutes, budgetMinutes)
    if not isPositive(budgetMinutes) then return allocations end
    local perGroup = {}
    for _, step in ipairs(steps) do
        if step.groupID and not step.travel then
            perGroup[step.groupID] = (perGroup[step.groupID] or 0)
                + (step.expectedMinutes or 0)
        end
    end
    local perKey = {}
    for _, group in ipairs(plan.groups or {}) do
        if group.key then
            perKey[group.key] = (perKey[group.key] or 0) + (perGroup[group.id] or 0)
        end
    end

    local drop, remaining = {}, plannedMinutes
    for index = #allocations, 2, -1 do
        if remaining <= budgetMinutes then break end
        drop[index] = true
        remaining = remaining - (perKey[allocations[index].key] or 0)
    end
    local keep = {}
    for index, allocation in ipairs(allocations) do
        if not drop[index] then keep[#keep + 1] = allocation end
    end
    if #keep == 0 then keep = { allocations[1] } end
    return keep
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
    if type(options) ~= "table" then options = {} end
    local C = config()
    local profile = options.profile or "CUSTOM"
    local setup = self:ProfileSetup(profile)
    local minutes = options.minutes or setup.minutes or C.DEFAULT_MINUTES
    minutes = math.max(math.min(minutes, C.MAX_MINUTES), C.MIN_MINUTES)
    local risk = options.risk or setup.risk or "medium"

    local snapshot = GCP.Capital:GetSnapshot()
    local candidates, report, waiting = self:CollectOpportunities(setup, options, snapshot)
    local inventory = options.inventory or GCP.Inventory:ScanAccount()

    -- WO STEHT DER SPIELER GERADE? Bis beta.4 hat das niemand gefragt, und
    -- options.startLocation kam von keinem Aufrufer. Ergebnis: Jede Route -
    -- auch jede NEUgeplante mitten im Auktionshaus - begann mit "Gehe zu:
    -- Auktionshaus, ca. 4 Minuten". Die vier Minuten waren der UNKNOWN-Wert
    -- der Reisematrix, also die Antwort "keine Ahnung, wo du bist".
    --
    -- Die Antwort liegt vor: Navigation kennt die selbst besuchten Orte und
    -- die eigene Position. Steht der Spieler an keinem bekannten Ort, bleibt
    -- es bei nil - und damit beim alten Verhalten.
    local startLocation = options.startLocation
    if startLocation == nil and GCP.Navigation then
        startLocation = GCP.Navigation:CurrentLocation()
    end

    local allocationPlan = GCP.Capital:Allocate(candidates, {
        snapshot = snapshot,
        capital = options.capital,
        risk = risk,
        timeBudgetMinutes = minutes,
        types = options.types,
        minScore = options.minScore,
        -- Die Rangfolge des Profils. Ohne sie sortiert der Allokator nach
        -- seinem eigenen Mass, und jedes Profil endet bei derselben Reihenfolge
        -- (siehe Route:Ranker).
        rank = setup.rank,
        -- Vom Nutzer gewaehlte Stueckzahlen je Chance (1.0.0-beta.6).
        unitLimits = options.unitLimits,
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
        local order = self:Order(plan, startLocation)
        steps = self:InsertTravel(order, startLocation)
        totals = self:Totals(steps)
        if totals.minutes <= minutes or #allocations <= 1 or attempt == 3 then
            break
        end
        local keep = self:TrimToBudget(plan, allocations, steps, totals.minutes, minutes)
        if #keep == #allocations then
            -- Nichts fiel heraus, obwohl die Zeit nicht reicht: dann ist schon
            -- die erste Gruppe zu lang. Die kuerzt niemand weg.
            break
        end
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
        startLocation = startLocation,
        -- Chancen, die nur deshalb fehlen, weil ihr Ergebnis schon im
        -- Auktionshaus liegt. Sie gehoeren in die Anzeige, nicht ins Schweigen.
        waiting = waiting,
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
    -- Eine zurueckgestellte Chance wird benannt, nicht verschwiegen - erst
    -- recht, wenn sie die einzige war.
    for _, entry in ipairs(waiting) do
        route.warnings[#route.warnings + 1] = self:WaitingText(entry)
    end
    if #allocations == 0 and #candidates == 0 and #waiting > 0 then
        route.blocker = route.blocker
            or "die gefundenen Chancen liegen bereits im Auktionshaus"
    end

    route.confidence = self:Confidence(allocations)
    route.goal = self:EvaluateGoal(options.goal, totals.profit, minutes, totals.minutes)
    route.summary = self:SummaryText(route)
    return route
end

function Route:Confidence(allocations)
    if type(allocations) ~= "table" or #allocations == 0 then return "none" end
    local levels = {}
    for _, allocation in ipairs(allocations) do
        levels[#levels + 1] = type(allocation) == "table"
            and allocation.confidence or "none"
    end
    return GCP.Opportunity:WeakestConfidence(unpack(levels))
end

-- Ein Goldziel ist ein Ziel, keine Zusage. Findet der Planer weniger, steht
-- genau das da - und nicht die Wunschzahl.
function Route:EvaluateGoal(target, expected, budgetMinutes, plannedMinutes)
    expected = tonumber(expected) or 0
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
    if type(route) ~= "table" or type(route.steps) ~= "table"
        or #route.steps == 0 then
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
    if type(current) ~= "table" or type(current.totals) ~= "table" then
        return true, "keine laufende Route"
    end
    if type(candidate) ~= "table" or type(candidate.steps) ~= "table"
        or #candidate.steps == 0 then
        return false, "kein besserer Plan"
    end
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
    if type(step) ~= "table" or step.travel then return true end
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
    if type(route) ~= "table" or type(route.steps) ~= "table" then
        return false, {}
    end
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
    if type(problem) ~= "table" or type(problem.step) ~= "table" then
        return "Die Marktlage hat sich geändert."
    end
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
