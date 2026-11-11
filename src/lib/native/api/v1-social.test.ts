import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { describe, it } from "node:test";
import { matchNativeV1Route, methodAllowed, isPublicNativeAuthRoute } from "./v1-router.ts";

const socialSrc = readFileSync(new URL("./v1-social.server.ts", import.meta.url), "utf8");
const clientSrc = readFileSync(new URL("../../../../ios/App/Katecheo/NativeAPIClient.swift", import.meta.url), "utf8");
const friendsSrc = readFileSync(
  new URL("../../../../ios/App/Katecheo/FriendsActivityViewController.swift", import.meta.url),
  "utf8",
);

describe("native social routes (auth + methods)", () => {
  it("requires bearer for links, granted notes, and notifications", () => {
    assert.equal(isPublicNativeAuthRoute({ kind: "links" }), false);
    assert.equal(isPublicNativeAuthRoute({ kind: "links-accept" }), false);
    assert.equal(isPublicNativeAuthRoute({ kind: "links-decline" }), false);
    assert.equal(isPublicNativeAuthRoute({ kind: "links-remove" }), false);
    assert.equal(isPublicNativeAuthRoute({ kind: "links-request" }), false);
    assert.equal(isPublicNativeAuthRoute({ kind: "links-search" }), false);
    assert.equal(isPublicNativeAuthRoute({ kind: "notes-granted" }), false);
    assert.equal(isPublicNativeAuthRoute({ kind: "notifications" }), false);
    assert.equal(isPublicNativeAuthRoute({ kind: "notifications-summary" }), false);
    assert.equal(isPublicNativeAuthRoute({ kind: "notifications-read" }), false);
  });

  it("maps stable paths used by iOS (not colliding with notes/:id)", () => {
    assert.deepEqual(matchNativeV1Route("notes/granted"), { kind: "notes-granted" });
    assert.notEqual(matchNativeV1Route("notes/granted").kind, "notes");
    assert.deepEqual(matchNativeV1Route("notifications/read"), { kind: "notifications-read" });
    assert.deepEqual(matchNativeV1Route("notifications/summary"), { kind: "notifications-summary" });
    assert.deepEqual(matchNativeV1Route("links/request"), { kind: "links-request" });
    assert.deepEqual(matchNativeV1Route("links/remove"), { kind: "links-remove" });
  });

  it("only allows the intended verbs", () => {
    assert.equal(methodAllowed({ kind: "links" }, "GET"), true);
    assert.equal(methodAllowed({ kind: "links" }, "POST"), false);
    assert.equal(methodAllowed({ kind: "links-accept" }, "POST"), true);
    assert.equal(methodAllowed({ kind: "links-decline" }, "POST"), true);
    assert.equal(methodAllowed({ kind: "links-remove" }, "POST"), true);
    assert.equal(methodAllowed({ kind: "links-request" }, "POST"), true);
    assert.equal(methodAllowed({ kind: "links-search" }, "GET"), true);
    assert.equal(methodAllowed({ kind: "notes-granted" }, "GET"), true);
    assert.equal(methodAllowed({ kind: "notifications" }, "GET"), true);
    assert.equal(methodAllowed({ kind: "notifications-summary" }, "GET"), true);
    assert.equal(methodAllowed({ kind: "notifications-read" }, "POST"), true);
  });

  it("ships removeLinkForUser that deletes the pair for both users", () => {
    assert.match(socialSrc, /export async function removeLinkForUser/);
    assert.match(socialSrc, /status !== "accepted"/);
    assert.match(socialSrc, /delete from user_links/);
    assert.match(socialSrc, /delete from note_grants/);
    assert.match(clientSrc, /func removeLink\(handle:/);
    assert.match(clientSrc, /links\/remove/);
    assert.match(friendsSrc, /removeLink\(/);
    assert.match(friendsSrc, /Remover amigo/);
    assert.match(friendsSrc, /incomingAccessory/);
    assert.doesNotMatch(friendsSrc, /Pedidos só saem da lista/);
    assert.doesNotMatch(friendsSrc, /Nenhum pedido pendente/);
  });
});
