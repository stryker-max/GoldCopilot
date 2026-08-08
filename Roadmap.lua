local addonName, GCP = ...

GCP.Roadmap = {}
local Roadmap = GCP.Roadmap

local GetItemInfoCompat = (C_Item and C_Item.GetItemInfo) or GetItemInfo

local function knowsSpell(spellID)
    if type(IsPlayerSpell) == "function" then
        return IsPlayerSpell(spellID)
    end
    if type(IsSpellKnown) == "function" then
        return IsSpellKnown(spellID)
    end
    return false
end

-- Restlicher Cooldown in Sekunden; 0 heisst bereit. Der Anniversary-Client
-- kennt C_Spell, aeltere Classic-Clients nur GetSpellCooldown - und beide
-- melden auch den globalen Cooldown, der hier nicht interessiert.
local function cooldownRemaining(spellID)
    local start, duration
    if C_Spell and C_Spell.GetSpellCooldown then
        local info = C_Spell.GetSpellCooldown(spellID)
        if info then
            start, duration = info.startTime, info.duration
        end
    elseif type(GetSpellCooldown) == "function" then
        start, duration = GetSpellCooldown(spellID)
    end
    if not start or not duration or start == 0 or duration == 0 then
        return 0
    end
    local remaining = (start + duration) - GetTime()
    if remaining < 3 then
        return 0
    end
    return remaining
end

local function formatHours(seconds)
    local hours = seconds / 3600
    if hours >= 1 then
        return string.format("%.0f Std.", math.ceil(hours))
    end
    return string.format("%.0f Min.", math.max(1, math.ceil(seconds / 60)))
end

local function spellLabel(spellID, productID)
    local productName = GetItemInfoCompat(productID)
    if productName then return productName end
    if C_Spell and C_Spell.GetSpellName then
        return C_Spell.GetSpellName(spellID)
    end
    if type(GetSpellInfo) == "function" then
        local name = GetSpellInfo(spellID)
        return name
    end
    return "Rezept " .. spellID
end

-- Berufs-Cooldowns des Charakters mit aktueller Gewinnrechnung: Erloes des
-- Produkts nach AH-Abzug minus Marktpreis der Zutaten.
function Roadmap:BuildCooldownEntries()
    local C = GCP.Constants
    local Prices = GCP.Prices
    local entries = {}
    for _, craft in ipairs(C.CRAFT_COOLDOWNS) do
        if knowsSpell(craft.spell) then
            local productPrice = Prices:GetMarketPrice(craft.product)
            if productPrice then
                local matCost = 0
                local matsKnown = true
                for _, mat in ipairs(craft.mats) do
                    local price = Prices:GetMarketPrice(mat[1])
                    if not price then
                        matsKnown = false
                        break
                    end
                    matCost = matCost + price * mat[2]
                end
                if matsKnown then
                    local profit = Prices:NetAuction(productPrice) - matCost
                    if profit > 0 then
                        local remaining = craft.cooldown and cooldownRemaining(craft.spell) or 0
                        local label = spellLabel(craft.spell, craft.product)
                        local text
                        if remaining > 0 then
                            text = string.format("%s: wieder bereit in %s (%s Gewinn)",
                                label, formatHours(remaining), Prices:FormatGold(profit))
                        elseif craft.cooldown then
                            text = string.format("%s herstellen (Cooldown bereit, %s Gewinn)",
                                label, Prices:FormatGold(profit))
                        else
                            text = string.format("%s herstellen (ohne Cooldown, %s Gewinn je Stück)",
                                label, Prices:FormatGold(profit))
                        end
                        entries[#entries + 1] = {
                            key = "cd:" .. craft.spell,
                            category = "Cooldowns & Crafts",
                            text = text,
                            value = profit,
                            ready = remaining == 0,
                        }
                    end
                end
            end
        end
    end
    table.sort(entries, function(a, b)
        if a.ready ~= b.ready then return a.ready end
        return a.value > b.value
    end)
    return entries
end

function Roadmap:BuildSellEntries(report)
    local Prices = GCP.Prices
    local entries = {}
    for index = 1, math.min(3, #report.rows) do
        local row = report.rows[index]
        if row.channel == "AH" and row.totalValue > 0 then
            entries[#entries + 1] = {
                key = "sell:" .. row.itemID,
                category = "Verkaufen",
                text = string.format("%s ×%d ins AH stellen (≈ %s)",
                    row.name or ("Item " .. row.itemID), row.count,
                    Prices:FormatGold(row.totalValue)),
                value = row.totalValue,
            }
        end
    end
    return entries
end

function Roadmap:BuildFlipEntries(flips)
    local C = GCP.Constants
    local Prices = GCP.Prices
    local entries = {}
    for _, row in ipairs(flips.motes) do
        if row.ownedCombines > 0 and row.combineDelta > 0 then
            entries[#entries + 1] = {
                key = "flip:combine:" .. row.primalID,
                category = "Flips",
                text = string.format("%d×%d Motes zu %s kombinieren (+%s gegenüber Einzelverkauf)",
                    row.ownedCombines, C.MOTES_PER_PRIMAL, row.name or "Ur-Partikel",
                    Prices:FormatGold(row.combineDelta * row.ownedCombines)),
                value = row.combineDelta * row.ownedCombines,
            }
        elseif row.buyProfit > 0 then
            entries[#entries + 1] = {
                key = "flip:buy:" .. row.primalID,
                category = "Flips",
                text = string.format("Motes kaufen und %s verkaufen (%s Gewinn je Stück)",
                    row.name or "Ur-Partikel", Prices:FormatGold(row.buyProfit)),
                value = row.buyProfit,
            }
        end
    end
    for _, row in ipairs(flips.essences) do
        if row.profit > 0 then
            local text
            if row.direction == "up" then
                text = string.format("3× niedere zu %s wandeln (%s Gewinn, Verzauberkunst)",
                    row.name or "Essenz", Prices:FormatGold(row.profit))
            else
                text = string.format("%s in 3 niedere aufteilen (%s Gewinn, Verzauberkunst)",
                    row.name or "Essenz", Prices:FormatGold(row.profit))
            end
            entries[#entries + 1] = {
                key = "flip:essence:" .. row.greaterID,
                category = "Flips",
                text = text,
                value = row.profit,
            }
        end
    end
    table.sort(entries, function(a, b) return a.value > b.value end)
    while #entries > 3 do
        table.remove(entries)
    end
    return entries
end

function Roadmap:BuildFarmEntries()
    local C = GCP.Constants
    local Prices = GCP.Prices
    local ranked = {}
    for _, farm in ipairs(C.FARM_CATALOG) do
        local price = Prices:GetMarketPrice(farm.item)
        if price then
            local name = GetItemInfoCompat(farm.item)
            ranked[#ranked + 1] = {
                item = farm.item,
                name = name,
                zone = farm.zone,
                stack = farm.stack,
                stackValue = price * farm.stack,
                unitPrice = price,
            }
        end
    end
    table.sort(ranked, function(a, b) return a.stackValue > b.stackValue end)
    local entries = {}
    for index = 1, math.min(3, #ranked) do
        local farm = ranked[index]
        local amount
        if farm.stack > 1 then
            amount = string.format("≈ %s je Stapel", GCP.Prices:FormatGold(farm.stackValue))
        else
            amount = string.format("≈ %s je Stück", GCP.Prices:FormatGold(farm.unitPrice))
        end
        entries[#entries + 1] = {
            key = "farm:" .. farm.item,
            category = "Farm-Tipp des Tages",
            text = string.format("%s farmen – %s (%s)",
                farm.name or ("Item " .. farm.item), farm.zone, amount),
            value = farm.stackValue,
        }
    end
    return entries
end

-- Der Tagesplan: erst die Preisbasis, dann Cooldowns, Verkaeufe, Flips und
-- Farm-Tipps. Abhaken landet in den SavedVariables und ueberlebt Reloads;
-- um Mitternacht beginnt der Plan leer.
function Roadmap:Generate()
    GCP:ResetRoadmapIfNewDay()
    local Prices = GCP.Prices
    local entries = {}

    -- Netherweave Cloth als Referenz dafuer, wie alt der letzte Scan ist: Es
    -- ist das meistgehandelte Gut und in praktisch jedem Scan enthalten.
    local scanAge = Prices:GetScanAgeDays(21877)
    if scanAge == nil or scanAge >= 1 then
        entries[#entries + 1] = {
            key = "scan",
            category = "Preisbasis",
            text = scanAge == nil
                and "Im AH einen vollständigen Auctionator-Scan starten (noch keine Preisdaten)"
                or string.format("Auctionator-Scan auffrischen (letzter Scan vor %d Tag(en))", scanAge),
            value = nil,
        }
    end

    local cooldowns = self:BuildCooldownEntries()
    for _, entry in ipairs(cooldowns) do entries[#entries + 1] = entry end

    local report = GCP.Advisor:BuildReport("account", "all")
    for _, entry in ipairs(self:BuildSellEntries(report)) do entries[#entries + 1] = entry end

    local flips = GCP.Flips:Build()
    for _, entry in ipairs(self:BuildFlipEntries(flips)) do entries[#entries + 1] = entry end

    for _, entry in ipairs(self:BuildFarmEntries()) do entries[#entries + 1] = entry end

    local checked = GCP.db.roadmap.checked
    local doneValue, openValue = 0, 0
    for _, entry in ipairs(entries) do
        entry.done = checked[entry.key] == true
        if entry.value then
            if entry.done then
                doneValue = doneValue + entry.value
            else
                openValue = openValue + entry.value
            end
        end
    end

    return {
        entries = entries,
        report = report,
        doneValue = doneValue,
        openValue = openValue,
    }
end

function Roadmap:SetChecked(key, checked)
    GCP:ResetRoadmapIfNewDay()
    GCP.db.roadmap.checked[key] = checked and true or nil
end

-- Golddifferenz zum aeltesten Eintrag der letzten 7 Tage, fuer die Kopfzeile.
function Roadmap:GetGoldTrend()
    local history = GCP.db and GCP.db.goldHistory
    if not history then return nil end
    local today = GCP:Today()
    local current = history[today]
    if not current then return nil end
    local baseline, baselineDay
    for offset = 7, 1, -1 do
        local day = date("%Y-%m-%d", time() - offset * 86400)
        if history[day] then
            baseline, baselineDay = history[day], day
            break
        end
    end
    if not baseline then return nil end
    return current - baseline, baselineDay
end
