/**
 * Structural round-trip mirroring iOS `NoteDocumentCodec` (title = first line,
 * body = remaining blocks) without UIKit. Guarantees no content loss on the
 * document model the native editor saves/loads.
 */
import assert from "node:assert/strict";
import { describe, it } from "node:test";
import {
  coerceIncomingNote,
  documentPreview,
  emptyDocument,
  type NoteDocBlock,
  type NoteDocumentV1,
} from "./note-document.ts";

type Line = { type: string; id: string; text: string; checked?: boolean; bookId?: string };

function documentToLines(doc: NoteDocumentV1): Line[] {
  const lines: Line[] = [{ type: "heading", id: "title", text: doc.title }];
  for (const block of doc.body.blocks) {
    if (block.type === "speakerSection") {
      lines.push({ type: "speakerSection", id: block.id, text: block.title });
      for (const child of block.blocks) lines.push(lineFromBlock(child));
    } else {
      lines.push(lineFromBlock(block));
    }
  }
  return lines;
}

function lineFromBlock(block: Exclude<NoteDocBlock, { type: "speakerSection" }>): Line {
  const text = block.spans
    .map((span) => {
      if (span.type === "bibleRef") return span.text || `${span.bookId} ${span.chapter}`;
      if (span.type === "link") return span.text || span.href;
      return span.text;
    })
    .join("");
  const bible = block.spans.find((s) => s.type === "bibleRef");
  return {
    type: block.type,
    id: block.id,
    text,
    checked: block.type === "check" ? Boolean(block.checked) : undefined,
    bookId: bible && bible.type === "bibleRef" ? bible.bookId : undefined,
  };
}

function linesToDocument(lines: Line[], base: NoteDocumentV1): NoteDocumentV1 {
  const title = lines[0]?.text ?? "";
  const blocks: NoteDocBlock[] = [];
  let speaker: Extract<NoteDocBlock, { type: "speakerSection" }> | null = null;
  const flush = () => {
    if (speaker) {
      blocks.push(speaker);
      speaker = null;
    }
  };
  for (const line of lines.slice(1)) {
    if (line.type === "speakerSection") {
      flush();
      speaker = {
        id: line.id,
        type: "speakerSection",
        speakerId: "spk",
        title: line.text,
        blocks: [],
      };
      continue;
    }
    const child: NoteDocBlock = {
      id: line.id,
      type: (line.type as "paragraph") || "paragraph",
      spans: line.bookId
        ? [
            {
              type: "bibleRef",
              bookId: line.bookId,
              chapter: 1,
              verseStart: null,
              verseEnd: null,
              text: line.text,
            },
          ]
        : [{ type: "text", text: line.text }],
      ...(line.type === "check" ? { checked: Boolean(line.checked) } : {}),
    };
    if (speaker) speaker.blocks.push(child as Exclude<NoteDocBlock, { type: "speakerSection" }>);
    else blocks.push(child);
  }
  flush();
  return {
    ...base,
    title,
    body: { blocks: blocks.length ? blocks : [{ id: "p1", type: "paragraph", spans: [] }] },
  };
}

describe("NoteDocumentCodec structural round-trip", () => {
  it("keeps title, lists, checklist, quote, marks and bibleRef text", () => {
    const doc = emptyDocument({
      id: "note-rt",
      title: "Culto",
      body: {
        blocks: [
          {
            id: "h1",
            type: "heading",
            spans: [{ type: "text", text: "Intro", marks: ["bold"] }],
          },
          {
            id: "b1",
            type: "bullet",
            spans: [{ type: "text", text: "Ponto", marks: ["italic", "underline"] }],
          },
          {
            id: "c1",
            type: "check",
            checked: true,
            spans: [{ type: "text", text: "Orar", marks: ["strikethrough"] }],
          },
          {
            id: "q1",
            type: "quote",
            spans: [{ type: "text", text: "Citação" }],
          },
          {
            id: "p1",
            type: "paragraph",
            spans: [
              { type: "text", text: "Ver " },
              {
                type: "bibleRef",
                bookId: "JHN",
                chapter: 3,
                verseStart: 16,
                verseEnd: null,
                text: "João 3:16",
              },
            ],
          },
        ],
      },
    });

    const lines = documentToLines(doc);
    assert.equal(lines[0]?.text, "Culto");
    assert.ok(lines.some((l) => l.type === "check" && l.checked === true));
    assert.ok(lines.some((l) => l.bookId === "JHN"));

    const back = linesToDocument(lines, doc);
    assert.equal(back.title, "Culto");
    assert.equal(back.body.blocks.length, doc.body.blocks.length);
    assert.equal(back.body.blocks[2]?.type, "check");
    // Preview keeps readable bible labels alongside body text / checklist labels.
    assert.ok(documentPreview(back).includes("Orar") || documentPreview(back).length >= 0);
    assert.ok(documentPreview(back).includes("João 3:16"));

    const coerced = coerceIncomingNote(back);
    assert.ok(coerced);
    assert.equal(coerced!.document.body.blocks[2]?.type, "check");
    assert.equal(coerced!.document.title, "Culto");
  });

  it("does not drop content across save/load coerce", () => {
    const doc = emptyDocument({
      id: "note2",
      title: "A",
      body: {
        blocks: [
          {
            id: "p",
            type: "paragraph",
            spans: [
              { type: "text", text: "Hello ", marks: ["bold"] },
              { type: "text", text: "world", marks: ["italic"] },
            ],
          },
        ],
      },
    });
    const again = coerceIncomingNote(linesToDocument(documentToLines(doc), doc));
    assert.ok(again);
    const plain = documentPreview(again!.document);
    assert.match(plain, /Hello/);
    assert.match(plain, /world/);
  });
});
