import { createServerFn } from "@tanstack/react-start";
import { authMiddleware } from "@/lib/auth/middleware";
import { getSql, type Sql } from "@/lib/db";
import { allowRequest } from "@/lib/rate-limit";
import { asNote, type Note } from "@/lib/notebook";

export type GroupVisibility = "listed" | "private";
export type GroupPostPolicy = "members" | "admins";
export type GroupRole = "admin" | "member";
export type GroupStatus = "pending" | "accepted";

export type GroupPerson = {
  userId: string;
  handle: string;
  firstName: string;
  lastName: string;
  avatarId: string;
  avatarUrl: string;
};

export type NotebookGroup = {
  id: string;
  name: string;
  description: string;
  visibility: GroupVisibility;
  postPolicy: GroupPostPolicy;
  createdBy: string;
  memberCount: number;
  myRole: GroupRole | null;
  myStatus: GroupStatus | null;
  updatedAt: string;
};

export type GroupMember = GroupPerson & { role: GroupRole; status: GroupStatus };

export type GroupNoteCard = {
  note: { id: string; title: string; happenedAt: string };
  author: GroupPerson;
};

const MAX_CREATED = 50;
const MAX_MEMBERSHIPS = 100;
const MAX_GROUP_NOTES = 200;

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

type PrefRow = {
  user_id: string;
  handle: string;
  first_name: string;
  last_name: string;
  avatar_id: string;
  avatar_url: string;
};

function newId() {
  return crypto.randomUUID().replaceAll("-", "");
}

function cleanName(value: string) {
  return value.trim().replace(/\s+/g, " ").slice(0, 60);
}

function cleanDescription(value: string) {
  return value.trim().slice(0, 240);
}

function asVisibility(value: string): GroupVisibility {
  return value === "listed" ? "listed" : "private";
}

function asPolicy(value: string): GroupPostPolicy {
  return value === "admins" ? "admins" : "members";
}

function asRole(value: string | null): GroupRole | null {
  if (value === "admin" || value === "member") return value;
  return null;
}

function asStatus(value: string | null): GroupStatus | null {
  if (value === "pending" || value === "accepted") return value;
  return null;
}

function person(row: PrefRow): GroupPerson {
  return {
    userId: row.user_id,
    handle: row.handle ?? "",
    firstName: row.first_name ?? "",
    lastName: row.last_name ?? "",
    avatarId: row.avatar_id || "book",
    avatarUrl: row.avatar_url ?? "",
  };
}

function fromGroup(row: GroupRow): NotebookGroup {
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

async function adminCount(sql: Sql, groupId: string) {
  const rows = await sql<{ n: number }>`
    select count(*)::int as n from notebook_group_members
    where group_id = ${groupId} and status = 'accepted' and "role" = 'admin'
  `;
  return Number(rows[0]?.n ?? 0);
}

export const listMyGroups = createServerFn({ method: "POST" })
  .middleware([authMiddleware])
  .handler(async ({ context }) => {
    const sql = await getSql();
    const rows = await sql<GroupRow>`
      select g.id, g.name, g.description, g.visibility, g.post_policy, g.created_by, g.updated_at,
        (select count(*)::int from notebook_group_members x where x.group_id = g.id and x.status = 'accepted') as member_count,
        coalesce(m."role", case when g.created_by = ${context.userId} then 'admin' end) as my_role,
        coalesce(m.status, case when g.created_by = ${context.userId} then 'accepted' end) as my_status
      from notebook_groups g
      left join notebook_group_members m on m.group_id = g.id and m.user_id = ${context.userId}
      where m.user_id is not null or g.created_by = ${context.userId}
      order by coalesce(m.status, 'accepted') asc, g.updated_at desc
      limit 100
    `;
    return rows.map(fromGroup);
  });

export const searchListedGroups = createServerFn({ method: "GET" })
  .middleware([authMiddleware])
  .validator((data: { query: string }) => data)
  .handler(async ({ context, data }) => {
    const q = data.query.trim().replace(/[%_\\]/g, "").slice(0, 40);
    if (q.length < 2) return [] as NotebookGroup[];
    const sql = await getSql();
    const rows = await sql<GroupRow>`
      select g.id, g.name, g.description, g.visibility, g.post_policy, g.created_by, g.updated_at,
        (select count(*)::int from notebook_group_members x where x.group_id = g.id and x.status = 'accepted') as member_count,
        (select "role" from notebook_group_members where group_id = g.id and user_id = ${context.userId}) as my_role,
        (select status from notebook_group_members where group_id = g.id and user_id = ${context.userId}) as my_status
      from notebook_groups g
      where g.visibility = 'listed' and g.name ilike ${"%" + q + "%"}
      order by g.updated_at desc
      limit 30
    `;
    return rows.map(fromGroup);
  });

export const getNotebookGroup = createServerFn({ method: "GET" })
  .middleware([authMiddleware])
  .validator((data: { id: string }) => data)
  .handler(async ({ context, data }) => {
    const sql = await getSql();
    const mine = await memberOf(sql, data.id, context.userId);
    // Same rule as native GET /groups/:id — accepted members only (no private metadata IDOR).
    if (!mine || mine.status !== "accepted") return null;
    const group = await loadGroup(sql, data.id, context.userId);
    if (!group) return null;
    return group;
  });

export const createNotebookGroup = createServerFn({ method: "POST" })
  .middleware([authMiddleware])
  .validator((data: { name: string; description?: string; visibility?: GroupVisibility }) => data)
  .handler(async ({ context, data }) => {
    const name = cleanName(data.name);
    if (name.length < 2) return { ok: false as const, error: "invalid" as const };
    if (!(await allowRequest(`gcreate:${context.userId}`, 20, 86_400_000))) {
      return { ok: false as const, error: "limit" as const };
    }
    const sql = await getSql();
    const created = await sql<{ n: number }>`
      select count(*)::int as n from notebook_groups where created_by = ${context.userId}
    `;
    if (Number(created[0]?.n ?? 0) >= MAX_CREATED) return { ok: false as const, error: "limit" as const };
    const memberships = await sql<{ n: number }>`
      select count(*)::int as n from notebook_group_members where user_id = ${context.userId} and status = 'accepted'
    `;
    if (Number(memberships[0]?.n ?? 0) >= MAX_MEMBERSHIPS) return { ok: false as const, error: "limit" as const };
    const id = newId();
    const visibility = data.visibility === "listed" ? "listed" : "private";
    const description = cleanDescription(data.description ?? "");
    await sql`
      with g as (
        insert into notebook_groups (id, name, description, visibility, post_policy, created_by, updated_at)
        values (${id}, ${name}, ${description}, ${visibility}, ${"members"}, ${context.userId}, now())
        returning id
      )
      insert into notebook_group_members (group_id, user_id, "role", status)
      select id, ${context.userId}, ${"admin"}, ${"accepted"} from g
    `;
    return { ok: true as const, id };
  });

export const updateNotebookGroup = createServerFn({ method: "POST" })
  .middleware([authMiddleware])
  .validator(
    (data: {
      id: string;
      name?: string;
      description?: string;
      visibility?: GroupVisibility;
      postPolicy?: GroupPostPolicy;
    }) => data,
  )
  .handler(async ({ context, data }) => {
    const sql = await getSql();
    const mine = await memberOf(sql, data.id, context.userId);
    if (mine?.role !== "admin" || mine.status !== "accepted") return { ok: false as const, error: "forbidden" as const };
    const current = await loadGroup(sql, data.id, context.userId);
    if (!current) return { ok: false as const, error: "missing" as const };
    const name = data.name != null ? cleanName(data.name) || current.name : current.name;
    const description = data.description != null ? cleanDescription(data.description) : current.description;
    const visibility = data.visibility ? asVisibility(data.visibility) : current.visibility;
    const postPolicy = data.postPolicy ? asPolicy(data.postPolicy) : current.postPolicy;
    await sql`
      update notebook_groups
      set name = ${name}, description = ${description}, visibility = ${visibility},
          post_policy = ${postPolicy}, updated_at = now()
      where id = ${data.id}
    `;
    return { ok: true as const };
  });

export const requestGroupJoin = createServerFn({ method: "POST" })
  .middleware([authMiddleware])
  .validator((data: { id: string }) => data)
  .handler(async ({ context, data }) => {
    if (!(await allowRequest(`gjoin:${context.userId}`, 30, 86_400_000))) {
      return { ok: false as const, error: "limit" as const };
    }
    const sql = await getSql();
    const group = await loadGroup(sql, data.id, context.userId);
    if (!group) return { ok: false as const, error: "missing" as const };
    const existing = await memberOf(sql, data.id, context.userId);
    if (existing) return { ok: true as const, error: null };
    const memberships = await sql<{ n: number }>`
      select count(*)::int as n from notebook_group_members where user_id = ${context.userId} and status = 'accepted'
    `;
    if (Number(memberships[0]?.n ?? 0) >= MAX_MEMBERSHIPS) return { ok: false as const, error: "limit" as const };
    await sql`
      insert into notebook_group_members (group_id, user_id, "role", status)
      values (${data.id}, ${context.userId}, ${"member"}, ${"pending"})
      on conflict (group_id, user_id) do nothing
    `;
    const admins = await sql<{ user_id: string }>`
      select user_id from notebook_group_members
      where group_id = ${data.id} and status = 'accepted' and "role" = 'admin'
    `;
    void import("@/lib/notify.server").then((mod) => {
      for (const admin of admins) {
        mod.notifySocial(context.userId, admin.user_id, "groups", "notifyGroupJoinTitle", "notifyGroupJoinBody", {
          plan: group.name,
          href: `/groups/${data.id}`,
        });
      }
    });
    return { ok: true as const, error: null };
  });

export const decideGroupMember = createServerFn({ method: "POST" })
  .middleware([authMiddleware])
  .validator((data: { id: string; userId: string; accept: boolean }) => data)
  .handler(async ({ context, data }) => {
    const sql = await getSql();
    const mine = await memberOf(sql, data.id, context.userId);
    if (mine?.role !== "admin" || mine.status !== "accepted") return { ok: false as const, error: "forbidden" as const };
    const other = await memberOf(sql, data.id, data.userId);
    if (!other || other.status !== "pending") return { ok: false as const, error: "missing" as const };
    if (data.accept) {
      await sql`
        update notebook_group_members set status = 'accepted'
        where group_id = ${data.id} and user_id = ${data.userId}
      `;
      const group = await loadGroup(sql, data.id, context.userId);
      void import("@/lib/notify.server").then((mod) =>
        mod.notifySocial(context.userId, data.userId, "groups", "notifyGroupAcceptTitle", "notifyGroupAcceptBody", {
          plan: group?.name ?? "",
          href: `/groups/${data.id}`,
        }),
      );
    } else {
      await sql`delete from notebook_group_members where group_id = ${data.id} and user_id = ${data.userId}`;
    }
    return { ok: true as const };
  });

export const setGroupMemberRole = createServerFn({ method: "POST" })
  .middleware([authMiddleware])
  .validator((data: { id: string; userId: string; role: GroupRole }) => data)
  .handler(async ({ context, data }) => {
    const sql = await getSql();
    const mine = await memberOf(sql, data.id, context.userId);
    if (mine?.role !== "admin" || mine.status !== "accepted") return { ok: false as const, error: "forbidden" as const };
    const other = await memberOf(sql, data.id, data.userId);
    if (!other || other.status !== "accepted") return { ok: false as const, error: "missing" as const };
    if (other.role === "admin" && data.role !== "admin" && (await adminCount(sql, data.id)) <= 1) {
      return { ok: false as const, error: "lastAdmin" as const };
    }
    await sql`
      update notebook_group_members set "role" = ${data.role}
      where group_id = ${data.id} and user_id = ${data.userId}
    `;
    if (data.role === "admin" && other.role !== "admin") {
      const group = await loadGroup(sql, data.id, context.userId);
      void import("@/lib/notify.server").then((mod) =>
        mod.notifySocial(context.userId, data.userId, "groups", "notifyGroupAdminTitle", "notifyGroupAdminBody", {
          plan: group?.name ?? "",
          href: `/groups/${data.id}`,
        }),
      );
    }
    return { ok: true as const };
  });

export const leaveNotebookGroup = createServerFn({ method: "POST" })
  .middleware([authMiddleware])
  .validator((data: { id: string; userId?: string }) => data)
  .handler(async ({ context, data }) => {
    const sql = await getSql();
    const target = data.userId || context.userId;
    const mine = await memberOf(sql, data.id, context.userId);
    if (!mine || mine.status !== "accepted") return { ok: false as const, error: "forbidden" as const };
    if (target !== context.userId && mine.role !== "admin") return { ok: false as const, error: "forbidden" as const };
    const other = await memberOf(sql, data.id, target);
    if (!other) return { ok: false as const, error: "missing" as const };
    if (other.role === "admin" && (await adminCount(sql, data.id)) <= 1) {
      return { ok: false as const, error: "lastAdmin" as const };
    }
    await sql`delete from notebook_group_members where group_id = ${data.id} and user_id = ${target}`;
    return { ok: true as const };
  });

export const deleteNotebookGroup = createServerFn({ method: "POST" })
  .middleware([authMiddleware])
  .validator((data: { id: string }) => data)
  .handler(async ({ context, data }) => {
    const sql = await getSql();
    const mine = await memberOf(sql, data.id, context.userId);
    if (mine?.role !== "admin" || mine.status !== "accepted") return { ok: false as const, error: "forbidden" as const };
    await sql`delete from notebook_group_notes where group_id = ${data.id}`;
    await sql`delete from notebook_group_invites where group_id = ${data.id}`;
    await sql`delete from notebook_group_members where group_id = ${data.id}`;
    await sql`delete from notebook_groups where id = ${data.id}`;
    return { ok: true as const };
  });

export const listGroupMembers = createServerFn({ method: "GET" })
  .middleware([authMiddleware])
  .validator((data: { id: string }) => data)
  .handler(async ({ context, data }) => {
    const sql = await getSql();
    const mine = await memberOf(sql, data.id, context.userId);
    if (mine?.status !== "accepted") return [] as GroupMember[];
    const rows = await sql<PrefRow & { role: string; status: string }>`
      select p.user_id, p.handle, p.first_name, p.last_name, p.avatar_id, p.avatar_url, m."role", m.status
      from notebook_group_members m
      join user_prefs p on p.user_id = m.user_id
      where m.group_id = ${data.id}
      order by m."role" asc, m.status asc, p.first_name
    `;
    return rows
      .filter((row) => mine.role === "admin" || row.status === "accepted")
      .map((row) => ({ ...person(row), role: asRole(row.role) ?? "member", status: asStatus(row.status) ?? "pending" }));
  });

export const listGroupNotes = createServerFn({ method: "POST" })
  .middleware([authMiddleware])
  .validator((data: { id: string }) => data)
  .handler(async ({ context, data }) => {
    const sql = await getSql();
    const rows = await sql<
      {
        id: string;
        title: string;
        happened_at: string;
        user_id: string;
        handle: string;
        first_name: string;
        last_name: string;
        avatar_id: string;
        avatar_url: string;
      }
    >`
      select n.id, n.title, n.happened_at::text,
             n.user_id, p.handle, p.first_name, p.last_name, p.avatar_id, p.avatar_url
      from notebook_group_notes g
      join notebook_notes n on n.id = g.note_id
      join user_prefs p on p.user_id = n.user_id
      join notebook_group_members m on m.group_id = g.group_id and m.user_id = ${context.userId} and m.status = 'accepted'
      where g.group_id = ${data.id}
      order by n.happened_at desc, n.updated_at desc
      limit 80
    `;
    return rows.map((row) => ({
      note: { id: row.id, title: row.title ?? "", happenedAt: typeof row.happened_at === "string" ? row.happened_at.slice(0, 10) : row.happened_at },
      author: person(row),
    }));
  });

export const listMyNoteGroups = createServerFn({ method: "GET" })
  .middleware([authMiddleware])
  .handler(async ({ context }) => {
    const sql = await getSql();
    const rows = await sql<{ note_id: string; group_id: string; name: string }>`
      select gn.note_id, g.id as group_id, g.name
      from notebook_notes n
      join notebook_group_notes gn on gn.note_id = n.id
      join notebook_groups g on g.id = gn.group_id
      where n.user_id = ${context.userId}
    `;
    const map: Record<string, { id: string; name: string }[]> = {};
    for (const row of rows) {
      (map[row.note_id] ??= []).push({ id: row.group_id, name: row.name });
    }
    return map;
  });

export const listNoteGroups = createServerFn({ method: "GET" })
  .middleware([authMiddleware])
  .validator((data: { noteId: string }) => data)
  .handler(async ({ context, data }) => {
    const sql = await getSql();
    // L2: require ownership or grant before revealing which of the caller's groups published the note.
    const owned = await sql<{ id: string }>`
      select id from notebook_notes where id = ${data.noteId} and user_id = ${context.userId} limit 1
    `;
    if (!owned[0]) {
      const granted = await sql<{ note_id: string }>`
        select note_id from note_grants where note_id = ${data.noteId} and user_id = ${context.userId} limit 1
      `;
      if (!granted[0]) return [];
    }
    const rows = await sql<{ group_id: string }>`
      select group_id from notebook_group_notes where note_id = ${data.noteId}
    `;
    const published = new Set(rows.map((row) => row.group_id));
    const mine = await sql<GroupRow>`
      select g.id, g.name, g.description, g.visibility, g.post_policy, g.created_by, g.updated_at,
        (select count(*)::int from notebook_group_members x where x.group_id = g.id and x.status = 'accepted') as member_count,
        m."role" as my_role, m.status as my_status
      from notebook_group_members m
      join notebook_groups g on g.id = m.group_id
      where m.user_id = ${context.userId} and m.status = 'accepted'
      order by g.updated_at desc
      limit 100
    `;
    return mine
      .map(fromGroup)
      .map((item) => ({ ...item, published: published.has(item.id) }));
  });

export const publishNoteToGroup = createServerFn({ method: "POST" })
  .middleware([authMiddleware])
  .validator((data: { groupId: string; note: Note }) => data)
  .handler(async ({ context, data }) => {
    const note = asNote(data.note);
    if (!note) return { ok: false as const, error: "invalid" as const };
    const sql = await getSql();
    const mine = await memberOf(sql, data.groupId, context.userId);
    if (mine?.status !== "accepted") return { ok: false as const, error: "forbidden" as const };
    const group = await loadGroup(sql, data.groupId, context.userId);
    if (!group) return { ok: false as const, error: "missing" as const };
    if (group.postPolicy === "admins" && mine.role !== "admin") return { ok: false as const, error: "forbidden" as const };
    const existing = await sql<{ user_id: string }>`
      select user_id from notebook_notes where id = ${note.id} limit 1
    `;
    if (existing[0] && existing[0].user_id !== context.userId) {
      return { ok: false as const, error: "forbidden" as const };
    }
    if (!existing[0]) {
      await sql`
        insert into notebook_notes (id, user_id, title, happened_at, tags, blocks, visibility, updated_at, speaker_id)
        values (
          ${note.id}, ${context.userId}, ${note.title}, ${note.happenedAt}::date,
          ${JSON.stringify(note.tags)}, ${JSON.stringify(note.blocks)}, ${note.visibility}, ${note.updatedAt}::timestamptz,
          ${note.speakerId}
        )
      `;
    } else {
      await sql`
        update notebook_notes
        set title = ${note.title}, happened_at = ${note.happenedAt}::date,
            tags = ${JSON.stringify(note.tags)}, blocks = ${JSON.stringify(note.blocks)},
            visibility = ${note.visibility}, updated_at = ${note.updatedAt}::timestamptz,
            speaker_id = ${note.speakerId}
        where id = ${note.id} and user_id = ${context.userId}
      `;
    }
    const count = await sql<{ n: number }>`
      select count(*)::int as n from notebook_group_notes where group_id = ${data.groupId}
    `;
    const already = await sql<{ note_id: string }>`
      select note_id from notebook_group_notes where group_id = ${data.groupId} and note_id = ${note.id}
    `;
    if (!already[0] && Number(count[0]?.n ?? 0) >= MAX_GROUP_NOTES) return { ok: false as const, error: "limit" as const };
    await sql`
      insert into notebook_group_notes (group_id, note_id, published_by)
      values (${data.groupId}, ${note.id}, ${context.userId})
      on conflict (group_id, note_id) do nothing
    `;
    if (!already[0]) {
      void import("@/lib/notify.server").then((mod) =>
        mod.notifyGroupNote(context.userId, data.groupId, group.name, note.id),
      );
    }
    return { ok: true as const };
  });

export const unpublishNoteFromGroup = createServerFn({ method: "POST" })
  .middleware([authMiddleware])
  .validator((data: { groupId: string; noteId: string }) => data)
  .handler(async ({ context, data }) => {
    const sql = await getSql();
    const mine = await memberOf(sql, data.groupId, context.userId);
    if (mine?.status !== "accepted") return { ok: false as const, error: "forbidden" as const };
    const owner = await sql<{ user_id: string }>`select user_id from notebook_notes where id = ${data.noteId}`;
    const isOwner = owner[0]?.user_id === context.userId;
    if (!isOwner && mine.role !== "admin") return { ok: false as const, error: "forbidden" as const };
    await sql`delete from notebook_group_notes where group_id = ${data.groupId} and note_id = ${data.noteId}`;
    return { ok: true as const };
  });
