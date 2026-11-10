import assert from "node:assert/strict";
import { generateKeyPairSync, type KeyObject } from "node:crypto";
import { describe, it } from "node:test";
import { SignJWT, exportJWK, importJWK, type JWK, type JWTVerifyGetKey } from "jose";
import { APPLE_BUNDLE_ID, APPLE_ISSUER } from "./apple.ts";
import {
  AppleTokenVerifyError,
  appleNonceMatches,
  sha256Base64Url,
  sha256Hex,
  verifyAppleIdentityToken,
} from "./apple-verify.server.ts";

type TestKey = { privateKey: KeyObject; jwk: JWK; kid: string };

async function makeKey(kid: string): Promise<TestKey> {
  const { publicKey, privateKey } = generateKeyPairSync("rsa", { modulusLength: 2048 });
  const jwk = await exportJWK(publicKey);
  return {
    privateKey,
    kid,
    jwk: { ...jwk, alg: "RS256", use: "sig", kid },
  };
}

function staticGetKey(jwk: JWK): JWTVerifyGetKey {
  return async () => importJWK(jwk, "RS256");
}

describe("appleNonceMatches", () => {
  it("accepts exact, sha256 hex, and sha256 base64url", () => {
    const raw = "raw-nonce-value";
    assert.equal(appleNonceMatches(raw, raw), true);
    assert.equal(appleNonceMatches(sha256Hex(raw), raw), true);
    assert.equal(appleNonceMatches(sha256Base64Url(raw), raw), true);
    assert.equal(appleNonceMatches("nope", raw), false);
  });
});

describe("verifyAppleIdentityToken", () => {
  it("accepts a valid Apple identity token", async () => {
    const key = await makeKey("apple-1");
    const rawNonce = "client-raw-nonce";
    const now = Math.floor(Date.now() / 1000);
    const token = await new SignJWT({
      sub: "apple-sub-1",
      email: "user@example.com",
      email_verified: true,
      nonce: sha256Hex(rawNonce),
    })
      .setProtectedHeader({ alg: "RS256", kid: key.kid })
      .setIssuer(APPLE_ISSUER)
      .setAudience(APPLE_BUNDLE_ID)
      .setIssuedAt(now)
      .setExpirationTime(now + 600)
      .sign(key.privateKey);

    const claims = await verifyAppleIdentityToken(token, {
      audience: APPLE_BUNDLE_ID,
      nonce: rawNonce,
      getKey: staticGetKey(key.jwk),
    });
    assert.equal(claims.sub, "apple-sub-1");
    assert.equal(claims.email, "user@example.com");
    assert.equal(claims.emailVerified, true);
  });

  it("rejects wrong audience", async () => {
    const key = await makeKey("apple-2");
    const now = Math.floor(Date.now() / 1000);
    const token = await new SignJWT({ sub: "apple-sub-2" })
      .setProtectedHeader({ alg: "RS256", kid: key.kid })
      .setIssuer(APPLE_ISSUER)
      .setAudience("com.other.app")
      .setIssuedAt(now)
      .setExpirationTime(now + 600)
      .sign(key.privateKey);

    await assert.rejects(
      () =>
        verifyAppleIdentityToken(token, {
          audience: APPLE_BUNDLE_ID,
          getKey: staticGetKey(key.jwk),
        }),
      (error: unknown) =>
        error instanceof AppleTokenVerifyError && error.code === "wrong_aud",
    );
  });

  it("rejects wrong nonce", async () => {
    const key = await makeKey("apple-3");
    const now = Math.floor(Date.now() / 1000);
    const token = await new SignJWT({
      sub: "apple-sub-3",
      nonce: sha256Hex("expected-nonce"),
    })
      .setProtectedHeader({ alg: "RS256", kid: key.kid })
      .setIssuer(APPLE_ISSUER)
      .setAudience(APPLE_BUNDLE_ID)
      .setIssuedAt(now)
      .setExpirationTime(now + 600)
      .sign(key.privateKey);

    await assert.rejects(
      () =>
        verifyAppleIdentityToken(token, {
          audience: APPLE_BUNDLE_ID,
          nonce: "different-nonce",
          getKey: staticGetKey(key.jwk),
        }),
      (error: unknown) =>
        error instanceof AppleTokenVerifyError && error.code === "wrong_nonce",
    );
  });

  it("rejects expired tokens", async () => {
    const key = await makeKey("apple-4");
    const now = Math.floor(Date.now() / 1000);
    const token = await new SignJWT({ sub: "apple-sub-4" })
      .setProtectedHeader({ alg: "RS256", kid: key.kid })
      .setIssuer(APPLE_ISSUER)
      .setAudience(APPLE_BUNDLE_ID)
      .setIssuedAt(now - 3600)
      .setExpirationTime(now - 60)
      .sign(key.privateKey);

    await assert.rejects(
      () =>
        verifyAppleIdentityToken(token, {
          audience: APPLE_BUNDLE_ID,
          getKey: staticGetKey(key.jwk),
          now,
        }),
      (error: unknown) =>
        error instanceof AppleTokenVerifyError && error.code === "expired",
    );
  });
});
