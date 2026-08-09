# Ideen für kommende Versionen

## Erledigt in 0.8.0

Die persönliche Handelsbilanz in `Ledger.lua`, Sell-through (stückzahlbasiert),
Median Time To Sale, Liquidity Score, Profit Velocity, persönliche Ein- und
Verkaufspreise, realisierter Gewinn, der Handel-Tab und die Ergebniszuordnung
im Chancen-Protokoll stehen. Erfasst wird ausschließlich aus dem Briefkasten
und dem Einstellvorgang; nichts wird geschätzt, und alles bleibt lokal.

## Erledigt in 0.7.0

Die Wissensbasis in `Knowledge/`, der Dependency Graph, Future Demand Score,
Hype Score, Future Opportunity Score, Einstiegszone, „Warum?“-Engine, der
Zukunft-Tab und die Watchlist mit These stehen. Spielwissen und Rechenlogik
sind strikt getrennt, und kein Eintrag kommt ohne Provenance in die
Wissensbasis.

## Wissensbasis erweitern (laufend)

Datenqualität vor Umfang – lieber vierzig belegte Zeilen als fünfhundert
halbrichtige. Offen und ausdrücklich **nicht** erfunden:

- **Mengen der Zwischenstufen** (Netherstoffballen, Adamantitbarren): Die
  Beziehung ist gesichert und als Kante hinterlegt, die genaue Stückzahl steht
  bewusst auf `nil`.
- **Weitere Widerstandssets**: Redeemed Soul (Leder) und Shackled Souls (Kette)
  sind über den Materialkatalog abgedeckt, aber noch ohne eigene Rezeptkanten.
- **Netherschwingen**: als Phaseninhalt vermerkt, ohne Item-Catalyst – ein
  belastbarer wirtschaftlicher Zusammenhang fehlt bislang.
- **Spätere Phasen**: Zul'Aman und Sonnenbrunnen sind inhaltlich modelliert,
  aber ohne Termin und ohne Item-Catalysts.

## Capital Allocator / Portfolio Brain (0.9)

0.8 weiß, wie schnell ein einzelnes Item wieder zu Gold wird. Offen bleibt die
Frage darüber: **Wohin mit dem Gold, das da ist?** Die Datenmodelle sind darauf
ausgelegt – `Ledger` kennt offene Einstellungen, gebundenes Kapital je Item,
realisierte Gewinne und die Profit Velocity –, aber 0.8 verteilt bewusst nichts:

- **Verfügbares Gold und Cash-Reserve**: Wie viel darf überhaupt gebunden
  werden, und wie viel bleibt liquide?
- **Offene Positionen je Item**: Was liegt gerade im Auktionshaus, was in der
  Bank, und zu welchem Einstand?
- **Exposure je Catalyst**: Wie viel Gold hängt an einer einzelnen These aus
  der Wissensbasis? Der Future Opportunity Score kennt diese Frage bewusst
  noch nicht.
- **Risiko und Diversifikation**: Zehn Chancen im selben Material sind eine
  Chance mit zehnfachem Einsatz.
- **Allokation nach Profit Velocity**: Kapital dorthin, wo es sich am
  schnellsten dreht – begrenzt durch das, was der Markt tatsächlich aufnimmt.
  Genau diese Markttiefe kennt 0.8 nicht und behauptet sie auch nicht; ohne
  sie bleibt jede Allokation eine Rangfolge, keine Stückzahl.

## Score-Kalibrierung (nach 0.9)

`db.opportunityHistory` schreibt seit 0.6 mit, was die Engine wann behauptet
hat, seit 0.7 auch die Future-Signale samt Phase und Catalyst-IDs und seit 0.8
das **tatsächliche Ergebnis** (`executedAt`, `entryPrice`, `soldAt`,
`exitPrice`, `holdingHours`, `realizedProfit`, `outcome`). Damit lässt sich
erstmals prüfen, welche Opportunity Scores, Future Signals, ROI-, Market- und
Hype-Werte etwas getaugt haben – und die Konstanten in `Constants.lua` an
echten Daten kalibrieren statt an Gefühl. **0.8 wertet ausdrücklich noch nichts
aus und passt keine Gewichte automatisch an**; es legt nur die Daten sauber ab.

- **Tooltip-Integration**: bester Verkaufskanal und Nettowert direkt im
  Item-Tooltip (abschaltbar).
- **Craft-Profit aus echten Rezepten**: gelernte Berufe scannen
  (TradeSkill-API) und alle Rezepte nach Gewinn sortieren, statt nur der
  kuratierten Cooldown-Liste.
- **Auktions-Pflege**: auslaufende eigene Auktionen und Undercut-Hinweise in
  der Tagesliste.
- **AH-Erlöse im Goldverlauf**: Die Erlöse werden seit 0.8.0 mitgeschrieben,
  aber der Goldverlauf weist sie noch nicht getrennt aus.
- **Minimap-Knopf** und Fensterposition merken.
- **Lokalisierung**: englische Oberfläche.
- **CurseForge-Veröffentlichung** mit gepackten Releases.
