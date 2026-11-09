import { getSql } from "@/lib/db";

export type CatalogPushKind = "themes_updated" | "reading_updated";

/** Silent APNs hint so iOS invalidates Themes/Reading caches without a banner. */
export async function pushCatalogHintToUser(userId: string, kind: CatalogPushKind): Promise<void> {
  try {
    const sql = await getSql();
    const { sendApnsSilentToUser } = await import("@/lib/apns.server");
    await sendApnsSilentToUser(sql, userId, { type: kind });
  } catch {
    /* push is best-effort */
  }
}

/** Broadcast after a static catalog deploy / admin write (all registered devices). */
export async function broadcastCatalogHint(kind: CatalogPushKind): Promise<void> {
  try {
    const sql = await getSql();
    const { broadcastApnsSilent } = await import("@/lib/apns.server");
    await broadcastApnsSilent(sql, { type: kind });
  } catch {
    /* push is best-effort */
  }
}
