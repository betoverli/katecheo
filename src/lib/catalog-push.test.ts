import assert from "node:assert/strict";
import { describe, it } from "node:test";
import { authorizeCatalogBroadcast, catalogPushSecretConfigured } from "./catalog-push-auth.ts";

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
