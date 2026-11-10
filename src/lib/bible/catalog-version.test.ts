import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { describe, it } from "node:test";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";
import {
  contentHash,
  readingVersionFromContent,
  stableSerialize,
  themesVersionFromContent,
} from "./catalog-content-hash.ts";

const here = dirname(fileURLToPath(import.meta.url));

describe("catalog-version module wiring", () => {
  it("ships bible / themes / reading version helpers over full content hashes", () => {
    const src = readFileSync(join(here, "catalog-version.ts"), "utf8");
    assert.match(src, /BIBLE_BOOKS_VERSION\s*=\s*"bible-books-v1"/);
    assert.match(src, /export function themesCatalogVersion/);
    assert.match(src, /export function readingCatalogVersion/);
    assert.match(src, /export function nativeCatalogVersions/);
    assert.match(src, /themesVersionFromContent\(COLLECTIONS\)/);
    assert.match(src, /readingVersionFromContent\(READING_PLANS\)/);
  });
});

describe("catalog content hash", () => {
  it("changes version when content changes", () => {
    const a = [{ id: "salvation", names: { pt: "Salvação" }, passages: [] }];
    const b = [{ id: "salvation", names: { pt: "Salvação editada" }, passages: [] }];
    assert.notEqual(themesVersionFromContent(a), themesVersionFromContent(b));
    assert.notEqual(contentHash(a), contentHash(b));
  });

  it("is stable for identical content and object-key reorder", () => {
    const left = {
      id: "grace",
      names: { en: "Grace", pt: "Graça", es: "Gracia" },
      passages: [{ bookId: "ROM", chapter: 3, verseStart: 24, verseEnd: null }],
    };
    const right = {
      passages: [{ verseEnd: null, verseStart: 24, chapter: 3, bookId: "ROM" }],
      names: { es: "Gracia", pt: "Graça", en: "Grace" },
      id: "grace",
    };
    assert.equal(stableSerialize(left), stableSerialize(right));
    assert.equal(themesVersionFromContent([left]), themesVersionFromContent([right]));
    assert.equal(contentHash([left]), contentHash([right]));
  });

  it("hashes reading plans independently of themes", () => {
    const plans = [{ id: "nt-90", names: { pt: "NT 90" }, categoryIds: [], days: [] }];
    const themes = [{ id: "faith", names: { pt: "Fé" }, passages: [] }];
    assert.match(readingVersionFromContent(plans), /^reading-[0-9a-f]{64}$/);
    assert.match(themesVersionFromContent(themes), /^themes-[0-9a-f]{64}$/);
    assert.notEqual(readingVersionFromContent(plans), themesVersionFromContent(themes));
  });
});
