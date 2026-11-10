import { createCipheriv, createDecipheriv, createHash, randomBytes } from "node:crypto";

export type HandoffKeyResult =
  | { ok: true; key: Buffer; source: "dedicated" | "auth" }
  | { ok: false; reason: "missing" | "invalid-dedicated" };

/**
 * AES-256 key for the short-lived login handoff.
 * A dedicated key wins. Otherwise the existing auth secret is stretched into
 * a key. If neither is set, or the dedicated key is not 32 bytes, nothing is
 * stored — a readable session token never goes into the database.
 */
export function resolveHandoffKey(env: {
  handoff?: string | null;
  auth?: string | null;
}): HandoffKeyResult {
  const dedicated = env.handoff?.trim() ?? "";
  if (dedicated) {
    const key = decodeKey(dedicated);
    if (!key) return { ok: false, reason: "invalid-dedicated" };
    return { ok: true, key, source: "dedicated" };
  }
  const auth = env.auth?.trim() ?? "";
  if (!auth) return { ok: false, reason: "missing" };
  const key = createHash("sha256").update(`katecheo.native-handoff.v1\0${auth}`).digest();
  return { ok: true, key, source: "auth" };
}

export function currentHandoffKey(): HandoffKeyResult {
  return resolveHandoffKey({
    handoff: process.env.NATIVE_AUTH_HANDOFF_KEY,
    auth: process.env.BETTER_AUTH_SECRET,
  });
}

function decodeKey(raw: string): Buffer | null {
  if (/^[0-9a-fA-F]{64}$/.test(raw)) return Buffer.from(raw, "hex");
  const b64 = raw.replace(/-/g, "+").replace(/_/g, "/");
  const padded = b64.length % 4 === 0 ? b64 : b64 + "=".repeat(4 - (b64.length % 4));
  const buf = Buffer.from(padded, "base64");
  if (buf.length === 32 && buf.toString("base64").replace(/=+$/g, "") === padded.replace(/=+$/g, "")) {
    return buf;
  }
  return null;
}

/** Encrypt a session token. The result does not contain the token text. */
export function sealSessionToken(token: string, key: Buffer): string {
  const iv = randomBytes(12);
  const cipher = createCipheriv("aes-256-gcm", key, iv);
  const encrypted = Buffer.concat([cipher.update(token, "utf8"), cipher.final()]);
  const tag = cipher.getAuthTag();
  return `v1.${Buffer.concat([iv, tag, encrypted]).toString("base64url")}`;
}

export function openSessionToken(payload: string, key: Buffer): string | null {
  if (!payload.startsWith("v1.")) return null;
  const raw = Buffer.from(payload.slice(3), "base64url");
  if (raw.length < 12 + 16 + 1) return null;
  const iv = raw.subarray(0, 12);
  const tag = raw.subarray(12, 28);
  const encrypted = raw.subarray(28);
  try {
    const decipher = createDecipheriv("aes-256-gcm", key, iv);
    decipher.setAuthTag(tag);
    return Buffer.concat([decipher.update(encrypted), decipher.final()]).toString("utf8");
  } catch {
    return null;
  }
}
