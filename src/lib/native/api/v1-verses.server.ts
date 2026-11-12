/**
 * Native `/api/native/v1` verse + theme catalog + append-to-note.
 * Reuses bible link/collections helpers and NoteDocumentV1 for refs in notes.
 */
import { BIBLE_APPS, appById } from "@/lib/bible/apps";
import { BOOKS, type Locale } from "@/lib/bible/books";
import { resolveCollections, type CollectionQuery } from "@/lib/bible/collections-api";
import { resolveLinks, type LinkQuery } from "@/lib/bible/link-api";
import type { Passage } from "@/lib/bible/passage";
import { formatPassageById } from "@/lib/bible/passage";
import {
  DEFAULT_TRANSLATION,
  normalizeTranslationId,
  TRANSLATIONS,
} from "@/lib/bible/translations";
import { getSql } from "@/lib/db";
import { appendPassageToBlocks, todayKey, type Note } from "@/lib/notebook";
import { cleanPassages } from "@/lib/user-collections";
import type { CollectionVisibility, UserCollection } from "@/lib/user-collection";
import {
  noteToDocument,
  type LegacyNote,
  type NoteDocumentV1,
} from "./note-document";
import { getPrefsForUser } from "./v1-profile.server";
import { noteFromRow, upsertNoteForUser } from "./v1.server";

type NoteRow = {
  id: string;
  title: string;
  happened_at: string;
  tags: string;
  blocks: string;
  visibility: string;
  updated_at: string;
  speaker_id?: string | null;
};

type CollectionRow = {
  id: string;
  title: string;
  slug: string;
  visibility: string;
  passages: string;
  source_id: string;
  updated_at: string;
};

const MAX_COLLECTIONS = 40;

function asLocale(value: string | undefined): Locale {
  if (value === "en" || value === "es" || value === "pt") return value;
  return "pt";
}

function newId() {
  return crypto.randomUUID().replaceAll("-", "");
}

function parseJson<T>(raw: string, fallback: T): T {
  try {
    return JSON.parse(raw) as T;
  } catch {
    return fallback;
  }
}

function asVisibility(value: string): CollectionVisibility {
  return value === "unlisted" || value === "public" ? value : "private";
}

function collectionFromRow(row: CollectionRow): UserCollection {
  return {
    id: row.id,
    title: row.title,
    slug: row.slug ?? "",
    visibility: asVisibility(row.visibility),
    sourceId: row.source_id ?? "",
    passages: cleanPassages(
      parseJson(typeof row.passages === "string" ? row.passages : JSON.stringify(row.passages ?? []), []),
    ),
    updatedAt: String(row.updated_at ?? ""),
  };
}

function asLegacy(note: Note): LegacyNote {
  return note as LegacyNote;
}

function parsePassage(raw: unknown): Passage | null {
  if (!raw || typeof raw !== "object") return null;
  const row = raw as Record<string, unknown>;
  const bookId = typeof row.bookId === "string" ? row.bookId.trim().toUpperCase() : "";
  const book = BOOKS.find((item) => item.id === bookId);
  const chapter = Number(row.chapter);
  if (!book || !Number.isInteger(chapter) || chapter < 1 || chapter > book.verses.length) return null;
  const verseStart =
    row.verseStart == null || row.verseStart === "" ? null : Number(row.verseStart);
  const verseEnd = row.verseEnd == null || row.verseEnd === "" ? null : Number(row.verseEnd);
  const start = verseStart && Number.isInteger(verseStart) && verseStart > 0 ? verseStart : null;
  const end = verseEnd && Number.isInteger(verseEnd) && verseEnd > 0 ? verseEnd : null;
  const maxVerse = book.verses[chapter - 1] ?? 0;
  if (start != null && start > maxVerse) return null;
  if (end != null && end > maxVerse) return null;
  return { bookId, chapter, verseStart: start, verseEnd: end };
}

/** Slim book catalog for the native picker (pt-BR names by default). */
export function listBibleBooks(localeRaw?: string) {
  const locale = asLocale(localeRaw);
  return {
    ok: true as const,
    locale,
    books: BOOKS.map((book) => ({
      id: book.id,
      testament: book.testament,
      name: book.names[locale],
      abbr: book.abbr[locale],
      chapters: book.verses.length,
      verses: book.verses,
    })),
  };
}

/** Bible apps + translations for pickers (mirrors Perfil Bible settings). */
export function listBibleApps(localeRaw?: string) {
  const locale = asLocale(localeRaw);
  return {
    ok: true as const,
    locale,
    apps: BIBLE_APPS.map((app) => ({
      id: app.id,
      name: app.names[locale],
      blurb: app.blurb[locale],
      hasWeb: app.hasWeb,
      hasNative: app.hasNative,
      usesTranslation: app.usesTranslation,
    })),
    translations: TRANSLATIONS.map((tr) => ({
      id: tr.id,
      locale: tr.locale,
      abbr: tr.abbr,
      name: tr.name[locale],
    })),
    defaults: {
      appId: "youversion",
      translationId: DEFAULT_TRANSLATION[locale],
      preferNative: false,
    },
  };
}

export async function resolveNativeLink(
  userId: string | null,
  query: LinkQuery,
): Promise<ReturnType<typeof resolveLinks>> {
  let app = query.app;
  let translation = query.translation;
  let locale = query.locale;
  let native = query.native;
  if (userId) {
    try {
      const prefs = await getPrefsForUser(userId);
      app = app || prefs.appId;
      translation = translation || prefs.translationId;
      locale = locale || prefs.locale;
      if (query.native == null) native = prefs.preferNative;
    } catch {
      // Prefs optional for public link resolution.
    }
  }
  const resolvedLocale = asLocale(locale);
  return resolveLinks({
    refs: query.refs,
    app,
    translation: normalizeTranslationId(translation, resolvedLocale),
    locale: resolvedLocale,
    native,
  });
}

export function resolveNativeThemes(query: CollectionQuery) {
  return resolveCollections(query);
}

export async function appendVerseForUser(
  userId: string,
  raw: unknown,
): Promise<
  | { ok: true; note: NoteDocumentV1; label: string }
  | { ok: false; error: "invalid" | "limit" | "missing" | "conflict" }
> {
  if (!raw || typeof raw !== "object") return { ok: false, error: "invalid" };
  const body = raw as Record<string, unknown>;
  const passage = parsePassage(body.passage ?? body);
  if (!passage) return { ok: false, error: "invalid" };

  const noteId = typeof body.noteId === "string" ? body.noteId.trim().slice(0, 40) : "";
  const speakerId =
    typeof body.speakerId === "string" && body.speakerId ? body.speakerId.slice(0, 40) : null;

  const sql = await getSql();
  let note: Note | null = null;

  if (noteId) {
    const rows = await sql<NoteRow>`
      select id, title, happened_at::text, tags, blocks, visibility, updated_at, speaker_id
      from notebook_notes
      where id = ${noteId} and user_id = ${userId}
      limit 1
    `;
    if (!rows[0]) return { ok: false, error: "missing" };
    note = noteFromRow(rows[0]);
  } else {
    const day = todayKey();
    const rows = await sql<NoteRow>`
      select id, title, happened_at::text, tags, blocks, visibility, updated_at, speaker_id
      from notebook_notes
      where user_id = ${userId} and happened_at = ${day}::date
      order by updated_at desc
      limit 1
    `;
    if (rows[0]) {
      note = noteFromRow(rows[0]);
    } else {
      note = {
        id: newId(),
        title: "",
        happenedAt: day,
        tags: [],
        speakerId: null,
        blocks: [{ id: newId(), type: "p", inlines: [] }],
        visibility: "private",
        updatedAt: new Date().toISOString(),
      };
    }
  }

  const next: Note = {
    ...note,
    blocks: appendPassageToBlocks(note.blocks, passage, speakerId),
    updatedAt: new Date().toISOString(),
  };

  const result = await upsertNoteForUser(userId, noteToDocument(asLegacy(next)));
  if (!result.ok) return { ok: false, error: result.error };

  let locale: Locale = "pt";
  try {
    locale = asLocale((await getPrefsForUser(userId)).locale);
  } catch {
    // keep pt
  }

  return {
    ok: true,
    note: result.note,
    label: formatPassageById(passage, locale) || `${passage.bookId} ${passage.chapter}`,
  };
}

export async function listMyCollectionsForUser(userId: string): Promise<UserCollection[]> {
  const sql = await getSql();
  const rows = await sql<CollectionRow>`
    select id, title, slug, visibility, passages, coalesce(source_id, '') as source_id, updated_at
    from user_collections
    where user_id = ${userId}
    order by updated_at desc
  `;
  return rows.map(collectionFromRow);
}

export async function getMyCollectionForUser(
  userId: string,
  id: string,
): Promise<UserCollection | null> {
  const sql = await getSql();
  const rows = await sql<CollectionRow>`
    select id, title, slug, visibility, passages, coalesce(source_id, '') as source_id, updated_at
    from user_collections
    where id = ${id} and user_id = ${userId}
    limit 1
  `;
  return rows[0] ? collectionFromRow(rows[0]) : null;
}

export async function createMyCollectionForUser(
  userId: string,
  raw: unknown,
): Promise<
  | { ok: true; collection: UserCollection }
  | { ok: false; error: "invalid" | "limit" | "missing" }
> {
  if (!raw || typeof raw !== "object") return { ok: false, error: "invalid" };
  const body = raw as Record<string, unknown>;
  const title =
    typeof body.title === "string" ? body.title.trim().replace(/\s+/g, " ").slice(0, 60) : "";
  if (!title) return { ok: false, error: "invalid" };
  const passages = cleanPassages(body.passages ?? []);
  const sourceId = typeof body.sourceId === "string" ? body.sourceId.slice(0, 64) : "";
  const visibility =
    typeof body.visibility === "string" ? asVisibility(body.visibility) : ("private" as CollectionVisibility);
  // Phase 6 import: accept a client id so Cap localStorage → native upsert is idempotent.
  const requestedId =
    typeof body.id === "string" ? body.id.trim().replace(/[^a-zA-Z0-9_-]/g, "").slice(0, 40) : "";
  if (requestedId) {
    const existing = await getMyCollectionForUser(userId, requestedId);
    if (existing) {
      return updateMyCollectionForUser(userId, requestedId, {
        title,
        passages,
        visibility,
      });
    }
  }
  const sql = await getSql();
  const count = await sql<{ n: string }>`
    select count(*)::text as n from user_collections where user_id = ${userId}
  `;
  if (Number(count[0]?.n ?? 0) >= MAX_COLLECTIONS) return { ok: false, error: "limit" };
  const id = requestedId || newId();
  await sql`
    insert into user_collections (id, user_id, title, visibility, passages, source_id, updated_at)
    values (${id}, ${userId}, ${title}, ${visibility}, ${JSON.stringify(passages)}, ${sourceId}, now())
  `;
  const collection = await getMyCollectionForUser(userId, id);
  if (!collection) return { ok: false, error: "invalid" };
  return { ok: true, collection };
}

export async function updateMyCollectionForUser(
  userId: string,
  id: string,
  raw: unknown,
): Promise<
  | { ok: true; collection: UserCollection }
  | { ok: false; error: "invalid" | "missing" }
> {
  if (!raw || typeof raw !== "object") return { ok: false, error: "invalid" };
  const body = raw as Record<string, unknown>;
  const current = await getMyCollectionForUser(userId, id);
  if (!current) return { ok: false, error: "missing" };
  const title =
    typeof body.title === "string"
      ? body.title.trim().replace(/\s+/g, " ").slice(0, 60) || current.title
      : current.title;
  const passages = body.passages != null ? cleanPassages(body.passages) : current.passages;
  const visibility =
    typeof body.visibility === "string" ? asVisibility(body.visibility) : current.visibility;
  const sql = await getSql();
  await sql`
    update user_collections
    set title = ${title}, passages = ${JSON.stringify(passages)}, visibility = ${visibility}, updated_at = now()
    where id = ${id} and user_id = ${userId}
  `;
  const collection = await getMyCollectionForUser(userId, id);
  if (!collection) return { ok: false, error: "missing" };
  return { ok: true, collection };
}

export async function deleteMyCollectionForUser(
  userId: string,
  id: string,
): Promise<{ ok: boolean }> {
  const sql = await getSql();
  const owned = await sql<{ id: string }>`
    select id from user_collections where id = ${id} and user_id = ${userId} limit 1
  `;
  if (!owned[0]) return { ok: false };
  await sql`delete from collection_grants where collection_id = ${id}`;
  await sql`delete from user_collections where id = ${id} and user_id = ${userId}`;
  return { ok: true };
}

/** Add a passage to an existing user collection (or create one titled from the theme). */
export async function savePassageToCollectionForUser(
  userId: string,
  raw: unknown,
): Promise<
  | { ok: true; collection: UserCollection }
  | { ok: false; error: "invalid" | "missing" | "limit" }
> {
  if (!raw || typeof raw !== "object") return { ok: false, error: "invalid" };
  const body = raw as Record<string, unknown>;
  const passage = parsePassage(body.passage ?? body);
  if (!passage) return { ok: false, error: "invalid" };

  const collectionId = typeof body.collectionId === "string" ? body.collectionId.trim() : "";
  if (collectionId) {
    const current = await getMyCollectionForUser(userId, collectionId);
    if (!current) return { ok: false, error: "missing" };
    const passages = cleanPassages([...current.passages, passage]);
    return updateMyCollectionForUser(userId, collectionId, { passages });
  }

  const title =
    typeof body.title === "string" && body.title.trim()
      ? body.title.trim().replace(/\s+/g, " ").slice(0, 60)
      : "Minha lista";
  return createMyCollectionForUser(userId, {
    title,
    passages: [passage],
    sourceId: typeof body.sourceId === "string" ? body.sourceId : "",
  });
}

export function bibleAppExists(appId: string) {
  return Boolean(appById(appId));
}
