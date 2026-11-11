import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { describe, it } from "node:test";

describe("online status", () => {
  const status = readFileSync(new URL("./online-status.ts", import.meta.url), "utf8");

  it("does not seed offline from navigator.onLine alone", () => {
    assert.match(status, /Start optimistic|online = true/);
    assert.match(status, /never seed from navigator\.onLine/i);
    assert.match(status, /PROBE_PATH = "\/robots\.txt"/);
    assert.doesNotMatch(status, /\/api\/auth/);
  });

  it("requires repeated probe failures before going offline", () => {
    assert.match(status, /FAIL_WHEN_CLAIMING_ONLINE = 3/);
    assert.match(status, /FAIL_WHEN_CLAIMING_OFFLINE = 2/);
    assert.match(status, /onBrowserOnline/);
    assert.match(status, /setOnline\(true\)/);
  });
});
