# Changelog

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
