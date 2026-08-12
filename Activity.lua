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

function Activity:Start(kind, now, mode)
    if type(kind) ~= "string" or kind == "" then return nil end
    local store = self:EnsureStore()
    if not store then return nil end
    local C = config()
    now = tonumber(now) or self:Now()
    -- Eine laufende Sitzung wird abgeschlossen, nicht ueberschrieben: Was
    -- gemessen wurde, bleibt gemessen.
    if store.current then self:Stop("neue Sitzung", now) end
    store.current = {
        kind = kind,
        mode = mode or C.MODE.AUTO,
        startedAt = now,
        lastEventAt = now,
        lastTickAt = now,
        -- Das letzte Lebenszeichen. Es entscheidet, bis wohin gezaehlt wird -
        -- und faellt beim Ausloggen von selbst weg, ohne dass jemand
        -- Offline-Zeit schaetzen muesste.
        lastSeenAt = now,
        activeSeconds = 0,
        gross = 0,
        cost = 0,
        events = 0,
        -- Material-Ledger (1.1.0-beta.3). credit = vom Kunden geliefert,
        -- consumed = beim Zaubern aus den Taschen verbraucht. Erst die
        -- Differenz ist eigener Einsatz.
        credit = {},
        consumed = {},
    }
    self:Touch()
    self:ScheduleHeartbeat()
    -- Ab jetzt braucht es einen Bezugsstand der Taschen: Ohne ihn laesst sich
    -- ein spaeterer Verbrauch nicht messen.
    if GCP.Materials then pcall(GCP.Materials.Refresh, GCP.Materials, now) end
    return store.current
end

-- MANUELLER START (1.1.0-beta.2)
--
-- "Ich stelle mich jetzt nach Shattrath und biete Verzauberungen an." Das ist
-- die einzige Angabe, die eine automatische Erkennung nicht rekonstruieren
-- kann: WANN es losging. Sie ist deshalb keine Bequemlichkeit, sondern die
-- Voraussetzung fuer eine ehrliche Stundenrate.
function Activity:StartManual(kind, now)
    return self:Start(kind or "service.enchant", now, config().MODE.MANUAL)
end

function Activity:IsManual()
    local session = self:Current()
    return session ~= nil and session.mode == config().MODE.MANUAL
end

-- Rechnet diese Sitzungsart nach verstrichener statt nach aktiver Zeit?
function Activity:UsesElapsedTime(session)
    if type(session) ~= "table" then return false end
    return config().ELAPSED_KINDS[session.kind or ""] and true or false
end

-- ---------------------------------------------------------------------------
-- HERZSCHLAG
--
-- Waehrend einer laufenden Sitzung laeuft alle HEARTBEAT Sekunden ein
-- Lebenszeichen. Kein OnUpdate: ein C_Timer, der sich selbst neu einplant und
-- aufhoert, sobald keine Sitzung mehr laeuft - dieselbe Bauweise wie der Guide
-- Viewer.
--
-- Er ist KEINE AFK-Erkennung. Der Client sagt nicht, ob jemand vor dem
-- Bildschirm sitzt, und das wird hier auch nicht behauptet. Er sagt nur, ob
-- der Charakter eingeloggt ist - und genau das genuegt, um Offline-Zeit aus
-- der Messung herauszuhalten.
-- ---------------------------------------------------------------------------
function Activity:ScheduleHeartbeat()
    if self.heartbeatRunning then return end
    if type(C_Timer) ~= "table" or type(C_Timer.After) ~= "function" then return end
    self.heartbeatRunning = true
    local function beat()
        if not self:Current() then
            self.heartbeatRunning = false
            return
        end
        self:Tick()
        C_Timer.After(config().HEARTBEAT, beat)
    end
    C_Timer.After(config().HEARTBEAT, beat)
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
    -- Das Lebenszeichen wandert IMMER mit, auch wenn die Luecke fuer die
    -- aktive Zeit zu gross war. Es beantwortet eine andere Frage: nicht "hat
    -- er gearbeitet", sondern "war er ueberhaupt da".
    --
    -- Und es wandert nur VORWAERTS. Ein Abschluss, der rueckwirkend abrechnet
    -- (Leerlauf, Reload), gibt einen frueheren Zeitpunkt herein - der darf ein
    -- spaeteres Lebenszeichen nicht zuruecknehmen.
    if (session.lastSeenAt or 0) < now then session.lastSeenAt = now end
    return session.activeSeconds or 0
end

-- Die wirtschaftlich eingesetzte Zeit dieser Sitzung, in Sekunden.
--
-- Fuer einen Dienstleistungsstand ist das die VERSTRICHENE Zeit: Warten auf
-- Kunden ist Arbeitszeit. Gezaehlt wird bis zum letzten Lebenszeichen plus
-- einer Karenz - nicht bis zu dem Moment, in dem jemand daran gedacht hat,
-- die Sitzung zu beenden.
function Activity:ElapsedSeconds(session, now)
    if type(session) ~= "table" then return 0 end
    local C = config()
    now = tonumber(now) or self:Now()
    local started = tonumber(session.startedAt) or now
    local seen = tonumber(session.lastSeenAt) or started
    local ceiling = math.min(now, seen + C.GRACE_SECONDS)
    local seconds = math.max(ceiling - started, 0)
    return math.min(seconds, C.MAX_SESSION_MINUTES * 60)
end

-- Die Zeitbasis, mit der diese Sitzung gerechnet wird.
function Activity:SessionSeconds(session, now)
    if type(session) ~= "table" then return 0 end
    if self:UsesElapsedTime(session) then
        return self:ElapsedSeconds(session, now)
    end
    return session.activeSeconds or 0
end

-- Beendet sich die Sitzung von selbst? Wer sie offen laesst und schlafen geht,
-- bekommt keine 8-Stunden-Rate.
function Activity:CheckIdle(now)
    local session = self:Current()
    if not session then return false end
    local C = config()
    now = tonumber(now) or self:Now()
    -- Eine MANUELL gestartete Sitzung haelt laenger durch: Der Spieler hat
    -- ausdruecklich gesagt, dass er jetzt anbietet, und eine zaehe Stunde ist
    -- immer noch eine Stunde. Eine automatisch erkannte kennt diese Absicht
    -- nicht - bei ihr weiss niemand, ob noch jemand dasteht.
    local timeout = (session.mode == C.MODE.MANUAL)
        and C.MANUAL_IDLE_TIMEOUT or C.IDLE_TIMEOUT
    if (now - (session.lastEventAt or session.startedAt)) >= timeout then
        -- Abgerechnet wird bis zum letzten Lebenszeichen, nicht bis zu dem
        -- Moment, in dem der Leerlauf auffiel. Die Karenz kommt in
        -- ElapsedSeconds oben drauf.
        self:Stop("keine Aktivität mehr", session.lastSeenAt or now)
        return true
    end
    return false
end

-- Nach einem Reload oder Login: Eine Sitzung, die noch offen im Speicher
-- steht, wird bis zu ihrem letzten Lebenszeichen abgerechnet. Offline-Zeit
-- faellt damit heraus, ohne dass sie jemand schaetzen muesste - das
-- Lebenszeichen hoert beim Ausloggen einfach auf.
function Activity:RecoverSession(now)
    local session = self:Current()
    if not session then return nil end
    now = tonumber(now) or self:Now()
    local seen = tonumber(session.lastSeenAt) or session.startedAt or now
    if (now - seen) <= config().GRACE_SECONDS then
        -- Kein Bruch: Der Herzschlag laeuft weiter.
        self:ScheduleHeartbeat()
        return nil
    end
    return self:Stop("Sitzung nach Unterbrechung abgerechnet", seen)
end

function Activity:Stop(reason, now)
    local store = self:EnsureStore()
    if not store or not store.current then return nil end
    local C = config()
    now = tonumber(now) or self:Now()
    local session = store.current
    -- Die Zeitbasis haengt an der Sitzungsart: Fuer einen Dienstleistungsstand
    -- ist Warten Arbeitszeit, fuers Farmen nicht.
    --
    -- Bestimmt wird sie VOR dem letzten Tick. Sonst waere jeder Abschluss sein
    -- eigenes Lebenszeichen - und ein Leerlauf, der nach zwei Stunden
    -- auffaellt, brachte zwei Stunden Arbeitszeit mit.
    local seconds = self:SessionSeconds(session, now)
    self:Tick(now)
    store.current = nil

    local minutes = seconds / 60
    -- Eine zu kurze Sitzung ist keine Messung, sondern ein Ausrutscher. Zwei
    -- Minuten mit einem grosszuegigen Trinkgeld waeren 3000 g/h.
    if minutes < C.MIN_MINUTES or not isPositive(session.gross) then
        self:Touch()
        return nil, "zu kurz oder ohne Ertrag"
    end

    -- MATERIALKOSTEN (1.1.0-beta.3). Erst hier steht fest, was der Spieler
    -- wirklich eingesetzt hat: verbraucht minus vom Kunden geliefert.
    -- AddCost-Betraege aus dem Handelsfenster kommen dazu - das ist der
    -- seltenere Fall, in dem der Enchanter Material direkt uebergibt.
    local settlement = GCP.Materials and GCP.Materials:Settle(session) or nil
    local materialCost = settlement and settlement.value or 0
    local costKnown = settlement == nil or settlement.known
    local totalCost = (session.cost or 0) + materialCost

    local record = {
        k = session.kind,
        s = session.startedAt,
        e = now,
        m = math.floor(minutes * 10 + 0.5) / 10,
        g = math.floor(session.gross + 0.5),
        -- Kosten stehen nur da, wenn sie BEKANNT sind. Eine unbekannte
        -- Kostenposition als 0 zu speichern waere schlechter als keine Zahl -
        -- sie saehe aus wie eine Messung.
        c = costKnown and math.floor(totalCost + 0.5) or nil,
        cu = (not costKnown) and 1 or nil,
        n = session.events or 0,
        -- Wie die Sitzung entstanden ist. Nicht wegwerfen: Eine manuell
        -- gestartete kennt ihren Anfang, eine automatisch erkannte nur als
        -- Untergrenze.
        mo = session.mode or C.MODE.AUTO,
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
            session.lastSeenAt = now
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
    --
    -- WICHTIG: Gemerkt wird das GANZE Ereignis, nicht nur sein Zeitpunkt. Bis
    -- 1.1.0-beta.1 stand hier eine Liste aus Zeitstempeln, und beim Start
    -- wurde nur der Betrag des ausloesenden Ereignisses uebernommen - das
    -- erste Trinkgeld war schlicht weg. Aus 20 g + 15 g wurden 15 g bei zwei
    -- gezaehlten Kunden. Ein Messfehler, kein Rundungsproblem.
    self.pending = self.pending or {}
    local pending = {}
    for _, entry in ipairs(self.pending) do
        if (now - entry.at) <= C.AUTO_START_WINDOW then
            pending[#pending + 1] = entry
        end
    end
    pending[#pending + 1] = {
        at = now,
        amount = tonumber(event.amount) or 0,
        confidence = event.confidence,
        source = event.source,
    }
    self.pending = pending
    if #pending < C.AUTO_START_EVENTS then return false end

    -- Die Sitzung beginnt beim ERSTEN der Ereignisse, nicht beim zweiten -
    -- sonst faehrt die gemessene Zeit systematisch zu kurz aus.
    local started = self:Start(kind, pending[1].at)
    if not started then return false end
    -- ALLE gesammelten Ereignisse wandern hinein, jedes genau einmal - auch
    -- das ausloesende, das in pending bereits enthalten ist.
    for _, entry in ipairs(pending) do
        started.events = (started.events or 0) + 1
        started.gross = (started.gross or 0) + (entry.amount or 0)
        started.lastEventAt = entry.at
    end
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
-- LIVE-ANZEIGE DER LAUFENDEN SITZUNG (1.1.0-beta.2)
--
-- Nur reale Daten, keine Hochrechnung auf kuenftige Kunden: Netto geteilt
-- durch die bisherige Dauer. Was danach passiert, weiss niemand.
-- ---------------------------------------------------------------------------

function Activity:LiveStats(now)
    local session = self:Current()
    if not session then return nil end
    now = tonumber(now) or self:Now()
    local seconds = self:SessionSeconds(session, now)
    local gross = session.gross or 0
    -- Auch live gilt: verbraucht minus vom Kunden geliefert, plus was direkt
    -- uebergeben wurde.
    local settlement = GCP.Materials and GCP.Materials:Settle(session) or nil
    local cost = (session.cost or 0) + (settlement and settlement.value or 0)
    local costKnown = settlement == nil or settlement.known
    local stats = {
        kind = session.kind,
        label = config().KIND_LABEL[session.kind or ""] or session.kind,
        mode = session.mode,
        modeLabel = config().MODE_LABEL[session.mode or config().MODE.AUTO],
        startedAt = session.startedAt,
        seconds = seconds,
        minutes = seconds / 60,
        events = session.events or 0,
        gross = gross,
        cost = cost,
        net = gross - cost,
        costKnown = costKnown,
        costNote = settlement and GCP.Materials:Describe(settlement) or nil,
    }
    -- Eine Stundenrate erst, wenn die Sitzung lange genug laeuft. Aus drei
    -- Minuten und einem Trinkgeld eine Rate zu bilden, waere die
    -- unehrlichste Zahl der ganzen Oberflaeche.
    if seconds >= config().MIN_MINUTES * 60 then
        -- Ohne bekannte Materialkosten ist das eine BRUTTOrate. Sie wird
        -- angezeigt, aber sie heisst auch so.
        stats.goldPerHour = stats.net / (seconds / 3600)
        stats.rateIsGross = not costKnown
    end
    return stats
end

function Activity:LiveText(now)
    local live = self:LiveStats(now)
    if not live then return nil end
    local money = function(value) return GCP.Prices:FormatGold(value or 0) end
    local text = string.format("%s · %d Min · %d Kunde(n) · brutto %s",
        live.label, math.floor(live.minutes), live.events, money(live.gross))
    if live.cost > 0 then
        text = text .. string.format(" · eigene Mats %s · netto %s",
            money(live.cost), money(live.net))
    end
    if not live.costKnown then
        text = text .. " · Materialkosten unbekannt"
    end
    if live.goldPerHour then
        text = text .. string.format(" · aktuell %s/h%s", money(live.goldPerHour),
            live.rateIsGross and " (brutto)" or "")
    else
        text = text .. " · für eine Stundenrate läuft sie noch zu kurz"
    end
    return text
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
    local count, grossOnly = 0, 0
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
            -- NETTO, nicht brutto: Was der Kunde zahlt, minus dem, was an
            -- eigenem Material darin steckt. Kundenmaterial taucht hier gar
            -- nicht auf - es war nie Einkommen und ist auch keine Kosten.
            --
            -- Sitzungen mit UNBEKANNTEN Materialkosten (cu) liefern nur eine
            -- Bruttorate. Sie zaehlen weiter mit - ihre Zeit und ihr Ertrag
            -- sind gemessen -, aber die ganze Methode gilt dann als brutto und
            -- wird oben entsprechend gekennzeichnet. Ihre Kosten mit null
            -- anzusetzen waere die stillste Falschaussage von allen.
            if record.cu then grossOnly = grossOnly + 1 end
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
        -- Ist die Rate netto? Nur, wenn zu JEDER Sitzung die Materialkosten
        -- bekannt waren. Eine einzige unbekannte macht die Aussage brutto -
        -- und das steht dann auch dran.
        netKnown = grossOnly == 0,
        grossOnlySessions = grossOnly,
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
