/**
 * 308 verse2note.com → https://katecheo.app (audit M9).
 *
 * Auto-registered via Nitro `serverDir: "./server"`. Exclusions live in
 * `src/lib/domain-cutover.ts` so unit tests cover the matcher without Nitro.
 */
import {
  isLegacyCutoverHost,
  legacyHostRedirectLocation,
} from "../../src/lib/domain-cutover";

interface CutoverEvent {
  url: URL;
  req: { method: string; headers: Headers };
}

function requestHost(event: CutoverEvent): string {
  const raw =
    event.req.headers.get("x-forwarded-host") ??
    event.req.headers.get("host") ??
    event.url.host;
  return raw.split(",")[0]?.trim().split(":")[0]?.toLowerCase() ?? "";
}

export default async function domainCutoverMiddleware(
  event: CutoverEvent,
  next: () => unknown | Promise<unknown>,
): Promise<unknown> {
  const host = requestHost(event);
  if (!isLegacyCutoverHost(host)) return next();

  const location = legacyHostRedirectLocation(
    host,
    event.url.pathname,
    event.url.search,
  );
  if (!location) return next();

  return new Response(null, {
    status: 308,
    headers: {
      Location: location,
      // Short CDN cache so a mistaken exclusion can be fixed without a long TTL.
      "Cache-Control": "public, max-age=0, must-revalidate",
    },
  });
}
