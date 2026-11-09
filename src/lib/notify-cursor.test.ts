import assert from "node:assert/strict";
import { describe, it } from "node:test";
import { decodeInboxCursor, encodeInboxCursor } from "./notify-cursor.ts";

describe("inbox cursor", () => {
  it("round-trips created_at + id", () => {
    const createdAt = "2026-11-08T12:34:56.789Z";
    const id = "notifabc123";
    const cursor = encodeInboxCursor(createdAt, id);
    assert.deepEqual(decodeInboxCursor(cursor), { createdAt, id });
  });

  it("rejects malformed cursors", () => {
    assert.equal(decodeInboxCursor(null), null);
    assert.equal(decodeInboxCursor(""), null);
    assert.equal(decodeInboxCursor("@@@"), null);
    assert.equal(decodeInboxCursor(Buffer.from("no-tab", "utf8").toString("base64url")), null);
  });

  it("orders stably for pagination (created_at desc, id desc)", () => {
    const a = { createdAt: "2026-11-08T10:00:00.000Z", id: "b" };
    const b = { createdAt: "2026-11-08T10:00:00.000Z", id: "a" };
    const c = { createdAt: "2026-11-08T09:00:00.000Z", id: "z" };
    const key = (x: { createdAt: string; id: string }) => `${x.createdAt}\t${x.id}`;
    const sorted = [a, b, c].sort((l, r) => (key(l) < key(r) ? 1 : key(l) > key(r) ? -1 : 0));
    assert.deepEqual(
      sorted.map((x) => x.id),
      ["b", "a", "z"],
    );
  });
});
