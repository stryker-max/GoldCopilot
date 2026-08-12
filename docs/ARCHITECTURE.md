# Architektur

Gold Copilot ist eine Kette. Jedes Modul beantwortet genau eine Frage und gibt
seine Antwort an das nächste weiter. Nichts überspringt eine Stufe, und keine
Stufe erfindet, was die vorherige nicht liefern konnte.

```
        PREISDATEN                Auctionator · TSM · eigene Beobachtung
             ↓
        MARKET BRAIN              Ist der Preis relativ zu seiner eigenen
        Market.lua                Geschichte günstig?  (Market Score)
             ↓
        OPPORTUNITY ENGINE        Ist daraus eine Gold-Chance ableitbar?
        Opportunity.lua           (Opportunity Score, ROI, Confidence)
             ↘
              FUTURE BRAIN        Was kommt an bekannten Veränderungen?
              Future.lua          (Future Demand, Hype, Catalysts)
                   ↓
        LIQUIDITY BRAIN           Komme ich da wieder heraus – und wie schnell?
        Ledger.lua                (Sell-through, Verkaufsdauer, Velocity)
                   ↓
        CAPITAL BRAIN             Wie viel Gold habe ich, und wohin damit?
        Capital.lua               (Positionen, Exposure, Reserve, Allokation)
                   ↓
        EXECUTION ENGINE          Was genau muss ich dafür tun?
        Execution.lua             (Aktionen, Abhängigkeiten, Bestandsabgleich)
                   ↓
        ROUTE PLANNER             In welcher Reihenfolge?
        Route.lua                 (Topologie, Wege, Budgets, Profile)
                   ↓
        GUIDE ENGINE              Wo stehe ich gerade?
        Guide.lua                 (Zustand, Auto-Erkennung, Neuplanung)
                   ↓
        DEMAND EVIDENCE           Kauft das überhaupt jemand?
        Demand.lua                (Belegstufe 0-5, Aufnahmefähigkeit)
                   ↓
        ACTIONABILITY             Reichen die Belege für eine Handlung?
        Actionability.lua         (bewährt · Markttest · spekulativ)
                   ↓
        RECOMMENDATION            Was jetzt tun - über alle Methoden hinweg?
        Recommendation.lua        (auch: gerade nichts)
                   ↓
        SPIELERAKTION             kaufen · herstellen · einstellen · farmen
                                  · Dienstleistung anbieten
                   ↓
        INCOME / ACTIVITY         Woher kam das Gold wirklich?
        Income.lua, Activity.lua  (Quelle mit Confidence, Sitzungen, Gold/h)
                   ↓
        LEDGER / OUTCOME          Was ist tatsächlich passiert?
        Ledger.lua                (bestätigte Ereignisse, Ergebniszuordnung)
             ↑
        Die Guide Engine meldet beim Abhaken zurück, AUS WELCHER CHANCE ein
        Schritt stammt (Opportunity:ClaimExecution). Das ist die einzige Stelle,
        die es weiß - und der einzige Weg, auf dem ein Craft je zugeordnet
        werden kann: Gekauft werden seine Zutaten, empfohlen war sein Produkt.
                   ↓
        PERSONAL BRAIN            Was heißt das für DIESEN Spieler?
        Personal.lua              (ausgeführt, übersprungen, realisiert)
                   ↓
        ANALYTICS                 Hat die Empfehlung gestimmt?
        Analytics.lua             (Trefferquoten je Dimension, mit n)
                   ↓
        CALIBRATION               Gewichte vorsichtig nachziehen
        Calibration.lua           (Bayes'sches Schrumpfen, harte Grenzen)
                   ↺  zurück in die Opportunity Engine
```

## Module

| Datei | Aufgabe |
| --- | --- |
| `Constants.lua` | Alle Stellschrauben. Keine Logik, keine Spielaussage. |
| `Core.lua` | Datenbank, Realmprofile, Migration, Slash-Befehle, Diagnose. |
| `Knowledge/` | Spielwissen mit Provenance. Keine Formel, keine Bewertung. |
| `Prices.lua` | Preisquellen, Planungspreise, AH-Gebühr, Formatierung. |
| `Inventory.lua` | Bestand aus Taschen und – mit Syndicator – Bank, Post, Auktionen. |
| `Advisor.lua` | Bester Verkaufskanal je Item. |
| `Flips.lua` | Umwandlungen (Partikel, Essenzen). |
| `Crafts.lua` | Gescannte Rezepte und ihr Gewinn. |
| `Market.lua` | Markthistorie, Market Score, Beobachtungsliste, **Markttiefe**. |
| `Ledger.lua` | Persönliche Handelsbilanz, Liquidität, Profit Velocity. |
| `Opportunity.lua` | Chancen-Bewertung, Chancen-Protokoll, Ergebniszuordnung. |
| `Future.lua` | Phasen, Catalysts, Dependency Graph, Future Demand, Hype. |
| `Capital.lua` | Positionen, Exposure, Cash-Reserve, Position Sizing, Allokation. |
| `Execution.lua` | Zerlegung einer Zuteilung in Aktionen samt Abhängigkeiten. |
| `Route.lua` | Reihenfolge, Wege, Budgets, Profile, Hysteresis, Gültigkeit. |
| `Navigation.lua` | Gelernte Orte, Richtung, Entfernung, TomTom (optional). |
| `Farm.lua` | Farmsitzungen, persönliche Raten, adaptive Hinweise. |
| `Personal.lua` | Persönliche Statistik über Aktivitäten und Ergebnisse. |
| `Demand.lua` | Nachfragebelege je Item: Struktur, Realm, eigene Verkäufe, heutige Lage. |
| `Actionability.lua` | Reichen die Belege für eine Handlung? PROVEN / TEST / SPECULATIVE / BLOCKED. |
| `Income.lua` | Goldzuflüsse mit Ursache und Confidence. UNKNOWN ist erlaubt. |
| `Materials.lua` | Was ein Zauber aus den eigenen Taschen verbraucht hat – und wem es gehörte. |
| `Activity.lua` | Sitzungen je Methode, Gold je aktiver Stunde, Methodenvergleich. |
| `Recommendation.lua` | Was jetzt tun – über alle Methoden hinweg, oder bewusst nichts. |
| `Analytics.lua` | Auswertung des Chancen-Protokolls mit Stichprobengrößen. |
| `Calibration.lua` | Konservative Anpassung der Gewichte an eigene Ergebnisse. |
| `Guide.lua` | Zustandsautomat der laufenden Route. |
| `Quests.lua`, `Roadmap.lua` | Tagesplan (seit 0.2/0.4, unverändert in Betrieb). |
| `UI.lua` | Fenster, Zentrale, Route, Guide Viewer, alle Tabs. |

## Zwei Regeln, die überall gelten

**1. Unbekannt ist ein Wert.** Kein Modul ersetzt eine fehlende Zahl durch
eine Null oder einen Schätzwert. Wo etwas fehlt, steht `nil` – und die
Oberfläche schreibt einen Satz statt einer Zahl. Das gilt für Liquidität ohne
eigene Verkäufe, für Farmraten ohne eigene Sitzungen, für Kostenbasis ohne
belegte Käufe, für Koordinaten ohne eigenen Besuch und für Angebotsmengen
ohne eigene AH-Suche. Und seit 1.0.0-beta.10 auch für die
Zuordnung einer Empfehlung zu ihrem Ergebnis: Ohne Beleg gibt es kein Ergebnis,
nicht ein geratenes.

**2. Spielwissen und Rechenweg sind getrennt.** In `Knowledge/` steht, was im
Spiel passiert – jede Zeile mit Quelle und Sicherheitsgrad. In `Constants.lua`
stehen Gewichte und Grenzen. In den Modulen steht die Rechnung. Wer die
Wissensbasis aktualisiert, fasst keine Logik an; wer eine Formel nachjustiert,
kein Spielwissen.

## Caches und Revisionen

Jedes teure Ergebnis hängt an einem Zähler oder einer Signatur, nicht an einer
Uhr allein:

| Modul | Invalidierung |
| --- | --- |
| `Market` | `Market.revision`, plus 15-Minuten-Fenster für Statistiken |
| `Ledger` | `Ledger.revision` (jedes erfasste Ereignis erhöht ihn) |
| `Opportunity` | Signatur aus Markt-, Rezept- und Optionsstand + 30 s |
| `Future` | Signatur aus Markt-, Graph- und Wissensstand |
| `Capital` | Signatur aus Ledger-, Markt- und Goldstand + 20 s |
| `Analytics` | Ledger-Revision + Länge des Chancen-Protokolls |
| `UI` (Zentrale) | Signatur aus Markt-, Ledger-, Kapitalstand + 30 s |

Es gibt **kein einziges `OnUpdate`** im Addon. Der Guide Viewer plant sich
zweimal je Sekunde selbst neu ein, solange er sichtbar ist – und keinen Aufruf
mehr, sobald er zu ist. Alles andere hängt an Ereignissen des Clients.

## Was bewusst fehlt

- **Keine Netzwerkzugriffe.** Addons können keine Webseiten abrufen, und Gold
  Copilot tut auch nicht so. Die Wissensbasis wird mit dem Addon ausgeliefert.
- **Kein eigener AH-Scanner.** Preise kommen von Auctionator oder TSM.
- **Keine Automatisierung.** Gold Copilot kauft, verkauft und läuft nichts.
  Es sagt, was zu tun ist; getan wird es vom Spieler.
