import { useEffect, useState, type ReactNode } from "react";
import { Link } from "@tanstack/react-router";
import type { Locale } from "@/lib/bible/books";
import { APP_STORE_LIVE, APP_STORE_URL, INSTAGRAM_URL } from "@/lib/app-store";
import { FEATURE_ORDER, MARKETING } from "@/lib/marketing-copy";
import { writeLocaleCookie } from "@/lib/i18n";
import { useAppStore } from "@/lib/store";
import { Wordmark } from "@/components/wordmark";
import { cn } from "@/lib/utils";

const LOCALES: Locale[] = ["pt", "en", "es"];

const JSON_LD = {
  "@context": "https://schema.org",
  "@type": "SoftwareApplication",
  name: "Katecheo",
  url: "https://katecheo.app",
  applicationCategory: "LifestyleApplication",
  operatingSystem: "iOS",
  offers: { "@type": "Offer", price: "0", priceCurrency: "USD" },
  description:
    "Bible study notebook for iPhone: notes with references that open in your Bible app, themes, reading plans, groups and friends. Katecheo never shows Bible text.",
  inLanguage: ["pt-BR", "en", "es"],
  sameAs: [INSTAGRAM_URL, "https://github.com/betoverli/katecheo"],
};

export function Landing({ initialLocale }: { initialLocale?: Locale }) {
  const storeLocale = useAppStore((s) => s.locale);
  const setLocale = useAppStore((s) => s.setLocale);
  const [locale, setLocal] = useState<Locale>(initialLocale ?? storeLocale);
  const copy = MARKETING[locale];

  useEffect(() => {
    if (initialLocale && initialLocale !== storeLocale) {
      setLocale(initialLocale);
      setLocal(initialLocale);
    }
    // Only sync the SSR-preferred locale once on mount.
    // eslint-disable-next-line react-hooks/exhaustive-deps -- mount sync
  }, []);

  useEffect(() => {
    setLocal(storeLocale);
  }, [storeLocale]);

  function pickLocale(next: Locale) {
    setLocale(next);
    setLocal(next);
    writeLocaleCookie(next);
    if (typeof document !== "undefined") {
      document.documentElement.lang = next === "pt" ? "pt-BR" : next;
      document.documentElement.setAttribute("data-locale", next);
    }
  }

  return (
    <div className="marketing-page relative min-h-dvh overflow-x-hidden bg-bg text-fg">
      <script type="application/ld+json" dangerouslySetInnerHTML={{ __html: JSON.stringify(JSON_LD) }} />
      <div className="pointer-events-none absolute inset-0 -z-10 marketing-atmosphere" aria-hidden />

      <header className="mx-auto flex w-full max-w-5xl items-center justify-between gap-3 px-5 pt-[calc(env(safe-area-inset-top)+1.25rem)] sm:px-8">
        <Wordmark size="sm" className="marketing-fade-in" />
        <div className="flex gap-1 marketing-fade-in marketing-delay-1">
          {LOCALES.map((item) => {
            const active = locale === item;
            return (
              <button
                key={item}
                type="button"
                suppressHydrationWarning
                onClick={() => pickLocale(item)}
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
      </header>

      <main>
        <section className="mx-auto flex min-h-[min(88dvh,920px)] w-full max-w-5xl flex-col justify-center px-5 pb-16 pt-10 sm:px-8 sm:pt-14">
          <div className="max-w-2xl">
            <h1 className="marketing-fade-up">
              <Wordmark size="lg" className="block text-[clamp(2.75rem,8vw,4.75rem)] leading-none" />
            </h1>
            <p className="mt-5 max-w-xl font-display text-2xl leading-snug tracking-tight text-fg italic sm:text-3xl marketing-fade-up marketing-delay-1">
              {copy.tagline}
            </p>
            <p className="mt-4 max-w-lg text-pretty text-base leading-relaxed text-muted marketing-fade-up marketing-delay-2">
              {copy.lead}
            </p>
            <div className="mt-8 flex flex-wrap items-center gap-3 marketing-fade-up marketing-delay-3">
              <AppStoreCta locale={locale} />
            </div>
          </div>

          <div className="mt-14 w-full max-w-md self-stretch marketing-fade-up marketing-delay-4 sm:max-w-lg">
            <PhoneFrame label={copy.features.notes.visual}>
              <NotesPlaceholder locale={locale} />
            </PhoneFrame>
          </div>
        </section>

        <section className="border-t border-separator/60 bg-surface/40">
          <div className="mx-auto w-full max-w-5xl px-5 py-16 sm:px-8 sm:py-20">
            <p className="text-xs font-medium tracking-wide text-subtle uppercase">{copy.featuresEyebrow}</p>
            <div className="mt-10 space-y-20 sm:space-y-28">
              {FEATURE_ORDER.map((id, index) => {
                const feature = copy.features[id];
                const reverse = index % 2 === 1;
                return (
                  <article
                    key={id}
                    className={cn(
                      "grid items-center gap-10 lg:grid-cols-2 lg:gap-16",
                      reverse && "lg:[&>*:first-child]:order-2",
                    )}
                  >
                    <div>
                      <h2 className="font-display text-3xl tracking-tight text-fg italic sm:text-4xl">
                        {feature.title}
                      </h2>
                      <p className="mt-4 max-w-md text-pretty text-base leading-relaxed text-muted">
                        {feature.body}
                      </p>
                    </div>
                    <PhoneFrame label={feature.visual}>
                      {id === "notes" ? <NotesPlaceholder locale={locale} /> : null}
                      {id === "themes" ? <ThemesPlaceholder locale={locale} /> : null}
                      {id === "reading" ? <ReadingPlaceholder locale={locale} /> : null}
                      {id === "groups" ? <GroupsPlaceholder locale={locale} /> : null}
                    </PhoneFrame>
                  </article>
                );
              })}
            </div>
          </div>
        </section>
      </main>

      <footer className="border-t border-separator/60">
        <div className="mx-auto flex w-full max-w-5xl flex-col gap-6 px-5 py-10 sm:flex-row sm:items-center sm:justify-between sm:px-8">
          <div className="space-y-2">
            <Wordmark size="sm" />
            <p className="text-xs text-subtle">{copy.footerRights}</p>
          </div>
          <nav className="flex flex-wrap gap-x-4 gap-y-2 text-sm text-muted">
            <a
              href={INSTAGRAM_URL}
              target="_blank"
              rel="noreferrer"
              className="underline-offset-2 hover:text-fg hover:underline"
            >
              {copy.instagram}
            </a>
            <Link to="/privacy" className="underline-offset-2 hover:text-fg hover:underline">
              {copy.footerPrivacy}
            </Link>
            <Link to="/terms" className="underline-offset-2 hover:text-fg hover:underline">
              {copy.footerTerms}
            </Link>
            <Link to="/contact" className="underline-offset-2 hover:text-fg hover:underline">
              {copy.footerContact}
            </Link>
            <Link to="/for-ai" className="underline-offset-2 hover:text-fg hover:underline">
              {copy.footerForAi}
            </Link>
          </nav>
        </div>
      </footer>
    </div>
  );
}

function AppStoreCta({ locale }: { locale: Locale }) {
  const copy = MARKETING[locale];
  if (!APP_STORE_LIVE || !APP_STORE_URL) {
    return (
      <span className="inline-flex min-h-12 items-center rounded-md bg-elevated px-5 text-sm font-semibold text-fg shadow-[inset_0_0_0_1px_var(--color-border)]">
        {copy.comingSoon}
      </span>
    );
  }
  return (
    <a
      href={APP_STORE_URL}
      className="inline-flex min-h-12 items-center rounded-md bg-accent px-5 text-sm font-semibold text-accent-fg transition-transform hover:brightness-110 active:scale-[0.99]"
      rel="noreferrer"
    >
      {copy.openAppStore}
    </a>
  );
}

function PhoneFrame({ label, children }: { label: string; children: ReactNode }) {
  return (
    <div className="marketing-device mx-auto w-full max-w-[280px] sm:max-w-[300px]">
      <div className="rounded-[2rem] bg-elevated p-2 shadow-[0_24px_60px_rgb(0_0_0/35%)] ring-1 ring-border">
        <div className="overflow-hidden rounded-[1.55rem] bg-bg">
          <div className="flex items-center justify-between px-4 pt-3 pb-2">
            <span className="text-[10px] font-medium tracking-wide text-subtle uppercase">{label}</span>
            <span className="h-1.5 w-16 rounded-full bg-fill" />
          </div>
          <div className="min-h-[420px] px-3 pb-4">{children}</div>
        </div>
      </div>
    </div>
  );
}

function NotesPlaceholder({ locale }: { locale: Locale }) {
  const lines =
    locale === "en"
      ? ["Meeting notes", "John 3:16 → opens in Bible app", "Romans 8:28", "Never shows Bible text"]
      : locale === "es"
        ? ["Notas de reunión", "Juan 3:16 → abre en la Biblia", "Romanos 8:28", "Nunca muestra el texto"]
        : ["Notas da reunião", "João 3:16 → abre no app da Bíblia", "Romanos 8:28", "Nunca mostra o texto"];
  return (
    <div className="space-y-3 pt-2">
      {lines.map((line, i) => (
        <div
          key={line}
          className={cn(
            "rounded-lg px-3 py-3 text-sm",
            i === 1 ? "bg-accent/15 text-fg ring-1 ring-accent/30" : "bg-surface text-muted",
          )}
        >
          {line}
        </div>
      ))}
    </div>
  );
}

function ThemesPlaceholder({ locale }: { locale: Locale }) {
  const items =
    locale === "en"
      ? ["Faith", "Hope", "Prayer", "Grace"]
      : locale === "es"
        ? ["Fe", "Esperanza", "Oración", "Gracia"]
        : ["Fé", "Esperança", "Oração", "Graça"];
  return (
    <div className="grid grid-cols-2 gap-2 pt-2">
      {items.map((item) => (
        <div key={item} className="rounded-lg bg-surface px-3 py-6 text-center text-sm font-medium text-fg">
          {item}
        </div>
      ))}
    </div>
  );
}

function ReadingPlaceholder({ locale }: { locale: Locale }) {
  const title = locale === "en" ? "Gospels in 30 days" : locale === "es" ? "Evangelios en 30 días" : "Evangelhos em 30 dias";
  const day = locale === "en" ? "Day 12" : locale === "es" ? "Día 12" : "Dia 12";
  return (
    <div className="space-y-3 pt-2">
      <div className="rounded-lg bg-surface px-3 py-4">
        <p className="text-sm font-medium text-fg">{title}</p>
        <p className="mt-1 text-xs text-muted">{day}</p>
        <div className="mt-3 h-2 overflow-hidden rounded-full bg-elevated">
          <div className="h-full w-[40%] rounded-full bg-accent" />
        </div>
      </div>
      <div className="rounded-lg bg-surface px-3 py-3 text-sm text-muted">Matthew 5</div>
      <div className="rounded-lg bg-surface px-3 py-3 text-sm text-muted">Matthew 6</div>
    </div>
  );
}

function GroupsPlaceholder({ locale }: { locale: Locale }) {
  const title = locale === "en" ? "Study group" : locale === "es" ? "Grupo de estudio" : "Grupo de estudo";
  const friends = locale === "en" ? "Friends" : locale === "es" ? "Amigos" : "Amigos";
  return (
    <div className="space-y-3 pt-2">
      <div className="rounded-lg bg-surface px-3 py-4">
        <p className="text-sm font-medium text-fg">{title}</p>
        <div className="mt-3 flex -space-x-2">
          {["A", "B", "C"].map((letter) => (
            <span
              key={letter}
              className="flex size-8 items-center justify-center rounded-full bg-elevated text-xs font-semibold text-fg ring-2 ring-bg"
            >
              {letter}
            </span>
          ))}
        </div>
      </div>
      <div className="rounded-lg bg-surface px-3 py-3 text-sm text-muted">{friends}</div>
    </div>
  );
}
