import { useEffect } from "react";
import { createFileRoute } from "@tanstack/react-router";
import { detectLocale, t } from "@/lib/i18n";

export const Route = createFileRoute("/auth/native-return")({
  validateSearch: (search: Record<string, unknown>) => ({
    error: search.error === "1" || search.error === 1 || search.error === true,
  }),
  head: () => ({
    meta: [{ title: "Katecheo" }, { name: "robots", content: "noindex" }],
  }),
  component: NativeReturn,
});

function NativeReturn() {
  const { error } = Route.useSearch();
  const locale = detectLocale();

  useEffect(() => {
    const url = new URL(window.location.href);
    if (!url.searchParams.has("code")) return;
    url.searchParams.delete("code");
    const next = `${url.pathname}${url.search}`;
    window.history.replaceState(null, "", next);
  }, []);

  return (
    <main className="grid min-h-dvh place-items-center bg-bg px-6 text-center text-fg">
      <p className="max-w-xs text-sm text-muted">
        {error ? t(locale, "nativeAuthFailed") : t(locale, "nativeAuthReturn")}
      </p>
    </main>
  );
}
