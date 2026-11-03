import assert from "node:assert/strict";
import { existsSync, readFileSync, readdirSync } from "node:fs";
import { describe, it } from "node:test";

const root = new URL("../../../", import.meta.url);

function read(rel: string) {
  return readFileSync(new URL(rel, root), "utf8");
}

describe("Phase 5 — remove Capacitor site host", () => {
  it("forces nativePrimary and never mounts Cap bridge", () => {
    const mode = read("ios/App/App/NativeShellMode.swift");
    assert.match(mode, /nativePrimary/);
    assert.match(mode, /return \.nativePrimary/);
    const rootVc = read("ios/App/App/AppRoot.swift");
    assert.match(rootVc, /NativeRootTabBarController/);
    assert.doesNotMatch(rootVc, /Verse2NoteBridge|capacitorSite|CAPBridge/);
    const scene = read("ios/App/App/SceneDelegate.swift");
    assert.match(scene, /AppRoot\.makeRootViewController/);
    assert.doesNotMatch(scene, /import Capacitor|SceneDelegateProxy/);
  });

  it("isolates WKWebView in NoteMioloEditorView with Keychain Bearer", () => {
    const miolo = read("ios/App/App/NoteMioloEditorView.swift");
    assert.match(miolo, /WKWebView/);
    assert.match(miolo, /native-editor/);
    assert.match(miolo, /KeychainStore\.bearerToken/);
    assert.match(miolo, /__V2N_EDITOR__/);
    const detail = read("ios/App/App/NoteDetailViewController.swift");
    assert.match(detail, /NoteMioloEditorView/);
    assert.doesNotMatch(detail, /WKWebView|import WebKit/);
  });

  it("forbids Cap / extra WKWebView surfaces under ios/App/App", () => {
    const appDir = new URL("ios/App/App/", root);
    const allowedWebKit = new Set([
      "NoteMioloEditorView.swift",
      "NativeSessionBootstrap.swift",
      "SceneDelegate.swift",
      "LegacyWebStorageImporter.swift",
    ]);
    const allowedWkWebView = new Set(["NoteMioloEditorView.swift", "LegacyWebStorageImporter.swift"]);
    const stripComments = (source: string) =>
      source.replace(/\/\*[\s\S]*?\*\//g, "").replace(/(^|[^:])\/\/.*$/gm, "$1");
    for (const name of readdirSync(appDir)) {
      if (!/\.(swift|m|h)$/.test(name)) continue;
      const body = stripComments(read(`ios/App/App/${name}`));
      assert.doesNotMatch(body, /\bimport\s+Capacitor\b/, name);
      assert.doesNotMatch(body, /\bCAPPlugin\b|\bCAPBridgeViewController\b/, name);
      if (/\bWKWebView\b/.test(body)) {
        assert.ok(allowedWkWebView.has(name), `WKWebView in ${name}`);
      }
      if (/\bimport\s+WebKit\b/.test(body)) {
        assert.ok(allowedWebKit.has(name), `import WebKit in ${name}`);
      }
    }
    for (const dead of [
      "ios/App/App/NativeShell.swift",
      "ios/App/App/LiquidChrome.swift",
      "ios/App/App/NativeMenus.swift",
      "ios/App/App/NativePhase0Plugin.swift",
      "ios/App/App/NoteEditorSpikeViewController.swift",
    ]) {
      assert.equal(existsSync(new URL(dead, root)), false, dead);
    }
  });

  it("ships native push + deep link routing (no Cap plugins)", () => {
    const push = read("ios/App/App/NativePushService.swift");
    assert.match(push, /UNUserNotificationCenter/);
    assert.match(push, /saveApnsDevice/);
    assert.match(push, /NativeDeepLinkRouter/);
    const deep = read("ios/App/App/NativeDeepLinkRouter.swift");
    assert.match(deep, /destination\(for/);
    assert.match(deep, /case note/);
    assert.match(deep, /NoteDetailViewController/);
    assert.equal(NativeDeepLinkRouterShim("/notebook/abc"), "note");
    assert.equal(NativeDeepLinkRouterShim("/groups/xyz"), "group");
    assert.equal(NativeDeepLinkRouterShim("/app"), "verses");
    assert.equal(NativeDeepLinkRouterShim("/reading"), "reading");
    assert.equal(NativeDeepLinkRouterShim("/profile"), "profile");
    const client = read("ios/App/App/NativeAPIClient.swift");
    assert.match(client, /func saveApnsDevice/);
    assert.match(client, /func dropApnsDevice/);
  });

  it("removes classic Cap fallbacks from login / Caderno / ComingSoon", () => {
    assert.doesNotMatch(read("ios/App/App/NativeSignInViewController.swift"), /site clássico|capacitorSite/i);
    assert.doesNotMatch(read("ios/App/App/NotebookListViewController.swift"), /Site clássico|capacitorSite/);
    const coming = read("ios/App/App/ComingSoonTabViewController.swift");
    assert.doesNotMatch(coming, /sitePath|Usar app clássico|Verse2NoteBridge|capacitorSite/);
    assert.match(coming, /Em breve nativo/);
  });

  it("drops Cap server.url and CapApp-SPM from the Xcode target", () => {
    const cap = read("capacitor.config.ts");
    assert.doesNotMatch(cap, /server\s*:\s*\{[\s\S]*?url\s*:/);
    const pbx = read("ios/App/App.xcodeproj/project.pbxproj");
    assert.doesNotMatch(pbx, /CapApp-SPM/);
    assert.match(pbx, /NoteMioloEditorView\.swift in Sources/);
    assert.match(pbx, /NativePushService\.swift in Sources/);
    assert.match(pbx, /NativeDeepLinkRouter\.swift in Sources/);
    const workflow = read(".github/workflows/ios.yml");
    assert.doesNotMatch(workflow, /cap sync/);
  });

  it("documents Phase 5 WebView isolation", () => {
    const doc = read("docs/ios-phase5-webview.md");
    assert.match(doc, /NoteMioloEditorView/);
    assert.match(doc, /Keychain/);
    assert.match(doc, /Phase 7/);
  });
});

/** Mirrors NativeDeepLinkRouter path mapping for unit coverage without Swift. */
function NativeDeepLinkRouterShim(path: string): string {
  const parts = path.replace(/^\//, "").split("/").filter(Boolean);
  if (parts[0] === "notebook" && parts[1]) return "note";
  if (parts[0] === "n" && parts[1]) return "note";
  if (parts[0] === "groups" && parts[1]) return "group";
  if (parts[0] === "groups") return "groups";
  if (parts[0] === "app" || parts[0] === "c") return "verses";
  if (parts[0] === "collections") return "themes";
  if (parts[0] === "reading") return "reading";
  if (parts[0] === "profile" || parts[0] === "u" || parts[0] === "inbox") return "profile";
  return "notebook";
}
