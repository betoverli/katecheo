/**
 * Deploy-only silent catalog APNs broadcast.
 * Auth: `Authorization: Bearer <CATALOG_PUSH_SECRET>` or header `x-catalog-push-secret`.
 * Not a public route — refused without the secret (M7).
 */
import { createFileRoute } from "@tanstack/react-router";
import {
  authorizeCatalogBroadcast,
  broadcastCatalogHint,
  type CatalogPushKind,
} from "@/lib/catalog-push.server";

function secretFromRequest(request: Request): string | null {
  const bearer = request.headers.get("authorization")?.trim() ?? "";
  if (/^Bearer\s+/i.test(bearer)) return bearer.replace(/^Bearer\s+/i, "").trim();
  return request.headers.get("x-catalog-push-secret")?.trim() || null;
}

function parseKind(raw: unknown): CatalogPushKind | null {
  return raw === "themes_updated" || raw === "reading_updated" ? raw : null;
}

export const Route = createFileRoute("/api/internal/catalog-push")({
  server: {
    handlers: {
      POST: async ({ request }) => {
        const secret = secretFromRequest(request);
        if (!authorizeCatalogBroadcast(secret)) {
          return new Response(JSON.stringify({ ok: false, error: "unauthorized" }), {
            status: 401,
            headers: { "content-type": "application/json; charset=utf-8", "cache-control": "no-store" },
          });
        }
        let body: Record<string, unknown> = {};
        try {
          const text = await request.text();
          if (text) body = JSON.parse(text) as Record<string, unknown>;
        } catch {
          return new Response(JSON.stringify({ ok: false, error: "invalid_json" }), {
            status: 400,
            headers: { "content-type": "application/json; charset=utf-8", "cache-control": "no-store" },
          });
        }
        const kind = parseKind(body.kind);
        if (!kind) {
          return new Response(
            JSON.stringify({
              ok: false,
              error: "invalid_kind",
              usage: '{ "kind": "themes_updated" | "reading_updated" }',
            }),
            {
              status: 400,
              headers: { "content-type": "application/json; charset=utf-8", "cache-control": "no-store" },
            },
          );
        }
        const result = await broadcastCatalogHint(kind, secret);
        return new Response(JSON.stringify(result), {
          status: result.ok ? 200 : result.error === "unauthorized" ? 401 : 500,
          headers: { "content-type": "application/json; charset=utf-8", "cache-control": "no-store" },
        });
      },
    },
  },
});
