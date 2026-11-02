import { UnauthorizedError } from "@/lib/auth/verify.server";
import { matchNativeV1Route, methodAllowed } from "./v1-router";

const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "GET, POST, PATCH, PUT, DELETE, OPTIONS",
  "Access-Control-Allow-Headers": "Authorization, Content-Type, Cookie",
};

export function json(data: unknown, status = 200): Response {
  return new Response(JSON.stringify(data), {
    status,
    headers: {
      "Content-Type": "application/json; charset=utf-8",
      "Cache-Control": "no-store",
      ...CORS,
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

    if (route.kind === "note-groups") {
      const groups = await groupsApi.listGroupsForNote(user.id, route.noteId);
      return json({ ok: true, groups });
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
