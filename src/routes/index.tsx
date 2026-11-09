import { useEffect, useState } from "react";
import { createFileRoute, useNavigate } from "@tanstack/react-router";
import { Landing } from "@/components/landing";
import { NativeEntry } from "@/components/native-entry";
import { SplashScreen } from "@/components/splash-screen";
import { useCurrentUserState } from "@/lib/auth/use-current-user";
import { isNativeShell } from "@/lib/native/runtime";
import { getNativeShellRequest } from "@/lib/native/shell-detect";
import { useAppStore } from "@/lib/store";

import { pageHead } from "@/lib/seo";

export const Route = createFileRoute("/")({
  component: Home,
  loader: async () => {
    // SSR: Capacitor appends Verse2NoteIOS so the first HTML paint can skip the
    // marketing landing inside the iOS app. Browsers never send that token.
    try {
      return await getNativeShellRequest();
    } catch {
      return { nativeShell: false };
    }
  },
  head: () =>
    pageHead({
      title: "Katecheo — links ricos de referências bíblicas",
      description:
        "Crie links ricos de referências bíblicas, coleções por tema e planos de leitura de capítulos para YouVersion, Logos e outros apps. Português, English, Español. Conta opcional. Funciona offline.",
      path: "/",
    }),
});

function Home() {
  const navigate = useNavigate();
  const { nativeShell: nativeFromLoader } = Route.useLoaderData();
  const onboarded = useAppStore((s) => s.onboarded);
  const { user, isPending } = useCurrentUserState();
  const [ready, setReady] = useState(false);
  const [nativeShell, setNativeShell] = useState(nativeFromLoader);

  useEffect(() => {
    setNativeShell(nativeFromLoader || isNativeShell());
  }, [nativeFromLoader]);

  useEffect(() => {
    const api = useAppStore.persist;
    if (!api || api.hasHydrated()) {
      setReady(true);
      return;
    }
    return api.onFinishHydration(() => setReady(true));
  }, []);

  // Public website: unchanged — marketing landing, then /app once onboarded.
  useEffect(() => {
    if (nativeShell) return;
    if (ready && onboarded) void navigate({ to: "/app" });
  }, [nativeShell, ready, onboarded, navigate]);

  // Native app: once the session is known, skip the landing and open notes
  // (or onboarding) for signed-in / returning visitors.
  const nativeEnterApp = nativeShell && ready && !isPending && (Boolean(user) || onboarded);

  useEffect(() => {
    if (nativeEnterApp) void navigate({ to: "/app" });
  }, [nativeEnterApp, navigate]);

  if (nativeShell) {
    // Session / store still loading, or redirecting into the app — blank splash,
    // never the marketing page.
    if (!ready || isPending || nativeEnterApp) return <SplashScreen />;
    return <NativeEntry />;
  }

  return <Landing />;
}
