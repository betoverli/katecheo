import assert from "node:assert/strict";
import { describe, it } from "node:test";
import { newGroupShouldOpenWeb, runNativeNewGroup } from "./new-group.ts";

describe("runNativeNewGroup", () => {
  it("always returns web-fallback so callers can open a create sheet", async () => {
    const result = await runNativeNewGroup("pt");
    assert.equal(result.type, "web-fallback");
    assert.equal(newGroupShouldOpenWeb(result), true);
  });

  it("never returns cancelled for the entry tap (that was the TF88 silent no-op)", async () => {
    const result = await runNativeNewGroup("en");
    assert.notEqual(result.type, "cancelled");
  });
});
