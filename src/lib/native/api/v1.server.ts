/**
 * Native JSON API handlers for `/api/native/v1/*`.
 * Shared SQL with notebook-cloud createServerFns; callable from URLSession + Bearer.
 */
import { auth, authConfigured } from "@/lib/auth/server";
import { UnauthorizedError, getSessionUser } from "@/lib/auth/verify.server";
import { getSql } from "@/lib/db";
import { saveApnsDevice, dropApnsDevice } from "@/lib/native/devices.server";
import { asSpeaker, cleanBlocks, cleanTags, noteSpeakerIds, type Note, type Speaker } from "@/lib/notebook";
import {
  coerceIncomingNote,
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

export function noteFromRow(row: NoteRow): Note {
  const happened =
    typeof row.happened_at === "string" ? row.happened_at.slice(0, 10) : row.happened_at;
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
    select id, title, happened_at::text, tags, blocks, visibility, updated_at, speaker_id
    from notebook_notes
    where user_id = ${userId}
    order by happened_at desc, updated_at desc
    limit 200
  `;
  return rows.map((row) => noteToDocument(asLegacyForDocument(noteFromRow(row))));
}

export async function getNoteForUser(userId: string, noteId: string): Promise<NoteDocumentV1 | null> {
  const sql = await getSql();
  const rows = await sql<NoteRow>`
    select id, title, happened_at::text, tags, blocks, visibility, updated_at, speaker_id
    from notebook_notes
    where id = ${noteId} and user_id = ${userId}
    limit 1
  `;
  const row = rows[0];
  return row ? noteToDocument(asLegacyForDocument(noteFromRow(row))) : null;
}

export async function upsertNoteForUser(
  userId: string,
  raw: unknown,
): Promise<{ ok: true; note: NoteDocumentV1 } | { ok: false; error: "invalid" | "limit" }> {
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
  await sql`
    insert into notebook_notes (id, user_id, title, happened_at, tags, blocks, visibility, updated_at, speaker_id)
    values (
      ${note.id}, ${userId}, ${note.title}, ${note.happenedAt}::date,
      ${JSON.stringify(note.tags)}, ${JSON.stringify(note.blocks)}, ${note.visibility}, ${note.updatedAt}::timestamptz,
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
  `;
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
): Promise<{ note: NoteDocumentV1; speakers: Speaker[] } | null> {
  const { documentToNote } = await import("./note-document");
  const document = await getNoteForUser(userId, noteId);
  if (!document) return null;
  const speakers = await listSpeakersForUser(userId);
  const asLegacy = documentToNote(document);
  const used = new Set(asLegacy ? noteSpeakerIds(asLegacy as Note) : []);
  if (document.noteSpeakerId) used.add(document.noteSpeakerId);
  return { note: document, speakers: speakers.filter((s) => used.has(s.id)) };
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
      { method: "POST", path: "/auth/apple", auth: false, body: "{ identityToken, nonce? }" },
      { method: "POST", path: "/auth/from-cookie", auth: false, note: "Cookie session → bearer" },
      { method: "POST", path: "/auth/sign-out", auth: true },
      { method: "GET", path: "/session", auth: true },
      { method: "GET", path: "/notes", auth: true, returns: "NoteDocumentV1[]" },
      { method: "POST", path: "/notes", auth: true, body: "NoteDocumentV1" },
      { method: "GET", path: "/notes/:id", auth: true, returns: "{ note: NoteDocumentV1, speakers }" },
      { method: "PATCH", path: "/notes/:id", auth: true, body: "NoteDocumentV1" },
      { method: "DELETE", path: "/notes/:id", auth: true },
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
      { method: "GET", path: "/groups/:id/notes", auth: true },
      { method: "POST", path: "/groups/:id/notes", auth: true, body: "{ noteId }" },
      { method: "DELETE", path: "/groups/:id/notes/:noteId", auth: true },
      { method: "GET", path: "/notes/:id/groups", auth: true },
      { method: "GET", path: "/me", auth: true, returns: "{ me: profile+prefs+notify }" },
      { method: "PATCH", path: "/me", auth: true, body: "partial profile/prefs" },
      { method: "GET", path: "/prefs", auth: true },
      { method: "PATCH", path: "/prefs", auth: true, body: "CloudPrefs fields" },
      { method: "GET", path: "/notify-prefs", auth: true },
      { method: "PATCH", path: "/notify-prefs", auth: true, body: "{ reading?, friends?, shares?, groups? }" },
      { method: "GET", path: "/account/export", auth: true },
      { method: "POST", path: "/account/delete", auth: true },
    ],
  };
}

/** Keep auth import used for tree-shaking clarity in route module. */
export async function pingAuthConfigured() {
  return Boolean(auth && authConfigured);
}
