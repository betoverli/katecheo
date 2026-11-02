import assert from "node:assert/strict";
import { describe, it } from "node:test";
import { isPublicNativeAuthRoute, matchNativeV1Route, methodAllowed } from "./v1-router.ts";

describe("matchNativeV1Route", () => {
  it("maps the catalog and session", () => {
    assert.deepEqual(matchNativeV1Route(""), { kind: "catalog" });
    assert.deepEqual(matchNativeV1Route("/"), { kind: "catalog" });
    assert.deepEqual(matchNativeV1Route("session"), { kind: "session" });
  });

  it("maps notes collection and item", () => {
    assert.deepEqual(matchNativeV1Route("notes"), { kind: "notes" });
    assert.deepEqual(matchNativeV1Route("notes/abc123"), { kind: "notes", noteId: "abc123" });
  });

  it("maps speakers and apns device", () => {
    assert.deepEqual(matchNativeV1Route("speakers"), { kind: "speakers" });
    assert.deepEqual(matchNativeV1Route("speakers/s1"), { kind: "speakers", speakerId: "s1" });
    assert.deepEqual(matchNativeV1Route("devices/apns"), { kind: "devices-apns" });
  });

  it("maps native auth endpoints", () => {
    assert.deepEqual(matchNativeV1Route("auth/providers"), { kind: "auth-providers" });
    assert.deepEqual(matchNativeV1Route("auth/claim"), { kind: "auth-claim" });
    assert.deepEqual(matchNativeV1Route("auth/email"), { kind: "auth-email" });
    assert.deepEqual(matchNativeV1Route("auth/apple"), { kind: "auth-apple" });
    assert.deepEqual(matchNativeV1Route("auth/from-cookie"), { kind: "auth-from-cookie" });
    assert.deepEqual(matchNativeV1Route("auth/sign-out"), { kind: "auth-sign-out" });
  });

  it("maps groups collection, item, and notes", () => {
    assert.deepEqual(matchNativeV1Route("groups"), { kind: "groups" });
    assert.deepEqual(matchNativeV1Route("groups/g1"), { kind: "groups", groupId: "g1" });
    assert.deepEqual(matchNativeV1Route("groups/g1/notes"), { kind: "group-notes", groupId: "g1" });
    assert.deepEqual(matchNativeV1Route("groups/g1/notes/n1"), {
      kind: "group-notes",
      groupId: "g1",
      noteId: "n1",
    });
    assert.deepEqual(matchNativeV1Route("notes/n1/groups"), { kind: "note-groups", noteId: "n1" });
  });

  it("rejects unknown paths", () => {
    assert.equal(matchNativeV1Route("plans").kind, "not-found");
    assert.equal(matchNativeV1Route("notes/a/b").kind, "not-found");
    assert.equal(matchNativeV1Route("auth/other").kind, "not-found");
  });
});

describe("methodAllowed", () => {
  it("allows GET session and CRUD notes", () => {
    assert.equal(methodAllowed({ kind: "session" }, "GET"), true);
    assert.equal(methodAllowed({ kind: "session" }, "POST"), false);
    assert.equal(methodAllowed({ kind: "notes" }, "GET"), true);
    assert.equal(methodAllowed({ kind: "notes" }, "POST"), true);
    assert.equal(methodAllowed({ kind: "notes", noteId: "x" }, "PATCH"), true);
    assert.equal(methodAllowed({ kind: "notes", noteId: "x" }, "DELETE"), true);
    assert.equal(methodAllowed({ kind: "notes", noteId: "x" }, "POST"), false);
  });

  it("allows auth POSTs and GET providers", () => {
    assert.equal(methodAllowed({ kind: "auth-providers" }, "GET"), true);
    assert.equal(methodAllowed({ kind: "auth-claim" }, "POST"), true);
    assert.equal(methodAllowed({ kind: "auth-email" }, "POST"), true);
    assert.equal(methodAllowed({ kind: "auth-apple" }, "POST"), true);
    assert.equal(methodAllowed({ kind: "auth-from-cookie" }, "POST"), true);
    assert.equal(methodAllowed({ kind: "auth-sign-out" }, "POST"), true);
    assert.equal(methodAllowed({ kind: "auth-claim" }, "GET"), false);
  });

  it("allows OPTIONS everywhere matched", () => {
    assert.equal(methodAllowed({ kind: "catalog" }, "OPTIONS"), true);
    assert.equal(methodAllowed({ kind: "devices-apns" }, "OPTIONS"), true);
    assert.equal(methodAllowed({ kind: "auth-email" }, "OPTIONS"), true);
  });

  it("allows groups CRUD and note publish", () => {
    assert.equal(methodAllowed({ kind: "groups" }, "GET"), true);
    assert.equal(methodAllowed({ kind: "groups" }, "POST"), true);
    assert.equal(methodAllowed({ kind: "groups", groupId: "g" }, "PATCH"), true);
    assert.equal(methodAllowed({ kind: "groups", groupId: "g" }, "DELETE"), true);
    assert.equal(methodAllowed({ kind: "group-notes", groupId: "g" }, "GET"), true);
    assert.equal(methodAllowed({ kind: "group-notes", groupId: "g" }, "POST"), true);
    assert.equal(methodAllowed({ kind: "group-notes", groupId: "g", noteId: "n" }, "DELETE"), true);
    assert.equal(methodAllowed({ kind: "note-groups", noteId: "n" }, "GET"), true);
  });
});

describe("isPublicNativeAuthRoute", () => {
  it("marks sign-in routes public and notes private", () => {
    assert.equal(isPublicNativeAuthRoute({ kind: "auth-claim" }), true);
    assert.equal(isPublicNativeAuthRoute({ kind: "auth-email" }), true);
    assert.equal(isPublicNativeAuthRoute({ kind: "catalog" }), true);
    assert.equal(isPublicNativeAuthRoute({ kind: "notes" }), false);
    assert.equal(isPublicNativeAuthRoute({ kind: "auth-sign-out" }), false);
  });
});
