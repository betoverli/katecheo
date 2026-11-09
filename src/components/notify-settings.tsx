import { useEffect, useState } from "react";
import { toast } from "sonner";
import type { Locale } from "@/lib/bible/books";
import { useCurrentUserState } from "@/lib/auth/use-current-user";
import { t } from "@/lib/i18n";
import { getNotifyPrefs, saveNotifyPrefs, type NotifyPrefs } from "@/lib/notify";
import { disablePush, enablePush, isStandalone, pushSupported } from "@/lib/push-client";
import { isNativeApp } from "@/lib/native/runtime";
import { isAppleUa } from "@/lib/platform";
import { useAppStore } from "@/lib/store";
import { cn } from "@/lib/utils";

function nativePushEnabled() {
  try {
    return localStorage.getItem("Katecheo.apns") === "1";
  } catch {
    return false;
  }
}

function Toggle({
  on,
  title,
  subtitle,
  onClick,
  disabled,
}: {
  on: boolean;
  title: string;
  subtitle?: string;
  onClick: () => void;
  disabled?: boolean;
}) {
  return (
    <button
      type="button"
      onClick={onClick}
      disabled={disabled}
      aria-pressed={on}
      className="flex min-h-11 w-full items-center justify-between gap-3 rounded-md bg-surface px-4 py-3 text-left text-fg shadow-[var(--shadow-border)] transition-[background-color,transform] duration-150 ease-out hover:bg-elevated active:scale-[0.99] disabled:opacity-40"
    >
      <span className="min-w-0">
        <span className="block text-sm font-medium">{title}</span>
        {subtitle ? <span className="mt-0.5 block text-xs text-muted">{subtitle}</span> : null}
      </span>
      <span
        className={cn("relative h-6 w-10 shrink-0 rounded-full p-0.5 transition-colors duration-150", on ? "bg-accent" : "bg-elevated")}
        aria-hidden
      >
        <span
          className={cn(
            "block size-5 rounded-full bg-bg transition-transform duration-150",
            on ? "translate-x-4" : "translate-x-0",
          )}
        />
      </span>
    </button>
  );
}

export function NotifySettings() {
  const locale = useAppStore((s) => s.locale);
  const { user } = useCurrentUserState();
  const [prefs, setPrefs] = useState<NotifyPrefs>({ reading: true, friends: true, shares: true, groups: true });
  const [deviceOn, setDeviceOn] = useState(false);
  const [busy, setBusy] = useState(false);
  const [native, setNative] = useState(false);
  const apple = isAppleUa();
  const standalone = isStandalone();
  const supported = native || pushSupported();
  const needsInstall = apple && !standalone && !native;

  useEffect(() => {
    setNative(isNativeApp());
  }, []);

  useEffect(() => {
    if (!user) return;
    void getNotifyPrefs()
      .then((data) => {
        setPrefs({ reading: data.reading, friends: data.friends, shares: data.shares, groups: data.groups });
        setDeviceOn(native ? nativePushEnabled() : data.subscribed);
      })
      .catch(() => undefined);
  }, [user, native]);

  async function toggleDevice() {
    if (busy || needsInstall || !supported) return;
    setBusy(true);
    try {
      if (deviceOn) {
        await disablePush();
        setDeviceOn(false);
        return;
      }
      const result = await enablePush();
      if (!result.ok) {
        toast(t(locale, result.error === "denied" ? "notifyDenied" : "notifyUnsupported"));
        return;
      }
      setDeviceOn(true);
    } finally {
      setBusy(false);
    }
  }

  function patch(key: keyof NotifyPrefs) {
    const next = { ...prefs, [key]: !prefs[key] };
    setPrefs(next);
    void saveNotifyPrefs({ data: { [key]: next[key] } }).catch(() => undefined);
  }

  if (!user) {
    return <p className="text-sm text-muted">{t(locale, "notifyLogin")}</p>;
  }

  return (
    <div className="flex flex-col gap-8">
      <section className="space-y-3">
        <h2 className="text-xs font-medium tracking-wide text-muted uppercase">{t(locale, "notifyDevice")}</h2>
        {needsInstall ? <p className="text-sm text-muted">{t(locale, "notifyInstall")}</p> : null}
        {native ? <p className="text-sm text-muted">{t(locale, "notifyNativeHint")}</p> : null}
        {!supported ? <p className="text-sm text-muted">{t(locale, "notifyUnsupported")}</p> : null}
        <Toggle
          on={deviceOn}
          title={t(locale, "notifyThisDevice")}
          subtitle={t(locale, "notifyThisDeviceHint")}
          onClick={() => void toggleDevice()}
          disabled={busy || needsInstall || !supported}
        />
      </section>
      <section className="space-y-3">
        <h2 className="text-xs font-medium tracking-wide text-muted uppercase">{t(locale, "notifyKinds")}</h2>
        <Toggle
          on={prefs.reading}
          title={t(locale, "notifyReading")}
          subtitle={t(locale, "notifyReadingHint")}
          onClick={() => patch("reading")}
        />
        <Toggle
          on={prefs.friends}
          title={t(locale, "notifyFriends")}
          subtitle={t(locale, "notifyFriendsHint")}
          onClick={() => patch("friends")}
        />
        <Toggle
          on={prefs.shares}
          title={t(locale, "notifyShares")}
          subtitle={t(locale, "notifySharesHint")}
          onClick={() => patch("shares")}
        />
        <Toggle
          on={prefs.groups}
          title={t(locale, "notifyGroups")}
          subtitle={t(locale, "notifyGroupsHint")}
          onClick={() => patch("groups")}
        />
      </section>
    </div>
  );
}

export function notifySummary(locale: Locale, prefs: NotifyPrefs) {
  const on = [
    prefs.reading ? t(locale, "notifyReading") : "",
    prefs.friends ? t(locale, "notifyFriends") : "",
    prefs.shares ? t(locale, "notifyShares") : "",
    prefs.groups ? t(locale, "notifyGroups") : "",
  ].filter(Boolean);
  return on.length ? on.join(" · ") : t(locale, "notifyOff");
}
