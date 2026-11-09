#!/usr/bin/env node
/**
 * Emits ios/App/App/BibleBooksData.json from src/lib/bible/books.ts.
 * Static catalog — ship in the app so Livros works offline from first launch.
 *
 * Bump BUNDLE_VERSION when verse counts / book metadata change.
 */
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
/** Keep in sync with NativeAPIClient.bibleBooksBundleVersion / server catalog-version. */
export const BIBLE_BOOKS_BUNDLE_VERSION = 1;

const src = fs.readFileSync(path.join(root, "src/lib/bible/books.ts"), "utf8");
const books = [];
const re =
  /\{\s*"id":\s*"([A-Z0-9]+)"[\s\S]*?"testament":\s*"(ot|nt)"[\s\S]*?"names":\s*\{([^}]+)\}[\s\S]*?"abbr":\s*\{([^}]+)\}[\s\S]*?"verses":\s*(\[[^\]]+\])/g;
let m;
while ((m = re.exec(src))) {
  const names = Object.fromEntries(
    [...m[3].matchAll(/"(pt|en|es)":\s*"((?:\\.|[^"\\])*)"/g)].map((x) => [x[1], JSON.parse(`"${x[2]}"`)]),
  );
  const abbr = Object.fromEntries(
    [...m[4].matchAll(/"(pt|en|es)":\s*"((?:\\.|[^"\\])*)"/g)].map((x) => [x[1], JSON.parse(`"${x[2]}"`)]),
  );
  const verses = JSON.parse(m[5]);
  books.push({ id: m[1], testament: m[2], names, abbr, chapters: verses.length, verses });
}

if (books.length < 66) {
  console.error(`Expected 66 books, got ${books.length}`);
  process.exit(1);
}

const out = {
  version: BIBLE_BOOKS_BUNDLE_VERSION,
  books,
};
const dest = path.join(root, "ios/App/App/BibleBooksData.json");
fs.writeFileSync(dest, `${JSON.stringify(out)}\n`);
console.log(`Wrote ${path.relative(root, dest)} (${books.length} books, v${BIBLE_BOOKS_BUNDLE_VERSION})`);
