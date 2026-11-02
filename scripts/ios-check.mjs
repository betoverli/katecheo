#!/usr/bin/env node
/**
 * Checks the iOS shell without a Mac. The unsigned compile itself runs on the
 * macOS GitHub Actions runner (see .github/workflows/ios.yml).
 */
import { readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const root = join(dirname(fileURLToPath(import.meta.url)), "..");
const read = (path) => readFileSync(join(root, path), "utf8");

const errors = [];
const notes = [];

const config = read("capacitor.config.ts");
if (!config.includes("https://verse2note.com")) {
  errors.push("capacitor.config.ts deve carregar https://verse2note.com por omissão.");
}
if (config.includes("NSAllowsArbitraryLoads") || config.includes("capacitorHttp")) {
  errors.push("Não ligar HTTP livre nem o proxy CapacitorHttp.");
}
const splashPlugin = config.match(/SplashScreen:\s*\{([\s\S]*?)\n\s*\},/);
const splashBlock = splashPlugin?.[1] ?? "";
if (!splashBlock.includes("launchAutoHide: false")) {
  errors.push("SplashScreen tem de ficar visível até o hide() do shell (launchAutoHide: false).");
}
if (splashBlock.includes("backgroundColor:")) {
  errors.push("SplashScreen não pode fixar backgroundColor — sobrescreve o LaunchScreen claro/escuro.");
}

const launchScreen = read("ios/App/App/Base.lproj/LaunchScreen.storyboard");
if (!launchScreen.includes("SplashBrand") || !launchScreen.includes("SplashBackground")) {
  errors.push("LaunchScreen tem de centrar SplashBrand sobre SplashBackground (igual ao splash web).");
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
  errors.push("O Release tem de declarar o domínio verse2note.com para o regresso do login.");
}
if (!releaseEntitlements.includes("webcredentials:verse2note.com")) {
  errors.push("O Release tem de declarar webcredentials:verse2note.com, senão o iPhone não abre a folha de login.");
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

const nativeShellJs = read("src/lib/native/shell.ts");
if (!nativeShellJs.includes("SplashScreen.hide") || !nativeShellJs.includes("fadeOutDuration: 0")) {
  errors.push("O shell tem de esconder o SplashScreen nativo sem fade assim que a web pinta.");
}

const shell = read("ios/App/App/NativeShell.swift");
if (!shell.includes('path: "/auth/native-return"') || !shell.includes("Callback.https")) {
  errors.push("O login nativo tem de poder regressar por Universal Link.");
}
if (!shell.includes("Verse2NoteBridgeViewController")) {
  errors.push("O controlador da ponte tem de registrar o plugin de login.");
}
if (!shell.includes("registerPluginInstance(LiquidChromePlugin())") || !shell.includes("liquidChrome.attach")) {
  errors.push("O controlador tem de montar o chrome nativo e registrar o plugin LiquidChrome.");
}
const liquid = read("ios/App/App/LiquidChrome.swift");
if (!liquid.includes("UITabBar") || !liquid.includes("UINavigationBar") || !liquid.includes("UISearchBar")) {
  errors.push("O chrome nativo tem de usar UITabBar, UINavigationBar e UISearchBar.");
}
if (!liquid.includes("bounces") && !shell.includes("scroll.bounces = false")) {
  errors.push("O chrome nativo não pode voltar a ligar o bounce da WKWebView.");
}
const material = read("ios/App/App/LiquidGlassMaterial.m");
if (!material.includes("UIGlassEffect") || !material.includes("UIBlurEffectStyleSystemChromeMaterial")) {
  errors.push("O material tem de ter UIGlassEffect e o desfoque clássico.");
}
if (!material.includes("__IPHONE_26_0") || !material.includes("prominentGlassButtonConfiguration")) {
  errors.push("Liquid Glass tem de compilar só com o SDK do iOS 26, com botão de vidro no FAB.");
}
if (!project.includes("LiquidChrome.swift in Sources") || !project.includes("LiquidGlassMaterial.m in Sources")) {
  errors.push("O projeto Xcode não compila o chrome nativo.");
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
  errors.push(
    "O fluxo não pode fixar o Xcode 26.0/26.1: a imagem traz a app sem essa plataforma e o xcodebuild sai 70.",
  );
}
const selector = read("scripts/select-xcode.mjs");
if (!selector.includes("export function chooseXcode") || !selector.includes("sdk.major < 26")) {
  errors.push("O selector de Xcode tem de exigir o SDK do iOS 26 com runtime de simulador instalado.");
}
const scene = read("ios/App/App/SceneDelegate.swift");
// Phase 1: root is AppRoot (hybrid native Caderno by default). Capacitor bridge
// remains for login modal + classic fallback, not as the cold-start root.
if (!scene.includes("AppRoot.makeRootViewController") && !scene.includes("Verse2NoteBridgeViewController()")) {
  errors.push("O SceneDelegate tem de montar a root via AppRoot (ou Cap bridge).");
}
if (!read("ios/App/App/AppRoot.swift").includes("Verse2NoteBridgeViewController")) {
  errors.push("AppRoot tem de conseguir montar o Cap bridge (fallback capacitorSite).");
}
const mainStoryboard = read("ios/App/App/Base.lproj/Main.storyboard");
if (!mainStoryboard.includes('customClass="Verse2NoteBridgeViewController"')) {
  errors.push("Main.storyboard tem de apontar para Verse2NoteBridgeViewController (plugins locais).");
}
if (mainStoryboard.includes('customClass="CAPBridgeViewController"')) {
  errors.push("Main.storyboard não pode ficar no CAPBridgeViewController genérico.");
}
const nativeMenus = read("ios/App/App/NativeMenus.swift");
if (!nativeMenus.includes("button.performPrimaryAction()") || /\bsendActions\s*\(/.test(nativeMenus)) {
  errors.push("NativeMenus tem de abrir o UIMenu com performPrimaryAction (sendActions não apresenta o menu).");
}
if (!shell.includes("registerPluginInstance(NativeMenusPlugin())")) {
  errors.push("NativeMenusPlugin tem de ser registrado em capacitorDidLoad.");
}
const liquidChrome = read("ios/App/App/LiquidChrome.swift");
if (!liquidChrome.includes("applyFabMenu") || !liquidChrome.includes("fabMenuSelect")) {
  errors.push("O FAB Liquid Glass tem de hospedar UIMenu (applyFabMenu / fabMenuSelect).");
}
if (!liquidChrome.includes("applyTrailingMenu") || !liquidChrome.includes("trailingMenuSelect")) {
  errors.push("O botão … do chrome Liquid Glass tem de hospedar UIMenu (applyTrailingMenu / trailingMenuSelect).");
}
if (!nativeMenus.includes("alpha = 0.01") || !nativeMenus.includes("0.40")) {
  errors.push("NativeMenus tem de usar âncora alpha 0.01 e fallback UIAlertController em ~400ms.");
}
if (!nativeMenus.includes("ObjectIdentifier") || !nativeMenus.includes("dismiss ignored stale")) {
  errors.push("NativeMenus.dismiss tem de ignorar dismiss obsoleto (race do primeiro speaker / remover).");
}
if (!nativeMenus.includes("topPresenter") || !nativeMenus.includes("preparePresenter") || !nativeMenus.includes("replaceActiveCall")) {
  errors.push("NativeMenus tem de apresentar no VC do topo sem race dismiss→present animado.");
}
if (!nativeMenus.includes('notifyListeners("presented"') && !nativeMenus.includes("notifyListeners(\"presented\"")) {
  errors.push("NativeMenus tem de emitir o evento presented para o watchdog JS.");
}
const menusTs = read("src/lib/native/menus.ts");
if (!menusTs.includes("PRESENTATION_CONFIRM_MS") || !menusTs.includes("presented")) {
  errors.push("O wrapper NativeMenus tem de falhar rápido (~600ms) sem apresentação e cair no web.");
}
if (/listener\s*=\s*await\s+plugin\.addListener/.test(menusTs)) {
  errors.push("menus.ts não pode await addListener antes de present (TF85: pending eterno).");
}
if (!menusTs.includes("classifyPresentOutcome") || !menusTs.includes("FORCE_WEB_FALLBACK_MS")) {
  errors.push("menus.ts tem de classificar cancel fantasma e expor FORCE_WEB_FALLBACK_MS.");
}
if (!nativeMenus.includes("itemObjects") || !nativeMenus.includes('getArray("items")')) {
  errors.push("NativeMenus tem de coerir items via itemObjects(getArray(\"items\")).");
}
if (/call\.getArray\("items",\s*JSObject\.self\)/.test(nativeMenus)) {
  errors.push("NativeMenus não pode usar getArray tipado para items (cast silencioso → sheet vazio).");
}
const noteEditor = read("src/components/notebook-editor.tsx");
if (noteEditor.includes("nativeBar={false}") || noteEditor.includes("presentNativeMenu")) {
  errors.push("O … da nota tem de usar trailingMenu no chrome nativo, não NativeMenus.present / nativeBar={false}.");
}
if (!noteEditor.includes('nativeSymbol={readOnly ? undefined : "ellipsis"}') || !noteEditor.includes("trailingMenu=")) {
  errors.push("O editor da nota tem de enviar ellipsis + trailingMenu ao chrome Liquid Glass.");
}
if (/title=\{draft\.title/.test(noteEditor) || !noteEditor.includes('title=""')) {
  errors.push("O título da nota tem de aparecer só no corpo (Apple Notes), não na top bar nativa/web.");
}
if (!noteEditor.includes("note-whole-speaker") || !noteEditor.includes("pickNoteSpeaker")) {
  errors.push("A nota com speaker ao nível da nota tem de mostrar o chip removível/trocável no corpo.");
}
const viewportSheet = read("src/components/viewport-sheet.tsx");
if (!viewportSheet.includes("settledRef") || !viewportSheet.includes("presented.map")) {
  errors.push("ActionSheet tem de aplicar onSelect mesmo após remount (settledRef + snapshot).");
}
if (!viewportSheet.includes("result.failed") || !viewportSheet.includes('setMode("web")')) {
  errors.push("ActionSheet tem de cair no sheet web quando o native falha.");
}
const noteSettings = read("src/lib/native/note-settings.ts");
if (!noteSettings.includes('type: "web-fallback"') || noteSettings.includes("presentNativeMenu")) {
  errors.push("note-settings tem de abrir o sheet web (sem NativeMenus.present após o …).");
}
if (!noteEditor.includes("openNoteSettings") || !noteEditor.includes("setMetaSheet(true)")) {
  errors.push("O editor tem de abrir metaSheet no tap de Settings (nunca ignorar o tap).");
}
if (/if \(action\.type === "cancelled"\) return/.test(noteEditor)) {
  errors.push("Settings não pode engolir cancelled sem abrir o sheet web.");
}
const newGroup = read("src/lib/native/new-group.ts");
const groupsHome = read("src/components/notebook-groups-home.tsx");
if (!newGroup.includes('type: "web-fallback"') || newGroup.includes("presentNativePrompt")) {
  errors.push("new-group tem de abrir o sheet web (sem presentNativePrompt silencioso).");
}
if (!groupsHome.includes("setCreate(true)") || /if \(result\.type === "cancelled"\) return/.test(groupsHome)) {
  errors.push("Novo grupo tem de abrir o ViewportSheet; cancelled não pode ser no-op.");
}
if (!nativeMenus.includes("presentingViewController") || nativeMenus.includes("Notify ASAP")) {
  errors.push("NativeMenus só pode emitir presented depois do present completar com sucesso.");
}
if (!viewportSheet.includes("FORCE_WEB_FALLBACK_MS") || !viewportSheet.includes("force web fallback")) {
  errors.push("ActionSheet tem de forçar o sheet web se o native ficar em pending.");
}
const stylesCss = read("src/styles.css");
if (!/html\.native-ios main\.screen > \.screen-body[\s\S]*?touch-action:\s*pan-x pan-y/.test(stylesCss)) {
  errors.push("screen-body nativo tem de permitir pan-x (senão o swipe-to-delete morre por interseção CSS).");
}
const notebookTs = read("src/lib/notebook.ts");
if (!notebookTs.includes("noteIncludesSpeaker") || !notebookTs.includes("note.speakerId === speakerId")) {
  errors.push("O filtro de speakers tem de incluir o speaker ao nível da nota.");
}
const offlineBanner = read("src/components/offline-banner.tsx");
if (!offlineBanner.includes("offlineBanner") || !offlineBanner.includes("subscribeOnlineStatus")) {
  errors.push("O indicador offline tem de usar subscribeOnlineStatus (não navigator.onLine directo).");
}
if (!offlineBanner.includes("--native-top-inset")) {
  errors.push("O banner offline não pode cobrir a top bar nativa (usar --native-top-inset).");
}
const onlineStatus = read("src/lib/online-status.ts");
if (!onlineStatus.includes("/robots.txt") || onlineStatus.includes("/api/auth")) {
  errors.push("O probe offline tem de usar um asset estático, nunca /api/auth.");
}
const swSource = read("public/sw.js");
if (!/verse2note-v1[6-9]|verse2note-v[2-9]\d/.test(swSource)) {
  errors.push("O service worker tem de cachear o app shell (v16+) incluindo /assets.");
}
if (!swSource.includes("networkFirst") || !swSource.includes("PRECACHE_URLS")) {
  errors.push("O service worker tem de ter network-first com timeout e PRECACHE_URLS para offline.");
}
if (!read("ios/App/App/NativeMenus.swift").includes('style == "prompt"') || !read("ios/App/App/NativeMenus.swift").includes("addTextField")) {
  errors.push("NativeMenus tem de expor alert/prompt (UIAlertController com text field).");
}
if (noteEditor.includes("dropSpeaker") || noteEditor.includes("confirmDropSpeaker")) {
  errors.push("Remover speaker de secção tem de ser imediato (sem ActionSheet de confirmação).");
}
if (!read("src/components/notebook-doc.tsx").includes("onPointerDownCapture")) {
  errors.push("O × da secção tem de usar pointerdown em capture (alvo Text node no iOS).");
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
const nativeAuth = read("src/lib/native/auth.ts");
if (!nativeAuth.includes("preferredNativeReturnMode")) {
  errors.push("O login nativo tem de pedir o esquema já registado no binário.");
}
const nativeConfig = read("src/routes/auth/native-config.ts");
if (!nativeConfig.includes("universalLinks: false")) {
  errors.push("native-config tem de dizer universalLinks false para o script já publicado pedir verse2note://.");
}
const done = read("src/routes/auth/native-done.ts");
if (done.includes("useEffect") || done.includes("window.location") || done.includes("Response.redirect(")) {
  errors.push("O regresso /auth/native-done tem de ser um 302 do servidor. Response.redirect recusa verse2note://.");
}
if (!done.includes("nativeDoneLocation") || !done.includes("status: 302")) {
  errors.push("O regresso /auth/native-done tem de redirecionar para o código de uso único.");
}

// Phase 0 — native JSON API + Keychain + flag (default Capacitor UI).
const nativeV1Router = read("src/lib/native/api/v1-router.ts");
const noteDocument = read("src/lib/native/api/note-document.ts");
const migrationPlan = read("docs/ios-native-migration.md");
if (!nativeV1Router.includes("devices-apns") || !read("src/routes/api/native/v1/$.ts").includes("handleNativeV1Request")) {
  errors.push("Falta o router /api/native/v1 (Phase 0).");
}
if (!noteDocument.includes("NOTE_DOCUMENT_SCHEMA_VERSION") || !noteDocument.includes("noteToDocument")) {
  errors.push("NoteDocumentV1 (schemaVersion + conversão legacy) é obrigatório no Phase 0.");
}
if (!migrationPlan.includes("Phase 7") || !migrationPlan.includes("NoteDocumentV1")) {
  errors.push("O plano tem de documentar Phase 7 (editor nativo final) e NoteDocumentV1.");
}
if (!shell.includes("registerPluginInstance(NativePhase0Plugin())")) {
  errors.push("NativePhase0Plugin tem de ser registrado no bridge.");
}
if (!project.includes("KeychainStore.swift in Sources") || !project.includes("NativePhase0Plugin.swift in Sources")) {
  errors.push("KeychainStore / NativePhase0 têm de estar no target Xcode.");
}
const shellMode = read("ios/App/App/NativeShellMode.swift");
if (!shellMode.includes("capacitorSite") || !shellMode.includes("hybrid")) {
  errors.push("NativeShellMode tem de expor capacitorSite (fallback) e hybrid.");
}
if (!shellMode.includes("return .hybrid")) {
  errors.push("Phase 1: NativeShellMode tem de defaultar para hybrid (caderno nativo).");
}
if (!scene.includes("AppRoot.makeRootViewController")) {
  errors.push("SceneDelegate tem de montar a root via AppRoot (Phase 1).");
}
for (const file of [
  "ios/App/App/NotebookListViewController.swift",
  "ios/App/App/NoteDetailViewController.swift",
  "ios/App/App/NoteSettingsViewController.swift",
  "ios/App/App/NativeRootTabBarController.swift",
  "ios/App/App/LocalNoteCache.swift",
  "ios/App/App/AppRoot.swift",
]) {
  try {
    const body = read(file);
    if (body.length < 80) errors.push(`${file} parece vazio.`);
  } catch {
    errors.push(`Ficheiro Phase 1 em falta: ${file}`);
  }
}
if (!project.includes("NotebookListViewController.swift in Sources")) {
  errors.push("NotebookListViewController tem de estar no target Xcode.");
}
const notebookList = read("ios/App/App/NotebookListViewController.swift");
if (!notebookList.includes("Site clássico") || !notebookList.includes("capacitorSite")) {
  errors.push("Tem de haver um fallback oculto para o UI Capacitor clássico.");
}
if (!notebookList.includes("UIActivityViewController") || !notebookList.includes("trailingSwipeActions")) {
  errors.push("A lista nativa tem de ter swipe e partilha nativa.");
}

// Native login (Keychain bearer) — required after Phase 1 Caderno default.
const loginService = read("ios/App/App/NativeLoginService.swift");
const signInVc = read("ios/App/App/NativeSignInViewController.swift");
const sessionBoot = read("ios/App/App/NativeSessionBootstrap.swift");
if (!loginService.includes("ASWebAuthenticationSession") || !loginService.includes("auth/claim")) {
  errors.push("NativeLoginService tem de fazer Google via ASWebAuthenticationSession + claim.");
}
if (!loginService.includes("signOut") || !loginService.includes("deleteBearerToken")) {
  errors.push("Sign-out nativo tem de limpar o Keychain.");
}
if (!signInVc.includes("Continuar com Google") || !signInVc.includes("Entrar com email")) {
  errors.push("Falta o ecrã nativo de login (Google + email).");
}
if (!sessionBoot.includes("__Host-grok-auth.session_token") || !sessionBoot.includes("migrateCookieToKeychainIfNeeded")) {
  errors.push("Tem de migrar o cookie Cap → bearer no Keychain.");
}
// Build 104: WKWebsiteDataStore init off-main → WTFCrashWithInfo. Keep migration MainActor-bound.
if (!sessionBoot.includes("@MainActor") || !sessionBoot.includes("Thread.isMainThread")) {
  errors.push("NativeSessionBootstrap tem de ser @MainActor e guardar Thread.isMainThread antes de WKWebsiteDataStore.");
}
if (!notebookList.includes("NativeSignInViewController") || !notebookList.includes("Terminar sessão")) {
  errors.push("O Caderno tem de abrir o login nativo e permitir terminar sessão.");
}
// Overloading presentSignIn() + presentSignIn(auto:) makes #selector(presentSignIn) ambiguous (Xcode).
if (/#selector\s*\(\s*presentSignIn\s*\)/.test(notebookList) || /func presentSignIn\s*\(\s*\)/.test(notebookList)) {
  errors.push("NotebookList: use presentSignInTapped + showSignIn(auto:) — não sobrecarregar presentSignIn (erro Swift).");
}
if (!notebookList.includes("presentSignInTapped") || !notebookList.includes("showSignIn(auto")) {
  errors.push("NotebookList tem de expor presentSignInTapped e showSignIn(auto:).");
}
const authRouter = read("src/lib/native/api/v1-router.ts");
if (!authRouter.includes("auth-claim") || !authRouter.includes("auth-email") || !authRouter.includes("auth-apple")) {
  errors.push("Faltam rotas /api/native/v1/auth/* (claim/email/apple).");
}
const ents = read("ios/App/App/AppRelease.entitlements");
if (!ents.includes("com.apple.developer.applesignin")) {
  errors.push("AppRelease.entitlements tem de incluir Sign in with Apple.");
}
if (!project.includes("NativeSignInViewController.swift in Sources") || !project.includes("NativeLoginService.swift in Sources")) {
  errors.push("Login nativo tem de estar no target Xcode.");
}

// Phase 2: native Grupos tab (not Coming Soon).
const rootTabs = read("ios/App/App/NativeRootTabBarController.swift");
if (!rootTabs.includes("GroupsListViewController") || rootTabs.includes('titleText: "Grupos"')) {
  errors.push("Phase 2: o separador Grupos tem de usar GroupsListViewController (não Em breve).");
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
if (!notebookList.includes("convenience init(group:") || !notebookList.includes("listGroupNotes")) {
  errors.push("O Caderno nativo tem de reutilizar a lista para notas de um grupo.");
}
const noteDetail = read("ios/App/App/NoteDetailViewController.swift");
if (!noteDetail.includes("Mover para grupo") || !noteDetail.includes("listGroupsForNote")) {
  errors.push("A nota ⋯ tem de permitir Mover para grupo.");
}
if (!authRouter.includes("group-notes") || !authRouter.includes('"groups"')) {
  errors.push("Faltam rotas /api/native/v1/groups* no router nativo.");
}

for (const path of [
  "ios/App/App/NativeShell.swift",
  "ios/App/App.xcodeproj/xcshareddata/xcschemes/App.xcscheme",
  "ios/App/CapApp-SPM/Package.swift",
  "native/www/offline.html",
  ".github/workflows/ios.yml",
  "docs/ios-native-migration.md",
  "src/routes/native-editor.tsx",
  "src/routes/native-phase0.tsx",
  "ios/App/App/NotebookListViewController.swift",
  "ios/App/App/NoteDetailViewController.swift",
  "ios/App/App/AppRoot.swift",
  "ios/App/App/NativeSignInViewController.swift",
  "ios/App/App/NativeLoginService.swift",
  "ios/App/App/NativeSessionBootstrap.swift",
]) {
  try {
    read(path);
  } catch {
    errors.push(`Ficheiro em falta: ${path}`);
  }
}

const serverUrl = process.env.CAPACITOR_SERVER_URL?.trim();
if (serverUrl?.startsWith("http://")) {
  notes.push(
    `CAPACITOR_SERVER_URL=${serverUrl} é HTTP. A Apple bloqueia HTTP (ATS) e o cookie __Host- da sessão exige HTTPS. Use https://verse2note.com.`,
  );
}

if (notes.length) console.log(notes.join("\n"));
if (errors.length) {
  console.error(errors.join("\n"));
  process.exit(1);
}
console.log("ios-check: projeto iOS coerente (compilação no runner macOS).");
