import type { CapacitorConfig } from "@capacitor/cli";

/**
 * Phase 7 — Capacitor is **not** the iOS UI host. Note editing is fully native
 * (`NativeNoteEditorView` / UITextView). No product WKWebView for notes.
 *
 * This file remains so `npx cap` tooling does not break for residual
 * package metadata. It does **not** set `server.url` to the full SPA.
 * See `docs/ios-phase7-native-editor.md`.
 */
const config: CapacitorConfig = {
  appId: "com.verse2note.app",
  appName: "Katecheo",
  // Minimal placeholder www — not loaded as the app root.
  webDir: "native/www",
  backgroundColor: "#000000",
  ios: {
    contentInset: "never",
    backgroundColor: "#000000",
    scheme: "verse2note",
  },
  // Intentionally no `server.url` — the native app must not host the site.
  plugins: {},
};

export default config;
