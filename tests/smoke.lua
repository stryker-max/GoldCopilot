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

function time()
    return mockNow
end

function GetTime()
    return mockNow
end

function GetMoney()
    return 100000
end

function UnitLevel()
    return 70
end

DEFAULT_CHAT_FRAME = { AddMessage = function() end }
SlashCmdList = {}
UIParent = {}
UISpecialFrames = {}
C_Timer = { After = function() end }

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
-- subType, stackCount, equipLoc, icon, sellPrice, classID.
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
}

function GetItemInfo(item)
    local id = tonumber(item)
    if not id then
        id = tonumber(tostring(item):match("item:(%d+)"))
    end
    local entry = items[id]
    if not entry then return nil end
    return entry[1], entry[2], entry[3], entry[4], entry[5], entry[6],
        entry[7], entry[8], entry[9], entry[10], entry[11], entry[12]
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
    [777] = 10000,
    [888] = 90000,
    [999] = 1000,
    [60001] = 8000,
    [60002] = 2000,
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
        },
    },
}

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
              { itemID = 60002, itemCount = 5, itemLink = "item:60002" } },
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
C_QuestLog = {
    IsQuestFlaggedCompleted = function(questID)
        return completedQuests[questID] == true
    end,
}

-- Fertigkeitenfenster: Sammelberufe des Charakters.
local skillLines = {
    { "Berufe", true, 0 },
    { "Kräuterkunde", false, 375 },
    { "Bergbau", false, 375 },
    { "Kürschnerei", false, 300 },
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
    "Advisor.lua", "Flips.lua", "Crafts.lua", "Roadmap.lua", "UI.lua",
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
expect(keys["cd:29688"].text:find("bereit in") ~= nil, "Laufender Cooldown nennt die Restzeit")
expect(keys["sell:23425"] ~= nil, "Groesster Verkaufsposten steht im Tagesplan")
expect(keys["craft:60001"] ~= nil, "Bestes Craft-Rezept steht im Tagesplan")
expectEqual(keys["craft:60001"].value, 5600 * 5, "Craft-Wert rechnet Gewinn mal Machbarkeit")
expect(keys["farm:23425"] ~= nil, "Farm-Tipp vorhanden")
expect(keys["farm:23425"].text:find("je Stunde") ~= nil, "Farm-Tipp rechnet in Gold je Stunde")
expectEqual(keys["farm:23425"].value, 50000 * 40, "Farmwert ist Preis mal Stundenrate")

expect(keys["daily:11023"] ~= nil, "Freigeschaltete Daily wird vorgeschlagen")
expectEqual(keys["daily:11080"].done, true, "Bereits gemachte Daily ist von selbst abgehakt")
expectEqual(keys["daily:11080"].autoDone, true, "Daily-Erkennung laeuft ueber das Quest-Flag")

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
-- Ergebnis
-- ---------------------------------------------------------------------------

print(string.format("smoke.lua: %d Tests bestanden, %d fehlgeschlagen", passed, failed))
if failed > 0 then
    error("Es gibt fehlgeschlagene Tests.")
end
