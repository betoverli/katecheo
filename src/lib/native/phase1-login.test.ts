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
    for (const kind of [
      "auth-claim",
      "auth-email",
      "auth-email-sign-up",
      "auth-email-forgot-password",
      "auth-email-reset-password",
      "auth-apple",
      "auth-from-cookie",
      "auth-sign-out",
      "auth-providers",
    ]) {
      assert.match(router, new RegExp(kind));
    }
    const http = read("src/lib/native/api/v1-http.ts");
    assert.match(http, /auth-claim/);
    assert.match(http, /claimNativeBearer/);
    assert.match(http, /signInEmailNative/);
    assert.match(http, /signUpEmailNative/);
    assert.match(http, /forgotPasswordNative/);
    assert.match(http, /resetPasswordNative/);
    assert.match(http, /signInAppleNative/);
    const auth = read("src/lib/native/api/v1-auth.server.ts");
    assert.match(auth, /signUpEmailNative/);
    assert.match(auth, /forgotPasswordNative/);
    assert.match(auth, /resetPasswordNative/);
    assert.match(auth, /email_exists/);
    assert.match(auth, /minPasswordLength/);
  });

  it("ships Swift sign-in + cookie bootstrap + Keychain sign-out", () => {
    const signIn = read("ios/App/Katecheo/NativeSignInViewController.swift");
    assert.match(signIn, /Continuar com Google/);
    assert.match(signIn, /ASAuthorizationAppleIDButton/);
    assert.match(signIn, /makeAppleButton|appleButtonStyle/);
    assert.match(signIn, /Entrar com email/);
    assert.match(signIn, /Criar conta/);
    assert.match(signIn, /Entrar ou criar conta/);
    assert.match(signIn, /UISegmentedControl|emailModeControl/);
    assert.match(signIn, /BrandMark/);
    assert.match(signIn, /\.continue|type: \.continue/);
    const login = read("ios/App/Katecheo/NativeLoginService.swift");
    assert.match(login, /ASWebAuthenticationSession/);
    assert.match(login, /auth\/claim/);
    assert.match(login, /auth\/apple/);
    assert.match(login, /auth\/email\/sign-up/);
    assert.match(login, /signUpWithEmail/);
    assert.match(login, /auth\/email\/forgot-password/);
    assert.match(login, /auth\/email\/reset-password/);
    assert.match(login, /requestPasswordReset|forgotPassword/);
    assert.match(login, /resetPasswordWithCode|resetPassword/);
    assert.match(signIn, /Esqueci minha senha/);
    assert.match(login, /authorizationCode/);
    assert.match(login, /fullName|givenName/);
    assert.match(login, /requestedScopes = \[\.fullName, \.email\]/);
    assert.match(login, /func signOut/);
    assert.match(login, /KeychainStore\.deleteBearerToken|KeychainStore\.setBearerToken/);
    const boot = read("ios/App/Katecheo/NativeSessionBootstrap.swift");
    assert.match(boot, /__Host-grok-auth\.session_token/);
    assert.match(boot, /migrateCookieToKeychainIfNeeded/);
    const list = read("ios/App/Katecheo/NotebookListViewController.swift");
    assert.match(list, /NativeSignInViewController/);
    assert.match(list, /Sair|Terminar sessão/);
    // Avoid #selector(presentSignIn) ambiguity with presentSignIn(auto:) overloads.
    assert.match(list, /presentSignInTapped/);
    assert.match(list, /showSignIn\(auto/);
    assert.doesNotMatch(list, /#selector\s*\(\s*presentSignIn\s*\)/);
  });

  it("registers Sign in with Apple entitlement", () => {
    const ents = read("ios/App/Katecheo/AppRelease.entitlements");
    assert.match(ents, /com\.apple\.developer\.applesignin/);
  });

  it("optionally wires Apple into Better Auth when env is set", () => {
    const apple = read("src/lib/auth/apple.ts");
    assert.match(apple, /APPLE_CLIENT_ID/);
    assert.match(apple, /APPLE_SIGNIN_KEY_ID|APPLE_SIGNIN_PRIVATE_KEY/);
    assert.match(apple, /appleNativeFromEnv/);
    const server = read("src/lib/auth/server.ts");
    assert.match(server, /appleOAuthFromEnv/);
    assert.match(server, /APPLE_PROVIDER_ID|apple:/);
    const auth = read("src/lib/native/api/v1-auth.server.ts");
    assert.match(auth, /verifyAppleIdentityToken/);
    assert.match(auth, /findOrCreateAppleUser/);
    assert.match(auth, /exchangeAppleAuthorizationCode/);
    const migration = read("migrations/0024_apple_signin.sql");
    assert.match(migration, /apple_sub/);
    assert.match(migration, /apple_refresh_token/);
    const profile = read("src/lib/native/api/v1-profile.server.ts");
    assert.match(profile, /revokeAppleToken/);
  });
});
