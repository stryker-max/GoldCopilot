local addonName, GCP = ...

GCP.Ledger = {}
local Ledger = GCP.Ledger

local GetItemInfoCompat = (C_Item and C_Item.GetItemInfo) or GetItemInfo

-- ---------------------------------------------------------------------------
-- LEDGER / LIQUIDITY BRAIN (0.8.0)
--
-- 0.5 beantwortet "steht der Preis relativ zu seiner eigenen Vergangenheit
-- guenstig?", 0.6 "ist daraus eine Chance ableitbar?", 0.7 "was kommt an
-- bekannten Veraenderungen?". Allen dreien fehlt dieselbe Antwort:
--
--     "Verkaufe ich dieses Item ueberhaupt - und wie schnell?"
--
-- Ein theoretischer Gewinn von +500 g ist wertlos, wenn das Item zehn Tage
-- steht. Ein +30-g-Handel, der sich dreimal am Tag dreht, ist besser. Genau
-- das kann dieses Modul zum ersten Mal beantworten - aber ausschliesslich aus
-- den eigenen, tatsaechlich stattgefundenen Geschaeften des Nutzers.
--
-- WAS HIER AUSDRUECKLICH NICHT PASSIERT:
--   * Keine erfundenen Sale Rates. Kein "Netherstoff verkauft sich schnell".
--   * Keine geschaetzten Verkaufszeiten. Ohne Zuordnung Einstellung -> Verkauf
--     gibt es keinen Median, sondern nil.
--   * Keine Rueckschluesse aus Goldaenderungen. Wer sein Gold zaehlt, weiss
--     nicht, ob es aus dem AH, vom Haendler oder aus einer Quest kam.
--   * Keine Haendler-, Post-, Handels-, Zerstoerungs- oder Craft-Vorgaenge.
--     Nur bestaetigte Auktionshaus-Verkaeufe zaehlen als Verkauf (siehe
--     RecordSale: alles ohne source "ah" bleibt aus der Sell-Through-Rechnung
--     heraus).
--   * Kein zweiter TSM-Ledger. Aufgeschrieben wird nur, was eine Empfehlung
--     verbessert, nicht jeder Kupfertransfer der letzten drei Jahre.
--
-- ALLE DATEN BLEIBEN LOKAL in den SavedVariables. Nichts wird uebertragen.
--
-- ---------------------------------------------------------------------------
-- DATENQUELLEN - was der Client wirklich hergibt
--
-- Vor der eigenen Ereigniserfassung wurden die vorhandenen Addons geprueft:
--
--   * Auctionator stellt ueber Auctionator.API.v1 Preise, Scan-Alter,
--     Entzauberwerte und einen DB-Update-Callback bereit - alles bereits seit
--     0.4/0.5 in Prices.lua und Market.lua genutzt. Verkaufs- oder
--     Kaufhistorie gehoert nicht dazu.
--   * Syndicator kennt Taschen, Bank, Post und laufende Auktionen als
--     Bestand (Inventory.lua nutzt das), aber keine Ereignisse: Es weiss, was
--     jetzt im AH liegt, nicht was gestern verkauft wurde.
--   * TSM veroeffentlicht mit TSM_API.GetCustomPriceValue ausschliesslich
--     Preisquellen. Der TSM-Ledger hat keine oeffentliche API.
--   * Journalator protokolliert genau diese Ereignisse - aber ohne
--     dokumentierte oeffentliche API, und seine veroeffentlichten Fassungen
--     zielen auf Retail, Season of Mastery und Wrath, nicht auf TBC
--     Anniversary. An seine internen Tabellen anzudocken hiesse, sich an
--     etwas zu haengen, das sich jederzeit aendern darf. Deshalb: keine
--     Kopplung. Sollte Journalator eine stabile API veroeffentlichen, ist der
--     Einstiegspunkt CaptureFromExternal() weiter unten.
--
-- Bleibt der Client selbst. Zwei Quellen sind belastbar:
--
--   1. DER BRIEFKASTEN. GetInboxInvoiceInfo(index) liefert fuer jede
--      AH-Rechnung invoiceType, itemName, playerName, bid, buyout, deposit und
--      consignment. Das ist die einzige Stelle, an der der Client
--      unmissverstaendlich sagt: "hier wurde etwas verkauft, fuer so viel,
--      abzueglich so viel Gebuehr". Dazu die Betreffzeilen
--      AUCTION_EXPIRED_MAIL_SUBJECT und AUCTION_REMOVED_MAIL_SUBJECT fuer
--      abgelaufene und zurueckgezogene Auktionen - beide mit dem Item als
--      Anhang, also mit Item-ID und Stueckzahl.
--
--   2. DAS EINSTELLEN. PostAuction wird per hooksecurefunc mitgelesen; das
--      Item steht dabei im Verkaufsplatz und laesst sich ueber
--      GetAuctionSellItemInfo benennen. CalculateAuctionDeposit liefert die
--      Einstellgebuehr exakt.
--
-- WAS DER CLASSIC-CLIENT NICHT HERGIBT (und was deshalb UNKNOWN bleibt):
--   * Eine Auktions-ID. Die klassische API kennt keine stabile Kennung einer
--     Auktion - weder beim Einstellen noch in der Rechnung. Die Zuordnung
--     Einstellung -> Verkauf ist deshalb grundsaetzlich eine Rekonstruktion.
--   * Die Stueckzahl in der Verkaufsrechnung. Die Rechnung nennt nur den
--     Item-NAMEN und den Betrag, keine Menge und keine Item-ID.
--   * Den Kaeufer-Zeitpunkt. Wann genau verkauft wurde, sagt niemand; bekannt
--     ist nur, wann die Post ankam (aus daysLeft rekonstruiert).
-- Wie damit umgegangen wird, steht bei MatchSale.
-- ---------------------------------------------------------------------------

-- ---------------------------------------------------------------------------
-- SPEICHERFORMAT
--
--   db.ledger = {
--       version = 1,
--       epoch   = 1786000000,        -- Bezugszeitpunkt, Unix-Sekunden
--       events  = { 2, 4711, 23425, 20, 50000, 47500, 2, ... },
--       items   = { [23425] = { c = {...}, m = {...}, b = {...},
--                               s = {...}, h = {...}, f = ..., l = ... } },
--       open    = { { 23425, 4711, 20, 50000, 300, 4711 }, ... },
--       names   = { ["Adamantiterz"] = 23425 },
--       mail    = { ["2|Adamantiterz|1000000"] = { 2, 60123 } },
--       prunedAt = 1786003600,
--   }
--
-- events ist wie in Market.lua eine flache Zahlenliste mit fester Schrittweite
-- (8), nicht eine Liste aus Tabellen mit Schluesseln. WoW schreibt
-- SavedVariables als Lua-Quelltext: benannte Felder kosten je Ereignis rund
-- 140 Zeichen, acht Zahlen rund 50. Bei 4000 Ereignissen sind das 560 KB
-- gegen 200 KB - derselbe Informationsgehalt.
--
-- Ein Ereignis: kind, minute, itemID, quantity, unitA, unitB, flags, extra
--   PURCHASE  unitA = Stueckpreis,        unitB = 0,             flags = 0
--   SALE      unitA = Stueckpreis brutto, unitB = Preis netto,   flags = Guete
--             extra = Verkaufsdauer in 1/10 Stunden (0 = unbekannt)
--   POST      unitA = Stueckpreis,        unitB = Einstellgebuehr, flags = Stunden
--   EXPIRE    unitA = Stueckpreis (0=unbekannt), unitB = verlorene Gebuehr, flags = 0
--   CANCEL    unitA = Stueckpreis (0=unbekannt), unitB = verlorene Gebuehr, flags = 0
-- quantity 0 heisst bei SALE ausdruecklich "Stueckzahl unbekannt" - nicht null.
-- itemID 0 heisst "Item nicht aufloesbar"; solche Ereignisse zaehlen nur in
-- die Gesamtsumme, nie in eine Item-Statistik.
--
-- Die Verkaufsdauer steht bewusst AUCH am einzelnen Ereignis und nicht nur in
-- der Stichprobenliste des Items: Nur so kann die 7- und 30-Tage-Ansicht einen
-- Median rechnen, der wirklich zu ihrem Zeitraum gehoert. Aus den Stichproben
-- je Item kaeme sonst der Median aller je gemessenen Verkaeufe, waehrend
-- darueber "7 Tage" steht.
--
-- items[itemID] haelt die Aggregate. Sie sind das Langzeitgedaechtnis: Die
-- Rohereignisse fallen nach 60 Tagen weg, die Zaehler bleiben. Kurze
-- Feldnamen aus demselben Grund wie oben; die Bedeutung steht hier:
--
--   c = { postedQty, soldQty, expiredQty, cancelledQty, boughtQty,
--         postedAuctions, soldAuctions, expiredAuctions, cancelledAuctions,
--         purchases, unmatchedSales }
--   m = { revenueGross, revenueNet, purchaseCost, depositPaid, depositLost,
--         matchedRevenueNet }
--   b = { Stueckpreis, Menge, ... }   Einkaufsstichproben
--   s = { Stueckpreis netto, Menge, ... }  Verkaufsstichproben
--   h = { letzteEinstellung, ganzePosition, ... }  Verkaufsdauer in 1/10 Stunden
--   f / l = erstes / letztes Ereignis (Unix-Sekunden)
--
-- open haelt die noch offenen Einstellungen als flache Sechsergruppen:
--   { itemID, postedAt, quantity, unitPrice, deposit, chainStart }
-- ---------------------------------------------------------------------------

local EVENT_STRIDE = 8
local KIND = { PURCHASE = 1, SALE = 2, POST = 3, EXPIRE = 4, CANCEL = 5 }
local KIND_NAME = {
    [1] = "purchase", [2] = "sale", [3] = "post", [4] = "expire", [5] = "cancel",
}
Ledger.KIND = KIND

local OPEN_STRIDE = 6

-- Lebensdauer eines Briefes im Postfach und die Rasterung, mit der der
-- Briefkasten-Abgleich arbeitet. Beides steht hier oben, weil das Aufraeumen
-- (Prune) es genauso braucht wie der Abgleich selbst; die Herleitung steht bei
-- ScanMailbox.
local MAIL_LIFETIME_DAYS = 30
local MAIL_BUCKET_SECONDS = 3600
local MAIL_BUCKET_TOLERANCE = 1

-- Laufzeitzustand. Gehoert bewusst nicht in die SavedVariables: Ein Cache muss
-- keinen Reload ueberleben, und ein kaputter Cache waere sonst dauerhaft.
Ledger.revision = 0
Ledger.itemCache = {}
Ledger.itemCacheRevision = nil
Ledger.globalCache = {}
Ledger.globalCacheRevision = nil
Ledger.hooked = false
Ledger.mailScanAt = nil

local function config()
    return GCP.Constants.LEDGER
end

local function clamp(value, low, high)
    if value < low then return low end
    if value > high then return high end
    return value
end

-- Saettigungskurve value / (value + half): 0 bei 0, 0,5 bei half, naehert sich
-- 1. Dieselbe Kurve wie in der Opportunity Engine - "mehr ist besser, aber
-- nicht linear" ist hier dieselbe Frage.
local function saturate(value, half)
    if type(value) ~= "number" or value <= 0 then return 0 end
    if type(half) ~= "number" or half <= 0 then return 1 end
    return value / (value + half)
end

local function isItemID(value)
    return type(value) == "number" and value > 0 and value == math.floor(value)
end

local function isPositive(value)
    return type(value) == "number" and value == value and value > 0
end

-- Beobachter bestaetigter Ereignisse (0.9.0). Die Guide Engine haengt sich
-- hier ein, um einen Kauf- oder Einstellschritt abzuhaken - das ist der
-- staerkste Beleg, den der Client hergibt, und deutlich besser als eine
-- Bestandsdifferenz. Fehler eines Beobachters duerfen die Erfassung nie
-- mitreissen, deshalb pcall.
function Ledger:Notify(kind, info)
    if GCP.Guide and type(GCP.Guide.OnLedgerEvent) == "function" then
        pcall(GCP.Guide.OnLedgerEvent, GCP.Guide, kind, info)
    end
    if GCP.Personal and type(GCP.Personal.OnLedgerEvent) == "function" then
        pcall(GCP.Personal.OnLedgerEvent, GCP.Personal, kind, info)
    end
end

function Ledger:Now()
    if GCP.Market then return GCP.Market:Now() end
    if type(time) == "function" then
        local ok, now = pcall(time)
        if ok and type(now) == "number" then return now end
    end
    return 0
end

-- Jede Aenderung an der Datenlage. Die Aggregat-Caches haengen daran, statt bei
-- jedem UI-Refresh ueber alle Ereignisse zu laufen.
function Ledger:Touch()
    self.revision = (self.revision or 0) + 1
    if GCP.Opportunity then GCP.Opportunity:Invalidate() end
    if GCP.Future then GCP.Future:Invalidate() end
end

-- ---------------------------------------------------------------------------
-- Speicher
-- ---------------------------------------------------------------------------

function Ledger:EnsureStore()
    local db = GCP.db
    if not db then return nil end
    local L = config()
    local store = db.ledger
    if type(store) ~= "table"
        or type(store.events) ~= "table"
        or type(store.items) ~= "table"
        or type(store.epoch) ~= "number"
        or store.version ~= L.STORE_VERSION then
        store = {
            version = L.STORE_VERSION,
            epoch = self:Now(),
            events = {},
            items = {},
            open = {},
            names = {},
            mail = {},
        }
        db.ledger = store
        self:Touch()
    end
    if type(store.open) ~= "table" then store.open = {} end
    if type(store.names) ~= "table" then store.names = {} end
    if type(store.mail) ~= "table" then store.mail = {} end
    return store
end

function Ledger:Reset()
    local db = GCP.db
    if not db then return 0 end
    local removed = 0
    local store = db.ledger
    if type(store) == "table" and type(store.events) == "table" then
        removed = math.floor(#store.events / EVENT_STRIDE)
    end
    db.ledger = nil
    self.itemCache = {}
    self.globalCache = {}
    self.itemCacheRevision = nil
    self.globalCacheRevision = nil
    self:Touch()
    self:EnsureStore()
    return removed
end

-- Der Bezugszeitpunkt darf nie hinter dem aeltesten Ereignis liegen, sonst
-- werden Minuten-Offsets negativ. Wie in Market.lua wandern beim Verschieben
-- alle Offsets mit.
function Ledger:RebaseEpoch(store, newEpoch)
    if type(newEpoch) ~= "number" then return end
    local deltaMinutes = math.floor((store.epoch - newEpoch) / 60)
    if deltaMinutes == 0 then return end
    local events = store.events
    for index = 2, #events, EVENT_STRIDE do
        events[index] = events[index] + deltaMinutes
    end
    store.epoch = store.epoch - deltaMinutes * 60
end

local function eventTimestamp(store, minute)
    return store.epoch + minute * 60
end

-- ---------------------------------------------------------------------------
-- Item-Namen. Die Verkaufsrechnung des Clients nennt nur den Namen, nie die
-- Item-ID. Aufgeloest wird ausschliesslich ueber Namen, die Gold Copilot selbst
-- schon einmal gesehen hat - beim Einstellen oder beim Kauf. Taucht derselbe
-- Name fuer zwei verschiedene IDs auf, wird der Eintrag dauerhaft auf false
-- gesetzt: Ein mehrdeutiger Name wird nie wieder aufgeloest, lieber unbekannt
-- als falsch zugeordnet.
-- ---------------------------------------------------------------------------

function Ledger:RememberName(itemID, name)
    if not isItemID(itemID) then return false end
    if type(name) ~= "string" or name == "" then return false end
    local store = self:EnsureStore()
    if not store then return false end
    local known = store.names[name]
    if known == itemID then return false end
    if known == nil then
        store.names[name] = itemID
        return true
    end
    if known ~= false then
        store.names[name] = false
    end
    return false
end

function Ledger:ResolveName(name)
    if type(name) ~= "string" or name == "" then return nil end
    local store = self:EnsureStore()
    if not store then return nil end
    local known = store.names[name]
    if isItemID(known) then return known end
    return nil
end

-- ---------------------------------------------------------------------------
-- Ereignisse schreiben
-- ---------------------------------------------------------------------------

-- Ein Eintrag ist nur brauchbar, wenn seine fuenf Listen da sind. WoW schreibt
-- SavedVariables beim Beenden; ein Absturz mittendrin kann eine halbe Datei
-- hinterlassen. Ein halber Eintrag wird verworfen, nicht repariert - eine
-- Statistik aus Bruchstuecken waere schlimmer als keine.
local function isValidItem(entry)
    return type(entry) == "table"
        and type(entry.c) == "table" and type(entry.m) == "table"
        and type(entry.b) == "table" and type(entry.s) == "table"
        and type(entry.h) == "table"
end

local function ensureItem(store, itemID)
    local entry = store.items[itemID]
    if entry and not isValidItem(entry) then
        entry = nil
        store.items[itemID] = nil
    end
    if not entry then
        entry = {
            c = { 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 },
            m = { 0, 0, 0, 0, 0, 0 },
            b = {}, s = {}, h = {},
        }
        store.items[itemID] = entry
    end
    -- Aeltere Eintraege koennen kuerzere Zaehlerlisten haben, wenn spaetere
    -- Fassungen einen Zaehler ergaenzen. Auffuellen statt neu anlegen.
    for index = 1, 11 do entry.c[index] = entry.c[index] or 0 end
    for index = 1, 6 do entry.m[index] = entry.m[index] or 0 end
    return entry
end

-- Haengt eine Stichprobe an und wirft die aelteste weg, sobald der Deckel
-- greift. Paarweise (Wert, Gewicht), damit Mediane nach Stueckzahl gewichtet
-- werden koennen.
local function pushSample(list, value, weight)
    local L = config()
    list[#list + 1] = value
    list[#list + 1] = weight
    local maxEntries = L.MAX_SAMPLES * 2
    while #list > maxEntries do
        table.remove(list, 1)
        table.remove(list, 1)
    end
end

function Ledger:AppendEvent(kind, timestamp, itemID, quantity, unitA, unitB, flags, extra)
    local store = self:EnsureStore()
    if not store then return false end
    timestamp = timestamp or self:Now()
    if timestamp < store.epoch then
        self:RebaseEpoch(store, timestamp)
    end
    local events = store.events
    local minute = math.floor((timestamp - store.epoch) / 60)
    events[#events + 1] = kind
    events[#events + 1] = minute
    events[#events + 1] = itemID or 0
    events[#events + 1] = quantity or 0
    events[#events + 1] = math.floor((unitA or 0) + 0.5)
    events[#events + 1] = math.floor((unitB or 0) + 0.5)
    events[#events + 1] = flags or 0
    events[#events + 1] = extra or 0

    -- Der Deckel greift sofort, das Aufraeumen nach Alter laeuft gedrosselt:
    -- Ein unbegrenzt wachsender Speicher waere ein Fehler, stuendliches
    -- Durchsuchen aller Ereignisse eine Verschwendung.
    local maxEntries = config().MAX_EVENTS * EVENT_STRIDE
    while #events > maxEntries do
        for _ = 1, EVENT_STRIDE do table.remove(events, 1) end
    end
    return true
end

-- --- KAUF ------------------------------------------------------------------
--
-- Aufgeschrieben wird nur, was die Kaufrechnung des Auktionshauses belegt:
-- Item, Stueckzahl und der tatsaechlich gezahlte Betrag. Ein Kauf beim
-- Haendler, ein Handel mit einem Mitspieler oder eine Postsendung ist kein
-- Einkauf im Sinne dieser Bilanz - der Kapitaleinsatz waere derselbe, aber die
-- Datenlage waere geraten.
function Ledger:RecordPurchase(info)
    if type(info) ~= "table" then return false end
    local itemID = info.itemID
    if not isItemID(itemID) then return false end
    local quantity = info.quantity
    if not isPositive(quantity) then return false end
    quantity = math.floor(quantity)

    local unitPrice = info.unitPrice
    if not isPositive(unitPrice) then
        if isPositive(info.totalCost) then
            unitPrice = info.totalCost / quantity
        else
            return false
        end
    end
    local totalCost = math.floor(unitPrice * quantity + 0.5)
    unitPrice = math.floor(unitPrice + 0.5)
    if unitPrice <= 0 then return false end

    local store = self:EnsureStore()
    if not store then return false end
    local now = info.timestamp or self:Now()

    local entry = ensureItem(store, itemID)
    entry.c[5] = entry.c[5] + quantity
    entry.c[10] = entry.c[10] + 1
    entry.m[3] = entry.m[3] + totalCost
    entry.f = entry.f or now
    entry.l = now
    pushSample(entry.b, unitPrice, quantity)

    self:RememberName(itemID, info.name or GetItemInfoCompat(itemID))
    self:AppendEvent(KIND.PURCHASE, now, itemID, quantity, unitPrice, 0, 0)
    self:Touch()
    self:Notify("purchase", info)
    return true
end

-- --- VERKAUF ---------------------------------------------------------------
--
-- source entscheidet ueber die Sell-Through-Rechnung: Nur "ah" ist ein
-- Auktionsverkauf. Alles andere (Haendler, Handel, Post) wuerde die Frage
-- "wie oft geht meine Auktion durch?" verfaelschen und bleibt deshalb aus den
-- Zaehlern heraus. Heute ruft nichts im Addon RecordSale mit einer anderen
-- Quelle auf - die Weiche steht trotzdem hier, damit sie spaeter nicht
-- vergessen wird.
--
-- quantity darf nil sein. Das heisst nicht "null", sondern "der Client hat es
-- nicht gesagt": Die Verkaufsrechnung nennt keine Stueckzahl. Solche Verkaeufe
-- zaehlen in den Umsatz, aber nie in eine Stueckzahl-Statistik - und sie
-- schalten die stueckzahlbasierte Sell-Through-Rate dieses Items ab, weil sie
-- sonst zu niedrig waere.
function Ledger:RecordSale(info)
    if type(info) ~= "table" then return false end
    local source = info.source or "ah"
    local itemID = info.itemID
    if itemID ~= nil and not isItemID(itemID) then return false end

    local quantity = info.quantity
    if quantity ~= nil and not isPositive(quantity) then quantity = nil end
    if quantity then quantity = math.floor(quantity) end

    local gross = info.totalGross
    if not isPositive(gross) then
        if isPositive(info.unitPriceGross) and quantity then
            gross = info.unitPriceGross * quantity
        else
            return false
        end
    end

    -- Die AH-Gebuehr genau einmal: Die Rechnung des Clients nennt sie als
    -- consignment, und dann gilt genau dieser Betrag. Fehlt sie, gilt der in
    -- Constants hinterlegte AH-Satz - dieselbe Zahl, mit der jede andere
    -- Rechnung im Addon arbeitet. Ein zweiter Abzug findet nirgends statt.
    local net = info.totalNet
    if not isPositive(net) then
        if type(info.consignment) == "number" and info.consignment >= 0 then
            net = gross - info.consignment
        else
            net = GCP.Prices:NetAuction(gross)
        end
    end
    if not isPositive(net) then return false end

    local store = self:EnsureStore()
    if not store then return false end
    local now = info.timestamp or self:Now()
    local matchQuality = info.matchQuality or config().MATCH.NONE

    local unitGross = quantity and math.floor(gross / quantity + 0.5) or math.floor(gross + 0.5)
    local unitNet = quantity and math.floor(net / quantity + 0.5) or math.floor(net + 0.5)

    if itemID then
        local entry = ensureItem(store, itemID)
        entry.m[1] = entry.m[1] + gross
        entry.m[2] = entry.m[2] + net
        entry.f = entry.f or now
        entry.l = now
        if source == "ah" then
            entry.c[7] = entry.c[7] + 1
            if quantity then
                entry.c[2] = entry.c[2] + quantity
                entry.m[6] = entry.m[6] + net
                pushSample(entry.s, unitNet, quantity)
            else
                entry.c[11] = entry.c[11] + 1
            end
            if isPositive(info.holdHours) then
                local chain = isPositive(info.chainHours) and info.chainHours or info.holdHours
                pushSample(entry.h,
                    math.floor(info.holdHours * 10 + 0.5),
                    math.floor(chain * 10 + 0.5))
            end
        end
        self:RememberName(itemID, info.name or GetItemInfoCompat(itemID))
    end

    self:AppendEvent(KIND.SALE, now, itemID or 0, quantity or 0,
        unitGross, unitNet, matchQuality,
        isPositive(info.holdHours) and math.floor(info.holdHours * 10 + 0.5) or 0)
    self:Touch()
    self:Notify("sale", info)
    return true
end

-- --- EINSTELLEN ------------------------------------------------------------
--
-- Eine Zeile je Auktion, nicht je Klick: Wer fuenf Stapel auf einmal
-- einstellt, hat fuenf Auktionen, und jede kann einzeln verkaufen oder
-- ablaufen. Genau das ist die Grundlage der stueckzahlbasierten Rechnung.
function Ledger:RecordAuctionPosted(info)
    if type(info) ~= "table" then return false end
    local itemID = info.itemID
    if not isItemID(itemID) then return false end
    local quantity = info.quantity
    if not isPositive(quantity) then return false end
    quantity = math.floor(quantity)
    local unitPrice = info.unitPrice
    if not isPositive(unitPrice) then
        if isPositive(info.totalPrice) then
            unitPrice = info.totalPrice / quantity
        else
            return false
        end
    end
    unitPrice = math.floor(unitPrice + 0.5)

    local store = self:EnsureStore()
    if not store then return false end
    local now = info.timestamp or self:Now()
    local deposit = isPositive(info.deposit) and math.floor(info.deposit + 0.5) or 0
    local hours = isPositive(info.durationHours) and math.floor(info.durationHours + 0.5) or 0

    local entry = ensureItem(store, itemID)
    entry.c[1] = entry.c[1] + quantity
    entry.c[6] = entry.c[6] + 1
    entry.m[4] = entry.m[4] + deposit
    entry.f = entry.f or now
    entry.l = now

    -- Relisting: Ist dasselbe Item kurz zuvor abgelaufen, gilt die neue
    -- Einstellung als Fortsetzung derselben Position. Nur fuer die Haltedauer -
    -- der Fehlschlag bleibt in der Sell-Through-Rate stehen.
    local chainStart = self:ClaimRelistChain(store, itemID, now) or now

    local open = store.open
    open[#open + 1] = itemID
    open[#open + 1] = now
    open[#open + 1] = quantity
    open[#open + 1] = unitPrice
    open[#open + 1] = deposit
    open[#open + 1] = chainStart

    local maxOpen = config().MAX_OPEN_POSTINGS * OPEN_STRIDE
    while #open > maxOpen do
        for _ = 1, OPEN_STRIDE do table.remove(open, 1) end
    end

    self:RememberName(itemID, info.name or GetItemInfoCompat(itemID))
    self:AppendEvent(KIND.POST, now, itemID, quantity, unitPrice, deposit, hours)
    self:Touch()
    self:Notify("post", info)
    return true
end

-- --- ABLAUF ----------------------------------------------------------------
--
-- Der einzige belegte Fehlschlag: Die Auktion lief durch und niemand hat
-- gekauft. Die Post bringt das Item zurueck, die Einstellgebuehr ist weg.
function Ledger:RecordAuctionExpired(info)
    if type(info) ~= "table" then return false end
    local itemID = info.itemID
    if not isItemID(itemID) then return false end
    local quantity = info.quantity
    if not isPositive(quantity) then return false end
    quantity = math.floor(quantity)

    local store = self:EnsureStore()
    if not store then return false end
    local now = info.timestamp or self:Now()

    local posting = self:TakeOpenPosting(store, itemID, quantity, nil)
    local unitPrice = posting and posting.unitPrice or 0
    local lostDeposit = posting and posting.deposit or 0

    local entry = ensureItem(store, itemID)
    entry.c[3] = entry.c[3] + quantity
    entry.c[8] = entry.c[8] + 1
    entry.m[5] = entry.m[5] + lostDeposit
    entry.f = entry.f or now
    entry.l = now

    -- Merken, damit eine Neu-Einstellung innerhalb der Frist die Haltedauer
    -- fortschreiben kann.
    self:RememberRelistChain(store, itemID, now,
        posting and posting.chainStart or nil)

    self:AppendEvent(KIND.EXPIRE, now, itemID, quantity, unitPrice, lostDeposit, 0)
    self:Touch()
    self:Notify("expire", info)
    return true
end

-- --- ZURUECKGEZOGEN --------------------------------------------------------
--
-- Ausdruecklich KEIN Fehlschlag. Wer eine Auktion abbricht, hat sich
-- umentschieden, unterboten gesehen oder umgepreist - das sagt nichts darueber
-- aus, ob das Item gekauft worden waere. Deshalb taucht cancelled in keiner
-- Sell-Through-Rechnung auf; nur die verlorene Einstellgebuehr bleibt eine
-- echte Kostenposition.
function Ledger:RecordAuctionCancelled(info)
    if type(info) ~= "table" then return false end
    local itemID = info.itemID
    if not isItemID(itemID) then return false end
    local quantity = info.quantity
    if not isPositive(quantity) then return false end
    quantity = math.floor(quantity)

    local store = self:EnsureStore()
    if not store then return false end
    local now = info.timestamp or self:Now()

    local posting = self:TakeOpenPosting(store, itemID, quantity, nil)
    local unitPrice = posting and posting.unitPrice or 0
    local lostDeposit = posting and posting.deposit or 0

    local entry = ensureItem(store, itemID)
    entry.c[4] = entry.c[4] + quantity
    entry.c[9] = entry.c[9] + 1
    entry.m[5] = entry.m[5] + lostDeposit
    entry.f = entry.f or now
    entry.l = now

    self:AppendEvent(KIND.CANCEL, now, itemID, quantity, unitPrice, lostDeposit, 0)
    self:Touch()
    self:Notify("cancel", info)
    return true
end

-- ---------------------------------------------------------------------------
-- Offene Einstellungen
--
-- Die klassische Auktions-API kennt keine Auktions-ID. Die Zuordnung
-- Einstellung -> Verkauf ist deshalb immer eine Rekonstruktion, und sie wird
-- hier in drei Stufen gemacht, deren Guete mitgespeichert wird:
--
--   EXACT   Es gibt eine offene Einstellung dieses Items, bei der
--           Stueckpreis x Stueckzahl genau dem Rechnungsbetrag entspricht.
--           Das ist ein Sofortkauf zum eingestellten Preis - eindeutig.
--   UNIQUE  Es gibt genau eine offene Einstellung dieses Items. Der Betrag
--           passt nicht (ein Gebot unter dem Sofortkaufpreis), aber es kommt
--           nichts anderes in Frage.
--   NONE    Mehrere offene Einstellungen und kein passender Betrag, oder gar
--           keine. Dann bleibt die Stueckzahl UNBEKANNT. Der Umsatz zaehlt,
--           die Sell-Through-Rate dieses Items wird abgeschaltet - eine Rate,
--           die einen echten Verkauf nicht mitzaehlt, waere zu niedrig, und
--           eine zu niedrige Rate ist eine Falschaussage.
-- ---------------------------------------------------------------------------

local function readPosting(open, base)
    return {
        base = base,
        itemID = open[base + 1],
        postedAt = open[base + 2],
        quantity = open[base + 3],
        unitPrice = open[base + 4],
        deposit = open[base + 5],
        chainStart = open[base + 6],
    }
end

local function removePosting(open, base)
    for _ = 1, OPEN_STRIDE do
        table.remove(open, base + 1)
    end
end

-- Nimmt eine offene Einstellung heraus. Bevorzugt die mit passender
-- Stueckzahl, sonst die aelteste des Items - eine Auktion, die laenger liegt,
-- laeuft zuerst ab.
function Ledger:TakeOpenPosting(store, itemID, quantity, totalPrice)
    local open = store.open
    local fallback = nil
    for base = 0, #open - OPEN_STRIDE, OPEN_STRIDE do
        if open[base + 1] == itemID then
            local posting = readPosting(open, base)
            if totalPrice and posting.unitPrice * posting.quantity == totalPrice then
                removePosting(open, base)
                return posting
            end
            if quantity and posting.quantity == quantity and not totalPrice then
                removePosting(open, base)
                return posting
            end
            if not fallback then fallback = posting end
        end
    end
    if fallback then
        removePosting(open, fallback.base)
        return fallback
    end
    return nil
end

function Ledger:CountOpenPostings(itemID)
    local store = self:EnsureStore()
    if not store then return 0 end
    local open = store.open
    local count = 0
    for base = 0, #open - OPEN_STRIDE, OPEN_STRIDE do
        if itemID == nil or open[base + 1] == itemID then
            count = count + 1
        end
    end
    return count
end

-- Sucht die Einstellung zu einer Verkaufsrechnung. Rueckgabe: Einstellung und
-- Guete, oder nil und MATCH.NONE.
function Ledger:MatchSale(store, itemID, totalPrice)
    local M = config().MATCH
    local open = store.open
    local candidates, onlyOne = 0, nil
    for base = 0, #open - OPEN_STRIDE, OPEN_STRIDE do
        if open[base + 1] == itemID then
            local posting = readPosting(open, base)
            if totalPrice and posting.unitPrice * posting.quantity == totalPrice then
                removePosting(open, base)
                return posting, M.EXACT
            end
            candidates = candidates + 1
            onlyOne = posting
        end
    end
    if candidates == 1 and onlyOne then
        removePosting(open, onlyOne.base)
        return onlyOne, M.UNIQUE
    end
    return nil, M.NONE
end

-- Relisting-Kette. Absichtlich kein eigener Speicher in den SavedVariables:
-- Die Kette lebt nur so lange, wie das Fenster offen ist, und ein Reload
-- dazwischen kostet hoechstens die Kettenzeit einer einzigen Position - nicht
-- die Sell-Through-Rate und nicht die exakte Verkaufsdauer.
Ledger.relistChains = {}

function Ledger:RememberRelistChain(store, itemID, expiredAt, chainStart)
    self.relistChains[itemID] = {
        expiredAt = expiredAt,
        chainStart = chainStart or expiredAt,
    }
end

function Ledger:ClaimRelistChain(store, itemID, now)
    local chain = self.relistChains[itemID]
    if not chain then return nil end
    self.relistChains[itemID] = nil
    if (now - chain.expiredAt) > config().RELIST_WINDOW then return nil end
    return chain.chainStart
end

-- ---------------------------------------------------------------------------
-- Aufraeumen
--
-- Gedrosselt: Ein Ereignis auszuloesen ist billig, ueber alle Ereignisse zu
-- laufen nicht. Deshalb laeuft das hier beim Login und danach hoechstens
-- stuendlich - nie im OnUpdate und nie bei jedem Refresh.
-- ---------------------------------------------------------------------------

function Ledger:Prune(now, force)
    local store = self:EnsureStore()
    if not store then return 0 end
    local L = config()
    now = now or self:Now()
    if not force and type(store.prunedAt) == "number"
        and (now - store.prunedAt) < L.PRUNE_INTERVAL then
        return 0
    end
    store.prunedAt = now
    local removed = 0

    -- 1. Rohereignisse aelter als die Aufbewahrungsfrist. Die Aggregate je Item
    --    bleiben davon unberuehrt - sie sind das Langzeitgedaechtnis.
    --
    --    Gefiltert wird ueber die ganze Liste statt vorn abgeschnitten: Die
    --    Ereignisse stehen ZEITLICH NICHT ZWINGEND IN ORDNUNG. Der Briefkasten
    --    wird in Postfach-Reihenfolge gelesen, und die ist nicht die Reihenfolge
    --    der Ankunft - ein Abschneiden am Anfang wuerde je nach Postfach mal zu
    --    viel und mal zu wenig entfernen.
    local cutoffMinute = math.floor((now - L.RETENTION_DAYS * 86400 - store.epoch) / 60)
    local events = store.events
    local kept = {}
    local oldestMinute = nil
    for base = 0, #events - EVENT_STRIDE, EVENT_STRIDE do
        local minute = events[base + 2]
        if minute >= cutoffMinute then
            for offset = 1, EVENT_STRIDE do
                kept[#kept + 1] = events[base + offset]
            end
            if oldestMinute == nil or minute < oldestMinute then oldestMinute = minute end
        else
            removed = removed + 1
        end
    end
    if removed > 0 then
        store.events = kept
        events = kept
    end
    if oldestMinute and oldestMinute > 0 then
        self:RebaseEpoch(store, eventTimestamp(store, oldestMinute))
    end

    -- 2. Offene Einstellungen, die niemand mehr zuordnen kann. Eine Auktion
    --    laeuft hoechstens 48 h, ihre Post liegt bis zu 30 Tage.
    local open = store.open
    local keptOpen = {}
    for base = 0, #open - OPEN_STRIDE, OPEN_STRIDE do
        if (now - (open[base + 2] or 0)) <= L.OPEN_POSTING_TTL then
            for offset = 1, OPEN_STRIDE do
                keptOpen[#keptOpen + 1] = open[base + offset]
            end
        end
    end
    store.open = keptOpen

    -- 3. Postfach-Index. Ein Eintrag wird gebraucht, solange die zugehoerige
    --    Post im Briefkasten liegen kann - AH-Post lebt 30 Tage. Danach kann
    --    sie nicht mehr doppelt gezaehlt werden, weil es sie nicht mehr gibt.
    --    Zusaetzlich ein Deckel: Der Index darf nicht der Teil sein, der die
    --    SavedVariables sprengt.
    local nowMinute = math.floor(now / 60)
    local mailCutoff = nowMinute - (MAIL_LIFETIME_DAYS + 5) * 1440
    local mailKeys = {}
    for key, entry in pairs(store.mail) do
        if type(entry) ~= "table" or type(entry[3]) ~= "number"
            or entry[3] < mailCutoff then
            store.mail[key] = nil
        else
            mailKeys[#mailKeys + 1] = { key = key, seenAt = entry[3] }
        end
    end
    if #mailKeys > L.MAX_MAIL_KEYS then
        table.sort(mailKeys, function(a, b)
            if a.seenAt ~= b.seenAt then return a.seenAt > b.seenAt end
            return a.key < b.key
        end)
        for index = L.MAX_MAIL_KEYS + 1, #mailKeys do
            store.mail[mailKeys[index].key] = nil
        end
    end

    -- 4. Deckel fuer die Item-Aggregate. Faellt er, fallen die Items mit der
    --    aeltesten letzten Aktivitaet - womit gerade gehandelt wird, bleibt.
    local itemCount = 0
    for _ in pairs(store.items) do itemCount = itemCount + 1 end
    if itemCount > L.MAX_ITEMS then
        local order = {}
        for itemID, entry in pairs(store.items) do
            order[#order + 1] = { itemID = itemID, lastAt = entry.l or 0 }
        end
        table.sort(order, function(a, b)
            if a.lastAt ~= b.lastAt then return a.lastAt > b.lastAt end
            return a.itemID < b.itemID
        end)
        for index = L.MAX_ITEMS + 1, #order do
            store.items[order[index].itemID] = nil
            removed = removed + 1
        end
    end

    if removed > 0 then self:Touch() end
    return removed
end

-- ---------------------------------------------------------------------------
-- SELL-THROUGH
--
--     sellThrough = soldQuantity / (soldQuantity + expiredQuantity)
--
-- Stueckzahlbasiert, nicht ereignisbasiert. 100 eingestellt, 60 verkauft, 40
-- abgelaufen sind 60 % - nicht 50 %, nur weil es eine Verkaufsmeldung und eine
-- Ablaufmeldung gab.
--
-- Zurueckgezogene Auktionen stehen in KEINEM der beiden Summanden. Ein Abbruch
-- ist eine Entscheidung des Spielers, kein Urteil des Marktes.
--
-- Zusaetzlich, weil beides verschiedene Fragen beantwortet:
--     sellThroughAuctions = soldAuctions / (soldAuctions + expiredAuctions)
-- Diese Rate ist immer verfuegbar, auch wenn eine Stueckzahl fehlt: Jede
-- Verkaufsrechnung ist genau eine verkaufte Auktion, ganz gleich wie gross der
-- Stapel war.
--
-- Konnte auch nur ein Verkauf dieses Items nicht zugeordnet werden, gibt es
-- KEINE stueckzahlbasierte Rate. Sie waere zu niedrig, und "verkauft sich
-- schlechter als er tut" ist genau die Art Falschaussage, die dieses Modul
-- nicht machen soll.
-- ---------------------------------------------------------------------------

function Ledger:SellThroughConfidence(auctions, units)
    local C = config().CONFIDENCE
    if auctions <= 0 then return "none" end
    if auctions >= C.HIGH_AUCTIONS and units >= C.HIGH_UNITS then return "high" end
    if auctions >= C.MEDIUM_AUCTIONS and units >= C.MEDIUM_UNITS then return "medium" end
    return "low"
end

function Ledger:ConfidenceLabel(confidence)
    return GCP.Market:ConfidenceLabel(confidence)
end

-- ---------------------------------------------------------------------------
-- Statistik. Wie in Market.lua bewusst ohne Fremdbibliothek.
-- ---------------------------------------------------------------------------

local function quantile(sorted, q)
    local n = #sorted
    if n == 0 then return nil end
    if n == 1 then return sorted[1] end
    local position = 1 + (n - 1) * q
    local lower = math.floor(position)
    local upper = math.ceil(position)
    if lower == upper then return sorted[lower] end
    return sorted[lower] + (sorted[upper] - sorted[lower]) * (position - lower)
end

-- Nach Gewicht gewichteter Median: Die Stichproben werden nach Wert sortiert
-- und die Gewichte aufsummiert; der Median ist der Wert, bei dem die halbe
-- Gesamtmenge erreicht ist. Ein Stapel von 20 zaehlt damit zwanzigmal so viel
-- wie ein Einzelstueck - was er auch ist.
local function weightedMedian(pairsList)
    if type(pairsList) ~= "table" or #pairsList < 2 then return nil end
    local samples = {}
    local total = 0
    for index = 1, #pairsList - 1, 2 do
        local weight = pairsList[index + 1] or 1
        if weight > 0 then
            samples[#samples + 1] = { pairsList[index], weight }
            total = total + weight
        end
    end
    if total <= 0 then return nil end
    table.sort(samples, function(a, b) return a[1] < b[1] end)
    local half = total / 2
    local running = 0
    for _, sample in ipairs(samples) do
        running = running + sample[2]
        if running >= half then return math.floor(sample[1] + 0.5) end
    end
    return math.floor(samples[#samples][1] + 0.5)
end

local function weightedAverage(pairsList)
    if type(pairsList) ~= "table" or #pairsList < 2 then return nil end
    local sum, weightSum = 0, 0
    for index = 1, #pairsList - 1, 2 do
        local weight = pairsList[index + 1] or 1
        if weight > 0 then
            sum = sum + pairsList[index] * weight
            weightSum = weightSum + weight
        end
    end
    if weightSum <= 0 then return nil end
    return math.floor(sum / weightSum + 0.5)
end

-- ---------------------------------------------------------------------------
-- ZEIT BIS ZUM VERKAUF
--
-- Gespeichert wird die reale Spanne zwischen dem Einstellen und dem Eintreffen
-- der Verkaufsrechnung - und zwar zweimal, weil zwei verschiedene Fragen
-- dahinterstehen:
--
--   medianHours      Von der LETZTEN Einstellung bis zum Verkauf. Exakt
--                    gemessen, ohne jede Annahme. Das ist die Zahl, die im
--                    UI steht: "Median bis Verkauf".
--   medianHoldHours  Von der ERSTEN Einstellung derselben Position bis zum
--                    Verkauf, ueber Neu-Einstellungen hinweg. Das ist die
--                    Zeit, die das Kapital wirklich gebunden war - und damit
--                    die richtige Groesse fuer die Profit Velocity. Die
--                    Verkettung ist eine dokumentierte Rekonstruktion (siehe
--                    RELIST_WINDOW), deshalb steht sie nicht als Hauptzahl da.
--
-- Median statt Durchschnitt: Eine einzige Auktion, die 47 Stunden stand,
-- verschiebt einen Durchschnitt aus fuenf Werten um Stunden. Zusaetzlich p25
-- und p75, damit die Streuung sichtbar bleibt.
--
-- Ohne zuordenbare Einstellung gibt es keine Zahl, sondern nil. Kein
-- Schaetzwert, keine Auktionsdauer als Ersatz.
-- ---------------------------------------------------------------------------

function Ledger:TimeStats(hoursList)
    if type(hoursList) ~= "table" or #hoursList < 2 then return nil end
    local last, chain = {}, {}
    for index = 1, #hoursList - 1, 2 do
        last[#last + 1] = hoursList[index] / 10
        chain[#chain + 1] = hoursList[index + 1] / 10
    end
    table.sort(last)
    table.sort(chain)
    return {
        samples = #last,
        median = quantile(last, 0.5),
        p25 = quantile(last, 0.25),
        p75 = quantile(last, 0.75),
        medianHold = quantile(chain, 0.5),
    }
end

-- ---------------------------------------------------------------------------
-- LIQUIDITY SCORE 0-100
--
-- Er beantwortet genau eine Frage:
--   "Wie leicht bekomme ich dieses Item nach MEINER bisherigen Erfahrung
--    wieder in Gold zurueck?"
--
-- Ausdruecklich nicht: wie stark der Preis schwankt. Volatilitaet ist keine
-- Liquiditaet - ein Item kann tagelang beim selben Preis stehen und sich
-- trotzdem nie verkaufen. Die Markthistorie aus 0.5 fliesst hier deshalb an
-- keiner Stelle ein.
--
-- Drei Bausteine, alle ausschliesslich aus eigenen Verkaufsdaten:
--
--   1. SELL-THROUGH (55 Punkte)   -   verkauft es sich ueberhaupt?
--        Punkte = 55 * min(sellThrough / 0,9 ; 1)
--        90 % gelten als volle Punktzahl. Der Unterschied zwischen 90 % und
--        100 % ist Rauschen; 100 % zu verlangen hiesse, dass kein reales Item
--        je gut abschneidet.
--
--   2. GESCHWINDIGKEIT (30 Punkte)   -   und wie schnell?
--        Punkte = 30 * 24 / (24 + medianHours)
--        Saettigungskurve: ein Median von 24 h gibt die halbe Punktzahl, 4 h
--        rund 86 %, 96 h rund 20 %. Monoton, ohne Sprungstelle, ohne Explosion
--        bei sehr kleinen Zeiten.
--
--   3. WIEDERHOLUNG (15 Punkte)   -   und immer wieder?
--        Punkte = 15 * v / (v + 3), v = Verkaeufe je Woche im beobachteten
--        Zeitraum. Ein Item, das sich einmal im Monat verkauft, ist etwas
--        anderes als eines, das dreimal am Tag durchgeht - auch bei gleicher
--        Sell-Through-Rate.
--
-- FEHLENDE BAUSTEINE WERDEN NICHT ERFUNDEN, SONDERN HERAUSGERECHNET:
--   Ist die Verkaufsdauer unbekannt (Verkaeufe ohne zuordenbare Einstellung),
--   wird der Score aus den verbleibenden Bausteinen ueber deren Gewicht
--   normiert - nicht mit 0 Punkten fuer den fehlenden bestraft und nicht mit
--   einem erfundenen Mittelwert gefuellt.
--
-- HARTE DECKEL:
--   * Ohne Sell-Through-Rate gibt es gar keinen Score, sondern nil.
--   * Die Confidence deckelt: "niedrig" hoechstens 55, "mittel" hoechstens 80.
--     Drei Auktionen koennen nie "sehr liquide" ergeben.
--
-- BEISPIEL (die Zahlen aus dem Handel-Tab eines gut laufenden Materials):
--   sellThrough 0,87 · medianHours 4,2 · 8 Verkaeufe/Woche · confidence high
--     Sell-Through   55 * min(0,87/0,9 ; 1) = 55 * 0,967 = 53,2
--     Geschwindigkeit 30 * 24/(24+4,2)      = 30 * 0,851 = 25,5
--     Wiederholung   15 * 8/(8+3)           = 15 * 0,727 = 10,9
--     Summe 89,6 -> Score 90, Deckel 100 (high) -> 90
-- ---------------------------------------------------------------------------

function Ledger:ComputeLiquidityScore(input)
    if type(input) ~= "table" then return nil end
    local sellThrough = input.sellThrough
    if type(sellThrough) ~= "number" then return nil end
    local S = config().SCORE

    local availableWeight = 0
    local earned = 0
    local parts = {}

    local stFactor = clamp(sellThrough / S.SELL_THROUGH_TARGET, 0, 1)
    parts.sellThrough = S.SELL_THROUGH_POINTS * stFactor
    earned = earned + parts.sellThrough
    availableWeight = availableWeight + S.SELL_THROUGH_POINTS

    if type(input.medianHours) == "number" and input.medianHours >= 0 then
        local speedFactor = S.SPEED_HALF_HOURS / (S.SPEED_HALF_HOURS + input.medianHours)
        parts.speed = S.SPEED_POINTS * speedFactor
        earned = earned + parts.speed
        availableWeight = availableWeight + S.SPEED_POINTS
    end

    if type(input.salesPerWeek) == "number" and input.salesPerWeek > 0 then
        parts.repetition = S.REPEAT_POINTS * saturate(input.salesPerWeek, S.REPEAT_HALF_PER_WEEK)
        earned = earned + parts.repetition
        availableWeight = availableWeight + S.REPEAT_POINTS
    end

    if availableWeight <= 0 then return nil end
    local raw = 100 * earned / availableWeight
    local ceiling = S.CONFIDENCE_CAP[input.confidence or "none"] or 100
    parts.raw = raw
    parts.ceiling = ceiling
    parts.availableWeight = availableWeight
    return clamp(math.floor(math.min(raw, ceiling) + 0.5), 0, 100), parts
end

function Ledger:ScoreBand(score)
    if type(score) ~= "number" then return nil end
    for _, band in ipairs(config().BANDS) do
        if score >= band.min then return band.label, band.min end
    end
    return nil
end

-- ---------------------------------------------------------------------------
-- PROFIT VELOCITY
--
-- Die Frage lautet nicht "wie viel Gewinn?", sondern:
--   "Wie schnell waechst mein eingesetztes Kapital?"
--
--     erwarteterGewinn = expectedProfit * sellThrough
--     haltedauerTage   = max(holdingHours ; 2 h) / 24
--     velocity         = erwarteterGewinn / kapital / haltedauerTage     [1/Tag]
--
-- und daraus die Zahl, die ein Mensch lesen kann:
--
--     Gewinn je 100 g gebundenem Kapital und Tag = velocity * 100 g
--
-- WARUM SO:
--   * sellThrough gehoert in den ZAEHLER, nicht in die Zeit. Es ist die
--     Wahrscheinlichkeit, dass der Gewinn ueberhaupt eintritt. Die Haltedauer
--     dagegen ist die gemessene Zeit der Verkaeufe, die stattgefunden haben.
--     Beides in die Zeit zu stecken, wuerde dasselbe Risiko zweimal zaehlen.
--   * Die Untergrenze von zwei Stunden verhindert die Division durch eine
--     winzige Zeit. Ohne sie waere ein einziger Verkauf nach vier Minuten eine
--     Rendite von mehreren tausend Prozent am Tag.
--   * Ohne sellThrough oder ohne gemessene Haltedauer gibt es KEINE Zahl,
--     sondern nil. Eine geschaetzte Verkaufsdauer waere hier der teuerste
--     Fehler von allen.
--
-- WAS DIE ZAHL NICHT SAGT: Sie ist eine Rate je eingesetztem Gold, keine
-- Aussage ueber die Menge. Ein Craft mit 65 g Einsatz und einer Velocity von
-- 100 g je 100 g und Tag laesst sich nicht mit 10.000 g fahren - der Markt
-- nimmt nicht 150 Stueck am Tag ab. Die Markttiefe kennt Gold Copilot nicht
-- und behauptet sie auch nicht.
--
-- BEISPIEL: Craft, Materialkosten 65 g, theoretischer Gewinn 19 g,
--           sellThrough 0,88, Haltedauer 5,4 h
--     erwarteterGewinn = 19 * 0,88 = 16,72 g
--     haltedauerTage   = 5,4 / 24  = 0,225
--     velocity         = 16,72 / 65 / 0,225 = 1,143 je Tag
--     je 100 g Kapital und Tag                = 114,3 g
-- ---------------------------------------------------------------------------

function Ledger:ProfitVelocity(input)
    if type(input) ~= "table" then return nil end
    local V = config().VELOCITY
    local profit, capital = input.expectedProfit, input.capital
    if not isPositive(profit) or not isPositive(capital) then return nil end
    local sellThrough = input.sellThrough
    if type(sellThrough) ~= "number" or sellThrough < 0 then return nil end
    local hours = input.holdingHours
    if type(hours) ~= "number" or hours < 0 then return nil end

    local effectiveHours = math.max(hours, V.MIN_HOLDING_HOURS)
    local days = effectiveHours / 24
    local expected = profit * sellThrough
    local velocity = expected / capital / days
    return velocity, {
        expectedProfit = expected,
        holdingHours = effectiveHours,
        clamped = effectiveHours > hours,
        perReferenceCapital = velocity * V.REFERENCE_CAPITAL,
    }
end

function Ledger:FormatVelocity(perReferenceCapital)
    if type(perReferenceCapital) ~= "number" then return "–" end
    return string.format("%s / 100 g / Tag",
        GCP.Prices:FormatGold(perReferenceCapital))
end

-- ---------------------------------------------------------------------------
-- Item-Statistik
-- ---------------------------------------------------------------------------

function Ledger:ComputeItemStats(itemID)
    local store = self:EnsureStore()
    if not store then return nil end
    local entry = store.items[itemID]
    if not isValidItem(entry) then return nil end
    local c, m = entry.c, entry.m

    local soldQuantity, expiredQuantity = c[2] or 0, c[3] or 0
    local soldAuctions, expiredAuctions = c[7] or 0, c[8] or 0
    local unmatchedSales = c[11] or 0
    local boughtQuantity = c[5] or 0

    local stats = {
        itemID = itemID,
        postedQuantity = c[1] or 0,
        soldQuantity = soldQuantity,
        expiredQuantity = expiredQuantity,
        cancelledQuantity = c[4] or 0,
        boughtQuantity = boughtQuantity,
        postedAuctions = c[6] or 0,
        soldAuctions = soldAuctions,
        expiredAuctions = expiredAuctions,
        cancelledAuctions = c[9] or 0,
        purchases = c[10] or 0,
        unmatchedSales = unmatchedSales,
        revenueGross = m[1] or 0,
        revenueNet = m[2] or 0,
        purchaseCost = m[3] or 0,
        depositPaid = m[4] or 0,
        depositLost = m[5] or 0,
        matchedRevenueNet = m[6] or 0,
        firstAt = entry.f,
        lastAt = entry.l,
        openPostings = self:CountOpenPostings(itemID),
    }

    -- Sell-Through, stueckzahlbasiert. Nur wenn jeder Verkauf zugeordnet ist.
    local resolvedUnits = soldQuantity + expiredQuantity
    if unmatchedSales == 0 and resolvedUnits > 0 then
        stats.sellThrough = soldQuantity / resolvedUnits
    end
    local resolvedAuctions = soldAuctions + expiredAuctions
    if resolvedAuctions > 0 then
        stats.sellThroughAuctions = soldAuctions / resolvedAuctions
    end
    stats.confidence = self:SellThroughConfidence(resolvedAuctions, resolvedUnits)
    if stats.sellThrough == nil then
        -- Ohne stueckzahlbasierte Rate gibt es keine Aussage ueber Liquiditaet,
        -- egal wie viele Auktionen bekannt sind.
        stats.confidence = unmatchedSales > 0 and "none" or stats.confidence
    end

    -- Verkaufsdauer.
    local timeStats = self:TimeStats(entry.h)
    if timeStats then
        stats.medianHours = timeStats.median
        stats.p25Hours = timeStats.p25
        stats.p75Hours = timeStats.p75
        stats.medianHoldHours = timeStats.medianHold
        stats.timeSamples = timeStats.samples
    end

    -- Wiederholungshaeufigkeit: Verkaufte Auktionen je Woche im beobachteten
    -- Zeitraum. Unter einem Tag Beobachtung gibt es keine Rate - sonst waere
    -- ein einziger Verkauf in der ersten Stunde "168 Verkaeufe pro Woche".
    if entry.f and entry.l and soldAuctions > 0 then
        local spanSeconds = math.max(entry.l - entry.f, 0)
        if spanSeconds >= 86400 then
            stats.spanDays = spanSeconds / 86400
            stats.salesPerWeek = soldAuctions / (spanSeconds / 604800)
        end
    end

    -- Persoenliche Preise, nach Stueckzahl gewichtet.
    stats.averageBuyPrice = boughtQuantity > 0
        and math.floor((m[3] or 0) / boughtQuantity + 0.5) or nil
    stats.medianBuyPrice = weightedMedian(entry.b)
    stats.averageSellPrice = soldQuantity > 0
        and math.floor((m[6] or 0) / soldQuantity + 0.5) or nil
    stats.medianSellPrice = weightedMedian(entry.s)
    if stats.medianBuyPrice and stats.medianBuyPrice > 0 and stats.medianSellPrice then
        stats.realizedMargin =
            (stats.medianSellPrice - stats.medianBuyPrice) / stats.medianBuyPrice
    end
    stats.averageBuyPriceUnweighted = weightedAverage(entry.b)

    -- Realisierter Gewinn. Gewichteter Durchschnittspreis als Kostenbasis - eine
    -- echte FIFO-/LIFO-Buchhaltung gibt die Datenlage nicht her, und sie zu
    -- behaupten waere schlimmer als sie wegzulassen.
    --
    -- Selbst gefarmte, gecraftete oder erbeutete Stuecke bekommen KEINE
    -- Kostenbasis 0. Wer 60 Stueck verkauft, aber nur 20 gekauft hat, hat 40
    -- Stueck unbekannter Herkunft - dann gibt es keinen realisierten Gewinn,
    -- sondern nil und die Angabe, wie weit die Kostenbasis traegt.
    if soldQuantity > 0 then
        stats.costBasisCoverage = math.min(boughtQuantity / soldQuantity, 1)
        if boughtQuantity >= soldQuantity and stats.averageBuyPrice then
            stats.costBasisKnown = true
            local attributableCost = stats.averageBuyPrice * soldQuantity
            stats.attributableCost = attributableCost
            stats.realizedProfit = (m[6] or 0) - attributableCost - (m[5] or 0)
        else
            stats.costBasisKnown = false
        end
    end

    -- Liquidity Score.
    local score, parts = self:ComputeLiquidityScore({
        sellThrough = stats.sellThrough,
        medianHours = stats.medianHours,
        salesPerWeek = stats.salesPerWeek,
        confidence = stats.confidence,
    })
    stats.liquidityScore = score
    stats.liquidityParts = parts
    -- Die Zahl, mit der die Chancen-Engine rechnet: gemessene Haltedauer der
    -- ganzen Position, sonst die exakte Dauer der letzten Einstellung.
    stats.expectedHours = stats.medianHours
    stats.holdingHours = stats.medianHoldHours or stats.medianHours
    return stats
end

function Ledger:GetItemStats(itemID)
    if not isItemID(itemID) then return nil end
    if self.itemCacheRevision ~= self.revision then
        self.itemCache = {}
        self.itemCacheRevision = self.revision
    end
    local cached = self.itemCache[itemID]
    if cached ~= nil then
        if cached == false then return nil end
        return cached
    end
    local stats = self:ComputeItemStats(itemID)
    self.itemCache[itemID] = stats or false
    return stats
end

-- Schlanke Sicht fuer Opportunity und Future: genau die Felder, die eine
-- Bewertung braucht, und nil statt einer leeren Tabelle, wenn nichts da ist.
function Ledger:GetLiquidity(itemID)
    local stats = self:GetItemStats(itemID)
    if not stats then return nil end
    if stats.sellThrough == nil and stats.sellThroughAuctions == nil
        and stats.medianHours == nil then
        return nil
    end
    return {
        itemID = itemID,
        sellThrough = stats.sellThrough,
        sellThroughAuctions = stats.sellThroughAuctions,
        expectedHours = stats.expectedHours,
        holdingHours = stats.holdingHours,
        liquidityScore = stats.liquidityScore,
        confidence = stats.confidence,
        soldQuantity = stats.soldQuantity,
        expiredQuantity = stats.expiredQuantity,
        soldAuctions = stats.soldAuctions,
        unmatchedSales = stats.unmatchedSales,
        realizedMargin = stats.realizedMargin,
        medianBuyPrice = stats.medianBuyPrice,
        medianSellPrice = stats.medianSellPrice,
    }
end

-- ---------------------------------------------------------------------------
-- Gesamtstatistik ueber ein Zeitfenster
--
-- Ein Durchlauf ueber die Rohereignisse, gecacht an der Revision: Solange kein
-- neues Ereignis dazukommt, wird nicht neu gerechnet. Der Handel-Tab fragt
-- 7 und 30 Tage ab; beide Fenster entstehen aus demselben Durchlauf.
-- ---------------------------------------------------------------------------

function Ledger:ComputeGlobalStats(days, now)
    local store = self:EnsureStore()
    if not store then return nil end
    now = now or self:Now()
    local cutoff = days and (now - days * 86400) or nil
    local events = store.events

    local stats = {
        days = days,
        revenueGross = 0, revenueNet = 0, purchaseCost = 0,
        depositPaid = 0, depositLost = 0,
        sales = 0, soldQuantity = 0, unmatchedSales = 0,
        expiries = 0, expiredQuantity = 0,
        cancels = 0, cancelledQuantity = 0,
        purchases = 0, boughtQuantity = 0,
        posts = 0, postedQuantity = 0,
        items = 0,
    }
    local seenItems = {}
    local matchedRevenue = 0
    local matchedCostQuantity = 0
    -- Verkaufsdauern ausschliesslich aus den Verkaeufen DIESES Fensters.
    local hours = {}

    for base = 0, #events - EVENT_STRIDE, EVENT_STRIDE do
        local stamp = eventTimestamp(store, events[base + 2])
        if not cutoff or stamp >= cutoff then
            local kind = events[base + 1]
            local itemID = events[base + 3]
            local quantity = events[base + 4]
            local unitA, unitB = events[base + 5], events[base + 6]
            if itemID > 0 and not seenItems[itemID] then
                seenItems[itemID] = true
                stats.items = stats.items + 1
            end
            if kind == KIND.SALE then
                stats.sales = stats.sales + 1
                if quantity > 0 then
                    stats.soldQuantity = stats.soldQuantity + quantity
                    stats.revenueGross = stats.revenueGross + unitA * quantity
                    stats.revenueNet = stats.revenueNet + unitB * quantity
                    matchedRevenue = matchedRevenue + unitB * quantity
                    matchedCostQuantity = matchedCostQuantity + quantity
                else
                    stats.unmatchedSales = stats.unmatchedSales + 1
                    stats.revenueGross = stats.revenueGross + unitA
                    stats.revenueNet = stats.revenueNet + unitB
                end
                local held = events[base + 8]
                if held > 0 then hours[#hours + 1] = held / 10 end
            elseif kind == KIND.EXPIRE then
                stats.expiries = stats.expiries + 1
                stats.expiredQuantity = stats.expiredQuantity + quantity
                stats.depositLost = stats.depositLost + unitB
            elseif kind == KIND.CANCEL then
                stats.cancels = stats.cancels + 1
                stats.cancelledQuantity = stats.cancelledQuantity + quantity
                stats.depositLost = stats.depositLost + unitB
            elseif kind == KIND.PURCHASE then
                stats.purchases = stats.purchases + 1
                stats.boughtQuantity = stats.boughtQuantity + quantity
                stats.purchaseCost = stats.purchaseCost + unitA * quantity
            elseif kind == KIND.POST then
                stats.posts = stats.posts + 1
                stats.postedQuantity = stats.postedQuantity + quantity
                stats.depositPaid = stats.depositPaid + unitB
            end
        end
    end

    local resolvedUnits = stats.soldQuantity + stats.expiredQuantity
    if stats.unmatchedSales == 0 and resolvedUnits > 0 then
        stats.sellThrough = stats.soldQuantity / resolvedUnits
    end
    local resolvedAuctions = stats.sales + stats.expiries
    if resolvedAuctions > 0 then
        stats.sellThroughAuctions = stats.sales / resolvedAuctions
    end
    stats.confidence = self:SellThroughConfidence(resolvedAuctions, resolvedUnits)

    if #hours > 0 then
        table.sort(hours)
        stats.medianHours = quantile(hours, 0.5)
        stats.timeSamples = #hours
    end

    -- Realisierter Gewinn des Fensters. Nur belastbar, wenn im selben Fenster
    -- auch die Einkaeufe stehen, die zu den Verkaeufen gehoeren - sonst waere
    -- es Umsatz minus zufaellig gleichzeitig gekaufter Ware.
    stats.realizedProfitKnown = false
    if matchedCostQuantity > 0 and stats.boughtQuantity >= matchedCostQuantity
        and stats.purchaseCost > 0 then
        local averageCost = stats.purchaseCost / stats.boughtQuantity
        stats.realizedProfit = matchedRevenue
            - averageCost * matchedCostQuantity - stats.depositLost
        stats.realizedProfitKnown = true
    end
    stats.grossMargin = stats.revenueNet - stats.purchaseCost
    return stats
end

function Ledger:GetGlobalStats(days)
    local key = tostring(days or "all")
    if self.globalCacheRevision ~= self.revision then
        self.globalCache = {}
        self.globalCacheRevision = self.revision
    end
    local cached = self.globalCache[key]
    if cached then return cached end
    local stats = self:ComputeGlobalStats(days)
    self.globalCache[key] = stats
    return stats
end

-- Die juengsten Geschaefte, neueste zuerst. Fuer den Handel-Tab und die
-- Zuordnung im Chancen-Protokoll.
--
-- Sortiert wird ausdruecklich, statt sich auf die Speicherreihenfolge zu
-- verlassen: Der Briefkasten wird in Postfach-Reihenfolge gelesen, und die ist
-- nicht die Reihenfolge der Ankunft. Erst danach greift der Deckel - sonst
-- waeren die "juengsten" Geschaefte die zuletzt geschriebenen statt der
-- zeitlich letzten.
function Ledger:GetRecentTrades(limit, kindFilter)
    local store = self:EnsureStore()
    if not store then return {} end
    limit = limit or config().MAX_RECENT_TRADES
    local events = store.events
    local list = {}
    for base = 0, #events - EVENT_STRIDE, EVENT_STRIDE do
        local kind = events[base + 1]
        if not kindFilter or kindFilter == kind then
            list[#list + 1] = {
                kind = KIND_NAME[kind],
                kindID = kind,
                timestamp = eventTimestamp(store, events[base + 2]),
                itemID = events[base + 3] > 0 and events[base + 3] or nil,
                quantity = events[base + 4] > 0 and events[base + 4] or nil,
                unitPrice = events[base + 5],
                unitNet = events[base + 6],
                flags = events[base + 7],
                holdHours = events[base + 8] > 0 and (events[base + 8] / 10) or nil,
            }
        end
    end
    table.sort(list, function(a, b)
        if a.timestamp ~= b.timestamp then return a.timestamp > b.timestamp end
        return (a.itemID or 0) < (b.itemID or 0)
    end)
    for index = #list, limit + 1, -1 do list[index] = nil end
    return list
end

-- Alle Items mit Handelsdaten, fertig fuer den Handel-Tab.
function Ledger:BuildReport(sortMode, limit)
    local store = self:EnsureStore()
    local rows = {}
    if store then
        for itemID in pairs(store.items) do
            local stats = self:GetItemStats(itemID)
            if stats and (stats.soldAuctions > 0 or stats.expiredAuctions > 0
                or stats.purchases > 0 or stats.postedAuctions > 0) then
                local name, _, quality, _, _, _, _, _, _, icon = GetItemInfoCompat(itemID)
                rows[#rows + 1] = {
                    itemID = itemID,
                    name = name,
                    icon = icon,
                    quality = quality,
                    stats = stats,
                }
            end
        end
    end

    local function value(row, field)
        return row.stats[field]
    end
    local comparators = {
        liquidity = function(a, b)
            local sa, sb = value(a, "liquidityScore"), value(b, "liquidityScore")
            if (sa ~= nil) ~= (sb ~= nil) then return sa ~= nil end
            if sa and sb and sa ~= sb then return sa > sb end
            return nil
        end,
        profit = function(a, b)
            local pa, pb = value(a, "realizedProfit"), value(b, "realizedProfit")
            if (pa ~= nil) ~= (pb ~= nil) then return pa ~= nil end
            if pa and pb and pa ~= pb then return pa > pb end
            return nil
        end,
        sales = function(a, b)
            local sa, sb = value(a, "soldAuctions") or 0, value(b, "soldAuctions") or 0
            if sa ~= sb then return sa > sb end
            return nil
        end,
    }
    local comparator = comparators[sortMode or "liquidity"] or comparators.liquidity
    table.sort(rows, function(a, b)
        local decided = comparator(a, b)
        if decided ~= nil then return decided end
        -- Gleichstand: mehr Verkaeufe zuerst, dann der Name. Nie zufaellig.
        local sa, sb = a.stats.soldAuctions or 0, b.stats.soldAuctions or 0
        if sa ~= sb then return sa > sb end
        if (a.name or "") ~= (b.name or "") then return (a.name or "") < (b.name or "") end
        return a.itemID < b.itemID
    end)

    local matched = #rows
    if limit and #rows > limit then
        for index = #rows, limit + 1, -1 do rows[index] = nil end
    end
    return {
        rows = rows,
        total = matched,
        listed = #rows,
        truncated = matched - #rows,
        week = self:GetGlobalStats(7),
        month = self:GetGlobalStats(30),
        lifetime = self:GetGlobalStats(nil),
        sortMode = sortMode or "liquidity",
    }
end

function Ledger:HasData()
    local store = self:EnsureStore()
    if not store then return false end
    return #store.events >= EVENT_STRIDE
end

-- ---------------------------------------------------------------------------
-- ERFASSUNG 1: DER BRIEFKASTEN
--
-- Die einzige Stelle, an der der Client einen Auktionsverkauf unmissverstaend-
-- lich bestaetigt. Gelesen wird bei MAIL_INBOX_UPDATE - nicht in einer
-- Schleife, nicht im OnUpdate.
--
-- DOPPELTZAEHLUNG ist hier der teuerste denkbare Fehler: Sie wuerde Verkaeufe
-- erfinden und damit genau die Zahl aufblasen, um die es geht. Postfach-Indizes
-- taugen nicht als Kennung - sie verschieben sich, sobald ein Brief gelesen
-- oder abgeholt wird. Und eine Kennung der Auktion gibt es in der klassischen
-- API nicht.
--
-- Deshalb ein Abgleich in zwei Stufen. Jeder Brief bekommt einen Schluessel aus
-- Art, Item und Betrag - ohne Zeit, damit ein Jitter ihn nicht veraendert.
-- Gespeichert werden dazu die Anzahl solcher Briefe im Postfach und das
-- Ankunftsfenster des aeltesten von ihnen:
--
--   1. Liegt das beobachtete Ankunftsfenster hoechstens eine Stunde neben dem
--      gespeicherten, ist es dieselbe Gruppe Briefe. Neu ist dann nur die
--      Differenz der Anzahl - drei gleiche Verkaufsbriefe zaehlen als drei
--      Verkaeufe, derselbe Brief beim zehnten Oeffnen als keiner.
--   2. Liegt es weiter weg, wurde die alte Gruppe abgeholt und eine neue ist
--      angekommen. Dann zaehlen alle beobachteten Briefe als neu.
--
-- Die Stunde Toleranz faengt die Ungenauigkeit von daysLeft ab, ohne die
-- Erkennung neuer Post zu verlieren. Wer sein Postfach leert und innerhalb
-- derselben Stunde exakt denselben Verkauf noch einmal macht, verliert einen
-- Eintrag - das ist die bewusst gewaehlte Richtung: lieber ein Verkauf zu wenig
-- als einer zu viel.
--
-- Der Zeitpunkt eines Briefes wird aus daysLeft rekonstruiert: AH-Post lebt 30
-- Tage, also ist sie vor (30 - daysLeft) Tagen angekommen. Das ist die einzige
-- Zeitangabe, die der Client hergibt, und sie ist genau genug fuer eine
-- Verkaufsdauer in Stunden.
-- ---------------------------------------------------------------------------

-- Baut aus einer Betreffvorlage des Clients ("Auktion abgelaufen: %s") ein
-- Lua-Muster. Bewusst aus der globalen Zeichenkette statt aus fest verdrahtetem
-- Text: Der Client ist deutsch, englisch oder sonst etwas, und geraten wird
-- hier nichts.
local function subjectPattern(template)
    if type(template) ~= "string" or template == "" then return nil end
    local escaped = template:gsub("([%^%$%(%)%%%.%[%]%*%+%-%?])", "%%%1")
    escaped = escaped:gsub("%%%%s", ".*")
    return "^" .. escaped .. "$"
end

function Ledger:MailPatterns()
    return {
        expired = subjectPattern(AUCTION_EXPIRED_MAIL_SUBJECT),
        cancelled = subjectPattern(AUCTION_REMOVED_MAIL_SUBJECT),
    }
end

-- Item-ID und Stueckzahl eines Anhangs. Der Link ist die verlaesslichste
-- Quelle; GetInboxItem ist der Rueckfall.
function Ledger:InboxAttachment(index)
    local itemID, count, name
    if type(GetInboxItemLink) == "function" then
        local ok, link = pcall(GetInboxItemLink, index, 1)
        if ok and type(link) == "string" then
            itemID = tonumber(link:match("item:(%d+)"))
        end
    end
    if type(GetInboxItem) == "function" then
        local ok, itemName, foundID, _, quantity = pcall(GetInboxItem, index, 1)
        if ok then
            name = type(itemName) == "string" and itemName or nil
            if not itemID and isItemID(foundID) then itemID = foundID end
            if isPositive(quantity) then count = math.floor(quantity) end
        end
    end
    return itemID, count, name
end

-- Ein Durchlauf ueber den Briefkasten. Rueckgabe: Anzahl neu aufgeschriebener
-- Ereignisse.
function Ledger:ScanMailbox(now)
    local store = self:EnsureStore()
    if not store then return 0 end
    if type(GetInboxNumItems) ~= "function" then return 0 end
    local okCount, numItems = pcall(GetInboxNumItems)
    if not okCount or type(numItems) ~= "number" or numItems <= 0 then return 0 end
    now = now or self:Now()
    local patterns = self:MailPatterns()
    local L = config()

    -- Erst zaehlen, dann vergleichen: Der Briefkasten ist die Wahrheit ueber
    -- "wie viele solcher Briefe gibt es", nicht ueber "was ist neu".
    local seen = {}
    local order = {}
    for index = 1, numItems do
        local record = self:ReadMail(index, patterns, now)
        if record then
            local group = seen[record.key]
            if not group then
                group = { count = 0, record = record }
                seen[record.key] = group
                order[#order + 1] = record.key
            end
            group.count = group.count + 1
            -- Der aelteste Brief einer Gruppe bestimmt Zeitpunkt und Fenster:
            -- Er ist zuerst angekommen, also gehoert ihm die laengste
            -- Verkaufsdauer.
            if record.arrivedAt < group.record.arrivedAt then
                group.record = record
            end
        end
    end

    local written = 0
    local nowMinute = math.floor(now / 60)
    for _, key in ipairs(order) do
        local group = seen[key]
        local bucket = math.floor(group.record.arrivedAt / MAIL_BUCKET_SECONDS)
        local stored = store.mail[key]
        local already = 0
        if type(stored) == "table" and type(stored[2]) == "number"
            and math.abs(bucket - stored[2]) <= MAIL_BUCKET_TOLERANCE then
            already = stored[1] or 0
        end
        local fresh = group.count - already
        if fresh > 0 then
            for _ = 1, fresh do
                if self:ApplyMail(group.record) then written = written + 1 end
            end
        end
        store.mail[key] = { group.count, bucket, nowMinute }
    end

    if written > 0 then
        self:Prune(now)
        -- Neue Kaeufe und Verkaeufe sind der einzige Zeitpunkt, an dem sich am
        -- Ergebnis einer alten Chance etwas aendern kann. Deshalb genau hier -
        -- und nicht bei jedem Refresh.
        if GCP.Opportunity then
            pcall(GCP.Opportunity.MatchHistoryOutcomes, GCP.Opportunity)
        end
        if GCP.UI then GCP.UI:RefreshIfShown() end
    end
    self.mailScanAt = now
    return written
end

-- Liest genau einen Brief und macht daraus einen Vorgang - oder nichts.
-- Alles, was nicht eindeutig eine AH-Rechnung, ein Ablauf oder ein Abbruch
-- ist, wird ignoriert. Kein Rueckschluss aus angehaengtem Gold, kein
-- Rueckschluss aus dem Absender.
function Ledger:ReadMail(index, patterns, now)
    if type(GetInboxHeaderInfo) ~= "function" then return nil end
    local ok, _, _, _, subject, _, _, daysLeft = pcall(GetInboxHeaderInfo, index)
    if not ok then return nil end
    if type(daysLeft) ~= "number" then daysLeft = MAIL_LIFETIME_DAYS end
    local age = math.max((MAIL_LIFETIME_DAYS - daysLeft) * 86400, 0)
    local arrivedAt = now - age

    local invoiceType, itemName, _, bid, buyout, deposit, consignment
    if type(GetInboxInvoiceInfo) == "function" then
        local okInvoice, a, b, c, d, e, f, g = pcall(GetInboxInvoiceInfo, index)
        if okInvoice then
            invoiceType, itemName, _, bid, buyout, deposit, consignment = a, b, c, d, e, f, g
        end
    end

    if invoiceType == "buyer" then
        local itemID, count = self:InboxAttachment(index)
        if not isItemID(itemID) or not isPositive(count) or not isPositive(bid) then
            return nil
        end
        return {
            kind = "purchase",
            key = string.format("p|%d|%d|%d", itemID, count, math.floor(bid)),
            itemID = itemID, quantity = count, total = bid,
            arrivedAt = arrivedAt, name = itemName,
        }
    end

    -- "seller_temp_invoice" ist derselbe Brief wie "seller", nur bevor das Gold
    -- ausgezahlt wurde. Beide fuehren auf denselben Schluessel, sonst zaehlte
    -- ein Verkauf zweimal - einmal vor und einmal nach der Auszahlung.
    if invoiceType == "seller" or invoiceType == "seller_temp_invoice" then
        if not isPositive(bid) or type(itemName) ~= "string" then return nil end
        return {
            kind = "sale",
            key = string.format("s|%s|%d", itemName, math.floor(bid)),
            itemName = itemName, total = bid, buyout = buyout,
            deposit = deposit, consignment = consignment,
            arrivedAt = arrivedAt,
        }
    end

    if type(subject) ~= "string" then return nil end
    local kind = nil
    if patterns.expired and subject:match(patterns.expired) then
        kind = "expire"
    elseif patterns.cancelled and subject:match(patterns.cancelled) then
        kind = "cancel"
    end
    if not kind then return nil end

    local itemID, count, attachmentName = self:InboxAttachment(index)
    if not isItemID(itemID) or not isPositive(count) then return nil end
    return {
        kind = kind,
        key = string.format("%s|%d|%d", kind == "expire" and "e" or "c", itemID, count),
        itemID = itemID, quantity = count,
        arrivedAt = arrivedAt, name = attachmentName,
    }
end

function Ledger:ApplyMail(record)
    if type(record) ~= "table" then return false end
    if record.kind == "purchase" then
        return self:RecordPurchase({
            itemID = record.itemID,
            quantity = record.quantity,
            totalCost = record.total,
            timestamp = record.arrivedAt,
            name = record.name,
            source = "ah",
        })
    elseif record.kind == "expire" then
        return self:RecordAuctionExpired({
            itemID = record.itemID,
            quantity = record.quantity,
            timestamp = record.arrivedAt,
        })
    elseif record.kind == "cancel" then
        return self:RecordAuctionCancelled({
            itemID = record.itemID,
            quantity = record.quantity,
            timestamp = record.arrivedAt,
        })
    elseif record.kind == "sale" then
        return self:ApplySaleInvoice(record)
    end
    return false
end

-- Die Verkaufsrechnung nennt Name und Betrag, sonst nichts. Item-ID und
-- Stueckzahl entstehen aus der Zuordnung zu einer offenen Einstellung; klappt
-- sie nicht, wird der Verkauf trotzdem aufgeschrieben - nur eben ohne
-- Stueckzahl und mit der ehrlichen Folge, dass die Sell-Through-Rate dieses
-- Items abgeschaltet bleibt.
function Ledger:ApplySaleInvoice(record)
    local store = self:EnsureStore()
    if not store then return false end
    local itemID = self:ResolveName(record.itemName)
    local posting, quality = nil, config().MATCH.NONE
    if itemID then
        posting, quality = self:MatchSale(store, itemID, math.floor(record.total))
    end

    local holdHours, chainHours = nil, nil
    if posting then
        holdHours = math.max((record.arrivedAt - posting.postedAt) / 3600, 0)
        chainHours = math.max((record.arrivedAt - (posting.chainStart or posting.postedAt)) / 3600, 0)
    end

    return self:RecordSale({
        itemID = itemID,
        name = record.itemName,
        quantity = posting and posting.quantity or nil,
        totalGross = record.total,
        consignment = record.consignment,
        timestamp = record.arrivedAt,
        holdHours = holdHours,
        chainHours = chainHours,
        matchQuality = quality,
        source = "ah",
    })
end

-- ---------------------------------------------------------------------------
-- ERFASSUNG 2: DAS EINSTELLEN
--
-- hooksecurefunc auf PostAuction. Die klassische API nennt beim Einstellen
-- weder Item noch Item-ID - sie nimmt, was im Verkaufsplatz liegt. Also wird
-- genau das gelesen: GetAuctionSellItemInfo gibt Name und Stueckzahl, die
-- Item-ID entsteht aus dem Abgleich mit den eigenen Taschen. Genau ein
-- passender Treffer wird akzeptiert; bei zwei Items gleichen Namens wird
-- nichts aufgeschrieben.
--
-- Reine Gebotsauktionen ohne Sofortkaufpreis werden NICHT aufgeschrieben: Ohne
-- Verkaufspreis gibt es keinen Stueckpreis, und ein Mindestgebot ist kein
-- Verkaufspreis.
-- ---------------------------------------------------------------------------

-- runTime ist je nach Clientfassung entweder die Stufe (1/2/3) oder die Dauer
-- in Minuten. Beides wird erkannt, nichts wird geraten: Passt keines von
-- beidem, bleibt die Dauer unbekannt.
local DURATION_STEPS = { [1] = 12, [2] = 24, [3] = 48 }

function Ledger:DurationHours(runTime)
    if type(runTime) ~= "number" then return nil end
    if DURATION_STEPS[runTime] then return DURATION_STEPS[runTime] end
    if runTime >= 60 and runTime <= 2880 then return runTime / 60 end
    return nil
end

-- Item-ID zu einem Namen aus dem Verkaufsplatz. Gesucht wird in den eigenen
-- Taschen - was eingestellt wird, liegt dort per Definition.
function Ledger:ResolveSellSlotItem(name)
    if type(name) ~= "string" or name == "" then return nil end
    local known = self:ResolveName(name)
    if known then return known end
    if not GCP.Inventory then return nil end
    local ok, bags = pcall(GCP.Inventory.ScanBags, GCP.Inventory, {})
    if not ok or type(bags) ~= "table" then return nil end
    local found = nil
    for itemID in pairs(bags) do
        if GetItemInfoCompat(itemID) == name then
            if found and found ~= itemID then return nil end
            found = itemID
        end
    end
    return found
end

function Ledger:OnPostAuction(minBid, buyout, runTime, stackSize, numStacks)
    if type(GetAuctionSellItemInfo) ~= "function" then return 0 end
    local ok, name, _, count = pcall(GetAuctionSellItemInfo)
    if not ok or type(name) ~= "string" or name == "" then return 0 end

    stackSize = isPositive(stackSize) and math.floor(stackSize)
        or (isPositive(count) and math.floor(count)) or nil
    if not stackSize then return 0 end
    numStacks = isPositive(numStacks) and math.floor(numStacks) or 1
    if not isPositive(buyout) then return 0 end

    local itemID = self:ResolveSellSlotItem(name)
    if not itemID then return 0 end
    self:RememberName(itemID, name)

    local unitPrice = buyout / stackSize
    local durationHours = self:DurationHours(runTime)

    -- Einstellgebuehr: exakt vom Client oder gar nicht. Eine Faustformel waere
    -- hier besonders verlockend und besonders falsch, weil sie in jede
    -- Gewinnrechnung durchschlaegt.
    local deposit = nil
    if type(CalculateAuctionDeposit) == "function" then
        local okDeposit, value = pcall(CalculateAuctionDeposit, runTime, stackSize, numStacks)
        if okDeposit and isPositive(value) then
            deposit = value / numStacks
        end
    end

    local written = 0
    local now = self:Now()
    for _ = 1, numStacks do
        if self:RecordAuctionPosted({
            itemID = itemID,
            quantity = stackSize,
            unitPrice = unitPrice,
            deposit = deposit,
            durationHours = durationHours,
            timestamp = now,
            name = name,
        }) then
            written = written + 1
        end
    end
    return written
end

function Ledger:InstallHooks()
    if self.hooked then return true end
    if type(hooksecurefunc) ~= "function" then return false end
    if type(PostAuction) ~= "function" then return false end
    local ok = pcall(hooksecurefunc, "PostAuction",
        function(minBid, buyout, runTime, stackSize, numStacks)
            pcall(function()
                GCP.Ledger:OnPostAuction(minBid, buyout, runTime, stackSize, numStacks)
            end)
        end)
    self.hooked = ok and true or false
    return self.hooked
end

-- Einstiegspunkt fuer eine spaetere externe Quelle (etwa eine stabile
-- Journalator-API). Sie bekaeme dieselben Vorgaenge wie der Briefkasten,
-- nichts anderes - und heute ruft sie niemand auf.
function Ledger:CaptureFromExternal(records)
    if type(records) ~= "table" then return 0 end
    local written = 0
    for _, record in ipairs(records) do
        local ok, applied = pcall(self.ApplyMail, self, record)
        if ok and applied then written = written + 1 end
    end
    return written
end

-- ---------------------------------------------------------------------------
-- Diagnose
-- ---------------------------------------------------------------------------

function Ledger:GetOverview()
    local store = self:EnsureStore()
    local events = store and store.events or {}
    local itemCount = 0
    if store then
        for _ in pairs(store.items) do itemCount = itemCount + 1 end
    end
    -- Aeltester und juengster Zeitpunkt werden gesucht, nicht am Rand der Liste
    -- abgelesen: Die Ereignisse stehen zeitlich nicht zwingend in Ordnung.
    local oldest, newest = nil, nil
    for base = 0, #events - EVENT_STRIDE, EVENT_STRIDE do
        local stamp = eventTimestamp(store, events[base + 2])
        if not oldest or stamp < oldest then oldest = stamp end
        if not newest or stamp > newest then newest = stamp end
    end
    return {
        events = math.floor(#events / EVENT_STRIDE),
        items = itemCount,
        openPostings = self:CountOpenPostings(nil),
        oldest = oldest,
        newest = newest,
        hooked = self.hooked,
        mailScanAt = self.mailScanAt,
    }
end

function Ledger:EstimateBytes()
    local store = self:EnsureStore()
    if not store then return 0 end
    local bytes = 96
    for index = 1, #store.events do
        bytes = bytes + #tostring(store.events[index]) + 1
    end
    for itemID, entry in pairs(store.items) do
        if isValidItem(entry) then
            bytes = bytes + #tostring(itemID) + 36
            for _, list in ipairs({ entry.c, entry.m, entry.b, entry.s, entry.h }) do
                for index = 1, #list do
                    bytes = bytes + #tostring(list[index]) + 1
                end
            end
        end
    end
    for index = 1, #store.open do
        bytes = bytes + #tostring(store.open[index]) + 1
    end
    for name in pairs(store.names) do bytes = bytes + #name + 12 end
    for key in pairs(store.mail) do bytes = bytes + #key + 18 end
    return bytes
end

-- ---------------------------------------------------------------------------
-- Ereignisse
--
-- Bewusst nur drei: Briefkasten auf, Briefkasten aktualisiert, Auktionshaus
-- auf. Kein OnUpdate, keine Schleife, kein Polling.
-- ---------------------------------------------------------------------------

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("PLAYER_LOGIN")
pcall(eventFrame.RegisterEvent, eventFrame, "MAIL_INBOX_UPDATE")
pcall(eventFrame.RegisterEvent, eventFrame, "MAIL_SHOW")
pcall(eventFrame.RegisterEvent, eventFrame, "AUCTION_HOUSE_SHOW")
eventFrame:SetScript("OnEvent", function(_, event)
    if not GCP.db then GCP:EnsureDB() end
    if event == "PLAYER_LOGIN" then
        Ledger:InstallHooks()
        Ledger:Prune(nil, true)
    elseif event == "AUCTION_HOUSE_SHOW" then
        -- Auctionator und Co. koennen nach Gold Copilot laden; das
        -- Auktionshaus ist der zweite, spaetere Versuch fuer den Hook.
        Ledger:InstallHooks()
    else
        Ledger:ScanMailbox()
    end
end)
