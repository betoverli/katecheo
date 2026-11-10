/**
 * Nitro middleware: apply the same security headers as vercel.json for
 * preview/local and any path that bypasses the CDN header layer.
 */
import { securityHeaders, withSecurityHeaders } from "../../src/lib/security-headers";

interface SecurityEvent {
  url: URL;
  req: { method: string; headers: Headers };
}

export default async function securityHeadersMiddleware(
  _event: SecurityEvent,
  next: () => unknown | Promise<unknown>,
): Promise<unknown> {
  const result = await next();
  if (result instanceof Response) {
    return withSecurityHeaders(result);
  }
  // Non-Response results (rare) — nothing to stamp.
  void securityHeaders;
  return result;
}
