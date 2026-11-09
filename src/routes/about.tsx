import { createFileRoute } from "@tanstack/react-router";
import { AppHeader } from "@/components/app-header";
import { Screen } from "@/components/screen";
import { AboutPage } from "@/components/about-page";
import { t } from "@/lib/i18n";
import { useAppStore } from "@/lib/store";

import { pageHead } from "@/lib/seo";

export const Route = createFileRoute("/about")({
  component: AboutRoute,
  head: () =>
    pageHead({
      title: "Katecheo — Sobre e ajuda",
      description:
        "Como surgiu o Katecheo, como gerar links, coleções, planos de leitura, conta opcional e como ajudar o projeto.",
      path: "/about",
    }),
});

function AboutRoute() {
  const locale = useAppStore((s) => s.locale);

  return (
    <Screen className="mx-auto flex min-h-dvh w-full max-w-3xl flex-col gap-8 px-4 pt-0 pb-[calc(env(safe-area-inset-bottom)+2rem)] sm:px-6">
      <AppHeader title={t(locale, "aboutTitle")} backTo="/" />
      <AboutPage />
    </Screen>
  );
}
