local addonName, GCP = ...

GCP.Execution = {}
local Execution = GCP.Execution

local GetItemInfoCompat = (C_Item and C_Item.GetItemInfo) or GetItemInfo

-- ---------------------------------------------------------------------------
-- EXECUTION ENGINE (0.9.0)
--
-- Eine Chance ist keine Handlung.
--
-- "Urmacht herstellen, +193 g theoretisch" ist eine Bewertung. Was der Spieler
-- tatsaechlich tun muss, sind sechs Dinge in einer bestimmten Reihenfolge:
-- zum Auktionshaus gehen, fuenf Materialien kaufen, den Transmutations-Zauber
-- wirken, zurueck zum Auktionshaus, einstellen. Genau diese Zerlegung passiert
-- hier - und nur hier.
--
-- WAS DIESES MODUL NICHT TUT:
--   * Es bewertet nichts. Score, Gewinn und Confidence kommen unveraendert aus
--     der Chance; hier wird nur verteilt, was auf welche Aktion entfaellt.
--   * Es erfindet keine Preise. maxBuyPrice und minSellPrice stammen aus der
--     Rechnung der Chance, mit einer klar benannten Toleranz.
--   * Es sortiert nicht. Die Reihenfolge macht Route.lua; hier entsteht nur
--     der Graph aus Abhaengigkeiten.
--   * Es erfindet keine Orte. Eine Aktion nennt die ART des Ortes
--     (Auktionshaus, Bank, Beruf); wo der liegt, weiss Navigation.lua - oder
--     eben nicht, und dann steht da eine Textanweisung ohne Pfeil.
--
-- ---------------------------------------------------------------------------
-- BESTANDSABGLEICH
--
-- Was schon da ist, wird nicht gekauft. Der Abgleich laeuft ueber einen
-- laufenden virtuellen Bestand: Jede Aktion, die etwas verbraucht, bucht es ab;
-- jede, die etwas erzeugt, bucht es zu. Dadurch koennen zwei Crafts nicht
-- beide dieselben zehn Partikel fuer sich beanspruchen.
--
-- Liegt das Material in der Bank oder in der Post statt im Beutel, entsteht
-- eine BANK_WITHDRAW- oder MAIL-Aktion statt eines Kaufs. Das weiss das Addon
-- nur, wenn Syndicator da ist; ohne Syndicator zaehlen die eigenen Taschen,
-- und der Rest wird gekauft.
-- ---------------------------------------------------------------------------

local C_EXEC = nil
local function config()
    C_EXEC = GCP.Constants.EXECUTION
    return C_EXEC
end

-- Ortsarten. Sie sind die Schnittstelle zu Navigation.lua und zur
-- Wissensbasis; hier stehen bewusst nur die Arten, keine Koordinaten.
Execution.LOCATION = {
    AUCTION_HOUSE = "AUCTION_HOUSE",
    BANK = "BANK",
    MAILBOX = "MAILBOX",
    PROFESSION = "PROFESSION",
    VENDOR = "VENDOR",
    FARM_AREA = "FARM_AREA",
    ANYWHERE = "ANYWHERE",
}

Execution.LOCATION_LABEL = {
    AUCTION_HOUSE = "Auktionshaus",
    BANK = "Bank",
    MAILBOX = "Briefkasten",
    PROFESSION = "Beruf",
    VENDOR = "Händler",
    FARM_AREA = "Farmgebiet",
    ANYWHERE = "überall",
}

-- Wie ein Schritt als erledigt gilt. "MANUAL" heisst ausdruecklich: Der Client
-- sagt es uns nicht, der Spieler muss haken.
Execution.COMPLETION = {
    AT_AUCTION_HOUSE = "AT_AUCTION_HOUSE",
    AT_BANK = "AT_BANK",
    AT_MAILBOX = "AT_MAILBOX",
    AT_PROFESSION = "AT_PROFESSION",
    IN_ZONE = "IN_ZONE",
    ITEM_GAINED = "ITEM_GAINED",
    ITEM_LOST = "ITEM_LOST",
    ITEM_COUNT = "ITEM_COUNT",
    AUCTION_POSTED = "AUCTION_POSTED",
    LEDGER_PURCHASE = "LEDGER_PURCHASE",
    MANUAL = "MANUAL",
}

local function isPositive(value)
    return type(value) == "number" and value > 0
end

local function itemName(itemID)
    if not itemID then return nil end
    local name = GetItemInfoCompat and GetItemInfoCompat(itemID)
    return name or ("Item " .. tostring(itemID))
end

-- ---------------------------------------------------------------------------
-- Zeitschaetzung
--
-- Grundzeit plus Aufschlag je Stueck. Bewusst grob: Der Unterschied zwischen
-- 68 und 74 geplanten Minuten ist Rauschen, der zwischen 20 und 90 nicht.
-- ---------------------------------------------------------------------------

function Execution:MinutesFor(actionType, quantity)
    local rule = config().MINUTES[actionType]
    if not rule then return 0 end
    local units = math.max(tonumber(quantity) or 1, 1)
    return rule.base + rule.perUnit * units
end

-- ---------------------------------------------------------------------------
-- Aktionen
-- ---------------------------------------------------------------------------

local function newPlan()
    return {
        actions = {},
        groups = {},
        warnings = {},
        nextID = 1,
        virtual = {},          -- laufender Bestand: itemID -> Restmenge
        bank = {},             -- was laut Syndicator in Bank/Post liegt
        mail = {},
    }
end

function Execution:AddAction(plan, fields)
    if #plan.actions >= config().MAX_ACTIONS then
        plan.warnings[#plan.warnings + 1] =
            "Der Plan wurde bei " .. config().MAX_ACTIONS .. " Schritten abgeschnitten."
        return nil
    end
    local action = {
        id = "a" .. plan.nextID,
        index = plan.nextID,
        type = fields.type,
        itemID = fields.itemID,
        quantity = fields.quantity,
        location = fields.location,
        maxBuyPrice = fields.maxBuyPrice,
        minSellPrice = fields.minSellPrice,
        capitalRequired = fields.capitalRequired or 0,
        expectedProfit = fields.expectedProfit or 0,
        expectedMinutes = fields.expectedMinutes
            or self:MinutesFor(fields.type, fields.quantity),
        confidence = fields.confidence,
        dependencies = fields.dependencies or {},
        completionCondition = fields.completionCondition or Execution.COMPLETION.MANUAL,
        optional = fields.optional and true or false,
        groupID = fields.groupID,
        title = fields.title,
        detail = fields.detail,
        why = fields.why,
        meta = fields.meta,
    }
    plan.nextID = plan.nextID + 1
    plan.actions[#plan.actions + 1] = action
    return action
end

local function location(kind, key, label)
    return { kind = kind, key = key, label = label or Execution.LOCATION_LABEL[kind] }
end

Execution.Location = location

-- ---------------------------------------------------------------------------
-- Bestandsabgleich
-- ---------------------------------------------------------------------------

function Execution:SeedInventory(plan, inventory)
    plan.virtual = {}
    plan.bank = {}
    plan.mail = {}
    for itemID, entry in pairs(inventory or {}) do
        if type(entry) == "table" and isPositive(entry.count) then
            local bags = entry.sources and entry.sources["Taschen"] or nil
            local bank = entry.sources and entry.sources["Bank"] or nil
            local mail = entry.sources and entry.sources["Post"] or nil
            -- Ohne Quellenangabe (kein Syndicator) zaehlt alles als greifbar.
            if bags == nil and bank == nil and mail == nil then
                plan.virtual[itemID] = entry.count
            else
                plan.virtual[itemID] = bags or 0
                plan.bank[itemID] = bank or 0
                plan.mail[itemID] = mail or 0
            end
        end
    end
end

-- Nimmt so viel wie moeglich aus dem virtuellen Bestand. Rueckgabe: entnommene
-- Menge aus den Taschen, aus der Bank, aus der Post und der offene Rest.
function Execution:TakeFromStock(plan, itemID, needed)
    local fromBags = math.min(plan.virtual[itemID] or 0, needed)
    plan.virtual[itemID] = (plan.virtual[itemID] or 0) - fromBags
    local rest = needed - fromBags
    local fromBank = math.min(plan.bank[itemID] or 0, rest)
    plan.bank[itemID] = (plan.bank[itemID] or 0) - fromBank
    rest = rest - fromBank
    local fromMail = math.min(plan.mail[itemID] or 0, rest)
    plan.mail[itemID] = (plan.mail[itemID] or 0) - fromMail
    rest = rest - fromMail
    return fromBags, fromBank, fromMail, rest
end

-- ---------------------------------------------------------------------------
-- Zerlegung einer Allokation
--
-- Der Ablauf ist fuer alle Chancenarten derselbe:
--   1. Eingaben beschaffen (Bestand -> Bank -> Post -> Kauf)
--   2. Umwandlung ausfuehren (herstellen, kombinieren, entzaubern)
--   3. Ergebnis einstellen
-- Was eine Chance nicht braucht, entfaellt: Resale hat keinen Schritt 2, und
-- Entzaubern hat keinen belegbaren Schritt 3.
-- ---------------------------------------------------------------------------

local AH = Execution.LOCATION.AUCTION_HOUSE

function Execution:BuildAcquisition(plan, group, input, runs)
    local E = config()
    local needed = math.ceil((input.count or 1) * runs)
    if needed <= 0 then return {} end
    local produced = {}
    local fromBags, fromBank, fromMail, missing = self:TakeFromStock(plan, input.itemID, needed)

    if fromBank > 0 then
        local action = self:AddAction(plan, {
            type = "BANK_WITHDRAW", itemID = input.itemID, quantity = fromBank,
            location = location(Execution.LOCATION.BANK),
            groupID = group.id,
            completionCondition = Execution.COMPLETION.ITEM_COUNT,
            title = string.format("%d× %s aus der Bank holen", fromBank,
                itemName(input.itemID)),
            meta = { gain = fromBank },
        })
        if action then produced[#produced + 1] = action.id end
    end
    if fromMail > 0 then
        local action = self:AddAction(plan, {
            type = "MAIL", itemID = input.itemID, quantity = fromMail,
            location = location(Execution.LOCATION.MAILBOX),
            groupID = group.id,
            completionCondition = Execution.COMPLETION.ITEM_COUNT,
            title = string.format("%d× %s aus dem Briefkasten holen", fromMail,
                itemName(input.itemID)),
            meta = { gain = fromMail },
        })
        if action then produced[#produced + 1] = action.id end
    end
    if missing > 0 then
        local unitPrice = input.unitPrice
        local maxBuy = isPositive(unitPrice)
            and math.floor(unitPrice * (1 + E.BUY_TOLERANCE) + 0.5) or nil
        local action = self:AddAction(plan, {
            type = "BUY", itemID = input.itemID, quantity = missing,
            location = location(AH),
            maxBuyPrice = maxBuy,
            capitalRequired = isPositive(unitPrice)
                and math.floor(unitPrice * missing + 0.5) or 0,
            groupID = group.id,
            confidence = group.confidence,
            completionCondition = Execution.COMPLETION.LEDGER_PURCHASE,
            title = string.format("%d× %s kaufen", missing, itemName(input.itemID)),
            detail = maxBuy and ("Maximal " .. GCP.Prices:FormatMoney(maxBuy) .. " / Stück")
                or "Preisgrenze unbekannt – im Zweifel nicht kaufen.",
            meta = { gain = missing },
        })
        if action then produced[#produced + 1] = action.id end
    end
    return produced
end

function Execution:BuildGroup(plan, allocation)
    local opportunity = allocation.opportunity or {}
    local blueprint = opportunity.execution
    if type(blueprint) ~= "table" then
        plan.warnings[#plan.warnings + 1] = string.format(
            "%s hat keinen Bauplan und bleibt außerhalb der Route.",
            tostring(allocation.title or allocation.key))
        return nil
    end
    local runs = math.max(math.floor(allocation.units or 1), 1)
    local group = {
        id = "g" .. (#plan.groups + 1),
        key = allocation.key,
        type = allocation.type,
        title = allocation.title,
        itemID = allocation.itemID,
        runs = runs,
        capital = allocation.capital,
        expectedProfit = allocation.expectedProfit,
        confidence = allocation.confidence,
        -- Die Chance bleibt an der Gruppe haengen: Der Guide beantwortet
        -- "Warum?" aus ihr, und die Positions-Provenance kommt von hier.
        opportunity = opportunity,
        phase = opportunity.phase,
        catalystIDs = opportunity.catalystIDs,
        actions = {},
    }
    plan.groups[#plan.groups + 1] = group

    -- 1) Eingaben
    local inputDeps = {}
    for _, input in ipairs(blueprint.inputs or {}) do
        for _, id in ipairs(self:BuildAcquisition(plan, group, input, runs)) do
            inputDeps[#inputDeps + 1] = id
        end
    end

    -- 2) Umwandlung
    local produceDeps = inputDeps
    local method = blueprint.method
    if method == "farm" then
        -- Ein Farmblock hat keine Eingaben, die man kaufen koennte: Er kostet
        -- Zeit statt Kapital. Die Minutenzahl stammt aus der GEMESSENEN
        -- eigenen Rate (Farm.lua) - ohne eine solche Rate entsteht dieser
        -- Block gar nicht erst.
        local outputItem = blueprint.outputs and blueprint.outputs[1]
        local quantity = outputItem and outputItem.count or 1
        local action = self:AddAction(plan, {
            type = "FARM",
            itemID = outputItem and outputItem.itemID or allocation.itemID,
            quantity = quantity,
            location = location(Execution.LOCATION.FARM_AREA, blueprint.zone,
                blueprint.zone),
            expectedMinutes = blueprint.farmMinutes or 20,
            groupID = group.id,
            confidence = allocation.confidence,
            dependencies = produceDeps,
            completionCondition = Execution.COMPLETION.ITEM_COUNT,
            title = string.format("%d× %s sammeln", quantity,
                itemName(outputItem and outputItem.itemID)),
            detail = blueprint.zone and ("Gebiet: " .. blueprint.zone) or nil,
            meta = { gain = quantity, zone = blueprint.zone },
        })
        if action then
            produceDeps = { action.id }
            if outputItem then
                self:AddStock(plan, outputItem.itemID, quantity)
            end
        end
    elseif method == "craft" or method == "convert" or method == "disenchant" then
        local actionType = method == "craft" and "CRAFT"
            or (method == "convert" and "CONVERT" or "DISENCHANT")
        local where = blueprint.profession
            and location(Execution.LOCATION.PROFESSION, blueprint.profession,
                blueprint.profession)
            or location(Execution.LOCATION.ANYWHERE)
        local outputItem = blueprint.outputs and blueprint.outputs[1]
        local title
        if actionType == "CRAFT" then
            title = string.format("%d× %s herstellen", runs,
                itemName(outputItem and outputItem.itemID or allocation.itemID))
        elseif actionType == "CONVERT" then
            title = string.format("%d× %s umwandeln", runs,
                itemName(blueprint.inputs and blueprint.inputs[1]
                    and blueprint.inputs[1].itemID))
        else
            title = string.format("%d× %s entzaubern", runs,
                itemName(blueprint.inputs and blueprint.inputs[1]
                    and blueprint.inputs[1].itemID))
        end
        local action = self:AddAction(plan, {
            type = actionType,
            itemID = outputItem and outputItem.itemID or allocation.itemID,
            quantity = runs,
            location = where,
            groupID = group.id,
            confidence = allocation.confidence,
            dependencies = produceDeps,
            completionCondition = outputItem and Execution.COMPLETION.ITEM_COUNT
                or Execution.COMPLETION.MANUAL,
            title = title,
            detail = blueprint.irreversible
                and "Der Weg zurück existiert nicht." or nil,
            meta = outputItem and { gain = outputItem.count * runs } or nil,
        })
        if action then
            produceDeps = { action.id }
            if outputItem then
                self:AddStock(plan, outputItem.itemID, outputItem.count * runs)
            end
        end
    end

    -- 3) Einstellen
    local sellItemID = blueprint.sellItemID
    if blueprint.unknownOutput then
        local action = self:AddAction(plan, {
            type = "POST_AUCTION", quantity = 1,
            location = location(AH),
            groupID = group.id,
            dependencies = produceDeps,
            optional = true,
            completionCondition = Execution.COMPLETION.MANUAL,
            title = "Gewonnene Materialien einstellen",
            detail = "Was beim Entzaubern herauskommt, steht vorher nicht fest – "
                .. "Gold Copilot kann hier keinen Mindestpreis nennen.",
        })
    elseif sellItemID then
        local E = config()
        local perRun = blueprint.sellCount or 1
        local quantity = math.floor(perRun * runs + 0.5)
        local unit = blueprint.sellUnitPrice
        local minSell = isPositive(unit)
            and math.floor(unit * (1 - E.SELL_TOLERANCE) + 0.5) or nil
        local action = self:AddAction(plan, {
            type = "POST_AUCTION", itemID = sellItemID, quantity = quantity,
            location = location(AH),
            minSellPrice = minSell,
            expectedProfit = allocation.expectedProfit,
            groupID = group.id,
            confidence = allocation.confidence,
            dependencies = produceDeps,
            completionCondition = Execution.COMPLETION.AUCTION_POSTED,
            title = string.format("%d× %s einstellen", quantity, itemName(sellItemID)),
            detail = minSell
                and ("Mindestens " .. GCP.Prices:FormatMoney(minSell) .. " / Stück")
                or "Kein belastbarer Mindestpreis – erst prüfen, dann einstellen.",
        })
    end

    for _, action in ipairs(plan.actions) do
        if action.groupID == group.id then
            group.actions[#group.actions + 1] = action.id
        end
    end
    return group
end

function Execution:StockOf(plan, itemID)
    return (plan.virtual[itemID] or 0)
end

function Execution:AddStock(plan, itemID, count)
    plan.virtual[itemID] = (plan.virtual[itemID] or 0) + count
end

-- ---------------------------------------------------------------------------
-- Plan
-- ---------------------------------------------------------------------------

function Execution:BuildPlan(allocations, options)
    options = options or {}
    local plan = newPlan()
    local inventory = options.inventory
    if inventory == nil then inventory = GCP.Inventory:ScanAccount() end
    self:SeedInventory(plan, inventory)

    for _, allocation in ipairs(allocations or {}) do
        self:BuildGroup(plan, allocation)
    end

    -- Ein Plan ohne die vorbereitenden Wege waere eine Liste, kein Guide. Die
    -- GO_TO-Schritte setzt Route.lua ein, sobald die Reihenfolge steht - hier
    -- waere jeder Weg geraten.
    local totals = { capital = 0, profit = 0, minutes = 0, actions = #plan.actions }
    for _, action in ipairs(plan.actions) do
        totals.capital = totals.capital + (action.capitalRequired or 0)
        totals.profit = totals.profit + (action.expectedProfit or 0)
        totals.minutes = totals.minutes + (action.expectedMinutes or 0)
    end
    plan.totals = totals
    plan.byID = {}
    for _, action in ipairs(plan.actions) do plan.byID[action.id] = action end

    local ok, errors = self:Validate(plan)
    plan.valid = ok
    plan.errors = errors
    return plan
end

-- ---------------------------------------------------------------------------
-- Graphpruefung
--
-- Drei Invarianten, und jede davon hat schon einmal eine Route zerstoert:
--   1. Jede Abhaengigkeit muss es geben.
--   2. Keine Aktion darf von sich selbst abhaengen (auch nicht ueber Umwege).
--   3. Keine Aktion darf zweimal im Plan stehen.
-- ---------------------------------------------------------------------------

function Execution:Validate(plan)
    local errors = {}
    local seen = {}
    for _, action in ipairs(plan.actions) do
        if seen[action.id] then
            errors[#errors + 1] = "Doppelte Aktions-ID: " .. action.id
        end
        seen[action.id] = true
        if not action.type or not config().MINUTES[action.type] then
            errors[#errors + 1] = "Unbekannte Aktionsart: " .. tostring(action.type)
        end
        if #action.dependencies > config().MAX_DEPENDENCIES then
            errors[#errors + 1] = action.id .. " hat zu viele Abhängigkeiten."
        end
    end
    for _, action in ipairs(plan.actions) do
        for _, dependency in ipairs(action.dependencies) do
            if not seen[dependency] then
                errors[#errors + 1] = string.format(
                    "%s hängt an %s, das es nicht gibt.", action.id, dependency)
            end
        end
    end

    -- Zyklensuche ueber eine Tiefensuche mit drei Farben.
    local state = {}
    local byID = plan.byID or {}
    if not plan.byID then
        for _, action in ipairs(plan.actions) do byID[action.id] = action end
    end
    local function visit(id, stack)
        if state[id] == 2 then return false end
        if state[id] == 1 then
            errors[#errors + 1] = "Abhängigkeitszyklus: " .. table.concat(stack, " -> ")
            return true
        end
        state[id] = 1
        stack[#stack + 1] = id
        local action = byID[id]
        for _, dependency in ipairs(action and action.dependencies or {}) do
            if byID[dependency] and visit(dependency, stack) then
                state[id] = 2
                return true
            end
        end
        stack[#stack] = nil
        state[id] = 2
        return false
    end
    for _, action in ipairs(plan.actions) do
        if state[action.id] == nil then visit(action.id, {}) end
    end

    return #errors == 0, errors
end

-- Topologische Reihenfolge. Kahn mit stabiler Auswahl: Bei gleichem Rang
-- gewinnt die kleinere Aktionsnummer, damit derselbe Plan immer dieselbe
-- Reihenfolge ergibt.
function Execution:TopologicalOrder(plan, pick)
    local indegree, dependents = {}, {}
    local byID = plan.byID or {}
    for _, action in ipairs(plan.actions) do
        indegree[action.id] = 0
        byID[action.id] = action
    end
    for _, action in ipairs(plan.actions) do
        for _, dependency in ipairs(action.dependencies) do
            if indegree[dependency] ~= nil then
                indegree[action.id] = indegree[action.id] + 1
                dependents[dependency] = dependents[dependency] or {}
                local list = dependents[dependency]
                list[#list + 1] = action.id
            end
        end
    end

    local ready = {}
    for _, action in ipairs(plan.actions) do
        if indegree[action.id] == 0 then ready[#ready + 1] = action end
    end

    local order = {}
    while #ready > 0 do
        local chosen, chosenIndex = nil, nil
        if pick then
            chosen, chosenIndex = pick(ready, order)
        end
        if not chosen then
            chosenIndex = 1
            for index = 2, #ready do
                if ready[index].index < ready[chosenIndex].index then
                    chosenIndex = index
                end
            end
            chosen = ready[chosenIndex]
        end
        table.remove(ready, chosenIndex)
        order[#order + 1] = chosen
        for _, dependentID in ipairs(dependents[chosen.id] or {}) do
            indegree[dependentID] = indegree[dependentID] - 1
            if indegree[dependentID] == 0 then
                ready[#ready + 1] = byID[dependentID]
            end
        end
    end

    -- Bleibt etwas uebrig, gibt es einen Zyklus. Validate haette ihn gemeldet;
    -- hier wird er nicht stillschweigend verschluckt.
    if #order < #plan.actions then
        return order, false
    end
    return order, true
end

-- ---------------------------------------------------------------------------
-- Darstellung
-- ---------------------------------------------------------------------------

function Execution:TypeLabel(actionType)
    return config().TYPE_LABEL[actionType] or actionType
end

function Execution:Describe(action)
    if not action then return "", "" end
    local title = action.title or self:TypeLabel(action.type)
    return title, action.detail
end

-- Die vollstaendige Begruendung eines Schritts. Sie kommt aus der Chance und
-- wird hier nur um das ergaenzt, was an der Aktion selbst haengt.
function Execution:Explain(action, group)
    local lines = {}
    if action.maxBuyPrice then
        lines[#lines + 1] = "Maximaler Einstieg: "
            .. GCP.Prices:FormatMoney(action.maxBuyPrice) .. " / Stück"
    end
    if action.minSellPrice then
        lines[#lines + 1] = "Mindestpreis: "
            .. GCP.Prices:FormatMoney(action.minSellPrice) .. " / Stück"
    end
    if isPositive(action.capitalRequired) then
        lines[#lines + 1] = "Kapital: " .. GCP.Prices:FormatMoney(action.capitalRequired)
    end
    if group and isPositive(group.expectedProfit) then
        lines[#lines + 1] = "Theoretisches Potenzial der Chance: "
            .. GCP.Prices:FormatMoney(group.expectedProfit)
    end
    if action.completionCondition == Execution.COMPLETION.MANUAL then
        lines[#lines + 1] = "Dieser Schritt lässt sich nicht zuverlässig automatisch "
            .. "erkennen – bitte selbst abhaken."
    end
    return lines
end
