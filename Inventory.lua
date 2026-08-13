local addonName, GCP = ...

GCP.Inventory = {}
local Inventory = GCP.Inventory

local GetItemInfoCompat = (C_Item and C_Item.GetItemInfo) or GetItemInfo

function Inventory:HasSyndicator()
    return Syndicator ~= nil and Syndicator.API ~= nil
        and type(Syndicator.API.GetAllCharacters) == "function"
end

local function ensureEntry(result, itemID)
    local entry = result[itemID]
    if not entry then
        entry = { itemID = itemID, count = 0, sources = {}, owners = {} }
        result[itemID] = entry
    end
    if type(entry.owners) ~= "table" then entry.owners = {} end
    return entry
end

-- owner ist der Charakter, bei dem der Stapel liegt. Er wird getrennt von der
-- Quelle gefuehrt: "Bank" sagt, WO etwas liegt, der Charakter sagt, WESSEN
-- Bank das ist. Bis 1.1.0-beta.4 ging diese Angabe beim Zusammenzaehlen
-- verloren - der Verkaufen-Tab konnte deshalb nicht sagen, auf welchem
-- Charakter die 40 Netherstoffballen liegen.
local function addCount(result, itemID, count, sourceLabel, link, isBound, owner)
    if type(itemID) ~= "number" or itemID <= 0 then return end
    count = tonumber(count) or 0
    if count <= 0 then return end
    local entry = ensureEntry(result, itemID)
    entry.count = entry.count + count
    entry.sources[sourceLabel] = (entry.sources[sourceLabel] or 0) + count
    if type(owner) == "string" and owner ~= "" then
        entry.owners[owner] = (entry.owners[owner] or 0) + count
    end
    if link and not entry.link then entry.link = link end
    -- Ein Stapel gebunden reicht: Das AH nimmt das Item dann nicht mehr an.
    if isBound then entry.bound = true end
end

-- Der eigene Charakter, so benannt wie Syndicator ihn benennt: "Name-Realm".
-- Ohne Realm bleibt der blosse Name - geraten wird nichts.
function Inventory:PlayerName()
    if type(UnitName) ~= "function" then return nil end
    local ok, name = pcall(UnitName, "player")
    if not ok or type(name) ~= "string" or name == "" then return nil end
    if type(GetRealmName) == "function" then
        local okRealm, realm = pcall(GetRealmName)
        if okRealm and type(realm) == "string" and realm ~= "" then
            return name .. "-" .. realm
        end
    end
    return name
end

-- Eigene Taschen live. Der Client kennt beide API-Generationen; der Anniversary-
-- Client liefert GetContainerItemInfo als Tabelle, aeltere Fassungen als Liste.
function Inventory:ScanBags(result, owner)
    result = result or {}
    owner = owner or self:PlayerName()
    local numSlots, getInfo
    if C_Container and C_Container.GetContainerNumSlots then
        numSlots = C_Container.GetContainerNumSlots
        getInfo = C_Container.GetContainerItemInfo
    else
        numSlots = GetContainerNumSlots
        getInfo = GetContainerItemInfo
    end
    if type(numSlots) ~= "function" then return result end
    for bag = 0, 4 do
        local slots = numSlots(bag) or 0
        for slot = 1, slots do
            local info = getInfo(bag, slot)
            if type(info) == "table" then
                addCount(result, info.itemID, info.stackCount, "Taschen",
                    info.hyperlink, info.isBound, owner)
            elseif info ~= nil then
                -- Alte Signatur: texture, itemCount, locked, quality, readable,
                -- lootable, itemLink, isFiltered, noValue, itemID, isBound
                local _, itemCount, _, _, _, _, itemLink, _, _, itemID, isBound =
                    getInfo(bag, slot)
                addCount(result, itemID, itemCount, "Taschen", itemLink, isBound, owner)
            end
        end
    end
    return result
end

-- Alles, was Syndicator ueber den Account weiss: Taschen, Bank, Post und
-- laufende Auktionen aller sichtbaren Charaktere. Angelegte Ausruestung bleibt
-- bewusst draussen - die will niemand "mal eben" versilbern. Die Struktur der
-- Syndicator-Daten wird nicht als stabil angenommen: Eingesammelt wird rekursiv
-- alles, was wie ein Item-Eintrag aussieht.
local SYNDICATOR_CONTAINERS = {
    bags = "Taschen",
    bank = "Bank",
    mail = "Post",
    auctions = "Auktionen",
}

local function collectItems(node, result, sourceLabel, depth, owner)
    if type(node) ~= "table" or depth > 6 then return end
    if type(node.itemID) == "number" then
        addCount(result, node.itemID, node.itemCount or node.count or 1,
            sourceLabel, node.itemLink, node.isBound, owner)
        return
    end
    for _, child in pairs(node) do
        if type(child) == "table" then
            collectItems(child, result, sourceLabel, depth + 1, owner)
        end
    end
end

function Inventory:ScanAccount()
    local result = {}
    if not self:HasSyndicator() then
        return self:ScanBags(result), false
    end
    local ok = pcall(function()
        for _, name in ipairs(Syndicator.API.GetAllCharacters() or {}) do
            local char = Syndicator.API.GetByCharacterFullName(name)
            if type(char) == "table" then
                for field, label in pairs(SYNDICATOR_CONTAINERS) do
                    collectItems(char[field], result, label, 0, name)
                end
            end
        end
    end)
    if not ok then
        -- Syndicator hat die Daten noch nicht bereit; die Live-Taschen sind
        -- besser als gar nichts.
        return self:ScanBags({}), false
    end
    -- Frisch gelootete Stapel sind bei Syndicator erst nach dessen naechstem
    -- Update sichtbar; die Live-Taschen ersetzen deshalb dessen Taschen-Zahlen
    -- nicht, sondern fuellen nur fehlende Items auf.
    local live = self:ScanBags({})
    for itemID, entry in pairs(live) do
        if not result[itemID] then
            result[itemID] = entry
        end
    end
    return result, true
end

-- Reicht die Item-Metadaten nach, die GetItemInfo kennt. Items ohne Cache-
-- Eintrag behalten name = nil; der Aufrufer entscheidet, wie er sie anzeigt.
function Inventory:Describe(entry)
    if not entry then return nil end
    local name, link, quality, _, _, _, _, _, _, icon, sellPrice, classID =
        GetItemInfoCompat(entry.link or entry.itemID)
    entry.name = name
    entry.link = entry.link or link
    entry.quality = quality
    entry.icon = icon
    entry.sellPrice = sellPrice
    entry.classID = classID
    return entry
end
