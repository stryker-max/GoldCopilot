# Gold Copilot 0.8.0

<p align="center"><img src="Media/Wordmark.png" alt="Gold Copilot" width="360"></p>

Dein Gold-Berater für **World of Warcraft: Burning Crusade Classic Anniversary** –
ein Standalone-Addon, das jeden Tag konkret sagt, was sich lohnt. Keine
Rohdaten-Tabellen: ein Tagesplan wie ein Daily-Quest-Log, der sich selbst
abhakt, wenn du die Dinge erledigst.

## Die neun Tabs

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
7. **Zukunft** – der neue **Future Market**: Welche bereits bekannten
   Veränderungen im Spiel könnten die Nachfrage nach einem Item verändern?
   Oben der nächste bekannte Catalyst mit Inhalt, Termin, Zeitfenster und
   Wissensstand, darunter die Items mit einer belegten Zukunftsaussage –
   je Zeile Market Score, **Future Demand**, **Hype Score**, Catalyst und
   **Future Opportunity Score**. Der Tooltip nennt jeden einzelnen Grund und
   trennt dabei ausdrücklich Fakt von Modell. Siehe
   [Der Future Market](#der-future-market).
8. **Handel** – das neue **Liquidity Brain**: deine eigene Handelsbilanz.
   Oben die letzten 7 und 30 Tage mit Umsatz, realisiertem Gewinn,
   Sell-through und medianer Verkaufszeit, darunter je Item **verkauft**,
   **abgelaufen**, **Sell-through**, **Zeit bis Verkauf**, **realisierte
   Marge** und **Liquidity Score**. Alles gemessen, nichts geschätzt – und
   alles bleibt lokal. Siehe [Das Liquidity Brain](#das-liquidity-brain).
9. **Optionen** – Preisquelle (Auto / Auctionator / TSM), **Mindestgewinn**
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
- **Zukünftige Nachfrage.** Kein Wort über kommende Phasen – das macht seit
  0.7.0 der [Future Market](#der-future-market) in einem eigenen Tab, und der
  Opportunity Score bleibt davon bewusst unberührt.
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

## Der Future Market

0.5 beantwortet „wie steht der Preis relativ zu seiner eigenen Vergangenheit?“,
0.6 „ist daraus gerade eine Gold-Chance ableitbar?“ – und 0.7 beantwortet:

> **Welche bereits bekannten Veränderungen im Spiel könnten die Nachfrage nach
> diesem Item verändern?**

TBC hat dabei einen Vorteil, den kaum ein anderes Spiel bietet: Ein großer Teil
dessen, was kommt, ist bekannt. Gold Copilot verbindet dieses Spielwissen mit
deiner eigenen Realm-Historie aus 0.5 und der Bewertung aus 0.6.

**Gold Copilot sagt keine Preise voraus.** Nirgends steht „Urschatten wird auf
35 g steigen“. Es steht dort: *dieses Material hat einen bekannten Catalyst, es
ist gemessen an deiner eigenen Historie gerade günstig, und der Catalyst scheint
auf deinem Realm noch nicht eingepreist.*

### Die Wissensbasis

Spielwissen und Rechenlogik sind strikt getrennt. Alles Wissen liegt in
`Knowledge/` – Phasen, Items, Rezeptkanten, Catalysts –, die gesamte Bewertung
in `Future.lua`, alle Stellschrauben in `Constants.lua`. Wer die Wissensbasis
aktualisiert, muss keine Logik anfassen.

Ein Addon kann keine Webseiten abrufen, und das ist hier kein Mangel, sondern
die Bauform: Die Wissensbasis wird mit dem Addon ausgeliefert. Ihr Stand steht
sichtbar im Zukunft-Tab („Wissensstand: 09.08.2026“) und in den Optionen.

**Keine Behauptung ohne Herkunft.** Jeder Eintrag trägt seine Provenance, und
ohne sie kommt er gar nicht erst in die Wissensbasis – die Prüfung verwirft ihn
und zählt ihn (`/gold wissen` zeigt Verworfenes an):

| Provenance | Bedeutung |
| --- | --- |
| `official` | von Blizzard angekündigt oder im Spiel nachweisbar |
| `historical` | aus den TBC-Spieldaten bzw. dem bekannten TBC-Verlauf |
| `inferred` | daraus abgeleitet – plausibel, aber nicht belegt |

Für **Releasetermine** gilt eine harte Regel: Ein exaktes Datum steht nur da,
wenn Blizzard es **für die Anniversary-Realms** angekündigt hat. Termine aus dem
ursprünglichen TBC oder aus TBC Classic werden **nie** als Anniversary-Termin
übernommen. Bekannte spätere Inhalte (Zul'Aman, Sonnenbrunnen) sind modelliert,
tragen aber `release = nil`, und der Tab schreibt „Termin offen“ statt einer
erfundenen Zahl.

### Catalysts

Ein Catalyst ist ein bekanntes zukünftiges Ereignis, das Angebot oder Nachfrage
verändern könnte – neuer Raid, neues Rezept, Widerstandsbedarf, neue
Sockelsteine, neue PvP-Saison, zusätzliches Angebot. Seine `strength` ist
**keine Preisprognose**: 0,8 heißt „starker plausibler Nachfragegrund“, nicht
„+80 %“.

Catalysts hängen meist am **Produkt**, nicht am Material – die belegbare Aussage
ist „in Phase 3 gibt es dieses Rezept“. Dass dadurch die Zutaten gefragt sind,
rechnet der Dependency Graph aus.

### Dependency Graph

Gold Copilot kennt nicht nur die direkt genannten Items, sondern die
Lieferkette dahinter:

```
Neues Rezept (Catalyst)
  └─ braucht Material A          → 70 % des Catalysts
       └─ das braucht Material B → 40 % des Catalysts
            └─ Ebene 3           → nicht mehr
```

Die Grenze ist der eigentliche Punkt. Ohne sie wäre nach fünf Ebenen jedes
Material der Scherbenwelt „extrem bullish“, weil am Ende jeder Kette Netherstoff
und Adamantiterz stehen – eine Aussage, die auf alles zutrifft, ist keine.
Kreise in der Kette (die Ur-Partikel lassen sich im Kreis transmutieren) werden
erkannt und laufen nicht endlos.

Der Graph speist sich aus drei Quellen: der kuratierten Wissensbasis, den
Umwandlungen aus `Constants.lua` und – am wertvollsten – **deinen tatsächlich
gescannten Rezepten**, die direkt aus dem Spielclient kommen.

### Future Demand Score 0–100

- **50** – keine bekannten Faktoren, oder Nachfrage und Angebot heben sich auf
- **> 50** – bekannte Faktoren sprechen eher für zusätzliche Nachfrage
- **< 50** – bekannte Faktoren sprechen eher für Angebotsdruck oder
  nachlassende relative Nachfrage

Jeder Catalyst bekommt ein Gewicht aus fünf Faktoren: `strength` ×
Confidence × Provenance (offiziell schlägt abgeleitet) × Zeitfenster × Ebene im
Dependency Graph. Nachfrage- und Angebotsseite werden getrennt mit **abnehmendem
Ertrag** summiert – der stärkste Grund zählt voll, der zweite zu 60 %, der
dritte zu 36 % –, laufen durch dieselbe Sättigungskurve und werden
gegeneinander verrechnet:

```
Future Demand = 50 + 50 × (saturate(Nachfrage) − saturate(Angebot))
```

Damit kann ein Angebots-Catalyst einen Nachfrage-Catalyst neutralisieren – genau
das passiert beim Leitmaterial einer neuen Phase, das am Starttag gleichzeitig
gebraucht wird und massenhaft hereinkommt.

**Der Future Demand Score ist weder der Opportunity Score noch eine
Preisprognose.**

### Zeitfenster

Ist ein Termin bekannt, rechnet Gold Copilot die Tage bis dahin aus und ordnet
sie einer Zone zu: **EARLY** (> 30 Tage), **ACCUMULATION** (14–30),
**PRE_RELEASE** (3–13), **RELEASE** (0–2), danach **POST_RELEASE**. Bewusst
**nicht** „je näher, desto besser“: Kurz vor Release ist eine bekannte
Ankündigung meist längst eingepreist. ACCUMULATION heißt trotzdem nicht
automatisch „kaufen“.

### Hype Score 0–100

Die wichtigste Bremse des Moduls: Ist der bekannte Grund auf **deinem** Realm
schon eingepreist? Ausschließlich aus deinen eigenen Marktdaten – es gibt in
einem Addon keine Stimmungslage aus dem Internet, und eine erfundene wäre
schlimmer als keine.

Vier Signale: Aufschlag zum 30-Tage-Median (35 %), Perzentil in der eigenen
Reihe (25 %), Momentum 7d gegen 30d (25 %), Volatilität (15 %). Alle zählen nur
nach oben – ein Preis unter seinem Median ist kein negativer Hype, sondern
schlicht keiner.

**Ohne belastbare Historie gibt es keinen Hype Score, sondern gar keinen.** Aus
drei Messpunkten „kein Hype“ zu folgern wäre die gefährlichste Falschaussage,
die dieses Modul machen könnte.

### Future Opportunity Score 0–100

Ausdrücklich **nicht** Market Score mal Future Demand – ein Produkt zweier
Kennzahlen bestraft eine neutrale Zahl wie eine schlechte und kann nicht sagen,
welcher Faktor das Ergebnis getragen hat. Stattdessen ein Aufbau um die Mitte:

```
50
+ 0,50 × (Future Demand − 50)      bis ±25
+ 0,35 × (Market Score  − 50)      bis ±17,5   (fehlt: zählt 50)
− 0,60 × max(0, Hype − 50)         bis −30
+ Zeitfensterbonus                 −4 bis +6
− Volatilitätsabschlag             bis −8
danach gedeckelt durch Wissens-Confidence UND Realm-Datenlage
```

Beide Deckel: Ein Signal kann nie besser sein als das Wissen dahinter (niedrig
höchstens 60, mittel 80) und nie besser als die Daten, gegen die es geprüft
wurde – **ohne Realm-Historie ist bei 55 Schluss**, egal wie stark der Catalyst
ist.

| Score | Einordnung |
| --- | --- |
| 90–100 | außergewöhnlich interessant |
| 75–89 | interessant |
| 60–74 | beobachten |
| 40–59 | neutral |
| 25–39 | bereits teuer / schwaches Setup |
| 0–24 | hohes Hype-Risiko / unattraktiv |

Beispiel: `Market 88 · Demand 91 · Hype 22` heißt „historisch günstig **und**
mehrere bekannte zukünftige Nachfragegründe, noch nicht eingepreist“.
`Market 24 · Demand 92 · Hype 88` heißt „sehr relevanter Catalyst – aber der
Realm-Preis ist bereits gestiegen“, und das ist womöglich keine gute neue
Position mehr.

### Einstiegszone und „nicht hinterherlaufen“

Keine willkürliche Formel wie „Median minus 20 %“. Anker ist das **untere
Quartil deiner eigenen 30-Tage-Verteilung** – ein Preis, den es auf deinem Realm
nachweislich gab –, gebremst durch den 7-Tage-Median, damit die Zone nicht auf
eine Rückkehr wettet, für die es keinen Beleg gibt. Davon geht ein Abschlag ab,
der mit dem Hype Score wächst: Je mehr Erwartung schon im Preis steckt, desto
tiefer muss ein Einstieg liegen, um sie nicht mitzukaufen.

Reicht die Datenbasis nicht, steht dort **„noch keine belastbare
Einstiegszone“** statt einer Hausnummer. Liegt der Preis deutlich über der
eigenen Spanne, warnt die Zeile: **„Nicht hinterherlaufen – der Catalyst wird
womöglich bereits eingepreist.“**

### Fakt und Modell

Im Tab und im Tooltip wird sauber getrennt:

- **Fakt**: „Der Schwarze Tempel öffnet am 27.08.2026“, „Item X wird für
  Rezept Y gebraucht“.
- **Modell**: „Das könnte die Nachfrage erhöhen“, „Future Demand 84“,
  „Signal 88“.

Modelloutput wird nie als Blizzard-Fakt dargestellt. Jede Zeile der
Erklärung trägt intern ihre Art (`fact` oder `model`) und ihre Quelle.

### Beobachtung mit These

Ein Rechtsklick im Zukunft-Tab nimmt das Item mit **Phase, These und
Wunsch-Einstieg** in die Beobachtungsliste auf. Bestehende Einträge aus 0.6
bleiben unverändert gültig – die Liste wird erweitert, nicht ersetzt.

### Was 0.7 ausdrücklich **nicht** kann

- **Preise vorhersagen.** Der Future Demand Score beschreibt bekannte
  Spielzusammenhänge, keine Kursziele.
- **Wissen, was Blizzard nicht angekündigt hat.** Fehlt ein Termin, steht das
  da – statt eines Datums aus dem alten TBC.
- **Liquidität und Verkaufsdauer.** Seit 0.8.0 nachgeliefert – siehe
  [Das Liquidity Brain](#das-liquidity-brain). Der Future Demand Score selbst
  bleibt davon unberührt: Was eine kommende Phase braucht, ändert sich nicht
  dadurch, wie schnell **du** ein Item losgeworden bist. Nur das Investment
  Signal färbt sich leicht ein, und auch das erst ab mittlerer Datenlage.

## Das Liquidity Brain

0.5 beantwortet „wie steht der Preis relativ zu seiner eigenen Vergangenheit?“,
0.6 „ist daraus eine Chance ableitbar?“, 0.7 „was kommt an bekannten
Veränderungen?“. Allen dreien fehlt dieselbe Antwort:

> **Verkaufe ich dieses Item überhaupt – und wie schnell bekomme ich mein Gold
> zurück?**

Ein theoretischer Gewinn von +500 g ist wertlos, wenn das Item zehn Tage steht.
Ein +30-g-Handel, der sich dreimal am Tag dreht, ist besser. Seit 0.8.0 lernt
Gold Copilot deshalb zum ersten Mal **deine eigenen Handelsdaten** – und
ausschließlich die.

### Was erfasst wird

`Ledger.lua` führt eine kleine persönliche Handelsbilanz. Kein zweiter
TSM-Ledger: Aufgeschrieben wird nur, was eine Empfehlung verbessert.

| Vorgang | Quelle im Spiel | Was gespeichert wird |
| --- | --- | --- |
| **Eingestellt** | `PostAuction` (mitgelesen per `hooksecurefunc`) | Item, Stückzahl, Stückpreis, Laufzeit, Einstellgebühr aus `CalculateAuctionDeposit` |
| **Verkauft** | AH-Rechnung im Briefkasten (`GetInboxInvoiceInfo`, `invoiceType = "seller"`) | Zeitpunkt, Betrag, tatsächliche AH-Gebühr, zugeordnete Stückzahl |
| **Abgelaufen** | Post mit dem Betreff aus `AUCTION_EXPIRED_MAIL_SUBJECT` | Item und Stückzahl aus dem Anhang, verlorene Einstellgebühr |
| **Zurückgezogen** | Post mit dem Betreff aus `AUCTION_REMOVED_MAIL_SUBJECT` | Item und Stückzahl aus dem Anhang |
| **Gekauft** | AH-Rechnung (`invoiceType = "buyer"`) | Item und Stückzahl aus dem Anhang, gezahlter Betrag |

**Nur bestätigte Auktionshaus-Vorgänge.** Ein Verkauf an den Händler, ein
Handel mit einem Mitspieler, eine Postsendung, ein Craft, ein Entzaubern oder
ein zerstörter Stapel wird **nie** zu einem AH-Verkauf umgedeutet. Aus einer
Goldänderung wird grundsätzlich nichts abgeleitet: Wer sein Gold zählt, weiß
nicht, woher es kam.

### Sell-through

```
sellThrough = verkaufteStückzahl / (verkaufteStückzahl + abgelaufeneStückzahl)
```

**Stückzahlbasiert, nicht ereignisbasiert.** 100 eingestellt, 60 verkauft, 40
abgelaufen sind 60 % – nicht 50 %, nur weil es eine Verkaufsmeldung und eine
Ablaufmeldung gab.

**Zurückgezogene Auktionen stehen in keinem der beiden Summanden.** Ein Abbruch
ist eine Entscheidung des Spielers, kein Urteil des Marktes.

Daneben steht `sellThroughAuctions` als Rate je Auktion. Sie ist immer
verfügbar, auch wenn eine Stückzahl fehlt – jede Verkaufsrechnung ist genau
eine verkaufte Auktion. Konnte auch nur **ein** Verkauf eines Items keiner
Einstellung zugeordnet werden, gibt es **keine** stückzahlbasierte Rate: Sie
wäre zu niedrig, und eine zu niedrige Rate ist eine Falschaussage. Der
Handel-Tab zeigt dann die Rate je Auktion mit einem `*`.

Die Datenlage hängt an der Stichprobe: ab 6 Auktionen und 20 Stück „mittel“,
ab 20 Auktionen und 100 Stück „hoch“. Drei Verkäufe gegen einen Ablauf sind
75 % – aber mit niedriger Confidence.

### Median Time To Sale

Zwischen Einstellen und Eintreffen der Verkaufsrechnung liegt eine reale
Spanne. Sie wird zweimal gespeichert, weil zwei verschiedene Fragen
dahinterstehen:

- **`medianHours`** – von der **letzten** Einstellung bis zum Verkauf. Exakt
  gemessen, ohne jede Annahme. Das ist die Zahl im UI.
- **`medianHoldHours`** – von der **ersten** Einstellung derselben Position,
  über Neu-Einstellungen hinweg (Fenster: 48 h). Das ist die Zeit, die das
  Kapital wirklich gebunden war, und damit die Grundlage der Profit Velocity.

**Median statt Durchschnitt**: Eine einzige Auktion, die 47 Stunden stand,
verschiebt einen Durchschnitt aus fünf Werten um Stunden. p25 und p75 stehen im
Tooltip daneben.

Ohne zuordenbare Einstellung gibt es **keine Zahl, sondern `nil`**. Kein
Schätzwert, keine Auktionsdauer als Ersatz.

### Liquidity Score 0–100

Er beantwortet: *„Wie leicht bekomme ich dieses Item nach meiner bisherigen
Erfahrung wieder in Gold zurück?“* – ausdrücklich **nicht**, wie stark der
Preis schwankt. **Volatilität ist keine Liquidität.** Die Markthistorie aus 0.5
fließt hier an keiner Stelle ein.

```
1. Sell-through   55 Punkte × min(sellThrough / 0,9 ; 1)
2. Geschwindigkeit 30 Punkte × 24 / (24 + medianHours)
3. Wiederholung   15 Punkte × v / (v + 3)      v = Verkäufe je Woche
```

90 % Sell-through gelten als volle Punktzahl: Der Unterschied zwischen 90 % und
100 % ist Rauschen, und 100 % zu verlangen hieße, dass kein reales Item je gut
abschneidet. Ein Median von 24 h gibt die halbe Punktzahl.

**Fehlende Bausteine werden herausgerechnet, nicht erfunden.** Ist die
Verkaufsdauer unbekannt, entsteht der Score aus den verbleibenden Bausteinen
über deren Gewicht – er wird weder mit 0 bestraft noch mit einem Mittelwert
gefüllt. **Ohne Sell-through-Rate gibt es gar keinen Score, sondern `nil`** –
nicht 50. Die Confidence deckelt zusätzlich: „niedrig“ höchstens 55, „mittel“
höchstens 80.

Beispiel: `sellThrough 0,87 · medianHours 4,2 · 8 Verkäufe/Woche · high`
→ 53,2 + 25,5 + 10,9 = **90/100**.

### Profit Velocity

```
erwarteterGewinn = expectedProfit × sellThrough
haltedauerTage   = max(holdingHours ; 2 h) / 24
velocity         = erwarteterGewinn / kapital / haltedauerTage      [1/Tag]
```

und daraus die Zahl, die ein Mensch lesen kann: **Gewinn je 100 g gebundenem
Kapital und Tag**.

`sellThrough` gehört in den **Zähler**, nicht in die Zeit: Es ist die
Wahrscheinlichkeit, dass der Gewinn überhaupt eintritt; die Haltedauer ist die
gemessene Zeit der Verkäufe, die stattgefunden haben. Beides in die Zeit zu
stecken würde dasselbe Risiko zweimal zählen. Die **Mindesthaltedauer von zwei
Stunden** verhindert, dass ein einziger Verkauf nach vier Minuten zu einer
Rendite von mehreren tausend Prozent am Tag wird.

Ohne Sell-through oder ohne gemessene Haltedauer gibt es **keine Zahl**.

Beispiel: Craft für 65 g Materialkosten, +19 g Gewinn, 88 % Sell-through,
5,4 h Haltedauer → 16,72 g / 65 g / 0,225 Tage = **+114,3 g je 100 g Kapital
und Tag**. Das ist eine **Rate je eingesetztem Gold, keine Aussage über die
Menge**: Wie viele Stück der Markt am Tag abnimmt, weiß Gold Copilot nicht und
behauptet es auch nicht.

### Persönliche Preise und realisierter Gewinn

Gold Copilot weiß seit 0.8.0, zu welchem Preis **du** ein Item kaufst und
verkaufst – nach Stückzahl gewichtet, als Durchschnitt und als Median. Daraus
die **realisierte Marge**: `(Median-Verkauf netto − Median-Einkauf) /
Median-Einkauf`.

Der **realisierte Gewinn** rechnet mit dem gewichteten Durchschnittspreis als
Kostenbasis – eine echte FIFO-/LIFO-Buchhaltung gibt die Datenlage nicht her,
und sie zu behaupten wäre schlimmer, als sie wegzulassen:

```
realizedProfit = Nettoerlös − Ø Einkaufspreis × verkaufteStückzahl − verloreneEinstellgebühren
```

**Selbst gefarmte, gecraftete oder erbeutete Ware bekommt keine Kostenbasis 0.**
Wer 60 Stück verkauft, aber nur 20 gekauft hat, hat 40 Stück unbekannter
Herkunft – dann gibt es keinen realisierten Gewinn, sondern `nil` und die
Angabe, wie weit die Kostenbasis trägt. Die **AH-Gebühr wird genau einmal**
abgezogen, und zwar mit dem Betrag aus der Rechnung des Clients; fehlt er, gilt
der bekannte 5-%-Satz aus `Constants.lua` – dieselbe Zahl wie überall sonst im
Addon.

### Was das mit den Chancen macht

Der Opportunity Score aus 0.6 wird **erweitert, nicht ersetzt**:

```
adjust = 15 Punkte × clamp((liquidityScore − 55) / 50 ; −1 ; +1) × Gewicht
Gewicht = 0 / 0,25 / 0,65 / 1,0   nach Sell-through-Confidence
```

- **Ohne eigene Verkaufsdaten ist der Zuschlag exakt 0.** Eine 0.6-Bewertung
  bleibt Punkt für Punkt dieselbe, und die Oberfläche schreibt „Liquidität
  unbekannt“ – das ist die ganze Aussage.
- **Zwei Auktionen** ergeben „niedrig“ und damit höchstens 3,75 Punkte
  Verschiebung. Eine einzelne gescheiterte Auktion darf keine gute Chance
  zerstören.
- Der Zuschlag wirkt **vor** dem Confidence-Deckel: Ein Abschlag zieht immer,
  ein Zuschlag nur so weit, wie die Preisdaten ihn tragen.

Der Chancen-Tab bekommt eine Liquiditätsspalte und fünf Sortiermodi
(Opportunity Score, Profit Velocity, Liquidität, Profit, ROI). **Standard
bleibt der Opportunity Score** – die Liquidität steckt seit 0.8 in ihm drin,
deshalb gibt es bewusst keine automatische Umschaltung, die je nach Datenlage
hin und her springt.

### Deine Daten bleiben bei dir

**Alle persönlichen Handelsdaten liegen ausschließlich lokal in deinen
SavedVariables** (`WTF\Account\…\SavedVariables\GoldCopilot.lua`, Schlüssel
`db.ledger`). Nichts davon wird übertragen, hochgeladen, geteilt oder an
irgendeinen Dienst gemeldet – ein WoW-Addon kann das technisch nicht, und Gold
Copilot versucht es auch nicht. `/gold ledgerstats` zeigt Umfang und
Speicherbedarf, `/gold ledgerreset` löscht die Bilanz (und nur sie).

Gespeichert werden 60 Tage Rohereignisse (max. 4000) für die 7- und
30-Tage-Ansicht plus dauerhafte Aggregate je Item (max. 400 Items, je 60
Stichproben). Die Aggregate sind das Langzeitgedächtnis und überleben das
Aufräumen der Rohereignisse.

### Was 0.8 ausdrücklich **nicht** kann

- **Verkaufszeiten schätzen.** Ohne zuordenbare Einstellung gibt es keinen
  Median, sondern `nil`.
- **Sagen, wie viel der Markt am Tag abnimmt.** Die Profit Velocity ist eine
  Rate je Gold, keine Mengenaussage.
- **Eine Auktion eindeutig identifizieren.** Die klassische Auktions-API kennt
  keine Auktions-ID; die Zuordnung Einstellung → Verkauf ist immer eine
  Rekonstruktion (siehe FAQ).
- **Kapital verteilen.** Portfolio, Exposure und Cash-Reserve kommen mit 0.9;
  die Datenmodelle sind darauf ausgelegt, mehr nicht.

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
- `/gold zukunft` öffnet direkt den Zukunft-Tab.
- `/gold handel` öffnet direkt den Handel-Tab.
- `/gold ledgerstats` zeigt Umfang, Alter und geschätzte Dateigröße deiner
  Handelsbilanz und ob die beiden Erfassungswege (Einstell-Hook und
  Briefkasten-Abgleich) tatsächlich laufen.
- `/gold ledgerreset confirm` löscht **ausschließlich** die Handelsbilanz.
  Ohne `confirm` passiert nichts.
- `/gold wissen` zeigt Wissensstand, Umfang der Wissensbasis, aktuelle und
  nächste Phase, die Größe des Dependency Graphs und alles, was die Prüfung
  verworfen hat.
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
- **Zukunft**: Der Future Demand Score gewichtet jeden bekannten Catalyst mit
  `strength × Confidence × Provenance × Zeitfenster × Ebene im Dependency
  Graph`, summiert Nachfrage- und Angebotsseite getrennt mit abnehmendem Ertrag
  und verrechnet beide gegeneinander. Der Hype Score kommt ausschließlich aus
  deiner eigenen Realm-Historie, der Future Opportunity Score baut auf 50 auf
  und wird durch Wissens-Confidence **und** Datenlage gedeckelt. Keine dieser
  Zahlen ist eine Preisprognose.
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

**Wie lernt das Addon meine Verkäufe kennen?** – Über zwei Wege, beide aus der
Client-API: Beim Einstellen liest es `PostAuction` mit (Item, Stückzahl,
Preis, Einstellgebühr), und beim Öffnen des Briefkastens liest es die
AH-Rechnungen (`GetInboxInvoiceInfo`) sowie die Betreffzeilen abgelaufener und
zurückgezogener Auktionen. **Öffne also ab und zu deinen Briefkasten** – ohne
ihn sieht Gold Copilot keinen einzigen Verkauf. `/gold ledgerstats` sagt dir,
ob beide Wege laufen.

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

**Sagt mir der Zukunft-Tab, welcher Preis kommt?** – Nein. Er sagt, welche
bereits bekannten Ereignisse die Nachfrage nach einem Item verändern könnten,
wie sicher dieses Wissen ist, und ob dein Realm es schon eingepreist hat. Ein
Future Demand Score von 91 ist eine Einschätzung über Spielzusammenhänge, keine
Kurserwartung – und **keine Garantie**.

**Warum steht im Zukunft-Tab „Termin offen“?** – Weil Blizzard für diese Phase
noch keinen Anniversary-Termin angekündigt hat. Gold Copilot übernimmt
grundsätzlich **kein** Datum aus dem alten TBC oder aus TBC Classic – ein
falscher Termin wäre schlimmer als gar keiner. Der Inhalt der Phase ist trotzdem
modelliert und zählt, nur schwächer.

**Woher kommt das Wissen über kommende Phasen?** – Aus der mit dem Addon
ausgelieferten Wissensbasis in `Knowledge/`. Ein WoW-Addon kann keine Webseiten
abrufen, es gibt also keine Live-Abfragen. Der Stand steht sichtbar im Tab, und
`/gold wissen` zeigt Umfang und Herkunft.

**Der Chancen-Tab ist leer, obwohl der Markt-Tab voll ist.** – Wahrscheinlich
greifen die Filter: voreingestellt sind 1 g Mindestprofit und 5 % Mindest-ROI.
Wie viele Chancen daran hängen bleiben, steht in der Kopfzeile; die Schwellen
stehen in den Optionen. Sonst fehlt der Engine schlicht Futter: Craft-Chancen
brauchen gescannte Rezepte, Entzauber-Chancen brauchen Auctionator, und Resale
braucht mehrere Tage eigener Markthistorie.

**Sieht Gold Copilot meine Gildenbank?** – Nein, bewusst nicht.

**Verändert das Addon etwas an meinen Auktionen?** – Nein. Es liest Preise
und Bestände, stellt aber nichts ein und kauft nichts. Seit 0.8.0 liest es
zusätzlich mit, *dass* du eingestellt hast (`PostAuction` per
`hooksecurefunc`) – es ruft die Funktion nie selbst auf.

**Warum steht bei manchen Verkäufen „Stückzahl unbekannt“?** – Weil die
klassische Auktions-API es nicht sagt. Die Verkaufsrechnung im Briefkasten
nennt nur den **Item-Namen** und den Betrag: keine Item-ID, keine Menge, keinen
Verkaufszeitpunkt, keine Auktions-ID. Gold Copilot rekonstruiert die Zuordnung
aus deinen eigenen Einstellungen in drei Stufen – Preis × Menge geht genau auf,
oder es gibt nur eine offene Einstellung dieses Items, oder eben gar nichts.
Im letzten Fall bleibt die Stückzahl **unbekannt**: Der Umsatz zählt, die
stückzahlbasierte Sell-through-Rate wird abgeschaltet. Lieber `UNKNOWN` als
eine Rate, die einen echten Verkauf nicht mitzählt.

**Warum werden meine Verkäufe von letzter Woche nicht erfasst?** – Weil Gold
Copilot nur mitschreiben kann, was passiert, während es läuft. Es gibt in
Classic keine Historie, die sich nachträglich auslesen ließe. Die Bilanz
beginnt mit dem Tag, an dem du 0.8.0 installierst – und Verkäufe von
Auktionen, die vorher eingestellt wurden, haben keine zugehörige Einstellung
und landen deshalb als „Stückzahl unbekannt“.

**Brauche ich Journalator oder TSM Accounting?** – Nein, und Gold Copilot
liest auch nicht deren Daten. Journalator veröffentlicht keine stabile
öffentliche API, und seine Fassungen zielen auf Retail, Season of Mastery und
Wrath, nicht auf TBC Anniversary; an seine internen Tabellen anzudocken hieße,
sich an etwas zu hängen, das sich jederzeit ändern darf. Gold Copilot erfasst
deshalb selbst – aus dem Briefkasten und dem Einstellvorgang, beides
Client-API. Wenn du Journalator zusätzlich nutzt, stört das nichts.

**Verlassen meine Handelsdaten meinen Rechner?** – Nein. Sie liegen
ausschließlich lokal in deinen SavedVariables. Es gibt keinen Upload, keine
Telemetrie und keinen Abgleich mit irgendeinem Dienst.

## Lizenz

MIT – siehe [LICENSE](LICENSE).
