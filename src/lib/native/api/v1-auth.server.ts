/**
 * Native auth endpoints for `/api/native/v1/auth/*`.
 * Returns Better Auth session tokens as bearers for Keychain storage.
 */
import { appleOAuthFromEnv, APPLE_PROVIDER_ID } from "@/lib/auth/apple";
import { emailAndPasswordEnabled } from "@/lib/auth/email-password";
import { GOOGLE_PROVIDER_ID, googleOAuthFromEnv } from "@/lib/auth/google";
import { auth, authConfigured, SESSION_TOKEN_COOKIE } from "@/lib/auth/server";
import { allowRequest, clientKey } from "@/lib/rate-limit";
import { claimHandoff } from "@/lib/native/handoff.server";
import { NATIVE_SESSION_COOKIE, sessionTokenFromCookie } from "@/lib/native/session-cookie";
import { isAllowedPublicHost, trustedWebOrigins } from "@/lib/site";

function tokenFromSetCookie(headers: Headers): string | null {
  const bags = typeof headers.getSetCookie === "function" ? headers.getSetCookie() : [];
  if (bags.length) {
    for (const line of bags) {
      const token = sessionTokenFromCookie(line.split(";")[0] ?? line);
      if (token) return token;
    }
  }
  const single = headers.get("set-cookie");
  if (!single) return null;
  // Fallback when getSetCookie is unavailable: scan for the cookie name.
  const match = single.match(new RegExp(`${NATIVE_SESSION_COOKIE}=([^;]+)`));
  if (!match?.[1]) return null;
  try {
    return decodeURIComponent(match[1]);
  } catch {
    return match[1];
  }
}

export function listNativeAuthProviders() {
  const google = googleOAuthFromEnv(process.env);
  const apple = appleOAuthFromEnv(process.env);
  return {
    ok: true as const,
    authConfigured,
    google: google.configured,
    apple: apple.configured,
    email: emailAndPasswordEnabled && authConfigured,
    googleProviderId: GOOGLE_PROVIDER_ID,
    appleProviderId: APPLE_PROVIDER_ID,
    sessionCookie: SESSION_TOKEN_COOKIE,
  };
}

/** PKCE claim after Google ASWebAuthenticationSession (no WebView CSRF). */
export async function claimNativeBearer(
  request: Request,
  body: { code?: unknown; verifier?: unknown },
): Promise<{ ok: true; token: string } | { ok: false; error: string; status: number }> {
  const ip = clientKey(request);
  if (!(await allowRequest(`native-v1-claim:${ip}`, 30, 60_000))) {
    return { ok: false, error: "rate_limited", status: 429 };
  }
  const code = typeof body.code === "string" ? body.code : "";
  const verifier = typeof body.verifier === "string" ? body.verifier : "";
  // Bypass createServerFn same-site guard: PKCE is the auth factor.
  const claimed = await claimHandoffForApi(code, verifier, ip);
  if (!claimed.ok || !claimed.token) return { ok: false, error: "invalid_code", status: 401 };
  return { ok: true, token: claimed.token };
}

async function claimHandoffForApi(
  code: string,
  verifier: string,
  ip: string,
): Promise<{ ok: true; token: string } | { ok: false }> {
  // Reuse the same DB + PKCE logic as claimHandoff, but without assertSameSiteRequest.
  // Inline import of internals to avoid changing handoff.server's WebView contract.
  const { getSql } = await import("@/lib/db");
  const { currentHandoffKey, openSessionToken } = await import("@/lib/native/handoff-seal.server");
  const { hashHandoffCode, isHandoffCode } = await import("@/lib/native/handoff-code");
  const { isPkceMaterial, pkceChallenge } = await import("@/lib/native/pkce");
  if (!(await allowRequest(`native-claim-api:${ip}`, 20, 60_000))) return { ok: false };
  if (!isHandoffCode(code) || !isPkceMaterial(verifier)) return { ok: false };
  const challenge = await pkceChallenge(verifier);
  const resolved = currentHandoffKey();
  if (!resolved.ok) return { ok: false };
  const sql = await getSql();
  const rows = await sql<{ token_ciphertext: string }>`
    delete from native_auth_handoff
    where code_hash = ${hashHandoffCode(code)}
      and challenge = ${challenge}
      and token_ciphertext is not null
      and expires_at > now()
    returning token_ciphertext
  `;
  const sealed = rows[0]?.token_ciphertext;
  if (!sealed) return { ok: false };
  const token = openSessionToken(sealed, resolved.key);
  if (!token) return { ok: false };
  return { ok: true, token };
}

export async function signInEmailNative(
  request: Request,
  body: { email?: unknown; password?: unknown },
): Promise<{ ok: true; token: string } | { ok: false; error: string; status: number }> {
  if (!emailAndPasswordEnabled || !authConfigured) {
    return { ok: false, error: "email_disabled", status: 501 };
  }
  const ip = clientKey(request);
  if (!(await allowRequest(`native-v1-email:${ip}`, 20, 60_000))) {
    return { ok: false, error: "rate_limited", status: 429 };
  }
  const email = typeof body.email === "string" ? body.email.trim() : "";
  const password = typeof body.password === "string" ? body.password : "";
  if (!email || !password) return { ok: false, error: "invalid", status: 400 };
  try {
    const res = await auth.api.signInEmail({
      body: { email, password },
      headers: request.headers,
      asResponse: true,
    });
    if (!res.ok) {
      return { ok: false, error: "credentials", status: 401 };
    }
    const token = tokenFromSetCookie(res.headers) ?? sessionTokenFromCookie(request.headers.get("cookie"));
    if (!token) {
      // Some Better Auth builds put the token in the JSON body.
      const json = (await res.clone().json().catch(() => null)) as { token?: string } | null;
      if (json?.token) return { ok: true, token: json.token };
      return { ok: false, error: "no_token", status: 500 };
    }
    return { ok: true, token };
  } catch {
    return { ok: false, error: "credentials", status: 401 };
  }
}

export async function signInAppleNative(
  request: Request,
  body: { identityToken?: unknown; nonce?: unknown; fullName?: unknown },
): Promise<{ ok: true; token: string } | { ok: false; error: string; status: number }> {
  const apple = appleOAuthFromEnv(process.env);
  if (!apple.configured || !authConfigured) {
    return { ok: false, error: "apple_disabled", status: 501 };
  }
  const ip = clientKey(request);
  if (!(await allowRequest(`native-v1-apple:${ip}`, 20, 60_000))) {
    return { ok: false, error: "rate_limited", status: 429 };
  }
  const identityToken = typeof body.identityToken === "string" ? body.identityToken.trim() : "";
  if (!identityToken) return { ok: false, error: "invalid", status: 400 };
  const nonce = typeof body.nonce === "string" ? body.nonce : undefined;
  try {
    const res = await auth.api.signInSocial({
      body: {
        provider: APPLE_PROVIDER_ID,
        idToken: { token: identityToken, ...(nonce ? { nonce } : {}) },
        disableRedirect: true,
      },
      headers: request.headers,
      asResponse: true,
    });
    if (!res.ok) {
      const text = await res.text().catch(() => "");
      console.error("[native/v1/auth/apple]", res.status, text.slice(0, 200));
      return { ok: false, error: "apple_failed", status: 401 };
    }
    const token = tokenFromSetCookie(res.headers);
    if (!token) {
      const json = (await res.clone().json().catch(() => null)) as { token?: string } | null;
      if (json?.token) return { ok: true, token: json.token };
      return { ok: false, error: "no_token", status: 500 };
    }
    return { ok: true, token };
  } catch (error) {
    console.error("[native/v1/auth/apple]", error);
    return { ok: false, error: "apple_failed", status: 401 };
  }
}

function isTrustedBrowserOrigin(request: Request): boolean {
  // Prefer Sec-Fetch-Site when present (modern browsers).
  const site = request.headers.get("sec-fetch-site")?.toLowerCase();
  if (site === "cross-site" || site === "same-site") return false;
  const origin = request.headers.get("origin")?.trim();
  if (origin) {
    try {
      const url = new URL(origin);
      return isAllowedPublicHost(url.hostname) || trustedWebOrigins().includes(origin);
    } catch {
      return false;
    }
  }
  // No Origin: allow only when Referer is our host, or Sec-Fetch-Site is same-origin.
  const referer = request.headers.get("referer")?.trim();
  if (referer) {
    try {
      return isAllowedPublicHost(new URL(referer).hostname);
    } catch {
      return false;
    }
  }
  return site === "same-origin";
}

/** Upgrade a cookie session (classic Cap) into an explicit bearer token body. */
export async function bearerFromCookie(
  request: Request,
): Promise<{ ok: true; token: string } | { ok: false; error: string; status: number }> {
  const ip = clientKey(request);
  if (!(await allowRequest(`native-v1-from-cookie:${ip}`, 30, 60_000))) {
    return { ok: false, error: "rate_limited", status: 429 };
  }
  if (!isTrustedBrowserOrigin(request)) {
    return { ok: false, error: "forbidden_origin", status: 403 };
  }
  const token = sessionTokenFromCookie(request.headers.get("cookie"));
  if (!token) return { ok: false, error: "no_cookie", status: 401 };
  try {
    const session = await auth.api.getSession({ headers: request.headers });
    if (!session?.user?.id) return { ok: false, error: "unauthorized", status: 401 };
    return { ok: true, token };
  } catch {
    return { ok: false, error: "unauthorized", status: 401 };
  }
}

export async function signOutNative(
  request: Request,
): Promise<{ ok: true } | { ok: false; error: string; status: number }> {
  try {
    await auth.api.signOut({ headers: request.headers, asResponse: true });
  } catch {
    /* client still clears Keychain */
  }
  return { ok: true };
}

// Keep handoff import referenced for tree clarity in tests that mock modules.
void claimHandoff;
