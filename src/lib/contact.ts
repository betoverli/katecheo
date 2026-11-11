import type { Locale } from "@/lib/bible/books";
import { CONTACT_EMAIL } from "@/lib/app-store";

type Copy = {
  title: string;
  lead: string;
  emailLabel: string;
  emailHint: string;
  sections: { title: string; body: string }[];
};

const COPY: Record<Locale, Copy> = {
  pt: {
    title: "Contato e suporte",
    lead: "Suporte para o app Katecheo no iPhone e para as ferramentas públicas de IA.",
    emailLabel: "E-mail",
    emailHint: "Forma principal de contato — escreva para",
    sections: [
      {
        title: "GitHub",
        body: "Bugs e pedidos de recurso também podem ir para o repositório: github.com/betoverli/katecheo.",
      },
      {
        title: "Privacidade e conta",
        body: `Para pedidos sobre dados pessoais (LGPD), veja a Política de Privacidade ou escreva para ${CONTACT_EMAIL}. Exclusão de conta e exportação de dados ficam no app iOS (Perfil), quando a conta estiver ativa.`,
      },
      {
        title: "App Store",
        body: "Esta página serve como URL de suporte do Katecheo na App Store. O produto de uso diário é o app nativo para iPhone; este site é a página de marketing e as APIs.",
      },
    ],
  },
  en: {
    title: "Contact & support",
    lead: "Support for the Katecheo iPhone app and the public AI tools.",
    emailLabel: "Email",
    emailHint: "Primary contact — write to",
    sections: [
      {
        title: "GitHub",
        body: "Bugs and feature requests can also go to the repository: github.com/betoverli/katecheo.",
      },
      {
        title: "Privacy and account",
        body: `For personal-data requests, see the Privacy Policy or email ${CONTACT_EMAIL}. Account deletion and data export live in the iOS app (Profile) once your account is active.`,
      },
      {
        title: "App Store",
        body: "This page is Katecheo’s App Store support URL. Day-to-day product use is the native iPhone app; this site is marketing plus APIs.",
      },
    ],
  },
  es: {
    title: "Contacto y soporte",
    lead: "Soporte para la app Katecheo en iPhone y para las herramientas públicas de IA.",
    emailLabel: "Correo",
    emailHint: "Forma principal de contacto — escribe a",
    sections: [
      {
        title: "GitHub",
        body: "Errores y peticiones también pueden ir al repositorio: github.com/betoverli/katecheo.",
      },
      {
        title: "Privacidad y cuenta",
        body: `Para solicitudes de datos personales, consulta la Política de Privacidad o escribe a ${CONTACT_EMAIL}. La eliminación de cuenta y la exportación de datos están en la app iOS (Perfil) cuando la cuenta esté activa.`,
      },
      {
        title: "App Store",
        body: "Esta página es la URL de soporte de Katecheo en App Store. El uso diario del producto es la app nativa para iPhone; este sitio es marketing y APIs.",
      },
    ],
  },
};

export function contactCopy(locale: Locale): Copy {
  return COPY[locale] ?? COPY.pt;
}
