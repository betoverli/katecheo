import { useState, type FormEvent } from "react";
import { createFileRoute, Link, useNavigate } from "@tanstack/react-router";
import { authClient, authEnabled, signIn } from "@/lib/auth/client";
import { GOOGLE_PROVIDER_ID } from "@/lib/auth/google";
import { getGoogleSignInEnabled } from "@/lib/auth/google-status";
import { t } from "@/lib/i18n";
import { safeNext } from "@/lib/invite";
import { cleanEmail, cleanHandle, cleanName, profileIsComplete } from "@/lib/profile";
import { savePrefs } from "@/lib/cloud";
import { pageHead } from "@/lib/seo";
import { useAppStore } from "@/lib/store";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Wordmark } from "@/components/wordmark";

export const Route = createFileRoute("/login")({
  component: Login,
  loader: async () => {
    try {
      const result = await getGoogleSignInEnabled();
      return { google: result.enabled };
    } catch {
      return { google: false };
    }
  },
  validateSearch: (search: Record<string, unknown>): { create: boolean; next?: string } => {
    const next = safeNext(search.next);
    return {
      create: search.create === true || search.create === "1" || search.create === "true",
      ...(next ? { next } : {}),
    };
  },
  head: () => {
    const seo = pageHead({
      title: "Katecheo — Entrar",
      description: "Entre ou crie uma conta para guardar os planos de leitura em todos os aparelhos.",
      path: "/login",
    });
    return { ...seo, meta: [...seo.meta, { name: "robots", content: "noindex" }] };
  },
});

function GoogleMark() {
  return (
    <svg viewBox="0 0 18 18" aria-hidden="true" className="size-4">
      <path
        fill="#4285F4"
        d="M17.64 9.2c0-.637-.057-1.251-.164-1.84H9v3.481h4.844a4.14 4.14 0 0 1-1.796 2.716v2.259h2.908c1.702-1.567 2.684-3.875 2.684-6.615z"
      />
      <path
        fill="#34A853"
        d="M9 18c2.43 0 4.467-.806 5.956-2.184l-2.908-2.259c-.806.54-1.837.86-3.048.86-2.344 0-4.328-1.584-5.036-3.711H.957v2.332A8.997 8.997 0 0 0 9 18z"
      />
      <path
        fill="#FBBC05"
        d="M3.964 10.706A5.41 5.41 0 0 1 3.682 9c0-.593.102-1.17.282-1.706V4.962H.957A8.996 8.996 0 0 0 0 9c0 1.452.348 2.827.957 4.038l3.007-2.332z"
      />
      <path
        fill="#EA4335"
        d="M9 3.58c1.321 0 2.508.454 3.44 1.345l2.582-2.58C13.463.891 11.426 0 9 0A8.997 8.997 0 0 0 .957 4.962L3.964 7.294C4.672 5.163 6.656 3.58 9 3.58z"
      />
    </svg>
  );
}

function Login() {
  const locale = useAppStore((s) => s.locale);
  const navigate = useNavigate();
  const { create, next } = Route.useSearch();
  const { google } = Route.useLoaderData();
  const afterAuth = next ?? "/profile";
  const [mode, setMode] = useState<"in" | "up">(create ? "up" : "in");
  const [name, setName] = useState("");
  const [handle, setHandle] = useState("");
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const setProfile = useAppStore((s) => s.setProfile);

  async function onSocial(providerId: string) {
    setError(null);
    setBusy(true);
    try {
      await signIn(providerId, { callbackURL: afterAuth });
    } catch (err) {
      if (err instanceof Error && err.name === "AbortError") {
        setBusy(false);
        return;
      }
      const message = err instanceof Error ? err.message : "";
      setError(/pop-up|popup/i.test(message) ? t(locale, "accountPopup") : message || t(locale, "accountError"));
      setBusy(false);
    }
  }

  async function onSubmit(event: FormEvent) {
    event.preventDefault();
    setError(null);
    setBusy(true);
    try {
      if (mode === "up") {
        const firstName = cleanName(name);
        const userHandle = cleanHandle(handle);
        const mail = cleanEmail(email);
        if (!profileIsComplete({ handle: userHandle, firstName, profileEmail: mail })) {
          setError(t(locale, "completeProfileLead"));
          setBusy(false);
          return;
        }
        const result = await authClient.signUp.email({
          name: firstName,
          email: mail,
          password,
          callbackURL: afterAuth,
        });
        if (result.error) {
          setError(result.error.message || t(locale, "accountError"));
          setBusy(false);
          return;
        }
        setProfile({ handle: userHandle, firstName, profileEmail: mail });
        try {
          await authClient.getSession();
          const saved = await savePrefs({
            data: {
              locale: useAppStore.getState().locale,
              copyLocale: useAppStore.getState().copyLocale,
              appId: useAppStore.getState().appId,
              translationId: useAppStore.getState().translationId,
              preferNative: useAppStore.getState().preferNative,
              copyFormat: useAppStore.getState().copyFormat,
              citeBook: useAppStore.getState().citeBook,
              citeSep: useAppStore.getState().citeSep,
              booksCompact: useAppStore.getState().booksCompact,
              theme: useAppStore.getState().theme,
              activePlans: useAppStore.getState().activePlans,
              planProgress: useAppStore.getState().planProgress,
              avatarId: useAppStore.getState().avatarId,
              avatarUrl: useAppStore.getState().avatarUrl,
              handle: userHandle,
              firstName,
              lastName: useAppStore.getState().lastName,
              profileEmail: mail,
            },
          });
          if (saved && "error" in saved && saved.error === "handle") {
            setProfile({ handle: "" });
          } else {
            useAppStore.getState().setCloudProfileOk(true);
          }
        } catch {
          /* gate will ask again */
        }
      } else {
        const result = await authClient.signIn.email({
          email: email.trim(),
          password,
          callbackURL: afterAuth,
        });
        if (result.error) {
          setError(result.error.message || t(locale, "accountError"));
          setBusy(false);
          return;
        }
        try {
          await authClient.getSession();
        } catch {
          /* cookie session will land on the next page */
        }
      }
      if (afterAuth.startsWith("/g/")) {
        const id = afterAuth.slice(3).split("/")[0];
        await navigate({ to: "/g/$id", params: { id } });
      } else if (afterAuth.startsWith("/c/")) {
        const id = afterAuth.slice(3).split("/")[0];
        await navigate({ to: "/c/$id", params: { id } });
      } else if (afterAuth.startsWith("/reading/")) {
        const id = afterAuth.slice("/reading/".length).split("/")[0];
        await navigate({ to: "/reading/$id", params: { id } });
      } else if (afterAuth.startsWith("/collections")) {
        await navigate({ to: "/collections" });
      } else if (afterAuth === "/app") {
        await navigate({ to: "/app" });
      } else {
        await navigate({ to: "/profile" });
      }
    } catch {
      setError(t(locale, "accountError"));
      setBusy(false);
    }
  }

  return (
    <main className="mx-auto flex min-h-dvh w-full max-w-md flex-col px-5 pt-[calc(env(safe-area-inset-top)+1.5rem)] pb-[calc(env(safe-area-inset-bottom)+1.5rem)]">
      <Wordmark size="sm" />
      <h1 className="mt-8 text-[34px] leading-[1.15] font-bold tracking-[-0.022em] text-fg">
        {mode === "up" ? t(locale, "createAccount") : t(locale, "signIn")}
      </h1>
      <p className="mt-3 text-pretty text-[17px] leading-snug text-muted">{t(locale, "accountLead")}</p>

      <div className="mt-8 flex flex-col gap-2">
        {authEnabled ? (
          google ? (
            <Button
              type="button"
              variant="secondary"
              className="w-full" size="lg"
              disabled={busy}
              onClick={() => void onSocial(GOOGLE_PROVIDER_ID)}
            >
              <GoogleMark />
              {t(locale, "continueGoogle")}
            </Button>
          ) : null
        ) : (
          <p className="text-sm text-muted">{t(locale, "accountOff")}</p>
        )}
      </div>
      {error ? <p className="mt-4 text-[15px] text-danger">{error}</p> : null}

      {authEnabled ? (
        <>
          <p className="mt-6 text-center text-[13px] text-muted">{t(locale, "orEmail")}</p>
          <form className="mt-3 flex flex-col gap-4" onSubmit={(event) => void onSubmit(event)}>
            <div className="ios-fields">
              {mode === "up" ? (
                <>
                  <Input
                    name="name"
                    autoComplete="given-name"
                    required
                    value={name}
                    onChange={(event) => setName(event.target.value)}
                    placeholder={t(locale, "accountName")}
                    className="rounded-none bg-transparent shadow-none focus-visible:ring-0"
                  />
                  <div className="relative">
                    <span className="pointer-events-none absolute top-1/2 left-4 -translate-y-1/2 text-muted">@</span>
                    <Input
                      name="username"
                      autoComplete="username"
                      required
                      minLength={3}
                      maxLength={20}
                      value={handle}
                      onChange={(event) => setHandle(cleanHandle(event.target.value))}
                      className="rounded-none bg-transparent pl-8 shadow-none focus-visible:ring-0"
                      autoCapitalize="off"
                      autoCorrect="off"
                      spellCheck={false}
                      placeholder={t(locale, "handle")}
                    />
                  </div>
                </>
              ) : null}
              <Input
                type="email"
                name="email"
                autoComplete="email"
                required
                value={email}
                onChange={(event) => setEmail(event.target.value)}
                placeholder={t(locale, "accountEmail")}
                className="rounded-none bg-transparent shadow-none focus-visible:ring-0"
              />
              <Input
                type="password"
                name="password"
                autoComplete={mode === "up" ? "new-password" : "current-password"}
                required
                minLength={8}
                value={password}
                onChange={(event) => setPassword(event.target.value)}
                placeholder={t(locale, "accountPassword")}
                className="rounded-none bg-transparent shadow-none focus-visible:ring-0"
              />
            </div>
            <Button type="submit" className="w-full" size="lg" disabled={busy}>
              {busy ? t(locale, "accountWait") : mode === "up" ? t(locale, "createAccount") : t(locale, "signIn")}
            </Button>
          </form>
          <button
            type="button"
            className="mt-4 min-h-11 text-[17px] text-accent"
            onClick={() => {
              setMode(mode === "up" ? "in" : "up");
              setError(null);
            }}
          >
            {mode === "up" ? t(locale, "haveAccount") : t(locale, "noAccount")}
          </button>
        </>
      ) : null}

      <p className="mt-6 text-[13px] leading-relaxed text-subtle">{t(locale, "accountHint")}</p>
      <p className="mt-auto flex justify-center gap-3 pt-8 text-center text-[17px]">
        <Link to="/" className="text-accent">
          {t(locale, "back")}
        </Link>
        <span aria-hidden className="text-subtle">·</span>
        <Link to="/privacy" className="text-accent">
          {t(locale, "privacyTitle")}
        </Link>
      </p>
    </main>
  );
}
