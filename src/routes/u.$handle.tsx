import { createFileRoute, Link } from "@tanstack/react-router";
import { useEffect, useState } from "react";
import { toast } from "sonner";
import { AppHeader } from "@/components/app-header";
import { Screen } from "@/components/screen";
import { BadgeGrid } from "@/components/badge-grid";
import { Button } from "@/components/ui/button";
import { ProfileAvatar } from "@/lib/avatars";
import { useCurrentUserState } from "@/lib/auth/use-current-user";
import { getPublicProfile, type PublicProfile } from "@/lib/badge-stats";
import { t } from "@/lib/i18n";
import { getLinkStatus, requestLink, type LinkStatus } from "@/lib/links";
import { pageHead } from "@/lib/seo";
import { useAppStore } from "@/lib/store";

export const Route = createFileRoute("/u/$handle")({
  component: PublicProfileRoute,
  head: ({ params }) => {
    const seo = pageHead({
      title: `Katecheo — @${params.handle}`,
      description: `Perfil público de @${params.handle} no Katecheo.`,
      path: `/u/${params.handle}`,
    });
    return { ...seo, meta: [...seo.meta, { name: "robots", content: "noindex" }] };
  },
});

function ConnectButton({ handle }: { handle: string }) {
  const locale = useAppStore((s) => s.locale);
  const { user } = useCurrentUserState();
  const [status, setStatus] = useState<LinkStatus | null>(null);
  const [busy, setBusy] = useState(false);
  const myHandle = useAppStore((s) => s.handle);

  useEffect(() => {
    if (!user) {
      setStatus("none");
      return;
    }
    void getLinkStatus({ data: { handle } })
      .then((row) => setStatus(row.status))
      .catch(() => setStatus("none"));
  }, [user, handle]);

  if (myHandle && myHandle.toLowerCase() === handle.toLowerCase()) return null;
  if (!user) {
    return (
      <Button asChild>
        <Link to="/login" search={{ create: false, next: `/u/${handle}` }}>
          {t(locale, "linkConnect")}
        </Link>
      </Button>
    );
  }
  if (status === "accepted") {
    return (
      <p className="text-sm text-muted">{t(locale, "friends")}</p>
    );
  }
  if (status === "outgoing") {
    return (
      <Button variant="secondary" disabled>
        {t(locale, "linkPending")}
      </Button>
    );
  }
  if (status === "incoming") {
    return (
      <Button variant="secondary" asChild>
        <Link to="/profile/friends">{t(locale, "linkIncoming")}</Link>
      </Button>
    );
  }

  async function onConnect() {
    if (busy) return;
    setBusy(true);
    const result = await requestLink({ data: { handle } });
    setBusy(false);
    if (result?.ok) setStatus(result.status);
    const id = result?.ok ? toast.success(t(locale, "linkRequested")) : toast.error(t(locale, "linkSendFail"));
    window.setTimeout(() => toast.dismiss(id), 2000);
  }

  return (
    <Button disabled={busy || status == null} onClick={() => void onConnect()}>
      {t(locale, "linkConnect")}
    </Button>
  );
}

function PublicProfileRoute() {
  const { handle } = Route.useParams();
  const locale = useAppStore((s) => s.locale);
  const [profile, setProfile] = useState<PublicProfile | null | undefined>(undefined);

  useEffect(() => {
    let cancelled = false;
    void getPublicProfile({ data: { handle } }).then((row) => {
      if (!cancelled) setProfile(row);
    });
    return () => {
      cancelled = true;
    };
  }, [handle]);

  const name = profile ? [profile.firstName, profile.lastName].filter(Boolean).join(" ") : "";

  return (
    <Screen className="mx-auto flex min-h-dvh w-full max-w-lg flex-col gap-8 px-4 pt-0 pb-[calc(env(safe-area-inset-bottom)+2rem)] sm:px-6">
      <AppHeader title={profile ? `@${profile.handle}` : t(locale, "profile")} backTo="/" />
      {profile === undefined ? (
        <div className="h-40 rounded-lg bg-surface" aria-hidden="true" />
      ) : !profile ? (
        <p className="text-sm text-muted">{t(locale, "profileMissing")}</p>
      ) : (
        <div className="flex flex-col items-center gap-3">
          <ProfileAvatar
            id={profile.avatarId}
            url={profile.avatarUrl}
            className="size-20 bg-elevated"
            iconClassName="size-8"
          />
          <p className="font-display text-xl italic text-fg">@{profile.handle}</p>
          {name ? <p className="text-sm text-muted">{name}</p> : null}
          <ConnectButton handle={profile.handle} />
          <div className="mt-4 w-full space-y-3">
            <h2 className="text-xs font-medium tracking-wide text-muted uppercase">{t(locale, "badges")}</h2>
            {profile.badges.length ? (
              <BadgeGrid earned={profile.badges} locale={locale} />
            ) : (
              <p className="text-sm text-muted">{t(locale, "badgesEmpty")}</p>
            )}
          </div>
        </div>
      )}
    </Screen>
  );
}
