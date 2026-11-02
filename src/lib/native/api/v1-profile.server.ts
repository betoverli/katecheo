/**
 * Native `/api/native/v1/me`, `/prefs`, `/notify-prefs`, `/account/*` handlers.
 * Mirrors `cloud.ts` prefs + `account.ts` delete/export + notify prefs.
 */
import { isAvatarId } from "@/lib/avatars";
import { appById } from "@/lib/bible/apps";
import type { Locale } from "@/lib/bible/books";
import type { CiteBook, CiteSep } from "@/lib/bible/passage";
import type { CopyFormat } from "@/lib/copy-rich";
import { getSql } from "@/lib/db";
import { pictureFromJwt } from "@/lib/oauth-photo";
import { progressFromMarks } from "@/lib/plan-marks";
import { planById } from "@/lib/bible/reading-plans";
import { cleanEmail, cleanHandle, cleanName } from "@/lib/profile";
import { allowRequest } from "@/lib/rate-limit";
import type { Theme } from "@/lib/theme";

export type NativePrefs = {
  locale: Locale;
  copyLocale: Locale;
  appId: string;
  translationId: string;
  preferNative: boolean;
  copyFormat: CopyFormat;
  citeBook: CiteBook;
  citeSep: CiteSep;
  booksCompact: boolean;
  theme: Theme;
  activePlans: string[];
  planProgress: Record<string, number[]>;
  avatarId: string;
  avatarUrl: string;
  handle: string;
  firstName: string;
  lastName: string;
  profileEmail: string;
};

export type NativeNotifyPrefs = {
  reading: boolean;
  friends: boolean;
  shares: boolean;
  groups: boolean;
};

export type NativeMe = {
  id: string;
  email: string | null;
  displayName: string;
  prefs: NativePrefs;
  notify: NativeNotifyPrefs & { apnsDevices: number };
};

type PrefsRow = {
  locale: string;
  copy_locale: string;
  app_id: string;
  translation_id: string;
  prefer_native: boolean;
  copy_format: string;
  cite_book: string;
  cite_sep: string;
  books_compact: boolean;
  theme: string;
  active_plans: string;
  plan_progress: string;
  avatar_id: string;
  avatar_url: string;
  handle: string;
  first_name: string;
  last_name: string;
  email: string;
  notify_reading: boolean | null;
  notify_friends: boolean | null;
  notify_shares: boolean | null;
  notify_groups: boolean | null;
};

function asLocale(value: string): Locale {
  return value === "en" || value === "es" || value === "pt" ? value : "pt";
}

function asFormat(value: string): CopyFormat {
  return value === "markdown" || value === "plain" || value === "rich" ? value : "rich";
}

function asCiteBook(value: string): CiteBook {
  return value === "abbr" ? "abbr" : "name";
}

function asCiteSep(value: string): CiteSep {
  return value === "dot" || value === "comma" ? value : "colon";
}

function asTheme(value: string): Theme {
  return value === "light" || value === "dark" || value === "system" ? value : "system";
}

function parseJson<T>(raw: string, fallback: T): T {
  try {
    return JSON.parse(raw) as T;
  } catch {
    return fallback;
  }
}

function cleanAvatarUrl(value: string) {
  const raw = value.trim().slice(0, 500);
  if (!raw) return "";
  try {
    const url = new URL(raw);
    if (url.protocol === "https:") return url.href;
  } catch {
    /* ignore */
  }
  return "";
}

function defaultPrefs(): NativePrefs {
  return {
    locale: "pt",
    copyLocale: "pt",
    appId: "youversion",
    translationId: "111",
    preferNative: true,
    copyFormat: "rich",
    citeBook: "name",
    citeSep: "colon",
    booksCompact: false,
    theme: "system",
    activePlans: [],
    planProgress: {},
    avatarId: "book",
    avatarUrl: "",
    handle: "",
    firstName: "",
    lastName: "",
    profileEmail: "",
  };
}

function fromRow(row: PrefsRow): NativePrefs {
  return {
    locale: asLocale(row.locale),
    copyLocale: asLocale(row.copy_locale || row.locale),
    appId: row.app_id,
    translationId: row.translation_id,
    preferNative: Boolean(row.prefer_native),
    copyFormat: asFormat(row.copy_format),
    citeBook: asCiteBook(row.cite_book),
    citeSep: asCiteSep(row.cite_sep),
    booksCompact: Boolean(row.books_compact),
    theme: asTheme(row.theme),
    activePlans: parseJson<string[]>(row.active_plans, []),
    planProgress: parseJson<Record<string, number[]>>(row.plan_progress, {}),
    avatarId: isAvatarId(row.avatar_id) ? row.avatar_id : "book",
    avatarUrl: row.avatar_url ?? "",
    handle: row.handle ?? "",
    firstName: row.first_name ?? "",
    lastName: row.last_name ?? "",
    profileEmail: row.email ?? "",
  };
}

function notifyFromRow(row: PrefsRow | undefined): NativeNotifyPrefs {
  return {
    reading: row?.notify_reading !== false,
    friends: row?.notify_friends !== false,
    shares: row?.notify_shares !== false,
    groups: row?.notify_groups !== false,
  };
}

async function loadPrefsRow(userId: string): Promise<PrefsRow | undefined> {
  const sql = await getSql();
  const rows = await sql<PrefsRow>`
    select locale, copy_locale, app_id, translation_id, prefer_native, copy_format, cite_book, cite_sep, books_compact, theme,
           active_plans, plan_progress, avatar_id, avatar_url, handle, first_name, last_name, email,
           notify_reading, notify_friends, notify_shares, notify_groups
    from user_prefs
    where user_id = ${userId}
  `;
  return rows[0];
}

export async function getPrefsForUser(userId: string): Promise<NativePrefs> {
  const row = await loadPrefsRow(userId);
  if (!row) return defaultPrefs();
  const sql = await getSql();
  return { ...fromRow(row), planProgress: await progressFromMarks(sql, userId) };
}

export async function getNotifyPrefsForUser(
  userId: string,
): Promise<NativeNotifyPrefs & { apnsDevices: number }> {
  const row = await loadPrefsRow(userId);
  const { countApnsDevices } = await import("@/lib/native/devices.server");
  const apnsDevices = await countApnsDevices(userId);
  return { ...notifyFromRow(row), apnsDevices };
}

async function syncPhotoIfNeeded(userId: string, prefs: NativePrefs): Promise<NativePrefs> {
  if (prefs.avatarUrl) return prefs;
  const sql = await getSql();
  const users = await sql<{ image: string | null; name: string | null }>`
    select image, name from "user" where id = ${userId}
  `;
  const image = users[0]?.image?.trim();
  if (image) {
    return { ...prefs, avatarUrl: image };
  }
  const accounts = await sql<{ idToken: string | null }>`
    select "idToken" from account where "userId" = ${userId}
  `;
  for (const account of accounts) {
    const picture = pictureFromJwt(account.idToken);
    if (!picture) continue;
    await sql`update "user" set image = ${picture} where id = ${userId}`;
    return { ...prefs, avatarUrl: picture };
  }
  return prefs;
}

function displayNameFrom(prefs: NativePrefs, accountName: string | null): string {
  const joined = [prefs.firstName, prefs.lastName].filter(Boolean).join(" ").trim();
  if (joined) return joined;
  if (prefs.handle) return `@${prefs.handle}`;
  return accountName?.trim() || prefs.profileEmail || "";
}

export async function getMeForUser(
  userId: string,
  email: string | null,
): Promise<NativeMe> {
  let prefs = await getPrefsForUser(userId);
  prefs = await syncPhotoIfNeeded(userId, prefs);
  const notify = await getNotifyPrefsForUser(userId);
  const sql = await getSql();
  const users = await sql<{ name: string | null; email: string | null }>`
    select name, email from "user" where id = ${userId}
  `;
  const accountEmail = email ?? users[0]?.email ?? null;
  if (!prefs.profileEmail && accountEmail) {
    prefs = { ...prefs, profileEmail: accountEmail };
  }
  if (!prefs.firstName && users[0]?.name) {
    const [given, ...rest] = users[0].name.split(" ");
    prefs = {
      ...prefs,
      firstName: given ?? "",
      lastName: prefs.lastName || rest.join(" "),
    };
  }
  return {
    id: userId,
    email: accountEmail,
    displayName: displayNameFrom(prefs, users[0]?.name ?? null),
    prefs,
    notify,
  };
}

function pickString(raw: Record<string, unknown>, key: string): string | undefined {
  const v = raw[key];
  return typeof v === "string" ? v : undefined;
}

function pickBool(raw: Record<string, unknown>, key: string): boolean | undefined {
  const v = raw[key];
  return typeof v === "boolean" ? v : undefined;
}

/** Full prefs upsert (same semantics as web `savePrefs`). */
export async function savePrefsForUser(
  userId: string,
  raw: unknown,
): Promise<{ ok: true; prefs: NativePrefs } | { ok: false; error: "invalid" | "handle" }> {
  if (!raw || typeof raw !== "object") return { ok: false, error: "invalid" };
  const data = raw as Record<string, unknown>;
  const current = await getPrefsForUser(userId);

  const merged: NativePrefs = {
    locale: asLocale(pickString(data, "locale") ?? current.locale),
    copyLocale: asLocale(pickString(data, "copyLocale") ?? current.copyLocale),
    appId: pickString(data, "appId") ?? current.appId,
    translationId: (pickString(data, "translationId") ?? current.translationId).slice(0, 40),
    preferNative: pickBool(data, "preferNative") ?? current.preferNative,
    copyFormat: asFormat(pickString(data, "copyFormat") ?? current.copyFormat),
    citeBook: asCiteBook(pickString(data, "citeBook") ?? current.citeBook),
    citeSep: asCiteSep(pickString(data, "citeSep") ?? current.citeSep),
    booksCompact: pickBool(data, "booksCompact") ?? current.booksCompact,
    theme: asTheme(pickString(data, "theme") ?? current.theme),
    activePlans: Array.isArray(data.activePlans)
      ? (data.activePlans as unknown[]).filter((x): x is string => typeof x === "string")
      : current.activePlans,
    planProgress: current.planProgress,
    avatarId: pickString(data, "avatarId") ?? current.avatarId,
    avatarUrl: pickString(data, "avatarUrl") ?? current.avatarUrl,
    handle: pickString(data, "handle") ?? current.handle,
    firstName: pickString(data, "firstName") ?? current.firstName,
    lastName: pickString(data, "lastName") ?? current.lastName,
    profileEmail: pickString(data, "profileEmail") ?? current.profileEmail,
  };

  const sql = await getSql();
  const handle = cleanHandle(merged.handle);
  if (handle) {
    const taken = await sql<{ user_id: string }>`
      select user_id from user_prefs where handle = ${handle} and user_id <> ${userId} limit 1
    `;
    if (taken[0]) return { ok: false, error: "handle" };
  }
  const existing = await sql<{ plan_progress: string }>`
    select plan_progress from user_prefs where user_id = ${userId}
  `;
  const progress = existing[0]?.plan_progress ?? "{}";
  const active = JSON.stringify(
    [...new Set(merged.activePlans)].filter((id) => planById(id)).slice(0, 20),
  );
  const avatarId = isAvatarId(merged.avatarId) ? merged.avatarId : "book";
  const locale = merged.locale;
  const copyLocale = merged.copyLocale || merged.locale;
  const appId = appById(merged.appId) ? merged.appId : "youversion";
  const copyFormat = merged.copyFormat;
  const citeBook = merged.citeBook;
  const citeSep = merged.citeSep;
  const theme = merged.theme;
  const avatarUrl = cleanAvatarUrl(merged.avatarUrl);
  const firstName = cleanName(merged.firstName);
  const lastName = cleanName(merged.lastName);
  const profileEmail = cleanEmail(merged.profileEmail) || merged.profileEmail.trim().slice(0, 120);

  try {
    await sql`
      insert into user_prefs (
        user_id, locale, copy_locale, app_id, translation_id, prefer_native, copy_format, cite_book, cite_sep, books_compact, theme,
        active_plans, plan_progress, avatar_id, avatar_url, handle, first_name, last_name, email, updated_at
      ) values (
        ${userId}, ${locale}, ${copyLocale}, ${appId}, ${merged.translationId}, ${Boolean(merged.preferNative)},
        ${copyFormat}, ${citeBook}, ${citeSep}, ${Boolean(merged.booksCompact)}, ${theme}, ${active}, ${progress},
        ${avatarId}, ${avatarUrl}, ${handle}, ${firstName}, ${lastName}, ${profileEmail}, now()
      )
      on conflict (user_id) do update set
        locale = excluded.locale,
        copy_locale = excluded.copy_locale,
        app_id = excluded.app_id,
        translation_id = excluded.translation_id,
        prefer_native = excluded.prefer_native,
        copy_format = excluded.copy_format,
        cite_book = excluded.cite_book,
        cite_sep = excluded.cite_sep,
        books_compact = excluded.books_compact,
        theme = excluded.theme,
        active_plans = excluded.active_plans,
        avatar_id = excluded.avatar_id,
        avatar_url = excluded.avatar_url,
        handle = excluded.handle,
        first_name = excluded.first_name,
        last_name = excluded.last_name,
        email = excluded.email,
        updated_at = now()
    `;
  } catch {
    return { ok: false, error: "handle" };
  }

  return { ok: true, prefs: await getPrefsForUser(userId) };
}

/** Profile-focused PATCH — name/handle/email/avatar (+ optional theme/locale shortcuts). */
export async function patchMeForUser(
  userId: string,
  raw: unknown,
): Promise<{ ok: true; me: NativeMe } | { ok: false; error: "invalid" | "handle" }> {
  if (!raw || typeof raw !== "object") return { ok: false, error: "invalid" };
  const data = raw as Record<string, unknown>;
  const current = await getPrefsForUser(userId);
  const patch: Record<string, unknown> = { ...current };
  for (const key of [
    "firstName",
    "lastName",
    "handle",
    "profileEmail",
    "avatarId",
    "avatarUrl",
    "theme",
    "locale",
    "copyLocale",
    "appId",
    "translationId",
    "preferNative",
    "copyFormat",
    "citeBook",
    "citeSep",
    "booksCompact",
  ] as const) {
    if (key in data) patch[key] = data[key];
  }
  const saved = await savePrefsForUser(userId, patch);
  if (!saved.ok) return saved;
  const sql = await getSql();
  const users = await sql<{ email: string | null }>`select email from "user" where id = ${userId}`;
  const me = await getMeForUser(userId, users[0]?.email ?? null);
  return { ok: true, me };
}

export async function saveNotifyPrefsForUser(
  userId: string,
  raw: unknown,
): Promise<{ ok: true; notify: NativeNotifyPrefs } | { ok: false; error: "invalid" }> {
  if (!raw || typeof raw !== "object") return { ok: false, error: "invalid" };
  const data = raw as Record<string, unknown>;
  // Ensure a prefs row exists so notify UPDATE is not a no-op.
  const existing = await loadPrefsRow(userId);
  if (!existing) {
    const seeded = await savePrefsForUser(userId, defaultPrefs());
    if (!seeded.ok) return { ok: false, error: "invalid" };
  }
  const { loadPrefs, savePrefs } = await import("@/lib/notify.server");
  const current = await loadPrefs(userId);
  const patch = {
    reading: typeof data.reading === "boolean" ? data.reading : current.reading,
    friends: typeof data.friends === "boolean" ? data.friends : current.friends,
    shares: typeof data.shares === "boolean" ? data.shares : current.shares,
    groups: typeof data.groups === "boolean" ? data.groups : current.groups,
  };
  const saved = await savePrefs(userId, patch);
  return { ok: true, notify: saved };
}

export async function exportAccountForUser(userId: string) {
  const sql = await getSql();
  const prefs = await sql<{
    handle: string;
    first_name: string;
    last_name: string;
    email: string;
    locale: string;
    copy_locale: string;
    avatar_id: string;
  }>`
    select handle, first_name, last_name, email, locale, copy_locale, avatar_id
    from user_prefs where user_id = ${userId} limit 1
  `;
  const notes = await sql<{
    id: string;
    title: string;
    happened_at: string;
    tags: string;
    blocks: string;
    visibility: string;
    updated_at: string;
    speaker_id: string | null;
  }>`
    select id, title, happened_at::text, tags, blocks, visibility, updated_at, speaker_id
    from notebook_notes where user_id = ${userId} order by happened_at desc
  `;
  const speakers = await sql<{ id: string; name: string; color: string; updated_at: string }>`
    select id, name, color, updated_at from notebook_speakers where user_id = ${userId}
  `;
  const collections = await sql<{
    id: string;
    title: string;
    passages: string;
    visibility: string;
    updated_at: string;
  }>`
    select id, title, passages, visibility, updated_at from user_collections where user_id = ${userId}
  `;
  const groups = await sql<{ id: string; name: string; visibility: string; created_by: string }>`
    select g.id, g.name, g.visibility, g.created_by
    from notebook_groups g
    join notebook_group_members m on m.group_id = g.id
    where m.user_id = ${userId}
  `;
  return {
    ok: true as const,
    exportedAt: new Date().toISOString(),
    profile: prefs[0] ?? {
      handle: "",
      first_name: "",
      last_name: "",
      email: "",
      locale: "pt",
      copy_locale: "",
      avatar_id: "book",
    },
    notes,
    speakers,
    collections,
    groups,
  };
}

export async function deleteAccountForUser(
  userId: string,
): Promise<{ ok: true } | { ok: false; error: "limit" }> {
  if (!allowRequest(`adel:${userId}`, 3, 86_400_000)) {
    return { ok: false, error: "limit" };
  }
  const sql = await getSql();
  const id = userId;
  await sql`delete from note_grants where user_id = ${id} or from_id = ${id}`;
  await sql`delete from notebook_group_notes where note_id in (select id from notebook_notes where user_id = ${id})`;
  await sql`delete from notebook_notes where user_id = ${id}`;
  await sql`delete from notebook_speakers where user_id = ${id}`;
  await sql`delete from notebook_group_members where user_id = ${id}`;
  await sql`
    delete from notebook_groups g
    where created_by = ${id}
      and not exists (
        select 1 from notebook_group_members m where m.group_id = g.id and m.status = 'accepted'
      )
  `;
  await sql`delete from collection_grants where user_id = ${id} or from_id = ${id}`;
  await sql`delete from user_collections where user_id = ${id}`;
  await sql`delete from user_links where requester_id = ${id} or addressee_id = ${id}`;
  await sql`delete from plan_group_members where user_id = ${id}`;
  await sql`delete from plan_marks where user_id = ${id}`;
  await sql`delete from notifications where user_id = ${id}`;
  await sql`delete from push_subscriptions where user_id = ${id}`;
  await sql`delete from apns_devices where user_id = ${id}`;
  await sql`delete from native_auth_handoff where user_id = ${id}`;
  await sql`delete from user_prefs where user_id = ${id}`;
  await sql`delete from verification where identifier in (select email from "user" where id = ${id})`;
  await sql`delete from session where "userId" = ${id}`;
  await sql`delete from account where "userId" = ${id}`;
  await sql`delete from "user" where id = ${id}`;
  return { ok: true };
}
