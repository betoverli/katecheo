import type { BetterAuthPlugin } from "better-auth";
import { GROK_PROVIDERS } from "./providers";

/**
 * Better Auth 1.7 registers `genericOAuth` providers as social providers on
 * `/callback/:id`. The Grok broker (preview + deployed `GROK_AUTH_*` clients)
 * still allowlists `/api/auth/oauth2/callback/*`, so keep that path for the
 * legacy `grok-*` ids: advertise it as `callbackPath` and rewrite inbound
 * requests onto the new social callback endpoint.
 */
export function legacyGrokOAuthCallback(): BetterAuthPlugin {
  const ids = new Set(GROK_PROVIDERS.map((provider) => provider.providerId));
  return {
    id: "legacy-grok-oauth-callback",
    init(ctx) {
      const providers = ctx.socialProviders;
      if (!Array.isArray(providers) || providers.length === 0) return;
      return {
        context: {
          socialProviders: providers.map((provider) =>
            ids.has(provider.id)
              ? { ...provider, callbackPath: `/oauth2/callback/${provider.id}` }
              : provider,
          ),
        },
      };
    },
    async onRequest(request) {
      const url = new URL(request.url);
      const match = url.pathname.match(/^(.*\/api\/auth)\/oauth2\/callback\/([^/]+)\/?$/);
      if (!match) return;
      const providerId = match[2] ?? "";
      if (!ids.has(providerId)) return;
      url.pathname = `${match[1]}/callback/${providerId}`;
      return { request: new Request(url, request) };
    },
  };
}
