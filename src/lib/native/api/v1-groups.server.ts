/**
 * Native `/api/native/v1/groups*` handlers — same SQL as notebook-groups createServerFns.
 */
import { getSql, type Sql } from "@/lib/db";
import { allowRequest } from "@/lib/rate-limit";
import { groupNotesEtag } from "./group-notes-etag";
import { noteFromRow } from "./v1.server";
import { noteToDocument, type LegacyNote, type NoteDocumentV1 } from "./note-document";

export { groupNotesEtag } from "./group-notes-etag";

export type NativeGroupVisibility = "listed" | "private";
export type NativeGroupPostPolicy = "members" | "admins";
export type NativeGroupRole = "admin" | "member";
export type NativeGroupStatus = "pending" | "accepted";

export type NativeGroup = {
  id: string;
  name: string;
  description: string;
  visibility: NativeGroupVisibility;
  postPolicy: NativeGroupPostPolicy;
  createdBy: string;
  memberCount: number;
  myRole: NativeGroupRole | null;
  myStatus: NativeGroupStatus | null;
  updatedAt: string;
};

export type NativeGroupNoteCard = {
  note: { id: string; title: string; happenedAt: string; updatedAt: string };
  author: {
    userId: string;
    handle: string;
    firstName: string;
    lastName: string;
  };
  owned: boolean;
  /** Full document when the caller owns the note (Caderno reuse). */
  document: NoteDocumentV1 | null;
};

type GroupRow = {
  id: string;
  name: string;
  description: string;
  visibility: string;
  post_policy: string;
  created_by: string;
  updated_at: string;
  member_count: number;
  my_role: string | null;
  my_status: string | null;
};

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

const MAX_CREATED = 50;
const MAX_MEMBERSHIPS = 100;
const MAX_GROUP_NOTES = 200;

function newId() {
  return crypto.randomUUID().replaceAll("-", "");
}

function cleanName(value: string) {
  return value.trim().replace(/\s+/g, " ").slice(0, 60);
}

function cleanDescription(value: string) {
  return value.trim().slice(0, 240);
}

function asVisibility(value: string): NativeGroupVisibility {
  return value === "listed" ? "listed" : "private";
}

function asPolicy(value: string): NativeGroupPostPolicy {
  return value === "admins" ? "admins" : "members";
}

function asRole(value: string | null): NativeGroupRole | null {
  if (value === "admin" || value === "member") return value;
  return null;
}

function asStatus(value: string | null): NativeGroupStatus | null {
  if (value === "pending" || value === "accepted") return value;
  return null;
}

function fromGroup(row: GroupRow): NativeGroup {
  return {
    id: row.id,
    name: row.name,
    description: row.description ?? "",
    visibility: asVisibility(row.visibility),
    postPolicy: asPolicy(row.post_policy),
    createdBy: row.created_by,
    memberCount: Number(row.member_count ?? 0) || 0,
    myRole: asRole(row.my_role),
    myStatus: asStatus(row.my_status),
    updatedAt: String(row.updated_at ?? ""),
  };
}

async function loadGroup(sql: Sql, id: string, userId: string) {
  const found = await sql<GroupRow>`
    select g.id, g.name, g.description, g.visibility, g.post_policy, g.created_by, g.updated_at,
      (select count(*)::int from notebook_group_members x where x.group_id = g.id and x.status = 'accepted') as member_count,
      (select "role" from notebook_group_members where group_id = g.id and user_id = ${userId}) as my_role,
      (select status from notebook_group_members where group_id = g.id and user_id = ${userId}) as my_status
    from notebook_groups g
    where g.id = ${id}
    limit 1
  `;
  return found[0] ? fromGroup(found[0]) : null;
}

async function memberOf(sql: Sql, groupId: string, userId: string) {
  const rows = await sql<{ role: string; status: string }>`
    select "role", status from notebook_group_members
    where group_id = ${groupId} and user_id = ${userId}
    limit 1
  `;
  return rows[0] ?? null;
}

export async function listGroupsForUser(userId: string): Promise<NativeGroup[]> {
  const sql = await getSql();
  const rows = await sql<GroupRow>`
    select g.id, g.name, g.description, g.visibility, g.post_policy, g.created_by, g.updated_at,
      (select count(*)::int from notebook_group_members x where x.group_id = g.id and x.status = 'accepted') as member_count,
      coalesce(m."role", case when g.created_by = ${userId} then 'admin' end) as my_role,
      coalesce(m.status, case when g.created_by = ${userId} then 'accepted' end) as my_status
    from notebook_groups g
    left join notebook_group_members m on m.group_id = g.id and m.user_id = ${userId}
    where m.user_id is not null or g.created_by = ${userId}
    order by coalesce(m.status, 'accepted') asc, g.updated_at desc
    limit 100
  `;
  return rows.map(fromGroup);
}

export async function getGroupForUser(userId: string, groupId: string): Promise<NativeGroup | null> {
  const sql = await getSql();
  const mine = await memberOf(sql, groupId, userId);
  // Private metadata must not leak to non-members (IDOR). Accepted membership required.
  if (!mine || mine.status !== "accepted") return null;
  return loadGroup(sql, groupId, userId);
}

export async function createGroupForUser(
  userId: string,
  raw: unknown,
): Promise<
  | { ok: true; group: NativeGroup }
  | { ok: false; error: "invalid" | "limit" }
> {
  const body = raw && typeof raw === "object" ? (raw as Record<string, unknown>) : {};
  const name = cleanName(typeof body.name === "string" ? body.name : "");
  if (name.length < 2) return { ok: false, error: "invalid" };
  if (!(await allowRequest(`gcreate:${userId}`, 20, 86_400_000))) {
    return { ok: false, error: "limit" };
  }
  const sql = await getSql();
  const created = await sql<{ n: number }>`
    select count(*)::int as n from notebook_groups where created_by = ${userId}
  `;
  if (Number(created[0]?.n ?? 0) >= MAX_CREATED) return { ok: false, error: "limit" };
  const memberships = await sql<{ n: number }>`
    select count(*)::int as n from notebook_group_members where user_id = ${userId} and status = 'accepted'
  `;
  if (Number(memberships[0]?.n ?? 0) >= MAX_MEMBERSHIPS) return { ok: false, error: "limit" };
  const id = newId();
  const visibility = body.visibility === "listed" ? "listed" : "private";
  const description = cleanDescription(typeof body.description === "string" ? body.description : "");
  await sql`
    with g as (
      insert into notebook_groups (id, name, description, visibility, post_policy, created_by, updated_at)
      values (${id}, ${name}, ${description}, ${visibility}, ${"members"}, ${userId}, now())
      returning id
    )
    insert into notebook_group_members (group_id, user_id, "role", status)
    select id, ${userId}, ${"admin"}, ${"accepted"} from g
  `;
  const group = await loadGroup(sql, id, userId);
  if (!group) return { ok: false, error: "invalid" };
  return { ok: true, group };
}

export async function updateGroupForUser(
  userId: string,
  groupId: string,
  raw: unknown,
): Promise<{ ok: true; group: NativeGroup } | { ok: false; error: "forbidden" | "missing" | "invalid" }> {
  const sql = await getSql();
  const mine = await memberOf(sql, groupId, userId);
  if (mine?.role !== "admin" || mine.status !== "accepted") return { ok: false, error: "forbidden" };
  const current = await loadGroup(sql, groupId, userId);
  if (!current) return { ok: false, error: "missing" };
  const body = raw && typeof raw === "object" ? (raw as Record<string, unknown>) : {};
  const name =
    body.name != null && typeof body.name === "string"
      ? cleanName(body.name) || current.name
      : current.name;
  if (name.length < 2) return { ok: false, error: "invalid" };
  const description =
    body.description != null && typeof body.description === "string"
      ? cleanDescription(body.description)
      : current.description;
  const visibility =
    typeof body.visibility === "string" ? asVisibility(body.visibility) : current.visibility;
  const postPolicy =
    typeof body.postPolicy === "string" ? asPolicy(body.postPolicy) : current.postPolicy;
  await sql`
    update notebook_groups
    set name = ${name}, description = ${description}, visibility = ${visibility},
        post_policy = ${postPolicy}, updated_at = now()
    where id = ${groupId}
  `;
  const group = await loadGroup(sql, groupId, userId);
  if (!group) return { ok: false, error: "missing" };
  return { ok: true, group };
}

export async function deleteGroupForUser(
  userId: string,
  groupId: string,
): Promise<{ ok: true } | { ok: false; error: "forbidden" | "missing" }> {
  const sql = await getSql();
  const mine = await memberOf(sql, groupId, userId);
  if (mine?.role !== "admin" || mine.status !== "accepted") return { ok: false, error: "forbidden" };
  const current = await loadGroup(sql, groupId, userId);
  if (!current) return { ok: false, error: "missing" };
  await sql`delete from notebook_group_notes where group_id = ${groupId}`;
  await sql`delete from notebook_group_invites where group_id = ${groupId}`;
  await sql`delete from notebook_group_members where group_id = ${groupId}`;
  await sql`delete from notebook_groups where id = ${groupId}`;
  return { ok: true };
}

export type ListGroupNotesResult =
  | {
      ok: true;
      notes: NativeGroupNoteCard[];
      /** Weak fingerprint of id+updatedAt for If-None-Match / ETag. */
      etag: string;
      /** True when `notes` is only the delta since `updatedSince` (not the full list). */
      incremental: boolean;
    }
  | { ok: false; error: "forbidden" };

export async function listNotesInGroupForUser(
  userId: string,
  groupId: string,
  options: { updatedSince?: string | null } = {},
): Promise<ListGroupNotesResult> {
  const sql = await getSql();
  const mine = await memberOf(sql, groupId, userId);
  if (mine?.status !== "accepted") return { ok: false, error: "forbidden" };

  const { blockedIdsForUser } = await import("./v1-moderation.server");
  const blocked = await blockedIdsForUser(userId, sql);

  const rows = await sql<
    NoteRow & {
      user_id: string;
      handle: string;
      first_name: string;
      last_name: string;
    }
  >`
    select n.id, n.title, n.happened_at::text, n.tags, n.blocks, n.visibility, n.updated_at, n.speaker_id,
           n.user_id, coalesce(p.handle, '') as handle, coalesce(p.first_name, '') as first_name,
           coalesce(p.last_name, '') as last_name
    from notebook_group_notes g
    join notebook_notes n on n.id = g.note_id
    left join user_prefs p on p.user_id = n.user_id
    where g.group_id = ${groupId}
    order by n.happened_at desc, n.updated_at desc
    limit 80
  `;

  const allNotes: NativeGroupNoteCard[] = rows.filter((row) => !blocked.has(row.user_id)).map((row) => {
    const owned = row.user_id === userId;
    const document = owned ? noteToDocument(noteFromRow(row) as LegacyNote) : null;
    const happened =
      typeof row.happened_at === "string" ? row.happened_at.slice(0, 10) : String(row.happened_at);
    return {
      note: {
        id: row.id,
        title: row.title ?? "",
        happenedAt: happened,
        updatedAt: String(row.updated_at ?? ""),
      },
      author: {
        userId: row.user_id,
        handle: row.handle ?? "",
        firstName: row.first_name ?? "",
        lastName: row.last_name ?? "",
      },
      owned,
      document,
    };
  });

  const etag = groupNotesEtag(allNotes);
  const since = options.updatedSince?.trim() || "";
  if (since) {
    const delta = allNotes.filter((card) => card.note.updatedAt > since);
    // Only advertise incremental when the watermark filters something out.
    if (delta.length < allNotes.length) {
      return { ok: true, notes: delta, etag, incremental: true };
    }
  }
  return { ok: true, notes: allNotes, etag, incremental: false };
}

export async function listGroupsForNote(
  userId: string,
  noteId: string,
): Promise<Array<NativeGroup & { published: boolean }>> {
  const sql = await getSql();
  // L2: require ownership or an accepted note grant before revealing publish flags.
  const owned = await sql<{ id: string }>`
    select id from notebook_notes where id = ${noteId} and user_id = ${userId} limit 1
  `;
  if (!owned[0]) {
    const granted = await sql<{ note_id: string }>`
      select note_id from note_grants where note_id = ${noteId} and user_id = ${userId} limit 1
    `;
    if (!granted[0]) return [];
  }
  const rows = await sql<{ group_id: string }>`
    select group_id from notebook_group_notes where note_id = ${noteId}
  `;
  const published = new Set(rows.map((row) => row.group_id));
  const mine = await sql<GroupRow>`
    select g.id, g.name, g.description, g.visibility, g.post_policy, g.created_by, g.updated_at,
      (select count(*)::int from notebook_group_members x where x.group_id = g.id and x.status = 'accepted') as member_count,
      m."role" as my_role, m.status as my_status
    from notebook_group_members m
    join notebook_groups g on g.id = m.group_id
    where m.user_id = ${userId} and m.status = 'accepted'
    order by g.updated_at desc
    limit 100
  `;
  return mine.map(fromGroup).map((item) => ({ ...item, published: published.has(item.id) }));
}

export async function publishNoteIdToGroup(
  userId: string,
  groupId: string,
  noteId: string,
): Promise<
  | { ok: true }
  | { ok: false; error: "forbidden" | "missing" | "limit" }
> {
  const sql = await getSql();
  const mine = await memberOf(sql, groupId, userId);
  if (mine?.status !== "accepted") return { ok: false, error: "forbidden" };
  const group = await loadGroup(sql, groupId, userId);
  if (!group) return { ok: false, error: "missing" };
  if (group.postPolicy === "admins" && mine.role !== "admin") return { ok: false, error: "forbidden" };

  const owned = await sql<{ id: string }>`
    select id from notebook_notes where id = ${noteId} and user_id = ${userId} limit 1
  `;
  if (!owned[0]) return { ok: false, error: "missing" };

  const count = await sql<{ n: number }>`
    select count(*)::int as n from notebook_group_notes where group_id = ${groupId}
  `;
  const already = await sql<{ note_id: string }>`
    select note_id from notebook_group_notes where group_id = ${groupId} and note_id = ${noteId}
  `;
  if (!already[0] && Number(count[0]?.n ?? 0) >= MAX_GROUP_NOTES) return { ok: false, error: "limit" };

  await sql`
    insert into notebook_group_notes (group_id, note_id, published_by)
    values (${groupId}, ${noteId}, ${userId})
    on conflict (group_id, note_id) do nothing
  `;

  if (!already[0]) {
    void import("@/lib/notify.server").then((mod) =>
      mod.notifyGroupNote(userId, groupId, group.name, noteId),
    );
  }
  return { ok: true };
}

export async function unpublishNoteFromGroupForUser(
  userId: string,
  groupId: string,
  noteId: string,
): Promise<{ ok: true } | { ok: false; error: "forbidden" }> {
  const sql = await getSql();
  const mine = await memberOf(sql, groupId, userId);
  if (mine?.status !== "accepted") return { ok: false, error: "forbidden" };
  const owner = await sql<{ user_id: string }>`select user_id from notebook_notes where id = ${noteId}`;
  const isOwner = owner[0]?.user_id === userId;
  if (!isOwner && mine.role !== "admin") return { ok: false, error: "forbidden" };
  await sql`delete from notebook_group_notes where group_id = ${groupId} and note_id = ${noteId}`;
  return { ok: true };
}

export type NativeGroupMember = {
  userId: string;
  handle: string;
  firstName: string;
  lastName: string;
  avatarId: string;
  avatarUrl: string;
  role: NativeGroupRole;
  status: NativeGroupStatus;
};

async function adminCount(sql: Sql, groupId: string) {
  const rows = await sql<{ n: number }>`
    select count(*)::int as n from notebook_group_members
    where group_id = ${groupId} and status = 'accepted' and "role" = 'admin'
  `;
  return Number(rows[0]?.n ?? 0);
}

export async function listMembersForGroup(
  userId: string,
  groupId: string,
): Promise<{ ok: true; members: NativeGroupMember[] } | { ok: false; error: "forbidden" }> {
  const sql = await getSql();
  const mine = await memberOf(sql, groupId, userId);
  if (mine?.status !== "accepted") return { ok: false, error: "forbidden" };
  const rows = await sql<{
    user_id: string;
    handle: string;
    first_name: string;
    last_name: string;
    avatar_id: string;
    avatar_url: string;
    role: string;
    status: string;
  }>`
    select p.user_id, coalesce(p.handle, '') as handle, coalesce(p.first_name, '') as first_name,
           coalesce(p.last_name, '') as last_name, coalesce(p.avatar_id, '') as avatar_id,
           coalesce(p.avatar_url, '') as avatar_url, m."role", m.status
    from notebook_group_members m
    join user_prefs p on p.user_id = m.user_id
    where m.group_id = ${groupId}
    order by m."role" asc, m.status asc, p.first_name
  `;
  const members = rows
    .filter((row) => mine.role === "admin" || row.status === "accepted")
    .map((row) => ({
      userId: row.user_id,
      handle: row.handle,
      firstName: row.first_name,
      lastName: row.last_name,
      avatarId: row.avatar_id,
      avatarUrl: row.avatar_url,
      role: (asRole(row.role) ?? "member") as NativeGroupRole,
      status: (asStatus(row.status) ?? "pending") as NativeGroupStatus,
    }));
  return { ok: true, members };
}

export async function decideGroupMemberForUser(
  userId: string,
  groupId: string,
  targetUserId: string,
  accept: boolean,
): Promise<{ ok: true } | { ok: false; error: "forbidden" | "missing" }> {
  const sql = await getSql();
  const mine = await memberOf(sql, groupId, userId);
  if (mine?.role !== "admin" || mine.status !== "accepted") return { ok: false, error: "forbidden" };
  const other = await memberOf(sql, groupId, targetUserId);
  if (!other || other.status !== "pending") return { ok: false, error: "missing" };
  if (accept) {
    await sql`
      update notebook_group_members set status = 'accepted'
      where group_id = ${groupId} and user_id = ${targetUserId}
    `;
  } else {
    await sql`delete from notebook_group_members where group_id = ${groupId} and user_id = ${targetUserId}`;
  }
  return { ok: true };
}

export async function setGroupMemberRoleForUser(
  userId: string,
  groupId: string,
  targetUserId: string,
  role: NativeGroupRole,
): Promise<{ ok: true } | { ok: false; error: "forbidden" | "missing" | "lastAdmin" }> {
  const sql = await getSql();
  const mine = await memberOf(sql, groupId, userId);
  if (mine?.role !== "admin" || mine.status !== "accepted") return { ok: false, error: "forbidden" };
  const other = await memberOf(sql, groupId, targetUserId);
  if (!other || other.status !== "accepted") return { ok: false, error: "missing" };
  if (other.role === "admin" && role !== "admin" && (await adminCount(sql, groupId)) <= 1) {
    return { ok: false, error: "lastAdmin" };
  }
  await sql`
    update notebook_group_members set "role" = ${role}
    where group_id = ${groupId} and user_id = ${targetUserId}
  `;
  return { ok: true };
}

export async function removeGroupMemberForUser(
  userId: string,
  groupId: string,
  targetUserId: string,
): Promise<{ ok: true } | { ok: false; error: "forbidden" | "missing" | "lastAdmin" }> {
  const sql = await getSql();
  const mine = await memberOf(sql, groupId, userId);
  if (!mine || mine.status !== "accepted") return { ok: false, error: "forbidden" };
  if (targetUserId !== userId && mine.role !== "admin") return { ok: false, error: "forbidden" };
  const other = await memberOf(sql, groupId, targetUserId);
  if (!other) return { ok: false, error: "missing" };
  if (other.role === "admin" && (await adminCount(sql, groupId)) <= 1) {
    return { ok: false, error: "lastAdmin" };
  }
  await sql`delete from notebook_group_members where group_id = ${groupId} and user_id = ${targetUserId}`;
  return { ok: true };
}

export type NativeGroupInvitePerson = {
  userId: string;
  handle: string;
  firstName: string;
  lastName: string;
  avatarId: string;
  avatarUrl: string;
};

export type NativeGroupInvite = {
  id: string;
  groupId: string;
  groupName: string;
  status: "pending" | "accepted" | "declined";
  createdAt: string;
  inviter: NativeGroupInvitePerson;
};

const MAX_INVITES_PER_REQUEST = 20;

async function areFriends(sql: Sql, a: string, b: string) {
  const rows = await sql<{ id: string }>`
    select id from user_links
    where status = 'accepted'
      and (
        (requester_id = ${a} and addressee_id = ${b})
        or (requester_id = ${b} and addressee_id = ${a})
      )
    limit 1
  `;
  return Boolean(rows[0]);
}

function personFromPrefs(row: {
  user_id: string;
  handle: string;
  first_name: string;
  last_name: string;
  avatar_id: string;
  avatar_url: string;
}): NativeGroupInvitePerson {
  return {
    userId: row.user_id,
    handle: row.handle ?? "",
    firstName: row.first_name ?? "",
    lastName: row.last_name ?? "",
    avatarId: row.avatar_id || "book",
    avatarUrl: row.avatar_url ?? "",
  };
}

/** Friends who can be invited: accepted friends, not members, not already pending-invited. */
export async function listGroupInviteFriendsForUser(
  userId: string,
  groupId: string,
  query = "",
): Promise<
  | { ok: true; friends: NativeGroupInvitePerson[] }
  | { ok: false; error: "forbidden" | "missing" }
> {
  const sql = await getSql();
  const mine = await memberOf(sql, groupId, userId);
  // Same invite surface as share-link today: any accepted member.
  if (!mine || mine.status !== "accepted") return { ok: false, error: "forbidden" };
  const group = await loadGroup(sql, groupId, userId);
  if (!group) return { ok: false, error: "missing" };

  const q = query.trim().replace(/[%_\\]/g, "").slice(0, 40).toLowerCase();
  const rows = await sql<{
    user_id: string;
    handle: string;
    first_name: string;
    last_name: string;
    avatar_id: string;
    avatar_url: string;
  }>`
    select p.user_id, coalesce(p.handle, '') as handle, coalesce(p.first_name, '') as first_name,
           coalesce(p.last_name, '') as last_name, coalesce(p.avatar_id, '') as avatar_id,
           coalesce(p.avatar_url, '') as avatar_url
    from user_links l
    join user_prefs p on p.user_id = case
      when l.requester_id = ${userId} then l.addressee_id
      else l.requester_id
    end
    where l.status = 'accepted'
      and (l.requester_id = ${userId} or l.addressee_id = ${userId})
      and not exists (
        select 1 from notebook_group_members m
        where m.group_id = ${groupId} and m.user_id = p.user_id
      )
      and not exists (
        select 1 from notebook_group_invites i
        where i.group_id = ${groupId} and i.invitee_id = p.user_id and i.status = 'pending'
      )
      and (
        ${q} = ''
        or lower(coalesce(p.handle, '')) like ${"%" + q + "%"}
        or lower(coalesce(p.first_name, '')) like ${"%" + q + "%"}
        or lower(coalesce(p.last_name, '')) like ${"%" + q + "%"}
      )
    order by p.first_name, p.handle
    limit 80
  `;
  return { ok: true, friends: rows.map(personFromPrefs) };
}

export async function createGroupInvitesForUser(
  userId: string,
  groupId: string,
  raw: unknown,
): Promise<
  | { ok: true; invited: number; inviteIds: string[] }
  | { ok: false; error: "forbidden" | "missing" | "invalid" | "limit" }
> {
  const body = raw && typeof raw === "object" ? (raw as Record<string, unknown>) : {};
  const rawIds = Array.isArray(body.userIds) ? body.userIds : [];
  const userIds = [
    ...new Set(
      rawIds
        .filter((id): id is string => typeof id === "string")
        .map((id) => id.trim())
        .filter((id) => id.length > 0 && id.length <= 80 && id !== userId),
    ),
  ].slice(0, MAX_INVITES_PER_REQUEST);
  if (!userIds.length) return { ok: false, error: "invalid" };
  if (!(await allowRequest(`ginvite:${userId}`, 60, 86_400_000))) {
    return { ok: false, error: "limit" };
  }

  const sql = await getSql();
  const mine = await memberOf(sql, groupId, userId);
  if (!mine || mine.status !== "accepted") return { ok: false, error: "forbidden" };
  const group = await loadGroup(sql, groupId, userId);
  if (!group) return { ok: false, error: "missing" };

  const { blockedIdsForUser } = await import("./v1-moderation.server");
  const blocked = await blockedIdsForUser(userId, sql);

  const inviteIds: string[] = [];
  for (const inviteeId of userIds) {
    if (blocked.has(inviteeId)) continue;
    if (!(await areFriends(sql, userId, inviteeId))) continue;
    const existing = await memberOf(sql, groupId, inviteeId);
    if (existing) continue;
    const pending = await sql<{ id: string }>`
      select id from notebook_group_invites
      where group_id = ${groupId} and invitee_id = ${inviteeId} and status = 'pending'
      limit 1
    `;
    if (pending[0]) continue;

    const memberships = await sql<{ n: number }>`
      select count(*)::int as n from notebook_group_members
      where user_id = ${inviteeId} and status = 'accepted'
    `;
    if (Number(memberships[0]?.n ?? 0) >= MAX_MEMBERSHIPS) continue;

    const id = newId();
    await sql`
      insert into notebook_group_invites (id, group_id, inviter_id, invitee_id, status)
      values (${id}, ${groupId}, ${userId}, ${inviteeId}, ${"pending"})
    `;
    inviteIds.push(id);
    void import("@/lib/notify.server").then((mod) =>
      mod.notifySocial(
        userId,
        inviteeId,
        "groups",
        "notifyGroupInviteTitle",
        "notifyGroupInviteBody",
        {
          plan: group.name,
          href: `/groups/invite/${id}`,
        },
      ),
    );
  }

  return { ok: true, invited: inviteIds.length, inviteIds };
}

export async function listMyGroupInvitesForUser(
  userId: string,
): Promise<NativeGroupInvite[]> {
  const sql = await getSql();
  const rows = await sql<{
    id: string;
    group_id: string;
    group_name: string;
    status: string;
    created_at: string;
    user_id: string;
    handle: string;
    first_name: string;
    last_name: string;
    avatar_id: string;
    avatar_url: string;
  }>`
    select i.id, i.group_id, g.name as group_name, i.status, i.created_at::text,
           p.user_id, coalesce(p.handle, '') as handle, coalesce(p.first_name, '') as first_name,
           coalesce(p.last_name, '') as last_name, coalesce(p.avatar_id, '') as avatar_id,
           coalesce(p.avatar_url, '') as avatar_url
    from notebook_group_invites i
    join notebook_groups g on g.id = i.group_id
    join user_prefs p on p.user_id = i.inviter_id
    where i.invitee_id = ${userId} and i.status = 'pending'
    order by i.created_at desc
    limit 50
  `;
  return rows.map((row) => ({
    id: row.id,
    groupId: row.group_id,
    groupName: row.group_name,
    status: "pending" as const,
    createdAt: String(row.created_at ?? ""),
    inviter: personFromPrefs(row),
  }));
}

export async function getGroupInviteForUser(
  userId: string,
  inviteId: string,
): Promise<NativeGroupInvite | null> {
  const sql = await getSql();
  const rows = await sql<{
    id: string;
    group_id: string;
    group_name: string;
    status: string;
    created_at: string;
    user_id: string;
    handle: string;
    first_name: string;
    last_name: string;
    avatar_id: string;
    avatar_url: string;
  }>`
    select i.id, i.group_id, g.name as group_name, i.status, i.created_at::text,
           p.user_id, coalesce(p.handle, '') as handle, coalesce(p.first_name, '') as first_name,
           coalesce(p.last_name, '') as last_name, coalesce(p.avatar_id, '') as avatar_id,
           coalesce(p.avatar_url, '') as avatar_url
    from notebook_group_invites i
    join notebook_groups g on g.id = i.group_id
    join user_prefs p on p.user_id = i.inviter_id
    where i.id = ${inviteId} and i.invitee_id = ${userId}
    limit 1
  `;
  const row = rows[0];
  if (!row) return null;
  const status =
    row.status === "accepted" || row.status === "declined" ? row.status : "pending";
  return {
    id: row.id,
    groupId: row.group_id,
    groupName: row.group_name,
    status,
    createdAt: String(row.created_at ?? ""),
    inviter: personFromPrefs(row),
  };
}

export async function respondGroupInviteForUser(
  userId: string,
  inviteId: string,
  accept: boolean,
): Promise<
  | { ok: true; group: NativeGroup | null }
  | { ok: false; error: "forbidden" | "missing" | "limit" }
> {
  const sql = await getSql();
  const rows = await sql<{
    id: string;
    group_id: string;
    invitee_id: string;
    inviter_id: string;
    status: string;
    group_name: string;
  }>`
    select i.id, i.group_id, i.invitee_id, i.inviter_id, i.status, g.name as group_name
    from notebook_group_invites i
    join notebook_groups g on g.id = i.group_id
    where i.id = ${inviteId}
    limit 1
  `;
  const invite = rows[0];
  if (!invite || invite.invitee_id !== userId) return { ok: false, error: "missing" };
  if (invite.status !== "pending") return { ok: false, error: "missing" };

  if (!accept) {
    await sql`
      update notebook_group_invites
      set status = 'declined', responded_at = now()
      where id = ${inviteId}
    `;
    return { ok: true, group: null };
  }

  const memberships = await sql<{ n: number }>`
    select count(*)::int as n from notebook_group_members
    where user_id = ${userId} and status = 'accepted'
  `;
  if (Number(memberships[0]?.n ?? 0) >= MAX_MEMBERSHIPS) {
    return { ok: false, error: "limit" };
  }

  const existing = await memberOf(sql, invite.group_id, userId);
  if (existing?.status === "accepted") {
    await sql`
      update notebook_group_invites
      set status = 'accepted', responded_at = now()
      where id = ${inviteId}
    `;
    const group = await loadGroup(sql, invite.group_id, userId);
    return { ok: true, group };
  }

  await sql`
    insert into notebook_group_members (group_id, user_id, "role", status)
    values (${invite.group_id}, ${userId}, ${"member"}, ${"accepted"})
    on conflict (group_id, user_id) do update
      set status = 'accepted', "role" = excluded."role"
  `;
  await sql`
    update notebook_group_invites
    set status = 'accepted', responded_at = now()
    where id = ${inviteId}
  `;
  // Drop any other pending invites for this user+group.
  await sql`
    update notebook_group_invites
    set status = 'declined', responded_at = now()
    where group_id = ${invite.group_id} and invitee_id = ${userId}
      and status = 'pending' and id <> ${inviteId}
  `;

  void import("@/lib/notify.server").then((mod) =>
    mod.notifySocial(
      userId,
      invite.inviter_id,
      "groups",
      "notifyGroupInviteAcceptedTitle",
      "notifyGroupInviteAcceptedBody",
      {
        plan: invite.group_name,
        href: `/groups/${invite.group_id}`,
      },
    ),
  );

  const group = await loadGroup(sql, invite.group_id, userId);
  return { ok: true, group };
}
