import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { describe, it } from "node:test";
import { matchNativeV1Route, methodAllowed, isPublicNativeAuthRoute } from "./v1-router.ts";

const moderationSrc = readFileSync(new URL("./v1-moderation.server.ts", import.meta.url), "utf8");
const schemasSrc = readFileSync(new URL("./v1-schemas.ts", import.meta.url), "utf8");
const migrationSrc = readFileSync(
  new URL("../../../../migrations/0028_user_block_report.sql", import.meta.url),
  "utf8",
);
const socialSrc = readFileSync(new URL("./v1-social.server.ts", import.meta.url), "utf8");
const groupsSrc = readFileSync(new URL("./v1-groups.server.ts", import.meta.url), "utf8");
const clientSrc = readFileSync(
  new URL("../../../../ios/App/Katecheo/NativeAPIClient.swift", import.meta.url),
  "utf8",
);
const reportUiSrc = readFileSync(
  new URL("../../../../ios/App/Katecheo/ReportBlockSupport.swift", import.meta.url),
  "utf8",
);

describe("native report & block (Guideline 1.2)", () => {
  it("ships migration 0028 with user_block + content_report", () => {
    assert.match(migrationSrc, /create table if not exists user_block/);
    assert.match(migrationSrc, /unique|primary key \(blocker_id, blocked_id\)/);
    assert.match(migrationSrc, /create table if not exists content_report/);
    assert.match(migrationSrc, /target_type in \('user', 'note', 'group'\)/);
  });

  it("maps report / blocks / block/:userId routes (auth required)", () => {
    assert.deepEqual(matchNativeV1Route("report"), { kind: "report" });
    assert.deepEqual(matchNativeV1Route("blocks"), { kind: "blocks" });
    assert.deepEqual(matchNativeV1Route("block/u1"), { kind: "block", userId: "u1" });
    assert.equal(isPublicNativeAuthRoute({ kind: "report" }), false);
    assert.equal(isPublicNativeAuthRoute({ kind: "blocks" }), false);
    assert.equal(isPublicNativeAuthRoute({ kind: "block", userId: "u1" }), false);
  });

  it("only allows the intended verbs", () => {
    assert.equal(methodAllowed({ kind: "report" }, "POST"), true);
    assert.equal(methodAllowed({ kind: "report" }, "GET"), false);
    assert.equal(methodAllowed({ kind: "blocks" }, "GET"), true);
    assert.equal(methodAllowed({ kind: "blocks" }, "POST"), false);
    assert.equal(methodAllowed({ kind: "block", userId: "u1" }, "POST"), true);
    assert.equal(methodAllowed({ kind: "block", userId: "u1" }, "DELETE"), true);
    assert.equal(methodAllowed({ kind: "block", userId: "u1" }, "GET"), false);
  });

  it("ships contentReportSchema with user|note|group and spam/offensive/inappropriate/other", () => {
    assert.match(schemasSrc, /export const contentReportSchema/);
    assert.match(schemasSrc, /z\.enum\(\["user", "note", "group"\]\)/);
    assert.match(schemasSrc, /z\.enum\(\["spam", "offensive", "inappropriate", "other"\]\)/);
  });

  it("wires block helpers into friendship + shared content filters", () => {
    assert.match(moderationSrc, /export async function blockUserForUser/);
    assert.match(moderationSrc, /export async function unblockUserForUser/);
    assert.match(moderationSrc, /export async function listBlocksForUser/);
    assert.match(moderationSrc, /export async function reportContentForUser/);
    assert.match(moderationSrc, /sendResendEmail/);
    assert.match(moderationSrc, /contato@katecheo\.app|CONTACT_EMAIL/);
    assert.match(moderationSrc, /delete from user_links/);
    assert.match(moderationSrc, /delete from note_grants/);
    assert.match(socialSrc, /isEitherBlocked/);
    assert.match(socialSrc, /blockedIdsForUser/);
    assert.match(groupsSrc, /blockedIdsForUser/);
    const notifySrc = readFileSync(new URL("../../notify.server.ts", import.meta.url), "utf8");
    assert.match(notifySrc, /blockedIdsForUser/);
    assert.match(notifySrc, /if \(blocked\.has\(actorId\)\) return/);
  });

  it("ships iOS client + Report/Bloquear UI helpers", () => {
    assert.match(clientSrc, /func reportContent\(/);
    assert.match(clientSrc, /func blockUser\(userId:/);
    assert.match(clientSrc, /func unblockUser\(userId:/);
    assert.match(clientSrc, /func listBlockedUsers\(/);
    assert.match(clientSrc, /api\/native\/v1\/report/);
    assert.match(clientSrc, /api\/native\/v1\/block\//);
    assert.match(clientSrc, /api\/native\/v1\/blocks/);
    assert.match(reportUiSrc, /Denunciar/);
    assert.match(reportUiSrc, /Bloquear/);
    assert.match(reportUiSrc, /Usuários bloqueados/);
  });
});
