import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { describe, it } from "node:test";
import { matchNativeV1Route, methodAllowed } from "./api/v1-router.ts";

const root = new URL("../../../", import.meta.url);

function read(rel: string) {
  return readFileSync(new URL(rel, root), "utf8");
}

describe("Phase 2 native groups API", () => {
  it("routes groups CRUD and note publish/unpublish", () => {
    assert.deepEqual(matchNativeV1Route("groups"), { kind: "groups" });
    assert.deepEqual(matchNativeV1Route("groups/abc"), { kind: "groups", groupId: "abc" });
    assert.deepEqual(matchNativeV1Route("groups/abc/notes"), { kind: "group-notes", groupId: "abc" });
    assert.deepEqual(matchNativeV1Route("groups/abc/notes/n1"), {
      kind: "group-notes",
      groupId: "abc",
      noteId: "n1",
    });
    assert.deepEqual(matchNativeV1Route("notes/n1/groups"), { kind: "note-groups", noteId: "n1" });
    assert.equal(methodAllowed({ kind: "groups" }, "POST"), true);
    assert.equal(methodAllowed({ kind: "groups", groupId: "g" }, "DELETE"), true);
    assert.equal(methodAllowed({ kind: "group-notes", groupId: "g" }, "POST"), true);
  });

  it("ships groups server + HTTP dispatch", () => {
    const groups = read("src/lib/native/api/v1-groups.server.ts");
    assert.match(groups, /listGroupsForUser/);
    assert.match(groups, /createGroupForUser/);
    assert.match(groups, /updateGroupForUser/);
    assert.match(groups, /deleteGroupForUser/);
    assert.match(groups, /listNotesInGroupForUser/);
    assert.match(groups, /publishNoteIdToGroup/);
    assert.match(groups, /listGroupsForNote/);
    assert.match(groups, /createGroupInvitesForUser/);
    assert.match(groups, /respondGroupInviteForUser/);
    assert.match(groups, /listGroupInviteFriendsForUser/);
    const http = read("src/lib/native/api/v1-http.ts");
    assert.match(http, /v1-groups\.server/);
    assert.match(http, /group-notes/);
    assert.match(http, /note-groups/);
    assert.match(http, /group-invite/);
    const catalog = read("src/lib/native/api/v1.server.ts");
    assert.match(catalog, /\/groups/);
    assert.match(catalog, /\/notes\/:id\/groups/);
    assert.match(catalog, /\/groups\/:id\/invites/);
    assert.match(catalog, /\/groups\/invites/);
  });

  it("ships friend-invite UI + deep link for push taps", () => {
    const members = read("ios/App/Katecheo/GroupMembersViewController.swift");
    assert.match(members, /Convidar amigos/);
    assert.match(members, /GroupInviteFriendsViewController/);
    const notebook = read("ios/App/Katecheo/NotebookListViewController.swift");
    assert.match(notebook, /openInviteFriends|GroupInviteFriendsViewController/);
    const router = read("ios/App/Katecheo/NativeDeepLinkRouter.swift");
    assert.match(router, /groupInvite/);
    assert.match(router, /groups\/invite/);
    const detail = read("ios/App/Katecheo/GroupInviteDetailViewController.swift");
    assert.match(detail, /respondGroupInvite/);
    const migration = read("migrations/0030_notebook_group_invites.sql");
    assert.match(migration, /notebook_group_invites/);
  });
});

describe("Phase 2 native Groups UI", () => {
  it("replaces Grupos Em breve with GroupsListViewController", () => {
    const tabs = read("ios/App/Katecheo/NativeRootTabBarController.swift");
    assert.match(tabs, /GroupsListViewController/);
    assert.doesNotMatch(tabs, /titleText:\s*"Grupos"/);
    const list = read("ios/App/Katecheo/GroupsListViewController.swift");
    assert.match(list, /Novo grupo/);
    assert.match(list, /createGroup/);
    assert.match(list, /confirmDelete/);
    assert.match(list, /promptRename|Renomear/);
    assert.match(list, /NotebookListViewController\(group:/);
  });

  it("reuses Caderno list for group notes + rename/delete", () => {
    const notebook = read("ios/App/Katecheo/NotebookListViewController.swift");
    assert.match(notebook, /convenience init\(group:/);
    assert.match(notebook, /listGroupNotes/);
    assert.match(notebook, /Renomear grupo/);
    assert.match(notebook, /Excluir grupo|Apagar grupo/);
    assert.match(notebook, /publishNote/);
    assert.match(notebook, /LocalGroupNotesCache/);
  });

  it("caches group notes on device with conditional GET support", () => {
    const cache = read("ios/App/Katecheo/LocalGroupNotesCache.swift");
    assert.match(cache, /clearAll/);
    assert.match(cache, /userId/);
    assert.match(cache, /groupId/);
    const client = read("ios/App/Katecheo/NativeAPIClient.swift");
    assert.match(client, /If-None-Match/);
    assert.match(client, /updatedSince/);
    assert.match(client, /mergeGroupNotes/);
    const groups = read("src/lib/native/api/v1-groups.server.ts");
    assert.match(groups, /groupNotesEtag|updatedSince/);
    assert.match(read("src/lib/native/api/group-notes-etag.ts"), /groupNotesEtag/);
    assert.match(groups, /updatedSince/);
    const http = read("src/lib/native/api/v1-http.ts");
    assert.match(http, /if-none-match/i);
    assert.match(http, /304/);
  });

  it("moves a note to a group from the note ⋯ menu", () => {
    const detail = read("ios/App/Katecheo/NoteDetailViewController.swift");
    assert.match(detail, /Mover para grupo/);
    assert.match(detail, /listGroupsForNote/);
    assert.match(detail, /publishNote/);
    const client = read("ios/App/Katecheo/NativeAPIClient.swift");
    assert.match(client, /func listGroups\(/);
    assert.match(client, /func createGroup\(/);
    assert.match(client, /func publishNote\(/);
    assert.match(client, /notes\/\\\(noteId\)\/groups/);
  });

  it("registers GroupsListViewController in the Xcode target", () => {
    const project = read("ios/App/Katecheo.xcodeproj/project.pbxproj");
    assert.match(project, /GroupsListViewController\.swift in Sources/);
  });

  it("keeps WebKit session bootstrap on the main actor", () => {
    const boot = read("ios/App/Katecheo/NativeSessionBootstrap.swift");
    assert.match(boot, /@MainActor/);
    assert.match(boot, /Thread\.isMainThread/);
    assert.match(boot, /WKWebsiteDataStore/);
  });
});
