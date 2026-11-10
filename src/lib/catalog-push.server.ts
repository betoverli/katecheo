import { getSql } from "@/lib/db";
import { authorizeCatalogBroadcast } from "@/lib/catalog-push-auth";
import {
  actionFromClaim,
  type CatalogPushKind,
  type CatalogSyncAction,
  type CatalogSyncKindResult,
} from "@/lib/catalog-push-decision";
import { claimCatalogVersion, revertCatalogVersionClaim } from "@/lib/catalog-push-sync";
import { readingCatalogVersion, themesCatalogVersion } from "@/lib/bible/catalog-version";

export type { CatalogPushKind, CatalogSyncAction, CatalogSyncKindResult };
export { authorizeCatalogBroadcast, catalogPushSecretConfigured } from "@/lib/catalog-push-auth";

const KIND_VERSION: Record<CatalogPushKind, () => string> = {
  themes_updated: () => themesCatalogVersion(),
  reading_updated: () => readingCatalogVersion(),
};

export const ALL_CATALOG_PUSH_KINDS: CatalogPushKind[] = ["themes_updated", "reading_updated"];

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

export type SyncCatalogPushResult =
  | {
      ok: true;
      force: boolean;
      results: CatalogSyncKindResult[];
      broadcast: CatalogPushKind[];
      skipped: CatalogPushKind[];
    }
  | {
      ok: false;
      error: "unauthorized" | "push_failed";
      force: boolean;
      results: CatalogSyncKindResult[];
      failedKind?: CatalogPushKind;
    };

/**
 * Idempotent catalog sync: compare content hashes to Neon `catalog_push_state`,
 * broadcast only kinds whose version changed (or all when `force`).
 * First row for a kind baselines without APNs unless `force`.
 */
export async function syncCatalogPush(opts: {
  secret: string | null | undefined;
  force?: boolean;
  kinds?: CatalogPushKind[];
}): Promise<SyncCatalogPushResult> {
  const force = Boolean(opts.force);
  const kinds = opts.kinds?.length ? opts.kinds : ALL_CATALOG_PUSH_KINDS;

  if (!authorizeCatalogBroadcast(opts.secret)) {
    return {
      ok: false,
      error: "unauthorized",
      force,
      results: [],
    };
  }

  const results: CatalogSyncKindResult[] = [];
  const broadcast: CatalogPushKind[] = [];
  const skipped: CatalogPushKind[] = [];

  for (const kind of kinds) {
    const version = KIND_VERSION[kind]();
    const claim = await claimCatalogVersion(kind, version);
    const action = actionFromClaim(claim, force);

    if (action !== "broadcast") {
      results.push({ kind, version, action });
      skipped.push(kind);
      continue;
    }

    const pushed = await broadcastCatalogHint(kind, opts.secret);
    if (!pushed.ok) {
      try {
        await revertCatalogVersionClaim(kind, claim, version);
      } catch (error) {
        console.error("[catalog-push] failed to revert version claim", kind, error);
      }
      results.push({ kind, version, action: "broadcast" });
      return {
        ok: false,
        error: pushed.error,
        force,
        results,
        failedKind: kind,
      };
    }

    results.push({ kind, version, action });
    broadcast.push(kind);
  }

  return { ok: true, force, results, broadcast, skipped };
}
