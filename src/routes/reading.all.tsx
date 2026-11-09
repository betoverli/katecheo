import { createFileRoute } from "@tanstack/react-router";
import { useMemo, useState } from "react";
import { AppHeader } from "@/components/app-header";
import { Screen } from "@/components/screen";
import { PlanList } from "@/components/plan-list";
import { searchPlans } from "@/lib/bible/reading-plans";
import { t } from "@/lib/i18n";
import { pageHead } from "@/lib/seo";
import { useAppStore } from "@/lib/store";

export const Route = createFileRoute("/reading/all")({
  component: AllPlansRoute,
  head: () =>
    pageHead({
      title: "Katecheo — Todos os planos",
      description: "Lista de planos de leitura bíblica. Capítulos completos, com progresso no aparelho.",
      path: "/reading/all",
    }),
});

function AllPlansRoute() {
  const locale = useAppStore((s) => s.locale);
  const [query, setQuery] = useState("");
  const items = useMemo(() => searchPlans(query, locale), [query, locale]);

  return (
    <Screen className="mx-auto flex min-h-dvh w-full max-w-3xl flex-col gap-6 px-4 pt-0 pb-[calc(var(--tab-bar-height)+1.5rem)] sm:px-6">
      <AppHeader
        title={t(locale, "allPlans")}
        backTo="/reading"
        search={{ value: query, onChange: setQuery, placeholder: t(locale, "readingSearch") }}
      />
      <PlanList items={items} from="all" />
    </Screen>
  );
}
