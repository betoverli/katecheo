---
name: verse2note
description: >
  Generate rich-text Bible reference deep links for YouVersion, Logos, Tecarta
  and other Bible apps. Also fetch themed collections and reading-plan days
  (whole chapters). Use when the user wants to link verses, copy João 3:16 /
  John 3:16 / Juan 3:16, paste Scripture into notes, get a list by theme, or
  today's reading in a plan.
---

# Katecheo

Katecheo is a verse picker, not a Bible. It does not return full verse text. It returns
the **passage name already linked** to the user's Bible app.

If you fetched this file from `{origin}/skill.md`:
- links: `{origin}/api/link`
- collections: `{origin}/api/collections`
- reading plans: `{origin}/api/plans`
- MCP: `{origin}/api/mcp`

## Call the API — one reference or a list

```
GET {origin}/api/link?ref=John+3:16&app=youversion&locale=en
GET {origin}/api/link?refs=João+3:16|Romanos+8:28&app=youversion&locale=pt
POST {origin}/api/link
Content-Type: application/json
{ "refs": ["John 3:16", "Romans 8:28"], "app": "youversion", "locale": "en" }
```

Response `markdown` is what you paste. Example: `[John 3:16](https://www.bible.com/bible/111/JHN.3.16)`.

## Call the API — collections (themes)

160 themed lists, 14 categories. Search, open a category, or fetch a theme as linked markdown.

```
GET {origin}/api/collections?locale=pt
GET {origin}/api/collections?q=oração&locale=pt
GET {origin}/api/collections?category=doctrine&locale=pt
GET {origin}/api/collections?id=salvation&app=youversion&locale=pt
```

`id=salvation` returns `markdown` for the whole list. Snippets are only the **start** of the verse, from a free translation — not the full text.

Category ids: `doctrine`, `jesus`, `personal`, `church-life`, `home`, `seasons`, `society`, `character`, `spirit`, `last-things`, `stories`, `emotions`, `work-money`, `worship-prayer`.

## Call the API — reading plans (whole chapters)

34 plans (canonical year, chronological OT/NT/whole Bible, theme mixes, Four paths). Links are always **complete chapters**. The API does not store progress. In the web app, “My plans” lives on an optional user account.

## Human accounts vs agents

Google / email accounts exist only in the Katecheo web app (profile, My plans, Bible-app prefs). **Do not** send cookies, tokens, or a login to `/api/*` or `/api/mcp`. Those endpoints are public and anonymous.

```
GET {origin}/api/plans?locale=pt
GET {origin}/api/plans?q=evangelho&locale=pt
GET {origin}/api/plans?category=duration&locale=pt
GET {origin}/api/plans?id=gospels-30
GET {origin}/api/plans?id=gospels-30&day=1&app=youversion&locale=pt
```

`id` without `day` returns the outline (labels per day). With `day`, returns `markdown` for that day's chapters.

Plan ids: `bible-year`, `bible-90`, `nt-90`, `nt-30`, `gospels-30`, `john-21`, `matthew-28`, `luke-24`, `acts-28`, `romans-16`, `proverbs-31`, `psalms-30`, `pentateuch-90`, `paul-letters`, `chrono-bible`, `chrono-ot`, `chrono-nt`, `four-paths`, `ot-year`, `isaiah-66`, `story-40`, `hope-21`, `prayer-21`, `women-21`, `justice-14`, `wilderness-14`, `covenant-14`, `holy-week`, `advent-24`, `who-is-jesus`, `lament-14`, `wisdom-21`, `apocalyptic`, `early-church`.

Plan category ids: `duration`, `chronological`, `themes`, `gospels`, `new-testament`, `old-testament`, `books`.

## Parameters

| Name | Default | Notes |
|---|---|---|
| `ref` / `refs` | required on `/api/link` | Book + chapter + verse. PT/EN/ES names and abbreviations. |
| `q` | — | Search themes, categories, or plans. |
| `id` | — | Theme id or plan id. |
| `day` | — | Day number on `/api/plans`. |
| `category` | — | Collection or plan category id. |
| `app` | `youversion` | youversion, tecarta, logos, olive-tree, bible-gateway, blue-letter, esv, biblia-online, bible-hub, accordance, e-sword, mysword, jw-library |
| `translation` | locale default | nvi-pt, niv, rvr1960, esv, kjv, … |
| `locale` | pt | pt, en, es — labels in that language |
| `native` | false | `true` uses the app URL scheme when the app has one |

## MCP

JSON-RPC at `POST {origin}/api/mcp`.

Tools:
- `verse2note_link` — same fields as `/api/link`
- `verse2note_collection` — `q`, `id`, `category`, plus `app` / `locale` / `translation` / `native`
- `verse2note_plan` — `q`, `id`, `day`, `category`, plus `app` / `locale` / `translation` / `native`

```
{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"verse2note_link","arguments":{"ref":"John 3:16","app":"youversion","locale":"en"}}}
{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"verse2note_collection","arguments":{"id":"salvation","locale":"pt","app":"youversion"}}}
{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"verse2note_plan","arguments":{"id":"gospels-30","day":1,"locale":"pt","app":"youversion"}}}
```

## Rules

- Never invent a bible.com / Logos URL. Always call the API.
- Several references in one meeting → one `refs` call, or a collection `id`, then paste `markdown`.
- A reading-plan day → `verse2note_plan` with `id` + `day`.
- If the user names a Bible app, pass `app`. If they name a translation, pass `translation`.
- Do not fetch or quote full verse text unless the user already provided it. Collection snippets are beginnings only. Plan links are whole chapters.
