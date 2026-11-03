# Phase 5 — WebView / Capacitor isolation

**Goal:** the iOS app never loads the Verse2Note website as its root UI.

## What was removed

| Surface | Before | After |
| --- | --- | --- |
| `CAPBridgeViewController` / `Verse2NoteBridgeViewController` | Full SPA at `https://verse2note.com` | Deleted |
| LiquidChrome + NativeMenus Cap plugins | Web-driven chrome over Cap WebView | Deleted (native UIKit chrome only) |
| `NativeShellMode.capacitorSite` | Hidden “Site clássico” fallback | Forced `nativePrimary` |
| Cap Push / Share / Splash / StatusBar | Used from JS | Native APNs + `UIActivityViewController` + LaunchScreen |
| Cap `server.url` | Pointed at the SPA | Removed from `capacitor.config.ts` |

## The one allowed WKWebView

**File:** `ios/App/App/NoteMioloEditorView.swift`

- Loads only `/native-editor` (miolo / note body).
- Auth: Keychain Bearer injected via `WKUserScript` into `localStorage` /
  `sessionStorage` / `window.__V2N_EDITOR__.bearer` — **not** Cap cookies.
- Bridge: `WKScriptMessageHandler` name `v2n`.
- Hosted by `NoteDetailViewController` (native chrome: nav, ⋯, settings, share).

`ios-check` fails CI if Cap bridges reappear, or if `WKWebView` appears outside
`NoteMioloEditorView` and the Phase 6 one-time `LegacyWebStorageImporter`.

## Still using WebKit (not a product UI WebView)

- `NativeSessionBootstrap` — one-time cookie → Keychain migration via
  `WKWebsiteDataStore` (**must** run on the main thread).
- `LegacyWebStorageImporter` (Phase 6) — hidden `WKWebView` once, to read
  leftover `localStorage` (`cita-settings`, `verse2note-outbox`) from the old
  Cap `https://verse2note.com` host.

## Phase 7

Replace `NoteMioloEditorView` with a fully native editor reading/writing
`NoteDocumentV1`. Then delete this file and the `/native-editor` route from
the app path.
