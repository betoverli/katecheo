import { Outlet, createFileRoute } from "@tanstack/react-router";
import { pageHead } from "@/lib/seo";

export const Route = createFileRoute("/profile")({
  component: ProfileLayout,
  head: () => {
    const seo = pageHead({
      title: "Katecheo — Perfil",
      description: "Conta Katecheo: avatar, @ e nome.",
      path: "/profile",
    });
    return { ...seo, meta: [...seo.meta, { name: "robots", content: "noindex" }] };
  },
});

function ProfileLayout() {
  return <Outlet />;
}
