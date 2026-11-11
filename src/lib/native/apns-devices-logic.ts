/** APNs device token: 64–200 hex chars, stored lowercase. */
export function cleanApnsToken(token: string): string | null {
  const value = token.trim();
  if (!/^[0-9a-fA-F]{64,200}$/.test(value)) return null;
  return value.toLowerCase();
}

/**
 * Stable installation/device id from the client (identifierForVendor / Keychain UUID).
 * Allows legacy backfill ids (`legacy:<token>`).
 */
export function cleanDeviceId(deviceId: string): string | null {
  const value = deviceId.trim();
  if (!/^[A-Za-z0-9:_-]{8,128}$/.test(value)) return null;
  return value;
}

/**
 * Whether an APNs HTTP response means the token must be deleted.
 * Prune on 410 (Unregistered) and 400 BadDeviceToken (and close cousins).
 */
export function shouldPruneApnsDevice(status: number, body: string): boolean {
  if (status === 410) return true;
  if (status !== 400) return false;
  return /BadDeviceToken|Unregistered|DeviceTokenNotForTopic/.test(body);
}

export type ApnsDeviceMemRow = {
  token: string;
  userId: string;
  deviceId: string;
  sandbox: boolean;
  updatedAt: number;
};

/**
 * Pure upsert/dedupe rules (mirrors `saveApnsDevice` SQL).
 * - One row per (userId, deviceId)
 * - New token for the same device replaces the old token
 * - Same token on another row is removed (deduped)
 * - Reassignment to another user blocked if previous binding is &lt; 60s old
 */
export function applyApnsDeviceRegister(
  rows: ApnsDeviceMemRow[],
  input: {
    userId: string;
    token: string;
    deviceId: string;
    sandbox: boolean;
    now?: number;
  },
):
  | { ok: true; rows: ApnsDeviceMemRow[] }
  | { ok: false; error: "invalid" | "conflict" } {
  const token = cleanApnsToken(input.token);
  const deviceId = cleanDeviceId(input.deviceId);
  if (!token || !deviceId) return { ok: false, error: "invalid" };
  const now = input.now ?? Date.now();

  const byToken = rows.find((r) => r.token === token);
  if (byToken && byToken.userId !== input.userId) {
    if (now - byToken.updatedAt < 60_000) {
      return { ok: false, error: "conflict" };
    }
  }

  const next = rows.filter(
    (r) =>
      !(r.token === token && !(r.userId === input.userId && r.deviceId === deviceId)) &&
      !(r.userId === input.userId && r.deviceId === deviceId),
  );
  next.push({
    token,
    userId: input.userId,
    deviceId,
    sandbox: input.sandbox,
    updatedAt: now,
  });
  return { ok: true, rows: next };
}
