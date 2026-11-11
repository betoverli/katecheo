/**
 * Bearer-authenticated Contas conectadas endpoints under `/api/native/v1/auth/identities*`.
 */
import { APPLE_PROVIDER_ID, appleNativeFromEnv } from "@/lib/auth/apple";
import {
  storeAppleRefreshToken,
} from "@/lib/auth/apple-native.server";
import { exchangeAppleAuthorizationCode } from "@/lib/auth/apple-token.server";
import {
  AppleTokenVerifyError,
  verifyAppleIdentityToken,
} from "@/lib/auth/apple-verify.server";
import {
  emailAndPasswordEnabled,
  emailPasswordMinLength,
} from "@/lib/auth/email-password";
import { GOOGLE_PROVIDER_ID, googleOAuthFromEnv } from "@/lib/auth/google";
import {
  CREDENTIAL_PROVIDER_ID,
  decideGoogleReassign,
  decideLinkIdentity,
  decideSetPassword,
  decideUnlinkIdentity,
  IDENTITY_PROVIDERS,
  maskEmail,
  normalizeIdentityProvider,
  providerIdForIdentity,
  type IdentityProvider,
} from "@/lib/auth/identity-link";
import { auth, authConfigured } from "@/lib/auth/server";
import { getSql } from "@/lib/db";
import { allowRequest, clientKey } from "@/lib/rate-limit";
import { currentHandoffKey, openSessionToken } from "@/lib/native/handoff-seal.server";
import { hashHandoffCode, isHandoffCode } from "@/lib/native/handoff-code";
import { isPkceMaterial, pkceChallenge } from "@/lib/native/pkce";

const RECENT_SHELL_MS = 5 * 60_000;

export type IdentityRowDTO = {
  provider: IdentityProvider;
  linked: boolean;
  emailMasked: string | null;
};

type AccountRow = {
  id: string;
  accountId: string;
  providerId: string;
  userId: string;
  password: string | null;
};

function fail(error: string, status: number) {
  return { ok: false as const, error, status };
}

async function rateOrFail(
  request: Request,
  bucket: string,
  max: number,
): Promise<ReturnType<typeof fail> | null> {
  const ip = clientKey(request);
  if (!(await allowRequest(`${bucket}:${ip}`, max, 60_000))) {
    return fail("rate_limited", 429);
  }
  return null;
}

async function listAccountsForUser(userId: string): Promise<AccountRow[]> {
  const sql = await getSql();
  return sql<AccountRow>`
    select id, "accountId" as "accountId", "providerId" as "providerId",
           "userId" as "userId", password
    from account
    where "userId" = ${userId}
  `;
}

function linkedProvidersFromAccounts(accounts: AccountRow[]): Set<IdentityProvider> {
  const linked = new Set<IdentityProvider>();
  for (const row of accounts) {
    if (row.providerId === APPLE_PROVIDER_ID) linked.add("apple");
    if (row.providerId === GOOGLE_PROVIDER_ID) linked.add("google");
    if (row.providerId === CREDENTIAL_PROVIDER_ID && row.password) linked.add("password");
  }
  return linked;
}

async function appleSubForUser(userId: string): Promise<string | null> {
  const sql = await getSql();
  const rows = await sql<{ apple_sub: string | null }>`
    select apple_sub from "user" where id = ${userId} limit 1
  `;
  return rows[0]?.apple_sub?.trim() || null;
}

async function emailForUser(userId: string): Promise<string | null> {
  const sql = await getSql();
  const rows = await sql<{ email: string }>`
    select email from "user" where id = ${userId} limit 1
  `;
  return rows[0]?.email?.trim() || null;
}

/** GET /auth/identities */
export async function listIdentitiesForUser(
  request: Request,
  userId: string,
): Promise<
  | { ok: true; identities: IdentityRowDTO[]; minPasswordLength: number }
  | { ok: false; error: string; status: number }
> {
  const limited = await rateOrFail(request, "native-v1-identities", 60);
  if (limited) return limited;

  const accounts = await listAccountsForUser(userId);
  const linked = linkedProvidersFromAccounts(accounts);
  const appleSub = await appleSubForUser(userId);
  if (appleSub) linked.add("apple");

  const userEmail = await emailForUser(userId);

  const identities: IdentityRowDTO[] = IDENTITY_PROVIDERS.map((provider) => {
    const isLinked = linked.has(provider);
    const emailMasked = isLinked ? maskEmail(userEmail) : null;
    return { provider, linked: isLinked, emailMasked };
  });

  return {
    ok: true,
    identities,
    minPasswordLength: emailPasswordMinLength,
  };
}

async function findAccountOwner(
  providerId: string,
  accountId: string,
): Promise<{ userId: string; accountRowId: string } | null> {
  const sql = await getSql();
  const rows = await sql<{ id: string; userId: string }>`
    select id, "userId" as "userId"
    from account
    where "providerId" = ${providerId}
      and "accountId" = ${accountId}
    limit 1
  `;
  const row = rows[0];
  if (!row) return null;
  return { userId: row.userId, accountRowId: row.id };
}

async function ensureProviderAccount(
  userId: string,
  providerId: string,
  accountId: string,
  extra?: { refreshToken?: string | null },
): Promise<void> {
  const ctx = await auth.$context;
  const accounts = await ctx.internalAdapter.findAccounts(userId);
  const existing = accounts.find(
    (item) => item.providerId === providerId && item.accountId === accountId,
  );
  if (existing) {
    if (extra?.refreshToken) {
      await ctx.internalAdapter.updateAccount(existing.id, {
        refreshToken: extra.refreshToken,
        updatedAt: new Date(),
      });
    }
    return;
  }
  await ctx.internalAdapter.linkAccount({
    userId,
    providerId,
    accountId,
    ...(extra?.refreshToken ? { refreshToken: extra.refreshToken } : {}),
  });
}

/** POST /auth/identities/link/apple */
export async function linkAppleIdentity(
  request: Request,
  userId: string,
  body: {
    identityToken?: unknown;
    authorizationCode?: unknown;
    nonce?: unknown;
  },
): Promise<{ ok: true } | { ok: false; error: string; status: number }> {
  const apple = appleNativeFromEnv(process.env);
  if (!apple.configured || !authConfigured) {
    return fail("apple_disabled", 501);
  }
  const limited = await rateOrFail(request, "native-v1-link-apple", 20);
  if (limited) return limited;

  const identityToken = typeof body.identityToken === "string" ? body.identityToken.trim() : "";
  if (!identityToken) return fail("invalid", 400);
  const nonce = typeof body.nonce === "string" ? body.nonce : undefined;
  const authorizationCode =
    typeof body.authorizationCode === "string" ? body.authorizationCode.trim() : "";

  try {
    const claims = await verifyAppleIdentityToken(identityToken, {
      audience: apple.audience,
      nonce: nonce ?? null,
    });
    const sub = claims.sub;

    const bySub = await (async () => {
      const sql = await getSql();
      const rows = await sql<{ id: string }>`
        select id from "user" where apple_sub = ${sub} limit 1
      `;
      return rows[0]?.id ?? null;
    })();
    const byAccount = await findAccountOwner(APPLE_PROVIDER_ID, sub);
    const ownerUserId = bySub ?? byAccount?.userId ?? null;

    const decision = decideLinkIdentity({ currentUserId: userId, ownerUserId });
    if (decision.action === "conflict") {
      return fail("identity_in_use", 409);
    }

    let refreshToken: string | null = null;
    if (authorizationCode) {
      const exchanged = await exchangeAppleAuthorizationCode(authorizationCode);
      refreshToken = exchanged.refreshToken ?? null;
    }

    if (decision.action === "already_linked") {
      if (refreshToken) {
        await storeAppleRefreshToken(userId, sub, refreshToken);
      }
      return { ok: true };
    }

    if (refreshToken) {
      await storeAppleRefreshToken(userId, sub, refreshToken);
    } else {
      const sql = await getSql();
      await sql`
        update "user"
        set apple_sub = ${sub}, "updatedAt" = now()
        where id = ${userId}
      `;
      await ensureProviderAccount(userId, APPLE_PROVIDER_ID, sub);
    }
    return { ok: true };
  } catch (error) {
    if (error instanceof AppleTokenVerifyError) {
      console.error("[native/v1/auth/identities/link/apple]", error.code, error.message);
      return fail("apple_failed", 401);
    }
    console.error("[native/v1/auth/identities/link/apple]", error);
    return fail("apple_failed", 401);
  }
}

async function openHandoffToken(
  code: string,
  verifier: string,
): Promise<string | null> {
  if (!isHandoffCode(code) || !isPkceMaterial(verifier)) return null;
  const challenge = await pkceChallenge(verifier);
  const resolved = currentHandoffKey();
  if (!resolved.ok) return null;
  const sql = await getSql();
  const rows = await sql<{ token_ciphertext: string; user_id: string }>`
    delete from native_auth_handoff
    where code_hash = ${hashHandoffCode(code)}
      and challenge = ${challenge}
      and token_ciphertext is not null
      and expires_at > now()
    returning token_ciphertext, user_id
  `;
  const sealed = rows[0]?.token_ciphertext;
  if (!sealed) return null;
  return openSessionToken(sealed, resolved.key);
}

async function sessionUserIdFromToken(token: string): Promise<string | null> {
  const sql = await getSql();
  const rows = await sql<{ userId: string }>`
    select "userId" as "userId"
    from session
    where token = ${token}
      and "expiresAt" > now()
    limit 1
  `;
  return rows[0]?.userId ?? null;
}

async function userShellMeta(userId: string): Promise<{
  accountCount: number;
  hasContent: boolean;
  createdRecently: boolean;
}> {
  const sql = await getSql();
  const accounts = await sql<{ n: number }>`
    select count(*)::int as n from account where "userId" = ${userId}
  `;
  const notes = await sql<{ n: number }>`
    select count(*)::int as n from notebook_notes where user_id = ${userId} limit 1
  `;
  const user = await sql<{ createdAt: string | Date }>`
    select "createdAt" as "createdAt" from "user" where id = ${userId} limit 1
  `;
  const createdAt = user[0]?.createdAt ? new Date(user[0].createdAt).getTime() : 0;
  return {
    accountCount: Number(accounts[0]?.n ?? 0),
    hasContent: Number(notes[0]?.n ?? 0) > 0,
    createdRecently: createdAt > 0 && Date.now() - createdAt < RECENT_SHELL_MS,
  };
}

async function deleteEmptyShellUser(userId: string): Promise<void> {
  const sql = await getSql();
  await sql`delete from session where "userId" = ${userId}`;
  const remaining = await sql<{ n: number }>`
    select count(*)::int as n from account where "userId" = ${userId}
  `;
  if (Number(remaining[0]?.n ?? 0) > 0) return;
  const notes = await sql<{ n: number }>`
    select count(*)::int as n from notebook_notes where user_id = ${userId}
  `;
  if (Number(notes[0]?.n ?? 0) > 0) return;
  await sql`delete from "user" where id = ${userId}`;
}

/** POST /auth/identities/link/google — body matches claim: { code, verifier }. */
export async function linkGoogleIdentity(
  request: Request,
  userId: string,
  body: { code?: unknown; verifier?: unknown },
): Promise<{ ok: true } | { ok: false; error: string; status: number }> {
  const google = googleOAuthFromEnv(process.env);
  if (!google.configured || !authConfigured) {
    return fail("google_disabled", 501);
  }
  const limited = await rateOrFail(request, "native-v1-link-google", 20);
  if (limited) return limited;

  const code = typeof body.code === "string" ? body.code : "";
  const verifier = typeof body.verifier === "string" ? body.verifier : "";
  const token = await openHandoffToken(code, verifier);
  if (!token) return fail("invalid_code", 401);

  const googleUserId = await sessionUserIdFromToken(token);
  if (!googleUserId) return fail("invalid_code", 401);

  const sql = await getSql();
  // Drop the temporary Google session so the client keeps the current bearer.
  await sql`delete from session where token = ${token}`;

  const googleAccounts = await sql<AccountRow>`
    select id, "accountId" as "accountId", "providerId" as "providerId",
           "userId" as "userId", password
    from account
    where "userId" = ${googleUserId}
      and "providerId" = ${GOOGLE_PROVIDER_ID}
    limit 1
  `;
  const googleAccount = googleAccounts[0];
  if (!googleAccount) return fail("google_failed", 401);

  const owner = await findAccountOwner(GOOGLE_PROVIDER_ID, googleAccount.accountId);
  let decision = decideLinkIdentity({
    currentUserId: userId,
    ownerUserId: owner?.userId ?? null,
  });

  if (decision.action === "conflict" && owner && owner.userId !== userId) {
    const meta = await userShellMeta(owner.userId);
    decision = decideGoogleReassign({
      currentUserId: userId,
      ownerUserId: owner.userId,
      ownerAccountCount: meta.accountCount,
      ownerHasContent: meta.hasContent,
      ownerCreatedRecently: meta.createdRecently,
    });
    if (decision.action === "link") {
      await sql`
        update account
        set "userId" = ${userId}, "updatedAt" = now()
        where id = ${googleAccount.id}
      `;
      await deleteEmptyShellUser(owner.userId);
      return { ok: true };
    }
  }

  if (decision.action === "conflict") {
    return fail("identity_in_use", 409);
  }
  if (decision.action === "already_linked") {
    return { ok: true };
  }

  await ensureProviderAccount(userId, GOOGLE_PROVIDER_ID, googleAccount.accountId, {
    refreshToken: null,
  });
  // If googleUserId was current (email auto-link during OAuth), done.
  if (googleUserId !== userId) {
    // Defensive: should have been handled by reassign path.
    return fail("identity_in_use", 409);
  }
  return { ok: true };
}

/** POST /auth/identities/set-password */
export async function setPasswordIdentity(
  request: Request,
  userId: string,
  body: { password?: unknown; currentPassword?: unknown },
): Promise<{ ok: true } | { ok: false; error: string; status: number }> {
  if (!emailAndPasswordEnabled || !authConfigured) {
    return fail("email_disabled", 501);
  }
  const limited = await rateOrFail(request, "native-v1-set-password", 15);
  if (limited) return limited;

  const password = typeof body.password === "string" ? body.password : "";
  const currentPassword =
    typeof body.currentPassword === "string" ? body.currentPassword : "";
  if (!password) return fail("invalid", 400);
  if (password.length < emailPasswordMinLength) return fail("password_short", 400);
  if (password.length > 200) return fail("invalid", 400);

  const userEmail = await emailForUser(userId);
  if (!userEmail) return fail("no_email", 400);

  try {
    const ctx = await auth.$context;
    const accounts = await ctx.internalAdapter.findAccounts(userId);
    const credential = accounts.find(
      (item) => item.providerId === CREDENTIAL_PROVIDER_ID && item.password,
    );
    const decision = decideSetPassword({ hasCredential: Boolean(credential) });

    if (decision.action === "change") {
      if (!currentPassword) {
        return fail("current_password_required", 400);
      }
      const valid = await ctx.password.verify({
        hash: credential!.password!,
        password: currentPassword,
      });
      if (!valid) return fail("credentials", 401);
      const passwordHash = await ctx.password.hash(password);
      await ctx.internalAdapter.updatePassword(userId, passwordHash);
      return { ok: true };
    }

    const passwordHash = await ctx.password.hash(password);
    await ctx.internalAdapter.linkAccount({
      userId,
      providerId: CREDENTIAL_PROVIDER_ID,
      accountId: userId,
      password: passwordHash,
    });
    return { ok: true };
  } catch (error) {
    console.error("[native/v1/auth/identities/set-password]", error);
    return fail("server_error", 500);
  }
}

/** DELETE /auth/identities/unlink/:provider */
export async function unlinkIdentity(
  request: Request,
  userId: string,
  providerRaw: string,
): Promise<{ ok: true } | { ok: false; error: string; status: number }> {
  const limited = await rateOrFail(request, "native-v1-unlink", 20);
  if (limited) return limited;

  const provider = normalizeIdentityProvider(providerRaw);
  if (!provider) return fail("invalid", 400);

  const accounts = await listAccountsForUser(userId);
  const linked = linkedProvidersFromAccounts(accounts);
  const appleSub = await appleSubForUser(userId);
  if (appleSub) linked.add("apple");

  const decision = decideUnlinkIdentity({
    providerLinked: linked.has(provider),
    linkedMethodCount: linked.size,
  });
  if (decision.action === "refuse") {
    return fail(decision.code, decision.code === "last_method" ? 400 : 404);
  }

  const sql = await getSql();
  const providerId = providerIdForIdentity(provider);

  if (provider === "apple") {
    await sql`
      update "user"
      set apple_sub = null,
          apple_refresh_token = null,
          "updatedAt" = now()
      where id = ${userId}
    `;
  }

  await sql`
    delete from account
    where "userId" = ${userId}
      and "providerId" = ${providerId}
  `;

  return { ok: true };
}
