import { createFileRoute, Link, useNavigate } from "@tanstack/react-router";
import { useEffect, useState } from "react";
import { AppHeader } from "@/components/app-header";
import { Screen } from "@/components/screen";
import { NotebookEditor } from "@/components/notebook-editor";
import { useCurrentUserState } from "@/lib/auth/use-current-user";
import { t } from "@/lib/i18n";
import { getGrantedNote, getSharedNote } from "@/lib/notebook-cloud";
import { remixNote } from "@/lib/notebook-local";
import type { Note, Speaker } from "@/lib/notebook";
import { pageHead } from "@/lib/seo";
import { useAppStore } from "@/lib/store";
import { Button } from "@/components/ui/button";

export const Route = createFileRoute("/n/$id")({
  component: SharedNoteRoute,
  validateSearch: (search: Record<string, unknown>): { g?: string } => ({
    g: typeof search.g === "string" && search.g.length > 0 ? search.g.slice(0, 40) : undefined,
  }),
  head: () => {
    const seo = pageHead({
      title: "Katecheo — Nota",
      description: "Nota compartilhada do caderno.",
      path: "/n",
    });
    return { ...seo, meta: [...seo.meta, { name: "robots", content: "noindex" }] };
  },
});

function SharedNoteRoute() {
  const { id } = Route.useParams();
  const { g } = Route.useSearch();
  const locale = useAppStore((s) => s.locale);
  const hydrated = useAppStore((s) => s.cloudHydrated);
  const mine = useAppStore((s) => s.notes.find((item) => item.id === id));
  const { user, isPending } = useCurrentUserState();
  const navigate = useNavigate();
  const [payload, setPayload] = useState<{ note: Note; speakers: Speaker[] } | null | undefined>(undefined);

  useEffect(() => {
    if (isPending) return;
    let cancelled = false;
    void (async () => {
      if (user) {
        try {
          const granted = await getGrantedNote({ data: { id } });
          if (cancelled) return;
          if (granted) {
            setPayload(granted);
            return;
          }
        } catch {
          /* fall through */
        }
      }
      try {
        const shared = await getSharedNote({ data: { id } });
        if (!cancelled) setPayload(shared);
      } catch {
        if (!cancelled) setPayload(null);
      }
    })();
    return () => {
      cancelled = true;
    };
  }, [id, user, isPending]);

  if (!hydrated) return null;

  if (mine) {
    return (
      <main className="note-screen mx-auto flex min-h-dvh w-full max-w-3xl flex-col gap-4 px-4 pt-0 sm:px-6">
        <NotebookEditor note={mine} fromGroup={g} />
      </main>
    );
  }

  const note = payload?.note;
  if (payload === undefined) {
    return (
      <Screen className="mx-auto flex min-h-dvh w-full max-w-3xl flex-col px-4 pt-0 sm:px-6">
        <AppHeader
          title={t(locale, "notebook")}
          backTo={g ? "/groups/$id" : "/notebook"}
          backParams={g ? { id: g } : undefined}
        />
      </Screen>
    );
  }
  if (!note) {
    return (
      <Screen className="mx-auto flex min-h-dvh w-full max-w-3xl flex-col gap-6 px-4 pt-0 sm:px-6">
        <AppHeader
          title={t(locale, "notebook")}
          backTo={g ? "/groups/$id" : "/notebook"}
          backParams={g ? { id: g } : undefined}
        />
        <p className="text-sm text-muted">{t(locale, "notebookEmpty")}</p>
      </Screen>
    );
  }

  return (
    <main className="note-screen mx-auto flex min-h-dvh w-full max-w-3xl flex-col gap-4 px-4 pt-0 sm:px-6">
      <NotebookEditor
        note={note}
        readOnly
        speakerList={payload?.speakers ?? []}
        fromGroup={g}
        footer={
          <div className="mt-4 flex flex-col gap-3 pb-8">
            <Button
              onClick={() => {
                const copy = remixNote(note, payload?.speakers ?? []);
                if (copy) void navigate({ to: "/notebook/$id", params: { id: copy.id }, search: g ? { g } : undefined });
              }}
            >
              {t(locale, "notebookRemix")}
            </Button>
            <Button variant="ghost" asChild>
              <Link to="/notebook">{t(locale, "back")}</Link>
            </Button>
          </div>
        }
      />
    </main>
  );
}
