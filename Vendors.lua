local addonName, GCP = ...

GCP.Vendors = {}
local Vendors = GCP.Vendors

-- ---------------------------------------------------------------------------
-- HAENDLERWARE (1.1.0-beta.5)
--
-- Manche Zutaten stehen in jeder Stadt beim Handelswarenhaendler, zu einem
-- Preis, der sich nie bewegt. Runenfaden kostet 50 Silber - gestern, heute und
-- naechstes Jahr. Wer denselben Faden im Auktionshaus fuer 68 Silber kauft,
-- zahlt einen Aufschlag dafuer, dass ihm jemand den Weg zum Haendler abgenommen
-- hat.
--
-- Bis 1.1.0-beta.4 hat Gold Copilot genau das getan: Die Execution Engine
-- kannte nur einen Ort zum Einkaufen, und der war das Auktionshaus. Die
-- Ortsart VENDOR und die Aktionsart VENDOR_BUY standen seit 0.9.0 in den
-- Konstanten und wurden nie erzeugt.
--
-- ---------------------------------------------------------------------------
-- WOHER DER PREIS KOMMT - IN DIESER REIHENFOLGE
--
--   1. GESEHEN. Wer bei einem Haendler war, hat dessen Angebot im Client
--      stehen: GetMerchantItemInfo nennt Preis, Stapelgroesse und Vorrat. Das
--      ist keine Schaetzung, sondern der Betrag, den DIESER Spieler zahlt -
--      inklusive seines Rufrabatts, den es in TBC noch gibt.
--   2. WISSENSBASIS. Die Liste unten. Jede Zeile ist gegen die lokal
--      installierten Spieldaten geprueft (Questie-Itemdatenbank fuer ID und
--      Name, TSM-Datensatz fuer den Grundpreis unbegrenzt verfuegbarer
--      Haendlerware). Keine Zeile stammt aus dem Gedaechtnis.
--   3. GAR NICHT. Dann gibt es keinen Haendlerpreis, und die Route kauft im
--      Auktionshaus - wie bisher. Ein geratener Haendlerpreis waere hier der
--      teuerste Fehler: Er schickte den Spieler zu einem Haendler, der die Ware
--      gar nicht fuehrt.
--
-- ---------------------------------------------------------------------------
-- WAS HIER AUSDRUECKLICH NICHT STEHT
--
--   * Kein Item mit begrenztem Vorrat. Silberkontakt steht bei ueber hundert
--     Haendlern und ist trotzdem staendig ausverkauft; eine Route, die darauf
--     baut, laesst den Spieler vor einem leeren Angebot stehen. Gelernt wird
--     deshalb nur, was der Client als unbegrenzt meldet (numAvailable == -1).
--   * Kein Item, das etwas anderes als Gold kostet (Marken, Ehre, Ruf).
--   * Kein Haendlerstandort. Wo der naechste Handelswarenhaendler steht, lernt
--     Navigation.lua aus den eigenen Besuchen - genau wie Bank und Briefkasten.
-- ---------------------------------------------------------------------------

local function config()
    return GCP.Constants.VENDORS
end

local function isPositive(value)
    return type(value) == "number" and value > 0
end

-- ---------------------------------------------------------------------------
-- Grundpreise
--
-- Nur Handelswaren, die als Zutat in einem Rezept auftauchen koennen. Die
-- englischen Namen dienen dem Abgleich mit den Spieldaten; angezeigt wird zur
-- Laufzeit immer der lokalisierte Name aus GetItemInfo.
--
-- Preise in Kupfer, ohne Rufrabatt. Wer bei dem Haendler Ruf hat, zahlt
-- weniger - und sobald er einmal davorstand, steht der guenstigere Preis
-- gelernt daneben und schlaegt diese Liste.
-- ---------------------------------------------------------------------------

Vendors.BASE_PRICES = {
    -- Faden
    [2320]  = 10,      -- Coarse Thread
    [2321]  = 100,     -- Fine Thread
    [4291]  = 500,     -- Silken Thread
    [8343]  = 2000,    -- Heavy Silken Thread
    [14341] = 5000,    -- Rune Thread

    -- Farbstoffe
    [2325]  = 1000,    -- Black Dye
    [2604]  = 50,      -- Red Dye
    [2605]  = 100,     -- Green Dye
    [4340]  = 350,     -- Gray Dye
    [4341]  = 500,     -- Yellow Dye
    [4342]  = 2500,    -- Purple Dye
    [6260]  = 50,      -- Blue Dye
    [6261]  = 1000,    -- Orange Dye
    [10290] = 2500,    -- Pink Dye
    [2324]  = 25,      -- Bleach

    -- Phiolen
    [3371]  = 20,      -- Empty Vial
    [3372]  = 200,     -- Leaded Vial
    [8925]  = 2500,    -- Crystal Vial
    [18256] = 30000,   -- Imbued Vial

    -- Schmiedekunst
    [2880]  = 100,     -- Weak Flux
    [3466]  = 2000,    -- Strong Flux
    [18567] = 150000,  -- Elemental Flux
    [3857]  = 500,     -- Coal

    -- Ingenieurskunst und Buechsenmacherei
    [4399]  = 200,     -- Wooden Stock
    [4400]  = 2000,    -- Heavy Stock
    [4470]  = 38,      -- Simple Wood
    [11291] = 4500,    -- Star Wood
    [10647] = 2000,    -- Engineer's Ink
    [10648] = 500,     -- Blank Parchment

    -- Verzauberkunst
    [6217]  = 124,     -- Copper Rod

    -- Kochkunst
    [4289]  = 50,      -- Salt
    [2678]  = 10,      -- Mild Spices
    [2692]  = 40,      -- Hot Spices
    [3713]  = 160,     -- Soothing Spices
    [159]   = 25,      -- Refreshing Spring Water
    [1179]  = 125,     -- Ice Cold Milk
}

-- ---------------------------------------------------------------------------
-- Speicher
--
--   db.vendors = {
--       version = 1,
--       items = { [itemID] = { p = Kupfer, at = "2026-08-13" } },
--   }
--
-- Bewusst im Wurzelverzeichnis der Datenbank und nicht im Realmprofil: Ein
-- Haendlerpreis ist serverweit gleich. Er ist auch keine Marktbeobachtung -
-- er aendert sich nur, wenn Blizzard ihn aendert oder der eigene Ruf steigt.
-- ---------------------------------------------------------------------------

function Vendors:EnsureStore()
    local db = GCP.db
    if not db then return nil end
    local C = config()
    local store = db.vendors
    if type(store) ~= "table" or store.version ~= C.STORE_VERSION then
        store = { version = C.STORE_VERSION, items = {} }
        db.vendors = store
    end
    if type(store.items) ~= "table" then store.items = {} end
    return store
end

function Vendors:Count()
    local store = self:EnsureStore()
    if not store then return 0 end
    local count = 0
    for _ in pairs(store.items) do count = count + 1 end
    return count
end

function Vendors:Forget()
    local store = self:EnsureStore()
    if not store then return 0 end
    local removed = self:Count()
    store.items = {}
    return removed
end

-- ---------------------------------------------------------------------------
-- Nachschlagen
--
-- Rueckgabe: Preis je Stueck in Kupfer, Quelle ("gesehen" | "Wissensbasis").
-- Ohne beides nil - und nicht etwa der Haendler-VERKAUFSwert aus GetItemInfo.
-- Der sagt, was der Haendler zahlt, nicht was er verlangt; die beiden liegen
-- regelmaessig um den Faktor vier auseinander.
-- ---------------------------------------------------------------------------

function Vendors:GetBuyPrice(itemID)
    if type(itemID) ~= "number" then return nil, nil end
    local store = self:EnsureStore()
    local learned = store and store.items[itemID]
    if type(learned) == "table" and isPositive(learned.p) then
        return learned.p, "gesehen"
    end
    local base = self.BASE_PRICES[itemID]
    if isPositive(base) then return base, "Wissensbasis" end
    return nil, nil
end

function Vendors:IsVendorItem(itemID)
    return self:GetBuyPrice(itemID) ~= nil
end

-- Der Satz fuer Tooltip und Begruendung.
function Vendors:Describe(itemID)
    local price, source = self:GetBuyPrice(itemID)
    if not price then return nil end
    if source == "gesehen" then
        return string.format("Beim Händler für %s – selbst gesehen.",
            GCP.Prices:FormatMoney(price))
    end
    return string.format("Beim Händler für %s.", GCP.Prices:FormatMoney(price))
end

-- ---------------------------------------------------------------------------
-- Lernen
--
-- Aufgerufen, wenn ein Haendlerfenster aufgeht. Uebernommen wird nur, was
-- unbegrenzt verfuegbar ist und mit Gold bezahlt wird - alles andere waere
-- eine Zusage, die die Route nicht halten kann.
-- ---------------------------------------------------------------------------

function Vendors:Remember(itemID, unitPrice, now)
    if type(itemID) ~= "number" or itemID <= 0 then return false end
    if not isPositive(unitPrice) then return false end
    local store = self:EnsureStore()
    if not store then return false end
    local existing = store.items[itemID]
    if type(existing) ~= "table" then
        local count = self:Count()
        if count >= config().MAX_ITEMS then return false end
        existing = {}
        store.items[itemID] = existing
    end
    existing.p = math.floor(unitPrice + 0.5)
    existing.at = now or GCP:Today()
    return true
end

local function merchantItemCount()
    if type(GetMerchantNumItems) ~= "function" then return 0 end
    local ok, count = pcall(GetMerchantNumItems)
    if not ok or type(count) ~= "number" then return 0 end
    return count
end

local function merchantItemID(index)
    if type(GetMerchantItemLink) ~= "function" then return nil end
    local ok, link = pcall(GetMerchantItemLink, index)
    if not ok or type(link) ~= "string" then return nil end
    return tonumber(link:match("item:(%d+)"))
end

-- Kostet dieser Posten etwas anderes als Gold? GetMerchantItemCostInfo nennt
-- die Zahl der zusaetzlichen Waehrungen. Kennt der Client die Funktion nicht,
-- entscheidet das achte Rueckgabefeld von GetMerchantItemInfo.
local function costsCurrency(index, extendedCost)
    if type(GetMerchantItemCostInfo) == "function" then
        local ok, count = pcall(GetMerchantItemCostInfo, index)
        if ok and type(count) == "number" and count > 0 then return true end
    end
    return extendedCost and true or false
end

function Vendors:ScanMerchant()
    local count = merchantItemCount()
    if count <= 0 then return 0 end
    if type(GetMerchantItemInfo) ~= "function" then return 0 end
    local now = GCP:Today()
    local learned = 0
    for index = 1, count do
        local ok, _, _, price, quantity, numAvailable, _, _, extendedCost =
            pcall(GetMerchantItemInfo, index)
        -- numAvailable == -1 heisst: unbegrenzter Vorrat. Alles andere ist ein
        -- Posten, der ausverkauft sein kann - und auf den keine Route bauen darf.
        if ok and numAvailable == -1 and isPositive(price) and isPositive(quantity)
            and not costsCurrency(index, extendedCost) then
            local itemID = merchantItemID(index)
            if itemID and self:Remember(itemID, price / quantity, now) then
                learned = learned + 1
            end
        end
    end
    return learned
end

function Vendors:InstallEvents()
    if self.eventFrame then return self.eventFrame end
    local frame = CreateFrame("Frame")
    pcall(frame.RegisterEvent, frame, "MERCHANT_SHOW")
    pcall(frame.RegisterEvent, frame, "MERCHANT_UPDATE")
    frame:SetScript("OnEvent", function()
        if not GCP.db then return end
        Vendors:ScanMerchant()
    end)
    self.eventFrame = frame
    return frame
end
