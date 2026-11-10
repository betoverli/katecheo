import { createServerFn } from "@tanstack/react-start";
import { authMiddleware } from "@/lib/auth/middleware";
import { getSql } from "@/lib/db";
import { allowRequest } from "@/lib/rate-limit";
import {
  asNote,
  asSpeaker,
  cleanBlocks,
  cleanTags,
  noteSpeakerIds,
  type Note,
  type Speaker,
} from "@/lib/notebook";

type NoteRow = {
  id: string;
  title: string;
  happened_at: string;
  tags: string;
  blocks: string;
  visibility: string;
  updated_at: string;
  speaker_id?: string | null;
};

type SpeakerRow = {
  id: string;
  name: string;
  color: string;
  updated_at: string;
};

function parseJson<T>(raw: string, fallback: T): T {
  try {
    return JSON.parse(raw) as T;
  } catch {
    return fallback;
  }
}

function fromNoteRow(row: NoteRow): Note {
  const happened =
    typeof row.happened_at === "string" ? row.happened_at.slice(0, 10) : row.happened_at;
  return {
    id: row.id,
    title: row.title ?? "",
    happenedAt: happened,
    tags: cleanTags(parseJson(row.tags, [])),
    speakerId: row.speaker_id || null,
    blocks: cleanBlocks(parseJson(typeof row.blocks === "string" ? row.blocks : JSON.stringify(row.blocks ?? []), [])),
    visibility: row.visibility === "unlisted" ? "unlisted" : "private",
    updatedAt: String(row.updated_at ?? ""),
  };
}

function fromSpeakerRow(row: SpeakerRow): Speaker {
  return {
    id: row.id,
    name: row.name,
    color: row.color,
    updatedAt: String(row.updated_at ?? ""),
  };
}

export const listMyNotes = createServerFn({ method: "GET" })
  .middleware([authMiddleware])
  .handler(async ({ context }) => {
    const sql = await getSql();
    const rows = await sql<NoteRow>`
      select id, title, happened_at::text, tags, blocks, visibility, updated_at, speaker_id
      from notebook_notes
      where user_id = ${context.userId}
      order by happened_at desc, updated_at desc
      limit 200
    `;
    return rows.map(fromNoteRow);
  });

export const listMySpeakers = createServerFn({ method: "GET" })
  .middleware([authMiddleware])
  .handler(async ({ context }) => {
    const sql = await getSql();
    const rows = await sql<SpeakerRow>`
      select id, name, color, updated_at from notebook_speakers
      where user_id = ${context.userId}
      order by name
    `;
    return rows.map(fromSpeakerRow);
  });

export const upsertMyNote = createServerFn({ method: "POST" })
  .middleware([authMiddleware])
  .validator((data: Note) => data)
  .handler(async ({ context, data }) => {
    const note = asNote(data);
    if (!note) return { ok: false as const, error: "invalid" as const };
    const sql = await getSql();
    const count = await sql<{ n: string }>`
      select count(*)::text as n from notebook_notes where user_id = ${context.userId}
    `;
    const existing = await sql<{ id: string }>`
      select id from notebook_notes where id = ${note.id} and user_id = ${context.userId}
    `;
    if (!existing[0] && Number(count[0]?.n ?? 0) >= 200) return { ok: false as const, error: "limit" as const };
    await sql`
      insert into notebook_notes (id, user_id, title, happened_at, tags, blocks, visibility, updated_at, speaker_id)
      values (
        ${note.id}, ${context.userId}, ${note.title}, ${note.happenedAt}::date,
        ${JSON.stringify(note.tags)}, ${JSON.stringify(note.blocks)}, ${note.visibility}, ${note.updatedAt}::timestamptz,
        ${note.speakerId}
      )
      on conflict (id) do update set
        title = excluded.title,
        happened_at = excluded.happened_at,
        tags = excluded.tags,
        blocks = excluded.blocks,
        visibility = excluded.visibility,
        updated_at = excluded.updated_at,
        speaker_id = excluded.speaker_id
      where notebook_notes.user_id = ${context.userId}
        and notebook_notes.updated_at <= excluded.updated_at
    `;
    return { ok: true as const };
  });

export const deleteMyNote = createServerFn({ method: "POST" })
  .middleware([authMiddleware])
  .validator((data: { id: string }) => data)
  .handler(async ({ context, data }) => {
    const sql = await getSql();
    const owned = await sql<{ id: string }>`
      select id from notebook_notes where id = ${data.id} and user_id = ${context.userId} limit 1
    `;
    if (!owned[0]) return { ok: false as const };
    await sql`delete from notebook_group_notes where note_id = ${data.id}`;
    await sql`delete from note_grants where note_id = ${data.id}`;
    await sql`delete from notebook_notes where id = ${data.id} and user_id = ${context.userId}`;
    return { ok: true as const };
  });

export const upsertMySpeaker = createServerFn({ method: "POST" })
  .middleware([authMiddleware])
  .validator((data: Speaker) => data)
  .handler(async ({ context, data }) => {
    const speaker = asSpeaker(data);
    if (!speaker) return { ok: false as const, error: "invalid" as const };
    const sql = await getSql();
    await sql`
      insert into notebook_speakers (id, user_id, name, color, updated_at)
      values (${speaker.id}, ${context.userId}, ${speaker.name}, ${speaker.color}, ${speaker.updatedAt}::timestamptz)
      on conflict (id) do update set
        name = excluded.name,
        color = excluded.color,
        updated_at = excluded.updated_at
      where notebook_speakers.user_id = ${context.userId}
        and notebook_speakers.updated_at <= excluded.updated_at
    `;
    return { ok: true as const };
  });

export const deleteMySpeaker = createServerFn({ method: "POST" })
  .middleware([authMiddleware])
  .validator((data: { id: string }) => data)
  .handler(async ({ context, data }) => {
    const sql = await getSql();
    await sql`delete from notebook_speakers where id = ${data.id} and user_id = ${context.userId}`;
    return { ok: true as const };
  });

export const getSharedNote = createServerFn({ method: "GET" })
  .validator((data: { id: string }) => data)
  .handler(async ({ data }) => {
    const sql = await getSql();
    const rows = await sql<NoteRow & { user_id: string }>`
      select id, user_id, title, happened_at::text, tags, blocks, visibility, updated_at, speaker_id
      from notebook_notes
      where id = ${data.id}
      limit 1
    `;
    const row = rows[0];
    if (!row) return null;
    if (row.visibility !== "unlisted") return null;
    const note = fromNoteRow(row);
    const used = new Set(noteSpeakerIds(note));
    const speakers = used.size
      ? await sql<SpeakerRow>`
          select id, name, color, updated_at from notebook_speakers where user_id = ${row.user_id}
        `
      : [];
    return { note, speakers: speakers.filter((item) => used.has(item.id)).map(fromSpeakerRow) };
  });

export const getGrantedNote = createServerFn({ method: "GET" })
  .middleware([authMiddleware])
  .validator((data: { id: string }) => data)
  .handler(async ({ context, data }) => {
    const sql = await getSql();
    const rows = await sql<NoteRow>`
      select n.id, n.title, n.happened_at::text, n.tags, n.blocks, n.visibility, n.updated_at, n.speaker_id
      from notebook_notes n
      join note_grants g on g.note_id = n.id
      where n.id = ${data.id} and g.user_id = ${context.userId}
      limit 1
    `;
    let row = rows[0];
    if (!row) {
      const viaGroup = await sql<NoteRow>`
        select n.id, n.title, n.happened_at::text, n.tags, n.blocks, n.visibility, n.updated_at, n.speaker_id
        from notebook_notes n
        join notebook_group_notes p on p.note_id = n.id
        join notebook_group_members m on m.group_id = p.group_id
        where n.id = ${data.id} and m.user_id = ${context.userId} and m.status = 'accepted'
        limit 1
      `;
      row = viaGroup[0];
    }
    if (!row) return null;
    const note = fromNoteRow(row);
    const owner = await sql<{ user_id: string }>`select user_id from notebook_notes where id = ${data.id}`;
    const used = new Set(noteSpeakerIds(note));
    const speakers = owner[0] && used.size
      ? await sql<SpeakerRow>`select id, name, color, updated_at from notebook_speakers where user_id = ${owner[0].user_id}`
      : [];
    return { note, speakers: speakers.filter((item) => used.has(item.id)).map(fromSpeakerRow) };
  });

export const listGrantedNotes = createServerFn({ method: "GET" })
  .middleware([authMiddleware])
  .handler(async ({ context }) => {
    const sql = await getSql();
    const rows = await sql<NoteRow>`
      select n.id, n.title, n.happened_at::text, n.tags, n.blocks, n.visibility, n.updated_at, n.speaker_id
      from notebook_notes n
      join note_grants g on g.note_id = n.id
      where g.user_id = ${context.userId}
      order by n.happened_at desc
      limit 80
    `;
    return rows.map(fromNoteRow);
  });

export const sendNoteToFriend = createServerFn({ method: "POST" })
  .middleware([authMiddleware])
  .validator((data: { handle: string; noteId: string }) => data)
  .handler(async ({ context, data }) => {
    if (!(await allowRequest(`send:${context.userId}`, 40, 86_400_000))) {
      return { ok: false as const, error: "limit" as const };
    }
    const handle = data.handle.trim().replace(/^@+/, "").toLowerCase().replace(/[^a-z0-9_]/g, "").slice(0, 20);
    const sql = await getSql();
    const other = await sql<{ user_id: string }>`
      select user_id from user_prefs where handle = ${handle} limit 1
    `;
    if (!other[0]) return { ok: false as const, error: "missing" as const };
    const friends = await sql<{ n: string }>`
      select count(*)::text as n from user_links
      where status = 'accepted'
        and ((requester_id = ${context.userId} and addressee_id = ${other[0].user_id})
          or (requester_id = ${other[0].user_id} and addressee_id = ${context.userId}))
    `;
    if (Number(friends[0]?.n ?? 0) < 1) return { ok: false as const, error: "missing" as const };
    const owned = await sql<{ id: string; title: string }>`
      select id, title from notebook_notes where id = ${data.noteId} and user_id = ${context.userId}
    `;
    const note = owned[0];
    if (!note) return { ok: false as const, error: "missing" as const };
    await sql`update notebook_notes set visibility = 'unlisted' where id = ${note.id} and user_id = ${context.userId}`;
    await sql`
      insert into note_grants (note_id, user_id, from_id)
      values (${note.id}, ${other[0].user_id}, ${context.userId})
      on conflict (note_id, user_id) do nothing
    `;
    void import("@/lib/notify.server").then((mod) =>
      mod.notifySocial(context.userId, other[0]!.user_id, "shares", "notifyNoteSendTitle", "notifyNoteSendBody", {
        plan: note.title || "Caderno",
        href: `/n/${note.id}`,
      }),
    );
    return { ok: true as const, error: null };
  });
