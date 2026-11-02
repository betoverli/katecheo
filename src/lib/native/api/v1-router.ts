/**
 * Pure path matching for `/api/native/v1/*` (unit-tested without a database).
 */

export type NativeV1Route =
  | { kind: "catalog" }
  | { kind: "session" }
  | { kind: "notes"; noteId?: string }
  | { kind: "note-groups"; noteId: string }
  | { kind: "speakers"; speakerId?: string }
  | { kind: "devices-apns" }
  | { kind: "auth-providers" }
  | { kind: "auth-claim" }
  | { kind: "auth-email" }
  | { kind: "auth-apple" }
  | { kind: "auth-from-cookie" }
  | { kind: "auth-sign-out" }
  | { kind: "groups"; groupId?: string }
  | { kind: "group-notes"; groupId: string; noteId?: string }
  | { kind: "me" }
  | { kind: "prefs" }
  | { kind: "notify-prefs" }
  | { kind: "account-export" }
  | { kind: "account-delete" }
  | { kind: "not-found"; path: string };

/**
 * @param splat - path after `/api/native/v1/` (no leading slash), e.g. `notes/abc`
 */
export function matchNativeV1Route(splat: string): NativeV1Route {
  const raw = splat.replace(/^\/+|\/+$/g, "");
  if (!raw) return { kind: "catalog" };

  const parts = raw.split("/").filter(Boolean);
  const [a, b, c, d] = parts;

  if (a === "session" && parts.length === 1) return { kind: "session" };
  if (a === "notes" && parts.length === 1) return { kind: "notes" };
  if (a === "notes" && parts.length === 2 && b) return { kind: "notes", noteId: b };
  if (a === "notes" && b && c === "groups" && parts.length === 3) {
    return { kind: "note-groups", noteId: b };
  }
  if (a === "speakers" && parts.length === 1) return { kind: "speakers" };
  if (a === "speakers" && parts.length === 2 && b) return { kind: "speakers", speakerId: b };
  if (a === "devices" && b === "apns" && parts.length === 2) return { kind: "devices-apns" };
  if (a === "auth" && b === "providers" && parts.length === 2) return { kind: "auth-providers" };
  if (a === "auth" && b === "claim" && parts.length === 2) return { kind: "auth-claim" };
  if (a === "auth" && b === "email" && parts.length === 2) return { kind: "auth-email" };
  if (a === "auth" && b === "apple" && parts.length === 2) return { kind: "auth-apple" };
  if (a === "auth" && b === "from-cookie" && parts.length === 2) return { kind: "auth-from-cookie" };
  if (a === "auth" && b === "sign-out" && parts.length === 2) return { kind: "auth-sign-out" };

  if (a === "groups" && parts.length === 1) return { kind: "groups" };
  if (a === "groups" && parts.length === 2 && b) return { kind: "groups", groupId: b };
  if (a === "groups" && b && c === "notes" && parts.length === 3) {
    return { kind: "group-notes", groupId: b };
  }
  if (a === "groups" && b && c === "notes" && d && parts.length === 4) {
    return { kind: "group-notes", groupId: b, noteId: d };
  }

  if (a === "me" && parts.length === 1) return { kind: "me" };
  if (a === "prefs" && parts.length === 1) return { kind: "prefs" };
  if (a === "notify-prefs" && parts.length === 1) return { kind: "notify-prefs" };
  if (a === "account" && b === "export" && parts.length === 2) return { kind: "account-export" };
  if (a === "account" && b === "delete" && parts.length === 2) return { kind: "account-delete" };

  return { kind: "not-found", path: raw };
}

/** Auth routes that do not require a prior bearer (sign-in + provider catalog). */
export function isPublicNativeAuthRoute(route: NativeV1Route): boolean {
  return (
    route.kind === "auth-providers" ||
    route.kind === "auth-claim" ||
    route.kind === "auth-email" ||
    route.kind === "auth-apple" ||
    route.kind === "auth-from-cookie" ||
    route.kind === "catalog"
  );
}

export function methodAllowed(route: NativeV1Route, method: string): boolean {
  const m = method.toUpperCase();
  if (m === "OPTIONS") return true;
  switch (route.kind) {
    case "catalog":
      return m === "GET";
    case "session":
      return m === "GET";
    case "notes":
      if (!route.noteId) return m === "GET" || m === "POST";
      return m === "GET" || m === "PATCH" || m === "PUT" || m === "DELETE";
    case "note-groups":
      return m === "GET";
    case "speakers":
      if (!route.speakerId) return m === "GET" || m === "POST";
      return m === "DELETE";
    case "devices-apns":
      return m === "POST" || m === "DELETE";
    case "auth-providers":
      return m === "GET";
    case "auth-claim":
    case "auth-email":
    case "auth-apple":
    case "auth-from-cookie":
    case "auth-sign-out":
      return m === "POST";
    case "groups":
      if (!route.groupId) return m === "GET" || m === "POST";
      return m === "GET" || m === "PATCH" || m === "PUT" || m === "DELETE";
    case "group-notes":
      if (!route.noteId) return m === "GET" || m === "POST";
      return m === "DELETE";
    case "me":
      return m === "GET" || m === "PATCH" || m === "PUT";
    case "prefs":
      return m === "GET" || m === "PATCH" || m === "PUT" || m === "POST";
    case "notify-prefs":
      return m === "GET" || m === "PATCH" || m === "PUT" || m === "POST";
    case "account-export":
      return m === "GET";
    case "account-delete":
      return m === "POST" || m === "DELETE";
    case "not-found":
      return false;
  }
}
