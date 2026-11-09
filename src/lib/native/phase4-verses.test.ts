import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { describe, it } from "node:test";
import { isPublicNativeAuthRoute, matchNativeV1Route, methodAllowed } from "./api/v1-router.ts";

const root = new URL("../../../", import.meta.url);

function read(rel: string) {
  return readFileSync(new URL(rel, root), "utf8");
}

describe("Phase 4 native verses API", () => {
  it("routes bible catalog, append, and my-collections", () => {
    assert.deepEqual(matchNativeV1Route("bible/books"), { kind: "bible-books" });
    assert.deepEqual(matchNativeV1Route("bible/apps"), { kind: "bible-apps" });
    assert.deepEqual(matchNativeV1Route("bible/link"), { kind: "bible-link" });
    assert.deepEqual(matchNativeV1Route("bible/themes"), { kind: "bible-themes" });
    assert.deepEqual(matchNativeV1Route("verses/append"), { kind: "verses-append" });
    assert.deepEqual(matchNativeV1Route("my-collections"), { kind: "my-collections" });
    assert.deepEqual(matchNativeV1Route("my-collections/save"), { kind: "my-collections-save" });
    assert.deepEqual(matchNativeV1Route("my-collections/abc"), {
      kind: "my-collections",
      collectionId: "abc",
    });
    assert.equal(methodAllowed({ kind: "bible-books" }, "GET"), true);
    assert.equal(methodAllowed({ kind: "bible-link" }, "POST"), true);
    assert.equal(methodAllowed({ kind: "bible-themes" }, "POST"), false);
    assert.equal(methodAllowed({ kind: "verses-append" }, "POST"), true);
    assert.equal(methodAllowed({ kind: "my-collections" }, "GET"), true);
    assert.equal(methodAllowed({ kind: "my-collections" }, "POST"), true);
    assert.equal(methodAllowed({ kind: "my-collections", collectionId: "x" }, "DELETE"), true);
    assert.equal(methodAllowed({ kind: "my-collections-save" }, "POST"), true);
  });

  it("marks bible catalog public and append private", () => {
    assert.equal(isPublicNativeAuthRoute({ kind: "bible-books" }), true);
    assert.equal(isPublicNativeAuthRoute({ kind: "bible-apps" }), true);
    assert.equal(isPublicNativeAuthRoute({ kind: "bible-link" }), true);
    assert.equal(isPublicNativeAuthRoute({ kind: "bible-themes" }), true);
    assert.equal(isPublicNativeAuthRoute({ kind: "verses-append" }), false);
    assert.equal(isPublicNativeAuthRoute({ kind: "my-collections" }), false);
  });

  it("ships verses server + HTTP dispatch + catalog with NoteDocumentV1 refs", () => {
    const verses = read("src/lib/native/api/v1-verses.server.ts");
    assert.match(verses, /appendVerseForUser/);
    assert.match(verses, /listBibleBooks/);
    assert.match(verses, /resolveNativeThemes/);
    assert.match(verses, /savePassageToCollectionForUser/);
    assert.match(verses, /appendPassageToBlocks/);
    assert.match(verses, /noteToDocument/);
    const books = read("src/lib/bible/books.ts");
    assert.match(books, /"id": "JHN"/);
    assert.match(books, /"pt": "João"/);
    const http = read("src/lib/native/api/v1-http.ts");
    assert.match(http, /v1-verses\.server/);
    assert.match(http, /verses-append/);
    assert.match(http, /bible-themes/);
    // Optional CDN-friendly caching for the auth-free static catalog.
    assert.match(http, /bible-books[\s\S]*Cache-Control[\s\S]*max-age=86400/);
    assert.match(http, /ETag[\s\S]*bible-books-v1/);
    const catalog = read("src/lib/native/api/v1.server.ts");
    assert.match(catalog, /\/bible\/books/);
    assert.match(catalog, /\/verses\/append/);
    assert.match(catalog, /\/my-collections/);
    const doc = read("src/lib/native/api/note-document.ts");
    assert.match(doc, /type: "bibleRef"/);
  });
});

describe("Phase 4 native Versículos / Ferramentas UI", () => {
  it("hosts Tools tab with VersesHomeViewController and Books grid", () => {
    const tabs = read("ios/App/App/NativeRootTabBarController.swift");
    assert.match(tabs, /VersesHomeViewController/);
    assert.match(tabs, /Ferramentas/);
    assert.doesNotMatch(tabs, /titleText:\s*"Versículos"/);
    assert.match(tabs, /selectedIndex = 0/);
    const home = read("ios/App/App/VersesHomeViewController.swift");
    assert.match(home, /Ferramentas/);
    assert.match(home, /BooksHomeViewController/);
    assert.match(home, /Temas/);
    assert.match(home, /fetchBibleBooks|listBibleBooks/);
    assert.doesNotMatch(home, /utilizador|Definições|Partilhar|Guardar|Activa/);
  });

  it("ships picker + actions + themes screens", () => {
    const screens = read("ios/App/App/VersesScreens.swift");
    assert.match(screens, /VerseChapterViewController/);
    assert.match(screens, /VerseNumberViewController/);
    assert.match(screens, /V2NNumberCell|V2NNumberGridLayout/);
    assert.match(screens, /VerseActionsViewController/);
    assert.match(screens, /ThemesHomeViewController/);
    assert.match(screens, /V2NNamedCreateViewController/);
    assert.match(screens, /appendVerse/);
    assert.match(screens, /Compartilhar|openBible|UIActivityViewController/);
    assert.match(screens, /Adicionar à nota/);
    assert.doesNotMatch(screens, /utilizador|Definições|Partilhar|Guardar|Activa /);
  });

  it("exposes verse methods on NativeAPIClient", () => {
    const client = read("ios/App/App/NativeAPIClient.swift");
    assert.match(client, /func fetchBibleBooks\(/);
    assert.match(client, /func resolveBibleLink\(/);
    assert.match(client, /func appendVerse\(/);
    assert.match(client, /func fetchThemes\(/);
    assert.match(client, /struct BibleBookDTO/);
    assert.match(client, /bibleRef/);
  });

  it("registers Verses screens in the Xcode target", () => {
    const project = read("ios/App/App.xcodeproj/project.pbxproj");
    assert.match(project, /VersesHomeViewController\.swift in Sources/);
    assert.match(project, /VersesScreens\.swift in Sources/);
  });

  it("keeps WebKit session bootstrap on the main actor", () => {
    const boot = read("ios/App/App/NativeSessionBootstrap.swift");
    assert.match(boot, /@MainActor/);
    assert.match(boot, /Thread\.isMainThread/);
    assert.match(boot, /WKWebsiteDataStore/);
  });
});
