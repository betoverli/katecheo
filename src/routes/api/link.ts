import { createFileRoute } from "@tanstack/react-router";
import { collectRefs, corsJson, corsPreflight, queryFromSearch, rateLimited, resolveLinks } from "@/lib/bible/link-api";

export const Route = createFileRoute("/api/link")({
  server: {
    handlers: {
      OPTIONS: async () => corsPreflight(),
      GET: async ({ request }) => {
        const limited = await rateLimited(request);
        if (limited) return limited;
        const result = resolveLinks(queryFromSearch(new URL(request.url).searchParams));
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
            return corsJson(
              { ok: false, error: "Body must be JSON.", usage: "POST { ref, refs, app, translation, locale, native }" },
              400,
            );
          }
        }
        const search = new URL(request.url).searchParams;
        const fromBody = collectRefs([
          typeof body.ref === "string" ? body.ref : undefined,
          Array.isArray(body.refs) ? body.refs.map(String) : typeof body.refs === "string" ? body.refs : undefined,
        ]);
        const result = resolveLinks({
          refs: fromBody.length ? fromBody : queryFromSearch(search).refs,
          app: typeof body.app === "string" ? body.app : search.get("app") ?? undefined,
          translation:
            typeof body.translation === "string" ? body.translation : search.get("translation") ?? undefined,
          locale: typeof body.locale === "string" ? body.locale : search.get("locale") ?? undefined,
          native:
            body.native === true ||
            body.native === "1" ||
            search.get("native") === "1" ||
            search.get("native") === "true",
        });
        return corsJson(result, result.ok ? 200 : 400);
      },
    },
  },
});
