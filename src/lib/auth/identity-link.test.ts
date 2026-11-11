import assert from "node:assert/strict";
import { describe, it } from "node:test";
import {
  decideGoogleReassign,
  decideLinkIdentity,
  decideSetPassword,
  decideUnlinkIdentity,
  maskEmail,
  normalizeIdentityProvider,
  providerIdForIdentity,
} from "./identity-link.ts";

describe("maskEmail", () => {
  it("masks local part keeping first character", () => {
    assert.equal(maskEmail("Ana.Silva@Example.com"), "a***@example.com");
    assert.equal(maskEmail("x@y.co"), "x***@y.co");
  });

  it("returns null for empty or invalid values", () => {
    assert.equal(maskEmail(null), null);
    assert.equal(maskEmail(""), null);
    assert.equal(maskEmail("not-an-email"), null);
  });
});

describe("decideLinkIdentity", () => {
  it("links when the identity is free", () => {
    assert.deepEqual(
      decideLinkIdentity({ currentUserId: "u1", ownerUserId: null }),
      { action: "link" },
    );
  });

  it("is idempotent when already on the current user", () => {
    assert.deepEqual(
      decideLinkIdentity({ currentUserId: "u1", ownerUserId: "u1" }),
      { action: "already_linked" },
    );
  });

  it("conflicts when another user owns the identity", () => {
    assert.deepEqual(
      decideLinkIdentity({ currentUserId: "u1", ownerUserId: "u2" }),
      { action: "conflict", code: "identity_in_use" },
    );
  });
});

describe("decideGoogleReassign", () => {
  it("allows reassigning a brand-new empty Google-only shell", () => {
    assert.deepEqual(
      decideGoogleReassign({
        currentUserId: "u1",
        ownerUserId: "u-shell",
        ownerAccountCount: 1,
        ownerHasContent: false,
        ownerCreatedRecently: true,
      }),
      { action: "link" },
    );
  });

  it("refuses to steal an established account", () => {
    assert.deepEqual(
      decideGoogleReassign({
        currentUserId: "u1",
        ownerUserId: "u2",
        ownerAccountCount: 1,
        ownerHasContent: true,
        ownerCreatedRecently: true,
      }),
      { action: "conflict", code: "identity_in_use" },
    );
    assert.deepEqual(
      decideGoogleReassign({
        currentUserId: "u1",
        ownerUserId: "u2",
        ownerAccountCount: 2,
        ownerHasContent: false,
        ownerCreatedRecently: true,
      }),
      { action: "conflict", code: "identity_in_use" },
    );
    assert.deepEqual(
      decideGoogleReassign({
        currentUserId: "u1",
        ownerUserId: "u2",
        ownerAccountCount: 1,
        ownerHasContent: false,
        ownerCreatedRecently: false,
      }),
      { action: "conflict", code: "identity_in_use" },
    );
  });
});

describe("decideUnlinkIdentity", () => {
  it("blocks unlinking the last remaining method", () => {
    assert.deepEqual(
      decideUnlinkIdentity({ providerLinked: true, linkedMethodCount: 1 }),
      { action: "refuse", code: "last_method" },
    );
  });

  it("allows unlink when another method remains", () => {
    assert.deepEqual(
      decideUnlinkIdentity({ providerLinked: true, linkedMethodCount: 2 }),
      { action: "unlink" },
    );
  });

  it("refuses when the method is not linked", () => {
    assert.deepEqual(
      decideUnlinkIdentity({ providerLinked: false, linkedMethodCount: 2 }),
      { action: "refuse", code: "not_linked" },
    );
  });
});

describe("decideSetPassword", () => {
  it("creates when no credential exists", () => {
    assert.deepEqual(decideSetPassword({ hasCredential: false }), { action: "create" });
  });

  it("requires current password to change an existing credential", () => {
    assert.deepEqual(decideSetPassword({ hasCredential: true }), {
      action: "change",
      requireCurrent: true,
    });
  });
});

describe("provider helpers", () => {
  it("maps password ↔ credential", () => {
    assert.equal(providerIdForIdentity("password"), "credential");
    assert.equal(providerIdForIdentity("apple"), "apple");
    assert.equal(normalizeIdentityProvider("credential"), "password");
    assert.equal(normalizeIdentityProvider("password"), "password");
    assert.equal(normalizeIdentityProvider("apple"), "apple");
    assert.equal(normalizeIdentityProvider("nope"), null);
  });
});
