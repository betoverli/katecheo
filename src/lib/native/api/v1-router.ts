/**
 * Pure path matching for `/api/native/v1/*` (unit-tested without a database).
 */

export type NativeV1Route =
  | { kind: "catalog" }
  | { kind: "session" }
  | { kind: "notes"; noteId?: string }
  | { kind: "notes-granted" }
  | { kind: "note-groups"; noteId: string }
  | { kind: "links" }
  | { kind: "links-accept" }
  | { kind: "links-decline" }
  | { kind: "links-request" }
  | { kind: "links-search" }
  | { kind: "notifications" }
  | { kind: "notifications-read" }
  | { kind: "notifications-summary" }
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
  | { kind: "group-members"; groupId: string; userId?: string }
  | { kind: "group-members-decide"; groupId: string }
  | { kind: "group-members-role"; groupId: string }
  | { kind: "me" }
  | { kind: "prefs" }
  | { kind: "notify-prefs" }
  | { kind: "account-export" }
  | { kind: "account-delete" }
  | { kind: "bible-books" }
  | { kind: "catalog-versions" }
  | { kind: "bible-apps" }
  | { kind: "bible-link" }
  | { kind: "bible-themes" }
  | { kind: "verses-append" }
  | { kind: "my-collections"; collectionId?: string }
  | { kind: "my-collections-save" }
  | { kind: "plans" }
  | { kind: "plans-mark" }
  | { kind: "plans-reset" }
  | { kind: "plans-start" }
  | { kind: "plans-stop" }
  | { kind: "plans-invite" }
  | { kind: "plans-join" }
  | { kind: "plans-group"; groupId: string }
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
  // Must precede notes/:id so "granted" is not treated as a note id.
  if (a === "notes" && b === "granted" && parts.length === 2) return { kind: "notes-granted" };
  if (a === "notes" && parts.length === 2 && b) return { kind: "notes", noteId: b };
  if (a === "notes" && b && c === "groups" && parts.length === 3) {
    return { kind: "note-groups", noteId: b };
  }
  if (a === "links" && parts.length === 1) return { kind: "links" };
  if (a === "links" && b === "accept" && parts.length === 2) return { kind: "links-accept" };
  if (a === "links" && b === "decline" && parts.length === 2) return { kind: "links-decline" };
  if (a === "links" && b === "request" && parts.length === 2) return { kind: "links-request" };
  if (a === "links" && b === "search" && parts.length === 2) return { kind: "links-search" };
  if (a === "notifications" && parts.length === 1) return { kind: "notifications" };
  if (a === "notifications" && b === "summary" && parts.length === 2) {
    return { kind: "notifications-summary" };
  }
  if (a === "notifications" && b === "read" && parts.length === 2) {
    return { kind: "notifications-read" };
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
  if (a === "groups" && b && c === "members" && parts.length === 3) {
    return { kind: "group-members", groupId: b };
  }
  if (a === "groups" && b && c === "members" && d === "decide" && parts.length === 4) {
    return { kind: "group-members-decide", groupId: b };
  }
  if (a === "groups" && b && c === "members" && d === "role" && parts.length === 4) {
    return { kind: "group-members-role", groupId: b };
  }
  if (a === "groups" && b && c === "members" && d && parts.length === 4) {
    return { kind: "group-members", groupId: b, userId: d };
  }

  if (a === "me" && parts.length === 1) return { kind: "me" };
  if (a === "prefs" && parts.length === 1) return { kind: "prefs" };
  if (a === "notify-prefs" && parts.length === 1) return { kind: "notify-prefs" };
  if (a === "account" && b === "export" && parts.length === 2) return { kind: "account-export" };
  if (a === "account" && b === "delete" && parts.length === 2) return { kind: "account-delete" };

  if (a === "catalog" && b === "versions" && parts.length === 2) return { kind: "catalog-versions" };
  if (a === "bible" && b === "books" && parts.length === 2) return { kind: "bible-books" };
  if (a === "bible" && b === "apps" && parts.length === 2) return { kind: "bible-apps" };
  if (a === "bible" && b === "link" && parts.length === 2) return { kind: "bible-link" };
  if (a === "bible" && b === "themes" && parts.length === 2) return { kind: "bible-themes" };
  if (a === "verses" && b === "append" && parts.length === 2) return { kind: "verses-append" };
  if (a === "my-collections" && b === "save" && parts.length === 2) {
    return { kind: "my-collections-save" };
  }
  if (a === "my-collections" && parts.length === 1) return { kind: "my-collections" };
  if (a === "my-collections" && parts.length === 2 && b) {
    return { kind: "my-collections", collectionId: b };
  }

  if (a === "plans" && parts.length === 1) return { kind: "plans" };
  if (a === "plans" && b === "mark" && parts.length === 2) return { kind: "plans-mark" };
  if (a === "plans" && b === "reset" && parts.length === 2) return { kind: "plans-reset" };
  if (a === "plans" && b === "start" && parts.length === 2) return { kind: "plans-start" };
  if (a === "plans" && b === "stop" && parts.length === 2) return { kind: "plans-stop" };
  if (a === "plans" && b === "invite" && parts.length === 2) return { kind: "plans-invite" };
  if (a === "plans" && b === "join" && parts.length === 2) return { kind: "plans-join" };
  if (a === "plans" && b === "groups" && c && parts.length === 3) {
    return { kind: "plans-group", groupId: c };
  }

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
    route.kind === "catalog" ||
    route.kind === "catalog-versions" ||
    route.kind === "bible-books" ||
    route.kind === "bible-apps" ||
    route.kind === "bible-link" ||
    route.kind === "bible-themes" ||
    route.kind === "plans"
  );
}

export function methodAllowed(route: NativeV1Route, method: string): boolean {
  const m = method.toUpperCase();
  if (m === "OPTIONS") return true;
  switch (route.kind) {
    case "catalog":
      return m === "GET";
    case "catalog-versions":
      return m === "GET";
    case "session":
      return m === "GET";
    case "notes":
      if (!route.noteId) return m === "GET" || m === "POST";
      return m === "GET" || m === "PATCH" || m === "PUT" || m === "DELETE";
    case "notes-granted":
      return m === "GET";
    case "links":
    case "links-search":
      return m === "GET";
    case "links-accept":
    case "links-decline":
    case "links-request":
      return m === "POST";
    case "notifications":
    case "notifications-summary":
      return m === "GET";
    case "notifications-read":
      return m === "POST";
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
    case "group-members":
      if (!route.userId) return m === "GET";
      return m === "DELETE";
    case "group-members-decide":
    case "group-members-role":
      return m === "POST";
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
    case "bible-books":
    case "bible-apps":
    case "bible-themes":
      return m === "GET";
    case "bible-link":
      return m === "GET" || m === "POST";
    case "verses-append":
    case "my-collections-save":
      return m === "POST";
    case "my-collections":
      if (!route.collectionId) return m === "GET" || m === "POST";
      return m === "GET" || m === "PATCH" || m === "PUT" || m === "DELETE";
    case "plans":
    case "plans-group":
      return m === "GET";
    case "plans-mark":
    case "plans-reset":
    case "plans-start":
    case "plans-stop":
    case "plans-invite":
    case "plans-join":
      return m === "POST";
    case "not-found":
      return false;
  }
}
