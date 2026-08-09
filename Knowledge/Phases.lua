local addonName, GCP = ...

local Knowledge = GCP.Knowledge

-- ---------------------------------------------------------------------------
-- PHASEN DER ANNIVERSARY-REALMS
--
-- Eine harte Regel, und sie ist der Grund, warum diese Datei so kurz ist:
--
--   Ein exaktes Datum steht hier nur, wenn Blizzard es fuer die
--   Anniversary-Realms angekuendigt hat.
--
-- Termine aus dem urspruenglichen TBC (2007) oder aus TBC Classic (2021) sind
-- KEINE Anniversary-Termine. Inhalte, deren Reihenfolge aus TBC bekannt ist,
-- duerfen modelliert werden - ihr Termin bleibt dann release = nil, und der
-- Zukunft-Tab schreibt "Termin noch nicht angekündigt" statt einer Zahl.
--
-- sourceConfidence sagt, worauf die Aussage beruht:
--   official    Blizzard-Ankuendigung
--   historical  bekannter TBC-Inhalt und bekannte Phasenreihenfolge
--   inferred    daraus abgeleitet
-- ---------------------------------------------------------------------------

local UTC = function(spec) return Knowledge:UTC(spec) end

-- Phase 1 und 2 sind auf den Anniversary-Realms gelaufen, bevor 0.7 entstand.
-- Beleg ist die Phase-3-Ankuendigung selbst: Sie nennt Phase 3 als naechste
-- Phase. Ein Datum wird hier trotzdem nicht behauptet - es wird auch nicht
-- gebraucht, "live" genuegt.
Knowledge:RegisterPhase({
    id = "phase1",
    order = 1,
    name = "Karazhan, Gruul & Magtheridon",
    shortName = "Phase 1",
    live = true,
    release = nil,
    sourceConfidence = "official",
    sourceName = "Blizzard: Phase-3-Ankündigung nennt Phase 3 als nächste Phase",
    content = {
        { text = "Karazhan, Gruuls Unterschlupf, Magtheridons Kammer" },
    },
})

Knowledge:RegisterPhase({
    id = "phase2",
    order = 2,
    name = "Höhlen des Schlangenschreins & Auge des Sturms",
    shortName = "Phase 2",
    live = true,
    release = nil,
    sourceConfidence = "official",
    sourceName = "Blizzard: Phase-3-Ankündigung nennt Phase 3 als nächste Phase",
    content = {
        { text = "Höhlen des Schlangenschreins (Lady Vashj)" },
        { text = "Festung der Stürme: Auge des Sturms (Kael'thas)" },
        { text = "Nethersturmwirbel als Handwerksmaterial (Bosse und Marken-Händler)" },
    },
})

-- Der einzige exakte Termin in dieser Datei. Quelle: Blizzard-News
-- "BCC Anniversary Edition: Black Temple Arrives August 27" (Artikel 24291476,
-- ebenso im offiziellen Forum und im Blue Tracker). Angekuendigt ist der
-- 27.08.2026, 15:00 PDT - das ist 22:00 UTC, und genau als UTC steht es hier.
Knowledge:RegisterPhase({
    id = "phase3",
    order = 3,
    name = "Schwarzer Tempel & Berg Hyjal",
    shortName = "Phase 3",
    release = UTC({ year = 2026, month = 8, day = 27, hour = 22, min = 0 }),
    sourceConfidence = "official",
    sourceName = "Blizzard-News: BCC Anniversary Edition – Black Temple Arrives August 27",
    sourceNote = "Angekündigt für den 27.08.2026, 15:00 PDT (22:00 UTC), global.",
    content = {
        { text = "Schwarzer Tempel – 9 Bosse, Endboss Illidan Sturmgrimm",
          sourceConfidence = "official" },
        { text = "Schlacht um den Berg Hyjal – 5 Bosse, Endboss Archimonde; "
            .. "Zugang über die Questreihe \"Die Phiolen der Ewigkeit\"",
          sourceConfidence = "official" },
        { text = "Epische Sockelsteine – Bergbau (375) in der Schlacht um den Berg Hyjal "
            .. "und seltene Funde im Schwarzen Tempel",
          sourceConfidence = "official" },
        { text = "Netherschwingen: neue Tagesquests und Ruf",
          sourceConfidence = "official" },
        { text = "Arena-Saison 3 startet am 1. September mit dem regionalen Wochenreset",
          sourceConfidence = "official" },
        { text = "Ashtongue Deathsworn: Rezepte beim Quartiermeister Okuno im Schwarzen Tempel",
          sourceConfidence = "historical" },
        { text = "Mutter Shahraz im Schwarzen Tempel verlangt Schattenwiderstand",
          sourceConfidence = "historical" },
    },
})

-- Ab hier ist nur die Reihenfolge bekannt, nicht der Termin. Genau dafuer gibt
-- es release = nil: Der Inhalt darf modelliert werden, das Datum wird nicht
-- erfunden.
Knowledge:RegisterPhase({
    id = "phase4",
    order = 4,
    name = "Zul'Aman",
    shortName = "Phase 4",
    release = nil,
    live = false,
    sourceConfidence = "historical",
    sourceName = "TBC-Inhaltsreihenfolge (Patch 2.3)",
    sourceNote = "Für die Anniversary-Realms ist noch kein Termin angekündigt.",
    content = {
        { text = "Zul'Aman (10 Spieler)" },
    },
})

Knowledge:RegisterPhase({
    id = "phase5",
    order = 5,
    name = "Sonnenbrunnenplateau",
    shortName = "Phase 5",
    release = nil,
    live = false,
    sourceConfidence = "historical",
    sourceName = "TBC-Inhaltsreihenfolge (Patch 2.4)",
    sourceNote = "Für die Anniversary-Realms ist noch kein Termin angekündigt.",
    content = {
        { text = "Sonnenbrunnenplateau, Insel von Quel'Danas, Offensive der Zerschmetterten Sonne" },
    },
})
