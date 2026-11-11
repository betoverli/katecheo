import assert from "node:assert/strict";
import { readFileSync, existsSync } from "node:fs";
import { describe, it } from "node:test";
import { isFormerWebAppPath, WEB_APP_REDIRECT_PATHS } from "./web-app-gone.ts";

const root = new URL("../../", import.meta.url);

function read(rel: string) {
  return readFileSync(new URL(rel, root), "utf8");
}

describe("marketing cutover — former web app paths", () => {
  it("flags classic product URLs as former web app paths", () => {
    assert.equal(isFormerWebAppPath("/app"), true);
    assert.equal(isFormerWebAppPath("/login"), true);
    assert.equal(isFormerWebAppPath("/notebook/abc"), true);
    assert.equal(isFormerWebAppPath("/groups/xyz"), true);
    assert.equal(isFormerWebAppPath("/profile/edit"), true);
    assert.equal(isFormerWebAppPath("/u/beto"), true);
    assert.equal(isFormerWebAppPath("/"), false);
    assert.equal(isFormerWebAppPath("/privacy"), false);
    assert.equal(isFormerWebAppPath("/for-ai"), false);
    assert.equal(isFormerWebAppPath("/api/native/v1/session"), false);
  });

  it("keeps redirect stubs for known product routes", () => {
    for (const path of WEB_APP_REDIRECT_PATHS) {
      assert.equal(isFormerWebAppPath(path), true, path);
    }
    const appRoute = read("src/routes/app.tsx");
    assert.match(appRoute, /redirectWebAppToLanding/);
    assert.match(appRoute, /statusCode:\s*308|redirectWebAppToLanding/);
    const loginRoute = read("src/routes/login.tsx");
    assert.match(loginRoute, /redirectWebAppToLanding/);
  });

  it("vercel.json permanently redirects former web product paths home", () => {
    const vercel = JSON.parse(read("vercel.json")) as {
      redirects?: { source: string; destination: string; permanent?: boolean }[];
    };
    const redirects = vercel.redirects ?? [];
    assert.ok(redirects.length > 0);
    for (const rule of redirects) {
      assert.equal(rule.destination, "/");
      assert.equal(rule.permanent, true);
    }
    assert.ok(redirects.some((r) => r.source === "/app"));
    assert.ok(redirects.some((r) => r.source === "/login"));
    assert.ok(redirects.some((r) => r.source === "/notebook/:path*"));
  });
});

describe("marketing cutover — kept surfaces", () => {
  it("keeps native API routes, AI tools, auth bridges, and legal pages", () => {
    assert.equal(existsSync(new URL("src/routes/api/native/v1/$.ts", root)), true);
    assert.equal(existsSync(new URL("src/routes/api/native/v1.index.ts", root)), true);
    assert.equal(existsSync(new URL("src/routes/api/link.ts", root)), true);
    assert.equal(existsSync(new URL("src/routes/api/collections.ts", root)), true);
    assert.equal(existsSync(new URL("src/routes/api/plans.ts", root)), true);
    assert.equal(existsSync(new URL("src/routes/api/mcp.ts", root)), true);
    assert.equal(existsSync(new URL("src/routes/api/auth/$.ts", root)), true);
    assert.equal(existsSync(new URL("src/routes/auth/native-start.ts", root)), true);
    assert.equal(existsSync(new URL("src/routes/auth/native-done.ts", root)), true);
    assert.equal(existsSync(new URL("src/routes/auth/native-return.tsx", root)), true);
    assert.equal(existsSync(new URL("src/routes/privacy.tsx", root)), true);
    assert.equal(existsSync(new URL("src/routes/terms.tsx", root)), true);
    assert.equal(existsSync(new URL("src/routes/contact.tsx", root)), true);
    assert.equal(existsSync(new URL("src/routes/for-ai.tsx", root)), true);
    assert.equal(existsSync(new URL("migrations/0025_password_reset.sql", root)), true);
  });

  it("App Store CTA is driven by a single config constant", () => {
    const cfg = read("src/lib/app-store.ts");
    assert.match(cfg, /export const APP_STORE_URL/);
    assert.match(cfg, /INSTAGRAM_URL/);
    const landing = read("src/components/landing.tsx");
    assert.match(landing, /APP_STORE_URL|APP_STORE_LIVE/);
    assert.match(landing, /INSTAGRAM_URL/);
  });
});
