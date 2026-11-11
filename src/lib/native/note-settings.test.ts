import assert from "node:assert/strict";
import { describe, it } from "node:test";
import { noteSettingsShouldOpenWeb, runNativeNoteSettings } from "./note-settings.ts";

const emptyNote = {
  id: "n1",
  title: "",
  happenedAt: "2026-01-01",
  tags: [] as string[],
  speakerId: null as string | null,
  blocks: [],
  updatedAt: new Date().toISOString(),
};

describe("runNativeNoteSettings", () => {
  it("always returns web-fallback so callers can open settings UI", async () => {
    const action = await runNativeNoteSettings({ locale: "pt", note: emptyNote as never });
    assert.equal(action.type, "web-fallback");
    assert.equal(noteSettingsShouldOpenWeb(action), true);
  });

  it("never returns cancelled for the entry tap (that was the TF88 silent no-op)", async () => {
    const action = await runNativeNoteSettings({ locale: "en", note: emptyNote as never });
    assert.notEqual(action.type, "cancelled");
  });
});
