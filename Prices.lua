local addonName, GCP = ...

GCP.Prices = {}
local Prices = GCP.Prices

local GetItemInfoCompat = (C_Item and C_Item.GetItemInfo) or GetItemInfo

-- Auctionator und TSM melden sich beide ueber globale Tabellen. Welche Quelle
-- antwortet, entscheidet sich je Item: "auto" fragt erst Auctionator (Scan-
-- Preise vom eigenen Server), dann TSM (dbmarket via Desktop-App).

local function auctionatorPrice(itemID)
    if not (Auctionator and Auctionator.API and Auctionator.API.v1
        and Auctionator.API.v1.GetAuctionPriceByItemID) then
        return nil
    end
    local ok, price = pcall(Auctionator.API.v1.GetAuctionPriceByItemID, addonName, itemID)
    if ok and type(price) == "number" and price > 0 then
        return price
    end
    return nil
end

local function tsmPrice(itemID)
    if not (TSM_API and TSM_API.GetCustomPriceValue) then
        return nil
    end
    local ok, price = pcall(TSM_API.GetCustomPriceValue, "dbmarket", "i:" .. itemID)
    if ok and type(price) == "number" and price > 0 then
        return price
    end
    return nil
end

function Prices:GetConfiguredSource()
    local db = GCP.db
    return (db and db.options and db.options.priceSource) or "auto"
end

-- Marktpreis in Kupfer oder nil, plus Quellenname fuer die Anzeige.
function Prices:GetMarketPrice(itemID)
    if type(itemID) ~= "number" then return nil, nil end
    local mode = self:GetConfiguredSource()
    if mode == "auctionator" then
        local price = auctionatorPrice(itemID)
        return price, price and "Auctionator" or nil
    elseif mode == "tsm" then
        local price = tsmPrice(itemID)
        return price, price and "TSM" or nil
    end
    local price = auctionatorPrice(itemID)
    if price then return price, "Auctionator" end
    price = tsmPrice(itemID)
    if price then return price, "TSM" end
    return nil, nil
end

function Prices:GetVendorPrice(itemID)
    local sellPrice = select(11, GetItemInfoCompat(itemID))
    if type(sellPrice) == "number" and sellPrice > 0 then
        return sellPrice
    end
    return nil
end

-- Nimmt das Auktionshaus dieses Item ueberhaupt an? Graue Qualitaet nicht, beim
-- Aufheben oder per Quest gebundene Items auch nicht. Kennt der Client die
-- Bindungsart noch nicht (kalter Item-Cache), gilt das Item als handelbar:
-- lieber den Marktwert zeigen als ihn faelschlich verschweigen.
local BIND_ON_PICKUP, BIND_QUEST = 1, 4

function Prices:IsAuctionable(itemID)
    local info = { GetItemInfoCompat(itemID) }
    local quality, bindType = info[3], info[14]
    if type(quality) == "number" and quality < 1 then return false end
    if bindType == BIND_ON_PICKUP or bindType == BIND_QUEST then return false end
    return true
end

-- Erwarteter AH-Erloes fuer Entzauberbares; kommt ausschliesslich aus
-- Auctionator, TSM Classic bietet dafuer keine fertige Quelle.
function Prices:GetDisenchantPrice(itemLink)
    if type(itemLink) ~= "string" then return nil end
    if not (Auctionator and Auctionator.API and Auctionator.API.v1
        and Auctionator.API.v1.GetDisenchantPriceByItemLink) then
        return nil
    end
    local ok, price = pcall(Auctionator.API.v1.GetDisenchantPriceByItemLink, addonName, itemLink)
    if ok and type(price) == "number" and price > 0 then
        return price
    end
    return nil
end

-- Alter des letzten Auctionator-Scans in Tagen (0 = heute), nil wenn unbekannt.
function Prices:GetScanAgeDays(itemID)
    if not (Auctionator and Auctionator.API and Auctionator.API.v1
        and Auctionator.API.v1.GetAuctionAgeByItemID) then
        return nil
    end
    local ok, age = pcall(Auctionator.API.v1.GetAuctionAgeByItemID, addonName, itemID)
    if ok and type(age) == "number" then
        return age
    end
    return nil
end

function Prices:GetActiveSourceLabel()
    local mode = self:GetConfiguredSource()
    local hasAuctionator = Auctionator and Auctionator.API and Auctionator.API.v1 ~= nil
    local hasTSM = TSM_API ~= nil
    if mode == "auctionator" then
        return hasAuctionator and "Auctionator" or "Auctionator (nicht geladen!)"
    elseif mode == "tsm" then
        return hasTSM and "TSM (dbmarket)" or "TSM (nicht geladen!)"
    end
    if hasAuctionator and hasTSM then return "Auto: Auctionator, dann TSM" end
    if hasAuctionator then return "Auto: Auctionator" end
    if hasTSM then return "Auto: TSM (dbmarket)" end
    return "keine Preisquelle gefunden"
end

function Prices:NetAuction(price)
    if type(price) ~= "number" then return nil end
    return math.floor(price * (1 - GCP.Constants.AH_CUT) + 0.5)
end

-- Geldbetraege stehen ueberall im UI; GetCoinTextureString liefert die
-- Muenz-Symbole des Clients, der Fallback ist reiner Text fuer die Tests.
function Prices:FormatMoney(copper)
    if type(copper) ~= "number" then return "-" end
    copper = math.floor(copper + 0.5)
    if type(GetCoinTextureString) == "function" then
        return GetCoinTextureString(copper)
    end
    local gold = math.floor(copper / 10000)
    local silver = math.floor((copper % 10000) / 100)
    local rest = copper % 100
    if gold > 0 then
        return string.format("%dg %ds %dc", gold, silver, rest)
    elseif silver > 0 then
        return string.format("%ds %dc", silver, rest)
    end
    return string.format("%dc", rest)
end

-- Kompakte Goldangabe fuer Summen ("123 g"), gerundet auf ganze Goldstuecke.
function Prices:FormatGold(copper)
    if type(copper) ~= "number" then return "-" end
    local gold = copper / 10000
    if gold >= 100 then
        return string.format("%.0f g", gold)
    elseif gold >= 1 then
        return string.format("%.1f g", gold)
    end
    return string.format("%.2f g", gold)
end

-- ---------------------------------------------------------------------------
-- Preishistorie. Der Momentanpreis ist der niedrigste Buyout des letzten
-- Scans - eine einzige Dumping-Auktion verzerrt ihn. Empfehlungen rechnen
-- deshalb mit dem Median der letzten 7 Tage (untere Mitte, also konservativ);
-- der Verkaufen-Tab zeigt bewusst weiter den Momentanpreis, denn er
-- beantwortet "was bekomme ich jetzt".
-- ---------------------------------------------------------------------------

function Prices:ObservedItemIDs()
    local C = GCP.Constants
    local seen, list = {}, {}
    local function add(itemID)
        if type(itemID) == "number" and not seen[itemID] then
            seen[itemID] = true
            list[#list + 1] = itemID
        end
    end
    for _, farm in ipairs(C.FARM_CATALOG) do add(farm.item) end
    for _, pair in ipairs(C.PRIMALS) do add(pair.mote); add(pair.primal) end
    for _, pair in ipairs(C.ESSENCES) do add(pair.lesser); add(pair.greater) end
    for _, craft in ipairs(C.CRAFT_COOLDOWNS) do
        add(craft.product)
        for _, mat in ipairs(craft.mats) do add(mat[1]) end
    end
    if GCP.Crafts then
        for _, recipe in ipairs(GCP.Crafts:AllRecipes()) do
            add(recipe.product)
            for _, mat in ipairs(recipe.mats) do add(mat[1]) end
        end
    end
    return list
end

function Prices:RecordObservedPrices()
    local db = GCP.db
    if not db then return end
    local today = GCP:Today()
    for _, itemID in ipairs(self:ObservedItemIDs()) do
        local price = self:GetMarketPrice(itemID)
        if price then
            local history = db.priceHistory[itemID]
            if not history then
                history = {}
                db.priceHistory[itemID] = history
            end
            history[today] = price
        end
    end
    -- 14 Tage reichen; alles Aeltere wuerde nur die SavedVariables maesten.
    local cutoff = date("%Y-%m-%d", time() - 14 * 86400)
    for itemID, history in pairs(db.priceHistory) do
        local remaining = 0
        for day in pairs(history) do
            if day < cutoff then
                history[day] = nil
            else
                remaining = remaining + 1
            end
        end
        if remaining == 0 then
            db.priceHistory[itemID] = nil
        end
    end
end

-- Planungspreis fuer Empfehlungen: Median der letzten 7 Tage, solange es
-- Verlauf gibt, sonst der Momentanpreis. Zweiter Rueckgabewert: Anzahl der
-- eingeflossenen Tageswerte.
function Prices:GetPlanningPrice(itemID)
    local db = GCP.db
    local history = db and db.priceHistory and db.priceHistory[itemID]
    if history then
        local cutoff = date("%Y-%m-%d", time() - 7 * 86400)
        local values = {}
        for day, price in pairs(history) do
            if day >= cutoff then
                values[#values + 1] = price
            end
        end
        if #values > 0 then
            table.sort(values)
            return values[math.floor((#values + 1) / 2)], #values
        end
    end
    return self:GetMarketPrice(itemID), 0
end

-- ---------------------------------------------------------------------------
-- Datenqualitaet des Planungspreises. GetPlanningPrice liefert die Anzahl der
-- eingeflossenen Tageswerte ohnehin mit - erst benannt wird daraus eine
-- Aussage: Der Median aus zwei Tagen ist kaum mehr als eine Momentaufnahme,
-- der aus sieben ist eine Preisbasis.
-- ---------------------------------------------------------------------------

function Prices:ConfidenceLabel(days)
    days = days or 0
    if days <= 0 then return "Momentanpreis" end
    if days <= 2 then return "wenig Daten" end
    if days <= 5 then return "mittlere Datenbasis" end
    return "gute Datenbasis"
end

-- Fertige Zeile fuer Tooltip und Breakdown.
function Prices:FormatPlanningBasis(days)
    days = days or 0
    if days <= 0 then
        return "Preisbasis: aktueller Marktpreis · noch keine Historie"
    end
    return string.format("Preisbasis: 7-Tage-Median · %d Tageswert%s · %s",
        days, days == 1 and "" or "e", self:ConfidenceLabel(days))
end

-- Rueckgabe: Stufentext, Anzahl Tageswerte, Planungspreis.
function Prices:GetPlanningConfidence(itemID)
    local price, days = self:GetPlanningPrice(itemID)
    return self:ConfidenceLabel(days), days or 0, price
end

function Prices:GetPlanningPriceInfo(itemID)
    local price, days = self:GetPlanningPrice(itemID)
    days = days or 0
    return {
        price = price,
        days = days,
        label = self:ConfidenceLabel(days),
        basis = days > 0 and "7-Tage-Median" or "aktueller Marktpreis",
        text = self:FormatPlanningBasis(days),
    }
end

-- Bester planbarer Wert eines Items ueber alle Kanaele: AH netto oder
-- Haendlerpreis, je nachdem was mehr bringt. Ohne Marktpreis bleibt der
-- Haendlerwert stehen - ein Item, das der Haendler fuer 3 g nimmt, ist nicht
-- wertlos, nur weil es niemand ins AH stellt. Umgekehrt wird nichts ins AH
-- gerechnet, was dort gar nicht landen kann.
-- Rueckgabe: Wert je Stueck, Quelle ("AH" | "Händler"), Tageswerte des
-- Planungspreises.
function Prices:GetBestPlanningValue(itemID)
    local market, days = self:GetPlanningPrice(itemID)
    days = days or 0
    local vendor = self:GetVendorPrice(itemID)
    local value, source
    if market and self:IsAuctionable(itemID) then
        local net = self:NetAuction(market)
        if net and net > 0 then
            value, source = net, "AH"
        end
    end
    if vendor and (not value or vendor > value) then
        value, source = vendor, "Händler"
    end
    return value, source, days
end
