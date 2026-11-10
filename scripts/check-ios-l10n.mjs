#!/usr/bin/env node
/**
 * Ensures Localizable.xcstrings exists and every string key has en + es translations.
 * Also checks InfoPlist.xcstrings and that Swift UI sources use String(localized:).
 */
import fs from "node:fs";
import path from "node:path";

const root = path.resolve(path.dirname(new URL(import.meta.url).pathname), "..");
const errors = [];

function readJson(rel) {
  const full = path.join(root, rel);
  if (!fs.existsSync(full)) {
    errors.push(`Falta ${rel}`);
    return null;
  }
  return JSON.parse(fs.readFileSync(full, "utf8"));
}

const catalog = readJson("ios/App/Katecheo/Localizable.xcstrings");
const infoCatalog = readJson("ios/App/Katecheo/InfoPlist.xcstrings");

if (catalog) {
  if (catalog.sourceLanguage !== "pt-BR") {
    errors.push(`Localizable.xcstrings sourceLanguage tem de ser pt-BR (é ${catalog.sourceLanguage}).`);
  }
  const strings = catalog.strings || {};
  const keys = Object.keys(strings);
  if (keys.length < 50) {
    errors.push(`Localizable.xcstrings tem poucas chaves (${keys.length}).`);
  }
  let missing = 0;
  for (const key of keys) {
    const locs = strings[key]?.localizations || {};
    for (const lang of ["en", "es", "pt-BR"]) {
      const value = locs[lang]?.stringUnit?.value;
      if (typeof value !== "string" || value.length === 0) {
        missing++;
        if (missing <= 20) {
          errors.push(`Chave sem tradução ${lang}: ${JSON.stringify(key).slice(0, 80)}`);
        }
      }
    }
  }
  if (missing > 20) {
    errors.push(`… e mais ${missing - 20} traduções em falta.`);
  }
}

if (infoCatalog) {
  for (const key of ["CFBundleDisplayName", "CFBundleName"]) {
    const locs = infoCatalog.strings?.[key]?.localizations || {};
    for (const lang of ["en", "es", "pt-BR"]) {
      if (!locs[lang]?.stringUnit?.value) {
        errors.push(`InfoPlist.xcstrings: ${key} sem ${lang}`);
      }
    }
  }
}

const project = fs.readFileSync(path.join(root, "ios/App/Katecheo.xcodeproj/project.pbxproj"), "utf8");
if (!project.includes("Localizable.xcstrings in Resources")) {
  errors.push("Localizable.xcstrings tem de estar nos Resources do target.");
}
if (!project.includes("InfoPlist.xcstrings in Resources")) {
  errors.push("InfoPlist.xcstrings tem de estar nos Resources do target.");
}
if (!project.includes("AppLocale.swift in Sources")) {
  errors.push("AppLocale.swift tem de estar nos Sources do target.");
}
if (!project.includes('"pt-BR"') || !/\bes,\s*$/m.test(project) && !project.includes("\n\t\t\t\tes,\n")) {
  if (!project.includes("knownRegions") || !project.includes("pt-BR") || !project.includes("\tes,")) {
    errors.push("project.pbxproj knownRegions tem de incluir pt-BR e es.");
  }
}

const infoPlist = fs.readFileSync(path.join(root, "ios/App/Katecheo/Info.plist"), "utf8");
if (!infoPlist.includes("CFBundleLocalizations") || !infoPlist.includes("pt-BR")) {
  errors.push("Info.plist tem de declarar CFBundleLocalizations com pt-BR, en, es.");
}

const languageScreen = fs.readFileSync(path.join(root, "ios/App/Katecheo/ProfileSettingsScreens.swift"), "utf8");
if (!languageScreen.includes("openSettingsURLString") && !languageScreen.includes("AppLocale.openSystemSettings")) {
  errors.push("ProfileLanguageViewController tem de abrir as Configurações do iOS para o idioma da interface.");
}
if (!languageScreen.includes("copyLocale")) {
  errors.push("ProfileLanguageViewController tem de manter o seletor de Referências (copyLocale).");
}
if (languageScreen.includes('prefs.locale = option.id') && languageScreen.includes('"locale": option.id')) {
  errors.push("Não volte o seletor de idioma de interface — use o idioma do iPhone.");
}

const appLocale = fs.readFileSync(path.join(root, "ios/App/Katecheo/AppLocale.swift"), "utf8");
if (!appLocale.includes("preferredLanguages") || !appLocale.includes("apiCode")) {
  errors.push("AppLocale tem de derivar o locale da interface de Locale.preferredLanguages.");
}

// Spot-check that key UI files localize strings.
for (const rel of [
  "ios/App/Katecheo/ProfileViewController.swift",
  "ios/App/Katecheo/NativeRootTabBarController.swift",
  "ios/App/Katecheo/NotebookListViewController.swift",
  "ios/App/Katecheo/VersesScreens.swift",
]) {
  const src = fs.readFileSync(path.join(root, rel), "utf8");
  if (!src.includes("String(localized:")) {
    errors.push(`${rel} tem de usar String(localized:).`);
  }
}

if (errors.length) {
  console.error("check-ios-l10n falhou:");
  for (const e of errors) console.error(" -", e);
  process.exit(1);
}
console.log("check-ios-l10n: catálogo pt-BR/en/es completo e wiring OK.");
