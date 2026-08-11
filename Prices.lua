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
    -- tonumber statt type: Ein Betrag aus einer kaputten SavedVariable kann
    -- eine Zeichenkette sein, und ein sehr grosser Wert bleibt eine Kommazahl,
    -- an der "%d" in Lua 5.3 scheitert. Beides faengt diese Zeile ab.
    copper = tonumber(copper)
    if not copper then return "–" end
    copper = math.floor(copper + 0.5)
    if type(GetCoinTextureString) == "function" then
        return GetCoinTextureString(copper)
    end
    local gold = math.floor(copper / 10000)
    local silver = math.floor((copper % 10000) / 100)
    local rest = copper % 100
    if gold > 0 then
        return string.format("%.0fg %.0fs %.0fc", gold, silver, rest)
    elseif silver > 0 then
        return string.format("%.0fs %.0fc", silver, rest)
    end
    return string.format("%dc", rest)
end

-- Kompakte Goldangabe fuer Summen ("123 g"), gerundet auf ganze Goldstuecke.
function Prices:FormatGold(copper)
    copper = tonumber(copper)
    if not copper then return "-" end
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
            local history = GCP:Profile().priceHistory[itemID]
            if not history then
                history = {}
                GCP:Profile().priceHistory[itemID] = history
            end
            history[today] = price
        end
    end
    -- 14 Tage reichen; alles Aeltere wuerde nur die SavedVariables maesten.
    local cutoff = date("%Y-%m-%d", time() - 14 * 86400)
    for itemID, history in pairs(GCP:Profile().priceHistory) do
        local remaining = 0
        for day in pairs(history) do
            if day < cutoff then
                history[day] = nil
            else
                remaining = remaining + 1
            end
        end
        if remaining == 0 then
            GCP:Profile().priceHistory[itemID] = nil
        end
    end
end

-- Planungspreis fuer Empfehlungen: Median der letzten 7 Tage, solange es
-- Verlauf gibt, sonst der Momentanpreis. Zweiter Rueckgabewert: Anzahl der
-- eingeflossenen Tageswerte.
function Prices:GetPlanningPrice(itemID)
    local db = GCP.db
    local profile = db and GCP:Profile() or nil
    local history = profile and profile.priceHistory and profile.priceHistory[itemID]
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
-- PLAUSIBILITAET EINES VERKAUFSPREISES (1.0.0-beta.3)
--
-- Die Herleitung steht bei C.PRICE_SANITY in Constants.lua. Hier steht nur die
-- Ausfuehrung, und sie folgt einer Regel: Erst nach Belegen suchen, dann
-- zweifeln. Ein Item, fuer das jemand nachweislich gezahlt hat oder um das
-- mehrere Anbieter konkurrieren, wird nie beanstandet - unabhaengig davon, wie
-- hoch sein Preis steht.
-- ---------------------------------------------------------------------------

-- Gibt es einen bestaetigten eigenen Verkauf dieses Items? Das ist der
-- staerkste Beleg, den das Addon ueberhaupt kennt: Da hat wirklich jemand
-- bezahlt, und zwar diesem Spieler.
function Prices:HasConfirmedSale(itemID)
    if not GCP.Ledger or type(itemID) ~= "number" then return false end
    local stats = GCP.Ledger:GetItemStats(itemID)
    return type(stats) == "table" and (stats.soldQuantity or 0) > 0
end

-- Ist der Markt dieses Items besetzt? Gemessen wird ausschliesslich, was der
-- Spieler selbst im Auktionshaus gesehen hat - hochgerechnet wird nichts.
function Prices:HasCompetitiveMarket(itemID)
    if not GCP.Market or type(itemID) ~= "number" then return false end
    local S = GCP.Constants.PRICE_SANITY
    local depth = GCP.Market:GetDepth(itemID)
    if type(depth) ~= "table" then return false end
    if (depth.ageSeconds or math.huge) > S.MAX_DEPTH_AGE then return false end
    return (depth.listingCount or 0) >= S.MIN_LISTINGS
end

-- Alter des letzten Auctionator-Scans in Tagen, gemessen am Referenzgut.
-- nil heisst "unbekannt" - dann wird ueber Angebote nicht geurteilt.
function Prices:GetReferenceScanAgeDays()
    return self:GetScanAgeDays(GCP.Constants.PRICE_SANITY.SCAN_REFERENCE_ITEM)
end

-- Liegt dieses Item gerade ueberhaupt im Auktionshaus? Die Begruendung des
-- Verfahrens steht bei SCAN_REFERENCE_ITEM in Constants.lua.
--
-- Rueckgabe: "listed" | "absent" | "unknown", dazu Item- und Referenzalter.
-- Ausdruecklich drei Zustaende: "unbekannt" ist keine Ablehnung. Wer nie
-- gescannt hat, bekommt keine Vorwuerfe, sondern keine Aussage.
function Prices:GetListingState(itemID)
    if type(itemID) ~= "number" then return "unknown", nil, nil end
    local S = GCP.Constants.PRICE_SANITY

    -- Eigene frische Beobachtung schlaegt jede Ableitung: Wer die Angebote
    -- selbst gesehen hat, braucht kein Scanalter zu vergleichen.
    if GCP.Market then
        local depth = GCP.Market:GetDepth(itemID)
        if type(depth) == "table" and (depth.ageSeconds or math.huge) <= S.MAX_DEPTH_AGE then
            return (depth.listingCount or 0) > 0 and "listed" or "absent", 0, 0
        end
    end

    local reference = self:GetReferenceScanAgeDays()
    local age = self:GetScanAgeDays(itemID)
    if reference == nil or age == nil then return "unknown", age, reference end
    if (age - reference) >= S.ABSENT_AFTER_DAYS then
        return "absent", age, reference
    end
    return "listed", age, reference
end

-- Fertiger Befund fuer die KAUFSEITE einer Chance: Laesst sich das ueberhaupt
-- besorgen? Rueckgabe: kaufbar (bool), Grund (string oder nil).
--
-- Zuerst die harte Aussage: Beim Aufheben oder per Quest gebundene Gegenstaende
-- kommen NIE ins Auktionshaus. Eine Daemonische Rune laesst sich nicht kaufen,
-- egal wie voll das Haus ist - sie wird gefarmt. IsAuctionable kannte diese
-- Frage schon, wurde aber bis 1.0.0-beta.3 nur auf die Verkaufsseite
-- angewendet ("darf ich das einstellen?"). Fuer die Kaufseite gilt sie genauso,
-- und dort ist sie sogar wichtiger: Ein Plan, der etwas Ungekauftes einkauft,
-- ist nicht ungenau, sondern unausfuehrbar.
function Prices:AssessPurchase(itemID)
    if type(itemID) == "number" and not self:IsAuctionable(itemID) then
        local name = GetItemInfoCompat(itemID) or ("Item " .. tostring(itemID))
        return false, string.format(
            "%s ist beim Aufheben gebunden und steht nie im Auktionshaus – das "
            .. "lässt sich nicht kaufen, sondern nur farmen.", name)
    end

    local state, age, reference = self:GetListingState(itemID)
    if state ~= "absent" then return true, nil end
    if age and reference then
        return false, string.format(
            "Keine Angebote gesehen: Dieses Item stand zuletzt vor %d Tag(en) in "
            .. "einem Scan, das Auktionshaus wurde aber vor %d Tag(en) zuletzt "
            .. "erfasst. Der Preis stammt also aus der Erinnerung, nicht aus "
            .. "dem Haus – kaufen lässt sich dort gerade nichts.",
            age, reference)
    end
    return false, "Keine Angebote im Auktionshaus gesehen."
end

-- Kern der Pruefung. price ist der geplante VERKAUFSPREIS (brutto, vor
-- AH-Gebuehr), reference ein optionaler zweiter Anker - bei Crafts die
-- Materialkosten des Durchgangs.
--
-- Rueckgabe: plausibel (bool), Grund (string oder nil).
function Prices:AssessSalePrice(itemID, price, reference)
    price = tonumber(price)
    if type(itemID) ~= "number" or not price or price <= 0 then
        return true, nil
    end
    local S = GCP.Constants.PRICE_SANITY

    -- Kleine Betraege werden nicht befragt. Ein Vielfaches ist bei billiger
    -- Ware keine Aussage: 2 Kupfer beim Haendler und 80 Silber im
    -- Auktionshaus sind das Viertausendfache und trotzdem der Normalfall.
    if price < S.MIN_ABSURD_PRICE then return true, nil end

    -- Gegenbelege als Naechstes. Wer sie hat, wird nicht weiter befragt.
    if self:HasConfirmedSale(itemID) then return true, nil end
    if self:HasCompetitiveMarket(itemID) then return true, nil end

    -- Der Haendlervergleich gilt nur fuer Waffen und Ruestung; die Begruendung
    -- steht bei VENDOR_CLASSES.
    local classID = select(12, GetItemInfoCompat(itemID))
    if S.VENDOR_CLASSES[classID] then
        local vendor = self:GetVendorPrice(itemID)
        if vendor and vendor > 0 and price > vendor * S.VENDOR_FACTOR then
            return false, string.format(
                "Preis unbelegt: %s im Auktionshaus gegenüber %s beim Händler – "
                .. "das %.0f-Fache. Es gibt weder einen eigenen Verkauf noch "
                .. "mehrere Anbieter; sehr wahrscheinlich steht dort eine "
                .. "einzelne Fantasie-Auktion.",
                self:FormatMoney(price), self:FormatMoney(vendor), price / vendor)
        end
    end

    reference = tonumber(reference)
    if reference and reference > 0 and price > reference * S.CRAFT_FACTOR then
        return false, string.format(
            "Preis unbelegt: %s Erlös aus %s Material – das %.0f-Fache. Wer das "
            .. "Rezept hat, könnte das jederzeit unterbieten. Dass es niemand "
            .. "tut, spricht gegen einen Markt, nicht für eine Marge.",
            self:FormatMoney(price), self:FormatMoney(reference), price / reference)
    end

    return true, nil
end

-- ---------------------------------------------------------------------------
-- Datenqualitaet des Planungspreises. GetPlanningPrice liefert die Anzahl der
-- eingeflossenen Tageswerte ohnehin mit - erst benannt wird daraus eine
-- Aussage: Der Median aus zwei Tagen ist kaum mehr als eine Momentaufnahme,
-- der aus sieben ist eine Preisbasis.
-- ---------------------------------------------------------------------------

function Prices:ConfidenceLabel(days)
    days = tonumber(days) or 0
    if days <= 0 then return "Momentanpreis" end
    if days <= 2 then return "wenig Daten" end
    if days <= 5 then return "mittlere Datenbasis" end
    return "gute Datenbasis"
end

-- Fertige Zeile fuer Tooltip und Breakdown.
function Prices:FormatPlanningBasis(days)
    days = tonumber(days) or 0
    if days <= 0 then
        return "Preisbasis: aktueller Marktpreis · noch keine Historie"
    end
    return string.format("Preisbasis: 7-Tage-Median · %.0f Tageswert%s · %s",
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
