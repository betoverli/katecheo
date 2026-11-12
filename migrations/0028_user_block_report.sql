-- App Store Guideline 1.2: user block + content report for UGC (friends / groups).

create table if not exists user_block (
  blocker_id text not null,
  blocked_id text not null,
  created_at timestamptz not null default now(),
  primary key (blocker_id, blocked_id),
  constraint user_block_not_self check (blocker_id <> blocked_id)
);

create index if not exists user_block_blocked_idx on user_block (blocked_id);

create table if not exists content_report (
  id text primary key,
  reporter_id text not null,
  target_type text not null,
  target_id text not null,
  reason text not null,
  details text not null default '',
  status text not null default 'open',
  created_at timestamptz not null default now(),
  constraint content_report_target_type_chk check (target_type in ('user', 'note', 'group')),
  constraint content_report_status_chk check (status in ('open', 'reviewed', 'closed'))
);

create index if not exists content_report_reporter_idx on content_report (reporter_id, created_at desc);
create index if not exists content_report_target_idx on content_report (target_type, target_id);
create index if not exists content_report_status_idx on content_report (status, created_at desc);
