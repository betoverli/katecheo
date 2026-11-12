import type { Locale } from "./books";

export type Translation = {
  id: string;
  locale: Locale;
  abbr: string;
  name: Record<Locale, string>;
  youVersion: number;
  bibleGateway: string;
  bibliaOnline?: string;
  blb: string;
  logos: string;
};

export const TRANSLATIONS: Translation[] = [
  {
    id: "nvi-pt",
    locale: "pt",
    abbr: "NVI",
    name: {
      pt: "Nova Versão Internacional",
      en: "Nova Versão Internacional",
      es: "Nova Versão Internacional",
    },
    youVersion: 129,
    bibleGateway: "NVI",
    bibliaOnline: "nvi",
    blb: "nvi",
    logos: "NVI",
  },
  {
    id: "ntlh",
    locale: "pt",
    abbr: "NTLH",
    name: {
      pt: "Nova Tradução na Linguagem de Hoje",
      en: "Portuguese: Language of Today",
      es: "Nueva Traducción en Lenguaje de Hoy",
    },
    youVersion: 211,
    bibleGateway: "NTLH",
    bibliaOnline: "ntlh",
    blb: "ntlh",
    logos: "NTLH",
  },
  {
    id: "arc",
    locale: "pt",
    abbr: "ARC",
    name: {
      pt: "Almeida Revista e Corrigida",
      en: "Almeida Revista e Corrigida",
      es: "Almeida Revista y Corregida",
    },
    youVersion: 1608,
    bibleGateway: "ARC",
    bibliaOnline: "arc",
    blb: "arc",
    logos: "ARC",
  },
  {
    id: "naa",
    locale: "pt",
    abbr: "NAA",
    name: {
      pt: "Nova Almeida Atualizada",
      en: "Nova Almeida Atualizada",
      es: "Nova Almeida Atualizada",
    },
    youVersion: 1840,
    bibleGateway: "NAA",
    bibliaOnline: "naa",
    blb: "naa",
    logos: "NAA",
  },
  {
    id: "ara",
    locale: "pt",
    abbr: "ARA",
    name: {
      pt: "Almeida Revista e Atualizada",
      en: "Almeida Revista e Atualizada",
      es: "Almeida Revista y Actualizada",
    },
    youVersion: 212,
    bibleGateway: "ARA",
    bibliaOnline: "aa",
    blb: "ara",
    logos: "ARA",
  },
  {
    id: "niv",
    locale: "en",
    abbr: "NIV",
    name: {
      pt: "New International Version",
      en: "New International Version",
      es: "New International Version",
    },
    youVersion: 111,
    bibleGateway: "NIV",
    blb: "niv",
    logos: "NIV",
  },
  {
    id: "esv",
    locale: "en",
    abbr: "ESV",
    name: {
      pt: "English Standard Version",
      en: "English Standard Version",
      es: "English Standard Version",
    },
    youVersion: 59,
    bibleGateway: "ESV",
    blb: "esv",
    logos: "ESV",
  },
  {
    id: "kjv",
    locale: "en",
    abbr: "KJV",
    name: {
      pt: "King James Version",
      en: "King James Version",
      es: "King James Version",
    },
    youVersion: 1,
    bibleGateway: "KJV",
    blb: "kjv",
    logos: "KJV1900",
  },
  {
    id: "nlt",
    locale: "en",
    abbr: "NLT",
    name: {
      pt: "New Living Translation",
      en: "New Living Translation",
      es: "New Living Translation",
    },
    youVersion: 116,
    bibleGateway: "NLT",
    blb: "nlt",
    logos: "NLT",
  },
  {
    id: "nkjv",
    locale: "en",
    abbr: "NKJV",
    name: {
      pt: "New King James Version",
      en: "New King James Version",
      es: "New King James Version",
    },
    youVersion: 114,
    bibleGateway: "NKJV",
    blb: "nkjv",
    logos: "NKJV",
  },
  {
    id: "nasb",
    locale: "en",
    abbr: "NASB",
    name: {
      pt: "New American Standard Bible",
      en: "New American Standard Bible",
      es: "New American Standard Bible",
    },
    youVersion: 100,
    bibleGateway: "NASB",
    blb: "nasb95",
    logos: "NASB95",
  },
  {
    id: "csb",
    locale: "en",
    abbr: "CSB",
    name: {
      pt: "Christian Standard Bible",
      en: "Christian Standard Bible",
      es: "Christian Standard Bible",
    },
    youVersion: 1713,
    bibleGateway: "CSB",
    blb: "csb",
    logos: "CSB",
  },
  {
    id: "web",
    locale: "en",
    abbr: "WEB",
    name: {
      pt: "World English Bible",
      en: "World English Bible",
      es: "World English Bible",
    },
    youVersion: 206,
    bibleGateway: "WEB",
    blb: "web",
    logos: "WEB",
  },
  {
    id: "rvr1960",
    locale: "es",
    abbr: "RVR1960",
    name: {
      pt: "Reina-Valera 1960",
      en: "Reina-Valera 1960",
      es: "Reina-Valera 1960",
    },
    youVersion: 128,
    bibleGateway: "RVR1960",
    blb: "rvr60",
    logos: "RVR60",
  },
  {
    id: "nvi-es",
    locale: "es",
    abbr: "NVI",
    name: {
      pt: "Nueva Versión Internacional",
      en: "Nueva Versión Internacional",
      es: "Nueva Versión Internacional",
    },
    youVersion: 103,
    bibleGateway: "NVI",
    blb: "nvi",
    logos: "NVI",
  },
  {
    id: "ntv",
    locale: "es",
    abbr: "NTV",
    name: {
      pt: "Nueva Traducción Viviente",
      en: "Nueva Traducción Viviente",
      es: "Nueva Traducción Viviente",
    },
    youVersion: 149,
    bibleGateway: "NTV",
    blb: "ntv",
    logos: "NTV",
  },
];

export const DEFAULT_TRANSLATION: Record<Locale, string> = {
  pt: "nvi-pt",
  en: "niv",
  es: "rvr1960",
};

/**
 * Map a prefs / API translation value onto a known TRANSLATIONS id.
 * Accepts modern slug ids (`niv`, `nvi-pt`) and legacy YouVersion numeric
 * strings (`"111"` → `niv`). Unknown values fall back to the locale default.
 */
export function normalizeTranslationId(
  raw: string | undefined | null,
  locale: Locale = "pt",
): string {
  const fallback = DEFAULT_TRANSLATION[locale] ?? DEFAULT_TRANSLATION.pt;
  if (raw == null) return fallback;
  const trimmed = String(raw).trim();
  if (!trimmed) return fallback;
  if (TRANSLATIONS.some((item) => item.id === trimmed)) return trimmed;
  if (/^\d+$/.test(trimmed)) {
    const youVersion = Number(trimmed);
    const match = TRANSLATIONS.find((item) => item.youVersion === youVersion);
    if (match) return match.id;
  }
  return fallback;
}

export function translationById(id: string, locale: Locale = "pt"): Translation {
  const normalized = normalizeTranslationId(id, locale);
  return TRANSLATIONS.find((t) => t.id === normalized) ?? TRANSLATIONS[0];
}

export function translationsFor(locale: Locale): Translation[] {
  return TRANSLATIONS.filter((t) => t.locale === locale);
}
