# Phase 2 – Architekturplan

> Von „welche Chance rechnet sich?" zu „was soll ich jetzt tun?"

Dieser Plan steht **vor** der Umsetzung. Er beantwortet die fünfzehn Fragen aus
dem Auftrag, benennt die technischen Grenzen des Clients ehrlich und legt die
Reihenfolge fest.

---

## 0. Ausgangslage

Nach dem Audit (1.0.0-beta.10) steht die Kette

```
Market → Opportunity → Capital → Execution → Route → Guide → Ledger → Analytics
```

Sie ist rechnerisch sauber: Kosten und Kapitalbedarf sind getrennt, die
Angebotslage zählt alle Zutaten, Vorhersagen werden belegt zugeordnet. Was
fehlt, ist eine Ebene darüber. Heute gilt:

**Eine Chance mit positivem Gewinn und guten Preisdaten wird zur Empfehlung.**

Das ist zu wenig. Ob jemand das Produkt *kauft*, steht in dieser Kette an keiner
Stelle. `Ledger:GetLiquidity` weiß es, aber nur als weicher Zu-/Abschlag von
±15 Punkten auf einen Score – und wo es nichts weiß, verschiebt es gar nichts.
Eine Nischenrüstung ohne einen einzigen eigenen Verkauf kann heute die
Startseite füllen, wenn nur die Marge stimmt.

---

## 1. Welche bestehenden Module bleiben, wie sie sind?

Der weitaus größte Teil. Phase 2 baut **auf** der Kette auf, sie ersetzt nichts.

| Modul | Rolle in Phase 2 |
| --- | --- |
| `Market.lua` | unverändert. Liefert Preis, Historie, Trend, **Preisstufen** (`GetDepth().priceLevels`) – die Grundlage der echten Arbitrage. |
| `Ledger.lua` | wird **erweitert**, nicht umgebaut: gefensterte Item-Statistik und Preisband-Statistik kommen dazu. Sell-through, Time-to-Sale, Deposit-Logik bleiben Zeile für Zeile. |
| `Opportunity.lua` | bleibt die Bewertung. Der Opportunity Score bleibt, was er ist – ein Bestandteil, nicht mehr die Antwort. |
| `Capital.lua` | bleibt Position Sizing und Exposure. Bekommt eine weitere Grenze (`demandCapacity`) in dieselbe `math.min`-Kette. |
| `Execution/Route/Guide` | unverändert. Eine Empfehlung wird weiterhin genau so ausgeführt. |
| `Farm.lua` | bleibt Messquelle für Farmraten – und wird zur ersten von mehreren Methoden im Vergleich. |
| `Knowledge/` | wird um **Demand Identity** erweitert (Priorwissen, keine Verkaufsbehauptung). |
| `Future.lua` | liefert Phase und Catalysts für Obsoleszenz und Recency. |

**Nichts von alledem wird zusammengelegt.** Die Regel „ein Modul, eine Frage"
gilt weiter.

---

## 2. Welche neuen Module?

Fünf, jedes mit genau einer Frage:

| Modul | Frage |
| --- | --- |
| `Demand.lua` | *Welche Belege gibt es, dass dieses Item gekauft wird?* |
| `Actionability.lua` | *Reichen diese Belege, um Gold und Zeit anzuvertrauen?* |
| `Income.lua` | *Woher kommt das Gold dieses Spielers wirklich?* |
| `Activity.lua` | *Wie viel Gold je Stunde bringt eine Methode bei ihm?* |
| `Recommendation.lua` | *Was soll er jetzt tun – über alle Methoden hinweg?* |

`Actionability` ist bewusst nicht Teil von `Demand`: Die eine Frage ist
beschreibend („was wissen wir?"), die andere entscheidend („reicht das?"). Wer
sie zusammenlegt, kann später die Schwellen nicht ändern, ohne die Messung
anzufassen.

`Income` und `Activity` sind getrennt, weil ein Ereignis und eine Sitzung
verschiedene Lebensdauern haben: Ein Goldzufluss ist eine Beobachtung, eine
Sitzung ist ein Fenster darüber. Farm-Sitzungen liegen schon in `Farm.lua`;
`Activity` vergleicht sie mit Service-Sitzungen, ohne eine davon zu besitzen.

---

## 3. Datenfluss

```
  Knowledge          Market            Ledger           Income
  (Priorwissen)      (Realm)           (eigene Sales)   (Goldzuflüsse)
       │                │                  │                │
       └────────┬───────┴──────┬───────────┘                │
                ▼              ▼                            ▼
           DEMAND.lua                                  ACTIVITY.lua
    Evidence-Level 0–5 je Item                  Methoden: Gold/h, Median,
    demandCapacity (Stück/Zeitraum)             Confidence, Kontext
                │                                          │
                ▼                                          │
        OPPORTUNITY.lua  ──────►  ACTIONABILITY.lua        │
        (Score, Marge, ROI)       PROVEN / TEST /          │
                                  SPECULATIVE / BLOCKED    │
                                          │                │
                                          ▼                │
                                    CAPITAL.lua            │
                              min(Kapital, Exposure,       │
                                  Supply, Zeit, DEMAND)    │
                                          │                │
                                          └───────┬────────┘
                                                  ▼
                                        RECOMMENDATION.lua
                                     vergleicht Item-Aktionen
                                     mit Methoden (Service, Farm)
                                                  │
                                                  ▼
                                             STARTSEITE
                                     Was? Warum? Wie viel? Wie sicher?
```

Zwei Regeln für den Fluss:

1. **Actionability kann nur begrenzen, nie befördern.** Sie hebt keine Chance
   an, die die Opportunity Engine schwach findet.
2. **Recommendation erfindet keine Zahl.** Sie vergleicht nur Zahlen, die
   Demand, Capital und Activity belegt haben.

---

## 4. Wie wird Demand Evidence modelliert?

Vier voneinander **getrennte** Quellen, die nie miteinander verrechnet werden,
bevor ihre Herkunft feststeht:

### A) Structural Demand (Priorwissen)

Aus `Knowledge/Items.lua`, erweitert um eine Demand Identity:

```lua
{ id = 21884, name = "Primal Fire", role = "material",
  demand = {
      type = "RECURRING",        -- RECURRING | ONE_TIME | SEASONAL
      breadth = "HIGH",          -- HIGH | MEDIUM | LOW | NARROW
      consumption = "CONSUMED",  -- CONSUMED | DURABLE
      obsolescence = "LOW",      -- LOW | MEDIUM | HIGH
      source = "inferred",       -- official | historical | inferred
  } }
```

**Das ist keine behauptete Sell-through.** Es ist die Antwort auf „wie viele
Leute könnten das grundsätzlich brauchen, und brauchen sie es wieder?" Ein
Material, das in acht Rezepten steckt und verbraucht wird, hat eine breitere
Nachfragebasis als eine Brustplatte, die man einmal kauft und dann nie wieder.

Die Breite wird nicht geraten: Sie lässt sich aus dem **Dependency Graph**
zählen (`Knowledge:GetProductsOf`). Ein Item, das in vielen Rezepten vorkommt,
hat belegbar breite Verwendung. Für Items ohne Graph-Kante gilt `UNKNOWN`.

Strukturelle Nachfrage erreicht **höchstens Level 1**. Sie darf allein nie eine
starke Empfehlung tragen.

### B) Realm Market Evidence

Aus `Market:GetDepth` und der Preisreihe: Anbieterzahl, Angebotsmenge,
Preisstufen, Stabilität, wiederkehrende Beobachtung.

**Listings sind Angebot, nicht Nachfrage.** Fünfzig Auktionen können heißen,
dass zwanzig Verkäufer auf ihrer Ware sitzen. Realm Evidence erreicht deshalb
höchstens **Level 2** und beantwortet nur: *„Gibt es hier überhaupt einen
Markt?"* Ein Indiz für tatsächliche Nachfrage ist die **Fluktuation**: Wenn die
Angebotsmenge zwischen zwei Beobachtungen fällt, ohne dass der Preis
einbricht, hat jemand gekauft. Das ist die einzige Nachfrageaussage, die sich
aus Realm-Daten ohne eigene Verkäufe ableiten lässt – und sie braucht mehrere
Messungen, sonst entsteht sie nicht.

### C) Personal Sales Evidence (der stärkste Beleg)

Aus `Ledger`: verkaufte Stückzahl, abgelaufene Stückzahl, Sell-through,
Median-Verkaufsdauer, Wiederholungen, realisierte Marge, Relisting-Ketten.

Level 3 ab dem ersten belegten Verkauf, Level 4 ab wiederholten Verkäufen,
Level 5 bei stabiler Historie (Stichprobe **und** Zeitraum).

### D) Current Market State

Historische Nachfrage ist keine heutige. Geprüft wird gegen: aktuellen Preis,
aktuelle Angebotsmenge, Preiswand, **Trend** (seit beta.10), Phase, Catalysts.

Dieser Teil kann ein Evidence-Level **senken**, nie heben: Wer zwanzig Stück
verkauft hat, aber seit dem Phasenwechsel keines mehr, hat keine Level-5-Lage
mehr.

### Evidence-Level

| Level | Bedeutung | Bedingung |
| --- | --- | --- |
| 0 | keine Information | nichts davon |
| 1 | strukturell plausibel | Demand Identity vorhanden |
| 2 | aktiver Realm-Markt | mehrfach beobachtet, Angebot vorhanden |
| 3 | eigener Verkauf belegt | ≥ 1 verkaufte Auktion |
| 4 | wiederholte Verkäufe | ≥ 3 verkaufte Auktionen, Sell-through bekannt |
| 5 | stabile Historie | ≥ 8 Auktionen über ≥ 14 Tage, Sell-through ≥ Schwelle |

Die Schwellen stehen in `Constants.lua`, nicht im Code.

---

## 5. Wie funktioniert Actionability?

Ein Klassifikator, kein Score. Eingang: Opportunity + Evidence. Ausgang:

```lua
{ class = "PROVEN" | "TEST" | "SPECULATIVE" | "BLOCKED",
  maxUnits = 6, reasons = { ... }, blockers = { ... } }
```

| Klasse | Bedingung | Startseite |
| --- | --- | --- |
| `PROVEN` | Evidence ≥ 4, Sell-through über Schwelle, Marktlage heute plausibel, Preis belegt | ja, als „Beste Aktion" |
| `TEST` | Rechnung trägt, Markt existiert, aber Evidence < 4 | ja, ausdrücklich als **Markttest** mit 1 Stück |
| `SPECULATIVE` | Evidence dünn, Preis fraglich, sehr dünner Markt, reine Zukunftswette | nein – nur im Chancen-Tab |
| `BLOCKED` | nicht beschaffbar, Preis unplausibel, Markt tot | nein |

Die Klassen sind **absteigend geordnet**: Was die Bedingungen für `PROVEN`
nicht erfüllt, fällt auf `TEST`, was `TEST` nicht erfüllt, auf `SPECULATIVE`.
Es gibt keinen Pfad nach oben.

Ein Craft ohne einen einzigen eigenen Verkauf kann damit **nie** `PROVEN`
werden, egal wie gut die Marge aussieht. Das ist genau die Sperre, die im
Prüfszenario „20× Nischenrüstung" fehlt.

---

## 6. Wie wird Demand Capacity berechnet?

Die Frage lautet nicht „wie viele kann ich kaufen", sondern „wie viele werde
ich los".

```
demandCapacity = f(Evidence-Level)

Level 0-1   →  0        keine Handlungsempfehlung, nur Beobachtung
Level 2     →  1        Markttest
Level 3     →  1-2      erster Beleg, sehr vorsichtig
Level 4-5   →  aus eigener Absorptionsrate
```

Für Level 4–5 rechnet `Ledger:AbsorptionPerWeek` (seit beta.10) bereits die
Stückzahl je Woche. Darauf kommen zwei Korrekturen:

- **Sell-through**: Wer 15 von 18 Stück verkauft, hat eine andere Kapazität als
  wer 15 von 60 verkauft. Die Rate wird mit der Sell-through multipliziert.
- **Untere Vertrauensgrenze statt Punktschätzung.** Bei kleinen Stichproben ist
  der Median optimistisch. Gerechnet wird konservativ mit
  `n / (n + PRIOR)`-Schrumpfung gegen 1 Stück – dieselbe Formel, die die
  Kalibrierung schon benutzt. Sie hat genau die richtige Eigenschaft: Bei
  wenigen Daten bleibt fast alles beim Markttest, bei vielen nähert sie sich der
  Messung an, und sie springt nie.

`demandCapacity` geht als weitere Grenze in dieselbe `math.min`-Kette von
`Capital:SizePosition`, in der schon Kapital, Exposure, Angebot und Zeit stehen.
`limitedBy` benennt sie, wenn sie greift – damit die Startseite „Warum nur 6?"
beantworten kann.

---

## 7. Wie werden Income Events erfasst?

Ein Income Event ist ein **beobachteter Goldzufluss mit Kontext**:

```lua
{ at, amount, source, confidence, sessionID, note }
```

Quellen und ihr jeweils belastbarster Auslöser:

| Quelle | Beleg |
| --- | --- |
| `AUCTION_SALE` | `Ledger` meldet einen bestätigten Verkauf (Notify-Hook, existiert) |
| `TRADE` | Handelsfenster beidseitig bestätigt **und** Goldzuwachs |
| `SERVICE_ENCHANT` | Trade + Verzauber-Kontext (siehe 9.) |
| `VENDOR` | `MERCHANT_SHOW` offen und Goldzuwachs |
| `QUEST` | `QUEST_TURNED_IN` / `QUEST_FINISHED` mit Goldzuwachs |
| `LOOT` | `CHAT_MSG_MONEY` (der Client nennt den Betrag im Klartext) |
| `UNKNOWN` | Goldstand geändert, kein Kontext |

**Der wichtigste Satz dieses Abschnitts:** Aus einer reinen Änderung des
Goldstands wird **keine Ursache erfunden**. `PLAYER_MONEY` sagt, dass sich etwas
geändert hat, und sonst nichts. Ohne Kontextfenster heißt die Quelle `UNKNOWN`,
und `UNKNOWN` fließt in keine Gold/h-Rechnung ein.

Der Kontext entsteht aus einem kurzen Zeitfenster: Wer gerade ein Handelsfenster
geschlossen hat, dessen Goldzuwachs in den nächsten Sekunden gehört zu diesem
Handel. Wer nichts davon hatte, hat einen Zufluss ohne Ursache.

---

## 8. Wie werden Activities/Sessions erkannt?

Eine Session ist ein Fenster mit Start, Ende, aktiver Zeit und den Income
Events darin. `Farm.lua` macht das seit 0.9 vor; `Activity.lua` verallgemeinert
das Muster:

```lua
{ kind = "service.enchant", startedAt, endedAt, activeMinutes,
  events = n, gross, materialCost, net, zone, hourOfDay, weekday, phase }
```

Start: ausdrücklich durch den Spieler **oder** automatisch, wenn zwei
klassifizierte Service-Trades innerhalb eines kurzen Fensters auftreten.
Ende: durch den Spieler, oder nach `IDLE_TIMEOUT` ohne Ereignis – dieselbe
Regel wie bei Farmsitzungen („wer die Sitzung offen lässt und schlafen geht,
bekommt keine 8-Stunden-Rate").

Aus den Sessions entsteht je Methode eine **Methodenstatistik**: Median Gold/h,
Stichprobe, Confidence. Median statt Mittelwert, weil ein einzelnes 500-g-
Trinkgeld sonst die Erwartung verschiebt – dieselbe Begründung wie bei den
Farmraten.

---

## 9. Wie wird Enchanting Service zuverlässig klassifiziert?

Hier liegt die technisch heikelste Stelle, und hier ist Ehrlichkeit wichtiger
als Vollständigkeit.

**Was der Client hergibt** (TBC Classic, Interface 20506):

| Signal | API |
| --- | --- |
| Handelsfenster offen | `TRADE_SHOW` / `TRADE_CLOSED` |
| beide haben bestätigt | `TRADE_ACCEPT_UPDATE(player, target)` |
| Inhalt der Seiten | `GetTradePlayerItemLink(i)` / `GetTradeTargetItemLink(i)` |
| Gold beider Seiten | `GetPlayerTradeMoney()` / `GetTargetTradeMoney()` |
| Handelspartner | `UnitName("NPC")` während des Handels |
| **Verzauberungs-Slot** | Slot **7** („wird nicht getauscht") |
| Handel abgeschlossen | `ERR_TRADE_COMPLETE` als Systemnachricht |
| Zauber gewirkt | `UNIT_SPELLCAST_SUCCEEDED` |

Der **7. Handelsslot** ist der Glücksfall. In TBC legt der Kunde das zu
verzaubernde Item dort hinein; es wird nicht getauscht. Ein belegter Slot 7 auf
der Kundenseite ist damit ein direkter, nicht interpretierter Beleg für eine
Verzauberungsdienstleistung – kein Muster, keine Heuristik.

**Evidenzstufen der Klassifikation:**

| Confidence | Bedingung |
| --- | --- |
| `high` | Slot 7 belegt **und** Handel abgeschlossen **und** Gold erhalten |
| `medium` | Handel abgeschlossen, Gold erhalten, Verzauberzauber in zeitlicher Nähe |
| `low` | Handel abgeschlossen, Gold erhalten, sonst nichts Passendes |
| – | alles darunter bleibt `TRADE`, nicht `SERVICE_ENCHANT` |

Nur `medium` und `high` zählen in die Service-Statistik. **Eine falsche
Klassifikation ist schlechter als `UNKNOWN`** – ein einzelner Goldtransfer von
einem Gildenkollegen darf keine 400-g/h-Methode erfinden.

### Ehrliche Grenzen des Clients (Punkt 15 des Auftrags)

Diese Dinge gibt der Client **nicht** her. Sie werden nicht simuliert:

1. **`TRADE_CLOSED` sagt nicht, ob der Handel zustande kam.** Es feuert beim
   Abbrechen genauso. Deshalb der Umweg über `ERR_TRADE_COMPLETE` und den
   tatsächlichen Goldzuwachs. Feuert weder das eine noch das andere, gilt der
   Handel als **nicht** erfolgt.
2. **Nach `TRADE_CLOSED` ist der Inhalt weg.** Die API antwortet dann nicht mehr.
   Deshalb wird beim beidseitigen Bestätigen ein Abzug genommen – das ist der
   letzte Moment, in dem der Inhalt noch abfragbar ist.
3. **Es gibt keine Zuordnung „dieser Zauber gehört zu diesem Handel".**
   `UNIT_SPELLCAST_SUCCEEDED` nennt den Zauber, nicht den Kunden. Die Verbindung
   ist ausschließlich zeitliche Nähe – deshalb ist sie `medium` und nicht `high`.
4. **Der Wert der Kundenmaterialien ist kein Einkommen** und wird auch nicht als
   solches erfasst (siehe 10.).
5. **Kein Zugriff auf fremde Addons.** Eine optionale Integration könnte später
   zusätzliche Sicherheit liefern; die Basisfunktion hängt an keiner.
6. **`PLAYER_MONEY` nennt keinen Grund.** Der gesamte Kontextmechanismus
   existiert nur, weil der Client diese Frage nicht beantwortet.

---

## 10. Kundenmaterialien und eigene Materialien

Zwei verschiedene Fälle, und die Verwechslung wäre teuer:

| Fall | Revenue | Economic Cost | Net |
| --- | --- | --- | --- |
| Kunde bringt Mats, zahlt 20 g Trinkgeld | 20 g | 0 | **20 g** |
| Eigene Mats (Marktwert 62 g), Kunde zahlt 100 g | 100 g | 62 g | **38 g** |

Kundenmaterialien sind **Durchlaufmaterial**, kein Einkommen. Erkennbar daran,
dass sie in derselben Handelsseite ankommen wie das Gold – und dass der
verzauberte Gegenstand über Slot 7 zurückgeht.

Eigene Materialien werden über den Bestandsabgleich erkannt und mit ihrem
Marktwert als `economicCost` gebucht – dieselbe Trennung von wirtschaftlichen
Kosten und Cash Flow, die in beta.10 eingeführt wurde.

---

## 11. Wie werden Goldmethoden vergleichbar?

Nicht durch eine gemeinsame Zahl. Ein Flip und eine Farmstunde sind
verschiedene Geschäfte, und sie in eine Kennzahl zu pressen wäre genau die
Sorte Vereinfachung, die falsche Empfehlungen erzeugt.

Verglichen werden **drei Größen nebeneinander**:

| Größe | für wen |
| --- | --- |
| **Active Gold/h** | Farmen, Services – Gold je tatsächlich eingesetzter Spielzeit |
| **Capital Efficiency** | Resale, Crafts – Rendite je gebundenem Gold |
| **Zeitbindung** | AH-Geschäfte binden Kapital lange, aber kaum aktive Zeit |

Die Entscheidungsregel ist bewusst schlicht und erklärbar:

1. Eine Aktion mit belegter **Active Gold/h** und hoher Confidence schlägt eine
   Item-Aktion, deren erwarteter Gewinn je eingesetzter Minute niedriger liegt.
2. Item-Aktionen werden über ihren erwarteten Gewinn geteilt durch die
   **aktive Planzeit** vergleichbar gemacht – nicht über die Haltedauer. Wer
   fünf Minuten braucht, um 40 g zu verdienen, und danach wartet, hat 480 g/h
   aktiv verdient; das Warten kostet Kapital, nicht Zeit.
3. Die Kapitalbindung geht als eigene Zeile in die Begründung, nicht in die
   Zahl.
4. **Ohne belegte Zahl kein Vergleich.** Eine Methode ohne Sitzungen tritt nicht
   an.

---

## 12. Neue Startseitenlogik

```
Recommendation:Best()
  ├── Kandidat 1..n aus Actionability (PROVEN, dann TEST)
  ├── Kandidat aus Activity (Methoden mit belegter Gold/h)
  ├── vergleiche nach Regel 11
  └── kein Kandidat über der Schwelle  →  "DERZEIT KEINE ÜBERZEUGENDE AKTION"
```

Die Startseite zeigt vier Dinge und sonst nichts:

```
BESTE AKTION JETZT
6× Urfeuer kaufen bis max. 21,40 g          ← Was?
Warum?   21 eigene Verkäufe · 86 % · 5,7 h  ← Warum?
Warum 6? Deine Absatzhistorie trägt ~6      ← Wie viel?
Datenlage hoch                              ← Wie sicher?
```

Vier Zustände, jeder mit eigener Überschrift:

| Zustand | Überschrift |
| --- | --- |
| `PROVEN` | BESTE AKTION JETZT |
| Methode | BESTE AKTION JETZT (mit Median Gold/h) |
| `TEST` | MARKTTEST |
| nichts | DERZEIT KEINE ÜBERZEUGENDE AKTION |

Der vierte Zustand ist ausdrücklich ein **Ergebnis**, kein Fehler.

---

## 13. SavedVariables und Migration

Drei neue Speicher, alle je Realm und Fraktion (`GCP:Profile()`), alle mit
Formatversion, Obergrenze und Typprüfung in ihrer `EnsureStore`:

| Speicher | Inhalt | Aufbewahrung | Obergrenze |
| --- | --- | --- | --- |
| `income` | Goldzuflüsse mit Quelle und Confidence | 60 Tage | 2000 Ereignisse |
| `activity` | Sessions je Methode | 180 Tage | 200 Sessions |
| `demand` | nur Cache-Zeitstempel, **keine abgeleiteten Zahlen** | – | – |

`demand` speichert bewusst nichts Abgeleitetes: Evidence entsteht aus Ledger,
Market und Knowledge und wäre als Kopie sofort veraltet.

**Migration**: additiv. Kein bestehender Speicher ändert sein Format, keiner
wird gelöscht. Wer aktualisiert, hat Income- und Activity-Historie der Länge
null – und damit exakt den Kaltstart, für den die Test-Klasse gebaut ist.
Beschädigte Speicher werden wie bisher ersetzt statt weiterbenutzt.

---

## 14. Tests

Je Phase eine eigene Sektion, dazu die im Auftrag genannten Szenarien
vollständig. Die beiden Abnahmeprüfungen aus §37 werden als **Tests**
geschrieben, nicht als Behauptung im Bericht:

- Ein Craft ohne einen einzigen eigenen Verkauf darf **nie** `PROVEN` werden und
  **nie** mehr als die Testmenge empfehlen – auch bei beliebig hoher Marge,
  beliebig viel Kapital und beliebig gutem Angebot.
- Eine über mehrere Sessions belegte Service-Methode muss eine schwächere
  Item-Chance schlagen; eine schwach belegte darf es nicht.

---

## 15. Reihenfolge

| Phase | Inhalt |
| --- | --- |
| A | `Demand.lua` + `Actionability.lua` + Knowledge Demand Identity |
| B | `demandCapacity` in `Capital:SizePosition` |
| C | Resale-Semantik: echte Arbitrage gegen historische Unterbewertung |
| D | `Income.lua` – Ereignisse, Klassifikation, Kontextfenster |
| E | `Activity.lua` – Sessions, Enchanting Service, Slot-7-Erkennung |
| F | Methodenvergleich (Active Gold/h gegen Kapitaleffizienz) |
| G | `Recommendation.lua` + neue Startseite |
| H | Recency/Decay und Preisband-Nachfrage |

Nach jeder Phase: `npm test` grün, keine Regression, keine erfundene Zahl.
