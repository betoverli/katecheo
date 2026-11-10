# Catalog silent push (Themes / Reading)

When **COLLECTIONS** (Themes) or **READING_PLANS** change in production, every
registered iOS device should receive the existing silent APNs hint
(`themes_updated` / `reading_updated`) **exactly once per content change**.
iOS already handles these in `AppDelegate`, `NativePushService`, and
`NativeCatalogSync` — this doc covers the backend + deploy hook only.

## How it works

1. **Versions** — `GET /api/native/v1/catalog/versions` returns
   `{ ok, bibleBooks, themes, reading }`. `themes` / `reading` are
   `themes-<sha256>` / `reading-<sha256>` of the full stable-serialized
   `COLLECTIONS` / `READING_PLANS` payloads (not just ids/counts).
2. **Idempotent endpoint** — `POST /api/internal/catalog-push` (auth required):
   - Computes current versions.
   - Compares to Neon table `catalog_push_state` (one row per kind).
   - **First run** (no row): stores the version and **does not** broadcast
     (avoids spamming on rollout), unless `"force": true`.
   - **Version changed**: claims the new version (row lock / transaction) and
     broadcasts; concurrent callers lose the claim and skip.
   - **Unchanged**: skips (unless `force`).
   - Response lists each kind’s `action`: `broadcast` |
     `skipped_baseline` | `skipped_unchanged`.
3. **GitHub Action** — `.github/workflows/catalog-push.yml`:
   - **Cron every 15 minutes** (primary; safe because the endpoint is idempotent).
   - **`workflow_dispatch`** with optional `force`.
   - **`deployment_status`** best-effort on any `success` (no environment-name
     filter — Vercel often does not emit this event to the repo).
   - Concurrency group `catalog-push` (no overlapping runs); job timeout 5 min;
     curl-only (no checkout).

## Secrets

| Where | Name | Notes |
| --- | --- | --- |
| Vercel (Production) | `CATALOG_PUSH_SECRET` | ≥16 chars; used by the API |
| GitHub Actions | `CATALOG_PUSH_SECRET` | **Must equal** the Vercel value |

If the GitHub secret is empty, the workflow **warns and skips** (does not fail).

Auth header: `x-catalog-push-secret: <secret>` (or `Authorization: Bearer <secret>`).

## Force a broadcast

From GitHub → Actions → **Catalog push** → Run workflow → enable **force**.

Or manually:

```bash
curl -sS -X POST 'https://katecheo.app/api/internal/catalog-push' \
  -H 'content-type: application/json' \
  -H "x-catalog-push-secret: $CATALOG_PUSH_SECRET" \
  -d '{"force":true}'
```

Optional single kind: `"kind":"themes_updated"` or `"reading_updated"`.

## Database

Migration `migrations/0023_catalog_push_state.sql` creates `catalog_push_state`.
It is applied **automatically on deploy** via `npm run build` → `npm run db:migrate`
(`scripts/migrate.mjs` against `DATABASE_URL`). No manual SQL step in production.
