import { useEffect, useState } from "react";
import { Link, useNavigate } from "@tanstack/react-router";
import { Award, BarChart3, Bell, BookOpen, ChevronRight, CircleHelp, Globe, Pencil, Share2, Sun, Users } from "lucide-react";
import { authEnabled, signOut } from "@/lib/auth/client";
import { hasGateSessionMarker } from "@/lib/auth/gate-session-marker";
import { useCurrentUserState } from "@/lib/auth/use-current-user";
import { AVATARS, PHOTO_AVATAR, AvatarMark, ProfileAvatar } from "@/lib/avatars";
import { getMyBadges } from "@/lib/badge-stats";
import { BADGE_IDS, type BadgeId } from "@/lib/badges";
import { listLinks } from "@/lib/links";
import { toast } from "sonner";
import { appById } from "@/lib/bible/apps";
import type { Locale } from "@/lib/bible/books";
import { savePrefs, syncAccountPhoto } from "@/lib/cloud";
import { t } from "@/lib/i18n";
import { cleanHandle, profileIsComplete } from "@/lib/profile";
import { languagesLabel, themeLabel } from "@/components/settings-panel";
import { LinkedMethods } from "@/components/linked-methods";
import { useAppStore } from "@/lib/store";
import { getIsAdmin } from "@/lib/usage";
import { deleteMyAccount, exportMyData } from "@/lib/account";
import { clearMyGroupsCache } from "@/lib/groups-cache";
import { Button } from "@/components/ui/button";
import { ActionSheet } from "@/components/viewport-sheet";
import { Input } from "@/components/ui/input";
import { cn } from "@/lib/utils";

function snapshot() {
  const s = useAppStore.getState();
  return {
    locale: s.locale,
    copyLocale: s.copyLocale,
    appId: s.appId,
    translationId: s.translationId,
    preferNative: s.preferNative,
    copyFormat: s.copyFormat,
    citeBook: s.citeBook,
    citeSep: s.citeSep,
    booksCompact: s.booksCompact,
    theme: s.theme,
    activePlans: s.activePlans,
    planProgress: s.planProgress,
    avatarId: s.avatarId,
    avatarUrl: s.avatarUrl,
    handle: s.handle,
    firstName: s.firstName,
    lastName: s.lastName,
    profileEmail: s.profileEmail,
  };
}

function usePrefillProfile() {
  const firstName = useAppStore((s) => s.firstName);
  const lastName = useAppStore((s) => s.lastName);
  const profileEmail = useAppStore((s) => s.profileEmail);
  const avatarUrl = useAppStore((s) => s.avatarUrl);
  const avatarId = useAppStore((s) => s.avatarId);
  const setProfile = useAppStore((s) => s.setProfile);
  const { user } = useCurrentUserState();

  useEffect(() => {
    if (!user) return;
    const patch: Parameters<typeof setProfile>[0] = {};
    if (!profileEmail && user.primaryEmail) patch.profileEmail = user.primaryEmail;
    const photo = user.profileImageUrl;
    if (photo) patch.avatarUrl = photo;
    if (!firstName && user.displayName) {
      const [given, ...rest] = user.displayName.split(" ");
      patch.firstName = given ?? "";
      if (!lastName) patch.lastName = rest.join(" ");
    }
    if (Object.keys(patch).length) setProfile(patch);
    if (!photo && !avatarUrl) {
      void syncAccountPhoto().then((url) => {
        if (url) setProfile({ avatarUrl: url });
      });
    }
  }, [user, profileEmail, avatarUrl, firstName, lastName, setProfile]);
}

function SettingCards({ earned }: { earned: number }) {
  const locale = useAppStore((s) => s.locale);
  const copyLocale = useAppStore((s) => s.copyLocale);
  const theme = useAppStore((s) => s.theme);
  const appId = useAppStore((s) => s.appId);
  const app = appById(appId);
  const { user } = useCurrentUserState();
  const [friendCount, setFriendCount] = useState(0);
  const [incomingCount, setIncomingCount] = useState(0);

  useEffect(() => {
    if (!user) return;
    void listLinks()
      .then((data) => {
        setFriendCount(data.friends.length);
        setIncomingCount(data.incoming.length);
      })
      .catch(() => undefined);
  }, [user]);

  const cards = [
    ...(user
      ? [
          {
            to: "/profile/badges" as const,
            icon: Award,
            title: t(locale, "badges"),
            subtitle: `${earned} / ${BADGE_IDS.length}`,
          },
          {
            to: "/profile/friends" as const,
            icon: Users,
            title: t(locale, "friends"),
            subtitle: incomingCount
              ? `${incomingCount} ${t(locale, "linkIncoming").toLowerCase()}`
              : `${friendCount}`,
          },
          {
            to: "/profile/notifications" as const,
            icon: Bell,
            title: t(locale, "notifications"),
            subtitle: t(locale, "notifySetup"),
          },
        ]
      : []),
    {
      to: "/profile/theme" as const,
      icon: Sun,
      title: t(locale, "appearance"),
      subtitle: themeLabel(locale, theme),
    },
    {
      to: "/profile/bible" as const,
      icon: BookOpen,
      title: t(locale, "bibleApp"),
      subtitle: app?.names[locale] ?? t(locale, "bibleApp"),
    },
    {
      to: "/profile/language" as const,
      icon: Globe,
      title: t(locale, "language"),
      subtitle: languagesLabel(locale, copyLocale),
    },
    {
      to: "/profile/help" as const,
      icon: CircleHelp,
      title: t(locale, "aboutTitle"),
      subtitle: t(locale, "helpTitle"),
    },
  ];

  return (
    <ul className="ios-group" data-inset="icon">
      {cards.map((card) => {
        const Icon = card.icon;
        return (
          <li key={card.to}>
            <Link
              to={card.to}
              className="flex min-h-11 items-center gap-3 px-4 py-2.5 text-fg active:bg-fill"
            >
              <span className="flex size-7 shrink-0 items-center justify-center rounded-[8px] bg-accent text-accent-fg">
                <Icon className="size-4" />
              </span>
              <span className="min-w-0 flex-1 truncate text-[17px] leading-snug">{card.title}</span>
              <span className="max-w-[42%] truncate text-right text-[15px] text-muted">{card.subtitle}</span>
              <ChevronRight className="size-4 shrink-0 text-subtle" />
            </Link>
          </li>
        );
      })}
    </ul>
  );
}

async function shareProfile(handle: string, locale: Locale) {
  const url = `${window.location.origin}/u/${handle}`;
  try {
    if (typeof navigator.share === "function") {
      await navigator.share({ title: `@${handle}`, url });
      return;
    }
  } catch (error) {
    if (error instanceof Error && error.name === "AbortError") return;
  }
  try {
    await navigator.clipboard.writeText(url);
    const id = toast.success(t(locale, "profileCopied"));
    window.setTimeout(() => toast.dismiss(id), 2000);
  } catch {
    const id = toast.error(t(locale, "copyProfile"));
    window.setTimeout(() => toast.dismiss(id), 2000);
  }
}

export function ProfileView() {
  const locale = useAppStore((s) => s.locale);
  const avatarId = useAppStore((s) => s.avatarId);
  const avatarUrl = useAppStore((s) => s.avatarUrl);
  const handle = useAppStore((s) => s.handle);
  const firstName = useAppStore((s) => s.firstName);
  const lastName = useAppStore((s) => s.lastName);
  const { user, isPending } = useCurrentUserState();
  const [signingOut, setSigningOut] = useState(false);
  const [askDelete, setAskDelete] = useState(false);
  const [admin, setAdmin] = useState(false);
  const [badges, setBadges] = useState<BadgeId[]>([]);
  const gateSession = typeof window !== "undefined" ? hasGateSessionMarker() : false;
  usePrefillProfile();
  const name = [firstName, lastName].filter(Boolean).join(" ");

  useEffect(() => {
    if (!user) {
      setAdmin(false);
      setBadges([]);
      return;
    }
    void getIsAdmin()
      .then(setAdmin)
      .catch(() => setAdmin(false));
    void getMyBadges()
      .then(setBadges)
      .catch(() => setBadges([]));
  }, [user]);

  return (
    <div className="flex flex-col gap-8">
      {isPending ? (
        <div className="h-24 rounded-lg bg-surface" aria-hidden="true" />
      ) : user ? (
        <section className="flex flex-col items-center gap-3 pt-2">
          <ProfileAvatar id={avatarId} url={avatarUrl} className="size-24 bg-elevated" iconClassName="size-10" />
          {handle ? (
            <div className="flex items-center gap-0.5">
              <Link to="/u/$handle" params={{ handle }} className="text-[22px] font-semibold tracking-[-0.02em] text-fg">
                @{handle}
              </Link>
              <Button
                variant="ghost"
                size="icon"
                className="size-8 text-muted [&_svg]:size-3.5"
                aria-label={t(locale, "copyProfile")}
                onClick={() => void shareProfile(handle, locale)}
              >
                <Share2 />
              </Button>
            </div>
          ) : (
            <p className="text-sm text-muted">{t(locale, "handleMissing")}</p>
          )}
          {name ? <p className="text-sm text-muted">{name}</p> : null}
        </section>
      ) : (
        <section className="flex flex-col gap-3">
          <p className="text-pretty text-sm leading-relaxed text-muted">{t(locale, "profileGuest")}</p>
          <Button className="w-full" size="lg" asChild>
            <Link to="/login" search={{ create: false }}>
              {t(locale, "signIn")}
            </Link>
          </Button>
          <Button variant="secondary" className="w-full" size="lg" asChild>
            <Link to="/login" search={{ create: true }}>
              {t(locale, "createAccount")}
            </Link>
          </Button>
        </section>
      )}

      <SettingCards earned={badges.length} />

      {admin ? (
        <ul className="ios-group" data-inset="icon">
          <li>
            <Link to="/admin" className="flex min-h-11 items-center gap-3 px-4 py-2.5 text-fg active:bg-fill">
              <span className="flex size-7 shrink-0 items-center justify-center rounded-[8px] bg-accent text-accent-fg">
                <BarChart3 className="size-4" />
              </span>
              <span className="min-w-0 flex-1">
                <span className="block truncate text-[17px]">{t(locale, "adminTitle")}</span>
                <span className="block truncate text-[13px] text-muted">{t(locale, "adminHint")}</span>
              </span>
              <ChevronRight className="size-4 shrink-0 text-subtle" />
            </Link>
          </li>
        </ul>
      ) : null}

      {user && authEnabled && !gateSession ? (
        <ul className="ios-group">
          <li>
            <button
              type="button"
              className="flex min-h-11 w-full items-center px-4 text-left text-[17px] text-fg active:bg-fill disabled:opacity-40"
              disabled={signingOut}
              onClick={() => {
                setSigningOut(true);
                void signOut().catch(() => {
                  setSigningOut(false);
                  toast.error(t(locale, "signOutFailed"));
                });
              }}
            >
              {signingOut ? t(locale, "signingOut") : t(locale, "signOut")}
            </button>
          </li>
          <li>
            <button
              type="button"
              className="flex min-h-11 w-full items-center px-4 text-left text-[17px] text-fg active:bg-fill disabled:opacity-40"
              disabled={signingOut}
              onClick={() => {
                void exportMyData()
                  .then((data) => {
                    const blob = new Blob([JSON.stringify(data, null, 2)], { type: "application/json" });
                    const url = URL.createObjectURL(blob);
                    const a = document.createElement("a");
                    a.href = url;
                    a.download = "Katecheo-data.json";
                    a.click();
                    URL.revokeObjectURL(url);
                  })
                  .catch(() => toast.error(t(locale, "linkSendFail")));
              }}
            >
              {t(locale, "exportData")}
            </button>
          </li>
          <li>
            <button
              type="button"
              className="flex min-h-11 w-full items-center px-4 text-left text-[17px] text-danger active:bg-fill disabled:opacity-40"
              disabled={signingOut}
              onClick={() => setAskDelete(true)}
            >
              {t(locale, "deleteAccount")}
            </button>
          </li>
        </ul>
      ) : null}
      {askDelete ? (
        <ActionSheet
          message={t(locale, "deleteAccountAsk")}
          cancelLabel={t(locale, "linkCancel")}
          onClose={() => setAskDelete(false)}
          actions={[
            {
              label: t(locale, "deleteAccount"),
              destructive: true,
              onSelect: () => {
                setSigningOut(true);
                void deleteMyAccount()
                  .then((result) => {
                    if (!result?.ok) {
                      setSigningOut(false);
                      toast.error(t(locale, "linkSendFail"));
                      return;
                    }
                    clearMyGroupsCache();
                    useAppStore.getState().clearAccount();
                    toast.success(t(locale, "accountDeleted"));
                    void signOut().catch(() => {
                      setSigningOut(false);
                      toast.error(t(locale, "signOutFailed"));
                    });
                  })
                  .catch(() => {
                    setSigningOut(false);
                    toast.error(t(locale, "linkSendFail"));
                  });
              },
            },
          ]}
        />
      ) : null}
    </div>
  );
}

export function ProfileEdit() {
  const locale = useAppStore((s) => s.locale);
  const avatarId = useAppStore((s) => s.avatarId);
  const avatarUrl = useAppStore((s) => s.avatarUrl);
  const handle = useAppStore((s) => s.handle);
  const firstName = useAppStore((s) => s.firstName);
  const lastName = useAppStore((s) => s.lastName);
  const profileEmail = useAppStore((s) => s.profileEmail);
  const setProfile = useAppStore((s) => s.setProfile);
  const { user, isPending } = useCurrentUserState();
  const navigate = useNavigate();
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState<string | null>(null);
  usePrefillProfile();
  const photoUrl = avatarUrl || user?.profileImageUrl || "";

  async function onSave() {
    setError(null);
    if (!profileIsComplete({ handle, firstName, profileEmail })) {
      setError(t(locale, "completeProfileLead"));
      return;
    }
    setSaving(true);
    try {
      const result = await savePrefs({ data: snapshot() });
      if (result && "error" in result && result.error === "handle") {
        setError(t(locale, "handleTaken"));
        setSaving(false);
        return;
      }
      await navigate({ to: "/profile" });
    } catch {
      setError(t(locale, "accountError"));
      setSaving(false);
    }
  }

  if (isPending) {
    return <div className="h-40 rounded-md bg-surface" aria-hidden="true" />;
  }

  if (!user) {
    return <ProfileView />;
  }

  return (
    <div className="flex flex-col gap-8">
      <section className="space-y-3">
        <h2 className="ios-caption">{t(locale, "avatar")}</h2>
        <div className="grid grid-cols-6 gap-2">
          {photoUrl ? (
            <button
              type="button"
              onClick={() => setProfile({ avatarId: PHOTO_AVATAR, avatarUrl: photoUrl })}
              aria-pressed={avatarId === PHOTO_AVATAR}
              aria-label={t(locale, "avatarPhoto")}
              className={cn(
                "grid aspect-square place-items-center overflow-hidden rounded-full transition-colors",
                avatarId === PHOTO_AVATAR ? "ring-2 ring-accent ring-offset-2 ring-offset-bg" : "bg-surface",
              )}
            >
              <img src={photoUrl} alt="" referrerPolicy="no-referrer" className="size-full object-cover" />
            </button>
          ) : null}
          {AVATARS.map((item) => {
            const active = avatarId === item.id;
            return (
              <button
                key={item.id}
                type="button"
                onClick={() => setProfile({ avatarId: item.id })}
                aria-pressed={active}
                className={cn(
                  "grid aspect-square place-items-center rounded-full transition-colors",
                  active ? "bg-accent text-accent-fg" : "bg-surface text-fg shadow-[var(--shadow-border)]",
                )}
              >
                <AvatarMark id={item.id} className="bg-transparent" iconClassName="size-5" />
              </button>
            );
          })}
        </div>
      </section>

      <section className="space-y-3">
        <label className="block space-y-1.5">
          <span className="px-1 text-[13px] text-muted">{t(locale, "handle")}</span>
          <div className="relative">
            <span className="pointer-events-none absolute top-1/2 left-4 -translate-y-1/2 text-muted">@</span>
            <Input
              value={handle}
              onChange={(event) => setProfile({ handle: cleanHandle(event.target.value) })}
              className="pl-8"
              autoCapitalize="off"
              autoCorrect="off"
              spellCheck={false}
              maxLength={20}
              placeholder="joao"
              required
            />
          </div>
        </label>
        <div className="grid grid-cols-2 gap-3">
          <label className="block space-y-1.5">
            <span className="px-1 text-[13px] text-muted">{t(locale, "firstName")}</span>
            <Input
              value={firstName}
              onChange={(event) => setProfile({ firstName: event.target.value })}
              required
            />
          </label>
          <label className="block space-y-1.5">
            <span className="px-1 text-[13px] text-muted">{t(locale, "lastName")}</span>
            <Input value={lastName} onChange={(event) => setProfile({ lastName: event.target.value })} />
          </label>
        </div>
        <label className="block space-y-1.5">
          <span className="px-1 text-[13px] text-muted">{t(locale, "accountEmail")}</span>
          <Input
            type="email"
            value={profileEmail}
            onChange={(event) => setProfile({ profileEmail: event.target.value })}
            autoComplete="email"
            required
          />
        </label>
        {error ? <p className="text-[15px] text-danger">{error}</p> : null}
        <Button className="w-full" disabled={saving || !profileIsComplete({ handle, firstName, profileEmail })} onClick={() => void onSave()}>
          {saving ? t(locale, "accountWait") : t(locale, "saveProfile")}
        </Button>
      </section>
      <LinkedMethods />
    </div>
  );
}

export function ProfileHeaderActions() {
  const locale = useAppStore((s) => s.locale);
  const { user, isPending } = useCurrentUserState();
  if (isPending || !user) return null;

  return (
    <Button variant="ghost" size="icon" className="size-12 text-fg [&_svg]:size-6" aria-label={t(locale, "editProfile")} asChild>
      <Link to="/profile/edit">
        <Pencil />
      </Link>
    </Button>
  );
}
