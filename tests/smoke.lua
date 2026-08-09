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
    "Constants.lua", "Core.lua", "Prices.lua", "Inventory.lua",
    "Advisor.lua", "Flips.lua", "Crafts.lua", "Market.lua", "Quests.lua",
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
expectEqual(migrated.version, "0.5.0", "EnsureDB schreibt die neue Version")
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
