local addonName, GCP = ...

GCP.Advisor = {}
local Advisor = GCP.Advisor

local CLASS_TRADEGOODS = 7
local CLASS_WEAPON = 2
local CLASS_ARMOR = 4

local function matchesFilter(entry, filter)
    if filter == "mats" then
        return entry.classID == CLASS_TRADEGOODS
    elseif filter == "gear" then
        return entry.classID == CLASS_WEAPON or entry.classID == CLASS_ARMOR
    elseif filter == "keep" then
        return entry.classID == GCP.Constants.CLASS_CONSUMABLE
    end
    return true
end

-- Eigenbedarf: Traenke, Elixiere und Essen schlaegt der Tagesplan nicht zum
-- Verkauf vor. Wer 40 Manatraenke mit sich fuehrt, hat sie fuer den Raid
-- dabei - ein Addon, das ihm empfiehlt, sie zu verkaufen, hat die Frage
-- "wie werde ich reich" mit "verkauf deine Ausruestung" beantwortet.
local function isPersonalUse(entry)
    return entry.classID == GCP.Constants.CLASS_CONSUMABLE
end

-- Syndicator benennt Charaktere als "Name-Realm". Auf dem eigenen Realm ist
-- der Zusatz Rauschen; in der Liste steht deshalb der blosse Name.
function Advisor:ShortName(fullName)
    if type(fullName) ~= "string" then return nil end
    return (fullName:gsub("%-.*$", ""))
end

-- Bewertet ein einzelnes Item ueber alle Verkaufskanaele und benennt den besten.
-- Rueckgabe nil, wenn das Item ueber keinen Kanal Geld einbringt.
function Advisor:Evaluate(entry)
    local Prices = GCP.Prices
    local market, source = Prices:GetMarketPrice(entry.itemID)
    local vendor = entry.sellPrice or Prices:GetVendorPrice(entry.itemID)
    local netMarket = market and Prices:NetAuction(market) or nil

    local disenchant = nil
    if (entry.classID == CLASS_WEAPON or entry.classID == CLASS_ARMOR)
        and entry.quality and entry.quality >= 2 and entry.link then
        disenchant = Prices:GetDisenchantPrice(entry.link)
    end

    -- Graue Items nimmt das AH nicht an, gebundene auch nicht: Dort zaehlen nur
    -- Haendler und Entzaubern.
    local canAuction = (entry.quality or 0) >= 1 and not entry.bound
    local best, channel = 0, nil
    if canAuction and netMarket and netMarket > best then
        best, channel = netMarket, "AH"
    end
    if vendor and vendor > best then
        best, channel = vendor, "Händler"
    end
    if disenchant and disenchant > best then
        best, channel = disenchant, "Entzaubern"
    end
    if not channel then
        return nil
    end

    -- Bei WEM liegt das Zeug? Aufgeteilt auf mehrere Charaktere gewinnt der
    -- mit dem groessten Stapel; bei Gleichstand der alphabetisch erste, damit
    -- dieselbe Datenlage immer dieselbe Zuordnung ergibt.
    local primaryOwner, primaryCount, ownerCount = nil, 0, 0
    for owner, count in pairs(entry.owners or {}) do
        ownerCount = ownerCount + 1
        if count > primaryCount
            or (count == primaryCount and owner < (primaryOwner or "")) then
            primaryOwner, primaryCount = owner, count
        end
    end

    return {
        itemID = entry.itemID,
        name = entry.name,
        link = entry.link,
        icon = entry.icon,
        quality = entry.quality,
        count = entry.count,
        sources = entry.sources,
        owners = entry.owners,
        owner = primaryOwner,
        ownerCount = ownerCount,
        ownerLabel = primaryOwner and Advisor:ShortName(primaryOwner) or nil,
        bound = entry.bound,
        keep = isPersonalUse(entry) or nil,
        channel = channel,
        unitValue = best,
        totalValue = best * entry.count,
        marketUnit = market,
        marketSource = source,
        vendorUnit = vendor,
        disenchantUnit = disenchant,
    }
end

function Advisor:ToggleIgnored(itemID)
    local ignored = GCP.db.options.ignored
    if ignored[itemID] then
        ignored[itemID] = nil
    else
        ignored[itemID] = true
    end
end

-- Der Kern des Verkaufen-Tabs: alle Bestaende bewertet und sortiert.
-- scope "bags" oder "account", filter "all" | "mats" | "gear".
-- showIgnored kehrt die Ignorier-Liste um und zeigt nur Ausgeblendetes,
-- damit ein Doppelklick dort Items wieder hervorholen kann.
--
-- sort "value" (Vorgabe) oder "owner". Nach Charakter sortiert liest sich die
-- Liste als Packliste: Wer sein Zeug zusammensuchen will, laeuft nicht
-- vierzehnmal zwischen Charakteren hin und her - er nimmt einen nach dem
-- anderen. Innerhalb eines Charakters bleibt es beim Wert.
function Advisor:BuildReport(scope, filter, showIgnored, sort)
    local Inventory = GCP.Inventory
    local options = (GCP.db and GCP.db.options) or {}
    local ignoredList = options.ignored or {}
    local items, accountWide
    if scope == "account" then
        items, accountWide = Inventory:ScanAccount()
    else
        items, accountWide = Inventory:ScanBags({}), false
    end

    local rows = {}
    local totalValue = 0
    local missingInfo = 0
    local missingPrice = 0
    local ignoredCount = 0
    for _, entry in pairs(items) do
        Inventory:Describe(entry)
        local isIgnored = ignoredList[entry.itemID] == true
        if isIgnored then
            ignoredCount = ignoredCount + 1
        end
        local visible
        if showIgnored then
            visible = isIgnored
        else
            visible = not isIgnored and not (options.hideBound and entry.bound)
        end
        if not entry.name then
            missingInfo = missingInfo + 1
        elseif visible and matchesFilter(entry, filter or "all") then
            local row = self:Evaluate(entry)
            if row then
                if not row.marketUnit then
                    missingPrice = missingPrice + 1
                end
                rows[#rows + 1] = row
                totalValue = totalValue + row.totalValue
            end
        end
    end

    local byValue = function(a, b)
        if a.totalValue ~= b.totalValue then
            return a.totalValue > b.totalValue
        end
        return (a.name or "") < (b.name or "")
    end
    if sort == "owner" then
        table.sort(rows, function(a, b)
            -- Was keinem Charakter zugeordnet ist, steht hinten. Es ihm
            -- zuzuschlagen waere geraten.
            local aOwner, bOwner = a.owner or "\255", b.owner or "\255"
            if aOwner ~= bOwner then return aOwner < bOwner end
            return byValue(a, b)
        end)
    else
        table.sort(rows, byValue)
    end

    -- Wert je Charakter. Die Zeile ueber der Gruppe beantwortet die Frage, die
    -- man beim Umschalten stellt: Lohnt der Weg zu diesem Charakter ueberhaupt?
    local byOwner, owners = {}, {}
    for _, row in ipairs(rows) do
        local key = row.owner or ""
        if not byOwner[key] then
            byOwner[key] = { owner = row.owner, label = row.ownerLabel,
                value = 0, items = 0 }
            owners[#owners + 1] = byOwner[key]
        end
        byOwner[key].value = byOwner[key].value + row.totalValue
        byOwner[key].items = byOwner[key].items + 1
    end

    return {
        rows = rows,
        totalValue = totalValue,
        accountWide = accountWide,
        missingInfo = missingInfo,
        missingPrice = missingPrice,
        ignoredCount = ignoredCount,
        sort = sort == "owner" and "owner" or "value",
        owners = owners,
        byOwner = byOwner,
    }
end
