import { UnauthorizedError } from "@/lib/auth/verify.server";
import { matchNativeV1Route, methodAllowed } from "./v1-router";

const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "GET, POST, PATCH, PUT, DELETE, OPTIONS",
  "Access-Control-Allow-Headers": "Authorization, Content-Type, Cookie",
};

export function json(
  data: unknown,
  status = 200,
  extraHeaders: Record<string, string> = {},
): Response {
  return new Response(JSON.stringify(data), {
    status,
    headers: {
      "Content-Type": "application/json; charset=utf-8",
      "Cache-Control": "no-store",
      ...CORS,
      ...extraHeaders,
    },
  });
}

export function preflight(): Response {
  return new Response(null, { status: 204, headers: CORS });
}

async function readBody(request: Request): Promise<unknown> {
  const text = await request.text();
  if (!text) return null;
  try {
    return JSON.parse(text) as unknown;
  } catch {
    return Symbol.for("invalid-json");
  }
}

/**
 * Dispatch a native v1 request. Dynamic-imports the server module so tests can
 * exercise the router without loading Postgres.
 */
export async function handleNativeV1Request(request: Request, splat: string): Promise<Response> {
  if (request.method.toUpperCase() === "OPTIONS") return preflight();

  const route = matchNativeV1Route(splat);
  if (route.kind === "not-found") {
    return json({ ok: false, error: "not_found", path: route.path }, 404);
  }
  if (!methodAllowed(route, request.method)) {
    return json({ ok: false, error: "method_not_allowed" }, 405);
  }

  if (route.kind === "catalog") {
    const { nativeV1Catalog } = await import("./v1.server");
    return json(nativeV1Catalog());
  }

  try {
    // Public reading plans catalog (same data as /api/plans).
    if (route.kind === "plans") {
      const plansApi = await import("./v1-plans.server");
      const url = new URL(request.url);
      const result = plansApi.resolveNativePlans(url.searchParams);
      return json(result, result.ok ? 200 : 400);
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
        return json(versesApi.listBibleBooks(url.searchParams.get("locale") ?? undefined), 200, {
          "Cache-Control": "public, max-age=86400, stale-while-revalidate=604800",
          ETag: `"bible-books-v1-${url.searchParams.get("locale") ?? "pt"}"`,
        });
      }
      if (route.kind === "bible-apps") {
        return json(versesApi.listBibleApps(url.searchParams.get("locale") ?? undefined));
      }
      if (route.kind === "bible-themes") {
        const { queryCollectionsFromSearch } = await import("@/lib/bible/collections-api");
        return json(versesApi.resolveNativeThemes(queryCollectionsFromSearch(url.searchParams)));
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
        const body = await readBody(request);
        if (body === Symbol.for("invalid-json")) return json({ ok: false, error: "invalid_json" }, 400);
        const payload = body && typeof body === "object" ? (body as Record<string, unknown>) : {};
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
      return json(result, result.ok ? 200 : 400);
    }

    // Public auth endpoints (no bearer yet). Catalog already returned above.
    if (
      route.kind === "auth-providers" ||
      route.kind === "auth-claim" ||
      route.kind === "auth-email" ||
      route.kind === "auth-apple" ||
      route.kind === "auth-from-cookie"
    ) {
      const authApi = await import("./v1-auth.server");
      if (route.kind === "auth-providers") {
        return json(authApi.listNativeAuthProviders());
      }
      const body = await readBody(request);
      if (body === Symbol.for("invalid-json")) return json({ ok: false, error: "invalid_json" }, 400);
      const payload = body && typeof body === "object" ? (body as Record<string, unknown>) : {};

      if (route.kind === "auth-claim") {
        const result = await authApi.claimNativeBearer(request, payload);
        return json(result, result.ok ? 200 : result.status);
      }
      if (route.kind === "auth-email") {
        const result = await authApi.signInEmailNative(request, payload);
        return json(result, result.ok ? 200 : result.status);
      }
      if (route.kind === "auth-apple") {
        const result = await authApi.signInAppleNative(request, payload);
        return json(result, result.ok ? 200 : result.status);
      }
      const result = await authApi.bearerFromCookie(request);
      return json(result, result.ok ? 200 : result.status);
    }

    if (route.kind === "auth-sign-out") {
      const authApi = await import("./v1-auth.server");
      const result = await authApi.signOutNative(request);
      return json(result, result.ok ? 200 : result.status);
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
      return json(await getNativeSession(user.id, user.email));
    }

    if (route.kind === "notes") {
      if (!route.noteId) {
        if (method === "GET") return json({ ok: true, notes: await listNotesForUser(user.id) });
        const body = await readBody(request);
        if (body === Symbol.for("invalid-json")) return json({ ok: false, error: "invalid_json" }, 400);
        const result = await upsertNoteForUser(user.id, body);
        if (!result.ok) return json(result, result.error === "limit" ? 409 : 400);
        return json(result, 201);
      }
      if (method === "GET") {
        const packed = await getNoteWithSpeakersForUser(user.id, route.noteId);
        if (!packed) return json({ ok: false, error: "missing" }, 404);
        return json({ ok: true, ...packed });
      }
      if (method === "DELETE") {
        const result = await deleteNoteForUser(user.id, route.noteId);
        return json(result, result.ok ? 200 : 404);
      }
      // Mutations require ownership — grants are read-only via GET.
      const body = await readBody(request);
      if (body === Symbol.for("invalid-json")) return json({ ok: false, error: "invalid_json" }, 400);
      const existing = await getNoteForUser(user.id, route.noteId);
      if (!existing) return json({ ok: false, error: "missing" }, 404);
      const patch = body && typeof body === "object" ? (body as Record<string, unknown>) : {};
      const merged = {
        ...existing,
        ...patch,
        id: route.noteId,
        schemaVersion: existing.schemaVersion,
        body: (patch.body as typeof existing.body | undefined) ?? existing.body,
      };
      const result = await upsertNoteForUser(user.id, merged);
      if (!result.ok) return json(result, 400);
      return json(result);
    }

    if (route.kind === "notes-granted") {
      const social = await import("./v1-social.server");
      return json({ ok: true, notes: await social.listGrantedNotesForUser(user.id) });
    }

    if (route.kind === "links") {
      const social = await import("./v1-social.server");
      return json({ ok: true, ...(await social.listLinksForUser(user.id)) });
    }

    if (route.kind === "links-search") {
      const social = await import("./v1-social.server");
      const url = new URL(request.url);
      const q = url.searchParams.get("q") ?? "";
      return json({ ok: true, people: await social.searchPeopleForUser(user.id, q) });
    }

    if (route.kind === "links-accept" || route.kind === "links-decline" || route.kind === "links-request") {
      const body = await readBody(request);
      if (body === Symbol.for("invalid-json")) return json({ ok: false, error: "invalid_json" }, 400);
      const payload = body && typeof body === "object" ? (body as Record<string, unknown>) : {};
      const handle = typeof payload.handle === "string" ? payload.handle : "";
      if (!handle.trim()) return json({ ok: false, error: "invalid" }, 400);
      const social = await import("./v1-social.server");
      if (route.kind === "links-accept") {
        const result = await social.acceptLinkForUser(user.id, handle);
        if (!result.ok) {
          const status = result.error === "rate" ? 429 : result.error === "limit" ? 409 : 404;
          return json(result, status);
        }
        return json(result);
      }
      if (route.kind === "links-request") {
        const result = await social.requestLinkForUser(user.id, handle);
        if (!result.ok) {
          const status = result.error === "rate" ? 429 : result.error === "limit" ? 409 : 404;
          return json(result, status);
        }
        return json(result);
      }
      // decline also cancels outgoing (web friends page).
      const result = await social.declineLinkForUser(user.id, handle);
      return json(result, result.ok ? 200 : 404);
    }

    if (route.kind === "notifications") {
      const social = await import("./v1-social.server");
      const url = new URL(request.url);
      const cursor = url.searchParams.get("cursor");
      const limitRaw = url.searchParams.get("limit");
      const limit = limitRaw ? Number(limitRaw) : undefined;
      const unreadOnly =
        url.searchParams.get("unreadOnly") === "1" || url.searchParams.get("unreadOnly") === "true";
      const payload = await social.listNotificationsForUser(user.id, {
        cursor,
        limit: Number.isFinite(limit) ? limit : undefined,
        unreadOnly,
      });
      return json({ ok: true, ...payload });
    }

    if (route.kind === "notifications-summary") {
      const social = await import("./v1-social.server");
      const payload = await social.notificationsSummaryForUser(user.id);
      return json({ ok: true, ...payload });
    }

    if (route.kind === "notifications-read") {
      const body = await readBody(request);
      if (body === Symbol.for("invalid-json")) return json({ ok: false, error: "invalid_json" }, 400);
      const payload = body && typeof body === "object" ? (body as Record<string, unknown>) : {};
      const id = typeof payload.id === "string" && payload.id.trim() ? payload.id.trim() : undefined;
      const social = await import("./v1-social.server");
      return json(await social.markNotificationsReadForUser(user.id, id));
    }

    if (route.kind === "speakers") {
      if (!route.speakerId) {
        if (method === "GET") return json({ ok: true, speakers: await listSpeakersForUser(user.id) });
        const body = await readBody(request);
        if (body === Symbol.for("invalid-json")) return json({ ok: false, error: "invalid_json" }, 400);
        const result = await upsertSpeakerForUser(user.id, body);
        if (!result.ok) return json(result, 400);
        return json(result, 201);
      }
      if (method === "DELETE") {
        const result = await deleteSpeakerForUser(user.id, route.speakerId);
        return json(result);
      }
    }

    if (route.kind === "devices-apns") {
      const body = (await readBody(request)) as { token?: string; sandbox?: boolean } | null;
      if (body === Symbol.for("invalid-json")) return json({ ok: false, error: "invalid_json" }, 400);
      if (method === "POST") {
        const result = await saveApnsDevice(user.id, String(body?.token ?? ""), body?.sandbox === true);
        return json(result, result.ok ? 200 : 400);
      }
      const result = await dropApnsDevice(user.id, String(body?.token ?? ""));
      return json(result);
    }

    const groupsApi = await import("./v1-groups.server");

    if (route.kind === "groups") {
      if (!route.groupId) {
        if (method === "GET") return json({ ok: true, groups: await groupsApi.listGroupsForUser(user.id) });
        const body = await readBody(request);
        if (body === Symbol.for("invalid-json")) return json({ ok: false, error: "invalid_json" }, 400);
        const result = await groupsApi.createGroupForUser(user.id, body);
        if (!result.ok) return json(result, result.error === "limit" ? 409 : 400);
        return json(result, 201);
      }
      if (method === "GET") {
        const group = await groupsApi.getGroupForUser(user.id, route.groupId);
        if (!group) return json({ ok: false, error: "missing" }, 404);
        return json({ ok: true, group });
      }
      if (method === "DELETE") {
        const result = await groupsApi.deleteGroupForUser(user.id, route.groupId);
        if (!result.ok) {
          return json(result, result.error === "missing" ? 404 : 403);
        }
        return json(result);
      }
      const body = await readBody(request);
      if (body === Symbol.for("invalid-json")) return json({ ok: false, error: "invalid_json" }, 400);
      const result = await groupsApi.updateGroupForUser(user.id, route.groupId, body);
      if (!result.ok) {
        const status = result.error === "missing" ? 404 : result.error === "forbidden" ? 403 : 400;
        return json(result, status);
      }
      return json(result);
    }

    if (route.kind === "group-notes") {
      if (!route.noteId) {
        if (method === "GET") {
          const result = await groupsApi.listNotesInGroupForUser(user.id, route.groupId);
          if (!result.ok) return json(result, 403);
          return json(result);
        }
        const body = await readBody(request);
        if (body === Symbol.for("invalid-json")) return json({ ok: false, error: "invalid_json" }, 400);
        const noteId =
          body && typeof body === "object" && typeof (body as { noteId?: unknown }).noteId === "string"
            ? (body as { noteId: string }).noteId.trim()
            : "";
        if (!noteId) return json({ ok: false, error: "invalid" }, 400);
        const result = await groupsApi.publishNoteIdToGroup(user.id, route.groupId, noteId);
        if (!result.ok) {
          const status =
            result.error === "missing" ? 404 : result.error === "limit" ? 409 : 403;
          return json(result, status);
        }
        return json(result, 201);
      }
      if (method === "DELETE") {
        const result = await groupsApi.unpublishNoteFromGroupForUser(user.id, route.groupId, route.noteId);
        if (!result.ok) return json(result, 403);
        return json(result);
      }
    }

    if (route.kind === "group-members") {
      if (!route.userId) {
        const result = await groupsApi.listMembersForGroup(user.id, route.groupId);
        if (!result.ok) return json(result, 403);
        return json(result);
      }
      if (method === "DELETE") {
        const result = await groupsApi.removeGroupMemberForUser(user.id, route.groupId, route.userId);
        if (!result.ok) {
          const status =
            result.error === "missing" ? 404 : result.error === "lastAdmin" ? 409 : 403;
          return json(result, status);
        }
        return json(result);
      }
    }

    if (route.kind === "group-members-decide") {
      const body = await readBody(request);
      if (body === Symbol.for("invalid-json")) return json({ ok: false, error: "invalid_json" }, 400);
      const payload = body && typeof body === "object" ? (body as Record<string, unknown>) : {};
      const targetUserId = typeof payload.userId === "string" ? payload.userId.trim() : "";
      const accept = payload.accept === true;
      if (!targetUserId) return json({ ok: false, error: "invalid" }, 400);
      const result = await groupsApi.decideGroupMemberForUser(user.id, route.groupId, targetUserId, accept);
      if (!result.ok) {
        return json(result, result.error === "missing" ? 404 : 403);
      }
      return json(result);
    }

    if (route.kind === "group-members-role") {
      const body = await readBody(request);
      if (body === Symbol.for("invalid-json")) return json({ ok: false, error: "invalid_json" }, 400);
      const payload = body && typeof body === "object" ? (body as Record<string, unknown>) : {};
      const targetUserId = typeof payload.userId === "string" ? payload.userId.trim() : "";
      const role = payload.role === "admin" ? "admin" : payload.role === "member" ? "member" : "";
      if (!targetUserId || !role) return json({ ok: false, error: "invalid" }, 400);
      const result = await groupsApi.setGroupMemberRoleForUser(
        user.id,
        route.groupId,
        targetUserId,
        role,
      );
      if (!result.ok) {
        const status =
          result.error === "missing" ? 404 : result.error === "lastAdmin" ? 409 : 403;
        return json(result, status);
      }
      return json(result);
    }

    if (route.kind === "note-groups") {
      const groups = await groupsApi.listGroupsForNote(user.id, route.noteId);
      return json({ ok: true, groups });
    }

    const profileApi = await import("./v1-profile.server");

    if (route.kind === "me") {
      if (method === "GET") {
        return json({ ok: true, me: await profileApi.getMeForUser(user.id, user.email) });
      }
      const body = await readBody(request);
      if (body === Symbol.for("invalid-json")) return json({ ok: false, error: "invalid_json" }, 400);
      const result = await profileApi.patchMeForUser(user.id, body);
      if (!result.ok) return json(result, result.error === "handle" ? 409 : 400);
      return json(result);
    }

    if (route.kind === "prefs") {
      if (method === "GET") {
        return json({ ok: true, prefs: await profileApi.getPrefsForUser(user.id) });
      }
      const body = await readBody(request);
      if (body === Symbol.for("invalid-json")) return json({ ok: false, error: "invalid_json" }, 400);
      const result = await profileApi.savePrefsForUser(user.id, body);
      if (!result.ok) return json(result, result.error === "handle" ? 409 : 400);
      return json(result);
    }

    if (route.kind === "notify-prefs") {
      if (method === "GET") {
        return json({ ok: true, notify: await profileApi.getNotifyPrefsForUser(user.id) });
      }
      const body = await readBody(request);
      if (body === Symbol.for("invalid-json")) return json({ ok: false, error: "invalid_json" }, 400);
      const result = await profileApi.saveNotifyPrefsForUser(user.id, body);
      if (!result.ok) return json(result, 400);
      return json(result);
    }

    if (route.kind === "account-export") {
      return json(await profileApi.exportAccountForUser(user.id));
    }

    if (route.kind === "account-delete") {
      const result = await profileApi.deleteAccountForUser(user.id);
      if (!result.ok) return json(result, 429);
      return json(result);
    }

    const versesApi = await import("./v1-verses.server");

    if (route.kind === "verses-append") {
      const body = await readBody(request);
      if (body === Symbol.for("invalid-json")) return json({ ok: false, error: "invalid_json" }, 400);
      const result = await versesApi.appendVerseForUser(user.id, body);
      if (!result.ok) {
        const status = result.error === "missing" ? 404 : result.error === "limit" ? 409 : 400;
        return json(result, status);
      }
      return json(result, 201);
    }

    if (route.kind === "my-collections-save") {
      const body = await readBody(request);
      if (body === Symbol.for("invalid-json")) return json({ ok: false, error: "invalid_json" }, 400);
      const result = await versesApi.savePassageToCollectionForUser(user.id, body);
      if (!result.ok) {
        const status = result.error === "missing" ? 404 : result.error === "limit" ? 409 : 400;
        return json(result, status);
      }
      return json(result);
    }

    if (route.kind === "my-collections") {
      if (!route.collectionId) {
        if (method === "GET") {
          return json({ ok: true, collections: await versesApi.listMyCollectionsForUser(user.id) });
        }
        const body = await readBody(request);
        if (body === Symbol.for("invalid-json")) return json({ ok: false, error: "invalid_json" }, 400);
        const result = await versesApi.createMyCollectionForUser(user.id, body);
        if (!result.ok) return json(result, result.error === "limit" ? 409 : 400);
        return json(result, 201);
      }
      if (method === "GET") {
        const collection = await versesApi.getMyCollectionForUser(user.id, route.collectionId);
        if (!collection) return json({ ok: false, error: "missing" }, 404);
        return json({ ok: true, collection });
      }
      if (method === "DELETE") {
        const result = await versesApi.deleteMyCollectionForUser(user.id, route.collectionId);
        return json(result, result.ok ? 200 : 404);
      }
      const body = await readBody(request);
      if (body === Symbol.for("invalid-json")) return json({ ok: false, error: "invalid_json" }, 400);
      const result = await versesApi.updateMyCollectionForUser(user.id, route.collectionId, body);
      if (!result.ok) return json(result, result.error === "missing" ? 404 : 400);
      return json(result);
    }

    const plansApi = await import("./v1-plans.server");

    if (
      route.kind === "plans-mark" ||
      route.kind === "plans-reset" ||
      route.kind === "plans-start" ||
      route.kind === "plans-stop" ||
      route.kind === "plans-invite" ||
      route.kind === "plans-join"
    ) {
      const body = await readBody(request);
      if (body === Symbol.for("invalid-json")) return json({ ok: false, error: "invalid_json" }, 400);
      const payload = body && typeof body === "object" ? (body as Record<string, unknown>) : {};
      if (route.kind === "plans-mark") {
        const planId = typeof payload.planId === "string" ? payload.planId : "";
        const day = typeof payload.day === "number" ? payload.day : Number(payload.day);
        const on = payload.on !== false;
        const result = await plansApi.markPlanDayForUser(user.id, planId, day, on);
        return json(result, result.ok ? 200 : result.error === "pace" ? 429 : 400);
      }
      if (route.kind === "plans-reset") {
        const planId = typeof payload.planId === "string" ? payload.planId : "";
        return json(await plansApi.resetPlanMarksForUser(user.id, planId));
      }
      if (route.kind === "plans-start") {
        const planId = typeof payload.planId === "string" ? payload.planId : "";
        const result = await plansApi.startPlanForUser(user.id, planId);
        return json(result, result.ok ? 200 : 404);
      }
      if (route.kind === "plans-stop") {
        const planId = typeof payload.planId === "string" ? payload.planId : "";
        const result = await plansApi.stopPlanForUser(user.id, planId);
        return json(result, result.ok ? 200 : 404);
      }
      if (route.kind === "plans-invite") {
        const planId = typeof payload.planId === "string" ? payload.planId : "";
        const result = await plansApi.createPlanInviteForUser(user.id, planId);
        return json(result, result.ok ? 200 : 404);
      }
      const groupId = typeof payload.id === "string" ? payload.id : typeof payload.groupId === "string" ? payload.groupId : "";
      const result = await plansApi.joinPlanGroupForUser(user.id, groupId);
      return json(result, result.ok ? 200 : 404);
    }

    if (route.kind === "plans-group") {
      const group = await plansApi.getPlanGroupPreviewForUser(route.groupId, user.id);
      if (!group) return json({ ok: false, error: "missing" }, 404);
      return json({ ok: true, group });
    }

    return json({ ok: false, error: "not_found" }, 404);
  } catch (error) {
    if (error instanceof UnauthorizedError) {
      return json({ ok: false, error: "unauthorized" }, 401);
    }
    console.error("[native/v1]", error);
    return json({ ok: false, error: "server_error" }, 500);
  }
}
