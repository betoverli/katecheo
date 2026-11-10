import { trustedWebOrigins } from "../site.ts";

/**
 * CORS for public JSON APIs.
 * - `trusted`: katecheo / verse2note web origins only (link, collections, plans).
 * - `mcp`: `*` — MCP hosts (Claude Desktop, Cursor, agents) call from arbitrary
 *   origins or with no Origin; JSON-RPC cannot use a cookie credential here.
 */
export type PublicApiCorsMode = "trusted" | "mcp";

export function publicApiCorsHeaders(
  request: Request | undefined,
  mode: PublicApiCorsMode = "trusted",
): Record<string, string> {
  const base: Record<string, string> = {
    "access-control-allow-methods": "GET, POST, OPTIONS",
    "access-control-allow-headers": "Content-Type, Accept, MCP-Protocol-Version",
    Vary: "Origin",
  };
  if (mode === "mcp") {
    return { ...base, "access-control-allow-origin": "*" };
  }
  const origin = request?.headers.get("origin")?.trim() ?? "";
  if (!origin) return base;
  if (trustedWebOrigins().includes(origin)) {
    return { ...base, "access-control-allow-origin": origin };
  }
  return base;
}
