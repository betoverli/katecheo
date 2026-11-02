# Verse2Note iOS — native migration plan

**Product decision (Beto, 2026-11-01):** In the Verse2Note **iOS app**, ship native UI (Swift / SwiftUI / UIKit) for shell and screens first; the note body / editor (*miolo*) may stay in a WKWebView through mid phases. **Final phase (approved same day):** the note body/editor also becomes fully native — **no WebView at all**. Note content is stored and served in a **platform-neutral, versioned JSON document** (not HTML), so a future Android app can read/write the same format. The public website is out of scope for compatibility — no requirement to keep the Capacitor “full site in a WebView” model. Native screens talk to **verse2note.com** (Better Auth + JSON API) directly.

**Baseline:** `main` after TF88 fixes (PR #34). Current app: Capacitor 8 shell loading `https://verse2note.com`.

---

## 1. Goals and non-goals

### Goals

- Native navigation, lists, sheets, alerts, settings, groups, profile, verses/reading chrome.
- **Interim:** note *miolo* may remain a WKWebView (Phases 1–5) while chrome is native.
- **Final:** note editor is native too; zero WebView in the app.
- Note body is a **versioned JSON document** (Bible refs, speakers/sections, marks, links) shared by iOS and future Android — API never serves HTML as the source of truth.
- Same backend and user accounts; bearer session in Keychain (URLSession + any interim editor WebView).
- Offline-capable notebook preserved or improved.
- Ship in **small TestFlight phases**, each usable.

### Non-goals (this program)

- Rewriting the public marketing site or forcing web parity with native UX.
- Building Android UI in this track (format must stay Android-ready).
- Keeping Capacitor as the long-term UI host once native screens replace it.

### End state (sketch) — after final phase

```text
┌─────────────────────────────────────────────┐
│  Native UIKit / SwiftUI app (no WKWebView)  │
│  Tabs · lists · sheets · note editor        │
│         │ URLSession + Bearer               │
│         ▼                                   │
│  https://verse2note.com                     │
│  Better Auth + /api/native/v1               │
│  NoteDocumentV1 JSON (schemaVersion)        │
└─────────────────────────────────────────────┘
```

Interim (Phases 1–5) still embeds a miolo WKWebView that consumes the **same** `NoteDocumentV1` JSON.

---

## 2. Inventory — current screens, modals, flows

Legend: **Primary** = main tab shell; **Secondary** = pushed / detail; **System** = auth handoff / platform; **Web-only today** = marketing/legal (low priority for native).

### 2.1 App shell (already partly native)

| Piece | Today | Notes |
| --- | --- | --- |
| Tabs | LiquidChrome `UITabBar` via `APP_TABS` | verses `/app`, groups `/groups`, notebook `/notebook`, reading `/reading`, profile `/profile` (`src/lib/tabs.ts`) |
| Top bar | LiquidChrome `UINavigationBar` | title, back, search, trailing `…` / badge |
| FAB | LiquidChrome FAB + optional `UIMenu` | compose, new group |
| Menus / alerts | `NativeMenus` plugin | `menu` / `sheet` / `alert` / `prompt` |
| Login browser | `NativeAuth` + ASWebAuthenticationSession | Google |
| Share | `@capacitor/share` | note swipe share |
| Push | `@capacitor/push-notifications` + APNs | `saveApnsDevice` / `dropApnsDevice` |
| Splash / status | Capacitor SplashScreen + StatusBar | LaunchScreen storyboard |

### 2.2 Auth / session

| Flow | Route / entry | UI today |
| --- | --- | --- |
| Login screen | `/login` | Google + email/password (web form) |
| Native Google start | `/auth/native-start` | redirect into OAuth |
| Native return / done | `/auth/native-return`, `/auth/native-done` | handoff seal → bearer in WebView `localStorage` |
| Native config | `/auth/native-config` | `{ universalLinks: false }` JSON |
| Gate / onboarding | `app-shell` overlays | `Onboarding`, `CompleteProfile`, `Coachmarks` |

### 2.3 Notebook

| Flow | Route / UI | Class |
| --- | --- | --- |
| Note list | `/notebook/` · `NotebookHome` | Primary |
| Note editor (full page) | `/notebook/$id` · `NotebookEditor` | Secondary (tab bar hidden) |
| Shared / granted note | `/n/$id` | Secondary / deep link |
| Import | `/notebook/import` | Secondary |
| Compose | FAB UIMenu or ActionSheet: Nova nota / Importar | Modal |
| Swipe share / delete | `NoteCard` + confirm ActionSheet | Gesture + alert |
| Note settings | `…` → Settings → ViewportSheet (date, tags, note speaker) | Sheet (web after TF88) |
| Speakers manage / pick | `NotebookSpeakerSheet` | Sheet |
| First-speaker scope | ActionSheet whole-note vs section | Alert/sheet |
| Publish to group | editor / group flows | Sheet / actions |
| Send to friend | `SendToFriendButton` | Sheet |
| Offline banner | `OfflineBanner` | Chrome |

### 2.4 Groups

| Flow | Route / UI | Class |
| --- | --- | --- |
| Groups home | `/groups/` · `NotebookGroupsHome` | Primary |
| Group detail | `/groups/$id` · `NotebookGroupDetail` | Primary |
| Novo grupo | FAB / button → ViewportSheet (name + private/listed) | Sheet |
| Join / members / roles / delete | group detail | Sheets + ActionSheet |
| Group notes list | inside detail | List |

### 2.5 Verses / collections

| Flow | Route | Class |
| --- | --- | --- |
| Verse picker + preview | `/app` | Primary |
| Collections index / themes / category / detail | `/collections/*` | Primary |
| User / shared collection | `/c/$id` | Primary |
| Save to collection | `SaveToCollectionButton` | Sheet |
| Open in Bible app | link / `NativeAuth.open` | External |

### 2.6 Reading plans

| Flow | Route | Class |
| --- | --- | --- |
| Reading home | `/reading/` | Primary |
| Plan lists / detail | `/reading/all`, `/reading/category/$id`, `/reading/$id` | Primary |
| Join plan group | `/g/$id` | Secondary / invite |
| Day marks | in plan detail | Local + outbox |

### 2.7 Profile / settings

| Flow | Route | Class |
| --- | --- | --- |
| Profile home | `/profile/` | Primary |
| Edit / friends / badges / bible / language / theme / notifications / help | `/profile/*` | Primary |
| Delete account | ActionSheet on profile | Alert |
| Public profile | `/u/$handle` | Secondary (optional native later) |
| Inbox | `/inbox` → redirect `/app` | NotifyBell sheet instead |

### 2.8 Notifications

| Flow | UI | Class |
| --- | --- | --- |
| In-app notify list | `NotifyBell` ViewportSheet | Overlay |
| Notify settings / prompt | `NotifySettings`, `NotifyPrompt` | Settings |
| APNs register / tap | `src/lib/native/push.ts` | System |

### 2.9 Low priority / web-only for native app

| Flow | Route | Note |
| --- | --- | --- |
| Marketing landing | `/` | Native cold start → login or last tab |
| Privacy / about / for-ai | `/privacy`, `/about`, `/for-ai` | Optional Safari or later Settings links |
| Admin | `/admin` | Keep web or omit from App Store binary |

---

## 3. Backend surface — what native must call

### 3.1 Reality check

Almost all app data I/O today is **TanStack Start `createServerFn` RPC** (cookie and/or `Authorization: Bearer`), not a documented public REST JSON API. Capacitor works because the WebView shares origin with those RPCs.

**Native URLSession cannot call `createServerFn` as-is** without reverse-engineering the Start RPC protocol. Therefore the migration **requires a first-class HTTP JSON API** (or an official RPC bridge) on verse2note.com that wraps the same handlers / SQL.

Public HTTP routes that already exist under `src/routes/api`:

| Path | Role |
| --- | --- |
| `/api/auth/*` | Better Auth (session, OAuth callbacks, bearer plugin) |
| `/api/link` | Bible link helper (public) |
| `/api/collections` | Catalog collections (public) |
| `/api/plans` | Catalog plans (public) |
| `/api/mcp` | MCP JSON-RPC for AI tools (public) |

Auth handoff (non-`/api`): `/auth/native-start|done|return|config`.

### 3.2 Domains to expose for native (from existing `createServerFn`s)

Proposed mount: **`/api/native/v1/...`** (name TBD), all JSON, all authenticated unless marked public. Reuse `authMiddleware` / `getSessionUser` (cookie **or** Bearer).

| Domain | Existing server fns (representative) | Native needs |
| --- | --- | --- |
| **Session** | Better Auth `/api/auth/get-session`, sign-in, sign-out | GET session, email sign-in, sign-out; keep native Google handoff |
| **Notes** | `listMyNotes`, `upsertMyNote`, `deleteMyNote`, `getSharedNote`, `getGrantedNote`, `listGrantedNotes`, `sendNoteToFriend` | Full CRUD + share/grant |
| **Speakers** | `listMySpeakers`, `upsertMySpeaker`, `deleteMySpeaker` | Full CRUD |
| **Groups** | `listMyGroups`, `searchListedGroups`, `getNotebookGroup`, `create/update/join/decide/role/leave/delete`, `listGroupMembers`, `listGroupNotes`, `listMyNoteGroups`, `publishNoteToGroup`, `unpublishNoteFromGroup` | Full surface |
| **Friends / links** | `searchPeople`, `listLinks`, `getLinkStatus`, `request/accept/declineLink`, `sendPlanToFriend`, `sendCollectionToFriend` | Full surface |
| **User collections** | list/get/create/update/remix/delete/granted + `getSharedCollection` | Full surface |
| **Plan groups / marks** | invite/join/get/list + mark/reset + preview | Full surface |
| **Prefs / profile** | `getPrefs`, `savePrefs`, `syncAccountPhoto` | GET/PATCH prefs; avatar |
| **Account** | `exportMyData`, `deleteMyAccount`, `addEmailPassword` | Settings |
| **Notify (web push)** | VAPID, prefs, subscriptions, list, unread, markRead | Optional on iOS (APNs is primary) |
| **APNs** | `saveApnsDevice`, `dropApnsDevice` | Keep |
| **Badges** | `getMyBadges`, `getPublicProfile` | Profile |
| **Handoff** | `mintNativeHandoff`, `claimNativeHandoff`, `abortNativeReturn` | Keep for Google login |
| **Catalog (public)** | `/api/link`, `/api/collections`, `/api/plans` | Reuse as-is for verses/reading chrome |

### 3.3 Missing endpoints / work to add

| Gap | Why | Suggested work |
| --- | --- | --- |
| **Native JSON API layer** | Swift cannot use Start RPC | Add `/api/native/v1/*` (or OpenAPI) wrapping existing handlers; shared zod schemas |
| **Batch sync / delta** | Native offline store needs efficient pull | `GET /notes?since=` / `GET /speakers?since=` (or single `/sync`) — **new** |
| **Note snapshot for editor bootstrap** | Miolo WebView needs one note + speakers without full SPA | `GET /notes/:id` returning note JSON (+ speakers) — thin wrapper |
| **Editor session bootstrap** | Inject auth into miolo WebView | `POST /auth/native-editor-token` short-lived token **or** cookie set on dedicated editor origin path — **new** |
| **Device-aware notify** | In-app notify list without web push | Ensure notify list APIs work with Bearer (already authMiddleware) |
| **Multipart / photo** | Profile photo sync | Confirm `syncAccountPhoto` shape; may need upload URL |
| **Rate limits / pagination** | Mobile chatty clients | Explicit page cursors on list endpoints where today `limit 200` |

No need to expose `/api/mcp` or admin stats to the App Store client.

---

## 4. Auth and session — native ↔ note WebView

### 4.1 Today

- Better Auth at `/api/auth/*` with **bearer plugin** + HttpOnly `__Host-grok-auth.*` cookies.
- **Native Google:** ASWebAuthenticationSession → handoff → `claimNativeHandoff` → bearer in WebView `localStorage` (`grok-auth.bearer-token`).
- **Email/password:** sets `__Host-` cookie inside WKWebView; may also copy bearer.
- Capacitor remote URL keeps cookies on `https://verse2note.com`.

### 4.2 Target

| Store | Owner | Use |
| --- | --- | --- |
| **Keychain** | Native app | Long-lived refresh/session bearer (or session token) |
| **URLSession** | Native screens | `Authorization: Bearer …` on `/api/native/v1/*` and `/api/auth/*` |
| **Note miolo WKWebView** | Embedded only on note screen | Must authenticate to same API for autosave / outbox flush |

### 4.3 Bridging auth into the miolo WebView

Recommended approach (phased):

1. **Editor bundle** hosted at e.g. `https://verse2note.com/native-editor/` (minimal HTML/JS: block editor only — extract from `notebook-doc` / `notebook-line`, not full app shell).
2. On open note, native:
   - Loads that URL (or `about:blank` + injected bundle later).
   - Calls `POST /api/native/v1/editor/session` with the Keychain bearer → server sets a short-lived HttpOnly cookie **or** returns a one-time code.
   - Native injects via `WKUserScript`: `window.__V2N_EDITOR__ = { noteId, bearerOrCode, locale, bridge: true }`.
3. Editor JS uses Bearer (from injected token) for `upsertMyNote`-equivalent API; never relies on full SPA router.
4. On logout, native clears Keychain, wipes WebView data store for editor, calls sign-out API.

**Do not** keep the full Capacitor site WebView as the session source of truth once native lists exist.

Google login can keep ASWebAuthenticationSession + handoff; email/password should move to native form posting to Better Auth HTTP APIs, storing bearer in Keychain.

---

## 5. Offline strategy

### 5.1 Today (web)

- Zustand persist (`cita-settings`): notes (≤200), speakers (≤80), prefs, collections, plan marks, etc.
- Outbox (`verse2note-outbox`): `note.*`, `speaker.*`, `collection.*`, `plan.*`, `prefs` → flush via server fns when online.
- Service worker caches app shell; **never** `/api/*`.
- Groups / friends / notify are mostly online-only (+ `groups-cache`).

### 5.2 Target (native)

| Data | Store | Sync |
| --- | --- | --- |
| Notes + speakers | On-device DB (SwiftData or SQLite) | Outbox mirror of today’s jobs; pull via `/sync` or list+since |
| Prefs / theme / locale | UserDefaults or DB | PATCH prefs |
| Own collections + plan marks | DB + outbox | Same job types |
| Groups / members / friends | Network-first cache | Optional disk cache; stale-while-revalidate |
| Catalog (books, plans, collections) | Bundle or CDN cache | Public `/api/collections`, `/api/plans` |
| Editor miolo | May keep a small JS local draft buffer | Must call native bridge `noteDidChange` so native owns durable save |

**Rule:** Native owns durable note records. The WebView is a **projection + editor** of `blocks` (and maybe title live-edit), not the source of truth for the note list.

Cold start offline: native shell + local DB works without Capacitor `offline.html`. Editor WebView needs a **bundled** editor assets fallback (ship editor www in the app binary) so opening a note offline still types.

---

## 6. Note miolo WebView — embed and communication

### 6.1 What stays web (until Phase 7)

- Block document editing UX in a WKWebView through Phases 1–6: paragraphs, headings, lists, inline bible refs, speaker sections, caret/selection.
- **Data** is still `NoteDocumentV1` JSON over the API — the WebView is only a renderer/editor, not an HTML store.
- Phase 7 replaces this with a native editor; see §8 Phase 7.

### 6.2 What becomes native on the note screen

- Nav bar (back, title display policy, `…` menu).
- Note settings (date, tags, whole-note speaker).
- Speaker pick / manage sheets.
- Share, send to friend, publish to group.
- Delete note, offline indicator, keyboard chrome insets (Liquid Glass / safe area).

### 6.3 Bridge protocol (draft)

Bidirectional `WKScriptMessageHandler` + `window.webkit.messageHandlers.v2n`:

| Direction | Message | Purpose |
| --- | --- | --- |
| N→W | `loadNote { note, speakers, readOnly }` | Initial document |
| N→W | `setSpeakers` / `setReadOnly` / `focus` | Updates from native sheets |
| W→N | `noteChanged { note }` (debounced) | Native writes DB + outbox |
| W→N | `openRef { bookId, chapter, … }` | Native opens Bible / preview |
| W→N | `requestSpeaker { blockId? }` | Native presents speaker sheet |
| W→N | `height` / `scroll` / `focus` | Layout / keyboard |
| W→N | `ready` / `error` | Lifecycle |

Editor URL must not show site chrome, tab bar, or marketing. Strip to a dedicated editor entry (new route or static package under `native/editor`).

---

## 7. Note document model (platform-neutral)

**Invariant from Phase 0 onward:** `/api/native/v1` note payloads are **`NoteDocumentV1`**, not HTML and not the web editor’s DOM. Postgres may still store the legacy web `Note.blocks` tree; the API **converts at the boundary** (`noteToDocument` / `documentToNote` / `coerceIncomingNote` in `src/lib/native/api/note-document.ts`).

### 7.1 Wire shape (`schemaVersion: 1`)

```json
{
  "schemaVersion": 1,
  "id": "…",
  "title": "…",
  "happenedAt": "YYYY-MM-DD",
  "tags": ["…"],
  "noteSpeakerId": null,
  "visibility": "private",
  "updatedAt": "ISO-8601",
  "body": {
    "blocks": [
      {
        "id": "…",
        "type": "paragraph",
        "spans": [
          { "type": "text", "text": "Hello ", "marks": ["bold"] },
          { "type": "bibleRef", "bookId": "JHN", "chapter": 3, "verseStart": 16, "verseEnd": null }
        ]
      },
      {
        "id": "…",
        "type": "speakerSection",
        "speakerId": "…",
        "title": "João",
        "blocks": [{ "id": "…", "type": "heading", "spans": [{ "type": "text", "text": "…" }] }]
      }
    ]
  }
}
```

| Concept | `type` / field | Notes |
| --- | --- | --- |
| Schema | `schemaVersion` | Integer; bump only on breaking changes |
| Line blocks | `paragraph` \| `heading` \| `bullet` \| `numbered` | Maps from legacy `p`/`h`/`ul`/`ol` |
| Inline text | `spans[].type = "text"` + optional `marks: ["bold","italic"]` | |
| Bible ref | `spans[].type = "bibleRef"` | `bookId` + chapter + verse range (OSIS-style ids) |
| Link (reserved) | `spans[].type = "link"` | Optional; flattened to text when writing legacy store |
| Speaker section | `speakerSection` | Nested line blocks; not HTML |
| Whole-note speaker | `noteSpeakerId` | Distinct from section speakers |

### 7.2 Conversion

| Direction | Function |
| --- | --- |
| Legacy `Note` → API | `noteToDocument` |
| API → legacy `Note` (DB) | `documentToNote` |
| POST/PATCH body | `coerceIncomingNote` (accepts V1 **or** legacy for gradual clients) |

Android and native iOS editors must **write V1**; they must not depend on HTML serialization.

### 7.3 Why this lands in Phase 0

If Phase 0 shipped HTML or web-only block JSON, the final native editor and Android would force a redo. Serving `NoteDocumentV1` now locks the contract early while the interim miolo WebView (and spike) consume the same JSON.

---

## 8. Phased PR order (each shippable to TestFlight)

Principles: **small**, **user-visible or foundational**, **reversible feature flags** where possible (`NativeShellMode`: `capacitorSite` → `hybrid` → `nativePrimary`). Website deploy can add APIs without removing the old SPA.

### Phase 0 — Foundation (API + auth + flag) — **first shippable scope**

**Goal:** Native binary can authenticate and call a real JSON API that already speaks **`NoteDocumentV1`**; editor extraction spike can load one note. App UI can still be Capacitor site behind a flag.

**Scope:**

1. **API:** `/api/native/v1` with:
   - `GET /session`
   - `GET/POST /notes`, `GET/PATCH/DELETE /notes/:id` (**NoteDocumentV1**)
   - `GET/POST /speakers`, `DELETE /speakers/:id`
   - `POST/DELETE /devices/apns`
   - Catalog at `GET /api/native/v1` documenting `noteSchemaVersion`
2. **Auth:** Keychain bearer; sync from WebView session; URLSession client
3. **Editor spike:** `/native-editor` + native modal WKWebView (bridge `v2n`); debug page `/native-phase0`
4. **Feature flag:** `NativeShellMode` default **`capacitorSite`** (no UX change until toggled)
5. **Tests:** router + document conversion + ios:check

**Out of scope for Phase 0:** Replacing tab UI; full native editor.

**Exit criteria:** Sign-in works; `GET /api/native/v1/notes` with Keychain bearer returns `NoteDocumentV1[]`; spike editor loads a note; default flag leaves current UI unchanged.

---

### Phase 1 — Native notebook list + open note (hybrid) — **default app experience**

**Goal:** Caderno is native by default (`NativeShellMode.hybrid`). Capacitor full-site remains a **hidden fallback** (⋯ → “Site clássico”, or other tabs’ “Usar app clássico”).

- Native `UITabBar` / notebook list (file cache seeded from `/api/native/v1`).
- Swipe share / delete + confirm (`UIAlertController`), compose, native search.
- Tapping a row pushes native note chrome (nav, `…`, settings, speakers, share, delete) + **miolo WKWebView** on `/native-editor` speaking `NoteDocumentV1`.
- Other tabs: “Em breve” placeholders with optional Cap modal / classic fallback.
- Offline: read/edit from `LocalNoteCache`; save retries when online.
- **Exit criteria:** Cold start opens native Caderno; list loads via Bearer; open/edit/delete/share work; classic Cap still reachable without being default.

### Phase 2 — Native groups

- Groups home + detail + create/join/members native.
- Publish/unpublish note to group from native note chrome.
- APIs: full groups section of §3.2.

### Phase 3 — Native profile, settings, friends, APNs UI

- **Shipped (this phase):** Profile hub, edit name/handle/email, language, theme, bible app prefs, notify toggles, sign-out (Keychain), delete account + export via `/api/native/v1/me|prefs|notify-prefs|account/*`.
- Friends search/request/accept — follow-up (still web / Em breve).
- Push permission + device registration (already partially native; notify screen shows APNs device count).

### Phase 4 — Native verses + reading

- **Shipped (Versículos):** native picker (livro → capítulo → versículo), temas/coleções, abrir na Bíblia (`UIApplication.open` + prefs do Perfil), compartilhar/copiar, adicionar `bibleRef` à nota de hoje (`POST /verses/append` → NoteDocumentV1), minhas listas (`/my-collections*`). API pública: `/bible/books|apps|link|themes`.
- Reading plans + day marks — follow-up (aba Leitura ainda Em breve).

### Phase 5 — Remove Capacitor site host

- App no longer sets `server.url` to the full SPA as the root UI.
- Capacitor optional only for plugins **or** replace Share/Push/Splash with pure native and drop Capacitor dependency.
- Delete LiquidChrome-as-WebView-chrome path; keep design language in SwiftUI/UIKit.
- Miolo WKWebView may still remain until Phase 7.

### Phase 6 — Hardening (pre-final editor)

- Sync conflicts, migration from WebView localStorage/outbox → native DB (one-time import).
- Performance, accessibility, TestFlight rollout.
- Confirm all note I/O uses `NoteDocumentV1` only (no HTML paths left in native clients).

### Phase 7 — FINAL: native note editor (no WebView)

**Goal:** Delete the last WKWebView. Note body editing is 100% Swift/SwiftUI (or UIKit TextKit), reading/writing **`NoteDocumentV1`** via `/api/native/v1`.

**Scope:**

1. Native block editor: paragraphs, headings, lists, text marks, bible-ref chips, speaker sections, caret/selection, undo.
2. Open/save/autosave against the same API schema (no conversion to HTML).
3. Remove `/native-editor` WebView spike and any embedded miolo WebView from Phase 1.
4. Document Android parity: same JSON schema; no iOS-only storage quirks.
5. Optional later: bump `schemaVersion` only if the native editor needs breaking fields (prefer additive).

**Exit criteria:** A TestFlight build with **zero WKWebView** can create and edit a note end-to-end; exported JSON opens on a second client (future Android) without HTML scraping.

---

## 9. First phase — explicit checklist

**Phase 0 PR(s) should include:**

| Item | Done when |
| --- | --- |
| Design doc (`docs/ios-native-migration.md`) incl. document model + Phase 7 | This file |
| `/api/native/v1` + Bearer + **NoteDocumentV1** | Notes/speakers/session |
| Conversion tests legacy ↔ V1 | `note-document.test.ts` |
| Swift Keychain + APIClient + shell flag (default off) | Device smoke |
| Editor spike + `/native-phase0` debug page | Loads note / demo |
| TF: default UI unchanged | `NativeShellMode.capacitorSite` |

**Do not** in Phase 0: rewrite all tabs, remove website, ship full native editor (that is Phase 7).

---

## 10. Risks

| Risk | Mitigation |
| --- | --- |
| Start RPC lock-in | Phase 0 JSON API mandatory before UI rewrite |
| Dual write (WebView localStorage vs native DB) | Single writer: native owns notes; one-time import |
| Auth cookie vs bearer confusion | Bearer Keychain primary for native |
| Scope creep | Phases 1–4 ordered; Phase 7 last |
| HTML creeping into API | NoteDocumentV1 only; conversion at boundary |
| Schema redo for Android | schemaVersion + documented spans from Phase 0 |
| App Review / login | Keep ASWebAuthenticationSession for Google |

---

## 11. References (code)

- Tabs: `src/lib/tabs.ts`
- Capacitor host: `capacitor.config.ts`, `ios/App/App/NativeShell.swift`
- Chrome / menus: `LiquidChrome.swift`, `NativeMenus.swift`
- Notes legacy: `src/lib/notebook.ts`, `notebook-cloud.ts`, `outbox.ts`
- **Native document:** `src/lib/native/api/note-document.ts`
- **Native API:** `src/lib/native/api/v1*.ts`, `src/routes/api/native/v1/`
- Auth / push: `src/lib/auth/*`, `src/lib/native/handoff.ts`, `push.ts`

---

## 12. Decision log

| Date | Decision |
| --- | --- |
| 2026-11-01 | Native shell first; miolo may stay WebView mid-migration; website compatibility not required; plan-first PR. |
| 2026-11-01 | Phase 0 = API + Keychain + editor spike + flag default Capacitor UI. |
| 2026-11-01 | **Final Phase 7:** note editor fully native (no WebView). Content = versioned platform-neutral JSON from Phase 0 (`NoteDocumentV1`), not HTML. |
| 2026-11-01 | Phase 0 merged (TF 95). **Phase 1:** native Caderno default (`hybrid`); Cap site hidden fallback. |
| 2026-11-01 | Phase 1 TF 98: add **native login** (Google ASWebAuth, Apple ASAuthorization, email) + cookie→Keychain migration + sign-out. |
| 2026-11-02 | Phase 2 Grupos merged (#41). **Phase 3:** native Perfil + Configurações (`/me`, `/prefs`, `/notify-prefs`, `/account/delete|export`). |
| 2026-11-02 | **Phase 4 Versículos:** native picker + temas + append `bibleRef` (`/bible/*`, `/verses/append`, `/my-collections*`). Leitura (plans) fica para follow-up. |
