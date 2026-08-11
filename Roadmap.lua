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
    local Quests = GCP.Quests
    local entries = {}
    for _, pool in ipairs(C.DAILY_POOLS) do
        if Quests:IsPoolAvailable(pool) then
            if pool.oneOf then
                -- Ein Questgeber, ein Angebot pro Tag: eine Zeile.
                local done, doneID = Quests:PoolDoneToday(pool)
                local gold, measured = Quests:PoolGold(pool)
                entries[#entries + 1] = {
                    key = "pool:" .. pool.key,
                    category = "Daily-Quests",
                    text = pool.label .. (pool.note and (" – " .. pool.note) or ""),
                    note = pool.zone,
                    value = gold,
                    estimated = not measured,
                    minutes = pool.minutes,
                    autoDone = done or nil,
                    questID = doneID,
                }
            else
                for _, quest in ipairs(pool.quests) do
                    if Quests:IsQuestUnlocked(quest) then
                        local gold, measured = Quests:GetGold(quest.id, quest.gold)
                        entries[#entries + 1] = {
                            key = "daily:" .. quest.id,
                            category = "Daily-Quests",
                            text = quest.name,
                            note = quest.zone,
                            value = gold,
                            estimated = not measured,
                            minutes = pool.minutes,
                            autoDone = Quests:IsCompleted(quest.id) == true or nil,
                            questID = quest.id,
                        }
                    end
                end
            end
        end
    end
    return entries
end

-- Angenommene Quests, die sich schon abgeben lassen: fertiges Gold, das nur
-- noch abgeholt werden muss.
function Roadmap:BuildQuestLogEntries()
    local C = GCP.Constants
    local Prices = GCP.Prices
    local entries = {}
    local threshold = minValue()
    local report = GCP.Quests:BuildLogReport()
    for _, row in ipairs(report.rows) do
        if #entries >= 3 then break end
        if row.isComplete == true and row.value >= threshold then
            local breakdown = {}
            if row.money and row.money > 0 then
                breakdown[#breakdown + 1] = "Questgold: " .. Prices:FormatMoney(row.money)
            end
            if row.itemValue and row.itemValue > 0 then
                breakdown[#breakdown + 1] = string.format("Belohnung%s: %s",
                    row.rewardName and (" " .. row.rewardName) or "",
                    Prices:FormatMoney(row.itemValue))
                if row.rewardSource then
                    breakdown[#breakdown + 1] = row.rewardSource == "AH"
                        and "Bewertet über das AH (netto nach 5 % Gebühr)"
                        or "Bewertet über den Händlerpreis (kein besserer AH-Wert)"
                end
                if row.rewardSource == "AH" then
                    breakdown[#breakdown + 1] = Prices:FormatPlanningBasis(row.rewardDays)
                end
            end
            entries[#entries + 1] = {
                key = "quest:" .. (row.questID or row.title),
                category = "Quests abgeben",
                text = row.title,
                note = row.rewardName and ("Belohnung: " .. row.rewardName) or "abgabebereit",
                value = row.value,
                minutes = C.MINUTES.questlog,
                breakdown = breakdown,
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
            local productPrice, productDays = Prices:GetPlanningPrice(craft.product)
            if productPrice then
                local matCost = 0
                local matsKnown = true
                local priceDays = productDays or 0
                for _, mat in ipairs(craft.mats) do
                    local price, matDays = Prices:GetPlanningPrice(mat[1])
                    if not price then
                        matsKnown = false
                        break
                    end
                    if (matDays or 0) < priceDays then priceDays = matDays or 0 end
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
                    local text, note
                    if autoDone then
                        text = label .. " hergestellt"
                    elseif remaining > 0 then
                        text = label
                        note = "wieder bereit in " .. formatHours(remaining)
                    elseif craft.cooldown then
                        text = label .. " herstellen"
                        note = "Cooldown bereit"
                    else
                        text = label .. " herstellen"
                        note = "ohne Cooldown, je Stück"
                    end
                    entries[#entries + 1] = {
                        key = key,
                        category = "Cooldowns & Crafts",
                        text = text,
                        note = note,
                        value = profit,
                        minutes = GCP.Constants.MINUTES.cooldown,
                        ready = remaining == 0,
                        autoDone = autoDone,
                        itemID = craft.product,
                        breakdown = {
                            "Produktwert netto: " .. Prices:FormatMoney(Prices:NetAuction(productPrice)),
                            "Zutatenwert: " .. Prices:FormatMoney(matCost),
                            "Erwarteter Gewinn: " .. Prices:FormatMoney(profit),
                            Prices:FormatPlanningBasis(priceDays),
                        },
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
                    text = string.format("%d× %s herstellen", row.craftable, row.name),
                    note = row.profession,
                    value = total,
                    minutes = GCP.Constants.MINUTES.craft,
                    autoDone = autoDone,
                    itemID = row.product,
                    breakdown = {
                        string.format("Produktwert netto (×%.1f): %s",
                            row.numMade, Prices:FormatMoney(row.revenue)),
                        "Zutatenwert: " .. Prices:FormatMoney(row.matCost),
                        string.format("Erwarteter Gewinn: %s je Stück · %s für %d Stück",
                            Prices:FormatMoney(row.profit), Prices:FormatMoney(total), row.craftable),
                        Prices:FormatPlanningBasis(row.priceDays),
                    },
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
    local protectConsumables = GCP.db.options.keepConsumables
    for _, row in ipairs(report.rows) do
        if #entries >= 3 then break end
        local skip = row.channel ~= "AH"
            or row.totalValue < threshold
            or (protectConsumables and row.keep)
        if not skip then
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
            local breakdown = {
                string.format("Verkauf netto: %s je Stück", Prices:FormatMoney(row.unitValue)),
                string.format("Erwartung: %s für %d Stück",
                    Prices:FormatMoney(row.totalValue), row.count),
            }
            if row.vendorUnit then
                breakdown[#breakdown + 1] = "Zum Vergleich Händler: "
                    .. Prices:FormatMoney(row.vendorUnit)
            end
            -- Der Verkaufen-Tab rechnet bewusst mit dem Momentanpreis ("was
            -- bekomme ich jetzt"), nicht mit dem 7-Tage-Median.
            breakdown[#breakdown + 1] = "Preisbasis: aktueller Scanpreis"
                .. (row.marketSource and (" (" .. row.marketSource .. ")") or "")
            entries[#entries + 1] = {
                key = key,
                category = "Verkaufen",
                text = string.format("%s ×%d ins AH stellen",
                    row.name or ("Item " .. row.itemID), row.count),
                value = row.totalValue,
                minutes = GCP.Constants.MINUTES.sell,
                autoDone = autoDone,
                itemID = row.itemID,
                link = row.link,
                breakdown = breakdown,
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
                    text = string.format("%d×%d Partikel zu %s kombinieren",
                        row.ownedCombines, C.MOTES_PER_PRIMAL, row.name or "Urelement"),
                    note = "gegenüber Einzelverkauf",
                    value = total,
                    minutes = C.MINUTES.flip,
                    autoDone = autoDone,
                    itemID = row.primalID,
                    breakdown = {
                        string.format("Zutaten: %d Partikel, einzeln netto %s",
                            C.MOTES_PER_PRIMAL,
                            Prices:FormatMoney(C.MOTES_PER_PRIMAL * Prices:NetAuction(row.motePrice))),
                        "Verkauf netto: " .. Prices:FormatMoney(Prices:NetAuction(row.primalPrice)),
                        string.format("Gewinn: %s je Kombination · %s für %d",
                            Prices:FormatMoney(row.combineDelta),
                            Prices:FormatMoney(total), row.ownedCombines),
                        Prices:FormatPlanningBasis(row.priceDays),
                    },
                }
            end
        elseif row.buyProfit >= threshold then
            entries[#entries + 1] = {
                key = "flip:buy:" .. row.primalID,
                category = "Flips",
                text = string.format("Partikel kaufen und %s verkaufen",
                    row.name or "Urelement"),
                note = "je Stück",
                value = row.buyProfit,
                minutes = C.MINUTES.flip,
                itemID = row.primalID,
                breakdown = {
                    string.format("Einkauf: %d Partikel zu je %s = %s",
                        C.MOTES_PER_PRIMAL, Prices:FormatMoney(row.motePrice),
                        Prices:FormatMoney(C.MOTES_PER_PRIMAL * row.motePrice)),
                    "Verkauf netto: " .. Prices:FormatMoney(Prices:NetAuction(row.primalPrice)),
                    "Gewinn: " .. Prices:FormatMoney(row.buyProfit),
                    Prices:FormatPlanningBasis(row.priceDays),
                },
            }
        end
    end
    for _, row in ipairs(flips.essences) do
        if row.profit >= threshold then
            local text, buy, sell
            if row.direction == "up" then
                text = string.format("3× niedere zu %s wandeln", row.name or "Essenz")
                buy = C.ESSENCES_PER_GREATER * row.lesserPrice
                sell = Prices:NetAuction(row.greaterPrice)
            else
                text = string.format("%s in 3 niedere aufteilen", row.name or "Essenz")
                buy = row.greaterPrice
                sell = C.ESSENCES_PER_GREATER * Prices:NetAuction(row.lesserPrice)
            end
            entries[#entries + 1] = {
                key = "flip:essence:" .. row.greaterID,
                category = "Flips",
                text = text,
                note = "Verzauberkunst",
                value = row.profit,
                minutes = C.MINUTES.flip,
                itemID = row.greaterID,
                breakdown = {
                    "Einkauf/Zutaten: " .. Prices:FormatMoney(buy),
                    "Verkauf netto: " .. Prices:FormatMoney(sell),
                    "Gewinn: " .. Prices:FormatMoney(row.profit),
                    Prices:FormatPlanningBasis(row.priceDays),
                },
            }
        end
    end
    table.sort(entries, function(a, b) return a.value > b.value end)
    while #entries > 3 do
        table.remove(entries)
    end
    return entries
end

-- ---------------------------------------------------------------------------
-- FARM-EINTRAEGE DES TAGESPLANS (1.0.0-beta.10 neu gebaut)
--
-- Bis beta.9 stand hier die Rechnung
--
--     hourValue = Marktpreis x FARM_CATALOG.ratePerHour
--
-- und daraus wurde eine Zeile wie "Felweed farmen - Erwartung 240 g je
-- Stunde", nach genau dieser Zahl sortiert. Die Raten stammten aus fremden
-- Farm-Guides. Das war der einzige Ort im ganzen Addon, an dem eine fremde
-- Schaetzung als eigene Erwartung ausgegeben wurde - und ausgerechnet an der
-- Frage "Was soll ich heute tun?", also dort, wo es am meisten wiegt.
--
-- Jetzt gibt es nur noch eine Quelle fuer Gold je Stunde: Farm.lua, und die
-- kennt ausschliesslich eigene, gemessene Sitzungen.
--
--   MIT eigenen Messungen  entstehen Zeilen mit einer konkreten Zahl, gereiht
--                          nach dem gemessenen Wert - und mit der Stichprobe
--                          daneben.
--   OHNE eigene Messungen  entsteht KEINE Gold-Zahl. Stattdessen eine einzige
--                          Zeile ohne Wert, die sagt, dass eine Farmrate erst
--                          gemessen werden muss - mit dem Hinweis, wie.
--
-- Der Katalog aus Constants liefert weiterhin, was er ehrlich liefern kann:
-- welche Ziele es gibt, wo sie vorkommen und wer sie einsammeln kann.
-- ---------------------------------------------------------------------------
function Roadmap:BuildFarmEntries(inventory)
    local C = GCP.Constants
    local Prices = GCP.Prices
    local Farm = GCP.Farm
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

    -- Zone je Item aus dem Katalog - reine Ortsangabe, keine Bewertung.
    local catalogZone, farmable = {}, {}
    for _, farm in ipairs(C.FARM_CATALOG) do
        catalogZone[farm.item] = farm.zone
        farmable[farm.item] = canFarm(farm)
    end

    local entries = {}

    -- 1) Eigene gemessene Raten. Farm:BuildOpportunities liefert bereits
    --    Bloecke aus dem eigenen Median je Zone und Item; hier wird daraus
    --    eine Tagesplanzeile, ohne die Rechnung ein zweites Mal zu fuehren.
    local blocks = Farm and Farm:BuildOpportunities(C.MINUTES.farm) or {}
    for _, block in ipairs(blocks) do
        if #entries >= 3 then break end
        -- Ziele, die der Charakter gar nicht ernten kann, fallen weiter raus -
        -- auch wenn irgendwann einmal eine Sitzung dazu lief.
        if farmable[block.itemID] ~= false then
            local key = "farm:" .. tostring(block.itemID) .. ":" .. tostring(block.zone)
            local owned = inventory[block.itemID] and inventory[block.itemID].count or 0
            local baseline = ensureBaseline(key, owned)
            local rate = block.rate or {}
            -- Rund zehn Minuten Ausbeute gelten als "war farmen" - gemessen an
            -- der EIGENEN Rate, nicht an einer angenommenen.
            local perHour = rate.medianItemsPerHour or 0
            local gainThreshold = math.max(2, math.floor(perHour / 6))
            local autoDone = (owned - baseline >= gainThreshold) or nil
            local minutes = block.blockMinutes or C.MINUTES.farm
            entries[#entries + 1] = {
                key = key,
                category = "Farmen",
                text = string.format("%s farmen – %s",
                    GetItemInfoCompat(block.itemID) or ("Item " .. tostring(block.itemID)),
                    block.zone or catalogZone[block.itemID] or "eigene Farmzone"),
                note = string.format("eigene Rate aus %d Sitzung(en)", rate.sessions or 0),
                value = block.expectedProfit,
                minutes = minutes,
                autoDone = autoDone,
                itemID = block.itemID,
                breakdown = {
                    string.format("Deine gemessene Rate: %.0f Stück/Stunde", perHour),
                    string.format("Datenlage: %d Sitzung(en) – %s",
                        rate.sessions or 0,
                        GCP.Market:ConfidenceLabel(rate.confidence)),
                    string.format("In %d Minuten also etwa %d Stück",
                        minutes, block.quantity or 0),
                    "Wert: " .. Prices:FormatMoney(block.expectedProfit or 0),
                    "Gold je Stunde entsteht ausschließlich aus deinen eigenen "
                        .. "Sitzungen – Gold Copilot übernimmt keine Raten aus Guides.",
                },
            }
        end
    end
    if #entries > 0 then return entries end

    -- 2) Keine eigene Messung. Es gibt also keine Farmrate - und damit auch
    --    keine Gold-Zahl. Was es gibt, ist ein sinnvoller naechster Schritt:
    --    eine Sitzung starten, damit ueberhaupt eine Rate entstehen kann.
    --
    --    value bleibt bewusst nil. Die Zeile steht damit im Tagesplan ohne
    --    Wert, und der Zielplan rechnet sie nicht mit - genau richtig, denn
    --    niemand weiss, was sie einbringt.
    local suggestion = nil
    for _, farm in ipairs(C.FARM_CATALOG) do
        if farmable[farm.item] and Prices:GetPlanningPrice(farm.item) then
            suggestion = farm
            break
        end
    end
    if not suggestion then return entries end

    local name = GetItemInfoCompat(suggestion.item)
        or ("Item " .. tostring(suggestion.item))
    entries[#entries + 1] = {
        key = "farm:measure",
        category = "Farmen",
        text = string.format("Farmrate messen – z. B. %s in %s", name, suggestion.zone),
        note = "noch keine eigene Rate",
        value = nil,
        minutes = C.MINUTES.farm,
        itemID = suggestion.item,
        breakdown = {
            "Gold Copilot kennt für dich noch keine Farmrate.",
            "Farmraten hängen an Ausrüstung, Klasse, Route, Konkurrenz und "
                .. "Tageszeit – eine Zahl aus einem Guide wäre für dich falsch.",
            "Starte im Farm-Tab eine Sitzung. Ab der ersten abgeschlossenen "
                .. "Sitzung steht hier deine eigene, gemessene Rate.",
        },
    }
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

    for _, entry in ipairs(self:BuildQuestLogEntries()) do entries[#entries + 1] = entry end
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
    local categories, categoryOrder = {}, {}
    for _, entry in ipairs(entries) do
        if entry.autoDone then
            -- Von selbst erkannte Erledigung wird persistiert, damit sie auch
            -- dann stehen bleibt, wenn sich die Datenlage wieder aendert.
            -- Ausnahme Quests: Deren Flag setzt der Server beim taeglichen
            -- Reset zurueck, und dann soll die Zeile wieder offen sein.
            if entry.key:sub(1, 6) ~= "daily:" and entry.key:sub(1, 5) ~= "pool:" then
                checked[entry.key] = true
            end
        end
        entry.done = entry.autoDone == true or checked[entry.key] == true
        totalCount = totalCount + 1
        if entry.done then doneCount = doneCount + 1 end
        if entry.value then
            if entry.done then
                doneValue = doneValue + entry.value
            else
                openValue = openValue + entry.value
            end
        end
        local bucket = categories[entry.category]
        if not bucket then
            bucket = { open = 0, done = 0, count = 0 }
            categories[entry.category] = bucket
            categoryOrder[#categoryOrder + 1] = entry.category
        end
        bucket.count = bucket.count + 1
        if entry.value then
            if entry.done then
                bucket.done = bucket.done + entry.value
            else
                bucket.open = bucket.open + entry.value
            end
        end
    end

    local goal = self:BuildGoalPlan(entries)

    return {
        entries = entries,
        report = report,
        doneValue = doneValue,
        openValue = openValue,
        doneCount = doneCount,
        totalCount = totalCount,
        categories = categories,
        categoryOrder = categoryOrder,
        goal = goal,
    }
end

-- Der schnellste Weg zum Tagesziel: offene Aufgaben nach Gold je Minute,
-- gierig aufgesammelt bis das Ziel erreicht ist. Farmen steht dabei fast
-- immer hinten - eine Stunde Kraeuter bringt selten so viel wie zehn Minuten
-- Dailies, und genau das soll die Reihenfolge zeigen.
function Roadmap:BuildGoalPlan(entries)
    local goalValue = (GCP.db.options.dailyGoal) or GCP.Constants.DEFAULT_DAILY_GOAL
    local earned = 0
    local open = {}
    for _, entry in ipairs(entries) do
        if entry.done then
            if entry.value then earned = earned + entry.value end
        elseif entry.value and entry.value > 0 and entry.minutes then
            open[#open + 1] = entry
        end
    end
    if goalValue <= 0 then
        return { goalValue = 0, earned = earned, steps = {}, gold = 0, minutes = 0, reached = true }
    end

    table.sort(open, function(a, b)
        return (a.value / a.minutes) > (b.value / b.minutes)
    end)

    local steps, gold, minutes = {}, 0, 0
    for _, entry in ipairs(open) do
        if earned + gold >= goalValue then break end
        steps[#steps + 1] = entry
        entry.goalRank = #steps
        gold = gold + entry.value
        minutes = minutes + entry.minutes
    end

    return {
        goalValue = goalValue,
        earned = earned,
        steps = steps,
        gold = gold,
        minutes = minutes,
        reached = earned + gold >= goalValue,
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
