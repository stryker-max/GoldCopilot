local addonName, GCP = ...

GCP.Flips = {}
local Flips = GCP.Flips

local GetItemInfoCompat = (C_Item and C_Item.GetItemInfo) or GetItemInfo

local function itemName(itemID)
    local name = GetItemInfoCompat(itemID)
    return name
end

-- Mote-Rechnung je Element. Kombinieren ist eine Einbahnstrasse (10 Motes ->
-- 1 Ur-Partikel), deshalb gibt es zwei Fragen: Lohnt es, eigene Motes zu
-- kombinieren statt einzeln zu verkaufen? Und lohnt es, Motes im AH zu kaufen,
-- nur um das Ur-Partikel zu verkaufen?
function Flips:BuildMoteRows(inventory)
    local C = GCP.Constants
    local Prices = GCP.Prices
    local rows = {}
    for _, pair in ipairs(C.PRIMALS) do
        local motePrice = Prices:GetPlanningPrice(pair.mote)
        local primalPrice = Prices:GetPlanningPrice(pair.primal)
        if motePrice and primalPrice then
            local netPrimal = Prices:NetAuction(primalPrice)
            local netMotesEach = Prices:NetAuction(motePrice)
            local combineDelta = netPrimal - C.MOTES_PER_PRIMAL * netMotesEach
            local buyProfit = netPrimal - C.MOTES_PER_PRIMAL * motePrice
            local ownedMotes = 0
            local invEntry = inventory and inventory[pair.mote]
            if invEntry then ownedMotes = invEntry.count end
            rows[#rows + 1] = {
                kind = "mote",
                moteID = pair.mote,
                primalID = pair.primal,
                name = itemName(pair.primal),
                icon = select(10, GetItemInfoCompat(pair.primal)),
                motePrice = motePrice,
                primalPrice = primalPrice,
                combineDelta = combineDelta,
                buyProfit = buyProfit,
                ownedMotes = ownedMotes,
                ownedCombines = math.floor(ownedMotes / C.MOTES_PER_PRIMAL),
            }
        end
    end
    table.sort(rows, function(a, b) return a.buyProfit > b.buyProfit end)
    return rows
end

-- Essenz-Umwandlung braucht Verzauberkunst und geht in beide Richtungen:
-- 3 niedere <-> 1 hohe. Angezeigt wird der Kauf-Flip je Richtung.
function Flips:BuildEssenceRows(inventory)
    local C = GCP.Constants
    local Prices = GCP.Prices
    local rows = {}
    for _, pair in ipairs(C.ESSENCES) do
        local lesserPrice = Prices:GetPlanningPrice(pair.lesser)
        local greaterPrice = Prices:GetPlanningPrice(pair.greater)
        if lesserPrice and greaterPrice then
            local toGreater = Prices:NetAuction(greaterPrice) - C.ESSENCES_PER_GREATER * lesserPrice
            local toLesser = C.ESSENCES_PER_GREATER * Prices:NetAuction(lesserPrice) - greaterPrice
            local bestProfit, direction
            if toGreater >= toLesser then
                bestProfit, direction = toGreater, "up"
            else
                bestProfit, direction = toLesser, "down"
            end
            local ownedLesser = inventory and inventory[pair.lesser] and inventory[pair.lesser].count or 0
            local ownedGreater = inventory and inventory[pair.greater] and inventory[pair.greater].count or 0
            rows[#rows + 1] = {
                kind = "essence",
                lesserID = pair.lesser,
                greaterID = pair.greater,
                name = itemName(pair.greater),
                icon = select(10, GetItemInfoCompat(pair.greater)),
                lesserPrice = lesserPrice,
                greaterPrice = greaterPrice,
                profit = bestProfit,
                direction = direction,
                ownedLesser = ownedLesser,
                ownedGreater = ownedGreater,
            }
        end
    end
    table.sort(rows, function(a, b) return a.profit > b.profit end)
    return rows
end

function Flips:Build()
    local inventory = GCP.Inventory:ScanAccount()
    return {
        motes = self:BuildMoteRows(inventory),
        essences = self:BuildEssenceRows(inventory),
    }
end
