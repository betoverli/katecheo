/**
 * Native auth endpoints for `/api/native/v1/auth/*`.
 * Returns Better Auth session tokens as bearers for Keychain storage.
 */
import { APPLE_PROVIDER_ID, appleNativeFromEnv } from "@/lib/auth/apple";
import {
  createAppleSessionToken,
  findOrCreateAppleUser,
  storeAppleRefreshToken,
  type AppleFullName,
} from "@/lib/auth/apple-native.server";
import { exchangeAppleAuthorizationCode } from "@/lib/auth/apple-token.server";
import {
  AppleTokenVerifyError,
  verifyAppleIdentityToken,
} from "@/lib/auth/apple-verify.server";
import {
  emailAndPasswordEnabled,
  emailPasswordMinLength,
} from "@/lib/auth/email-password";
import { GOOGLE_PROVIDER_ID, googleOAuthFromEnv } from "@/lib/auth/google";
import {
  PASSWORD_RESET_EMAIL_RATE_MAX,
  PASSWORD_RESET_IP_RATE_MAX,
  PASSWORD_RESET_MAX_ATTEMPTS,
  PASSWORD_RESET_TTL_MS,
  PASSWORD_RESET_VERIFY_IP_RATE_MAX,
  asPasswordResetLocale,
  generateResetCode,
  hashResetCode,
  isSixDigitCode,
  normalizeResetEmail,
  resetCodesMatch,
} from "@/lib/auth/password-reset-code";
import { buildPasswordResetEmail } from "@/lib/auth/password-reset-email";
import { sendResendEmail } from "@/lib/auth/resend-email.server";
import { auth, authConfigured, SESSION_TOKEN_COOKIE } from "@/lib/auth/server";
import { getSql } from "@/lib/db";
import { allowRequest, clientKey } from "@/lib/rate-limit";
import { claimHandoff } from "@/lib/native/handoff.server";
import { NATIVE_SESSION_COOKIE, sessionTokenFromCookie } from "@/lib/native/session-cookie";
import { isAllowedPublicHost, trustedWebOrigins } from "@/lib/site";

const GENERIC_FORGOT_OK = { ok: true as const };

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
  // Native Apple only needs APPLE_CLIENT_ID (JWKS verify).
  const apple = appleNativeFromEnv(process.env);
  return {
    ok: true as const,
    authConfigured,
    google: google.configured,
    apple: apple.configured && authConfigured,
    email: emailAndPasswordEnabled && authConfigured,
    minPasswordLength: emailPasswordMinLength,
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

function betterAuthErrorCode(payload: unknown): string | null {
  if (!payload || typeof payload !== "object") return null;
  const obj = payload as Record<string, unknown>;
  if (typeof obj.code === "string" && obj.code) return obj.code;
  const err = obj.error;
  if (err && typeof err === "object" && !Array.isArray(err)) {
    const nested = err as Record<string, unknown>;
    if (typeof nested.code === "string" && nested.code) return nested.code;
  }
  return null;
}

async function tokenFromAuthResponse(
  res: Response,
  request: Request,
): Promise<{ ok: true; token: string } | { ok: false; error: string; status: number }> {
  const token = tokenFromSetCookie(res.headers) ?? sessionTokenFromCookie(request.headers.get("cookie"));
  if (token) return { ok: true, token };
  const json = (await res.clone().json().catch(() => null)) as { token?: string } | null;
  if (json?.token) return { ok: true, token: json.token };
  return { ok: false, error: "no_token", status: 500 };
}

/** Native email sign-up → Better Auth `signUpEmail` → bearer for Keychain. */
export async function signUpEmailNative(
  request: Request,
  body: { name?: unknown; email?: unknown; password?: unknown },
): Promise<{ ok: true; token: string } | { ok: false; error: string; status: number }> {
  if (!emailAndPasswordEnabled || !authConfigured) {
    return { ok: false, error: "email_disabled", status: 501 };
  }
  const ip = clientKey(request);
  if (!(await allowRequest(`native-v1-email-signup:${ip}`, 15, 60_000))) {
    return { ok: false, error: "rate_limited", status: 429 };
  }
  const name = typeof body.name === "string" ? body.name.trim() : "";
  const email = typeof body.email === "string" ? body.email.trim() : "";
  const password = typeof body.password === "string" ? body.password : "";
  if (!name || !email || !password) return { ok: false, error: "invalid", status: 400 };
  if (password.length < emailPasswordMinLength) {
    return { ok: false, error: "password_short", status: 400 };
  }
  try {
    const res = await auth.api.signUpEmail({
      body: { name, email, password },
      headers: request.headers,
      asResponse: true,
    });
    if (!res.ok) {
      const json = await res.clone().json().catch(() => null);
      const code = betterAuthErrorCode(json)?.toUpperCase() ?? "";
      if (code.includes("USER_ALREADY_EXISTS")) {
        return { ok: false, error: "email_exists", status: 409 };
      }
      if (code.includes("PASSWORD_TOO_SHORT")) {
        return { ok: false, error: "password_short", status: 400 };
      }
      if (code.includes("INVALID_EMAIL")) {
        return { ok: false, error: "invalid_email", status: 400 };
      }
      return { ok: false, error: "signup_failed", status: res.status >= 400 && res.status < 600 ? res.status : 400 };
    }
    return tokenFromAuthResponse(res, request);
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error ?? "");
    const upper = message.toUpperCase();
    if (upper.includes("USER_ALREADY_EXISTS") || /already exists/i.test(message)) {
      return { ok: false, error: "email_exists", status: 409 };
    }
    if (upper.includes("PASSWORD_TOO_SHORT") || /password too short/i.test(message)) {
      return { ok: false, error: "password_short", status: 400 };
    }
    if (upper.includes("INVALID_EMAIL") || /invalid email/i.test(message)) {
      return { ok: false, error: "invalid_email", status: 400 };
    }
    console.error("[native/v1/auth/email/sign-up]", error);
    return { ok: false, error: "signup_failed", status: 400 };
  }
}

function parseAppleFullName(raw: unknown): AppleFullName | null {
  if (!raw || typeof raw !== "object" || Array.isArray(raw)) return null;
  const obj = raw as Record<string, unknown>;
  const givenName =
    typeof obj.givenName === "string"
      ? obj.givenName
      : typeof obj.firstName === "string"
        ? obj.firstName
        : undefined;
  const familyName =
    typeof obj.familyName === "string"
      ? obj.familyName
      : typeof obj.lastName === "string"
        ? obj.lastName
        : undefined;
  if (!givenName && !familyName) return null;
  return { givenName, familyName };
}

export async function signInAppleNative(
  request: Request,
  body: {
    identityToken?: unknown;
    authorizationCode?: unknown;
    nonce?: unknown;
    fullName?: unknown;
    name?: unknown;
  },
): Promise<{ ok: true; token: string } | { ok: false; error: string; status: number }> {
  const apple = appleNativeFromEnv(process.env);
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
  const authorizationCode =
    typeof body.authorizationCode === "string" ? body.authorizationCode.trim() : "";
  const fullName = parseAppleFullName(body.fullName) ?? parseAppleFullName(body.name);

  try {
    const claims = await verifyAppleIdentityToken(identityToken, {
      audience: apple.audience,
      nonce: nonce ?? null,
    });
    const user = await findOrCreateAppleUser(claims, fullName);

    if (authorizationCode) {
      const exchanged = await exchangeAppleAuthorizationCode(authorizationCode);
      if (exchanged.refreshToken) {
        await storeAppleRefreshToken(user.id, claims.sub, exchanged.refreshToken);
      }
    }

    const token = await createAppleSessionToken(user.id);
    return { ok: true, token };
  } catch (error) {
    if (error instanceof AppleTokenVerifyError) {
      console.error("[native/v1/auth/apple]", error.code, error.message);
      return { ok: false, error: "apple_failed", status: 401 };
    }
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

/**
 * Request a 6-digit reset code by email.
 * Always returns the same generic 200 body whether or not the account exists.
 * Rate limits: per email (3 / 15 min) and per IP (10 / 15 min).
 */
export async function forgotPasswordNative(
  request: Request,
  body: { email?: unknown; locale?: unknown },
): Promise<{ ok: true } | { ok: false; error: string; status: number }> {
  if (!emailAndPasswordEnabled || !authConfigured) {
    return { ok: false, error: "email_disabled", status: 501 };
  }
  const ip = clientKey(request);
  if (!(await allowRequest(`native-v1-forgot-ip:${ip}`, PASSWORD_RESET_IP_RATE_MAX, PASSWORD_RESET_TTL_MS))) {
    return { ok: false, error: "rate_limited", status: 429 };
  }

  const emailRaw = typeof body.email === "string" ? body.email : "";
  const email = normalizeResetEmail(emailRaw);
  if (!email || email.length > 320 || !email.includes("@")) {
    // Same generic success — do not leak validation vs existence.
    return GENERIC_FORGOT_OK;
  }

  if (!(await allowRequest(`native-v1-forgot-email:${email}`, PASSWORD_RESET_EMAIL_RATE_MAX, PASSWORD_RESET_TTL_MS))) {
    return { ok: false, error: "rate_limited", status: 429 };
  }

  const locale = asPasswordResetLocale(body.locale);

  try {
    const sql = await getSql();
    const users = await sql<{ id: string }>`
      select u.id
      from "user" u
      inner join account a on a."userId" = u.id
      where lower(u.email) = ${email}
        and a."providerId" = 'credential'
        and a.password is not null
        and length(a.password) > 0
      limit 1
    `;
    const userId = users[0]?.id;
    if (!userId) {
      // Timing cover: still hash a dummy code so work is similar.
      hashResetCode("missing-user", generateResetCode());
      return GENERIC_FORGOT_OK;
    }

    const code = generateResetCode();
    const codeHash = hashResetCode(userId, code);
    const id = crypto.randomUUID().replaceAll("-", "");
    const expiresAt = new Date(Date.now() + PASSWORD_RESET_TTL_MS).toISOString();

    // Invalidate older unused codes for this user.
    await sql`
      update password_reset_codes
      set used_at = now()
      where user_id = ${userId}
        and used_at is null
    `;
    await sql`
      insert into password_reset_codes (
        id, user_id, email_normalized, code_hash, attempts, expires_at, created_at
      ) values (
        ${id}, ${userId}, ${email}, ${codeHash}, 0, ${expiresAt}::timestamptz, now()
      )
    `;

    const copy = buildPasswordResetEmail(locale, code);
    const from = process.env.EMAIL_FROM?.trim() || "";
    const sent = await sendResendEmail({
      from,
      to: email,
      subject: copy.subject,
      html: copy.html,
      text: copy.text,
    });
    if (!sent.ok) {
      console.error("[native/v1/auth/email/forgot-password] email not sent", sent.error, sent.detail);
    }
  } catch (error) {
    console.error("[native/v1/auth/email/forgot-password]", error);
  }

  return GENERIC_FORGOT_OK;
}

/**
 * Verify the 6-digit code, set a new password, revoke other sessions, sign in.
 * Returns the same `{ ok, token }` payload as email sign-in.
 */
export async function resetPasswordNative(
  request: Request,
  body: { email?: unknown; code?: unknown; newPassword?: unknown },
): Promise<{ ok: true; token: string } | { ok: false; error: string; status: number }> {
  if (!emailAndPasswordEnabled || !authConfigured) {
    return { ok: false, error: "email_disabled", status: 501 };
  }
  const ip = clientKey(request);
  if (!(await allowRequest(`native-v1-reset-ip:${ip}`, PASSWORD_RESET_VERIFY_IP_RATE_MAX, 60_000))) {
    return { ok: false, error: "rate_limited", status: 429 };
  }

  const email = normalizeResetEmail(typeof body.email === "string" ? body.email : "");
  const code = typeof body.code === "string" ? body.code.trim() : "";
  const newPassword = typeof body.newPassword === "string" ? body.newPassword : "";
  if (!email || !isSixDigitCode(code) || !newPassword) {
    return { ok: false, error: "invalid", status: 400 };
  }
  if (newPassword.length < emailPasswordMinLength) {
    return { ok: false, error: "password_short", status: 400 };
  }
  if (newPassword.length > 200) {
    return { ok: false, error: "invalid", status: 400 };
  }

  try {
    const sql = await getSql();
    const rows = await sql<{
      id: string;
      user_id: string;
      code_hash: string;
      attempts: number;
      expires_at: string | Date;
    }>`
      select id, user_id, code_hash, attempts, expires_at
      from password_reset_codes
      where email_normalized = ${email}
        and used_at is null
        and expires_at > now()
      order by created_at desc
      limit 1
    `;
    const row = rows[0];
    if (!row) {
      return { ok: false, error: "invalid_code", status: 400 };
    }
    if (Number(row.attempts) >= PASSWORD_RESET_MAX_ATTEMPTS) {
      await sql`
        update password_reset_codes set used_at = now() where id = ${row.id} and used_at is null
      `;
      return { ok: false, error: "code_exhausted", status: 400 };
    }

    if (!resetCodesMatch(row.code_hash, row.user_id, code)) {
      const nextAttempts = Number(row.attempts) + 1;
      if (nextAttempts >= PASSWORD_RESET_MAX_ATTEMPTS) {
        await sql`
          update password_reset_codes
          set attempts = ${nextAttempts}, used_at = now()
          where id = ${row.id} and used_at is null
        `;
        return { ok: false, error: "code_exhausted", status: 400 };
      }
      await sql`
        update password_reset_codes
        set attempts = ${nextAttempts}
        where id = ${row.id} and used_at is null
      `;
      return { ok: false, error: "invalid_code", status: 400 };
    }

    // Consume the code first so concurrent resets cannot reuse it.
    const consumed = await sql<{ id: string }>`
      update password_reset_codes
      set used_at = now()
      where id = ${row.id}
        and used_at is null
        and expires_at > now()
      returning id
    `;
    if (!consumed[0]?.id) {
      return { ok: false, error: "invalid_code", status: 400 };
    }

    const ctx = await auth.$context;
    const passwordHash = await ctx.password.hash(newPassword);
    const credential = await ctx.internalAdapter.findCredentialAccount(row.user_id);
    if (!credential?.password) {
      return { ok: false, error: "invalid_code", status: 400 };
    }
    await ctx.internalAdapter.updatePassword(row.user_id, passwordHash);
    await ctx.internalAdapter.deleteUserSessions(row.user_id);

    const session = await ctx.internalAdapter.createSession(row.user_id, false);
    if (!session?.token) {
      return { ok: false, error: "no_token", status: 500 };
    }
    return { ok: true, token: session.token };
  } catch (error) {
    console.error("[native/v1/auth/email/reset-password]", error);
    return { ok: false, error: "server_error", status: 500 };
  }
}

// Keep handoff import referenced for tree clarity in tests that mock modules.
void claimHandoff;
