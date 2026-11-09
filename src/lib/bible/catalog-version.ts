/**
 * Lightweight content versions for native Themes / Reading / Bible catalogs.
 * Bump when static catalog files change (or rely on derived fingerprints).
 */
import { COLLECTIONS } from "@/lib/bible/collections";
import { PLAN_TOTAL, READING_PLANS } from "@/lib/bible/reading-plans";

/** Keep aligned with `scripts/generate-bible-books-bundle.mjs` / iOS NativeSWR.bibleBooksBundleVersion. */
export const BIBLE_BOOKS_VERSION = "bible-books-v1";

function fingerprint(parts: string[]): string {
  // Stable, short, no crypto dependency — good enough for cache busting.
  let h = 2166136261;
  const joined = parts.join("|");
  for (let i = 0; i < joined.length; i++) {
    h ^= joined.charCodeAt(i);
    h = Math.imul(h, 16777619);
  }
  return (h >>> 0).toString(16);
}

export function themesCatalogVersion(): string {
  return `themes-${fingerprint([
    String(COLLECTIONS.length),
    COLLECTIONS.map((c) => c.id).join(","),
  ])}`;
}

export function readingCatalogVersion(): string {
  return `reading-${fingerprint([
    String(PLAN_TOTAL),
    READING_PLANS.map((p) => p.id).join(","),
  ])}`;
}

export function nativeCatalogVersions() {
  return {
    ok: true as const,
    bibleBooks: BIBLE_BOOKS_VERSION,
    themes: themesCatalogVersion(),
    reading: readingCatalogVersion(),
  };
}
