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
-- 2000 Gold. Vorher standen hier 10 Gold, und damit scheiterte jede Chance an
-- der Exposure-Grenze ("83 % des investierbaren Kapitals") - die Attrappe hat
-- nie eine Route zustande gebracht. Unbemerkt blieb das, weil die Guide-Tests
-- hinter "if StepCount() > 0" stehen und stillschweigend uebersprungen wurden,
-- und weil die Zentrale ohne Zuteilung ihren Leerzweig zeichnet: leere Texte,
-- ausgeblendete Mengenknoepfe, nichts zu pruefen. Ein Spieler, der sich nichts
-- leisten kann, ist der einzige Fall, den dieses Fenster nicht zeigen muss.
function GetMoney() return 20000000 end
function UnitLevel() return 70 end
function InCombatLockdown() return false end
function IsShiftKeyDown() return false end
-- ALT_DOWN steuert das Ablehnen per Alt+Rechtsklick (1.0.0-beta.4).
ALT_DOWN = false
function IsAltKeyDown() return ALT_DOWN end

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

-- Fontstrings tragen keine eigene Hoehe; der Client leitet sie aus der Schrift
-- ab. Fuer die Layoutpruefung wird sie hier genauso geschaetzt: Schriftgroesse
-- plus vier Pixel Zeilenluft. Das ist knapp genug, um Ueberlappungen zu finden,
-- und grosszuegig genug, um keine zu erfinden - mehrzeilige Texte bleiben
-- deshalb ausgenommen (siehe layout.extentOf).
local FONTSTRING_PADDING = 4

-- ---------------------------------------------------------------------------
-- TEXTBREITE (1.0.0-beta.9)
--
-- Die Attrappe kennt FRIZQT__.TTF nicht und kann eine Textbreite deshalb nicht
-- ausmessen. Geschaetzt wird trotzdem - aber ausdruecklich als UNTERGRENZE:
-- "so breit ist der Text mindestens".
--
-- Das ist der ganze Trick. Aus einer Schaetzung, die in beide Richtungen
-- danebenliegen kann, wird damit eine belastbare Aussage: Wer selbst bei der
-- schmalsten denkbaren Darstellung ueberlappt oder aus dem Rahmen faellt, tut
-- es im Spiel erst recht. Umgekehrt bleibt manches unentdeckt - das ist der
-- Preis dafuer, dass jede Meldung stimmt. Ein Test, der gelegentlich grundlos
-- ausschlaegt, wird abgeschaltet und findet dann gar nichts mehr.
--
-- Anteile der Schriftgroesse je Zeichen. Bewusst tief angesetzt: Die
-- tatsaechliche mittlere Zeichenbreite dieser Schrift liegt bei etwa 0,5.
local NARROW_CHARS = "[ilIjtfr%.,:;!|'%(%)%[%]%s]"
local NARROW_ADVANCE = 0.20
local WIDE_ADVANCE = 0.35

-- Was vom Text uebrig bleibt, wenn man die Steuerzeichen des Clients abzieht.
-- Farbcodes (|cffd9a834 ... |r) und Hyperlink-Klammern rendern nichts; sie
-- machen die Zeichenkette laenger, den Text aber nicht breiter. Der
-- Verkaufen-Tab und die Statuszeilen stecken voller solcher Codes - sie
-- mitzuzaehlen waere keine Untergrenze mehr, sondern eine Erfindung.
local function visibleText(text)
    if type(text) ~= "string" then return "" end
    local visible = text
    visible = visible:gsub("|c%x%x%x%x%x%x%x%x", "")
    visible = visible:gsub("|r", "")
    visible = visible:gsub("|H.-|h", "")
    visible = visible:gsub("|h", "")
    -- Ein eingebettetes Symbol ist etwa quadratisch; es zaehlt als ein Gevierte.
    visible = visible:gsub("|T.-|t", "MM")
    return visible
end

local function textWidthLowerBound(text, fontSize)
    local visible = visibleText(text)
    if visible == "" then return 0 end
    fontSize = tonumber(fontSize) or 12
    -- Fortsetzungsbytes von UTF-8 wegwerfen, damit ein Umlaut ein Zeichen ist
    -- und nicht zwei. #text zaehlt Bytes - genau daran hat die alte Schaetzung
    -- jeden deutschen Text um ein Fuenftel zu breit gemacht.
    visible = visible:gsub("[\128-\191]", "")
    local width = 0
    for index = 1, #visible do
        local char = visible:sub(index, index)
        width = width + fontSize
            * (char:match(NARROW_CHARS) and NARROW_ADVANCE or WIDE_ADVANCE)
    end
    return width
end

local function newFontString(parent)
    local fs = { _text = "", _shown = true, _fontSize = 12, _parent = parent }
    function fs:SetFont(font, size) assert(type(font) == "string", "SetFont ohne Font")
        assert(type(size) == "number", "SetFont ohne Groesse")
        self._fontSize = size
        self._height = size + FONTSTRING_PADDING
    end
    function fs:SetPoint(point, ...)
        local relativeTo, relativePoint, x, y = ...
        if type(relativeTo) == "number" then
            relativeTo, relativePoint, x, y = self._parent, point, relativeTo, relativePoint
        end
        self._points = self._points or {}
        self._points[#self._points + 1] = {
            point = point, relativeTo = relativeTo,
            relativePoint = relativePoint or point,
            x = tonumber(x) or 0, y = tonumber(y) or 0,
        }
    end
    function fs:ClearAllPoints() self._points = nil end
    function fs:SetWidth(width) self._width = width end
    function fs:SetWordWrap(enabled) self._wordWrap = enabled and true or false end
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
    function fs:GetStringWidth()
        return textWidthLowerBound(self._text, self._fontSize)
    end
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
function frameMethods.CreateFontString(self) return newFontString(self) end
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

-- Anker mitschreiben (1.0.0-beta.6). Die Attrappe hat SetPoint bisher
-- verschluckt, und damit war jede Aussage ueber Geometrie unmoeglich - genau
-- deshalb konnte eine Knopfreihe im Command Center auf der Zeile darunter
-- landen, ohne dass ein Test das gemerkt haette. Aufgezeichnet wird nur, was
-- hier gebraucht wird: Ankerpunkt, Bezugsrahmen und der senkrechte Versatz.
function frameMethods.SetPoint(self, point, ...)
    local relativeTo, relativePoint, x, y = ...
    if type(relativeTo) == "number" then
        -- Kurzform SetPoint(point, x, y): Bezug ist der Elternrahmen.
        relativeTo, relativePoint, x, y = self._parent, point, relativeTo, relativePoint
    end
    self._points = self._points or {}
    self._points[#self._points + 1] = {
        point = point, relativeTo = relativeTo,
        relativePoint = relativePoint or point,
        x = tonumber(x) or 0, y = tonumber(y) or 0,
    }
end
function frameMethods.ClearAllPoints(self) self._points = nil end

-- Ein frisch angelegter Rahmen ist im Client SICHTBAR; versteckt wird er erst
-- durch ein ausdrueckliches Hide - und genau so macht es UI.lua (Hauptfenster,
-- Guide, Optionenbereich, Command Panel rufen es auf). Die Attrappe hat ihn bis
-- 1.0.0-beta.9 versteckt angelegt. Das fiel nie auf, weil niemand nach der
-- Sichtbarkeit gefragt hat; die Layoutpruefung tut das, und mit dem falschen
-- Standardwert hat sie stillschweigend fast alles uebersprungen - gruene
-- Meldungen, die nichts angesehen hatten.
function CreateFrame(_, _, parent)
    return setmetatable({ _shown = true, _scripts = {}, _parent = parent }, frameMeta)
end

UIParent = CreateFrame("Frame")

-- ---------------------------------------------------------------------------
-- LAYOUTPRUEFUNG (1.0.0-beta.8)
--
-- Die Attrappe schreibt Anker mit; hier werden sie in Rechtecke aufgeloest.
-- Gemessen wird in Pixeln vom linken oberen Rand des Behaelters, nach rechts
-- und nach UNTEN wachsend - anders als in WoW, wo y nach oben zeigt. Der
-- Vorzeichenwechsel passiert genau einmal, beim Auswerten des Versatzes.
--
-- Warum ueberhaupt: Bis 1.0.0-beta.6 hat die Attrappe SetPoint verschluckt.
-- Damit war jede Aussage ueber Geometrie unmoeglich, und drei Layoutfehler in
-- Folge sind erst dem Nutzer im Spiel aufgefallen - ueberlappende Symbole, ein
-- zu schmales Guide-Fenster und eine Knopfreihe, die aus ihrem Block fiel.
-- ---------------------------------------------------------------------------

local layout = {}

-- Ausgeblendetes zaehlt nicht. Mehrere Elemente teilen sich absichtlich
-- dieselbe Flaeche und schliessen sich gegenseitig aus - im Guide etwa "Neue
-- Route planen", das genau dort steht, wo waehrend der Route die Knopfreihe
-- liegt. Ohne diese Unterscheidung meldet die Pruefung Absicht als Fehler, und
-- das ist der schnellste Weg, sie unglaubwuerdig zu machen.
local function isVisible(widget)
    return type(widget) == "table" and widget._shown ~= false
end

-- Wo liegt ein Ankerpunkt innerhalb eines Elements? Rueckgabe: Anteil der
-- Breite und der Hoehe (0 = links/oben, 1 = rechts/unten).
local function anchorFractions(point)
    point = tostring(point or "CENTER"):upper()
    local fx, fy = 0.5, 0.5
    if point:find("LEFT") then fx = 0 elseif point:find("RIGHT") then fx = 1 end
    if point:find("TOP") then fy = 0 elseif point:find("BOTTOM") then fy = 1 end
    return fx, fy
end

-- Breite und Hoehe eines Elements. Die Bloecke dieses Addons setzen fast nie
-- SetSize, sondern spannen sich zwischen zwei gegenueberliegenden Ankern auf
-- ("TOPLEFT beim Elternrahmen, RIGHT am Elternrahmen"). Ohne diese Aufloesung
-- waere jede waagerechte Aussage ueber sie wertlos - und in der ersten Fassung
-- dieser Pruefung waren es prompt sieben Fehlalarme.
--
-- Aufgeloest wird nur der Fall, den es hier gibt: zwei Anker an DENSELBEN
-- Bezugsrahmen mit gegenueberliegenden Kanten. Alles andere ergibt nil, und nil
-- heisst "keine Aussage".
local function oppositeSpan(widget, axis, depth)
    local points = widget._points
    if not points or #points < 2 then return nil end
    local key = axis == "x" and "x" or "y"
    local low, high, reference
    for _, point in ipairs(points) do
        local fx, fy = anchorFractions(point.relativePoint)
        local fraction = axis == "x" and fx or fy
        if reference == nil then reference = point.relativeTo
        elseif reference ~= point.relativeTo then return nil end
        if fraction == 0 then low = point
        elseif fraction == 1 then high = point end
    end
    if not (low and high and reference) then return nil end
    local span = axis == "x" and layout.widthOf(reference, depth)
        or layout.heightOf(reference, depth)
    if not span then return nil end
    -- Bei y zeigt der Versatz nach oben, bei x nach rechts.
    local sign = axis == "x" and 1 or -1
    return span - sign * (low[key] or 0) + sign * (high[key] or 0)
end

function layout.widthOf(widget, depth)
    depth = (depth or 0) + 1
    if type(widget) ~= "table" or depth > 12 then return nil end
    if widget._width then return widget._width end
    local span = oppositeSpan(widget, "x", depth)
    if span then return span end
    -- Ein Text ohne feste Breite und ohne zweiten Anker ist so breit wie sein
    -- Inhalt. Gemessen wird die Untergrenze; siehe textWidthLowerBound.
    if widget._text ~= nil then
        return widget:GetStringWidth(), true
    end
    return nil
end

function layout.heightOf(widget, depth)
    depth = (depth or 0) + 1
    if type(widget) ~= "table" or depth > 12 then return nil end
    if widget._height then return widget._height end
    return oppositeSpan(widget, "y", depth)
end

-- Rechteck eines Elements in den Koordinaten von container, oder nil, wenn die
-- Ankerkette sich nicht aufloesen laesst. nil heisst ausdruecklich "keine
-- Aussage" und niemals "in Ordnung": Ungeprueftes wird uebersprungen, nicht
-- durchgewunken.
function layout.extentOf(widget, container, depth)
    depth = (depth or 0) + 1
    local function boxOf(frame)
        return { left = 0, top = 0,
            right = layout.widthOf(frame), bottom = layout.heightOf(frame) }
    end
    if widget == container then return boxOf(container) end
    if depth > 12 or type(widget) ~= "table" then return nil end
    local point = widget._points and widget._points[1]
    if not point then return nil end

    local base
    local relativeTo = point.relativeTo
    if relativeTo == nil or relativeTo == container then
        base = boxOf(container)
    else
        base = layout.extentOf(relativeTo, container, depth)
    end
    if not base then return nil end
    -- Ohne bekannte Ausdehnung des Bezugs laesst sich an dessen ferner Kante
    -- nichts messen. Lieber keine Aussage als eine falsche.
    local rfxCheck, rfyCheck = anchorFractions(point.relativePoint)
    if (rfxCheck > 0 and not base.right) or (rfyCheck > 0 and not base.bottom) then
        return nil
    end

    local rfx, rfy = rfxCheck, rfyCheck
    local anchorX = base.left + ((base.right or base.left) - base.left) * rfx
        + (point.x or 0)
    -- Hier der einzige Vorzeichenwechsel: In WoW zeigt y nach oben.
    local anchorY = base.top + ((base.bottom or base.top) - base.top) * rfy
        - (point.y or 0)

    local width, height = layout.widthOf(widget), layout.heightOf(widget)
    local fx, fy = anchorFractions(point.point)
    local box = { top = anchorY - (height or 0) * fy, bottom = nil,
        left = anchorX - (width or 0) * fx, right = nil }
    box.bottom = height and (box.top + height) or nil
    box.right = width and (box.left + width) or nil
    return box
end

-- Prueft, ob jedes benannte Element eines Behaelters innerhalb seiner Grenzen
-- liegt. Mehrzeilige Texte bleiben aussen vor: Ihre Hoehe haengt am Umbruch,
-- den die Attrappe nicht kennt, und ein geschaetzter Wert wuerde Fehlalarme
-- erzeugen statt Fehler zu finden.
function layout.checkContainment(container, label, report)
    local height = layout.heightOf(container)
    local width = layout.widthOf(container)
    for name, widget in pairs(container) do
        local isWidget = type(widget) == "table" and widget._points
            and type(name) == "string" and not name:find("^_")
        if isWidget and not widget._wordWrap and isVisible(widget) then
            local box = layout.extentOf(widget, container)
            if box then
                if height and box.bottom and box.bottom > height + 0.5 then
                    report(false, string.format(
                        "%s.%s fällt unten aus dem Rahmen (%d von %d)",
                        label, name, math.floor(box.bottom), math.floor(height)))
                elseif box.top < -0.5 then
                    report(false, string.format("%s.%s liegt über dem Rahmen (%d)",
                        label, name, math.floor(box.top)))
                elseif width and box.right and box.right > width + 0.5 then
                    report(false, string.format(
                        "%s.%s fällt rechts aus dem Rahmen (%d von %d)",
                        label, name, math.floor(box.right), math.floor(width)))
                elseif width and box.left < -0.5 then
                    report(false, string.format("%s.%s liegt links vom Rahmen (%d)",
                        label, name, math.floor(box.left)))
                else
                    report(true, label .. "." .. name .. " liegt im Rahmen")
                end
            end
        end
    end
end

-- Ueberlappung zweier Rechtecke.
--
-- Texte duerfen seit 1.0.0-beta.9 mitgeprueft werden, weil ihre Breite als
-- Untergrenze geschaetzt wird: Was sich schon bei der schmalsten denkbaren
-- Darstellung ueberschneidet, ueberschneidet sich im Spiel erst recht. Die
-- Hoehe ist ebenfalls knapp angesetzt (Schriftgroesse plus vier Pixel).
--
-- Deshalb gilt: Eine Meldung ist ein Fund, kein Verdacht. Ausbleiben ist
-- dagegen kein Freispruch - fuer Texte ist es nur "nicht offensichtlich
-- falsch".
function layout.checkOverlap(container, label, names, report)
    for outer = 1, #names do
        for inner = outer + 1, #names do
            local first, second = container[names[outer]], container[names[inner]]
            local a = layout.extentOf(first, container)
            local b = layout.extentOf(second, container)
            local measurable = a and b and a.right and b.right
                and a.bottom and b.bottom
                -- Mehrzeiliges bleibt aussen vor: Die Zeilenzahl kennt die
                -- Attrappe nicht, also auch nicht die wahre Hoehe.
                and not (first._wordWrap or second._wordWrap)
                and isVisible(first) and isVisible(second)
            if measurable then
                local apart = a.right <= b.left + 0.5 or b.right <= a.left + 0.5
                    or a.bottom <= b.top + 0.5 or b.bottom <= a.top + 0.5
                report(apart, string.format(
                    "%s: %s und %s überlappen sich nicht", label,
                    names[outer], names[inner]))
            end
        end
    end
end

-- Eine Gruppe von Elementen, die im Betrieb GEMEINSAM erscheinen, gegeneinander
-- pruefen - unabhaengig davon, ob sie beim Testlauf gerade sichtbar sind.
--
-- Noetig, weil das Guide-Fenster in dieser Attrappe nie eine echte Route zeigt:
-- Ohne diesen Weg blieben seine Knopfreihen ungeprueft, und die Pruefung waere
-- gruen, ohne etwas angesehen zu haben. Die Sichtbarkeit wird darum kurz
-- gesetzt und danach wiederhergestellt - gefragt ist hier die Geometrie, nicht
-- der Zustand.
function layout.checkGroup(container, label, names, report)
    local restore = {}
    for _, name in ipairs(names) do
        local widget = container[name]
        if type(widget) == "table" then
            restore[name] = widget._shown
            widget._shown = true
        end
    end
    layout.checkOverlap(container, label, names, report)
    for name, shown in pairs(restore) do
        container[name]._shown = shown
    end
end

-- Alle benannten Elemente eines Behaelters paarweise gegeneinander. Bequemer
-- als eine Liste von Hand - und sie veraltet nicht, sobald jemand ein Element
-- hinzufuegt, was bei diesem Fenster regelmaessig vorkommt.
function layout.checkAllOverlaps(container, label, report)
    local names = {}
    for name, widget in pairs(container) do
        if type(name) == "string" and not name:find("^_")
            and type(widget) == "table" and widget._points then
            names[#names + 1] = name
        end
    end
    table.sort(names)
    layout.checkOverlap(container, label, names, report)
end

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

-- Preise in der Groessenordnung eines echten Realms. Vorher standen hier
-- Betraege um 100 bis 1300 Kupfer; damit blieb jede Zuteilung unter der
-- Mindestgroesse von 1 Gold (CAPITAL.ALLOCATOR.MIN_ALLOCATION) und die
-- Attrappe brachte nie eine Route zustande. Der Zusammenhang ist der
-- Stueckzahl-Deckel aus 1.0.0-beta.3: fuenf Stueck ohne eigene Verkaufsdaten
-- mal 1000 Kupfer sind eben keine Position, die eine Route rechtfertigt.
local marketPrices = {
    [21884] = 130000, [22574] = 10000, [23425] = 50000, [22785] = 800,
    [10938] = 10000, [10939] = 40000, [60001] = 8000, [60002] = 2000,
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
    "Constants.lua", "Core.lua",
    "Knowledge/Knowledge.lua", "Knowledge/Phases.lua", "Knowledge/Items.lua",
    "Knowledge/Recipes.lua", "Knowledge/Catalysts.lua", "Knowledge/Locations.lua", "Knowledge/FarmRoutes.lua",
    "Prices.lua", "Inventory.lua", "Advisor.lua",
    "Flips.lua", "Crafts.lua", "Market.lua", "Ledger.lua", "Opportunity.lua", "Future.lua", "Demand.lua", "Actionability.lua", "Capital.lua", "Execution.lua", "Route.lua", "Navigation.lua", "Farm.lua", "Income.lua", "Materials.lua", "Activity.lua", "Personal.lua",
    "Analytics.lua", "Calibration.lua", "Recommendation.lua", "Guide.lua",
    "Quests.lua", "Roadmap.lua", "UI.lua",
}) do
    local chunk, err = loadfile(file)
    assert(chunk, "Ladefehler in " .. file .. ": " .. tostring(err))
    chunk("GoldCopilot", GCP)
end

GCP:EnsureDB()

local TABS = { "zentrale", "route", "today", "sell", "flips", "crafts", "market",
    "chancen", "zukunft", "handel", "options" }

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
    -- Nur sichtbare Zeilen: Der Zeilen-Pool traegt hinter der letzten Zeile noch
    -- die Zahlen des zuletzt gezeichneten Tabs.
    local score = line:IsShown() and tonumber(line.value:GetText() or "") or nil
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

-- --- Chancen-Tab ------------------------------------------------------------

-- Wenn der Filter alles wegnimmt, muss das Fenster trotzdem etwas
-- Verstaendliches zeichnen. Der Zustand wird hier ausdruecklich hergestellt -
-- vorher hing er daran, dass die Attrappe nur Chancen im Kupferbereich kannte,
-- und zerbrach in dem Moment, in dem sie realistische Preise bekam. Ein Test,
-- der einen Zustand braucht, soll ihn herstellen und nicht hoffen.
local savedMinProfit = GCP.db.options.opportunityMinProfit
GCP.db.options.opportunityMinProfit = 100000000     -- 10.000 g
GCP.Opportunity:Invalidate()
GCP.UI:SelectTab("chancen")
local filteredSummary = GCP.UI.frame.summary:GetText()
expect(filteredSummary:find("Chance") ~= nil,
    "Der Chancen-Tab zeigt auch mit leerer Liste eine Kopfzeile")
local filteredText = {}
for _, line in ipairs(GCP.UI.rows) do
    filteredText[#filteredText + 1] = line.text:GetText() or ""
end
expect(table.concat(filteredText, "\n"):find("Mindestprofit") ~= nil,
    "Ausgefilterte Chancen werden als Filterergebnis erklärt, nicht verschwiegen")
GCP.db.options.opportunityMinProfit = savedMinProfit

-- Ohne Filter bleiben die Conversion-Chancen der Attrappe stehen.
GCP.db.options.opportunityMinProfit = 0
GCP.db.options.opportunityMinROI = 0
GCP.Opportunity:Invalidate()
GCP.UI:SelectTab("chancen")

local oppHead = GCP.UI.rows[1]
expectEqual(oppHead.value:GetText(), "SCORE", "Spaltenkopf Score")
expectEqual(oppHead.typeText:GetText(), "TYP", "Spaltenkopf Typ")
expectEqual(oppHead.text:GetText(), "AKTION", "Spaltenkopf Aktion")
expectEqual(oppHead.cols[1]:GetText(), "LIQ.", "Spaltenkopf Liquidität")
expectEqual(oppHead.cols[2]:GetText(), "ROI", "Spaltenkopf ROI")
expectEqual(oppHead.cols[3]:GetText(), "PROFIT", "Spaltenkopf Profit")
expectEqual(oppHead.cols[4]:GetText(), "KAPITAL", "Spaltenkopf Kapital")

local oppSummary = GCP.UI.frame.summary:GetText()
expect(oppSummary:find("Gold Copilot hat") ~= nil,
    "Die Kopfzeile nennt die Zahl der gefundenen Chancen")
expect(oppSummary:find("KAUF") == nil and oppSummary:find("kaufen!") == nil,
    "Die Kopfzeile schreit nicht \"kaufen\"")

local oppRow = GCP.UI.rows[2]
expect(oppRow ~= nil, "Der Chancen-Tab erzeugt Datenzeilen")
expect(tonumber(oppRow.value:GetText()) ~= nil, "Die Score-Spalte trägt eine Zahl")
expect(oppRow.typeText:GetText() ~= "", "Die Typ-Spalte ist gefüllt")
expect(oppRow.text:GetText() ~= "", "Die Aktion ist benannt")
for column = 1, 3 do
    expect(oppRow.cols[column]:GetText() ~= "",
        string.format("Spalte %d der Chancenzeile ist gefüllt", column))
end
expect(oppRow.pill:IsShown(), "Die Einordnung steht als eigenes Etikett daneben")

local oppBreakdown = table.concat(oppRow.data.breakdown, "\n")
for _, needle in ipairs({
    "Kapitaleinsatz:", "Erlös netto:", "Theoretischer Gewinn:", "ROI:",
    "Opportunity Score:", "Confidence:",
}) do
    expect(oppBreakdown:find(needle, 1, true) ~= nil,
        "Der Tooltip nennt \"" .. needle .. "\"")
end
expect(oppBreakdown:find("Liquidität unbekannt", 1, true) ~= nil,
    "Ohne eigene Verkäufe sagt der Tooltip ausdrücklich \"unbekannt\"")
expect(oppBreakdown:find("PROFIT VELOCITY", 1, true) == nil,
    "...und zeigt keine Profit Velocity, die es nicht gibt")
expect(GCP.UI.frame.summary:GetText():find("Liquidität unbekannt", 1, true) ~= nil,
    "Die Kopfzeile des Chancen-Tabs sagt es ebenfalls")
expectEqual(oppRow.cols[1]:GetText(), "–",
    "Die Liquiditätsspalte trägt einen Strich statt einer erfundenen Zahl")
expect(oppBreakdown:find("keine Zusage", 1, true) ~= nil,
    "Der Tooltip verspricht ausdrücklich keinen Gewinn")

-- Sortierung: der Score faellt von oben nach unten.
local previousOpportunity = nil
for index = 2, #GCP.UI.rows do
    local line = GCP.UI.rows[index]
    -- Nur sichtbare Zeilen: Der Zeilen-Pool traegt hinter der letzten Zeile
    -- noch die Beschriftung des zuletzt gezeichneten Tabs.
    local score = line:IsShown() and tonumber(line.value:GetText() or "") or nil
    if score then
        if previousOpportunity then
            expect(score <= previousOpportunity, "Der Chancen-Tab sortiert nach Score absteigend")
        end
        previousOpportunity = score
    end
end

-- Rechtsklick nimmt in die Beobachtung auf und wieder heraus.
local watchedItem = oppRow.data.watchable
expect(watchedItem ~= nil, "Eine Chancenzeile lässt sich beobachten")
expectEqual(GCP.Market:IsWatched(watchedItem), false, "Vorher ist sie es nicht")
expect(pcall(oppRow:GetScript("OnClick"), oppRow, "RightButton"),
    "Rechtsklick auf eine Chancenzeile")
expectEqual(GCP.Market:IsWatched(watchedItem), true,
    "Rechtsklick nimmt das Item zur Beobachtung auf")
expect(GCP.UI.frame.watchButton.label:GetText():find("1") ~= nil,
    "Der Knopf zeigt die Zahl der beobachteten Items")

GCP.UI:SelectTab("chancen")
GCP.UI.onlyWatched = true
GCP.UI:Refresh()
for index = 2, #GCP.UI.rows do
    local line = GCP.UI.rows[index]
    if line:IsShown() and line.data and line.data.watchable then
        expectEqual(GCP.Market:IsWatched(line.data.watchable), true,
            "Die Beobachtungsansicht zeigt nur beobachtete Items")
    end
end
GCP.UI.onlyWatched = false

expect(pcall(oppRow:GetScript("OnEnter"), oppRow), "Tooltip einer Chancenzeile öffnet")
expect(pcall(oppRow:GetScript("OnLeave"), oppRow), "Tooltip einer Chancenzeile schließt")
expect(pcall(oppRow:GetScript("OnClick"), oppRow, "RightButton"),
    "Rechtsklick nimmt das Item wieder heraus")
expectEqual(GCP.Market:IsWatched(watchedItem), false, "...und danach ist es das auch")

-- --- Ablehnen per Alt+Rechtsklick (1.0.0-beta.4) ---------------------------
--
-- Die Antwort auf "der Guide schlaegt immer dasselbe vor": Ohne eine
-- Moeglichkeit abzulehnen hat der Planer bei gleicher Datenlage keine andere
-- Wahl. Geprueft wird, dass Alt die Watchlist NICHT anfasst - beide liegen auf
-- derselben Maustaste.
local rejectItem = oppRow.data and oppRow.data.rejectable
expect(rejectItem ~= nil, "Eine Chancenzeile laesst sich ablehnen")
local watchedBefore = GCP.Market:IsWatched(rejectItem)

ALT_DOWN = true
expect(pcall(oppRow:GetScript("OnClick"), oppRow, "RightButton"),
    "Alt + Rechtsklick auf eine Chancenzeile")
expectEqual(GCP.db.options.rejected[rejectItem], true,
    "...lehnt das Item ab")
expectEqual(GCP.Market:IsWatched(rejectItem), watchedBefore,
    "...und fasst die Beobachtung ausdruecklich nicht an")
ALT_DOWN = false

GCP.Opportunity:Invalidate()
local afterReject = GCP.Opportunity:BuildReport(true)
local stillThere = false
for _, opportunity in ipairs(afterReject.opportunities) do
    if opportunity.itemID == rejectItem then stillThere = true end
end
expectEqual(stillThere, false, "Ein abgelehntes Item taucht in keiner Chance mehr auf")
expect(afterReject.hiddenByIgnore >= 1, "...und wird als abgelehnt gezaehlt")

-- Zuruecknehmen ueber die Funktion statt ueber die Zeile: Nach dem Ablehnen
-- rendert die Liste neu, und der Zeilen-Pool vergibt dieselbe Zeile an das
-- naechste Item. Ein zweiter Klick auf oppRow traefe damit etwas anderes.
GCP.UI:ToggleRejected(rejectItem)
expectEqual(GCP.db.options.rejected[rejectItem], nil,
    "Ablehnen ist ein Schalter, keine Einbahnstrasse")
GCP.Opportunity:Invalidate()
local afterUndo = GCP.Opportunity:BuildReport(true)
local back = false
for _, opportunity in ipairs(afterUndo.opportunities) do
    if opportunity.itemID == rejectItem then back = true end
end
expectEqual(back, true, "...und danach steht die Chance wieder in der Liste")

-- Der Markt-Tab kann dasselbe.
GCP.UI:SelectTab("market")
local marketRow = GCP.UI.rows[2]
expect(marketRow.data.watchable ~= nil, "Auch eine Marktzeile lässt sich beobachten")
expect(pcall(marketRow:GetScript("OnClick"), marketRow, "RightButton"),
    "Rechtsklick auf eine Marktzeile")
expectEqual(GCP.Market:IsWatched(marketRow.data.watchable), true,
    "Rechtsklick im Markt-Tab nimmt zur Beobachtung auf")
GCP.Market:RemoveWatchItem(marketRow.data.watchable)

-- Optionen: die neuen Chancen-Filter sind da und getrennt vom Mindestgewinn.
GCP.db.options.minRoadmapValue = 50000
GCP.UI:SelectTab("options")
local panel = GCP.UI.frame.optionsPanel
expect(panel.oppProfitButtons ~= nil, "Die Optionen kennen den Mindestprofit der Chancen")
expect(panel.oppROIButtons ~= nil, "Die Optionen kennen den Mindest-ROI der Chancen")
expect(panel.oppProfitButtons[500000] ~= nil, "Es gibt eine 50-g-Stufe")
expect(panel.oppROIButtons[0.30] ~= nil, "Es gibt eine 30-%-Stufe")
expect(pcall(panel.oppProfitButtons[100000]:GetScript("OnClick")),
    "Ein Klick auf den Mindestprofit der Chancen")
expectEqual(GCP.db.options.opportunityMinProfit, 100000, "...setzt genau diese Option")
expectEqual(GCP.db.options.minRoadmapValue, 50000,
    "...und lässt den Mindestgewinn des Tagesplans in Ruhe")
expect(pcall(panel.oppROIButtons[0.20]:GetScript("OnClick")),
    "Ein Klick auf den Mindest-ROI der Chancen")
expectEqual(GCP.db.options.opportunityMinROI, 0.20, "...setzt genau diese Option")
GCP.db.options.opportunityMinProfit = 0
GCP.db.options.opportunityMinROI = 0

-- --- Zukunft-Tab ------------------------------------------------------------

-- Die Uhr wird relativ zum Phase-3-Termin gestellt: So ist der Abstand exakt
-- zwoelf Tage, egal in welcher Zeitzone der Test laeuft.
local phase3 = GCP.Knowledge:GetPhase("phase3")
mockNow = phase3.release - 12 * 86400 - 3600
GCP.Market:InvalidateCaches()
GCP.Future:Invalidate()
GCP.UI:SelectTab("zukunft")

local futureHead = GCP.UI.rows[1]
expect((futureHead.text:GetText() or ""):find("Nächster bekannter Catalyst") ~= nil,
    "Der Zukunft-Tab beginnt mit dem nächsten bekannten Catalyst")

local futureText = {}
for _, line in ipairs(GCP.UI.rows) do
    if line:IsShown() then futureText[#futureText + 1] = line.text:GetText() or "" end
end
futureText = table.concat(futureText, "\n")
expect(futureText:find("Schwarzer Tempel") ~= nil, "Die nächste Phase wird benannt")
expect(futureText:find("Illidan") ~= nil, "Ihr Inhalt steht darunter")
expect(futureText:find("Wissensstand") ~= nil, "Der Wissensstand steht sichtbar dabei")
expect(GCP.UI.rows[2].value:GetText() == "12 T",
    "Die Tage bis zum Termin stehen an der Phase")

-- Kopfzeile der Tabelle.
local futureTableHead = nil
for index, line in ipairs(GCP.UI.rows) do
    if line:IsShown() and (line.text:GetText() or ""):find("TOP FUTURE") then
        futureTableHead = index
        break
    end
end
expect(futureTableHead ~= nil, "Die Tabelle hat eine eigene Kopfzeile")
local futureCaptions = GCP.UI.rows[futureTableHead]
expectEqual(futureCaptions.value:GetText(), "SIGNAL", "Spaltenkopf Signal")
expectEqual(futureCaptions.cols[1]:GetText(), "CATALYST", "Spaltenkopf Catalyst")
expectEqual(futureCaptions.cols[2]:GetText(), "HYPE", "Spaltenkopf Hype")
expectEqual(futureCaptions.cols[3]:GetText(), "DEMAND", "Spaltenkopf Demand")
expectEqual(futureCaptions.cols[4]:GetText(), "MARKT", "Spaltenkopf Markt")

local futureRow = GCP.UI.rows[futureTableHead + 1]
expect(futureRow ~= nil and futureRow:IsShown(), "Der Zukunft-Tab erzeugt Datenzeilen")
expect(futureRow.text:GetText() ~= "", "Die Zeile nennt das Item")
expect(tonumber(futureRow.cols[3]:GetText()) ~= nil, "Die Demand-Spalte trägt eine Zahl")
expect(futureRow.cols[1]:GetText() ~= "", "Die Catalyst-Spalte ist gefüllt")
expect(futureRow.value:GetText() ~= "", "Die Signal-Spalte ist gefüllt")

local futureBreak = table.concat(futureRow.data.breakdown, "\n")
for _, needle in ipairs({
    "Aktueller Realm-Preis:", "7d Median:", "30d Median:", "Market Score:",
    "FUTURE DEMAND", "Catalysts:", "HYPE", "SIGNAL", "Wissensstand:",
}) do
    expect(futureBreak:find(needle, 1, true) ~= nil,
        "Der Tooltip nennt \"" .. needle .. "\"")
end
expect(futureBreak:find("keine Preisgarantie", 1, true) ~= nil,
    "Der Tooltip sagt ausdrücklich, dass er nichts garantiert")
expect(futureBreak:find("(Modell)", 1, true) ~= nil,
    "Modellwerte sind als solche gekennzeichnet")
expect(futureBreak:find("KAUFEN", 1, true) == nil, "Nirgends steht \"KAUFEN\"")

-- Sortierung: das Signal faellt von oben nach unten.
local previousSignal = nil
for index = futureTableHead + 1, #GCP.UI.rows do
    local line = GCP.UI.rows[index]
    local score = line:IsShown() and tonumber(line.value:GetText() or "") or nil
    if score then
        if previousSignal then
            expect(score <= previousSignal, "Der Zukunft-Tab sortiert nach Signal absteigend")
        end
        previousSignal = score
    end
end

-- Rechtsklick nimmt mit These in die Beobachtung auf.
GCP:Profile().watchlist = {}
local futureItem = futureRow.data.watchable
expect(futureItem ~= nil, "Eine Zukunftszeile lässt sich beobachten")
expect(pcall(futureRow:GetScript("OnClick"), futureRow, "RightButton"),
    "Rechtsklick auf eine Zukunftszeile")
expectEqual(GCP.Market:IsWatched(futureItem), true, "Das Item ist danach beobachtet")
expectEqual(GCP.Market:GetWatchEntry(futureItem).reason, "future",
    "...mit der Zukunft als Grund")
expectEqual(GCP.Market:GetWatchEntry(futureItem).phase, "phase3",
    "...und der Phase als These")
expect(pcall(futureRow:GetScript("OnEnter"), futureRow), "Tooltip einer Zukunftszeile öffnet")
expect(pcall(futureRow:GetScript("OnLeave"), futureRow), "Tooltip einer Zukunftszeile schließt")
GCP:Profile().watchlist = {}

-- Eine Phase ohne bekannten Termin muss genauso sauber zeichnen.
local savedRelease = phase3.release
phase3.release = nil
GCP.Future:Invalidate()
expect(pcall(GCP.UI.SelectTab, GCP.UI, "zukunft"),
    "Der Zukunft-Tab zeichnet auch ohne bekannten Termin")
local unknownText = {}
for _, line in ipairs(GCP.UI.rows) do
    if line:IsShown() then
        unknownText[#unknownText + 1] = (line.text:GetText() or "")
            .. " " .. (line.value:GetText() or "")
    end
end
expect(table.concat(unknownText, "\n"):find("Termin offen") ~= nil,
    "Ohne Ankündigung steht \"Termin offen\" statt einer erfundenen Zahl")
phase3.release = savedRelease
GCP.Future:Invalidate()

-- --- Handel-Tab (0.8.0) -----------------------------------------------------

-- Kaltstart: Ohne einen einzigen eigenen Verkauf muss der Tab erklaeren, was er
-- vorhat, statt eine leere Tabelle zu zeigen.
GCP.UI:SelectTab("handel")
local coldLedger = {}
for _, line in ipairs(GCP.UI.rows) do
    if line:IsShown() then coldLedger[#coldLedger + 1] = line.text:GetText() or "" end
end
local coldLedgerText = table.concat(coldLedger, "\n")
expect(coldLedgerText:find("lernt deine Verkäufe", 1, true) ~= nil,
    "Der Handel-Tab sagt beim Kaltstart, dass er erst lernt")
expect(coldLedgerText:find("Kapitalrotation", 1, true) ~= nil,
    "...und wozu die Daten gut sind")
expect(coldLedgerText:find("lokal", 1, true) ~= nil,
    "...und dass nichts den Rechner verlässt")
expect(coldLedgerText:find("7 Tage", 1, true) ~= nil,
    "Die Sieben-Tage-Kopfzeile steht auch im Kaltstart")
expect(GCP.UI.frame.summary:GetText():find("Noch keine eigenen Handelsdaten", 1, true) ~= nil,
    "Die Kopfzeile sagt es ebenfalls")
expect(GCP.UI.frame.ledgerSortButton:IsShown(), "Der Sortierknopf des Handel-Tabs ist sichtbar")

-- Mit Daten: eine gut laufende und eine zaehe Reihe, dazu ein Verkauf ohne
-- zuordenbare Einstellung.
local ledgerBase = mockNow - 6 * 86400
for index = 1, 10 do
    GCP.Ledger:RecordAuctionPosted({ itemID = 23425, quantity = 5, unitPrice = 50000,
        deposit = 400, timestamp = ledgerBase + index * 7200 })
    GCP.Ledger:ApplySaleInvoice({ itemName = "Adamantiterz", total = 250000,
        consignment = 12500, arrivedAt = ledgerBase + index * 7200 + 3 * 3600 })
end
GCP.Ledger:RecordPurchase({ itemID = 23425, quantity = 60, unitPrice = 40000,
    timestamp = ledgerBase })
GCP.Ledger:RecordAuctionPosted({ itemID = 22785, quantity = 20, unitPrice = 800,
    deposit = 100, timestamp = ledgerBase })
GCP.Ledger:RecordAuctionExpired({ itemID = 22785, quantity = 20,
    timestamp = ledgerBase + 48 * 3600 })
GCP.UI:SelectTab("handel")

local ledgerHead = nil
for index, line in ipairs(GCP.UI.rows) do
    if line:IsShown() and line.text:GetText() == "ITEM" then ledgerHead = index end
end
expect(ledgerHead ~= nil, "Der Handel-Tab hat eine Tabellenkopfzeile")
local ledgerCaptions = GCP.UI.rows[ledgerHead]
expectEqual(ledgerCaptions.value:GetText(), "LIQUIDITÄT", "Spaltenkopf Liquidität")
expectEqual(ledgerCaptions.cols[1]:GetText(), "REAL. MARGE", "Spaltenkopf realisierte Marge")
expectEqual(ledgerCaptions.cols[2]:GetText(), "ZEIT", "Spaltenkopf Zeit")
expectEqual(ledgerCaptions.cols[3]:GetText(), "SELL-THROUGH", "Spaltenkopf Sell-through")
expectEqual(ledgerCaptions.cols[4]:GetText(), "ABGELAUFEN", "Spaltenkopf abgelaufen")
expectEqual(ledgerCaptions.cols[5]:GetText(), "VERKAUFT", "Spaltenkopf verkauft")

local ledgerRow = GCP.UI.rows[ledgerHead + 1]
expect(ledgerRow ~= nil, "Der Handel-Tab erzeugt Datenzeilen")
expect(ledgerRow.text:GetText() ~= "", "Die Zeile nennt das Item")
for column = 1, 5 do
    expect(ledgerRow.cols[column]:GetText() ~= "",
        string.format("Spalte %d der Handelszeile ist gefüllt", column))
end
expect(tonumber(ledgerRow.value:GetText()) ~= nil,
    "Die beste Zeile trägt einen echten Liquidity Score")

local ledgerBreak = table.concat(ledgerRow.data.breakdown, "\n")
for _, needle in ipairs({
    "Eingestellt:", "Verkauft:", "Abgelaufen:", "Zurückgezogen:",
    "Sell-through (Stückzahl):", "Median bis Verkauf:", "Dein Einkauf (Median):",
    "Dein Verkauf netto (Median):", "Realisierte Marge:", "Liquidity Score:",
}) do
    expect(ledgerBreak:find(needle, 1, true) ~= nil,
        "Der Handel-Tooltip nennt \"" .. needle .. "\"")
end
expect(ledgerBreak:find("kein Fehlschlag", 1, true) ~= nil,
    "Der Tooltip sagt, dass ein Abbruch kein Fehlschlag ist")
expect(ledgerBreak:find("lokal", 1, true) ~= nil,
    "...und dass die Daten lokal bleiben")

local ledgerSummary = GCP.UI.frame.summary:GetText()
expect(ledgerSummary:find("Verkauf", 1, true) ~= nil,
    "Die Kopfzeile nennt die Zahl der Verkäufe")
expect(ledgerSummary:find("Umsatz netto", 1, true) ~= nil, "...und den Nettoumsatz")

-- Sortierung: der Knopf schaltet um, und die Liste folgt.
local sortedByLiquidity = {}
for index = ledgerHead + 1, #GCP.UI.rows do
    local line = GCP.UI.rows[index]
    local score = line:IsShown() and tonumber(line.value:GetText() or "") or nil
    if score then sortedByLiquidity[#sortedByLiquidity + 1] = score end
end
for index = 2, #sortedByLiquidity do
    expect(sortedByLiquidity[index] <= sortedByLiquidity[index - 1],
        "Der Handel-Tab sortiert nach Liquidity Score absteigend")
end
expect(pcall(GCP.UI.frame.ledgerSortButton:GetScript("OnClick")),
    "Der Sortierknopf des Handel-Tabs lässt sich klicken")
expectEqual(GCP.db.options.ledgerSort, "profit", "...und schaltet auf den realisierten Gewinn")
expect(pcall(GCP.UI.SelectTab, GCP.UI, "handel"),
    "Der Handel-Tab zeichnet auch in der zweiten Sortierung")
expect(GCP.UI.frame.ledgerSortButton.label:GetText():find("Gewinn", 1, true) ~= nil,
    "Der Knopf beschriftet die aktive Sortierung")
GCP.db.options.ledgerSort = "liquidity"

-- Tooltip und Rechtsklick einer Handelszeile.
GCP:Profile().watchlist = {}
GCP.UI:SelectTab("handel")
local watchRow = GCP.UI.rows[ledgerHead + 1]
expect(pcall(watchRow:GetScript("OnEnter"), watchRow), "Tooltip einer Handelszeile öffnet")
expect(pcall(watchRow:GetScript("OnLeave"), watchRow), "Tooltip einer Handelszeile schließt")
expect(pcall(watchRow:GetScript("OnClick"), watchRow, "RightButton"),
    "Rechtsklick auf eine Handelszeile")
expectEqual(GCP.Market:IsWatched(watchRow.data.watchable), true,
    "...nimmt das Item in die Beobachtung auf")
GCP:Profile().watchlist = {}

-- Ein Verkauf ohne zuordenbare Einstellung schaltet die stueckzahlbasierte
-- Rate ab - und die Oberflaeche sagt das mit einem Stern statt einer Zahl,
-- die zu niedrig waere.
GCP.Ledger:ApplySaleInvoice({ itemName = "Adamantiterz", total = 99999,
    arrivedAt = mockNow - 600 })
GCP.UI:SelectTab("handel")
local starText = {}
for index = ledgerHead, #GCP.UI.rows do
    local line = GCP.UI.rows[index]
    if line:IsShown() then starText[#starText + 1] = line.cols[3]:GetText() or "" end
end
expect(table.concat(starText, " "):find("*", 1, true) ~= nil,
    "Eine Rate je Auktion statt je Stück wird mit * gekennzeichnet")

-- --- Erweiterte Tooltips mit Handelsdaten -----------------------------------

GCP.db.options.opportunityMinProfit = 0
GCP.db.options.opportunityMinROI = 0
GCP.Opportunity:Invalidate()

-- Welche Chance die Attrappe gerade hergibt, ist fuer diese Pruefung egal -
-- entscheidend ist, dass genau die Chance mit eigener Verkaufsgeschichte sie
-- auch im Tooltip zeigt. Also bekommt das Item der ersten Chance eine.
local coldOpportunities = GCP.Opportunity:BuildReport(true).opportunities
expect(#coldOpportunities > 0, "Die Attrappe liefert mindestens eine Chance")
local oppItemID = coldOpportunities[1].itemID
local oppItemName = GetItemInfo(oppItemID)
for index = 1, 8 do
    GCP.Ledger:RecordAuctionPosted({ itemID = oppItemID, quantity = 4, unitPrice = 25000,
        timestamp = ledgerBase + index * 7200 })
    GCP.Ledger:ApplySaleInvoice({ itemName = oppItemName, total = 100000,
        consignment = 5000, arrivedAt = ledgerBase + index * 7200 + 5 * 3600 })
end
GCP.Ledger:RecordAuctionPosted({ itemID = oppItemID, quantity = 4, unitPrice = 25000,
    timestamp = ledgerBase + 90 * 3600 })
GCP.Ledger:RecordAuctionExpired({ itemID = oppItemID, quantity = 4,
    timestamp = ledgerBase + 138 * 3600 })
GCP.Opportunity:Invalidate()

GCP.UI:SelectTab("chancen")
local warmOpp, warmText = nil, nil
for index = 2, #GCP.UI.rows do
    local line = GCP.UI.rows[index]
    if line:IsShown() and line.data and line.data.breakdown then
        local text = table.concat(line.data.breakdown, "\n")
        if text:find("DEINE VERKAUFSDATEN", 1, true) then
            warmOpp, warmText = line, text
            break
        end
    end
end
expect(warmOpp ~= nil, "Eine Chance mit eigenen Verkaufsdaten zeigt sie im Tooltip")
if warmOpp then
    for _, needle in ipairs({ "Sell-through", "Median bis Verkauf", "Verkäufe:",
        "Liquidity Score:" }) do
        expect(warmText:find(needle, 1, true) ~= nil,
            "Der Chancen-Tooltip nennt \"" .. needle .. "\"")
    end
    expect(warmText:find("PROFIT VELOCITY", 1, true) ~= nil,
        "Der Chancen-Tooltip zeigt die Profit Velocity, sobald es sie gibt")
    expect(warmText:find("100 g / Tag", 1, true) ~= nil,
        "...und zwar als Gewinn je 100 g gebundenem Kapital und Tag")
    expect(warmText:find("nicht je Menge", 1, true) ~= nil,
        "...mit dem Hinweis, dass die Markttiefe unbekannt bleibt")
    expect(warmText:find("KAUFEN", 1, true) == nil,
        "Auch mit Verkaufsdaten steht nirgends \"KAUFEN\"")
    expect(warmOpp.cols[1]:GetText() ~= "–",
        "Die Liquiditätsspalte der Zeile trägt jetzt eine Zahl")
    expect(warmText:find("Deine Spur zu diesem Item", 1, true) ~= nil,
        "Der Tooltip nennt den belegten Ausführungsstatus")
    expect(warmOpp.autoPill:IsShown(), "...und die Zeile trägt ihn als Etikett")
end

-- Der Zukunft-Tooltip bekommt dieselbe Dimension - ohne den Demand zu ruehren.
GCP.Future:Invalidate()
GCP.UI:SelectTab("zukunft")
local futureLiquidity = {}
for _, line in ipairs(GCP.UI.rows) do
    if line:IsShown() and line.data and line.data.breakdown then
        futureLiquidity[#futureLiquidity + 1] = table.concat(line.data.breakdown, "\n")
    end
end
expect(table.concat(futureLiquidity, "\n"):find("Liquidität", 1, true) ~= nil,
    "Der Zukunft-Tooltip nennt die persönliche Liquidität als eigene Dimension")

GCP.db.options.opportunityMinProfit = 0
GCP.db.options.opportunityMinROI = 0

-- Fenster oeffnen loest OnShow samt Aufzeichnung aus.
-- Die Optionen weisen die Handelsbilanz mitsamt Datenschutzsatz aus.
GCP.UI:SelectTab("options")
local optionsData = GCP.UI.frame.optionsPanel.dataText:GetText()
expect(optionsData:find("Handelsbilanz", 1, true) ~= nil,
    "Die Datenübersicht nennt die Handelsbilanz")
expect(optionsData:find("bleibt lokal", 1, true) ~= nil,
    "...und sagt ausdrücklich, dass sie den Rechner nicht verlässt")

expect(pcall(GCP.UI.Toggle, GCP.UI), "Das Fenster lässt sich öffnen")
for _, fn in ipairs(timers) do fn() end
expect(GCP.UI.frame:IsShown(), "Nach dem Öffnen ist das Fenster sichtbar")

-- ---------------------------------------------------------------------------
-- 0.9.0: Zentrale, Route und Guide Viewer
-- ---------------------------------------------------------------------------

-- Erster Start: Der Willkommenstext steht vor allem anderen.
GCP.db.options.seenWelcome = nil
GCP.UI:SelectTab("zentrale")
expect(GCP.UI.frame.commandPanel.welcome:IsShown(),
    "Beim ersten Start begruesst die Zentrale statt Zahlen zu zeigen")
local welcomeText = GCP.UI.frame.commandPanel.welcome.body:GetText()
expect(welcomeText:find("Auctionator", 1, true) ~= nil,
    "...und erklaert, was bessere Empfehlungen bringt")
expect(welcomeText:find("verlässt deinen Rechner", 1, true) ~= nil,
    "...und dass nichts den Rechner verlaesst")
-- Der Willkommensschirm liegt ueber der Zentrale. Blieben die Bloecke dahinter
-- sichtbar, stuenden Begruessung und Kapitalzahlen uebereinander im Bild -
-- genau das war bis 1.0.0-beta.1 der Fall.
local hiddenBehindWelcome = 0
for _, block in ipairs(GCP.UI.frame.commandPanel.blocks) do
    if not block:IsShown() then hiddenBehindWelcome = hiddenBehindWelcome + 1 end
end
expectEqual(hiddenBehindWelcome, #GCP.UI.frame.commandPanel.blocks,
    "...und verdeckt dabei jeden Block der Zentrale")

GCP.db.options.seenWelcome = true
GCP.UI:SelectTab("zentrale")
expect(not GCP.UI.frame.commandPanel.welcome:IsShown(),
    "Nach dem Bestaetigen ist der Willkommenstext weg")
for _, block in ipairs(GCP.UI.frame.commandPanel.blocks) do
    expect(block:IsShown(), "...und die Bloecke der Zentrale sind wieder da")
end

local kpi = GCP.UI.frame.commandPanel.kpi
expect(kpi.gold.value:GetText() ~= "", "Die Zentrale nennt den Goldstand")
expect(kpi.free.value:GetText() ~= "", "...und das frei verfuegbare Gold")
expect(kpi.today.value:GetText() ~= "", "...und was heute realisiert wurde")
expect(kpi.potential.value:GetText() ~= "", "...und das offene Potenzial")
expect(kpi.potential.value:GetText():find("0 g") == nil
    or kpi.potential.value:GetText():find("keine") ~= nil,
    "Ohne Chance steht dort ein Satz statt einer Null")

local best = GCP.UI.frame.commandPanel.best
expect(best.title:GetText() ~= "", "Die Zentrale nennt immer eine beste Aktion oder sagt, dass es keine gibt")
expect(best.startButton.label:GetText():find("ROUTE") ~= nil,
    "...und traegt einen Knopf, der eine Route startet")

-- Zielmodus: Die Knoepfe spiegeln die gespeicherte Einstellung.
GCP.db.options.goalMinutes = 90
GCP.db.options.goalRisk = "low"
GCP.UI:SelectTab("zentrale")
expect(GCP.UI.frame.commandPanel.goal.timeButtons[90].active,
    "Die gewaehlte Zeit ist als aktiv markiert")
expect(GCP.UI.frame.commandPanel.goal.riskButtons.low.active,
    "Die gewaehlte Risikostufe ebenfalls")
expect(GCP.UI.frame.commandPanel.goal.capitalNote:GetText():find("Reserve", 1, true) ~= nil,
    "Der Zielmodus weist die Cash-Reserve aus")

-- Route planen und anzeigen.
local planned = GCP.UI:PlanRouteFromGoal()
expect(planned ~= nil, "Aus dem Zielmodus entsteht eine Route")
expectEqual(GCP.UI.activeTab, "route", "...und die Ansicht wechselt zur Route")
local routeText = {}
for _, row in ipairs(GCP.UI.rows) do
    if row:IsShown() then routeText[#routeText + 1] = row.text:GetText() or "" end
end
local routeJoined = table.concat(routeText, "\n")
expect(routeJoined ~= "", "Der Routen-Tab zeigt Zeilen")
expect(GCP.UI.frame.summary:GetText() ~= "", "...und eine Zusammenfassung")


-- Guide Viewer
GCP.db.options.guideViewer = true
GCP.UI:ShowGuideViewer()
local guide = GCP.UI.guideFrame
expect(guide ~= nil, "Es gibt ein eigenes Guide-Fenster")
GCP.UI:StartRouteFromGoal()
GCP.UI:RefreshGuide()
if GCP.Guide:StepCount() > 0 then
    expect(guide:IsShown(), "Mit laufender Route ist der Guide sichtbar")
    expect(guide.step:GetText():find("Schritt", 1, true) ~= nil,
        "...und zaehlt die Schritte")
    expect(guide.action:GetText() ~= "", "...und nennt die aktuelle Anweisung")
    expect(guide.whyButton ~= nil, "...mit einem Warum-Knopf")
    expect(guide.skipButton ~= nil, "...und einem Ueberspringen-Knopf")

    -- Minimieren blendet den Inhalt aus, nicht das Fenster.
    GCP.UI:ToggleGuideMinimized()
    GCP.UI:RefreshGuide()
    expect(guide:IsShown(), "Minimiert bleibt das Fenster sichtbar")
    expect(not guide.action:IsShown(), "...aber die Anweisung ist ausgeblendet")
    GCP.UI:ToggleGuideMinimized()
    GCP.UI:RefreshGuide()
    expect(guide.action:IsShown(), "Wieder aufgeklappt steht sie wieder da")

    -- Skalierung wird gespeichert.
    expect(GCP.UI:SetGuideScale(1.2), "Die Groesse laesst sich aendern")
    expectEqual(GCP.db.options.guideScale, 1.2, "...und wird gespeichert")
    GCP.UI:SetGuideScale(9)
    expect(GCP.db.options.guideScale <= 2, "...aber nicht ins Absurde")

    expect(GCP.UI:PrintGuideWhy(), "Der Warum-Knopf gibt eine Begruendung aus")

    -- --- Renderbare Zeichen (1.0.0-beta.4) ---------------------------------
    --
    -- FRIZQT__.TTF, die Standardschrift des Clients, enthaelt den
    -- Unicode-Block "Geometric Shapes" nicht. Der Richtungspfeil bestand aus
    -- genau diesen Zeichen und erschien im Spiel als leeres Kaestchen - ueber
    -- mehrere Fassungen hinweg, weil kein Test je hingesehen hat. Diese
    -- Pruefung sieht hin: Was im Guide steht, muss reines ASCII sein.
    -- Gesucht sind nicht "Zeichen ueber 127" - Umlaute kann die Schrift sehr
    -- wohl, und "Überspringen" faengt mit einem an. Gesucht sind die Bloecke,
    -- die ihr fehlen: Pfeile (U+2190-U+21FF) und geometrische Formen
    -- (U+25A0-U+25FF). In UTF-8 beginnen beide mit 0xE2, gefolgt von 0x86/0x87
    -- beziehungsweise 0x96/0x97.
    local function hasUnrenderableGlyph(text)
        text = text or ""
        for index = 1, #text - 1 do
            if text:byte(index) == 0xE2 then
                local second = text:byte(index + 1)
                if second == 0x86 or second == 0x87
                    or second == 0x96 or second == 0x97 then
                    return true
                end
            end
        end
        return false
    end
    expect(not hasUnrenderableGlyph(guide.arrow:GetText()),
        "Der Richtungspfeil besteht aus Zeichen, die die Clientschrift kennt")
    expect(not hasUnrenderableGlyph(guide.backButton.label:GetText()),
        "Der Zurueck-Knopf ebenfalls")
    expect(not hasUnrenderableGlyph(guide.skipButton.label:GetText()),
        "Der Ueberspringen-Knopf ebenfalls")

    -- --- Vorhaben und Item (1.0.0-beta.4) ----------------------------------
    expect(guide.goalLine ~= nil, "Das Guide-Fenster hat eine Zeile fuer das Vorhaben")
    expect(guide.itemButton ~= nil, "...und einen Knopf fuer das Item")
    local step = GCP.Guide:CurrentStep()
    local groupInfo = step and GCP.Guide:GroupInfo(step)
    if groupInfo and groupInfo.title then
        expect(guide.goalLine:GetText():find(groupInfo.title, 1, true) ~= nil,
            "Bei einem Schritt mit Vorhaben steht dessen Ziel im Fenster")
    end
    if guide.itemButton.itemID then
        expect(pcall(guide.itemButton:GetScript("OnEnter"), guide.itemButton),
            "Der Tooltip des Items laesst sich oeffnen")
        expect(pcall(guide.itemButton:GetScript("OnLeave"), guide.itemButton),
            "...und wieder schliessen")
    end
end

GCP.UI:HideGuideViewer()
expect(not GCP.UI.guideFrame:IsShown(), "Der Guide laesst sich schliessen")
expectEqual(GCP.db.options.guideViewer, false, "...und bleibt zu")
GCP.Guide:Abort()

-- Ohne Route zeigt der Guide nichts an, auch wenn er eingeschaltet ist.
GCP.db.options.guideViewer = true
expect(not GCP.UI:RefreshGuide(), "Ohne Route bleibt der Guide leer")

-- ===========================================================================
-- LAYOUT
--
-- Ganz zum Schluss, wenn jeder Tab einmal gezeichnet und jeder Anker gesetzt
-- ist. Geprueft wird zweierlei:
--
--   1. Faellt etwas aus seinem Rahmen? Das war der Fehler aus 1.0.0-beta.6:
--      eine Knopfreihe endete vier Pixel unter ihrem Block und lag damit auf
--      der Zeile darunter.
--   2. Ueberlappen sich zwei Knoepfe? Das war der Fehler aus 1.0.0-beta.3:
--      die Knopfreihe des Guides war breiter als das Fenster.
--
-- Die zweite Pruefung laeuft nur ueber Knoepfe. Deren Groesse steht exakt fest;
-- bei Texten ist sie geschaetzt, und eine Meldung waere nur so gut wie die
-- Schaetzung.
-- ===========================================================================

do
    local function report(ok, label) expect(ok, label) end
    -- Zurueck auf die Zentrale und einmal zeichnen: Geprueft wird der Zustand,
    -- den der Spieler sieht, nicht der, in dem der letzte Test aufgehoert hat.
    GCP.UI:SelectTab("zentrale")
    GCP.UI:Refresh()
    local panel = GCP.UI.frame.commandPanel

    layout.checkContainment(panel.best, "Beste Aktion", report)
    layout.checkContainment(panel.goal, "Zielmodus", report)
    layout.checkContainment(panel.quick, "Schnellprofile", report)
    layout.checkContainment(panel.farm, "Farm", report)
    layout.checkContainment(panel.service, "Dienstleistung", report)
    for key, box in pairs(panel.kpi) do
        layout.checkContainment(box, "Kachel " .. tostring(key), report)
    end

    -- Und die Bloecke selbst gegen das Panel. Diese eine Zeile haette den
    -- Fehler aus 1.1.0 gefunden: Die Dienstleistungsflaeche hing 40 Pixel unter
    -- dem unteren Rand, weil sie eine sechste Reihe in einem Bauplan fuer fuenf
    -- war. Geprueft wurde bis dahin nur der Inhalt JEDES Blocks gegen SEINEN
    -- Block - nie ein Block gegen die Flaeche, die ihn tragen muss.
    layout.checkContainment(panel, "Command Center", report)

    -- Seit 1.0.0-beta.9 alles gegen alles, Texte eingeschlossen. Die Liste von
    -- Hand zu pflegen hiesse, sie beim naechsten neuen Element zu vergessen.
    layout.checkAllOverlaps(panel.best, "Beste Aktion", report)
    layout.checkAllOverlaps(panel.goal, "Zielmodus", report)
    layout.checkAllOverlaps(panel.farm, "Farm", report)

    -- Der Bauplan gegen die verfuegbare Hoehe. Beide Zahlen kommen aus UI.lua
    -- selbst (panel.requiredHeight / panel.availableHeight) und zaehlen die
    -- Reihen, die BuildCommandPanel wirklich angelegt hat.
    --
    -- Vorher stand hier eine von Hand aufgezaehlte Liste aus fuenf Bloecken und
    -- ein fest eingetipptes "4 * 14". Beides veraltete beim Einfuegen der
    -- sechsten Reihe, und der Test blieb gruen, waehrend der Knopf im Spiel
    -- unter dem Fensterrand lag. Eine Pruefung, die ihre eigene Annahme
    -- mitbringt, prueft die Annahme und nicht den Code.
    expect(#panel.rows >= 5, string.format(
        "Das Command Center meldet seine Reihen (%d)", #panel.rows))
    expect((panel.requiredHeight or 0) > 0,
        "Die Reihen des Command Centers haben Hoehen")
    expect(panel.requiredHeight <= panel.availableHeight, string.format(
        "Die Reihen des Command Centers passen in die Panelhoehe (%d von %d)",
        math.floor(panel.requiredHeight or 0), math.floor(panel.availableHeight or 0)))

    -- Die Statuszeile sitzt bei -158 und damit innerhalb der Kachelreihe des
    -- Command Centers. Auf der Zentrale muss sie weg sein - sonst steht der
    -- Text des zuletzt besuchten Tabs hinter den Kacheln.
    expect(not GCP.UI.frame.summary:IsShown(),
        "Auf der Zentrale ist die Statuszeile ausgeblendet")
    GCP.UI:SelectTab("chancen")
    expect(GCP.UI.frame.summary:IsShown(),
        "...auf den anderen Tabs steht sie wieder da")
    -- Und sie hat eine rechte Grenze, sonst waechst sie aus dem Fenster.
    expect(#GCP.UI.frame.summary._points >= 2,
        "Die Statuszeile ist links UND rechts verankert")
    expect(GCP.UI.frame.summary._wordWrap == false,
        "...und bricht nicht in eine zweite Zeile um")
    GCP.UI:SelectTab("zentrale")
    GCP.UI:Refresh()

    -- Das Guide-Fenster. Es steht waehrend des Spielens offen und ist das
    -- engste Fenster des Addons; hier zaehlt jeder Pixel.
    -- Das Guide-Fenster hat zwei Zustaende, die sich dieselbe Flaeche teilen:
    -- waehrend der Route die Knopfreihe, danach "Neue Route planen". Beide
    -- werden einzeln geprueft - zusammen betrachtet wuerden sie sich
    -- ueberlappen, und zwar mit Absicht.
    local guideFrame = GCP.UI.guideFrame
    layout.checkContainment(guideFrame, "Guide", report)
    -- "action" fehlt in dieser Liste, und zwar bewusst: Seine Position haengt
    -- davon ab, ob daneben ein Item-Symbol steht - RefreshGuide rueckt es zur
    -- Laufzeit entweder an den Rand oder hinter das Symbol. Beim Anlegen steht
    -- es am Rand und laege damit auf dem Symbol; geprueft wuerde also ein
    -- Zustand, den es im Spiel nie gibt. Diese Attrappe kann keine echte Route
    -- zeigen und damit auch keinen der beiden richtigen Zustaende herstellen.
    layout.checkGroup(guideFrame, "Guide (Route läuft)", {
        "title", "close", "minimize", "goal", "step", "goalLine", "arrow",
        "distance", "itemButton", "numbers", "confidence",
        "backButton", "whyButton", "doneButton", "skipButton",
        "pauseButton", "abortButton",
    }, report)
    layout.checkGroup(guideFrame, "Guide (Route fertig)", {
        "title", "close", "minimize", "goal", "step",
        "backButton", "newRouteButton", "abortButton",
    }, report)

    -- Das Servicefenster (1.1.0-beta.5). Uhr, drei Kacheln, Rate, Notiz und
    -- zwei Knoepfe auf 260 x 224 Pixeln - die Kachelreihe ist auf den Pixel
    -- ausgereizt (3 x 76 + 2 x 8 = 244 bei 236 Innenbreite waere zu breit,
    -- deshalb steht sie am linken Rand und endet vor dem rechten).
    GCP.UI:ShowServiceViewer()
    local serviceFrame = GCP.UI.serviceFrame
    layout.checkContainment(serviceFrame, "Servicefenster", report)
    layout.checkGroup(serviceFrame, "Servicefenster", {
        "title", "close", "clock", "state", "rate", "note",
        "toggleButton", "stopButton",
    }, report)
    for key, tile in pairs(serviceFrame.tiles) do
        layout.checkContainment(tile, "Servicekachel " .. key, report)
    end
    layout.checkOverlap(serviceFrame, "Servicekacheln",
        { "tiles.customers", "tiles.gross", "tiles.net" }, report)
    GCP.UI:HideServiceViewer()

    -- Die Werkzeugleiste des Hauptfensters.
    layout.checkOverlap(GCP.UI.frame.toolbar, "Werkzeugleiste",
        { "scopeButton", "filterButton", "boundButton", "sortButton",
          "ignoredButton", "refreshButton" }, report)
end

print(string.format("ui.lua: %d Tests bestanden, %d fehlgeschlagen", passed, failed))
if failed > 0 then
    error("Es gibt fehlgeschlagene Tests.")
end
