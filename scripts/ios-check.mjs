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

const launchScreen = read("ios/App/Katecheo/Base.lproj/LaunchScreen.storyboard");
if (!launchScreen.includes("SplashBrand") || !launchScreen.includes("SplashBackground")) {
  errors.push("LaunchScreen tem de centrar SplashBrand sobre SplashBackground.");
}
if (launchScreen.includes("scaleAspectFill") || launchScreen.includes('image="Splash"')) {
  errors.push("LaunchScreen não pode voltar ao Splash em ecrã inteiro.");
}
if (/Verse2Note|Verse 2 Note|VERSE2NOTE/.test(launchScreen)) {
  errors.push("LaunchScreen.storyboard não pode conter o wordmark Verse2Note.");
}
for (const asset of [
  "ios/App/Katecheo/Assets.xcassets/SplashBrand.imageset/Contents.json",
  "ios/App/Katecheo/Assets.xcassets/SplashBackground.colorset/Contents.json",
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

// Katecheo splash: asset filenames + LaunchScreen must not keep Verse2Note wordmarks.
{
  const assetsRoot = join(root, "ios/App/Katecheo/Assets.xcassets");
  /** @type {string[]} */
  const badNames = [];
  const walkAssets = (dir) => {
    let entries;
    try {
      entries = readdirSync(dir, { withFileTypes: true });
    } catch {
      return;
    }
    for (const ent of entries) {
      const full = join(dir, ent.name);
      if (/verse2note|verse.?2.?note/i.test(ent.name)) {
        badNames.push(full.slice(root.length + 1));
      }
      if (ent.isDirectory()) walkAssets(full);
    }
  };
  walkAssets(assetsRoot);
  if (badNames.length) {
    errors.push(
      "Assets.xcassets: nomes com verse2note / Verse2Note proibidos (wordmark antigo). Hits: " +
        badNames.join(", "),
    );
  }
  const brandFiles = [
    "splash-brand-light.png",
    "splash-brand-light@2x.png",
    "splash-brand-light@3x.png",
    "splash-brand-dark.png",
    "splash-brand-dark@2x.png",
    "splash-brand-dark@3x.png",
  ];
  for (const name of brandFiles) {
    const rel = `ios/App/Katecheo/Assets.xcassets/SplashBrand.imageset/${name}`;
    try {
      const st = statSync(join(root, rel));
      if (!st.isFile() || st.size < 500) {
        errors.push(`${rel} em falta ou demasiado pequeno (regenerar com scripts/generate-splash-brand.mjs).`);
      }
    } catch {
      errors.push(`Falta ${rel} — rode scripts/generate-splash-brand.mjs.`);
    }
  }
  try {
    read("scripts/generate-splash-brand.mjs");
  } catch {
    errors.push("Falta scripts/generate-splash-brand.mjs (fonte do wordmark Katecheo na splash).");
  }
  const markFiles = [
    "brand-mark-light.png",
    "brand-mark-light@2x.png",
    "brand-mark-light@3x.png",
    "brand-mark-dark.png",
    "brand-mark-dark@2x.png",
    "brand-mark-dark@3x.png",
  ];
  for (const name of markFiles) {
    const rel = `ios/App/Katecheo/Assets.xcassets/BrandMark.imageset/${name}`;
    try {
      const st = statSync(join(root, rel));
      if (!st.isFile() || st.size < 500) {
        errors.push(`${rel} em falta ou demasiado pequeno (regenerar com scripts/generate-brand-mark.mjs).`);
      }
    } catch {
      errors.push(`Falta ${rel} — rode scripts/generate-brand-mark.mjs.`);
    }
  }
  try {
    const brandMarkContents = read("ios/App/Katecheo/Assets.xcassets/BrandMark.imageset/Contents.json");
    if (!brandMarkContents.includes('"value" : "dark"') && !brandMarkContents.includes('"value": "dark"')) {
      errors.push("BrandMark.imageset/Contents.json tem de declarar a variante dark.");
    }
  } catch {
    errors.push("Falta ios/App/Katecheo/Assets.xcassets/BrandMark.imageset/Contents.json");
  }
  try {
    read("scripts/generate-brand-mark.mjs");
  } catch {
    errors.push("Falta scripts/generate-brand-mark.mjs (logo Katecheo in-app).");
  }
  // Capacitor placeholder www (not the product UI, but still user-visible if opened).
  // Match the product wordmark only — not hostnames like verse2note.com.
  const wordmarkNeedle = /Verse2Note|Verse 2 Note|VERSE2NOTE/;
  for (const rel of ["native/www/index.html", "native/www/offline.html"]) {
    try {
      const html = read(rel);
      if (wordmarkNeedle.test(html)) {
        errors.push(`${rel}: substitua o wordmark Verse2Note por Katecheo.`);
      }
    } catch {
      /* optional */
    }
  }
  if (!read("capacitor.config.ts").includes('appName: "Katecheo"')) {
    errors.push('capacitor.config.ts appName tem de ser "Katecheo".');
  }
  // Katecheo must be one uniform word — ban Kate/cheo dual-style splits.
  try {
    const wordmark = read("src/components/wordmark.tsx");
    if (
      /["'`]Kate["'`]/.test(wordmark) ||
      /["'`]cheo["'`]/.test(wordmark) ||
      /(?<![\w-])italic(?![\w-])/.test(wordmark) ||
      wordmark.includes(">Kate<") ||
      wordmark.includes(">cheo<")
    ) {
      errors.push(
        "src/components/wordmark.tsx: Katecheo tem de ser uma só palavra em estilo uniforme (sem Kate/cheo nem italic).",
      );
    }
    if (!/\bKatecheo\b/.test(wordmark)) {
      errors.push('src/components/wordmark.tsx tem de renderizar "Katecheo" completo.');
    }
  } catch {
    errors.push("Falta src/components/wordmark.tsx");
  }
  try {
    const splashGen = read("scripts/generate-splash-brand.mjs");
    if (
      splashGen.includes('"Kate"') ||
      splashGen.includes('"cheo"') ||
      splashGen.includes("NotoSerifDisplay-Italic") ||
      /kate,\s*cheo\s*=/.test(splashGen)
    ) {
      errors.push(
        "scripts/generate-splash-brand.mjs: wordmark da splash tem de ser Katecheo inteiro (sem Kate/cheo nem italic).",
      );
    }
    if (!splashGen.includes('"Katecheo"') && !splashGen.includes("'Katecheo'")) {
      errors.push('scripts/generate-splash-brand.mjs tem de desenhar "Katecheo" completo.');
    }
  } catch {
    errors.push("Falta scripts/generate-splash-brand.mjs");
  }
}

const plist = read("ios/App/Katecheo/Info.plist");
if (!plist.includes("<string>katecheo</string>")) {
  errors.push("Falta o esquema verse2note no Info.plist.");
}
if (plist.includes("<key>NSAllowsArbitraryLoads</key>") || plist.includes("<key>NSExceptionAllowsInsecureHTTPLoads</key>")) {
  errors.push("Info.plist não deve abrir exceção de ATS. O site já é HTTPS.");
}
if (!plist.includes("remote-notification")) {
  errors.push("Falta UIBackgroundModes remote-notification.");
}
if (!plist.includes("KatecheoUniversalLinks")) {
  errors.push("Falta a flag KatecheoUniversalLinks no Info.plist.");
}

const releaseEntitlements = read("ios/App/Katecheo/AppRelease.entitlements");
if (!releaseEntitlements.includes("<string>production</string>")) {
  errors.push("O arquivo de Release tem de pedir APNs de produção (TestFlight).");
}
if (!releaseEntitlements.includes("applinks:katecheo.app")) {
  errors.push("O Release tem de declarar applinks:katecheo.app para Universal Links.");
}
if (!releaseEntitlements.includes("webcredentials:katecheo.app")) {
  errors.push("O Release tem de declarar webcredentials:katecheo.app (ASWebAuthenticationSession).");
}
if (releaseEntitlements.includes("applinks:verse2note.com") || releaseEntitlements.includes("webcredentials:verse2note.com")) {
  errors.push("Associated Domains: remova verse2note.com — só katecheo.app.");
}
if (!releaseEntitlements.includes("com.apple.developer.applesignin")) {
  errors.push("AppRelease.entitlements tem de incluir Sign in with Apple.");
}

const project = read("ios/App/Katecheo.xcodeproj/project.pbxproj");
if (project.includes("CODE_SIGN_ENTITLEMENTS = Katecheo/AppDebug")) {
  errors.push("A configuração Debug não deve exigir entitlements, para o build sem assinatura passar.");
}
if (!project.includes("CODE_SIGN_ENTITLEMENTS = Katecheo/AppRelease.entitlements")) {
  errors.push("Falta o entitlement de push na configuração Release.");
}
const debugTarget = project.split("504EC3171FED79650016851F /* Debug */")[1]?.split("name = Debug;")[0] ?? "";
const releaseTarget = project.split("504EC3181FED79650016851F /* Release */")[1]?.split("name = Release;")[0] ?? "";
if (debugTarget.includes("CODE_SIGN_ENTITLEMENTS") || !debugTarget.includes("KATECHEO_UNIVERSAL_LINKS = NO")) {
  errors.push("A configuração Debug não deve pedir Universal Links nem entitlements.");
}
if (!releaseTarget.includes("KATECHEO_UNIVERSAL_LINKS = YES") || !releaseTarget.includes("Katecheo/AppRelease.entitlements")) {
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
if (!project.includes("KCDesign.swift in Sources") || !project.includes("KCComponents.swift in Sources")) {
  errors.push("KCDesign / KCComponents (design system) têm de estar no target Xcode.");
}
if (!project.includes("BibleRefInsertPicker.swift in Sources")) {
  errors.push("BibleRefInsertPicker tem de estar no target Xcode.");
}
if (!project.includes("NativePushService.swift in Sources") || !project.includes("NativeDeepLinkRouter.swift in Sources")) {
  errors.push("NativePushService / NativeDeepLinkRouter têm de estar no target Xcode.");
}
if (!project.includes("DeviceIdStore.swift in Sources")) {
  errors.push("DeviceIdStore tem de estar no target Xcode.");
}
if (!project.includes("LiquidGlassMaterial.m in Sources")) {
  errors.push("LiquidGlassMaterial tem de permanecer no target (vidro nativo).");
}
if (!project.includes('SWIFT_OBJC_BRIDGING_HEADER = "Katecheo/App-Bridging-Header.h"')) {
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

const scene = read("ios/App/Katecheo/SceneDelegate.swift");
if (!scene.includes("AppRoot.makeRootViewController")) {
  errors.push("SceneDelegate tem de montar a root via AppRoot.");
}
if (scene.includes("import Capacitor") || scene.includes("SceneDelegateProxy") || scene.includes("KatecheoBridge")) {
  errors.push("SceneDelegate não pode importar Capacitor nem montar o bridge Cap.");
}
if (!scene.includes("NativeDeepLinkRouter") || !scene.includes("NSUserActivityTypeBrowsingWeb")) {
  errors.push("SceneDelegate tem de encaminhar Universal Links para NativeDeepLinkRouter.");
}
if (!scene.includes("AppAppearance") || scene.includes("overrideUserInterfaceStyle = .unspecified")) {
  errors.push("SceneDelegate tem de aplicar AppAppearance no connect (não forçar .unspecified) — TF219.");
}
try {
  const appearance = read("ios/App/Katecheo/AppAppearance.swift");
  if (!appearance.includes("overrideUserInterfaceStyle") || !appearance.includes("storedTheme") || !appearance.includes("syncFromCacheAndApply")) {
    errors.push("AppAppearance tem de persistir o tema e pintar todos os UIWindow (TF219).");
  }
} catch {
  errors.push("Falta AppAppearance.swift (TF219).");
}
if (!project.includes("AppAppearance.swift in Sources")) {
  errors.push("AppAppearance.swift tem de estar no target Xcode.");
}

const appRoot = read("ios/App/Katecheo/AppRoot.swift");
if (!appRoot.includes("NativeRootTabBarController") || appRoot.includes("KatecheoBridge") || appRoot.includes("capacitorSite")) {
  errors.push("AppRoot tem de montar NativeRootTabBarController (sem Cap).");
}
if (!appRoot.includes("OnboardingViewController") || !appRoot.includes("OnboardingStore")) {
  errors.push("AppRoot tem de mostrar OnboardingViewController na primeira abertura (antes do auth).");
}
if (!appRoot.includes("applyMainShell") || !appRoot.includes("makeMainShell")) {
  errors.push("AppRoot tem de trocar para o shell principal depois do onboarding (applyMainShell).");
}

const onboardingStore = read("ios/App/Katecheo/OnboardingStore.swift");
if (!onboardingStore.includes("katecheo.hasSeenOnboarding") || !onboardingStore.includes("UserDefaults")) {
  errors.push("OnboardingStore tem de persistir hasSeen com chave katecheo.* em UserDefaults.");
}
if (!onboardingStore.includes("-katecheoSkipOnboarding")) {
  errors.push("OnboardingStore tem de aceitar -katecheoSkipOnboarding para testes existentes.");
}

const onboardingVC = read("ios/App/Katecheo/OnboardingViewController.swift");
if (!onboardingVC.includes("Pular") || !onboardingVC.includes("Começar")) {
  errors.push("OnboardingViewController tem de ter Pular e Começar.");
}
if (!onboardingVC.includes("isPagingEnabled") || !onboardingVC.includes("UIPageControl")) {
  errors.push("OnboardingViewController tem de ser swipeable com page dots.");
}
if (!onboardingVC.includes('String(localized: "Katecheo")') || /["'`]Kate["'`]/.test(onboardingVC) || /["'`]cheo["'`]/.test(onboardingVC)) {
  errors.push('Onboarding: "Katecheo" tem de ser uma só palavra em estilo uniforme.');
}
if (!onboardingVC.includes("Seu estudo bíblico, organizado")) {
  errors.push("Onboarding página 1 tem de incluir o tagline de boas-vindas.");
}
if (!onboardingVC.includes("Notas com referências") || !onboardingVC.includes("Temas e leitura") || !onboardingVC.includes("Grupos e amigos")) {
  errors.push("Onboarding tem de ter as 4 páginas (boas-vindas, notas, temas, grupos).");
}
if (!onboardingVC.includes("adjustsFontForContentSizeCategory") || !onboardingVC.includes("safeAreaLayoutGuide")) {
  errors.push("Onboarding tem de respeitar Dynamic Type e safe areas.");
}
if (!onboardingVC.includes("minimumScaleFactor") || !onboardingVC.includes("numberOfLines = 1") || !onboardingVC.includes("adjustsFontSizeToFitWidth")) {
  errors.push("Onboarding wordmark Katecheo tem de ser 1 linha (scale ≥0.6, sem hyphenation/wrap).");
}
if (!onboardingVC.includes("stack.alignment = .fill") && !onboardingVC.includes("alignment = .fill")) {
  errors.push("Onboarding titles/bodies têm de usar largura total (.fill), não coluna estreita por .center.");
}
if (!onboardingVC.includes("Space.xl") || !onboardingVC.includes("bottomBar.bottomAnchor")) {
  errors.push("Onboarding tem de usar padding horizontal ~32pt e pinar Get started na safe area inferior.");
}
if (!onboardingVC.includes("effectiveBottomSafeInset") || !onboardingVC.includes("homeIndicatorFallback") || !onboardingVC.includes("view.bottomAnchor")) {
  errors.push("Onboarding Get started tem de usar effectiveBottomSafeInset (fallback home indicator) pinado a view.bottomAnchor.");
}
if (!onboardingVC.includes("isUserInteractionEnabled = last") || onboardingVC.includes("startButton.isHidden")) {
  errors.push("Onboarding Get started não pode usar isHidden no botão (reflow); usar alpha + isUserInteractionEnabled.");
}

const sceneDelegate = read("ios/App/Katecheo/SceneDelegate.swift");
if (!sceneDelegate.includes("windowScene.windows") || !sceneDelegate.includes("coordinateSpace.bounds")) {
  errors.push("SceneDelegate tem de reutilizar uma única window da scene (sem duplicar sobre Main.storyboard).");
}
const infoPlist = read("ios/App/Katecheo/Info.plist");
if (infoPlist.includes("UISceneStoryboardFile") || infoPlist.includes("<key>UIMainStoryboardFile</key>")) {
  errors.push("Info.plist não pode carregar Main.storyboard na scene (causa janela duplicada / safe area zerada).");
}
if (!project.includes("KatecheoUITests") || !project.includes("OnboardingGetStartedUITests.swift")) {
  errors.push("KatecheoUITests / OnboardingGetStartedUITests têm de estar no projeto Xcode.");
}
if (!onboardingVC.includes("accessibilityLabel") || !onboardingVC.includes("accessibilityHint")) {
  errors.push("Onboarding tem de ter labels VoiceOver.");
}

const profileForOnboarding = read("ios/App/Katecheo/ProfileViewController.swift");
if (!profileForOnboarding.includes("Ver introdução") || !profileForOnboarding.includes("presentOnboardingReplay")) {
  errors.push("Perfil/Settings tem de oferecer 'Ver introdução' para repetir o onboarding.");
}

if (!project.includes("OnboardingStore.swift in Sources") || !project.includes("OnboardingViewController.swift in Sources")) {
  errors.push("OnboardingStore/OnboardingViewController têm de estar no target Xcode.");
}
if (!project.includes("OnboardingFlowTests.swift in Sources")) {
  errors.push("OnboardingFlowTests tem de estar no target KatecheoTests.");
}

const mainStoryboard = read("ios/App/Katecheo/Base.lproj/Main.storyboard");
if (!mainStoryboard.includes('customClass="NativeRootTabBarController"')) {
  errors.push("Main.storyboard tem de apontar para NativeRootTabBarController.");
}
if (mainStoryboard.includes("KatecheoBridge") || mainStoryboard.includes("CAPBridgeViewController")) {
  errors.push("Main.storyboard não pode referenciar o Cap bridge.");
}

const appDelegate = read("ios/App/Katecheo/AppDelegate.swift");
if (appDelegate.includes("import Capacitor") || appDelegate.includes("capacitorDidRegister")) {
  errors.push("AppDelegate tem de usar APNs nativo (sem Capacitor).");
}
if (!appDelegate.includes("NativePushService") || !appDelegate.includes("didRegisterForRemoteNotifications")) {
  errors.push("AppDelegate tem de registar o token APNs via NativePushService.");
}

const shellMode = read("ios/App/Katecheo/NativeShellMode.swift");
if (!shellMode.includes("nativePrimary") || !shellMode.includes("return .nativePrimary")) {
  errors.push("NativeShellMode tem de defaultar / forçar nativePrimary.");
}

const editor = read("ios/App/Katecheo/NativeNoteEditorView.swift");
if (!editor.includes("UITextView") || editor.includes("WKWebView") || editor.includes("import WebKit")) {
  errors.push("NativeNoteEditorView tem de ser UITextView nativo (sem WebKit).");
}
if (!editor.includes("inputAccessoryView") || !editor.includes("Referência bíblica")) {
  errors.push("NativeNoteEditorView tem de ter toolbar com referência bíblica (pt-BR).");
}
if (!editor.includes("setEditingChrome") || !editor.includes("textViewDidBeginEditing")) {
  errors.push("Toolbar de formatação só depois de entrar em modo edição.");
}
// TF200/TF210: inline @/ popovers gone; TF210 also removes typing shortcuts.
if (
  editor.includes("NoteEditorTriggerMenuView") ||
  editor.includes("repositionTriggerMenuIfNeeded") ||
  editor.includes("showAtMenu") ||
  editor.includes("presentTriggerMenu")
) {
  errors.push("Remova o popup inline @/ (NoteEditorTriggerMenuView).");
}
if (editor.includes('text == "@"') || editor.includes('text == "/"')) {
  errors.push("TF210: @ e / não abrem sheets — só inserem o caractere (usar toolbar).");
}
if (!editor.includes("presentSpeakerPicker()") || !editor.includes("presentBibleRefPicker()")) {
  errors.push("Toolbar tem de abrir speaker / referência (presentSpeakerPicker / presentBibleRefPicker).");
}
if (!editor.includes("NoteEditorTagsStrip") || !editor.includes("bodyHasVisibleContent") || !editor.includes("refreshEditingChrome")) {
  errors.push("TF210: tags sob o título, placeholder por attachments, toolbar escondida no título/tags.");
}
if (editor.includes("case .undo") || editor.includes("arrow.uturn.backward") || editor.includes("arrow.uturn.forward")) {
  errors.push("TF210: remova undo/redo da toolbar de formatação.");
}
if (!editor.includes('("person.wave.2", .speaker') || !editor.includes('("book", .bibleRef')) {
  errors.push("TF210: speaker e referência têm de ser os primeiros botões da toolbar.");
}
if (!editor.includes("keyboardOverlap")) {
  errors.push("NativeNoteEditorView tem de acompanhar o teclado (keyboardOverlap).");
}
if (!editor.includes("titlePlaceholderLabel") || !editor.includes("bodyPlaceholderLabel") || !editor.includes("Comece a escrever")) {
  errors.push("Editor tem de ter placeholders de título e corpo (TF200).");
}
if (!editor.includes("@MainActor") && !editor.includes("Thread.isMainThread")) {
  errors.push("NativeNoteEditorView tem de exigir main thread / @MainActor.");
}

const codec = read("ios/App/Katecheo/NoteDocumentCodec.swift");
if (!codec.includes("attributedString(from") || !codec.includes("func document(") || !codec.includes("bibleRef")) {
  errors.push("NoteDocumentCodec tem de round-trip NoteDocument ↔ attributed string com bibleRef.");
}
if (codec.includes("final class SpeakerSectionAttachment")) {
  errors.push("Remova SpeakerSectionAttachment — secção de speaker é header + barra lateral.");
}
if (!codec.includes("speakerRailSpecs") || !codec.includes("speakerSectionContentInset")) {
  errors.push("NoteDocumentCodec tem de expor ranges/cores da barra lateral do speaker.");
}
if (!editor.includes("NoteSpeakerRailLayoutManager") || !editor.includes("refreshSpeakerRails")) {
  errors.push("NativeNoteEditorView tem de desenhar a barra lateral do speaker (rail).");
}
if (!editor.includes("toggleSpeakerCollapsed") || !codec.includes("collapsedKey")) {
  errors.push("Secção de speaker tem de colapsar/expandir (collapsed no NoteDocumentV1).");
}
if (!editor.includes("isSpecialTapTarget") || !editor.includes("gestureRecognizerShouldBegin")) {
  errors.push("Toque em referência bíblica não pode mover o caret.");
}
if (!editor.includes("override func gestureRecognizerShouldBegin")) {
  errors.push("gestureRecognizerShouldBegin tem de usar override (UIView já define o método).");
}
if (!codec.includes("paragraphSpacing = 10") || !editor.includes("baseAttributesPublic")) {
  errors.push("Corpo da nota tem de ter espaçamento entre parágrafos (paragraphSpacing via baseAttributes).");
}
if (!editor.includes("exitSpeakerSection") || !editor.includes("isLastBodyParagraphOfSpeakerSection") || !codec.includes("speakerBodyKey")) {
  errors.push("Enter duplo num parágrafo vazio tem de sair da secção de speaker (speakerBodyKey + exitSpeakerSection).");
}
if (!editor.includes("enum SpeakerEnterDecision") || !editor.includes("ensureTypingAttributes")) {
  errors.push("Editor tem de estabilizar typingAttributes e Enter do speaker (SpeakerEnterDecision).");
}
if (!editor.includes("continueInSection") || !editor.includes("insertContinuingSpeakerBodyParagraph")) {
  errors.push("Enter no corpo do orador tem de continuar dentro da secção (continueInSection).");
}
try {
  const speakerEdit = read("ios/App/Katecheo/SpeakerSectionEditing.swift");
  if (!speakerEdit.includes("insertContinuingBodyParagraph") || !speakerEdit.includes("\\u{200B}") || !speakerEdit.includes("speakerBodyKey")) {
    errors.push("SpeakerSectionEditing tem de inserir corpo com ZWSP + speakerBodyKey.");
  }
  if (!speakerEdit.includes("insertSpeakerBlock")) {
    errors.push("SpeakerSectionEditing tem de inserir secções via modelo (insertSpeakerBlock), sem linhas fantasma.");
  }
} catch {
  errors.push("Falta SpeakerSectionEditing.swift");
}
if (!project.includes("SpeakerSectionEditing.swift in Sources") || !project.includes("SpeakerSectionEditingTests.swift in Sources")) {
  errors.push("SpeakerSectionEditing (+ tests) têm de estar no target Xcode.");
}
try {
  const header = read("ios/App/Katecheo/SpeakerHeaderAttachment.swift");
  if (!header.includes("NSTextAttachment") || !header.includes("Hit") || !header.includes("remove")) {
    errors.push("SpeakerHeaderAttachment tem de ser NSTextAttachment não editável (chevron / nome / ×).");
  }
} catch {
  errors.push("Falta SpeakerHeaderAttachment.swift");
}
if (!project.includes("SpeakerHeaderAttachment.swift in Sources")) {
  errors.push("SpeakerHeaderAttachment tem de estar no target Xcode.");
}
if (!editor.includes("removeSpeakerSection") || !editor.includes("renameSpeakerSection") || !editor.includes("rangeIntersectsSpeakerHeader")) {
  errors.push("Cabeçalho do orador tem de ser não editável (bloquear teclado, × remove, rename via picker).");
}
if (!editor.includes("paragraphBlockType") || !editor.includes("normalizeSpeakerBodyParagraphAttributes") || !editor.includes("isNewlineReplacement")) {
  errors.push("Enter do orador tem de usar o tipo do início do parágrafo + normalizar o corpo (não só helpers puros).");
}
if (!editor.includes("testing_insertText") || !editor.includes("testing_prepare") || !project.includes("NativeNoteEditorSpeakerPathTests.swift in Sources")) {
  errors.push("KatecheoTests têm de exercer o caminho real NativeNoteEditorView/UITextView (NativeNoteEditorSpeakerPathTests).");
}
if (!project.includes("NativeNoteEditorTF194Tests.swift in Sources")) {
  errors.push("AppTests TF194 (NativeNoteEditorTF194Tests) têm de estar no target.");
}
if (!project.includes("NativeNoteEditorTF200Tests.swift in Sources")) {
  errors.push("AppTests TF200 (NativeNoteEditorTF200Tests) têm de estar no target.");
}
if (!project.includes("NativeNoteEditorTF210Tests.swift in Sources")) {
  errors.push("AppTests TF210 (NativeNoteEditorTF210Tests) têm de estar no target.");
}
if (!project.includes("NoteEditorTagsStrip.swift in Sources")) {
  errors.push("NoteEditorTagsStrip tem de estar no target App.");
}
try {
  const settings = read("ios/App/Katecheo/NoteSettingsViewController.swift");
  if (settings.includes('String(localized: "Tags")') || settings.includes("tagField") || settings.includes("addTag")) {
    errors.push("TF210: tags saíram das Configurações (ficam sob o título no editor).");
  }
} catch {
  errors.push("Falta NoteSettingsViewController.swift");
}
if (!codec.includes("listMarkerWidth") || !codec.includes("titleTagsReservedSpacing")) {
  errors.push("NoteDocumentCodec tem de medir a largura do marcador da lista e reservar espaço para tags.");
}
try {
  const api = read("ios/App/Katecheo/NativeAPIClient.swift");
  const spanIdx = api.indexOf("private func spanText");
  const spanText = spanIdx >= 0 ? api.slice(spanIdx, spanIdx + 450) : "";
  if (!spanText.includes('span.type == "bibleRef"') || !spanText.includes("return nil")) {
    errors.push("NativeAPIClient.preview/spanText tem de saltar bibleRef (só texto plano).");
  }
} catch {
  errors.push("Falta NativeAPIClient.swift");
}
try {
  const cache = read("ios/App/Katecheo/LocalNoteCache.swift");
  if (!cache.includes("mergeSpeakers") || !cache.includes("removeSpeaker")) {
    errors.push("LocalNoteCache tem de mergeSpeakers (não apagar o catálogo com speakers note-scoped).");
  }
} catch {
  errors.push("Ficheiro em falta: ios/App/Katecheo/LocalNoteCache.swift");
}
if (!editor.includes("confirmRemoveSpeakerSection") || !editor.includes("Remover seção do speaker?")) {
  errors.push("× do speaker tem de pedir confirmação localizada antes de apagar.");
}
if (!project.includes("KCSheetPresenter.swift in Sources")) {
  errors.push("KCSheetPresenter tem de estar no target (dismiss por backdrop).");
}
try {
  const sheet = read("ios/App/Katecheo/KCSheetPresenter.swift");
  if (!sheet.includes("isModalInPresentation = false") || !sheet.includes(".medium()")) {
    errors.push("KCSheetPresenter tem de permitir dismiss por fora (medium detent + não modal-in-presentation).");
  }
} catch {
  errors.push("Falta KCSheetPresenter.swift");
}
if (!editor.includes("from: textView.textStorage")) {
  errors.push("currentDocument tem de ler textStorage (attributedText pode perder speakerBodyKey).");
}
try {
  const spec = read("docs/editor-behavior-spec.md");
  if (!spec.includes("contenteditable=\"false\"") || !spec.includes("note-speaker-remove")) {
    errors.push("docs/editor-behavior-spec.md tem de documentar o cabeçalho não editável da web.");
  }
} catch {
  errors.push("Falta docs/editor-behavior-spec.md (parity com o editor web).");
}
if (!editor.includes("typingAttributesForCaret") || !codec.includes("\\u{200B}")) {
  errors.push("Nota vazia / load path tem de criar runs atribuídos (ZWSP) e definir typingAttributes no pushNote.");
}
if (!editor.includes("class NoteEditorTextView") || !editor.includes("override func caretRect(for")) {
  errors.push("Caret do editor tem de limitar a altura à lineHeight da fonte (NoteEditorTextView.caretRect).");
}
if (!project.includes("KatecheoTests") || !project.includes("NoteDocumentCodecTests.swift in Sources")) {
  errors.push("Target KatecheoTests com round-trip do codec tem de existir no Xcode project.");
}
if (!codec.includes("BibleBookCatalog.formatPassage") || !project.includes("BibleBookCatalog.swift in Sources")) {
  errors.push("Referências nas notas têm de formatar nomes via BibleBookCatalog (idioma de referências).");
}
const biblePicker = read("ios/App/Katecheo/BibleRefInsertPicker.swift");
if (!biblePicker.includes("KCNumberCell") || !biblePicker.includes("KCNumberGridLayout") || biblePicker.includes("UITableViewController")) {
  errors.push("Picker de referência na nota tem de usar grelha (KCNumberCell), não lista.");
}

const noteDetail = read("ios/App/Katecheo/NoteDetailViewController.swift");
if (noteDetail.includes("WKWebView") || noteDetail.includes("import WebKit") || noteDetail.includes("NoteMioloEditorView")) {
  errors.push("NoteDetailViewController não pode usar WebView / NoteMioloEditorView.");
}
if (!noteDetail.includes("NativeNoteEditorView")) {
  errors.push("NoteDetailViewController tem de hospedar NativeNoteEditorView.");
}
if (!noteDetail.includes("hidesBottomBarWhenPushed = true")) {
  errors.push("A tela da nota tem de esconder a tab bar (hidesBottomBarWhenPushed).");
}
if (noteDetail.includes("Salvo no aparelho — sincroniza") || noteDetail.includes("Editor nativo") || noteDetail.includes('statusLabel.text')) {
  errors.push("A nota não pode mostrar texto de sync no topo — use ícone discreto.");
}
if (!noteDetail.includes("checkmark.icloud") && !noteDetail.includes("icloud.and.arrow.up")) {
  errors.push("A nota tem de expor sync só como ícone (icloud), não como label.");
}

try {
  read("ios/App/Katecheo/NoteMioloEditorView.swift");
  errors.push("Phase 7: NoteMioloEditorView.swift ainda existe — remover.");
} catch {
  /* expected missing */
}

// Guard: no Cap / product WKWebView surfaces (bootstrap + Phase 6 import only).
const appDir = join(root, "ios/App/Katecheo");
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

const legacyImport = read("ios/App/Katecheo/LegacyWebStorageImporter.swift");
if (!legacyImport.includes("@MainActor") || !legacyImport.includes("Thread.isMainThread")) {
  errors.push("LegacyWebStorageImporter tem de ser @MainActor e exigir Thread.isMainThread.");
}
if (!legacyImport.includes("cita-settings") || !legacyImport.includes("verse2note-outbox")) {
  errors.push("LegacyWebStorageImporter tem de ler cita-settings e verse2note-outbox.");
}
if (!legacyImport.includes("NoteDocument") && !legacyImport.includes("LegacyNoteConverter")) {
  errors.push("LegacyWebStorageImporter tem de converter para NoteDocumentV1.");
}

const outbox = read("ios/App/Katecheo/NativeOutbox.swift");
if (!outbox.includes("enqueueNoteUpsert") || !outbox.includes("flushIfPossible") || !outbox.includes("nextAttemptAt")) {
  errors.push("NativeOutbox tem de ter enqueue + flush com backoff (nextAttemptAt).");
}

for (const dead of [
  "ios/App/Katecheo/NativeShell.swift",
  "ios/App/Katecheo/LiquidChrome.swift",
  "ios/App/Katecheo/NativeMenus.swift",
  "ios/App/Katecheo/NativePhase0Plugin.swift",
  "ios/App/Katecheo/NoteEditorSpikeViewController.swift",
  "ios/App/Katecheo/NoteMioloEditorView.swift",
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

const material = read("ios/App/Katecheo/LiquidGlassMaterial.m");
if (!material.includes("UIGlassEffect") || !material.includes("UIBlurEffectStyleSystemChromeMaterial")) {
  errors.push("O material tem de ter UIGlassEffect e o desfoque clássico.");
}
if (!material.includes("__IPHONE_26_0") || !material.includes("prominentGlassButtonConfiguration")) {
  errors.push("Liquid Glass tem de compilar só com o SDK do iOS 26.");
}

const sessionBoot = read("ios/App/Katecheo/NativeSessionBootstrap.swift");
if (!sessionBoot.includes("@MainActor") || !sessionBoot.includes("Thread.isMainThread")) {
  errors.push("NativeSessionBootstrap tem de ser @MainActor e guardar Thread.isMainThread antes de WKWebsiteDataStore.");
}

const push = read("ios/App/Katecheo/NativePushService.swift");
if (!push.includes("UNUserNotificationCenter") || !push.includes("saveApnsDevice") || !push.includes("NativeDeepLinkRouter")) {
  errors.push("NativePushService tem de registar APNs e abrir href via NativeDeepLinkRouter.");
}
if (!push.includes("DeviceIdStore") || !push.includes("deviceId:")) {
  errors.push("NativePushService tem de enviar deviceId estável com o token APNs.");
}
try {
  const deviceIdStore = read("ios/App/Katecheo/DeviceIdStore.swift");
  if (!deviceIdStore.includes("identifierForVendor") || !deviceIdStore.includes("KeychainStore")) {
    errors.push("DeviceIdStore tem de usar identifierForVendor + Keychain.");
  }
} catch {
  errors.push("Falta ios/App/Katecheo/DeviceIdStore.swift.");
}

const deep = read("ios/App/Katecheo/NativeDeepLinkRouter.swift");
if (!deep.includes("destination(for") || !deep.includes("notebook") || !deep.includes("NoteDetailViewController")) {
  errors.push("NativeDeepLinkRouter tem de mapear paths para ecrãs nativos.");
}

const comingSoon = read("ios/App/Katecheo/ComingSoonTabViewController.swift");
if (comingSoon.includes("capacitorSite") || comingSoon.includes("KatecheoBridge") || comingSoon.includes("Usar app clássico")) {
  errors.push("ComingSoon não pode oferecer o host Capacitor.");
}

const design = read("ios/App/Katecheo/KCDesign.swift");
if (!design.includes("static let accent") || !design.includes("static let canvas") || !design.includes("enum KCChrome") || !design.includes("static func applyAppWide")) {
  errors.push("KCDesign tem de expor accent/canvas e KCChrome.applyAppWide.");
}
if (!design.includes("userInterfaceStyle == .dark")) {
  errors.push("KCDesign tem de declarar cores com suporte a Dark Mode.");
}
const components = read("ios/App/Katecheo/KCComponents.swift");
if (!components.includes("KCEmptyStateView") || !components.includes("KCNoteRowCell") || !components.includes("KCHaptics")) {
  errors.push("KCComponents tem de incluir empty state, note row e haptics.");
}
if (!appDelegate.includes("KCChrome.applyAppWide")) {
  errors.push("AppDelegate tem de aplicar KCChrome.applyAppWide no launch.");
}
const rootTabsChrome = read("ios/App/Katecheo/NativeRootTabBarController.swift");
if (!rootTabsChrome.includes("KCDesign.accent") || !rootTabsChrome.includes("KCChrome.style")) {
  errors.push("NativeRootTabBarController tem de usar o design system (accent + chrome).");
}
if (/Partilhar|Guardar|utilizador|Definições/.test(design) || /Partilhar|Guardar|utilizador|Definições/.test(components)) {
  errors.push("Design system: strings têm de ser pt-BR (não Partilhar/Guardar/utilizador/Definições).");
}

const signIn = read("ios/App/Katecheo/NativeSignInViewController.swift");
if (signIn.includes("Abrir site clássico") || signIn.includes("capacitorSite")) {
  errors.push("O login nativo não pode abrir o site clássico.");
}
if (!signIn.includes("Continuar com Google") || !signIn.includes("Entrar com email")) {
  errors.push("Falta o ecrã nativo de login (Google + email).");
}
if (!signIn.includes("Entrar ou criar conta") || !signIn.includes("Criar conta")) {
  errors.push("O ecrã de auth tem de deixar claro Entrar ou criar conta (segmento Criar conta).");
}
if (!signIn.includes("UISegmentedControl") || !signIn.includes("Confirmar senha")) {
  errors.push("Create-account mode precisa de UISegmentedControl + confirmação de senha.");
}
if (!signIn.includes("ASAuthorizationAppleIDButton") || !signIn.includes("makeAppleButton")) {
  errors.push("NativeSignInViewController tem de renderizar ASAuthorizationAppleIDButton (Sign in with Apple).");
}
if (!signIn.includes("type: .continue") && !signIn.includes("type:.continue")) {
  errors.push("ASAuthorizationAppleIDButton tem de usar type .continue (HIG).");
}
if (!signIn.includes("appleButtonStyle") || !signIn.includes("userInterfaceStyle")) {
  errors.push("O botão Apple tem de adaptar light/dark (appleButtonStyle).");
}
if (!signIn.includes('UIImage(named: "BrandMark")') || signIn.includes("book.closed.fill")) {
  errors.push('NativeSignInViewController tem de usar UIImage(named: "BrandMark") (não SF Symbol book.closed.fill).');
}
if (!signIn.includes('String(localized: "Katecheo")') || /["'`]Kate["'`]/.test(signIn) || /["'`]cheo["'`]/.test(signIn)) {
  errors.push('NativeSignInViewController: "Katecheo" tem de ser uma só palavra em estilo uniforme.');
}
if (
  !signIn.includes("Esqueci minha senha") ||
  !signIn.includes("tapForgotPassword") ||
  !signIn.includes("NativeForgotPasswordViewController")
) {
  errors.push("Entrar mode tem de expor 'Esqueci minha senha' → NativeForgotPasswordViewController.");
}

const forgotVC = read("ios/App/Katecheo/NativeForgotPasswordViewController.swift");
if (!forgotVC.includes("oneTimeCode") || !forgotVC.includes("numberPad")) {
  errors.push("Forgot-password step 2 precisa de textContentType .oneTimeCode + teclado numberPad.");
}
if (!forgotVC.includes("Reenviar código")) {
  errors.push("Forgot-password precisa de ação Reenviar código com cooldown.");
}
if (!forgotVC.includes("Nova senha (mín. 8)") || !forgotVC.includes("Confirmar nova senha")) {
  errors.push("Forgot-password step 2 precisa de campos de nova senha + confirmação.");
}
if (!forgotVC.includes("AppLocale.apiCode")) {
  errors.push("Forgot-password tem de enviar o idioma do dispositivo como locale.");
}

const forgotForm = read("ios/App/Katecheo/NativeForgotPasswordForm.swift");
if (!forgotForm.includes("codeLength = 6") || !forgotForm.includes("resendCooldownSeconds")) {
  errors.push("NativeForgotPasswordForm tem de validar código de 6 dígitos e cooldown de reenvio.");
}

const loginService = read("ios/App/Katecheo/NativeLoginService.swift");
if (!loginService.includes("ASWebAuthenticationSession") || !loginService.includes("auth/claim")) {
  errors.push("NativeLoginService tem de fazer Google via ASWebAuthenticationSession + claim.");
}
if (
  !loginService.includes("requestPasswordReset") ||
  !loginService.includes("auth/email/forgot-password") ||
  !loginService.includes("resetPasswordWithCode") ||
  !loginService.includes("auth/email/reset-password")
) {
  errors.push(
    "NativeLoginService tem de chamar /auth/email/forgot-password e /auth/email/reset-password.",
  );
}
if (!loginService.includes("locale") || !loginService.includes("invalid_code") || !loginService.includes("code_exhausted")) {
  errors.push("Forgot/reset nativo tem de enviar locale e tratar invalid_code / code_exhausted.");
}
if (
  !loginService.includes("signInWithApple") ||
  !loginService.includes("auth/apple") ||
  !loginService.includes("authorizationCode") ||
  !loginService.includes("requestedScopes")
) {
  errors.push(
    "NativeLoginService tem de enviar identityToken + authorizationCode + nonce (scopes fullName/email) a /auth/apple.",
  );
}
if (!loginService.includes("signOut") || !loginService.includes("deleteBearerToken")) {
  errors.push("Sign-out nativo tem de limpar o Keychain.");
}
if (!loginService.includes("signUpWithEmail") || !loginService.includes("auth/email/sign-up")) {
  errors.push("NativeLoginService tem de chamar /api/native/v1/auth/email/sign-up.");
}
if (!loginService.includes("email_exists")) {
  errors.push("Sign-up nativo tem de tratar email_exists com mensagem amigável.");
}

const notebookList = read("ios/App/Katecheo/NotebookListViewController.swift");
if (notebookList.includes("Site clássico") || notebookList.includes("capacitorSite")) {
  errors.push("O Caderno não pode oferecer Site clássico (Cap).");
}
if (!notebookList.includes("UIActivityViewController") || !notebookList.includes("trailingSwipeActions")) {
  errors.push("A lista nativa tem de ter swipe e partilha nativa.");
}
if (!notebookList.includes("kcIconOnly") || !notebookList.includes("leadingSwipeActions")) {
  errors.push("Swipe do Caderno tem de ser só ícone (kcIconOnly) em leading/trailing.");
}
if (/UIContextualAction\(style:.*title:\s*String\(localized:/.test(notebookList)) {
  errors.push("Swipe do Caderno não pode mostrar título de texto (usar title nil + ícone).");
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

const rootTabs = read("ios/App/Katecheo/NativeRootTabBarController.swift");
if (!rootTabs.includes("GroupsListViewController") || rootTabs.includes('titleText: "Grupos"')) {
  errors.push("Phase 2: o separador Grupos tem de usar GroupsListViewController.");
}
if (!rootTabs.includes("ProfileViewController") || rootTabs.includes('titleText: "Perfil"')) {
  errors.push("Phase 3: a aba Perfil tem de usar ProfileViewController.");
}
if (!rootTabs.includes("VersesHomeViewController") || rootTabs.includes('titleText: "Versículos"')) {
  errors.push("Phase 4: a aba Ferramentas tem de usar VersesHomeViewController.");
}
if (!rootTabs.includes("Ferramentas") || !rootTabs.includes("selectedIndex = 0")) {
  errors.push("Tab bar: Caderno default + Ferramentas (não Versículos).");
}
// Caderno · Grupos · Ferramentas · Perfil — Leitura is not a root tab.
if (rootTabs.includes("ReadingHomeViewController") || /UITabBarItem\([\s\S]*Leitura/.test(rootTabs)) {
  errors.push("Remova a aba Leitura do tab bar — Leitura fica sob Ferramentas.");
}
if (!/NotebookListViewController[\s\S]*GroupsListViewController[\s\S]*VersesHomeViewController[\s\S]*ProfileViewController/.test(rootTabs)) {
  errors.push("Ordem das abas: Caderno, Grupos, Ferramentas, Perfil.");
}
if (!project.includes("ReadingScreens.swift in Sources")) {
  errors.push("ReadingScreens.swift tem de estar no target Xcode.");
}
if (
  /KCFilterChip\(id:\s*"themes"/.test(notebookList) ||
  /KCFilterChip\(id:\s*"lists"/.test(notebookList)
) {
  errors.push("Caderno não pode mostrar chips Temas/Listas (só filtros de notas).");
}
if (!notebookList.includes("hidesSearchBarWhenScrolling = true")) {
  errors.push("Caderno: a busca tem de ocultar ao rolar (hidesSearchBarWhenScrolling).");
}
if (!notebookList.includes("allowsDeselect") || !notebookList.includes("handleNotebookChip")) {
  errors.push("Caderno: pills têm de permitir deselect e trocar filtros sem sumir.");
}
if (!notebookList.includes("Membros") || !notebookList.includes("GroupMembersViewController")) {
  errors.push("Menu … do grupo tem de incluir Membros (GroupMembersViewController).");
}
if (!components.includes("allowsDeselect") || !components.includes("config.title = selected ? chip.title")) {
  errors.push("KCFilterChipsView: ícone só quando não selecionado; ícone+nome quando selecionado.");
}
if (!components.includes("leading: horizontal") || !/selected \? 16 : 24/.test(components) || !components.includes("greaterThanOrEqualToConstant: 72")) {
  errors.push("Pills não selecionadas têm de ser cápsulas largas (padding ≥24 / min width 72).");
}
if (!components.includes("kcApplyBrandListStyle") || !components.includes("kcApplyBrandChrome")) {
  errors.push("Temas/Listas têm de usar helpers de marca (sem tint azul de sistema).");
}
const versesScreens = read("ios/App/Katecheo/VersesScreens.swift");
if (!versesScreens.includes("kcApplyBrandListStyle") || !versesScreens.includes("KCEmptyStateView") || !versesScreens.includes("KCDesign.accent")) {
  errors.push("Temas e Listas têm de usar empty states e tint de marca.");
}
if (!project.includes("LocalSessionCache.swift in Sources") || !project.includes("GroupMembersViewController.swift in Sources")) {
  errors.push("LocalSessionCache / GroupMembersViewController têm de estar no target Xcode.");
}

try {
  const groupsList = read("ios/App/Katecheo/GroupsListViewController.swift");
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
  const versesHome = read("ios/App/Katecheo/VersesHomeViewController.swift");
  if (!versesHome.includes("Ferramentas") || !versesHome.includes("BooksHomeViewController")) {
    errors.push("Ferramentas: home com pills + BooksHomeViewController.");
  }
  if (versesHome.includes("KCToolCardCell") || versesHome.includes("cardsPanel")) {
    errors.push("Remova o hub de cards legado da Ferramentas — abrir direto na pill.");
  }
  if (!versesHome.includes("ThemesHomeViewController") || !versesHome.includes("ReadingHomeViewController") || !versesHome.includes("MyCollectionsViewController")) {
    errors.push("Ferramentas tem de abrir Temas, Listas e Leitura.");
  }
  if (!versesHome.includes("KCFilterChipsView") || !versesHome.includes("chips.configure")) {
    errors.push("Ferramentas tem de ter pills (KCFilterChipsView) Livros/Temas/Listas/Leitura.");
  }
  if (!versesHome.includes("selectTool") || !versesHome.includes("embedded: true") || !versesHome.includes("lastToolKey") || !versesHome.includes("allowsDeselect = false")) {
    errors.push("Ferramentas: abrir na última pill (persistida) ou Livros; sem cards.");
  }
  if (!versesHome.includes("applyBooksCompact") || !versesHome.includes("booksCompact")) {
    errors.push("Livros tem de manter Siglas/Nomes sincronizados com booksCompact no primeiro load.");
  }
  if (!versesHome.includes("refreshCollectionLayoutIfNeeded") || !versesHome.includes("pendingLayoutRefresh")) {
    errors.push("Livros tem de invalidar o grid só com bounds válidos (lista vazia no launch).");
  }
  // Livros must not own a permanent search; Temas/Leitura may install parent searchController (build-238).
  if (versesHome.includes("Buscar livro") || (versesHome.includes("magnifyingglass") && !versesHome.includes("installSearchController"))) {
    errors.push("Remova a busca permanente da tela Livros (ícone / Buscar livro).");
  }
  if (versesHome.includes("UISearchController") && !versesHome.includes("installSearchController")) {
    errors.push("UISearchController em Ferramentas só via installSearchController (Temas/Leitura pull-to-reveal).");
  }
  if (versesHome.includes("livros · Bíblia") || versesHome.includes("statusBanner")) {
    errors.push("Remova o subtítulo «N livros · Bíblia: …» do header.");
  }
  if (!versesHome.includes("largeTitleDisplayMode = .always") || !versesHome.includes("prefersLargeTitles = true")) {
    errors.push("Ferramentas/Livros têm de usar large title.");
  }
  if (!versesHome.includes("trailing: indexPath.section == 0 ? modeToggle") && !versesHome.includes("trailing: indexPath.section == 0 ? modeToggle : nil")) {
    errors.push("Siglas/Nomes (modeToggle) tem de ficar na header do Antigo Testamento (scroll).");
  }
  if (!components.includes("trailing:") || !components.includes("trailingHost")) {
    errors.push("KCBookSectionHeaderView tem de aceitar trailing (Siglas/Nomes no scroll).");
  }
  if (!components.includes("KCNamedCreateViewController") || !components.includes("KCNumberCell") || !components.includes("KCBibleAppLogoCell")) {
    errors.push("Faltam componentes: create form, number grid, bible logo tiles.");
  }
  const groupsListSync = read("ios/App/Katecheo/GroupsListViewController.swift");
  if (groupsListSync.includes("grupos · sincronizado")) {
    errors.push("Remova o banner persistente «grupos · sincronizado».");
  }
  const readingHome = read("ios/App/Katecheo/ReadingScreens.swift");
  if (!readingHome.includes("KCPlanCategoryCardCell") || !readingHome.includes("UICollectionView")) {
    errors.push("Leitura home tem de usar cards (UICollectionView) como a web original.");
  }
  if (!readingHome.includes("init(embedded:") || !readingHome.includes("reloadFromParent")) {
    errors.push("ReadingHomeViewController tem de manter init(embedded:) + reloadFromParent.");
  }
  if (!deep.includes('selectHomeFilter("reading")') && !deep.includes("selectHomeFilter(\"reading\")")) {
    errors.push("Deep links de Leitura têm de abrir Ferramentas → Leitura.");
  }
  if (!deep.includes("Tab.tools") && !deep.includes("selectedIndex = Tab.tools") && !/selectedIndex = 2/.test(deep)) {
    errors.push("Deep links: Ferramentas é o índice 2 (Caderno=0, Grupos=1).");
  }
  const versesScreens = read("ios/App/Katecheo/VersesScreens.swift");
  if (
    !versesScreens.includes("VerseActionsViewController") ||
    !versesScreens.includes("appendVerse") ||
    !versesScreens.includes("Adicionar à nota")
  ) {
    errors.push("Faltam telas nativas de ações de versículo / adicionar à nota.");
  }
  if (!versesScreens.includes("KCNumberCell") || !versesScreens.includes("KCNumberGridLayout")) {
    errors.push("Picker de capítulo/versículo tem de usar grelha numérica.");
  }
  if (!versesScreens.includes("KCNamedCreateViewController")) {
    errors.push("Criar lista/tema tem de usar o formulário KCNamedCreateViewController (sem alerta azul).");
  }
  if (/Partilhar|Guardar|utilizador|Definições/.test(versesScreens) || /Partilhar|Guardar|utilizador|Definições/.test(versesHome)) {
    errors.push("Strings de Ferramentas têm de ser pt-BR (não Partilhar/Guardar/utilizador/Definições).");
  }
  const bibleSettings = read("ios/App/Katecheo/ProfileSettingsScreens.swift");
  if (!bibleSettings.includes("KCBibleAppLogoCell") || !bibleSettings.includes("BibleApp_")) {
    errors.push("App de Bíblia: grelha de logos (KCBibleAppLogoCell + assets).");
  }
  if (!bibleSettings.includes("kcApplyTabBarScrollClearance") || !bibleSettings.includes("tableHeaderView")) {
    errors.push("App de Bíblia: scroll único + clearance da tab bar (TF214).");
  }
  const design = read("ios/App/Katecheo/KCDesign.swift");
  if (!design.includes("KCScrollChrome") || !design.includes("tabBarClearance")) {
    errors.push("KCScrollChrome tem de calcular inset inferior sob a tab bar flutuante.");
  }
  const speakerHeader = read("ios/App/Katecheo/SpeakerHeaderAttachment.swift");
  if (!speakerHeader.includes("renderedInterfaceStyle") || !speakerHeader.includes("alwaysOriginal")) {
    errors.push("SpeakerHeaderAttachment tem de bakear imagem alwaysOriginal com renderedInterfaceStyle (TF214/TF222).");
  }
  if (!speakerHeader.includes("palette(for:") || !speakerHeader.includes("resolvedBakeStyle")) {
    errors.push("SpeakerHeaderAttachment tem de usar palette RGB fixa (não UIColor.label) — TF222.");
  }
  {
    const boundsChunk = (speakerHeader.split("func attachmentBounds")[1] || "").split("func hit")[0] || "";
    if (boundsChunk.includes("UITraitCollection.current")) {
      errors.push("attachmentBounds não pode re-bakear com UITraitCollection.current (TF222 — white on beige).");
    }
  }
  if (speakerHeader.includes("UIColor.label") || speakerHeader.includes("UIColor.secondaryLabel")) {
    errors.push("SpeakerHeaderAttachment não pode usar UIColor.label/secondaryLabel no bake (TF222).");
  }
  if (!editor.includes("refreshSpeakerHeaderAppearances") || !editor.includes("traitCollectionDidChange")) {
    errors.push("NativeNoteEditorView tem de re-renderizar headers de speaker ao mudar light/dark.");
  }
  if (!editor.includes("speakerBakeTraits") || !editor.includes("didMoveToWindow") || !editor.includes("textView.traitCollection")) {
    errors.push("NativeNoteEditorView tem de bakear headers com traits do UITextView + Appearance (TF219).");
  }
  const codec = read("ios/App/Katecheo/NoteDocumentCodec.swift");
  if (!codec.includes("speakerSectionHeader") || !codec.includes("UIColor.clear")) {
    errors.push("speakerSectionHeader tem de usar foregroundColor clear no attachment (TF222).");
  }
} catch {
  errors.push("Arquivo Phase 4 em falta: VersesHomeViewController.swift / VersesScreens.swift");
}
if (!project.includes("VersesHomeViewController.swift in Sources") || !project.includes("VersesScreens.swift in Sources")) {
  errors.push("VersesHomeViewController / VersesScreens têm de estar no target Xcode.");
}

try {
  const confirmation = read("ios/App/Katecheo/KCConfirmation.swift");
  if (!confirmation.includes("needsPopoverAnchor") || !confirmation.includes("presentActionSheet")) {
    errors.push("KCConfirmation tem de apresentar action sheets sem popover no iPhone.");
  }
  if (!project.includes("KCConfirmation.swift in Sources")) {
    errors.push("KCConfirmation.swift tem de estar no target Xcode.");
  }
  if (!project.includes("ConfirmationDialogTests.swift in Sources")) {
    errors.push("ConfirmationDialogTests têm de estar no target.");
  }
  const friends = read("ios/App/Katecheo/FriendsActivityViewController.swift");
  if (!friends.includes("KCConfirmation.presentActionSheet")) {
    errors.push("Friends tem de usar KCConfirmation para confirmações nativas.");
  }
  if (!friends.includes("incomingAccessory") || !friends.includes("Remover amigo") || !friends.includes("removeLink")) {
    errors.push("Friends tem de ter Aceitar/Recusar inline, Remover amigo e removeLink.");
  }
  if (friends.includes("Nenhum pedido pendente") || friends.includes("Pedidos só saem da lista")) {
    errors.push("Friends não pode mostrar empty states verbosos de pedidos vazios.");
  }
  for (const rel of [
    "ios/App/Katecheo/ProfileViewController.swift",
    "ios/App/Katecheo/FriendsActivityViewController.swift",
    "ios/App/Katecheo/NotebookListViewController.swift",
    "ios/App/Katecheo/NoteDetailViewController.swift",
    "ios/App/Katecheo/GroupsListViewController.swift",
    "ios/App/Katecheo/GroupMembersViewController.swift",
    "ios/App/Katecheo/ReadingScreens.swift",
    "ios/App/Katecheo/VersesScreens.swift",
  ]) {
    const src = read(rel);
    if (src.includes("popoverPresentationController")) {
      errors.push(`${rel} não pode configurar popoverPresentationController diretamente (usar KCConfirmation).`);
    }
  }
} catch (err) {
  errors.push(`Falha na auditoria de confirmações: ${err instanceof Error ? err.message : String(err)}`);
}

try {
  const profile = read("ios/App/Katecheo/ProfileViewController.swift");
  if (!profile.includes("Sair da conta") || !(profile.includes("Apagar conta") || profile.includes("Excluir conta")) || !profile.includes("getMe")) {
    errors.push("ProfileViewController tem de mostrar perfil, sair da conta e excluir conta.");
  }
  if (!profile.includes("KCConfirmation.presentActionSheet") || !profile.includes('String(localized: "Sair")')) {
    errors.push("Sign out tem de usar KCConfirmation + botão destrutivo «Sair».");
  }
  const settings = read("ios/App/Katecheo/ProfileSettingsScreens.swift");
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
if (!project.includes("KCScrollChromeTests.swift in Sources")) {
  errors.push("AppTests KCScrollChromeTests têm de estar no target.");
}
if (!project.includes("KCSwipeActionTests.swift in Sources")) {
  errors.push("AppTests KCSwipeActionTests têm de estar no target.");
}
if (!project.includes("TabBackgroundConsistencyTests.swift in Sources")) {
  errors.push("AppTests TabBackgroundConsistencyTests têm de estar no target.");
}
try {
  const design = read("ios/App/Katecheo/KCDesign.swift");
  if (!design.includes("screenBackground") || !design.includes("styleScreen") || !design.includes("makeNavigationBarAppearance")) {
    errors.push("KCChrome tem de unificar screenBackground no nav + tabs (Profile-matched).");
  }
  if (design.includes("surface.withAlphaComponent(0.94)")) {
    errors.push("Nav bar não pode usar surface semi-opaco (banda mais clara que o conteúdo).");
  }
  const notebook = read("ios/App/Katecheo/NotebookListViewController.swift");
  const groups = read("ios/App/Katecheo/GroupsListViewController.swift");
  const tools = read("ios/App/Katecheo/VersesHomeViewController.swift");
  const profile = read("ios/App/Katecheo/ProfileViewController.swift");
  for (const [name, src] of [
    ["Notebook", notebook],
    ["Groups", groups],
    ["Tools", tools],
    ["Profile", profile],
  ]) {
    if (!src.includes("styleScreen")) {
      errors.push(`${name} tem de usar KCChrome.styleScreen (fundo único como Perfil).`);
    }
  }
} catch {
  errors.push("Falha ao validar chrome de fundo das tabs.");
}
if (!project.includes("NativeNoteEditorTF214Tests.swift in Sources")) {
  errors.push("AppTests TF214 (NativeNoteEditorTF214Tests) têm de estar no target.");
}
if (!project.includes("NativeNoteEditorTF219Tests.swift in Sources")) {
  errors.push("AppTests TF219 (NativeNoteEditorTF219Tests) têm de estar no target.");
}
if (!project.includes("NativeNoteEditorTF222Tests.swift in Sources")) {
  errors.push("AppTests TF222 (NativeNoteEditorTF222Tests) têm de estar no target.");
}
if (!project.includes("NativeNoteEditorCaretScrollTests.swift in Sources")) {
  errors.push("AppTests de scroll do caret (NativeNoteEditorCaretScrollTests) têm de estar no target.");
}
{
  const editorSrc = read("ios/App/Katecheo/NativeNoteEditorView.swift");
  if (!editorSrc.includes("NoteEditorCaretScroll") || !editorSrc.includes("contentInsetAdjustmentBehavior = .never")) {
    errors.push("NativeNoteEditorView tem de usar NoteEditorCaretScroll + contentInsetAdjustmentBehavior.never (sem scrollRangeToVisible no caret).");
  }
  if (!editorSrc.includes("pendingScrollAnchor") || !editorSrc.includes("restoreScrollAnchorIfNeeded")) {
    errors.push("NativeNoteEditorView tem de preservar contentOffset (pendingScrollAnchor) após Enter/Backspace.");
  }
  if (!editorSrc.includes("stickyContentOffset") || !editorSrc.includes("measuredContentHeight") || !editorSrc.includes("caretRectInBoundsForScroll")) {
    errors.push("NativeNoteEditorView tem de travar contentOffset (sticky) e medir caret/altura via layoutManager.");
  }
  if (!/override func scrollRangeToVisible/.test(editorSrc) || !editorSrc.includes("onRequestCaretScroll")) {
    errors.push("NoteEditorTextView.scrollRangeToVisible tem de encaminhar para onRequestCaretScroll (minimal caret follow).");
  }
  const caretTests = read("ios/App/KatecheoTests/NativeNoteEditorCaretScrollTests.swift");
  if (!caretTests.includes("testRepeatedEnterAtLastVisibleLine_scrollsAboutOneLineEachTime")) {
    errors.push("NativeNoteEditorCaretScrollTests tem de cobrir Enter repetido na última linha visível (~1 linha por Enter).");
  }
}
if (!project.includes("Build234FeedbackTests.swift in Sources")) {
  errors.push("AppTests Build234 (Build234FeedbackTests) têm de estar no target.");
}
if (!project.includes("Build238FeedbackTests.swift in Sources")) {
  errors.push("AppTests Build238 (Build238FeedbackTests) têm de estar no target.");
}
if (!project.includes("NotificationsCenterViewModel.swift in Sources") || !project.includes("NotificationsCenterViewController.swift in Sources")) {
  errors.push("Notifications Center (ViewModel + ViewController) tem de estar no target App.");
}

{
  const testsDir = join(root, "ios/App/KatecheoTests");
  for (const name of readdirSync(testsDir)) {
    if (!name.endsWith(".swift")) continue;
    const body = readFileSync(join(testsDir, name), "utf8");
    if (body.includes("@testable import App") || !body.includes("@testable import Katecheo")) {
      // Allow files that don't import the app module (none today) only if no testable import.
      if (/@testable\s+import\s+\w+/.test(body) && !body.includes("@testable import Katecheo")) {
        errors.push(`${name}: use @testable import Katecheo (módulo = PRODUCT_NAME).`);
      }
      if (body.includes("@testable import App")) {
        errors.push(`${name}: @testable import App inválido após rename — use Katecheo.`);
      }
    }
  }
}

if (!project.includes("NotificationsCenterTests.swift in Sources")) {
  errors.push("AppTests NotificationsCenterTests têm de estar no target.");
}
if (!project.includes("KCActivityStore.swift in Sources")) {
  errors.push("KCActivityStore tem de estar no target App (build-238 dots).");
}
if (!project.includes("KCActivitySync.swift in Sources")) {
  errors.push("KCActivitySync tem de estar no target App (build-238 inbox sync).");
}
if (!project.includes("NativeSWR.swift in Sources")) {
  errors.push("NativeSWR tem de estar no target App (SWR cache / load reduction).");
}
try {
  const swr = read("ios/App/Katecheo/NativeSWR.swift");
  const api = read("ios/App/Katecheo/NativeAPIClient.swift");
  if (!swr.includes("stale-while-revalidate") && !swr.includes("TTL")) {
    errors.push("NativeSWR precisa de TTLs SWR.");
  }
  if (!api.includes("listNotes(force: Bool = false)") || !api.includes("getPrefs(force: Bool = false)")) {
    errors.push("NativeAPIClient GETs precisam de force/SWR (listNotes/getPrefs/…).");
  }
  if (!read("ios/App/Katecheo/KCActivitySync.swift").includes("skippedFresh")) {
    errors.push("KCActivitySync tem de debouncear refresh (skippedFresh).");
  }
} catch {
  errors.push("Falha ao validar NativeSWR / activity debounce.");
}
if (!project.includes("FriendsActivityViewController.swift in Sources")) {
  errors.push("FriendsActivityViewController tem de estar no target App (build-238).");
}
try {
  const detail = read("ios/App/Katecheo/NoteDetailViewController.swift");
  if (detail.includes("next.tags = note.tags")) {
    errors.push("NoteDetail não pode sobrescrever tags do editor com note.tags (build-238).");
  }
  if (!detail.includes("keepEditorInLightMode") && !read("ios/App/Katecheo/AppAppearance.swift").includes("keepEditorInLightMode")) {
    errors.push("Falta preferência keepEditorInLightMode (build-238).");
  }
  const appearance = read("ios/App/Katecheo/AppAppearance.swift");
  if (!appearance.includes("keepEditorLightKey") || !appearance.includes("keepEditorInLightMode")) {
    errors.push("AppAppearance tem de persistir keepEditorInLightMode (build-238).");
  }
  const notebook = read("ios/App/Katecheo/NotebookListViewController.swift");
  if (!notebook.includes("KCConfirmation.presentActionSheet") || !notebook.includes("rectForRow")) {
    errors.push("Confirmação de exclusão de nota tem de ancorar no row/swipe via KCConfirmation (build-238).");
  }
  const groups = read("ios/App/Katecheo/GroupsListViewController.swift");
  if (!groups.includes("rectForRow") && !groups.includes("source.bounds")) {
    errors.push("Confirmação de exclusão de grupo tem de ancorar no row/swipe (build-238).");
  }
  const lists = read("ios/App/Katecheo/VersesScreens.swift");
  if (!lists.includes("translatesAutoresizingMaskIntoConstraints = true") || !lists.includes("MyCollectionsViewController")) {
    errors.push("Listas empty state tem de usar autoresizing backgroundView (build-238).");
  }
  const tools = read("ios/App/Katecheo/VersesHomeViewController.swift");
  if (!tools.includes("hidesSearchBarWhenScrolling") || !tools.includes("installSearchController")) {
    errors.push("Ferramentas Temas/Leitura: search no parent com hidesSearchBarWhenScrolling (build-238).");
  }
  const activity = read("ios/App/Katecheo/KCActivityStore.swift");
  if (!activity.includes("sharedNote") || !activity.includes("Compartilhadas") && !activity.includes("shared")) {
    // soft — shared kind exists
  }
  if (!activity.includes("reconcileServer") || !activity.includes("markSharedNoteOpened")) {
    errors.push("KCActivityStore tem de reconciliar via servidor (links/grants/inbox) (build-238).");
  }
  if (!activity.includes("acknowledgeNotificationIds") || !activity.includes("acknowledgeAllInboxNotifications")) {
    errors.push("KCActivityStore tem de limpar dots ao ler na Central de notificações (notificationIds).");
  }
  const notebookNotify = read("ios/App/Katecheo/NotebookListViewController.swift");
  if (!notebookNotify.includes("KCNotificationsBellButton") || !notebookNotify.includes("openNotificationsCenter")) {
    errors.push("Caderno tem de ter o botão de avisos (bell) só no tab pessoal.");
  }
  const notifyVm = read("ios/App/Katecheo/NotificationsCenterViewModel.swift");
  if (!notifyVm.includes("badgeText") || !notifyVm.includes("99+")) {
    errors.push("Badge de avisos tem de esconder em 0 e limitar a 99+.");
  }
  if (activity.includes("visibility == \"shared\"") || activity.includes("visibility == \"link\"")) {
    errors.push("KCActivityStore não pode inventar Shared a partir de visibility (build-238).");
  }
  const api = read("ios/App/Katecheo/NativeAPIClient.swift");
  if (!api.includes("notes/granted") || !api.includes("links/accept") || !api.includes("notifications/read")) {
    errors.push("NativeAPIClient tem de chamar notes/granted, links accept/decline e notifications/read (build-238).");
  }
  if (!api.includes("links/request") || !api.includes("links/search") || !api.includes("notifications/summary")) {
    errors.push("NativeAPIClient tem de chamar links/request, links/search e notifications/summary (build-238 limits).");
  }
  if (!api.includes("func deleteNotification") || !api.includes("notifications/clear") || !api.includes("func clearNotifications")) {
    errors.push("NativeAPIClient tem de apagar avisos (DELETE notifications/:id + clear).");
  }
  const notifyCenter = read("ios/App/Katecheo/NotificationsCenterViewController.swift");
  if (!notifyCenter.includes("Limpar tudo") || !notifyCenter.includes("deleteNotification") || !notifyCenter.includes("Excluir")) {
    errors.push("Avisos tem de ter swipe Excluir e Limpar tudo com confirmação.");
  }
  if (!notifyCenter.includes("checkmark.circle") || !notifyCenter.includes("systemName: \"trash\"")) {
    errors.push("Avisos Mark all / Clear all têm de ser botões de ícone SF Symbol (não texto).");
  }
  const emptyState = read("ios/App/Katecheo/KCComponents.swift");
  if (!emptyState.includes("stopIconAnimation") || !/func show\([\s\S]*stopIconAnimation/.test(emptyState)) {
    errors.push("KCEmptyStateView.show tem de parar a animação de loading (empty state estático).");
  }
  if (!read("ios/App/Katecheo/LocalGroupNotesCache.swift").includes("clearAll")) {
    errors.push("LocalGroupNotesCache.clearAll obrigatório (cache de notas do grupo).");
  }
  if (!project.includes("LocalGroupNotesCache.swift in Sources")) {
    errors.push("LocalGroupNotesCache.swift tem de estar no target App.");
  }
  if (!project.includes("GroupNotesCacheTests.swift in Sources")) {
    errors.push("GroupNotesCacheTests.swift tem de estar no target KatecheoTests.");
  }
  if (!api.includes("listGroupNotes") || !api.includes("If-None-Match") || !api.includes("updatedSince")) {
    errors.push("listGroupNotes tem de usar If-None-Match / updatedSince (SWR do grupo).");
  }
  if (!notifyVm.includes("func deleteNotification") || !notifyVm.includes("func clearAll")) {
    errors.push("NotificationsCenterViewModel tem de apagar/limpar com UI otimista.");
  }
  if (!api.includes("links/remove") || !api.includes("func removeLink")) {
    errors.push("NativeAPIClient tem de chamar links/remove (unfriend).");
  }
  const friends = read("ios/App/Katecheo/FriendsActivityViewController.swift");
  if (!friends.includes("acceptLink") || !friends.includes("declineLink") || !friends.includes("requestLink")) {
    errors.push("Amigos tem de pedir/aceitar/recusar via API nativa (build-238).");
  }
  if (!friends.includes("removeLink") || !friends.includes("incomingAccessory")) {
    errors.push("Amigos tem de ter Aceitar/Recusar inline e removeLink (unfriend).");
  }
  const push = read("ios/App/Katecheo/NativePushService.swift");
  if (push.includes("ingestPush") && !push.includes("handlePushHint") && !push.includes("refreshFromServer")) {
    errors.push("Push não pode acender bolinha sem reconciliar servidor (build-238).");
  }
  if (!read("ios/App/Katecheo/KCActivitySync.swift").includes("handlePushHint")) {
    errors.push("KCActivitySync.handlePushHint obrigatório (build-238).");
  }
  if (friends.includes("markFriendsAcceptedSeen") && friends.includes("clearKind(.friendPending)")) {
    // pending must not clear on appear — only accepted signals
    if (/viewWillAppear[\s\S]*clearKind\(\.friendPending\)/.test(friends) || /viewDidLoad[\s\S]*clearKind\(\.friendPending\)/.test(friends)) {
      errors.push("Amigos não pode limpar pedidos pendentes só por abrir a tela (build-238).");
    }
  }
  const notebookShared = read("ios/App/Katecheo/NotebookListViewController.swift");
  if (notebookShared.includes("visibility == \"shared\"") || notebookShared.includes("visibility == \"link\"")) {
    errors.push("Compartilhadas tem de usar listGrantedNotes, não visibility heuristic (build-238).");
  }
  if (notebookShared.includes("Shared with me") || notebookShared.includes("Compartilhadas comigo")) {
    errors.push("Não criar secção duplicada Shared with me — reutilizar Compartilhadas (build-238).");
  }
  if (!notebookShared.includes("LocalGroupNotesCache") || !notebookShared.includes("groupNotesAwaitingFirstPaint")) {
    errors.push("NotebookList (grupo) tem de pintar cache local antes do fetch.");
  }
} catch {
  errors.push("Falha ao validar checks build-238.");
}
try {
  const noteDetail = read("ios/App/Katecheo/NoteDetailViewController.swift");
  if (!noteDetail.includes("applyEditorChrome") || !noteDetail.includes("background: KCDesign.canvas")) {
    errors.push("NoteDetail tem de pintar nav standard/scrollEdge/compact com KCDesign.canvas (build-234).");
  }
  const codec = read("ios/App/Katecheo/NoteDocumentCodec.swift");
  if (!codec.includes("final class BibleRefPillAttachment") || !codec.includes("renderedInterfaceStyle")) {
    errors.push("BibleRefPillAttachment tem de existir com renderedInterfaceStyle (build-234).");
  }
  {
    const pillChunk = (codec.split("final class BibleRefPillAttachment")[1] || "").split("extension UIColor")[0] || "";
    const boundsChunk = (pillChunk.split("func attachmentBounds")[1] || "").split("override func image")[0] || "";
    if (boundsChunk.includes("UITraitCollection.current")) {
      errors.push("BibleRefPillAttachment.attachmentBounds não pode re-bakear com UITraitCollection.current (build-234).");
    }
    if (!pillChunk.includes("palette(") || !pillChunk.includes("alwaysOriginal")) {
      errors.push("BibleRefPillAttachment tem de bakear alwaysOriginal com palette RGB fixa (build-234).");
    }
  }
  const editor = read("ios/App/Katecheo/NativeNoteEditorView.swift");
  if (!editor.includes("refreshBibleRefPillAppearances")) {
    errors.push("NativeNoteEditorView tem de refreshBibleRefPillAppearances (build-234).");
  }
  const chrome = read("ios/App/Katecheo/KCComponents.swift");
  if (!chrome.includes("kcApplyThemedGroupedCell") || !chrome.includes("kcApplyGroupedChrome")) {
    errors.push("Profile/settings cells têm de usar kcApplyThemedGroupedCell + kcApplyGroupedChrome (build-234).");
  }
  const settings = read("ios/App/Katecheo/ProfileSettingsScreens.swift");
  for (const cls of [
    "ProfileEditViewController",
    "ProfileThemeViewController",
    "ProfileLanguageViewController",
    "ProfileBibleViewController",
    "ProfileNotifyViewController",
  ]) {
    if (!settings.includes(cls)) {
      errors.push(`Falta ${cls} (build-234 Profile audit).`);
    }
  }
  if (!settings.includes("kcApplyGroupedChrome") || !settings.includes("kcApplyThemedGroupedCell")) {
    errors.push("ProfileSettingsScreens têm de aplicar chrome/células themed (build-234).");
  }
} catch {
  errors.push("Falha ao validar checks build-234.");
}

const authRouter = read("src/lib/native/api/v1-router.ts");
if (!authRouter.includes("auth-claim") || !authRouter.includes("auth-email") || !authRouter.includes("auth-apple")) {
  errors.push("Faltam rotas /api/native/v1/auth/* (claim/email/apple).");
}
if (!authRouter.includes("group-notes") || !authRouter.includes('"groups"')) {
  errors.push("Faltam rotas /api/native/v1/groups* no router nativo.");
}
if (!authRouter.includes("group-members")) {
  errors.push("Faltam rotas /api/native/v1/groups/:id/members* no router nativo.");
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

const apiClient = read("ios/App/Katecheo/NativeAPIClient.swift");
if (!apiClient.includes("func getMe(") || !apiClient.includes("func deleteAccount(")) {
  errors.push("NativeAPIClient tem de expor getMe e deleteAccount.");
}
if (!apiClient.includes("listGroupMembers") || !apiClient.includes("decideGroupMember")) {
  errors.push("NativeAPIClient tem de expor listGroupMembers / decideGroupMember.");
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
  "ios/App/Katecheo.xcodeproj/xcshareddata/xcschemes/Katecheo.xcscheme",
  "docs/ios-native-migration.md",
  "docs/ios-phase5-webview.md",
  "docs/ios-phase7-native-editor.md",
  "docs/note-document-v1.md",
  "migrations/0021_note_blocks_backup.sql",
  "ios/App/Katecheo/NotebookListViewController.swift",
  "ios/App/Katecheo/NoteDetailViewController.swift",
  "ios/App/Katecheo/NativeNoteEditorView.swift",
  "ios/App/Katecheo/NoteDocumentCodec.swift",
  "ios/App/Katecheo/BibleRefInsertPicker.swift",
  "ios/App/Katecheo/AppRoot.swift",
  "ios/App/Katecheo/NativeSignInViewController.swift",
  "ios/App/Katecheo/NativeLoginService.swift",
  "ios/App/Katecheo/NativeSessionBootstrap.swift",
  "ios/App/Katecheo/NativePushService.swift",
  "ios/App/Katecheo/NativeDeepLinkRouter.swift",
  "ios/App/Katecheo/ProfileViewController.swift",
  "ios/App/Katecheo/ProfileSettingsScreens.swift",
  "ios/App/Katecheo/VersesHomeViewController.swift",
  "ios/App/Katecheo/VersesScreens.swift",
  "ios/App/Katecheo/ReadingScreens.swift",
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
  "ios/App/Katecheo/Localizable.xcstrings",
  "ios/App/Katecheo/InfoPlist.xcstrings",
  "ios/App/Katecheo/AppLocale.swift",
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
if (!project.includes("AppSite.swift in Sources")) {
  errors.push("AppSite.swift tem de estar no target Xcode (Katecheo base URL + fallback).");
}

// Katecheo rebrand: no user-visible "Verse2Note" / "Verse 2 Note" remains in iOS UI surfaces.
// Allowed: bundle id com.verse2note.*, Info.plist Katecheo* keys, katecheo.* internals,
// legacy web outbox key verse2note-outbox, comments/tests.
{
  const brandNeedle = /Verse\s*2\s*Note/i;
  const allowLine =
    /com\.verse2note|katecheo:\/\/|callbackURLScheme:\s*"katecheo"|customScheme\("katecheo"\)|scheme == "katecheo"|<string>katecheo<\/string>|CFBundleURLSchemes|KatecheoAPIBase|KatecheoApns|KatecheoUniversal|KatecheoNative|katecheo\.(native|legacy|cookie|apns|apiBase|activity|notifications|appearance|swr|catalog|session|ferramentas|booksCompact|copyLocale|cite)|verse2note-outbox|PRODUCT_BUNDLE_IDENTIFIER|KATECHEO_|Notification\.Name\("katecheo|defaultsKey|statusKey|migratedFlagKey|infoPlistKey|acceptedHosts|verse2note\.com|www\.verse2note\.com|temporaryDirectory\.appendingPathComponent\("katecheo-|\/\/|\/\*|\* /;

  const scanFiles = (dir, pred) => {
    /** @type {string[]} */
    const out = [];
    const walk = (d) => {
      let entries;
      try {
        entries = readdirSync(d, { withFileTypes: true });
      } catch {
        return;
      }
      for (const ent of entries) {
        const full = join(d, ent.name);
        if (ent.isDirectory()) {
          if (/(^|\/)(DerivedData|build|\.git)$/i.test(ent.name)) continue;
          walk(full);
          continue;
        }
        if (!pred(ent.name)) continue;
        out.push(full);
      }
    };
    walk(dir);
    return out;
  };

  const appRoot = join(root, "ios/App/Katecheo");
  const uiFiles = scanFiles(
    appRoot,
    (name) => /\.(swift|plist|xcstrings|storyboard|strings|intentdefinition|json)$/i.test(name),
  );
  /** @type {string[]} */
  const brandHits = [];
  for (const full of uiFiles) {
    const rel = full.slice(root.length + 1);
    // Bundle / project identifiers live in Info.plist keys — still scan values carefully.
    let text;
    try {
      text = readFileSync(full, "utf8");
    } catch {
      continue;
    }
    const lines = text.split(/\r?\n/);
    lines.forEach((line, idx) => {
      if (!brandNeedle.test(line)) return;
      if (allowLine.test(line)) return;
      // brandNeedle is Verse2Note specifically (MCP tools are katecheo_*).
      brandHits.push(`${rel}:${idx + 1}:${line.trim().slice(0, 120)}`);
    });
  }

  // Display name must be Katecheo in InfoPlist catalog + Info.plist.
  try {
    const infoCatalog = JSON.parse(read("ios/App/Katecheo/InfoPlist.xcstrings"));
    for (const key of ["CFBundleDisplayName", "CFBundleName"]) {
      for (const lang of ["pt-BR", "en", "es"]) {
        const value = infoCatalog.strings?.[key]?.localizations?.[lang]?.stringUnit?.value;
        if (value !== "Katecheo") {
          errors.push(`InfoPlist.xcstrings ${key}/${lang} tem de ser "Katecheo" (é ${JSON.stringify(value)}).`);
        }
      }
    }
  } catch {
    errors.push("InfoPlist.xcstrings ilegível para o rebrand Katecheo.");
  }
  const infoPlist = read("ios/App/Katecheo/Info.plist");
  if (!infoPlist.includes("<string>Katecheo</string>")) {
    errors.push('Info.plist CFBundleDisplayName tem de ser "Katecheo".');
  }
  if (!infoPlist.includes("<string>katecheo</string>")) {
    errors.push('Info.plist tem de registar o URL scheme katecheo.');
  }
  if (infoPlist.includes("<string>verse2note</string>")) {
    errors.push("Info.plist não pode manter o URL scheme verse2note.");
  }

  const site = read("ios/App/Katecheo/AppSite.swift");
  if (!site.includes("katecheo.app") || site.includes("verse2note.com") || !site.includes('primaryHost = "katecheo.app"')) {
    errors.push("AppSite.swift: só katecheo.app (sem fallback verse2note.com).");
  }
  if (site.includes("fallbackHost") || site.includes("fallbackOrigin")) {
    errors.push("AppSite.swift: remova fallbackHost/fallbackOrigin.");
  }
  const api = read("ios/App/Katecheo/NativeAPIClient.swift");
  if (!api.includes("AppSite.baseURL")) {
    errors.push("NativeAPIClient tem de usar AppSite.baseURL.");
  }
  if (api.includes("fallbackOrigin") || api.includes("comps.host = fallbackHost")) {
    errors.push("NativeAPIClient não pode retry em verse2note.com.");
  }

  if (brandHits.length) {
    errors.push(
      "Rebrand Katecheo: string user-visible ainda contém Verse2Note (bundle id / ids internos OK). Hits:\n  - " +
        brandHits.slice(0, 30).join("\n  - ") +
        (brandHits.length > 30 ? `\n  - … +${brandHits.length - 30} more` : ""),
    );
  }
}

// Build 256: Tools tab must localize via String(localized:) + Localizable en/es (not raw PT titleText).
{
  const toolsFiles = [
    "ios/App/Katecheo/NativeRootTabBarController.swift",
    "ios/App/Katecheo/VersesHomeViewController.swift",
  ];
  for (const rel of toolsFiles) {
    const src = read(rel);
    if (src.includes('titleText: "Ferramentas"') || src.includes('title = "Ferramentas"')) {
      errors.push(`${rel}: use String(localized: "Ferramentas") — never a hardcoded tab/title literal.`);
    }
    if (!src.includes('String(localized: "Ferramentas")')) {
      errors.push(`${rel}: tab/title Ferramentas tem de usar String(localized:).`);
    }
  }
  try {
    const catalog = JSON.parse(read("ios/App/Katecheo/Localizable.xcstrings"));
    const allKeys = Object.keys(catalog.strings || {});
    if (allKeys.length < 700) {
      errors.push(
        `Localizable.xcstrings encolheu (${allKeys.length} chaves); o gerador/ios-check não podem apagar strings existentes.`,
      );
    }
    for (const key of [
      "Aceitar ou recusar este pedido de amizade?",
      "Cancelar pedido",
      "Buscar por @usuário",
      "Copiar",
      "Comece a escrever…",
      "ARC — Almeida Revista e Corrigida",
      "Sair",
      "Esqueci minha senha",
      "Enviar código",
      "Reenviar código",
    ]) {
      if (!catalog.strings?.[key]) {
        errors.push(`Localizable.xcstrings tem de manter a chave ${JSON.stringify(key)}.`);
      }
    }
    if (catalog.strings?.Sair?.localizations?.en?.stringUnit?.value !== "Sign out") {
      errors.push('Localizable.xcstrings «Sair»/en tem de continuar "Sign out".');
    }
    const ferr = catalog.strings?.Ferramentas?.localizations || {};
    for (const lang of ["pt-BR", "en", "es"]) {
      const value = ferr[lang]?.stringUnit?.value;
      if (typeof value !== "string" || !value) {
        errors.push(`Localizable.xcstrings: Ferramentas sem tradução ${lang}.`);
      }
    }
    if (ferr.en?.stringUnit?.value !== "Tools") {
      errors.push('Localizable.xcstrings: Ferramentas/en tem de ser "Tools".');
    }
  } catch {
    errors.push("Não foi possível ler Localizable.xcstrings para a chave Ferramentas.");
  }
  const genL10n = read("scripts/generate-ios-l10n.mjs");
  if (!genL10n.includes("mergeCatalog") || !genL10n.includes("refused to shrink")) {
    errors.push("generate-ios-l10n.mjs tem de fazer merge-only (nunca apagar chaves do Localizable).");
  }
  if (!project.includes("BibleBooksData.json in Resources")) {
    errors.push("BibleBooksData.json tem de estar nos Resources (catálogo bíblico permanente).");
  }
  if (!project.includes("NativeCatalogSync.swift in Sources")) {
    errors.push("NativeCatalogSync.swift tem de estar no target (Themes/Reading version + silent push).");
  }
  const apiClient = read("ios/App/Katecheo/NativeAPIClient.swift");
  if (!apiClient.includes("catalog/versions") || !apiClient.includes("loadBundledBibleBooks")) {
    errors.push("NativeAPIClient: catalog/versions + bundled bible books são obrigatórios (build 256).");
  }
  const swr = read("ios/App/Katecheo/NativeSWR.swift");
  if (
    !swr.includes("bibleBooksBundleVersion") ||
    !/static let bibleBooks:\s*TimeInterval\s*=\s*\.greatestFiniteMagnitude/.test(swr)
  ) {
    errors.push("NativeSWR: bible books TTL tem de ser permanente (greatestFiniteMagnitude).");
  }
  const catalogPush = read("src/lib/catalog-push.server.ts");
  if (!catalogPush.includes("themes_updated") || !catalogPush.includes("reading_updated")) {
    errors.push("catalog-push.server: themes_updated / reading_updated silenciosos.");
  }
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

// Katecheo does not track users. PR #72 wrongly added NSUserTrackingUsageDescription
// to InfoPlist.xcstrings (without Info.plist / without ATT APIs) → ITMS-90683 on upload.
// Ban ATT symbols and orphaned tracking purpose strings so ASC stays clean.
{
  const attNeedle =
    /AppTrackingTransparency|ATTrackingManager|requestTrackingAuthorization|ASIdentifierManager|advertisingIdentifier|NSUserTrackingUsageDescription/;
  const scanRoots = [
    "ios/App/Katecheo",
    "ios/App/KatecheoTests",
    "ios/App/CapApp-SPM",
    "ios/App/Katecheo.xcodeproj",
    "scripts",
  ];
  const skipName = /(^|\/)(node_modules|\.git|DerivedData|build)(\/|$)/;
  /** @type {string[]} */
  const hits = [];
  const walk = (dir) => {
    let entries;
    try {
      entries = readdirSync(dir, { withFileTypes: true });
    } catch {
      return;
    }
    for (const ent of entries) {
      const full = join(dir, ent.name);
      if (skipName.test(full)) continue;
      if (ent.isDirectory()) {
        walk(full);
        continue;
      }
      if (!/\.(swift|m|h|mm|plist|pbxproj|xcstrings|xcconfig|mjs|js|json|md)$/i.test(ent.name)) continue;
      let text;
      try {
        text = readFileSync(full, "utf8");
      } catch {
        continue;
      }
      if (attNeedle.test(text)) {
        hits.push(full.slice(root.length + 1));
      }
    }
  };
  for (const rel of scanRoots) walk(join(root, rel));
  // Allow this guard itself to mention the needles.
  const allowed = new Set(["scripts/ios-check.mjs"]);
  const bad = hits.filter((h) => !allowed.has(h));
  if (bad.length) {
    errors.push(
      "App Tracking Transparency / NSUserTrackingUsageDescription proibido (Katecheo não rastreia). Remova a referência — não adicione purpose string. Hits: " +
        bad.join(", "),
    );
  }
}

if (notes.length) console.log(notes.join("\n"));
if (errors.length) {
  console.error(errors.join("\n"));
  process.exit(1);
}
console.log("ios-check: projeto iOS coerente (Phase 7 — editor nativo; sem Cap host / miolo WebView).");
