local addonName, GCP = ...

local Knowledge = GCP.Knowledge

-- ---------------------------------------------------------------------------
-- CATALYSTS
--
-- Ein Catalyst ist ein bekanntes zukuenftiges Ereignis, das Angebot oder
-- Nachfrage eines Items veraendern KOENNTE. Er ist ausdruecklich keine
-- Preisprognose.
--
-- strength ist eine Einschaetzung der Wucht des Zusammenhangs, kein Prozentsatz
-- auf den Preis. 0.8 heisst "starker, plausibler Nachfragegrund", nicht
-- "+80 %". Wer das verwechselt, liest aus dieser Datei eine Zusage heraus, die
-- sie nicht macht.
--
-- Catalysts haengen bewusst oft am PRODUKT, nicht am Material: Die Tatsache ist
-- "in Phase 3 gibt es dieses Rezept". Dass dadurch die Zutaten gefragt sind,
-- rechnet der Dependency Graph aus - abgeschwaecht je Ebene. So steht die
-- Behauptung dort, wo sie belegbar ist, und die Ableitung dort, wo sie
-- hingehoert.
--
-- Direkt am Material haengen nur Catalysts, die breiter sind als das einzelne
-- modellierte Rezept (etwa: alle vier Schattenwiderstands-Sets zusammen).
-- ---------------------------------------------------------------------------

local BLIZZARD = "Blizzard-News: BCC Anniversary Edition – Black Temple Arrives August 27"
local GAME_DATA = "TBC-Spieldaten 2.4.3 (Rezept- und Encounterdaten)"

local function add(catalyst)
    catalyst.phase = catalyst.phase or "phase3"
    Knowledge:RegisterCatalyst(catalyst)
end

-- ---------------------------------------------------------------------------
-- 1. Schattenwiderstand: Mutter Shahraz im Schwarzen Tempel
--
-- FAKT: Der Encounter verlangt Schattenwiderstand, und die vier hergestellten
-- Widerstandssets (Soulguard fuer Stoff, Redeemed Soul fuer Leder, Shackled
-- Souls fuer Kette, Shadesteel fuer Platte) sind die Antwort darauf.
-- MODELL: Dass das die Nachfrage nach Urschatten hebt.
-- ---------------------------------------------------------------------------

add({
    id = "p3-resist-primal-shadow",
    type = "RESISTANCE_REQUIREMENT",
    itemID = 22456,                                  -- Primal Shadow
    direction = "demand_up",
    strength = 0.85,
    confidence = "high",
    reason = "Mutter Shahraz verlangt Schattenwiderstand. Alle vier hergestellten "
        .. "Widerstandssets verbrauchen je Rüstungsteil 4–6 Urschatten – und ein "
        .. "Raid rüstet damit nicht einen Spieler aus, sondern die halbe Gruppe.",
    fact = "Die Rezepte der Widerstandssets führen Urschatten als Hauptzutat.",
    sourceConfidence = "historical",
    sourceName = GAME_DATA,
})

add({
    id = "p3-resist-soulguard-slippers",
    type = "RESISTANCE_REQUIREMENT",
    itemID = 32391,                                  -- Soulguard Slippers
    direction = "demand_up",
    strength = 0.75,
    confidence = "high",
    reason = "Stoff-Widerstandsset für den Schwarzen Tempel; das Rezept kommt mit "
        .. "dem Ruf bei den Ashtongue Deathsworn.",
    sourceConfidence = "historical",
    sourceName = GAME_DATA,
})

add({
    id = "p3-resist-shadesteel-greaves",
    type = "RESISTANCE_REQUIREMENT",
    itemID = 32404,                                  -- Shadesteel Greaves
    direction = "demand_up",
    strength = 0.75,
    confidence = "high",
    reason = "Platten-Widerstandsset für den Schwarzen Tempel; verbraucht neben "
        .. "Urschatten zwölf Adamantitbarren je Teil.",
    sourceConfidence = "historical",
    sourceName = GAME_DATA,
})

-- ---------------------------------------------------------------------------
-- 2. Das Leitmaterial der Phase
--
-- Herz der Finsternis ist der Sonderfall, an dem sich zeigt, warum ein
-- Nachfrage-Catalyst allein zu kurz greift: Das Material ist Zutat fast jedes
-- neuen Rezepts UND faellt ab demselben Tag massenhaft von Trashgruppen. Beide
-- Seiten stehen deshalb als eigener Catalyst da, und die Rechnung verrechnet
-- sie gegeneinander.
-- ---------------------------------------------------------------------------

add({
    id = "p3-heart-of-darkness-demand",
    type = "NEW_CRAFT",
    itemID = 32428,                                  -- Heart of Darkness
    direction = "demand_up",
    strength = 0.9,
    confidence = "high",
    reason = "Zutat praktisch jedes neuen Rezepts der Phase – Widerstandssets, "
        .. "Armschienen, Schultern.",
    sourceConfidence = "historical",
    sourceName = GAME_DATA,
})

add({
    id = "p3-heart-of-darkness-supply",
    type = "SUPPLY_INCREASE",
    itemID = 32428,
    direction = "supply_up",
    strength = 0.7,
    confidence = "high",
    reason = "Fällt ab dem ersten Tag von Trashgruppen im Schwarzen Tempel und am "
        .. "Berg Hyjal. Das Angebot entsteht zeitgleich mit der Nachfrage – vorher "
        .. "gibt es das Material auf dem Realm überhaupt nicht.",
    fact = "Trash-Drop in beiden neuen Raids.",
    sourceConfidence = "historical",
    sourceName = GAME_DATA,
})

-- ---------------------------------------------------------------------------
-- 3. Neue hergestellte Spitzenausruestung
-- ---------------------------------------------------------------------------

add({
    id = "p3-bis-swiftheal-wraps",
    type = "NEW_BIS_ITEM",
    itemID = 32584,                                  -- Swiftheal Wraps
    direction = "demand_up",
    strength = 0.7,
    confidence = "high",
    reason = "Gefragte Heiler-Armschienen aus Phase 3; Muster fällt im Schwarzen Tempel.",
    sourceConfidence = "historical",
    sourceName = GAME_DATA,
})

add({
    id = "p3-bis-bracers-nimble-thought",
    type = "NEW_BIS_ITEM",
    itemID = 32586,                                  -- Bracers of Nimble Thought
    direction = "demand_up",
    strength = 0.7,
    confidence = "high",
    reason = "Gefragte Zauberer-Armschienen aus Phase 3; Muster fällt bei Teron Gorefiend.",
    sourceConfidence = "historical",
    sourceName = GAME_DATA,
})

add({
    id = "p3-bis-swiftstrike-bracers",
    type = "NEW_BIS_ITEM",
    itemID = 32580,                                  -- Swiftstrike Bracers
    direction = "demand_up",
    strength = 0.7,
    confidence = "high",
    reason = "Gefragte Nahkampf-Armschienen aus Phase 3; verbraucht zehn Urluft je Stück.",
    sourceConfidence = "historical",
    sourceName = GAME_DATA,
})

-- ---------------------------------------------------------------------------
-- 4. Raid-Verbrauchsgueter
--
-- FAKT: Zwei neue 25-Spieler-Raids oeffnen gleichzeitig.
-- MODELL: Mehr Raidabende heissen mehr Flakons, und Flakons heissen Kraeuter.
-- Die Kraeuter selbst bekommen keinen eigenen Catalyst - sie erben ihn ueber
-- die Rezeptkanten, sonst zaehlte derselbe Grund doppelt.
-- ---------------------------------------------------------------------------

add({
    id = "p3-raid-flask-relentless-assault",
    type = "NEW_RAID",
    itemID = 22854,                                  -- Flask of Relentless Assault
    direction = "demand_up",
    strength = 0.6,
    confidence = "high",
    reason = "Schwarzer Tempel und Berg Hyjal öffnen gleichzeitig. Zwei neue "
        .. "25-Spieler-Raids bedeuten mehr Flakonverbrauch je Woche.",
    fact = "Beide Raids öffnen am selben Tag (Blizzard-Ankündigung).",
    sourceConfidence = "official",
    sourceName = BLIZZARD,
})

add({
    id = "p3-raid-flask-pure-death",
    type = "NEW_RAID",
    itemID = 22866,                                  -- Flask of Pure Death
    direction = "demand_up",
    strength = 0.55,
    confidence = "high",
    reason = "Zusätzlicher Flakonverbrauch durch zwei neue 25-Spieler-Raids.",
    fact = "Beide Raids öffnen am selben Tag (Blizzard-Ankündigung).",
    sourceConfidence = "official",
    sourceName = BLIZZARD,
})

-- ---------------------------------------------------------------------------
-- 5. Epische Sockelsteine
--
-- FAKT: Blizzard nennt epische Sockelsteine ausdruecklich als Inhalt der
-- Phase 3, zu holen ueber Bergbau (375) am Berg Hyjal und als seltene Funde im
-- Schwarzen Tempel.
-- MODELL: Dass sie gefragt sind und die blauen Steine im Endgame verdraengen.
-- ---------------------------------------------------------------------------

local epicGems = {
    { id = 32227, name = "Crimson Spinel" },
    { id = 32228, name = "Empyrean Sapphire" },
    { id = 32229, name = "Lionseye" },
    { id = 32230, name = "Shadowsong Amethyst" },
    { id = 32231, name = "Pyrestone" },
    { id = 32249, name = "Seaspray Emerald" },
}

for _, gem in ipairs(epicGems) do
    add({
        id = "p3-epic-gem-" .. gem.id,
        type = "NEW_GEM",
        itemID = gem.id,
        direction = "demand_up",
        strength = 0.7,
        confidence = "high",
        reason = "Epische Sockelsteine kommen mit Phase 3. Quelle sind Bergbau (375) "
            .. "in der Schlacht um den Berg Hyjal und seltene Funde im Schwarzen "
            .. "Tempel – das Angebot hängt also am Raidfortschritt.",
        fact = "Blizzard nennt epische Sockelsteine als Inhalt der Phase 3.",
        sourceConfidence = "official",
        sourceName = BLIZZARD,
    })
end

-- Der einzige Catalyst der Wissensbasis, der nach unten zeigt. Er steht hier,
-- weil eine Wissensbasis, die nur Gruende zum Kaufen kennt, keine Wissensbasis
-- ist, sondern ein Verkaufsprospekt.
local rareGems = { 23436, 23437, 23438, 23439, 23440, 23441 }
for _, gemID in ipairs(rareGems) do
    add({
        id = "p3-rare-gem-" .. gemID,
        type = "NEW_GEM",
        itemID = gemID,
        direction = "demand_down",
        strength = 0.45,
        confidence = "medium",
        reason = "Epische Sockelsteine verdrängen die blauen Steine nach und nach aus "
            .. "der Endgame-Ausrüstung. Wie schnell das geht, hängt daran, wie viele "
            .. "epische Steine auf deinem Realm ankommen.",
        sourceConfidence = "inferred",
        sourceName = "Abgeleitet aus der offiziellen Ankündigung epischer Sockelsteine",
    })
end

-- ---------------------------------------------------------------------------
-- 6. Verzauberungen und Arena-Saison 3
-- ---------------------------------------------------------------------------

add({
    id = "p3-enchant-large-prismatic-shard",
    type = "DEMAND_INCREASE",
    itemID = 22449,                                  -- Large Prismatic Shard
    direction = "demand_up",
    strength = 0.45,
    confidence = "medium",
    reason = "Neue Ausrüstung aus zwei Raids wird verzaubert; große Prismasplitter "
        .. "sind die Grundlage der Endgame-Verzauberungen.",
    sourceConfidence = "inferred",
    sourceName = "Abgeleitet aus dem Raidstart (Blizzard-Ankündigung)",
})

add({
    id = "p3-arena-season-3-shards",
    type = "NEW_PVP_SEASON",
    itemID = 22449,
    direction = "demand_up",
    strength = 0.35,
    confidence = "medium",
    reason = "Arena-Saison 3 startet am 1. September mit dem regionalen Wochenreset. "
        .. "Frische PvP-Ausrüstung wird ebenfalls verzaubert und gesockelt.",
    fact = "Arena-Saison 3 startet laut Ankündigung am 1. September.",
    sourceConfidence = "official",
    sourceName = BLIZZARD,
})
