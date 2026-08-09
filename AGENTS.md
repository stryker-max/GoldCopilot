# Projektregeln Gold Copilot

- **Standalone-Addon**: Das Repo-Wurzelverzeichnis ist der Addon-Ordner
  (`GoldCopilot.toc` liegt im Root). Es gibt bewusst keinen Installer und
  keine Companion-App.
- Fertige, getestete Änderungen werden ohne Rückfrage nach `main` gepusht.
- Versionsnummer immer an drei Stellen synchron halten: `GoldCopilot.toc`
  (`## Version`), `Constants.lua` (`VERSION`) und die Überschrift der
  `README.md`. `tests/validate.mjs` erzwingt das.
- Vor jedem Push: `npm test` (validate.mjs + smoke.lua, ui.lua, engine.lua und
  simulation.lua über fengari) muss grün sein. Lua läuft lokal nur über
  fengari (npm-Paket), es gibt keinen installierten Interpreter.
- Nach Änderungen die lokale Installation unter
  `C:\Program Files (x86)\World of Warcraft\_anniversary_\Interface\AddOns\GoldCopilot`
  aktualisieren: nur `GoldCopilot.toc`, `*.lua`, `Knowledge/`, `Media/` und
  `README.md` kopieren – nie `tests/`, `docs/`, `node_modules/`, `.git/` oder
  `package.json`.
- Die `WTF`-SavedVariables des Nutzers niemals verändern oder löschen.
- Neue Item- oder Zauber-IDs vor dem Eintragen gegen die lokalen
  Questie-/AtlasLoot-Datenbanken prüfen (siehe AddOns-Ordner), nicht raten.
- Marktdaten liegen je Realm und Fraktion in `db.profiles`. Neue
  realmabhängige Speicher gehören dorthin (`GCP:Profile()`), nicht ins
  Wurzelverzeichnis der Datenbank.
- Jede persistente Struktur braucht eine Formatversion, eine Obergrenze und
  eine Typprüfung in ihrer `EnsureStore`-Funktion.
- Kein `OnUpdate`. Wiederkehrende Arbeit läuft über Ereignisse oder über
  `C_Timer.After`, das sich selbst neu einplant und aufhört, sobald es nicht
  mehr gebraucht wird.
- Fehlende Daten ergeben `nil` und einen Satz in der Oberfläche – nie eine 0
  und nie einen Schätzwert.
