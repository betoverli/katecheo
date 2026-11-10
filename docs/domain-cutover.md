# Domain cutover: verse2note.com → katecheo.app

Katecheo’s canonical public host is **`https://katecheo.app`**.  
`www.katecheo.app` already 308s to the apex at the Vercel domain layer.

`verse2note.com` and `www.verse2note.com` stay attached to the same Vercel
project (`verse2note`) so old iOS builds keep working. App middleware issues a
**308** from those legacy hosts to `https://katecheo.app` + the same path and
query, with the exclusions below.

Implementation: `src/lib/domain-cutover.ts` + `server/middleware/domain-cutover.ts`.

## Redirect vs serve-on-legacy

| Host | Behavior |
| --- | --- |
| `katecheo.app` | Serve (canonical) |
| `www.katecheo.app` | 308 → `katecheo.app` (Vercel) |
| `verse2note.com` / `www.verse2note.com` | 308 → `https://katecheo.app{path}{query}` **except** exclusions |

### Exclusions (still served on verse2note.com)

Keep these until old App Store / TestFlight builds are gone:

| Prefix | Why |
| --- | --- |
| `/api/native/*` | Old builds call the native API on verse2note.com |
| `/.well-known/*` | `apple-app-site-association` (and related) for Universal Links / webcredentials on the legacy domain |
| `/api/auth/*` | Better Auth — Google/Apple social callbacks, sessions, email; includes legacy broker `/api/auth/oauth2/callback/*` (PR #78) |
| `/auth/*` | Native OAuth start/done/return/config and `/auth/popup` — old builds open these on verse2note.com |

Everything else on the legacy host (marketing pages, `/login`, `/app`,
`/api/link`, etc.) permanently redirects to katecheo.app.

Better Auth **`allowedHosts` / `trustedOrigins`** still list both brands
(`src/lib/auth/server.ts` via `trustedWebOrigins()` in `src/lib/site.ts`).

iOS `AppSite.swift` uses **katecheo.app** as primary and **verse2note.com**
only as a DNS/TLS fallback.

## OAuth redirect URIs — keep both domains for now

### Google Cloud Console (OAuth client → Web application)

**Authorized redirect URIs** that must stay registered until cutover ends:

- `https://katecheo.app/api/auth/callback/google`
- `https://www.katecheo.app/api/auth/callback/google` (optional if www always 308s before OAuth; safe to keep)
- `https://verse2note.com/api/auth/callback/google`
- `https://www.verse2note.com/api/auth/callback/google`

**Authorized JavaScript origins** (if the console requires them):

- `https://katecheo.app`
- `https://www.katecheo.app`
- `https://verse2note.com`
- `https://www.verse2note.com`

Dev / preview (unchanged by cutover):

- `http://localhost:8080/api/auth/callback/google`
- `http://127.0.0.1:8080/api/auth/callback/google`
- preview / `*.grok-sandbox.com` URIs as already documented in README

### Apple Developer (Sign in with Apple → Services ID)

Return URLs / domains that must stay until cutover ends:

- Domains: `katecheo.app`, `verse2note.com` (and `www` variants if registered)
- Return URLs:
  - `https://katecheo.app/api/auth/callback/apple`
  - `https://verse2note.com/api/auth/callback/apple`
  - `www` variants if you registered them

Associated Domains on the iOS app already declare both hosts (`applinks` +
`webcredentials`). AASA is served from both origins under `/.well-known/`
(excluded from the 308).

Bundle id stays `com.verse2note.app`.

## Manual checklist (not done by this PR)

1. Confirm Vercel project domains: `katecheo.app` (primary), `www.katecheo.app`
   (redirect to apex), `verse2note.com`, `www.verse2note.com` (same project,
   **no** full-domain redirect that would bypass `/api/native` exclusions).
2. Confirm Google redirect URIs list both brands (above).
3. Confirm Apple Services ID domains + return URLs list both brands.
4. After deploy: `curl -sI https://verse2note.com/` → `308` +
   `Location: https://katecheo.app/`;  
   `curl -sI https://verse2note.com/api/native/v1/…` → **not** 308;  
   `curl -sI https://verse2note.com/.well-known/apple-app-site-association` → **not** 308;  
   `curl -sI https://verse2note.com/api/auth/callback/google` → **not** 308.

## What to remove later (old builds retired)

When analytics / App Store show no meaningful traffic on verse2note.com native
paths:

1. Drop legacy exclusions and optionally 308 **all** verse2note.com traffic
   (or detach the domain).
2. Remove `verse2note.com` / `www.verse2note.com` from Better Auth
   `allowedHosts` / `trustedOrigins` and from `trustedWebOrigins()`.
3. Remove Google redirect URIs and JS origins for verse2note.com (both apex and www).
4. Remove Apple Services ID domains / return URLs for verse2note.com.
5. Remove iOS Associated Domains `applinks:verse2note.com` /
   `webcredentials:verse2note.com` and `AppSite` fallback (ship a new binary).
6. Update privacy / marketing copy that still mentions the legacy host.
