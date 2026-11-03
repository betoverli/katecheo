# Phase 5 — WebView / Capacitor isolation (historical)

**Goal:** the iOS app never loads the Verse2Note website as its root UI.

## What was removed in Phase 5

| Surface | Before | After |
| --- | --- | --- |
| `CAPBridgeViewController` / `Verse2NoteBridgeViewController` | Full SPA at `https://verse2note.com` | Deleted |
| LiquidChrome + NativeMenus Cap plugins | Web-driven chrome over Cap WebView | Deleted (native UIKit chrome only) |
| `NativeShellMode.capacitorSite` | Hidden “Site clássico” fallback | Forced `nativePrimary` |
| Cap Push / Share / Splash / StatusBar | Used from JS | Native APNs + `UIActivityViewController` + LaunchScreen |
| Cap `server.url` | Pointed at the SPA | Removed from `capacitor.config.ts` |

## Interim (Phase 5–6): one allowed note WKWebView

**File (removed in Phase 7):** `NoteMioloEditorView.swift`

- Loaded only `/native-editor` (miolo / note body).
- Auth: Keychain Bearer via `WKUserScript`.
- Hosted by `NoteDetailViewController`.

## Phase 7 (done)

`NoteMioloEditorView` was replaced by `NativeNoteEditorView` (UITextView).
Product note editing has **zero WKWebView**. See
`docs/ios-phase7-native-editor.md` and `docs/note-document-v1.md`.

## Still using WebKit (not a product UI WebView)

- `NativeSessionBootstrap` — one-time cookie → Keychain migration via
  `WKWebsiteDataStore` (**must** run on the main thread).
- `LegacyWebStorageImporter` (Phase 6) — hidden `WKWebView` once, to read
  leftover `localStorage` from the old Cap host.
