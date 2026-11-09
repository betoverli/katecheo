import { createFileRoute } from "@tanstack/react-router";

export const Route = createFileRoute("/auth/native-config")({
  server: {
    handlers: {
      // The script already on the TestFlight build reads this before opening
      // the sheet. `true` makes it ask for an HTTPS callback, and that build
      // treats the resulting iOS cancel as the user giving up. `false` makes
      // the same script ask for Katecheo://, which the binary already opens.
      // The association file still publishes applinks and webcredentials.
      GET: async () =>
        new Response(JSON.stringify({ universalLinks: false }), {
          status: 200,
          headers: {
            "content-type": "application/json",
            "cache-control": "no-store",
          },
        }),
    },
  },
});
