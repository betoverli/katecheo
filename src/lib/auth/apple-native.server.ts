/**
 * Find / link / create a Better Auth user from a verified Apple identity.
 * Also mints a session token for the native Keychain bearer.
 */
import { getSql } from "@/lib/db";
import { cleanName } from "@/lib/profile";
import { auth } from "@/lib/auth/server";
import {
  APPLE_PROVIDER_ID,
  applePlaceholderEmail,
  isApplePrivateRelayEmail,
} from "./apple.ts";
import { decideAppleUserLink } from "./apple-link.ts";
import type { AppleIdentityClaims } from "./apple-verify.server.ts";

export type AppleFullName = {
  givenName?: string | null;
  familyName?: string | null;
  firstName?: string | null;
  lastName?: string | null;
};

export type AppleUserRecord = {
  id: string;
  email: string;
  name: string;
  linked: boolean;
  created: boolean;
};

type UserRow = {
  id: string;
  email: string;
  name: string;
  emailVerified: boolean;
  apple_sub: string | null;
};

function displayNameFrom(fullName: AppleFullName | null | undefined, fallback: string): string {
  if (!fullName) return fallback;
  const first = cleanName(
    String(fullName.givenName ?? fullName.firstName ?? ""),
  );
  const last = cleanName(
    String(fullName.familyName ?? fullName.lastName ?? ""),
  );
  const joined = [first, last].filter(Boolean).join(" ").trim();
  return joined || fallback;
}

function splitName(fullName: AppleFullName | null | undefined): {
  firstName: string;
  lastName: string;
} {
  if (!fullName) return { firstName: "", lastName: "" };
  return {
    firstName: cleanName(String(fullName.givenName ?? fullName.firstName ?? "")),
    lastName: cleanName(String(fullName.familyName ?? fullName.lastName ?? "")),
  };
}

async function applyNameToPrefs(
  userId: string,
  fullName: AppleFullName | null | undefined,
): Promise<void> {
  const { firstName, lastName } = splitName(fullName);
  if (!firstName && !lastName) return;
  const sql = await getSql();
  const existing = await sql<{ user_id: string }>`
    select user_id from user_prefs where user_id = ${userId} limit 1
  `;
  if (existing[0]) {
    await sql`
      update user_prefs set
        first_name = case
          when ${firstName} <> '' and (first_name = '' or first_name is null)
          then ${firstName} else first_name end,
        last_name = case
          when ${lastName} <> '' and (last_name = '' or last_name is null)
          then ${lastName} else last_name end,
        updated_at = now()
      where user_id = ${userId}
    `;
    return;
  }
  await sql`
    insert into user_prefs (
      user_id, locale, app_id, translation_id, prefer_native, first_name, last_name
    ) values (
      ${userId}, 'pt', 'youversion', '111', true, ${firstName}, ${lastName}
    )
  `;
}

async function ensureAppleAccount(userId: string, sub: string, refreshToken: string | null) {
  const ctx = await auth.$context;
  const accounts = await ctx.internalAdapter.findAccounts(userId);
  const existing = accounts.find(
    (item) => item.providerId === APPLE_PROVIDER_ID && item.accountId === sub,
  );
  if (existing) {
    if (refreshToken) {
      await ctx.internalAdapter.updateAccount(existing.id, {
        refreshToken,
        updatedAt: new Date(),
      });
    }
    return;
  }
  await ctx.internalAdapter.linkAccount({
    userId,
    providerId: APPLE_PROVIDER_ID,
    accountId: sub,
    ...(refreshToken ? { refreshToken } : {}),
  });
}

async function setAppleColumns(
  userId: string,
  sub: string,
  refreshToken: string | null,
): Promise<void> {
  const sql = await getSql();
  if (refreshToken) {
    await sql`
      update "user"
      set apple_sub = ${sub},
          apple_refresh_token = ${refreshToken},
          "updatedAt" = now()
      where id = ${userId}
    `;
  } else {
    await sql`
      update "user"
      set apple_sub = ${sub},
          "updatedAt" = now()
      where id = ${userId}
    `;
  }
}

/**
 * Resolve an Apple `sub` to a local user: by apple_sub, by account row, by
 * verified email (incl. private relay), or create a new user.
 */
export async function findOrCreateAppleUser(
  claims: AppleIdentityClaims,
  fullName?: AppleFullName | null,
): Promise<AppleUserRecord> {
  const sql = await getSql();
  const sub = claims.sub;
  const email = claims.email?.trim().toLowerCase() || null;
  const nameHint = displayNameFrom(fullName, "");

  const bySub = await sql<UserRow>`
    select id, email, name, "emailVerified" as "emailVerified", apple_sub
    from "user"
    where apple_sub = ${sub}
    limit 1
  `;
  const byAccount = bySub[0]
    ? []
    : await sql<UserRow>`
        select u.id, u.email, u.name, u."emailVerified" as "emailVerified", u.apple_sub
        from "user" u
        join account a on a."userId" = u.id
        where a."providerId" = ${APPLE_PROVIDER_ID}
          and a."accountId" = ${sub}
        limit 1
      `;
  const byEmail =
    bySub[0] || byAccount[0] || !email
      ? []
      : await sql<UserRow>`
          select id, email, name, "emailVerified" as "emailVerified", apple_sub
          from "user"
          where lower(email) = ${email}
          limit 1
        `;

  const decision = decideAppleUserLink({
    byAppleSub: bySub[0]
      ? {
          id: bySub[0].id,
          email: bySub[0].email,
          emailVerified: bySub[0].emailVerified,
          appleSub: bySub[0].apple_sub,
        }
      : null,
    byAppleAccount: byAccount[0]
      ? {
          id: byAccount[0].id,
          email: byAccount[0].email,
          emailVerified: byAccount[0].emailVerified,
          appleSub: byAccount[0].apple_sub,
        }
      : null,
    byEmail: byEmail[0]
      ? {
          id: byEmail[0].id,
          email: byEmail[0].email,
          emailVerified: byEmail[0].emailVerified,
          appleSub: byEmail[0].apple_sub,
        }
      : null,
    claims: {
      sub,
      email,
      emailVerified: claims.emailVerified,
      isPrivateEmail: claims.isPrivateEmail,
    },
  });

  if (decision.action === "use_existing") {
    const row =
      decision.reason === "apple_sub" ? bySub[0]! : byAccount[0]!;
    if (decision.reason === "account") {
      await setAppleColumns(row.id, sub, null);
    }
    if (nameHint && (!row.name || row.name === "Katecheo")) {
      const ctx = await auth.$context;
      await ctx.internalAdapter.updateUser(row.id, { name: nameHint });
    }
    await applyNameToPrefs(row.id, fullName);
    return {
      id: row.id,
      email: row.email,
      name: nameHint || row.name,
      linked: decision.reason === "account",
      created: false,
    };
  }

  if (decision.action === "link_email") {
    const row = byEmail[0]!;
    await setAppleColumns(row.id, sub, null);
    await ensureAppleAccount(row.id, sub, null);
    if (nameHint && (!row.name || row.name === "Katecheo")) {
      const ctx = await auth.$context;
      await ctx.internalAdapter.updateUser(row.id, { name: nameHint });
    }
    await applyNameToPrefs(row.id, fullName);
    return {
      id: row.id,
      email: row.email,
      name: nameHint || row.name,
      linked: true,
      created: false,
    };
  }

  const ctx = await auth.$context;
  const emailForCreate = email || applePlaceholderEmail(sub);
  const nameForCreate = nameHint || "Katecheo";
  const created = await ctx.internalAdapter.createOAuthUser(
    {
      email: emailForCreate,
      name: nameForCreate,
      emailVerified:
        Boolean(email) && (claims.emailVerified || isApplePrivateRelayEmail(email)),
    },
    {
      providerId: APPLE_PROVIDER_ID,
      accountId: sub,
    },
  );
  if (!created?.user?.id) {
    throw new Error("apple_create_user_failed");
  }
  await setAppleColumns(created.user.id, sub, null);
  await applyNameToPrefs(created.user.id, fullName);
  return {
    id: created.user.id,
    email: created.user.email,
    name: created.user.name,
    linked: false,
    created: true,
  };
}

export async function storeAppleRefreshToken(
  userId: string,
  sub: string,
  refreshToken: string,
): Promise<void> {
  await setAppleColumns(userId, sub, refreshToken);
  await ensureAppleAccount(userId, sub, refreshToken);
}

/** Mint a Better Auth session token for the native Keychain bearer. */
export async function createAppleSessionToken(userId: string): Promise<string> {
  const ctx = await auth.$context;
  const session = await ctx.internalAdapter.createSession(userId, false);
  if (!session?.token) {
    throw new Error("apple_session_failed");
  }
  return session.token;
}

/** Load Apple revoke material before deleting the user row. */
export async function loadAppleRevokeMaterial(
  userId: string,
): Promise<{ appleSub: string | null; refreshToken: string | null }> {
  const sql = await getSql();
  const rows = await sql<{ apple_sub: string | null; apple_refresh_token: string | null }>`
    select apple_sub, apple_refresh_token
    from "user"
    where id = ${userId}
    limit 1
  `;
  const row = rows[0];
  if (!row) return { appleSub: null, refreshToken: null };
  let refresh = row.apple_refresh_token?.trim() || null;
  if (!refresh) {
    const accounts = await sql<{ refreshToken: string | null }>`
      select "refreshToken" as "refreshToken"
      from account
      where "userId" = ${userId}
        and "providerId" = ${APPLE_PROVIDER_ID}
      limit 1
    `;
    refresh = accounts[0]?.refreshToken?.trim() || null;
  }
  return {
    appleSub: row.apple_sub?.trim() || null,
    refreshToken: refresh,
  };
}
