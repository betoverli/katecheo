import { createServerFn } from "@tanstack/react-start";
import { authMiddleware } from "@/lib/auth/middleware";
import { planById } from "@/lib/bible/reading-plans";
import { getSql, type Sql } from "@/lib/db";
import { allowRequest } from "@/lib/rate-limit";

export type LinkPerson = {
  userId: string;
  handle: string;
  firstName: string;
  lastName: string;
  avatarId: string;
  avatarUrl: string;
};

export type LinkStatus = "none" | "self" | "incoming" | "outgoing" | "accepted";

export type PeopleHit = LinkPerson & { status: LinkStatus };

type PrefRow = {
  user_id: string;
  handle: string;
  first_name: string;
  last_name: string;
  avatar_id: string;
  avatar_url: string;
};

const MAX_FRIENDS = 80;

function newId() {
  return crypto.randomUUID().replaceAll("-", "");
}

function cleanHandle(value: string) {
  return value.trim().replace(/^@+/, "").toLowerCase().replace(/[^a-z0-9_]/g, "").slice(0, 20);
}

function cleanQuery(value: string) {
  return value.trim().replace(/^@+/, "").replace(/[%_\\]/g, "").slice(0, 24);
}

function person(row: PrefRow): LinkPerson {
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

async function pairStatus(sql: Sql, me: string, other: string): Promise<LinkStatus> {
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

async function friendCount(sql: Sql, userId: string) {
  const rows = await sql<{ n: number }>`
    select count(*)::int as n from user_links
    where status = 'accepted' and (requester_id = ${userId} or addressee_id = ${userId})
  `;
  return Number(rows[0]?.n ?? 0);
}

async function areFriends(sql: Sql, a: string, b: string) {
  return (await pairStatus(sql, a, b)) === "accepted";
}

async function addToHostGroup(sql: Sql, hostId: string, planId: string, memberId: string) {
  const existing = await sql<{ id: string }>`
    select id from plan_groups where host_id = ${hostId} and plan_id = ${planId} limit 1
  `;
  let groupId = existing[0]?.id;
  if (!groupId) {
    groupId = newId();
    await sql`insert into plan_groups (id, plan_id, host_id) values (${groupId}, ${planId}, ${hostId})`;
    await sql`insert into plan_group_members (group_id, user_id) values (${groupId}, ${hostId}) on conflict do nothing`;
  }
  await sql`
    insert into plan_group_members (group_id, user_id)
    values (${groupId}, ${memberId})
    on conflict do nothing
  `;
}

export const searchPeople = createServerFn({ method: "POST" })
  .middleware([authMiddleware])
  .validator((data: { q: string }) => data)
  .handler(async ({ context, data }) => {
    if (!(await allowRequest(`people:${context.userId}`, 30, 60_000))) return [] as PeopleHit[];
    const q = cleanQuery(data.q);
    if (q.length < 2) return [] as PeopleHit[];
    const sql = await getSql();
    const like = `${q}%`;
    const name = `%${q}%`;
    const rows = await sql<PrefRow & { link_status: string | null; requester_id: string | null }>`
      select p.user_id, p.handle, p.first_name, p.last_name, p.avatar_id, p.avatar_url,
             l.status as link_status, l.requester_id
      from user_prefs p
      left join user_links l
        on (l.requester_id = ${context.userId} and l.addressee_id = p.user_id)
        or (l.requester_id = p.user_id and l.addressee_id = ${context.userId})
      where p.handle is not null
        and length(trim(p.handle)) > 0
        and p.user_id <> ${context.userId}
        and (p.handle like ${like} or p.first_name ilike ${name} or p.last_name ilike ${name})
      order by p.handle
      limit 20
    `;
    return rows.map((row) => {
      let status: LinkStatus = "none";
      if (row.link_status === "accepted") status = "accepted";
      else if (row.link_status === "pending" && row.requester_id === context.userId) status = "outgoing";
      else if (row.link_status === "pending") status = "incoming";
      return { ...person(row), status };
    });
  });

export const listLinks = createServerFn({ method: "GET" })
  .middleware([authMiddleware])
  .handler(async ({ context }) => {
    const sql = await getSql();
    const rows = await sql<{ requester_id: string; addressee_id: string; status: string }>`
      select requester_id, addressee_id, status
      from user_links
      where requester_id = ${context.userId} or addressee_id = ${context.userId}
      order by created_at desc
    `;
    const friends: LinkPerson[] = [];
    const incoming: LinkPerson[] = [];
    const outgoing: LinkPerson[] = [];
    for (const row of rows) {
      const otherId = row.requester_id === context.userId ? row.addressee_id : row.requester_id;
      const pref = await prefsById(sql, otherId);
      if (!pref) continue;
      const item = person(pref);
      if (row.status === "accepted") friends.push(item);
      else if (row.requester_id === context.userId) outgoing.push(item);
      else incoming.push(item);
    }
    return { friends, incoming, outgoing };
  });

export const getLinkStatus = createServerFn({ method: "GET" })
  .middleware([authMiddleware])
  .validator((data: { handle: string }) => data)
  .handler(async ({ context, data }) => {
    const handle = cleanHandle(data.handle);
    if (!handle) return { status: "none" as const };
    const sql = await getSql();
    const other = await prefsByHandle(sql, handle);
    if (!other) return { status: "none" as const };
    return { status: await pairStatus(sql, context.userId, other.user_id) };
  });

export const requestLink = createServerFn({ method: "POST" })
  .middleware([authMiddleware])
  .validator((data: { handle: string }) => data)
  .handler(async ({ context, data }) => {
    if (!(await allowRequest(`link-req:${context.userId}`, 20, 86_400_000))) {
      return { ok: false as const, error: "limit" as const, status: "none" as const };
    }
    const handle = cleanHandle(data.handle);
    const sql = await getSql();
    const other = handle ? await prefsByHandle(sql, handle) : null;
    if (!other || other.user_id === context.userId) {
      return { ok: false as const, error: "missing" as const, status: "none" as const };
    }
    const current = await pairStatus(sql, context.userId, other.user_id);
    if (current === "accepted") return { ok: true as const, error: null, status: current };
    if (current === "outgoing") return { ok: true as const, error: null, status: current };
    if (current === "incoming") {
      const rows = await sql<{ id: string }>`
        update user_links set status = 'accepted'
        where requester_id = ${other.user_id} and addressee_id = ${context.userId} and status = 'pending'
        returning id
      `;
      if (!rows[0]) return { ok: false as const, error: "missing" as const, status: "none" as const };
      void import("@/lib/notify.server").then((mod) =>
        mod.notifySocial(context.userId, other.user_id, "friends", "notifyLinkAcceptedTitle", "notifyLinkAcceptedBody", {
          href: "/profile/friends",
        }),
      );
      return { ok: true as const, error: null, status: "accepted" as const };
    }
    if ((await friendCount(sql, context.userId)) >= MAX_FRIENDS) {
      return { ok: false as const, error: "limit" as const, status: "none" as const };
    }
    await sql`
      insert into user_links (id, requester_id, addressee_id, status)
      values (${newId()}, ${context.userId}, ${other.user_id}, ${"pending"})
      on conflict (requester_id, addressee_id) do nothing
    `;
    await sql`
      delete from user_links
      where requester_id = ${other.user_id} and addressee_id = ${context.userId} and status = 'pending'
    `;
    void import("@/lib/notify.server").then((mod) =>
      mod.notifySocial(context.userId, other.user_id, "friends", "notifyLinkTitle", "notifyLinkBody", {
        href: "/profile/friends",
      }),
    );
    return { ok: true as const, error: null, status: "outgoing" as const };
  });

export const acceptLink = createServerFn({ method: "POST" })
  .middleware([authMiddleware])
  .validator((data: { handle: string }) => data)
  .handler(async ({ context, data }) => {
    if (!(await allowRequest(`link-acc:${context.userId}`, 30, 86_400_000))) {
      return { ok: false as const };
    }
    const handle = cleanHandle(data.handle);
    const sql = await getSql();
    const other = handle ? await prefsByHandle(sql, handle) : null;
    if (!other) return { ok: false as const };
    if ((await friendCount(sql, context.userId)) >= MAX_FRIENDS) return { ok: false as const };
    const rows = await sql<{ id: string }>`
      update user_links set status = 'accepted'
      where requester_id = ${other.user_id} and addressee_id = ${context.userId} and status = 'pending'
      returning id
    `;
    if (!rows[0]) return { ok: false as const };
    void import("@/lib/notify.server").then((mod) =>
      mod.notifySocial(context.userId, other.user_id, "friends", "notifyLinkAcceptedTitle", "notifyLinkAcceptedBody", {
        href: "/profile/friends",
      }),
    );
    return { ok: true as const };
  });

export const declineLink = createServerFn({ method: "POST" })
  .middleware([authMiddleware])
  .validator((data: { handle: string }) => data)
  .handler(async ({ context, data }) => {
    const handle = cleanHandle(data.handle);
    const sql = await getSql();
    const other = handle ? await prefsByHandle(sql, handle) : null;
    if (!other) return { ok: false as const };
    await sql`
      delete from user_links
      where (requester_id = ${other.user_id} and addressee_id = ${context.userId})
         or (requester_id = ${context.userId} and addressee_id = ${other.user_id})
    `;
    await sql`
      delete from collection_grants
      where (from_id = ${context.userId} and user_id = ${other.user_id})
         or (from_id = ${other.user_id} and user_id = ${context.userId})
    `;
    await sql`
      delete from note_grants
      where (from_id = ${context.userId} and user_id = ${other.user_id})
         or (from_id = ${other.user_id} and user_id = ${context.userId})
    `;
    return { ok: true as const };
  });

export const sendPlanToFriend = createServerFn({ method: "POST" })
  .middleware([authMiddleware])
  .validator((data: { handle: string; planId: string }) => data)
  .handler(async ({ context, data }) => {
    if (!(await allowRequest(`send:${context.userId}`, 40, 86_400_000))) {
      return { ok: false as const, error: "limit" as const };
    }
    const plan = planById(data.planId);
    if (!plan) return { ok: false as const, error: "missing" as const };
    const handle = cleanHandle(data.handle);
    const sql = await getSql();
    const other = handle ? await prefsByHandle(sql, handle) : null;
    if (!other || !(await areFriends(sql, context.userId, other.user_id))) {
      return { ok: false as const, error: "missing" as const };
    }
    await addToHostGroup(sql, context.userId, plan.id, other.user_id);
    void import("@/lib/notify.server").then(async (mod) => {
      const localeRow = await sql<{ locale: string }>`select locale from user_prefs where user_id = ${other.user_id}`;
      const locale = localeRow[0]?.locale === "en" || localeRow[0]?.locale === "es" ? localeRow[0].locale : "pt";
      await mod.notifySocial(context.userId, other.user_id, "friends", "notifyPlanSendTitle", "notifyPlanSendBody", {
        plan: plan.names[locale],
        href: `/reading/${plan.id}`,
      });
    });
    return { ok: true as const, error: null };
  });

export const sendCollectionToFriend = createServerFn({ method: "POST" })
  .middleware([authMiddleware])
  .validator((data: { handle: string; collectionId: string }) => data)
  .handler(async ({ context, data }) => {
    if (!(await allowRequest(`send:${context.userId}`, 40, 86_400_000))) {
      return { ok: false as const, error: "limit" as const };
    }
    const handle = cleanHandle(data.handle);
    const sql = await getSql();
    const other = handle ? await prefsByHandle(sql, handle) : null;
    if (!other || !(await areFriends(sql, context.userId, other.user_id))) {
      return { ok: false as const, error: "missing" as const };
    }
    const owned = await sql<{ id: string; title: string }>`
      select id, title from user_collections
      where id = ${data.collectionId} and user_id = ${context.userId}
    `;
    const collection = owned[0];
    if (!collection) return { ok: false as const, error: "missing" as const };
    await sql`
      insert into collection_grants (collection_id, user_id, from_id)
      values (${collection.id}, ${other.user_id}, ${context.userId})
      on conflict (collection_id, user_id) do nothing
    `;
    void import("@/lib/notify.server").then((mod) =>
      mod.notifySocial(context.userId, other.user_id, "shares", "notifyCollectionSendTitle", "notifyCollectionSendBody", {
        plan: collection.title,
        href: `/c/${collection.id}`,
      }),
    );
    return { ok: true as const, error: null };
  });
