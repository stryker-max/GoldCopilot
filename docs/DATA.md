# Daten

Alles, was Gold Copilot weiß, steht in **deinen** SavedVariables
(`WTF/Account/<Account>/SavedVariables/GoldCopilot.lua`). Es gibt keine
Übertragung, keinen Abgleich, keinen Server und keinen Netzwerkzugriff.

## Realm- und Fraktionstrennung

`GoldCopilotDB` ist accountweit. Das ist für Optionen und den Goldverlauf
richtig – und für Marktdaten falsch: Das Auktionshaus der Horde auf Realm A hat
mit dem der Allianz auf Realm B nichts zu tun.

Deshalb bekommt jede Kombination aus Realm und Fraktion einen eigenen Speicher:

```lua
GoldCopilotDB = {
    version = "1.0.0-beta.1",
    profileVersion = 1,
    options = { ... },          -- accountweit
    goldHistory = { ... },      -- accountweit
    questGold = { ... },        -- accountweit
    recipes = { ... },          -- accountweit
    roadmap = { ... },          -- accountweit
    locations = { ... },        -- accountweit, intern je Realm+Fraktion
    profiles = {
        ["Blackrock|Horde"] = { marketHistory = ..., ledger = ..., ... },
        ["Blackrock|Alliance"] = { ... },
    },
}
```

**Migration**: Beim ersten Start mit 1.0 wandern die vorhandenen Daten *einmal*
in das Profil des Charakters, mit dem eingeloggt wird – verschoben, nicht
kopiert. Das ist die einzige Zuordnung, die sich belegen lässt; woher die Daten
wirklich stammen, weiß niemand. Ein Realmwechsel danach legt ein leeres Profil
an und lässt das erste unberührt.

## Speicher im Überblick

| Schlüssel | Umfang | Aufbewahrung | Obergrenze |
| --- | --- | --- | --- |
| `marketHistory` | Preisreihen je Item | 30 Tage | 500 Items × 400 Punkte |
| `marketDepth` | Angebotsmengen je Item | 14 Tage | 200 Items × 24 Messungen |
| `priceHistory` | ein Tageswert je Item | 14 Tage | – |
| `watchlist` | beobachtete Items | – | 100 |
| `ledger` | Handelsereignisse | 60 Tage | 4000 Ereignisse, 400 Items |
| `ledger.items` | Aggregate je Item | **unbegrenzt in der Zeit** | 400 Items, 60 Stichproben je Reihe |
| `ledger.open` | offene Einstellungen | 35 Tage | 250 |
| `opportunityHistory` | Empfehlungen + Ergebnis | 90 Tage | 400 |
| `marketProbes` | Score-Beobachtungspunkte | 30 Tage | 600 |
| `income` | Goldzuflüsse mit Quelle und Confidence | 60 Tage | 2000 |
| `activity` | Sitzungen je Goldmethode (mit Modus manuell/automatisch) | 180 Tage | 200 |
| `capital.meta` | Herkunft einer Position | 45 Tage | 300 |
| `farm.sessions` | Farmsitzungen | – | 120 |
| `personal` | Aktivitätsstatistik | – | je Chancenart eine Zeile |
| `calibration` | Faktoren je Chancenart | – | je Chancenart eine Zahl |
| `guide` | laufende Route + Fortschritt | bis zum Abschluss | 40 Schritte |
| `locations` | gelernte Orte | – | 24 je Art und Profil |

Jeder Speicher trägt eine **Formatversion**. Passt sie nicht, wird
ausschließlich dieser Speicher verworfen und neu angelegt – nie die ganze
Datenbank, nie ein anderer Speicher.

## Robustheit

Jede `EnsureStore`-Funktion prüft nicht nur die Version, sondern auch die
**Typen der Felder**. Getestet wird das gegen:

- unbekannte Formatversion → Speicher wird ersetzt
- falscher Typ (`"kaputt"` statt Tabelle) → Speicher wird ersetzt
- halb kaputte Struktur (einzelne Felder falsch) → nur diese Felder werden
  ersetzt
- unsinniger Zustand (`state = 42`, `currentIndex = -5`) → Standardwert

Ein kaputter Speicher reißt weder den Start noch ein anderes Modul mit.

## Format der Rohdaten

Zwei Speicher liegen als **flache Zahlenlisten** vor, nicht als Listen aus
Tabellen: `marketHistory.items` (Paare aus Minute und Preis) und
`ledger.events` (Achtergruppen). WoW schreibt SavedVariables als Lua-Quelltext;
benannte Felder kosten je Ereignis rund 140 Zeichen, acht Zahlen rund 50. Bei
4000 Ereignissen sind das 560 KB gegen 200 KB – bei identischem
Informationsgehalt.

Ein Ereignis im Ledger: `kind, minute, itemID, quantity, unitA, unitB, flags,
extra`.

| kind | unitA | unitB | flags | extra |
| --- | --- | --- | --- | --- |
| PURCHASE | Stückpreis | 0 | 0 | 0 |
| SALE | Stückpreis brutto | Stückpreis netto | Güte der Zuordnung | Verkaufsdauer (1/10 h) |
| POST | Stückpreis | Einstellgebühr | Laufzeit (h) | 0 |
| EXPIRE | Stückpreis | verlorene Gebühr | 0 | 0 |
| CANCEL | Stückpreis | verlorene Gebühr | 0 | 0 |

`quantity = 0` heißt bei SALE ausdrücklich **„Stückzahl unbekannt"** – nicht
null. `itemID = 0` heißt „Item nicht auflösbar"; solche Ereignisse zählen nur in
die Gesamtsumme, nie in eine Item-Statistik.

## Was erfasst wird – und was nicht

**Erfasst wird ausschließlich, was der Client bestätigt:**

- Verkaufsrechnungen aus dem Briefkasten (`GetInboxInvoiceInfo`)
- abgelaufene und zurückgezogene Auktionen (Betreffzeile + Anhang)
- das Einstellen selbst (`PostAuction` per `hooksecurefunc`)
- Bestandsveränderungen bei Farmsitzungen
- Angebotsmengen der gerade durchblätterten Auktionsliste
- Orte, an denen der Spieler ein Fenster geöffnet hat

**Nicht erfasst wird:**

- Rückschlüsse aus Goldänderungen. Wer sein Gold zählt, weiß nicht, ob es aus
  dem AH, vom Händler oder aus einer Quest kam.
- Händler-, Post-, Handels- oder Zerstörungsvorgänge.
- Irgendetwas über andere Spieler.

## Löschen

| Befehl | Wirkung |
| --- | --- |
| `/gold marketreset confirm` | löscht **nur** die Markthistorie dieses Profils |
| `/gold ledgerreset confirm` | löscht **nur** die Handelsbilanz dieses Profils |

Beide sind zweistufig: Ohne `confirm` passiert nichts. Ein Vertipper darf keine
Wochen Realm-Daten kosten.

## Wissensbasis

`Knowledge/` wird **mit dem Addon ausgeliefert** und liegt nicht in den
SavedVariables. Jeder Eintrag trägt:

- `sourceConfidence`: `official` (Blizzard-Ankündigung oder im Spiel
  nachweisbar), `historical` (bekannter TBC-Verlauf), `inferred` (abgeleitet)
- `sourceName`: worauf sich die Aussage stützt
- `knowledgeVersion`: Stand der Wissensbasis

Was ohne Provenance kommt, wird beim Laden verworfen und gezählt (`/gold
wissen` zeigt es). Zusätzlich läuft eine Prüfung über die *Beziehungen*:
Catalysts ohne bekanntes Item, Rezeptkanten ins Leere, Zyklen im
Abhängigkeitsgraphen, exakte Termine ohne offizielle Quelle, verwaiste Items.

`Knowledge/Locations.lua` und `Knowledge/FarmRoutes.lua` sind **absichtlich
leer**: Eine geratene Koordinate schickt den Spieler aktiv in die falsche
Richtung. Beide Dateien enthalten Schema und Prüfung und sind dokumentierte
Erweiterungspunkte; die Orte, die Gold Copilot tatsächlich kennt, lernt es aus
den eigenen Besuchen des Spielers.
