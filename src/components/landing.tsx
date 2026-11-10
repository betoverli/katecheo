import { BookOpen, ClipboardPaste, Copy } from "lucide-react";
import { Link } from "@tanstack/react-router";
import type { Locale } from "@/lib/bible/books";
import { t } from "@/lib/i18n";
import { useAppStore } from "@/lib/store";
import { Button } from "@/components/ui/button";
import { Wordmark } from "@/components/wordmark";
import { cn } from "@/lib/utils";

const LOCALES: Locale[] = ["pt", "en", "es"];

const JSON_LD = {
  "@context": "https://schema.org",
  "@type": "WebApplication",
  name: "Katecheo",
  url: "https://katecheo.app",
  applicationCategory: "UtilitiesApplication",
  operatingSystem: "Web",
  browserRequirements: "Requires JavaScript",
  offers: { "@type": "Offer", price: "0", priceCurrency: "USD" },
  description:
    "Rich-text Bible reference deep links, 160 themed collections, and 34 reading plans of whole chapters for YouVersion, Logos, and other Bible apps. Portuguese, English, Spanish. Offline PWA. API and MCP for agents.",
  inLanguage: ["pt", "en", "es"],
  sameAs: ["https://github.com/betoverli/katecheo"],
  featureList: [
    "Book, chapter and verse picker",
    "Rich-text copy with a deep link",
    "Multiple Bible apps",
    "160 themed collections in 14 categories",
    "34 reading plans of whole chapters",
    "Optional Google / email account for groups, notes and My plans",
    "API, skill and MCP for AI agents (no login)",
    "Works offline after first open",
  ],
};

export function Landing() {
  const locale = useAppStore((s) => s.locale);
  const setLocale = useAppStore((s) => s.setLocale);

  return (
    <main
      className="clip-box mx-auto flex h-dvh w-full max-w-lg flex-col px-5 pt-[calc(env(safe-area-inset-top)+1.25rem)] pb-[calc(env(safe-area-inset-bottom)+1.5rem)] sm:px-6"
      suppressHydrationWarning
    >
      <script type="application/ld+json" dangerouslySetInnerHTML={{ __html: JSON.stringify(JSON_LD) }} />
      <div className="flex items-center justify-between gap-3">
        <Wordmark size="sm" />
        <div className="flex gap-1">
          {LOCALES.map((item) => {
            const active = locale === item;
            return (
              <button
                key={item}
                type="button"
                suppressHydrationWarning
                onClick={() => setLocale(item)}
                aria-pressed={active}
                className={cn(
                  "min-h-11 min-w-11 rounded-md px-2 text-xs font-medium uppercase transition-colors",
                  active ? "bg-accent text-accent-fg" : "text-muted hover:bg-elevated hover:text-fg",
                )}
              >
                {item}
              </button>
            );
          })}
        </div>
      </div>

      <div className="mt-8 flex min-h-0 flex-1 flex-col overflow-y-auto">
        <p className="text-xs font-medium tracking-wide text-subtle uppercase">
          {t(locale, "landKicker")}
        </p>
        <h1 className="mt-3 font-display text-3xl leading-tight tracking-tight text-fg italic sm:text-5xl">
          {t(locale, "landHeadline")}
        </h1>
        <p className="mt-4 max-w-md text-pretty text-sm leading-relaxed text-muted">
          {t(locale, "landLead")}
        </p>

        <div className="mt-6 rounded-lg bg-surface px-5 py-4 shadow-[var(--shadow-border)]">
          <p className="text-xs tracking-wide text-subtle uppercase">{t(locale, "landDemoLabel")}</p>
          <p className="mt-2 font-display text-xl italic text-fg underline decoration-fg/35 underline-offset-4 sm:text-2xl">
            {t(locale, "landSample")}
          </p>
          <p className="mt-1 font-display text-xl italic text-fg underline decoration-fg/35 underline-offset-4 sm:text-2xl">
            {t(locale, "landSampleTwo")}
          </p>
          <p className="mt-3 text-xs text-muted">{t(locale, "landSampleHint")}</p>
        </div>

        <ul className="mt-6 space-y-3">
          <Step icon={BookOpen} label={t(locale, "landStepPick")} />
          <Step icon={Copy} label={t(locale, "landStepCopy")} />
          <Step icon={ClipboardPaste} label={t(locale, "landStepPaste")} />
        </ul>
        <p className="mt-4 max-w-md text-pretty text-xs leading-relaxed text-subtle">
          {t(locale, "landLimits")}
        </p>
      </div>

      <div className="mt-6 shrink-0 space-y-3 border-t border-border/60 pt-4">
        <div className="flex gap-2">
          <Button variant="secondary" className="flex-1" size="lg" asChild>
            <Link to="/login" search={{ create: false }}>
              {t(locale, "signIn")}
            </Link>
          </Button>
          <Button className="flex-[1.4]" size="lg" asChild>
            <Link to="/login" search={{ create: true }}>
              {t(locale, "createAccount")}
            </Link>
          </Button>
        </div>
        <p className="text-center text-xs text-subtle">
          <Link to="/app" className="underline-offset-2 hover:text-fg hover:underline">
            {t(locale, "landCta")}
          </Link>
        </p>
        <p className="text-center text-xs text-subtle">
          <Link to="/about" className="underline-offset-2 hover:text-fg hover:underline">
            {t(locale, "aboutTitle")}
          </Link>
          <span className="text-subtle"> · </span>
          <Link to="/privacy" className="underline-offset-2 hover:text-fg hover:underline">
            {t(locale, "privacyTitle")}
          </Link>
          <span className="text-subtle"> · </span>
          <Link to="/groups" className="underline-offset-2 hover:text-fg hover:underline">
            {t(locale, "notebookGroups")}
          </Link>
          <span className="text-subtle"> · </span>
          <Link to="/collections" className="underline-offset-2 hover:text-fg hover:underline">
            {t(locale, "collections")}
          </Link>
          <span className="text-subtle"> · </span>
          <Link to="/reading" className="underline-offset-2 hover:text-fg hover:underline">
            {t(locale, "reading")}
          </Link>
          <span className="text-subtle"> · </span>
          <Link to="/for-ai" className="underline-offset-2 hover:text-fg hover:underline">
            {t(locale, "forAiTitle")}
          </Link>
        </p>
        <p className="text-center text-xs text-subtle">{t(locale, "landFoot")}</p>
      </div>
    </main>
  );
}

function Step({ icon: Icon, label }: { icon: typeof BookOpen; label: string }) {
  return (
    <li className="flex items-center gap-3 text-sm text-fg">
      <span className="flex size-9 shrink-0 items-center justify-center rounded-md bg-elevated text-muted">
        <Icon className="size-4" />
      </span>
      {label}
    </li>
  );
}
