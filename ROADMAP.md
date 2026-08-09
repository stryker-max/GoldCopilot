# Ideen für kommende Versionen

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

## Liquidity Brain (0.8)

Die Felder liegen im Datenmodell bereit und stehen ausdrücklich auf `nil`,
damit niemand einen erfundenen Standardwert für eine Messung hält:

- **Liquidity Score / Sell-Through**: Wie schnell verkauft sich das Item
  wirklich? Ein historisch billiges Item, das niemand kauft, ist kein Gewinn.
  Das ist die größte offene Lücke der Engine, und 0.6 wie 0.7 sagen das an
  jeder Zeile ausdrücklich dazu.
- **Profit Velocity**: Gewinn je Zeit statt Gewinn je Durchgang – erst damit
  wird die Rangfolge der Chancen wirklich belastbar. Braucht Sell-Through.
- **Personal Sales Learning**: eingehende AH-Erlöse aus dem Postfach
  mitschreiben und daraus lernen, was sich auf diesem Realm tatsächlich
  verkauft – und wie lange es dauert.
- **Treffsicherheit auswerten**: `db.opportunityHistory` schreibt seit 0.6 mit,
  was die Engine wann behauptet hat, seit 0.7 auch die Future-Signale samt
  Phase und Catalyst-IDs. Daraus lässt sich gegen die tatsächliche
  Preisentwicklung prüfen, ob die Scores etwas taugen – und die Konstanten in
  `Constants.lua` an echten Daten kalibrieren statt an Gefühl.
- **Portfolio Exposure**: Wie viel Gold steckt bereits in einer einzelnen
  These? Der Future Opportunity Score kennt diese Frage bewusst noch nicht.
- **Capital Allocation**: Wie verteilt sich vorhandenes Gold sinnvoll auf
  Trading, Crafting und langfristige Investments?

- **Tooltip-Integration**: bester Verkaufskanal und Nettowert direkt im
  Item-Tooltip (abschaltbar).
- **Craft-Profit aus echten Rezepten**: gelernte Berufe scannen
  (TradeSkill-API) und alle Rezepte nach Gewinn sortieren, statt nur der
  kuratierten Cooldown-Liste.
- **Auktions-Pflege**: auslaufende eigene Auktionen und Undercut-Hinweise in
  der Tagesliste.
- **Verkaufs-Historie**: eingehende AH-Erlöse aus dem Postfach mitschreiben
  und im Goldverlauf getrennt ausweisen.
- **Minimap-Knopf** und Fensterposition merken.
- **Lokalisierung**: englische Oberfläche.
- **CurseForge-Veröffentlichung** mit gepackten Releases.
