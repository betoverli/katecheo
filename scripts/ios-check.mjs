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
if (!scene.includes("AppAppearance") || scene.includes("overrideUserInterfaceStyle = .unspecified")) {
  errors.push("SceneDelegate tem de aplicar AppAppearance no connect (não forçar .unspecified) — TF219.");
}
try {
  const appearance = read("ios/App/App/AppAppearance.swift");
  if (!appearance.includes("overrideUserInterfaceStyle") || !appearance.includes("storedTheme") || !appearance.includes("syncFromCacheAndApply")) {
    errors.push("AppAppearance tem de persistir o tema e pintar todos os UIWindow (TF219).");
  }
} catch {
  errors.push("Falta AppAppearance.swift (TF219).");
}
if (!project.includes("AppAppearance.swift in Sources")) {
  errors.push("AppAppearance.swift tem de estar no target Xcode.");
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

const codec = read("ios/App/App/NoteDocumentCodec.swift");
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
  const speakerEdit = read("ios/App/App/SpeakerSectionEditing.swift");
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
  const header = read("ios/App/App/SpeakerHeaderAttachment.swift");
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
  errors.push("AppTests têm de exercer o caminho real NativeNoteEditorView/UITextView (NativeNoteEditorSpeakerPathTests).");
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
  const settings = read("ios/App/App/NoteSettingsViewController.swift");
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
  const api = read("ios/App/App/NativeAPIClient.swift");
  const spanIdx = api.indexOf("private func spanText");
  const spanText = spanIdx >= 0 ? api.slice(spanIdx, spanIdx + 450) : "";
  if (!spanText.includes('span.type == "bibleRef"') || !spanText.includes("return nil")) {
    errors.push("NativeAPIClient.preview/spanText tem de saltar bibleRef (só texto plano).");
  }
} catch {
  errors.push("Falta NativeAPIClient.swift");
}
try {
  const cache = read("ios/App/App/LocalNoteCache.swift");
  if (!cache.includes("mergeSpeakers") || !cache.includes("removeSpeaker")) {
    errors.push("LocalNoteCache tem de mergeSpeakers (não apagar o catálogo com speakers note-scoped).");
  }
} catch {
  errors.push("Ficheiro em falta: ios/App/App/LocalNoteCache.swift");
}
if (!editor.includes("confirmRemoveSpeakerSection") || !editor.includes("Remover seção do speaker?")) {
  errors.push("× do speaker tem de pedir confirmação localizada antes de apagar.");
}
if (!project.includes("V2NSheetPresenter.swift in Sources")) {
  errors.push("V2NSheetPresenter tem de estar no target (dismiss por backdrop).");
}
try {
  const sheet = read("ios/App/App/V2NSheetPresenter.swift");
  if (!sheet.includes("isModalInPresentation = false") || !sheet.includes(".medium()")) {
    errors.push("V2NSheetPresenter tem de permitir dismiss por fora (medium detent + não modal-in-presentation).");
  }
} catch {
  errors.push("Falta V2NSheetPresenter.swift");
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
if (!project.includes("AppTests") || !project.includes("NoteDocumentCodecTests.swift in Sources")) {
  errors.push("Target AppTests com round-trip do codec tem de existir no Xcode project.");
}
if (!codec.includes("BibleBookCatalog.formatPassage") || !project.includes("BibleBookCatalog.swift in Sources")) {
  errors.push("Referências nas notas têm de formatar nomes via BibleBookCatalog (idioma de referências).");
}
const biblePicker = read("ios/App/App/BibleRefInsertPicker.swift");
if (!biblePicker.includes("V2NNumberCell") || !biblePicker.includes("V2NNumberGridLayout") || biblePicker.includes("UITableViewController")) {
  errors.push("Picker de referência na nota tem de usar grelha (V2NNumberCell), não lista.");
}

const noteDetail = read("ios/App/App/NoteDetailViewController.swift");
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
if (!notebookList.includes("v2nIconOnly") || !notebookList.includes("leadingSwipeActions")) {
  errors.push("Swipe do Caderno tem de ser só ícone (v2nIconOnly) em leading/trailing.");
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

const rootTabs = read("ios/App/App/NativeRootTabBarController.swift");
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
  /V2NFilterChip\(id:\s*"themes"/.test(notebookList) ||
  /V2NFilterChip\(id:\s*"lists"/.test(notebookList)
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
  errors.push("V2NFilterChipsView: ícone só quando não selecionado; ícone+nome quando selecionado.");
}
if (!components.includes("leading: horizontal") || !/selected \? 16 : 24/.test(components) || !components.includes("greaterThanOrEqualToConstant: 72")) {
  errors.push("Pills não selecionadas têm de ser cápsulas largas (padding ≥24 / min width 72).");
}
if (!components.includes("v2nApplyBrandListStyle") || !components.includes("v2nApplyBrandChrome")) {
  errors.push("Temas/Listas têm de usar helpers de marca (sem tint azul de sistema).");
}
const versesScreens = read("ios/App/App/VersesScreens.swift");
if (!versesScreens.includes("v2nApplyBrandListStyle") || !versesScreens.includes("V2NEmptyStateView") || !versesScreens.includes("V2NDesign.accent")) {
  errors.push("Temas e Listas têm de usar empty states e tint de marca.");
}
if (!project.includes("LocalSessionCache.swift in Sources") || !project.includes("GroupMembersViewController.swift in Sources")) {
  errors.push("LocalSessionCache / GroupMembersViewController têm de estar no target Xcode.");
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
  if (!versesHome.includes("Ferramentas") || !versesHome.includes("BooksHomeViewController")) {
    errors.push("Ferramentas: home com pills + BooksHomeViewController.");
  }
  if (versesHome.includes("V2NToolCardCell") || versesHome.includes("cardsPanel")) {
    errors.push("Remova o hub de cards legado da Ferramentas — abrir direto na pill.");
  }
  if (!versesHome.includes("ThemesHomeViewController") || !versesHome.includes("ReadingHomeViewController") || !versesHome.includes("MyCollectionsViewController")) {
    errors.push("Ferramentas tem de abrir Temas, Listas e Leitura.");
  }
  if (!versesHome.includes("V2NFilterChipsView") || !versesHome.includes("chips.configure")) {
    errors.push("Ferramentas tem de ter pills (V2NFilterChipsView) Livros/Temas/Listas/Leitura.");
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
    errors.push("V2NBookSectionHeaderView tem de aceitar trailing (Siglas/Nomes no scroll).");
  }
  if (!components.includes("V2NNamedCreateViewController") || !components.includes("V2NNumberCell") || !components.includes("V2NBibleAppLogoCell")) {
    errors.push("Faltam componentes: create form, number grid, bible logo tiles.");
  }
  const groupsListSync = read("ios/App/App/GroupsListViewController.swift");
  if (groupsListSync.includes("grupos · sincronizado")) {
    errors.push("Remova o banner persistente «grupos · sincronizado».");
  }
  const readingHome = read("ios/App/App/ReadingScreens.swift");
  if (!readingHome.includes("V2NPlanCategoryCardCell") || !readingHome.includes("UICollectionView")) {
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
  const versesScreens = read("ios/App/App/VersesScreens.swift");
  if (
    !versesScreens.includes("VerseActionsViewController") ||
    !versesScreens.includes("appendVerse") ||
    !versesScreens.includes("Adicionar à nota")
  ) {
    errors.push("Faltam telas nativas de ações de versículo / adicionar à nota.");
  }
  if (!versesScreens.includes("V2NNumberCell") || !versesScreens.includes("V2NNumberGridLayout")) {
    errors.push("Picker de capítulo/versículo tem de usar grelha numérica.");
  }
  if (!versesScreens.includes("V2NNamedCreateViewController")) {
    errors.push("Criar lista/tema tem de usar o formulário V2NNamedCreateViewController (sem alerta azul).");
  }
  if (/Partilhar|Guardar|utilizador|Definições/.test(versesScreens) || /Partilhar|Guardar|utilizador|Definições/.test(versesHome)) {
    errors.push("Strings de Ferramentas têm de ser pt-BR (não Partilhar/Guardar/utilizador/Definições).");
  }
  const bibleSettings = read("ios/App/App/ProfileSettingsScreens.swift");
  if (!bibleSettings.includes("V2NBibleAppLogoCell") || !bibleSettings.includes("BibleApp_")) {
    errors.push("App de Bíblia: grelha de logos (V2NBibleAppLogoCell + assets).");
  }
  if (!bibleSettings.includes("v2nApplyTabBarScrollClearance") || !bibleSettings.includes("tableHeaderView")) {
    errors.push("App de Bíblia: scroll único + clearance da tab bar (TF214).");
  }
  const design = read("ios/App/App/V2NDesign.swift");
  if (!design.includes("V2NScrollChrome") || !design.includes("tabBarClearance")) {
    errors.push("V2NScrollChrome tem de calcular inset inferior sob a tab bar flutuante.");
  }
  const speakerHeader = read("ios/App/App/SpeakerHeaderAttachment.swift");
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
  const codec = read("ios/App/App/NoteDocumentCodec.swift");
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
if (!project.includes("V2NScrollChromeTests.swift in Sources")) {
  errors.push("AppTests V2NScrollChromeTests têm de estar no target.");
}
if (!project.includes("V2NSwipeActionTests.swift in Sources")) {
  errors.push("AppTests V2NSwipeActionTests têm de estar no target.");
}
if (!project.includes("TabBackgroundConsistencyTests.swift in Sources")) {
  errors.push("AppTests TabBackgroundConsistencyTests têm de estar no target.");
}
try {
  const design = read("ios/App/App/V2NDesign.swift");
  if (!design.includes("screenBackground") || !design.includes("styleScreen") || !design.includes("makeNavigationBarAppearance")) {
    errors.push("V2NChrome tem de unificar screenBackground no nav + tabs (Profile-matched).");
  }
  if (design.includes("surface.withAlphaComponent(0.94)")) {
    errors.push("Nav bar não pode usar surface semi-opaco (banda mais clara que o conteúdo).");
  }
  const notebook = read("ios/App/App/NotebookListViewController.swift");
  const groups = read("ios/App/App/GroupsListViewController.swift");
  const tools = read("ios/App/App/VersesHomeViewController.swift");
  const profile = read("ios/App/App/ProfileViewController.swift");
  for (const [name, src] of [
    ["Notebook", notebook],
    ["Groups", groups],
    ["Tools", tools],
    ["Profile", profile],
  ]) {
    if (!src.includes("styleScreen")) {
      errors.push(`${name} tem de usar V2NChrome.styleScreen (fundo único como Perfil).`);
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
if (!project.includes("Build234FeedbackTests.swift in Sources")) {
  errors.push("AppTests Build234 (Build234FeedbackTests) têm de estar no target.");
}
if (!project.includes("Build238FeedbackTests.swift in Sources")) {
  errors.push("AppTests Build238 (Build238FeedbackTests) têm de estar no target.");
}
if (!project.includes("V2NActivityStore.swift in Sources")) {
  errors.push("V2NActivityStore tem de estar no target App (build-238 dots).");
}
if (!project.includes("V2NActivitySync.swift in Sources")) {
  errors.push("V2NActivitySync tem de estar no target App (build-238 inbox sync).");
}
if (!project.includes("FriendsActivityViewController.swift in Sources")) {
  errors.push("FriendsActivityViewController tem de estar no target App (build-238).");
}
try {
  const detail = read("ios/App/App/NoteDetailViewController.swift");
  if (detail.includes("next.tags = note.tags")) {
    errors.push("NoteDetail não pode sobrescrever tags do editor com note.tags (build-238).");
  }
  if (!detail.includes("keepEditorInLightMode") && !read("ios/App/App/AppAppearance.swift").includes("keepEditorInLightMode")) {
    errors.push("Falta preferência keepEditorInLightMode (build-238).");
  }
  const appearance = read("ios/App/App/AppAppearance.swift");
  if (!appearance.includes("keepEditorLightKey") || !appearance.includes("keepEditorInLightMode")) {
    errors.push("AppAppearance tem de persistir keepEditorInLightMode (build-238).");
  }
  const notebook = read("ios/App/App/NotebookListViewController.swift");
  if (!notebook.includes("anchorActionSheet") || !notebook.includes("rectForRow")) {
    errors.push("Confirmação de exclusão de nota tem de ancorar no row/swipe (build-238).");
  }
  const groups = read("ios/App/App/GroupsListViewController.swift");
  if (!groups.includes("rectForRow") && !groups.includes("source.bounds")) {
    errors.push("Confirmação de exclusão de grupo tem de ancorar no row/swipe (build-238).");
  }
  const lists = read("ios/App/App/VersesScreens.swift");
  if (!lists.includes("translatesAutoresizingMaskIntoConstraints = true") || !lists.includes("MyCollectionsViewController")) {
    errors.push("Listas empty state tem de usar autoresizing backgroundView (build-238).");
  }
  const tools = read("ios/App/App/VersesHomeViewController.swift");
  if (!tools.includes("hidesSearchBarWhenScrolling") || !tools.includes("installSearchController")) {
    errors.push("Ferramentas Temas/Leitura: search no parent com hidesSearchBarWhenScrolling (build-238).");
  }
  const activity = read("ios/App/App/V2NActivityStore.swift");
  if (!activity.includes("sharedNote") || !activity.includes("Compartilhadas") && !activity.includes("shared")) {
    // soft — shared kind exists
  }
  if (!activity.includes("reconcileServer") || !activity.includes("markSharedNoteOpened")) {
    errors.push("V2NActivityStore tem de reconciliar via servidor (links/grants/inbox) (build-238).");
  }
  if (activity.includes("visibility == \"shared\"") || activity.includes("visibility == \"link\"")) {
    errors.push("V2NActivityStore não pode inventar Shared a partir de visibility (build-238).");
  }
  const api = read("ios/App/App/NativeAPIClient.swift");
  if (!api.includes("notes/granted") || !api.includes("links/accept") || !api.includes("notifications/read")) {
    errors.push("NativeAPIClient tem de chamar notes/granted, links accept/decline e notifications/read (build-238).");
  }
  if (!api.includes("links/request") || !api.includes("links/search") || !api.includes("notifications/summary")) {
    errors.push("NativeAPIClient tem de chamar links/request, links/search e notifications/summary (build-238 limits).");
  }
  const friends = read("ios/App/App/FriendsActivityViewController.swift");
  if (!friends.includes("acceptLink") || !friends.includes("declineLink") || !friends.includes("requestLink")) {
    errors.push("Amigos tem de pedir/aceitar/recusar via API nativa (build-238).");
  }
  const push = read("ios/App/App/NativePushService.swift");
  if (push.includes("ingestPush") && !push.includes("handlePushHint") && !push.includes("refreshFromServer")) {
    errors.push("Push não pode acender bolinha sem reconciliar servidor (build-238).");
  }
  if (!read("ios/App/App/V2NActivitySync.swift").includes("handlePushHint")) {
    errors.push("V2NActivitySync.handlePushHint obrigatório (build-238).");
  }
  if (friends.includes("markFriendsAcceptedSeen") && friends.includes("clearKind(.friendPending)")) {
    // pending must not clear on appear — only accepted signals
    if (/viewWillAppear[\s\S]*clearKind\(\.friendPending\)/.test(friends) || /viewDidLoad[\s\S]*clearKind\(\.friendPending\)/.test(friends)) {
      errors.push("Amigos não pode limpar pedidos pendentes só por abrir a tela (build-238).");
    }
  }
  const notebookShared = read("ios/App/App/NotebookListViewController.swift");
  if (notebookShared.includes("visibility == \"shared\"") || notebookShared.includes("visibility == \"link\"")) {
    errors.push("Compartilhadas tem de usar listGrantedNotes, não visibility heuristic (build-238).");
  }
  if (notebookShared.includes("Shared with me") || notebookShared.includes("Compartilhadas comigo")) {
    errors.push("Não criar secção duplicada Shared with me — reutilizar Compartilhadas (build-238).");
  }
} catch {
  errors.push("Falha ao validar checks build-238.");
}
try {
  const noteDetail = read("ios/App/App/NoteDetailViewController.swift");
  if (!noteDetail.includes("applyEditorChrome") || !noteDetail.includes("background: V2NDesign.canvas")) {
    errors.push("NoteDetail tem de pintar nav standard/scrollEdge/compact com V2NDesign.canvas (build-234).");
  }
  const codec = read("ios/App/App/NoteDocumentCodec.swift");
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
  const editor = read("ios/App/App/NativeNoteEditorView.swift");
  if (!editor.includes("refreshBibleRefPillAppearances")) {
    errors.push("NativeNoteEditorView tem de refreshBibleRefPillAppearances (build-234).");
  }
  const chrome = read("ios/App/App/V2NComponents.swift");
  if (!chrome.includes("v2nApplyThemedGroupedCell") || !chrome.includes("v2nApplyGroupedChrome")) {
    errors.push("Profile/settings cells têm de usar v2nApplyThemedGroupedCell + v2nApplyGroupedChrome (build-234).");
  }
  const settings = read("ios/App/App/ProfileSettingsScreens.swift");
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
  if (!settings.includes("v2nApplyGroupedChrome") || !settings.includes("v2nApplyThemedGroupedCell")) {
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

const apiClient = read("ios/App/App/NativeAPIClient.swift");
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

// Verse2Note does not track users. PR #72 wrongly added NSUserTrackingUsageDescription
// to InfoPlist.xcstrings (without Info.plist / without ATT APIs) → ITMS-90683 on upload.
// Ban ATT symbols and orphaned tracking purpose strings so ASC stays clean.
{
  const attNeedle =
    /AppTrackingTransparency|ATTrackingManager|requestTrackingAuthorization|ASIdentifierManager|advertisingIdentifier|NSUserTrackingUsageDescription/;
  const scanRoots = [
    "ios/App/App",
    "ios/App/AppTests",
    "ios/App/CapApp-SPM",
    "ios/App/App.xcodeproj",
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
      "App Tracking Transparency / NSUserTrackingUsageDescription proibido (Verse2Note não rastreia). Remova a referência — não adicione purpose string. Hits: " +
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
