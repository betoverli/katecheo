import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { describe, it } from "node:test";

const root = new URL("../../../", import.meta.url);

function read(rel: string) {
  return readFileSync(new URL(rel, root), "utf8");
}

describe("Phase 1 native notebook shell (updated Phase 5)", () => {
  it("uses nativePrimary shell (Cap site host removed)", () => {
    const mode = read("ios/App/Katecheo/NativeShellMode.swift");
    assert.match(mode, /return \.nativePrimary/);
    assert.match(mode, /case nativePrimary/);
  });

  it("SceneDelegate roots through AppRoot (native tabs)", () => {
    const scene = read("ios/App/Katecheo/SceneDelegate.swift");
    assert.match(scene, /AppRoot\.makeRootViewController/);
  });

  it("ships native list + note chrome + native editor", () => {
    for (const file of [
      "ios/App/Katecheo/NotebookListViewController.swift",
      "ios/App/Katecheo/NoteDetailViewController.swift",
      "ios/App/Katecheo/NoteSettingsViewController.swift",
      "ios/App/Katecheo/SpeakerPickerViewController.swift",
      "ios/App/Katecheo/NativeRootTabBarController.swift",
      "ios/App/Katecheo/LocalNoteCache.swift",
      "ios/App/Katecheo/NativeNoteEditorView.swift",
      "ios/App/Katecheo/NoteDocumentCodec.swift",
    ]) {
      const body = read(file);
      assert.ok(body.length > 100, file);
    }
    const list = read("ios/App/Katecheo/NotebookListViewController.swift");
    assert.match(list, /trailingSwipeActionsConfigurationForRowAt/);
    assert.match(list, /leadingSwipeActionsConfigurationForRowAt/);
    assert.match(list, /UISearchResultsUpdating/);
    assert.match(list, /UIActivityViewController/);
    assert.doesNotMatch(list, /Site clássico|capacitorSite/);
    const detail = read("ios/App/Katecheo/NoteDetailViewController.swift");
    assert.match(detail, /NativeNoteEditorView/);
    assert.match(detail, /NoteDocument/);
    const editor = read("ios/App/Katecheo/NativeNoteEditorView.swift");
    assert.match(editor, /UITextView/);
    assert.doesNotMatch(editor, /WKWebView/);
  });

  it("does not offer Capacitor classic fallback", () => {
    const coming = read("ios/App/Katecheo/ComingSoonTabViewController.swift");
    assert.doesNotMatch(coming, /capacitorSite|Usar app clássico/);
  });

  it("Xcode project includes Phase 1 sources", () => {
    const project = read("ios/App/Katecheo.xcodeproj/project.pbxproj");
    for (const name of [
      "NotebookListViewController.swift in Sources",
      "NoteDetailViewController.swift in Sources",
      "NativeNoteEditorView.swift in Sources",
      "NoteDocumentCodec.swift in Sources",
      "AppRoot.swift in Sources",
      "NativeRootTabBarController.swift in Sources",
    ]) {
      assert.match(project, new RegExp(name.replace(/\./g, "\\.")));
    }
  });
});
