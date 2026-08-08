# Gold Copilot 0.1.0

Dein Gold-Berater für **World of Warcraft: Burning Crusade Classic Anniversary**.

Gold Copilot beantwortet jeden Tag drei Fragen:

1. **Was mache ich heute für Gold?** – Der Tab **Heute** baut dir eine tägliche
   Checkliste wie ein Daily-Quest-Log: Berufs-Cooldowns mit aktueller
   Gewinnrechnung, die wertvollsten Verkäufe aus deinem Bestand, die besten
   Flips und ein Farm-Tipp des Tages – sortiert nach Gold pro Aufwand, zum
   Abhaken, mit Tagesreset um Mitternacht.
2. **Was ist mein Kram wert?** – Der Tab **Verkaufen** scannt deine Taschen und
   (mit Syndicator) den **ganzen Account** – Bank, Postfach, Twinks, laufende
   Auktionen. Für jedes Item zeigt er den besten Verkaufskanal: **AH** (nach
   5 % Gebühr), **Händler** oder **Entzaubern**, sortiert nach Gesamtwert.
3. **Welche 1-Klick-Gewinne gibt es gerade?** – Der Tab **Flips** rechnet
   Motes ↔ Ur-Partikel (10:1) für alle Elemente und Essenzen (3:1, mit
   Verzauberkunst) in beide Richtungen durch – inklusive AH-Gebühr und
   deinem vorhandenen Bestand.

Dazu gibt es einen 7-Tage-Goldverlauf über den ganzen Account und eine
Erinnerung, wenn deine Preisbasis veraltet ist.

## Voraussetzungen

Gold Copilot bringt bewusst keinen eigenen AH-Scanner mit, sondern nutzt die
Preise, die du ohnehin schon hast:

- **[Auctionator](https://www.curseforge.com/wow/addons/auctionator)**
  (empfohlen): Führe im Auktionshaus regelmäßig einen vollständigen Scan aus,
  dann rechnet Gold Copilot mit echten Preisen deines Servers.
- **[TradeSkillMaster](https://www.tradeskillmaster.com/)** (optional):
  Ohne Auctionator-Preis greift Gold Copilot auf `dbmarket` zurück.
- **[Syndicator](https://www.curseforge.com/wow/addons/syndicator)**
  (empfohlen): Damit sieht Gold Copilot Bank, Post und Twinks – ohne
  Syndicator nur die Taschen des eingeloggten Charakters.

Mindestens eine Preisquelle (Auctionator oder TSM) muss installiert sein.

## Installation

1. [Code herunterladen](https://github.com/stryker-max/GoldCopilot/archive/refs/heads/main.zip)
   und entpacken.
2. Den entpackten Ordner in `World of Warcraft\_anniversary_\Interface\AddOns\`
   legen und in **`GoldCopilot`** umbenennen (GitHub hängt sonst `-main` an –
   der Ordnername muss exakt `GoldCopilot` lauten, damit WoW die
   `GoldCopilot.toc` findet).
3. WoW neu starten und am Charakterbildschirm unter „AddOns" aktivieren.

## Benutzung

- `/gold` öffnet und schließt das Fenster (`/goldcopilot` geht auch).
- `/gold reset` setzt die heutige Checkliste zurück.
- `/gold quelle` zeigt die aktive Preisquelle.
- Im Tab **Verkaufen**: „Umfang" schaltet zwischen Account und Taschen,
  „Filter" zwischen Alles / Mats / Ausrüstung. Shift-Klick auf eine Zeile
  verlinkt das Item im Chat, der Tooltip zeigt alle Kanäle und Lagerorte.

## Wie die Zahlen entstehen

- **Marktpreis**: Auctionator-Scanpreis deines Servers; fällt auf TSM
  `dbmarket` zurück (Reihenfolge unter `/gold quelle` sichtbar).
- **AH-Werte** sind immer **netto**: 5 % Auktionshausgebühr sind abgezogen.
- **Entzaubern** nutzt Auctionators Entzauberungswert (Durchschnitt der
  möglichen Materialien zu aktuellen Preisen).
- **Cooldown-Gewinn** = Produkterlös netto minus Marktpreis der Zutaten –
  auch wenn du die Zutaten schon besitzt, denn verbrauchte Mats hätten sonst
  verkauft werden können.
- Graue und gebundene Items werden nie fürs AH vorgeschlagen.

## FAQ

**Warum zeigt fast alles „ohne Marktpreis"?** – Es fehlt ein
Auctionator-Scan auf diesem Realm. Auktionshaus öffnen, Volltext-Scan im
Auctionator starten, dann `/gold` neu öffnen.

**Sieht Gold Copilot meine Gildenbank?** – Nein, bewusst nicht: Was in der
Gildenbank liegt, gehört selten einem allein.

**Verändert das Addon etwas an meinen Auktionen?** – Nein. Gold Copilot ist
ein reiner Berater: Er liest Preise und Bestände, stellt aber nichts ein und
kauft nichts.

## Lizenz

MIT – siehe [LICENSE](LICENSE).
