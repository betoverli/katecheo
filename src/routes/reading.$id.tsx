import { createFileRoute, Navigate } from "@tanstack/react-router";
import { AppHeader } from "@/components/app-header";
import { Screen } from "@/components/screen";
import { ReadingPlanDetail } from "@/components/reading-plan-detail";
import { planById, planCategoryById, planLead } from "@/lib/bible/reading-plans";
import { t } from "@/lib/i18n";
import { pageHead } from "@/lib/seo";
import { useAppStore } from "@/lib/store";

export const Route = createFileRoute("/reading/$id")({
  component: ReadingPlanRoute,
  validateSearch: (search: Record<string, unknown>): { from?: string } => ({
    from: typeof search.from === "string" ? search.from : undefined,
  }),
  head: ({ params }) => {
    const plan = planById(params.id);
    const name = plan?.names.pt ?? "Leitura";
    const lead = plan ? planLead(plan.id, "pt") : "";
    return pageHead({
      title: `Katecheo — ${name}`,
      description: lead || (plan ? `${plan.names.pt}: ${plan.days.length} dias de capítulos completos.` : "Plano de leitura Katecheo."),
      path: `/reading/${params.id}`,
    });
  },
});

function ReadingPlanRoute() {
  const { id } = Route.useParams();
  const { from } = Route.useSearch();
  const locale = useAppStore((s) => s.locale);
  const plan = planById(id);
  if (!plan) return <Navigate to="/reading" />;

  const category = from && from !== "all" ? planCategoryById(from) : undefined;
  const backTo = from === "all" ? "/reading/all" : category ? "/reading/category/$categoryId" : "/reading";
  const backParams = category ? { categoryId: category.id } : undefined;
  const backLabel = category ? category.names[locale] : from === "all" ? t(locale, "allPlans") : t(locale, "reading");

  return (
    <Screen className="mx-auto flex min-h-dvh w-full max-w-3xl flex-col gap-6 px-4 pt-0 pb-[calc(var(--tab-bar-height)+1.5rem)] sm:px-6">
      <AppHeader title={plan.names[locale]} backTo={backTo} backParams={backParams} backLabel={backLabel} />
      <ReadingPlanDetail plan={plan} />
    </Screen>
  );
}
