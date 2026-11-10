import { createAuthClient } from "better-auth/react";
import { runPreSignInSignOut, runSignOut } from "../../../scripts/sign-out-plan.mjs";
import { GROK_PROVIDERS } from "./providers";
import { BEARER_KEY, bearerFromStores, sanitizeBearerToken } from "./bearer-store";
import { clearSessionUser } from "./session-cache";
import { clearOutbox } from "@/lib/outbox";
import { isNativeApp } from "@/lib/native/runtime";
import { useAppStore } from "@/lib/store";

/**
 * Better Auth client for this React SPA (browser-side).
 *
 * Talks to this app's OWN Better Auth at same-origin `/api/auth/*`. In the live
 * preview the app is an embedded iframe with PARTITIONED cookies, so after a
 * popup sign-in it can't read the session cookie — it authenticates with a
 * bearer token instead (captured from the popup, see `signIn`). The `onRequest`
 * hook attaches that token when present. The website keeps using the HttpOnly
 * cookie and does not store a token. The iOS shell does: its Google session
 * never lands in the WebView cookie jar, and that jar can be empty after a
 * kill, so the same bearer is kept in localStorage.
 *
 * Better Auth 1.7 dropped `genericOAuthClient`; broker ids and built-in social
 * providers both use `signIn.social`.
 *
 * To sign out call `signOut()` below, NOT `authClient.signOut()`: the raw call
 * leaves the bearer token in place, and `onRequest` keeps re-attaching it, so
 * the visitor stays signed in.
 */
export const authClient = createAuthClient({
  fetchOptions: {
    onRequest(ctx) {
      const token = getBearerToken();
      if (token) ctx.headers.set("Authorization", `Bearer ${token}`);
      return ctx;
    },
    onSuccess(ctx) {
      // Email sign-in (and session refresh) put the signed session on
      // `set-auth-token`. The WebView cookie may not survive the next kill,
      // so the native app keeps this copy. The website must not: that header
      // would turn the HttpOnly cookie into a script-readable token.
      if (!isNativeApp()) return;
      const token = sanitizeBearerToken(ctx.response.headers.get("set-auth-token"));
      if (token) setBearerToken(token);
    },
  },
});

/**
 * True when sign-in UI should be shown — i.e. whenever `VITE_AUTH_ENABLED` is
 * not `"false"`. The shipped template sets it to `"false"`
 * (`.grok/app-env.json`), which selects the dev user (see `use-current-user`);
 * with the key removed, sign-in is real in preview (baked preview client) and
 * when deployed (injected per-app client).
 */
export const authEnabled = import.meta.env.VITE_AUTH_ENABLED !== "false";

/** The upstream providers to render sign-in buttons for. */
export { GROK_PROVIDERS };

// ── Bearer token ─────────────────────────────────────────────────────────────
// Live preview: partitioned cookies, so the session rides sessionStorage and
// dies with the iframe. Native app: Google never sets a WebView cookie, and
// the email cookie is an HttpOnly `__Host-` cookie WKWebView may drop on kill.
// localStorage survives that kill (the same store as the notebook). The
// website keeps using the cookie and does not write this key.

/** The stored bearer token, or null. */
export function getBearerToken(): string | null {
  if (typeof window === "undefined") return null;
  try {
    const native = isNativeApp();
    const found = bearerFromStores(
      native,
      window.localStorage.getItem(BEARER_KEY),
      window.sessionStorage.getItem(BEARER_KEY),
    );
    if (found.promote && found.token) window.localStorage.setItem(BEARER_KEY, found.token);
    return found.token;
  } catch {
    return null;
  }
}

function setBearerToken(token: string | null): void {
  if (typeof window === "undefined") return;
  const next = sanitizeBearerToken(token);
  try {
    if (isNativeApp()) {
      if (next) window.localStorage.setItem(BEARER_KEY, next);
      else window.localStorage.removeItem(BEARER_KEY);
      window.sessionStorage.removeItem(BEARER_KEY);
      return;
    }
    if (next) window.sessionStorage.setItem(BEARER_KEY, next);
    else window.sessionStorage.removeItem(BEARER_KEY);
  } catch {
    /* storage unavailable — ignore */
  }
}

/**
 * The sandbox live preview runs this app inside an iframe on a `*.grok-sandbox.com`
 * host, where a full-page redirect to the broker can't work — so sign-in uses a
 * popup there and a normal redirect everywhere else.
 */
function inLivePreview(): boolean {
  return (
    typeof window !== "undefined" &&
    window.location.hostname.endsWith(".grok-sandbox.com")
  );
}

/** Message the popup posts back to the opener once sign-in completes. */
type PopupMessage = { source: "grok-auth-popup"; token: string | null; error?: string };

/**
 * Start sign-in with one provider.
 *
 * Provider ids use Better Auth's social sign-in (`signIn.social`): native
 * Google (`google`, callback `/api/auth/callback/google`) or a broker id in
 * `GROK_PROVIDERS` (legacy `grok-google` only; X is not registered).
 *
 * - **Live preview** (`*.grok-sandbox.com` iframe): opens a POPUP to
 *   `/auth/popup`, served by the template Vite plugin (see `vite.config.ts` +
 *   `popup.server.ts`) — 302s to the broker/upstream login (no app chrome) and,
 *   on return, posts the session bearer token back. We store it and refresh the
 *   session; no top-level navigation of the iframe to the broker.
 * - **Deployed** (and local non-iframe): a normal full-page redirect into the broker.
 *
 * Either way it clears any existing local session FIRST so switching providers
 * actually switches identity.
 */
export async function signIn(
  providerId: string,
  opts: { callbackURL?: string; errorCallbackURL?: string } = {},
): Promise<void> {
  const callbackURL = opts.callbackURL ?? "/";
  const errorCallbackURL = opts.errorCallbackURL ?? "/";

  // Open the popup SYNCHRONOUSLY on the user gesture — before any await
  // (including signOut). Awaiting first drops user-gesture privilege in some
  // browsers when the opener is a cross-origin live-preview iframe.
  const popup = inLivePreview() ? openSignInPopup(providerId) : null;

  // Clear any prior session so switching providers actually switches identity.
  // Bounded because the popup is already open — a request that never settles
  // would leave it hanging — but bounded PER ENVIRONMENT: only the server can
  // end a deployed session, so cutting it short at the preview's 1.5s would
  // start OAuth with the old session still live.
  await runPreSignInSignOut({
    livePreview: inLivePreview(),
    hasBearer: Boolean(getBearerToken()),
    requestSignOut: () => authClient.signOut(),
    clearToken: () => setBearerToken(null),
  });

  if (isNativeApp()) {
    // The WebView must not call signIn.social. That would navigate the shell
    // itself, and Google's redirect_uri would follow whatever host the shell
    // happened to be on. The system browser always starts on the canonical site.
    const { signInWithNativeBrowser } = await import("@/lib/native/auth");
    await signInWithNativeBrowser(providerId, callbackURL);
    return;
  }

  if (inLivePreview()) {
    if (!popup) throw new Error("Pop-up blocked — allow pop-ups for sign-in");
    const token = await waitForPopupToken(popup);
    if (!token) throw new Error("Sign-in was cancelled or failed");
    setBearerToken(token);
    // Refresh the client session store with the bearer attached (onRequest).
    // Avoid a full iframe reload when we're already on the destination — that
    // reload was the slow "still loading after the popup closed" feeling.
    try {
      await authClient.getSession();
    } catch {
      /* session store will recover on next useSession fetch */
    }
    if (typeof window !== "undefined") {
      const dest = new URL(callbackURL, window.location.origin);
      const here = window.location;
      if (dest.origin !== here.origin || dest.pathname !== here.pathname || dest.search !== here.search) {
        window.location.href = callbackURL;
      }
    }
    return;
  }

  const { data, error } = await authClient.signIn.social({
    provider: providerId,
    callbackURL,
    errorCallbackURL,
    disableRedirect: true,
  });
  if (error) throw new Error(error.message ?? "Sign-in failed");
  if (data?.url) {
    window.location.assign(data.url);
    return;
  }
  throw new Error("Sign-in did not return a redirect URL");
}

/**
 * Open `/auth/popup` in a new window. Must run synchronously inside the click
 * handler (no await before this). The path is served by the template Vite
 * plugin (`authPopupPlugin` in vite.config.ts) — NOT by a React route.
 *
 * Opens the real URL directly (not about:blank → assign). From a cross-origin
 * iframe the about:blank dance often fails on the first click and the window
 * ends up showing the app shell.
 */
function openSignInPopup(providerId: string): Window | null {
  const origin = window.location.origin;
  const url = `${origin}/auth/popup?providerId=${encodeURIComponent(providerId)}`;
  // Unique name per attempt so a prior attempt stuck on the SPA is not reused.
  const name = `grok-signin-${Date.now()}`;
  return window.open(url, name, "popup,width=500,height=650");
}

/**
 * Wait for the popup's completion page to postMessage the session bearer (or
 * for the user to dismiss the popup).
 */
function waitForPopupToken(popup: Window): Promise<string | null> {
  return new Promise((resolve) => {
    const origin = window.location.origin;
    let settled = false;
    let closeTimer: number | undefined;
    const settle = (token: string | null) => {
      if (settled) return;
      settled = true;
      cleanup();
      resolve(token);
    };
    const onMessage = (event: MessageEvent) => {
      if (event.origin !== origin) return;
      const data = event.data as PopupMessage | undefined;
      if (!data || data.source !== "grok-auth-popup") return;
      settle(data.token ?? null);
    };
    // Fallback when the user dismisses the popup. Grace period lets the
    // completion page's postMessage win over a racing `popup.closed`.
    const pollTimer = window.setInterval(() => {
      if (!popup.closed) return;
      window.clearInterval(pollTimer);
      closeTimer = window.setTimeout(() => settle(null), 400);
    }, 300);
    function cleanup() {
      window.clearInterval(pollTimer);
      if (closeTimer !== undefined) window.clearTimeout(closeTimer);
      window.removeEventListener("message", onMessage);
    }
    window.addEventListener("message", onMessage);
  });
}

/**
 * Store the session token handed back by the iOS system browser and continue.
 * The website never calls this: there is no token to adopt outside the app.
 */
export async function adoptNativeSession(token: string, callbackURL: string): Promise<void> {
  setBearerToken(token);
  try {
    await authClient.getSession();
  } catch {
    /* session store recovers on the next read */
  }
  try {
    const { syncBearerToKeychain } = await import("@/lib/native/phase0");
    await syncBearerToKeychain();
  } catch {
    /* Keychain sync is best-effort on older binaries */
  }
  window.location.assign(callbackURL);
}

/**
 * Where sign-out lands. `/` sends an onboarded person straight back into the
 * app, and an unfinished profile then covers that page again. `/login` is
 * public, so the profile gate cannot paint over it.
 */
export const SIGN_OUT_PATH = "/login";

async function clearNativeAuthCookies(): Promise<void> {
  const { registerPlugin } = await import("@capacitor/core");
  const cookies = registerPlugin<{ clearAllCookies(): Promise<void> }>("CapacitorCookies");
  await cookies.clearAllCookies();
}

/**
 * Sign out of THIS app's local session, clear the preview token, then open
 * the login screen.
 *
 * Use this, never `authClient.signOut()` — see the note on `authClient`.
 * Sequencing lives in `scripts/sign-out-plan.mjs` so it can be unit-tested.
 *
 * **Rejects when deployed if the server never confirms.** There the session is
 * an HttpOnly cookie only the server can clear, so redirecting anyway would
 * report a sign-out that did not happen. Callers must catch it and let the
 * visitor retry. In the live preview the local clear is sufficient, so it
 * always resolves.
 */
export async function signOut(redirectTo = SIGN_OUT_PATH): Promise<void> {
  clearSessionUser();
  clearOutbox();
  await runSignOut({
    livePreview: inLivePreview(),
    hasBearer: Boolean(getBearerToken()),
    // Better Auth resolves with `{ error }` instead of rejecting, so surface a
    // failed response as a rejection for the sequence to act on.
    requestSignOut: async () => {
      const { error } = await authClient.signOut();
      if (error) throw new Error(error.message ?? "Sign-out failed");
    },
    clearToken: () => setBearerToken(null),
    redirect: async () => {
      // A render while the request was in flight may have written the cached
      // user back. Drop it again, and drop the local profile, before the next
      // page reads either one.
      clearSessionUser();
      useAppStore.getState().clearAccount();
      if (isNativeApp()) {
        await Promise.race([
          clearNativeAuthCookies().catch(() => undefined),
          new Promise((resolve) => setTimeout(resolve, 1500)),
        ]);
      }
      window.location.assign(redirectTo);
    },
  });
}
