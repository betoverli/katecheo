import { createServerFn } from "@tanstack/react-start";
import { authMiddleware } from "@/lib/auth/middleware";

export const saveApnsDevice = createServerFn({ method: "POST" })
  .middleware([authMiddleware])
  .validator((data: { token: string; sandbox?: boolean }) => ({
    token: typeof data?.token === "string" ? data.token : "",
    sandbox: data?.sandbox === true,
  }))
  .handler(async ({ context, data }) => {
    const { saveApnsDevice: save } = await import("./devices.server");
    return save(context.userId, data.token, data.sandbox);
  });

export const dropApnsDevice = createServerFn({ method: "POST" })
  .middleware([authMiddleware])
  .validator((data: { token?: string; all?: boolean }) => ({
    token: typeof data?.token === "string" ? data.token : "",
    all: data?.all === true,
  }))
  .handler(async ({ context, data }) => {
    const { dropApnsDevice: drop } = await import("./devices.server");
    return drop(context.userId, data.token, { all: data.all });
  });
