import http2 from "node:http2";
import { importPKCS8, SignJWT } from "jose";
import type { Sql } from "@/lib/db";
import { apnsPayload, apnsSilentPayload, type ApnsAlert, type ApnsSilentHint } from "@/lib/apns-payload";
import { shouldPruneApnsDevice } from "@/lib/native/apns-devices-logic";

export { shouldPruneApnsDevice } from "@/lib/native/apns-devices-logic";

const TOPIC = () => process.env.APNS_TOPIC?.trim() || "com.verse2note.app";

type JwtCache = { token: string; exp: number };
let jwtCache: JwtCache | null = null;

function privateKeyPem(): string | null {
  const raw = process.env.APNS_PRIVATE_KEY?.trim();
  if (!raw) return null;
  const pem = raw.includes("BEGIN") ? raw : Buffer.from(raw, "base64").toString("utf8");
  return pem.replace(/\\n/g, "\n");
}

/** Provider token for APNs. Null when the server has no key yet. */
export async function apnsJwt(): Promise<string | null> {
  const keyId = process.env.APNS_KEY_ID?.trim();
  const teamId = process.env.APNS_TEAM_ID?.trim();
  const pem = privateKeyPem();
  if (!keyId || !teamId || !pem) return null;
  const now = Math.floor(Date.now() / 1000);
  if (jwtCache && jwtCache.exp - 60 > now) return jwtCache.token;
  const key = await importPKCS8(pem, "ES256");
  const token = await new SignJWT({})
    .setProtectedHeader({ alg: "ES256", kid: keyId })
    .setIssuer(teamId)
    .setIssuedAt(now)
    .sign(key);
  jwtCache = { token, exp: now + 50 * 60 };
  return token;
}

function hostFor(sandbox: boolean): string {
  const forced = process.env.APNS_ENVIRONMENT?.trim().toLowerCase();
  const useSandbox = forced === "sandbox" ? true : forced === "production" ? false : sandbox;
  return useSandbox ? "api.sandbox.push.apple.com" : "api.push.apple.com";
}

function postApns(
  host: string,
  device: string,
  jwt: string,
  body: string,
  opts?: { pushType?: "alert" | "background"; priority?: "5" | "10" },
): Promise<{ status: number; body: string }> {
  return new Promise((resolve, reject) => {
    const client = http2.connect(`https://${host}`);
    const fail = (error: Error) => {
      client.close();
      reject(error);
    };
    client.on("error", fail);
    const req = client.request({
      ":method": "POST",
      ":path": `/3/device/${device}`,
      authorization: `bearer ${jwt}`,
      "apns-topic": TOPIC(),
      "apns-push-type": opts?.pushType ?? "alert",
      "apns-priority": opts?.priority ?? "10",
    });
    let status = 0;
    let response = "";
    req.setEncoding("utf8");
    req.on("response", (headers) => {
      status = Number(headers[":status"] ?? 0);
    });
    req.on("data", (chunk) => {
      response += chunk;
    });
    req.on("end", () => {
      client.close();
      resolve({ status, body: response });
    });
    req.on("error", fail);
    req.end(body);
  });
}

async function deliverToDevices(
  sql: Sql,
  devices: { token: string; sandbox: boolean }[],
  body: string,
  opts: { pushType: "alert" | "background"; priority: "5" | "10" },
): Promise<void> {
  const jwt = await apnsJwt();
  if (!jwt) return;
  for (const device of devices) {
    if (!/^[0-9a-fA-F]{64,200}$/.test(device.token)) continue;
    try {
      const result = await postApns(hostFor(device.sandbox), device.token, jwt, body, opts);
      if (shouldPruneApnsDevice(result.status, result.body)) {
        await sql`delete from apns_devices where token = ${device.token}`;
      }
    } catch {
      /* one device failing must not stop the others or the web push path */
    }
  }
}

/** Send one alert to every iOS device of this user. Web push is separate. */
export async function sendApnsToUser(sql: Sql, userId: string, alert: ApnsAlert): Promise<void> {
  const devices = await sql<{ token: string; sandbox: boolean }>`
    select token, sandbox from apns_devices where user_id = ${userId}
  `;
  await deliverToDevices(sql, devices, JSON.stringify(apnsPayload(alert)), {
    pushType: "alert",
    priority: "10",
  });
}

/** Silent/background push for catalog hints (themes_updated / reading_updated). */
export async function sendApnsSilentToUser(sql: Sql, userId: string, hint: ApnsSilentHint): Promise<void> {
  const devices = await sql<{ token: string; sandbox: boolean }>`
    select token, sandbox from apns_devices where user_id = ${userId}
  `;
  await deliverToDevices(sql, devices, JSON.stringify(apnsSilentPayload(hint)), {
    pushType: "background",
    priority: "5",
  });
}

/**
 * Broadcast a silent catalog hint to every registered iOS device (static catalog deploys).
 * Callers MUST authorize via `CATALOG_PUSH_SECRET` (see `broadcastCatalogHint`) —
 * never wire this to a public HTTP route.
 */
export async function broadcastApnsSilent(sql: Sql, hint: ApnsSilentHint): Promise<void> {
  const devices = await sql<{ token: string; sandbox: boolean }>`
    select token, sandbox from apns_devices
  `;
  await deliverToDevices(sql, devices, JSON.stringify(apnsSilentPayload(hint)), {
    pushType: "background",
    priority: "5",
  });
}
