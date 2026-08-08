// PNG -> unkomprimiertes 32-Bit-TGA (BGRA), wie WoW es als Textur erwartet.
// Skaliert per Box-Filter auf eine Zweierpotenz-Kantenlaenge.
// Aufruf: node tools/png2tga.mjs <input.png> <output.tga> [groesse=256]
import fs from "node:fs";
import { PNG } from "pngjs";

const [input, output, sizeArg] = process.argv.slice(2);
if (!input || !output) {
  console.error("Aufruf: node tools/png2tga.mjs <input.png> <output.tga> [groesse]");
  process.exit(1);
}
const size = Number(sizeArg || 256);
if ((size & (size - 1)) !== 0) {
  console.error(`Groesse ${size} ist keine Zweierpotenz.`);
  process.exit(1);
}

const png = PNG.sync.read(fs.readFileSync(input));

// Box-Filter: Mittelwert aller Quellpixel, die auf den Zielpixel fallen.
const out = Buffer.alloc(size * size * 4);
for (let y = 0; y < size; y++) {
  const y0 = Math.floor((y * png.height) / size);
  const y1 = Math.max(y0 + 1, Math.floor(((y + 1) * png.height) / size));
  for (let x = 0; x < size; x++) {
    const x0 = Math.floor((x * png.width) / size);
    const x1 = Math.max(x0 + 1, Math.floor(((x + 1) * png.width) / size));
    let r = 0, g = 0, b = 0, a = 0, n = 0;
    for (let sy = y0; sy < y1; sy++) {
      for (let sx = x0; sx < x1; sx++) {
        const idx = (sy * png.width + sx) * 4;
        const alpha = png.data[idx + 3];
        r += png.data[idx] * alpha;
        g += png.data[idx + 1] * alpha;
        b += png.data[idx + 2] * alpha;
        a += alpha;
        n++;
      }
    }
    const idx = (y * size + x) * 4;
    if (a > 0) {
      out[idx] = Math.round(b / a);
      out[idx + 1] = Math.round(g / a);
      out[idx + 2] = Math.round(r / a);
      out[idx + 3] = Math.round(a / n);
    }
  }
}

// TGA-Header: Typ 2 (uncompressed truecolor), 32 Bit, Ursprung oben links.
const header = Buffer.alloc(18);
header[2] = 2;
header.writeUInt16LE(size, 12);
header.writeUInt16LE(size, 14);
header[16] = 32;
header[17] = 0x28;

fs.mkdirSync(new URL("../" + output.split("/").slice(0, -1).join("/"), import.meta.url), { recursive: true });
fs.writeFileSync(output, Buffer.concat([header, out]));
console.log(`${output}: ${size}x${size}, 32 Bit BGRA.`);
