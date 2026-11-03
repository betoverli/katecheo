import type { CapacitorConfig } from "@capacitor/cli";

/**
 * Phase 5 — Capacitor is **not** the iOS UI host anymore.
 *
 * The App Store binary is a native UIKit tab shell. The only WKWebView is
 * `NoteMioloEditorView`, which loads `https://verse2note.com/native-editor`
 * with a Keychain Bearer (not Cap cookies / CAPBridgeViewController).
 *
 * This file remains so `npx cap` tooling does not break for residual
 * package metadata. It does **not** set `server.url` to the full SPA.
 * Push / Share / Splash / StatusBar plugins are unused on iOS (native
 * replacements). See `docs/ios-phase5-webview.md`.
 */
const config: CapacitorConfig = {
  appId: "com.verse2note.app",
  appName: "Verse2Note",
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
