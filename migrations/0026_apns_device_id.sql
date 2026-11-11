-- Stable APNs device identity: one row per (user_id, device_id).
-- Pre-launch cleanup keeps only the newest token per user so reinstall
-- duplicates stop inflating Alerts > Device ("Registered (N)").

alter table apns_devices add column if not exists device_id text;

-- Keep the most recently updated row per user; tie-break on token text.
delete from apns_devices a
where exists (
  select 1 from apns_devices b
  where b.user_id = a.user_id
    and (
      b.updated_at > a.updated_at
      or (b.updated_at = a.updated_at and b.token > a.token)
    )
);

update apns_devices
set device_id = 'legacy:' || lower(token)
where device_id is null or btrim(device_id) = '';

alter table apns_devices alter column device_id set not null;

-- Primary key moves from token → (user, device); token stays globally unique.
alter table apns_devices drop constraint if exists apns_devices_pkey;
alter table apns_devices add constraint apns_devices_user_device_pkey primary key (user_id, device_id);
create unique index if not exists apns_devices_token_uidx on apns_devices (token);
