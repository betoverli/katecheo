import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { describe, it } from "node:test";
import { matchNativeV1Route, methodAllowed } from "./api/v1-router.ts";

const root = new URL("../../../", import.meta.url);

function read(rel: string) {
  return readFileSync(new URL(rel, root), "utf8");
}

describe("Phase 3 native profile API", () => {
  it("routes me, prefs, notify-prefs, and account delete/export", () => {
    assert.deepEqual(matchNativeV1Route("me"), { kind: "me" });
    assert.deepEqual(matchNativeV1Route("prefs"), { kind: "prefs" });
    assert.deepEqual(matchNativeV1Route("notify-prefs"), { kind: "notify-prefs" });
    assert.deepEqual(matchNativeV1Route("account/export"), { kind: "account-export" });
    assert.deepEqual(matchNativeV1Route("account/delete"), { kind: "account-delete" });
    assert.equal(methodAllowed({ kind: "me" }, "GET"), true);
    assert.equal(methodAllowed({ kind: "me" }, "PATCH"), true);
    assert.equal(methodAllowed({ kind: "prefs" }, "PATCH"), true);
    assert.equal(methodAllowed({ kind: "notify-prefs" }, "GET"), true);
    assert.equal(methodAllowed({ kind: "account-export" }, "GET"), true);
    assert.equal(methodAllowed({ kind: "account-delete" }, "POST"), true);
    assert.equal(methodAllowed({ kind: "account-delete" }, "GET"), false);
  });

  it("ships profile server + HTTP dispatch + catalog", () => {
    const profile = read("src/lib/native/api/v1-profile.server.ts");
    assert.match(profile, /getMeForUser/);
    assert.match(profile, /patchMeForUser/);
    assert.match(profile, /savePrefsForUser/);
    assert.match(profile, /getNotifyPrefsForUser/);
    assert.match(profile, /saveNotifyPrefsForUser/);
    assert.match(profile, /deleteAccountForUser/);
    assert.match(profile, /exportAccountForUser/);
    const http = read("src/lib/native/api/v1-http.ts");
    assert.match(http, /v1-profile\.server/);
    assert.match(http, /account-delete/);
    assert.match(http, /notify-prefs/);
    const catalog = read("src/lib/native/api/v1.server.ts");
    assert.match(catalog, /\/me/);
    assert.match(catalog, /\/prefs/);
    assert.match(catalog, /\/account\/delete/);
  });
});

describe("Phase 3 native Profile UI", () => {
  it("replaces Perfil Em breve with ProfileViewController", () => {
    const tabs = read("ios/App/Katecheo/NativeRootTabBarController.swift");
    assert.match(tabs, /ProfileViewController/);
    assert.doesNotMatch(tabs, /titleText:\s*"Perfil"/);
    const profile = read("ios/App/Katecheo/ProfileViewController.swift");
    assert.match(profile, /Contas conectadas/);
    assert.match(profile, /ConnectedIdentitiesViewController/);
    assert.match(profile, /Sair da conta/);
    assert.match(profile, /Apagar conta|Excluir conta/);
    assert.match(profile, /Baixar meus dados/);
    assert.match(profile, /getMe/);
    assert.match(profile, /signOut/);
    assert.match(profile, /deleteAccount/);
    assert.match(profile, /KCConfirmation\.presentActionSheet/);
    assert.match(profile, /String\(localized:\s*"Sair"\)/);
    assert.doesNotMatch(profile, /popoverPresentationController/);
    assert.doesNotMatch(profile, /utilizador|Terminar sessão|Gerir |Activa|Definições/);
  });

  it("ships KCConfirmation helper and Friends redesign (list-first, inline actions)", () => {
    const confirmation = read("ios/App/Katecheo/KCConfirmation.swift");
    assert.match(confirmation, /needsPopoverAnchor/);
    assert.match(confirmation, /presentActionSheet/);
    assert.match(confirmation, /horizontalSizeClass == \.regular/);
    const friends = read("ios/App/Katecheo/FriendsActivityViewController.swift");
    assert.match(friends, /incomingAccessory/);
    assert.match(friends, /Remover amigo/);
    assert.match(friends, /removeLink/);
    assert.match(friends, /KCConfirmation\.presentActionSheet/);
    assert.doesNotMatch(friends, /Nenhum pedido pendente/);
    assert.doesNotMatch(friends, /popoverPresentationController/);
    const project = read("ios/App/Katecheo.xcodeproj/project.pbxproj");
    assert.match(project, /KCConfirmation\.swift in Sources/);
    assert.match(project, /ConfirmationDialogTests\.swift in Sources/);
  });

  it("ships edit + theme + language + bible + notify screens", () => {
    const settings = read("ios/App/Katecheo/ProfileSettingsScreens.swift");
    assert.match(settings, /ProfileEditViewController/);
    assert.match(settings, /ProfileThemeViewController/);
    assert.match(settings, /ProfileLanguageViewController/);
    assert.match(settings, /ProfileBibleViewController/);
    assert.match(settings, /ProfileNotifyViewController/);
    assert.match(settings, /patchMe/);
    assert.match(settings, /patchPrefs/);
    assert.match(settings, /patchNotifyPrefs/);
    assert.match(settings, /Salvar/);
    assert.match(settings, /Configurações do iOS/);
    assert.match(settings, /AppLocale\.openSystemSettings|openSettingsURLString/);
    assert.match(settings, /copyLocale/);
    assert.match(settings, /Referências/);
    assert.doesNotMatch(settings, /utilizador|contacto|Actividade|Activa |Definições|Partilhas|Guardar/);
  });

  it("localizes UI via String Catalog (pt-BR / en / es) following the iPhone language", () => {
    const catalog = read("ios/App/Katecheo/Localizable.xcstrings");
    assert.match(catalog, /"sourceLanguage"\s*:\s*"pt-BR"/);
    assert.match(catalog, /"en"/);
    assert.match(catalog, /"es"/);
    const locale = read("ios/App/Katecheo/AppLocale.swift");
    assert.match(locale, /preferredLanguages/);
    assert.match(locale, /apiCode/);
    const project = read("ios/App/Katecheo.xcodeproj/project.pbxproj");
    assert.match(project, /Localizable\.xcstrings in Resources/);
    assert.match(project, /pt-BR/);
    const profile = read("ios/App/Katecheo/ProfileViewController.swift");
    assert.match(profile, /String\(localized:/);
    assert.match(profile, /Segue o idioma do iPhone/);
  });

  it("exposes profile methods on NativeAPIClient", () => {
    const client = read("ios/App/Katecheo/NativeAPIClient.swift");
    assert.match(client, /func getMe\(/);
    assert.match(client, /func patchMe\(/);
    assert.match(client, /func patchPrefs\(/);
    assert.match(client, /func deleteAccount\(/);
    assert.match(client, /account\/export/);
    assert.match(client, /struct MeDTO/);
  });

  it("registers Profile screens in the Xcode target", () => {
    const project = read("ios/App/Katecheo.xcodeproj/project.pbxproj");
    assert.match(project, /ProfileViewController\.swift in Sources/);
    assert.match(project, /ProfileSettingsScreens\.swift in Sources/);
  });

  it("keeps WebKit session bootstrap on the main actor", () => {
    const boot = read("ios/App/Katecheo/NativeSessionBootstrap.swift");
    assert.match(boot, /@MainActor/);
    assert.match(boot, /Thread\.isMainThread/);
    assert.match(boot, /WKWebsiteDataStore/);
  });
});
