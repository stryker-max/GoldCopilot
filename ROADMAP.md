# Ideen für kommende Versionen

## Auf dem Market Brain aufbauend (0.6 und später)

Der Market Score aus 0.5.0 beantwortet ausdrücklich nur eine Frage: *Wie
günstig ist der aktuelle Preis, gemessen an der eigenen Historie?* Er ist kein
„Kaufen“. Damit daraus ein echtes Kaufsignal wird, fehlen noch die Faktoren,
für die die Market Engine bewusst offen gebaut ist – jeder von ihnen hängt sich
an `Market:GetMarketScore()` und `Market:RegisterItem()` an, ohne die
Aufzeichnung anfassen zu müssen:

- **Liquidity Score / Sell-Through**: Wie schnell verkauft sich das Item
  wirklich? Ein historisch billiges Item, das niemand kauft, ist kein Gewinn.
- **Future Demand Score**: Welche Materialien werden durch kommende Phasen
  voraussichtlich stärker nachgefragt? Nur mit belegbarer Grundlage – keine
  hartkodierten Behauptungen über die Zukunft.
- **Craft-, Disenchant- und Stack-Arbitrage** auf Basis der Zeitreihen statt
  einzelner Momentanpreise.
- **Capital Allocation**: Wie verteilt sich vorhandenes Gold sinnvoll auf
  Trading, Crafting und langfristige Investments?
- Daraus dann: `Opportunity Score = Market Value × Future Demand × Liquidity ×
  Confidence − Risk − Hype`.

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
