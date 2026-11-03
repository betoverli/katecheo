import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { describe, it } from "node:test";

const root = new URL("../../../", import.meta.url);

function read(rel: string) {
  return readFileSync(new URL(rel, root), "utf8");
}

describe("Phase 1 native notebook shell (updated Phase 5)", () => {
  it("uses nativePrimary shell (Cap site host removed)", () => {
    const mode = read("ios/App/App/NativeShellMode.swift");
    assert.match(mode, /return \.nativePrimary/);
    assert.match(mode, /case nativePrimary/);
  });

  it("SceneDelegate roots through AppRoot (native tabs)", () => {
    const scene = read("ios/App/App/SceneDelegate.swift");
    assert.match(scene, /AppRoot\.makeRootViewController/);
  });

  it("ships native list + note chrome + isolated miolo", () => {
    for (const file of [
      "ios/App/App/NotebookListViewController.swift",
      "ios/App/App/NoteDetailViewController.swift",
      "ios/App/App/NoteSettingsViewController.swift",
      "ios/App/App/SpeakerPickerViewController.swift",
      "ios/App/App/NativeRootTabBarController.swift",
      "ios/App/App/LocalNoteCache.swift",
      "ios/App/App/NoteMioloEditorView.swift",
    ]) {
      const body = read(file);
      assert.ok(body.length > 100, file);
    }
    const list = read("ios/App/App/NotebookListViewController.swift");
    assert.match(list, /trailingSwipeActionsConfigurationForRowAt/);
    assert.match(list, /leadingSwipeActionsConfigurationForRowAt/);
    assert.match(list, /UISearchResultsUpdating/);
    assert.match(list, /UIActivityViewController/);
    assert.doesNotMatch(list, /Site clássico|capacitorSite/);
    const detail = read("ios/App/App/NoteDetailViewController.swift");
    assert.match(detail, /NoteMioloEditorView/);
    assert.match(detail, /NoteDocument/);
    const miolo = read("ios/App/App/NoteMioloEditorView.swift");
    assert.match(miolo, /WKScriptMessageHandler/);
    assert.match(miolo, /native-editor/);
  });

  it("does not offer Capacitor classic fallback", () => {
    const coming = read("ios/App/App/ComingSoonTabViewController.swift");
    assert.doesNotMatch(coming, /capacitorSite|Usar app clássico/);
  });

  it("Xcode project includes Phase 1 sources", () => {
    const project = read("ios/App/App.xcodeproj/project.pbxproj");
    for (const name of [
      "NotebookListViewController.swift in Sources",
      "NoteDetailViewController.swift in Sources",
      "NoteMioloEditorView.swift in Sources",
      "AppRoot.swift in Sources",
      "NativeRootTabBarController.swift in Sources",
    ]) {
      assert.match(project, new RegExp(name.replace(/\./g, "\\.")));
    }
  });
});
