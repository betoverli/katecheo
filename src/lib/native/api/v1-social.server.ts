/**
 * Native Bearer wraps for friends links, granted notes, and notifications inbox.
 * Reuses existing web SQL / notify.server — no schema changes.
 */
import { getSql, type Sql } from "@/lib/db";
import { allowRequest } from "@/lib/rate-limit";
import { noteSpeakerIds, type Note, type Speaker } from "@/lib/notebook";
import { type NoteDocumentV1 } from "./note-document";
import { documentFromRow, speakerFromRow } from "./v1.server";

export type NativeLinkPerson = {
  userId: string;
  handle: string;
  firstName: string;
  lastName: string;
  avatarId: string;
  avatarUrl: string;
};

export type NativeLinksPayload = {
  friends: NativeLinkPerson[];
  incoming: NativeLinkPerson[];
  outgoing: NativeLinkPerson[];
};

type PrefRow = {
  user_id: string;
  handle: string;
  first_name: string;
  last_name: string;
  avatar_id: string;
  avatar_url: string;
};

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

const MAX_FRIENDS = 80;

function cleanHandle(value: string) {
  return value.trim().replace(/^@+/, "").toLowerCase().replace(/[^a-z0-9_]/g, "").slice(0, 20);
}

function person(row: PrefRow): NativeLinkPerson {
  return {
    userId: row.user_id,
    handle: row.handle ?? "",
    firstName: row.first_name ?? "",
    lastName: row.last_name ?? "",
    avatarId: row.avatar_id || "book",
    avatarUrl: row.avatar_url ?? "",
  };
}

async function prefsByHandle(sql: Sql, handle: string) {
  const rows = await sql<PrefRow>`
    select user_id, handle, first_name, last_name, avatar_id, avatar_url
    from user_prefs
    where handle = ${handle}
    limit 1
  `;
  return rows[0] ?? null;
}

async function prefsById(sql: Sql, userId: string) {
  const rows = await sql<PrefRow>`
    select user_id, handle, first_name, last_name, avatar_id, avatar_url
    from user_prefs
    where user_id = ${userId}
    limit 1
  `;
  return rows[0] ?? null;
}

async function friendCount(sql: Sql, userId: string) {
  const rows = await sql<{ n: number }>`
    select count(*)::int as n from user_links
    where status = 'accepted' and (requester_id = ${userId} or addressee_id = ${userId})
  `;
  return Number(rows[0]?.n ?? 0);
}

/** Same shape as web `listLinks`. Scoped to the authenticated user. */
export async function listLinksForUser(userId: string): Promise<NativeLinksPayload> {
  const sql = await getSql();
  const rows = await sql<{ requester_id: string; addressee_id: string; status: string }>`
    select requester_id, addressee_id, status
    from user_links
    where requester_id = ${userId} or addressee_id = ${userId}
    order by created_at desc
  `;
  const friends: NativeLinkPerson[] = [];
  const incoming: NativeLinkPerson[] = [];
  const outgoing: NativeLinkPerson[] = [];
  for (const row of rows) {
    const otherId = row.requester_id === userId ? row.addressee_id : row.requester_id;
    const pref = await prefsById(sql, otherId);
    if (!pref) continue;
    const item = person(pref);
    if (row.status === "accepted") friends.push(item);
    else if (row.requester_id === userId) outgoing.push(item);
    else incoming.push(item);
  }
  return { friends, incoming, outgoing };
}

/** Same semantics as web `acceptLink` (by handle, addressee = me). */
export async function acceptLinkForUser(
  userId: string,
  handleRaw: string,
): Promise<{ ok: true } | { ok: false; error: "missing" | "limit" | "rate" }> {
  if (!allowRequest(`link-acc:${userId}`, 30, 86_400_000)) {
    return { ok: false, error: "rate" };
  }
  const handle = cleanHandle(handleRaw);
  const sql = await getSql();
  const other = handle ? await prefsByHandle(sql, handle) : null;
  if (!other) return { ok: false, error: "missing" };
  if ((await friendCount(sql, userId)) >= MAX_FRIENDS) return { ok: false, error: "limit" };
  const rows = await sql<{ id: string }>`
    update user_links set status = 'accepted'
    where requester_id = ${other.user_id} and addressee_id = ${userId} and status = 'pending'
    returning id
  `;
  if (!rows[0]) return { ok: false, error: "missing" };
  void import("@/lib/notify.server").then((mod) =>
    mod.notifySocial(userId, other.user_id, "friends", "notifyLinkAcceptedTitle", "notifyLinkAcceptedBody", {
      href: "/profile/friends",
    }),
  );
  return { ok: true };
}

/** Same semantics as web `declineLink` (by handle). */
export async function declineLinkForUser(
  userId: string,
  handleRaw: string,
): Promise<{ ok: true } | { ok: false; error: "missing" }> {
  const handle = cleanHandle(handleRaw);
  const sql = await getSql();
  const other = handle ? await prefsByHandle(sql, handle) : null;
  if (!other) return { ok: false, error: "missing" };
  await sql`
    delete from user_links
    where (requester_id = ${other.user_id} and addressee_id = ${userId})
       or (requester_id = ${userId} and addressee_id = ${other.user_id})
  `;
  await sql`
    delete from collection_grants
    where (from_id = ${userId} and user_id = ${other.user_id})
       or (from_id = ${other.user_id} and user_id = ${userId})
  `;
  await sql`
    delete from note_grants
    where (from_id = ${userId} and user_id = ${other.user_id})
       or (from_id = ${other.user_id} and user_id = ${userId})
  `;
  return { ok: true };
}

/** Same SQL as web `listGrantedNotes`, returned as NoteDocumentV1 for native clients. */
export async function listGrantedNotesForUser(userId: string): Promise<NoteDocumentV1[]> {
  const sql = await getSql();
  const rows = await sql<NoteRow>`
    select n.id, n.title, n.happened_at::text, n.tags, n.blocks, n.blocks_backup, n.visibility, n.updated_at, n.speaker_id
    from notebook_notes n
    join note_grants g on g.note_id = n.id
    where g.user_id = ${userId}
    order by n.happened_at desc
    limit 80
  `;
  return rows.map((row) => documentFromRow(row).document);
}

/** Grant-or-own access for GET /notes/:id (read). Never returns another user's private note. */
export async function getAccessibleNoteForUser(
  userId: string,
  noteId: string,
): Promise<{ note: NoteDocumentV1; speakers: Speaker[]; via: "owned" | "grant" } | null> {
  const sql = await getSql();
  const owned = await sql<NoteRow>`
    select id, title, happened_at::text, tags, blocks, blocks_backup, visibility, updated_at, speaker_id
    from notebook_notes
    where id = ${noteId} and user_id = ${userId}
    limit 1
  `;
  if (owned[0]) {
    const document = documentFromRow(owned[0]).document;
    const speakers = await listOwnerSpeakersForNote(sql, userId, document);
    return { note: document, speakers, via: "owned" };
  }
  const granted = await sql<NoteRow>`
    select n.id, n.title, n.happened_at::text, n.tags, n.blocks, n.blocks_backup, n.visibility, n.updated_at, n.speaker_id
    from notebook_notes n
    join note_grants g on g.note_id = n.id
    where n.id = ${noteId} and g.user_id = ${userId}
    limit 1
  `;
  if (!granted[0]) return null;
  const document = documentFromRow(granted[0]).document;
  const owner = await sql<{ user_id: string }>`
    select user_id from notebook_notes where id = ${noteId} limit 1
  `;
  const speakers = owner[0]
    ? await listOwnerSpeakersForNote(sql, owner[0].user_id, document)
    : [];
  return { note: document, speakers, via: "grant" };
}

async function listOwnerSpeakersForNote(
  sql: Sql,
  ownerId: string,
  document: NoteDocumentV1,
): Promise<Speaker[]> {
  const { documentToNote } = await import("./note-document");
  const asLegacy = documentToNote(document);
  const used = new Set(asLegacy ? noteSpeakerIds(asLegacy as Note) : []);
  if (document.noteSpeakerId) used.add(document.noteSpeakerId);
  if (used.size === 0) return [];
  const rows = await sql<SpeakerRow>`
    select id, name, color, updated_at from notebook_speakers
    where user_id = ${ownerId}
  `;
  return rows.map(speakerFromRow).filter((s) => used.has(s.id));
}

export async function listNotificationsForUser(userId: string) {
  const { listInbox, maybeSendDigests } = await import("@/lib/notify.server");
  void maybeSendDigests().catch(() => undefined);
  const items = await listInbox(userId);
  const { unreadCount } = await import("@/lib/notify.server");
  const unread = await unreadCount(userId);
  return { items, unread };
}

/** Idempotent: only sets read_at when still null; always scoped to userId. */
export async function markNotificationsReadForUser(userId: string, id?: string) {
  const { markRead } = await import("@/lib/notify.server");
  await markRead(userId, id);
  return { ok: true as const };
}
