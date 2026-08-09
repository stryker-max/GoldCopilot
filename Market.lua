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
    local store = db.marketHistory
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
        db.marketHistory = store
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
    self:Prune(now)
    if written > 0 then
        self.overviewCache = nil
    end
    return written
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
    local snapshots = 0
    local store = db.marketHistory
    if type(store) == "table" and type(store.items) == "table" then
        for _, series in pairs(store.items) do
            snapshots = snapshots + math.floor(#series / 2)
        end
    end
    db.marketHistory = nil
    self.lastRecordAt = nil
    self:InvalidateCaches()
    self:InvalidateTrackedCache()
    self:Touch()
    self:EnsureStore()
    -- Nicht erneut importieren: Der Nutzer wollte die Markthistorie leer haben.
    local fresh = db.marketHistory
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

    local history = db.priceHistory
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
-- ---------------------------------------------------------------------------

function Market:EnsureWatchlist()
    local db = GCP.db
    if not db then return nil end
    if type(db.watchlist) ~= "table" then db.watchlist = {} end
    return db.watchlist
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
function Market:RegisterWatchItem(itemID, reason)
    if not isItemID(itemID) then return false end
    local watchlist = self:EnsureWatchlist()
    if not watchlist then return false end
    local existing = watchlist[itemID]
    if type(existing) == "table" then
        if type(reason) == "string" and reason ~= "" and existing.reason ~= reason then
            existing.reason = reason
        end
        return false
    end
    if self:CountWatchItems() >= marketConfig().MAX_WATCH_ITEMS then
        return false, "voll"
    end
    watchlist[itemID] = {
        reason = (type(reason) == "string" and reason ~= "") and reason or "manuell",
        addedAt = self:Now(),
    }
    self:InvalidateTrackedCache()
    self:Touch()
    return true
end

function Market:RemoveWatchItem(itemID)
    local watchlist = self:EnsureWatchlist()
    if not watchlist or watchlist[itemID] == nil then return false end
    watchlist[itemID] = nil
    self:InvalidateTrackedCache()
    self:Touch()
    return true
end

function Market:ToggleWatchItem(itemID, reason)
    if self:IsWatched(itemID) then
        self:RemoveWatchItem(itemID)
        return false
    end
    self:RegisterWatchItem(itemID, reason)
    return self:IsWatched(itemID)
end

-- Beobachtete Items als sortierte Liste, juengste Aufnahme zuerst.
function Market:GetWatchlist()
    local watchlist = self:EnsureWatchlist()
    local list = {}
    for itemID, entry in pairs(watchlist or {}) do
        if isItemID(itemID) and type(entry) == "table" then
            list[#list + 1] = {
                itemID = itemID,
                reason = entry.reason,
                addedAt = entry.addedAt,
            }
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
    return string.format("%d.", percentile)
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
    if not stats then return "Keine Daten." end
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
    return string.format(
        "Der aktuelle Preis liegt %.0f %% %s dem 30-Tage-Median und im %d. Perzentil "
        .. "deiner gespeicherten Realm-Daten.",
        math.abs(delta) * 100,
        delta < 0 and "unter" or "über",
        stats.percentile or 50)
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
    return string.format("%d B", bytes)
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
-- Ereignisse
-- ---------------------------------------------------------------------------

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("PLAYER_LOGIN")
-- Auctionator kann nach Gold Copilot laden; dann ist beim Login noch keine API
-- da. Das Betreten des Auktionshauses ist der zweite, spaetere Versuch.
pcall(eventFrame.RegisterEvent, eventFrame, "AUCTION_HOUSE_SHOW")
eventFrame:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_LOGIN" then
        if not GCP.db then GCP:EnsureDB() end
        Market:TryRegisterAuctionatorCallback()
        Market:RecordSnapshots("Login")
    elseif event == "AUCTION_HOUSE_SHOW" then
        Market:TryRegisterAuctionatorCallback()
    end
end)
