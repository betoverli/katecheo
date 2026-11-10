/**
 * Apple authorization-code exchange + token revoke for Sign in with Apple.
 * client_secret is a short-lived ES256 JWT signed with the Sign in with Apple key.
 */
import { importPKCS8, SignJWT } from "jose";
import {
  APPLE_REVOKE_URL,
  APPLE_TOKEN_URL,
  appleSignInKeyFromEnv,
  type AppleSignInKeyConfig,
} from "./apple.ts";

type TokenExchangeResult = {
  access_token?: string;
  refresh_token?: string;
  id_token?: string;
  token_type?: string;
  expires_in?: number;
};

let clientSecretCache: { token: string; exp: number; keyId: string } | null = null;

export async function mintAppleClientSecret(
  key: Extract<AppleSignInKeyConfig, { configured: true }>,
  nowSec = Math.floor(Date.now() / 1000),
): Promise<string> {
  if (
    clientSecretCache &&
    clientSecretCache.keyId === key.keyId &&
    clientSecretCache.exp - 60 > nowSec
  ) {
    return clientSecretCache.token;
  }
  const privateKey = await importPKCS8(key.privateKeyPem, "ES256");
  // Apple allows client_secret JWTs up to 6 months; keep ours shorter.
  const exp = nowSec + 60 * 60 * 24 * 30;
  const token = await new SignJWT({})
    .setProtectedHeader({ alg: "ES256", kid: key.keyId })
    .setIssuer(key.teamId)
    .setIssuedAt(nowSec)
    .setExpirationTime(exp)
    .setAudience("https://appleid.apple.com")
    .setSubject(key.clientId)
    .sign(privateKey);
  clientSecretCache = { token, exp, keyId: key.keyId };
  return token;
}

/** Clear cached client_secret (tests). */
export function clearAppleClientSecretCache(): void {
  clientSecretCache = null;
}

export async function exchangeAppleAuthorizationCode(
  authorizationCode: string,
  env: Record<string, string | undefined> = process.env,
): Promise<{ refreshToken: string | null; accessToken: string | null; skipped: boolean }> {
  const key = appleSignInKeyFromEnv(env);
  if (!key.configured) {
    console.warn(
      "[apple] token exchange skipped — set APPLE_CLIENT_ID, APPLE_TEAM_ID, APPLE_SIGNIN_KEY_ID, APPLE_SIGNIN_PRIVATE_KEY",
    );
    return { refreshToken: null, accessToken: null, skipped: true };
  }
  const code = authorizationCode.trim();
  if (!code) return { refreshToken: null, accessToken: null, skipped: false };

  try {
    const clientSecret = await mintAppleClientSecret(key);
    const body = new URLSearchParams({
      client_id: key.clientId,
      client_secret: clientSecret,
      code,
      grant_type: "authorization_code",
    });
    const res = await fetch(APPLE_TOKEN_URL, {
      method: "POST",
      headers: {
        "content-type": "application/x-www-form-urlencoded",
        accept: "application/json",
      },
      body,
    });
    if (!res.ok) {
      const text = await res.text().catch(() => "");
      console.warn("[apple] token exchange failed", res.status, text.slice(0, 200));
      return { refreshToken: null, accessToken: null, skipped: false };
    }
    const json = (await res.json()) as TokenExchangeResult;
    return {
      refreshToken: typeof json.refresh_token === "string" ? json.refresh_token : null,
      accessToken: typeof json.access_token === "string" ? json.access_token : null,
      skipped: false,
    };
  } catch (error) {
    console.warn("[apple] token exchange error", error);
    return { refreshToken: null, accessToken: null, skipped: false };
  }
}

/**
 * Revoke an Apple refresh (or access) token. Returns false when skipped or failed.
 * Never throws — account deletion must continue.
 */
export async function revokeAppleToken(
  token: string,
  env: Record<string, string | undefined> = process.env,
  tokenTypeHint: "refresh_token" | "access_token" = "refresh_token",
): Promise<{ revoked: boolean; skipped: boolean }> {
  const key = appleSignInKeyFromEnv(env);
  if (!key.configured) {
    console.warn("[apple] revoke skipped — Sign in with Apple key env vars missing");
    return { revoked: false, skipped: true };
  }
  const value = token.trim();
  if (!value) return { revoked: false, skipped: true };

  try {
    const clientSecret = await mintAppleClientSecret(key);
    const body = new URLSearchParams({
      client_id: key.clientId,
      client_secret: clientSecret,
      token: value,
      token_type_hint: tokenTypeHint,
    });
    const res = await fetch(APPLE_REVOKE_URL, {
      method: "POST",
      headers: {
        "content-type": "application/x-www-form-urlencoded",
        accept: "application/json",
      },
      body,
    });
    if (!res.ok) {
      const text = await res.text().catch(() => "");
      console.warn("[apple] revoke failed", res.status, text.slice(0, 200));
      return { revoked: false, skipped: false };
    }
    return { revoked: true, skipped: false };
  } catch (error) {
    console.warn("[apple] revoke error", error);
    return { revoked: false, skipped: false };
  }
}
