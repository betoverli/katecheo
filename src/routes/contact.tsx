import { createFileRoute } from "@tanstack/react-router";
import { AppHeader } from "@/components/app-header";
import { MailtoText } from "@/components/mailto-text";
import { Screen } from "@/components/screen";
import { CONTACT_EMAIL, CONTACT_MAILTO } from "@/lib/app-store";
import { contactCopy } from "@/lib/contact";
import { pageHead } from "@/lib/seo";
import { useAppStore } from "@/lib/store";

export const Route = createFileRoute("/contact")({
  component: ContactRoute,
  head: () =>
    pageHead({
      title: "Katecheo — Contato e suporte",
      description: "Suporte e contato do Katecheo: contato@katecheo.app, App Store e o app iPhone.",
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

      <section className="max-w-xl rounded-lg bg-surface px-5 py-5 shadow-[inset_0_0_0_1px_var(--color-border)]">
        <h2 className="text-xs font-medium tracking-wide text-muted uppercase">{copy.emailLabel}</h2>
        <p className="mt-2 text-sm leading-relaxed text-fg">
          {copy.emailHint}{" "}
          <a href={CONTACT_MAILTO} className="font-semibold text-accent underline-offset-2 hover:underline">
            {CONTACT_EMAIL}
          </a>
          .
        </p>
      </section>

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
