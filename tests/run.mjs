import fs from "node:fs";
import { lua, lauxlib, lualib, to_luastring } from "fengari";

// Aus dem Repo-Wurzelverzeichnis starten: smoke.lua laedt die Addon-Dateien
// ueber relative Pfade.
if (!fs.existsSync("GoldCopilot.toc")) {
  console.error("Bitte aus dem Repo-Wurzelverzeichnis starten (node tests/run.mjs).");
  process.exit(1);
}

const L = lauxlib.luaL_newstate();
lualib.luaL_openlibs(L);

const source = fs.readFileSync("tests/smoke.lua", "utf8");
const status = lauxlib.luaL_dostring(L, to_luastring(source));
if (status !== lua.LUA_OK) {
  console.error("smoke.lua fehlgeschlagen:", lua.lua_tojsstring(L, -1));
  process.exit(1);
}
