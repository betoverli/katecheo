/**
 * Legacy-host → katecheo.app cutover (audit M9).
 *
 * Requests to verse2note.com / www.verse2note.com 308 to the same path+query
 * on https://katecheo.app, except paths old iOS builds and OAuth still need
 * on the legacy host (native API, AASA, Better Auth callbacks, native login).
 */

import { LEGACY_HOSTS, publicBaseUrl } from "./site.ts";

/** Apex canonical origin for permanent redirects. */
export function canonicalCutoverOrigin(): string {
  // Always apex katecheo.app for cutover Location headers (www already 308s
  // at the Vercel domain layer). Fall back if PUBLIC_BASE_URL is mis-set.
  const primary = publicBaseUrl();
  try {
    const url = new URL(primary);
    if (url.hostname === "www.katecheo.app") return "https://katecheo.app";
    if (url.hostname === "katecheo.app") return url.origin;
  } catch {
    /* ignore */
  }
  return "https://katecheo.app";
}

export function isLegacyCutoverHost(hostname: string): boolean {
  const host = hostname.toLowerCase().split(":")[0] ?? "";
  return (LEGACY_HOSTS as readonly string[]).includes(host);
}

/**
 * Paths that must keep serving on verse2note.com during the dual-host window.
 * Conservative: anything that could break an old build's login or Universal
 * Links stays put.
 */
export function isLegacyCutoverExclusion(pathname: string): boolean {
  const path = pathname.length > 0 ? pathname : "/";

  // Old TestFlight / App Store builds call the native API on verse2note.com.
  if (path === "/api/native" || path.startsWith("/api/native/")) return true;

  // apple-app-site-association (+ any other well-known for old applinks).
  if (path === "/.well-known" || path.startsWith("/.well-known/")) return true;

  // Better Auth (Google/Apple social + legacy broker oauth2/callback/*).
  if (path === "/api/auth" || path.startsWith("/api/auth/")) return true;

  // Native OAuth start/done/return/config + /auth/popup completion.
  if (path === "/auth" || path.startsWith("/auth/")) return true;

  return false;
}

/**
 * If this request should 308 off the legacy host, return the Location URL.
 * Otherwise null (serve as-is on this host).
 */
export function legacyHostRedirectLocation(
  host: string,
  pathname: string,
  search = "",
): string | null {
  if (!isLegacyCutoverHost(host)) return null;
  if (isLegacyCutoverExclusion(pathname)) return null;
  const qs = search && search !== "?" ? (search.startsWith("?") ? search : `?${search}`) : "";
  const path = pathname.length > 0 ? pathname : "/";
  return `${canonicalCutoverOrigin()}${path}${qs}`;
}

/** Convenience for full request URLs (tests + middleware). */
export function legacyToCanonicalRedirectUrl(requestUrl: string | URL): string | null {
  const url = typeof requestUrl === "string" ? new URL(requestUrl) : new URL(requestUrl.href);
  return legacyHostRedirectLocation(url.hostname, url.pathname, url.search);
}
