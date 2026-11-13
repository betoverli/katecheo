/**
 * Native Bearer wraps for friends links, granted notes, and notifications inbox.
 * Reuses existing web SQL / notify.server — no schema changes.
 */
import { getSql, type Sql } from "@/lib/db";
import { allowRequest } from "@/lib/rate-limit";
import { noteSpeakerIds, type Note, type Speaker } from "@/lib/notebook";
import { type NoteDocumentV1 } from "./note-document";
import { documentFromRow, speakerFromRow } from "./v1.server";
import { blockedIdsForUser, isEitherBlocked } from "./v1-moderation.server";

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
  const blocked = await blockedIdsForUser(userId, sql);
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
    if (blocked.has(otherId)) continue;
    const pref = await prefsById(sql, otherId);
    if (!pref) continue;
    const item = person(pref);
    if (row.status === "accepted") friends.push(item);
    else if (row.requester_id === userId) outgoing.push(item);
    else incoming.push(item);
  }
  return { friends, incoming, outgoing };
}

function newId() {
  return crypto.randomUUID().replaceAll("-", "");
}

async function pairStatus(
  sql: Sql,
  me: string,
  other: string,
): Promise<"none" | "self" | "incoming" | "outgoing" | "accepted"> {
  if (me === other) return "self";
  const rows = await sql<{ requester_id: string; addressee_id: string; status: string }>`
    select requester_id, addressee_id, status
    from user_links
    where (requester_id = ${me} and addressee_id = ${other})
       or (requester_id = ${other} and addressee_id = ${me})
    limit 1
  `;
  const row = rows[0];
  if (!row) return "none";
  if (row.status === "accepted") return "accepted";
  if (row.requester_id === me) return "outgoing";
  return "incoming";
}

/**
 * Same semantics as web `requestLink` (by handle).
 * Missing/self → `{ ok:false, error:"missing" }` (no distinct “exists” signal).
 * Duplicate outgoing/accepted → `{ ok:true, status }` (idempotent).
 * Cancel sent request = `declineLinkForUser` (web uses decline on outgoing).
 */
export async function requestLinkForUser(
  userId: string,
  handleRaw: string,
): Promise<
  | { ok: true; error: null; status: "accepted" | "outgoing" | "incoming" | "none" }
  | { ok: false; error: "missing" | "limit" | "rate"; status: "none" }
> {
  if (!(await allowRequest(`link-req:${userId}`, 20, 86_400_000))) {
    return { ok: false, error: "rate", status: "none" };
  }
  const handle = cleanHandle(handleRaw);
  const sql = await getSql();
  const other = handle ? await prefsByHandle(sql, handle) : null;
  if (!other || other.user_id === userId) {
    return { ok: false, error: "missing", status: "none" };
  }
  if (await isEitherBlocked(userId, other.user_id, sql)) {
    return { ok: false, error: "missing", status: "none" };
  }
  const current = await pairStatus(sql, userId, other.user_id);
  if (current === "accepted") return { ok: true, error: null, status: current };
  if (current === "outgoing") return { ok: true, error: null, status: current };
  if (current === "incoming") {
    const rows = await sql<{ id: string }>`
      update user_links set status = 'accepted'
      where requester_id = ${other.user_id} and addressee_id = ${userId} and status = 'pending'
      returning id
    `;
    if (!rows[0]) return { ok: false, error: "missing", status: "none" };
    void import("@/lib/notify.server").then((mod) =>
      mod.notifySocial(userId, other.user_id, "friends", "notifyLinkAcceptedTitle", "notifyLinkAcceptedBody", {
        href: "/profile/friends",
      }),
    );
    return { ok: true, error: null, status: "accepted" };
  }
  if ((await friendCount(sql, userId)) >= MAX_FRIENDS) {
    return { ok: false, error: "limit", status: "none" };
  }
  await sql`
    insert into user_links (id, requester_id, addressee_id, status)
    values (${newId()}, ${userId}, ${other.user_id}, ${"pending"})
    on conflict (requester_id, addressee_id) do nothing
  `;
  await sql`
    delete from user_links
    where requester_id = ${other.user_id} and addressee_id = ${userId} and status = 'pending'
  `;
  void import("@/lib/notify.server").then((mod) =>
    mod.notifySocial(userId, other.user_id, "friends", "notifyLinkTitle", "notifyLinkBody", {
      href: "/profile/friends",
    }),
  );
  return { ok: true, error: null, status: "outgoing" };
}

export type NativePeopleHit = NativeLinkPerson & {
  status: "none" | "self" | "incoming" | "outgoing" | "accepted";
};

export type NativePublicProfile = NativeLinkPerson & {
  status: "none" | "self" | "incoming" | "outgoing" | "accepted";
};

/**
 * Read-only public profile for another user (Amigos → profile).
 * Missing user or either-side block → null (caller returns 404; no existence leak beyond search).
 */
export async function getPublicProfileForUser(
  viewerId: string,
  targetUserIdRaw: string,
): Promise<NativePublicProfile | null> {
  const targetUserId = String(targetUserIdRaw ?? "").trim();
  if (!targetUserId || targetUserId.length > 80) return null;
  if (targetUserId === viewerId) {
    const self = await prefsById(await getSql(), viewerId);
    if (!self) return null;
    return { ...person(self), status: "self" };
  }
  const sql = await getSql();
  if (await isEitherBlocked(viewerId, targetUserId, sql)) return null;
  const pref = await prefsById(sql, targetUserId);
  if (!pref) return null;
  const status = await pairStatus(sql, viewerId, targetUserId);
  return { ...person(pref), status };
}

/** Same as web `searchPeople` (handle/name, min 2 chars, shared Neon rate limit). Hides users without a handle (L1). */
export async function searchPeopleForUser(userId: string, qRaw: string): Promise<NativePeopleHit[]> {
  if (!(await allowRequest(`people:${userId}`, 30, 60_000))) return [];
  const q = qRaw.trim().replace(/^@+/, "").replace(/[%_\\]/g, "").slice(0, 24);
  if (q.length < 2) return [];
  const sql = await getSql();
  const like = `${q}%`;
  const name = `%${q}%`;
  const blocked = await blockedIdsForUser(userId, sql);
  const rows = await sql<
    PrefRow & { link_status: string | null; requester_id: string | null }
  >`
    select p.user_id, p.handle, p.first_name, p.last_name, p.avatar_id, p.avatar_url,
           l.status as link_status, l.requester_id
    from user_prefs p
    left join user_links l
      on (l.requester_id = ${userId} and l.addressee_id = p.user_id)
      or (l.requester_id = p.user_id and l.addressee_id = ${userId})
    where p.handle is not null
      and length(trim(p.handle)) > 0
      and p.user_id <> ${userId}
      and (p.handle like ${like} or p.first_name ilike ${name} or p.last_name ilike ${name})
    order by p.handle
    limit 20
  `;
  return rows
    .filter((row) => !blocked.has(row.user_id))
    .map((row) => {
      let status: NativePeopleHit["status"] = "none";
      if (row.link_status === "accepted") status = "accepted";
      else if (row.link_status === "pending" && row.requester_id === userId) status = "outgoing";
      else if (row.link_status === "pending") status = "incoming";
      return { ...person(row), status };
    });
}

/** Same semantics as web `acceptLink` (by handle, addressee = me). */
export async function acceptLinkForUser(
  userId: string,
  handleRaw: string,
): Promise<{ ok: true } | { ok: false; error: "missing" | "limit" | "rate" }> {
  if (!(await allowRequest(`link-acc:${userId}`, 30, 86_400_000))) {
    return { ok: false, error: "rate" };
  }
  const handle = cleanHandle(handleRaw);
  const sql = await getSql();
  const other = handle ? await prefsByHandle(sql, handle) : null;
  if (!other) return { ok: false, error: "missing" };
  if (await isEitherBlocked(userId, other.user_id, sql)) return { ok: false, error: "missing" };
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

/** Same semantics as web `declineLink` (by handle). Also cancels outgoing. */
export async function declineLinkForUser(
  userId: string,
  handleRaw: string,
): Promise<{ ok: true } | { ok: false; error: "missing" }> {
  return deletePairLink(userId, handleRaw);
}

/**
 * Remove an accepted friendship for both users (and shared grants).
 * Distinct from decline so clients can keep request vs unfriend UX separate.
 */
export async function removeLinkForUser(
  userId: string,
  handleRaw: string,
): Promise<{ ok: true } | { ok: false; error: "missing" }> {
  const handle = cleanHandle(handleRaw);
  const sql = await getSql();
  const other = handle ? await prefsByHandle(sql, handle) : null;
  if (!other) return { ok: false, error: "missing" };
  const status = await pairStatus(sql, userId, other.user_id);
  if (status !== "accepted") return { ok: false, error: "missing" };
  return deletePairLink(userId, handleRaw);
}

async function deletePairLink(
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
  const blocked = await blockedIdsForUser(userId, sql);
  const rows = await sql<NoteRow & { from_id: string }>`
    select n.id, n.title, n.happened_at::text, n.tags, n.blocks, n.blocks_backup, n.visibility, n.updated_at, n.speaker_id,
           g.from_id
    from notebook_notes n
    join note_grants g on g.note_id = n.id
    where g.user_id = ${userId}
    order by n.happened_at desc
    limit 80
  `;
  return rows
    .filter((row) => !blocked.has(row.from_id))
    .map((row) => documentFromRow(row).document);
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
  const granted = await sql<NoteRow & { from_id: string }>`
    select n.id, n.title, n.happened_at::text, n.tags, n.blocks, n.blocks_backup, n.visibility, n.updated_at, n.speaker_id,
           g.from_id
    from notebook_notes n
    join note_grants g on g.note_id = n.id
    where n.id = ${noteId} and g.user_id = ${userId}
    limit 1
  `;
  if (!granted[0]) return null;
  const blocked = await blockedIdsForUser(userId, sql);
  if (blocked.has(granted[0].from_id)) return null;
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

export async function listNotificationsForUser(
  userId: string,
  opts: { cursor?: string | null; limit?: number; unreadOnly?: boolean } = {},
) {
  const { listInboxPage, maybeSendDigests, unreadCount } = await import("@/lib/notify.server");
  void maybeSendDigests().catch(() => undefined);
  const page = await listInboxPage(userId, opts);
  const unread = await unreadCount(userId);
  return { items: page.items, nextCursor: page.nextCursor, unread };
}

export async function notificationsSummaryForUser(userId: string) {
  const { unreadSummary, maybeSendDigests } = await import("@/lib/notify.server");
  void maybeSendDigests().catch(() => undefined);
  return unreadSummary(userId);
}

/** Idempotent: only sets read_at when still null; always scoped to userId. */
export async function markNotificationsReadForUser(userId: string, id?: string) {
  const { markRead } = await import("@/lib/notify.server");
  await markRead(userId, id);
  return { ok: true as const };
}

/** Deletes one alert row; never touches user_links / Friends requests. */
export async function deleteNotificationForUser(userId: string, id: string) {
  const { deleteNotification } = await import("@/lib/notify.server");
  return deleteNotification(userId, id);
}

/** Clears the entire alerts inbox for this user. */
export async function clearNotificationsForUser(userId: string) {
  const { clearNotifications } = await import("@/lib/notify.server");
  return clearNotifications(userId);
}
