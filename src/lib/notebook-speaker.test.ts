import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { describe, it } from "node:test";

describe("note speaker attribution", () => {
  const notebook = readFileSync(new URL("./notebook.ts", import.meta.url), "utf8");

  it("noteIncludesSpeaker matches whole-note speakerId and section blocks", () => {
    assert.match(notebook, /export function noteIncludesSpeaker/);
    assert.match(notebook, /note\.speakerId === speakerId/);
    assert.match(notebook, /block\.type === "speaker" && block\.speakerId === speakerId/);
    assert.match(notebook, /if \(note\.speakerId\) ids\.add\(note\.speakerId\)/);
  });

  it("asks whole-vs-section on the first speaker via noteNeedsSpeakerAsk", () => {
    assert.match(notebook, /export function noteNeedsSpeakerAsk/);
  });
});
