-- Shared rate-limit buckets (Neon / PGLite). One row per key + window start.
create table if not exists rate_limit_buckets (
  bucket_key text not null,
  window_start timestamptz not null,
  hit_count integer not null default 0,
  primary key (bucket_key, window_start)
);

create index if not exists rate_limit_buckets_window_idx
  on rate_limit_buckets (window_start);
