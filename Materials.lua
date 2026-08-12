local addonName, GCP = ...

GCP.Materials = {}
local Materials = GCP.Materials

-- ---------------------------------------------------------------------------
-- MATERIAL LEDGER (1.1.0-beta.3)
--
-- Eine Frage, und sie ist schwerer als sie aussieht:
--
--     "Was hat dieser Enchant aus MEINEN Taschen verbraucht?"
--
-- Bis beta.2 kamen die Materialkosten einer Service-Sitzung aus dem
-- HANDELSFENSTER. Das war fuer den echten Ablauf wertlos: Bei einem
-- Verzauberungsservice legt der Enchanter nichts ins Fenster. Der Kunde legt
-- sein Item in Slot 7, der Enchanter wirkt den Zauber, und die Reagenzien
-- verschwinden direkt aus seinen Taschen. Gemessen wurden dadurch 0 g Kosten,
-- und die eigene Stundenrate war systematisch zu hoch.
--
-- ---------------------------------------------------------------------------
-- WAS GEMESSEN WIRD - UND WAS AUSDRUECKLICH NICHT
--
-- Gemessen wird, was TATSAECHLICH die Taschen verlassen hat. Nicht, was ein
-- Rezept theoretisch braucht.
--
-- Der Unterschied ist der ganze Punkt: Bringt der Kunde die Reagenzien mit,
-- kostet der Enchant den Spieler nichts. Ein Rezeptabgleich haette trotzdem
-- Kosten gebucht - und zwar genau in dem Fall, der in der Praxis der haeufigste
-- ist.
--
-- DER KUNDE BRINGT MATERIAL. Dann liegt es kurz in den eigenen Taschen und
-- verschwindet gleich darauf wieder. Ein blosser Taschenvergleich saehe einen
-- Abgang und buchte eigene Kosten - falsch. Deshalb fuehrt dieses Modul ein
-- Ledger mit zwei Seiten:
--
--     Kunde geliefert:   +4 Arkanstaub  +2 Essenz
--     Enchant verbraucht: -4 Arkanstaub  -2 Essenz
--     eigener Verbrauch:   0
--
-- Verrechnet wird je Item: Was der Kunde geliefert hat, wird zuerst
-- aufgebraucht. Erst was darueber hinausgeht, ist eigener Einsatz.
--
-- ---------------------------------------------------------------------------
-- WAS DER CLIENT HERGIBT (TBC Classic, Interface 20506)
--
--   UNIT_SPELLCAST_SUCCEEDED    sagt, DASS ein Zauber gelungen ist, und welcher.
--   BAG_UPDATE_DELAYED          feuert gebuendelt nach Taschenaenderungen.
--   GetContainerItemInfo        sagt, was jetzt in den Taschen liegt.
--   Handelsfenster              sagt beim beidseitigen Bestaetigen, was der
--                               Kunde mitgebracht hat.
--
-- WAS ER NICHT HERGIBT, und was deshalb hier nicht behauptet wird:
--
--   1. Es gibt KEINE Abfrage "welche Reagenzien braucht Zauber X" zur
--      Laufzeit. GetTradeSkillReagentInfo arbeitet ueber die Listenposition im
--      GEOEFFNETEN Berufsfenster, nicht ueber eine Zauber-ID. Ein Rezept-
--      abgleich waere also ohnehin nur mit offenem Fenster moeglich - und er
--      waere die falsche Frage (siehe oben).
--   2. Der Client sagt NICHT, wem ein Gegenstand in den Taschen "gehoert".
--      Herkunft entsteht ausschliesslich aus dem Ledger: Was durch einen
--      Handel hereinkam, ist Kundenmaterial; alles andere lag vorher da.
--   3. Eine Taschenaenderung nennt keinen GRUND. Zugeordnet wird deshalb nur,
--      was in einem kurzen Fenster nach einem gelungenen Zauber passiert -
--      und auch das nur einmal.
--
-- ---------------------------------------------------------------------------
-- WANN DIE KOSTEN UNBEKANNT BLEIBEN
--
-- Eine unbekannte Kostenposition als 0 zu behandeln waere schlechter als keine
-- Zahl - sie saehe aus wie eine Messung. Unbekannt wird deshalb ausdruecklich
-- vermerkt, wenn:
--
--   * ein Zauber gelang, aber keine Taschenaenderung zuzuordnen war,
--   * ein verbrauchter Gegenstand keinen belastbaren Preis hat,
--   * die Taschen zum Zeitpunkt des Zaubers nicht lesbar waren.
--
-- Eine Sitzung mit unbekannten Kosten liefert weiterhin ihre BRUTTOrate - aber
-- sie ist als brutto gekennzeichnet, und die Empfehlungsschicht behandelt sie
-- vorsichtiger.
-- ---------------------------------------------------------------------------

local function config()
    return GCP.Constants.MATERIALS
end

local function isPositive(value)
    return type(value) == "number" and value > 0
end

-- Laufzeitzustand. Gehoert NICHT in die SavedVariables: Ein Taschenabbild ist
-- nach einem Reload ohnehin wertlos, und ein halb offenes Zuordnungsfenster
-- soll keinen Neustart ueberleben.
Materials.baseline = nil          -- itemID -> Anzahl, letzter bekannter Stand
Materials.pendingCastAt = nil     -- wann zuletzt ein Enchant gelang
Materials.lastError = nil

function Materials:Now()
    if type(time) == "function" then
        local ok, value = pcall(time)
        if ok and type(value) == "number" then return value end
    end
    return 0
end

-- ---------------------------------------------------------------------------
-- Taschenabbild
--
-- Genutzt wird Inventory:ScanBags - dort ist die Unterscheidung zwischen der
-- alten und der neuen Container-API bereits erledigt, und sie soll genau
-- einmal im Addon stehen.
-- ---------------------------------------------------------------------------

function Materials:BagCounts()
    if not GCP.Inventory then return nil end
    local ok, result = pcall(GCP.Inventory.ScanBags, GCP.Inventory, {})
    if not ok or type(result) ~= "table" then return nil end
    local counts = {}
    for itemID, entry in pairs(result) do
        if type(entry) == "table" and isPositive(entry.count) then
            counts[itemID] = entry.count
        end
    end
    return counts
end

-- Den Bezugsstand auffrischen. Ohne ihn gibt es spaeter keinen Vergleich - und
-- ohne Vergleich keine Kostenaussage.
function Materials:Refresh(now)
    self.baseline = self:BagCounts()
    self.baselineAt = tonumber(now) or self:Now()
    return self.baseline ~= nil
end

-- ---------------------------------------------------------------------------
-- Das Ledger einer Sitzung
--
-- Es haengt an der laufenden Sitzung, nicht am Modul: Zwei Sitzungen sollen
-- sich nicht dieselben Kundenmaterialien anrechnen.
-- ---------------------------------------------------------------------------

local function ledgerOf(session)
    if type(session) ~= "table" then return nil end
    if type(session.credit) ~= "table" then session.credit = {} end
    if type(session.consumed) ~= "table" then session.consumed = {} end
    return session
end

local function addTo(bucket, itemID, count)
    if type(bucket) ~= "table" or not isPositive(count) then return end
    local size = 0
    for _ in pairs(bucket) do size = size + 1 end
    if bucket[itemID] == nil and size >= config().MAX_ITEMS then return end
    bucket[itemID] = (bucket[itemID] or 0) + count
end

-- KUNDENMATERIAL. Aufgerufen, wenn ein Handel belegt abgeschlossen wurde.
-- Gezaehlt werden die Gegenstaende der KUNDENSEITE - ohne Slot 7: Dort liegt
-- das zu verzaubernde Item, und das ist kein Reagenz, sondern der Auftrag.
function Materials:CreditCustomer(snapshot, session, now)
    session = session or (GCP.Activity and GCP.Activity:Current())
    if not ledgerOf(session) or type(snapshot) ~= "table" then return 0 end
    local credited = 0
    for _, entry in ipairs(snapshot.targetItems or {}) do
        if entry.slot ~= 7 and type(entry.link) == "string" then
            local itemID = tonumber(entry.link:match("item:(%d+)"))
            local count = tonumber(entry.count) or 1
            if itemID then
                addTo(session.credit, itemID, count)
                credited = credited + count
            end
        end
    end
    if credited > 0 then
        session.creditAt = tonumber(now) or self:Now()
        if GCP.Activity then GCP.Activity:Touch() end
    end
    return credited
end

-- ---------------------------------------------------------------------------
-- Verbrauch erkennen
-- ---------------------------------------------------------------------------

-- Ein Zauber ist gelungen. Ab jetzt darf die naechste Taschenaenderung ihm
-- zugerechnet werden - genau eine, und nur innerhalb des Fensters.
function Materials:ArmForCast(now)
    now = tonumber(now) or self:Now()
    self.pendingCastAt = now
    -- Ohne Bezugsstand laesst sich nichts vergleichen. Das ist kein Fehler,
    -- sondern eine Luecke - und sie wird als solche gemeldet.
    if self.baseline == nil then
        self:Refresh(now)
        self.castWithoutBaseline = true
    else
        self.castWithoutBaseline = false
    end
end

-- Die Taschen haben sich geaendert. Rueckgabe: zugeordnete Abgaenge (Tabelle
-- itemID -> Anzahl) oder nil, wenn nichts zuzuordnen war.
function Materials:OnBagUpdate(now)
    now = tonumber(now) or self:Now()
    local current = self:BagCounts()
    if current == nil then
        -- Taschen nicht lesbar. Ein Zauber in diesem Fenster bleibt ohne
        -- Kostenaussage; geraten wird nichts.
        if self.pendingCastAt then self:MarkUnknown("Taschen nicht lesbar") end
        self.pendingCastAt = nil
        return nil
    end

    local previous = self.baseline
    self.baseline = current
    self.baselineAt = now

    local armed = self.pendingCastAt
        and (now - self.pendingCastAt) <= config().ATTRIBUTION_WINDOW
    if self.pendingCastAt and not armed then
        -- Das Fenster ist verstrichen, ohne dass etwas zuzuordnen war.
        self:MarkUnknown("keine Taschenänderung zum Zauber")
    end
    if not armed then
        self.pendingCastAt = nil
        return nil
    end
    self.pendingCastAt = nil
    if type(previous) ~= "table" then
        self:MarkUnknown("kein Vergleichsstand der Taschen")
        return nil
    end

    -- Nur ABGAENGE zaehlen. Ein Zugang in demselben Fenster ist kein Verbrauch;
    -- er kommt vom Kunden oder von woanders her und wird ueber das Ledger
    -- verrechnet, nicht hier.
    local consumed, any = {}, false
    for itemID, before in pairs(previous) do
        local after = current[itemID] or 0
        if after < before then
            consumed[itemID] = before - after
            any = true
        end
    end
    if not any then
        self:MarkUnknown("Zauber ohne erkennbaren Materialverbrauch")
        return nil
    end

    local session = GCP.Activity and GCP.Activity:Current()
    if ledgerOf(session) then
        for itemID, count in pairs(consumed) do
            addTo(session.consumed, itemID, count)
        end
        session.consumedAt = now
        GCP.Activity:Touch()
    end
    return consumed
end

-- Ein Zauber, dessen Kosten sich nicht bestimmen liessen. Die Sitzung merkt
-- sich das - ein unbekannter Posten als 0 waere schlechter als keine Zahl.
function Materials:MarkUnknown(reason)
    self.lastError = reason
    local session = GCP.Activity and GCP.Activity:Current()
    if type(session) == "table" then
        session.costUnknown = true
        session.costUnknownReason = reason
        if GCP.Activity then GCP.Activity:Touch() end
    end
    return reason
end

-- ---------------------------------------------------------------------------
-- ABRECHNUNG
--
-- Eigener Verbrauch = verbraucht MINUS vom Kunden geliefert, je Item. Was der
-- Kunde gebracht hat, wird zuerst aufgebraucht.
--
-- Rueckgabe: { value, known, items, unpriced, reason }
-- ---------------------------------------------------------------------------

function Materials:Settle(session)
    if type(session) ~= "table" then return nil end
    local result = { value = 0, known = true, items = {}, unpriced = {} }
    local credit = type(session.credit) == "table" and session.credit or {}
    local consumed = type(session.consumed) == "table" and session.consumed or {}

    for itemID, count in pairs(consumed) do
        local supplied = credit[itemID] or 0
        local own = count - supplied
        if own > 0 then
            local price = GCP.Prices and GCP.Prices:GetBestPlanningValue(itemID) or nil
            if isPositive(price) then
                result.value = result.value + price * own
                result.items[itemID] = own
            else
                -- Ein Gegenstand ohne belastbaren Preis laesst sich nicht
                -- bewerten. Ihn mit null anzusetzen waere eine Falschaussage.
                result.unpriced[itemID] = own
                result.known = false
                result.reason = "verbrauchtes Material ohne belastbaren Preis"
            end
        end
    end

    -- Ein Zauber, dessen Verbrauch nicht zuzuordnen war, macht die ganze
    -- Sitzung unsicher: Es koennen Kosten entstanden sein, die niemand kennt.
    if session.costUnknown then
        result.known = false
        result.reason = session.costUnknownReason or result.reason
            or "Materialverbrauch nicht zuzuordnen"
    end
    return result
end

-- Der Satz dazu, fuer Oberflaeche und Diagnose.
function Materials:Describe(settlement)
    if type(settlement) ~= "table" then return nil end
    if not settlement.known then
        return string.format("Materialkosten unbekannt – %s. Die Rate gilt "
            .. "deshalb brutto.", settlement.reason or "Grund unbekannt")
    end
    if settlement.value <= 0 then
        return "Keine eigenen Materialien verbraucht – der Kunde hat sie gestellt."
    end
    return string.format("Eigene Materialien: %s",
        GCP.Prices:FormatGold(settlement.value))
end
