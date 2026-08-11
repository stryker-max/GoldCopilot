local addonName, GCP = ...

GCP.Constants = {
    VERSION = "1.0.0-beta.9",

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

    -- 10 Partikel ergeben per Rechtsklick 1 Urelement (10x Lebenspartikel ->
    -- 1x Urleben); der Weg zurueck existiert nicht.
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

    -- ---------------------------------------------------------------------
    -- MARKTTIEFE (0.9.0). Datenquelle ist ausschliesslich das, was der Spieler
    -- selbst im Auktionshaus durchblaettert - der Client gibt Angebotsmengen
    -- nur fuer die gerade angezeigte Liste heraus. Auctionator liefert Preise,
    -- keine Mengen; nichts davon wird hochgerechnet.
    -- ---------------------------------------------------------------------
    DEPTH = {
        STORE_VERSION = 1,
        MAX_ITEMS = 200,
        MAX_HISTORY = 24,           -- Mengenverlauf je Item
        MAX_LEVELS = 6,             -- gespeicherte Preisstufen
        RETENTION_DAYS = 14,
        MIN_INTERVAL = 900,         -- je Item hoechstens alle 15 Minuten
        -- "In der Naehe des Marktpreises" heisst: bis zu so viel ueber dem
        -- guenstigsten Angebot.
        NEAR_MARKET = 0.10,

        -- Marktstruktur-Signale. Ausdruecklich BESCHREIBUNGEN, keine
        -- Unterstellungen: Warum jemand so anbietet, weiss niemand.
        THIN_LISTINGS = 3,
        THIN_QUANTITY = 5,
        SHOCK_FACTOR = 3,           -- dreifache Menge gegenueber dem Median
        SHOCK_MIN_HISTORY = 4,
        WALL_SHARE = 0.6,           -- eine Preisstufe haelt 60 % der Menge
        WALL_MIN_LISTINGS = 4,
        OUTLIER_RATIO = 0.6,        -- guenstigstes Angebot 40 % unter dem naechsten
        OUTLIER_MIN_LEVELS = 3,
        CONCENTRATION_SHARE = 0.7,
        CONCENTRATION_MIN_LISTINGS = 5,
        -- Ab dieser Angebotsmenge gegenueber dem Median gilt der Markt als
        -- ueberversorgt; die Positionsgroesse faellt dann kleiner aus.
        GLUT_FACTOR = 2,
        -- Wie frisch muss eine Tiefenmessung sein, damit sie eine Stueckzahl
        -- begrenzen darf? Eine zwei Tage alte Angebotsmenge sagt nichts
        -- darueber, was heute im Auktionshaus liegt.
        MAX_UNITS_FRESHNESS = 2 * 3600,
    },

    -- Watchlist (0.6.0). Sie ist die technische Grundlage fuer Future Market
    -- 0.7 und laeuft ueber db.watchlist; beobachtete Items landen mit hoechster
    -- Prioritaet in Market:GetTrackedItems(). Der Deckel verhindert, dass eine
    -- versehentlich vollgeklickte Liste die Aufzeichnung verdraengt.
    MAX_WATCH_ITEMS = 100,
}

-- ---------------------------------------------------------------------------
-- Ledger / Liquidity Brain (0.8.0). Alle Stellschrauben der persoenlichen
-- Handelsbilanz stehen hier zusammen; die Formeln selbst sind in Ledger.lua
-- ausfuehrlich hergeleitet. In dieser Datei steht keine einzige Aussage
-- darueber, wie schnell sich irgendein Item verkauft - das lernt das Addon
-- ausschliesslich aus den eigenen Verkaeufen des Nutzers.
-- ---------------------------------------------------------------------------
C.LEDGER = {
    -- Formatversion von db.ledger. Erhoehen, wenn sich das Layout so aendert,
    -- dass alte Daten nicht mehr lesbar sind - dann wird nur dieser Speicher
    -- verworfen, nichts anderes.
    STORE_VERSION = 1,

    -- Speicherstrategie. Rohereignisse sind das Kurzzeitgedaechtnis (60 Tage
    -- fuer die 7- und 30-Tage-Ansicht), die Aggregate je Item das
    -- Langzeitgedaechtnis - sie werden nie nach Alter verworfen, nur nach
    -- Anzahl. Beides zusammen ist hart gedeckelt.
    RETENTION_DAYS = 60,
    MAX_EVENTS = 4000,
    MAX_ITEMS = 400,
    MAX_SAMPLES = 60,               -- Stichproben je Reihe und Item
    MAX_OPEN_POSTINGS = 250,
    MAX_MAIL_KEYS = 800,            -- Abgleichindex des Briefkastens
    -- Eine Auktion laeuft hoechstens 48 h, die zugehoerige Post liegt danach
    -- bis zu 30 Tage im Briefkasten. Erst danach ist eine offene Einstellung
    -- sicher nicht mehr zuzuordnen.
    OPEN_POSTING_TTL = 35 * 86400,
    PRUNE_INTERVAL = 3600,

    -- Relisting: Laeuft eine Auktion ab und wird dasselbe Item innerhalb
    -- dieser Frist erneut eingestellt, gilt das als Fortsetzung derselben
    -- Position. Nur dafuer - die Fehlschlaege zaehlen trotzdem einzeln.
    RELIST_WINDOW = 48 * 3600,

    -- Datenqualitaet der Sell-Through-Rate. Beide Bedingungen muessen erfuellt
    -- sein: Auktionen ohne Stueckzahl waeren eine duenne Stichprobe, Stueckzahl
    -- ohne Auktionen nur ein einziger grosser Stapel.
    CONFIDENCE = {
        MEDIUM_AUCTIONS = 6,  MEDIUM_UNITS = 20,
        HIGH_AUCTIONS = 20,   HIGH_UNITS = 100,
    },

    -- Liquidity Score. Herleitung in Ledger.lua.
    SCORE = {
        SELL_THROUGH_POINTS = 55,
        -- 90 % Sell-Through zaehlen als volle Punktzahl. Darueber gibt es
        -- nichts mehr: Der Unterschied zwischen 90 % und 100 % ist Rauschen,
        -- und 100 % zu verlangen hiesse, dass kein reales Item gut abschneidet.
        SELL_THROUGH_TARGET = 0.9,

        SPEED_POINTS = 30,
        SPEED_HALF_HOURS = 24,      -- Median von einem Tag = halbe Punktzahl

        REPEAT_POINTS = 15,
        REPEAT_HALF_PER_WEEK = 3,   -- drei Verkaeufe je Woche = halbe Punktzahl

        -- Eine duenne Stichprobe kann nie "sehr liquide" ergeben.
        CONFIDENCE_CAP = { none = 0, low = 55, medium = 80, high = 100 },
    },

    -- Profit Velocity.
    VELOCITY = {
        -- Untergrenze der Haltedauer. Ohne sie explodiert die Rate, sobald ein
        -- Item einmal in zehn Minuten weg war.
        MIN_HOLDING_HOURS = 2,
        -- Bezugsgroesse der verstaendlichen Kennzahl: "Gewinn je 100 g
        -- gebundenem Kapital und Tag".
        REFERENCE_CAPITAL = 1000000,
    },

    -- Einordnung des Liquidity Scores in Worte.
    BANDS = {
        { min = 80, label = "sehr liquide" },
        { min = 60, label = "liquide" },
        { min = 40, label = "mittel" },
        { min = 20, label = "zäh" },
        { min = 0,  label = "sehr zäh" },
    },

    -- Zuordnung Verkauf -> Einstellung. Mehr dazu in Ledger.lua; "exact" heisst
    -- Preis und Stueckzahl gehen auf, "unique" heisst genau eine offene
    -- Einstellung dieses Items.
    MATCH = { NONE = 0, UNIQUE = 1, EXACT = 2 },

    -- Ereignisprotokoll des Handel-Tabs.
    MAX_RECENT_TRADES = 40,
}

-- ---------------------------------------------------------------------------
-- PREIS-PLAUSIBILITAET (1.0.0-beta.3)
--
-- Die Preisquelle liefert den GUENSTIGSTEN BUYOUT des letzten Scans. Liegt zu
-- einem Item genau eine Auktion im Haus, ist dieser Preis der Wunsch eines
-- einzelnen Verkaeufers und keine Marktaussage. Der 7-Tage-Median haelt dagegen
-- weniger, als er verspricht: Steht dieselbe Auktion sieben Tage lang da, ist
-- sein Median genau dieser eine Wunsch - siebenmal abgeschrieben.
--
-- Das ist der Grund, warum ein Addon einem "Einfache Leinenstiefel herstellen,
-- +94 g, 105.841 % ROI" vorschlagen kann. Die Rechnung ist richtig. Die
-- Eingangszahl ist es nicht.
--
-- Geprueft wird deshalb nicht der Preis gegen einen erfundenen "wahren Wert" -
-- den kennt niemand -, sondern gegen zwei Anker, die es wirklich gibt:
--
--   1. Der Haendlerpreis. Er steht im Client, gilt serverweit und laesst sich
--      nicht faelschen. Ein AH-Preis weit jenseits davon KANN echt sein
--      (Rezepte, Mats mit Haendlerwert null), deshalb ist der Faktor hoch
--      angesetzt und die Pruefung entfaellt bei Haendlerwert null.
--   2. Die Materialkosten eines Crafts. Wer das Rezept hat, kann jederzeit
--      unterbieten; ein Produkt, das dauerhaft das Zwanzigfache seiner
--      Zutaten bringt, haette laengst Konkurrenz. Bleibt sie aus, liegt das
--      meistens nicht am Markt, sondern daran, dass es keinen gibt.
--
-- BEIDE Pruefungen greifen nur, wenn es keinen Gegenbeleg gibt. Gegenbelege
-- sind ein eigener bestaetigter Verkauf (dann hat wirklich jemand gezahlt) und
-- ein nachweislich besetzter Markt (mehrere Anbieter, also echte Konkurrenz).
-- Ein Item mit Beleg wird nie ausgeblendet, egal wie hoch sein Preis steht.
-- ---------------------------------------------------------------------------
C.PRICE_SANITY = {
    -- Unterhalb dieses Betrags wird gar nicht gezweifelt, und das aus einem
    -- handfesten Grund: Ein Vielfaches ist bei billiger Ware nichts wert. Eine
    -- Knusperschlange bringt 2 Kupfer beim Haendler und 80 Silber im
    -- Auktionshaus - das Viertausendfache, und trotzdem voellig normal. Absurd
    -- ist erst die Kombination aus grossem Faktor UND grossem Betrag; die
    -- gemeldeten Leinenstiefel standen bei 99 Gold.
    --
    -- Eine Zeile unterhalb dieses Betrags kann ohnehin keine Route verderben -
    -- dafuer gibt es den Mindestprofit.
    MIN_ABSURD_PRICE = 50000,       -- 5 g

    -- Ab dem Wievielfachen des Haendlerpreises ist ein AH-Preis ohne Beleg
    -- verdaechtig? Bewusst grosszuegig: Echte Ausreisser dieser Art liegen beim
    -- Tausendfachen, normale Ausruestung bei Faktor 5 bis 50.
    VENDOR_FACTOR = 200,

    -- ...und nur bei AUSRUESTUNG. Bei Rohstoffen ist der Haendlerpreis kein
    -- Anker, sondern Zufall: Adamantiterz bringt 25 Kupfer beim Haendler und
    -- 10 Gold im Auktionshaus - das Viertausendfache, und der voellige
    -- Normalfall. Blizzard setzt den Haendlerwert von Handwerkswaren und
    -- Verbrauchbarem bewusst nahe null, ihr Preis entsteht ausschliesslich aus
    -- der Nachfrage.
    --
    -- Bei Waffen und Ruestung ist es umgekehrt: Dort haengt der Haendlerwert an
    -- Gegenstandsstufe und Qualitaet und waechst mit ihnen mit. Nur deshalb
    -- traegt der Vergleich hier ueberhaupt.
    VENDOR_CLASSES = { [2] = true, [4] = true },    -- Waffe, Ruestung

    -- Dasselbe fuer Crafts, gemessen am Materialeinsatz. Faktor 25 heisst
    -- 2400 % ROI - alles darunter bleibt unangetastet.
    CRAFT_FACTOR = 25,

    -- Wie viele verschiedene Angebote gelten als "besetzter Markt"? Unterhalb
    -- davon gibt es keine Konkurrenz, die einen Preis korrigieren wuerde.
    MIN_LISTINGS = 3,

    -- Wie alt darf die Tiefenmessung sein, damit sie als Gegenbeleg zaehlt?
    -- Laenger als einen Tag sagt sie nichts ueber das aktuelle Angebot.
    MAX_DEPTH_AGE = 86400,

    -- ------------------------------------------------------------------
    -- IST DAS ITEM UEBERHAUPT ZU HABEN? (1.0.0-beta.4)
    --
    -- Ein Preis heisst nicht, dass gerade jemand verkauft. Auctionator
    -- antwortet aus seiner gespeicherten Scandatenbank und liefert auch dann
    -- einen Preis, wenn das Item seit Tagen in keinem Scan mehr aufgetaucht
    -- ist. Ein Routenschritt "20x Teufelsstoffschultern kaufen" ist wertlos,
    -- wenn im Auktionshaus keine einzige liegt.
    --
    -- Das Alter je Item kennt Auctionator (GetAuctionAgeByItemID), ein
    -- globales Scandatum nicht. Beides zusammen ergibt aber die Antwort:
    -- Verglichen wird das Alter des Items mit dem Alter eines Referenzguts,
    -- das in praktisch jedem Scan vorkommt. Ist das Item deutlich aelter, war
    -- es bei den letzten Scans nicht dabei - also liegt keines im Haus.
    --
    -- Die Unterscheidung ist wichtig, weil ein hohes Alter zwei Ursachen hat:
    -- Das Item fehlt, ODER es wurde lange nicht gescannt. Nur der Vergleich
    -- trennt die beiden Faelle. Ohne Referenz wird deshalb gar nicht geurteilt.
    SCAN_REFERENCE_ITEM = 21877,    -- Netherstoffballen, wie in Roadmap.lua

    -- Wie viele Tage aelter als der letzte Scan macht ein Item "nicht im
    -- Angebot"? Zwei Tage lassen Raum fuer Teilscans und einzelne
    -- Suchdurchlaeufe, die nicht das ganze Haus erfassen.
    ABSENT_AFTER_DAYS = 2,
}

-- ---------------------------------------------------------------------------
-- Opportunity Engine (0.6.0). Alle Stellschrauben der Chancen-Bewertung stehen
-- hier zusammen, damit sie sich an echten Realm-Daten kalibrieren lassen, ohne
-- die Logik in Opportunity.lua anzufassen. Die Formel selbst ist dort
-- ausfuehrlich hergeleitet.
-- ---------------------------------------------------------------------------
C.OPPORTUNITY = {
    -- Punktebudget des Opportunity Scores. Die vier Gutschriften summieren sich
    -- auf genau 100, die beiden Abschlaege ziehen bis zu 30 Punkte ab.
    SCORE = {
        -- Kapitaleffizienz. Saettigungskurve p * roi / (roi + ROI_HALF):
        -- bei ROI_HALF gibt es die halbe Punktzahl, danach flacht sie ab.
        -- Eine 500-%-Chance ist besser als eine 50-%-Chance, aber nicht
        -- zehnmal so gut - jenseits davon entscheidet die Datenlage.
        MARGIN_POINTS = 35,
        ROI_HALF = 0.25,

        -- Absolute Groesse. Getrennt von der ROI, weil beides verschiedene
        -- Fragen beantwortet: 80 % auf 50 g sind ein guter Schnitt, 5 % auf
        -- 500 g sind eine andere Art Geschaeft. Halbe Punktzahl bei 10 g.
        PROFIT_POINTS = 15,
        PROFIT_HALF = 100000,

        -- Marktlage der Kaufseite: der Market Score aus 0.5.0, unveraendert
        -- uebernommen. Fehlt er (zu wenig Historie), zaehlt bewusst 50 -
        -- "keine Aussage", nicht "schlecht".
        MARKET_POINTS = 25,
        NEUTRAL_MARKET_SCORE = 50,

        -- Datenqualitaet als eigener Summand. Score und Confidence bleiben
        -- daneben getrennt ausgewiesen.
        CONFIDENCE_POINTS = { none = 0, low = 8, medium = 17, high = 25 },
        -- ... und zusaetzlich als harte Obergrenze: eine duenne Datenbasis
        -- kann nie "sehr interessant" ergeben, egal wie gut die Rechnung
        -- aussieht.
        CONFIDENCE_CAP = { none = 0, low = 55, medium = 80, high = 100 },

        -- Risiko durch Schwankung. Volatilitaet ist der Quartilsabstand am
        -- Median (siehe Market.lua); ab VOLATILITY_CAP wird nicht weiter
        -- bestraft, sonst dominiert ein einzelner Ausreisser die Bewertung.
        VOLATILITY_PENALTY = 15,
        VOLATILITY_CAP = 0.6,

        -- Kapitalbedarf. Gebundenes Gold ist Risiko und fehlt anderswo;
        -- halber Abschlag bei 250 g Einsatz.
        CAPITAL_PENALTY = 15,
        CAPITAL_HALF = 2500000,

        -- Liquiditaet (0.8.0). Bewusst ein Zuschlag/Abschlag auf den
        -- bestehenden Score statt eines neuen Summanden im Budget: Ohne eigene
        -- Verkaufsdaten bleibt die Bewertung aus 0.6 Punkt fuer Punkt
        -- unveraendert, und mit Daten verschiebt sie sich um hoechstens 15
        -- Punkte. Das Gewicht haengt an der Stichprobengroesse - zwei
        -- Auktionen duerfen keine Chance zerstoeren.
        LIQUIDITY_POINTS = 15,
        LIQUIDITY_NEUTRAL = 55,
        LIQUIDITY_SPAN = 50,
        LIQUIDITY_WEIGHT = { none = 0, low = 0.25, medium = 0.65, high = 1.0 },
    },

    -- Sortiermodi des Chancen-Tabs (0.8.0). "score" bleibt der Standard: Die
    -- Liquiditaet steckt seit 0.8 im Score selbst, deshalb braucht es keine
    -- automatische Umschaltung, die je nach Datenlage hin und her springt.
    SORT_MODES = { "score", "velocity", "liquidity", "profit", "roi" },
    SORT_LABEL = {
        score = "Opportunity Score",
        velocity = "Profit Velocity",
        liquidity = "Liquidität",
        profit = "Profit",
        roi = "ROI",
    },

    -- Einordnung in Worte. Bewusst kein "KAUFEN": Liquiditaet und
    -- Verkaufsdauer kennt auch 0.6 noch nicht.
    BANDS = {
        { min = 80, label = "sehr interessant" },
        { min = 60, label = "interessant" },
        { min = 40, label = "beobachten" },
        { min = 0,  label = "geringe Priorität" },
    },

    TYPE_LABEL = {
        conversion = "Conversion",
        craft = "Craft",
        disenchant = "Entzaubern",
        resale = "Resale",
    },

    -- Preisbasis (Tageswerte aus Prices:GetPlanningPrice) -> Confidence-Stufe.
    -- 0 Tageswerte heisst "echter Momentanpreis, aber keine Historie" - das ist
    -- niedrige Sicherheit, nicht "keine Daten".
    PRICE_CONFIDENCE = { MEDIUM_DAYS = 3, HIGH_DAYS = 6 },

    -- Resale setzt einen belastbaren Market Score voraus. Darunter ist ein
    -- Preis nicht "guenstig", sondern nur "irgendwo in seiner Spanne".
    RESALE_MIN_SCORE = 70,

    -- Standardfilter. Bewusst getrennt von options.minRoadmapValue: Der
    -- Tagesplan filtert Aufgaben, die Chancen filtern Kapitaleinsatz.
    -- Voreingestellt niedriger als der Mindestgewinn des Tagesplans: Ein
    -- 2-Gold-Flip ist kein Tagesplan-Eintrag, aber eine Chance - der Filter
    -- soll den 3-Silber-Kram ausblenden, nicht die halbe Liste.
    DEFAULT_MIN_PROFIT = 10000,      -- 1 g
    DEFAULT_MIN_ROI = 0.05,          -- 5 %

    MAX_ROWS = 60,
    -- Kurzer Cache gegen mehrfaches Scannen je Frame-Refresh. Zusaetzlich
    -- haengt der Cache an einer Signatur aus Marktstand, Rezepten und Optionen.
    CACHE_SECONDS = 30,

    -- Prediction Tracking. Aufgeschrieben wird zurueckhaltend: nur belastbare
    -- Chancen, nur wenn sie neu sind oder sich merklich bewegt haben.
    HISTORY = {
        RETENTION_DAYS = 90,
        MAX_ENTRIES = 400,
        MIN_INTERVAL = 21600,        -- dieselbe Chance hoechstens alle 6 h
        MIN_SCORE = 60,
        MIN_CONFIDENCE = "medium",
        SCORE_DELTA = 10,            -- Punkte
        PROFIT_DELTA = 0.25,         -- 25 % Veraenderung
        -- 0.8.0: Wie lange nach einer aufgezeichneten Chance ein Kauf noch als
        -- deren Ausfuehrung gelten darf. Drei Tage - danach hat der Kauf mit
        -- der damaligen Rechnung nichts mehr zu tun.
        MATCH_WINDOW = 3 * 86400,
    },
}

-- ---------------------------------------------------------------------------
-- Future Market / Catalyst Engine (0.7.0). Alle Stellschrauben der
-- Zukunftsbewertung stehen hier zusammen; die Formeln selbst sind in Future.lua
-- ausfuehrlich hergeleitet. Spielwissen steht ausschliesslich in Knowledge/ -
-- in dieser Datei steht keine einzige Aussage ueber den Spielinhalt.
-- ---------------------------------------------------------------------------
C.FUTURE = {
    -- Zeitfenster um einen bekannten Termin, in Tagen bis Release. Bewusst
    -- keine Regel "je naeher, desto besser": Kurz vor Release ist eine bekannte
    -- Ankuendigung meist eingepreist.
    TIMING = {
        EARLY_DAYS = 30,          -- mehr als 30 Tage: EARLY
        ACCUMULATION_DAYS = 14,   -- 14 bis 30 Tage: ACCUMULATION
        PRE_RELEASE_DAYS = 3,     -- 3 bis 13 Tage: PRE_RELEASE
        RELEASE_DAYS = 0,         -- 0 bis 2 Tage: RELEASE, danach POST_RELEASE
    },

    TIMING_LABEL = {
        EARLY = "früh",
        ACCUMULATION = "Aufbauphase",
        PRE_RELEASE = "kurz vor Release",
        RELEASE = "Releasefenster",
        POST_RELEASE = "nach Release",
        UNKNOWN = "Termin unbekannt",
    },

    -- Dependency Graph. Die Tiefenbegrenzung ist keine Optimierung, sondern
    -- eine Aussagegrenze: Nach drei Ebenen haengt jedes Material der
    -- Scherbenwelt an jedem Ereignis.
    GRAPH = {
        MAX_DEPTH = 2,
        PROPAGATION = { [0] = 1.0, [1] = 0.7, [2] = 0.4 },
        -- Schutz gegen entartete Graphen (ein Material in sehr vielen
        -- gescannten Rezepten): Ab hier werden Kanten verworfen und gezaehlt.
        MAX_EDGES_PER_NODE = 24,
    },

    DEMAND = {
        NEUTRAL = 50,
        SPAN = 50,
        -- Saettigungspunkt: Bei dieser gewichteten Summe ist die halbe
        -- Auslenkung erreicht.
        HALF = 0.7,
        -- Abnehmender Ertrag je weiterem Grund: der zweite zaehlt 60 %, der
        -- dritte 36 %.
        DIMINISHING = 0.6,
        CONFIDENCE_WEIGHT = { high = 1.0, medium = 0.75, low = 0.45 },
        SOURCE_WEIGHT = { official = 1.0, historical = 0.85, inferred = 0.6 },
        TIMING_WEIGHT = {
            EARLY = 0.65, ACCUMULATION = 1.0, PRE_RELEASE = 0.95,
            RELEASE = 0.85, POST_RELEASE = 0.45, UNKNOWN = 0.5,
        },
    },

    -- Hype: ausschliesslich aus eigenen Realm-Daten. Unter MIN_SNAPSHOTS oder
    -- MIN_DAYS gibt es keinen Score, sondern nil - "kein Hype" waere hier die
    -- gefaehrlichste Falschaussage.
    HYPE = {
        MIN_SNAPSHOTS = 6,
        MIN_DAYS = 3,
        PREMIUM_WEIGHT = 0.35, PREMIUM_SPAN = 0.35,
        PERCENTILE_WEIGHT = 0.25,
        MOMENTUM_WEIGHT = 0.25, MOMENTUM_SPAN = 0.20,
        VOLATILITY_WEIGHT = 0.15, VOLATILITY_CAP = 0.6,
    },

    SIGNAL = {
        BASE = 50,
        DEMAND_WEIGHT = 0.5,
        MARKET_WEIGHT = 0.35,
        NEUTRAL_MARKET_SCORE = 50,
        HYPE_WEIGHT = 0.6,
        HYPE_NEUTRAL = 50,
        TIMING_BONUS = {
            EARLY = 2, ACCUMULATION = 6, PRE_RELEASE = 3,
            RELEASE = 0, POST_RELEASE = -4, UNKNOWN = 0,
        },
        VOLATILITY_PENALTY = 8, VOLATILITY_CAP = 0.6,
        -- Persoenliche Liquiditaet (0.8.0). Bewusst schwach gewichtet und erst
        -- ab mittlerer Datenlage: Future Demand ist Spielwissen, Liquiditaet
        -- eine ganz andere Dimension. Sie darf die Frage "wird das gebraucht?"
        -- nicht beantworten, nur die Frage "komme ich da wieder raus?" ein
        -- wenig mit einfaerben.
        LIQUIDITY_POINTS = 8,
        LIQUIDITY_NEUTRAL = 55,
        LIQUIDITY_SPAN = 50,
        LIQUIDITY_MIN_CONFIDENCE = "medium",
        -- Ein Signal kann nie besser sein als das Wissen dahinter ...
        KNOWLEDGE_CAP = { high = 100, medium = 80, low = 60 },
        -- ... und nie besser als die Realm-Daten, gegen die es geprueft wurde.
        MARKET_CAP = { none = 55, low = 70, medium = 88, high = 100 },
    },

    -- Einordnung in Worte. Kein "KAUFEN": 0.7 kennt Liquiditaet und
    -- Verkaufsdauer weiterhin nicht.
    BANDS = {
        { min = 90, label = "außergewöhnlich interessant" },
        { min = 75, label = "interessant" },
        { min = 60, label = "beobachten" },
        { min = 40, label = "neutral" },
        { min = 25, label = "bereits teuer / schwaches Setup" },
        { min = 0,  label = "hohes Hype-Risiko / unattraktiv" },
    },

    ENTRY = {
        MIN_SNAPSHOTS = 8,
        MIN_DAYS = 3,
        BASE_DISCOUNT = 0.03,
        HYPE_DISCOUNT = 0.12,
        DONT_CHASE_PREMIUM = 0.15,
        DONT_CHASE_PERCENTILE = 80,
        DONT_CHASE_HYPE = 70,
    },

    MAX_ROWS = 40,
    CACHE_SECONDS = 30,

    -- Protokoll. Teilt sich die Tabelle mit dem Chancen-Protokoll aus 0.6.
    HISTORY = {
        MIN_INTERVAL = 21600,     -- dasselbe Item hoechstens alle 6 h
        MIN_SIGNAL = 60,
        MIN_DEMAND = 60,
        SIGNAL_DELTA = 10,
    },
}

-- ---------------------------------------------------------------------------
-- Capital Brain (0.9.0). Alle Stellschrauben der Kapitalsicht, der
-- Positionsgroesse und der Allokation stehen hier zusammen; die Herleitung
-- steht in Capital.lua. Bewusst KEINE Aussage darueber, was ein "gutes"
-- Portfolio ist - nur Obergrenzen, die verhindern, dass eine einzelne These
-- das ganze Kapital bindet.
-- ---------------------------------------------------------------------------
C.CAPITAL = {
    -- Formatversion von db.capital (Positions-Provenance und Reserve).
    STORE_VERSION = 1,

    -- Cash-Reserve. Voreingestellt prozentual: Wer 500 g hat, will keine
    -- 1000-g-Reserve, und wer 200.000 g hat, ist mit 1000 g nicht abgesichert.
    RESERVE = {
        DEFAULT_MODE = "percent",       -- "percent" | "absolute"
        DEFAULT_PERCENT = 0.20,
        DEFAULT_ABSOLUTE = 10000000,    -- 1000 g
        MAX_PERCENT = 0.9,
    },

    -- Positions-Provenance (welche Chance hat diese Position erzeugt).
    MAX_POSITION_META = 300,
    POSITION_META_TTL = 45 * 86400,

    -- Exposure-Grenzen als Anteil am investierbaren Kapital. WARN blendet einen
    -- Hinweis ein, MAX ist die harte Grenze der Allokation. Die Zahlen sind
    -- Risikopolitik, keine Marktaussage - deshalb stehen sie hier und nicht in
    -- der Logik.
    EXPOSURE = {
        ITEM     = { warn = 0.12, max = 0.20 },
        TYPE     = { warn = 0.35, max = 0.55 },
        CATALYST = { warn = 0.25, max = 0.40 },
        PHASE    = { warn = 0.35, max = 0.55 },
        GROUP    = { warn = 0.30, max = 0.50 },
    },

    EXPOSURE_LABEL = {
        item = "Item",
        type = "Chancenart",
        catalyst = "Catalyst",
        phase = "Phase",
        group = "Marktgruppe",
    },

    -- Position Sizing. BASE_SHARE ist der Anteil des investierbaren Kapitals
    -- bei einer voellig neutralen Chance; alles andere sind Faktoren darauf.
    SIZING = {
        BASE_SHARE = 0.18,
        MIN_SHARE = 0.02,
        MAX_SHARE = 0.35,           -- niemals All-In, auch nicht bei Score 100

        SCORE_NEUTRAL = 50,
        SCORE_SPAN = 50,
        SCORE_SWING = 0.60,

        CONFIDENCE_FACTOR = { none = 0.30, low = 0.50, medium = 0.80, high = 1.0 },

        LIQUIDITY_NEUTRAL = 55,
        LIQUIDITY_SPAN = 50,
        LIQUIDITY_SWING = 0.35,
        -- Ohne eigene Verkaufsdaten wird die Position kleiner, nicht groesser:
        -- "unbekannt" ist kein Freibrief.
        LIQUIDITY_UNKNOWN_FACTOR = 0.75,

        VOLATILITY_CAP = 0.6,
        VOLATILITY_PENALTY = 0.35,

        VELOCITY_BONUS = 0.20,
        VELOCITY_HALF = 20000,      -- 2 g Gewinn je 100 g und Tag = halber Bonus

        -- Zukunftssignale. Hype ueber HYPE_HOT heisst: schon gelaufen.
        DEMAND_NEUTRAL = 50,
        DEMAND_SPAN = 50,
        DEMAND_SWING = 0.20,
        HYPE_HOT = 70,
        HYPE_PENALTY = 0.30,

        -- Risikostufen des Zielmodus.
        RISK_FACTOR = { low = 0.6, medium = 1.0, high = 1.4 },

        -- Angebotslage (0.9.0, nur wenn Markttiefe gemessen wurde).
        SUPPLY_GLUT_FACTOR = 0.7,
        SUPPLY_THIN_FACTOR = 0.85,

        -- ------------------------------------------------------------------
        -- STUECKZAHL-DECKEL (1.0.0-beta.3)
        --
        -- Kapitalanteil und Exposure begrenzen einen BETRAG, keine MENGE. Bei
        -- einem 2-Gold-Item sind 20 % von 260 Gold eben 26 Stueck - die
        -- Rechnung stimmt, die Empfehlung nicht: Ob der Markt 26 Stueck
        -- aufnimmt, ist eine voellig andere Frage als ob das Gold reicht.
        --
        -- Beantworten laesst sich diese Frage nur mit Belegen, und die sind
        -- entweder eigene Verkaufsdaten (Sell-through aus dem Handel-Tab) oder
        -- eine frische Tiefenmessung im Auktionshaus. Fehlen beide - und beim
        -- ersten Kontakt mit einem Item fehlen sie immer -, gilt der
        -- vorsichtige Deckel. Er ist ausdruecklich eine Vorsichtsregel, keine
        -- Marktaussage.
        MAX_UNITS_UNPROVEN = 5,
        -- Mit belegter Liquiditaet darf es mehr sein, aber nicht beliebig
        -- viel: Auch ein gut laufendes Item hat einen Tagesumsatz.
        MAX_UNITS_PROVEN = 20,
    },

    ALLOCATOR = {
        MAX_ALLOCATIONS = 12,
        MIN_ALLOCATION = 10000,     -- unter 1 g Einsatz lohnt keine Zeile
        -- Jede weitere Allokation derselben Chancenart bekommt weniger:
        -- Diversifikation ohne kuenstliche Quote.
        TYPE_DECAY = 0.80,
        -- Ranking der Kandidaten. Profit Velocity zieht nur, wenn sie bekannt
        -- ist; sonst bleibt es beim Opportunity Score.
        VELOCITY_WEIGHT = 0.25,
        VELOCITY_HALF = 20000,
    },
}

-- ---------------------------------------------------------------------------
-- Execution Engine (0.9.0). Aktionsarten, Zeitschaetzungen und Grenzen des
-- Aktionsgraphen. Die Minutenwerte sind bewusst grobe Bedienzeiten des
-- Spielers, keine Behauptung ueber Reisewege - der Reiseweg steht in
-- ROUTE.TRAVEL.
-- ---------------------------------------------------------------------------
C.EXECUTION = {
    TYPES = {
        "GO_TO", "BUY", "SELL", "CRAFT", "CONVERT", "DISENCHANT",
        "BANK_WITHDRAW", "BANK_DEPOSIT", "MAIL", "FARM",
        "VENDOR_BUY", "VENDOR_SELL", "POST_AUCTION", "WAIT", "WATCH",
    },

    TYPE_LABEL = {
        GO_TO = "Gehe zu", BUY = "Kaufen", SELL = "Verkaufen",
        CRAFT = "Herstellen", CONVERT = "Umwandeln", DISENCHANT = "Entzaubern",
        BANK_WITHDRAW = "Aus der Bank holen", BANK_DEPOSIT = "In die Bank legen",
        MAIL = "Post", FARM = "Farmen", VENDOR_BUY = "Beim Händler kaufen",
        VENDOR_SELL = "An den Händler verkaufen", POST_AUCTION = "Einstellen",
        WAIT = "Warten", WATCH = "Beobachten",
    },

    -- Bedienzeit je Aktion in Minuten: Grundwert plus Aufschlag je Stueck.
    -- Ein Kauf von 20 Stueck dauert laenger als einer von 1, aber nicht
    -- zwanzigmal so lang.
    MINUTES = {
        GO_TO         = { base = 0,   perUnit = 0 },   -- kommt aus ROUTE.TRAVEL
        BUY           = { base = 1.0, perUnit = 0.06 },
        SELL          = { base = 1.0, perUnit = 0.04 },
        CRAFT         = { base = 0.5, perUnit = 0.35 },
        CONVERT       = { base = 0.3, perUnit = 0.15 },
        DISENCHANT    = { base = 0.3, perUnit = 0.20 },
        BANK_WITHDRAW = { base = 0.7, perUnit = 0.02 },
        BANK_DEPOSIT  = { base = 0.7, perUnit = 0.02 },
        MAIL          = { base = 1.0, perUnit = 0.02 },
        FARM          = { base = 0,   perUnit = 0 },   -- kommt aus Farm.lua
        VENDOR_BUY    = { base = 0.6, perUnit = 0.03 },
        VENDOR_SELL   = { base = 0.6, perUnit = 0.03 },
        POST_AUCTION  = { base = 1.0, perUnit = 0.10 },
        WAIT          = { base = 0,   perUnit = 0 },
        WATCH         = { base = 0.3, perUnit = 0 },
    },

    -- Preisspielraum der Anweisungen. Ein "kaufe bis 21 g" darf nicht auf den
    -- Kupfer genau am Planungspreis kleben, sonst ist die Anweisung nie
    -- erfuellbar.
    BUY_TOLERANCE = 0.03,
    SELL_TOLERANCE = 0.03,

    MAX_ACTIONS = 120,
    MAX_DEPENDENCIES = 12,
}

-- ---------------------------------------------------------------------------
-- Route Planner (0.9.0).
-- ---------------------------------------------------------------------------
C.ROUTE = {
    STORE_VERSION = 1,

    -- Reisezeit zwischen zwei Orten in Minuten. Bewusst grob und symmetrisch:
    -- Der Planer braucht nur eine Rangfolge ("gleicher Ort ist billiger als
    -- gleiche Stadt ist billiger als andere Zone"), keine Flugroutenkunde.
    TRAVEL = {
        SAME_SPOT = 0,
        SAME_HUB = 1.5,
        SAME_ZONE = 3,
        OTHER_ZONE = 6,
        UNKNOWN = 4,
    },

    PROFILES = {
        "QUICK_GOLD", "MAX_PROFIT", "LOW_RISK", "GROW_CAPITAL",
        "TRADING", "CRAFTING", "FARMING", "FUTURE_INVESTING", "CUSTOM",
    },

    PROFILE_LABEL = {
        QUICK_GOLD = "Schnelles Gold",
        MAX_PROFIT = "Maximaler Gewinn",
        LOW_RISK = "Geringes Risiko",
        GROW_CAPITAL = "Kapital aufbauen",
        TRADING = "Handel",
        CRAFTING = "Herstellen",
        FARMING = "Farmen",
        FUTURE_INVESTING = "Zukunft",
        CUSTOM = "Eigene Vorgaben",
    },

    DEFAULT_MINUTES = 60,
    MIN_MINUTES = 5,
    MAX_MINUTES = 480,
    MAX_STEPS = 40,

    -- Hysteresis. Eine laufende Route wird nur ersetzt, wenn der neue Plan
    -- merklich besser ist - sonst sortiert jede Silberbewegung die Route um.
    REPLAN = {
        MIN_INTERVAL = 20,          -- Sekunden zwischen zwei Neuplanungen
        MIN_GAIN_RATIO = 0.12,      -- 12 % mehr erwarteter Gewinn ...
        MIN_GAIN_ABSOLUTE = 50000,  -- ... oder 5 g, je nachdem was groesser ist
        MAX_PER_SESSION = 40,
        PRICE_TOLERANCE = 0.05,     -- 5 % ueber maxBuyPrice = Chance ungueltig
    },

    -- Opportunity Interrupts.
    INTERRUPT = {
        MIN_SCORE = 80,
        MIN_PROFIT = 100000,        -- 10 g
        MIN_ADVANTAGE = 1.5,        -- 50 % besser als der laufende Schritt
        AUTO_INSERT_DEFAULT = false,
        COOLDOWN = 300,
    },
}

-- ---------------------------------------------------------------------------
-- Guide Engine (0.9.0).
-- ---------------------------------------------------------------------------
C.GUIDE = {
    STORE_VERSION = 1,

    -- Groesster Abstand zweier Ticks, der noch als aktive Zeit zaehlt. Alles
    -- darueber ist ein Ladebildschirm, ein /reload oder eine Kaffeepause -
    -- und keine Zeit, die in "aktive Minuten" gehoert.
    MAX_TICK_SECONDS = 120,

    -- Wie viele Schritte der Viewer im Voraus zeigt.
    PREVIEW_STEPS = 3,

    -- Voreinstellungen des Zielmodus.
    DEFAULT_GOAL = 5000000,          -- 500 g
    TIME_PRESETS = { 30, 60, 90, 120 },
    RISK_LEVELS = { "low", "medium", "high" },
    RISK_LABEL = { low = "niedrig", medium = "mittel", high = "hoch" },
}

-- ---------------------------------------------------------------------------
-- Farm Brain (0.9.0). Hier steht KEINE einzige Gold/h-Angabe - die lernt das
-- Addon ausschliesslich aus den eigenen Sitzungen des Spielers.
-- ---------------------------------------------------------------------------
C.FARM = {
    STORE_VERSION = 1,

    MAX_SESSIONS = 120,
    -- Unter dieser Dauer ist eine Sitzung keine Messung, sondern ein
    -- Ausrutscher: Zwei Minuten mit einem Glueckstreffer waeren 300 Stueck/h.
    MIN_MINUTES = 5,
    -- Ohne Ausbeute ueber diese Zeit gilt die Sitzung als beendet. Wer die
    -- Sitzung offen laesst und schlafen geht, bekommt keine 8-Stunden-Rate.
    IDLE_TIMEOUT = 15 * 60,
    -- Groesster Abstand zweier Ticks, der noch als Farmzeit zaehlt. Bewusst
    -- grosszuegiger als beim Guide: Wer farmt, hat das Fenster meist zu.
    MAX_TICK_SECONDS = 300,

    CONFIDENCE = { LOW_SESSIONS = 2, MEDIUM_SESSIONS = 5, HIGH_SESSIONS = 12 },

    -- Ab welcher Abweichung vom eigenen Median ist ein Hinweis faellig?
    DEVIATION_THRESHOLD = 0.20,
    -- Eine Alternative wird nur vorgeschlagen, wenn sie deutlich besser ist.
    ALTERNATIVE_MARGIN = 1.3,

    -- Laenge eines Farmblocks in der Route.
    BLOCK_MINUTES = 20,
    MAX_BLOCK_MINUTES = 60,
}

-- ---------------------------------------------------------------------------
-- Personal Brain (0.9.0). Alles hier bleibt lokal.
-- ---------------------------------------------------------------------------
C.PERSONAL = {
    STORE_VERSION = 1,
    -- Unter dieser Zahl abgeschlossener Faelle gibt es keine persoenliche
    -- Aussage - nur die Zahl selbst, ausdruecklich als duenne Stichprobe.
    MIN_SAMPLES = 12,
    MIN_SKIP_SAMPLES = 6,
    SKIP_THRESHOLD = 0.5,
}

-- ---------------------------------------------------------------------------
-- Analytics (0.9.0).
-- ---------------------------------------------------------------------------
C.ANALYTICS = {
    -- Darunter steht LOW SAMPLE an der Zeile, und die Kalibrierung ruehrt sie
    -- nicht an.
    MIN_SAMPLES = 15,
}

-- ---------------------------------------------------------------------------
-- Kalibrierung (0.9.0). Konservativ, versioniert, jederzeit ruecksetzbar.
-- ---------------------------------------------------------------------------
C.CALIBRATION = {
    STORE_VERSION = 1,
    -- Modellversion. Aendert sich die Bewertungsformel so, dass alte
    -- Ergebnisse nicht mehr zu ihr passen, wird diese Zahl erhoeht - und die
    -- Kalibrierung faengt von vorn an, statt auf falschen Zahlen weiterzurechnen.
    MODEL_VERSION = 1,

    -- Voreingestellt AUS. Wer die Bewertung an eigenen Daten ausrichten will,
    -- soll das entscheiden - nicht das Addon.
    DEFAULT_ENABLED = false,

    -- Bevor ueberhaupt kalibriert wird, braucht es so viele abgeschlossene
    -- Faelle insgesamt ...
    MIN_TOTAL_SAMPLES = 40,
    -- ... und so viele je Chancenart.
    MIN_SAMPLES = 15,

    -- Bayes'sches Schrumpfen: gewicht = n / (n + PRIOR). Bei n = PRIOR zaehlt
    -- die Messung zur Haelfte, bei n = 3 x PRIOR zu drei Vierteln.
    PRIOR = 30,

    -- Harte Grenzen. Eine Chancenart kann durch Kalibrierung hoechstens ein
    -- Viertel gewinnen oder verlieren - egal, was die Daten sagen.
    MIN_FACTOR = 0.75,
    MAX_FACTOR = 1.25,
    -- Und sie bewegt sich je Durchlauf hoechstens um diesen Schritt.
    MAX_STEP = 0.05,
}

-- ---------------------------------------------------------------------------
-- Navigation (0.9.0). Orte lernt Gold Copilot aus den eigenen Besuchen des
-- Spielers; hier stehen nur die Grenzen dieser Erfassung.
-- ---------------------------------------------------------------------------
C.NAVIGATION = {
    STORE_VERSION = 1,

    -- Zwei Punkte auf derselben Karte gelten als derselbe Ort, wenn sie
    -- weniger als so viele Kartenanteile auseinanderliegen. Drei Auktionatoren
    -- nebeneinander sind ein Auktionshaus, nicht drei.
    MERGE_DISTANCE = 0.012,
    -- Ab hier gilt ein Ziel als erreicht (in Kartenanteilen).
    ARRIVED_DISTANCE = 0.010,

    MAX_PER_KIND = 24,
    -- Der Pfeil aktualisiert sich hoechstens fuenfmal je Sekunde. Ein Pfeil,
    -- der jeden Frame neu rechnet, ist die klassische Addon-Bremse.
    UPDATE_INTERVAL = 0.2,
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
