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
    const http = read("src/lib/native/api/v1-http.ts");
    assert.match(http, /v1-groups\.server/);
    assert.match(http, /group-notes/);
    assert.match(http, /note-groups/);
    const catalog = read("src/lib/native/api/v1.server.ts");
    assert.match(catalog, /\/groups/);
    assert.match(catalog, /\/notes\/:id\/groups/);
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
