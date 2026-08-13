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
    AT_VENDOR = "AT_VENDOR",
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

-- ---------------------------------------------------------------------------
-- ITEMNAMEN UND DER KALTE CACHE (1.1.0-beta.5)
--
-- GetItemInfo antwortet nur fuer Items, die der Client schon kennt. Ein
-- Rezeptprodukt, das der Spieler nie in der Hand hatte, ist ihm unbekannt -
-- die Abfrage stoesst dann eine Serveranfrage an und liefert erst beim
-- naechsten Mal einen Namen.
--
-- Bis beta.4 wanderte in genau diesem Moment "Item 10042" als Titel in den
-- Plan UND in die SavedVariables des Guides. Der Name kam Sekunden spaeter an,
-- der Titel blieb fuer immer die Nummer.
--
-- Deshalb zwei Dinge: Die Anfrage wird ausdruecklich gestellt (statt sie als
-- Nebenwirkung mitzunehmen), und der Ersatztext ist ein PLATZHALTER, den die
-- Anzeige spaeter ersetzt - siehe Execution:DisplayTitle.
-- ---------------------------------------------------------------------------

function Execution:RequestItemData(itemID)
    if type(itemID) ~= "number" then return false end
    if C_Item and type(C_Item.RequestLoadItemDataByID) == "function" then
        local ok = pcall(C_Item.RequestLoadItemDataByID, itemID)
        if ok then return true end
    end
    -- Auch der blosse Aufruf stoesst die Anfrage an; er ist der Rueckfall fuer
    -- Clientfassungen ohne die C_Item-API.
    if GetItemInfoCompat then pcall(GetItemInfoCompat, itemID) end
    return false
end

local function itemName(itemID)
    if not itemID then return nil end
    local name = GetItemInfoCompat and GetItemInfoCompat(itemID)
    if name then return name end
    Execution:RequestItemData(itemID)
    return "Item " .. tostring(itemID)
end

-- Der Titel, wie er JETZT lautet. Steckt noch der Platzhalter darin und kennt
-- der Client das Item inzwischen, steht hier der richtige Name - ohne dass der
-- gespeicherte Schritt angefasst werden muesste.
function Execution:DisplayTitle(step)
    if type(step) ~= "table" then return "" end
    local title = step.title
    if type(title) ~= "string" or type(step.itemID) ~= "number" then
        return title or self:TypeLabel(step.type)
    end
    local placeholder = "Item " .. tostring(step.itemID)
    if not title:find(placeholder, 1, true) then return title end
    local name = GetItemInfoCompat and GetItemInfoCompat(step.itemID)
    if not name then
        self:RequestItemData(step.itemID)
        return title
    end
    return (title:gsub(placeholder, name))
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
            local sources = entry.sources
            local bags = sources and sources["Taschen"] or nil
            local bank = sources and sources["Bank"] or nil
            local mail = sources and sources["Post"] or nil
            -- Ohne Quellenangabe (kein Syndicator) zaehlt alles als greifbar:
            -- Dann kommt der Bestand aus den eigenen Taschen.
            --
            -- MIT Quellenangabe zaehlen nur Taschen, Bank und Post. Was bereits
            -- im Auktionshaus liegt, ist Besitz, aber kein Material - wer es
            -- verplant, muesste erst die Auktion abbrechen und die
            -- Einstellgebuehr abschreiben.
            --
            -- Bis 1.0.0-beta.9 griff die Ausnahme "keine Quellenangabe" auch
            -- dann, wenn Syndicator NUR Auktionen meldete: Dann galt der volle
            -- Bestand als greifbar, und der Plan rechnete mit Material, das im
            -- Haus lag. Deshalb entscheidet jetzt, ob es ueberhaupt eine
            -- Quellenangabe gibt - nicht, ob zufaellig eine der drei fehlt.
            if sources == nil or next(sources) == nil then
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

function Execution:BuildAcquisition(plan, group, input, runs, depth)
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
        -- Erst fragen, ob Selbermachen billiger ist. Nur wenn nicht, wird
        -- gekauft - das ist die Regel, und sie steht bei BuildSubCraft.
        local action = self:BuildSubCraft(plan, group, input, missing, depth)
            or self:BuildPurchase(plan, group, input, missing)
        if action then produced[#produced + 1] = action.id end
    end
    return produced
end

-- ---------------------------------------------------------------------------
-- EINKAUF: AUKTIONSHAUS ODER HAENDLER? (1.1.0-beta.5)
--
-- Bis beta.4 gab es diese Frage nicht - jeder fehlende Rohstoff wurde im
-- Auktionshaus gekauft. Fuer Runenfaden, Farbstoffe, Phiolen und Flussmittel
-- war das schlicht falsch: Die stehen beim Handelswarenhaendler zu einem
-- festen Preis, und im Auktionshaus stehen sie nur, weil jemand genau diesen
-- Weg verkauft.
--
-- Der Haendler gewinnt, wenn er guenstiger ist ODER wenn es im Auktionshaus
-- keinen belegten Preis gibt. Er gewinnt NICHT, wenn das Haus billiger ist -
-- auch Haendlerware wird gelegentlich unter Wert verramscht.
-- ---------------------------------------------------------------------------
-- ---------------------------------------------------------------------------
-- SELBST HERSTELLEN STATT KAUFEN (1.1.0-beta.5)
--
-- Braucht ein Rezept zwoelf Netherstoffballen und kostet der Ballen im Haus
-- 1 g, waehrend fuenf eigene Netherstoff 60 Silber kosten, dann kauft man
-- nicht den Ballen. Man macht ihn.
--
-- Der Unter-Craft entsteht nur, wenn ALLES davon zutrifft:
--   * Es gibt ein Rezept, das der Spieler KANN.
--   * Selbst herstellen ist echt guenstiger - nicht gleich teuer. Ein
--     zusaetzlicher Arbeitsschritt fuer null Ersparnis ist keine Ersparnis.
--   * Die Zutaten des Unter-Crafts lassen sich ihrerseits beschaffen. Das
--     prueft die Rekursion in Crafts:CraftCost bereits mit; hier wird sie nur
--     noch einmal aufgerufen, um an Rezept und Beruf zu kommen.
--
-- Der Bestand zaehlt dabei ganz normal mit: BuildAcquisition laeuft fuer die
-- Zutaten des Unter-Crafts genauso wie fuer alles andere, greift also erst in
-- Taschen, Bank und Post und kauft nur den Rest.
-- ---------------------------------------------------------------------------
function Execution:BuildSubCraft(plan, group, input, quantity, depth)
    if depth and depth > 1 then return nil end        -- eine Ebene in der Route
    local itemID = input.itemID
    local unitPrice = input.unitPrice
    local buyPrice = unitPrice
    local vendorPrice = GCP.Prices:GetVendorBuyPrice(itemID)
    if vendorPrice and (not buyPrice or vendorPrice < buyPrice) then
        buyPrice = vendorPrice
    end
    local craftPrice, professionName, recipe = GCP.Crafts:CraftCost(itemID)
    if not craftPrice or not recipe then return nil end
    if buyPrice and craftPrice >= buyPrice then return nil end

    local numMade = math.max(recipe.numMade or 1, 1)
    local runs = math.ceil(quantity / numMade)
    if runs <= 0 then return nil end

    -- Die Zutaten des Unter-Crafts: derselbe Weg wie ueberall - Bestand zuerst,
    -- dann Haendler oder Haus.
    local inputDeps = {}
    for _, mat in ipairs(recipe.mats or {}) do
        if type(mat[1]) == "number" and type(mat[2]) == "number" then
            local subInput = {
                itemID = mat[1],
                count = mat[2],
                unitPrice = GCP.Prices:GetAcquisitionPrice(mat[1]),
            }
            for _, id in ipairs(self:BuildAcquisition(plan, group, subInput, runs,
                (depth or 0) + 1)) do
                inputDeps[#inputDeps + 1] = id
            end
        end
    end

    local produced = numMade * runs
    local action = self:AddAction(plan, {
        type = "CRAFT", itemID = itemID, quantity = runs,
        location = professionName
            and location(Execution.LOCATION.PROFESSION, professionName, professionName)
            or location(Execution.LOCATION.ANYWHERE),
        groupID = group.id,
        confidence = group.confidence,
        dependencies = inputDeps,
        completionCondition = Execution.COMPLETION.ITEM_COUNT,
        title = string.format("%d× %s selbst herstellen", produced, itemName(itemID)),
        detail = string.format("Selbst gemacht %s statt %s im Einkauf – "
            .. "das spart %s.", GCP.Prices:FormatMoney(craftPrice),
            GCP.Prices:FormatMoney(buyPrice or 0),
            GCP.Prices:FormatMoney((buyPrice or 0) - craftPrice)),
        meta = { gain = produced, subCraft = true },
    })
    if not action then return nil end
    -- Was zu viel entsteht, bleibt liegen und ist beim naechsten Bedarf da.
    if produced > quantity then
        self:AddStock(plan, itemID, produced - quantity)
    end
    return action
end

function Execution:BuildPurchase(plan, group, input, quantity)
    local E = config()
    local unitPrice = input.unitPrice
    local vendorPrice, vendorSource = GCP.Prices:GetVendorBuyPrice(input.itemID)

    if vendorPrice and (not isPositive(unitPrice) or vendorPrice <= unitPrice) then
        return self:AddAction(plan, {
            type = "VENDOR_BUY", itemID = input.itemID, quantity = quantity,
            location = location(Execution.LOCATION.VENDOR),
            -- Ein Haendlerpreis braucht keine Toleranz: Er steht fest.
            maxBuyPrice = vendorPrice,
            capitalRequired = math.floor(vendorPrice * quantity + 0.5),
            groupID = group.id,
            confidence = group.confidence,
            -- Der Client meldet keinen Haendlerkauf im Ledger; erkannt wird er
            -- am Bestandszuwachs, weil Haendlerware sofort in den Taschen liegt.
            completionCondition = Execution.COMPLETION.ITEM_COUNT,
            title = string.format("%d× %s beim Händler kaufen", quantity,
                itemName(input.itemID)),
            detail = string.format("%s / Stück – fester Preis%s.",
                GCP.Prices:FormatMoney(vendorPrice),
                vendorSource == "gesehen" and ", selbst gesehen" or ""),
            meta = { gain = quantity, vendor = true },
        })
    end

    local maxBuy = isPositive(unitPrice)
        and math.floor(unitPrice * (1 + E.BUY_TOLERANCE) + 0.5) or nil
    return self:AddAction(plan, {
        type = "BUY", itemID = input.itemID, quantity = quantity,
        location = location(AH),
        maxBuyPrice = maxBuy,
        capitalRequired = isPositive(unitPrice)
            and math.floor(unitPrice * quantity + 0.5) or 0,
        groupID = group.id,
        confidence = group.confidence,
        completionCondition = Execution.COMPLETION.LEDGER_PURCHASE,
        title = string.format("%d× %s kaufen", quantity, itemName(input.itemID)),
        detail = maxBuy and ("Maximal " .. GCP.Prices:FormatMoney(maxBuy) .. " / Stück")
            or "Preisgrenze unbekannt – im Zweifel nicht kaufen.",
        meta = { gain = quantity },
    })
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

-- ---------------------------------------------------------------------------
-- GLEICHE KAEUFE SIND EIN KAUF (1.1.0-beta.5)
--
-- Fuenf Chancen, die alle Runenfaden brauchen, ergaben bis beta.4 fuenf
-- Zeilen "1x Runenfaden kaufen". Im Auktionshaus ist das derselbe Handgriff,
-- und in der Route sind es fuenf Schritte, die einzeln abgehakt werden wollen.
--
-- Zusammengefasst wird nur, was WIRKLICH dasselbe ist: dieselbe Aktionsart,
-- dasselbe Item, damit auch derselbe Ort. Ein Kauf im Auktionshaus und einer
-- beim Haendler bleiben zwei Schritte, weil sie zwei Wege sind.
--
-- Die Gruppen der zusammengefassten Aktionen wandern mit (groupIDs): Der Guide
-- meldet die Ausfuehrung an das Chancen-Protokoll, und ein Kauf, der drei
-- Chancen bedient, darf nicht nur eine davon belegen.
-- ---------------------------------------------------------------------------

local MERGEABLE = {
    BUY = true, VENDOR_BUY = true, BANK_WITHDRAW = true, MAIL = true,
}

function Execution:MergeIdenticalActions(plan)
    if type(plan) ~= "table" or type(plan.actions) ~= "table" then return 0 end
    local survivors, replacement, kept = {}, {}, {}
    local merged = 0

    for _, action in ipairs(plan.actions) do
        local key = nil
        if MERGEABLE[action.type] and action.itemID then
            key = action.type .. "|" .. tostring(action.itemID)
        end
        local first = key and survivors[key] or nil
        if first then
            first.quantity = (first.quantity or 0) + (action.quantity or 0)
            first.capitalRequired = (first.capitalRequired or 0)
                + (action.capitalRequired or 0)
            first.expectedProfit = (first.expectedProfit or 0)
                + (action.expectedProfit or 0)
            -- Die STRENGERE Preisgrenze gilt. Wer fuer die eine Chance nur bis
            -- 3 g kaufen darf, darf es auch dann nicht teurer, wenn eine
            -- zweite Chance mit 4 g rechnet.
            if isPositive(action.maxBuyPrice) and (not isPositive(first.maxBuyPrice)
                or action.maxBuyPrice < first.maxBuyPrice) then
                first.maxBuyPrice = action.maxBuyPrice
            end
            if type(first.meta) == "table" and type(action.meta) == "table" then
                first.meta.gain = (first.meta.gain or 0) + (action.meta.gain or 0)
            end
            first.confidence = GCP.Opportunity:WeakestConfidence(
                first.confidence, action.confidence)
            if action.groupID then
                first.groupIDs = first.groupIDs or { first.groupID }
                first.groupIDs[#first.groupIDs + 1] = action.groupID
            end
            replacement[action.id] = first.id
            merged = merged + 1
        else
            if key then survivors[key] = action end
            kept[#kept + 1] = action
        end
    end
    if merged == 0 then return 0 end

    -- Titel und Bedienzeit stimmen nach dem Addieren nicht mehr.
    for _, action in ipairs(kept) do
        if action.groupIDs then
            action.quantity = math.max(math.floor(action.quantity or 1), 1)
            action.expectedMinutes = self:MinutesFor(action.type, action.quantity)
            if action.type == "VENDOR_BUY" then
                action.title = string.format("%d× %s beim Händler kaufen",
                    action.quantity, itemName(action.itemID))
            elseif action.type == "BUY" then
                action.title = string.format("%d× %s kaufen",
                    action.quantity, itemName(action.itemID))
            elseif action.type == "BANK_WITHDRAW" then
                action.title = string.format("%d× %s aus der Bank holen",
                    action.quantity, itemName(action.itemID))
            elseif action.type == "MAIL" then
                action.title = string.format("%d× %s aus dem Briefkasten holen",
                    action.quantity, itemName(action.itemID))
            end
        end
    end

    -- Verweise auf entfernte Aktionen umbiegen, ohne Dubletten zu erzeugen.
    for _, action in ipairs(kept) do
        local rewritten, seen, changed = {}, {}, false
        for _, dependency in ipairs(action.dependencies or {}) do
            local target = replacement[dependency] or dependency
            if target ~= dependency then changed = true end
            if not seen[target] and target ~= action.id then
                seen[target] = true
                rewritten[#rewritten + 1] = target
            elseif seen[target] then
                changed = true
            end
        end
        if changed then action.dependencies = rewritten end
    end

    plan.actions = kept
    self:RebuildGroupActions(plan)
    return merged
end

function Execution:RebuildGroupActions(plan)
    local byGroup = {}
    for _, action in ipairs(plan.actions) do
        for _, groupID in ipairs(action.groupIDs or { action.groupID }) do
            if groupID then
                byGroup[groupID] = byGroup[groupID] or {}
                local list = byGroup[groupID]
                list[#list + 1] = action.id
            end
        end
    end
    for _, group in ipairs(plan.groups or {}) do
        group.actions = byGroup[group.id] or {}
    end
end

-- ---------------------------------------------------------------------------
-- ERSTEIGERTES KOMMT PER POST (1.1.0-beta.5)
--
-- In TBC landet ein Sofortkauf nicht in den Taschen, sondern im Briefkasten.
-- Bis beta.4 wusste der Plan das nicht: Er schickte den Spieler vom
-- Auktionshaus direkt zur Werkbank, wo dann das Material fehlte. Erst die
-- naechste Neuplanung sah die Post - und baute einen zweiten Weg zum
-- Briefkasten ein. Genau daher das Hin und Her zwischen Haus und Post.
--
-- Ein Gang, nicht einer je Kauf: Der Briefkasten gibt alles auf einmal heraus.
-- ---------------------------------------------------------------------------
function Execution:InsertMailCollection(plan)
    if not config().AUCTION_DELIVERY_BY_MAIL then return nil end
    if type(plan) ~= "table" or type(plan.actions) ~= "table" then return nil end

    local purchases, isPurchase = {}, {}
    for _, action in ipairs(plan.actions) do
        if action.type == "BUY" then
            purchases[#purchases + 1] = action.id
            isPurchase[action.id] = true
        end
    end
    if #purchases == 0 then return nil end

    -- Haengt ueberhaupt etwas an einem dieser Kaeufe? Ein reiner Einkauf ohne
    -- Weiterverarbeitung braucht keinen erzwungenen Postgang - wer nur kauft
    -- und liegen laesst, holt die Post ab, wann er will.
    local hasConsumer = false
    for _, action in ipairs(plan.actions) do
        for _, dependency in ipairs(action.dependencies or {}) do
            if isPurchase[dependency] then hasConsumer = true break end
        end
        if hasConsumer then break end
    end
    if not hasConsumer then return nil end

    local collect = self:AddAction(plan, {
        type = "MAIL_COLLECT",
        quantity = #purchases,
        location = location(Execution.LOCATION.MAILBOX),
        dependencies = purchases,
        completionCondition = Execution.COMPLETION.AT_MAILBOX,
        title = "Ersteigertes aus dem Briefkasten holen",
        detail = "Was im Auktionshaus gekauft wird, kommt per Post. Ohne diesen "
            .. "Gang steht das Material nicht in den Taschen.",
    })
    if not collect then return nil end

    for _, action in ipairs(plan.actions) do
        if action.id ~= collect.id then
            local rewritten, seen, changed = {}, {}, false
            for _, dependency in ipairs(action.dependencies or {}) do
                local target = isPurchase[dependency] and collect.id or dependency
                if target ~= dependency then changed = true end
                if not seen[target] then
                    seen[target] = true
                    rewritten[#rewritten + 1] = target
                else
                    changed = true
                end
            end
            if changed then action.dependencies = rewritten end
        end
    end
    return collect
end

function Execution:StockOf(plan, itemID)
    if type(plan) ~= "table" or type(plan.virtual) ~= "table" then return 0 end
    return (plan.virtual[itemID] or 0)
end

function Execution:AddStock(plan, itemID, count)
    if type(plan) ~= "table" or type(plan.virtual) ~= "table" then return end
    plan.virtual[itemID] = (plan.virtual[itemID] or 0) + count
end

-- ---------------------------------------------------------------------------
-- Plan
-- ---------------------------------------------------------------------------

function Execution:BuildPlan(allocations, options)
    if type(allocations) ~= "table" then allocations = {} end
    if type(options) ~= "table" then options = {} end
    local plan = newPlan()
    local inventory = options.inventory
    if inventory == nil then inventory = GCP.Inventory:ScanAccount() end
    self:SeedInventory(plan, inventory)

    for _, allocation in ipairs(allocations or {}) do
        self:BuildGroup(plan, allocation)
    end

    -- Erst zusammenfassen, dann den Postgang setzen: Nach dem Zusammenfassen
    -- gibt es weniger Kaeufe, an denen er haengen muss.
    self:MergeIdenticalActions(plan)
    self:InsertMailCollection(plan)

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
    if type(plan) ~= "table" or type(plan.actions) ~= "table" then
        return false, { "Kein Plan." }
    end
    local seen = {}
    for _, action in ipairs(plan.actions) do
        if seen[action.id] then
            errors[#errors + 1] = "Doppelte Aktions-ID: " .. action.id
        end
        seen[action.id] = true
        if not action.type or not config().MINUTES[action.type] then
            errors[#errors + 1] = "Unbekannte Aktionsart: " .. tostring(action.type)
        end
        -- Der Postgang ist die eine Ausnahme: Er haengt an JEDEM Kauf der
        -- Route, weil er sie alle auf einmal abholt. Eine Obergrenze waere
        -- hier keine Sicherung, sondern eine kuenstliche Grenze fuer die Zahl
        -- der Kaeufe.
        if action.type ~= "MAIL_COLLECT"
            and #action.dependencies > config().MAX_DEPENDENCIES then
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
    if type(plan) ~= "table" or type(plan.actions) ~= "table" then return {}, false end
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

-- ---------------------------------------------------------------------------
-- ABSCHNITTE EINER ROUTE (1.1.0-beta.5)
--
-- Seit die Route nach Orten buendelt, hat sie eine natuerliche Gliederung:
-- erst einkaufen, dann die Post holen, dann herstellen, dann einstellen. Als
-- flache Liste von vierzig Zeilen ist das trotzdem eine Wurst - man sieht die
-- Gliederung erst, wenn man sie sich selbst zusammenreimt.
--
-- Die Abschnitte stehen deshalb hier und nicht in der Oberflaeche: Sie folgen
-- aus der Aktionsart, und der Guide und der Route-Tab sollen dieselbe
-- Einteilung zeigen.
-- ---------------------------------------------------------------------------

Execution.SECTION_LABEL = {
    VENDOR = "Beim Händler kaufen",
    BUY = "Im Auktionshaus kaufen",
    COLLECT = "Aus Briefkasten und Bank holen",
    CRAFT = "Herstellen",
    FARM = "Sammeln",
    POST = "Ins Auktionshaus stellen",
}

local SECTION_OF_TYPE = {
    VENDOR_BUY = "VENDOR",
    VENDOR_SELL = "VENDOR",
    BUY = "BUY",
    MAIL = "COLLECT",
    MAIL_COLLECT = "COLLECT",
    BANK_WITHDRAW = "COLLECT",
    BANK_DEPOSIT = "COLLECT",
    CRAFT = "CRAFT",
    CONVERT = "CRAFT",
    DISENCHANT = "CRAFT",
    FARM = "FARM",
    POST_AUCTION = "POST",
    SELL = "POST",
}

function Execution:SectionOf(step)
    if type(step) ~= "table" then return nil end
    return SECTION_OF_TYPE[step.type or ""]
end

-- Der Abschnitt je Schritt einer fertigen Liste.
--
-- Ein Weg gehoert zu dem Abschnitt, in den er FUEHRT: "Gehe zu: Auktionshaus"
-- steht einmal ueber dem Einkauf und einmal ueber dem Einstellen, und beide
-- Male ist die Ueberschrift darueber die richtige. Deshalb laeuft die Zuordnung
-- von hinten nach vorn - erst dann steht fest, wohin ein Weg gehoert.
--
-- Rueckgabe: Liste der Abschnittsschluessel je Position, und je Schluessel die
-- Zahl der Schritte darin.
function Execution:Sections(steps)
    local keys, counts = {}, {}
    if type(steps) ~= "table" then return keys, counts end
    local following = nil
    for index = #steps, 1, -1 do
        local key = self:SectionOf(steps[index])
        if key then
            following = key
        else
            key = following
        end
        keys[index] = key
        if key then counts[key] = (counts[key] or 0) + 1 end
    end
    return keys, counts
end

function Execution:SectionLabel(key)
    return Execution.SECTION_LABEL[key or ""] or nil
end

function Execution:Describe(action)
    if type(action) ~= "table" then return "", "" end
    local title = action.title or self:TypeLabel(action.type)
    return title, action.detail
end

-- Die vollstaendige Begruendung eines Schritts. Sie kommt aus der Chance und
-- wird hier nur um das ergaenzt, was an der Aktion selbst haengt.
function Execution:Explain(action, group)
    local lines = {}
    if type(action) ~= "table" then return lines end
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
