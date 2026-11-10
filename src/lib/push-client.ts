import { dropPushSubscription, getVapidPublicKey, savePushSubscription } from "@/lib/notify";
import { isNativeApp } from "@/lib/native/runtime";

function toBytes(base64: string) {
  const pad = "=".repeat((4 - (base64.length % 4)) % 4);
  const raw = atob(base64.replace(/-/g, "+").replace(/_/g, "/") + pad);
  const out = new Uint8Array(raw.length);
  for (let i = 0; i < raw.length; i += 1) out[i] = raw.charCodeAt(i);
  return out;
}

export function pushSupported() {
  return (
    typeof window !== "undefined" &&
    "Notification" in window &&
    "serviceWorker" in navigator &&
    "PushManager" in window
  );
}

export function isStandalone() {
  if (typeof window === "undefined") return false;
  return (
    window.matchMedia("(display-mode: standalone)").matches ||
    Boolean((navigator as Navigator & { standalone?: boolean }).standalone)
  );
}

async function registration() {
  const existing = await navigator.serviceWorker.getRegistration();
  if (existing) return existing;
  return navigator.serviceWorker.register("/sw.js");
}

export async function enablePush() {
  if (isNativeApp()) {
    const { enableNativePush } = await import("@/lib/native/push");
    return enableNativePush();
  }
  if (!pushSupported()) return { ok: false as const, error: "unsupported" as const };
  const permission = await Notification.requestPermission();
  if (permission !== "granted") return { ok: false as const, error: "denied" as const };
  const key = await getVapidPublicKey();
  if (!key) return { ok: false as const, error: "unsupported" as const };
  const worker = await registration();
  await navigator.serviceWorker.ready;
  const sub = await worker.pushManager.subscribe({
    userVisibleOnly: true,
    applicationServerKey: toBytes(key) as BufferSource,
  });
  const json = sub.toJSON();
  const endpoint = json.endpoint ?? "";
  const p256dh = json.keys?.p256dh ?? "";
  const auth = json.keys?.auth ?? "";
  const saved = await savePushSubscription({ data: { endpoint, p256dh, auth } });
  if (!saved.ok) return { ok: false as const, error: "save" as const };
  return { ok: true as const, error: null };
}

export async function disablePush() {
  if (isNativeApp()) {
    const { disableNativePush } = await import("@/lib/native/push");
    await disableNativePush();
    return;
  }
  const worker = await navigator.serviceWorker.getRegistration();
  const sub = await worker?.pushManager.getSubscription();
  if (sub) {
    await dropPushSubscription({ data: { endpoint: sub.endpoint } });
    await sub.unsubscribe();
  }
}
