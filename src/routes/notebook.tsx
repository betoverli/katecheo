import { createFileRoute } from "@tanstack/react-router";
import { redirectWebAppToLanding } from "@/lib/web-app-gone";

/** Former web-product route — permanent redirect to the marketing landing. */
export const Route = createFileRoute("/notebook")({
  beforeLoad: () => {
    redirectWebAppToLanding();
  },
});
