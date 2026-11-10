import assert from "node:assert/strict";
import { describe, it } from "node:test";
import { contentSecurityPolicy, securityHeaders, withSecurityHeaders } from "./security-headers.ts";

describe("security headers (M6)", () => {
  it("emits CSP with frame-ancestors, HSTS, nosniff, referrer", () => {
    const headers = securityHeaders();
    assert.match(headers["Content-Security-Policy"], /frame-ancestors/);
    assert.match(headers["Content-Security-Policy"], /accounts\.google\.com/);
    assert.match(headers["Content-Security-Policy"], /appleid\.apple\.com/);
    assert.match(headers["Content-Security-Policy"], /grok\.com/);
    assert.match(headers["Strict-Transport-Security"], /max-age=31536000/);
    assert.equal(headers["X-Content-Type-Options"], "nosniff");
    assert.equal(headers["Referrer-Policy"], "strict-origin-when-cross-origin");
  });

  it("keeps inline script allowance for auth popup / theme boot", () => {
    assert.match(contentSecurityPolicy(), /'unsafe-inline'/);
  });

  it("does not clobber an existing CSP on a Response", () => {
    const res = withSecurityHeaders(
      new Response("ok", { headers: { "Content-Security-Policy": "default-src 'none'" } }),
    );
    assert.equal(res.headers.get("Content-Security-Policy"), "default-src 'none'");
    assert.equal(res.headers.get("X-Content-Type-Options"), "nosniff");
  });
});
