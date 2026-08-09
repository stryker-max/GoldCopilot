# Gold Copilot 0.6.0

<p align="center"><img src="Media/Wordmark.png" alt="Gold Copilot" width="360"></p>

Dein Gold-Berater für **World of Warcraft: Burning Crusade Classic Anniversary** –
ein Standalone-Addon, das jeden Tag konkret sagt, was sich lohnt. Keine
Rohdaten-Tabellen: ein Tagesplan wie ein Daily-Quest-Log, der sich selbst
abhakt, wenn du die Dinge erledigst.

## Die sieben Tabs

1. **Heute** – die Gold-Roadmap. Neu mit jedem **WoW-Daily-Reset** (nicht um
   lokale Mitternacht), zum Abhaken, mit Fortschrittsbalken, Goldsumme je
   Kategorie und automatischer Erledigt-Erkennung:
   - **Tagesziel**: Sag dem Addon, wie viel Gold du heute willst – es zeigt
     dir den **schnellsten Weg dorthin**, also die offenen Aufgaben nach
     Gold je Minute sortiert und als „Plan 1, 2, 3 …“ nummeriert, samt
     Zeitschätzung.
   - **Daily-Quests**: Ogri'la & Himmelswache, Dungeon-Daily normal und
     heroisch, Kochkunst- und Angel-Daily – nur die, die dein Charakter nach
     Level, Beruf, Skillstand und Freischaltungskette wirklich annehmen kann
     (mit Questie sogar dessen eigene Prüfung). Abgegebene erkennt das Addon
     am Quest-Flag von selbst, und den **echten Goldbetrag lernt es beim
     ersten Abgeben** – bis dahin steht „ca.“ an der Zeile.
   - **Quests abgeben**: abgabebereite Quests aus deinem Log mit dem Wert
     ihrer Belohnung – Gold plus Items, jedes zum **besseren von AH netto und
     Händlerpreis**; bei Auswahlbelohnungen zählt nur die beste.
   - **Cooldowns & Crafts**: Transmutationen, Mondstoff & Co. mit
     Gewinnrechnung und Restzeit – benutzt du den Cooldown, hakt sich der
     Punkt selbst ab. Dazu die besten Crafts aus deinen **gescannten
     Rezepten**, die dein Bestand sofort hergibt.
   - **Verkaufen**: die wertvollsten AH-Posten deines Accounts. Halbiert
     sich der Bestand, gilt der Punkt als erledigt.
   - **Flips** und ein **Farm-Tipp des Tages** in geschätztem Gold pro
     Stunde – nur für Sammelberufe, die dein Charakter tatsächlich hat.
2. **Verkaufen** – bewertet Taschen und (mit Syndicator) den ganzen Account:
   Bank, Post, Twinks, laufende Auktionen. Pro Item der beste Kanal – **AH**
   (netto nach 5 % Gebühr), **Händler** oder **Entzaubern**. Rechtsklick oder
   Doppelklick blendet ein Item dauerhaft aus („Ignoriert“-Ansicht holt es
   zurück), gebundene Items lassen sich per Knopf ausblenden. Tränke,
   Elixiere und Essen gelten als **Eigenbedarf** und werden nie zum Verkauf
   vorgeschlagen – ihr Wert zählt trotzdem mit.
3. **Flips** – Motes » Ur-Partikel (10:1) und Essenzen 3:1 in beide
   Richtungen, inklusive Bestand und Kauf-Flip-Rechnung.
4. **Crafts** – der Rezept-Radar: Öffne einmal jedes Berufsfenster, Gold
   Copilot merkt sich alle Rezepte dauerhaft und sortiert sie nach Gewinn
   (Erlös netto minus Zutaten zum Marktpreis), mit „×N machbar“ aus deinem
   Accountbestand.
5. **Markt** – das neue **Market Brain**: Gold Copilot schreibt eine eigene
   Markthistorie deines Realms mit und ordnet jeden Preis in seine eigene
   Vergangenheit ein. Pro Item aktueller Preis, 7- und 30-Tage-Median,
   **Preis-Perzentil** und ein **Market Score von 0 bis 100**, sortiert nach
   dem höchsten Score. Der Tooltip zeigt die ganze Rechnung: 24h-/7d-/30d-
   Median, 7-Tage-Spanne, Volatilität, Anzahl Messpunkte, Historientage,
   Score, Confidence und einen Satz im Klartext („Der aktuelle Preis liegt
   24 % unter dem 30-Tage-Median und im 8. Perzentil deiner gespeicherten
   Realm-Daten“). Siehe [Das Market Brain](#das-market-brain).
6. **Chancen** – die neue **Opportunity Engine**: eine nach Score sortierte
   Liste konkreter Gold-Chancen aus Conversion, Crafting, Entzaubern und
   historischer Unterbewertung, jeweils mit Kapitalbedarf, theoretischer Marge
   und ROI. Der Tooltip zeigt die komplette Rechnung. Siehe
   [Die Opportunity Engine](#die-opportunity-engine).
7. **Optionen** – Preisquelle (Auto / Auctionator / TSM), **Mindestgewinn**
   für alle Vorschläge (Schluss mit 0,04-g-Tipps), **Mindestprofit und
   Mindest-ROI der Chancenliste** (getrennt davon), **Tagesziel**,
   Eigenbedarfsschutz, Datenübersicht und eine Erklärung aller
   Rechenmethoden.

## Das Market Brain

Bis 0.4.0 kannte Gold Copilot je Item und Kalendertag genau einen Preis. Ein
Tag ist aber kein Markt, sondern eine Momentaufnahme mit Datumsstempel. Seit
0.5.0 liegt daneben eine echte Zeitreihe.

- **Mehrere Messpunkte pro Tag.** Aufgezeichnet wird, sobald Auctionator seine
  Datenbank aktualisiert – also nach jedem Scan –, außerdem beim Login, beim
  Öffnen des Fensters und beim Verlassen des Auktionshauses.
- **Und trotzdem klein.** Höchstens ein Messpunkt je Item und 30 Minuten; ein
  unveränderter Preis wird höchstens alle zwei Stunden wiederholt; aufbewahrt
  werden 30 Tage, danach räumt das Addon selbst auf. Gespeichert wird nicht
  eine Tabelle je Messpunkt, sondern ein Zahlenpaar – das ist rund ein Zehntel
  der Dateigröße. Wie viel es tatsächlich ist, sagt `/gold marketstats`.
- **Nicht alles wird beobachtet.** Nur was Gold Copilot ohnehin braucht:
  Farmziele, Flip- und Rezeptzutaten, dein Accountbestand (nur was das AH
  annimmt) und alles, wofür schon eine Reihe existiert.
- **Market Score 0–100.** Er beantwortet genau eine Frage: *Wie günstig ist der
  aktuelle Preis, gemessen an deiner eigenen Historie?* Er ist **keine
  Kaufempfehlung** – 0.5 kennt weder Nachfrage noch Liquidität noch
  Verkaufsdauer. Ein Item kann historisch spottbillig sein, weil es niemand
  mehr braucht. Die Bänder: 90–100 außergewöhnlich günstig, 75–89 interessant,
  50–74 normal, 25–49 teuer, 0–24 sehr teuer.
- **Score und Sicherheit sind getrennt.** Die Confidence steht als eigenes
  Etikett in der Zeile: **niedrig** unter 3 Tagen, **mittel** ab 3 Tagen und
  5 Messpunkten, **hoch** ab 7 Tagen und 10 Messpunkten. Sie deckelt den Score
  zusätzlich – bei niedriger Sicherheit sind höchstens 68 Punkte möglich, bei
  mittlerer 85. Zwei Messpunkte ergeben deshalb nie „Score 95“, sondern gar
  keinen Score: unter drei Punkten gibt es keine Verteilung, in die sich etwas
  einordnen ließe.
- **Kaltstart wird gesagt, nicht kaschiert.** Ein frisch installiertes Addon
  hat keine Historie, und der Markt-Tab schreibt genau das hin, statt Zahlen zu
  erfinden.
- **Deine 0.4-Daten gehen nicht verloren.** Beim ersten Start übernimmt Gold
  Copilot die vorhandene Tages-Preishistorie als je einen Messpunkt pro Tag.
  Die Preise sind echte, auf deinem Realm beobachtete Werte; nur die Uhrzeit
  ist mangels besserer Information auf 12 Uhr mittags gesetzt. Die alte
  `priceHistory` bleibt daneben unverändert bestehen und versorgt weiterhin die
  Planungspreise von Tagesplan, Flips und Craft-Radar.

## Die Opportunity Engine

Der Market Score aus 0.5.0 beantwortet genau eine Frage: *Ist der aktuelle
Preis, gemessen an der eigenen Historie, günstig?* Das ist nützlich und
trotzdem nicht die Frage, die man morgens im Auktionshaus hat. Die lautet:
**Ist das eine interessante Gold-Chance?**

Seit 0.6.0 beantwortet der Chancen-Tab genau die – aus denselben Daten, ohne
eine einzige neue Annahme über die Zukunft.

### Vier Arten von Chancen

| Art | Rechnung | Datenquelle |
| --- | --- | --- |
| **Conversion** | Motes » Ur-Partikel (10:1), Essenzen 3:1 in beide Richtungen | Einkauf zum Planungspreis, Erlös netto |
| **Craft** | Materialkosten gegen Produkterlös netto, samt „×N machbar“ | deine **gescannten Rezepte** |
| **Entzaubern** | Kaufpreis gegen Entzauber-Erwartungswert netto | **Auctionators** Entzauberwert – Gold Copilot schätzt keine eigenen Dropchancen |
| **Resale** | aktueller Preis gegen konservativen Zielpreis | deine eigene Markthistorie, Market Score ≥ 70 |

Jede Zeile nennt **Kapitalbedarf, theoretische Marge und ROI** – denn das sind
drei verschiedene Dinge. Eine 500-g-Chance mit 5 % ROI ist nicht automatisch
besser als eine 50-g-Chance mit 80 % ROI, und der Score behandelt sie auch
nicht so.

### Opportunity Score 0–100

Bewusst keine gewichtete Fantasieformel, sondern ein Punktebudget aus vier
Gutschriften und zwei Abschlägen. Jeder Summand beantwortet genau eine Frage,
hat eine eigene Obergrenze und steht als Zahl in `Constants.lua` – damit lässt
er sich an echten Realm-Daten nachjustieren, ohne die Logik anzufassen:

```
Opportunity Score =
      Margin Quality        (0–35)   Kapitaleffizienz aus der ROI
    + Profit Scale          (0–15)   absolute Größe des Gewinns
    + Market Attractiveness (0–25)   Market Score der Kaufseite
    + Data Quality          (0–25)   Confidence als eigener Summand
    - Volatility Risk       (0–15)   Schwankung der beteiligten Reihe
    - Capital Penalty       (0–15)   gebundenes Gold
```

- **Margin Quality** = `35 × ROI / (ROI + 0,25)`. Bei 25 % ROI gibt es die
  halbe Punktzahl, danach flacht die Kurve ab: 500 % sind besser als 50 %,
  aber nicht zehnmal so gut.
- **Profit Scale** = `15 × Gewinn / (Gewinn + 10 g)`. Getrennt von der ROI,
  weil beides verschiedene Fragen sind.
- **Market Attractiveness** übernimmt den Market Score unverändert. Fehlt er,
  zählen 50 Punkte – *keine Aussage*, nicht *schlecht*. Eine fehlende Zahl
  darf keine Behauptung werden.
- **Volatility Risk** misst am Quartilsabstand (siehe unten), gedeckelt bei
  0,6. **Capital Penalty** halbiert sich bei 250 g Einsatz.
- **Confidence deckelt zusätzlich hart**: niedrig höchstens 55, mittel
  höchstens 80. Ohne jede Datenbasis gibt es **gar keinen Score** – nicht die
  Note 0. „Weiß ich nicht“ ist keine schlechte Bewertung, sondern keine.
- **Score und Confidence bleiben getrennt** ausgewiesen: Der Score ist die
  Aussage, die Confidence ihr Gewicht.

Die Bänder: 80–100 sehr interessant, 60–79 interessant, 40–59 beobachten,
darunter geringe Priorität. Dort steht bewusst nie „kaufen“.

### Der konservative Zielpreis

Resale rechnet **nicht** mit dem vollen 30-Tage-Median, sondern mit
`min(7-Tage-Median, 30-Tage-Median)`, davon 5 % AH-Gebühr. Ist der
7-Tage-Median niedriger, ist der Markt gerade gefallen – auf den
30-Tage-Median zu setzen hieße, auf eine Rückkehr zu wetten, für die es keinen
Beleg gibt. Ist er höher, wäre er der bequemere Wert; genau deshalb wird er
nicht genommen. Das Minimum ist in beiden Richtungen die unbequeme Wahl.

### Was 0.6 ausdrücklich **nicht** kann

- **Liquidität und Verkaufsdauer.** Wie schnell sich etwas tatsächlich
  verkauft, weiß das Addon nicht – dafür fehlt die Datenbasis. Die Felder
  `liquidity`, `sellThrough`, `expectedHours` und `profitVelocity` sind im
  Datenmodell vorbereitet und stehen bewusst leer statt auf einem erfundenen
  Standardwert.
- **Zukünftige Nachfrage.** Kein Wort über kommende Phasen – das wird Future
  Market 0.7.
- Deshalb heißt hier nichts „Gewinn“, sondern **„theoretischer Gewinn“**, und
  jeder Tooltip schreibt beide Einschränkungen hin.

### Beobachtungsliste

**Rechtsklick** auf eine Zeile im Markt- oder Chancen-Tab nimmt das Item in
die Beobachtungsliste auf (und wieder heraus). Beobachtete Items werden ab
dann mit **höchster Priorität** mitgeschrieben – auch wenn sie weder im
Bestand liegen noch in einem Rezept vorkommen. `/gold watchlist` zeigt sie an.
Das ist die technische Grundlage für Future Market 0.7.

### Filter

Nicht jeder 3-Silber-Gewinn gehört auf den Bildschirm. Der Chancen-Tab hat
**eigene** Schwellen (Mindestprofit 1/5/10/25/50 g, Mindest-ROI 0/5/10/20/30 %),
getrennt vom Mindestgewinn des Tagesplans – wer den einen ändert, meint nicht
den anderen. Was ausgefiltert wurde, steht als Zahl in der Kopfzeile, statt
lautlos zu verschwinden.

## Voraussetzungen

Gold Copilot bringt bewusst keinen eigenen AH-Scanner mit, sondern nutzt die
Preise, die du ohnehin schon hast:

- **[Auctionator](https://www.curseforge.com/wow/addons/auctionator)**
  (empfohlen): Führe im Auktionshaus regelmäßig einen vollständigen Scan aus.
  Gold Copilot hängt sich, wenn vorhanden, an Auctionators offizielle
  Rückmeldung `Auctionator.API.v1.RegisterForDBUpdate` und zeichnet direkt nach
  jedem Scan auf; fehlt sie, bleibt `AUCTION_HOUSE_CLOSED` der Auslöser.
- **[TradeSkillMaster](https://www.tradeskillmaster.com/)** (optional):
  Ohne Auctionator-Preis greift Gold Copilot auf `dbmarket` zurück.
- **[Syndicator](https://www.curseforge.com/wow/addons/syndicator)**
  (empfohlen): Damit sieht Gold Copilot Bank, Post und Twinks.
- **[Questie](https://www.curseforge.com/wow/addons/questie)** (optional):
  Übernimmt die Prüfung, welche Tagesquests dein Charakter wirklich
  freigeschaltet hat.

Mindestens eine Preisquelle (Auctionator oder TSM) muss installiert sein.

## Installation

1. [Code herunterladen](https://github.com/stryker-max/GoldCopilot/archive/refs/heads/main.zip)
   und entpacken.
2. Den entpackten Ordner in `World of Warcraft\_anniversary_\Interface\AddOns\`
   legen und in **`GoldCopilot`** umbenennen (GitHub hängt sonst `-main` an –
   der Ordnername muss exakt `GoldCopilot` lauten).
3. WoW neu starten und am Charakterbildschirm unter „AddOns“ aktivieren.

## Benutzung

- `/gold` öffnet und schließt das Fenster (`/goldcopilot` geht auch).
- `/gold reset` setzt die Checkliste der laufenden Daily-Periode zurück.
- `/gold quelle` zeigt die aktive Preisquelle.
- `/gold marketstats` zeigt Umfang, Alter und geschätzte Dateigröße der
  Markthistorie und ob der Auctionator-Callback aktiv ist.
- `/gold marketreset confirm` löscht **ausschließlich** die Markthistorie.
  Ohne `confirm` passiert nichts – Optionen, Goldverlauf, Rezepte, Questgold
  und die alte Preishistorie bleiben in jedem Fall unangetastet.
- `/gold chancen` öffnet direkt den Chancen-Tab.
- `/gold watchlist` listet die beobachteten Items.
- Einmal je Charakter: **alle Berufsfenster öffnen**, damit der Craft-Radar
  deine Rezepte kennt.
- Shift-Klick auf eine Zeile verlinkt das Item im Chat; der Tooltip zeigt
  alle Kanäle, Lagerorte und die Rechnung.
- **Jede Empfehlung erklärt sich im Tooltip**: Produktwert, Zutaten,
  erwarteter Gewinn beziehungsweise Marktpreis, angenommene Rate und
  Erwartung je Stunde – dazu die **Preisbasis** (siehe unten).

## So wird gerechnet

- **AH-Erlöse sind immer netto**: 5 % Auktionshausgebühr abgezogen. Die
  Einzahlung (Deposit) wird bei erfolgreichem Verkauf erstattet und darum
  nicht abgezogen.
- **Planungspreise**: Empfehlungen (Roadmap, Flips, Crafts) rechnen mit dem
  **Median der letzten 7 Tage** deiner beobachteten Preise – eine einzelne
  Dumping-Auktion wirft den Plan nicht um. Der Verkaufen-Tab zeigt bewusst
  den aktuellen Scanpreis („was bekomme ich jetzt“). Beobachtet werden alle
  Items, mit denen Gold Copilot rechnet, 14 Tage lang – aufgezeichnet beim
  Login, beim Öffnen des Fensters, beim Aktualisieren und **nach dem
  Verlassen des Auktionshauses**, wenn deine Scanpreise am frischesten sind.
- **Markthistorie**: Der Markt-Tab rechnet auf einer eigenen, feineren
  Zeitreihe (siehe [Das Market Brain](#das-market-brain)) – Median und
  Perzentil über alle gespeicherten Messpunkte, nicht über Tagesmittel. Die
  Volatilität ist bewusst der **Quartilsabstand geteilt durch den Median** und
  nicht die Standardabweichung: Eine einzelne Dumping-Auktion soll ein Item
  nicht als „schwankend“ abstempeln.
- **Datenqualität sichtbar**: Jeder Empfehlungs-Tooltip nennt, worauf der
  Preis beruht – `Preisbasis: 7-Tage-Median · 6 Tageswerte · gute
  Datenbasis`. Die Stufen: 0 Tageswerte = Momentanpreis, 1–2 = wenig Daten,
  3–5 = mittlere Datenbasis, 6–7 = gute Datenbasis. Bei mehreren beteiligten
  Items (Craft, Flip) zählt die schwächste Reihe.
- **Tagesplan-Reset**: Die Checkliste wird am **Daily-Reset deines Servers**
  neu (über `GetQuestResetTime`), nicht um lokale Mitternacht – sonst wäre
  die Liste mitten in der Abendsitzung leer, während die Dailies selbst noch
  gesperrt sind. `/gold reset` setzt sie jederzeit von Hand zurück.
  Goldverlauf und Preishistorie folgen weiterhin dem Kalendertag.
- **Questbelohnungen**: Jedes Belohnungsitem zählt mit dem besseren Wert aus
  AH netto und Händlerpreis. Fehlt der Marktpreis, bleibt der Händlerwert –
  ein Item, das der Händler für 8 g nimmt, ist nicht wertlos. Was gar nicht
  ins AH darf (gebunden, grau), wird auch nicht so bewertet.
- **Craft-Gewinn** = Produkterlös netto (bei Zufallsausbeute der Mittelwert)
  minus Zutaten zum Marktpreis – auch wenn du die Zutaten schon besitzt,
  denn sie hätten sonst verkauft werden können.
- **Chancen**: Die Opportunity Engine erfindet keine eigene Rechnung, sondern
  orchestriert die vorhandenen – Craft-Gewinn, Flip-Rechnung, Planungspreise
  und Market Score kommen unverändert dorther, wo sie ohnehin entstehen. Die
  AH-Gebühr fällt deshalb **genau einmal** an, immer auf der Verkaufsseite;
  Materialkosten zählen genau einmal; Kaufen kostet keine Gebühr. **ROI** =
  theoretischer Gewinn geteilt durch Kapitaleinsatz. Fehlt auch nur ein
  benötigter Preis, entsteht keine Chance – sie wird als „ohne Preis“ gezählt,
  nicht geschätzt.
- **Farm-Tipps**: Marktpreis × konservativ geschätzte Sammelrate pro Stunde,
  gefiltert nach deinen tatsächlichen Sammelberufen und Skillständen.
- **Daily-Quests**: Der angezeigte Betrag ist zunächst eine Schätzung
  („ca.“). Beim ersten Abgeben liest Gold Copilot mit, was der Server
  tatsächlich überweist, und rechnet ab dann mit dem echten Wert.
- **Tagesziel**: Die Reihenfolge ergibt sich aus Gold je Minute, mit
  konservativen Zeitschätzungen je Aufgabenart (Daily ≈ 8 Min., Auktion
  einstellen ≈ 3 Min., Craft ≈ 2 Min., Farmen = 60 Min.).
- Graue und gebundene Items werden nie fürs AH vorgeschlagen.

## FAQ

**Warum zeigt fast alles „ohne Marktpreis“?** – Es fehlt ein
Auctionator-Scan auf diesem Realm. Auktionshaus öffnen, vollständigen Scan
starten, `/gold` neu öffnen – die Roadmap erinnert dich von selbst daran.

**Woher weiß das Addon, dass ich etwas erledigt habe?** – Beim ersten Blick
auf den Tagesplan merkt es sich deine Bestände als Ausgangsbasis. Benutzte
Cooldowns, abgegebene Dailies (Quest-Flag), halbierte Verkaufsbestände,
kombinierte Motes, neue Craft-Produkte und Farm-Zuwächse erkennt es daran
automatisch – der Rest bleibt per Häkchen abhakbar.

**Warum will es meine Manatränke nicht verkaufen?** – Weil du sie brauchst.
Verbrauchbares gilt als Eigenbedarf und wird nie vorgeschlagen; in den
Optionen lässt sich das abschalten.

**Wird meine SavedVariables-Datei jetzt riesig?** – Nein. Die Markthistorie
ist hart begrenzt: höchstens ein Messpunkt je Item und 30 Minuten, höchstens
400 Punkte je Item, höchstens 500 beobachtete Items, und nach 30 Tagen fliegt
Altes raus. `/gold marketstats` zeigt jederzeit die geschätzte Größe.

**Warum steht bei manchen Items kein Score?** – Weil noch zu wenig Daten da
sind. Unter drei Messpunkten gibt es keine Verteilung, in die sich der aktuelle
Preis einordnen ließe – dann steht dort „–“ statt einer Zahl, die niemand
belegen kann.

**Sagt mir der Chancen-Tab, was ich kaufen soll?** – Nein, und das ist Absicht.
Er sagt, welche Rechnungen aus deinen eigenen Preisen gerade am
interessantesten aussehen, und legt jede Rechnung offen. Ob sich das Ergebnis
auch verkauft, weiß 0.6 nicht: Liquidität und Verkaufsdauer fehlen der Engine
noch vollständig, und sie behauptet das Gegenteil an keiner Stelle.

**Der Chancen-Tab ist leer, obwohl der Markt-Tab voll ist.** – Wahrscheinlich
greifen die Filter: voreingestellt sind 1 g Mindestprofit und 5 % Mindest-ROI.
Wie viele Chancen daran hängen bleiben, steht in der Kopfzeile; die Schwellen
stehen in den Optionen. Sonst fehlt der Engine schlicht Futter: Craft-Chancen
brauchen gescannte Rezepte, Entzauber-Chancen brauchen Auctionator, und Resale
braucht mehrere Tage eigener Markthistorie.

**Sieht Gold Copilot meine Gildenbank?** – Nein, bewusst nicht.

**Verändert das Addon etwas an meinen Auktionen?** – Nein. Es liest Preise
und Bestände, stellt aber nichts ein und kauft nichts.

## Lizenz

MIT – siehe [LICENSE](LICENSE).
