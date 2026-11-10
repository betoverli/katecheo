import assert from "node:assert/strict";
import { createHash, randomBytes } from "node:crypto";
import { readFileSync } from "node:fs";
import { describe, it } from "node:test";
import { appleAppSiteAssociation } from "./aasa.server.ts";
import { openSessionToken, resolveHandoffKey, sealSessionToken } from "./handoff-seal.server.ts";
import { pkceCookieHeader, readPkceCookie } from "./pkce-cookie.ts";
import { isPkceMaterial, newPkceVerifier, pkceChallenge, samePkce, verifierMatches } from "./pkce.ts";
import { isScriptedCrossSite } from "../auth/fetch-metadata.ts";
import { nativeDoneLocation } from "./done-redirect.ts";
import {
  canonicalNativeStart,
  isAllowedReturn,
  nativeOAuthStartOrigin,
  nativeReturnTo,
  preferredNativeReturnMode,
  shouldFallBackToScheme,
} from "./return-to.ts";
import { NATIVE_SESSION_COOKIE, sessionTokenFromCookie } from "./session-cookie.ts";

const token = "session-token-that-must-not-be-stored-raw";

describe("pkce", () => {
  it("matches the hash the server will store and rejects a different verifier", async () => {
    const verifier = newPkceVerifier();
    const challenge = await pkceChallenge(verifier);
    const expected = createHash("sha256").update(verifier).digest("base64url");
    assert.equal(challenge, expected);
    assert.equal(await verifierMatches(verifier, challenge), true);
    const wrong = `${verifier.slice(0, -1)}${verifier.endsWith("a") ? "b" : "a"}`;
    assert.equal(await verifierMatches(wrong, challenge), false);
    assert.equal(isPkceMaterial("short"), false);
    assert.equal(samePkce(challenge, expected), true);
  });
});

describe("return url", () => {
  it("uses the universal link or the scheme, and never the session token", () => {
    const code = "a".repeat(43);
    const https = nativeReturnTo("https", { code });
    const scheme = nativeReturnTo("scheme", { code });
    assert.equal(https, `https://katecheo.app/auth/native-return?code=${code}`);
    assert.equal(scheme, `verse2note://auth?code=${code}`);
    assert.equal(https.includes(token), false);
    assert.equal(isAllowedReturn(new URL(https), "https"), true);
    assert.equal(isAllowedReturn(new URL(https), "scheme"), false);
    assert.equal(isAllowedReturn(new URL(scheme), "scheme"), true);
    assert.equal(isAllowedReturn(new URL(nativeReturnTo("https", { error: true })), "https"), false);
  });
});

describe("pkce cookie", () => {
  it("round-trips the challenge and the return mode", async () => {
    const challenge = await pkceChallenge("b".repeat(43));
    const header = pkceCookieHeader(challenge, "https");
    assert.match(header, /HttpOnly/);
    assert.match(header, /Secure/);
    const parsed = readPkceCookie(`other=1; ${header.split(";")[0]}`);
    assert.deepEqual(parsed, { challenge, mode: "https" });
    assert.equal(readPkceCookie("nope=1"), null);
  });
});

describe("handoff seal", () => {
  it("encrypts the session token and refuses to invent a key", () => {
    assert.deepEqual(resolveHandoffKey({}), { ok: false, reason: "missing" });
    assert.equal(resolveHandoffKey({ handoff: "not-a-key", auth: "fallback-secret" }).ok, false);

    const authKey = resolveHandoffKey({ auth: "better-auth-secret" });
    assert.equal(authKey.ok, true);
    if (!authKey.ok) return;
    const sealed = sealSessionToken(token, authKey.key);
    assert.equal(sealed.includes(token), false);
    assert.equal(openSessionToken(sealed, authKey.key), token);
    assert.equal(openSessionToken(sealed, randomBytes(32)), null);
    const flipped = `${sealed.slice(0, -2)}${sealed.endsWith("a") ? "b" : "a"}`;
    assert.equal(openSessionToken(flipped, authKey.key), null);

    const hex = randomBytes(32).toString("hex");
    const dedicated = resolveHandoffKey({ handoff: hex, auth: "unused" });
    assert.equal(dedicated.ok && dedicated.source, "dedicated");
    if (!dedicated.ok) return;
    assert.equal(openSessionToken(sealSessionToken(token, dedicated.key), dedicated.key), token);
  });
});

describe("apple-app-site-association", () => {
  it("claims no app until the Team ID exists", () => {
    const empty = appleAppSiteAssociation(null);
    assert.equal(JSON.stringify(empty).includes("com.verse2note.app"), false);
    assert.equal("webcredentials" in empty, false);
    const live = appleAppSiteAssociation("AB12CD34EF");
    assert.deepEqual(live.applinks.details[0]?.appIDs, ["AB12CD34EF.com.verse2note.app"]);
    assert.equal(live.applinks.details[0]?.components[0]?.["/"], "/auth/native-return");
    assert.deepEqual(live.webcredentials, { apps: ["AB12CD34EF.com.verse2note.app"] });
  });
});

describe("https auth session fallback", () => {
  it("retries the custom scheme only when the https sheet never opened", () => {
    assert.equal(shouldFallBackToScheme("https", "Não foi possível abrir o login."), true);
    assert.equal(shouldFallBackToScheme("https", "cancelled"), false);
    assert.equal(shouldFallBackToScheme("https", "The user cancelled the login."), false);
    assert.equal(shouldFallBackToScheme("scheme", "Não foi possível abrir o login."), false);
  });

  it("prefers https Universal Links (custom scheme remains the fallback)", () => {
    assert.equal(preferredNativeReturnMode(), "https");
  });
});

describe("native oauth start host", () => {
  it("sends Google through katecheo.app (canonical) or verse2note.com (legacy)", () => {
    assert.equal(nativeOAuthStartOrigin("https://katecheo.app/login"), "https://katecheo.app");
    assert.equal(nativeOAuthStartOrigin("https://www.katecheo.app/app"), "https://katecheo.app");
    assert.equal(nativeOAuthStartOrigin("https://verse2note.com/login"), "https://verse2note.com");
    assert.equal(nativeOAuthStartOrigin("https://www.verse2note.com/app"), "https://verse2note.com");
    assert.equal(
      nativeOAuthStartOrigin("https://verse2note.vercel.app/login"),
      "https://katecheo.app",
    );
    assert.equal(nativeOAuthStartOrigin("http://localhost:8080/login"), "http://localhost:8080");
    assert.equal(
      nativeOAuthStartOrigin("https://preview.grok-sandbox.com/login"),
      "https://preview.grok-sandbox.com",
    );
    assert.equal(nativeOAuthStartOrigin("verse2note://localhost/login"), "https://katecheo.app");
  });

  it("bounces a non-canonical native-start to katecheo.app before Google", () => {
    const query = "?providerId=google&code_challenge=abc&return=scheme";
    assert.equal(canonicalNativeStart(`https://verse2note.com/auth/native-start${query}`), null);
    assert.equal(canonicalNativeStart(`http://localhost:8080/auth/native-start${query}`), null);
    assert.equal(
      canonicalNativeStart(`https://verse2note.vercel.app/auth/native-start${query}`),
      `https://katecheo.app/auth/native-start${query}`,
    );
    assert.equal(
      canonicalNativeStart(`https://www.verse2note.com/auth/native-start${query}`),
      `https://verse2note.com/auth/native-start${query}`,
    );
  });
});

describe("native done redirect", () => {
  it("follows the pkce cookie and never puts the session token in the url", async () => {
    const challenge = await pkceChallenge("c".repeat(43));
    const schemeCookie = pkceCookieHeader(challenge, "scheme").split(";")[0];
    const httpsCookie = pkceCookieHeader(challenge, "https").split(";")[0];
    const code = "d".repeat(43);
    assert.equal(nativeDoneLocation(schemeCookie, { code }), `verse2note://auth?code=${code}`);
    assert.equal(
      nativeDoneLocation(httpsCookie, { code }),
      `https://katecheo.app/auth/native-return?code=${code}`,
    );
    assert.equal(nativeDoneLocation(schemeCookie, { error: true }), "verse2note://auth?error=1");
    assert.equal(
      nativeDoneLocation(httpsCookie, { error: true }),
      "https://katecheo.app/auth/native-return?error=1",
    );
    assert.equal(nativeDoneLocation(null, { code }), "verse2note://auth?error=1");
    assert.equal(nativeDoneLocation(`${schemeCookie}; ${NATIVE_SESSION_COOKIE}=secret`, { code }).includes("secret"), false);
  });
});

describe("session cookie", () => {
  it("reads the session cookie the handoff will seal", () => {
    const header = `a=1; ${NATIVE_SESSION_COOKIE}=session%2Etoken; b=2`;
    assert.equal(sessionTokenFromCookie(header), "session.token");
    assert.equal(sessionTokenFromCookie("a=1"), null);
    assert.equal(sessionTokenFromCookie(`${NATIVE_SESSION_COOKIE}=${"x".repeat(4001)}`), null);
    const server = readFileSync(new URL("../auth/server.ts", import.meta.url), "utf8");
    assert.match(server, new RegExp(`SESSION_TOKEN_COOKIE = ${JSON.stringify(NATIVE_SESSION_COOKIE)}`));
  });
});

describe("native done request", () => {
  it("allows the google redirect and blocks a scripted sibling", () => {
    const navigate = new Headers({
      "sec-fetch-site": "cross-site",
      "sec-fetch-mode": "navigate",
      "sec-fetch-dest": "document",
    });
    assert.equal(isScriptedCrossSite("GET", navigate), false);
    const scripted = new Headers({
      "sec-fetch-site": "same-site",
      "sec-fetch-mode": "cors",
      "sec-fetch-dest": "empty",
    });
    assert.equal(isScriptedCrossSite("POST", scripted), true);
    assert.equal(isScriptedCrossSite("GET", new Headers()), false);
  });
});
