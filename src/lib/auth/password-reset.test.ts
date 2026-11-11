import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { describe, it } from "node:test";
import {
  PASSWORD_RESET_EMAIL_RATE_MAX,
  PASSWORD_RESET_MAX_ATTEMPTS,
  PASSWORD_RESET_TTL_MS,
  asPasswordResetLocale,
  generateResetCode,
  hashResetCode,
  isSixDigitCode,
  normalizeResetEmail,
  resetCodesMatch,
} from "./password-reset-code.ts";
import { buildPasswordResetEmail } from "./password-reset-email.ts";

const root = new URL("../../../", import.meta.url);

function read(rel: string) {
  return readFileSync(new URL(rel, root), "utf8");
}

describe("password reset codes", () => {
  it("generates 6-digit codes and hashes them with HMAC", () => {
    const code = generateResetCode();
    assert.equal(isSixDigitCode(code), true);
    assert.equal(code.length, 6);
    const hash = hashResetCode("user-1", code);
    assert.notEqual(hash, code);
    assert.equal(resetCodesMatch(hash, "user-1", code), true);
    assert.equal(resetCodesMatch(hash, "user-1", "000000"), false);
    assert.equal(resetCodesMatch(hash, "other-user", code), false);
  });

  it("normalizes email and locale with en fallback", () => {
    assert.equal(normalizeResetEmail("  Ana@Example.COM "), "ana@example.com");
    assert.equal(asPasswordResetLocale("pt-BR"), "pt");
    assert.equal(asPasswordResetLocale("es-MX"), "es");
    assert.equal(asPasswordResetLocale("en-US"), "en");
    assert.equal(asPasswordResetLocale("fr"), "en");
    assert.equal(asPasswordResetLocale(undefined), "en");
  });

  it("documents security constants", () => {
    assert.equal(PASSWORD_RESET_TTL_MS, 15 * 60_000);
    assert.equal(PASSWORD_RESET_MAX_ATTEMPTS, 5);
    assert.equal(PASSWORD_RESET_EMAIL_RATE_MAX, 3);
  });

  it("builds localized emails with Katecheo as one word and a prominent code", () => {
    for (const locale of ["pt", "en", "es"] as const) {
      const copy = buildPasswordResetEmail(locale, "123456");
      assert.match(copy.subject, /Katecheo/);
      assert.match(copy.text, /123456/);
      assert.match(copy.text, /15/);
      assert.match(copy.html, /123456/);
      assert.match(copy.html, />Katecheo</);
      // Reject split brand spellings (space / hyphen / underscore), not the word itself.
      assert.doesNotMatch(copy.html, /Kate[\s_-]+cheo/i);
      assert.doesNotMatch(copy.text, /Kate[\s_-]+cheo/i);
    }
    assert.match(buildPasswordResetEmail("pt", "999999").subject, /código|codigo|Katecheo/i);
    assert.match(buildPasswordResetEmail("en", "999999").subject, /code/i);
    assert.match(buildPasswordResetEmail("es", "999999").subject, /código|codigo/i);
  });

  it("ships migration + Resend fetch client + native handlers (no website reset page)", () => {
    const migration = read("migrations/0025_password_reset.sql");
    assert.match(migration, /password_reset_codes/);
    assert.match(migration, /code_hash/);
    assert.match(migration, /attempts/);

    const resend = read("src/lib/auth/resend-email.server.ts");
    assert.match(resend, /api\.resend\.com\/emails/);
    assert.match(resend, /RESEND_API_KEY/);
    assert.match(resend, /EMAIL_FROM/);

    const auth = read("src/lib/native/api/v1-auth.server.ts");
    assert.match(auth, /forgotPasswordNative/);
    assert.match(auth, /resetPasswordNative/);
    assert.match(auth, /GENERIC_FORGOT_OK|ok: true as const/);
    assert.match(auth, /code_exhausted/);
    assert.match(auth, /deleteUserSessions/);
    assert.match(auth, /createSession/);

    const router = read("src/lib/native/api/v1-router.ts");
    assert.match(router, /auth-email-forgot-password/);
    assert.match(router, /auth-email-reset-password/);
    assert.match(router, /forgot-password/);
    assert.match(router, /reset-password/);

    const http = read("src/lib/native/api/v1-http.ts");
    assert.match(http, /forgotPasswordNative/);
    assert.match(http, /resetPasswordNative/);

    // Website must not gain a reset page.
    assert.equal(
      (() => {
        try {
          return read("src/routes/reset-password.tsx");
        } catch {
          return null;
        }
      })(),
      null,
    );
    const login = read("src/routes/login.tsx");
    assert.doesNotMatch(login, /forgot-password|reset-password|Esqueci minha senha/i);
  });
});
