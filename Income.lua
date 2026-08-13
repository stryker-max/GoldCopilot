local addonName, GCP = ...

GCP.Income = {}
local Income = GCP.Income

local GetItemInfoCompat = (C_Item and C_Item.GetItemInfo) or GetItemInfo

-- ---------------------------------------------------------------------------
-- INCOME TRACKER (1.1.0)
--
-- Gold Copilot kennt bis 1.0 genau eine Einnahmequelle: das Auktionshaus. Der
-- Spieler kennt mehr. Ein Verzauberer, der in Shattrath steht und gegen
-- Trinkgeld verzaubert, verdient womoeglich das Dreifache einer Farmstunde -
-- und das Addon wusste davon nichts.
--
-- Dieses Modul beantwortet:
--
--     "Woher kommt das Gold dieses Spielers wirklich?"
--
-- DER WICHTIGSTE SATZ DES MODULS:
--
--     Aus einer Aenderung des Goldstands wird KEINE Ursache erfunden.
--
-- PLAYER_MONEY feuert und sagt: es ist mehr geworden. Es sagt nicht, warum.
-- Ohne Kontext heisst die Quelle UNKNOWN - und UNKNOWN fliesst in keine
-- Gold/h-Rechnung, in keine Empfehlung und in keinen Methodenvergleich ein.
-- Eine falsche Zuordnung waere hier besonders teuer: Aus einem Gildengeschenk
-- wuerde eine 400-g/h-Methode.
--
-- DER KONTEXT entsteht aus einem kurzen Zeitfenster. Wer gerade ein
-- Handelsfenster geschlossen hat, dessen Goldzuwachs in den naechsten Sekunden
-- gehoert zu diesem Handel. Wer nichts davon hatte, hat einen Zufluss ohne
-- Ursache - und der wird auch so aufgeschrieben.
--
-- ---------------------------------------------------------------------------
-- WAS DER CLIENT NICHT HERGIBT (und was hier deshalb nicht behauptet wird)
--
--   1. TRADE_CLOSED sagt NICHT, ob der Handel zustande kam. Es feuert beim
--      Abbrechen genauso. Deshalb gilt ein Handel erst als erfolgt, wenn
--      entweder die Systemmeldung ERR_TRADE_COMPLETE kam oder das Gold
--      tatsaechlich mehr wurde.
--   2. Nach TRADE_CLOSED ist der Inhalt weg - die API antwortet nicht mehr.
--      Deshalb wird beim beidseitigen Bestaetigen ein Abzug genommen; das ist
--      der letzte Moment, in dem der Inhalt noch abfragbar ist.
--   3. Es gibt KEINE Zuordnung "dieser Zauber gehoert zu diesem Kunden".
--      UNIT_SPELLCAST_SUCCEEDED nennt den Zauber, nicht den Handelspartner.
--      Die Verbindung ist ausschliesslich zeitliche Naehe - deshalb reicht sie
--      fuer "medium" und nie fuer "high".
--
-- Der Glueckfall ist der SIEBTE HANDELSSLOT. In TBC legt der Kunde das zu
-- verzaubernde Item dort hinein ("wird nicht getauscht"). Ein belegter Slot 7
-- auf der Kundenseite ist ein direkter Beleg fuer eine Verzauberung - keine
-- Heuristik, keine zeitliche Naehe, sondern die Sache selbst.
--
--   db.income = {
--       version = 1,
--       epoch = 1786000000,
--       events = { kind, minute, amount, confidence, sessionRef, ... }
--   }
-- ---------------------------------------------------------------------------

local EVENT_STRIDE = 5

Income.SOURCE = {
    AUCTION_SALE = 1,
    SERVICE_ENCHANT = 2,
    TRADE = 3,
    VENDOR = 4,
    QUEST = 5,
    LOOT = 6,
    UNKNOWN = 7,
    -- 1.1.0-beta.5. Angehaengt statt eingeordnet: Die Zahlen stehen so in den
    -- SavedVariables, und eine Umnummerierung machte aus jedem alten
    -- Handelsgold eine Verzauberung.
    SERVICE_PORTAL = 8,
}
local SOURCE_NAME = {
    [1] = "AUCTION_SALE", [2] = "SERVICE_ENCHANT", [3] = "TRADE",
    [4] = "VENDOR", [5] = "QUEST", [6] = "LOOT", [7] = "UNKNOWN",
    [8] = "SERVICE_PORTAL",
}
Income.SOURCE_NAME = SOURCE_NAME

-- Sicherheit der Zuordnung. Nur "high" und "medium" duerfen in eine
-- Methodenstatistik einfliessen; "low" wird gezaehlt und ausgewiesen.
Income.CONFIDENCE = { LOW = 1, MEDIUM = 2, HIGH = 3 }
local CONFIDENCE_NAME = { [1] = "low", [2] = "medium", [3] = "high" }
Income.CONFIDENCE_NAME = CONFIDENCE_NAME

Income.revision = 0
-- Laufzeitzustand des Kontextfensters. Gehoert NICHT in die SavedVariables:
-- Ein halb offenes Handelsfenster soll keinen Reload ueberleben.
Income.context = nil
Income.lastGold = nil
Income.lastEnchantAt = nil
Income.pendingTrade = nil

local function config()
    return GCP.Constants.INCOME
end

local function isPositive(value)
    return type(value) == "number" and value > 0
end

function Income:Now()
    if type(time) == "function" then
        local ok, value = pcall(time)
        if ok and type(value) == "number" then return value end
    end
    return 0
end

function Income:Touch()
    self.revision = self.revision + 1
    self.cache = nil
end

-- ---------------------------------------------------------------------------
-- Speicher
-- ---------------------------------------------------------------------------

function Income:EnsureStore()
    local db = GCP.db
    if not db then return nil end
    local C = config()
    local profile = GCP:Profile()
    local store = profile.income
    if type(store) ~= "table" or store.version ~= C.STORE_VERSION
        or type(store.events) ~= "table" or type(store.epoch) ~= "number" then
        store = { version = C.STORE_VERSION, epoch = self:Now(), events = {} }
        profile.income = store
    end
    return store
end

function Income:Reset()
    local db = GCP.db
    if not db then return false end
    GCP:Profile().income = nil
    self:EnsureStore()
    self:Touch()
    return true
end

-- Ein Ereignis ist eine BEOBACHTUNG, keine Behauptung. source und confidence
-- stehen deshalb beide daran - und wer sie auswertet, muss beide lesen.
function Income:Record(info)
    if type(info) ~= "table" then return false end
    local amount = tonumber(info.amount)
    if not isPositive(amount) then return false end
    local C = config()
    if amount < C.MIN_AMOUNT then return false end

    local store = self:EnsureStore()
    if not store then return false end
    local now = tonumber(info.timestamp) or self:Now()
    if now < store.epoch then store.epoch = now end

    local source = self.SOURCE[info.source or "UNKNOWN"] or self.SOURCE.UNKNOWN
    local confidence = tonumber(info.confidence) or self.CONFIDENCE.LOW
    local sessionRef = tonumber(info.sessionRef) or 0

    local events = store.events
    events[#events + 1] = source
    events[#events + 1] = math.floor((now - store.epoch) / 60)
    events[#events + 1] = math.floor(amount + 0.5)
    events[#events + 1] = confidence
    events[#events + 1] = sessionRef

    local maxEntries = C.MAX_EVENTS * EVENT_STRIDE
    while #events > maxEntries do
        for _ = 1, EVENT_STRIDE do table.remove(events, 1) end
    end
    self:Touch()
    -- Die Aktivitaetsschicht bekommt jedes Ereignis zu sehen: Sie entscheidet,
    -- ob daraus eine Sitzung wird.
    if GCP.Activity then
        pcall(GCP.Activity.OnIncome, GCP.Activity, {
            source = info.source or "UNKNOWN",
            amount = amount,
            confidence = confidence,
            timestamp = now,
        })
    end
    return true
end

function Income:Prune(now)
    local store = self:EnsureStore()
    if not store then return 0 end
    local C = config()
    now = tonumber(now) or self:Now()
    local cutoff = now - C.RETENTION_DAYS * 86400
    local events = store.events
    local kept = {}
    for index = 1, #events - EVENT_STRIDE + 1, EVENT_STRIDE do
        local stamp = store.epoch + events[index + 1] * 60
        if stamp >= cutoff then
            for offset = 0, EVENT_STRIDE - 1 do
                kept[#kept + 1] = events[index + offset]
            end
        end
    end
    local removed = (#events - #kept) / EVENT_STRIDE
    if removed > 0 then
        for index = #events, 1, -1 do events[index] = nil end
        for index = 1, #kept do events[index] = kept[index] end
        self:Touch()
    end
    return removed
end

-- Alle Ereignisse als Tabellen. Der flache Zahlenspeicher spart Platz;
-- niemand ausserhalb dieses Moduls soll mit Schrittweiten rechnen muessen.
function Income:GetEvents(sinceSeconds)
    local store = self:EnsureStore()
    if not store then return {} end
    local cutoff = isPositive(sinceSeconds) and (self:Now() - sinceSeconds) or nil
    local list = {}
    local events = store.events
    for index = 1, #events - EVENT_STRIDE + 1, EVENT_STRIDE do
        local stamp = store.epoch + events[index + 1] * 60
        if not cutoff or stamp >= cutoff then
            list[#list + 1] = {
                source = SOURCE_NAME[events[index]] or "UNKNOWN",
                timestamp = stamp,
                amount = events[index + 2],
                confidence = events[index + 3],
                confidenceLabel = CONFIDENCE_NAME[events[index + 3]] or "low",
                sessionRef = events[index + 4],
            }
        end
    end
    return list
end

-- Summe je Quelle. UNKNOWN steht dabei und wird nicht weggerechnet: Wie viel
-- Gold ohne erkennbare Ursache hereinkam, ist selbst eine Aussage - naemlich
-- ueber die Grenzen dieser Messung.
function Income:Summary(days)
    local seconds = isPositive(days) and days * 86400 or nil
    local summary = { bySource = {}, total = 0, events = 0, unknown = 0 }
    for _, event in ipairs(self:GetEvents(seconds)) do
        local bucket = summary.bySource[event.source]
        if not bucket then
            bucket = { amount = 0, events = 0 }
            summary.bySource[event.source] = bucket
        end
        bucket.amount = bucket.amount + event.amount
        bucket.events = bucket.events + 1
        summary.total = summary.total + event.amount
        summary.events = summary.events + 1
        if event.source == "UNKNOWN" then
            summary.unknown = summary.unknown + event.amount
        end
    end
    return summary
end

-- ---------------------------------------------------------------------------
-- KONTEXT
--
-- Der ganze Mechanismus existiert nur, weil der Client die Frage "warum ist
-- mein Gold mehr geworden?" nicht beantwortet. Ein Kontext ist ein kurzes
-- Fenster, in dem eine Ursache bekannt ist.
-- ---------------------------------------------------------------------------

function Income:SetContext(source, detail, now)
    self.context = {
        source = source,
        detail = detail,
        at = tonumber(now) or self:Now(),
    }
end

function Income:ClearContext()
    self.context = nil
end

-- Der Kontext, der JETZT gilt - oder nil, wenn er abgelaufen ist.
function Income:ActiveContext(now)
    local context = self.context
    if type(context) ~= "table" then return nil end
    now = tonumber(now) or self:Now()
    if (now - context.at) > config().CONTEXT_WINDOW then
        self.context = nil
        return nil
    end
    return context
end

-- ---------------------------------------------------------------------------
-- GOLDSTAND
--
-- Der einzige Einstiegspunkt fuer alles, was nicht ueber einen eigenen
-- Ereignishaken laeuft. Er buchstabiert die Regel dieses Moduls aus: Ein
-- Zuwachs OHNE Kontext ist ein Zuwachs ohne Ursache.
-- ---------------------------------------------------------------------------

-- Den Bezugsstand setzen, ohne daraus ein Ereignis zu machen.
--
-- Ohne ihn war der ERSTE Goldzufluss nach jedem Login verloren: OnMoney
-- braucht einen Vorherwert, um eine Differenz zu bilden, und legte ihn bis
-- 1.1.0-beta.5 erst beim ersten Aufruf an - womit genau dieser Aufruf nichts
-- zurueckgab. Wer sich einloggt und als Erstes ein Trinkgeld bekommt, hatte
-- keines.
function Income:Prime()
    if type(GetMoney) ~= "function" then return false end
    local ok, current = pcall(GetMoney)
    if not ok or type(current) ~= "number" then return false end
    self.lastGold = current
    return true
end

function Income:OnMoney(now)
    local current = (type(GetMoney) == "function") and GetMoney() or nil
    if type(current) ~= "number" then return false end
    local previous = self.lastGold
    self.lastGold = current
    if type(previous) ~= "number" then return false end
    local delta = current - previous
    if delta <= 0 then return false end

    now = tonumber(now) or self:Now()
    local context = self:ActiveContext(now)

    -- ---------------------------------------------------------------------
    -- DAS GOLD IST DER ABSCHLUSSBELEG (Fehler bis 1.1.0-beta.5)
    --
    -- Im Kopf dieses Moduls steht seit jeher: Ein Handel gilt als erfolgt,
    -- wenn ENTWEDER die Systemmeldung kam ODER das Gold tatsaechlich mehr
    -- wurde. Die zweite Haelfte war nie umgesetzt - OnMoney sah nur den
    -- Kontext und nie den offenen Handelsabzug.
    --
    -- In der Praxis kommt PLAYER_MONEY in TBC regelmaessig VOR
    -- ERR_TRADE_COMPLETE. Dann gab es zum Zeitpunkt des Zuflusses noch keinen
    -- Kontext, das Trinkgeld wurde als UNKNOWN verbucht - und eine laufende
    -- Servicesitzung sah davon nichts.
    --
    -- Ein offener Abzug, der erhaltenes Gold ausweist, PLUS ein tatsaechlicher
    -- Goldzuwachs sind zusammen der Beleg. Das ist keine erfundene Ursache:
    -- Beide Haelften sind beobachtet.
    if not context and type(self.pendingTrade) == "table"
        and isPositive(self.pendingTrade.targetMoney) then
        self:OnTradeCompleted(now)
        context = self:ActiveContext(now)
    end

    if not context then
        -- KEINE URSACHE ERFINDEN. Hier stand die Versuchung, aus "Gold ist
        -- mehr geworden" etwas zu machen - genau das passiert nicht.
        return self:Record({ amount = delta, source = "UNKNOWN",
            confidence = self.CONFIDENCE.LOW, timestamp = now })
    end

    local recorded = self:Record({
        amount = delta,
        source = context.source,
        confidence = context.confidence or self.CONFIDENCE.MEDIUM,
        timestamp = now,
    })
    -- Ein Kontext gilt fuer genau einen Zufluss. Wer zweimal hintereinander
    -- Gold bekommt, hat zwei Ereignisse - und nur das erste hat die Ursache.
    self:ClearContext()
    return recorded
end

-- ---------------------------------------------------------------------------
-- HANDEL
--
-- Der Ablauf im Client, und warum er so umstaendlich ist:
--
--   TRADE_SHOW              Fenster auf. Noch ist nichts drin.
--   TRADE_ACCEPT_UPDATE     Beide haben bestaetigt -> JETZT den Abzug nehmen.
--                           Danach antwortet die API nicht mehr.
--   TRADE_CLOSED            Fenster zu. Sagt NICHT, ob es geklappt hat.
--   ERR_TRADE_COMPLETE      Systemmeldung: es hat geklappt.
--   PLAYER_MONEY            Das Gold ist da.
-- ---------------------------------------------------------------------------

-- Der Abzug des Handelsinhalts. Getrennt gefuehrt, damit die Tests ihn ohne
-- Handelsfenster stellen koennen - und damit klar bleibt, WANN er entsteht.
function Income:SnapshotTrade(now)
    local snapshot = {
        at = tonumber(now) or self:Now(),
        partner = nil,
        targetMoney = 0,
        playerMoney = 0,
        targetItems = {},
        playerItems = {},
        enchantSlot = nil,
    }
    if type(UnitName) == "function" then
        local ok, name = pcall(UnitName, "NPC")
        if ok and type(name) == "string" and name ~= "" then snapshot.partner = name end
    end
    if type(GetTargetTradeMoney) == "function" then
        local ok, value = pcall(GetTargetTradeMoney)
        if ok and type(value) == "number" then snapshot.targetMoney = value end
    end
    if type(GetPlayerTradeMoney) == "function" then
        local ok, value = pcall(GetPlayerTradeMoney)
        if ok and type(value) == "number" then snapshot.playerMoney = value end
    end
    -- Slot 7 ist der Verzauberungsslot: "wird nicht getauscht". Wer dort etwas
    -- hineinlegt, will es verzaubert haben - das ist der direkteste Beleg, den
    -- dieses Modul ueberhaupt bekommen kann.
    -- Die STUECKZAHL gehoert dazu. Ohne sie waeren vier Arkanstaub in einem
    -- Stapel ein Stueck - und das Material-Ledger rechnete dem Spieler drei
    -- Staub als eigenen Einsatz an, die der Kunde mitgebracht hat.
    --
    -- GetTradeTargetItemInfo liefert sie als dritten Rueckgabewert; existiert
    -- die Funktion nicht, bleibt es bei einem Stueck je Slot - und das ist
    -- dann eine Untergrenze, keine Behauptung.
    local function stackOf(getter, slot)
        if type(getter) ~= "function" then return 1 end
        local ok, _, _, quantity = pcall(getter, slot)
        if ok and type(quantity) == "number" and quantity > 0 then return quantity end
        return 1
    end

    for slot = 1, 7 do
        if type(GetTradeTargetItemLink) == "function" then
            local ok, link = pcall(GetTradeTargetItemLink, slot)
            if ok and type(link) == "string" and link ~= "" then
                if slot == 7 then
                    snapshot.enchantSlot = link
                else
                    snapshot.targetItems[#snapshot.targetItems + 1] = {
                        slot = slot, link = link,
                        count = stackOf(GetTradeTargetItemInfo, slot),
                    }
                end
            end
        end
        if type(GetTradePlayerItemLink) == "function" then
            local ok, link = pcall(GetTradePlayerItemLink, slot)
            if ok and type(link) == "string" and link ~= "" then
                snapshot.playerItems[#snapshot.playerItems + 1] = {
                    slot = slot, link = link,
                    count = stackOf(GetTradePlayerItemInfo, slot),
                }
            end
        end
    end
    return snapshot
end

-- Die Klassifikation. Sie ist der Kern des Moduls und bewusst streng:
-- Eine falsche Zuordnung ist schlechter als UNKNOWN.
--
-- Rueckgabe: source (string), confidence (number), Begruendung (string)
function Income:ClassifyTrade(snapshot, now)
    if type(snapshot) ~= "table" then
        return "UNKNOWN", self.CONFIDENCE.LOW, "kein Handelsinhalt bekannt"
    end
    now = tonumber(now) or self:Now()

    -- Ohne erhaltenes Gold ist es kein Einkommen. Ein Handel, bei dem nur
    -- Gegenstaende den Besitzer wechseln, mag alles Moegliche sein - eine
    -- Einnahme ist er nicht.
    if not isPositive(snapshot.targetMoney) then
        return "UNKNOWN", self.CONFIDENCE.LOW, "kein Gold erhalten"
    end

    -- HOCH: Der Kunde hat etwas in den Verzauberungsslot gelegt. Das ist keine
    -- Vermutung ueber ein Muster, das ist die Sache selbst.
    if snapshot.enchantSlot then
        return "SERVICE_ENCHANT", self.CONFIDENCE.HIGH,
            "Der Kunde hat einen Gegenstand in den Verzauberungsslot gelegt."
    end

    -- MITTEL: Ein Dienstleistungszauber in zeitlicher Naehe - eine
    -- Verzauberung oder ein Portal. Der Client sagt nicht, zu welchem Kunden
    -- ein Zauber gehoert; deshalb reicht das nie fuer "hoch", auch wenn es
    -- meistens stimmt.
    local lastEnchant = self.lastEnchantAt
    if isPositive(lastEnchant) and (now - lastEnchant) <= config().ENCHANT_WINDOW then
        if self.lastServiceKind == "portal" then
            return "SERVICE_PORTAL", self.CONFIDENCE.MEDIUM,
                "Kurz vor dem Handel wurde ein Portal gestellt."
        end
        return "SERVICE_ENCHANT", self.CONFIDENCE.MEDIUM,
            "Kurz vor dem Handel wurde eine Verzauberung gewirkt."
    end

    -- NIEDRIG: Gold ueber einen Handel, sonst nichts Passendes. Das ist ein
    -- Handel und ausdruecklich KEIN Verzauberungsservice - aus einem
    -- Gildengeschenk wuerde sonst eine Goldmethode.
    return "TRADE", self.CONFIDENCE.LOW, "Gold über einen Handel erhalten."
end

-- Beide Seiten haben bestaetigt: letzter Moment fuer den Abzug.
function Income:OnTradeAccepted(now)
    self.pendingTrade = self:SnapshotTrade(now)
    return self.pendingTrade
end

-- Der Handel ist BELEGT abgeschlossen. Ausgeloest von der Systemmeldung
-- ERR_TRADE_COMPLETE - nicht von TRADE_CLOSED, das auch beim Abbrechen feuert.
function Income:OnTradeCompleted(now)
    local snapshot = self.pendingTrade
    self.pendingTrade = nil
    if type(snapshot) ~= "table" then return false end
    now = tonumber(now) or self:Now()

    local source, confidence, why = self:ClassifyTrade(snapshot, now)
    -- Der Kontext traegt die Klassifikation zum Goldzufluss, der gleich kommt.
    self.context = {
        source = source, confidence = confidence, detail = why, at = now,
        snapshot = snapshot,
    }

    -- EIGENE MATERIALIEN (1.1.0-beta.2). Was der Spieler in den Handel legt,
    -- ist sein Einsatz und gehoert als wirtschaftliche Kosten in die laufende
    -- Sitzung - sonst waere die Stundenrate brutto statt netto.
    --
    -- Was der KUNDE mitbringt, taucht hier bewusst nicht auf: Es ist
    -- Durchlaufmaterial, war nie sein Gold und ist auch keine Kosten.
    local value = self:ValueOfTrade(snapshot)
    if value and value.ownMaterialValue > 0 and GCP.Activity then
        pcall(GCP.Activity.AddCost, GCP.Activity, value.ownMaterialValue, now)
    end

    -- KUNDENMATERIAL INS LEDGER (1.1.0-beta.3). Was der Kunde mitbringt,
    -- landet gleich in den eigenen Taschen und verschwindet beim Zaubern
    -- wieder. Ohne diese Gutschrift saehe der Taschenvergleich einen Abgang
    -- und buchte eigene Kosten - genau der Fall, der in der Praxis der
    -- haeufigste ist.
    if GCP.Materials then
        pcall(GCP.Materials.CreditCustomer, GCP.Materials, snapshot, nil, now)
        -- Der Zufluss veraendert die Taschen. Der Bezugsstand muss ihn kennen,
        -- sonst gilt er spaeter als Verbrauch.
        pcall(GCP.Materials.Refresh, GCP.Materials, now)
    end
    return true, source, confidence, why
end

-- Ein abgebrochener Handel hinterlaesst nichts.
function Income:OnTradeClosed()
    self.pendingTrade = nil
end

-- Verzauberungen und Portale. Der Zauber selbst ist kein Einkommen - er ist
-- der Kontext, der einem spaeteren Trinkgeld seine Bedeutung gibt.
--
-- Bei einem Portal ist er ausserdem der Ausloeser fuer die Kostenmessung: Die
-- Rune verlaesst die Taschen, und genau das misst Materials ueber die
-- Bestandsdifferenz. Zahlt der Kunde nichts, bleibt die Rune trotzdem weg -
-- und die Sitzung faellt entsprechend ins Minus. Das ist keine Panne, sondern
-- die Antwort auf die Frage, was der Stand wirklich einbringt.
function Income:OnServiceCast(kind, now)
    now = tonumber(now) or self:Now()
    self.lastEnchantAt = now
    self.lastServiceKind = kind or "enchant"
    -- Ab hier darf die naechste Taschenaenderung diesem Zauber zugerechnet
    -- werden. Genau eine, und nur kurz.
    if GCP.Materials then pcall(GCP.Materials.ArmForCast, GCP.Materials, now) end
end

-- Alter Name, unveraendert in der Wirkung.
function Income:OnEnchantCast(now)
    return self:OnServiceCast("enchant", now)
end

-- ---------------------------------------------------------------------------
-- KUNDENMATERIAL IST KEIN EINKOMMEN
--
-- Der Kunde bringt zwei Grosse Prismasplitter, vier Arkanstaub und 20 g
-- Trinkgeld. Das Einkommen ist 20 g. NICHT 20 g plus der Marktwert der
-- Materialien - die waren nie sein Gold und sind es nie geworden.
--
-- Diese Funktion sagt, was ein Handel WIRKLICH eingebracht hat, und trennt
-- dabei Durchlaufmaterial von eigenem Einsatz.
-- ---------------------------------------------------------------------------

function Income:ValueOfTrade(snapshot)
    if type(snapshot) ~= "table" then return nil end
    local result = {
        cashReceived = snapshot.targetMoney or 0,
        cashPaid = snapshot.playerMoney or 0,
        customerMaterials = 0,
        ownMaterialValue = 0,
    }

    -- Was der Kunde mitbringt, ist Durchlaufmaterial. Es zaehlt als Menge,
    -- nicht als Wert - der Wert gehoerte nie dem Spieler.
    result.customerMaterials = #(snapshot.targetItems or {})

    -- Was der Spieler hergibt, ist eigener Einsatz. Er zaehlt mit seinem
    -- Marktwert als wirtschaftliche Kosten - dieselbe Trennung von
    -- wirtschaftlichen Kosten und Cash Flow wie ueberall sonst.
    for _, entry in ipairs(snapshot.playerItems or {}) do
        local itemID = entry.link and tonumber(entry.link:match("item:(%d+)")) or nil
        if itemID and GCP.Prices then
            local value = GCP.Prices:GetBestPlanningValue(itemID)
            if isPositive(value) then
                result.ownMaterialValue = result.ownMaterialValue
                    + value * (tonumber(entry.count) or 1)
            end
        end
    end

    result.cashIncome = result.cashReceived - result.cashPaid
    -- Wirtschaftlicher Gewinn: erhaltenes Gold minus dem, was an eigenem
    -- Material darin steckt.
    result.economicProfit = result.cashIncome - result.ownMaterialValue
    return result
end

-- ---------------------------------------------------------------------------
-- Darstellung
-- ---------------------------------------------------------------------------

function Income:SourceLabel(source)
    return config().SOURCE_LABEL[source or "UNKNOWN"] or source
end

function Income:Lines(days)
    local summary = self:Summary(days)
    local lines = {}
    if summary.events == 0 then
        lines[#lines + 1] = "Noch keine Goldzuflüsse erfasst – Gold Copilot lernt "
            .. "deine Einnahmequellen, sobald welche hereinkommen."
        return lines
    end
    lines[#lines + 1] = string.format("%d Zufluss/Zuflüsse, zusammen %s",
        summary.events, GCP.Prices:FormatGold(summary.total))
    for source, bucket in pairs(summary.bySource) do
        lines[#lines + 1] = string.format("  %s: %s (%d)",
            self:SourceLabel(source), GCP.Prices:FormatGold(bucket.amount),
            bucket.events)
    end
    if summary.unknown > 0 then
        lines[#lines + 1] = string.format(
            "Davon %s ohne erkennbare Ursache – Gold Copilot erfindet dafür keine.",
            GCP.Prices:FormatGold(summary.unknown))
    end
    return lines
end
