/**
 * Public site identity for Katecheo.
 * `PUBLIC_BASE_URL` (e.g. https://katecheo.app) is the canonical origin.
 * verse2note.com / www.verse2note.com 308 to katecheo.app (same path+query)
 * except native API, well-known, and auth paths for old iOS builds — see
 * `domain-cutover.ts` and `docs/domain-cutover.md`. Both hosts stay in
 * Better Auth trusted origins until those builds are gone.
 */

export const BRAND_NAME = "Katecheo";

export const LEGACY_HOSTS = ["verse2note.com", "www.verse2note.com"] as const;
export const PRIMARY_HOSTS = ["katecheo.app", "www.katecheo.app"] as const;

const DEFAULT_PUBLIC_ORIGIN = "https://katecheo.app";
const LEGACY_PUBLIC_ORIGIN = "https://verse2note.com";

function normalizeOrigin(raw: string | undefined | null): string | null {
  const trimmed = raw?.trim();
  if (!trimmed) return null;
  try {
    const url = new URL(trimmed.includes("://") ? trimmed : `https://${trimmed}`);
    if (url.protocol !== "http:" && url.protocol !== "https:") return null;
    return url.origin;
  } catch {
    return null;
  }
}

/** Canonical public origin (emails, OG, OAuth bounce target). */
export function publicBaseUrl(): string {
  return normalizeOrigin(process.env.PUBLIC_BASE_URL) ?? DEFAULT_PUBLIC_ORIGIN;
}

/** Legacy origin kept live until DNS + redirects are finished. */
export function legacyPublicBaseUrl(): string {
  return LEGACY_PUBLIC_ORIGIN;
}

export function isAllowedPublicHost(hostname: string): boolean {
  const host = hostname.toLowerCase();
  return (
    host === "katecheo.app" ||
    host === "www.katecheo.app" ||
    host === "verse2note.com" ||
    host === "www.verse2note.com"
  );
}

/** Better Auth / CORS trusted web origins (both brands during cutover). */
export function trustedWebOrigins(): string[] {
  const primary = publicBaseUrl();
  const set = new Set<string>([
    primary,
    primary.replace("://", "://www."),
    LEGACY_PUBLIC_ORIGIN,
    "https://www.verse2note.com",
    "https://katecheo.app",
    "https://www.katecheo.app",
  ]);
  return [...set];
}

export function absoluteUrl(path = "/"): string {
  const base = publicBaseUrl().replace(/\/$/, "");
  if (!path || path === "/") return `${base}/`;
  return path.startsWith("/") ? `${base}${path}` : `${base}/${path}`;
}
