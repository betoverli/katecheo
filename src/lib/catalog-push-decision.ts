/**
 * Pure idempotent decision helpers for silent catalog broadcasts (no DB / APNs).
 */
export type CatalogPushKind = "themes_updated" | "reading_updated";

export type CatalogSyncAction = "broadcast" | "skipped_unchanged" | "skipped_baseline";

export type CatalogSyncKindResult = {
  kind: CatalogPushKind;
  version: string;
  action: CatalogSyncAction;
};

export type CatalogVersionClaim =
  | { outcome: "inserted"; previousVersion: null }
  | { outcome: "updated"; previousVersion: string }
  | { outcome: "unchanged"; previousVersion: string };

/**
 * Decide what to do given the previously stored version (null = no row yet).
 * First sight of a kind baselines without broadcast unless `force`.
 */
export function decideCatalogSyncAction(opts: {
  storedVersion: string | null;
  currentVersion: string;
  force: boolean;
}): CatalogSyncAction {
  const { storedVersion, currentVersion, force } = opts;
  if (storedVersion === null) {
    return force ? "broadcast" : "skipped_baseline";
  }
  if (force) return "broadcast";
  if (storedVersion !== currentVersion) return "broadcast";
  return "skipped_unchanged";
}

/** Map a successful claim onto the public action (+ whether APNs should fire). */
export function actionFromClaim(claim: CatalogVersionClaim, force: boolean): CatalogSyncAction {
  if (claim.outcome === "inserted") {
    return force ? "broadcast" : "skipped_baseline";
  }
  if (claim.outcome === "updated") return "broadcast";
  return force ? "broadcast" : "skipped_unchanged";
}
