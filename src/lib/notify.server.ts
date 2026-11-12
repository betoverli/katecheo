import webpush from "web-push";
import type { Locale } from "@/lib/bible/books";
import { bookById } from "@/lib/bible/books";
import { formatPassage } from "@/lib/bible/passage";
import { planById, readingToPassage } from "@/lib/bible/reading-plans";
import { getSql, type Sql } from "@/lib/db";
import { t, type I18nKey } from "@/lib/i18n";
import { decodeInboxCursor, encodeInboxCursor } from "@/lib/notify-cursor";
import { allowRequest } from "@/lib/rate-limit";
import { publicBaseUrl } from "@/lib/site";

export { encodeInboxCursor, decodeInboxCursor } from "@/lib/notify-cursor";

export type NotifyKind = "reading" | "friends" | "shares" | "groups";

export type NotifyPrefs = {
  reading: boolean;
  friends: boolean;
  shares: boolean;
  groups: boolean;
};

export type InboxItem = {
  id: string;
  kind: NotifyKind;
  title: string;
  body: string;
  href: string;
  read: boolean;
  createdAt: string;
};

const VAPID_SUB = publicBaseUrl();
/** Retention for *read* rows only — unread are never trimmed (dots/pagination need them). */
const MAX_READ_RETAINED = 100;
/** Default page size for cursor inbox (native + web first page). */
export const INBOX_PAGE_SIZE = 50;

function asLocale(value: string): Locale {
  return value === "en" || value === "es" || value === "pt" ? value : "pt";
}

function asKind(value: string): NotifyKind {
  return value === "friends" || value === "shares" || value === "groups" || value === "reading" ? value : "reading";
}

function newId() {
  return crypto.randomUUID().replaceAll("-", "");
}

function safeHref(value: string) {
  if (!value.startsWith("/") || value.startsWith("//")) return "/app";
  return value.slice(0, 200);
}

function fill(template: string, vars: Record<string, string>) {
  return template.replace(/\{(\w+)\}/g, (_, key: string) => vars[key] ?? "");
}

function isProductionRuntime() {
  const vercel = process.env.VERCEL_ENV;
  if (vercel === "production") return true;
  if (vercel === "preview" || vercel === "development") return false;
  return process.env.NODE_ENV === "production";
}

/**
 * Resolve VAPID keys. Production requires `VAPID_PUBLIC_KEY` + `VAPID_PRIVATE_KEY`
 * and never generates/stores new keys. Existing `push_config` rows are left intact.
 */
async function loadKeys(sql: Sql): Promise<{ publicKey: string; privateKey: string } | null> {
  const envPub = process.env.VAPID_PUBLIC_KEY?.trim();
  const envPriv = process.env.VAPID_PRIVATE_KEY?.trim();
  if (envPub && envPriv) {
    await sql`
      insert into push_config (id, public_key, private_key)
      values (1, ${envPub}, ${envPriv})
      on conflict (id) do nothing
    `;
    return { publicKey: envPub, privateKey: envPriv };
  }
  if (isProductionRuntime()) {
    console.warn(
      "[notify] VAPID_PUBLIC_KEY / VAPID_PRIVATE_KEY unset in production — refusing web push (not generating keys)",
    );
    return null;
  }
  const rows = await sql<{ public_key: string; private_key: string }>`
    select public_key, private_key from push_config where id = 1
  `;
  if (rows[0]) return { publicKey: rows[0].public_key, privateKey: rows[0].private_key };
  const generated = webpush.generateVAPIDKeys();
  await sql`
    insert into push_config (id, public_key, private_key)
    values (1, ${generated.publicKey}, ${generated.privateKey})
    on conflict (id) do nothing
  `;
  const again = await sql<{ public_key: string; private_key: string }>`
    select public_key, private_key from push_config where id = 1
  `;
  return {
    publicKey: again[0]?.public_key ?? generated.publicKey,
    privateKey: again[0]?.private_key ?? generated.privateKey,
  };
}

export async function vapidPublicKey() {
  const sql = await getSql();
  const keys = await loadKeys(sql);
  return keys?.publicKey ?? null;
}

async function trimInbox(sql: Sql, userId: string) {
  // Never delete unread — only prune older read rows beyond retention.
  await sql`
    delete from notifications
    where user_id = ${userId}
      and read_at is not null
      and id not in (
        select id from notifications
        where user_id = ${userId} and read_at is not null
        order by created_at desc, id desc
        limit ${MAX_READ_RETAINED}
      )
  `;
}

async function pushToUser(
  sql: Sql,
  userId: string,
  payload: { title: string; body: string; href: string },
) {
  const keys = await loadKeys(sql);
  if (keys) {
    webpush.setVapidDetails(VAPID_SUB, keys.publicKey, keys.privateKey);
    const subs = await sql<{ endpoint: string; p256dh: string; auth: string }>`
      select endpoint, p256dh, auth from push_subscriptions where user_id = ${userId}
    `;
    const body = JSON.stringify(payload);
    for (const sub of subs) {
      try {
        await webpush.sendNotification(
          { endpoint: sub.endpoint, keys: { p256dh: sub.p256dh, auth: sub.auth } },
          body,
          { TTL: 86_400 },
        );
      } catch (err) {
        const status = (err as { statusCode?: number }).statusCode;
        if (status === 404 || status === 410) {
          await sql`delete from push_subscriptions where endpoint = ${sub.endpoint}`;
        }
      }
    }
  }
  try {
    const { sendApnsToUser } = await import("./apns.server");
    await sendApnsToUser(sql, userId, payload);
  } catch {
    /* APNs is additive. A missing key or a bad device must not fail web push. */
  }
}

async function deliver(
  userId: string,
  kind: NotifyKind,
  locale: Locale,
  titleKey: I18nKey,
  bodyKey: I18nKey,
  vars: Record<string, string>,
  opts?: { push?: boolean },
) {
  const sql = await getSql();
  const prefs = await sql<{
    notify_reading: boolean;
    notify_friends: boolean;
    notify_shares: boolean;
    notify_groups: boolean | null;
  }>`
    select notify_reading, notify_friends, notify_shares, notify_groups from user_prefs where user_id = ${userId}
  `;
  const pref = prefs[0];
  if (!pref) return;
  if (kind === "reading" && !pref.notify_reading) return;
  if (kind === "friends" && !pref.notify_friends) return;
  if (kind === "shares" && !pref.notify_shares) return;
  if (kind === "groups" && pref.notify_groups === false) return;

  const title = fill(t(locale, titleKey), vars).slice(0, 120);
  const body = fill(t(locale, bodyKey), vars).slice(0, 240);
  const href = safeHref(vars.href || "/app");
  const id = newId();
  await sql`
    insert into notifications (id, user_id, kind, title, body, href)
    values (${id}, ${userId}, ${kind}, ${title}, ${body}, ${href})
  `;
  await trimInbox(sql, userId);
  if (opts?.push !== false) await pushToUser(sql, userId, { title, body, href });
}

async function userLocale(sql: Sql, userId: string): Promise<Locale> {
  const rows = await sql<{ locale: string }>`select locale from user_prefs where user_id = ${userId}`;
  return asLocale(rows[0]?.locale ?? "pt");
}

async function actorName(sql: Sql, userId: string, locale: Locale) {
  const rows = await sql<{ handle: string; first_name: string }>`
    select handle, first_name from user_prefs where user_id = ${userId}
  `;
  if (rows[0]?.handle) return `@${rows[0].handle}`;
  if (rows[0]?.first_name) return rows[0].first_name;
  return t(locale, "notifySomeone");
}

export async function notifySocial(
  actorId: string,
  targetId: string,
  kind: NotifyKind,
  titleKey: I18nKey,
  bodyKey: I18nKey,
  extra: Record<string, string> = {},
) {
  if (!actorId || !targetId || actorId === targetId) return;
  const sql = await getSql();
  // Guideline 1.2: blocker must not see friend activity from a blocked user.
  const { blockedIdsForUser } = await import("@/lib/native/api/v1-moderation.server");
  const blocked = await blockedIdsForUser(targetId, sql);
  if (blocked.has(actorId)) return;
  const locale = await userLocale(sql, targetId);
  const name = await actorName(sql, actorId, locale);
  await deliver(targetId, kind, locale, titleKey, bodyKey, { name, ...extra });
}

export async function notifyGroupNote(actorId: string, groupId: string, groupName: string, noteId: string) {
  if (!actorId || !groupId) return;
  const sql = await getSql();
  const members = await sql<{ user_id: string }>`
    select user_id from notebook_group_members
    where group_id = ${groupId} and status = 'accepted' and user_id <> ${actorId}
  `;
  if (!members.length) return;
  const { blockedIdsForUser } = await import("@/lib/native/api/v1-moderation.server");
  const locale = await userLocale(sql, members[0]!.user_id);
  const name = await actorName(sql, actorId, locale);
  const push = await allowRequest(`gnote-push:${groupId}`, 1, 15 * 60 * 1000);
  for (const member of members) {
    const blocked = await blockedIdsForUser(member.user_id, sql);
    if (blocked.has(actorId)) continue;
    const loc = await userLocale(sql, member.user_id);
    const who = loc === locale ? name : await actorName(sql, actorId, loc);
    await deliver(
      member.user_id,
      "groups",
      loc,
      "notifyGroupNoteTitle",
      "notifyGroupNoteBody",
      { name: who, plan: groupName, href: `/n/${noteId}?g=${groupId}` },
      { push },
    );
  }
}

export async function notifyPlanMarked(actorId: string, planId: string, day: number) {
  const plan = planById(planId);
  if (!plan) return;
  const sql = await getSql();
  const members = await sql<{ user_id: string }>`
    select distinct m.user_id
    from plan_group_members m
    join plan_groups g on g.id = m.group_id
    where g.plan_id = ${planId}
      and m.user_id <> ${actorId}
      and exists (
        select 1 from plan_group_members me
        where me.group_id = m.group_id and me.user_id = ${actorId}
      )
  `;
  for (const row of members) {
    const locale = await userLocale(sql, row.user_id);
    const name = await actorName(sql, actorId, locale);
    await deliver(row.user_id, "friends", locale, "notifyFriendTitle", "notifyFriendBody", {
      name,
      day: String(day),
      plan: plan.names[locale],
      href: `/reading/${planId}`,
    });
  }
}

export async function notifyPlanJoined(actorId: string, groupId: string, planId: string) {
  const plan = planById(planId);
  if (!plan) return;
  const sql = await getSql();
  const members = await sql<{ user_id: string }>`
    select user_id from plan_group_members where group_id = ${groupId} and user_id <> ${actorId}
  `;
  for (const row of members) {
    const locale = await userLocale(sql, row.user_id);
    const name = await actorName(sql, actorId, locale);
    await deliver(row.user_id, "friends", locale, "notifyJoinTitle", "notifyJoinBody", {
      name,
      plan: plan.names[locale],
      href: `/reading/${planId}`,
    });
  }
}

export async function notifyCollectionRemix(actorId: string, ownerId: string, title: string, collectionId: string) {
  if (!ownerId || ownerId === actorId) return;
  const sql = await getSql();
  const locale = await userLocale(sql, ownerId);
  const name = await actorName(sql, actorId, locale);
  await deliver(ownerId, "shares", locale, "notifyShareTitle", "notifyShareBody", {
    name,
    plan: title,
    href: `/c/${collectionId}`,
  });
}

function dayPassages(planId: string, day: number, locale: Locale) {
  const plan = planById(planId);
  const row = plan?.days.find((item) => item.day === day);
  if (!row) return "";
  return row.readings
    .map((reading) => {
      const book = bookById(reading.bookId);
      return book ? formatPassage(book, readingToPassage(reading), locale) : "";
    })
    .filter(Boolean)
    .join(" · ");
}

export async function maybeSendDigests() {
  const sql = await getSql();
  await loadKeys(sql);
  const claimed = await sql<{ last_digest: string | null }>`
    update push_config
    set last_digest = current_date
    where id = 1 and (last_digest is null or last_digest < current_date)
    returning last_digest
  `;
  if (!claimed[0]) return;
  const users = await sql<{ user_id: string; locale: string; active_plans: string }>`
    select user_id, locale, active_plans from user_prefs where notify_reading = true
  `;
  for (const user of users) {
    const already = await sql<{ n: number }>`
      select count(*)::int as n
      from notifications
      where user_id = ${user.user_id} and kind = 'reading' and created_at::date = current_date
    `;
    if (Number(already[0]?.n ?? 0) > 0) continue;
    let plans: string[] = [];
    try {
      const parsed = JSON.parse(user.active_plans || "[]") as unknown;
      if (Array.isArray(parsed)) plans = parsed.filter((id): id is string => typeof id === "string");
    } catch {
      plans = [];
    }
    const marks = await sql<{ plan_id: string; day: number }>`
      select plan_id, day from plan_marks where user_id = ${user.user_id}
    `;
    const done = new Map<string, Set<number>>();
    for (const row of marks) {
      const set = done.get(row.plan_id) ?? new Set<number>();
      set.add(Number(row.day));
      done.set(row.plan_id, set);
    }
    const locale = asLocale(user.locale);
    for (const planId of plans) {
      const plan = planById(planId);
      if (!plan) continue;
      const read = done.get(planId) ?? new Set<number>();
      const next = plan.days.find((item) => !read.has(item.day));
      if (!next) continue;
      await deliver(user.user_id, "reading", locale, "notifyReadingTitle", "notifyReadingBody", {
        day: String(next.day),
        plan: plan.names[locale],
        passages: dayPassages(planId, next.day, locale),
        href: `/reading/${planId}`,
      });
      break;
    }
  }
}

export async function saveSubscription(
  userId: string,
  data: { endpoint: string; p256dh: string; auth: string },
) {
  if (!data.endpoint.startsWith("https://")) return { ok: false as const };
  let host = "";
  try {
    host = new URL(data.endpoint).hostname;
  } catch {
    return { ok: false as const };
  }
  const allowed =
    host.endsWith(".googleapis.com") ||
    host.endsWith(".mozilla.com") ||
    host.endsWith(".push.apple.com") ||
    host.endsWith(".windows.com") ||
    host.endsWith(".microsoft.com");
  if (!allowed) return { ok: false as const };
  const p256dh = data.p256dh.slice(0, 200);
  const auth = data.auth.slice(0, 200);
  if (!p256dh || !auth) return { ok: false as const };
  const sql = await getSql();
  await sql`
    insert into push_subscriptions (endpoint, user_id, p256dh, auth)
    values (${data.endpoint.slice(0, 2000)}, ${userId}, ${p256dh}, ${auth})
    on conflict (endpoint) do update set p256dh = excluded.p256dh, auth = excluded.auth
    where push_subscriptions.user_id = excluded.user_id
  `;
  return { ok: true as const };
}

export async function dropSubscription(userId: string, endpoint: string) {
  const sql = await getSql();
  await sql`delete from push_subscriptions where user_id = ${userId} and endpoint = ${endpoint}`;
}

export async function hasSubscription(userId: string) {
  const sql = await getSql();
  const rows = await sql<{ n: number }>`
    select count(*)::int as n from push_subscriptions where user_id = ${userId}
  `;
  return Number(rows[0]?.n ?? 0) > 0;
}

export async function loadPrefs(userId: string): Promise<NotifyPrefs> {
  const sql = await getSql();
  const rows = await sql<{
    notify_reading: boolean;
    notify_friends: boolean;
    notify_shares: boolean;
    notify_groups: boolean | null;
  }>`
    select notify_reading, notify_friends, notify_shares, notify_groups from user_prefs where user_id = ${userId}
  `;
  const row = rows[0];
  return {
    reading: row?.notify_reading !== false,
    friends: row?.notify_friends !== false,
    shares: row?.notify_shares !== false,
    groups: row?.notify_groups !== false,
  };
}

export async function savePrefs(userId: string, patch: Partial<NotifyPrefs>) {
  const current = await loadPrefs(userId);
  const reading = patch.reading ?? current.reading;
  const friends = patch.friends ?? current.friends;
  const shares = patch.shares ?? current.shares;
  const groups = patch.groups ?? current.groups;
  const sql = await getSql();
  await sql`
    update user_prefs
    set notify_reading = ${reading}, notify_friends = ${friends}, notify_shares = ${shares},
        notify_groups = ${groups}, updated_at = now()
    where user_id = ${userId}
  `;
  return { reading, friends, shares, groups };
}

type InboxRow = {
  id: string;
  kind: string;
  title: string;
  body: string;
  href: string;
  read_at: string | null;
  created_at: string;
};

function mapInboxRow(row: InboxRow): InboxItem {
  return {
    id: row.id,
    kind: asKind(row.kind),
    title: row.title,
    body: row.body,
    href: safeHref(row.href),
    read: Boolean(row.read_at),
    createdAt: String(row.created_at),
  };
}

export type InboxPage = {
  items: InboxItem[];
  nextCursor: string | null;
};

/**
 * Cursor page over inbox. Stable order: created_at DESC, id DESC.
 * `unreadOnly` skips read rows (for activity-dot sync).
 */
export async function listInboxPage(
  userId: string,
  opts: { cursor?: string | null; limit?: number; unreadOnly?: boolean } = {},
): Promise<InboxPage> {
  const sql = await getSql();
  const limit = Math.min(Math.max(Math.floor(opts.limit ?? INBOX_PAGE_SIZE), 1), 100);
  const decoded = decodeInboxCursor(opts.cursor ?? null);
  const unreadOnly = opts.unreadOnly === true;

  let rows: InboxRow[];
  if (decoded) {
    if (unreadOnly) {
      rows = await sql<InboxRow>`
        select id, kind, title, body, href, read_at, created_at
        from notifications
        where user_id = ${userId}
          and read_at is null
          and (created_at, id) < (${decoded.createdAt}::timestamptz, ${decoded.id})
        order by created_at desc, id desc
        limit ${limit + 1}
      `;
    } else {
      rows = await sql<InboxRow>`
        select id, kind, title, body, href, read_at, created_at
        from notifications
        where user_id = ${userId}
          and (created_at, id) < (${decoded.createdAt}::timestamptz, ${decoded.id})
        order by created_at desc, id desc
        limit ${limit + 1}
      `;
    }
  } else if (unreadOnly) {
    rows = await sql<InboxRow>`
      select id, kind, title, body, href, read_at, created_at
      from notifications
      where user_id = ${userId} and read_at is null
      order by created_at desc, id desc
      limit ${limit + 1}
    `;
  } else {
    rows = await sql<InboxRow>`
      select id, kind, title, body, href, read_at, created_at
      from notifications
      where user_id = ${userId}
      order by created_at desc, id desc
      limit ${limit + 1}
    `;
  }

  const hasMore = rows.length > limit;
  const page = hasMore ? rows.slice(0, limit) : rows;
  const last = page[page.length - 1];
  return {
    items: page.map(mapInboxRow),
    nextCursor: hasMore && last ? encodeInboxCursor(String(last.created_at), last.id) : null,
  };
}

/** Web-compatible first page (no cursor). */
export async function listInbox(userId: string): Promise<InboxItem[]> {
  const page = await listInboxPage(userId, { limit: INBOX_PAGE_SIZE });
  return page.items;
}

export async function unreadCount(userId: string) {
  const sql = await getSql();
  const rows = await sql<{ n: number }>`
    select count(*)::int as n from notifications where user_id = ${userId} and read_at is null
  `;
  return Number(rows[0]?.n ?? 0);
}

export async function unreadCountsByKind(userId: string) {
  const sql = await getSql();
  const rows = await sql<{ kind: string; n: number }>`
    select kind, count(*)::int as n
    from notifications
    where user_id = ${userId} and read_at is null
    group by kind
  `;
  const byKind: Record<NotifyKind, number> = { reading: 0, friends: 0, shares: 0, groups: 0 };
  for (const row of rows) {
    const kind = asKind(row.kind);
    byKind[kind] = Number(row.n ?? 0);
  }
  return byKind;
}

/** Counts + first unread page for native activity dots (client continues with cursor). */
export async function unreadSummary(
  userId: string,
  opts: { limit?: number } = {},
): Promise<{
  unread: number;
  byKind: Record<NotifyKind, number>;
  items: InboxItem[];
  nextCursor: string | null;
}> {
  const byKind = await unreadCountsByKind(userId);
  const unread = Object.values(byKind).reduce((a, b) => a + b, 0);
  const page = await listInboxPage(userId, { unreadOnly: true, limit: opts.limit ?? INBOX_PAGE_SIZE });
  return { unread, byKind, items: page.items, nextCursor: page.nextCursor };
}

export async function markRead(userId: string, id?: string) {
  const sql = await getSql();
  if (id) {
    await sql`
      update notifications set read_at = now()
      where user_id = ${userId} and id = ${id} and read_at is null
    `;
  } else {
    await sql`
      update notifications set read_at = now()
      where user_id = ${userId} and read_at is null
    `;
  }
}

/**
 * Remove one inbox row for this user. Friend/group link rows are untouched —
 * deleting a connection-request alert only clears the notice, not the request.
 */
export async function deleteNotification(userId: string, id: string) {
  const sql = await getSql();
  const trimmed = id.trim();
  if (!trimmed) return { ok: true as const, deleted: false };
  const rows = await sql<{ id: string }>`
    delete from notifications
    where user_id = ${userId} and id = ${trimmed}
    returning id
  `;
  return { ok: true as const, deleted: rows.length > 0 };
}

/** Wipe the user's notification inbox (alerts only — not Friends requests). */
export async function clearNotifications(userId: string) {
  const sql = await getSql();
  await sql`delete from notifications where user_id = ${userId}`;
  return { ok: true as const };
}
