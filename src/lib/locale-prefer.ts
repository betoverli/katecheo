import type { Locale } from "./bible/books.ts";

function asLocale(value: unknown): Locale | null {
  return value === "en" || value === "es" || value === "pt" ? value : null;
}

function tagToLocale(tag: string): Locale | null {
  const lower = tag.toLowerCase();
  if (lower === "pt" || lower.startsWith("pt-")) return "pt";
  if (lower === "en" || lower.startsWith("en-")) return "en";
  if (lower === "es" || lower.startsWith("es-")) return "es";
  return null;
}

/**
 * Map Accept-Language (or a single BCP-47 tag) to pt | en | es.
 * Honors q-values; default: pt (pt-BR).
 */
export function localeFromAcceptLanguage(header: string | null | undefined): Locale {
  if (!header) return "pt";
  const scored: { locale: Locale; q: number; index: number }[] = [];
  const parts = header.split(",");
  parts.forEach((raw, index) => {
    const [tagPart, ...params] = raw.trim().split(";");
    const tag = tagPart?.trim() ?? "";
    if (!tag) return;
    const locale = tagToLocale(tag);
    if (!locale) return;
    let q = 1;
    for (const param of params) {
      const m = param.trim().match(/^q\s*=\s*([0-9.]+)$/i);
      if (m) {
        const parsed = Number(m[1]);
        if (Number.isFinite(parsed)) q = parsed;
      }
    }
    scored.push({ locale, q, index });
  });
  if (scored.length === 0) return "pt";
  scored.sort((a, b) => b.q - a.q || a.index - b.index);
  return scored[0]!.locale;
}

export function localeFromCookieHeader(cookie: string | null | undefined): Locale | null {
  if (!cookie) return null;
  const match = cookie.match(/(?:^|;\s*)v2n-locale=(pt|en|es)(?:;|$)/);
  return asLocale(match?.[1] ?? null);
}

/** Prefer explicit cookie, then Accept-Language, then pt. */
export function resolveRequestLocale(opts: {
  cookie?: string | null;
  acceptLanguage?: string | null;
}): Locale {
  return localeFromCookieHeader(opts.cookie) ?? localeFromAcceptLanguage(opts.acceptLanguage);
}
