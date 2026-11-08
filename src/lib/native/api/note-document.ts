/**
 * Platform-neutral note document model for `/api/native/v1`.
 *
 * Designed so iOS (Phase 0+) and a future Android app share one JSON shape.
 * The web SPA still persists the legacy `Note` / `NoteBlock` tree in Postgres;
 * this module converts at the API boundary so native clients never depend on
 * HTML or web-editor internals.
 *
 * Self-contained (no `@/` runtime imports) so Node unit tests can run under
 * `--experimental-strip-types` without the bible/Vite path alias graph.
 *
 * schemaVersion 1 — current surface (text marks, bible refs, speaker sections).
 * Bump schemaVersion only for breaking changes; additive fields may appear
 * under the same version when optional.
 */

/** Legacy store shapes (mirrors `src/lib/notebook.ts` — keep in sync). */
export type LegacyNoteInline =
  | { type: "text"; text: string; bold?: boolean; italic?: boolean }
  | { type: "ref"; bookId: string; chapter: number; verseStart: number | null; verseEnd: number | null };

export type LegacyLineType = "p" | "h" | "ul" | "ol";

export type LegacyLineBlock = {
  id: string;
  type: LegacyLineType;
  inlines: LegacyNoteInline[];
};

export type LegacySpeakerBlock = {
  id: string;
  type: "speaker";
  speakerId: string;
  title: string;
  children: LegacyLineBlock[];
  collapsed?: boolean;
};

export type LegacyNoteBlock = LegacyLineBlock | LegacySpeakerBlock;

export type LegacyNote = {
  id: string;
  title: string;
  happenedAt: string;
  tags: string[];
  speakerId: string | null;
  blocks: LegacyNoteBlock[];
  visibility: "private" | "unlisted";
  updatedAt: string;
};

export const NOTE_DOCUMENT_SCHEMA_VERSION = 1 as const;

/** Marker written into `notebook_notes.blocks` when storing V1 body JSON. */
export const NOTE_DOCUMENT_STORAGE_MARKER = 1 as const;

export type TextMark = "bold" | "italic" | "underline" | "strikethrough";

export type NoteDocTextSpan = {
  type: "text";
  text: string;
  marks?: TextMark[];
};

/** Canonical Bible reference node (OSIS-style bookId, e.g. JHN). */
export type NoteDocBibleRefSpan = {
  type: "bibleRef";
  bookId: string;
  chapter: number;
  verseStart: number | null;
  verseEnd: number | null;
  /** Optional display label (locale-formatted). Clients may regenerate. */
  text?: string;
};

/**
 * Optional hyperlink span. Not produced by today's web editor; reserved so
 * Android/iOS can add links without a schema bump if kept optional.
 */
export type NoteDocLinkSpan = {
  type: "link";
  href: string;
  text: string;
};

export type NoteDocSpan = NoteDocTextSpan | NoteDocBibleRefSpan | NoteDocLinkSpan;

export type NoteDocLineType = "paragraph" | "heading" | "bullet" | "numbered" | "check" | "quote";

export type NoteDocLineBlock = {
  id: string;
  type: NoteDocLineType;
  spans: NoteDocSpan[];
  /** Only for `type: "check"`. */
  checked?: boolean;
};

export type NoteDocSpeakerSection = {
  id: string;
  type: "speakerSection";
  speakerId: string;
  title: string;
  collapsed?: boolean;
  blocks: NoteDocLineBlock[];
};

export type NoteDocBlock = NoteDocLineBlock | NoteDocSpeakerSection;

/**
 * Wire format for native note payloads (`GET/POST/PATCH /notes`).
 * `body.blocks` is the document; never HTML.
 */
export type NoteDocumentV1 = {
  schemaVersion: typeof NOTE_DOCUMENT_SCHEMA_VERSION;
  id: string;
  title: string;
  happenedAt: string;
  tags: string[];
  /** Whole-note speaker (chip), distinct from inline speaker sections. */
  noteSpeakerId: string | null;
  visibility: "private" | "unlisted";
  updatedAt: string;
  body: {
    blocks: NoteDocBlock[];
  };
};

const LINE_TO_DOC: Record<LegacyLineType, NoteDocLineType> = {
  p: "paragraph",
  h: "heading",
  ul: "bullet",
  ol: "numbered",
};

/** check/quote flatten to closest legacy line types when writing the old store. */
const DOC_TO_LINE: Record<NoteDocLineType, LegacyLineType> = {
  paragraph: "p",
  heading: "h",
  bullet: "ul",
  numbered: "ol",
  check: "ul",
  quote: "p",
};

const ALL_MARKS: TextMark[] = ["bold", "italic", "underline", "strikethrough"];

function asDocLineType(value: unknown): NoteDocLineType {
  if (value === "heading" || value === "bullet" || value === "numbered" || value === "check" || value === "quote") {
    return value;
  }
  return "paragraph";
}

function cleanMarks(input: unknown): TextMark[] | undefined {
  if (!Array.isArray(input)) return undefined;
  const marks = input.filter((m): m is TextMark => typeof m === "string" && (ALL_MARKS as string[]).includes(m));
  return marks.length ? marks : undefined;
}

function cleanSpan(input: unknown): NoteDocSpan | null {
  if (!input || typeof input !== "object") return null;
  const row = input as Record<string, unknown>;
  if (row.type === "bibleRef") {
    const bookId = typeof row.bookId === "string" ? row.bookId.slice(0, 12) : "";
    const chapter = typeof row.chapter === "number" ? row.chapter : Number(row.chapter);
    if (!bookId || !Number.isFinite(chapter)) return null;
    const span: NoteDocBibleRefSpan = {
      type: "bibleRef",
      bookId,
      chapter,
      verseStart: typeof row.verseStart === "number" ? row.verseStart : null,
      verseEnd: typeof row.verseEnd === "number" ? row.verseEnd : null,
    };
    if (typeof row.text === "string" && row.text.trim()) span.text = row.text.trim().slice(0, 120);
    return span;
  }
  if (row.type === "link") {
    const href = typeof row.href === "string" ? row.href.trim().slice(0, 2000) : "";
    if (!href) return null;
    const text =
      typeof row.text === "string" && row.text.trim() ? row.text.trim().slice(0, 500) : href.slice(0, 500);
    return { type: "link", href, text };
  }
  if (typeof row.text === "string") {
    const marks = cleanMarks(row.marks);
    return marks ? { type: "text", text: row.text, marks } : { type: "text", text: row.text };
  }
  return null;
}

function cleanDocLine(input: unknown): NoteDocLineBlock | null {
  if (!input || typeof input !== "object") return null;
  const row = input as Record<string, unknown>;
  const type = asDocLineType(row.type);
  const spans = Array.isArray(row.spans)
    ? row.spans.map(cleanSpan).filter((span): span is NoteDocSpan => Boolean(span)).slice(0, 200)
    : [];
  const block: NoteDocLineBlock = {
    id: typeof row.id === "string" && row.id ? row.id.slice(0, 40) : newId(),
    type,
    spans,
  };
  if (type === "check") block.checked = Boolean(row.checked);
  return block;
}

/** Normalize V1 body.blocks (line + speakerSection). */
export function cleanDocBlocks(input: unknown): NoteDocBlock[] {
  if (!Array.isArray(input)) return [emptyDocLine()];
  const out: NoteDocBlock[] = [];
  for (const item of input) {
    if (!item || typeof item !== "object") continue;
    const row = item as Record<string, unknown>;
    if (row.type === "speakerSection") {
      const speakerId = typeof row.speakerId === "string" ? row.speakerId.slice(0, 40) : "";
      if (!speakerId) continue;
      const children = Array.isArray(row.blocks)
        ? row.blocks.map(cleanDocLine).filter((block): block is NoteDocLineBlock => Boolean(block)).slice(0, 80)
        : [emptyDocLine()];
      out.push({
        id: typeof row.id === "string" && row.id ? row.id.slice(0, 40) : newId(),
        type: "speakerSection",
        speakerId,
        title: typeof row.title === "string" ? row.title.trim().slice(0, 80) : "",
        ...(row.collapsed ? { collapsed: true as const } : {}),
        blocks: children.length ? children : [emptyDocLine()],
      });
    } else {
      const line = cleanDocLine(row);
      if (line) out.push(line);
    }
    if (out.length >= 200) break;
  }
  return out.length ? out : [emptyDocLine()];
}

/** Persist shape for `notebook_notes.blocks` after Phase 7. */
export type NoteDocumentStorageV1 = {
  v: typeof NOTE_DOCUMENT_STORAGE_MARKER;
  blocks: NoteDocBlock[];
};

export function encodeDocumentStorage(blocks: NoteDocBlock[]): string {
  const payload: NoteDocumentStorageV1 = { v: NOTE_DOCUMENT_STORAGE_MARKER, blocks: cleanDocBlocks(blocks) };
  return JSON.stringify(payload);
}

export function isDocumentStorage(raw: unknown): raw is NoteDocumentStorageV1 {
  return Boolean(
    raw &&
      typeof raw === "object" &&
      !Array.isArray(raw) &&
      (raw as NoteDocumentStorageV1).v === NOTE_DOCUMENT_STORAGE_MARKER &&
      Array.isArray((raw as NoteDocumentStorageV1).blocks),
  );
}

function newId(): string {
  return crypto.randomUUID().replaceAll("-", "");
}

function todayKey(date = new Date()): string {
  const y = date.getFullYear();
  const m = String(date.getMonth() + 1).padStart(2, "0");
  const d = String(date.getDate()).padStart(2, "0");
  return `${y}-${m}-${d}`;
}

function emptyLegacyLine(type: LegacyLineType = "p"): LegacyLineBlock {
  return { id: newId(), type, inlines: [] };
}

function emptyDocLine(): NoteDocLineBlock {
  return { id: newId(), type: "paragraph", spans: [] };
}

function asLineType(value: unknown): LegacyLineType {
  return value === "h" || value === "ul" || value === "ol" ? value : "p";
}

function cleanInlines(input: unknown): LegacyNoteInline[] {
  if (!Array.isArray(input)) return [];
  const out: LegacyNoteInline[] = [];
  for (const item of input) {
    if (!item || typeof item !== "object") continue;
    const row = item as Record<string, unknown>;
    if (row.type === "ref") {
      const bookId = typeof row.bookId === "string" ? row.bookId.slice(0, 12) : "";
      const chapter = typeof row.chapter === "number" ? row.chapter : Number(row.chapter);
      if (!bookId || !Number.isFinite(chapter)) continue;
      out.push({
        type: "ref",
        bookId,
        chapter,
        verseStart: typeof row.verseStart === "number" ? row.verseStart : null,
        verseEnd: typeof row.verseEnd === "number" ? row.verseEnd : null,
      });
    } else if (typeof row.text === "string") {
      out.push({
        type: "text",
        text: row.text,
        bold: row.bold ? true : undefined,
        italic: row.italic ? true : undefined,
      });
    }
    if (out.length >= 200) break;
  }
  return out;
}

function cleanLegacyLine(input: unknown): LegacyLineBlock | null {
  if (!input || typeof input !== "object") return null;
  const row = input as Record<string, unknown>;
  const id = typeof row.id === "string" && row.id ? row.id.slice(0, 40) : newId();
  return { id, type: asLineType(row.type), inlines: cleanInlines(row.inlines) };
}

function cleanLegacyBlocks(input: unknown): LegacyNoteBlock[] {
  if (!Array.isArray(input)) return [emptyLegacyLine()];
  const out: LegacyNoteBlock[] = [];
  for (const item of input) {
    if (!item || typeof item !== "object") continue;
    const row = item as Record<string, unknown>;
    if (row.type === "speaker") {
      const speakerId = typeof row.speakerId === "string" ? row.speakerId.slice(0, 40) : "";
      if (!speakerId) continue;
      const children = Array.isArray(row.children)
        ? row.children.map(cleanLegacyLine).filter((block): block is LegacyLineBlock => Boolean(block)).slice(0, 80)
        : [emptyLegacyLine()];
      out.push({
        id: typeof row.id === "string" && row.id ? row.id.slice(0, 40) : newId(),
        type: "speaker",
        speakerId,
        title: typeof row.title === "string" ? row.title.trim().slice(0, 80) : "",
        children: children.length ? children : [emptyLegacyLine()],
        ...(row.collapsed ? { collapsed: true as const } : {}),
      });
    } else {
      const line = cleanLegacyLine(row);
      if (line) out.push(line);
    }
    if (out.length >= 200) break;
  }
  return out.length ? out : [emptyLegacyLine()];
}

function cleanTags(input: unknown): string[] {
  if (!Array.isArray(input)) return [];
  const out: string[] = [];
  for (const item of input) {
    if (typeof item !== "string") continue;
    const tag = item.trim().replace(/^#+/, "").slice(0, 24);
    if (tag && !out.includes(tag)) out.push(tag);
    if (out.length >= 12) break;
  }
  return out;
}

/** Validate / normalize a legacy Note-shaped payload (DB / web). */
export function asLegacyNote(input: unknown): LegacyNote | null {
  if (!input || typeof input !== "object") return null;
  const row = input as Record<string, unknown>;
  const id = typeof row.id === "string" ? row.id.slice(0, 40) : "";
  if (!id) return null;
  const happenedAt =
    typeof row.happenedAt === "string" && /^\d{4}-\d{2}-\d{2}$/.test(row.happenedAt) ? row.happenedAt : todayKey();
  return {
    id,
    title: typeof row.title === "string" ? row.title.trim().slice(0, 80) : "",
    happenedAt,
    tags: cleanTags(row.tags),
    speakerId: typeof row.speakerId === "string" && row.speakerId ? row.speakerId.slice(0, 40) : null,
    blocks: cleanLegacyBlocks(row.blocks),
    visibility: row.visibility === "unlisted" ? "unlisted" : "private",
    updatedAt: typeof row.updatedAt === "string" ? row.updatedAt : new Date().toISOString(),
  };
}

function inlineToSpan(part: LegacyNoteInline): NoteDocSpan {
  if (part.type === "ref") {
    return {
      type: "bibleRef",
      bookId: part.bookId,
      chapter: part.chapter,
      verseStart: part.verseStart,
      verseEnd: part.verseEnd,
    };
  }
  const marks: TextMark[] = [];
  if (part.bold) marks.push("bold");
  if (part.italic) marks.push("italic");
  return marks.length ? { type: "text", text: part.text, marks } : { type: "text", text: part.text };
}

function spanToInline(span: NoteDocSpan): LegacyNoteInline | null {
  if (span.type === "bibleRef") {
    return {
      type: "ref",
      bookId: span.bookId,
      chapter: span.chapter,
      verseStart: span.verseStart,
      verseEnd: span.verseEnd,
    };
  }
  if (span.type === "link") {
    // Legacy store has no link node — flatten to visible text for web compat.
    return { type: "text", text: span.text || span.href };
  }
  // underline / strikethrough are V1-only; legacy keeps bold/italic only.
  return {
    type: "text",
    text: span.text,
    bold: span.marks?.includes("bold") || undefined,
    italic: span.marks?.includes("italic") || undefined,
  };
}

function lineToDoc(block: LegacyLineBlock): NoteDocLineBlock {
  return {
    id: block.id,
    type: LINE_TO_DOC[block.type] ?? "paragraph",
    spans: block.inlines.map(inlineToSpan),
  };
}

function docToLine(block: NoteDocLineBlock): LegacyLineBlock {
  return {
    id: block.id || newId(),
    type: DOC_TO_LINE[block.type] ?? "p",
    inlines: block.spans.map(spanToInline).filter((part): part is LegacyNoteInline => part != null),
  };
}

function blockToDoc(block: LegacyNoteBlock): NoteDocBlock {
  if (block.type === "speaker") {
    return {
      id: block.id,
      type: "speakerSection",
      speakerId: block.speakerId,
      title: block.title,
      ...(block.collapsed ? { collapsed: true as const } : {}),
      blocks: block.children.map(lineToDoc),
    };
  }
  return lineToDoc(block);
}

function docToBlock(block: NoteDocBlock): LegacyNoteBlock {
  if (block.type === "speakerSection") {
    const childBlocks: NoteDocLineBlock[] = block.blocks?.length ? block.blocks : [emptyDocLine()];
    const speaker: LegacySpeakerBlock = {
      id: block.id || newId(),
      type: "speaker",
      speakerId: block.speakerId,
      title: block.title || "",
      ...(block.collapsed ? { collapsed: true as const } : {}),
      children: childBlocks.map(docToLine),
    };
    return speaker;
  }
  return docToLine(block);
}

/** Legacy Postgres / zustand `Note` → native document. */
export function noteToDocument(note: LegacyNote): NoteDocumentV1 {
  return {
    schemaVersion: NOTE_DOCUMENT_SCHEMA_VERSION,
    id: note.id,
    title: note.title,
    happenedAt: note.happenedAt,
    tags: note.tags,
    noteSpeakerId: note.speakerId,
    visibility: note.visibility,
    updatedAt: note.updatedAt,
    body: {
      blocks: note.blocks.map(blockToDoc),
    },
  };
}

/** Native document → legacy `Note` for persistence in existing columns. */
export function documentToNote(doc: NoteDocumentV1): LegacyNote | null {
  const legacy = asLegacyNote({
    id: doc.id,
    title: doc.title,
    happenedAt: doc.happenedAt,
    tags: doc.tags,
    speakerId: doc.noteSpeakerId,
    visibility: doc.visibility,
    updatedAt: doc.updatedAt,
    blocks: (doc.body?.blocks?.length ? doc.body.blocks : []).map(docToBlock),
  });
  if (!legacy) return null;
  if (!legacy.blocks.length) legacy.blocks = [emptyLegacyLine()];
  return legacy;
}

/**
 * Accept either a NoteDocumentV1 or a legacy Note-shaped payload.
 * Returns a validated legacy Note (for append/web helpers) plus a lossless
 * NoteDocumentV1 (preferred for native persistence).
 */
export function coerceIncomingNote(raw: unknown): { note: LegacyNote; document: NoteDocumentV1 } | null {
  if (!raw || typeof raw !== "object") return null;
  const row = raw as Record<string, unknown>;

  if (row.schemaVersion === 1 || row.body != null) {
    const doc = normalizeDocument(row);
    if (!doc) return null;
    const note = documentToNote(doc);
    if (!note) return null;
    // Keep the cleaned V1 document (do not round-trip through legacy — that
    // would drop check/quote/underline/strikethrough/bibleRef.text).
    return { note, document: doc };
  }

  const note = asLegacyNote(raw);
  if (!note) return null;
  return { note, document: noteToDocument(note) };
}

function normalizeDocument(row: Record<string, unknown>): NoteDocumentV1 | null {
  const id = typeof row.id === "string" ? row.id.slice(0, 40) : "";
  if (!id) return null;
  const body = row.body && typeof row.body === "object" ? (row.body as { blocks?: unknown }) : null;
  const blocks = cleanDocBlocks(body?.blocks);
  const happenedAt =
    typeof row.happenedAt === "string" && /^\d{4}-\d{2}-\d{2}$/.test(row.happenedAt)
      ? row.happenedAt
      : todayKey();
  return {
    schemaVersion: NOTE_DOCUMENT_SCHEMA_VERSION,
    id,
    title: typeof row.title === "string" ? row.title.trim().slice(0, 80) : "",
    happenedAt,
    tags: cleanTags(row.tags),
    noteSpeakerId:
      typeof row.noteSpeakerId === "string" && row.noteSpeakerId
        ? row.noteSpeakerId.slice(0, 40)
        : typeof row.speakerId === "string" && row.speakerId
          ? row.speakerId.slice(0, 40)
          : null,
    visibility: row.visibility === "unlisted" ? "unlisted" : "private",
    updatedAt: typeof row.updatedAt === "string" ? row.updatedAt : new Date().toISOString(),
    body: { blocks },
  };
}

export function emptyDocument(partial?: Partial<NoteDocumentV1>): NoteDocumentV1 {
  const id = partial?.id || newId();
  return {
    schemaVersion: NOTE_DOCUMENT_SCHEMA_VERSION,
    id,
    title: partial?.title ?? "",
    happenedAt: partial?.happenedAt ?? new Date().toISOString().slice(0, 10),
    tags: partial?.tags ?? [],
    noteSpeakerId: partial?.noteSpeakerId ?? null,
    visibility: partial?.visibility ?? "private",
    updatedAt: partial?.updatedAt ?? new Date().toISOString(),
    body: partial?.body ?? {
      blocks: [{ id: newId(), type: "paragraph", spans: [] }],
    },
  };
}

/** Plain-text preview for native list rows (no HTML). */
export function documentPreview(doc: NoteDocumentV1, maxLen = 160): string {
  const parts: string[] = [];
  for (const block of doc.body.blocks) {
    if (block.type === "speakerSection") {
      for (const child of block.blocks) {
        parts.push(spansToPlain(child.spans));
      }
    } else {
      parts.push(spansToPlain(block.spans));
    }
    if (parts.join(" ").length >= maxLen) break;
  }
  const text = parts.join(" ").replace(/\s+/g, " ").trim();
  if (!text) return "";
  return text.length > maxLen ? `${text.slice(0, maxLen - 1)}…` : text;
}

function spansToPlain(spans: NoteDocSpan[]): string {
  return spans
    .map((span) => {
      // List/Caderno preview: plain body only — never surface bibleRef pills.
      if (span.type === "bibleRef") return "";
      if (span.type === "link") return span.text || span.href;
      return span.text;
    })
    .join("");
}

/** Detect V1 line types inside a raw JSON array (not legacy p/h/ul/ol). */
export function looksLikeDocBlocksArray(raw: unknown): boolean {
  if (!Array.isArray(raw) || raw.length === 0) return false;
  const first = raw[0];
  if (!first || typeof first !== "object") return false;
  const type = (first as { type?: unknown }).type;
  return (
    type === "paragraph" ||
    type === "heading" ||
    type === "bullet" ||
    type === "numbered" ||
    type === "check" ||
    type === "quote" ||
    type === "speakerSection"
  );
}
