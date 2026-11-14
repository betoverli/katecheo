import { useEffect, useState } from "react";
import { Link } from "@tanstack/react-router";
import type { Locale } from "@/lib/bible/books";
import {
  APP_STORE_LIVE,
  APP_STORE_URL,
  CONTACT_EMAIL,
  CONTACT_MAILTO,
  INSTAGRAM_URL,
} from "@/lib/app-store";
import {
  FEATURE_ORDER,
  MARKETING,
  SCREENSHOT_ORDER,
  SCREENSHOT_SIZE,
  type MarketingScreenshotId,
} from "@/lib/marketing-copy";
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
      <script
        type="application/ld+json"
        dangerouslySetInnerHTML={{ __html: JSON.stringify(JSON_LD) }}
      />
      <div
        className="pointer-events-none absolute inset-0 -z-10 marketing-atmosphere"
        aria-hidden
      />

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
                  active
                    ? "bg-accent text-accent-fg"
                    : "text-muted hover:bg-elevated hover:text-fg",
                )}
              >
                {item}
              </button>
            );
          })}
        </div>
      </header>

      <main>
        <section className="mx-auto flex w-full max-w-5xl flex-col justify-center px-5 pb-16 pt-10 sm:px-8 sm:pt-14">
          <div className="max-w-2xl">
            <h1 className="marketing-fade-up">
              <Wordmark
                size="lg"
                className="block text-[clamp(2.75rem,8vw,4.75rem)] leading-none"
              />
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

          <div className="marketing-hero-shot mt-10 w-full marketing-fade-up marketing-delay-4">
            <AppStoreScreenshot locale={locale} id="01-caderno" priority />
          </div>
        </section>

        <section className="border-t border-separator/60 bg-surface/40">
          <div className="mx-auto w-full max-w-5xl px-5 py-16 sm:px-8 sm:py-20">
            <p className="text-xs font-medium tracking-wide text-subtle uppercase">
              {copy.screenshotsEyebrow}
            </p>
            <ul className="marketing-shots mt-8" aria-label={copy.screenshotsEyebrow}>
              {SCREENSHOT_ORDER.map((id) => (
                <li key={id} className="marketing-shots-item">
                  <AppStoreScreenshot locale={locale} id={id} />
                </li>
              ))}
            </ul>

            <p className="mt-16 text-xs font-medium tracking-wide text-subtle uppercase sm:mt-20">
              {copy.featuresEyebrow}
            </p>
            <div className="mt-10 grid gap-12 sm:grid-cols-2 sm:gap-x-12 sm:gap-y-16">
              {FEATURE_ORDER.map((id) => {
                const feature = copy.features[id];
                return (
                  <article key={id}>
                    <h2 className="font-display text-3xl tracking-tight text-fg italic sm:text-4xl">
                      {feature.title}
                    </h2>
                    <p className="mt-4 max-w-md text-pretty text-base leading-relaxed text-muted">
                      {feature.body}
                    </p>
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
            <a href={CONTACT_MAILTO} className="underline-offset-2 hover:text-fg hover:underline">
              {CONTACT_EMAIL}
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

const APP_STORE_BADGE: Record<Locale, { alt: string; black: string; white: string }> = {
  pt: {
    alt: "Baixar na App Store",
    black: "/badges/download-on-the-app-store-black-pt-br.svg",
    white: "/badges/download-on-the-app-store-white-pt-br.svg",
  },
  en: {
    alt: "Download on the App Store",
    black: "/badges/download-on-the-app-store-black-en-us.svg",
    white: "/badges/download-on-the-app-store-white-en-us.svg",
  },
  es: {
    alt: "Consíguelo en el App Store",
    black: "/badges/download-on-the-app-store-black-es-es.svg",
    white: "/badges/download-on-the-app-store-white-es-es.svg",
  },
};

function AppStoreCta({ locale }: { locale: Locale }) {
  const copy = MARKETING[locale];
  if (!APP_STORE_LIVE || !APP_STORE_URL) {
    return (
      <span className="inline-flex min-h-12 items-center rounded-md bg-elevated px-5 text-sm font-semibold text-fg shadow-[inset_0_0_0_1px_var(--color-border)]">
        {copy.comingSoon}
      </span>
    );
  }
  const badge = APP_STORE_BADGE[locale];
  return (
    <a
      href={APP_STORE_URL}
      className="app-store-badge-link"
      rel="noreferrer"
      aria-label={badge.alt}
    >
      <img
        src={badge.white}
        alt=""
        width={144}
        height={48}
        className="app-store-badge app-store-badge-on-dark"
        aria-hidden="true"
      />
      <img
        src={badge.black}
        alt=""
        width={144}
        height={48}
        className="app-store-badge app-store-badge-on-light"
        aria-hidden="true"
      />
    </a>
  );
}

function AppStoreScreenshot({
  locale,
  id,
  priority = false,
}: {
  locale: Locale;
  id: MarketingScreenshotId;
  priority?: boolean;
}) {
  const copy = MARKETING[locale];
  const alt = copy.screenshotAlts[id];
  return (
    <div className="marketing-shot">
      <ScreenshotPicture
        locale={locale}
        id={id}
        theme="dark"
        alt={alt}
        priority={priority}
      />
      <ScreenshotPicture
        locale={locale}
        id={id}
        theme="light"
        alt={alt}
        priority={priority}
      />
    </div>
  );
}

function ScreenshotPicture({
  locale,
  id,
  theme,
  alt,
  priority,
}: {
  locale: Locale;
  id: MarketingScreenshotId;
  theme: "light" | "dark";
  alt: string;
  priority: boolean;
}) {
  const base = `/screenshots/${locale}/${id}-${theme}`;
  return (
    <picture className={`marketing-shot-on-${theme}`}>
      <source type="image/avif" srcSet={`${base}.avif`} />
      <source type="image/webp" srcSet={`${base}.webp`} />
      <img
        src={`${base}.webp`}
        width={SCREENSHOT_SIZE.width}
        height={SCREENSHOT_SIZE.height}
        alt={alt}
        loading={priority ? "eager" : "lazy"}
        fetchPriority={priority ? "high" : "low"}
        decoding="async"
        className="marketing-shot-image"
      />
    </picture>
  );
}
