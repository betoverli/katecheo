/**
 * Broker identities still registered with Better Auth.
 *
 * Source of truth for the server (`server.ts`, one `genericOAuth` provider per
 * entry). Kept dependency-free so the client can import it without pulling the
 * server-only Better Auth instance (and `pg`) into the browser bundle.
 *
 * Google sign-in buttons use Better Auth's native Google social provider
 * (`./google`: env `GOOGLE_CLIENT_ID` / `GOOGLE_CLIENT_SECRET`, callback
 * `/api/auth/callback/google`). `grok-google` stays registered so an existing
 * broker account id can still be recognized. It is not a sign-in button.
 *
 * X (Better Auth id `twitter`, local id `grok-x`) is intentionally absent.
 * Existing account rows may still name that provider; new sign-in is not
 * offered. To bring a broker upstream back, add one entry here
 * (`{ providerId: "grok-x", idp: "twitter", label: "X" }`).
 * The `providerId` is this app's local id. Better Auth 1.7 serves social
 * callbacks at `/api/auth/callback/<providerId>`; `legacyGrokOAuthCallback`
 * keeps the broker allowlist path `/api/auth/oauth2/callback/<providerId>`.
 * `idp` is the hint the broker reads to pick the upstream.
 */
export type GrokProvider = {
  /** This app's local provider id; also the callback path segment. */
  providerId: string;
  /** Upstream hint the broker forwards to (Better Auth social id). */
  idp: string;
  /** Human label. Not used for the native Google button. */
  label: string;
};

export const GROK_PROVIDERS: readonly GrokProvider[] = [
  { providerId: "grok-google", idp: "google", label: "Google" },
];
