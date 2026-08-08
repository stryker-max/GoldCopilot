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
