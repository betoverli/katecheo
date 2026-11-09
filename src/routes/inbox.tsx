import { createFileRoute, Navigate } from "@tanstack/react-router";
import { pageHead } from "@/lib/seo";

export const Route = createFileRoute("/inbox")({
  component: () => <Navigate to="/app" />,
  head: () => {
    const seo = pageHead({
      title: "Katecheo — Avisos",
      description: "Avisos de planos, amigos e coleções.",
      path: "/inbox",
    });
    return { ...seo, meta: [...seo.meta, { name: "robots", content: "noindex" }] };
  },
});
