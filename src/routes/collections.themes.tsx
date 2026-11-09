import { createFileRoute } from "@tanstack/react-router";
import { useMemo, useState } from "react";
import { AppHeader } from "@/components/app-header";
import { Screen } from "@/components/screen";
import { ThemeList } from "@/components/theme-list";
import { searchCollections } from "@/lib/bible/collections";
import { t } from "@/lib/i18n";
import { pageHead } from "@/lib/seo";
import { useAppStore } from "@/lib/store";

export const Route = createFileRoute("/collections/themes")({
  component: AllThemesRoute,
  head: () =>
    pageHead({
      title: "Katecheo — Todos os temas",
      description: "Lista A–Z de 160 temas bíblicos. Busque, abra uma lista e copie as referências com deep link.",
      path: "/collections/themes",
    }),
});

function AllThemesRoute() {
  const locale = useAppStore((s) => s.locale);
  const [query, setQuery] = useState("");
  const items = useMemo(() => searchCollections(query, locale), [query, locale]);

  return (
    <Screen className="mx-auto flex min-h-dvh w-full max-w-3xl flex-col gap-6 px-4 pt-0 pb-[calc(var(--tab-bar-height)+1.5rem)] sm:px-6">
      <AppHeader
        title={t(locale, "allThemes")}
        backTo="/collections"
        search={{ value: query, onChange: setQuery, placeholder: t(locale, "collectionsSearch") }}
      />
      <ThemeList items={items} from="all" />
    </Screen>
  );
}
