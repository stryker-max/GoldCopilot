# Changelog

## 1.0.0-beta.7 – 2026-08-11

### Behoben

- **Die Mengenwahl aus beta.6 lag auf der Routennotiz.** Der senkrechte Bauplan
  des Command Centers ist auf zwei Pixel genau ausgereizt (56 + 144 + 250 + 28 +
  28 + 4 × 14 = 562 von 564) – links war schlicht keine Zeile mehr frei, und die
  neue Knopfreihe endete vier Pixel unterhalb ihres Blocks. Sie sitzt jetzt in
  der rechten Knopfspalte unter „Guide anzeigen", wo 60 Pixel frei waren. Die
  Notizzeile bekommt dieselbe rechte Begrenzung wie Titel und Detail; ihr fehlte
  sie als einziger Zeile, weshalb sie unter die Knöpfe lief.

### Tests

- **Die Oberflächen-Attrappe schreibt jetzt Anker mit.** `SetPoint` wurde bisher
  verschluckt, damit war jede Aussage über Geometrie unmöglich – genau deshalb
  konnte diese Kollision überhaupt durchrutschen. Eine neue Prüfung rechnet die
  Ankerketten des Command Centers nach und meldet jedes Element, das aus seinem
  Block fällt. Gegenprobe mit dem alten Anker: *„amountReset bleibt im Block der
  besten Aktion (endet bei 148 von 144)"*. Die von Hand gepflegte Summe im
  Quelltext ist damit nicht mehr die einzige Absicherung.

## 1.0.0-beta.6 – 2026-08-11

**Du entscheidest die Menge.** Und zwei Knöpfe, die nur so aussahen, als täten
sie etwas, tun jetzt etwas.

### Behoben

- **„Neue Route" und „Aktualisieren" bewirkten sichtbar nichts.** Bei laufender
  Route lehnte „Neue Route" stillschweigend ab – mit einer Chatzeile, die man
  leicht übersieht, und einem Knopf, der aussah, als sei er kaputt. Jetzt fragt
  er einmal nach („Wirklich ersetzen?") und tut es dann. „Aktualisieren" konnte
  die gespeicherten Schritte ohnehin nie ändern; es plant jetzt den **Rest** der
  Route mit den frischen Preisen neu und behält das Erledigte. Findet sich kein
  besserer Plan, bleibt die Route stehen – und das steht dann auch in der
  Statuszeile, statt dass gar nichts passiert.
- **Die Goldbeträge der Dailys blieben ewig Schätzungen.** Der Client nennt den
  echten Betrag schon, während die Quest im Log liegt – das Addon las ihn beim
  Durchlauf und warf ihn weg. Gelernt wurde nur beim Abgeben. Wer eine Daily nie
  abgab, sah nie einen echten Wert: In den SavedVariables stand entsprechend
  gar nichts. Jetzt wird an drei Stellen gelernt – Questlog, Abgabedialog,
  Abgabe. Einmal annehmen genügt, danach steht kein „ca." mehr an der Zeile.

### Neu

- **Eigene Stückzahl.** Die Zentrale zeigt unter der besten Aktion eine
  Mengenwahl; Kapital, Potenzial und ROI rechnen live mit. Die Vorgabe schlägt
  Kapitalanteil und den Vorsichtsdeckel aus beta.3 – beides sind Vorsichtsregeln,
  und wer sie übergehen will, darf das. Sie schlägt ausdrücklich **nicht** die
  harten Grenzen: Was das freie Gold nicht hergibt, lässt sich auch auf Wunsch
  nicht kaufen, und was der Markt nicht anbietet, ebensowenig. Passt die Vorgabe
  nicht, steht daneben, woran es scheitert.
- Bewusst **vor** dem Start und nicht im laufenden Guide: Mitten in der Route
  wäre eine Mengenänderung ein Eingriff in einen Abhängigkeitsgraphen – kaufe
  20, stelle 10 her, verkaufe 10 – und würde die folgenden Schritte falsch
  machen, statt sie anzupassen.

## 1.0.0-beta.5 – 2026-08-11

**Der Guide sagt jetzt, wozu.** Bisher stand dort „Gehe zu: Auktionshaus" und
sonst nichts – nicht, was daraus wird, nicht, wo im Plan man steht.

### Behoben

- **Der Richtungspfeil war ein leeres Kästchen.** Er bestand aus Zeichen des
  Unicode-Blocks „Geometric Shapes" (▲ ◥ ▶ …), und `FRIZQT__.TTF` – die
  Standardschrift des Clients – enthält diesen Block nicht. Eine fehlende
  Glyphe meldet keinen Fehler, sie wird stillschweigend als Kästchen
  gezeichnet; im Quelltext sah alles richtig aus. Betroffen war auch der
  Zurück-Knopf aus beta.3. Jetzt reines ASCII, und `validate.mjs` lässt solche
  Zeichen in Anzeigetexten gar nicht mehr durch.
- **Wege wurden nur abgehakt, wenn das Ziel ein Fenster öffnet.** Wer schon am
  Auktionshaus stand und es nicht noch einmal anklickte, blieb auf „Gehe zu:
  Auktionshaus" stehen – mit „1 m" daneben im selben Fenster. Die Entfernung
  wird für den Pfeil ohnehin zweimal je Sekunde gerechnet und der Wegpunkt
  weiß selbst, ob er erreicht ist; genau das hakt den Schritt jetzt ab.
  Ausdrücklich nur Wege: Vor dem Auktionator zu stehen heißt nicht, gekauft zu
  haben.
- **„Guide anzeigen" zeigte nur an.** Der Knopf lässt die Route jetzt auch
  laufen – fortsetzen, wenn sie pausiert, planen und starten, wenn keine da
  ist. Zwei Knöpfe für einen Vorgang waren einer zu viel. Das Schließen bleibt
  reines Schließen.

### Neu

- **Das Vorhaben steht über der Handlung.** Statt nur „Gehe zu: Auktionshaus"
  jetzt „Hexerzwirnrobe · Teilschritt 2/5 · Vorhaben 1/3". Eine Route bündelt
  nach Ort, damit man nicht dreimal zum Auktionshaus läuft – dadurch liegen die
  Schritte zweier Crafts zwangsläufig ineinander, und dann muss an jedem
  Schritt stehen, wozu er gehört. Schritte ohne Vorhaben (Wege dazwischen)
  lassen die Zeile leer, statt eine Zugehörigkeit zu behaupten.
- **Das Item mit Tooltip.** Neben der Handlung steht das Symbol; wer darüber
  fährt, sieht den Tooltip des Clients. Bei Schritten ohne eigenes Item – etwa
  einem Weg – wird das Item des Vorhabens gezeigt. Shift-Klick fügt den Link in
  die Chateingabe ein.

## 1.0.0-beta.4 – 2026-08-11

**Ein Preis ist kein Angebot.** beta.3 hat geprüft, ob eine Zahl trägt. Diese
Fassung prüft die Frage davor: Lässt sich das überhaupt kaufen?

### Behoben

- **Routen kauften Dinge, die es nicht zu kaufen gibt.** Auctionator antwortet
  aus seiner gespeicherten Scandatenbank und liefert auch dann einen Preis,
  wenn seit Tagen keine einzige Auktion mehr gesehen wurde. So entstand
  „Teufelsstoffschultern kaufen“, obwohl keine einzige im Auktionshaus lag.
  Verglichen wird jetzt das Scanalter des Items mit dem eines Referenzguts,
  das in praktisch jedem Scan vorkommt (Netherstoff, wie schon im Tagesplan).
  Ist das Item deutlich älter, war es bei den letzten Scans nicht dabei – also
  liegt keines im Haus. Wurde dagegen insgesamt lange nicht gescannt, fällt
  gar kein Urteil: Ein hohes Alter hat zwei Ursachen, und nur der Vergleich
  trennt sie.
- **Beim Aufheben gebundene Reagenzien standen als Kaufschritt in der Route.**
  Eine Dämonische Rune kommt nie ins Auktionshaus – die wird gefarmt. Das
  Addon wusste das sogar (`IsAuctionable` prüft die Bindungsart seit 0.3),
  fragte aber nur auf der **Verkaufs**seite: „darf ich das einstellen?“ Für
  die Kaufseite gilt dieselbe Frage, und dort wiegt sie schwerer – ein Plan,
  der Ungekauftes einkauft, ist nicht ungenau, sondern unausführbar. Geprüft
  wird jede Zutat, nicht nur die erste: Ein Craft aus fünf Reagenzien
  scheitert an dem einen, das es nicht gibt, und welches das ist, entscheidet
  nicht seine Reihenfolge in der Liste.

### Neu

- **Chancen ablehnen: Alt + Rechtsklick** auf eine Zeile im Route- oder
  Chancen-Tab. Das Item verschwindet aus allen Chancen und aus jeder künftigen
  Route, „Neue Route“ plant dann ohne es. Das ist die eigentliche Antwort auf
  „der Guide schlägt immer dasselbe vor“: Ohne eine Möglichkeit abzulehnen hat
  der Planer bei unveränderter Datenlage auch keine andere Wahl. Nochmal
  Alt + Rechtsklick lässt das Item wieder zu; ein Knopf in den Optionen leert
  die ganze Liste.
- Abgelehnte Items sind **bewusst eine eigene Liste**, nicht die des
  Verkaufen-Tabs. Dort heißt „ignoriert“ *das behalte ich, schlag es mir nicht
  zum Verkauf vor* – hier heißt es *damit will ich gar nicht handeln*. Wer
  seine Manatränke behält, meint damit nicht, dass ihn ein Manatrank-Flip
  nicht interessiert.

### Tests

- Die Plausibilitätsregeln aus beta.3 haben jetzt Tests im Repo (`engine.lua`),
  nicht nur außerhalb. Dazu kommt eine Attrappe für ein beim Aufheben
  gebundenes Reagenz mit Marktpreis – genau die Falle, um die es geht: Der
  Preis ist da, die Ware nicht zu haben.

## 1.0.0-beta.3 – 2026-08-11

**Nicht jede richtige Rechnung ist ein guter Rat.** Diese Fassung nimmt dem
Addon drei Empfehlungen weg, die formal stimmten und praktisch unbrauchbar
waren, und gibt dem Guide die Knöpfe, die ihm gefehlt haben.

### Behoben

- **Eine einzelne überteuerte Auktion konnte eine ganze Route erfinden.** Die
  Preisquelle liefert den günstigsten Buyout des letzten Scans. Liegt genau
  eine Auktion im Haus, ist dieser Preis der Wunsch eines einzelnen
  Verkäufers – und der 7-Tage-Median half nicht, sondern schrieb denselben
  Wunsch siebenmal ab. So entstand „Einfache Leinenstiefel herstellen,
  +94 g, 105.841 % ROI“. Verkaufspreise werden jetzt gegen zwei Anker
  geprüft, die es wirklich gibt: die Materialkosten des Crafts (wer das
  Rezept hat, kann jederzeit unterbieten – bleibt die Konkurrenz aus, fehlt
  meist der Markt und nicht die Marge) und den Händlerpreis, aber
  ausdrücklich **nur bei Waffen und Rüstung**. Bei Rohstoffen ist er kein
  Anker, sondern Zufall: Adamantiterz bringt 25 Kupfer beim Händler und
  10 Gold im Auktionshaus – das Viertausendfache und der völlige Normalfall.
  Unter 5 Gold wird ohnehin nicht gezweifelt, und ein Item mit eigenem
  bestätigtem Verkauf oder mit mehreren Anbietern wird nie beanstandet, egal
  wie hoch sein Preis steht.
- **Routen kauften 26× dasselbe Item.** Kapitalanteil und Exposure begrenzen
  einen *Betrag*, keine *Menge*: Bei einem 2-Gold-Item sind 20 % des Kapitals
  eben 26 Stück. Ob der Markt 26 Stück aufnimmt, ist eine völlig andere Frage
  als ob das Gold reicht. Neu ist ein Stückzahl-Deckel – ohne eigene
  Verkaufsdaten 5 Stück, mit belegter Liquidität 20, in den Optionen frei
  einstellbar.
- **Das Symbol lag auf dem ersten Buchstaben des Itemnamens** in Verkaufen,
  Flips, Crafts, Markt, Zukunft und Handel. Der Chancen-Tab hängt das Symbol
  hinter die Score-Spalte um; der gemeinsame Zeilen-Pool nahm diesen Anker mit
  in jeden folgenden Tab. Er wird jetzt beim Zurücksetzen einer Zeile
  wiederhergestellt.
- **„Aktualisieren“ tat im Route-Tab nichts.** Der Routenvorschlag wurde
  einmal berechnet und danach nur noch angezeigt. Der Knopf verwirft ihn
  jetzt mit.
- **Der Route-Tab blieb für immer auf der fertigen Route stehen.** Er zählte
  nur die Schritte, nicht den Zustand – eine abgeschlossene Route galt damit
  als laufend, und es gab keinen Weg zu einer neuen. Die Zentrale hat diese
  Unterscheidung immer gemacht; jetzt macht der Route-Tab sie auch.

### Neu

- **Schritt zurück im Guide.** Ein automatisch gesetzter oder versehentlich
  übersprungener Haken lässt sich zurücknehmen. Zurückgenommen wird
  ausschließlich die Marke, nie die Handlung: Was gekauft wurde, bleibt
  gekauft, und das Handelsbuch bleibt unangetastet.
- **„Neue Route planen“** – als Knopf in der Werkzeugleiste des Route-Tabs und
  im Guide-Fenster an der Stelle, an der am Ende einer Route bisher eine Reihe
  wirkungsloser Knöpfe stand. Eine *laufende* Route wird dabei nie verworfen.
- **Zwei neue Optionen**: „Chancen: unbelegte Preise“ (voreingestellt: aus\-
  blenden) und „Stückzahl je Position“.

### Geändert

- Die Erklärung zum Mindest-ROI in den Optionen sagt jetzt, was ROI
  beantwortet – und was nicht.
- Ausgeblendete Fantasiepreise werden in der Statuszeile des Chancen-Tabs
  gezählt. Ein Filter, von dem niemand weiß, ist nicht besser als gar keiner.
- Das Guide-Fenster ist 20 Pixel breiter, damit der Schritt-zurück-Knopf mit
  in die Reihe passt.

## 1.0.0-beta.2 – 2026-08-10

**Aufgeräumte Oberfläche.** Diese Fassung ändert nichts an der Rechnung und
alles an den Abständen: Das Fenster war gedrängt, an einer Stelle lagen zwei
Ansichten übereinander.

### Behoben

- **Der Willkommensschirm lag im Bild statt davor.** Beim ersten Start standen
  Begrüßungstext, Kapitalkacheln und Zielmodus übereinander: Der Schirm ist
  ein gleichrangiger Frame, und gleichrangige Frames zeichnen ihre Schriften
  über jeden Hintergrund derselben Ebene. Er bekommt jetzt eine eigene, höhere
  Ebene, und die Blöcke dahinter werden weggeblendet.
- **Symbol und Itemname berührten sich** in allen Listen-Tabs. Zwischen
  Haken, Symbol und Text stehen jetzt feste Spalten mit echtem Abstand.
- **Die Knopfreihen des Zielmodus begannen an vier verschiedenen Stellen**,
  weil jede an der Breite ihrer eigenen Beschriftung hing („Aktivitäten“ ist
  länger als „Zeit“). Eine feste Beschriftungsspalte stellt sie untereinander.
- **Die Chancenmeldung des Guide-Fensters lag auf den Knöpfen**, sobald sie
  erschien. Sie sitzt jetzt in einem festen Kasten zwischen Sicherheit und
  Knopfreihe.
- **Der Zielstand im Guide-Fenster klebte am Minimieren-Knopf.**

### Geändert

- **Ein Layoutraster statt verstreuter Einzelwerte.** Alle Abstände kommen aus
  sechs Zahlen am Kopf von `UI.lua` (Fensterrand, Innenabstand, Abstand
  nebeneinander, Abstand untereinander, Beschriftung zu Inhalt, Zeilenabstand).
  Wer die Oberfläche enger oder luftiger will, dreht dort - nicht an
  zweihundert `SetPoint`-Aufrufen.
- **Fenster 1000 x 700 statt 960 x 640.** Elf Tabs und fünf Kapitalkacheln
  nebeneinander brauchen die Breite, das Command Center die Höhe. Passt
  weiterhin in die 768 Einheiten hohe Standardoberfläche.
- **Listenzeilen 30 statt 26 Pixel hoch**, Abschnittszeilen 38 statt 32, und
  zwischen zwei Zahlenspalten stehen 12 statt 10 Pixel.
- **Mehrzeilige Texte haben Zeilenabstand.** Er wird einmal in `createText`
  gesetzt und gilt damit überall.
- **Guide-Fenster 320 x 262 statt 280 x 190.** Die Knopfreihe „Warum ·
  Erledigt · Überspringen“ hat jetzt echte Abstände statt vier Pixel.
- **Kapitalkacheln und Schnellprofile füllen die Breite gleichmäßig aus**,
  statt fester Breiten mit einem angebrochenen Rest rechts.

### Wortlaut

- **„Mote“ und „Ur-Partikel“ heißen auf Deutsch anders.** Die zehn Kleinteile
  sind **Partikel** (Lebenspartikel, Erdpartikel …), das Ergebnis ist ein
  **Urelement** (Urleben, Urerde …). Flips-Tab, Tagesplan und die zugehörigen
  Erklärtexte sagen das jetzt auch so.

## 1.0.0-beta.1 – 2026-08-09

**Gold-Making-Navigation.** 0.5 beantwortet „wie steht der Preis relativ zur
eigenen Vergangenheit?", 0.6 „ist daraus eine Chance ableitbar?", 0.7 „welche
bekannten Veränderungen kommen?", 0.8 „wie schnell komme ich wieder heraus?" –
diese Fassung beantwortet zum ersten Mal die Frage, die am Anfang jeder Sitzung
steht: **„Was soll ich jetzt tun?"**

Du setzt ein Goldziel, ein Zeitbudget und eine Risikostufe. Gold Copilot macht
daraus eine Route aus konkreten Schritten und führt dich hindurch.

### Neue Module

- **`Capital.lua` – Capital Brain.** Kapitalsicht (frei, investiert, Reserve,
  Bestandswert, Einzahlungsrisiko), Positionsmodell mit ehrlicher Kostenbasis
  (nicht belegt = `nil`, nie 0), Exposure über Item, Chancenart, Catalyst,
  Phase und Marktgruppe, Position Sizing und ein Allocator, der Kapital
  **verteilt** statt alles auf den höchsten Score zu legen. Nie All-In: harter
  Deckel bei 35 % des investierbaren Kapitals je Position.
- **`Execution.lua` – Execution Engine.** Zerlegt eine Kapitalzuteilung in
  Aktionen (`GO_TO`, `BUY`, `CRAFT`, `CONVERT`, `DISENCHANT`, `POST_AUCTION`,
  `BANK_WITHDRAW`, `MAIL`, `FARM`, `WAIT`, `WATCH` …), gleicht dabei Taschen,
  Bank und Post ab, baut den Abhängigkeitsgraphen und prüft ihn auf fehlende
  Kanten, Doppelungen und Zyklen. Beim Entzaubern entsteht bewusst **kein**
  behauptetes Ergebnis-Item und kein erfundener Mindestpreis.
- **`Route.lua` – Route Planner.** Topologische Reihenfolge mit
  Ortsbündelung, nachträglich eingesetzte Wege, Kapital- und Zeitbudget, acht
  Profile (Schnelles Gold, Maximaler Gewinn, Geringes Risiko, Kapital aufbauen,
  Handel, Herstellen, Farmen, Zukunft) plus eigene Vorgaben, Gültigkeitsprüfung
  je Schritt und **Hysteresis**: Eine laufende Route wird nur ersetzt, wenn der
  neue Plan mindestens 12 % **und** 5 g besser ist.
- **`Guide.lua` – Guide Engine.** Zustandsautomat (IDLE, PLANNING, ACTIVE,
  WAITING, REPLANNING, COMPLETED, PAUSED), Schritte und Fortschritt in den
  SavedVariables (ein `/reload` mitten in der Route verliert nichts),
  automatische Erkennung nur dort, wo der Client eindeutig ist, sichtbarer
  Unterschied zwischen **erkannt** und **selbst abgehakt**, kaskadierendes
  Überspringen, gedrosseltes Replanning und Opportunity Interrupts
  (Auto-Insert voreingestellt **aus**).
- **`Navigation.lua`** lernt Orte aus den **eigenen Besuchen** des Spielers
  (Auktionshaus, Bank, Briefkasten, Berufsfenster, Händler), getrennt je Realm
  und Fraktion. Richtung immer, Entfernung nur mit Weltkoordinaten, TomTom
  optional. **Keine einzige geratene Koordinate.**
- **`Farm.lua` – Farm Brain.** Misst Farmsitzungen (Zone, Ausbeute, aktive
  Zeit) und leitet daraus persönliche Raten mit Median, Sitzungszahl und
  Sicherheitsgrad ab. **Keine Gold/h aus Guides**; ohne eigene Messung entsteht
  kein Farmblock. Adaptive Einschätzung gegen den eigenen Median samt
  Alternativvorschlag.
- **`Personal.lua` – Personal Brain.** Lernt lokal, welche Aktivitäten
  ausgeführt und welche übersprungen werden und womit tatsächlich verdient
  wird. Aussagen erst ab Mindeststichprobe, sonst gar keine.
- **`Analytics.lua`** wertet das Chancen-Protokoll nach Chancenart,
  Score-Band, Market Score, Future Demand, Hype, Liquidität und Confidence aus –
  immer mit `n` und mit **LOW SAMPLE**, wo die Stichprobe zu dünn ist.
- **`Calibration.lua`** zieht die Gewichte vorsichtig an eigenen Ergebnissen
  nach: Bayes'sches Schrumpfen Richtung Standardmodell, harte Grenzen ×0,75 bis
  ×1,25, höchstens ×0,05 je Durchlauf, mindestens 40 Ergebnisse insgesamt und
  15 je Chancenart, versioniert, jederzeit rücksetzbar, voreingestellt aus.
  **Keine KI, keine Blackbox.**
- **`Knowledge/Locations.lua`** und **`Knowledge/FarmRoutes.lua`** bringen
  Schema und Prüfung mit; der kuratierte Teil ist **absichtlich leer**. Eine
  geratene Koordinate schickt den Spieler aktiv in die falsche Richtung.

### Markttiefe

`Market.lua` kennt jetzt Mengen, nicht nur Preise: verfügbare Stückzahl,
Angebotszahl, Preisstufen und die Tiefe nahe am Marktpreis – erfasst
ausschließlich aus der Auktionsliste, die der Spieler selbst durchblättert.
Jede Aussage trägt ihr Alter und ist ausdrücklich eine **Untergrenze**.

Marktstruktur-Signale beschreiben, statt zu unterstellen: `THIN_MARKET`,
`SUPPLY_SHOCK`, `PRICE_WALL`, `PRICE_OUTLIER`, `UNUSUAL_LISTING_CONCENTRATION`.
Nirgends steht „Manipulation" – warum jemand so anbietet, weiß niemand.

Die Chancen-Engine nutzt die Tiefe für zwei Dinge, die sie belegen kann: eine
Obergrenze der sinnvollen Stückzahl und den Hinweis „Preis günstig, aber
ungewöhnlich hohes Angebot". Der Opportunity Score bleibt unverändert.

### Oberfläche

- **Neuer Tab „Zentrale"** als Startseite: Gold, frei verfügbar, investiert,
  heute realisiert, offenes Potenzial – darunter die beste Aktion jetzt mit
  einem Knopf, der Zielmodus (Goldziel per Knopf oder eigenem Feld, Zeit,
  Risiko, Aktivitäten) und sechs Schnellprofile.
- **Neuer Tab „Route"**: Übersicht vor dem Start (Schritte, aktive Zeit,
  Kapitalbedarf, Potenzial, Sicherheit, Zielrealismus, Inhalt) und die laufende
  Route mit Haken, Etiketten und Begründung je Schritt.
- **Guide Viewer** als eigenes, verschiebbares, skalierbares und minimierbares
  Fenster mit Richtungsglyphe, Entfernung und den Knöpfen Warum, Erledigt,
  Überspringen, Pause und Abbrechen. Position und Größe werden gespeichert.
- **Erster Start** zeigt einen Willkommenstext statt einer Wand aus Nullen.
- Optionen für Guide-Fenster, Pfeil, Auto-Insert, TomTom, Cash-Reserve und
  Kalibrierung; die Datenübersicht nennt jetzt auch Markttiefe, gelernte Orte,
  Farmhistorie und persönliche Statistik.
- Die bestehenden neun Tabs bleiben unverändert – sie sind der Expertenmodus.

### Realm- und Fraktionstrennung

`GoldCopilotDB` ist accountweit – für Optionen und Goldverlauf richtig, für
Marktdaten falsch. Ab jetzt bekommt jede Kombination aus Realm und Fraktion
ihren eigenen Speicher (`db.profiles`), und die vorhandenen Daten wandern
**einmalig** dorthin: verschoben, nicht kopiert. Betroffen sind Markthistorie,
Markttiefe, Preisverlauf, Beobachtungsliste, Handelsbilanz, Chancen-Protokoll,
Kapital, Farmhistorie, persönliche Statistik, Kalibrierung und Guide-Zustand.

### Diagnose

- `/gold diagnostics` mit Version, Speicherständen, Positionen, Route,
  Cache-Revisionen, Wissensprüfung und erkannten optionalen Addons.
- `/gold debug <bereich>` für zehn Bereiche, nur mit eingeschaltetem Debug.
- `/gold route`, `start`, `pause`, `stop`, `guide`, `warum`, `ziel`, `zeit`,
  `farm`, `hilfe`.
- Prüfung der Wissensbasis auf **Beziehungen**: Catalysts ohne bekanntes Item,
  Rezeptkanten ins Leere, Zyklen im Abhängigkeitsgraphen, exakte Termine ohne
  offizielle Quelle, verwaiste Items. Die ausgelieferte Wissensbasis ist sauber.

### Tests

Von 1.383 auf **2.453 Zusicherungen** in vier Dateien:

- `tests/harness.lua` – gemeinsame, während des Tests veränderbare
  WoW-Attrappe samt Simulationsbausteinen.
- `tests/engine.lua` – 648 Zusicherungen zur Entscheidungsschicht.
- `tests/simulation.lua` – **18 vollständige End-to-End-Sitzungen** plus
  Invarianten, die über hunderte erzeugte Eingaben gelten statt an einem
  Beispiel.

### Dokumentation

README neu geschrieben und auf die Kernbotschaft gebracht; die technischen
Details liegen jetzt in `docs/ARCHITECTURE.md`, `docs/MODELS.md`,
`docs/DATA.md`, `docs/TESTING.md` und `docs/INGAME_TEST.md`.

## 0.8.0 – 2026-08-09

Liquidity Brain. 0.5.0 beantwortet „wie steht der Preis relativ zur eigenen
Vergangenheit?“, 0.6.0 „ist daraus eine Chance ableitbar?“, 0.7.0 „welche
bekannten Veränderungen kommen?“ – 0.8.0 beantwortet zum ersten Mal:
**„Verkaufe ich dieses Item überhaupt, wie schnell bekomme ich mein Gold
zurück, und welche Chance vermehrt mein Kapital am schnellsten?“**

- **Neues Modul `Ledger.lua`** – eine kleine persönliche Handelsbilanz mit
  `RecordPurchase`, `RecordSale`, `RecordAuctionPosted`, `RecordAuctionExpired`,
  `RecordAuctionCancelled`, `GetItemStats`, `GetGlobalStats`, `GetRecentTrades`,
  `GetLiquidity`, `ComputeLiquidityScore` und `ProfitVelocity`. Ausdrücklich
  **kein zweiter TSM-Ledger**: Aufgeschrieben wird nur, was eine Empfehlung
  verbessert, nicht jeder Kupfertransfer.
- **Datenquellen zuerst geprüft, dann selbst gebaut.** Auctionator
  (`Auctionator.API.v1`) liefert Preise, Scan-Alter, Entzauberwerte und einen
  DB-Update-Callback – keine Verkaufshistorie. Syndicator kennt Bestände, aber
  keine Ereignisse. TSM veröffentlicht nur `GetCustomPriceValue`.
  **Journalator** protokolliert genau diese Vorgänge, hat aber **keine
  dokumentierte öffentliche API**, und seine Fassungen zielen auf Retail,
  Season of Mastery und Wrath, nicht auf TBC Anniversary – an interne Tabellen
  anzudocken hieße, sich an etwas zu hängen, das sich jederzeit ändern darf.
  Entscheidung: **keine Kopplung.** Der Einstiegspunkt `CaptureFromExternal()`
  steht bereit, falls sich das ändert.
- **Eigene Erfassung über zwei belastbare Client-Wege**: `PostAuction` per
  `hooksecurefunc` (Item aus dem Verkaufsplatz, Stückzahl, Stückpreis, Laufzeit,
  Einstellgebühr aus `CalculateAuctionDeposit`) und der Briefkasten
  (`GetInboxInvoiceInfo` für Verkaufs- und Kaufrechnungen,
  `AUCTION_EXPIRED_MAIL_SUBJECT` / `AUCTION_REMOVED_MAIL_SUBJECT` für Ablauf
  und Abbruch, Item und Stückzahl aus dem Anhang). Jede optionale Integration
  läuft über Laufzeitprüfung und `pcall`; fehlt etwas, gibt es keinen Lua-Fehler
  und keine Zahl.
- **Nur bestätigte AH-Vorgänge.** Händlerverkäufe, Handel, Post von
  Mitspielern, Crafts, Entzaubern und zerstörte Stapel werden **nie** zu einem
  Auktionsverkauf umgedeutet. Aus Goldänderungen wird grundsätzlich nichts
  abgeleitet.
- **Sell-through stückzahlbasiert**: `verkaufteStückzahl / (verkaufte +
  abgelaufene)`. 100 eingestellt, 60 verkauft, 40 abgelaufen sind 60 % – nicht
  50 %, nur weil es eine Verkaufs- und eine Ablaufmeldung gab.
  **Zurückgezogene Auktionen zählen in keinem der beiden Summanden** – ein
  Abbruch ist eine Entscheidung des Spielers, kein Urteil des Marktes. Daneben
  `sellThroughAuctions` als Rate je Auktion. Konnte auch nur ein Verkauf keiner
  Einstellung zugeordnet werden, gibt es **keine** stückzahlbasierte Rate: Sie
  wäre zu niedrig, und das ist genau die Falschaussage, die hier nicht
  passieren soll.
- **Median Time To Sale** aus der realen Spanne Einstellung → Verkaufsrechnung,
  zweimal gespeichert: `medianHours` von der letzten Einstellung (exakt) und
  `medianHoldHours` über Neu-Einstellungen hinweg (Fenster 48 h, für die
  Kapitalbindung). Median statt Durchschnitt, dazu p25 und p75. **Ohne
  Zuordnung `nil`** – kein Schätzwert, keine Auktionsdauer als Ersatz.
- **Liquidity Score 0–100** ausschließlich aus eigenen Verkäufen:
  `55 × min(sellThrough/0,9 ; 1) + 30 × 24/(24+medianHours) + 15 × v/(v+3)`.
  Fehlende Bausteine werden über ihr Gewicht **herausgerechnet**, nicht mit 0
  bestraft. Ohne Sell-through-Rate gibt es **gar keinen Score, sondern `nil`** –
  nicht 50. Die Confidence deckelt hart (niedrig ≤ 55, mittel ≤ 80).
  **Volatilität fließt nicht ein – sie ist keine Liquidität.**
- **Profit Velocity**: `expectedProfit × sellThrough / kapital /
  max(holdingHours; 2 h) × 24`, ausgegeben als **Gewinn je 100 g gebundenem
  Kapital und Tag**. Die Sell-through-Rate steht im Zähler und nicht in der
  Zeit, damit dasselbe Risiko nicht zweimal zählt; die Mindesthaltedauer
  verhindert die Divisionsexplosion. Ohne Sell-through oder gemessene
  Haltedauer: `nil`.
- **Persönliche Preise**: `averageBuyPrice`, `medianBuyPrice`,
  `averageSellPrice`, `medianSellPrice` – alle nach Stückzahl gewichtet – und
  daraus die **realisierte Marge**.
- **Realisierter Gewinn** mit gewichtetem Durchschnittspreis als Kostenbasis
  (eine FIFO-/LIFO-Buchhaltung gibt die Datenlage nicht her). Verlorene
  Einstellgebühren werden abgezogen, die AH-Gebühr genau einmal – mit dem
  Betrag aus der Rechnung, sonst mit dem bekannten Satz aus `Constants.lua`.
  **Selbst gefarmte oder gecraftete Ware bekommt keine Kostenbasis 0**: Deckt
  der Einkauf die verkaufte Stückzahl nicht, gibt es `nil` und die Angabe, wie
  weit die Kostenbasis trägt.
- **Die in 0.6/0.7 vorbereiteten Felder sind jetzt gefüllt** – `liquidity`,
  `sellThrough`, `expectedHours`, `profitVelocity`, `liquidityScore` –, aber
  nur bei echten Daten. Ohne eigene Verkäufe bleiben sie `nil`, und die
  Oberfläche schreibt „Liquidität unbekannt“.
- **Opportunity Score erweitert, nicht ersetzt**: ein Zuschlag von ±15 Punkten,
  gewichtet nach Datenlage (0 / 0,25 / 0,65 / 1,0). **Ohne Daten ist er exakt
  0** – eine 0.6-Bewertung bleibt Punkt für Punkt dieselbe. Zwei Auktionen
  verschieben höchstens 3,75 Punkte. Der Zuschlag wirkt vor dem
  Confidence-Deckel: Abschläge ziehen immer, Zuschläge nur so weit, wie die
  Preisdaten sie tragen.
- **Future Market**: Der **Future Demand Score bleibt unverändert** – er ist
  Spielwissen. Nur das Investment Signal färbt sich um bis zu ±8 Punkte ein,
  und das erst ab mittlerer Datenlage; darunter passiert gar nichts.
- **Neuer Tab „Handel“** mit 7- und 30-Tage-Kopf (Umsatz, realisierter Gewinn,
  Sell-through, mediane Verkaufszeit) und einer Tabelle je Item: verkauft,
  abgelaufen, Sell-through, Zeit, realisierte Marge, Liquidity Score.
  Sortierbar nach Liquidität, realisiertem Gewinn und Verkäufen. Kaltstart mit
  klarer Ansage statt leerer Tabelle.
- **Chancen-Tab**: neue Liquiditätsspalte, erweiterter Tooltip („DEINE
  VERKAUFSDATEN“ und „PROFIT VELOCITY“) und fünf Sortiermodi. Standard bleibt
  der Opportunity Score – die Liquidität steckt in ihm drin, deshalb gibt es
  bewusst keine automatische Umschaltung, die ständig springt.
- **Prediction Tracking**: `db.opportunityHistory` bekommt `executedAt`,
  `entryPrice`, `soldAt`, `exitPrice`, `holdingHours`, `realizedProfit` und
  `outcome` (WIN / LOSS / OPEN / UNKNOWN) – aber nur bei eindeutiger Zuordnung.
  Ein Kauf gehört zu genau einem Eintrag, das Fenster beträgt drei Tage, und
  ein gesetztes Ergebnis wird **nie** überschrieben. **0.8 wertet daraus noch
  nichts aus und passt keine Gewichte an** – es legt nur die Daten sauber ab,
  damit 0.9 es kann.
- **Speicherstrategie**: 60 Tage Rohereignisse als flache Zahlenliste mit
  Schrittweite 8 (max. 4000) plus dauerhafte Aggregate je Item (max. 400
  Items, je 60 Stichproben). Die Verkaufsdauer steht auch am einzelnen
  Ereignis, damit die 7- und 30-Tage-Ansicht einen Median rechnet, der
  wirklich zu ihrem Zeitraum gehört. Die Aggregate überleben das Aufräumen –
  sie sind das Langzeitgedächtnis. Aufgeräumt wird beim Login und danach höchstens
  stündlich, nie im `OnUpdate`. Aggregate werden inkrementell fortgeschrieben,
  Fensterstatistiken an einer Revision gecacht.
- **Alle Handelsdaten bleiben lokal.** Kein Upload, keine Telemetrie, kein
  Abgleich mit irgendeinem Dienst – im README ausdrücklich vermerkt.
- **Neue Slash-Befehle**: `/gold handel`, `/gold ledgerstats`,
  `/gold ledgerreset confirm` (zweistufig wie der Marktreset).
- **Rückwärtskompatibel**: `db.ledger` legt sich leer an, ersetzt nichts und
  verwirft bei unbekannter Formatversion ausschließlich sich selbst. Eine
  Datenbank aus 0.3 bis 0.7 bleibt vollständig.
- **Tests**: 1.383 Assertions (vorher 1.143), davon rund 240 neue für Ledger,
  Sell-through, Time-to-Sale, Liquidity Score, Profit Velocity, persönliche
  Preise, realisierten Gewinn, Retention und Deckel, Briefkasten-Abgleich samt
  Doppeltzählungsschutz, Opportunity- und Future-Integration, Handel-Tab und
  Ergebniszuordnung im Chancen-Protokoll. Ausdrücklich mitgeprüft: Post von
  einem Mitspieler erzeugt keinen einzigen Handelsvorgang, eine Entzauber-Chance
  übernimmt nie die Liquidität des gekauften Items, und ohne Handelsbilanz
  rechnet der Opportunity Score exakt wie in 0.6.

## 0.7.0 – 2026-08-09

Future Market. 0.5.0 beantwortet „wie steht der Preis relativ zur eigenen
Vergangenheit?“, 0.6.0 „ist daraus gerade eine Gold-Chance ableitbar?“ – 0.7.0
beantwortet zum ersten Mal: **„Welche bereits bekannten Veränderungen im Spiel
könnten die Nachfrage nach diesem Item verändern?“**

- **Neue Wissensbasis `Knowledge/`**, strikt getrennt von jeder Rechenlogik:
  `Knowledge.lua` (Register, Prüfung, Nachschlagen), `Phases.lua` (Phasen),
  `Items.lua` (43 geprüfte Items), `Recipes.lua` (Rezeptkanten),
  `Catalysts.lua` (26 Catalysts). Sie wird mit dem Addon ausgeliefert – ein
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
- **Tests**: 1.143 Zusicherungen (vorher 851). Neu geprüft werden Phasenzustand
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
