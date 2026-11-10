/**
 * Native Google sign-in (Better Auth social provider).
 *
 * This is not the Grok auth broker. The broker provider id is `grok-google`
 * (compat callback `/api/auth/oauth2/callback/grok-google`). Native Google
 * uses Better Auth's built-in provider id `google` and callback path below.
 *
 * Both `GOOGLE_CLIENT_ID` and `GOOGLE_CLIENT_SECRET` must be set on the server.
 * If either is missing, the provider is not registered and the Google button
 * stays hidden. Email/password sign-in is unaffected.
 *
 * Full redirect URI registered in Google Cloud Console:
 * `https://katecheo.app/api/auth/callback/google`
 * Better Auth builds it as `{origin}/api/auth/callback/google` from the
 * request host. It is never `/auth/native-done`, `/auth/native-return`,
 * or the `Katecheo` scheme. The native app opens
 * `https://katecheo.app/auth/native-start` so a WebView on another host
 * cannot send Google a different callback.
 */

export const GOOGLE_PROVIDER_ID = "google" as const;

/** Server-only. Never prefix with `VITE_` — that would ship the secret to the browser. */
export const GOOGLE_CLIENT_ID_ENV = "GOOGLE_CLIENT_ID";
export const GOOGLE_CLIENT_SECRET_ENV = "GOOGLE_CLIENT_SECRET";

/** Better Auth social callback. Do not rename; Google must whitelist this path. */
export const GOOGLE_CALLBACK_PATH = "/api/auth/callback/google";

export type GoogleOAuthConfig =
  | { configured: false }
  | { configured: true; clientId: string; clientSecret: string };

export function googleOAuthFromEnv(
  env: Record<string, string | undefined>,
): GoogleOAuthConfig {
  const clientId = env[GOOGLE_CLIENT_ID_ENV]?.trim() ?? "";
  const clientSecret = env[GOOGLE_CLIENT_SECRET_ENV]?.trim() ?? "";
  if (!clientId || !clientSecret) return { configured: false };
  return { configured: true, clientId, clientSecret };
}
