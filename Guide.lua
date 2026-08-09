local addonName, GCP = ...

GCP.Guide = {}
local Guide = GCP.Guide

local GetItemInfoCompat = (C_Item and C_Item.GetItemInfo) or GetItemInfo

-- ---------------------------------------------------------------------------
-- GUIDE ENGINE (0.9.0)
--
-- Alles davor beantwortet Fragen. Dieses Modul gibt Anweisungen.
--
--     SCHRITT 3 / 11
--     KAUFE 20x URFEUER
--     Maximal 21 g 00 s / Stück
--
-- Der Guide haelt fest, wo im Plan der Spieler steht, hakt ab, was der Client
-- zweifelsfrei bestaetigt, und plant neu, wenn der Plan nicht mehr stimmt.
--
-- WAS AUTOMATISCH ABGEHAKT WIRD - und nur das:
--   GO_TO Auktionshaus  -> AUCTION_HOUSE_SHOW
--   GO_TO Bank          -> BANKFRAME_OPENED
--   GO_TO Briefkasten   -> MAIL_SHOW
--   GO_TO Beruf         -> TRADE_SKILL_SHOW / CRAFT_SHOW
--   GO_TO Farmgebiet    -> Zonenwechsel in die richtige Zone
--   KAUFEN              -> bestaetigter Kauf im Ledger, sonst Bestandszuwachs
--   HERSTELLEN/UMWANDELN-> Bestandszuwachs um die erwartete Menge
--   EINSTELLEN          -> bestaetigtes Einstellen im Ledger
--
-- WAS NICHT AUTOMATISCH ABGEHAKT WIRD:
--   Alles, was der Client nicht eindeutig meldet. Ein Entzauberergebnis, ein
--   Haendlerkauf, ein Farmblock ohne Zielmenge. Dort steht [ERLEDIGT], und
--   wer ihn drueckt, bekommt einen Schritt, der als MANUELL erledigt gilt -
--   nicht als bestaetigt. Der Unterschied steht in den Daten und im Protokoll.
--
-- ZUSTANDSAUTOMAT
--
--   IDLE ---------- Plan() ---------> PLANNING --- Route steht ---> ACTIVE
--   ACTIVE -------- Pause() --------> PAUSED ----- Resume() ------> ACTIVE
--   ACTIVE -------- alle Schritte --> COMPLETED
--   ACTIVE -------- Trigger --------> REPLANNING -- neue Route ---> ACTIVE
--   ACTIVE -------- WAIT-Schritt ---> WAITING ---- Bedingung -----> ACTIVE
--   beliebig ------ Abort() --------> IDLE
--
-- Der Zustand liegt in den SavedVariables: Ein /reload mitten in der Route
-- darf weder den Fortschritt noch die bereits erledigten Schritte kosten.
-- ---------------------------------------------------------------------------

local function config()
    return GCP.Constants.GUIDE
end

Guide.STATES = {
    IDLE = "IDLE", PLANNING = "PLANNING", ACTIVE = "ACTIVE", WAITING = "WAITING",
    REPLANNING = "REPLANNING", COMPLETED = "COMPLETED", PAUSED = "PAUSED",
}

Guide.STATE_LABEL = {
    IDLE = "bereit", PLANNING = "plant", ACTIVE = "läuft", WAITING = "wartet",
    REPLANNING = "plant neu", COMPLETED = "fertig", PAUSED = "pausiert",
}

Guide.revision = 0
Guide.route = nil               -- die laufende Route (Laufzeitobjekt)
Guide.baseline = nil            -- Bestandsstand beim Start des aktuellen Schritts
Guide.lastReplan = nil
Guide.interrupt = nil
Guide.lastInterruptAt = nil

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

local function clockSeconds()
    if type(GetTime) == "function" then
        local ok, value = pcall(GetTime)
        if ok and type(value) == "number" then return value end
    end
    return now()
end

function Guide:Touch()
    self.revision = self.revision + 1
end

-- ---------------------------------------------------------------------------
-- Speicher
--
--   db.guide = {
--       version = 1,
--       state = "ACTIVE",
--       routeID = "r3", revision = 3, startedAt = ..., profile = "QUICK_GOLD",
--       budgetMinutes = 90, risk = "medium", goal = 5000000,
--       steps = { <kompakte Schrittkopie>, ... },
--       progress = { ["r3:a1"] = { at = ..., auto = true } },
--       skipped = { ["r3:a4"] = ... },
--       currentIndex = 4,
--       activeSeconds = 812, lastTickAt = ...,
--       replans = 2, startGold = 4200000,
--   }
--
-- Die Schritte liegen mit im Speicher, nicht nur die Fortschrittsmarken. Nach
-- einem /reload waere eine neu geplante Route eine ANDERE Route - und die
-- Haken darin waeren geraten.
-- ---------------------------------------------------------------------------

function Guide:EnsureStore()
    local db = GCP.db
    if not db then return nil end
    local C = config()
    local profile = GCP:Profile()
    local store = profile.guide
    if type(store) ~= "table" or store.version ~= C.STORE_VERSION then
        store = { version = C.STORE_VERSION, state = Guide.STATES.IDLE }
        profile.guide = store
    end
    if type(store.steps) ~= "table" then store.steps = {} end
    if type(store.progress) ~= "table" then store.progress = {} end
    if type(store.skipped) ~= "table" then store.skipped = {} end
    if type(store.state) ~= "string" or not Guide.STATES[store.state] then
        store.state = Guide.STATES.IDLE
    end
    if type(store.currentIndex) ~= "number" or store.currentIndex < 1 then
        store.currentIndex = 1
    end
    if type(store.activeSeconds) ~= "number" then store.activeSeconds = 0 end
    if type(store.replans) ~= "number" then store.replans = 0 end
    return store
end

function Guide:GetState()
    local store = self:EnsureStore()
    return store and store.state or Guide.STATES.IDLE
end

function Guide:SetState(state)
    local store = self:EnsureStore()
    if not store or not Guide.STATES[state] then return false end
    if store.state == state then return false end
    store.state = state
    self:Touch()
    return true
end

-- "Laeuft" heisst: Es gibt eine Route, an der weitergearbeitet werden kann -
-- auch pausiert. "Aktiv" heisst: Der Spieler arbeitet gerade daran. Nur im
-- aktiven Zustand wird automatisch abgehakt; wer pausiert hat, will nicht,
-- dass ihm die Route unter den Fingern weiterlaeuft.
function Guide:IsRunning()
    local state = self:GetState()
    return state == Guide.STATES.ACTIVE or state == Guide.STATES.WAITING
        or state == Guide.STATES.PAUSED or state == Guide.STATES.REPLANNING
end

function Guide:IsActive()
    local state = self:GetState()
    return state == Guide.STATES.ACTIVE or state == Guide.STATES.WAITING
end

-- ---------------------------------------------------------------------------
-- Schritte speichern und laden
--
-- Bewusst eine flache Kopie mit genau den Feldern, die der Viewer und die
-- Pruefung brauchen. Die Chance dahinter wird NICHT mitgespeichert: Sie ist
-- eine Momentaufnahme des Marktes und waere nach einem Reload ohnehin veraltet.
-- ---------------------------------------------------------------------------

local STEP_FIELDS = {
    "id", "type", "itemID", "quantity", "maxBuyPrice", "minSellPrice",
    "capitalRequired", "expectedProfit", "expectedMinutes", "confidence",
    "completionCondition", "optional", "groupID", "title", "detail", "travel",
}

function Guide:PackStep(step)
    local packed = {}
    for _, field in ipairs(STEP_FIELDS) do packed[field] = step[field] end
    if step.location then
        packed.location = {
            kind = step.location.kind, key = step.location.key,
            label = step.location.label,
        }
    end
    if type(step.dependencies) == "table" and #step.dependencies > 0 then
        packed.dependencies = {}
        for index, id in ipairs(step.dependencies) do packed.dependencies[index] = id end
    end
    if type(step.meta) == "table" then
        packed.meta = { gain = step.meta.gain, zone = step.meta.zone }
    end
    return packed
end

-- Uebernimmt eine frisch geplante Route. Bereits erledigte Schritte bleiben
-- stehen und werden der neuen Route vorangestellt - der Fortschritt einer
-- Sitzung darf durch eine Neuplanung nicht verschwinden.
function Guide:Adopt(route, options)
    options = options or {}
    local store = self:EnsureStore()
    if not store then return false end

    local prefix = {}
    if options.keepCompleted then
        for _, step in ipairs(store.steps) do
            if store.progress[step.id] or store.skipped[step.id] then
                prefix[#prefix + 1] = step
            end
        end
    else
        store.progress = {}
        store.skipped = {}
        store.activeSeconds = 0
        store.startedAt = now()
        store.startGold = (type(GetMoney) == "function" and GetMoney()) or nil
    end

    local steps = {}
    for _, step in ipairs(prefix) do steps[#steps + 1] = step end
    for _, step in ipairs(route.steps) do
        local packed = self:PackStep(step)
        -- Schritt-IDs bekommen die Routennummer davor: Zwei Routen in einer
        -- Sitzung haetten sonst beide ein "a3", und der Haken landete am
        -- falschen Schritt.
        packed.id = route.id .. ":" .. tostring(packed.id or (#steps + 1))
        if packed.dependencies then
            for index, id in ipairs(packed.dependencies) do
                packed.dependencies[index] = route.id .. ":" .. id
            end
        end
        packed.groupID = packed.groupID and (route.id .. ":" .. packed.groupID) or nil
        steps[#steps + 1] = packed
    end

    store.steps = steps
    store.routeID = route.id
    store.revision = route.revision
    store.profile = route.profile
    store.budgetMinutes = route.budgetMinutes
    store.risk = route.risk
    store.goal = route.goal and route.goal.target or nil
    store.plannedProfit = route.totals.profit
    store.plannedCapital = route.totals.capital
    store.plannedMinutes = route.totals.minutes
    store.confidence = route.confidence
    store.currentIndex = self:FirstOpenIndex(store)
    store.lastTickAt = clockSeconds()
    self.route = route
    self:CaptureBaseline()
    self:Touch()
    return true
end

function Guide:FirstOpenIndex(store)
    store = store or self:EnsureStore()
    for index, step in ipairs(store.steps) do
        if not store.progress[step.id] and not store.skipped[step.id] then
            return index
        end
    end
    return #store.steps + 1
end

function Guide:CurrentStep()
    local store = self:EnsureStore()
    if not store then return nil end
    return store.steps[store.currentIndex], store.currentIndex
end

function Guide:StepCount()
    local store = self:EnsureStore()
    return store and #store.steps or 0
end

function Guide:DoneCount()
    local store = self:EnsureStore()
    if not store then return 0, 0 end
    local done, skipped = 0, 0
    for _, step in ipairs(store.steps) do
        if store.progress[step.id] then done = done + 1
        elseif store.skipped[step.id] then skipped = skipped + 1 end
    end
    return done, skipped
end

-- ---------------------------------------------------------------------------
-- Start und Ende
-- ---------------------------------------------------------------------------

function Guide:Start(options)
    local store = self:EnsureStore()
    if not store then return nil, "keine Datenbank" end
    self:SetState(Guide.STATES.PLANNING)
    local route = GCP.Route:Plan(options)
    if #route.steps == 0 then
        self:SetState(Guide.STATES.IDLE)
        return route, route.warnings[1] or "keine passende Chance gefunden"
    end
    store.options = {
        profile = options and options.profile,
        minutes = options and options.minutes,
        risk = options and options.risk,
        goal = options and options.goal,
        types = options and options.types,
        capital = options and options.capital,
    }
    self:Adopt(route, { keepCompleted = false })
    self:SetState(Guide.STATES.ACTIVE)
    self:SyncNavigation()
    return route
end

-- Nach einem /reload oder einem neuen Login. Die Schritte stehen in den
-- SavedVariables und werden NICHT neu geplant - eine neu geplante Route waere
-- eine andere, und die Haken darin waeren geraten. Neu gerechnet wird nur der
-- Zeitzaehler: Zwischen Ausloggen und Einloggen war der Spieler nicht aktiv.
function Guide:Restore()
    local store = self:EnsureStore()
    if not store then return false end
    store.lastTickAt = clockSeconds()
    if #store.steps == 0 then
        store.state = Guide.STATES.IDLE
        store.currentIndex = 1
        return false
    end
    -- Eine Route, die beim Ausloggen lief, laeuft weiter - aber pausiert:
    -- Wer nach zwei Tagen wieder einloggt, soll nicht mitten in Schritt 7
    -- stehen, ohne es zu merken.
    if store.state == Guide.STATES.ACTIVE or store.state == Guide.STATES.WAITING
        or store.state == Guide.STATES.REPLANNING then
        store.state = Guide.STATES.PAUSED
    end
    store.currentIndex = self:FirstOpenIndex(store)
    if store.currentIndex > #store.steps then
        store.state = Guide.STATES.COMPLETED
    end
    self:CaptureBaseline()
    self:Touch()
    return true
end

function Guide:Abort()
    local store = self:EnsureStore()
    if not store then return false end
    store.state = Guide.STATES.IDLE
    store.steps = {}
    store.progress = {}
    store.skipped = {}
    store.currentIndex = 1
    self.route = nil
    self.interrupt = nil
    if GCP.Navigation then GCP.Navigation:SetTarget(nil) end
    self:Touch()
    return true
end

function Guide:Pause()
    if not self:IsRunning() then return false end
    self:Tick()
    return self:SetState(Guide.STATES.PAUSED)
end

function Guide:Resume()
    if self:GetState() ~= Guide.STATES.PAUSED then return false end
    local store = self:EnsureStore()
    store.lastTickAt = clockSeconds()
    self:SetState(Guide.STATES.ACTIVE)
    self:SyncNavigation()
    return true
end

-- Aktive Zeit. Gezaehlt wird nur, waehrend die Route laeuft - eine Pause und
-- ein Ausloggen zaehlen nicht mit. Der Tick wird von der Oberflaeche und von
-- jedem Schrittwechsel angestossen, nicht von einem OnUpdate.
function Guide:Tick()
    local store = self:EnsureStore()
    if not store then return 0 end
    local nowClock = clockSeconds()
    if store.state == Guide.STATES.ACTIVE or store.state == Guide.STATES.WAITING then
        local last = store.lastTickAt
        if type(last) == "number" then
            local delta = nowClock - last
            -- Ein Sprung ueber die Pausenschwelle ist keine aktive Zeit,
            -- sondern eine Unterbrechung (AFK, Ladebildschirm, Reload).
            if delta > 0 and delta < config().MAX_TICK_SECONDS then
                store.activeSeconds = store.activeSeconds + delta
            end
        end
    end
    store.lastTickAt = nowClock
    return store.activeSeconds
end

function Guide:ActiveMinutes()
    local store = self:EnsureStore()
    if not store then return 0 end
    return store.activeSeconds / 60
end

-- ---------------------------------------------------------------------------
-- Schritte abschliessen
-- ---------------------------------------------------------------------------

function Guide:Complete(stepID, auto)
    local store = self:EnsureStore()
    if not store then return false end
    local step, index = nil, nil
    for position, candidate in ipairs(store.steps) do
        if candidate.id == stepID then step, index = candidate, position break end
    end
    if not step then return false end
    if store.progress[stepID] or store.skipped[stepID] then return false end
    self:Tick()
    store.progress[stepID] = { at = now(), auto = auto and true or false }
    if step.groupID then
        store.groupProgress = store.groupProgress or {}
        store.groupProgress[step.groupID] = (store.groupProgress[step.groupID] or 0) + 1
    end
    -- Provenance der entstehenden Position: Die Guide Engine ist die einzige
    -- Stelle, die weiss, aus welcher Chance ein Kauf stammt.
    if step.type == "BUY" and step.itemID and GCP.Capital then
        local group = self:GroupOf(step)
        GCP.Capital:RememberPositionMeta(step.itemID, {
            opportunityType = group and group.type or nil,
            phase = group and group.phase or nil,
            catalystIDs = group and group.catalystIDs or nil,
        })
    end
    self:Advance()
    self:Touch()
    return true
end

function Guide:Skip(stepID)
    local store = self:EnsureStore()
    if not store then return false end
    local found = nil
    for _, step in ipairs(store.steps) do
        if step.id == stepID then found = step break end
    end
    if not found then return false end
    if store.progress[stepID] or store.skipped[stepID] then return false end
    self:Tick()
    store.skipped[stepID] = { at = now() }
    -- Alles, was auf diesem Schritt aufbaut, ist damit ebenfalls hinfaellig.
    -- Es wird uebersprungen und nicht etwa als erledigt gefuehrt.
    self:SkipDependents(store, stepID)
    if GCP.Personal then GCP.Personal:RecordSkip(found) end
    self:Advance()
    self:RequestReplan("step_skipped")
    self:Touch()
    return true
end

function Guide:SkipDependents(store, stepID)
    local changed = true
    local skippedIDs = { [stepID] = true }
    while changed do
        changed = false
        for _, step in ipairs(store.steps) do
            if not store.skipped[step.id] and not store.progress[step.id] then
                for _, dependency in ipairs(step.dependencies or {}) do
                    if skippedIDs[dependency] then
                        store.skipped[step.id] = { at = now(), cascade = true }
                        skippedIDs[step.id] = true
                        changed = true
                        break
                    end
                end
            end
        end
    end
end

function Guide:Advance()
    local store = self:EnsureStore()
    if not store then return end
    store.currentIndex = self:FirstOpenIndex(store)
    if store.currentIndex > #store.steps then
        self:SetState(Guide.STATES.COMPLETED)
        if GCP.Navigation then GCP.Navigation:SetTarget(nil) end
        if GCP.Personal then GCP.Personal:RecordRouteFinished(self:Progress()) end
        return
    end
    if store.state == Guide.STATES.WAITING then
        self:SetState(Guide.STATES.ACTIVE)
    end
    self:CaptureBaseline()
    self:SyncNavigation()
end

function Guide:GroupOf(step)
    if not step or not step.groupID or not self.route then return nil end
    local plain = tostring(step.groupID):gsub("^[^:]+:", "")
    for _, group in ipairs(self.route.groups or {}) do
        if group.id == plain then return group end
    end
    return nil
end

-- ---------------------------------------------------------------------------
-- Automatische Erkennung
--
-- Grundsatz: Nur abhaken, was der Client zweifelsfrei sagt. Fuer alles, was
-- ueber Bestandsaenderungen laeuft, wird beim Betreten des Schritts ein
-- Bezugswert genommen; abgehakt wird erst, wenn der Zuwachs die erwartete
-- Menge erreicht. Ein zufaellig gelooteter Stapel kann einen Kaufschritt
-- dadurch zwar abschliessen - deshalb hat der Kauf zusaetzlich den
-- Ledger-Beleg, und der zaehlt staerker.
-- ---------------------------------------------------------------------------

function Guide:CountInBags(itemID)
    if not itemID then return 0 end
    if type(GetItemCount) == "function" then
        local ok, count = pcall(GetItemCount, itemID)
        if ok and type(count) == "number" then return count end
    end
    local inventory = GCP.Inventory:ScanBags({})
    local entry = inventory[itemID]
    return entry and entry.count or 0
end

function Guide:CaptureBaseline()
    local step = self:CurrentStep()
    self.baseline = nil
    if not step then return end
    if step.itemID then
        self.baseline = { itemID = step.itemID, count = self:CountInBags(step.itemID),
            at = now() }
    end
end

function Guide:SyncNavigation()
    if not GCP.Navigation then return nil end
    local step = self:CurrentStep()
    if not step or not step.location then
        GCP.Navigation:SetTarget(nil)
        return nil
    end
    return GCP.Navigation:SetTarget(step.location)
end

local LOCATION_EVENT = {
    AUCTION_HOUSE_SHOW = "AT_AUCTION_HOUSE",
    BANKFRAME_OPENED = "AT_BANK",
    MAIL_SHOW = "AT_MAILBOX",
    TRADE_SKILL_SHOW = "AT_PROFESSION",
    CRAFT_SHOW = "AT_PROFESSION",
}

function Guide:OnEvent(event, ...)
    if not self:IsActive() then return false end
    local step = self:CurrentStep()
    if not step then return false end

    local condition = LOCATION_EVENT[event]
    if condition and step.completionCondition == condition then
        return self:Complete(step.id, true)
    end

    if event == "ZONE_CHANGED_NEW_AREA"
        and step.completionCondition == "IN_ZONE" then
        local zone = GCP.Navigation and GCP.Navigation:ZoneName()
        local wanted = step.meta and step.meta.zone
        if wanted == nil or (zone and zone == wanted) then
            return self:Complete(step.id, true)
        end
    end

    if event == "BAG_UPDATE_DELAYED" or event == "BAG_UPDATE" then
        return self:CheckInventoryCompletion()
    end
    return false
end

function Guide:CheckInventoryCompletion()
    local step = self:CurrentStep()
    if not step or not self.baseline then return false end
    if step.completionCondition ~= "ITEM_COUNT"
        and step.completionCondition ~= "LEDGER_PURCHASE" then
        return false
    end
    local gain = step.meta and step.meta.gain
    if not isPositive(gain) then return false end
    local count = self:CountInBags(self.baseline.itemID)
    if (count - self.baseline.count) >= gain then
        return self:Complete(step.id, true)
    end
    return false
end

-- Vom Ledger gemeldet: bestaetigter Kauf, bestaetigtes Einstellen. Das ist der
-- staerkste verfuegbare Beleg - er kommt aus dem Client selbst und nicht aus
-- einer Bestandsdifferenz.
function Guide:OnLedgerEvent(kind, info)
    if not self:IsActive() then return false end
    local step = self:CurrentStep()
    if not step or type(info) ~= "table" then return false end
    if kind == "purchase" and step.completionCondition == "LEDGER_PURCHASE"
        and step.itemID and info.itemID == step.itemID then
        return self:Complete(step.id, true)
    end
    if kind == "post" and step.completionCondition == "AUCTION_POSTED"
        and step.itemID and info.itemID == step.itemID then
        return self:Complete(step.id, true)
    end
    return false
end

-- ---------------------------------------------------------------------------
-- Fortschritt
-- ---------------------------------------------------------------------------

function Guide:Progress()
    local store = self:EnsureStore()
    if not store then return nil end
    local done, skipped = self:DoneCount()
    local remaining, remainingProfit, remainingMinutes, remainingCapital = 0, 0, 0, 0
    for _, step in ipairs(store.steps) do
        if not store.progress[step.id] and not store.skipped[step.id] then
            remaining = remaining + 1
            remainingProfit = remainingProfit + (step.expectedProfit or 0)
            remainingMinutes = remainingMinutes + (step.expectedMinutes or 0)
            remainingCapital = remainingCapital + (step.capitalRequired or 0)
        end
    end

    -- Realisiert: nur, was das Ledger bestaetigt hat, und nur seit dem Start
    -- der Route. Eine Schaetzung aus Goldbewegungen waere hier wertlos - wer
    -- zwischendurch eine Quest abgibt, haette "Routengewinn".
    local realized, spent = nil, nil
    if GCP.Ledger and store.startedAt then
        realized, spent = self:RealizedSince(store.startedAt)
    end

    return {
        state = store.state,
        stateLabel = Guide.STATE_LABEL[store.state],
        step = store.currentIndex,
        steps = #store.steps,
        done = done,
        skipped = skipped,
        remaining = remaining,
        remainingProfit = remainingProfit,
        remainingMinutes = remainingMinutes,
        remainingCapital = remainingCapital,
        plannedProfit = store.plannedProfit,
        plannedMinutes = store.plannedMinutes,
        plannedCapital = store.plannedCapital,
        activeMinutes = store.activeSeconds / 60,
        goal = store.goal,
        confidence = store.confidence,
        realizedNet = realized,
        spentCapital = spent,
        replans = store.replans,
    }
end

-- Bestaetigte Ein- und Verkaeufe seit einem Zeitpunkt. Rueckgabe: Nettoerloes
-- und Einkaufskosten - bewusst getrennt, weil ein Gewinn erst feststeht, wenn
-- beide dasselbe Item betreffen. Der Guide zeigt beide Zahlen nebeneinander
-- und behauptet keine Differenz, die er nicht belegen kann.
function Guide:RealizedSince(timestamp)
    local Ledger = GCP.Ledger
    if not Ledger then return nil, nil end
    local store = Ledger:EnsureStore()
    if not store then return nil, nil end
    local stride = 8
    local events = store.events
    local revenue, cost = 0, 0
    for base = 0, #events - stride, stride do
        local kind = events[base + 1]
        local minute = events[base + 2]
        local stamp = (store.epoch or 0) + minute * 60
        if stamp >= timestamp then
            local quantity = events[base + 4]
            local unitNet = events[base + 6]
            local unitPrice = events[base + 5]
            if kind == Ledger.KIND.SALE then
                revenue = revenue + (unitNet or 0) * math.max(quantity or 1, 1)
            elseif kind == Ledger.KIND.PURCHASE then
                cost = cost + (unitPrice or 0) * math.max(quantity or 1, 1)
            end
        end
    end
    return revenue, cost
end

-- ---------------------------------------------------------------------------
-- NEUPLANUNG
--
-- Ausgeloest wird sie von Ereignissen, nicht von einer Uhr. Ausgefuehrt wird
-- sie gedrosselt und nur, wenn der neue Plan MATERIELL besser ist
-- (Route:ShouldReplace). Beides zusammen ist der Unterschied zwischen einem
-- Guide, dem man folgen kann, und einer Liste, die bei jeder Preisbewegung
-- die Reihenfolge tauscht.
-- ---------------------------------------------------------------------------

Guide.REPLAN_REASONS = {
    market_revision = "Neue Marktdaten",
    opportunity_invalid = "Chance nicht mehr gültig",
    price_above_max = "Preis über deiner Einstiegszone",
    price_below_min = "Preis unter dem geplanten Mindestpreis",
    item_unavailable = "Item nicht verfügbar",
    capital_changed = "Kapital verändert",
    step_skipped = "Schritt übersprungen",
    craft_impossible = "Herstellung nicht möglich",
    inventory_changed = "Bestand unerwartet verändert",
    strong_opportunity = "Deutlich bessere Chance",
    time_budget = "Zeitbudget läuft aus",
}

function Guide:RequestReplan(reason)
    local store = self:EnsureStore()
    if not store or not self:IsRunning() then return false, "nicht aktiv" end
    local C = GCP.Constants.ROUTE.REPLAN
    local nowClock = clockSeconds()
    if self.lastReplan and (nowClock - self.lastReplan) < C.MIN_INTERVAL then
        return false, "gedrosselt"
    end
    if store.replans >= C.MAX_PER_SESSION then
        return false, "Neuplanungsgrenze erreicht"
    end
    self.pendingReason = reason
    return self:Replan(reason)
end

function Guide:Replan(reason)
    local store = self:EnsureStore()
    if not store then return false end
    local previousState = store.state
    self:SetState(Guide.STATES.REPLANNING)
    self.lastReplan = clockSeconds()

    -- Was bleibt uebrig? Zeit und Kapital der laufenden Sitzung, nicht die
    -- Ausgangswerte. Eine Neuplanung, die wieder 90 Minuten verplant, waere
    -- keine Anpassung, sondern eine neue Route.
    local progress = self:Progress()
    local minutesLeft = math.max((store.budgetMinutes or 60) - progress.activeMinutes, 5)
    local options = {}
    for key, value in pairs(store.options or {}) do options[key] = value end
    options.minutes = minutesLeft
    if isPositive(store.goal) then
        local achieved = progress.realizedNet or 0
        options.goal = math.max(store.goal - achieved, 0)
    end

    local candidate = GCP.Route:Plan(options)
    local invalid = reason ~= "market_revision" and reason ~= "strong_opportunity"
    local should, why = GCP.Route:ShouldReplace(
        { totals = { profit = progress.remainingProfit }, remainingProfit = progress.remainingProfit },
        candidate, invalid and "invalid" or nil)

    if not should or #candidate.steps == 0 then
        self:SetState(previousState == Guide.STATES.REPLANNING
            and Guide.STATES.ACTIVE or previousState)
        return false, why
    end

    store.replans = store.replans + 1
    self:Adopt(candidate, { keepCompleted = true })
    self:SetState(Guide.STATES.ACTIVE)
    self.lastReplanReason = reason
    self.lastReplanNote = self.REPLAN_REASONS[reason] or reason
    return true, why
end

-- Prueft die laufende Route gegen den aktuellen Markt und loest bei Bedarf
-- eine Neuplanung aus. Wird von der Oberflaeche und beim Betreten des
-- Auktionshauses aufgerufen - nicht in einer Schleife.
function Guide:Verify()
    if not self:IsActive() then return true end
    local store = self:EnsureStore()
    local step = self:CurrentStep()
    if not step then return true end
    local ok, reason = GCP.Route:ValidateStep(step)
    if ok then return true end
    self.lastProblem = {
        step = step, reason = reason,
        text = GCP.Route:DescribeProblem({ step = step, reason = reason,
            price = step.itemID and GCP.Prices:GetMarketPrice(step.itemID) or nil }),
    }
    self:RequestReplan(reason)
    return false, reason
end

-- ---------------------------------------------------------------------------
-- OPPORTUNITY INTERRUPTS
--
-- Waehrend einer Route kann eine aussergewoehnlich gute Chance auftauchen. Der
-- Guide bietet sie an, uebernimmt sie aber nicht von selbst: Wer einer Route
-- folgt, will nicht, dass sie sich unter ihm veraendert. Auto-Insert ist
-- abschaltbar und standardmaessig AUS.
-- ---------------------------------------------------------------------------

function Guide:CheckInterrupt()
    if not self:IsActive() then return nil end
    local C = GCP.Constants.ROUTE.INTERRUPT
    local nowClock = clockSeconds()
    if self.lastInterruptAt and (nowClock - self.lastInterruptAt) < C.COOLDOWN then
        return nil
    end
    local store = self:EnsureStore()
    local inRoute = {}
    for _, step in ipairs(store.steps) do
        if step.itemID then inRoute[step.itemID] = true end
    end

    local report = GCP.Opportunity:BuildReport()
    local currentStep = self:CurrentStep()
    local currentValue = (currentStep and currentStep.expectedProfit or 0)
    local best = nil
    for _, opportunity in ipairs(report.opportunities or {}) do
        if opportunity.execution and not inRoute[opportunity.itemID]
            and (opportunity.opportunityScore or 0) >= C.MIN_SCORE
            and (opportunity.expectedProfit or 0) >= C.MIN_PROFIT
            and (currentValue <= 0
                or opportunity.expectedProfit >= currentValue * C.MIN_ADVANTAGE) then
            if not best or opportunity.expectedProfit > best.expectedProfit then
                best = opportunity
            end
        end
    end
    if not best then return nil end

    self.lastInterruptAt = nowClock
    self.interrupt = {
        opportunity = best,
        at = now(),
        extraMinutes = GCP.Route:MinutesPerUnit(best) or 1,
        text = string.format("%s – theoretische Marge %s",
            best.title or "Neue Chance", GCP.Prices:FormatGold(best.expectedProfit)),
    }
    if GCP.db and GCP.db.options.guideAutoInsert then
        self:AcceptInterrupt()
    end
    return self.interrupt
end

function Guide:AcceptInterrupt()
    local interrupt = self.interrupt
    if not interrupt then return false end
    local store = self:EnsureStore()
    local opportunity = interrupt.opportunity
    local snapshot = GCP.Capital:GetSnapshot()
    local sizing = GCP.Capital:SizePosition({
        unitCost = opportunity.cost,
        investable = snapshot.availableGold,
        exposureBase = snapshot.exposureBase,
        score = opportunity.opportunityScore,
        confidence = opportunity.confidence,
        liquidityScore = opportunity.liquidityScore,
        volatility = opportunity.volatility,
        risk = store.risk,
    })
    if not sizing then
        self.interrupt = nil
        return false, "Kapital reicht nicht"
    end
    local plan = GCP.Execution:BuildPlan({ {
        opportunity = opportunity, key = opportunity.key, type = opportunity.type,
        itemID = opportunity.itemID, title = opportunity.title,
        units = sizing.units, unitCost = sizing.unitCost, capital = sizing.capital,
        expectedProfit = opportunity.expectedProfit * sizing.units,
        confidence = opportunity.confidence,
    } })
    if #plan.actions == 0 then
        self.interrupt = nil
        return false, "kein Bauplan"
    end

    -- Direkt hinter dem aktuellen Schritt einsetzen, mit eigenem ID-Praefix.
    local prefix = "i" .. tostring(store.replans or 0) .. tostring(#store.steps)
    local inserted = {}
    local order = GCP.Execution:TopologicalOrder(plan)
    for _, action in ipairs(order) do
        local packed = self:PackStep(action)
        packed.id = prefix .. ":" .. action.id
        if packed.dependencies then
            for index, id in ipairs(packed.dependencies) do
                packed.dependencies[index] = prefix .. ":" .. id
            end
        end
        packed.groupID = packed.groupID and (prefix .. ":" .. packed.groupID) or nil
        packed.interrupt = true
        inserted[#inserted + 1] = packed
    end
    local at = store.currentIndex
    for offset = #inserted, 1, -1 do
        table.insert(store.steps, at, inserted[offset])
    end
    self.interrupt = nil
    self:CaptureBaseline()
    self:SyncNavigation()
    self:Touch()
    return true, #inserted
end

function Guide:DismissInterrupt()
    self.interrupt = nil
    return true
end

-- ---------------------------------------------------------------------------
-- Darstellung
-- ---------------------------------------------------------------------------

function Guide:StepTitle(step)
    if not step then return "" end
    return step.title or GCP.Execution:TypeLabel(step.type)
end

function Guide:StepLines(step)
    local lines = {}
    if not step then return lines end
    if step.detail then lines[#lines + 1] = step.detail end
    if isPositive(step.capitalRequired) then
        lines[#lines + 1] = "Kapital: " .. GCP.Prices:FormatMoney(step.capitalRequired)
    end
    if isPositive(step.expectedProfit) then
        lines[#lines + 1] = "Potenzial: " .. GCP.Prices:FormatMoney(step.expectedProfit)
    end
    return lines
end

-- Die vollstaendige Begruendung eines Schritts: was er kostet, was er bringt
-- und warum die Chance dahinter ueberhaupt eine ist.
function Guide:Why(step)
    local lines = { context = {}, positive = {}, negative = {},
        warnings = {}, unknown = {} }
    if not step then return lines end
    -- Der Kontext steht immer da, auch bei einem reinen Weg. Ein "Warum?", das
    -- bei jedem zweiten Schritt leer bleibt, ist kein Warum.
    lines.context[#lines.context + 1] = self:StepTitle(step)
    if step.location and step.location.kind ~= "ANYWHERE" then
        local label, hint = GCP.Navigation
            and GCP.Navigation:DescribeTarget(step.location,
                GCP.Navigation:GetWaypoint(step.location))
            or (step.location.label or step.location.kind), nil
        lines.context[#lines.context + 1] = "Ort: " .. tostring(label)
        if hint and hint ~= "" then lines.context[#lines.context + 1] = hint end
    end
    if step.travel then
        lines.context[#lines.context + 1] =
            "Ein Weg bindet kein Kapital – er kostet nur Zeit."
    end
    local group = self:GroupOf(step)
    if step.maxBuyPrice then
        lines.positive[#lines.positive + 1] = "Maximaler Einstieg: "
            .. GCP.Prices:FormatMoney(step.maxBuyPrice) .. " / Stück"
    end
    if step.minSellPrice then
        lines.positive[#lines.positive + 1] = "Geplanter Mindestpreis: "
            .. GCP.Prices:FormatMoney(step.minSellPrice) .. " / Stück"
    end
    if group and group.expectedProfit then
        lines.positive[#lines.positive + 1] = "Theoretisches Potenzial der Chance: "
            .. GCP.Prices:FormatMoney(group.expectedProfit)
    end
    local opportunity = group and group.opportunity
    if not opportunity and self.route then
        for _, allocation in ipairs(self.route.allocations or {}) do
            if group and allocation.key == group.key then
                opportunity = allocation.opportunity
            end
        end
    end
    if opportunity then
        local explanation = GCP.Opportunity:Explain(opportunity)
        for _, line in ipairs(explanation or {}) do
            lines.positive[#lines.positive + 1] = line
        end
        if not opportunity.liquidityScore then
            lines.unknown[#lines.unknown + 1] =
                GCP.Opportunity:UnknownLiquidityNote(opportunity.type)
        end
    end
    if step.completionCondition == "MANUAL" then
        lines.warnings[#lines.warnings + 1] =
            "Dieser Schritt wird nicht automatisch erkannt – bitte selbst abhaken."
    end
    if step.optional then
        lines.warnings[#lines.warnings + 1] = "Optionaler Schritt."
    end
    return lines
end

function Guide:HeaderText()
    local progress = self:Progress()
    if not progress or progress.steps == 0 then
        return "Keine Route aktiv."
    end
    if progress.state == Guide.STATES.COMPLETED then
        return string.format("Route abgeschlossen · %d von %d Schritten erledigt",
            progress.done, progress.steps)
    end
    return string.format("Schritt %d / %d", math.min(progress.step, progress.steps),
        progress.steps)
end

-- ---------------------------------------------------------------------------
-- Ereignisse
-- ---------------------------------------------------------------------------

Guide.EVENTS = {
    "AUCTION_HOUSE_SHOW", "BANKFRAME_OPENED", "MAIL_SHOW",
    "TRADE_SKILL_SHOW", "CRAFT_SHOW", "ZONE_CHANGED_NEW_AREA",
    "BAG_UPDATE_DELAYED", "PLAYER_MONEY",
}

function Guide:InstallEvents()
    if self.eventFrame then return self.eventFrame end
    local frame = CreateFrame("Frame")
    for _, event in ipairs(Guide.EVENTS) do
        pcall(frame.RegisterEvent, frame, event)
    end
    frame:SetScript("OnEvent", function(_, event, ...)
        if not GCP.db then return end
        Guide:OnEvent(event, ...)
        if event == "AUCTION_HOUSE_SHOW" then
            Guide:Verify()
        end
        if GCP.UI and GCP.UI.RefreshGuide then GCP.UI:RefreshGuide() end
    end)
    self.eventFrame = frame
    return frame
end
