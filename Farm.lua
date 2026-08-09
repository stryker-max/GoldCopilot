local addonName, GCP = ...

GCP.Farm = {}
local Farm = GCP.Farm

local GetItemInfoCompat = (C_Item and C_Item.GetItemInfo) or GetItemInfo

-- ---------------------------------------------------------------------------
-- FARM BRAIN (0.9.0)
--
-- "Elementarplateau bringt 238 g/h" ist die Sorte Aussage, die in jedem Guide
-- steht und fuer niemanden stimmt. Sie haengt an Ausruestung, Klasse, Route,
-- Konkurrenz, Serverbevoelkerung und Tageszeit.
--
-- DESHALB ERFINDET GOLD COPILOT KEINE FARMRATE. Es misst die eigene.
--
-- Eine Farm-Sitzung ist ein Zeitraum, in dem der Spieler bestimmte Items
-- einsammelt. Gold Copilot merkt sich Start- und Endbestand, die aktive Zeit
-- und die Zone - daraus entsteht eine Stueckzahl je Stunde und, ueber die
-- Marktpreise, eine Goldrate. Nach genuegend Sitzungen ist das eine belastbare
-- persoenliche Zahl. Vorher steht dort "noch keine eigene Rate".
--
-- WAS HIER AUSDRUECKLICH NICHT PASSIERT:
--   * Keine Gold/h aus Guides. Die Schaetzwerte in C.FARM_CATALOG gehoeren dem
--     Tagesplan aus 0.4 und sind dort als Schaetzung ausgewiesen; der Farm
--     Brain benutzt sie nicht.
--   * Keine Hochrechnung aus einer einzigen Sitzung. Unter MIN_SESSIONS gibt
--     es einen Wert, aber keine Confidence ueber "low".
--   * Keine Zeit, die der Spieler nicht gefarmt hat. Wer die Sitzung offen
--     laesst und schlafen geht, bekommt keine 8-Stunden-Rate: Ein Fortschritt
--     ohne Ausbeute ueber IDLE_TIMEOUT beendet die Sitzung automatisch.
-- ---------------------------------------------------------------------------

local function config()
    return GCP.Constants.FARM
end

Farm.revision = 0
Farm.session = nil               -- laufende Sitzung (Laufzeit + Speicher)

local function isPositive(value)
    return type(value) == "number" and value > 0
end

local function isItemID(value)
    return type(value) == "number" and value > 0 and value == math.floor(value)
end

local function now()
    if type(time) == "function" then
        local ok, value = pcall(time)
        if ok and type(value) == "number" then return value end
    end
    return 0
end

function Farm:Touch()
    self.revision = self.revision + 1
    self.cache = nil
end

-- ---------------------------------------------------------------------------
-- Speicher
--
--   db.farm = {
--       version = 1,
--       session = { <laufende Sitzung> } | nil,
--       sessions = {
--           { z = "Nagrand", s = 1786000000, e = 1786003600, m = 58.2,
--             y = { [23425] = 41 }, g = 2050000 },
--       },
--       rates = { ["Nagrand|23425"] = { n = 7, ... } },   -- abgeleitet, Cache
--   }
--
-- Aufgeschrieben werden nur ABGESCHLOSSENE Sitzungen mit Ausbeute. Eine
-- Sitzung ohne einen einzigen Fund ist keine Messung, sondern ein Ausrutscher -
-- sie wuerde den Median nach unten ziehen, ohne etwas ueber die Rate zu sagen.
-- ---------------------------------------------------------------------------

function Farm:EnsureStore()
    local db = GCP.db
    if not db then return nil end
    local C = config()
    local profile = GCP:Profile()
    local store = profile.farm
    if type(store) ~= "table" or store.version ~= C.STORE_VERSION then
        store = { version = C.STORE_VERSION, sessions = {} }
        profile.farm = store
    end
    if type(store.sessions) ~= "table" then store.sessions = {} end
    return store
end

function Farm:Reset()
    local store = self:EnsureStore()
    if not store then return 0 end
    local removed = #store.sessions
    store.sessions = {}
    store.session = nil
    self.session = nil
    self:Touch()
    return removed
end

-- ---------------------------------------------------------------------------
-- Sitzung
-- ---------------------------------------------------------------------------

function Farm:CountOf(itemID)
    if type(GetItemCount) == "function" then
        local ok, count = pcall(GetItemCount, itemID)
        if ok and type(count) == "number" then return count end
    end
    local bags = GCP.Inventory:ScanBags({})
    local entry = bags[itemID]
    return entry and entry.count or 0
end

function Farm:Snapshot(itemIDs)
    local snapshot = {}
    if type(itemIDs) == "table" and #itemIDs > 0 then
        for _, itemID in ipairs(itemIDs) do
            if isItemID(itemID) then snapshot[itemID] = self:CountOf(itemID) end
        end
        return snapshot
    end
    -- Offene Sitzung: alles, was in den Taschen liegt. Der Vergleich am Ende
    -- laeuft dann ueber jedes Item, das dazugekommen ist.
    for itemID, entry in pairs(GCP.Inventory:ScanBags({})) do
        if isItemID(itemID) then snapshot[itemID] = entry.count end
    end
    return snapshot
end

-- Startet eine Farmsitzung. Ohne Ziel-Items wird ALLES gezaehlt, was in den
-- Taschen dazukommt - das ist der Normalfall: Wer farmt, weiss vorher selten,
-- was genau fallen wird. Mit Ziel-Items zaehlt nur, was auf der Liste steht;
-- so entstehen die Raten je Item, mit denen der Routenplaner rechnet.
function Farm:Start(itemIDs, zone, options)
    local store = self:EnsureStore()
    if not store then return nil end
    options = type(options) == "table" and options or {}
    if type(itemIDs) ~= "table" then itemIDs = nil end
    if type(zone) ~= "string" then zone = nil end
    local list = {}
    for _, itemID in ipairs(itemIDs or {}) do
        if isItemID(itemID) then list[#list + 1] = itemID end
    end

    local session = {
        items = list,
        open = #list == 0,
        -- Wer die Sitzung gestartet hat, entscheidet, wer sie beenden darf:
        -- Eine von Hand gestartete Messung soll der Guide nicht wegraeumen,
        -- nur weil seine Route gerade den Farmschritt verlaesst.
        startedByGuide = options.byGuide and true or false,
        zone = zone or (GCP.Navigation and GCP.Navigation:ZoneName()) or "unbekannt",
        startedAt = now(),
        lastProgressAt = now(),
        startInventory = self:Snapshot(list),
        activeSeconds = 0,
        lastTickAt = (type(GetTime) == "function" and GetTime()) or now(),
    }
    store.session = session
    self.session = session
    self:Touch()
    return session
end

function Farm:Current()
    local store = self:EnsureStore()
    if not store then return nil end
    self.session = store.session
    return store.session
end

-- Aktive Zeit fortschreiben. Ein Sprung ueber MAX_TICK_SECONDS ist keine
-- Farmzeit, sondern ein Ladebildschirm, ein /reload oder eine Pause - er
-- zaehlt nicht mit. Der Wert ist bewusst grosszuegiger als beim Guide: Wer
-- farmt, hat das Fenster oft zu, und die Leerlaufgrenze beendet eine wirklich
-- unterbrochene Sitzung ohnehin.
function Farm:Accumulate(session)
    local C = config()
    local clock = (type(GetTime) == "function" and GetTime()) or now()
    local last = session.lastTickAt or clock
    local delta = clock - last
    if delta > 0 and delta <= C.MAX_TICK_SECONDS then
        session.activeSeconds = (session.activeSeconds or 0) + delta
    end
    session.lastTickAt = clock
    return session.activeSeconds or 0
end

function Farm:Tick()
    local session = self:Current()
    if not session then return nil end
    local C = config()
    self:Accumulate(session)
    -- Erst nachsehen, ob seit dem letzten Tick etwas dazugekommen ist: Status
    -- schreibt lastProgressAt fort. Ohne diesen Aufruf wuerde die
    -- Leerlaufpruefung eine erfolgreiche Sitzung beenden, nur weil zwischen
    -- zwei Ticks niemand hingeschaut hat.
    self:Status()
    -- Ohne Ausbeute ueber die Leerlaufgrenze hinaus ist die Sitzung vorbei.
    if (now() - (session.lastProgressAt or session.startedAt)) > C.IDLE_TIMEOUT then
        return self:Stop("Leerlauf")
    end
    return session
end

-- Aktueller Stand der Sitzung: Ausbeute, aktive Zeit, gemessene Rate.
function Farm:Status()
    local session = self:Current()
    if not session then return nil end
    local yield, value = {}, 0
    local total = 0

    -- Welche Items werden verglichen? Bei einer Zielliste genau die, sonst
    -- alles, was jetzt in den Taschen liegt.
    local candidates = {}
    if session.open then
        for itemID in pairs(GCP.Inventory:ScanBags({})) do candidates[#candidates + 1] = itemID end
        -- Items, die zwischendurch komplett verkauft wurden, faenden sich
        -- sonst nicht mehr - sie zaehlen mit ihrem Ausgangsstand von null.
        for itemID in pairs(session.startInventory) do
            local seen = false
            for _, known in ipairs(candidates) do
                if known == itemID then seen = true break end
            end
            if not seen then candidates[#candidates + 1] = itemID end
        end
    else
        candidates = session.items
    end

    for _, itemID in ipairs(candidates) do
        local gained = math.max(self:CountOf(itemID) - (session.startInventory[itemID] or 0), 0)
        if gained > 0 then
            yield[itemID] = gained
            total = total + gained
            local unit = GCP.Prices:GetBestPlanningValue(itemID)
            if isPositive(unit) then value = value + unit * gained end
        end
    end
    if total > (session.lastTotal or 0) then
        session.lastTotal = total
        session.lastProgressAt = now()
    end
    local minutes = (session.activeSeconds or 0) / 60
    local status = {
        zone = session.zone,
        items = session.items,
        open = session.open and true or false,
        yield = yield,
        totalItems = total,
        estimatedValue = math.floor(value + 0.5),
        activeMinutes = minutes,
        startedAt = session.startedAt,
    }
    if minutes >= config().MIN_MINUTES then
        status.itemsPerHour = total / (minutes / 60)
        status.goldPerHour = value / (minutes / 60)
    end
    return status
end

function Farm:Stop(reason)
    local store = self:EnsureStore()
    local session = self:Current()
    if not store or not session then return nil end
    -- Die letzte Strecke bis zum Stopp gehoert noch zur Sitzung.
    self:Accumulate(session)
    local status = self:Status()
    store.session = nil
    self.session = nil

    -- Eine Sitzung ohne Ausbeute oder ohne Mindestdauer wird nicht
    -- aufgeschrieben. Sie waere keine Messung, sondern Rauschen.
    if not status or status.totalItems <= 0
        or status.activeMinutes < config().MIN_MINUTES then
        self:Touch()
        return status, reason, false
    end

    local record = {
        z = status.zone,
        s = session.startedAt,
        e = now(),
        m = math.floor(status.activeMinutes * 10 + 0.5) / 10,
        y = status.yield,
        g = status.estimatedValue,
    }
    store.sessions[#store.sessions + 1] = record
    while #store.sessions > config().MAX_SESSIONS do
        table.remove(store.sessions, 1)
    end
    self:Touch()
    if GCP.Personal then GCP.Personal:RecordFarmSession(record) end
    return status, reason, true
end

-- ---------------------------------------------------------------------------
-- PERSOENLICHE FARMRATE
--
-- Median statt Mittelwert: Eine einzige Sitzung mit einem Glueckstreffer soll
-- die Erwartung nicht verschieben. Die Confidence haengt an der Zahl der
-- Sitzungen - und darunter steht die Zahl, damit niemand aus drei Sitzungen
-- eine Gewissheit liest.
-- ---------------------------------------------------------------------------

local function median(values)
    if #values == 0 then return nil end
    table.sort(values)
    local middle = math.floor(#values / 2)
    if #values % 2 == 1 then return values[middle + 1] end
    return (values[middle] + values[middle + 1]) / 2
end

function Farm:ConfidenceOf(sessions)
    local C = config().CONFIDENCE
    sessions = tonumber(sessions) or 0
    if sessions >= C.HIGH_SESSIONS then return "high" end
    if sessions >= C.MEDIUM_SESSIONS then return "medium" end
    if sessions >= C.LOW_SESSIONS then return "low" end
    return "none"
end

-- Rate je Zone (und optional je Item). Ohne Sitzungen gibt es nil, nicht null.
function Farm:GetRate(zone, itemID)
    local store = self:EnsureStore()
    if not store then return nil end
    local goldRates, itemRates = {}, {}
    local sessions = 0
    for _, record in ipairs(store.sessions) do
        if (zone == nil or record.z == zone) and isPositive(record.m) then
            local hours = record.m / 60
            local counted = false
            if itemID then
                local gained = record.y and record.y[itemID]
                if isPositive(gained) then
                    itemRates[#itemRates + 1] = gained / hours
                    counted = true
                end
            else
                local total = 0
                for _, gained in pairs(record.y or {}) do total = total + gained end
                if total > 0 then
                    itemRates[#itemRates + 1] = total / hours
                    counted = true
                end
            end
            if counted and isPositive(record.g) then
                goldRates[#goldRates + 1] = record.g / hours
            end
            if counted then sessions = sessions + 1 end
        end
    end
    if sessions == 0 then return nil end
    return {
        zone = zone,
        itemID = itemID,
        sessions = sessions,
        medianItemsPerHour = median(itemRates),
        medianGoldPerHour = median(goldRates),
        confidence = self:ConfidenceOf(sessions),
    }
end

function Farm:Zones()
    local store = self:EnsureStore()
    if not store then return {} end
    local seen, list = {}, {}
    for _, record in ipairs(store.sessions) do
        if record.z and not seen[record.z] then
            seen[record.z] = true
            list[#list + 1] = record.z
        end
    end
    table.sort(list)
    return list
end

function Farm:SessionCount()
    local store = self:EnsureStore()
    return store and #store.sessions or 0
end

-- ---------------------------------------------------------------------------
-- ADAPTIVES FARMEN
--
-- Waehrend einer Sitzung wird die laufende Rate mit dem eigenen Median
-- verglichen. Faellt sie deutlich ab, sagt Gold Copilot das - und schaut nach,
-- ob eine andere Aktivitaet gerade eine hoehere erwartete Goldrate hat.
-- Verglichen wird ausschliesslich mit EIGENEN Zahlen; ohne Median gibt es
-- keinen Vergleich und damit auch keinen Rat.
-- ---------------------------------------------------------------------------

function Farm:Assess()
    local status = self:Status()
    if not status then return nil end
    local rate = self:GetRate(status.zone)
    local assessment = { status = status, rate = rate }
    if not rate or not isPositive(rate.medianGoldPerHour) then
        assessment.text = "Noch keine eigene Farmrate für diese Zone – "
            .. "Gold Copilot misst gerade die erste."
        return assessment
    end
    if not isPositive(status.goldPerHour) then
        assessment.text = string.format("Dein Median in %s: %s/h aus %d Sitzung(en).",
            status.zone, GCP.Prices:FormatGold(rate.medianGoldPerHour), rate.sessions)
        return assessment
    end
    local ratio = status.goldPerHour / rate.medianGoldPerHour
    assessment.ratio = ratio
    local delta = (ratio - 1) * 100
    if math.abs(delta) < config().DEVIATION_THRESHOLD * 100 then
        assessment.text = string.format("Deine aktuelle Rate liegt im Rahmen deines "
            .. "persönlichen Medians (%s/h).", GCP.Prices:FormatGold(rate.medianGoldPerHour))
        return assessment
    end
    if delta < 0 then
        assessment.below = true
        assessment.text = string.format("Deine aktuelle Rate liegt %.0f %% unter deinem "
            .. "persönlichen Median.", -delta)
        assessment.alternative = self:BetterAlternative(status.goldPerHour)
    else
        assessment.text = string.format("Deine aktuelle Rate liegt %.0f %% über deinem "
            .. "persönlichen Median.", delta)
    end
    return assessment
end

-- Gibt es gerade eine belastbare Chance mit hoeherer erwarteter aktiver
-- Goldrate? Verglichen wird Gewinn je aktiver Minute - nicht Gewinn absolut.
function Farm:BetterAlternative(goldPerHour)
    if not isPositive(goldPerHour) then return nil end
    local report = GCP.Opportunity:BuildReport()
    local best, bestRate = nil, goldPerHour * config().ALTERNATIVE_MARGIN
    for _, opportunity in ipairs(report.opportunities or {}) do
        local minutes = GCP.Route:MinutesPerUnit(opportunity)
        if isPositive(minutes) and isPositive(opportunity.expectedProfit) then
            local rate = opportunity.expectedProfit / (minutes / 60)
            if rate > bestRate then best, bestRate = opportunity, rate end
        end
    end
    if not best then return nil end
    return {
        opportunity = best,
        goldPerHour = bestRate,
        text = string.format("%s weist gerade eine höhere erwartete aktive Goldrate auf "
            .. "(%s/h gegenüber %s/h).", best.title or "Eine andere Chance",
            GCP.Prices:FormatGold(bestRate), GCP.Prices:FormatGold(goldPerHour)),
    }
end

-- ---------------------------------------------------------------------------
-- FARMBLOECKE FUER DIE ROUTE
--
-- Ein Farmblock kommt NUR zustande, wenn es eine eigene gemessene Rate gibt.
-- Ohne sie waere jede Minutenangabe und jedes Potenzial geraten - und ein
-- geratener Farmblock ist der schnellste Weg, eine ganze Route unglaubwuerdig
-- zu machen.
-- ---------------------------------------------------------------------------

function Farm:BuildOpportunities(minutesAvailable)
    local store = self:EnsureStore()
    if not store or #store.sessions == 0 then return {} end
    local C = config()
    minutesAvailable = math.max(math.min(minutesAvailable or C.BLOCK_MINUTES,
        C.MAX_BLOCK_MINUTES), C.MIN_MINUTES)

    -- Je Zone und Item eine Chance, sofern die Rate belastbar ist.
    local seen, list = {}, {}
    for _, record in ipairs(store.sessions) do
        for itemID in pairs(record.y or {}) do
            local key = tostring(record.z) .. "|" .. tostring(itemID)
            if not seen[key] then
                seen[key] = true
                local rate = self:GetRate(record.z, itemID)
                if rate and rate.sessions >= C.CONFIDENCE.LOW_SESSIONS
                    and isPositive(rate.medianItemsPerHour) then
                    local unit = GCP.Prices:GetBestPlanningValue(itemID)
                    if isPositive(unit) then
                        local minutes = math.min(minutesAvailable, C.BLOCK_MINUTES)
                        local quantity = math.floor(rate.medianItemsPerHour * (minutes / 60))
                        if quantity >= 1 then
                            local name = (GetItemInfoCompat and GetItemInfoCompat(itemID))
                                or ("Item " .. itemID)
                            list[#list + 1] = {
                                type = "farm",
                                key = "farm:" .. key,
                                itemID = itemID,
                                saleItemID = itemID,
                                title = string.format("%s in %s farmen", name, record.z),
                                action = string.format("%d× %s sammeln", quantity, name),
                                cost = 0,
                                expectedRevenue = unit * quantity,
                                expectedProfit = unit * quantity,
                                roi = nil,
                                confidence = rate.confidence,
                                opportunityScore = nil,
                                minutesPerUnit = nil,
                                blockMinutes = minutes,
                                quantity = quantity,
                                rate = rate,
                                zone = record.z,
                                execution = {
                                    method = "farm",
                                    zone = record.z,
                                    inputs = nil,
                                    outputs = { { itemID = itemID, count = quantity } },
                                    sellItemID = itemID,
                                    sellCount = quantity,
                                    sellUnitPrice = unit,
                                    farmMinutes = minutes,
                                },
                                explanation = {
                                    string.format("Deine gemessene Rate in %s: %.0f Stück/h "
                                        .. "aus %d Sitzung(en).", record.z,
                                        rate.medianItemsPerHour, rate.sessions),
                                    string.format("Datenlage: %s",
                                        GCP.Market:ConfidenceLabel(rate.confidence)),
                                    string.format("Wert je Stück: %s",
                                        GCP.Prices:FormatMoney(unit)),
                                    "Farmraten stammen ausschließlich aus deinen eigenen "
                                        .. "Sitzungen – Gold Copilot erfindet keine Gold/h.",
                                },
                            }
                        end
                    end
                end
            end
        end
    end
    table.sort(list, function(a, b)
        if a.expectedProfit ~= b.expectedProfit then
            return a.expectedProfit > b.expectedProfit
        end
        return a.key < b.key
    end)
    return list
end

function Farm:SummaryText()
    local count = self:SessionCount()
    if count == 0 then
        return "Noch keine Farmhistorie – Gold Copilot lernt deine Raten aus "
            .. "deinen eigenen Sitzungen."
    end
    local zones = self:Zones()
    return string.format("%d Farmsitzung(en) in %d Zone(n).", count, #zones)
end
