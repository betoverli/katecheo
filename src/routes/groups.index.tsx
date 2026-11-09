import { createFileRoute } from "@tanstack/react-router";
import { useState } from "react";
import { AppHeader } from "@/components/app-header";
import { Screen } from "@/components/screen";
import { NotebookGroupsHome } from "@/components/notebook-groups-home";
import { t } from "@/lib/i18n";
import { pageHead } from "@/lib/seo";
import { useAppStore } from "@/lib/store";

export const Route = createFileRoute("/groups/")({
  component: GroupsIndex,
  head: () =>
    pageHead({
      title: "Katecheo — Grupos",
      description: "Cadernos compartilhados. Crie um grupo, convide e publiquem notas juntos.",
      path: "/groups",
    }),
});

function GroupsIndex() {
  const locale = useAppStore((s) => s.locale);
  const [query, setQuery] = useState("");
  return (
    <Screen className="mx-auto flex min-h-dvh w-full max-w-3xl flex-col gap-6 px-4 pt-0 pb-[calc(var(--tab-bar-height)+5rem)] sm:px-6">
      <AppHeader
        title={t(locale, "notebookGroups")}
        search={{ value: query, onChange: setQuery, placeholder: t(locale, "notebookSearch") }}
      />
      <NotebookGroupsHome query={query} />
    </Screen>
  );
}
