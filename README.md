# Gold Copilot 0.4.0

<p align="center"><img src="Media/Wordmark.png" alt="Gold Copilot" width="360"></p>

Dein Gold-Berater für **World of Warcraft: Burning Crusade Classic Anniversary** –
ein Standalone-Addon, das jeden Tag konkret sagt, was sich lohnt. Keine
Rohdaten-Tabellen: ein Tagesplan wie ein Daily-Quest-Log, der sich selbst
abhakt, wenn du die Dinge erledigst.

## Die fünf Tabs

1. **Heute** – die Gold-Roadmap. Neu mit jedem **WoW-Daily-Reset** (nicht um
   lokale Mitternacht), zum Abhaken, mit Fortschrittsbalken, Goldsumme je
   Kategorie und automatischer Erledigt-Erkennung:
   - **Tagesziel**: Sag dem Addon, wie viel Gold du heute willst – es zeigt
     dir den **schnellsten Weg dorthin**, also die offenen Aufgaben nach
     Gold je Minute sortiert und als „Plan 1, 2, 3 …“ nummeriert, samt
     Zeitschätzung.
   - **Daily-Quests**: Ogri'la & Himmelswache, Dungeon-Daily normal und
     heroisch, Kochkunst- und Angel-Daily – nur die, die dein Charakter nach
     Level, Beruf, Skillstand und Freischaltungskette wirklich annehmen kann
     (mit Questie sogar dessen eigene Prüfung). Abgegebene erkennt das Addon
     am Quest-Flag von selbst, und den **echten Goldbetrag lernt es beim
     ersten Abgeben** – bis dahin steht „ca.“ an der Zeile.
   - **Quests abgeben**: abgabebereite Quests aus deinem Log mit dem Wert
     ihrer Belohnung – Gold plus Items, jedes zum **besseren von AH netto und
     Händlerpreis**; bei Auswahlbelohnungen zählt nur die beste.
   - **Cooldowns & Crafts**: Transmutationen, Mondstoff & Co. mit
     Gewinnrechnung und Restzeit – benutzt du den Cooldown, hakt sich der
     Punkt selbst ab. Dazu die besten Crafts aus deinen **gescannten
     Rezepten**, die dein Bestand sofort hergibt.
   - **Verkaufen**: die wertvollsten AH-Posten deines Accounts. Halbiert
     sich der Bestand, gilt der Punkt als erledigt.
   - **Flips** und ein **Farm-Tipp des Tages** in geschätztem Gold pro
     Stunde – nur für Sammelberufe, die dein Charakter tatsächlich hat.
2. **Verkaufen** – bewertet Taschen und (mit Syndicator) den ganzen Account:
   Bank, Post, Twinks, laufende Auktionen. Pro Item der beste Kanal – **AH**
   (netto nach 5 % Gebühr), **Händler** oder **Entzaubern**. Rechtsklick oder
   Doppelklick blendet ein Item dauerhaft aus („Ignoriert“-Ansicht holt es
   zurück), gebundene Items lassen sich per Knopf ausblenden. Tränke,
   Elixiere und Essen gelten als **Eigenbedarf** und werden nie zum Verkauf
   vorgeschlagen – ihr Wert zählt trotzdem mit.
3. **Flips** – Motes » Ur-Partikel (10:1) und Essenzen 3:1 in beide
   Richtungen, inklusive Bestand und Kauf-Flip-Rechnung.
4. **Crafts** – der Rezept-Radar: Öffne einmal jedes Berufsfenster, Gold
   Copilot merkt sich alle Rezepte dauerhaft und sortiert sie nach Gewinn
   (Erlös netto minus Zutaten zum Marktpreis), mit „×N machbar“ aus deinem
   Accountbestand.
5. **Optionen** – Preisquelle (Auto / Auctionator / TSM), **Mindestgewinn**
   für alle Vorschläge (Schluss mit 0,04-g-Tipps), **Tagesziel**,
   Eigenbedarfsschutz, Datenübersicht und eine Erklärung aller
   Rechenmethoden.

## Voraussetzungen

Gold Copilot bringt bewusst keinen eigenen AH-Scanner mit, sondern nutzt die
Preise, die du ohnehin schon hast:

- **[Auctionator](https://www.curseforge.com/wow/addons/auctionator)**
  (empfohlen): Führe im Auktionshaus regelmäßig einen vollständigen Scan aus.
- **[TradeSkillMaster](https://www.tradeskillmaster.com/)** (optional):
  Ohne Auctionator-Preis greift Gold Copilot auf `dbmarket` zurück.
- **[Syndicator](https://www.curseforge.com/wow/addons/syndicator)**
  (empfohlen): Damit sieht Gold Copilot Bank, Post und Twinks.
- **[Questie](https://www.curseforge.com/wow/addons/questie)** (optional):
  Übernimmt die Prüfung, welche Tagesquests dein Charakter wirklich
  freigeschaltet hat.

Mindestens eine Preisquelle (Auctionator oder TSM) muss installiert sein.

## Installation

1. [Code herunterladen](https://github.com/stryker-max/GoldCopilot/archive/refs/heads/main.zip)
   und entpacken.
2. Den entpackten Ordner in `World of Warcraft\_anniversary_\Interface\AddOns\`
   legen und in **`GoldCopilot`** umbenennen (GitHub hängt sonst `-main` an –
   der Ordnername muss exakt `GoldCopilot` lauten).
3. WoW neu starten und am Charakterbildschirm unter „AddOns“ aktivieren.

## Benutzung

- `/gold` öffnet und schließt das Fenster (`/goldcopilot` geht auch).
- `/gold reset` setzt die Checkliste der laufenden Daily-Periode zurück.
- `/gold quelle` zeigt die aktive Preisquelle.
- Einmal je Charakter: **alle Berufsfenster öffnen**, damit der Craft-Radar
  deine Rezepte kennt.
- Shift-Klick auf eine Zeile verlinkt das Item im Chat; der Tooltip zeigt
  alle Kanäle, Lagerorte und die Rechnung.
- **Jede Empfehlung erklärt sich im Tooltip**: Produktwert, Zutaten,
  erwarteter Gewinn beziehungsweise Marktpreis, angenommene Rate und
  Erwartung je Stunde – dazu die **Preisbasis** (siehe unten).

## So wird gerechnet

- **AH-Erlöse sind immer netto**: 5 % Auktionshausgebühr abgezogen. Die
  Einzahlung (Deposit) wird bei erfolgreichem Verkauf erstattet und darum
  nicht abgezogen.
- **Planungspreise**: Empfehlungen (Roadmap, Flips, Crafts) rechnen mit dem
  **Median der letzten 7 Tage** deiner beobachteten Preise – eine einzelne
  Dumping-Auktion wirft den Plan nicht um. Der Verkaufen-Tab zeigt bewusst
  den aktuellen Scanpreis („was bekomme ich jetzt“). Beobachtet werden alle
  Items, mit denen Gold Copilot rechnet, 14 Tage lang – aufgezeichnet beim
  Login, beim Öffnen des Fensters, beim Aktualisieren und **nach dem
  Verlassen des Auktionshauses**, wenn deine Scanpreise am frischesten sind.
- **Datenqualität sichtbar**: Jeder Empfehlungs-Tooltip nennt, worauf der
  Preis beruht – `Preisbasis: 7-Tage-Median · 6 Tageswerte · gute
  Datenbasis`. Die Stufen: 0 Tageswerte = Momentanpreis, 1–2 = wenig Daten,
  3–5 = mittlere Datenbasis, 6–7 = gute Datenbasis. Bei mehreren beteiligten
  Items (Craft, Flip) zählt die schwächste Reihe.
- **Tagesplan-Reset**: Die Checkliste wird am **Daily-Reset deines Servers**
  neu (über `GetQuestResetTime`), nicht um lokale Mitternacht – sonst wäre
  die Liste mitten in der Abendsitzung leer, während die Dailies selbst noch
  gesperrt sind. `/gold reset` setzt sie jederzeit von Hand zurück.
  Goldverlauf und Preishistorie folgen weiterhin dem Kalendertag.
- **Questbelohnungen**: Jedes Belohnungsitem zählt mit dem besseren Wert aus
  AH netto und Händlerpreis. Fehlt der Marktpreis, bleibt der Händlerwert –
  ein Item, das der Händler für 8 g nimmt, ist nicht wertlos. Was gar nicht
  ins AH darf (gebunden, grau), wird auch nicht so bewertet.
- **Craft-Gewinn** = Produkterlös netto (bei Zufallsausbeute der Mittelwert)
  minus Zutaten zum Marktpreis – auch wenn du die Zutaten schon besitzt,
  denn sie hätten sonst verkauft werden können.
- **Farm-Tipps**: Marktpreis × konservativ geschätzte Sammelrate pro Stunde,
  gefiltert nach deinen tatsächlichen Sammelberufen und Skillständen.
- **Daily-Quests**: Der angezeigte Betrag ist zunächst eine Schätzung
  („ca.“). Beim ersten Abgeben liest Gold Copilot mit, was der Server
  tatsächlich überweist, und rechnet ab dann mit dem echten Wert.
- **Tagesziel**: Die Reihenfolge ergibt sich aus Gold je Minute, mit
  konservativen Zeitschätzungen je Aufgabenart (Daily ≈ 8 Min., Auktion
  einstellen ≈ 3 Min., Craft ≈ 2 Min., Farmen = 60 Min.).
- Graue und gebundene Items werden nie fürs AH vorgeschlagen.

## FAQ

**Warum zeigt fast alles „ohne Marktpreis“?** – Es fehlt ein
Auctionator-Scan auf diesem Realm. Auktionshaus öffnen, vollständigen Scan
starten, `/gold` neu öffnen – die Roadmap erinnert dich von selbst daran.

**Woher weiß das Addon, dass ich etwas erledigt habe?** – Beim ersten Blick
auf den Tagesplan merkt es sich deine Bestände als Ausgangsbasis. Benutzte
Cooldowns, abgegebene Dailies (Quest-Flag), halbierte Verkaufsbestände,
kombinierte Motes, neue Craft-Produkte und Farm-Zuwächse erkennt es daran
automatisch – der Rest bleibt per Häkchen abhakbar.

**Warum will es meine Manatränke nicht verkaufen?** – Weil du sie brauchst.
Verbrauchbares gilt als Eigenbedarf und wird nie vorgeschlagen; in den
Optionen lässt sich das abschalten.

**Sieht Gold Copilot meine Gildenbank?** – Nein, bewusst nicht.

**Verändert das Addon etwas an meinen Auktionen?** – Nein. Es liest Preise
und Bestände, stellt aber nichts ein und kauft nichts.

## Lizenz

MIT – siehe [LICENSE](LICENSE).
