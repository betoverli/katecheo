# NoteDocumentV1 — platform-neutral note body

Canonical wire format for Katecheo native clients (iOS now, Android later).
Served and accepted by `/api/native/v1` notes endpoints. **Never HTML** as the
source of truth.

- TypeScript: `src/lib/native/api/note-document.ts`
- Swift: `NativeAPIClient.NoteDocument` (+ `NoteDocumentCodec`)
- `schemaVersion: 1` — bump only for breaking changes. Additive optional fields
  (e.g. `bibleRef.text`, `check.checked`, underline mark) stay on v1.

## Top-level document

```json
{
  "schemaVersion": 1,
  "id": "note_abc",
  "title": "Culto de domingo",
  "happenedAt": "2026-11-02",
  "tags": ["igreja"],
  "noteSpeakerId": null,
  "visibility": "private",
  "updatedAt": "2026-11-02T18:00:00.000Z",
  "body": { "blocks": [ /* … */ ] }
}
```

| Field | Type | Notes |
| --- | --- | --- |
| `schemaVersion` | `1` | Required |
| `id` | string ≤40 | Client or server id |
| `title` | string ≤80 | First line in the Apple Notes–style editor |
| `happenedAt` | `YYYY-MM-DD` | Note date (not created-at) |
| `tags` | string[] ≤12 | No `#` prefix |
| `noteSpeakerId` | string \| null | Whole-note speaker chip |
| `visibility` | `private` \| `unlisted` | |
| `updatedAt` | ISO-8601 | Optimistic concurrency on upsert |
| `body.blocks` | Block[] | Document content |

## Blocks

### Line blocks

`type`: `paragraph` | `heading` | `bullet` | `numbered` | `check` | `quote`

```json
{
  "id": "blk1",
  "type": "paragraph",
  "spans": [
    { "type": "text", "text": "Olá ", "marks": ["bold"] },
    {
      "type": "bibleRef",
      "bookId": "JHN",
      "chapter": 3,
      "verseStart": 16,
      "verseEnd": null,
      "text": "João 3:16"
    }
  ]
}
```

Checklist:

```json
{
  "id": "c1",
  "type": "check",
  "checked": false,
  "spans": [{ "type": "text", "text": "Ler o capítulo" }]
}
```

### Speaker section

```json
{
  "id": "s1",
  "type": "speakerSection",
  "speakerId": "spk1",
  "title": "Pr. João",
  "collapsed": false,
  "blocks": [
    { "id": "h1", "type": "heading", "spans": [{ "type": "text", "text": "Introdução" }] }
  ]
}
```

`collapsed` is an **optional** boolean (default expanded / omitted). Clients may hide the
nested `blocks` in the UI when `collapsed === true` and still persist the children on
write. Unknown clients should ignore the field (forward compatible; no schema bump).

## Spans (inline)

| `type` | Fields | Marks / notes |
| --- | --- | --- |
| `text` | `text`, optional `marks` | `bold`, `italic`, `underline`, `strikethrough` |
| `bibleRef` | `bookId`, `chapter`, `verseStart`, `verseEnd`, optional `text` | OSIS-style ids (`JHN`, `GEN`, …). `text` is display label. |
| `link` | `href`, `text` | Optional; clients should validate schemes. |

## Server storage

Postgres column `notebook_notes.blocks` stores either:

1. **V1 envelope** (preferred after Phase 7 writes):
   `{"v":1,"blocks":[…NoteDocBlock]}`
2. **Legacy** web `Note.blocks` JSON (`p`/`h`/`ul`/`ol`/`speaker` + `inlines`)
3. **HTML string** (rare / imported) — lazy-converted on read to V1; original kept in
   `notebook_notes.blocks_backup` (never deleted)

Conversion helpers: `noteToDocument`, `documentToNote`, `coerceIncomingNote`,
`htmlToDocumentBlocks`, `documentFromRow`.

## Android checklist

1. Decode `schemaVersion === 1` + `body.blocks`.
2. Ignore unknown block/span types and unknown marks (forward compatible).
3. Render `bibleRef` as a tappable chip; open the user’s Bible app with the same
   deep-link prefs pattern as iOS (`POST /api/native/v1/bible/link`).
4. Write V1 only on save (`POST /api/native/v1/notes`).
5. Do not depend on HTML or iOS attributed-string details.

## Examples

See also `src/lib/native/api/note-document.test.ts` and
`src/lib/native/api/html-to-document.test.ts`.
