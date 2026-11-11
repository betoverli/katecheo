-- Contas conectadas: unique (providerId, accountId) so an Apple/Google/credential
-- identity cannot be attached to two Katecheo users at once. Linking endpoints
-- still return identity_in_use (409) before insert when a conflict is found.

create unique index if not exists account_provider_account_uidx
  on account ("providerId", "accountId");
