/**
 * Shared zod schemas for native `/api/native/v1` mutating bodies + query clamps.
 * Keep these permissive enough for existing iOS NoteDocumentV1 / legacy payloads;
 * deep note cleaning still happens in `coerceIncomingNote`.
 */
import { z } from "zod";

/** Hard cap on native JSON bodies (notes can be large; keep DoS bounded). */
export const MAX_BODY_BYTES = 512 * 1024;
export const MAX_NOTIFICATION_LIMIT = 100;

const id40 = z.string().min(1).max(40);
const handleSchema = z.string().min(1).max(40);

export type ParseOk<T> = { ok: true; data: T };
export type ParseFail = {
  ok: false;
  error: "invalid_body";
  issues: Array<{ path: string; message: string }>;
};

export function formatZodIssues(error: z.ZodError): ParseFail["issues"] {
  return error.issues.map((issue) => ({
    path: issue.path.length ? issue.path.join(".") : "(root)",
    message: issue.message,
  }));
}

export function parseWithSchema<T>(schema: z.ZodType<T>, raw: unknown): ParseOk<T> | ParseFail {
  const result = schema.safeParse(raw);
  if (result.success) return { ok: true, data: result.data };
  return { ok: false, error: "invalid_body", issues: formatZodIssues(result.error) };
}

/** Clamp notifications `limit` query (finite → [1, 100]; else undefined). */
export function clampNotificationLimit(raw: string | null): number | undefined {
  if (raw == null || raw === "") return undefined;
  const n = Number(raw);
  if (!Number.isFinite(n)) return undefined;
  return Math.min(Math.max(1, Math.floor(n)), MAX_NOTIFICATION_LIMIT);
}

/** Accept object bodies; reject arrays / primitives with a clear 400. */
const objectBody = z.record(z.string(), z.unknown());

/** NoteDocumentV1 or legacy Note — structural gate only; coerceIncomingNote cleans. */
export const noteUpsertSchema = z
  .object({
    id: z.string().min(1).max(40).optional(),
    schemaVersion: z.union([z.literal(1), z.literal("1")]).optional(),
    title: z.string().max(200).optional(),
    happenedAt: z.string().max(32).optional(),
    tags: z.array(z.unknown()).max(24).optional(),
    noteSpeakerId: z.union([z.string().max(40), z.null()]).optional(),
    speakerId: z.union([z.string().max(40), z.null()]).optional(),
    visibility: z.string().max(32).optional(),
    updatedAt: z.string().max(64).optional(),
    body: z
      .object({
        blocks: z.array(z.unknown()).max(200).optional(),
      })
      .passthrough()
      .optional(),
    blocks: z.array(z.unknown()).max(200).optional(),
  })
  .passthrough()
  .superRefine((val, ctx) => {
    // POST create needs an id; PATCH merge may omit (route supplies id).
    if (val.body == null && val.blocks == null && val.schemaVersion == null && !val.id) {
      ctx.addIssue({ code: "custom", message: "note body requires id or body/blocks", path: ["id"] });
    }
  });

export const notePatchSchema = objectBody;

export const speakerUpsertSchema = z
  .object({
    id: id40,
    name: z.string().min(1).max(80),
    color: z.string().max(32).optional(),
    updatedAt: z.string().max(64).optional(),
  })
  .passthrough();

export const handleBodySchema = z
  .object({
    handle: handleSchema,
  })
  .passthrough();

export const notificationsReadSchema = z
  .object({
    id: z.string().min(1).max(80).optional(),
  })
  .passthrough();

export const devicesApnsPostSchema = z
  .object({
    token: z.string().min(1).max(200),
    deviceId: z.string().min(8).max(128),
    sandbox: z.boolean().optional(),
    /** Optional alias for sandbox (`sandbox` | `production`). */
    environment: z.enum(["sandbox", "production"]).optional(),
  })
  .passthrough();

export const devicesApnsDeleteSchema = z
  .object({
    token: z.string().max(200).optional(),
    deviceId: z.string().max(128).optional(),
    all: z.boolean().optional(),
  })
  .passthrough()
  .superRefine((val, ctx) => {
    if (val.all === true) return;
    if (typeof val.deviceId === "string" && val.deviceId.trim()) return;
    if (typeof val.token === "string" && val.token.trim()) return;
    ctx.addIssue({
      code: "custom",
      message: "token or deviceId required unless all=true",
      path: ["token"],
    });
  });

export const groupCreateSchema = z
  .object({
    name: z.string().min(1).max(80),
    description: z.string().max(500).optional(),
    visibility: z.enum(["private", "listed"]).optional(),
  })
  .passthrough();

export const groupUpdateSchema = z
  .object({
    name: z.string().min(1).max(80).optional(),
    description: z.string().max(500).optional(),
    visibility: z.enum(["private", "listed"]).optional(),
    postPolicy: z.enum(["members", "admins"]).optional(),
  })
  .passthrough();

export const groupNotePublishSchema = z
  .object({
    noteId: z.string().min(1).max(40),
  })
  .passthrough();

export const groupMemberDecideSchema = z
  .object({
    userId: z.string().min(1).max(80),
    accept: z.boolean(),
  })
  .passthrough();

export const groupMemberRoleSchema = z
  .object({
    userId: z.string().min(1).max(80),
    role: z.enum(["admin", "member"]),
  })
  .passthrough();

export const groupInvitesCreateSchema = z
  .object({
    userIds: z.array(z.string().min(1).max(80)).min(1).max(20),
  })
  .passthrough();

export const groupInviteRespondSchema = z
  .object({
    accept: z.boolean(),
  })
  .passthrough();

export const authClaimSchema = z
  .object({
    code: z.string().min(1).max(200),
    verifier: z.string().min(1).max(200),
  })
  .passthrough();

export const authEmailSchema = z
  .object({
    email: z.string().min(1).max(320),
    password: z.string().min(1).max(200),
  })
  .passthrough();

export const authEmailSignUpSchema = z
  .object({
    name: z.string().min(1).max(120),
    email: z.string().min(1).max(320),
    password: z.string().min(1).max(200),
  })
  .passthrough();

export const authEmailForgotPasswordSchema = z
  .object({
    email: z.string().min(1).max(320),
    locale: z.string().min(1).max(32).optional(),
  })
  .passthrough();

export const authEmailResetPasswordSchema = z
  .object({
    email: z.string().min(1).max(320),
    code: z.string().min(1).max(12),
    newPassword: z.string().min(1).max(200),
  })
  .passthrough();

export const authAppleSchema = z
  .object({
    identityToken: z.string().min(1).max(8000),
    authorizationCode: z.string().max(4000).optional(),
    nonce: z.string().max(200).optional(),
    fullName: z.unknown().optional(),
    name: z.unknown().optional(),
  })
  .passthrough();

/** Link Apple — same token payload as sign-in (no fullName required). */
export const authIdentitiesLinkAppleSchema = z
  .object({
    identityToken: z.string().min(1).max(8000),
    authorizationCode: z.string().max(4000).optional(),
    nonce: z.string().max(200).optional(),
  })
  .passthrough();

/** Link Google — same PKCE claim body as `/auth/claim`. */
export const authIdentitiesLinkGoogleSchema = authClaimSchema;

export const authIdentitiesSetPasswordSchema = z
  .object({
    password: z.string().min(1).max(200),
    currentPassword: z.string().max(200).optional(),
  })
  .passthrough();

export const prefsPatchSchema = objectBody;
export const mePatchSchema = objectBody;

export const notifyPrefsSchema = z
  .object({
    reading: z.boolean().optional(),
    friends: z.boolean().optional(),
    shares: z.boolean().optional(),
    groups: z.boolean().optional(),
  })
  .passthrough();

/** POST /report — App Store UGC moderation. */
export const contentReportSchema = z
  .object({
    targetType: z.enum(["user", "note", "group"]),
    targetId: z.string().min(1).max(80),
    reason: z.enum(["spam", "offensive", "inappropriate", "other"]),
    details: z.string().max(2000).optional(),
  })
  .passthrough();

export const versesAppendSchema = objectBody;
export const collectionCreateSchema = objectBody;
export const collectionUpdateSchema = objectBody;
export const collectionSaveSchema = objectBody;

export const planMarkSchema = z
  .object({
    planId: z.string().min(1).max(80),
    day: z.union([z.number(), z.string()]),
    on: z.boolean().optional(),
  })
  .passthrough();

export const planIdSchema = z
  .object({
    planId: z.string().min(1).max(80),
  })
  .passthrough();

export const planJoinSchema = z
  .object({
    id: z.string().min(1).max(80).optional(),
    groupId: z.string().min(1).max(80).optional(),
  })
  .passthrough()
  .superRefine((val, ctx) => {
    const id = typeof val.id === "string" ? val.id.trim() : "";
    const groupId = typeof val.groupId === "string" ? val.groupId.trim() : "";
    if (!id && !groupId) {
      ctx.addIssue({ code: "custom", message: "id or groupId required", path: ["id"] });
    }
  });

export const bibleLinkBodySchema = objectBody;
