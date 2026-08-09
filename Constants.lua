local addonName, GCP = ...

GCP.Constants = {
    VERSION = "0.5.0",

    -- Fraktionsauktionshaus behaelt 5 % des Verkaufspreises ein.
    AH_CUT = 0.05,

    -- Tagesplan-Eintraege unter diesem Gewinn (Kupfer) sind Zeitverschwendung
    -- und fliegen raus; ueberschreibbar via options.minRoadmapValue.
    MIN_ROADMAP_VALUE = 50000,

    -- Standard-Tagesziel (Kupfer), einstellbar in den Optionen.
    DEFAULT_DAILY_GOAL = 5000000,

    -- Item-Klassen, die im Plan nie zum Verkauf vorgeschlagen werden:
    -- Traenke, Elixiere, Essen. Wer 40 Manatraenke im Beutel hat, hat sie
    -- fuer den Raid da - der Verkaufen-Tab zeigt ihren Wert trotzdem an.
    CLASS_CONSUMABLE = 0,

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

-- ---------------------------------------------------------------------------
-- Market Engine (0.5.0). Alle Stellschrauben der Markthistorie und des Market
-- Scores stehen hier zusammen, damit sie sich anhand echter Realm-Daten
-- nachjustieren lassen, ohne die Logik anzufassen.
-- ---------------------------------------------------------------------------
C.MARKET = {
    -- Formatversion von db.marketHistory. Erhoehen, wenn sich das Layout so
    -- aendert, dass alte Daten nicht mehr lesbar sind - dann wird der Speicher
    -- verworfen (und nur der, nichts anderes).
    STORE_VERSION = 1,

    -- Speicherbegrenzung. Die drei Zahlen zusammen bestimmen die Obergrenze:
    -- MAX_TRACKED_ITEMS x MAX_SNAPSHOTS_PER_ITEM Zahlenpaare.
    SNAPSHOT_INTERVAL = 1800,        -- fruehestens alle 30 Minuten je Item
    IDENTICAL_SKIP = 7200,           -- unveraenderter Preis: hoechstens alle 2 h
    RETENTION_DAYS = 30,
    MAX_SNAPSHOTS_PER_ITEM = 400,    -- ~13 Punkte/Tag ueber 30 Tage
    MAX_TRACKED_ITEMS = 500,
    PRUNE_INTERVAL = 3600,           -- Aufraeumen hoechstens stuendlich

    -- Laufzeit-Drosselung, damit ein Auctionator-Scan nicht hunderte
    -- Schreibdurchlaeufe ausloest.
    DB_UPDATE_DEBOUNCE = 20,         -- Sekunden nach dem letzten DB-Update
    RECORD_INTERVAL = 60,            -- Mindestabstand zweier voller Durchlaeufe
    TRACKED_CACHE_SECONDS = 60,
    -- Grosszuegig: Die Statistik eines Items wird ohnehin verworfen, sobald ein
    -- neuer Messpunkt dazukommt. Diese Frist faengt nur das Wandern der
    -- Zeitfenster ab - und ein 24-Stunden-Fenster verschiebt sich in einer
    -- Viertelstunde nicht nennenswert.
    STATS_CACHE_SECONDS = 900,

    -- Plausibilitaetsgrenzen: alles ausserhalb ist kein Preis, sondern ein Bug.
    MIN_PRICE = 1,
    MAX_PRICE = 1e12,

    -- Ab wann ist ueberhaupt ein Score verantwortbar? Unter drei Messpunkten
    -- gibt es keine Verteilung, in die sich der aktuelle Preis einordnen liesse.
    MIN_SCORE_SNAPSHOTS = 3,

    -- Datenqualitaet. Beides muss erfuellt sein: Tage ohne Snapshots waeren
    -- luftig, Snapshots ohne Tage nur eine einzige Sitzung.
    CONFIDENCE = {
        MEDIUM_DAYS = 3, MEDIUM_SNAPSHOTS = 5,
        HIGH_DAYS = 7, HIGH_SNAPSHOTS = 10,
    },

    -- Market-Score-Formel, ausfuehrlich dokumentiert in Market.lua.
    SCORE = {
        PERCENTILE_WEIGHT = 0.55,
        DISCOUNT_WEIGHT = 0.45,
        MEDIAN7_SHARE = 0.4,
        MEDIAN30_SHARE = 0.6,
        DISCOUNT_SPAN = 100,         -- 1 % Abstand zum Median = 1 Punkt
        VOLATILITY_CAP = 0.6,
        VOLATILITY_DAMPING = 0.25,
        -- Zieht den Score bei duenner Datenlage Richtung 50 (= "keine Aussage").
        CONFIDENCE_FACTOR = { none = 0, low = 0.35, medium = 0.7, high = 1 },
    },

    -- Visuelle Einordnung. Ausdruecklich keine Kauf-/Verkaufsempfehlung: 0.5
    -- kennt weder Nachfrage noch Liquiditaet.
    BANDS = {
        { min = 90, label = "außergewöhnlich günstig" },
        { min = 75, label = "interessant" },
        { min = 50, label = "normal" },
        { min = 25, label = "teuer" },
        { min = 0,  label = "sehr teuer" },
    },

    CONFIDENCE_LABEL = {
        none = "keine Daten",
        low = "niedrig",
        medium = "mittel",
        high = "hoch",
    },
}

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
    cooking = { "Kochkunst", "Cooking" },
    fishing = { "Angeln", "Fishing" },
}

-- Geschaetzter Zeitaufwand je Aufgabenart in Minuten. Nur damit laesst sich
-- "der schnellste Weg zum Tagesziel" ueberhaupt sortieren: Gold allein sagt
-- nichts, Gold je Minute schon.
C.MINUTES = {
    sell = 3,
    craft = 2,
    cooldown = 2,
    flip = 5,
    farm = 60,
    questlog = 8,
}

-- Tagesquests, gruppiert nach Questgeber. Viele NPCs bieten pro Tag genau
-- eine Quest aus einem Pool an (oneOf = true) - dafuer steht eine Zeile im
-- Plan, nicht fuenfzehn. Die Ogri'la-/Himmelswache-Quests sind dagegen alle
-- gleichzeitig annehmbar und bekommen je eine Zeile.
--
-- gold ist eine Schaetzung. Den echten Betrag lernt das Addon beim ersten
-- Abgeben (QUEST_TURNED_IN liefert ihn) und rechnet danach damit; bis dahin
-- steht "ca." an der Zeile. Alle Quest- und NPC-IDs stammen aus der lokalen
-- Questie-Datenbank.
C.DAILY_POOLS = {
    {
        key = "ogrila", label = "Ogri'la & Himmelswache", oneOf = false,
        minLevel = 70, minutes = 8,
        note = "Flugmount nötig",
        quests = {
            { id = 11023, pre = 11010, gold = 119900, name = "Bombardiert sie noch mal!", zone = "Schergrat (Ogri'la)" },
            { id = 11051, pre = 11026, gold = 119900, name = "Verbannt noch mehr Dämonen", zone = "Schergrat (Ogri'la)" },
            { id = 11066, pre = 11065, gold = 119900, name = "Fangt noch mehr Ätherrochen ein!", zone = "Schergrat (Himmelswache)" },
            { id = 11080, pre = 11058, gold = 91000,  name = "Die Ausstrahlung des Relikts", zone = "Schergrat (Ogri'la)" },
            { id = 11008, pre = 11098, gold = 119900, name = "Feuer über Skettis", zone = "Wälder von Terokkar (Skettis)" },
            { id = 11085, pre = 11098, gold = 91000,  name = "Flucht aus Skettis", zone = "Wälder von Terokkar (Skettis)" },
        },
    },
    {
        key = "dungeon", label = "Dungeon-Daily (normal)", oneOf = true,
        minLevel = 70, minutes = 30, gold = 96000,
        zone = "Shattrath, Unterstadt – Netherpirscher Mah'duun",
        quests = { 11364, 11371, 11376, 11383, 11385, 11387, 11389, 11500 },
    },
    {
        key = "heroic", label = "Dungeon-Daily (heroisch)", oneOf = true,
        minLevel = 70, minutes = 45, gold = 119900,
        note = "nur heroisch",
        zone = "Shattrath, Unterstadt – Windhändler Zhareem",
        quests = {
            11354, 11362, 11363, 11368, 11369, 11370, 11372, 11373,
            11374, 11375, 11378, 11382, 11384, 11386, 11388, 11499,
        },
    },
    {
        key = "cooking", label = "Kochkunst-Daily", oneOf = true,
        minLevel = 70, minutes = 15, gold = 44000,
        skill = "cooking", minSkill = 275,
        zone = "Shattrath, Unterstadt – Der Rokk",
        quests = { 11377, 11379, 11380, 11381 },
    },
    {
        key = "fishing", label = "Angel-Daily", oneOf = true,
        minLevel = 70, minutes = 15, gold = 44000,
        skill = "fishing", minSkill = 1,
        zone = "Wälder von Terokkar – Silmyrsee, der alte Barlo",
        quests = { 11665, 11666, 11667, 11668, 11669 },
    },
}
