import assert from "node:assert/strict";
import { describe, it } from "node:test";
import {
  localeFromAcceptLanguage,
  localeFromCookieHeader,
  resolveRequestLocale,
} from "./locale-prefer.ts";

describe("localeFromAcceptLanguage", () => {
  it("defaults to pt", () => {
    assert.equal(localeFromAcceptLanguage(null), "pt");
    assert.equal(localeFromAcceptLanguage(""), "pt");
    assert.equal(localeFromAcceptLanguage("fr-FR,fr;q=0.9"), "pt");
  });

  it("maps pt-BR, en, es from Accept-Language order", () => {
    assert.equal(localeFromAcceptLanguage("pt-BR,pt;q=0.9,en;q=0.8"), "pt");
    assert.equal(localeFromAcceptLanguage("en-US,en;q=0.9"), "en");
    assert.equal(localeFromAcceptLanguage("es-MX,es;q=0.9,en;q=0.8"), "es");
    assert.equal(localeFromAcceptLanguage("en;q=0.8,pt-BR;q=0.9"), "pt");
  });
});

describe("resolveRequestLocale", () => {
  it("prefers cookie over Accept-Language", () => {
    assert.equal(
      resolveRequestLocale({ cookie: "v2n-locale=en; Path=/", acceptLanguage: "pt-BR" }),
      "en",
    );
    assert.equal(localeFromCookieHeader("a=1; v2n-locale=es"), "es");
  });
});
