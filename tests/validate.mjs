import fs from "node:fs";
import path from "node:path";

const root = path.resolve(".");
const toc = fs.readFileSync(path.join(root, "GoldCopilot.toc"), "utf8");
const constants = fs.readFileSync(path.join(root, "Constants.lua"), "utf8");
const readme = fs.readFileSync(path.join(root, "README.md"), "utf8");

for (const entry of [
  "## Interface: 20506",
  "## Title: Gold Copilot",
  "## SavedVariables: GoldCopilotDB",
]) {
  if (!toc.includes(entry)) {
    throw new Error(`Fehlender TOC-Eintrag: ${entry}`);
  }
}

const tocVersion = toc.match(/^## Version:\s*(\S+)/m)?.[1];
const constantsVersion = constants.match(/\bVERSION\s*=\s*"([^"]+)"/)?.[1];
const readmeVersion = readme.match(/^# Gold Copilot\s+(\S+)/m)?.[1];
if (!tocVersion || tocVersion !== constantsVersion || tocVersion !== readmeVersion) {
  throw new Error(
    `Versionen widersprechen sich: TOC=${tocVersion}, Constants=${constantsVersion}, README=${readmeVersion}`
  );
}

// Jede Datei aus der TOC muss existieren, und jede Lua-Datei des Addons muss in
// der TOC stehen - eine vergessene Datei laedt WoW sonst stillschweigend nie.
// Die TOC schreibt Pfade in WoW-Schreibweise mit Backslash (Knowledge\Foo.lua);
// hier wird auf Schraegstriche normalisiert, damit die Pruefung auf jedem
// Betriebssystem funktioniert.
const tocFiles = toc
  .split(/\r?\n/)
  .map((line) => line.trim())
  .filter((line) => line.length > 0 && !line.startsWith("##"))
  .map((line) => line.replace(/\\/g, "/"));
for (const file of tocFiles) {
  if (!fs.existsSync(path.join(root, file))) {
    throw new Error(`TOC nennt ${file}, aber die Datei fehlt.`);
  }
}

// Testgeruest und Werkzeuge gehoeren nicht ins Addon und deshalb nicht in die TOC.
const IGNORED_DIRS = new Set(["tests", "tools", "node_modules", ".git", "Media"]);
function luaFilesIn(dir, prefix = "") {
  const found = [];
  for (const entry of fs.readdirSync(path.join(root, dir || "."), { withFileTypes: true })) {
    const relative = prefix ? `${prefix}/${entry.name}` : entry.name;
    if (entry.isDirectory()) {
      if (IGNORED_DIRS.has(entry.name)) continue;
      found.push(...luaFilesIn(relative, relative));
    } else if (entry.name.endsWith(".lua")) {
      found.push(relative);
    }
  }
  return found;
}
for (const file of luaFilesIn("")) {
  if (!tocFiles.includes(file)) {
    throw new Error(`${file} gehoert zum Addon, steht aber nicht in der TOC.`);
  }
}

// Copy-Paste-Schutz gegenueber dem Schwesterprojekt.
for (const file of tocFiles) {
  const content = fs.readFileSync(path.join(root, file), "utf8");
  if (content.includes("GuildCopilot")) {
    throw new Error(`${file} enthaelt noch einen GuildCopilot-Verweis.`);
  }
}

if (!readme.includes("/gold")) {
  throw new Error("README erklaert den Slash-Befehl /gold nicht.");
}

// Zeichen, die die Clientschrift nicht kennt (1.0.0-beta.4).
//
// FRIZQT__.TTF enthaelt den Unicode-Block "Geometric Shapes" (U+25A0-U+25FF)
// nicht, ebensowenig die Pfeilbloecke. Der Richtungspfeil des Guides bestand
// aus genau diesen Zeichen und erschien im Spiel ueber mehrere Fassungen
// hinweg als leeres Kaestchen, ohne dass es auffiel - im Quelltext sieht "▲"
// schliesslich richtig aus.
//
// Die Pruefung steht hier statt in den Lua-Tests, weil sie den QUELLTEXT
// betrifft: Zur Laufzeit faellt nichts auf, denn eine fehlende Glyphe meldet
// keinen Fehler, sie wird stillschweigend als Kaestchen gezeichnet.
const forbiddenGlyphs = /[←-⇿■-◿⬀-⯿]/;
for (const file of tocFiles) {
  const content = fs.readFileSync(path.join(root, file), "utf8");
  const lines = content.split(/\r?\n/);
  for (let index = 0; index < lines.length; index += 1) {
    const line = lines[index];
    // Kommentare duerfen solche Zeichen tragen: Die liest nur, wer den
    // Quelltext oeffnet, und der hat eine Schrift, die sie kennt.
    if (line.trim().startsWith("--")) continue;
    const match = line.match(forbiddenGlyphs);
    if (match) {
      throw new Error(
        `${file}:${index + 1} verwendet "${match[0]}" - dieses Zeichen fehlt ` +
          `in FRIZQT__.TTF und erscheint im Spiel als leeres Kaestchen.`
      );
    }
  }
}

console.log(`validate.mjs: Struktur in Ordnung (Version ${tocVersion}).`);
