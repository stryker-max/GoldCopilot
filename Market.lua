local addonName, GCP = ...

GCP.Market = {}
local Market = GCP.Market

local GetItemInfoCompat = (C_Item and C_Item.GetItemInfo) or GetItemInfo

-- ---------------------------------------------------------------------------
-- MARKET ENGINE (0.5.0)
--
-- Die Preishistorie aus 0.4.0 (db.priceHistory) haelt genau einen Preis je Item
-- und Kalendertag. Fuer "ist der Preis gerade gut?" reicht das nicht: Ein Tag
-- ist kein Markt, sondern eine Momentaufnahme mit Datumsstempel.
--
-- db.marketHistory speichert deshalb echte Zeitreihen mit mehreren Punkten pro
-- Tag. db.priceHistory bleibt unangetastet und versorgt weiterhin die
-- Planungspreise von Roadmap, Flips und Craft-Radar - dieses Modul liegt
-- daneben, nicht darueber.
--
-- SPEICHERFORMAT (bewusst nicht die naheliegende Liste aus Tabellen):
--
--   db.marketHistory = {
--       version  = 1,
--       epoch    = 1786000000,          -- Bezugszeitpunkt, Unix-Sekunden
--       items    = { [23425] = { 0, 50000, 31, 50100, 94, 49800 } },
--       source   = { [23425] = "A" },   -- A = Auctionator, T = TSM, H = Import
--       prunedAt = 1786003600,
--       imported = true,
--   }
--
-- items[itemID] ist eine flache Zahlenliste aus Paaren
-- (Minuten seit epoch, Preis in Kupfer), aufsteigend nach Zeit.
--
-- Warum flach statt { timestamp = ..., price = ... }? WoW schreibt
-- SavedVariables als Lua-Quelltext. Ein Eintrag als Tabelle mit Schluesseln
-- kostet rund 50 Zeichen, ein Zahlenpaar mit Minuten-Offset rund 13. Bei
-- 500 Items x 400 Snapshots sind das ~2,6 MB gegen ~260 KB - derselbe
-- Informationsgehalt, ein Zehntel der Datei.
--
-- Die Quelle steht je Item statt je Snapshot: Wer Auctionator benutzt, benutzt
-- ihn dauerhaft; ein Wechsel ist ein Ereignis, kein Merkmal jeder Messung.
-- Ein Kuerzel je Item kostet nichts, ein String je Snapshot verdoppelt die Datei.
--
-- OBERGRENZE: MAX_TRACKED_ITEMS (500) x MAX_SNAPSHOTS_PER_ITEM (400) Paare,
-- zusaetzlich begrenzt durch RETENTION_DAYS (30) und SNAPSHOT_INTERVAL (30 min).
-- ---------------------------------------------------------------------------

-- Laufzeitzustand. Gehoert bewusst nicht in die SavedVariables: Caches muessen
-- einen Reload nicht ueberleben, und ein kaputter Cache waere sonst dauerhaft.
Market.statsCache = {}
Market.trackedCache = nil
Market.trackedCachedAt = nil
Market.trackedReasons = {}
Market.registered = {}
Market.overviewCache = nil
Market.bytesCache = nil
Market.lastRecordAt = nil
Market.callbackRegistered = false
Market.flushScheduled = false
Market.pendingReason = nil

-- Zaehler fuer alles, was die Datenlage tatsaechlich veraendert: geschriebene
-- Snapshots, weggeraeumte Punkte, ein Reset, An- und Abmeldungen. Die
-- Opportunity Engine haengt ihren Cache daran, statt bei jedem Refresh alle
-- Reihen neu durchzurechnen. Bewusst Laufzeitzustand: Nach einem Reload ist er
-- 0, und ein leerer Cache ist danach ohnehin richtig.
Market.revision = 0

function Market:Touch()
    self.revision = (self.revision or 0) + 1
end

local SOURCE_CODES = {
    ["Auctionator"] = "A",
    ["TSM"] = "T",
    ["A"] = "A", ["T"] = "T", ["H"] = "H",
}

local SOURCE_LABELS = {
    A = "Auctionator",
    T = "TSM (dbmarket)",
    H = "aus der 0.4-Preishistorie übernommen",
}

local function marketConfig()
    return GCP.Constants.MARKET
end

function Market:Now()
    if type(time) == "function" then
        local ok, now = pcall(time)
        if ok and type(now) == "number" then return now end
    end
    return 0
end

-- ---------------------------------------------------------------------------
-- Speicher
-- ---------------------------------------------------------------------------

-- Legt den Speicher an oder verwirft ihn, wenn er aus einer unbekannten
-- Formatversion stammt. Verworfen wird ausschliesslich db.marketHistory -
-- Goldverlauf, Preishistorie, Rezepte und Optionen bleiben unberuehrt.
function Market:EnsureStore()
    local db = GCP.db
    if not db then return nil end
    local M = marketConfig()
    local profile = GCP:Profile()
    local store = profile.marketHistory
    if type(store) ~= "table"
        or type(store.items) ~= "table"
        or type(store.epoch) ~= "number"
        or store.version ~= M.STORE_VERSION then
        store = {
            version = M.STORE_VERSION,
            epoch = self:Now(),
            items = {},
            source = {},
        }
        profile.marketHistory = store
        self:InvalidateCaches()
        self:InvalidateTrackedCache()
        self:Touch()
    end
    if type(store.source) ~= "table" then store.source = {} end
    return store
end

function Market:InvalidateCaches()
    self.statsCache = {}
    self.overviewCache = nil
    self.bytesCache = nil
end

function Market:InvalidateTrackedCache()
    self.trackedCache = nil
    self.trackedCachedAt = nil
    self.overviewCache = nil
end

-- Der Bezugszeitpunkt darf nie hinter dem aeltesten Datenpunkt liegen, sonst
-- werden Minuten-Offsets negativ. Beim Verschieben wandern alle Offsets mit;
-- die Rechnung ist exakt, weil nur ganze Minuten verschoben werden.
function Market:RebaseEpoch(store, newEpoch)
    if type(newEpoch) ~= "number" then return end
    local deltaMinutes = math.floor((store.epoch - newEpoch) / 60)
    if deltaMinutes == 0 then return end
    for _, series in pairs(store.items) do
        for i = 1, #series, 2 do
            series[i] = series[i] + deltaMinutes
        end
    end
    store.epoch = store.epoch - deltaMinutes * 60
end

local function seriesTimestamp(store, minute)
    return store.epoch + minute * 60
end

-- ---------------------------------------------------------------------------
-- Snapshots
-- ---------------------------------------------------------------------------

-- Ein Preis ist nur dann einer, wenn er eine positive, endliche Zahl in
-- vernuenftiger Groessenordnung ist. nil, 0, negative Werte, NaN, unendlich
-- und alles Nicht-Numerische werden verworfen, nicht gespeichert.
function Market:NormalizePrice(price)
    if type(price) ~= "number" then return nil end
    if price ~= price then return nil end            -- NaN
    local M = marketConfig()
    if price < M.MIN_PRICE or price > M.MAX_PRICE then return nil end
    return math.floor(price + 0.5)
end

function Market:SnapshotCount(itemID)
    local store = self:EnsureStore()
    local series = store and store.items[itemID]
    if not series then return 0 end
    return math.floor(#series / 2)
end

-- Letzter gespeicherter Punkt eines Items: Zeitstempel und Preis, sonst nil.
function Market:LastSnapshot(itemID)
    local store = self:EnsureStore()
    local series = store and store.items[itemID]
    if not series or #series < 2 then return nil end
    local count = #series
    return seriesTimestamp(store, series[count - 1]), series[count]
end

-- Schreibt einen Messpunkt, sofern er neu genug Information traegt.
-- Rueckgabe: true, wenn geschrieben wurde.
--
-- Drei Filter, in dieser Reihenfolge:
--   1. Ungueltige Preise fliegen raus.
--   2. SNAPSHOT_INTERVAL (30 min): mehr Aufloesung braucht kein Mensch, und
--      Auctionator scannt ohnehin nicht oefter sinnvoll.
--   3. IDENTICAL_SKIP (2 h): Ist der Preis exakt derselbe wie zuletzt, ist der
--      zweite Punkt keine neue Information, sondern nur Dateigroesse. Nach zwei
--      Stunden wird trotzdem geschrieben, damit ein flacher Markt nicht wie eine
--      Datenluecke aussieht.
function Market:AddSnapshot(itemID, price, now, source)
    if type(itemID) ~= "number" or itemID <= 0 or itemID ~= math.floor(itemID) then
        return false
    end
    price = self:NormalizePrice(price)
    if not price then return false end

    local store = self:EnsureStore()
    if not store then return false end
    now = now or self:Now()
    local M = marketConfig()

    -- Uhr zurueckgestellt oder Import aelterer Daten: Bezugspunkt mitziehen.
    if now < store.epoch then
        self:RebaseEpoch(store, now)
    end

    local series = store.items[itemID]
    if series then
        local count = #series
        if count >= 2 then
            local lastTime = seriesTimestamp(store, series[count - 1])
            local age = now - lastTime
            if age < M.SNAPSHOT_INTERVAL then return false end
            if price == series[count] and age < M.IDENTICAL_SKIP then return false end
        end
    else
        series = {}
        store.items[itemID] = series
        self:InvalidateTrackedCache()
    end

    local minute = math.floor((now - store.epoch) / 60)
    local count = #series
    if count >= 2 and minute <= series[count - 1] then
        -- Zwei Messungen in derselben Minute oder eine ruckelnde Uhr: die
        -- Reihenfolge der Reihe ist wichtiger als die exakte Minute.
        minute = series[count - 1] + 1
    end
    series[count + 1] = minute
    series[count + 2] = price

    -- Harte Obergrenze je Item; der aelteste Punkt faellt zuerst.
    local maxEntries = M.MAX_SNAPSHOTS_PER_ITEM * 2
    while #series > maxEntries do
        table.remove(series, 1)
        table.remove(series, 1)
    end

    local code = SOURCE_CODES[source]
    if code then store.source[itemID] = code end

    self.statsCache[itemID] = nil
    self.overviewCache = nil
    self.bytesCache = nil
    self:Touch()
    return true
end

-- Voller Durchlauf ueber alle beobachteten Items. Gedrosselt auf einen Lauf je
-- RECORD_INTERVAL, damit weder ein Auctionator-Scan noch haeufiges Oeffnen des
-- Fensters die Preisquelle hunderte Male befragt.
function Market:RecordSnapshots(reason, force)
    local store = self:EnsureStore()
    if not store then return 0 end
    local now = self:Now()
    local M = marketConfig()
    if not force and self.lastRecordAt
        and (now - self.lastRecordAt) < M.RECORD_INTERVAL then
        return 0
    end
    self.lastRecordAt = now

    local written = 0
    for _, itemID in ipairs(self:GetTrackedItems()) do
        local price, source = GCP.Prices:GetMarketPrice(itemID)
        if self:AddSnapshot(itemID, price, now, source) then
            written = written + 1
        end
    end
    -- Beobachtungspunkte fuer die spaetere Selbstpruefung des Scores. Sie
    -- laufen bewusst hier mit: Zu diesem Zeitpunkt sind die Preise gerade
    -- frisch geschrieben, und ein zweiter Durchlauf ueber alle Items waere
    -- Verschwendung.
    self:RecordScoreProbes(now)
    self:Prune(now)
    if written > 0 then
        self.overviewCache = nil
    end
    return written
end

-- ---------------------------------------------------------------------------
-- MARKET-SCORE-SONDE (1.0.0-beta.10)
--
-- Die unbequemste Frage an das eigene Modell lautet nicht "war die Chance gut",
-- sondern:
--
--     "Was ist eigentlich passiert, NACHDEM der Market Score hoch war?"
--
-- Das Chancen-Protokoll kann das nicht beantworten. Es kennt nur Chancen, denen
-- der Spieler gefolgt ist - und misst damit seine Auswahl mit, nicht das
-- Modell. Ein Score, der nur dann geprueft wird, wenn jemand gekauft hat, ist
-- nicht geprueft.
--
-- Deshalb hier ein reiner Beobachtungspunkt, voellig unabhaengig vom Handeln:
-- Item, Zeit, Score, Preis. Was daraus wurde, steht ohnehin schon in der
-- Preisreihe; die Sonde ist nur der Merkzettel, wo nachzuschauen ist.
--
-- Sie veraendert KEINE Bewertung, erzeugt KEINE Empfehlung und fliesst in
-- KEINE Kalibrierung. Sie beantwortet eine Frage, die sonst niemand stellt.
--
--   profile.marketProbes = {
--       version = 1,
--       epoch = 1786000000,
--       points = { itemID, minute, score, preis, ... },   -- Schrittweite 4
--   }
-- ---------------------------------------------------------------------------

local PROBE_STRIDE = 4

local function probeConfig()
    return marketConfig().PROBE
end

function Market:EnsureProbeStore()
    local db = GCP.db
    if not db then return nil end
    local P = probeConfig()
    local profile = GCP:Profile()
    local store = profile.marketProbes
    if type(store) ~= "table" or store.version ~= P.STORE_VERSION
        or type(store.points) ~= "table" or type(store.epoch) ~= "number" then
        store = { version = P.STORE_VERSION, epoch = self:Now(), points = {} }
        profile.marketProbes = store
    end
    return store
end

function Market:ResetProbes()
    local db = GCP.db
    if not db then return false end
    GCP:Profile().marketProbes = nil
    self:EnsureProbeStore()
    return true
end

-- Letzter Beobachtungszeitpunkt je Item, in einem Durchgang. Ein Aufruf je
-- Item waere quadratisch: 500 Items gegen 600 Punkte sind 300000 Vergleiche
-- fuer eine Frage, die sich in einem Durchlauf beantworten laesst.
function Market:LastProbeByItem(store)
    local last = {}
    if type(store) ~= "table" then store = self:EnsureProbeStore() end
    if type(store) ~= "table" or type(store.points) ~= "table"
        or type(store.epoch) ~= "number" then
        return last
    end
    local points = store.points
    for index = 1, #points - PROBE_STRIDE + 1, PROBE_STRIDE do
        local itemID = points[index]
        local stamp = store.epoch + points[index + 1] * 60
        if last[itemID] == nil or stamp > last[itemID] then
            last[itemID] = stamp
        end
    end
    return last
end

function Market:RecordScoreProbes(now)
    local store = self:EnsureProbeStore()
    if not store then return 0 end
    local P = probeConfig()
    now = tonumber(now) or self:Now()
    local last = self:LastProbeByItem(store)
    local written = 0
    for _, itemID in ipairs(self:GetTrackedItems()) do
        if written >= P.MAX_PER_RUN then break end
        -- Das Zeitfenster wird VOR der Statistik geprueft. Andersherum waere
        -- der teure Teil (sortieren ueber bis zu 400 Preispunkte) auch dann
        -- faellig, wenn der Punkt anschliessend gar nicht geschrieben wird -
        -- und dieser Durchlauf haengt an einem Ereignis mitten im Spiel.
        local previous = last[itemID]
        if not previous or (now - previous) >= P.MIN_INTERVAL then
            local stats = self:GetStats(itemID)
            -- Ohne Score gibt es nichts zu pruefen. Das ist kein Mangel: Ein
            -- Item ohne Historie hat auch keine Vorhersage abgegeben.
            if stats and stats.score and stats.current and stats.current > 0 then
                local points = store.points
                points[#points + 1] = itemID
                points[#points + 1] = math.floor((now - store.epoch) / 60)
                points[#points + 1] = stats.score
                points[#points + 1] = stats.current
                written = written + 1
            end
        end
    end
    if written > 0 then self:PruneProbes(now) end
    return written
end

function Market:PruneProbes(now)
    local store = self:EnsureProbeStore()
    if not store then return 0 end
    local P = probeConfig()
    now = tonumber(now) or self:Now()
    local cutoff = now - P.RETENTION_DAYS * 86400
    local points = store.points

    local kept = {}
    for index = 1, #points - PROBE_STRIDE + 1, PROBE_STRIDE do
        local stamp = store.epoch + points[index + 1] * 60
        if stamp >= cutoff then
            for offset = 0, PROBE_STRIDE - 1 do
                kept[#kept + 1] = points[index + offset]
            end
        end
    end
    -- Deckel: die aeltesten Punkte fallen zuerst.
    local overflow = (#kept / PROBE_STRIDE) - P.MAX_ENTRIES
    if overflow > 0 then
        local trimmed = {}
        for index = overflow * PROBE_STRIDE + 1, #kept do
            trimmed[#trimmed + 1] = kept[index]
        end
        kept = trimmed
    end

    local removed = (#points - #kept) / PROBE_STRIDE
    if removed > 0 then
        for index = #points, 1, -1 do points[index] = nil end
        for index = 1, #kept do points[index] = kept[index] end
    end
    return removed
end

-- Alle Beobachtungspunkte als Tabellen. Bewusst eine eigene Funktion: Der
-- flache Zahlenspeicher spart Platz, aber niemand soll ausserhalb dieses
-- Moduls mit Schrittweiten rechnen muessen.
function Market:GetProbes()
    local store = self:EnsureProbeStore()
    if not store then return {} end
    local list = {}
    local points = store.points
    for index = 1, #points - PROBE_STRIDE + 1, PROBE_STRIDE do
        list[#list + 1] = {
            itemID = points[index],
            timestamp = store.epoch + points[index + 1] * 60,
            score = points[index + 2],
            price = points[index + 3],
        }
    end
    return list
end

-- Der Preis eines Items zu einem Zeitpunkt, gesucht in der eigenen Preisreihe.
-- Rueckgabe: Preis und die tatsaechliche Abweichung vom gewuenschten Zeitpunkt
-- in Sekunden - oder nil, wenn es dort keinen Messpunkt gibt.
--
-- Genommen wird der ERSTE Punkt ab dem Zielzeitpunkt, nicht der naechstgelegene:
-- Ein Punkt davor wuesste nichts von dem, was danach passiert ist.
function Market:PriceAt(itemID, timestamp)
    timestamp = tonumber(timestamp)
    if type(itemID) ~= "number" or not timestamp then return nil end
    local store = self:EnsureStore()
    local series = store and store.items[itemID]
    if not series then return nil end
    for index = 1, #series - 1, 2 do
        local stamp = seriesTimestamp(store, series[index])
        if stamp >= timestamp then
            return series[index + 1], stamp - timestamp
        end
    end
    return nil
end

-- Entfernt alles aelter als RETENTION_DAYS und schiebt den Bezugszeitpunkt
-- hinter den aeltesten verbliebenen Punkt - so bleiben die gespeicherten
-- Minuten-Offsets fuenfstellig statt mit den Jahren zu wachsen.
function Market:Prune(now, force)
    local store = self:EnsureStore()
    if not store then return 0 end
    local M = marketConfig()
    now = now or self:Now()
    if not force and type(store.prunedAt) == "number"
        and (now - store.prunedAt) < M.PRUNE_INTERVAL then
        return 0
    end
    store.prunedAt = now

    local cutoffMinute = math.floor((now - M.RETENTION_DAYS * 86400 - store.epoch) / 60)
    local removed = 0
    local oldestMinute = nil
    for itemID, series in pairs(store.items) do
        local first = 1
        while first + 1 <= #series and series[first] < cutoffMinute do
            first = first + 2
        end
        if first > 1 then
            removed = removed + math.floor((first - 1) / 2)
            local kept = {}
            for i = first, #series do
                kept[#kept + 1] = series[i]
            end
            series = kept
            if #kept > 0 then
                store.items[itemID] = kept
            else
                store.items[itemID] = nil
                store.source[itemID] = nil
            end
            self.statsCache[itemID] = nil
        end
        if #series >= 2 and (oldestMinute == nil or series[1] < oldestMinute) then
            oldestMinute = series[1]
        end
    end

    if oldestMinute and oldestMinute > 0 then
        self:RebaseEpoch(store, seriesTimestamp(store, oldestMinute))
    end
    if removed > 0 then
        self:InvalidateTrackedCache()
        self.overviewCache = nil
        self.bytesCache = nil
        self:Touch()
    end
    return removed
end

-- Loescht ausschliesslich die neue Markthistorie. Alles andere in
-- GoldCopilotDB - Optionen, Goldverlauf, priceHistory, Rezepte, Questgold -
-- bleibt unangetastet.
function Market:Reset()
    local db = GCP.db
    if not db then return 0 end
    local profile = GCP:Profile()
    local snapshots = 0
    local store = profile.marketHistory
    if type(store) == "table" and type(store.items) == "table" then
        for _, series in pairs(store.items) do
            snapshots = snapshots + math.floor(#series / 2)
        end
    end
    profile.marketHistory = nil
    self.lastRecordAt = nil
    self:InvalidateCaches()
    self:InvalidateTrackedCache()
    self:Touch()
    self:EnsureStore()
    -- Nicht erneut importieren: Der Nutzer wollte die Markthistorie leer haben.
    local fresh = profile.marketHistory
    if fresh then fresh.imported = true end
    return snapshots
end

-- ---------------------------------------------------------------------------
-- Uebernahme der 0.4-Preishistorie
--
-- db.priceHistory haelt echte, auf diesem Realm beobachtete Preise - nur eben
-- ohne Uhrzeit. Sie wegzuwerfen waere Datenvernichtung, sie zu erfinden kommt
-- nicht in Frage: Uebernommen wird der gespeicherte Preis unveraendert, als
-- genau ein Messpunkt um 12 Uhr mittags des jeweiligen Kalendertages, markiert
-- mit der Quelle "H". Der Preis ist echt, die Uhrzeit ist erklaertermassen
-- gesetzt - deshalb steht das so im README.
-- ---------------------------------------------------------------------------

local function noonOf(day)
    if type(day) ~= "string" then return nil end
    local year, month, dayOfMonth = day:match("^(%d%d%d%d)%-(%d%d)%-(%d%d)$")
    if not year then return nil end
    local ok, stamp = pcall(time, {
        year = tonumber(year), month = tonumber(month),
        day = tonumber(dayOfMonth), hour = 12, min = 0, sec = 0,
    })
    if ok and type(stamp) == "number" then return stamp end
    return nil
end

function Market:ImportLegacyHistory()
    local db = GCP.db
    if not db then return 0 end
    local store = self:EnsureStore()
    if not store or store.imported then return 0 end
    store.imported = true

    local history = GCP:Profile().priceHistory
    if type(history) ~= "table" then return 0 end

    local points = {}
    for itemID, days in pairs(history) do
        if type(itemID) == "number" and type(days) == "table" then
            for day, price in pairs(days) do
                local stamp = noonOf(day)
                local value = self:NormalizePrice(price)
                if stamp and value then
                    points[#points + 1] = { stamp, itemID, value }
                end
            end
        end
    end
    if #points == 0 then return 0 end

    table.sort(points, function(a, b)
        if a[1] ~= b[1] then return a[1] < b[1] end
        return a[2] < b[2]
    end)
    -- Einmal auf den aeltesten Punkt umbasieren, statt bei jedem Einfuegen.
    if points[1][1] < store.epoch then
        self:RebaseEpoch(store, points[1][1])
    end

    local imported = 0
    for _, point in ipairs(points) do
        if self:AddSnapshot(point[2], point[3], point[1], "H") then
            imported = imported + 1
        end
    end
    self:Prune(self:Now(), true)
    return imported
end

-- ---------------------------------------------------------------------------
-- Beobachtete Items
--
-- Es waere technisch moeglich, jedes Item der Scherbenwelt mitzuschreiben, und
-- fachlich sinnlos: Der Nutzer handelt mit ein paar Dutzend Maerkten, nicht mit
-- zwanzigtausend. Beobachtet wird deshalb genau das, womit Gold Copilot ohnehin
-- rechnet, plus was im Bestand liegt, plus was bereits Historie hat.
--
-- Andere Module haengen sich mit Market:RegisterItem(itemID, reason) ein - so
-- kann eine spaetere Future-Market-Watchlist ihre Items beisteuern, ohne dass
-- dieses Modul sie kennen muss.
-- ---------------------------------------------------------------------------

local REASON_PRIORITY = {
    ["Watchlist"] = 0,
    ["Rezept"] = 1,
    ["Flip"] = 1,
    ["Farmziel"] = 1,
    -- Items der Wissensbasis (0.7.0). Sie stehen weit vorn, weil ihre Historie
    -- gebraucht wird, bevor die Phase da ist - wer erst am Releasetag anfaengt
    -- zu messen, hat nichts zu vergleichen.
    ["Zukunft"] = 1,
    ["Historie"] = 2,
    ["Bestand"] = 3,
}

local DEFAULT_PRIORITY = 2

local function isItemID(itemID)
    return type(itemID) == "number" and itemID > 0 and itemID == math.floor(itemID)
end

function Market:RegisterItem(itemID, reason)
    if not isItemID(itemID) then return false end
    reason = type(reason) == "string" and reason or "Watchlist"
    if self.registered[itemID] == reason then return false end
    self.registered[itemID] = reason
    self:InvalidateTrackedCache()
    self:Touch()
    return true
end

function Market:UnregisterItem(itemID)
    if self.registered[itemID] == nil then return false end
    self.registered[itemID] = nil
    self:InvalidateTrackedCache()
    self:Touch()
    return true
end

-- ---------------------------------------------------------------------------
-- Watchlist (0.6.0)
--
-- Market:RegisterItem lebt nur zur Laufzeit - ein Modul meldet beim Laden an,
-- was es braucht. Die Watchlist ist das Gegenstueck fuer den Nutzer: Sie steht
-- in db.watchlist, ueberlebt den Reload und ist die Grundlage fuer Future
-- Market 0.7. Beobachtete Items landen mit hoechster Prioritaet in
-- GetTrackedItems() - wer ein Item bewusst beobachtet, will seine Reihe auch
-- dann behalten, wenn es weder im Bestand liegt noch in einem Rezept vorkommt.
--
--   db.watchlist = { [itemID] = { reason = "...", addedAt = 1786000000 } }
--
-- 0.7.0 ergaenzt vier optionale Felder, mehr nicht: phase, thesis, targetEntry
-- und notes. Ein Eintrag aus 0.6 kennt sie nicht und funktioniert unveraendert
-- weiter - die Watchlist wird erweitert, nicht ersetzt.
--
--   db.watchlist = { [itemID] = {
--       reason = "future", addedAt = 1786000000,
--       phase = "phase3", thesis = "Epic Gem dependency",
--       targetEntry = 204000, notes = "...",
--   } }
-- ---------------------------------------------------------------------------

-- Uebernimmt die optionalen Zusatzfelder. Bewusst eine feste Liste: Was hier
-- nicht steht, landet auch nicht in den SavedVariables.
local WATCH_META_FIELDS = { "phase", "thesis", "targetEntry", "notes" }

local function applyWatchMeta(entry, meta)
    if type(meta) ~= "table" then return false end
    local changed = false
    for _, field in ipairs(WATCH_META_FIELDS) do
        local value = meta[field]
        if value ~= nil and entry[field] ~= value then
            entry[field] = value
            changed = true
        end
    end
    return changed
end

function Market:EnsureWatchlist()
    local db = GCP.db
    if not db then return nil end
    local profile = GCP:Profile()
    if type(profile.watchlist) ~= "table" then profile.watchlist = {} end
    return profile.watchlist
end

function Market:IsWatched(itemID)
    local watchlist = self:EnsureWatchlist()
    return (watchlist and type(watchlist[itemID]) == "table") and true or false
end

function Market:GetWatchEntry(itemID)
    local watchlist = self:EnsureWatchlist()
    return watchlist and watchlist[itemID] or nil
end

function Market:CountWatchItems()
    local watchlist = self:EnsureWatchlist()
    local count = 0
    for _ in pairs(watchlist or {}) do count = count + 1 end
    return count
end

-- Rueckgabe: true, wenn das Item neu aufgenommen wurde. Ein bereits
-- beobachtetes Item bekommt hoechstens eine neue Begruendung; der Zeitpunkt der
-- Aufnahme bleibt stehen, damit spaetere Auswertungen wissen, seit wann.
function Market:RegisterWatchItem(itemID, reason, meta)
    if not isItemID(itemID) then return false end
    local watchlist = self:EnsureWatchlist()
    if not watchlist then return false end
    local existing = watchlist[itemID]
    if type(existing) == "table" then
        if type(reason) == "string" and reason ~= "" and existing.reason ~= reason then
            existing.reason = reason
        end
        applyWatchMeta(existing, meta)
        return false
    end
    if self:CountWatchItems() >= marketConfig().MAX_WATCH_ITEMS then
        return false, "voll"
    end
    local entry = {
        reason = (type(reason) == "string" and reason ~= "") and reason or "manuell",
        addedAt = self:Now(),
    }
    applyWatchMeta(entry, meta)
    watchlist[itemID] = entry
    self:InvalidateTrackedCache()
    self:Touch()
    return true
end

-- Ergaenzt die Zusatzfelder eines bereits beobachteten Items. Rueckgabe true,
-- wenn sich etwas geaendert hat.
function Market:UpdateWatchMeta(itemID, meta)
    local entry = self:GetWatchEntry(itemID)
    if type(entry) ~= "table" then return false end
    local changed = applyWatchMeta(entry, meta)
    if changed then self:Touch() end
    return changed
end

function Market:RemoveWatchItem(itemID)
    local watchlist = self:EnsureWatchlist()
    if not watchlist or watchlist[itemID] == nil then return false end
    watchlist[itemID] = nil
    self:InvalidateTrackedCache()
    self:Touch()
    return true
end

function Market:ToggleWatchItem(itemID, reason, meta)
    if self:IsWatched(itemID) then
        self:RemoveWatchItem(itemID)
        return false
    end
    self:RegisterWatchItem(itemID, reason, meta)
    return self:IsWatched(itemID)
end

-- Beobachtete Items als sortierte Liste, juengste Aufnahme zuerst.
function Market:GetWatchlist()
    local watchlist = self:EnsureWatchlist()
    local list = {}
    for itemID, entry in pairs(watchlist or {}) do
        if isItemID(itemID) and type(entry) == "table" then
            local row = {
                itemID = itemID,
                reason = entry.reason,
                addedAt = entry.addedAt,
            }
            -- Zusatzfelder aus 0.7.0, sofern vorhanden. Ein Eintrag aus 0.6 hat
            -- sie nicht und bleibt deshalb genau so, wie er war.
            for _, field in ipairs(WATCH_META_FIELDS) do
                row[field] = entry[field]
            end
            list[#list + 1] = row
        end
    end
    table.sort(list, function(a, b)
        if (a.addedAt or 0) ~= (b.addedAt or 0) then
            return (a.addedAt or 0) > (b.addedAt or 0)
        end
        return a.itemID < b.itemID
    end)
    return list
end

function Market:GetTrackReason(itemID)
    self:GetTrackedItems()
    return self.trackedReasons[itemID]
end

-- Sammelt die beobachteten Items mit Begruendung. Erster Treffer gewinnt,
-- deshalb ist die Reihenfolge der Bloecke die Rangfolge der Begruendungen.
function Market:BuildTrackedItems()
    local C = GCP.Constants
    local reasons = {}
    local list = {}

    local function add(itemID, reason)
        if type(itemID) ~= "number" or itemID <= 0 then return end
        if reasons[itemID] then return end
        reasons[itemID] = reason
        list[#list + 1] = itemID
    end

    -- 1. Die Watchlist des Nutzers. Sie steht vor allem anderen: Wer ein Item
    --    bewusst beobachtet, soll seine Reihe behalten, auch wenn der Deckel
    --    greift.
    for _, entry in ipairs(self:GetWatchlist()) do
        add(entry.itemID, "Watchlist")
    end

    -- 2. Ausdruecklich angemeldete Items anderer Module.
    for itemID, reason in pairs(self.registered) do
        add(itemID, reason)
    end

    -- 3. Womit Gold Copilot rechnet: Farmziele, Flips, Rezepte.
    for _, farm in ipairs(C.FARM_CATALOG) do add(farm.item, "Farmziel") end
    for _, pair in ipairs(C.PRIMALS) do
        add(pair.mote, "Flip"); add(pair.primal, "Flip")
    end
    for _, pair in ipairs(C.ESSENCES) do
        add(pair.lesser, "Flip"); add(pair.greater, "Flip")
    end
    for _, craft in ipairs(C.CRAFT_COOLDOWNS) do
        add(craft.product, "Rezept")
        for _, mat in ipairs(craft.mats) do add(mat[1], "Rezept") end
    end
    if GCP.Crafts then
        local ok, recipes = pcall(GCP.Crafts.AllRecipes, GCP.Crafts)
        if ok and type(recipes) == "table" then
            for _, recipe in ipairs(recipes) do
                add(recipe.product, "Rezept")
                for _, mat in ipairs(recipe.mats or {}) do add(mat[1], "Rezept") end
            end
        end
    end

    -- 4. Was bereits Historie hat, bleibt beobachtet - sonst reisst die Reihe ab,
    --    sobald ein Item einmal nicht mehr im Bestand liegt.
    local store = self:EnsureStore()
    if store then
        for itemID in pairs(store.items) do add(itemID, "Historie") end
    end

    -- 5. Der eigene Bestand, aber nur was das AH ueberhaupt annimmt: graue
    --    Qualitaet und gebundene Ausruestung haben keinen Markt.
    if GCP.Inventory then
        local ok, inventory = pcall(GCP.Inventory.ScanAccount, GCP.Inventory)
        if ok and type(inventory) == "table" then
            for itemID, entry in pairs(inventory) do
                if not entry.bound and GCP.Prices:IsAuctionable(itemID) then
                    add(itemID, "Bestand")
                end
            end
        end
    end

    -- Deckel. Faellt er, fallen zuerst Bestandsitems - Farmziele, Rezepte und
    -- bestehende Reihen sind die Maerkte, um die es geht.
    local M = marketConfig()
    if #list > M.MAX_TRACKED_ITEMS then
        table.sort(list, function(a, b)
            local pa = REASON_PRIORITY[reasons[a]] or DEFAULT_PRIORITY
            local pb = REASON_PRIORITY[reasons[b]] or DEFAULT_PRIORITY
            if pa ~= pb then return pa < pb end
            return a < b
        end)
        for index = #list, M.MAX_TRACKED_ITEMS + 1, -1 do
            reasons[list[index]] = nil
            list[index] = nil
        end
    end

    return list, reasons
end

function Market:GetTrackedItems()
    local now = self:Now()
    local M = marketConfig()
    if self.trackedCache and self.trackedCachedAt
        and (now - self.trackedCachedAt) < M.TRACKED_CACHE_SECONDS then
        return self.trackedCache
    end
    local list, reasons = self:BuildTrackedItems()
    self.trackedCache = list
    self.trackedReasons = reasons
    self.trackedCachedAt = now
    return list
end

-- ---------------------------------------------------------------------------
-- Statistik. Bewusst ohne externe Bibliothek: Median, Quantil und Perzentil
-- sind zwanzig Zeilen, und eine eingebundene Fremdbibliothek waere in einem
-- Addon-Ordner eine Wartungslast ohne Gegenwert.
-- ---------------------------------------------------------------------------

-- Quantil mit linearer Interpolation zwischen den Nachbarn (Typ 7, wie R und
-- numpy). Erwartet eine aufsteigend sortierte Liste.
local function quantile(sorted, q)
    local n = #sorted
    if n == 0 then return nil end
    if n == 1 then return sorted[1] end
    local position = 1 + (n - 1) * q
    local lower = math.floor(position)
    local upper = math.ceil(position)
    if lower == upper then return sorted[lower] end
    local weight = position - lower
    return sorted[lower] + (sorted[upper] - sorted[lower]) * weight
end

local function medianOf(sorted)
    local value = quantile(sorted, 0.5)
    if not value then return nil end
    return math.floor(value + 0.5)
end

-- Perzentil des aktuellen Preises in der eigenen Verteilung, nach der
-- Mittelrang-Methode: gleich grosse Werte zaehlen halb. Ohne diese Haelfte
-- stuende ein voellig flacher Markt bei Perzentil 0 ("historisch spottbillig"),
-- obwohl der Preis exakt seinem Normalwert entspricht - mit ihr steht er bei 50.
local function percentileOf(sorted, value)
    local n = #sorted
    if n == 0 or type(value) ~= "number" then return nil end
    local below, equal = 0, 0
    for index = 1, n do
        local sample = sorted[index]
        if sample < value then
            below = below + 1
        elseif sample == value then
            equal = equal + 1
        else
            break
        end
    end
    return math.floor(100 * (below + 0.5 * equal) / n + 0.5)
end

local function clamp(value, low, high)
    if value < low then return low end
    if value > high then return high end
    return value
end

function Market:ConfidenceOf(days, snapshots)
    local C = marketConfig().CONFIDENCE
    if snapshots <= 0 then return "none" end
    if days >= C.HIGH_DAYS and snapshots >= C.HIGH_SNAPSHOTS then return "high" end
    if days >= C.MEDIUM_DAYS and snapshots >= C.MEDIUM_SNAPSHOTS then return "medium" end
    return "low"
end

-- ---------------------------------------------------------------------------
-- MARKET SCORE 0-100
--
-- Er beantwortet genau eine Frage:
--   "Wie guenstig ist der aktuelle Preis, gemessen an der eigenen Historie?"
--
-- Er bedeutet ausdruecklich NICHT "kaufen". 0.5 kennt weder Nachfrage noch
-- Liquiditaet noch Verkaufsgeschwindigkeit. Ein Item kann historisch spottbillig
-- sein, weil es niemand mehr braucht.
--
-- Die Rechnung in vier Schritten:
--
-- 1. Perzentil-Anteil (Gewicht 0.55)
--       priceScore = 100 - Perzentil
--    Das Perzentil sagt, welcher Anteil aller gespeicherten Preise unter dem
--    aktuellen lag. Perzentil 8 heisst: nur 8 % waren guenstiger -> 92 Punkte.
--    Robust gegen Ausreisser, weil nur Raenge zaehlen, keine Betraege.
--
-- 2. Abstands-Anteil (Gewicht 0.45)
--       discount7  = (Median7  - aktuell) / Median7
--       discount30 = (Median30 - aktuell) / Median30
--       blended    = 0.4 * discount7 + 0.6 * discount30
--       discountScore = 50 + 100 * blended, begrenzt auf 0..100
--    Das Perzentil kennt nur die Reihenfolge; ob "guenstig" 2 % oder 40 % unter
--    dem Median bedeutet, sagt erst der Abstand. Der 30-Tage-Median wiegt
--    schwerer, der 7-Tage-Median haelt frische Marktbewegungen dagegen.
--
-- 3. Volatilitaets-Daempfung
--       volFactor = 1 - min(Volatilitaet, 0.6) * 0.25    (also 1.00 bis 0.85)
--       score = 50 + (roh - 50) * volFactor
--    In einem stark schwankenden Markt ist ein tiefer Preis weniger Aussage und
--    mehr Zufall. Gedaempft wird Richtung 50 - Richtung "keine Aussage", nicht
--    Richtung "teuer".
--
-- 4. Datenqualitaets-Daempfung
--       Faktor: none 0, low 0.35, medium 0.7, high 1.0
--       score = 50 + (score - 50) * Faktor
--    Damit ist die Obergrenze bei duenner Datenlage hart begrenzt: bei "low"
--    sind hoechstens 68 Punkte moeglich, bei "medium" 85. Zwei Messpunkte
--    koennen also nie "Score 95" ergeben. Score und Confidence bleiben getrennt
--    ausgewiesen - der Score ist die Aussage, die Confidence ihr Gewicht.
--
-- Unter MIN_SCORE_SNAPSHOTS (3) Messpunkten gibt es gar keinen Score: In eine
-- Verteilung aus zwei Punkten laesst sich nichts einordnen.
-- ---------------------------------------------------------------------------

function Market:ComputeStats(itemID, now)
    local M = marketConfig()
    local store = self:EnsureStore()
    local series = store and store.items[itemID]

    local cutoff30 = now - 30 * 86400
    local cutoff7 = now - 7 * 86400
    local cutoff24 = now - 86400

    local window30, window7, window24 = {}, {}, {}
    local dayKeys, days = {}, 0
    local oldest, newest = nil, nil

    if series then
        for index = 1, #series - 1, 2 do
            local stamp = seriesTimestamp(store, series[index])
            local price = series[index + 1]
            newest = stamp
            if stamp >= cutoff30 then
                if not oldest then oldest = stamp end
                window30[#window30 + 1] = price
                if stamp >= cutoff7 then window7[#window7 + 1] = price end
                if stamp >= cutoff24 then window24[#window24 + 1] = price end
                local day = date("%Y-%m-%d", stamp)
                if not dayKeys[day] then
                    dayKeys[day] = true
                    days = days + 1
                end
            end
        end
    end

    -- Der aktuelle Preis kommt aus der Preisquelle. Antwortet sie nicht (kein
    -- Scan seit dem Login), gilt der juengste gespeicherte Punkt - und das
    -- Ergebnis sagt, dass er nicht live ist.
    local current, currentSource = GCP.Prices:GetMarketPrice(itemID)
    current = self:NormalizePrice(current)
    local live = current ~= nil
    if not current and series and #series >= 2 then
        current = series[#series]
        currentSource = nil
    end

    local snapshots = #window30
    local stats = {
        itemID = itemID,
        current = current,
        currentIsLive = live,
        currentSource = currentSource,
        snapshots = snapshots,
        days = days,
        firstSeen = oldest,
        lastSeen = newest,
        source = store and store.source[itemID] or nil,
        confidence = self:ConfidenceOf(days, snapshots),
        score = nil,
    }

    if snapshots == 0 then
        return stats
    end

    table.sort(window30)
    table.sort(window7)
    table.sort(window24)

    stats.median30 = medianOf(window30)
    stats.median7 = medianOf(window7)
    stats.median24 = medianOf(window24)
    stats.min7 = window7[1]
    stats.max7 = window7[#window7]
    stats.percentile = percentileOf(window30, current)

    -- Robuste Volatilitaet: Quartilsabstand geteilt durch Median. Gegenueber
    -- Standardabweichung/Mittelwert unempfindlich gegen die eine
    -- Dumping-Auktion, die den halben Datensatz sonst verzerrt.
    if stats.median30 and stats.median30 > 0 then
        local q25 = quantile(window30, 0.25)
        local q75 = quantile(window30, 0.75)
        if q25 and q75 then
            stats.volatility = (q75 - q25) / stats.median30
            -- Die beiden Quartile stehen seit 0.7.0 auch einzeln zur Verfuegung:
            -- Die Einstiegszone der Future Engine ankert am unteren Quartil,
            -- und ein zweites Mal sortieren, was hier ohnehin schon berechnet
            -- ist, waere Verschwendung.
            stats.q25 = math.floor(q25 + 0.5)
            stats.q75 = math.floor(q75 + 0.5)
        end
    end

    -- ---------------------------------------------------------------------
    -- TREND / REGIME (1.0.0-beta.10)
    --
    -- Der Score bis beta.9 misst ausschliesslich LAGE: Wo steht der Preis
    -- innerhalb seiner eigenen Verteilung? Er unterscheidet damit nicht
    -- zwischen
    --
    --     100 90 110 95 105 60      <- ein Ausreisser nach unten
    --     100 95 90 80 70 60        <- ein Markt, der faellt
    --
    -- In beiden Faellen steht 60 ganz unten in der Verteilung, in beiden
    -- Faellen liegt der Preis weit unter dem Median - und der Score ist hoch.
    -- Im ersten Fall zu Recht, im zweiten ist es ein fallendes Messer.
    --
    -- Gemessen wird mit dem, was ohnehin schon dasteht: der Abstand des
    -- 7-Tage-Medians zum 30-Tage-Median. Liegt die juengere Haelfte deutlich
    -- unter der aelteren, faellt der Markt - und dann ist "billig" eine
    -- schwaechere Aussage, keine falsche.
    --
    -- Die Wirkung ist bewusst klein, einseitig und benannt:
    --   * Sie zieht Richtung 50 ("keine Aussage"), nie darueber hinaus.
    --   * Ein STEIGENDER Markt bekommt keinen Bonus. Wer teuer kauft, hat
    --     keinen besseren Einstand, nur weil es gerade aufwaerts geht.
    --   * Unter TREND_MIN_SNAPSHOTS/DAYS gibt es keinen Trend, sondern Zufall.
    if stats.median7 and stats.median30 and stats.median30 > 0
        and snapshots >= M.SCORE.TREND_MIN_SNAPSHOTS
        and days >= M.SCORE.TREND_MIN_DAYS then
        stats.drift = (stats.median7 - stats.median30) / stats.median30
        if stats.drift <= M.SCORE.TREND_DOWN then
            stats.trend = "falling"
        elseif stats.drift >= M.SCORE.TREND_UP then
            stats.trend = "rising"
        else
            stats.trend = "flat"
        end
    end

    if current and snapshots >= M.MIN_SCORE_SNAPSHOTS
        and stats.median30 and stats.median30 > 0 then
        local S = M.SCORE
        local priceScore = 100 - (stats.percentile or 50)

        local discount30 = (stats.median30 - current) / stats.median30
        local blended = discount30
        if stats.median7 and stats.median7 > 0 then
            local discount7 = (stats.median7 - current) / stats.median7
            blended = S.MEDIAN7_SHARE * discount7 + S.MEDIAN30_SHARE * discount30
        end
        local discountScore = clamp(50 + S.DISCOUNT_SPAN * blended, 0, 100)

        local raw = S.PERCENTILE_WEIGHT * priceScore + S.DISCOUNT_WEIGHT * discountScore

        local volatility = stats.volatility or 0
        local volFactor = 1 - math.min(volatility, S.VOLATILITY_CAP) * S.VOLATILITY_DAMPING
        local damped = 50 + (raw - 50) * volFactor

        -- Trenddaempfung. Sie greift nur nach unten und nur bei einem Score
        -- ueber 50: Einen ohnehin schlechten Score noch weiter zu senken, weil
        -- der Markt faellt, waere doppelt gezaehlt.
        if stats.trend == "falling" and damped > 50 then
            local span = S.TREND_FULL - S.TREND_DOWN
            local strength = 1
            if span ~= 0 then
                strength = clamp((stats.drift - S.TREND_DOWN) / span, 0, 1)
            end
            local factor = 1 - S.TREND_DAMPING * strength
            damped = 50 + (damped - 50) * factor
            stats.trendDamping = factor
        end

        local confidenceFactor = S.CONFIDENCE_FACTOR[stats.confidence] or 0
        local final = 50 + (damped - 50) * confidenceFactor

        stats.rawScore = raw
        stats.score = clamp(math.floor(final + 0.5), 0, 100)
    end

    return stats
end

-- Statistik eines Items, gecacht. Der Cache wird verworfen, sobald fuer das
-- Item ein Snapshot geschrieben wird; zusaetzlich laeuft er nach
-- STATS_CACHE_SECONDS ab, weil die Zeitfenster wandern.
function Market:GetStats(itemID)
    if type(itemID) ~= "number" then return nil end
    local now = self:Now()
    local M = marketConfig()
    local cached = self.statsCache[itemID]
    if cached and (now - cached.computedAt) < M.STATS_CACHE_SECONDS then
        return cached.stats
    end
    local stats = self:ComputeStats(itemID, now)
    self.statsCache[itemID] = { computedAt = now, stats = stats }
    return stats
end

-- Oeffentliche Schnittstelle der Market Engine. Liefert dieselbe Struktur wie
-- GetStats; der Name benennt, wofuer sie gedacht ist.
function Market:GetMarketScore(itemID)
    return self:GetStats(itemID)
end

-- ---------------------------------------------------------------------------
-- Einordnung und Aufbereitung fuer die Oberflaeche
-- ---------------------------------------------------------------------------

function Market:ScoreBand(score)
    if type(score) ~= "number" then return nil end
    for _, band in ipairs(marketConfig().BANDS) do
        if score >= band.min then return band.label, band.min end
    end
    return nil
end

function Market:ConfidenceLabel(confidence)
    return marketConfig().CONFIDENCE_LABEL[confidence or "none"] or "keine Daten"
end

function Market:SourceLabel(code)
    return SOURCE_LABELS[code or ""] or "unbekannt"
end

function Market:FormatPercentile(percentile)
    if type(percentile) ~= "number" then return "–" end
    -- Das Perzentil entsteht aus einer Division und ist damit eine Kommazahl.
    -- "%d" verlangt in Lua 5.3 eine ganze Zahl - gerundet wird hier.
    return string.format("%.0f.", percentile)
end

function Market:FormatVolatility(volatility)
    if type(volatility) ~= "number" then return "–" end
    return string.format("%.2f", volatility)
end

-- Tausenderpunkte, wie im deutschen UI ueblich ("1.284 Preispunkte").
function Market:FormatCount(count)
    if type(count) ~= "number" then return "0" end
    local text = tostring(math.floor(count))
    local out = text:reverse():gsub("(%d%d%d)", "%1."):reverse()
    return (out:gsub("^%.", ""))
end

-- Der Satz unter dem Tooltip: was der Score in Worten bedeutet. Kein "kaufen",
-- keine Prognose - nur die Einordnung in die eigenen Daten.
function Market:DescribeScore(stats)
    if type(stats) ~= "table" then return "Keine Daten." end
    if not stats.current then
        return "Noch kein Preis für dieses Item – im AH einen Auctionator-Scan starten."
    end
    local M = marketConfig()
    if stats.snapshots < M.MIN_SCORE_SNAPSHOTS or not stats.median30 then
        return string.format(
            "Erst %d Preispunkt(e) an %d Tag(en) gespeichert – für eine Einordnung "
            .. "braucht Gold Copilot mehrere Tage Realm-Daten.",
            stats.snapshots, stats.days)
    end
    local delta = (stats.current - stats.median30) / stats.median30
    local text = string.format(
        "Der aktuelle Preis liegt %.0f %% %s dem 30-Tage-Median und im %d. Perzentil "
        .. "deiner gespeicherten Realm-Daten.",
        math.abs(delta) * 100,
        delta < 0 and "unter" or "über",
        stats.percentile or 50)
    -- Der Trend gehoert dazu, sobald er den Score veraendert hat: Eine
    -- Daempfung, die niemand sieht, ist keine nachvollziehbare Rechnung.
    if stats.trend == "falling" then
        text = text .. string.format(
            " Der 7-Tage-Median liegt allerdings %.0f %% unter dem 30-Tage-Median – "
            .. "der Markt fällt gerade. Günstig heißt dann nicht zwangsläufig "
            .. "billig%s.",
            math.abs(stats.drift or 0) * 100,
            stats.trendDamping and ", und der Score ist dafür gedämpft" or "")
    elseif stats.trend == "rising" then
        text = text .. string.format(
            " Der 7-Tage-Median liegt %.0f %% über dem 30-Tage-Median – der Markt "
            .. "steigt. Das hebt den Score nicht an: Ein steigender Preis ist kein "
            .. "besserer Einstand.", math.abs(stats.drift or 0) * 100)
    end
    return text
end

-- Kennzahlen ueber alle Reihen. Bewusst O(Anzahl Items) statt O(Anzahl
-- Snapshots): Die Kopfzeile des Markt-Tabs wird bei jedem Refresh gebraucht.
function Market:GetOverview()
    local now = self:Now()
    if self.overviewCache and (now - self.overviewCache.computedAt) < 15 then
        return self.overviewCache.data
    end
    local store = self:EnsureStore()
    local snapshots, itemsWithHistory = 0, 0
    local oldest, newest = nil, nil
    if store then
        for _, series in pairs(store.items) do
            local count = #series
            if count >= 2 then
                itemsWithHistory = itemsWithHistory + 1
                snapshots = snapshots + math.floor(count / 2)
                local first = seriesTimestamp(store, series[1])
                local last = seriesTimestamp(store, series[count - 1])
                if not oldest or first < oldest then oldest = first end
                if not newest or last > newest then newest = last end
            end
        end
    end
    local spanDays = 0
    if oldest and newest then
        spanDays = math.floor((newest - oldest) / 86400) + 1
    end
    local data = {
        tracked = #self:GetTrackedItems(),
        itemsWithHistory = itemsWithHistory,
        snapshots = snapshots,
        oldest = oldest,
        newest = newest,
        spanDays = spanDays,
        callback = self.callbackRegistered,
    }
    self.overviewCache = { computedAt = now, data = data }
    return data
end

-- Grobe Schaetzung der Dateigroesse in Bytes: je Zahl ihre Stellen plus
-- Trennzeichen, je Item der Tabellenkopf. WoW schreibt SavedVariables als
-- Lua-Quelltext, also ist die Zeichenzahl die Dateigroesse.
--
-- Das ist die einzige Rechnung, die wirklich jeden gespeicherten Wert anfasst.
-- Deshalb eine Minute Cache: Der Optionen-Tab zeigt die Zahl bei jedem Refresh,
-- und sie aendert sich zwischen zwei Scans ohnehin nicht.
function Market:EstimateBytes()
    local now = self:Now()
    if self.bytesCache and (now - self.bytesCache.computedAt) < 60 then
        return self.bytesCache.value
    end
    local store = self:EnsureStore()
    if not store then return 0 end
    local bytes = 64
    for itemID, series in pairs(store.items) do
        bytes = bytes + #tostring(itemID) + 12
        for index = 1, #series do
            bytes = bytes + #tostring(series[index]) + 1
        end
    end
    for itemID in pairs(store.source) do
        bytes = bytes + #tostring(itemID) + 10
    end
    self.bytesCache = { computedAt = now, value = bytes }
    return bytes
end

function Market:FormatBytes(bytes)
    if type(bytes) ~= "number" then return "–" end
    if bytes >= 1048576 then
        return string.format("%.1f MB", bytes / 1048576)
    elseif bytes >= 1024 then
        return string.format("%.0f KB", bytes / 1024)
    end
    -- Bewusst "%.0f" statt "%d": Der Schaetzwert ist eine Kommazahl, und "%d"
    -- verlangt in Lua 5.3 eine ganze Zahl. Runden allein genuegt nicht -
    -- math.floor liefert bei sehr grossen Werten weiterhin eine Kommazahl.
    return string.format("%.0f B", bytes)
end

-- Fertige, sortierte Tabelle fuer den Markt-Tab. Items ohne jeden Messpunkt
-- fehlen bewusst: Der Tab zeigt beobachtete Maerkte, nicht Absichtserklaerungen.
function Market:BuildReport(limit)
    local rows = {}
    local store = self:EnsureStore()
    for _, itemID in ipairs(self:GetTrackedItems()) do
        -- Beobachtete Items ohne jede Reihe gar nicht erst durchrechnen: In den
        -- ersten Tagen ist das die Mehrheit, und die Statistik waere jedes Mal
        -- dieselbe Null.
        local stats = store and store.items[itemID] and self:GetMarketScore(itemID)
        if stats and stats.snapshots > 0 then
            local name, _, quality, _, _, _, _, _, _, icon = GetItemInfoCompat(itemID)
            rows[#rows + 1] = {
                itemID = itemID,
                name = name,
                icon = icon,
                quality = quality,
                reason = self.trackedReasons[itemID],
                stats = stats,
                score = stats.score,
                confidence = stats.confidence,
            }
        end
    end
    -- Hoechster Score zuerst; Reihen ohne Score stehen hinten, dort entscheidet
    -- die Datenmenge - wer am naechsten an einer Aussage ist, steht oben.
    table.sort(rows, function(a, b)
        if (a.score ~= nil) ~= (b.score ~= nil) then return a.score ~= nil end
        if a.score and b.score and a.score ~= b.score then return a.score > b.score end
        if a.stats.snapshots ~= b.stats.snapshots then
            return a.stats.snapshots > b.stats.snapshots
        end
        return (a.name or "") < (b.name or "")
    end)
    -- Ein negativer oder gebrochener Deckel wuerde die Schleife bis in den
    -- negativen Zahlenbereich laufen lassen; sie endet dann praktisch nie.
    limit = tonumber(limit)
    if limit then limit = math.max(math.floor(limit), 0) end
    if limit and #rows > limit then
        for index = #rows, limit + 1, -1 do
            rows[index] = nil
        end
    end
    return { rows = rows, overview = self:GetOverview() }
end

-- ---------------------------------------------------------------------------
-- Auctionator-Anbindung
--
-- Auctionator stellt seit 2020 Auctionator.API.v1.RegisterForDBUpdate(callerID,
-- callback) bereit; die Fassung 9.1.3 hat die Ausloesung nach einem
-- Vollscan repariert und 9.1.6-bcc sie ausdruecklich auf das TBC-Scanverfahren
-- umgestellt - genau die Reihe, aus der die Anniversary-Fassung stammt.
--
-- Trotzdem wird nicht auf den Namen vertraut: Registriert wird nur, wenn die
-- Funktion zur Laufzeit wirklich existiert, und auch dann in pcall. Faellt eines
-- davon aus, bleibt AUCTION_HOUSE_CLOSED aus 0.4.0 als Rueckfall - deshalb ist
-- es weiterhin registriert, auch wenn der Callback laeuft.
--
-- Ein Vollscan feuert das DB-Update viele Male hintereinander. Deshalb schreibt
-- der Callback nicht selbst, sondern setzt eine Marke; erst DB_UPDATE_DEBOUNCE
-- Sekunden nach dem letzten Update laeuft genau ein Durchlauf. Zusammen mit dem
-- 30-Minuten-Fenster je Item kann ein Scan hoechstens einen Snapshot je Item
-- erzeugen, egal wie oft er meldet.
-- ---------------------------------------------------------------------------

function Market:HasAuctionatorCallbackAPI()
    return Auctionator ~= nil and Auctionator.API ~= nil
        and Auctionator.API.v1 ~= nil
        and type(Auctionator.API.v1.RegisterForDBUpdate) == "function"
end

function Market:TryRegisterAuctionatorCallback()
    if self.callbackRegistered then return true end
    if not self:HasAuctionatorCallbackAPI() then return false end
    local ok = pcall(Auctionator.API.v1.RegisterForDBUpdate, addonName, function()
        GCP.Market:OnDatabaseUpdate("Auctionator")
    end)
    self.callbackRegistered = ok and true or false
    self.overviewCache = nil
    return self.callbackRegistered
end

-- Sammelstelle fuer alle Ausloeser: Auctionator-Callback, AH geschlossen,
-- Fenster geoeffnet. Rueckgabe true, wenn dieser Aufruf einen Durchlauf
-- angestossen hat (und nicht nur an einen laufenden angedockt wurde).
function Market:OnDatabaseUpdate(reason)
    self.pendingReason = reason or "unbekannt"
    if self.flushScheduled then return false end
    self.flushScheduled = true
    local delay = marketConfig().DB_UPDATE_DEBOUNCE
    if type(C_Timer) == "table" and type(C_Timer.After) == "function" then
        C_Timer.After(delay, function() GCP.Market:FlushPending() end)
    else
        self:FlushPending()
    end
    return true
end

function Market:FlushPending()
    self.flushScheduled = false
    local reason = self.pendingReason
    self.pendingReason = nil
    if not reason or not GCP.db then return 0 end
    local written = self:RecordSnapshots(reason)
    if written > 0 and GCP.UI then
        GCP.UI:RefreshIfShown()
    end
    return written
end

-- ---------------------------------------------------------------------------
-- MARKTTIEFE (0.9.0)
--
-- Bis 0.8 kennt Gold Copilot Preise, aber keine MENGEN. Das ist die Luecke,
-- die jede Kaufempfehlung offen laesst: "30 % unter Median" heisst wenig,
-- wenn davon 400 Stueck herumliegen.
--
-- DATENQUELLE. Der Classic-Client gibt Angebotsmengen ausschliesslich fuer die
-- gerade angezeigte Auktionsliste heraus (GetNumAuctionItems / GetAuctionItemInfo).
-- Auctionator liefert Preise, keine Mengen. Es gibt also genau einen ehrlichen
-- Weg: mitlesen, was der Spieler ohnehin durchblaettert.
--
-- WAS DARAUS FOLGT - und was hier ausdruecklich NICHT behauptet wird:
--   * Die Tiefe gilt fuer den Zeitpunkt des Blaetterns, nicht fuer jetzt.
--     Deshalb steht an jeder Aussage, wie alt sie ist.
--   * Nur die ERSTE SEITE. Wer nicht weiterblaettert, sieht nicht alles; die
--     gemessene Menge ist damit eine Untergrenze und heisst auch so.
--   * Items, die der Spieler nie gesucht hat, haben keine Tiefe - und dann
--     steht dort nichts, nicht "0 Angebote".
--
-- MARKTSTRUKTUR-SIGNALE sind BESCHREIBUNGEN. Gold Copilot sagt nie
-- "Marktmanipulation" - das kann niemand wissen. Es sagt "ungewoehnliche
-- Marktstruktur" und beschreibt, was ungewoehnlich ist.
-- ---------------------------------------------------------------------------

local DEPTH_HISTORY_STRIDE = 2

local function depthConfig()
    return marketConfig().DEPTH
end

function Market:EnsureDepthStore()
    local db = GCP.db
    if not db then return nil end
    local D = depthConfig()
    local profile = GCP:Profile()
    local store = profile.marketDepth
    if type(store) ~= "table" or store.version ~= D.STORE_VERSION
        or type(store.items) ~= "table" or type(store.epoch) ~= "number" then
        store = { version = D.STORE_VERSION, epoch = self:Now(), items = {} }
        profile.marketDepth = store
    end
    return store
end

function Market:ResetDepth()
    local db = GCP.db
    if not db then return 0 end
    local store = self:EnsureDepthStore()
    local count = 0
    for _ in pairs(store.items) do count = count + 1 end
    GCP:Profile().marketDepth = nil
    self:EnsureDepthStore()
    self:Touch()
    return count
end

-- Rechnet eine Liste roher Auktionszeilen in eine Tiefenaufnahme um.
-- listings: { { count = 5, buyoutTotal = 100000, owner = "..." }, ... }
-- Zeilen ohne Sofortkauf zaehlen in die Gesamtmenge, aber in keine Preisstufe:
-- Was man nicht sofort kaufen kann, ist kein Angebot zu einem Preis.
function Market:ComputeDepth(listings)
    if type(listings) ~= "table" or #listings == 0 then return nil end
    local D = depthConfig()
    local totalQuantity, buyoutQuantity = 0, 0
    local levels, levelIndex = {}, {}
    local owners, knownOwners = {}, 0
    local lowest = nil

    for _, listing in ipairs(listings) do
        -- Eine Zeile, die keine Tabelle ist, ist kein Angebot. Der Client
        -- liefert so etwas nicht, aber eine kaputte SavedVariable oder ein
        -- fremder Aufrufer schon - und dann faellt hier nichts um.
        local count = type(listing) == "table" and (tonumber(listing.count) or 0) or 0
        if count > 0 then
            totalQuantity = totalQuantity + count
            local total = tonumber(listing.buyoutTotal) or 0
            if total > 0 then
                local unit = math.floor(total / count + 0.5)
                if unit >= marketConfig().MIN_PRICE and unit <= marketConfig().MAX_PRICE then
                    buyoutQuantity = buyoutQuantity + count
                    if lowest == nil or unit < lowest then lowest = unit end
                    local slot = levelIndex[unit]
                    if not slot then
                        slot = { unit = unit, quantity = 0, listings = 0 }
                        levelIndex[unit] = slot
                        levels[#levels + 1] = slot
                    end
                    slot.quantity = slot.quantity + count
                    slot.listings = slot.listings + 1
                end
            end
            if type(listing.owner) == "string" and listing.owner ~= "" then
                owners[listing.owner] = (owners[listing.owner] or 0) + 1
                knownOwners = knownOwners + 1
            end
        end
    end
    if totalQuantity <= 0 then return nil end
    table.sort(levels, function(a, b) return a.unit < b.unit end)

    local nearQuantity = 0
    if lowest then
        local ceiling = lowest * (1 + D.NEAR_MARKET)
        for _, level in ipairs(levels) do
            if level.unit <= ceiling then
                nearQuantity = nearQuantity + level.quantity
            end
        end
    end

    local topOwner, topOwnerCount = nil, 0
    for owner, count in pairs(owners) do
        if count > topOwnerCount then topOwner, topOwnerCount = owner, count end
    end

    return {
        listingCount = #listings,
        availableQuantity = totalQuantity,
        buyoutQuantity = buyoutQuantity,
        lowestUnitPrice = lowest,
        priceLevels = levels,
        depthNearMarket = nearQuantity,
        ownerKnownCount = knownOwners,
        topOwnerCount = topOwnerCount,
    }
end

-- Schreibt eine Tiefenaufnahme fort. Gedrosselt je Item: Wer dreimal
-- hintereinander dasselbe sucht, erzeugt nicht drei Messpunkte.
function Market:RecordDepth(itemID, listings, now)
    if not isItemID(itemID) then return false end
    local store = self:EnsureDepthStore()
    if not store then return false end
    local D = depthConfig()
    now = tonumber(now) or self:Now()
    local depth = self:ComputeDepth(listings)
    if not depth then return false end

    local minute = math.floor((now - store.epoch) / 60)
    local entry = store.items[itemID]
    if entry and type(entry.at) == "number"
        and (minute - entry.at) * 60 < D.MIN_INTERVAL then
        return false, "gedrosselt"
    end

    local history = (entry and entry.h) or {}
    history[#history + 1] = minute
    history[#history + 1] = depth.availableQuantity
    while #history > D.MAX_HISTORY * DEPTH_HISTORY_STRIDE do
        table.remove(history, 1)
        table.remove(history, 1)
    end

    local levels = {}
    for index = 1, math.min(#depth.priceLevels, D.MAX_LEVELS) do
        levels[#levels + 1] = depth.priceLevels[index].unit
        levels[#levels + 1] = depth.priceLevels[index].quantity
    end

    store.items[itemID] = {
        at = minute,
        q = depth.availableQuantity,
        b = depth.buyoutQuantity,
        l = depth.listingCount,
        d = depth.depthNearMarket,
        p = levels,
        o = depth.topOwnerCount,
        k = depth.ownerKnownCount,
        h = history,
    }
    self:PruneDepth(now)
    self:Touch()
    return true
end

function Market:PruneDepth(now)
    local store = self:EnsureDepthStore()
    if not store then return 0 end
    local D = depthConfig()
    now = tonumber(now) or self:Now()
    local cutoff = math.floor((now - D.RETENTION_DAYS * 86400 - store.epoch) / 60)
    local removed = 0
    local order = {}
    for itemID, entry in pairs(store.items) do
        if type(entry) ~= "table" or type(entry.at) ~= "number" or entry.at < cutoff then
            store.items[itemID] = nil
            removed = removed + 1
        else
            order[#order + 1] = { itemID = itemID, at = entry.at }
        end
    end
    if #order > D.MAX_ITEMS then
        table.sort(order, function(a, b) return a.at < b.at end)
        for index = 1, #order - D.MAX_ITEMS do
            store.items[order[index].itemID] = nil
            removed = removed + 1
        end
    end
    return removed
end

local function depthMedian(history)
    local values = {}
    for index = 2, #history, DEPTH_HISTORY_STRIDE do
        values[#values + 1] = history[index]
    end
    if #values == 0 then return nil, 0 end
    table.sort(values)
    local middle = math.floor(#values / 2)
    if #values % 2 == 1 then return values[middle + 1], #values end
    return (values[middle] + values[middle + 1]) / 2, #values
end

-- Die gespeicherte Tiefe eines Items, aufbereitet. nil heisst: nie gesehen -
-- ausdruecklich nicht "keine Angebote".
function Market:GetDepth(itemID)
    local store = self:EnsureDepthStore()
    if not store then return nil end
    local entry = store.items[itemID]
    if type(entry) ~= "table" then return nil end
    local D = depthConfig()
    local observedAt = store.epoch + (entry.at or 0) * 60
    local levels = {}
    for index = 1, #(entry.p or {}), 2 do
        levels[#levels + 1] = { unit = entry.p[index], quantity = entry.p[index + 1] }
    end
    local median, samples = depthMedian(entry.h or {})
    -- Der Mengenverlauf, nicht nur sein Median (1.1.0). Die Demand Engine
    -- fragt danach: Ist die Angebotsmenge zwischen zwei Beobachtungen
    -- gesunken? Dann hat jemand gekauft - oder zurueckgezogen. Mehr sagt der
    -- Verlauf nicht, und mehr wird auch nicht daraus gemacht.
    local quantityHistory = {}
    for index = 1, #(entry.h or {}) - 1, DEPTH_HISTORY_STRIDE do
        quantityHistory[#quantityHistory + 1] = {
            at = store.epoch + entry.h[index] * 60,
            quantity = entry.h[index + 1],
        }
    end
    local depth = {
        itemID = itemID,
        observedAt = observedAt,
        quantityHistory = quantityHistory,
        ageSeconds = math.max(self:Now() - observedAt, 0),
        availableQuantity = entry.q or 0,
        buyoutQuantity = entry.b or 0,
        listingCount = entry.l or 0,
        depthNearMarket = entry.d or 0,
        priceLevels = levels,
        lowestUnitPrice = levels[1] and levels[1].unit or nil,
        medianQuantity = median,
        samples = samples,
        topOwnerCount = entry.o,
        ownerKnownCount = entry.k,
        -- Gemessen wird die angezeigte Seite. Mehr kann dort sein, weniger nicht.
        isLowerBound = true,
    }
    depth.signals = self:DepthSignals(depth)
    if median and median > 0 then
        depth.supplyRatio = depth.availableQuantity / median
    end
    -- Ueberversorgung ist ein VERGLEICH und braucht Historie; Duenne ist eine
    -- direkte Beobachtung und braucht keine. Deshalb wird zuerst auf den
    -- Vergleich geprueft und erst danach auf die Beobachtung.
    if depth.supplyRatio and samples >= D.SHOCK_MIN_HISTORY
        and depth.supplyRatio >= D.GLUT_FACTOR then
        depth.supplyState = "glut"
    elseif depth.listingCount <= D.THIN_LISTINGS
        or depth.availableQuantity <= D.THIN_QUANTITY then
        depth.supplyState = "thin"
    end
    return depth
end

-- ---------------------------------------------------------------------------
-- Marktstruktur-Signale
--
-- Jedes Signal beschreibt eine Beobachtung und nennt die Zahl dahinter. Keines
-- behauptet einen Grund.
-- ---------------------------------------------------------------------------

Market.DEPTH_SIGNALS = {
    SUPPLY_SHOCK = "ungewöhnlich hohes Angebot",
    THIN_MARKET = "sehr dünner Markt",
    PRICE_WALL = "Preismauer",
    PRICE_OUTLIER = "einzelnes Angebot weit unter dem Rest",
    UNUSUAL_LISTING_CONCENTRATION = "ungewöhnliche Angebotskonzentration",
}

function Market:DepthSignals(depth)
    local D = depthConfig()
    local signals = {}
    if type(depth) ~= "table" then return signals end
    -- Die Signale rechnen mit Mengen. Fehlt eine, ist sie null - eine
    -- Tiefenaufnahme ohne Zahlen ist ein duenner Markt, kein Fehler.
    local listingCount = tonumber(depth.listingCount) or 0
    local availableQuantity = tonumber(depth.availableQuantity) or 0
    local buyoutQuantity = tonumber(depth.buyoutQuantity) or 0
    local function add(code, text)
        signals[#signals + 1] = { code = code,
            label = Market.DEPTH_SIGNALS[code], text = text }
    end

    if listingCount <= D.THIN_LISTINGS or availableQuantity <= D.THIN_QUANTITY then
        add("THIN_MARKET", string.format("%.0f Angebot(e), %.0f Stück insgesamt.",
            listingCount, availableQuantity))
    end

    local median = tonumber(depth.medianQuantity)
    if median and median > 0 and (tonumber(depth.samples) or 0) >= D.SHOCK_MIN_HISTORY
        and availableQuantity >= median * D.SHOCK_FACTOR then
        add("SUPPLY_SHOCK", string.format(
            "%.0f Stück gegenüber sonst etwa %.0f – rund %.1f-faches Angebot.",
            availableQuantity, median, availableQuantity / median))
    end

    local levels = depth.priceLevels or {}
    if #levels > 0 and listingCount >= D.WALL_MIN_LISTINGS then
        local biggest = levels[1]
        for _, level in ipairs(levels) do
            if level.quantity > biggest.quantity then biggest = level end
        end
        if buyoutQuantity > 0 and biggest.quantity >= buyoutQuantity * D.WALL_SHARE then
            add("PRICE_WALL", string.format(
                "%.0f von %.0f Stück liegen auf einer einzigen Preisstufe (%s).",
                biggest.quantity, buyoutQuantity,
                GCP.Prices:FormatMoney(biggest.unit)))
        end
    end

    if #levels >= D.OUTLIER_MIN_LEVELS then
        local first, second = levels[1], levels[2]
        if first and second and second.unit > 0
            and (first.unit / second.unit) <= D.OUTLIER_RATIO then
            add("PRICE_OUTLIER", string.format(
                "Günstigstes Angebot %s, nächstes %s.",
                GCP.Prices:FormatMoney(first.unit), GCP.Prices:FormatMoney(second.unit)))
        end
    end

    local ownerKnown = tonumber(depth.ownerKnownCount)
    local topOwner = tonumber(depth.topOwnerCount)
    if ownerKnown and topOwner
        and listingCount >= D.CONCENTRATION_MIN_LISTINGS
        and ownerKnown >= listingCount * 0.8
        and topOwner >= listingCount * D.CONCENTRATION_SHARE then
        add("UNUSUAL_LISTING_CONCENTRATION", string.format(
            "%.0f von %.0f Angeboten stammen von derselben Quelle. Warum, weiß "
            .. "Gold Copilot nicht – es beschreibt nur die Struktur.",
            topOwner, listingCount))
    end

    return signals
end

function Market:DescribeDepth(depth)
    if type(depth) ~= "table" then
        return "Keine Angebotsdaten – Gold Copilot kennt nur, was du selbst im "
            .. "Auktionshaus gesucht hast."
    end
    local age = depth.ageSeconds or 0
    local ageText
    if age < 3600 then
        ageText = string.format("%.0f Minute(n) alt", age / 60)
    else
        ageText = string.format("%.1f Stunde(n) alt", age / 3600)
    end
    return string.format("mindestens %.0f Stück in %.0f Angebot(en) · %.0f Stück "
        .. "nahe am Marktpreis · %s", depth.availableQuantity or 0,
        depth.listingCount or 0, depth.depthNearMarket or 0, ageText)
end

function Market:DepthOverview()
    local store = self:EnsureDepthStore()
    local items, quantity = 0, 0
    for _, entry in pairs(store and store.items or {}) do
        items = items + 1
        quantity = quantity + (entry.q or 0)
    end
    return { items = items, quantity = quantity }
end

-- ---------------------------------------------------------------------------
-- Erfassung aus dem Auktionshaus-Browser
--
-- Gelesen wird die gerade angezeigte Liste. Alles ist gegen fehlende APIs
-- abgesichert: Ein Client ohne diese Funktionen verliert die Markttiefe und
-- sonst nichts.
-- ---------------------------------------------------------------------------

function Market:HasAuctionBrowseAPI()
    return type(GetNumAuctionItems) == "function"
        and type(GetAuctionItemInfo) == "function"
end

function Market:ReadAuctionList()
    if not self:HasAuctionBrowseAPI() then return nil end
    local ok, shown = pcall(GetNumAuctionItems, "list")
    if not ok or type(shown) ~= "number" or shown <= 0 then return nil end
    local listings = {}
    local itemID = nil
    for index = 1, math.min(shown, 50) do
        local infoOK, name, _, count, _, _, _, _, _, _, buyout, _, _, _, owner =
            pcall(GetAuctionItemInfo, "list", index)
        if infoOK and type(count) == "number" then
            listings[#listings + 1] = {
                count = count, buyoutTotal = buyout, owner = owner, name = name,
            }
            if itemID == nil and type(GetAuctionItemLink) == "function" then
                local linkOK, link = pcall(GetAuctionItemLink, "list", index)
                if linkOK and type(link) == "string" then
                    itemID = tonumber(link:match("item:(%d+)"))
                end
            end
        end
    end
    if #listings == 0 then return nil end
    -- Ohne eindeutige Item-ID wird nichts geschrieben: Eine Suche nach
    -- "Urfeuer" kann mehrere Items liefern, und eine gemischte Tiefe waere
    -- schlimmer als keine.
    local mixed = false
    local firstName = listings[1].name
    for _, listing in ipairs(listings) do
        if listing.name ~= firstName then mixed = true break end
    end
    if mixed then return nil end
    return itemID, listings
end

function Market:CaptureAuctionList()
    if not GCP.db then return false end
    local itemID, listings = self:ReadAuctionList()
    if not itemID or not listings then return false end
    return self:RecordDepth(itemID, listings)
end

-- ---------------------------------------------------------------------------
-- Ereignisse
-- ---------------------------------------------------------------------------

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("PLAYER_LOGIN")
-- Auctionator kann nach Gold Copilot laden; dann ist beim Login noch keine API
-- da. Das Betreten des Auktionshauses ist der zweite, spaetere Versuch.
pcall(eventFrame.RegisterEvent, eventFrame, "AUCTION_HOUSE_SHOW")
-- Markttiefe (0.9.0): Die Angebotsliste steht nur waehrend des Blaetterns zur
-- Verfuegung. AUCTION_ITEM_LIST_UPDATE ist der einzige Zeitpunkt, an dem sie
-- vollstaendig ist; kennt eine Clientfassung das Ereignis nicht, faellt nur
-- die Tiefe weg.
pcall(eventFrame.RegisterEvent, eventFrame, "AUCTION_ITEM_LIST_UPDATE")
eventFrame:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_LOGIN" then
        if not GCP.db then GCP:EnsureDB() end
        Market:TryRegisterAuctionatorCallback()
        Market:RecordSnapshots("Login")
    elseif event == "AUCTION_HOUSE_SHOW" then
        Market:TryRegisterAuctionatorCallback()
    elseif event == "AUCTION_ITEM_LIST_UPDATE" then
        Market:CaptureAuctionList()
    end
end)
