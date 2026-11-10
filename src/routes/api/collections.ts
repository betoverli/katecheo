import { createFileRoute } from "@tanstack/react-router";
import { corsJson, corsPreflight, rateLimited } from "@/lib/bible/link-api";
import { queryCollectionsFromSearch, resolveCollections } from "@/lib/bible/collections-api";

export const Route = createFileRoute("/api/collections")({
  server: {
    handlers: {
      OPTIONS: async () => corsPreflight(),
      GET: async ({ request }) => {
        const limited = await rateLimited(request);
        if (limited) return limited;
        const result = resolveCollections(queryCollectionsFromSearch(new URL(request.url).searchParams));
        return corsJson(result, result.ok ? 200 : 400);
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
            return corsJson({ ok: false, error: "Body must be JSON.", usage: "POST { q, id, category, locale, app }" }, 400);
          }
        }
        const search = new URL(request.url).searchParams;
        const fromSearch = queryCollectionsFromSearch(search);
        const result = resolveCollections({
          q: typeof body.q === "string" ? body.q : fromSearch.q,
          id: typeof body.id === "string" ? body.id : fromSearch.id,
          category: typeof body.category === "string" ? body.category : fromSearch.category,
          locale: typeof body.locale === "string" ? body.locale : fromSearch.locale,
          app: typeof body.app === "string" ? body.app : fromSearch.app,
          translation: typeof body.translation === "string" ? body.translation : fromSearch.translation,
          native: body.native === true || body.native === "1" || fromSearch.native,
        });
        return corsJson(result, result.ok ? 200 : 400);
      },
    },
  },
});
