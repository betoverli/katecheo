import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { describe, it } from "node:test";
import {
  DEFAULT_TRANSLATION,
  normalizeTranslationId,
  translationById,
  TRANSLATIONS,
} from "./translations.ts";

const root = new URL("../../../", import.meta.url);

function read(rel: string) {
  return readFileSync(new URL(rel, root), "utf8");
}

describe("normalizeTranslationId", () => {
  it("keeps known slug ids", () => {
    assert.equal(normalizeTranslationId("niv", "en"), "niv");
    assert.equal(normalizeTranslationId("nvi-pt", "pt"), "nvi-pt");
    assert.equal(normalizeTranslationId("rvr1960", "es"), "rvr1960");
  });

  it("maps legacy YouVersion numeric strings via youVersion", () => {
    assert.equal(normalizeTranslationId("111", "en"), "niv");
    assert.equal(normalizeTranslationId("129", "pt"), "nvi-pt");
    assert.equal(normalizeTranslationId("128", "es"), "rvr1960");
    assert.equal(normalizeTranslationId("59", "en"), "esv");
    for (const tr of TRANSLATIONS) {
      assert.equal(
        normalizeTranslationId(String(tr.youVersion), tr.locale),
        tr.id,
        `${tr.youVersion} → ${tr.id}`,
      );
    }
  });

  it("falls back to DEFAULT_TRANSLATION[locale] for unknown values", () => {
    assert.equal(normalizeTranslationId("99999", "pt"), DEFAULT_TRANSLATION.pt);
    assert.equal(normalizeTranslationId("99999", "en"), DEFAULT_TRANSLATION.en);
    assert.equal(normalizeTranslationId("99999", "es"), DEFAULT_TRANSLATION.es);
    assert.equal(normalizeTranslationId("not-a-real-id", "en"), DEFAULT_TRANSLATION.en);
    assert.equal(normalizeTranslationId("", "pt"), DEFAULT_TRANSLATION.pt);
    assert.equal(normalizeTranslationId(null, "es"), DEFAULT_TRANSLATION.es);
    assert.equal(normalizeTranslationId(undefined, "en"), DEFAULT_TRANSLATION.en);
  });

  it("translationById resolves numeric legacy ids", () => {
    assert.equal(translationById("111", "en").id, "niv");
    assert.equal(translationById("111").youVersion, 111);
  });
});

describe("link-api + prefs legacy translation wiring", () => {
  it("tolerates numeric translations instead of 400 Unknown translation", () => {
    const linkApi = read("src/lib/bible/link-api.ts");
    assert.match(linkApi, /normalizeTranslationId/);
    assert.doesNotMatch(linkApi, /Unknown translation/);
  });

  it("defaultPrefs uses DEFAULT_TRANSLATION slug, not YouVersion 111", () => {
    const profile = read("src/lib/native/api/v1-profile.server.ts");
    assert.match(profile, /DEFAULT_TRANSLATION\[locale\]/);
    assert.doesNotMatch(profile, /translationId:\s*"111"/);
    assert.match(profile, /normalizeTranslationId/);
  });

  it("v1-verses prefs fallback normalizes translation ids", () => {
    const verses = read("src/lib/native/api/v1-verses.server.ts");
    assert.match(verses, /normalizeTranslationId\(translation/);
  });

  it("ships migration 0029 mapping numeric translation_id rows", () => {
    const sql = read("migrations/0029_normalize_translation_id.sql");
    assert.match(sql, /when '111' then 'niv'/);
    assert.match(sql, /when '129' then 'nvi-pt'/);
    assert.match(sql, /translation_id = 'nvi-pt'/);
  });
});
