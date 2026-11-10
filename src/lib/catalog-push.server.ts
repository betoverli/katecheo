import { getSql } from "@/lib/db";
import { authorizeCatalogBroadcast, catalogPushSecretConfigured } from "@/lib/catalog-push-auth";

export type CatalogPushKind = "themes_updated" | "reading_updated";

export { authorizeCatalogBroadcast, catalogPushSecretConfigured } from "@/lib/catalog-push-auth";

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

/**
 * Broadcast after a static catalog deploy (all registered devices).
 * Requires `CATALOG_PUSH_SECRET` — refused otherwise (never a public unauthenticated path).
 */
export async function broadcastCatalogHint(
  kind: CatalogPushKind,
  secret: string | null | undefined,
): Promise<{ ok: true; devices?: number } | { ok: false; error: "unauthorized" | "push_failed" }> {
  if (!authorizeCatalogBroadcast(secret)) {
    console.warn("[catalog-push] broadcast refused — missing/invalid CATALOG_PUSH_SECRET");
    return { ok: false, error: "unauthorized" };
  }
  try {
    const sql = await getSql();
    const { broadcastApnsSilent } = await import("@/lib/apns.server");
    await broadcastApnsSilent(sql, { type: kind });
    return { ok: true };
  } catch (error) {
    console.error("[catalog-push] broadcast failed", error);
    return { ok: false, error: "push_failed" };
  }
}
