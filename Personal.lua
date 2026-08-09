local addonName, GCP = ...

GCP.Personal = {}
local Personal = GCP.Personal

-- ---------------------------------------------------------------------------
-- PERSONAL BRAIN (0.9.0)
--
-- Bis 0.8 hat Gold Copilot Realm-Wissen (Markthistorie) und Handelswissen
-- (Ledger). Was fehlt, ist das Wissen ueber den SPIELER: Welche Aktivitaeten
-- fuehrt er wirklich aus? Welche ueberspringt er jedes Mal? Womit verdient er
-- tatsaechlich Gold - und womit nicht?
--
-- Genau das steht hier. Und zwar so, dass es spaeter Saetze wie
--
--     "Du erreichst mit Crafts typischerweise 21 % ROI (n=34)."
--
-- moeglich macht - statt der generischen Behauptung "Crafts sind gut".
--
-- ALLES BLEIBT LOKAL. Es gibt keine Uebertragung, keinen Abgleich, keine
-- Statistik ueber andere Spieler. Was hier steht, steht in den eigenen
-- SavedVariables und nirgendwo sonst.
--
-- WAS HIER AUSDRUECKLICH NICHT PASSIERT:
--   * Keine Aussage aus zu wenigen Daten. Unter MIN_SAMPLES gibt es die Zahl,
--     aber sie wird als LOW SAMPLE ausgewiesen und fliesst in keine Bewertung.
--   * Keine Schaetzung von Gewinnen. Realisiert ist nur, was das Ledger
--     bestaetigt hat.
--   * Keine Bewertung des Spielers. "Haeufig uebersprungen" ist eine
--     Beobachtung, kein Vorwurf - und fuehrt hoechstens dazu, dass eine
--     Aktivitaet seltener vorgeschlagen wird.
-- ---------------------------------------------------------------------------

local function config()
    return GCP.Constants.PERSONAL
end

Personal.revision = 0

local function isPositive(value)
    return type(value) == "number" and value > 0
end

local function now()
    if type(time) == "function" then
        local ok, value = pcall(time)
        if ok and type(value) == "number" then return value end
    end
    return 0
end

function Personal:Touch()
    self.revision = self.revision + 1
    self.cache = nil
end

-- ---------------------------------------------------------------------------
-- Speicher
--
--   db.personal = {
--       version = 1,
--       types = {
--           craft = { executed = 12, skipped = 3, profit = 480000, loss = 0,
--                     minutes = 92.5, wins = 9, losses = 1, roiSum = 2.4,
--                     roiCount = 10 },
--       },
--       routes = { started = 8, completed = 5, aborted = 1, minutes = 410 },
--       farm = { sessions = 12, minutes = 380, gold = 4100000 },
--       lastAt = 1786000000,
--   }
-- ---------------------------------------------------------------------------

function Personal:EnsureStore()
    local db = GCP.db
    if not db then return nil end
    local C = config()
    local store = db.personal
    if type(store) ~= "table" or store.version ~= C.STORE_VERSION then
        store = { version = C.STORE_VERSION }
        db.personal = store
    end
    if type(store.types) ~= "table" then store.types = {} end
    if type(store.routes) ~= "table" then
        store.routes = { started = 0, completed = 0, aborted = 0, minutes = 0 }
    end
    if type(store.farm) ~= "table" then
        store.farm = { sessions = 0, minutes = 0, gold = 0 }
    end
    return store
end

function Personal:Reset()
    local db = GCP.db
    if not db then return false end
    db.personal = nil
    self:EnsureStore()
    self:Touch()
    return true
end

local function bucket(store, kind)
    kind = kind or "unknown"
    local entry = store.types[kind]
    if type(entry) ~= "table" then
        entry = { executed = 0, skipped = 0, profit = 0, loss = 0, minutes = 0,
            wins = 0, losses = 0, roiSum = 0, roiCount = 0 }
        store.types[kind] = entry
    end
    return entry
end

-- ---------------------------------------------------------------------------
-- Erfassen
-- ---------------------------------------------------------------------------

function Personal:RecordStep(step, group, minutes)
    local store = self:EnsureStore()
    if not store or type(step) ~= "table" then return false end
    local entry = bucket(store, group and group.type or "unknown")
    entry.executed = entry.executed + 1
    if isPositive(minutes) then entry.minutes = entry.minutes + minutes end
    store.lastAt = now()
    self:Touch()
    return true
end

function Personal:RecordSkip(step)
    local store = self:EnsureStore()
    if not store or type(step) ~= "table" then return false end
    local kind = step.opportunityType or "unknown"
    if GCP.Guide then
        local group = GCP.Guide:GroupOf(step)
        if group and group.type then kind = group.type end
    end
    local entry = bucket(store, kind)
    entry.skipped = entry.skipped + 1
    store.lastAt = now()
    self:Touch()
    return true
end

function Personal:RecordRouteStarted()
    local store = self:EnsureStore()
    if not store then return false end
    store.routes.started = (store.routes.started or 0) + 1
    self:Touch()
    return true
end

function Personal:RecordRouteFinished(progress)
    local store = self:EnsureStore()
    if not store or type(progress) ~= "table" then return false end
    store.routes.completed = (store.routes.completed or 0) + 1
    store.routes.minutes = (store.routes.minutes or 0) + (progress.activeMinutes or 0)
    store.lastAt = now()
    self:Touch()
    return true
end

function Personal:RecordRouteAborted()
    local store = self:EnsureStore()
    if not store then return false end
    store.routes.aborted = (store.routes.aborted or 0) + 1
    self:Touch()
    return true
end

function Personal:RecordFarmSession(record)
    local store = self:EnsureStore()
    if not store or type(record) ~= "table" then return false end
    store.farm.sessions = (store.farm.sessions or 0) + 1
    store.farm.minutes = (store.farm.minutes or 0) + (record.m or 0)
    store.farm.gold = (store.farm.gold or 0) + (record.g or 0)
    store.lastAt = now()
    self:Touch()
    return true
end

-- Ein abgeschlossenes Ergebnis aus dem Chancen-Protokoll. Nur eindeutige
-- Ergebnisse zaehlen; OPEN und UNKNOWN bleiben draussen.
function Personal:RecordOutcome(entry)
    local store = self:EnsureStore()
    if not store or type(entry) ~= "table" then return false end
    if entry.outcome ~= "WIN" and entry.outcome ~= "LOSS" then return false end
    if entry.countedByPersonal then return false end
    local item = bucket(store, entry.type or "unknown")
    if entry.outcome == "WIN" then
        item.wins = item.wins + 1
        item.profit = item.profit + math.max(entry.realizedProfit or 0, 0)
    else
        item.losses = item.losses + 1
        item.loss = item.loss + math.abs(math.min(entry.realizedProfit or 0, 0))
    end
    if isPositive(entry.entryPrice) and isPositive(entry.entryQuantity)
        and type(entry.realizedProfit) == "number" then
        local invested = entry.entryPrice * entry.entryQuantity
        if invested > 0 then
            item.roiSum = item.roiSum + entry.realizedProfit / invested
            item.roiCount = item.roiCount + 1
        end
    end
    entry.countedByPersonal = true
    store.lastAt = now()
    self:Touch()
    return true
end

-- Laeuft ueber das Chancen-Protokoll und uebernimmt alle noch nicht gezaehlten
-- Ergebnisse. Bewusst idempotent: countedByPersonal verhindert Doppelzaehlung.
function Personal:SyncOutcomes()
    local history = GCP.Opportunity and GCP.Opportunity:EnsureHistory()
    if not history then return 0 end
    local counted = 0
    for _, entry in ipairs(history) do
        if self:RecordOutcome(entry) then counted = counted + 1 end
    end
    return counted
end

function Personal:OnLedgerEvent(kind, info)
    -- Das Ledger ist bereits die Wahrheit ueber Kaeufe und Verkaeufe; hier wird
    -- nichts doppelt gefuehrt. Gebraucht wird nur der Anstoss, Ergebnisse
    -- nachzutragen, sobald ein Verkauf durch ist.
    if kind ~= "sale" then return false end
    if GCP.Opportunity then GCP.Opportunity:MatchHistoryOutcomes() end
    return self:SyncOutcomes() > 0
end

-- ---------------------------------------------------------------------------
-- Auswerten
-- ---------------------------------------------------------------------------

function Personal:GetStats(kind)
    local store = self:EnsureStore()
    if not store then return nil end
    local entry = store.types[kind]
    if type(entry) ~= "table" then return nil end
    local C = config()
    local decided = (entry.wins or 0) + (entry.losses or 0)
    local stats = {
        type = kind,
        executed = entry.executed or 0,
        skipped = entry.skipped or 0,
        minutes = entry.minutes or 0,
        wins = entry.wins or 0,
        losses = entry.losses or 0,
        profit = entry.profit or 0,
        loss = entry.loss or 0,
        decided = decided,
    }
    stats.net = stats.profit - stats.loss
    if decided > 0 then
        stats.hitRate = stats.wins / decided
        stats.lowSample = decided < C.MIN_SAMPLES
    end
    if (entry.roiCount or 0) > 0 then
        stats.averageROI = entry.roiSum / entry.roiCount
        stats.roiSamples = entry.roiCount
    end
    local offered = stats.executed + stats.skipped
    if offered > 0 then
        stats.skipRate = stats.skipped / offered
        stats.skipSamples = offered
    end
    if isPositive(stats.minutes) then
        stats.goldPerHour = stats.net / (stats.minutes / 60)
    end
    return stats
end

function Personal:AllStats()
    local store = self:EnsureStore()
    if not store then return {} end
    local list = {}
    for kind in pairs(store.types) do
        local stats = self:GetStats(kind)
        if stats then list[#list + 1] = stats end
    end
    table.sort(list, function(a, b)
        if a.net ~= b.net then return a.net > b.net end
        return a.type < b.type
    end)
    return list
end

-- Der Satz, der aus einer generischen Aussage eine persoenliche macht. Er
-- entsteht NUR ueber der Mindeststichprobe - darunter gibt es nil, und die
-- Oberflaeche sagt dann schlicht nichts.
function Personal:ExpectedValueText(kind)
    local stats = self:GetStats(kind)
    if not stats then return nil end
    local C = config()
    if (stats.roiSamples or 0) >= C.MIN_SAMPLES and stats.averageROI then
        return string.format("Du erreichst mit %s typischerweise %.0f %% ROI (n=%d).",
            GCP.Opportunity:TypeLabel(kind) or kind, stats.averageROI * 100,
            stats.roiSamples)
    end
    if (stats.decided or 0) >= C.MIN_SAMPLES and stats.hitRate then
        return string.format("%s gehen bei dir zu %.0f %% positiv aus (n=%d).",
            GCP.Opportunity:TypeLabel(kind) or kind, stats.hitRate * 100, stats.decided)
    end
    return nil
end

-- Aktivitaeten, die der Spieler regelmaessig ueberspringt. Das ist eine
-- Beobachtung ueber die Oberflaeche, keine Bewertung der Aktivitaet.
function Personal:SkippedActivities()
    local C = config()
    local list = {}
    for _, stats in ipairs(self:AllStats()) do
        if (stats.skipSamples or 0) >= C.MIN_SKIP_SAMPLES
            and (stats.skipRate or 0) >= C.SKIP_THRESHOLD then
            list[#list + 1] = stats
        end
    end
    table.sort(list, function(a, b) return a.skipRate > b.skipRate end)
    return list
end

function Personal:PreferredActivities()
    local C = config()
    local list = {}
    for _, stats in ipairs(self:AllStats()) do
        if stats.executed >= C.MIN_SKIP_SAMPLES
            and (stats.skipRate or 0) < C.SKIP_THRESHOLD then
            list[#list + 1] = stats
        end
    end
    table.sort(list, function(a, b) return a.executed > b.executed end)
    return list
end

function Personal:HasData()
    local store = self:EnsureStore()
    if not store then return false end
    if (store.routes.started or 0) > 0 or (store.farm.sessions or 0) > 0 then
        return true
    end
    return next(store.types) ~= nil
end

function Personal:SummaryText()
    if not self:HasData() then
        return "Noch keine persönlichen Daten – Gold Copilot lernt sie aus deinen "
            .. "eigenen Routen, Verkäufen und Farmsitzungen."
    end
    local store = self:EnsureStore()
    return string.format("%d Route(n) gestartet, %d abgeschlossen · %d Farmsitzung(en).",
        store.routes.started or 0, store.routes.completed or 0,
        store.farm.sessions or 0)
end
