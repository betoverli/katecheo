import { getRequest } from "@tanstack/react-start/server";
import { isScriptedCrossSite } from "@/lib/auth/fetch-metadata";
import { assertSameSiteRequest, CrossSiteRequestError } from "@/lib/auth/isolation.server";
import { readSessionToken } from "@/lib/auth/server";
import { getSql } from "@/lib/db";
import { allowRequest, clientKey } from "@/lib/rate-limit";
import { currentHandoffKey, openSessionToken, sealSessionToken } from "@/lib/native/handoff-seal.server";
import { hashHandoffCode, isHandoffCode, newHandoffCode } from "@/lib/native/handoff-code";
import { readPkceCookie } from "@/lib/native/pkce-cookie";
import { isPkceMaterial, pkceChallenge } from "@/lib/native/pkce";
import { nativeReturnTo, type NativeReturnMode } from "@/lib/native/return-to";

const TTL_MS = 90_000;

/** Cookie jar for a route handler. Server functions omit this and use the request context. */
export type HandoffRequest = {
  cookieHeader: string | null;
  token: string | null;
  method: string;
  headers: Headers;
};

function cookieHeader(): string | null {
  return getRequest()?.headers.get("cookie") ?? null;
}

function guard(source?: HandoffRequest): void {
  if (!source) {
    assertSameSiteRequest();
    return;
  }
  if (isScriptedCrossSite(source.method, source.headers)) throw new CrossSiteRequestError();
}

function returnMode(): NativeReturnMode {
  return readPkceCookie(cookieHeader())?.mode ?? "scheme";
}

let loggedKey = false;

function refuseKey(
  reason: "missing" | "invalid-dedicated",
  mode: NativeReturnMode,
): { ok: false; redirect: string } {
  if (!loggedKey) {
    loggedKey = true;
    const detail =
      reason === "invalid-dedicated"
        ? "NATIVE_AUTH_HANDOFF_KEY não tem 32 bytes."
        : "Falta NATIVE_AUTH_HANDOFF_KEY e também BETTER_AUTH_SECRET.";
    console.error(`Login nativo recusado: ${detail} A sessão não foi gravada.`);
  }
  return { ok: false, redirect: nativeReturnTo(mode, { error: true }) };
}

/** Called from the system login browser, which holds the session cookie. */
export async function mintHandoff(userId: string, source?: HandoffRequest) {
  guard(source);
  const header = source ? source.cookieHeader : cookieHeader();
  const pkce = readPkceCookie(header);
  const mode = pkce?.mode ?? "scheme";
  const fail = { ok: false as const, redirect: nativeReturnTo(mode, { error: true }) };
  if (!pkce) return fail;
  const token = source ? source.token : readSessionToken();
  if (!token || token.length > 4000) return fail;
  const resolved = currentHandoffKey();
  if (!resolved.ok) return refuseKey(resolved.reason, mode);
  if (!(await allowRequest(`native-mint:${userId}`, 12, 60 * 60_000))) return fail;
  const code = newHandoffCode();
  const sealed = sealSessionToken(token, resolved.key);
  const sql = await getSql();
  const expires = new Date(Date.now() + TTL_MS).toISOString();
  await sql`delete from native_auth_handoff where user_id = ${userId} or expires_at < now()`;
  await sql`
    insert into native_auth_handoff (code_hash, user_id, token_ciphertext, challenge, expires_at)
    values (${hashHandoffCode(code)}, ${userId}, ${sealed}, ${pkce.challenge}, ${expires})
  `;
  return { ok: true as const, redirect: nativeReturnTo(mode, { code }) };
}

/** Error return for a login that never minted a code. Clears nothing sensitive. */
export function errorReturn() {
  assertSameSiteRequest();
  return { ok: false as const, redirect: nativeReturnTo(returnMode(), { error: true }) };
}

/** Called from the WebView. The code is single-use, expires in 90 seconds, and needs the verifier. */
export async function claimHandoff(code: string, verifier: string) {
  assertSameSiteRequest();
  const request = getRequest();
  const ip = request ? clientKey(request) : "local";
  if (!(await allowRequest(`native-claim:${ip}`, 20, 60_000))) return { ok: false as const };
  if (!isHandoffCode(code) || !isPkceMaterial(verifier)) return { ok: false as const };
  const challenge = await pkceChallenge(verifier);
  const resolved = currentHandoffKey();
  if (!resolved.ok) return { ok: false as const };
  const sql = await getSql();
  const rows = await sql<{ token_ciphertext: string }>`
    delete from native_auth_handoff
    where code_hash = ${hashHandoffCode(code)}
      and challenge = ${challenge}
      and token_ciphertext is not null
      and expires_at > now()
    returning token_ciphertext
  `;
  const sealed = rows[0]?.token_ciphertext;
  if (!sealed) return { ok: false as const };
  const token = openSessionToken(sealed, resolved.key);
  if (!token) return { ok: false as const };
  return { ok: true as const, token };
}
