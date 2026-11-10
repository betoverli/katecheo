import { auth } from "./server";

/**
 * Start the OAuth redirect for a sign-in button.
 *
 * Better Auth 1.7 routes both built-in social providers (Google, Apple) and
 * `genericOAuth` broker ids (`grok-google`) through `signInSocial`. Legacy
 * broker callbacks stay on `/api/auth/oauth2/callback/<id>` via
 * `legacyGrokOAuthCallback`. X is not registered.
 */
export function beginOAuthSignIn(
  request: Request,
  body: { providerId: string; callbackURL: string; errorCallbackURL: string },
): Promise<Response> {
  return auth.api.signInSocial({
    body: {
      provider: body.providerId,
      callbackURL: body.callbackURL,
      errorCallbackURL: body.errorCallbackURL,
      // Keep a JSON `{ url }` body. The default sets a Location header, and the
      // popup / native-app callers read the URL themselves.
      disableRedirect: true,
    },
    headers: request.headers,
    asResponse: true,
  });
}
