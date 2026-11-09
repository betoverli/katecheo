import assert from "node:assert/strict";
import { describe, it } from "node:test";
import { apnsPayload, apnsSilentPayload } from "./apns-payload.ts";

describe("apnsPayload", () => {
  it("keeps the in-app path and drops an off-site href", () => {
    const ok = apnsPayload({ title: "Leitura", body: "Dia 2", href: "/reading/gospels-30" });
    assert.equal(ok.href, "/reading/gospels-30");
    assert.equal(ok.aps.alert.title, "Leitura");
    const blocked = apnsPayload({ title: "x", body: "y", href: "https://evil.example/phish" });
    assert.equal(blocked.href, "/app");
  });
});

describe("apnsSilentPayload", () => {
  it("emits content-available catalog hints without an alert", () => {
    const themes = apnsSilentPayload({ type: "themes_updated" });
    assert.equal(themes.aps["content-available"], 1);
    assert.equal(themes.type, "themes_updated");
    assert.equal("alert" in themes.aps, false);
    const reading = apnsSilentPayload({ type: "reading_updated", href: "/reading" });
    assert.equal(reading.type, "reading_updated");
    assert.equal(reading.href, "/reading");
  });
});
