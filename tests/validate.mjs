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

// Jede Datei aus der TOC muss existieren, und jede Lua-Datei im Wurzelverzeichnis
// muss in der TOC stehen - eine vergessene Datei laedt WoW sonst stillschweigend nie.
const tocFiles = toc
  .split(/\r?\n/)
  .map((line) => line.trim())
  .filter((line) => line.length > 0 && !line.startsWith("##"));
for (const file of tocFiles) {
  if (!fs.existsSync(path.join(root, file))) {
    throw new Error(`TOC nennt ${file}, aber die Datei fehlt.`);
  }
}
for (const file of fs.readdirSync(root)) {
  if (file.endsWith(".lua") && !tocFiles.includes(file)) {
    throw new Error(`${file} liegt im Wurzelverzeichnis, steht aber nicht in der TOC.`);
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

console.log(`validate.mjs: Struktur in Ordnung (Version ${tocVersion}).`);
