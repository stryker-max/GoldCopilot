local addonName, GCP = ...

GCP.Constants = {
    VERSION = "0.1.0",

    -- Fraktionsauktionshaus behaelt 5 % des Verkaufspreises ein.
    AH_CUT = 0.05,

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

-- Kuratierte Farm-Ziele fuer den Tagesplan. Die Reihung im Plan ergibt sich aus
-- dem aktuellen Marktpreis, nicht aus dieser Liste. stack: uebliche Stapelgroesse
-- fuer die Anzeige "Gold je Stapel".
C.FARM_CATALOG = {
    { item = 22785, stack = 20, zone = "Höllenfeuerhalbinsel (überall in der Scherbenwelt)" }, -- Felweed
    { item = 22786, stack = 20, zone = "Höllenfeuerhalbinsel / Wälder von Terokkar" },         -- Dreaming Glory
    { item = 22787, stack = 20, zone = "Zangarmarschen" },                                     -- Ragveil
    { item = 22788, stack = 20, zone = "Zangarmarschen (Pilzhöhlen)" },                        -- Flame Cap
    { item = 22789, stack = 20, zone = "Wälder von Terokkar" },                                -- Terocone
    { item = 22790, stack = 20, zone = "Höhlen der Scherbenwelt" },                            -- Ancient Lichen
    { item = 22791, stack = 20, zone = "Nethersturm" },                                        -- Netherbloom
    { item = 22792, stack = 20, zone = "Schattenmondtal" },                                    -- Nightmare Vine
    { item = 22793, stack = 20, zone = "Schergrat / Netherschwingenscherbe (Kräuterkunde 375)" }, -- Mana Thistle
    { item = 23424, stack = 20, zone = "Höllenfeuerhalbinsel / Zangarmarschen" },              -- Fel Iron Ore
    { item = 23425, stack = 20, zone = "Nagrand / Schergrat" },                                -- Adamantite Ore
    { item = 23426, stack = 20, zone = "seltene Vorkommen in Adamantit-Gebieten" },            -- Khorium Ore
    { item = 21877, stack = 20, zone = "Humanoide in der Scherbenwelt" },                      -- Netherweave Cloth
    { item = 21887, stack = 20, zone = "Talbuks und Klufthufe in Nagrand" },                   -- Knothide Leather
    { item = 21884, stack = 20, zone = "Elementarplateau / Feuerelementare in Nagrand" },      -- Primal Fire
    { item = 21885, stack = 20, zone = "Elementarplateau / Zangarmarschen" },                  -- Primal Water
    { item = 22451, stack = 20, zone = "Elementarplateau / Windelementare" },                  -- Primal Air
    { item = 22452, stack = 20, zone = "Elementarplateau / Nagrand" },                         -- Primal Earth
    { item = 22456, stack = 20, zone = "Leerwandler bei Auchindoun / Nagrand" },               -- Primal Shadow
    { item = 22457, stack = 20, zone = "Manawyrms im Nethersturm" },                           -- Primal Mana
    { item = 13468, stack = 1,  zone = "seltene Spawns in Silithus, Winterquell, Ostliche Pestländer" }, -- Black Lotus
    { item = 12363, stack = 20, zone = "Thoriumadern in Un'Goro, Winterquell, Silithus" },     -- Arcane Crystal
    { item = 14047, stack = 20, zone = "Humanoide ab Stufe 50" },                              -- Runecloth
}
