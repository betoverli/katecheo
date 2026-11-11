import { UnauthorizedError } from "@/lib/auth/verify.server";
import { trustedWebOrigins } from "@/lib/site";
import { matchNativeV1Route, methodAllowed } from "./v1-router";
import {
  MAX_BODY_BYTES,
  authAppleSchema,
  authClaimSchema,
  authEmailSchema,
  authEmailForgotPasswordSchema,
  authEmailResetPasswordSchema,
  authEmailSignUpSchema,
  bibleLinkBodySchema,
  clampNotificationLimit,
  collectionCreateSchema,
  collectionSaveSchema,
  collectionUpdateSchema,
  devicesApnsDeleteSchema,
  devicesApnsPostSchema,
  groupCreateSchema,
  groupMemberDecideSchema,
  groupMemberRoleSchema,
  groupNotePublishSchema,
  groupUpdateSchema,
  handleBodySchema,
  mePatchSchema,
  notePatchSchema,
  noteUpsertSchema,
  notificationsReadSchema,
  notifyPrefsSchema,
  parseWithSchema,
  planIdSchema,
  planJoinSchema,
  planMarkSchema,
  prefsPatchSchema,
  speakerUpsertSchema,
  versesAppendSchema,
  type ParseFail,
} from "./v1-schemas";
import type { z } from "zod";

const CORS_METHODS = "GET, POST, PATCH, PUT, DELETE, OPTIONS";
const CORS_HEADERS = "Authorization, Content-Type, Cookie, If-None-Match";

function corsHeadersFor(request: Request): Record<string, string> {
  const origin = request.headers.get("origin")?.trim() ?? "";
  // Native iOS URLSession typically sends no Origin — allow without ACAO.
  if (!origin) {
    return {
      "Access-Control-Allow-Methods": CORS_METHODS,
      "Access-Control-Allow-Headers": CORS_HEADERS,
      Vary: "Origin",
    };
  }
  const allowed = new Set(trustedWebOrigins());
  if (!allowed.has(origin)) {
    return {
      "Access-Control-Allow-Methods": CORS_METHODS,
      "Access-Control-Allow-Headers": CORS_HEADERS,
      Vary: "Origin",
    };
  }
  return {
    "Access-Control-Allow-Origin": origin,
    "Access-Control-Allow-Methods": CORS_METHODS,
    "Access-Control-Allow-Headers": CORS_HEADERS,
    Vary: "Origin",
  };
}

export function json(
  data: unknown,
  status = 200,
  extraHeaders: Record<string, string> = {},
  request?: Request,
): Response {
  const cors = request ? corsHeadersFor(request) : {
    "Access-Control-Allow-Methods": CORS_METHODS,
    "Access-Control-Allow-Headers": CORS_HEADERS,
  };
  return new Response(JSON.stringify(data), {
    status,
    headers: {
      "Content-Type": "application/json; charset=utf-8",
      "Cache-Control": "no-store",
      ...cors,
      ...extraHeaders,
    },
  });
}

export function preflight(request: Request): Response {
  return new Response(null, { status: 204, headers: corsHeadersFor(request) });
}

async function readBody(request: Request): Promise<unknown> {
  const lengthHeader = request.headers.get("content-length");
  if (lengthHeader) {
    const n = Number(lengthHeader);
    if (Number.isFinite(n) && n > MAX_BODY_BYTES) return Symbol.for("body-too-large");
  }
  const text = await request.text();
  if (text.length > MAX_BODY_BYTES) return Symbol.for("body-too-large");
  if (!text) return null;
  try {
    return JSON.parse(text) as unknown;
  } catch {
    return Symbol.for("invalid-json");
  }
}

type Respond = (data: unknown, status?: number, extraHeaders?: Record<string, string>) => Response;

async function readAndParse<T>(
  request: Request,
  schema: z.ZodType<T>,
  respond: Respond,
  opts?: { emptyAs?: unknown },
): Promise<T | Response> {
  const body = await readBody(request);
  if (body === Symbol.for("body-too-large")) return respond({ ok: false, error: "body_too_large" }, 413);
  if (body === Symbol.for("invalid-json")) return respond({ ok: false, error: "invalid_json" }, 400);
  const raw = body == null && opts?.emptyAs !== undefined ? opts.emptyAs : body;
  const parsed = parseWithSchema(schema, raw);
  if (!parsed.ok) {
    const fail = parsed as ParseFail;
    return respond({ ok: false, error: fail.error, issues: fail.issues }, 400);
  }
  return parsed.data;
}

/**
 * Dispatch a native v1 request. Dynamic-imports the server module so tests can
 * exercise the router without loading Postgres.
 */
export async function handleNativeV1Request(request: Request, splat: string): Promise<Response> {
  if (request.method.toUpperCase() === "OPTIONS") return preflight(request);

  const respond = (
    data: unknown,
    status = 200,
    extraHeaders: Record<string, string> = {},
  ) => json(data, status, extraHeaders, request);

  const route = matchNativeV1Route(splat);
  if (route.kind === "not-found") {
    return respond({ ok: false, error: "not_found", path: route.path }, 404);
  }
  if (!methodAllowed(route, request.method)) {
    return respond({ ok: false, error: "method_not_allowed" }, 405);
  }

  if (route.kind === "catalog") {
    const { nativeV1Catalog } = await import("./v1.server");
    return respond(nativeV1Catalog());
  }

  if (route.kind === "catalog-versions") {
    const { nativeCatalogVersions } = await import("@/lib/bible/catalog-version");
    // Tiny fingerprint payload — clients poll this on foreground instead of full catalogs.
    return respond(nativeCatalogVersions(), 200, {
      "Cache-Control": "public, max-age=60, stale-while-revalidate=600",
    });
  }

  try {
    // Public reading plans catalog (same data as /api/plans).
    if (route.kind === "plans") {
      const plansApi = await import("./v1-plans.server");
      const url = new URL(request.url);
      const result = plansApi.resolveNativePlans(url.searchParams);
      return respond(result, result.ok ? 200 : 400);
    }

    // Public bible catalog (no bearer required — same as /api/link + /api/collections).
    if (
      route.kind === "bible-books" ||
      route.kind === "bible-apps" ||
      route.kind === "bible-link" ||
      route.kind === "bible-themes"
    ) {
      const versesApi = await import("./v1-verses.server");
      const url = new URL(request.url);
      if (route.kind === "bible-books") {
        // Auth-free static catalog — safe to cache at the edge/CDN for a day.
        // Clients also SWR locally; this is optional and does not change payload.
        return respond(versesApi.listBibleBooks(url.searchParams.get("locale") ?? undefined), 200, {
          "Cache-Control": "public, max-age=86400, stale-while-revalidate=604800",
          ETag: `"bible-books-v1-${url.searchParams.get("locale") ?? "pt"}"`,
        });
      }
      if (route.kind === "bible-apps") {
        return respond(versesApi.listBibleApps(url.searchParams.get("locale") ?? undefined));
      }
      if (route.kind === "bible-themes") {
        const { queryCollectionsFromSearch } = await import("@/lib/bible/collections-api");
        return respond(versesApi.resolveNativeThemes(queryCollectionsFromSearch(url.searchParams)));
      }
      // bible-link
      let linkQuery: {
        refs: string[];
        app?: string;
        translation?: string;
        locale?: string;
        native?: boolean;
      };
      if (request.method.toUpperCase() === "POST") {
        const payload = await readAndParse(request, bibleLinkBodySchema, respond, { emptyAs: {} });
        if (payload instanceof Response) return payload;
        const { collectRefs } = await import("@/lib/bible/link-api");
        const refs = collectRefs([
          payload.ref as string | undefined,
          payload.refs as string | string[] | undefined,
        ]);
        const nativeRaw = payload.native;
        linkQuery = {
          refs,
          app: typeof payload.app === "string" ? payload.app : undefined,
          translation: typeof payload.translation === "string" ? payload.translation : undefined,
          locale: typeof payload.locale === "string" ? payload.locale : undefined,
          native:
            nativeRaw === true || nativeRaw === 1 || nativeRaw === "1" || nativeRaw === "true"
              ? true
              : nativeRaw === false || nativeRaw === 0 || nativeRaw === "0" || nativeRaw === "false"
                ? false
                : undefined,
        };
      } else {
        const { queryFromSearch } = await import("@/lib/bible/link-api");
        linkQuery = queryFromSearch(url.searchParams);
        if (!url.searchParams.has("native")) linkQuery.native = undefined;
      }
      // Optional bearer → merge user prefs.
      let userId: string | null = null;
      try {
        const { resolveNativeUser } = await import("./v1.server");
        const user = await resolveNativeUser(request);
        userId = user.id;
      } catch {
        userId = null;
      }
      const result = await versesApi.resolveNativeLink(userId, linkQuery);
      return respond(result, result.ok ? 200 : 400);
    }

    // Public auth endpoints (no bearer yet). Catalog already returned above.
    if (
      route.kind === "auth-providers" ||
      route.kind === "auth-claim" ||
      route.kind === "auth-email" ||
      route.kind === "auth-email-sign-up" ||
      route.kind === "auth-email-forgot-password" ||
      route.kind === "auth-email-reset-password" ||
      route.kind === "auth-apple" ||
      route.kind === "auth-from-cookie"
    ) {
      const authApi = await import("./v1-auth.server");
      if (route.kind === "auth-providers") {
        return respond(authApi.listNativeAuthProviders());
      }
      if (route.kind === "auth-claim") {
        const payload = await readAndParse(request, authClaimSchema, respond);
        if (payload instanceof Response) return payload;
        const result = await authApi.claimNativeBearer(request, payload);
        return respond(result, result.ok ? 200 : result.status);
      }
      if (route.kind === "auth-email") {
        const payload = await readAndParse(request, authEmailSchema, respond);
        if (payload instanceof Response) return payload;
        const result = await authApi.signInEmailNative(request, payload);
        return respond(result, result.ok ? 200 : result.status);
      }
      if (route.kind === "auth-email-sign-up") {
        const payload = await readAndParse(request, authEmailSignUpSchema, respond);
        if (payload instanceof Response) return payload;
        const result = await authApi.signUpEmailNative(request, payload);
        return respond(result, result.ok ? 200 : result.status);
      }
      if (route.kind === "auth-email-forgot-password") {
        const payload = await readAndParse(request, authEmailForgotPasswordSchema, respond);
        if (payload instanceof Response) return payload;
        const result = await authApi.forgotPasswordNative(request, payload);
        return respond(result, result.ok ? 200 : result.status);
      }
      if (route.kind === "auth-email-reset-password") {
        const payload = await readAndParse(request, authEmailResetPasswordSchema, respond);
        if (payload instanceof Response) return payload;
        const result = await authApi.resetPasswordNative(request, payload);
        return respond(result, result.ok ? 200 : result.status);
      }
      if (route.kind === "auth-apple") {
        const payload = await readAndParse(request, authAppleSchema, respond);
        if (payload instanceof Response) return payload;
        const result = await authApi.signInAppleNative(request, payload);
        return respond(result, result.ok ? 200 : result.status);
      }
      const result = await authApi.bearerFromCookie(request);
      return respond(result, result.ok ? 200 : result.status);
    }

    if (route.kind === "auth-sign-out") {
      const authApi = await import("./v1-auth.server");
      const result = await authApi.signOutNative(request);
      return respond(result, result.ok ? 200 : result.status);
    }

    const {
      resolveNativeUser,
      getNativeSession,
      listNotesForUser,
      getNoteForUser,
      getNoteWithSpeakersForUser,
      upsertNoteForUser,
      deleteNoteForUser,
      listSpeakersForUser,
      upsertSpeakerForUser,
      deleteSpeakerForUser,
      saveApnsDevice,
      dropApnsDevice,
    } = await import("./v1.server");

    const user = await resolveNativeUser(request);
    const method = request.method.toUpperCase();

    if (route.kind === "session") {
      return respond(await getNativeSession(user.id, user.email));
    }

    if (route.kind === "notes") {
      if (!route.noteId) {
        if (method === "GET") return respond({ ok: true, notes: await listNotesForUser(user.id) });
        const body = await readAndParse(request, noteUpsertSchema, respond);
        if (body instanceof Response) return body;
        const result = await upsertNoteForUser(user.id, body);
        if (!result.ok) return respond(result, result.error === "limit" || result.error === "conflict" ? 409 : 400);
        return respond(result, 201);
      }
      if (method === "GET") {
        const packed = await getNoteWithSpeakersForUser(user.id, route.noteId);
        if (!packed) return respond({ ok: false, error: "missing" }, 404);
        return respond({ ok: true, ...packed });
      }
      if (method === "DELETE") {
        const result = await deleteNoteForUser(user.id, route.noteId);
        return respond(result, result.ok ? 200 : 404);
      }
      // Mutations require ownership — grants are read-only via GET.
      const patchBody = await readAndParse(request, notePatchSchema, respond, { emptyAs: {} });
      if (patchBody instanceof Response) return patchBody;
      const existing = await getNoteForUser(user.id, route.noteId);
      if (!existing) return respond({ ok: false, error: "missing" }, 404);
      const patch = patchBody;
      const merged = {
        ...existing,
        ...patch,
        id: route.noteId,
        schemaVersion: existing.schemaVersion,
        body: (patch.body as typeof existing.body | undefined) ?? existing.body,
      };
      const result = await upsertNoteForUser(user.id, merged);
      if (!result.ok) return respond(result, result.error === "conflict" ? 409 : result.error === "limit" ? 409 : 400);
      return respond(result);
    }

    if (route.kind === "notes-granted") {
      const social = await import("./v1-social.server");
      return respond({ ok: true, notes: await social.listGrantedNotesForUser(user.id) });
    }

    if (route.kind === "links") {
      const social = await import("./v1-social.server");
      return respond({ ok: true, ...(await social.listLinksForUser(user.id)) });
    }

    if (route.kind === "links-search") {
      const social = await import("./v1-social.server");
      const url = new URL(request.url);
      const q = url.searchParams.get("q") ?? "";
      return respond({ ok: true, people: await social.searchPeopleForUser(user.id, q) });
    }

    if (
      route.kind === "links-accept" ||
      route.kind === "links-decline" ||
      route.kind === "links-remove" ||
      route.kind === "links-request"
    ) {
      const payload = await readAndParse(request, handleBodySchema, respond);
      if (payload instanceof Response) return payload;
      const handle = payload.handle;
      const social = await import("./v1-social.server");
      if (route.kind === "links-accept") {
        const result = await social.acceptLinkForUser(user.id, handle);
        if (!result.ok) {
          const status = result.error === "rate" ? 429 : result.error === "limit" ? 409 : 404;
          return respond(result, status);
        }
        return respond(result);
      }
      if (route.kind === "links-request") {
        const result = await social.requestLinkForUser(user.id, handle);
        if (!result.ok) {
          const status = result.error === "rate" ? 429 : result.error === "limit" ? 409 : 404;
          return respond(result, status);
        }
        return respond(result);
      }
      if (route.kind === "links-remove") {
        // Unfriend: deletes the accepted link for both users (+ shared grants).
        const result = await social.removeLinkForUser(user.id, handle);
        return respond(result, result.ok ? 200 : 404);
      }
      // decline also cancels outgoing (web friends page).
      const result = await social.declineLinkForUser(user.id, handle);
      return respond(result, result.ok ? 200 : 404);
    }

    if (route.kind === "notifications") {
      const social = await import("./v1-social.server");
      if (route.notificationId) {
        return respond(await social.deleteNotificationForUser(user.id, route.notificationId));
      }
      const url = new URL(request.url);
      const cursor = url.searchParams.get("cursor");
      const limit = clampNotificationLimit(url.searchParams.get("limit"));
      const unreadOnly =
        url.searchParams.get("unreadOnly") === "1" || url.searchParams.get("unreadOnly") === "true";
      const payload = await social.listNotificationsForUser(user.id, {
        cursor,
        limit,
        unreadOnly,
      });
      return respond({ ok: true, ...payload });
    }

    if (route.kind === "notifications-summary") {
      const social = await import("./v1-social.server");
      const payload = await social.notificationsSummaryForUser(user.id);
      return respond({ ok: true, ...payload });
    }

    if (route.kind === "notifications-read") {
      const payload = await readAndParse(request, notificationsReadSchema, respond, { emptyAs: {} });
      if (payload instanceof Response) return payload;
      const id = typeof payload.id === "string" && payload.id.trim() ? payload.id.trim() : undefined;
      const social = await import("./v1-social.server");
      return respond(await social.markNotificationsReadForUser(user.id, id));
    }

    if (route.kind === "notifications-clear") {
      const social = await import("./v1-social.server");
      return respond(await social.clearNotificationsForUser(user.id));
    }

    if (route.kind === "speakers") {
      if (!route.speakerId) {
        if (method === "GET") return respond({ ok: true, speakers: await listSpeakersForUser(user.id) });
        const body = await readAndParse(request, speakerUpsertSchema, respond);
        if (body instanceof Response) return body;
        const result = await upsertSpeakerForUser(user.id, body);
        if (!result.ok) return respond(result, 400);
        return respond(result, 201);
      }
      if (method === "DELETE") {
        const result = await deleteSpeakerForUser(user.id, route.speakerId);
        return respond(result);
      }
    }

    if (route.kind === "devices-apns") {
      if (method === "POST") {
        const payload = await readAndParse(request, devicesApnsPostSchema, respond);
        if (payload instanceof Response) return payload;
        const sandbox =
          payload.sandbox === true || payload.environment === "sandbox";
        const result = await saveApnsDevice(
          user.id,
          payload.token,
          sandbox,
          String(payload.deviceId ?? ""),
        );
        const status =
          result.ok ? 200 : result.error === "rate" ? 429 : result.error === "conflict" ? 409 : 400;
        return respond(result, status);
      }
      const payload = await readAndParse(request, devicesApnsDeleteSchema, respond, { emptyAs: {} });
      if (payload instanceof Response) return payload;
      const result = await dropApnsDevice(user.id, String(payload.token ?? ""), {
        all: payload.all === true,
        deviceId: typeof payload.deviceId === "string" ? payload.deviceId : undefined,
      });
      return respond(result, result.ok ? 200 : 400);
    }

    const groupsApi = await import("./v1-groups.server");

    if (route.kind === "groups") {
      if (!route.groupId) {
        if (method === "GET") return respond({ ok: true, groups: await groupsApi.listGroupsForUser(user.id) });
        const body = await readAndParse(request, groupCreateSchema, respond);
        if (body instanceof Response) return body;
        const result = await groupsApi.createGroupForUser(user.id, body);
        if (!result.ok) return respond(result, result.error === "limit" ? 409 : 400);
        return respond(result, 201);
      }
      if (method === "GET") {
        const group = await groupsApi.getGroupForUser(user.id, route.groupId);
        if (!group) return respond({ ok: false, error: "missing" }, 404);
        return respond({ ok: true, group });
      }
      if (method === "DELETE") {
        const result = await groupsApi.deleteGroupForUser(user.id, route.groupId);
        if (!result.ok) {
          return respond(result, result.error === "missing" ? 404 : 403);
        }
        return respond(result);
      }
      const body = await readAndParse(request, groupUpdateSchema, respond, { emptyAs: {} });
      if (body instanceof Response) return body;
      const result = await groupsApi.updateGroupForUser(user.id, route.groupId, body);
      if (!result.ok) {
        const status = result.error === "missing" ? 404 : result.error === "forbidden" ? 403 : 400;
        return respond(result, status);
      }
      return respond(result);
    }

    if (route.kind === "group-notes") {
      if (!route.noteId) {
        if (method === "GET") {
          const url = new URL(request.url);
          const updatedSince = url.searchParams.get("updatedSince");
          const result = await groupsApi.listNotesInGroupForUser(user.id, route.groupId, {
            updatedSince,
          });
          if (!result.ok) return respond(result, 403);
          const inm = request.headers.get("if-none-match")?.trim() ?? "";
          if (inm && inm === result.etag) {
            return new Response(null, {
              status: 304,
              headers: {
                ETag: result.etag,
                "Cache-Control": "private, no-cache",
                ...corsHeadersFor(request),
              },
            });
          }
          return respond(
            { ok: true, notes: result.notes, incremental: result.incremental },
            200,
            {
              ETag: result.etag,
              "Cache-Control": "private, no-cache",
              "Access-Control-Expose-Headers": "ETag",
            },
          );
        }
        const body = await readAndParse(request, groupNotePublishSchema, respond);
        if (body instanceof Response) return body;
        const noteId = body.noteId.trim();
        const result = await groupsApi.publishNoteIdToGroup(user.id, route.groupId, noteId);
        if (!result.ok) {
          const status =
            result.error === "missing" ? 404 : result.error === "limit" ? 409 : 403;
          return respond(result, status);
        }
        return respond(result, 201);
      }
      if (method === "DELETE") {
        const result = await groupsApi.unpublishNoteFromGroupForUser(user.id, route.groupId, route.noteId);
        if (!result.ok) return respond(result, 403);
        return respond(result);
      }
    }

    if (route.kind === "group-members") {
      if (!route.userId) {
        const result = await groupsApi.listMembersForGroup(user.id, route.groupId);
        if (!result.ok) return respond(result, 403);
        return respond(result);
      }
      if (method === "DELETE") {
        const result = await groupsApi.removeGroupMemberForUser(user.id, route.groupId, route.userId);
        if (!result.ok) {
          const status =
            result.error === "missing" ? 404 : result.error === "lastAdmin" ? 409 : 403;
          return respond(result, status);
        }
        return respond(result);
      }
    }

    if (route.kind === "group-members-decide") {
      const payload = await readAndParse(request, groupMemberDecideSchema, respond);
      if (payload instanceof Response) return payload;
      const result = await groupsApi.decideGroupMemberForUser(
        user.id,
        route.groupId,
        payload.userId.trim(),
        payload.accept === true,
      );
      if (!result.ok) {
        return respond(result, result.error === "missing" ? 404 : 403);
      }
      return respond(result);
    }

    if (route.kind === "group-members-role") {
      const payload = await readAndParse(request, groupMemberRoleSchema, respond);
      if (payload instanceof Response) return payload;
      const result = await groupsApi.setGroupMemberRoleForUser(
        user.id,
        route.groupId,
        payload.userId.trim(),
        payload.role,
      );
      if (!result.ok) {
        const status =
          result.error === "missing" ? 404 : result.error === "lastAdmin" ? 409 : 403;
        return respond(result, status);
      }
      return respond(result);
    }

    if (route.kind === "note-groups") {
      const groups = await groupsApi.listGroupsForNote(user.id, route.noteId);
      return respond({ ok: true, groups });
    }

    const profileApi = await import("./v1-profile.server");

    if (route.kind === "me") {
      if (method === "GET") {
        return respond({ ok: true, me: await profileApi.getMeForUser(user.id, user.email) });
      }
      const body = await readAndParse(request, mePatchSchema, respond, { emptyAs: {} });
      if (body instanceof Response) return body;
      const result = await profileApi.patchMeForUser(user.id, body);
      if (!result.ok) return respond(result, result.error === "handle" ? 409 : 400);
      return respond(result);
    }

    if (route.kind === "prefs") {
      if (method === "GET") {
        return respond({ ok: true, prefs: await profileApi.getPrefsForUser(user.id) });
      }
      const body = await readAndParse(request, prefsPatchSchema, respond, { emptyAs: {} });
      if (body instanceof Response) return body;
      const result = await profileApi.savePrefsForUser(user.id, body);
      if (!result.ok) return respond(result, result.error === "handle" ? 409 : 400);
      return respond(result);
    }

    if (route.kind === "notify-prefs") {
      if (method === "GET") {
        return respond({ ok: true, notify: await profileApi.getNotifyPrefsForUser(user.id) });
      }
      const body = await readAndParse(request, notifyPrefsSchema, respond, { emptyAs: {} });
      if (body instanceof Response) return body;
      const result = await profileApi.saveNotifyPrefsForUser(user.id, body);
      if (!result.ok) return respond(result, 400);
      return respond(result);
    }

    if (route.kind === "account-export") {
      return respond(await profileApi.exportAccountForUser(user.id));
    }

    if (route.kind === "account-delete") {
      const result = await profileApi.deleteAccountForUser(user.id);
      if (!result.ok) return respond(result, 429);
      return respond(result);
    }

    const versesApi = await import("./v1-verses.server");

    if (route.kind === "verses-append") {
      const body = await readAndParse(request, versesAppendSchema, respond);
      if (body instanceof Response) return body;
      const result = await versesApi.appendVerseForUser(user.id, body);
      if (!result.ok) {
        const status =
          result.error === "missing"
            ? 404
            : result.error === "limit" || result.error === "conflict"
              ? 409
              : 400;
        return respond(result, status);
      }
      return respond(result, 201);
    }

    if (route.kind === "my-collections-save") {
      const body = await readAndParse(request, collectionSaveSchema, respond);
      if (body instanceof Response) return body;
      const result = await versesApi.savePassageToCollectionForUser(user.id, body);
      if (!result.ok) {
        const status = result.error === "missing" ? 404 : result.error === "limit" ? 409 : 400;
        return respond(result, status);
      }
      void import("@/lib/catalog-push.server").then((m) => m.pushCatalogHintToUser(user.id, "themes_updated"));
      return respond(result);
    }

    if (route.kind === "my-collections") {
      if (!route.collectionId) {
        if (method === "GET") {
          return respond({ ok: true, collections: await versesApi.listMyCollectionsForUser(user.id) });
        }
        const body = await readAndParse(request, collectionCreateSchema, respond);
        if (body instanceof Response) return body;
        const result = await versesApi.createMyCollectionForUser(user.id, body);
        if (!result.ok) {
          const status =
            result.error === "missing" ? 404 : result.error === "limit" ? 409 : 400;
          return respond(result, status);
        }
        void import("@/lib/catalog-push.server").then((m) => m.pushCatalogHintToUser(user.id, "themes_updated"));
        return respond(result, 201);
      }
      if (method === "GET") {
        const collection = await versesApi.getMyCollectionForUser(user.id, route.collectionId);
        if (!collection) return respond({ ok: false, error: "missing" }, 404);
        return respond({ ok: true, collection });
      }
      if (method === "DELETE") {
        const result = await versesApi.deleteMyCollectionForUser(user.id, route.collectionId);
        if (result.ok) {
          void import("@/lib/catalog-push.server").then((m) => m.pushCatalogHintToUser(user.id, "themes_updated"));
        }
        return respond(result, result.ok ? 200 : 404);
      }
      const body = await readAndParse(request, collectionUpdateSchema, respond, { emptyAs: {} });
      if (body instanceof Response) return body;
      const result = await versesApi.updateMyCollectionForUser(user.id, route.collectionId, body);
      if (!result.ok) return respond(result, result.error === "missing" ? 404 : 400);
      void import("@/lib/catalog-push.server").then((m) => m.pushCatalogHintToUser(user.id, "themes_updated"));
      return respond(result);
    }

    const plansApi = await import("./v1-plans.server");

    if (route.kind === "plans-mark") {
      const payload = await readAndParse(request, planMarkSchema, respond);
      if (payload instanceof Response) return payload;
      const day = typeof payload.day === "number" ? payload.day : Number(payload.day);
      const result = await plansApi.markPlanDayForUser(user.id, payload.planId, day, payload.on !== false);
      return respond(result, result.ok ? 200 : result.error === "pace" ? 429 : 400);
    }
    if (route.kind === "plans-reset" || route.kind === "plans-start" || route.kind === "plans-stop" || route.kind === "plans-invite") {
      const payload = await readAndParse(request, planIdSchema, respond);
      if (payload instanceof Response) return payload;
      if (route.kind === "plans-reset") {
        return respond(await plansApi.resetPlanMarksForUser(user.id, payload.planId));
      }
      if (route.kind === "plans-start") {
        const result = await plansApi.startPlanForUser(user.id, payload.planId);
        return respond(result, result.ok ? 200 : 404);
      }
      if (route.kind === "plans-stop") {
        const result = await plansApi.stopPlanForUser(user.id, payload.planId);
        return respond(result, result.ok ? 200 : 404);
      }
      const result = await plansApi.createPlanInviteForUser(user.id, payload.planId);
      return respond(result, result.ok ? 200 : 404);
    }
    if (route.kind === "plans-join") {
      const payload = await readAndParse(request, planJoinSchema, respond);
      if (payload instanceof Response) return payload;
      const groupId =
        typeof payload.id === "string" && payload.id.trim()
          ? payload.id.trim()
          : typeof payload.groupId === "string"
            ? payload.groupId.trim()
            : "";
      const result = await plansApi.joinPlanGroupForUser(user.id, groupId);
      return respond(result, result.ok ? 200 : 404);
    }

    if (route.kind === "plans-group") {
      const group = await plansApi.getPlanGroupPreviewForUser(route.groupId, user.id);
      if (!group) return respond({ ok: false, error: "missing" }, 404);
      return respond({ ok: true, group });
    }

    return respond({ ok: false, error: "not_found" }, 404);
  } catch (error) {
    if (error instanceof UnauthorizedError) {
      return respond({ ok: false, error: "unauthorized" }, 401);
    }
    console.error("[native/v1]", error);
    return respond({ ok: false, error: "server_error" }, 500);
  }
}
