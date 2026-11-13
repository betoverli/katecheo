import assert from "node:assert/strict";
import { existsSync, readFileSync } from "node:fs";
import { describe, it } from "node:test";

const root = new URL("../../", import.meta.url);

describe("OG / Twitter share cards", () => {
  it("ships cache-busted Katecheo PNGs and wires absolute metadata URLs", () => {
    assert.ok(existsSync(new URL("public/og-katecheo-v2.png", root)));
    assert.ok(existsSync(new URL("public/twitter-katecheo-v2.png", root)));
    assert.equal(existsSync(new URL("public/og.jpg", root)), false);
    assert.equal(existsSync(new URL("public/x-banner.jpg", root)), false);

    const seo = readFileSync(new URL("src/lib/seo.ts", root), "utf8");
    assert.match(seo, /og-katecheo-v2\.png/);
    assert.match(seo, /twitter-katecheo-v2\.png/);
    assert.match(seo, /og:image:width/);
    assert.match(seo, /og:image:height/);
    assert.doesNotMatch(seo, /\/og\.jpg/);
    assert.doesNotMatch(seo, /x-banner\.jpg/);

    const site = JSON.parse(readFileSync(new URL("src/lib/og/site.json", root), "utf8"));
    assert.equal(site.card, "custom");
    assert.equal(site.image, "/og-katecheo-v2.png");
    assert.equal(site.banner, "/twitter-katecheo-v2.png");

    const groups = readFileSync(new URL("src/routes/groups.$id.tsx", root), "utf8");
    assert.match(groups, /pageHead/);
    assert.match(groups, /og-katecheo|pageHead/);

    const pwa = readFileSync(new URL("scripts/grok-pwa-shared.mjs", root), "utf8");
    assert.match(pwa, /og-katecheo-v2\.png/);
    assert.match(pwa, /twitter-katecheo-v2\.png/);
  });
});
