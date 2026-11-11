import { createHmac, randomInt, timingSafeEqual } from "node:crypto";

export const PASSWORD_RESET_CODE_LENGTH = 6;
export const PASSWORD_RESET_TTL_MS = 15 * 60_000;
export const PASSWORD_RESET_MAX_ATTEMPTS = 5;
/** Max forgot-password requests per email in the TTL window. */
export const PASSWORD_RESET_EMAIL_RATE_MAX = 3;
/** Max forgot-password requests per IP in the TTL window. */
export const PASSWORD_RESET_IP_RATE_MAX = 10;
/** Max reset-password attempts per IP per minute. */
export const PASSWORD_RESET_VERIFY_IP_RATE_MAX = 20;

export type PasswordResetLocale = "pt" | "en" | "es";

/** Normalize app/device locale → email copy locale (unknown → en). */
export function asPasswordResetLocale(raw: unknown): PasswordResetLocale {
  const value = typeof raw === "string" ? raw.trim().toLowerCase() : "";
  if (value.startsWith("pt")) return "pt";
  if (value.startsWith("es")) return "es";
  if (value.startsWith("en")) return "en";
  return "en";
}

export function normalizeResetEmail(email: string): string {
  return email.trim().toLowerCase();
}

export function isSixDigitCode(code: string): boolean {
  return /^\d{6}$/.test(code);
}

/** Cryptographically random 6-digit code (000000–999999), zero-padded. */
export function generateResetCode(): string {
  return String(randomInt(0, 1_000_000)).padStart(PASSWORD_RESET_CODE_LENGTH, "0");
}

function hmacSecret(): string {
  return process.env.BETTER_AUTH_SECRET?.trim() || "katecheo-dev-password-reset";
}

/** Store only HMAC(userId:code) — never the plaintext code. */
export function hashResetCode(userId: string, code: string): string {
  return createHmac("sha256", hmacSecret()).update(`${userId}:${code}`).digest("hex");
}

export function resetCodesMatch(expectedHash: string, userId: string, code: string): boolean {
  const actual = hashResetCode(userId, code);
  if (expectedHash.length !== actual.length) return false;
  try {
    return timingSafeEqual(Buffer.from(expectedHash, "utf8"), Buffer.from(actual, "utf8"));
  } catch {
    return false;
  }
}
