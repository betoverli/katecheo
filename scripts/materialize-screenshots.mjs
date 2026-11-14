import { mkdirSync, writeFileSync, readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const root = join(dirname(fileURLToPath(import.meta.url)), "..");
const data = JSON.parse(readFileSync(join(root, "scripts/app-store-screenshots.json"), "utf8"));

for (const [rel, b64] of Object.entries(data)) {
  const dest = join(root, "public/screenshots", rel);
  mkdirSync(dirname(dest), { recursive: true });
  writeFileSync(dest, Buffer.from(b64, "base64"));
}
