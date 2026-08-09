import fs from "node:fs";
import { lua, lauxlib, lualib, to_luastring } from "fengari";

// Aus dem Repo-Wurzelverzeichnis starten: die Testdateien laden die
// Addon-Dateien ueber relative Pfade.
if (!fs.existsSync("GoldCopilot.toc")) {
  console.error("Bitte aus dem Repo-Wurzelverzeichnis starten (node tests/run.mjs).");
  process.exit(1);
}

// Jede Testdatei bekommt einen eigenen Lua-Zustand: ui.lua braucht eine
// reichhaltigere Frame-Attrappe, und die darf smoke.lua nicht beeinflussen.
for (const file of ["tests/smoke.lua", "tests/ui.lua"]) {
  const L = lauxlib.luaL_newstate();
  lualib.luaL_openlibs(L);
  const source = fs.readFileSync(file, "utf8");
  const status = lauxlib.luaL_dostring(L, to_luastring(source));
  if (status !== lua.LUA_OK) {
    console.error(`${file} fehlgeschlagen:`, lua.lua_tojsstring(L, -1));
    process.exit(1);
  }
}
