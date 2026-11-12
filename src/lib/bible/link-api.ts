import { BIBLE_APPS, appById, buildDeepLink } from "@/lib/bible/apps";
import type { Locale } from "@/lib/bible/books";
import { parseReference } from "@/lib/bible/parse";
import { formatPassageById, type Passage } from "@/lib/bible/passage";
import { normalizeTranslationId, translationById } from "@/lib/bible/translations";
import { buildCopyPayload, buildListPayload } from "@/lib/copy-rich";
import { allowRequest, clientKey } from "@/lib/rate-limit";
import {
  publicApiCorsHeaders,
  type PublicApiCorsMode,
} from "@/lib/bible/public-api-cors";

export { publicApiCorsHeaders, type PublicApiCorsMode } from "@/lib/bible/public-api-cors";

const LOCALES: Locale[] = ["pt", "en", "es"];
const MAX_REFS = 30;

export type LinkQuery = {
  refs: string[];
  app?: string;
  translation?: string;
  locale?: string;
  native?: boolean;
};

export type LinkItem = {
  input: string;
  label: string;
  url: string;
  markdown: string;
  html: string;
  plain: string;
};

export type LinkOk = {
  ok: true;
  locale: Locale;
  app: string;
  translation: string;
  native: boolean;
  items: LinkItem[];
  markdown: string;
  html: string;
  plain: string;
};

export type LinkErr = {
  ok: false;
  error: string;
  usage: string;
};

export type LinkResult = LinkOk | LinkErr;

export const LINK_USAGE =
  "GET /api/link?ref=John+3:16&app=youversion&translation=niv&locale=en — also refs=John+3:16|Romans+8:28";

function asLocale(value: string | undefined): Locale {
  if (value === "en" || value === "es" || value === "pt") return value;
  return "pt";
}

function parseAny(input: string, preferred: Locale): Passage | null {
  const order: Locale[] = [preferred, ...LOCALES.filter((item) => item !== preferred)];
  for (const locale of order) {
    const parsed = parseReference(input, locale);
    if (parsed) return parsed;
  }
  return null;
}

export function collectRefs(values: Array<string | string[] | undefined | null>): string[] {
  const out: string[] = [];
  for (const value of values) {
    if (!value) continue;
    const parts = Array.isArray(value) ? value : [value];
    for (const part of parts) {
      for (const piece of part.split(/[\n|;]+/)) {
        const trimmed = piece.trim();
        if (trimmed) out.push(trimmed);
      }
    }
  }
  return out.slice(0, MAX_REFS);
}

export function queryFromSearch(search: URLSearchParams): LinkQuery {
  return {
    refs: collectRefs([...search.getAll("ref"), search.get("refs")]),
    app: search.get("app") ?? undefined,
    translation: search.get("translation") ?? undefined,
    locale: search.get("locale") ?? undefined,
    native: search.get("native") === "1" || search.get("native") === "true",
  };
}

export function resolveLinks(query: LinkQuery): LinkResult {
  const locale = asLocale(query.locale);
  if (query.refs.length === 0) {
    return { ok: false, error: "Missing ref. Pass ref=John+3:16 or refs=John+3:16|Romans+8:28.", usage: LINK_USAGE };
  }

  if (query.app && !BIBLE_APPS.some((app) => app.id === query.app)) {
    return {
      ok: false,
      error: `Unknown app "${query.app}". Use: ${BIBLE_APPS.map((app) => app.id).join(", ")}.`,
      usage: LINK_USAGE,
    };
  }

  const app = appById(query.app || "youversion");
  // Tolerate legacy numeric YouVersion ids stored in prefs (`"111"` → `niv`).
  const translation = translationById(
    normalizeTranslationId(query.translation, locale),
    locale,
  );
  const native = Boolean(query.native);
  const items: LinkItem[] = [];

  for (const input of query.refs) {
    const passage = parseAny(input, locale);
    if (!passage) {
      return { ok: false, error: `Could not parse "${input}".`, usage: LINK_USAGE };
    }
    const url = buildDeepLink(app.id, passage, translation, native);
    if (!url) {
      return { ok: false, error: `Could not build a link for "${input}".`, usage: LINK_USAGE };
    }
    const label = formatPassageById(passage, locale);
    const payload = buildCopyPayload(label, url, "markdown");
    items.push({
      input,
      label,
      url,
      markdown: payload.markdown,
      html: payload.html,
      plain: `${label}\n${url}`,
    });
  }

  const list = buildListPayload(
    items.map((item) => ({ label: item.label, url: item.url })),
    "markdown",
  );

  return {
    ok: true,
    locale,
    app: app.id,
    translation: translation.id,
    native,
    items,
    markdown: list.markdown,
    html: list.html,
    plain: items.map((item) => item.plain).join("\n\n"),
  };
}

export async function rateLimited(
  request: Request,
  mode: PublicApiCorsMode = "trusted",
) {
  // Shared Neon rate_limit_buckets (migration 0022) — not process-local.
  if (!(await allowRequest(`api:${clientKey(request)}`, 90, 60_000))) {
    return corsJson({ ok: false, error: "Too many requests." }, 429, request, mode);
  }
  return null;
}

export function corsJson(
  data: unknown,
  status = 200,
  request?: Request,
  mode: PublicApiCorsMode = "trusted",
): Response {
  return new Response(JSON.stringify(data), {
    status,
    headers: {
      "content-type": "application/json; charset=utf-8",
      "cache-control": "no-store",
      ...publicApiCorsHeaders(request, mode),
    },
  });
}

export function corsPreflight(
  request?: Request,
  mode: PublicApiCorsMode = "trusted",
): Response {
  return new Response(null, {
    status: 204,
    headers: publicApiCorsHeaders(request, mode),
  });
}
