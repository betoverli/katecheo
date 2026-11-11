import { createFileRoute } from "@tanstack/react-router";
import { AppHeader } from "@/components/app-header";
import { Screen } from "@/components/screen";
import { contactCopy } from "@/lib/contact";
import { pageHead } from "@/lib/seo";
import { useAppStore } from "@/lib/store";

export const Route = createFileRoute("/contact")({
  component: ContactRoute,
  head: () =>
    pageHead({
      title: "Katecheo — Contato e suporte",
      description: "Suporte e contato do Katecheo para App Store, privacidade e o app iPhone.",
      path: "/contact",
    }),
});

function ContactRoute() {
  const locale = useAppStore((s) => s.locale);
  const copy = contactCopy(locale);
  return (
    <Screen className="mx-auto flex min-h-dvh w-full max-w-3xl flex-col gap-8 px-4 pt-0 pb-[calc(env(safe-area-inset-bottom)+2rem)] sm:px-6">
      <AppHeader title={copy.title} backTo="/" />
      <p className="max-w-xl text-pretty text-sm leading-relaxed text-muted">{copy.lead}</p>
      <div className="flex flex-col gap-8">
        {copy.sections.map((section) => (
          <section key={section.title} className="space-y-2">
            <h2 className="text-xs font-medium tracking-wide text-muted uppercase">{section.title}</h2>
            <p className="max-w-xl text-pretty text-sm leading-relaxed text-fg">{section.body}</p>
          </section>
        ))}
      </div>
      <p className="text-sm text-muted">
        <a
          href="https://github.com/betoverli/katecheo"
          className="text-accent underline-offset-2 hover:underline"
          rel="noreferrer"
          target="_blank"
        >
          github.com/betoverli/katecheo
        </a>
      </p>
    </Screen>
  );
}
