# Modelle und Formeln

Alle Gewichte und Grenzen stehen in `Constants.lua` und lassen sich ändern,
ohne eine Zeile Logik anzufassen. Was hier steht, ist die Herleitung.

Grundsatz für jede Formel im Addon: **Eine fehlende Eingabe ergibt keine
Ausgabe.** Kein Score fällt bei fehlenden Daten auf 0 oder 50 zurück, ohne dass
das benannt wird.

---

## Market Score (0–100)

> „Ist der aktuelle Preis, gemessen an der eigenen Geschichte dieses Items,
> günstig?"

Zwei Bestandteile, gewichtet 55 : 45:

- **Perzentil** des aktuellen Preises in der eigenen 30-Tage-Reihe.
- **Abstand zum Median**, zusammengesetzt aus 40 % 7-Tage- und 60 %
  30-Tage-Median. 1 % Abstand = 1 Punkt.

Danach zwei Korrekturen:

- **Volatilität** (Quartilsabstand am Median, gedeckelt bei 0,6) dämpft den
  Ausschlag um bis zu 25 %.
- **Datenqualität** zieht den Score Richtung 50 („keine Aussage"): Faktor
  0 / 0,35 / 0,7 / 1,0 für keine / niedrige / mittlere / hohe Confidence.

Unter drei Messpunkten gibt es keinen Score, sondern `nil`.

**Confidence** braucht beides – Tage *und* Messpunkte: mittel ab 3 Tagen und 5
Punkten, hoch ab 7 Tagen und 10 Punkten.

---

## Opportunity Score (0–100)

Vier Gutschriften summieren sich auf 100, zwei Abschläge ziehen bis zu 30 ab,
ein Zu-/Abschlag verschiebt um bis zu 15.

| Bestandteil | max. | Kurve |
| --- | --- | --- |
| Kapitaleffizienz (ROI) | 35 | Sättigung, halbe Punktzahl bei 25 % ROI |
| Absolute Größe | 15 | Sättigung, halbe Punktzahl bei 10 g Gewinn |
| Market Score der **Kaufseite** | 25 | linear; fehlt er, zählt 50 |
| Datenqualität | 25 | 0 / 8 / 17 / 25 |
| − Volatilität | −15 | linear bis Deckel 0,6 |
| − Kapitalbedarf | −15 | Sättigung, halber Abschlag bei 250 g |
| ± Liquidität | ±15 | um Neutralwert 55, gewichtet nach Stichprobe |

Danach zwei harte Deckel:

- **Confidence-Deckel**: keine 0, niedrig 55, mittel 80, hoch 100. Eine dünne
  Datenbasis kann nie „sehr interessant" ergeben, egal wie gut die Rechnung
  aussieht.
- **Kalibrierungsfaktor** (siehe unten), anschließend erneut auf den
  Confidence-Deckel und auf 0–100 begrenzt.

Ohne Datenlage (`confidence == "none"`) entsteht **gar kein Score**.

---

## Liquidity Score (0–100)

Ausschließlich aus den eigenen, tatsächlich stattgefundenen Geschäften.

| Bestandteil | max. | Kurve |
| --- | --- | --- |
| Sell-through (stückzahlbasiert) | 55 | 90 % = volle Punktzahl |
| Verkaufsgeschwindigkeit | 30 | Sättigung, halbe Punktzahl bei 24 h Median |
| Wiederholungshäufigkeit | 15 | Sättigung, halbe Punktzahl bei 3 Verkäufen/Woche |

Gedeckelt nach Stichprobe: keine 0, niedrig 55, mittel 80, hoch 100.

Die Sell-through-Rate entsteht **nur**, wenn jeder Verkauf einer Einstellung
zugeordnet werden konnte. Ein Verkauf ohne bekannte Stückzahl schaltet sie ab –
sie wäre sonst zu niedrig.

**Profit Velocity** = erwarteter Gewinn × Sell-through, geteilt durch
Haltedauer in Tagen, bezogen auf 100 g gebundenes Kapital. Ohne gemessene
Haltedauer gibt es sie nicht.

---

## Future Demand Score (0–100)

50 heißt „keine bekannten Faktoren". Darüber sprechen bekannte Faktoren eher
für zusätzliche Nachfrage, darunter eher für Angebotsdruck.

Jeder Catalyst bekommt ein Gewicht aus fünf Faktoren:

```
gewicht = stärke × confidence × quellensicherheit × zeitfenster × ausbreitung
```

- **Ausbreitung** über den Dependency Graph: 1,0 direkt, 0,7 eine Ebene
  entfernt, 0,4 zwei Ebenen. Tiefer nicht – nach drei Ebenen hängt jedes
  Material der Scherbenwelt an jedem Ereignis.
- **Abnehmender Ertrag**: der stärkste Grund zählt voll, der zweite zu 60 %,
  der dritte zu 36 %. Acht kleine Verweise schlagen nicht einen starken.
- Nachfrage- und Angebotsseite laufen durch dieselbe Sättigungskurve und
  werden gegeneinander verrechnet.

## Hype Score (0–100)

Ausschließlich aus eigenen Realm-Daten: Aufschlag über den 30-Tage-Median
(35 %), Perzentil (25 %), Momentum der letzten Tage (25 %), Volatilität (15 %).
Unter 6 Messpunkten oder 3 Tagen gibt es **keinen** Hype Score – „kein Hype"
wäre hier die gefährlichste Falschaussage.

## Future Opportunity Score

Basis 50, verschoben durch Future Demand (Gewicht 0,5), Market Score (0,35) und
Hype (0,6, invertiert – bereits gelaufen ist schlechter), plus einen kleinen
Zeitfensterbonus, minus Volatilität, plus einen sehr kleinen Liquiditätsanteil.
Zwei Deckel: einer aus der Sicherheit des Wissens, einer aus der Qualität der
Realm-Daten.

---

## Position Sizing

Ausgangspunkt ist ein Anteil des investierbaren Kapitals (18 %), auf den
Faktoren **multiplikativ** wirken – weil sich die Gründe verstärken sollen:
Eine gute Chance mit dünner Datenlage und hoher Volatilität ist keine
mittelgroße Position, sondern eine kleine.

| Faktor | Wirkung |
| --- | --- |
| Score | ±60 % um den Neutralwert 50 |
| Datenlage | ×0,30 / 0,50 / 0,80 / 1,00 |
| Liquidität | ±35 % um Score 55; **unbekannt = ×0,75** |
| Volatilität | bis −35 % |
| Profit Velocity | bis +20 % |
| Future Demand | ±20 % |
| Hype ≥ 70 | −30 % |
| Angebotslage | Überversorgung ×0,7, dünner Markt ×0,85 |
| Risikostufe | niedrig ×0,6, mittel ×1,0, hoch ×1,4 |

Danach: Deckel auf 2 %–35 % (**nie All-In**), dann die Exposure-Grenzen als
absoluter Betrag, dann das verbleibende Kapital, dann das Marktangebot, dann
das Zeitbudget. Erst zum Schluss wird in ganze Stück umgerechnet – „0,7 mal
kaufen" gibt es nicht.

## Exposure

Bezugsgröße ist das **investierbare Kapital**: freies Gold plus das, was
bereits in Positionen steckt. Nicht das Gesamtvermögen (die Reserve soll gerade
nicht als Spielraum durchgehen) und nicht nur das freie Gold (sonst wäre jede
bestehende Position sofort über jeder Grenze).

| Dimension | Warnung ab | harte Grenze |
| --- | --- | --- |
| Item | 12 % | 20 % |
| Chancenart | 35 % | 55 % |
| Catalyst | 25 % | 40 % |
| Phase | 35 % | 55 % |
| Marktgruppe | 30 % | 50 % |

Positionen ohne bekannte Herkunft landen im Eimer „unbekannt" und blockieren
keine Chancenart – dass früher einmal etwas gekauft wurde, sagt nichts darüber,
ob ein Craft heute zu viel Kapital in eine Richtung legt.

## Capital Allocator

Kein „bester Score bekommt alles". Die Kandidaten werden nach Score (angehoben
um die Profit Velocity, **wo sie bekannt ist**) sortiert; dann wird der Reihe
nach zugeteilt, und **jede Zuteilung erhöht das Exposure, das die nächste
begrenzt**. Dadurch verteilt sich Kapital von selbst, ohne eine
Diversifikationsquote zu erfinden. Zusätzlich bekommt jede weitere Chance
derselben Art nur noch 80 % des Anteils der vorigen.

Wird gar nichts zugeteilt, obwohl es Kandidaten gab, wird der häufigste Grund
benannt – eine leere Liste ohne Begründung wäre die schlechteste Antwort.

---

## Route

**Reihenfolge**: topologische Sortierung (Kahn) mit einer Auswahlheuristik.
Aus den gerade möglichen Aktionen gewinnt die mit dem besten Wert aus
`−Reisezeit + Gruppenrang`. Bei Gleichstand die früher erzeugte – derselbe Plan
ergibt immer dieselbe Route.

**Reisezeit** hat vier Stufen: gleicher Ort 0, gleicher Knotenpunkt 1,5,
gleiche Zone 3, andere Zone 6 Minuten. Mehr wäre geraten.

**Wege** werden erst eingesetzt, wenn die Reihenfolge steht – ein `GO_TO`, das
schon in der Zerlegung entsteht, wäre bei jeder Umsortierung falsch.

**Zeitbudget**: bis zu drei Durchläufe. Passt der Plan nicht, fallen ganze
Gruppen heraus (nie halbe: eine halbe Craft-Kette ist gebundenes Kapital ohne
Verkauf), und es wird neu gebaut – nicht abgeschnitten, weil der
Bestandsabgleich sonst falsche Kaufmengen behielte.

**Goldziel**: ein Ziel, keine Zusage. Findet der Planer nur Chancen für 180 g,
steht 180 g da – und daneben, dass 500 g gewünscht waren.

## Replanning und Hysteresis

Ausgelöst wird von Ereignissen, nicht von einer Uhr:

`market_revision · opportunity_invalid · price_above_max · price_below_min ·
item_unavailable · capital_changed · step_skipped · craft_impossible ·
inventory_changed · strong_opportunity · time_budget`

Ausgeführt wird gedrosselt (frühestens alle 20 Sekunden, höchstens 40-mal je
Sitzung) und nur, wenn der neue Plan **materiell besser** ist: mindestens 12 %
mehr erwarteter Gewinn **und** mindestens 5 g mehr. Eine ungültig gewordene
Route wird immer ersetzt.

Erledigte und übersprungene Schritte bleiben dabei stehen und werden der neuen
Route vorangestellt.

## Auto-Completion

| Schritt | Beleg |
| --- | --- |
| Weg zum Auktionshaus | `AUCTION_HOUSE_SHOW` |
| Weg zur Bank | `BANKFRAME_OPENED` |
| Weg zum Briefkasten | `MAIL_SHOW` |
| Weg zum Beruf | `TRADE_SKILL_SHOW` / `CRAFT_SHOW` |
| Weg ins Farmgebiet | Zonenwechsel in die richtige Zone |
| Kaufen | bestätigter Kauf im Ledger, sonst Bestandszuwachs |
| Herstellen / Umwandeln | Bestandszuwachs um die erwartete Menge |
| Einstellen | bestätigtes Einstellen im Ledger |
| Alles andere | **manuell** – und im Protokoll steht, dass es manuell war |

---

## Farmraten

Median statt Mittelwert über die eigenen Sitzungen; eine Sitzung mit einem
Glückstreffer soll die Erwartung nicht verschieben. Confidence nach Zahl der
Sitzungen: niedrig ab 2, mittel ab 5, hoch ab 12.

Eine Sitzung unter 5 Minuten oder ohne Ausbeute wird nicht gewertet. Ohne
Ausbeute über 15 Minuten beendet sich die Sitzung von selbst – wer sie offen
lässt und schlafen geht, bekommt keine 8-Stunden-Rate.

**Es gibt keine Gold/h aus Guides.** Ohne eigene Messung entsteht kein
Farmblock in einer Route.

---

## Markttiefe und Marktstruktur

Datenquelle ist ausschließlich die Auktionsliste, die der Spieler selbst
durchblättert. Gemessen wird die angezeigte Seite; die Menge ist damit eine
**Untergrenze** und heißt auch so.

| Signal | Bedingung |
| --- | --- |
| `THIN_MARKET` | ≤ 3 Angebote oder ≤ 5 Stück |
| `SUPPLY_SHOCK` | ≥ 3-faches der eigenen Median-Menge (ab 4 Messungen) |
| `PRICE_WALL` | eine Preisstufe hält ≥ 60 % der Sofortkaufmenge |
| `PRICE_OUTLIER` | günstigstes Angebot ≤ 60 % des nächsten |
| `UNUSUAL_LISTING_CONCENTRATION` | ≥ 70 % der Angebote aus einer Quelle |

Kein Signal heißt „Manipulation". Warum jemand so anbietet, weiß niemand –
Gold Copilot beschreibt die Struktur und sagt das auch dazu.

---

## Kalibrierung

Keine KI, keine Blackbox. Eine Rechnung:

```
angepasst = 1 + (gemessen − 1) × n / (n + 30)
```

`gemessen` ist die Trefferquote einer Chancenart geteilt durch die eigene
Gesamttrefferquote. Der Prior von 30 sorgt dafür, dass selbst bei 100 Fällen
ein Rest Standardmodell stehen bleibt.

Sicherheitsregeln:

- mindestens **40** abgeschlossene Fälle insgesamt und **15** je Chancenart
- harte Grenzen ×0,75 bis ×1,25
- höchstens ×0,05 Änderung je Durchlauf
- versioniert: ändert sich das Modell, fängt die Kalibrierung neu an
- jederzeit rücksetzbar, **voreingestellt aus**

Angepasst werden ausschließlich Multiplikatoren auf den fertigen Score je
Chancenart – nicht die Formel und nicht die einzelnen Summanden. Der Rechenweg
bleibt derselbe und bleibt nachvollziehbar.
