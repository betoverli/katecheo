import { createFileRoute, Navigate } from "@tanstack/react-router";
import { AppHeader } from "@/components/app-header";
import { Screen } from "@/components/screen";
import { PlanList } from "@/components/plan-list";
import { planCategoryById, plansInCategory } from "@/lib/bible/reading-plans";
import { t } from "@/lib/i18n";
import { pageHead } from "@/lib/seo";
import { useAppStore } from "@/lib/store";

export const Route = createFileRoute("/reading/category/$categoryId")({
  component: ReadingCategoryRoute,
  head: ({ params }) => {
    const category = planCategoryById(params.categoryId);
    const name = category?.names.pt ?? "Leitura";
    return pageHead({
      title: `Katecheo — ${name}`,
      description: category
        ? `${category.names.pt}: planos de leitura bíblica com capítulos completos.`
        : "Planos de leitura Katecheo.",
      path: `/reading/category/${params.categoryId}`,
    });
  },
});

function ReadingCategoryRoute() {
  const { categoryId } = Route.useParams();
  const locale = useAppStore((s) => s.locale);
  const category = planCategoryById(categoryId);
  if (!category) return <Navigate to="/reading" />;

  return (
    <Screen className="mx-auto flex min-h-dvh w-full max-w-3xl flex-col gap-6 px-4 pt-0 pb-[calc(var(--tab-bar-height)+1.5rem)] sm:px-6">
      <AppHeader title={category.names[locale]} backTo="/reading" backLabel={t(locale, "reading")} />
      <PlanList items={plansInCategory(categoryId, locale)} from={categoryId} />
    </Screen>
  );
}
