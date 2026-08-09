local addonName, GCP = ...

local Knowledge = GCP.Knowledge

-- ---------------------------------------------------------------------------
-- FARMROUTEN (0.9.0)
--
-- Dieselbe Regel wie bei den Orten: KEINE erfundenen Wegpunkte. Eine falsche
-- Farmroute schickt den Spieler nicht nur ins Leere, sie kostet ihn die Zeit,
-- die er eigentlich sparen wollte.
--
-- Deshalb gilt hier:
--   * Was Gold Copilot ueber Farmen weiss, sind ZAHLEN aus den eigenen
--     Sitzungen des Spielers (Farm.lua): wie viel er in welcher Zeit
--     eingesammelt hat, in welcher Zone. Diese Zahlen sind gemessen, nicht
--     geschaetzt.
--   * Was hier steht, sind WEGE. Eine validierte Route besteht aus einer Zone
--     und einer Folge von Wegpunkten, die im Kreis fuehrt. Ohne belegte
--     Koordinaten gibt es keine Route - und dann farmt der Spieler wie immer,
--     nur dass Gold Copilot mitzaehlt.
--
-- SCHEMA:
--   {
--       id = "nagrand-adamantit",
--       name = "Adamantit-Runde Nagrand",
--       mapID = 107,
--       itemIDs = { 23425 },
--       loop = true,
--       waypoints = { { x = 0.41, y = 0.52 }, ... },
--       minSkill = 325, skill = "mining",
--       sourceConfidence = "official" | "historical" | "inferred",
--       sourceName = "woher",
--       knowledgeVersion = ...,
--   }
-- ---------------------------------------------------------------------------

Knowledge.farmRoutes = {}
Knowledge.farmRoutesByItem = {}

local function rejectRoute(id, reason)
    Knowledge.rejected[#Knowledge.rejected + 1] =
        { kind = "farmroute", id = tostring(id), reason = reason }
    return false
end

local function isCoordinate(value)
    return type(value) == "number" and value >= 0 and value <= 1
end

function Knowledge:RegisterFarmRoute(entry)
    if type(entry) ~= "table" then return rejectRoute("?", "keine Tabelle") end
    local id = entry.id
    if type(id) ~= "string" or id == "" then return rejectRoute(id, "ohne Kennung") end
    if self.farmRoutes[id] then return rejectRoute(id, "doppelte Kennung") end
    if type(entry.name) ~= "string" or entry.name == "" then
        return rejectRoute(id, "ohne Namen")
    end
    if type(entry.mapID) ~= "number" or entry.mapID <= 0
        or entry.mapID ~= math.floor(entry.mapID) then
        return rejectRoute(id, "ungültige MapID")
    end
    if type(entry.itemIDs) ~= "table" or #entry.itemIDs == 0 then
        return rejectRoute(id, "ohne Ziel-Items")
    end
    for _, itemID in ipairs(entry.itemIDs) do
        if type(itemID) ~= "number" or itemID <= 0 then
            return rejectRoute(id, "ungültige Item-ID")
        end
    end
    if type(entry.waypoints) ~= "table" or #entry.waypoints < 2 then
        return rejectRoute(id, "weniger als zwei Wegpunkte")
    end
    for _, point in ipairs(entry.waypoints) do
        if type(point) ~= "table" or not isCoordinate(point.x) or not isCoordinate(point.y) then
            return rejectRoute(id, "Wegpunkt außerhalb von 0..1")
        end
    end
    if not self.SOURCE_RANK[entry.sourceConfidence] then
        return rejectRoute(id, "ohne Provenance")
    end
    if type(entry.sourceName) ~= "string" or entry.sourceName == "" then
        return rejectRoute(id, "ohne Quellenangabe")
    end
    entry.knowledgeVersion = entry.knowledgeVersion or self.VERSION
    self.farmRoutes[id] = entry
    for _, itemID in ipairs(entry.itemIDs) do
        local bucket = self.farmRoutesByItem[itemID]
        if not bucket then
            bucket = {}
            self.farmRoutesByItem[itemID] = bucket
        end
        bucket[#bucket + 1] = entry
    end
    return true
end

function Knowledge:GetFarmRoute(id)
    return self.farmRoutes[id]
end

function Knowledge:GetFarmRoutesForItem(itemID)
    return self.farmRoutesByItem[itemID] or {}
end

function Knowledge:CountFarmRoutes()
    local count = 0
    for _ in pairs(self.farmRoutes) do count = count + 1 end
    return count
end

-- ---------------------------------------------------------------------------
-- KURATIERTE ROUTEN
--
-- Absichtlich leer. Solange keine belegten Wegpunkte vorliegen, gibt es keine
-- Route - und Gold Copilot behauptet auch keine. Der Farm Brain rechnet
-- trotzdem: Er misst, was der Spieler tatsaechlich einsammelt, und sagt ihm,
-- wie seine aktuelle Sitzung im Vergleich zu seinen eigenen Sitzungen laeuft.
-- ---------------------------------------------------------------------------

local FARM_ROUTES = {
}

for _, entry in ipairs(FARM_ROUTES) do
    Knowledge:RegisterFarmRoute(entry)
end
