/**
 * Sign in with Apple for the native iOS app (`com.verse2note.app`).
 *
 * Native flow: ASAuthorizationAppleID → POST `/api/native/v1/auth/apple` with
 * identityToken (+ authorizationCode, raw nonce, name on first sign-in).
 * The server verifies the JWT against Apple's JWKS; token exchange / revoke
 * use a client_secret JWT minted from the Sign in with Apple key when env
 * vars are present. Sign-in still works when those are missing (verify only).
 *
 * Better Auth's built-in Apple social provider (web) still needs a ready
 * `APPLE_CLIENT_SECRET` JWT in addition to `APPLE_CLIENT_ID`.
 */

export const APPLE_PROVIDER_ID = "apple" as const;

/** App ID / Services ID — also the JWT `aud` for native identity tokens. */
export const APPLE_CLIENT_ID_ENV = "APPLE_CLIENT_ID";
/** Pre-made Apple client_secret JWT (Better Auth web Apple). Optional for native. */
export const APPLE_CLIENT_SECRET_ENV = "APPLE_CLIENT_SECRET";
/** Team ID (10 chars) — used to mint client_secret + AASA. */
export const APPLE_TEAM_ID_ENV = "APPLE_TEAM_ID";
/** Sign in with Apple key id (not the APNs key). */
export const APPLE_SIGNIN_KEY_ID_ENV = "APPLE_SIGNIN_KEY_ID";
/** PEM (or base64 PEM) of the Sign in with Apple `.p8` private key. */
export const APPLE_SIGNIN_PRIVATE_KEY_ENV = "APPLE_SIGNIN_PRIVATE_KEY";

export const APPLE_BUNDLE_ID = "com.verse2note.app";
export const APPLE_ISSUER = "https://appleid.apple.com";
export const APPLE_JWKS_URL = "https://appleid.apple.com/auth/keys";
export const APPLE_TOKEN_URL = "https://appleid.apple.com/auth/token";
export const APPLE_REVOKE_URL = "https://appleid.apple.com/auth/revoke";
export const APPLE_PRIVATE_RELAY_SUFFIX = "@privaterelay.appleid.com";

export type AppleOAuthConfig =
  | { configured: false }
  | { configured: true; clientId: string; clientSecret: string };

/** Native Sign in with Apple — on when `APPLE_CLIENT_ID` is set (token verify). */
export type AppleNativeConfig =
  | { configured: false }
  | { configured: true; clientId: string; audience: string };

/** Key material to mint client_secret + exchange/revoke authorization codes. */
export type AppleSignInKeyConfig =
  | { configured: false }
  | {
      configured: true;
      clientId: string;
      teamId: string;
      keyId: string;
      privateKeyPem: string;
    };

function trim(env: Record<string, string | undefined>, key: string): string {
  return env[key]?.trim() ?? "";
}

function normalizePrivateKeyPem(raw: string): string {
  const value = raw.trim();
  if (!value) return "";
  const pem = value.includes("BEGIN")
    ? value
    : Buffer.from(value, "base64").toString("utf8");
  return pem.replace(/\\n/g, "\n").trim();
}

/** Better Auth web Apple — both client id and a ready client_secret JWT. */
export function appleOAuthFromEnv(
  env: Record<string, string | undefined>,
): AppleOAuthConfig {
  const clientId = trim(env, APPLE_CLIENT_ID_ENV);
  const clientSecret = trim(env, APPLE_CLIENT_SECRET_ENV);
  if (!clientId || !clientSecret) return { configured: false };
  return { configured: true, clientId, clientSecret };
}

/**
 * Native iOS Sign in with Apple. Audience defaults to the client id (App ID
 * `com.verse2note.app`). Does not require the signing key / client_secret.
 */
export function appleNativeFromEnv(
  env: Record<string, string | undefined>,
): AppleNativeConfig {
  const clientId = trim(env, APPLE_CLIENT_ID_ENV);
  if (!clientId) return { configured: false };
  return { configured: true, clientId, audience: clientId };
}

/** True when we can mint client_secret and call Apple token/revoke endpoints. */
export function appleSignInKeyFromEnv(
  env: Record<string, string | undefined>,
): AppleSignInKeyConfig {
  const clientId = trim(env, APPLE_CLIENT_ID_ENV);
  const teamId = trim(env, APPLE_TEAM_ID_ENV);
  const keyId = trim(env, APPLE_SIGNIN_KEY_ID_ENV);
  const privateKeyPem = normalizePrivateKeyPem(trim(env, APPLE_SIGNIN_PRIVATE_KEY_ENV));
  if (!clientId || !teamId || !keyId || !privateKeyPem) return { configured: false };
  return { configured: true, clientId, teamId, keyId, privateKeyPem };
}

export function isApplePrivateRelayEmail(email: string | null | undefined): boolean {
  if (!email) return false;
  return email.trim().toLowerCase().endsWith(APPLE_PRIVATE_RELAY_SUFFIX);
}

/** Placeholder unique email when Apple omits email (return visits / Hide My Email edge). */
export function applePlaceholderEmail(sub: string): string {
  const safe = sub.replace(/[^a-zA-Z0-9._-]/g, "").slice(0, 64) || "unknown";
  return `apple.${safe}${APPLE_PRIVATE_RELAY_SUFFIX}`;
}
