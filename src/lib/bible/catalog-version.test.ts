import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { describe, it } from "node:test";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";

const here = dirname(fileURLToPath(import.meta.url));

describe("catalog-version module", () => {
  it("ships bible / themes / reading version helpers", () => {
    const src = readFileSync(join(here, "catalog-version.ts"), "utf8");
    assert.match(src, /BIBLE_BOOKS_VERSION\s*=\s*"bible-books-v1"/);
    assert.match(src, /export function themesCatalogVersion/);
    assert.match(src, /export function readingCatalogVersion/);
    assert.match(src, /export function nativeCatalogVersions/);
  });
});
