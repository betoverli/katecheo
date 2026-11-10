import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { describe, it } from "node:test";
import {
  canonicalCutoverOrigin,
  isLegacyCutoverExclusion,
  isLegacyCutoverHost,
  legacyHostRedirectLocation,
  legacyToCanonicalRedirectUrl,
} from "./domain-cutover.ts";

describe("domain-cutover middleware wiring", () => {
  it("ships Nitro middleware that 308s via the shared matcher", () => {
    const middleware = readFileSync(
      new URL("../../server/middleware/domain-cutover.ts", import.meta.url),
      "utf8",
    );
    assert.match(middleware, /legacyHostRedirectLocation/);
    assert.match(middleware, /status:\s*308/);
    assert.match(middleware, /isLegacyCutoverHost/);
  });
});

describe("legacy cutover host detection", () => {
  it("matches verse2note apex and www only", () => {
    assert.equal(isLegacyCutoverHost("verse2note.com"), true);
    assert.equal(isLegacyCutoverHost("www.verse2note.com"), true);
    assert.equal(isLegacyCutoverHost("VERSE2NOTE.COM"), true);
    assert.equal(isLegacyCutoverHost("verse2note.com:443"), true);
    assert.equal(isLegacyCutoverHost("katecheo.app"), false);
    assert.equal(isLegacyCutoverHost("www.katecheo.app"), false);
    assert.equal(isLegacyCutoverHost("verse2note.vercel.app"), false);
    assert.equal(isLegacyCutoverHost("localhost"), false);
  });
});

describe("legacy cutover exclusions", () => {
  const excluded = [
    "/api/native",
    "/api/native/",
    "/api/native/v1/notes",
    "/api/native/v1/auth/email",
    "/api/native/v1/auth/apple",
    "/.well-known",
    "/.well-known/",
    "/.well-known/apple-app-site-association",
    "/.well-known/assetlinks.json",
    "/api/auth",
    "/api/auth/callback/google",
    "/api/auth/callback/apple",
    "/api/auth/oauth2/callback/grok-google",
    "/api/auth/sign-in/email",
    "/api/auth/get-session",
    "/auth",
    "/auth/",
    "/auth/native-start",
    "/auth/native-done",
    "/auth/native-return",
    "/auth/native-config",
    "/auth/popup",
  ];

  const redirected = [
    "/",
    "/app",
    "/about",
    "/privacy",
    "/login",
    "/notebook",
    "/groups/abc",
    "/api/link",
    "/api/mcp",
    "/api/collections",
    "/api/plans",
    "/sw.js",
    "/robots.txt",
  ];

  for (const path of excluded) {
    it(`excludes ${path}`, () => {
      assert.equal(isLegacyCutoverExclusion(path), true);
      assert.equal(legacyHostRedirectLocation("verse2note.com", path), null);
      assert.equal(legacyHostRedirectLocation("www.verse2note.com", path, "?x=1"), null);
    });
  }

  for (const path of redirected) {
    it(`redirects ${path}`, () => {
      assert.equal(isLegacyCutoverExclusion(path), false);
      assert.equal(
        legacyHostRedirectLocation("verse2note.com", path),
        `https://katecheo.app${path}`,
      );
      assert.equal(
        legacyHostRedirectLocation("www.verse2note.com", path, "?q=1&b=2"),
        `https://katecheo.app${path}?q=1&b=2`,
      );
    });
  }

  it("does not treat /api/nativeX as native API", () => {
    assert.equal(isLegacyCutoverExclusion("/api/nativeX"), false);
    assert.equal(
      legacyHostRedirectLocation("verse2note.com", "/api/nativeX"),
      "https://katecheo.app/api/nativeX",
    );
  });

  it("does not treat /authenticate as /auth", () => {
    assert.equal(isLegacyCutoverExclusion("/authenticate"), false);
    assert.equal(
      legacyHostRedirectLocation("verse2note.com", "/authenticate"),
      "https://katecheo.app/authenticate",
    );
  });
});

describe("legacyToCanonicalRedirectUrl", () => {
  it("builds Location with path and query on katecheo.app", () => {
    assert.equal(
      legacyToCanonicalRedirectUrl("https://verse2note.com/about?lang=pt"),
      "https://katecheo.app/about?lang=pt",
    );
    assert.equal(
      legacyToCanonicalRedirectUrl("https://www.verse2note.com/groups/x"),
      "https://katecheo.app/groups/x",
    );
  });

  it("returns null for excluded legacy paths and non-legacy hosts", () => {
    assert.equal(
      legacyToCanonicalRedirectUrl(
        "https://verse2note.com/api/native/v1/notes?limit=10",
      ),
      null,
    );
    assert.equal(
      legacyToCanonicalRedirectUrl(
        "https://verse2note.com/api/auth/callback/google?code=abc",
      ),
      null,
    );
    assert.equal(
      legacyToCanonicalRedirectUrl("https://verse2note.com/.well-known/apple-app-site-association"),
      null,
    );
    assert.equal(
      legacyToCanonicalRedirectUrl("https://verse2note.com/auth/native-start?return=scheme"),
      null,
    );
    assert.equal(legacyToCanonicalRedirectUrl("https://katecheo.app/about"), null);
  });

  it("canonical origin is apex katecheo.app", () => {
    assert.equal(canonicalCutoverOrigin(), "https://katecheo.app");
  });
});
