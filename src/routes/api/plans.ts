import { createFileRoute } from "@tanstack/react-router";
import { corsJson, corsPreflight, rateLimited } from "@/lib/bible/link-api";
import { queryPlansFromSearch, resolvePlans } from "@/lib/bible/plans-api";

export const Route = createFileRoute("/api/plans")({
  server: {
    handlers: {
      OPTIONS: async ({ request }) => corsPreflight(request),
      GET: async ({ request }) => {
        const limited = await rateLimited(request);
        if (limited) return limited;
        const result = resolvePlans(queryPlansFromSearch(new URL(request.url).searchParams));
        return corsJson(result, result.ok ? 200 : 400, request);
      },
      POST: async ({ request }) => {
        const limited = await rateLimited(request);
        if (limited) return limited;
        let body: Record<string, unknown> = {};
        const text = await request.text();
        if (text) {
          try {
            body = JSON.parse(text) as Record<string, unknown>;
          } catch {
            return corsJson(
              { ok: false, error: "Body must be JSON.", usage: "POST { q, id, category, day, locale, app }" },
              400,
              request,
            );
          }
        }
        const fromSearch = queryPlansFromSearch(new URL(request.url).searchParams);
        const result = resolvePlans({
          q: typeof body.q === "string" ? body.q : fromSearch.q,
          id: typeof body.id === "string" ? body.id : fromSearch.id,
          category: typeof body.category === "string" ? body.category : fromSearch.category,
          day: typeof body.day === "number" || typeof body.day === "string" ? body.day : fromSearch.day,
          locale: typeof body.locale === "string" ? body.locale : fromSearch.locale,
          app: typeof body.app === "string" ? body.app : fromSearch.app,
          translation: typeof body.translation === "string" ? body.translation : fromSearch.translation,
          native: body.native === true || body.native === "1" || fromSearch.native,
        });
        return corsJson(result, result.ok ? 200 : 400, request);
      },
    },
  },
});
