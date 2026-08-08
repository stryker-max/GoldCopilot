local addonName, GCP = ...

GCP.Roadmap = {}
local Roadmap = GCP.Roadmap

local GetItemInfoCompat = (C_Item and C_Item.GetItemInfo) or GetItemInfo

-- ---------------------------------------------------------------------------
-- Client-Abfragen, jeweils mit Fallback fuer aeltere API-Generationen
-- ---------------------------------------------------------------------------

local function knowsSpell(spellID)
    if type(IsPlayerSpell) == "function" then
        return IsPlayerSpell(spellID)
    end
    if type(IsSpellKnown) == "function" then
        return IsSpellKnown(spellID)
    end
    return false
end

-- Restlicher Cooldown in Sekunden; 0 heisst bereit. Beide API-Generationen
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

-- true/false, oder nil wenn der Client keine Abfrage anbietet.
local function questCompleted(questID)
    if C_QuestLog and C_QuestLog.IsQuestFlaggedCompleted then
        return C_QuestLog.IsQuestFlaggedCompleted(questID) == true
    end
    if type(IsQuestFlaggedCompleted) == "function" then
        return IsQuestFlaggedCompleted(questID) == true
    end
    return nil
end

local function playerLevel()
    if type(UnitLevel) == "function" then
        return UnitLevel("player") or 0
    end
    return 0
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

local function minValue()
    local options = GCP.db and GCP.db.options
    return (options and options.minRoadmapValue) or GCP.Constants.MIN_ROADMAP_VALUE
end

-- ---------------------------------------------------------------------------
-- Baselines: Bestaende beim ersten Blick auf den Tagesplan. An der Differenz
-- erkennt der Plan spaeter von selbst, dass eine Aufgabe erledigt wurde -
-- verkauft, kombiniert, gefarmt, gecraftet oder Cooldown benutzt.
-- ---------------------------------------------------------------------------

local function ensureBaseline(key, value)
    local baseline = GCP.db.roadmap.baseline
    if baseline[key] == nil then
        baseline[key] = value
    end
    return baseline[key]
end

local function getBaseline(key)
    return GCP.db.roadmap.baseline[key]
end

local function sellableCount(entry)
    if not entry then return 0 end
    local inAuctions = (entry.sources and entry.sources["Auktionen"]) or 0
    return entry.count - inAuctions
end

-- ---------------------------------------------------------------------------
-- Die einzelnen Abschnitte des Tagesplans
-- ---------------------------------------------------------------------------

function Roadmap:BuildDailyEntries()
    local C = GCP.Constants
    local Prices = GCP.Prices
    local entries = {}
    if playerLevel() < 70 then
        return entries
    end
    for _, daily in ipairs(C.DAILY_QUESTS) do
        -- Ohne abgeschlossene Vorquest ist die Daily gar nicht annehmbar;
        -- kann der Client das nicht beantworten (nil), lieber anzeigen.
        local unlocked = daily.pre == nil or questCompleted(daily.pre) ~= false
        if unlocked then
            local doneToday = questCompleted(daily.quest) == true
            entries[#entries + 1] = {
                key = "daily:" .. daily.quest,
                category = "Daily-Quests",
                text = string.format("%s – %s (%s)",
                    daily.name, daily.zone, Prices:FormatGold(daily.gold)),
                value = daily.gold,
                autoDone = doneToday or nil,
            }
        end
    end
    return entries
end

function Roadmap:BuildCooldownEntries()
    local C = GCP.Constants
    local Prices = GCP.Prices
    local entries = {}
    local threshold = minValue()
    for _, craft in ipairs(C.CRAFT_COOLDOWNS) do
        if knowsSpell(craft.spell) then
            local productPrice = Prices:GetPlanningPrice(craft.product)
            if productPrice then
                local matCost = 0
                local matsKnown = true
                for _, mat in ipairs(craft.mats) do
                    local price = Prices:GetPlanningPrice(mat[1])
                    if not price then
                        matsKnown = false
                        break
                    end
                    matCost = matCost + price * mat[2]
                end
                local profit = matsKnown and (Prices:NetAuction(productPrice) - matCost) or 0
                if matsKnown and profit >= threshold then
                    local key = "cd:" .. craft.spell
                    local remaining = craft.cooldown and cooldownRemaining(craft.spell) or 0
                    local label = spellLabel(craft.spell, craft.product)
                    local autoDone = nil
                    if craft.cooldown then
                        if remaining == 0 then
                            ensureBaseline("ready:" .. key, true)
                        elseif getBaseline("ready:" .. key) then
                            -- Heute als bereit gesehen, jetzt auf Cooldown:
                            -- der Transmute wurde benutzt.
                            autoDone = true
                        end
                    end
                    local text
                    if autoDone then
                        text = string.format("%s hergestellt (%s Gewinn)",
                            label, Prices:FormatGold(profit))
                    elseif remaining > 0 then
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
                        key = key,
                        category = "Cooldowns & Crafts",
                        text = text,
                        value = profit,
                        ready = remaining == 0,
                        autoDone = autoDone,
                    }
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

-- Die besten Crafts aus den gescannten Berufsrezepten, sofern der Bestand sie
-- sofort hergibt. Cooldown-Rezepte behandelt die Cooldown-Sektion.
function Roadmap:BuildCraftEntries(craftReport, inventory)
    local Prices = GCP.Prices
    local entries = {}
    local threshold = minValue()
    for _, row in ipairs(craftReport.rows) do
        if #entries >= 2 then break end
        if row.profit > 0 and row.craftable >= 1 and not row.hasCooldown then
            local total = row.profit * row.craftable
            if total >= threshold then
                local key = "craft:" .. row.product
                local owned = inventory[row.product] and inventory[row.product].count or 0
                local baseline = ensureBaseline(key, owned)
                local autoDone = owned > baseline or nil
                entries[#entries + 1] = {
                    key = key,
                    category = "Cooldowns & Crafts",
                    text = string.format("%d× %s herstellen (%s Gewinn, %s)",
                        row.craftable, row.name, Prices:FormatGold(total), row.profession),
                    value = total,
                    autoDone = autoDone,
                }
            end
        end
    end
    return entries
end

function Roadmap:BuildSellEntries(report)
    local Prices = GCP.Prices
    local entries = {}
    local threshold = minValue()
    for index = 1, math.min(3, #report.rows) do
        local row = report.rows[index]
        if row.channel == "AH" and row.totalValue >= threshold then
            local key = "sell:" .. row.itemID
            local sellable = sellableCount(row)
            local autoDone = nil
            if sellable > 0 then
                local baseline = ensureBaseline(key, sellable)
                if baseline > 0 and sellable <= math.floor(baseline / 2) then
                    -- Mehr als die Haelfte des Bestands ist weg: verkauft
                    -- oder eingestellt.
                    autoDone = true
                end
            end
            entries[#entries + 1] = {
                key = key,
                category = "Verkaufen",
                text = string.format("%s ×%d ins AH stellen (≈ %s)",
                    row.name or ("Item " .. row.itemID), row.count,
                    Prices:FormatGold(row.totalValue)),
                value = row.totalValue,
                autoDone = autoDone,
            }
        end
    end
    return entries
end

function Roadmap:BuildFlipEntries(flips, inventory)
    local C = GCP.Constants
    local Prices = GCP.Prices
    local entries = {}
    local threshold = minValue()
    for _, row in ipairs(flips.motes) do
        if row.ownedCombines > 0 and row.combineDelta > 0 then
            local total = row.combineDelta * row.ownedCombines
            if total >= threshold then
                local key = "flip:combine:" .. row.primalID
                local ownedMotes = inventory[row.moteID] and inventory[row.moteID].count or 0
                local baseline = ensureBaseline(key, ownedMotes)
                local autoDone = (baseline - ownedMotes >= C.MOTES_PER_PRIMAL) or nil
                entries[#entries + 1] = {
                    key = key,
                    category = "Flips",
                    text = string.format("%d×%d Motes zu %s kombinieren (+%s gegenüber Einzelverkauf)",
                        row.ownedCombines, C.MOTES_PER_PRIMAL, row.name or "Ur-Partikel",
                        Prices:FormatGold(total)),
                    value = total,
                    autoDone = autoDone,
                }
            end
        elseif row.buyProfit >= threshold then
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
        if row.profit >= threshold then
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

-- Farm-Tipps nach geschaetztem Gold je Stunde; Ziele, die der Charakter
-- mangels Sammelberuf oder Skill nicht ernten kann, fliegen raus.
function Roadmap:BuildFarmEntries(inventory)
    local C = GCP.Constants
    local Prices = GCP.Prices
    local skills = GCP:GetKnownSkills()
    local hasAnySkillData = next(skills) ~= nil

    local function canFarm(farm)
        if not farm.skill then return true end
        if not hasAnySkillData then return true end
        local names = C.SKILL_NAMES[farm.skill] or {}
        for _, skillName in ipairs(names) do
            local rank = skills[skillName]
            if rank and rank >= (farm.minSkill or 1) then
                return true
            end
        end
        return false
    end

    local ranked = {}
    for _, farm in ipairs(C.FARM_CATALOG) do
        if canFarm(farm) then
            local price = Prices:GetPlanningPrice(farm.item)
            if price then
                local name = GetItemInfoCompat(farm.item)
                ranked[#ranked + 1] = {
                    item = farm.item,
                    name = name,
                    zone = farm.zone,
                    rate = farm.ratePerHour,
                    hourValue = price * farm.ratePerHour,
                }
            end
        end
    end
    table.sort(ranked, function(a, b) return a.hourValue > b.hourValue end)

    local entries = {}
    for index = 1, math.min(3, #ranked) do
        local farm = ranked[index]
        local key = "farm:" .. farm.item
        local owned = inventory[farm.item] and inventory[farm.item].count or 0
        local baseline = ensureBaseline(key, owned)
        -- Rund zehn Minuten Ausbeute gelten als "war farmen".
        local gainThreshold = math.max(2, math.floor(farm.rate / 6))
        local autoDone = (owned - baseline >= gainThreshold) or nil
        entries[#entries + 1] = {
            key = key,
            category = "Farm-Tipp des Tages",
            text = string.format("%s farmen – %s (≈ %s je Stunde, geschätzt)",
                farm.name or ("Item " .. farm.item), farm.zone,
                Prices:FormatGold(farm.hourValue)),
            value = farm.hourValue,
            autoDone = autoDone,
        }
    end
    return entries
end

-- ---------------------------------------------------------------------------
-- Zusammenbau
-- ---------------------------------------------------------------------------

function Roadmap:Generate()
    GCP:ResetRoadmapIfNewDay()
    local Prices = GCP.Prices
    local entries = {}

    -- Netherstoff als Referenz fuer das Scan-Alter: meistgehandeltes Gut, in
    -- praktisch jedem Auctionator-Scan enthalten.
    local scanAge = Prices:GetScanAgeDays(21877)
    local needScan = scanAge == nil or scanAge >= 1
    if needScan then
        ensureBaseline("scan:needed", true)
        entries[#entries + 1] = {
            key = "scan",
            category = "Preisbasis",
            text = scanAge == nil
                and "Im AH einen vollständigen Auctionator-Scan starten (noch keine Preisdaten)"
                or string.format("Auctionator-Scan auffrischen (letzter Scan vor %d Tag(en))", scanAge),
            value = nil,
        }
    elseif getBaseline("scan:needed") then
        entries[#entries + 1] = {
            key = "scan",
            category = "Preisbasis",
            text = "Auctionator-Scan aktualisiert – Preisbasis ist frisch",
            value = nil,
            autoDone = true,
        }
    end

    local inventory = GCP.Inventory:ScanAccount()

    for _, entry in ipairs(self:BuildDailyEntries()) do entries[#entries + 1] = entry end
    for _, entry in ipairs(self:BuildCooldownEntries()) do entries[#entries + 1] = entry end

    local craftReport = GCP.Crafts:BuildReport()
    for _, entry in ipairs(self:BuildCraftEntries(craftReport, inventory)) do
        entries[#entries + 1] = entry
    end

    local report = GCP.Advisor:BuildReport("account", "all")
    for _, entry in ipairs(self:BuildSellEntries(report)) do entries[#entries + 1] = entry end

    local flips = GCP.Flips:Build()
    for _, entry in ipairs(self:BuildFlipEntries(flips, inventory)) do
        entries[#entries + 1] = entry
    end

    for _, entry in ipairs(self:BuildFarmEntries(inventory)) do entries[#entries + 1] = entry end

    local checked = GCP.db.roadmap.checked
    local doneValue, openValue = 0, 0
    local doneCount, totalCount = 0, 0
    for _, entry in ipairs(entries) do
        if entry.autoDone then
            -- Von selbst erkannte Erledigung wird persistiert, damit sie auch
            -- dann stehen bleibt, wenn sich die Datenlage wieder aendert.
            checked[entry.key] = true
        end
        entry.done = checked[entry.key] == true
        totalCount = totalCount + 1
        if entry.done then doneCount = doneCount + 1 end
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
        doneCount = doneCount,
        totalCount = totalCount,
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
