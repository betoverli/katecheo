import { getSql } from "@/lib/db";
import { allowRequest } from "@/lib/rate-limit";

function cleanToken(token: string): string | null {
  const value = token.trim();
  if (!/^[0-9a-fA-F]{64,200}$/.test(value)) return null;
  return value.toLowerCase();
}

/**
 * Register / refresh an APNs device token for `userId`.
 *
 * Reassignment policy:
 * - Same user: always refresh sandbox + updated_at.
 * - Different user: allow (device can switch accounts) but only if the previous
 *   binding is at least 60s old — blocks rapid flip-flop token theft loops.
 * Rate limits: 20 registrations / user / day and 10 / token / hour.
 */
export async function saveApnsDevice(userId: string, token: string, sandbox: boolean) {
  const clean = cleanToken(token);
  if (!clean) return { ok: false as const, error: "invalid" as const };
  if (!(await allowRequest(`apns-reg:${userId}`, 20, 86_400_000))) {
    return { ok: false as const, error: "rate" as const };
  }
  if (!(await allowRequest(`apns-token:${clean}`, 10, 3_600_000))) {
    return { ok: false as const, error: "rate" as const };
  }
  const sql = await getSql();
  const existing = await sql<{ user_id: string; updated_at: string }>`
    select user_id, updated_at::text from apns_devices where token = ${clean} limit 1
  `;
  const row = existing[0];
  if (row && row.user_id !== userId) {
    const updatedMs = Date.parse(row.updated_at);
    if (Number.isFinite(updatedMs) && Date.now() - updatedMs < 60_000) {
      return { ok: false as const, error: "conflict" as const };
    }
  }
  await sql`
    insert into apns_devices (token, user_id, sandbox)
    values (${clean}, ${userId}, ${sandbox})
    on conflict (token) do update
      set user_id = excluded.user_id, sandbox = excluded.sandbox, updated_at = now()
  `;
  return { ok: true as const };
}

/**
 * Unregister a device. Wipe-all requires `all: true` explicitly — empty token alone
 * must not delete every device for the account.
 */
export async function dropApnsDevice(
  userId: string,
  token: string,
  opts?: { all?: boolean },
) {
  const sql = await getSql();
  if (opts?.all === true) {
    await sql`delete from apns_devices where user_id = ${userId}`;
    return { ok: true as const };
  }
  const clean = cleanToken(token);
  if (!clean) return { ok: false as const, error: "invalid" as const };
  await sql`delete from apns_devices where user_id = ${userId} and token = ${clean}`;
  return { ok: true as const };
}

export async function countApnsDevices(userId: string): Promise<number> {
  const sql = await getSql();
  const rows = await sql<{ n: number }>`
    select count(*)::int as n from apns_devices where user_id = ${userId}
  `;
  return Number(rows[0]?.n ?? 0);
}
