import { createHash, timingSafeEqual } from "node:crypto";

/** Deploy / internal secret for mass silent APNs. Never expose via a public route. */
export function catalogPushSecretConfigured(): boolean {
  const secret = process.env.CATALOG_PUSH_SECRET?.trim() ?? "";
  return secret.length >= 16;
}

function digest(value: string): Buffer {
  return createHash("sha256").update(value).digest();
}

/**
 * Authorize catalog/silent broadcast. Expects the raw secret (header or arg).
 * Constant-time compare against `CATALOG_PUSH_SECRET`.
 */
export function authorizeCatalogBroadcast(provided: string | null | undefined): boolean {
  const expected = process.env.CATALOG_PUSH_SECRET?.trim() ?? "";
  if (expected.length < 16) return false;
  const got = typeof provided === "string" ? provided.trim() : "";
  if (!got) return false;
  try {
    const a = digest(expected);
    const b = digest(got);
    return a.length === b.length && timingSafeEqual(a, b);
  } catch {
    return false;
  }
}
