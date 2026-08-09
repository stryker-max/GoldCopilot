-- Render-Test fuer UI.lua: baut das Fenster mit einer Frame-Attrappe auf und
-- zeichnet jeden Tab einmal ohne und einmal mit Markthistorie. smoke.lua prueft
-- die Rechenwege, dieser Test die Oberflaeche - Layoutfehler, vergessene
-- Spalten und Tooltips, die nie erscheinen, faellt sonst niemandem auf.
--
-- Bewusst eine eigene Datei mit eigenem Lua-Zustand: Die reichhaltigere
-- Attrappe darf das Verhalten der bestehenden Tests nicht verschieben.
-- Start ueber "node tests/run.mjs" aus dem Repo-Wurzelverzeichnis.

unpack = unpack or table.unpack

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

local mockNow = os.time({ year = 2026, month = 9, day = 1, hour = 8 })
function date(fmt, t) return os.date(fmt, t or mockNow) end
function time(spec)
    if type(spec) == "table" then return os.time(spec) end
    return mockNow
end
function GetTime() return mockNow end
function GetQuestResetTime() return 3600 end
function GetMoney() return 100000 end
function UnitLevel() return 70 end
function InCombatLockdown() return false end
function IsShiftKeyDown() return false end

DEFAULT_CHAT_FRAME = { AddMessage = function() end }
SlashCmdList = {}
UISpecialFrames = {}
function tinsert(list, value) list[#list + 1] = value end

local timers = {}
C_Timer = { After = function(_, fn) timers[#timers + 1] = fn end }

-- --- Attrappen fuer Texturen, Fontstrings und Frames ------------------------

local function newTexture()
    local tex = { _shown = true }
    return setmetatable(tex, { __index = function(t, key)
        if key == "IsShown" then return function(self) return self._shown end end
        if key == "Show" then return function(self) self._shown = true end end
        if key == "Hide" then return function(self) self._shown = false end end
        if key == "SetShown" then return function(self, v) self._shown = v and true or false end end
        if type(key) == "string" and key:match("^%u") then return function() end end
        return nil
    end })
end

local function newFontString()
    local fs = { _text = "", _shown = true }
    function fs:SetFont(font, size) assert(type(font) == "string", "SetFont ohne Font")
        assert(type(size) == "number", "SetFont ohne Groesse") end
    function fs:SetText(text)
        assert(text == nil or type(text) == "string" or type(text) == "number",
            "SetText mit " .. type(text))
        self._text = text and tostring(text) or ""
    end
    function fs:GetText() return self._text end
    function fs:SetTextColor(r, g, b)
        assert(type(r) == "number" and type(g) == "number" and type(b) == "number",
            "SetTextColor ohne Farbe")
    end
    function fs:GetStringWidth() return #self._text * 6 end
    function fs:Show() self._shown = true end
    function fs:Hide() self._shown = false end
    function fs:IsShown() return self._shown end
    function fs:SetShown(v) self._shown = v and true or false end
    return setmetatable(fs, { __index = function(_, key)
        if type(key) == "string" and key:match("^%u") then return function() end end
        return nil
    end })
end

local frameMethods = {}
local frameMeta = { __index = function(t, key)
    local method = frameMethods[key]
    if method then return method end
    if type(key) == "string" and key:match("^%u") then return function() end end
    return nil
end }

function frameMethods.CreateTexture() return newTexture() end
function frameMethods.CreateFontString() return newFontString() end
function frameMethods.SetScript(self, name, fn) self._scripts[name] = fn end
function frameMethods.GetScript(self, name) return self._scripts[name] end
function frameMethods.Show(self) self._shown = true
    local fn = self._scripts.OnShow; if fn then fn(self) end end
function frameMethods.Hide(self) self._shown = false end
function frameMethods.IsShown(self) return self._shown end
function frameMethods.SetShown(self, v) self._shown = v and true or false end
function frameMethods.SetHeight(self, h) self._height = h end
function frameMethods.GetHeight(self) return self._height or 26 end
function frameMethods.SetWidth(self, w) self._width = w end
function frameMethods.GetWidth(self) return self._width or 100 end
function frameMethods.SetSize(self, w, h) self._width, self._height = w, h end
function frameMethods.GetParent(self) return self._parent end
function frameMethods.RegisterEvent(self, event)
    assert(type(event) == "string", "RegisterEvent ohne Ereignisnamen")
end

function CreateFrame(_, _, parent)
    return setmetatable({ _shown = false, _scripts = {}, _parent = parent }, frameMeta)
end

UIParent = CreateFrame("Frame")

GameTooltip = setmetatable({}, { __index = function(_, key)
    if type(key) == "string" and key:match("^%u") then return function() return true end end
    return nil
end })

-- --- Daten ------------------------------------------------------------------

local items = {
    [21884] = { "Urfeuer", "item:21884", 1, 65, 0, "Handwerkswaren", "Elementar", 20, "", 101, 0, 7 },
    [22574] = { "Feuerpartikel", "item:22574", 1, 65, 0, "Handwerkswaren", "Elementar", 20, "", 108, 0, 7 },
    [23425] = { "Adamantiterz", "item:23425", 1, 65, 0, "Handwerkswaren", "Metall", 20, "", 116, 25, 7 },
    [22785] = { "Teufelsgras", "item:22785", 1, 60, 0, "Handwerkswaren", "Kraut", 20, "", 117, 5, 7 },
    [10938] = { "Niedere Magieessenz", "item:10938", 2, 15, 0, "Handwerkswaren", "Verzauberung", 10, "", 119, 0, 7 },
    [10939] = { "Hohe Magieessenz", "item:10939", 2, 20, 0, "Handwerkswaren", "Verzauberung", 10, "", 120, 0, 7 },
    [60001] = { "Knusperschlange", "item:60001", 1, 70, 0, "Verbrauchbar", "Essen", 20, "", 126, 2, 0 },
    [60002] = { "Schlangenfleisch", "item:60002", 1, 65, 0, "Handwerkswaren", "Fleisch", 20, "", 127, 1, 7 },
}
function GetItemInfo(item)
    local id = tonumber(item) or tonumber(tostring(item):match("item:(%d+)"))
    local entry = items[id]
    if not entry then return nil end
    return unpack(entry)
end
C_Item = { GetItemInfo = GetItemInfo }

local marketPrices = {
    [21884] = 1300, [22574] = 100, [23425] = 50000, [22785] = 800,
    [10938] = 100, [10939] = 400, [60001] = 8000, [60002] = 2000,
}
Auctionator = { API = { v1 = {
    GetAuctionPriceByItemID = function(_, id) return marketPrices[id] end,
    GetDisenchantPriceByItemLink = function() return nil end,
    GetAuctionAgeByItemID = function() return 0 end,
    RegisterForDBUpdate = function() end,
} } }

local bags = {
    [0] = { { itemID = 23425, stackCount = 40, hyperlink = "item:23425" },
            { itemID = 22574, stackCount = 25, hyperlink = "item:22574" } },
}
C_Container = {
    GetContainerNumSlots = function(bag) return bags[bag] and #bags[bag] or 0 end,
    GetContainerItemInfo = function(bag, slot) return bags[bag] and bags[bag][slot] end,
}

function GetNumSkillLines() return 2 end
function GetSkillLineInfo(index)
    if index == 1 then return "Kräuterkunde", false, nil, 375 end
    return "Bergbau", false, nil, 375
end
function IsPlayerSpell() return true end
function GetSpellCooldown() return 0, 0, 1 end
C_QuestLog = { IsQuestFlaggedCompleted = function() return false end }
function GetNumQuestLogEntries() return 0 end

-- --- Addon laden und alle Tabs rendern --------------------------------------

local GCP = {}
for _, file in ipairs({
    "Constants.lua", "Core.lua", "Prices.lua", "Inventory.lua", "Advisor.lua",
    "Flips.lua", "Crafts.lua", "Market.lua", "Quests.lua", "Roadmap.lua", "UI.lua",
}) do
    local chunk, err = loadfile(file)
    assert(chunk, "Ladefehler in " .. file .. ": " .. tostring(err))
    chunk("GoldCopilot", GCP)
end

GCP:EnsureDB()

local TABS = { "today", "sell", "flips", "crafts", "market", "options" }

-- Kaltstart: jeder Tab muss auch ohne eine einzige Zeile Historie zeichnen.
for _, tab in ipairs(TABS) do
    local ok, err = pcall(GCP.UI.SelectTab, GCP.UI, tab)
    expect(ok, string.format("Tab \"%s\" zeichnet beim Kaltstart (%s)", tab, tostring(err)))
end

GCP.UI:SelectTab("market")
local coldSummary = GCP.UI.frame.summary:GetText()
expect(coldSummary:find("beobachtet") ~= nil,
    "Der Markt-Tab nennt die Zahl der beobachteten Märkte")
expect(coldSummary:find("noch keine Preispunkte") ~= nil,
    "Der Kaltstart sagt ausdrücklich, dass noch keine Daten vorliegen")
local coldText = {}
for _, row in ipairs(GCP.UI.rows) do
    coldText[#coldText + 1] = row.text:GetText() or ""
end
expect(table.concat(coldText, "\n"):find("lernt deinen Realm") ~= nil,
    "Der Kaltstart erklärt, dass das Addon erst lernt")

-- Historie ueber gut eine Woche, damit Score und Confidence etwas zu tun haben.
local base = mockNow - 8 * 86400
for step = 0, 15 do
    local stamp = base + step * 12 * 3600
    for itemID, price in pairs(marketPrices) do
        local wobble = 1 + ((step % 4) - 1.5) * 0.08
        GCP.Market:AddSnapshot(itemID, math.floor(price * wobble), stamp, "Auctionator")
    end
end
GCP.Market:InvalidateCaches()

for _, tab in ipairs(TABS) do
    local ok, err = pcall(GCP.UI.SelectTab, GCP.UI, tab)
    expect(ok, string.format("Tab \"%s\" zeichnet mit Historie (%s)", tab, tostring(err)))
end

-- Kopfzeile und Spalten des Markt-Tabs.
GCP.UI:SelectTab("market")
local header = GCP.UI.rows[1]
expectEqual(header.cols[1]:GetText(), "PERZENTIL", "Spaltenkopf Perzentil")
expectEqual(header.cols[2]:GetText(), "30T MEDIAN", "Spaltenkopf 30-Tage-Median")
expectEqual(header.cols[3]:GetText(), "7T MEDIAN", "Spaltenkopf 7-Tage-Median")
expectEqual(header.cols[4]:GetText(), "JETZT", "Spaltenkopf Jetzt")
expectEqual(header.value:GetText(), "SCORE", "Spaltenkopf Score")

local warmSummary = GCP.UI.frame.summary:GetText()
expect(warmSummary:find("Preispunkte") ~= nil, "Die Kopfzeile zählt die Preispunkte")
expect(warmSummary:find("Historie") ~= nil, "Die Kopfzeile nennt die Länge der Historie")

-- Erste Datenzeile: alle fuenf Spalten gefuellt, Tooltip vollstaendig.
local row = GCP.UI.rows[2]
expect(row ~= nil, "Der Markt-Tab erzeugt Datenzeilen")
expect(row.text:GetText() ~= "", "Die Zeile nennt das Item")
for column = 1, 4 do
    expect(row.cols[column]:GetText() ~= "",
        string.format("Spalte %d der Datenzeile ist gefüllt", column))
end
expect(row.value:GetText() ~= "", "Die Score-Spalte ist gefüllt")
expect(row.autoPill:IsShown(), "Die Confidence steht als eigenes Etikett daneben")

local breakdown = table.concat(row.data.breakdown, "\n")
for _, needle in ipairs({
    "Aktuell:", "24h Median:", "7d Median:", "30d Median:", "7d Range:",
    "Perzentil:", "Volatilität:", "Snapshots:", "Historientage:",
    "Market Score:", "Confidence:",
}) do
    expect(breakdown:find(needle, 1, true) ~= nil,
        "Der Tooltip nennt \"" .. needle .. "\"")
end
expect(breakdown:find("Nachfrage", 1, true) ~= nil,
    "Der Tooltip sagt ausdrücklich, was der Score nicht bedeutet")

-- Sortierung: der Score faellt von oben nach unten.
local previous = nil
for index = 2, #GCP.UI.rows do
    local line = GCP.UI.rows[index]
    local score = tonumber(line.value:GetText() or "")
    if score then
        if previous then
            expect(score <= previous, "Der Markt-Tab sortiert nach Score absteigend")
        end
        previous = score
    end
end

-- Mausereignisse und Klick dürfen nicht in die Wand laufen.
expect(pcall(row:GetScript("OnEnter"), row), "Tooltip einer Marktzeile öffnet")
expect(pcall(row:GetScript("OnLeave"), row), "Tooltip einer Marktzeile schließt")
expect(pcall(row:GetScript("OnClick"), row, "LeftButton"), "Klick auf eine Marktzeile")

-- Fenster oeffnen loest OnShow samt Aufzeichnung aus.
expect(pcall(GCP.UI.Toggle, GCP.UI), "Das Fenster lässt sich öffnen")
for _, fn in ipairs(timers) do fn() end
expect(GCP.UI.frame:IsShown(), "Nach dem Öffnen ist das Fenster sichtbar")

print(string.format("ui.lua: %d Tests bestanden, %d fehlgeschlagen", passed, failed))
if failed > 0 then
    error("Es gibt fehlgeschlagene Tests.")
end
