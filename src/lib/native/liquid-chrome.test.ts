import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { describe, it } from "node:test";
import { chromeVisibility, readTrailing, suspensionFromDom } from "./liquid-chrome.ts";
import { selectedTabId, showTabBar } from "../tabs.ts";

describe("selectedTabId", () => {
  it("highlights the five root tabs and the screens that belong to them", () => {
    assert.equal(selectedTabId("/app"), "verses");
    assert.equal(selectedTabId("/collections"), "verses");
    assert.equal(selectedTabId("/c/abc"), "verses");
    assert.equal(selectedTabId("/groups"), "groups");
    assert.equal(selectedTabId("/groups/abc"), "groups");
    assert.equal(selectedTabId("/notebook/g/abc"), "groups");
    assert.equal(selectedTabId("/notebook"), "notebook");
    assert.equal(selectedTabId("/reading"), "reading");
    assert.equal(selectedTabId("/reading/gospels-30"), "reading");
    assert.equal(selectedTabId("/g/invite"), "reading");
    assert.equal(selectedTabId("/profile"), "profile");
    assert.equal(selectedTabId("/profile/theme"), "profile");
  });

  it("hides the bar on a note, the same way the HTML bar does", () => {
    assert.equal(showTabBar("/notebook/note-1"), false);
    assert.equal(selectedTabId("/notebook/note-1"), null);
    assert.equal(selectedTabId("/n/note-1"), null);
    assert.equal(selectedTabId("/"), null);
    assert.equal(selectedTabId("/login"), null);
  });
});

describe("chromeVisibility", () => {
  const base = { active: true, suspension: "none" as const, hasTabBar: true, hasHeader: true, hasFab: true, keyboard: false };

  it("keeps the HTML chrome when the native plugin is absent", () => {
    assert.deepEqual(chromeVisibility({ ...base, active: false }), {
      tabs: false,
      top: false,
      fab: false,
      keyboard: false,
    });
  });

  it("drops the tab bar and the FAB while a sheet is open, and everything during the tour", () => {
    assert.equal(chromeVisibility({ ...base, suspension: "tabs" }).tabs, false);
    assert.equal(chromeVisibility({ ...base, suspension: "tabs" }).fab, false);
    assert.equal(chromeVisibility({ ...base, suspension: "tabs" }).top, true);
    assert.deepEqual(chromeVisibility({ ...base, suspension: "all" }), {
      tabs: false,
      top: false,
      fab: false,
      keyboard: false,
    });
  });

  it("hides the FAB while the keyboard is up but still reserves the tab inset", () => {
    const next = chromeVisibility({ ...base, keyboard: true });
    assert.equal(next.fab, false);
    assert.equal(next.tabs, true);
    assert.equal(next.keyboard, true);
  });
});

describe("suspensionFromDom", () => {
  it("reads the sheet and the tour markers", () => {
    const root = documentStub([
      { attrs: { "data-native-chrome": "tabs", role: "dialog" } },
    ]);
    assert.equal(suspensionFromDom(root), "tabs");
    const tour = documentStub([{ attrs: { "data-native-chrome": "all", role: "dialog" } }]);
    assert.equal(suspensionFromDom(tour), "all");
    assert.equal(suspensionFromDom(documentStub([])), "none");
  });
});

describe("native underlap (website CSS; Cap LiquidChrome removed in Phase 5)", () => {
  const css = readFileSync(new URL("../../styles.css", import.meta.url), "utf8");

  it("does not reserve a solid header band behind the native top bar", () => {
    assert.doesNotMatch(css, /height:\s*var\(--native-top-inset\)/);
    assert.match(css, /html\.native-ios\.native-top main\.screen > \.screen-body > \.screen-content/);
    assert.match(css, /padding-top:\s*max\(0px, calc\(var\(--native-top-inset, 0px\) \+ var\(--native-title-gap, 12px\)\)\)/);
    assert.match(css, /html\.native-ios\.native-top::before/);
    assert.match(css, /-webkit-backdrop-filter:\s*saturate\(180%\) blur\(22px\)/);
    assert.match(css, /html\.native-ios\.native-top main\.note-screen > \.note-chrome/);
    assert.match(css, /html\.native-ios\.native-top main\.note-screen > \.screen-body/);
  });

  it("Phase 5: LiquidChrome.swift is gone from the iOS target", () => {
    const pbx = readFileSync(new URL("../../../ios/App/Katecheo.xcodeproj/project.pbxproj", import.meta.url), "utf8");
    assert.doesNotMatch(pbx, /LiquidChrome\.swift/);
  });
});

describe("readTrailing", () => {
  it("ignores a symbol when the web control is not in the header", () => {
    const root = documentStub([]);
    assert.deepEqual(readTrailing(root, "bell"), { visible: false, label: "", badge: "" });
    assert.deepEqual(readTrailing(root, null), { visible: false, label: "", badge: "" });
  });
});

function documentStub(nodes: { attrs: Record<string, string> }[]): ParentNode {
  return {
    querySelector(selector: string) {
      for (const node of nodes) {
        if (selector.includes('data-native-chrome="all"') && node.attrs["data-native-chrome"] === "all") return element(node.attrs);
        if (selector.includes('data-native-chrome="tabs"') && node.attrs["data-native-chrome"] === "tabs") return element(node.attrs);
        if (selector.includes('role="dialog"') && node.attrs.role === "dialog") return element(node.attrs);
        if (selector === "[data-native-trailing]" && node.attrs["data-native-trailing"] != null) return element(node.attrs);
      }
      return null;
    },
  } as ParentNode;
}

function element(attrs: Record<string, string>): Element {
  return {
    getAttribute: (name: string) => attrs[name] ?? null,
    querySelector: () => null,
  } as unknown as Element;
}
