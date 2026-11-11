import assert from "node:assert/strict";
import { describe, it } from "node:test";
import {
  MAX_BODY_BYTES,
  authEmailSchema,
  authEmailForgotPasswordSchema,
  authEmailResetPasswordSchema,
  authEmailSignUpSchema,
  clampNotificationLimit,
  devicesApnsDeleteSchema,
  devicesApnsPostSchema,
  groupCreateSchema,
  handleBodySchema,
  noteUpsertSchema,
  parseWithSchema,
  planMarkSchema,
  speakerUpsertSchema,
} from "./v1-schemas.ts";
import { emailPasswordMinLength } from "../../auth/email-password.ts";

describe("native v1 schemas (M1)", () => {
  it("clamps notification limit to 1..100", () => {
    assert.equal(clampNotificationLimit(null), undefined);
    assert.equal(clampNotificationLimit(""), undefined);
    assert.equal(clampNotificationLimit("nope"), undefined);
    assert.equal(clampNotificationLimit("0"), 1);
    assert.equal(clampNotificationLimit("50"), 50);
    assert.equal(clampNotificationLimit("999"), 100);
    assert.equal(clampNotificationLimit("-5"), 1);
    assert.equal(clampNotificationLimit("3.9"), 3);
  });

  it("documents the hard body size cap", () => {
    assert.equal(MAX_BODY_BYTES, 512 * 1024);
  });

  it("accepts a NoteDocumentV1-shaped payload the iOS client sends", () => {
    const doc = {
      schemaVersion: 1 as const,
      id: "noteabc123",
      title: "Estudo",
      happenedAt: "2026-11-10",
      tags: ["fé"],
      noteSpeakerId: null,
      visibility: "private",
      updatedAt: new Date().toISOString(),
      body: {
        blocks: [
          {
            type: "line",
            id: "b1",
            spans: [{ type: "text", text: "Olá" }],
          },
        ],
      },
    };
    const parsed = parseWithSchema(noteUpsertSchema, doc);
    assert.equal(parsed.ok, true);
  });

  it("rejects empty / non-object note bodies with clear issues", () => {
    const parsed = parseWithSchema(noteUpsertSchema, {});
    assert.equal(parsed.ok, false);
    if (parsed.ok) return;
    assert.equal(parsed.error, "invalid_body");
    assert.ok(parsed.issues.length >= 1);
  });

  it("validates speaker / handle / group / plan / device bodies", () => {
    assert.equal(parseWithSchema(speakerUpsertSchema, { id: "s1", name: "Ana" }).ok, true);
    assert.equal(parseWithSchema(speakerUpsertSchema, { id: "s1", name: "" }).ok, false);
    assert.equal(parseWithSchema(handleBodySchema, { handle: "betoverli" }).ok, true);
    assert.equal(parseWithSchema(handleBodySchema, {}).ok, false);
    assert.equal(parseWithSchema(groupCreateSchema, { name: "Grupo" }).ok, true);
    assert.equal(parseWithSchema(planMarkSchema, { planId: "gospels-30", day: 1 }).ok, true);
    assert.equal(parseWithSchema(planMarkSchema, { planId: "gospels-30", day: "2", on: false }).ok, true);
    assert.equal(parseWithSchema(devicesApnsDeleteSchema, { all: true }).ok, true);
    assert.equal(parseWithSchema(devicesApnsDeleteSchema, { token: "abc" }).ok, true);
    assert.equal(parseWithSchema(devicesApnsDeleteSchema, { deviceId: "device-123" }).ok, true);
    assert.equal(parseWithSchema(devicesApnsDeleteSchema, {}).ok, false);
    assert.equal(
      parseWithSchema(devicesApnsPostSchema, {
        token: "a".repeat(64),
        deviceId: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE",
        sandbox: true,
      }).ok,
      true,
    );
    assert.equal(
      parseWithSchema(devicesApnsPostSchema, {
        token: "a".repeat(64),
        deviceId: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE",
        environment: "production",
      }).ok,
      true,
    );
    assert.equal(parseWithSchema(devicesApnsPostSchema, { token: "a".repeat(64) }).ok, false);
  });

  it("validates email sign-in and sign-up bodies", () => {
    assert.equal(emailPasswordMinLength, 8);
    assert.equal(parseWithSchema(authEmailSchema, { email: "a@b.co", password: "x" }).ok, true);
    assert.equal(parseWithSchema(authEmailSchema, { email: "", password: "x" }).ok, false);
    assert.equal(
      parseWithSchema(authEmailSignUpSchema, {
        name: "Ana",
        email: "ana@example.com",
        password: "password1",
      }).ok,
      true,
    );
    assert.equal(
      parseWithSchema(authEmailSignUpSchema, {
        name: "",
        email: "ana@example.com",
        password: "password1",
      }).ok,
      false,
    );
    assert.equal(
      parseWithSchema(authEmailForgotPasswordSchema, { email: "ana@example.com", locale: "pt" }).ok,
      true,
    );
    assert.equal(parseWithSchema(authEmailForgotPasswordSchema, { email: "" }).ok, false);
    assert.equal(
      parseWithSchema(authEmailResetPasswordSchema, {
        email: "ana@example.com",
        code: "123456",
        newPassword: "password1",
      }).ok,
      true,
    );
    assert.equal(
      parseWithSchema(authEmailResetPasswordSchema, {
        email: "ana@example.com",
        code: "",
        newPassword: "password1",
      }).ok,
      false,
    );
  });
});
