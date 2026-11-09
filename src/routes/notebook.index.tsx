import { createFileRoute } from "@tanstack/react-router";
import { useState } from "react";
import { AppHeader } from "@/components/app-header";
import { Screen } from "@/components/screen";
import { NotebookHome } from "@/components/notebook-home";
import { t } from "@/lib/i18n";
import { pageHead } from "@/lib/seo";
import { useAppStore } from "@/lib/store";

export const Route = createFileRoute("/notebook/")({
  component: NotebookIndex,
  head: () =>
    pageHead({
      title: "Katecheo — Caderno",
      description: "Notas de reunião com referências bíblicas em pílulas e blocos de quem falou.",
      path: "/notebook",
    }),
});

function NotebookIndex() {
  const locale = useAppStore((s) => s.locale);
  const [query, setQuery] = useState("");
  return (
    <Screen className="mx-auto flex min-h-dvh w-full max-w-3xl flex-col gap-6 px-4 pt-0 pb-[calc(var(--tab-bar-height)+5rem)] sm:px-6">
      <AppHeader
        title={t(locale, "notebook")}
        search={{ value: query, onChange: setQuery, placeholder: t(locale, "notebookSearch") }}
      />
      <NotebookHome query={query} />
    </Screen>
  );
}
