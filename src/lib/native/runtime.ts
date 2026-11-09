/**
 * Pure helpers for the iOS shell. Safe to import from the website: nothing
 * here touches Capacitor unless `isNativeApp()` is true, and that is only
 * true inside the Capacitor WebView.
 */

const BIBLE_HOSTS = new Set([
  "bible.com",
  "tecartabible.com",
  "ref.ly",
  "biblegateway.com",
  "blueletterbible.org",
  "esv.org",
  "bibliaonline.com.br",
  "biblehub.com",
]);

const CUSTOM_SCHEMES = new Set([
  "youversion",
  "bible",
  "olivetree",
  "accord",
  "e-sword",
  "mysword",
  "jwlibrary",
]);

type CapacitorGlobal = {
  isNativePlatform?: () => boolean;
  getPlatform?: () => string;
};

/** Capacitor appends this token so the hosted site can tell the iOS shell apart. */
export const NATIVE_IOS_UA_TOKEN = "Verse2NoteIOS";

export function isNativeAppUa(ua: string | null | undefined): boolean {
  return typeof ua === "string" && ua.includes(NATIVE_IOS_UA_TOKEN);
}

export function isNativeApp(): boolean {
  if (typeof window === "undefined") return false;
  const cap = (window as Window & { Capacitor?: CapacitorGlobal }).Capacitor;
  return cap?.getPlatform?.() === "ios" && cap.isNativePlatform?.() === true;
}

/**
 * Native iOS shell (Capacitor WebView). Prefer `isNativeApp()` when Capacitor
 * is ready; this also accepts the UA / `native-ios` class so the first paint
 * (and SSR via UA) can skip the marketing landing before the bridge loads.
 */
export function isNativeShell(): boolean {
  if (typeof window === "undefined") return false;
  if (isNativeApp()) return true;
  if (document.documentElement.classList.contains("native-ios")) return true;
  return isNativeAppUa(navigator.userAgent);
}

export type LinkDecision = "stay" | "external";

function isBibleHost(hostname: string): boolean {
  const host = hostname.toLowerCase().replace(/^www\./, "");
  return BIBLE_HOSTS.has(host) || host === "bible.com" || host.endsWith(".bible.com");
}

function isAppHost(hostname: string, pageHost: string): boolean {
  const host = hostname.toLowerCase();
  if (host === pageHost.toLowerCase()) return true;
  return (
    host === "katecheo.app" ||
    host === "www.katecheo.app" ||
    host === "verse2note.com" ||
    host === "www.verse2note.com"
  );
}

/**
 * Decide whether a URL should leave the WebView and open through iOS
 * (universal links and Bible-app schemes) or stay inside the app.
 * Same-window navigations to other sites stay put so an in-app redirect
 * is not sent to Safari by accident. Bible hosts and custom schemes always
 * leave, because WKWebView will not hand a universal link to YouVersion.
 */
export function classifyLink(href: string, target = "", pageUrl = "https://katecheo.app/"): LinkDecision {
  let url: URL;
  let page: URL;
  try {
    page = new URL(pageUrl);
    url = new URL(href, page);
  } catch {
    return "stay";
  }
  const scheme = url.protocol.replace(/:$/, "").toLowerCase();
  if (scheme === "javascript" || scheme === "about" || scheme === "blob" || scheme === "data") return "stay";
  if (CUSTOM_SCHEMES.has(scheme) || scheme === "mailto" || scheme === "tel" || scheme === "sms") return "external";
  if (scheme !== "http" && scheme !== "https") return "external";
  if (isAppHost(url.hostname, page.hostname)) return "stay";
  if (isBibleHost(url.hostname)) return "external";
  if (target === "_blank") return "external";
  return "stay";
}
