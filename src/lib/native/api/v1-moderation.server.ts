/**
 * Native report & block (App Store Guideline 1.2 — UGC).
 * Tables: user_block, content_report (migration 0028).
 */
import { getSql, type Sql } from "@/lib/db";
import { allowRequest } from "@/lib/rate-limit";
import { sendResendEmail } from "@/lib/auth/resend-email.server";
import { CONTACT_EMAIL } from "@/lib/app-store";

export type ReportTargetType = "user" | "note" | "group";
export type ReportReason = "spam" | "offensive" | "inappropriate" | "other";

export type NativeBlockedPerson = {
  userId: string;
  handle: string;
  firstName: string;
  lastName: string;
  avatarId: string;
  avatarUrl: string;
  blockedAt: string;
};

function newId() {
  return crypto.randomUUID().replaceAll("-", "");
}

/** Ids the viewer has blocked (content hide + friend activity). */
export async function blockedIdsForUser(userId: string, sql?: Sql): Promise<Set<string>> {
  const db = sql ?? (await getSql());
  const rows = await db<{ blocked_id: string }>`
    select blocked_id from user_block where blocker_id = ${userId}
  `;
  return new Set(rows.map((r) => r.blocked_id));
}

/** True if either side has blocked the other (blocks friend requests both ways). */
export async function isEitherBlocked(a: string, b: string, sql?: Sql): Promise<boolean> {
  if (!a || !b || a === b) return false;
  const db = sql ?? (await getSql());
  const rows = await db<{ n: number }>`
    select count(*)::int as n from user_block
    where (blocker_id = ${a} and blocked_id = ${b})
       or (blocker_id = ${b} and blocked_id = ${a})
  `;
  return Number(rows[0]?.n ?? 0) > 0;
}

async function removePairLinksAndGrants(sql: Sql, me: string, other: string) {
  await sql`
    delete from user_links
    where (requester_id = ${me} and addressee_id = ${other})
       or (requester_id = ${other} and addressee_id = ${me})
  `;
  await sql`
    delete from collection_grants
    where (from_id = ${me} and user_id = ${other})
       or (from_id = ${other} and user_id = ${me})
  `;
  await sql`
    delete from note_grants
    where (from_id = ${me} and user_id = ${other})
       or (from_id = ${other} and user_id = ${me})
  `;
}

export async function blockUserForUser(
  userId: string,
  targetUserIdRaw: string,
): Promise<
  | { ok: true }
  | { ok: false; error: "missing" | "self" | "rate" }
> {
  if (!(await allowRequest(`block:${userId}`, 30, 86_400_000))) {
    return { ok: false, error: "rate" };
  }
  const targetUserId = targetUserIdRaw.trim().slice(0, 40);
  if (!targetUserId) return { ok: false, error: "missing" };
  if (targetUserId === userId) return { ok: false, error: "self" };

  const sql = await getSql();
  const exists = await sql<{ user_id: string }>`
    select user_id from user_prefs where user_id = ${targetUserId} limit 1
  `;
  if (!exists[0]) return { ok: false, error: "missing" };

  await sql`
    insert into user_block (blocker_id, blocked_id)
    values (${userId}, ${targetUserId})
    on conflict (blocker_id, blocked_id) do nothing
  `;
  await removePairLinksAndGrants(sql, userId, targetUserId);
  return { ok: true };
}

export async function unblockUserForUser(
  userId: string,
  targetUserIdRaw: string,
): Promise<{ ok: true } | { ok: false; error: "missing" | "rate" }> {
  if (!(await allowRequest(`unblock:${userId}`, 60, 86_400_000))) {
    return { ok: false, error: "rate" };
  }
  const targetUserId = targetUserIdRaw.trim().slice(0, 40);
  if (!targetUserId) return { ok: false, error: "missing" };
  const sql = await getSql();
  const rows = await sql<{ blocked_id: string }>`
    delete from user_block
    where blocker_id = ${userId} and blocked_id = ${targetUserId}
    returning blocked_id
  `;
  if (!rows[0]) return { ok: false, error: "missing" };
  return { ok: true };
}

export async function listBlocksForUser(userId: string): Promise<NativeBlockedPerson[]> {
  const sql = await getSql();
  const rows = await sql<{
    blocked_id: string;
    created_at: string;
    handle: string;
    first_name: string;
    last_name: string;
    avatar_id: string;
    avatar_url: string;
  }>`
    select b.blocked_id, b.created_at::text,
           coalesce(p.handle, '') as handle,
           coalesce(p.first_name, '') as first_name,
           coalesce(p.last_name, '') as last_name,
           coalesce(p.avatar_id, 'book') as avatar_id,
           coalesce(p.avatar_url, '') as avatar_url
    from user_block b
    left join user_prefs p on p.user_id = b.blocked_id
    where b.blocker_id = ${userId}
    order by b.created_at desc
  `;
  return rows.map((row) => ({
    userId: row.blocked_id,
    handle: row.handle ?? "",
    firstName: row.first_name ?? "",
    lastName: row.last_name ?? "",
    avatarId: row.avatar_id || "book",
    avatarUrl: row.avatar_url ?? "",
    blockedAt: String(row.created_at ?? ""),
  }));
}

const REASONS = new Set<ReportReason>(["spam", "offensive", "inappropriate", "other"]);
const TARGETS = new Set<ReportTargetType>(["user", "note", "group"]);

export async function reportContentForUser(
  userId: string,
  input: {
    targetType?: unknown;
    targetId?: unknown;
    reason?: unknown;
    details?: unknown;
  },
): Promise<
  | { ok: true; id: string }
  | { ok: false; error: "invalid" | "rate" | "self" }
> {
  if (!(await allowRequest(`report:${userId}`, 20, 86_400_000))) {
    return { ok: false, error: "rate" };
  }

  const targetType = String(input.targetType ?? "").trim() as ReportTargetType;
  const targetId = String(input.targetId ?? "").trim().slice(0, 80);
  const reason = String(input.reason ?? "").trim() as ReportReason;
  const details = String(input.details ?? "")
    .trim()
    .slice(0, 2000);

  if (!TARGETS.has(targetType) || !targetId || !REASONS.has(reason)) {
    return { ok: false, error: "invalid" };
  }
  if (targetType === "user" && targetId === userId) {
    return { ok: false, error: "self" };
  }

  const id = newId();
  const sql = await getSql();
  await sql`
    insert into content_report (id, reporter_id, target_type, target_id, reason, details, status)
    values (${id}, ${userId}, ${targetType}, ${targetId}, ${reason}, ${details}, ${"open"})
  `;

  void notifyModerationEmail({
    reportId: id,
    reporterId: userId,
    targetType,
    targetId,
    reason,
    details,
  }).catch((error) => {
    console.error("[native/v1/report] email failed", error);
  });

  return { ok: true, id };
}

async function notifyModerationEmail(payload: {
  reportId: string;
  reporterId: string;
  targetType: ReportTargetType;
  targetId: string;
  reason: ReportReason;
  details: string;
}) {
  const from = process.env.EMAIL_FROM?.trim() || "";
  if (!from) {
    console.error("[native/v1/report] EMAIL_FROM missing — report stored without email");
    return;
  }
  const subject = `[Katecheo] Denúncia ${payload.targetType}/${payload.targetId}`;
  const text = [
    `Report id: ${payload.reportId}`,
    `Reporter: ${payload.reporterId}`,
    `Target: ${payload.targetType} ${payload.targetId}`,
    `Reason: ${payload.reason}`,
    `Details: ${payload.details || "(none)"}`,
  ].join("\n");
  const html = `<pre style="font-family:ui-monospace,monospace;font-size:13px">${escapeHtml(text)}</pre>`;
  const sent = await sendResendEmail({
    from,
    to: CONTACT_EMAIL,
    subject,
    html,
    text,
  });
  if (!sent.ok) {
    console.error("[native/v1/report] email not sent", sent.error, sent.detail);
  }
}

function escapeHtml(value: string) {
  return value
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;");
}
