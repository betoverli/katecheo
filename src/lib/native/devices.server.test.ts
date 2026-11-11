import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { describe, it } from "node:test";
import {
  applyApnsDeviceRegister,
  cleanApnsToken,
  cleanDeviceId,
  shouldPruneApnsDevice,
  type ApnsDeviceMemRow,
} from "./apns-devices-logic.ts";

const root = new URL("../../../", import.meta.url);
const TOKEN_A = "a".repeat(64);
const TOKEN_B = "b".repeat(64);
const TOKEN_C = "c".repeat(64);

function read(rel: string) {
  return readFileSync(new URL(rel, root), "utf8");
}

describe("APNs device id cleaning", () => {
  it("accepts hex tokens and stable device ids", () => {
    assert.equal(cleanApnsToken(TOKEN_A.toUpperCase()), TOKEN_A);
    assert.equal(cleanApnsToken("short"), null);
    assert.equal(cleanDeviceId("AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE"), "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE");
    assert.equal(cleanDeviceId("legacy:" + TOKEN_A), "legacy:" + TOKEN_A);
    assert.equal(cleanDeviceId("nope"), null);
  });
});

describe("APNs upsert / dedupe", () => {
  it("upserts by (user, deviceId) when the token rotates", () => {
    const first = applyApnsDeviceRegister([], {
      userId: "u1",
      token: TOKEN_A,
      deviceId: "device-1",
      sandbox: true,
      now: 1_000,
    });
    assert.equal(first.ok, true);
    if (!first.ok) return;

    const rotated = applyApnsDeviceRegister(first.rows, {
      userId: "u1",
      token: TOKEN_B,
      deviceId: "device-1",
      sandbox: false,
      now: 2_000,
    });
    assert.equal(rotated.ok, true);
    if (!rotated.ok) return;
    assert.equal(rotated.rows.length, 1);
    assert.equal(rotated.rows[0]?.token, TOKEN_B);
    assert.equal(rotated.rows[0]?.sandbox, false);
    assert.equal(rotated.rows[0]?.deviceId, "device-1");
  });

  it("dedupes the same token from another row", () => {
    const seeded = applyApnsDeviceRegister([], {
      userId: "u1",
      token: TOKEN_A,
      deviceId: "iphone-old",
      sandbox: true,
      now: 1_000,
    });
    assert.equal(seeded.ok, true);
    if (!seeded.ok) return;

    const withSecond = applyApnsDeviceRegister(seeded.rows, {
      userId: "u1",
      token: TOKEN_C,
      deviceId: "iphone-new",
      sandbox: true,
      now: 2_000,
    });
    assert.equal(withSecond.ok, true);
    if (!withSecond.ok) return;
    assert.equal(withSecond.rows.length, 2);

    const deduped = applyApnsDeviceRegister(withSecond.rows, {
      userId: "u1",
      token: TOKEN_A,
      deviceId: "iphone-new",
      sandbox: true,
      now: 3_000,
    });
    assert.equal(deduped.ok, true);
    if (!deduped.ok) return;
    assert.equal(deduped.rows.length, 1);
    assert.equal(deduped.rows[0]?.deviceId, "iphone-new");
    assert.equal(deduped.rows[0]?.token, TOKEN_A);
  });

  it("blocks rapid token reassignment across users", () => {
    const owned = applyApnsDeviceRegister([], {
      userId: "alice",
      token: TOKEN_A,
      deviceId: "phone-alice",
      sandbox: true,
      now: 10_000,
    });
    assert.equal(owned.ok, true);
    if (!owned.ok) return;

    const conflict = applyApnsDeviceRegister(owned.rows, {
      userId: "bob",
      token: TOKEN_A,
      deviceId: "phone-bobby",
      sandbox: true,
      now: 10_000 + 30_000,
    });
    assert.equal(conflict.ok, false);
    if (conflict.ok) return;
    assert.equal(conflict.error, "conflict");

    const later = applyApnsDeviceRegister(owned.rows, {
      userId: "bob",
      token: TOKEN_A,
      deviceId: "phone-bobby",
      sandbox: true,
      now: 10_000 + 61_000,
    });
    assert.equal(later.ok, true);
    if (!later.ok) return;
    assert.equal(later.rows.length, 1);
    assert.equal(later.rows[0]?.userId, "bob");
  });

  it("keeps distinct devices for the same user", () => {
    let rows: ApnsDeviceMemRow[] = [];
    const a = applyApnsDeviceRegister(rows, {
      userId: "u1",
      token: TOKEN_A,
      deviceId: "iphone-one",
      sandbox: true,
      now: 1,
    });
    assert.equal(a.ok, true);
    if (!a.ok) return;
    rows = a.rows;
    const b = applyApnsDeviceRegister(rows, {
      userId: "u1",
      token: TOKEN_B,
      deviceId: "ipad-two1",
      sandbox: true,
      now: 2,
    });
    assert.equal(b.ok, true);
    if (!b.ok) return;
    assert.equal(b.rows.length, 2);
  });
});

describe("APNs 410 / BadDeviceToken prune", () => {
  it("deletes on 410 Unregistered and 400 BadDeviceToken", () => {
    assert.equal(shouldPruneApnsDevice(410, '{"reason":"Unregistered"}'), true);
    assert.equal(shouldPruneApnsDevice(400, '{"reason":"BadDeviceToken"}'), true);
    assert.equal(shouldPruneApnsDevice(400, '{"reason":"DeviceTokenNotForTopic"}'), true);
    assert.equal(shouldPruneApnsDevice(400, '{"reason":"PayloadTooLarge"}'), false);
    assert.equal(shouldPruneApnsDevice(500, '{"reason":"Internal"}'), false);
    assert.equal(shouldPruneApnsDevice(200, ""), false);
  });
});

describe("APNs device migration + wiring", () => {
  it("ships migration with unique (user, device) and duplicate cleanup", () => {
    const migration = read("migrations/0026_apns_device_id.sql");
    assert.match(migration, /device_id/);
    assert.match(migration, /apns_devices_user_device_pkey|primary key \(user_id, device_id\)/);
    assert.match(migration, /apns_devices_token_uidx/);
    assert.match(migration, /delete from apns_devices/);
    assert.match(migration, /legacy:/);

    const server = read("src/lib/native/devices.server.ts");
    assert.match(server, /on conflict \(user_id, device_id\)/);
    assert.match(server, /device_id/);

    const apns = read("src/lib/apns.server.ts");
    assert.match(apns, /shouldPruneApnsDevice/);
    assert.match(apns, /delete from apns_devices where token/);

    const push = read("ios/App/Katecheo/NativePushService.swift");
    assert.match(push, /DeviceIdStore\.deviceId/);
    assert.match(push, /deviceId:/);

    const client = read("ios/App/Katecheo/NativeAPIClient.swift");
    assert.match(client, /"deviceId"/);
    assert.match(client, /"environment"/);
  });
});
