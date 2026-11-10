/**
 * Native `/api/native/v1/groups*` handlers — same SQL as notebook-groups createServerFns.
 */
import { getSql, type Sql } from "@/lib/db";
import { allowRequest } from "@/lib/rate-limit";
import { noteFromRow } from "./v1.server";
import { noteToDocument, type LegacyNote, type NoteDocumentV1 } from "./note-document";

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
  await sql`delete from notebook_group_members where group_id = ${groupId}`;
  await sql`delete from notebook_groups where id = ${groupId}`;
  return { ok: true };
}

export async function listNotesInGroupForUser(
  userId: string,
  groupId: string,
): Promise<{ ok: true; notes: NativeGroupNoteCard[] } | { ok: false; error: "forbidden" }> {
  const sql = await getSql();
  const mine = await memberOf(sql, groupId, userId);
  if (mine?.status !== "accepted") return { ok: false, error: "forbidden" };

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

  const notes: NativeGroupNoteCard[] = rows.map((row) => {
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
  return { ok: true, notes };
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
