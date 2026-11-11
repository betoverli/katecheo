/**
 * Pure decisions for Contas conectadas (link / unlink / set-password).
 * No DB I/O — unit-tested and reused by the native identities API.
 */

export type IdentityProvider = "apple" | "google" | "password";

export const IDENTITY_PROVIDERS: readonly IdentityProvider[] = [
  "apple",
  "google",
  "password",
] as const;

/** Better Auth `account.providerId` for email/password. */
export const CREDENTIAL_PROVIDER_ID = "credential" as const;

export function providerIdForIdentity(provider: IdentityProvider): string {
  return provider === "password" ? CREDENTIAL_PROVIDER_ID : provider;
}

export function identityFromProviderId(providerId: string): IdentityProvider | null {
  if (providerId === "apple") return "apple";
  if (providerId === "google") return "google";
  if (providerId === CREDENTIAL_PROVIDER_ID) return "password";
  return null;
}

/**
 * Mask an email for display: `a***@example.com`.
 * Returns null when the value is empty or not an email-shaped string.
 */
export function maskEmail(raw: string | null | undefined): string | null {
  const email = typeof raw === "string" ? raw.trim().toLowerCase() : "";
  if (!email || !email.includes("@")) return null;
  const at = email.indexOf("@");
  const local = email.slice(0, at);
  const domain = email.slice(at + 1);
  if (!local || !domain || !domain.includes(".")) return null;
  const visible = local.slice(0, 1);
  return `${visible}***@${domain}`;
}

export type LinkIdentityDecision =
  | { action: "already_linked" }
  | { action: "link" }
  | { action: "conflict"; code: "identity_in_use" };

/**
 * Decide whether a verified external identity may attach to `currentUserId`.
 * `ownerUserId` is who already holds this provider accountId (null = free).
 */
export function decideLinkIdentity(input: {
  currentUserId: string;
  ownerUserId: string | null;
}): LinkIdentityDecision {
  const current = input.currentUserId.trim();
  const owner = input.ownerUserId?.trim() || null;
  if (!current) return { action: "conflict", code: "identity_in_use" };
  if (!owner) return { action: "link" };
  if (owner === current) return { action: "already_linked" };
  return { action: "conflict", code: "identity_in_use" };
}

/**
 * When Google OAuth minted a *different* user for this identity, we may only
 * reassign that account if the other user is a fresh, empty shell (never merge
 * real accounts). Otherwise treat as conflict.
 */
export function decideGoogleReassign(input: {
  currentUserId: string;
  ownerUserId: string;
  ownerAccountCount: number;
  ownerHasContent: boolean;
  ownerCreatedRecently: boolean;
}): LinkIdentityDecision {
  const base = decideLinkIdentity({
    currentUserId: input.currentUserId,
    ownerUserId: input.ownerUserId,
  });
  if (base.action !== "conflict") return base;
  const canReassign =
    input.ownerAccountCount <= 1 &&
    !input.ownerHasContent &&
    input.ownerCreatedRecently;
  return canReassign ? { action: "link" } : { action: "conflict", code: "identity_in_use" };
}

export type UnlinkIdentityDecision =
  | { action: "unlink" }
  | { action: "refuse"; code: "last_method" | "not_linked" };

export function decideUnlinkIdentity(input: {
  providerLinked: boolean;
  linkedMethodCount: number;
}): UnlinkIdentityDecision {
  if (!input.providerLinked) return { action: "refuse", code: "not_linked" };
  if (input.linkedMethodCount <= 1) return { action: "refuse", code: "last_method" };
  return { action: "unlink" };
}

export type SetPasswordDecision =
  | { action: "create" }
  | { action: "change"; requireCurrent: true };

export function decideSetPassword(input: { hasCredential: boolean }): SetPasswordDecision {
  if (input.hasCredential) return { action: "change", requireCurrent: true };
  return { action: "create" };
}

export function isIdentityProvider(raw: string): raw is IdentityProvider {
  return (
    raw === "apple" || raw === "google" || raw === "password" || raw === "credential"
  );
}

export function normalizeIdentityProvider(raw: string): IdentityProvider | null {
  if (raw === "credential" || raw === "password") return "password";
  if (raw === "apple" || raw === "google") return raw;
  return null;
}
