import { createFileRoute } from "@tanstack/react-router";
import { AppHeader } from "@/components/app-header";
import { Screen } from "@/components/screen";
import { ForAiPage } from "@/components/for-ai-page";
import { t } from "@/lib/i18n";
import { useAppStore } from "@/lib/store";

import { pageHead } from "@/lib/seo";

export const Route = createFileRoute("/for-ai")({
  component: ForAiRoute,
  head: () =>
    pageHead({
      title: "Katecheo — API, skill e MCP",
      description:
        "API pública (sem login), skill e MCP do Katecheo: gere deep links de referências, coleções por tema e o dia de um plano de leitura para Grok, Claude, Cursor ou qualquer agente.",
      path: "/for-ai",
    }),
});

function ForAiRoute() {
  const locale = useAppStore((s) => s.locale);

  return (
    <Screen className="mx-auto flex min-h-dvh w-full max-w-3xl flex-col gap-8 px-4 pt-0 pb-[calc(env(safe-area-inset-bottom)+2rem)] sm:px-6">
      <AppHeader title={t(locale, "forAiTitle")} backTo="/" />
      <ForAiPage />
    </Screen>
  );
}
