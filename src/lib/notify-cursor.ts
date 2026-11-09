/**
 * Opaque inbox pagination cursor: `${createdAt}\t${id}` (created_at desc, id desc).
 * Pure helpers — safe to unit-test without loading web-push / DB.
 */

export function encodeInboxCursor(createdAt: string, id: string): string {
  return Buffer.from(`${createdAt}\t${id}`, "utf8").toString("base64url");
}

export function decodeInboxCursor(raw: string | null | undefined): { createdAt: string; id: string } | null {
  if (!raw || typeof raw !== "string") return null;
  try {
    const text = Buffer.from(raw, "base64url").toString("utf8");
    const tab = text.indexOf("\t");
    if (tab <= 0) return null;
    const createdAt = text.slice(0, tab);
    const id = text.slice(tab + 1);
    if (!createdAt || !id) return null;
    return { createdAt, id };
  } catch {
    return null;
  }
}
