import { createServerFn } from "@tanstack/react-start";
import { authMiddleware } from "@/lib/auth/middleware";
import { getSql, withTransaction } from "@/lib/db";
import { allowRequest } from "@/lib/rate-limit";

export const exportMyData = createServerFn({ method: "GET" })
  .middleware([authMiddleware])
  .handler(async ({ context }) => {
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
      from user_prefs where user_id = ${context.userId} limit 1
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
      from notebook_notes where user_id = ${context.userId} order by happened_at desc
    `;
    const speakers = await sql<{ id: string; name: string; color: string; updated_at: string }>`
      select id, name, color, updated_at from notebook_speakers where user_id = ${context.userId}
    `;
    const collections = await sql<{
      id: string;
      title: string;
      passages: string;
      visibility: string;
      updated_at: string;
    }>`
      select id, title, passages, visibility, updated_at from user_collections where user_id = ${context.userId}
    `;
    const groups = await sql<{ id: string; name: string; visibility: string; created_by: string }>`
      select g.id, g.name, g.visibility, g.created_by
      from notebook_groups g
      join notebook_group_members m on m.group_id = g.id
      where m.user_id = ${context.userId}
    `;
    return {
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
  });

export const deleteMyAccount = createServerFn({ method: "POST" })
  .middleware([authMiddleware])
  .handler(async ({ context }) => {
    if (!(await allowRequest(`adel:${context.userId}`, 3, 86_400_000))) {
      return { ok: false as const, error: "limit" as const };
    }
    const id = context.userId;
    await withTransaction(async (sql) => {
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
    });
    return { ok: true as const };
  });
