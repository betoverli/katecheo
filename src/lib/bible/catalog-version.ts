/**
 * Content versions for native Themes / Reading / Bible catalogs.
 * Themes + Reading are sha256 of the full serialized catalog payload so any
 * content edit (not just id/count changes) bumps the version iOS polls.
 */
import { COLLECTIONS } from "@/lib/bible/collections";
import { READING_PLANS } from "@/lib/bible/reading-plans";
import {
  readingVersionFromContent,
  themesVersionFromContent,
} from "@/lib/bible/catalog-content-hash";

export {
  contentHash,
  readingVersionFromContent,
  stableSerialize,
  themesVersionFromContent,
} from "@/lib/bible/catalog-content-hash";

/** Keep aligned with `scripts/generate-bible-books-bundle.mjs` / iOS NativeSWR.bibleBooksBundleVersion. */
export const BIBLE_BOOKS_VERSION = "bible-books-v1";

export function themesCatalogVersion(): string {
  return themesVersionFromContent(COLLECTIONS);
}

export function readingCatalogVersion(): string {
  return readingVersionFromContent(READING_PLANS);
}

export function nativeCatalogVersions() {
  return {
    ok: true as const,
    bibleBooks: BIBLE_BOOKS_VERSION,
    themes: themesCatalogVersion(),
    reading: readingCatalogVersion(),
  };
}
