/**
 * Pure find / link / create decisions for Sign in with Apple (no DB I/O).
 * Used by `apple-native.server.ts` and unit tests.
 */
import { isApplePrivateRelayEmail } from "./apple.ts";

export type AppleLinkCandidate = {
  id: string;
  email: string;
  emailVerified: boolean;
  appleSub: string | null;
};

export type AppleLinkClaims = {
  sub: string;
  email: string | null;
  emailVerified: boolean;
  isPrivateEmail: boolean;
};

export type AppleLinkDecision =
  | { action: "use_existing"; userId: string; reason: "apple_sub" | "account" }
  | { action: "link_email"; userId: string }
  | { action: "create" };

/**
 * Decide how to attach an Apple `sub` to a local user.
 * Priority: apple_sub → account(provider=apple) → verified email → create.
 */
export function decideAppleUserLink(input: {
  byAppleSub: AppleLinkCandidate | null;
  byAppleAccount: AppleLinkCandidate | null;
  byEmail: AppleLinkCandidate | null;
  claims: AppleLinkClaims;
}): AppleLinkDecision {
  if (input.byAppleSub) {
    return { action: "use_existing", userId: input.byAppleSub.id, reason: "apple_sub" };
  }
  if (input.byAppleAccount) {
    return { action: "use_existing", userId: input.byAppleAccount.id, reason: "account" };
  }

  const email = input.claims.email?.trim().toLowerCase() || null;
  const row = input.byEmail;
  if (email && row) {
    const canLink =
      row.emailVerified ||
      input.claims.emailVerified ||
      isApplePrivateRelayEmail(email) ||
      input.claims.isPrivateEmail;
    // Do not steal an account that already has a different Apple sub.
    if (canLink && (!row.appleSub || row.appleSub === input.claims.sub)) {
      return { action: "link_email", userId: row.id };
    }
  }

  return { action: "create" };
}
