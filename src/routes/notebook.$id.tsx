import { createFileRoute, Link } from "@tanstack/react-router";
import { AppHeader } from "@/components/app-header";
import { Screen } from "@/components/screen";
import { NotebookEditor } from "@/components/notebook-editor";
import { t } from "@/lib/i18n";
import { pageHead } from "@/lib/seo";
import { useAppStore } from "@/lib/store";
import { Button } from "@/components/ui/button";

export const Route = createFileRoute("/notebook/$id")({
  component: NotebookNoteRoute,
  validateSearch: (search: Record<string, unknown>): { g?: string } => ({
    g: typeof search.g === "string" && search.g.length > 0 ? search.g.slice(0, 40) : undefined,
  }),
  head: () =>
    pageHead({
      title: "Katecheo — Nota",
      description: "Nota do caderno.",
      path: "/notebook",
    }),
});

function NotebookNoteRoute() {
  const { id } = Route.useParams();
  const { g } = Route.useSearch();
  const locale = useAppStore((s) => s.locale);
  const note = useAppStore((s) => s.notes.find((item) => item.id === id));
  if (!note) {
    return (
      <Screen className="mx-auto flex min-h-dvh w-full max-w-3xl flex-col gap-6 px-4 pt-0 pb-8 sm:px-6">
        <AppHeader
          title={t(locale, "notebook")}
          backTo={g ? "/groups/$id" : "/notebook"}
          backParams={g ? { id: g } : undefined}
        />
        <p className="text-sm text-muted">{t(locale, "notebookEmpty")}</p>
        <Button asChild>
          <Link to={g ? "/groups/$id" : "/notebook"} params={g ? { id: g } : undefined}>
            {t(locale, "back")}
          </Link>
        </Button>
      </Screen>
    );
  }
  return (
    <main className="note-screen mx-auto flex min-h-dvh w-full max-w-3xl flex-col gap-4 px-4 pt-0 sm:px-6">
      <NotebookEditor note={note} fromGroup={g} />
    </main>
  );
}
