import { createFileRoute, useNavigate } from "@tanstack/react-router";
import { useEffect, useRef, useState } from "react";
import { FileUp } from "lucide-react";
import { AppHeader } from "@/components/app-header";
import { Screen } from "@/components/screen";
import { Button } from "@/components/ui/button";
import { t } from "@/lib/i18n";
import { draftToNote, htmlToText, textToDraft, type ImportDraft } from "@/lib/notebook-import";
import { fileToText } from "@/lib/notebook-import-file";
import { createLocalNote, upsertLocalSpeaker } from "@/lib/notebook-local";
import { pageHead } from "@/lib/seo";
import { useAppStore } from "@/lib/store";
import { notePreview } from "@/lib/notebook";

export const Route = createFileRoute("/notebook/import")({
  component: NotebookImportRoute,
  validateSearch: (search: Record<string, unknown>): { shared?: boolean } => ({
    shared: search.shared === true || search.shared === "1" || search.shared === "true",
  }),
  head: () =>
    pageHead({
      title: "Katecheo — Importar nota",
      description: "Importe uma nota do Notes, Docs, PDF ou Word e gere pílulas de referências.",
      path: "/notebook/import",
    }),
});

async function readShared(): Promise<{ text: string; filename?: string } | null> {
  try {
    const cache = await caches.open("Katecheo-share");
    const metaRes = await cache.match("/__import_share");
    if (!metaRes) return null;
    const meta = (await metaRes.json()) as { text?: string; title?: string; fileName?: string };
    const fileRes = await cache.match("/__import_file");
    await cache.delete("/__import_share");
    await cache.delete("/__import_file");
    if (fileRes) {
      const blob = await fileRes.blob();
      const name = meta.fileName || "nota";
      const file = new File([blob], name, { type: blob.type });
      return fileToText(file);
    }
    const text = [meta.title, meta.text].filter(Boolean).join("\n").trim();
    return text ? { text, filename: meta.fileName } : null;
  } catch {
    return null;
  }
}

function NotebookImportRoute() {
  const locale = useAppStore((s) => s.locale);
  const copyLocale = useAppStore((s) => s.copyLocale);
  const speakers = useAppStore((s) => s.speakers);
  const navigate = useNavigate();
  const { shared } = Route.useSearch();
  const [raw, setRaw] = useState("");
  const [filename, setFilename] = useState("");
  const [draft, setDraft] = useState<ImportDraft | null>(null);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState("");
  const fileRef = useRef<HTMLInputElement>(null);

  function run(text: string, name?: string) {
    const next = textToDraft(text, { locale: copyLocale, filename: name, existing: speakers });
    setDraft(next.blocks.length ? next : null);
  }

  useEffect(() => {
    if (!shared) return;
    void readShared().then((payload) => {
      if (!payload?.text) return;
      setRaw(payload.text);
      setFilename(payload.filename ?? "");
      run(payload.text, payload.filename);
    });
  }, [shared]);

  async function onFile(file: File) {
    setBusy(true);
    setError("");
    try {
      const payload = await fileToText(file);
      setRaw(payload.text);
      setFilename(payload.filename);
      run(payload.text, payload.filename);
    } catch {
      setError(t(locale, "notebookImportFail"));
    } finally {
      setBusy(false);
    }
  }

  function onPasteHtml(html: string, plain: string) {
    const text = html ? htmlToText(html) : plain;
    setRaw(text);
    run(text, filename);
  }

  function create() {
    if (!draft) return;
    for (const speaker of draft.speakers) upsertLocalSpeaker(speaker);
    const note = createLocalNote(draftToNote(draft));
    void navigate({ to: "/notebook/$id", params: { id: note.id } });
  }

  return (
    <Screen className="mx-auto flex min-h-dvh w-full max-w-3xl flex-col gap-6 px-4 pt-0 pb-[calc(env(safe-area-inset-bottom)+2rem)] sm:px-6">
      <AppHeader title={t(locale, "notebookImport")} backTo="/notebook" />
      <p className="text-sm leading-relaxed text-muted">{t(locale, "notebookImportHint")}</p>
      <textarea
        value={raw}
        onChange={(event) => {
          setRaw(event.target.value);
          run(event.target.value, filename);
        }}
        onPaste={(event) => {
          const html = event.clipboardData.getData("text/html");
          const plain = event.clipboardData.getData("text/plain");
          if (html) {
            event.preventDefault();
            onPasteHtml(html, plain);
          }
        }}
        placeholder={t(locale, "notebookImportPaste")}
        className="min-h-40 w-full rounded-lg bg-surface px-4 py-3 text-base text-fg outline-none"
      />
      <input
        ref={fileRef}
        type="file"
        accept=".txt,.md,.html,.htm,.pdf,.docx,.rtf,text/plain,text/html,application/pdf,application/vnd.openxmlformats-officedocument.wordprocessingml.document"
        className="hidden"
        onChange={(event) => {
          const file = event.target.files?.[0];
          event.target.value = "";
          if (file) void onFile(file);
        }}
      />
      <Button type="button" variant="secondary" className="w-full" disabled={busy} onClick={() => fileRef.current?.click()}>
        <FileUp />
        {t(locale, "notebookImportFile")}
      </Button>
      {error ? <p className="text-sm text-[#8b3a32]">{error}</p> : null}
      {draft ? (
        <section className="rounded-lg bg-surface px-4 py-4 shadow-[var(--shadow-border)]">
          <p className="text-xs font-medium tracking-wide text-muted uppercase">{t(locale, "notebookImportPreview")}</p>
          <input
            value={draft.title}
            onChange={(event) => setDraft({ ...draft, title: event.target.value.slice(0, 80) })}
            className="mt-2 h-11 w-full bg-transparent text-base font-semibold text-fg outline-none"
          />
          <p className="mt-1 text-xs text-muted">
            {draft.happenedAt}
            {draft.refCount ? ` · ${draft.refCount} ${t(locale, "notebookImportRefs")}` : ""}
            {draft.speakers.length ? ` · ${draft.speakers.map((item) => item.name).join(", ")}` : ""}
          </p>
          <p className="mt-3 line-clamp-4 text-sm leading-relaxed text-muted">
            {notePreview(draftToNote(draft)) || t(locale, "notebookImportEmpty")}
          </p>
          <Button className="mt-4 w-full" onClick={create}>
            {t(locale, "notebookImportCreate")}
          </Button>
        </section>
      ) : null}
      <p className="text-xs leading-relaxed text-subtle">{t(locale, "notebookImportShare")}</p>
    </Screen>
  );
}
