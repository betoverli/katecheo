/**
 * Verify a Sign in with Apple identity token (native ASAuthorizationAppleID).
 * JWKS: https://appleid.apple.com/auth/keys — iss appleid.apple.com, aud App ID.
 */
import { createHash } from "node:crypto";
import {
  createRemoteJWKSet,
  jwtVerify,
  type JWTPayload,
  type JWTVerifyGetKey,
} from "jose";
import {
  APPLE_BUNDLE_ID,
  APPLE_ISSUER,
  APPLE_JWKS_URL,
} from "./apple.ts";

export type AppleIdentityClaims = {
  sub: string;
  email: string | null;
  emailVerified: boolean;
  isPrivateEmail: boolean;
  nonce: string | null;
};

export type VerifyAppleIdentityOptions = {
  audience?: string | string[];
  /** Raw nonce from the client (before hashing). */
  nonce?: string | null;
  /** Injected JWKS resolver for unit tests. */
  getKey?: JWTVerifyGetKey;
  /** Override clock for expired-token tests (unix seconds). */
  now?: number;
};

const remoteJwks = createRemoteJWKSet(new URL(APPLE_JWKS_URL));

export function sha256Hex(value: string): string {
  return createHash("sha256").update(value, "utf8").digest("hex");
}

export function sha256Base64Url(value: string): string {
  return createHash("sha256")
    .update(value, "utf8")
    .digest("base64")
    .replace(/\+/g, "-")
    .replace(/\//g, "_")
    .replace(/=+$/g, "");
}

/**
 * Apple echoes the request nonce in the ID token. Clients typically send the
 * SHA-256 of a raw nonce (hex or base64url). Accept exact, hex, or base64url.
 */
export function appleNonceMatches(claimNonce: unknown, rawNonce: string): boolean {
  if (typeof claimNonce !== "string" || !claimNonce) return false;
  if (!rawNonce) return false;
  if (claimNonce === rawNonce) return true;
  if (claimNonce === sha256Hex(rawNonce)) return true;
  if (claimNonce === sha256Base64Url(rawNonce)) return true;
  return false;
}

function asBool(value: unknown): boolean {
  return value === true || value === "true";
}

function claimsFromPayload(payload: JWTPayload): AppleIdentityClaims | null {
  const sub = typeof payload.sub === "string" ? payload.sub.trim() : "";
  if (!sub) return null;
  const email = typeof payload.email === "string" ? payload.email.trim() : null;
  return {
    sub,
    email: email || null,
    emailVerified: asBool(payload.email_verified) || Boolean(email),
    isPrivateEmail: asBool(payload.is_private_email),
    nonce: typeof payload.nonce === "string" ? payload.nonce : null,
  };
}

export class AppleTokenVerifyError extends Error {
  readonly code: "invalid" | "wrong_aud" | "wrong_nonce" | "expired" | "bad_iss";

  constructor(code: AppleTokenVerifyError["code"], message: string) {
    super(message);
    this.name = "AppleTokenVerifyError";
    this.code = code;
  }
}

/**
 * Cryptographically verify an Apple identity token.
 * Throws {@link AppleTokenVerifyError} on failure.
 */
export async function verifyAppleIdentityToken(
  identityToken: string,
  options: VerifyAppleIdentityOptions = {},
): Promise<AppleIdentityClaims> {
  const audience = options.audience ?? APPLE_BUNDLE_ID;
  const getKey = options.getKey ?? remoteJwks;
  const rawNonce = options.nonce?.trim() || null;

  let payload: JWTPayload;
  try {
    const verified = await jwtVerify(identityToken, getKey, {
      issuer: APPLE_ISSUER,
      audience,
      algorithms: ["RS256"],
      requiredClaims: ["iss", "sub", "aud", "exp", "iat"],
      clockTolerance: 30,
      ...(typeof options.now === "number"
        ? { currentDate: new Date(options.now * 1000) }
        : {}),
    });
    payload = verified.payload;
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    if (/expir/i.test(message) || /timestamp.*check/i.test(message)) {
      throw new AppleTokenVerifyError("expired", message);
    }
    if (/audience/i.test(message) || /\baud\b/i.test(message)) {
      throw new AppleTokenVerifyError("wrong_aud", message);
    }
    if (/issuer/i.test(message) || /\biss\b/i.test(message)) {
      throw new AppleTokenVerifyError("bad_iss", message);
    }
    throw new AppleTokenVerifyError("invalid", message);
  }

  if (rawNonce) {
    if (!appleNonceMatches(payload.nonce, rawNonce)) {
      throw new AppleTokenVerifyError("wrong_nonce", "ID token nonce does not match");
    }
  }

  const claims = claimsFromPayload(payload);
  if (!claims) {
    throw new AppleTokenVerifyError("invalid", "ID token missing sub");
  }
  return claims;
}
