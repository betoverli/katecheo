import { createFileRoute, Navigate } from "@tanstack/react-router";
import { AppHeader } from "@/components/app-header";
import { Screen } from "@/components/screen";
import { ThemeList } from "@/components/theme-list";
import { categoryById, themesInCategory } from "@/lib/bible/categories";
import { pageHead } from "@/lib/seo";
import { t } from "@/lib/i18n";
import { useAppStore } from "@/lib/store";

export const Route = createFileRoute("/collections/category/$categoryId")({
  component: CategoryRoute,
  head: ({ params }) => {
    const category = categoryById(params.categoryId);
    const name = category?.names.pt ?? "Coleções";
    return pageHead({
      title: `Katecheo — ${name}`,
      description: category
        ? `${category.names.pt} / ${category.names.en} / ${category.names.es}: listas de referências bíblicas para copiar com deep link.`
        : "Coleções Katecheo.",
      path: `/collections/category/${params.categoryId}`,
    });
  },
});

function CategoryRoute() {
  const { categoryId } = Route.useParams();
  const locale = useAppStore((s) => s.locale);
  const category = categoryById(categoryId);
  if (!category) return <Navigate to="/collections" />;

  return (
    <Screen className="mx-auto flex min-h-dvh w-full max-w-3xl flex-col gap-6 px-4 pt-0 pb-[calc(var(--tab-bar-height)+1.5rem)] sm:px-6">
      <AppHeader
        title={category.names[locale]}
        backTo="/collections"
        backLabel={t(locale, "collections")}
      />
      <ThemeList items={themesInCategory(categoryId, locale)} from={categoryId} />
    </Screen>
  );
}
