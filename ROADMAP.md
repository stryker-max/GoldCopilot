# Ideen für kommende Versionen

## Erledigt in 0.6.0

Craft-, Conversion- und Disenchant-Arbitrage, historische Unterbewertung, der
Opportunity Score, die Beobachtungsliste und das Chancen-Protokoll stehen. Der
Score ist bewusst additiv statt multiplikativ geworden: Ein Produkt aus fünf
Faktoren wird von jedem einzelnen auf null gezogen, und genau die Faktoren, die
0.6 noch gar nicht messen kann, hätten dort gestanden.

## Future Market (0.7)

Die Felder liegen im Datenmodell jeder Chance bereit und stehen ausdrücklich
auf `nil`, damit niemand einen erfundenen Standardwert für eine Messung hält:

- **Liquidity Score / Sell-Through**: Wie schnell verkauft sich das Item
  wirklich? Ein historisch billiges Item, das niemand kauft, ist kein Gewinn.
  Das ist die größte offene Lücke der Opportunity Engine, und 0.6 sagt das an
  jeder Chance ausdrücklich dazu.
- **Profit Velocity**: Gewinn je Zeit statt Gewinn je Durchgang – erst damit
  wird die Rangfolge der Chancen wirklich belastbar. Braucht Sell-Through.
- **Future Demand Score**: Welche Materialien werden durch kommende Phasen
  voraussichtlich stärker nachgefragt? Nur mit belegbarer Grundlage – keine
  hartkodierten Behauptungen über die Zukunft.
- **Treffsicherheit auswerten**: `db.opportunityHistory` schreibt seit 0.6 mit,
  was die Engine wann behauptet hat. Daraus lässt sich später gegen die
  tatsächliche Preisentwicklung prüfen, ob der Score etwas taugt – und die
  Konstanten in `Constants.lua` an echten Daten kalibrieren statt an Gefühl.
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
