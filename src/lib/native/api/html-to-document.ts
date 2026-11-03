/**
 * Convert HTML (old web editor / paste) into NoteDocumentV1 body blocks.
 * Pure string parser — no DOM — so Node unit tests run without jsdom.
 */
import {
  type NoteDocBlock,
  type NoteDocLineBlock,
  type NoteDocLineType,
  type NoteDocSpan,
  type TextMark,
} from "./note-document.ts";

function newId(): string {
  return crypto.randomUUID().replaceAll("-", "");
}

function decodeEntities(raw: string): string {
  return raw
    .replace(/&nbsp;/gi, " ")
    .replace(/&amp;/gi, "&")
    .replace(/&lt;/gi, "<")
    .replace(/&gt;/gi, ">")
    .replace(/&quot;/gi, '"')
    .replace(/&#39;/gi, "'");
}

function stripTags(raw: string): string {
  return decodeEntities(raw.replace(/<br\s*\/?>/gi, "\n").replace(/<[^>]+>/g, "")).replace(/\u200B/g, "");
}

type MarkState = { bold: boolean; italic: boolean; underline: boolean; strikethrough: boolean };

function marksFromState(state: MarkState): TextMark[] | undefined {
  const marks: TextMark[] = [];
  if (state.bold) marks.push("bold");
  if (state.italic) marks.push("italic");
  if (state.underline) marks.push("underline");
  if (state.strikethrough) marks.push("strikethrough");
  return marks.length ? marks : undefined;
}

function pushText(spans: NoteDocSpan[], text: string, state: MarkState) {
  const cleaned = decodeEntities(text).replace(/\u200B/g, "");
  if (!cleaned) return;
  const marks = marksFromState(state);
  spans.push(marks ? { type: "text", text: cleaned, marks } : { type: "text", text: cleaned });
}

/** Walk a fragment of HTML and collect NoteDoc spans. */
export function parseInlineHtml(html: string): NoteDocSpan[] {
  const spans: NoteDocSpan[] = [];
  const state: MarkState = { bold: false, italic: false, underline: false, strikethrough: false };
  let i = 0;
  const src = html;

  while (i < src.length) {
    if (src[i] !== "<") {
      const next = src.indexOf("<", i);
      const chunk = next === -1 ? src.slice(i) : src.slice(i, next);
      pushText(spans, chunk, state);
      i = next === -1 ? src.length : next;
      continue;
    }

    const end = src.indexOf(">", i);
    if (end === -1) {
      pushText(spans, src.slice(i), state);
      break;
    }
    const rawTag = src.slice(i + 1, end).trim();
    const selfClosing = /\/\s*$/.test(rawTag);
    const closing = rawTag.startsWith("/");
    const nameMatch = rawTag.replace(/^\//, "").match(/^([a-z0-9]+)/i);
    const tag = (nameMatch?.[1] ?? "").toLowerCase();
    const attrs = rawTag.slice(tag.length + (closing ? 1 : 0));

    if (tag === "br") {
      pushText(spans, "\n", state);
      i = end + 1;
      continue;
    }

    if (!closing && tag === "span" && /data-ref\s*=/i.test(attrs)) {
      const refMatch = attrs.match(/data-ref\s*=\s*["']([^"']+)["']/i);
      const close = src.toLowerCase().indexOf("</span>", end + 1);
      const inner = close === -1 ? "" : src.slice(end + 1, close);
      const label = stripTags(inner).trim();
      if (refMatch) {
        const [bookId, chapterRaw, startRaw, endRaw] = refMatch[1]!.split("|");
        const chapter = Number(chapterRaw);
        if (bookId && Number.isFinite(chapter)) {
          spans.push({
            type: "bibleRef",
            bookId: bookId.slice(0, 12),
            chapter,
            verseStart: startRaw ? Number(startRaw) || null : null,
            verseEnd: endRaw ? Number(endRaw) || null : null,
            ...(label ? { text: label.slice(0, 120) } : {}),
          });
        }
      }
      i = close === -1 ? end + 1 : close + "</span>".length;
      continue;
    }

    if (!closing && tag === "a") {
      const hrefMatch = attrs.match(/href\s*=\s*["']([^"']+)["']/i);
      const close = src.toLowerCase().indexOf("</a>", end + 1);
      const inner = close === -1 ? "" : src.slice(end + 1, close);
      const text = stripTags(inner).trim();
      const href = hrefMatch?.[1]?.trim() ?? "";
      if (href) {
        spans.push({ type: "link", href: href.slice(0, 2000), text: (text || href).slice(0, 500) });
      } else if (text) {
        pushText(spans, text, state);
      }
      i = close === -1 ? end + 1 : close + "</a>".length;
      continue;
    }

    if (!selfClosing) {
      if (tag === "b" || tag === "strong") state.bold = !closing ? true : false;
      else if (tag === "i" || tag === "em") state.italic = !closing ? true : false;
      else if (tag === "u") state.underline = !closing ? true : false;
      else if (tag === "s" || tag === "strike" || tag === "del") state.strikethrough = !closing ? true : false;
    }

    i = end + 1;
  }

  return mergeTextSpans(spans);
}

function mergeTextSpans(spans: NoteDocSpan[]): NoteDocSpan[] {
  const out: NoteDocSpan[] = [];
  for (const span of spans) {
    const last = out[out.length - 1];
    if (
      span.type === "text" &&
      last?.type === "text" &&
      JSON.stringify(last.marks ?? []) === JSON.stringify(span.marks ?? [])
    ) {
      last.text += span.text;
      continue;
    }
    out.push(span);
  }
  return out.filter((span) => span.type !== "text" || span.text.length > 0);
}

function line(type: NoteDocLineType, htmlInner: string, checked?: boolean): NoteDocLineBlock {
  const block: NoteDocLineBlock = {
    id: newId(),
    type,
    spans: parseInlineHtml(htmlInner),
  };
  if (type === "check" && checked != null) block.checked = checked;
  return block;
}

function extractListItems(inner: string, listAttrs: string, ordered: boolean): NoteDocLineBlock[] {
  const items: NoteDocLineBlock[] = [];
  const liRe = /<li(\s[^>]*)?>([\s\S]*?)<\/li>/gi;
  let li: RegExpExecArray | null;
  while ((li = liRe.exec(inner))) {
    const liAttrs = li[1] ?? "";
    const checked =
      /data-checked\s*=\s*["']?(true|1)/i.test(liAttrs) || /☑|✓|✔/.test(stripTags(li[2] ?? "").slice(0, 2));
    const isCheck =
      /checklist|todo|task/i.test(listAttrs + liAttrs) ||
      /type\s*=\s*["']?checkbox/i.test(liAttrs) ||
      /data-checked/i.test(liAttrs);
    if (isCheck) items.push(line("check", li[2] ?? "", checked));
    else items.push(line(ordered ? "numbered" : "bullet", li[2] ?? ""));
    if (items.length >= 200) break;
  }
  if (!items.length) items.push(line(ordered ? "numbered" : "bullet", inner));
  return items;
}

function extractBlocks(html: string): NoteDocBlock[] {
  const blocks: NoteDocBlock[] = [];
  const working = html.replace(/<\/?(?:body|html|head)[^>]*>/gi, "");
  const chunkRe = /<(h[1-6]|p|blockquote|ul|ol|div)(\s[^>]*)?>([\s\S]*?)<\/\1>/gi;
  let matched = false;
  let match: RegExpExecArray | null;
  while ((match = chunkRe.exec(working))) {
    matched = true;
    const tag = match[1]!.toLowerCase();
    const attrs = match[2] ?? "";
    const inner = match[3] ?? "";
    if (tag === "ul" || tag === "ol") {
      blocks.push(...extractListItems(inner, attrs, tag === "ol"));
    } else if (/^h[1-6]$/.test(tag)) {
      blocks.push(line("heading", inner));
    } else if (tag === "blockquote") {
      blocks.push(line("quote", inner));
    } else {
      blocks.push(line("paragraph", inner));
    }
    if (blocks.length >= 200) break;
  }
  if (!matched) {
    const plain = stripTags(working).trim();
    if (plain) {
      for (const part of plain.split(/\n{2,}/)) {
        const text = part.replace(/\n/g, " ").trim();
        if (!text) continue;
        blocks.push({ id: newId(), type: "paragraph", spans: [{ type: "text", text }] });
      }
    }
  }
  return blocks.length ? blocks.slice(0, 200) : [{ id: newId(), type: "paragraph", spans: [] }];
}

/** True when a stored `blocks` column looks like HTML rather than JSON. */
export function looksLikeHtml(raw: string): boolean {
  const trimmed = raw.trim();
  if (!trimmed) return false;
  if (trimmed.startsWith("{") || trimmed.startsWith("[")) return false;
  return /<\/?[a-z][\s\S]*>/i.test(trimmed);
}

/** HTML string → NoteDocumentV1 body.blocks (never empty). */
export function htmlToDocumentBlocks(html: string): NoteDocBlock[] {
  return extractBlocks(html);
}
