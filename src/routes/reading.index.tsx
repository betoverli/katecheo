import { createFileRoute } from "@tanstack/react-router";
import { useState } from "react";
import { AppHeader } from "@/components/app-header";
import { Screen } from "@/components/screen";
import { ReadingPage } from "@/components/reading-page";
import { t } from "@/lib/i18n";
import { pageHead } from "@/lib/seo";
import { useAppStore } from "@/lib/store";

export const Route = createFileRoute("/reading/")({
  component: ReadingIndexRoute,
  head: () =>
    pageHead({
      title: "Katecheo — Planos de leitura",
      description: "Planos de leitura bíblica por duração, evangelhos e livros. Marque os capítulos que já leu.",
      path: "/reading",
    }),
});

function ReadingIndexRoute() {
  const locale = useAppStore((s) => s.locale);
  const [query, setQuery] = useState("");
  return (
    <Screen className="mx-auto flex min-h-dvh w-full max-w-3xl flex-col gap-6 px-4 pt-0 pb-[calc(var(--tab-bar-height)+1.5rem)] sm:px-6">
      <AppHeader
        title={t(locale, "reading")}
        search={{ value: query, onChange: setQuery, placeholder: t(locale, "readingSearch") }}
      />
      <ReadingPage query={query} />
    </Screen>
  );
}