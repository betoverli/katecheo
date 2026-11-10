import { UNIVERSAL_RETURN_PATH } from "./return-to.ts";

const BUNDLE_ID = "com.verse2note.app";

/** Team ID from the server env. Empty until the Apple Developer account exists. */
export function configuredTeamId(): string | null {
  const id = process.env.APPLE_TEAM_ID?.trim() ?? "";
  return /^[A-Z0-9]{10}$/.test(id) ? id : null;
}

/**
 * apple-app-site-association. With no Team ID the file is valid and claims
 * no app, so the custom-scheme return keeps working. After APPLE_TEAM_ID is
 * set, only that team's app receives listed paths on katecheo.app.
 *
 * `webcredentials` is required for ASWebAuthenticationSession's HTTPS callback
 * (iOS 17.4+). `applinks` alone lets the return URL open the app, but the
 * system refuses to present the login sheet until this app is also listed
 * under webcredentials.
 *
 * Paths match NativeDeepLinkRouter destinations used as Universal Links.
 */
export function appleAppSiteAssociation(teamId: string | null): {
  applinks: { details: Array<{ appIDs: string[]; components: Array<Record<string, unknown>> }> };
  webcredentials?: { apps: string[] };
} {
  if (!teamId) return { applinks: { details: [] } };
  const appId = `${teamId}.${BUNDLE_ID}`;
  return {
    applinks: {
      details: [
        {
          appIDs: [appId],
          components: [
            {
              "/": UNIVERSAL_RETURN_PATH,
              comment: "Native login return. Bound to this app by the Team ID.",
            },
            { "/": "/notebook", comment: "Caderno home" },
            { "/": "/notebook/*", comment: "Note detail" },
            { "/": "/n/*", comment: "Short note links" },
            { "/": "/groups", comment: "Groups home" },
            { "/": "/groups/*", comment: "Group detail" },
            { "/": "/g/*", comment: "Reading invite" },
            { "/": "/app", comment: "Tools / verses" },
            { "/": "/collections", comment: "Themes" },
            { "/": "/collections/*", comment: "Theme / list detail" },
            { "/": "/c/*", comment: "Short collection links" },
            { "/": "/reading", comment: "Reading home" },
            { "/": "/reading/*", comment: "Reading plan" },
            { "/": "/profile", comment: "Profile" },
            { "/": "/u/*", comment: "User profile" },
            { "/": "/inbox", comment: "Inbox / notifications" },
            { "/": "/login", comment: "Sign in" },
            { "/": "/auth/*", comment: "Auth deep links" },
          ],
        },
      ],
    },
    webcredentials: { apps: [appId] },
  };
}
