/**
 * Thin Resend HTTP client (no SDK). Server-only — uses RESEND_API_KEY.
 */
export type ResendEmailPayload = {
  from: string;
  to: string;
  subject: string;
  html: string;
  text: string;
};

export type ResendSendResult =
  | { ok: true; id?: string }
  | { ok: false; error: "missing_api_key" | "missing_from" | "http_error" | "network_error"; detail?: string };

export async function sendResendEmail(payload: ResendEmailPayload): Promise<ResendSendResult> {
  const apiKey = process.env.RESEND_API_KEY?.trim();
  if (!apiKey) {
    console.error("[resend] RESEND_API_KEY is missing — cannot send email");
    return { ok: false, error: "missing_api_key" };
  }
  const from = (payload.from || process.env.EMAIL_FROM || "").trim();
  if (!from) {
    console.error("[resend] EMAIL_FROM is missing — cannot send email");
    return { ok: false, error: "missing_from" };
  }

  try {
    const res = await fetch("https://api.resend.com/emails", {
      method: "POST",
      headers: {
        Authorization: `Bearer ${apiKey}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        from,
        to: [payload.to],
        subject: payload.subject,
        html: payload.html,
        text: payload.text,
      }),
    });
    if (!res.ok) {
      const body = await res.text().catch(() => "");
      console.error("[resend] send failed", res.status, body.slice(0, 500));
      return { ok: false, error: "http_error", detail: `status_${res.status}` };
    }
    const json = (await res.json().catch(() => null)) as { id?: string } | null;
    return { ok: true, id: typeof json?.id === "string" ? json.id : undefined };
  } catch (error) {
    console.error("[resend] network error", error);
    return { ok: false, error: "network_error" };
  }
}
