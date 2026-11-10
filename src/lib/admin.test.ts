import assert from "node:assert/strict";
import { describe, it } from "node:test";
import { adminHandles, isOwnerHandle } from "./admin.ts";

describe("admin handles (M10)", () => {
  it("uses ADMIN_HANDLES from env when set", () => {
    const prev = process.env.ADMIN_HANDLES;
    process.env.ADMIN_HANDLES = "betoverli,other";
    try {
      assert.deepEqual(adminHandles().sort(), ["betoverli", "other"]);
      assert.equal(isOwnerHandle("BetOverli"), true);
      assert.equal(isOwnerHandle("@other"), true);
      assert.equal(isOwnerHandle("nobody"), false);
    } finally {
      if (prev === undefined) delete process.env.ADMIN_HANDLES;
      else process.env.ADMIN_HANDLES = prev;
    }
  });

  it("has no hardcoded production default when ADMIN_HANDLES is empty in production", () => {
    const prevHandles = process.env.ADMIN_HANDLES;
    const prevVercel = process.env.VERCEL_ENV;
    const prevNode = process.env.NODE_ENV;
    delete process.env.ADMIN_HANDLES;
    process.env.VERCEL_ENV = "production";
    process.env.NODE_ENV = "production";
    try {
      assert.deepEqual(adminHandles(), []);
      assert.equal(isOwnerHandle("betoverli"), false);
    } finally {
      if (prevHandles === undefined) delete process.env.ADMIN_HANDLES;
      else process.env.ADMIN_HANDLES = prevHandles;
      if (prevVercel === undefined) delete process.env.VERCEL_ENV;
      else process.env.VERCEL_ENV = prevVercel;
      if (prevNode === undefined) delete process.env.NODE_ENV;
      else process.env.NODE_ENV = prevNode;
    }
  });
});
