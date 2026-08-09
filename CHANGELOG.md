# Changelog

## 0.7.0 – 2026-08-09

Future Market. 0.5.0 beantwortet „wie steht der Preis relativ zur eigenen
Vergangenheit?“, 0.6.0 „ist daraus gerade eine Gold-Chance ableitbar?“ – 0.7.0
beantwortet zum ersten Mal: **„Welche bereits bekannten Veränderungen im Spiel
könnten die Nachfrage nach diesem Item verändern?“**

- **Neue Wissensbasis `Knowledge/`**, strikt getrennt von jeder Rechenlogik:
  `Knowledge.lua` (Register, Prüfung, Nachschlagen), `Phases.lua` (Phasen),
  `Items.lua` (45 geprüfte Items), `Recipes.lua` (Rezeptkanten),
  `Catalysts.lua` (24 Catalysts). Sie wird mit dem Addon ausgeliefert – ein
  WoW-Addon kann keine Webseiten abrufen, und das ist hier die Bauform, kein
  Mangel. Der Wissensstand steht sichtbar im Zukunft-Tab und in den Optionen;
  die Struktur ist so schlicht gehalten, dass sich diese Dateien später aus
  einer externen Datenpipeline erzeugen lassen.
- **Keine Behauptung ohne Provenance.** Jeder Eintrag trägt `sourceConfidence`
  (`official` / `historical` / `inferred`) und eine benannte Quelle; ohne beides
  wird er beim Laden **verworfen und gezählt** statt still übernommen. `/gold
  wissen` zeigt Umfang und Verworfenes.
- **Harte Termin-Regel**: Ein exaktes Datum steht nur da, wenn Blizzard es für
  die **Anniversary-Realms** angekündigt hat (Phase 3: 27.08.2026, 15:00 PDT).
  Termine aus dem ursprünglichen TBC oder aus TBC Classic werden nie
  übernommen – Zul'Aman und Sonnenbrunnen sind inhaltlich modelliert, tragen
  aber `release = nil`, und die Oberfläche schreibt „Termin offen“. Die
  Umrechnung läuft zeitzonenfrei über eine eigene UTC-Rechnung statt über
  `time({...})`.
- **Neues Modul `Future.lua`** mit `GetCurrentPhase`, `GetUpcomingPhases`,
  `GetItemKnowledge`, `GetCatalysts`, `GetFutureDemandScore`, `GetHypeScore`,
  `GetInvestmentSignal`, `GetExplanation` und `BuildReport`. Es enthält
  ausschließlich Logik, kein Spielwissen; alle Stellschrauben stehen in
  `Constants.lua` unter `FUTURE`.
- **Dependency Graph** über die Lieferkette: Ein Catalyst am Produkt erreicht
  dessen Zutaten zu 70 %, deren Zutaten zu 40 %, ab Ebene 3 gar nicht mehr.
  Ohne diese Grenze wäre nach fünf Ebenen jedes Material der Scherbenwelt
  „extrem bullish“. Kreise (die Ur-Partikel lassen sich im Kreis transmutieren)
  werden erkannt. Der Graph speist sich aus der Wissensbasis, den Umwandlungen
  aus `Constants.lua` und **deinen gescannten Rezepten** – die kommen direkt
  aus dem Spielclient und sind damit die beste Quelle überhaupt.
- **Future Demand Score 0–100** (50 = neutral): Jeder Catalyst wird mit
  `strength × Confidence × Provenance × Zeitfenster × Ebene` gewichtet;
  Nachfrage- und Angebotsseite werden getrennt mit abnehmendem Ertrag summiert
  (der zweite Grund zählt 60 %, der dritte 36 %), laufen durch eine
  Sättigungskurve und werden gegeneinander verrechnet. Ein Angebots-Catalyst
  kann einen Nachfrage-Catalyst neutralisieren – genau das passiert beim
  Leitmaterial einer neuen Phase. **Kein Opportunity Score und keine
  Preisprognose.**
- **Hype Score 0–100** ausschließlich aus eigenen Realm-Daten: Aufschlag zum
  30-Tage-Median (35 %), Perzentil (25 %), Momentum 7d gegen 30d (25 %),
  Volatilität (15 %). Ohne belastbare Historie gibt es **gar keinen** Hype
  Score statt eines niedrigen – „kein Hype“ wäre hier die gefährlichste
  Falschaussage.
- **Future Opportunity Score 0–100**, ausdrücklich **nicht** Market Score mal
  Future Demand, sondern ein Aufbau um die Mitte: `50 + 0,5 × (Demand − 50)
  + 0,35 × (Market − 50) − 0,6 × max(0, Hype − 50) + Zeitfensterbonus
  − Volatilitätsabschlag`, gedeckelt durch Wissens-Confidence **und**
  Realm-Datenlage. Ohne eigene Historie ist bei 55 Schluss, egal wie stark der
  Catalyst ist.
- **Zeitfenster** EARLY / ACCUMULATION / PRE_RELEASE / RELEASE / POST_RELEASE.
  Bewusst nicht „je näher, desto besser“: Kurz vor Release ist eine bekannte
  Ankündigung meist längst eingepreist.
- **Einstiegszone statt Kaufkurs**: Anker ist das untere Quartil der eigenen
  30-Tage-Verteilung, gebremst durch den 7-Tage-Median, abzüglich eines
  Abschlags, der mit dem Hype Score wächst. Reicht die Datenbasis nicht, steht
  dort „noch keine belastbare Einstiegszone“. Dazu die Warnung **„nicht
  hinterherlaufen“**, sobald der Preis deutlich über der eigenen Spanne liegt.
- **Neuer Tab „Zukunft“** mit dem nächsten bekannten Catalyst (Phase, Inhalt,
  Tage bis Release, Provenance) und der nach Signal sortierten Liste: Item,
  Markt, Demand, Hype, Catalyst, Signal. Der Tooltip zeigt Preis, Mediane,
  jeden einzelnen Grund, Hype, Einstiegszone und Signal – und trennt dabei
  **Fakt von Modell**.
- **„Warum?“-Engine**: `Future:GetExplanation(itemID)` liefert strukturierte
  Gründe (`positive`, `negative`, `warnings`, `facts`) statt einer fertigen
  Textwand, jede Zeile mit ihrer Art (`fact` / `model`) und ihrer Quelle.
- **Watchlist mit These**: Ein Rechtsklick im Zukunft-Tab merkt sich zusätzlich
  Phase, These und Wunsch-Einstieg. Einträge aus 0.6 bleiben unverändert
  gültig – die Liste wird erweitert, nicht ersetzt.
- **Protokoll erweitert**: Future-Signale landen als `type = "future"` in
  `db.opportunityHistory` – mit Market-, Demand-, Hype- und Signal-Score,
  Phase, Tagen bis zum Catalyst und den beteiligten Catalyst-IDs. Dieselbe
  Zeile höchstens alle sechs Stunden, dazwischen nur bei deutlicher Bewegung.
  Die Einträge aus 0.6 bleiben unverändert lesbar.
- **Market Engine**: Die Items der Wissensbasis melden sich automatisch zur
  Beobachtung an (Grund „Zukunft“, hohe Priorität) – wer erst am Releasetag
  anfängt zu messen, hat nichts zu vergleichen. `Market:GetStats` weist die
  Quartile `q25`/`q75` jetzt einzeln aus; sie waren ohnehin schon berechnet.
- **0.8 bleibt vorbereitet**: `liquidity`, `sellThrough`, `expectedHours`,
  `profitVelocity` und `liquidityScore` bleiben in 0.7 ausdrücklich `nil`. Ein
  erfundener Standardwert wäre schlimmer als eine fehlende Zahl.
- **Tests**: 1.140 Zusicherungen (vorher 851). Neu geprüft werden Phasenzustand
  und unbekannte Termine, die zeitzonenfreie UTC-Rechnung, alle Zeitfenster,
  Provenance-Pflicht und Ablehnung ungültiger Einträge, Propagation über die
  Ebenen 0/1/2 und ihr Abbruch ab Ebene 3, Kreise im Graphen, Confidence- und
  Provenance-Gewichtung, Angebots-Catalysts, alle vier Hype-Signale und der
  fehlende Score bei dünner Historie, Einstiegszone und „nicht
  hinterherlaufen“, alle Deckel des Signals, die Trennung von Fakt und Modell,
  Watchlist-Kompatibilität mit 0.6, das erweiterte Protokoll und das Rendern
  des neuen Tabs samt Kaltstart und unbekanntem Termin.

## 0.6.0 – 2026-08-09

Aus dem Market Brain wird eine Opportunity Engine. 0.5.0 beantwortet „ist der
aktuelle Preis relativ zur eigenen Historie günstig?“ – 0.6.0 beantwortet zum
ersten Mal „ist das eine interessante Gold-Chance?“.

- **Neues Modul `Opportunity.lua`** mit der öffentlichen Schnittstelle
  `GCP.Opportunity:Get(itemID)` und `GCP.Opportunity:BuildReport()`. Es erfindet
  bewusst keine neue Rechnung, sondern orchestriert die vorhandenen: Market
  Score und Volatilität aus `Market.lua`, Planungspreise und AH-Gebühr aus
  `Prices.lua`, Rezeptgewinne aus `Crafts.lua`, Umwandlungen aus `Flips.lua`,
  Bestand aus `Inventory.lua`. **Der Market Score bleibt unverändert** und
  bedeutet weiterhin ausschließlich „historisch günstig“.
- **Opportunity Score 0–100** als eigene, neue Kennzahl. Bewusst keine
  gewichtete Fantasieformel, sondern ein Punktebudget aus vier Gutschriften und
  zwei Abschlägen, jeder mit eigener Obergrenze und als Konstante in
  `Constants.lua` kalibrierbar:
  `Margin Quality (0–35, aus der ROI) + Profit Scale (0–15, absolute Größe)
  + Market Attractiveness (0–25) + Data Quality (0–25)
  − Volatility Risk (0–15) − Capital Penalty (0–15)`.
  Margin und Profit laufen über Sättigungskurven (halbe Punktzahl bei 25 % ROI
  bzw. 10 g Gewinn) statt linear – 500 % sind besser als 50 %, aber nicht
  zehnmal so gut. Ein fehlender Market Score zählt neutral als 50 („keine
  Aussage“), nicht als 0. **Score und Confidence bleiben getrennt**; die
  Confidence deckelt zusätzlich hart auf 55 (niedrig) bzw. 80 (mittel), und
  ohne jede Datenbasis gibt es **gar keinen Score** statt der Note 0.
- **Vier Arten von Chancen**, alle ausschließlich aus vorhandenen Daten:
  - **Conversion**: Motes » Ur-Partikel (10:1) und Essenzen 3:1 in beide
    Richtungen, mit Einkaufskosten, Erlös netto, Profit, ROI und Preisbasis.
  - **Craft**: Materialkosten gegen Produkterlös netto aus den gescannten
    Rezepten, samt erforderlichem Kapital und machbarer Stückzahl. Fehlt ein
    Preis, entsteht keine Chance – gezählt statt geschätzt.
  - **Entzaubern**: Kaufpreis gegen Auctionators Entzauber-Erwartungswert netto,
    nur für tatsächlich entzauberbare, handelbare Items und nur wenn der
    Erwartungswert über dem Kaufpreis liegt. Eigene Dropchancen werden
    ausdrücklich nicht erfunden.
  - **Resale**: aktueller Preis gegen einen **konservativen Zielpreis**
    `min(7-Tage-Median, 30-Tage-Median)` minus AH-Gebühr, und nur ab Market
    Score 70. Der volle 30-Tage-Median wäre der bequemere Wert – genau deshalb
    wird er nicht genommen.
- **Kein Double Counting**: Die AH-Gebühr fällt genau einmal an, immer auf der
  Verkaufsseite; Kaufen kostet keine Gebühr; Materialkosten zählen genau
  einmal; Craft- und Flip-Rechnung werden wiederverwendet statt nachgebaut.
  Jede dieser Zusagen hat einen eigenen Test.
- **Neuer Tab „Chancen“**: oben eine Zeile („Gold Copilot hat 7 interessante
  Chancen gefunden“), darunter die Liste nach Score – Score, Typ, Aktion,
  Kapital, Profit, ROI. Der Tooltip zeigt die komplette Rechnung samt Market
  Score, Confidence und den Grenzen dieser Version. Formuliert wird
  „interessant“, „sehr interessant“, „beobachten“ – **nie „kaufen“**.
- **Eigene Filter für die Chancen**: Mindestprofit (1/5/10/25/50 g,
  voreingestellt 1 g) und Mindest-ROI (0/5/10/20/30 %, voreingestellt 5 %),
  gespeichert als `options.opportunityMinProfit` und
  `options.opportunityMinROI` – **getrennt** vom Mindestgewinn des Tagesplans,
  der unverändert weiterläuft. Ausgefiltertes wird in der Kopfzeile gezählt,
  statt lautlos zu verschwinden; dasselbe gilt für den Zeilendeckel.
- **Deduplikation**: Zwei Rezepte zum selben Produkt ergeben eine Chance, nicht
  zwei. Taucht ein Item über mehrere unabhängige Wege auf (etwa Craft und
  Resale), bleiben die Zeilen getrennt – es sind verschiedene Geschäfte –,
  wissen aber voneinander und sagen es in der Zeile dazu.
- **Beobachtungsliste** als Grundlage für Future Market 0.7: `db.watchlist`
  mit `Market:RegisterWatchItem`, `RemoveWatchItem`, `IsWatched`,
  `ToggleWatchItem` und `GetWatchlist` (unter denselben Namen auch auf
  `GCP.Opportunity`). Beobachtete Items landen automatisch und mit höchster
  Priorität in `Market:GetTrackedItems()`. Aufgenommen wird per **Rechtsklick**
  auf eine Zeile im Markt- oder Chancen-Tab; `/gold watchlist` zeigt sie.
- **Chancen-Protokoll** `db.opportunityHistory` als Datenmodell für spätere
  Treffsicherheits-Auswertungen. Bewusst zurückhaltend geschrieben: nur ab 60
  Punkten und mittlerer Confidence, dieselbe Chance höchstens alle sechs
  Stunden, dazwischen nur bei merklich verändertem Score oder Gewinn, 90 Tage
  Aufbewahrung, harte Obergrenze. **Ein UI-Refresh schreibt nie**: protokolliert
  wird ausschließlich beim echten Neuberechnen, nie bei einem Cache-Treffer.
- **Vorbereitet für 0.7, aber leer**: `liquidity`, `sellThrough`,
  `expectedHours`, `profitVelocity`, `futureDemandScore`, `liquidityScore`,
  `hypeScore`, `riskScore`, `catalysts`, `phase` und `exitWindow` stehen im
  Datenmodell jeder Chance und bleiben `nil`. Ein erfundener Standardwert wäre
  schlimmer als eine fehlende Zahl.
- **Performance**: Der Chancenbericht wird gecacht. Verworfen wird er, sobald
  sich etwas ändert, das das Ergebnis wirklich beeinflusst – neue Marktdaten
  (`Market.revision`), neu gescannte Rezepte (`Crafts.revision`), geänderte
  Filter oder Preisquelle, geänderte Watchlist. Für den Bestand, der keine
  Invalidierungs-Ereignisse liefert, kommt eine kurze Frist dazu. `Crafts:BuildReport`
  nimmt jetzt optional einen bereits gescannten Bestand entgegen, statt ihn ein
  zweites Mal einzusammeln.
- **Optionen-Tab scrollt**: Mit den neuen Abschnitten passte der Inhalt nicht
  mehr ins Fenster – eine abgeschnittene Erklärung ist schlimmer als eine
  Bildlaufleiste.
- **Neue Befehle**: `/gold chancen` öffnet den Chancen-Tab, `/gold watchlist`
  listet die beobachteten Items. `/gold marketstats` nennt zusätzlich die Größe
  der Beobachtungsliste.
- **Rückwärtskompatibel**: `db.watchlist` und `db.opportunityHistory` legen sich
  leer an, die neuen Optionen bekommen ihre Standardwerte. Preishistorie,
  Markthistorie, Goldverlauf, Rezepte, Questgold, Ignorierliste und der
  Mindestgewinn des Tagesplans bleiben unangetastet – dafür gibt es Tests mit
  Datenbanken aus 0.3, 0.4, 0.5 und 0.6.
- **Tests**: 851 Zusicherungen (vorher 441) – Score-Formel Punkt für Punkt
  nachgerechnet, alle vier Chancenarten, AH-Gebühr genau einmal, ROI, beide
  Filter, Confidence-Deckel, kein Score bei zu wenig Daten, Deduplikation,
  Gruppierung, Cache-Invalidierung, Watchlist samt Deckel, Protokoll samt
  Aufbewahrung, Rendern des Chancen-Tabs und Rechtsklick-Beobachtung.

## 0.5.0 – 2026-08-09

Die Datengrundlage. Gold Copilot merkt sich ab jetzt, wie sich Preise über den
Tag bewegen – und sagt, wie der aktuelle Preis dazu steht.

- **Market Recorder**: Neben der bisherigen Tages-Preishistorie liegt jetzt
  `db.marketHistory`, eine echte Zeitreihe mit mehreren Messpunkten pro Tag.
  Gespeichert wird pro Item eine flache Liste aus Paaren (Minuten seit einem
  gemeinsamen Bezugszeitpunkt, Preis in Kupfer) statt einer Tabelle je
  Messpunkt – rund 13 Zeichen statt 50, also etwa ein Zehntel der Dateigröße
  bei identischem Informationsgehalt. Begrenzt durch: höchstens ein Punkt je
  Item und 30 Minuten, ein unveränderter Preis höchstens alle zwei Stunden,
  400 Punkte je Item, 500 beobachtete Items, 30 Tage Aufbewahrung mit
  automatischem Aufräumen. Ungültige Preise (nil, 0, negativ, NaN, unendlich,
  Text) werden nie gespeichert. **`db.priceHistory` bleibt unverändert** und
  versorgt weiterhin die Planungspreise von Tagesplan, Flips und Craft-Radar.
- **Auctionator-Callback statt nur AH-Schließen**: Ist
  `Auctionator.API.v1.RegisterForDBUpdate` in der geladenen Fassung wirklich
  vorhanden, hängt sich Gold Copilot dort ein und zeichnet direkt nach jedem
  Scan auf. Geprüft wird zur Laufzeit, nicht am Namen; registriert wird in
  `pcall`. `AUCTION_HOUSE_CLOSED` bleibt als Rückfall bestehen. Ein Vollscan
  meldet das Datenbank-Update viele Male – daraus wird durch Entprellung
  (20 s) genau ein Schreibdurchlauf, und das 30-Minuten-Fenster je Item
  begrenzt ihn auf höchstens einen Punkt pro Markt.
- **Beobachtete Items statt aller Items**: `Market:GetTrackedItems()` sammelt
  Farmziele, Flip- und Rezeptzutaten, den Accountbestand (nur was das AH
  annimmt) und alles mit vorhandener Historie – jeweils mit Begründung. Andere
  Module melden sich über `Market:RegisterItem(itemID, reason)` an; die
  Watchlist späterer Versionen braucht dafür keine Änderung an diesem Modul.
- **Marktstatistik**: aktueller Preis, 24h-/7d-/30d-Median, Minimum und
  Maximum der letzten 7 Tage, Anzahl Messpunkte, Anzahl unterschiedlicher Tage,
  robuste Volatilität (Quartilsabstand geteilt durch Median – unempfindlich
  gegen die eine Dumping-Auktion) und das **Preis-Perzentil** nach der
  Mittelrang-Methode. Ohne Fremdbibliothek: Median und Quantile mit linearer
  Interpolation, gleiche Werte zählen halb – ein flacher Markt steht damit im
  50. Perzentil und nicht fälschlich im nullten.
- **Market Score 0–100** (`Market:GetMarketScore(itemID)`): 55 % Perzentil,
  45 % Abstand zum 7- und 30-Tage-Median, gedämpft durch Volatilität und
  Datenqualität – jeweils Richtung 50 („keine Aussage“), nie Richtung „teuer“.
  Die Formel steht ausführlich kommentiert in `Market.lua`, damit sie sich an
  echten Daten nachjustieren lässt. **Score und Confidence bleiben getrennt**;
  die Confidence deckelt den Score zusätzlich auf 68 (niedrig) bzw. 85
  (mittel). Unter drei Messpunkten gibt es gar keinen Score.
- **Neuer Tab „Markt“**: Zusammenfassung („Gold Copilot beobachtet 47 Märkte ·
  1.284 Preispunkte · 12 Tage Historie“) und eine Tabelle mit Item, Jetzt,
  7T-Median, 30T-Median, Perzentil und Score, sortiert nach dem höchsten Score.
  Der Tooltip zeigt alle Kennzahlen und erklärt das Ergebnis in einem Satz.
  **Kein BUY/SELL** – der Score sagt nur, wie der Preis zur eigenen Historie
  steht, und der Tooltip schreibt ausdrücklich hin, dass Nachfrage und
  Liquidität darin nicht vorkommen.
- **Kaltstart wird ausgesprochen**: Ohne Historie steht im Markt-Tab „Gold
  Copilot lernt deinen Realm“ statt einer Tabelle aus Platzhaltern.
- **Übernahme der 0.4-Daten**: Vorhandene Tageswerte aus `priceHistory` wandern
  einmalig als je ein Messpunkt pro Tag in die Markthistorie. Die Preise sind
  echte Beobachtungen; nur die Uhrzeit ist mangels besserer Information auf
  12 Uhr mittags gesetzt – das steht so im README.
- **Neue Befehle**: `/gold marketstats` (beobachtete Items, Preispunkte,
  ältester und jüngster Punkt, Spanne, geschätzte Dateigröße, Zustand des
  Auctionator-Callbacks) und `/gold marketreset`, das ohne `confirm`
  ausdrücklich nichts tut. `/gold marketreset confirm` löscht **ausschließlich**
  `db.marketHistory`.
- **Performance**: beobachtete Items, Statistik je Item und die Zusammenfassung
  sind gecacht und werden verworfen, sobald neue Messpunkte geschrieben werden.
  Kein voller Durchlauf über die Reihen bei jedem Preisupdate; das Aufräumen
  läuft höchstens stündlich, ein Schreibdurchlauf höchstens minütlich.
- **Tests**: 441 Prüfungen (vorher 232). Neu unter anderem Snapshot-Schreiben,
  30-Minuten-Drosselung, Plateau-Kompression, Retention, ungültige Preise,
  Median, Perzentil, Min/Max, Volatilität, Score, Confidence-Stufen, Kaltstart,
  Obergrenze je Item, unverändertes Weiterleben bestehender SavedVariables,
  `marketreset` und der Nachweis, dass 200 Auctionator-Meldungen genau einen
  Snapshot je Item erzeugen. Dazu ein eigener Render-Test (`tests/ui.lua`), der
  jeden Tab einmal ohne und einmal mit Historie zeichnet.

## 0.4.0 – 2026-08-09

Der Plan folgt jetzt dem Server, und jede Empfehlung erklärt sich selbst.

- **Tagesplan am WoW-Daily-Reset statt um Mitternacht**: Die Checkliste wird
  neu, wenn der Server seine Dailies zurücksetzt – ermittelt über
  `GetQuestResetTime()`, mit dem bisherigen lokalen Kalendertag als Rückfall.
  Vorher leerte sich der Plan um 0 Uhr, während die Dailies noch stundenlang
  gesperrt blieben; abends abgegebene Quests standen danach wieder als offen
  in der Liste. `db.roadmap.day` bleibt der Schlüssel, enthält nun aber die
  Resetperiode. **Goldverlauf und Preishistorie bleiben bewusst beim
  Kalendertag** – das sind Zeitreihen, keine Checkliste. `/gold reset`
  funktioniert unverändert.
- **Questbelohnungen realistisch bewertet**: Feste Belohnungen kannten bisher
  nur den AH-Preis und zählten ohne Marktpreis als 0 – ein Ring, den der
  Händler für 8 g nimmt, war „wertlos“. Jetzt gilt für feste und
  Auswahlbelohnungen dieselbe Rechnung: **max(AH netto, Händlerpreis)**, ohne
  Marktpreis der Händlerwert. Was gar nicht ins AH darf (beim Aufheben oder
  per Quest gebunden, graue Qualität), wird auch nicht so bewertet. Bei
  Auswahlbelohnungen zählt weiterhin nur die beste, und der Tooltip nennt,
  woher der Wert stammt.
- **Preise nach dem Auktionshaus auffrischen**: `AUCTION_HOUSE_CLOSED` löst
  eine weitere Aufzeichnung der Preishistorie aus – genau dann sind die
  Scandaten am frischesten. Gedrosselt auf einmal pro Minute, damit
  mehrfaches Auf- und Zumachen nichts durchrechnet; während des Einstellens
  von Auktionen passiert weiterhin nichts.
- **Datenqualität sichtbar**: Neue Helfer `Prices:GetPlanningConfidence()` /
  `GetPlanningPriceInfo()` benennen die Belastbarkeit des 7-Tage-Medians –
  0 Tageswerte = Momentanpreis, 1–2 = wenig Daten, 3–5 = mittlere, 6–7 = gute
  Datenbasis. Jede Empfehlung nennt sie im Tooltip: „Preisbasis:
  7-Tage-Median · 6 Tageswerte · gute Datenbasis“. Bei Crafts und Flips zählt
  die schwächste beteiligte Preisreihe.
- **Empfehlungen nachvollziehbar**: Der Tooltip zeigt jetzt die Rechnung –
  Craft: Produktwert netto, Zutatenwert, erwarteter Gewinn. Farm: Marktpreis,
  angenommene Rate, Erwartung je Stunde. Flip: Einkauf/Zutaten, Verkauf
  netto, Gewinn. Dazu jeweils die Preisbasis.
- **Tooltip im Tab „Heute“ repariert**: Er hing an einem Item-Link und
  erschien deshalb bei Tagesplanzeilen nie – die dort schon vorhandenen
  Zeit- und Gold-je-Minute-Angaben waren unsichtbar. Zeilen mit Item zeigen
  jetzt zusätzlich den Item-Tooltip.

## 0.3.0 – 2026-08-08

Zweiter Umbau nach Ingame-Feedback.

- **Abgeschnittene Zeilen behoben**: Die rechte Spalte wird jetzt von rechts
  nach links gesetzt, der Text bekommt den ganzen Rest. Vorher waren feste
  300 Pixel reserviert – auch wenn dort nichts stand. Zusatzangaben
  (Gebiet, Restzeit, „je Stunde“) stehen als eigene Spalte statt in Klammern
  im Text.
- **Goldsumme je Kategorie** in jeder Abschnittsüberschrift.
- **Tagesziel** einstellbar (100 g bis 2.500 g). Der Tab „Heute“ zeigt den
  **schnellsten Weg dorthin**: offene Aufgaben nach Gold je Minute sortiert,
  nummeriert als „Plan 1, 2, 3 …“, mit Zeit- und Goldsumme. Farmen landet
  dadurch dort, wo es hingehört – hinter allem, was schneller zahlt.
- **Mehr Dailies**: Dungeon-Daily normal (Netherpirscher Mah'duun) und
  heroisch (Windhändler Zhareem), Kochkunst-Daily (Der Rokk) und Angel-Daily
  (der alte Barlo) – je eine Zeile pro Questgeber statt einer je Quest, mit
  Level-, Berufs- und Skillprüfung. Ist Questie geladen, entscheidet dessen
  Freischaltungslogik.
- **Echte Questbeträge**: Beim Abgeben liest Gold Copilot den tatsächlich
  überwiesenen Betrag mit und rechnet danach damit; bis dahin steht „ca.“.
- **Quests abgeben**: Abgabebereite Quests aus dem Questlog stehen mit dem
  Wert ihrer Belohnung (Gold plus beste Auswahlbelohnung netto) im Tagesplan.
- **Eigenbedarf**: Tränke, Elixiere und Essen werden nicht mehr zum Verkauf
  vorgeschlagen – ihr Wert steht weiter im Verkaufen-Tab, markiert mit
  „Eigenbedarf“. Abschaltbar in den Optionen.
- **Ignorieren repariert**: Doppelklick wird jetzt selbst erkannt (das
  OnDoubleClick-Skript feuerte je nach Client gar nicht), zusätzlich geht
  **Rechtsklick**. Ausgeblendete Items landen zuverlässig in der
  „Ignoriert“-Ansicht.
- **Selbsterkennung live**: Abgegebene Quests, benutzte Cooldowns und
  veränderte Bestände hakt der Plan jetzt sofort ab, ohne das Fenster neu zu
  öffnen – gedrosselt und im Kampf ausgesetzt.
- Logo-Platzhalter: Bis das eigene Logo als TGA vorliegt, zeigt der
  Fensterkopf ein Münz-Icon statt einer leeren Fläche.

## 0.2.0 – 2026-08-08

Großer Umbau nach dem ersten Ingame-Test.

- **Neues Design**: flaches, dunkles 2026-Interface mit Goldakzent statt der
  Blizzard-Dialogbox – eigene Tabs, Pill-Etiketten, Zebra-Zeilen,
  Fortschrittsbalken, Icon-Zuschnitt; kaputte Pfeil-Zeichen (`→`) ersetzt.
- **Automatische Erledigt-Erkennung** im Tagesplan: benutzte Cooldowns,
  abgegebene Daily-Quests (Quest-Flag), halbierte Verkaufsbestände,
  kombinierte Motes, neue Craft-Produkte und Farm-Zuwächse haken sich selbst
  ab („automatisch erkannt“).
- **Daily-Quests** (Ogri'la/Skyguard, Phase 3) mit Goldbelohnung im
  Tagesplan – nur wenn die Vorquest-Kette abgeschlossen ist (Stufe 70).
- **Rezept-Radar**: Berufsfenster einmal öffnen, Rezepte werden dauerhaft
  gespeichert; neuer Crafts-Tab mit Gewinn je Rezept und Machbarkeit aus dem
  Accountbestand; Top-Crafts erscheinen im Tagesplan.
- **Mindestgewinn einstellbar** (Standard 5 g) und wirksam in Tagesplan,
  Flips und Crafts – keine 0,04-g-Vorschläge mehr. Dailies sind als sicheres
  Gold ausgenommen.
- **Solidere Preisbasis**: tägliche Preisaufzeichnung aller relevanten Items,
  Empfehlungen rechnen mit dem 7-Tage-Median statt der Momentaufnahme; der
  Verkaufen-Tab zeigt weiterhin den aktuellen Scanpreis.
- **Farm-Tipps realistisch**: geschätztes Gold pro Stunde statt
  irreführender Stapelwerte, gefiltert nach den Sammelberufen und
  Skillständen des Charakters.
- **Verkaufen-Tab**: Doppelklick blendet Items dauerhaft aus (mit
  „Ignoriert“-Ansicht zum Zurückholen), Gebundenes per Knopf ausblendbar.
- **Optionen-Tab**: Preisquelle (Auto/Auctionator/TSM), Mindestgewinn,
  Datenübersicht und Erklärung der Rechenmethoden.
- Logo-Unterstützung (Addon-Icon und Fensterkopf) samt PNG»TGA-Werkzeug.

## 0.1.0 – 2026-08-08

Erste Fassung.

- **Heute-Tab (Gold-Roadmap)**: tägliche Checkliste mit Tagesreset –
  Auctionator-Scan-Erinnerung, Berufs-Cooldowns (TBC- und Classic-Transmutes,
  Arkanitbarren, Mondstoff) mit Gewinnrechnung und Restzeit, Top-Verkäufe aus
  dem Bestand, beste Flips, Farm-Tipps nach aktuellem Marktwert.
- **Verkaufen-Tab**: Bestandsbewertung über Taschen oder (mit Syndicator)
  den ganzen Account inklusive Bank, Post und laufender Auktionen; bester
  Kanal je Item (AH netto / Händler / Entzaubern), Filter für Mats und
  Ausrüstung, Tooltip mit Kanalvergleich und Lagerorten.
- **Flips-Tab**: Motes → Ur-Partikel (10:1) mit Kombinieren- und
  Kauf-Flip-Rechnung, Essenzen 3:1 in beide Richtungen.
- **Preisquellen**: Auctionator zuerst, TSM `dbmarket` als Rückfall;
  umschaltbar, alle AH-Werte nach 5 % Gebühr.
- **Goldverlauf**: höchster Tagesstand je Kalendertag, accountweit über
  Syndicator, 7-Tage-Trend im Fenster.
- Slash-Befehle `/gold`, `/goldcopilot`, `/gold reset`, `/gold quelle`.
