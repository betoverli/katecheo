import assert from "node:assert/strict";
import { describe, it } from "node:test";
import { publicApiCorsHeaders } from "./public-api-cors.ts";

describe("public API CORS (M5)", () => {
  it("keeps wildcard for MCP", () => {
    const headers = publicApiCorsHeaders(undefined, "mcp");
    assert.equal(headers["access-control-allow-origin"], "*");
  });

  it("allows trusted katecheo / verse2note origins only for link-style APIs", () => {
    const allowed = publicApiCorsHeaders(
      new Request("https://katecheo.app/api/link", {
        headers: { origin: "https://katecheo.app" },
      }),
      "trusted",
    );
    assert.equal(allowed["access-control-allow-origin"], "https://katecheo.app");

    const denied = publicApiCorsHeaders(
      new Request("https://katecheo.app/api/link", {
        headers: { origin: "https://evil.example" },
      }),
      "trusted",
    );
    assert.equal(denied["access-control-allow-origin"], undefined);
  });

  it("omits ACAO when there is no Origin (curl / server clients)", () => {
    const headers = publicApiCorsHeaders(new Request("https://katecheo.app/api/link"), "trusted");
    assert.equal(headers["access-control-allow-origin"], undefined);
    assert.equal(headers["access-control-allow-methods"], "GET, POST, OPTIONS");
  });
});
