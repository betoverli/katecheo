import { createFileRoute } from "@tanstack/react-router";
import { AdminPage } from "@/components/admin-page";
import { AppHeader } from "@/components/app-header";
import { Screen } from "@/components/screen";
import { t } from "@/lib/i18n";
import { pageHead } from "@/lib/seo";
import { useAppStore } from "@/lib/store";

export const Route = createFileRoute("/admin")({
  component: AdminRoute,
  head: () => {
    const seo = pageHead({
      title: "Katecheo — Uso",
      description: "Painel de uso do Katecheo.",
      path: "/admin",
    });
    return { ...seo, meta: [...seo.meta, { name: "robots", content: "noindex" }] };
  },
});

function AdminRoute() {
  const locale = useAppStore((s) => s.locale);
  return (
    <Screen className="mx-auto flex min-h-dvh w-full max-w-3xl flex-col gap-6 px-4 pt-0 pb-[calc(env(safe-area-inset-bottom)+2rem)] sm:px-6">
      <AppHeader title={t(locale, "adminTitle")} backTo="/profile" />
      <AdminPage />
    </Screen>
  );
}
