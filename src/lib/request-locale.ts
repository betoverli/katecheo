import { createServerFn } from "@tanstack/react-start";
import type { Locale } from "@/lib/bible/books";
import { resolveRequestLocale } from "@/lib/locale-prefer";

/** SSR locale: cookie override, else Accept-Language, else pt. */
export const getRequestLocale = createServerFn({ method: "GET" }).handler(async (): Promise<Locale> => {
  try {
    const { getRequest } = await import("@tanstack/react-start/server");
    const request = getRequest();
    return resolveRequestLocale({
      cookie: request?.headers.get("cookie"),
      acceptLanguage: request?.headers.get("accept-language"),
    });
  } catch {
    return "pt";
  }
});
