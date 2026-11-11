import assert from "node:assert/strict";
import { describe, it } from "node:test";
import { groupNotesEtag } from "./group-notes-etag.ts";

describe("groupNotesEtag", () => {
  it("is stable regardless of input order", () => {
    const a = groupNotesEtag([
      { note: { id: "n1", updatedAt: "2026-11-10T12:00:00Z" } },
      { note: { id: "n2", updatedAt: "2026-11-11T12:00:00Z" } },
    ]);
    const b = groupNotesEtag([
      { note: { id: "n2", updatedAt: "2026-11-11T12:00:00Z" } },
      { note: { id: "n1", updatedAt: "2026-11-10T12:00:00Z" } },
    ]);
    assert.equal(a, b);
    assert.match(a, /^W\/"gnotes-/);
  });

  it("changes when a note updates", () => {
    const before = groupNotesEtag([{ note: { id: "n1", updatedAt: "2026-11-10T12:00:00Z" } }]);
    const after = groupNotesEtag([{ note: { id: "n1", updatedAt: "2026-11-11T12:00:00Z" } }]);
    assert.notEqual(before, after);
  });
});
