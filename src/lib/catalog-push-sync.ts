/**
 * DB claim helpers for silent catalog broadcasts (Neon `catalog_push_state`).
 */
import { withTransaction, type Sql } from "./db.ts";
import type { CatalogPushKind, CatalogVersionClaim } from "./catalog-push-decision.ts";

export type { CatalogPushKind, CatalogVersionClaim };
export {
  actionFromClaim,
  decideCatalogSyncAction,
  type CatalogSyncAction,
  type CatalogSyncKindResult,
} from "./catalog-push-decision.ts";

/**
 * Conditionally upsert `catalog_push_state` so concurrent callers broadcast at most once.
 * Runs in a transaction with row lock.
 */
export async function claimCatalogVersion(
  kind: CatalogPushKind,
  currentVersion: string,
): Promise<CatalogVersionClaim> {
  return withTransaction(async (sql) => claimCatalogVersionTx(sql, kind, currentVersion));
}

export async function claimCatalogVersionTx(
  sql: Sql,
  kind: CatalogPushKind,
  currentVersion: string,
): Promise<CatalogVersionClaim> {
  const existing = await sql<{ version: string }>`
    select version from catalog_push_state where kind = ${kind} for update
  `;

  if (existing.length === 0) {
    await sql`
      insert into catalog_push_state (kind, version)
      values (${kind}, ${currentVersion})
    `;
    return { outcome: "inserted", previousVersion: null };
  }

  const previousVersion = String(existing[0].version);
  if (previousVersion === currentVersion) {
    return { outcome: "unchanged", previousVersion };
  }

  await sql`
    update catalog_push_state
    set version = ${currentVersion}, updated_at = now()
    where kind = ${kind}
  `;
  return { outcome: "updated", previousVersion };
}

/** Roll back a claimed version so a failed broadcast can be retried. */
export async function revertCatalogVersionClaim(
  kind: CatalogPushKind,
  claim: CatalogVersionClaim,
  currentVersion: string,
): Promise<void> {
  await withTransaction(async (sql) => {
    if (claim.outcome === "inserted") {
      await sql`
        delete from catalog_push_state
        where kind = ${kind} and version = ${currentVersion}
      `;
      return;
    }
    if (claim.outcome === "updated") {
      await sql`
        update catalog_push_state
        set version = ${claim.previousVersion}, updated_at = now()
        where kind = ${kind} and version = ${currentVersion}
      `;
    }
  });
}
