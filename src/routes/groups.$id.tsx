import { createFileRoute } from "@tanstack/react-router";
import { pageHead } from "@/lib/seo";
import { redirectWebAppToLanding } from "@/lib/web-app-gone";

/**
 * Former web group route — browsers 308 to the marketing landing.
 * Share crawlers (WhatsApp / iMessage / etc.) still need correct OG tags on this URL;
 * `head` runs for the matched route before the redirect response.
 */
export const Route = createFileRoute("/groups/$id")({
  head: ({ params }) =>
    pageHead({
      title: "Katecheo",
      description:
        "Katecheo — Seu estudo bíblico, organizado. Em breve no iPhone. Notas com referências que abrem no seu app de Bíblia, temas, planos, grupos e amigos.",
      path: `/groups/${params.id}`,
    }),
  beforeLoad: () => {
    redirectWebAppToLanding();
  },
});
