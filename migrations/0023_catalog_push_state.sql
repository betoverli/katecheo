-- Last-broadcast content versions for silent Themes / Reading catalog APNs.
-- Used by /api/internal/catalog-push so each content change broadcasts at most once.
create table if not exists catalog_push_state (
  kind text primary key,
  version text not null,
  updated_at timestamptz not null default now(),
  constraint catalog_push_state_kind_check
    check (kind in ('themes_updated', 'reading_updated'))
);
