# Changelog

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
