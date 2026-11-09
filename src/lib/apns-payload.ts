export type ApnsAlert = {
  title: string;
  body: string;
  href: string;
};

export type ApnsSilentHint = {
  /** e.g. themes_updated | reading_updated */
  type: string;
  href?: string;
};

/** APNs alert body. `href` is read by the iOS app when the person taps the alert. */
export function apnsPayload(alert: ApnsAlert) {
  return {
    aps: {
      alert: {
        title: alert.title.slice(0, 120),
        body: alert.body.slice(0, 240),
      },
      sound: "default",
    },
    href: alert.href.startsWith("/") && !alert.href.startsWith("//") ? alert.href.slice(0, 200) : "/app",
  };
}

/** Background/silent push — wakes the app without showing a banner. */
export function apnsSilentPayload(hint: ApnsSilentHint) {
  return {
    aps: {
      "content-available": 1,
    },
    type: hint.type.slice(0, 64),
    href:
      hint.href && hint.href.startsWith("/") && !hint.href.startsWith("//")
        ? hint.href.slice(0, 200)
        : undefined,
  };
}
