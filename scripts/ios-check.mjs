#!/usr/bin/env node
/**
 * Checks the iOS shell without a Mac. The unsigned compile itself runs on the
 * macOS GitHub Actions runner (see .github/workflows/ios.yml).
 *
 * Phase 7: Capacitor site host removed; note editor is fully native (no product WKWebView).
 */
import { spawnSync } from "node:child_process";
import { readdirSync, readFileSync, statSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const root = join(dirname(fileURLToPath(import.meta.url)), "..");
const read = (path) => readFileSync(join(root, path), "utf8");

const errors = [];
const notes = [];

// --- Capacitor config: must NOT host the SPA ---
const config = read("capacitor.config.ts");
if (/server\s*:\s*\{[\s\S]*?url\s*:/.test(config)) {
  errors.push("Phase 5: capacitor.config.ts não pode definir server.url (host do site removido).");
}
if (config.includes("NSAllowsArbitraryLoads") || config.includes("capacitorHttp")) {
  errors.push("Não ligar HTTP livre nem o proxy CapacitorHttp.");
}
if (!config.includes("NativeNoteEditorView") && !config.includes("Phase 7")) {
  errors.push("capacitor.config.ts tem de documentar o editor nativo (Phase 7 / NativeNoteEditorView).");
}

const launchScreen = read("ios/App/App/Base.lproj/LaunchScreen.storyboard");
if (!launchScreen.includes("SplashBrand") || !launchScreen.includes("SplashBackground")) {
  errors.push("LaunchScreen tem de centrar SplashBrand sobre SplashBackground.");
}
if (launchScreen.includes("scaleAspectFill") || launchScreen.includes('image="Splash"')) {
  errors.push("LaunchScreen não pode voltar ao Splash em ecrã inteiro.");
}
for (const asset of [
  "ios/App/App/Assets.xcassets/SplashBrand.imageset/Contents.json",
  "ios/App/App/Assets.xcassets/SplashBackground.colorset/Contents.json",
]) {
  try {
    const json = read(asset);
    if (!json.includes('"value" : "dark"')) {
      errors.push(`${asset} tem de declarar a variante dark.`);
    }
  } catch {
    errors.push(`Ficheiro em falta: ${asset}`);
  }
}

const plist = read("ios/App/App/Info.plist");
if (!plist.includes("<string>verse2note</string>")) {
  errors.push("Falta o esquema verse2note no Info.plist.");
}
if (plist.includes("<key>NSAllowsArbitraryLoads</key>") || plist.includes("<key>NSExceptionAllowsInsecureHTTPLoads</key>")) {
  errors.push("Info.plist não deve abrir exceção de ATS. O site já é HTTPS.");
}
if (!plist.includes("remote-notification")) {
  errors.push("Falta UIBackgroundModes remote-notification.");
}
if (!plist.includes("Verse2NoteUniversalLinks")) {
  errors.push("Falta a flag Verse2NoteUniversalLinks no Info.plist.");
}

const releaseEntitlements = read("ios/App/App/AppRelease.entitlements");
if (!releaseEntitlements.includes("<string>production</string>")) {
  errors.push("O arquivo de Release tem de pedir APNs de produção (TestFlight).");
}
if (!releaseEntitlements.includes("applinks:verse2note.com")) {
  errors.push("O Release tem de declarar o domínio verse2note.com para Universal Links.");
}
if (!releaseEntitlements.includes("webcredentials:verse2note.com")) {
  errors.push("O Release tem de declarar webcredentials:verse2note.com (ASWebAuthenticationSession).");
}
if (!releaseEntitlements.includes("com.apple.developer.applesignin")) {
  errors.push("AppRelease.entitlements tem de incluir Sign in with Apple.");
}

const project = read("ios/App/App.xcodeproj/project.pbxproj");
if (project.includes("CODE_SIGN_ENTITLEMENTS = App/AppDebug")) {
  errors.push("A configuração Debug não deve exigir entitlements, para o build sem assinatura passar.");
}
if (!project.includes("CODE_SIGN_ENTITLEMENTS = App/AppRelease.entitlements")) {
  errors.push("Falta o entitlement de push na configuração Release.");
}
const debugTarget = project.split("504EC3171FED79650016851F /* Debug */")[1]?.split("name = Debug;")[0] ?? "";
const releaseTarget = project.split("504EC3181FED79650016851F /* Release */")[1]?.split("name = Release;")[0] ?? "";
if (debugTarget.includes("CODE_SIGN_ENTITLEMENTS") || !debugTarget.includes("VERSE2NOTE_UNIVERSAL_LINKS = NO")) {
  errors.push("A configuração Debug não deve pedir Universal Links nem entitlements.");
}
if (!releaseTarget.includes("VERSE2NOTE_UNIVERSAL_LINKS = YES") || !releaseTarget.includes("App/AppRelease.entitlements")) {
  errors.push("A configuração Release tem de ativar Universal Links e os entitlements.");
}
if (project.includes("CapApp-SPM") || project.includes("NativeShell.swift") || project.includes("LiquidChrome.swift")) {
  errors.push("Phase 5: o target Xcode não pode ligar CapApp-SPM nem NativeShell/LiquidChrome.");
}
if (project.includes("NoteMioloEditorView.swift")) {
  errors.push("Phase 7: NoteMioloEditorView tem de ser removido do target Xcode.");
}
if (!project.includes("NativeNoteEditorView.swift in Sources") || !project.includes("NoteDocumentCodec.swift in Sources")) {
  errors.push("NativeNoteEditorView / NoteDocumentCodec têm de estar no target Xcode.");
}
if (!project.includes("V2NDesign.swift in Sources") || !project.includes("V2NComponents.swift in Sources")) {
  errors.push("V2NDesign / V2NComponents (design system) têm de estar no target Xcode.");
}
if (!project.includes("BibleRefInsertPicker.swift in Sources")) {
  errors.push("BibleRefInsertPicker tem de estar no target Xcode.");
}
if (!project.includes("NativePushService.swift in Sources") || !project.includes("NativeDeepLinkRouter.swift in Sources")) {
  errors.push("NativePushService / NativeDeepLinkRouter têm de estar no target Xcode.");
}
if (!project.includes("LiquidGlassMaterial.m in Sources")) {
  errors.push("LiquidGlassMaterial tem de permanecer no target (vidro nativo).");
}
if (!project.includes('SWIFT_OBJC_BRIDGING_HEADER = "App/App-Bridging-Header.h"')) {
  errors.push("Falta o bridging header do material de vidro.");
}

const workflow = read(".github/workflows/ios.yml");
const selectorUses = workflow.split("node scripts/select-xcode.mjs").length - 1;
if (selectorUses < 2) {
  errors.push("Simulador e TestFlight têm de escolher o Xcode com scripts/select-xcode.mjs.");
}
if (workflow.includes("Xcode_26.1.app") || workflow.includes("Xcode_26.0.app")) {
  errors.push("O fluxo não pode fixar o Xcode 26.0/26.1.");
}
if (workflow.includes("npx cap sync")) {
  errors.push("Phase 5: o CI iOS não deve correr `cap sync` (Cap host removido).");
}
const selector = read("scripts/select-xcode.mjs");
if (!selector.includes("export function chooseXcode") || !selector.includes("sdk.major < 26")) {
  errors.push("O selector de Xcode tem de exigir o SDK do iOS 26 com runtime de simulador instalado.");
}

const scene = read("ios/App/App/SceneDelegate.swift");
if (!scene.includes("AppRoot.makeRootViewController")) {
  errors.push("SceneDelegate tem de montar a root via AppRoot.");
}
if (scene.includes("import Capacitor") || scene.includes("SceneDelegateProxy") || scene.includes("Verse2NoteBridge")) {
  errors.push("SceneDelegate não pode importar Capacitor nem montar o bridge Cap.");
}
if (!scene.includes("NativeDeepLinkRouter") || !scene.includes("NSUserActivityTypeBrowsingWeb")) {
  errors.push("SceneDelegate tem de encaminhar Universal Links para NativeDeepLinkRouter.");
}

const appRoot = read("ios/App/App/AppRoot.swift");
if (!appRoot.includes("NativeRootTabBarController") || appRoot.includes("Verse2NoteBridge") || appRoot.includes("capacitorSite")) {
  errors.push("AppRoot tem de montar só NativeRootTabBarController (sem Cap).");
}

const mainStoryboard = read("ios/App/App/Base.lproj/Main.storyboard");
if (!mainStoryboard.includes('customClass="NativeRootTabBarController"')) {
  errors.push("Main.storyboard tem de apontar para NativeRootTabBarController.");
}
if (mainStoryboard.includes("Verse2NoteBridge") || mainStoryboard.includes("CAPBridgeViewController")) {
  errors.push("Main.storyboard não pode referenciar o Cap bridge.");
}

const appDelegate = read("ios/App/App/AppDelegate.swift");
if (appDelegate.includes("import Capacitor") || appDelegate.includes("capacitorDidRegister")) {
  errors.push("AppDelegate tem de usar APNs nativo (sem Capacitor).");
}
if (!appDelegate.includes("NativePushService") || !appDelegate.includes("didRegisterForRemoteNotifications")) {
  errors.push("AppDelegate tem de registar o token APNs via NativePushService.");
}

const shellMode = read("ios/App/App/NativeShellMode.swift");
if (!shellMode.includes("nativePrimary") || !shellMode.includes("return .nativePrimary")) {
  errors.push("NativeShellMode tem de defaultar / forçar nativePrimary.");
}

const editor = read("ios/App/App/NativeNoteEditorView.swift");
if (!editor.includes("UITextView") || editor.includes("WKWebView") || editor.includes("import WebKit")) {
  errors.push("NativeNoteEditorView tem de ser UITextView nativo (sem WebKit).");
}
if (!editor.includes("inputAccessoryView") || !editor.includes("Referência bíblica")) {
  errors.push("NativeNoteEditorView tem de ter toolbar com referência bíblica (pt-BR).");
}
if (!editor.includes("@MainActor") && !editor.includes("Thread.isMainThread")) {
  errors.push("NativeNoteEditorView tem de exigir main thread / @MainActor.");
}

const codec = read("ios/App/App/NoteDocumentCodec.swift");
if (!codec.includes("attributedString(from") || !codec.includes("func document(") || !codec.includes("bibleRef")) {
  errors.push("NoteDocumentCodec tem de round-trip NoteDocument ↔ attributed string com bibleRef.");
}

const noteDetail = read("ios/App/App/NoteDetailViewController.swift");
if (noteDetail.includes("WKWebView") || noteDetail.includes("import WebKit") || noteDetail.includes("NoteMioloEditorView")) {
  errors.push("NoteDetailViewController não pode usar WebView / NoteMioloEditorView.");
}
if (!noteDetail.includes("NativeNoteEditorView")) {
  errors.push("NoteDetailViewController tem de hospedar NativeNoteEditorView.");
}

try {
  read("ios/App/App/NoteMioloEditorView.swift");
  errors.push("Phase 7: NoteMioloEditorView.swift ainda existe — remover.");
} catch {
  /* expected missing */
}

// Guard: no Cap / product WKWebView surfaces (bootstrap + Phase 6 import only).
const appDir = join(root, "ios/App/App");
const allowedWebKit = new Set([
  "NativeSessionBootstrap.swift",
  "SceneDelegate.swift",
  "LegacyWebStorageImporter.swift",
]);
const allowedWkWebView = new Set(["LegacyWebStorageImporter.swift"]);
const allowedCookieFlush = new Set(["SceneDelegate.swift", "NativeSessionBootstrap.swift"]);
/** Strip line/block comments so docstrings don't trip Cap/WebView guards. */
function stripComments(source) {
  return source
    .replace(/\/\*[\s\S]*?\*\//g, "")
    .replace(/(^|[^:])\/\/.*$/gm, "$1");
}

for (const name of readdirSync(appDir)) {
  const full = join(appDir, name);
  if (!statSync(full).isFile()) continue;
  if (!/\.(swift|m|h)$/.test(name)) continue;
  const body = stripComments(readFileSync(full, "utf8"));
  if (/\bimport\s+Capacitor\b/.test(body) || /\bCAPBridgeViewController\b/.test(body) || /\bCAPPlugin\b/.test(body)) {
    errors.push(`Phase 5: ${name} não pode usar Capacitor/CAPPlugin.`);
  }
  if (/\bWKWebView\b/.test(body) && !allowedWkWebView.has(name)) {
    errors.push(`Phase 7: WKWebView de produto proibido (só LegacyWebStorageImporter); encontrado em ${name}.`);
  }
  if (/\bimport\s+WebKit\b/.test(body) && !allowedWebKit.has(name)) {
    errors.push(`Phase 7: import WebKit fora do permitido (${name}).`);
  }
  if (/\bWKWebsiteDataStore\b/.test(body) && !allowedCookieFlush.has(name)) {
    errors.push(`Phase 5: WKWebsiteDataStore só para migração de cookies (${name}).`);
  }
}

const legacyImport = read("ios/App/App/LegacyWebStorageImporter.swift");
if (!legacyImport.includes("@MainActor") || !legacyImport.includes("Thread.isMainThread")) {
  errors.push("LegacyWebStorageImporter tem de ser @MainActor e exigir Thread.isMainThread.");
}
if (!legacyImport.includes("cita-settings") || !legacyImport.includes("verse2note-outbox")) {
  errors.push("LegacyWebStorageImporter tem de ler cita-settings e verse2note-outbox.");
}
if (!legacyImport.includes("NoteDocument") && !legacyImport.includes("LegacyNoteConverter")) {
  errors.push("LegacyWebStorageImporter tem de converter para NoteDocumentV1.");
}

const outbox = read("ios/App/App/NativeOutbox.swift");
if (!outbox.includes("enqueueNoteUpsert") || !outbox.includes("flushIfPossible") || !outbox.includes("nextAttemptAt")) {
  errors.push("NativeOutbox tem de ter enqueue + flush com backoff (nextAttemptAt).");
}

for (const dead of [
  "ios/App/App/NativeShell.swift",
  "ios/App/App/LiquidChrome.swift",
  "ios/App/App/NativeMenus.swift",
  "ios/App/App/NativePhase0Plugin.swift",
  "ios/App/App/NoteEditorSpikeViewController.swift",
  "ios/App/App/NoteMioloEditorView.swift",
]) {
  try {
    read(dead);
    errors.push(`Ficheiro Cap/WebView morto ainda presente: ${dead}`);
  } catch {
    /* expected missing */
  }
}

try {
  read("docs/ios-phase5-webview.md");
  read("docs/ios-phase7-native-editor.md");
  read("docs/note-document-v1.md");
} catch (e) {
  errors.push(`Falta doc Phase 5/7: ${e.message || e}`);
}

const material = read("ios/App/App/LiquidGlassMaterial.m");
if (!material.includes("UIGlassEffect") || !material.includes("UIBlurEffectStyleSystemChromeMaterial")) {
  errors.push("O material tem de ter UIGlassEffect e o desfoque clássico.");
}
if (!material.includes("__IPHONE_26_0") || !material.includes("prominentGlassButtonConfiguration")) {
  errors.push("Liquid Glass tem de compilar só com o SDK do iOS 26.");
}

const sessionBoot = read("ios/App/App/NativeSessionBootstrap.swift");
if (!sessionBoot.includes("@MainActor") || !sessionBoot.includes("Thread.isMainThread")) {
  errors.push("NativeSessionBootstrap tem de ser @MainActor e guardar Thread.isMainThread antes de WKWebsiteDataStore.");
}

const push = read("ios/App/App/NativePushService.swift");
if (!push.includes("UNUserNotificationCenter") || !push.includes("saveApnsDevice") || !push.includes("NativeDeepLinkRouter")) {
  errors.push("NativePushService tem de registar APNs e abrir href via NativeDeepLinkRouter.");
}

const deep = read("ios/App/App/NativeDeepLinkRouter.swift");
if (!deep.includes("destination(for") || !deep.includes("notebook") || !deep.includes("NoteDetailViewController")) {
  errors.push("NativeDeepLinkRouter tem de mapear paths para ecrãs nativos.");
}

const comingSoon = read("ios/App/App/ComingSoonTabViewController.swift");
if (comingSoon.includes("capacitorSite") || comingSoon.includes("Verse2NoteBridge") || comingSoon.includes("Usar app clássico")) {
  errors.push("ComingSoon não pode oferecer o host Capacitor.");
}

const design = read("ios/App/App/V2NDesign.swift");
if (!design.includes("static let accent") || !design.includes("static let canvas") || !design.includes("enum V2NChrome") || !design.includes("static func applyAppWide")) {
  errors.push("V2NDesign tem de expor accent/canvas e V2NChrome.applyAppWide.");
}
if (!design.includes("userInterfaceStyle == .dark")) {
  errors.push("V2NDesign tem de declarar cores com suporte a Dark Mode.");
}
const components = read("ios/App/App/V2NComponents.swift");
if (!components.includes("V2NEmptyStateView") || !components.includes("V2NNoteRowCell") || !components.includes("V2NHaptics")) {
  errors.push("V2NComponents tem de incluir empty state, note row e haptics.");
}
if (!appDelegate.includes("V2NChrome.applyAppWide")) {
  errors.push("AppDelegate tem de aplicar V2NChrome.applyAppWide no launch.");
}
const rootTabsChrome = read("ios/App/App/NativeRootTabBarController.swift");
if (!rootTabsChrome.includes("V2NDesign.accent") || !rootTabsChrome.includes("V2NChrome.style")) {
  errors.push("NativeRootTabBarController tem de usar o design system (accent + chrome).");
}
if (/Partilhar|Guardar|utilizador|Definições/.test(design) || /Partilhar|Guardar|utilizador|Definições/.test(components)) {
  errors.push("Design system: strings têm de ser pt-BR (não Partilhar/Guardar/utilizador/Definições).");
}

const signIn = read("ios/App/App/NativeSignInViewController.swift");
if (signIn.includes("Abrir site clássico") || signIn.includes("capacitorSite")) {
  errors.push("O login nativo não pode abrir o site clássico.");
}
if (!signIn.includes("Continuar com Google") || !signIn.includes("Entrar com email")) {
  errors.push("Falta o ecrã nativo de login (Google + email).");
}

const loginService = read("ios/App/App/NativeLoginService.swift");
if (!loginService.includes("ASWebAuthenticationSession") || !loginService.includes("auth/claim")) {
  errors.push("NativeLoginService tem de fazer Google via ASWebAuthenticationSession + claim.");
}
if (!loginService.includes("signOut") || !loginService.includes("deleteBearerToken")) {
  errors.push("Sign-out nativo tem de limpar o Keychain.");
}

const notebookList = read("ios/App/App/NotebookListViewController.swift");
if (notebookList.includes("Site clássico") || notebookList.includes("capacitorSite")) {
  errors.push("O Caderno não pode oferecer Site clássico (Cap).");
}
if (!notebookList.includes("UIActivityViewController") || !notebookList.includes("trailingSwipeActions")) {
  errors.push("A lista nativa tem de ter swipe e partilha nativa.");
}
if (!notebookList.includes("NativeSignInViewController") || !(notebookList.includes("Sair") || notebookList.includes("Terminar sessão"))) {
  errors.push("O Caderno tem de abrir o login nativo e permitir sair da sessão.");
}
if (/#selector\s*\(\s*presentSignIn\s*\)/.test(notebookList) || /func presentSignIn\s*\(\s*\)/.test(notebookList)) {
  errors.push("NotebookList: use presentSignInTapped + showSignIn(auto:) — não sobrecarregar presentSignIn.");
}
if (!notebookList.includes("presentSignInTapped") || !notebookList.includes("showSignIn(auto")) {
  errors.push("NotebookList tem de expor presentSignInTapped e showSignIn(auto:).");
}
if (!notebookList.includes("convenience init(group:") || !notebookList.includes("listGroupNotes")) {
  errors.push("O Caderno nativo tem de reutilizar a lista para notas de um grupo.");
}

const rootTabs = read("ios/App/App/NativeRootTabBarController.swift");
if (!rootTabs.includes("GroupsListViewController") || rootTabs.includes('titleText: "Grupos"')) {
  errors.push("Phase 2: o separador Grupos tem de usar GroupsListViewController.");
}
if (!rootTabs.includes("ProfileViewController") || rootTabs.includes('titleText: "Perfil"')) {
  errors.push("Phase 3: a aba Perfil tem de usar ProfileViewController.");
}
if (!rootTabs.includes("VersesHomeViewController") || rootTabs.includes('titleText: "Versículos"')) {
  errors.push("Phase 4: a aba Versículos tem de usar VersesHomeViewController.");
}
if (!rootTabs.includes("ReadingHomeViewController") || rootTabs.includes('titleText: "Leitura"')) {
  errors.push("A aba Leitura tem de usar ReadingHomeViewController (não ComingSoon).");
}
if (!project.includes("ReadingScreens.swift in Sources")) {
  errors.push("ReadingScreens.swift tem de estar no target Xcode.");
}

try {
  const groupsList = read("ios/App/App/GroupsListViewController.swift");
  if (!groupsList.includes("Novo grupo") || !groupsList.includes("listGroups")) {
    errors.push("GroupsListViewController tem de listar e criar grupos.");
  }
} catch {
  errors.push("Ficheiro Phase 2 em falta: GroupsListViewController.swift");
}
if (!project.includes("GroupsListViewController.swift in Sources")) {
  errors.push("GroupsListViewController tem de estar no target Xcode.");
}
if (!noteDetail.includes("Mover para grupo") || !noteDetail.includes("listGroupsForNote")) {
  errors.push("A nota ⋯ tem de permitir Mover para grupo.");
}

try {
  const versesHome = read("ios/App/App/VersesHomeViewController.swift");
  if (!versesHome.includes("Temas") || !versesHome.includes("fetchBibleBooks")) {
    errors.push("VersesHomeViewController tem de listar livros e abrir Temas.");
  }
  if (
    /pushViewController\(\s*ThemesHomeViewController/.test(versesHome) ||
    /pushViewController\(\s*MyCollectionsViewController/.test(versesHome)
  ) {
    errors.push("Chips Livros/Temas/Listas têm de trocar o conteúdo in-place (sem push).");
  }
  if (!versesHome.includes("applyBooksCompact") || !versesHome.includes("booksCompact")) {
    errors.push("Versículos tem de manter Siglas/Nomes sincronizados com booksCompact no primeiro load.");
  }
  const groupsListSync = read("ios/App/App/GroupsListViewController.swift");
  if (groupsListSync.includes("grupos · sincronizado")) {
    errors.push("Remova o banner persistente «grupos · sincronizado».");
  }
  const readingHome = read("ios/App/App/ReadingScreens.swift");
  if (!readingHome.includes("V2NPlanCategoryCardCell") || !readingHome.includes("UICollectionView")) {
    errors.push("Leitura home tem de usar cards (UICollectionView) como a web original.");
  }
  const versesScreens = read("ios/App/App/VersesScreens.swift");
  if (
    !versesScreens.includes("VerseActionsViewController") ||
    !versesScreens.includes("appendVerse") ||
    !versesScreens.includes("Adicionar à nota")
  ) {
    errors.push("Faltam telas nativas de ações de versículo / adicionar à nota.");
  }
  if (/Partilhar|Guardar|utilizador|Definições/.test(versesScreens) || /Partilhar|Guardar|utilizador|Definições/.test(versesHome)) {
    errors.push("Strings de Versículos têm de ser pt-BR (não Partilhar/Guardar/utilizador/Definições).");
  }
} catch {
  errors.push("Arquivo Phase 4 em falta: VersesHomeViewController.swift / VersesScreens.swift");
}
if (!project.includes("VersesHomeViewController.swift in Sources") || !project.includes("VersesScreens.swift in Sources")) {
  errors.push("VersesHomeViewController / VersesScreens têm de estar no target Xcode.");
}

try {
  const profile = read("ios/App/App/ProfileViewController.swift");
  if (!profile.includes("Sair da conta") || !(profile.includes("Apagar conta") || profile.includes("Excluir conta")) || !profile.includes("getMe")) {
    errors.push("ProfileViewController tem de mostrar perfil, sair da conta e excluir conta.");
  }
  const settings = read("ios/App/App/ProfileSettingsScreens.swift");
  if (
    !settings.includes("ProfileEditViewController") ||
    !settings.includes("ProfileThemeViewController") ||
    !settings.includes("ProfileNotifyViewController")
  ) {
    errors.push("Faltam telas nativas de editar perfil / aparência / avisos.");
  }
  if (!settings.includes("NativePushService")) {
    errors.push("Avisos tem de ativar push via NativePushService.");
  }
} catch {
  errors.push("Arquivo Phase 3 em falta: ProfileViewController.swift / ProfileSettingsScreens.swift");
}
if (!project.includes("ProfileViewController.swift in Sources") || !project.includes("ProfileSettingsScreens.swift in Sources")) {
  errors.push("ProfileViewController / ProfileSettingsScreens têm de estar no target Xcode.");
}

const authRouter = read("src/lib/native/api/v1-router.ts");
if (!authRouter.includes("auth-claim") || !authRouter.includes("auth-email") || !authRouter.includes("auth-apple")) {
  errors.push("Faltam rotas /api/native/v1/auth/* (claim/email/apple).");
}
if (!authRouter.includes("group-notes") || !authRouter.includes('"groups"')) {
  errors.push("Faltam rotas /api/native/v1/groups* no router nativo.");
}
if (!authRouter.includes('"me"') || !authRouter.includes("account-delete") || !authRouter.includes("notify-prefs")) {
  errors.push("Faltam rotas /api/native/v1/me|prefs|account* no router nativo.");
}
if (!authRouter.includes("bible-books") || !authRouter.includes("verses-append") || !authRouter.includes("my-collections")) {
  errors.push("Faltam rotas /api/native/v1/bible*|verses/append|my-collections no router nativo.");
}
if (!authRouter.includes("devices-apns")) {
  errors.push("Falta devices/apns no router nativo.");
}
if (!authRouter.includes("plans-mark") || !authRouter.includes("plans-start")) {
  errors.push("Faltam rotas /api/native/v1/plans* no router nativo.");
}

const apiClient = read("ios/App/App/NativeAPIClient.swift");
if (!apiClient.includes("func getMe(") || !apiClient.includes("func deleteAccount(")) {
  errors.push("NativeAPIClient tem de expor getMe e deleteAccount.");
}
if (!apiClient.includes("func fetchBibleBooks(") || !apiClient.includes("func appendVerse(")) {
  errors.push("NativeAPIClient tem de expor fetchBibleBooks e appendVerse.");
}
if (!apiClient.includes("func saveApnsDevice(") || !apiClient.includes("func dropApnsDevice(")) {
  errors.push("NativeAPIClient tem de expor saveApnsDevice / dropApnsDevice.");
}
if (!apiClient.includes("handleUnauthorized") || !apiClient.includes("nativeSessionDidExpire")) {
  errors.push("NativeAPIClient tem de limpar sessão em 401 (handleUnauthorized).");
}
if (!apiClient.includes("upsertMyCollection")) {
  errors.push("NativeAPIClient tem de expor upsertMyCollection para o import Phase 6.");
}
if (!apiClient.includes("checked")) {
  errors.push("NativeAPIClient.LineBlock tem de incluir checked (checklist NoteDocumentV1).");
}

const nativeV1Router = read("src/lib/native/api/v1-router.ts");
const noteDocument = read("src/lib/native/api/note-document.ts");
const migrationPlan = read("docs/ios-native-migration.md");
if (!nativeV1Router.includes("devices-apns") || !read("src/routes/api/native/v1/$.ts").includes("handleNativeV1Request")) {
  errors.push("Falta o router /api/native/v1.");
}
if (!noteDocument.includes("NOTE_DOCUMENT_SCHEMA_VERSION") || !noteDocument.includes("noteToDocument")) {
  errors.push("NoteDocumentV1 (schemaVersion + conversão legacy) é obrigatório.");
}
if (!noteDocument.includes('"check"') || !noteDocument.includes("strikethrough") || !noteDocument.includes("encodeDocumentStorage")) {
  errors.push("NoteDocumentV1 Phase 7: check/strikethrough/storage envelope obrigatórios.");
}
if (!migrationPlan.includes("Phase 7") || !migrationPlan.includes("NoteDocumentV1") || !migrationPlan.includes("Phase 5")) {
  errors.push("O plano tem de documentar Phase 5/7 e NoteDocumentV1.");
}

const handoff = read("src/lib/native/handoff.server.ts");
if (handoff.includes("session_token") || !handoff.includes("token_ciphertext")) {
  errors.push("O handoff não pode gravar o token de sessão em claro.");
}
const aasa = read("src/routes/[.]well-known/apple-app-site-association.ts");
if (!aasa.includes("appleAppSiteAssociation")) {
  errors.push("Falta servir apple-app-site-association.");
}
const aasaSource = read("src/lib/native/aasa.server.ts");
if (!aasaSource.includes("webcredentials")) {
  errors.push("O AASA tem de publicar webcredentials para o ASWebAuthenticationSession HTTPS.");
}

for (const path of [
  "ios/App/App.xcodeproj/xcshareddata/xcschemes/App.xcscheme",
  "docs/ios-native-migration.md",
  "docs/ios-phase5-webview.md",
  "docs/ios-phase7-native-editor.md",
  "docs/note-document-v1.md",
  "migrations/0021_note_blocks_backup.sql",
  "ios/App/App/NotebookListViewController.swift",
  "ios/App/App/NoteDetailViewController.swift",
  "ios/App/App/NativeNoteEditorView.swift",
  "ios/App/App/NoteDocumentCodec.swift",
  "ios/App/App/BibleRefInsertPicker.swift",
  "ios/App/App/AppRoot.swift",
  "ios/App/App/NativeSignInViewController.swift",
  "ios/App/App/NativeLoginService.swift",
  "ios/App/App/NativeSessionBootstrap.swift",
  "ios/App/App/NativePushService.swift",
  "ios/App/App/NativeDeepLinkRouter.swift",
  "ios/App/App/ProfileViewController.swift",
  "ios/App/App/ProfileSettingsScreens.swift",
  "ios/App/App/VersesHomeViewController.swift",
  "ios/App/App/VersesScreens.swift",
  "ios/App/App/ReadingScreens.swift",
  "src/lib/native/api/v1-profile.server.ts",
  "src/lib/native/api/v1-verses.server.ts",
  "src/lib/native/api/html-to-document.ts",
]) {
  try {
    read(path);
  } catch {
    errors.push(`Ficheiro em falta: ${path}`);
  }
}

for (const path of [
  "ios/App/App/Localizable.xcstrings",
  "ios/App/App/InfoPlist.xcstrings",
  "ios/App/App/AppLocale.swift",
  "scripts/check-ios-l10n.mjs",
]) {
  try {
    read(path);
  } catch {
    errors.push(`Ficheiro em falta: ${path}`);
  }
}

if (!project.includes("Localizable.xcstrings in Resources") || !project.includes("pt-BR")) {
  errors.push("Xcode project tem de incluir Localizable.xcstrings e knownRegions pt-BR/es.");
}
if (!project.includes("AppLocale.swift in Sources")) {
  errors.push("AppLocale.swift tem de estar no target Xcode.");
}

{
  const l10n = spawnSync(process.execPath, ["scripts/check-ios-l10n.mjs"], {
    cwd: root,
    encoding: "utf8",
  });
  if (l10n.status !== 0) {
    errors.push(((l10n.stdout || "") + (l10n.stderr || "")).trim() || "check-ios-l10n falhou");
  } else if (l10n.stdout) {
    notes.push(l10n.stdout.trim());
  }
}

if (notes.length) console.log(notes.join("\n"));
if (errors.length) {
  console.error(errors.join("\n"));
  process.exit(1);
}
console.log("ios-check: projeto iOS coerente (Phase 7 — editor nativo; sem Cap host / miolo WebView).");
