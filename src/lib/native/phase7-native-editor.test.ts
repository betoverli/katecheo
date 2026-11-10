import assert from "node:assert/strict";
import { existsSync, readFileSync, readdirSync } from "node:fs";
import { describe, it } from "node:test";
import {
  coerceIncomingNote,
  encodeDocumentStorage,
  isDocumentStorage,
  noteToDocument,
  type LegacyNote,
} from "./api/note-document.ts";
import { htmlToDocumentBlocks } from "./api/html-to-document.ts";

const root = new URL("../../../", import.meta.url);

function read(rel: string) {
  return readFileSync(new URL(rel, root), "utf8");
}

describe("Phase 7 — native note editor", () => {
  it("removes NoteMioloEditorView and ships NativeNoteEditorView + codec", () => {
    assert.equal(existsSync(new URL("ios/App/Katecheo/NoteMioloEditorView.swift", root)), false);
    assert.equal(existsSync(new URL("ios/App/Katecheo/NativeNoteEditorView.swift", root)), true);
    assert.equal(existsSync(new URL("ios/App/Katecheo/NoteDocumentCodec.swift", root)), true);
    assert.equal(existsSync(new URL("ios/App/Katecheo/BibleRefInsertPicker.swift", root)), true);
    const editor = read("ios/App/Katecheo/NativeNoteEditorView.swift");
    assert.match(editor, /UITextView/);
    assert.doesNotMatch(editor, /WKWebView|import WebKit/);
    assert.match(editor, /Referência bíblica/);
    const codec = read("ios/App/Katecheo/NoteDocumentCodec.swift");
    assert.match(codec, /attributedString\(from/);
    assert.match(codec, /func document\(/);
    assert.match(codec, /bibleRef/);
    const detail = read("ios/App/Katecheo/NoteDetailViewController.swift");
    assert.match(detail, /NativeNoteEditorView/);
    assert.doesNotMatch(detail, /NoteMioloEditorView|WKWebView/);
  });

  it("forbids product WKWebView under ios/App/Katecheo (import only for migration)", () => {
    const appDir = new URL("ios/App/Katecheo/", root);
    const allowedWebKit = new Set([
      "NativeSessionBootstrap.swift",
      "SceneDelegate.swift",
      "LegacyWebStorageImporter.swift",
    ]);
    const allowedWkWebView = new Set(["LegacyWebStorageImporter.swift"]);
    const stripComments = (source: string) =>
      source.replace(/\/\*[\s\S]*?\*\//g, "").replace(/(^|[^:])\/\/.*$/gm, "$1");
    for (const name of readdirSync(appDir)) {
      if (!/\.(swift|m|h)$/.test(name)) continue;
      const body = stripComments(read(`ios/App/Katecheo/${name}`));
      if (/\bWKWebView\b/.test(body)) {
        assert.ok(allowedWkWebView.has(name), `WKWebView in ${name}`);
      }
      if (/\bimport\s+WebKit\b/.test(body)) {
        assert.ok(allowedWebKit.has(name), `import WebKit in ${name}`);
      }
    }
  });

  it("documents schema + Phase 7 for Android / Beto", () => {
    assert.equal(existsSync(new URL("docs/note-document-v1.md", root)), true);
    assert.equal(existsSync(new URL("docs/ios-phase7-native-editor.md", root)), true);
    const schema = read("docs/note-document-v1.md");
    assert.match(schema, /bibleRef/);
    assert.match(schema, /check/);
    assert.match(schema, /Android/);
    const phase7 = read("docs/ios-phase7-native-editor.md");
    assert.match(phase7, /NativeNoteEditorView/);
    assert.match(phase7, /Beto|pt-BR/i);
  });

  it("stores V1 envelope and migrates HTML without content loss", () => {
    const legacy: LegacyNote = {
      id: "n1",
      title: "Culto",
      happenedAt: "2026-11-02",
      tags: [],
      speakerId: null,
      blocks: [
        {
          id: "l1",
          type: "p",
          inlines: [
            { type: "text", text: "Oi ", bold: true },
            { type: "ref", bookId: "JHN", chapter: 3, verseStart: 16, verseEnd: null },
          ],
        },
      ],
      visibility: "private",
      updatedAt: "2026-11-02T12:00:00.000Z",
    };
    const doc = noteToDocument(legacy);
    const encoded = encodeDocumentStorage(doc.body.blocks);
    const parsed = JSON.parse(encoded);
    assert.ok(isDocumentStorage(parsed));

    const withExtras = {
      ...doc,
      body: {
        blocks: [
          {
            id: "c1",
            type: "check" as const,
            checked: true,
            spans: [{ type: "text" as const, text: "Orar", marks: ["underline" as const] }],
          },
          {
            id: "q1",
            type: "quote" as const,
            spans: [{ type: "text" as const, text: "Citação", marks: ["strikethrough" as const] }],
          },
          ...doc.body.blocks,
        ],
      },
    };
    const coerced = coerceIncomingNote(withExtras);
    assert.ok(coerced);
    assert.equal(coerced!.document.body.blocks[0]?.type, "check");
    assert.equal(coerced!.document.body.blocks[1]?.type, "quote");
    const check = coerced!.document.body.blocks[0];
    assert.ok(check && check.type === "check" && check.checked === true);

    const htmlBlocks = htmlToDocumentBlocks('<p>Salvo <b>rico</b></p><p>Linha 2</p>');
    const plain = htmlBlocks
      .map((b) => ("spans" in b ? b.spans.map((s) => (s.type === "text" ? s.text : "")).join("") : ""))
      .join(" ");
    assert.match(plain, /Salvo/);
    assert.match(plain, /rico/);
    assert.match(plain, /Linha 2/);
  });

  it("Xcode target lists Phase 7 sources and drops miolo WebView", () => {
    const pbx = read("ios/App/Katecheo.xcodeproj/project.pbxproj");
    assert.match(pbx, /NativeNoteEditorView\.swift in Sources/);
    assert.match(pbx, /NoteDocumentCodec\.swift in Sources/);
    assert.match(pbx, /BibleRefInsertPicker\.swift in Sources/);
    assert.doesNotMatch(pbx, /NoteMioloEditorView/);
  });
});
