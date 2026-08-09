local addonName, GCP = ...

GCP.Knowledge = {}
local Knowledge = GCP.Knowledge

-- ---------------------------------------------------------------------------
-- KNOWLEDGE BASE (0.7.0)
--
-- Hier liegt Spielwissen, sonst nichts. Keine Bewertung, keine Formel, kein
-- Score - das steht in Future.lua. Diese Trennung ist Absicht: Spielwissen
-- veraltet mit jeder Phase, Rechenwege nicht. Wer die Wissensbasis aktualisiert,
-- soll keine Logik anfassen muessen; wer die Formel nachjustiert, kein
-- Spielwissen.
--
-- Aufbau:
--   Knowledge/Knowledge.lua   dieses Modul: Register, Pruefung, Nachschlagen
--   Knowledge/Phases.lua      bekannte Anniversary-Phasen
--   Knowledge/Items.lua       die Items, ueber die wir ueberhaupt etwas wissen
--   Knowledge/Recipes.lua     Materialabhaengigkeiten (Dependency Graph)
--   Knowledge/Catalysts.lua   bekannte zukuenftige Ereignisse je Item
--
-- PROVENANCE - die wichtigste Regel dieses Moduls:
-- Jede Aussage traegt, woher sie stammt. Ohne sourceConfidence wird ein Eintrag
-- nicht aufgenommen, sondern verworfen und gezaehlt (Knowledge.rejected). Ein
-- Addon, das nicht sagen kann, warum es etwas glaubt, soll es nicht behaupten.
--
--   official    von Blizzard angekuendigt oder im Spiel nachweisbar
--   historical  aus den TBC-Spieldaten bzw. dem bekannten TBC-Verlauf
--   inferred    daraus abgeleitet - plausibel, aber nicht belegt
--
-- KEINE LAUFZEIT-WEBZUGRIFFE. Addons koennen keine Webseiten abrufen, und das
-- ist hier kein Mangel, sondern die Bauform: Die Wissensbasis wird mit dem
-- Addon ausgeliefert und mit ihm aktualisiert. Die Struktur ist bewusst so
-- schlicht, dass sich diese Dateien spaeter aus einer externen Datenpipeline
-- erzeugen lassen (Blizzard-Daten, oeffentliche Spieldaten, eigene Kuratierung).
-- ---------------------------------------------------------------------------

-- Wissensstand. Steht im Zukunft-Tab, damit sichtbar ist, wie alt das Wissen
-- ist, auf dem die Einschaetzungen beruhen.
Knowledge.VERSION = "2026-08-09"
Knowledge.VERSION_LABEL = "09.08.2026"

Knowledge.SOURCE_RANK = { official = 3, historical = 2, inferred = 1 }
Knowledge.CONFIDENCE_RANK = { high = 3, medium = 2, low = 1 }

Knowledge.SOURCE_LABEL = {
    official = "offiziell bestätigt",
    historical = "aus TBC-Spieldaten",
    inferred = "abgeleitet",
}

-- Richtungen. demand_down und supply_up zeigen beide nach unten, meinen aber
-- Verschiedenes: weniger Nachfrage gegen mehr Angebot. Die Rechnung behandelt
-- sie gleich, die Erklaerung nicht.
Knowledge.DIRECTIONS = {
    demand_up = 1, demand_down = -1, supply_up = -1, supply_down = 1,
}

-- Ereignisarten. Die Liste ist absichtlich geschlossen: Ein Tippfehler im Typ
-- waere sonst ein stiller, nie wieder gefundener Eintrag.
Knowledge.TYPES = {
    NEW_RAID = true, NEW_RECIPE = true, NEW_GEM = true, NEW_ENCHANT = true,
    NEW_REPUTATION = true, NEW_DAILY = true, NEW_BIS_ITEM = true,
    RESISTANCE_REQUIREMENT = true, NEW_CRAFT = true, NEW_VENDOR = true,
    NEW_ZONE = true, NEW_PVP_SEASON = true, NEW_CONVERSION = true,
    SUPPLY_INCREASE = true, DEMAND_INCREASE = true,
}

Knowledge.TYPE_LABEL = {
    NEW_RAID = "neuer Raid",
    NEW_RECIPE = "neues Rezept",
    NEW_GEM = "neue Sockelsteine",
    NEW_ENCHANT = "neue Verzauberung",
    NEW_REPUTATION = "neuer Ruf",
    NEW_DAILY = "neue Tagesquests",
    NEW_BIS_ITEM = "neues Spitzen-Item",
    RESISTANCE_REQUIREMENT = "Widerstandsbedarf",
    NEW_CRAFT = "neue Herstellung",
    NEW_VENDOR = "neuer Händler",
    NEW_ZONE = "neues Gebiet",
    NEW_PVP_SEASON = "neue PvP-Saison",
    NEW_CONVERSION = "neue Umwandlung",
    SUPPLY_INCREASE = "mehr Angebot",
    DEMAND_INCREASE = "mehr Nachfrage",
}

Knowledge.RELATIONS = {
    craft_material = true,     -- Zutat eines Rezepts
    smelt_material = true,     -- Erz -> Barren
    conversion = true,         -- Umwandlung, z. B. Partikel -> Ur-Partikel
}

Knowledge.phases = {}
Knowledge.phaseByID = {}
Knowledge.catalysts = {}
Knowledge.catalystsByItem = {}
Knowledge.catalystsByPhase = {}
Knowledge.edges = {}
Knowledge.edgesByProduct = {}
Knowledge.edgesByMaterial = {}
Knowledge.items = {}
Knowledge.itemList = {}

-- Verworfene Eintraege. Kein Fehlerdialog, aber auch kein stilles Schlucken:
-- Die Tests pruefen diese Liste, und /gold future zeigt sie an.
Knowledge.rejected = {}

local function reject(kind, id, reason)
    Knowledge.rejected[#Knowledge.rejected + 1] = {
        kind = kind, id = tostring(id), reason = reason,
    }
    return false
end

function Knowledge:RejectedCount()
    return #self.rejected
end

local function isItemID(value)
    return type(value) == "number" and value > 0 and value == math.floor(value)
end

-- ---------------------------------------------------------------------------
-- Zeitrechnung
--
-- Releasetermine sind UTC-Zeitpunkte, keine lokalen. time({...}) rechnet in der
-- lokalen Zeitzone und wuerde je nach Rechner um Stunden danebenliegen -
-- deshalb hier eine eigene, zeitzonenfreie Umrechnung (days_from_civil, das
-- uebliche Verfahren mit auf Maerz verschobenem Jahresanfang, damit Schaltjahre
-- ohne Sonderfaelle aufgehen). Dieselbe Zahl auf jedem Rechner, auch im Test.
-- ---------------------------------------------------------------------------

local function daysFromCivil(year, month, day)
    year = year - (month <= 2 and 1 or 0)
    local era = math.floor(year / 400)
    local yearOfEra = year - era * 400                            -- 0..399
    local dayOfYear = math.floor((153 * (month + (month > 2 and -3 or 9)) + 2) / 5) + day - 1
    local dayOfEra = yearOfEra * 365 + math.floor(yearOfEra / 4)
        - math.floor(yearOfEra / 100) + dayOfYear                 -- 0..146096
    return era * 146097 + dayOfEra - 719468
end

-- Unix-Zeitstempel eines UTC-Zeitpunkts.
function Knowledge:UTC(spec)
    if type(spec) ~= "table" then return nil end
    local year, month, day = spec.year, spec.month, spec.day
    if type(year) ~= "number" or type(month) ~= "number" or type(day) ~= "number" then
        return nil
    end
    if month < 1 or month > 12 or day < 1 or day > 31 then return nil end
    return daysFromCivil(year, month, day) * 86400
        + (spec.hour or 0) * 3600 + (spec.min or 0) * 60 + (spec.sec or 0)
end

-- ---------------------------------------------------------------------------
-- Phasen
-- ---------------------------------------------------------------------------

-- release = nil heisst ausdruecklich "Termin unbekannt", nicht "kommt nicht".
-- Ein Termin aus dem urspruenglichen TBC oder aus TBC Classic ist KEIN
-- Anniversary-Termin und darf hier nie als solcher stehen.
function Knowledge:RegisterPhase(phase)
    if type(phase) ~= "table" then return reject("phase", "?", "keine Tabelle") end
    if type(phase.id) ~= "string" or phase.id == "" then
        return reject("phase", phase.id, "ohne id")
    end
    if self.phaseByID[phase.id] then
        return reject("phase", phase.id, "doppelte id")
    end
    if type(phase.name) ~= "string" or phase.name == "" then
        return reject("phase", phase.id, "ohne Namen")
    end
    if type(phase.order) ~= "number" then
        return reject("phase", phase.id, "ohne Reihenfolge")
    end
    if not self.SOURCE_RANK[phase.sourceConfidence] then
        return reject("phase", phase.id, "ohne Provenance")
    end
    if phase.release ~= nil and type(phase.release) ~= "number" then
        return reject("phase", phase.id, "ungültiger Releasezeitpunkt")
    end
    -- Ein exakter Termin braucht eine benannte Quelle. "Irgendwo gelesen" ist
    -- kein Datum.
    if phase.release ~= nil and (type(phase.sourceName) ~= "string" or phase.sourceName == "") then
        return reject("phase", phase.id, "Termin ohne Quellenangabe")
    end
    phase.content = phase.content or {}
    self.phases[#self.phases + 1] = phase
    self.phaseByID[phase.id] = phase
    table.sort(self.phases, function(a, b) return a.order < b.order end)
    return true
end

function Knowledge:GetPhase(id)
    return self.phaseByID[id]
end

function Knowledge:GetPhases()
    return self.phases
end

-- "live" | "upcoming" | "unknown". Ein bekannter Termin entscheidet; ohne
-- Termin zaehlt, was die Wissensbasis ueber den Zustand sagt (phase.live), und
-- wenn auch das fehlt, ist die Antwort ehrlich "unbekannt".
function Knowledge:PhaseStatus(phase, now)
    if type(phase) ~= "table" then return "unknown" end
    if type(phase.release) == "number" then
        return phase.release <= (now or 0) and "live" or "upcoming"
    end
    if phase.live == true then return "live" end
    if phase.live == false then return "upcoming" end
    return "unknown"
end

-- ---------------------------------------------------------------------------
-- Catalysts
-- ---------------------------------------------------------------------------

function Knowledge:RegisterCatalyst(catalyst)
    if type(catalyst) ~= "table" then return reject("catalyst", "?", "keine Tabelle") end
    local id = catalyst.id
    if type(id) ~= "string" or id == "" then
        return reject("catalyst", "?", "ohne id")
    end
    if not isItemID(catalyst.itemID) then
        return reject("catalyst", id, "ungültige Item-ID")
    end
    if not self.TYPES[catalyst.type] then
        return reject("catalyst", id, "unbekannter Typ")
    end
    if not self.DIRECTIONS[catalyst.direction] then
        return reject("catalyst", id, "unbekannte Richtung")
    end
    if type(catalyst.strength) ~= "number"
        or catalyst.strength <= 0 or catalyst.strength > 1 then
        return reject("catalyst", id, "Stärke außerhalb 0..1")
    end
    if not self.CONFIDENCE_RANK[catalyst.confidence] then
        return reject("catalyst", id, "ohne Confidence")
    end
    if not self.SOURCE_RANK[catalyst.sourceConfidence] then
        return reject("catalyst", id, "ohne Provenance")
    end
    if type(catalyst.sourceName) ~= "string" or catalyst.sourceName == "" then
        return reject("catalyst", id, "ohne Quellenangabe")
    end
    if type(catalyst.reason) ~= "string" or catalyst.reason == "" then
        return reject("catalyst", id, "ohne Begründung")
    end
    if catalyst.phase ~= nil and not self.phaseByID[catalyst.phase] then
        return reject("catalyst", id, "unbekannte Phase")
    end

    self.catalysts[#self.catalysts + 1] = catalyst
    local byItem = self.catalystsByItem[catalyst.itemID]
    if not byItem then
        byItem = {}
        self.catalystsByItem[catalyst.itemID] = byItem
    end
    byItem[#byItem + 1] = catalyst
    if catalyst.phase then
        local byPhase = self.catalystsByPhase[catalyst.phase]
        if not byPhase then
            byPhase = {}
            self.catalystsByPhase[catalyst.phase] = byPhase
        end
        byPhase[#byPhase + 1] = catalyst
    end
    return true
end

function Knowledge:GetCatalystsForItem(itemID)
    return self.catalystsByItem[itemID]
end

function Knowledge:GetCatalystsForPhase(phaseID)
    return self.catalystsByPhase[phaseID] or {}
end

-- ---------------------------------------------------------------------------
-- Dependency Graph
--
-- from = Material, to = Produkt. quantity darf nil sein: Dass ein Barren aus
-- Erz geschmolzen wird, ist gesichert, die genaue Stueckzahl in dieser
-- Wissensbasis nicht immer - und eine erfundene Zahl waere schlimmer als eine
-- fehlende. Die Rechnung braucht die Menge ohnehin nicht, sie steht fuer die
-- Erklaerung da.
-- ---------------------------------------------------------------------------

function Knowledge:RegisterEdge(edge)
    if type(edge) ~= "table" then return reject("edge", "?", "keine Tabelle") end
    local label = tostring(edge.from) .. "->" .. tostring(edge.to)
    if not isItemID(edge.from) or not isItemID(edge.to) then
        return reject("edge", label, "ungültige Item-ID")
    end
    if edge.from == edge.to then
        return reject("edge", label, "Kante auf sich selbst")
    end
    if not self.RELATIONS[edge.relation] then
        return reject("edge", label, "unbekannte Beziehung")
    end
    if edge.quantity ~= nil and (type(edge.quantity) ~= "number" or edge.quantity <= 0) then
        return reject("edge", label, "ungültige Menge")
    end
    if not self.SOURCE_RANK[edge.sourceConfidence] then
        return reject("edge", label, "ohne Provenance")
    end
    if type(edge.sourceName) ~= "string" or edge.sourceName == "" then
        return reject("edge", label, "ohne Quellenangabe")
    end

    self.edges[#self.edges + 1] = edge
    local byProduct = self.edgesByProduct[edge.to]
    if not byProduct then
        byProduct = {}
        self.edgesByProduct[edge.to] = byProduct
    end
    byProduct[#byProduct + 1] = edge
    local byMaterial = self.edgesByMaterial[edge.from]
    if not byMaterial then
        byMaterial = {}
        self.edgesByMaterial[edge.from] = byMaterial
    end
    byMaterial[#byMaterial + 1] = edge
    return true
end

-- Alle Zutaten eines Produkts.
function Knowledge:GetMaterialsOf(itemID)
    return self.edgesByProduct[itemID] or {}
end

-- Alles, wofuer ein Material gebraucht wird.
function Knowledge:GetProductsOf(itemID)
    return self.edgesByMaterial[itemID] or {}
end

-- ---------------------------------------------------------------------------
-- Items
--
-- Nur was hier steht, kennt die Wissensbasis beim Namen. Der Client liefert den
-- lokalisierten Namen zur Laufzeit; die englischen Namen hier dienen der
-- Lesbarkeit und dem Abgleich mit den Spieldaten - genau wie in Constants.lua.
-- ---------------------------------------------------------------------------

function Knowledge:RegisterItem(entry)
    if type(entry) ~= "table" then return reject("item", "?", "keine Tabelle") end
    if not isItemID(entry.id) then return reject("item", entry.id, "ungültige Item-ID") end
    if type(entry.name) ~= "string" or entry.name == "" then
        return reject("item", entry.id, "ohne Namen")
    end
    if self.items[entry.id] then return reject("item", entry.id, "doppelte Item-ID") end
    self.items[entry.id] = entry
    self.itemList[#self.itemList + 1] = entry
    return true
end

function Knowledge:GetItem(itemID)
    return self.items[itemID]
end

function Knowledge:ItemName(itemID)
    local entry = self.items[itemID]
    return entry and entry.name or nil
end

-- Alle Items, ueber die die Wissensbasis etwas aussagt - Catalyst-Ziele,
-- Rezeptzutaten und Produkte. Market.lua meldet sie zur Beobachtung an, damit
-- ueberhaupt eine Realm-Historie entsteht, bevor die Phase da ist.
function Knowledge:AllKnownItems()
    local seen, list = {}, {}
    local function add(itemID)
        if isItemID(itemID) and not seen[itemID] then
            seen[itemID] = true
            list[#list + 1] = itemID
        end
    end
    for _, catalyst in ipairs(self.catalysts) do add(catalyst.itemID) end
    for _, edge in ipairs(self.edges) do add(edge.from); add(edge.to) end
    for _, entry in ipairs(self.itemList) do add(entry.id) end
    return list
end

-- ---------------------------------------------------------------------------
-- PRUEFUNG DER WISSENSBASIS (0.9.0)
--
-- Register* faengt beim Eintragen ab, was offensichtlich falsch ist. Was es
-- nicht sehen kann, sind Widersprueche ZWISCHEN Eintraegen: ein Catalyst auf
-- ein Item, ueber das sonst nichts bekannt ist; eine Rezeptkante ins Leere;
-- ein Kreis im Abhaengigkeitsgraphen. Genau das prueft diese Funktion - und
-- zwar zur Laufzeit, damit eine neue Wissensdatei sofort auffaellt und nicht
-- erst, wenn der Zukunft-Tab merkwuerdige Zahlen zeigt.
--
-- Rueckgabe: Liste von { kind, id, problem }. Leer heisst: sauber.
-- ---------------------------------------------------------------------------

-- Die Wissensbasis wird beim Laden gebaut und danach nie veraendert. Die
-- Pruefung braucht deshalb genau einmal zu laufen.
function Knowledge:GetProblems()
    if not self.validationCache then
        self.validationCache = self:Validate()
    end
    return self.validationCache
end

function Knowledge:Validate()
    local problems = {}
    local function add(kind, id, problem)
        problems[#problems + 1] = { kind = kind, id = tostring(id), problem = problem }
    end

    -- Alles, was schon beim Eintragen verworfen wurde, ist ein Problem.
    for _, entry in ipairs(self.rejected) do
        add(entry.kind, entry.id, entry.reason)
    end

    -- Catalysts: Item muss bekannt sein, Phase muss existieren, ein exakter
    -- Termin braucht eine offizielle Quelle.
    for _, catalyst in ipairs(self.catalysts) do
        if not self.items[catalyst.itemID] then
            add("catalyst", catalyst.id,
                "verweist auf Item " .. tostring(catalyst.itemID)
                .. ", ueber das die Wissensbasis nichts sagt")
        end
        if catalyst.phase and not self.phaseByID[catalyst.phase] then
            add("catalyst", catalyst.id, "unbekannte Phase " .. tostring(catalyst.phase))
        end
    end

    -- Phasen: Ein Datum ohne offizielle Quelle waere eine Behauptung.
    for _, phase in ipairs(self.phases) do
        if phase.release ~= nil and phase.sourceConfidence ~= "official" then
            add("phase", phase.id,
                "exakter Termin ohne offizielle Quelle")
        end
    end

    -- Rezeptkanten: beide Enden muessen bekannt sein.
    for _, edge in ipairs(self.edges) do
        if not self.items[edge.from] then
            add("edge", tostring(edge.from) .. "->" .. tostring(edge.to),
                "Zutat " .. tostring(edge.from) .. " ist der Wissensbasis unbekannt")
        end
        if not self.items[edge.to] then
            add("edge", tostring(edge.from) .. "->" .. tostring(edge.to),
                "Produkt " .. tostring(edge.to) .. " ist der Wissensbasis unbekannt")
        end
        if edge.from == edge.to then
            add("edge", tostring(edge.from), "Kante auf sich selbst")
        end
    end

    -- Zyklen im Rezeptgraphen. Ein Kreis waere kein Fehler im Spiel (Urfeuer
    -- laesst sich hin und zurueck transmutieren), aber in der Wissensbasis:
    -- Der Dependency Graph laeuft sonst im Kreis. Deshalb wird er hier
    -- gefunden und gemeldet, statt zur Laufzeit begrenzt zu werden.
    local state = {}
    local function visit(itemID, stack)
        if state[itemID] == 2 then return false end
        if state[itemID] == 1 then
            add("edge", tostring(itemID),
                "Zyklus: " .. table.concat(stack, " -> ") .. " -> " .. tostring(itemID))
            return true
        end
        state[itemID] = 1
        stack[#stack + 1] = itemID
        for _, edge in ipairs(self.edgesByMaterial[itemID] or {}) do
            if visit(edge.to, stack) then
                state[itemID] = 2
                stack[#stack] = nil
                return true
            end
        end
        stack[#stack] = nil
        state[itemID] = 2
        return false
    end
    for _, edge in ipairs(self.edges) do
        if state[edge.from] == nil then visit(edge.from, {}) end
    end

    -- Verwaiste Items: Ein Item, ueber das die Wissensbasis etwas sagt, ohne
    -- dass es irgendwo vorkommt, ist toter Ballast.
    local referenced = {}
    for _, catalyst in ipairs(self.catalysts) do referenced[catalyst.itemID] = true end
    for _, edge in ipairs(self.edges) do
        referenced[edge.from] = true
        referenced[edge.to] = true
    end
    for _, entry in ipairs(self.itemList) do
        if not referenced[entry.id] and not entry.standalone then
            add("item", entry.id, "steht in keinem Catalyst und keiner Rezeptkante")
        end
    end

    return problems
end

function Knowledge:Summary()
    return {
        version = self.VERSION,
        phases = #self.phases,
        catalysts = #self.catalysts,
        edges = #self.edges,
        items = #self.itemList,
        rejected = #self.rejected,
        locations = self.CountLocations and self:CountLocations() or 0,
        farmRoutes = self.CountFarmRoutes and self:CountFarmRoutes() or 0,
        problems = #self:GetProblems(),
    }
end
