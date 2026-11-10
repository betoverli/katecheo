/**
 * Self-hosted Better Auth for THIS app (server-only).
 *
 * Pre-wired for live preview + deploy — do not rewrite this file. To enable
 * local email/password, flip the flag in `./email-password` only (see auth skill).
 *
 * The app runs its own Better Auth at `/api/auth/*`, so the session cookie stays
 * on this app's own origin. The legacy `grok-google` broker identity still
 * federates to the shared **Grok auth broker** (`GROK_AUTH_ISSUER`) via the
 * `genericOAuth` plugin. X is not registered. Native Google does not use the
 * broker: when `GOOGLE_CLIENT_ID` and `GOOGLE_CLIENT_SECRET` are set, Better
 * Auth's built-in Google social provider is registered (callback
 * `/api/auth/callback/google`).
 * If those env vars are missing, Google is omitted and the rest of auth still boots.
 *
 * Tri-mode:
 *   - Deployed: the deployer injects a per-app `GROK_AUTH_*` + `BETTER_AUTH_URL`
 *     + `DATABASE_URL`, so real federated auth is persisted in Postgres.
 *   - Sandbox live preview: no injection -> falls back to the shared **preview
 *     client** (`./preview`) and derives the preview's `https://*.grok-sandbox.com`
 *     origin from the request, so real sign-in works (no demo users). Sessions
 *     and identities persist in the embedded PGLite DB (same DB as app data);
 *     the process restart wipes both. Live-preview iframe clients use a bearer
 *     token (partitioned cookies) — see `client.ts`.
 *   - Off (`VITE_AUTH_ENABLED=false`, the shipped default): no providers;
 *     `requireUserId` resolves a dev user with no database configured, and
 *     throws fail-closed once `DATABASE_URL` is set (see `verify.server.ts`).
 *
 * NEVER import this from client code — it pulls in `pg` + the preview secret +
 * server-only Better Auth internals. The client uses `@/lib/auth/client`;
 * components read the user via `@/lib/auth/use-current-user`; server functions get
 * a verified id via `@/lib/auth/middleware`.
 */
import { betterAuth } from "better-auth";
import { bearer, genericOAuth } from "better-auth/plugins";
import { tanstackStartCookies } from "better-auth/tanstack-start";
import { getCookie } from "@tanstack/react-start/server";
import { randomBytes } from "node:crypto";
import { Pool } from "pg";
import { ensureDbReady, getPglite } from "../db";
import { emailAndPasswordEnabled } from "./email-password";
import { GATE_PROVIDER_ID, gateIdentitySessions } from "./gate-session.server";
import { APPLE_PROVIDER_ID, appleOAuthFromEnv } from "./apple";
import { GOOGLE_PROVIDER_ID, googleOAuthFromEnv } from "./google";
import { legacyGrokOAuthCallback } from "./legacy-oauth-callback";
import { GROK_PROVIDERS } from "./providers";
import { pgliteDialect } from "./pglite-dialect";
import {
  GROK_ISSUER_DEFAULT,
  PREVIEW_ALLOWED_HOSTS,
  PREVIEW_CLIENT_ID,
  PREVIEW_CLIENT_SECRET,
} from "./preview";
import { decodeJwtPayload, extractImage, pictureFromJwt } from "@/lib/oauth-photo";
import { trustedWebOrigins } from "@/lib/site";

// Kick (and share) PGLite bootstrap as soon as the auth server module loads.
void ensureDbReady();

/**
 * Preview secret must outlive module reloads: PGLite (and its session rows) is
 * stored on `globalThis`, so an HMR re-eval of this file must NOT mint a new
 * signing secret or every existing session becomes invalid mid-dev. Process
 * restart clears both the secret and PGLite together.
 */
const globalAuthRef = globalThis as typeof globalThis & {
  __grokAuthPreviewSecret__?: string;
};
function previewAuthSecret(): string {
  globalAuthRef.__grokAuthPreviewSecret__ ??= randomBytes(32).toString("hex");
  return globalAuthRef.__grokAuthPreviewSecret__;
}

/** Read an env var, treating empty/whitespace as unset. */
const env = (key: string): string | undefined => {
  const value = process.env[key]?.trim();
  return value ? value : undefined;
};

// Explicit off-switch. The deployer sets `VITE_AUTH_ENABLED=true` when it
// provisions auth; set it to "false" to force auth off everywhere (dev user).
const authDisabled = env("VITE_AUTH_ENABLED") === "false";

// Broker federation creds: the deployer injects a per-app client when deployed;
// otherwise fall back to the shared live-preview client, which the broker accepts
// for any `*.grok-sandbox.com` callback (see `./preview`).
const grokIssuer = env("GROK_AUTH_ISSUER") ?? GROK_ISSUER_DEFAULT;
const grokClientId = env("GROK_AUTH_CLIENT_ID") ?? PREVIEW_CLIENT_ID;
const grokClientSecret = env("GROK_AUTH_CLIENT_SECRET") ?? PREVIEW_CLIENT_SECRET;

/** True when federated sign-in is active (real auth is enforced). */
export const authConfigured =
  !authDisabled && Boolean(grokClientId && grokClientSecret);

/**
 * Native Google. Off unless both server env vars are set, and off entirely when
 * auth is disabled. Partial config does not register a broken provider.
 */
const googleOAuth = authDisabled ? { configured: false as const } : googleOAuthFromEnv(process.env);
const appleOAuth = authDisabled ? { configured: false as const } : appleOAuthFromEnv(process.env);

// This app's own Better Auth origin. When deployed the deployer injects the
// public URL. In the sandbox live preview there's no fixed URL (each preview gets
// a dynamic `*.grok-sandbox.com` host), so we hand Better Auth a dynamic baseURL:
// it derives the origin per-request from the (proxied) host, validated against the
// preview allowlist, which makes the OAuth `redirect_uri` the concrete preview URL
// the broker's preview client accepts.
const explicitBaseURL = env("BETTER_AUTH_URL");
// Explicit `string[]` (not a readonly tuple) — Better Auth's DynamicBaseURLConfig
// requires a mutable `allowedHosts: string[]`.
const previewAllowedHosts: string[] = [...PREVIEW_ALLOWED_HOSTS];
// Local `npm run dev` (port 8080 contract). Browsers may send Origin as any of
// these for the same server — trusting only `localhost` rejects `127.0.0.1` and
// breaks email/password with "Invalid origin".
const LOCAL_DEV_ORIGINS: string[] = [
  "http://localhost:8080",
  "http://127.0.0.1:8080",
  "http://[::1]:8080",
];
// Custom domains (Katecheo + legacy verse2note.com during DNS cutover). Without
// these, email/OAuth POSTs get Better Auth "Invalid origin".
const CUSTOM_ORIGINS: string[] = trustedWebOrigins();

function extraTrustedOrigins(): string[] {
  const raw = env("BETTER_AUTH_TRUSTED_ORIGINS");
  const fromEnv = raw
    ? raw.split(",").map((item) => item.trim()).filter(Boolean)
    : [];
  return [...CUSTOM_ORIGINS, ...fromEnv];
}

function hostOf(url: string | undefined): string | undefined {
  if (!url) return undefined;
  try {
    return new URL(url).hostname;
  } catch {
    return undefined;
  }
}

// Always derive baseURL from the request Host so OAuth redirect_uri and
// __Host- cookies land on the request host (katecheo.app or verse2note.com
// during cutover — not only the grok.me publish URL).
const deployedHost = hostOf(explicitBaseURL);
const baseURL = {
  allowedHosts: [
    ...previewAllowedHosts,
    "localhost",
    "127.0.0.1",
    "[::1]",
    // Better Auth matches the Host header, which includes the port. Without
    // these, local sign-in falls back to BETTER_AUTH_URL and Google is sent
    // the production redirect URI.
    "localhost:8080",
    "127.0.0.1:8080",
    "[::1]:8080",
    "katecheo.app",
    "www.katecheo.app",
    "verse2note.com",
    "www.verse2note.com",
    "*.grok.me",
    ...(deployedHost ? [deployedHost] : []),
  ],
  protocol: "auto" as const,
  fallback: explicitBaseURL ?? "http://localhost:8080",
};

// Origins Better Auth accepts on credentialed POSTs (sign-up/sign-in, etc.).
// Missing entries here surface as FORBIDDEN "Invalid origin".
const trustedOrigins: string[] = explicitBaseURL
  ? [
      ...new Set([
        explicitBaseURL,
        ...extraTrustedOrigins(),
        ...(explicitBaseURL.startsWith("https://") && !explicitBaseURL.includes("localhost")
          ? []
          : LOCAL_DEV_ORIGINS),
      ]),
    ]
  : [
      // Host wildcards (matched against Origin's host)
      ...previewAllowedHosts,
      // Full-origin wildcards (matched against Origin)
      ...previewAllowedHosts.flatMap((host) => [`https://${host}`, `http://${host}`]),
      ...extraTrustedOrigins(),
      ...LOCAL_DEV_ORIGINS,
    ];

const databaseUrl = env("DATABASE_URL");

// Static broker OAuth endpoints (skip OIDC discovery on every sign-in / callback).
// Discovery would cost an extra network hop to the broker before the popup can
// even redirect to the upstream — the live-preview popup felt stuck on the app for
// that whole round-trip. These paths match the broker's discovery document.
const issuerBase = grokIssuer.replace(/\/+$/, "");
const grokAuthorizationUrl = `${issuerBase}/api/auth/oauth2/authorize`;
const grokTokenUrl = `${issuerBase}/api/auth/oauth2/token`;
const grokUserInfoUrl = `${issuerBase}/api/auth/oauth2/userinfo`;

// Real Postgres when `DATABASE_URL` is set (deployed apps), else the app's
// embedded PGLite (preview) via a Kysely dialect — so Better Auth persists to the
// SAME DB as app data, including email/password users. Both use the Better Auth
// schema from `migrations/auth/0001_auth.sql`, copied into `migrations/` when
// the app turns sign-in on.
const database = databaseUrl
  ? new Pool({ connectionString: databaseUrl })
  : { dialect: pgliteDialect(() => getPglite()), type: "postgres" as const };

/** Session token cookie name — also read by the live-preview popup completion page. */
export const SESSION_TOKEN_COOKIE = "__Host-grok-auth.session_token";

// Built separately so the `betterAuth({...})` call stays easy to edit without
// breaking brackets (models often trip on the conditional plugin spread).
const grokOAuthPlugin = authConfigured
  ? genericOAuth({
      config: GROK_PROVIDERS.map(({ providerId, idp }) => ({
        providerId,
        clientId: grokClientId as string,
        clientSecret: grokClientSecret as string,
        // Prefer static endpoints over `discoveryUrl` so initiating (and
        // completing) OAuth does not wait on a broker discovery fetch.
        authorizationUrl: grokAuthorizationUrl,
        tokenUrl: grokTokenUrl,
        userInfoUrl: grokUserInfoUrl,
        scopes: ["openid", "profile", "email"],
        // Only `idp` — do not send prompt=login. That forced Google to treat
        // every visit as a first-time consent and mailed a new-app email.
        authorizationUrlParams: { idp },
        overrideUserInfo: true,
        getUserInfo: async (tokens) => {
          const fromJwt = decodeJwtPayload(tokens.idToken) ?? {};
          let fromApi: Record<string, unknown> = {};
          if (tokens.accessToken) {
            try {
              const response = await fetch(grokUserInfoUrl, {
                headers: { Authorization: `Bearer ${tokens.accessToken}` },
              });
              if (response.ok) {
                const body: unknown = await response.json();
                if (body && typeof body === "object") fromApi = body as Record<string, unknown>;
              }
            } catch {
              /* userinfo is best-effort; id token may still have the picture */
            }
          }
          const profile = { ...fromJwt, ...fromApi };
          const image =
            extractImage(fromApi) ||
            extractImage(fromJwt) ||
            pictureFromJwt(tokens.idToken);
          const id = String(profile.sub ?? profile.id ?? "");
          if (!id) return null;
          return {
            id,
            name: String(profile.name ?? profile.login ?? ""),
            email: typeof profile.email === "string" ? profile.email : undefined,
            emailVerified: Boolean(profile.email_verified),
            image,
          };
        },
        mapProfileToUser: (profile: Record<string, unknown>) => ({
          name: String(profile.name ?? profile.login ?? ""),
          email: typeof profile.email === "string" ? profile.email : undefined,
          image: extractImage(profile) || (typeof profile.image === "string" ? profile.image : undefined),
        }),
      })),
    })
  : null;

export const auth = betterAuth({
  baseURL,
  // Deployed apps inject BETTER_AUTH_SECRET. Preview: process-stable secret on
  // globalThis so HMR doesn't invalidate PGLite-backed sessions (see above).
  secret: env("BETTER_AUTH_SECRET") ?? previewAuthSecret(),
  database,

  // CSRF / origin check for credentialed auth POSTs (email sign-up/sign-in, …).
  // See `trustedOrigins` construction above — must cover live preview hosts AND
  // local loopback variants, or clients get "Invalid origin".
  trustedOrigins,

  // Encrypt broker-issued OAuth tokens at rest, and treat registered broker
  // identities as trusted first-party identities. WITHOUT this a login can fail
  // with `account_not_linked` (Better Auth refuses to attach an untrusted,
  // unverified identity to an existing user). Google and a password account
  // stay separate identities.
  account: {
    encryptOAuthTokens: true,
    accountLinking: {
      enabled: true,
      trustedProviders: [
        ...GROK_PROVIDERS.map((p) => p.providerId),
        ...(googleOAuth.configured ? [GOOGLE_PROVIDER_ID] : []),
        ...(appleOAuth.configured ? [APPLE_PROVIDER_ID] : []),
        GATE_PROVIDER_ID,
      ],
      // Password accounts are never email-verified (no mailer). Require the
      // local email to be verified before linking, so an attacker cannot
      // register victim@gmail.com then ride the victim's later Google login.
      // Google still creates its own user when the local email is unverified.
      requireLocalEmailVerified: true,
      // Explicit "add Google or email" from a signed-in profile links the new
      // identity onto the current user. Google uses Better Auth `linkSocial`
      // (`/api/auth/callback/google`). Those identities do not share an email,
      // so linking must allow it.
      allowDifferentEmails: true,
    },
  },

  // Cache the session in the short-lived signed `session_data` cookie so reads
  // (incl. the client's `/get-session`) skip the DB — this shrinks the "loading"
  // window and reduces auth flicker. See the `auth` skill for the full
  // flicker-prevention guidance (gate on `isPending`; SSR the session).
  session: { cookieCache: { enabled: true, maxAge: 300 } },

  // Local email/password — toggled only via `./email-password` (not a plugin).
  ...(emailAndPasswordEnabled ? { emailAndPassword: { enabled: true } } : {}),

  // Native Google Cloud OAuth. `select_account` lets the visitor pick an account
  // without `prompt=consent` / `prompt=login`, which made Google treat every
  // visit as a first-time consent. Callback: `/api/auth/callback/google`.
  // Apple is optional (APPLE_CLIENT_ID + APPLE_CLIENT_SECRET) for Sign in with Apple.
  ...((googleOAuth.configured || appleOAuth.configured)
    ? {
        socialProviders: {
          ...(googleOAuth.configured
            ? {
                google: {
                  clientId: googleOAuth.clientId,
                  clientSecret: googleOAuth.clientSecret,
                  prompt: "select_account" as const,
                  overrideUserInfoOnSignIn: true,
                },
              }
            : {}),
          ...(appleOAuth.configured
            ? {
                apple: {
                  clientId: appleOAuth.clientId,
                  clientSecret: appleOAuth.clientSecret,
                },
              }
            : {}),
        },
      }
    : {}),

  // `__Host-` prefixed cookies: the browser REFUSES any same-named cookie that
  // carries a `Domain` attribute, so a sibling `*.grok.me` app cannot "toss" a
  // `Domain=.grok.me` session cookie onto this app. `__Host-` requires Secure +
  // Path=/ + no Domain; Better Auth otherwise uses `__Secure-` (which permits
  // Domain), so we drop its auto prefix (`useSecureCookies: false`) and set
  // Secure + the names ourselves. (Browsers allow Secure cookies on
  // `http://localhost`, so local dev still works.)
  advanced: {
    useSecureCookies: false,
    defaultCookieAttributes: { secure: true, sameSite: "lax", path: "/" },
    cookies: {
      session_token: { name: SESSION_TOKEN_COOKIE },
      session_data: { name: "__Host-grok-auth.session_data" },
      account_data: { name: "__Host-grok-auth.account_data" },
      dont_remember: { name: "__Host-grok-auth.dont_remember" },
    },
  },

  plugins: [
    gateIdentitySessions(),

    // One genericOAuth provider per remaining broker identity (when auth is on).
    // X is not in `GROK_PROVIDERS`, so Better Auth does not register it.
    ...(grokOAuthPlugin ? [grokOAuthPlugin] : []),
    // Keep broker allowlisted `/oauth2/callback/<id>` paths on Better Auth 1.7.
    ...(grokOAuthPlugin ? [legacyGrokOAuthCallback()] : []),

    // Accept `Authorization: Bearer <session-token>` as an alternative to the
    // cookie. Needed for the LIVE PREVIEW: the app runs in an embedded iframe
    // where cookies are partitioned, so after popup sign-in it authenticates with
    // a bearer token instead (see `client.ts` / the `auth` skill). The hook only
    // fires when an Authorization header is present, so the cookie path
    // (deployed apps) is unaffected.
    bearer(),

    // Bridges Better Auth's Set-Cookie into TanStack Start responses. MUST be
    // last so it runs after every other plugin's hooks.
    tanstackStartCookies(),
  ],
});

export function readSessionToken(): string | null {
  return getCookie(SESSION_TOKEN_COOKIE) ?? null;
}

// Re-exported for convenience; the array lives in the dependency-free
// `providers.ts` so the client can import it too.
export { GROK_PROVIDERS } from "./providers";
