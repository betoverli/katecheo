import assert from "node:assert/strict";
import { readFileSync, existsSync } from "node:fs";
import { describe, it } from "node:test";

const root = new URL("../../../", import.meta.url);

function read(rel: string) {
  return readFileSync(new URL(rel, root), "utf8");
}

describe("Phase 6 — hardening + legacy WebView import", () => {
  it("ships one-time localStorage importer on the main thread", () => {
    assert.equal(existsSync(new URL("ios/App/App/LegacyWebStorageImporter.swift", root)), true);
    const importer = read("ios/App/App/LegacyWebStorageImporter.swift");
    assert.match(importer, /@MainActor/);
    assert.match(importer, /Thread\.isMainThread/);
    assert.match(importer, /cita-settings/);
    assert.match(importer, /verse2note-outbox/);
    assert.match(importer, /grok-auth\.bearer-token/);
    assert.match(importer, /LegacyNoteConverter/);
    assert.match(importer, /verse2note\.legacyWebImport\.v1/);
    // Import must not enqueue deletes against the server.
    assert.match(importer, /Intentionally skipped|never enqueue deletes|Skips deletes/i);
  });

  it("converts legacy Note blocks into NoteDocumentV1", () => {
    const converter = read("ios/App/App/LegacyNoteConverter.swift");
    assert.match(converter, /schemaVersion:\s*1/);
    assert.match(converter, /speakerSection/);
    assert.match(converter, /bibleRef/);
    assert.match(converter, /noteDocument\(fromLegacy/);
  });

  it("has a durable outbox with backoff and 401 handling", () => {
    const outbox = read("ios/App/App/NativeOutbox.swift");
    assert.match(outbox, /enqueueNoteUpsert/);
    assert.match(outbox, /flushIfPossible/);
    assert.match(outbox, /nextAttemptAt/);
    assert.match(outbox, /pow\(2/);
    const client = read("ios/App/App/NativeAPIClient.swift");
    assert.match(client, /handleUnauthorized/);
    assert.match(client, /nativeSessionDidExpire/);
    assert.match(client, /upsertMyCollection/);
    const scene = read("ios/App/App/SceneDelegate.swift");
    assert.match(scene, /LegacyWebStorageImporter\.runIfNeeded/);
    assert.match(scene, /NativeOutbox\.flushIfPossible/);
    assert.match(scene, /nativeSessionDidExpire/);
  });

  it("keeps collection create idempotent when client id is supplied", () => {
    const verses = read("src/lib/native/api/v1-verses.server.ts");
    assert.match(verses, /requestedId/);
    assert.match(verses, /Phase 6 import/);
    assert.match(verses, /updateMyCollectionForUser\(userId, requestedId/);
  });

  it("documents Phase 6 for Beto", () => {
    assert.equal(existsSync(new URL("docs/ios-phase6-hardening.md", root)), true);
    const doc = read("docs/ios-phase6-hardening.md");
    assert.match(doc, /cita-settings/);
    assert.match(doc, /verse2note-outbox/);
    assert.match(doc, /NoteDocumentV1/);
    assert.match(doc, /pt-BR|Beto/);
  });
});
