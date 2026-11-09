/**
 * Where the system browser sends the one-time code. `https` is a Universal
 * Link on the canonical public host (only this app's team can claim it).
 * `scheme` is the custom URL, used until that association exists. Both are PKCE-bound.
 */

import { isAllowedPublicHost, legacyPublicBaseUrl, publicBaseUrl } from "../site.ts";

export type NativeReturnMode = "https" | "scheme";

export const UNIVERSAL_RETURN_PATH = "/auth/native-return";
/** Canonical OAuth / Universal Link origin (PUBLIC_BASE_URL → katecheo.app). */
export const UNIVERSAL_RETURN_ORIGIN = publicBaseUrl();
/** Legacy apex kept live until DNS + 308 cutover finish. */
export const LEGACY_RETURN_ORIGIN = legacyPublicBaseUrl();

/**
 * Host the system browser must open for Google.
 *
 * Better Auth sets `redirect_uri` from the request host
 * (`{origin}/api/auth/callback/google`). A WebView on any other host —
 * a Vercel deployment URL, for example — would send Google a callback that
 * is not registered. Local and sandbox origins stay put so those environments
 * can register their own callback. katecheo.app and verse2note.com are both OK
 * (apex form) during the cutover.
 */
export function nativeOAuthStartOrigin(pageUrl: string): string {
  let url: URL;
  try {
    url = new URL(pageUrl);
  } catch {
    return UNIVERSAL_RETURN_ORIGIN;
  }
  const host = url.hostname.toLowerCase();
  if (host === "katecheo.app" || host === "www.katecheo.app") return UNIVERSAL_RETURN_ORIGIN;
  if (host === "verse2note.com" || host === "www.verse2note.com") return LEGACY_RETURN_ORIGIN;
  const http = url.protocol === "http:" || url.protocol === "https:";
  if (
    http &&
    (host === "localhost" || host === "127.0.0.1" || host === "[::1]" || host.endsWith(".grok-sandbox.com"))
  ) {
    return url.origin;
  }
  return UNIVERSAL_RETURN_ORIGIN;
}

/**
 * Where a non-canonical `/auth/native-start` request must go before Google
 * is contacted. Null means this request's host is already the one Better
 * Auth will put in `redirect_uri`.
 */
export function canonicalNativeStart(requestUrl: string): string | null {
  let url: URL;
  try {
    url = new URL(requestUrl);
  } catch {
    return null;
  }
  const origin = nativeOAuthStartOrigin(url.href);
  if (origin === url.origin) return null;
  return new URL(`${url.pathname}${url.search}`, origin).toString();
}

export function parseReturnMode(value: string | null | undefined): NativeReturnMode {
  return value === "https" ? "https" : "scheme";
}

/**
 * Mode the website asks the installed app to open.
 *
 * An HTTPS auth callback on the TestFlight build is refused or reported as a
 * cancel when the associated-domain check is missing or stale. The login
 * screen treats that cancel as the user giving up, so it never opens the
 * custom-scheme sheet. That scheme is already registered in the binary.
 */
export function preferredNativeReturnMode(): NativeReturnMode {
  return "scheme";
}

export function nativeReturnTo(
  mode: NativeReturnMode,
  params: { code?: string; error?: boolean },
): string {
  const query = new URLSearchParams();
  if (params.error) query.set("error", "1");
  if (params.code) query.set("code", params.code);
  const qs = query.toString();
  if (mode === "https") {
    return `${UNIVERSAL_RETURN_ORIGIN}${UNIVERSAL_RETURN_PATH}${qs ? `?${qs}` : ""}`;
  }
  return `verse2note://auth${qs ? `?${qs}` : ""}`;
}

/**
 * The HTTPS auth session refuses to present when the app is not associated
 * via `webcredentials` (typical on a TestFlight build that only declared
 * `applinks`). That failure is not a user cancel, so the caller can open the
 * custom-scheme session instead. A cancel must not start a second prompt.
 */
export function shouldFallBackToScheme(mode: NativeReturnMode, message: string): boolean {
  if (mode !== "https") return false;
  return !/cancel/i.test(message);
}

/** True when this URL is the callback the app is waiting for, and it succeeded. */
export function isAllowedReturn(url: URL, mode: NativeReturnMode): boolean {
  if (url.searchParams.has("error")) return false;
  const code = url.searchParams.get("code") ?? "";
  if (!/^[A-Za-z0-9_-]{43,128}$/.test(code)) return false;
  if (mode === "https") {
    return (
      url.protocol === "https:" &&
      isAllowedPublicHost(url.hostname) &&
      url.pathname === UNIVERSAL_RETURN_PATH
    );
  }
  // Existing installs use verse2note://; katecheo:// is registered as an extra scheme.
  return (
    (url.protocol === "verse2note:" || url.protocol === "katecheo:") && url.hostname === "auth"
  );
}
