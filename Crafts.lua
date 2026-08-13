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

-- ---------------------------------------------------------------------------
-- SELBER MACHEN ODER KAUFEN? (1.1.0-beta.5)
--
-- Netherstoffballen kosten im Auktionshaus 1 g. Fuenf Netherstoff kosten 60
-- Silber. Wer den Ballen kauft, zahlt 40 Silber dafuer, dass jemand anders
-- einmal auf "herstellen" gedrueckt hat - und bei zwoelf Ballen je Route ist
-- das kein Rundungsfehler mehr.
--
-- Bis 1.1.0-beta.4 kannte die Beschaffung genau einen Weg: kaufen. Jetzt
-- kennt sie drei, und sie nimmt den guenstigsten:
--
--     Kosten = min(Auktionshaus, Haendler, selbst herstellen)
--
-- Das ist dieselbe Frage, die TSM mit
-- "min(dbmarket, crafting, vendorbuy, ...)" beantwortet - hier mit den eigenen
-- Preisquellen und ausdruecklich nur mit RezeptEN, die der Spieler kennt.
--
-- ---------------------------------------------------------------------------
-- WORAN SICH DIE REKURSION HAELT
--
--   * TIEFE. Ein Ballen aus Stoff ist eine Ebene. Drei sind das Aeusserste,
--     was in TBC vorkommt; darueber bricht die Rechnung ab und nimmt den
--     Kaufpreis. Ohne Grenze frisst eine Rezeptkette den Frame.
--   * ZYKLEN. Es gibt Rezeptpaare, die sich gegenseitig herstellen. Ein Item,
--     das in der laufenden Rechnung schon vorkommt, wird nicht noch einmal
--     aufgeloest - sonst laeuft die Rechnung im Kreis.
--   * UNBEKANNTES. Fehlt EINE Zutat der Preis, gibt es keinen Herstellpreis.
--     Nicht "die halbe Rechnung", nicht null - keinen. Eine Kostenschaetzung
--     mit einer geratenen Position ist eine geratene Kostenschaetzung.
--   * NUR EIGENE REZEPTE. Was der Spieler nicht kann, kann er nicht billiger
--     machen. Gerechnet wird ausschliesslich mit db.recipes.
-- ---------------------------------------------------------------------------

local MAX_CRAFT_DEPTH = 3

-- Produkt -> Rezept. Ohne diesen Index liefe jede Kostenrechnung ueber alle
-- Rezepte, und die Rechnung laeuft je Zutat und je Rekursionsebene erneut -
-- bei zweihundert Rezepten ist das der Unterschied zwischen "merkt niemand"
-- und einem Ruckler beim Oeffnen des Fensters.
function Crafts:ProductIndex()
    if self.productIndex and self.productIndexRevision == self.revision then
        return self.productIndex
    end
    local index = {}
    for professionName, data in pairs(GCP.db and GCP.db.recipes or {}) do
        for _, recipe in ipairs(data.list or {}) do
            if type(recipe.product) == "number" and not index[recipe.product] then
                index[recipe.product] = { recipe = recipe, profession = professionName }
            end
        end
    end
    self.productIndex = index
    self.productIndexRevision = self.revision
    return index
end

-- Das bekannte Rezept fuer dieses Produkt. Rueckgabe: Rezept, Ausbeute je
-- Durchgang, Beruf.
function Crafts:RecipeFor(itemID)
    if type(itemID) ~= "number" then return nil end
    local entry = self:ProductIndex()[itemID]
    if not entry then return nil end
    return entry.recipe, math.max(entry.recipe.numMade or 1, 1), entry.profession
end

-- Was kostet es, EIN Stueck davon selbst herzustellen?
--
-- visited ist die Kette der Items, die in dieser Rechnung schon offen sind -
-- der Zyklusschutz. Rueckgabe: Stueckkosten oder nil.
-- Kurzlebiger Zwischenspeicher. Dieselbe Zutat kommt in einem Durchlauf ueber
-- alle Rezepte dutzendfach vor; ohne ihn waere die Rekursion exponentiell.
-- Fuenf Sekunden, weil sich Preise in dieser Zeit nicht bewegen und ein
-- Rezeptscan die Fassung ohnehin hochzaehlt.
local COST_CACHE_SECONDS = 5

function Crafts:CostCache()
    local now = (type(GetTime) == "function" and GetTime()) or 0
    if self.costCache and self.costCacheRevision == self.revision
        and self.costCacheAt and (now - self.costCacheAt) < COST_CACHE_SECONDS then
        return self.costCache
    end
    self.costCache = {}
    self.costCacheRevision = self.revision
    self.costCacheAt = now
    return self.costCache
end

function Crafts:CraftCost(itemID, depth, visited)
    depth = depth or 1
    if depth > MAX_CRAFT_DEPTH then return nil end
    local recipe, numMade, professionName = self:RecipeFor(itemID)
    if not recipe then return nil end
    visited = visited or {}
    if visited[itemID] then return nil end

    -- Nur die oberste Ebene speichert zwischen: Weiter unten haengt das
    -- Ergebnis an der Kette darueber (Zyklusschutz), und ein Treffer waere
    -- dort fuer eine andere Kette womoeglich falsch.
    local cache = (depth == 1) and self:CostCache() or nil
    local hit = cache and cache[itemID]
    if hit ~= nil then
        if hit == false then return nil end
        return hit, professionName, recipe
    end

    visited[itemID] = true
    local total = 0
    local complete = true
    for _, mat in ipairs(recipe.mats or {}) do
        local matID, count = mat[1], mat[2]
        if type(matID) ~= "number" or type(count) ~= "number" or count <= 0 then
            complete = false
            break
        end
        local price = GCP.Prices:GetAcquisitionPrice(matID, depth + 1, visited)
        if not price then
            -- Eine Zutat ohne Preis macht die ganze Rechnung wertlos.
            complete = false
            break
        end
        total = total + price * count
    end
    visited[itemID] = nil

    if not complete or total <= 0 then
        if cache then cache[itemID] = false end
        return nil
    end
    local unit = total / numMade
    if cache then cache[itemID] = unit end
    return unit, professionName, recipe
end

-- ---------------------------------------------------------------------------
-- HERSTELLEN AUS DEM GUIDE (1.1.0-beta.5)
--
-- Der Guide sagt "1x Hexerzwirnrobe herstellen", und danach sucht man das
-- Rezept von Hand in einer Liste mit zweihundert Eintraegen. Der Knopf im
-- Guide-Fenster nimmt genau diesen Schritt ab.
--
-- WAS DER CLIENT DABEI VORGIBT:
--   * Rezepte gibt es nur ueber die LISTENPOSITION im GEOEFFNETEN
--     Berufsfenster. Es gibt keine Abfrage "stelle Item X her". Ist das Fenster
--     zu, ist die Liste leer - dann sagt der Knopf das, statt einen Index zu
--     raten.
--   * Die Liste ist gefiltert, wie der Spieler sie zuletzt gefiltert hat.
--     Gesucht wird deshalb ueber den Item-Link des Produkts und nicht ueber
--     einen gemerkten Index: Ein gemerkter Index zeigt nach einem Filterwechsel
--     auf ein anderes Rezept, und dann stellt der Knopf etwas anderes her.
--   * Verzauberkunst laeuft ueber die aeltere Craft-API. Beide Wege werden
--     geprueft, in dieser Reihenfolge.
--
-- Rueckgabe: Listenposition, "trade" | "craft", Rezeptname.
-- ---------------------------------------------------------------------------

function Crafts:FindOpenRecipe(itemID)
    if type(itemID) ~= "number" then return nil end
    if type(GetNumTradeSkills) == "function"
        and type(GetTradeSkillItemLink) == "function" then
        local total = GetNumTradeSkills() or 0
        for index = 1, total do
            local name, skillType = GetTradeSkillInfo(index)
            if name and skillType ~= "header"
                and itemIDFromLink(GetTradeSkillItemLink(index)) == itemID then
                return index, "trade", name
            end
        end
    end
    if type(GetNumCrafts) == "function" and type(GetCraftItemLink) == "function" then
        local total = GetNumCrafts() or 0
        for index = 1, total do
            local name, _, craftType = GetCraftInfo(index)
            if name and craftType ~= "header"
                and itemIDFromLink(GetCraftItemLink(index)) == itemID then
                return index, "craft", name
            end
        end
    end
    return nil
end

-- Ist das Berufsfenster ueberhaupt offen? Ohne offene Liste gibt der Client
-- keine Rezepte heraus - das ist keine Vermutung, sondern die API.
function Crafts:HasOpenProfession()
    if type(GetNumTradeSkills) == "function" and (GetNumTradeSkills() or 0) > 0 then
        return true
    end
    if type(GetNumCrafts) == "function" and (GetNumCrafts() or 0) > 0 then
        return true
    end
    return false
end

-- Rueckgabe: true bei ausgeloestem Zauber, sonst false und ein Satz, der sagt
-- warum. Ein "false" ohne Begruendung waere ein Knopf, der nichts tut.
function Crafts:Make(itemID, count)
    if type(itemID) ~= "number" then
        return false, "Zu diesem Schritt gehört kein herstellbares Item."
    end
    if not self:HasOpenProfession() then
        return false, "Öffne zuerst dein Berufsfenster – ohne offene Liste gibt "
            .. "der Client kein Rezept heraus."
    end
    local index, api, name = self:FindOpenRecipe(itemID)
    if not index then
        local product = GetItemInfoCompat(itemID) or ("Item " .. tostring(itemID))
        return false, string.format("%s steht nicht in der geöffneten "
            .. "Berufsliste – anderer Beruf oder ein gesetzter Filter?", product)
    end
    count = math.max(math.floor(tonumber(count) or 1), 1)
    if api == "trade" then
        if type(DoTradeSkill) ~= "function" then
            return false, "Dieser Client kennt DoTradeSkill nicht."
        end
        local ok = pcall(DoTradeSkill, index, count)
        if not ok then return false, "Der Client hat die Herstellung abgelehnt." end
    else
        if type(DoCraft) ~= "function" then
            return false, "Dieser Client kennt DoCraft nicht."
        end
        local ok = pcall(DoCraft, index)
        if not ok then return false, "Der Client hat die Herstellung abgelehnt." end
    end
    return true, name
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
                    -- Der Beschaffungspreis, nicht der Auktionspreis: Zutaten
                    -- wie Runenfaden oder Blauer Farbstoff stehen beim Haendler
                    -- zu einem festen Betrag, und der ist regelmaessig
                    -- niedriger. Bis 1.1.0-beta.4 fiel ausserdem jedes Rezept
                    -- mit einer reinen Haendlerzutat ganz aus der Bewertung,
                    -- weil so eine Zutat im Auktionshaus oft gar nicht steht.
                    local price, matSource, matDays = Prices:GetAcquisitionPrice(mat[1])
                    if not price then
                        complete = false
                        break
                    end
                    -- Ein Haendlerpreis hat keine Historie und braucht auch
                    -- keine: Er bewegt sich nicht. Ihn als "null Tageswerte"
                    -- in die Datenbasis zu rechnen wuerde jedes Rezept mit
                    -- einer Haendlerzutat auf "Momentanpreis" druecken - und
                    -- damit die sicherste Zahl der ganzen Rechnung als die
                    -- unsicherste ausweisen.
                    if matSource ~= "Händler" and (matDays or 0) < priceDays then
                        priceDays = matDays or 0
                    end
                    matValues[#matValues + 1] = { mat[1], mat[2], price, matSource }
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
