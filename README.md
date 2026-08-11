# Gold Copilot 1.0.0-beta.9

<p align="center"><img src="Media/Wordmark.png" alt="Gold Copilot" width="360"></p>

**SETZ EIN GOLDZIEL. FOLGE DER ROUTE.**

Gold Copilot ist ein Standalone-Addon für **World of Warcraft: Burning Crusade
Classic Anniversary**. Es ersetzt weder TSM noch Auctionator und zeigt auch
keine zwanzig Tabellen. Es beantwortet eine einzige Frage:

> **Was soll ich jetzt tun?**

Du sagst, wie viel Gold du willst, wie viel Zeit du hast und wie viel Risiko
dir recht ist. Gold Copilot rechnet Realmpreise, deine eigene Preisgeschichte,
Crafts, Umwandlungen, Entzaubern, bekannte Phase-Catalysts, deine eigenen
Verkaufsdaten, dein verfügbares Kapital, deine offenen Positionen und deinen
Bestand zusammen – und macht daraus eine Liste von Schritten, die du abarbeitest.

```
GOLD ROUTE READY

11 Schritte
68 Minuten aktive Zeit
1.840 g Kapitalbedarf
+286 g geschätztes Potenzial
Sicherheit: mittel

[ START ]
```

Danach folgst du einem Guide – ein Schritt nach dem anderen, mit Richtungspfeil,
Preisobergrenze und einem Knopf für „Warum?".

```
┌──────────────────────────────┐
│ GOLD ROUTE       +184/500 g  │
│ Schritt 4 / 11               │
│                              │
│ KAUFE 20× URFEUER            │
│                              │
│ Maximal 21 g 00 s / Stück    │
│ Kapital: 420 g               │
│ Potenzial: +86 g             │
│                              │
│ Sicherheit: hoch             │
│                              │
│ [Warum?]  [Überspringen]     │
└──────────────────────────────┘
```

---

## Die eine Regel

**Gold Copilot tut nie so, als wüsste es mehr, als es weiß.**

Wo Daten fehlen, steht ein Satz statt einer Zahl. Es gibt keine erfundenen
Verkaufsraten, keine Gold-pro-Stunde aus fremden Guides, keine geratenen
Koordinaten, keine Kostenbasis für selbst gefarmte Stapel und keine
Angebotsmengen für Items, die du nie gesucht hast. Und wenn genug Daten da
sind, nimmt es dir die Entscheidung ab – statt dir siebzehn Diagramme zu zeigen.

---

## Was Gold Copilot kann

**Marktverständnis.** Eine eigene Preishistorie deines Realms, mehrere
Messpunkte je Tag, 30 Tage aufbewahrt. Daraus der **Market Score**: Ist der
aktuelle Preis, gemessen an seiner eigenen Geschichte, günstig?

**Chancen.** Crafts aus deinen gescannten Rezepten, Umwandlungen (Partikel,
Essenzen), Entzaubern und Resale werden zu einer Liste mit **Opportunity
Score**, ROI, Kapitalbedarf und Sicherheitsgrad – jede Zeile mit der
vollständigen Rechnung im Tooltip.

**Zukunft.** Eine gepflegte Wissensbasis über die Anniversary-Phasen: Was
kommt, wann (falls angekündigt), und welche Items hängen daran. Daraus **Future
Demand**, **Hype Score** und eine Einstiegszone – mit Quellenangabe an jeder
einzelnen Aussage.

**Liquidität.** Aus deinen eigenen, tatsächlich stattgefundenen Verkäufen:
Sell-through, mediane Verkaufsdauer, **Liquidity Score** und Profit Velocity.
Ein theoretischer Gewinn von +500 g ist wertlos, wenn das Item zehn Tage steht.

**Kapital.** Wie viel Gold ist frei, wie viel steckt in offenen Positionen, wie
viel ist Reserve? Wie stark hängst du an einem Item, einer Chancenart, einem
Catalyst? Daraus eine **Positionsgröße** und eine **Kapitalverteilung** über
mehrere Chancen – nie alles auf eine.

**Route.** Aus Chancen werden Aktionen (kaufen, herstellen, umwandeln,
einstellen, farmen), aus Aktionen wird eine Reihenfolge: Abhängigkeiten zuerst,
Wege gebündelt, Kapital- und Zeitbudget eingehalten.

**Guide.** Ein kleines Fenster zeigt genau einen Schritt. Was der Client
zweifelsfrei bestätigt, hakt sich von selbst ab. Ändert sich der Markt so, dass
der Plan nicht mehr stimmt, wird neu geplant – aber nicht wegen jeder
Silberbewegung.

**Navigation.** Ein Richtungspfeil zum nächsten Ort. Die Orte lernt Gold
Copilot aus deinen eigenen Besuchen: Wer einmal ein Auktionshaus geöffnet hat,
hat damit belegt, wo es liegt.

**Lernen.** Jede Empfehlung landet im Protokoll; jeder Kauf und Verkauf wird ihr
zugeordnet. Nach genügend Ergebnissen kannst du die Bewertung an deine eigenen
Zahlen kalibrieren – in kleinen Schritten, mit harten Grenzen und jederzeit
rücksetzbar.

---

## Die Tabs

**Zentrale** ist die Startseite: Kapital, beste Aktion jetzt, Zielmodus,
Schnellprofile. Wer nur hier arbeitet, kommt vollständig durch.

**Route** zeigt den Plan vor dem Start und die laufende Route mit Haken.

Alles Weitere ist der **Expertenmodus** und bleibt vollständig erhalten:

| Tab | Inhalt |
| --- | --- |
| Heute | Tagesplan mit Daily-Quests, Cooldowns, Farmzielen, Tagesziel |
| Verkaufen | Bestandsbewertung, bester Kanal je Item |
| Flips | Partikel- und Essenz-Umwandlungen |
| Crafts | Gewinn je gescanntem Rezept |
| Markt | eigene Preishistorie mit Market Score und Perzentil |
| Chancen | alle Chancen mit Score, ROI, Liquidität |
| Zukunft | Phasen, Catalysts, Future Demand, Hype, Einstiegszone |
| Handel | deine Handelsbilanz: Sell-through, Verkaufsdauer, Marge |
| Optionen | Preisquelle, Filter, Guide, Cash-Reserve, Kalibrierung, Daten |

---

## Voraussetzungen

Gold Copilot bringt bewusst keinen eigenen AH-Scanner mit:

- **[Auctionator](https://www.curseforge.com/wow/addons/auctionator)**
  (empfohlen) – regelmäßig einen vollständigen Scan im Auktionshaus ausführen.
- **[TradeSkillMaster](https://www.tradeskillmaster.com/)** (optional) –
  liefert `dbmarket`, wenn Auctionator keinen Preis hat.
- **[Syndicator](https://www.curseforge.com/wow/addons/syndicator)**
  (empfohlen) – damit sieht Gold Copilot Bank, Post und Twinks.
- **[Questie](https://www.curseforge.com/wow/addons/questie)** (optional) –
  prüft, welche Tagesquests freigeschaltet sind.
- **[TomTom](https://www.curseforge.com/wow/addons/tomtom)** (optional) –
  setzt Wegpunkte. Ohne TomTom bringt Gold Copilot seinen eigenen Pfeil mit.

Mindestens eine Preisquelle (Auctionator oder TSM) sollte installiert sein.
Ohne sie läuft alles weiter – es gibt dann nur nichts zu rechnen, und das steht
auch da.

## Installation

1. [Code herunterladen](https://github.com/stryker-max/GoldCopilot/archive/refs/heads/main.zip)
   und entpacken.
2. Den Ordner nach `World of Warcraft\_anniversary_\Interface\AddOns\` legen und
   in **`GoldCopilot`** umbenennen (GitHub hängt sonst `-main` an – der
   Ordnername muss exakt `GoldCopilot` lauten).
3. WoW neu starten und am Charakterbildschirm unter „AddOns" aktivieren.

## So kommst du in Gang

1. `/gold` öffnen, den Willkommenstext lesen, `[Los geht's]`.
2. Einmal **alle Berufsfenster öffnen**, damit die Rezepte bekannt sind.
3. Im Auktionshaus einen **vollständigen Auctionator-Scan** ausführen.
4. In der Zentrale Goldziel, Zeit und Risiko wählen.
5. `[GOLD ROUTE ERSTELLEN]`, dann `[ROUTE STARTEN]`.
6. Dem Guide folgen. Handle wie immer – Gold Copilot lernt aus deinen Käufen,
   Verkäufen, Abläufen und Farmsitzungen mit und wird mit jeder Sitzung besser.

## Befehle

| Befehl | Wirkung |
| --- | --- |
| `/gold` | Fenster öffnen und schließen (`/goldcopilot` geht auch) |
| `/gold route [profil]` | Route planen (`quick_gold`, `max_profit`, `low_risk`, `grow_capital`, `trading`, `crafting`, `farming`, `future_investing`) |
| `/gold start` | Route starten |
| `/gold pause` | Route anhalten oder fortsetzen |
| `/gold stop` | Route abbrechen |
| `/gold guide` | Guide-Fenster ein-/ausblenden |
| `/gold warum` | Begründung des aktuellen Schritts im Chat |
| `/gold ziel 500` | Goldziel setzen (in Gold) |
| `/gold zeit 90` | Zeitbudget setzen (in Minuten) |
| `/gold diagnostics` | kompakte Diagnose für Fehlerberichte |
| `/gold debug on` / `off` | Debugausgaben ein-/ausschalten |
| `/gold debug <bereich>` | `market`, `opportunity`, `future`, `ledger`, `capital`, `execution`, `route`, `guide`, `farm`, `personal` |
| `/gold chancen`, `zukunft`, `handel` | direkt in den jeweiligen Tab |
| `/gold farm start` / `stop` | Farmsitzung messen (auch als Knopf in der Zentrale) |
| `/gold farm`, `wissen`, `watchlist` | Kurzübersichten im Chat |
| `/gold marketstats`, `ledgerstats` | Umfang und Zustand der Speicher |
| `/gold marketreset confirm` | löscht **nur** die Markthistorie |
| `/gold ledgerreset confirm` | löscht **nur** die Handelsbilanz |
| `/gold reset` | setzt die Tagesplan-Checkliste zurück |
| `/gold hilfe` | diese Liste im Spiel |

Shift-Klick auf eine Zeile verlinkt das Item im Chat. Rechtsklick im Markt-,
Chancen- oder Zukunft-Tab nimmt ein Item in die Beobachtungsliste auf. Jede
Empfehlung erklärt sich im Tooltip – mit Rechnung, Preisbasis und dem, was
Gold Copilot über dieses Item **nicht** weiß.

---

## Deine Daten

Alles bleibt lokal in deinen SavedVariables. Es gibt keine Übertragung, keinen
Abgleich, keinen Server und keinen Netzwerkzugriff – Addons können das nicht,
und Gold Copilot tut auch nicht so.

Markt- und Handelsdaten werden **je Realm und Fraktion getrennt** gespeichert:
Das Auktionshaus der Horde auf Realm A hat mit dem der Allianz auf Realm B
nichts zu tun. Optionen, Goldverlauf, gelernte Quest-Beträge und Rezepte
bleiben accountweit.

Details: [`docs/DATA.md`](docs/DATA.md).

## Was Gold Copilot bewusst nicht tut

- **Nichts automatisieren.** Es kauft, verkauft und läuft nichts. Es sagt, was
  zu tun ist; getan wird es von dir.
- **Nichts erfinden.** Kein Preis, keine Rate, keine Koordinate und keine
  Verkaufsdauer ohne Beleg.
- **Nichts behaupten, was der Client nicht hergibt.** Der Classic-Client kennt
  keine Auktions-ID; die Zuordnung Einstellung → Verkauf ist immer eine
  Rekonstruktion, und das steht auch dran.
- **Keine Marktmanipulation unterstellen.** Ungewöhnliche Angebotsstrukturen
  werden beschrieben, nicht erklärt – warum jemand so anbietet, weiß niemand.
- **Keine Zukunft vorhersagen.** Ein Catalyst ist ein bekannter Zusammenhang,
  keine Preisprognose.

## Bekannte Grenzen

- **Orte und Farmrouten** kennt Gold Copilot nur aus deinen eigenen Besuchen.
  Die kuratierten Wissensdateien dafür sind absichtlich leer.
- **Markttiefe** entsteht nur für Items, die du im Auktionshaus gesucht hast,
  und gilt für die angezeigte Seite – gemessene Mengen sind Untergrenzen.
- **Farmraten** entstehen erst nach mehreren eigenen Sitzungen.
- **Kalibrierung** läuft erst ab 40 abgeschlossenen Ergebnissen und ist
  voreingestellt aus.
- **Zwischenstufen-Mengen** (Netherstoffballen, Adamantitbarren) sind als
  Beziehung hinterlegt, die genaue Stückzahl steht bewusst auf `nil`.
- **Spätere Phasen** (Zul'Aman, Sonnenbrunnen) sind inhaltlich modelliert,
  aber ohne Termin und ohne Item-Catalysts.

---

## Technische Dokumentation

| Dokument | Inhalt |
| --- | --- |
| [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) | Pipeline, Module, Caches, was bewusst fehlt |
| [`docs/MODELS.md`](docs/MODELS.md) | Alle Formeln und ihre Herleitung |
| [`docs/DATA.md`](docs/DATA.md) | SavedVariables-Schema, Grenzen, Aufbewahrung, Realmtrennung |
| [`docs/TESTING.md`](docs/TESTING.md) | Testaufbau, Simulationsschicht, Invarianten |
| [`docs/INGAME_TEST.md`](docs/INGAME_TEST.md) | manuelle Testcheckliste für den Client |

## Mitarbeit

```
npm install
npm test
```

`npm test` prüft die Struktur und führt 2453 Zusicherungen in vier
Lua-Testdateien aus. Vor jedem Push muss es grün sein.

Neue Item- oder Zauber-IDs vor dem Eintragen gegen die lokalen Questie-/
AtlasLoot-Datenbanken prüfen – nicht raten. Jeder Eintrag in `Knowledge/`
braucht `sourceConfidence` und `sourceName`, sonst wird er beim Laden verworfen.

## Lizenz

MIT – siehe [LICENSE](LICENSE).
