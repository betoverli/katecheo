-- Friend invites to notebook groups (invitee accepts/declines; accepting joins as member).
create table if not exists notebook_group_invites (
  id text primary key,
  group_id text not null,
  inviter_id text not null,
  invitee_id text not null,
  status text not null default 'pending',
  created_at timestamptz not null default now(),
  responded_at timestamptz
);

create index if not exists notebook_group_invites_invitee_idx
  on notebook_group_invites (invitee_id, status, created_at desc);

create index if not exists notebook_group_invites_group_idx
  on notebook_group_invites (group_id, status);

-- At most one pending invite per (group, invitee).
create unique index if not exists notebook_group_invites_pending_uniq
  on notebook_group_invites (group_id, invitee_id)
  where status = 'pending';
