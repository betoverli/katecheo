import assert from "node:assert/strict";
import { describe, it } from "node:test";
import { readFileSync } from "node:fs";
import {
  classifyPresentOutcome,
  FORCE_WEB_FALLBACK_MS,
  PRESENTATION_CONFIRM_MS,
  rectFromElement,
  rectFromPoint,
} from "./menus.ts";

describe("rectFromElement", () => {
  it("falls back to a centered 44pt target without an element", () => {
    const rect = rectFromElement(null);
    assert.equal(rect.width, 44);
    assert.equal(rect.height, 44);
  });

  it("reads getBoundingClientRect when present", () => {
    const el = {
      getBoundingClientRect() {
        return { left: 10, top: 20, width: 100, height: 40 };
      },
    };
    assert.deepEqual(rectFromElement(el as Element), { x: 10, y: 20, width: 100, height: 40 });
  });
});

describe("rectFromPoint", () => {
  it("centers a hit target on the point", () => {
    assert.deepEqual(rectFromPoint(100, 200, 40), { x: 80, y: 180, width: 40, height: 40 });
  });
});

describe("classifyPresentOutcome (web fallback logic)", () => {
  it("marks plugin errors as failed so callers open the web sheet", () => {
    assert.deepEqual(classifyPresentOutcome({ presented: false, error: new Error("hang") }), {
      id: null,
      cancelled: true,
      failed: true,
    });
  });

  it("marks replaced / missing results as failed", () => {
    assert.equal(classifyPresentOutcome({ presented: true, result: { id: null, cancelled: true, replaced: true } }).failed, true);
    assert.equal(classifyPresentOutcome({ presented: false }).failed, true);
  });

  it("treats cancel without a confirmed presentation as failed (phantom cancel)", () => {
    const outcome = classifyPresentOutcome({
      presented: false,
      result: { id: null, cancelled: true },
    });
    assert.equal(outcome.failed, true);
    assert.equal(outcome.cancelled, true);
  });

  it("keeps a real user cancel after presentation (no failed → no web flash)", () => {
    const outcome = classifyPresentOutcome({
      presented: true,
      result: { id: null, cancelled: true },
    });
    assert.equal(outcome.failed, undefined);
    assert.equal(outcome.cancelled, true);
  });

  it("returns the selected id when presentation succeeded", () => {
    assert.deepEqual(
      classifyPresentOutcome({
        presented: true,
        result: { id: "action-0", cancelled: false },
      }),
      { id: "action-0", cancelled: false, value: undefined },
    );
  });

  it("keeps the force-web budget just above the presentation confirm budget", () => {
    assert.ok(FORCE_WEB_FALLBACK_MS > PRESENTATION_CONFIRM_MS);
    assert.ok(FORCE_WEB_FALLBACK_MS <= PRESENTATION_CONFIRM_MS + 500);
  });
});

describe("native menus wiring (Phase 5: Cap plugins removed from iOS)", () => {
  const storyboard = readFileSync(new URL("../../../ios/App/Katecheo/Base.lproj/Main.storyboard", import.meta.url), "utf8");
  const pbx = readFileSync(new URL("../../../ios/App/Katecheo.xcodeproj/project.pbxproj", import.meta.url), "utf8");
  const wrapper = readFileSync(new URL("./menus.ts", import.meta.url), "utf8");

  it("drops NativeMenus / Cap bridge from the iOS target", () => {
    assert.doesNotMatch(pbx, /NativeMenus\.swift/);
    assert.doesNotMatch(pbx, /NativeShell\.swift/);
    assert.doesNotMatch(pbx, /CapApp-SPM/);
    assert.match(storyboard, /customClass="NativeRootTabBarController"/);
    assert.doesNotMatch(storyboard, /KatecheoBridge|CAPBridgeViewController/);
  });

  it("TS wrapper still marks failures for callers that fall back", () => {
    assert.match(wrapper, /failed\?:\s*boolean/);
    assert.match(wrapper, /PRESENT_HANG_TIMEOUT_MS/);
    assert.match(wrapper, /PRESENTATION_CONFIRM_MS/);
    assert.match(wrapper, /FORCE_WEB_FALLBACK_MS/);
    assert.match(wrapper, /classifyPresentOutcome/);
    assert.match(wrapper, /failed:\s*true/);
  });

  it("does not await addListener before present (TF85 blank pending hang)", () => {
    assert.doesNotMatch(wrapper, /listener\s*=\s*await\s+plugin\.addListener/);
    assert.match(wrapper, /NEVER await addListener before present/);
    assert.match(wrapper, /Promise\.race\(\[listenerReady/);
  });
});
