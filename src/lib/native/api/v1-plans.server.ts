/**
 * Native reading plans: catalog (public) + mark/reset/invite/join (auth).
 * Reuses the same SQL rules as the web createServerFns.
 */
import { resolvePlans, queryPlansFromSearch, type PlanQuery } from "@/lib/bible/plans-api";
import { planById } from "@/lib/bible/reading-plans";
import { getSql } from "@/lib/db";
import { progressFromMarks } from "@/lib/plan-marks";
import { getPrefsForUser, savePrefsForUser } from "./v1-profile.server";

const MAX_PER_DAY = 2;

function newId() {
  return crypto.randomUUID().replaceAll("-", "");
}

export function resolveNativePlans(search: URLSearchParams) {
  return resolvePlans(queryPlansFromSearch(search));
}

export function resolveNativePlansQuery(query: PlanQuery) {
  return resolvePlans(query);
}

export async function markPlanDayForUser(
  userId: string,
  planId: string,
  day: number,
  on: boolean,
): Promise<{ ok: true; error: null } | { ok: false; error: "missing" | "pace" }> {
  const plan = planById(planId);
  if (!plan || !Number.isInteger(day) || day < 1 || day > plan.days.length) {
    return { ok: false, error: "missing" };
  }
  const sql = await getSql();
  if (!on) {
    await sql`
      delete from plan_marks
      where user_id = ${userId} and plan_id = ${planId} and day = ${day}
    `;
    const progress = JSON.stringify(await progressFromMarks(sql, userId));
    await sql`
      update user_prefs set plan_progress = ${progress}, updated_at = now() where user_id = ${userId}
    `;
    return { ok: true, error: null };
  }
  const existing = await sql<{ day: number }>`
    select day from plan_marks
    where user_id = ${userId} and plan_id = ${planId} and day = ${day}
  `;
  if (existing[0]) return { ok: true, error: null };
  const today = await sql<{ n: number }>`
    select count(*)::int as n from plan_marks
    where user_id = ${userId} and marked_on = current_date
  `;
  if (Number(today[0]?.n ?? 0) >= MAX_PER_DAY) {
    return { ok: false, error: "pace" };
  }
  await sql`
    insert into plan_marks (user_id, plan_id, day, marked_on)
    values (${userId}, ${planId}, ${day}, current_date)
  `;
  const progress = JSON.stringify(await progressFromMarks(sql, userId));
  await sql`
    update user_prefs set plan_progress = ${progress}, updated_at = now() where user_id = ${userId}
  `;
  void import("@/lib/notify.server")
    .then((mod) => mod.notifyPlanMarked(userId, planId, day))
    .catch(() => undefined);
  return { ok: true, error: null };
}

export async function resetPlanMarksForUser(userId: string, planId: string) {
  const sql = await getSql();
  await sql`delete from plan_marks where user_id = ${userId} and plan_id = ${planId}`;
  const progress = JSON.stringify(await progressFromMarks(sql, userId));
  await sql`
    update user_prefs set plan_progress = ${progress}, updated_at = now() where user_id = ${userId}
  `;
  return { ok: true as const };
}

export async function startPlanForUser(userId: string, planId: string) {
  if (!planById(planId)) return { ok: false as const, error: "missing" as const };
  const prefs = await getPrefsForUser(userId);
  const active = [planId, ...prefs.activePlans.filter((id) => id !== planId)].slice(0, 20);
  const saved = await savePrefsForUser(userId, { activePlans: active });
  if (!saved.ok) return { ok: false as const, error: "missing" as const };
  return { ok: true as const, prefs: saved.prefs };
}

export async function stopPlanForUser(userId: string, planId: string) {
  const prefs = await getPrefsForUser(userId);
  const active = prefs.activePlans.filter((id) => id !== planId);
  const saved = await savePrefsForUser(userId, { activePlans: active });
  if (!saved.ok) return { ok: false as const, error: "missing" as const };
  return { ok: true as const, prefs: saved.prefs };
}

export async function createPlanInviteForUser(userId: string, planId: string) {
  if (!planById(planId)) return { ok: false as const, error: "missing" as const };
  const sql = await getSql();
  const existing = await sql<{ id: string }>`
    select id from plan_groups where host_id = ${userId} and plan_id = ${planId} limit 1
  `;
  if (existing[0]) {
    await sql`
      insert into plan_group_members (group_id, user_id)
      values (${existing[0].id}, ${userId})
      on conflict do nothing
    `;
    return { ok: true as const, id: existing[0].id };
  }
  const id = newId();
  await sql`
    insert into plan_groups (id, plan_id, host_id) values (${id}, ${planId}, ${userId})
  `;
  await sql`
    insert into plan_group_members (group_id, user_id) values (${id}, ${userId})
  `;
  return { ok: true as const, id };
}

export async function joinPlanGroupForUser(userId: string, groupId: string) {
  const sql = await getSql();
  const groups = await sql<{ id: string; plan_id: string }>`
    select id, plan_id from plan_groups where id = ${groupId}
  `;
  const group = groups[0];
  if (!group) return { ok: false as const, error: "missing" as const, planId: "" };
  await sql`
    insert into plan_group_members (group_id, user_id)
    values (${group.id}, ${userId})
    on conflict do nothing
  `;
  void import("@/lib/notify.server")
    .then((mod) => mod.notifyPlanJoined(userId, group.id, group.plan_id))
    .catch(() => undefined);
  await startPlanForUser(userId, group.plan_id);
  return { ok: true as const, planId: group.plan_id, error: null };
}

export async function getPlanGroupPreviewForUser(groupId: string, userId?: string) {
  const sql = await getSql();
  const groups = await sql<{ id: string; plan_id: string; host_id: string }>`
    select id, plan_id, host_id from plan_groups where id = ${groupId}
  `;
  const group = groups[0];
  if (!group) return null;
  const memberRows = await sql<{ user_id: string }>`
    select user_id from plan_group_members where group_id = ${groupId} order by joined_at
  `;
  const members = [];
  for (const row of memberRows) {
    const prefs = await sql<{
      handle: string;
      first_name: string;
      avatar_id: string;
      avatar_url: string;
    }>`
      select handle, first_name, avatar_id, avatar_url from user_prefs where user_id = ${row.user_id}
    `;
    const pref = prefs[0];
    const marks = await sql<{ day: number }>`
      select day from plan_marks where user_id = ${row.user_id} and plan_id = ${group.plan_id}
    `;
    members.push({
      userId: row.user_id,
      handle: pref?.handle ?? "",
      firstName: pref?.first_name ?? "",
      avatarId: pref?.avatar_id || "book",
      avatarUrl: pref?.avatar_url ?? "",
      days: marks.map((item) => Number(item.day)).filter((n) => Number.isInteger(n) && n > 0),
      me: userId ? row.user_id === userId : false,
    });
  }
  return {
    id: group.id,
    planId: group.plan_id,
    hostId: group.host_id,
    members,
  };
}
