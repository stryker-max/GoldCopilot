local addonName, GCP = ...

_G.GoldCopilot = GCP

GCP.addonName = addonName
GCP.initialized = false

function GCP:Print(message)
    if DEFAULT_CHAT_FRAME then
        DEFAULT_CHAT_FRAME:AddMessage(GCP.Constants.COLOR_PREFIX .. tostring(message))
    end
end

-- Heutiger Kalendertag als Schluessel fuer Tagesplan und Goldverlauf. Der Reset
-- folgt bewusst dem Kalendertag der lokalen Uhr statt dem Server-Daily-Reset:
-- Fuer eine Checkliste zaehlt "heute" so, wie der Spieler den Tag erlebt.
function GCP:Today()
    return date("%Y-%m-%d")
end

function GCP:EnsureDB()
    GoldCopilotDB = GoldCopilotDB or {}
    local db = GoldCopilotDB
    db.version = GCP.Constants.VERSION
    db.options = db.options or {}
    if db.options.priceSource == nil then db.options.priceSource = "auto" end
    if db.options.hideBound == nil then db.options.hideBound = false end
    if db.options.minRoadmapValue == nil then
        db.options.minRoadmapValue = GCP.Constants.MIN_ROADMAP_VALUE
    end
    if db.options.dailyGoal == nil then
        db.options.dailyGoal = GCP.Constants.DEFAULT_DAILY_GOAL
    end
    if db.options.keepConsumables == nil then db.options.keepConsumables = true end
    db.options.ignored = db.options.ignored or {}
    db.questGold = db.questGold or {}
    db.roadmap = db.roadmap or {}
    db.roadmap.checked = db.roadmap.checked or {}
    db.roadmap.baseline = db.roadmap.baseline or {}
    db.goldHistory = db.goldHistory or {}
    db.priceHistory = db.priceHistory or {}
    self.db = db
    self:ResetRoadmapIfNewDay()
    return db
end

function GCP:ResetRoadmapIfNewDay()
    local today = self:Today()
    if self.db.roadmap.day ~= today then
        self.db.roadmap.day = today
        self.db.roadmap.checked = {}
        -- Die Baselines sind die Bestaende bei der ersten Plan-Erstellung des
        -- Tages; daran erkennt der Plan spaeter von selbst erledigte Aufgaben.
        self.db.roadmap.baseline = {}
    end
end

-- Haelt je Kalendertag den hoechsten gesehenen Goldstand fest. Accountweit,
-- sofern Syndicator die anderen Charaktere kennt; sonst nur der eigene.
function GCP:RecordGold()
    if not self.db then return end
    local total = GetMoney() or 0
    local ok, sum = pcall(function()
        if not (Syndicator and Syndicator.API) then return nil end
        local mine = Syndicator.API.GetCurrentCharacter()
        local accountSum = 0
        for _, name in ipairs(Syndicator.API.GetAllCharacters() or {}) do
            if name ~= mine then
                local char = Syndicator.API.GetByCharacterFullName(name)
                local money = char and char.money or (char and char.details and char.details.money)
                if type(money) == "number" then
                    accountSum = accountSum + money
                end
            end
        end
        return accountSum
    end)
    if ok and type(sum) == "number" then
        total = total + sum
    end
    local today = self:Today()
    local previous = self.db.goldHistory[today]
    if not previous or total > previous then
        self.db.goldHistory[today] = total
    end
    -- Der Verlauf soll die SavedVariables nicht endlos fuellen: 120 Tage reichen
    -- fuer jede Trendanzeige.
    local cutoff = date("%Y-%m-%d", time() - 120 * 86400)
    for day in pairs(self.db.goldHistory) do
        if day < cutoff then
            self.db.goldHistory[day] = nil
        end
    end
end

-- Berufe und Sammelskills aus dem Fertigkeitenfenster; Classic kennt kein
-- GetProfessions. Rueckgabe: Skillname -> Rang.
function GCP:GetKnownSkills()
    local skills = {}
    if type(GetNumSkillLines) ~= "function" then return skills end
    for index = 1, GetNumSkillLines() do
        local name, isHeader, _, rank = GetSkillLineInfo(index)
        if name and not isHeader then
            skills[name] = rank or 0
        end
    end
    return skills
end

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:RegisterEvent("PLAYER_LOGIN")
eventFrame:RegisterEvent("PLAYER_MONEY")
eventFrame:SetScript("OnEvent", function(_, event, arg1)
    if event == "ADDON_LOADED" and arg1 == addonName then
        GCP:EnsureDB()
        GCP.initialized = true
    elseif event == "PLAYER_LOGIN" then
        if not GCP.db then GCP:EnsureDB() end
        GCP:RecordGold()
        GCP.Prices:RecordObservedPrices()
        GCP:Print("bereit. /gold öffnet deinen Gold-Berater.")
    elseif event == "PLAYER_MONEY" then
        if GCP.db then GCP:RecordGold() end
    end
end)

SLASH_GOLDCOPILOT1 = "/gold"
SLASH_GOLDCOPILOT2 = "/goldcopilot"
SlashCmdList["GOLDCOPILOT"] = function(msg)
    msg = (msg or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
    if not GCP.db then GCP:EnsureDB() end
    if msg == "reset" then
        GCP.db.roadmap.day = nil
        GCP:ResetRoadmapIfNewDay()
        GCP:Print("Tagesplan zurückgesetzt.")
        if GCP.UI then GCP.UI:Refresh() end
    elseif msg == "quelle" or msg == "source" then
        local source = GCP.Prices:GetActiveSourceLabel()
        GCP:Print("aktive Preisquelle: " .. source)
    else
        if GCP.UI then
            GCP.UI:Toggle()
        end
    end
end
