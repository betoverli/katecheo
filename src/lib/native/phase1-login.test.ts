import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { describe, it } from "node:test";

const root = new URL("../../../", import.meta.url);

function read(rel: string) {
  return readFileSync(new URL(rel, root), "utf8");
}

describe("Phase 1 native login", () => {
  it("exposes auth routes on the native v1 router", () => {
    const router = read("src/lib/native/api/v1-router.ts");
    for (const kind of ["auth-claim", "auth-email", "auth-apple", "auth-from-cookie", "auth-sign-out", "auth-providers"]) {
      assert.match(router, new RegExp(kind));
    }
    const http = read("src/lib/native/api/v1-http.ts");
    assert.match(http, /auth-claim/);
    assert.match(http, /claimNativeBearer/);
    assert.match(http, /signInEmailNative/);
    assert.match(http, /signInAppleNative/);
  });

  it("ships Swift sign-in + cookie bootstrap + Keychain sign-out", () => {
    const signIn = read("ios/App/App/NativeSignInViewController.swift");
    assert.match(signIn, /Continuar com Google/);
    assert.match(signIn, /ASAuthorizationAppleIDButton/);
    assert.match(signIn, /Entrar com email/);
    const login = read("ios/App/App/NativeLoginService.swift");
    assert.match(login, /ASWebAuthenticationSession/);
    assert.match(login, /auth\/claim/);
    assert.match(login, /func signOut/);
    assert.match(login, /KeychainStore\.deleteBearerToken|KeychainStore\.setBearerToken/);
    const boot = read("ios/App/App/NativeSessionBootstrap.swift");
    assert.match(boot, /__Host-grok-auth\.session_token/);
    assert.match(boot, /migrateCookieToKeychainIfNeeded/);
    const list = read("ios/App/App/NotebookListViewController.swift");
    assert.match(list, /NativeSignInViewController/);
    assert.match(list, /Sair|Terminar sessão/);
    // Avoid #selector(presentSignIn) ambiguity with presentSignIn(auto:) overloads.
    assert.match(list, /presentSignInTapped/);
    assert.match(list, /showSignIn\(auto/);
    assert.doesNotMatch(list, /#selector\s*\(\s*presentSignIn\s*\)/);
  });

  it("registers Sign in with Apple entitlement", () => {
    const ents = read("ios/App/App/AppRelease.entitlements");
    assert.match(ents, /com\.apple\.developer\.applesignin/);
  });

  it("optionally wires Apple into Better Auth when env is set", () => {
    const apple = read("src/lib/auth/apple.ts");
    assert.match(apple, /APPLE_CLIENT_ID/);
    const server = read("src/lib/auth/server.ts");
    assert.match(server, /appleOAuthFromEnv/);
    assert.match(server, /APPLE_PROVIDER_ID|apple:/);
  });
});
