local addonName, GCP = ...

GCP.Capital = {}
local Capital = GCP.Capital

local GetItemInfoCompat = (C_Item and C_Item.GetItemInfo) or GetItemInfo

-- ---------------------------------------------------------------------------
-- CAPITAL BRAIN (0.9.0)
--
-- 0.5 bis 0.8 beantworten Fragen ueber einzelne Items: Ist der Preis guenstig?
-- Ist daraus eine Chance ableitbar? Wie schnell komme ich wieder heraus?
-- Keine dieser Fragen ist die, die am Anfang einer Sitzung steht:
--
--     "Wie viel Gold habe ich ueberhaupt frei - und wohin damit?"
--
-- Dieses Modul beantwortet sie. Es erfindet dafuer keine Marktaussage: Alles,
-- was es rechnet, sind Summen ueber Dinge, die andere Module bereits belegt
-- haben - offene Auktionen aus dem Ledger, Bestand aus Inventory, Preise aus
-- Prices, Liquiditaet aus Ledger, Catalysts aus Future.
--
-- WAS HIER AUSDRUECKLICH NICHT PASSIERT:
--   * Keine erfundene Kostenbasis. Wer 40 Netherstoff farmt und verkauft, hat
--     dafuer nichts bezahlt - aber "Einstand 0" waere eine Luege, die jeden
--     Gewinn aufblaeht. Unbekannt bleibt unbekannt (nil).
--   * Kein "jedes Item im Beutel ist ein Investment". Ein Manatrank ist kein
--     Investment, und die Ruestung, die man traegt, erst recht nicht. Als
--     Position zaehlt nur, was im Auktionshaus liegt oder nachweislich gekauft
--     wurde.
--   * Keine Behauptung ueber den Gesamtbestand des Accounts, wenn Syndicator
--     fehlt. Dann steht da der eigene Charakter - und das steht auch dran.
--   * Keine feste Fantasiegrenze im Code. Alle Exposure-Grenzen stehen in
--     Constants.lua und sind eine Risikopolitik, keine Marktaussage.
--
-- ---------------------------------------------------------------------------
-- DAS POSITIONSMODELL
--
-- Eine Position ist eine Menge eines Items, die Kapital bindet:
--
--   {
--       itemID, quantity,
--       source = "auction" | "inventory",
--       costBasis,          -- Stueckpreis oder nil = UNKNOWN
--       costBasisKnown,     -- true nur, wenn Kaeufe die Menge decken
--       currentValue,       -- netto ueber alle Stueck, oder nil
--       unrealizedPnL,      -- nur wenn costBasis bekannt
--       capitalAllocated,   -- costBasis * quantity, oder nil
--       depositAtRisk,      -- nur bei offenen Auktionen
--       liquidityScore, opportunityType, catalystIDs, phase, confidence
--   }
--
-- HERKUNFT DER KOSTENBASIS. Das Ledger kennt gekaufte Stueckzahl und
-- gewichteten Einkaufspreis je Item. Die Frage ist, ob die Stuecke, die JETZT
-- da liegen, aus diesen Kaeufen stammen. Belastbar ist das nur, wenn
-- (gekauft - verkauft) mindestens so gross ist wie die Position. Sonst ist ein
-- Teil selbst gefarmt, gecraftet oder erbeutet - und dann gibt es keine
-- Kostenbasis, sondern nil.
-- ---------------------------------------------------------------------------

-- Laufzeitzustand. Gehoert nicht in die SavedVariables.
Capital.cache = nil
Capital.cacheAt = nil
Capital.cacheSignature = nil
Capital.revision = 0

local CACHE_SECONDS = 20

local function config()
    return GCP.Constants.CAPITAL
end

local function clamp(value, low, high)
    if value < low then return low end
    if value > high then return high end
    return value
end

-- Saettigungskurve: bei half die halbe Auslenkung, danach flacher.
local function saturate(value, half)
    if type(value) ~= "number" or value <= 0 then return 0 end
    if type(half) ~= "number" or half <= 0 then return 0 end
    return value / (value + half)
end

local function isItemID(value)
    return type(value) == "number" and value > 0 and value == math.floor(value)
end

local function isPositiveNumber(value)
    return type(value) == "number" and value > 0
end

function Capital:Now()
    if type(time) == "function" then
        local ok, now = pcall(time)
        if ok and type(now) == "number" then return now end
    end
    return 0
end

function Capital:Touch()
    self.revision = self.revision + 1
    self.cache = nil
    self.cacheAt = nil
    self.cacheSignature = nil
end

function Capital:Invalidate()
    self:Touch()
end

-- ---------------------------------------------------------------------------
-- Speicher
--
--   db.capital = {
--       version = 1,
--       reserve = { mode = "percent", percent = 0.2, absolute = 10000000 },
--       meta = { [itemID] = { t = "craft", p = "phase-id", c = {1,2}, at = ... } },
--   }
--
-- meta ist die Provenance einer Position: Welche Chancenart hat sie erzeugt?
-- Sie wird von der Guide Engine geschrieben, sobald ein Kauf aus einer Route
-- bestaetigt ist. Ohne Guide bleibt sie leer, und dann heisst die Chancenart
-- schlicht "unbekannt" - nicht "resale".
-- ---------------------------------------------------------------------------

function Capital:EnsureStore()
    local db = GCP.db
    if not db then return nil end
    local C = config()
    local profile = GCP:Profile()
    local store = profile.capital
    if type(store) ~= "table" or store.version ~= C.STORE_VERSION then
        store = { version = C.STORE_VERSION }
        profile.capital = store
    end
    if type(store.reserve) ~= "table" then
        store.reserve = {
            mode = C.RESERVE.DEFAULT_MODE,
            percent = C.RESERVE.DEFAULT_PERCENT,
            absolute = C.RESERVE.DEFAULT_ABSOLUTE,
        }
    end
    if type(store.meta) ~= "table" then store.meta = {} end
    return store
end

function Capital:GetReserveSettings()
    local store = self:EnsureStore()
    local C = config().RESERVE
    if not store then
        return { mode = C.DEFAULT_MODE, percent = C.DEFAULT_PERCENT,
            absolute = C.DEFAULT_ABSOLUTE }
    end
    local reserve = store.reserve
    if reserve.mode ~= "percent" and reserve.mode ~= "absolute" then
        reserve.mode = C.DEFAULT_MODE
    end
    if type(reserve.percent) ~= "number" or reserve.percent < 0 then
        reserve.percent = C.DEFAULT_PERCENT
    end
    reserve.percent = clamp(reserve.percent, 0, C.MAX_PERCENT)
    if type(reserve.absolute) ~= "number" or reserve.absolute < 0 then
        reserve.absolute = C.DEFAULT_ABSOLUTE
    end
    return reserve
end

function Capital:SetReserve(mode, value)
    local store = self:EnsureStore()
    if not store then return false end
    local C = config().RESERVE
    local reserve = self:GetReserveSettings()
    if mode == "percent" then
        reserve.mode = "percent"
        if type(value) == "number" then
            reserve.percent = clamp(value, 0, C.MAX_PERCENT)
        end
    elseif mode == "absolute" then
        reserve.mode = "absolute"
        if type(value) == "number" then
            reserve.absolute = math.max(0, math.floor(value))
        end
    else
        return false
    end
    self:Touch()
    return true
end

-- Die Reserve in Kupfer. Prozentual bezogen auf das Gold, das JETZT da ist -
-- nicht auf das Gesamtvermoegen: Was im Auktionshaus liegt, kann man im
-- Notfall nicht ausgeben.
function Capital:ComputeReserve(currentGold)
    local reserve = self:GetReserveSettings()
    currentGold = math.max(tonumber(currentGold) or 0, 0)
    local value
    if reserve.mode == "absolute" then
        value = reserve.absolute
    else
        value = math.floor(currentGold * reserve.percent + 0.5)
    end
    return clamp(value, 0, currentGold)
end

function Capital:DescribeReserve()
    local reserve = self:GetReserveSettings()
    if reserve.mode == "absolute" then
        return string.format("fest %s", GCP.Prices:FormatGold(reserve.absolute))
    end
    return string.format("%d %% deines Goldes", math.floor(reserve.percent * 100 + 0.5))
end

-- ---------------------------------------------------------------------------
-- Positions-Provenance
-- ---------------------------------------------------------------------------

function Capital:RememberPositionMeta(itemID, meta)
    if not isItemID(itemID) or type(meta) ~= "table" then return false end
    local store = self:EnsureStore()
    if not store then return false end
    local entry = store.meta[itemID] or {}
    entry.t = meta.opportunityType or entry.t
    entry.p = meta.phase or entry.p
    if type(meta.catalystIDs) == "table" and #meta.catalystIDs > 0 then
        local ids = {}
        for index = 1, math.min(#meta.catalystIDs, 6) do
            ids[index] = meta.catalystIDs[index]
        end
        entry.c = ids
    end
    entry.at = self:Now()
    store.meta[itemID] = entry
    self:PruneMeta()
    self:Touch()
    return true
end

function Capital:GetPositionMeta(itemID)
    local store = self:EnsureStore()
    if not store then return nil end
    return store.meta[itemID]
end

function Capital:PruneMeta(now)
    local store = self:EnsureStore()
    if not store then return 0 end
    local C = config()
    now = tonumber(now) or self:Now()
    local removed = 0
    local order = {}
    for itemID, entry in pairs(store.meta) do
        if type(entry) ~= "table" or type(entry.at) ~= "number"
            or (now - entry.at) > C.POSITION_META_TTL then
            store.meta[itemID] = nil
            removed = removed + 1
        else
            order[#order + 1] = { itemID = itemID, at = entry.at }
        end
    end
    if #order > C.MAX_POSITION_META then
        table.sort(order, function(a, b) return a.at < b.at end)
        for index = 1, #order - C.MAX_POSITION_META do
            store.meta[order[index].itemID] = nil
            removed = removed + 1
        end
    end
    return removed
end

-- ---------------------------------------------------------------------------
-- Gold
--
-- GetMoney ist der eingeloggte Charakter. Syndicator kennt daneben die anderen
-- Charaktere des Accounts - aber deren Gold liegt woanders und ist fuer die
-- Planung dieser Sitzung nicht verfuegbar. Deshalb steht es getrennt und geht
-- NICHT in availableGold ein.
-- ---------------------------------------------------------------------------

function Capital:GetGold()
    local current = 0
    if type(GetMoney) == "function" then
        local ok, money = pcall(GetMoney)
        if ok and type(money) == "number" and money >= 0 then current = money end
    end
    local others, characters = nil, nil
    local ok, sum, count = pcall(function()
        if not (Syndicator and Syndicator.API
            and type(Syndicator.API.GetAllCharacters) == "function") then
            return nil, nil
        end
        local mine = Syndicator.API.GetCurrentCharacter and Syndicator.API.GetCurrentCharacter()
        local total, seen = 0, 0
        for _, name in ipairs(Syndicator.API.GetAllCharacters() or {}) do
            if name ~= mine then
                local char = Syndicator.API.GetByCharacterFullName(name)
                local money = char and (char.money
                    or (char.details and char.details.money))
                if type(money) == "number" and money >= 0 then
                    total = total + money
                    seen = seen + 1
                end
            end
        end
        return total, seen
    end)
    if ok and type(sum) == "number" then
        others = sum
        characters = count
    end
    return current, others, characters
end

-- ---------------------------------------------------------------------------
-- Positionen
-- ---------------------------------------------------------------------------

local function marketGroup(itemID)
    if type(GetItemInfoCompat) ~= "function" then return nil, nil end
    local ok, _, _, _, _, _, itemType, itemSubType = pcall(GetItemInfoCompat, itemID)
    if not ok or type(itemType) ~= "string" then return nil, nil end
    if type(itemSubType) == "string" and itemSubType ~= "" then
        return itemType .. "/" .. itemSubType, itemType .. " · " .. itemSubType
    end
    return itemType, itemType
end

-- Wert einer Menge netto: Was bliebe, wenn man es jetzt ueber den besten Kanal
-- losschluege. GetBestPlanningValue zieht die AH-Gebuehr bereits ab und faellt
-- auf den Haendlerpreis zurueck, wo das AH nichts hergibt.
function Capital:UnitValue(itemID)
    local value, source, days = GCP.Prices:GetBestPlanningValue(itemID)
    return value, source, days
end

-- Wie viele Stueck dieses Items liegen gerade unverkauft im eigenen
-- Auktionshaus? Die Antwort kommt aus der eigenen Handelsbilanz - es ist keine
-- Vermutung ueber den Markt, sondern die eigene offene Einstellung.
function Capital:PostedQuantity(itemID)
    if not isItemID(itemID) then return 0 end
    local snapshot = self:GetSnapshot()
    local posted = type(snapshot) == "table" and snapshot.postedByItem or nil
    return (type(posted) == "table" and posted[itemID]) or 0
end

-- Wie viele Stueck dieses Items lassen sich mit einer belegten Kostenbasis
-- erklaeren? Rueckgabe: Deckungsmenge und Stueckpreis (beide nil = UNKNOWN).
function Capital:CostBasisFor(itemID)
    local stats = GCP.Ledger and GCP.Ledger:GetItemStats(itemID)
    if not stats then return nil, nil end
    local bought = stats.boughtQuantity or 0
    if bought <= 0 then return nil, nil end
    local unit = stats.averageBuyPrice
    if not isPositiveNumber(unit) then return nil, nil end
    local covered = bought - (stats.soldQuantity or 0)
    if covered <= 0 then return 0, unit end
    return covered, unit
end

local function newPosition(itemID, quantity, source)
    return {
        itemID = itemID,
        quantity = quantity,
        source = source,
        costBasis = nil,
        costBasisKnown = false,
        capitalAllocated = nil,
        currentValue = nil,
        unrealizedPnL = nil,
        depositAtRisk = 0,
    }
end

-- Offene Auktionen aus dem Ledger, je Item zusammengefasst. Das sind die
-- einzigen Positionen, bei denen der Verkaufsvorgang bereits laeuft.
function Capital:CollectAuctionPositions(byItem)
    local Ledger = GCP.Ledger
    if not Ledger then return 0 end
    local store = Ledger:EnsureStore()
    if not store or type(store.open) ~= "table" then return 0 end
    local open = store.open
    local stride = 6
    local count = 0
    for base = 0, #open - stride, stride do
        local itemID = open[base + 1]
        local quantity = open[base + 3]
        local unitPrice = open[base + 4]
        local deposit = open[base + 5]
        if isItemID(itemID) and isPositiveNumber(quantity) then
            local entry = byItem[itemID]
            if not entry then
                entry = newPosition(itemID, 0, "auction")
                byItem[itemID] = entry
            end
            entry.quantity = entry.quantity + quantity
            entry.source = "auction"
            entry.askTotal = (entry.askTotal or 0)
                + (isPositiveNumber(unitPrice) and unitPrice * quantity or 0)
            entry.depositAtRisk = (entry.depositAtRisk or 0)
                + (isPositiveNumber(deposit) and deposit or 0)
            entry.auctions = (entry.auctions or 0) + 1
            count = count + 1
        end
    end
    return count
end

-- Bestand, der nachweislich gekauft wurde. Alles andere bleibt Bestand und
-- wird nicht zur Position erklaert.
function Capital:CollectInventoryPositions(byItem, inventory)
    if type(inventory) ~= "table" then return 0 end
    local count = 0
    for itemID, entry in pairs(inventory) do
        if isItemID(itemID) and isPositiveNumber(entry and entry.count) then
            local covered = self:CostBasisFor(itemID)
            if covered and covered > 0 then
                local already = byItem[itemID]
                local posted = already and already.quantity or 0
                -- Was schon im Auktionshaus liegt, ist bereits gezaehlt; nur
                -- der Rest der gekauften Menge liegt noch im Beutel.
                local free = math.max(covered - posted, 0)
                local quantity = math.min(entry.count, free)
                if quantity > 0 then
                    local position = already
                    if not position then
                        position = newPosition(itemID, 0, "inventory")
                        byItem[itemID] = position
                    end
                    position.quantity = position.quantity + quantity
                    position.inventoryQuantity =
                        (position.inventoryQuantity or 0) + quantity
                    count = count + 1
                end
            end
        end
    end
    return count
end

function Capital:FinishPosition(position)
    local itemID = position.itemID
    local covered, unit = self:CostBasisFor(itemID)
    if covered and unit and covered >= position.quantity then
        position.costBasis = unit
        position.costBasisKnown = true
        position.capitalAllocated = math.floor(unit * position.quantity + 0.5)
    else
        position.costBasis = nil
        position.costBasisKnown = false
        position.capitalAllocated = nil
        position.costBasisCoverage = covered and position.quantity > 0
            and clamp(covered / position.quantity, 0, 1) or 0
    end

    local unitValue, valueSource = self:UnitValue(itemID)
    if isPositiveNumber(unitValue) then
        position.unitValue = unitValue
        position.valueSource = valueSource
        position.currentValue = math.floor(unitValue * position.quantity + 0.5)
    end
    if position.costBasisKnown and position.currentValue then
        position.unrealizedPnL = position.currentValue - position.capitalAllocated
    end

    local liquidity = GCP.Ledger and GCP.Ledger:GetLiquidity(itemID)
    if liquidity then
        position.liquidityScore = liquidity.liquidityScore
        position.liquidityConfidence = liquidity.confidence
        position.expectedHours = liquidity.expectedHours
    end

    local meta = self:GetPositionMeta(itemID)
    position.opportunityType = meta and meta.t or nil
    position.phase = meta and meta.p or nil
    position.catalystIDs = meta and meta.c or nil

    -- Catalysts kommen bevorzugt aus der Wissensbasis: Sie haengen am Item,
    -- nicht an der Herkunft der Position. GetCatalysts liefert Fundstellen
    -- ({ catalyst = ..., depth = ... }), nicht die Catalysts selbst.
    if GCP.Future then
        local ok, found = pcall(GCP.Future.GetCatalysts, GCP.Future, itemID)
        if ok and type(found) == "table" and #found > 0 then
            local ids, phase = {}, position.phase
            for _, entry in ipairs(found) do
                local catalyst = entry.catalyst
                if catalyst and catalyst.id then
                    ids[#ids + 1] = catalyst.id
                    if not phase and catalyst.phase then phase = catalyst.phase end
                end
            end
            if #ids > 0 then position.catalystIDs = ids end
            position.phase = phase
        end
    end

    position.groupKey, position.groupLabel = marketGroup(itemID)
    position.name = (GetItemInfoCompat and GetItemInfoCompat(itemID)) or nil
    return position
end

function Capital:BuildPositions(inventory)
    local byItem = {}
    self:CollectAuctionPositions(byItem)
    self:CollectInventoryPositions(byItem, inventory)
    local list = {}
    for _, position in pairs(byItem) do
        if position.quantity > 0 then
            list[#list + 1] = self:FinishPosition(position)
        end
    end
    table.sort(list, function(a, b)
        local av = a.capitalAllocated or a.currentValue or 0
        local bv = b.capitalAllocated or b.currentValue or 0
        if av ~= bv then return av > bv end
        return a.itemID < b.itemID
    end)
    return list
end

-- ---------------------------------------------------------------------------
-- Exposure
--
-- Bezugsgroesse ist das INVESTIERBARE Kapital: das freie Gold plus das, was
-- bereits in Positionen steckt. Nicht das Gesamtvermoegen - die Reserve soll
-- gerade nicht als Spielraum durchgehen -, und nicht nur das freie Gold, sonst
-- waere jede bestehende Position sofort ueber jeder Grenze.
-- ---------------------------------------------------------------------------

local DIMENSIONS = { "item", "type", "catalyst", "phase", "group" }

local function addExposure(bucket, key, label, value, quantity)
    if key == nil then return end
    local entry = bucket[key]
    if not entry then
        entry = { key = key, label = label, value = 0, quantity = 0, positions = 0 }
        bucket[key] = entry
    end
    entry.value = entry.value + (value or 0)
    entry.quantity = entry.quantity + (quantity or 0)
    entry.positions = entry.positions + 1
end

function Capital:BuildExposure(positions, base)
    local exposure = {}
    for _, dimension in ipairs(DIMENSIONS) do exposure[dimension] = {} end
    for _, position in ipairs(positions) do
        -- Bewertet wird mit dem gebundenen Kapital, wo es bekannt ist, sonst
        -- mit dem heutigen Wert. Eine Position ohne beides zaehlt nur als
        -- Stueckzahl - sie bindet Kapital, das niemand beziffern kann.
        local value = position.capitalAllocated or position.currentValue or 0
        addExposure(exposure.item, position.itemID,
            position.name or ("Item " .. position.itemID), value, position.quantity)
        addExposure(exposure.type, position.opportunityType or "unknown",
            GCP.Opportunity and GCP.Opportunity:TypeLabel(position.opportunityType)
                or "unbekannt", value, position.quantity)
        if type(position.catalystIDs) == "table" then
            for _, catalystID in ipairs(position.catalystIDs) do
                addExposure(exposure.catalyst, catalystID, catalystID, value,
                    position.quantity)
            end
        end
        addExposure(exposure.phase, position.phase, position.phase, value,
            position.quantity)
        addExposure(exposure.group, position.groupKey, position.groupLabel,
            value, position.quantity)
    end
    if isPositiveNumber(base) then
        for _, dimension in ipairs(DIMENSIONS) do
            for _, entry in pairs(exposure[dimension]) do
                entry.share = entry.value / base
            end
        end
    end
    return exposure
end

function Capital:ExposureValue(exposure, dimension, key)
    if not exposure or key == nil then return 0 end
    local bucket = exposure[dimension]
    local entry = bucket and bucket[key]
    return entry and entry.value or 0
end

function Capital:ExposureShare(exposure, dimension, key)
    if not exposure or key == nil then return nil end
    local bucket = exposure[dimension]
    local entry = bucket and bucket[key]
    return entry and entry.share or nil
end

-- Alle Dimensionen, die ueber ihrer Warnschwelle liegen. Absteigend sortiert,
-- damit die Oberflaeche die dringendste zuerst zeigen kann.
function Capital:ExposureWarnings(exposure)
    local C = config()
    local warnings = {}
    if type(exposure) ~= "table" then return warnings end
    for _, dimension in ipairs(DIMENSIONS) do
        local limits = C.EXPOSURE[dimension:upper()]
        if limits then
            for _, entry in pairs(exposure[dimension] or {}) do
                if entry.share and entry.share >= limits.warn and entry.key ~= "unknown" then
                    warnings[#warnings + 1] = {
                        dimension = dimension,
                        key = entry.key,
                        label = entry.label,
                        share = entry.share,
                        value = entry.value,
                        overMax = entry.share >= limits.max,
                        text = string.format("%s %s: %.0f %% des investierbaren Kapitals",
                            C.EXPOSURE_LABEL[dimension] or dimension,
                            tostring(entry.label), entry.share * 100),
                    }
                end
            end
        end
    end
    table.sort(warnings, function(a, b) return a.share > b.share end)
    return warnings
end

-- ---------------------------------------------------------------------------
-- Gesamtbild
-- ---------------------------------------------------------------------------

local function signature()
    local db = GCP.db
    local parts = {
        tostring(GCP.Ledger and GCP.Ledger.revision or 0),
        tostring(GCP.Market and GCP.Market.revision or 0),
        tostring(Capital.revision),
    }
    if type(GetMoney) == "function" then
        local ok, money = pcall(GetMoney)
        parts[#parts + 1] = tostring(ok and money or "?")
    end
    local reserve = db and GCP:Profile().capital and GCP:Profile().capital.reserve
    if reserve then
        parts[#parts + 1] = tostring(reserve.mode)
        parts[#parts + 1] = tostring(reserve.percent)
        parts[#parts + 1] = tostring(reserve.absolute)
    end
    return table.concat(parts, "|")
end

function Capital:GetSnapshot(force)
    local now = (type(GetTime) == "function" and GetTime()) or self:Now()
    local sig = signature()
    if not force and self.cache and self.cacheSignature == sig
        and self.cacheAt and (now - self.cacheAt) < CACHE_SECONDS then
        return self.cache
    end
    local snapshot = self:ComputeSnapshot()
    self.cache = snapshot
    self.cacheAt = now
    self.cacheSignature = sig
    return snapshot
end

function Capital:ComputeSnapshot()
    local currentGold, otherGold, otherCharacters = self:GetGold()
    local reservedGold = self:ComputeReserve(currentGold)
    local availableGold = math.max(currentGold - reservedGold, 0)

    local inventory, accountWide = GCP.Inventory:ScanAccount()
    local positions = self:BuildPositions(inventory)

    local invested, positionsValue, unrealized = 0, 0, 0
    local unknownCost, knownCost, depositAtRisk = 0, 0, 0
    local openAuctions = 0
    -- Was liegt gerade unverkauft im eigenen Auktionshaus? Einmal je Snapshot
    -- aufgestellt, damit die Actionability nicht je Chance die ganze offene
    -- Liste durchgeht.
    local postedByItem = {}
    for _, position in ipairs(positions) do
        if position.source == "auction" and isItemID(position.itemID)
            and isPositiveNumber(position.quantity) then
            postedByItem[position.itemID] = position.quantity
        end
        if position.capitalAllocated then
            invested = invested + position.capitalAllocated
            knownCost = knownCost + 1
        else
            unknownCost = unknownCost + 1
        end
        positionsValue = positionsValue + (position.currentValue or 0)
        if position.unrealizedPnL then
            unrealized = unrealized + position.unrealizedPnL
        end
        depositAtRisk = depositAtRisk + (position.depositAtRisk or 0)
        openAuctions = openAuctions + (position.auctions or 0)
    end

    -- Bestandswert: alles, was der Spieler besitzt, zum besten planbaren Wert.
    -- Das ist ausdruecklich KEIN Investment, sondern eine Aussage darueber, was
    -- an Gold im Bestand steckt.
    local inventoryValue = 0
    for itemID, entry in pairs(inventory or {}) do
        if isItemID(itemID) and isPositiveNumber(entry.count) then
            local unitValue = self:UnitValue(itemID)
            if isPositiveNumber(unitValue) then
                inventoryValue = inventoryValue + unitValue * entry.count
            end
        end
    end
    inventoryValue = math.floor(inventoryValue + 0.5)

    local exposureBase = availableGold + invested
    local exposure = self:BuildExposure(positions, exposureBase)

    local snapshot = {
        currentGold = currentGold,
        otherCharacterGold = otherGold,
        otherCharacters = otherCharacters,
        accountWide = accountWide and true or false,
        reservedGold = reservedGold,
        reserveMode = self:GetReserveSettings().mode,
        reserveLabel = self:DescribeReserve(),
        availableGold = availableGold,
        investedCapital = invested,
        capitalAtRisk = invested + depositAtRisk,
        depositAtRisk = depositAtRisk,
        positionsValue = positionsValue,
        inventoryValue = inventoryValue,
        unrealizedPnL = knownCost > 0 and unrealized or nil,
        unrealizedKnownPositions = knownCost,
        unknownCostPositions = unknownCost,
        openPositions = #positions,
        openAuctions = openAuctions,
        positions = positions,
        postedByItem = postedByItem,
        exposureBase = exposureBase,
        exposure = exposure,
        computedAt = self:Now(),
    }
    snapshot.warnings = self:ExposureWarnings(exposure)
    snapshot.portfolioValue = currentGold + positionsValue
    return snapshot
end

-- ---------------------------------------------------------------------------
-- POSITION SIZING
--
-- Ausgangspunkt ist ein Anteil des investierbaren Kapitals (BASE_SHARE), auf
-- den mehrere Faktoren wirken. Multiplikativ und nicht additiv, weil sich die
-- Gruende gegenseitig verstaerken sollen: Eine gute Chance mit duenner
-- Datenlage und hoher Volatilitaet ist keine mittelgrosse Position, sondern
-- eine kleine.
--
-- Danach schneiden die Exposure-Grenzen ab, und erst zum Schluss wird in ganze
-- Stueck umgerechnet. Ein "0,7 mal kaufen" gibt es nicht.
-- ---------------------------------------------------------------------------

-- Obergrenze der Stueckzahl je Position (1.0.0-beta.3). Siehe die Begruendung
-- an MAX_UNITS_UNPROVEN in Constants.lua: Der Kapitalanteil deckelt einen
-- Betrag, nicht die Menge, und "das Gold reicht fuer 26 Stueck" ist keine
-- Aussage darueber, ob 26 Stueck jemand kauft.
--
-- options.maxUnitsPerPosition: nil oder "auto" = belegabhaengiger Deckel,
-- eine Zahl = harte Obergrenze des Nutzers, 0 = kein Deckel.
-- Rueckgabe: Deckel (oder nil) und die Begruendung fuer allocation.limitedBy.
function Capital:UnitCap(input)
    if type(input) ~= "table" then input = {} end
    local C = config().SIZING
    local option = GCP.db and GCP.db.options and GCP.db.options.maxUnitsPerPosition
    if type(option) == "number" then
        if option <= 0 then return nil, nil end
        return math.floor(option), "Stückzahl-Limit"
    end

    -- Belegt ist die Aufnahmefaehigkeit des Marktes durch eigene Verkaufsdaten
    -- oder durch eine frische Tiefenmessung. "liquidityScore vorhanden" allein
    -- genuegt nicht - der kann aus zwei Auktionen stammen.
    local proven = false
    local confidence = input.liquidityConfidence
    if confidence == "medium" or confidence == "high" then
        proven = true
    elseif isPositiveNumber(input.maxUnits) then
        -- maxUnits entsteht nur aus einer Messung, die juenger ist als
        -- MARKET.DEPTH.MAX_UNITS_FRESHNESS. Aelteres kommt hier nie an.
        proven = true
    end

    local cap, reason
    if proven then
        cap, reason = C.MAX_UNITS_PROVEN, "Stückzahl-Vorsicht"
    else
        cap, reason = C.MAX_UNITS_UNPROVEN, "keine Verkaufsdaten"
    end

    -- PERSOENLICHE MARKTAUFNAHME (1.0.0-beta.10). Die Deckel oben sind pauschal
    -- und kennen den Spieler nicht. Wer nach eigenen Daten rund 18 Stueck je
    -- Woche verkauft, soll nicht 80 Stueck einkaufen, nur weil Gold und
    -- Angebot es hergeben - die anderen 62 liegen dann Monate im Postfach.
    --
    -- Der Deckel greift ausschliesslich bei belastbarer eigener Datenlage und
    -- kann nur verkleinern, nie vergroessern: math.min gegen den bisherigen
    -- Wert, und die Begruendung wechselt nur mit, wenn er wirklich gegriffen
    -- hat.
    local absorption = input.absorptionPerWeek
    if isPositiveNumber(absorption) then
        local byAbsorption = math.max(
            math.floor(absorption * C.ABSORPTION_WEEKS), C.ABSORPTION_MIN_UNITS)
        if not cap or byAbsorption < cap then
            cap, reason = byAbsorption, "deine Verkaufsmenge"
        end
    end
    return cap, reason
end

function Capital:SizePosition(input)
    if type(input) ~= "table" then return nil, { reason = "Keine Eingabe." } end
    local C = config().SIZING
    local unitCost = input.unitCost
    if not isPositiveNumber(unitCost) then
        return nil, { reason = "Kein Kapitalbedarf bekannt." }
    end
    local investable = math.max(tonumber(input.investable) or 0, 0)
    if investable <= 0 then
        return nil, { reason = "Kein freies Kapital." }
    end

    local factors = {}
    local share = C.BASE_SHARE

    local score = tonumber(input.score)
    if score then
        local factor = 1 + C.SCORE_SWING
            * clamp((score - C.SCORE_NEUTRAL) / C.SCORE_SPAN, -1, 1)
        share = share * factor
        factors[#factors + 1] = { name = "Score", value = factor,
            detail = string.format("%d Punkte", math.floor(score + 0.5)) }
    end

    local confidenceFactor = C.CONFIDENCE_FACTOR[input.confidence or "none"]
        or C.CONFIDENCE_FACTOR.none
    share = share * confidenceFactor
    factors[#factors + 1] = { name = "Datenlage", value = confidenceFactor,
        detail = tostring(input.confidence or "keine Daten") }

    if type(input.liquidityScore) == "number" then
        local factor = 1 + C.LIQUIDITY_SWING
            * clamp((input.liquidityScore - C.LIQUIDITY_NEUTRAL) / C.LIQUIDITY_SPAN, -1, 1)
        share = share * factor
        factors[#factors + 1] = { name = "Liquidität", value = factor,
            detail = string.format("Score %d", math.floor(input.liquidityScore + 0.5)) }
    else
        share = share * C.LIQUIDITY_UNKNOWN_FACTOR
        factors[#factors + 1] = { name = "Liquidität", value = C.LIQUIDITY_UNKNOWN_FACTOR,
            detail = "unbekannt" }
    end

    if type(input.volatility) == "number" and input.volatility > 0 then
        local capped = math.min(input.volatility, C.VOLATILITY_CAP)
        local factor = 1 - C.VOLATILITY_PENALTY * (capped / C.VOLATILITY_CAP)
        share = share * factor
        factors[#factors + 1] = { name = "Schwankung", value = factor,
            detail = string.format("%.0f %%", input.volatility * 100) }
    end

    if type(input.profitVelocity) == "number" and input.profitVelocity > 0 then
        local factor = 1 + C.VELOCITY_BONUS
            * saturate(input.profitVelocity, C.VELOCITY_HALF)
        share = share * factor
        factors[#factors + 1] = { name = "Profit Velocity", value = factor }
    end

    if type(input.futureDemandScore) == "number" then
        local factor = 1 + C.DEMAND_SWING
            * clamp((input.futureDemandScore - C.DEMAND_NEUTRAL) / C.DEMAND_SPAN, -1, 1)
        share = share * factor
        factors[#factors + 1] = { name = "Zukunftsnachfrage", value = factor }
    end

    if type(input.hypeScore) == "number" and input.hypeScore >= C.HYPE_HOT then
        local factor = 1 - C.HYPE_PENALTY
        share = share * factor
        factors[#factors + 1] = { name = "Hype", value = factor,
            detail = string.format("%d", math.floor(input.hypeScore + 0.5)) }
    end

    if input.supplyState == "glut" then
        share = share * C.SUPPLY_GLUT_FACTOR
        factors[#factors + 1] = { name = "Angebot", value = C.SUPPLY_GLUT_FACTOR,
            detail = "ungewöhnlich hoch" }
    elseif input.supplyState == "thin" then
        share = share * C.SUPPLY_THIN_FACTOR
        factors[#factors + 1] = { name = "Angebot", value = C.SUPPLY_THIN_FACTOR,
            detail = "dünn" }
    end

    local riskFactor = C.RISK_FACTOR[input.risk or "medium"] or 1
    if riskFactor ~= 1 then
        share = share * riskFactor
        factors[#factors + 1] = { name = "Risikostufe", value = riskFactor,
            detail = tostring(input.risk) }
    end

    share = clamp(share, C.MIN_SHARE, C.MAX_SHARE)

    local budget = investable * share
    local limitedBy = "Kapitalanteil"

    -- Exposure-Deckel. Sie begrenzen nicht den Anteil, sondern den absoluten
    -- Betrag: Was schon gebunden ist, zaehlt mit.
    local limits = config().EXPOSURE
    local exposureBase = tonumber(input.exposureBase) or investable
    local function capBy(dimension, current, name)
        local rule = limits[dimension:upper()]
        if not rule or not isPositiveNumber(exposureBase) then return end
        local room = rule.max * exposureBase - (current or 0)
        if room < budget then
            budget = math.max(room, 0)
            limitedBy = name
        end
    end
    capBy("item", input.itemExposure, "Exposure Item")
    capBy("type", input.typeExposure, "Exposure Chancenart")
    capBy("catalyst", input.catalystExposure, "Exposure Catalyst")
    capBy("phase", input.phaseExposure, "Exposure Phase")
    capBy("group", input.groupExposure, "Exposure Marktgruppe")

    local units = math.floor(budget / unitCost)

    -- ---------------------------------------------------------------------
    -- LIQUIDITAETSGRENZE (1.0.0-beta.10)
    --
    -- Bis beta.9 stand hier eine einzige Zeile: Das freie Gold deckelte das
    -- Budget, und das Budget rechnete in wirtschaftlichen Kosten. Fuer einen
    -- Craft, dessen Materialien alle im Beutel liegen, hiess das: 400 g
    -- Kapitalbedarf angemeldet, 0 g tatsaechlich noetig. Die Execution Engine
    -- kaufte nichts, und trotzdem war das Gold fuer alle weiteren Chancen
    -- dieser Route weg.
    --
    -- Getrennt gerechnet wird jetzt so:
    --   * unitCost (wirtschaftlich) begrenzt ueber Anteil und Exposure. Das
    --     bleibt richtig: Verbrauchte Materialien sind gebundenes Vermoegen,
    --     auch wenn kein Gold fliesst.
    --   * unitCashCost begrenzt ueber das freie Gold. Die ersten ownedUnits
    --     Durchgaenge kosten davon nichts.
    local unitCashCost = tonumber(input.unitCashCost)
    if not isPositiveNumber(unitCashCost) then unitCashCost = unitCost end
    local ownedUnits = math.max(math.floor(tonumber(input.ownedUnits) or 0), 0)

    if type(input.remainingCapital) == "number" then
        local cash = math.max(input.remainingCapital, 0)
        local affordable = ownedUnits + math.floor(cash / unitCashCost)
        if affordable < units then
            units = math.max(affordable, 0)
            limitedBy = "verfügbares Kapital"
        end
    end
    if type(input.maxUnits) == "number" and input.maxUnits >= 0
        and units > input.maxUnits then
        units = math.floor(input.maxUnits)
        limitedBy = "Marktangebot"
    end

    -- ---------------------------------------------------------------------
    -- NACHFRAGEGRENZE (1.1.0)
    --
    -- Bis 1.0 beantwortete diese Funktion nur die halbe Frage: "Wie viele
    -- Stueck kann ich mir leisten?" Die andere Haelfte fehlte vollstaendig:
    --
    --     "Wie viele Stueck nimmt der Markt bei mir ueberhaupt ab?"
    --
    -- Ohne sie wurde aus "das Gold reicht fuer 20" die Empfehlung "mach 20" -
    -- auch bei einem Item, von dem noch nie jemand eines gekauft hat. Die
    -- Grenze kommt aus Demand.lua und ist bei fehlenden Belegen genau ein
    -- Teststueck.
    --
    -- Sie steht bewusst NACH dem Marktangebot und VOR dem pauschalen
    -- Stueckzahl-Deckel: Was der Markt nicht hergibt, kann die Nachfrage nicht
    -- retten, und was die Nachfrage nicht traegt, soll nicht als
    -- "Stückzahl-Vorsicht" erklaert werden.
    if type(input.demandCapacity) == "number" and input.demandCapacity >= 0
        and units > input.demandCapacity then
        units = math.floor(input.demandCapacity)
        limitedBy = input.demandBasis or "Nachfrage"
    end
    -- Stueckzahl-Deckel. Er steht VOR dem Zeitbudget, damit "Zeitbudget" als
    -- Begruendung nur dann stehenbleibt, wenn die Zeit wirklich die engste
    -- Grenze war.
    local unitCap, unitCapReason = self:UnitCap(input)
    if unitCap and units > unitCap then
        units = unitCap
        limitedBy = unitCapReason
    end

    -- Eigene Mengenvorgabe (1.0.0-beta.6). Sie schlaegt Kapitalanteil und
    -- Deckel - beides sind Vorsichtsregeln, und wer sie uebergehen will, darf
    -- das. Sie schlaegt ausdruecklich NICHT die harten Grenzen: Was das freie
    -- Gold nicht hergibt, laesst sich auch auf Wunsch nicht kaufen, und was der
    -- Markt nicht anbietet, ebensowenig. Eine Vorgabe ist eine Entscheidung
    -- ueber Risiko, keine ueber die Wirklichkeit.
    if isPositiveNumber(input.forceUnits) then
        local wanted = math.floor(input.forceUnits)
        -- Bezahlbar heisst bezahlbar in GOLD: Was schon im Beutel liegt, muss
        -- niemand noch einmal kaufen.
        local affordable = ownedUnits + math.floor(
            math.max(tonumber(input.remainingCapital) or investable, 0) / unitCashCost)
        if type(input.maxUnits) == "number" and input.maxUnits >= 0 then
            affordable = math.min(affordable, math.floor(input.maxUnits))
        end
        if wanted <= affordable then
            units, limitedBy = wanted, "deine Vorgabe"
        else
            units = math.max(affordable, 0)
            limitedBy = "Vorgabe gekürzt: " .. limitedBy
        end
    end

    if type(input.timeBudgetMinutes) == "number"
        and isPositiveNumber(input.minutesPerUnit) then
        local byTime = math.floor(input.timeBudgetMinutes / input.minutesPerUnit)
        if byTime < units then
            units = math.max(byTime, 0)
            limitedBy = "Zeitbudget"
        end
    end
    if units < 1 then
        return nil, { reason = "Reicht nicht für ein Stück.", limitedBy = limitedBy,
            share = share, factors = factors }
    end

    return {
        units = units,
        unitCost = unitCost,
        -- capital ist der WIRTSCHAFTLICHE Einsatz: Er begrenzt das Exposure und
        -- steht fuer das, was in dieser Position gebunden ist.
        capital = math.floor(units * unitCost + 0.5),
        -- cashRequired ist das GOLD, das dafuer fliessen muss. Bei einer
        -- Position ohne eigenen Bestand sind beide gleich; bei einem Craft aus
        -- vorhandenem Material ist cashRequired kleiner - und nur diese Zahl
        -- darf das freie Gold der naechsten Chance verringern.
        cashRequired = math.floor(
            math.max(units - ownedUnits, 0) * unitCashCost + 0.5),
        ownedUnits = ownedUnits,
        share = share,
        budget = math.floor(budget + 0.5),
        limitedBy = limitedBy,
        factors = factors,
    }
end

-- ---------------------------------------------------------------------------
-- CAPITAL ALLOCATOR
--
-- Nicht "bester Score bekommt alles". Der Reihe nach wird jede Chance mit dem
-- gerechnet, was zu diesem Zeitpunkt noch frei ist - und jede Zuteilung
-- erhoeht das Exposure, das die naechste Zuteilung begrenzt. Dadurch verteilt
-- sich Kapital von selbst, ohne eine Diversifikationsquote zu erfinden.
--
-- Die Rangfolge ist der Opportunity Score, angehoben um die Profit Velocity,
-- WO SIE BEKANNT IST. Ohne eigene Verkaufsdaten bleibt es beim Score - eine
-- unbekannte Velocity darf eine Chance weder bevorzugen noch bestrafen.
-- ---------------------------------------------------------------------------

-- Wie viele Stueck nimmt der eigene Markt je Woche auf? Gefragt wird nach dem
-- VERKAUFSITEM: Wie schnell Urerde weggeht, sagt nichts darueber, wie viele
-- Urmacht jemand loswird.
function Capital:AbsorptionFor(opportunity)
    if not GCP.Ledger or type(opportunity) ~= "table" then return nil end
    local itemID = opportunity.saleItemID or opportunity.itemID
    if not isItemID(itemID) then return nil end
    return GCP.Ledger:AbsorptionPerWeek(itemID)
end

function Capital:RankValue(opportunity)
    local A = config().ALLOCATOR
    local score = opportunity.opportunityScore or 0
    if type(opportunity.profitVelocity) == "number" and opportunity.profitVelocity > 0 then
        score = score * (1 + A.VELOCITY_WEIGHT
            * saturate(opportunity.profitVelocity, A.VELOCITY_HALF))
    end
    return score
end

function Capital:Allocate(opportunities, options)
    if type(opportunities) ~= "table" then opportunities = {} end
    if type(options) ~= "table" then options = {} end
    local A = config().ALLOCATOR
    local snapshot = options.snapshot or self:GetSnapshot()

    local investable = options.capital
    if type(investable) ~= "number" then investable = snapshot.availableGold end
    investable = math.max(math.floor(investable), 0)

    local exposureBase = snapshot.exposureBase
    if not isPositiveNumber(exposureBase) then
        exposureBase = investable + snapshot.investedCapital
    end
    if not isPositiveNumber(exposureBase) then exposureBase = investable end

    -- Laufende Exposure-Summen: Startwert ist das, was schon gebunden ist.
    local running = { item = {}, type = {}, catalyst = {}, phase = {}, group = {} }
    for dimension, bucket in pairs(snapshot.exposure or {}) do
        if running[dimension] then
            for key, entry in pairs(bucket) do
                -- Positionen ohne bekannte Herkunft landen im Eimer "unknown".
                -- Der darf keine Chancenart blockieren: Dass frueher einmal
                -- etwas gekauft wurde, sagt nichts darueber, ob ein Craft heute
                -- zu viel Kapital in eine Richtung legt.
                if not (dimension == "type" and key == "unknown") then
                    running[dimension][key] = entry.value
                end
            end
        end
    end

    local candidates = {}
    for _, opportunity in ipairs(opportunities or {}) do
        -- Ein Eintrag, der keine Chance ist, ist keine Chance. Er faellt hier
        -- heraus statt weiter unten mit einem Absturz aufzufallen.
        local allowed = type(opportunity) == "table"
        if options.types and next(options.types) ~= nil then
            allowed = options.types[opportunity.type] and true or false
        end
        if allowed and options.minScore and (opportunity.opportunityScore or 0) < options.minScore then
            allowed = false
        end
        if allowed and isPositiveNumber(opportunity.cost) then
            candidates[#candidates + 1] = opportunity
        end
    end
    table.sort(candidates, function(a, b)
        local av, bv = Capital:RankValue(a), Capital:RankValue(b)
        if av ~= bv then return av > bv end
        return tostring(a.key) < tostring(b.key)
    end)

    local allocations = {}
    local remaining = investable
    local typeCount = {}
    local skipped = {}
    local timeLeft = options.timeBudgetMinutes

    -- ---------------------------------------------------------------------
    -- BEREITS BEANSPRUCHTER BESTAND (1.0.0-beta.10)
    --
    -- ownedRuns an der Chance sagt, wie viele Durchgaenge der eigene Bestand
    -- deckt - gerechnet, als waere diese Chance die einzige. Zwei Crafts, die
    -- dasselbe Urfeuer brauchen, koennen es aber nicht beide umsonst haben.
    --
    -- Die Execution Engine loest das sauber ueber einen laufenden virtuellen
    -- Bestand; sie laeuft aber erst NACH der Zuteilung. Hier gilt deshalb die
    -- vorsichtige Regel: Wer als Zweiter auf dieselbe Zutat zugreift, rechnet
    -- so, als muesste er alles kaufen.
    --
    -- Der Fehler geht damit in die sichere Richtung - es wird eher zu viel
    -- Gold reserviert als zu wenig. Zu wenig waere ein Plan, der mittendrin
    -- nicht mehr bezahlbar ist.
    local claimedStock = {}
    local function stockCredit(opportunity)
        local owned = tonumber(opportunity.ownedRuns) or 0
        if owned <= 0 then return 0 end
        local inputs = opportunity.execution and opportunity.execution.inputs
        if type(inputs) ~= "table" then return owned end
        for _, input in ipairs(inputs) do
            if input.itemID and claimedStock[input.itemID] then return 0 end
        end
        return owned
    end
    local function claimStock(opportunity)
        local inputs = opportunity.execution and opportunity.execution.inputs
        if type(inputs) ~= "table" then return end
        for _, input in ipairs(inputs) do
            if input.itemID then claimedStock[input.itemID] = true end
        end
    end

    for _, opportunity in ipairs(candidates) do
        if #allocations >= A.MAX_ALLOCATIONS or remaining < A.MIN_ALLOCATION then
            break
        end
        local kind = opportunity.type or "unknown"
        local decay = A.TYPE_DECAY ^ (typeCount[kind] or 0)
        local catalystKey = opportunity.catalystIDs and opportunity.catalystIDs[1] or nil
        local groupKey = marketGroup(opportunity.saleItemID or opportunity.itemID)

        -- NACHFRAGE-GATE (1.1.0). Vor der Frage "wie viel Gold" steht seit
        -- 1.1 die Frage "gibt es ueberhaupt Belege". Eine spekulative Chance
        -- bekommt kein Kapital - sie bleibt im Chancen-Tab sichtbar, aber sie
        -- wird nicht zur Handlungsaufforderung.
        local assessment = GCP.Actionability
            and GCP.Actionability:Assess(opportunity, { investable = investable }) or nil
        local class = assessment and assessment.class or nil
        -- PENDING zaehlt hier wie gesperrt: Das Kapital steckt schon in dieser
        -- Chance, es ein zweites Mal zu verteilen waere doppelt gerechnet.
        local blocked = (class == "BLOCKED" or class == "SPECULATIVE"
            or class == "PENDING")
        if blocked then
            skipped[#skipped + 1] = {
                key = opportunity.key, title = opportunity.title,
                reason = assessment.pendingReason or assessment.speculativeReason
                    or assessment.blockers[1] or "keine belastbaren Nachfragebelege",
                limitedBy = GCP.Actionability:ClassLabel(class),
            }
        end

        -- KEIN SPRUNG. Hier stand bis 1.1.0-beta.4 ein "goto continue" auf ein
        -- Label am Schleifenende - Lua 5.2. WoW Classic laeuft auf Lua 5.1 und
        -- kennt weder goto noch Labels: Die Datei liess sich im Spiel nicht
        -- uebersetzen, GCP.Capital blieb nil, und alles, was daran haengt, fiel
        -- um - die Zentrale zeigte nur Striche, die Routenplanung brach ab.
        --
        -- Gruen war trotzdem alles: fengari, die Lua-Umgebung der Tests, ist
        -- 5.3 und schluckt goto klaglos. Deshalb prueft tests/validate.mjs die
        -- Addon-Dateien jetzt zusaetzlich auf 5.2-Syntax.
        --
        -- Ohne Sprung: Eine gesperrte Chance bekommt keine Groesse. Weil sizing
        -- und why dann nil bleiben, laeuft der Rest der Schleife von selbst ins
        -- Leere - die Annahmebedingung unten ist falsch, und "elseif why" auch.
        local sizing, why
        if not blocked then
            sizing, why = self:SizePosition({
                -- Wirtschaftliche Kosten fuer Anteil, Exposure und ROI ...
                unitCost = opportunity.cost,
                -- ... die Nachfragegrenze aus Demand.lua ...
                demandCapacity = assessment and assessment.maxUnits or nil,
                demandBasis = assessment and assessment.class == "TEST"
                    and "Markttest" or "deine Absatzhistorie",
                -- ... und getrennt davon das Gold, das wirklich fliessen muss.
                -- Ohne die Felder (aeltere Aufrufer, Farmbloecke) sind beide
                -- gleich, und dann rechnet SizePosition wie vor 1.0.0-beta.10.
                unitCashCost = opportunity.cashRequired,
                ownedUnits = stockCredit(opportunity),
                absorptionPerWeek = self:AbsorptionFor(opportunity),
                investable = investable * decay,
                remainingCapital = remaining,
                exposureBase = exposureBase,
                score = opportunity.opportunityScore,
                confidence = opportunity.confidence,
                liquidityScore = opportunity.liquidityScore,
                liquidityConfidence = opportunity.liquidityConfidence,
                volatility = opportunity.volatility,
                profitVelocity = opportunity.profitVelocity,
                futureDemandScore = opportunity.futureDemandScore,
                hypeScore = opportunity.hypeScore,
                supplyState = opportunity.supplyState,
                risk = options.risk,
                maxUnits = options.respectFeasible ~= false and opportunity.maxUnits or nil,
                -- Vom Nutzer gewaehlte Stueckzahl fuer genau diese Chance.
                forceUnits = options.unitLimits and options.unitLimits[opportunity.key] or nil,
                timeBudgetMinutes = timeLeft,
                minutesPerUnit = opportunity.minutesPerUnit,
                itemExposure = running.item[opportunity.itemID],
                typeExposure = running.type[kind],
                catalystExposure = catalystKey and running.catalyst[catalystKey] or nil,
                phaseExposure = opportunity.phase and running.phase[opportunity.phase] or nil,
                groupExposure = groupKey and running.group[groupKey] or nil,
            })
        end

        -- Die Annahmebedingung fragt nach GOLD, nicht nach wirtschaftlichem
        -- Einsatz: Eine Zuteilung, die 400 g Material verbraucht und 0 g
        -- kostet, scheitert nicht daran, dass gerade nur 100 g frei sind.
        -- MIN_ALLOCATION bleibt am wirtschaftlichen Wert - sie soll
        -- Kleinstpositionen aussortieren, und eine Position aus eigenem
        -- Material ist nicht klein, nur weil sie nichts kostet.
        if sizing and sizing.capital >= A.MIN_ALLOCATION
            and (sizing.cashRequired or sizing.capital) <= remaining then
            local allocation = {
                opportunity = opportunity,
                key = opportunity.key,
                type = kind,
                itemID = opportunity.itemID,
                title = opportunity.title,
                units = sizing.units,
                unitCost = sizing.unitCost,
                capital = sizing.capital,
                cashRequired = sizing.cashRequired or sizing.capital,
                ownedUnits = sizing.ownedUnits,
                expectedProfit = math.floor((opportunity.expectedProfit or 0) * sizing.units + 0.5),
                share = sizing.share,
                limitedBy = sizing.limitedBy,
                factors = sizing.factors,
                confidence = opportunity.confidence,
                -- Die Einordnung wandert mit: Die Startseite muss "bewaehrt"
                -- von "Markttest" unterscheiden koennen, ohne sie noch einmal
                -- zu rechnen.
                actionability = assessment,
            }
            allocations[#allocations + 1] = allocation
            -- Freies Gold sinkt um das, was wirklich ausgegeben wird ...
            remaining = remaining - allocation.cashRequired
            -- ... und der beanspruchte Bestand steht der naechsten Chance
            -- nicht mehr kostenlos zur Verfuegung.
            if (allocation.ownedUnits or 0) > 0 then claimStock(opportunity) end
            typeCount[kind] = (typeCount[kind] or 0) + 1
            running.item[opportunity.itemID] =
                (running.item[opportunity.itemID] or 0) + sizing.capital
            running.type[kind] = (running.type[kind] or 0) + sizing.capital
            if catalystKey then
                running.catalyst[catalystKey] =
                    (running.catalyst[catalystKey] or 0) + sizing.capital
            end
            if opportunity.phase then
                running.phase[opportunity.phase] =
                    (running.phase[opportunity.phase] or 0) + sizing.capital
            end
            if groupKey then
                running.group[groupKey] = (running.group[groupKey] or 0) + sizing.capital
            end
            if type(timeLeft) == "number" and isPositiveNumber(opportunity.minutesPerUnit) then
                timeLeft = math.max(timeLeft - sizing.units * opportunity.minutesPerUnit, 0)
            end
        elseif why then
            skipped[#skipped + 1] = {
                key = opportunity.key, title = opportunity.title,
                reason = why.reason, limitedBy = why.limitedBy,
            }
        end
    end

    -- invested ist der wirtschaftliche Einsatz, cashNeeded das Gold. Beide
    -- Zahlen stehen nebeneinander, weil sie verschiedene Fragen beantworten:
    -- "Wie viel Vermoegen liegt jetzt in Ware?" und "Wie viel Gold brauche ich
    -- dafuer in der Tasche?"
    local invested, expected, cashNeeded = 0, 0, 0
    for _, allocation in ipairs(allocations) do
        invested = invested + allocation.capital
        cashNeeded = cashNeeded + (allocation.cashRequired or allocation.capital)
        expected = expected + allocation.expectedProfit
    end

    -- Wenn nichts zugeteilt wurde, obwohl es Kandidaten gab, ist das keine
    -- Ratlosigkeit, sondern ein Ergebnis. Der haeufigste Grund wird benannt -
    -- eine leere Liste ohne Begruendung waere die schlechteste Antwort.
    local blocker = nil
    if #allocations == 0 and #skipped > 0 then
        local reasons = {}
        for _, entry in ipairs(skipped) do
            local key = entry.limitedBy or entry.reason or "unbekannt"
            reasons[key] = (reasons[key] or 0) + 1
        end
        local bestCount = 0
        for key, count in pairs(reasons) do
            if count > bestCount then blocker, bestCount = key, count end
        end
    end

    return {
        allocations = allocations,
        skipped = skipped,
        blocker = blocker,
        investable = investable,
        invested = invested,
        cashRequired = cashNeeded,
        -- Was am Ende noch frei ist, misst sich am ausgegebenen GOLD.
        unused = investable - cashNeeded,
        reserved = snapshot.reservedGold,
        exposureBase = exposureBase,
        expectedProfit = expected,
        snapshot = snapshot,
    }
end

-- Die Zuteilung in Worten. Jede Allokation muss erklaerbar sein - das ist
-- keine Kosmetik, sondern die Bedingung dafuer, dass jemand ihr folgen kann.
function Capital:ExplainAllocation(allocation)
    local lines = {}
    if type(allocation) ~= "table" then return lines end
    -- Eine Allokation ohne Zahlen laesst sich nicht erklaeren; eine leere
    -- Antwort ist richtig, ein Absturz waere es nicht.
    if type(allocation.units) ~= "number" or type(allocation.capital) ~= "number"
        or type(allocation.unitCost) ~= "number"
        or type(allocation.expectedProfit) ~= "number" then
        return lines
    end
    local money = function(copper) return GCP.Prices:FormatMoney(copper) end
    lines[#lines + 1] = string.format("%d × %s", allocation.units,
        allocation.title or ("Item " .. tostring(allocation.itemID)))
    lines[#lines + 1] = string.format("Kapital: %s (%s je Durchgang)",
        money(allocation.capital), money(allocation.unitCost))
    -- Der Unterschied wird nur dann benannt, wenn es einen gibt. "Davon aus
    -- eigenem Bestand: 0" an jeder Zeile waere Rauschen.
    if type(allocation.cashRequired) == "number"
        and allocation.cashRequired < allocation.capital then
        lines[#lines + 1] = string.format(
            "Davon tatsächlich auszugeben: %s – der Rest steckt in Material, "
            .. "das du schon hast (%d Durchgang/Durchgänge).",
            money(allocation.cashRequired), allocation.ownedUnits or 0)
    end
    lines[#lines + 1] = string.format("Theoretisches Potenzial: %s",
        money(allocation.expectedProfit))
    lines[#lines + 1] = string.format("Anteil am investierbaren Kapital: %.1f %%",
        (allocation.share or 0) * 100)
    if allocation.limitedBy then
        lines[#lines + 1] = "Begrenzt durch: " .. allocation.limitedBy
    end
    for _, factor in ipairs(allocation.factors or {}) do
        local detail = factor.detail and (" (" .. factor.detail .. ")") or ""
        lines[#lines + 1] = string.format("  %s%s: ×%.2f", factor.name, detail, factor.value)
    end
    return lines
end

-- ---------------------------------------------------------------------------
-- Kaltstart-Texte. Ohne Daten steht hier ein Satz, keine Null.
-- ---------------------------------------------------------------------------

function Capital:SummaryText(snapshot)
    if type(snapshot) ~= "table" or type(snapshot.openPositions) ~= "number" then
        snapshot = self:GetSnapshot()
    end
    local Prices = GCP.Prices
    if snapshot.openPositions == 0 then
        return string.format("%s frei von %s · noch keine offenen Positionen.",
            Prices:FormatGold(snapshot.availableGold),
            Prices:FormatGold(snapshot.currentGold))
    end
    local invested = snapshot.investedCapital > 0
        and Prices:FormatGold(snapshot.investedCapital)
        or "unbekannter Einstand"
    return string.format("%s frei · %s in %d Position(en) · Reserve %s",
        Prices:FormatGold(snapshot.availableGold), invested,
        snapshot.openPositions, Prices:FormatGold(snapshot.reservedGold))
end
