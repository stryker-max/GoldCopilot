# Stand und offene Punkte

## Erledigt in 1.0.0-beta.1

Die Entscheidungsschicht steht: Capital Brain, Execution Engine, Route Planner,
Guide Engine, Navigation, Farm Brain, Personal Brain, Analytics, Kalibrierung
und Markttiefe. Dazu die Zentrale als Startseite, der Guide Viewer, die
Realm- und Fraktionstrennung, `/gold diagnostics` und `/gold debug`, 18
End-to-End-Szenarien und die Dokumentation in `docs/`.

Damit ist die Produktvision abgeschlossen: **Ziel setzen, Route bekommen,
Schritten folgen.** Was jetzt zählt, ist der Ingame-Test –
`docs/INGAME_TEST.md` ist die Checkliste dafür.

## Was bewusst offen bleibt

Diese Punkte sind **keine geplanten Features**, sondern die Stellen, an denen
Gold Copilot heute ehrlich sagt, dass es etwas nicht weiß. Sie sind als
Erweiterungspunkte gebaut und werden gefüllt, sobald es belastbare Daten gibt –
nicht vorher.

### Ortswissen

`Knowledge/Locations.lua` ist leer. Gold Copilot lernt Orte aus den eigenen
Besuchen des Spielers, und das ist genauer als jede kuratierte Liste. Wer die
Datei füllt, muss je Eintrag belegen können, woher Karte und Koordinate
stammen; `RegisterLocation` nimmt nichts ohne `sourceConfidence` und
`sourceName` an.

### Farmrouten

`Knowledge/FarmRoutes.lua` ist ebenfalls leer. Die **Raten** lernt der Farm
Brain aus eigenen Sitzungen; was fehlt, sind belegte **Wege**. Eine falsche
Farmroute kostet genau die Zeit, die sie sparen soll.

### Wissensbasis

Datenqualität vor Umfang. Offen und ausdrücklich **nicht** erfunden:

- **Mengen der Zwischenstufen** (Netherstoffballen, Adamantitbarren): Die
  Beziehung ist gesichert und als Kante hinterlegt, die genaue Stückzahl steht
  bewusst auf `nil`.
- **Weitere Widerstandssets**: Redeemed Soul (Leder) und Shackled Souls (Kette)
  sind über den Materialkatalog abgedeckt, aber noch ohne eigene Rezeptkanten.
- **Netherschwingen**: als Phaseninhalt vermerkt, ohne Item-Catalyst – ein
  belastbarer wirtschaftlicher Zusammenhang fehlt bislang.
- **Spätere Phasen**: Zul'Aman und Sonnenbrunnen sind inhaltlich modelliert,
  aber ohne Termin und ohne Item-Catalysts.

### Externe Integrationen

- **Journalator** protokolliert genau die Ereignisse, die `Ledger.lua` selbst
  erfasst, hat aber keine dokumentierte öffentliche API. Der Einstiegspunkt
  `Ledger:CaptureFromExternal()` steht bereit, falls sich das ändert.
- **Markttiefe aus einem Vollscan**: Der Client gibt Angebotsmengen nur für die
  angezeigte Liste heraus. Gäbe eine Preisquelle Mengen als API heraus, wäre
  `Market:RecordDepth()` der Einstiegspunkt.

### Grenzen des Clients

- Die klassische Auktions-API kennt **keine Auktions-ID**. Die Zuordnung
  Einstellung → Verkauf bleibt eine Rekonstruktion, und das steht überall dran,
  wo es zählt.
- Die Verkaufsrechnung nennt **keine Stückzahl**. Verkäufe ohne Stückzahl
  zählen in den Umsatz, aber in keine Stückzahl-Statistik – und sie schalten
  die stückzahlbasierte Sell-through-Rate des Items ab.
- **Entfernungen** gibt es nur, wenn `C_Map.GetWorldPosFromMapPos` vorhanden
  ist. Sonst bleibt die Richtung, und die Entfernung bleibt leer.
