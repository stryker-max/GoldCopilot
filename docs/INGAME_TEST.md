# Ingame-Testcheckliste

Diese Liste ist die Gegenprobe zu den 2453 automatischen Zusicherungen. Die
laufen gegen eine Attrappe; hier geht es um das, was nur der echte Client
zeigen kann.

Vorbereitung: Ordner nach
`World of Warcraft\_anniversary_\Interface\AddOns\GoldCopilot` kopieren
(nur `GoldCopilot.toc`, `*.lua`, `Knowledge/`, `Media/`, `README.md` – **nicht**
`tests/`, `docs/`, `node_modules/`, `.git/`, `package.json`).

---

## A. Start und Grundfunktion

- [ ] **A1** Addon lädt ohne Lua-Fehler. Vorher `/console scriptErrors 1`
      setzen, damit Fehler auch wirklich angezeigt werden.
- [ ] **A2** `/gold` öffnet das Fenster. Es steht die Zentrale vorn.
- [ ] **A3** Beim allerersten Start steht dort der Willkommenstext, nicht eine
      Wand aus Nullen. `[Los geht's]` blendet ihn dauerhaft aus.
- [ ] **A4** `/gold hilfe` listet die Befehle.
- [ ] **A5** `/gold diagnostics` gibt eine kompakte Diagnose aus. Prüfen:
      Version `1.0.0-beta.1`, Realm/Fraktion korrekt, Auctionator erkannt.
- [ ] **A6** ESC schließt das Fenster.
- [ ] **A7** `/reload` – Fenster lässt sich danach wieder öffnen, keine Fehler.

## B. Kaltstart (frischer Realm, noch keine Daten)

- [ ] **B1** Zentrale zeigt Goldstand und „frei verfügbar", bei allem anderen
      Sätze statt Nullen („noch nichts", „keine Chance").
- [ ] **B2** `[GOLD ROUTE ERSTELLEN]` sagt, dass es nichts zu planen gibt –
      und warum.
- [ ] **B3** Jeder Tab lässt sich öffnen, ohne Fehler und ohne leere Tabellen
      ohne Erklärung.

## C. Preisdaten

- [ ] **C1** Im Auktionshaus einen vollständigen Auctionator-Scan ausführen.
- [ ] **C2** `/gold marketstats` – Snapshots > 0, Auctionator-Callback „aktiv".
- [ ] **C3** Markt-Tab zeigt Zeilen mit Score, Perzentil und Confidence.
- [ ] **C4** Nach mehreren Tagen: Confidence steigt von „niedrig" auf „mittel".

## D. Markttiefe (neu)

- [ ] **D1** Im Auktionshaus **ein einzelnes Item suchen** (z. B. Urfeuer).
- [ ] **D2** Fenster schließen, `/gold debug on`, `/gold debug market` –
      unter „Markttiefe" steht mindestens 1 Item.
- [ ] **D3** Im Chancen-Tab im Tooltip dieses Items steht der Block
      **ANGEBOTSLAGE** mit „mindestens N Stück in M Angebot(en)" und dem Alter.
- [ ] **D4** Ein Item mit sehr wenigen Angeboten suchen → „sehr dünner Markt".
- [ ] **D5** Nirgends taucht das Wort „Manipulation" auf.

## E. Zentrale und Zielmodus

- [ ] **E1** Goldziel wählen (Knopf oder eigenes Feld + Enter). Der gewählte
      Knopf ist markiert.
- [ ] **E2** Zeit und Risiko wählen – ebenfalls markiert.
- [ ] **E3** Aktivitäten an-/abschalten. Abgeschaltete Arten tauchen in der
      Route nicht mehr auf.
- [ ] **E4** Unter dem Zielmodus steht das erkannte Kapital samt Reserve.
- [ ] **E5** „BESTE AKTION JETZT" nennt eine konkrete Aktion mit Kapital,
      Potenzial und ROI – oder sagt, dass es gerade keine gibt.

## F. Route planen

- [ ] **F1** `[GOLD ROUTE ERSTELLEN]` wechselt in den Routen-Tab.
- [ ] **F2** Kopfzeile „GOLD ROUTE READY" mit Schrittzahl, aktiver Zeit,
      Kapitalbedarf, Potenzial und Sicherheit.
- [ ] **F3** Bei unerreichbarem Ziel steht **nicht** die Wunschzahl, sondern
      „Mit den aktuell bekannten Chancen liegt das geschätzte Potenzial bei …".
- [ ] **F4** Die Schrittliste beginnt mit einem Weg und enthält Kaufen,
      Herstellen/Umwandeln und Einstellen in sinnvoller Reihenfolge.
- [ ] **F5** Kapitalbedarf der Route ≤ frei verfügbares Gold.
- [ ] **F6** Zeitbudget 30 Minuten ergibt eine kürzere Route als 2 Stunden.
- [ ] **F7** Alle acht Profile durchklicken (`/gold route quick_gold` usw.) –
      keines wirft einen Fehler.

## G. Guide Viewer

- [ ] **G1** `[ROUTE STARTEN]` – das kleine Guide-Fenster erscheint.
- [ ] **G2** Es zeigt „Schritt 1 / N" und die erste Anweisung.
- [ ] **G3** Verschieben per Drag. `/reload` – **Position bleibt erhalten**.
- [ ] **G4** `–` minimiert (nur Kopfzeile bleibt), erneut klicken klappt auf.
- [ ] **G5** `[Warum?]` gibt im Chat die vollständige Begründung aus.
- [ ] **G6** `[Erledigt]` schließt den Schritt ab, `[Überspringen]` überspringt
      ihn – und alles, was darauf aufbaut, verschwindet mit.
- [ ] **G7** `[Pause]` hält an; solange pausiert ist, hakt **nichts**
      automatisch ab. `[Weiter]` setzt fort.
- [ ] **G8** `[Route abbrechen]` beendet sie, das Fenster verschwindet.
- [ ] **G9** `/gold guide` blendet das Fenster ein und aus.

## H. Automatische Erkennung

- [ ] **H1** Schritt „Gehe zum Auktionshaus": Auktionshaus öffnen → Haken
      erscheint von selbst, in der Routenliste steht das Etikett **erkannt**.
- [ ] **H2** Schritt „Kaufe N× X": das Item im AH kaufen, Briefkasten öffnen →
      Schritt schließt sich (Ledger-Beleg).
- [ ] **H3** Schritt „Gehe zur Bank": Bank öffnen → Haken.
- [ ] **H4** Schritt „Herstellen": herstellen → Haken über den Bestandszuwachs.
- [ ] **H5** Schritt „Einstellen": Auktion einstellen → Haken.
- [ ] **H6** Ein von Hand abgehakter Schritt trägt **erledigt**, nicht
      **erkannt**. Der Unterschied muss sichtbar sein.

## I. Navigation und Pfeil

- [ ] **I1** Vor dem ersten Besuch: Schritt „Gehe zum Auktionshaus" zeigt
      **keinen** Pfeil, sondern den Satz „Gold Copilot kennt diesen Ort noch
      nicht – einmal hingehen genügt".
- [ ] **I2** Auktionshaus einmal öffnen, Route neu starten → jetzt erscheint
      eine Richtungsglyphe und eine Entfernung.
- [ ] **I3** Auf der Stelle drehen: Die Glyphe dreht sich mit. Nach Norden
      blickend zeigt ein nördliches Ziel „vorwärts".
- [ ] **I4** Zum Ziel laufen: Die Entfernung sinkt.
- [ ] **I5** Auf einer anderen Karte (andere Zone) steht „andere Karte" statt
      einer falschen Richtung.
- [ ] **I6** In den Optionen „Richtungspfeil" abschalten → Glyphe verschwindet,
      alles andere bleibt.
- [ ] **I7** Mit installiertem TomTom: Option „TomTom-Wegpunkte" einschalten →
      es entsteht ein TomTom-Wegpunkt. Ohne TomTom: keine Fehlermeldung.

## J. Dynamische Neuplanung

- [ ] **J1** Route starten, die einen Kauf enthält.
- [ ] **J2** Warten, bis sich der Marktpreis dieses Items deutlich über die
      angezeigte Obergrenze bewegt hat (oder das AH erneut scannen, nachdem
      jemand die günstigen Angebote weggekauft hat).
- [ ] **J3** Auktionshaus öffnen → Gold Copilot erkennt die Ungültigkeit und
      plant neu.
- [ ] **J4** **Wichtig:** Bereits erledigte Schritte bleiben erledigt.
- [ ] **J5** Die Route springt **nicht** bei jeder kleinen Preisbewegung um.
      Mehrfach das AH öffnen und schließen – die Reihenfolge bleibt stabil.
- [ ] **J6** `/gold debug route` zeigt den aktuellen Plan.

## K. Opportunity Interrupts

- [ ] **K1** Während einer laufenden Route das AH scannen, wenn gerade ein
      auffällig günstiges Angebot vorliegt.
- [ ] **K2** Im Guide-Fenster erscheint „NEUE CHANCE: …".
- [ ] **K3** Ohne Zutun wird **nichts** eingefügt (Auto-Insert ist aus).
- [ ] **K4** Option „Chancen automatisch einfügen" einschalten → beim nächsten
      Mal wird sie eingefügt und die Route wird länger.

## L. Kapital, Positionen, Exposure

- [ ] **L1** Mehrere Auktionen einstellen → Zentrale zeigt „Investiert".
- [ ] **L2** `/gold debug capital` listet die Positionen mit Einstand und Wert.
- [ ] **L3** Ein Item, das nie gekauft, sondern selbst gefarmt wurde, zeigt
      Einstand **UNKNOWN** – nicht 0.
- [ ] **L4** Sehr viel Kapital in ein Item legen → Exposure-Warnung erscheint.
- [ ] **L5** Cash-Reserve in den Optionen umstellen → „frei verfügbar" ändert
      sich sofort, und die Route verplant die Reserve nie.

## M. Farmen

- [ ] **M1** In der Zentrale das Farmprofil wählen. Ohne eigene Sitzungen
      entsteht **kein** Farmblock.
- [ ] **M2** `/gold farm` sagt, dass es noch keine Farmhistorie gibt.
- [ ] **M3** *(sobald die Farm-Oberfläche genutzt wird)* Nach mehreren
      Sitzungen zeigt `/gold farm` einen Median mit Sitzungszahl und
      Sicherheitsstufe.
- [ ] **M4** Nirgends steht eine Gold/h-Angabe, die nicht aus eigenen
      Sitzungen stammt.

## N. Handel und Ergebnisse

- [ ] **N1** Auktion einstellen → Handel-Tab zeigt eine offene Einstellung.
- [ ] **N2** Auktion verkauft, Briefkasten öffnen → Verkauf erfasst,
      Sell-through und Verkaufsdauer entstehen.
- [ ] **N3** Auktion abgelaufen → als Ablauf gezählt, **nicht** als Abbruch.
- [ ] **N4** Auktion zurückgezogen → als Abbruch gezählt, verändert die
      Sell-through **nicht**.
- [ ] **N5** `/gold ledgerstats` zeigt Einstell-Hook „aktiv" und den
      Briefkasten-Abgleich.
- [ ] **N6** Nach einigen Wochen: `/gold debug personal` zeigt Trefferquoten
      mit `n=` und LOW SAMPLE, wo die Stichprobe dünn ist.

## O. Kalibrierung

- [ ] **O1** In den Optionen steht „Modell: STANDARD".
- [ ] **O2** „Persönliche Kalibrierung" einschalten, bevor 40 Ergebnisse
      vorliegen → es bleibt beim Standardmodell, mit Begründung.
- [ ] **O3** Nach genügend Ergebnissen: Faktoren erscheinen, alle zwischen
      ×0,75 und ×1,25.
- [ ] **O4** „Zurücksetzen" stellt den Standard wieder her.

## P. Mehrere Charaktere und Realms

- [ ] **P1** Zweiten Charakter **derselben Fraktion und desselben Realms**
      einloggen → Marktdaten und Handelsbilanz sind da.
- [ ] **P2** Charakter der **anderen Fraktion** einloggen → eigener,
      zunächst leerer Speicher. Der erste bleibt unberührt.
- [ ] **P3** Charakter auf einem **anderen Realm** → ebenfalls eigener
      Speicher.
- [ ] **P4** Zurück auf den ersten Charakter → alle Daten unverändert da.
- [ ] **P5** `/gold diagnostics` zeigt unter „Profile" die richtige Anzahl.
- [ ] **P6** Optionen und Goldverlauf sind auf allen Charakteren gleich.

## Q. Ohne optionale Addons

- [ ] **Q1** Auctionator deaktivieren → Addon lädt, keine Fehler.
- [ ] **Q2** Es steht ausdrücklich da, dass keine Preisquelle vorhanden ist.
- [ ] **Q3** Syndicator deaktivieren → Bestand kommt aus den eigenen Taschen,
      Bank und Post fehlen, und das steht auch dran.
- [ ] **Q4** TomTom deaktivieren → eigener Pfeil, keine Fehlermeldung.

## R. Robustheit

- [ ] **R1** `/reload` mitten in einer Route → Fortschritt vollständig da,
      Route steht auf **pausiert**.
- [ ] **R2** Ausloggen und wieder einloggen → dasselbe.
- [ ] **R3** Im Kampf das Fenster offen lassen → keine Ruckler, keine Fehler.
- [ ] **R4** Vollen Auctionator-Scan mit offenem Gold-Copilot-Fenster →
      kein spürbares Einfrieren.
- [ ] **R5** Fenster bei 1280×720 und bei UI-Skalierung 0,64 öffnen → nichts
      ist abgeschnitten, alle elf Tabs passen in die Leiste.

## S. Was bewusst nicht passieren darf

- [ ] **S1** Nirgends steht „KAUFEN" als Zusage.
- [ ] **S2** Nirgends steht eine Liquidität, Farmrate oder Kostenbasis, die
      nicht aus eigenen Daten stammt.
- [ ] **S3** Kein Pfeil zu einem Ort, den du nie besucht hast.
- [ ] **S4** Keine Zahl, wo „unbekannt" richtig wäre.
- [ ] **S5** Gold Copilot kauft, verkauft und bewegt nichts von selbst.

---

## Wenn etwas schiefgeht

1. `/console scriptErrors 1` und den vollständigen Fehlertext notieren.
2. `/gold diagnostics` – die Ausgabe gehört in jeden Fehlerbericht.
3. `/gold debug on` und den passenden Bereich (`market`, `route`, `guide`,
   `capital`, `ledger`, `execution`, `farm`, `personal`, `opportunity`,
   `future`).
4. Beides zusammen mit dem Schritt, bei dem es passiert ist, an das Repository.
