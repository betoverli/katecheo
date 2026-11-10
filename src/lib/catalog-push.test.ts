import assert from "node:assert/strict";
import { describe, it } from "node:test";
import { authorizeCatalogBroadcast, catalogPushSecretConfigured } from "./catalog-push-auth.ts";
import {
  actionFromClaim,
  decideCatalogSyncAction,
  type CatalogVersionClaim,
} from "./catalog-push-decision.ts";

describe("catalog broadcast auth (M7)", () => {
  it("refuses when CATALOG_PUSH_SECRET is unset or too short", () => {
    const prev = process.env.CATALOG_PUSH_SECRET;
    delete process.env.CATALOG_PUSH_SECRET;
    try {
      assert.equal(catalogPushSecretConfigured(), false);
      assert.equal(authorizeCatalogBroadcast("anything-long-enough"), false);
    } finally {
      if (prev === undefined) delete process.env.CATALOG_PUSH_SECRET;
      else process.env.CATALOG_PUSH_SECRET = prev;
    }
  });

  it("accepts only the configured secret", () => {
    const prev = process.env.CATALOG_PUSH_SECRET;
    process.env.CATALOG_PUSH_SECRET = "deploy-secret-16chars";
    try {
      assert.equal(catalogPushSecretConfigured(), true);
      assert.equal(authorizeCatalogBroadcast("deploy-secret-16chars"), true);
      assert.equal(authorizeCatalogBroadcast("wrong-secret-16chars!"), false);
      assert.equal(authorizeCatalogBroadcast(""), false);
      assert.equal(authorizeCatalogBroadcast(null), false);
    } finally {
      if (prev === undefined) delete process.env.CATALOG_PUSH_SECRET;
      else process.env.CATALOG_PUSH_SECRET = prev;
    }
  });
});

describe("catalog push idempotent decisions", () => {
  it("baselines without broadcast on first run", () => {
    assert.equal(
      decideCatalogSyncAction({
        storedVersion: null,
        currentVersion: "themes-aaa",
        force: false,
      }),
      "skipped_baseline",
    );
  });

  it("broadcasts on first run when force is set", () => {
    assert.equal(
      decideCatalogSyncAction({
        storedVersion: null,
        currentVersion: "themes-aaa",
        force: true,
      }),
      "broadcast",
    );
  });

  it("broadcasts only when the version changed", () => {
    assert.equal(
      decideCatalogSyncAction({
        storedVersion: "themes-aaa",
        currentVersion: "themes-bbb",
        force: false,
      }),
      "broadcast",
    );
    assert.equal(
      decideCatalogSyncAction({
        storedVersion: "themes-aaa",
        currentVersion: "themes-aaa",
        force: false,
      }),
      "skipped_unchanged",
    );
  });

  it("force broadcasts even when unchanged", () => {
    assert.equal(
      decideCatalogSyncAction({
        storedVersion: "reading-aaa",
        currentVersion: "reading-aaa",
        force: true,
      }),
      "broadcast",
    );
  });

  it("maps claims to actions the same way (concurrency winners)", () => {
    const inserted: CatalogVersionClaim = { outcome: "inserted", previousVersion: null };
    const updated: CatalogVersionClaim = { outcome: "updated", previousVersion: "old" };
    const unchanged: CatalogVersionClaim = { outcome: "unchanged", previousVersion: "same" };

    assert.equal(actionFromClaim(inserted, false), "skipped_baseline");
    assert.equal(actionFromClaim(inserted, true), "broadcast");
    assert.equal(actionFromClaim(updated, false), "broadcast");
    assert.equal(actionFromClaim(unchanged, false), "skipped_unchanged");
    assert.equal(actionFromClaim(unchanged, true), "broadcast");
  });
});
