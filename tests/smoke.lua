-- Smoke-Test fuer Gold Copilot: laedt die Addon-Dateien in einer minimalen
-- WoW-Umgebung (fengari, Lua 5.3) und prueft die Kernlogik. Start ueber
-- "node tests/run.mjs" aus dem Repo-Wurzelverzeichnis.

unpack = unpack or table.unpack

-- ---------------------------------------------------------------------------
-- Testgeruest
-- ---------------------------------------------------------------------------

local passed, failed = 0, 0
local function expect(condition, label)
    if condition then
        passed = passed + 1
    else
        failed = failed + 1
        print("FEHLSCHLAG: " .. label)
    end
end

local function expectEqual(actual, wanted, label)
    expect(actual == wanted, string.format("%s (erwartet %s, erhalten %s)",
        label, tostring(wanted), tostring(actual)))
end

-- ---------------------------------------------------------------------------
-- WoW-Umgebung
-- ---------------------------------------------------------------------------

local mockNow = os.time({ year = 2026, month = 8, day = 8, hour = 12 })

function date(fmt, t)
    return os.date(fmt, t or mockNow)
end

-- Wie in WoW: time() ohne Argument ist "jetzt", time(tabelle) rechnet ein
-- Datum in einen Zeitstempel um. Die Market Engine braucht die zweite Form,
-- um die Tages-Preishistorie aus 0.4 zu uebernehmen.
function time(spec)
    if type(spec) == "table" then
        return os.time(spec)
    end
    return mockNow
end

function GetTime()
    return mockNow
end

-- Sekunden bis zum naechsten Daily-Reset des Servers. Der Tagesplan richtet
-- sich danach; Goldverlauf und Preishistorie bewusst nicht.
local questResetSeconds = 3600
function GetQuestResetTime()
    return questResetSeconds
end

function GetMoney()
    return 100000
end

function UnitLevel()
    return 70
end

local chatLog = {}
DEFAULT_CHAT_FRAME = { AddMessage = function(_, message) chatLog[#chatLog + 1] = message end }
SlashCmdList = {}
UIParent = {}
UISpecialFrames = {}

-- Timer sammeln statt verwerfen: Der Debounce der Market Engine laesst sich nur
-- pruefen, wenn der Test entscheidet, wann ein Timer ablaeuft. Wer flushTimers
-- nicht aufruft, sieht dasselbe Verhalten wie vorher - naemlich keines.
local timerQueue = {}
C_Timer = {
    After = function(_, callback)
        timerQueue[#timerQueue + 1] = callback
    end,
}
local function flushTimers()
    local pending = timerQueue
    timerQueue = {}
    for _, callback in ipairs(pending) do
        callback()
    end
    return #pending
end

local frameMeta = {
    __index = function()
        return function() end
    end,
}
function CreateFrame()
    return setmetatable({}, frameMeta)
end

function tinsert(list, value)
    list[#list + 1] = value
end

-- GetItemInfo-Reihenfolge: name, link, quality, itemLevel, minLevel, type,
-- subType, stackCount, equipLoc, icon, sellPrice, classID, subClassID,
-- bindType. Die meisten Attrappen enden bei classID - genau wie ein Client mit
-- kaltem Item-Cache, der die Bindungsart noch nicht kennt.
local items = {
    [21884] = { "Urfeuer", "item:21884", 1, 65, 0, "Handwerkswaren", "Elementar", 20, "", 101, 0, 7 },
    [21885] = { "Urwasser", "item:21885", 1, 65, 0, "Handwerkswaren", "Elementar", 20, "", 102, 0, 7 },
    [22451] = { "Urluft", "item:22451", 1, 65, 0, "Handwerkswaren", "Elementar", 20, "", 103, 0, 7 },
    [22452] = { "Urerde", "item:22452", 1, 65, 0, "Handwerkswaren", "Elementar", 20, "", 104, 0, 7 },
    [22456] = { "Urschatten", "item:22456", 1, 65, 0, "Handwerkswaren", "Elementar", 20, "", 105, 0, 7 },
    [22457] = { "Urmana", "item:22457", 1, 65, 0, "Handwerkswaren", "Elementar", 20, "", 106, 0, 7 },
    [21886] = { "Urleben", "item:21886", 1, 65, 0, "Handwerkswaren", "Elementar", 20, "", 107, 0, 7 },
    [22574] = { "Feuerpartikel", "item:22574", 1, 65, 0, "Handwerkswaren", "Elementar", 20, "", 108, 0, 7 },
    [22578] = { "Wasserpartikel", "item:22578", 1, 65, 0, "Handwerkswaren", "Elementar", 20, "", 109, 0, 7 },
    [22572] = { "Luftpartikel", "item:22572", 1, 65, 0, "Handwerkswaren", "Elementar", 20, "", 110, 0, 7 },
    [22573] = { "Erdpartikel", "item:22573", 1, 65, 0, "Handwerkswaren", "Elementar", 20, "", 111, 0, 7 },
    [22577] = { "Schattenpartikel", "item:22577", 1, 65, 0, "Handwerkswaren", "Elementar", 20, "", 112, 0, 7 },
    [22576] = { "Manapartikel", "item:22576", 1, 65, 0, "Handwerkswaren", "Elementar", 20, "", 113, 0, 7 },
    [22575] = { "Lebenspartikel", "item:22575", 1, 65, 0, "Handwerkswaren", "Elementar", 20, "", 114, 0, 7 },
    [23571] = { "Urmacht", "item:23571", 2, 70, 0, "Handwerkswaren", "Elementar", 20, "", 115, 0, 7 },
    [23425] = { "Adamantiterz", "item:23425", 1, 65, 0, "Handwerkswaren", "Metall", 20, "", 116, 25, 7 },
    [22785] = { "Teufelsgras", "item:22785", 1, 60, 0, "Handwerkswaren", "Kraut", 20, "", 117, 5, 7 },
    [21877] = { "Netherstoff", "item:21877", 1, 60, 0, "Handwerkswaren", "Stoff", 20, "", 118, 30, 7 },
    [10938] = { "Niedere Magieessenz", "item:10938", 2, 15, 0, "Handwerkswaren", "Verzauberung", 10, "", 119, 0, 7 },
    [10939] = { "Hohe Magieessenz", "item:10939", 2, 20, 0, "Handwerkswaren", "Verzauberung", 10, "", 120, 0, 7 },
    [777] = { "Grüne Testklinge", "item:777", 2, 30, 25, "Waffe", "Schwerter", 1, "INVTYPE_WEAPON", 121, 1500, 2 },
    [888] = { "Gebundene Testschulter", "item:888", 3, 40, 35, "Rüstung", "Stoff", 1, "INVTYPE_SHOULDER", 122, 5000, 4 },
    [999] = { "Händlerliebling", "item:999", 1, 10, 0, "Handwerkswaren", "Sonstiges", 20, "", 123, 2000, 7 },
    [3000] = { "Grauer Plunder", "item:3000", 0, 5, 0, "Müll", "Müll", 5, "", 124, 1234, 15 },
    [555] = { "Wertloses Questteil", "item:555", 1, 1, 0, "Quest", "Quest", 1, "", 125, 0, 12 },
    [60001] = { "Knusperschlange", "item:60001", 1, 70, 0, "Verbrauchbar", "Essen", 20, "", 126, 2, 0 },
    [60002] = { "Schlangenfleisch", "item:60002", 1, 65, 0, "Handwerkswaren", "Fleisch", 20, "", 127, 1, 7 },
    [60003] = { "Manatrank der Auchenai", "item:60003", 1, 70, 0, "Verbrauchbar", "Trank", 20, "", 128, 200, 0 },
    -- Questbelohnungen: eine ohne jeden Marktpreis, eine beim Aufheben
    -- gebundene (bindType 1) trotz vorhandenem Marktpreis.
    [4244] = { "Händlerbrosche", "item:4244", 2, 60, 0, "Rüstung", "Schmuck", 1, "INVTYPE_FINGER", 129, 30000, 4 },
    [4245] = { "Siegel des Prüfers", "item:4245", 3, 70, 0, "Rüstung", "Stoff", 1, "INVTYPE_HEAD", 130, 4000, 4, 1, 1 },
}

function GetItemInfo(item)
    local id = tonumber(item)
    if not id then
        id = tonumber(tostring(item):match("item:(%d+)"))
    end
    local entry = items[id]
    if not entry then return nil end
    return entry[1], entry[2], entry[3], entry[4], entry[5], entry[6],
        entry[7], entry[8], entry[9], entry[10], entry[11], entry[12],
        entry[13], entry[14]
end

C_Item = { GetItemInfo = GetItemInfo }

-- Marktpreise (Kupfer) der Auctionator-Attrappe; TSM kennt bewusst andere
-- Items, damit die Quellen-Reihenfolge sichtbar wird.
local marketPrices = {
    [21884] = 1300, [21885] = 1100, [22451] = 1200, [22452] = 900,
    [22456] = 1400, [22457] = 1000, [21886] = 800,
    [22574] = 100, [22578] = 90, [22572] = 105, [22573] = 70,
    [22577] = 120, [22576] = 95, [22575] = 60,
    [23571] = 250000,
    [23425] = 50000,
    [22785] = 800,
    [21877] = 60,
    [10938] = 100, [10939] = 400,
    [4245] = 100000,
    [777] = 10000,
    [888] = 90000,
    [999] = 1000,
    [60001] = 8000,
    [60002] = 2000,
    [60003] = 60000,
}
local tsmPrices = {
    [4242] = 7777,
    [21877] = 55,
}
local disenchantPrices = {
    ["item:777"] = 15000,
    ["item:888"] = 20000,
}
local scanAgeByItem = { [21877] = 0 }

-- Auctionator meldet Datenbank-Updates ueber RegisterForDBUpdate(callerID,
-- callback). Die Attrappe merkt sich die Registrierungen, damit der Test einen
-- Vollscan nachstellen kann - der feuert das Ereignis viele Male hintereinander.
local dbUpdateCallbacks = {}
local dbUpdateRegistrations = {}

Auctionator = {
    API = {
        v1 = {
            GetAuctionPriceByItemID = function(_, itemID)
                return marketPrices[itemID]
            end,
            GetDisenchantPriceByItemLink = function(_, itemLink)
                return disenchantPrices[itemLink]
            end,
            GetAuctionAgeByItemID = function(_, itemID)
                return scanAgeByItem[itemID]
            end,
            RegisterForDBUpdate = function(callerID, callback)
                assert(type(callerID) == "string" and callerID ~= "",
                    "RegisterForDBUpdate erwartet eine callerID")
                assert(type(callback) == "function",
                    "RegisterForDBUpdate erwartet eine Callback-Funktion")
                dbUpdateRegistrations[#dbUpdateRegistrations + 1] = callerID
                dbUpdateCallbacks[#dbUpdateCallbacks + 1] = callback
            end,
        },
    },
}

local function fireAuctionatorDBUpdate(times)
    for _ = 1, times or 1 do
        for _, callback in ipairs(dbUpdateCallbacks) do
            callback()
        end
    end
end

TSM_API = {
    GetCustomPriceValue = function(priceString, itemString)
        assert(priceString == "dbmarket")
        local id = tonumber(tostring(itemString):match("^i:(%d+)$"))
        return tsmPrices[id]
    end,
}

-- Taschen des eingeloggten Charakters (neue Tabellen-Signatur des Clients).
local bagContents = {
    [0] = {
        { itemID = 22574, stackCount = 25, hyperlink = "item:22574" },
        { itemID = 777, stackCount = 1, hyperlink = "item:777" },
        { itemID = 3000, stackCount = 5, hyperlink = "item:3000" },
    },
    [1] = {
        { itemID = 888, stackCount = 1, hyperlink = "item:888", isBound = true },
        { itemID = 999, stackCount = 10, hyperlink = "item:999" },
        { itemID = 555, stackCount = 1, hyperlink = "item:555" },
    },
}

C_Container = {
    GetContainerNumSlots = function(bag)
        return bagContents[bag] and #bagContents[bag] or 0
    end,
    GetContainerItemInfo = function(bag, slot)
        return bagContents[bag] and bagContents[bag][slot]
    end,
}

-- Syndicator kennt zusaetzlich Bank, Post und einen Bankchar.
local syndicatorCharacters = {
    ["Falco-Everlook"] = {
        details = { money = 500000 },
        bags = {
            { { itemID = 22574, itemCount = 25, itemLink = "item:22574" },
              { itemID = 60002, itemCount = 5, itemLink = "item:60002" },
              { itemID = 60003, itemCount = 40, itemLink = "item:60003" } },
        },
        bank = {
            { { itemID = 23425, itemCount = 40, itemLink = "item:23425" } },
        },
        mail = {},
        auctions = {},
    },
    ["Bankchar-Everlook"] = {
        details = { money = 250000 },
        bags = {},
        bank = {
            { { itemID = 23425, itemCount = 20, itemLink = "item:23425" } },
            { { itemID = 10938, itemCount = 9, itemLink = "item:10938" } },
        },
        mail = {
            { itemID = 22785, itemCount = 40, itemLink = "item:22785" },
        },
        auctions = {},
    },
}

Syndicator = {
    API = {
        GetAllCharacters = function()
            return { "Falco-Everlook", "Bankchar-Everlook" }
        end,
        GetByCharacterFullName = function(name)
            return syndicatorCharacters[name]
        end,
        GetCurrentCharacter = function()
            return "Falco-Everlook"
        end,
    },
}

local knownSpells = { [28566] = true, [29688] = true, [17187] = true }
function IsPlayerSpell(spellID)
    return knownSpells[spellID] == true
end

local cooldowns = {
    [29688] = { start = mockNow - 100, duration = 86400 },
}
function GetSpellCooldown(spellID)
    local cd = cooldowns[spellID]
    if cd then
        return cd.start, cd.duration, 1
    end
    return 0, 0, 1
end

-- Quest-Flags: Vorquests der Dailies sind abgeschlossen, 11080 ist heute
-- schon erledigt.
local completedQuests = {
    [11010] = true, [11026] = true, [11065] = true,
    [11058] = true, [11098] = true,
    [11080] = true,
}

-- Questlog: eine abgabebereite Quest mit Gold- und Auswahlbelohnung, eine
-- laufende, dazu eine Kopfzeile.
local questLog = {
    { title = "Zone", isHeader = true },
    { title = "Die Kiste des Prospektors", questID = 90001, complete = true,
      money = 80000, choices = { { item = "item:23425", count = 4 } } },
    { title = "Noch nicht fertig", questID = 90002, complete = false,
      money = 50000 },
}
local selectedLogIndex = 1

C_QuestLog = {
    IsQuestFlaggedCompleted = function(questID)
        return completedQuests[questID] == true
    end,
    GetInfo = function(index)
        local entry = questLog[index]
        if not entry then return nil end
        return { title = entry.title, isHeader = entry.isHeader == true,
                 questID = entry.questID, level = 70 }
    end,
    IsComplete = function(questID)
        for _, entry in ipairs(questLog) do
            if entry.questID == questID then return entry.complete == true end
        end
        return false
    end,
}

function GetNumQuestLogEntries() return #questLog end
function GetQuestLogSelection() return selectedLogIndex end
function SelectQuestLogEntry(index) selectedLogIndex = index end
function GetQuestLogRewardMoney()
    local entry = questLog[selectedLogIndex]
    return entry and entry.money or 0
end
function GetNumQuestLogRewards()
    local entry = questLog[selectedLogIndex]
    return entry and entry.rewards and #entry.rewards or 0
end
function GetQuestLogRewardInfo(index)
    local entry = questLog[selectedLogIndex]
    local reward = entry and entry.rewards and entry.rewards[index]
    return "Belohnung", nil, reward and reward.count or 1
end
function GetNumQuestLogChoices()
    local entry = questLog[selectedLogIndex]
    return entry and entry.choices and #entry.choices or 0
end
function GetQuestLogChoiceInfo(index)
    local entry = questLog[selectedLogIndex]
    local choice = entry and entry.choices and entry.choices[index]
    return "Auswahl", nil, choice and choice.count or 1
end
function GetQuestLogItemLink(kind, index)
    local entry = questLog[selectedLogIndex]
    local list = kind == "choice" and entry.choices or entry.rewards
    local item = list and list[index]
    return item and item.item
end

-- Fertigkeitenfenster: Sammelberufe des Charakters.
local skillLines = {
    { "Berufe", true, 0 },
    { "Kräuterkunde", false, 375 },
    { "Bergbau", false, 375 },
    { "Kürschnerei", false, 300 },
    { "Kochkunst", false, 375 },
}
function GetNumSkillLines()
    return #skillLines
end
function GetSkillLineInfo(index)
    local line = skillLines[index]
    if not line then return nil end
    return line[1], line[2], nil, line[3]
end

-- Berufsfenster-Attrappe (Kochkunst): ein Header, ein sauberes Rezept, ein
-- Eintrag ohne Item-Link, der uebersprungen werden muss.
local tradeSkills = {
    { name = "Feuerküche", type = "header" },
    { name = "Knusperschlange", type = "optimal", product = "item:60001",
      made = { 1, 1 }, mats = { { "item:60002", 1 } } },
    { name = "Geheimrezept", type = "easy", product = nil,
      made = { 1, 1 }, mats = { { "item:60002", 2 } } },
}
function GetTradeSkillLine() return "Kochkunst", 375, 375 end
function GetNumTradeSkills() return #tradeSkills end
function GetTradeSkillInfo(index)
    local entry = tradeSkills[index]
    if not entry then return nil end
    return entry.name, entry.type, 0
end
function GetTradeSkillItemLink(index)
    local entry = tradeSkills[index]
    return entry and entry.product
end
function GetTradeSkillNumMade(index)
    local entry = tradeSkills[index]
    if entry and entry.made then return entry.made[1], entry.made[2] end
    return 1, 1
end
function GetTradeSkillNumReagents(index)
    local entry = tradeSkills[index]
    return entry and entry.mats and #entry.mats or 0
end
function GetTradeSkillReagentInfo(index, reagent)
    local mat = tradeSkills[index].mats[reagent]
    return "Zutat", nil, mat[2], 0
end
function GetTradeSkillReagentItemLink(index, reagent)
    return tradeSkills[index].mats[reagent][1]
end

-- ---------------------------------------------------------------------------
-- Addon-Dateien laden (wie WoW: jede Datei erhaelt addonName und Namensraum)
-- ---------------------------------------------------------------------------

local GCP = {}
local files = {
    "Constants.lua", "Core.lua",
    "Knowledge/Knowledge.lua", "Knowledge/Phases.lua", "Knowledge/Items.lua",
    "Knowledge/Recipes.lua", "Knowledge/Catalysts.lua",
    "Prices.lua", "Inventory.lua",
    "Advisor.lua", "Flips.lua", "Crafts.lua", "Market.lua", "Ledger.lua", "Opportunity.lua",
    "Future.lua",
    "Quests.lua",
    "Roadmap.lua", "UI.lua",
}
for _, file in ipairs(files) do
    local chunk, err = loadfile(file)
    assert(chunk, "Ladefehler in " .. file .. ": " .. tostring(err))
    chunk("GoldCopilot", GCP)
end

GCP:EnsureDB()
expectEqual(GCP.db.options.minRoadmapValue, GCP.Constants.MIN_ROADMAP_VALUE,
    "Mindestgewinn startet auf dem Standardwert")
-- Fuer die Basistests soll nichts unter den Tisch fallen.
GCP.db.options.minRoadmapValue = 0

-- ---------------------------------------------------------------------------
-- Preise
-- ---------------------------------------------------------------------------

local price, source = GCP.Prices:GetMarketPrice(21884)
expectEqual(price, 1300, "Auctionator liefert den Marktpreis")
expectEqual(source, "Auctionator", "Quelle Auctionator wird benannt")

price, source = GCP.Prices:GetMarketPrice(4242)
expectEqual(price, 7777, "TSM springt ein, wenn Auctionator nichts kennt")
expectEqual(source, "TSM", "Quelle TSM wird benannt")

GCP.db.options.priceSource = "tsm"
price = GCP.Prices:GetMarketPrice(21877)
expectEqual(price, 55, "Erzwungene TSM-Quelle nutzt dbmarket")
GCP.db.options.priceSource = "auctionator"
price = GCP.Prices:GetMarketPrice(4242)
expectEqual(price, nil, "Erzwungenes Auctionator kennt reine TSM-Items nicht")
GCP.db.options.priceSource = "auto"

expectEqual(GCP.Prices:NetAuction(10000), 9500, "AH-Abzug betraegt 5 Prozent")
expectEqual(GCP.Prices:FormatMoney(123456), "12g 34s 56c", "Geldformat ohne Client-Symbole")
expectEqual(GCP.Prices:FormatGold(1234500), "123 g", "Kompakte Goldangabe rundet")

-- Median: gestriger Ausreisser nach oben veraendert den Planungspreis nicht.
GCP.Prices:RecordObservedPrices()
expectEqual(GCP.db.priceHistory[21884][GCP:Today()], 1300,
    "Beobachtete Preise landen in der Historie")
GCP.db.priceHistory[21884][date("%Y-%m-%d", mockNow - 86400)] = 999000
local planning, days = GCP.Prices:GetPlanningPrice(21884)
expectEqual(planning, 1300, "Median (untere Mitte) ignoriert den Ausreisser")
expectEqual(days, 2, "Beide Tageswerte flossen ein")
GCP.db.priceHistory[21884] = nil
planning = GCP.Prices:GetPlanningPrice(21884)
expectEqual(planning, 1300, "Ohne Historie gilt der Momentanpreis")

-- ---------------------------------------------------------------------------
-- Inventar
-- ---------------------------------------------------------------------------

local bags = GCP.Inventory:ScanBags({})
expectEqual(bags[22574].count, 25, "Taschen-Scan zaehlt Stapel")
expectEqual(bags[888].bound, true, "Gebundene Items werden markiert")

local account, accountWide = GCP.Inventory:ScanAccount()
expectEqual(accountWide, true, "Syndicator wird erkannt")
expectEqual(account[23425].count, 60, "Bankbestaende beider Charaktere summieren sich")
expectEqual(account[22785].count, 40, "Postfach wird mitgezaehlt")
expectEqual(account[999].count, 10, "Live-Taschen fuellen Items auf, die Syndicator fehlen")
expectEqual(account[22574].count, 25, "Von Syndicator gezaehlte Taschen werden nicht doppelt addiert")

-- ---------------------------------------------------------------------------
-- Verkaufsberater
-- ---------------------------------------------------------------------------

local report = GCP.Advisor:BuildReport("account", "all")
local byID = {}
for _, row in ipairs(report.rows) do byID[row.itemID] = row end

expectEqual(byID[23425].channel, "AH", "Handelsware mit gutem Marktpreis gehoert ins AH")
expectEqual(byID[23425].totalValue, 47500 * 60, "AH-Wert rechnet netto mal Menge")
expectEqual(byID[3000].channel, "Händler", "Graue Items gehen zum Haendler")
expectEqual(byID[777].channel, "Entzaubern", "Entzaubern schlaegt schwachen AH-Preis")
expectEqual(byID[888].channel, "Entzaubern", "Gebundenes darf nicht ins AH")
expectEqual(byID[999].channel, "Händler", "Haendlerpreis schlaegt schwachen AH-Preis")
expectEqual(byID[555], nil, "Wertloses taucht gar nicht auf")
expectEqual(report.rows[1].itemID, 23425, "Sortierung stellt den groessten Posten nach oben")

local matsOnly = GCP.Advisor:BuildReport("account", "mats")
local matsHasGear = false
for _, row in ipairs(matsOnly.rows) do
    if row.itemID == 777 then matsHasGear = true end
end
expectEqual(matsHasGear, false, "Mats-Filter blendet Ausruestung aus")

-- Ignorieren per Doppelklick und der Gebunden-Filter.
GCP.Advisor:ToggleIgnored(999)
report = GCP.Advisor:BuildReport("account", "all")
byID = {}
for _, row in ipairs(report.rows) do byID[row.itemID] = row end
expectEqual(byID[999], nil, "Ignorierte Items verschwinden aus der Liste")
expectEqual(report.ignoredCount, 1, "Ignorierte werden gezaehlt")

local ignoredView = GCP.Advisor:BuildReport("account", "all", true)
expectEqual(#ignoredView.rows, 1, "Ignoriert-Ansicht zeigt genau die Ausgeblendeten")
expectEqual(ignoredView.rows[1].itemID, 999, "Ignoriert-Ansicht zeigt das richtige Item")
GCP.Advisor:ToggleIgnored(999)

GCP.db.options.hideBound = true
report = GCP.Advisor:BuildReport("account", "all")
byID = {}
for _, row in ipairs(report.rows) do byID[row.itemID] = row end
expectEqual(byID[888], nil, "Gebunden-Filter blendet gebundene Items aus")
GCP.db.options.hideBound = false

-- ---------------------------------------------------------------------------
-- Flips
-- ---------------------------------------------------------------------------

local flips = GCP.Flips:Build()
local fireRow
for _, row in ipairs(flips.motes) do
    if row.primalID == 21884 then fireRow = row end
end
expect(fireRow ~= nil, "Feuer-Flip vorhanden")
expectEqual(fireRow.buyProfit, 1235 - 1000, "Kauf-Flip: netto Ur-Partikel minus 10 Motes brutto")
expectEqual(fireRow.combineDelta, 1235 - 950, "Kombinieren-Delta gegen Einzelverkauf")
expectEqual(fireRow.ownedMotes, 25, "Eigene Motes werden gezaehlt")
expectEqual(fireRow.ownedCombines, 2, "25 Motes ergeben 2 Kombinationen")

local magicRow
for _, row in ipairs(flips.essences) do
    if row.greaterID == 10939 then magicRow = row end
end
expect(magicRow ~= nil, "Magieessenz-Flip vorhanden")
expectEqual(magicRow.direction, "up", "3:1 nach oben ist hier profitabel")
expectEqual(magicRow.profit, 380 - 300, "Essenzgewinn rechnet mit AH-Abzug")

-- ---------------------------------------------------------------------------
-- Rezept-Scanner
-- ---------------------------------------------------------------------------

GCP.Crafts:ScanTradeSkills()
expect(GCP.db.recipes and GCP.db.recipes["Kochkunst"], "Berufsscan legt Rezepte ab")
expectEqual(#GCP.db.recipes["Kochkunst"].list, 1,
    "Header und Rezepte ohne Item-Link werden uebersprungen")
local recipe = GCP.db.recipes["Kochkunst"].list[1]
expectEqual(recipe.product, 60001, "Produkt-ID stammt aus dem Item-Link")
expectEqual(recipe.mats[1][1], 60002, "Zutaten-ID stammt aus dem Reagenz-Link")

local craftReport = GCP.Crafts:BuildReport()
expectEqual(#craftReport.rows, 1, "Craft-Radar bewertet das Rezept")
local craftRow = craftReport.rows[1]
expectEqual(craftRow.profit, 7600 - 2000, "Craft-Gewinn: Erloes netto minus Zutaten")
expectEqual(craftRow.craftable, 5, "Machbarkeit folgt dem Accountbestand")

-- ---------------------------------------------------------------------------
-- Roadmap
-- ---------------------------------------------------------------------------

local plan = GCP.Roadmap:Generate()
local keys = {}
for _, entry in ipairs(plan.entries) do keys[entry.key] = entry end

expectEqual(keys["scan"], nil, "Frischer Scan erzeugt keinen Scan-Eintrag")
expect(keys["cd:28566"] ~= nil, "Bereiter Transmute-Cooldown wird vorgeschlagen")
expect(keys["cd:29688"] ~= nil, "Laufender Cooldown bleibt sichtbar")
expect(keys["cd:29688"].note:find("bereit in") ~= nil, "Laufender Cooldown nennt die Restzeit")
expect(keys["sell:23425"] ~= nil, "Groesster Verkaufsposten steht im Tagesplan")
expect(keys["craft:60001"] ~= nil, "Bestes Craft-Rezept steht im Tagesplan")
expectEqual(keys["craft:60001"].value, 5600 * 5, "Craft-Wert rechnet Gewinn mal Machbarkeit")
expect(keys["farm:23425"] ~= nil, "Farm-Tipp vorhanden")
expect(keys["farm:23425"].note:find("je Stunde") ~= nil, "Farm-Tipp rechnet in Gold je Stunde")
expectEqual(keys["farm:23425"].value, 50000 * 40, "Farmwert ist Preis mal Stundenrate")

expect(keys["daily:11023"] ~= nil, "Freigeschaltete Daily wird vorgeschlagen")
expectEqual(keys["daily:11080"].done, true, "Bereits gemachte Daily ist von selbst abgehakt")
expectEqual(keys["daily:11080"].autoDone, true, "Daily-Erkennung laeuft ueber das Quest-Flag")

-- ---------------------------------------------------------------------------
-- Daily-Pools, Questlog und Zielplan
-- ---------------------------------------------------------------------------

expect(keys["pool:dungeon"] ~= nil, "Normale Dungeon-Daily erscheint als eine Zeile")
expect(keys["pool:heroic"] ~= nil, "Heroische Dungeon-Daily erscheint als eine Zeile")
expect(keys["pool:cooking"] ~= nil, "Kochkunst-Daily erscheint mit Kochkunst 375")
expectEqual(keys["pool:fishing"], nil, "Ohne Angeln keine Angel-Daily")
expectEqual(keys["pool:dungeon"].estimated, true, "Ungelernter Betrag ist als Schaetzung markiert")

-- Ein abgegebener Pool-Eintrag gilt als erledigt, egal welche Quest daraus kam.
completedQuests[11376] = true
plan = GCP.Roadmap:Generate()
keys = {}
for _, entry in ipairs(plan.entries) do keys[entry.key] = entry end
expectEqual(keys["pool:dungeon"].done, true, "Eine erledigte Quest hakt den ganzen Pool ab")
completedQuests[11376] = nil

-- Echte Goldbetraege schlagen Schaetzungen.
GCP.Quests:LearnGold(11364, 111100)
local poolGold, measured = GCP.Quests:PoolGold(GCP.Constants.DAILY_POOLS[2])
expectEqual(poolGold, 111100, "Gelernter Betrag gilt fuer den ganzen Pool")
expectEqual(measured, true, "Gelernter Betrag ist keine Schaetzung mehr")

local logReport = GCP.Quests:BuildLogReport()
expectEqual(#logReport.rows, 2, "Questlog-Kopfzeilen werden uebersprungen")
expectEqual(logReport.rows[1].questID, 90001, "Abgabebereite Quest steht oben")
expectEqual(logReport.rows[1].value, 80000 + 47500 * 4,
    "Questwert: Gold plus beste Auswahlbelohnung netto")
expectEqual(selectedLogIndex, 1, "Die Questlog-Auswahl des Spielers bleibt unveraendert")

plan = GCP.Roadmap:Generate()
keys = {}
for _, entry in ipairs(plan.entries) do keys[entry.key] = entry end
expect(keys["quest:90001"] ~= nil, "Abgabebereite Quest steht im Tagesplan")
expectEqual(keys["quest:90002"], nil, "Unfertige Quest steht nicht im Tagesplan")

-- Kategorie-Summen
expect(plan.categories["Daily-Quests"].open > 0, "Kategorie-Summe wird gebildet")
local dailySum = 0
for _, entry in ipairs(plan.entries) do
    if entry.category == "Daily-Quests" and not entry.done and entry.value then
        dailySum = dailySum + entry.value
    end
end
expectEqual(plan.categories["Daily-Quests"].open, dailySum,
    "Kategorie-Summe entspricht den offenen Eintraegen")

-- Zielplan: sortiert nach Gold je Minute, Farmen landet hinten.
GCP.db.options.dailyGoal = 1000000
plan = GCP.Roadmap:Generate()
expect(#plan.goal.steps > 0, "Zielplan waehlt Schritte aus")
expect(plan.goal.gold >= plan.goal.goalValue - plan.goal.earned or not plan.goal.reached,
    "Zielplan sammelt bis zum Ziel")
local previousRate
local farmBeforeQuest = false
for _, step in ipairs(plan.goal.steps) do
    local rate = step.value / step.minutes
    if previousRate then
        expect(rate <= previousRate + 0.001, "Zielplan ist nach Gold je Minute sortiert")
    end
    previousRate = rate
    if step.category == "Farmen" then farmBeforeQuest = true end
    if farmBeforeQuest and step.category == "Daily-Quests" then
        expect(false, "Farmen darf nicht vor einer Daily stehen")
    end
end
expectEqual(plan.goal.steps[1].goalRank, 1, "Schritte werden nummeriert")
GCP.db.options.dailyGoal = 0
plan = GCP.Roadmap:Generate()
expectEqual(#plan.goal.steps, 0, "Ausgeschaltetes Ziel erzeugt keinen Plan")
GCP.db.options.dailyGoal = GCP.Constants.DEFAULT_DAILY_GOAL

-- Eigenbedarf: Verbrauchbares wird nicht zum Verkauf vorgeschlagen.
local consumableReport = GCP.Advisor:BuildReport("account", "all")
local potionRow
for _, row in ipairs(consumableReport.rows) do
    if row.itemID == 60003 then potionRow = row end
end
expect(potionRow ~= nil, "Der Trank taucht im Verkaufen-Tab auf")
expectEqual(potionRow.keep, true, "Der Trank ist als Eigenbedarf markiert")
expect(potionRow.totalValue > 0, "Sein Wert wird trotzdem gezaehlt")
plan = GCP.Roadmap:Generate()
keys = {}
for _, entry in ipairs(plan.entries) do keys[entry.key] = entry end
expectEqual(keys["sell:60003"], nil, "Traenke stehen nicht im Verkaufsplan")
GCP.db.options.keepConsumables = false
plan = GCP.Roadmap:Generate()
keys = {}
for _, entry in ipairs(plan.entries) do keys[entry.key] = entry end
expect(keys["sell:60003"] ~= nil, "Abgeschaltet werden Traenke wieder vorgeschlagen")
GCP.db.options.keepConsumables = true
plan = GCP.Roadmap:Generate()
keys = {}
for _, entry in ipairs(plan.entries) do keys[entry.key] = entry end

local firstCooldown
for _, entry in ipairs(plan.entries) do
    if entry.key:sub(1, 3) == "cd:" then firstCooldown = entry.key break end
end
expectEqual(firstCooldown, "cd:28566", "Bereite Cooldowns stehen vor laufenden")

GCP.Roadmap:SetChecked("cd:28566", true)
plan = GCP.Roadmap:Generate()
for _, entry in ipairs(plan.entries) do
    if entry.key == "cd:28566" then
        expectEqual(entry.done, true, "Abhaken wird gespeichert")
    end
end
expect(plan.doneValue > 0, "Erledigter Wert wird summiert")
GCP.Roadmap:SetChecked("cd:28566", false)

-- Ohne Scan-Daten erscheint die Scan-Aufgabe ganz oben.
scanAgeByItem[21877] = nil
plan = GCP.Roadmap:Generate()
expectEqual(plan.entries[1].key, "scan", "Fehlende Preisbasis wird zur ersten Aufgabe")
scanAgeByItem[21877] = 0
plan = GCP.Roadmap:Generate()
expectEqual(keys["scan"], nil, "Scan-Aufgabe verschwindet nicht kommentarlos")
local scanEntry
for _, entry in ipairs(plan.entries) do
    if entry.key == "scan" then scanEntry = entry end
end
expect(scanEntry ~= nil and scanEntry.autoDone == true,
    "Frischer Scan nach Aufforderung gilt als von selbst erledigt")

-- Mindestgewinn: Kleinkram fliegt, sicheres Daily-Gold bleibt.
GCP.db.options.minRoadmapValue = 50000
plan = GCP.Roadmap:Generate()
keys = {}
for _, entry in ipairs(plan.entries) do keys[entry.key] = entry end
expectEqual(keys["cd:28566"], nil, "Cooldown unter Mindestgewinn verschwindet")
expect(keys["cd:29688"] ~= nil, "Grosser Cooldown bleibt ueber der Schwelle")
expectEqual(keys["craft:60001"], nil, "Craft unter Mindestgewinn verschwindet")
expectEqual(keys["flip:combine:21884"], nil, "Mini-Flip verschwindet")
expect(keys["sell:23425"] ~= nil, "Grosser Verkaufsposten bleibt")
expect(keys["daily:11023"] ~= nil, "Dailies bleiben trotz Schwelle sichtbar")
GCP.db.options.minRoadmapValue = 0

-- Skill-Filter: ohne Bergbau kein Erz-Farmtipp.
skillLines[3] = { "Angeln", false, 200 }
plan = GCP.Roadmap:Generate()
keys = {}
for _, entry in ipairs(plan.entries) do keys[entry.key] = entry end
expectEqual(keys["farm:23425"], nil, "Ohne Bergbau kein Adamantit-Farmtipp")
expect(keys["farm:22785"] ~= nil, "Kraeuter bleiben mit Kraeuterkunde farmbar")
skillLines[3] = { "Bergbau", false, 375 }

-- Goldstand
GCP:RecordGold()
expectEqual(GCP.db.goldHistory[GCP:Today()], 100000 + 250000,
    "Goldstand summiert eigenen Charakter plus Syndicator-Twinks")

-- ---------------------------------------------------------------------------
-- Neuer Tag: Haekchen fallen, dann erkennt der Plan Erledigtes von selbst
-- ---------------------------------------------------------------------------

completedQuests[11080] = false
mockNow = mockNow + 86400
plan = GCP.Roadmap:Generate()
for _, entry in ipairs(plan.entries) do
    expectEqual(entry.done, false, "Neuer Tag setzt " .. entry.key .. " zurueck")
end

GCP:RecordGold()
local trend = GCP.Roadmap:GetGoldTrend()
expectEqual(trend, 0, "Goldtrend vergleicht mit dem Vortag")

-- Der Spieler "erledigt" nun alles Moegliche, ohne ein Haekchen zu setzen:
cooldowns[28566] = { start = mockNow - 10, duration = 86400 }        -- Transmute benutzt
syndicatorCharacters["Falco-Everlook"].bank[1][1].itemCount = 5      -- Erz verkauft (60 -> 25)
syndicatorCharacters["Bankchar-Everlook"].mail[1].itemCount = 60     -- Teufelsgras gefarmt (+20)
syndicatorCharacters["Falco-Everlook"].bags[1][1].itemCount = 12     -- Motes kombiniert (25 -> 12)
bagContents[0][1].stackCount = 12
table.insert(syndicatorCharacters["Falco-Everlook"].bags[1],
    { itemID = 60001, itemCount = 2, itemLink = "item:60001" })      -- Knusperschlangen gebraten
completedQuests[11023] = true                                        -- Daily abgegeben

plan = GCP.Roadmap:Generate()
keys = {}
for _, entry in ipairs(plan.entries) do keys[entry.key] = entry end

expectEqual(keys["cd:28566"].autoDone, true, "Benutzter Cooldown wird von selbst erkannt")
expectEqual(keys["cd:28566"].done, true, "Benutzter Cooldown ist abgehakt")
expectEqual(keys["sell:23425"].autoDone, true, "Halbierter Bestand gilt als verkauft")
expectEqual(keys["farm:22785"].autoDone, true, "Deutlicher Zuwachs gilt als gefarmt")
expectEqual(keys["flip:combine:21884"].autoDone, true, "Verbrauchte Motes gelten als kombiniert")
expectEqual(keys["craft:60001"].autoDone, true, "Neues Produkt im Bestand gilt als hergestellt")
expectEqual(keys["daily:11023"].autoDone, true, "Abgegebene Daily wird von selbst erkannt")
expect(plan.doneCount >= 6, "Automatisch Erkanntes zaehlt in den Tagesfortschritt")

-- ---------------------------------------------------------------------------
-- Questbelohnungen: feste und Auswahlbelohnungen rechnen nach derselben Regel
-- max(AH netto, Haendlerwert)
-- ---------------------------------------------------------------------------

local function withRewardQuest(entry)
    questLog[#questLog + 1] = entry
    selectedLogIndex = #questLog
    local value, money, itemValue, name, source, days = GCP.Quests:SelectedRewardValue()
    questLog[#questLog] = nil
    selectedLogIndex = 1
    return value, money, itemValue, name, source, days
end

expectEqual(GCP.Prices:IsAuctionable(23425), true, "Handelsware darf ins AH")
expectEqual(GCP.Prices:IsAuctionable(3000), false, "Graue Items nimmt das AH nicht an")
expectEqual(GCP.Prices:IsAuctionable(4245), false,
    "Beim Aufheben gebundene Items gehen nicht ins AH")

local unitValue, unitSource, unitDays = GCP.Prices:GetBestPlanningValue(23425)
expectEqual(unitValue, 47500, "Bester Planwert nimmt den AH-Preis netto")
expectEqual(unitSource, "AH", "Quelle des besten Planwerts wird benannt")
expectEqual(unitDays, 1, "Der Planwert nennt seine Tageswerte mit")

local rewardValue, rewardMoney, rewardItems, rewardName, rewardSource = withRewardQuest({
    title = "Erzlieferung", questID = 90101, complete = true, money = 1000,
    rewards = { { item = "item:23425", count = 2 } },
})
expectEqual(rewardItems, 47500 * 2, "Feste Belohnung wird mit AH netto bewertet")
expectEqual(rewardMoney, 1000, "Questgold zaehlt separat")
expectEqual(rewardValue, 1000 + 47500 * 2, "Gesamtwert ist Gold plus Belohnung")
expectEqual(rewardSource, "AH", "Bewertungsquelle der Belohnung wird benannt")
expectEqual(rewardName, "Adamantiterz", "Wertvollste Belohnung wird benannt")

-- Der eigentliche Fehler bis 0.3.0: ohne Marktpreis zaehlte eine feste
-- Belohnung als 0, obwohl der Haendler dafuer zahlt.
rewardValue, rewardMoney, rewardItems, rewardName, rewardSource = withRewardQuest({
    title = "Broschenlieferung", questID = 90102, complete = true, money = 0,
    rewards = { { item = "item:4244", count = 1 } },
})
expectEqual(rewardItems, 30000, "Ohne Marktpreis zaehlt der Haendlerwert")
expectEqual(rewardSource, "Händler", "Haendlerquelle wird benannt")
expectEqual(rewardName, "Händlerbrosche", "Auch die Haendler-Belohnung wird benannt")

rewardValue, rewardMoney, rewardItems, rewardName, rewardSource = withRewardQuest({
    title = "Haendlerliebling", questID = 90103, complete = true, money = 0,
    rewards = { { item = "item:999", count = 3 } },
})
expectEqual(rewardItems, 2000 * 3, "Haendlerwert schlaegt schwachen AH-Preis")
expectEqual(rewardSource, "Händler", "Der bessere Kanal bestimmt die Quelle")

rewardValue, rewardMoney, rewardItems, rewardName, rewardSource = withRewardQuest({
    title = "Siegel des Prüfers", questID = 90104, complete = true, money = 0,
    rewards = { { item = "item:4245", count = 1 } },
})
expectEqual(rewardItems, 4000,
    "Gebundene Belohnung wird trotz Marktpreis nur ueber den Haendler bewertet")
expectEqual(rewardSource, "Händler", "Gebundenes zaehlt nie als AH-Wert")

rewardValue, rewardMoney, rewardItems, rewardName, rewardSource = withRewardQuest({
    title = "Freie Wahl", questID = 90105, complete = true, money = 500,
    choices = {
        { item = "item:999", count = 1 },   -- 2000 beim Haendler
        { item = "item:23425", count = 1 }, -- 47500 im AH
    },
})
expectEqual(rewardItems, 47500, "Von den Auswahlbelohnungen zaehlt nur die beste")
expectEqual(rewardName, "Adamantiterz", "Die beste Auswahl wird benannt")
expectEqual(rewardSource, "AH", "Auch die Auswahl nennt ihre Quelle")

rewardValue, rewardMoney, rewardItems, rewardName, rewardSource = withRewardQuest({
    title = "Freie Wahl II", questID = 90106, complete = true, money = 0,
    choices = {
        { item = "item:22785", count = 1 }, -- 760 netto im AH
        { item = "item:999", count = 1 },   -- 2000 beim Haendler
    },
})
expectEqual(rewardItems, 2000, "Auch die Auswahl rechnet mit max(AH netto, Haendler)")
expectEqual(rewardSource, "Händler", "Die Auswahl nennt den Haendler als Quelle")

rewardValue, rewardMoney, rewardItems = withRewardQuest({
    title = "Beides", questID = 90107, complete = true, money = 0,
    rewards = { { item = "item:999", count = 1 } },
    choices = { { item = "item:999", count = 1 }, { item = "item:999", count = 2 } },
})
expectEqual(rewardItems, 2000 + 4000,
    "Feste Belohnungen zaehlen vollstaendig, von der Auswahl genau eine")

-- ---------------------------------------------------------------------------
-- Datenqualitaet des Planungspreises
-- ---------------------------------------------------------------------------

expectEqual(GCP.Prices:ConfidenceLabel(0), "Momentanpreis", "0 Tageswerte: Momentanpreis")
expectEqual(GCP.Prices:ConfidenceLabel(1), "wenig Daten", "1 Tageswert: wenig Daten")
expectEqual(GCP.Prices:ConfidenceLabel(2), "wenig Daten", "2 Tageswerte: wenig Daten")
expectEqual(GCP.Prices:ConfidenceLabel(3), "mittlere Datenbasis", "3 Tageswerte: mittlere Datenbasis")
expectEqual(GCP.Prices:ConfidenceLabel(5), "mittlere Datenbasis", "5 Tageswerte: mittlere Datenbasis")
expectEqual(GCP.Prices:ConfidenceLabel(6), "gute Datenbasis", "6 Tageswerte: gute Datenbasis")
expectEqual(GCP.Prices:ConfidenceLabel(7), "gute Datenbasis", "7 Tageswerte: gute Datenbasis")

expectEqual(GCP.Prices:FormatPlanningBasis(0),
    "Preisbasis: aktueller Marktpreis · noch keine Historie",
    "Ohne Historie nennt die Zeile den Momentanpreis")
expectEqual(GCP.Prices:FormatPlanningBasis(1),
    "Preisbasis: 7-Tage-Median · 1 Tageswert · wenig Daten",
    "Ein einzelner Tageswert steht im Singular")

local confidenceItem = 22785
GCP.db.priceHistory[confidenceItem] = nil
local confidenceLabel, confidenceDays = GCP.Prices:GetPlanningConfidence(confidenceItem)
expectEqual(confidenceDays, 0, "Ohne Historie zaehlt kein Tageswert")
expectEqual(confidenceLabel, "Momentanpreis", "Ohne Historie gilt der Momentanpreis")

local confidenceHistory = {}
GCP.db.priceHistory[confidenceItem] = confidenceHistory
local expectedLabels = {
    "wenig Daten", "wenig Daten",
    "mittlere Datenbasis", "mittlere Datenbasis", "mittlere Datenbasis",
    "gute Datenbasis", "gute Datenbasis",
}
for count = 1, 7 do
    confidenceHistory[date("%Y-%m-%d", mockNow - (count - 1) * 86400)] = 800
    local stepLabel, stepDays = GCP.Prices:GetPlanningConfidence(confidenceItem)
    expectEqual(stepDays, count, string.format("%d Tageswert(e) werden gezaehlt", count))
    expectEqual(stepLabel, expectedLabels[count],
        string.format("%d Tageswert(e) ergeben \"%s\"", count, expectedLabels[count]))
end

local priceInfo = GCP.Prices:GetPlanningPriceInfo(confidenceItem)
expectEqual(priceInfo.days, 7, "Die Info-Struktur nennt die Tageswerte")
expectEqual(priceInfo.price, 800, "Die Info-Struktur nennt den Planungspreis")
expectEqual(priceInfo.basis, "7-Tage-Median", "Mit Historie ist die Basis der Median")
expectEqual(priceInfo.text, "Preisbasis: 7-Tage-Median · 7 Tageswerte · gute Datenbasis",
    "Die fertige Zeile fasst Basis, Umfang und Stufe zusammen")
GCP.db.priceHistory[confidenceItem] = { [GCP:Today()] = 800 }

-- ---------------------------------------------------------------------------
-- Nachvollziehbare Empfehlungen: die Rechnung steht im Breakdown
-- ---------------------------------------------------------------------------

plan = GCP.Roadmap:Generate()
keys = {}
for _, entry in ipairs(plan.entries) do keys[entry.key] = entry end

local function breakdownText(entry)
    if not (entry and entry.breakdown) then return "" end
    return table.concat(entry.breakdown, "\n")
end

local farmEntry = keys["farm:23425"]
expect(farmEntry ~= nil and farmEntry.breakdown ~= nil, "Farm-Tipp bringt seine Rechnung mit")
expectEqual(farmEntry.itemID, 23425, "Farm-Tipp verweist auf sein Item")
local farmText = breakdownText(farmEntry)
expect(farmText:find("Marktpreis:") ~= nil, "Farm-Rechnung nennt den Marktpreis")
expect(farmText:find("Stück/Stunde") ~= nil, "Farm-Rechnung nennt die angenommene Rate")
expect(farmText:find("Erwartung:") ~= nil, "Farm-Rechnung nennt die Erwartung je Stunde")
expect(farmText:find("Preisbasis:") ~= nil, "Farm-Rechnung nennt die Preisbasis")

local cooldownText = breakdownText(keys["cd:29688"])
expect(cooldownText:find("Produktwert netto:") ~= nil, "Craft-Rechnung nennt den Produktwert")
expect(cooldownText:find("Zutatenwert:") ~= nil, "Craft-Rechnung nennt den Zutatenwert")
expect(cooldownText:find("Erwarteter Gewinn:") ~= nil, "Craft-Rechnung nennt den Gewinn")
expect(cooldownText:find("Preisbasis:") ~= nil, "Craft-Rechnung nennt die Preisbasis")

local flipEntry = keys["flip:combine:21884"] or keys["flip:buy:21884"]
local flipText = breakdownText(flipEntry)
expect(flipText:find("Verkauf netto:") ~= nil, "Flip-Rechnung nennt den Verkaufserloes")
expect(flipText:find("Gewinn:") ~= nil, "Flip-Rechnung nennt den Gewinn")
expect(flipText:find("Preisbasis:") ~= nil, "Flip-Rechnung nennt die Preisbasis")

expect(GCP.Crafts:BuildReport().rows[1].priceDays ~= nil,
    "Der Craft-Radar reicht die Datenbasis mit durch")

-- ---------------------------------------------------------------------------
-- Preisaufzeichnung nach dem Auktionshaus
-- ---------------------------------------------------------------------------

GCP.db.priceHistory = {}
expectEqual(GCP:RecordPricesAfterAuction(), true,
    "Nach dem Verlassen des Auktionshauses wird aufgezeichnet")
expectEqual(GCP.db.priceHistory[23425] and GCP.db.priceHistory[23425][GCP:Today()], 50000,
    "Die frischen Scanpreise landen in der Historie")
expectEqual(GCP:RecordPricesAfterAuction(), false,
    "Sofortiges Wiederbetreten des AH zeichnet nicht erneut auf")
mockNow = mockNow + 120
expectEqual(GCP:RecordPricesAfterAuction(), true,
    "Nach der Drosselzeit wird wieder aufgezeichnet")

-- ---------------------------------------------------------------------------
-- Tagesplan folgt dem WoW-Daily-Reset, nicht der lokalen Mitternacht
-- ---------------------------------------------------------------------------

expect(GCP:ResetPeriodKey():find("^reset:") ~= nil,
    "Mit GetQuestResetTime beschreibt der Schluessel die Resetperiode")
expect(GCP:ResetPeriodKey() ~= GCP:Today(), "Die Resetperiode ist nicht der Kalendertag")

-- 23:30 Uhr, der Serverreset kommt erst am naechsten Morgen.
mockNow = os.time({ year = 2026, month = 8, day = 20, hour = 23, min = 30 })
questResetSeconds = 5 * 3600
GCP.db.roadmap.day = nil
GCP:ResetRoadmapIfNewDay()
local nightPeriod = GCP.db.roadmap.day
local nightDay = GCP:Today()
GCP.db.roadmap.checked["cd:28566"] = true
GCP.db.roadmap.baseline["farm:23425"] = 7

-- Eine Stunde spaeter: neuer Kalendertag, gleiche Resetperiode.
mockNow = mockNow + 3600
questResetSeconds = questResetSeconds - 3600
expect(GCP:Today() ~= nightDay, "Um 0:30 Uhr laeuft der Kalendertag weiter")
expectEqual(GCP:ResetPeriodKey(), nightPeriod,
    "Lokale Mitternacht wechselt die Resetperiode nicht")
GCP:ResetRoadmapIfNewDay()
expectEqual(GCP.db.roadmap.checked["cd:28566"], true,
    "Gleiche Resetperiode haelt die Haekchen")
expectEqual(GCP.db.roadmap.baseline["farm:23425"], 7,
    "Gleiche Resetperiode haelt die Baselines")

-- Und jetzt ueber den Serverreset hinweg.
mockNow = mockNow + questResetSeconds + 60
questResetSeconds = 86400 - 60
expect(GCP:ResetPeriodKey() ~= nightPeriod, "Der Serverreset wechselt die Periode")
GCP:ResetRoadmapIfNewDay()
expectEqual(GCP.db.roadmap.checked["cd:28566"], nil, "Der Serverreset loescht die Haekchen")
expectEqual(GCP.db.roadmap.baseline["farm:23425"], nil, "Der Serverreset loescht die Baselines")

-- Goldverlauf und Preishistorie bleiben am Kalendertag haengen.
GCP:RecordGold()
expect(GCP.db.goldHistory[GCP:Today()] ~= nil,
    "Der Goldverlauf schluesselt weiter nach Kalendertag")
GCP.Prices:RecordObservedPrices()
expect(GCP.db.priceHistory[23425][GCP:Today()] ~= nil,
    "Die Preishistorie schluesselt weiter nach Kalendertag")

-- Ohne GetQuestResetTime bleibt alles beim lokalen Kalendertag.
local savedResetTime = GetQuestResetTime
GetQuestResetTime = nil
expectEqual(GCP:ResetPeriodKey(), GCP:Today(),
    "Ohne GetQuestResetTime gilt der lokale Kalendertag")
GCP.db.roadmap.day = nil
GCP:ResetRoadmapIfNewDay()
expectEqual(GCP.db.roadmap.day, GCP:Today(), "Der Rueckfall nutzt den Kalendertag als Schluessel")
GetQuestResetTime = savedResetTime

-- /gold reset raeumt die Checkliste unabhaengig von der Periode.
GCP:ResetRoadmapIfNewDay()
GCP.db.roadmap.checked["cd:28566"] = true
GCP.db.roadmap.baseline["farm:23425"] = 7
local realUI = GCP.UI
GCP.UI = nil
SlashCmdList["GOLDCOPILOT"]("reset")
GCP.UI = realUI
expectEqual(GCP.db.roadmap.checked["cd:28566"], nil, "/gold reset leert die Checkliste")
expectEqual(GCP.db.roadmap.baseline["farm:23425"], nil, "/gold reset verwirft die Baselines")
expectEqual(GCP.db.roadmap.day, GCP:ResetPeriodKey(),
    "/gold reset setzt die laufende Resetperiode neu")

-- ---------------------------------------------------------------------------
-- Market Engine: Aufzeichnung
-- ---------------------------------------------------------------------------

local Market = GCP.Market
local MARKET = GCP.Constants.MARKET

-- Ab hier laeuft die Uhr ausschliesslich ueber advance(): Jeder Schritt der
-- Markttests ist ein bewusst gesetzter Zeitpunkt, kein Nebeneffekt.
mockNow = os.time({ year = 2026, month = 9, day = 1, hour = 8, min = 0, sec = 0 })

local function advance(seconds)
    mockNow = mockNow + seconds
    Market:InvalidateCaches()
end

Market:Reset()
expect(GCP.db.marketHistory ~= nil, "Market:Reset legt einen frischen Speicher an")
expectEqual(GCP.db.marketHistory.version, MARKET.STORE_VERSION,
    "Der Speicher traegt seine Formatversion")

expectEqual(Market:AddSnapshot(23425, 50000, mockNow, "Auctionator"), true,
    "Ein gueltiger Preis wird als Snapshot gespeichert")
expectEqual(Market:SnapshotCount(23425), 1, "Der Snapshot liegt in der Reihe")
local snapshotTime, snapshotPrice = Market:LastSnapshot(23425)
expectEqual(snapshotPrice, 50000, "Der gespeicherte Preis stimmt")
expectEqual(snapshotTime, mockNow, "Der gespeicherte Zeitpunkt stimmt")
expectEqual(GCP.db.marketHistory.source[23425], "A",
    "Die Preisquelle wird je Item als Kuerzel vermerkt")

advance(29 * 60)
expectEqual(Market:AddSnapshot(23425, 51000, mockNow, "Auctionator"), false,
    "Innerhalb von 30 Minuten entsteht kein zweiter Snapshot")
expectEqual(Market:SnapshotCount(23425), 1, "Die Reihe bleibt dabei unveraendert")

advance(2 * 60)
expectEqual(Market:AddSnapshot(23425, 51000, mockNow, "Auctionator"), true,
    "Nach 30 Minuten wird wieder aufgezeichnet")
expectEqual(Market:SnapshotCount(23425), 2, "Der zweite Snapshot liegt in der Reihe")

advance(31 * 60)
expectEqual(Market:AddSnapshot(23425, 51000, mockNow, "Auctionator"), false,
    "Ein unveraenderter Preis wird innerhalb von zwei Stunden nicht wiederholt")
advance(2 * 3600)
expectEqual(Market:AddSnapshot(23425, 51000, mockNow, "Auctionator"), true,
    "Nach zwei Stunden wird auch ein unveraenderter Preis wieder festgehalten")
expectEqual(Market:SnapshotCount(23425), 3, "Der Plateau-Punkt liegt in der Reihe")

-- Ungueltige Preise: nichts davon darf je in den SavedVariables landen.
advance(3600)
local beforeInvalid = Market:SnapshotCount(23425)
expectEqual(Market:AddSnapshot(23425, nil, mockNow, "Auctionator"), false,
    "Ein fehlender Preis wird ignoriert")
expectEqual(Market:AddSnapshot(23425, 0, mockNow, "Auctionator"), false,
    "Der Preis 0 wird ignoriert")
expectEqual(Market:AddSnapshot(23425, -500, mockNow, "Auctionator"), false,
    "Ein negativer Preis wird ignoriert")
expectEqual(Market:AddSnapshot(23425, 0 / 0, mockNow, "Auctionator"), false,
    "NaN wird ignoriert")
expectEqual(Market:AddSnapshot(23425, math.huge, mockNow, "Auctionator"), false,
    "Ein unendlicher Preis wird ignoriert")
expectEqual(Market:AddSnapshot(23425, "1000", mockNow, "Auctionator"), false,
    "Ein Preis als Text wird ignoriert")
expectEqual(Market:AddSnapshot(nil, 1000, mockNow, "Auctionator"), false,
    "Ohne Item-ID wird nichts gespeichert")
expectEqual(Market:SnapshotCount(23425), beforeInvalid,
    "Kein ungueltiger Preis hat die Reihe veraendert")

-- Hilfsfunktion fuer die Statistiktests: setzt eine Reihe mit festen Abstaenden.
local function seedSeries(itemID, prices, startAt, stepSeconds)
    GCP.db.marketHistory.items[itemID] = nil
    Market:InvalidateCaches()
    local stamp = startAt
    for _, price in ipairs(prices) do
        assert(Market:AddSnapshot(itemID, price, stamp, "Auctionator"),
            "Seed-Snapshot abgelehnt: " .. tostring(price))
        stamp = stamp + stepSeconds
    end
    return stamp - stepSeconds
end

-- Obergrenze je Item. Der Deckel wird fuer den Test abgesenkt, damit nicht
-- vierhundert Punkte gesetzt werden muessen - geprueft wird die Mechanik.
local savedCap = MARKET.MAX_SNAPSHOTS_PER_ITEM
MARKET.MAX_SNAPSHOTS_PER_ITEM = 3
seedSeries(99010, { 1000, 2000, 3000, 4000, 5000 }, mockNow - 20 * 3600, 3 * 3600)
expectEqual(Market:SnapshotCount(99010), 3, "Die Obergrenze je Item haelt")
local _, cappedNewest = Market:LastSnapshot(99010)
expectEqual(cappedNewest, 5000, "Beim Ueberlauf faellt der aelteste Punkt, nicht der neueste")
MARKET.MAX_SNAPSHOTS_PER_ITEM = savedCap
GCP.db.marketHistory.items[99010] = nil

-- ---------------------------------------------------------------------------
-- Market Engine: Retention
-- ---------------------------------------------------------------------------

local ancient = 99002
Market:AddSnapshot(ancient, 1000, mockNow - 40 * 86400, "Auctionator")
Market:AddSnapshot(ancient, 1200, mockNow - 2 * 86400, "Auctionator")
expectEqual(Market:SnapshotCount(ancient), 2, "Beide Punkte sind zunaechst gespeichert")
-- Der 40 Tage alte Punkt liegt vor dem bisherigen Bezugszeitpunkt; die Reihe
-- des anderen Items muss den Umbau des Zeitbezugs unbeschadet ueberstehen.
expectEqual(Market:SnapshotCount(23425), beforeInvalid,
    "Das Verschieben des Zeitbezugs laesst andere Reihen unangetastet")
local _, afterRebase = Market:LastSnapshot(23425)
expectEqual(afterRebase, 51000, "Auch die Preise bleiben beim Umbau erhalten")

Market:Prune(mockNow, true)
expectEqual(Market:SnapshotCount(ancient), 1, "Punkte aelter als 30 Tage werden entfernt")
local _, survivor = Market:LastSnapshot(ancient)
expectEqual(survivor, 1200, "Der juengere Punkt bleibt erhalten")

local expired = 99003
Market:AddSnapshot(expired, 900, mockNow - 45 * 86400, "Auctionator")
Market:Prune(mockNow, true)
expectEqual(GCP.db.marketHistory.items[expired], nil,
    "Eine vollstaendig veraltete Reihe verschwindet ganz")
expectEqual(GCP.db.marketHistory.items[ancient] ~= nil, true,
    "Reihen mit frischen Punkten bleiben")

-- ---------------------------------------------------------------------------
-- Market Engine: Statistik
--
-- Die Testitems haben bewusst keinen Auctionator-Preis: Damit ist "aktuell"
-- immer der zuletzt gespeicherte Punkt und jede Zahl unten nachrechenbar.
-- ---------------------------------------------------------------------------

local statsItem = 99001
seedSeries(statsItem, { 80000, 90000, 110000, 120000 }, mockNow - 18 * 3600, 6 * 3600)
local stats = Market:GetMarketScore(statsItem)
expectEqual(stats.snapshots, 4, "Alle vier Punkte liegen im 30-Tage-Fenster")
expectEqual(stats.current, 120000, "Ohne Live-Preis gilt der juengste gespeicherte Punkt")
expectEqual(stats.currentIsLive, false, "Und das wird ausdruecklich vermerkt")
expectEqual(stats.median30, 100000, "30-Tage-Median: Mitte aus 90.000 und 110.000")
expectEqual(stats.median7, 100000, "7-Tage-Median rechnet auf derselben Reihe")
expectEqual(stats.min7, 80000, "Minimum der letzten 7 Tage")
expectEqual(stats.max7, 120000, "Maximum der letzten 7 Tage")
-- Quartile: 25 % bei 87.500, 75 % bei 112.500 -> Abstand 25.000 auf Median
-- 100.000 = 0,25.
expectEqual(stats.volatility, 0.25, "Volatilitaet ist der Quartilsabstand am Median")
-- Perzentil nach Mittelrang: drei Werte darunter, einer gleich -> (3 + 0,5)/4.
expectEqual(stats.percentile, 88, "Perzentil zaehlt gleiche Werte zur Haelfte")

-- Ein voellig flacher Markt steht im 50. Perzentil, nicht im nullten.
seedSeries(99004, { 5000, 5000, 5000, 5000 }, mockNow - 18 * 3600, 6 * 3600)
expectEqual(Market:GetMarketScore(99004).percentile, 50,
    "Ein unveraenderter Preis liegt genau in der Mitte seiner eigenen Historie")

-- ---------------------------------------------------------------------------
-- Market Engine: Score und Confidence
-- ---------------------------------------------------------------------------

-- Kaltstart: kein einziger Messpunkt.
Market:Reset()
local cold = Market:GetMarketScore(23425)
expectEqual(cold.snapshots, 0, "Ohne Daten gibt es keine Snapshots")
expectEqual(cold.days, 0, "Ohne Daten gibt es keine Historientage")
expectEqual(cold.score, nil, "Ohne Daten gibt es keinen Score")
expectEqual(cold.confidence, "none", "Ohne Daten ist die Confidence \"none\"")
local coldReport = Market:BuildReport()
expectEqual(#coldReport.rows, 0, "Der Markt-Tab zeigt beim Kaltstart keine Zeilen")
expectEqual(coldReport.overview.snapshots, 0, "Die Zusammenfassung nennt null Preispunkte")
expect(Market:DescribeScore(cold):find("mehrere Tage") ~= nil,
    "Der Kaltstart-Text verspricht keine Aussage, sondern nennt den Bedarf")

-- Zwei Messpunkte: niemals ein Score, niemals hohe Sicherheit.
seedSeries(99005, { 100000, 40000 }, mockNow - 6 * 3600, 3 * 3600)
local thin = Market:GetMarketScore(99005)
expectEqual(thin.snapshots, 2, "Zwei Punkte sind gespeichert")
expectEqual(thin.score, nil, "Unter drei Punkten gibt es keinen Score")
expectEqual(thin.confidence, "low", "Zwei Punkte ergeben niemals hohe Sicherheit")

-- LOW: vier Punkte an einem Tag. Das Rohsignal waere 93, die Datenlage
-- deckelt es auf 64 - genau der Zweck der Confidence-Daempfung.
seedSeries(99006, { 100000, 100000, 100000, 20000 }, mockNow - 9 * 3600, 3 * 3600)
local lowStats = Market:GetMarketScore(99006)
expectEqual(lowStats.days, 1, "Vier Punkte an einem Tag sind ein Historientag")
expectEqual(lowStats.confidence, "low", "Ein Tag ergibt niedrige Sicherheit")
expectEqual(lowStats.percentile, 13, "Perzentil des Ausreissers nach unten")
expectEqual(lowStats.score, 64, "Der Score bleibt bei duenner Datenlage gedeckelt")
expect(lowStats.score <= 68, "Bei niedriger Confidence sind hoechstens 68 Punkte moeglich")

-- MEDIUM: zehn Punkte an drei Tagen.
seedSeries(99007,
    { 100000, 100000, 100000, 100000, 100000, 100000, 100000, 100000, 100000, 50000 },
    mockNow - 54 * 3600, 6 * 3600)
local mediumStats = Market:GetMarketScore(99007)
expectEqual(mediumStats.days, 3, "Zehn Punkte im 6-Stunden-Takt ergeben drei Tage")
expectEqual(mediumStats.snapshots, 10, "Alle zehn Punkte zaehlen")
expectEqual(mediumStats.confidence, "medium", "Drei Tage und zehn Punkte sind mittlere Sicherheit")
expectEqual(mediumStats.percentile, 5, "Der aktuelle Preis liegt im 5. Perzentil")
expectEqual(mediumStats.median30, 100000, "Median der Reihe")
expectEqual(mediumStats.score, 83, "Mittlere Sicherheit deckelt den Score auf 85")

-- HIGH: 14 Punkte an sieben Tagen.
local highPrices = {}
for index = 1, 13 do highPrices[index] = 250000 end
highPrices[14] = 182000
seedSeries(99008, highPrices, mockNow - 156 * 3600, 12 * 3600)
advance(60)
local highStats = Market:GetMarketScore(99008)
expectEqual(highStats.snapshots, 14, "Alle 14 Punkte liegen im 30-Tage-Fenster")
expectEqual(highStats.days, 7, "Zwei Punkte je Tag ueber sieben Tage")
expectEqual(highStats.confidence, "high", "Sieben Tage und 14 Punkte sind hohe Sicherheit")
expectEqual(highStats.current, 182000, "Aktueller Preis ist der juengste Punkt")
expectEqual(highStats.median7, 250000, "7-Tage-Median")
expectEqual(highStats.median30, 250000, "30-Tage-Median")
expectEqual(highStats.median24, 216000, "24-Stunden-Median aus den beiden letzten Punkten")
expectEqual(highStats.min7, 182000, "Minimum der letzten 7 Tage")
expectEqual(highStats.max7, 250000, "Maximum der letzten 7 Tage")
expectEqual(highStats.percentile, 4, "Perzentil des aktuellen Preises")
expectEqual(highStats.volatility, 0, "Eine flache Reihe hat keine Volatilitaet")
expectEqual(highStats.score, 88, "Market Score bei voller Datenlage")
expectEqual(Market:ScoreBand(highStats.score), "interessant",
    "Score 88 faellt in das Band \"interessant\"")
expectEqual(Market:ScoreBand(95), "außergewöhnlich günstig", "Band ab 90")
expectEqual(Market:ScoreBand(60), "normal", "Band ab 50")
expectEqual(Market:ScoreBand(30), "teuer", "Band ab 25")
expectEqual(Market:ScoreBand(10), "sehr teuer", "Band unter 25")
expectEqual(Market:ConfidenceLabel("high"), "hoch", "Confidence-Beschriftung")

local description = Market:DescribeScore(highStats)
expect(description:find("27 %%") ~= nil,
    "Der Erklaersatz nennt den Abstand zum 30-Tage-Median")
expect(description:find("4%. Perzentil") ~= nil, "Der Erklaersatz nennt das Perzentil")
expect(description:find("unter") ~= nil, "Der Erklaersatz nennt die Richtung")

-- Ein teures Item bekommt einen niedrigen Score, nicht gar keinen.
local expensive = {}
for index = 1, 13 do expensive[index] = 100000 end
expensive[14] = 150000
seedSeries(99009, expensive, mockNow - 156 * 3600, 12 * 3600)
local expensiveStats = Market:GetMarketScore(99009)
expectEqual(expensiveStats.confidence, "high", "Auch die teure Reihe hat volle Datenlage")
expect(expensiveStats.score < 25, "Ein Preis deutlich ueber dem Median landet unten")

-- Sortierung des Markt-Tabs: hoechster Score zuerst, Reihen ohne Score hinten.
local marketReport = Market:BuildReport()
expect(#marketReport.rows >= 2, "Der Markt-Tab zeigt die beobachteten Reihen")
local previousScore = nil
local seenWithoutScore = false
for _, row in ipairs(marketReport.rows) do
    if row.score == nil then
        seenWithoutScore = true
    else
        expect(not seenWithoutScore, "Reihen ohne Score stehen hinter denen mit Score")
        if previousScore then
            expect(row.score <= previousScore, "Der Markt-Tab sortiert nach Score absteigend")
        end
        previousScore = row.score
    end
end
expectEqual(marketReport.rows[1].itemID, 99008, "Der beste Score steht oben")
expect(marketReport.overview.snapshots > 0, "Die Zusammenfassung zaehlt die Preispunkte")

-- ---------------------------------------------------------------------------
-- Market Engine: beobachtete Items
-- ---------------------------------------------------------------------------

Market:InvalidateTrackedCache()
local tracked = Market:GetTrackedItems()
local isTracked = {}
for _, itemID in ipairs(tracked) do isTracked[itemID] = true end
expect(#tracked > 0, "Es werden Items beobachtet")
expectEqual(isTracked[22785], true, "Farmziele aus dem Katalog werden beobachtet")
expectEqual(isTracked[22574], true, "Flip-Items werden beobachtet")
expectEqual(isTracked[60001], true, "Produkte gescannter Rezepte werden beobachtet")
expectEqual(isTracked[23425], true, "Items aus dem Accountbestand werden beobachtet")
expectEqual(isTracked[99008], true, "Items mit vorhandener Historie bleiben beobachtet")
expectEqual(isTracked[3000], nil, "Graue Ware hat keinen Markt und wird nicht beobachtet")
expectEqual(Market:GetTrackReason(22785), "Farmziel", "Der Grund der Beobachtung wird benannt")
expectEqual(Market:GetTrackReason(22574), "Flip", "Flip-Items nennen ihren Grund")
expectEqual(Market:GetTrackReason(60001), "Rezept", "Rezeptprodukte nennen ihren Grund")
expectEqual(Market:GetTrackReason(99008), "Historie", "Bestehende Reihen nennen ihren Grund")

expectEqual(Market:RegisterItem(12345, "Watchlist"), true,
    "Andere Module koennen Items zur Beobachtung anmelden")
expectEqual(Market:RegisterItem(12345, "Watchlist"), false,
    "Dieselbe Anmeldung zweimal aendert nichts")
tracked = Market:GetTrackedItems()
isTracked = {}
for _, itemID in ipairs(tracked) do isTracked[itemID] = true end
expectEqual(isTracked[12345], true, "Angemeldete Items stehen in der Beobachtungsliste")
expectEqual(Market:GetTrackReason(12345), "Watchlist", "Der angegebene Grund bleibt erhalten")
expectEqual(Market:RegisterItem("keine Zahl", "Watchlist"), false,
    "Eine ungueltige Item-ID wird abgelehnt")
Market:UnregisterItem(12345)

-- ---------------------------------------------------------------------------
-- Market Engine: Auctionator-Callback statt nur AUCTION_HOUSE_CLOSED
-- ---------------------------------------------------------------------------

Market:Reset()
Market.lastRecordAt = nil
Market.callbackRegistered = false
expectEqual(Market:HasAuctionatorCallbackAPI(), true,
    "Die Attrappe stellt RegisterForDBUpdate bereit")
expectEqual(Market:TryRegisterAuctionatorCallback(), true,
    "Der offizielle Auctionator-Callback wird genutzt")
expectEqual(#dbUpdateRegistrations, 1, "Genau eine Registrierung")
expectEqual(dbUpdateRegistrations[1], "GoldCopilot",
    "Die Registrierung nennt den Addon-Namen als callerID")
expectEqual(Market:TryRegisterAuctionatorCallback(), true,
    "Ein zweiter Versuch meldet Erfolg")
expectEqual(#dbUpdateRegistrations, 1, "...registriert sich aber nicht erneut")

-- Ein Vollscan meldet das Datenbank-Update sehr oft. Daraus darf genau ein
-- Schreibdurchlauf werden.
fireAuctionatorDBUpdate(200)
expectEqual(Market:SnapshotCount(23425), 0,
    "Der Callback schreibt nicht sofort, sondern sammelt")
expectEqual(flushTimers(), 1, "200 Meldungen ergeben genau einen geplanten Durchlauf")
expectEqual(Market:SnapshotCount(23425), 1, "Nach dem Debounce genau ein Snapshot je Item")
local afterScan = Market:GetOverview().snapshots
expect(afterScan > 1, "Der Durchlauf hat mehrere Maerkte erfasst")

-- Zweiter Vollscan zwei Minuten spaeter: die Drosselung je Durchlauf ist
-- abgelaufen, das 30-Minuten-Fenster je Item nicht.
advance(120)
fireAuctionatorDBUpdate(200)
expectEqual(flushTimers(), 1, "Auch der zweite Scan plant genau einen Durchlauf")
expectEqual(Market:SnapshotCount(23425), 1,
    "Innerhalb von 30 Minuten entsteht trotz zweitem Scan kein zweiter Snapshot")
expectEqual(Market:GetOverview().snapshots, afterScan,
    "Die Gesamtzahl der Preispunkte bleibt unveraendert")

-- Eine halbe Stunde spaeter ist das Zeitfenster offen - der Preis ist aber
-- unveraendert, und ein zweites Mal derselbe Wert ist keine neue Information.
advance(31 * 60)
fireAuctionatorDBUpdate(5)
flushTimers()
expectEqual(Market:SnapshotCount(23425), 1,
    "Ein unveraenderter Preis erzeugt auch nach 30 Minuten keinen zweiten Punkt")

-- Bewegt sich der Preis, wird er festgehalten.
marketPrices[23425] = 52000
advance(31 * 60)
fireAuctionatorDBUpdate(5)
flushTimers()
expectEqual(Market:SnapshotCount(23425), 2,
    "Ein veraenderter Preis wird nach 30 Minuten aufgezeichnet")

-- Rueckfall: ohne die Auctionator-API bleibt AUCTION_HOUSE_CLOSED der Ausloeser.
local savedRegister = Auctionator.API.v1.RegisterForDBUpdate
Auctionator.API.v1.RegisterForDBUpdate = nil
Market.callbackRegistered = false
expectEqual(Market:HasAuctionatorCallbackAPI(), false,
    "Ohne die Funktion meldet die Pruefung keine API")
expectEqual(Market:TryRegisterAuctionatorCallback(), false,
    "Ohne die Funktion wird nicht registriert")
marketPrices[23425] = 53000
advance(31 * 60)
expectEqual(GCP:NotifyMarketOfFreshPrices("Test"), true,
    "Der Rueckfall stoesst einen Durchlauf an")
expectEqual(GCP:NotifyMarketOfFreshPrices("Test"), false,
    "Ein zweiter Aufruf dockt am laufenden Durchlauf an")
expectEqual(flushTimers(), 1, "Auch der Rueckfall plant genau einen Durchlauf")
expectEqual(Market:SnapshotCount(23425), 3,
    "Der Rueckfall zeichnet auf, wenn der Callback fehlt")
Auctionator.API.v1.RegisterForDBUpdate = savedRegister
marketPrices[23425] = 50000

-- ---------------------------------------------------------------------------
-- Market Engine: /gold marketstats und /gold marketreset
-- ---------------------------------------------------------------------------

local savedUI = GCP.UI
GCP.UI = nil

for index = #chatLog, 1, -1 do chatLog[index] = nil end
SlashCmdList["GOLDCOPILOT"]("marketstats")
local statsOutput = table.concat(chatLog, "\n")
expect(statsOutput:find("Tracked items:") ~= nil, "/gold marketstats nennt die beobachteten Items")
expect(statsOutput:find("Market snapshots:") ~= nil, "/gold marketstats nennt die Preispunkte")
expect(statsOutput:find("Oldest snapshot:") ~= nil, "/gold marketstats nennt den aeltesten Punkt")
expect(statsOutput:find("DB estimate:") ~= nil, "/gold marketstats schaetzt die Dateigroesse")

-- Fuer den Reset-Test alle anderen Datentoepfe fuellen: keiner darf angefasst
-- werden.
GCP.db.options.minRoadmapValue = 4711
GCP.db.options.ignored[999] = true
GCP.db.goldHistory["2026-09-01"] = 123456
GCP.db.priceHistory[23425] = { ["2026-09-01"] = 50000 }
GCP.db.questGold[11364] = 111100
local recipesBefore = GCP.db.recipes
local snapshotsBefore = Market:GetOverview().snapshots
expect(snapshotsBefore > 0, "Vor dem Reset liegen Preispunkte vor")

for index = #chatLog, 1, -1 do chatLog[index] = nil end
SlashCmdList["GOLDCOPILOT"]("marketreset")
expectEqual(Market:GetOverview().snapshots, snapshotsBefore,
    "/gold marketreset allein loescht noch nichts")
expect(table.concat(chatLog, "\n"):find("marketreset confirm") ~= nil,
    "/gold marketreset verlangt eine Bestaetigung")

SlashCmdList["GOLDCOPILOT"]("marketreset confirm")
expectEqual(Market:GetOverview().snapshots, 0, "Die Bestaetigung leert die Markthistorie")
expectEqual(GCP.db.options.minRoadmapValue, 4711, "marketreset laesst die Optionen unberuehrt")
expectEqual(GCP.db.options.ignored[999], true, "marketreset laesst die Ignorierliste unberuehrt")
expectEqual(GCP.db.goldHistory["2026-09-01"], 123456,
    "marketreset laesst den Goldverlauf unberuehrt")
expectEqual(GCP.db.priceHistory[23425]["2026-09-01"], 50000,
    "marketreset laesst die alte Preishistorie unberuehrt")
expectEqual(GCP.db.questGold[11364], 111100, "marketreset laesst das Questgold unberuehrt")
expectEqual(GCP.db.recipes, recipesBefore, "marketreset laesst die Rezepte unberuehrt")
expectEqual(GCP.db.marketHistory.imported, true,
    "Nach dem Reset wird die alte Preishistorie nicht erneut importiert")

GCP.db.options.minRoadmapValue = 0
GCP.db.options.ignored[999] = nil
GCP.UI = savedUI

-- ---------------------------------------------------------------------------
-- Opportunity Engine: Score-Formel
--
-- Der Score wird hier direkt gerechnet, ohne Umweg ueber Bestand und Rezepte:
-- Jede Zahl unten ist aus den Konstanten in Constants.lua nachrechenbar, und
-- genau das ist der Zweck - die Formel soll spaeter kalibrierbar sein, ohne
-- dass jemand raten muss, was sie tut.
-- ---------------------------------------------------------------------------

local Opportunity = GCP.Opportunity
local OPP = GCP.Constants.OPPORTUNITY

-- Basisfall: ROI 300 %, 50 g Gewinn, 10 g Einsatz, Market Score 100.
--   Margin  = 35 * 3,00 / (3,00 + 0,25) = 32,31
--   Scale   = 15 * 500000 / (500000 + 100000) = 12,50
--   Market  = 25 * 100 / 100 = 25,00
--   Data    = 25 (high)
--   Kapital = 15 * 100000 / (100000 + 2500000) = 0,58
--   Summe   = 94,23 -> 94
local function scoreInput(overrides)
    local input = {
        roi = 3.0, profit = 500000, cost = 100000,
        marketScore = 100, volatility = 0, confidence = "high",
    }
    for key, value in pairs(overrides or {}) do input[key] = value end
    return input
end

expectEqual(Opportunity:ScoreOf(scoreInput()), 94,
    "Opportunity Score des dokumentierten Basisfalls")
expectEqual(Opportunity:ScoreOf(scoreInput({ marketScore = 0 })), 69,
    "Ein ungünstiger Market Score kostet die vollen 25 Punkte")
expectEqual(Opportunity:ScoreOf({
    roi = 3.0, profit = 500000, cost = 100000, volatility = 0, confidence = "high" }), 82,
    "Ein fehlender Market Score zählt neutral als 50, nicht als 0")
expectEqual(Opportunity:ScoreOf(scoreInput({ volatility = 0.6 })), 79,
    "Volle Volatilität kostet 15 Punkte")
expectEqual(Opportunity:ScoreOf(scoreInput({ volatility = 5 })), 79,
    "Über der Kappungsgrenze wird nicht weiter bestraft")
expectEqual(Opportunity:ScoreOf(scoreInput({ cost = 2500000, roi = 3.0 })), 87,
    "250 g Kapitaleinsatz kosten den halben Kapitalabschlag")

-- Confidence deckelt hart. Dieselbe Rechnung, nur duennere Datenlage.
expectEqual(Opportunity:ScoreOf(scoreInput({ confidence = "medium" })), 80,
    "Mittlere Confidence deckelt den Opportunity Score auf 80")
expectEqual(Opportunity:ScoreOf(scoreInput({ confidence = "low" })), 55,
    "Niedrige Confidence deckelt den Opportunity Score auf 55")
expectEqual(Opportunity:ScoreOf(scoreInput({ confidence = "none" })), nil,
    "Ohne Datenbasis gibt es gar keinen Score, nicht die Note 0")
expectEqual(Opportunity:ScoreOf(scoreInput({ confidence = "erfunden" })), nil,
    "Eine unbekannte Confidence-Stufe ergibt keinen Score")

-- Ohne belastbare Eingaben gibt es keinen Score.
expectEqual(Opportunity:ScoreOf(scoreInput({ profit = 0 })), nil,
    "Ohne positiven Gewinn gibt es keinen Score")
expectEqual(Opportunity:ScoreOf(scoreInput({ profit = -100 })), nil,
    "Ein Verlust ist keine Chance")
expectEqual(Opportunity:ScoreOf(scoreInput({ cost = 0 })), nil,
    "Ohne Kapitaleinsatz ist die ROI keine Kennzahl")
expectEqual(Opportunity:ScoreOf(scoreInput({ roi = 0 / 0 })), nil, "NaN ergibt keinen Score")
expectEqual(Opportunity:ScoreOf(nil), nil, "Ohne Eingabe gibt es keinen Score")

-- Der Kern der Sache: hoher absoluter Gewinn und hohe ROI sind zwei
-- verschiedene Dinge, und die dicke Chance gewinnt nicht automatisch.
local bigSlow = Opportunity:ScoreOf({
    roi = 0.05, profit = 250000, cost = 5000000,
    marketScore = 50, volatility = 0, confidence = "high" })
local smallFast = Opportunity:ScoreOf({
    roi = 0.80, profit = 40000, cost = 50000,
    marketScore = 50, volatility = 0, confidence = "high" })
expect(smallFast > bigSlow,
    "500 g Einsatz mit 5 % ROI schlägt nicht automatisch 50 g mit 80 % ROI")

-- Baender
expectEqual(Opportunity:ScoreBand(94), "sehr interessant", "Band ab 80")
expectEqual(Opportunity:ScoreBand(65), "interessant", "Band ab 60")
expectEqual(Opportunity:ScoreBand(45), "beobachten", "Band ab 40")
expectEqual(Opportunity:ScoreBand(10), "geringe Priorität", "Band unter 40")
expectEqual(Opportunity:ScoreBand(nil), nil, "Ohne Score gibt es kein Band")

-- Confidence-Stufen aus der Preisbasis und die schwaechste Reihe.
expectEqual(Opportunity:ConfidenceFromDays(0, true), "low",
    "Ein Momentanpreis ohne Historie ist niedrige Sicherheit")
expectEqual(Opportunity:ConfidenceFromDays(3, true), "medium", "Ab drei Tageswerten mittel")
expectEqual(Opportunity:ConfidenceFromDays(6, true), "high", "Ab sechs Tageswerten hoch")
expectEqual(Opportunity:ConfidenceFromDays(7, false), "none", "Ohne Preis gibt es keine Stufe")
expectEqual(Opportunity:WeakestConfidence("high", "low"), "low",
    "Die schwaechste beteiligte Reihe bestimmt die Aussagekraft")
expectEqual(Opportunity:WeakestConfidence("high", "high"), "high",
    "Sind alle Reihen belegt, bleibt es dabei")
expectEqual(Opportunity:WeakestConfidence(), "none", "Ohne Angabe gibt es keine Stufe")

-- ---------------------------------------------------------------------------
-- Opportunity Engine: die vier Chancenarten
-- ---------------------------------------------------------------------------

-- Ausgangslage: leere Tagespreis-Historie (also Momentanpreise), keine Filter.
GCP.db.priceHistory = {}
GCP.db.options.opportunityMinProfit = 0
GCP.db.options.opportunityMinROI = 0
Market:Reset()
Opportunity:Invalidate()

local function findOpportunity(report, kind, itemID)
    for _, opportunity in ipairs(report.opportunities) do
        if opportunity.type == kind and opportunity.itemID == itemID then
            return opportunity
        end
    end
    return nil
end

local oppReport = Opportunity:ComputeReport()

-- A) CONVERSION: 10 Feuerpartikel (je 100) -> 1 Urfeuer (1300).
local conversion = findOpportunity(oppReport, "conversion", 21884)
expect(conversion ~= nil, "Aus Motes und Ur-Partikeln entsteht eine Conversion-Chance")
expectEqual(conversion.cost, 1000, "Einkauf: 10 Motes zu je 100 Kupfer")
expectEqual(conversion.expectedRevenue, 1235, "Erlös netto: 1300 minus 5 % AH-Gebühr")
expectEqual(conversion.expectedProfit, 235, "Gewinn ist Erlös netto minus Einkauf")
expectEqual(conversion.roi, 235 / 1000, "ROI ist Gewinn geteilt durch Kapitaleinsatz")
expectEqual(conversion.expectedRevenue, GCP.Prices:NetAuction(1300),
    "Die AH-Gebühr wird genau einmal abgezogen – auf der Verkaufsseite")
expect(conversion.expectedRevenue ~= GCP.Prices:NetAuction(GCP.Prices:NetAuction(1300)),
    "...und ausdrücklich nicht zweimal")
expectEqual(conversion.cost, 10 * 100,
    "Auf den Einkauf wird keine AH-Gebühr gerechnet – Kaufen kostet keine Gebühr")

-- Essenzen 3:1. Die guenstigere Richtung gewinnt, hier "3 niedere -> 1 hohe".
local essence = findOpportunity(oppReport, "conversion", 10939)
expect(essence ~= nil, "Aus den Essenzen entsteht eine Conversion-Chance")
expectEqual(essence.cost, 300, "Einkauf: 3 niedere Essenzen zu je 100")
expectEqual(essence.expectedRevenue, GCP.Prices:NetAuction(400),
    "Erlös netto der hohen Essenz")

-- B) CRAFT: Knusperschlange (8000) aus 1x Schlangenfleisch (2000).
local craft = findOpportunity(oppReport, "craft", 60001)
expect(craft ~= nil, "Aus einem gescannten Rezept entsteht eine Craft-Chance")
expectEqual(craft.cost, 2000, "Materialkosten zaehlen genau einmal")
expectEqual(craft.expectedRevenue, GCP.Prices:NetAuction(8000),
    "Produkterlös netto nach 5 % AH-Gebühr")
expectEqual(craft.expectedProfit, GCP.Prices:NetAuction(8000) - 2000,
    "Craft-Gewinn ist Erlös netto minus Materialkosten")
expectEqual(craft.roi, craft.expectedProfit / craft.cost, "ROI des Crafts")
expect(craft.feasible ~= nil, "Die machbare Stückzahl steht an der Chance")

-- Die Marktlage eines Crafts kommt von den Zutaten, nicht vom Produkt: Ein
-- billiges Produkt ist fuer den, der es verkauft, kein Vorteil.
expectEqual(Opportunity:BasketFacts({}), nil,
    "Ein leerer Zutatenkorb ergibt keinen Score, nicht die Note 0")
expectEqual(Opportunity:BasketFacts({ { 99201, 1, 1000 } }), nil,
    "Zutaten ohne eigene Historie ergeben keinen Score")
-- Zwei Zutaten mit sehr unterschiedlichem Kostenanteil und sehr
-- unterschiedlicher Marktlage: Die billige liegt auf ihrem Normalwert, die
-- teure deutlich darunter. 99,9 % des Geldes stecken in der teuren, also muss
-- sie den Korb bestimmen.
local cheapSeries, dearSeries = {}, {}
for index = 1, 14 do cheapSeries[index] = 100 end
for index = 1, 13 do dearSeries[index] = 100000 end
dearSeries[14] = 50000
seedSeries(99202, cheapSeries, mockNow - 156 * 3600, 12 * 3600)
seedSeries(99203, dearSeries, mockNow - 156 * 3600, 12 * 3600)
local cheapScore = Market:GetMarketScore(99202).score
local dearScore = Market:GetMarketScore(99203).score
expectEqual(cheapScore, 50, "Eine flache Reihe steht genau in der Mitte")
expect(dearScore > 80, "Eine halbierte Reihe steht weit oben")
local basketScore, basketVolatility = Opportunity:BasketFacts({
    { 99202, 1, 100 }, { 99203, 1, 90000 } })
expect(math.abs(basketScore - dearScore) < math.abs(basketScore - cheapScore),
    "Der Zutatenkorb gewichtet nach Kostenanteil, nicht nach Stueckzahl")
expectEqual(basketVolatility, 0, "Zwei flache Reihen ergeben keine Volatilitaet")
GCP.db.marketHistory.items[99202] = nil
GCP.db.marketHistory.items[99203] = nil

-- C) DISENCHANT: gruene Waffe fuer 10000, Auctionator-Entzauberwert 15000.
local disenchant = findOpportunity(oppReport, "disenchant", 777)
expect(disenchant ~= nil, "Aus einem entzauberbaren Item entsteht eine DE-Chance")
expectEqual(disenchant.cost, 10000, "Kaufpreis des Items, ohne AH-Gebühr")
expectEqual(disenchant.expectedRevenue, GCP.Prices:NetAuction(15000),
    "Erlös netto der Materialien – die Gebühr fällt beim Verkauf an, einmal")
expectEqual(disenchant.expectedProfit, GCP.Prices:NetAuction(15000) - 10000,
    "DE-Gewinn ist Erwartungswert netto minus Kaufpreis")
expectEqual(findOpportunity(oppReport, "disenchant", 888), nil,
    "Ein gebundenes Item ist keine DE-Chance – man kann es nicht kaufen")
expectEqual(findOpportunity(oppReport, "disenchant", 23425), nil,
    "Handwerkswaren sind nicht entzauberbar")

-- Nur wenn der Erwartungswert ueber dem Kaufpreis liegt.
local savedDisenchant = disenchantPrices["item:777"]
disenchantPrices["item:777"] = 5000
Opportunity:Invalidate()
expectEqual(findOpportunity(Opportunity:ComputeReport(), "disenchant", 777), nil,
    "Liegt der Entzauberwert unter dem Kaufpreis, entsteht keine Chance")
disenchantPrices["item:777"] = savedDisenchant

-- D) RESALE: Adamantiterz steht historisch bei 100.000, aktuell bei 50.000.
local resalePrices = {}
for index = 1, 14 do resalePrices[index] = 100000 end
seedSeries(23425, resalePrices, mockNow - 156 * 3600, 12 * 3600)
Opportunity:Invalidate()
oppReport = Opportunity:ComputeReport()
local resale = findOpportunity(oppReport, "resale", 23425)
expect(resale ~= nil, "Ein Preis deutlich unter der eigenen Historie ist eine Resale-Chance")
expectEqual(resale.cost, 50000, "Kapitaleinsatz ist der aktuelle Preis")
expectEqual(resale.marketScore, 100, "Der Market Score wird unveraendert uebernommen")
expectEqual(resale.confidence, "high", "14 Punkte an 7 Tagen sind hohe Sicherheit")
-- Konservativer Zielpreis: min(7d Median, 30d Median), davon 5 % AH-Gebuehr.
expectEqual(Opportunity:TargetPrice({ median7 = 90000, median30 = 100000 }), 90000,
    "Der konservative Zielpreis ist das Minimum aus 7d- und 30d-Median")
expectEqual(Opportunity:TargetPrice({ median7 = 120000, median30 = 100000 }), 100000,
    "...auch wenn der 7-Tage-Median der bequemere Wert waere")
expectEqual(resale.expectedRevenue, GCP.Prices:NetAuction(100000),
    "Erlös netto des konservativen Zielpreises")
expectEqual(resale.expectedProfit, GCP.Prices:NetAuction(100000) - 50000,
    "Resale-Marge ist Zielpreis netto minus aktueller Preis")
expectEqual(resale.opportunityScore, 82, "Opportunity Score der Resale-Chance")
expectEqual(Opportunity:ScoreBand(resale.opportunityScore), "sehr interessant",
    "...und faellt damit in das oberste Band")

-- Die Resale-Erklaerung zeigt die vollstaendige Rechnung, Zeile fuer Zeile.
local resaleText = table.concat(Opportunity:Explain(resale), "\n")
for _, needle in ipairs({
    "Aktueller Preis:", "7d Median:", "30d Median:", "Konservativer Zielpreis:",
    "Erlös netto", "Theoretischer Gewinn:", "ROI:", "Opportunity Score:",
    "Market Score der Kaufseite:", "Confidence:", "Preispunkte:",
}) do
    expect(resaleText:find(needle, 1, true) ~= nil,
        "Die Resale-Erklärung nennt \"" .. needle .. "\"")
end
expect(resaleText:find("Liquidität", 1, true) ~= nil,
    "Die Resale-Erklärung nennt die fehlende Liquidität ausdrücklich")
-- Market Score und Confidence stehen genau einmal drin, nicht zweimal.
local _, marketScoreMentions = resaleText:gsub("Market Score", "")
expectEqual(marketScoreMentions, 1, "Der Market Score steht genau einmal in der Erklärung")

-- Ohne belastbaren Market Score gibt es keine Resale-Chance: Zwei Messpunkte
-- sind keine Verteilung, in die sich etwas einordnen liesse.
seedSeries(99101, { 100000, 100000 }, mockNow - 4 * 3600, 2 * 3600)
Market:RegisterItem(99101, "Historie")
Opportunity:Invalidate()
expectEqual(findOpportunity(Opportunity:ComputeReport(), "resale", 99101), nil,
    "Zu wenig Daten ergeben keine Resale-Chance und keinen Score")
Market:UnregisterItem(99101)
GCP.db.marketHistory.items[99101] = nil

-- Ein teurer Preis ueber dem eigenen Median ist keine Chance. Teufelsgras
-- steht aktuell bei 800, die Historie bei 100.
local expensiveSeries = {}
for index = 1, 14 do expensiveSeries[index] = 100 end
seedSeries(22785, expensiveSeries, mockNow - 156 * 3600, 12 * 3600)
Opportunity:Invalidate()
expectEqual(findOpportunity(Opportunity:ComputeReport(), "resale", 22785), nil,
    "Ein Preis über dem eigenen Median ist keine Resale-Chance")
GCP.db.marketHistory.items[22785] = nil

-- ---------------------------------------------------------------------------
-- Opportunity Engine: keine Chance ohne Preise
-- ---------------------------------------------------------------------------

local savedProductPrice = marketPrices[60001]
marketPrices[60001] = nil
Opportunity:Invalidate()
local missingReport = Opportunity:ComputeReport()
expectEqual(findOpportunity(missingReport, "craft", 60001), nil,
    "Ohne Produktpreis entsteht keine Craft-Chance")
expect(missingReport.missingPrices > 0, "Fehlende Preise werden gezaehlt statt geraten")
marketPrices[60001] = savedProductPrice

local savedMotePrice = marketPrices[22574]
marketPrices[22574] = nil
Opportunity:Invalidate()
expectEqual(findOpportunity(Opportunity:ComputeReport(), "conversion", 21884), nil,
    "Ohne Mote-Preis entsteht keine Conversion-Chance")
marketPrices[22574] = savedMotePrice

-- ---------------------------------------------------------------------------
-- Opportunity Engine: Filter
-- ---------------------------------------------------------------------------

Opportunity:Invalidate()
local unfiltered = Opportunity:ComputeReport()
expect(unfiltered.shownCount > 0, "Ohne Filter bleibt etwas uebrig")

GCP.db.options.opportunityMinProfit = 5000
GCP.db.options.opportunityMinROI = 0
Opportunity:Invalidate()
local profitFiltered = Opportunity:ComputeReport()
expect(profitFiltered.hiddenByProfit > 0, "Der Mindestprofit blendet Kleinkram aus")
for _, opportunity in ipairs(profitFiltered.opportunities) do
    expect(opportunity.expectedProfit >= 5000,
        "Keine Chance unter dem Mindestprofit bleibt stehen")
end
expectEqual(findOpportunity(profitFiltered, "conversion", 21884), nil,
    "235 Kupfer Gewinn fallen unter einem Mindestprofit von 50 Silber raus")

GCP.db.options.opportunityMinProfit = 0
GCP.db.options.opportunityMinROI = 0.30
Opportunity:Invalidate()
local roiFiltered = Opportunity:ComputeReport()
expect(roiFiltered.hiddenByROI > 0, "Der Mindest-ROI blendet duenne Margen aus")
for _, opportunity in ipairs(roiFiltered.opportunities) do
    expect(opportunity.roi >= 0.30, "Keine Chance unter dem Mindest-ROI bleibt stehen")
end
expectEqual(findOpportunity(roiFiltered, "conversion", 21884), nil,
    "23,5 % ROI fallen unter einer Schwelle von 30 % raus")
expect(findOpportunity(roiFiltered, "craft", 60001) ~= nil,
    "Ein Craft mit 280 % ROI bleibt stehen")

-- Der Mindestgewinn des Tagesplans bleibt davon voellig unberuehrt.
GCP.db.options.minRoadmapValue = 4711
GCP.db.options.opportunityMinProfit = 12345
GCP.db.options.opportunityMinROI = 0.05
expectEqual(GCP.db.options.minRoadmapValue, 4711,
    "Die Chancen-Filter fassen den Mindestgewinn des Tagesplans nicht an")
local filterProfit, filterROI = Opportunity:GetFilters()
expectEqual(filterProfit, 12345, "Der Mindestprofit der Chancen wird gelesen")
expectEqual(filterROI, 0.05, "Der Mindest-ROI der Chancen wird gelesen")
GCP.db.options.minRoadmapValue = 0
GCP.db.options.opportunityMinProfit = 0
GCP.db.options.opportunityMinROI = 0

-- ---------------------------------------------------------------------------
-- Opportunity Engine: Deduplikation und Gruppierung
-- ---------------------------------------------------------------------------

-- Zwei Rezepte fuehren zum selben Produkt. Das ist eine Chance, nicht zwei.
GCP.db.recipes["Testberuf"] = {
    scannedAt = GCP:Today(),
    list = { { name = "Knusperschlange (teuer)", product = 60001, numMade = 1,
               mats = { { 60002, 2 } } } },
}
GCP.Crafts.revision = GCP.Crafts.revision + 1
Opportunity:Invalidate()
local dedupReport = Opportunity:ComputeReport()
local craftCount = 0
for _, opportunity in ipairs(dedupReport.opportunities) do
    if opportunity.type == "craft" and opportunity.itemID == 60001 then
        craftCount = craftCount + 1
    end
end
expectEqual(craftCount, 1, "Zwei Wege zum selben Produkt ergeben genau eine Craft-Chance")
expect(dedupReport.duplicates > 0, "Die verworfene Doppelung wird gezaehlt")
local dedupCraft = findOpportunity(dedupReport, "craft", 60001)
expectEqual(dedupCraft.cost, 2000, "Von zwei Rezepten bleibt das profitablere")
GCP.db.recipes["Testberuf"] = nil
GCP.Crafts.revision = GCP.Crafts.revision + 1

-- Dasselbe Item ueber verschiedene Wege: getrennte Zeilen, aber sie wissen
-- voneinander. Knusperschlange wird kuenstlich auch historisch guenstig.
local resaleCraftSeries = {}
for index = 1, 14 do resaleCraftSeries[index] = 20000 end
seedSeries(60001, resaleCraftSeries, mockNow - 156 * 3600, 12 * 3600)
Opportunity:Invalidate()
local groupedReport = Opportunity:ComputeReport()
local bucket = groupedReport.groups[60001]
expect(bucket ~= nil, "Chancen zum selben Item werden gruppiert")
expectEqual(#bucket.opportunities, 2, "Craft und Resale bleiben zwei eigene Chancen")
expectEqual(#bucket.typeList, 2, "Die Gruppe kennt beide Arten")
expect(bucket.best ~= nil, "Die Gruppe kennt ihre beste Chance")
for _, opportunity in ipairs(bucket.opportunities) do
    expectEqual(opportunity.groupSize, 2, "Jede Zeile weiss, dass sie zu zweit ist")
    expect(opportunity.alsoTypes ~= nil and #opportunity.alsoTypes == 1,
        "Jede Zeile nennt die andere Art")
end

-- Get(itemID) ist die oeffentliche Einzelabfrage.
Opportunity:Invalidate()
local single = Opportunity:Get(60001)
expect(single ~= nil, "Opportunity:Get liefert die Gruppe eines Items")
expectEqual(single.itemID, 60001, "...zum abgefragten Item")
expectEqual(Opportunity:Get(4242), nil, "Ohne Chance liefert Get nichts")
expectEqual(Opportunity:Get("keine Zahl"), nil, "Eine ungueltige ID liefert nichts")
GCP.db.marketHistory.items[60001] = nil
Opportunity:Invalidate()

-- ---------------------------------------------------------------------------
-- Opportunity Engine: Sortierung und Aufbereitung
-- ---------------------------------------------------------------------------

local sorted = Opportunity:ComputeReport()
local previousOpportunityScore = nil
for _, opportunity in ipairs(sorted.opportunities) do
    if previousOpportunityScore then
        expect(opportunity.opportunityScore <= previousOpportunityScore,
            "Die Chancenliste sortiert nach Opportunity Score absteigend")
    end
    previousOpportunityScore = opportunity.opportunityScore
    expect(opportunity.expectedProfit > 0, "Jede gezeigte Chance hat einen positiven Gewinn")
    expect(opportunity.cost > 0, "Jede gezeigte Chance hat einen Kapitaleinsatz")
    expectEqual(opportunity.roi, opportunity.expectedProfit / opportunity.cost,
        "ROI ist immer Gewinn geteilt durch Kapitaleinsatz")
    -- Datenmodell fuer 0.7: vorbereitet, aber ausdruecklich leer.
    expectEqual(opportunity.liquidity, nil, "liquidity bleibt leer statt erfunden")
    expectEqual(opportunity.sellThrough, nil, "sellThrough bleibt leer")
    expectEqual(opportunity.expectedHours, nil, "expectedHours bleibt leer")
    expectEqual(opportunity.profitVelocity, nil, "profitVelocity bleibt leer")
    expectEqual(opportunity.futureDemandScore, nil, "futureDemandScore bleibt leer")
    expectEqual(opportunity.liquidityScore, nil, "liquidityScore bleibt leer")
    expectEqual(opportunity.hypeScore, nil, "hypeScore bleibt leer")
    expectEqual(opportunity.riskScore, nil, "riskScore bleibt leer")
    expectEqual(opportunity.catalysts, nil, "catalysts bleibt leer")
    expectEqual(opportunity.phase, nil, "phase bleibt leer")
    expectEqual(opportunity.exitWindow, nil, "exitWindow bleibt leer")
end

-- Der Zeilendeckel kappt die Liste, nicht die Zaehlung: Eine still gekappte
-- Zahl waere eine Falschaussage.
local savedMaxRows = OPP.MAX_ROWS
OPP.MAX_ROWS = 2
Opportunity:Invalidate()
local capped = Opportunity:ComputeReport()
expectEqual(#capped.opportunities, 2, "Der Zeilendeckel begrenzt die Liste")
expectEqual(capped.listed, 2, "...und benennt, wie viele gelistet sind")
expect(capped.shownCount > 2, "Die Zahl der gefundenen Chancen bleibt ungekappt")
expectEqual(capped.truncated, capped.shownCount - 2,
    "Die Zahl der nicht gezeigten Chancen steht ausdruecklich da")
OPP.MAX_ROWS = savedMaxRows
Opportunity:Invalidate()

-- Die Kopfzeile zaehlt, sie wirbt nicht.
expect(Opportunity:SummaryText(sorted):find("Chance") ~= nil,
    "Die Kopfzeile nennt die Zahl der gefundenen Chancen")
expectEqual(Opportunity:SummaryText({ shownCount = 1, total = 1 }),
    "Gold Copilot hat 1 interessante Chance gefunden", "Einzahl im Singular")
expectEqual(Opportunity:SummaryText({ shownCount = 0, total = 0 }),
    "Gold Copilot hat noch keine belastbare Chance gefunden",
    "Ohne Chance wird nichts behauptet")
expect(Opportunity:SummaryText({ shownCount = 0, total = 5 }):find("Filter") ~= nil,
    "Ausgefilterte Chancen werden als solche benannt")

-- Jede Chance erklaert ihre komplette Rechnung.
local explained = Opportunity:Explain(findOpportunity(sorted, "craft", 60001))
local explainedText = table.concat(explained, "\n")
for _, needle in ipairs({
    "Materialkosten:", "Produkterlös netto", "Kapitaleinsatz:", "Erlös netto:",
    "Theoretischer Gewinn:", "ROI:", "Opportunity Score:", "Confidence:",
}) do
    expect(explainedText:find(needle, 1, true) ~= nil,
        "Die Erklärung nennt \"" .. needle .. "\"")
end
expect(explainedText:find("Liquidität", 1, true) ~= nil,
    "Die Erklärung sagt ausdrücklich, was in dieser Version fehlt")
expect(explainedText:find("keine Zusage", 1, true) ~= nil,
    "Die Erklärung verspricht ausdrücklich keinen Gewinn")
expect(explainedText:find("garantiert") == nil,
    "Nirgends steht \"garantiert\"")
expectEqual(#Opportunity:Explain(nil), 0, "Ohne Chance gibt es keine Erklärung")
expectEqual(Opportunity:FormatROI(0.269), "26.9 %", "ROI-Format")
expectEqual(Opportunity:TypeLabel("craft"), "Craft", "Typbezeichnung")
expectEqual(Opportunity:TypeLabel("unbekannt"), "Chance", "Unbekannter Typ bleibt neutral")

-- ---------------------------------------------------------------------------
-- Opportunity Engine: Cache
-- ---------------------------------------------------------------------------

Opportunity:Invalidate()
local firstReport = Opportunity:BuildReport()
local secondReport = Opportunity:BuildReport()
expect(rawequal(firstReport, secondReport),
    "Ein zweiter Aufruf liefert den gecachten Bericht statt neu zu scannen")

Market:Touch()
local afterTouch = Opportunity:BuildReport()
expect(not rawequal(firstReport, afterTouch),
    "Neue Marktdaten verwerfen den Cache")

GCP.db.options.opportunityMinProfit = 999
local afterOption = Opportunity:BuildReport()
expect(not rawequal(afterTouch, afterOption),
    "Geaenderte Optionen verwerfen den Cache")
GCP.db.options.opportunityMinProfit = 0

local afterCrafts = Opportunity:BuildReport()
GCP.Crafts.revision = GCP.Crafts.revision + 1
expect(not rawequal(afterCrafts, Opportunity:BuildReport()),
    "Neu gescannte Rezepte verwerfen den Cache")

Opportunity:Invalidate()
expectEqual(Opportunity.cache, nil, "Invalidate leert den Cache")

-- ---------------------------------------------------------------------------
-- Watchlist
-- ---------------------------------------------------------------------------

local watchItem = 55555
expectEqual(Market:IsWatched(watchItem), false, "Ein unbekanntes Item ist nicht beobachtet")
expectEqual(Market:RegisterWatchItem(watchItem, "Test"), true,
    "Ein Item laesst sich zur Beobachtung anmelden")
expectEqual(Market:IsWatched(watchItem), true, "Danach ist es beobachtet")
expectEqual(Market:RegisterWatchItem(watchItem, "Test"), false,
    "Dieselbe Anmeldung zweimal aendert nichts")
expectEqual(GCP.db.watchlist[watchItem].reason, "Test",
    "Die Begruendung landet in den SavedVariables")
expect(type(GCP.db.watchlist[watchItem].addedAt) == "number",
    "Der Zeitpunkt der Aufnahme wird festgehalten")
local addedAt = GCP.db.watchlist[watchItem].addedAt
Market:RegisterWatchItem(watchItem, "Neue Begruendung")
expectEqual(GCP.db.watchlist[watchItem].reason, "Neue Begruendung",
    "Eine neue Begruendung wird uebernommen")
expectEqual(GCP.db.watchlist[watchItem].addedAt, addedAt,
    "...der Zeitpunkt der Aufnahme bleibt aber stehen")
expectEqual(Market:RegisterWatchItem("keine Zahl"), false,
    "Eine ungueltige Item-ID wird abgelehnt")
expectEqual(Market:RegisterWatchItem(-5), false, "Eine negative Item-ID wird abgelehnt")

-- Beobachtete Items landen in der Beobachtungsliste der Market Engine, auch
-- wenn sie sonst nirgends vorkommen.
Market:InvalidateTrackedCache()
local watchedTracked = {}
for _, itemID in ipairs(Market:GetTrackedItems()) do watchedTracked[itemID] = true end
expectEqual(watchedTracked[watchItem], true,
    "Watchlist-Items stehen automatisch in Market:GetTrackedItems()")
expectEqual(Market:GetTrackReason(watchItem), "Watchlist",
    "...und nennen die Watchlist als Grund")

local watchlist = Market:GetWatchlist()
expectEqual(#watchlist, 1, "Die Watchlist liefert ihre Eintraege")
expectEqual(watchlist[1].itemID, watchItem, "...mit Item-ID")
expectEqual(Market:CountWatchItems(), 1, "Die Watchlist laesst sich zaehlen")

expectEqual(Market:ToggleWatchItem(watchItem), false, "Ein zweiter Klick nimmt heraus")
expectEqual(Market:IsWatched(watchItem), false, "Danach ist es nicht mehr beobachtet")
expectEqual(Market:ToggleWatchItem(watchItem, "Chancen-Tab"), true, "Und wieder hinein")
expectEqual(Market:RemoveWatchItem(watchItem), true, "Entfernen meldet Erfolg")
expectEqual(Market:RemoveWatchItem(watchItem), false, "Zweimal entfernen aendert nichts")
Market:InvalidateTrackedCache()
watchedTracked = {}
for _, itemID in ipairs(Market:GetTrackedItems()) do watchedTracked[itemID] = true end
expectEqual(watchedTracked[watchItem], nil,
    "Nach dem Entfernen wird das Item nicht mehr beobachtet")

-- Deckel: eine vollgeklickte Liste darf die Aufzeichnung nicht verdraengen.
local savedWatchCap = GCP.Constants.MARKET.MAX_WATCH_ITEMS
GCP.Constants.MARKET.MAX_WATCH_ITEMS = 2
expectEqual(Market:RegisterWatchItem(70001, "Test"), true, "Erstes Item passt")
expectEqual(Market:RegisterWatchItem(70002, "Test"), true, "Zweites Item passt")
expectEqual(Market:RegisterWatchItem(70003, "Test"), false, "Das dritte sprengt den Deckel")
expectEqual(Market:IsWatched(70003), false, "...und wird nicht aufgenommen")
Market:RemoveWatchItem(70001)
Market:RemoveWatchItem(70002)
GCP.Constants.MARKET.MAX_WATCH_ITEMS = savedWatchCap

-- Die Engine bietet dieselben Funktionen unter ihrem eigenen Namen an.
expectEqual(Opportunity:RegisterWatchItem(watchItem, "Chancen-Tab"), true,
    "Opportunity:RegisterWatchItem meldet an")
expectEqual(Opportunity:IsWatched(watchItem), true, "Opportunity:IsWatched antwortet")
expectEqual(#Opportunity:GetWatchlist(), 1, "Opportunity:GetWatchlist liefert die Liste")
expectEqual(Opportunity:RemoveWatchItem(watchItem), true, "Opportunity:RemoveWatchItem entfernt")

-- ---------------------------------------------------------------------------
-- Chancen-Protokoll (Datenmodell fuer 0.7)
-- ---------------------------------------------------------------------------

GCP.db.opportunityHistory = {}
local logCandidate = {
    type = "craft", itemID = 60001, cost = 2000,
    expectedProfit = 5600, opportunityScore = 75, confidence = "high",
}
expectEqual(Opportunity:ShouldLog(logCandidate, mockNow), true,
    "Eine neue, belastbare Chance wird protokolliert")
expectEqual(Opportunity:LogReport({ opportunities = { logCandidate } }, mockNow), 1,
    "Der Eintrag landet im Protokoll")
expectEqual(#GCP.db.opportunityHistory, 1, "Genau ein Eintrag")
local logged = GCP.db.opportunityHistory[1]
expectEqual(logged.type, "craft", "Der Eintrag nennt die Art")
expectEqual(logged.itemID, 60001, "Der Eintrag nennt das Item")
expectEqual(logged.marketPrice, 2000, "Der Eintrag haelt den Preis fest")
expectEqual(logged.expectedProfit, 5600, "Der Eintrag haelt die erwartete Marge fest")
expectEqual(logged.opportunityScore, 75, "Der Eintrag haelt den Score fest")
expectEqual(logged.confidence, "high", "Der Eintrag haelt die Confidence fest")
expectEqual(logged.timestamp, mockNow, "Der Eintrag haelt den Zeitpunkt fest")

-- Unveraendert und kurz danach: kein zweiter Eintrag. Genau das verhindert,
-- dass ein UI-Refresh das Protokoll flutet.
expectEqual(Opportunity:ShouldLog(logCandidate, mockNow + 60), false,
    "Dieselbe Chance kurz danach wird nicht erneut protokolliert")
expectEqual(Opportunity:LogReport({ opportunities = { logCandidate } }, mockNow + 60), 0,
    "Ein erneuter Durchlauf schreibt nichts")
expectEqual(#GCP.db.opportunityHistory, 1, "Das Protokoll bleibt bei einem Eintrag")

expectEqual(Opportunity:ShouldLog(logCandidate, mockNow + OPP.HISTORY.MIN_INTERVAL), true,
    "Nach sechs Stunden wird wieder protokolliert")
local movedScore = {}
for key, value in pairs(logCandidate) do movedScore[key] = value end
movedScore.opportunityScore = 90
expectEqual(Opportunity:ShouldLog(movedScore, mockNow + 60), true,
    "Ein deutlich veraenderter Score wird sofort protokolliert")
local movedProfit = {}
for key, value in pairs(logCandidate) do movedProfit[key] = value end
movedProfit.expectedProfit = 5600 * 2
expectEqual(Opportunity:ShouldLog(movedProfit, mockNow + 60), true,
    "Eine deutlich veraenderte Marge wird sofort protokolliert")

-- Schwache Chancen kommen gar nicht erst ins Protokoll.
local weakScore = {}
for key, value in pairs(logCandidate) do weakScore[key] = value end
weakScore.opportunityScore = OPP.HISTORY.MIN_SCORE - 1
weakScore.itemID = 60002
expectEqual(Opportunity:ShouldLog(weakScore, mockNow), false,
    "Eine schwache Chance wird nicht protokolliert")
local weakConfidence = {}
for key, value in pairs(logCandidate) do weakConfidence[key] = value end
weakConfidence.confidence = "low"
weakConfidence.itemID = 60003
expectEqual(Opportunity:ShouldLog(weakConfidence, mockNow), false,
    "Eine duenne Datenlage wird nicht protokolliert")

-- Aufbewahrung: 90 Tage, danach faellt es raus.
GCP.db.opportunityHistory = {
    { timestamp = mockNow - 100 * 86400, type = "craft", itemID = 1,
      opportunityScore = 70, confidence = "high" },
    { timestamp = mockNow - 10 * 86400, type = "craft", itemID = 2,
      opportunityScore = 70, confidence = "high" },
}
expectEqual(Opportunity:PruneHistory(mockNow), 1, "Ein Eintrag ist zu alt")
expectEqual(#GCP.db.opportunityHistory, 1, "Der juengere bleibt")
expectEqual(GCP.db.opportunityHistory[1].itemID, 2, "...und zwar der richtige")

-- Obergrenze: die aeltesten Eintraege fallen zuerst.
local savedMaxEntries = OPP.HISTORY.MAX_ENTRIES
OPP.HISTORY.MAX_ENTRIES = 3
GCP.db.opportunityHistory = {}
for index = 1, 6 do
    GCP.db.opportunityHistory[index] = {
        timestamp = mockNow - (10 - index) * 3600, type = "craft", itemID = index,
        opportunityScore = 70, confidence = "high",
    }
end
Opportunity:PruneHistory(mockNow)
expectEqual(#GCP.db.opportunityHistory, 3, "Die Obergrenze haelt")
expectEqual(GCP.db.opportunityHistory[1].itemID, 4, "Die aeltesten Eintraege fallen zuerst")
OPP.HISTORY.MAX_ENTRIES = savedMaxEntries
GCP.db.opportunityHistory = {}

-- Der Weg ueber BuildReport schreibt nur beim echten Neuberechnen mit.
Market:Reset()
GCP.db.opportunityHistory = {}
Opportunity:Invalidate()
Opportunity:BuildReport()
local afterFirstBuild = #GCP.db.opportunityHistory
Opportunity:BuildReport()
Opportunity:BuildReport()
expectEqual(#GCP.db.opportunityHistory, afterFirstBuild,
    "Ein Cache-Treffer schreibt nie ins Protokoll")

GCP.db.options.opportunityMinProfit = GCP.Constants.OPPORTUNITY.DEFAULT_MIN_PROFIT
GCP.db.options.opportunityMinROI = GCP.Constants.OPPORTUNITY.DEFAULT_MIN_ROI

-- ---------------------------------------------------------------------------
-- Future Market / Catalyst Engine (0.7.0)
--
-- Der ganze Abschnitt liegt in einem do-Block: Lua begrenzt die Zahl
-- gleichzeitig sichtbarer lokaler Variablen je Chunk, und diese Datei ist ein
-- einziger Chunk. Nach dem Block sind die Namen wieder frei.
-- ---------------------------------------------------------------------------
-- Jeder Abschnitt laeuft in einer eigenen Funktion: Lua begrenzt die Zahl
-- gleichzeitig sichtbarer lokaler Variablen je Funktion auf 200, und dieser
-- Chunk hat die Grenze fast erreicht. Eine wiederverwendete Variable statt
-- zehn benannter haelt den Verbrauch bei genau eins.
local futureSection

futureSection = function()
    local K, F = GCP.Knowledge, GCP.Future
    local FUT = GCP.Constants.FUTURE
    local phase3 = K:GetPhase("phase3")

    -- Die Uhr wird relativ zum Phase-3-Termin gestellt, nicht auf ein festes
    -- Datum: So ist der Abstand exakt 18 Tage und eine Stunde, egal in welcher
    -- Zeitzone der Test laeuft.
    mockNow = phase3.release - 18 * 86400 - 3600
    Market:Reset()
    Market:InvalidateCaches()
    Market:InvalidateTrackedCache()
    F:Invalidate()

    -- --- Wissensbasis und Provenance ---------------------------------------
    expect(type(K.VERSION) == "string" and #K.VERSION > 0,
        "Die Wissensbasis nennt ihren Stand")
    expectEqual(K:RejectedCount(), 0,
        "Die ausgelieferte Wissensbasis enthaelt keinen ungueltigen Eintrag")
    expect(#K.catalysts > 0, "Es gibt Catalysts")
    expect(#K.edges > 0, "Es gibt Rezeptkanten")

    local withoutSource = 0
    for _, catalyst in ipairs(K.catalysts) do
        if not K.SOURCE_RANK[catalyst.sourceConfidence]
            or type(catalyst.sourceName) ~= "string" or catalyst.sourceName == ""
            or type(catalyst.reason) ~= "string" or catalyst.reason == "" then
            withoutSource = withoutSource + 1
        end
    end
    expectEqual(withoutSource, 0, "Jeder Catalyst nennt Herkunft und Begruendung")

    withoutSource = 0
    for _, edge in ipairs(K.edges) do
        if not K.SOURCE_RANK[edge.sourceConfidence] then
            withoutSource = withoutSource + 1
        end
    end
    expectEqual(withoutSource, 0, "Jede Rezeptkante nennt ihre Herkunft")

    -- Datenhygiene in beide Richtungen: kein Item ohne Aussage, keine Aussage
    -- ueber ein Item, das die Wissensbasis gar nicht kennt.
    local referenced = {}
    for _, catalyst in ipairs(K.catalysts) do referenced[catalyst.itemID] = true end
    for _, edge in ipairs(K.edges) do
        referenced[edge.from] = true
        referenced[edge.to] = true
    end
    local orphans, unnamed = 0, 0
    for _, entry in ipairs(K.itemList) do
        if not referenced[entry.id] then orphans = orphans + 1 end
    end
    for itemID in pairs(referenced) do
        if not K:GetItem(itemID) then unnamed = unnamed + 1 end
    end
    expectEqual(orphans, 0,
        "Kein Item steht in der Wissensbasis, ueber das sie nichts aussagt")
    expectEqual(unnamed, 0,
        "Ueber kein Item wird etwas ausgesagt, das die Wissensbasis nicht kennt")

    withoutSource = 0
    for _, phase in ipairs(K:GetPhases()) do
        if phase.release ~= nil and (type(phase.sourceName) ~= "string"
            or phase.sourceName == "") then
            withoutSource = withoutSource + 1
        end
    end
    expectEqual(withoutSource, 0, "Jeder exakte Termin nennt seine Quelle")

    -- Die Pruefung laesst nichts durch, was keine Herkunft hat.
    local rejectedBefore = K:RejectedCount()
    expectEqual(K:RegisterCatalyst({
        id = "test-ohne-provenance", itemID = 990001, type = "NEW_RAID",
        direction = "demand_up", strength = 0.5, confidence = "high",
        reason = "Test",
    }), false, "Ein Catalyst ohne Provenance wird abgelehnt")
    expectEqual(K:RegisterCatalyst({
        id = "test-unbekannter-typ", itemID = 990001, type = "GIBT_ES_NICHT",
        direction = "demand_up", strength = 0.5, confidence = "high",
        reason = "Test", sourceConfidence = "historical", sourceName = "Test",
    }), false, "Ein unbekannter Catalyst-Typ wird abgelehnt")
    expectEqual(K:RegisterCatalyst({
        id = "test-staerke", itemID = 990001, type = "NEW_RAID",
        direction = "demand_up", strength = 5, confidence = "high",
        reason = "Test", sourceConfidence = "historical", sourceName = "Test",
    }), false, "Eine Staerke ausserhalb 0..1 wird abgelehnt")
    expectEqual(K:RegisterEdge({
        from = 990001, to = 990001, relation = "craft_material",
        sourceConfidence = "historical", sourceName = "Test",
    }), false, "Eine Kante auf sich selbst wird abgelehnt")
    expectEqual(K:RejectedCount(), rejectedBefore + 4,
        "Verworfene Eintraege werden gezaehlt statt still geschluckt")

    -- --- Zeitrechnung ------------------------------------------------------
    expectEqual(K:UTC({ year = 1970, month = 1, day = 1 }), 0,
        "Die Zeitrechnung der Wissensbasis ist zeitzonenfrei")
    expectEqual(K:UTC({ year = 2026, month = 8, day = 27, hour = 22, min = 0 }),
        1787868000, "Der Phase-3-Termin rechnet sich exakt in UTC um")
    expectEqual(K:UTC({ year = 2024, month = 2, day = 29 }), 1709164800,
        "Schaltjahre gehen auf")
    expectEqual(K:UTC("kein Datum"), nil, "Ohne Datumstabelle gibt es keinen Zeitpunkt")

end
futureSection()

futureSection = function()
    local K, F = GCP.Knowledge, GCP.Future
    local FUT = GCP.Constants.FUTURE
    local phase3 = K:GetPhase("phase3")

    -- --- Phasen ------------------------------------------------------------
    expectEqual(F:GetCurrentPhase().id, "phase2",
        "Vor dem Phase-3-Termin laeuft noch Phase 2")
    local upcoming = F:GetUpcomingPhases()
    expect(#upcoming >= 3, "Es sind mehrere Phasen bekannt, die noch kommen")
    expectEqual(upcoming[1].id, "phase3", "Die naechste Phase steht vorn")
    expectEqual(F:GetNextPhase().id, "phase3", "GetNextPhase liefert dieselbe")
    expectEqual(phase3.sourceConfidence, "official",
        "Der Phase-3-Termin ist offiziell belegt")
    expectEqual(K:GetPhase("phase4").release, nil,
        "Ohne Anniversary-Ankuendigung gibt es kein Datum")
    expectEqual(K:PhaseStatus(K:GetPhase("phase4"), mockNow), "upcoming",
        "Eine Phase ohne Termin gilt trotzdem als noch kommend")
    expectEqual(K:PhaseStatus(phase3, phase3.release + 60), "live",
        "Nach ihrem Termin laeuft die Phase")

    -- --- Zeitfenster -------------------------------------------------------
    local timing = F:PhaseTiming("phase3", mockNow)
    expectEqual(timing.daysUntil, 18, "Bis Phase 3 sind es 18 Tage")
    expectEqual(timing.zone, "ACCUMULATION", "18 Tage vorher ist Aufbauphase")
    expectEqual(F:PhaseTiming("phase3", phase3.release - 40 * 86400).zone, "EARLY",
        "40 Tage vorher ist es frueh")
    expectEqual(F:PhaseTiming("phase3", phase3.release - 20 * 86400).zone, "ACCUMULATION",
        "20 Tage vorher ist Aufbauphase")
    expectEqual(F:PhaseTiming("phase3", phase3.release - 5 * 86400).zone, "PRE_RELEASE",
        "5 Tage vorher ist kurz vor Release")
    expectEqual(F:PhaseTiming("phase3", phase3.release - 3600).zone, "RELEASE",
        "Am Releasetag ist Releasefenster")
    expectEqual(F:PhaseTiming("phase3", phase3.release + 3 * 86400).zone, "POST_RELEASE",
        "Danach ist danach")
    expectEqual(F:PhaseTiming("phase4", mockNow).zone, "UNKNOWN",
        "Ohne Termin gibt es kein Zeitfenster")
    expectEqual(F:PhaseTiming("phase4", mockNow).daysUntil, nil,
        "...und erst recht keine Tageszahl")
    expect(F:TimingLabel("ACCUMULATION") ~= F:TimingLabel("POST_RELEASE"),
        "Jedes Zeitfenster hat seinen eigenen Text")

end
futureSection()

futureSection = function()
    local K, F = GCP.Knowledge, GCP.Future
    local FUT = GCP.Constants.FUTURE
    local phase3 = K:GetPhase("phase3")

    -- --- Catalysts am Item -------------------------------------------------
    local shadow = F:GetItemRecord(22456)          -- Urschatten
    expect(#shadow.catalysts >= 3, "Urschatten hat mehrere Catalysts")
    expectEqual(shadow.catalysts[1].depth, 0,
        "Der staerkste Grund ist ein direkter Catalyst")
    expectEqual(shadow.catalysts[1].zone, "ACCUMULATION",
        "Der Catalyst kennt sein Zeitfenster")
    expectEqual(shadow.catalysts[1].daysUntil, 18, "...und die Tage bis dahin")
    expect(shadow.futureDemandScore > 70,
        "Ein starker Widerstandsbedarf hebt den Future Demand deutlich")
    expectEqual(shadow.demand.downCount, 0, "Fuer Urschatten spricht nichts dagegen")
    expectEqual(shadow.phase, "phase3", "Die fuehrende Phase wird benannt")

    -- Heart of Darkness: Nachfrage UND Angebot gleichzeitig.
    local heart = F:GetItemRecord(32428)
    expect(heart.demand.upCount > 0, "Das Leitmaterial hat Nachfragegruende")
    expect(heart.demand.downCount > 0, "...und einen Angebots-Catalyst")
    expect(heart.futureDemandScore < shadow.futureDemandScore,
        "Der Angebots-Catalyst daempft den Score gegenueber reiner Nachfrage")
    expect(heart.futureDemandScore > 50,
        "...ohne ihn ins Negative zu drehen, denn die Nachfrage ueberwiegt")

    -- Ein Catalyst nach unten senkt den Score unter die Mitte.
    local rareGem = F:GetItemRecord(23436)         -- Blutrubin
    expect(rareGem.futureDemandScore < 50,
        "Ein reiner Nachfrage-Abwaerts-Catalyst drueckt unter 50")
    expectEqual(rareGem.demand.upCount, 0, "...und hat keine Gegenrichtung")

    -- --- Dependency Graph --------------------------------------------------
    expectEqual(F:GetItemRecord(32391).catalysts[1].depth, 0,
        "Ebene 0: das Item selbst")
    local imbued = F:GetItemRecord(21842)          -- direkte Zutat
    expect(#imbued.catalysts > 0, "Ebene 1: die Zutat erbt den Catalyst")
    expectEqual(imbued.catalysts[1].depth, 1, "...auf Ebene 1")
    expect(imbued.catalysts[1].viaItemID ~= nil,
        "Die Erklaerung weiss, ueber welches Produkt sie kommt")
    local ore = F:GetItemRecord(23425)             -- Erz ueber den Barren
    expect(#ore.catalysts > 0, "Ebene 2: die Zutat der Zutat erbt auch noch")
    expectEqual(ore.catalysts[1].depth, 2, "...auf Ebene 2")
    local cloth = F:GetItemRecord(21877)           -- Netherstoff, Ebene 3
    expectEqual(#cloth.catalysts, 0,
        "Ab Ebene 3 wird nicht weiter propagiert - sonst ist am Ende alles bullish")
    expectEqual(cloth.futureDemandScore, FUT.DEMAND.NEUTRAL,
        "Ohne Catalyst bleibt der Future Demand exakt neutral")
    expectEqual(cloth.demand.hasCatalysts, false, "...und sagt das auch")

    -- Die Abschwaechung je Ebene ist die eigentliche Aussage.
    expect(imbued.catalysts[1].propagation < 1, "Ebene 1 zaehlt abgeschwaecht")
    expect(ore.catalysts[1].propagation < imbued.catalysts[1].propagation,
        "Ebene 2 zaehlt noch schwaecher")

    -- Kreise im Graphen duerfen keine Endlosschleife werden. Die
    -- Alchemie-Umwandlungen aus Constants.lua sind welche (Urfeuer <-> Urmana),
    -- und hier kommt zur Sicherheit ein ausdruecklicher dazu.
    K:RegisterEdge({ from = 990101, to = 990102, relation = "craft_material",
        sourceConfidence = "historical", sourceName = "Test" })
    K:RegisterEdge({ from = 990102, to = 990101, relation = "craft_material",
        sourceConfidence = "historical", sourceName = "Test" })
    K:RegisterCatalyst({ id = "test-kreis", itemID = 990102, phase = "phase3",
        type = "NEW_RAID", direction = "demand_up", strength = 0.8,
        confidence = "high", reason = "Test", sourceConfidence = "historical",
        sourceName = "Test" })
    F:Invalidate()
    local cycle = F:GetItemRecord(990101)
    expectEqual(#cycle.catalysts, 1, "Ein Kreis im Graphen liefert genau einen Fund")
    expectEqual(cycle.catalysts[1].depth, 1, "...auf der richtigen Ebene")
    expect(F:GetItemRecord(22457) ~= nil,
        "Auch die Umwandlungskreise der Ur-Partikel laufen nicht endlos")

end
futureSection()

futureSection = function()
    local K, F = GCP.Knowledge, GCP.Future
    local FUT = GCP.Constants.FUTURE
    local phase3 = K:GetPhase("phase3")

    -- --- Future Demand: Confidence und Provenance wirken -------------------
    K:RegisterCatalyst({ id = "test-demand-high", itemID = 990201, phase = "phase3",
        type = "NEW_RAID", direction = "demand_up", strength = 0.8,
        confidence = "high", reason = "Test", sourceConfidence = "official",
        sourceName = "Test" })
    K:RegisterCatalyst({ id = "test-demand-low", itemID = 990202, phase = "phase3",
        type = "NEW_RAID", direction = "demand_up", strength = 0.8,
        confidence = "low", reason = "Test", sourceConfidence = "official",
        sourceName = "Test" })
    K:RegisterCatalyst({ id = "test-demand-inferred", itemID = 990203, phase = "phase3",
        type = "NEW_RAID", direction = "demand_up", strength = 0.8,
        confidence = "high", reason = "Test", sourceConfidence = "inferred",
        sourceName = "Test" })
    K:RegisterCatalyst({ id = "test-demand-supply", itemID = 990204, phase = "phase3",
        type = "NEW_RAID", direction = "demand_up", strength = 0.8,
        confidence = "high", reason = "Test", sourceConfidence = "official",
        sourceName = "Test" })
    K:RegisterCatalyst({ id = "test-demand-supply2", itemID = 990204, phase = "phase3",
        type = "SUPPLY_INCREASE", direction = "supply_up", strength = 0.8,
        confidence = "high", reason = "Test", sourceConfidence = "official",
        sourceName = "Test" })
    K:RegisterCatalyst({ id = "test-demand-second", itemID = 990205, phase = "phase3",
        type = "NEW_RAID", direction = "demand_up", strength = 0.8,
        confidence = "high", reason = "Test", sourceConfidence = "official",
        sourceName = "Test" })
    K:RegisterCatalyst({ id = "test-demand-second-b", itemID = 990205, phase = "phase3",
        type = "NEW_RECIPE", direction = "demand_up", strength = 0.8,
        confidence = "high", reason = "Test", sourceConfidence = "official",
        sourceName = "Test" })
    F:Invalidate()

    expectEqual(F:GetFutureDemandScore(990999), FUT.DEMAND.NEUTRAL,
        "Ein unbekanntes Item ist neutral, nicht schlecht")
    local strong = F:GetFutureDemandScore(990201)
    expect(strong > 50, "Ein starker Catalyst hebt den Future Demand")
    expect(F:GetFutureDemandScore(990202) < strong,
        "Dieselbe Behauptung mit niedriger Confidence zaehlt weniger")
    expect(F:GetFutureDemandScore(990203) < strong,
        "Abgeleitetes Wissen zaehlt weniger als offizielles")
    expect(F:GetFutureDemandScore(990204) < strong,
        "Ein Angebots-Catalyst senkt den Score")
    expectEqual(F:GetFutureDemandScore(990204), FUT.DEMAND.NEUTRAL,
        "Gleich starke Nachfrage und Angebot heben sich exakt auf")
    expect(F:GetFutureDemandScore(990205) > strong,
        "Zwei unabhaengige Gruende wiegen mehr als einer")
    expect(F:GetFutureDemandScore(990205) < 2 * strong - 50,
        "...aber nicht doppelt so viel")

    -- Das Zeitfenster wirkt: nach dem Release zaehlt derselbe Catalyst weniger.
    local beforeRelease = F:GetFutureDemandScore(990201)
    mockNow = phase3.release + 5 * 86400
    Market:InvalidateCaches()
    F:Invalidate()
    expect(F:GetFutureDemandScore(990201) < beforeRelease,
        "Nach dem Release zaehlt eine bekannte Ankuendigung weniger")
    mockNow = phase3.release - 18 * 86400 - 3600
    Market:InvalidateCaches()
    F:Invalidate()

end
futureSection()

futureSection = function()
    local K, F = GCP.Knowledge, GCP.Future
    local FUT = GCP.Constants.FUTURE
    local phase3 = K:GetPhase("phase3")

    -- --- Hype Score --------------------------------------------------------
    local hypeItem = 990301
    marketPrices[hypeItem] = 10000
    seedSeries(hypeItem, { 10000, 10100, 9900, 10000, 10050, 9950, 10000, 10100,
        9900, 10000, 10050, 9950 }, mockNow - 10 * 86400, 20 * 3600)
    F:Invalidate()
    local calmHype = F:GetHypeScore(hypeItem)
    expect(type(calmHype) == "number", "Mit genug Historie gibt es einen Hype Score")
    expect(calmHype < 30, "Ein Preis an seinem Median ist kein Hype")

    marketPrices[hypeItem] = 16000
    Market:InvalidateCaches()
    F:Invalidate()
    local richHype = F:GetHypeScore(hypeItem)
    expect(richHype > calmHype + 30,
        "Ein Preis weit ueber dem 30-Tage-Median schlaegt als Hype durch")

    marketPrices[hypeItem] = 10000
    local momentumItem = 990302
    marketPrices[momentumItem] = 13000
    seedSeries(momentumItem, { 10000, 10000, 10000, 10000, 10000, 10000, 10000,
        10000, 12500, 13000, 13200, 13000 }, mockNow - 20 * 86400, 40 * 3600)
    F:Invalidate()
    local momentumHype = F:GetHypeScore(momentumItem)
    expect(type(momentumHype) == "number", "Auch hier gibt es einen Hype Score")
    expect(momentumHype > calmHype + 20,
        "Ein steigender 7-Tage-Median schlaegt als Momentum durch")

    local thinItem = 990303
    marketPrices[thinItem] = 50000
    seedSeries(thinItem, { 50000, 51000, 52000 }, mockNow - 3 * 3600, 3600)
    F:Invalidate()
    expectEqual(F:GetHypeScore(thinItem), nil,
        "Zu wenige Tage ergeben keinen Hype Score - und schon gar keinen niedrigen")

    -- Die zweite Haelfte derselben Bedingung: genug Tage, zu wenige Messpunkte.
    local sparseItem = 990304
    marketPrices[sparseItem] = 50000
    seedSeries(sparseItem, { 50000, 51000, 52000, 51500 }, mockNow - 6 * 86400, 86400)
    F:Invalidate()
    expectEqual(F:GetHypeScore(sparseItem), nil,
        "Vier Messpunkte ueber sechs Tage sind ebenfalls zu duenn fuer einen Hype Score")

    -- --- Einstiegszone und Nicht-Hinterherlaufen ---------------------------
    local entryItem = 990401
    marketPrices[entryItem] = 10000
    seedSeries(entryItem, { 9000, 9500, 10000, 10500, 11000, 9200, 9800, 10200,
        10800, 9600, 10000, 10400 }, mockNow - 12 * 86400, 20 * 3600)
    F:Invalidate()
    local entryRecord = F:GetItemRecord(entryItem)
    expect(type(entryRecord.entryPrice) == "number",
        "Mit belastbarer Historie gibt es eine Einstiegszone")
    expect(entryRecord.entryPrice < entryRecord.stats.median30,
        "Die Einstiegszone liegt unter dem 30-Tage-Median")
    expect(entryRecord.entryPrice <= (entryRecord.stats.q25 or 0),
        "...und nicht ueber dem unteren Quartil")
    expectEqual(entryRecord.dontChase, false,
        "Ein Preis mitten in der Spanne ist kein Hinterherlaufen")

    expectEqual(F:GetItemRecord(thinItem).entryPrice, nil,
        "Ohne belastbare Historie gibt es keine Einstiegszone")

    marketPrices[entryItem] = 20000
    Market:InvalidateCaches()
    F:Invalidate()
    local chased = F:GetItemRecord(entryItem)
    expectEqual(chased.dontChase, true,
        "Weit ueber der eigenen Spanne wird gewarnt statt hinterhergelaufen")
    expect(type(chased.dontChaseReason) == "string" and #chased.dontChaseReason > 0,
        "...und die Warnung sagt, warum")
    marketPrices[entryItem] = 10000

end
futureSection()

futureSection = function()
    local K, F = GCP.Knowledge, GCP.Future
    local FUT = GCP.Constants.FUTURE
    local phase3 = K:GetPhase("phase3")

    -- --- Investment Signal -------------------------------------------------
    local cheapStrong = F:ComputeSignal({ futureDemandScore = 90, marketScore = 85,
        hypeScore = 20, zone = "ACCUMULATION", knowledgeConfidence = "high",
        marketConfidence = "high" })
    expect(cheapStrong >= 80,
        "Guenstiger Preis und starker Catalyst ergeben ein starkes Signal")
    local expensiveStrong = F:ComputeSignal({ futureDemandScore = 90, marketScore = 20,
        hypeScore = 20, zone = "ACCUMULATION", knowledgeConfidence = "high",
        marketConfidence = "high" })
    expect(expensiveStrong < cheapStrong,
        "Derselbe Catalyst bei teurem Preis ergibt ein schwaecheres Signal")
    local cheapNoCatalyst = F:ComputeSignal({ futureDemandScore = 50, marketScore = 85,
        zone = "UNKNOWN", marketConfidence = "high" })
    expect(cheapNoCatalyst < cheapStrong,
        "Guenstig ohne Catalyst ist weniger als guenstig mit Catalyst")
    expect(cheapNoCatalyst > 50,
        "...bleibt aber ueber der Mitte, denn der Preis ist ja guenstig")
    local hyped = F:ComputeSignal({ futureDemandScore = 92, marketScore = 24,
        hypeScore = 88, zone = "ACCUMULATION", knowledgeConfidence = "high",
        marketConfidence = "high" })
    expect(hyped < 60,
        "Starker Catalyst, aber bereits eingepreist: kein starkes Signal mehr")
    expect(hyped < expensiveStrong,
        "Hoher Hype senkt das Signal gegenueber demselben Fall ohne Hype")
    local weakKnowledge = F:ComputeSignal({ futureDemandScore = 90, marketScore = 85,
        hypeScore = 20, zone = "ACCUMULATION", knowledgeConfidence = "low",
        marketConfidence = "high" })
    expectEqual(weakKnowledge, FUT.SIGNAL.KNOWLEDGE_CAP.low,
        "Duennes Wissen deckelt das Signal hart")
    local noHistory = F:ComputeSignal({ futureDemandScore = 90, marketScore = nil,
        zone = "ACCUMULATION", knowledgeConfidence = "high", marketConfidence = "none" })
    expectEqual(noHistory, FUT.SIGNAL.MARKET_CAP.none,
        "Ohne Realm-Historie ist bei 55 Schluss, egal wie stark der Catalyst ist")
    expectEqual(F:ComputeSignal({ futureDemandScore = 50, marketScore = 50,
        zone = "UNKNOWN", marketConfidence = "high" }), 50,
        "Neutral bleibt neutral")
    expectEqual(select(2, F:ComputeSignal({ futureDemandScore = 50, marketScore = nil,
        zone = "UNKNOWN", marketConfidence = "high" })).marketKnown, false,
        "Ein fehlender Market Score wird als fehlend ausgewiesen, nicht als 0")

    expectEqual(F:ScoreBand(95), "außergewöhnlich interessant", "Band 90+")
    expectEqual(F:ScoreBand(80), "interessant", "Band 75+")
    expectEqual(F:ScoreBand(65), "beobachten", "Band 60+")
    expectEqual(F:ScoreBand(45), "neutral", "Band 40+")
    expectEqual(F:ScoreBand(30), "bereits teuer / schwaches Setup", "Band 25+")
    expectEqual(F:ScoreBand(10), "hohes Hype-Risiko / unattraktiv", "Band 0+")
    expectEqual(F:ScoreBand(nil), nil, "Ohne Zahl kein Band")

end
futureSection()

futureSection = function()
    local K, F = GCP.Knowledge, GCP.Future
    local FUT = GCP.Constants.FUTURE
    local phase3 = K:GetPhase("phase3")

    -- --- Erklaerung: Fakt und Modell bleiben getrennt ----------------------
    local explanation = F:GetExplanation(22456)
    expect(#explanation.positive > 0, "Die Erklaerung nennt Gruende dafuer")
    expect(#explanation.warnings > 0, "Die Erklaerung nennt Einschraenkungen")
    local kinds = {}
    for _, bucket in ipairs({ explanation.positive, explanation.negative,
        explanation.warnings, explanation.facts }) do
        for _, entry in ipairs(bucket) do
            expect(entry.kind == "fact" or entry.kind == "model",
                "Jede Zeile sagt, ob sie Fakt oder Modell ist")
            kinds[entry.kind] = true
        end
    end
    expectEqual(kinds.model, true, "Es gibt Modellaussagen")
    local warningText = ""
    for _, entry in ipairs(explanation.warnings) do
        warningText = warningText .. entry.text .. "\n"
    end
    expect(warningText:find("keine Preisgarantie", 1, true) ~= nil,
        "Die Erklaerung sagt ausdruecklich, dass sie nichts garantiert")
    local heartExplanation = F:GetExplanation(32428)
    expect(#heartExplanation.negative > 0,
        "Gegenargumente stehen als solche da, nicht bei den Gruenden")

    local emptyExplanation = F:GetExplanation(990999)
    expect(#emptyExplanation.positive == 0,
        "Ohne Catalyst gibt es keine Gruende")
    warningText = ""
    for _, entry in ipairs(emptyExplanation.warnings) do
        warningText = warningText .. entry.text .. "\n"
    end
    expect(warningText:find("Kein belastbarer zukünftiger Nachfragegrund") ~= nil,
        "...und das steht da auch so")

    -- Eine Phase ohne Termin wird als solche erklaert.
    K:RegisterCatalyst({ id = "test-phase4", itemID = 990501, phase = "phase4",
        type = "NEW_RAID", direction = "demand_up", strength = 0.6,
        confidence = "medium", reason = "Test", sourceConfidence = "historical",
        sourceName = "Test" })
    F:Invalidate()
    local unknownDate = F:GetItemRecord(990501)
    expectEqual(unknownDate.daysUntilCatalyst, nil,
        "Ohne Termin gibt es keine Tageszahl")
    expectEqual(unknownDate.timing, "UNKNOWN", "...und kein Zeitfenster")
    expect(unknownDate.futureDemandScore > 50,
        "Der Catalyst zaehlt trotzdem, nur schwaecher")
    warningText = ""
    for _, entry in ipairs(F:GetExplanation(990501).warnings) do
        warningText = warningText .. entry.text .. "\n"
    end
    expect(warningText:find("noch kein Termin angekündigt") ~= nil,
        "Die Erklaerung sagt, dass der Termin fehlt - statt einen zu erfinden")

    -- --- Item Knowledge ----------------------------------------------------
    local itemKnowledge = F:GetItemKnowledge(22456)
    expect(itemKnowledge ~= nil, "Die Wissensbasis kennt Urschatten")
    expect(#itemKnowledge.catalysts > 0, "...mit direkten Catalysts")
    expect(#itemKnowledge.products > 0, "...und weiss, wofuer es gebraucht wird")
    expectEqual(F:GetItemKnowledge(4242), nil,
        "Ueber ein beliebiges Item weiss die Wissensbasis nichts")
    expectEqual(F:GetItemKnowledge("keine Zahl"), nil,
        "Eine ungueltige Item-ID liefert nichts")

end
futureSection()

futureSection = function()
    local K, F = GCP.Knowledge, GCP.Future
    local FUT = GCP.Constants.FUTURE
    local phase3 = K:GetPhase("phase3")

    -- --- Bericht -----------------------------------------------------------
    F:Invalidate()
    local report = F:BuildReport()
    expect(#report.rows > 0, "Der Bericht hat Zeilen")
    expectEqual(report.knowledgeVersion, K.VERSION, "Der Bericht nennt den Wissensstand")
    expectEqual(report.nextPhase.id, "phase3", "...und den naechsten Catalyst")
    expect(report.graph.edges > 0, "...und die Groesse des Dependency Graphs")
    local previousScore = nil
    local withoutCatalyst = 0
    for _, row in ipairs(report.rows) do
        if not row.demand.hasCatalysts then withoutCatalyst = withoutCatalyst + 1 end
        local score = row.futureOpportunityScore or -1
        if previousScore then
            expect(score <= previousScore, "Der Bericht sortiert nach Signal absteigend")
        end
        previousScore = score
    end
    expectEqual(withoutCatalyst, 0, "Ohne Catalyst steht nichts im Zukunft-Tab")
    expect(F:SummaryText(report):find("Catalyst") ~= nil,
        "Die Kopfzeile nennt, worum es geht")
    expect(F:SummaryText({ total = 0 }):find("keinen belastbaren") ~= nil,
        "Ohne Catalyst wird nichts behauptet")
    expect(rawequal(F:BuildReport(), report),
        "Ein zweiter Aufruf liefert den gecachten Bericht")
    Market:Touch()
    expect(not rawequal(F:BuildReport(), report),
        "Neue Marktdaten verwerfen den Cache")

end
futureSection()

futureSection = function()
    local K, F = GCP.Knowledge, GCP.Future
    local FUT = GCP.Constants.FUTURE
    local phase3 = K:GetPhase("phase3")

    -- --- Watchlist mit These -----------------------------------------------
    GCP.db.watchlist = {}
    expectEqual(F:Watch(22456, "Schattenwiderstand Phase 3"), true,
        "Ein Item laesst sich mit These beobachten")
    local watchEntry = Market:GetWatchEntry(22456)
    expectEqual(watchEntry.reason, "future", "Der Grund steht in den SavedVariables")
    expectEqual(watchEntry.phase, "phase3", "Die Phase steht dabei")
    expectEqual(watchEntry.thesis, "Schattenwiderstand Phase 3", "Die These steht dabei")
    expect(type(watchEntry.addedAt) == "number", "Der Zeitpunkt bleibt erhalten")
    expectEqual(Market:UpdateWatchMeta(22456, { notes = "gesammelt ab 15 g" }), true,
        "Notizen lassen sich nachtragen")
    expectEqual(Market:GetWatchEntry(22456).notes, "gesammelt ab 15 g", "...und stehen dann da")
    expectEqual(Market:UpdateWatchMeta(4242, { notes = "x" }), false,
        "Ein nicht beobachtetes Item bekommt keine Notiz")

    -- Ein Eintrag aus 0.6 hat die neuen Felder nicht - und funktioniert weiter.
    GCP.db.watchlist = { [23425] = { reason = "Chancen-Tab", addedAt = mockNow - 7200 } }
    Market:InvalidateTrackedCache()
    expectEqual(Market:IsWatched(23425), true, "Ein 0.6-Eintrag bleibt beobachtet")
    local legacyList = Market:GetWatchlist()
    expectEqual(#legacyList, 1, "...und steht in der Liste")
    expectEqual(legacyList[1].reason, "Chancen-Tab", "...mit seinem Grund")
    expectEqual(legacyList[1].phase, nil, "...und ohne erfundene Zusatzfelder")
    expectEqual(Market:RegisterWatchItem(23425, "Chancen-Tab",
        { phase = "phase3", thesis = "nachgetragen" }), false,
        "Ein bereits beobachtetes Item wird nicht doppelt aufgenommen")
    expectEqual(Market:GetWatchEntry(23425).thesis, "nachgetragen",
        "...bekommt die neuen Felder aber nachgetragen")
    expectEqual(Market:GetWatchEntry(23425).addedAt, mockNow - 7200,
        "...und behaelt seinen Aufnahmezeitpunkt")
    GCP.db.watchlist = {}
    Market:InvalidateTrackedCache()

end
futureSection()

futureSection = function()
    local K, F = GCP.Knowledge, GCP.Future
    local FUT = GCP.Constants.FUTURE
    local phase3 = K:GetPhase("phase3")

    -- --- Protokoll ---------------------------------------------------------
    GCP.db.opportunityHistory = {
        { timestamp = mockNow - 3600, type = "craft", itemID = 60001,
          marketPrice = 2000, expectedProfit = 5600, opportunityScore = 71,
          confidence = "high" },
    }
    local futureRecord = {
        itemID = 22456, futureOpportunityScore = 82, futureDemandScore = 81,
        hypeScore = 20, marketScore = 70, confidence = "high", phase = "phase3",
        daysUntilCatalyst = 18,
        demand = { hasCatalysts = true },
        catalysts = { { catalyst = { id = "p3-resist-primal-shadow" } } },
        stats = { current = 140000 },
    }
    expectEqual(F:ShouldLog(futureRecord, mockNow), true,
        "Ein belastbares Future-Signal wird protokolliert")
    expectEqual(F:LogReport({ rows = { futureRecord } }, mockNow), 1,
        "Der Eintrag landet im Protokoll")
    expectEqual(#GCP.db.opportunityHistory, 2,
        "Das Protokoll aus 0.6 bleibt daneben stehen")
    local futureEntry = GCP.db.opportunityHistory[2]
    expectEqual(futureEntry.type, "future", "Der Eintrag ist als Future-Signal erkennbar")
    expectEqual(futureEntry.itemID, 22456, "Er nennt das Item")
    expectEqual(futureEntry.futureDemandScore, 81, "Er haelt den Future Demand fest")
    expectEqual(futureEntry.hypeScore, 20, "Er haelt den Hype fest")
    expectEqual(futureEntry.futureOpportunityScore, 82, "Er haelt das Signal fest")
    expectEqual(futureEntry.marketScore, 70, "Er haelt den Market Score fest")
    expectEqual(futureEntry.marketPrice, 140000, "Er haelt den Preis fest")
    expectEqual(futureEntry.phase, "phase3", "Er haelt die Phase fest")
    expectEqual(futureEntry.daysUntilCatalyst, 18, "Er haelt die Tage bis dahin fest")
    expectEqual(futureEntry.catalystIDs[1], "p3-resist-primal-shadow",
        "Er haelt fest, welche Catalysts das Signal getragen haben")
    expectEqual(GCP.db.opportunityHistory[1].type, "craft",
        "Der alte Eintrag ist unveraendert lesbar")
    expectEqual(GCP.db.opportunityHistory[1].opportunityScore, 71,
        "...mit allen Werten")

    expectEqual(F:ShouldLog(futureRecord, mockNow + 60), false,
        "Dasselbe Signal kurz danach wird nicht erneut protokolliert")
    expectEqual(F:LogReport({ rows = { futureRecord } }, mockNow + 60), 0,
        "Ein zweiter Durchlauf schreibt nichts")
    expectEqual(F:ShouldLog(futureRecord, mockNow + FUT.HISTORY.MIN_INTERVAL), true,
        "Nach sechs Stunden wieder")
    local movedRecord = {}
    for key, value in pairs(futureRecord) do movedRecord[key] = value end
    movedRecord.futureOpportunityScore = 95
    expectEqual(F:ShouldLog(movedRecord, mockNow + 60), true,
        "Ein deutlich veraendertes Signal wird sofort protokolliert")
    local weakRecord = {}
    for key, value in pairs(futureRecord) do weakRecord[key] = value end
    weakRecord.futureOpportunityScore = FUT.HISTORY.MIN_SIGNAL - 1
    weakRecord.itemID = 22457
    expectEqual(F:ShouldLog(weakRecord, mockNow), false,
        "Ein schwaches Signal kommt gar nicht erst ins Protokoll")
    local noCatalystRecord = {}
    for key, value in pairs(futureRecord) do noCatalystRecord[key] = value end
    noCatalystRecord.itemID = 22451
    noCatalystRecord.demand = { hasCatalysts = false }
    expectEqual(F:ShouldLog(noCatalystRecord, mockNow), false,
        "Ohne Catalyst wird nichts protokolliert")
    -- Der Weg ueber Opportunity bleibt vom Future-Protokoll unberuehrt.
    expectEqual(GCP.Opportunity:LastLogged("craft", 60001).opportunityScore, 71,
        "Die Chancen-Suche findet weiterhin ihre eigenen Eintraege")
    GCP.db.opportunityHistory = {}

end
futureSection()

futureSection = function()
    local K, F = GCP.Knowledge, GCP.Future
    local FUT = GCP.Constants.FUTURE
    local phase3 = K:GetPhase("phase3")

    -- --- Anmeldung bei der Market Engine -----------------------------------
    Market:InvalidateTrackedCache()
    local trackedFuture = {}
    for _, itemID in ipairs(Market:GetTrackedItems()) do trackedFuture[itemID] = true end
    expectEqual(trackedFuture[32428], true,
        "Items der Wissensbasis werden beobachtet, bevor die Phase da ist")
    expectEqual(Market:GetTrackReason(32428), "Zukunft",
        "...und nennen die Wissensbasis als Grund")

    -- --- 0.8 bleibt vorbereitet -------------------------------------------
    local prepared = F:GetItemRecord(22456)
    expectEqual(prepared.liquidity, nil, "Liquiditaet bleibt in 0.7 leer")
    expectEqual(prepared.sellThrough, nil, "Sell-Through bleibt leer")
    expectEqual(prepared.expectedHours, nil, "Verkaufsdauer bleibt leer")
    expectEqual(prepared.profitVelocity, nil, "Profit-Velocity bleibt leer")
    expectEqual(prepared.liquidityScore, nil, "Liquiditaets-Score bleibt leer")

    -- Aufraeumen: die Testreihen sollen den folgenden Abschnitten nicht in die
    -- Quere kommen.
    for _, itemID in ipairs({ 990301, 990302, 990303, 990304, 990401 }) do
        marketPrices[itemID] = nil
        GCP.db.marketHistory.items[itemID] = nil
    end
    Market:InvalidateCaches()
    F:Invalidate()
    mockNow = os.time({ year = 2026, month = 9, day = 1, hour = 8, min = 0, sec = 0 })
end
futureSection()

-- ---------------------------------------------------------------------------
-- Ledger / Liquidity Brain (0.8.0)
--
-- Geprueft wird in dieser Reihenfolge: die fuenf Ereignisarten und was sie
-- ablehnen, die stueckzahlbasierte Sell-Through-Rate, die Zuordnung
-- Einstellung -> Verkauf, die persoenlichen Preise, der realisierte Gewinn,
-- die beiden Formeln (Liquidity Score und Profit Velocity), das Aufraeumen,
-- der Briefkasten und zuletzt, was Opportunity, Future und das Chancen-
-- Protokoll daraus machen.
-- ---------------------------------------------------------------------------

local function expectClose(actual, wanted, tolerance, label)
    expect(type(actual) == "number" and math.abs(actual - wanted) <= tolerance,
        string.format("%s (erwartet ~%s, erhalten %s)", label, tostring(wanted),
            tostring(actual)))
end

local function ledgerSection()
    local Ledger = GCP.Ledger
    local Opportunity = GCP.Opportunity
    local Future = GCP.Future
    local L = GCP.Constants.LEDGER

    local function resetLedger()
        GCP.db.ledger = nil
        Ledger.relistChains = {}
        Ledger.itemCache = {}
        Ledger.globalCache = {}
        Ledger:Touch()
        Ledger:EnsureStore()
    end
    resetLedger()

    local base = mockNow - 10 * 86400

    -- --- Die fuenf Ereignisarten -------------------------------------------
    expectEqual(Ledger:RecordPurchase({
        itemID = 23425, quantity = 20, unitPrice = 40000, timestamp = base }), true,
        "Ein Kauf wird aufgeschrieben")
    local ore = Ledger:GetItemStats(23425)
    expectEqual(ore.boughtQuantity, 20, "Der Kauf zaehlt seine Stueckzahl")
    expectEqual(ore.purchases, 1, "...und sich selbst als einen Vorgang")
    expectEqual(ore.purchaseCost, 800000, "Kosten = Stueckpreis mal Stueckzahl")
    expectEqual(ore.averageBuyPrice, 40000, "Der gewichtete Einkaufspreis stimmt")

    expectEqual(Ledger:RecordPurchase({
        itemID = 23425, totalCost = 210000, quantity = 5, timestamp = base + 60 }), true,
        "Ein Kauf laesst sich auch ueber die Gesamtsumme aufschreiben")
    expectEqual(Ledger:GetItemStats(23425).averageBuyPrice,
        math.floor((800000 + 210000) / 25 + 0.5),
        "Der Durchschnitt wird nach Stueckzahl gewichtet, nicht je Vorgang")

    -- Ungueltiges wird abgelehnt statt gerettet.
    expectEqual(Ledger:RecordPurchase(nil), false, "Kein Kauf ohne Daten")
    expectEqual(Ledger:RecordPurchase({ itemID = 23425, quantity = 0, unitPrice = 100 }), false,
        "Kein Kauf ohne Stueckzahl")
    expectEqual(Ledger:RecordPurchase({ itemID = -3, quantity = 1, unitPrice = 100 }), false,
        "Kein Kauf mit unmoeglicher Item-ID")
    expectEqual(Ledger:RecordPurchase({ itemID = 23425, quantity = 3 }), false,
        "Kein Kauf ohne Preis")
    expectEqual(Ledger:RecordAuctionPosted({ itemID = 23425, quantity = 10 }), false,
        "Keine Einstellung ohne Preis")
    expectEqual(Ledger:RecordSale({ itemID = 23425 }), false,
        "Kein Verkauf ohne Betrag")
    expectEqual(Ledger:RecordAuctionExpired({ itemID = 23425 }), false,
        "Kein Ablauf ohne Stueckzahl")
    expectEqual(Ledger:RecordAuctionCancelled({ quantity = 5 }), false,
        "Kein Abbruch ohne Item")

    -- --- Sell-Through ist stueckzahlbasiert, nicht ereignisbasiert ---------
    -- 60 + 40 Stueck eingestellt, der 60er-Stapel verkauft, der 40er laeuft ab.
    -- Ereignisbezogen waere das 1 zu 1, also 50 %. Richtig sind 60 %.
    Ledger:RecordAuctionPosted({ itemID = 22785, quantity = 60, unitPrice = 1000,
        deposit = 900, durationHours = 24, timestamp = base })
    Ledger:RecordAuctionPosted({ itemID = 22785, quantity = 40, unitPrice = 1000,
        deposit = 600, durationHours = 24, timestamp = base })
    Ledger:ApplySaleInvoice({ itemName = "Teufelsgras", total = 60000,
        consignment = 3000, arrivedAt = base + 4 * 3600 })
    Ledger:RecordAuctionExpired({ itemID = 22785, quantity = 40, timestamp = base + 48 * 3600 })

    local herb = Ledger:GetItemStats(22785)
    expectEqual(herb.soldQuantity, 60, "Verkaufte Stueckzahl kommt aus der Zuordnung")
    expectEqual(herb.expiredQuantity, 40, "Abgelaufene Stueckzahl steht daneben")
    expectClose(herb.sellThrough, 0.6, 0.0001, "Sell-Through ist stueckzahlbasiert (60 %)")
    expectClose(herb.sellThroughAuctions, 0.5, 0.0001,
        "Die ereignisbezogene Rate steht daneben und ist eine andere Zahl (50 %)")
    expectEqual(herb.postedQuantity, 100, "Eingestellt waren 100 Stueck")
    expectEqual(herb.postedAuctions, 2, "...in zwei Auktionen")

    -- Ein Abbruch ist kein Fehlschlag.
    Ledger:RecordAuctionPosted({ itemID = 22785, quantity = 25, unitPrice = 1000,
        deposit = 400, timestamp = base + 60 * 3600 })
    Ledger:RecordAuctionCancelled({ itemID = 22785, quantity = 25, timestamp = base + 61 * 3600 })
    herb = Ledger:GetItemStats(22785)
    expectEqual(herb.cancelledQuantity, 25, "Der Abbruch wird festgehalten")
    expectClose(herb.sellThrough, 0.6, 0.0001,
        "...veraendert die Sell-Through-Rate aber nicht")
    expectEqual(herb.depositLost, 400 + 600,
        "Verlorene Einstellgebuehren aus Ablauf und Abbruch zaehlen beide")

    -- Wenig Daten heisst niedrige Confidence - und der Deckel greift.
    expectEqual(herb.confidence, "low", "Zwei aufgeloeste Auktionen sind duenn")
    expectEqual(herb.liquidityScore, 55,
        "Der Confidence-Deckel begrenzt den Liquidity Score bei duenner Datenlage")

    -- --- Zuordnung Einstellung -> Verkauf und Verkaufsdauer ----------------
    Ledger:RecordAuctionPosted({ itemID = 21884, quantity = 10, unitPrice = 1300,
        timestamp = base })
    Ledger:RecordAuctionPosted({ itemID = 21884, quantity = 5, unitPrice = 2000,
        timestamp = base + 3600 })
    -- 10.000 = 2.000 x 5: passt genau auf die zweite Einstellung.
    Ledger:ApplySaleInvoice({ itemName = "Urfeuer", total = 10000, consignment = 500,
        arrivedAt = base + 3 * 3600 })
    local fire = Ledger:GetItemStats(21884)
    expectEqual(fire.soldQuantity, 5, "Der exakte Treffer liefert die Stueckzahl")
    expectClose(fire.medianHours, 2, 0.01, "Verkaufsdauer: zwei Stunden nach dem Einstellen")

    -- Betrag passt auf keine Einstellung, aber es ist nur noch eine offen.
    Ledger:ApplySaleInvoice({ itemName = "Urfeuer", total = 9000, consignment = 450,
        arrivedAt = base + 10 * 3600 })
    fire = Ledger:GetItemStats(21884)
    expectEqual(fire.soldQuantity, 15, "Die eindeutige Zuordnung liefert die zweite Stueckzahl")
    expectClose(fire.medianHours, 6, 0.01, "Median aus zwei Verkaufsdauern (2 h und 10 h)")
    expectClose(fire.p25Hours, 4, 0.01, "Das untere Quartil steht daneben")
    expectEqual(fire.timeSamples, 2, "Zwei Stichproben stehen hinter dem Median")
    expectEqual(Ledger:CountOpenPostings(21884), 0,
        "Zugeordnete Einstellungen sind danach nicht mehr offen")

    -- Die AH-Gebuehr wird genau einmal abgezogen: aus der Rechnung, nicht noch
    -- einmal ueber NetAuction.
    expectEqual(fire.revenueGross, 19000, "Bruttoerloes ist die Summe der Rechnungen")
    expectEqual(fire.revenueNet, 19000 - 950,
        "Nettoerloes zieht genau die Gebuehr der Rechnung ab, kein zweites Mal")

    -- Verkauf ohne jede Zuordnung: der Umsatz zaehlt, die Stueckzahl bleibt
    -- unbekannt - und damit gibt es keine stueckzahlbasierte Rate mehr.
    Ledger:ApplySaleInvoice({ itemName = "Urfeuer", total = 5000, consignment = 250,
        arrivedAt = base + 20 * 3600 })
    fire = Ledger:GetItemStats(21884)
    expectEqual(fire.unmatchedSales, 1, "Der nicht zuordenbare Verkauf wird als solcher gezaehlt")
    expectEqual(fire.soldAuctions, 3, "Er zaehlt trotzdem als verkaufte Auktion")
    expectEqual(fire.soldQuantity, 15, "...aber nicht in die Stueckzahl")
    expectEqual(fire.sellThrough, nil,
        "Ohne vollstaendige Zuordnung gibt es keine stueckzahlbasierte Rate, sondern nil")
    expectEqual(fire.confidence, "none", "...und keine Datenlage, auf die man sich beruft")
    expectEqual(fire.liquidityScore, nil, "...und damit auch keinen Liquidity Score")
    expectEqual(fire.revenueNet, 19000 - 950 + 5000 - 250,
        "Der Umsatz zaehlt trotzdem vollstaendig")

    -- Ein Verkauf ohne aufloesbaren Namen landet nur in der Gesamtsumme.
    local beforeGlobal = Ledger:GetGlobalStats(nil).revenueNet
    Ledger:ApplySaleInvoice({ itemName = "Etwas nie Gehandeltes", total = 4000,
        consignment = 200, arrivedAt = base + 21 * 3600 })
    expectEqual(Ledger:GetGlobalStats(nil).revenueNet, beforeGlobal + 3800,
        "Ein Verkauf ohne bekannte Item-ID zaehlt in die Gesamtsumme")

    -- Fehlt die Gebuehr in der Rechnung, gilt der AH-Satz aus Constants -
    -- dieselbe Zahl wie ueberall sonst, keine erfundene Pauschale.
    Ledger:RecordAuctionPosted({ itemID = 22456, quantity = 1, unitPrice = 20000,
        timestamp = base })
    Ledger:ApplySaleInvoice({ itemName = "Urschatten", total = 20000, arrivedAt = base + 3600 })
    expectEqual(Ledger:GetItemStats(22456).revenueNet, GCP.Prices:NetAuction(20000),
        "Ohne Gebuehr in der Rechnung gilt der bekannte AH-Satz")

    -- --- Persoenliche Preise, nach Stueckzahl gewichtet --------------------
    Ledger:RecordPurchase({ itemID = 21877, quantity = 100, unitPrice = 50, timestamp = base })
    Ledger:RecordPurchase({ itemID = 21877, quantity = 10, unitPrice = 150,
        timestamp = base + 3600 })
    local cloth = Ledger:GetItemStats(21877)
    expectEqual(cloth.averageBuyPrice, math.floor(6500 / 110 + 0.5),
        "Gewichteter Einkaufsdurchschnitt (59), nicht der Mittelwert der Preise (100)")
    expectEqual(cloth.medianBuyPrice, 50,
        "Der gewichtete Median folgt der Stueckzahl, nicht der Zahl der Vorgaenge")

    Ledger:RecordAuctionPosted({ itemID = 21877, quantity = 100, unitPrice = 80,
        deposit = 200, timestamp = base + 2 * 3600 })
    Ledger:ApplySaleInvoice({ itemName = "Netherstoff", total = 8000, consignment = 400,
        arrivedAt = base + 5 * 3600 })
    cloth = Ledger:GetItemStats(21877)
    expectEqual(cloth.medianSellPrice, 76, "Median-Verkaufspreis netto je Stueck")
    expectEqual(cloth.averageSellPrice, 76, "Gewichteter Verkaufsdurchschnitt daneben")
    expectClose(cloth.realizedMargin, (76 - 50) / 50, 0.0001,
        "Realisierte Marge aus den beiden Medianen")

    -- --- Realisierter Gewinn -----------------------------------------------
    expectEqual(cloth.costBasisKnown, true,
        "110 gekaufte gegen 100 verkaufte Stueck: die Kostenbasis traegt")
    expectEqual(cloth.realizedProfit, 7600 - 59 * 100,
        "Realisierter Gewinn = Nettoerloes minus gewichteter Einkauf")

    Ledger:RecordAuctionPosted({ itemID = 21877, quantity = 10, unitPrice = 80,
        deposit = 30, timestamp = base + 6 * 3600 })
    Ledger:RecordAuctionExpired({ itemID = 21877, quantity = 10, timestamp = base + 54 * 3600 })
    cloth = Ledger:GetItemStats(21877)
    expectEqual(cloth.depositLost, 30, "Die verlorene Einstellgebuehr wird erfasst")
    expectEqual(cloth.realizedProfit, 7600 - 59 * 100 - 30,
        "...und vom realisierten Gewinn abgezogen")

    -- Selbst gefarmte Ware bekommt ausdruecklich keine Kostenbasis 0.
    Ledger:RecordAuctionPosted({ itemID = 22574, quantity = 20, unitPrice = 100,
        timestamp = base })
    Ledger:ApplySaleInvoice({ itemName = "Feuerpartikel", total = 2000, consignment = 100,
        arrivedAt = base + 2 * 3600 })
    local mote = Ledger:GetItemStats(22574)
    expectEqual(mote.costBasisKnown, false, "Ohne Einkauf gibt es keine belegte Kostenbasis")
    expectEqual(mote.realizedProfit, nil,
        "...und deshalb keinen realisierten Gewinn statt eines geschenkten")
    expectEqual(mote.costBasisCoverage, 0, "Die Deckung der Kostenbasis wird ausgewiesen")

    -- --- Liquidity Score ----------------------------------------------------
    expectEqual(Ledger:ComputeLiquidityScore({ sellThrough = 0.87, medianHours = 4.2,
        salesPerWeek = 8, confidence = "high" }), 90,
        "Hohe Rate und schnelle Verkaeufe ergeben einen hohen Score")
    expectEqual(Ledger:ComputeLiquidityScore({ sellThrough = 0.87, medianHours = 96,
        salesPerWeek = 8, confidence = "high" }), 70,
        "Dieselbe Rate mit langsamen Verkaeufen faellt deutlich ab")
    expectEqual(Ledger:ComputeLiquidityScore({ sellThrough = 0.2, medianHours = 4.2,
        salesPerWeek = 8, confidence = "high" }), 49,
        "Eine niedrige Rate zieht den Score nach unten, auch wenn es schnell geht")
    expectEqual(Ledger:ComputeLiquidityScore({ sellThrough = 0.87, medianHours = 4.2,
        salesPerWeek = 8, confidence = "low" }), 55,
        "Wenig Stichproben deckeln den Score hart")
    expectEqual(Ledger:ComputeLiquidityScore({ sellThrough = nil, medianHours = 4.2,
        confidence = "high" }), nil,
        "Ohne Sell-Through-Rate gibt es gar keinen Score, nicht 50")
    expectEqual(Ledger:ComputeLiquidityScore({}), nil, "Ohne Daten gibt es keinen Score")
    -- Eine fehlende Verkaufsdauer wird herausgerechnet, nicht mit 0 bestraft.
    expectEqual(Ledger:ComputeLiquidityScore({ sellThrough = 0.9, salesPerWeek = 8,
        confidence = "high" }), 94,
        "Eine unbekannte Verkaufsdauer wird herausgerechnet statt als 0 gewertet")
    expectEqual(Ledger:ScoreBand(90), "sehr liquide", "Der Score bekommt eine Einordnung")

    -- --- Profit Velocity ----------------------------------------------------
    local velocity, velocityParts = Ledger:ProfitVelocity({
        expectedProfit = 190000, capital = 650000, sellThrough = 0.88, holdingHours = 5.4 })
    expectClose(velocity, (190000 * 0.88) / 650000 / (5.4 / 24), 0.0001,
        "Profit Velocity folgt exakt der dokumentierten Formel")
    expectClose(velocityParts.perReferenceCapital, velocity * 1000000, 1,
        "Die verstaendliche Zahl ist Gewinn je 100 g Kapital und Tag")

    local slow = Ledger:ProfitVelocity({ expectedProfit = 500000, capital = 1000000,
        sellThrough = 1, holdingHours = 240 })
    local quick = Ledger:ProfitVelocity({ expectedProfit = 30000, capital = 1000000,
        sellThrough = 1, holdingHours = 6 })
    expect(quick > slow,
        "3 % ROI mit sechs Stunden Umschlag schlaegt 50 % ROI mit zehn Tagen Liegezeit")

    local fast, fastParts = Ledger:ProfitVelocity({ expectedProfit = 10000,
        capital = 100000, sellThrough = 1, holdingHours = 0.1 })
    expectEqual(fastParts.clamped, true, "Eine winzige Haltedauer wird angehoben")
    expectClose(fast, 10000 / 100000 / (L.VELOCITY.MIN_HOLDING_HOURS / 24), 0.0001,
        "...und die Mindestdauer verhindert die Divisionsexplosion")
    expectEqual(Ledger:ProfitVelocity({ expectedProfit = 1000, capital = 1000,
        holdingHours = 5 }), nil, "Ohne Sell-Through-Rate gibt es keine Velocity")
    expectEqual(Ledger:ProfitVelocity({ expectedProfit = 1000, capital = 1000,
        sellThrough = 0.8 }), nil, "Ohne gemessene Haltedauer ebenfalls nicht")

    -- --- Retention, Deckel, Aufraeumen -------------------------------------
    local before = Ledger:GetOverview().events
    Ledger:AppendEvent(1, base - 80 * 86400, 23425, 1, 100, 0, 0)
    expectEqual(Ledger:GetOverview().events, before + 1, "Ein altes Ereignis laesst sich anlegen")
    Ledger:Prune(mockNow, true)
    expectEqual(Ledger:GetOverview().events, before,
        "Das Aufraeumen entfernt Ereignisse jenseits der Aufbewahrungsfrist")
    expectEqual(Ledger:GetItemStats(21877).realizedProfit, 7600 - 59 * 100 - 30,
        "Die Aggregate je Item ueberleben das Aufraeumen - sie sind das Langzeitgedaechtnis")

    local savedMax = L.MAX_EVENTS
    L.MAX_EVENTS = 12
    for index = 1, 20 do
        Ledger:AppendEvent(1, base + index * 60, 23425, 1, 100, 0, 0)
    end
    expectEqual(Ledger:GetOverview().events, 12, "Der harte Deckel begrenzt die Ereignisliste")
    L.MAX_EVENTS = savedMax

    local savedSamples = L.MAX_SAMPLES
    L.MAX_SAMPLES = 3
    for index = 1, 6 do
        Ledger:RecordPurchase({ itemID = 60002, quantity = 1, unitPrice = 100 * index,
            timestamp = base + index * 60 })
    end
    expectEqual(#GCP.db.ledger.items[60002].b, 6, "Auch die Stichproben je Item sind gedeckelt")
    L.MAX_SAMPLES = savedSamples

    local savedItems = L.MAX_ITEMS
    L.MAX_ITEMS = 2
    Ledger:Prune(mockNow, true)
    local itemCount = 0
    for _ in pairs(GCP.db.ledger.items) do itemCount = itemCount + 1 end
    expectEqual(itemCount, 2, "Der Deckel begrenzt auch die Zahl gespeicherter Items")
    L.MAX_ITEMS = savedItems

    -- Offene Einstellungen, die niemand mehr zuordnen kann, verschwinden.
    resetLedger()
    Ledger:RecordAuctionPosted({ itemID = 23425, quantity = 5, unitPrice = 50000,
        timestamp = mockNow - 40 * 86400 })
    Ledger:RecordAuctionPosted({ itemID = 23425, quantity = 5, unitPrice = 50000,
        timestamp = mockNow - 3600 })
    expectEqual(Ledger:CountOpenPostings(23425), 2, "Beide Einstellungen sind zunaechst offen")
    Ledger:Prune(mockNow, true)
    expectEqual(Ledger:CountOpenPostings(23425), 1,
        "Eine 40 Tage alte offene Einstellung ist nicht mehr zuzuordnen und faellt weg")

    -- --- Relisting ----------------------------------------------------------
    resetLedger()
    Ledger:RecordAuctionPosted({ itemID = 22785, quantity = 10, unitPrice = 1000,
        timestamp = base })
    Ledger:RecordAuctionExpired({ itemID = 22785, quantity = 10, timestamp = base + 24 * 3600 })
    Ledger:RecordAuctionPosted({ itemID = 22785, quantity = 10, unitPrice = 1000,
        timestamp = base + 25 * 3600 })
    Ledger:ApplySaleInvoice({ itemName = "Teufelsgras", total = 10000, consignment = 500,
        arrivedAt = base + 29 * 3600 })
    local relisted = Ledger:GetItemStats(22785)
    expectClose(relisted.medianHours, 4, 0.01,
        "Die Verkaufsdauer misst die letzte Einstellung - exakt und ohne Annahme")
    expectClose(relisted.medianHoldHours, 29, 0.01,
        "Die Haltedauer der ganzen Position laeuft ueber die Neu-Einstellung hinweg")
    expectClose(relisted.sellThrough, 0.5, 0.0001,
        "Der Fehlschlag vor der Neu-Einstellung bleibt in der Sell-Through-Rate stehen")

    -- --- Briefkasten --------------------------------------------------------
    resetLedger()
    AUCTION_EXPIRED_MAIL_SUBJECT = "Auktion abgelaufen: %s"
    AUCTION_REMOVED_MAIL_SUBJECT = "Auktion abgebrochen: %s"

    local inbox = {}
    function GetInboxNumItems() return #inbox, #inbox end
    function GetInboxHeaderInfo(index)
        local mail = inbox[index]
        if not mail then return nil end
        return nil, nil, mail.sender or "Auktionshaus", mail.subject,
            mail.money or 0, 0, mail.daysLeft or 30
    end
    function GetInboxInvoiceInfo(index)
        local mail = inbox[index]
        local invoice = mail and mail.invoice
        if not invoice then return nil end
        return invoice.kind, invoice.itemName, invoice.player, invoice.bid,
            invoice.buyout, invoice.deposit, invoice.consignment
    end
    function GetInboxItemLink(index)
        local mail = inbox[index]
        return mail and mail.itemID and ("item:" .. mail.itemID) or nil
    end
    function GetInboxItem(index)
        local mail = inbox[index]
        if not mail or not mail.itemID then return nil end
        return mail.itemName, mail.itemID, nil, mail.count, 1, true
    end

    -- Die Einstellung muss vor der Rechnung da sein, sonst gibt es nichts
    -- zuzuordnen - genau wie im Spiel.
    Ledger:RecordAuctionPosted({ itemID = 23425, quantity = 4, unitPrice = 50000,
        deposit = 300, timestamp = mockNow - 6 * 3600 })
    inbox = {
        { subject = "Auktion erfolgreich: Adamantiterz", daysLeft = 30 - 2 / 24,
          invoice = { kind = "seller", itemName = "Adamantiterz", bid = 200000,
                      buyout = 200000, deposit = 300, consignment = 10000 } },
        { subject = "Auktion gewonnen: Teufelsgras", daysLeft = 30 - 1 / 24,
          itemID = 22785, itemName = "Teufelsgras", count = 20,
          invoice = { kind = "buyer", itemName = "Teufelsgras", bid = 16000 } },
        { subject = "Auktion abgelaufen: Urfeuer", daysLeft = 30 - 3 / 24,
          itemID = 21884, itemName = "Urfeuer", count = 7 },
        { subject = "Auktion abgebrochen: Urwasser", daysLeft = 30 - 4 / 24,
          itemID = 21885, itemName = "Urwasser", count = 3 },
        -- Post von einem Mitspieler mit Gold dran. Sie darf niemals ein
        -- Verkauf werden - Handel, Post und Haendler sind kein Auktionsverkauf.
        { subject = "Danke fuer die Mats!", sender = "Kumpel", money = 500000,
          itemID = 22574, itemName = "Feuerpartikel", count = 5, daysLeft = 29 },
    }
    local written = Ledger:ScanMailbox(mockNow)
    expectEqual(written, 4, "Der Briefkasten liefert genau die vier AH-Vorgaenge")

    local scanned = Ledger:GetItemStats(23425)
    expectEqual(scanned.soldAuctions, 1, "Die Verkaufsrechnung wird als Verkauf erkannt")
    expectEqual(scanned.soldQuantity, 4,
        "Die Stueckzahl kommt aus der zugeordneten Einstellung, nicht aus der Rechnung")
    expectEqual(scanned.revenueNet, 190000,
        "Netto = Gebot minus der Gebuehr aus der Rechnung")
    expectClose(scanned.medianHours, 4, 0.05,
        "Die Verkaufsdauer entsteht aus Einstellzeit und Ankunft der Post")

    expectEqual(Ledger:GetItemStats(22785).boughtQuantity, 20,
        "Die Kaufrechnung liefert Item und Stueckzahl aus dem Anhang")
    expectEqual(Ledger:GetItemStats(22785).purchaseCost, 16000, "...und den bezahlten Betrag")
    expectEqual(Ledger:GetItemStats(21884).expiredQuantity, 7,
        "Die Ablauf-Post wird ueber ihren Betreff erkannt")
    expectEqual(Ledger:GetItemStats(21885).cancelledQuantity, 3,
        "Die Abbruch-Post ebenso - und getrennt vom Ablauf")
    expectEqual(Ledger:GetItemStats(22574), nil,
        "Post von einem Mitspieler erzeugt keinen einzigen Handelsvorgang")

    expectEqual(Ledger:ScanMailbox(mockNow), 0,
        "Ein zweiter Durchlauf ueber denselben Briefkasten schreibt nichts noch einmal")
    expectEqual(Ledger:ScanMailbox(mockNow + 600), 0,
        "...auch nicht kurze Zeit spaeter mit gewanderten Restlaufzeiten")

    -- Drei gleiche Verkaufsbriefe sind drei Verkaeufe.
    Ledger:RecordAuctionPosted({ itemID = 22456, quantity = 2, unitPrice = 10000,
        timestamp = mockNow - 2 * 3600 })
    Ledger:RecordAuctionPosted({ itemID = 22456, quantity = 2, unitPrice = 10000,
        timestamp = mockNow - 2 * 3600 })
    inbox = {
        { subject = "Auktion erfolgreich: Urschatten", daysLeft = 30 - 1 / 24,
          invoice = { kind = "seller", itemName = "Urschatten", bid = 20000,
                      consignment = 1000 } },
        { subject = "Auktion erfolgreich: Urschatten", daysLeft = 30 - 1 / 24,
          invoice = { kind = "seller", itemName = "Urschatten", bid = 20000,
                      consignment = 1000 } },
    }
    expectEqual(Ledger:ScanMailbox(mockNow), 2, "Zwei gleiche Briefe sind zwei Verkaeufe")
    expectEqual(Ledger:GetItemStats(22456).soldAuctions, 2, "...und werden auch so gezaehlt")
    expectEqual(Ledger:ScanMailbox(mockNow), 0, "Beim naechsten Blick sind sie nicht neu")

    -- Abgeholt, und Stunden spaeter kommt derselbe Verkauf noch einmal.
    inbox = {}
    Ledger:ScanMailbox(mockNow)
    Ledger:RecordAuctionPosted({ itemID = 22456, quantity = 2, unitPrice = 10000,
        timestamp = mockNow + 5 * 3600 })
    inbox = {
        { subject = "Auktion erfolgreich: Urschatten", daysLeft = 30 - 1 / 24,
          invoice = { kind = "seller", itemName = "Urschatten", bid = 20000,
                      consignment = 1000 } },
    }
    expectEqual(Ledger:ScanMailbox(mockNow + 7 * 3600), 1,
        "Ein spaeter eingetroffener gleicher Verkauf wird wieder als neu erkannt")

    -- Die Zwischenrechnung vor der Auszahlung ist derselbe Brief, kein zweiter.
    inbox = {}
    Ledger:ScanMailbox(mockNow + 8 * 3600)
    Ledger:RecordAuctionPosted({ itemID = 22457, quantity = 1, unitPrice = 30000,
        timestamp = mockNow + 8 * 3600 })
    inbox = {
        { subject = "Auktion erfolgreich: Urmana", daysLeft = 30 - 1 / 24,
          invoice = { kind = "seller_temp_invoice", itemName = "Urmana", bid = 30000,
                      consignment = 1500 } },
    }
    expectEqual(Ledger:ScanMailbox(mockNow + 9 * 3600), 1,
        "Die vorlaeufige Rechnung zaehlt bereits als Verkauf")
    inbox[1].invoice.kind = "seller"
    expectEqual(Ledger:ScanMailbox(mockNow + 9 * 3600), 0,
        "Nach der Auszahlung wird derselbe Verkauf nicht ein zweites Mal gezaehlt")

    -- --- Gesamtstatistik ----------------------------------------------------
    local week = Ledger:GetGlobalStats(7)
    expect(week.sales > 0, "Die Sieben-Tage-Statistik kennt Verkaeufe")
    expect(week.revenueNet > 0, "...und einen Nettoumsatz")
    expectEqual(Ledger:GetGlobalStats(7), week, "Die Gesamtstatistik wird gecacht")
    expect(#Ledger:GetRecentTrades(5) <= 5, "Die letzten Geschaefte sind begrenzt abrufbar")

    -- Die mediane Verkaufszeit eines Zeitfensters gehoert diesem Zeitfenster.
    -- Ein schneller Verkauf von heute darf den 30-Tage-Median nicht ersetzen,
    -- und ein langsamer von vorletzter Woche nicht den der letzten sieben Tage.
    resetLedger()
    Ledger:RecordAuctionPosted({ itemID = 22785, quantity = 5, unitPrice = 1000,
        timestamp = mockNow - 20 * 86400 })
    Ledger:ApplySaleInvoice({ itemName = "Teufelsgras", total = 5000, consignment = 250,
        arrivedAt = mockNow - 20 * 86400 + 40 * 3600 })
    Ledger:RecordAuctionPosted({ itemID = 22785, quantity = 5, unitPrice = 1000,
        timestamp = mockNow - 2 * 86400 })
    Ledger:ApplySaleInvoice({ itemName = "Teufelsgras", total = 5000, consignment = 250,
        arrivedAt = mockNow - 2 * 86400 + 2 * 3600 })
    expectClose(Ledger:GetGlobalStats(7).medianHours, 2, 0.01,
        "Die Sieben-Tage-Ansicht rechnet nur mit Verkaeufen aus sieben Tagen")
    expectClose(Ledger:GetGlobalStats(30).medianHours, 21, 0.01,
        "Die 30-Tage-Ansicht nimmt beide - Median aus 2 h und 40 h")
    expectClose(Ledger:GetItemStats(22785).medianHours, 21, 0.01,
        "Die Item-Statistik selbst kennt weiterhin alle Stichproben")

    -- --- Opportunity Score --------------------------------------------------
    local scoreInput = { roi = 0.3, profit = 200000, cost = 650000,
        marketScore = 70, volatility = 0.1, confidence = "high" }
    local function scoreWith(liquidityScore, liquidityConfidence)
        local input = {}
        for key, value in pairs(scoreInput) do input[key] = value end
        input.liquidityScore = liquidityScore
        input.liquidityConfidence = liquidityConfidence
        return Opportunity:ScoreOf(input)
    end
    local plain = scoreWith(nil, nil)
    expectEqual(plain, 66, "Ohne Liquiditaetsdaten rechnet der Score exakt wie in 0.6")
    expectEqual(scoreWith(95, "none"), plain,
        "Ein Score ohne Datenlage veraendert nichts")
    expectEqual(scoreWith(95, "high"), 78, "Gute Liquiditaet verbessert die Bewertung")
    expectEqual(scoreWith(10, "high"), 52, "Schlechte Liquiditaet senkt sie")
    local thin = scoreWith(10, "low")
    expect(math.abs(thin - plain) <= 4,
        "Zwei Auktionen verschieben den Score um hoechstens ein paar Punkte")
    expect(thin < plain, "...ziehen ihn aber in die richtige Richtung")

    -- Fuer die Integrationspruefung zaehlt nicht, WELCHE Chance die Attrappe
    -- gerade hergibt, sondern dass genau die Chance mit eigenen Verkaufsdaten
    -- sie auch traegt. Deshalb wird die erste Chance der Liste genommen und ihr
    -- Item mit Handelsdaten versehen.
    local savedMinProfit = GCP.db.options.opportunityMinProfit
    local savedMinROI = GCP.db.options.opportunityMinROI
    GCP.db.options.opportunityMinProfit = 0
    GCP.db.options.opportunityMinROI = 0

    resetLedger()
    Opportunity:Invalidate()
    local coldReport = Opportunity:BuildReport(true)
    expect(#coldReport.opportunities >= 2,
        "Die Attrappe liefert mehrere Chancen zum Vergleichen")
    expectEqual(coldReport.withLiquidity, 0,
        "Ohne Handelsbilanz hat keine einzige Chance eine Liquiditaetsaussage")
    local target = coldReport.opportunities[1]
    local targetID, targetName = target.itemID, GetItemInfo(target.itemID)
    local coldScore = target.opportunityScore
    expectEqual(target.sellThrough, nil, "Ohne Daten bleibt sellThrough nil")
    expectEqual(target.expectedHours, nil, "...ebenso die erwartete Verkaufsdauer")
    expectEqual(target.liquidityScore, nil, "...der Liquidity Score")
    expectEqual(target.profitVelocity, nil, "...und die Profit Velocity")

    -- Eine belastbare, gute Verkaufsgeschichte fuer genau dieses Item.
    for index = 1, 12 do
        Ledger:RecordAuctionPosted({ itemID = targetID, quantity = 3, unitPrice = 90000,
            timestamp = base + index * 7200 })
        Ledger:ApplySaleInvoice({ itemName = targetName, total = 270000, consignment = 13500,
            arrivedAt = base + index * 7200 + 4 * 3600 })
    end
    Ledger:RecordAuctionPosted({ itemID = targetID, quantity = 3, unitPrice = 90000,
        timestamp = base + 100 * 3600 })
    Ledger:RecordAuctionExpired({ itemID = targetID, quantity = 3, timestamp = base + 148 * 3600 })

    local targetStats = Ledger:GetItemStats(targetID)
    expectClose(targetStats.sellThrough, 36 / 39, 0.0001, "Zwoelf Verkaeufe gegen einen Ablauf")
    expectEqual(targetStats.confidence, "medium",
        "13 Auktionen und 39 Stueck sind mittlere Datenlage")
    expect(targetStats.liquidityScore ~= nil, "Damit gibt es einen Liquidity Score")

    Opportunity:Invalidate()
    local report = Opportunity:BuildReport(true)
    local warm, untouched = nil, nil
    for _, opportunity in ipairs(report.opportunities) do
        if opportunity.itemID == targetID and opportunity.key == target.key then
            warm = opportunity
        elseif opportunity.liquidity == nil then
            untouched = opportunity
        end
    end
    expect(warm ~= nil, "Die Chance mit Handelsdaten steht weiterhin in der Liste")
    if warm then
        expectClose(warm.sellThrough, 36 / 39, 0.0001,
            "Das vorbereitete Feld sellThrough ist jetzt gefuellt")
        expect(warm.expectedHours ~= nil, "...ebenso die erwartete Verkaufsdauer")
        expect(warm.liquidityScore ~= nil, "...und der Liquidity Score")
        expect(warm.profitVelocity ~= nil, "...und die Profit Velocity")
        expectClose(warm.profitVelocity,
            (warm.expectedProfit * warm.sellThrough) / warm.cost
                / (math.max(warm.liquidity.holdingHours, L.VELOCITY.MIN_HOLDING_HOURS) / 24),
            0.0001, "Die Profit Velocity der Chance folgt derselben Formel")
        expect(warm.opportunityScore >= coldScore,
            "Eine gute, belegte Liquiditaet verschlechtert die Bewertung nicht")
    end
    expectEqual(report.withLiquidity, 1,
        "Der Bericht zaehlt genau die eine Zeile mit eigenen Verkaufsdaten")

    -- Alle anderen bleiben ausdruecklich ohne Aussage.
    expect(untouched ~= nil, "Es gibt weiterhin Chancen ohne eigene Verkaufsdaten")
    if untouched then
        expectEqual(untouched.sellThrough, nil, "Sie bleiben bei nil statt bei einer Schaetzung")
        expectEqual(untouched.profitVelocity, nil, "...auch bei der Profit Velocity")
    end

    -- Die Liquiditaet gehoert immer der VERKAUFSSEITE. Beim Entzaubern gibt es
    -- die nicht: Was herauskommt, steht vorher nicht fest. Die Verkaufsdaten des
    -- gekauften Items duerfen deshalb NICHT durchschlagen.
    local disenchantable = 777
    for index = 1, 12 do
        Ledger:RecordAuctionPosted({ itemID = disenchantable, quantity = 1,
            unitPrice = 10000, timestamp = base + index * 7200 })
        Ledger:ApplySaleInvoice({ itemName = GetItemInfo(disenchantable), total = 10000,
            consignment = 500, arrivedAt = base + index * 7200 + 3600 })
    end
    expect(Ledger:GetItemStats(disenchantable).liquidityScore ~= nil,
        "Das entzauberbare Item selbst hat eine belegte Liquiditaet")
    Opportunity:Invalidate()
    local disenchantReport = Opportunity:BuildReport(true)
    local disenchant = nil
    for _, opportunity in ipairs(disenchantReport.opportunities) do
        if opportunity.type == "disenchant" then disenchant = opportunity end
    end
    expect(disenchant ~= nil, "Die Attrappe liefert eine Entzauber-Chance")
    if disenchant then
        expectEqual(disenchant.liquidity, nil,
            "Eine Entzauber-Chance uebernimmt die Liquiditaet des Kaufitems nicht")
        expectEqual(disenchant.profitVelocity, nil, "...und bekommt keine Profit Velocity")
        expect(table.concat(Opportunity:Explain(disenchant), "\n")
            :find("was beim Entzaubern herauskommt", 1, true) ~= nil,
            "...und der Tooltip nennt den richtigen Grund dafuer")
    end

    -- Sortiermodi.
    expectEqual(Opportunity:GetSortMode(), "score", "Standard bleibt der Opportunity Score")
    Opportunity:SetSortMode("velocity")
    expectEqual(Opportunity:GetSortMode(), "velocity", "Ein Modus laesst sich setzen")
    expectEqual(Opportunity:SetSortMode("gibtsnicht"), false, "Unbekannte Modi werden abgelehnt")
    Opportunity:Invalidate()
    local sorted = Opportunity:BuildReport(true)
    local seenWithout = false
    for _, opportunity in ipairs(sorted.opportunities) do
        if opportunity.profitVelocity == nil then
            seenWithout = true
        else
            expect(not seenWithout,
                "Nach Profit Velocity sortiert stehen Chancen ohne diese Zahl hinten")
        end
    end
    Opportunity:CycleSortMode()
    expect(Opportunity:GetSortMode() ~= "velocity", "Der Knopf schaltet weiter")
    Opportunity:SetSortMode("score")
    GCP.db.options.opportunityMinProfit = savedMinProfit
    GCP.db.options.opportunityMinROI = savedMinROI
    Opportunity:Invalidate()

    -- --- Future Market ------------------------------------------------------
    local signalInput = { futureDemandScore = 70, marketScore = 60, hypeScore = 40,
        zone = "ACCUMULATION", knowledgeConfidence = "high", marketConfidence = "high" }
    local function signalWith(liquidityScore, liquidityConfidence)
        local input = {}
        for key, value in pairs(signalInput) do input[key] = value end
        input.liquidityScore = liquidityScore
        input.liquidityConfidence = liquidityConfidence
        return Future:ComputeSignal(input)
    end
    local plainSignal = signalWith(nil, nil)
    expectEqual(signalWith(95, "low"), plainSignal,
        "Unter mittlerer Datenlage bleibt das Investment Signal unberuehrt")
    expectEqual(signalWith(95, "none"), plainSignal,
        "Unbekannte Liquiditaet bleibt neutral")
    expect(signalWith(95, "high") > plainSignal,
        "Gute, belegte Liquiditaet hebt das Investment Signal leicht an")
    expect(signalWith(10, "high") < plainSignal, "Schlechte senkt es")
    expect(math.abs(signalWith(95, "high") - plainSignal) <= 8,
        "Der Einfluss bleibt klein - Spielwissen wiegt schwerer")

    -- Der Future Demand Score selbst bleibt unangetastet.
    local demandBefore = Future:GetFutureDemandScore(23571)
    Ledger:RecordAuctionPosted({ itemID = 23571, quantity = 3, unitPrice = 90000,
        timestamp = mockNow - 3600 })
    Ledger:ApplySaleInvoice({ itemName = "Urmacht", total = 270000, consignment = 13500,
        arrivedAt = mockNow - 1800 })
    Future:Invalidate()
    expectEqual(Future:GetFutureDemandScore(23571), demandBefore,
        "Neue Verkaufsdaten aendern den Future Demand Score nicht - er ist Spielwissen")

    -- --- Chancen-Protokoll: Ergebnis einer alten Chance ----------------------
    resetLedger()
    GCP.db.opportunityHistory = {
        { timestamp = base, type = "resale", itemID = 10939, marketPrice = 40000,
          expectedProfit = 8000, opportunityScore = 72, confidence = "high" },
        { timestamp = base, type = "resale", itemID = 10938, marketPrice = 100,
          expectedProfit = 50, opportunityScore = 65, confidence = "high" },
    }
    Ledger:RecordPurchase({ itemID = 10939, quantity = 10, unitPrice = 40000,
        timestamp = base + 12 * 3600 })
    Ledger:RecordAuctionPosted({ itemID = 10939, quantity = 10, unitPrice = 55000,
        timestamp = base + 13 * 3600 })
    Ledger:ApplySaleInvoice({ itemName = "Hohe Magieessenz", total = 550000,
        consignment = 27500, arrivedAt = base + 20 * 3600 })
    Opportunity:MatchHistoryOutcomes()

    local logged = GCP.db.opportunityHistory[1]
    expectEqual(logged.executedAt, base + 12 * 3600, "Der Kauf wird der Chance zugeordnet")
    expectEqual(logged.entryPrice, 40000, "Der Einstiegspreis kommt aus dem Kauf")
    expectEqual(logged.exitPrice, 52250, "Der Ausstiegspreis ist der Nettoerloes je Stueck")
    expectEqual(logged.outcome, "WIN", "Ein Gewinn wird als WIN abgelegt")
    expectEqual(logged.realizedProfit, (52250 - 40000) * 10, "...mit dem realisierten Gewinn")
    expectClose(logged.holdingHours, 8, 0.01, "...und der Haltedauer")

    local untouchedEntry = GCP.db.opportunityHistory[2]
    expectEqual(untouchedEntry.outcome, nil,
        "Eine Chance ohne zuordenbaren Handel bleibt ohne Ergebnis - kein geratenes UNKNOWN")
    expectEqual(untouchedEntry.executedAt, nil, "...und ohne Ausfuehrungszeitpunkt")

    -- Ein zweiter Lauf darf nichts umschreiben.
    Ledger:RecordPurchase({ itemID = 10939, quantity = 10, unitPrice = 99000,
        timestamp = base + 30 * 86400 })
    Opportunity:MatchHistoryOutcomes()
    expectEqual(GCP.db.opportunityHistory[1].entryPrice, 40000,
        "Ein spaeterer Kauf schreibt ein fertiges Ergebnis nicht um")
    expectEqual(GCP.db.opportunityHistory[1].outcome, "WIN", "...und auch nicht das Ergebnis")

    -- Ausfuehrungsstatus.
    expectEqual(Opportunity:ExecutionStatus(60003), "AVAILABLE",
        "Ohne eigene Spur bleibt eine Chance schlicht verfuegbar")
    Ledger:RecordAuctionPosted({ itemID = 60003, quantity = 1, unitPrice = 60000,
        timestamp = mockNow - 600 })
    expectEqual(Opportunity:ExecutionStatus(60003), "POSTED",
        "Eine offene Einstellung ist ein belegter Status")

    -- Aufraeumen hinterher: Die folgenden Abschnitte sollen eine leere Bilanz
    -- sehen, damit ihre Zahlen aus 0.6 und 0.7 unveraendert bleiben.
    GCP.db.opportunityHistory = {}
    resetLedger()
    Opportunity:Invalidate()
    Future:Invalidate()
    GetInboxNumItems = nil
    GetInboxHeaderInfo = nil
    GetInboxInvoiceInfo = nil
    GetInboxItemLink = nil
    GetInboxItem = nil
end
ledgerSection()

-- ---------------------------------------------------------------------------
-- Bestehende SavedVariables ueberleben das Update
-- ---------------------------------------------------------------------------

-- Eine Datenbank aus 0.3.0: roadmap.day ist dort noch ein Kalendertag.
GoldCopilotDB = {
    version = "0.3.0",
    options = { priceSource = "tsm", minRoadmapValue = 12345, ignored = { [999] = true } },
    questGold = { [11364] = 111100 },
    roadmap = {
        day = "2026-01-01",
        checked = { ["cd:28566"] = true },
        baseline = { ["farm:23425"] = 3 },
    },
    goldHistory = { ["2026-01-01"] = 4242 },
    priceHistory = { [23425] = { ["2026-01-01"] = 4711 } },
    recipes = { ["Kochkunst"] = { scannedAt = "2026-01-01", list = {} } },
}
local migrated = GCP:EnsureDB()
expectEqual(migrated.version, "0.8.0", "EnsureDB schreibt die neue Version")
expectEqual(migrated.options.priceSource, "tsm", "Gespeicherte Preisquelle bleibt erhalten")
expectEqual(migrated.options.minRoadmapValue, 12345, "Gespeicherter Mindestgewinn bleibt erhalten")
expectEqual(migrated.options.ignored[999], true, "Ignorierte Items bleiben erhalten")
expectEqual(migrated.options.keepConsumables, true, "Fehlende Option bekommt ihren Standardwert")
expectEqual(migrated.questGold[11364], 111100, "Gelerntes Questgold bleibt erhalten")
expectEqual(migrated.goldHistory["2026-01-01"], 4242, "Der Goldverlauf bleibt unangetastet")
expectEqual(migrated.priceHistory[23425]["2026-01-01"], 4711, "Die Preishistorie bleibt unangetastet")
expectEqual(migrated.recipes["Kochkunst"].scannedAt, "2026-01-01", "Gescannte Rezepte bleiben erhalten")
-- Einzig der Tagesplan startet neu: Ein Kalendertag ist keine Resetperiode.
expectEqual(migrated.roadmap.day, GCP:ResetPeriodKey(), "roadmap.day traegt jetzt die Resetperiode")
expectEqual(migrated.roadmap.checked["cd:28566"], nil,
    "Der Wechsel auf den Serverreset raeumt die Checkliste genau einmal")

-- Die Markthistorie legt sich beim Update von selbst an, ohne irgendetwas
-- Bestehendes zu ersetzen.
expect(type(migrated.marketHistory) == "table", "Das Update legt die Markthistorie an")
expectEqual(migrated.marketHistory.version, MARKET.STORE_VERSION,
    "Die neue Markthistorie traegt ihre Formatversion")
expect(type(migrated.priceHistory) == "table",
    "Die alte Preishistorie existiert unveraendert weiter")

-- Dasselbe fuer die Neuzugaenge aus 0.6.0: leer angelegt, nichts ersetzt.
expect(type(migrated.watchlist) == "table", "Das Update legt die Watchlist an")
expectEqual(next(migrated.watchlist), nil, "...und zwar leer")
expect(type(migrated.opportunityHistory) == "table",
    "Das Update legt das Chancen-Protokoll an")
expectEqual(#migrated.opportunityHistory, 0, "...und zwar leer")
expectEqual(migrated.options.opportunityMinProfit,
    GCP.Constants.OPPORTUNITY.DEFAULT_MIN_PROFIT,
    "Der Mindestprofit der Chancen bekommt seinen Standardwert")
expectEqual(migrated.options.opportunityMinROI,
    GCP.Constants.OPPORTUNITY.DEFAULT_MIN_ROI,
    "Der Mindest-ROI der Chancen bekommt seinen Standardwert")

-- Und dasselbe fuer die Handelsbilanz aus 0.8.0: Sie legt sich leer an, ersetzt
-- nichts und behauptet vor dem ersten eigenen Verkauf gar nichts.
expect(type(migrated.ledger) == "table", "Das Update legt die Handelsbilanz an")
expectEqual(migrated.ledger.version, GCP.Constants.LEDGER.STORE_VERSION,
    "Die neue Handelsbilanz traegt ihre Formatversion")
expectEqual(#migrated.ledger.events, 0, "...und ist leer")
expectEqual(next(migrated.ledger.items), nil, "...auch ohne jede Item-Statistik")
expectEqual(GCP.Ledger:HasData(), false, "Ein frisches Update hat keine Handelsdaten")
expectEqual(GCP.Ledger:GetItemStats(23425), nil,
    "Ohne Daten gibt es keine Item-Statistik, sondern nil")
expectEqual(GCP.Ledger:GetLiquidity(23425), nil, "...und keine Liquiditaetsaussage")
expectEqual(migrated.options.opportunitySort, "score",
    "Die Sortierung der Chancen startet auf dem Opportunity Score")
expectEqual(migrated.options.ledgerSort, "liquidity",
    "Der Handel-Tab startet nach Liquiditaet sortiert")

-- Ein Speicher aus einer unbekannten Formatversion wird verworfen - und zwar
-- nur er. Alles andere in der Datenbank bleibt stehen.
migrated.ledger = { version = 99, events = "kaputt" }
GCP.Ledger:EnsureStore()
expectEqual(GoldCopilotDB.ledger.version, GCP.Constants.LEDGER.STORE_VERSION,
    "Eine unbekannte Formatversion der Handelsbilanz wird ersetzt")
expectEqual(GoldCopilotDB.priceHistory[23425]["2026-01-01"], 4711,
    "...ohne irgendetwas anderes anzufassen")
expectEqual(migrated.options.minRoadmapValue, 12345,
    "Der gespeicherte Mindestgewinn des Tagesplans bleibt davon unberuehrt")

-- Eine 0.6-Datenbank mit gefuellter Watchlist und Protokoll: beides bleibt
-- unveraendert stehen, auch die eigenen Filterwerte.
GoldCopilotDB = {
    version = "0.6.0",
    options = { priceSource = "auto", ignored = {},
                opportunityMinProfit = 250000, opportunityMinROI = 0.20 },
    questGold = {}, roadmap = { day = GCP:ResetPeriodKey(), checked = {}, baseline = {} },
    goldHistory = {}, priceHistory = {}, recipes = {},
    watchlist = { [23425] = { reason = "Chancen-Tab", addedAt = mockNow - 3600 } },
    opportunityHistory = {
        { timestamp = mockNow - 86400, type = "craft", itemID = 60001,
          marketPrice = 2000, expectedProfit = 5600, opportunityScore = 71,
          confidence = "high" },
    },
}
local kept = GCP:EnsureDB()
expectEqual(kept.watchlist[23425].reason, "Chancen-Tab",
    "Eine bestehende Watchlist ueberlebt den Start")
expectEqual(kept.watchlist[23425].addedAt, mockNow - 3600,
    "...samt Aufnahmezeitpunkt")
expectEqual(#kept.opportunityHistory, 1, "Das Chancen-Protokoll ueberlebt den Start")
expectEqual(kept.opportunityHistory[1].opportunityScore, 71,
    "...mit allen Werten")
expectEqual(kept.options.opportunityMinProfit, 250000,
    "Eigene Chancen-Filter bleiben erhalten")
expectEqual(kept.options.opportunityMinROI, 0.20,
    "...auch der Mindest-ROI")
expectEqual(GCP.Market:IsWatched(23425), true,
    "Die uebernommene Watchlist wird sofort wieder beachtet")

-- Eine 0.4-Datenbank mit frischen Tageswerten: die echten Preise wandern als
-- Messpunkte in die Markthistorie, die Tageshistorie bleibt daneben stehen.
local importOlder = date("%Y-%m-%d", mockNow - 2 * 86400)
local importNewer = date("%Y-%m-%d", mockNow - 1 * 86400)
GoldCopilotDB = {
    version = "0.4.0",
    options = { priceSource = "auto", ignored = {} },
    questGold = {},
    roadmap = { day = GCP:ResetPeriodKey(), checked = {}, baseline = {} },
    goldHistory = { [importOlder] = 4242 },
    priceHistory = { [23425] = { [importOlder] = 40000, [importNewer] = 42000 } },
    recipes = {},
}
local imported = GCP:EnsureDB()
expectEqual(imported.priceHistory[23425][importOlder], 40000,
    "Die uebernommene Tageshistorie bleibt unveraendert erhalten")
expectEqual(GCP.Market:SnapshotCount(23425), 2,
    "Vorhandene Tageswerte werden als Messpunkte uebernommen")
local _, importedNewest = GCP.Market:LastSnapshot(23425)
expectEqual(importedNewest, 42000, "Der juengste Tageswert steht am Ende der Reihe")
expectEqual(imported.marketHistory.imported, true, "Die Uebernahme ist als erledigt vermerkt")
GCP:EnsureDB()
expectEqual(GCP.Market:SnapshotCount(23425), 2,
    "Ein zweiter Start uebernimmt nicht noch einmal")

-- ---------------------------------------------------------------------------
-- Ergebnis
-- ---------------------------------------------------------------------------

print(string.format("smoke.lua: %d Tests bestanden, %d fehlgeschlagen", passed, failed))
if failed > 0 then
    error("Es gibt fehlgeschlagene Tests.")
end
