import { getSql } from "@/lib/db";
import { allowRequest } from "@/lib/rate-limit";
import { cleanApnsToken, cleanDeviceId } from "@/lib/native/apns-devices-logic";

export { cleanApnsToken, cleanDeviceId, applyApnsDeviceRegister } from "@/lib/native/apns-devices-logic";
export type { ApnsDeviceMemRow } from "@/lib/native/apns-devices-logic";

/**
 * Register / refresh an APNs device for `userId`.
 *
 * Identity is `(userId, deviceId)` — a new token for the same device replaces
 * the previous token. If the token already exists on another row, that row is
 * removed so delivery stays single-homed.
 *
 * Reassignment policy (token owned by a different user):
 * - Allowed only if the previous binding is at least 60s old.
 * Rate limits: 20 registrations / user / day and 10 / token / hour.
 */
export async function saveApnsDevice(
  userId: string,
  token: string,
  sandbox: boolean,
  deviceId: string,
) {
  const clean = cleanApnsToken(token);
  const id = cleanDeviceId(deviceId);
  if (!clean || !id) return { ok: false as const, error: "invalid" as const };
  if (!(await allowRequest(`apns-reg:${userId}`, 20, 86_400_000))) {
    return { ok: false as const, error: "rate" as const };
  }
  if (!(await allowRequest(`apns-token:${clean}`, 10, 3_600_000))) {
    return { ok: false as const, error: "rate" as const };
  }
  const sql = await getSql();
  const existing = await sql<{ user_id: string; device_id: string; updated_at: string }>`
    select user_id, device_id, updated_at::text from apns_devices where token = ${clean} limit 1
  `;
  const row = existing[0];
  if (row && row.user_id !== userId) {
    const updatedMs = Date.parse(row.updated_at);
    if (Number.isFinite(updatedMs) && Date.now() - updatedMs < 60_000) {
      return { ok: false as const, error: "conflict" as const };
    }
  }
  // Dedupe: free the token from any other row before upserting this device.
  await sql`
    delete from apns_devices
    where token = ${clean}
      and not (user_id = ${userId} and device_id = ${id})
  `;
  await sql`
    insert into apns_devices (token, user_id, device_id, sandbox)
    values (${clean}, ${userId}, ${id}, ${sandbox})
    on conflict (user_id, device_id) do update
      set token = excluded.token, sandbox = excluded.sandbox, updated_at = now()
  `;
  return { ok: true as const };
}

/**
 * Unregister a device. Prefer `deviceId` when present; otherwise match `token`.
 * Wipe-all requires `all: true` explicitly — empty token alone must not delete
 * every device for the account.
 */
export async function dropApnsDevice(
  userId: string,
  token: string,
  opts?: { all?: boolean; deviceId?: string },
) {
  const sql = await getSql();
  if (opts?.all === true) {
    await sql`delete from apns_devices where user_id = ${userId}`;
    return { ok: true as const };
  }
  const id = opts?.deviceId ? cleanDeviceId(opts.deviceId) : null;
  if (id) {
    await sql`delete from apns_devices where user_id = ${userId} and device_id = ${id}`;
    return { ok: true as const };
  }
  const clean = cleanApnsToken(token);
  if (!clean) return { ok: false as const, error: "invalid" as const };
  await sql`delete from apns_devices where user_id = ${userId} and token = ${clean}`;
  return { ok: true as const };
}

/** Distinct registered devices for this user (one row per device id). */
export async function countApnsDevices(userId: string): Promise<number> {
  const sql = await getSql();
  const rows = await sql<{ n: number }>`
    select count(*)::int as n from apns_devices where user_id = ${userId}
  `;
  return Number(rows[0]?.n ?? 0);
}
