/**
 * App-level security headers for Katecheo (CSP, HSTS, framing, MIME sniffing).
 *
 * CSP notes (must keep login + auth popup/handoff working):
 * - `'unsafe-inline'` scripts: theme boot in `__root.tsx`, auth popup completion
 *   HTML (`popup.server.ts`), and Vite/TanStack hydration markers.
 * - `https://grok.com`: App Builder PWA branding injector (`grok-pwa` middleware).
 * - Google / Apple OAuth: accounts.google.com, appleid.apple.com (+ gstatic).
 * - `frame-ancestors`: allow self + Grok embedder preview hosts; block others.
 * - MCP/public JSON APIs are not framed; headers still apply via middleware.
 */

export const SECURITY_HEADER_NAMES = [
  "Content-Security-Policy",
  "Strict-Transport-Security",
  "X-Content-Type-Options",
  "Referrer-Policy",
  "X-Frame-Options",
] as const;

/** CSP string used by Vercel + Nitro middleware (keep in sync with vercel.json). */
export function contentSecurityPolicy(): string {
  const directives = [
    "default-src 'self'",
    "base-uri 'self'",
    "object-src 'none'",
    "frame-ancestors 'self' https://grok.com https://*.grok.com",
    "form-action 'self' https://accounts.google.com https://appleid.apple.com",
    [
      "script-src",
      "'self'",
      "'unsafe-inline'",
      "https://grok.com",
      "https://accounts.google.com",
      "https://appleid.apple.com",
    ].join(" "),
    "style-src 'self' 'unsafe-inline'",
    "img-src 'self' data: blob: https:",
    "font-src 'self' data:",
    [
      "connect-src",
      "'self'",
      "https://katecheo.app",
      "https://*.katecheo.app",
      "https://verse2note.com",
      "https://*.verse2note.com",
      "https://accounts.google.com",
      "https://appleid.apple.com",
      "https://*.googleapis.com",
      "https://*.gstatic.com",
      "https://grok.com",
      "https://*.grok.com",
      "wss:",
    ].join(" "),
    "frame-src 'self' https://accounts.google.com https://appleid.apple.com",
    "worker-src 'self' blob:",
    "manifest-src 'self'",
  ];
  return directives.join("; ");
}

export function securityHeaders(): Record<string, string> {
  return {
    "Content-Security-Policy": contentSecurityPolicy(),
    "Strict-Transport-Security": "max-age=31536000; includeSubDomains; preload",
    "X-Content-Type-Options": "nosniff",
    "Referrer-Policy": "strict-origin-when-cross-origin",
    // Legacy framing hint; CSP frame-ancestors is authoritative for modern browsers.
    "X-Frame-Options": "SAMEORIGIN",
  };
}

/** Merge security headers onto a Response without clobbering existing CSP. */
export function withSecurityHeaders(response: Response): Response {
  const headers = new Headers(response.headers);
  const extras = securityHeaders();
  for (const [key, value] of Object.entries(extras)) {
    if (!headers.has(key)) headers.set(key, value);
  }
  return new Response(response.body, {
    status: response.status,
    statusText: response.statusText,
    headers,
  });
}
