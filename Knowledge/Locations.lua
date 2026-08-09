local addonName, GCP = ...

local Knowledge = GCP.Knowledge

-- ---------------------------------------------------------------------------
-- ORTE (0.9.0)
--
-- Der Guide zeigt einen Pfeil. Ein Pfeil braucht Koordinaten. Koordinaten sind
-- die einzige Art Spielwissen, bei der ein Fehler den Spieler nicht bloss
-- schlecht beraet, sondern aktiv in die falsche Richtung schickt.
--
-- DESHALB STEHT HIER KEINE EINZIGE GERATENE KOORDINATE.
--
-- Gold Copilot loest das Problem anders herum: Es LERNT Orte aus den eigenen
-- Besuchen des Spielers. Wer einmal ein Auktionshaus geoeffnet hat, hat dem
-- Addon damit belegt, wo dieses Auktionshaus liegt - Karte, x, y, Zone, alles
-- direkt vom Client. Das ist nicht nur ehrlicher als eine kuratierte Liste, es
-- ist auch genauer: Es sind genau die Orte, die dieser Spieler benutzt, auf
-- seiner Fraktion, in seinen Staedten.
--
-- Die Erfassung steht in Navigation.lua; hier steht nur das SCHEMA und die
-- Pruefung. Der kuratierte Teil (LOCATIONS weiter unten) ist bewusst leer und
-- ausdruecklich ein Erweiterungspunkt: Sobald belegte Koordinaten aus einer
-- Datenpipeline vorliegen, koennen sie hier eingetragen werden, ohne dass an
-- Navigation.lua etwas geaendert werden muss.
--
-- SCHEMA eines Ortseintrags:
--   {
--       id = "orgrimmar-ah",         -- eindeutig
--       kind = "AUCTION_HOUSE",      -- siehe KINDS
--       mapID = 85,                  -- UiMapID; wird gegen den Client geprueft
--       x = 0.545, y = 0.687,        -- Kartenkoordinaten 0..1
--       name = "Auktionshaus Orgrimmar",
--       zone = "Orgrimmar",
--       faction = "Horde" | "Alliance" | nil,
--       sourceConfidence = "official" | "historical" | "inferred",
--       sourceName = "woher",
--       sourceReference = optional,
--       knowledgeVersion = Knowledge.VERSION,
--   }
--
-- Was ohne gueltige mapID, ohne Koordinaten im Bereich 0..1, ohne bekannte Art
-- oder ohne Provenance kommt, wird verworfen und gezaehlt - wie jeder andere
-- Wissenseintrag auch.
-- ---------------------------------------------------------------------------

Knowledge.LOCATION_KINDS = {
    AUCTION_HOUSE = true,
    BANK = true,
    MAILBOX = true,
    PROFESSION = true,
    VENDOR = true,
    CRAFT_LOCATION = true,
    FARM_AREA = true,
    NPC = true,
}

Knowledge.LOCATION_KIND_LABEL = {
    AUCTION_HOUSE = "Auktionshaus",
    BANK = "Bank",
    MAILBOX = "Briefkasten",
    PROFESSION = "Beruf",
    VENDOR = "Händler",
    CRAFT_LOCATION = "Arbeitsplatz",
    FARM_AREA = "Farmgebiet",
    NPC = "NPC",
}

Knowledge.locations = {}
Knowledge.locationsByKind = {}

local function rejectLocation(id, reason)
    Knowledge.rejected[#Knowledge.rejected + 1] =
        { kind = "location", id = tostring(id), reason = reason }
    return false
end

-- Eine UiMapID ist eine positive ganze Zahl. Ob sie im laufenden Client
-- existiert, weiss nur der Client - deshalb wird sie hier auf Form geprueft und
-- bei der Benutzung noch einmal gegen C_Map.GetMapInfo. Ein Eintrag, den der
-- Client nicht kennt, fuehrt zu einer Textanweisung ohne Pfeil, nicht zu einem
-- Pfeil ins Nichts.
local function isMapID(value)
    return type(value) == "number" and value > 0 and value == math.floor(value)
        and value < 100000
end

local function isCoordinate(value)
    return type(value) == "number" and value >= 0 and value <= 1
end

function Knowledge:RegisterLocation(entry)
    if type(entry) ~= "table" then return rejectLocation("?", "keine Tabelle") end
    local id = entry.id
    if type(id) ~= "string" or id == "" then
        return rejectLocation(id, "ohne Kennung")
    end
    if self.locations[id] then return rejectLocation(id, "doppelte Kennung") end
    if not self.LOCATION_KINDS[entry.kind] then
        return rejectLocation(id, "unbekannte Ortsart: " .. tostring(entry.kind))
    end
    if not isMapID(entry.mapID) then
        return rejectLocation(id, "ungültige MapID")
    end
    if not isCoordinate(entry.x) or not isCoordinate(entry.y) then
        return rejectLocation(id, "Koordinaten außerhalb von 0..1")
    end
    if type(entry.name) ~= "string" or entry.name == "" then
        return rejectLocation(id, "ohne Namen")
    end
    if not self.SOURCE_RANK[entry.sourceConfidence] then
        return rejectLocation(id, "ohne Provenance")
    end
    if type(entry.sourceName) ~= "string" or entry.sourceName == "" then
        return rejectLocation(id, "ohne Quellenangabe")
    end
    entry.knowledgeVersion = entry.knowledgeVersion or self.VERSION
    self.locations[id] = entry
    local bucket = self.locationsByKind[entry.kind]
    if not bucket then
        bucket = {}
        self.locationsByKind[entry.kind] = bucket
    end
    bucket[#bucket + 1] = entry
    return true
end

function Knowledge:GetLocation(id)
    return self.locations[id]
end

function Knowledge:GetLocationsOfKind(kind)
    return self.locationsByKind[kind] or {}
end

function Knowledge:CountLocations()
    local count = 0
    for _ in pairs(self.locations) do count = count + 1 end
    return count
end

-- ---------------------------------------------------------------------------
-- KURATIERTE ORTE
--
-- Absichtlich leer. Siehe oben: Eine geratene Koordinate ist schlimmer als
-- keine. Was Gold Copilot ueber Orte weiss, lernt es aus den Besuchen des
-- Spielers (Navigation.lua) - und was es nicht weiss, sagt es als Text.
--
-- Wer diese Liste fuellt, muss je Eintrag belegen koennen, woher Karte und
-- Koordinate stammen; RegisterLocation nimmt nichts ohne sourceConfidence und
-- sourceName an.
-- ---------------------------------------------------------------------------

local LOCATIONS = {
}

for _, entry in ipairs(LOCATIONS) do
    Knowledge:RegisterLocation(entry)
end
