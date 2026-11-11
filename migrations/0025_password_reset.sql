-- One-time 6-digit password reset codes for native email/password accounts.
-- Only the hash is stored; plaintext codes live in the Resend email briefly.
create table if not exists password_reset_codes (
  id text primary key,
  user_id text not null references "user" ("id") on delete cascade,
  email_normalized text not null,
  code_hash text not null,
  attempts integer not null default 0,
  expires_at timestamptz not null,
  used_at timestamptz,
  created_at timestamptz not null default now()
);

create index if not exists password_reset_codes_user_idx
  on password_reset_codes (user_id, created_at desc);

create index if not exists password_reset_codes_email_idx
  on password_reset_codes (email_normalized, created_at desc);

create index if not exists password_reset_codes_expires_idx
  on password_reset_codes (expires_at);
