-- Sign in with Apple: persist Apple subject + optional refresh token for revoke-on-delete.
-- Native iOS posts the identity token to /api/native/v1/auth/apple; the server verifies
-- JWKS and finds/links/creates the user by apple_sub (or verified email).

alter table "user" add column if not exists apple_sub text;
alter table "user" add column if not exists apple_refresh_token text;

create unique index if not exists user_apple_sub_uidx
  on "user" (apple_sub)
  where apple_sub is not null and apple_sub <> '';
