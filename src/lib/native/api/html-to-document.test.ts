import assert from "node:assert/strict";
import { describe, it } from "node:test";
import { htmlToDocumentBlocks, looksLikeHtml } from "./html-to-document.ts";

describe("looksLikeHtml", () => {
  it("detects HTML and rejects JSON", () => {
    assert.equal(looksLikeHtml("<p>Olá</p>"), true);
    assert.equal(looksLikeHtml('[{"type":"p"}]'), false);
    assert.equal(looksLikeHtml('{"v":1,"blocks":[]}'), false);
  });
});

describe("htmlToDocumentBlocks", () => {
  it("converts paragraphs, headings, lists, quotes and marks", () => {
    const html = `
      <h2>Título</h2>
      <p>Texto <b>negrito</b> e <i>itálico</i> com <u>sub</u> e <s>risco</s></p>
      <ul><li>um</li><li>dois</li></ul>
      <ol><li>primeiro</li></ol>
      <blockquote>Citação</blockquote>
    `;
    const blocks = htmlToDocumentBlocks(html);
    assert.equal(blocks[0]?.type, "heading");
    assert.equal(blocks[1]?.type, "paragraph");
    const marks = new Set(
      (blocks[1] && "spans" in blocks[1] ? blocks[1].spans : [])
        .filter((s) => s.type === "text")
        .flatMap((s) => ("marks" in s && s.marks ? s.marks : [])),
    );
    assert.ok(marks.has("bold"));
    assert.ok(marks.has("italic"));
    assert.ok(marks.has("underline"));
    assert.ok(marks.has("strikethrough"));
    assert.ok(blocks.some((b) => b.type === "bullet"));
    assert.ok(blocks.some((b) => b.type === "numbered"));
    assert.ok(blocks.some((b) => b.type === "quote"));
  });

  it("preserves bibleRef pills with display text", () => {
    const html = `<p>Ver <span class="ref-pill" data-ref="JHN|3|16|">João 3:16</span> hoje</p>`;
    const blocks = htmlToDocumentBlocks(html);
    const spans = blocks[0] && "spans" in blocks[0] ? blocks[0].spans : [];
    const ref = spans.find((s) => s.type === "bibleRef");
    assert.ok(ref);
    assert.equal(ref?.type, "bibleRef");
    if (ref?.type === "bibleRef") {
      assert.equal(ref.bookId, "JHN");
      assert.equal(ref.chapter, 3);
      assert.equal(ref.verseStart, 16);
      assert.equal(ref.text, "João 3:16");
    }
  });

  it("never loses plain text content", () => {
    const html = "<div>Linha A</div><div>Linha B</div>";
    const blocks = htmlToDocumentBlocks(html);
    const plain = blocks
      .map((b) => ("spans" in b ? b.spans.map((s) => (s.type === "text" ? s.text : "")).join("") : ""))
      .join(" ");
    assert.match(plain, /Linha A/);
    assert.match(plain, /Linha B/);
  });

  it("converts checklist-ish lists", () => {
    const html = `<ul class="checklist"><li data-checked="true">Feito</li><li>Pendente</li></ul>`;
    const blocks = htmlToDocumentBlocks(html);
    assert.equal(blocks[0]?.type, "check");
    if (blocks[0]?.type === "check") assert.equal(blocks[0].checked, true);
    assert.equal(blocks[1]?.type, "check");
  });
});
