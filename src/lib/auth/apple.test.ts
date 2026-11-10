import assert from "node:assert/strict";
import { describe, it } from "node:test";
import {
  APPLE_BUNDLE_ID,
  APPLE_CLIENT_ID_ENV,
  APPLE_CLIENT_SECRET_ENV,
  APPLE_PROVIDER_ID,
  APPLE_SIGNIN_KEY_ID_ENV,
  APPLE_SIGNIN_PRIVATE_KEY_ENV,
  APPLE_TEAM_ID_ENV,
  appleNativeFromEnv,
  appleOAuthFromEnv,
  applePlaceholderEmail,
  appleSignInKeyFromEnv,
  isApplePrivateRelayEmail,
} from "./apple.ts";

describe("appleOAuthFromEnv", () => {
  it("is configured only when both client id and secret are non-empty", () => {
    const configured = appleOAuthFromEnv({
      [APPLE_CLIENT_ID_ENV]: " com.verse2note.app ",
      [APPLE_CLIENT_SECRET_ENV]: " apple-secret ",
    });
    assert.deepEqual(configured, {
      configured: true,
      clientId: "com.verse2note.app",
      clientSecret: "apple-secret",
    });
    assert.equal(APPLE_PROVIDER_ID, "apple");
    assert.equal(APPLE_BUNDLE_ID, "com.verse2note.app");
  });

  it("stays off when either value is missing or blank", () => {
    assert.deepEqual(appleOAuthFromEnv({}), { configured: false });
    assert.deepEqual(appleOAuthFromEnv({ [APPLE_CLIENT_ID_ENV]: "id-only" }), {
      configured: false,
    });
    assert.deepEqual(appleOAuthFromEnv({ [APPLE_CLIENT_SECRET_ENV]: "secret-only" }), {
      configured: false,
    });
  });
});

describe("appleNativeFromEnv", () => {
  it("enables native Sign in with Apple with only APPLE_CLIENT_ID", () => {
    assert.deepEqual(appleNativeFromEnv({ [APPLE_CLIENT_ID_ENV]: "com.verse2note.app" }), {
      configured: true,
      clientId: "com.verse2note.app",
      audience: "com.verse2note.app",
    });
    assert.deepEqual(appleNativeFromEnv({}), { configured: false });
  });
});

describe("appleSignInKeyFromEnv", () => {
  it("requires client id, team id, key id and private key for exchange/revoke", () => {
    assert.deepEqual(appleSignInKeyFromEnv({}), { configured: false });
    assert.deepEqual(
      appleSignInKeyFromEnv({
        [APPLE_CLIENT_ID_ENV]: "com.verse2note.app",
        [APPLE_TEAM_ID_ENV]: "TEAM123456",
        [APPLE_SIGNIN_KEY_ID_ENV]: "KEYID12345",
      }),
      { configured: false },
    );
    const pem = "-----BEGIN PRIVATE KEY-----\nABC\n-----END PRIVATE KEY-----";
    const configured = appleSignInKeyFromEnv({
      [APPLE_CLIENT_ID_ENV]: "com.verse2note.app",
      [APPLE_TEAM_ID_ENV]: "TEAM123456",
      [APPLE_SIGNIN_KEY_ID_ENV]: "KEYID12345",
      [APPLE_SIGNIN_PRIVATE_KEY_ENV]: pem,
    });
    assert.equal(configured.configured, true);
    if (configured.configured) {
      assert.equal(configured.teamId, "TEAM123456");
      assert.equal(configured.keyId, "KEYID12345");
      assert.match(configured.privateKeyPem, /BEGIN PRIVATE KEY/);
    }
  });
});

describe("Apple email helpers", () => {
  it("detects private relay and builds placeholders", () => {
    assert.equal(isApplePrivateRelayEmail("a@privaterelay.appleid.com"), true);
    assert.equal(isApplePrivateRelayEmail("person@example.com"), false);
    assert.match(applePlaceholderEmail("sub.1"), /@privaterelay\.appleid\.com$/);
  });
});
