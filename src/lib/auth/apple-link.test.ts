import assert from "node:assert/strict";
import { describe, it } from "node:test";
import { decideAppleUserLink } from "./apple-link.ts";

const claims = {
  sub: "apple.sub.1",
  email: "person@example.com",
  emailVerified: true,
  isPrivateEmail: false,
};

describe("decideAppleUserLink", () => {
  it("uses the user found by apple_sub", () => {
    const decision = decideAppleUserLink({
      byAppleSub: {
        id: "u-sub",
        email: "person@example.com",
        emailVerified: true,
        appleSub: "apple.sub.1",
      },
      byAppleAccount: null,
      byEmail: null,
      claims,
    });
    assert.deepEqual(decision, {
      action: "use_existing",
      userId: "u-sub",
      reason: "apple_sub",
    });
  });

  it("falls back to the Better Auth apple account row", () => {
    const decision = decideAppleUserLink({
      byAppleSub: null,
      byAppleAccount: {
        id: "u-acc",
        email: "person@example.com",
        emailVerified: true,
        appleSub: null,
      },
      byEmail: null,
      claims,
    });
    assert.deepEqual(decision, {
      action: "use_existing",
      userId: "u-acc",
      reason: "account",
    });
  });

  it("links a verified email when no apple_sub exists yet", () => {
    const decision = decideAppleUserLink({
      byAppleSub: null,
      byAppleAccount: null,
      byEmail: {
        id: "u-email",
        email: "person@example.com",
        emailVerified: true,
        appleSub: null,
      },
      claims,
    });
    assert.deepEqual(decision, { action: "link_email", userId: "u-email" });
  });

  it("links a private-relay email even when local emailVerified is false", () => {
    const decision = decideAppleUserLink({
      byAppleSub: null,
      byAppleAccount: null,
      byEmail: {
        id: "u-relay",
        email: "hidden@privaterelay.appleid.com",
        emailVerified: false,
        appleSub: null,
      },
      claims: {
        sub: "apple.sub.2",
        email: "hidden@privaterelay.appleid.com",
        emailVerified: true,
        isPrivateEmail: true,
      },
    });
    assert.deepEqual(decision, { action: "link_email", userId: "u-relay" });
  });

  it("creates a user when email is missing (return visit / Hide My Email)", () => {
    const decision = decideAppleUserLink({
      byAppleSub: null,
      byAppleAccount: null,
      byEmail: null,
      claims: {
        sub: "apple.sub.3",
        email: null,
        emailVerified: false,
        isPrivateEmail: false,
      },
    });
    assert.deepEqual(decision, { action: "create" });
  });

  it("creates instead of linking an unverified conflicting email", () => {
    const decision = decideAppleUserLink({
      byAppleSub: null,
      byAppleAccount: null,
      byEmail: {
        id: "u-unverified",
        email: "person@example.com",
        emailVerified: false,
        appleSub: null,
      },
      claims: {
        sub: "apple.sub.4",
        email: "person@example.com",
        emailVerified: false,
        isPrivateEmail: false,
      },
    });
    assert.deepEqual(decision, { action: "create" });
  });

  it("does not link when another Apple sub already owns the email user", () => {
    const decision = decideAppleUserLink({
      byAppleSub: null,
      byAppleAccount: null,
      byEmail: {
        id: "u-taken",
        email: "person@example.com",
        emailVerified: true,
        appleSub: "other.apple.sub",
      },
      claims,
    });
    assert.deepEqual(decision, { action: "create" });
  });
});
