local addonName, GCP = ...

GCP.Crafts = {}
local Crafts = GCP.Crafts

local GetItemInfoCompat = (C_Item and C_Item.GetItemInfo) or GetItemInfo

-- Zaehlt jeden Rezept-Scan mit. Die Opportunity Engine haengt ihren Cache
-- daran, statt die Rezeptliste bei jedem Refresh neu zu bewerten.
Crafts.revision = 0

local function itemIDFromLink(link)
    if type(link) ~= "string" then return nil end
    return tonumber(link:match("item:(%d+)"))
end

-- WoW gibt Rezeptdaten nur bei geoeffnetem Berufsfenster heraus. Einmal
-- oeffnen genuegt aber: Das Ergebnis landet in den SavedVariables, und der
-- Craft-Radar rechnet fortan auch ohne Fenster. Verzauberkunst laeuft ueber
-- die aeltere Craft-API; dort zaehlen nur Rezepte mit echtem Item-Produkt
-- (Öle) - Verzauberungen selbst lassen sich in TBC nicht ins AH stellen.

local function storeRecipes(professionName, list)
    if #list == 0 then return end
    GCP.db.recipes = GCP.db.recipes or {}
    GCP.db.recipes[professionName] = { scannedAt = GCP:Today(), list = list }
    Crafts.revision = Crafts.revision + 1
    GCP:Print(string.format("%d Rezepte aus \"%s\" übernommen.", #list, professionName))
    -- Neue Produkte und Zutaten sofort in die Preisbeobachtung aufnehmen.
    GCP.Prices:RecordObservedPrices()
    if GCP.UI then GCP.UI:RefreshIfShown() end
end

function Crafts:ScanTradeSkills()
    if type(GetNumTradeSkills) ~= "function" then return end
    local professionName = GetTradeSkillLine and GetTradeSkillLine() or nil
    if not professionName or professionName == "UNKNOWN" then return end
    local list = {}
    for index = 1, GetNumTradeSkills() do
        local skillName, skillType = GetTradeSkillInfo(index)
        if skillName and skillType ~= "header" then
            local product = itemIDFromLink(GetTradeSkillItemLink and GetTradeSkillItemLink(index))
            if product then
                local minMade, maxMade = 1, 1
                if type(GetTradeSkillNumMade) == "function" then
                    minMade, maxMade = GetTradeSkillNumMade(index)
                end
                local mats, complete = {}, true
                local reagentCount = (type(GetTradeSkillNumReagents) == "function")
                    and GetTradeSkillNumReagents(index) or 0
                for reagent = 1, reagentCount do
                    local _, _, needed = GetTradeSkillReagentInfo(index, reagent)
                    local matID = itemIDFromLink(GetTradeSkillReagentItemLink(index, reagent))
                    if matID and needed and needed > 0 then
                        mats[#mats + 1] = { matID, needed }
                    else
                        complete = false
                    end
                end
                local onCooldown = type(GetTradeSkillCooldown) == "function"
                    and GetTradeSkillCooldown(index) ~= nil or nil
                if complete and #mats > 0 then
                    list[#list + 1] = {
                        name = skillName,
                        product = product,
                        numMade = ((minMade or 1) + (maxMade or 1)) / 2,
                        mats = mats,
                        hasCooldown = onCooldown,
                    }
                end
            end
        end
    end
    storeRecipes(professionName, list)
end

function Crafts:ScanCrafts()
    if type(GetNumCrafts) ~= "function" then return end
    local professionName = (type(GetCraftName) == "function" and GetCraftName()) or "Verzauberkunst"
    local list = {}
    for index = 1, GetNumCrafts() do
        local craftName, _, craftType = GetCraftInfo(index)
        if craftName and craftType ~= "header" then
            local product = itemIDFromLink(GetCraftItemLink and GetCraftItemLink(index))
            if product then
                local mats, complete = {}, true
                local reagentCount = (type(GetCraftNumReagents) == "function")
                    and GetCraftNumReagents(index) or 0
                for reagent = 1, reagentCount do
                    local _, _, needed = GetCraftReagentInfo(index, reagent)
                    local matID = itemIDFromLink(GetCraftReagentItemLink(index, reagent))
                    if matID and needed and needed > 0 then
                        mats[#mats + 1] = { matID, needed }
                    else
                        complete = false
                    end
                end
                if complete and #mats > 0 then
                    list[#list + 1] = {
                        name = craftName,
                        product = product,
                        numMade = 1,
                        mats = mats,
                    }
                end
            end
        end
    end
    storeRecipes(professionName, list)
end

function Crafts:AllRecipes()
    local all = {}
    local recipes = GCP.db and GCP.db.recipes
    if not recipes then return all end
    for _, data in pairs(recipes) do
        for _, recipe in ipairs(data.list or {}) do
            all[#all + 1] = recipe
        end
    end
    return all
end

-- Bewertet alle bekannten Rezepte: Erloes = Produkt-Planungspreis mal
-- Ausbeute, netto nach AH-Gebuehr; Kosten = Zutaten zum Planungspreis, auch
-- wenn sie schon im Besitz sind (verbrauchte Mats haetten sonst verkauft
-- werden koennen). craftable: wie oft der Accountbestand das Rezept hergibt.
--
-- inventory ist optional: Wer den Bestand ohnehin gerade gescannt hat (die
-- Opportunity Engine tut das), reicht ihn durch, statt ihn ein zweites Mal
-- einzusammeln. Ohne Argument bleibt alles wie bisher.
function Crafts:BuildReport(inventory)
    local Prices = GCP.Prices
    inventory = inventory or GCP.Inventory:ScanAccount()
    local cooldownProducts = {}
    for _, cd in ipairs(GCP.Constants.CRAFT_COOLDOWNS) do
        cooldownProducts[cd.product] = true
    end

    local rows = {}
    local missingPrices = 0
    local professions = {}
    local recipes = GCP.db and GCP.db.recipes or {}
    for professionName, data in pairs(recipes) do
        professions[#professions + 1] = {
            name = professionName,
            scannedAt = data.scannedAt,
            count = #(data.list or {}),
        }
        for _, recipe in ipairs(data.list or {}) do
            local productPrice, productDays = Prices:GetPlanningPrice(recipe.product)
            if not productPrice then
                missingPrices = missingPrices + 1
            else
                local matCost = 0
                local complete = true
                local craftable = nil
                -- Datenbasis der Rechnung ist die schwaechste beteiligte Reihe:
                -- Ein sieben Tage belegtes Produkt hilft nicht, wenn die
                -- teuerste Zutat nur einen Momentanpreis hat.
                local priceDays = productDays or 0
                -- Die Zutaten mit ihrem tatsaechlich verwendeten Preis: Der
                -- Tooltip kann sie damit aufschluesseln, und die Opportunity
                -- Engine gewichtet die Marktlage der Kaufseite danach, ohne die
                -- Preise ein zweites Mal zu holen.
                local matValues = {}
                for _, mat in ipairs(recipe.mats) do
                    local price, matDays = Prices:GetPlanningPrice(mat[1])
                    if not price then
                        complete = false
                        break
                    end
                    if (matDays or 0) < priceDays then priceDays = matDays or 0 end
                    matValues[#matValues + 1] = { mat[1], mat[2], price }
                    matCost = matCost + price * mat[2]
                    local owned = inventory[mat[1]] and inventory[mat[1]].count or 0
                    local possible = math.floor(owned / mat[2])
                    if craftable == nil or possible < craftable then
                        craftable = possible
                    end
                end
                if not complete then
                    missingPrices = missingPrices + 1
                else
                    local revenue = Prices:NetAuction(productPrice * recipe.numMade)
                    local profit = revenue - matCost
                    local name, _, quality, _, _, _, _, _, _, icon = GetItemInfoCompat(recipe.product)
                    -- Der Produktpreis ist eine Eingangszahl, keine Wahrheit.
                    -- Geprueft wird gegen Haendlerwert und Materialeinsatz;
                    -- die Begruendung steht bei C.PRICE_SANITY.
                    local plausible, priceWarning = Prices:AssessSalePrice(
                        recipe.product, productPrice * recipe.numMade, matCost)
                    rows[#rows + 1] = {
                        recipeName = recipe.name,
                        name = name or recipe.name,
                        product = recipe.product,
                        quality = quality,
                        icon = icon,
                        profession = professionName,
                        numMade = recipe.numMade,
                        matCost = matCost,
                        mats = matValues,
                        revenue = revenue,
                        profit = profit,
                        priceDays = priceDays,
                        craftable = craftable or 0,
                        hasCooldown = recipe.hasCooldown or cooldownProducts[recipe.product] or nil,
                        pricePlausible = plausible,
                        priceWarning = priceWarning,
                    }
                end
            end
        end
    end
    table.sort(rows, function(a, b)
        if a.profit ~= b.profit then return a.profit > b.profit end
        return (a.name or "") < (b.name or "")
    end)
    table.sort(professions, function(a, b) return a.name < b.name end)
    return {
        rows = rows,
        missingPrices = missingPrices,
        professions = professions,
    }
end

local scanPending = false
local function queueScan(scanFunction)
    -- TRADE_SKILL_UPDATE feuert im Schwall; ausserdem fehlen direkt nach dem
    -- Oeffnen oft noch Item-Links. Ein gebuendelter, leicht verzoegerter Scan
    -- bekommt vollstaendige Daten.
    if scanPending then return end
    scanPending = true
    C_Timer.After(0.8, function()
        scanPending = false
        scanFunction(Crafts)
    end)
end

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("TRADE_SKILL_SHOW")
eventFrame:RegisterEvent("TRADE_SKILL_UPDATE")
eventFrame:RegisterEvent("CRAFT_SHOW")
eventFrame:RegisterEvent("CRAFT_UPDATE")
eventFrame:SetScript("OnEvent", function(_, event)
    if not GCP.db then return end
    if event == "TRADE_SKILL_SHOW" or event == "TRADE_SKILL_UPDATE" then
        queueScan(Crafts.ScanTradeSkills)
    else
        queueScan(Crafts.ScanCrafts)
    end
end)
