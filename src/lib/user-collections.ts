import { createServerFn } from "@tanstack/react-start";
import { authMiddleware } from "@/lib/auth/middleware";
import { bookById } from "@/lib/bible/books";
import { samePassage, type Passage } from "@/lib/bible/passage";
import { getSql } from "@/lib/db";
import type { CollectionPassage, CollectionVisibility, UserCollection } from "@/lib/user-collection";

export type { CollectionPassage, CollectionVisibility, UserCollection };

const MAX_COLLECTIONS = 40;
const MAX_PASSAGES = 80;
const MAX_TITLE = 60;
const MAX_NOTE = 80;

type Row = {
  id: string;
  title: string;
  slug: string;
  visibility: string;
  passages: string;
  source_id: string;
  updated_at: string;
};

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

function cleanTitle(value: string) {
  return value.trim().replace(/\s+/g, " ").slice(0, MAX_TITLE);
}

function cleanNote(value: unknown) {
  return typeof value === "string" ? value.trim().replace(/\s+/g, " ").slice(0, MAX_NOTE) : "";
}

export function cleanPassages(input: unknown): CollectionPassage[] {
  if (!Array.isArray(input)) return [];
  const out: CollectionPassage[] = [];
  for (const item of input) {
    if (!item || typeof item !== "object") continue;
    const row = item as Record<string, unknown>;
    const bookId = typeof row.bookId === "string" ? row.bookId : "";
    const book = bookById(bookId);
    const chapter = Number(row.chapter);
    if (!book || !Number.isInteger(chapter) || chapter < 1 || chapter > book.verses.length) continue;
    const verseStart =
      row.verseStart == null || row.verseStart === "" ? null : Number(row.verseStart);
    const verseEnd = row.verseEnd == null || row.verseEnd === "" ? null : Number(row.verseEnd);
    const start = verseStart && Number.isInteger(verseStart) && verseStart > 0 ? verseStart : null;
    const end = verseEnd && Number.isInteger(verseEnd) && verseEnd > 0 ? verseEnd : null;
    const passage: CollectionPassage = {
      bookId,
      chapter,
      verseStart: start,
      verseEnd: end,
      title: cleanNote(row.title),
    };
    if (out.some((existing) => samePassage(existing, passage))) continue;
    out.push(passage);
    if (out.length >= MAX_PASSAGES) break;
  }
  return out;
}

function fromRow(row: Row): UserCollection {
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

function newId() {
  return crypto.randomUUID().replaceAll("-", "");
}

export const listMyCollections = createServerFn({ method: "GET" })
  .middleware([authMiddleware])
  .handler(async ({ context }) => {
    const sql = await getSql();
    const rows = await sql<Row>`
      select id, title, slug, visibility, passages, coalesce(source_id, '') as source_id, updated_at
      from user_collections
      where user_id = ${context.userId}
      order by updated_at desc
    `;
    return rows.map(fromRow);
  });

export const getMyCollection = createServerFn({ method: "GET" })
  .middleware([authMiddleware])
  .validator((data: { id: string }) => data)
  .handler(async ({ context, data }) => {
    const sql = await getSql();
    const rows = await sql<Row>`
      select id, title, slug, visibility, passages, coalesce(source_id, '') as source_id, updated_at
      from user_collections
      where id = ${data.id} and user_id = ${context.userId}
    `;
    return rows[0] ? fromRow(rows[0]) : null;
  });

export const getSharedCollection = createServerFn({ method: "GET" })
  .validator((data: { id: string }) => data)
  .handler(async ({ data }) => {
    const sql = await getSql();
    const rows = await sql<Row>`
      select id, title, slug, visibility, passages, coalesce(source_id, '') as source_id, updated_at
      from user_collections
      where id = ${data.id}
    `;
    const row = rows[0];
    if (!row) return null;
    const vis = asVisibility(row.visibility);
    if (vis === "private") return null;
    return fromRow(row);
  });

export const listGrantedCollections = createServerFn({ method: "GET" })
  .middleware([authMiddleware])
  .handler(async ({ context }) => {
    const sql = await getSql();
    const rows = await sql<Row>`
      select c.id, c.title, c.slug, c.visibility, c.passages, coalesce(c.source_id, '') as source_id, c.updated_at
      from user_collections c
      join collection_grants g on g.collection_id = c.id
      where g.user_id = ${context.userId}
      order by g.created_at desc
    `;
    return rows.map(fromRow);
  });

export const getGrantedCollection = createServerFn({ method: "GET" })
  .middleware([authMiddleware])
  .validator((data: { id: string }) => data)
  .handler(async ({ context, data }) => {
    const sql = await getSql();
    const grant = await sql<{ collection_id: string }>`
      select collection_id from collection_grants
      where collection_id = ${data.id} and user_id = ${context.userId}
    `;
    if (!grant[0]) return null;
    const rows = await sql<Row>`
      select id, title, slug, visibility, passages, coalesce(source_id, '') as source_id, updated_at
      from user_collections
      where id = ${data.id}
    `;
    return rows[0] ? fromRow(rows[0]) : null;
  });

export const createMyCollection = createServerFn({ method: "POST" })
  .middleware([authMiddleware])
  .validator((data: { title: string; passages?: Passage[]; sourceId?: string; id?: string }) => data)
  .handler(async ({ context, data }) => {
    const title = cleanTitle(data.title) || "Coleção";
    const passages = cleanPassages(data.passages ?? []);
    const sql = await getSql();
    const count = await sql<{ n: number }>`
      select count(*)::int as n from user_collections where user_id = ${context.userId}
    `;
    if (Number(count[0]?.n ?? 0) >= MAX_COLLECTIONS) {
      return { ok: false as const, error: "limit" as const };
    }
    const requested = typeof data.id === "string" ? data.id.replace(/[^a-f0-9]/g, "").slice(0, 32) : "";
    const id = requested.length >= 16 ? requested : newId();
    const sourceId = typeof data.sourceId === "string" ? data.sourceId.slice(0, 64) : "";
    await sql`
      insert into user_collections (id, user_id, title, visibility, passages, source_id, updated_at)
      values (${id}, ${context.userId}, ${title}, ${"private"}, ${JSON.stringify(passages)}, ${sourceId}, now())
    `;
    void import("@/lib/catalog-push.server")
      .then((m) => m.pushCatalogHintToUser(context.userId, "themes_updated"))
      .catch(() => undefined);
    return { ok: true as const, id };
  });

export const updateMyCollection = createServerFn({ method: "POST" })
  .middleware([authMiddleware])
  .validator((data: { id: string; title?: string; passages?: Passage[]; visibility?: CollectionVisibility }) => data)
  .handler(async ({ context, data }) => {
    const sql = await getSql();
    const rows = await sql<Row>`
      select id, title, slug, visibility, passages, coalesce(source_id, '') as source_id, updated_at
      from user_collections
      where id = ${data.id} and user_id = ${context.userId}
    `;
    const current = rows[0] ? fromRow(rows[0]) : null;
    if (!current) return { ok: false as const, error: "missing" as const };
    const title = data.title != null ? cleanTitle(data.title) || current.title : current.title;
    const passages = data.passages ? cleanPassages(data.passages) : current.passages;
    const visibility = data.visibility ? asVisibility(data.visibility) : current.visibility;
    await sql`
      update user_collections
      set title = ${title}, passages = ${JSON.stringify(passages)}, visibility = ${visibility}, updated_at = now()
      where id = ${data.id} and user_id = ${context.userId}
    `;
    void import("@/lib/catalog-push.server")
      .then((m) => m.pushCatalogHintToUser(context.userId, "themes_updated"))
      .catch(() => undefined);
    return { ok: true as const };
  });

export const remixCollection = createServerFn({ method: "POST" })
  .middleware([authMiddleware])
  .validator((data: { id: string }) => data)
  .handler(async ({ context, data }) => {
    const sql = await getSql();
    const rows = await sql<Row & { user_id: string }>`
      select id, user_id, title, slug, visibility, passages, coalesce(source_id, '') as source_id, updated_at
      from user_collections
      where id = ${data.id}
    `;
    const row = rows[0];
    if (!row) return { ok: false as const, error: "missing" as const };
    const vis = asVisibility(row.visibility);
    if (vis === "private" && row.user_id !== context.userId) {
      return { ok: false as const, error: "missing" as const };
    }
    const count = await sql<{ n: number }>`
      select count(*)::int as n from user_collections where user_id = ${context.userId}
    `;
    if (Number(count[0]?.n ?? 0) >= MAX_COLLECTIONS) {
      return { ok: false as const, error: "limit" as const };
    }
    const source = fromRow(row);
    const id = newId();
    await sql`
      insert into user_collections (id, user_id, title, visibility, passages, source_id, updated_at)
      values (${id}, ${context.userId}, ${source.title}, ${"private"}, ${JSON.stringify(source.passages)}, ${source.id}, now())
    `;
    void import("@/lib/notify.server")
      .then((mod) => mod.notifyCollectionRemix(context.userId, row.user_id, source.title, source.id))
      .catch(() => undefined);
    void import("@/lib/catalog-push.server")
      .then((m) => m.pushCatalogHintToUser(context.userId, "themes_updated"))
      .catch(() => undefined);
    return { ok: true as const, id };
  });

export const deleteMyCollection = createServerFn({ method: "POST" })
  .middleware([authMiddleware])
  .validator((data: { id: string }) => data)
  .handler(async ({ context, data }) => {
    const sql = await getSql();
    await sql`delete from user_collections where id = ${data.id} and user_id = ${context.userId}`;
    void import("@/lib/catalog-push.server")
      .then((m) => m.pushCatalogHintToUser(context.userId, "themes_updated"))
      .catch(() => undefined);
    return { ok: true as const };
  });
