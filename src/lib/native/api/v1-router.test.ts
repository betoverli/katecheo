import assert from "node:assert/strict";
import { describe, it } from "node:test";
import { isPublicNativeAuthRoute, matchNativeV1Route, methodAllowed } from "./v1-router.ts";

describe("matchNativeV1Route", () => {
  it("maps the catalog and session", () => {
    assert.deepEqual(matchNativeV1Route(""), { kind: "catalog" });
    assert.deepEqual(matchNativeV1Route("/"), { kind: "catalog" });
    assert.deepEqual(matchNativeV1Route("session"), { kind: "session" });
  });

  it("maps notes collection, granted, and item", () => {
    assert.deepEqual(matchNativeV1Route("notes"), { kind: "notes" });
    assert.deepEqual(matchNativeV1Route("notes/granted"), { kind: "notes-granted" });
    assert.deepEqual(matchNativeV1Route("notes/abc123"), { kind: "notes", noteId: "abc123" });
  });

  it("maps links and notifications inbox", () => {
    assert.deepEqual(matchNativeV1Route("links"), { kind: "links" });
    assert.deepEqual(matchNativeV1Route("links/accept"), { kind: "links-accept" });
    assert.deepEqual(matchNativeV1Route("links/decline"), { kind: "links-decline" });
    assert.deepEqual(matchNativeV1Route("notifications"), { kind: "notifications" });
    assert.deepEqual(matchNativeV1Route("notifications/read"), { kind: "notifications-read" });
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

  it("maps groups collection, item, notes, and members", () => {
    assert.deepEqual(matchNativeV1Route("groups"), { kind: "groups" });
    assert.deepEqual(matchNativeV1Route("groups/g1"), { kind: "groups", groupId: "g1" });
    assert.deepEqual(matchNativeV1Route("groups/g1/notes"), { kind: "group-notes", groupId: "g1" });
    assert.deepEqual(matchNativeV1Route("groups/g1/notes/n1"), {
      kind: "group-notes",
      groupId: "g1",
      noteId: "n1",
    });
    assert.deepEqual(matchNativeV1Route("groups/g1/members"), { kind: "group-members", groupId: "g1" });
    assert.deepEqual(matchNativeV1Route("groups/g1/members/decide"), {
      kind: "group-members-decide",
      groupId: "g1",
    });
    assert.deepEqual(matchNativeV1Route("groups/g1/members/role"), {
      kind: "group-members-role",
      groupId: "g1",
    });
    assert.deepEqual(matchNativeV1Route("groups/g1/members/u1"), {
      kind: "group-members",
      groupId: "g1",
      userId: "u1",
    });
    assert.deepEqual(matchNativeV1Route("notes/n1/groups"), { kind: "note-groups", noteId: "n1" });
  });

  it("maps profile, prefs, and account endpoints", () => {
    assert.deepEqual(matchNativeV1Route("me"), { kind: "me" });
    assert.deepEqual(matchNativeV1Route("prefs"), { kind: "prefs" });
    assert.deepEqual(matchNativeV1Route("notify-prefs"), { kind: "notify-prefs" });
    assert.deepEqual(matchNativeV1Route("account/export"), { kind: "account-export" });
    assert.deepEqual(matchNativeV1Route("account/delete"), { kind: "account-delete" });
  });

  it("maps bible catalog, append, and my-collections", () => {
    assert.deepEqual(matchNativeV1Route("bible/books"), { kind: "bible-books" });
    assert.deepEqual(matchNativeV1Route("bible/apps"), { kind: "bible-apps" });
    assert.deepEqual(matchNativeV1Route("bible/link"), { kind: "bible-link" });
    assert.deepEqual(matchNativeV1Route("bible/themes"), { kind: "bible-themes" });
    assert.deepEqual(matchNativeV1Route("verses/append"), { kind: "verses-append" });
    assert.deepEqual(matchNativeV1Route("my-collections"), { kind: "my-collections" });
    assert.deepEqual(matchNativeV1Route("my-collections/save"), { kind: "my-collections-save" });
    assert.deepEqual(matchNativeV1Route("my-collections/c1"), {
      kind: "my-collections",
      collectionId: "c1",
    });
  });

  it("maps reading plans endpoints", () => {
    assert.deepEqual(matchNativeV1Route("plans"), { kind: "plans" });
    assert.deepEqual(matchNativeV1Route("plans/mark"), { kind: "plans-mark" });
    assert.deepEqual(matchNativeV1Route("plans/reset"), { kind: "plans-reset" });
    assert.deepEqual(matchNativeV1Route("plans/start"), { kind: "plans-start" });
    assert.deepEqual(matchNativeV1Route("plans/stop"), { kind: "plans-stop" });
    assert.deepEqual(matchNativeV1Route("plans/invite"), { kind: "plans-invite" });
    assert.deepEqual(matchNativeV1Route("plans/join"), { kind: "plans-join" });
    assert.deepEqual(matchNativeV1Route("plans/groups/g1"), { kind: "plans-group", groupId: "g1" });
  });

  it("rejects unknown paths", () => {
    assert.equal(matchNativeV1Route("plans/other").kind, "not-found");
    assert.equal(matchNativeV1Route("notes/a/b").kind, "not-found");
    assert.equal(matchNativeV1Route("auth/other").kind, "not-found");
    assert.equal(matchNativeV1Route("account").kind, "not-found");
    assert.equal(matchNativeV1Route("bible").kind, "not-found");
    assert.equal(matchNativeV1Route("links/other").kind, "not-found");
    assert.equal(matchNativeV1Route("notifications/other").kind, "not-found");
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
    assert.equal(methodAllowed({ kind: "notes-granted" }, "GET"), true);
    assert.equal(methodAllowed({ kind: "notes-granted" }, "POST"), false);
    assert.equal(methodAllowed({ kind: "links" }, "GET"), true);
    assert.equal(methodAllowed({ kind: "links-accept" }, "POST"), true);
    assert.equal(methodAllowed({ kind: "links-decline" }, "POST"), true);
    assert.equal(methodAllowed({ kind: "notifications" }, "GET"), true);
    assert.equal(methodAllowed({ kind: "notifications-read" }, "POST"), true);
    assert.equal(methodAllowed({ kind: "notifications-read" }, "GET"), false);
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

  it("allows profile prefs and account delete", () => {
    assert.equal(methodAllowed({ kind: "me" }, "GET"), true);
    assert.equal(methodAllowed({ kind: "me" }, "PATCH"), true);
    assert.equal(methodAllowed({ kind: "prefs" }, "GET"), true);
    assert.equal(methodAllowed({ kind: "prefs" }, "PATCH"), true);
    assert.equal(methodAllowed({ kind: "notify-prefs" }, "POST"), true);
    assert.equal(methodAllowed({ kind: "account-export" }, "GET"), true);
    assert.equal(methodAllowed({ kind: "account-delete" }, "POST"), true);
    assert.equal(methodAllowed({ kind: "account-delete" }, "DELETE"), true);
    assert.equal(methodAllowed({ kind: "me" }, "DELETE"), false);
  });

  it("allows bible GET and verses append POST", () => {
    assert.equal(methodAllowed({ kind: "bible-books" }, "GET"), true);
    assert.equal(methodAllowed({ kind: "bible-link" }, "POST"), true);
    assert.equal(methodAllowed({ kind: "bible-themes" }, "GET"), true);
    assert.equal(methodAllowed({ kind: "verses-append" }, "POST"), true);
    assert.equal(methodAllowed({ kind: "my-collections-save" }, "POST"), true);
    assert.equal(methodAllowed({ kind: "my-collections" }, "POST"), true);
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

  it("marks bible catalog and plans index public", () => {
    assert.equal(isPublicNativeAuthRoute({ kind: "plans" }), true);
    assert.equal(isPublicNativeAuthRoute({ kind: "plans-mark" }), false);
    assert.equal(isPublicNativeAuthRoute({ kind: "bible-books" }), true);
    assert.equal(isPublicNativeAuthRoute({ kind: "bible-themes" }), true);
    assert.equal(isPublicNativeAuthRoute({ kind: "verses-append" }), false);
    assert.equal(isPublicNativeAuthRoute({ kind: "my-collections" }), false);
  });
});
