/**
 * Former web-product routes are gone — product use is iOS-only.
 * Call from route `beforeLoad` so SSR and client navigations 308 to `/`.
 */
import { redirect } from "@tanstack/react-router";

export function redirectWebAppToLanding(): never {
  throw redirect({ to: "/", statusCode: 308 });
}

/** Paths that used to be the web product UI (and must redirect home). */
export const WEB_APP_REDIRECT_PATHS = [
  "/app",
  "/login",
  "/admin",
  "/settings",
  "/inbox",
  "/collections",
  "/collections/themes",
  "/reading",
  "/reading/all",
  "/notebook",
  "/notebook/import",
  "/groups",
  "/profile",
  "/profile/edit",
  "/profile/bible",
  "/profile/language",
  "/profile/theme",
  "/profile/notifications",
  "/profile/friends",
  "/profile/badges",
  "/profile/help",
  "/native-editor",
  "/native-phase0",
] as const;

/** Prefixes for dynamic former web-product URLs. */
export const WEB_APP_REDIRECT_PREFIXES = [
  "/collections/",
  "/c/",
  "/reading/",
  "/g/",
  "/notebook/",
  "/n/",
  "/groups/",
  "/u/",
] as const;

export function isFormerWebAppPath(pathname: string): boolean {
  const path = pathname.length > 0 ? pathname : "/";
  if ((WEB_APP_REDIRECT_PATHS as readonly string[]).includes(path)) return true;
  return WEB_APP_REDIRECT_PREFIXES.some(
    (prefix) => path === prefix.slice(0, -1) || path.startsWith(prefix),
  );
}
