function splitEnv(name: string) {
  const raw = typeof process !== "undefined" ? process.env[name] : undefined;
  return (raw ?? "")
    .split(",")
    .map((item) => item.trim().toLowerCase())
    .filter(Boolean);
}

function isProductionRuntime() {
  const vercel = typeof process !== "undefined" ? process.env.VERCEL_ENV : undefined;
  if (vercel === "production") return true;
  if (vercel === "preview" || vercel === "development") return false;
  return typeof process !== "undefined" && process.env.NODE_ENV === "production";
}

export function adminEmails() {
  return splitEnv("ADMIN_EMAILS");
}

/**
 * Admin handles from `ADMIN_HANDLES` (comma-separated).
 * Production: env-only (no hardcoded owner). Set `ADMIN_HANDLES=betoverli` on Vercel.
 * Non-production: falls back to `betoverli` so local/preview admin still works.
 */
export function adminHandles() {
  const fromEnv = splitEnv("ADMIN_HANDLES");
  if (fromEnv.length) return [...new Set(fromEnv)];
  if (isProductionRuntime()) return [];
  return ["betoverli"];
}

export function isOwnerHandle(handle: string | null | undefined) {
  if (!handle) return false;
  return adminHandles().includes(handle.trim().replace(/^@+/, "").toLowerCase());
}
