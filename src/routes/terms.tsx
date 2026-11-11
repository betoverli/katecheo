import { createFileRoute } from "@tanstack/react-router";
import { AppHeader } from "@/components/app-header";
import { MailtoText } from "@/components/mailto-text";
import { Screen } from "@/components/screen";
import { pageHead } from "@/lib/seo";
import { useAppStore } from "@/lib/store";
import { termsCopy } from "@/lib/terms";

export const Route = createFileRoute("/terms")({
  component: TermsRoute,
  head: () =>
    pageHead({
      title: "Katecheo — Termos de uso",
      description: "Termos de uso do Katecheo: app iOS, conta, conteúdo e disponibilidade.",
      path: "/terms",
    }),
});

function TermsRoute() {
  const locale = useAppStore((s) => s.locale);
  const copy = termsCopy(locale);
  return (
    <Screen className="mx-auto flex min-h-dvh w-full max-w-3xl flex-col gap-8 px-4 pt-0 pb-[calc(env(safe-area-inset-bottom)+2rem)] sm:px-6">
      <AppHeader title={copy.title} backTo="/" />
      <p className="text-xs tracking-wide text-muted uppercase">{copy.updated}</p>
      <div className="flex flex-col gap-8">
        {copy.sections.map((section) => (
          <section key={section.title} className="space-y-2">
            <h2 className="text-xs font-medium tracking-wide text-muted uppercase">{section.title}</h2>
            <MailtoText
              text={section.body}
              className="max-w-xl text-pretty text-sm leading-relaxed text-fg"
            />
          </section>
        ))}
      </div>
    </Screen>
  );
}
