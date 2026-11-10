import { createServerFn } from "@tanstack/react-start";
import { adminEmails, adminHandles } from "@/lib/admin";
import { authMiddleware } from "@/lib/auth/middleware";
import { getSql } from "@/lib/db";

export type UsageDay = {
  day: string;
  visits: number;
  pageviews: number;
  signedIn: number;
  signups: number;
};

export type UsageStats = {
  users: number;
  users7: number;
  users30: number;
  collections: number;
  plans: number;
  visitsToday: number;
  visits7: number;
  pageviewsToday: number;
  providers: { provider: string; n: number }[];
  days: UsageDay[];
};

function asInt(value: unknown) {
  const n = Number(value);
  return Number.isFinite(n) ? n : 0;
}

function dayKey(value: unknown) {
  return String(value ?? "").slice(0, 10);
}

async function assertAdmin(userId: string) {
  const sql = await getSql();
  const users = await sql<{ email: string | null }>`
    select email from "user" where id = ${userId}
  `;
  const email = (users[0]?.email ?? "").toLowerCase();
  if (email && adminEmails().includes(email)) return;
  const prefs = await sql<{ handle: string | null }>`
    select handle from user_prefs where user_id = ${userId}
  `;
  const handle = (prefs[0]?.handle ?? "").toLowerCase();
  if (handle && adminHandles().includes(handle)) return;
  throw new Error("Forbidden");
}

export const pingVisit = createServerFn({ method: "POST" })
  .validator((data: { first?: boolean }) => data)
  .handler(async ({ data }) => {
    const { assertSameSiteRequest } = await import("@/lib/auth/isolation.server");
    assertSameSiteRequest();
    const { getRequest } = await import("@tanstack/react-start/server");
    const { allowRequest, clientKey } = await import("@/lib/rate-limit");
    const request = getRequest();
    if (request && !(await allowRequest(`visit:${clientKey(request)}`, 40, 60_000))) {
      return { ok: true as const };
    }
    let signed = 0;
    if (data.first) {
      try {
        const { auth } = await import("@/lib/auth/server");
        const session = request ? await auth.api.getSession({ headers: request.headers }) : null;
        if (session?.user) signed = 1;
      } catch {
        signed = 0;
      }
    }
    const sql = await getSql();
    const visit = data.first ? 1 : 0;
    await sql`
      insert into usage_daily (day, visits, pageviews, signed_in)
      values (current_date, ${visit}, 1, ${signed})
      on conflict (day) do update set
        visits = usage_daily.visits + excluded.visits,
        pageviews = usage_daily.pageviews + 1,
        signed_in = usage_daily.signed_in + excluded.signed_in
    `;
    void import("@/lib/notify.server")
      .then((mod) => mod.maybeSendDigests())
      .catch(() => undefined);
    return { ok: true as const };
  });

export const getIsAdmin = createServerFn({ method: "GET" })
  .middleware([authMiddleware])
  .handler(async ({ context }) => {
    try {
      await assertAdmin(context.userId);
      return true;
    } catch {
      return false;
    }
  });

export const getUsageStats = createServerFn({ method: "GET" })
  .middleware([authMiddleware])
  .handler(async ({ context }) => {
    await assertAdmin(context.userId);
    const sql = await getSql();
    const users = await sql<{ n: number }>`select count(*)::int as n from "user"`;
    const users7 = await sql<{ n: number }>`
      select count(*)::int as n from "user" where "createdAt" >= now() - interval '7 days'
    `;
    const users30 = await sql<{ n: number }>`
      select count(*)::int as n from "user" where "createdAt" >= now() - interval '30 days'
    `;
    const collections = await sql<{ n: number }>`select count(*)::int as n from user_collections`;
    const planRows = await sql<{ active_plans: string }>`select active_plans from user_prefs`;
    let plans = 0;
    for (const row of planRows) {
      try {
        const parsed = JSON.parse(row.active_plans || "[]") as unknown;
        if (Array.isArray(parsed)) plans += parsed.length;
      } catch {
        /* ignore */
      }
    }
    const today = await sql<{ visits: number; pageviews: number }>`
      select visits, pageviews from usage_daily where day = current_date
    `;
    const week = await sql<{ visits: number }>`
      select coalesce(sum(visits), 0)::int as visits
      from usage_daily
      where day >= current_date - 6
    `;
    const providers = await sql<{ provider: string; n: number }>`
      select "providerId" as provider, count(*)::int as n from account group by 1 order by n desc
    `;
    const usageDays = await sql<{ day: string; visits: number; pageviews: number; signed_in: number }>`
      select day, visits, pageviews, signed_in
      from usage_daily
      where day >= current_date - 13
      order by day desc
    `;
    const signupDays = await sql<{ day: string; n: number }>`
      select to_char("createdAt"::date, 'YYYY-MM-DD') as day, count(*)::int as n
      from "user"
      where "createdAt" >= now() - interval '14 days'
      group by 1
    `;
    const signupMap = new Map(signupDays.map((row) => [dayKey(row.day), asInt(row.n)]));
    const dayMap = new Map<string, UsageDay>();
    for (const row of usageDays) {
      const day = dayKey(row.day);
      dayMap.set(day, {
        day,
        visits: asInt(row.visits),
        pageviews: asInt(row.pageviews),
        signedIn: asInt(row.signed_in),
        signups: signupMap.get(day) ?? 0,
      });
    }
    for (const [day, n] of signupMap) {
      if (!dayMap.has(day)) {
        dayMap.set(day, { day, visits: 0, pageviews: 0, signedIn: 0, signups: n });
      }
    }
    const days = [...dayMap.values()].sort((a, b) => (a.day < b.day ? 1 : -1));
    return {
      users: asInt(users[0]?.n),
      users7: asInt(users7[0]?.n),
      users30: asInt(users30[0]?.n),
      collections: asInt(collections[0]?.n),
      plans,
      visitsToday: asInt(today[0]?.visits),
      visits7: asInt(week[0]?.visits),
      pageviewsToday: asInt(today[0]?.pageviews),
      providers: providers.map((row) => ({ provider: row.provider, n: asInt(row.n) })),
      days,
    } satisfies UsageStats;
  });
