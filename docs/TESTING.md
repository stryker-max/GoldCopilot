# Tests

```
npm install    # einmalig (fengari)
npm test
```

`npm test` führt zwei Schritte aus:

1. **`tests/validate.mjs`** – Struktur: Version in TOC, `Constants.lua` und
   README identisch; jede TOC-Datei existiert; jede Lua-Datei des Addons steht
   in der TOC; keine Verweise auf das Schwesterprojekt; README erklärt `/gold`.
2. **`tests/run.mjs`** – lädt die vier Lua-Testdateien nacheinander in je einem
   eigenen fengari-Zustand.

Es gibt keinen installierten Lua-Interpreter; Lua läuft ausschließlich über das
npm-Paket `fengari` (Lua 5.3). WoW selbst läuft auf Lua 5.1 – wo das einen
Unterschied macht (`math.atan2`), steht eine Weiche im Code.

## Aufbau

| Datei | Gegenstand |
| --- | --- |
| `tests/smoke.lua` | Rechenwege: Preise, Bestand, Flips, Crafts, Markt, Ledger, Chancen, Zukunft, Migration, Realmtrennung |
| `tests/ui.lua` | Oberfläche: jeder Tab zeichnet kalt und warm, Tooltips, Zentrale, Guide Viewer |
| `tests/engine.lua` | Entscheidungsschicht: Wissensprüfung, Kapital, Execution, Route, Navigation, Guide, Farm, Personal, Analytics, Kalibrierung, Markttiefe, Diagnose, Speicherhärtung |
| `tests/simulation.lua` | 18 vollständige Sitzungen plus Invarianten |
| `tests/harness.lua` | gemeinsame WoW-Attrappe und Simulationsschicht |

`smoke.lua` und `ui.lua` bringen ihre eigenen, historisch gewachsenen Attrappen
mit. Alles ab 0.9 nutzt `harness.lua` – eine Umgebung, die sich **während** des
Tests ändern lässt: Preise steigen, Taschen füllen sich, Ereignisse feuern, die
Uhr läuft weiter.

## Die Simulationsschicht

```lua
local H = dofile("tests/harness.lua")
local GCP = H.boot()          -- Globals setzen, Addon laden, DB anlegen

H.reset(GCP)                  -- frische Welt und frische Datenbank
H.seedRealm(GCP)              -- Markthistorie und ein Rezept
H.seedTrade(GCP, 21884, { rounds = 8 })   -- eigene Handelsspur
H.seedOpenAuction(GCP, 21884, 10, 220000) -- offene Position
H.farmRun(GCP, 1800, { chunk = 300, itemID = 23425, perChunk = 5 })

H.setPrice(21884, 300000)     -- der Markt zieht an
H.advance(3600)               -- eine Stunde vergeht
H.fire("AUCTION_HOUSE_SHOW")  -- ein Ereignis
H.flushTimers()               -- C_Timer.After ausführen
```

`H.reset` setzt nicht nur die Welt zurück, sondern auch alle Laufzeit-Caches
der Module. Ein Cache, der eine Sitzung überlebt, wäre in einem
End-to-End-Test die häufigste Fehlerquelle.

## Die 18 Szenarien

| # | Szenario | Kernaussage |
| --- | --- | --- |
| 1 | Frische Installation | ohne Daten keine Route, aber auch kein Fehler |
| 2 | Marktdaten ohne Ledger | Chancen ja, Liquidität ausdrücklich unbekannt |
| 3 | Markt und Ledger | eigene Verkaufsdaten fließen ein |
| 4 | Craft-Chance | kaufen → herstellen → einstellen, in dieser Reihenfolge |
| 5 | Conversion-Chance | Umwandlung samt Hinweis auf die Unumkehrbarkeit |
| 6 | Zukunftschance | Catalysts aus der Wissensbasis |
| 7 | Hoher Hype | Hype erkannt, Position kleiner |
| 8 | Zähe Liquidität | schlechte Sell-through senkt die Positionsgröße |
| 9 | Wenig Kapital | Route bleibt im Rahmen, Reserve unangetastet |
| 10 | Viel Kapital | kein All-In, Maximalanteil eingehalten |
| 11 | Preisänderung während der Route | Schritt wird ungültig, Neuplanung |
| 12 | Item verschwunden | kein falscher Ungültigkeitsschluss ohne Preis |
| 13 | Übersprungener Schritt | Abhängiges fällt mit weg, als Folge markiert |
| 14 | Schwache Farmsitzung | Abweichung vom eigenen Median wird beziffert |
| 15 | Vollständige Gold Route | bis COMPLETED, Ergebnis wandert ins Protokoll |
| 16 | ReloadUI mittendrin | kein Fortschritt verloren, Route pausiert |
| 17 | Optionale Addons fehlen | alles läuft, nur ohne Preise |
| 18 | Kaputte SavedVariables | jeder Speicher repariert sich, Heiles bleibt |

## Invarianten

Zusätzlich prüft `simulation.lua` Zusicherungen über viele erzeugte Eingaben
statt an einem Beispiel:

- Opportunity Score über hunderte Kombinationen immer ganzzahlig in 0–100
- ohne Datenlage gar kein Score – nicht 0
- keine ROI ohne Kapitaleinsatz, kein Verlustgeschäft als Chance
- Positionsgrößen ganzzahlig, positiv, unter dem Maximalanteil
- Allokation nie über dem freien Kapital, Reserve nie angetastet, Rest nie negativ
- in jeder Route: keine doppelte Aktion, jede Abhängigkeit vor ihrem Nachfolger,
  Kapital- und Schrittgrenzen eingehalten
- ein erledigter Schritt lässt sich nicht zweimal erledigen
- Abbruch ist kein Ablauf
- UNKNOWN wird nie stillschweigend zu 0
- mehr Messpunkte senken die Sicherheit nie
- ein einzelner Ausreißer hebt keinen Score sprunghaft
- Neuplanung verliert keinen Fortschritt und läuft nicht in eine Schleife
- die AH-Gebühr wird genau einmal abgezogen

## Umfang

Stand 1.0.0-beta.1:

| Datei | Zusicherungen |
| --- | --- |
| `smoke.lua` | 1155 |
| `ui.lua` | 271 |
| `engine.lua` | 648 |
| `simulation.lua` | 170 |
| **gesamt** | **2244** |

## Was die Tests nicht können

Sie laufen gegen eine Attrappe, nicht gegen WoW. Was sie **nicht** beweisen:

- dass Blizzards API sich genauso verhält wie die Attrappe
- dass ein Frame an der richtigen Stelle sitzt (geprüft wird, dass er gezeichnet
  wird und welchen Text er trägt – nicht, wie er aussieht)
- dass der Richtungspfeil in der Spielwelt wirklich dorthin zeigt

Genau dafür gibt es `docs/INGAME_TEST.md`.
