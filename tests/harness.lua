-- Gemeinsame WoW-Attrappe und Simulationsschicht fuer die Tests ab 0.9.0.
--
-- smoke.lua und ui.lua bringen ihre eigenen, historisch gewachsenen Attrappen
-- mit und bleiben unangetastet. Alles, was danach kam - Capital, Execution,
-- Route, Guide, Navigation, Farm, Personal, Kalibrierung - braucht dagegen
-- eine Umgebung, die sich WAEHREND eines Tests aendern laesst: Preise steigen,
-- Taschen fuellen sich, Ereignisse feuern, die Uhr laeuft weiter. Genau das
-- ist hier drin.
--
-- Verwendung:
--   local H = dofile("tests/harness.lua")
--   H.install()                    -- Globals setzen
--   local GCP = H.loadAddon()      -- Addon-Dateien laden
--   H.fire("AUCTION_HOUSE_SHOW")   -- Ereignis ausloesen
--   H.report("engine.lua")         -- Ergebnis ausgeben, Fehler werfen

local H = {}

-- ---------------------------------------------------------------------------
-- Testgeruest
-- ---------------------------------------------------------------------------

H.passed, H.failed = 0, 0
H.failures = {}

function H.expect(condition, label)
    if condition then
        H.passed = H.passed + 1
    else
        H.failed = H.failed + 1
        H.failures[#H.failures + 1] = label
        print("FEHLSCHLAG: " .. tostring(label))
    end
    return condition and true or false
end

function H.expectEqual(actual, wanted, label)
    return H.expect(actual == wanted, string.format("%s (erwartet %s, erhalten %s)",
        label, tostring(wanted), tostring(actual)))
end

function H.expectNear(actual, wanted, tolerance, label)
    local ok = type(actual) == "number" and math.abs(actual - wanted) <= tolerance
    return H.expect(ok, string.format("%s (erwartet ~%s, erhalten %s)",
        label, tostring(wanted), tostring(actual)))
end

function H.expectRange(actual, low, high, label)
    local ok = type(actual) == "number" and actual >= low and actual <= high
    return H.expect(ok, string.format("%s (erwartet %s..%s, erhalten %s)",
        label, tostring(low), tostring(high), tostring(actual)))
end

function H.section(title)
    H.currentSection = title
end

function H.report(name)
    print(string.format("%s: %d Tests bestanden, %d fehlgeschlagen",
        name, H.passed, H.failed))
    if H.failed > 0 then
        error("Es gibt fehlgeschlagene Tests.")
    end
end

-- ---------------------------------------------------------------------------
-- Simulierter Zustand
-- ---------------------------------------------------------------------------

H.now = os.time({ year = 2026, month = 8, day = 8, hour = 12 })
H.money = 30000000                 -- 3000 g
H.playerLevel = 70
H.questResetSeconds = 3600
H.facing = 0                       -- Blickrichtung in Radiant
H.mapID = 100
H.position = { x = 0.5, y = 0.5 }
H.zoneName = "Höllenfeuerhalbinsel"
H.realm = "Testrealm"
H.playerName = "Testspieler"
H.faction = "Horde"
H.inCombat = false

-- Zaubernamen fuer die Verzauberungserkennung. Der Client liefert den
-- lokalisierten Namen; die Attrappe tut dasselbe.
H.spells = { [13898] = "Verzaubern: Waffe - Feuerbrand",
    [27837] = "Verzaubern: Waffe - Große Beweglichkeit",
    [2018] = "Schmiedekunst" }

-- Die globale Zeichenkette, mit der der Client einen abgeschlossenen Handel
-- meldet. Sie ist der einzige Beleg dafuer, dass ein Handel wirklich zustande
-- kam - TRADE_CLOSED feuert auch beim Abbruch.
ERR_TRADE_COMPLETE = "Handel abgeschlossen."

-- Item-Katalog. Reihenfolge wie GetItemInfo: name, link, quality, itemLevel,
-- minLevel, type, subType, stackCount, equipLoc, icon, sellPrice, classID,
-- subClassID, bindType.
H.items = {
    [21884] = { "Urfeuer", "item:21884", 1, 65, 0, "Handwerkswaren", "Elementar", 20, "", 101, 0, 7, 12 },
    [21885] = { "Urwasser", "item:21885", 1, 65, 0, "Handwerkswaren", "Elementar", 20, "", 102, 0, 7, 12 },
    [22451] = { "Urluft", "item:22451", 1, 65, 0, "Handwerkswaren", "Elementar", 20, "", 103, 0, 7, 12 },
    [22452] = { "Urerde", "item:22452", 1, 65, 0, "Handwerkswaren", "Elementar", 20, "", 104, 0, 7, 12 },
    [22456] = { "Urschatten", "item:22456", 1, 65, 0, "Handwerkswaren", "Elementar", 20, "", 105, 0, 7, 12 },
    [22457] = { "Urmana", "item:22457", 1, 65, 0, "Handwerkswaren", "Elementar", 20, "", 106, 0, 7, 12 },
    [21886] = { "Urleben", "item:21886", 1, 65, 0, "Handwerkswaren", "Elementar", 20, "", 107, 0, 7, 12 },
    [22574] = { "Feuerpartikel", "item:22574", 1, 65, 0, "Handwerkswaren", "Elementar", 20, "", 108, 0, 7, 12 },
    [22578] = { "Wasserpartikel", "item:22578", 1, 65, 0, "Handwerkswaren", "Elementar", 20, "", 109, 0, 7, 12 },
    [22572] = { "Luftpartikel", "item:22572", 1, 65, 0, "Handwerkswaren", "Elementar", 20, "", 110, 0, 7, 12 },
    [22573] = { "Erdpartikel", "item:22573", 1, 65, 0, "Handwerkswaren", "Elementar", 20, "", 111, 0, 7, 12 },
    [22577] = { "Schattenpartikel", "item:22577", 1, 65, 0, "Handwerkswaren", "Elementar", 20, "", 112, 0, 7, 12 },
    [22576] = { "Manapartikel", "item:22576", 1, 65, 0, "Handwerkswaren", "Elementar", 20, "", 113, 0, 7, 12 },
    [22575] = { "Lebenspartikel", "item:22575", 1, 65, 0, "Handwerkswaren", "Elementar", 20, "", 114, 0, 7, 12 },
    [23571] = { "Urmacht", "item:23571", 2, 70, 0, "Handwerkswaren", "Elementar", 20, "", 115, 0, 7, 12 },
    [23425] = { "Adamantiterz", "item:23425", 1, 65, 0, "Handwerkswaren", "Metall", 20, "", 116, 25, 7, 7 },
    [22785] = { "Teufelsgras", "item:22785", 1, 60, 0, "Handwerkswaren", "Kraut", 20, "", 117, 5, 7, 9 },
    [21877] = { "Netherstoff", "item:21877", 1, 60, 0, "Handwerkswaren", "Stoff", 20, "", 118, 30, 7, 5 },
    [10938] = { "Niedere Magieessenz", "item:10938", 2, 15, 0, "Handwerkswaren", "Verzauberung", 10, "", 119, 0, 7, 12 },
    [10939] = { "Hohe Magieessenz", "item:10939", 2, 20, 0, "Handwerkswaren", "Verzauberung", 10, "", 120, 0, 7, 12 },
    [777]   = { "Grüne Testklinge", "item:777", 2, 30, 25, "Waffe", "Schwerter", 1, "INVTYPE_WEAPON", 121, 1500, 2, 7 },
    [888]   = { "Gebundene Testschulter", "item:888", 3, 40, 35, "Rüstung", "Stoff", 1, "INVTYPE_SHOULDER", 122, 5000, 4, 1 },
    [999]   = { "Händlerliebling", "item:999", 1, 10, 0, "Handwerkswaren", "Sonstiges", 20, "", 123, 2000, 7, 11 },
    [3000]  = { "Grauer Plunder", "item:3000", 0, 5, 0, "Müll", "Müll", 5, "", 124, 1234, 15, 0 },
    [60003] = { "Manatrank der Auchenai", "item:60003", 1, 70, 0, "Verbrauchbar", "Trank", 20, "", 128, 200, 0, 1 },
    -- Beim Aufheben gebundenes Reagenz (bindType 1 an Stelle 14). Vorbild ist
    -- die Daemonische Rune: Sie hat einen bekannten Wert, steht aber nie im
    -- Auktionshaus, weil man sie farmen muss. Genau daran ist bis
    -- 1.0.0-beta.3 ein Routenschritt "kaufen" entstanden, den niemand
    -- ausfuehren konnte. Die uebrigen Attrappen enden bei subClassID - wie ein
    -- Client, dessen Item-Cache die Bindungsart noch nicht kennt.
    [60010] = { "Gebundenes Testreagenz", "item:60010", 1, 60, 0, "Handwerkswaren",
        "Sonstiges", 20, "", 129, 400, 7, 12, 1 },
}

-- Marktpreise (Kupfer). Laufzeitaenderungen ueber H.setPrice.
H.marketPrices = {
    [21884] = 210000, [21885] = 110000, [22451] = 120000, [22452] = 90000,
    [22456] = 140000, [22457] = 100000, [21886] = 80000,
    [22574] = 18000, [22578] = 9000, [22572] = 10500, [22573] = 7000,
    [22577] = 12000, [22576] = 9500, [22575] = 6000,
    [23571] = 900000,
    [23425] = 50000,
    [22785] = 8000,
    [21877] = 6000,
    [10938] = 10000, [10939] = 40000,
    [777] = 100000,
    [888] = 90000,
    [999] = 10000,
    [60003] = 60000,
    -- Ausdruecklich MIT Preis: Die Beschaffbarkeit muss an der Bindung
    -- scheitern, nicht daran, dass ohnehin kein Preis vorliegt.
    [60010] = 30000,
}

H.disenchantPrices = { ["item:777"] = 150000 }
H.scanAge = {}

-- Taschen. bag -> Liste von { itemID, stackCount, hyperlink, isBound }
H.bags = {
    [0] = {},
    [1] = {},
}

-- Postfach.
H.inbox = {}

-- Auktionshaus-Browserergebnisse je Item: Liste aus
-- { count = 5, buyoutTotal = 100000, owner = "X" }
H.auctionListings = {}
H.auctionQuery = nil

H.skills = {
    { "Berufe", true },
    { "Alchemie", false, 375 },
    { "Verzauberkunst", false, 375 },
    { "Kräuterkunde", false, 375 },
    { "Bergbau", false, 375 },
}

H.timers = {}
H.frames = {}
H.chat = {}
H.tomtom = nil

function H.setPrice(itemID, copper)
    H.marketPrices[itemID] = copper
end

function H.setBag(bag, list)
    H.bags[bag] = list
end

function H.addBagItem(itemID, count, bag)
    bag = bag or 0
    H.bags[bag] = H.bags[bag] or {}
    local link = "item:" .. itemID
    for _, slot in ipairs(H.bags[bag]) do
        if slot.itemID == itemID then
            slot.stackCount = slot.stackCount + count
            return
        end
    end
    H.bags[bag][#H.bags[bag] + 1] =
        { itemID = itemID, stackCount = count, hyperlink = link }
end

function H.clearBags()
    H.bags = { [0] = {}, [1] = {} }
end

function H.advance(seconds)
    H.now = H.now + seconds
end

function H.flushTimers()
    local pending = H.timers
    H.timers = {}
    for _, callback in ipairs(pending) do callback() end
    return #pending
end

-- Ereignis an alle Frames, die es abonniert haben.
function H.fire(event, ...)
    local delivered = 0
    for _, frame in ipairs(H.frames) do
        if frame._events[event] and frame._scripts.OnEvent then
            frame._scripts.OnEvent(frame, event, ...)
            delivered = delivered + 1
        end
    end
    return delivered
end

-- ---------------------------------------------------------------------------
-- Attrappen
-- ---------------------------------------------------------------------------

local function newTexture()
    local tex = { _shown = true }
    return setmetatable(tex, { __index = function(_, key)
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
    function fs:SetText(text) self._text = text and tostring(text) or "" end
    function fs:GetText() return self._text end
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
local frameMeta = { __index = function(_, key)
    local method = frameMethods[key]
    if method then return method end
    if type(key) == "string" and key:match("^%u") then return function() end end
    return nil
end }

function frameMethods.CreateTexture() return newTexture() end
function frameMethods.CreateFontString() return newFontString() end
function frameMethods.SetScript(self, name, fn) self._scripts[name] = fn end
function frameMethods.GetScript(self, name) return self._scripts[name] end
function frameMethods.HookScript(self, name, fn)
    local previous = self._scripts[name]
    self._scripts[name] = function(...)
        if previous then previous(...) end
        fn(...)
    end
end
function frameMethods.RegisterEvent(self, event)
    assert(type(event) == "string" and event ~= "", "RegisterEvent ohne Ereignisnamen")
    self._events[event] = true
end
function frameMethods.UnregisterEvent(self, event) self._events[event] = nil end
function frameMethods.IsEventRegistered(self, event) return self._events[event] or false end
function frameMethods.Show(self)
    self._shown = true
    if self._scripts.OnShow then self._scripts.OnShow(self) end
end
function frameMethods.Hide(self)
    self._shown = false
    if self._scripts.OnHide then self._scripts.OnHide(self) end
end
function frameMethods.IsShown(self) return self._shown end
function frameMethods.IsVisible(self) return self._shown end
function frameMethods.SetShown(self, v)
    if v then frameMethods.Show(self) else frameMethods.Hide(self) end
end
function frameMethods.SetHeight(self, h) self._height = h end
function frameMethods.GetHeight(self) return self._height or 26 end
function frameMethods.SetWidth(self, w) self._width = w end
function frameMethods.GetWidth(self) return self._width or 100 end
function frameMethods.SetSize(self, w, h) self._width, self._height = w, h end
function frameMethods.SetFrameLevel(self, level) self._level = level end
function frameMethods.GetFrameLevel(self) return self._level or 1 end
function frameMethods.GetParent(self) return self._parent end
function frameMethods.GetName(self) return self._name end
function frameMethods.SetPoint(self, ...) self._points = { ... } end
function frameMethods.GetPoint(self) return unpack(self._points or { "CENTER", nil, "CENTER", 0, 0 }) end
function frameMethods.GetScale(self) return self._scale or 1 end
function frameMethods.SetScale(self, scale) self._scale = scale end
function frameMethods.GetLeft(self) return 0 end
function frameMethods.GetTop(self) return 0 end
function frameMethods.GetEffectiveScale(self) return 1 end

H.frameMethods = frameMethods

-- ---------------------------------------------------------------------------
-- Globals installieren
-- ---------------------------------------------------------------------------

function H.install()
    unpack = unpack or table.unpack

    function date(fmt, t) return os.date(fmt, t or H.now) end
    function time(spec)
        if type(spec) == "table" then return os.time(spec) end
        return H.now
    end
    function GetTime() return H.now end
    function GetQuestResetTime() return H.questResetSeconds end
    function GetMoney() return H.money end
    function UnitLevel() return H.playerLevel end
    function UnitName(unit)
        -- Waehrend eines Handels nennt der Client den Partner unter "NPC".
        if unit == "NPC" then return H.trade and H.trade.partner or nil end
        return H.playerName
    end
    function UnitFactionGroup() return H.faction end
    function GetRealmName() return H.realm end
    function InCombatLockdown() return H.inCombat end
    function IsShiftKeyDown() return false end
    function IsControlKeyDown() return false end
    -- H.altDown, damit ein Test das Ablehnen per Alt+Rechtsklick ausloesen kann.
    function IsAltKeyDown() return H.altDown and true or false end
    -- HANDEL (1.1.0). Die Attrappe bildet nach, was der Client wirklich
    -- hergibt - einschliesslich des siebten Slots, in den der Kunde das zu
    -- verzaubernde Item legt und der ausdruecklich NICHT getauscht wird.
    H.trade = H.trade or { partner = nil, targetMoney = 0, playerMoney = 0,
        targetItems = {}, playerItems = {} }
    function GetTargetTradeMoney() return H.trade.targetMoney or 0 end
    function GetPlayerTradeMoney() return H.trade.playerMoney or 0 end
    function GetTradeTargetItemLink(slot) return H.trade.targetItems[slot] end
    function GetTradePlayerItemLink(slot) return H.trade.playerItems[slot] end
    function GetSpellInfo(spellID) return H.spells[spellID] end

    function GetZoneText() return H.zoneName end
    function GetSubZoneText() return "" end
    function GetPlayerFacing() return H.facing end
    function GetCVarBool() return false end

    DEFAULT_CHAT_FRAME = {
        AddMessage = function(_, message) H.chat[#H.chat + 1] = message end,
    }
    SlashCmdList = {}
    UISpecialFrames = {}
    ERR_AUCTION_STARTED = "Auktion erstellt."

    function tinsert(list, value) list[#list + 1] = value end
    function tremove(list, index) return table.remove(list, index) end

    C_Timer = {
        After = function(_, callback) H.timers[#H.timers + 1] = callback end,
        NewTicker = function() return { Cancel = function() end } end,
    }

    function CreateFrame(_, name, parent)
        local frame = setmetatable({
            _shown = false, _scripts = {}, _events = {},
            _parent = parent, _name = name,
        }, frameMeta)
        H.frames[#H.frames + 1] = frame
        return frame
    end

    UIParent = CreateFrame("Frame")
    WorldFrame = CreateFrame("Frame")

    GameTooltip = setmetatable({ _lines = {} }, { __index = function(_, key)
        if key == "SetOwner" then return function(self) self._lines = {} end end
        if key == "AddLine" then
            return function(self, text) self._lines[#self._lines + 1] = tostring(text or "") end
        end
        if key == "AddDoubleLine" then
            return function(self, a, b)
                self._lines[#self._lines + 1] = tostring(a or "") .. "\t" .. tostring(b or "")
            end
        end
        if key == "GetText" then return function(self) return table.concat(self._lines, "\n") end end
        if type(key) == "string" and key:match("^%u") then return function() end end
        return nil
    end })

    -- Items
    function GetItemInfo(item)
        local id = tonumber(item)
        if not id then id = tonumber(tostring(item):match("item:(%d+)")) end
        local entry = H.items[id]
        if not entry then return nil end
        return entry[1], entry[2], entry[3], entry[4], entry[5], entry[6],
            entry[7], entry[8], entry[9], entry[10], entry[11], entry[12],
            entry[13], entry[14]
    end
    C_Item = { GetItemInfo = GetItemInfo }
    function GetItemCount(itemID)
        local total = 0
        for _, slots in pairs(H.bags) do
            for _, slot in ipairs(slots) do
                if slot.itemID == itemID then total = total + slot.stackCount end
            end
        end
        return total
    end

    -- Taschen
    C_Container = {
        GetContainerNumSlots = function(bag)
            return H.bags[bag] and #H.bags[bag] or 0
        end,
        GetContainerItemInfo = function(bag, slot)
            return H.bags[bag] and H.bags[bag][slot] or nil
        end,
    }

    -- Berufe
    function GetNumSkillLines() return #H.skills end
    function GetSkillLineInfo(index)
        local entry = H.skills[index]
        if not entry then return nil end
        return entry[1], entry[2], nil, entry[3]
    end
    function IsPlayerSpell() return true end
    function GetSpellCooldown() return 0, 0, 1 end
    function GetSpellInfo(spellID) return "Zauber " .. tostring(spellID) end
    function GetNumTradeSkills() return 0 end
    function GetNumCrafts() return 0 end

    -- Quests
    C_QuestLog = { IsQuestFlaggedCompleted = function() return false end }
    function GetNumQuestLogEntries() return 0 end
    function GetQuestLogTitle() return nil end

    -- Karte
    C_Map = {
        GetBestMapForUnit = function() return H.mapID end,
        GetPlayerMapPosition = function(mapID, unit)
            if mapID ~= H.mapID then return nil end
            local pos = H.position
            return {
                GetXY = function() return pos.x, pos.y end,
                x = pos.x, y = pos.y,
            }
        end,
        GetMapInfo = function(mapID)
            if type(mapID) ~= "number" then return nil end
            if mapID <= 0 or mapID > 2000 then return nil end
            return { mapID = mapID, name = "Karte " .. mapID, mapType = 3 }
        end,
        GetWorldPosFromMapPos = function(mapID, pos)
            local x, y = pos.x or 0, pos.y or 0
            -- Ein sehr grobes, aber monotones Weltkoordinatensystem: 1 Karten-
            -- einheit = 4000 Yards. Damit werden Entfernungen vergleichbar,
            -- ohne echte Kartendaten zu behaupten.
            return mapID, { x = x * 4000, y = y * 4000 }
        end,
    }

    -- Auctionator
    Auctionator = {
        API = {
            v1 = {
                GetAuctionPriceByItemID = function(_, itemID)
                    return H.marketPrices[itemID]
                end,
                GetDisenchantPriceByItemLink = function(_, link)
                    return H.disenchantPrices[link]
                end,
                GetAuctionAgeByItemID = function(_, itemID)
                    return H.scanAge[itemID]
                end,
                RegisterForDBUpdate = function(callerID, callback)
                    assert(type(callerID) == "string" and callerID ~= "")
                    assert(type(callback) == "function")
                    H.dbUpdateCallbacks = H.dbUpdateCallbacks or {}
                    H.dbUpdateCallbacks[#H.dbUpdateCallbacks + 1] = callback
                end,
            },
        },
    }

    -- Auktionshaus-Browser (Classic-Signatur)
    function GetNumAuctionItems(list)
        if list ~= "list" then return 0, 0 end
        local entries = H.auctionListings[H.auctionQuery or -1] or {}
        return #entries, #entries
    end
    function GetAuctionItemInfo(list, index)
        if list ~= "list" then return nil end
        local entries = H.auctionListings[H.auctionQuery or -1] or {}
        local entry = entries[index]
        if not entry then return nil end
        local info = H.items[H.auctionQuery] or {}
        -- name, texture, count, quality, canUse, level, levelColHeader,
        -- minBid, minIncrement, buyoutPrice, bidAmount, highBidder,
        -- bidderFullName, owner, ...
        return info[1] or "?", info[10] or 0, entry.count or 1, info[3] or 1,
            true, 1, nil, entry.buyoutTotal or 0, 0, entry.buyoutTotal or 0,
            0, nil, nil, entry.owner or "Verkäufer"
    end
    function GetAuctionItemLink(list, index)
        if list ~= "list" then return nil end
        return "item:" .. tostring(H.auctionQuery)
    end
    function QueryAuctionItems() end
    function CalculateAuctionDeposit(runTime) return 300 * (runTime or 12) / 12 end
    function GetAuctionSellItemInfo() return H.sellSlotName, nil, H.sellSlotCount end
    function PostAuction() end

    -- Post
    function GetInboxNumItems() return #H.inbox end
    function GetInboxHeaderInfo(index)
        local mail = H.inbox[index]
        if not mail then return nil end
        return nil, nil, mail.sender or "Auktionshaus", mail.subject or "",
            mail.money or 0, 0, mail.daysLeft or 25, mail.hasItem or 0
    end
    function GetInboxInvoiceInfo(index)
        local mail = H.inbox[index]
        if not mail or not mail.invoice then return nil end
        local i = mail.invoice
        return i.invoiceType, i.itemName, i.playerName, i.bid, i.buyout,
            i.deposit, i.consignment
    end
    function GetInboxItemLink(index, slot)
        local mail = H.inbox[index]
        return mail and mail.itemLink or nil
    end
    function GetInboxItem(index, slot)
        local mail = H.inbox[index]
        if not mail then return nil end
        return mail.itemName, nil, nil, mail.itemCount or 1
    end

    -- Optionale Addons bleiben abwesend, solange ein Test sie nicht setzt.
    Syndicator = H.syndicator
    TSM_API = H.tsm
    TomTom = H.tomtom
end

-- ---------------------------------------------------------------------------
-- Addon laden
-- ---------------------------------------------------------------------------

-- Die Ladereihenfolge ist die der TOC. Sie wird beim Start gegen die TOC
-- geprueft (siehe tests/validate.mjs), damit kein Modul in den Tests laeuft,
-- das WoW nie laedt - und keines fehlt, das WoW laedt.
H.FILES = {
    "Constants.lua", "Core.lua",
    "Knowledge/Knowledge.lua", "Knowledge/Phases.lua", "Knowledge/Items.lua",
    "Knowledge/Recipes.lua", "Knowledge/Catalysts.lua", "Knowledge/Locations.lua", "Knowledge/FarmRoutes.lua",
    "Prices.lua", "Inventory.lua", "Advisor.lua", "Flips.lua", "Crafts.lua",
    "Market.lua", "Ledger.lua", "Opportunity.lua", "Future.lua", "Demand.lua", "Actionability.lua", "Capital.lua",
    "Execution.lua", "Route.lua", "Navigation.lua", "Farm.lua", "Income.lua", "Activity.lua", "Personal.lua",
    "Analytics.lua", "Calibration.lua", "Guide.lua",
    "Quests.lua", "Roadmap.lua", "UI.lua",
}

function H.loadAddon(files)
    local GCP = {}
    for _, file in ipairs(files or H.FILES) do
        local chunk, err = loadfile(file)
        assert(chunk, "Ladefehler in " .. file .. ": " .. tostring(err))
        chunk("GoldCopilot", GCP)
    end
    return GCP
end

-- Vollstaendiger Kaltstart: Umgebung, Addon, leere Datenbank.
function H.boot(files)
    H.install()
    local GCP = H.loadAddon(files)
    GoldCopilotDB = nil
    GCP:EnsureDB()
    return GCP
end

-- Setzt die simulierte Welt UND den Laufzeitzustand des Addons zurueck. Damit
-- laufen mehrere vollstaendige Sitzungen nacheinander in einem Lua-Zustand,
-- ohne dass eine die naechste beeinflusst - genau das braucht ein
-- End-to-End-Test.
function H.reset(GCP, options)
    options = options or {}
    H.clearBags()
    H.inbox = {}
    H.auctionListings = {}
    H.auctionQuery = nil
    H.timers = {}
    H.chat = {}
    H.money = options.money or 30000000
    H.realm = options.realm or "Testrealm"
    H.faction = options.faction or "Horde"
    H.zoneName = options.zone or "Höllenfeuerhalbinsel"
    H.mapID = options.mapID or 100
    H.position = { x = 0.5, y = 0.5 }
    H.facing = 0
    H.scanAge = {}
    H.trade = { partner = nil, targetMoney = 0, playerMoney = 0,
        targetItems = {}, playerItems = {} }

    -- Laufzeit-Caches der Module. Ein Cache, der eine Sitzung ueberlebt, waere
    -- in einem End-to-End-Test die haeufigste Fehlerquelle.
    GCP.Market.statsCache = {}
    GCP.Market.overviewCache = nil
    GCP.Market.trackedCache = nil
    GCP.Market.bytesCache = nil
    GCP.Market.lastRecordAt = nil
    GCP.Ledger.itemCache = {}
    GCP.Ledger.itemCacheRevision = nil
    GCP.Ledger.globalCache = {}
    GCP.Ledger.globalCacheRevision = nil
    GCP.Ledger.relistChains = {}
    GCP.Opportunity.cache = nil
    GCP.Future.itemCache = {}
    GCP.Future.itemCacheSignature = nil
    GCP.Future.graph = nil
    GCP.Capital.cache = nil
    GCP.Capital.cacheAt = nil
    GCP.Capital.cacheSignature = nil
    GCP.Guide.route = nil
    GCP.Guide.baseline = nil
    GCP.Guide.lastReplan = nil
    GCP.Guide.interrupt = nil
    GCP.Guide.lastInterruptAt = nil
    GCP.Farm.session = nil
    GCP.Income.context = nil
    GCP.Income.lastGold = nil
    GCP.Income.lastEnchantAt = nil
    GCP.Income.pendingTrade = nil
    GCP.Activity.pending = nil
    GCP.Navigation.current = nil
    GCP.Navigation.currentSpec = nil
    GCP.Navigation.lastUpdate = nil
    GCP.Analytics:Invalidate()
    if GCP.UI then
        GCP.UI.plannedRoute = nil
        GCP.UI.plannedProfile = nil
    end
    GCP.profileCache = nil

    if options.keepDatabase ~= true then
        GoldCopilotDB = nil
    end
    GCP:EnsureDB()
    return GCP
end

-- Ein kompletter Realm mit Historie, Rezepten und optional Handelsspur.
function H.seedRealm(GCP, options)
    options = options or {}
    for itemID, price in pairs(H.marketPrices) do
        H.seedHistory(GCP, itemID, price, options.days or 12,
            options.points or 24, options.wobble or 0.10)
    end
    if options.recipes ~= false then
        GCP:Profile().recipes = nil
        GCP.db.recipes = {
            ["Alchemie"] = {
                scannedAt = GCP:Today(),
                list = {
                    { name = "Urmacht", product = 23571, numMade = 1,
                      mats = { { 21884, 1 }, { 21885, 1 }, { 22451, 1 },
                               { 22452, 1 }, { 22457, 1 } },
                      hasCooldown = true },
                },
            },
        }
        GCP.Crafts.revision = (GCP.Crafts.revision or 0) + 1
    end
    GCP.Market:InvalidateCaches()
    GCP.Opportunity:Invalidate()
    GCP.Future:Invalidate()
    GCP.Capital:Invalidate()
end

-- ---------------------------------------------------------------------------
-- Simulationsbausteine
-- ---------------------------------------------------------------------------

-- Erzeugt eine Preishistorie: `points` Messpunkte ueber `days` Tage, mit
-- gleichmaessiger Schwankung um den Basispreis.
function H.seedHistory(GCP, itemID, basePrice, days, points, wobble)
    days = days or 10
    points = points or 20
    wobble = wobble or 0.08
    local start = H.now - days * 86400
    local step = (days * 86400) / points
    for index = 0, points - 1 do
        local stamp = math.floor(start + index * step)
        local factor = 1 + ((index % 4) - 1.5) * wobble
        GCP.Market:AddSnapshot(itemID, math.floor(basePrice * factor), stamp, "Auctionator")
    end
end

-- Erzeugt eine persoenliche Handelsspur: gekauft, eingestellt, verkauft.
function H.seedTrade(GCP, itemID, options)
    options = options or {}
    local quantity = options.quantity or 10
    local buyPrice = options.buyPrice or 1000
    local sellPrice = options.sellPrice or 1500
    local rounds = options.rounds or 6
    local holdHours = options.holdHours or 5
    local expiries = options.expiries or 0
    local base = options.startAt or (H.now - 20 * 86400)
    local store = GCP.Ledger:EnsureStore()
    for round = 1, rounds do
        local at = base + round * 2 * 86400
        if options.buy ~= false then
            GCP.Ledger:RecordPurchase({
                itemID = itemID, quantity = quantity, unitPrice = buyPrice, timestamp = at,
            })
        end
        GCP.Ledger:RecordAuctionPosted({
            itemID = itemID, quantity = quantity, unitPrice = sellPrice,
            deposit = 300, durationHours = 12, timestamp = at + 60,
        })
        -- Wie im echten Ablauf: Erst die offene Einstellung zuordnen, dann den
        -- Verkauf buchen. Sonst bliebe jede Einstellung offen und die
        -- Positionsrechnung saehe Auktionen, die laengst verkauft sind.
        local total = sellPrice * quantity
        local posting, quality = GCP.Ledger:MatchSale(store, itemID, total)
        GCP.Ledger:RecordSale({
            itemID = itemID, quantity = quantity, totalGross = total,
            source = "ah", timestamp = at + holdHours * 3600,
            holdHours = posting and holdHours or nil,
            matchQuality = quality,
        })
    end
    for round = 1, expiries do
        local at = base + (rounds + round) * 2 * 86400
        GCP.Ledger:RecordAuctionPosted({
            itemID = itemID, quantity = quantity, unitPrice = sellPrice,
            deposit = 300, durationHours = 12, timestamp = at,
        })
        GCP.Ledger:RecordAuctionExpired({
            itemID = itemID, quantity = quantity, timestamp = at + 48 * 3600,
        })
    end
end

-- Laesst eine Farmsitzung ueber `seconds` laufen und tickt dabei so oft, wie
-- es die Oberflaeche im Spiel auch taete. Ein einziger Sprung ueber Minuten
-- waere kein realistischer Ablauf - und wuerde von der Leerlaufpruefung zu
-- Recht verworfen.
function H.farmRun(GCP, seconds, options)
    options = options or {}
    local chunk = options.chunk or 60
    local elapsed = 0
    while elapsed < seconds do
        local step = math.min(chunk, seconds - elapsed)
        H.advance(step)
        elapsed = elapsed + step
        if options.itemID and options.perChunk then
            H.addBagItem(options.itemID, options.perChunk)
        end
        GCP.Farm:Tick()
        if not GCP.Farm:Current() then break end
    end
    return elapsed
end

-- Laesst eine offene Auktion stehen (fuer Positions- und Exposure-Tests).
function H.seedOpenAuction(GCP, itemID, quantity, unitPrice, at)
    GCP.Ledger:RecordAuctionPosted({
        itemID = itemID, quantity = quantity, unitPrice = unitPrice,
        deposit = 300, durationHours = 12, timestamp = at or (H.now - 3600),
    })
end

return H
