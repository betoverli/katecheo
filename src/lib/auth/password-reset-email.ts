import type { PasswordResetLocale } from "./password-reset-code";

export type PasswordResetEmailCopy = {
  subject: string;
  text: string;
  html: string;
};

/**
 * Localized reset-code email. Brand name is always the single word "Katecheo"
 * in one uniform style (never split or restyled mid-word).
 */
export function buildPasswordResetEmail(
  locale: PasswordResetLocale,
  code: string,
): PasswordResetEmailCopy {
  const copy = COPY[locale] ?? COPY.en;
  const text = [
    copy.greeting,
    "",
    copy.lead,
    "",
    code,
    "",
    copy.expires,
    copy.ignore,
    "",
    "— Katecheo",
  ].join("\n");

  const html = `<!DOCTYPE html>
<html lang="${locale === "pt" ? "pt-BR" : locale}">
<head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"></head>
<body style="margin:0;padding:0;background:#f6f1ea;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,sans-serif;color:#2c241b;">
  <table role="presentation" width="100%" cellspacing="0" cellpadding="0" style="background:#f6f1ea;padding:32px 16px;">
    <tr><td align="center">
      <table role="presentation" width="100%" style="max-width:480px;background:#fffdf9;border-radius:16px;padding:32px 28px;border:1px solid #e8dfd3;">
        <tr><td style="font-size:22px;font-weight:700;letter-spacing:-0.02em;padding-bottom:8px;">Katecheo</td></tr>
        <tr><td style="font-size:15px;line-height:1.5;color:#5a4f43;padding-bottom:20px;">${escapeHtml(copy.lead)}</td></tr>
        <tr><td align="center" style="padding:8px 0 24px;">
          <div style="display:inline-block;font-size:32px;font-weight:700;letter-spacing:0.35em;padding:14px 22px 14px 28px;background:#f3ebe1;border-radius:12px;color:#2c241b;">${escapeHtml(code)}</div>
        </td></tr>
        <tr><td style="font-size:14px;line-height:1.5;color:#5a4f43;padding-bottom:8px;">${escapeHtml(copy.expires)}</td></tr>
        <tr><td style="font-size:13px;line-height:1.5;color:#8a7d6e;">${escapeHtml(copy.ignore)}</td></tr>
      </table>
    </td></tr>
  </table>
</body>
</html>`;

  return { subject: copy.subject, text, html };
}

const COPY: Record<
  PasswordResetLocale,
  { subject: string; greeting: string; lead: string; expires: string; ignore: string }
> = {
  pt: {
    subject: "Seu código Katecheo",
    greeting: "Olá,",
    lead: "Use este código no app Katecheo para redefinir sua senha:",
    expires: "O código expira em 15 minutos.",
    ignore: "Se você não pediu isso, pode ignorar este email.",
  },
  en: {
    subject: "Your Katecheo code",
    greeting: "Hi,",
    lead: "Use this code in the Katecheo app to reset your password:",
    expires: "This code expires in 15 minutes.",
    ignore: "If you did not request this, you can ignore this email.",
  },
  es: {
    subject: "Tu código de Katecheo",
    greeting: "Hola,",
    lead: "Usa este código en la app Katecheo para restablecer tu contraseña:",
    expires: "El código caduca en 15 minutos.",
    ignore: "Si no pediste esto, puedes ignorar este correo.",
  },
};

function escapeHtml(value: string): string {
  return value
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;");
}
