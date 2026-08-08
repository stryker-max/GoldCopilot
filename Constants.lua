local addonName, GCP = ...

GCP.Constants = {
    VERSION = "0.2.0",

    -- Fraktionsauktionshaus behaelt 5 % des Verkaufspreises ein.
    AH_CUT = 0.05,

    -- Tagesplan-Eintraege unter diesem Gewinn (Kupfer) sind Zeitverschwendung
    -- und fliegen raus; ueberschreibbar via options.minRoadmapValue.
    MIN_ROADMAP_VALUE = 50000,

    -- 10 Motes ergeben per Rechtsklick 1 Ur-Partikel; der Weg zurueck existiert nicht.
    MOTES_PER_PRIMAL = 10,

    -- Verzauberer wandeln 3 niedere Essenzen in 1 hohe um und umgekehrt.
    ESSENCES_PER_GREATER = 3,

    COLOR_PREFIX = "|cffd9a834Gold Copilot:|r ",
    COLOR_GOLD = "|cffd9a834",
    COLOR_GREEN = "|cff4dcc4d",
    COLOR_RED = "|cffe05555",
    COLOR_GRAY = "|cff9d9d9d",
}

local C = GCP.Constants

-- Item-Namen kommen zur Laufzeit aus GetItemInfo und sind damit automatisch in
-- der Client-Sprache; hier stehen nur IDs, die englischen Namen dienen der
-- Lesbarkeit. IDs gegen die Questie-/AtlasLoot-Datenbanken geprueft.

C.PRIMALS = {
    { mote = 22574, primal = 21884 }, -- Fire
    { mote = 22578, primal = 21885 }, -- Water
    { mote = 22572, primal = 22451 }, -- Air
    { mote = 22573, primal = 22452 }, -- Earth
    { mote = 22577, primal = 22456 }, -- Shadow
    { mote = 22576, primal = 22457 }, -- Mana
    { mote = 22575, primal = 21886 }, -- Life
}

C.ESSENCES = {
    { lesser = 10938, greater = 10939 }, -- Magic
    { lesser = 10998, greater = 11082 }, -- Astral
    { lesser = 11134, greater = 11135 }, -- Mystic
    { lesser = 11174, greater = 11175 }, -- Nether
    { lesser = 16202, greater = 16203 }, -- Eternal
    { lesser = 22447, greater = 22446 }, -- Planar
}

-- Berufs-Cooldowns und dauerhaft wiederholbare Umwandlungen. "cooldown = false"
-- heisst: beliebig oft herstellbar (Arkanit hat seit 2.0 keinen Cooldown mehr).
-- mats: { itemID, Anzahl }. product wird 1x erzeugt.
C.CRAFT_COOLDOWNS = {
    -- TBC-Alchemie (geteilter Transmutations-Cooldown)
    { spell = 29688, product = 23571, cooldown = true, profession = "Alchemie",
      mats = { { 21884, 1 }, { 21885, 1 }, { 22451, 1 }, { 22452, 1 }, { 22457, 1 } } }, -- Primal Might
    { spell = 28566, product = 21884, cooldown = true, profession = "Alchemie", mats = { { 22451, 1 } } }, -- Air -> Fire
    { spell = 28567, product = 21885, cooldown = true, profession = "Alchemie", mats = { { 22452, 1 } } }, -- Earth -> Water
    { spell = 28568, product = 22452, cooldown = true, profession = "Alchemie", mats = { { 21884, 1 } } }, -- Fire -> Earth
    { spell = 28569, product = 22451, cooldown = true, profession = "Alchemie", mats = { { 21885, 1 } } }, -- Water -> Air
    { spell = 28580, product = 21885, cooldown = true, profession = "Alchemie", mats = { { 22456, 1 } } }, -- Shadow -> Water
    { spell = 28581, product = 22456, cooldown = true, profession = "Alchemie", mats = { { 21885, 1 } } }, -- Water -> Shadow
    { spell = 28582, product = 21884, cooldown = true, profession = "Alchemie", mats = { { 22457, 1 } } }, -- Mana -> Fire
    { spell = 28583, product = 22457, cooldown = true, profession = "Alchemie", mats = { { 21884, 1 } } }, -- Fire -> Mana
    { spell = 28584, product = 22452, cooldown = true, profession = "Alchemie", mats = { { 21886, 1 } } }, -- Life -> Earth
    { spell = 28585, product = 21886, cooldown = true, profession = "Alchemie", mats = { { 22452, 1 } } }, -- Earth -> Life
    -- Klassische Alchemie
    { spell = 17187, product = 12360, cooldown = false, profession = "Alchemie",
      mats = { { 12359, 1 }, { 12363, 1 } } }, -- Arcanite Bar
    { spell = 17559, product = 7078, cooldown = true, profession = "Alchemie", mats = { { 7082, 1 } } }, -- Air -> Fire
    { spell = 17560, product = 7076, cooldown = true, profession = "Alchemie", mats = { { 7078, 1 } } }, -- Fire -> Earth
    { spell = 17561, product = 7080, cooldown = true, profession = "Alchemie", mats = { { 7076, 1 } } }, -- Earth -> Water
    { spell = 17562, product = 7082, cooldown = true, profession = "Alchemie", mats = { { 7080, 1 } } }, -- Water -> Air
    { spell = 17563, product = 12808, cooldown = true, profession = "Alchemie", mats = { { 7080, 1 } } }, -- Water -> Undeath
    { spell = 17565, product = 7076, cooldown = true, profession = "Alchemie", mats = { { 12803, 1 } } }, -- Life -> Earth
    { spell = 17566, product = 12803, cooldown = true, profession = "Alchemie", mats = { { 7076, 1 } } }, -- Earth -> Life
    { spell = 11479, product = 3577, cooldown = true, profession = "Alchemie", mats = { { 3575, 1 } } }, -- Iron -> Gold
    { spell = 11480, product = 6037, cooldown = true, profession = "Alchemie", mats = { { 3860, 1 } } }, -- Mithril -> Truesilver
    -- Schneiderei
    { spell = 18560, product = 14342, cooldown = true, profession = "Schneiderei",
      mats = { { 14256, 2 } } }, -- Mooncloth aus Felcloth
}

-- Kuratierte Farm-Ziele fuer den Tagesplan, gereiht nach Gold je Stunde:
-- Marktpreis mal ratePerHour. Die Raten sind bewusst konservative Schaetzungen
-- aus gaengigen Farm-Guides - ein Stapelpreis sagt nichts darueber, wie lange
-- man fuer den Stapel braucht. skill/minSkill filtern Ziele aus, die der
-- Charakter gar nicht einsammeln koennte.
C.FARM_CATALOG = {
    { item = 22785, ratePerHour = 60, skill = "herb", zone = "Höllenfeuerhalbinsel (überall in der Scherbenwelt)" }, -- Felweed
    { item = 22786, ratePerHour = 70, skill = "herb", zone = "Höllenfeuerhalbinsel / Wälder von Terokkar" },  -- Dreaming Glory
    { item = 22787, ratePerHour = 50, skill = "herb", zone = "Zangarmarschen" },                              -- Ragveil
    { item = 22788, ratePerHour = 40, skill = "herb", zone = "Zangarmarschen (Pilzhöhlen)" },                 -- Flame Cap
    { item = 22789, ratePerHour = 50, skill = "herb", zone = "Wälder von Terokkar" },                         -- Terocone
    { item = 22790, ratePerHour = 30, skill = "herb", minSkill = 340, zone = "Höhlen der Scherbenwelt" },     -- Ancient Lichen
    { item = 22791, ratePerHour = 50, skill = "herb", zone = "Nethersturm" },                                 -- Netherbloom
    { item = 22792, ratePerHour = 40, skill = "herb", zone = "Schattenmondtal" },                             -- Nightmare Vine
    { item = 22793, ratePerHour = 40, skill = "herb", minSkill = 375, zone = "Schergrat / Netherschwingenscherbe" }, -- Mana Thistle
    { item = 23424, ratePerHour = 60, skill = "mining", zone = "Höllenfeuerhalbinsel / Zangarmarschen" },     -- Fel Iron Ore
    { item = 23425, ratePerHour = 40, skill = "mining", zone = "Nagrand / Schergrat" },                       -- Adamantite Ore
    { item = 23426, ratePerHour = 5,  skill = "mining", minSkill = 375, zone = "seltene Vorkommen in Adamantit-Gebieten" }, -- Khorium Ore
    { item = 21877, ratePerHour = 120, zone = "Humanoide in der Scherbenwelt" },                              -- Netherweave Cloth
    { item = 21887, ratePerHour = 60, skill = "skinning", zone = "Talbuks und Klufthufe in Nagrand" },        -- Knothide Leather
    { item = 21884, ratePerHour = 4, zone = "Elementarplateau / Feuerelementare in Nagrand" },                -- Primal Fire
    { item = 21885, ratePerHour = 3, zone = "Elementarplateau / Zangarmarschen" },                            -- Primal Water
    { item = 22451, ratePerHour = 3, zone = "Elementarplateau / Windelementare" },                            -- Primal Air
    { item = 22452, ratePerHour = 5, zone = "Elementarplateau / Nagrand" },                                   -- Primal Earth
    { item = 22456, ratePerHour = 4, zone = "Leerwandler bei Auchindoun / Nagrand" },                         -- Primal Shadow
    { item = 22457, ratePerHour = 3, zone = "Manawyrms im Nethersturm" },                                     -- Primal Mana
    { item = 13468, ratePerHour = 1, skill = "herb", minSkill = 300, zone = "seltene Spawns in Silithus, Winterquell, Östliche Pestländer" }, -- Black Lotus
    { item = 12363, ratePerHour = 2, skill = "mining", zone = "Thoriumadern in Un'Goro, Winterquell, Silithus" }, -- Arcane Crystal
    { item = 14047, ratePerHour = 100, zone = "Humanoide ab Stufe 50" },                                      -- Runecloth
}

-- Skill-Zeilen des Fertigkeitenfensters, deutsch und englisch, zum Abgleich
-- mit FARM_CATALOG.skill.
C.SKILL_NAMES = {
    herb = { "Kräuterkunde", "Herbalism" },
    mining = { "Bergbau", "Mining" },
    skinning = { "Kürschnerei", "Skinning" },
}

-- Level-70-Tagesquests der Anniversary-Phase 3 (Patch 2.1: Ogri'la und
-- Skyguard). gold ist der Gesamterlös auf Stufe 70 inklusive der
-- XP-Kompensation. pre: letzte Quest der Freischaltungskette - ist sie nicht
-- abgeschlossen, kann der Charakter die Daily noch gar nicht annehmen.
-- Quest-IDs gegen die Questie-Datenbank geprueft.
C.DAILY_QUESTS = {
    { quest = 11023, pre = 11010, gold = 119900, name = "Bombardiert sie noch mal!", zone = "Schergrat (Ogri'la)" },
    { quest = 11051, pre = 11026, gold = 119900, name = "Verbannt noch mehr Dämonen", zone = "Schergrat (Ogri'la)" },
    { quest = 11066, pre = 11065, gold = 119900, name = "Fangt noch mehr Ätherrochen ein!", zone = "Schergrat (Himmelswache)" },
    { quest = 11080, pre = 11058, gold = 91000,  name = "Die Ausstrahlung des Relikts", zone = "Schergrat (Ogri'la)" },
    { quest = 11008, pre = 11098, gold = 119900, name = "Feuer über Skettis", zone = "Wälder von Terokkar (Skettis)" },
    { quest = 11085, pre = 11098, gold = 91000,  name = "Flucht aus Skettis", zone = "Wälder von Terokkar (Skettis)" },
}
