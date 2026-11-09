import { useEffect } from "react";
import { isNativeApp } from "@/lib/native/runtime";

const WARM_ROUTES = [
  "/",
  "/app",
  "/notebook",
  "/notebook/import",
  "/groups",
  "/reading",
  "/collections",
  "/profile",
  "/inbox",
  "/login",
];

/**
 * Registers the app-shell service worker and warms the offline cache.
 *
 * On the website this powers offline PWA. Inside the Capacitor iOS shell the
 * WebView still loads https://katecheo.app (auth cookies / Google return),
 * so the same SW can keep the shell and notebook routes cached after the
 * first online open. Cold launch with zero cache still needs the native
 * offline.html fallback.
 */
export function OfflineSupport() {
  useEffect(() => {
    if (!("serviceWorker" in navigator)) return;
    const standalone =
      window.matchMedia("(display-mode: standalone)").matches ||
      ("standalone" in navigator &&
        Boolean((navigator as Navigator & { standalone?: boolean }).standalone));
    if (import.meta.env.DEV && !standalone && !isNativeApp()) return;

    let cancelled = false;
    void (async () => {
      try {
        const reg = await navigator.serviceWorker.register("/sw.js");
        if (cancelled) return;
        const ready = await navigator.serviceWorker.ready;
        if (cancelled) return;
        const urls = [
          ...WARM_ROUTES,
          ...[...document.querySelectorAll("script[src], link[rel='stylesheet']")].map((node) => {
            if (node instanceof HTMLScriptElement) return node.src;
            if (node instanceof HTMLLinkElement) return node.href;
            return "";
          }).filter((href): href is string => Boolean(href) && href.startsWith(window.location.origin)),
        ];
        ready.active?.postMessage({ type: "PRECACHE_URLS", urls: [...new Set(urls)] });
        // Keep the registration alive across navigations in the native shell.
        void reg.update().catch(() => {});
      } catch {
        /* registration is best-effort */
      }
    })();
    return () => {
      cancelled = true;
    };
  }, []);
  return null;
}
