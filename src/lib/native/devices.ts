import { createServerFn } from "@tanstack/react-start";
import { authMiddleware } from "@/lib/auth/middleware";

export const saveApnsDevice = createServerFn({ method: "POST" })
  .middleware([authMiddleware])
  .validator((data: { token: string; deviceId: string; sandbox?: boolean; environment?: string }) => ({
    token: typeof data?.token === "string" ? data.token : "",
    deviceId: typeof data?.deviceId === "string" ? data.deviceId : "",
    sandbox:
      data?.sandbox === true ||
      (typeof data?.environment === "string" && data.environment.toLowerCase() === "sandbox"),
  }))
  .handler(async ({ context, data }) => {
    const { saveApnsDevice: save } = await import("./devices.server");
    return save(context.userId, data.token, data.sandbox, data.deviceId);
  });

export const dropApnsDevice = createServerFn({ method: "POST" })
  .middleware([authMiddleware])
  .validator((data: { token?: string; deviceId?: string; all?: boolean }) => ({
    token: typeof data?.token === "string" ? data.token : "",
    deviceId: typeof data?.deviceId === "string" ? data.deviceId : "",
    all: data?.all === true,
  }))
  .handler(async ({ context, data }) => {
    const { dropApnsDevice: drop } = await import("./devices.server");
    return drop(context.userId, data.token, {
      all: data.all,
      deviceId: data.deviceId || undefined,
    });
  });
