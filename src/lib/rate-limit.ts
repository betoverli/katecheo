import { getSql } from "@/lib/db";

/**
 * Shared rate limiter backed by Postgres (`rate_limit_buckets`).
 * Works across Vercel isolates (unlike the previous in-memory Map).
 *
 * Window alignment is floor(now / windowMs) so concurrent upserts share one row.
 * Fail-open on DB errors for non-auth paths would be dangerous for auth — we
 * fail closed (deny) when the store is unavailable so auth cannot be flooded.
 */

function windowStartIso(windowMs: number, now = Date.now()): string {
  const startMs = Math.floor(now / windowMs) * windowMs;
  return new Date(startMs).toISOString();
}

/**
 * @returns true if the request is allowed, false if over the limit.
 */
export async function allowRequest(
  key: string,
  max: number,
  windowMs: number,
): Promise<boolean> {
  const bucketKey = key.slice(0, 200);
  if (!bucketKey || max < 1 || windowMs < 1) return false;
  const windowStart = windowStartIso(windowMs);
  try {
    const sql = await getSql();
    const rows = await sql<{ hit_count: number }>`
      insert into rate_limit_buckets (bucket_key, window_start, hit_count)
      values (${bucketKey}, ${windowStart}::timestamptz, 1)
      on conflict (bucket_key, window_start) do update
        set hit_count = rate_limit_buckets.hit_count + 1
      returning hit_count
    `;
    const count = Number(rows[0]?.hit_count ?? 0);
    return count <= max;
  } catch (error) {
    console.error("[rate-limit] store unavailable — denying request", error);
    return false;
  }
}

export function clientKey(request: Request) {
  const forwarded = request.headers.get("cf-connecting-ip") || request.headers.get("x-forwarded-for");
  return (forwarded?.split(",")[0] ?? "").trim() || request.headers.get("x-real-ip") || "local";
}
