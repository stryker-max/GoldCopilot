local addonName, GCP = ...

GCP.Quests = {}
local Quests = GCP.Quests

local GetItemInfoCompat = (C_Item and C_Item.GetItemInfo) or GetItemInfo

-- ---------------------------------------------------------------------------
-- Abgeschlossen-Abfrage. true/false, oder nil wenn der Client keine anbietet.
-- ---------------------------------------------------------------------------

function Quests:IsCompleted(questID)
    if C_QuestLog and C_QuestLog.IsQuestFlaggedCompleted then
        return C_QuestLog.IsQuestFlaggedCompleted(questID) == true
    end
    if type(IsQuestFlaggedCompleted) == "function" then
        return IsQuestFlaggedCompleted(questID) == true
    end
    return nil
end

-- Questie kennt die Freischaltungsketten besser als jede eigene Liste. Ist es
-- geladen, entscheidet es; sonst faellt die Pruefung auf die Vorquest zurueck.
local function questieSaysDoable(questID)
    local QuestieLoader = _G.QuestieLoader
    if not (QuestieLoader and QuestieLoader.ImportModule) then return nil end
    local ok, QuestieDB = pcall(QuestieLoader.ImportModule, QuestieLoader, "QuestieDB")
    if not ok or type(QuestieDB) ~= "table" or type(QuestieDB.IsDoable) ~= "function" then
        return nil
    end
    local doable
    ok, doable = pcall(QuestieDB.IsDoable, questID)
    if not ok then return nil end
    return doable == true
end

-- ---------------------------------------------------------------------------
-- Echte Goldbetraege lernen. Die Schaetzungen in Constants sind Startwerte;
-- was der Server beim Abgeben ueberweist, ist die Wahrheit.
-- ---------------------------------------------------------------------------

function Quests:LearnGold(questID, money)
    if type(questID) ~= "number" or type(money) ~= "number" or money <= 0 then
        return
    end
    if not GCP.db then return end
    GCP.db.questGold = GCP.db.questGold or {}
    GCP.db.questGold[questID] = money
end

-- Rueckgabe: Betrag, sowie true wenn er gemessen (statt geschaetzt) ist.
function Quests:GetGold(questID, fallback)
    local learned = GCP.db and GCP.db.questGold and GCP.db.questGold[questID]
    if learned then
        return learned, true
    end
    return fallback, false
end

-- ---------------------------------------------------------------------------
-- Verfuegbarkeit eines Daily-Pools
-- ---------------------------------------------------------------------------

local function meetsSkill(pool)
    if not pool.skill then return true end
    local skills = GCP:GetKnownSkills()
    if next(skills) == nil then
        -- Fertigkeitenfenster noch nicht gelesen: lieber anzeigen als
        -- faelschlich verschweigen.
        return true
    end
    for _, name in ipairs(GCP.Constants.SKILL_NAMES[pool.skill] or {}) do
        local rank = skills[name]
        if rank and rank >= (pool.minSkill or 1) then
            return true
        end
    end
    return false
end

local function playerLevel()
    if type(UnitLevel) == "function" then
        return UnitLevel("player") or 0
    end
    return 0
end

-- Fuer Pools mit oneOf: Ist heute schon eine Quest daraus abgegeben?
function Quests:PoolDoneToday(pool)
    for _, entry in ipairs(pool.quests) do
        local questID = type(entry) == "table" and entry.id or entry
        if self:IsCompleted(questID) then
            return true, questID
        end
    end
    return false
end

function Quests:PoolGold(pool)
    -- Der gelernte Betrag irgendeiner Quest des Pools gilt fuer den Pool:
    -- Sie zahlen alle gleich.
    for _, entry in ipairs(pool.quests) do
        local questID = type(entry) == "table" and entry.id or entry
        local gold, measured = self:GetGold(questID, nil)
        if measured then
            return gold, true
        end
    end
    return pool.gold, false
end

function Quests:IsPoolAvailable(pool)
    if playerLevel() < (pool.minLevel or 1) then return false end
    return meetsSkill(pool)
end

-- Einzelquest eines nicht-oneOf-Pools: Vorquest-Kette pruefen.
function Quests:IsQuestUnlocked(quest)
    local viaQuestie = questieSaysDoable(quest.id)
    if viaQuestie ~= nil then
        -- Questie meldet bereits abgegebene Dailies als nicht machbar; das
        -- ist hier kein Grund, die Zeile zu verstecken.
        if viaQuestie then return true end
        return self:IsCompleted(quest.id) == true
    end
    if not quest.pre then return true end
    return self:IsCompleted(quest.pre) ~= false
end

-- ---------------------------------------------------------------------------
-- Questlog-Bewertung: was bringen die Quests, die schon angenommen sind?
-- Das braucht kein Questie - nur die Belohnungsdaten des Clients.
-- ---------------------------------------------------------------------------

local function logEntryInfo(index)
    if C_QuestLog and C_QuestLog.GetInfo then
        local info = C_QuestLog.GetInfo(index)
        if info then
            return info.title, info.isHeader == true, info.questID, info.level
        end
        return nil
    end
    -- Aeltere Signaturen unterscheiden sich in der Reihenfolge; Titel und
    -- Kopfzeilen-Flag stehen aber stabil. Ohne questID entfaellt nur die
    -- Abgabebereit-Markierung, nicht die Bewertung.
    local title, level, _, _, isHeader = GetQuestLogTitle(index)
    return title, isHeader == true or isHeader == 1, nil, level
end

-- Wert der Belohnungen einer im Log ausgewaehlten Quest.
function Quests:SelectedRewardValue()
    local Prices = GCP.Prices
    local money = (type(GetQuestLogRewardMoney) == "function" and GetQuestLogRewardMoney()) or 0
    local itemValue, best, bestName = 0, 0, nil

    local fixedCount = (type(GetNumQuestLogRewards) == "function" and GetNumQuestLogRewards()) or 0
    for index = 1, fixedCount do
        local link = GetQuestLogItemLink and GetQuestLogItemLink("reward", index)
        local itemID = link and tonumber(tostring(link):match("item:(%d+)"))
        if itemID then
            local _, _, count = GetQuestLogRewardInfo(index)
            local price = Prices:GetPlanningPrice(itemID)
            if price then
                itemValue = itemValue + Prices:NetAuction(price) * (count or 1)
            end
        end
    end

    -- Bei Auswahlbelohnungen zaehlt nur die wertvollste: mehr gibt es nicht.
    local choiceCount = (type(GetNumQuestLogChoices) == "function" and GetNumQuestLogChoices()) or 0
    for index = 1, choiceCount do
        local link = GetQuestLogItemLink and GetQuestLogItemLink("choice", index)
        local itemID = link and tonumber(tostring(link):match("item:(%d+)"))
        if itemID then
            local _, _, count = GetQuestLogChoiceInfo(index)
            local price = Prices:GetPlanningPrice(itemID)
            local vendor = Prices:GetVendorPrice(itemID)
            local value = price and Prices:NetAuction(price) or vendor or 0
            value = value * (count or 1)
            if value > best then
                best = value
                bestName = GetItemInfoCompat(itemID)
            end
        end
    end

    return money + itemValue + best, money, itemValue + best, bestName
end

-- Alle angenommenen Quests mit ihrem Gesamtwert, wertvollste zuerst.
function Quests:BuildLogReport()
    local rows = {}
    if type(GetNumQuestLogEntries) ~= "function" then
        return { rows = rows, total = 0 }
    end
    local numEntries = GetNumQuestLogEntries()
    local previousSelection = (type(GetQuestLogSelection) == "function") and GetQuestLogSelection() or nil
    local total = 0
    for index = 1, numEntries do
        local title, isHeader, questID = logEntryInfo(index)
        if title and not isHeader then
            SelectQuestLogEntry(index)
            local value, money, itemValue, bestName = self:SelectedRewardValue()
            if value > 0 then
                local isComplete = nil
                if questID and C_QuestLog and C_QuestLog.IsComplete then
                    isComplete = C_QuestLog.IsComplete(questID)
                end
                rows[#rows + 1] = {
                    title = title,
                    questID = questID,
                    value = value,
                    money = money,
                    itemValue = itemValue,
                    rewardName = bestName,
                    isComplete = isComplete,
                }
                total = total + value
            end
        end
    end
    if previousSelection and previousSelection > 0 then
        SelectQuestLogEntry(previousSelection)
    end
    table.sort(rows, function(a, b)
        if (a.isComplete == true) ~= (b.isComplete == true) then
            return a.isComplete == true
        end
        return a.value > b.value
    end)
    return { rows = rows, total = total }
end

-- ---------------------------------------------------------------------------
-- Ereignisse
-- ---------------------------------------------------------------------------

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("QUEST_TURNED_IN")
eventFrame:SetScript("OnEvent", function(_, _, questID, _, moneyReward)
    if not GCP.db then return end
    Quests:LearnGold(questID, moneyReward)
    if GCP.UI then GCP.UI:RefreshIfShown() end
end)
