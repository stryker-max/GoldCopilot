local addonName, GCP = ...

GCP.Activity = {}
local Activity = GCP.Activity

-- ---------------------------------------------------------------------------
-- ACTIVITY / SESSIONS (1.1.0)
--
-- Farm.lua misst seit 0.9 eigene Farmraten und beweist damit, dass das Muster
-- traegt: Start, Ende, aktive Zeit, Ausbeute, Median ueber Sitzungen. Was
-- fehlte, war die Verallgemeinerung - denn erst sie macht Methoden
-- VERGLEICHBAR:
--
--     "Verzauberungsservice: 218 g/h aus 8 Sitzungen, Datenlage hoch"
--     "Adamantit farmen:     162 g/h aus 5 Sitzungen, Datenlage mittel"
--
-- Ohne diesen Vergleich beantwortet das Addon nur "welches Item?", nie
-- "welche Methode?".
--
-- WAS HIER NICHT PASSIERT:
--   * Keine Gold/h ohne eigene Sitzungen. Dieselbe Regel wie bei den
--     Farmraten, aus demselben Grund.
--   * Keine Hochrechnung aus einer Sitzung. Unter MIN_SESSIONS gibt es eine
--     Zahl, aber keine Confidence ueber "low".
--   * Keine Zeit, die niemand gearbeitet hat. Wer die Sitzung offen laesst und
--     schlafen geht, bekommt keine 8-Stunden-Rate.
--   * Kein Mittelwert. Ein einzelnes 500-g-Trinkgeld darf die Erwartung nicht
--     verschieben - deshalb Median, wie bei den Farmraten.
--
--   db.activity = {
--       version = 1,
--       current = { <laufende Sitzung> } | nil,
--       sessions = {
--           { k = "service.enchant", s = 1786000000, e = 1786003600,
--             m = 59.0, g = 2430000, c = 62000, n = 14, h = 19, w = 3 },
--       },
--   }
--
--   k Art  s Start  e Ende  m aktive Minuten  g Bruttogold  c eigene Kosten
--   n Ereignisse  h Stunde des Tages  w Wochentag
-- ---------------------------------------------------------------------------

local function config()
    return GCP.Constants.ACTIVITY
end

Activity.revision = 0

local function isPositive(value)
    return type(value) == "number" and value > 0
end

function Activity:Now()
    if type(time) == "function" then
        local ok, value = pcall(time)
        if ok and type(value) == "number" then return value end
    end
    return 0
end

function Activity:Touch()
    self.revision = self.revision + 1
    self.cache = nil
end

-- Median statt Mittelwert. Die Begruendung steht im Kopf des Moduls.
local function median(values)
    if type(values) ~= "table" or #values == 0 then return nil end
    local sorted = {}
    for index, value in ipairs(values) do sorted[index] = value end
    table.sort(sorted)
    local count = #sorted
    if count % 2 == 1 then return sorted[(count + 1) / 2] end
    return (sorted[count / 2] + sorted[count / 2 + 1]) / 2
end

-- ---------------------------------------------------------------------------
-- Speicher
-- ---------------------------------------------------------------------------

function Activity:EnsureStore()
    local db = GCP.db
    if not db then return nil end
    local C = config()
    local profile = GCP:Profile()
    local store = profile.activity
    if type(store) ~= "table" or store.version ~= C.STORE_VERSION
        or type(store.sessions) ~= "table" then
        store = { version = C.STORE_VERSION, sessions = {} }
        profile.activity = store
    end
    if store.current ~= nil and type(store.current) ~= "table" then
        store.current = nil
    end
    return store
end

function Activity:Reset()
    local db = GCP.db
    if not db then return false end
    GCP:Profile().activity = nil
    self:EnsureStore()
    self:Touch()
    return true
end

-- ---------------------------------------------------------------------------
-- Sitzungen
-- ---------------------------------------------------------------------------

function Activity:Current()
    local store = self:EnsureStore()
    return store and store.current or nil
end

function Activity:Start(kind, now)
    if type(kind) ~= "string" or kind == "" then return nil end
    local store = self:EnsureStore()
    if not store then return nil end
    now = tonumber(now) or self:Now()
    -- Eine laufende Sitzung wird abgeschlossen, nicht ueberschrieben: Was
    -- gemessen wurde, bleibt gemessen.
    if store.current then self:Stop("neue Sitzung", now) end
    store.current = {
        kind = kind,
        startedAt = now,
        lastEventAt = now,
        lastTickAt = now,
        activeSeconds = 0,
        gross = 0,
        cost = 0,
        events = 0,
    }
    self:Touch()
    return store.current
end

-- Aktive Zeit. Gezaehlt wird nur, was zwischen zwei Lebenszeichen liegt und
-- kurz genug ist, um Arbeit zu sein - dieselbe Regel wie beim Guide und beim
-- Farmen.
function Activity:Tick(now)
    local session = self:Current()
    if not session then return 0 end
    now = tonumber(now) or self:Now()
    local last = session.lastTickAt
    if type(last) == "number" then
        local delta = now - last
        if delta > 0 and delta < config().MAX_TICK_SECONDS then
            session.activeSeconds = (session.activeSeconds or 0) + delta
        end
    end
    session.lastTickAt = now
    return session.activeSeconds or 0
end

-- Beendet sich die Sitzung von selbst? Wer sie offen laesst und schlafen geht,
-- bekommt keine 8-Stunden-Rate.
function Activity:CheckIdle(now)
    local session = self:Current()
    if not session then return false end
    now = tonumber(now) or self:Now()
    if (now - (session.lastEventAt or session.startedAt)) >= config().IDLE_TIMEOUT then
        self:Stop("keine Aktivität mehr", now)
        return true
    end
    return false
end

function Activity:Stop(reason, now)
    local store = self:EnsureStore()
    if not store or not store.current then return nil end
    local C = config()
    now = tonumber(now) or self:Now()
    self:Tick(now)
    local session = store.current
    store.current = nil

    local minutes = (session.activeSeconds or 0) / 60
    -- Eine zu kurze Sitzung ist keine Messung, sondern ein Ausrutscher. Zwei
    -- Minuten mit einem grosszuegigen Trinkgeld waeren 3000 g/h.
    if minutes < C.MIN_MINUTES or not isPositive(session.gross) then
        self:Touch()
        return nil, "zu kurz oder ohne Ertrag"
    end

    local record = {
        k = session.kind,
        s = session.startedAt,
        e = now,
        m = math.floor(minutes * 10 + 0.5) / 10,
        g = math.floor(session.gross + 0.5),
        c = math.floor((session.cost or 0) + 0.5),
        n = session.events or 0,
    }
    -- Tageszeit und Wochentag wandern mit. Ausgewertet werden sie erst, wenn
    -- die Stichprobe es hergibt - gespeichert werden sie ab dem ersten Tag,
    -- weil man sie spaeter nicht mehr rekonstruieren kann.
    if type(date) == "function" then
        local ok, hour = pcall(date, "%H", session.startedAt)
        if ok then record.h = tonumber(hour) end
        local ok2, weekday = pcall(date, "%w", session.startedAt)
        if ok2 then record.w = tonumber(weekday) end
    end

    local sessions = store.sessions
    sessions[#sessions + 1] = record
    while #sessions > C.MAX_SESSIONS do table.remove(sessions, 1) end
    self:Touch()
    if GCP.Personal then
        pcall(GCP.Personal.Touch, GCP.Personal)
    end
    return record
end

-- ---------------------------------------------------------------------------
-- Ereignisse aus dem Income Tracker
--
-- Der Income Tracker meldet jeden Zufluss hierher. Diese Schicht entscheidet,
-- ob daraus eine Sitzung wird - und zwar nur bei Zufluessen, deren Zuordnung
-- belastbar ist. Ein Handel unbekannter Herkunft startet keine Servicesitzung.
-- ---------------------------------------------------------------------------

local SOURCE_KIND = {
    SERVICE_ENCHANT = "service.enchant",
}

function Activity:OnIncome(event)
    if type(event) ~= "table" then return false end
    local kind = SOURCE_KIND[event.source or ""]
    local now = tonumber(event.timestamp) or self:Now()
    local session = self:Current()

    -- Laeuft bereits eine Sitzung dieser Art, zaehlt das Ereignis hinein.
    if session then
        if kind and session.kind == kind then
            self:Tick(now)
            session.gross = (session.gross or 0) + (event.amount or 0)
            session.events = (session.events or 0) + 1
            session.lastEventAt = now
            self:Touch()
            return true
        end
        return false
    end

    if not kind then return false end
    -- Nur belastbar zugeordnete Ereignisse duerfen eine Sitzung starten. Aus
    -- einem einzelnen Goldtransfer unbekannter Herkunft wird keine Methode.
    local C = config()
    if (event.confidence or 0) < GCP.Income.CONFIDENCE.MEDIUM then return false end

    -- Zwei Ereignisse in kurzer Folge starten die Sitzung. Eines allein ist ein
    -- Gefallen, kein Geschaeft - und eine Sitzung aus einem einzigen Trinkgeld
    -- waere eine Rate aus einer Beobachtung.
    self.pending = self.pending or {}
    local pending = {}
    for _, at in ipairs(self.pending) do
        if (now - at) <= C.AUTO_START_WINDOW then pending[#pending + 1] = at end
    end
    pending[#pending + 1] = now
    self.pending = pending
    if #pending < C.AUTO_START_EVENTS then return false end

    -- Die Sitzung beginnt beim ERSTEN der Ereignisse, nicht beim zweiten -
    -- sonst faehrt die gemessene Zeit systematisch zu kurz aus.
    local started = self:Start(kind, pending[1])
    if not started then return false end
    for _, at in ipairs(pending) do
        started.events = (started.events or 0) + 1
        started.lastEventAt = at
    end
    started.gross = (started.gross or 0) + (event.amount or 0)
    self:Tick(now)
    self.pending = nil
    self:Touch()
    return true
end

-- Eigene Materialien, die in einer Sitzung verbraucht wurden. Sie sind
-- wirtschaftliche Kosten, kein Cash-Abfluss - dieselbe Trennung wie ueberall.
function Activity:AddCost(amount, now)
    local session = self:Current()
    if not session or not isPositive(amount) then return false end
    session.cost = (session.cost or 0) + amount
    session.lastEventAt = tonumber(now) or self:Now()
    self:Touch()
    return true
end

-- ---------------------------------------------------------------------------
-- METHODENSTATISTIK
--
-- Die Zahl, um die es geht: Wie viel Gold je aktiver Stunde bringt diese
-- Methode BEI DIESEM SPIELER? Median ueber die Sitzungen, Confidence nach
-- ihrer Zahl.
-- ---------------------------------------------------------------------------

function Activity:ConfidenceOf(sessions)
    local C = config().CONFIDENCE
    sessions = tonumber(sessions) or 0
    if sessions >= C.HIGH_SESSIONS then return "high" end
    if sessions >= C.MEDIUM_SESSIONS then return "medium" end
    if sessions >= C.LOW_SESSIONS then return "low" end
    return "none"
end

function Activity:MethodStats(kind, options)
    local store = self:EnsureStore()
    if not store then return nil end
    options = options or {}
    local rates, minutes, gross = {}, 0, 0
    local count = 0
    local newest = nil
    for _, record in ipairs(store.sessions) do
        local matches = (kind == nil or record.k == kind)
        -- Optionaler Kontextfilter. Er wird nur ausgewertet, wenn die
        -- Stichprobe es hergibt - das prueft der Aufrufer, nicht diese
        -- Funktion.
        if matches and options.hour ~= nil and record.h ~= options.hour then
            matches = false
        end
        if matches and isPositive(record.m) and isPositive(record.g) then
            local net = record.g - (record.c or 0)
            rates[#rates + 1] = net / (record.m / 60)
            minutes = minutes + record.m
            gross = gross + record.g
            count = count + 1
            if not newest or record.e > newest then newest = record.e end
        end
    end
    if count == 0 then return nil end
    return {
        kind = kind,
        sessions = count,
        minutes = minutes,
        gross = gross,
        medianGoldPerHour = median(rates),
        confidence = self:ConfidenceOf(count),
        lastAt = newest,
    }
end

-- Alle Methoden, fuer die es eigene Messungen gibt - inklusive der Farmraten
-- aus Farm.lua. Die liegen dort und werden dort auch gemessen; hier stehen sie
-- nur unter demselben Namen wie alles andere, damit sie vergleichbar werden.
function Activity:AllMethods()
    local store = self:EnsureStore()
    local list = {}
    local seen = {}
    for _, record in ipairs(store and store.sessions or {}) do
        if record.k and not seen[record.k] then
            seen[record.k] = true
            local stats = self:MethodStats(record.k)
            if stats then
                stats.label = config().KIND_LABEL[record.k] or record.k
                list[#list + 1] = stats
            end
        end
    end

    -- Farmen wird von Farm.lua gemessen. Es hier noch einmal zu erfassen,
    -- hiesse dieselbe Sitzung zweimal zu zaehlen.
    if GCP.Farm then
        local zones = GCP.Farm:Zones()
        local best = nil
        for _, zone in ipairs(zones) do
            local rate = GCP.Farm:GetRate(zone)
            if rate and isPositive(rate.medianGoldPerHour) then
                if not best or rate.medianGoldPerHour > best.medianGoldPerHour then
                    best = rate
                end
            end
        end
        if best then
            list[#list + 1] = {
                kind = "farm",
                label = string.format("%s (%s)",
                    config().KIND_LABEL["farm"] or "Farmen", best.zone),
                sessions = best.sessions,
                medianGoldPerHour = best.medianGoldPerHour,
                confidence = best.confidence,
                zone = best.zone,
            }
        end
    end

    table.sort(list, function(a, b)
        local av = a.medianGoldPerHour or 0
        local bv = b.medianGoldPerHour or 0
        if av ~= bv then return av > bv end
        return tostring(a.kind) < tostring(b.kind)
    end)
    return list
end

-- ---------------------------------------------------------------------------
-- KONTEXT: TAGESZEIT
--
-- Langfristig kann eine Methode zu bestimmten Zeiten besser laufen. Das darf
-- aber NICHT programmiert werden ("abends ist Verzaubern gut"), sondern muss
-- aus eigenen Daten entstehen - und nur, wenn die Stichprobe es hergibt.
--
-- Rueckgabe: nil, solange zu wenige Sitzungen in diesem Zeitfenster liegen.
-- ---------------------------------------------------------------------------

function Activity:ContextStats(kind, hour)
    local C = config()
    local scoped = self:MethodStats(kind, { hour = hour })
    -- Ohne genuegend Sitzungen IN DIESEM FENSTER gibt es keine Aussage ueber
    -- dieses Fenster. Das ist der ganze Schutz gegen Ueberanpassung.
    if not scoped or scoped.sessions < C.CONFIDENCE.MEDIUM_SESSIONS then return nil end
    return scoped
end

function Activity:SummaryText()
    local methods = self:AllMethods()
    if #methods == 0 then
        return "Noch keine gemessene Goldmethode – Gold Copilot lernt sie aus "
            .. "deinen eigenen Sitzungen."
    end
    local best = methods[1]
    return string.format("%s: %s/h aus %d Sitzung(en), Datenlage %s",
        best.label or best.kind,
        GCP.Prices:FormatGold(best.medianGoldPerHour or 0),
        best.sessions or 0,
        GCP.Market:ConfidenceLabel(best.confidence))
end
