import assert from "node:assert/strict";
import { describe, it } from "node:test";
import {
  NOTE_DOCUMENT_SCHEMA_VERSION,
  coerceIncomingNote,
  documentPreview,
  documentToNote,
  noteToDocument,
  type LegacyNote,
} from "./note-document.ts";

const sampleLegacy: LegacyNote = {
  id: "note1",
  title: "Culto",
  happenedAt: "2026-11-01",
  tags: ["igreja"],
  speakerId: "spk-root",
  blocks: [
    {
      id: "l1",
      type: "p",
      inlines: [
        { type: "text", text: "Hello ", bold: true },
        { type: "ref", bookId: "JHN", chapter: 3, verseStart: 16, verseEnd: null },
      ],
    },
    {
      id: "s1",
      type: "speaker",
      speakerId: "spk1",
      title: "João",
      children: [{ id: "l2", type: "h", inlines: [{ type: "text", text: "Section", italic: true }] }],
    },
  ],
  visibility: "private",
  updatedAt: "2026-11-01T12:00:00.000Z",
};

describe("noteToDocument / documentToNote", () => {
  it("emits schemaVersion 1 and platform-neutral block types", () => {
    const doc = noteToDocument(sampleLegacy);
    assert.equal(doc.schemaVersion, NOTE_DOCUMENT_SCHEMA_VERSION);
    assert.equal(doc.noteSpeakerId, "spk-root");
    assert.equal(doc.body.blocks[0]?.type, "paragraph");
    assert.equal(doc.body.blocks[1]?.type, "speakerSection");
    const spans = doc.body.blocks[0] && "spans" in doc.body.blocks[0] ? doc.body.blocks[0].spans : [];
    assert.deepEqual(spans[0], { type: "text", text: "Hello ", marks: ["bold"] });
    assert.equal(spans[1]?.type, "bibleRef");
  });

  it("round-trips legacy notes without dropping refs or speakers", () => {
    const doc = noteToDocument(sampleLegacy);
    const back = documentToNote(doc);
    assert.ok(back);
    assert.equal(back!.id, sampleLegacy.id);
    assert.equal(back!.speakerId, "spk-root");
    assert.equal(back!.blocks.length, 2);
    assert.equal(back!.blocks[0]!.type, "p");
    assert.equal(back!.blocks[1]!.type, "speaker");
    const again = noteToDocument(back!);
    assert.deepEqual(again.body, doc.body);
  });

  it("flattens reserved link spans to text when writing legacy store", () => {
    const doc = noteToDocument(sampleLegacy);
    const line = doc.body.blocks[0];
    assert.ok(line && "spans" in line);
    line.spans.push({ type: "link", href: "https://example.com", text: "site" });
    const back = documentToNote(doc);
    assert.ok(back);
    const first = back!.blocks[0];
    assert.ok(first && first.type === "p");
    const last = first.inlines.at(-1);
    assert.ok(last && last.type === "text");
    assert.equal(last.text, "site");
  });
});

describe("documentPreview", () => {
  it("keeps readable bible ref labels in list rows (no dangling Passagem:)", () => {
    const doc = noteToDocument(sampleLegacy);
    const preview = documentPreview(doc);
    assert.match(preview, /Hello/);
    // Legacy refs lack stored display text → compact bookId fallback.
    assert.match(preview, /JHN 3:16/);

    const withLabel = noteToDocument(sampleLegacy);
    const line = withLabel.body.blocks[0];
    assert.ok(line && "spans" in line);
    const ref = line.spans.find((s) => s.type === "bibleRef");
    assert.ok(ref && ref.type === "bibleRef");
    ref.text = "João 3:16";
    const labeled = documentPreview(withLabel);
    assert.match(labeled, /João 3:16/);
    assert.match(labeled, /Hello/);
  });

  it("renders stored labels after Passagem: / Referência: prefixes", () => {
    const doc = noteToDocument(sampleLegacy);
    const line = doc.body.blocks[0];
    assert.ok(line && "spans" in line);
    line.spans = [
      { type: "text", text: "Passagem: " },
      {
        type: "bibleRef",
        bookId: "PSA",
        chapter: 23,
        verseStart: null,
        verseEnd: null,
        text: "Salmos 23",
      },
      { type: "text", text: " · Referência: " },
      {
        type: "bibleRef",
        bookId: "JHN",
        chapter: 15,
        verseStart: 1,
        verseEnd: 8,
        text: "João 15:1–8",
      },
    ];
    const preview = documentPreview(doc);
    assert.match(preview, /Passagem: Salmos 23/);
    assert.match(preview, /Referência: João 15:1–8/);
    assert.doesNotMatch(preview, /Passagem:\s*$/);
  });
});

describe("coerceIncomingNote", () => {
  it("accepts NoteDocumentV1 payloads", () => {
    const doc = noteToDocument(sampleLegacy);
    const coerced = coerceIncomingNote(doc);
    assert.ok(coerced);
    assert.equal(coerced!.document.schemaVersion, 1);
    assert.equal(coerced!.note.title, "Culto");
  });

  it("accepts legacy Note payloads for gradual migration", () => {
    const coerced = coerceIncomingNote(sampleLegacy);
    assert.ok(coerced);
    assert.equal(coerced!.document.body.blocks[0]?.type, "paragraph");
  });

  it("rejects empty ids", () => {
    assert.equal(coerceIncomingNote({ schemaVersion: 1, id: "", body: { blocks: [] } }), null);
  });
});
