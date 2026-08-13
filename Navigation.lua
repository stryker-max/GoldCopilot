local addonName, GCP = ...

GCP.Navigation = {}
local Navigation = GCP.Navigation

-- ---------------------------------------------------------------------------
-- NAVIGATION (0.9.0)
--
-- Der Guide sagt "Gehe zum Auktionshaus". Damit daraus ein Pfeil wird, muss
-- das Addon wissen, wo dieses Auktionshaus liegt. Es gibt keine WoW-API, die
-- das verraet - und geratene Koordinaten sind hier der teuerste denkbare
-- Fehler, weil sie den Spieler aktiv in die falsche Richtung schicken.
--
-- DESHALB LERNT GOLD COPILOT ORTE AUS DEN EIGENEN BESUCHEN.
--
-- Wer ein Auktionshaus oeffnet, steht davor. In genau diesem Moment liefert
-- der Client Karte und Position - belegt, exakt, in der eigenen Stadt, auf der
-- eigenen Fraktion. Dasselbe gilt fuer Bank (BANKFRAME_OPENED), Briefkasten
-- (MAIL_SHOW), Berufsfenster (TRADE_SKILL_SHOW / CRAFT_SHOW) und Haendler
-- (MERCHANT_SHOW).
--
-- WAS DER CLIENT NICHT HERGIBT (und was deshalb UNKNOWN bleibt):
--   * Entfernungen ohne Weltkoordinaten. C_Map.GetWorldPosFromMapPos gibt es
--     nicht in jeder Clientfassung. Fehlt es, gibt es eine RICHTUNG, aber
--     keine Meterangabe - und dann steht auch keine da.
--   * Wegfindung. Ein Pfeil zeigt die Luftlinie. Ob eine Wand dazwischen
--     steht, weiss niemand.
--   * Orte, die der Spieler noch nie besucht hat. Dann bleibt es bei der
--     Textanweisung, und der Pfeil erscheint gar nicht erst.
--
-- TOMTOM ist optional. Ist es da, kann Gold Copilot einen Wegpunkt setzen;
-- fehlt es, bringt es seinen eigenen, sehr schlichten Pfeil mit. Vorausgesetzt
-- wird es nirgends.
-- ---------------------------------------------------------------------------

local function config()
    return GCP.Constants.NAVIGATION
end

Navigation.revision = 0
Navigation.current = nil          -- aktives Ziel
Navigation.lastUpdate = nil

local TWO_PI = math.pi * 2

-- WoW laeuft auf Lua 5.1 (math.atan2), das Testgeruest auf 5.3 (math.atan mit
-- zwei Argumenten). Beides bedeutet dasselbe; die Weiche steht genau hier.
local atan2 = math.atan2 or function(y, x) return math.atan(y, x) end

local function isCoordinate(value)
    return type(value) == "number" and value >= 0 and value <= 1
end

local function isMapID(value)
    return type(value) == "number" and value > 0 and value == math.floor(value)
end

-- ---------------------------------------------------------------------------
-- Speicher
--
--   db.locations = {
--       version = 1,
--       realms = {
--           ["Testrealm|Horde"] = {
--               ["AUCTION_HOUSE"] = {
--                   { m = 85, x = 0.54, y = 0.68, z = "Orgrimmar",
--                     n = "Auktionshaus", at = ..., v = 12 },
--               },
--           },
--       },
--   }
--
-- Getrennt je Realm UND Fraktion: Das Auktionshaus der Horde ist nicht das der
-- Allianz, und ein Realmwechsel soll die gelernten Orte nicht vermischen.
-- ---------------------------------------------------------------------------

function Navigation:RealmKey()
    local realm = (type(GetRealmName) == "function" and GetRealmName()) or "?"
    local faction = (type(UnitFactionGroup) == "function" and UnitFactionGroup("player"))
        or "?"
    return tostring(realm) .. "|" .. tostring(faction)
end

function Navigation:EnsureStore()
    local db = GCP.db
    if not db then return nil end
    local C = config()
    local store = db.locations
    if type(store) ~= "table" or store.version ~= C.STORE_VERSION then
        store = { version = C.STORE_VERSION, realms = {} }
        db.locations = store
    end
    if type(store.realms) ~= "table" then store.realms = {} end
    local key = self:RealmKey()
    if type(store.realms[key]) ~= "table" then store.realms[key] = {} end
    return store, store.realms[key]
end

function Navigation:Touch()
    self.revision = self.revision + 1
end

-- ---------------------------------------------------------------------------
-- Position des Spielers
-- ---------------------------------------------------------------------------

function Navigation:PlayerPosition()
    if type(C_Map) ~= "table" then return nil end
    local ok, mapID = pcall(C_Map.GetBestMapForUnit, "player")
    if not ok or not isMapID(mapID) then return nil end
    local okPos, position = pcall(C_Map.GetPlayerMapPosition, mapID, "player")
    if not okPos or type(position) ~= "table" then return nil end
    local x, y
    if type(position.GetXY) == "function" then
        local okXY, px, py = pcall(position.GetXY, position)
        if okXY then x, y = px, py end
    end
    if x == nil then x, y = position.x, position.y end
    if not isCoordinate(x) or not isCoordinate(y) then return nil end
    return mapID, x, y
end

function Navigation:ZoneName()
    if type(GetZoneText) == "function" then
        local ok, zone = pcall(GetZoneText)
        if ok and type(zone) == "string" and zone ~= "" then return zone end
    end
    return nil
end

-- ---------------------------------------------------------------------------
-- Lernen
-- ---------------------------------------------------------------------------

-- Zwei Orte gelten als derselbe, wenn sie auf derselben Karte weniger als
-- MERGE_DISTANCE Kartenanteile auseinanderliegen. Das Auktionshaus von
-- Orgrimmar hat drei Auktionatoren; das sind nicht drei Orte.
function Navigation:Learn(kind, key)
    if not GCP.Knowledge.LOCATION_KINDS[kind] then return false end
    local _, bucketRoot = self:EnsureStore()
    if not bucketRoot then return false end
    local mapID, x, y = self:PlayerPosition()
    if not mapID then return false end

    local C = config()
    local bucket = bucketRoot[kind]
    if type(bucket) ~= "table" then
        bucket = {}
        bucketRoot[kind] = bucket
    end

    local now = (type(time) == "function" and time()) or 0
    for _, entry in ipairs(bucket) do
        if entry.m == mapID and entry.k == key then
            local dx, dy = entry.x - x, entry.y - y
            if (dx * dx + dy * dy) <= (C.MERGE_DISTANCE * C.MERGE_DISTANCE) then
                -- Laufender Mittelwert ueber die Besuche: Ein Ort, den man
                -- zwanzigmal betreten hat, wird mit jedem Besuch genauer.
                local visits = (entry.v or 1) + 1
                entry.x = entry.x + (x - entry.x) / visits
                entry.y = entry.y + (y - entry.y) / visits
                entry.v = visits
                entry.at = now
                self:Touch()
                return true, entry, false
            end
        end
    end

    local entry = {
        m = mapID, x = x, y = y, k = key,
        z = self:ZoneName(), at = now, v = 1,
    }
    bucket[#bucket + 1] = entry
    while #bucket > C.MAX_PER_KIND do
        -- Der aelteste, am seltensten besuchte Ort faellt zuerst.
        local worst, worstIndex = nil, 1
        for index, candidate in ipairs(bucket) do
            local rank = (candidate.v or 1) * 1000000 + (candidate.at or 0) / 1000
            if worst == nil or rank < worst then worst, worstIndex = rank, index end
        end
        table.remove(bucket, worstIndex)
    end
    self:Touch()
    return true, entry, true
end

function Navigation:KnownCount(kind)
    local _, bucketRoot = self:EnsureStore()
    if not bucketRoot then return 0 end
    if kind then return #(bucketRoot[kind] or {}) end
    local total = 0
    for _, bucket in pairs(bucketRoot) do total = total + #bucket end
    return total
end

function Navigation:Forget(kind)
    local _, bucketRoot = self:EnsureStore()
    if not bucketRoot then return 0 end
    local removed = 0
    if kind then
        removed = #(bucketRoot[kind] or {})
        bucketRoot[kind] = nil
    else
        for name, bucket in pairs(bucketRoot) do
            removed = removed + #bucket
            bucketRoot[name] = nil
        end
    end
    self:Touch()
    return removed
end

-- ---------------------------------------------------------------------------
-- Nachschlagen
--
-- Reihenfolge: gelernte Orte auf der aktuellen Karte, dann gelernte Orte
-- anderswo, dann kuratierte Orte aus der Wissensbasis. Das ist Absicht - was
-- der Spieler selbst benutzt, schlaegt jede Liste.
-- ---------------------------------------------------------------------------

local function mapDistanceSquared(ax, ay, bx, by)
    local dx, dy = ax - bx, ay - by
    return dx * dx + dy * dy
end

function Navigation:FindLocation(kind, key)
    if not kind or kind == "ANYWHERE" then return nil end
    local _, bucketRoot = self:EnsureStore()
    local mapID, px, py = self:PlayerPosition()

    local best, bestScore, sameMap = nil, nil, false
    for _, entry in ipairs((bucketRoot and bucketRoot[kind]) or {}) do
        -- Ein Beruf ist nicht wie der andere: PROFESSION-Orte tragen den
        -- Berufsnamen als Schluessel und werden nur dann verwendet.
        local keyMatches = (key == nil) or (entry.k == key) or (entry.k == nil)
        if keyMatches then
            local onMap = mapID ~= nil and entry.m == mapID
            local distance = onMap and mapDistanceSquared(px, py, entry.x, entry.y) or 9
            -- Auf der eigenen Karte gewinnt die Naehe, sonst die Zahl der
            -- Besuche: Der Ort, den man am haeufigsten benutzt, ist der
            -- wahrscheinlichste.
            local score = onMap and (10 - distance) or ((entry.v or 1) / 1000)
            if bestScore == nil or score > bestScore then
                best, bestScore, sameMap = entry, score, onMap
            end
        end
    end
    if best then
        return {
            source = "learned",
            mapID = best.m, x = best.x, y = best.y,
            zone = best.z, key = best.k, visits = best.v,
            onCurrentMap = sameMap,
        }
    end

    for _, entry in ipairs(GCP.Knowledge:GetLocationsOfKind(kind)) do
        if key == nil or entry.key == key then
            -- Der Client ist die Instanz, die entscheidet, ob es die Karte
            -- gibt. Eine kuratierte MapID, die er nicht kennt, wird nicht zum
            -- Pfeil ins Nichts, sondern zu gar keinem Pfeil.
            local okMap = true
            if type(C_Map) == "table" and type(C_Map.GetMapInfo) == "function" then
                local ok, info = pcall(C_Map.GetMapInfo, entry.mapID)
                okMap = ok and type(info) == "table"
            end
            if okMap then
                return {
                    source = "knowledge",
                    mapID = entry.mapID, x = entry.x, y = entry.y,
                    zone = entry.zone, name = entry.name,
                    sourceConfidence = entry.sourceConfidence,
                    onCurrentMap = mapID ~= nil and entry.mapID == mapID,
                }
            end
        end
    end
    return nil
end

-- ---------------------------------------------------------------------------
-- Richtung und Entfernung
--
-- KOORDINATENSYSTEM: Kartenkoordinaten laufen von links oben (0,0) nach rechts
-- unten (1,1) - x waechst nach Osten, y nach SUEDEN. GetPlayerFacing liefert
-- die Blickrichtung im Bogenmass, 0 = Norden, gegen den Uhrzeigersinn wachsend.
--
-- Peilung des Ziels im Uhrzeigersinn ab Norden:  atan2(dx, -dy)
-- Blickrichtung im Uhrzeigersinn ab Norden:      -facing
-- Relative Richtung (0 = geradeaus):             atan2(dx, -dy) + facing
--
-- Entfernungen gibt es nur mit Weltkoordinaten. Ohne sie bleibt die Richtung
-- und die Entfernung ist nil - eine in Kartenanteilen gerechnete "Entfernung"
-- waere je nach Zonengroesse um den Faktor zehn daneben.
-- ---------------------------------------------------------------------------

function Navigation:WorldPosition(mapID, x, y)
    if type(C_Map) ~= "table" or type(C_Map.GetWorldPosFromMapPos) ~= "function" then
        return nil
    end
    local ok, continent, position = pcall(C_Map.GetWorldPosFromMapPos, mapID, { x = x, y = y })
    if not ok or type(position) ~= "table" then return nil end
    local wx, wy = position.x, position.y
    if type(wx) ~= "number" or type(wy) ~= "number" then return nil end
    return continent, wx, wy
end

function Navigation:DistanceYards(fromMap, fx, fy, toMap, tx, ty)
    local continentA, ax, ay = self:WorldPosition(fromMap, fx, fy)
    local continentB, bx, by = self:WorldPosition(toMap, tx, ty)
    if not ax or not bx then return nil end
    if continentA ~= continentB then return nil end
    local dx, dy = bx - ax, by - ay
    return math.sqrt(dx * dx + dy * dy)
end

function Navigation:Bearing(px, py, tx, ty)
    px, py = tonumber(px), tonumber(py)
    tx, ty = tonumber(tx), tonumber(ty)
    if not (px and py and tx and ty) then return nil end
    local dx, dy = tx - px, ty - py
    if dx == 0 and dy == 0 then return 0 end
    local bearing = atan2(dx, -dy)
    local facing = 0
    if type(GetPlayerFacing) == "function" then
        local ok, value = pcall(GetPlayerFacing)
        if ok and type(value) == "number" then facing = value end
    end
    local relative = bearing + facing
    while relative < 0 do relative = relative + TWO_PI end
    while relative >= TWO_PI do relative = relative - TWO_PI end
    return relative
end

-- Himmelsrichtung in Worten. Nur acht Stufen: "Nordnordost" hilft niemandem.
local COMPASS = { "vorwärts", "rechts voraus", "rechts", "rechts hinten",
    "zurück", "links hinten", "links", "links voraus" }

function Navigation:CompassText(relative)
    if type(relative) ~= "number" then return nil end
    local index = math.floor((relative + math.pi / 8) / (math.pi / 4)) % 8 + 1
    return COMPASS[index]
end

-- ---------------------------------------------------------------------------
-- Wegpunkt
-- ---------------------------------------------------------------------------

function Navigation:GetWaypoint(locationSpec)
    if type(locationSpec) ~= "table" then return nil end
    local kind = locationSpec.kind
    if not kind or kind == "ANYWHERE" then return nil end
    local found = self:FindLocation(kind, locationSpec.key)
    if not found then
        return nil, "unbekannt"
    end
    local mapID, px, py = self:PlayerPosition()
    local waypoint = {
        kind = kind,
        label = locationSpec.label or GCP.Knowledge.LOCATION_KIND_LABEL[kind] or kind,
        mapID = found.mapID, x = found.x, y = found.y,
        zone = found.zone, source = found.source,
        onCurrentMap = found.onCurrentMap,
    }
    waypoint.key = found.key or locationSpec.key
    if mapID then
        waypoint.distance = self:DistanceYards(mapID, px, py, found.mapID, found.x, found.y)
        if found.mapID == mapID then
            waypoint.relative = self:Bearing(px, py, found.x, found.y)
            waypoint.compass = self:CompassText(waypoint.relative)
            waypoint.arrived = mapDistanceSquared(px, py, found.x, found.y)
                <= (config().ARRIVED_DISTANCE * config().ARRIVED_DISTANCE)
        end
    end
    return waypoint
end

-- ---------------------------------------------------------------------------
-- WO STEHT DER SPIELER GERADE? (1.1.0-beta.5)
--
-- Der Routenplaner braucht diese Antwort, sonst beginnt jede Route - auch die
-- mitten im Auktionshaus neu geplante - mit "Gehe zu: Auktionshaus".
--
-- Geraten wird dabei nichts. Gefragt wird genau das, was ohnehin schon
-- gerechnet wird: Liegt einer der selbst besuchten Orte innerhalb der
-- Ankunftsentfernung? Dann steht der Spieler dort. Liegt keiner in Reichweite
-- - oder wurde noch keiner gelernt -, ist die Antwort nil, und der Planer
-- rechnet wie bisher mit einer unbekannten Ausgangslage.
--
-- Die Reihenfolge entscheidet Gleichstaende: In jeder Stadt liegen
-- Auktionshaus, Briefkasten und Bank dicht beieinander, und dann ist die
-- Aussage "du bist am Auktionshaus" die nuetzlichste - dort faengt jede Route
-- an.
-- ---------------------------------------------------------------------------

Navigation.PRESENCE_ORDER = {
    "AUCTION_HOUSE", "MAILBOX", "BANK", "VENDOR", "PROFESSION",
}

function Navigation:CurrentLocation()
    local _, bucketRoot = self:EnsureStore()
    if not bucketRoot then return nil end
    for _, kind in ipairs(self.PRESENCE_ORDER) do
        if bucketRoot[kind] and #bucketRoot[kind] > 0 then
            local waypoint = self:GetWaypoint({ kind = kind })
            if waypoint and waypoint.arrived then
                return {
                    kind = kind,
                    key = waypoint.key,
                    label = GCP.Knowledge.LOCATION_KIND_LABEL[kind] or kind,
                    zone = waypoint.zone,
                }
            end
        end
    end
    return nil
end

function Navigation:SetTarget(locationSpec)
    if locationSpec == nil then
        self.current = nil
        self:ClearTomTom()
        return nil
    end
    local waypoint, reason = self:GetWaypoint(locationSpec)
    self.current = waypoint
    self.currentSpec = locationSpec
    self.reason = reason
    if waypoint and GCP.db and GCP.db.options.navigationTomTom then
        self:SendToTomTom(waypoint)
    end
    return waypoint
end

function Navigation:Refresh()
    if not self.currentSpec then return nil end
    local now = (type(GetTime) == "function" and GetTime()) or 0
    if self.lastUpdate and (now - self.lastUpdate) < config().UPDATE_INTERVAL then
        return self.current
    end
    self.lastUpdate = now
    self.current = self:GetWaypoint(self.currentSpec)
    return self.current
end

function Navigation:FormatDistance(distance)
    distance = tonumber(distance)
    if not distance then return nil end
    if distance < 1000 then
        return string.format("%.0f m", distance)
    end
    return string.format("%.1f km", distance / 1000)
end

-- Der Satz, der unter dem Pfeil steht - und der ohne Pfeil an seine Stelle
-- tritt.
function Navigation:DescribeTarget(locationSpec, waypoint)
    if type(locationSpec) ~= "table" then locationSpec = nil end
    if type(waypoint) ~= "table" then waypoint = nil end
    local label = locationSpec and (locationSpec.label
        or GCP.Knowledge.LOCATION_KIND_LABEL[locationSpec.kind]) or "Ziel"
    if not waypoint then
        return label, "Gold Copilot kennt diesen Ort noch nicht – "
            .. "einmal hingehen genügt, danach zeigt der Pfeil dorthin."
    end
    local parts = {}
    if waypoint.zone then parts[#parts + 1] = waypoint.zone end
    if waypoint.distance then
        parts[#parts + 1] = self:FormatDistance(waypoint.distance)
    elseif not waypoint.onCurrentMap then
        parts[#parts + 1] = "andere Karte"
    end
    if waypoint.compass then parts[#parts + 1] = waypoint.compass end
    return label, table.concat(parts, " · ")
end

-- ---------------------------------------------------------------------------
-- TomTom (optional)
--
-- Vorausgesetzt wird nichts. Fehlt TomTom, passiert hier schlicht nichts, und
-- der eigene Pfeil bleibt die Anzeige.
-- ---------------------------------------------------------------------------

function Navigation:HasTomTom()
    return type(TomTom) == "table" and type(TomTom.AddWaypoint) == "function"
end

function Navigation:SendToTomTom(waypoint)
    if not self:HasTomTom() or not waypoint then return false end
    self:ClearTomTom()
    local ok, handle = pcall(TomTom.AddWaypoint, TomTom, waypoint.mapID,
        waypoint.x, waypoint.y, {
            title = "Gold Copilot: " .. (waypoint.label or "Ziel"),
            persistent = false,
            minimap = true,
            world = true,
        })
    if ok then
        self.tomtomHandle = handle
        return true
    end
    return false
end

function Navigation:ClearTomTom()
    if not self.tomtomHandle then return false end
    if type(TomTom) == "table" and type(TomTom.RemoveWaypoint) == "function" then
        pcall(TomTom.RemoveWaypoint, TomTom, self.tomtomHandle)
    end
    self.tomtomHandle = nil
    return true
end

-- ---------------------------------------------------------------------------
-- Ereignisse
--
-- Genau die fuenf Ereignisse, bei denen der Spieler nachweislich vor etwas
-- steht. Kein OnUpdate, kein Polling: Gelernt wird nur, wenn der Client selbst
-- sagt, dass ein Fenster aufgegangen ist.
-- ---------------------------------------------------------------------------

Navigation.LEARN_EVENTS = {
    AUCTION_HOUSE_SHOW = "AUCTION_HOUSE",
    BANKFRAME_OPENED = "BANK",
    MAIL_SHOW = "MAILBOX",
    MERCHANT_SHOW = "VENDOR",
    TRADE_SKILL_SHOW = "PROFESSION",
    CRAFT_SHOW = "PROFESSION",
}

function Navigation:OnEvent(event)
    local kind = self.LEARN_EVENTS[event]
    if not kind then return false end
    local key = nil
    if kind == "PROFESSION" then
        if event == "TRADE_SKILL_SHOW" and type(GetTradeSkillLine) == "function" then
            local ok, name = pcall(GetTradeSkillLine)
            if ok and type(name) == "string" and name ~= "" and name ~= "UNKNOWN" then
                key = name
            end
        elseif event == "CRAFT_SHOW" and type(GetCraftName) == "function" then
            local ok, name = pcall(GetCraftName)
            if ok and type(name) == "string" and name ~= "" then key = name end
        end
    end
    return self:Learn(kind, key)
end

function Navigation:InstallEvents()
    if self.eventFrame then return self.eventFrame end
    local frame = CreateFrame("Frame")
    for event in pairs(self.LEARN_EVENTS) do
        pcall(frame.RegisterEvent, frame, event)
    end
    frame:SetScript("OnEvent", function(_, event)
        if GCP.db then Navigation:OnEvent(event) end
    end)
    self.eventFrame = frame
    return frame
end
