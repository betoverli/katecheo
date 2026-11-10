import { isNativeApp } from "@/lib/native/runtime";

const TOKEN_KEY = "katecheo.apns-token";
const FLAG_KEY = "katecheo.apns";

type PushResult =
  | { ok: true; error: null }
  | { ok: false; error: "denied" | "unsupported" | "save" };

type NativeAuthRuntime = {
  runtime: () => Promise<{ apnsSandbox?: boolean }>;
};

let listenersReady = false;
let sandbox = false;
let pending: ((result: PushResult) => void) | null = null;

async function readSandbox(): Promise<boolean> {
  try {
    const { registerPlugin } = await import("@capacitor/core");
    const native = registerPlugin<NativeAuthRuntime>("NativeAuth");
    const runtime = await native.runtime();
    return runtime.apnsSandbox === true;
  } catch {
    return false;
  }
}

async function persistToken(token: string): Promise<PushResult> {
  try {
    localStorage.setItem(TOKEN_KEY, token);
    localStorage.setItem(FLAG_KEY, "1");
  } catch {
    /* storage can be blocked; the server row is what matters */
  }
  const { saveApnsDevice } = await import("@/lib/native/devices");
  const saved = await saveApnsDevice({ data: { token, sandbox } });
  if (!saved.ok) return { ok: false, error: "save" };
  return { ok: true, error: null };
}

function settle(result: PushResult) {
  const done = pending;
  pending = null;
  done?.(result);
}

/** Listen for the device token and for taps. Safe to call more than once. */
export async function installPushListeners() {
  if (!isNativeApp() || listenersReady) return;
  listenersReady = true;
  const { PushNotifications } = await import("@capacitor/push-notifications");
  await PushNotifications.addListener("registration", (event) => {
    const token = event.value?.trim() ?? "";
    if (!token) {
      settle({ ok: false, error: "unsupported" });
      return;
    }
    void persistToken(token).then(settle, () => settle({ ok: false, error: "save" }));
  });
  await PushNotifications.addListener("registrationError", () => {
    settle({ ok: false, error: "unsupported" });
  });
  await PushNotifications.addListener("pushNotificationActionPerformed", (action) => {
    const href = action.notification.data?.href;
    if (typeof href === "string" && href.startsWith("/") && !href.startsWith("//")) {
      window.location.assign(href.slice(0, 200));
    }
  });
}

function waitForRegistration(): Promise<PushResult> {
  return new Promise((resolve) => {
    const timer = window.setTimeout(() => {
      if (pending) {
        pending = null;
        resolve({ ok: false, error: "unsupported" });
      }
    }, 15_000);
    pending = (result) => {
      window.clearTimeout(timer);
      resolve(result);
    };
  });
}

export async function enableNativePush(): Promise<PushResult> {
  if (!isNativeApp()) return { ok: false, error: "unsupported" };
  await installPushListeners();
  sandbox = await readSandbox();
  const { PushNotifications } = await import("@capacitor/push-notifications");
  let permission: { receive: string };
  try {
    permission = await PushNotifications.requestPermissions();
  } catch {
    return { ok: false, error: "unsupported" };
  }
  if (permission.receive !== "granted") return { ok: false, error: "denied" };
  const pendingResult = waitForRegistration();
  await PushNotifications.register();
  return pendingResult;
}

export async function resumeNativePush() {
  if (!isNativeApp()) return;
  let flagged = false;
  try {
    flagged = localStorage.getItem(FLAG_KEY) === "1";
  } catch {
    return;
  }
  if (!flagged) return;
  await installPushListeners();
  const { PushNotifications } = await import("@capacitor/push-notifications");
  const permission = await PushNotifications.checkPermissions();
  if (permission.receive !== "granted") return;
  sandbox = await readSandbox();
  await PushNotifications.register();
}

export async function disableNativePush() {
  let token = "";
  try {
    token = localStorage.getItem(TOKEN_KEY) ?? "";
    localStorage.removeItem(FLAG_KEY);
    localStorage.removeItem(TOKEN_KEY);
  } catch {
    /* still drop the server row when we can */
  }
  const { dropApnsDevice } = await import("@/lib/native/devices");
  await dropApnsDevice({ data: { token } });
  try {
    const { PushNotifications } = await import("@capacitor/push-notifications");
    await PushNotifications.unregister();
  } catch {
    /* unregister is best-effort; the server row is what stops delivery */
  }
}
