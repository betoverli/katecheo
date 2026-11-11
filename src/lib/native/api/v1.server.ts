/**
 * Native JSON API handlers for `/api/native/v1/*`.
 * Shared SQL with notebook-cloud createServerFns; callable from URLSession + Bearer.
 */
import { auth, authConfigured } from "@/lib/auth/server";
import { UnauthorizedError, getSessionUser } from "@/lib/auth/verify.server";
import { getSql } from "@/lib/db";
import { saveApnsDevice, dropApnsDevice } from "@/lib/native/devices.server";
import { asSpeaker, cleanBlocks, cleanTags, noteSpeakerIds, type Note, type Speaker } from "@/lib/notebook";
import { htmlToDocumentBlocks, looksLikeHtml } from "./html-to-document";
import {
  coerceIncomingNote,
  cleanDocBlocks,
  documentToNote,
  encodeDocumentStorage,
  isDocumentStorage,
  looksLikeDocBlocksArray,
  noteToDocument,
  type LegacyNote,
  type NoteDocumentV1,
  NOTE_DOCUMENT_SCHEMA_VERSION,
} from "./note-document";

type NoteRow = {
  id: string;
  title: string;
  happened_at: string;
  tags: string;
  blocks: string;
  blocks_backup?: string | null;
  visibility: string;
  updated_at: string;
  speaker_id?: string | null;
};

type SpeakerRow = {
  id: string;
  name: string;
  color: string;
  updated_at: string;
};

function parseJson<T>(raw: string, fallback: T): T {
  try {
    return JSON.parse(raw) as T;
  } catch {
    return fallback;
  }
}

/**
 * Parse `notebook_notes.blocks` into NoteDocumentV1.
 * Supports: V1 storage envelope, raw V1 block arrays, legacy Note.blocks JSON, HTML.
 * HTML conversion is lazy + idempotent (caller may persist backup + rewritten JSON).
 */
export function documentFromRow(row: NoteRow): {
  document: NoteDocumentV1;
  migratedFromHtml: boolean;
  originalBlocksRaw: string;
} {
  const happened =
    typeof row.happened_at === "string" ? row.happened_at.slice(0, 10) : String(row.happened_at).slice(0, 10);
  const rawBlocks = typeof row.blocks === "string" ? row.blocks : JSON.stringify(row.blocks ?? []);
  const baseMeta = {
    schemaVersion: NOTE_DOCUMENT_SCHEMA_VERSION,
    id: row.id,
    title: row.title ?? "",
    happenedAt: happened,
    tags: cleanTags(parseJson(row.tags, [])),
    noteSpeakerId: row.speaker_id || null,
    visibility: (row.visibility === "unlisted" ? "unlisted" : "private") as "private" | "unlisted",
    updatedAt: String(row.updated_at ?? ""),
  };

  if (looksLikeHtml(rawBlocks)) {
    return {
      document: {
        ...baseMeta,
        body: { blocks: htmlToDocumentBlocks(rawBlocks) },
      },
      migratedFromHtml: true,
      originalBlocksRaw: rawBlocks,
    };
  }

  const parsed = parseJson<unknown>(rawBlocks, []);
  if (isDocumentStorage(parsed)) {
    return {
      document: { ...baseMeta, body: { blocks: cleanDocBlocks(parsed.blocks) } },
      migratedFromHtml: false,
      originalBlocksRaw: rawBlocks,
    };
  }
  if (looksLikeDocBlocksArray(parsed)) {
    return {
      document: { ...baseMeta, body: { blocks: cleanDocBlocks(parsed) } },
      migratedFromHtml: false,
      originalBlocksRaw: rawBlocks,
    };
  }

  const legacy = {
    id: row.id,
    title: row.title ?? "",
    happenedAt: happened,
    tags: cleanTags(parseJson(row.tags, [])),
    speakerId: row.speaker_id || null,
    blocks: cleanBlocks(Array.isArray(parsed) ? parsed : []),
    visibility: (row.visibility === "unlisted" ? "unlisted" : "private") as "private" | "unlisted",
    updatedAt: String(row.updated_at ?? ""),
  } satisfies Note;
  return {
    document: noteToDocument(asLegacyForDocument(legacy)),
    migratedFromHtml: false,
    originalBlocksRaw: rawBlocks,
  };
}

export function noteFromRow(row: NoteRow): Note {
  const { document } = documentFromRow(row);
  const legacy = documentToNote(document);
  if (legacy) return legacy as Note;
  const happened =
    typeof row.happened_at === "string" ? row.happened_at.slice(0, 10) : String(row.happened_at).slice(0, 10);
  return {
    id: row.id,
    title: row.title ?? "",
    happenedAt: happened,
    tags: cleanTags(parseJson(row.tags, [])),
    speakerId: row.speaker_id || null,
    blocks: cleanBlocks(
      parseJson(typeof row.blocks === "string" ? row.blocks : JSON.stringify(row.blocks ?? []), []),
    ),
    visibility: row.visibility === "unlisted" ? "unlisted" : "private",
    updatedAt: String(row.updated_at ?? ""),
  };
}

function asLegacyForDocument(note: Note): LegacyNote {
  // Note and LegacyNote are structurally identical; keep an explicit cast at the boundary.
  return note as LegacyNote;
}

/** Persist V1 body; when migrating from HTML, keep the original in blocks_backup once. */
async function persistDocumentStorage(
  userId: string,
  document: NoteDocumentV1,
  opts?: { backupHtml?: string | null },
): Promise<void> {
  const sql = await getSql();
  const encoded = encodeDocumentStorage(document.body.blocks);
  if (opts?.backupHtml) {
    await sql`
      update notebook_notes
      set blocks = ${encoded},
          blocks_backup = coalesce(blocks_backup, ${opts.backupHtml}),
          updated_at = ${document.updatedAt}::timestamptz
      where id = ${document.id} and user_id = ${userId}
    `;
    return;
  }
  await sql`
    update notebook_notes
    set blocks = ${encoded}
    where id = ${document.id} and user_id = ${userId}
      and blocks is distinct from ${encoded}
  `;
}

export function speakerFromRow(row: SpeakerRow): Speaker {
  return {
    id: row.id,
    name: row.name,
    color: row.color,
    updatedAt: String(row.updated_at ?? ""),
  };
}

/** Resolve user from cookie and/or Authorization: Bearer (Better Auth bearer plugin). */
export async function resolveNativeUser(request: Request): Promise<{ id: string; email: string | null }> {
  const headerAuth = request.headers.get("authorization");
  const bearer = headerAuth?.match(/^Bearer\s+(.+)$/i)?.[1]?.trim();
  if (authConfigured || bearer) {
    const user = await getSessionUser(bearer);
    if (user) return user;
  }
  // Dev-only fallback when auth is off and no DB (same contract as requireUserId).
  if (!authConfigured && !process.env.DATABASE_URL?.trim()) {
    return { id: "dev-user", email: null };
  }
  throw new UnauthorizedError();
}

export async function getNativeSession(userId: string, email: string | null) {
  return {
    ok: true as const,
    user: { id: userId, email },
    api: "native/v1",
  };
}

export async function listNotesForUser(userId: string): Promise<NoteDocumentV1[]> {
  const sql = await getSql();
  const rows = await sql<NoteRow>`
    select id, title, happened_at::text, tags, blocks, blocks_backup, visibility, updated_at, speaker_id
    from notebook_notes
    where user_id = ${userId}
    order by happened_at desc, updated_at desc
    limit 200
  `;
  const out: NoteDocumentV1[] = [];
  for (const row of rows) {
    const parsed = documentFromRow(row);
    if (parsed.migratedFromHtml) {
      try {
        await persistDocumentStorage(userId, parsed.document, { backupHtml: parsed.originalBlocksRaw });
      } catch {
        /* read still succeeds even if rewrite fails */
      }
    }
    out.push(parsed.document);
  }
  return out;
}

export async function getNoteForUser(userId: string, noteId: string): Promise<NoteDocumentV1 | null> {
  const sql = await getSql();
  const rows = await sql<NoteRow>`
    select id, title, happened_at::text, tags, blocks, blocks_backup, visibility, updated_at, speaker_id
    from notebook_notes
    where id = ${noteId} and user_id = ${userId}
    limit 1
  `;
  const row = rows[0];
  if (!row) return null;
  const parsed = documentFromRow(row);
  if (parsed.migratedFromHtml) {
    try {
      await persistDocumentStorage(userId, parsed.document, { backupHtml: parsed.originalBlocksRaw });
    } catch {
      /* ignore */
    }
  }
  return parsed.document;
}

export async function upsertNoteForUser(
  userId: string,
  raw: unknown,
): Promise<{ ok: true; note: NoteDocumentV1 } | { ok: false; error: "invalid" | "limit" | "conflict" }> {
  const coerced = coerceIncomingNote(raw);
  if (!coerced) return { ok: false, error: "invalid" };
  const { note, document } = coerced;
  const sql = await getSql();
  const count = await sql<{ n: string }>`
    select count(*)::text as n from notebook_notes where user_id = ${userId}
  `;
  const existing = await sql<{ id: string }>`
    select id from notebook_notes where id = ${note.id} and user_id = ${userId}
  `;
  if (!existing[0] && Number(count[0]?.n ?? 0) >= 200) return { ok: false, error: "limit" };
  const encodedBlocks = encodeDocumentStorage(document.body.blocks);
  const foreign = await sql<{ id: string }>`
    select id from notebook_notes where id = ${note.id} and user_id <> ${userId} limit 1
  `;
  if (foreign[0]) return { ok: false, error: "conflict" };

  const written = await sql<{ id: string }>`
    insert into notebook_notes (id, user_id, title, happened_at, tags, blocks, visibility, updated_at, speaker_id)
    values (
      ${note.id}, ${userId}, ${note.title}, ${note.happenedAt}::date,
      ${JSON.stringify(note.tags)}, ${encodedBlocks}, ${note.visibility}, ${note.updatedAt}::timestamptz,
      ${note.speakerId}
    )
    on conflict (id) do update set
      title = excluded.title,
      happened_at = excluded.happened_at,
      tags = excluded.tags,
      blocks = excluded.blocks,
      visibility = excluded.visibility,
      updated_at = excluded.updated_at,
      speaker_id = excluded.speaker_id
    where notebook_notes.user_id = ${userId}
      and notebook_notes.updated_at <= excluded.updated_at
    returning id
  `;
  // Conflict owned by us but stale updatedAt → no row returned; still treat as ok (idempotent older write).
  if (!written[0] && !existing[0]) return { ok: false, error: "invalid" };
  return { ok: true, note: document };
}

export async function deleteNoteForUser(userId: string, noteId: string): Promise<{ ok: boolean }> {
  const sql = await getSql();
  const owned = await sql<{ id: string }>`
    select id from notebook_notes where id = ${noteId} and user_id = ${userId} limit 1
  `;
  if (!owned[0]) return { ok: false };
  await sql`delete from notebook_group_notes where note_id = ${noteId}`;
  await sql`delete from note_grants where note_id = ${noteId}`;
  await sql`delete from notebook_notes where id = ${noteId} and user_id = ${userId}`;
  return { ok: true };
}

export async function listSpeakersForUser(userId: string): Promise<Speaker[]> {
  const sql = await getSql();
  const rows = await sql<SpeakerRow>`
    select id, name, color, updated_at from notebook_speakers
    where user_id = ${userId}
    order by name
  `;
  return rows.map(speakerFromRow);
}

export async function upsertSpeakerForUser(
  userId: string,
  raw: unknown,
): Promise<{ ok: true } | { ok: false; error: "invalid" }> {
  const speaker = asSpeaker(raw);
  if (!speaker) return { ok: false, error: "invalid" };
  const sql = await getSql();
  await sql`
    insert into notebook_speakers (id, user_id, name, color, updated_at)
    values (${speaker.id}, ${userId}, ${speaker.name}, ${speaker.color}, ${speaker.updatedAt}::timestamptz)
    on conflict (id) do update set
      name = excluded.name,
      color = excluded.color,
      updated_at = excluded.updated_at
    where notebook_speakers.user_id = ${userId}
      and notebook_speakers.updated_at <= excluded.updated_at
  `;
  return { ok: true };
}

export async function deleteSpeakerForUser(userId: string, speakerId: string): Promise<{ ok: boolean }> {
  const sql = await getSql();
  await sql`delete from notebook_speakers where id = ${speakerId} and user_id = ${userId}`;
  return { ok: true };
}

export async function getNoteWithSpeakersForUser(
  userId: string,
  noteId: string,
): Promise<{ note: NoteDocumentV1; speakers: Speaker[]; via?: "owned" | "grant" } | null> {
  // Owned notes stay on the fast path; grants reuse social helper (note_grants join).
  const owned = await getNoteForUser(userId, noteId);
  if (owned) {
    const { documentToNote } = await import("./note-document");
    const speakers = await listSpeakersForUser(userId);
    const asLegacy = documentToNote(owned);
    const used = new Set(asLegacy ? noteSpeakerIds(asLegacy as Note) : []);
    if (owned.noteSpeakerId) used.add(owned.noteSpeakerId);
    return { note: owned, speakers: speakers.filter((s) => used.has(s.id)), via: "owned" };
  }
  const { getAccessibleNoteForUser } = await import("./v1-social.server");
  const accessible = await getAccessibleNoteForUser(userId, noteId);
  if (!accessible || accessible.via !== "grant") return null;
  return { note: accessible.note, speakers: accessible.speakers, via: "grant" };
}

export { saveApnsDevice, dropApnsDevice };

/** OpenAPI-ish discovery document for Swift stubs / docs. */
export function nativeV1Catalog() {
  return {
    ok: true as const,
    version: 1,
    noteSchemaVersion: NOTE_DOCUMENT_SCHEMA_VERSION,
    base: "/api/native/v1",
    auth: "Authorization: Bearer <session-token> (Better Auth bearer) or session cookie",
    noteDocument:
      "Notes use NoteDocumentV1 (schemaVersion + body.blocks). Not HTML. See docs/ios-native-migration.md § Document model.",
    endpoints: [
      { method: "GET", path: "/auth/providers", auth: false },
      { method: "POST", path: "/auth/claim", auth: false, body: "{ code, verifier }" },
      { method: "POST", path: "/auth/email", auth: false, body: "{ email, password }" },
      {
        method: "POST",
        path: "/auth/email/sign-up",
        auth: false,
        body: "{ name, email, password }",
      },
      {
        method: "POST",
        path: "/auth/email/forgot-password",
        auth: false,
        body: "{ email, locale?}",
        note: "Always 200 generic; emails 6-digit code via Resend when credential account exists",
      },
      {
        method: "POST",
        path: "/auth/email/reset-password",
        auth: false,
        body: "{ email, code, newPassword }",
        returns: "{ ok, token } same as email sign-in",
      },
      {
        method: "POST",
        path: "/auth/apple",
        auth: false,
        body: "{ identityToken, authorizationCode?, nonce?, fullName? }",
      },
      { method: "POST", path: "/auth/from-cookie", auth: false, note: "Cookie session → bearer" },
      { method: "POST", path: "/auth/sign-out", auth: true },
      { method: "GET", path: "/session", auth: true },
      { method: "GET", path: "/notes", auth: true, returns: "NoteDocumentV1[]" },
      { method: "POST", path: "/notes", auth: true, body: "NoteDocumentV1" },
      { method: "GET", path: "/notes/granted", auth: true, returns: "NoteDocumentV1[] via note_grants" },
      { method: "GET", path: "/notes/:id", auth: true, returns: "{ note: NoteDocumentV1, speakers, via? }" },
      { method: "PATCH", path: "/notes/:id", auth: true, body: "NoteDocumentV1" },
      { method: "DELETE", path: "/notes/:id", auth: true },
      { method: "GET", path: "/links", auth: true, returns: "{ friends, incoming, outgoing }" },
      { method: "GET", path: "/links/search", auth: true, query: "q", returns: "{ people }" },
      { method: "POST", path: "/links/request", auth: true, body: "{ handle }" },
      { method: "POST", path: "/links/accept", auth: true, body: "{ handle }" },
      { method: "POST", path: "/links/decline", auth: true, body: "{ handle }", note: "also cancels outgoing" },
      { method: "POST", path: "/links/remove", auth: true, body: "{ handle }", note: "unfriend both sides + grants" },
      {
        method: "GET",
        path: "/notifications",
        auth: true,
        query: "cursor?, limit?, unreadOnly?",
        returns: "{ items, nextCursor, unread }",
      },
      {
        method: "GET",
        path: "/notifications/summary",
        auth: true,
        returns: "{ unread, byKind, items, nextCursor }",
      },
      { method: "POST", path: "/notifications/read", auth: true, body: "{ id? }" },
      { method: "DELETE", path: "/notifications/:id", auth: true },
      { method: "POST", path: "/notifications/clear", auth: true },
      { method: "GET", path: "/speakers", auth: true },
      { method: "POST", path: "/speakers", auth: true, body: "Speaker" },
      { method: "DELETE", path: "/speakers/:id", auth: true },
      { method: "POST", path: "/devices/apns", auth: true, body: "{ token, sandbox? }" },
      { method: "DELETE", path: "/devices/apns", auth: true, body: "{ token? }" },
      { method: "GET", path: "/groups", auth: true },
      { method: "POST", path: "/groups", auth: true, body: "{ name, description?, visibility? }" },
      { method: "GET", path: "/groups/:id", auth: true },
      { method: "PATCH", path: "/groups/:id", auth: true, body: "{ name?, description?, visibility?, postPolicy? }" },
      { method: "DELETE", path: "/groups/:id", auth: true },
      {
        method: "GET",
        path: "/groups/:id/notes",
        auth: true,
        note: "Supports updatedSince + If-None-Match/ETag (304)",
      },
      { method: "POST", path: "/groups/:id/notes", auth: true, body: "{ noteId }" },
      { method: "DELETE", path: "/groups/:id/notes/:noteId", auth: true },
      { method: "GET", path: "/groups/:id/members", auth: true },
      { method: "POST", path: "/groups/:id/members/decide", auth: true, body: "{ userId, accept }" },
      { method: "POST", path: "/groups/:id/members/role", auth: true, body: "{ userId, role }" },
      { method: "DELETE", path: "/groups/:id/members/:userId", auth: true },
      { method: "GET", path: "/notes/:id/groups", auth: true },
      { method: "GET", path: "/me", auth: true, returns: "{ me: profile+prefs+notify }" },
      { method: "PATCH", path: "/me", auth: true, body: "partial profile/prefs" },
      { method: "GET", path: "/prefs", auth: true },
      { method: "GET", path: "/plans", auth: false, note: "Reading plans catalog (same as /api/plans)" },
      { method: "POST", path: "/plans/start", auth: true, body: "{ planId }" },
      { method: "POST", path: "/plans/stop", auth: true, body: "{ planId }" },
      { method: "POST", path: "/plans/mark", auth: true, body: "{ planId, day, on }" },
      { method: "POST", path: "/plans/reset", auth: true, body: "{ planId }" },
      { method: "POST", path: "/plans/invite", auth: true, body: "{ planId }" },
      { method: "POST", path: "/plans/join", auth: true, body: "{ id }" },
      { method: "PATCH", path: "/prefs", auth: true, body: "CloudPrefs fields" },
      { method: "GET", path: "/notify-prefs", auth: true },
      { method: "PATCH", path: "/notify-prefs", auth: true, body: "{ reading?, friends?, shares?, groups? }" },
      { method: "GET", path: "/account/export", auth: true },
      { method: "POST", path: "/account/delete", auth: true },
      { method: "GET", path: "/bible/books", auth: false, returns: "book catalog + verse counts" },
      { method: "GET", path: "/bible/apps", auth: false, returns: "apps + translations" },
      { method: "GET|POST", path: "/bible/link", auth: false, note: "optional Bearer merges prefs" },
      { method: "GET", path: "/bible/themes", auth: false, note: "wraps /api/collections" },
      {
        method: "POST",
        path: "/verses/append",
        auth: true,
        body: "{ bookId, chapter, verseStart?, verseEnd?, noteId? }",
        note: "appends bibleRef span to today's note (NoteDocumentV1)",
      },
      { method: "GET|POST", path: "/my-collections", auth: true },
      { method: "GET|PATCH|DELETE", path: "/my-collections/:id", auth: true },
      { method: "POST", path: "/my-collections/save", auth: true, body: "{ passage, collectionId? }" },
    ],
  };
}

/** Keep auth import used for tree-shaking clarity in route module. */
export async function pingAuthConfigured() {
  return Boolean(auth && authConfigured);
}
